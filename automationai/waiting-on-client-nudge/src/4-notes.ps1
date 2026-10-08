# === Step 4: Internal note per action, and the run summary ===
# Writes one internal (technician-only) note on every ticket that had an action, including failures and the
# P1/P2 holds, then returns the run summary. With preview: true it writes nothing and returns the preview.

$state = Read-NudgeState
$s = $state.settings
$wf = 'Waiting-on-Client Nudge'

function Get-NudgeInternalNote {
    param($p)
    $since = Format-NudgeDay $p.since
    switch ($p.action) {
        'remind' {
            # Another run already sent this reminder (and writes its own internal note).
            if ($p.remindResult -eq 'already sent') { return $null }
            if ($p.remindResult -eq 'sent') {
                return @{ tag = "day $($p.day)"; text = "$wf sent reminder $($p.reminderNo) of $($p.reminderTotal) (day $($p.day)) to the client as a public note. The ticket has waited $($p.daysWaiting) days, since $since. It will be closed on $(Format-NudgeDay $p.closeBy) if the client doesn't reply." }
            }
            return @{ tag = 'failed'; text = "$wf tried to send the day $($p.day) reminder, but $($s.psaName) refused it: $($p.error). The next run will try again." }
        }
        'close' {
            $notice = if ($p.noticeResult -eq 'sent') { 'The closing notice was sent to the client as a public note.' } else { 'The closing notice was sent on an earlier run.' }
            if ($p.closeResult -eq 'closed') { return @{ tag = 'closed'; text = "$wf closed this ticket (status '$($p.closedStatus)') after $($p.daysWaiting) days waiting for the client, since $since. $notice" } }
            if ($p.noticeResult -eq 'failed') { return @{ tag = 'failed'; text = "$wf couldn't send the closing notice, so the ticket was left open: $($p.error). The next run will try again." } }
            return @{ tag = 'failed'; text = "$wf sent the closing notice but couldn't close the ticket: $($p.error). The next run will retry the close without sending another notice." }
        }
        'hold' {
            return @{ tag = 'close held'; text = "This ticket has waited $($p.daysWaiting) days for the client, since $since. Its priority is '$($p.priority)', so $wf didn't close it. Please follow up with the client or close it yourself." }
        }
    }
    return $null
}

$todo = @($state.plan | Where-Object { $_.action })
if ($todo.Count -and -not $s.preview) { $null = Connect-Psa $s.psa }
foreach ($p in $todo) {
    $n = Get-NudgeInternalNote $p
    if ($null -eq $n) { continue }
    if ($s.preview) { $p.noteResult = 'would write'; continue }
    try { Add-PsaNote -Id $p.ticketId -Text "$($n.text)`n$(Get-NudgeMarker $n.tag $p.since)" -Title $wf; $p.noteResult = 'written' }
    catch { $p.noteResult = 'failed'; $state.warnings += "Couldn't write the internal note on ticket $(Get-NudgeTicketLabel $p): $($_.Exception.Message)" }
}

# ---- summary ----
$reminded = @($todo | Where-Object { $_.remindResult -in @('sent', 'would send') }).Count
$closed = @($todo | Where-Object { $_.closeResult -in @('closed', 'would close') }).Count
$held = @($todo | Where-Object { $_.action -eq 'hold' }).Count
$failed = @($todo | Where-Object { $_.remindResult -eq 'failed' -or $_.noticeResult -eq 'failed' -or $_.closeResult -eq 'failed' -or $_.noteResult -eq 'failed' }).Count
$replied = @($state.skipped | Where-Object { $_.reason -eq 'client replied' }).Count

$actions = @(foreach ($p in $todo) {
        $result = switch ($p.action) {
            'remind' { "reminder $($p.reminderNo) of $($p.reminderTotal) (day $($p.day)): $($p.remindResult)" }
            'close' { "closing notice: $($p.noticeResult); close: $($p.closeResult)$(if ($p.closedStatus) { " ($($p.closedStatus))" })" }
            'hold' { 'not closed (high priority); technician asked to follow up' }
        }
        [ordered]@{ ticket_id = $p.ticketId; ticket = $p.number; company = $p.companyName; action = $p.action; days_waiting = $p.daysWaiting; result = $result; internal_note = $p.noteResult; error = $p.error }
    })

$verb = if ($s.preview) { @{ remind = 'would send'; close = 'would close'; hold = 'would flag' } } else { @{ remind = 'sent'; close = 'closed'; hold = 'flagged' } }
$parts = @()
if ($reminded) { $parts += "$($verb.remind) $(Get-NudgePlural $reminded 'reminder' 'reminders')" }
if ($closed) { $parts += "$($verb.close) $(Get-NudgePlural $closed 'ticket' 'tickets')" }
if ($held) { $parts += "$($verb.hold) $(Get-NudgePlural $held 'high-priority ticket' 'high-priority tickets') for a technician instead of closing them" }
$scope = "in '$($s.waitingStatus)' in $($s.psaName)$(if ($s.companyName) { " for $($s.companyName)" } elseif ($s.companyId) { " for company $($s.companyId)" })"
$joined = if ($parts.Count -gt 1) { ($parts[0..($parts.Count - 2)] -join ', ') + ' and ' + $parts[-1] } elseif ($parts.Count) { $parts[0] } else { '' }
$message = if ($parts.Count) { "Checked $(Get-NudgePlural $state.found 'ticket' 'tickets') $scope" + ": $joined." } elseif ($state.found) { "Checked $(Get-NudgePlural $state.found 'ticket' 'tickets') $scope. None needed a reminder or closing today." } else { "No tickets $scope have waited long enough to need a reminder. If your waiting status has a different name, set waiting_status_name." }
if ($replied) { $message += " $(Get-NudgePlural $replied 'ticket was' 'tickets were') skipped because the client had replied." }
if ($failed) { $message += " $(Get-NudgePlural $failed 'ticket' 'tickets') had a problem; see the warnings." }
if ($s.preview) { $message = "Preview only, nothing was changed. $message" }

$lines = @("$wf run at $($s.runAt)$(if ($s.preview) { ' (preview, nothing changed)' }). Reminder days: $(@($s.reminderDays) -join ', '); close day: $($s.closeDay).")
foreach ($a in $actions) { $lines += "#$($a.ticket)$(if ($a.company) { " ($($a.company))" }): waited $($a.days_waiting) days; $($a.result)$(if ($a.error) { ". Problem: $($a.error)" })." }
foreach ($w in $state.warnings) { $lines += "Warning: $w" }

$status = if ($failed) { 'incomplete' } elseif ($s.preview -and $todo.Count) { 'pending_confirmation' } else { 'success' }
Set-NodeOutput ([ordered]@{
        status        = $status
        message       = $message
        public_note   = ''
        internal_note = ($lines -join "`n")
        ticket_id     = ''
        preview       = $s.preview
        counts        = [ordered]@{ found = $state.found; reminded = $reminded; closed = $closed; held = $held; skipped = @($state.skipped).Count; client_replied = $replied; failed = $failed }
        actions       = @($actions)
        skipped       = @($state.skipped)
        warnings      = @($state.warnings)
    })
