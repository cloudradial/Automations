# =====================================================================
#  Secure Score -> CloudRadial Assessment (deterministic, JSON assessment API)
#  Run input: {"companyId":123,"tenantId":"<client Graph tenant GUID>","assessmentTitle":"Microsoft Secure Score","mode":"apply"}
#    companyId  - CloudRadial company the assessment is created under (required)
#    tenantId   - the CLIENT's Entra tenant id to pull Secure Score from (required)
#    mode       - "apply" (default) writes; "plan" previews only
#  Keeps one assessment per client ("<companyName> Secure Score Assessment"), one question per control keyed on
#  the control id, refreshed in place on every run, and adds a dated run the portal lists.
#  Secrets (runner Key Vault): CloudRadial-BaseUrl / -PublicKey / -PrivateKey,
#    and M365-ClientID / M365-ClientSecret (an Entra app with
#    SecurityEvents.Read.All application permission, consented in the client tenant).
# =====================================================================
$ErrorActionPreference = 'Stop'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

function Get-Secret { param([string]$Name) Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue }
function Get-Prop { param($o,$n) if($null -eq $o){return $null}; if($o -is [System.Collections.IDictionary]){ if($o.Contains($n)){return $o[$n]}; return $null }; $p=$o.PSObject.Properties[$n]; if($p){return $p.Value}; return $null }

# ---- run input ----
$in = Get-NodeInput
$t = Get-Prop $in 'trigger'; if ($null -ne $t) { $in = $t }
if ($in -is [string]) { $s = $in.Trim(); if ($s.StartsWith('{')) { $in = $s | ConvertFrom-Json } }
$companyId = Get-Prop $in 'companyId'
$tenantId  = Get-Prop $in 'tenantId'
$title     = [string](Get-Prop $in 'assessmentTitle'); if ([string]::IsNullOrWhiteSpace($title)) { $title = 'Microsoft Secure Score' }
$mode      = [string](Get-Prop $in 'mode'); if ([string]::IsNullOrWhiteSpace($mode)) { $mode = 'apply' }
if ([string]::IsNullOrWhiteSpace([string]$tenantId) -or [string]$tenantId -match '^0{8}-') { Set-NodeOutput ([ordered]@{ status = 'skipped'; message = 'Microsoft 365 is not connected for this client (no tenant on the portal company), so the Secure Score section was skipped.'; plannerCards = @() }); return }
if (-not $companyId -or [string]::IsNullOrWhiteSpace([string]$tenantId)) {
    $m = 'Need companyId (CloudRadial) and tenantId (the client Entra tenant). e.g. {"companyId":123,"tenantId":"00000000-0000-0000-0000-000000000000"}.'
    Set-NodeOutput @{ status = 'error'; message = $m }; throw $m
}

