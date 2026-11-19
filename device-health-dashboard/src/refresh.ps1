$ErrorActionPreference = 'Stop'
Set-StrictMode -Off
# === NODE: Refresh the Device Health dashboard ===
# Reads every device from Datto RMM, works out patch, antivirus, reboot and check-in health, starts a Windows Update
# repair job on online devices with patch problems, then writes the @DH tokens that drive the Device Health dashboard.
# Input: companyId (CloudRadial company, required), remediateDevices (hostnames allowed to get a fix) or remediateAll,
# timeZone (IANA, default America/New_York), sites (Datto site names, default all), remediate (default true),
# maxFixes (default 3), notifyUsers (CloudRadial user ids for a Signal summary), confirm (default true).
function P { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function J { param($x) if ($x -is [string]) { try { return ($x | ConvertFrom-Json) } catch { return $null } }; return $x }
function Sec { param([string[]]$names) foreach ($n in $names) { $v = [string](Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $n -AsPlainText -ErrorAction SilentlyContinue); if ($v) { return $v.Trim() } }; return '' }
function Flag { param($v, [bool]$def) if ($null -eq $v -or [string]$v -eq '') { return $def }; return -not ([string]$v -match '^(?i)(false|0|no|off)$') }

$in = Get-NodeInput; $trig = J (P $in 'trigger'); if ($null -eq $trig) { $trig = $in }
$companyId = [int](P $trig 'companyId'); if ($companyId -le 0) { throw 'Send companyId: the CloudRadial company whose Device Health dashboard to refresh.' }
$sites = @(P $trig 'sites' | ForEach-Object { [string]$_ } | Where-Object { $_ })
$remediate = Flag (P $trig 'remediate') $true
$confirm = Flag (P $trig 'confirm') $true
$maxFixes = 3; if ([string](P $trig 'maxFixes') -match '^\d+$') { $maxFixes = [int](P $trig 'maxFixes') }
$notifyUsers = @(P $trig 'notifyUsers' | ForEach-Object { [string]$_ } | Where-Object { $_ })
$fixDevices = @(P $trig 'remediateDevices' | ForEach-Object { [string]$_ } | Where-Object { $_ }); $fixAll = Flag (P $trig 'remediateAll') $false
$fixComponent = [string](P $trig 'fixComponent'); if (-not $fixComponent) { $fixComponent = 'Windows Update Toolkit [WIN]' }
$crSuffix = [string](P $trig 'cloudradial_company')
$crSuffix = ($crSuffix.ToLower() -replace '[^a-z0-9]+', '-').Trim('-'); $sfx = if ($crSuffix) { "-$crSuffix" } else { '' }
$tzId = [string](P $trig 'timeZone'); if (-not $tzId) { $tzId = 'America/New_York' }; $tzLabel = [string](P $trig 'timeZoneLabel'); if (-not $tzLabel -and $tzId -eq 'America/New_York') { $tzLabel = 'ET' }
$tz = $null; try { $tz = [TimeZoneInfo]::FindSystemTimeZoneById($tzId) } catch { }
function Local { param([datetime]$utc) if ($tz) { return [TimeZoneInfo]::ConvertTimeFromUtc($utc, $tz) }; return $utc }
$nowUtc = (Get-Date).ToUniversalTime(); $nowL = Local $nowUtc
$warnings = New-Object System.Collections.Generic.List[string]

# ---- CloudRadial ----
$crB = (Sec @("CloudRadial-BaseUrl$sfx", 'CloudRadial-BaseUrl')).TrimEnd('/'); $crPu = Sec @("CloudRadial-PublicKey$sfx", 'CloudRadial-PublicKey'); $crPr = Sec @("CloudRadial-PrivateKey$sfx", 'CloudRadial-PrivateKey')
$crH = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($crPu):$($crPr)")); Accept = 'application/json' }
function Set-Tok { param([string]$n, [string]$v) $b = @{ companyId = $companyId; token = $n; value = $v; type = 'String' } | ConvertTo-Json; $null = Invoke-RestMethod -Method Post -Uri "$crB/v2/token" -Headers $crH -ContentType 'application/json' -Body $b }
$history = @()
try { $tk = Invoke-RestMethod -Method Get -Uri "$crB/v2/odata/token?`$filter=$([uri]::EscapeDataString("companyId eq $companyId and name eq 'DHHistory'"))" -Headers $crH; $hv = [string](@($tk.value) | Select-Object -First 1).value; if ($hv) { $history = @($hv | ConvertFrom-Json) } } catch { $warnings.Add("History not read: $($_.Exception.Message)") }

# ---- Datto RMM ----
$base = (Sec @('Datto-ApiUrl')).TrimEnd('/'); if ($base.EndsWith('/api')) { $base = $base.Substring(0, $base.Length - 4) }
$basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('public-client:public'))
$form = "grant_type=password&username=$([uri]::EscapeDataString((Sec @('Datto-ApiKey'))))&password=$([uri]::EscapeDataString((Sec @('Datto-ApiSecret'))))"
$tok = Invoke-RestMethod -Method POST -Uri "$base/auth/oauth/token" -Headers @{ Authorization = "Basic $basic"; Accept = 'application/json' } -Body $form -ContentType 'application/x-www-form-urlencoded'
$dh = @{ Authorization = "Bearer $($tok.access_token)"; Accept = 'application/json' }
function DGet { param([string]$Path) Invoke-RestMethod -Method GET -Uri "$base$Path" -Headers $dh }
$all = @(); $page = 0
do { $resp = DGet "/api/v2/account/devices?max=250&page=$page"; $all += @($resp.devices); $page++ } while ($resp.pageDetails.nextPageUrl -and $page -lt 20)
if ($sites.Count) { $all = @($all | Where-Object { $sites -contains [string]$_.siteName }) }
$pcs = @($all | Where-Object { $cat = [string]$_.deviceType.category; $_.deviceClass -eq 'device' -and $cat -notmatch '(?i)network|printer' })

