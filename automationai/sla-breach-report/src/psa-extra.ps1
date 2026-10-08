# ---------- psa-extra.ps1: ticket lists, SLA targets, queue moves and note reads for six PSAs ----------
# ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk. Needs _shared/psa.ps1 pasted above it
# (it uses Get-PsaConn, Invoke-Psa, Get-PsaProp, Get-PsaPath, Get-PsaAtPicklist and $PsaState).
# The same file ships in automationai/sla-breach-report/src and automationai/auto-escalation/src. Keep the
# two copies identical. It is a candidate to move into automationai/_shared/psa.ps1.
# Every call marked "Unverified" is not in reference/build-kit/PSA.md yet. Check it against a real tenant
# before relying on it, then record it in PSA.md.
#
#   Find-PsaTickets [-UpdatedBefore <datetime>] [-Status <string[]>] [-Max <int>] [-IncludeClosed]
#       Open tickets (by default), optionally only those last updated before a time or in named statuses.
#       Returns @(@{ id; number; summary; companyId; companyName; status; priority; priorityLabel; queueId;
#       queueName; assigneeId; assigneeName; created; updated; raw }). priority is critical, high, medium,
#       low or ''. created and updated are UTC [datetime] values (updated falls back to created).
#   Resolve-PsaTicketNames -Tickets <rows>   fills blank company, technician, queue and status names (cached).
#   Get-PsaTicketSla -Ticket <row>
#       The PSA's own SLA target: @{ source ('psa' or 'none'); kind ('respond', 'resolve' or 'due'); start;
#       target; breached ($true when the PSA itself says the SLA was missed, else $null); detail }.
#       source 'psa' with no target means the PSA's SLA clock is paused or already met.
#   Set-PsaQueue -Id <string> -Queue <string>   moves a ticket to another board, queue, team or group.
#   Get-PsaTicketNotes -Id <string>   @(@{ text; internal; created }), newest first where the PSA sorts.
#   Get-PsaDefaultRole -UserId <string>   Autotask: the resource's default Service Desk role id, for Set-PsaAssignee.
#       Other PSAs don't need a role and get ''.

$PsaExtraState = @{ Names = @{}; Sla = @{}; MaxPages = 50 }

# A UTC [datetime], or $null for blank, unparseable or placeholder dates (HaloPSA sends 1900-01-01 for none).
function ConvertTo-PsaDate {
    param($Value)
    if ($null -eq $Value) { return $null }
    $d = [datetime]::MinValue
    if ($Value -is [datetime]) { $d = $Value }
    elseif ($Value -is [datetimeoffset]) { $d = $Value.UtcDateTime }
    else {
        $s = ([string]$Value).Trim()
        if (-not $s) { return $null }
        $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
        if (-not [datetime]::TryParse($s, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$d)) { return $null }
    }
    if ($d.Kind -eq [DateTimeKind]::Local) { $d = $d.ToUniversalTime() }
    elseif ($d.Kind -eq [DateTimeKind]::Unspecified) { $d = [datetime]::SpecifyKind($d, [DateTimeKind]::Utc) }
    if ($d.Year -lt 1971) { return $null }
    return $d
}

# critical, high, medium or low for a PSA priority label ('' when it matches none).
function Get-PsaPriorityClass {
    param([string]$Label)
    if ([string]::IsNullOrWhiteSpace($Label)) { return '' }
    foreach ($k in @('critical', 'high', 'medium', 'low')) { foreach ($p in $PsaState.PriorityPatterns[$k]) { if ($Label -match $p) { return $k } } }
    return ''
}

function New-PsaTicketRow {
    param($Id, $Number, $Summary, $CompanyId, $CompanyName, $Status, $PriorityLabel, $QueueId, $QueueName, $AssigneeId, $AssigneeName, $Created, $Updated, $Raw)
    $cr = ConvertTo-PsaDate $Created
    $up = ConvertTo-PsaDate $Updated
    if ($null -eq $up) { $up = $cr }
    $blank = { param($v) if (Test-PsaBlank $v) { '' } else { [string]$v } }
    return @{
        id = [string]$Id; number = $(if (Test-PsaBlank $Number) { [string]$Id } else { [string]$Number }); summary = [string]$Summary
        companyId = (& $blank $CompanyId); companyName = [string]$CompanyName; status = [string]$Status
        priority = (Get-PsaPriorityClass ([string]$PriorityLabel)); priorityLabel = [string]$PriorityLabel
        queueId = (& $blank $QueueId); queueName = [string]$QueueName
        assigneeId = (& $blank $AssigneeId); assigneeName = [string]$AssigneeName
        created = $cr; updated = $up; raw = $Raw
    }
}

