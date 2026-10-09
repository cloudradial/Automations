# === NODE: Create assessment run (IN DEVELOPMENT) ===
# In development: on a live test (2026-10-06) the portal API refused the CloudRadial API key (HTTP 401),
# so this step currently ends with status 'unsupported' and creates nothing. It will work if CloudRadial
# accepts API keys there or adds a v2 run endpoint. Until then, create the run in the portal.
# Creates today's run of the assessment the way the portal's Run button does:
# POST <portal>/api/assessments/run {id, name}, which copies the assessment (questions, answers and
# updateKey) into a linked type 30 run. That is the portal's own internal API, not the public v2 API:
# the v2 upload can't link a run (it ignores updateKey; verified live), and v2 has no run
# endpoint. The portal API normally takes the signed-in user's token, so this step first checks with
# a read-only request that it accepts the CloudRadial API key, and creates nothing if it doesn't.
# Needs portalUrl (run input) or the CloudRadial-PortalUrl secret, e.g. https://contoso.us.cloudradial.com.
#{{COMMON}}
$in = Read-StepInput
$companyId = [int](Get-Prop $in 'companyId' 0)
$companyName = [string](Get-Prop $in 'companyName' '')
$title = [string](Get-Prop $in 'assessmentTitle' '')
$runTitle = [string](Get-Prop $in 'runTitle' '')
$summary = [string](Get-Prop $in 'summary' '')
$mode = [string](Get-Prop $in 'mode' 'apply')
$uploads = [string](Get-Prop $in 'uploads' 'both')
$portalUrl = ([string](Get-Prop $in 'portalUrl' '')).Trim().TrimEnd('/')
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
if ($mode -eq 'plan') { Out-Run 'success' "Plan only. Would create the run '$runTitle' of '$title' for $companyName through the portal's Run endpoint, unless that run already exists."; return }
if ($parentId -le 0) { Out-Run 'skipped' "There is no assessment '$title' for $companyName to create a run of."; return }

Connect-Cr
if (-not $portalUrl) { $portalUrl = ([string](Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'CloudRadial-PortalUrl' -AsPlainText -ErrorAction SilentlyContinue)).Trim().TrimEnd('/') }
if (-not $portalUrl) { Out-Run 'skipped' "No run was created: send portalUrl in the run input (or add the CloudRadial-PortalUrl secret) to create runs automatically, or create the run from '$title' (assessmentId $parentId) in the portal."; return }
if ($portalUrl -notmatch '^https://[a-z0-9.-]+\.cloudradial\.com$') { Stop-Run "portalUrl must look like https://<name>.us.cloudradial.com (got '$portalUrl')." }

try { $all = @(Get-CompanyAssessments $companyId) }
catch { Stop-Run "Couldn't list this company's assessments, so no run was created (to avoid a duplicate). $($_.Exception.Message)" }
$existing = Find-Assessment $all $runTitle 30
if ($existing) {
    $k = [string](Get-Prop $existing 'updateKey' '')
    Out-Run 'skipped' "The run '$runTitle' already exists for $companyName (assessmentId $(Get-Prop $existing 'assessmentId')). Nothing was changed." @{ assessmentId = [int](Get-Prop $existing 'assessmentId' 0); linked = [bool]($parentKey -and $k -eq $parentKey); run = Get-Fields $existing }
    return
}

$pHeaders = @{ Authorization = $script:crAuth; Accept = 'application/json' }
function Get-HttpCode { param($err) $r = Get-Prop $err.Exception 'Response'; if ($r) { try { return [int]$r.StatusCode } catch { } }; return 0 }
# 1. Read-only check that the portal API accepts the API key.
try { $null = Invoke-RestMethod -Method Get -Uri "$portalUrl/api/assessments?s=0&t=1&f=id&c=eq&v=$parentId" -Headers $pHeaders }
catch {
    $code = Get-HttpCode $_
    Out-Run 'unsupported' "No run was created: the portal API at $portalUrl refused the CloudRadial API key (HTTP $code), so it only accepts a signed-in user. Create the run from '$title' (assessmentId $parentId) in the portal." @{ portalHttpStatus = $code }
    return
}
# 2. Same call as the portal's Run button.
try { $r = Invoke-RestMethod -Method Post -Uri "$portalUrl/api/assessments/run" -Headers $pHeaders -ContentType 'application/json' -Body (@{ id = $parentId; name = $runTitle } | ConvertTo-Json -Compress) }
catch { Stop-Run "The portal accepted the API key for reading but the Run call failed (HTTP $(Get-HttpCode $_)): $($_.Exception.Message) $(if ($_.ErrorDetails) { $_.ErrorDetails.Message })" }
$runId = 0; [int]::TryParse([string](Get-Prop $r 'data' ''), [ref]$runId) | Out-Null
$runRow = $null
foreach ($wait in @(0, 3, 10)) {
    if ($wait) { Start-Sleep -Seconds $wait }
    try { $all = @(Get-CompanyAssessments $companyId) } catch { continue }
    $runRow = $(if ($runId -gt 0) { @($all | Where-Object { [int](Get-Prop $_ 'assessmentId' 0) -eq $runId }) | Select-Object -First 1 } else { Find-Assessment $all $runTitle 30 })
    if ($runRow) { break }
}
if (-not $runRow) { Stop-Run "The portal's Run call succeeded (reply data: '$(Get-Prop $r 'data' '')') but the new run wasn't found in /v2/odata/assessment. Check '$title' in the portal." }
$runId = [int](Get-Prop $runRow 'assessmentId' 0)
$runKey = [string](Get-Prop $runRow 'updateKey' '')
$linked = [bool]($parentKey -and $runKey -eq $parentKey)
Out-Run $(if ($linked) { 'success' } else { 'unlinked' }) "Created the run '$runTitle' (assessmentId $runId) of '$title' for $companyName through the portal's Run endpoint$(if ($linked) { '. It is linked to the assessment.' } else { ", but its updateKey $runKey doesn't match the assessment's $parentKey." }) The run copies the assessment's answers." @{
    assessmentId = $runId; linked = $linked; updateKey = $runKey; parentUpdateKey = $parentKey
    compliantScore = Get-Prop $runRow 'compliantScore'; partialScore = Get-Prop $runRow 'partialScore'; totalScore = Get-Prop $runRow 'totalScore'; maxScore = Get-Prop $runRow 'maxScore'
    run = Get-Fields $runRow; parent = Get-Prop $parent 'fields'; companyAssessments = Get-Listing $all }
