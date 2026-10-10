# Strict-mode harness for Waiting-on-Client Nudge. Runs the four steps exactly as shipped in
# ../waiting-on-client-nudge.yml (via build.js --dump), each through & ([scriptblock]::Create(...)) under
# Set-StrictMode -Version Latest, against the mock PSAs in mock-psa.ps1.
# Usage: pwsh -NoProfile -File test.ps1      (needs node and js-yaml: npm install here, or set JS_YAML_PATH)
. (Join-Path $PSScriptRoot 'mock-psa.ps1')

& node (Join-Path $PSScriptRoot 'build.js') --check
Check 'the .yml matches the source (build.js --check)' ($LASTEXITCODE -eq 0)
Import-Steps (Join-Path $PSScriptRoot 'build.js')
Check 'four PowerShell steps' ($MockSteps.Count -eq 4) ($MockSteps.Keys -join ', ')

$Waiting = @{ connectwise = 'Waiting Customer'; autotask = 'Waiting Customer'; halopsa = 'Waiting on User'; kaseyabms = 'Waiting on Customer'; syncro = 'Waiting on Customer'; zendesk = 'pending' }
# Old style (before public notes switched to the opaque ref): the marker on the public note itself. Still read.
function Get-Marker { param([string]$Tag, [double]$SinceDays) return "Reminder text.`n[waiting-nudge: $Tag, waiting since $(Get-Stamp (Get-Ago $SinceDays))]" }
# New style: the public reminder shows only an opaque Ref line; the companion internal note holds the marker.
function Get-PubReminder { param($Id) return "Hello,`n`nWe're following up on ticket #$Id. We're waiting on a reply from you before we can go any further.`nRef: 0a1b2c3d" }
function Get-IntMarker { param([string]$Tag, [double]$SinceDays) return "Waiting-on-Client Nudge sent a reminder.`n[waiting-nudge: $Tag, waiting since $(Get-Stamp (Get-Ago $SinceDays))]" }
# A client-visible note: our wording, then only the opaque ref; no marker, tag, address or internal status word.
function Test-CleanPublic { param([string]$Text) return ($Text -notmatch '\[|waiting-nudge|@|closing notice|close held|failed' -and $Text -cmatch "`nRef: [0-9a-f]{8}$") }

# The standard world. Expected on a first run with the defaults (reminders 2,4; close 7):
#   101 remind day 2   102 remind day 4   103 close with notice   104 client replied: skip
#   105 P1 at day 9: hold (no close)   106 day 2 sent, day 3 now: nothing due   107 other status: never touched
#   108 created yesterday: not listed
function New-StandardWorld {
    param([string]$Psa)
    Reset-World $Psa
    $w = $Waiting[$Psa]
    $null = Add-WorldTicket 101 $w -Created 10 -Notes @(@{ d = 3; who = 'tech'; text = 'Could you send a screenshot of the error?' })
    $null = Add-WorldTicket 102 $w -Created 12 -Notes @(@{ d = 5; who = 'tech'; text = 'Which printer is it?' }, @{ d = 3; who = 'marker'; text = (Get-PubReminder 102) }, @{ d = 3; who = 'marker'; internal = $true; text = (Get-IntMarker 'day 2' 5) })
    $null = Add-WorldTicket 103 $w -Created 20 -Notes @(@{ d = 8; who = 'tech'; text = 'Please restart and tell us if it helps.' }, @{ d = 6; who = 'marker'; text = (Get-PubReminder 103) }, @{ d = 6; who = 'marker'; internal = $true; text = (Get-IntMarker 'day 2' 8) }, @{ d = 4; who = 'marker'; text = (Get-PubReminder 103) }, @{ d = 4; who = 'marker'; internal = $true; text = (Get-IntMarker 'day 4' 8) })
    $null = Add-WorldTicket 104 $w -Created 10 -Notes @(@{ d = 6; who = 'tech'; text = 'Can you confirm the user name?' }, @{ d = 4; who = 'marker'; text = (Get-Marker 'day 2' 6) }, @{ d = 1; who = 'client'; text = 'It is pat@contoso.example.' })
    $null = Add-WorldTicket 105 $w -Prio critical -Created 20 -Notes @(@{ d = 9; who = 'tech'; text = 'Is the server back up?' }, @{ d = 7; who = 'marker'; text = (Get-PubReminder 105) }, @{ d = 7; who = 'marker'; internal = $true; text = (Get-IntMarker 'day 2' 9) }, @{ d = 5; who = 'marker'; text = (Get-PubReminder 105) }, @{ d = 5; who = 'marker'; internal = $true; text = (Get-IntMarker 'day 4' 9) })
    $null = Add-WorldTicket 106 $w -Created 10 -Notes @(@{ d = 3; who = 'tech'; text = 'Any update?' }, @{ d = 1; who = 'marker'; text = (Get-Marker 'day 2' 3) })
    $null = Add-WorldTicket 107 'In Progress' -Created 20 -Notes @(@{ d = 10; who = 'tech'; text = 'Working on it.' })
    $null = Add-WorldTicket 108 $w -Created 0.5 -Notes @()
}
function Get-Action { param($Out, $Id) return @($Out.actions | Where-Object { [string]$_.ticket_id -eq [string]$Id }) | Select-Object -First 1 }

