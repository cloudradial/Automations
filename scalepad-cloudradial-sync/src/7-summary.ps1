#{{COMMON}}
# =====================================================================
# Step 7 - Migration report
#   Builds a plain-language summary and, in apply mode, writes it into the
#   CloudRadial portal so the result is visible there:
#     reportTarget = archive (default) -> one "ScalePad sync report" item in the company's
#                    "ScalePad Migration" report archive, updated each run. Report archives
#                    are limited by security role (admins only), which is why this is the default.
#     reportTarget = article           -> a knowledge base article (visible to portal users)
#     reportTarget = archive           -> (legacy wording) an HTML item in the company's
#                    "ScalePad Migration" report archive (POST /v2/archiveitem)
#     reportTarget = none              -> run output only
#   If the archive can't be written, it falls back to an article.
#   Plan mode writes nothing - the report is returned in the run output.
# =====================================================================
$results = ConvertTo-Dict (Get-P $ctx 'results')
$settings = Get-P $ctx 'settings'
$companyId = [int](Get-P $ctx 'companyId')
$companyName = [string](Get-P $ctx 'companyName')
$spName = [string](Get-P $ctx 'scalePadClientName')
$runDay = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
function ConvertTo-HtmlText { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }

$discovery = Get-P $ctx 'discovery'
if ($null -ne $discovery) {
    Set-NodeOutput @{ status = 'ok'; mode = 'plan'; summary = [string](Get-P $discovery 'message'); message = [string](Get-P $discovery 'message'); matchedClients = @(Get-P $discovery 'matched' @()); unmatchedClients = @(Get-P $discovery 'unmatched' @()); nextRun = [string](Get-P $discovery 'nextRun'); reportLocation = 'run output only'; results = [ordered]@{}; warnings = @(Get-P $ctx 'warnings' @()) }
    return
}


# ---- Areas of ScalePad Lifecycle Manager this API-to-API sync does not move ----
# CloudRadial has no API for these (or none this workflow uses yet), so the report says so plainly.
$NotMigrated = @(
    [ordered]@{ area = 'Policies and standards'; why = "CloudRadial's API has no route for Compliance Policies. The only policy data it exposes is each endpoint's Windows audit-policy settings (EndpointAuditPolicy), reported by the agent - so ScalePad's lifecycle, warranty and replacement policies can't be recreated automatically."; action = "Set up the equivalent checks in CloudRadial under Compliance > Policies. The Sync already fills the endpoint fields those checks read (warranty expiry, purchase date, server type)." }
    [ordered]@{ area = 'Assessment templates'; why = 'Only completed assessments (with answers) are imported. Blank templates and scoring rules have no import route.'; action = 'Recreate templates under Compliance > Assessments, or export one from ScalePad and import it with the Excel template.' }
    [ordered]@{ area = 'Meeting scheduling'; why = 'CloudRadial has no meeting or calendar API. The notes, attendees and action items of each meeting are archived in the ScalePad Meeting Notes report archive.'; action = 'Recreate upcoming and recurring meetings in your calendar or PSA - the checklist lists them.' }
    [ordered]@{ area = 'Goals'; why = 'CloudRadial has no API for client goals or outcomes.'; action = "Record them on a Planner card or in the client's QBR notes - the checklist lists this client's goals." }
    [ordered]@{ area = 'Initiative action items and notes'; why = 'Planner cards carry the initiative, budget and quarter, but CloudRadial has no API for card sub-tasks.'; action = "Add action items to the Planner card's description, or track them in your PSA." }
    [ordered]@{ area = 'Report and deliverable templates, branding'; why = 'Templates are not exposed by either API; only finished PDFs are.'; action = 'Rebuild layouts in CloudRadial Report Layouts.' }
)
$lines = New-Object System.Collections.ArrayList
$html = New-Object System.Text.StringBuilder
$null = $lines.Add("ScalePad client '$spName' to CloudRadial company '$companyName' ($companyId), $mode mode.")
$null = $html.Append("<h2>ScalePad migration - $(ConvertTo-HtmlText $companyName)</h2><p>Run on $runDay in <b>$(if ($apply) { 'apply' } else { 'plan (preview)' })</b> mode, from ScalePad client <b>$(ConvertTo-HtmlText $spName)</b>.</p>")
$rows = New-Object System.Collections.ArrayList
$attention = New-Object System.Collections.ArrayList
$notes = New-Object System.Collections.ArrayList

