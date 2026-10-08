# =====================================================================
#  Endpoint LifeCycle Manager - no-AI workflow step
#  Reviews every managed computer per company against hardware refresh
#  standards and keeps one Planner card per refresh category (Replace,
#  Plan replacement, Upgrade in place, Retain, Needs data, Human review,
#  Virtual machines). Same rules as the Endpoint LifeCycle Manager agent,
#  but deterministic: no model, no turn limit, any AI provider.
#  Run input (all optional): {"companyIds": "1,4,7", "mode": "plan"}
#  Secrets (runner Key Vault): CloudRadial-BaseUrl, CloudRadial-PublicKey,
#  CloudRadial-PrivateKey.
# =====================================================================
$ErrorActionPreference = 'Stop'
function Get-Prop { param($o, $n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }

# ---- run input ----
$in = $null; try { $in = Get-NodeInput } catch { }
$t = Get-Prop $in 'trigger'; if ($null -ne $t) { $in = $t }
if ($in -is [string]) { $in = $(if ($in.Trim().StartsWith('{')) { $in | ConvertFrom-Json } else { $null }) }
$CompanyIds = @(@(Get-Prop $in 'companyIds') | ForEach-Object { ([string]$_) -split '[,;\s]+' } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } | Select-Object -Unique)
$single = Get-Prop $in 'companyId'; if ($single -and [string]$single -match '^\d+$') { $CompanyIds = @([int]$single) }
$Mode = ([string](Get-Prop $in 'mode')).Trim().ToLowerInvariant(); if ($Mode -ne 'plan') { $Mode = 'apply' }
$Apply = $Mode -eq 'apply'
$PlannerCategory = [string](Get-Prop $in 'plannerCategory'); if (-not $PlannerCategory) { $PlannerCategory = 'Efficiency' }
$ProductCategoryId = 7; [int]::TryParse([string](Get-Prop $in 'plannerProductCategoryId'), [ref]$ProductCategoryId) | Out-Null; if ($ProductCategoryId -le 0) { $ProductCategoryId = 7 }
$CloseEmpty = -not ([string](Get-Prop $in 'closeEmptyCards') -match '^(false|no|0)$')
$OnRoadmap = [string](Get-Prop $in 'scheduleOnRoadmap') -match '^(true|yes|1)$'

# ---- secrets ----
function Get-Secret { param([string]$Name) Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue }
$BaseUrl = Get-Secret 'CloudRadial-BaseUrl'; $PublicKey = Get-Secret 'CloudRadial-PublicKey'; $PrivateKey = Get-Secret 'CloudRadial-PrivateKey'
$missing = @(@{ n = 'CloudRadial-BaseUrl'; v = $BaseUrl }, @{ n = 'CloudRadial-PublicKey'; v = $PublicKey }, @{ n = 'CloudRadial-PrivateKey'; v = $PrivateKey } | Where-Object { [string]::IsNullOrWhiteSpace($_.v) } | ForEach-Object { $_.n })
if ($missing.Count) { $m = "Please add these secrets to your runner Key Vault and run again: $($missing -join ', ')"; Set-NodeOutput @{ status = 'error'; message = $m }; throw $m }
$BaseUrl = $BaseUrl.TrimEnd('/')
$headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${PublicKey}:${PrivateKey}")); Accept = 'application/json' }

