# ---------- psa-extra.ps1: PSA calls that _shared/psa.ps1 doesn't have yet ----------
# Ticket lists, time entries, agreements, invoices and ticket relations for the six PSAs
# (ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk).
# Needs _shared/psa.ps1 pasted above it (Connect-Psa, Invoke-Psa, Get-PsaProp and friends).
# The same file ships in automationai/related-ticket-detection/src and automationai/invoice-context/src.
# It is a candidate to move into automationai/_shared once these calls are proven live.
# None of these calls is in reference/build-kit/PSA.md yet. Each one carries an "Unverified" comment
# saying what to check against a real tenant before relying on it.
# State lives in $PsaExtraState (changed in place), never in $script: variables.

$PsaExtraState = @{
    Warnings = (New-Object System.Collections.ArrayList)
    MaxPages = 10
    MaxTicketLoop = 50
}

# What the connected PSA can do here. A value of $false means the function returns nothing. An empty list
# and "not supported" look the same to a caller (PowerShell unrolls an empty array), so check this first.
#   relation: 'native' (always a real link), 'conditional' (a real link only when the other
#   ticket is a Problem ticket), or 'note' (cross-reference notes only).
function Get-PsaExtraSupport {
    $c = Get-PsaConn
    switch ($c.Psa) {
        'connectwise' { return @{ tickets = $true; time = $true; agreements = $true; invoices = $true; relation = 'note' } }
        'autotask' { return @{ tickets = $true; time = $true; agreements = $true; invoices = $true; relation = 'conditional' } }
        'halopsa' { return @{ tickets = $true; time = $true; agreements = $true; invoices = $true; relation = 'native' } }
        'kaseyabms' { return @{ tickets = $true; time = $true; agreements = $true; invoices = $false; relation = 'note' } }
        'syncro' { return @{ tickets = $true; time = $true; agreements = $true; invoices = $false; relation = 'note' } }
        'zendesk' { return @{ tickets = $true; time = $false; agreements = $false; invoices = $false; relation = 'conditional' } }
    }
}

function Add-PsaExtraWarning { param([string]$Text) if (-not $PsaExtraState.Warnings.Contains($Text)) { $null = $PsaExtraState.Warnings.Add($Text) } }

