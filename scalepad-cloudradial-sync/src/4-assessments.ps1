#{{COMMON}}
# =====================================================================
# Step 4 - Assessments -> CloudRadial assessment (JSON assessment API)
#   Each ScalePad assessment becomes one CloudRadial assessment (type 20) created with its questions and
#   ScalePad's own answer options, answered, then run once so the portal lists it with its score.
# =====================================================================
$phase = 'assessments'
$results = ConvertTo-Dict (Get-P $ctx 'results')
$settings = Get-P $ctx 'settings'
$companyId = [int](Get-P $ctx 'companyId')
$spClientId = [string](Get-P $ctx 'scalePadClientId')
$counts = [ordered]@{ scalePadAssessments = 0; alreadyInCloudRadial = 0; toImport = 0; imported = 0; questions = 0; errors = 0 }
$items = New-Object System.Collections.ArrayList

$ScoreText = @{ 2 = 'Compliant'; 1 = 'Partially Compliant'; 0 = 'N/A'; -1 = 'Missing answer'; -2 = 'Not compliant' }
$Suffix = @{ 2 = ''; 1 = '+'; 0 = '='; -1 = '*'; -2 = '-' }

function Get-LabelScore { param([string]$key, [string]$label, $overrides)
    if ($null -ne $overrides) { $o = Get-P $overrides $key; if ($null -ne $o) { return [int]$o } }
    $t = ("$label $key").ToLowerInvariant()
    if ($t -match 'not applicable|n/a|\bna\b|notapplicable') { return 0 }
    if ($t -match 'partial|needs attention|needsattention|some|in progress|inprogress|moderate|minor') { return 1 }
    if ($t -match 'unanswered|unknown|not assessed|notassessed') { return -1 }
    if ($t -match '\bno\b|not |non|fail|unsatisf|at risk|atrisk|missing|critical|major|poor|\bnone\b|high risk|highrisk') { return -2 }
    if ($t -match 'yes|satisf|compliant|pass|good|complete|met|low risk|lowrisk|healthy') { return 2 }
    return -1
}
function Get-Text { param($v) if ($null -eq $v) { return '' }; if ($v -is [string]) { return $v }; $t = Get-P $v 'text' (Get-P $v 'comment' (Get-P $v 'value' '')); return [string]$t }
# Answers many questions in one call. Invoke-Cr sends PATCH as a JSON Patch array, so this one calls the API directly.
function Set-CrAnswers { param([int]$AssessmentId, [object[]]$Answers)
    $json = [ordered]@{ answers = $Answers } | ConvertTo-Json -Depth 8
    return Invoke-WithRetry -What "CloudRadial PATCH /v2/assessment/$AssessmentId/answers" -Call { Invoke-RestMethod -Method Patch -Uri "$crBase/v2/assessment/$AssessmentId/answers?companyId=$companyId" -Headers $crHeaders -ContentType 'application/json' -Body $json }
}