$cu = Get-P $results 'cleanup.counts'
if ($cu) {
    $del = [bool](Get-P $results 'cleanup.deleted' $false)
    $act = if ($del) { "Deleted $(Get-P $cu 'deleted') duplicate copies." } else { "Would delete $(Get-P $cu 'toDelete') duplicate copies (nothing deleted)." }
    $null = $lines.Add("Clean-up: $(Get-P $cu 'syncRecords') software records written by the Sync, $(Get-P $cu 'duplicateGroups') duplicated. $act")
    $null = $rows.Add(@('Duplicate software clean-up', "$(Get-P $cu 'syncRecords') Sync-written records of $(Get-P $cu 'records')", $act, "$(Get-P $cu 'errors') errors"))
}
$d = Get-P $results 'devices.counts'
if ($d) {
    $act = if ($apply) { "Enriched $(Get-P $d 'enriched') and created $(Get-P $d 'created')." } else { "Would enrich $(Get-P $d 'toEnrich') and create $(Get-P $d 'toCreate')." }
    $null = $lines.Add("Devices: $(Get-P $d 'inScope') workstations, servers and VMs in ScalePad, $(Get-P $d 'matched') already in CloudRadial. $act $(Get-P $d 'unchanged') needed nothing, $(Get-P $d 'skipped') were skipped, $(Get-P $d 'errors') errors.")
    $null = $rows.Add(@('Devices', "$(Get-P $d 'inScope') in ScalePad, $(Get-P $d 'matched') already in CloudRadial", $act, "$(Get-P $d 'skipped') skipped, $(Get-P $d 'errors') errors"))
    $groups = @{}
    foreach ($s in @(Get-P $results 'devices.skipped' @())) { $r = [string](Get-P $s 'reason'); if (-not $groups.ContainsKey($r)) { $groups[$r] = New-Object System.Collections.ArrayList }; $null = $groups[$r].Add([string](Get-P $s 'device')) }
    foreach ($k in $groups.Keys) { $null = $attention.Add("Devices skipped - $k ($($groups[$k].Count)): $((@($groups[$k]) | Select-Object -First 15) -join ', ')") }
}
$fa = Get-P $results 'assets.counts'
if ($fa) {
    $moved = [int](Get-P $fa $(if ($apply) { 'moved' } else { 'toMove' }) 0)
    $act = if ($apply) { "Created $(Get-P $fa 'created') and updated $(Get-P $fa 'updated')$(if ($moved) { "; moved $moved from the old single type" })." } else { "Would create $(Get-P $fa 'toCreate') and update $(Get-P $fa 'toUpdate')$(if ($moved) { "; would move $moved from the old single type" })." }
    $byType = @((ConvertTo-Dict (Get-P $fa 'byType')).GetEnumerator() | ForEach-Object { "$($_.Value) $($_.Key)" }) -join ', '
    $typeNames = @(Get-P $results 'assets.flexibleAssetTypes' @()); if ($typeNames.Count -eq 0) { $typeNames = @([string](Get-P $results 'assets.flexibleAssetType' '')) }
    $where = "the " + ((@($typeNames | ForEach-Object { "'$_'" })) -join ', ') + " flexible asset type$(if ($typeNames.Count -gt 1) { 's' }) (Infrastructure)"
    $null = $lines.Add("Other hardware: $(Get-P $fa 'scalePadAssets') ScalePad assets that aren't endpoints$(if ($byType) { " ($byType)" }), kept in $where. $act")
    $legacyType = [string](Get-P $results 'assets.legacyType' '')
    if ($legacyType -and $moved) { $null = $attention.Add("This company's rows in the old '$legacyType' flexible asset type $(if ($apply) { 'were moved' } else { 'will be moved' }) to a type per kind of device. Once every company has been synced, the empty '$legacyType' type can be deleted under Settings.") }
    $null = $rows.Add(@('Other hardware (flexible assets)', "$(Get-P $fa 'scalePadAssets') assets$(if ($byType) { ": $byType" })", $act, "$(Get-P $fa 'unchanged') unchanged, $(Get-P $fa 'errors') errors"))
}
$sa = Get-P $results 'saas.counts'
if ($sa) {
    $act = if ($apply) { "Created $(Get-P $sa 'created') and updated $(Get-P $sa 'updated')." } else { "Would create $(Get-P $sa 'toCreate') and update $(Get-P $sa 'toUpdate')." }
    $null = $lines.Add("SaaS: $(Get-P $sa 'scalePadAssets') ScalePad SaaS subscriptions, kept in the '$(Get-P $results 'saas.flexibleAssetType')' flexible asset type. $act")
    $saasType = [string](Get-P $results 'saas.flexibleAssetType' 'SaaS')
    $null = $notes.Add("SaaS subscriptions are under Infrastructure > $saasType (a flexible asset type), not under Software > SaaS. That tab lists SaaS CloudRadial discovers itself and has no API to write to, so ScalePad's subscriptions - with licences, assigned seats and renewal dates - are kept in the $saasType flexible asset instead.")
    $null = $rows.Add(@('SaaS subscriptions (flexible assets)', "$(Get-P $sa 'scalePadAssets') subscriptions", $act, "$(Get-P $sa 'unchanged') unchanged, $(Get-P $sa 'errors') errors"))
}
$s = Get-P $results 'software.counts'
if ($s) {
    $act = if ($apply) { "Created $(Get-P $s 'created')." } else { "Would create $(Get-P $s 'toCreate')." }
    $null = $lines.Add("Software: $(Get-P $s 'scalePadInstalls') installed items in ScalePad, $(Get-P $s 'alreadyPresent') already in CloudRadial. $act $(Get-P $s 'noDevice') are on devices not in CloudRadial.")
    $null = $rows.Add(@('Installed software', "$(Get-P $s 'scalePadInstalls') installs on $(Get-P $s 'scalePadDevices' (Get-P $s 'devicesWithSoftware')) devices", $act, "$(Get-P $s 'noDevice') on devices not in CloudRadial, $(Get-P $s 'errors') errors"))
    if ([int](Get-P $s 'overCap' 0) -gt 0) { $null = $attention.Add("Software: $(Get-P $s 'overCap') records left for the next run (maxSoftwareWrites).") }
}
$a = Get-P $results 'assessments.counts'
if ($a) {
    $act = if ($apply) { "Imported $(Get-P $a 'imported')." } else { "Would import $(Get-P $a 'toImport')." }
    $null = $lines.Add("Assessments: $(Get-P $a 'scalePadAssessments') in ScalePad, $(Get-P $a 'alreadyInCloudRadial') already imported. $act ($(Get-P $a 'questions') questions).")
    $null = $rows.Add(@('Assessments', "$(Get-P $a 'scalePadAssessments') in ScalePad ($(Get-P $a 'questions') questions)", $act, "$(Get-P $a 'alreadyInCloudRadial') already imported, $(Get-P $a 'errors') errors"))
}
$r = Get-P $results 'roadmap.counts'
if ($r) {
    $act = if ($apply) { "Created $(Get-P $r 'created') cards and updated $(Get-P $r 'updated')." } else { "Would create $(Get-P $r 'toCreate') cards and update $(Get-P $r 'toUpdate')." }
    $null = $lines.Add("Roadmap: $(Get-P $r 'initiatives') initiatives and $(Get-P $r 'contracts') contracts. $act")
    $null = $rows.Add(@('Roadmap and budget', "$(Get-P $r 'initiatives') initiatives, $(Get-P $r 'contracts') contracts", $act, "$(Get-P $r 'unchanged' 0) unchanged, $(Get-P $r 'errors') errors"))
}
$ins = Get-P $results 'insights.counts'
if ($ins) {
    $act = if ($apply) { "Created $(Get-P $ins 'created') Planner cards, updated $(Get-P $ins 'updated'), closed $(Get-P $ins 'closed' 0) resolved." } else { "Would create $(Get-P $ins 'toCreate') Planner cards and update $(Get-P $ins 'toUpdate')." }
    $null = $lines.Add("Insights: $(Get-P $ins 'insights') in ScalePad, $(Get-P $ins 'active') with affected assets. $act")
    $null = $rows.Add(@('Insights and recommendations', "$(Get-P $ins 'insights') insights, $(Get-P $ins 'active') with affected assets", $act, "$(Get-P $ins 'unchanged' 0) unchanged, $(Get-P $ins 'errors') errors"))
}
$mn = Get-P $results 'meetings.counts'
if ($mn) {
    $act = if ($apply) { "Archived $(Get-P $mn 'archived'), refreshed $(Get-P $mn 'updated' 0)." } else { "Would archive $(Get-P $mn 'toArchive') and refresh $(Get-P $mn 'toUpdate' 0)." }
    $null = $lines.Add("Meeting notes: $(Get-P $mn 'meetings') meetings in ScalePad, $(Get-P $mn 'alreadyArchived') already archived. $act")
    $null = $rows.Add(@('Meeting notes', "$(Get-P $mn 'meetings') meetings", $act, "$(Get-P $mn 'alreadyArchived') already archived, $(Get-P $mn 'errors') errors"))
    $null = $notes.Add("Meeting notes (agenda, attendees and action items for each ScalePad meeting) are in the '$(Get-P $results 'meetings.archiveName' 'ScalePad Meeting Notes')' report archive under Compliance > Reports.")
}
$ar = Get-P $results 'archive.counts'
if ($ar) {
    $act = if ($apply) { "Uploaded $(Get-P $ar 'uploaded')." } else { "Would archive $(Get-P $ar 'toArchive')." }
    $null = $lines.Add("Report archive: $(Get-P $ar 'deliverables') ScalePad deliverables, $(Get-P $ar 'alreadyArchived') already archived. $act ")
    $null = $rows.Add(@('Deliverable PDFs', "$(Get-P $ar 'deliverables') in ScalePad", $act, "$(Get-P $ar 'alreadyArchived') already archived, $(Get-P $ar 'errors') errors"))
}