# A 403 on a read becomes a plain sentence about the API user's permissions.
function Invoke-PsaRead {
    param([string]$Path, [string]$What)
    try { return Invoke-Psa GET $Path }
    catch {
        $m = [string]$_.Exception.Message
        if ($m -match '\(HTTP 403\)') { throw "$(Get-PsaName) refused to $What (HTTP 403). Give the API user permission to read service tickets and their notes, then run this again." }
        throw
    }
}

# Kaseya BMS list replies are {Success, Result}; Result may be the list or hold it. Unverified: the list shape.
function Get-PsaBmsList {
    param($Reply)
    $res = Get-PsaProp $Reply 'Result'
    if ($null -eq $res) { return @() }
    if ($res -is [array]) { return @($res | Where-Object { $null -ne $_ }) }
    foreach ($n in @('Items', 'Data', 'Tickets', 'Records')) { $v = Get-PsaProp $res $n; if ($null -ne $v) { return @($v | Where-Object { $null -ne $_ }) } }
    return @($res)
}

function Find-PsaTickets {
    param($UpdatedBefore = $null, [string[]]$Status = @(), [int]$Max = 500, [switch]$IncludeClosed)
    $c = Get-PsaConn
    $cut = ConvertTo-PsaDate $UpdatedBefore
    $iso = if ($cut) { $cut.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { '' }
    $want = @($Status | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
    if ($Max -lt 1) { $Max = 1 }
    $found = New-Object System.Collections.ArrayList
    $what = 'list tickets'
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: the lastUpdated condition with a [date] literal (CW conditions syntax) and the list fields used.
            $conds = @(); if (-not $IncludeClosed) { $conds += 'closedFlag=false' }
            if ($iso) { $conds += "lastUpdated < [$iso]" }
            if ($want.Count -eq 1) { $conds += ('status/name="' + $Status[0].Trim().Replace('"', '\"') + '"') }
            $cq = if ($conds.Count) { "conditions=$(ConvertTo-PsaQuery ($conds -join ' and '))&" } else { '' }
            for ($p = 1; $p -le $PsaExtraState.MaxPages; $p++) {
                $page = @(Invoke-PsaRead "/service/tickets?$($cq)orderBy=$(ConvertTo-PsaQuery 'id asc')&pageSize=100&page=$p" $what | Where-Object { $null -ne $_ })
                foreach ($t in $page) {
                    $null = $found.Add((New-PsaTicketRow (Get-PsaProp $t 'id') $null (Get-PsaProp $t 'summary') (Get-PsaPath $t 'company.id') (Get-PsaPath $t 'company.name') (Get-PsaPath $t 'status.name') (Get-PsaPath $t 'priority.name') (Get-PsaPath $t 'board.id') (Get-PsaPath $t 'board.name') $(if (Get-PsaPath $t 'owner.identifier') { Get-PsaPath $t 'owner.identifier' } else { Get-PsaPath $t 'owner.id' }) (Get-PsaPath $t 'owner.name') (Get-PsaPath $t '_info.dateEntered') (Get-PsaPath $t '_info.lastUpdated') $t))
                }
                if ($page.Count -lt 100 -or $found.Count -ge $Max) { break }
            }
        }
        'autotask' {
            # Unverified: lastActivityDate as the "last touched" field, and the SLA due-date fields read later.
            $f = @()
            if (-not $IncludeClosed) { foreach ($v in @(Get-PsaAtCompleteStatuses)) { $f += [ordered]@{ op = 'noteq'; field = 'status'; value = $v } } }
            if ($iso) { $f += [ordered]@{ op = 'lt'; field = 'lastActivityDate'; value = $iso } }
            if (-not $f.Count) { $f += [ordered]@{ op = 'gt'; field = 'id'; value = 0 } }
            $path = "/Tickets/query?search=$(ConvertTo-PsaQuery (@{ filter = $f; MaxRecords = 500 } | ConvertTo-Json -Depth 6 -Compress))"
            $statusVals = @(Get-PsaAtPicklist 'Tickets' 'status'); $prioVals = @(Get-PsaAtPicklist 'Tickets' 'priority'); $queueVals = @(Get-PsaAtPicklist 'Tickets' 'queueID')
            $label = { param($vals, $v) $h = @($vals | Where-Object { [string](Get-PsaProp $_ 'value') -eq [string]$v }) | Select-Object -First 1; if ($h) { [string](Get-PsaProp $h 'label') } else { '' } }
            for ($p = 1; $p -le $PsaExtraState.MaxPages -and $path; $p++) {
                $r = Invoke-PsaRead $path $what
                foreach ($t in @(Get-PsaProp $r 'items' | Where-Object { $null -ne $_ })) {
                    $st = Get-PsaProp $t 'status'; $pr = Get-PsaProp $t 'priority'; $q = Get-PsaProp $t 'queueID'
                    $null = $found.Add((New-PsaTicketRow (Get-PsaProp $t 'id') (Get-PsaProp $t 'ticketNumber') (Get-PsaProp $t 'title') (Get-PsaProp $t 'companyID') '' $(& $label $statusVals $st) $(& $label $prioVals $pr) $q $(& $label $queueVals $q) (Get-PsaProp $t 'assignedResourceID') '' (Get-PsaProp $t 'createDate') (Get-PsaProp $t 'lastActivityDate') $t))
                }
                $path = [string](Get-PsaPath $r 'pageDetails.nextPageUrl')
                if ($found.Count -ge $Max) { break }
            }
        }
        'halopsa' {
            # Unverified: list paging (pageinate, page_size, page_no), lastactiondate, and status_name/team/agent_name on list rows.
            $open = if ($IncludeClosed) { '' } else { 'open_only=true&' }
            for ($p = 1; $p -le $PsaExtraState.MaxPages; $p++) {
                $r = Invoke-PsaRead "/Tickets?$($open)pageinate=true&page_size=100&page_no=$p&order=id" $what
                $page = @(Get-PsaProp $r 'tickets' | Where-Object { $null -ne $_ })
                foreach ($t in $page) {
                    $pid0 = Get-PsaProp $t 'priority_id'
                    $plabel = [string](Get-PsaProp $t 'priority_name'); if (-not $plabel -and -not (Test-PsaBlank $pid0)) { $plabel = "P$pid0" }
                    $sname = [string](Get-PsaProp $t 'status_name'); if (-not $sname) { $sname = "Status $(Get-PsaProp $t 'status_id')" }
                    $upd = Get-PsaProp $t 'lastactiondate'; if (-not (ConvertTo-PsaDate $upd)) { $upd = Get-PsaProp $t 'last_update' }
                    $null = $found.Add((New-PsaTicketRow (Get-PsaProp $t 'id') $null (Get-PsaProp $t 'summary') (Get-PsaProp $t 'client_id') (Get-PsaProp $t 'client_name') $sname $plabel (Get-PsaProp $t 'team_id') (Get-PsaProp $t 'team') (Get-PsaProp $t 'agent_id') (Get-PsaProp $t 'agent_name') (Get-PsaProp $t 'dateoccurred') $upd $t))
                }
                $total = Get-PsaProp $r 'record_count'
                if ($page.Count -lt 100 -or ($null -ne $total -and $p * 100 -ge [int]$total) -or $found.Count -ge $Max) { break }
            }
        }
        'kaseyabms' {
            # Unverified: list paging (PageNumber, PageSize), the reply shape and every field name below. Open/closed is read from the status name.
            for ($p = 1; $p -le $PsaExtraState.MaxPages; $p++) {
                $page = @(Get-PsaBmsList (Invoke-PsaRead "/servicedesk/tickets?PageNumber=$p&PageSize=100" $what))
                foreach ($t in $page) {
                    $sname = [string](Get-PsaProp $t 'StatusName')
                    if (-not $IncludeClosed -and $sname -match '(?i)complete|closed|resolved|cancel') { continue }
                    $upd = $null; foreach ($n in @('LastActivityUpdate', 'LastModifiedDate', 'ModifiedOn', 'UpdatedOn')) { if (ConvertTo-PsaDate (Get-PsaProp $t $n)) { $upd = Get-PsaProp $t $n; break } }
                    $null = $found.Add((New-PsaTicketRow (Get-PsaProp $t 'Id') (Get-PsaProp $t 'TicketNumber') (Get-PsaProp $t 'Title') (Get-PsaProp $t 'AccountId') (Get-PsaProp $t 'AccountName') $sname (Get-PsaProp $t 'PriorityName') (Get-PsaProp $t 'QueueId') (Get-PsaProp $t 'QueueName') (Get-PsaProp $t 'AssigneeId') (Get-PsaProp $t 'AssigneeName') (Get-PsaProp $t 'OpenDate') $upd $t))
                }
                if ($page.Count -lt 100 -or $found.Count -ge $Max) { break }
            }
        }
        'syncro' {
            # Unverified: customer_business_then_name, priority, updated_at and due_date on list rows (status "Not Closed" is in PSA.md).
            $st = if ($IncludeClosed) { '' } else { "status=$(ConvertTo-PsaQuery 'Not Closed')&" }
            for ($p = 1; $p -le $PsaExtraState.MaxPages; $p++) {
                $r = Invoke-PsaRead "/tickets?$($st)page=$p" $what
                foreach ($t in @(Get-PsaProp $r 'tickets' | Where-Object { $null -ne $_ })) {
                    $null = $found.Add((New-PsaTicketRow (Get-PsaProp $t 'id') (Get-PsaProp $t 'number') (Get-PsaProp $t 'subject') (Get-PsaProp $t 'customer_id') (Get-PsaProp $t 'customer_business_then_name') (Get-PsaProp $t 'status') (Get-PsaProp $t 'priority') '' (Get-PsaProp $t 'problem_type') (Get-PsaProp $t 'user_id') (Get-PsaPath $t 'user.full_name') (Get-PsaProp $t 'created_at') (Get-PsaProp $t 'updated_at') $t))
                }
                $pages = Get-PsaPath $r 'meta.total_pages'
                if ($null -eq $pages -or $p -ge [int]$pages -or $found.Count -ge $Max) { break }
            }
        }
        'zendesk' {
            # Unverified: the updated< search with a time, and sideloading SLAs with include=tickets(slas) on search.
            $q = 'type:ticket'; if (-not $IncludeClosed) { $q += ' status<solved' }; if ($iso) { $q += " updated<$iso" }
            $path = "/search?query=$(ConvertTo-PsaQuery $q)&sort_by=updated_at&sort_order=asc&per_page=100&include=$(ConvertTo-PsaQuery 'tickets(slas)')"
            for ($p = 1; $p -le 10 -and $path; $p++) {
                $r = Invoke-PsaRead $path $what
                foreach ($t in @(Get-PsaProp $r 'results' | Where-Object { $null -ne $_ })) {
                    $null = $found.Add((New-PsaTicketRow (Get-PsaProp $t 'id') $null (Get-PsaProp $t 'subject') (Get-PsaProp $t 'organization_id') '' (Get-PsaProp $t 'status') (Get-PsaProp $t 'priority') (Get-PsaProp $t 'group_id') '' (Get-PsaProp $t 'assignee_id') '' (Get-PsaProp $t 'created_at') (Get-PsaProp $t 'updated_at') $t))
                }
                $path = [string](Get-PsaProp $r 'next_page')
                if ($found.Count -ge $Max) { break }
            }
        }
    }
    # The same filters again here, for the PSAs that can't filter on the server.
    $out = @($found | Where-Object {
            (-not $cut -or ($null -ne $_.updated -and $_.updated -lt $cut)) -and
            (-not $want.Count -or $want -contains $_.status.Trim().ToLowerInvariant())
        })
    return @($out | Select-Object -First $Max)
}

