# Step 2: Send the survey (mode "survey" only).
# Posts a one-question satisfaction survey as a public note, so the PSA emails it to the requester.
# Each answer is a link to the survey page with the ticket number and score filled in.
# With preview=true it returns the note (status pending_confirmation) and posts nothing.
# In mode "score", or when step 1 skipped, it passes the context straight on.
$stopState = @{ done = $false }
$warnings = New-Object System.Collections.ArrayList
$ctx = Read-StepContext (Get-NodeInput)
trap { if (-not $stopState.done) { $stopState.done = $true; $m = [string]$_.Exception.Message; $tid = ''; if ($null -ne $ctx -and $null -ne $ctx.PSObject.Properties['ticket_id']) { $tid = [string]$ctx.ticket_id }; Set-NodeOutput ([ordered]@{ status = 'error'; message = "The survey for ticket $tid could not be sent: $m"; public_note = ''; internal_note = "Post-close feedback failed: $m"; ticket_id = $tid; mode = 'survey'; survey_sent = $false; actions = @(); warnings = @(Get-StepWarnings $warnings); ctx_json = '' }) }; break }
if ($null -eq $ctx -or $null -eq $ctx.PSObject.Properties['skip']) { throw 'The request details from step 1 are missing. Run the workflow from the start.' }
if ($ctx.skip -or $ctx.mode -ne 'survey') { $stopState.done = $true; Set-NodeOutput ([ordered]@{ status = 'success'; message = 'Nothing to send in this step.'; ctx_json = (ConvertTo-Json -InputObject $ctx -Depth 8 -Compress) }); return }

$id = [string]$ctx.ticket_id
$actions = New-Object System.Collections.ArrayList; foreach ($x in @($ctx.actions)) { if ($x) { $null = $actions.Add([string]$x) } }
$warnings = New-Object System.Collections.ArrayList; foreach ($x in @($ctx.warnings)) { if ($x) { $null = $warnings.Add([string]$x) } }

# The link for one answer. {ticketId} (or {id}), {score} and {email} are filled in; when the template has no
# {score}, ticket and score are added as query parameters.
function Get-SurveyLink {
    param([string]$Template, [string]$TicketId, [int]$Score, [string]$Email)
    $e = { param($v) [uri]::EscapeDataString([string]$v) }
    $u = $Template.Replace('{ticketId}', (& $e $TicketId)).Replace('{id}', (& $e $TicketId)).Replace('{email}', (& $e $Email))
    if ($u.Contains('{score}')) { return $u.Replace('{score}', [string]$Score) }
    $sep = if ($u.Contains('?')) { '&' } else { '?' }
    if ($Template.Contains('{ticketId}') -or $Template.Contains('{id}')) { return "$u$($sep)score=$Score" }
    return "$u$($sep)ticket=$(& $e $TicketId)&score=$Score"
}
$labels = @{ 1 = 'Very poor'; 2 = 'Poor'; 3 = 'Okay'; 4 = 'Good'; 5 = 'Excellent' }
$max = [int]$ctx.score_max
$summary = [string]$ctx.summary
$lines = New-Object System.Collections.ArrayList
$null = $lines.Add("How did we do on ticket $id$(if ($summary) { " ($summary)" })?")
$null = $lines.Add('')
$null = $lines.Add('Your ticket is now closed. One click tells us how it went:')
for ($s = $max; $s -ge 1; $s--) {
    $label = if ($max -eq 5) { "$($labels[$s]) ($s)" } else { "$s out of $max" }
    $null = $lines.Add("$($label): $(Get-SurveyLink ([string]$ctx.feedback_url) $id $s ([string]$ctx.contact))")
}
$null = $lines.Add('')
$null = $lines.Add('Thank you. If anything still isn''t right, just reply to this ticket.')
$note = $lines -join "`n"

if ($ctx.preview) {
    $stopState.done = $true
    $ctx | Add-Member -NotePropertyName result -NotePropertyValue ([ordered]@{
            status = 'pending_confirmation'; message = "Preview: this survey would be posted on ticket $id as a public note. Run again without preview to send it."
            public_note = $note; internal_note = 'Post-close survey preview. Nothing was posted.'; ticket_id = $id; mode = 'survey'; survey_sent = $false
            score = $null; low_score = $false; manager_emailed = $false; actions = @($actions); warnings = @(Get-StepWarnings $warnings)
        }) -Force
    Set-NodeOutput ([ordered]@{ status = 'pending_confirmation'; message = $ctx.result.message; ctx_json = (ConvertTo-Json -InputObject $ctx -Depth 8 -Compress) })
    return
}

$conn = Connect-Psa $ctx.psa
Add-PsaNote -Id $id -Text $note -Title 'How did we do?' -Public
$null = $actions.Add("Posted the satisfaction survey on ticket $id as a public note.")
$stopState.done = $true
$ctx | Add-Member -NotePropertyName result -NotePropertyValue ([ordered]@{
        status = 'success'; message = "Sent the satisfaction survey for ticket $id."
        public_note = $note; internal_note = "Posted a one-question satisfaction survey for the requester. Scores come back through this workflow in score mode."
        ticket_id = $id; mode = 'survey'; survey_sent = $true; score = $null; low_score = $false; manager_emailed = $false; actions = @($actions); warnings = @(Get-StepWarnings $warnings)
    }) -Force
Set-NodeOutput ([ordered]@{ status = 'success'; message = $ctx.result.message; ctx_json = (ConvertTo-Json -InputObject $ctx -Depth 8 -Compress) })
