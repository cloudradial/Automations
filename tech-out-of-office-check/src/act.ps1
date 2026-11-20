# Step 2: Handle the ticket and tell the dispatcher.
# when_out decides what happens to a ticket whose owner is out:
#   reassign  make the in, active technician with the fewest open tickets the owner (default). Candidates come
#             from OOO-BackupPool, else the ticket's board team. Nobody fits: left as is and flagged.
#   flag      leave the assignment alone
#   unassign  remove the owner, so the ticket goes back to the dispatch queue (opt-in only)
# Every live run adds one internal note marked [ooo-check] and alerts the dispatcher (email through Postmark,
# and a Teams message through a Power Automate flow when OOO-TeamsFlowUrl is set).
# Until live mode is on (confirm true, or the OOO-LiveMode secret is yes) it writes nothing and returns
# status pending_confirmation with the note it would add.
# A sweep (a Routine, no ticket) hands over one context per ticket; each is handled the same way and the run
# returns a summary of all of them.
$stopState = @{ done = $false }
$warnings = New-Object System.Collections.ArrayList
function Add-ActPsaWarnings { foreach ($w in @($PsaState.Warnings)) { if ($w -and -not $warnings.Contains([string]$w)) { $null = $warnings.Add([string]$w) } } }
$ctx = Read-StepContext (Get-NodeInput)
trap { if (-not $stopState.done) { $stopState.done = $true; $m = [string]$_.Exception.Message; $tid = ''; if ($null -ne $ctx) { $tid = [string]$ctx.ticket_id }; Add-ActPsaWarnings; Set-NodeOutput ([ordered]@{ status = 'error'; message = "The out-of-office check for ticket $tid could not be completed: $m"; public_note = ''; internal_note = "Out-of-office check failed: $m"; ticket_id = $tid; out_members = @(); changed = $false; actions = @(); warnings = @($warnings); chatReply = 'The out-of-office check failed. See the run for details.' }) }; break }
if ($null -eq $ctx -or $null -eq $ctx.PSObject.Properties['skip']) { throw 'The check result is missing. Run the workflow from the start.' }
if ($ctx.skip) { $stopState.done = $true; Set-NodeOutput $ctx.result; return }
$conn = Connect-Psa 'connectwise'
$OooCache = @{ coverage = $null }   # the coverage article, read once per run

