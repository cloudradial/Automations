# Step 1: Read the request.
# Two entry points into the same workflow:
#   mode "survey" (the default): a ticket was closed. Checks it should get a survey (not closed as duplicate
#     or spam, no survey sent before) and hands the details to step 2.
#   mode "score": the requester answered the survey. Checks the score is valid, that a survey was sent for
#     this ticket, and that no score was recorded before, and hands the details to step 3.
# Nothing is written here. Skips end the run with status success and a plain reason.
$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
$stopState = @{ done = $false }
function Stop-Parse {
    param([string]$Status, [string]$Why, [string]$TicketId = '', [string]$Mode = '')
    $stopState.done = $true
    Set-NodeOutput ([ordered]@{ status = $Status; message = $Why; public_note = ''; internal_note = "Post-close feedback did not run: $Why"; ticket_id = $TicketId; mode = $Mode; actions = @($actions); warnings = @($warnings); ctx_json = '' })
    throw $Why
}
trap { if (-not $stopState.done) { $stopState.done = $true; $m = [string]$_.Exception.Message; Set-NodeOutput ([ordered]@{ status = 'error'; message = $m; public_note = ''; internal_note = "Post-close feedback failed: $m"; ticket_id = ''; mode = ''; actions = @($actions); warnings = @($warnings); ctx_json = '' }) }; break }
function Skip-Parse {
    param([string]$Why, [string]$TicketId, [string]$Mode)
    $stopState.done = $true
    $ctx = @{ skip = $true; mode = $Mode; ticket_id = $TicketId; result = [ordered]@{ status = 'success'; message = $Why; public_note = ''; internal_note = ''; ticket_id = $TicketId; mode = $Mode; survey_sent = $false; score = $null; low_score = $false; manager_emailed = $false; actions = @($actions); warnings = @($warnings) } }
    Set-NodeOutput ([ordered]@{ status = 'success'; message = $Why; ticket_id = $TicketId; mode = $Mode; ctx_json = (ConvertTo-Json -InputObject $ctx -Depth 8 -Compress) })
}
function Get-Int { param([string]$s, [int]$Default) $n = 0; if ($s -and [int]::TryParse($s, [ref]$n)) { return $n }; return $Default }

$a = Read-StepTrigger (Get-NodeInput)
$ticketId = Get-StepField $a @('ticketId', 'ticket_id', 'TicketId', 'ticketNumber', 'TicketNumber')
$scoreRaw = Get-StepField $a @('score', 'rating', 'Score')
$mode = (Get-StepField $a @('mode')).ToLowerInvariant()
if (-not $mode) { $mode = $(if ($scoreRaw) { 'score' } else { 'survey' }) }
$contact = Get-StepField $a @('contactEmail', 'contact_email', 'requesterEmail', 'requester_email', 'UserEmail')
$preview = Test-StepTrue (Get-StepField $a @('preview', 'dryRun', 'dry_run'))
$scoreMax = Get-Int (Get-StepField $a @('score_max', 'scoreMax')) 5
$threshold = Get-Int (Get-StepField $a @('threshold', 'low_score_threshold')) 2

if (@('survey', 'score') -notcontains $mode) { Stop-Parse 'rejected' "Mode '$mode' isn't one of: survey, score." $ticketId $mode }
if (-not $ticketId) { Stop-Parse 'incomplete' 'The request has no ticket number, so nothing was done.' '' $mode }
if ($ticketId -notmatch '^[A-Za-z0-9-]{1,40}$') { Stop-Parse 'rejected' "Ticket number '$ticketId' isn't valid, so nothing was done." '' $mode }
if ($scoreMax -lt 2 -or $scoreMax -gt 10) { Stop-Parse 'rejected' "score_max must be between 2 and 10 (it was $scoreMax)." $ticketId $mode }

$feedbackUrl = ''
$score = 0
if ($mode -eq 'survey') {
    $feedbackUrl = Get-StepField $a @('feedback_url', 'feedbackUrl')
    if (-not $feedbackUrl) { $feedbackUrl = [string](Get-PsaSecret 'CSAT-FeedbackUrl') }
    if (-not $feedbackUrl) { Stop-Parse 'incomplete' 'No survey link is set. Add the CSAT-FeedbackUrl secret or send feedback_url, so the survey has somewhere to send the answer.' $ticketId $mode }
    if ($feedbackUrl -notmatch '^https://') { Stop-Parse 'rejected' 'The survey link must start with https://.' $ticketId $mode }
}
else {
    if (-not $scoreRaw) { Stop-Parse 'incomplete' "The score for ticket $ticketId is missing, so nothing was recorded." $ticketId $mode }
    if (-not [int]::TryParse($scoreRaw, [ref]$score) -or $score -lt 1 -or $score -gt $scoreMax) { Stop-Parse 'rejected' "The score '$scoreRaw' isn't a whole number from 1 to $scoreMax, so nothing was recorded." $ticketId $mode }
}

