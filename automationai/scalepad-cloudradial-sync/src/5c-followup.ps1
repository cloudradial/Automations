#{{COMMON}}
# =====================================================================
# Manual follow-up (read-only) - the company's own items in areas that
# have no CloudRadial API, gathered for the report's checklist:
#   - open action items, grouped under the Planner card of their initiative
#   - meetings (upcoming, plus the last 12 months) to recreate
#   - goals
#   - the assessment templates this client's assessments used
# Nothing is written here; the migration report turns it into a checklist.
# =====================================================================
$phase = 'followup'
$results = ConvertTo-Dict (Get-P $ctx 'results')
$spClientId = [string](Get-P $ctx 'scalePadClientId')
$counts = [ordered]@{ actionItems = 0; meetings = 0; goals = 0; templates = 0; errors = 0 }
$data = [ordered]@{ actionItems = @(); meetings = @(); goals = @(); templates = @() }

if ((Get-P $ctx 'phases' @()) -notcontains $phase) {
    $results[$phase] = [ordered]@{ ran = $false }
}
else {
    $q = @{ 'filter[client.id]' = "eq:$spClientId" }
    try {
        $open = @(Get-SpAll '/lifecycle-manager/v1/action-items' (@{ 'filter[client.id]' = "eq:$spClientId"; 'filter[is_completed]' = 'eq:false' }) -PageSize 100)
        $data.actionItems = @($open | ForEach-Object {
            $ini = Get-P $_ 'initiative_links'
            [ordered]@{ title = [string](Get-P $_ 'title' ''); due = Format-Day (Get-P $_ 'due_at'); initiative = [string](Get-P $ini 'initiative_name' ''); meeting = [string]((@(Get-P $_ 'meeting_links' @()) | Select-Object -First 1 | ForEach-Object { Get-P $_ 'meeting_title' '' }) -join '') }
        })
        $counts.actionItems = $data.actionItems.Count
    } catch { $counts.errors++; Warn "Couldn't read ScalePad action items: $($_.Exception.Message)" }

    try {
        $since = (Get-Date).ToUniversalTime().AddMonths(-12)
        $all = @(Get-SpAll '/lifecycle-manager/v1/meetings' $q -PageSize 100)
        $data.meetings = @($all | Where-Object { $d0 = ConvertTo-IsoDate (Get-P $_ 'starts_at'); (-not (Get-P $_ 'is_complete' $false)) -or (-not $d0) -or ([datetime]$d0 -ge $since) } |
            Sort-Object { ConvertTo-IsoDate (Get-P $_ 'starts_at') } | ForEach-Object {
                [ordered]@{ title = [string](Get-P $_ 'title' ''); type = [string](Get-P $_ 'type' ''); starts = Format-Day (Get-P $_ 'starts_at'); complete = [bool](Get-P $_ 'is_complete' $false); deliverables = [int](Get-P $_ 'linked_deliverable_count' 0) }
            })
        $counts.meetings = $data.meetings.Count
    } catch { $counts.errors++; Warn "Couldn't read ScalePad meetings: $($_.Exception.Message)" }

    try {
        $data.goals = @(@(Get-SpAll '/lifecycle-manager/v1/goals' $q -PageSize 100) | Where-Object { ([string](Get-P $_ 'status' '')) -notmatch '(?i)archiv|cancel' } | ForEach-Object {
            $per = Get-P $_ 'period'
            [ordered]@{ title = [string](Get-P $_ 'title' ''); status = [string](Get-P $_ 'status' ''); period = (@((Get-P $per 'year'), $(if (Get-P $per 'quarter') { 'Q' + (Get-P $per 'quarter') } elseif (Get-P $per 'half') { 'H' + (Get-P $per 'half') })) | Where-Object { $_ }) -join ' '; outcomes = @(@(Get-P $_ 'outcomes' @()) | Where-Object { -not (Get-P $_ 'is_archived' $false) } | ForEach-Object { [string](Get-P $_ 'label' '') }) }
        })
        $counts.goals = $data.goals.Count
    } catch { $counts.errors++; Warn "Couldn't read ScalePad goals: $($_.Exception.Message)" }

    try {
        $data.templates = @(@(Get-SpAll '/lifecycle-manager/v1/assessments' $q -PageSize 100) | Group-Object { [string](Get-P $_ 'assessment_template_id' '') } | Where-Object { $_.Name } | ForEach-Object {
            [ordered]@{ templateId = $_.Name; usedBy = @($_.Group | ForEach-Object { [string](Get-P $_ 'title' '') } | Select-Object -Unique -First 5); count = $_.Count }
        })
        $counts.templates = $data.templates.Count
    } catch { $counts.errors++; Warn "Couldn't read ScalePad assessments for templates: $($_.Exception.Message)" }

    $results[$phase] = [ordered]@{ ran = $true; counts = $counts; data = $data }
}

$ctx.results = $results
$ctx.warnings = @(@(Get-P $ctx 'warnings' @()) + @($warnings))
$c = $counts
Set-NodeOutput @{ status = 'ok'; message = "Follow-up: $($c.actionItems) open action items, $($c.meetings) meetings, $($c.goals) goals, $($c.templates) assessment templates to handle by hand, $($c.errors) read errors."; ctx = $ctx }
