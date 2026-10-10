# Strict-mode harness for Auto-Close Resolved. Runs the three steps exactly as shipped in
# ../auto-close-resolved.yml (via build.js --dump), each through & ([scriptblock]::Create(...)) under
# Set-StrictMode -Version Latest, against the mock PSAs in mock-psa.ps1.
# Usage: pwsh -NoProfile -File test.ps1      (needs node and js-yaml: npm install here, or set JS_YAML_PATH)
. (Join-Path $PSScriptRoot 'mock-psa.ps1')

& node (Join-Path $PSScriptRoot 'build.js') --check
Check 'the .yml matches the source (build.js --check)' ($LASTEXITCODE -eq 0)
Import-Steps (Join-Path $PSScriptRoot 'build.js')
Check 'three PowerShell steps' ($MockSteps.Count -eq 3) ($MockSteps.Keys -join ', ')

# Syncro's own Resolved status is already closed, so its world uses a custom "Pending Close" status.
$Resolved = @{ connectwise = 'Resolved'; autotask = 'Resolved'; halopsa = 'Resolved'; kaseyabms = 'Resolved'; syncro = 'Pending Close'; zendesk = 'solved' }
$RunIn = @{ syncro = @{ resolved_status_name = 'Pending Close' } }
function Get-RunInput { param([string]$Psa, [hashtable]$Extra = @{}) $h = @{}; if ($RunIn.Contains($Psa)) { foreach ($k in $RunIn[$Psa].Keys) { $h[$k] = $RunIn[$Psa][$k] } }; foreach ($k in $Extra.Keys) { $h[$k] = $Extra[$k] }; return [pscustomobject]$h }
function Get-Marker { param([string]$Tag, [double]$SinceDays) return "Note text.`n[auto-close-resolved: $Tag, resolved since $(Get-Stamp (Get-Ago $SinceDays))]" }
# The public final notice as it now looks: our wording, then only the opaque ref.
function Get-PubNotice { param($Id) return "Hello,`n`nWe marked ticket #$Id as resolved 5 days ago and haven't heard back, so we're closing it now.`nRef: 0a1b2c3d" }
# A client-visible note: no marker, tag, address or internal status word, and it ends with only the opaque ref.
function Test-CleanPublic { param([string]$Text) return ($Text -notmatch '\[|auto-close-resolved|@|final notice|failed' -and $Text -cmatch "`nRef: [0-9a-f]{8}$") }