$conn = Connect-Psa (Get-PsaType (Get-StepField $a @('psa')))
$t = Get-PsaTicket $ticketId
$null = $actions.Add("Read ticket $ticketId from $(Get-PsaName).")
# A portal form sends @CompanyPsaId, which the requester can't change: the ticket must belong to that company.
$psaCo = Get-StepField $a @('company_psa_id', 'CompanyPsaId')
if ($psaCo -and [string]$t.companyId -and $psaCo -ne [string]$t.companyId) { Stop-Parse 'rejected' "Ticket $ticketId belongs to a different company, so nothing was done." $ticketId $mode }
$notes = @(Get-PsaNotes $ticketId)
$marker = "How did we do on ticket $ticketId"
$surveySent = @($notes | Where-Object { $_.public -and ([string]$_.text).Contains($marker) }).Count -gt 0
$tplUrl = [string](Get-PsaSecret 'PSA-TicketUrlTemplate')
$ctx = @{
    skip = $false; mode = $mode; ticket_id = $ticketId; psa = $conn.Psa; psa_name = (Get-PsaName); summary = [string]$t.summary; company_id = [string]$t.companyId
    contact = $contact; preview = $preview; score_max = $scoreMax; ticket_url = (Get-PsaTicketUrl $ticketId $tplUrl); actions = @($actions); warnings = @($warnings)
}

if ($mode -eq 'survey') {
    $status = Get-StepField $a @('status', 'newStatus', 'new_status', 'Status', 'StatusName')
    if (-not $status) { $status = [string]$t.status }
    $status = Get-PsaStatusName $status
    $reason = Get-StepField $a @('close_reason', 'closeReason', 'resolution')
    $skipRaw = Get-StepField $a @('skip_statuses', 'skipStatuses')
    $skipList = if ($skipRaw) { @(Get-StepList $skipRaw) } else { @('Duplicate', 'Spam', 'Merged', 'Cancelled', 'Canceled', 'Junk', 'No Response Needed') }
    foreach ($s in $skipList) {
        $pat = if ($s.Contains('*')) { $s } else { "*$s*" }
        if ($status -like $pat -or $reason -like $pat) { Skip-Parse "Ticket $ticketId was closed as $(if ($status -like $pat) { $status } else { $reason }), so no survey was sent." $ticketId $mode; return }
    }
    if ($surveySent) { Skip-Parse "A survey was already sent for ticket $ticketId, so it wasn't sent again." $ticketId $mode; return }
    if (-not $contact) { $null = $warnings.Add('No contactEmail was sent. The PSA sends the survey to the ticket''s own contact.') }
    $ctx.feedback_url = $feedbackUrl
    $ctx.status = $status
    $ctx.warnings = @($warnings)
    Set-NodeOutput ([ordered]@{ status = 'success'; message = "Ticket $ticketId ($status) will get a survey."; ticket_id = $ticketId; mode = $mode; ctx_json = (ConvertTo-Json -InputObject $ctx -Depth 8 -Compress) })
    return
}

# ---- score mode ----
$requireSurvey = $true; $rs = Get-StepField $a @('require_survey', 'requireSurvey'); if ($rs) { $requireSurvey = Test-StepTrue $rs }
if ($requireSurvey -and -not $surveySent) { Stop-Parse 'rejected' "No survey was sent for ticket $ticketId, so the score wasn't accepted." $ticketId $mode }
$prior = @($notes | Where-Object { -not $_.public -and ([string]$_.text).TrimStart().StartsWith('Satisfaction score received') }).Count -gt 0
if ($prior) { Skip-Parse "A score for ticket $ticketId was already recorded, so this one was ignored." $ticketId $mode; return }
$managers = @(Get-StepList (Get-StepField $a @('service_manager_email', 'serviceManagerEmail')))
if (-not $managers.Count) { $managers = @(Get-StepList ([string](Get-PsaSecret 'CSAT-ServiceManagerEmail'))) }
$comment = Get-StepField $a @('comment', 'feedback_comment', 'feedbackComment')
if ($comment.Length -gt 1000) { $comment = $comment.Substring(0, 1000) + '...' }
$ctx.score = $score
$ctx.threshold = $threshold
$ctx.low = ($score -le $threshold)
$ctx.comment = $comment
$ctx.managers = @($managers | Where-Object { Test-StepEmail $_ })
$ctx.cr_company_id = Get-StepField $a @('cr_company_id', 'crCompanyId', 'Company.CompanyId')
Set-NodeOutput ([ordered]@{ status = 'success'; message = "Ticket $ticketId was rated $score out of $scoreMax."; ticket_id = $ticketId; mode = $mode; ctx_json = (ConvertTo-Json -InputObject $ctx -Depth 8 -Compress) })
