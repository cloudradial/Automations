# ---------- src/psa-extra.ps1: ticket lists, ticket notes and named-status close for six PSAs ----------
# Adds what _shared/psa.ps1 can't do yet. Paste it AFTER _shared/psa.ps1 in the same step: it uses
# Invoke-Psa, Get-PsaConn, Get-PsaProp, Get-PsaPath, Test-PsaBlank, ConvertTo-PsaQuery, Get-PsaAtPicklist,
# Select-PsaByLabel, Set-PsaStatus and $PsaState.PriorityPatterns from there.
# The same file ships in waiting-on-client-nudge/src and auto-close-resolved/src (keep them identical).
# It is a candidate to move into automationai/_shared once the calls are proven live.
# Calls marked "Unverified" are not in reference/build-kit/PSA.md yet; check them before the first live write.
#
#   Find-PsaTickets -StatusName <name> [-OlderThan <datetime>] [-NewerThan <datetime>] [-DateField updated|created] [-CompanyId <id>] [-Max <int>]
#       Tickets whose status is exactly that name and whose updated (or created) date is between NewerThan and OlderThan. Returns up to Max + 1 rows, so a caller can
#       tell there were more than Max. Each row: @{ id; number; summary; companyId; companyName; status;
#       priority; priorityLevel; created; updated; statusChanged; resolved; requesterId; raw }.
#       Dates are UTC [datetime] or $null when the PSA doesn't give one.
#   Get-PsaTicketNotes -Id <id> [-Ticket <row from Find-PsaTickets>]
#       @(@{ id; text; created; internal; fromClient; author }), oldest first.
#       fromClient is best effort (see each PSA below); $false when the PSA doesn't say.
#   Close-PsaTicket -Id <id> [-StatusName <name>] [-NotStatus <name>]
#       Closes the ticket to the named status, or the PSA's usual closed status, never to -NotStatus.
#       Returns the status that was set.
#   Get-PsaStatusId -Name <name>      the id of a named status (Autotask, HaloPSA, Kaseya BMS)
#   Get-PsaPriorityLevel -Label <s>   critical, high, medium, low or ''
#   ConvertTo-PsaDate <value>         a UTC [datetime], or $null

function ConvertTo-PsaDate {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [DateTimeKind]::Unspecified) { return [datetime]::SpecifyKind($Value, [DateTimeKind]::Utc) }
        return $Value.ToUniversalTime()
    }
    if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime }
    $s = ([string]$Value).Trim()
    if (-not $s -or $s -eq '0') { return $null }
    $d = [datetime]::MinValue
    $styles = [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal
    if ([datetime]::TryParse($s, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$d)) { return $d }
    return $null
}

function Get-PsaPriorityLevel {
    param([string]$Label)
    if ([string]::IsNullOrWhiteSpace($Label)) { return '' }
    foreach ($lvl in @('critical', 'high', 'medium', 'low')) {
        foreach ($p in $PsaState.PriorityPatterns[$lvl]) { if ($Label -match $p) { return $lvl } }
    }
    return ''
}

# The first non-blank property of $o among $Names.
function Get-PsaFirst {
    param($o, [string[]]$Names)
    foreach ($n in $Names) { $v = Get-PsaPath $o $n; if (-not (Test-PsaBlank $v)) { return $v } }
    return $null
}

# Status lists for the PSAs that key statuses by id: @(@{ id; name }).
function Get-PsaStatusList {
    $c = Get-PsaConn
    switch ($c.Psa) {
        'autotask' { return @(Get-PsaAtPicklist 'Tickets' 'status' | ForEach-Object { @{ id = [string](Get-PsaProp $_ 'value'); name = [string](Get-PsaProp $_ 'label') } }) }
        'halopsa' {
            # Unverified: GET /api/Status (HaloAPI Get-HaloStatus) returns an array of { id, name }.
            $r = Invoke-Psa GET '/Status'
            $rows = @(Get-PsaProp $r 'statuses'); if (-not @($rows | Where-Object { $null -ne $_ }).Count) { $rows = @($r) }
            return @($rows | Where-Object { $null -ne $_ -and $null -ne (Get-PsaProp $_ 'name') } | ForEach-Object { @{ id = [string](Get-PsaProp $_ 'id'); name = [string](Get-PsaProp $_ 'name') } })
        }
        'kaseyabms' {
            # From the BMS swagger: GET /v2/system/statuses/lookup returns { Result: [{ Id, Name, IsActive }] }.
            $r = Invoke-Psa GET '/system/statuses/lookup'
            return @(Get-PsaProp $r 'Result' | Where-Object { $null -ne $_ -and (Get-PsaProp $_ 'IsActive') -ne $false } | ForEach-Object { @{ id = [string](Get-PsaProp $_ 'Id'); name = [string](Get-PsaProp $_ 'Name') } })
        }
    }
    return @()
}