# A date from any PSA field (string, DateTime or blank) as UTC, or $null.
function ConvertTo-PsaDate {
    param($v)
    if ($null -eq $v) { return $null }
    if ($v -is [datetime]) { if ($v.Kind -eq [DateTimeKind]::Unspecified) { return [datetime]::SpecifyKind($v, [DateTimeKind]::Utc) }; return $v.ToUniversalTime() }
    $s = ([string]$v).Trim(); if (-not $s) { return $null }
    $d = [datetime]::MinValue
    if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, ([System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal), [ref]$d)) { return $d }
    return $null
}
function Format-PsaDate { param([datetime]$d) return $d.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
function Get-PsaNumber { param($v) if (Test-PsaBlank $v) { return 0.0 }; $n = 0.0; if ([double]::TryParse([string]$v, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return $n }; return 0.0 }
# The first property of $o that has a value, from a list of names.
function Get-PsaFirst { param($o, [string[]]$Names) foreach ($n in $Names) { $v = Get-PsaPath $o $n; if (-not (Test-PsaBlank $v)) { return $v } }; return $null }

# Autotask query with paging. Returns the items (up to $Max).
function Invoke-PsaAtQuery {
    param([string]$Entity, [object[]]$Filter, [string[]]$Fields = @(), [int]$Max = 500)
    $s = [ordered]@{ filter = @($Filter); MaxRecords = [Math]::Min(500, [Math]::Max(1, $Max)) }
    if ($Fields.Count) { $s.IncludeFields = $Fields }
    $path = "/$Entity/query?search=$(ConvertTo-PsaQuery ($s | ConvertTo-Json -Depth 8 -Compress))"
    $out = New-Object System.Collections.ArrayList
    for ($p = 1; $p -le $PsaExtraState.MaxPages -and $path; $p++) {
        $r = Invoke-Psa GET $path
        foreach ($i in @(Get-PsaProp $r 'items' | Where-Object { $null -ne $_ })) { $null = $out.Add($i) }
        if ($out.Count -ge $Max) { break }
        $path = [string](Get-PsaPath $r 'pageDetails.nextPageUrl')
    }
    return @($out | Select-Object -First $Max)
}

# ConnectWise list with paging (pageSize/page).
function Invoke-PsaCwList {
    param([string]$Path, [int]$Max = 200, [int]$PageSize = 100)
    $out = New-Object System.Collections.ArrayList
    $sep = if ($Path.Contains('?')) { '&' } else { '?' }
    for ($p = 1; $p -le $PsaExtraState.MaxPages; $p++) {
        $rows = @(Invoke-Psa GET "$Path$($sep)pageSize=$PageSize&page=$p" | Where-Object { $null -ne $_ })
        foreach ($r in $rows) { $null = $out.Add($r) }
        if ($rows.Count -lt $PageSize -or $out.Count -ge $Max) { break }
    }
    return @($out | Select-Object -First $Max)
}

# A ticket number as the PSA's internal id. ConnectWise, HaloPSA and Zendesk show the id itself.
# Autotask and Kaseya BMS show numbers like T20261008.0001; Syncro shows a number that differs from its id.
function Resolve-PsaTicketId {
    param([string]$Ref)
    $c = Get-PsaConn
    $r = ([string]$Ref).Trim().TrimStart('#')
    if (-not $r) { throw 'No ticket number was given.' }
    switch ($c.Psa) {
        'autotask' {
            if ($r -match '^\d+$') { return $r }
            # Unverified: querying Tickets by ticketNumber.
            $hit = @(Invoke-PsaAtQuery 'Tickets' @([ordered]@{ op = 'eq'; field = 'ticketNumber'; value = $r }) @('id', 'ticketNumber') 1) | Select-Object -First 1
            if (-not $hit) { throw "Autotask has no ticket $r." }
            return [string](Get-PsaProp $hit 'id')
        }
        'kaseyabms' {
            if ($r -match '^\d+$') { return $r }
            # Unverified: the Filter.TicketNumber list filter and the Result envelope.
            $res = Get-PsaProp (Invoke-Psa GET "/servicedesk/tickets?Filter.TicketNumber=$(ConvertTo-PsaQuery $r)&PageSize=5") 'Result'
            $items = @(if ($null -ne (Get-PsaProp $res 'Items')) { Get-PsaProp $res 'Items' } else { $res })
            $hit = @($items | Where-Object { $null -ne $_ -and [string](Get-PsaProp $_ 'TicketNumber') -eq $r }) | Select-Object -First 1
            if (-not $hit) { throw "Kaseya BMS has no ticket $r." }
            return [string](Get-PsaProp $hit 'Id')
        }
        'syncro' {
            if ($r -notmatch '^\d+$') { throw "Syncro ticket numbers are numeric; '$r' isn't." }
            # Unverified: GET /tickets?number= filters on the ticket number customers see. Falls back to treating it as the id.
            $rows = @()
            try { $rows = @(Get-PsaProp (Invoke-Psa GET "/tickets?number=$r") 'tickets' | Where-Object { $null -ne $_ -and [string](Get-PsaProp $_ 'number') -eq $r }) } catch { $rows = @() }
            if ($rows.Count) { return [string](Get-PsaProp $rows[0] 'id') }
            return $r
        }
        default {
            if ($r -notmatch '^\d+$') { throw "$(Get-PsaName) ticket numbers are numeric; '$r' isn't." }
            return $r
        }
    }
}

# A link a technician can click for a ticket, or '' when the PSA has no known pattern.
# The optional PSA-TicketUrlTemplate secret (with {id}) overrides the defaults.
function Get-PsaTicketUrl {
    param([string]$Id)
    $c = Get-PsaConn
    $tpl = Get-PsaSecret 'PSA-TicketUrlTemplate'
    if ($tpl) { return $tpl.Replace('{id}', $Id) }
    $u = $null; try { $u = [uri]$c.Base } catch { return '' }
    switch ($c.Psa) {
        # Unverified: the ConnectWise web URL. The API host api-na.myconnectwise.net serves the UI as na.myconnectwise.net.
        'connectwise' { $h = $u.Host -replace '^api-', ''; return "https://$h/v4_6_release/services/system_io/Service/fv_sr100_request.rails?service_recid=$Id" }
        # Unverified: the Autotask web URL. The API zone webservicesN.autotask.net serves the UI as wwN.autotask.net.
        'autotask' { $h = $u.Host -replace '^webservices', 'ww'; return "https://$h/Mvc/ServiceDesk/TicketDetail.mvc?ticketId=$Id" }
        # Unverified: the HaloPSA agent URL.
        'halopsa' { return "$($u.Scheme)://$($u.Authority)/tickets?id=$Id" }
        'kaseyabms' { return '' }
        # Unverified: the Syncro web URL.
        'syncro' { return "$($u.Scheme)://$($u.Authority)/tickets/$Id" }
        'zendesk' { return "$($u.Scheme)://$($u.Authority)/agent/tickets/$Id" }
    }
    return ''
}

# One PSA ticket record as @{ id; number; summary; description; companyId; status; closed; contactId; contactName; createdAt; configIds; ticketType; raw }.
# Works on list rows and on Get-PsaTicket's raw record.
function ConvertTo-PsaTicketRow {
    param($Raw, [int[]]$CompleteStatuses = @())
    $c = Get-PsaConn
    $t = $Raw
    $row = @{ id = ''; number = ''; summary = ''; description = ''; companyId = ''; status = ''; closed = $false; contactId = ''; contactName = ''; createdAt = $null; configIds = @(); ticketType = ''; raw = $t }
    switch ($c.Psa) {
        'connectwise' {
            $row.id = [string](Get-PsaProp $t 'id'); $row.number = $row.id
            $row.summary = [string](Get-PsaProp $t 'summary'); $row.description = [string](Get-PsaProp $t 'initialDescription')
            $row.companyId = [string](Get-PsaPath $t 'company.id'); $row.status = [string](Get-PsaPath $t 'status.name')
            $row.closed = ((Get-PsaProp $t 'closedFlag') -eq $true)
            $row.contactId = [string](Get-PsaPath $t 'contact.id'); $row.contactName = [string](Get-PsaFirst $t @('contactName', 'contact.name'))
            $row.createdAt = ConvertTo-PsaDate (Get-PsaFirst $t @('dateEntered', '_info.dateEntered'))
            $row.ticketType = [string](Get-PsaPath $t 'type.name')
        }
        'autotask' {
            $row.id = [string](Get-PsaProp $t 'id'); $row.number = [string](Get-PsaFirst $t @('ticketNumber', 'id'))
            $row.summary = [string](Get-PsaProp $t 'title'); $row.description = [string](Get-PsaProp $t 'description')
            $row.companyId = [string](Get-PsaProp $t 'companyID'); $row.status = [string](Get-PsaProp $t 'status')
            $st = Get-PsaProp $t 'status'
            $row.closed = ((-not (Test-PsaBlank $st)) -and $CompleteStatuses -contains [int]$st) -or (-not (Test-PsaBlank (Get-PsaProp $t 'completedDate')))
            $row.contactId = [string](Get-PsaProp $t 'contactID')
            $row.createdAt = ConvertTo-PsaDate (Get-PsaProp $t 'createDate')
            $ci = Get-PsaProp $t 'configurationItemID'; if (-not (Test-PsaBlank $ci)) { $row.configIds = @([string]$ci) }
            $row.ticketType = [string](Get-PsaProp $t 'ticketType')
        }
        'halopsa' {
            # Unverified: the list row field names (user_id, user_name, dateoccurred, hasbeenclosed, tickettype_id).
            $row.id = [string](Get-PsaProp $t 'id'); $row.number = $row.id
            $row.summary = [string](Get-PsaProp $t 'summary'); $row.description = [string](Get-PsaProp $t 'details')
            $row.companyId = [string](Get-PsaProp $t 'client_id'); $row.status = [string](Get-PsaProp $t 'status_id')
            $row.closed = ((Get-PsaProp $t 'hasbeenclosed') -eq $true)
            $row.contactId = [string](Get-PsaProp $t 'user_id'); $row.contactName = [string](Get-PsaProp $t 'user_name')
            $row.createdAt = ConvertTo-PsaDate (Get-PsaProp $t 'dateoccurred')
            $assets = @(Get-PsaProp $t 'assets' | Where-Object { $null -ne $_ } | ForEach-Object { [string](Get-PsaProp $_ 'id') } | Where-Object { $_ })
            if ($assets.Count) { $row.configIds = $assets }
            $row.ticketType = [string](Get-PsaProp $t 'tickettype_id')
        }
        'kaseyabms' {
            # Unverified: the list row field names (TicketNumber, ContactId, ContactName, OpenDate, StatusName, AssetId).
            $row.id = [string](Get-PsaProp $t 'Id'); $row.number = [string](Get-PsaFirst $t @('TicketNumber', 'Id'))
            $row.summary = [string](Get-PsaProp $t 'Title'); $row.description = [string](Get-PsaProp $t 'Details')
            $row.companyId = [string](Get-PsaProp $t 'AccountId'); $row.status = [string](Get-PsaProp $t 'StatusName')
            $row.closed = ($row.status -match '(?i)complete|closed|resolved|cancel')
            $row.contactId = [string](Get-PsaProp $t 'ContactId'); $row.contactName = [string](Get-PsaProp $t 'ContactName')
            $row.createdAt = ConvertTo-PsaDate (Get-PsaFirst $t @('OpenDate', 'CreatedOn'))
            $a = Get-PsaProp $t 'AssetId'; if (-not (Test-PsaBlank $a)) { $row.configIds = @([string]$a) }
            $row.ticketType = [string](Get-PsaProp $t 'TypeName')
        }
        'syncro' {
            $row.id = [string](Get-PsaProp $t 'id'); $row.number = [string](Get-PsaFirst $t @('number', 'id'))
            $row.summary = [string](Get-PsaProp $t 'subject')
            $cm = @(Get-PsaProp $t 'comments' | Where-Object { $null -ne $_ }); if ($cm.Count) { $row.description = [string](Get-PsaProp $cm[0] 'body') }
            $row.companyId = [string](Get-PsaProp $t 'customer_id'); $row.status = [string](Get-PsaProp $t 'status')
            $row.closed = ($row.status -match '(?i)^(resolved|closed)$')
            $row.contactId = [string](Get-PsaProp $t 'contact_id')
            $row.createdAt = ConvertTo-PsaDate (Get-PsaProp $t 'created_at')
            $row.ticketType = [string](Get-PsaProp $t 'problem_type')
        }
        'zendesk' {
            $row.id = [string](Get-PsaProp $t 'id'); $row.number = $row.id
            $row.summary = [string](Get-PsaProp $t 'subject'); $row.description = [string](Get-PsaProp $t 'description')
            $row.companyId = [string](Get-PsaProp $t 'organization_id'); $row.status = [string](Get-PsaProp $t 'status')
            $row.closed = ($row.status -match '(?i)^(solved|closed)$')
            $row.contactId = [string](Get-PsaProp $t 'requester_id')
            $row.createdAt = ConvertTo-PsaDate (Get-PsaProp $t 'created_at')
            $row.ticketType = [string](Get-PsaProp $t 'type')
        }
    }
    return $row
}

# Tickets for one company. -OpenOnly leaves out closed tickets; -Since and -Until bound the
# creation date. Returns normalized rows (ConvertTo-PsaTicketRow), newest first, at most -Max.
# Every row is checked against the company id again here, so another company's ticket never comes back.
function Find-PsaTickets {
    param([string]$CompanyId, [switch]$OpenOnly, $Since = $null, $Until = $null, [int]$Max = 200)
    $c = Get-PsaConn
    if (Test-PsaBlank $CompanyId) { throw 'Find-PsaTickets needs a company id.' }
    $from = ConvertTo-PsaDate $Since; $to = ConvertTo-PsaDate $Until
    $rows = @(); $complete = @()
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: list conditions with company/id, closedFlag and dateEntered in [brackets].
            $cond = "company/id=$([int]$CompanyId)"
            if ($OpenOnly) { $cond += ' and closedFlag=false' }
            if ($from) { $cond += " and dateEntered>=[$(Format-PsaDate $from)]" }
            if ($to) { $cond += " and dateEntered<[$(Format-PsaDate $to)]" }
            $rows = @(Invoke-PsaCwList "/service/tickets?conditions=$(ConvertTo-PsaQuery $cond)&orderBy=$(ConvertTo-PsaQuery 'id desc')" $Max)
        }
        'autotask' {
            # Unverified: Tickets/query with companyID, createDate and status filters.
            $complete = @(Get-PsaAtCompleteStatuses)
            $f = @([ordered]@{ op = 'eq'; field = 'companyID'; value = [long]$CompanyId })
            if ($from) { $f += [ordered]@{ op = 'gte'; field = 'createDate'; value = (Format-PsaDate $from) } }
            if ($to) { $f += [ordered]@{ op = 'lt'; field = 'createDate'; value = (Format-PsaDate $to) } }
            if ($OpenOnly) { foreach ($s in $complete) { $f += [ordered]@{ op = 'noteq'; field = 'status'; value = $s } } }
            $rows = @(Invoke-PsaAtQuery 'Tickets' $f @() 500)
        }
        'halopsa' {
            # Unverified: client_id, open_only and the datesearch/startdate/enddate filters on GET /api/Tickets.
            $q = "client_id=$CompanyId&pageinate=true&page_size=100"
            if ($OpenOnly) { $q += '&open_only=true' }
            if ($from -or $to) { $q += '&datesearch=dateoccurred'; if ($from) { $q += "&startdate=$(ConvertTo-PsaQuery (Format-PsaDate $from))" }; if ($to) { $q += "&enddate=$(ConvertTo-PsaQuery (Format-PsaDate $to))" } }
            $acc = New-Object System.Collections.ArrayList
            for ($p = 1; $p -le $PsaExtraState.MaxPages; $p++) {
                $r = Invoke-Psa GET "/Tickets?$q&page_no=$p"
                $page = @(Get-PsaProp $r 'tickets' | Where-Object { $null -ne $_ })
                foreach ($x in $page) { $null = $acc.Add($x) }
                $total = [int](Get-PsaNumber (Get-PsaProp $r 'record_count'))
                if ($page.Count -lt 100 -or $acc.Count -ge $Max -or ($total -and $acc.Count -ge $total)) { break }
            }
            $rows = @($acc)
        }
        'kaseyabms' {
            # Unverified: Filter.AccountId on GET /v2/servicedesk/tickets and whether Result is a list or { Items }.
            $acc = New-Object System.Collections.ArrayList
            for ($p = 1; $p -le $PsaExtraState.MaxPages; $p++) {
                $res = Get-PsaProp (Invoke-Psa GET "/servicedesk/tickets?Filter.AccountId=$CompanyId&PageNumber=$p&PageSize=100") 'Result'
                $page = @($(if ($null -ne (Get-PsaProp $res 'Items')) { Get-PsaProp $res 'Items' } else { $res }) | Where-Object { $null -ne $_ })
                foreach ($x in $page) { $null = $acc.Add($x) }
                if ($page.Count -lt 100 -or $acc.Count -ge $Max) { break }
            }
            $rows = @($acc)
        }
        'syncro' {
            # customer_id and status=Not Closed are in the Syncro spec; dates are filtered here.
            $q = "customer_id=$CompanyId"
            if ($OpenOnly) { $q += "&status=$(ConvertTo-PsaQuery 'Not Closed')" }
            $acc = New-Object System.Collections.ArrayList
            for ($p = 1; $p -le $PsaExtraState.MaxPages; $p++) {
                $r = Invoke-Psa GET "/tickets?$q&page=$p"
                foreach ($x in @(Get-PsaProp $r 'tickets' | Where-Object { $null -ne $_ })) { $null = $acc.Add($x) }
                $pages = [int](Get-PsaNumber (Get-PsaPath $r 'meta.total_pages'))
                if ($p -ge $pages -or $acc.Count -ge $Max) { break }
            }
            $rows = @($acc)
        }
        'zendesk' {
            # Search syntax from developer.zendesk.com: organization:, status<solved, created>= and created<.
            $q = "type:ticket organization:$CompanyId"
            if ($OpenOnly) { $q += ' status<solved' }
            if ($from) { $q += " created>=$($from.ToString('yyyy-MM-dd'))" }
            if ($to) { $q += " created<$($to.ToString('yyyy-MM-dd'))" }
            $path = "/search?query=$(ConvertTo-PsaQuery $q)&sort_by=created_at&sort_order=desc&per_page=100"
            $acc = New-Object System.Collections.ArrayList
            for ($p = 1; $p -le $PsaExtraState.MaxPages -and $path; $p++) {
                $r = Invoke-Psa GET $path
                foreach ($x in @(Get-PsaProp $r 'results' | Where-Object { $null -ne $_ })) { $null = $acc.Add($x) }
                if ($acc.Count -ge $Max) { break }
                $path = [string](Get-PsaProp $r 'next_page')
            }
            $rows = @($acc)
        }
    }
    $out = @(foreach ($r in $rows) {
            $row = ConvertTo-PsaTicketRow $r $complete
            if ($row.companyId -and $row.companyId -ne [string]$CompanyId) { continue }
            if ($OpenOnly -and $row.closed) { continue }
            if ($from -and $row.createdAt -and $row.createdAt -lt $from) { continue }
            if ($to -and $row.createdAt -and $row.createdAt -ge $to) { continue }
            $row
        })
    return @($out | Sort-Object -Property @{ Expression = { if ($_.createdAt) { $_.createdAt } else { [datetime]::MinValue } } }, @{ Expression = { [long](Get-PsaNumber $_.id) } } -Descending | Select-Object -First $Max)
}

