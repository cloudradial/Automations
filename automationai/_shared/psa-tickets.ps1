# ---------- _shared/psa-tickets.ps1: ticket lists, time, contracts, invoices, contacts and SLA for six PSAs ----------
# ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk.
# Paste it AFTER _shared/psa.ps1 in the same step: it uses Connect-Psa, Invoke-Psa, Invoke-PsaRead,
# Get-PsaTicketNotes, Add-PsaNote, the Get-Psa* helpers and $PsaState from there.
# Edit this file, then run: node automationai/_shared/inject.js <automation-folder>
# Merged from the service-desk builds' src/psa-extra.ps1 files (October 2026). For each call the most
# complete, best-checked version was kept. Calls marked "Unverified" are not in reference/build-kit/PSA.md yet
# and have not been proven by a live run; check them against a real tenant before relying on them.
# "Vendor docs" means checked against the vendor's published API spec but not yet run live.

# One normalized ticket row. Dates are UTC [datetime] or $null.
function New-PsaTicketRow {
    param([hashtable]$F)
    $v = { param($k) if ($F.ContainsKey($k)) { $F[$k] } else { $null } }
    $s = { param($k) $x = & $v $k; if (Test-PsaBlank $x) { '' } else { [string]$x } }
    $t = { param($k) $x = & $v $k; if ($null -eq $x) { '' } else { [string]$x } }
    $id = & $s 'id'
    $prio = & $t 'priority'
    $qid = & $s 'queueId'; $qname = & $t 'queueName'
    $created = ConvertTo-PsaDate (& $v 'created')
    $updated = ConvertTo-PsaDate (& $v 'updated'); if ($null -eq $updated) { $updated = $created }
    $cfg = @(& $v 'configIds' | Where-Object { -not (Test-PsaBlank $_) } | ForEach-Object { [string]$_ })
    $closedAt = ConvertTo-PsaDate (& $v 'closed')
    $isClosed = [bool](& $v 'isClosed')
    $byStatus = if ($F.ContainsKey('closedByStatus')) { [bool]$F['closedByStatus'] } else { $isClosed }
    return @{
        id = $id; number = $(if (Test-PsaBlank (& $v 'number')) { $id } else { [string](& $v 'number') }); summary = (& $t 'summary'); description = (& $t 'description')
        status = (& $t 'status'); isClosed = $isClosed; closedByStatus = $byStatus; closedDateSet = ($null -ne $closedAt)
        companyId = (& $s 'companyId'); companyName = (& $t 'companyName')
        contactId = (& $s 'contactId'); contactName = (& $t 'contactName'); contactEmail = (& $t 'contactEmail')
        assigneeId = (& $s 'assigneeId'); assigneeName = (& $t 'assigneeName')
        queue = $(if ($qname) { $qname } else { $qid }); queueId = $qid; queueName = $qname
        priority = $prio; priorityLevel = (Get-PsaPriorityLevel $prio)
        created = $created; updated = $updated; closed = $closedAt; statusChanged = (ConvertTo-PsaDate (& $v 'statusChanged'))
        ticketType = (& $t 'ticketType'); configIds = $cfg
        url = $(if ($id) { Get-PsaTicketUrl $id } else { '' }); raw = (& $v 'raw')
    }
}

# One raw PSA ticket, from a list or from Get-PsaTicket's .raw, as a normalized row (the Find-PsaTickets shape).
#   -AssumeStatus  the status name to use when the record only has a status id that can't be named (HaloPSA)
#   -AssumeClosed  treat the record as closed when it doesn't say (HaloPSA closed_only lists)
function ConvertTo-PsaTicketRow {
    param($Raw, [string]$AssumeStatus = '', [switch]$AssumeClosed)
    $c = Get-PsaConn
    $t = $Raw
    $F = @{ raw = $t }
    switch ($c.Psa) {
        'connectwise' {
            $F += @{ id = (Get-PsaProp $t 'id'); summary = (Get-PsaProp $t 'summary'); description = (Get-PsaProp $t 'initialDescription')
                status = (Get-PsaPath $t 'status.name'); isClosed = ((Get-PsaProp $t 'closedFlag') -eq $true)
                companyId = (Get-PsaPath $t 'company.id'); companyName = (Get-PsaPath $t 'company.name')
                contactId = (Get-PsaPath $t 'contact.id'); contactName = (Get-PsaFirst $t @('contactName', 'contact.name')); contactEmail = (Get-PsaProp $t 'contactEmailAddress')
                assigneeId = (Get-PsaFirst $t @('owner.identifier', 'owner.id')); assigneeName = (Get-PsaPath $t 'owner.name')
                queueId = (Get-PsaPath $t 'board.id'); queueName = (Get-PsaPath $t 'board.name'); priority = (Get-PsaPath $t 'priority.name')
                created = (Get-PsaFirst $t @('dateEntered', '_info.dateEntered')); updated = (Get-PsaFirst $t @('_info.lastUpdated', 'lastUpdated')); closed = (Get-PsaProp $t 'closedDate')
                ticketType = (Get-PsaPath $t 'type.name') }
        }
        'autotask' {
            # Status, priority, queue and ticket type are per-tenant picklists (read once, cached), shown by label.
            $complete = @(Get-PsaAtCompleteStatuses)
            $label = { param([string]$Field, $x) if (Test-PsaBlank $x) { return '' }; $h = @(Get-PsaAtPicklist 'Tickets' $Field | Where-Object { [string](Get-PsaProp $_ 'value') -eq [string]$x }) | Select-Object -First 1; if ($h) { return [string](Get-PsaProp $h 'label') }; return [string]$x }
            $st = Get-PsaProp $t 'status'; $q = Get-PsaProp $t 'queueID'
            $F += @{ id = (Get-PsaProp $t 'id'); number = (Get-PsaProp $t 'ticketNumber'); summary = (Get-PsaProp $t 'title'); description = (Get-PsaProp $t 'description')
                status = (& $label 'status' $st); isClosed = ((-not (Test-PsaBlank $st)) -and $complete -contains [int]$st)
                companyId = (Get-PsaProp $t 'companyID'); contactId = (Get-PsaProp $t 'contactID')
                assigneeId = (Get-PsaProp $t 'assignedResourceID'); queueId = $q; queueName = (& $label 'queueID' $q); priority = (& $label 'priority' (Get-PsaProp $t 'priority'))
                created = (Get-PsaProp $t 'createDate'); updated = (Get-PsaProp $t 'lastActivityDate'); closed = (Get-PsaFirst $t @('completedDate', 'resolvedDateTime'))
                ticketType = (& $label 'ticketType' (Get-PsaProp $t 'ticketType')); configIds = @(Get-PsaProp $t 'configurationItemID') }
        }
        'halopsa' {
            # Unverified: the list row field names (HaloAPI module). A status id is named from the cached status list.
            # isClosed counts a datecleared as closed; closedByStatus (for -OpenByStatus) uses hasbeenclosed and the
            # status name only. Unverified: whether hasbeenclosed stays set after a ticket is reopened.
            $sname = [string](Get-PsaProp $t 'status_name'); $sid = [string](Get-PsaProp $t 'status_id')
            if (-not $sname -and $sid) {
                $list = @(); try { $list = @(Get-PsaStatusList) } catch { $PsaState.Statuses = @() }
                $hit = @($list | Where-Object { $_.id -eq $sid }) | Select-Object -First 1
                $sname = if ($hit) { $hit.name } elseif ($AssumeStatus) { $AssumeStatus } else { "Status $sid" }
            }
            $pid0 = [string](Get-PsaProp $t 'priority_id')
            $plabel = [string](Get-PsaProp $t 'priority_name')
            # Unverified: Halo's out-of-box priority ids 1 to 4 are Critical to Low.
            if (-not $plabel -and $pid0) { $plabel = switch ($pid0) { '1' { 'Critical' } '2' { 'High' } '3' { 'Medium' } '4' { 'Low' } default { "P$pid0" } } }
            $cl = Get-PsaFirst $t @('datecleared', 'dateclosed')
            $upd = Get-PsaProp $t 'lastactiondate'; if (-not (ConvertTo-PsaDate $upd)) { $upd = Get-PsaProp $t 'last_update' }
            $F += @{ id = (Get-PsaProp $t 'id'); summary = (Get-PsaProp $t 'summary'); description = (Get-PsaProp $t 'details'); status = $sname
                isClosed = (((Get-PsaProp $t 'hasbeenclosed') -eq $true) -or ($null -ne (ConvertTo-PsaDate $cl)) -or [bool]$AssumeClosed)
                closedByStatus = (((Get-PsaProp $t 'hasbeenclosed') -eq $true) -or $sname -match '(?i)\b(closed|resolved|completed?|cancell?ed)\b' -or [bool]$AssumeClosed)
                companyId = (Get-PsaProp $t 'client_id'); companyName = (Get-PsaProp $t 'client_name')
                contactId = (Get-PsaProp $t 'user_id'); contactName = (Get-PsaProp $t 'user_name'); contactEmail = (Get-PsaFirst $t @('user_email', 'emailaddress'))
                assigneeId = (Get-PsaProp $t 'agent_id'); assigneeName = (Get-PsaProp $t 'agent_name'); queueId = (Get-PsaProp $t 'team_id'); queueName = (Get-PsaProp $t 'team'); priority = $plabel
                created = (Get-PsaProp $t 'dateoccurred'); updated = $upd; closed = $cl; ticketType = (Get-PsaProp $t 'tickettype_id')
                configIds = @(Get-PsaProp $t 'assets' | Where-Object { $null -ne $_ } | ForEach-Object { Get-PsaProp $_ 'id' }) }
        }
        'kaseyabms' {
            # Unverified: the list row field names. Closed is read from CompletedDate or the status name;
            # closedByStatus (for -OpenByStatus) from the status name only.
            $sname = [string](Get-PsaProp $t 'StatusName'); $cd = Get-PsaProp $t 'CompletedDate'
            $F += @{ id = (Get-PsaProp $t 'Id'); number = (Get-PsaProp $t 'TicketNumber'); summary = (Get-PsaProp $t 'Title'); description = (Get-PsaProp $t 'Details')
                status = $sname; isClosed = (($null -ne (ConvertTo-PsaDate $cd)) -or $sname -match '(?i)complete|closed|resolved|cancel')
                closedByStatus = ($sname -match '(?i)complete|closed|resolved|cancel')
                companyId = (Get-PsaProp $t 'AccountId'); companyName = (Get-PsaProp $t 'AccountName')
                contactId = (Get-PsaProp $t 'ContactId'); contactName = (Get-PsaProp $t 'ContactName'); contactEmail = (Get-PsaProp $t 'ContactEmail')
                assigneeId = (Get-PsaProp $t 'AssigneeId'); assigneeName = (Get-PsaProp $t 'AssigneeName'); queueId = (Get-PsaProp $t 'QueueId'); queueName = (Get-PsaProp $t 'QueueName'); priority = (Get-PsaProp $t 'PriorityName')
                created = (Get-PsaFirst $t @('OpenDate', 'CreatedOn')); updated = (Get-PsaFirst $t @('LastActivityUpdate', 'LastModifiedDate', 'ModifiedOn', 'UpdatedOn')); closed = $cd
                statusChanged = (Get-PsaProp $t 'LastStatusUpdate'); ticketType = (Get-PsaProp $t 'TypeName'); configIds = @(Get-PsaProp $t 'AssetId') }
        }
        'syncro' {
            # Unverified: customer_business_then_name, contact_fullname, resolved_at and user.full_name on list rows.
            $st = [string](Get-PsaProp $t 'status')
            $cm = @(Get-PsaProp $t 'comments' | Where-Object { $null -ne $_ })
            $F += @{ id = (Get-PsaProp $t 'id'); number = (Get-PsaProp $t 'number'); summary = (Get-PsaProp $t 'subject'); description = $(if ($cm.Count) { Get-PsaProp $cm[0] 'body' } else { '' })
                status = $st; isClosed = ($st -match '(?i)^(resolved|closed)$')
                companyId = (Get-PsaProp $t 'customer_id'); companyName = (Get-PsaProp $t 'customer_business_then_name')
                contactId = (Get-PsaProp $t 'contact_id'); contactName = (Get-PsaProp $t 'contact_fullname'); contactEmail = (Get-PsaPath $t 'contact.email')
                assigneeId = (Get-PsaProp $t 'user_id'); assigneeName = (Get-PsaPath $t 'user.full_name'); queueName = (Get-PsaProp $t 'problem_type'); priority = (Get-PsaProp $t 'priority')
                created = (Get-PsaProp $t 'created_at'); updated = (Get-PsaProp $t 'updated_at'); closed = (Get-PsaProp $t 'resolved_at'); ticketType = (Get-PsaProp $t 'problem_type') }
        }
        'zendesk' {
            $st = [string](Get-PsaProp $t 'status')
            $F += @{ id = (Get-PsaProp $t 'id'); summary = (Get-PsaProp $t 'subject'); description = (Get-PsaProp $t 'description'); status = $st; isClosed = ($st -in @('solved', 'closed'))
                companyId = (Get-PsaProp $t 'organization_id'); contactId = (Get-PsaProp $t 'requester_id'); assigneeId = (Get-PsaProp $t 'assignee_id'); queueId = (Get-PsaProp $t 'group_id'); priority = (Get-PsaProp $t 'priority')
                created = (Get-PsaProp $t 'created_at'); updated = (Get-PsaProp $t 'updated_at'); ticketType = (Get-PsaProp $t 'type') }
        }
    }
    return (New-PsaTicketRow $F)
}

