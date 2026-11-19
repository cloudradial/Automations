$ErrorActionPreference = 'Stop'
Set-StrictMode -Off
trap { Set-NodeOutput ([ordered]@{ status = 'error'; message = $_.Exception.Message; line = $_.InvocationInfo.ScriptLineNumber; text = ([string]$_.InvocationInfo.Line).Trim() }); break }
# === NODE: Refresh the QBR dashboard ===
# Fills the @CH tokens behind the Quarterly Business Review dashboard with live data: ConnectWise tickets and projects,
# Datto RMM devices, CloudRadial feedback and users, and Microsoft 365 Secure Score and MFA where the app has consent.
# Input: companyId (CloudRadial, required), timeZone (IANA, default America/New_York), psaCompanyId (ConnectWise), sites (Datto site names, default all),
# tenantId (Microsoft 365, default the company's), refreshCostPerDevice (default 1400), confirm (default true).
function P { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Sec { param([string[]]$names) foreach ($n in $names) { $v = [string](Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $n -AsPlainText -ErrorAction SilentlyContinue); if ($v) { return $v.Trim() } }; return '' }
function Pct { param($a, $b) if (-not $b) { return 0 }; return [math]::Round(100.0 * $a / $b) }
function Col { param($v, [int]$good = 80, [int]$ok = 65) if ($v -ge $good) { '#16a34a' } elseif ($v -ge $ok) { '#d97706' } else { '#dc2626' } }
$in = Get-NodeInput; $trig = P $in 'trigger'; if ($trig -is [string]) { $trig = $trig | ConvertFrom-Json }; if ($null -eq $trig) { $trig = $in }
$companyId = [int](P $trig 'companyId'); if ($companyId -le 0) { throw 'Send companyId: the CloudRadial company whose QBR dashboard to refresh.' }
$psaId = [int](P $trig 'psaCompanyId')
$sites = @(P $trig 'sites' | ForEach-Object { [string]$_ } | Where-Object { $_ })
$cost = 1400; if ([string](P $trig 'refreshCostPerDevice') -match '^\d+$') { $cost = [int](P $trig 'refreshCostPerDevice') }
$confirm = -not ([string](P $trig 'confirm') -match '^(?i)(false|0|no)$')
$crSuffix = [string](P $trig 'cloudradial_company'); $sfx = if ($crSuffix) { "-$crSuffix" } else { '' }
$warnings = New-Object System.Collections.Generic.List[string]
$now = (Get-Date).ToUniversalTime()
$tzId = [string](P $trig 'timeZone'); if (-not $tzId) { $tzId = 'America/New_York' }
$tz = $null; try { $tz = [TimeZoneInfo]::FindSystemTimeZoneById($tzId) } catch { }
$nowL = if ($tz) { [TimeZoneInfo]::ConvertTimeFromUtc($now, $tz) } else { $now }

# ---- CloudRadial ----
$crB = (Sec @("CloudRadial-BaseUrl$sfx", 'CloudRadial-BaseUrl')).TrimEnd('/'); $crPu = Sec @("CloudRadial-PublicKey$sfx", 'CloudRadial-PublicKey'); $crPr = Sec @("CloudRadial-PrivateKey$sfx", 'CloudRadial-PrivateKey')
$crH = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($crPu):$($crPr)")); Accept = 'application/json' }
function CrGet { param([string]$Path) Invoke-RestMethod -Method Get -Uri "$crB$Path" -Headers $crH }
$co = $null; try { $co = @((CrGet "/v2/odata/company?`$filter=$([uri]::EscapeDataString("companyId eq $companyId"))").value) | Select-Object -First 1 } catch { $warnings.Add("Company not read: $($_.Exception.Message)") }
if (-not $psaId -and $co) { foreach ($k in 'psaId', 'psaCompanyId', 'psaKey') { $v = [string](P $co $k); if ($v -match '^\d+$') { $psaId = [int]$v; break } } }
$tenantId = [string](P $trig 'tenantId'); if (-not $tenantId -and $co) { $tenantId = [string](P $co 'tenantId') }

# ---- ConnectWise ----
$cwApi = (Sec @('CW-ApiUrl')).TrimEnd('/'); $pair = "{0}+{1}:{2}" -f (Sec @('CW-CompanyID')), (Sec @('CW-PublicKey')), (Sec @('CW-PrivateKey'))
$cwH = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair)); clientId = (Sec @('CW-ClientId')); Accept = 'application/json' }
function CwGet { param([string]$Path) $r = Invoke-RestMethod -Method Get -Uri "$cwApi$Path" -Headers $cwH; if ($r -is [array]) { foreach ($x in $r) { $x } } else { $r } }
function CwCount { param([string]$cond) [int](CwGet "/service/tickets/count?conditions=$([uri]::EscapeDataString($cond))").count }
function D { param([datetime]$d) $d.ToString('yyyy-MM-ddTHH:mm:ssZ') }
$T = @{}
$q = [math]::Floor(($nowL.Month - 1) / 3); $qStart = [datetime]::new($nowL.Year, $q * 3 + 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
$qNames = @('Jan to Mar', 'Apr to Jun', 'Jul to Sep', 'Oct to Dec')
$T.CHPeriod = "Q$($q + 1) $($nowL.Year) ($($qNames[$q]))"; $T.CHUpdated = $nowL.ToString('MMM d, yyyy')
$months = @(); $sla = 0; $medTxt = '–'; $cats = @(); $projects = @(); $qCreated = 0; $qOpen = 0; $closedN = 0
if ($psaId) {
    try {
        $mx = 1
        for ($i = 5; $i -ge 0; $i--) {
            $ms = [datetime]::new($nowL.Year, $nowL.Month, 1, 0, 0, 0, [DateTimeKind]::Utc).AddMonths(-$i); $me = $ms.AddMonths(1)
            $c = CwCount "company/id=$psaId and dateEntered>=[$(D $ms)] and dateEntered<[$(D $me)]"
            $x = CwCount "company/id=$psaId and closedFlag=true and closedDate>=[$(D $ms)] and closedDate<[$(D $me)]"
            $months += [pscustomobject]@{ m = $ms.ToString('MMM') + $(if ($i -eq 0) { '*' } else { '' }); c = $c; x = $x }; $mx = [math]::Max($mx, [math]::Max($c, $x))
        }
        $qCreated = CwCount "company/id=$psaId and dateEntered>=[$(D $qStart)]"
        $qOpen = CwCount "company/id=$psaId and dateEntered>=[$(D $qStart)] and closedFlag=false"
        $closed = @(CwGet "/service/tickets?pageSize=1000&fields=id,closedDate,_info/dateEntered&conditions=$([uri]::EscapeDataString("company/id=$psaId and closedFlag=true and closedDate>=[$(D $now.AddDays(-90))]"))")
        $hours = @(foreach ($tk in $closed) { try { ([datetime]$tk.closedDate - [datetime]$tk._info.dateEntered).TotalHours } catch { } }) | Where-Object { $_ -ge 0 } | Sort-Object
        $closedN = $hours.Count
        if ($closedN) { $sla = Pct (@($hours | Where-Object { $_ -le 72 }).Count) $closedN; $med = $hours[[int][math]::Floor(($closedN - 1) / 2)]; $medTxt = if ($med -lt 1) { "$([math]::Round($med * 60)) min" } elseif ($med -lt 48) { "$([math]::Round($med, 1)) hrs" } else { "$([math]::Round($med / 24, 1)) days" } }
        $recent = @(CwGet "/service/tickets?pageSize=1000&fields=id,type/name&conditions=$([uri]::EscapeDataString("company/id=$psaId and dateEntered>=[$(D $now.AddDays(-90))]"))")
        $grp = @($recent | Group-Object { $n = [string]$_.type.name; if ($n) { $n } else { 'Uncategorized' } } | Sort-Object Count -Descending)
        $tot = [math]::Max(1, $recent.Count)
        $cats = @($grp | Select-Object -First 5 | ForEach-Object { [pscustomobject]@{ n = $_.Name; p = Pct $_.Count $tot } })
        $rest = $tot - (@($grp | Select-Object -First 5 | Measure-Object Count -Sum).Sum); if ($grp.Count -gt 5 -and $rest -gt 0) { $cats += [pscustomobject]@{ n = 'Other'; p = Pct $rest $tot } }
        $projects = @(CwGet "/project/projects?pageSize=5&orderBy=estimatedEnd&fields=id,name,percentComplete,estimatedEnd,status/name,type/name&conditions=$([uri]::EscapeDataString("company/id=$psaId and closedFlag=false"))")
    } catch { $warnings.Add("ConnectWise: $($_.Exception.Message)") }
} else { $warnings.Add('No ConnectWise company id; ticket and project figures are empty.') }
for ($i = 1; $i -le 6; $i++) { $m = if ($i -le $months.Count) { $months[$i - 1] } else { $null }
    $T["CHTktMonth$i"] = $(if ($m) { $m.m } else { '' }); $T["CHTktCreated$i"] = $(if ($m) { [string]$m.c } else { '' }); $T["CHTktClosed$i"] = $(if ($m) { [string]$m.x } else { '' })
    $T["CHTktBarCreated$i"] = $(if ($m) { [string](Pct $m.c $mx) } else { '0' }); $T["CHTktBarClosed$i"] = $(if ($m) { [string](Pct $m.x $mx) } else { '0' }) }
$T.CHNoteTickets = '* month to date'
$top = if ($cats.Count) { [math]::Max(1, $cats[0].p) } else { 1 }
for ($i = 1; $i -le 6; $i++) { $c = if ($i -le $cats.Count) { $cats[$i - 1] } else { $null }; $T["CHCatName$i"] = $(if ($c) { $c.n } else { '' }); $T["CHCatPct$i"] = $(if ($c) { [string]$c.p } else { '0' }); $T["CHCatBar$i"] = $(if ($c) { [string](Pct $c.p $top) } else { '0' }) }
$T.CHOpenTickets = [string]$qCreated; $T.CHNoteOpenTickets = "$qOpen still open"
$T.CHSlaPct = [string]$sla; $T.CHNoteSla = "$closedN closed in the last 90 days"
$T.CHFirstResponse = $medTxt; $T.CHNoteFirstResponse = 'median, last 90 days'
$stMap = @{ 'On track' = @('#dcfce7', '#166534', '#22c55e'); 'At risk' = @('#fef3c7', '#92400e', '#f59e0b'); 'Off track' = @('#fee2e2', '#991b1b', '#ef4444'); 'Complete' = @('#e0f2fe', '#075985', '#0ea5e9') }
for ($i = 1; $i -le 5; $i++) { $p = if ($i -le $projects.Count) { $projects[$i - 1] } else { $null }
    if ($p) { $pc = [double]$p.percentComplete; if ($pc -le 1) { $pc = $pc * 100 }; $sn = [string]$p.status.name
        $st = if ($pc -ge 100 -or $sn -match '(?i)complete|closed') { 'Complete' } elseif ($sn -match '(?i)hold|risk|wait') { 'At risk' } elseif ($p.estimatedEnd -and ([datetime]$p.estimatedEnd) -lt $now) { 'Off track' } else { 'On track' }
        $c = $stMap[$st]; $T["CHProjName$i"] = [string]$p.name; $T["CHProjType$i"] = $(if ($p.type.name) { [string]$p.type.name } else { $sn }); $T["CHProjPct$i"] = [string][math]::Round($pc)
        $T["CHProjDue$i"] = $(if ($p.estimatedEnd) { ([datetime]$p.estimatedEnd).ToString('MMM d, yyyy') } else { '' }); $T["CHProjStatus$i"] = $st; $T["CHProjBg$i"] = $c[0]; $T["CHProjFg$i"] = $c[1]; $T["CHProjBar$i"] = $c[2] }
    else { $T["CHProjName$i"] = $(if ($i -eq 1) { 'No open projects' } else { '' }); $T["CHProjType$i"] = ''; $T["CHProjPct$i"] = '0'; $T["CHProjDue$i"] = ''; $T["CHProjStatus$i"] = ''; $T["CHProjBg$i"] = '#ffffff'; $T["CHProjFg$i"] = '#ffffff'; $T["CHProjBar$i"] = '#eef2f7' } }

# ---- CSAT and adoption (CloudRadial) ----
$csat = '–'; $csatN = 0; $adopt = 0; $adoptNote = ''
try {
    $fb = @((CrGet "/v2/odata/feedback?`$filter=$([uri]::EscapeDataString("companyId eq $companyId"))").value)
    $rk = if ($fb.Count) { @($fb[0].PSObject.Properties.Name | Where-Object { $_ -match '(?i)^(rating|score|stars|satisfaction)' }) | Select-Object -First 1 } else { $null }
    $vals = @($fb | ForEach-Object { $v = P $_ $rk; if ([string]$v -match '^\d+(\.\d+)?$') { [double]$v } })
    if ($vals.Count) { $avg = ($vals | Measure-Object -Average).Average; $mxv = ($vals | Measure-Object -Maximum).Maximum; if ($mxv -gt 5) { $avg = $avg / 2 }; $csat = [string][math]::Round($avg, 1); $csatN = $vals.Count }
} catch { $warnings.Add("Feedback: $($_.Exception.Message)") }
try {
    $users = @((CrGet "/v2/odata/user?`$filter=$([uri]::EscapeDataString("companyId eq $companyId"))").value)
    $lk = if ($users.Count) { @($users[0].PSObject.Properties.Name | Where-Object { $_ -match '(?i)last.*(log|sign|active|access)' }) | Select-Object -First 1 } else { $null }
    if ($lk) { $act = @($users | Where-Object { $v = P $_ $lk; $v -and ([datetime]$v) -gt $now.AddDays(-90) }).Count; $adopt = Pct $act $users.Count; $adoptNote = "$act of $($users.Count) users active in the portal" }
    else { $sig = @((CrGet '/v2/signaldevice').data | Where-Object { [int]$_.companyId -eq $companyId -and $_.signedIn }).Count; $adopt = [math]::Min(100, (Pct $sig ([math]::Max(1, $users.Count))) * 5); $adoptNote = "$sig Signal desktops signed in" }
} catch { $warnings.Add("Users: $($_.Exception.Message)") }
$T.CHCsat = $csat; $T.CHNoteCsat = $(if ($csatN) { "$csatN ratings" } else { 'no ratings yet' })

# ---- Datto RMM ----
$n = 0; $online = 0; $patchPct = 0; $avPct = 0; $checkPct = 0; $w10 = 0; $cur = 0; $plan = 0; $repl = 0; $unk = 0
try {
    $base = (Sec @('Datto-ApiUrl')).TrimEnd('/'); if ($base.EndsWith('/api')) { $base = $base.Substring(0, $base.Length - 4) }
    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('public-client:public'))
    $form = "grant_type=password&username=$([uri]::EscapeDataString((Sec @('Datto-ApiKey'))))&password=$([uri]::EscapeDataString((Sec @('Datto-ApiSecret'))))"
    $tok = Invoke-RestMethod -Method POST -Uri "$base/auth/oauth/token" -Headers @{ Authorization = "Basic $basic"; Accept = 'application/json' } -Body $form -ContentType 'application/x-www-form-urlencoded'
    $dh = @{ Authorization = "Bearer $($tok.access_token)"; Accept = 'application/json' }
    $all = @(); $page = 0; do { $resp = Invoke-RestMethod -Uri "$base/api/v2/account/devices?max=250&page=$page" -Headers $dh; $all += @($resp.devices); $page++ } while ($resp.pageDetails.nextPageUrl -and $page -lt 20)
    if ($sites.Count) { $all = @($all | Where-Object { $sites -contains [string]$_.siteName }) }
    $pcs = @($all | Where-Object { $_.deviceClass -eq 'device' -and [string]$_.deviceType.category -notmatch '(?i)network|printer' })
    $n = $pcs.Count; $online = @($pcs | Where-Object { $_.online }).Count
    $pp = @($pcs | Where-Object { @('FullyPatched', 'ApprovedPending', 'InstallError', 'RebootRequired') -contains [string]$_.patchManagement.patchStatus })
    $patchPct = Pct (@($pp | Where-Object { $_.patchManagement.patchStatus -eq 'FullyPatched' }).Count) $pp.Count
    $avPct = Pct (@($pcs | Where-Object { [string]$_.antivirus.antivirusStatus -eq 'RunningAndUpToDate' }).Count) $n
    foreach ($d in $pcs) {
        $days = if ($d.lastSeen) { ($now - [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$d.lastSeen).UtcDateTime).TotalDays } else { 9999 }
        $os = [string]$d.operatingSystem
        if ($os -match 'Windows 10') { $w10++ }
        if (-not $d.online -and $days -gt 90) { $repl++ } elseif ($os -match 'Windows 10') { $plan++ } elseif (-not $os) { $unk++ } else { $cur++ }
    }
    $checkPct = Pct (@($pcs | Where-Object { $_.online -or ($_.lastSeen -and [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$_.lastSeen).UtcDateTime -gt $now.AddDays(-30)) }).Count) $n
} catch { $warnings.Add("Datto RMM: $($_.Exception.Message)") }
$T.CHEndpoints = [string]$n; $T.CHNoteEndpoints = "$online online now"
$T.CHLcTotal = [string]$n; $T.CHLcBudget = '$' + ('{0:N0}' -f (($plan + $repl) * $cost))
foreach ($k in @(@('Current', $cur), @('Plan', $plan), @('Replace', $repl), @('Oow', $unk))) { $T["CHLcCount$($k[0])"] = [string]$k[1]; $T["CHLcPct$($k[0])"] = [string](Pct $k[1] $n) }