# Fills blank company, technician, queue and status names, one lookup per id. A failed lookup leaves an id-based name.
function Resolve-PsaTicketNames {
    param($Tickets)
    $c = Get-PsaConn
    $cache = $PsaExtraState.Names
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
    foreach ($t in @($Tickets)) {
        if ($null -eq $t) { continue }
        if (-not $t.companyName) { $t.companyName = & $look 'company' $t.companyId; if (-not $t.companyName) { $t.companyName = $(if ($t.companyId) { "Company $($t.companyId)" } else { 'No company' }) } }
        if (-not $t.assigneeName) { $t.assigneeName = & $look 'user' $t.assigneeId; if (-not $t.assigneeName) { $t.assigneeName = $(if ($t.assigneeId) { "Technician $($t.assigneeId)" } else { 'Unassigned' }) } }
        if (-not $t.queueName -and $t.queueId) { $t.queueName = & $look 'queue' $t.queueId; if (-not $t.queueName) { $t.queueName = "Queue $($t.queueId)" } }
    }
}

# ConnectWise SLA hours for one SLA and priority, cached. Unverified: /service/SLAs/{id} and its /priorities
# (respondHours, resolutionHours). Wall-clock hours: CW applies business hours, so treat the result as approximate.
function Get-PsaCwSlaHours {
    param([string]$SlaId, [string]$PriorityId)
    $key = "cw:$SlaId"
    if (-not $PsaExtraState.Sla.ContainsKey($key)) {
        $base = Invoke-Psa GET "/service/SLAs/$SlaId"
        $prios = @(); try { $prios = @(Invoke-Psa GET "/service/SLAs/$SlaId/priorities?pageSize=100" | Where-Object { $null -ne $_ }) } catch { }
        $PsaExtraState.Sla[$key] = @{ base = $base; prios = $prios }
    }
    $d = $PsaExtraState.Sla[$key]
    $src = $d.base
    if ($PriorityId) { $hit = @($d.prios | Where-Object { [string](Get-PsaPath $_ 'priority.id') -eq $PriorityId }) | Select-Object -First 1; if ($hit) { $src = $hit } }
    $num = { param($o, $n) $v = Get-PsaProp $o $n; if (Test-PsaBlank $v) { $null } else { [double]$v } }
    return @{ respond = (& $num $src 'respondHours'); resolve = (& $num $src 'resolutionHours') }
}

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

