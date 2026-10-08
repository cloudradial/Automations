# === Step 2: Send final notice ===
# Posts the final notice as a public note, so the PSA emails the client. Sent once per ticket: a ticket whose
# notice went out on an earlier run (and whose close then failed) doesn't get a second one.
# With preview: true it only records what it would send.

$state = Read-AcrState
$todo = @($state.plan | Where-Object { $_.action -eq 'close' })
if (@($todo | Where-Object { $_.notice }).Count -and -not $state.settings.preview) { $null = Connect-Psa $state.settings.psa }
foreach ($p in $todo) {
    if (-not $p.notice) { $p.noticeResult = 'sent earlier'; continue }
    if ($state.settings.preview) { $p.noticeResult = 'would send'; continue }
    try {
        $r = Add-PsaNote -Id $p.ticketId -Text (Get-AcrNoticeText $p) -Title 'Closing this ticket' -Public -Marker (Get-AcrMarker 'final notice' $p.since)
        $p.noticeResult = $(if ($r -eq 'already-present') { 'sent earlier' } else { 'sent' })
    }
    catch {
        $p.noticeResult = 'failed'; $p.error = [string]$_.Exception.Message
        $state.warnings += "Couldn't send the final notice on ticket $(Get-AcrTicketLabel $p), so it was left open: $($p.error)"
    }
}
Write-AcrState $state