# ---- secrets ----
$crBaseRaw = Get-Secret 'CloudRadial-BaseUrl'; $pub = Get-Secret 'CloudRadial-PublicKey'; $prv = Get-Secret 'CloudRadial-PrivateKey'
$appId = Get-Secret 'M365-ClientID'; $appSecret = Get-Secret 'M365-ClientSecret'
$missing = foreach ($pair in @(
    @{ n='CloudRadial-BaseUrl'; v=$crBaseRaw }, @{ n='CloudRadial-PublicKey'; v=$pub }, @{ n='CloudRadial-PrivateKey'; v=$prv },
    @{ n='M365-ClientID'; v=$appId }, @{ n='M365-ClientSecret'; v=$appSecret }
)) { if ([string]::IsNullOrWhiteSpace([string]$pair.v)) { $pair.n } }
if (@($missing).Count -gt 0) { $m = "Add these runner Key Vault secret(s) and re-run: $($missing -join ', ')."; Set-NodeOutput @{ status='error'; message=$m }; throw $m }
$crBase = ([string]$crBaseRaw).TrimEnd('/')
$crAuth = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$pub`:$prv"))

# ---- CloudRadial API (assessments from JSON, no workbook upload) ----
# @shared:cloudradial.ps1
$null = Connect-Cr
function Invoke-Cr { param([string]$Method, [string]$Path, [object]$Body) Invoke-CrApi -Path $Path -Method $Method -Body $Body }

# ---- Microsoft Graph: token + Secure Score ----
$tokUri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
$tok = (Invoke-RestMethod -Uri $tokUri -Method Post -ContentType 'application/x-www-form-urlencoded' -Body @{ grant_type='client_credentials'; client_id=$appId; client_secret=$appSecret; scope='https://graph.microsoft.com/.default' }).access_token
if (-not $tok) { throw 'Could not get a Microsoft Graph token - check the app id/secret and that the app is consented in the client tenant.' }
$gh = @{ Authorization = "Bearer $tok" }
# What the token holds: the app id and its application permissions (never the token itself), so a 403 can say what is missing.
function Get-TokenInfo { param([string]$Jwt)
    $info = [ordered]@{ appId = ''; roles = @() }
    try {
        $p = $Jwt.Split('.')[1].Replace('-', '+').Replace('_', '/'); while ($p.Length % 4) { $p += '=' }
        $c = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
        $info.appId = [string](Get-Prop $c 'appid'); $info.roles = @(Get-Prop $c 'roles' | Where-Object { $_ })
    } catch { }
    return $info
}
try { $score = (Invoke-RestMethod -Uri 'https://graph.microsoft.com/v1.0/security/secureScores?$top=1' -Headers $gh).value | Select-Object -First 1 }
catch {
    $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch { }
    if ($code -ne 403 -and $code -ne 401) { throw }
    $ti = Get-TokenInfo $tok
    $has = if (@($ti.roles).Count) { (@($ti.roles) | Sort-Object) -join ', ' } else { 'none' }
    $m = "Microsoft Graph refused to read Secure Score (HTTP $code). The app registration $($ti.appId) has these application permissions in tenant $($tenantId): $has. Add SecurityEvents.Read.All to it as an Application permission (not Delegated) and grant admin consent in this tenant. Its existing permissions stay as they are. Nothing was created."
    Set-NodeOutput @{ status = 'error'; message = $m; appId = $ti.appId; grantedRoles = @($ti.roles) }; throw $m
}
if (-not $score) { throw 'No Secure Score data for this tenant (is Microsoft Secure Score enabled, and does the app have SecurityEvents.Read.All?).' }
$tenantCur = [double]$score.currentScore; $tenantMax = [double]$score.maxScore
$lookup = @{}; foreach ($cs in @($score.controlScores)) { $lookup[[string]$cs.controlName] = $cs.score }
$profiles = @(); $uri = 'https://graph.microsoft.com/v1.0/security/secureScoreControlProfiles'
while ($uri) { $r = Invoke-RestMethod -Uri $uri -Headers $gh; $profiles += @($r.value); $uri = Get-Prop $r '@odata.nextLink' }
$active = @($profiles | Where-Object { -not $_.deprecated })
if ($active.Count -eq 0) { throw 'No active Secure Score control profiles returned.' }

function ConvertTo-PlainText { param([string]$Html)
    if ([string]::IsNullOrWhiteSpace($Html)) { return '' }
    $t = $Html -replace '(?i)<br\s*/?>', "`n" -replace '(?i)</p\s*>', "`n" -replace '(?i)<li[^>]*>', "`n• " -replace '(?i)</(li|ul|ol|div|h\d)\s*>', "`n"
    $t = $t -replace '<[^>]+>', ''
    $t = [System.Net.WebUtility]::HtmlDecode([System.Net.WebUtility]::HtmlDecode($t))
    $t = $t -replace " ", ' ' -replace '[ \t]+', ' ' -replace ' *\r?\n *', "`n" -replace "(`n){2,}", "`n"
    return $t.Trim()
}
function Get-ShortText { param([string]$Text, [int]$Max = 240)
    $first = (($Text -split "`n") | ForEach-Object { ($_ -replace '^\s*(•|\d+\.)\s*', '').Trim() } | Where-Object { $_.Length -ge 25 } | Select-Object -First 1)
    if (-not $first) { $first = ($Text -replace "\s*`n\s*", ' ').Trim() }
    if ($first.Length -le $Max) { return $first }
    $cut = $first.Substring(0, $Max); $dot = $cut.LastIndexOf('. ')
    if ($dot -gt [int]($Max * 0.5)) { return $cut.Substring(0, $dot + 1) }
    $sp = $cut.LastIndexOf(' '); if ($sp -gt 0) { $cut = $cut.Substring(0, $sp) }
    return ($cut.TrimEnd(',', ';', ':', ' ') + '…')
}
# ---- one question per control, keyed on the control id so a rerun updates the same question ----
$catOrder = @{ 'Identity'=1; 'Device'=2; 'Apps'=3; 'Data'=4; 'Infrastructure'=5 }
$sorted = $active | Sort-Object @(
    @{ Expression = { $k=[string]$_.controlCategory; if ($catOrder.ContainsKey($k)) { $catOrder[$k] } else { 99 } } },
    @{ Expression = { $_.rank } }
)
$today = Get-Date -Format 'yyyy-MM-dd'
$questions = New-Object System.Collections.ArrayList
$order = 0; $compliantCount = 0
foreach ($c in $sorted) {
    $order += 10
    $cc = [string]$c.controlCategory
    $cat = switch ($cc) { 'Account' { 'Identity' } 'Identity' { 'Identity' } 'Data' { 'Data' } 'Device' { 'Device' } 'Apps' { 'Apps' } 'Infrastructure' { 'Infrastructure' } default { $cc } }
    $cur = if ($lookup.ContainsKey([string]$c.id)) { [double]$lookup[[string]$c.id] } else { 0 }
    $max = if ($c.maxScore) { [double]$c.maxScore } else { 0 }
    $isCompliant = ($cur -ge $max) -and ($max -gt 0)
    if ($isCompliant) { $compliantCount++ }
    $pct = if ($tenantMax -gt 0) { [math]::Round(($max / $tenantMax) * 100, 2) } else { 0 }
    $rem = ConvertTo-PlainText ([string]$c.remediation)
    $null = $questions.Add([ordered]@{
        updateKey = [string]$c.id; category = $cat; label = ([System.Net.WebUtility]::HtmlDecode([string]$c.title)).Trim(); order = $order
        explanation = "Service: $($c.service) | Score impact: $pct% | Points: $cur / $max"
        evaluationInfo = 'Review this control in the Microsoft 365 Defender portal under Secure Score.'
        remediationInfo = $rem; remediationLineItem = (Get-ShortText $rem 240)
        value = $(if ($isCompliant) { 2 } else { -2 }); isFlagged = (-not $isCompliant)
        privateNotes = "Microsoft Secure Score - $($c.service): $cur of $max points on $today."
    })
}
$textSample = @($questions | Where-Object { $_.remediationInfo } | Select-Object -First 3 | ForEach-Object { [ordered]@{ title = $_.label; short = $_.remediationLineItem; full = $_.remediationInfo.Substring(0, [math]::Min(600, $_.remediationInfo.Length)) } })

