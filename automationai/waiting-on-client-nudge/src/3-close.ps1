# === Step 3: Close with notice ===
# For tickets that reached close_day: posts the closing notice as a public note (once), then closes the
# ticket. If the notice can't be posted, the ticket stays open. If the close fails after the notice went
# out, the next run retries the close without sending the notice again. With preview: true it changes nothing.

$state = Read-NudgeState
$todo = @($state.plan | Where-Object { $_.action -eq 'close' })
if ($todo.Count -and -not $state.settings.preview) { $null = Connect-Psa $state.settings.psa }
foreach ($p in $todo) {
    if ($state.settings.preview) {
        $p.noticeResult = $(if ($p.notice) { 'would send' } else { 'sent earlier' })
        $p.closeResult = 'would close'
        continue
    }
    if ($p.notice) {
        try { Add-PsaNote -Id $p.ticketId -Text (Get-NudgeClosingText $p) -Title 'Closing this ticket' -Public; $p.noticeResult = 'sent' }
        catch {
            $p.noticeResult = 'failed'; $p.closeResult = 'not closed'; $p.error = [string]$_.Exception.Message
            $state.warnings += "Couldn't send the closing notice on ticket $(Get-NudgeTicketLabel $p), so it was left open: $($p.error)"
            continue
        }
    }
    else { $p.noticeResult = 'sent earlier' }
    try {
        $p.closedStatus = [string](Close-PsaTicket -Id $p.ticketId -StatusName $state.settings.closeStatus -NotStatus $state.settings.waitingStatus)
        $p.closeResult = 'closed'
    }
    catch {
        $p.closeResult = 'failed'; $p.error = [string]$_.Exception.Message
        $state.warnings += "Sent the closing notice on ticket $(Get-NudgeTicketLabel $p) but couldn't close it: $($p.error)"
    }
}
Write-NudgeState $state
