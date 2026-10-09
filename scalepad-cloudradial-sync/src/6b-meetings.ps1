#{{COMMON}}
# =====================================================================
# Meeting notes -> Report Archive
#   Every ScalePad meeting - completed and upcoming - becomes an HTML
#   item in the company's "ScalePad Meeting Notes" report archive: title,
#   type, date, attendees, the meeting's notes/agenda (converted from
#   ScalePad's rich-text JSON) and the action items raised in it.
#   Items are matched on their subject, so re-runs don't write them twice.
# =====================================================================
$phase = 'meetings'
$results = ConvertTo-Dict (Get-P $ctx 'results')
$settings = Get-P $ctx 'settings'
$companyId = [int](Get-P $ctx 'companyId')
$spClientId = [string](Get-P $ctx 'scalePadClientId')
$counts = [ordered]@{ meetings = 0; alreadyArchived = 0; toArchive = 0; archived = 0; toUpdate = 0; updated = 0; errors = 0 }
$items = New-Object System.Collections.ArrayList
function ConvertTo-Html { param($s) return [System.Net.WebUtility]::HtmlEncode([string]$s) }

# ProseMirror JSON (ScalePad's rich text) -> HTML.
function ConvertFrom-ProseMirror {
    param($node)
    if ($null -eq $node) { return '' }
    if ($node -is [string]) { if ($node.Trim().StartsWith('{')) { try { $node = $node | ConvertFrom-Json } catch { return "<p>$(ConvertTo-Html $node)</p>" } } else { return "<p>$(ConvertTo-Html $node)</p>" } }
    $kids = (@(Get-P $node 'content' @()) | ForEach-Object { ConvertFrom-ProseMirror $_ }) -join ''
    switch ([string](Get-P $node 'type' '')) {
        'doc'         { return $kids }
        'paragraph'   { return "<p>$kids</p>" }
        'heading'     { $l = [Math]::Min(6, [Math]::Max(3, [int](Get-P $node 'attrs.level' 3) + 2)); return "<h$l>$kids</h$l>" }
        'bulletList'  { return "<ul>$kids</ul>" }
        'orderedList' { return "<ol>$kids</ol>" }
        'listItem'    { return "<li>$kids</li>" }
        'taskList'    { return "<ul>$kids</ul>" }
        'taskItem'    { return "<li>$(if (Get-P $node 'attrs.checked' $false) { '&#9745;' } else { '&#9744;' }) $kids</li>" }
        'blockquote'  { return "<blockquote>$kids</blockquote>" }
        'codeBlock'   { return "<pre>$kids</pre>" }
        'hardBreak'   { return '<br>' }
        'horizontalRule' { return '<hr>' }
        'text' {
            $t = ConvertTo-Html (Get-P $node 'text' '')
            foreach ($m in @(Get-P $node 'marks' @())) {
                switch ([string](Get-P $m 'type' '')) {
                    'bold' { $t = "<b>$t</b>" } 'strong' { $t = "<b>$t</b>" } 'italic' { $t = "<i>$t</i>" } 'em' { $t = "<i>$t</i>" }
                    'underline' { $t = "<u>$t</u>" } 'strike' { $t = "<s>$t</s>" } 'code' { $t = "<code>$t</code>" }
                    'link' { $h = [string](Get-P $m 'attrs.href' ''); if ($h -match '^https?://') { $t = "<a href=""$(ConvertTo-Html $h)"">$t</a>" } }
                }
            }
            return $t
        }
        default { return $kids }
    }
}
function Get-PersonName { param($p)
    $n = [string](Get-P $p 'name' (Get-P $p 'full_name' (Get-P $p 'display_name' '')))
    if (-not $n) { $n = ((@((Get-P $p 'first_name' ''), (Get-P $p 'last_name' '')) | Where-Object { $_ }) -join ' ') }
    if (-not $n) { $n = [string](Get-P $p 'email' '') }
    return $n
}

