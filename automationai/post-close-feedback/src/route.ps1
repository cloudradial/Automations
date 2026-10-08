# Step 3: Route low scores (mode "score" only).
# Records the score as an internal note on the ticket. When the score is at or below the threshold, it first
# emails the service manager through Postmark (or, if Postmark isn't set up, says so in the note).
# When a CloudRadial company id is sent and the CloudRadial secrets are set, it also records the score as
# CloudRadial feedback, so the Feedback & CSAT Report (automationai/feedback-csat-report) counts it.
# With preview=true it returns what it would do (status pending_confirmation) and writes nothing.
# In mode "survey", or when step 1 skipped, it returns the result of the earlier steps.
$stopState = @{ done = $false }
$ctx = Read-StepContext (Get-NodeInput)
trap { if (-not $stopState.done) { $stopState.done = $true; $m = [string]$_.Exception.Message; $tid = ''; if ($null -ne $ctx -and $null -ne $ctx.PSObject.Properties['ticket_id']) { $tid = [string]$ctx.ticket_id }; Set-NodeOutput ([ordered]@{ status = 'error'; message = "The score for ticket $tid could not be recorded: $m"; public_note = ''; internal_note = "Post-close feedback failed: $m"; ticket_id = $tid; mode = 'score'; survey_sent = $false; score = $null; low_score = $false; manager_emailed = $false; actions = @(); warnings = @() }) }; break }
if ($null -eq $ctx -or $null -eq $ctx.PSObject.Properties['skip']) { throw 'The request details from step 1 are missing. Run the workflow from the start.' }
if ($ctx.skip -or $ctx.mode -ne 'score') {
    if ($null -eq $ctx.PSObject.Properties['result']) { throw 'The survey step left no result. Run the workflow from the start.' }
    $stopState.done = $true; Set-NodeOutput $ctx.result; return
}

$id = [string]$ctx.ticket_id
$score = [int]$ctx.score; $max = [int]$ctx.score_max; $low = [bool]$ctx.low
$actions = New-Object System.Collections.ArrayList; foreach ($x in @($ctx.actions)) { if ($x) { $null = $actions.Add([string]$x) } }
$warnings = New-Object System.Collections.ArrayList; foreach ($x in @($ctx.warnings)) { if ($x) { $null = $warnings.Add([string]$x) } }
$managers = @($ctx.managers | Where-Object { $_ })
$mgrText = if ($managers.Count) { $managers -join ', ' } else { 'nobody (no service manager address is set)' }
$who = if ($ctx.contact) { " from $($ctx.contact)" } else { '' }
$comment = [string]$ctx.comment

$noteLines = New-Object System.Collections.ArrayList
$null = $noteLines.Add("Satisfaction score received: $score out of $max$who.")
if ($comment) { $null = $noteLines.Add("Comment: $comment") }

$mailText = @(
    "Ticket $id$(if ($ctx.summary) { " ($($ctx.summary))" }) was rated $score out of $max$who, which is at or below the alert threshold of $($ctx.threshold)."
    $(if ($comment) { "Their comment: $comment" } else { 'They left no comment.' })
    $(if ($ctx.ticket_url) { "Open the ticket: $($ctx.ticket_url)" } else { '' })
    ''
    'Please follow up with them. A note on the ticket records the score.'
) -join "`n"
$subject = "Low satisfaction score on ticket $($id): $score out of $max"

if ($ctx.preview) {
    $stopState.done = $true
    $preview = ($noteLines -join "`n") + $(if ($low) { "`nIt would email the service manager ($mgrText)." } else { '' })
    Set-NodeOutput ([ordered]@{
            status = 'pending_confirmation'; message = "Preview: ticket $id was rated $score out of $max. Run again without preview to record it$(if ($low) { ' and alert the service manager' })."
            public_note = ''; internal_note = $preview; ticket_id = $id; mode = 'score'; survey_sent = $true; score = $score; low_score = $low; manager_emailed = $false
            email_text = $(if ($low) { $mailText } else { '' }); actions = @($actions); warnings = @($warnings)
        })
    return
}