# Lists tickets. Every filter is sent to the PSA where it can take it, and every row is checked again here,
# so a filter the PSA ignores (or that isn't verified yet) never lets the wrong ticket through.
#   -Status <names>      exact status names, case-insensitive (alias -StatusName). Several are allowed.
#   -Open / -Closed      only tickets that aren't closed / are closed. Neither means both. A closed date counts
#                        as closed on HaloPSA and Kaseya BMS even when the status is open.
#   -OpenByStatus        like -Open, but "open" is decided by the PSA's status or closed flag only, never by a
#                        closed date, so an open ticket that wrongly carries a closed date is kept (the
#                        psa-hygiene check). Only differs from -Open on HaloPSA and Kaseya BMS; on Kaseya BMS
#                        Filter.ExcludeCompleted isn't sent, so completed rows are read and dropped here.
#   -CompanyId <id>      only this PSA company id (numeric). Rows for any other company, or with no company,
#                        are always dropped here, so one client's run never sees another client's ticket.
#   -CreatedAfter/-CreatedBefore, -UpdatedAfter/-UpdatedBefore, -ClosedAfter/-ClosedBefore
#                        [datetime] or text, UTC. After is inclusive (>=), Before is exclusive (<).
#   -Text <words>        summary text (the PSA's own search where it has one).
#   -Max <n>             at most n rows (default 500). $PsaState.FindTruncated is $true when there were more.
#   -Order oldest|newest by created date (default oldest).
#   -IncludeSla          Zendesk only: sideload SLA policy metrics so Get-PsaTicketSla needs no extra call.
# Returns @(@{ id; number; summary; description; status; isClosed; companyId; companyName; contactId; contactName;
#   contactEmail; assigneeId; assigneeName; queue; queueId; queueName; priority; priorityLevel; created; updated;
#   closed; statusChanged; ticketType; configIds; url; raw; closedByStatus; closedDateSet }). closedByStatus is the
#   status or closed flag alone; closedDateSet is $true when the row carries a closed date. priority is the PSA's own label; priorityLevel is
#   critical, high, medium, low or ''. created, updated (falls back to created), closed and statusChanged are UTC
#   [datetime] or $null. Names a PSA leaves out of list rows are '' (Resolve-PsaTicketNames fills them).
function Find-PsaTickets {
    param(
        [Alias('StatusName')][string[]]$Status = @(), [switch]$Open, [switch]$OpenByStatus, [switch]$Closed, [string]$CompanyId = '',
        $CreatedAfter = $null, $CreatedBefore = $null, $UpdatedAfter = $null, $UpdatedBefore = $null, $ClosedAfter = $null, $ClosedBefore = $null,
        [string]$Text = '', [int]$Max = 500, [ValidateSet('oldest', 'newest')][string]$Order = 'oldest', [switch]$IncludeSla
    )
    $c = Get-PsaConn
    $PsaState.FindTruncated = $false
    if (($Open -or $OpenByStatus) -and $Closed) { throw 'Find-PsaTickets takes -Open (or -OpenByStatus) or -Closed, not both.' }
    $byStatus = [bool]$OpenByStatus
    $wantOpen = [bool]($Open -or $OpenByStatus)
    if ($Max -lt 1) { $Max = 1 }
    $co = ([string]$CompanyId).Trim(); if ($co.StartsWith('@')) { $co = '' }
    if ($co -and $co -notmatch '^\d+$') { throw "Find-PsaTickets needs a numeric PSA company id, not '$co'. Use Resolve-PsaCompanyId or Find-PsaCompany to look a name up." }
    $names = @($Status | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { ([string]$_).Trim() })
    $want = @($names | ForEach-Object { $_.ToLowerInvariant() })
    $txt = ([string]$Text).Trim()
    $bd = @{ ca = (ConvertTo-PsaDate $CreatedAfter); cb = (ConvertTo-PsaDate $CreatedBefore); ua = (ConvertTo-PsaDate $UpdatedAfter); ub = (ConvertTo-PsaDate $UpdatedBefore); xa = (ConvertTo-PsaDate $ClosedAfter); xb = (ConvertTo-PsaDate $ClosedBefore) }
    $iso = @{}; foreach ($k in @($bd.Keys)) { $iso[$k] = $(if ($bd[$k]) { Format-PsaDate $bd[$k] } else { '' }) }
    $hasClosedRange = [bool]($bd.xa -or $bd.xb)
    # Filters the PSA applied itself: a row with no date for that field is then trusted rather than dropped.
    $server = @{ created = $false; updated = $false; closed = $false; text = $false }
    $newest = $Order -eq 'newest'
    $what = 'list tickets'
    $rows = New-Object System.Collections.ArrayList
    $keep = {
        param($r)
        if ($co -and $r.companyId -ne $co) { return $false }
        if ($want.Count -and $want -notcontains $r.status.Trim().ToLowerInvariant()) { return $false }
        if ($byStatus) { if ($r.closedByStatus) { return $false } }
        elseif ($Open -and $r.isClosed) { return $false }
        if ($Closed -and -not $r.isClosed) { return $false }
        foreach ($k in @(@('created', 'ca', 'cb'), @('updated', 'ua', 'ub'), @('closed', 'xa', 'xb'))) {
            $lo = $bd[$k[1]]; $hi = $bd[$k[2]]
            if (-not $lo -and -not $hi) { continue }
            $d = $r[$k[0]]
            if ($null -eq $d) { if ($server[$k[0]]) { continue }; return $false }
            if ($lo -and $d -lt $lo) { return $false }
            if ($hi -and $d -ge $hi) { return $false }
        }
        if ($txt -and -not $server.text -and "$($r.summary) $($r.description)".IndexOf($txt, [StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
        return $true
    }
    $assume = if ($names.Count -eq 1) { $names[0] } else { '' }
    $add = { param($raw) $row = ConvertTo-PsaTicketRow $raw -AssumeStatus $assume -AssumeClosed:$Closed; if (& $keep $row) { $null = $rows.Add($row) } }
    $enough = { return ($rows.Count -gt $Max) }
    $morePages = $false
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: the dateEntered, lastUpdated and closedDate conditions with [date] literals, and
            # "summary contains". closedFlag, company/id and status/name follow the CW conditions syntax.
            $esc = { param($x) ([string]$x).Replace('\', '\\').Replace('"', '\"') }
            $conds = @()
            if ($wantOpen) { $conds += 'closedFlag=false' } elseif ($Closed) { $conds += 'closedFlag=true' }
            if ($co) { $conds += "company/id=$co" }
            if ($names.Count -eq 1) { $conds += ('status/name="' + (& $esc $names[0]) + '"') }
            elseif ($names.Count -gt 1) { $conds += ('(' + (@($names | ForEach-Object { 'status/name="' + (& $esc $_) + '"' }) -join ' or ') + ')') }
            foreach ($pair in @(@('ca', 'dateEntered>=', 'created'), @('cb', 'dateEntered<', 'created'), @('ua', 'lastUpdated>=', 'updated'), @('ub', 'lastUpdated<', 'updated'), @('xa', 'closedDate>=', 'closed'), @('xb', 'closedDate<', 'closed'))) {
                if ($iso[$pair[0]]) { $conds += "$($pair[1])[$($iso[$pair[0]])]"; $server[$pair[2]] = $true }
            }
            if ($txt) { $conds += ('summary contains "' + (& $esc $txt) + '"'); $server.text = $true }
            $cq = if ($conds.Count) { "conditions=$(ConvertTo-PsaQuery ($conds -join ' and '))&" } else { '' }
            $ob = ConvertTo-PsaQuery $(if ($newest) { 'id desc' } else { 'id asc' })
            for ($p = 1; $p -le $PsaState.MaxPages; $p++) {
                $page = @(Invoke-PsaRead "/service/tickets?$($cq)orderBy=$ob&pageSize=100&page=$p" $what | Where-Object { $null -ne $_ })
                foreach ($t in $page) { & $add $t }
                if ($page.Count -lt 100) { break }
                if (& $enough) { break }
                if ($p -eq $PsaState.MaxPages) { $morePages = $true }
            }
        }
        'autotask' {
            # Status, priority and queue are per-tenant picklists, matched on the label. Unverified: lastActivityDate
            # as "updated", completedDate as "closed", the "in" operator, and "contains" on title.
            $complete = @(Get-PsaAtCompleteStatuses)
            $f = @()
            if ($wantOpen) { foreach ($v in $complete) { $f += [ordered]@{ op = 'noteq'; field = 'status'; value = $v } } }
            elseif ($Closed -and -not $hasClosedRange -and -not $names.Count) { $f += [ordered]@{ op = 'in'; field = 'status'; value = @($complete) } }
            if ($names.Count -eq 1) { $f += [ordered]@{ op = 'eq'; field = 'status'; value = [int](Get-PsaStatusId $names[0]) } }
            elseif ($names.Count -gt 1) { $f += [ordered]@{ op = 'in'; field = 'status'; value = @($names | ForEach-Object { [int](Get-PsaStatusId $_) }) } }
            if ($co) { $f += [ordered]@{ op = 'eq'; field = 'companyID'; value = [long]$co } }
            foreach ($pair in @(@('ca', 'gte', 'createDate', 'created'), @('cb', 'lt', 'createDate', 'created'), @('ua', 'gte', 'lastActivityDate', 'updated'), @('ub', 'lt', 'lastActivityDate', 'updated'), @('xa', 'gte', 'completedDate', 'closed'), @('xb', 'lt', 'completedDate', 'closed'))) {
                if ($iso[$pair[0]]) { $f += [ordered]@{ op = $pair[1]; field = $pair[2]; value = $iso[$pair[0]] }; $server[$pair[3]] = $true }
            }
            if ($txt) { $f += [ordered]@{ op = 'contains'; field = 'title'; value = $txt }; $server.text = $true }
            if (-not $f.Count) { $f += [ordered]@{ op = 'gt'; field = 'id'; value = 0 } }
            $path = "/Tickets/query?search=$(ConvertTo-PsaQuery (@{ filter = $f; MaxRecords = 500 } | ConvertTo-Json -Depth 6 -Compress))"
            for ($p = 1; $p -le $PsaState.MaxPages -and $path; $p++) {
                $r = Invoke-PsaRead $path $what
                foreach ($t in @(Get-PsaProp $r 'items' | Where-Object { $null -ne $_ })) { & $add $t }
                $path = [string](Get-PsaPath $r 'pageDetails.nextPageUrl')
                if (& $enough) { break }
                if ($p -eq $PsaState.MaxPages -and $path) { $morePages = $true }
            }
        }
        'halopsa' {
            # Unverified: open_only, closed_only, status_id, client_id, search, the datesearch/startdate/enddate filters
            # (one date field per request), order/orderdesc, and the list row field names (HaloAPI module).
            $q = @()
            if ($wantOpen) { $q += 'open_only=true' } elseif ($Closed) { $q += 'closed_only=true' }
            if ($names.Count -eq 1) { $q += "status_id=$(Get-PsaStatusId $names[0])" }
            if ($co) { $q += "client_id=$co" }
            if ($hasClosedRange) { $q += 'datesearch=datecleared'; if ($iso.xa) { $q += "startdate=$(ConvertTo-PsaQuery $iso.xa)" }; if ($iso.xb) { $q += "enddate=$(ConvertTo-PsaQuery $iso.xb)" }; $server.closed = $true }
            elseif ($bd.ca -or $bd.cb) { $q += 'datesearch=dateoccurred'; if ($iso.ca) { $q += "startdate=$(ConvertTo-PsaQuery $iso.ca)" }; if ($iso.cb) { $q += "enddate=$(ConvertTo-PsaQuery $iso.cb)" }; $server.created = $true }
            if ($txt) { $q += "search=$(ConvertTo-PsaQuery $txt)"; $server.text = $true }
            $q += $(if ($newest) { 'order=id&orderdesc=true' } else { 'order=id' })
            for ($p = 1; $p -le $PsaState.MaxPages; $p++) {
                $r = Invoke-PsaRead "/Tickets?$($q -join '&')&pageinate=true&page_size=100&page_no=$p" $what
                $page = @(Get-PsaProp $r 'tickets' | Where-Object { $null -ne $_ })
                foreach ($t in $page) { & $add $t }
                $total = Get-PsaProp $r 'record_count'
                if ($page.Count -lt 100 -or ($null -ne $total -and $p * 100 -ge [int]$total)) { break }
                if (& $enough) { break }
                if ($p -eq $PsaState.MaxPages) { $morePages = $true }
            }
        }
        'kaseyabms' {
            # Vendor docs (BMS swagger): Filter.StatusNames, Filter.AccountIds, Filter.ExcludeCompleted, Filter.OpenDateFrom/To,
            # Filter.LastActivityUpdateFrom/To, Filter.CompletedDateFrom/To, PageSize, PageNumber and TotalRecords.
            # Unverified live: the date format, whether the To dates are inclusive, whether StatusNames is exact,
            # and the list field names. There is no text filter, so text is matched here.
            $q = @()
            if ($Open -and -not $byStatus) { $q += 'Filter.ExcludeCompleted=1' }
            foreach ($n in $names) { $q += "Filter.StatusNames=$(ConvertTo-PsaQuery $n)" }
            if ($co) { $q += "Filter.AccountIds=$co" }
            foreach ($pair in @(@('ca', 'Filter.OpenDateFrom', 'created'), @('cb', 'Filter.OpenDateTo', 'created'), @('ua', 'Filter.LastActivityUpdateFrom', 'updated'), @('ub', 'Filter.LastActivityUpdateTo', 'updated'), @('xa', 'Filter.CompletedDateFrom', 'closed'), @('xb', 'Filter.CompletedDateTo', 'closed'))) {
                if ($iso[$pair[0]]) { $q += "$($pair[1])=$(ConvertTo-PsaQuery $iso[$pair[0]])"; $server[$pair[2]] = $true }
            }
            $qs = if ($q.Count) { ($q -join '&') + '&' } else { '' }
            for ($p = 1; $p -le $PsaState.MaxPages; $p++) {
                $r = Invoke-PsaRead "/servicedesk/tickets?$($qs)PageSize=100&PageNumber=$p" $what
                $page = @(Get-PsaBmsList $r)
                foreach ($t in $page) { & $add $t }
                $total = [int](Get-PsaNumber (Get-PsaProp $r 'TotalRecords'))
                if ($page.Count -lt 100 -or ($total -gt 0 -and $p * 100 -ge $total)) { break }
                if (& $enough) { break }
                if ($p -eq $PsaState.MaxPages) { $morePages = $true }
            }
        }
        'syncro' {
            # Vendor docs (Syncro swagger): status (a label, or "Not Closed"), customer_id, created_after, since_updated_at,
            # resolved_after (a date), 25 per page with meta.total_pages. Unverified: query= as the text search, and that
            # Resolved is the only closed status. Before-dates are checked here.
            $q = @()
            if ($names.Count -eq 1) { $q += "status=$(ConvertTo-PsaQuery $names[0])" }
            elseif ($wantOpen) { $q += "status=$(ConvertTo-PsaQuery 'Not Closed')" }
            elseif ($Closed -and -not $bd.xa) { $q += 'status=Resolved' }
            if ($co) { $q += "customer_id=$co" }
            if ($iso.ca) { $q += "created_after=$(ConvertTo-PsaQuery $iso.ca)" }
            if ($iso.ua) { $q += "since_updated_at=$(ConvertTo-PsaQuery $iso.ua)" }
            if ($bd.xa) { $q += "resolved_after=$($bd.xa.AddDays(-1).ToString('yyyy-MM-dd'))" }
            if ($txt) { $q += "query=$(ConvertTo-PsaQuery $txt)"; $server.text = $true }
            $qs = if ($q.Count) { ($q -join '&') + '&' } else { '' }
            for ($p = 1; $p -le $PsaState.MaxPages; $p++) {
                $r = Invoke-PsaRead "/tickets?$($qs)page=$p" $what
                foreach ($t in @(Get-PsaProp $r 'tickets' | Where-Object { $null -ne $_ })) { & $add $t }
                $pages = Get-PsaPath $r 'meta.total_pages'
                if ($null -eq $pages -or $p -ge [int]$pages) { break }
                if (& $enough) { break }
                if ($p -eq $PsaState.MaxPages) { $morePages = $true }
            }
        }
        'zendesk' {
            # Vendor docs: search with type:ticket, status<solved / status>=solved, status:<name>, created and updated
            # with ISO times. Unverified: organization:<id>, solved>= / solved< and the tickets(slas) sideload on search.
            # Search returns at most 1,000 results (10 pages). A ticket has no solved date of its own, so closed is $null.
            $sq = 'type:ticket'
            if ($wantOpen) { $sq += ' status<solved' } elseif ($Closed) { $sq += ' status>=solved' }
            if ($names.Count -eq 1) { $sq += " status:$($names[0].ToLowerInvariant())" }
            if ($co) { $sq += " organization:$co" }
            foreach ($pair in @(@('ca', 'created>=', 'created'), @('cb', 'created<', 'created'), @('ua', 'updated>=', 'updated'), @('ub', 'updated<', 'updated'), @('xa', 'solved>=', 'closed'), @('xb', 'solved<', 'closed'))) {
                if ($iso[$pair[0]]) { $sq += " $($pair[1])$($iso[$pair[0]])"; $server[$pair[2]] = $true }
            }
            if ($txt) { $sq += ' "' + $txt.Replace('"', '') + '"'; $server.text = $true }
            $path = "/search?query=$(ConvertTo-PsaQuery $sq)&sort_by=created_at&sort_order=$(if ($newest) { 'desc' } else { 'asc' })&per_page=100"
            if ($IncludeSla) { $path += "&include=$(ConvertTo-PsaQuery 'tickets(slas)')" }
            for ($p = 1; $p -le [Math]::Min(10, $PsaState.MaxPages) -and $path; $p++) {
                $r = Invoke-PsaRead $path $what
                foreach ($t in @(Get-PsaProp $r 'results' | Where-Object { $null -ne $_ })) { & $add $t }
                $path = [string](Get-PsaProp $r 'next_page')
                if (& $enough) { break }
            }
            if ($path -and -not (& $enough)) { $morePages = $true }
        }
    }
    $sortKey = @{ Expression = { if ($null -ne $_.created) { $_.created } else { [datetime]::MinValue } }; Descending = $newest }
    $idKey = @{ Expression = { [long](Get-PsaNumber $_.id) }; Descending = $newest }
    $sorted = @($rows | Sort-Object -Property $sortKey, $idKey)
    if ($sorted.Count -gt $Max -or $morePages) { $PsaState.FindTruncated = $true }
    return @($sorted | Select-Object -First $Max)
}

# Fills blank companyName, assigneeName and queueName (and queue) on Find-PsaTickets rows, one lookup per id,
# cached for the run. A failed lookup leaves a plain fallback ("Company 42", "Technician 7", "Unassigned").
function Resolve-PsaTicketNames {
    param($Tickets)
    $c = Get-PsaConn
    $cache = $PsaState.Lookups
    $list = @($Tickets | Where-Object { $null -ne $_ })
    if ($c.Psa -eq 'autotask') {
        # Company names in batches of 200 first. Unverified: the "in" operator on Companies.
        $ids = @($list | Where-Object { $_.companyId -and -not $_.companyName } | ForEach-Object { [string]$_.companyId } | Where-Object { -not $cache.ContainsKey("company:$_") } | Sort-Object -Unique)
        for ($i = 0; $i -lt $ids.Count; $i += 200) {
            $chunk = @($ids | Select-Object -Skip $i -First 200 | ForEach-Object { [long]$_ })
            try { foreach ($co in @(Invoke-PsaAtQuery 'Companies' @([ordered]@{ op = 'in'; field = 'id'; value = $chunk }) @('id', 'companyName') 500)) { $cache["company:$(Get-PsaProp $co 'id')"] = [string](Get-PsaProp $co 'companyName') } } catch { }
        }
    }
    $look = {
        param([string]$Kind, [string]$Id)
        if (Test-PsaBlank $Id) { return '' }
        $key = "$Kind`:$Id"
        if ($cache.ContainsKey($key)) { return $cache[$key] }
        $name = ''
        try {
            switch ("$($c.Psa)/$Kind") {
                'autotask/company' { $name = [string](Get-PsaPath (Invoke-Psa GET "/Companies/$Id") 'item.companyName') }
                'autotask/user' { $i = Get-PsaProp (Invoke-Psa GET "/Resources/$Id") 'item'; $name = ("$(Get-PsaProp $i 'firstName') $(Get-PsaProp $i 'lastName')").Trim() }
                'halopsa/user' { $name = [string](Get-PsaProp (Invoke-Psa GET "/Agent/$Id") 'name') }        # Unverified
                'syncro/user' { $name = [string](Get-PsaPath (Invoke-Psa GET "/users/$Id") 'user.full_name') }  # Unverified: the field name
                'zendesk/company' { $name = [string](Get-PsaPath (Invoke-Psa GET "/organizations/$Id") 'organization.name') }
                'zendesk/user' { $name = [string](Get-PsaPath (Invoke-Psa GET "/users/$Id") 'user.name') }
                'zendesk/queue' { $name = [string](Get-PsaPath (Invoke-Psa GET "/groups/$Id") 'group.name') }
            }
        }
        catch { $name = '' }
        $cache[$key] = $name
        return $name
    }
    foreach ($t in $list) {
        if (-not $t.companyName) { $t.companyName = & $look 'company' $t.companyId; if (-not $t.companyName) { $t.companyName = $(if ($t.companyId) { "Company $($t.companyId)" } else { 'No company' }) } }
        if (-not $t.assigneeName) { $t.assigneeName = & $look 'user' $t.assigneeId; if (-not $t.assigneeName) { $t.assigneeName = $(if ($t.assigneeId) { "Technician $($t.assigneeId)" } else { 'Unassigned' }) } }
        if (-not $t.queueName -and $t.queueId) { $t.queueName = & $look 'queue' $t.queueId; if (-not $t.queueName) { $t.queueName = "Queue $($t.queueId)" } }
        if ($t -is [System.Collections.IDictionary] -and $t.Contains('queue') -and $t.queueName) { $t.queue = $t.queueName }
    }
}

# ConnectWise SLA hours for one SLA and priority, cached. Unverified: /service/SLAs/{id} and its /priorities
# (respondHours, resolutionHours). Wall-clock hours: CW applies business hours, so treat the result as approximate.
function Get-PsaCwSlaHours {
    param([string]$SlaId, [string]$PriorityId)
    $key = "cw:$SlaId"
    if (-not $PsaState.Sla.ContainsKey($key)) {
        $base = Invoke-Psa GET "/service/SLAs/$SlaId"
        $prios = @(); try { $prios = @(Invoke-Psa GET "/service/SLAs/$SlaId/priorities?pageSize=100" | Where-Object { $null -ne $_ }) } catch { }
        $PsaState.Sla[$key] = @{ base = $base; prios = $prios }
    }
    $d = $PsaState.Sla[$key]
    $src = $d.base
    if ($PriorityId) { $hit = @($d.prios | Where-Object { [string](Get-PsaPath $_ 'priority.id') -eq $PriorityId }) | Select-Object -First 1; if ($hit) { $src = $hit } }
    $num = { param($o, $n) $v = Get-PsaProp $o $n; if (Test-PsaBlank $v) { $null } else { [double]$v } }
    return @{ respond = (& $num $src 'respondHours'); resolve = (& $num $src 'resolutionHours') }
}

# The PSA's own SLA target for a Find-PsaTickets row:
#   @{ source ('psa' or 'none'); kind ('respond', 'resolve' or 'due'); start; target; breached ($true when the
#   PSA itself says the SLA was missed, else $null); detail }. source 'psa' with no target means the PSA's SLA
#   clock is paused or already met.
function Get-PsaTicketSla {
    param($Ticket)
    $c = Get-PsaConn
    $raw = $Ticket.raw
    $none = @{ source = 'none'; kind = ''; start = $Ticket.created; target = $null; breached = $null; detail = '' }
    $mk = { param($kind, $target, $breached, $detail) @{ source = 'psa'; kind = $kind; start = $Ticket.created; target = $target; breached = $breached; detail = $detail } }
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: dateResponded, isInSla and sla.id on the ticket; see Get-PsaCwSlaHours for the hours.
            $slaId = [string](Get-PsaPath $raw 'sla.id')
            $flag = if ((Get-PsaProp $raw 'isInSla') -eq $false) { $true } else { $null }
            if ((Test-PsaBlank $slaId) -or $null -eq $Ticket.created) { if ($flag) { return (& $mk 'resolve' $null $true 'ConnectWise marks this ticket as out of SLA.') }; return $none }
            $h = $null; try { $h = Get-PsaCwSlaHours $slaId ([string](Get-PsaPath $raw 'priority.id')) } catch { $h = $null }
            if ($null -eq $h) { return $none }
            $responded = ConvertTo-PsaDate (Get-PsaProp $raw 'dateResponded')
            if (-not $responded -and $null -ne $h.respond) { return (& $mk 'respond' $Ticket.created.AddHours($h.respond) $flag "ConnectWise SLA: respond within $($h.respond) hours") }
            if ($null -ne $h.resolve) { return (& $mk 'resolve' $Ticket.created.AddHours($h.resolve) $flag "ConnectWise SLA: resolve within $($h.resolve) hours") }
            return $none
        }
        'autotask' {
            # Unverified: firstResponseDueDateTime, firstResponseDateTime, resolvedDueDateTime, serviceLevelAgreementHasBeenMet.
            $flag = if ((Get-PsaProp $raw 'serviceLevelAgreementHasBeenMet') -eq $false) { $true } else { $null }
            $fr = ConvertTo-PsaDate (Get-PsaProp $raw 'firstResponseDateTime'); $frDue = ConvertTo-PsaDate (Get-PsaProp $raw 'firstResponseDueDateTime')
            $resDue = ConvertTo-PsaDate (Get-PsaProp $raw 'resolvedDueDateTime'); $due = ConvertTo-PsaDate (Get-PsaProp $raw 'dueDateTime')
            if (-not $fr -and $frDue) { return (& $mk 'respond' $frDue $flag 'Autotask first response due date') }
            if ($resDue) { return (& $mk 'resolve' $resDue $flag 'Autotask resolution due date') }
            if ($due) { return (& $mk 'due' $due $flag 'Autotask ticket due date') }
            return $none
        }
        'halopsa' {
            # Unverified: respondbydate, responsedate and fixbydate (1900-01-01 means none).
            $responded = ConvertTo-PsaDate (Get-PsaProp $raw 'responsedate'); $respondBy = ConvertTo-PsaDate (Get-PsaProp $raw 'respondbydate'); $fixBy = ConvertTo-PsaDate (Get-PsaProp $raw 'fixbydate')
            if (-not $responded -and $respondBy) { return (& $mk 'respond' $respondBy $null 'HaloPSA respond-by date') }
            if ($fixBy) { return (& $mk 'resolve' $fixBy $null 'HaloPSA fix-by date') }
            return $none
        }
        'kaseyabms' {
            # Unverified: the due-date field names.
            foreach ($n in @('ResponseDueDate', 'ResolutionDueDate', 'DueDate')) { $d = ConvertTo-PsaDate (Get-PsaProp $raw $n); if ($d) { return (& $mk $(if ($n -eq 'ResponseDueDate') { 'respond' } elseif ($n -eq 'DueDate') { 'due' } else { 'resolve' }) $d $null "Kaseya BMS $n") } }
            return $none
        }
        'syncro' {
            # Unverified: due_date on the ticket.
            $d = ConvertTo-PsaDate (Get-PsaProp $raw 'due_date'); if ($d) { return (& $mk 'due' $d $null 'Syncro due date') }
            return $none
        }
        'zendesk' {
            # Unverified: SLA policy metrics (slas.policy_metrics with metric, stage, breach_at). Needs a plan with SLA policies.
            $slas = Get-PsaProp $raw 'slas'
            if ($null -eq $slas) { try { $slas = Get-PsaPath (Invoke-Psa GET "/tickets/$($Ticket.id)?include=slas") 'ticket.slas' } catch { $slas = $null } }
            $metrics = @(Get-PsaProp $slas 'policy_metrics' | Where-Object { $null -ne $_ })
            if (-not $metrics.Count) { return $none }
            $active = @($metrics | Where-Object { [string](Get-PsaProp $_ 'stage') -eq 'active' -and (ConvertTo-PsaDate (Get-PsaProp $_ 'breach_at')) } | Sort-Object { ConvertTo-PsaDate (Get-PsaProp $_ 'breach_at') })
            if (-not $active.Count) { return (& $mk '' $null $null 'Zendesk SLA is paused or already met') }
            $m = $active[0]; $metric = [string](Get-PsaProp $m 'metric')
            return (& $mk $(if ($metric -match 'reply') { 'respond' } else { 'resolve' }) (ConvertTo-PsaDate (Get-PsaProp $m 'breach_at')) $null "Zendesk SLA policy ($metric)")
        }
    }
    return $none
}

# The configuration items (devices) on a ticket, as ids. Uses the row's configIds where the PSA lists them;
# ConnectWise keeps them on a sub-resource. Returns @() when there are none or the PSA can't tell.
function Get-PsaTicketDevices {
    param([string]$Id, $Row = $null)
    $c = Get-PsaConn
    if ($null -ne $Row -and @(Get-PsaProp $Row 'configIds' | Where-Object { $_ }).Count) { return @(Get-PsaProp $Row 'configIds' | Where-Object { $_ }) }
    if ($c.Psa -ne 'connectwise') { return @() }
    # Unverified: GET /service/tickets/{id}/configurations.
    try { return @(Invoke-Psa GET "/service/tickets/$Id/configurations?fields=id&pageSize=50" | Where-Object { $null -ne $_ } | ForEach-Object { [string](Get-PsaProp $_ 'id') } | Where-Object { $_ }) } catch { return @() }
}

# What the connected PSA can do with these functions. Check it before calling a function that may be unsupported.
#   relation: 'native' (always a real link), 'conditional' (a real link only when the other ticket is a Problem
#   ticket), or 'note' (cross-reference notes only).  time: $true, or 'field' for Zendesk (needs -ZendeskTimeFieldId).
function Get-PsaCapabilities {
    $c = Get-PsaConn
    switch ($c.Psa) {
        'connectwise' { return @{ tickets = $true; notes = $true; time = $true; agreements = $true; invoices = $true; primaryContact = $true; relation = 'note' } }
        'autotask' { return @{ tickets = $true; notes = $true; time = $true; agreements = $true; invoices = $true; primaryContact = $true; relation = 'conditional' } }
        'halopsa' { return @{ tickets = $true; notes = $true; time = $true; agreements = $true; invoices = $true; primaryContact = $true; relation = 'native' } }
        'kaseyabms' { return @{ tickets = $true; notes = $true; time = $true; agreements = $true; invoices = $false; primaryContact = $true; relation = 'note' } }
        'syncro' { return @{ tickets = $true; notes = $true; time = $true; agreements = $true; invoices = $false; primaryContact = $true; relation = 'note' } }
        'zendesk' { return @{ tickets = $true; notes = $true; time = 'field'; agreements = $false; invoices = $false; primaryContact = $false; relation = 'conditional' } }
    }
}

# Time entries for tickets, or (ConnectWise) for a whole company. Returns @{ supported; reason; entries; warnings }.
#   -TicketId / -TicketIds  the tickets to read (every PSA except ConnectWise with -CompanyId needs these)
#   -CompanyId              ConnectWise only: read all the company's time in one query instead of ticket by ticket
#                           (any ticket ids are then ignored); the other PSAs ignore it
#   -After / -Before        UTC bounds on the entry date (After inclusive, Before exclusive)
#   -ZendeskTimeFieldId     Zendesk has no time entries. With the Time Tracking app's "Total time spent (sec)"
#                           field id, a ticket's total becomes one entry. Without it, supported is $false.
#   -MaxTickets             PSAs read ticket by ticket stop after this many (default 50) and add a warning.
# entries: @(@{ id; ticketId; date; hours; billableHours; billable ($true, $false or $null when not set);
#   billableKnown; notes; notesKnown; member; workType; agreementId; raw }). date is UTC [datetime] or $null.
#   notesKnown and billableKnown are $false when the PSA has no such field for that entry.
function Get-PsaTimeEntries {
    param([string]$TicketId = '', [string[]]$TicketIds = @(), [string]$CompanyId = '', $After = $null, $Before = $null, [string]$ZendeskTimeFieldId = '', [int]$Max = 2000, [int]$MaxTickets = 50)
    $c = Get-PsaConn
    $from = ConvertTo-PsaDate $After; $to = ConvertTo-PsaDate $Before
    $ids = @(@($TicketId) + @($TicketIds) | Where-Object { -not (Test-PsaBlank $_) } | ForEach-Object { ([string]$_).Trim() } | Select-Object -Unique)
    $byCompany = ($c.Psa -eq 'connectwise' -and [bool]$CompanyId)
    if ($CompanyId -and $CompanyId -notmatch '^\d+$') { throw "Get-PsaTimeEntries needs a numeric company id (it was '$CompanyId')." }
    if (-not $ids.Count -and -not $byCompany) { throw 'Get-PsaTimeEntries needs -TicketId or -TicketIds (ConnectWise also takes -CompanyId).' }
    $out = New-Object System.Collections.ArrayList
    $warn = New-Object System.Collections.ArrayList
    $what = 'read time entries'; $need = 'read time entries'
    $add = {
        param([hashtable]$E)
        # Index reads: a missing key is $null (dot reads of a missing key throw in strict mode).
        $d = ConvertTo-PsaDate $E['date']
        if ($d -and (($from -and $d -lt $from) -or ($to -and $d -ge $to))) { return }
        if ($out.Count -ge $Max) { return }
        $h = [Math]::Round((Get-PsaNumber $E['hours']), 2)
        $bill = $E['billable']
        $bh = $(if ($null -ne $E['billableHours']) { [Math]::Round((Get-PsaNumber $E['billableHours']), 2) } elseif ($bill -eq $true) { $h } else { 0.0 })
        $null = $out.Add(@{ id = [string]$E['id']; ticketId = [string]$E['ticketId']; date = $d; hours = $h; billableHours = $bh; billable = $bill; billableKnown = $(if ($E.ContainsKey('billableKnown')) { [bool]$E['billableKnown'] } else { $true })
                notes = [string]$E['notes']; notesKnown = $(if ($E.ContainsKey('notesKnown')) { [bool]$E['notesKnown'] } else { $true }); member = [string]$E['member']; workType = [string]$E['workType']; agreementId = [string]$E['agreementId']; raw = $E['raw'] })
    }
    $longer = { param($a, $b) $x = ([string]$a).Trim(); $y = ([string]$b).Trim(); if ($x.Length -ge $y.Length) { $x } else { $y } }
    $loop = {
        # The PSAs that read ticket by ticket stop after MaxTickets.
        if ($ids.Count -gt $MaxTickets) { $null = $warn.Add("Time was read for the first $MaxTickets of $($ids.Count) tickets only, because $(Get-PsaName) keeps time per ticket."); return @($ids | Select-Object -First $MaxTickets) }
        return $ids
    }
    if ($c.Psa -eq 'zendesk') {
        if (-not $ZendeskTimeFieldId) { return @{ supported = $false; reason = 'Zendesk has no native time entries. Give the Time Tracking app''s "Total time spent (sec)" field id to read a ticket''s total time.'; entries = @(); warnings = @() } }
    }
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: /time/entries with company/id and timeStart, or chargeToType and chargeToId; billableOption
            # values Billable, DoNotBill, NoCharge, NoDefault.
            $one = {
                param([string]$Cond, [string]$ForTicket)
                for ($p = 1; $p -le $PsaState.MaxPages; $p++) {
                    $page = @(Invoke-PsaRead "/time/entries?conditions=$(ConvertTo-PsaQuery $Cond)&pageSize=1000&page=$p" $what $need | Where-Object { $null -ne $_ })
                    foreach ($e in $page) {
                        $bo = [string](Get-PsaProp $e 'billableOption')
                        $b = if ($bo -eq 'Billable') { $true } elseif ($bo -in @('DoNotBill', 'NoCharge')) { $false } else { $null }
                        $hrs = Get-PsaNumber (Get-PsaProp $e 'actualHours')
                        $ct = [string](Get-PsaProp $e 'chargeToType')
                        & $add @{ id = (Get-PsaProp $e 'id'); ticketId = $(if ($ForTicket) { $ForTicket } elseif ($ct -match '(?i)ticket' -or -not $ct) { [string](Get-PsaProp $e 'chargeToId') } else { '' }); date = (Get-PsaProp $e 'timeStart')
                            hours = $hrs; billableHours = $(if ($b -eq $true) { if ($null -ne (Get-PsaProp $e 'hoursBilled')) { Get-PsaNumber (Get-PsaProp $e 'hoursBilled') } else { $hrs } } else { 0.0 }); billable = $b
                            notes = (& $longer (Get-PsaProp $e 'notes') (Get-PsaProp $e 'internalNotes')); member = (Get-PsaFirst $e @('member.name', 'member.identifier')); workType = (Get-PsaPath $e 'workType.name'); agreementId = (Get-PsaPath $e 'agreement.id'); raw = $e }
                    }
                    if ($page.Count -lt 1000) { break }
                }
            }
            $dateCond = ''
            if ($from) { $dateCond += " and timeStart>=[$(Format-PsaDate $from)]" }
            if ($to) { $dateCond += " and timeStart<[$(Format-PsaDate $to)]" }
            if ($byCompany) { & $one "company/id=$CompanyId$dateCond" '' }
            else { foreach ($tid in @(& $loop)) { & $one ("chargeToType=`"ServiceTicket`" and chargeToId=$([long]$tid)$dateCond") $tid } }
        }
        'autotask' {
            # Unverified: TimeEntries query on ticketID (eq, or "in" for several), dateWorked, and the fields
            # hoursWorked, hoursToBill, summaryNotes, internalNotes, isNonBillable, contractID, billingCodeID.
            for ($i = 0; $i -lt $ids.Count; $i += 200) {
                $chunk = @($ids | Select-Object -Skip $i -First 200 | ForEach-Object { [long]$_ })
                $f = @($(if ($chunk.Count -eq 1) { [ordered]@{ op = 'eq'; field = 'ticketID'; value = $chunk[0] } } else { [ordered]@{ op = 'in'; field = 'ticketID'; value = $chunk } }))
                if ($from) { $f += [ordered]@{ op = 'gte'; field = 'dateWorked'; value = (Format-PsaDate $from) } }
                if ($to) { $f += [ordered]@{ op = 'lt'; field = 'dateWorked'; value = (Format-PsaDate $to) } }
                foreach ($e in @(Invoke-PsaAtQuery 'TimeEntries' $f @() $Max $what)) {
                    $nb = Get-PsaProp $e 'isNonBillable'
                    $b = if ($null -eq $nb) { $null } else { -not [bool]$nb }
                    & $add @{ id = (Get-PsaProp $e 'id'); ticketId = (Get-PsaProp $e 'ticketID'); date = (Get-PsaFirst $e @('dateWorked', 'startDateTime')); hours = (Get-PsaNumber (Get-PsaProp $e 'hoursWorked'))
                        billableHours = $(if ($b -eq $false) { 0.0 } else { Get-PsaNumber (Get-PsaFirst $e @('hoursToBill', 'hoursWorked')) }); billable = $b
                        notes = (& $longer (Get-PsaProp $e 'summaryNotes') (Get-PsaProp $e 'internalNotes')); member = (Get-PsaProp $e 'resourceID'); workType = (Get-PsaProp $e 'billingCodeID'); agreementId = (Get-PsaProp $e 'contractID'); raw = $e }
                }
            }
        }
        'halopsa' {
            # Unverified: /Actions?ticket_id with excludesys; timetaken in hours; chargehours (or actionchargehours) as the
            # billable hours and actionnonchargehours as the rest. Only actions with time count as time entries.
            foreach ($tid in @(& $loop)) {
                $r = Invoke-PsaRead "/Actions?ticket_id=$tid&excludesys=true" $what $need
                $list = @(Get-PsaListReply $r @('actions'))
                foreach ($e in @($list | Where-Object { $null -ne $_ })) {
                    $h = Get-PsaNumber (Get-PsaProp $e 'timetaken'); if ($h -le 0) { continue }
                    $chRaw = Get-PsaFirst $e @('chargehours', 'actionchargehours'); $ch = Get-PsaNumber $chRaw; $nch = Get-PsaNumber (Get-PsaProp $e 'actionnonchargehours')
                    $b = if ($ch -gt 0) { $true } elseif ($nch -gt 0 -or ($null -ne $chRaw)) { $false } else { $null }
                    & $add @{ id = (Get-PsaProp $e 'id'); ticketId = $tid; date = (Get-PsaFirst $e @('datetime', 'actiondatecreated')); hours = $h; billableHours = $(if ($b -eq $true) { $ch } else { 0.0 }); billable = $b
                        notes = (ConvertTo-PsaPlainText ([string](Get-PsaFirst $e @('note', 'note_html')))); member = (Get-PsaProp $e 'who'); workType = (Get-PsaProp $e 'outcome'); agreementId = (Get-PsaProp $e 'contract_id'); raw = $e }
                }
            }
        }
        'kaseyabms' {
            # Vendor docs (BMS swagger): GET /v2/timelogs with Filter.TicketId; Timespent, Notes, InternalNotes, IsBillable,
            # StartDate. Unverified live: that Timespent is in hours.
            foreach ($tid in @(& $loop)) {
                for ($p = 1; $p -le 20; $p++) {
                    $list = @(Get-PsaBmsList (Invoke-PsaRead "/timelogs?Filter.TicketId=$tid&PageSize=100&PageNumber=$p" $what $need))
                    foreach ($e in $list) {
                        $ib = Get-PsaProp $e 'IsBillable'
                        & $add @{ id = (Get-PsaProp $e 'Id'); ticketId = $tid; date = (Get-PsaFirst $e @('StartDate', 'StartTime', 'Date')); hours = (Get-PsaNumber (Get-PsaFirst $e @('Timespent', 'ActualHours', 'Hours'))); billable = $(if ($null -eq $ib) { $null } else { [bool]$ib })
                            notes = (& $longer (Get-PsaProp $e 'Notes') (Get-PsaProp $e 'InternalNotes')); member = ("$(Get-PsaProp $e 'FirstName') $(Get-PsaProp $e 'LastName')".Trim()); workType = (Get-PsaProp $e 'WorkTypeName'); agreementId = (Get-PsaProp $e 'ContractId'); raw = $e }
                    }
                    if ($list.Count -lt 100) { break }
                }
            }
        }
        'syncro' {
            # Vendor docs (Syncro swagger): GET /ticket_timers?ticket_id with active_duration (seconds), billable and notes.
            # Unverified: labour charged straight as ticket line items (no timer) is read from the ticket's line_items when
            # the name looks like labour or time, with quantity as hours.
            foreach ($tid in @(& $loop)) {
                $before = $out.Count
                for ($p = 1; $p -le 20; $p++) {
                    $r = Invoke-PsaRead "/ticket_timers?ticket_id=$tid&page=$p" $what $need
                    foreach ($e in @(Get-PsaProp $r 'ticket_timers' | Where-Object { $null -ne $_ })) {
                        $bl = Get-PsaProp $e 'billable'
                        & $add @{ id = (Get-PsaProp $e 'id'); ticketId = $tid; date = (Get-PsaProp $e 'start_time'); hours = ((Get-PsaNumber (Get-PsaProp $e 'active_duration')) / 3600); billable = $(if ($null -eq $bl) { $null } else { [bool]$bl })
                            notes = (Get-PsaProp $e 'notes'); member = (Get-PsaProp $e 'user_id'); raw = $e }
                    }
                    $pages = Get-PsaPath $r 'meta.total_pages'
                    if ($null -eq $pages -or $p -ge [int]$pages) { break }
                }
                if ($out.Count -eq $before) {
                    $t = Get-PsaProp (Invoke-PsaRead "/tickets/$tid" $what $need) 'ticket'
                    foreach ($li in @(Get-PsaProp $t 'line_items' | Where-Object { $null -ne $_ })) {
                        if ("$(Get-PsaProp $li 'name') $(Get-PsaProp $li 'item')" -notmatch '(?i)labou?r|hour|time') { continue }
                        & $add @{ id = "line-$(Get-PsaProp $li 'id')"; ticketId = $tid; date = (Get-PsaProp $li 'created_at'); hours = (Get-PsaNumber (Get-PsaProp $li 'quantity')); billable = $true; notes = (Get-PsaProp $li 'description'); raw = $li }
                    }
                }
            }
        }
        'zendesk' {
            # Unverified: that the Time Tracking app's field holds whole seconds. Notes and the billable flag aren't available.
            foreach ($tid in @(& $loop)) {
                $t = Get-PsaProp (Invoke-PsaRead "/tickets/$tid" $what $need) 'ticket'
                $f = @(Get-PsaProp $t 'custom_fields' | Where-Object { $null -ne $_ -and [string](Get-PsaProp $_ 'id') -eq $ZendeskTimeFieldId }) | Select-Object -First 1
                $sec = 0.0; if ($f) { $sec = Get-PsaNumber (Get-PsaProp $f 'value') }
                if ($sec -gt 0) { & $add @{ id = "zd-$tid"; ticketId = $tid; date = (Get-PsaProp $t 'updated_at'); hours = ($sec / 3600); billable = $null; billableKnown = $false; notes = ''; notesKnown = $false; raw = $t } }
            }
        }
    }
    foreach ($w in $warn) { Add-PsaWarning $w }
    return @{ supported = $true; reason = ''; entries = @($out); warnings = @($warn) }
}

# The company's agreements (contracts). Returns @{ supported; reason; agreements = @(@{ id; name; type; status; active;
# startDate; endDate; amount; cycle; coverage }) }. supported is $false for Zendesk, which has none.
# Every row is checked against the company id again here.
function Get-PsaAgreements {
    param([string]$CompanyId)
    $c = Get-PsaConn
    if (Test-PsaBlank $CompanyId) { throw 'Get-PsaAgreements needs a company id.' }
    $rows = New-Object System.Collections.ArrayList
    $what = 'read agreements'; $need = 'read agreements and contracts'
    $mine = { param($v) $s = [string]$v; return (-not $s -or $s -eq [string]$CompanyId) }
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: GET /finance/agreements with company/id; fields agreementStatus, billAmount, applicationUnits, applicationLimit.
            foreach ($a in @(Invoke-PsaRead "/finance/agreements?conditions=$(ConvertTo-PsaQuery "company/id=$([long]$CompanyId)")&pageSize=100" $what $need | Where-Object { $null -ne $_ })) {
                if (-not (& $mine (Get-PsaPath $a 'company.id'))) { continue }
                $units = [string](Get-PsaProp $a 'applicationUnits'); $lim = Get-PsaProp $a 'applicationLimit'
                $cov = if ($units -and -not (Test-PsaBlank $lim)) { "$lim $($units.ToLowerInvariant()) per $(if (Get-PsaPath $a 'applicationCycle') { [string](Get-PsaPath $a 'applicationCycle') } else { 'period' })" } elseif ($units -match '(?i)unlimited') { 'unlimited' } else { '' }
                $st = [string](Get-PsaProp $a 'agreementStatus')
                $null = $rows.Add(@{ id = [string](Get-PsaProp $a 'id'); name = [string](Get-PsaProp $a 'name'); type = [string](Get-PsaPath $a 'type.name'); status = $st
                        active = ((Get-PsaProp $a 'cancelledFlag') -ne $true -and $st -notmatch '(?i)cancel|expired|inactive'); startDate = (ConvertTo-PsaDate (Get-PsaProp $a 'startDate')); endDate = (ConvertTo-PsaDate (Get-PsaProp $a 'endDate'))
                        amount = (Get-PsaNumber (Get-PsaProp $a 'billAmount')); cycle = [string](Get-PsaPath $a 'billingCycle.name'); coverage = $cov })
            }
        }
        'autotask' {
            # Unverified: Contracts query by companyID; contractType and status are picklists (status 1 = Active by default).
            $types = @(); try { $types = @(Get-PsaAtPicklist 'Contracts' 'contractType') } catch { $types = @() }
            foreach ($a in @(Invoke-PsaAtQuery 'Contracts' @([ordered]@{ op = 'eq'; field = 'companyID'; value = [long]$CompanyId }) @() 200 $what)) {
                if (-not (& $mine (Get-PsaProp $a 'companyID'))) { continue }
                $tv = [string](Get-PsaProp $a 'contractType')
                $tl = @($types | Where-Object { [string](Get-PsaProp $_ 'value') -eq $tv }) | Select-Object -First 1
                $st = Get-PsaProp $a 'status'
                $null = $rows.Add(@{ id = [string](Get-PsaProp $a 'id'); name = [string](Get-PsaProp $a 'contractName'); type = $(if ($tl) { [string](Get-PsaProp $tl 'label') } else { $tv }); status = [string]$st
                        active = ([string]$st -eq '1'); startDate = (ConvertTo-PsaDate (Get-PsaProp $a 'startDate')); endDate = (ConvertTo-PsaDate (Get-PsaProp $a 'endDate'))
                        amount = (Get-PsaNumber (Get-PsaProp $a 'setupFee')); cycle = ''; coverage = $(if (Get-PsaProp $a 'estimatedHours') { "$(Get-PsaProp $a 'estimatedHours') estimated hours" } else { '' }) })
            }
        }
        'halopsa' {
            # Unverified: GET /api/ClientContract?client_id= and its field names (ref, contract_type, start_date, end_date, active).
            $r = Invoke-PsaRead "/ClientContract?client_id=$CompanyId" $what $need
            $list = @(Get-PsaListReply $r @('contracts', 'clientcontracts'))
            foreach ($a in @($list | Where-Object { $null -ne $_ })) {
                if (-not (& $mine (Get-PsaProp $a 'client_id'))) { continue }
                $null = $rows.Add(@{ id = [string](Get-PsaProp $a 'id'); name = [string](Get-PsaFirst $a @('ref', 'name')); type = [string](Get-PsaFirst $a @('contract_type_name', 'billing_description', 'contract_type')); status = $(if ((Get-PsaProp $a 'active') -eq $false) { 'Inactive' } else { 'Active' })
                        active = ((Get-PsaProp $a 'active') -ne $false); startDate = (ConvertTo-PsaDate (Get-PsaProp $a 'start_date')); endDate = (ConvertTo-PsaDate (Get-PsaProp $a 'end_date'))
                        amount = (Get-PsaNumber (Get-PsaFirst $a @('periodchargeamount', 'value'))); cycle = [string](Get-PsaProp $a 'billing_period'); coverage = $(if (Get-PsaProp $a 'prepay_hours') { "$(Get-PsaProp $a 'prepay_hours') prepaid hours" } else { '' }) })
            }
        }
        'kaseyabms' {
            # Unverified: GET /v2/finance/contracts?Filter.AccountId= and its field names.
            foreach ($a in @(Get-PsaBmsList (Invoke-PsaRead "/finance/contracts?Filter.AccountId=$CompanyId&PageSize=100" $what $need))) {
                if (-not (& $mine (Get-PsaProp $a 'AccountId'))) { continue }
                $st = [string](Get-PsaFirst $a @('StatusName', 'Status'))
                $null = $rows.Add(@{ id = [string](Get-PsaProp $a 'Id'); name = [string](Get-PsaFirst $a @('Name', 'ContractName')); type = [string](Get-PsaFirst $a @('ContractTypeName', 'TypeName')); status = $st
                        active = ($st -notmatch '(?i)cancel|expired|inactive'); startDate = (ConvertTo-PsaDate (Get-PsaProp $a 'StartDate')); endDate = (ConvertTo-PsaDate (Get-PsaProp $a 'EndDate'))
                        amount = (Get-PsaNumber (Get-PsaFirst $a @('Amount', 'RecurringAmount'))); cycle = [string](Get-PsaProp $a 'BillingCycleName'); coverage = '' })
            }
        }
        'syncro' {
            # Unverified: GET /contracts?customer_id= ({ contracts: [...] } with name, contract_amount, start_date, end_date, status).
            foreach ($a in @(Get-PsaProp (Invoke-PsaRead "/contracts?customer_id=$CompanyId" $what $need) 'contracts' | Where-Object { $null -ne $_ })) {
                if (-not (& $mine (Get-PsaProp $a 'customer_id'))) { continue }
                $st = [string](Get-PsaProp $a 'status')
                $null = $rows.Add(@{ id = [string](Get-PsaProp $a 'id'); name = [string](Get-PsaProp $a 'name'); type = [string](Get-PsaProp $a 'contract_type'); status = $st
                        active = ($st -notmatch '(?i)cancel|expired|inactive'); startDate = (ConvertTo-PsaDate (Get-PsaProp $a 'start_date')); endDate = (ConvertTo-PsaDate (Get-PsaProp $a 'end_date'))
                        amount = (Get-PsaNumber (Get-PsaProp $a 'contract_amount')); cycle = ''; coverage = '' })
            }
        }
        'zendesk' { return @{ supported = $false; reason = 'Zendesk has no agreements or contracts.'; agreements = @() } }
    }
    return @{ supported = $true; reason = ''; agreements = @($rows) }
}

# One invoice by its number: @{ id; number; companyId; date; periodStart; periodEnd; periodDerived; total },
# or $null when it isn't found. Throws when the PSA has no invoice API (Kaseya BMS, Syncro, Zendesk: check
# Get-PsaCapabilities first). When the invoice carries no service period, the period is the calendar month
# before the invoice date, and periodDerived is $true.
function Get-PsaInvoice {
    param([string]$Number)
    $c = Get-PsaConn
    $n = ([string]$Number).Trim().TrimStart('#')
    if (-not $n) { throw 'Get-PsaInvoice needs an invoice number.' }
    $inv = $null; $companyId = ''; $date = $null; $ps = $null; $pe = $null; $total = 0.0; $id = ''
    $what = 'read invoices'; $need = 'read invoices'
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: GET /finance/invoices?conditions=invoiceNumber="..." and the fields company.id, date, total.
            $q = $n.Replace('\', '\\').Replace('"', '\"')
            $inv = @(Invoke-PsaRead "/finance/invoices?conditions=$(ConvertTo-PsaQuery ('invoiceNumber="' + $q + '"'))&pageSize=5" $what $need | Where-Object { $null -ne $_ }) | Select-Object -First 1
            if (-not $inv) { return $null }
            $id = [string](Get-PsaProp $inv 'id'); $companyId = [string](Get-PsaPath $inv 'company.id'); $date = ConvertTo-PsaDate (Get-PsaProp $inv 'date'); $total = Get-PsaNumber (Get-PsaProp $inv 'total')
        }
        'autotask' {
            # Unverified: Invoices query by invoiceNumber; fields companyID, invoiceDateTime, fromDate, toDate, invoiceTotal.
            $inv = @(Invoke-PsaAtQuery 'Invoices' @([ordered]@{ op = 'eq'; field = 'invoiceNumber'; value = $n }) @() 5 $what) | Select-Object -First 1
            if (-not $inv) { return $null }
            $id = [string](Get-PsaProp $inv 'id'); $companyId = [string](Get-PsaProp $inv 'companyID'); $date = ConvertTo-PsaDate (Get-PsaProp $inv 'invoiceDateTime')
            $ps = ConvertTo-PsaDate (Get-PsaProp $inv 'fromDate'); $pe = ConvertTo-PsaDate (Get-PsaProp $inv 'toDate'); if ($pe) { $pe = $pe.Date.AddDays(1) }
            $total = Get-PsaNumber (Get-PsaFirst $inv @('invoiceTotal', 'totalAmount'))
        }
        'halopsa' {
            # Unverified: GET /api/Invoice?search= ({ invoices: [...] }) and the fields invoicenumber, client_id, invoice_date, total.
            $r = Invoke-PsaRead "/Invoice?search=$(ConvertTo-PsaQuery $n)&count=20" $what $need
            $list = @(Get-PsaListReply $r @('invoices'))
            $inv = @($list | Where-Object { $null -ne $_ -and ([string](Get-PsaFirst $_ @('invoicenumber', 'invoice_number', 'id'))) -eq $n }) | Select-Object -First 1
            if (-not $inv) { return $null }
            $id = [string](Get-PsaProp $inv 'id'); $companyId = [string](Get-PsaProp $inv 'client_id'); $date = ConvertTo-PsaDate (Get-PsaFirst $inv @('invoice_date', 'invoicedate', 'date'))
            $total = Get-PsaNumber (Get-PsaFirst $inv @('total', 'total_amount', 'amount'))
        }
        default { throw "$(Get-PsaName) invoices can't be looked up by number here." }
    }
    $derived = $false
    if (-not $ps -or -not $pe) {
        if (-not $date) { return @{ id = $id; number = $n; companyId = $companyId; date = $null; periodStart = $null; periodEnd = $null; periodDerived = $false; total = $total } }
        $first = [datetime]::new($date.Year, $date.Month, 1, 0, 0, 0, [DateTimeKind]::Utc)
        $ps = $first.AddMonths(-1); $pe = $first; $derived = $true
    }
    return @{ id = $id; number = $n; companyId = $companyId; date = $date; periodStart = $ps; periodEnd = $pe; periodDerived = $derived; total = $total }
}

# A company's active contacts. Returns @{ primarySupported; contacts = @(@{ id; name; email; primary }) }.
# primarySupported is $false for PSAs with no primary-contact flag (Syncro, Zendesk); primary is then always $false.
function Get-PsaCompanyContacts {
    param([string]$CompanyId)
    $c = Get-PsaConn
    if ($CompanyId -notmatch '^\d+$') { throw "Get-PsaCompanyContacts needs a numeric company id (it was '$CompanyId')." }
    $list = New-Object System.Collections.ArrayList
    $supported = $true
    $what = 'read contacts'; $need = 'read companies and contacts'
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: company.defaultContact as the primary contact, the contacts conditions, and the email from
            # communicationItems (communicationType Email, defaultFlag first) when the list rows carry them.
            $co = Invoke-PsaRead "/company/companies/$CompanyId" $what $need
            $def = [string](Get-PsaPath $co 'defaultContact.id')
            foreach ($p in @(Invoke-PsaRead "/company/contacts?conditions=$(ConvertTo-PsaQuery "company/id=$CompanyId and inactiveFlag=false")&pageSize=1000" $what $need | Where-Object { $null -ne $_ })) {
                $id = [string](Get-PsaProp $p 'id')
                $items = @(Get-PsaProp $p 'communicationItems' | Where-Object { $null -ne $_ -and [string](Get-PsaProp $_ 'communicationType') -eq 'Email' })
                $pick = @(@($items | Where-Object { (Get-PsaProp $_ 'defaultFlag') -eq $true }) + $items) | Select-Object -First 1
                $null = $list.Add(@{ id = $id; name = "$(Get-PsaProp $p 'firstName') $(Get-PsaProp $p 'lastName')".Trim(); email = $(if ($pick) { [string](Get-PsaProp $pick 'value') } else { '' }); primary = (($def -and $id -eq $def) -or (Get-PsaProp $p 'defaultFlag') -eq $true) })
            }
        }
        'autotask' {
            # Unverified: Contacts query on companyID and isActive, and the primaryContact flag.
            foreach ($p in @(Invoke-PsaAtQuery 'Contacts' @([ordered]@{ op = 'eq'; field = 'companyID'; value = [long]$CompanyId }, [ordered]@{ op = 'eq'; field = 'isActive'; value = 1 }) @() 2000 $what)) {
                $null = $list.Add(@{ id = [string](Get-PsaProp $p 'id'); name = "$(Get-PsaProp $p 'firstName') $(Get-PsaProp $p 'lastName')".Trim(); email = [string](Get-PsaProp $p 'emailAddress'); primary = ((Get-PsaProp $p 'primaryContact') -eq $true) })
            }
        }
        'halopsa' {
            # Unverified: /Users?client_id and the isprimarycontact flag name.
            $r = Invoke-PsaRead "/Users?client_id=$CompanyId&count=500" $what $need
            $users = @(Get-PsaListReply $r @('users'))
            foreach ($p in @($users | Where-Object { $null -ne $_ -and (Get-PsaProp $_ 'inactive') -ne $true })) {
                $pri = ((Get-PsaProp $p 'isprimarycontact') -eq $true) -or ((Get-PsaProp $p 'is_primary_contact') -eq $true)
                $null = $list.Add(@{ id = [string](Get-PsaProp $p 'id'); name = [string](Get-PsaProp $p 'name'); email = [string](Get-PsaProp $p 'emailaddress'); primary = $pri })
            }
        }
        'kaseyabms' {
            # Vendor docs: GET /v2/crm/contacts/summary with Filter.AccountId and Filter.IsActive; IsPoc marks the point of contact.
            for ($page = 1; $page -le 20; $page++) {
                $rs = @(Get-PsaBmsList (Invoke-PsaRead "/crm/contacts/summary?Filter.AccountId=$CompanyId&Filter.IsActive=true&PageSize=100&PageNumber=$page" $what $need))
                foreach ($p in $rs) {
                    $em = @(Get-PsaProp $p 'Emails' | Where-Object { $null -ne $_ }) | Select-Object -First 1
                    $mail = [string](Get-PsaProp $em 'EmailAddress'); if (-not $mail) { $mail = [string](Get-PsaProp $p 'EmailAddress') }
                    $null = $list.Add(@{ id = [string](Get-PsaProp $p 'Id'); name = "$(Get-PsaProp $p 'FirstName') $(Get-PsaProp $p 'LastName')".Trim(); email = $mail; primary = ((Get-PsaProp $p 'IsPoc') -eq $true) })
                }
                if ($rs.Count -lt 100) { break }
            }
        }
        'syncro' {
            # Vendor docs: GET /contacts?customer_id. Syncro contacts have no primary flag.
            $supported = $false
            for ($page = 1; $page -le 20; $page++) {
                $r = Invoke-PsaRead "/contacts?customer_id=$CompanyId&page=$page" $what $need
                foreach ($p in @(Get-PsaProp $r 'contacts' | Where-Object { $null -ne $_ })) { $null = $list.Add(@{ id = [string](Get-PsaProp $p 'id'); name = [string](Get-PsaProp $p 'name'); email = [string](Get-PsaProp $p 'email'); primary = $false }) }
                $pages = Get-PsaPath $r 'meta.total_pages'
                if ($null -eq $pages -or $page -ge [int]$pages) { break }
            }
        }
        'zendesk' {
            # Unverified: GET /organizations/{id}/users. Zendesk organizations have no primary contact.
            $supported = $false
            foreach ($p in @(Get-PsaProp (Invoke-PsaRead "/organizations/$CompanyId/users?per_page=100" $what $need) 'users' | Where-Object { $null -ne $_ -and (Get-PsaProp $_ 'active') -ne $false })) {
                $null = $list.Add(@{ id = [string](Get-PsaProp $p 'id'); name = [string](Get-PsaProp $p 'name'); email = [string](Get-PsaProp $p 'email'); primary = $false })
            }
        }
    }
    return @{ primarySupported = $supported; contacts = @($list) }
}

# The company's primary contact as @{ id; name; email }, or $null when the PSA has none, can't say, or the
# contact has no usable email address. Zendesk organizations have no primary contact, so it is always $null.
function Get-PsaPrimaryContact {
    param([string]$CompanyId)
    $c = Get-PsaConn
    if (Test-PsaBlank $CompanyId) { return $null }
    $id = ''; $name = ''; $email = ''
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: the company's defaultContact, then the contact's default Email communication item.
            $co = Invoke-PsaRead "/company/companies/$CompanyId" 'read companies' 'read companies and contacts'
            $id = [string](Get-PsaPath $co 'defaultContact.id')
            if (Test-PsaBlank $id) { return $null }
            $ct = Invoke-PsaRead "/company/contacts/$id" 'read contacts' 'read companies and contacts'
            $name = (@([string](Get-PsaProp $ct 'firstName'), [string](Get-PsaProp $ct 'lastName')) -join ' ').Trim()
            $items = @(Get-PsaProp $ct 'communicationItems' | Where-Object { $null -ne $_ -and [string](Get-PsaProp $_ 'communicationType') -eq 'Email' })
            $pick = @(@($items | Where-Object { (Get-PsaProp $_ 'defaultFlag') -eq $true }) + $items) | Select-Object -First 1
            if ($pick) { $email = [string](Get-PsaProp $pick 'value') }
        }
        'autotask' {
            # Unverified: Contacts query on companyID with primaryContact = true and isActive = 1.
            $hit = @(Invoke-PsaAtQuery 'Contacts' @([ordered]@{ op = 'eq'; field = 'companyID'; value = [long]$CompanyId }, [ordered]@{ op = 'eq'; field = 'primaryContact'; value = $true }, [ordered]@{ op = 'eq'; field = 'isActive'; value = 1 }) @() 5 'read contacts') | Select-Object -First 1
            if (-not $hit) { return $null }
            $id = [string](Get-PsaProp $hit 'id'); $name = (@([string](Get-PsaProp $hit 'firstName'), [string](Get-PsaProp $hit 'lastName')) -join ' ').Trim(); $email = [string](Get-PsaProp $hit 'emailAddress')
        }
        { $_ -in @('halopsa', 'kaseyabms') } {
            $hit = @((Get-PsaCompanyContacts -CompanyId $CompanyId).contacts | Where-Object { $_.primary }) | Select-Object -First 1
            if (-not $hit) { return $null }
            $id = $hit.id; $name = $hit.name; $email = $hit.email
        }
        'syncro' {
            # Unverified: a Syncro customer carries its own main email and name.
            $cu = Get-PsaProp (Invoke-PsaRead "/customers/$CompanyId" 'read customers' 'read customers and contacts') 'customer'
            if ($null -eq $cu) { return $null }
            $id = ''; $name = (@([string](Get-PsaProp $cu 'firstname'), [string](Get-PsaProp $cu 'lastname')) -join ' ').Trim(); $email = [string](Get-PsaProp $cu 'email')
        }
        'zendesk' { return $null }
    }
    $email = $email.Trim()
    if ($email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return $null }
    return @{ id = $id; name = $name; email = $email }
}

# Relates ticket -Id to the older ticket -RelatedId. Uses the PSA's own relation where one exists:
#   HaloPSA: Id becomes a child of RelatedId (parent_id).
#   Autotask and Zendesk: Id becomes an Incident of RelatedId, only when RelatedId is already a Problem ticket.
#   ConnectWise, Kaseya BMS, Syncro: no relation in the API, so notes only.
# -NotesOnly skips the PSA relation (a ticket can only have one parent or problem).
# Always adds an internal cross-reference note on -NoteTicketId (default RelatedId) naming the other ticket, with
# the marker "related: <Id> and <RelatedId>", so a retried run doesn't add it twice. Never merges, closes or
# changes status. Returns @{ method = 'native' | 'note-only'; detail; note = 'written' | 'already-present' }.
function Add-PsaTicketRelation {
    param([string]$Id, [string]$RelatedId, [string]$Reason = '', [switch]$NotesOnly, [string]$NoteTicketId = '')
    $c = Get-PsaConn
    if ($Id -eq $RelatedId) { throw 'A ticket cannot be related to itself.' }
    if (-not $NoteTicketId) { $NoteTicketId = $RelatedId }
    $method = 'note-only'; $detail = ''
    $kind = if ($NotesOnly) { 'notes' } else { $c.Psa }
    switch ($kind) {
        'notes' { $detail = 'Related by notes only.' }
        'halopsa' {
            # Unverified: parent_id on POST /api/Tickets. Halo may close child tickets with their parent, depending on its settings.
            $null = Invoke-Psa POST '/Tickets' @([ordered]@{ id = [long]$Id; parent_id = [long]$RelatedId })
            $method = 'native'; $detail = "Ticket $Id is now a child of ticket $RelatedId."
        }
        'autotask' {
            # Unverified: ticketType picklist labels Problem and Incident, and the problemTicketID field.
            $other = Get-PsaProp (Invoke-Psa GET "/Tickets/$RelatedId") 'item'
            $types = @(Get-PsaAtPicklist 'Tickets' 'ticketType')
            $problem = Select-PsaAtValue $types @('(?i)^problem$'); $incident = Select-PsaAtValue $types @('(?i)^incident$')
            if ($null -ne $problem -and $null -ne $incident -and [string](Get-PsaProp $other 'ticketType') -eq [string]$problem) {
                $null = Invoke-Psa PATCH '/Tickets' ([ordered]@{ id = [long]$Id; ticketType = [int]$incident; problemTicketID = [long]$RelatedId })
                $method = 'native'; $detail = "Ticket $Id is now an incident of problem ticket $RelatedId."
            }
            else { $detail = "Ticket $RelatedId is not a Problem ticket, so they were related by notes only." }
        }
        'zendesk' {
            # Vendor docs: problem_id with type incident. Only when the other ticket is already a problem.
            $other = Get-PsaProp (Invoke-Psa GET "/tickets/$RelatedId") 'ticket'
            if ([string](Get-PsaProp $other 'type') -eq 'problem') {
                $null = Invoke-Psa PUT "/tickets/$Id" @{ ticket = @{ type = 'incident'; problem_id = [long]$RelatedId } }
                $method = 'native'; $detail = "Ticket $Id is now an incident of problem ticket $RelatedId."
            }
            else { $detail = "Ticket $RelatedId is not a problem ticket, so they were related by notes only." }
        }
        default { $detail = "$(Get-PsaName) has no ticket relation in its API, so they were related by notes only." }
    }
    $otherId = if ($NoteTicketId -eq $RelatedId) { $Id } else { $RelatedId }
    $text = "Related ticket: #$otherId looks like the same issue as this ticket.$(if ($Reason) { " $Reason" })$(if ($method -eq 'native') { " $detail" }) Nothing was merged or closed."
    $note = Add-PsaNote -Id $NoteTicketId -Text $text -Title 'Related ticket' -Marker "related: $Id and $RelatedId"
    return @{ method = $method; detail = $detail; note = $note }
}
# ---------- end _shared/psa-tickets.ps1 ----------