# Update the status of earlier fixes from their job results
foreach ($h in $history) { if ($h.res -eq 'Running' -and $h.job) { try { $r = DGet "/api/v2/job/$($h.job)/results/$($h.devUid)"; $cs = [string](@($r.componentResults) | Select-Object -First 1).componentStatus; if ($cs -match '(?i)success') { $h.res = 'Success' } elseif ($cs -and $cs -notmatch '(?i)running|pending|scheduled|queued') { $h.res = 'Failed' } } catch { } } }

# ---- Health figures ----
$n = $pcs.Count
$online = @($pcs | Where-Object { $_.online }).Count
$staleList = @($pcs | Where-Object { -not $_.online -and $_.lastSeen -and ([DateTimeOffset]::FromUnixTimeMilliseconds([int64]$_.lastSeen).UtcDateTime -lt $nowUtc.AddDays(-30)) })
$patchable = @($pcs | Where-Object { $s = [string]$_.patchManagement.patchStatus; $s -and $s -ne 'NoData' })
$cnt = @{ Full = 0; Pend = 0; Err = 0; Rbt = 0; None = 0 }
foreach ($d in $patchable) { switch ([string]$d.patchManagement.patchStatus) { 'FullyPatched' { $cnt.Full++ } 'ApprovedPending' { $cnt.Pend++ } 'InstallError' { $cnt.Err++ } 'RebootRequired' { $cnt.Rbt++ } default { $cnt.None++ } } }
$patchDen = $cnt.Full + $cnt.Pend + $cnt.Err + $cnt.Rbt
$patchPct = if ($patchDen) { [math]::Round(100 * $cnt.Full / $patchDen) } else { 0 }
$avOk = @($pcs | Where-Object { [string]$_.antivirus.antivirusStatus -eq 'RunningAndUpToDate' }).Count
$avPct = if ($n) { [math]::Round(100 * $avOk / $n) } else { 0 }
$reboot = @($pcs | Where-Object { $_.rebootRequired -or [string]$_.patchManagement.patchStatus -eq 'RebootRequired' }).Count
$checkPct = if ($n) { 100 * ($n - $staleList.Count) / $n } else { 0 }
$rebootPct = if ($n) { 100 * ($n - $reboot) / $n } else { 100 }
$score = [math]::Round(0.4 * $patchPct + 0.3 * $avPct + 0.2 * $checkPct + 0.1 * $rebootPct)
$label = if ($score -ge 85) { 'Excellent' } elseif ($score -ge 70) { 'Good' } elseif ($score -ge 50) { 'Fair' } else { 'Poor' }
$scoreColor = if ($score -ge 85) { '#22c55e' } elseif ($score -ge 70) { '#14b8a6' } elseif ($score -ge 50) { '#f59e0b' } else { '#ef4444' }
$siteCount = @($pcs | ForEach-Object { $_.siteName } | Select-Object -Unique).Count