$allWarnings = @(@(Get-P $ctx 'warnings' @()) + @($warnings) | Where-Object { $_ })
$errors = 0
foreach ($ph in @('cleanup', 'devices', 'assets', 'saas', 'software', 'assessments', 'roadmap', 'insights', 'archive', 'meetings', 'followup')) { $errors += [int](Get-P $results "$ph.counts.errors" 0) }

$null = $html.Append('<table border="1" cellpadding="6" cellspacing="0"><tr><th>Area</th><th>In ScalePad</th><th>Result</th><th>Notes</th></tr>')
foreach ($row in $rows) { $null = $html.Append("<tr><td>$(ConvertTo-HtmlText $row[0])</td><td>$(ConvertTo-HtmlText $row[1])</td><td>$(ConvertTo-HtmlText $row[2])</td><td>$(ConvertTo-HtmlText $row[3])</td></tr>") }
$null = $html.Append('</table>')
$checklist = New-Object System.Collections.ArrayList
function Add-Check { param([string]$Group, [string]$Text) $null = $checklist.Add([ordered]@{ group = $Group; item = $Text }) }
# (the checklist appears in plan and apply runs)
    Add-Check 'Policies' 'Recreate the lifecycle, warranty and replacement policies you used in ScalePad under Compliance > Policies (no API). The endpoint fields they check are already filled.'
    $fu = Get-P $results 'followup.data'
    if ($fu) {
        foreach ($g in @(@(Get-P $fu 'actionItems' @()) | Group-Object { [string](Get-P $_ 'initiative' '') })) {
            foreach ($a in $g.Group) {
                $due = [string](Get-P $a 'due' ''); $mt = [string](Get-P $a 'meeting' '')
                $txt = "$(Get-P $a 'title')$(if ($due) { " (due $due)" })$(if ($mt) { " - from meeting '$mt'" })"
                if ($g.Name) { Add-Check 'Action items' "Add to Planner card 'ScalePad Initiative - $($g.Name)': $txt" } else { Add-Check 'Action items' "Track in your PSA (not linked to an initiative): $txt" }
            }
        }
        foreach ($m in @(Get-P $fu 'meetings' @())) {
            $when = [string](Get-P $m 'starts' ''); $typ = [string](Get-P $m 'type' '')
            if (Get-P $m 'complete' $false) { continue }   # its notes are in the meeting-notes archive
            if ($when -and $when -lt $runDay) { continue }  # already happened - notes archived; nothing to recreate
            else { Add-Check 'Meetings' "Recreate '$(Get-P $m 'title')'$(if ($typ) { " ($typ)" })$(if ($when) { " on $when" }) in your calendar or PSA." }
        }
        foreach ($g in @(Get-P $fu 'goals' @())) {
            $oc = @(Get-P $g 'outcomes' @()) -join '; '
            Add-Check 'Goals' "Record goal '$(Get-P $g 'title')'$(if (Get-P $g 'period') { ' (' + (Get-P $g 'period') + ')' })$(if (Get-P $g 'status') { ', ' + (Get-P $g 'status') })$(if ($oc) { ' - outcomes: ' + $oc })."
        }
        foreach ($t in @(Get-P $fu 'templates' @())) { Add-Check 'Assessment templates' "Recreate the template behind: $(@(Get-P $t 'usedBy' @()) -join ', ') ($(Get-P $t 'count' 0) assessment(s))." }
    }
    # Problems from this run that need a person.
    foreach ($w in @(@(Get-P $ctx 'warnings' @()) + @($warnings) | Where-Object { $_ } | Select-Object -Unique)) {
        $ws = [string]$w
        if ($ws -match '^Warranty differs') { Add-Check 'Decide' $ws }
        elseif ($ws -match "(?i)couldn't|could not|failed") { Add-Check 'Fix and re-run' $ws }
        elseif ($ws -match '^Skipped \d+ cancelled') { Add-Check 'Decide' $ws }
    }