function Get-PsaStatusId {
    param([string]$Name)
    if ($Name -match '^\d+$') { return $Name }
    $list = @(Get-PsaStatusList)
    $hit = @($list | Where-Object { $_.name.Trim() -ieq $Name.Trim() }) | Select-Object -First 1
    if (-not $hit) { throw "$(Get-PsaName) has no ticket status named '$Name'. Its statuses are: $((@($list | ForEach-Object { $_.name }) | Sort-Object -Unique) -join ', ')." }
    return $hit.id
}

# One normalized ticket row.
function New-PsaTicketRow {
    param($Raw, $Id, $Number, $Summary, $CompanyId, $CompanyName, $Status, $Priority, $Created, $Updated, $StatusChanged, $Resolved, $RequesterId)
    return @{
        id = [string]$Id; number = $(if (Test-PsaBlank $Number) { [string]$Id } else { [string]$Number }); summary = [string]$Summary
        companyId = $(if (Test-PsaBlank $CompanyId) { '' } else { [string]$CompanyId }); companyName = [string]$CompanyName
        status = [string]$Status; priority = [string]$Priority; priorityLevel = (Get-PsaPriorityLevel ([string]$Priority))
        created = (ConvertTo-PsaDate $Created); updated = (ConvertTo-PsaDate $Updated); statusChanged = (ConvertTo-PsaDate $StatusChanged); resolved = (ConvertTo-PsaDate $Resolved)
        requesterId = $(if (Test-PsaBlank $RequesterId) { '' } else { [string]$RequesterId }); raw = $Raw
    }
}