$ci = [System.Globalization.CultureInfo]::InvariantCulture
$runDate = (Get-Date).ToUniversalTime()
$today = $runDate.ToString('d MMM yyyy', $ci)
$SubjectPrefix = 'Endpoint Hardware Refresh - '
$Categories = @('Replace', 'Plan replacement', 'Upgrade in place', 'Retain', 'Needs data', 'Human review', 'Virtual machines')
$PriorityInt = @{ Critical = 1; High = 1; Medium = 0; Low = -1 }   # Planner has no Critical: stored as High
$TierRank = @{ Critical = 3; High = 2; Medium = 1; Low = 0 }
$TierOrder = @('Critical', 'High', 'Medium', 'Low')
$Recommend = @{
    'Replace'          = 'Replace these computers. They are too old, run an operating system that no longer gets security updates, or are below the minimum specification.'
    'Plan replacement' = 'Plan to replace these computers in the next budget cycle, and extend warranties or upgrade parts to bridge the gap.'
    'Upgrade in place' = 'Upgrade these computers to Windows 11 in place. The hardware is capable, so no replacement is needed.'
    'Retain'           = 'Keep these computers, but extend the warranty or make a targeted upgrade where noted.'
    'Needs data'       = 'Confirm the age, warranty and operating system for these computers so they can be placed in a refresh category next time.'
    'Human review'     = 'Have a technician review these servers and decide the right next step for each one.'
    'Virtual machines' = 'Upgrade the guest operating system or adjust the assigned resources on these virtual machines. No hardware refresh is needed.'
}
$Opening = @{
    'Replace' = 'due for replacement'; 'Plan replacement' = 'approaching the end of the refresh cycle'; 'Upgrade in place' = 'ready for an in-place Windows 11 upgrade'
    'Retain' = 'worth keeping with a small fix'; 'Needs data' = 'missing the details needed for a refresh decision'; 'Human review' = 'servers that need a technician''s review'
    'Virtual machines' = 'virtual machines that need attention'
}
$RoadmapQuarter = @{ Critical = 1; High = 1; Medium = 2; Low = 3 }

# ---- shared: begin (Weekly Fleet Audit embeds everything down to "shared: end"; it needs $BaseUrl, $headers, $ci, $runDate, Get-Prop) ----
function Invoke-CrApi {
    param([string]$Path, [string]$Method = 'GET', $Body, [string]$ContentType = 'application/json')
    $url = if ($Path -match '^https?://') { $Path } else { "$BaseUrl$Path" }
    for ($i = 1; $i -le 6; $i++) {
        try {
            $a = @{ Uri = $url; Method = $Method; Headers = $headers; ContentType = $ContentType }
            if ($null -ne $Body) { $a.Body = $(if ($Body -is [string]) { $Body } else { ConvertTo-Json -InputObject $Body -Depth 12 }) }
            return Invoke-RestMethod @a
        }
        catch {
            $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch { }
            $msg = [string]$_.Exception.Message
            $transient = (-not $code -and $msg -match 'SSL connection|could not be established|No such host|actively refused|forcibly closed|error occurred while sending|timed out|TaskCanceled')
            if (($code -eq 429 -or ($Method -eq 'GET' -and $code -ge 500) -or $transient) -and $i -lt 6) { Start-Sleep -Seconds ([Math]::Min(30, [Math]::Pow(2, $i))); continue }
            $detail = $(if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $msg })
            throw "CloudRadial $Method $Path failed$(if ($code) { " (HTTP $code)" }): $detail"
        }
    }
}
function Get-CrAll {
    # OData lists stop at 200 rows with no nextLink, so page with $top/$skip.
    param([string]$Path)
    $rows = New-Object System.Collections.ArrayList; $skip = 0; $page = 200
    for ($n = 0; $n -lt 500; $n++) {
        $sep = if ($Path -match '\?') { '&' } else { '?' }
        $resp = Invoke-CrApi -Path "$Path$sep`$top=$page&`$skip=$skip"
        $batch = @(); $v = $(if ($null -ne $resp) { $resp.PSObject.Properties['value'] } else { $null })
        if ($v -and $null -ne $v.Value) { $batch = @($v.Value) } elseif ($resp -is [array]) { $batch = @($resp) }
        foreach ($r in $batch) { $null = $rows.Add($r) }
        if ($batch.Count -lt $page) { break }
        $skip += $page
    }
    return @($rows)
}
function Enc { param($t) [System.Net.WebUtility]::HtmlEncode([string]$t) }
function Parse-Date { param($v) $d = [datetime]::MinValue; if ($null -ne $v -and [string]$v -and [datetime]::TryParse([string]$v, $ci, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$d)) { if ($d.Year -gt 1900) { return $d } }; return $null }
function Friendly { param([datetime]$d) $d.ToString('d MMM yyyy', $ci) }
function Test-Completed { param($card) $s = [string](Get-Prop $card 'status'); return ($s -eq '40' -or $s -match '(?i)^completed$') }

