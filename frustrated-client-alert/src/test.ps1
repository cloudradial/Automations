# Strict-mode harness for Frustrated Client Alert. Runs the two PowerShell steps exactly as shipped in
# ../frustrated-client-alert.yml (via build.js --dump), each through & ([scriptblock]::Create(...)) under
# Set-StrictMode -Version Latest, against the mock PSAs in mock-psa.ps1. The AI step is stood in for by a
# fixed score JSON, the way the runner would hand it over.
# Usage: pwsh -NoProfile -File test.ps1      (needs node and js-yaml: npm install in _shared, or set JS_YAML_PATH)
. (Join-Path $PSScriptRoot 'mock-psa.ps1')
# The alert step reads its two bound parameters by name.
function Get-NodeInput { param([string]$Name) if ($Name) { return Get-PsaPropMock $MockHarness.Input $Name }; return $MockHarness.Input }
function Get-PsaPropMock { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }

& node (Join-Path $PSScriptRoot 'build.js') --check
Check 'the .yml matches the source (build.js --check)' ($LASTEXITCODE -eq 0)
Import-Steps (Join-Path $PSScriptRoot 'build.js')
Check 'two PowerShell steps: find and alert' (($MockSteps.Keys -join ',') -eq 'node-find,node-alert') ($MockSteps.Keys -join ', ')

$Open = @{ connectwise = 'In Progress'; autotask = 'In Progress'; halopsa = 'In Progress'; kaseyabms = 'In Progress'; syncro = 'In Progress'; zendesk = 'open' }
# 201 angry client reply just now     202 polite client reply just now     203 angry client reply 2 days ago (outside the window)
# 204 only a technician note just now  205 an internal note just now
function New-FcaWorld {
    param([string]$Psa)
    Reset-World $Psa
    $s = $Open[$Psa]
    $null = Add-WorldTicket 201 $s -Created 5 -Notes @(@{ d = 2; who = 'tech'; text = 'We have reset the VPN profile.' }, @{ d = 0.01; who = 'client'; text = 'This is the third time the VPN has dropped this week. If it is not fixed today we will look at other providers.' })
    $null = Add-WorldTicket 202 $s -Created 5 -Notes @(@{ d = 0.01; who = 'client'; text = 'Thanks, that worked. Have a good weekend.' })
    $null = Add-WorldTicket 203 $s -Created 5 -Notes @(@{ d = 2; who = 'client'; text = 'Still broken. Unacceptable.' })
    $null = Add-WorldTicket 204 $s -Created 5 -Notes @(@{ d = 0.01; who = 'tech'; text = 'Calling the client now.' })
    $null = Add-WorldTicket 205 $s -Created 5 -Notes @(@{ d = 0.01; who = 'client'; internal = $true; text = 'Internal: client sounds annoyed.' })
}
function Get-ReplyKey { param($Ctx, $TicketId) return [string](@($Ctx.replies | Where-Object { [string]$_.ticketId -eq [string]$TicketId }) | Select-Object -First 1).key }
function New-Score { param($Ctx, [string]$Angry = 'high') return (@{ results = @(@{ key = (Get-ReplyKey $Ctx 201); level = $Angry; reason = 'The client says the VPN failed a third time and mentions other providers.'; quote = 'If it is not fixed today we will look at other providers' }, @{ key = (Get-ReplyKey $Ctx 202); level = 'none'; reason = 'Thanks.'; quote = '' }) } | ConvertTo-Json -Depth 5 -Compress) }
$Run = [pscustomobject]@{ lookback_minutes = 240; alert_email = 'service.manager@example.com' }

# ---- 1. Find: the right replies on every PSA that marks client notes ----
foreach ($psa in @('connectwise', 'autotask', 'halopsa', 'syncro', 'zendesk')) {
    New-FcaWorld $psa
    $f = Invoke-Step 'node-find' $Run
    $ctx = $f.ctx_json | ConvertFrom-Json
    $ids = @($ctx.replies | ForEach-Object { [string]$_.ticketId }) -join ','
    Check "$psa find: only the new client replies (201, 202)" ($ids -eq '201,202' -or $ids -eq '202,201') "$ids :: $($f.message) $(@($f.warnings) -join ' | ')"
    Check "$psa find: facts carry the reply text, keyed" ($f.facts_json -match 'third time the VPN' -and $f.facts_json -match '"key":"r1"' -and $f.facts_json -notmatch 'Unacceptable') $f.facts_json
    Check "$psa find: nothing written" (@(Get-Writes).Count -eq 0)
}