function Find-PsaTickets {
    param([string]$StatusName, $OlderThan = $null, $NewerThan = $null, [ValidateSet('updated', 'created')][string]$DateField = 'updated', [string]$CompanyId = '', [int]$Max = 200)
    $c = Get-PsaConn
    if ([string]::IsNullOrWhiteSpace($StatusName)) { throw 'Find-PsaTickets needs a status name.' }
    $StatusName = $StatusName.Trim()
    $want = $Max + 1
    $cut = ConvertTo-PsaDate $OlderThan
    $iso = if ($cut) { $cut.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) } else { '' }
    $from = ConvertTo-PsaDate $NewerThan
    $isoFrom = if ($from) { $from.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) } else { '' }
    $rows = New-Object System.Collections.ArrayList
    # Every row is re-checked here, because some list filters are unverified or missing. Paging stops once
    # Max + 1 rows pass, so rows a PSA can't filter out on the server don't use up the budget.
    $keepRow = {
        param($r)
        $ok = ($r.status.Trim() -ieq $StatusName)
        if ($ok -and $CompanyId -and $r.companyId) { $ok = ($r.companyId -eq [string]$CompanyId) }
        $d = $(if ($DateField -eq 'created') { $r.created } else { $r.updated })
        if ($ok -and $cut -and $null -ne $d) { $ok = ($d -lt $cut) }
        if ($ok -and $from -and $null -ne $d) { $ok = ($d -gt $from) }
        return $ok
    }
    $more = { return (@($rows | Where-Object { & $keepRow $_ }).Count -lt $want) }
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: the lastUpdated / dateEntered condition names and the [date] literal (CW conditions syntax).
            $q = $StatusName.Replace('\', '\\').Replace('"', '\"')
            $cond = 'status/name="' + $q + '"'
            if ($CompanyId) { $cond += " and company/id=$([int]$CompanyId)" }
            if ($iso) { $cond += $(if ($DateField -eq 'created') { " and dateEntered < [$iso]" } else { " and lastUpdated < [$iso]" }) }
            if ($isoFrom) { $cond += $(if ($DateField -eq 'created') { " and dateEntered > [$isoFrom]" } else { " and lastUpdated > [$isoFrom]" }) }
            $size = [Math]::Min($want, 1000)
            for ($p = 1; $p -le 50 -and (& $more); $p++) {
                $page = @(Invoke-Psa GET "/service/tickets?conditions=$(ConvertTo-PsaQuery $cond)&orderBy=$(ConvertTo-PsaQuery 'id asc')&pageSize=$size&page=$p" | Where-Object { $null -ne $_ })
                foreach ($t in $page) {
                    $null = $rows.Add((New-PsaTicketRow $t (Get-PsaProp $t 'id') (Get-PsaProp $t 'id') (Get-PsaProp $t 'summary') (Get-PsaPath $t 'company.id') (Get-PsaPath $t 'company.name') (Get-PsaPath $t 'status.name') (Get-PsaPath $t 'priority.name') (Get-PsaProp $t 'dateEntered') (Get-PsaPath $t '_info.lastUpdated') $null (Get-PsaProp $t 'closedDate') (Get-PsaPath $t 'contact.id')))
                }
                if ($page.Count -lt $size) { break }
            }
        }
        'autotask' {
            # Status and priority are per-tenant picklists, matched on the label. Unverified: lastActivityDate as the
            # "updated" field, and resolvedDateTime / createdByContactID names (Autotask Tickets entity docs).
            $sv = Get-PsaStatusId $StatusName
            $f = @([ordered]@{ op = 'eq'; field = 'status'; value = [int]$sv })
            if ($CompanyId) { $f += [ordered]@{ op = 'eq'; field = 'companyID'; value = [long]$CompanyId } }
            if ($iso) { $f += [ordered]@{ op = 'lt'; field = $(if ($DateField -eq 'created') { 'createDate' } else { 'lastActivityDate' }); value = $iso } }
            if ($isoFrom) { $f += [ordered]@{ op = 'gt'; field = $(if ($DateField -eq 'created') { 'createDate' } else { 'lastActivityDate' }); value = $isoFrom } }
            $prios = @{}; foreach ($pv in @(Get-PsaAtPicklist 'Tickets' 'priority')) { $prios[[string](Get-PsaProp $pv 'value')] = [string](Get-PsaProp $pv 'label') }
            $s = [ordered]@{ filter = $f; MaxRecords = [Math]::Min($want, 500) }
            $next = "/Tickets/query?search=$(ConvertTo-PsaQuery ($s | ConvertTo-Json -Depth 6 -Compress))"
            for ($p = 1; $p -le 50 -and $next -and (& $more); $p++) {
                $r = Invoke-Psa GET $next
                foreach ($t in @(Get-PsaProp $r 'items' | Where-Object { $null -ne $_ })) {
                    $pr = [string](Get-PsaProp $t 'priority'); if ($prios.ContainsKey($pr)) { $pr = $prios[$pr] }
                    $null = $rows.Add((New-PsaTicketRow $t (Get-PsaProp $t 'id') (Get-PsaProp $t 'ticketNumber') (Get-PsaProp $t 'title') (Get-PsaProp $t 'companyID') '' $StatusName $pr (Get-PsaProp $t 'createDate') (Get-PsaProp $t 'lastActivityDate') $null (Get-PsaProp $t 'resolvedDateTime') (Get-PsaProp $t 'contactID')))
                }
                $next = [string](Get-PsaPath $r 'pageDetails.nextPageUrl')
            }
        }
        'halopsa' {
            # Unverified: the status_id and client_id list filters, the { tickets, record_count } reply, and the
            # lastactiondate / dateoccurred field names (HaloAPI module). No date filter is used; dates are checked below. Halo's out-of-box priority ids 1 to 4 are
            # Critical to Low; other ids are left unlabelled.
            $sid = Get-PsaStatusId $StatusName
            $base = "/Tickets?status_id=$sid&pageinate=true&page_size=100"
            if ($CompanyId) { $base += "&client_id=$([long]$CompanyId)" }
            for ($p = 1; $p -le 50 -and (& $more); $p++) {
                $r = Invoke-Psa GET "$base&page_no=$p"
                $page = @(Get-PsaProp $r 'tickets' | Where-Object { $null -ne $_ })
                foreach ($t in $page) {
                    $pid0 = [string](Get-PsaProp $t 'priority_id')
                    $pr = switch ($pid0) { '1' { 'Critical' } '2' { 'High' } '3' { 'Medium' } '4' { 'Low' } default { '' } }
                    $null = $rows.Add((New-PsaTicketRow $t (Get-PsaProp $t 'id') (Get-PsaProp $t 'id') (Get-PsaProp $t 'summary') (Get-PsaProp $t 'client_id') (Get-PsaProp $t 'client_name') $StatusName $pr (Get-PsaProp $t 'dateoccurred') (Get-PsaFirst $t @('lastactiondate', 'last_update')) $null (Get-PsaProp $t 'dateclosed') (Get-PsaProp $t 'user_id')))
                }
                if ($page.Count -lt 100) { break }
            }
        }
        'kaseyabms' {
            # From the BMS swagger: GET /v2/servicedesk/tickets with Filter.StatusNames, Filter.AccountIds,
            # Filter.LastActivityUpdateTo / Filter.OpenDateTo, PageSize and PageNumber; it returns { Result, TotalRecords }.
            # Unverified: whether Filter.StatusNames is an exact or a contains match, so rows are re-checked below.
            $base = "/servicedesk/tickets?Filter.StatusNames=$(ConvertTo-PsaQuery $StatusName)&PageSize=100"
            if ($CompanyId) { $base += "&Filter.AccountIds=$([long]$CompanyId)" }
            if ($iso) { $base += $(if ($DateField -eq 'created') { "&Filter.OpenDateTo=$(ConvertTo-PsaQuery $iso)" } else { "&Filter.LastActivityUpdateTo=$(ConvertTo-PsaQuery $iso)" }) }
            if ($isoFrom) { $base += $(if ($DateField -eq 'created') { "&Filter.OpenDateFrom=$(ConvertTo-PsaQuery $isoFrom)" } else { "&Filter.LastActivityUpdateFrom=$(ConvertTo-PsaQuery $isoFrom)" }) }
            for ($p = 1; $p -le 50 -and (& $more); $p++) {
                $r = Invoke-Psa GET "$base&PageNumber=$p"
                $page = @(Get-PsaProp $r 'Result' | Where-Object { $null -ne $_ })
                foreach ($t in $page) {
                    $null = $rows.Add((New-PsaTicketRow $t (Get-PsaProp $t 'Id') (Get-PsaProp $t 'TicketNumber') (Get-PsaProp $t 'Title') (Get-PsaProp $t 'AccountId') (Get-PsaProp $t 'AccountName') (Get-PsaProp $t 'StatusName') (Get-PsaProp $t 'PriorityName') (Get-PsaFirst $t @('OpenDate', 'CreatedOn')) (Get-PsaFirst $t @('LastActivityUpdate', 'ModifiedOn')) (Get-PsaProp $t 'LastStatusUpdate') (Get-PsaProp $t 'CompletedDate') (Get-PsaProp $t 'ContactId')))
                }
                if ($page.Count -lt 100) { break }
            }
        }
        'syncro' {
            # From the Syncro swagger: GET /tickets?status=<label>&customer_id=&page= returns { tickets, meta.total_pages }.
            # There is no "updated before" filter, so dates are checked below; since_updated_at and created_after bound the other end.
            $base = "/tickets?status=$(ConvertTo-PsaQuery $StatusName)"
            if ($isoFrom) { $base += $(if ($DateField -eq 'created') { "&created_after=$(ConvertTo-PsaQuery $isoFrom)" } else { "&since_updated_at=$(ConvertTo-PsaQuery $isoFrom)" }) }
            if ($CompanyId) { $base += "&customer_id=$([long]$CompanyId)" }
            for ($p = 1; $p -le 50 -and (& $more); $p++) {
                $r = Invoke-Psa GET "$base&page=$p"
                foreach ($t in @(Get-PsaProp $r 'tickets' | Where-Object { $null -ne $_ })) {
                    $null = $rows.Add((New-PsaTicketRow $t (Get-PsaProp $t 'id') (Get-PsaProp $t 'number') (Get-PsaProp $t 'subject') (Get-PsaProp $t 'customer_id') (Get-PsaProp $t 'customer_business_then_name') (Get-PsaProp $t 'status') (Get-PsaProp $t 'priority') (Get-PsaProp $t 'created_at') (Get-PsaProp $t 'updated_at') $null (Get-PsaProp $t 'resolved_at') (Get-PsaProp $t 'contact_id')))
                }
                if ($p -ge [int](Get-PsaPath $r 'meta.total_pages')) { break }
            }
        }
        'zendesk' {
            # Zendesk search (vendor docs): status:<name> and updated< / created< with an ISO date.
            # Unverified: organization:<id> as the company filter, so rows are re-checked below. Search stops at 1000 results.
            $query = "type:ticket status:$($StatusName.ToLowerInvariant())"
            if ($CompanyId) { $query += " organization:$([long]$CompanyId)" }
            if ($iso) { $query += $(if ($DateField -eq 'created') { " created<$iso" } else { " updated<$iso" }) }
            if ($isoFrom) { $query += $(if ($DateField -eq 'created') { " created>$isoFrom" } else { " updated>$isoFrom" }) }
            $next = "/search?query=$(ConvertTo-PsaQuery $query)&sort_by=created_at&sort_order=asc&per_page=100"
            for ($p = 1; $p -le 10 -and $next -and (& $more); $p++) {
                $r = Invoke-Psa GET $next
                foreach ($t in @(Get-PsaProp $r 'results' | Where-Object { $null -ne $_ })) {
                    $null = $rows.Add((New-PsaTicketRow $t (Get-PsaProp $t 'id') (Get-PsaProp $t 'id') (Get-PsaProp $t 'subject') (Get-PsaProp $t 'organization_id') '' (Get-PsaProp $t 'status') (Get-PsaProp $t 'priority') (Get-PsaProp $t 'created_at') (Get-PsaProp $t 'updated_at') $null $null (Get-PsaProp $t 'requester_id')))
                }
                $next = [string](Get-PsaProp $r 'next_page')
            }
        }
    }
    $out = @($rows | Where-Object { & $keepRow $_ })
    return @($out | Select-Object -First $want)
}