if ($checklist.Count -gt 0) {
    $null = $html.Append('<h3>Manual follow-up checklist</h3>')
    $order = @('Fix and re-run', 'Decide', 'Action items', 'Meetings', 'Goals', 'Assessment templates', 'Policies')
    foreach ($grp in @($checklist | Group-Object { $_.group } | Sort-Object { $i = [array]::IndexOf($order, $_.Name); if ($i -lt 0) { 99 } else { $i } })) {
        $null = $html.Append("<p><b>$(ConvertTo-HtmlText $grp.Name)</b></p><ul>")
        foreach ($x in $grp.Group) { $null = $html.Append("<li>&#9744; $(ConvertTo-HtmlText $x.item)</li>") }
        $null = $html.Append('</ul>')
    }
}
$insTable = @(Get-P $results 'insights.table' @())
if ($insTable.Count -gt 0) {
    $null = $html.Append('<h3>ScalePad insights</h3><table border="1" cellpadding="6" cellspacing="0"><tr><th>Insight</th><th>Category</th><th>Risk</th><th>Affected</th><th>30-day change</th></tr>')
    $clear = @($insTable | Where-Object { [int](Get-P $_ 'affected' 0) -le 0 } | ForEach-Object { [string](Get-P $_ 'insight') })
    foreach ($t in @($insTable | Where-Object { [int](Get-P $_ 'affected' 0) -gt 0 } | Sort-Object { -[int](Get-P $_ 'affected' 0) })) { $tr = Get-P $t 'trend'; $null = $html.Append("<tr><td>$(ConvertTo-HtmlText (Get-P $t 'insight'))</td><td>$(ConvertTo-HtmlText (Get-P $t 'category'))</td><td>$(ConvertTo-HtmlText (Get-P $t 'risk'))</td><td>$(Get-P $t 'affected' 0)</td><td>$(if ($null -ne $tr) { $tr })</td></tr>") }
    $null = $html.Append('</table>')
    if ($clear.Count) { $null = $html.Append("<p><b>All clear ($($clear.Count)):</b> $(ConvertTo-HtmlText ($clear -join '; ')).</p>") }
    $null = $html.Append('<p>Insights with affected assets are Planner cards ("ScalePad Insight - ..."); a card is closed when its insight clears.</p>')
}
if ($notes.Count -gt 0) { $null = $html.Append('<h3>Where to find it</h3><ul>'); foreach ($x in $notes) { $null = $html.Append("<li>$(ConvertTo-HtmlText $x)</li>") }; $null = $html.Append('</ul>') }
if ($attention.Count -gt 0) { $null = $html.Append('<h3>Needs attention</h3><ul>'); foreach ($x in $attention) { $null = $html.Append("<li>$(ConvertTo-HtmlText $x)</li>") }; $null = $html.Append('</ul>') }
if ($allWarnings.Count -gt 0) { $null = $html.Append('<h3>Warnings</h3><ul>'); foreach ($x in @($allWarnings | Select-Object -First 40)) { $null = $html.Append("<li>$(ConvertTo-HtmlText $x)</li>") }; $null = $html.Append('</ul>') }
$null = $html.Append('<h3>Not migrated - no CloudRadial API for these areas</h3><table border="1" cellpadding="6" cellspacing="0"><tr><th>ScalePad area</th><th>Why</th><th>What to do</th></tr>')
foreach ($n in $NotMigrated) { $null = $html.Append("<tr><td>$(ConvertTo-HtmlText $n.area)</td><td>$(ConvertTo-HtmlText $n.why)</td><td>$(ConvertTo-HtmlText $n.action)</td></tr>") }
$null = $html.Append('</table>')
$null = $html.Append('<p><i>Written by the AutomationAI workflow "ScalePad to CloudRadial Sync". Devices created from ScalePad are tagged ScalePad.</i></p>')