# Operating systems
$osb = [ordered]@{ 'Windows 11' = 0; 'Windows 10' = 0; 'Windows Server' = 0; 'macOS' = 0; 'Other' = 0 }
foreach ($d in $pcs) { $os = [string]$d.operatingSystem; if ($os -match 'Server') { $osb['Windows Server']++ } elseif ($os -match 'Windows 11') { $osb['Windows 11']++ } elseif ($os -match 'Windows 10') { $osb['Windows 10']++ } elseif ($os -match '(?i)mac') { $osb['macOS']++ } else { $osb['Other']++ } }
$osTop = @($osb.GetEnumerator() | Where-Object { $_.Value -gt 0 } | Sort-Object Value -Descending | Select-Object -First 4)

# Needs attention
$need = New-Object System.Collections.Generic.List[object]
function SeenTxt { param($d) if (-not $d.lastSeen) { return 'never' }; $t = Local ([DateTimeOffset]::FromUnixTimeMilliseconds([int64]$d.lastSeen).UtcDateTime); if ($d.online) { return 'Online now' }; if ($t.Year -eq $nowL.Year) { return $t.ToString('MMM d') }; return $t.ToString('MMM d, yyyy') }
foreach ($d in $pcs) {
    $ps = [string]$d.patchManagement.patchStatus; $av = [string]$d.antivirus.antivirusStatus
    $days = if ($d.lastSeen) { [int]($nowUtc - [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$d.lastSeen).UtcDateTime).TotalDays } else { 9999 }
    $issue = $null; $sev = 0
    if ($ps -eq 'InstallError') { $issue = 'Patch install errors'; $sev = 3 }
    elseif ($av -and $av -ne 'RunningAndUpToDate') { $issue = $(if ($av -eq 'NotDetected') { 'No antivirus detected' } elseif ($av -eq 'NotRunning') { 'Antivirus not running' } else { 'Antivirus out of date' }); $sev = 3 }
    elseif ($d.rebootRequired -or $ps -eq 'RebootRequired') { $issue = 'Reboot required'; $sev = 2 }
    elseif (-not $d.online -and $days -gt 30) { $issue = "Not seen in $days days"; $sev = $(if ($days -gt 180) { 1 } else { 2 }) }
    elseif ([string]$d.operatingSystem -match 'Windows 10') { $issue = 'Windows 10, end of support'; $sev = 1 }
    elseif ($ps -eq 'NoPolicy') { $issue = 'No patch policy'; $sev = 1 }
    if ($issue) { $need.Add([pscustomobject]@{ name = [string]$d.hostname; issue = $issue; seen = (SeenTxt $d); sev = $sev; days = $days }) }
}
$needTop = @($need | Sort-Object @{ Expression = 'sev'; Descending = $true }, @{ Expression = 'days'; Descending = $false } | Select-Object -First 6)

