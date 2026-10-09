# Step 2: Build the alert.
# Writes the account manager's email (subject, text and HTML) from the ticket summary and link.
# Makes no calls. Passes the context straight through when step 1 decided there is nothing to send.
$ctx = Read-StepContext (Get-NodeInput)
if ($null -eq $ctx) {
    $m = 'The VIP check result is missing. Run the workflow from the start.'
    Set-NodeOutput ([ordered]@{ status = 'error'; message = $m; public_note = ''; internal_note = "VIP ticket alert failed: $m"; ticket_id = ''; actions = @(); warnings = @(); chatReply = $m; ctx_json = '' })
    throw $m
}
if ($ctx.skip) { Set-NodeOutput ([ordered]@{ status = 'success'; message = [string]$ctx.result.message; ctx_json = (ConvertTo-Json -InputObject $ctx -Depth 8 -Compress) }); return }

$id = [string]$ctx.ticket_id
$summary = [string]$ctx.summary; if (-not $summary) { $summary = '(no summary)' }
if ($summary.Length -gt 300) { $summary = $summary.Substring(0, 300) + '...' }
$lines = New-Object System.Collections.ArrayList
$null = $lines.Add("A new ticket came in from $($ctx.company), which is on your VIP list.")
$null = $lines.Add('')
$null = $lines.Add("Ticket: $id")
$null = $lines.Add("Summary: $summary")
if ($ctx.priority) { $null = $lines.Add("Priority: $($ctx.priority)") }
if ($ctx.contact) { $null = $lines.Add("Contact: $($ctx.contact)") }
if ($ctx.ticket_url) { $null = $lines.Add("Open the ticket: $($ctx.ticket_url)") }
$null = $lines.Add('')
$null = $lines.Add('You get this alert once per ticket. A note on the ticket records that it was sent.')
$text = $lines -join "`n"

$h = New-Object System.Text.StringBuilder
$null = $h.Append("<p>A new ticket came in from <strong>$(ConvertTo-StepHtml $ctx.company)</strong>, which is on your VIP list.</p><table cellpadding=`"4`">")
$null = $h.Append("<tr><td>Ticket</td><td>$(ConvertTo-StepHtml $id)</td></tr><tr><td>Summary</td><td>$(ConvertTo-StepHtml $summary)</td></tr>")
if ($ctx.priority) { $null = $h.Append("<tr><td>Priority</td><td>$(ConvertTo-StepHtml $ctx.priority)</td></tr>") }
if ($ctx.contact) { $null = $h.Append("<tr><td>Contact</td><td>$(ConvertTo-StepHtml $ctx.contact)</td></tr>") }
$null = $h.Append('</table>')
if ($ctx.ticket_url) { $null = $h.Append("<p><a href=`"$(ConvertTo-StepHtml $ctx.ticket_url)`">Open the ticket</a></p>") }
$null = $h.Append('<p>You get this alert once per ticket. A note on the ticket records that it was sent.</p>')

$subject = "VIP ticket from $($ctx.company): $summary"
if ($subject.Length -gt 150) { $subject = $subject.Substring(0, 147) + '...' }
$ctx | Add-Member -NotePropertyName alert -NotePropertyValue ([ordered]@{ subject = $subject; text = $text; html = $h.ToString() }) -Force
Set-NodeOutput ([ordered]@{ status = 'success'; message = "Alert written for ticket $id."; subject = $subject; ctx_json = (ConvertTo-Json -InputObject $ctx -Depth 8 -Compress) })