# One ticket: the change, the note and the alert. Returns the result for that ticket.
function Invoke-OooTicket {
    param($ctx)

    $id = [string]$ctx.ticket_id
    $warnings = New-Object System.Collections.ArrayList
    $actions = New-Object System.Collections.ArrayList; foreach ($x in @($ctx.actions)) { if ($x) { $null = $actions.Add([string]$x) } }
    foreach ($x in @($ctx.warnings)) { if ($x) { $null = $warnings.Add([string]$x) } }
    $out = @($ctx.out)
    $owner = [string]$ctx.owner
    $ownerOut = $owner -and (@($out | Where-Object { ([string]$_.identifier).ToLowerInvariant() -eq $owner.ToLowerInvariant() }).Count -gt 0)
    $resourceOnly = @($out | Where-Object { -not $owner -or ([string]$_.identifier).ToLowerInvariant() -ne $owner.ToLowerInvariant() } | ForEach-Object { [string]$_.identifier })


    # ---- decide the change ----
    $backupId = ''; $plan = 'flag'; $case = 'flagged'; $poolSource = ''; $planText = 'The assignment was left as it is for the dispatcher to decide.'
    if ($ownerOut -and $ctx.when_out -eq 'unassign') { $plan = 'unassign'; $case = 'unassigned'; $planText = "$owner was removed as owner so the ticket goes back to dispatch." }
    $considered = @(); $pick = $null
    if ($ownerOut -and $ctx.when_out -eq 'reassign') {
        # list-order with a coverage article: the out owner's row, else the board's, else "*", in that order.
        $pickBy = [string]$ctx.pick_by; $pool = @($ctx.backup_pool); $poolLabel = 'the backup list'
        $article = [string](Get-StepProp $ctx 'coverage_article')
        if ($pickBy -eq 'list-order' -and $article) {
            if ($null -eq $OooCache.coverage) { $OooCache.coverage = Get-OooCoverage $article }
            if ($OooCache.coverage.error) { $null = $warnings.Add("$($OooCache.coverage.error) The ticket's team was used instead.") }
            $row = $null
            if (-not $OooCache.coverage.error) { $row = Select-OooCoverageRow $OooCache.coverage -Identifier $owner -MemberId ([string](Get-StepProp $ctx 'owner_id')) -Board ([string]$ctx.board) }
            if ($row) { $pool = @($row.list); $poolLabel = "the coverage table ($($row.label))" }
            else {
                if (-not $OooCache.coverage.error) { $null = $warnings.Add("The coverage article has no row for $owner, the $([string]$ctx.board) board or *, so the ticket's team was used (fewest open tickets).") }
                $pool = @(); $pickBy = 'fewest-open'
            }
        }
        $pick = Find-OooReplacement -PickBy $pickBy -Pool $pool -PoolLabel $poolLabel -BoardId ([string]$ctx.board_id) -TeamId ([string]$ctx.team_id) -Exclude @($out | ForEach-Object { [string]$_.identifier }) -Now (ConvertTo-PsaDate $ctx.now) -InTypes @($ctx.in_types) -ScheduleTypes @($ctx.schedule_types)
        $considered = @($pick.considered)
        if ($pick.identifier) {
            $plan = 'reassign'; $case = 'reassigned'; $backupId = [string]$pick.identifier
            $why = "from $($pick.source), $($pick.how)"
            $planText = "The ticket was reassigned from $owner to $backupId, who is in ($why)."
        }
        else {
            $case = 'no-replacement'; $poolSource = [string]$pick.source
            $planText = "Nobody in $($pick.source) is in and active right now, so the ticket was left with $owner for the dispatcher to reassign."
            $null = $warnings.Add("No replacement technician was found in $($pick.source): $($considered -join ' ')")
        }
    }
    if (-not $ownerOut) { $case = if ($owner) { 'resource-only' } else { 'no-owner' } }
    if (-not $ownerOut -and $ctx.when_out -ne 'flag') {
        if (-not $owner) { $planText = "The ticket has no owner saved yet, so nothing was unassigned. Please make sure it isn't scheduled to $(@($out | ForEach-Object { $_.identifier }) -join ', ')."; $null = $warnings.Add("Ticket $id has no owner saved in ConnectWise yet, so there was nothing to $($ctx.when_out). If ServiceAI assigns after the Action runs, the dispatcher alert and note are the record.") }
        else { $null = $warnings.Add("The technician who is out isn't the ticket owner (they're on the resources list), so the assignment was left alone. Remove them from the schedule by hand if needed.") }
    }

    # ---- the note, and the dispatcher email (subject, plain text, HTML), rebuilt if the change fails ----
    $outNames = (@($out | ForEach-Object { [string]$_.identifier }) -join ', ')
    $ticketUrl = ''; try { $ticketUrl = [string](Get-PsaTicketUrl -Id $id) } catch { $ticketUrl = '' }
    $txt = @{}
    $buildText = {
        $lines = @("Out-of-office check: ticket $id is assigned to someone who is out.")
        foreach ($o in $out) { $lines += "- $($o.identifier): $(@($o.reasons) -join '; ')" }
        $lines += $planText
        $txt.note = ($lines -join "`n")

        # What happened (headline), what the dispatcher should do, and the subject, per outcome. Preview says "would".
        $w = if ($ctx.live) { @{ was = 'was'; is = 'is'; has = 'has' } } else { @{ was = 'would be'; is = 'would be'; has = 'would have' } }
        switch ($case) {
            'reassigned' { $subj = "Ticket $id reassigned to ${backupId}: $owner is out"; $head = "Ticket $id $($w.was) reassigned from $owner to $backupId because $owner is out."; $todo = "Nothing, unless $backupId isn't the right fit. $backupId $($w.was) picked from $(if ($pick) { "$($pick.source) ($($pick.how))" } else { 'the team' })." }
            'unassigned' { $subj = "Ticket $id unassigned: $owner is out"; $head = "$owner $($w.was) removed as owner of ticket $id because they're out. The ticket $($w.is) back in the dispatch queue."; $todo = 'Assign the ticket to a technician who is in.' }
            'no-replacement' { $subj = "Action needed: ticket $id is assigned to $owner, who is out"; $head = "Ticket $id is assigned to $owner, who is out, and nobody in $poolSource is available to take it."; $todo = 'Reassign the ticket by hand.' }
            'failed' { $subj = "Action needed: ticket $id is assigned to $owner, who is out"; $head = "Ticket $id is assigned to $owner, who is out. The workflow tried to $(if ($failedPlan -eq 'unassign') { "remove $owner as owner" } else { "reassign it to $backupId" }), but ConnectWise refused the change."; $todo = "$(if ($failedPlan -eq 'unassign') { 'Remove the owner' } else { "Reassign the ticket to $backupId or another technician" }) by hand." }
            'no-owner' { $subj = "Check ticket ${id}: $outNames is out"; $head = "Ticket $id has no owner saved yet, and $outNames, who ServiceAI picked for it, is out."; $todo = "Make sure the ticket isn't assigned or scheduled to $outNames." }
            'resource-only' { $subj = "Check ticket ${id}: $outNames is out"; $head = "$outNames is on the schedule for ticket $id but is out. The owner, $owner, is in."; $todo = "Remove $outNames from the ticket's schedule if they shouldn't be on it." }
            default { $subj = "Action needed: ticket $id is assigned to $outNames, who is out"; $head = "Ticket $id is assigned to $outNames, who is out."; $todo = 'Reassign the ticket if it can''t wait until they''re back.' }
        }
        if (-not $ctx.live) { $subj = "Preview: $subj" }

        $details = [ordered]@{}
        $details['Ticket'] = "#$id$(if ($ctx.summary) { " $($ctx.summary)" })"
        if ($ctx.company) { $details['Company'] = [string]$ctx.company }
        if ($ctx.board) { $details['Board'] = [string]$ctx.board }

        # Plain text: one fact per line, blank lines between sections (Teams and mail clients that strip HTML).
        $t = @($head, '')
        foreach ($k in $details.Keys) { $t += "${k}: $($details[$k])" }
        if ($ticketUrl) { $t += "Open the ticket: $ticketUrl" }
        foreach ($o in $out) {
            $t += ''; $t += "Why $($o.identifier) is out:"
            foreach ($r in @($o.items)) { $t += "  - $($r.what) ($($r.where)), until $($r.until)" }
        }
        $t += ''; $t += "What to do: $todo"
        $t += ''; $t += 'Sent by the Out-of-Office Check workflow in AutomationAI. The ticket has an internal note with the same details.'
        $txt.subject = $subj
        $txt.alert = ($t -join "`n")

        # HTML: the same content, laid out so Outlook doesn't merge lines.
        $e = { param($v) ConvertTo-PmHtml ([string]$v) }
        $rows = foreach ($k in $details.Keys) { "<tr><td style=""padding:2px 12px 2px 0;color:#555"">$(& $e $k)</td><td style=""padding:2px 0"">$(& $e $details[$k])</td></tr>" }
        $why = foreach ($o in $out) {
            "<p style=""margin:16px 0 4px""><b>Why $(& $e $o.identifier) is out</b></p><ul style=""margin:0;padding-left:20px"">" + ((@($o.items) | ForEach-Object { "<li>$(& $e $_.what) <span style=""color:#555"">($(& $e $_.where))</span>, until <b>$(& $e $_.until)</b></li>" }) -join '') + '</ul>'
        }
        $link = if ($ticketUrl) { "<p style=""margin:12px 0""><a href=""$(& $e $ticketUrl)"">Open ticket $(& $e $id) in ConnectWise</a></p>" } else { '' }
        $txt.html = @"
    <div style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#222;line-height:1.4">
    <p style="margin:0 0 12px;font-size:15px"><b>$(& $e $head)</b></p>
    <table style="border-collapse:collapse;font-size:14px">$($rows -join '')</table>
    $link$($why -join '')
    <p style="margin:16px 0 4px"><b>What to do</b></p><p style="margin:0">$(& $e $todo)</p>
    <p style="margin:20px 0 0;color:#777;font-size:12px">Sent by the Out-of-Office Check workflow in AutomationAI. The ticket has an internal note with the same details.</p>
    </div>
"@
    }
    $failedPlan = ''
    . $buildText
    $noteText = $txt.note; $alertText = $txt.alert; $subject = $txt.subject

    if (-not $ctx.live) {
        # Preview: say what would happen, not what did.
        foreach ($pair in @(@('The ticket was reassigned from', 'The ticket would be reassigned from'), @(' was removed as owner so the ticket goes back', ' would be removed as owner so the ticket would go back'), @('The assignment was left as it is', 'The assignment would be left as it is'), @('so the ticket was left with', 'so the ticket would be left with'))) { $planText = $planText.Replace($pair[0], $pair[1]) }
        . $buildText
        $noteText = $txt.note; $alertText = $txt.alert; $subject = $txt.subject
        $would = if ($plan -eq 'reassign') { " It would go to $backupId." } elseif ($plan -eq 'unassign') { " The owner would be removed." } else { '' }
        $msg = "Preview: ticket $id is assigned to $(@($out | ForEach-Object { $_.identifier }) -join ', '), who is out.$would Live mode is off, so nothing was changed, noted or sent."
        return ([ordered]@{ status = 'pending_confirmation'; message = $msg; public_note = ''; internal_note = $noteText; ticket_id = $id; out_members = $out; plan = $plan; replacement = $backupId; considered = @($considered); changed = $false; subject = $subject; alert_text = $alertText; alert_html = $txt.html; actions = @($actions); warnings = @($warnings); chatReply = $msg })
    }

    # ---- make the change ----
    $changed = $false
    $changeFailed = $false
    try {
        if ($plan -eq 'unassign') {
            $null = Invoke-Psa PATCH "/service/tickets/$id" @([ordered]@{ op = 'remove'; path = 'owner' })
            $changed = $true; $null = $actions.Add("Removed $owner as owner of ticket $id.")
        }
        elseif ($plan -eq 'reassign') {
            Set-PsaAssignee -Id $id -UserId $backupId
            $changed = $true; $null = $actions.Add("Made $backupId the owner of ticket $id.")
        }
    }
    catch {
        # The dispatcher still needs to know, so a failed change becomes a flag: note and alert still go out.
        $why = [string]$_.Exception.Message
        $changeFailed = $true
        $hint = if ($why -match '\(HTTP 403\)') { ' Give the API member Service Desk > Service Tickets: Edit permission.' } else { '' }
        $null = $warnings.Add("The ticket could not be changed ($plan): $why$hint")
        $planText = "The workflow tried to $(if ($plan -eq 'unassign') { "remove $owner as owner" } else { "reassign the ticket to $backupId" }) but ConnectWise refused, so please do it by hand."
        $failedPlan = $plan; $plan = 'flag'; $case = 'failed'
        . $buildText
        $noteText = $txt.note; $alertText = $txt.alert; $subject = $txt.subject
    }

    # ---- move the out owner's schedule entries on this ticket to the new owner, so the ticket leaves their calendar ----
    # Unverified on a live ConnectWise: PATCH /schedule/entries/{id} replace member.
    if ($changed -and $plan -eq 'reassign') {
        try {
            foreach ($e in @(Get-OooTicketEntries -TicketId $id -Identifier $owner)) {
                $eid = [string](Get-PsaProp $e 'id')
                try {
                    $null = Invoke-Psa PATCH "/schedule/entries/$eid" @([ordered]@{ op = 'replace'; path = 'member'; value = @{ identifier = $backupId } })
                    $null = $actions.Add("Moved schedule entry $eid on ticket $id from $owner to $backupId.")
                }
                catch { $null = $warnings.Add("Schedule entry $eid still has $owner on ticket ${id}: $($_.Exception.Message) Give the API member edit access to schedule entries, or move it by hand.") }
            }
        }
        catch { $null = $warnings.Add("The ticket's schedule entries couldn't be read, so $owner may still show on ticket ${id}'s resources: $($_.Exception.Message)") }
    }

    # ---- tell the dispatcher ----
    $told = @()
    $to = @($ctx.dispatch_to | Where-Object { $_ })
    if ($to.Count) {
        $mail = Send-PmMail -To $to -Subject $subject -Text $alertText -Html $txt.html -Tag 'ooo-check'
        if ($mail.sent) { $told += "email to $($to -join ', ')"; $null = $actions.Add("Emailed the dispatcher ($($to -join ', ')).") }
        else { $null = $warnings.Add("The dispatcher email was not sent: $(([string]$mail.reason).TrimEnd('.')).") }
    }
    if ($ctx.teams_flow) {
        try {
            $null = Invoke-RestMethod -Method POST -Uri ([string]$ctx.teams_flow) -Body (ConvertTo-Json -InputObject ([ordered]@{ title = $subject; text = $alertText; ticketId = $id }) -Compress) -ContentType 'application/json' -ErrorAction Stop
            $told += 'Teams'; $null = $actions.Add('Posted the alert to Teams.')
        }
        catch { $null = $warnings.Add("The Teams alert was not posted: $($_.Exception.Message)") }
    }
    if (-not $told.Count) { $null = $warnings.Add('No dispatcher alert went out (set OOO-DispatchTo and Postmark, or OOO-TeamsFlowUrl). The internal note is the only record.') }

    $noteFull = "$noteText`nDispatcher told by: $(if ($told.Count) { $told -join ' and ' } else { 'nobody (no alert is set up)' })."
    $noted = Add-PsaNote -Id $id -Text $noteFull -Title 'Out-of-office check' -Internal -Marker 'ooo-check'
    if ($noted -eq 'already-present') { $null = $warnings.Add("Ticket $id already had the out-of-office note, so no second note was added.") } else { $null = $actions.Add("Added an internal note to ticket $id.") }

    $msg = "Ticket ${id}: $(@($out | ForEach-Object { $_.identifier }) -join ', ') is out. $planText"
    return ([ordered]@{ status = $(if ($changeFailed) { 'incomplete' } else { 'success' }); message = $msg; public_note = ''; internal_note = $noteFull; ticket_id = $id; out_members = $out; plan = $plan; replacement = $(if ($changed) { $backupId } else { '' }); considered = @($considered); changed = $changed; actions = @($actions); warnings = @($warnings); chatReply = $msg })

}

