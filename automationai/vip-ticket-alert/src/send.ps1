# Step 3: Email the account manager and note the ticket.
# With preview=true it returns what it would send (status pending_confirmation) and sends nothing.
# Otherwise it emails the alert through Postmark, then adds an internal note saying who was told.
# If Postmark isn't set up or refuses the email, the internal note carries the alert instead.
# It never changes the ticket's status, priority or assignee, and never writes a client-visible note.
$stopState = @{ done = $false }
$ctx = Read-StepContext (Get-NodeInput)
trap { if (-not $stopState.done) { $stopState.done = $true; $m = [string]$_.Exception.Message; $tid = ''; if ($null -ne $ctx) { $tid = [string]$ctx.ticket_id }; Set-NodeOutput ([ordered]@{ status = 'error'; message = "The VIP alert for ticket $tid could not be completed: $m"; public_note = ''; internal_note = "VIP ticket alert failed: $m"; ticket_id = $tid; vip = $true; alerted = $false; recipients = @(); actions = @(); warnings = @(); chatReply = 'The VIP ticket alert failed. See the run for details.' }) }; break }
if ($null -eq $ctx -or $null -eq $ctx.PSObject.Properties['skip']) { throw 'The VIP check result is missing. Run the workflow from the start.' }
if ($ctx.skip) { $stopState.done = $true; Set-NodeOutput $ctx.result; return }
if ($null -eq $ctx.PSObject.Properties['alert']) { throw 'The alert text from the build step is missing. Run the workflow from the start.' }

$id = [string]$ctx.ticket_id
$actions = New-Object System.Collections.ArrayList; foreach ($x in @($ctx.actions)) { if ($x) { $null = $actions.Add([string]$x) } }
$warnings = New-Object System.Collections.ArrayList; foreach ($x in @($ctx.warnings)) { if ($x) { $null = $warnings.Add([string]$x) } }
$to = @($ctx.recipients | Where-Object { $_ })
$toText = if ($to.Count) { $to -join ', ' } else { 'nobody (no address is set)' }
$matched = "$($ctx.company) is on the VIP list (matched $($ctx.match.kind) '$($ctx.match.entry)' from $($ctx.list_from))."

if ($ctx.preview) {
    $stopState.done = $true
    $msg = "Preview: ticket $id is from a VIP. Run again without preview to email $toText and add an internal note."
    Set-NodeOutput ([ordered]@{
            status = 'pending_confirmation'; message = $msg; public_note = ''
            internal_note = "VIP ticket alert (preview, nothing sent). $matched It would email $toText.`n`n$($ctx.alert.text)"
            ticket_id = $id; vip = $true; alerted = $false; recipients = $to; subject = [string]$ctx.alert.subject; email_text = [string]$ctx.alert.text
            actions = @($actions); warnings = @($warnings); chatReply = $msg
        })
    return
}

$conn = Connect-Psa $ctx.psa
$mail = Send-PmMail -To $to -Subject ([string]$ctx.alert.subject) -Text ([string]$ctx.alert.text) -Html ([string]$ctx.alert.html) -Tag 'vip-ticket-alert'
$reason = ([string]$mail.reason).TrimEnd('.')
if ($mail.sent) {
    $null = $actions.Add("Emailed the VIP alert to $toText.")
    $note = "VIP ticket alert sent to $toText by email. $matched"
}
else {
    $null = $warnings.Add("The alert email was not sent: $reason.")
    $note = "VIP ticket alert: the email to $toText was not sent because $reason. $matched Please let the account manager know.`n`n$($ctx.alert.text)"
}
# The [vip-ticket-alert] marker is what step 1 looks for, so a retry or rerun never alerts twice.
$noted = ''
try { $noted = Add-PsaNote -Id $id -Text $note -Title 'VIP ticket alert' -Marker 'vip-ticket-alert' }
catch {
    if (-not $mail.sent) { throw }
    # The email went out but the note didn't: say so plainly, because the note is what stops a second alert.
    $stopState.done = $true
    $m = "The VIP alert for ticket $id was emailed to $toText, but the internal note could not be added: $($_.Exception.Message) Add an internal note that contains [vip-ticket-alert] by hand; without it, a rerun would email again."
    Set-NodeOutput ([ordered]@{ status = 'error'; message = $m; public_note = ''; internal_note = $note; ticket_id = $id; vip = $true; alerted = $true; recipients = $to; postmark_message_id = [string]$mail.messageId; actions = @($actions); warnings = @($warnings); chatReply = $m })
    throw $m
}
if ($noted -eq 'already-present') { $null = $warnings.Add("Ticket $id already had the VIP alert note (another run added it), so no second note was added.") }
else { $null = $actions.Add("Added an internal note to ticket $id.") }
$stopState.done = $true
$msg = if ($mail.sent) { "VIP alert for ticket $id sent to $toText." } else { "Ticket $id is from a VIP, but the email could not be sent, so the alert is in an internal note on the ticket." }
Set-NodeOutput ([ordered]@{
        status = 'success'; message = $msg; public_note = ''; internal_note = $note; ticket_id = $id; vip = $true; alerted = [bool]$mail.sent
        recipients = $to; postmark_message_id = [string]$mail.messageId; actions = @($actions); warnings = @($warnings); chatReply = $msg
    })