$conn = Connect-Psa $ctx.psa
$mail = @{ sent = $false; messageId = ''; reason = '' }
if ($low) {
    $mail = Send-PmMail -To $managers -Subject $subject -Text $mailText -Tag 'post-close-feedback'
    $reason = ([string]$mail.reason).TrimEnd('.')
    if ($mail.sent) { $null = $actions.Add("Emailed the service manager ($mgrText) about the low score."); $null = $noteLines.Add("This is at or below the alert threshold of $($ctx.threshold), so the service manager ($mgrText) was emailed.") }
    else { $null = $warnings.Add("The service manager email was not sent: $reason."); $null = $noteLines.Add("This is at or below the alert threshold of $($ctx.threshold), but the service manager email was not sent because $reason. Please follow up with the requester.") }
}
$note = $noteLines -join "`n"
# The [csat-score] marker is what step 1 looks for, so a retry or rerun never records the score twice.
$noted = ''
try { $noted = Add-PsaNote -Id $id -Text $note -Title 'Satisfaction score' -Marker 'csat-score' }
catch {
    if (-not $mail.sent) { throw }
    $stopState.done = $true
    $m = "The service manager was emailed about ticket $id, but the internal note could not be added: $($_.Exception.Message) Add an internal note that contains [csat-score] by hand; without it, a rerun would email again."
    Set-NodeOutput ([ordered]@{ status = 'error'; message = $m; public_note = ''; internal_note = $note; ticket_id = $id; mode = 'score'; survey_sent = $true; score = $score; low_score = $low; manager_emailed = $true; actions = @($actions); warnings = @($warnings) })
    throw $m
}
if ($noted -eq 'already-present') { $null = $warnings.Add("Ticket $id already had a score note (another run added it), so no second note was added.") }
else { $null = $actions.Add("Added an internal note with the score to ticket $id.") }

# ---- optional: record it as CloudRadial feedback for the CSAT report ----
$crId = [string]$ctx.cr_company_id
$crRecorded = $false
if ($crId -match '^\d+$') {
    if (-not (Get-PsaSecret 'CloudRadial-BaseUrl') -or -not (Get-PsaSecret 'CloudRadial-PublicKey') -or -not (Get-PsaSecret 'CloudRadial-PrivateKey')) {
        $null = $warnings.Add('The score was not recorded in CloudRadial because the CloudRadial-BaseUrl, CloudRadial-PublicKey and CloudRadial-PrivateKey secrets are not all set.')
    }
    else {
        # Unverified: POST /v2/feedback (public v2 spec; companyId and sentiment are required). feedbackRating is
        # 1 positive, 0 neutral, -1 negative; sentiment is sent the same way.
        $pct = $score / [double]$max
        $rating = if ($pct -ge 0.75) { 1 } elseif ($pct -gt 0.5) { 0 } else { -1 }
        $fb = [ordered]@{ companyId = [int]$crId; sentiment = $rating; feedbackRating = $rating; feedbackRatingNumber = $score; feedbackComment = $comment; ticketSubject = [string]$ctx.summary; userEmail = [string]$ctx.contact }
        if ($id -match '^\d+$') { $fb.ticketPsaId = [long]$id }
        try { $null = Connect-Cr; $null = Invoke-CrApi -Path '/v2/feedback' -Method 'POST' -Body $fb; $crRecorded = $true; $null = $actions.Add("Recorded the score as CloudRadial feedback for company $crId.") }
        catch { $null = $warnings.Add("The score was not recorded in CloudRadial: $($_.Exception.Message)") }
    }
}

$stopState.done = $true
$msg = if ($low -and $mail.sent) { "Ticket $id was rated $score out of $max. The service manager was emailed and the score was noted on the ticket." }
elseif ($low) { "Ticket $id was rated $score out of $max. The service manager email could not be sent, so the internal note asks the team to follow up." }
else { "Ticket $id was rated $score out of $max. The score was noted on the ticket." }
Set-NodeOutput ([ordered]@{
        status = 'success'; message = $msg; public_note = ''; internal_note = $note; ticket_id = $id; mode = 'score'; survey_sent = $true
        score = $score; low_score = $low; manager_emailed = [bool]$mail.sent; postmark_message_id = [string]$mail.messageId; cloudradial_recorded = $crRecorded
        actions = @($actions); warnings = @($warnings)
    })
