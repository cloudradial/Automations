# Step 1: Detect the status change.
# Reads the webhook body (flat or the CloudRadial {Ticket, Company} shape), decides whether the requester
# should hear about this change, and gathers only client-visible facts for the AI step: the ticket summary,
# the original request and the latest public notes. Internal notes are never read into the facts.
# Skips (status success, nothing posted): the status didn't change, the new status is on the ignore list,
# or an update for this status is already the newest public note.
$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
$stopState = @{ done = $false }
function Stop-Detect {
    param([string]$Status, [string]$Why, [string]$TicketId = '')
    $stopState.done = $true
    Set-NodeOutput ([ordered]@{ status = $Status; message = $Why; public_note = ''; internal_note = "Status change update did not run: $Why"; ticket_id = $TicketId; actions = @($actions); warnings = @($warnings); facts_json = '{"skip":true}'; ctx_json = '' })
    throw $Why
}
trap { if (-not $stopState.done) { $stopState.done = $true; $m = [string]$_.Exception.Message; Set-NodeOutput ([ordered]@{ status = 'error'; message = $m; public_note = ''; internal_note = "Status change update failed: $m"; ticket_id = ''; actions = @($actions); warnings = @($warnings); facts_json = '{"skip":true}'; ctx_json = '' }) }; break }
# Ends the run quietly: later steps see skip and post nothing.
function Skip-Detect {
    param([string]$Why, [string]$TicketId)
    $stopState.done = $true
    $ctx = @{ skip = $true; ticket_id = $TicketId; result = [ordered]@{ status = 'success'; message = $Why; public_note = ''; internal_note = ''; ticket_id = $TicketId; posted = $false; written_by = ''; actions = @($actions); warnings = @($warnings) } }
    Set-NodeOutput ([ordered]@{ status = 'success'; message = $Why; ticket_id = $TicketId; facts_json = '{"skip":true}'; ctx_json = (ConvertTo-Json -InputObject $ctx -Depth 8 -Compress) })
}

$a = Read-StepTrigger (Get-NodeInput)
$ticketId = Get-StepField $a @('ticketId', 'ticket_id', 'TicketId', 'ticketNumber', 'TicketNumber')
$oldStatus = Get-StepField $a @('oldStatus', 'old_status', 'previousStatus', 'previous_status', 'OldStatus', 'fromStatus')
$newStatus = Get-StepField $a @('newStatus', 'new_status', 'NewStatus', 'toStatus', 'status', 'Status', 'StatusName')
$contact = Get-StepField $a @('contactEmail', 'contact_email', 'requesterEmail', 'requester_email', 'UserEmail')
$preview = Test-StepTrue (Get-StepField $a @('preview', 'dryRun', 'dry_run'))
$ignoreRaw = Get-StepField $a @('ignore_statuses', 'ignoreStatuses')
$ignore = if ($ignoreRaw) { @(Get-StepList $ignoreRaw) } else { @('Waiting on Vendor', 'Waiting on Parts', 'Waiting on Third Party', 'Internal Review', 'Escalated', 'Scheduled Internally') }
$templates = Read-StepJson (Get-StepField $a @('templates'))

if (-not $ticketId) { Stop-Detect 'incomplete' 'The request has no ticket number, so no update was posted.' }
if ($ticketId -notmatch '^[A-Za-z0-9-]{1,40}$') { Stop-Detect 'rejected' "Ticket number '$ticketId' isn't valid, so no update was posted." }
if (-not $contact) { $null = $warnings.Add('No contactEmail was sent. The PSA sends the update to the ticket''s own contact.') }

$conn = Connect-Psa (Get-PsaType (Get-StepField $a @('psa')))
$oldStatus = Get-PsaStatusName $oldStatus
$newStatus = Get-PsaStatusName $newStatus
if ($oldStatus -and $newStatus -and $oldStatus.Trim() -ieq $newStatus.Trim()) { Skip-Detect "Ticket $ticketId is still $newStatus, so no update was needed." $ticketId; return }

$t = Get-PsaTicket $ticketId
$null = $actions.Add("Read ticket $ticketId from $(Get-PsaName).")
if (-not $newStatus) { $newStatus = Get-PsaStatusName ([string]$t.status) }
if (-not $newStatus) { Stop-Detect 'incomplete' "Ticket $ticketId has no new status, so no update was posted." $ticketId }
if ($oldStatus -and $oldStatus.Trim() -ieq $newStatus.Trim()) { Skip-Detect "Ticket $ticketId is still $newStatus, so no update was needed." $ticketId; return }
foreach ($ig in $ignore) {
    if ($newStatus -like $ig) { Skip-Detect "$newStatus is an internal status, so the requester wasn't sent an update for ticket $ticketId." $ticketId; return }
}

# ---- client-visible history only ----
$notes = @(Get-PsaNotes $ticketId)
$public = @($notes | Where-Object { $_.public -and ([string]$_.text).Trim() })
$footer = "(Status: $newStatus)"
if ($public.Count -and ([string]$public[0].text).TrimEnd().EndsWith($footer, [StringComparison]::OrdinalIgnoreCase)) {
    Skip-Detect "An update for $newStatus is already the newest public note on ticket $ticketId, so it wasn't posted again." $ticketId; return
}
$clip = { param([string]$s, [int]$n) $s = (ConvertTo-PsaPlainText $s); if ($s.Length -gt $n) { return $s.Substring(0, $n) + '...' }; return $s }
# ConnectWise and Syncro keep the request in the first note, which may be internal, so use the oldest public note we have.
$request = if (@('connectwise', 'syncro') -contains $conn.Psa) { if ($public.Count) { [string]$public[-1].text } else { '' } } else { [string]$t.description }
$recent = @($public | Select-Object -First 3 | ForEach-Object { & $clip ([string]$_.text) 500 })
$facts = [ordered]@{
    skip = $false
    ticket_number = $ticketId
    summary = (& $clip ([string]$t.summary) 200)
    request = (& $clip $request 600)
    old_status = $oldStatus
    new_status = $newStatus
    recent_public_updates = $recent
}
$ctx = @{
    skip = $false; ticket_id = $ticketId; psa = $conn.Psa; psa_name = (Get-PsaName); old_status = $oldStatus; new_status = $newStatus
    summary = $facts.summary; contact = $contact; preview = $preview; templates = $templates; footer = $footer
    actions = @($actions); warnings = @($warnings)
}
Set-NodeOutput ([ordered]@{
        status = 'success'; message = "Ticket $ticketId moved$(if ($oldStatus) { " from $oldStatus" }) to $newStatus."; ticket_id = $ticketId
        facts_json = (ConvertTo-Json -InputObject $facts -Depth 5 -Compress); ctx_json = (ConvertTo-Json -InputObject $ctx -Depth 8 -Compress)
    })