# The configuration items (devices) on a ticket, as ids. Uses the row's own field where the PSA has one;
# ConnectWise keeps them on a sub-resource. Returns @() when there are none or the PSA can't tell.
function Get-PsaTicketDevices {
    param([string]$Id, $Row = $null)
    $c = Get-PsaConn
    if ($null -ne $Row -and @($Row.configIds).Count) { return @($Row.configIds) }
    if ($c.Psa -ne 'connectwise') { return @() }
    # Unverified: GET /service/tickets/{id}/configurations.
    try { return @(Invoke-Psa GET "/service/tickets/$Id/configurations?fields=id&pageSize=50" | Where-Object { $null -ne $_ } | ForEach-Object { [string](Get-PsaProp $_ 'id') } | Where-Object { $_ }) } catch { return @() }
}

# Time logged for one company between -Since and -Until. -TicketIds is needed by the PSAs that
# keep time on the ticket (Autotask, HaloPSA, Kaseya BMS, Syncro). Returns rows
# @{ id; ticketId; date; hours; billableHours; billable; member; workType; agreementId; notes },
# or nothing when the PSA has no time API (Zendesk; check Get-PsaExtraSupport .time).
function Get-PsaTimeEntries {
    param([string]$CompanyId, $Since, $Until, [string[]]$TicketIds = @(), [int]$Max = 2000)
    $c = Get-PsaConn
    $from = ConvertTo-PsaDate $Since; $to = ConvertTo-PsaDate $Until
    if (-not $from -or -not $to) { throw 'Get-PsaTimeEntries needs -Since and -Until.' }
    $ids = @($TicketIds | Where-Object { -not (Test-PsaBlank $_) } | Select-Object -Unique)
    if (@('halopsa', 'kaseyabms', 'syncro') -contains $c.Psa -and $ids.Count -gt $PsaExtraState.MaxTicketLoop) {
        Add-PsaExtraWarning "Time was read for the newest $($PsaExtraState.MaxTicketLoop) of $($ids.Count) tickets only, because $(Get-PsaName) keeps time per ticket."
        $ids = @($ids | Select-Object -First $PsaExtraState.MaxTicketLoop)
    }
    $out = New-Object System.Collections.ArrayList
    $add = { param($e) if ($e.date -and ($e.date -lt $from -or $e.date -ge $to)) { return }; if ($out.Count -lt $Max) { $null = $out.Add($e) } }
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: GET /time/entries with company/id and timeStart conditions; billableOption values Billable, DoNotBill, NoCharge, NoDefault.
            $cond = "company/id=$([int]$CompanyId) and timeStart>=[$(Format-PsaDate $from)] and timeStart<[$(Format-PsaDate $to)]"
            foreach ($t in @(Invoke-PsaCwList "/time/entries?conditions=$(ConvertTo-PsaQuery $cond)" $Max 1000)) {
                $bo = [string](Get-PsaProp $t 'billableOption')
                $hrs = Get-PsaNumber (Get-PsaProp $t 'actualHours')
                $chargeType = [string](Get-PsaProp $t 'chargeToType')
                & $add @{ id = [string](Get-PsaProp $t 'id'); ticketId = $(if ($chargeType -match '(?i)ticket' -or -not $chargeType) { [string](Get-PsaProp $t 'chargeToId') } else { '' }); date = (ConvertTo-PsaDate (Get-PsaProp $t 'timeStart'))
                    hours = $hrs; billableHours = $(if ($bo -eq 'Billable') { $(if ($null -ne (Get-PsaProp $t 'hoursBilled')) { Get-PsaNumber (Get-PsaProp $t 'hoursBilled') } else { $hrs }) } else { 0.0 }); billable = ($bo -eq 'Billable')
                    member = [string](Get-PsaPath $t 'member.identifier'); workType = [string](Get-PsaPath $t 'workType.name'); agreementId = [string](Get-PsaPath $t 'agreement.id'); notes = [string](Get-PsaProp $t 'notes') }
            }
        }
        'autotask' {
            # Unverified: TimeEntries/query with the "in" operator on ticketID; field names hoursWorked, hoursToBill, isNonBillable, contractID.
            for ($i = 0; $i -lt $ids.Count; $i += 200) {
                $chunk = @($ids[$i..([Math]::Min($i + 199, $ids.Count - 1))] | ForEach-Object { [long]$_ })
                $f = @([ordered]@{ op = 'in'; field = 'ticketID'; value = $chunk }, [ordered]@{ op = 'gte'; field = 'dateWorked'; value = (Format-PsaDate $from) }, [ordered]@{ op = 'lt'; field = 'dateWorked'; value = (Format-PsaDate $to) })
                foreach ($t in @(Invoke-PsaAtQuery 'TimeEntries' $f @() $Max)) {
                    $nb = ((Get-PsaProp $t 'isNonBillable') -eq $true)
                    & $add @{ id = [string](Get-PsaProp $t 'id'); ticketId = [string](Get-PsaProp $t 'ticketID'); date = (ConvertTo-PsaDate (Get-PsaFirst $t @('dateWorked', 'startDateTime')))
                        hours = (Get-PsaNumber (Get-PsaProp $t 'hoursWorked')); billableHours = $(if ($nb) { 0.0 } else { Get-PsaNumber (Get-PsaFirst $t @('hoursToBill', 'hoursWorked')) }); billable = (-not $nb)
                        member = [string](Get-PsaProp $t 'resourceID'); workType = [string](Get-PsaProp $t 'billingCodeID'); agreementId = [string](Get-PsaProp $t 'contractID'); notes = [string](Get-PsaProp $t 'summaryNotes') }
                }
            }
        }
        'halopsa' {
            # Unverified: GET /api/Actions?ticket_id= with timetaken (hours), chargehours and who; nonbillable time has chargehours 0.
            foreach ($tid in $ids) {
                $r = Invoke-Psa GET "/Actions?ticket_id=$tid&excludesys=true"
                foreach ($a in @(Get-PsaProp $r 'actions' | Where-Object { $null -ne $_ })) {
                    $hrs = Get-PsaNumber (Get-PsaProp $a 'timetaken'); if ($hrs -le 0) { continue }
                    $ch = Get-PsaProp $a 'chargehours'; $bill = $(if ($null -ne $ch) { Get-PsaNumber $ch } else { $hrs })
                    & $add @{ id = [string](Get-PsaProp $a 'id'); ticketId = [string]$tid; date = (ConvertTo-PsaDate (Get-PsaFirst $a @('datetime', 'actiondatecreated'))); hours = $hrs; billableHours = $bill; billable = ($bill -gt 0)
                        member = [string](Get-PsaProp $a 'who'); workType = [string](Get-PsaProp $a 'outcome'); agreementId = [string](Get-PsaProp $a 'contract_id'); notes = [string](Get-PsaProp $a 'note') }
                }
            }
        }
        'kaseyabms' {
            # Unverified: GET /v2/servicedesk/tickets/{id}/timelogs and its field names.
            foreach ($tid in $ids) {
                $res = Get-PsaProp (Invoke-Psa GET "/servicedesk/tickets/$tid/timelogs") 'Result'
                foreach ($a in @($(if ($null -ne (Get-PsaProp $res 'Items')) { Get-PsaProp $res 'Items' } else { $res }) | Where-Object { $null -ne $_ })) {
                    $hrs = Get-PsaNumber (Get-PsaFirst $a @('ActualHours', 'Hours', 'WorkedHours'))
                    $bill = Get-PsaNumber (Get-PsaFirst $a @('BillableHours', 'BillHours'))
                    $isBill = ((Get-PsaProp $a 'IsBillable') -eq $true) -or $bill -gt 0
                    & $add @{ id = [string](Get-PsaProp $a 'Id'); ticketId = [string]$tid; date = (ConvertTo-PsaDate (Get-PsaFirst $a @('StartDate', 'StartTime', 'Date'))); hours = $hrs; billableHours = $(if ($isBill -and $bill -le 0) { $hrs } else { $bill }); billable = $isBill
                        member = [string](Get-PsaFirst $a @('AssigneeName', 'ResourceName')); workType = [string](Get-PsaProp $a 'WorkTypeName'); agreementId = [string](Get-PsaProp $a 'ContractId'); notes = [string](Get-PsaProp $a 'Notes') }
                }
            }
        }
        'syncro' {
            # Unverified: the ticket_timers array on GET /tickets/{id} (start_time, end_time, billable, user_id, notes).
            foreach ($tid in $ids) {
                $t = Get-PsaProp (Invoke-Psa GET "/tickets/$tid") 'ticket'
                foreach ($a in @(Get-PsaProp $t 'ticket_timers' | Where-Object { $null -ne $_ })) {
                    $st = ConvertTo-PsaDate (Get-PsaProp $a 'start_time'); $en = ConvertTo-PsaDate (Get-PsaProp $a 'end_time')
                    $hrs = $(if ($st -and $en) { [Math]::Round(($en - $st).TotalHours, 2) } else { 0.0 })
                    $isBill = ((Get-PsaProp $a 'billable') -ne $false)
                    & $add @{ id = [string](Get-PsaProp $a 'id'); ticketId = [string]$tid; date = $st; hours = $hrs; billableHours = $(if ($isBill) { $hrs } else { 0.0 }); billable = $isBill
                        member = [string](Get-PsaProp $a 'user_id'); workType = ''; agreementId = ''; notes = [string](Get-PsaProp $a 'notes') }
                }
            }
        }
        'zendesk' {
            Add-PsaExtraWarning 'Zendesk has no time-entry API (time tracking is an app that writes custom fields), so time was not read.'
            return $null
        }
    }
    return @($out)
}