# ---- Automatic remediation ----
$started = New-Object System.Collections.Generic.List[string]
if ($remediate -and $confirm) {
    try {
        $comp = @((DGet '/api/v2/account/components?max=250').components) | Where-Object { $_.name -eq $fixComponent } | Select-Object -First 1
        if (-not $comp) { $warnings.Add("Remediation skipped: add '$fixComponent' to the Datto RMM component library.") }
        else {
            $recent = @($history | Where-Object { $_.ts -and ([datetime]$_.ts) -gt $nowUtc.AddHours(-24) } | ForEach-Object { $_.devUid })
            if (-not $fixDevices.Count -and -not $fixAll) { $warnings.Add('Remediation skipped: name the devices in remediateDevices, or set remediateAll to true.') }
            $targets = @($pcs | Where-Object { $ps = [string]$_.patchManagement.patchStatus; $listed = $fixDevices -contains [string]$_.hostname; $_.online -and [string]$_.operatingSystem -notmatch '(?i)mac' -and $recent -notcontains $_.uid -and (($listed -and $ps -ne 'FullyPatched') -or ($fixAll -and @('InstallError', 'ApprovedPending', 'RebootRequired') -contains $ps)) } | Select-Object -First $maxFixes)
            foreach ($d in $targets) {
                $vars = @(@($comp.variables) | Where-Object { $_ } | ForEach-Object { @{ name = $_.name; value = [string]$_.defaultVal } })
                $body = @{ jobName = "Device Health: Windows Update repair"; jobComponent = @{ componentUid = $comp.uid; variables = $vars } } | ConvertTo-Json -Depth 6
                try {
                    $job = Invoke-RestMethod -Method PUT -Uri "$base/api/v2/device/$($d.uid)/quickjob" -Headers $dh -ContentType 'application/json' -Body $body
                    $jid = [string](P (P $job 'job') 'uid')
                    $history = @([pscustomobject]@{ ts = $nowUtc.ToString('o'); when = $nowL.ToString('MMM d h:mm tt'); dev = [string]$d.hostname; devUid = [string]$d.uid; what = 'Windows Update repair'; res = 'Running'; job = $jid }) + @($history)
                    $started.Add([string]$d.hostname)
                } catch { $warnings.Add("Remediation not started on $($d.hostname): $($_.Exception.Message)") }
            }
        }
    } catch { $warnings.Add("Remediation skipped: $($_.Exception.Message)") }
}
$history = @($history | Select-Object -First 20)
$week = @($history | Where-Object { $_.ts -and ([datetime]$_.ts) -gt $nowUtc.AddDays(-7) })
$weekDone = @($week | Where-Object { $_.res -ne 'Running' })
$fixRate = if ($weekDone.Count) { [math]::Round(100 * @($weekDone | Where-Object { $_.res -eq 'Success' }).Count / $weekDone.Count) } else { 100 }

# ---- Tokens ----
$T = [ordered]@{}
$T.DHUpdated = $nowL.ToString('MMM d, h:mm tt') + $(if ($tzLabel) { " $tzLabel" } else { '' }); $T.DHSource = 'Datto RMM'
$T.DHScoreNum = [string]$score; $T.DHScoreColor = $scoreColor; $T.DHScoreLabel = $label
$T.DHDevices = [string]$n; $T.DHNoteDevices = "$siteCount site$(if ($siteCount -ne 1) { 's' })"
$T.DHOnline = [string]$online; $T.DHNoteOnline = "$($n - $online) offline"
$T.DHPatchPct = [string]$patchPct; $T.DHNotePatch = "$($cnt.Full) of $patchDen with a patch policy"
$T.DHAvPct = [string]$avPct; $T.DHNoteAv = "$avOk of $n running and up to date"
$T.DHReboot = [string]$reboot; $T.DHNoteReboot = $(if ($reboot -eq 1) { 'needs a restart' } else { 'need a restart' })
$T.DHStale = [string]$staleList.Count; $T.DHNoteStale = 'not seen in 30+ days'
$mx = [math]::Max(1, ($cnt.Values | Measure-Object -Maximum).Maximum)
foreach ($k in 'Full', 'Pend', 'Err', 'Rbt', 'None') { $T["DHPatchN$k"] = [string]$cnt[$k]; $T["DHPatchBar$k"] = [string][math]::Round(100 * $cnt[$k] / $mx) }
for ($i = 1; $i -le 4; $i++) { $e = if ($i -le $osTop.Count) { $osTop[$i - 1] } else { $null }; $T["DHOsName$i"] = $(if ($e) { $e.Key } else { '' }); $T["DHOsN$i"] = $(if ($e) { [string]$e.Value } else { '' }); $T["DHOsPct$i"] = $(if ($e -and $n) { [string][math]::Round(100 * $e.Value / $n) } else { '' }) }
$SEV = @{ 3 = @('High', '#fee2e2', '#991b1b'); 2 = @('Medium', '#fef3c7', '#92400e'); 1 = @('Low', '#e0f2fe', '#075985') }
for ($i = 1; $i -le 6; $i++) { $e = if ($i -le $needTop.Count) { $needTop[$i - 1] } else { $null }
    if ($e) { $s = $SEV[[int]$e.sev]; $T["DHNeedName$i"] = $e.name; $T["DHNeedIssue$i"] = $e.issue; $T["DHNeedSeen$i"] = $e.seen; $T["DHNeedSev$i"] = $s[0]; $T["DHNeedBg$i"] = $s[1]; $T["DHNeedFg$i"] = $s[2] }
    else { $T["DHNeedName$i"] = $(if ($i -eq 1) { 'All devices look healthy' } else { '' }); $T["DHNeedIssue$i"] = ''; $T["DHNeedSeen$i"] = ''; $T["DHNeedSev$i"] = ''; $T["DHNeedBg$i"] = '#ffffff'; $T["DHNeedFg$i"] = '#ffffff' } }
