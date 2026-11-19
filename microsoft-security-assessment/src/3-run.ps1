# === NODE: Create assessment run ===
# Creates today's run of the assessment through POST /v2/assessment/{id}/run, the same assessment service
# the portal's Run button uses: a dated type 30 copy with the assessment's answers and its updateKey, so the
# portal links the two and shows the run's score in the Assessments list. A run with the same title is never
# created twice.
#{{COMMON}}
$in = Read-StepInput
$companyId = [int](Get-Prop $in 'companyId' 0)
$companyName = [string](Get-Prop $in 'companyName' '')
$title = [string](Get-Prop $in 'assessmentTitle' '')
$runTitle = [string](Get-Prop $in 'runTitle' '')
$summary = [string](Get-Prop $in 'summary' '')
$mode = [string](Get-Prop $in 'mode' 'apply')
$uploads = [string](Get-Prop $in 'uploads' 'both')
$questions = @(Get-Prop $in 'questions' @())
$parent = Get-Prop $in 'parent'
$parentId = [int](Get-Prop $parent 'assessmentId' 0)
$parentKey = [string](Get-Prop $parent 'updateKey' '')
$preview = Get-Preview $questions
function Out-Run { param([string]$Status, [string]$Message, [hashtable]$More = @{})
    $o = [ordered]@{ status = $Status; mode = $mode; message = "$Message $summary".Trim(); companyId = $companyId; parentAssessmentId = $parentId; title = $runTitle }
    foreach ($k in $More.Keys) { $o[$k] = $More[$k] }
    $o.questions = $preview
    Set-NodeOutput $o }

if ($uploads -eq '20') { Out-Run 'skipped' 'assessmentType 20: only the assessment was requested, so no run was created.'; return }
if ($mode -eq 'plan') { Out-Run 'success' "Plan only. Would create the run '$runTitle' of '$title' for $companyName, unless that run already exists."; return }
if ($parentId -le 0) { Out-Run 'skipped' "There is no assessment '$title' for $companyName to create a run of."; return }

$null = Connect-Cr

try { $all = @(Get-CompanyAssessments $companyId) }
catch { Stop-Run "Couldn't list this company's assessments, so no run was created (to avoid a duplicate). $($_.Exception.Message)" }
$existing = Find-Assessment $all $runTitle 30
if ($existing) {
    $k = [string](Get-Prop $existing 'updateKey' '')
    Out-Run 'skipped' "The run '$runTitle' already exists for $companyName (assessmentId $(Get-Prop $existing 'assessmentId')). Nothing was changed." @{ assessmentId = [int](Get-Prop $existing 'assessmentId' 0); linked = [bool]($parentKey -and $k -eq $parentKey); run = Get-Fields $existing }
    return
}

try { $run = Invoke-CrApi -Path "/v2/assessment/$parentId/run" -Method POST -Body ([ordered]@{ companyId = $companyId; name = $runTitle }) }
catch { Stop-Run "Couldn't create the run '$runTitle' of '$title' (assessmentId $parentId): $($_.Exception.Message)" }
$runRow = Get-Prop $run 'data'; if ($null -eq $runRow) { $runRow = $run }
$runId = [int](Get-Prop $runRow 'assessmentId' 0)
if ($runId -le 0) { Stop-Run "CloudRadial answered the run request for '$title' without an assessmentId." }
$runKey = [string](Get-Prop $runRow 'updateKey' '')
$linked = [bool]($parentKey -and $runKey -eq $parentKey)
$all = @(); try { $all = @(Get-CompanyAssessments $companyId) } catch { }
Out-Run $(if ($linked -or -not $parentKey) { 'success' } else { 'unlinked' }) "Created the run '$runTitle' (assessmentId $runId) of '$title' for $companyName$(if ($linked) { '. It is linked to the assessment.' } elseif ($parentKey) { ", but its updateKey $runKey doesn't match the assessment's $parentKey." } else { '.' }) The run copies the assessment's answers." @{
    assessmentId = $runId; linked = $linked; updateKey = $runKey; parentUpdateKey = $parentKey
    compliantScore = Get-Prop $runRow 'compliantScore'; partialScore = Get-Prop $runRow 'partialScore'; totalScore = Get-Prop $runRow 'totalScore'; maxScore = Get-Prop $runRow 'maxScore'
    run = Get-Fields $runRow; parent = Get-Prop $parent 'fields'; companyAssessments = @($all | Sort-Object { [int](Get-Prop $_ 'assessmentId' 0) } -Descending | Select-Object -First 25 | ForEach-Object { Get-Fields $_ }) }