# The company's agreements (contracts). Returns rows @{ id; name; type; status; active; startDate; endDate; amount; cycle; coverage },
# or nothing when the PSA has no agreements (Zendesk; check Get-PsaExtraSupport .agreements).
function Get-PsaAgreements {
    param([string]$CompanyId)
    $c = Get-PsaConn
    if (Test-PsaBlank $CompanyId) { throw 'Get-PsaAgreements needs a company id.' }
    $rows = New-Object System.Collections.ArrayList
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: GET /finance/agreements with company/id; fields agreementStatus, billAmount, applicationUnits, applicationLimit.
            $cond = "company/id=$([int]$CompanyId)"
            foreach ($a in @(Invoke-PsaCwList "/finance/agreements?conditions=$(ConvertTo-PsaQuery $cond)" 100)) {
                if ([string](Get-PsaPath $a 'company.id') -and [string](Get-PsaPath $a 'company.id') -ne [string]$CompanyId) { continue }
                $units = [string](Get-PsaProp $a 'applicationUnits'); $lim = Get-PsaProp $a 'applicationLimit'
                $cov = if ($units -and -not (Test-PsaBlank $lim)) { "$lim $($units.ToLowerInvariant()) per $(if (Get-PsaPath $a 'applicationCycle') { [string](Get-PsaPath $a 'applicationCycle') } else { 'period' })" } elseif ($units -match '(?i)unlimited') { 'unlimited' } else { '' }
                $st = [string](Get-PsaProp $a 'agreementStatus')
                $null = $rows.Add(@{ id = [string](Get-PsaProp $a 'id'); name = [string](Get-PsaProp $a 'name'); type = [string](Get-PsaPath $a 'type.name'); status = $st
                        active = ((Get-PsaProp $a 'cancelledFlag') -ne $true -and $st -notmatch '(?i)cancel|expired|inactive'); startDate = (ConvertTo-PsaDate (Get-PsaProp $a 'startDate')); endDate = (ConvertTo-PsaDate (Get-PsaProp $a 'endDate'))
                        amount = (Get-PsaNumber (Get-PsaProp $a 'billAmount')); cycle = [string](Get-PsaPath $a 'billingCycle.name'); coverage = $cov })
            }
        }
        'autotask' {
            # Unverified: Contracts/query by companyID; contractType and status are picklists (status 1 = Active by default).
            $types = @(); try { $types = @(Get-PsaAtPicklist 'Contracts' 'contractType') } catch { $types = @() }
            foreach ($a in @(Invoke-PsaAtQuery 'Contracts' @([ordered]@{ op = 'eq'; field = 'companyID'; value = [long]$CompanyId }) @() 200)) {
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
            $r = Invoke-Psa GET "/ClientContract?client_id=$CompanyId"
            $list = @(if ($r -is [array]) { $r } else { Get-PsaFirst $r @('contracts', 'clientcontracts') })
            foreach ($a in @($list | Where-Object { $null -ne $_ })) {
                if ([string](Get-PsaProp $a 'client_id') -and [string](Get-PsaProp $a 'client_id') -ne [string]$CompanyId) { continue }
                $null = $rows.Add(@{ id = [string](Get-PsaProp $a 'id'); name = [string](Get-PsaFirst $a @('ref', 'name')); type = [string](Get-PsaFirst $a @('contract_type_name', 'billing_description', 'contract_type')); status = $(if ((Get-PsaProp $a 'active') -eq $false) { 'Inactive' } else { 'Active' })
                        active = ((Get-PsaProp $a 'active') -ne $false); startDate = (ConvertTo-PsaDate (Get-PsaProp $a 'start_date')); endDate = (ConvertTo-PsaDate (Get-PsaProp $a 'end_date'))
                        amount = (Get-PsaNumber (Get-PsaFirst $a @('periodchargeamount', 'value'))); cycle = [string](Get-PsaProp $a 'billing_period'); coverage = $(if (Get-PsaProp $a 'prepay_hours') { "$(Get-PsaProp $a 'prepay_hours') prepaid hours" } else { '' }) })
            }
        }
        'kaseyabms' {
            # Unverified: GET /v2/finance/contracts?Filter.AccountId= and its field names.
            $res = Get-PsaProp (Invoke-Psa GET "/finance/contracts?Filter.AccountId=$CompanyId&PageSize=100") 'Result'
            foreach ($a in @($(if ($null -ne (Get-PsaProp $res 'Items')) { Get-PsaProp $res 'Items' } else { $res }) | Where-Object { $null -ne $_ })) {
                if ([string](Get-PsaProp $a 'AccountId') -and [string](Get-PsaProp $a 'AccountId') -ne [string]$CompanyId) { continue }
                $st = [string](Get-PsaFirst $a @('StatusName', 'Status'))
                $null = $rows.Add(@{ id = [string](Get-PsaProp $a 'Id'); name = [string](Get-PsaFirst $a @('Name', 'ContractName')); type = [string](Get-PsaFirst $a @('ContractTypeName', 'TypeName')); status = $st
                        active = ($st -notmatch '(?i)cancel|expired|inactive'); startDate = (ConvertTo-PsaDate (Get-PsaProp $a 'StartDate')); endDate = (ConvertTo-PsaDate (Get-PsaProp $a 'EndDate'))
                        amount = (Get-PsaNumber (Get-PsaFirst $a @('Amount', 'RecurringAmount'))); cycle = [string](Get-PsaProp $a 'BillingCycleName'); coverage = '' })
            }
        }
        'syncro' {
            # Unverified: GET /contracts?customer_id= ({ contracts: [...] } with name, contract_amount, start_date, end_date, status).
            $r = Invoke-Psa GET "/contracts?customer_id=$CompanyId"
            foreach ($a in @(Get-PsaProp $r 'contracts' | Where-Object { $null -ne $_ })) {
                if ([string](Get-PsaProp $a 'customer_id') -and [string](Get-PsaProp $a 'customer_id') -ne [string]$CompanyId) { continue }
                $st = [string](Get-PsaProp $a 'status')
                $null = $rows.Add(@{ id = [string](Get-PsaProp $a 'id'); name = [string](Get-PsaProp $a 'name'); type = [string](Get-PsaProp $a 'contract_type'); status = $st
                        active = ($st -notmatch '(?i)cancel|expired|inactive'); startDate = (ConvertTo-PsaDate (Get-PsaProp $a 'start_date')); endDate = (ConvertTo-PsaDate (Get-PsaProp $a 'end_date'))
                        amount = (Get-PsaNumber (Get-PsaProp $a 'contract_amount')); cycle = ''; coverage = '' })
            }
        }
        'zendesk' {
            Add-PsaExtraWarning 'Zendesk has no agreements or contracts, so none were read.'
            return $null
        }
    }
    return @($rows)
}