if ([string](Get-StepProp $ctx 'mode') -ne 'sweep') {
    $r = Invoke-OooTicket $ctx
    foreach ($w in @($r.warnings)) { if ($w -and -not $warnings.Contains([string]$w)) { $null = $warnings.Add([string]$w) } }
    Add-ActPsaWarnings
    $r.warnings = @($warnings)
    $stopState.done = $true
    Set-NodeOutput $r
    return
}

# ---- sweep: every ticket the check step found ----
foreach ($x in @($ctx.warnings)) { if ($x -and -not $warnings.Contains([string]$x)) { $null = $warnings.Add([string]$x) } }
$results = New-Object System.Collections.ArrayList
foreach ($item in @($ctx.items)) {
    $tid = [string]$item.ticket_id
    try { $r = Invoke-OooTicket $item }
    catch { $r = [ordered]@{ status = 'error'; message = "Ticket ${tid}: $($_.Exception.Message)"; ticket_id = $tid; plan = 'flag'; replacement = ''; changed = $false; actions = @(); warnings = @() } }
    $null = $results.Add([ordered]@{ ticket_id = $tid; status = [string]$r.status; plan = [string]$r.plan; replacement = [string]$r.replacement; changed = [bool]$r.changed; message = [string]$r.message; considered = @($r.considered); actions = @($r.actions); warnings = @($r.warnings) })
}
Add-ActPsaWarnings
$stopState.done = $true
$n = $results.Count
$moved = @($results | Where-Object { $_.changed }).Count
$bad = @($results | Where-Object { @('error', 'incomplete') -contains $_.status }).Count
$preview = -not $ctx.live
$msg = if (-not $n) { [string]$ctx.message } elseif ($preview) { "Preview: $n ticket$(if ($n -ne 1) { 's' }) assigned to someone who is out. Live mode is off, so nothing was changed, noted or sent." } else { "$n ticket$(if ($n -ne 1) { 's' }) assigned to someone who is out: $moved reassigned$(if ($bad) { ", $bad need a person (see results)" })." }
$status = if ($preview -and $n) { 'pending_confirmation' } elseif ($bad) { 'incomplete' } else { 'success' }
Set-NodeOutput ([ordered]@{ status = $status; message = $msg; public_note = ''; internal_note = ''; ticket_id = ''; mode = 'sweep'; out_now = @($ctx.out_now); tickets = @($results); skipped = @($ctx.skipped); changed = ($moved -gt 0); actions = @($ctx.actions); warnings = @($warnings); chatReply = $msg })