$T.DHFixWeek = [string]$week.Count; $T.DHFixRate = [string]$fixRate; $T.DHFixLast = $nowL.ToString('MMM d, h:mm tt')
$RES = @{ Success = @('#dcfce7', '#166534'); Failed = @('#fee2e2', '#991b1b'); Running = @('#e0f2fe', '#075985') }
for ($i = 1; $i -le 5; $i++) { $e = if ($i -le $history.Count) { $history[$i - 1] } else { $null }
    if ($e) { $c = $RES[[string]$e.res]; if (-not $c) { $c = $RES.Running }; $T["DHFixWhen$i"] = [string]$e.when; $T["DHFixDev$i"] = [string]$e.dev; $T["DHFixWhat$i"] = [string]$e.what; $T["DHFixRes$i"] = [string]$e.res; $T["DHFixBg$i"] = $c[0]; $T["DHFixFg$i"] = $c[1] }
    else { $T["DHFixWhen$i"] = ''; $T["DHFixDev$i"] = $(if ($i -eq 1) { 'No fixes needed yet' } else { '' }); $T["DHFixWhat$i"] = ''; $T["DHFixRes$i"] = ''; $T["DHFixBg$i"] = '#ffffff'; $T["DHFixFg$i"] = '#ffffff' } }
$T.DHHistory = (ConvertTo-Json -InputObject @($history) -Depth 4 -Compress)

$written = 0
if ($confirm) { foreach ($k in $T.Keys) { try { Set-Tok $k ([string]$T[$k]); $written++ } catch { $warnings.Add("Token $k not written: $($_.Exception.Message)") } } }

$summary = "Device health $score ($label): $n devices, $online online, $patchPct% fully patched, $avPct% antivirus OK, $reboot reboot pending, $($staleList.Count) not checking in.$(if ($started.Count) { " Windows Update repair started on $($started -join ', ')." })"

# ---- Signal summary ----
$signaled = $false
if ($confirm -and $notifyUsers.Count) {
    try {
        $sb = @{ companyIds = @($companyId); users = @($notifyUsers); priority = 0; title = $(if ($started.Count) { "Device health: $($started.Count) fix$(if ($started.Count -ne 1) { 'es' }) started" } else { "Device health score: $score" }); body = $summary; expiresAt = $nowUtc.AddDays(1).ToString('o'); dedupeKey = "devhealth-$companyId-$($nowUtc.ToString('yyyyMMddHHmm'))" } | ConvertTo-Json -Depth 5
        $null = Invoke-RestMethod -Method Post -Uri "$crB/v2/signalmessage" -Headers $crH -ContentType 'application/json' -Body $sb; $signaled = $true
    } catch { $warnings.Add("Signal not sent: $($_.Exception.Message)") }
}

Set-NodeOutput ([ordered]@{
    status = $(if ($confirm) { 'success' } else { 'preview' }); message = $summary; companyId = $companyId
    score = $score; devices = $n; online = $online; patchPct = $patchPct; avPct = $avPct; reboot = $reboot; stale = $staleList.Count
    remediationStarted = @($started); tokensWritten = $written; signalSent = $signaled; warnings = @($warnings)
    needsAttention = @($needTop); internal_note = "Device Health refresh for company $($companyId): $summary"
})