# ---- Microsoft 365 ----
$score = $null; $mfa = $null
if ($tenantId) {
    try {
        $cid = Sec @('M365-ClientId', 'M365-ClientID'); $cs = Sec @('M365-ClientSecret')
        $gt = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body @{ client_id = $cid; client_secret = $cs; scope = 'https://graph.microsoft.com/.default'; grant_type = 'client_credentials' }
        $gh = @{ Authorization = "Bearer $($gt.access_token)" }
        try { $ss = @((Invoke-RestMethod -Uri 'https://graph.microsoft.com/v1.0/security/secureScores?`$top=1' -Headers $gh).value)[0]; if ($ss.maxScore) { $score = Pct $ss.currentScore $ss.maxScore } } catch { $warnings.Add("Secure Score: $($_.Exception.Message)") }
        try { $rd = @((Invoke-RestMethod -Uri 'https://graph.microsoft.com/v1.0/reports/authenticationMethods/userRegistrationDetails?`$top=999' -Headers $gh).value | Where-Object { $_.userType -ne 'guest' }); if ($rd.Count) { $mfa = Pct (@($rd | Where-Object { $_.isMfaRegistered }).Count) $rd.Count } } catch { $warnings.Add("MFA: $($_.Exception.Message)") }
    } catch { $warnings.Add("Microsoft 365 sign-in: $($_.Exception.Message)") }
}
$T.CHSecureScore = $(if ($null -ne $score) { [string]$score } else { '–' }); $T.CHNoteSecureScore = $(if ($null -ne $score) { 'Microsoft 365' } else { 'not connected' })
$sec = [ordered]@{ Mfa = $mfa; Patch = $patchPct; Edr = $avPct; Backup = $checkPct; Training = $score; Phish = (Pct $w10 $n) }
foreach ($k in $sec.Keys) { $v = $sec[$k]; $T["CHSecPct$k"] = $(if ($null -ne $v) { [string]$v } else { '–' })
    $T["CHSecColor$k"] = $(if ($null -eq $v) { '#94a3b8' } elseif ($k -eq 'Phish') { if ($v -gt 10) { '#ef4444' } else { '#22c55e' } } elseif ($v -ge 90) { '#22c55e' } elseif ($v -ge 75) { '#f59e0b' } else { '#ef4444' }) }