# The standard world. Expected on a first run with the defaults (resolved_days 3, max_resolved_days 30):
#   201 close with notice   202 notice sent and close failed earlier: close only, no second notice
#   203 client replied after resolution: skip   204 resolved yesterday: not listed   205 resolved 60 days ago: not listed
#   206 other status: never touched   207 P1, resolved 5 days: closed (no priority rule here)
function New-StandardWorld {
    param([string]$Psa)
    Reset-World $Psa
    $r = $Resolved[$Psa]
    $null = Add-WorldTicket 201 $r -Created 10 -Notes @(@{ d = 4; who = 'tech'; text = 'Fixed: the printer driver was reinstalled.' })
    $null = Add-WorldTicket 202 $r -Created 20 -Notes @(@{ d = 10; who = 'tech'; text = 'Fixed: the mailbox was restored.' }, @{ d = 5; who = 'marker'; text = (Get-PubNotice 202) }, @{ d = 5; who = 'marker'; internal = $true; text = (Get-Marker 'closed' 10) }, @{ d = 5; who = 'marker'; internal = $true; text = (Get-Marker 'failed' 10) })
    $null = Add-WorldTicket 203 $r -Created 10 -Notes @(@{ d = 6; who = 'tech'; text = 'Fixed: VPN profile updated.' }, @{ d = 4; who = 'client'; text = 'It is still not connecting.' })
    $null = Add-WorldTicket 204 $r -Created 5 -Notes @(@{ d = 1; who = 'tech'; text = 'Fixed: password reset.' })
    $null = Add-WorldTicket 205 $r -Created 90 -Notes @(@{ d = 60; who = 'tech'; text = 'Fixed long ago.' })
    $null = Add-WorldTicket 206 'In Progress' -Created 20 -Notes @(@{ d = 10; who = 'tech'; text = 'Working on it.' })
    $null = Add-WorldTicket 207 $r -Prio critical -Created 10 -Notes @(@{ d = 5; who = 'tech'; text = 'Fixed: server back up.' })
}
function Get-Action { param($Out, $Id) return @($Out.actions | Where-Object { [string]$_.ticket_id -eq [string]$Id }) | Select-Object -First 1 }
function Get-WriteList { return (@(Get-Writes | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ') }

# ---- 1. Preview on every PSA: the plan is right and nothing is written ----
foreach ($psa in @('connectwise', 'autotask', 'halopsa', 'kaseyabms', 'syncro', 'zendesk')) {
    New-StandardWorld $psa
    $out = Invoke-Workflow (Get-RunInput $psa @{ preview = $true })
    Check "$psa preview: status pending_confirmation" ($out.status -eq 'pending_confirmation') "$($out.message) $($out.warnings -join ' | ')"
    Check "$psa preview: nothing written" (@(Get-Writes).Count -eq 0) (Get-WriteList)
    $a = Get-Action $out 201; Check "$psa preview: 201 closes with a notice" ($null -ne $a -and $a.result -eq 'final notice: would send; close: would close') ($a | ConvertTo-Json -Compress)
    $a = Get-Action $out 202; Check "$psa preview: 202 closes without a second notice" ($null -ne $a -and $a.result -eq 'final notice: sent earlier; close: would close') ($a | ConvertTo-Json -Compress)
    $a = Get-Action $out 207; Check "$psa preview: 207 closes" ($null -ne $a) ($out.actions | ConvertTo-Json -Compress)
    foreach ($id in @(204, 205, 206)) { Check "$psa preview: no action on $id" ($null -eq (Get-Action $out $id)) }
    if ($psa -ne 'kaseyabms') {
        Check "$psa preview: 203 left open because the client replied" ($null -eq (Get-Action $out 203) -and @($out.skipped | Where-Object { [string]$_.ticketId -eq '203' -and $_.reason -eq 'client replied' }).Count -eq 1) ($out.skipped | ConvertTo-Json -Compress)
    }
    Check "$psa preview: message" ($out.message -like "Preview only, nothing was changed. Checked * would close * ticket*") $out.message
}

# ---- 2. Live run on ConnectWise ----
New-StandardWorld 'connectwise'
$cw = $MockBase.connectwise
$out = Invoke-Workflow $null
Check 'cw live: status success' ($out.status -eq 'success') "$($out.status): $($out.message) $($out.warnings -join ' | ')"
$pub = @(Get-Writes "POST $cw/service/tickets/*/notes" | Where-Object { $_.Body.detailDescriptionFlag -eq $true } | Sort-Object { ($_.Uri -split '/')[-2] })
Check 'cw live: final notices on 201 and 207 only' ((@($pub | ForEach-Object { ($_.Uri -split '/')[-2] }) -join ',') -eq '201,207') (Get-WriteList)
Check 'cw live: the notice is plain and ends with only the opaque ref' ($pub[0].Body.text -like "*as resolved 4 days ago and haven't heard back, so we're closing it now*" -and (Test-CleanPublic $pub[0].Body.text) -and (Test-CleanPublic $pub[1].Body.text)) "$($pub[0].Body.text) || $($pub[1].Body.text)"
Check 'cw live: the closing internal note keeps the readable marker' (@(Get-Writes "POST $cw/service/tickets/201/notes" | Where-Object { $_.Body.internalAnalysisFlag -and $_.Body.text -match '\[auto-close-resolved: closed, resolved since ' }).Count -eq 1) (Get-WriteList)
$int = @(Get-Writes "POST $cw/service/tickets/*/notes" | Where-Object { $_.Body.internalAnalysisFlag -eq $true })
Check 'cw live: internal notes on 201 and 207' ((@($int | ForEach-Object { ($_.Uri -split '/')[-2] } | Sort-Object) -join ',') -eq '201,207') (Get-WriteList)
Check 'cw live: 202 already holds its closing note from the failed run, so no second one' ((Get-Action $out 202).internal_note -eq 'written earlier' -and @(Get-Writes "POST $cw/service/tickets/202/notes").Count -eq 0) ((Get-Action $out 202) | ConvertTo-Json -Compress)
$patch = @(Get-Writes "PATCH $cw/service/tickets/*")
Check 'cw live: 201, 202, 207 moved to Closed, not left in Resolved' ((@($patch | ForEach-Object { ($_.Uri -split '/')[-1] } | Sort-Object) -join ',') -eq '201,202,207' -and @($patch | Where-Object { $_.Body[0].value.id -ne 13 }).Count -eq 0) ($patch | ConvertTo-Json -Depth 5 -Compress)
Check 'cw live: nothing written on 203, 204, 205, 206' (@(Get-Writes | Where-Object { $_.Uri -match '/(203|204|205|206)(/|$)' }).Count -eq 0) (Get-WriteList)
Check 'cw live: list asks for the status and both date bounds' (@($MockWorld.calls | Where-Object { $_ -like "GET $cw/service/tickets?*" -and [uri]::UnescapeDataString($_) -like '*status/name="Resolved" and lastUpdated>=`[*`] and lastUpdated<`[*`]*' }).Count -ge 1) (@($MockWorld.calls)[0..2] -join ' ; ')
Check 'cw live: message' ($out.message -eq "Checked 4 tickets in 'Resolved' in ConnectWise and closed 3 tickets after a final notice to the client. 1 ticket was left open because the client had replied.") $out.message
$MockWorld.writes.Clear()
$out2 = Invoke-Workflow $null
Check 'cw second run: nothing written' (@(Get-Writes).Count -eq 0 -and $out2.status -eq 'success') (Get-WriteList)

# ---- 3. Live run on Zendesk: internal note goes in before the close ----
New-StandardWorld 'zendesk'
$zd = $MockBase.zendesk
$out = Invoke-Workflow ([pscustomobject]@{ preview = 'no' })
Check 'zendesk live: status success' ($out.status -eq 'success') "$($out.message) $($out.warnings -join ' | ')"
$w201 = @(Get-Writes "PUT $zd/tickets/201")
Check 'zendesk live: 201 public notice, then private note, then closed' ($w201.Count -eq 3 -and $w201[0].Body.ticket.comment.public -eq $true -and $w201[1].Body.ticket.comment.public -eq $false -and $w201[2].Body.ticket.status -eq 'closed') ($w201 | ConvertTo-Json -Depth 6 -Compress)
Check 'zendesk live: 202 gets no public comment' (@(Get-Writes "PUT $zd/tickets/202" | Where-Object { $_.Body.ticket.PSObject.Properties['comment'] -and $_.Body.ticket.comment.public }).Count -eq 0)
Check 'zendesk live: 203 untouched' (@(Get-Writes "PUT $zd/tickets/203").Count -eq 0)

# ---- 4. A failed close is retried later without a second notice ----
New-StandardWorld 'connectwise'
$MockWorld.fail = "$cw/service/tickets/201"
$out = Invoke-Workflow $null
Check 'cw close refused: run is incomplete and 201 stays resolved' ($out.status -eq 'incomplete' -and (Get-WorldTicket 201).status -eq 'Resolved') $out.status
Check 'cw close refused: failure note says it will retry' (@(Get-Writes "POST $cw/service/tickets/201/notes" | Where-Object { $_.Body.internalAnalysisFlag -and $_.Body.text -like "*couldn't close*retry the close*" -and $_.Body.text -match '\[auto-close-resolved: failed, ' }).Count -eq 1) (Get-WriteList)
$MockWorld.fail = ''; $MockWorld.writes.Clear()
(Get-WorldTicket 201).updated = Get-Ago 4   # resolved_days later, the ticket is listed again
$out = Invoke-Workflow $null
Check 'cw retry: 201 closed, no second notice' ((Get-WorldTicket 201).status -eq 'Closed' -and @(Get-Writes "POST $cw/service/tickets/201/notes" | Where-Object { $_.Body.detailDescriptionFlag }).Count -eq 0) (Get-WriteList)
Check 'cw retry: no second "closing" note (Add-PsaNote -Marker)' (@((Get-WorldTicket 201).notes | Where-Object { $_.text.Contains('[auto-close-resolved: closed, ') }).Count -eq 1 -and (Get-Action $out 201).internal_note -eq 'written earlier') ((Get-Action $out 201) | ConvertTo-Json -Compress)

# ---- 4b. Two runs that overlap (or an Action Runs Retry) send the client one notice ----
# Both runs plan before either writes, so only the -Marker check in Add-PsaNote stands between them.
New-StandardWorld 'connectwise'
$planA = ConvertTo-RoundTrip (Invoke-Step 'node-find' $null)
$planB = ConvertTo-RoundTrip (Invoke-Step 'node-find' $null)
$null = Invoke-Step 'node-close' (ConvertTo-RoundTrip (Invoke-Step 'node-notice' $planA))
$MockWorld.writes.Clear()
$outB = ConvertTo-RoundTrip (Invoke-Step 'node-close' (ConvertTo-RoundTrip (Invoke-Step 'node-notice' $planB)))
Check 'overlap: the second run posts no note at all' (@(Get-Writes "POST $cw/service/tickets/*/notes").Count -eq 0) (Get-WriteList)
Check 'overlap: the second run reports the notices as sent earlier' (@($outB.actions | Where-Object { $_.result -like 'final notice: sent earlier*' }).Count -eq 3) ($outB.actions | ConvertTo-Json -Compress)
Check 'overlap: each ticket holds one final notice' (@((Get-WorldTicket 201).notes | Where-Object { -not $_.internal -and $_.text -like "*so we're closing it now*" }).Count -eq 1 -and @((Get-WorldTicket 207).notes | Where-Object { -not $_.internal -and $_.text -like "*so we're closing it now*" }).Count -eq 1)
Check 'overlap: no public note on any ticket shows a marker' (@($MockWorld.tickets | ForEach-Object { $_.notes } | Where-Object { -not $_.internal -and $_.text -like '*Ref: *' -and -not (Test-CleanPublic $_.text) }).Count -eq 0)

# ---- 4c. Back-compat: an older public notice with the bracketed marker still counts as sent ----
Reset-World 'connectwise'
$null = Add-WorldTicket 202 'Resolved' -Created 20 -Notes @(@{ d = 10; who = 'tech'; text = 'Fixed: the mailbox was restored.' }, @{ d = 5; who = 'marker'; text = (Get-Marker 'final notice' 10) }, @{ d = 5; who = 'marker'; internal = $true; text = (Get-Marker 'failed' 10) })
$out = Invoke-Workflow $null
Check 'back-compat: old bracketed public notice read, closed without a second notice' ((Get-WorldTicket 202).status -eq 'Closed' -and @(Get-Writes "POST $cw/service/tickets/202/notes" | Where-Object { $_.Body.detailDescriptionFlag }).Count -eq 0) (Get-WriteList)

# ---- 5. Missing permission (403) ----
New-StandardWorld 'connectwise'
$MockWorld.fail = "$cw/service/tickets?*"
$msg = Get-ThrowMessage { Invoke-Workflow $null }
Check 'cw 403: the run stops with the HTTP 403 and the permission' ($msg -like '*HTTP 403*permission to read service tickets*') $msg
Check 'cw 403: nothing written' (@(Get-Writes).Count -eq 0)

# ---- 6. Empty result ----
Reset-World 'autotask'
$out = Invoke-Workflow '{}'
Check 'empty: success with a plain message' ($out.status -eq 'success' -and $out.message -like "No tickets in 'Resolved' in Autotask have been resolved for 3 days or more.*") $out.message
Check 'empty: nothing written' (@(Get-Writes).Count -eq 0)

# ---- 7. Live run on Autotask (closes to Complete) ----
New-StandardWorld 'autotask'
$at = $MockBase.autotask
$out = Invoke-Workflow $null
$patch = @(Get-Writes "PATCH $at/Tickets")
Check 'autotask live: 201, 202, 207 set to Complete (5)' ((@($patch | ForEach-Object { $_.Body.id } | Sort-Object) -join ',') -eq '201,202,207' -and @($patch | Where-Object { $_.Body.status -ne 5 }).Count -eq 0) ($patch | ConvertTo-Json -Depth 4 -Compress)
Check 'autotask live: notices published to all users, notes internal' ((@(Get-Writes "POST $at/Tickets/201/Notes" | ForEach-Object { $_.Body.publish }) -join ',') -eq '1,2') (Get-WriteList)

# ---- 8. Inputs fail closed ----
New-StandardWorld 'syncro'
$msg = Get-ThrowMessage { Invoke-Workflow $null }
Check 'syncro default: refuses because Resolved is already closed' ($msg -like 'In Syncro, Resolved is already the closed status*') $msg
New-StandardWorld 'connectwise'
$msg = Get-ThrowMessage { Invoke-Workflow ([pscustomobject]@{ close_status_name = 'resolved' }) }
Check 'inputs: closing to the resolved status is refused' ($msg -like "close_status_name and resolved_status_name are both 'Resolved'*") $msg
$msg = Get-ThrowMessage { Invoke-Workflow ([pscustomobject]@{ resolved_days = 10; max_resolved_days = 7 }) }
Check 'inputs: max_resolved_days must be more than resolved_days' ($msg -eq 'max_resolved_days (7) must be more than resolved_days (10).') $msg
$msg = Get-ThrowMessage { Invoke-Workflow ([pscustomobject]@{ resolved_days = 'three' }) }
Check 'inputs: a non-number is rejected' ($msg -like 'resolved_days must be a whole number*') $msg
Check 'inputs: rejected runs wrote nothing' (@(Get-Writes).Count -eq 0)
New-StandardWorld 'connectwise'
$out = Invoke-Workflow ([pscustomobject]@{ preview = $true; resolved_days = 5; company = 'Contoso' })
Check 'inputs: resolved_days 5 leaves 201 (4 days) alone' ($null -eq (Get-Action $out 201) -and $null -ne (Get-Action $out 207)) ($out.actions | ConvertTo-Json -Compress)
Check 'inputs: company filter sent as company/id' (@($MockWorld.calls | Where-Object { [uri]::UnescapeDataString($_) -like '*company/id=42*' }).Count -ge 1)

# ---- 9. A warning from _shared/psa.ps1 reaches the output ----
# ConnectWise saves the final notice on 201, then answers the POST with an insecure redirect (what staging did).
# Add-PsaNote reads the ticket back, finds the note, and records a warning in $PsaState.Warnings; the run's
# warnings and its internal note must carry it, once.
$MockIrm = ${function:Invoke-RestMethod}
$MockRedirect = @{ on = $false }
function Invoke-RestMethod {
    [CmdletBinding()] param($Method = 'GET', $Uri, $Headers, $Body, $ContentType, $Form, [int]$MaximumRedirection = -1)
    if ($MockRedirect.on -and ([string]$Method).ToUpperInvariant() -eq 'POST' -and [string]$Uri -like '*/service/tickets/201/notes' -and ($Body | ConvertFrom-Json).detailDescriptionFlag) {
        $null = & $MockIrm @PSBoundParameters
        $er = [System.Management.Automation.ErrorRecord]::new([System.InvalidOperationException]::new(), 'InsecureRedirection,Microsoft.PowerShell.Commands.InvokeRestMethodCommand', 'InvalidOperation', $null); $er.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('Cannot follow an insecure redirection by default. Reissue the command specifying the -AllowInsecureRedirect switch.'); throw $er
    }
    & $MockIrm @PSBoundParameters
}
New-StandardWorld 'connectwise'
$MockRedirect.on = $true
$out = Invoke-Workflow $null
$MockRedirect.on = $false
$want = 'ConnectWise answered the note on ticket 201 with a redirect; reading the ticket back showed the note was saved, so it was not sent again.'
Check 'shared warning: the redirected final notice is saved once and the run still succeeds' ($out.status -eq 'success' -and @(Get-Writes "POST $cw/service/tickets/201/notes" | Where-Object { $_.Body.detailDescriptionFlag }).Count -eq 1) "$($out.status) / $(Get-WriteList)"
Check 'shared warning: $PsaState.Warnings reaches the output warnings, once' (@($out.warnings | Where-Object { $_ -eq $want }).Count -eq 1) ($out.warnings -join ' | ')
Check 'shared warning: the internal-note summary lists it' ($out.internal_note.Contains("Warning: $want")) $out.internal_note
${function:Invoke-RestMethod} = $MockIrm

Complete-Test
