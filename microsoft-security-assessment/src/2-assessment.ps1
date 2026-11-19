# === NODE: Create CloudRadial assessment ===
# Makes sure the company has the type 20 assessment "<name>" that the portal lists under
# Compliance > Assessments, holding this review's answers. The first run creates it from JSON
# (POST /v2/assessment); later runs refresh its questions and answers in place, matched on each
# check's updateKey, so the same row and its runs stay linked. Plan mode stops before any write.
#{{COMMON}}
$in = Read-StepInput
if ([string](Get-Prop $in 'status' '') -ne 'success') { Stop-Run 'The review step did not finish, so there is nothing to create.' }
$companyId = [int](Get-Prop $in 'companyId' 0)
$companyName = [string](Get-Prop $in 'companyName' '')
$title = [string](Get-Prop $in 'assessmentTitle' '')
$runTitle = [string](Get-Prop $in 'runTitle' '')
$summary = [string](Get-Prop $in 'summary' '')
$mode = [string](Get-Prop $in 'mode' 'apply')
$uploads = [string](Get-Prop $in 'uploads' 'both')
$questions = @(Get-Prop $in 'questions' @())
if ($companyId -le 0 -or -not $title -or -not $runTitle -or $questions.Count -eq 0) { Stop-Run 'The review step output is missing companyId, assessmentTitle, runTitle or questions.' }
# Passed on to the run step.
$carry = [ordered]@{ companyId = $companyId; companyName = $companyName; assessmentTitle = $title; runTitle = $runTitle; summary = $summary; mode = $mode; uploads = $uploads; portalUrl = [string](Get-Prop $in 'portalUrl' ''); questions = $questions }

if ($mode -eq 'plan') {
    $out = [ordered]@{ status = 'success'; message = "Plan only. The assessment is '$title' (type 20, created only if $companyName doesn't have it yet)." }
    foreach ($k in $carry.Keys) { $out[$k] = $carry[$k] }
    $out.parent = $null
    Set-NodeOutput $out
    return
}

$null = Connect-Cr
try { $all = @(Get-CompanyAssessments $companyId) }
catch { Stop-Run "Couldn't list this company's assessments, so nothing was created (to avoid a duplicate). $($_.Exception.Message)" }
$parentRow = Find-Assessment $all $title 20
$action = 'exists'
$scores = $null
if (-not $parentRow -and $uploads -eq '30') { $action = 'missing' }
elseif ($uploads -ne '30') {
    try { $sync = Sync-CrAssessment -CompanyId $companyId -Title $title -Questions (ConvertTo-CrQuestions $questions) -Category 'Security' -Description "Microsoft 365 security review for $companyName, refreshed by AutomationAI." -Visibility 2 }
    catch { Stop-Run "Couldn't $(if ($parentRow) { "refresh the answers in '$title'" } else { "create the assessment '$title'" }) for ${companyName}: $($_.Exception.Message)" }
    $action = $(if ($sync.action -eq 'created') { 'created' } else { 'refreshed' })
    $scores = $sync.scores
    $parentRow = @(@(Get-CompanyAssessments $companyId) | Where-Object { [int](Get-Prop $_ 'assessmentId' 0) -eq [int]$sync.assessmentId }) | Select-Object -First 1
    if (-not $parentRow) { $parentRow = [pscustomobject]@{ assessmentId = [int]$sync.assessmentId; title = $title; type = 20 } }
}
$parent = $null
if ($parentRow) { $parent = [ordered]@{ assessmentId = [int](Get-Prop $parentRow 'assessmentId' 0); updateKey = [string](Get-Prop $parentRow 'updateKey' ''); action = $action; fields = Get-Fields $parentRow } }
$msg = switch ($action) {
    'created' { "Created the assessment '$title' for $companyName (assessmentId $($parent.assessmentId))." }
    'refreshed' { "Updated the answers in the assessment '$title' for $companyName (assessmentId $($parent.assessmentId))$(if ($scores) { ": total $(Get-Prop $scores 'totalScore') of $(Get-Prop $scores 'maxScore')" })." }
    'exists' { "The assessment '$title' already exists for $companyName (assessmentId $($parent.assessmentId))." }
    default { "$companyName has no assessment '$title' and assessmentType 30 skips creating it, so there is nothing to run." }
}
$out = [ordered]@{ status = 'success'; message = $msg }
foreach ($k in $carry.Keys) { $out[$k] = $carry[$k] }
$out.parent = $parent
Set-NodeOutput $out
