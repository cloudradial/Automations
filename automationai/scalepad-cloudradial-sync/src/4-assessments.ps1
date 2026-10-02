#{{COMMON}}
# =====================================================================
# Step 4 - Assessments -> CloudRadial assessment (Excel import format)
#   Columns follow support KB 360052746791 "Importing Assessments".
#   The .xlsx is built in memory - nothing is written to storage.
# =====================================================================
$phase = 'assessments'
$results = ConvertTo-Dict (Get-P $ctx 'results')
$settings = Get-P $ctx 'settings'
$companyId = [int](Get-P $ctx 'companyId')
$spClientId = [string](Get-P $ctx 'scalePadClientId')
$counts = [ordered]@{ scalePadAssessments = 0; alreadyInCloudRadial = 0; toImport = 0; imported = 0; questions = 0; errors = 0 }
$items = New-Object System.Collections.ArrayList

$Columns = @('Category', 'Question', 'Order', 'Explanation', 'Type', 'Answer', 'Text Answer', 'Responses', 'Is Flagged', 'Notes', 'Evaluation', 'Remediation Summary', 'Remediation', 'Reference', 'Partner Notes')
# The official blank template (radials.io/blankassessment): sheet "Assessment", these 51
# headers in this order. The workbook is written in exactly this shape so it imports whether
# CloudRadial reads columns by name or by position; columns we don't fill stay empty.
$TemplateColumns = @('Partner Notes', 'Monthly Unit Cost', 'Project Unit Cost', 'Psa Board', 'Psa Item', 'Psa Status', 'Psa Category', 'Psa Sub Type', 'Psa Type', 'Psa Priority', 'Psa Source', 'Psa Estimated Time', 'Email List', 'Teams Webhook', 'Slack Webhook', 'Flow Webhook', 'Json Webhook', 'Script', 'Checklist', 'Category', 'Question', 'Order', 'Explanation', 'Type', 'Answer', 'Text Answer', 'Responses', 'Is Flagged', 'Notes', 'Evaluation', 'Remediation Summary', 'Remediation', 'Reference', 'Monthly Units', 'Monthly Unit Price', 'Project Units', 'Project Unit Price', 'Control Type', 'Likelihood', 'Risk', 'Risk Cost', 'Risk Impact', 'Owner', 'Updated by', 'Update Key', 'Content Update Key', 'Note Compliant', 'Note Partially Compliant', 'Note NA', 'Note Missing', 'Note Not Compliant')
function ConvertTo-TemplateRows { param([object[]]$Rows)
    $idx = @{}; for ($i = 0; $i -lt $Columns.Count; $i++) { $idx[$Columns[$i]] = $i }
    $out = New-Object System.Collections.ArrayList
    foreach ($r in $Rows) {
        $row = @($r)
        $null = $out.Add(@($TemplateColumns | ForEach-Object { if ($idx.ContainsKey($_)) { $row[$idx[$_]] } else { $null } }))
    }
    return $out.ToArray()
}
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
function New-XlsxBytes {
    # Minimal Office Open XML workbook: one sheet, inline strings, header row + data rows.
    param([string[]]$Header, [object[]]$Rows)
    Add-Type -AssemblyName System.IO.Compression
    $esc = { param($s) [System.Security.SecurityElement]::Escape([string]$s) }
    $colName = { param([int]$n) $s = ''; $n++; while ($n -gt 0) { $m = ($n - 1) % 26; $s = [char](65 + $m) + $s; $n = [int][Math]::Floor(($n - 1) / 26) }; $s }
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>')
    $all = @(, $Header) + $Rows
    for ($r = 0; $r -lt $all.Count; $r++) {
        $null = $sb.Append("<row r=""$($r + 1)"">")
        $row = @($all[$r])
        for ($c = 0; $c -lt $row.Count; $c++) {
            $ref = (& $colName $c) + ($r + 1)
            $val = $row[$c]
            if ($val -is [int] -or $val -is [long] -or $val -is [double]) { $null = $sb.Append("<c r=""$ref""><v>$val</v></c>") }
            elseif (-not [string]::IsNullOrEmpty([string]$val)) { $null = $sb.Append("<c r=""$ref"" t=""inlineStr""><is><t xml:space=""preserve"">$(& $esc $val)</t></is></c>") }
        }
        $null = $sb.Append('</row>')
    }
    $null = $sb.Append('</sheetData></worksheet>')
    $files = [ordered]@{
        '[Content_Types].xml'        = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'
        '_rels/.rels'                = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
        'xl/workbook.xml'            = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Assessment" sheetId="1" r:id="rId1"/></sheets></workbook>'
        'xl/_rels/workbook.xml.rels' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'
        'xl/worksheets/sheet1.xml'   = $sb.ToString()
    }
    $ms = New-Object System.IO.MemoryStream
    $zip = New-Object System.IO.Compression.ZipArchive($ms, [System.IO.Compression.ZipArchiveMode]::Create, $true)
    foreach ($k in $files.Keys) {
        $entry = $zip.CreateEntry($k)
        $w = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding($false)))
        $w.Write($files[$k]); $w.Dispose()
    }
    $zip.Dispose()
    return , $ms.ToArray()
}
if (-not (Get-Command Send-CrMultipart -ErrorAction SilentlyContinue)) {
    function script:Send-CrMultipart {
        param([string]$Path, [string]$DataJson, [byte[]]$FileBytes, [string]$FileName)
        Add-Type -AssemblyName System.Net.Http
        $client = New-Object System.Net.Http.HttpClient
        $client.DefaultRequestHeaders.Add('Authorization', $crAuth)
        $form = New-Object System.Net.Http.MultipartFormDataContent
        $form.Add((New-Object System.Net.Http.StringContent($DataJson, [Text.Encoding]::UTF8, 'application/json')), 'data')
        $fc = New-Object System.Net.Http.ByteArrayContent(, $FileBytes)
        $fc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
        $form.Add($fc, 'file', $FileName)
        $resp = $client.PostAsync("$crBase$Path", $form).GetAwaiter().GetResult()
        $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $client.Dispose()
        if (-not $resp.IsSuccessStatusCode) { throw "HTTP $([int]$resp.StatusCode): $text" }
        return $text
    }
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

    # No $select here: "$select=assessmentId,title" has returned HTTP 500 live.
    function Get-CrAssessments {
        $rows = $null; $lastErr = ''
        foreach ($path in @("/v2/odata/assessment?`$filter=companyId eq $companyId", '/v2/odata/assessment')) {
            try { $rows = @(Get-CrAll $path | Where-Object { [int](Get-P $_ 'companyId' $companyId) -eq $companyId -and (Get-P $_ 'isDeleted' $false) -ne $true }); break } catch { $lastErr = $_.Exception.Message }
        }
        if ($null -eq $rows) { throw $lastErr }
        return , $rows
    }
    function Get-AssessTitle { param($a) ([string](Get-P $a 'title' (Get-P $a 'name' ''))).Trim() }
    # The upload returns 204 with no body, so the new assessment is found by its title.
    function Find-CrAssessmentId { param([string]$Title)
        foreach ($wait in @(0, 3, 10)) {
            if ($wait) { Start-Sleep -Seconds $wait }
            try { $rows = Get-CrAssessments } catch { continue }
            $hit = @($rows | Where-Object { (Get-AssessTitle $_) -ieq $Title } | Sort-Object { [int](Get-P $_ 'assessmentId' 0) } -Descending)
            if ($hit.Count) { return [int](Get-P $hit[0] 'assessmentId' 0) }
        }
        return 0
    }

    $crTitles = New-Object System.Collections.Generic.HashSet[string]
    $crAssess = $null
    try { $crAssess = Get-CrAssessments; $assessReadFailed = $false }
    catch { Warn "Couldn't list CloudRadial assessments to check for ones already imported ($($_.Exception.Message)) - assessments were not imported this run to avoid duplicates."; $crAssess = @(); $assessReadFailed = $true }
    foreach ($a in $crAssess) { $null = $crTitles.Add((Get-AssessTitle $a).ToLowerInvariant()) }

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
                $responses = @(); $answer = -1
                foreach ($cr in @(Get-P $qn 'criteria_list' @())) {
                    $key = [string](Get-P $cr 'label_key' '')
                    $label = [string](Get-P $cr 'display_label' (Get-P $labels $key $key))
                    $sc = Get-LabelScore $key $label $overrides
                    $scoreUse["$label"] = $sc
                    $responses += ($label -replace ',', ' ') + $Suffix[$sc]
                    if ((Get-P $cr 'is_selected' $false) -eq $true) { $answer = $sc }
                }
                if ($responses.Count -eq 0) { $responses = @('Yes', 'Partially+', 'Not Applicable=', 'Unanswered*', 'No-') }
                $tips = [string](Get-P $qn 'remediation_tips' '')
                $summary = if ($tips) { ($tips -split '(?<=[.!?])\s')[0] } else { '' }
                $refs = @(@(Get-P $qn 'linked_initiatives' @()) | ForEach-Object { Get-P $_ 'initiative_name' } | Where-Object { $_ }) -join '; '
                $null = $rows.Add(@(
                        $catTitle, [string](Get-P $qn 'title' ''), $order, [string](Get-P $qn 'description' ''), 'List',
                        $answer, $ScoreText[$answer], ($responses -join ','), $(if ($answer -eq -2) { 'Yes' } else { 'No' }),
                        (Get-Text (Get-P $qn 'public_comment')), [string](Get-P $qn 'scoring_instructions' ''), $summary, $tips,
                        $(if ($refs) { "Linked initiatives: $refs" } else { '' }), (Get-Text (Get-P $qn 'internal_comments'))))
            }
        }
        $counts.questions += $rows.Count
        if ($rows.Count -eq 0) { $null = $items.Add(@{ title = $title; action = 'skip'; reason = 'no questions' }); continue }
        $counts.toImport++
        $item = [ordered]@{ title = $title; action = 'import'; questions = $rows.Count; scalePadScore = Get-P $s 'overall_score' }
        if ($apply -and -not $assessReadFailed) {
            try {
                # The v2 API has no create route (POST /v2/assessment returns 404). Like the portal's
                # Import Assessment dialog, the upload creates the assessment when assessmentId is 0,
                # titled by `name`. type 30 is a run; type 0 creates a row the portal never shows.
                $bytes = New-XlsxBytes -Header $TemplateColumns -Rows (ConvertTo-TemplateRows $rows.ToArray())
                $data = ([ordered]@{ name = $title; assessmentId = 0; type = 30; companyId = $companyId } | ConvertTo-Json -Compress)
                $null = Send-CrMultipart -Path '/v2/assessment/upload' -DataJson $data -FileBytes $bytes -FileName ('scalepad-' + $spId + '.xlsx')
                $null = $crTitles.Add($title.ToLowerInvariant())
                $counts.imported++
                $aid = Find-CrAssessmentId $title
                if ($aid -gt 0) { $item.assessmentId = $aid }
                else { Warn "Assessment '$title' was uploaded, but it didn't appear in this company's assessment list yet. Check Compliance > Assessments; a re-run skips it once it's there." }
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
