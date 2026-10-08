# ---------- src/psa-extra.ps1: ticket lists, time entries and contacts for six PSAs ----------
# Adds what _shared/psa.ps1 doesn't have yet: listing tickets by state and date, reading a ticket's
# time entries, listing a company's contacts and setting a ticket's contact.
# The identical file ships in automationai/time-entry-review/src and automationai/psa-hygiene/src.
# It is a candidate to move into automationai/_shared/psa.ps1.
# Needs _shared/psa.ps1 pasted above it (Invoke-Psa, Get-PsaProp, Get-PsaAtPicklist and $PsaState).
# Every call carries a source note. "Unverified" means it is not in reference/build-kit/PSA.md and has not
# been proven by a live run; check it before relying on it. "Vendor docs" means it was checked against the
# vendor's published API spec (Kaseya BMS and Syncro swagger) but not yet run live.

$PsaState.FindTruncated = $false

function ConvertTo-PsaUtcText {
    param($v)
    if ($null -eq $v) { return '' }
    $d = [datetime]::MinValue
    if ($v -is [datetime]) { $d = $v }
    else {
        $s = ([string]$v).Trim()
        if (-not $s) { return '' }
        $styles = ([Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
        if (-not [datetime]::TryParse($s, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$d)) { return '' }
    }
    if ($d.Kind -eq [DateTimeKind]::Local) { $d = $d.ToUniversalTime() }
    # HaloPSA writes 1900-01-01 for an empty date.
    if ($d.Year -lt 1901) { return '' }
    return $d.ToString('yyyy-MM-ddTHH:mm:ssZ')
}
function ConvertFrom-PsaHtml {
    param([string]$s)
    if ([string]::IsNullOrEmpty($s)) { return '' }
    $t = [System.Net.WebUtility]::HtmlDecode(($s -replace '<[^>]+>', ' '))
    return (($t -replace '\s+', ' ').Trim())
}
function Get-PsaBlankable { param($v) if (Test-PsaBlank $v) { return '' }; return [string]$v }
function New-PsaTicketRow {
    param($Id, $Number, $Summary, $CompanyId, $CompanyName, $ContactId, $ContactName, $Status, [bool]$Closed, $ClosedDate, $Created, $Updated, $AssigneeId, $AssigneeName)
    return [ordered]@{
        id = [string]$Id; number = $(if (Test-PsaBlank $Number) { [string]$Id } else { [string]$Number }); summary = [string]$Summary
        companyId = (Get-PsaBlankable $CompanyId); companyName = [string]$CompanyName
        contactId = (Get-PsaBlankable $ContactId); contactName = [string]$ContactName
        status = [string]$Status; closed = $Closed; closedDate = (ConvertTo-PsaUtcText $ClosedDate)
        createdDate = (ConvertTo-PsaUtcText $Created); updatedDate = (ConvertTo-PsaUtcText $Updated)
        assigneeId = (Get-PsaBlankable $AssigneeId); assigneeName = [string]$AssigneeName
    }
}

# Lists tickets. Returns @(normalized rows): id, number, summary, companyId, companyName, contactId, contactName,
# status, closed, closedDate, createdDate, updatedDate, assigneeId, assigneeName (dates are UTC text or '').
#   -State open       every ticket that isn't closed
#   -State closed     tickets closed from -ClosedFrom (inclusive) to -ClosedTo (exclusive), both UTC
#   -CompanyId        only this PSA company
#   -Max              stop after this many; $PsaState.FindTruncated says whether it stopped early
function Find-PsaTickets {
    param([ValidateSet('open', 'closed')][string]$State = 'open', [string]$ClosedFrom = '', [string]$ClosedTo = '', [string]$CompanyId = '', [int]$Max = 1000)
    $c = Get-PsaConn
    $PsaState.FindTruncated = $false
    $closed = $State -eq 'closed'
    $from = $null; $to = $null
    if ($closed) {
        if (-not $ClosedFrom -or -not $ClosedTo) { throw 'Find-PsaTickets -State closed needs -ClosedFrom and -ClosedTo.' }
        $from = [datetime]::Parse((ConvertTo-PsaUtcText $ClosedFrom), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
        $to = [datetime]::Parse((ConvertTo-PsaUtcText $ClosedTo), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
    }
    $fromIso = if ($closed) { $from.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { '' }
    $toIso = if ($closed) { $to.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { '' }
    if ($CompanyId -and $CompanyId -notmatch '^\d+$') { throw "The PSA company id must be a number (it was '$CompanyId')." }
    $rows = New-Object System.Collections.ArrayList
    $full = { $rows.Count -ge $Max }
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: the closedDate and closedFlag conditions with [datetime] values, and _info.lastUpdated.
            $cond = if ($closed) { "closedFlag=true and closedDate>=[$fromIso] and closedDate<[$toIso]" } else { 'closedFlag=false' }
            if ($CompanyId) { $cond += " and company/id=$CompanyId" }
            for ($page = 1; $page -le 100; $page++) {
                $r = @(Invoke-Psa GET "/service/tickets?conditions=$(ConvertTo-PsaQuery $cond)&orderBy=$(ConvertTo-PsaQuery 'id asc')&pageSize=200&page=$page" | Where-Object { $null -ne $_ })
                foreach ($t in $r) {
                    if (& $full) { $PsaState.FindTruncated = $true; break }
                    $null = $rows.Add((New-PsaTicketRow (Get-PsaProp $t 'id') $null (Get-PsaProp $t 'summary') (Get-PsaPath $t 'company.id') (Get-PsaPath $t 'company.name') (Get-PsaPath $t 'contact.id') (Get-PsaPath $t 'contact.name') (Get-PsaPath $t 'status.name') ([bool](Get-PsaProp $t 'closedFlag')) (Get-PsaProp $t 'closedDate') (Get-PsaPath $t '_info.dateEntered') (Get-PsaPath $t '_info.lastUpdated') (Get-PsaPath $t 'owner.identifier') (Get-PsaPath $t 'owner.name')))
                }
                if ($PsaState.FindTruncated -or $r.Count -lt 200) { break }
            }
        }
        'autotask' {
            # Unverified: filtering on completedDate and lastActivityDate, and following pageDetails.nextPageUrl.
            $done = @(Get-PsaAtCompleteStatuses)
            $labels = @{}; foreach ($v in @(Get-PsaAtPicklist 'Tickets' 'status')) { $labels[[string](Get-PsaProp $v 'value')] = [string](Get-PsaProp $v 'label') }
            $f = @()
            if ($closed) { $f += [ordered]@{ op = 'gte'; field = 'completedDate'; value = $fromIso }; $f += [ordered]@{ op = 'lt'; field = 'completedDate'; value = $toIso } }
            else { foreach ($s in $done) { $f += [ordered]@{ op = 'noteq'; field = 'status'; value = $s } } }
            if ($CompanyId) { $f += [ordered]@{ op = 'eq'; field = 'companyID'; value = [long]$CompanyId } }
            $path = "/Tickets/query?search=$(ConvertTo-PsaQuery (@{ filter = $f; MaxRecords = 500 } | ConvertTo-Json -Depth 6 -Compress))"
            for ($page = 1; $page -le 100 -and $path; $page++) {
                $r = Invoke-Psa GET $path
                foreach ($t in @(Get-PsaProp $r 'items' | Where-Object { $null -ne $_ })) {
                    if (& $full) { $PsaState.FindTruncated = $true; break }
                    $st = [string](Get-PsaProp $t 'status')
                    $isClosed = $done -contains [int](Get-PsaProp $t 'status')
                    $null = $rows.Add((New-PsaTicketRow (Get-PsaProp $t 'id') (Get-PsaProp $t 'ticketNumber') (Get-PsaProp $t 'title') (Get-PsaProp $t 'companyID') '' (Get-PsaProp $t 'contactID') '' $(if ($labels.ContainsKey($st)) { $labels[$st] } else { $st }) $isClosed (Get-PsaProp $t 'completedDate') (Get-PsaProp $t 'createDate') (Get-PsaProp $t 'lastActivityDate') (Get-PsaProp $t 'assignedResourceID') ''))
                }
                if ($PsaState.FindTruncated) { break }
                $path = [string](Get-PsaPath $r 'pageDetails.nextPageUrl')
            }
            # Company names for the report. Unverified: the "in" filter operator on Companies.
            $ids = @($rows | ForEach-Object { $_.companyId } | Where-Object { $_ } | Sort-Object -Unique)
            if ($ids.Count) {
                $names = @{}
                try {
                    for ($i = 0; $i -lt $ids.Count; $i += 200) {
                        $chunk = @($ids | Select-Object -Skip $i -First 200 | ForEach-Object { [long]$_ })
                        $s = @{ filter = @([ordered]@{ op = 'in'; field = 'id'; value = $chunk }); IncludeFields = @('id', 'companyName') }
                        foreach ($co in @(Get-PsaProp (Invoke-Psa GET "/Companies/query?search=$(ConvertTo-PsaQuery ($s | ConvertTo-Json -Depth 6 -Compress))") 'items' | Where-Object { $null -ne $_ })) { $names[[string](Get-PsaProp $co 'id')] = [string](Get-PsaProp $co 'companyName') }
                    }
                }
                catch { }
                foreach ($row in $rows) { if ($row.companyId -and $names.ContainsKey($row.companyId)) { $row.companyName = $names[$row.companyId] } }
            }
        }
        'halopsa' {
            # Unverified: open_only, closed_only with datesearch=datecleared and startdate/enddate, and the list's field names.
            $q = if ($closed) { "closed_only=true&datesearch=datecleared&startdate=$(ConvertTo-PsaQuery $fromIso)&enddate=$(ConvertTo-PsaQuery $toIso)" } else { 'open_only=true' }
            if ($CompanyId) { $q += "&client_id=$CompanyId" }
            for ($page = 1; $page -le 100; $page++) {
                $r = Invoke-Psa GET "/Tickets?$q&pageinate=true&page_size=100&page_no=$page"
                $list = @(Get-PsaProp $r 'tickets' | Where-Object { $null -ne $_ })
                foreach ($t in $list) {
                    if (& $full) { $PsaState.FindTruncated = $true; break }
                    $cd = Get-PsaProp $t 'datecleared'
                    if ($closed) { $cdt = ConvertTo-PsaUtcText $cd; if ($cdt -and ($cdt -lt $fromIso -or $cdt -ge $toIso)) { continue } }
                    $status = Get-PsaProp $t 'status_name'; if (-not $status) { $status = Get-PsaProp $t 'status_id' }
                    $upd = Get-PsaProp $t 'lastactiondate'; if (-not (ConvertTo-PsaUtcText $upd)) { $upd = Get-PsaProp $t 'last_update' }
                    $null = $rows.Add((New-PsaTicketRow (Get-PsaProp $t 'id') $null (Get-PsaProp $t 'summary') (Get-PsaProp $t 'client_id') (Get-PsaProp $t 'client_name') (Get-PsaProp $t 'user_id') (Get-PsaProp $t 'user_name') $status $closed $cd (Get-PsaProp $t 'dateoccurred') $upd (Get-PsaProp $t 'agent_id') (Get-PsaProp $t 'agent_name')))
                }
                if ($PsaState.FindTruncated -or $list.Count -lt 100) { break }
            }
        }
        'kaseyabms' {
            # Vendor docs: Filter.CompletedDateFrom/To, Filter.ExcludeCompleted (int), Filter.AccountIds, PageSize, PageNumber
            # and the Result fields. Unverified live: the date format and whether CompletedDateTo is inclusive.
            $q = if ($closed) { "Filter.CompletedDateFrom=$(ConvertTo-PsaQuery $fromIso)&Filter.CompletedDateTo=$(ConvertTo-PsaQuery $toIso)" } else { 'Filter.ExcludeCompleted=1' }
            if ($CompanyId) { $q += "&Filter.AccountIds=$CompanyId" }
            for ($page = 1; $page -le 100; $page++) {
                $r = Invoke-Psa GET "/servicedesk/tickets?$q&PageSize=100&PageNumber=$page"
                $list = @(Get-PsaProp $r 'Result' | Where-Object { $null -ne $_ })
                foreach ($t in $list) {
                    if (& $full) { $PsaState.FindTruncated = $true; break }
                    $cd = Get-PsaProp $t 'CompletedDate'
                    if ($closed) { $cdt = ConvertTo-PsaUtcText $cd; if ($cdt -and ($cdt -lt $fromIso -or $cdt -ge $toIso)) { continue } }
                    $upd = Get-PsaProp $t 'LastActivityUpdate'; if (-not (ConvertTo-PsaUtcText $upd)) { $upd = Get-PsaProp $t 'ModifiedOn' }
                    $cr = Get-PsaProp $t 'OpenDate'; if (-not (ConvertTo-PsaUtcText $cr)) { $cr = Get-PsaProp $t 'CreatedOn' }
                    $null = $rows.Add((New-PsaTicketRow (Get-PsaProp $t 'Id') (Get-PsaProp $t 'TicketNumber') (Get-PsaProp $t 'Title') (Get-PsaProp $t 'AccountId') (Get-PsaProp $t 'AccountName') (Get-PsaProp $t 'ContactId') (Get-PsaProp $t 'ContactName') (Get-PsaProp $t 'StatusName') $closed $cd $cr $upd (Get-PsaProp $t 'AssigneeId') (Get-PsaProp $t 'AssigneeName')))
                }
                $total = [int](Get-PsaProp $r 'TotalRecords')
                if ($PsaState.FindTruncated -or $list.Count -lt 100 -or ($total -gt 0 -and $page * 100 -ge $total)) { break }
            }
        }
        'syncro' {
            # Vendor docs: resolved_after, status "Not Closed", customer_id, 25 per page with meta.total_pages.
            # Unverified: that "Resolved" is the only closed status. resolved_after takes a date, so the range is re-checked here.
            $q = if ($closed) { "resolved_after=$($from.AddDays(-1).ToString('yyyy-MM-dd'))" } else { "status=$(ConvertTo-PsaQuery 'Not Closed')" }
            if ($CompanyId) { $q += "&customer_id=$CompanyId" }
            for ($page = 1; $page -le 200; $page++) {
                $r = Invoke-Psa GET "/tickets?$q&page=$page"
                foreach ($t in @(Get-PsaProp $r 'tickets' | Where-Object { $null -ne $_ })) {
                    if (& $full) { $PsaState.FindTruncated = $true; break }
                    $cd = Get-PsaProp $t 'resolved_at'
                    if ($closed) { $cdt = ConvertTo-PsaUtcText $cd; if (-not $cdt -or $cdt -lt $fromIso -or $cdt -ge $toIso) { continue } }
                    $st = [string](Get-PsaProp $t 'status')
                    $null = $rows.Add((New-PsaTicketRow (Get-PsaProp $t 'id') (Get-PsaProp $t 'number') (Get-PsaProp $t 'subject') (Get-PsaProp $t 'customer_id') (Get-PsaProp $t 'customer_business_then_name') (Get-PsaProp $t 'contact_id') (Get-PsaProp $t 'contact_fullname') $st ($closed -or $st -eq 'Resolved') $cd (Get-PsaProp $t 'created_at') (Get-PsaProp $t 'updated_at') (Get-PsaProp $t 'user_id') (Get-PsaPath $t 'user.full_name')))
                }
                if ($PsaState.FindTruncated -or $page -ge [int](Get-PsaPath $r 'meta.total_pages')) { break }
            }
        }
        'zendesk' {
            # Unverified: the solved>/solved< search terms with a UTC time. Search returns at most 1,000 results,
            # and a ticket has no solved date of its own (it is in ticket metrics), so closedDate stays empty.
            $q = if ($closed) { "type:ticket status>=solved solved>$($from.AddSeconds(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')) solved<$toIso" } else { 'type:ticket status<solved' }
            if ($CompanyId) { $q += " organization:$CompanyId" }
            $path = "/search?query=$(ConvertTo-PsaQuery $q)&sort_by=created_at&sort_order=asc&per_page=100"
            for ($page = 1; $page -le 10 -and $path; $page++) {
                $r = Invoke-Psa GET $path
                foreach ($t in @(Get-PsaProp $r 'results' | Where-Object { $null -ne $_ })) {
                    if (& $full) { $PsaState.FindTruncated = $true; break }
                    $st = [string](Get-PsaProp $t 'status')
                    $null = $rows.Add((New-PsaTicketRow (Get-PsaProp $t 'id') $null (Get-PsaProp $t 'subject') (Get-PsaProp $t 'organization_id') '' (Get-PsaProp $t 'requester_id') '' $st ($st -in @('solved', 'closed')) $null (Get-PsaProp $t 'created_at') (Get-PsaProp $t 'updated_at') (Get-PsaProp $t 'assignee_id') ''))
                }
                if ($PsaState.FindTruncated) { break }
                $path = [string](Get-PsaProp $r 'next_page')
            }
        }
    }
    return @($rows)
}

# A ticket's time entries. Returns @{ supported; entries; reason }:
#   supported  $false when this PSA can't report time (Zendesk without -ZendeskTimeFieldId); reason says why
#   entries    @(@{ id; hours; notes; notesKnown; billable ($true, $false or $null when not set); billableKnown; who; date })
#              notesKnown and billableKnown are $false when the PSA has no such field for that entry.
function Get-PsaTimeEntries {
    param([string]$TicketId, [string]$ZendeskTimeFieldId = '')
    $c = Get-PsaConn
    $out = New-Object System.Collections.ArrayList
    $add = {
        param($Id, $Hours, $Notes, [bool]$NotesKnown, $Billable, [bool]$BillableKnown, $Who, $Date)
        $h = 0.0; try { $h = [double]$Hours } catch { }
        $null = $out.Add([ordered]@{ id = [string]$Id; hours = [Math]::Round($h, 2); notes = [string]$Notes; notesKnown = $NotesKnown; billable = $Billable; billableKnown = $BillableKnown; who = [string]$Who; date = (ConvertTo-PsaUtcText $Date) })
    }
    $longer = { param($a, $b) $x = ([string]$a).Trim(); $y = ([string]$b).Trim(); if ($x.Length -ge $y.Length) { $x } else { $y } }
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: /time/entries with chargeToType and chargeToId conditions; billableOption values Billable, DoNotBill, NoCharge, NoDefault.
            $cond = "chargeToType=`"ServiceTicket`" and chargeToId=$TicketId"
            foreach ($e in @(Invoke-Psa GET "/time/entries?conditions=$(ConvertTo-PsaQuery $cond)&pageSize=1000" | Where-Object { $null -ne $_ })) {
                $bo = [string](Get-PsaProp $e 'billableOption')
                $b = if ($bo -eq 'Billable') { $true } elseif ($bo -in @('DoNotBill', 'NoCharge')) { $false } else { $null }
                $who = Get-PsaPath $e 'member.name'; if (-not $who) { $who = Get-PsaPath $e 'member.identifier' }
                & $add (Get-PsaProp $e 'id') (Get-PsaProp $e 'actualHours') (& $longer (Get-PsaProp $e 'notes') (Get-PsaProp $e 'internalNotes')) $true $b $true $who (Get-PsaProp $e 'timeStart')
            }
        }
        'autotask' {
            # Unverified: TimeEntries query on ticketID, and hoursWorked, summaryNotes, internalNotes, isNonBillable.
            $s = @{ filter = @([ordered]@{ op = 'eq'; field = 'ticketID'; value = [long]$TicketId }) }
            foreach ($e in @(Get-PsaProp (Invoke-Psa GET "/TimeEntries/query?search=$(ConvertTo-PsaQuery ($s | ConvertTo-Json -Depth 5 -Compress))") 'items' | Where-Object { $null -ne $_ })) {
                $nb = Get-PsaProp $e 'isNonBillable'
                $b = if ($null -eq $nb) { $null } else { -not [bool]$nb }
                & $add (Get-PsaProp $e 'id') (Get-PsaProp $e 'hoursWorked') (& $longer (Get-PsaProp $e 'summaryNotes') (Get-PsaProp $e 'internalNotes')) $true $b $true (Get-PsaProp $e 'resourceID') (Get-PsaProp $e 'dateWorked')
            }
        }
        'halopsa' {
            # Unverified: /Actions?ticket_id with excludesys, timetaken in hours, and actionchargehours/actionnonchargehours
            # as the billable split. Only actions with time count as time entries.
            $r = Invoke-Psa GET "/Actions?ticket_id=$TicketId&excludesys=true"
            $list = @(Get-PsaProp $r 'actions'); if (-not @($list | Where-Object { $null -ne $_ }).Count -and $r -is [array]) { $list = @($r) }
            foreach ($e in @($list | Where-Object { $null -ne $_ })) {
                $h = 0.0; try { $h = [double](Get-PsaProp $e 'timetaken') } catch { }
                if ($h -le 0) { continue }
                $ch = 0.0; $nch = 0.0; try { $ch = [double](Get-PsaProp $e 'actionchargehours') } catch { }; try { $nch = [double](Get-PsaProp $e 'actionnonchargehours') } catch { }
                $b = if ($ch -gt 0) { $true } elseif ($nch -gt 0) { $false } else { $null }
                $note = Get-PsaProp $e 'note'; if (-not $note) { $note = Get-PsaProp $e 'note_html' }
                & $add (Get-PsaProp $e 'id') $h (ConvertFrom-PsaHtml ([string]$note)) $true $b $true (Get-PsaProp $e 'who') (Get-PsaProp $e 'datetime')
            }
        }
        'kaseyabms' {
            # Vendor docs: GET /v2/timelogs with Filter.TicketId, and Timespent, Notes, InternalNotes, IsBillable.
            # Unverified live: that Timespent is in hours.
            for ($page = 1; $page -le 20; $page++) {
                $r = Invoke-Psa GET "/timelogs?Filter.TicketId=$TicketId&PageSize=100&PageNumber=$page"
                $list = @(Get-PsaProp $r 'Result' | Where-Object { $null -ne $_ })
                foreach ($e in $list) {
                    $ib = Get-PsaProp $e 'IsBillable'
                    & $add (Get-PsaProp $e 'Id') (Get-PsaProp $e 'Timespent') (& $longer (Get-PsaProp $e 'Notes') (Get-PsaProp $e 'InternalNotes')) $true $(if ($null -eq $ib) { $null } else { [bool]$ib }) $true ("$(Get-PsaProp $e 'FirstName') $(Get-PsaProp $e 'LastName')".Trim()) (Get-PsaProp $e 'StartDate')
                }
                if ($list.Count -lt 100) { break }
            }
        }
        'syncro' {
            # Vendor docs: GET /ticket_timers?ticket_id with active_duration (seconds), billable and notes.
            # Unverified: labour charged straight as ticket line items (no timer) is read from the ticket's line_items
            # when the name looks like labour or time, with quantity as hours.
            for ($page = 1; $page -le 20; $page++) {
                $r = Invoke-Psa GET "/ticket_timers?ticket_id=$TicketId&page=$page"
                foreach ($e in @(Get-PsaProp $r 'ticket_timers' | Where-Object { $null -ne $_ })) {
                    $sec = 0.0; try { $sec = [double](Get-PsaProp $e 'active_duration') } catch { }
                    $bl = Get-PsaProp $e 'billable'
                    & $add (Get-PsaProp $e 'id') ($sec / 3600) (Get-PsaProp $e 'notes') $true $(if ($null -eq $bl) { $null } else { [bool]$bl }) $true (Get-PsaProp $e 'user_id') (Get-PsaProp $e 'start_time')
                }
                if ($page -ge [int](Get-PsaPath $r 'meta.total_pages')) { break }
            }
            if (-not $out.Count) {
                $t = Get-PsaProp (Invoke-Psa GET "/tickets/$TicketId") 'ticket'
                foreach ($li in @(Get-PsaProp $t 'line_items' | Where-Object { $null -ne $_ })) {
                    $nm = "$(Get-PsaProp $li 'name') $(Get-PsaProp $li 'item')"
                    if ($nm -notmatch '(?i)labou?r|hour|time') { continue }
                    & $add "line-$(Get-PsaProp $li 'id')" (Get-PsaProp $li 'quantity') (Get-PsaProp $li 'description') $true $true $true '' (Get-PsaProp $li 'created_at')
                }
            }
        }
        'zendesk' {
            # Zendesk has no native time entries. The Time Tracking app keeps the ticket's total seconds in a custom
            # field; with that field's id the ticket counts as having time when the total is above zero. Notes and the
            # billable flag aren't available. Unverified: that the field holds whole seconds.
            if (-not $ZendeskTimeFieldId) { return @{ supported = $false; entries = @(); reason = 'Zendesk has no native time entries. Give zendesk_time_field_id (the Time Tracking app''s "Total time spent (sec)" field id) to check for tickets closed with no time.' } }
            $t = Get-PsaProp (Invoke-Psa GET "/tickets/$TicketId") 'ticket'
            $f = @(Get-PsaProp $t 'custom_fields' | Where-Object { $null -ne $_ -and [string](Get-PsaProp $_ 'id') -eq $ZendeskTimeFieldId }) | Select-Object -First 1
            $sec = 0.0; if ($f) { try { $sec = [double](Get-PsaProp $f 'value') } catch { } }
            if ($sec -gt 0) { & $add "zd-$TicketId" ($sec / 3600) '' $false $null $false '' (Get-PsaProp $t 'updated_at') }
        }
    }
    return @{ supported = $true; entries = @($out); reason = '' }
}

# A company's active contacts. Returns @{ primarySupported; contacts = @(@{ id; name; email; primary }) }.
# primarySupported is $false for PSAs with no primary-contact flag (Syncro, Zendesk); primary is then always $false.
function Get-PsaCompanyContacts {
    param([string]$CompanyId)
    $c = Get-PsaConn
    if ($CompanyId -notmatch '^\d+$') { throw "Get-PsaCompanyContacts needs a numeric company id (it was '$CompanyId')." }
    $list = New-Object System.Collections.ArrayList
    $supported = $true
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: company.defaultContact as the primary contact, and the contacts conditions.
            $co = Invoke-Psa GET "/company/companies/$CompanyId"
            $def = [string](Get-PsaPath $co 'defaultContact.id')
            $cond = "company/id=$CompanyId and inactiveFlag=false"
            foreach ($p in @(Invoke-Psa GET "/company/contacts?conditions=$(ConvertTo-PsaQuery $cond)&pageSize=1000" | Where-Object { $null -ne $_ })) {
                $id = [string](Get-PsaProp $p 'id')
                $null = $list.Add([ordered]@{ id = $id; name = "$(Get-PsaProp $p 'firstName') $(Get-PsaProp $p 'lastName')".Trim(); email = ''; primary = (($def -and $id -eq $def) -or (Get-PsaProp $p 'defaultFlag') -eq $true) })
            }
        }
        'autotask' {
            # Unverified: Contacts query on companyID and isActive, and the primaryContact flag.
            $s = @{ filter = @([ordered]@{ op = 'eq'; field = 'companyID'; value = [long]$CompanyId }, [ordered]@{ op = 'eq'; field = 'isActive'; value = 1 }) }
            foreach ($p in @(Get-PsaProp (Invoke-Psa GET "/Contacts/query?search=$(ConvertTo-PsaQuery ($s | ConvertTo-Json -Depth 5 -Compress))") 'items' | Where-Object { $null -ne $_ })) {
                $null = $list.Add([ordered]@{ id = [string](Get-PsaProp $p 'id'); name = "$(Get-PsaProp $p 'firstName') $(Get-PsaProp $p 'lastName')".Trim(); email = [string](Get-PsaProp $p 'emailAddress'); primary = ((Get-PsaProp $p 'primaryContact') -eq $true) })
            }
        }
        'halopsa' {
            # Unverified: /Users?client_id and the isprimarycontact flag name.
            $r = Invoke-Psa GET "/Users?client_id=$CompanyId&count=500"
            $users = @(Get-PsaProp $r 'users'); if (-not @($users | Where-Object { $null -ne $_ }).Count -and $r -is [array]) { $users = @($r) }
            foreach ($p in @($users | Where-Object { $null -ne $_ -and (Get-PsaProp $_ 'inactive') -ne $true })) {
                $pri = ((Get-PsaProp $p 'isprimarycontact') -eq $true) -or ((Get-PsaProp $p 'is_primary_contact') -eq $true)
                $null = $list.Add([ordered]@{ id = [string](Get-PsaProp $p 'id'); name = [string](Get-PsaProp $p 'name'); email = [string](Get-PsaProp $p 'emailaddress'); primary = $pri })
            }
        }
        'kaseyabms' {
            # Vendor docs: GET /v2/crm/contacts/summary with Filter.AccountId and Filter.IsActive; IsPoc marks the point of contact.
            for ($page = 1; $page -le 20; $page++) {
                $r = Invoke-Psa GET "/crm/contacts/summary?Filter.AccountId=$CompanyId&Filter.IsActive=true&PageSize=100&PageNumber=$page"
                $rs = @(Get-PsaProp $r 'Result' | Where-Object { $null -ne $_ })
                foreach ($p in $rs) {
                    $em = @(Get-PsaProp $p 'Emails' | Where-Object { $null -ne $_ }) | Select-Object -First 1
                    $null = $list.Add([ordered]@{ id = [string](Get-PsaProp $p 'Id'); name = "$(Get-PsaProp $p 'FirstName') $(Get-PsaProp $p 'LastName')".Trim(); email = [string](Get-PsaProp $em 'EmailAddress'); primary = ((Get-PsaProp $p 'IsPoc') -eq $true) })
                }
                if ($rs.Count -lt 100) { break }
            }
        }
        'syncro' {
            # Vendor docs: GET /contacts?customer_id. Syncro contacts have no primary flag.
            $supported = $false
            for ($page = 1; $page -le 20; $page++) {
                $r = Invoke-Psa GET "/contacts?customer_id=$CompanyId&page=$page"
                foreach ($p in @(Get-PsaProp $r 'contacts' | Where-Object { $null -ne $_ })) { $null = $list.Add([ordered]@{ id = [string](Get-PsaProp $p 'id'); name = [string](Get-PsaProp $p 'name'); email = [string](Get-PsaProp $p 'email'); primary = $false }) }
                if ($page -ge [int](Get-PsaPath $r 'meta.total_pages')) { break }
            }
        }
        'zendesk' {
            # Unverified: GET /organizations/{id}/users. Zendesk organizations have no primary contact.
            $supported = $false
            foreach ($p in @(Get-PsaProp (Invoke-Psa GET "/organizations/$CompanyId/users?per_page=100") 'users' | Where-Object { $null -ne $_ -and (Get-PsaProp $_ 'active') -ne $false })) {
                $null = $list.Add([ordered]@{ id = [string](Get-PsaProp $p 'id'); name = [string](Get-PsaProp $p 'name'); email = [string](Get-PsaProp $p 'email'); primary = $false })
            }
        }
    }
    return @{ primarySupported = $supported; contacts = @($list) }
}

# Sets a ticket's contact (the requester in Zendesk). Throws when the PSA rejects it.
function Set-PsaTicketContact {
    param([string]$Id, [string]$ContactId)
    $c = Get-PsaConn
    if ($ContactId -notmatch '^\d+$') { throw "Set-PsaTicketContact needs a numeric contact id (it was '$ContactId')." }
    switch ($c.Psa) {
        # Unverified: json-patch on contact, the same shape as owner (PSA.md).
        'connectwise' { $null = Invoke-Psa PATCH "/service/tickets/$Id" @([ordered]@{ op = 'replace'; path = 'contact'; value = @{ id = [int]$ContactId } }) }
        # Unverified: PATCH /Tickets with contactID, the at_update_ticket shape.
        'autotask' { $null = Invoke-Psa PATCH '/Tickets' ([ordered]@{ id = [long]$Id; contactID = [long]$ContactId }) }
        # Unverified: POST /Tickets with user_id updates the end user.
        'halopsa' { $null = Invoke-Psa POST '/Tickets' @([ordered]@{ id = [long]$Id; user_id = [long]$ContactId }) }
        # Vendor docs: PATCH /v2/servicedesk/tickets/{id} json-patch; ContactId is a ticket field. Unverified live.
        'kaseyabms' { $null = Invoke-Psa PATCH "/servicedesk/tickets/$Id" @([ordered]@{ op = 'replace'; path = '/ContactId'; value = [long]$ContactId }) }
        # Vendor docs: PUT /tickets/{id} takes contact_id in a flat body. Unverified live.
        'syncro' { $null = Invoke-Psa PUT "/tickets/$Id" @{ contact_id = [long]$ContactId } }
        # Vendor docs: requester_id on the ticket. Unverified live.
        'zendesk' { $null = Invoke-Psa PUT "/tickets/$Id" @{ ticket = @{ requester_id = [long]$ContactId } } }
    }
}
# ---------- end src/psa-extra.ps1 ----------