$catCards = @()
if ($mode -eq 'apply') {
    $groups = $sorted | Group-Object { $k = [string]$_.controlCategory; if ($k -eq 'Account') { 'Identity' } else { $k } }
    $existingCards = @(); try { $existingCards = @(Get-CrAll "/v2/odata/product?`$filter=companyId eq $companyId") } catch { }
    $asOf = (Get-Date).ToString('d MMM yyyy')
    foreach ($g in $groups) {
        $catName = [string]$g.Name; if (-not $catName) { continue }
        $gaps = @(); $got = 0.0; $possible = 0.0
        foreach ($c in $g.Group) {
            $cur = if ($lookup.ContainsKey([string]$c.id)) { [double]$lookup[[string]$c.id] } else { 0 }
            $max = if ($c.maxScore) { [double]$c.maxScore } else { 0 }
            $got += $cur; $possible += $max
            if (-not (($cur -ge $max) -and ($max -gt 0))) { $gaps += [pscustomobject]@{ title = [string]$c.title; gain = ($max - $cur) } }
        }
        if ($gaps.Count -eq 0) { continue }
        $top = @($gaps | Sort-Object gain -Descending | Select-Object -First 5)
        $subject = "Microsoft 365 $catName security"
        $pctC = if ($possible -gt 0) { [math]::Round(100 * $got / $possible, 0) } else { 0 }
        $summary = if ($gaps.Count) { "Your $catName security is at $pctC%. We found $($gaps.Count) improvement$(if ($gaps.Count -ne 1) { 's' }) worth making." } else { "Your $catName security is in great shape: every setting Microsoft checks is in place." }
        $items = ($top | ForEach-Object { '<li>' + [System.Net.WebUtility]::HtmlEncode($_.title) + ' (+' + [math]::Round($_.gain, 1) + ' points)</li>' }) -join ''
        $pctDone = if ($possible -gt 0) { [math]::Round(100 * $got / $possible, 0) } else { 0 }
        $body = "<div style='background:linear-gradient(135deg,#001F54 0%,#09507B 55%,#1282A2 100%);color:#fff;padding:14px 18px;border-radius:12px;border-left:6px solid #B3C9D5;margin:0 0 10px'><div style='font-size:18px;font-weight:600'><i class='fal fa-shield-halved' style='color:#B3C9D5'></i>&nbsp; Your $catName security is at $pctDone%</div><div style='font-size:13px;opacity:.9;margin-top:4px'>Microsoft checks $($g.Count) $catName settings in your Microsoft 365. $(if ($gaps.Count) { "$($gaps.Count) still need attention." } else { 'All of them are in place.' }) Checked $asOf.</div></div><div style='display:flex;align-items:center;gap:10px;margin:12px 0 6px;padding:8px 12px;background:#E8F3F7;border:1px solid #B3D7E3;border-left:4px solid #B3C9D5;border-radius:10px'><span style='background:#001F54;color:#B3C9D5;width:28px;height:28px;border-radius:8px;display:inline-flex;align-items:center;justify-content:center'><i class='fal fa-list-check'></i></span><span style='font-size:15px;font-weight:600;color:#001F54'>Where we would start</span></div><ul style='margin:6px 0 0 18px;color:#001F54'>$items</ul><p style='margin:10px 0 0;font-size:13px;color:#001F54'><b>What we suggest:</b> these are the changes that raise your score the most. We will go through each one with you, make sure it will not disrupt anyone, and schedule the work. Reply on this card with any questions.</p>"
        $ex = $existingCards | Where-Object { [string]$_.subject -eq $subject } | Select-Object -First 1
        try {
            if ($ex) { $ops = @(@{ op = 'replace'; path = '/summary'; value = $summary }, @{ op = 'replace'; path = '/body'; value = $body }); $null = Invoke-RestMethod -Uri "$crBase/v2/product/$($ex.productId)" -Method PATCH -Headers @{ Authorization = $crAuth; Accept = 'application/json' } -ContentType 'application/json-patch+json' -Body (ConvertTo-Json -InputObject $ops -Depth 5); $catCards += "Updated: $($subject)" }
            else { $null = Invoke-Cr -Method POST -Path '/v2/product' -Body @{ companyId = [int]$companyId; subject = $subject; summary = $summary; body = $body; category = 'Security'; productCategoryId = 6; isClientVisible = $true }; $catCards += "Created: $($subject)" }
        } catch { $catCards += "Could not save $($subject): $($_.Exception.Message)" }
    }
}
$coName = [string](Get-Prop $in 'companyName'); if (-not $coName) { $coName = 'Client' }
$titleFinal = "$coName Secure Score Assessment"
$summary = "$($questions.Count) controls ($compliantCount compliant). Tenant score $tenantCur / $tenantMax."
$facts = [ordered]@{ controls = $questions.Count; compliant = $compliantCount; tenantScore = "$tenantCur / $tenantMax" }
function Send-ReviewOut { param($o) $r = [ordered]@{ plannerCards = $catCards; textSample = $textSample }; foreach ($k in $o.Keys) { $r[$k] = $o[$k] }; foreach ($k in $facts.Keys) { $r[$k] = $facts[$k] }; Set-NodeOutput $r }