# The ticket's notes, oldest first: @(@{ id; text; created; internal; fromClient; author }).
function Get-PsaTicketNotes {
    param([string]$Id, $Ticket = $null)
    $c = Get-PsaConn
    $notes = New-Object System.Collections.ArrayList
    $add = { param($nid, $text, $created, $internal, $fromClient, $author) $null = $notes.Add(@{ id = [string]$nid; text = [string]$text; created = (ConvertTo-PsaDate $created); internal = [bool]$internal; fromClient = [bool]$fromClient; author = [string]$author }) }
    switch ($c.Psa) {
        'connectwise' {
            # Notes from the ticket's Discussion and Internal tabs. Unverified: a note with a contact and no member
            # is treated as written by the client.
            foreach ($n in @(Invoke-Psa GET "/service/tickets/$Id/notes?orderBy=$(ConvertTo-PsaQuery 'id desc')&pageSize=100" | Where-Object { $null -ne $_ })) {
                $member = Get-PsaProp $n 'member'; $contact = Get-PsaProp $n 'contact'
                $internal = ((Get-PsaProp $n 'internalAnalysisFlag') -eq $true -and (Get-PsaProp $n 'detailDescriptionFlag') -ne $true)
                & $add (Get-PsaProp $n 'id') (Get-PsaProp $n 'text') (Get-PsaFirst $n @('dateCreated', '_info.dateEntered', '_info.lastUpdated')) $internal ($null -ne $contact -and $null -eq $member) ([string](Get-PsaFirst $n @('member.identifier', 'contact.name', 'createdBy')))
            }
        }
        'autotask' {
            # Unverified: TicketNotes query by ticketID; createdByContactID set means the client wrote it.
            $internalIds = @(Get-PsaAtPicklist 'TicketNotes' 'publish' | Where-Object { [string](Get-PsaProp $_ 'label') -match '(?i)internal' } | ForEach-Object { [string](Get-PsaProp $_ 'value') })
            $s = [ordered]@{ filter = @([ordered]@{ op = 'eq'; field = 'ticketID'; value = [long]$Id }); MaxRecords = 500 }
            $r = Invoke-Psa GET "/TicketNotes/query?search=$(ConvertTo-PsaQuery ($s | ConvertTo-Json -Depth 6 -Compress))"
            foreach ($n in @(Get-PsaProp $r 'items' | Where-Object { $null -ne $_ })) {
                $byContact = Get-PsaProp $n 'createdByContactID'
                & $add (Get-PsaProp $n 'id') (Get-PsaProp $n 'description') (Get-PsaFirst $n @('createDateTime', 'lastActivityDate')) ([string](Get-PsaProp $n 'publish') -in $internalIds) (-not (Test-PsaBlank $byContact)) ([string](Get-PsaFirst $n @('creatorResourceID', 'createdByContactID')))
            }
        }
        'halopsa' {
            # Unverified: GET /api/Actions?ticket_id= returns { actions }; who_type 2 is taken to mean the end user wrote it.
            $r = Invoke-Psa GET "/Actions?ticket_id=$Id&excludesys=true&count=200"
            $rows = @(Get-PsaProp $r 'actions'); if (-not @($rows | Where-Object { $null -ne $_ }).Count -and $r -is [array]) { $rows = @($r) }
            foreach ($n in @($rows | Where-Object { $null -ne $_ })) {
                & $add (Get-PsaProp $n 'id') (Get-PsaFirst $n @('note', 'note_html')) (Get-PsaFirst $n @('datetime', 'actiondatecreated')) ((Get-PsaProp $n 'hiddenfromuser') -eq $true) ([string](Get-PsaProp $n 'who_type') -eq '2') ([string](Get-PsaProp $n 'who'))
            }
        }
        'kaseyabms' {
            # From the BMS swagger: GET /v2/servicedesk/tickets/{id}/notes returns { Result: [{ Id, Details, CreatedOn,
            # IsInternal, CreatedByName, CreatedByEmail }] }. It doesn't say whether the client wrote a note, so fromClient is false.
            $r = Invoke-Psa GET "/servicedesk/tickets/$Id/notes?PageSize=200"
            foreach ($n in @(Get-PsaProp $r 'Result' | Where-Object { $null -ne $_ })) {
                & $add (Get-PsaProp $n 'Id') (Get-PsaProp $n 'Details') (Get-PsaProp $n 'CreatedOn') ((Get-PsaProp $n 'IsInternal') -eq $true) $false ([string](Get-PsaProp $n 'CreatedByName'))
            }
        }
        'syncro' {
            # The ticket carries its comments (Syncro swagger). Unverified: a visible comment with no user_id is the client's.
            $t = Get-PsaProp (Invoke-Psa GET "/tickets/$Id") 'ticket'
            foreach ($n in @(Get-PsaProp $t 'comments' | Where-Object { $null -ne $_ })) {
                $hidden = (Get-PsaProp $n 'hidden') -eq $true
                & $add (Get-PsaProp $n 'id') (Get-PsaProp $n 'body') (Get-PsaProp $n 'created_at') $hidden ((-not $hidden) -and (Test-PsaBlank (Get-PsaProp $n 'user_id'))) ([string](Get-PsaProp $n 'tech'))
            }
        }
        'zendesk' {
            # GET /tickets/{id}/comments (vendor docs). The client wrote it when the author is the ticket's requester.
            $req = if ($null -ne $Ticket) { [string](Get-PsaProp $Ticket 'requesterId') } else { '' }
            if (-not $req) { $req = [string](Get-PsaPath (Invoke-Psa GET "/tickets/$Id") 'ticket.requester_id') }
            $r = Invoke-Psa GET "/tickets/$Id/comments?sort_order=desc&per_page=100"
            foreach ($n in @(Get-PsaProp $r 'comments' | Where-Object { $null -ne $_ })) {
                $author = [string](Get-PsaProp $n 'author_id')
                & $add (Get-PsaProp $n 'id') (Get-PsaProp $n 'body') (Get-PsaProp $n 'created_at') ((Get-PsaProp $n 'public') -eq $false) ($req -and $author -eq $req) $author
            }
        }
    }
    return @($notes | Sort-Object { if ($null -eq $_.created) { [datetime]::MinValue } else { $_.created } })
}