if ((Get-P $ctx 'phases' @()) -notcontains $phase) {
    $results[$phase] = [ordered]@{ ran = $false }
}
else {
    $archiveName = [string](Get-P $settings 'meetingArchiveName' 'ScalePad Meeting Notes')
    $limit = [int](Get-P $settings 'meetingLimit' 0)
    if ($limit -le 0) { $limit = [int]::MaxValue }   # default: every meeting, completed or not
    $list = @(Get-SpAll '/lifecycle-manager/v1/meetings' @{ 'filter[client.id]' = "eq:$spClientId" } -PageSize 100 |
        Sort-Object { ConvertTo-IsoDate (Get-P $_ 'starts_at') } -Descending)
    $counts.meetings = $list.Count

    # Action items raised in each meeting.
    $actionsByMeeting = @{}
    try {
        foreach ($a in @(Get-SpAll '/lifecycle-manager/v1/action-items' @{ 'filter[client.id]' = "eq:$spClientId" } -PageSize 100)) {
            foreach ($ml in @(Get-P $a 'meeting_links' @())) {
                $mid = [string](Get-P $ml 'meeting_id' '')
                if (-not $mid) { continue }
                if (-not $actionsByMeeting.ContainsKey($mid)) { $actionsByMeeting[$mid] = New-Object System.Collections.ArrayList }
                $null = $actionsByMeeting[$mid].Add($a)
            }
        }
    } catch { Warn "Couldn't read ScalePad action items for the meeting notes: $($_.Exception.Message)" }

    $archive = $null; $archiveId = 0
    if ($list.Count -gt 0) {
        try { $archive = Get-CrArchive -CompanyId $companyId -Name $archiveName -Create:$apply -Category 'ScalePad'; $archiveId = [int](Get-P $archive 'id' 0) }
        catch { $counts.errors++; Warn "Couldn't create or find the '$archiveName' report archive: $($_.Exception.Message)" }
        if (-not $archive -and -not $apply) { Warn "Archive '$archiveName' doesn't exist yet; apply will create it." }
    }
    # What is already in the archive: subject -> item id + text, so changed notes can be refreshed.
    $done = @{}
    if ($archiveId -gt 0) {
        try { foreach ($it in @(Get-CrAll "/v2/odata/archiveitem?`$filter=companyId eq $companyId and companyReportFolderId eq $archiveId&`$select=companyReportItemId,subject,text")) { $done[([string](Get-P $it 'subject' '')).ToLowerInvariant()] = @{ id = [int](Get-P $it 'companyReportItemId' 0); text = [string](Get-P $it 'text' '') } } }
        catch {
            try { foreach ($it in @(Get-CrBetaAll "/api/beta/archive/$archiveId/item")) { $done[([string](Get-P $it 'subject' (Get-P $it 'name' ''))).ToLowerInvariant()] = @{ id = [int](Get-P $it 'id' 0); text = '' } } }
            catch { Warn "Couldn't list the '$archiveName' archive; meeting notes already there may be written again. $($_.Exception.Message)" }
        }
    }
    function Get-Comparable { param([string]$h) return (($h -replace '<[^>]+>', ' ' -replace '&[a-z#0-9]+;', ' ' -replace '\s+', ' ').Trim().ToLowerInvariant()) }

    foreach ($m in @($list | Select-Object -First $limit)) {
        $mid = [string](Get-P $m 'id' '')
        $title = [string](Get-P $m 'title' 'Meeting')
        $day = Format-Day (Get-P $m 'starts_at')
        $subject = "Meeting - $title$(if ($day) { " ($day)" })"
        if ($subject.Length -gt 250) { $subject = $subject.Substring(0, 250) }
        $existing = $done[$subject.ToLowerInvariant()]
        try {
            $detail = $null; try { $detail = Get-P (Get-SpOne "/lifecycle-manager/v1/meetings/$mid") 'meeting' } catch { }
            $src = if ($null -ne $detail) { $detail } else { $m }
            $typ = [string](Get-P $src 'meeting_type.name' (Get-P $src 'type' ''))
            $people = @(@(Get-P $src 'contact_attendees' @()) + @(Get-P $src 'external_attendees' @()) | ForEach-Object { Get-PersonName $_ } | Where-Object { $_ })
            $rawNotes = Get-P $src 'agenda_json' ''
            $notes = if (Test-Blank $rawNotes) { '' } else { ConvertFrom-ProseMirror $rawNotes }
            if (($notes -replace '<[^>]+>', '').Trim() -eq '') { $notes = '' }
            $html = New-Object System.Text.StringBuilder
            $null = $html.Append("<h2>$(ConvertTo-Html $title)</h2><p>")
            if ($typ) { $null = $html.Append("<b>Type:</b> $(ConvertTo-Html $typ)<br>") }
            if ($day) { $null = $html.Append("<b>Date:</b> $(ConvertTo-Html $day)<br>") }
            $null = $html.Append("<b>Status:</b> $(if (Get-P $src 'is_complete' $false) { 'Completed' } else { 'Scheduled' })</p>")
            if ($people.Count) { $null = $html.Append('<h3>Attendees</h3><ul>' + ((@($people | ForEach-Object { "<li>$(ConvertTo-Html $_)</li>" })) -join '') + '</ul>') }
            $null = $html.Append('<h3>Notes and agenda</h3>' + $(if ($notes) { $notes } else { '<p><i>No notes were recorded in ScalePad.</i></p>' }))
            $acts = @($(if ($actionsByMeeting.ContainsKey($mid)) { $actionsByMeeting[$mid] }) | Where-Object { $null -ne $_ })
            if ($acts.Count) {
                $null = $html.Append('<h3>Action items</h3><ul>')
                foreach ($a in $acts) { $null = $html.Append("<li>$(if (Get-P $a 'is_completed' $false) { '&#9745;' } else { '&#9744;' }) $(ConvertTo-Html (Get-P $a 'title' ''))$(if (Format-Day (Get-P $a 'due_at')) { ' (due ' + (Format-Day (Get-P $a 'due_at')) + ')' })</li>") }
                $null = $html.Append('</ul>')
            }
            $null = $html.Append('<p><i>From ScalePad Lifecycle Manager, via the ScalePad to CloudRadial Sync.</i></p>')
            $text = $html.ToString()
            $body = [ordered]@{ companyId = $companyId; archiveId = $archiveId; subject = $subject; text = $text; isHtml = $true; isError = $false }

            if ($null -ne $existing) {
                # Already archived: refresh it only when the notes, attendees, status or action items changed.
                if (-not $existing.text -or (Get-Comparable $existing.text) -eq (Get-Comparable $text)) { $counts.alreadyArchived++; continue }
                $counts.toUpdate++
                $null = $items.Add([ordered]@{ meeting = $title; date = $day; subject = $subject; action = 'refresh' })
                if ($apply -and $existing.id -gt 0) { $null = Invoke-Cr -Method PUT -Path "/v2/archiveitem/$archiveId/$($existing.id)" -Body $body; $counts.updated++ }
                continue
            }
            $counts.toArchive++
            $null = $items.Add([ordered]@{ meeting = $title; date = $day; subject = $subject; action = 'archive' })
            if (-not $apply) { continue }
            if ($archiveId -le 0) { $counts.errors++; continue }
            $null = Invoke-Cr -Method POST -Path '/v2/archiveitem' -Body $body
            $counts.archived++
        }
        catch { $counts.errors++; Warn "Couldn't archive meeting '$title': $($_.Exception.Message)" }
    }
    if ($limit -lt [int]::MaxValue -and $list.Count -gt $limit) { Warn "Only the newest $limit of $($list.Count) meetings were archived (meetingLimit)." }
    $results[$phase] = [ordered]@{ ran = $true; counts = $counts; archiveName = $archiveName; archiveId = $archiveId; items = @($items | Select-Object -First 100) }
}

$ctx.results = $results
$ctx.warnings = @(@(Get-P $ctx 'warnings' @()) + @($warnings))
$c = $counts
Set-NodeOutput @{ status = 'ok'; message = "Meeting notes: $($c.meetings) meetings in ScalePad, $($c.alreadyArchived) already archived, $(if ($apply) { "$($c.archived) archived, $($c.updated) refreshed" } else { "$($c.toArchive) to archive, $($c.toUpdate) to refresh" }), $($c.errors) errors."; ctx = $ctx }