# ---- Health score ----
$secVals = @(@($mfa, $patchPct, $avPct, $score) | Where-Object { $null -ne $_ })
$hSvc = $sla; $hSec = if ($secVals.Count) { [math]::Round(($secVals | Measure-Object -Average).Average) } else { 0 }; $hLc = Pct $cur $n; $hAd = $adopt
$T.CHHealthService = [string]$hSvc; $T.CHHealthSecurity = [string]$hSec; $T.CHHealthLifecycle = [string]$hLc; $T.CHHealthAdoption = [string]$hAd
$T.CHHealthScore = [string][math]::Round(($hSvc + $hSec + $hLc + $hAd) / 4)
$T.CHColorService = Col $hSvc; $T.CHColorSecurity = Col $hSec; $T.CHColorLifecycle = Col $hLc; $T.CHColorAdoption = Col $hAd

$written = 0
if ($confirm) { foreach ($k in $T.Keys) { try { $b = @{ companyId = $companyId; token = $k; value = [string]$T[$k]; type = 'String' } | ConvertTo-Json; $null = Invoke-RestMethod -Method Post -Uri "$crB/v2/token" -Headers $crH -ContentType 'application/json' -Body $b; $written++ } catch { $warnings.Add("Token $k not written: $($_.Exception.Message)") } } }
$summary = "QBR for company $($companyId), $($T.CHPeriod): $qCreated tickets this quarter ($qOpen open), $sla% resolved within 3 days, $n devices ($patchPct% patched), Secure Score $($T.CHSecureScore), health $($T.CHHealthScore)."
Set-NodeOutput ([ordered]@{ status = $(if ($confirm) { 'success' } else { 'preview' }); message = $summary; tokensWritten = $written; psaCompanyId = $psaId; tenantId = $tenantId; adoption = $adoptNote; warnings = @($warnings); tokens = $T; internal_note = $summary })
