# === Step 3: Close with internal note ===
# For each ticket whose final notice is out: writes the internal note (its "closed" marker is also how a later run
# knows the notice went out), then closes the ticket. The note goes
# first because some PSAs (Zendesk) refuse notes on a closed ticket. If the close fails, a second internal note
# says so, and the next run retries the close without another notice. Then returns the run summary.
# With preview: true it changes nothing.

$state = Read-AcrState
$s = $state.settings
$wf = 'Auto-Close Resolved'
$todo = @($state.plan | Where-Object { $_.action -eq 'close' })
if ($todo.Count -and -not $s.preview) { $null = Connect-Psa $s.psa }

foreach ($p in $todo) {
    $since = Format-AcrDay $p.since
    if ($p.noticeResult -eq 'failed') {
        if ($s.preview) { continue }
        $p.closeResult = 'not closed'
        try { Add-PsaNote -Id $p.ticketId -Text "$wf couldn't send the final notice, so the ticket was left in '$($s.resolvedStatus)': $($p.error). The next run will try again.`n$(Get-AcrMarker 'failed' $p.since)" -Title $wf; $p.noteResult = 'written' }
        catch { $p.noteResult = 'failed'; $state.warnings += "Couldn't write the internal note on ticket $(Get-AcrTicketLabel $p): $($_.Exception.Message)" }
        continue
    }
    if ($s.preview) { $p.noteResult = 'would write'; $p.closeResult = 'would close'; continue }

    $notice = if ($p.noticeResult -eq 'sent') { 'The final notice was sent to the client as a public note.' } else { 'The final notice was sent on an earlier run.' }
    try {
        $r = Add-PsaNote -Id $p.ticketId -Text "$wf is closing this ticket. It has been in '$($s.resolvedStatus)' for $($p.daysResolved) days, since $since, with no reply from the client. $notice`n$(Get-AcrMarker 'closed' $p.since)" -Title $wf -Marker (Get-AcrMarker 'closed' $p.since)
        $p.noteResult = $(if ($r -eq 'already-present') { 'written earlier' } else { 'written' })
    }
    catch { $p.noteResult = 'failed'; $state.warnings += "Couldn't write the internal note on ticket $(Get-AcrTicketLabel $p): $($_.Exception.Message)" }
    try {
        $p.closedStatus = [string](Close-PsaTicket -Id $p.ticketId -StatusName $s.closeStatus -NotStatus $s.resolvedStatus)
        $p.closeResult = 'closed'
    }
    catch {
        $p.closeResult = 'failed'; $p.error = [string]$_.Exception.Message
        $state.warnings += "Sent the final notice on ticket $(Get-AcrTicketLabel $p) but couldn't close it: $($p.error)"
        try { Add-PsaNote -Id $p.ticketId -Text "$wf couldn't close this ticket: $($p.error). The next run will retry the close without sending another notice.`n$(Get-AcrMarker 'failed' $p.since)" -Title $wf } catch { }
    }
}

# ---- summary ----
$state.warnings = @(Get-AcrWarnings $state.warnings)
$closed = @($todo | Where-Object { $_.closeResult -in @('closed', 'would close') }).Count
$failed = @($todo | Where-Object { $_.noticeResult -eq 'failed' -or $_.closeResult -eq 'failed' -or $_.noteResult -eq 'failed' }).Count
$replied = @($state.skipped | Where-Object { $_.reason -eq 'client replied' }).Count

$actions = @(foreach ($p in $todo) {
        [ordered]@{ ticket_id = $p.ticketId; ticket = $p.number; company = $p.companyName; action = 'close'; days_resolved = $p.daysResolved
            result = "final notice: $($p.noticeResult); close: $(if ($p.closeResult) { $p.closeResult } else { 'not closed' })$(if ($p.closedStatus) { " ($($p.closedStatus))" })"
            internal_note = $p.noteResult; error = $p.error }
    })

$scope = "in '$($s.resolvedStatus)' in $($s.psaName)$(if ($s.companyName) { " for $($s.companyName)" } elseif ($s.companyId) { " for company $($s.companyId)" })"
$message = if ($closed) { "Checked $(Get-AcrPlural $state.found 'ticket' 'tickets') $scope and $(if ($s.preview) { 'would close' } else { 'closed' }) $(Get-AcrPlural $closed 'ticket' 'tickets') after a final notice to the client." }
elseif ($state.found) { "Checked $(Get-AcrPlural $state.found 'ticket' 'tickets') $scope. None needed closing today." }
else { "No tickets $scope have been resolved for $($s.resolvedDays) days or more. If your resolved status has a different name, set resolved_status_name." }
if ($replied) { $message += " $(Get-AcrPlural $replied 'ticket was' 'tickets were') left open because the client had replied." }
if ($failed) { $message += " $(Get-AcrPlural $failed 'ticket' 'tickets') had a problem; see the warnings." }
if ($s.preview) { $message = "Preview only, nothing was changed. $message" }

$lines = @("$wf run at $($s.runAt)$(if ($s.preview) { ' (preview, nothing changed)' }). Closes tickets in '$($s.resolvedStatus)' for $($s.resolvedDays) to $($s.maxResolvedDays) days.")
foreach ($a in $actions) { $lines += "#$($a.ticket)$(if ($a.company) { " ($($a.company))" }): resolved $($a.days_resolved) days; $($a.result)$(if ($a.error) { ". Problem: $($a.error)" })." }
foreach ($w in $state.warnings) { $lines += "Warning: $w" }

$status = if ($failed) { 'incomplete' } elseif ($s.preview -and $todo.Count) { 'pending_confirmation' } else { 'success' }
Set-NodeOutput ([ordered]@{
        status        = $status
        message       = $message
        public_note   = ''
        internal_note = ($lines -join "`n")
        ticket_id     = ''
        preview       = $s.preview
        counts        = [ordered]@{ found = $state.found; closed = $closed; skipped = @($state.skipped).Count; client_replied = $replied; failed = $failed }
        actions       = @($actions)
        skipped       = @($state.skipped)
        warnings      = @($state.warnings)
    })