# Closes a ticket to -StatusName, or to the PSA's usual closed status, and never to -NotStatus (for example
# the Resolved status a ticket is already in). Returns the status that was set.
function Close-PsaTicket {
    param([string]$Id, [string]$StatusName = '', [string]$NotStatus = '')
    $c = Get-PsaConn
    $StatusName = ([string]$StatusName).Trim(); $NotStatus = ([string]$NotStatus).Trim()
    if ($StatusName -and $NotStatus -and $StatusName -ieq $NotStatus) { throw "The closing status '$StatusName' is the status the ticket is already in. Choose a different closing status." }
    switch ($c.Psa) {
        'connectwise' {
            if ($StatusName) { return (Set-PsaStatus -Id $Id -StatusName $StatusName) }
            # Unverified (as Set-PsaStatus): the board's statuses with closedStatus set; skips -NotStatus.
            $t = Invoke-Psa GET "/service/tickets/$Id"
            $boardId = Get-PsaPath $t 'board.id'
            if (Test-PsaBlank $boardId) { throw "ConnectWise ticket $Id has no board, so its statuses can't be read." }
            $all = @(Invoke-Psa GET "/service/boards/$boardId/statuses?pageSize=200" | Where-Object { $null -ne $_ -and (Get-PsaProp $_ 'inactive') -ne $true -and (Get-PsaProp $_ 'closedStatus') -eq $true -and ([string](Get-PsaProp $_ 'name')).Trim() -ine $NotStatus })
            $st = Select-PsaByLabel $all 'name' @('(?i)^\W*closed\W*$', '(?i)closed', '(?i)complete', '(?i)resolved', '.')
            if (-not $st) { throw "ConnectWise board $boardId has no closed status other than '$NotStatus'. Set close_status_name." }
            return (Set-PsaStatus -Id $Id -StatusName ([string](Get-PsaProp $st 'name')))
        }
        'autotask' {
            if (-not $StatusName -and $NotStatus -imatch '^complete$') { throw "'$NotStatus' is already Autotask's closed status. Set close_status_name." }
            if ($StatusName) { return (Set-PsaStatus -Id $Id -StatusName $StatusName) }
            return (Set-PsaStatus -Id $Id -State closed)
        }
        { $_ -in @('halopsa', 'kaseyabms') } {
            if ($StatusName) { return (Set-PsaStatus -Id $Id -StatusName (Get-PsaStatusId $StatusName)) }
            return (Set-PsaStatus -Id $Id -State closed)
        }
        'syncro' {
            # Unverified (as Set-PsaStatus): Resolved is Syncro's default closed label.
            $target = if ($StatusName) { $StatusName } else { 'Resolved' }
            if ($target -ieq $NotStatus) { throw "In Syncro, '$NotStatus' is already the closed status, so there is nothing to close. Set close_status_name, or use a different status for tickets waiting to be closed." }
            return (Set-PsaStatus -Id $Id -StatusName $target)
        }
        'zendesk' {
            # Unverified: setting status closed through the API. Zendesk otherwise closes solved tickets on its own schedule.
            $target = if ($StatusName) { $StatusName.ToLowerInvariant() } elseif ($NotStatus -ieq 'solved') { 'closed' } else { 'solved' }
            return (Set-PsaStatus -Id $Id -StatusName $target)
        }
    }
}
# ---------- end src/psa-extra.ps1 ----------