# ---- rules (identical to the agent's decision tracks) ----
function Get-Age { param($ep)
    foreach ($f in @('manufacturedDate', 'biosDate', 'cpuDate')) { $d = Parse-Date (Get-Prop $ep $f); if ($d) { return @{ years = [math]::Round(($runDate - $d).TotalDays / 365.25, 1); estimated = ($f -ne 'manufacturedDate') } } }
    return $null
}
function Get-Warranty { param($ep)
    $d = Parse-Date (Get-Prop $ep 'expirationDate')
    if (-not $d) { return @{ status = 'unknown'; date = $null } }
    if ($d -lt $runDate) { return @{ status = 'expired'; date = $d } }
    if ($d -le $runDate.AddDays(90)) { return @{ status = 'expiring'; date = $d } }
    return @{ status = 'active'; date = $d }
}
function Get-OsType { param([string]$os) if ($os -match '(?i)windows') { 'windows' } elseif ($os -match '(?i)mac\s?os|os x') { 'macos' } else { 'other' } }
function Get-MacMajor { param([string]$os) if ($os -match '(?i)mac\s?os[^\d]*(\d+)') { [int]$Matches[1] } else { $null } }
function Get-OsSupport { param([string]$os, [string]$type)
    if ($type -eq 'windows') { if ($os -match '(?i)windows\s*11') { return 'supported' }; if ($os -match '(?i)windows\s*(10|8|7|xp|vista)') { return 'unsupported' }; return 'unknown' }
    if ($type -eq 'macos') { $m = Get-MacMajor $os; if ($null -eq $m) { return 'unknown' }; if ($m -ge 14) { return 'supported' }; return 'unsupported' }
    return 'unknown'
}
function Get-RamGb { param($ep) $b = 0.0; if ([double]::TryParse([string](Get-Prop $ep 'memory'), [System.Globalization.NumberStyles]::Float, $ci, [ref]$b) -and $b -gt 0) { [math]::Round($b / 1073741824, 1) } else { $null } }
function Get-Tier { param([string]$mode, $age, [string]$war, [string]$sup, [string]$type, $macMajor, $ram)
    if ($mode -eq 'vm') { if ($sup -eq 'unsupported' -or ($null -ne $ram -and $ram -lt 4)) { return 'High' }; return 'Low' }
    $hardEol = ($type -eq 'windows' -and $sup -eq 'unsupported') -or ($type -eq 'macos' -and $null -ne $macMajor -and $macMajor -le 12)
    if (($null -ne $age -and $age -ge 7) -or $hardEol -or ($null -ne $ram -and $ram -lt 4)) { return 'Critical' }
    if (($null -ne $age -and $age -ge 5) -or $war -eq 'expired' -or $sup -eq 'unsupported') { return 'High' }
    if (($null -ne $age -and $age -ge 4.5) -or $war -eq 'expiring') { return 'Medium' }
    return 'Low'
}
function Get-Assessment { param($ep)
    $name = [string](Get-Prop $ep 'name'); $os = [string](Get-Prop $ep 'os')
    $type = Get-OsType $os
    if ($type -eq 'other') { return @{ excluded = $true } }
    $ageO = Get-Age $ep; $age = if ($ageO) { $ageO.years } else { $null }
    $war = Get-Warranty $ep; $sup = Get-OsSupport $os $type; $mac = if ($type -eq 'macos') { Get-MacMajor $os } else { $null }
    # Positive-only Win11 signal. The API reports 'Ready' (and 'NotReady'), so match whole words and reject any 'not'.
    $ram = Get-RamGb $ep; $w11r = [string](Get-Prop $ep 'windows11Readiness'); $w11 = ($w11r -match '(?i)\b(installed|capable|ready)\b') -and ($w11r -notmatch '(?i)not')
    $mk = ([string](Get-Prop $ep 'manufacturer')).Trim(); $md = ([string](Get-Prop $ep 'model')).Trim(); $sn = ([string](Get-Prop $ep 'serialNumber')).Trim()
    $ident = (@($mk, $md) | Where-Object { $_ }) -join ' '; if ($sn) { $ident = $(if ($ident) { "$ident, serial $sn" } else { "serial $sn" }) }
    $lead = "<strong>$(Enc $name)</strong>$(if ($ident) { " ($(Enc $ident))" })"
    $ageTxt = if ($null -eq $age) { 'has no age on file' } elseif ($ageO.estimated) { "is about $age years old (estimated)" } else { "is about $age years old" }
    $warTxt = switch ($war.status) { 'expired' { "and its warranty expired on $(Friendly $war.date)" } 'expiring' { "and its warranty ends on $(Friendly $war.date)" } 'active' { "and is under warranty until $(Friendly $war.date)" } default { 'and has no warranty date on file' } }
    $osTxt = if (-not $os) { '' } else { " It is running $(Enc $os)$(switch ($sup) { 'supported' { ', which is supported' } 'unsupported' { ', which no longer gets security updates' } default { '' } })." }

    if ([bool](Get-Prop $ep 'isServer')) {
        return @{ flagged = $true; category = 'Human review'; tier = (Get-Tier 'std' $age $war.status $sup $type $mac $ram); line = "$lead $ageTxt $warTxt.$osTxt A technician should review this server and decide the next step." }
    }
    if ([bool](Get-Prop $ep 'isVirtual')) {
        $act = if ($sup -eq 'unsupported') { 'upgrade or rebuild the guest operating system onto Windows 11' } elseif ($null -ne $ram -and $ram -lt 4) { 'increase its assigned memory' } elseif ($null -ne $ram -and $ram -lt 8) { 'review and tune its assigned resources' } else { $null }
        if (-not $act) { return @{ flagged = $false } }   # healthy VM - not carded; unknown memory is not low
        return @{ flagged = $true; category = 'Virtual machines'; tier = (Get-Tier 'vm' $age $war.status $sup $type $mac $ram); line = "$lead is a virtual machine running $(if ($os) { Enc $os } else { 'an unknown operating system' }). Recommended action: $act." }
    }
    $rec = if (($null -ne $age -and $age -ge 5) -or ($sup -eq 'unsupported' -and -not $w11) -or ($null -ne $ram -and $ram -lt 4)) { 'Replace' }
        elseif ($sup -eq 'unsupported' -and $w11) { 'Upgrade in place' }
        elseif ($null -ne $age -and $age -ge 3) { 'Plan replacement' }
        elseif ($null -ne $age) { 'Retain' }
        elseif ($war.status -eq 'unknown' -and $sup -eq 'unknown') { 'Needs data' }
        else { 'Retain' }
    $flag = switch ($rec) { 'Retain' { ($war.status -in @('expired', 'expiring')) -or ($null -ne $ram -and $ram -lt 8) } default { $true } }
    if (-not $flag) { return @{ flagged = $false } }
    $act = switch ($rec) {
        'Replace' { 'replace this computer' }; 'Upgrade in place' { 'upgrade it to Windows 11 in place; the hardware is capable' }
        'Plan replacement' { 'plan its replacement this cycle, and extend the warranty or upgrade parts as a bridge' }
        'Retain' { 'extend the warranty or make a targeted upgrade' }; 'Needs data' { 'confirm its age, warranty and operating system so it can be placed next time' }
    }
    return @{ flagged = $true; category = $rec; tier = (Get-Tier 'std' $age $war.status $sup $type $mac $ram); line = "$lead $ageTxt $warTxt.$osTxt Recommended action: $act." }
}
# ---- shared: end ----