# One invoice by its number: @{ id; number; companyId; date; periodStart; periodEnd; periodDerived; total },
# or $null when it isn't found. Throws when the PSA has no invoice API (Kaseya BMS, Syncro, Zendesk:
# check Get-PsaExtraSupport first). When the invoice carries no service period, the period is the
# calendar month before the invoice date, and periodDerived is $true.
function Get-PsaInvoice {
    param([string]$Number)
    $c = Get-PsaConn
    $n = ([string]$Number).Trim().TrimStart('#')
    if (-not $n) { throw 'Get-PsaInvoice needs an invoice number.' }
    $inv = $null; $companyId = ''; $date = $null; $ps = $null; $pe = $null; $total = 0.0; $id = ''
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: GET /finance/invoices?conditions=invoiceNumber="..." and the fields company.id, date, total.
            $q = $n.Replace('\', '\\').Replace('"', '\"')
            $inv = @(Invoke-Psa GET "/finance/invoices?conditions=$(ConvertTo-PsaQuery ('invoiceNumber="' + $q + '"'))&pageSize=5" | Where-Object { $null -ne $_ }) | Select-Object -First 1
            if (-not $inv) { return $null }
            $id = [string](Get-PsaProp $inv 'id'); $companyId = [string](Get-PsaPath $inv 'company.id'); $date = ConvertTo-PsaDate (Get-PsaProp $inv 'date'); $total = Get-PsaNumber (Get-PsaProp $inv 'total')
        }
        'autotask' {
            # Unverified: Invoices/query by invoiceNumber; fields companyID, invoiceDateTime, fromDate, toDate, invoiceTotal.
            $inv = @(Invoke-PsaAtQuery 'Invoices' @([ordered]@{ op = 'eq'; field = 'invoiceNumber'; value = $n }) @() 5) | Select-Object -First 1
            if (-not $inv) { return $null }
            $id = [string](Get-PsaProp $inv 'id'); $companyId = [string](Get-PsaProp $inv 'companyID'); $date = ConvertTo-PsaDate (Get-PsaProp $inv 'invoiceDateTime')
            $ps = ConvertTo-PsaDate (Get-PsaProp $inv 'fromDate'); $pe = ConvertTo-PsaDate (Get-PsaProp $inv 'toDate'); if ($pe) { $pe = $pe.Date.AddDays(1) }
            $total = Get-PsaNumber (Get-PsaFirst $inv @('invoiceTotal', 'totalAmount'))
        }
        'halopsa' {
            # Unverified: GET /api/Invoice?search= ({ invoices: [...] }) and the fields invoicenumber, client_id, invoice_date, total.
            $r = Invoke-Psa GET "/Invoice?search=$(ConvertTo-PsaQuery $n)&count=20"
            $list = @(if ($r -is [array]) { $r } else { Get-PsaProp $r 'invoices' })
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

# Relates ticket -Id to the older ticket -RelatedId. Uses the PSA's own relation where one exists:
#   HaloPSA: Id becomes a child of RelatedId (parent_id).
#   Autotask and Zendesk: Id becomes an Incident of RelatedId, only when RelatedId is already a Problem ticket.
#   ConnectWise, Kaseya BMS, Syncro: no relation in the API, so notes only.
# -NotesOnly skips the PSA relation (a ticket can only have one parent or problem).
# Always adds an internal cross-reference note, on -NoteTicketId (default RelatedId) naming the other
# ticket. Never merges, closes or changes status. Returns @{ method = 'native' | 'note-only'; detail }.
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
            # problem_id with type incident (developer.zendesk.com). Only when the other ticket is already a problem.
            $other = Get-PsaProp (Invoke-Psa GET "/tickets/$RelatedId") 'ticket'
            if ([string](Get-PsaProp $other 'type') -eq 'problem') {
                $null = Invoke-Psa PUT "/tickets/$Id" @{ ticket = @{ type = 'incident'; problem_id = [long]$RelatedId } }
                $method = 'native'; $detail = "Ticket $Id is now an incident of problem ticket $RelatedId."
            }
            else { $detail = "Ticket $RelatedId is not a problem ticket, so they were related by notes only." }
        }
        default { $detail = "$(Get-PsaName) has no ticket relation in its API, so they were related by notes only." }
    }
    $other = if ($NoteTicketId -eq $RelatedId) { $Id } else { $RelatedId }
    $text = "Related ticket: #$other looks like the same issue as this ticket.$(if ($Reason) { " $Reason" })$(if ($method -eq 'native') { " $detail" }) Nothing was merged or closed."
    Add-PsaNote -Id $NoteTicketId -Text $text -Title 'Related ticket'
    return @{ method = $method; detail = $detail }
}
# ---------- end psa-extra.ps1 ----------