# ---- 1. Preview on every PSA: the plan is right and nothing is written ----
foreach ($psa in @('connectwise', 'autotask', 'halopsa', 'kaseyabms', 'syncro', 'zendesk')) {
    New-StandardWorld $psa
    $out = Invoke-Workflow ([pscustomobject]@{ preview = $true })
    Check "$psa preview: status pending_confirmation" ($out.status -eq 'pending_confirmation') $out.message
    Check "$psa preview: nothing written" (@(Get-Writes).Count -eq 0) (@(Get-Writes | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')
    $a = Get-Action $out 101; Check "$psa preview: 101 gets the day 2 reminder" ($null -ne $a -and $a.action -eq 'remind' -and $a.result -like 'reminder 1 of 2 (day 2)*') ($a | ConvertTo-Json -Compress)
    $a = Get-Action $out 102; Check "$psa preview: 102 gets the day 4 reminder, not day 2 again" ($null -ne $a -and $a.result -like 'reminder 2 of 2 (day 4)*') ($a | ConvertTo-Json -Compress)
    $a = Get-Action $out 103; Check "$psa preview: 103 is closed with a notice" ($null -ne $a -and $a.action -eq 'close' -and $a.result -like 'closing notice: would send; close: would close*') ($a | ConvertTo-Json -Compress)
    $a = Get-Action $out 105; Check "$psa preview: P1 ticket 105 is held, not closed" ($null -ne $a -and $a.action -eq 'hold') ($a | ConvertTo-Json -Compress)
    foreach ($id in @(104, 106, 107, 108)) { Check "$psa preview: no action on $id" ($null -eq (Get-Action $out $id)) }
    if ($psa -ne 'kaseyabms') { Check "$psa preview: 104 skipped because the client replied" (@($out.skipped | Where-Object { [string]$_.ticketId -eq '104' -and $_.reason -eq 'client replied' }).Count -eq 1) ($out.skipped | ConvertTo-Json -Compress) }
    Check "$psa preview: message says preview" ($out.message -like 'Preview only, nothing was changed.*would send 2 reminders, would close 1 ticket*') $out.message
}

# ---- 2. Live run on ConnectWise: the right writes, then a second run writes nothing ----
New-StandardWorld 'connectwise'
$out = Invoke-Workflow $null
$cw = $MockBase.connectwise
Check 'cw live: status success' ($out.status -eq 'success') "$($out.status): $($out.message) $($out.warnings -join ' | ')"
$pub = @(Get-Writes "POST $cw/service/tickets/*/notes" | Where-Object { $_.Body.detailDescriptionFlag -eq $true })
$pub = @($pub | Sort-Object { ($_.Uri -split '/')[-2] })   # tickets are listed oldest first, so sort by id
Check 'cw live: three public notes (101, 102, 103)' ((@($pub | ForEach-Object { ($_.Uri -split '/')[-2] } | Sort-Object) -join ',') -eq '101,102,103') (@($pub | ForEach-Object { $_.Uri }) -join '; ')
Check 'cw live: 101 reminder says when it closes and ends with only the opaque ref' ((Test-CleanPublic $pub[0].Body.text) -and $pub[0].Body.text -like '*close this ticket on*') $pub[0].Body.text
Check 'cw live: 102 and 103 public notes carry no marker, tag or address' ((Test-CleanPublic $pub[1].Body.text) -and (Test-CleanPublic $pub[2].Body.text)) "$($pub[1].Body.text) || $($pub[2].Body.text)"
Check 'cw live: 103 gets the closing notice' ($pub[2].Body.text -like "*so we're closing it*")
$patch = @(Get-Writes "PATCH $cw/service/tickets/*")
Check 'cw live: only 103 is closed, to Closed (not Resolved)' ($patch.Count -eq 1 -and $patch[0].Uri -like '*/103' -and $patch[0].Body[0].value.id -eq 13 -and (Get-WorldTicket 103).status -eq 'Closed') ($patch | ConvertTo-Json -Depth 5 -Compress)
$int = @(Get-Writes "POST $cw/service/tickets/*/notes" | Where-Object { $_.Body.internalAnalysisFlag -eq $true })
Check 'cw live: internal notes on 101, 102, 103 (notice and closed) and 105' ((@($int | ForEach-Object { ($_.Uri -split '/')[-2] } | Sort-Object) -join ',') -eq '101,102,103,103,105') (@($int | ForEach-Object { $_.Uri }) -join '; ')
$intText = { param($Id) @($int | Where-Object { $_.Uri -like "*/$Id/notes" } | ForEach-Object { [string]$_.Body.text }) -join ' || ' }
Check 'cw live: the readable markers are on the companion internal notes' ((& $intText 101) -match '\[waiting-nudge: day 2, waiting since ' -and (& $intText 102) -match '\[waiting-nudge: day 4, waiting since ' -and (& $intText 103) -match '\[waiting-nudge: closing notice, ' -and (& $intText 103) -match '\[waiting-nudge: closed, ') "$(& $intText 101) ## $(& $intText 103)"
Check 'cw live: 105 internal note asks a technician to follow up' (@($int | Where-Object { $_.Uri -like '*/105/notes' })[0].Body.text -like "*priority is 'Priority 1 - Emergency Response', so*didn't close it*" -and (@($int | Where-Object { $_.Uri -like '*/105/notes' })[0].Body.text -match '\[waiting-nudge: close held, ')) (@($int | Where-Object { $_.Uri -like '*/105/notes' })[0].Body.text)
Check 'cw live: nothing written on 104, 106, 107, 108' (@(Get-Writes | Where-Object { $_.Uri -match '/(104|106|107|108)(/|$)' }).Count -eq 0)
Check 'cw live: message' ($out.message -like "Checked 6 tickets in 'Waiting Customer' in ConnectWise: sent 2 reminders, closed 1 ticket and flagged 1 high-priority ticket for a technician instead of closing them. 1 ticket was skipped because the client had replied.") $out.message
Check 'cw live: counts' ($out.counts.reminded -eq 2 -and $out.counts.closed -eq 1 -and $out.counts.held -eq 1 -and $out.counts.failed -eq 0) ($out.counts | ConvertTo-Json -Compress)
Check 'cw live: warning names the ticket the client replied on' (@($out.warnings | Where-Object { $_ -like '*#104*client replied*' }).Count -eq 1) ($out.warnings -join ' | ')
$MockWorld.writes.Clear()
$out2 = Invoke-Workflow $null
Check 'cw second run: no reminder is sent twice and nothing is written' (@(Get-Writes).Count -eq 0 -and $out2.status -eq 'success') (@(Get-Writes | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')

# ---- 3. Live run on Zendesk (a second PSA) ----
New-StandardWorld 'zendesk'
$out = Invoke-Workflow ([pscustomobject]@{ preview = 'false' })
$zd = $MockBase.zendesk
Check 'zendesk live: status success' ($out.status -eq 'success') "$($out.message) $($out.warnings -join ' | ')"
$pubz = @(Get-Writes "PUT $zd/tickets/*" | Where-Object { $_.Body.ticket.PSObject.Properties['comment'] -and $_.Body.ticket.comment.public -eq $true })
Check 'zendesk live: public comments on 101, 102, 103' ((@($pubz | ForEach-Object { ($_.Uri -split '/')[-1] } | Sort-Object) -join ',') -eq '101,102,103')
$st = @(Get-Writes "PUT $zd/tickets/*" | Where-Object { $_.Body.ticket.PSObject.Properties['status'] })
Check 'zendesk live: 103 set to solved' ($st.Count -eq 1 -and $st[0].Uri -like '*/103' -and $st[0].Body.ticket.status -eq 'solved')
$intz = @(Get-Writes "PUT $zd/tickets/*" | Where-Object { $_.Body.ticket.PSObject.Properties['comment'] -and $_.Body.ticket.comment.public -eq $false })
Check 'zendesk live: private notes on 101, 102, 103 (notice and closed), 105' ((@($intz | ForEach-Object { ($_.Uri -split '/')[-1] } | Sort-Object) -join ',') -eq '101,102,103,103,105')
Check 'zendesk live: public comments carry no marker, tag or address' (@($pubz | Where-Object { -not (Test-CleanPublic ([string]$_.Body.ticket.comment.body)) }).Count -eq 0) (@($pubz | ForEach-Object { $_.Body.ticket.comment.body }) -join ' || ')
$MockWorld.writes.Clear(); $out2 = Invoke-Workflow $null
Check 'zendesk second run: nothing written' (@(Get-Writes).Count -eq 0) (@(Get-Writes | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')

# ---- 4. A failed close is retried without a second notice ----
New-StandardWorld 'connectwise'
$MockWorld.fail = "$cw/service/tickets/103"   # the PATCH (and the GET before it) are refused
$out = Invoke-Workflow $null
Check 'cw close refused: run is incomplete' ($out.status -eq 'incomplete') $out.status
Check 'cw close refused: failure note is internal and says it will retry' (@(Get-Writes "POST $cw/service/tickets/103/notes" | Where-Object { $_.Body.internalAnalysisFlag -and $_.Body.text -like "*couldn't close*retry the close*" -and $_.Body.text -match '\[waiting-nudge: failed, ' }).Count -eq 1)
$MockWorld.fail = ''; $MockWorld.writes.Clear()
$out = Invoke-Workflow $null
Check 'cw retry: 103 closed, no second closing notice' ((@(Get-Writes "POST $cw/service/tickets/103/notes" | Where-Object { $_.Body.detailDescriptionFlag }).Count -eq 0) -and (Get-WorldTicket 103).status -eq 'Closed') (@(Get-Writes | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')

# ---- 4b. Two runs that overlap (or an Action Runs Retry) send the client one copy ----
# Both runs plan before either writes, so only the -Marker check in Add-PsaNote stands between them.
New-StandardWorld 'connectwise'
$planA = ConvertTo-RoundTrip (Invoke-Step 'node-find' $null)
$planB = ConvertTo-RoundTrip (Invoke-Step 'node-find' $null)
$null = Invoke-Step 'node-close' (ConvertTo-RoundTrip (Invoke-Step 'node-remind' $planA))
$MockWorld.writes.Clear()
$b2 = ConvertTo-RoundTrip (Invoke-Step 'node-remind' $planB)
$b3 = ConvertTo-RoundTrip (Invoke-Step 'node-close' $b2)
$outB = ConvertTo-RoundTrip (Invoke-Step 'node-notes' $b3)
Check 'overlap: the second run posts no public note' (@(Get-Writes "POST $cw/service/tickets/*/notes" | Where-Object { $_.Body.detailDescriptionFlag }).Count -eq 0) (@(Get-Writes | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')
Check 'overlap: the second run reports the reminders as already sent' (@($b2.plan | Where-Object { $_.remindResult -eq 'already sent' }).Count -eq 2) ($b2.plan | ConvertTo-Json -Depth 5 -Compress)
Check 'overlap: the second run reports the closing notice as sent earlier' (@($b3.plan | Where-Object { $_.action -eq 'close' -and $_.noticeResult -eq 'sent earlier' }).Count -eq 1)
Check 'overlap: no second internal reminder note' (@(Get-Writes "POST $cw/service/tickets/*/notes" | Where-Object { $_.Uri -match '/(101|102)/notes$' }).Count -eq 0)
Check 'overlap: each ticket holds one copy of each reminder and one companion note' (@((Get-WorldTicket 101).notes | Where-Object { -not $_.internal -and $_.text -like "*We're following up on*" }).Count -eq 1 -and @((Get-WorldTicket 101).notes | Where-Object { $_.internal -and $_.text -match '\[waiting-nudge: day 2, ' }).Count -eq 1 -and @((Get-WorldTicket 103).notes | Where-Object { -not $_.internal -and $_.text -like "*so we're closing it*" }).Count -eq 1 -and @((Get-WorldTicket 103).notes | Where-Object { $_.internal -and $_.text -match '\[waiting-nudge: closing notice, ' }).Count -eq 1)
Check 'overlap: no public note on any ticket shows a marker' (@($MockWorld.tickets | ForEach-Object { $_.notes } | Where-Object { -not $_.internal -and $_.text -like '*Ref: *' -and -not (Test-CleanPublic $_.text) }).Count -eq 0)

# ---- 4c. The public reminder went out but its internal note was lost: no second reminder straight away ----
New-StandardWorld 'connectwise'
$null = Add-WorldTicket 109 $Waiting.connectwise -Created 10 -Notes @(@{ d = 6; who = 'tech'; text = 'Could you check the cable?' }, @{ d = 0.01; who = 'marker'; text = (Get-PubReminder 109) })
$out = Invoke-Workflow ([pscustomobject]@{ preview = $true })
Check 'lost internal note: no second reminder straight away' ($null -eq (Get-Action $out 109) -and @($out.skipped | Where-Object { [string]$_.ticketId -eq '109' -and $_.reason -like 'nothing due*' }).Count -eq 1) ($out.skipped | ConvertTo-Json -Compress)

# ---- 5. Missing permission (403) fails with a plain message ----
New-StandardWorld 'connectwise'
$MockWorld.fail = "$cw/service/tickets?*"
$msg = Get-ThrowMessage { Invoke-Workflow $null }
Check 'cw 403: the run stops and names the HTTP 403 and the permission' ($msg -like '*HTTP 403*permission to read service tickets*') $msg
Check 'cw 403: nothing written' (@(Get-Writes).Count -eq 0)

# ---- 6. Empty result ----
Reset-World 'connectwise'
$out = Invoke-Workflow ''
Check 'empty: success with a plain message' ($out.status -eq 'success' -and $out.message -like "No tickets in 'Waiting Customer' in ConnectWise have waited long enough*") $out.message
Check 'empty: nothing written' (@(Get-Writes).Count -eq 0)

# ---- 7. Inputs: custom days, company filter, bad input fails closed ----
New-StandardWorld 'connectwise'
$out = Invoke-Workflow ([pscustomobject]@{ preview = $true; reminder_days = '3'; close_day = 10; company = 'Contoso'; waiting_status_name = 'Waiting Customer' })
$cond = [uri]::UnescapeDataString((@($MockWorld.calls | Where-Object { $_ -like "GET $cw/service/tickets?*" })[0] -replace '^.*conditions=([^&]*).*$', '$1'))
Check 'inputs: company name resolved to its id in the list filter' ($cond -like 'company/id=42 and status/name="Waiting Customer" and dateEntered<`[*`]') $cond
Check 'inputs: with close_day 10, 103 (day 8, day 4 sent) gets nothing' ($null -eq (Get-Action $out 103))
Check 'inputs: 101 (day 3) gets reminder 1 of 1 (day 3)' ((Get-Action $out 101).result -like 'reminder 1 of 1 (day 3)*') ((Get-Action $out 101) | ConvertTo-Json -Compress)
$msg = Get-ThrowMessage { Invoke-Workflow ([pscustomobject]@{ reminder_days = '2,6'; close_day = 5 }) }
Check 'inputs: close_day before the last reminder is rejected' ($msg -eq 'close_day (5) must be later than the last reminder day (6).') $msg
$msg = Get-ThrowMessage { Invoke-Workflow ([pscustomobject]@{ preview = 'maybe' }) }
Check 'inputs: a bad preview value is rejected' ($msg -like "preview must be true or false*") $msg
$msg = Get-ThrowMessage { Invoke-Workflow '{"max_tickets": 0}' }
Check 'inputs: max_tickets 0 is rejected' ($msg -like 'max_tickets must be a whole number from 1 to 1000*') $msg
Check 'inputs: rejected runs wrote nothing' (@(Get-Writes).Count -eq 0)

# ---- 8. max_tickets caps the run and warns ----
New-StandardWorld 'connectwise'
$out = Invoke-Workflow ([pscustomobject]@{ preview = $true; max_tickets = 2 })
Check 'max_tickets: only 2 checked, with a warning' ($out.counts.found -eq 2 -and @($out.warnings | Where-Object { $_ -like 'More than 2 tickets*' }).Count -eq 1) ($out | ConvertTo-Json -Depth 5 -Compress)

# ---- 9. A warning from the shared PSA library reaches the output and the summary note ----
# ConnectWise saves each note POST, then answers it with a redirect. The shared Add-PsaNote reads the ticket back,
# finds the note and warns. The mock is wrapped here so mock-psa.ps1 (shared with auto-close-resolved) is unchanged.
# PowerShell 7's own refusal of an https-to-http redirect (no status code, text in ErrorDetails), as ConnectWise
# staging answers a note POST it has already saved. The shared Add-PsaNote reads the ticket back and warns.
function Throw-InsecureRedirect { $er = [System.Management.Automation.ErrorRecord]::new([System.InvalidOperationException]::new(), 'InsecureRedirection,Microsoft.PowerShell.Commands.InvokeRestMethodCommand', 'InvalidOperation', $null); $er.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('Cannot follow an insecure redirection by default. Reissue the command specifying the -AllowInsecureRedirect switch.'); throw $er }
$NudgeIrm = ${function:Invoke-RestMethod}
$NudgeRedirect = @{ on = $false }
function Invoke-RestMethod {
    [CmdletBinding()] param($Method = 'GET', $Uri, $Headers, $Body, $ContentType, $Form, [int]$MaximumRedirection = -1)
    $r = & $NudgeIrm @PSBoundParameters
    if ($NudgeRedirect.on -and ([string]$Method).ToUpperInvariant() -eq 'POST' -and [string]$Uri -match '/service/tickets/\d+/notes$') { Throw-InsecureRedirect }
    if ($r -is [array]) { return , $r }   # keep a JSON array reply as ONE object, as the mock and the real cmdlet do
    return $r
}
New-StandardWorld 'connectwise'
$NudgeRedirect.on = $true
$out = Invoke-Workflow $null
$NudgeRedirect.on = $false
$sw = @(@($out.warnings) | Where-Object { $_ -match '^ConnectWise answered the note on ticket 101 with a redirect; reading the ticket back showed the note was saved' })
Check 'shared warning: a redirected note POST that was saved is in the output warnings once and in the summary note' ($out.status -eq 'success' -and $sw.Count -eq 1 -and @(@($out.warnings) | Select-Object -Unique).Count -eq @($out.warnings).Count -and $out.internal_note -match 'Warning: ConnectWise answered the note on ticket 101 with a redirect') "$($out.status) / $(@($out.warnings) -join ' | ')"

Complete-Test