function Get-Summary { param([string]$category, [int]$n, [string]$top, $tierCounts)
    $noun = if ($category -eq 'Human review') { if ($n -eq 1) { 'server needs' } else { 'servers need' } } elseif ($category -eq 'Virtual machines') { if ($n -eq 1) { 'virtual machine needs' } else { 'virtual machines need' } } else { if ($n -eq 1) { 'computer is' } else { 'computers are' } }
    $what = switch ($category) {
        'Replace' { "$n $noun due for replacement" }; 'Plan replacement' { "$n $noun approaching the end of the refresh cycle" }
        'Upgrade in place' { "$n $noun ready for an in-place Windows 11 upgrade" }; 'Retain' { "$n $noun worth keeping with a warranty extension or small upgrade" }
        'Needs data' { "$n $noun missing the age, warranty or operating system details needed for a decision" }
        'Human review' { "$n $noun a technician's review" }; 'Virtual machines' { "$n $noun an operating system upgrade or resource change" }
    }
    $s = "$what."
    if ($top -eq 'Critical') { $s = "Critical: $s" }
    return $s
}

# ---- 1. read endpoints and sort them into categories ----
$filter = if ($CompanyIds.Count) { '?$filter=' + (($CompanyIds | ForEach-Object { "companyId eq $_" }) -join ' or ') } else { '' }
$endpoints = Get-CrAll "/v2/odata/endpoint$filter"
# The endpoint list still returns deleted endpoints of deleted companies (no deleted flag in the API);
# card writes for those fail with "Company not found", so skip any company not in the company list.
$knownCompanies = $null
try { $knownCompanies = New-Object System.Collections.Generic.HashSet[int]; foreach ($co in @(Get-CrAll '/v2/odata/company?$select=companyId')) { $null = $knownCompanies.Add([int](Get-Prop $co 'companyId')) } }
catch { $knownCompanies = $null }   # can't list companies: carry on without the check
if ($null -ne $knownCompanies -and $knownCompanies.Count -eq 0) { $knownCompanies = $null }
$counts = [ordered]@{ evaluated = 0; flaggedEndpoints = 0; excludedNonComputer = 0; skippedHealthy = 0; orphanedEndpoints = 0; companiesProcessed = 0; cardsCreated = 0; cardsUpdated = 0; cardsCompleted = 0; cardsSkipped = 0; errors = 0 }
$buckets = @{}; $evaluatedBy = @{}; $companiesInScope = New-Object System.Collections.Generic.HashSet[int]; $orphanedBy = @{}
foreach ($ep in $endpoints) {
    $cid = [int](Get-Prop $ep 'companyId')
    if ($CompanyIds.Count -and $CompanyIds -notcontains $cid) { continue }
    if ($null -ne $knownCompanies -and -not $knownCompanies.Contains($cid)) { $counts.orphanedEndpoints++; $orphanedBy[$cid] = 1 + [int]$orphanedBy[$cid]; continue }
    # Every key present: the runner runs in strict mode, where reading a missing key throws.
    $found = Get-Assessment $ep
    $a = @{ excluded = $false; flagged = $false; category = $null; tier = $null; line = $null }
    foreach ($k in @($found.Keys)) { $a[$k] = $found[$k] }
    if ($a.excluded) { $counts.excludedNonComputer++; continue }
    $null = $companiesInScope.Add($cid)
    $counts.evaluated++; $evaluatedBy[$cid] = 1 + [int]$evaluatedBy[$cid]
    if (-not $a.flagged) { $counts.skippedHealthy++; continue }
    $counts.flaggedEndpoints++
    if (-not $buckets.ContainsKey($cid)) { $buckets[$cid] = @{} }
    if (-not $buckets[$cid].ContainsKey($a.category)) { $buckets[$cid][$a.category] = New-Object System.Collections.ArrayList }
    $null = $buckets[$cid][$a.category].Add($a)
}
foreach ($c in $CompanyIds) { if ($null -eq $knownCompanies -or $knownCompanies.Contains($c)) { $null = $companiesInScope.Add($c) } elseif (-not $orphanedBy.ContainsKey($c)) { $orphanedBy[$c] = 0 } }   # a named company with no computers still gets its old cards closed