# Moves a ticket to another board (ConnectWise), queue (Autotask, Kaseya BMS), team (HaloPSA), issue type (Syncro)
# or group (Zendesk). -Queue is a name or an id. Throws when the PSA refuses.
function Set-PsaQueue {
    param([string]$Id, [string]$Queue)
    $c = Get-PsaConn
    if ([string]::IsNullOrWhiteSpace($Queue)) { throw 'Set-PsaQueue needs a queue name or id.' }
    $q = $Queue.Trim(); $isNum = $q -match '^\d+$'
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: json-patch on board (a reference, so {id} or {name}). CW may refuse when the status doesn't exist on the new board.
            $val = if ($isNum) { @{ id = [int]$q } } else { @{ name = $q } }
            $null = Invoke-Psa PATCH "/service/tickets/$Id" @([ordered]@{ op = 'replace'; path = 'board'; value = $val })
        }
        'autotask' {
            # Unverified: PATCH /Tickets with queueID (the field at_create_ticket uses).
            $qv = if ($isNum) { $q } else { Select-PsaAtValue (Get-PsaAtPicklist 'Tickets' 'queueID') @("(?i)^$([regex]::Escape($q))$") }
            if ($null -eq $qv) { throw "Autotask has no ticket queue named '$q'." }
            $null = Invoke-Psa PATCH '/Tickets' ([ordered]@{ id = [long]$Id; queueID = [int]$qv })
        }
        'halopsa' {
            # Unverified: team_id or team (name) on the POST /Tickets update.
            $b = [ordered]@{ id = [long]$Id }; if ($isNum) { $b.team_id = [long]$q } else { $b.team = $q }
            $null = Invoke-Psa POST '/Tickets' @($b)
        }
        'kaseyabms' {
            # Unverified: json-patch on /QueueId.
            if (-not $isNum) { throw 'Kaseya BMS needs a numeric queue id.' }
            $null = Invoke-Psa PATCH "/servicedesk/tickets/$Id" @([ordered]@{ op = 'replace'; path = '/QueueId'; value = [int]$q })
        }
        'syncro' {
            # Unverified: Syncro has no queues; the issue type (problem_type) is the closest field.
            $null = Invoke-Psa PUT "/tickets/$Id" @{ problem_type = $q }
        }
        'zendesk' {
            # group_id on PUT /tickets is in PSA.md. Unverified: the GET /groups name lookup.
            $gid = $q
            if (-not $isNum) {
                $g = @(Get-PsaProp (Invoke-Psa GET '/groups?per_page=100') 'groups' | Where-Object { $null -ne $_ -and [string](Get-PsaProp $_ 'name') -ieq $q }) | Select-Object -First 1
                if (-not $g) { throw "Zendesk has no group named '$q'." }
                $gid = [string](Get-PsaProp $g 'id')
            }
            $null = Invoke-Psa PUT "/tickets/$Id" @{ ticket = @{ group_id = [long]$gid } }
        }
    }
}

