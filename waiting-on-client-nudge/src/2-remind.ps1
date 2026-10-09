# === Step 2: Send reminders ===
# Posts the polite reminder as a public note, so the PSA emails the client. With preview: true it only
# records what it would send. Right after the public note it writes the companion internal note with the
# readable "day N" marker that later runs read (the client sees only an opaque Ref line).

$state = Read-NudgeState
$todo = @($state.plan | Where-Object { $_.action -eq 'remind' })
if ($todo.Count -and -not $state.settings.preview) { $null = Connect-Psa $state.settings.psa }
foreach ($p in $todo) {
    if ($state.settings.preview) { $p.remindResult = 'would send'; continue }
    try {
        $r = Add-PsaNote -Id $p.ticketId -Text (Get-NudgeReminderText $p) -Title 'Reminder: we are waiting on your reply' -Public -Marker (Get-NudgePublicMarker "day $($p.day)" $p.since)
        $p.remindResult = $(if ($r -eq 'already-present') { 'already sent' } else { 'sent' })
        $p.noteResult = Add-NudgeCompanionNote $p "day $($p.day)" (Get-NudgeReminderNote $p) $state
    }
    catch {
        $p.remindResult = 'failed'; $p.error = [string]$_.Exception.Message
        $state.warnings += "Couldn't send the day $($p.day) reminder on ticket $(Get-NudgeTicketLabel $p): $($p.error)"
    }
}
Write-NudgeState $state