# ---- 2. one card per company and category ----
$results = New-Object System.Collections.ArrayList
function Add-Result { param($cid, $cat, $prio, $action, $prodId, $n, $note) $null = $results.Add([ordered]@{ companyId = [string]$cid; category = $cat; priority = $prio; action = $action; productId = [string]$prodId; deviceCount = $n; note = $note }) }
function Send-Patch { param($id, $fields)
    $ops = @($fields.GetEnumerator() | ForEach-Object { @{ op = 'replace'; path = "/$($_.Key)"; value = $_.Value } })
    try { $null = Invoke-CrApi -Path "/v2/product/$id" -Method PATCH -Body $ops -ContentType 'application/json-patch+json' }
    catch {
        # Older portals may not take notes or the roadmap fields - write the card without them.
        $core = @($ops | Where-Object { $_.path -notin @('/notes', '/productType', '/scheduledQuarter', '/quarterOffset') })
        if ($core.Count -eq $ops.Count) { throw }
        $null = Invoke-CrApi -Path "/v2/product/$id" -Method PATCH -Body $core -ContentType 'application/json-patch+json'
        $script:optionalDropped = $true
    }
}
$optionalDropped = $false
foreach ($oc in @($orphanedBy.Keys | Sort-Object)) { Add-Result $oc '' '' 'skipped' '' $orphanedBy[$oc] "Company $oc has been deleted, so its $(if ($orphanedBy[$oc] -eq 1) { 'leftover endpoint was' } else { "$($orphanedBy[$oc]) leftover endpoints were" }) skipped and no cards were written." }