# The ticket's notes: @(@{ text; internal; created }).
function Get-PsaTicketNotes {
    param([string]$Id)
    $c = Get-PsaConn
    $what = "read the notes on ticket $Id"
    $rows = @(); $tp = 'text'; $ip = ''; $dp = 'created'; $flip = $false
    switch ($c.Psa) {
        'connectwise' { $rows = @(Invoke-PsaRead "/service/tickets/$Id/notes?orderBy=$(ConvertTo-PsaQuery 'id desc')&pageSize=100" $what); $ip = 'internalAnalysisFlag'; $dp = 'dateCreated' }
        'autotask' {
            # Unverified: TicketNotes query by ticketID; "internal" is read from the publish label.
            $s = @{ filter = @([ordered]@{ op = 'eq'; field = 'ticketID'; value = [long]$Id }) }
            $rows = @(Get-PsaProp (Invoke-PsaRead "/TicketNotes/query?search=$(ConvertTo-PsaQuery ($s | ConvertTo-Json -Depth 5 -Compress))" $what) 'items'); $tp = 'description'; $dp = 'createDateTime'
            $pubVals = @(Get-PsaAtPicklist 'TicketNotes' 'publish')
            return @($rows | Where-Object { $null -ne $_ } | ForEach-Object {
                    $pv = [string](Get-PsaProp $_ 'publish'); $pl = @($pubVals | Where-Object { [string](Get-PsaProp $_ 'value') -eq $pv }) | Select-Object -First 1
                    @{ text = [string](Get-PsaProp $_ 'description'); internal = ([string](Get-PsaProp $pl 'label') -match '(?i)internal'); created = (ConvertTo-PsaDate (Get-PsaProp $_ 'createDateTime')) }
                })
        }
        'halopsa' { $rows = @(Get-PsaProp (Invoke-PsaRead "/Actions?ticket_id=$Id&count=100" $what) 'actions'); $tp = 'note'; $ip = 'hiddenfromuser'; $dp = 'datetime' }   # Unverified
        'kaseyabms' { $rows = @(Get-PsaBmsList (Invoke-PsaRead "/servicedesk/tickets/$Id/notes" $what)); $tp = 'Details'; $ip = 'IsInternal'; $dp = 'NoteDate' }      # Unverified
        'syncro' { $rows = @(Get-PsaPath (Invoke-PsaRead "/tickets/$Id" $what) 'ticket.comments'); $tp = 'body'; $ip = 'hidden'; $dp = 'created_at' }
        'zendesk' { $rows = @(Get-PsaProp (Invoke-PsaRead "/tickets/$Id/comments" $what) 'comments'); $tp = 'body'; $ip = 'public'; $dp = 'created_at'; $flip = $true }  # Unverified
    }
    return @($rows | Where-Object { $null -ne $_ } | ForEach-Object {
            $iv = [bool](Get-PsaProp $_ $ip); if ($flip) { $iv = -not $iv }
            @{ text = [string](Get-PsaProp $_ $tp); internal = $iv; created = (ConvertTo-PsaDate (Get-PsaProp $_ $dp)) }
        })
}
# Autotask assigns a resource together with a role. Returns the resource's default Service Desk role, or ''.
function Get-PsaDefaultRole {
    param([string]$UserId)
    $c = Get-PsaConn
    if ($c.Psa -ne 'autotask' -or [string]::IsNullOrWhiteSpace($UserId)) { return '' }
    # Unverified: defaultServiceDeskRoleID on the Resources entity.
    $v = Get-PsaPath (Invoke-Psa GET "/Resources/$UserId") 'item.defaultServiceDeskRoleID'
    if (Test-PsaBlank $v) { return '' }
    return [string]$v
}
# ---------- end psa-extra.ps1 ----------