# ---- 2. Alert, live on ConnectWise: one note on 201, nothing on 202, marked so a rerun skips it ----
New-FcaWorld 'connectwise'
$f = Invoke-Step 'node-find' $Run
$ctx = $f.ctx_json | ConvertFrom-Json
$a = ConvertTo-RoundTrip (Invoke-Step 'node-alert' ([pscustomobject]@{ ctx = $f.ctx_json; score = (New-Score $ctx) }))
$notes = @(Get-Writes 'POST */service/tickets/*/notes')
Check 'cw alert: one note, on 201' ($notes.Count -eq 1 -and $notes[0].Uri -like '*/tickets/201/notes') (@($notes | ForEach-Object { $_.Uri }) -join '; ')
Check 'cw alert: the note is internal and marked' ($notes.Count -eq 1 -and $notes[0].Body.internalAnalysisFlag -eq $true -and $notes[0].Body.detailDescriptionFlag -ne $true -and [string]$notes[0].Body.text -match '\[frustrated-client 201-\d+\]') ($notes | ConvertTo-Json -Depth 5 -Compress)
Check 'cw alert: note says why, quotes them, suggests a call' ($notes.Count -eq 1 -and [string]$notes[0].Body.text -match 'reads as high frustration' -and [string]$notes[0].Body.text -match 'other providers' -and [string]$notes[0].Body.text -match 'call the client today') ''
Check 'cw alert: no status, priority or owner change' (@(Get-Writes | Where-Object { $_.Method -in @('PATCH', 'PUT') }).Count -eq 0) (@(Get-Writes | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')
Check 'cw alert: flagged list and message' (@($a.flagged).Count -eq 1 -and $a.message -like '1 ticket(s) with a frustrated client (1 high), from 2 new client replies*') $a.message

# ---- 2b. Several frustrated replies on one ticket: one note, every reply marked, none picked up again ----
New-FcaWorld 'connectwise'
Add-WorldNote 201 'Hello?? Anyone there? We still cannot connect.' $false
$t201 = Get-WorldTicket 201; $t201.notes[-1].client = $true; $t201.notes[-1].created = $MockWorld.now.AddMinutes(-90)
$f = Invoke-Step 'node-find' $Run
$ctx = $f.ctx_json | ConvertFrom-Json
$keys201 = @($ctx.replies | Where-Object { [string]$_.ticketId -eq '201' } | ForEach-Object { [string]$_.key })
$score = @{ results = @(@($keys201 | ForEach-Object { @{ key = $_; level = $(if ($_ -eq $keys201[0]) { 'medium' } else { 'high' }); reason = "reason $_"; quote = "quote $_" } }) + @(@{ key = (Get-ReplyKey $ctx 202); level = 'none'; reason = ''; quote = '' })) } | ConvertTo-Json -Depth 5 -Compress
$a = ConvertTo-RoundTrip (Invoke-Step 'node-alert' ([pscustomobject]@{ ctx = $f.ctx_json; score = $score }))
$notes = @(Get-Writes 'POST */service/tickets/*/notes')
Check 'grouped: two replies on 201, one alert at the highest level' ($keys201.Count -eq 2 -and $notes.Count -eq 1 -and @($a.flagged).Count -eq 1 -and $a.flagged[0].level -eq 'high' -and [string]$notes[0].Body.text -match "last 2 replies") "$($keys201.Count) keys, $($notes.Count) notes :: $($a.message)"
Check 'grouped: the note carries both markers and both quotes' ($notes.Count -eq 1 -and ([regex]::Matches([string]$notes[0].Body.text, '\[frustrated-client 201-\d+\]')).Count -eq 2 -and ([regex]::Matches([string]$notes[0].Body.text, 'They wrote:')).Count -eq 2) ([string]$notes[0].Body.text)
$f2 = Invoke-Step 'node-find' $Run
$ctx2 = $f2.ctx_json | ConvertFrom-Json
Check 'grouped rerun: neither reply on 201 comes back' (@($ctx2.replies | Where-Object { [string]$_.ticketId -eq '201' }).Count -eq 0) (@($ctx2.replies | ForEach-Object { $_.ticketId }) -join ',')
Check 'cw alert: without Postmark the email is skipped with a reason' (@($a.warnings | Where-Object { $_ -like "The alert email wasn't sent*" }).Count -eq 1 -and $a.status -eq 'partial') (@($a.warnings) -join ' | ')

$f2 = Invoke-Step 'node-find' $Run
$ctx2 = $f2.ctx_json | ConvertFrom-Json
Check 'cw rerun: the alerted reply is not picked up again' ((@($ctx2.replies | ForEach-Object { [string]$_.ticketId }) -join ',') -eq '202') (@($ctx2.replies | ForEach-Object { $_.ticketId }) -join ',')

# ---- 3. Preview writes nothing; medium is noted but not emailed at the default level ----
New-FcaWorld 'halopsa'
$f = Invoke-Step 'node-find' ([pscustomobject]@{ lookback_minutes = 240; preview = $true; alert_email = 'service.manager@example.com' })
$ctx = $f.ctx_json | ConvertFrom-Json
$a = ConvertTo-RoundTrip (Invoke-Step 'node-alert' ([pscustomobject]@{ ctx = $f.ctx_json; score = (New-Score $ctx 'medium') }))
Check 'halo preview: nothing written' (@(Get-Writes).Count -eq 0) (@(Get-Writes | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')
Check 'halo preview: pending_confirmation and says what it would do' ($a.status -eq 'pending_confirmation' -and @($a.actions | Where-Object { $_ -like 'Preview: would note ticket #201 (medium)*' -and $_ -notlike '*alert email*' }).Count -eq 1) (@($a.actions) -join ' | ')

# ---- 4. Odd AI output and edge cases ----
New-FcaWorld 'autotask'
$f = Invoke-Step 'node-find' $Run
$a = ConvertTo-RoundTrip (Invoke-Step 'node-alert' ([pscustomobject]@{ ctx = $f.ctx_json; score = 'Sorry, I cannot help with that.' }))
Check 'garbage AI output: nothing written, a warning says so' (@(Get-Writes).Count -eq 0 -and @($a.warnings | Where-Object { $_ -like 'The AI step gave no readable scores*' }).Count -eq 1) (@($a.warnings) -join ' | ')
$ctx = $f.ctx_json | ConvertFrom-Json
$wrapped = "Here you go: $(New-Score $ctx) Hope that helps."
$a = ConvertTo-RoundTrip (Invoke-Step 'node-alert' ([pscustomobject]@{ ctx = $f.ctx_json; score = $wrapped }))
Check 'AI JSON wrapped in prose is still read' (@($a.flagged).Count -eq 1) $a.message

Reset-World 'syncro'
$f = Invoke-Step 'node-find' $Run
Check 'quiet period: the AI is told to skip' ($f.facts_json -eq '{"skip":true}' -and $f.replies -eq 0) $f.facts_json
$a = ConvertTo-RoundTrip (Invoke-Step 'node-alert' ([pscustomobject]@{ ctx = $f.ctx_json; score = '{"results": []}' }))
Check 'quiet period: success, nothing to do' ($a.status -eq 'success' -and $a.message -like 'No new client replies*') $a.message

New-FcaWorld 'kaseyabms'
$f = Invoke-Step 'node-find' $Run
Check 'kaseya: says client replies cannot be picked out' ($f.replies -eq 0 -and @($f.warnings | Where-Object { $_ -like 'Kaseya BMS notes*' }).Count -eq 1) (@($f.warnings) -join ' | ')

Check 'bad setting fails early with a plain message' ((Get-ThrowMessage { Invoke-Step 'node-find' ([pscustomobject]@{ lookback_minutes = 2 }) }) -like 'lookback_minutes must be a whole number from 5 to 1440*')
Check 'bad email_level fails early' ((Get-ThrowMessage { Invoke-Step 'node-find' ([pscustomobject]@{ email_level = 'loud' }) }) -like 'email_level must be high, medium or none*')

Complete-Test