# ---- write the report into the portal ----
$reportLocation = 'run output only'
$target = [string](Get-P $settings 'reportTarget' 'archive')
if ((@(Get-P $ctx 'phases' @()) -join ',') -eq 'cleanup') { $target = 'none' }   # clean-up runs report in the run output only
$subject = "ScalePad migration - $runDay"
$articleSubject = [string](Get-P $settings 'reportArticleTitle' 'ScalePad sync report')
if ($apply -and $target -ne 'none') {
    $written = $false
    if ($target -eq 'archive') {
        try {
            $archName = [string](Get-P $settings 'reportArchiveName' 'ScalePad Migration')
            $arch = Get-CrArchive -CompanyId $companyId -Name $archName -Create -Category 'ScalePad'
            $archId = [int](Get-P $arch 'id' 0)
            if ($archId -le 0) { throw 'no archive id returned' }
            $itemBody = [ordered]@{ companyId = $companyId; archiveId = $archId; subject = $articleSubject; text = $html.ToString(); isHtml = $true; isError = ($errors -gt 0) }
            $escS = $articleSubject.Replace("'", "''")
            $prev = @(Get-CrAll "/v2/odata/archiveitem?`$filter=companyId eq $companyId and companyReportFolderId eq $archId and subject eq '$escS'&`$select=companyReportItemId,subject") | Where-Object { ([string](Get-P $_ 'subject' '')) -eq $articleSubject } | Select-Object -First 1
            if ($null -ne $prev -and [int](Get-P $prev 'companyReportItemId' 0) -gt 0) {
                $null = Invoke-Cr -Method PUT -Path "/v2/archiveitem/$archId/$([int](Get-P $prev 'companyReportItemId'))" -Body $itemBody
                $reportLocation = "Report archive '$archName' (Compliance > Reports, admins only), item '$articleSubject', updated $runDay"
            } else {
                $null = Invoke-Cr -Method POST -Path '/v2/archiveitem' -Body $itemBody
                $reportLocation = "Report archive '$archName' (Compliance > Reports, admins only), item '$articleSubject'"
            }
            $written = $true
        }
        catch {
            # Deliberately no knowledge-base fallback: articles can be visible to the client's users.
            Warn "Couldn't write the report to the '$archName' report archive ($($_.Exception.Message)). It's in the run output only - it was not written to the knowledge base, which client users can see."
            $written = $true
        }
    }
    if (-not $written -and $target -eq 'article') {
        try {
            # One article per company, refreshed each run (a scheduled sync doesn't pile up articles).
            $esc = $articleSubject.Replace("'", "''")
            $art = @(Get-CrAll "/v2/odata/article?`$filter=companyId eq $companyId and subject eq '$esc'&`$select=articleId,subject") | Where-Object { ([string](Get-P $_ 'subject' '')) -eq $articleSubject } | Select-Object -First 1
            $artBody = [ordered]@{ companyId = $companyId; subject = $articleSubject; category = 'ScalePad Migration'; datePublished = (ConvertTo-IsoDate (Get-Date)); body = $html.ToString(); author = 'AutomationAI' }
            if ($null -ne $art -and [int](Get-P $art 'articleId' 0) -gt 0) {
                $null = Invoke-Cr -Method PUT -Path "/v2/article/$([int](Get-P $art 'articleId'))" -Body $artBody
                $reportLocation = "Knowledge base article '$articleSubject' (category ScalePad Migration), updated $runDay"
            } else {
                $null = Invoke-Cr -Method POST -Path '/v2/article' -Body $artBody
                $reportLocation = "Knowledge base article '$articleSubject' (category ScalePad Migration)"
            }
        }
        catch { Warn "Couldn't write the report to the portal: $($_.Exception.Message). It's in the run output." }
    }
}
$null = $lines.Add("Report: $reportLocation.")
$allWarnings = @(@(Get-P $ctx 'warnings' @()) + @($warnings) | Where-Object { $_ })

Set-NodeOutput @{
    status         = $(if ($errors -gt 0) { 'completed_with_errors' } else { 'ok' })
    mode           = $mode
    summary        = ($lines -join ' ')
    reportLocation = $reportLocation
    reportHtml     = $html.ToString()
    notMigrated    = @($NotMigrated)
    notes          = @($notes)
    checklist      = @($checklist)
    results        = $results
    warnings       = $allWarnings
    message        = ($lines -join ' ')
}
