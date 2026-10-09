# === NODE: Create CloudRadial assessment ===
# Makes sure the company has the type 20 assessment "<name>" that the portal lists under
# Compliance > Assessments, holding this review's answers. The first run uploads it. Later runs
# re-upload into it (assessmentId set), which replaces the answers in place - live, 2026-10-06: the
# same row and updateKey, max score unchanged, total +6 -> -6 (verified live on a test tenant). A run created from
# it in the portal then copies the current answers. Plan mode stops before any write.
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

Connect-Cr
try { $all = @(Get-CompanyAssessments $companyId) }
catch { Stop-Run "Couldn't list this company's assessments, so nothing was created (to avoid a duplicate). $($_.Exception.Message)" }
$parentRow = Find-Assessment $all $title 20
$action = 'exists'
if (-not $parentRow) {
    if ($uploads -eq '30') { $action = 'missing' }
    else {
        $parentRow = Invoke-AssessmentUpload -CompanyId $companyId -CompanyName $companyName -Name $title -Type 20 -Bytes (New-AssessmentWorkbook $questions) -Label 'assessment'
        $action = 'created'
    }
}
elseif ($uploads -ne '30') {
    # Refresh the existing assessment's answers in place.
    $pid0 = [int](Get-Prop $parentRow 'assessmentId' 0)
    $was = [string](Get-Prop $parentRow 'dateModified' '')
    $data = [ordered]@{ name = $title; assessmentId = $pid0; type = 20; companyId = $companyId } | ConvertTo-Json -Compress
    try { $null = Send-CrMultipart -Path '/v2/assessment/upload' -DataJson $data -FileBytes (New-AssessmentWorkbook $questions) -FileName ('m365-security-refresh-' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd') + '.xlsx') }
    catch { Stop-Run "Couldn't refresh the answers in '$title' (assessmentId $pid0): $($_.Exception.Message)" }
    foreach ($wait in @(2, 5, 10)) {
        Start-Sleep -Seconds $wait
        try { $fresh = @(@(Get-CompanyAssessments $companyId) | Where-Object { [int](Get-Prop $_ 'assessmentId' 0) -eq $pid0 }) | Select-Object -First 1 } catch { continue }
        if ($fresh) { $parentRow = $fresh; if ([string](Get-Prop $fresh 'dateModified' '') -ne $was) { break } }
    }
    $action = 'refreshed'
}
$parent = $null
if ($parentRow) { $parent = [ordered]@{ assessmentId = [int](Get-Prop $parentRow 'assessmentId' 0); updateKey = [string](Get-Prop $parentRow 'updateKey' ''); action = $action; fields = Get-Fields $parentRow } }
$msg = switch ($action) {
    'created' { "Created the assessment '$title' for $companyName (assessmentId $($parent.assessmentId))." }
    'refreshed' { "Updated the answers in the assessment '$title' for $companyName (assessmentId $($parent.assessmentId)): compliant $(Get-Prop $parentRow 'compliantScore'), partial $(Get-Prop $parentRow 'partialScore'), total $(Get-Prop $parentRow 'totalScore') of $(Get-Prop $parentRow 'maxScore'). A run created from it in the portal now carries these answers." }
    'exists' { "The assessment '$title' already exists for $companyName (assessmentId $($parent.assessmentId))." }
    default { "$companyName has no assessment '$title' and assessmentType 30 skips creating it, so the run won't be linked to one." }
}
$out = [ordered]@{ status = 'success'; message = $msg }
foreach ($k in $carry.Keys) { $out[$k] = $carry[$k] }
$out.parent = $parent
Set-NodeOutput $out