foreach ($cid in @($companiesInScope | Sort-Object)) {
    $counts.companiesProcessed++
    $existing = @()
    try { $existing = Get-CrAll "/v2/odata/product?`$filter=companyId eq $cid" } catch { $counts.errors++; Add-Result $cid '' '' 'error' '' 0 "Couldn't read this company's Planner cards: $($_.Exception.Message)"; continue }
    $byCat = @{}
    foreach ($cat in $Categories) {
        $marker = "Refresh Plan Card: company $cid / $cat"
        $card = @($existing | Where-Object { ([string](Get-Prop $_ 'subject')).Trim() -eq "$SubjectPrefix$cat" -or ([string](Get-Prop $_ 'body')).Contains($marker) } | Select-Object -First 1)
        if ($card.Count) { $byCat[$cat] = $card[0] }
    }
    $mine = if ($buckets.ContainsKey($cid)) { $buckets[$cid] } else { @{} }

    foreach ($cat in $Categories) {
        $card = $byCat[$cat]; $devices = @(if ($mine.ContainsKey($cat)) { $mine[$cat] })
        $marker = "Refresh Plan Card: company $cid / $cat"
        try {
            if ($devices.Count -eq 0) {
                # Empty category: close this card (it reopens when devices return).
                if ($null -eq $card) { continue }
                if (Test-Completed $card) { $counts.cardsSkipped++; Add-Result $cid $cat '' 'skipped' (Get-Prop $card 'productId') 0 'Already closed; no computers in this category.'; continue }
                if (-not $CloseEmpty) { continue }
                # Write first, then count: a failed write is reported only as an error.
                if ($Apply) { Send-Patch (Get-Prop $card 'productId') @{ status = 40; body = "<p>No computers need action in this category as of $today.</p><p><em>$marker</em></p>"; notes = "Internal: company $cid. $([int]$evaluatedBy[$cid]) computers evaluated on $today; none in $cat, so this card was closed. Marker: $marker." } }
                $counts.cardsCompleted++
                Add-Result $cid $cat '' 'completed' (Get-Prop $card 'productId') 0 "No computers need action in this category any more, so the card $(if ($Apply) { 'was' } else { 'would be' }) marked Completed."
                continue
            }
            $top = ($devices | Sort-Object { $TierRank[$_.tier] } -Descending | Select-Object -First 1).tier
            $tierCounts = [ordered]@{}; foreach ($tr in $TierOrder) { $k = @($devices | Where-Object { $_.tier -eq $tr }).Count; if ($k) { $tierCounts[$tr] = $k } }
            $tierText = (@($tierCounts.GetEnumerator() | ForEach-Object { "$($_.Value) $($_.Key)" })) -join ', '
            $n = $devices.Count
            $sb = New-Object System.Text.StringBuilder
            $plural = $n -ne 1
            $openLine = switch ($cat) {
                'Human review' { "This company has $(if ($plural) { "$n servers that need" } else { 'one server that needs' }) a technician's review." }
                'Virtual machines' { "This company has $(if ($plural) { "$n virtual machines that need" } else { 'one virtual machine that needs' }) attention." }
                default { "$(if ($plural) { "$n computers at this company are" } else { 'One computer at this company is' }) $($Opening[$cat])." }
            }
            $null = $sb.Append("<p>$openLine</p>")
            $null = $sb.Append("<h4>What we recommend</h4><p>$($Recommend[$cat])</p>")
            foreach ($tr in $TierOrder) {
                $inTier = @($devices | Where-Object { $_.tier -eq $tr }); if (-not $inTier.Count) { continue }
                $null = $sb.Append("<h4>$tr</h4><ul>"); foreach ($d in $inTier) { $null = $sb.Append("<li>$($d.line)</li>") }; $null = $sb.Append('</ul>')
            }
            $null = $sb.Append("<h4>Summary</h4><p>$tierText.</p><p><em>$marker</em></p>")
            $summary = Get-Summary $cat $n $top $tierCounts
            $notes = "Internal: company $cid. $([int]$evaluatedBy[$cid]) computers evaluated on $today. This $cat card: $tierText. Marker: $marker."
            $fields = [ordered]@{ subject = "$SubjectPrefix$cat"; body = $sb.ToString(); summary = $summary; notes = $notes; category = $PlannerCategory; productCategoryId = $ProductCategoryId; priority = $PriorityInt[$top] }
            $quarter = if ($cat -in @('Human review', 'Needs data')) { 1 } else { $RoadmapQuarter[$top] }
            if ($OnRoadmap) { $fields.productType = 1; $fields.scheduledQuarter = $quarter; $fields.quarterOffset = $quarter - 1 }

            if ($null -ne $card) {
                $id = Get-Prop $card 'productId'
                $reopen = Test-Completed $card
                if ($reopen) { $fields.status = $(if ($OnRoadmap) { 20 } else { 0 }) } elseif ($OnRoadmap) { $fields.status = 20 }
                if ($Apply) { Send-Patch $id $fields }
                $counts.cardsUpdated++
                Add-Result $cid $cat $top $(if ($reopen) { 'reopened' } else { 'updated' }) $id $n $summary
            }
            else {
                $newId = ''
                if ($Apply) {
                    $body = [ordered]@{ companyId = $cid; datePublished = $runDate.ToString('yyyy-MM-ddTHH:mm:ss.fffZ'); isRequired = $false; isShowPrice = $false; isClientVisible = $false; status = $(if ($OnRoadmap) { 20 } else { 0 }) }
                    foreach ($k in $fields.Keys) { $body[$k] = $fields[$k] }
                    $new = $null
                    try { $new = Invoke-CrApi -Path '/v2/product' -Method POST -Body $body }
                    catch {
                        foreach ($k in @('notes', 'productType', 'scheduledQuarter', 'quarterOffset')) { $body.Remove($k) }
                        $new = Invoke-CrApi -Path '/v2/product' -Method POST -Body $body; $optionalDropped = $true
                    }
                    # POST replies { success, message, data = { productId, ... } }.
                    $newId = [string](Get-Prop $new 'productId'); if (-not $newId) { $newId = [string](Get-Prop (Get-Prop $new 'data') 'productId') }
                }
                $counts.cardsCreated++
                Add-Result $cid $cat $top 'created' $newId $n $summary
            }
        }
        catch { $counts.errors++; Add-Result $cid $cat '' 'error' $(if ($card) { Get-Prop $card 'productId' }) $devices.Count $_.Exception.Message }
    }
}

$scope = if ($CompanyIds.Count) { "companies $($CompanyIds -join ', ')" } else { 'all companies' }
$verb = if ($Apply) { '' } else { ' (plan - nothing written)' }
$out = [ordered]@{ status = $(if ($counts.errors) { 'completed_with_errors' } else { 'ok' }); mode = $Mode }
foreach ($k in $counts.Keys) { $out[$k] = $counts[$k] }
$out.optionalFieldsDropped = $optionalDropped
$out.results = @($results)
$out.message = "Endpoint LifeCycle Manager$verb for $scope : $($counts.evaluated) computers evaluated, $($counts.flaggedEndpoints) on cards, $($counts.excludedNonComputer) non-computers excluded$(if ($counts.orphanedEndpoints) { ", $($counts.orphanedEndpoints) skipped from deleted companies" }). Cards: $($counts.cardsCreated) created, $($counts.cardsUpdated) updated, $($counts.cardsCompleted) closed, $($counts.errors) errors."
Set-NodeOutput $out
