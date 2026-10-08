# === Step 2: Send reminders ===
# Posts the polite reminder as a public note, so the PSA emails the client. With preview: true it only
# records what it would send.

$state = Read-NudgeState
$todo = @($state.plan | Where-Object { $_.action -eq 'remind' })
if ($todo.Count -and -not $state.settings.preview) { $null = Connect-Psa $state.settings.psa }
foreach ($p in $todo) {
    if ($state.settings.preview) { $p.remindResult = 'would send'; continue }
    try {
        Add-PsaNote -Id $p.ticketId -Text (Get-NudgeReminderText $p) -Title 'Reminder: we are waiting on your reply' -Public
        $p.remindResult = 'sent'
    }
    catch {
        $p.remindResult = 'failed'; $p.error = [string]$_.Exception.Message
        $state.warnings += "Couldn't send the day $($p.day) reminder on ticket $(Get-NudgeTicketLabel $p): $($p.error)"
    }
}
Write-NudgeState $state