if ((Get-P $ctx 'phases' @()) -notcontains $phase) {
    $results[$phase] = [ordered]@{ ran = $false }
}
else {
    $labels = @{}
    try {
        foreach ($t in @(Get-P (Get-SpOne '/lifecycle-manager/v1/assessments/criteria/labels') 'data' @())) {
            foreach ($l in @(Get-P $t 'assessment_criterion_labels' @())) { $labels[[string](Get-P $l 'label_key')] = [string](Get-P $l 'label') }
        }
    } catch { Warn "Could not read ScalePad answer labels; scoring falls back to the answer text. $($_.Exception.Message)" }
    $overrides = Get-P $settings 'labelScoreMap'
    if ($overrides -is [string] -and -not (Test-Blank $overrides)) { try { $overrides = $overrides | ConvertFrom-Json } catch { Warn 'labelScoreMap is not valid JSON; ignored.'; $overrides = $null } }

    $status = [string](Get-P $settings 'assessmentStatus' 'Completed')
    $q = @{ 'filter[client.id]' = "eq:$spClientId" }
    if (-not (Test-Blank $status) -and $status -ne 'all') { $q['filter[status]'] = "eq:$status" }
    $list = @(Get-SpAll '/lifecycle-manager/v1/assessments' $q)
    $counts.scalePadAssessments = $list.Count
    $assessDiag = $null
    if ($list.Count -eq 0) {
        try {
            $probe = Invoke-WithRetry -What 'ScalePad GET /lifecycle-manager/v1/assessments (all clients)' -Call { Invoke-RestMethod -Method Get -Uri "$spBase/lifecycle-manager/v1/assessments?page_size=25" -Headers $spHeaders }
            $sampleClients = @(@(Get-P $probe 'data' @()) | ForEach-Object { "$(Get-P $_ 'client.label' (Get-P $_ 'client.name' (Get-P $_ 'client_name' 'client'))) ($(Get-P $_ 'client.id' (Get-P $_ 'client_id' '?')), $(Get-P $_ 'status' ''))" } | Select-Object -Unique -First 10)
            # Run output only - this lists other clients, so it must not reach this client's portal.
            $assessDiag = "ScalePad returned no assessments for client $spClientId. Across all clients it has $(Get-P $probe 'total_count' @(Get-P $probe 'data' @()).Count) assessment(s)$(if ($sampleClients.Count) { ', e.g. ' + ($sampleClients -join '; ') })."
        } catch { $assessDiag = "ScalePad returned no assessments for client $spClientId, and the all-clients check failed: $($_.Exception.Message)" }
    }

    $crTitles = New-Object System.Collections.Generic.HashSet[string]
    $crAssess = $null
    foreach ($path in @("/v2/odata/assessment?`$filter=companyId eq $companyId&`$select=assessmentId,title", "/v2/odata/assessment?`$filter=companyId eq $companyId", '/v2/odata/assessment')) {
        try { $crAssess = @(Get-CrAll $path | Where-Object { [int](Get-P $_ 'companyId' $companyId) -eq $companyId }); break } catch { $lastAssessErr = $_.Exception.Message }
    }
    if ($null -eq $crAssess) { Warn "Couldn't list CloudRadial assessments to check for ones already imported ($lastAssessErr) - assessments were not imported this run to avoid duplicates."; $crAssess = @(); $assessReadFailed = $true } else { $assessReadFailed = $false }
    foreach ($a in $crAssess) { $null = $crTitles.Add(([string](Get-P $a 'title' (Get-P $a 'name' ''))).ToLowerInvariant()) }

    $scoreUse = @{}
    foreach ($s in $list) {
        $spId = [string](Get-P $s 'id')
        $title = 'ScalePad - ' + [string](Get-P $s 'title' 'Assessment')
        $evaluated = Format-Day (Get-P $s 'evaluated_at')
        if ($evaluated) { $title = "$title ($evaluated)" }
        if ($crTitles.Contains($title.ToLowerInvariant())) { $counts.alreadyInCloudRadial++; $null = $items.Add(@{ title = $title; action = 'skip'; reason = 'already in CloudRadial' }); continue }

        $full = Get-P (Get-SpOne "/lifecycle-manager/v1/assessments/$spId") 'assessment'
        $rows = New-Object System.Collections.ArrayList
        $catNo = 0
        foreach ($cat in @(Get-P $full 'category_list' @())) {
            $catNo++
            $catTitle = '{0}. {1}' -f $catNo, [string](Get-P $cat 'title' 'General')
            $order = 0
            foreach ($qn in @(Get-P $cat 'question_list' @())) {
                $order += 10
                $options = @(); $answer = -1
                foreach ($cr in @(Get-P $qn 'criteria_list' @())) {
                    $key = [string](Get-P $cr 'label_key' '')
                    $label = [string](Get-P $cr 'display_label' (Get-P $labels $key $key))
                    $sc = Get-LabelScore $key $label $overrides
                    $scoreUse["$label"] = $sc
                    if (-not @($options | Where-Object { $_.label -eq $label }).Count) { $options += [ordered]@{ label = $label; value = $sc } }
                    if ((Get-P $cr 'is_selected' $false) -eq $true) { $answer = $sc }
                }
                # No criteria: the partner's default answer options. A choice question can't offer the same value twice, so keep the first.
                $seenValues = @{}; $options = @($options | Where-Object { if ($seenValues.ContainsKey([int]$_.value)) { $false } else { $seenValues[[int]$_.value] = $true; $true } })
                $tips = [string](Get-P $qn 'remediation_tips' '')
                $summary = if ($tips) { ($tips -split '(?<=[.!?])\s')[0] } else { '' }
                $refs = @(@(Get-P $qn 'linked_initiatives' @()) | ForEach-Object { Get-P $_ 'initiative_name' } | Where-Object { $_ }) -join '; '
                $explain = [string](Get-P $qn 'description' ''); if ($refs) { $explain = ("$explain Linked initiatives: $refs").Trim() }
                $qk = "scalepad-$spId-$([string](Get-P $qn 'id' "$catNo-$order"))"
                $qb = [ordered]@{
                    updateKey = $qk; category = $catTitle; label = [string](Get-P $qn 'title' ''); order = $order; explanation = $explain
                    evaluationInfo = [string](Get-P $qn 'scoring_instructions' ''); remediationInfo = $tips; remediationLineItem = $summary
                    value = $answer; isFlagged = ($answer -eq -2); publicNotes = (Get-Text (Get-P $qn 'public_comment')); privateNotes = (Get-Text (Get-P $qn 'internal_comments'))
                }
                if ($options.Count) { $qb.answerOptions = $options }
                $null = $rows.Add($qb)
            }
        }
        $counts.questions += $rows.Count
        if ($rows.Count -eq 0) { $null = $items.Add(@{ title = $title; action = 'skip'; reason = 'no questions' }); continue }
        $counts.toImport++
        $item = [ordered]@{ title = $title; action = 'import'; questions = $rows.Count; scalePadScore = Get-P $s 'overall_score' }
        if ($apply -and -not $assessReadFailed) {
            try {
                $desc = "Imported from ScalePad Lifecycle Manager. $([string](Get-P $full 'description' ''))".Trim()
                $structure = @($rows | ForEach-Object { $b = [ordered]@{}; foreach ($k in $_.Keys) { if ($k -notin @('value', 'isFlagged', 'publicNotes', 'privateNotes')) { $b[$k] = $_[$k] } }; $b['type'] = 80; , $b })
                $created = Invoke-Cr -Method POST -Path '/v2/assessment' -Body ([ordered]@{ companyId = $companyId; title = $title; type = 20; category = 'ScalePad'; description = $desc; visibility = 2; questions = $structure })
                $aid = Get-P (Get-P $created 'data' $created) 'assessmentId' (Get-P $created 'assessmentId')
                if (-not $aid) { throw 'CloudRadial did not return an assessmentId.' }
                $item.assessmentId = [int]$aid
                $answers = @($rows | ForEach-Object { [ordered]@{ updateKey = $_.updateKey; value = $_.value; isFlagged = $_.isFlagged; publicNotes = $_.publicNotes; privateNotes = $_.privateNotes } })
                $scored = Set-CrAnswers -AssessmentId ([int]$aid) -Answers $answers
                $item.score = Get-P (Get-P (Get-P $scored 'data' $scored) 'scores') 'totalScore'
                # A run is what the portal's Assessments list shows (date run, score and status).
                $runName = "$title - $((Get-Date).ToString('M/d/yy', [Globalization.CultureInfo]::InvariantCulture))"
                $run = Invoke-Cr -Method POST -Path "/v2/assessment/$aid/run" -Body ([ordered]@{ companyId = $companyId; name = $runName })
                $item.runId = [int](Get-P (Get-P $run 'data' $run) 'assessmentId' 0)
                $counts.imported++
            }
            catch { $counts.errors++; $item.error = $_.Exception.Message; Warn "Assessment '$title' failed: $($_.Exception.Message)" }
        }
        $null = $items.Add($item)
    }
    $results[$phase] = [ordered]@{ ran = $true; diagnostic = $assessDiag; counts = $counts; items = @($items); answerScoring = $scoreUse }
}

$ctx.results = $results
$ctx.warnings = @(@(Get-P $ctx 'warnings' @()) + @($warnings))
$c = $counts
Set-NodeOutput @{ status = 'ok'; message = "Assessments: $($c.scalePadAssessments) in ScalePad, $($c.alreadyInCloudRadial) already in CloudRadial, $(if ($apply) { "$($c.imported) imported" } else { "$($c.toImport) to import" }) ($($c.questions) questions), $($c.errors) errors."; ctx = $ctx }