if ($mode -eq 'plan') {
    $p = Sync-CrAssessment -CompanyId ([int]$companyId) -Title $titleFinal -Questions $questions.ToArray() -Preview
    $what = if ($p.action -eq 'would-update') { "refresh '$titleFinal' (assessmentId $($p.assessmentId)) in place" } else { "create '$titleFinal'" }
    Send-ReviewOut ([ordered]@{ status = 'plan'; message = "DRY RUN - would $what with $($questions.Count) questions and add today's run. $summary"; assessmentId = [int]$p.assessmentId })
    return
}
$pctScore = if ([double]$tenantMax -gt 0) { [math]::Round(100 * [double]$tenantCur / [double]$tenantMax, 0) } else { 0 }
$assessDescription = "Microsoft Secure Score review for $coName from Microsoft 365, refreshed by the Microsoft Tenant Review. Tenant score on $(Get-Date -Format 'd MMMM yyyy'): $tenantCur of $tenantMax points ($pctScore%), with $compliantCount of $($questions.Count) security controls fully in place. Each question is one Microsoft Secure Score control, grouped by Identity, Device, Apps and Data. Compliant means Microsoft reports the control as fully implemented; Not compliant means points are still available. The score impact on each question shows how much fixing it raises the overall score."
$assessRecommendations = "Start with the highest-impact gaps in Identity (multi-factor authentication, admin account protection and legacy sign-in blocking), then work through Device, Apps and Data. The Microsoft 365 security cards on the Planner list the top fixes for each category. Run the Microsoft Tenant Review again after changes to update the score."
try {
    # The portal names a run "<assessment> - M/d/yy". A second review on the same day gets " (2)", " (3)" and so on,
    # so every review keeps its own snapshot.
    $runBase = "$titleFinal - $((Get-Date).ToString('M/d/yy', [Globalization.CultureInfo]::InvariantCulture))"
    $taken = @(@(Get-CrAll "/v2/odata/assessment?`$filter=$([uri]::EscapeDataString("companyId eq $companyId"))") | Where-Object { -not (Get-Prop $_ 'isDeleted') } | ForEach-Object { ([string](Get-Prop $_ 'title')).Trim().ToLowerInvariant() })
    $runName = $runBase; $n = 1
    while ($taken -contains $runName.ToLowerInvariant()) { $n++; $runName = "$runBase ($n)" }
    $r = Sync-CrAssessment -CompanyId ([int]$companyId) -Title $titleFinal -Questions $questions.ToArray() -Category 'Microsoft 365 Security' -Description $assessDescription -Recommendations $assessRecommendations -Visibility 2 -RemoveMissing -RunName $runName
}
catch {
    $m = "Couldn't write the Secure Score assessment for companyId ${companyId}: $($_.Exception.Message)"
    Send-ReviewOut ([ordered]@{ status = 'error'; message = $m }); throw $m
}
$did = if ($r.action -eq 'created') { 'Created' } else { 'Refreshed' }
$sc = if ($r.scores) { " Assessment score $(Get-Prop $r.scores 'totalScore') of $(Get-Prop $r.scores 'maxScore')." } else { '' }
Send-ReviewOut ([ordered]@{ status = 'created'; message = "$did assessment '$titleFinal' (assessmentId $($r.assessmentId)) with $($questions.Count) questions and added the run '$runName' (assessmentId $($r.runId)). $summary$sc"; assessmentId = [int]$r.assessmentId; runId = [int]$r.runId; assessmentAction = $r.action; runName = $runName })
