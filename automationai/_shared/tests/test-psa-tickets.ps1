# Strict-mode tests for the ticket functions in _shared/psa.ps1 (notes, note markers, statuses, links, queue,
# contact, close, company and ticket-number lookups) and _shared/psa-tickets.ps1 (ticket lists, names, SLA,
# devices, time, agreements, invoices, contacts, relations) on all six PSAs: request shape, normalized rows,
# the exact-company guard, paging, the 403 message and the duplicate-note marker.
# Placeholder data only (Contoso, Example MSP).
. (Join-Path $PSScriptRoot 'mock.ps1')

$S = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://api-na.cw.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices5.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    halopsa     = @{ 'PSA-Type' = 'halopsa'; 'Halo-ApiUrl' = 'https://halo.example.com'; 'Halo-ClientId' = 'cid'; 'Halo-ClientSecret' = 'sec' }
    kaseyabms   = @{ 'PSA-Type' = 'kaseyabms'; 'KaseyaBMS-ApiUrl' = 'https://bms.example.com'; 'KaseyaBMS-Username' = 'u'; 'KaseyaBMS-Password' = 'p'; 'KaseyaBMS-CompanyName' = 'Example MSP'; 'KaseyaBMS-NoteTypeId' = '4'; 'KaseyaBMS-ClosedStatusId' = '3' }
    syncro      = @{ 'PSA-Type' = 'syncro'; 'Syncro-ApiUrl' = 'https://example.syncromsp.com/api/v1'; 'Syncro-ApiKey' = 'key' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
}
$PSAS = @('connectwise', 'autotask', 'halopsa', 'kaseyabms', 'syncro', 'zendesk')
$CW = 'https://api-na.cw.example.com/v4_6_release/apis/3.0'; $AT = 'https://webservices5.autotask.example/atservicesrest/v1.0'; $HALO = 'https://halo.example.com/api'
$BMS = 'https://bms.example.com/v2'; $SY = 'https://example.syncromsp.com/api/v1'; $ZD = 'https://example.zendesk.com/api/v2'
$Now = [datetime]::UtcNow
function Iso { param([double]$Hours) $Now.AddHours($Hours).ToString('yyyy-MM-ddTHH:mm:ssZ') }
function O { param([hashtable]$h) [pscustomobject]$h }
function Pick { param($v, $l) O @{ value = $v; label = $l; isActive = $true } }
function Unesc { param($u) [uri]::UnescapeDataString([string]$u) }
function AtSearch { param($u) (Unesc $u) -replace '^.*search=', '' | ConvertFrom-Json }

$AtTicketFields = O @{ fields = @(
        (O @{ name = 'status'; picklistValues = @((Pick '1' 'New'), (Pick '5' 'Complete'), (Pick '7' 'Waiting Customer')) }),
        (O @{ name = 'priority'; picklistValues = @((Pick '4' 'Critical'), (Pick '1' 'High'), (Pick '2' 'Medium'), (Pick '3' 'Low')) }),
        (O @{ name = 'queueID'; picklistValues = @((Pick '29683' 'Service Desk'), (Pick '29684' 'Tier 2')) }),
        (O @{ name = 'ticketType'; picklistValues = @((Pick '1' 'Service Request'), (Pick '2' 'Incident'), (Pick '3' 'Problem')) })) }
$AtNoteFields = O @{ fields = @((O @{ name = 'publish'; picklistValues = @((Pick '1' 'All Autotask Users'), (Pick '2' 'Internal Only')) }), (O @{ name = 'noteType'; picklistValues = @((Pick '1' 'Task Detail')) })) }

# ---- one router for every test: routes are @{ m; u; r } (r may be a scriptblock taking $c and $n) ----
$Routes = New-Object System.Collections.ArrayList
function Use-Routes { param([string]$Psa, [object[]]$R, [hashtable]$Extra = @{}) $Routes.Clear(); foreach ($x in $R) { $null = $Routes.Add($x) }; Reset-Mock ($S[$Psa] + $Extra) $Router }
$Router = {
    param($c, $n)
    if ($c.Uri -like '*/auth/token') { return (O @{ access_token = 'halo-token' }) }
    if ($c.Uri -like '*/v2/security/authenticate') { return (O @{ Result = (O @{ AccessToken = 'bms-token' }) }) }
    foreach ($r in $Routes) {
        if (($r.m -eq '*' -or $c.Method -eq $r.m) -and $c.Uri -like $r.u) { if ($r.r -is [scriptblock]) { return (& $r.r $c $n) }; return $r.r }
    }
    if ($c.Uri -like "$AT/Tickets/entityInformation/fields") { return $AtTicketFields }
    if ($c.Uri -like "$AT/TicketNotes/entityInformation/fields") { return $AtNoteFields }
    if ($c.Uri -ceq "$HALO/Status") { return @((O @{ id = 1; name = 'New' }), (O @{ id = 7; name = 'Waiting Customer' }), (O @{ id = 9; name = 'Closed' })) }
    return $null
}
function Write-Calls { param([string[]]$Methods = @('POST', 'PUT', 'PATCH')) return @($Mock.Calls | Where-Object { $Methods -contains $_.Method -and $_.Uri -notlike '*/auth/token' -and $_.Uri -notlike '*/security/authenticate' }) }

# ---- per-PSA ticket fixtures ----
#   row: a raw list row (id, company, closed, created, updated) in that PSA's shape
#   list/wrap/size/pageRx: the list route, its reply for one page, the page size and how to read the page number
#   find: what the basic Find call must send;  shape2: what the status/created/text call must send
$TicketFx = @{
    connectwise = @{
        row    = { param($id, $co, [bool]$cl, $cr, $up) O @{ id = $id; summary = "Printer offline $id"; initialDescription = 'The printer at Contoso is offline.'; closedFlag = $cl; status = (O @{ name = $(if ($cl) { 'Closed' } else { 'New' }) }); company = $(if ($co) { O @{ id = $co; name = 'Contoso Ltd' } } else { $null }); contact = (O @{ id = 5; name = 'Pat Doe' }); contactEmailAddress = 'pat@contoso.com'; owner = (O @{ id = 7; identifier = 'jlee'; name = 'Jordan Lee' }); board = (O @{ id = 1; name = 'Service Desk' }); priority = (O @{ id = 2; name = 'Priority 2 - High' }); _info = (O @{ dateEntered = $cr; lastUpdated = $up }) } }
        list   = '*/service/tickets[?]*'; size = 100; pageRx = '[?&]page=(\d+)'
        wrap   = { param($rows, $page, $more, $total) , @($rows) }
        find   = { param($u) $u -match 'conditions=closedFlag=false and company/id=42 and lastUpdated<\[\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\]&orderBy=id asc&pageSize=100&page=1$' }
        shape2 = { param($u) $u -match 'company/id=42 and status/name="Waiting Customer" and dateEntered>=\[\d{4}-' -and $u -match 'summary contains "printer"' }
        number = '11'; wait = 'Waiting Customer'
    }
    autotask    = @{
        row    = { param($id, $co, [bool]$cl, $cr, $up) O @{ id = $id; ticketNumber = "T20261008.00$id"; title = "Printer offline $id"; description = 'd'; companyID = $(if ($co) { $co } else { $null }); status = $(if ($cl) { 5 } else { 1 }); priority = 1; queueID = 29683; assignedResourceID = 29682885; contactID = 5; createDate = $cr; lastActivityDate = $up } }
        list   = '*/Tickets/query[?]*'; size = 40; pageRx = '[?&]page=(\d+)'
        wrap   = { param($rows, $page, $more, $total) O @{ items = @($rows); pageDetails = (O @{ nextPageUrl = $(if ($more) { "$AT/Tickets/query?page=$($page + 1)" } else { $null }) }) } }
        find   = { param($u) $s = AtSearch $u; @($s.filter | Where-Object { $_.op -eq 'noteq' -and $_.field -eq 'status' -and $_.value -eq 5 }).Count -eq 1 -and @($s.filter | Where-Object { $_.op -eq 'eq' -and $_.field -eq 'companyID' -and $_.value -eq 42 }).Count -eq 1 -and @($s.filter | Where-Object { $_.op -eq 'lt' -and $_.field -eq 'lastActivityDate' }).Count -eq 1 }
        shape2 = { param($u) $s = AtSearch $u; @($s.filter | Where-Object { $_.op -eq 'eq' -and $_.field -eq 'status' -and $_.value -eq 7 }).Count -eq 1 -and @($s.filter | Where-Object { $_.op -eq 'gte' -and $_.field -eq 'createDate' }).Count -eq 1 -and @($s.filter | Where-Object { $_.op -eq 'contains' -and $_.field -eq 'title' -and $_.value -eq 'printer' }).Count -eq 1 }
        number = 'T20261008.0011'; wait = 'Waiting Customer'
    }
    halopsa     = @{
        row    = { param($id, $co, [bool]$cl, $cr, $up) O @{ id = $id; summary = "Printer offline $id"; details = 'd'; client_id = $(if ($co) { $co } else { $null }); client_name = 'Contoso Ltd'; status_name = $(if ($cl) { 'Closed' } else { 'New' }); status_id = $(if ($cl) { 9 } else { 1 }); hasbeenclosed = $cl; priority_id = 2; team = 'Service Desk'; team_id = 3; agent_id = 7; agent_name = 'Jordan Lee'; user_id = 5; user_name = 'Pat Doe'; dateoccurred = $cr; lastactiondate = $up; datecleared = $(if ($cl) { $up } else { '1900-01-01T00:00:00' }) } }
        list   = '*/api/Tickets[?]*'; size = 100; pageRx = '[?&]page_no=(\d+)'
        wrap   = { param($rows, $page, $more, $total) O @{ record_count = $total; tickets = @($rows) } }
        find   = { param($u) $u -match '/Tickets\?open_only=true&client_id=42&order=id&pageinate=true&page_size=100&page_no=1$' }
        shape2 = { param($u) $u -match 'status_id=7&client_id=42&datesearch=dateoccurred&startdate=\d{4}-.*&search=printer&order=id' }
        number = '11'; wait = 'Waiting Customer'
    }
    kaseyabms   = @{
        row    = { param($id, $co, [bool]$cl, $cr, $up) O @{ Id = $id; TicketNumber = "BMS-$id"; Title = "Printer offline $id"; Details = 'd'; AccountId = $(if ($co) { $co } else { $null }); AccountName = 'Contoso Ltd'; StatusName = $(if ($cl) { 'Completed' } else { 'New' }); CompletedDate = $(if ($cl) { $up } else { $null }); PriorityName = 'High'; QueueId = 3; QueueName = 'Service Desk'; AssigneeId = 8; AssigneeName = 'Jordan Lee'; ContactId = 5; ContactName = 'Pat Doe'; OpenDate = $cr; LastActivityUpdate = $up } }
        list   = '*/v2/servicedesk/tickets[?]*'; size = 100; pageRx = 'PageNumber=(\d+)'
        wrap   = { param($rows, $page, $more, $total) O @{ Success = $true; Result = @($rows); TotalRecords = $total } }
        find   = { param($u) $u -match '/servicedesk/tickets\?Filter\.ExcludeCompleted=1&Filter\.AccountIds=42&Filter\.LastActivityUpdateTo=\d{4}-[^&]+&PageSize=100&PageNumber=1$' }
        shape2 = { param($u) $u -match 'Filter\.StatusNames=Waiting Customer&Filter\.AccountIds=42&Filter\.OpenDateFrom=\d{4}-' }
        number = 'BMS-11'; wait = 'Waiting Customer'
    }
    syncro      = @{
        row    = { param($id, $co, [bool]$cl, $cr, $up) O @{ id = $id; number = 1000 + $id; subject = "Printer offline $id"; customer_id = $(if ($co) { $co } else { $null }); customer_business_then_name = 'Contoso Ltd'; status = $(if ($cl) { 'Resolved' } else { 'New' }); priority = '1 High'; user_id = 7; contact_id = 5; contact_fullname = 'Pat Doe'; problem_type = 'Hardware'; created_at = $cr; updated_at = $up } }
        list   = '*/tickets[?]*'; size = 25; pageRx = '[?&]page=(\d+)'
        wrap   = { param($rows, $page, $more, $total) O @{ tickets = @($rows); meta = (O @{ total_pages = [int][Math]::Ceiling($total / 25) }) } }
        find   = { param($u) $u -match '/tickets\?status=Not Closed&customer_id=42&page=1$' }
        shape2 = { param($u) $u -match 'status=Waiting Customer&customer_id=42&created_after=\d{4}-[^&]+&query=printer&page=1' }
        number = '1011'; wait = 'Waiting Customer'
    }
    zendesk     = @{
        row    = { param($id, $co, [bool]$cl, $cr, $up) O @{ id = $id; subject = "Printer offline $id"; description = 'd'; organization_id = $(if ($co) { $co } else { $null }); status = $(if ($cl) { 'solved' } else { 'open' }); priority = 'high'; group_id = 21; assignee_id = 71; requester_id = 5; created_at = $cr; updated_at = $up; type = 'incident' } }
        list   = '*/search[?]*'; size = 100; pageRx = '[?&]page=(\d+)'
        wrap   = { param($rows, $page, $more, $total) O @{ results = @($rows); next_page = $(if ($more) { "$ZD/search?page=$($page + 1)" } else { $null }) } }
        find   = { param($u) $u -match 'query=type:ticket status<solved organization:42 updated<\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ&sort_by=created_at&sort_order=asc&per_page=100$' }
        shape2 = { param($u) $u -match 'query=type:ticket status:pending organization:42 created>=\d{4}-\S+ "printer"&' }
        number = '11'; wait = 'pending'
    }
}

# ======== Find-PsaTickets: request, normalized row, company guard, client-side state check ========
foreach ($psa in $PSAS) {
    $fx = $TicketFx[$psa]
    $rows = @((& $fx.row 11 42 $false (Iso -48) (Iso -5)), (& $fx.row 12 43 $false (Iso -48) (Iso -5)), (& $fx.row 13 42 $true (Iso -48) (Iso -5)), (& $fx.row 14 $null $false (Iso -48) (Iso -5)))
    Use-Routes $psa @(@{ m = 'GET'; u = $fx.list; r = (& $fx.wrap $rows 1 $false 4) })
    Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
        $null = Connect-Psa
        $r = @(Find-PsaTickets -Open -CompanyId '42' -UpdatedBefore $Now.AddHours(-1) -Max 50)
        $u = Unesc (@(Get-Calls 'GET' $fx.list)[0].Uri)
        Check "$($psa): Find sends open, company and updated-before to the PSA" ([bool](& $fx.find $u)) $u
        Check "$($psa): Find keeps only the open ticket of company 42 (other company, closed and no-company rows dropped)" ($r.Count -eq 1 -and $r[0].id -eq '11' -and $r[0].companyId -eq '42') "ids=$(@($r | ForEach-Object { "$($_.id)/$($_.companyId)" }) -join ',')"
        $x = $r[0]
        $ok = $x.number -eq $fx.number -and $x.summary -eq 'Printer offline 11' -and $x.isClosed -eq $false -and $x.priorityLevel -eq 'high' -and $x.created -is [datetime] -and $x.updated -is [datetime] -and $x.updated -gt $x.created -and $null -eq $x.closed -and $null -ne $x.raw -and $x.ContainsKey('contactEmail') -and $x.ContainsKey('queue') -and $x.ContainsKey('url')
        Check "$($psa): Find row is normalized" $ok ($x | ConvertTo-Json -Depth 1 -Compress -WarningAction SilentlyContinue)
        Check "$($psa): Find row carries a ticket link (none for Kaseya BMS)" ($(if ($psa -eq 'kaseyabms') { $x.url -eq '' } else { $x.url -match '^https://' -and $x.url -match '11' })) $x.url
        Check "$($psa): FindTruncated is false when everything fit" ($PsaState.FindTruncated -eq $false) ''
    }
}

# ======== ConvertTo-PsaTicketRow: one record (as Get-PsaTicket's .raw) in the same shape ========
foreach ($psa in $PSAS) {
    $fx = $TicketFx[$psa]
    $one = & $fx.row 11 42 $true (Iso -48) (Iso -5)
    Use-Routes $psa @()
    Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
        $null = Connect-Psa
        $x = ConvertTo-PsaTicketRow $one
        Check "$($psa): ConvertTo-PsaTicketRow normalizes a single record" ($x.id -eq '11' -and $x.number -eq $fx.number -and $x.companyId -eq '42' -and $x.isClosed -and $x.created -is [datetime] -and $x.priorityLevel -eq 'high') ($x | ConvertTo-Json -Depth 1 -Compress -WarningAction SilentlyContinue)
    }
}

# ======== Find-PsaTickets: status, created-after and text are sent ========
foreach ($psa in $PSAS) {
    $fx = $TicketFx[$psa]
    Use-Routes $psa @(@{ m = 'GET'; u = $fx.list; r = (& $fx.wrap @() 1 $false 0) })
    Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
        $null = Connect-Psa
        $r = @(Find-PsaTickets -Status $fx.wait -CompanyId 42 -CreatedAfter $Now.AddDays(-7) -Text 'printer')
        $u = Unesc (@(Get-Calls 'GET' $fx.list)[0].Uri)
        Check "$($psa): Find sends the status, created-after and text filters" ($r.Count -eq 0 -and [bool](& $fx.shape2 $u)) $u
    }
}

# ======== Find-PsaTickets: paging and -Max ========
foreach ($psa in $PSAS) {
    $fx = $TicketFx[$psa]
    $all = @(for ($i = 1; $i -le ($fx.size + 3); $i++) { & $fx.row (100 + $i) 42 $false (Iso (-500 + $i)) (Iso (-400 + $i)) })
    $global:PagingAll = $all; $global:PagingFx = $fx
    Use-Routes $psa @(@{ m = 'GET'; u = $fx.list; r = {
                param($c, $n)
                $m = [regex]::Match($c.Uri, $global:PagingFx.pageRx); $p = if ($m.Success) { [int]$m.Groups[1].Value } else { 1 }
                $sz = $global:PagingFx.size
                $slice = @($global:PagingAll | Select-Object -Skip (($p - 1) * $sz) -First $sz)
                return (& $global:PagingFx.wrap $slice $p ($p * $sz -lt $global:PagingAll.Count) $global:PagingAll.Count)
            }
        })
    Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
        $null = Connect-Psa
        $r = @(Find-PsaTickets -Open -CompanyId 42 -Max 1000)
        $n1 = @(Get-Calls 'GET' $fx.list).Count
        Check "$($psa): Find follows paging to the end ($($fx.size + 3) rows over 2 pages)" ($r.Count -eq ($fx.size + 3) -and $n1 -eq 2 -and -not $PsaState.FindTruncated -and $r[0].id -eq '101') "rows=$($r.Count) calls=$n1"
        $Mock.Calls.Clear()
        $r = @(Find-PsaTickets -Open -CompanyId 42 -Max 5)
        Check "$($psa): -Max stops early and sets FindTruncated" ($r.Count -eq 5 -and $PsaState.FindTruncated -and @(Get-Calls 'GET' $fx.list).Count -eq 1) "rows=$($r.Count) truncated=$($PsaState.FindTruncated) calls=$(@(Get-Calls 'GET' $fx.list).Count)"
        $r = @(Find-PsaTickets -Open -CompanyId 42 -Max 1000 -Order newest)
        Check "$($psa): -Order newest puts the newest first" ($r[0].id -eq [string](100 + $fx.size + 3)) $r[0].id
    }
}

# ======== Find-PsaTickets: 403 and input checks ========
foreach ($psa in $PSAS) {
    $fx = $TicketFx[$psa]
    Use-Routes $psa @(@{ m = 'GET'; u = $fx.list; r = { param($c, $n) New-HttpError 403 '{"message":"denied"}' } })
    Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
        $null = Connect-Psa
        $m = Get-ThrowMessage { Find-PsaTickets -Open }
        Check "$($psa): a 403 on Find is a plain permission sentence" ($m -match "refused to list tickets \(HTTP 403\)\. Give the API user permission") $m
    }
}
Use-Routes 'connectwise' @()
Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
    $null = Connect-Psa
    $m = Get-ThrowMessage { Find-PsaTickets -CompanyId 'Contoso' }
    Check 'Find refuses a company name before calling the PSA' ($m -match 'numeric PSA company id' -and @(Get-Calls 'GET' '*/service/tickets*').Count -eq 0) $m
    $m = Get-ThrowMessage { Find-PsaTickets -Open -Closed }
    Check 'Find refuses -Open with -Closed' ($m -match 'not both') $m
    $r = @(Find-PsaTickets -CompanyId '@CompanyPsaId' -Max 1)
    Check 'Find treats an unfilled @token company as no company filter' (@(Get-Calls 'GET' '*/service/tickets*').Count -eq 1 -and (Unesc (Get-LastCall).Uri) -notmatch 'company/id') (Get-LastCall).Uri
}

# ======== Find-PsaTickets: closed-date range ========
Use-Routes 'connectwise' @(@{ m = 'GET'; u = '*/service/tickets[?]*'; r = , @((O @{ id = 1; summary = 'A'; closedFlag = $true; closedDate = (Iso -30); company = (O @{ id = 42 }); _info = (O @{ dateEntered = (Iso -50) }) }), (O @{ id = 2; summary = 'B'; closedFlag = $true; closedDate = (Iso -100); company = (O @{ id = 42 }); _info = (O @{ dateEntered = (Iso -150) }) })) })
Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
    $null = Connect-Psa
    $r = @(Find-PsaTickets -Closed -ClosedAfter $Now.AddHours(-48) -ClosedBefore $Now)
    $u = Unesc (Get-LastCall).Uri
    Check 'connectwise: closed range sent, and a row outside it dropped here' ($u -match 'closedFlag=true and closedDate>=\[.*\] and closedDate<\[' -and $r.Count -eq 1 -and $r[0].id -eq '1' -and $r[0].closed -is [datetime] -and $r[0].isClosed) $u
}
Use-Routes 'zendesk' @(@{ m = 'GET'; u = '*/search[?]*'; r = (O @{ results = @((O @{ id = 1; subject = 'A'; status = 'solved'; organization_id = 42; created_at = (Iso -50) })); next_page = $null }) })
Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
    $null = Connect-Psa
    $r = @(Find-PsaTickets -Closed -ClosedAfter $Now.AddHours(-48) -ClosedBefore $Now)
    Check 'zendesk: solved range is a server filter, so a row with no solved date is kept' ((Unesc (Get-LastCall).Uri) -match 'status>=solved solved>=\S+ solved<' -and $r.Count -eq 1 -and $null -eq $r[0].closed) (Get-LastCall).Uri
}

# ======== Resolve-PsaTicketNames ========
Use-Routes 'zendesk' @(
    @{ m = 'GET'; u = '*/organizations/42'; r = (O @{ organization = (O @{ name = 'Contoso Ltd' }) }) }
    @{ m = 'GET'; u = '*/users/71'; r = (O @{ user = (O @{ name = 'Jordan Lee' }) }) }
    @{ m = 'GET'; u = '*/groups/21'; r = (O @{ group = (O @{ name = 'Service Desk' }) }) })
Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
    $null = Connect-Psa
    $a = New-PsaTicketRow @{ id = 1; companyId = 42; assigneeId = 71; queueId = 21 }
    $b = New-PsaTicketRow @{ id = 2; companyId = 42; assigneeId = '' }
    Resolve-PsaTicketNames @($a, $b)
    Check 'zendesk: names filled once per id; blank assignee is Unassigned' ($a.companyName -eq 'Contoso Ltd' -and $a.assigneeName -eq 'Jordan Lee' -and $a.queueName -eq 'Service Desk' -and $a.queue -eq 'Service Desk' -and $b.assigneeName -eq 'Unassigned' -and @(Get-Calls 'GET' '*/organizations/42').Count -eq 1) (Show-Calls)
}
Use-Routes 'autotask' @(
    @{ m = 'GET'; u = '*/Companies/query[?]*'; r = (O @{ items = @((O @{ id = 42; companyName = 'Contoso Ltd' })); pageDetails = (O @{ nextPageUrl = $null }) }) }
    @{ m = 'GET'; u = '*/Resources/29682885'; r = (O @{ item = (O @{ firstName = 'Jordan'; lastName = 'Lee' }) }) })
Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
    $null = Connect-Psa
    $a = New-PsaTicketRow @{ id = 1; companyId = 42; assigneeId = 29682885 }; $b = New-PsaTicketRow @{ id = 2; companyId = 43 }
    Resolve-PsaTicketNames @($a, $b)
    $s = AtSearch (@(Get-Calls 'GET' '*/Companies/query*')[0].Uri)
    Check 'autotask: company names in one "in" query, a missing one falls back to "Company n"' ($a.companyName -eq 'Contoso Ltd' -and $b.companyName -eq 'Company 43' -and $a.assigneeName -eq 'Jordan Lee' -and $s.filter[0].op -eq 'in') (Show-Calls)
}

# ======== Get-PsaTicketSla ========
Use-Routes 'connectwise' @(
    @{ m = 'GET'; u = '*/service/SLAs/5/priorities*'; r = , @((O @{ priority = (O @{ id = 2 }); respondHours = 2; resolutionHours = 8 })) }
    @{ m = 'GET'; u = '*/service/SLAs/5'; r = (O @{ id = 5; respondHours = 4; resolutionHours = 24 }) })
Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
    $null = Connect-Psa
    $a = New-PsaTicketRow @{ id = 1; created = $Now.AddHours(-3); raw = (O @{ sla = (O @{ id = 5 }); priority = (O @{ id = 2 }); dateResponded = $null }) }
    $b = New-PsaTicketRow @{ id = 2; created = $Now.AddHours(-3); raw = (O @{ sla = (O @{ id = 5 }); priority = (O @{ id = 3 }); dateResponded = (Iso -2) }) }
    $sa = Get-PsaTicketSla $a; $sb = Get-PsaTicketSla $b
    Check 'connectwise SLA: respond target from the priority override, resolve target after a response, cached' ($sa.kind -eq 'respond' -and [Math]::Abs(($sa.target - $Now.AddHours(-1)).TotalMinutes) -lt 2 -and $sb.kind -eq 'resolve' -and [Math]::Abs(($sb.target - $Now.AddHours(21)).TotalMinutes) -lt 2 -and @(Get-Calls 'GET' '*/service/SLAs/5').Count -eq 1) (Show-Calls)
}
$SlaCases = @(
    @{ psa = 'autotask'; raw = (O @{ firstResponseDueDateTime = (Iso -1); firstResponseDateTime = $null; resolvedDueDateTime = (Iso 5); serviceLevelAgreementHasBeenMet = $false }); kind = 'respond'; breached = $true }
    @{ psa = 'halopsa'; raw = (O @{ respondbydate = '1900-01-01T00:00:00'; responsedate = '1900-01-01T00:00:00'; fixbydate = (Iso 2) }); kind = 'resolve'; breached = $null }
    @{ psa = 'kaseyabms'; raw = (O @{ DueDate = (Iso -1) }); kind = 'due'; breached = $null }
    @{ psa = 'syncro'; raw = (O @{ due_date = (Iso 3) }); kind = 'due'; breached = $null }
    @{ psa = 'zendesk'; raw = (O @{ slas = (O @{ policy_metrics = @((O @{ metric = 'first_reply_time'; stage = 'active'; breach_at = (Iso -1) }), (O @{ metric = 'requester_wait_time'; stage = 'active'; breach_at = (Iso 5) })) }) }); kind = 'respond'; breached = $null }
)
foreach ($case in $SlaCases) {
    Use-Routes $case.psa @()
    Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
        $null = Connect-Psa
        $s = Get-PsaTicketSla (New-PsaTicketRow @{ id = 1; created = $Now.AddHours(-3); raw = $case.raw })
        Check "$($case.psa) SLA: $($case.kind) target from the PSA's own fields" ($s.source -eq 'psa' -and $s.kind -eq $case.kind -and $s.target -is [datetime] -and $s.breached -eq $case.breached) ($s | ConvertTo-Json -Depth 2 -Compress -WarningAction SilentlyContinue)
    }
}

# ======== Get-PsaTicketDevices and Get-PsaCapabilities ========
Use-Routes 'connectwise' @(@{ m = 'GET'; u = '*/service/tickets/11/configurations*'; r = , @((O @{ id = 901 }), (O @{ id = 902 })) })
Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
    $null = Connect-Psa
    $d = @(Get-PsaTicketDevices -Id 11)
    $d2 = @(Get-PsaTicketDevices -Id 11 -Row (New-PsaTicketRow @{ id = 11; configIds = @('77') }))
    Check 'connectwise: devices from the configurations sub-resource, or the row when it has them' (($d -join ',') -eq '901,902' -and ($d2 -join ',') -eq '77') "$($d -join ',') / $($d2 -join ',')"
}
Use-Routes 'zendesk' @()
Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
    $null = Connect-Psa
    $cap = Get-PsaCapabilities
    Check 'zendesk: capabilities say no agreements, invoices or primary contact; time needs a field' ($cap.agreements -eq $false -and $cap.invoices -eq $false -and $cap.primaryContact -eq $false -and $cap.time -eq 'field' -and $cap.relation -eq 'conditional') ($cap | ConvertTo-Json -Compress -WarningAction SilentlyContinue)
}

# ======== Get-PsaTicketNotes and the duplicate-note marker ========
# Each PSA returns the newer client note first, so the oldest-first sort is tested too.
$NoteFx = @{
    connectwise = @{ routes = @(@{ m = 'GET'; u = '*/service/tickets/11/notes[?]*'; r = , @((O @{ id = 2; text = 'Thanks, it works.'; internalAnalysisFlag = $false; detailDescriptionFlag = $true; dateCreated = (Iso -1); contact = (O @{ name = 'Pat Doe' }); member = $null }), (O @{ id = 1; text = 'Checked the printer. [aai-test: 1]'; internalAnalysisFlag = $true; detailDescriptionFlag = $false; dateCreated = (Iso -2); member = (O @{ identifier = 'jlee' }) })) })
        write = @('POST', "$CW/service/tickets/11/notes"); client = $true }
    autotask    = @{ routes = @(@{ m = 'GET'; u = '*/TicketNotes/query[?]*'; r = (O @{ items = @((O @{ id = 2; description = 'Thanks, it works.'; publish = 1; createDateTime = (Iso -1); createdByContactID = 5 }), (O @{ id = 1; title = 'Note'; description = 'Checked the printer. [aai-test: 1]'; publish = 2; createDateTime = (Iso -2); creatorResourceID = 29682885 })); pageDetails = (O @{ nextPageUrl = $null }) }) })
        write = @('POST', "$AT/Tickets/11/Notes"); client = $true }
    halopsa     = @{ routes = @(@{ m = 'GET'; u = '*/api/Actions[?]ticket_id=11*'; r = (O @{ actions = @((O @{ id = 2; note = '<p>Thanks, it works.</p>'; hiddenfromuser = $false; datetime = (Iso -1); who_type = 2 }), (O @{ id = 1; note = 'Checked the printer. [aai-test: 1]'; hiddenfromuser = $true; datetime = (Iso -2); who_type = 1 })) }) })
        write = @('POST', "$HALO/Actions"); client = $true }
    kaseyabms   = @{ routes = @(@{ m = 'GET'; u = '*/servicedesk/tickets/11/notes*'; r = (O @{ Result = @((O @{ Id = 2; Details = 'Thanks, it works.'; IsInternal = $false; CreatedOn = (Iso -1) }), (O @{ Id = 1; Details = 'Checked the printer. [aai-test: 1]'; IsInternal = $true; CreatedOn = (Iso -2); CreatedByName = 'Jordan Lee' })) }) })
        write = @('POST', "$BMS/servicedesk/tickets/11/notes"); client = $false }
    syncro      = @{ routes = @(@{ m = 'GET'; u = "$SY/tickets/11"; r = (O @{ ticket = (O @{ id = 11; comments = @((O @{ id = 2; subject = 'Reply'; body = 'Thanks, it works.'; hidden = $false; created_at = (Iso -1); user_id = $null }), (O @{ id = 1; subject = 'Note'; body = 'Checked the printer. [aai-test: 1]'; hidden = $true; created_at = (Iso -2); user_id = 7 })) }) }) })
        write = @('POST', "$SY/tickets/11/comment"); client = $true }
    zendesk     = @{ routes = @(@{ m = 'GET'; u = '*/tickets/11/comments*'; r = (O @{ comments = @((O @{ id = 2; body = 'Thanks, it works.'; public = $true; created_at = (Iso -1); author_id = 5 }), (O @{ id = 1; body = 'Checked the printer. [aai-test: 1]'; public = $false; created_at = (Iso -2); author_id = 71 })); next_page = $null }) }
            @{ m = 'GET'; u = "$ZD/tickets/11"; r = (O @{ ticket = (O @{ id = 11; requester_id = 5 }) }) })
        write = @('PUT', "$ZD/tickets/11"); client = $true }
}
foreach ($psa in $PSAS) {
    $nf = $NoteFx[$psa]
    Use-Routes $psa $nf.routes
    Invoke-WithLib @('psa.ps1') {
        $null = Connect-Psa
        $n = @(Get-PsaTicketNotes -Id 11)
        $ok = $n.Count -eq 2 -and $n[0].id -eq '1' -and $n[0].internal -and -not $n[0].public -and $n[1].public -and $n[1].text -eq 'Thanks, it works.' -and $n[0].created -is [datetime] -and $n[1].fromClient -eq $nf.client -and -not $n[0].fromClient
        Check "$($psa): notes come back oldest first with internal, public, date and client flags" $ok ($n | ForEach-Object { "$($_.id):$($_.internal):$($_.fromClient):$($_.text)" })
        $nn = @(Get-PsaTicketNotes -Id 11 -Newest -Max 1)
        Check "$($psa): -Newest -Max 1 returns only the newest note" ($nn.Count -eq 1 -and $nn[0].id -eq '2') ''
        Check "$($psa): Test-PsaNoteMarker finds [aai-test: 1] with or without brackets" ((Test-PsaNoteMarker -Id 11 -Marker 'aai-test: 1') -and (Test-PsaNoteMarker -Id 11 -Marker '[AAI-TEST: 1]') -and -not (Test-PsaNoteMarker -Id 11 -Marker 'aai-test: 2')) ''
        $before = @(Write-Calls).Count
        $res = Add-PsaNote -Id 11 -Text 'Checked the printer.' -Marker 'aai-test: 1'
        Check "$($psa): Add-PsaNote -Marker skips the write when the marker is already on the ticket" ($res -eq 'already-present' -and @(Write-Calls).Count -eq $before) (Show-Calls)
        $res = Add-PsaNote -Id 11 -Text 'Replaced the toner.' -Marker 'aai-test: 2'
        $l = @(Write-Calls)[-1]
        Check "$($psa): Add-PsaNote -Marker writes once with [marker] as the last line and returns 'written'" ($res -eq 'written' -and $l.Method -eq $nf.write[0] -and $l.Uri -eq $nf.write[1] -and $l.Body -match 'Replaced the toner\.\\n\[aai-test: 2\]') "$res $($l.Method) $($l.Uri) $($l.Body)"
        $res = Add-PsaNote -Id 11 -Text 'No marker.'
        Check "$($psa): Add-PsaNote without -Marker returns nothing (unchanged)" ($null -eq $res) "$res"
    }
}
Use-Routes 'connectwise' @(@{ m = 'GET'; u = '*/service/tickets/11/notes*'; r = { param($c, $n) New-HttpError 403 '{"message":"denied"}' } })
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $m = Get-ThrowMessage { Get-PsaTicketNotes -Id 11 }
    Check 'connectwise: a 403 on notes is a plain permission sentence' ($m -match 'refused to read the notes on ticket 11 \(HTTP 403\)') $m
    $m = Get-ThrowMessage { Add-PsaNote -Id 11 -Text 'x' -Marker 'aai-test: 3' }
    Check 'Add-PsaNote -Marker fails closed when the notes cannot be read (nothing written)' ($m -match "Couldn't check ticket 11 for an earlier note marked \[aai-test: 3\]" -and @(Write-Calls).Count -eq 0) $m
    $m = Get-ThrowMessage { Add-PsaNote -Id 11 -Text 'x' -Marker 'bad]marker' }
    Check 'a marker with brackets inside is refused' ($m -match "can't contain brackets") $m
}
Use-Routes 'zendesk' $NoteFx.zendesk.routes
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $null = Test-PsaNoteMarker -Id 11 -Marker 'aai-test: 1'
    Check 'zendesk: the marker check skips the extra requester read' (@(Get-Calls 'GET' "$ZD/tickets/11").Count -eq 0) (Show-Calls)
    $null = @(Get-PsaTicketNotes -Id 11 -Ticket (@{ contactId = '5' }))
    Check 'zendesk: -Ticket supplies the requester, so no ticket read' (@(Get-Calls 'GET' "$ZD/tickets/11").Count -eq 0) (Show-Calls)
}

# ======== statuses, links, ticket numbers, company lookup, default role ========
Use-Routes 'autotask' @(@{ m = 'GET'; u = '*/Tickets/query[?]*'; r = (O @{ items = @((O @{ id = 5011; ticketNumber = 'T20261008.0011' })); pageDetails = (O @{ nextPageUrl = $null }) }) }
    @{ m = 'GET'; u = '*/Resources/29682885'; r = (O @{ item = (O @{ id = 29682885; defaultServiceDeskRoleID = 29683461 }) }) })
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    Check 'autotask: status id and name from the picklist' ((Get-PsaStatusId 'waiting customer') -eq '7' -and (Get-PsaStatusName '7') -eq 'Waiting Customer' -and (Get-PsaStatusName 'New') -eq 'New') ''
    $m = Get-ThrowMessage { Get-PsaStatusId 'Nope' }
    Check 'autotask: an unknown status name lists the statuses' ($m -match "no ticket status named 'Nope'\. Its statuses are: Complete, New, Waiting Customer\.") $m
    Check 'autotask: ticket number T20261008.0011 resolves to its id; a number is used as given' ((Resolve-PsaTicketId '#T20261008.0011') -eq '5011' -and (Resolve-PsaTicketId '5011') -eq '5011') (Show-Calls)
    Check 'autotask: default role read from the resource' ((Get-PsaDefaultRole 29682885) -eq '29683461') ''
    Check 'autotask: ticket link uses the ww host' ((Get-PsaTicketUrl 11) -eq 'https://ww5.autotask.example/Mvc/ServiceDesk/TicketDetail.mvc?ticketId=11') (Get-PsaTicketUrl 11)
}
Use-Routes 'halopsa' @()
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    Check 'halopsa: status names read once from /Status and cached' ((Get-PsaStatusName '7') -eq 'Waiting Customer' -and (Get-PsaStatusId 'Closed') -eq '9' -and @(Get-Calls 'GET' "$HALO/Status").Count -eq 1) (Show-Calls)
}
Use-Routes 'kaseyabms' @(@{ m = 'GET'; u = '*/system/statuses/lookup'; r = (O @{ Result = @((O @{ Id = 3; Name = 'Completed'; IsActive = $true }), (O @{ Id = 6; Name = 'Waiting Customer'; IsActive = $true })) }) }
    @{ m = 'GET'; u = '*/servicedesk/tickets[?]Filter.TicketNumber=*'; r = (O @{ Result = @((O @{ Id = 900; TicketNumber = 'BMS-900' })) }) })
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    Check 'kaseyabms: status id from the lookup, ticket number resolved, no default link' ((Get-PsaStatusId 'Waiting Customer') -eq '6' -and (Resolve-PsaTicketId 'BMS-900') -eq '900' -and (Get-PsaTicketUrl 900) -eq '') ''
}
Use-Routes 'syncro' @(@{ m = 'GET'; u = '*/tickets[?]number=1011'; r = (O @{ tickets = @((O @{ id = 11; number = 1011 })) }) })
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    Check 'syncro: the number customers see resolves to the id' ((Resolve-PsaTicketId '1011') -eq '11') (Show-Calls)
    Check 'syncro: names pass through Get-PsaStatusId/Name' ((Get-PsaStatusId 'Waiting Customer') -eq 'Waiting Customer' -and (Get-PsaStatusName 'Resolved') -eq 'Resolved') ''
}
Use-Routes 'connectwise' @(@{ m = 'GET'; u = '*/company/companies*'; r = { param($c, $n) $u = Unesc $c.Uri; if ($u -match 'name="Contoso Ltd"') { return @((O @{ id = 42; name = 'Contoso Ltd' })) }; if ($u -match 'name="Twins"') { return @((O @{ id = 50; name = 'Twins' }), (O @{ id = 51; name = 'twins' })) }; return @() } })
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $a = Resolve-PsaCompanyId '42'; $b = Resolve-PsaCompanyId 'Contoso Ltd'; $c0 = Resolve-PsaCompanyId '@CompanyPsaId'
    Check 'Resolve-PsaCompanyId: an id is used as given, an exact name resolves, an @token means all' ($a.id -eq '42' -and $b.id -eq '42' -and $b.name -eq 'Contoso Ltd' -and $c0.id -eq '' -and @(Get-Calls 'GET' '*/company/companies*').Count -eq 1) (Show-Calls)
    $m = Get-ThrowMessage { Resolve-PsaCompanyId 'Twins' }
    Check 'Resolve-PsaCompanyId: an ambiguous name is refused plainly' ($m -eq "ConnectWise has 2 companies named 'Twins'. Use the PSA company id instead.") $m
    $m = Get-ThrowMessage { Resolve-PsaTicketId 'T123' }
    Check 'connectwise: a non-numeric ticket number is refused plainly' ($m -match "ticket numbers are numeric; 'T123' isn't") $m
    Check 'connectwise: ticket link drops the api- host prefix' ((Get-PsaTicketUrl 11) -eq 'https://na.cw.example.com/v4_6_release/services/system_io/Service/fv_sr100_request.rails?service_recid=11') (Get-PsaTicketUrl 11)
    Check 'Get-PsaTicketUrl: -Template wins and fills {id}; an @token template is ignored' ((Get-PsaTicketUrl 11 'https://portal.example.com/t/{id}') -eq 'https://portal.example.com/t/11' -and (Get-PsaTicketUrl 11 '@TicketUrl') -like 'https://na.cw.example.com/*') ''
    Check 'Get-PsaDefaultRole: not needed outside Autotask (no call)' ((Get-PsaDefaultRole 7) -eq '' -and @(Get-Calls 'GET' '*/Resources*').Count -eq 0) ''
}
Use-Routes 'zendesk' @() @{ 'PSA-TicketUrlTemplate' = 'https://help.example.com/agent/tickets/{ticketId}' }
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $u1 = Get-PsaTicketUrl 11; $u2 = Get-PsaTicketUrl 12
    Check 'Get-PsaTicketUrl: the PSA-TicketUrlTemplate secret is read once and used' ($u1 -eq 'https://help.example.com/agent/tickets/11' -and $u2 -like '*/12' -and @($Mock.Calls).Count -eq 0) "$u1 $u2"
}

# ======== Set-PsaQueue, Set-PsaTicketContact, Close-PsaTicket ========
$WriteCases = @(
    @{ psa = 'connectwise'; queue = 'Tier 2'; q = { param($l, $b) $l.Method -eq 'PATCH' -and $l.Uri -eq "$CW/service/tickets/11" -and $b[0].path -eq 'board' -and $b[0].value.name -eq 'Tier 2' }; contact = { param($l, $b) $l.Method -eq 'PATCH' -and $b[0].path -eq 'contact' -and $b[0].value.id -eq 5 } }
    @{ psa = 'autotask'; queue = 'tier 2'; q = { param($l, $b) $l.Method -eq 'PATCH' -and $l.Uri -eq "$AT/Tickets" -and $b.id -eq 11 -and $b.queueID -eq 29684 }; contact = { param($l, $b) $l.Method -eq 'PATCH' -and $b.contactID -eq 5 } }
    @{ psa = 'halopsa'; queue = '4'; q = { param($l, $b) $l.Method -eq 'POST' -and $l.Uri -eq "$HALO/Tickets" -and $b[0].team_id -eq 4 }; contact = { param($l, $b) $l.Method -eq 'POST' -and $b[0].user_id -eq 5 } }
    @{ psa = 'kaseyabms'; queue = '7'; q = { param($l, $b) $l.Method -eq 'PATCH' -and $l.Uri -eq "$BMS/servicedesk/tickets/11" -and $b[0].path -eq '/QueueId' -and $b[0].value -eq 7 }; contact = { param($l, $b) $l.Method -eq 'PATCH' -and $b[0].path -eq '/ContactId' -and $b[0].value -eq 5 } }
    @{ psa = 'syncro'; queue = 'Network'; q = { param($l, $b) $l.Method -eq 'PUT' -and $l.Uri -eq "$SY/tickets/11" -and $b.problem_type -eq 'Network' }; contact = { param($l, $b) $l.Method -eq 'PUT' -and $b.contact_id -eq 5 } }
    @{ psa = 'zendesk'; queue = 'Tier 2'; q = { param($l, $b) $l.Method -eq 'PUT' -and $l.Uri -eq "$ZD/tickets/11" -and $b.ticket.group_id -eq 22 }; contact = { param($l, $b) $l.Method -eq 'PUT' -and $b.ticket.requester_id -eq 5 } }
)
foreach ($case in $WriteCases) {
    Use-Routes $case.psa @(@{ m = 'GET'; u = '*/groups[?]*'; r = (O @{ groups = @((O @{ id = 21; name = 'Service Desk' }), (O @{ id = 22; name = 'Tier 2' })) }) })
    Invoke-WithLib @('psa.ps1') {
        $null = Connect-Psa
        Set-PsaQueue 11 $case.queue
        $l = Get-LastCall
        Check "$($case.psa): Set-PsaQueue request" ([bool](& $case.q $l (Read-Body $l))) "$($l.Method) $($l.Uri) $($l.Body)"
        Set-PsaTicketContact 11 5
        $l = Get-LastCall
        Check "$($case.psa): Set-PsaTicketContact request" ([bool](& $case.contact $l (Read-Body $l))) "$($l.Method) $($l.Uri) $($l.Body)"
    }
}
Use-Routes 'kaseyabms' @()
Invoke-WithLib @('psa.ps1') { $null = Connect-Psa; $m = Get-ThrowMessage { Set-PsaQueue 11 'Tier 2' }; Check 'kaseyabms: Set-PsaQueue refuses a queue name' ($m -match 'numeric queue id') $m; $m = Get-ThrowMessage { Set-PsaTicketContact 11 'pat' }; Check 'Set-PsaTicketContact refuses a non-numeric contact id' ($m -match 'numeric contact id') $m }
Use-Routes 'syncro' @()
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $m = Get-ThrowMessage { Close-PsaTicket -Id 11 -NotStatus 'Resolved' }
    Check 'syncro: Close-PsaTicket never closes to the status the ticket is already in' ($m -match "'Resolved' is already the closed status" -and @(Write-Calls).Count -eq 0) $m
    $st = Close-PsaTicket -Id 11 -StatusName 'Closed' -NotStatus 'Resolved'
    Check 'syncro: Close-PsaTicket to a named status' ($st -eq 'Closed' -and (Read-Body (Get-LastCall)).status -eq 'Closed') (Get-LastCall).Body
}
Use-Routes 'halopsa' @()
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $st = Close-PsaTicket -Id 11 -StatusName 'Closed' -NotStatus 'Waiting Customer'
    Check 'halopsa: Close-PsaTicket turns the status name into its id' ($st -eq '9' -and (Read-Body (Get-LastCall))[0].status_id -eq 9) (Get-LastCall).Body
}
Use-Routes 'zendesk' @()
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    $st = Close-PsaTicket -Id 11 -NotStatus 'solved'
    Check 'zendesk: Close-PsaTicket from solved goes to closed' ($st -eq 'closed' -and (Read-Body (Get-LastCall)).ticket.status -eq 'closed') (Get-LastCall).Body
}

# ======== Get-PsaTimeEntries ========
$TimeFx = @(
    @{ psa = 'connectwise'; routes = @(@{ m = 'GET'; u = '*/time/entries[?]*'; r = , @((O @{ id = 1; chargeToType = 'ServiceTicket'; chargeToId = 11; actualHours = 1.5; billableOption = 'Billable'; notes = 'Replaced the toner.'; timeStart = (Iso -3); member = (O @{ name = 'Jordan Lee' }) })) })
        req = { param($u) $u -match 'conditions=chargeToType="ServiceTicket" and chargeToId=11&' } }
    @{ psa = 'autotask'; routes = @(@{ m = 'GET'; u = '*/TimeEntries/query[?]*'; r = (O @{ items = @((O @{ id = 1; ticketID = 11; hoursWorked = 1.5; hoursToBill = 1.5; isNonBillable = $false; summaryNotes = 'Replaced the toner.'; dateWorked = (Iso -3); resourceID = 29682885 })); pageDetails = (O @{ nextPageUrl = $null }) }) })
        req = { param($u) $s = AtSearch $u; $s.filter[0].op -eq 'eq' -and $s.filter[0].field -eq 'ticketID' -and $s.filter[0].value -eq 11 } }
    @{ psa = 'halopsa'; routes = @(@{ m = 'GET'; u = '*/api/Actions[?]ticket_id=11*'; r = (O @{ actions = @((O @{ id = 1; timetaken = 1.5; chargehours = 1.5; note = '<p>Replaced the toner.</p>'; datetime = (Iso -3); who = 'Jordan Lee' }), (O @{ id = 2; timetaken = 0; note = 'No time' })) }) })
        req = { param($u) $u -match '/Actions\?ticket_id=11&excludesys=true$' } }
    @{ psa = 'kaseyabms'; routes = @(@{ m = 'GET'; u = '*/timelogs[?]*'; r = (O @{ Result = @((O @{ Id = 1; Timespent = 1.5; IsBillable = $true; Notes = 'Replaced the toner.'; StartDate = (Iso -3); FirstName = 'Jordan'; LastName = 'Lee' })) }) })
        req = { param($u) $u -match '/timelogs\?Filter\.TicketId=11&PageSize=100&PageNumber=1$' } }
    @{ psa = 'syncro'; routes = @(@{ m = 'GET'; u = '*/ticket_timers[?]*'; r = (O @{ ticket_timers = @((O @{ id = 1; active_duration = 5400; billable = $true; notes = 'Replaced the toner.'; start_time = (Iso -3); user_id = 7 })); meta = (O @{ total_pages = 1 }) }) })
        req = { param($u) $u -match '/ticket_timers\?ticket_id=11&page=1$' } }
    @{ psa = 'zendesk'; routes = @(@{ m = 'GET'; u = "$ZD/tickets/11"; r = (O @{ ticket = (O @{ id = 11; updated_at = (Iso -3); custom_fields = @((O @{ id = 360; value = 5400 })) }) }) })
        req = { param($u) $u -eq "$ZD/tickets/11" } }
)
foreach ($case in $TimeFx) {
    Use-Routes $case.psa $case.routes
    Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
        $null = Connect-Psa
        $res = Get-PsaTimeEntries -TicketId 11 -ZendeskTimeFieldId $(if ($case.psa -eq 'zendesk') { '360' } else { '' })
        $e = @($res.entries)
        $u = Unesc (@($Mock.Calls | Where-Object { $_.Method -eq 'GET' -and $_.Uri -notlike '*entityInformation*' })[0].Uri)
        Check "$($case.psa): time entries request" ([bool](& $case.req $u)) $u
        $ok = $res.supported -and $e.Count -eq 1 -and $e[0].hours -eq 1.5 -and $e[0].ticketId -eq '11' -and $e[0].date -is [datetime] -and $(if ($case.psa -eq 'zendesk') { $null -eq $e[0].billable -and -not $e[0].billableKnown -and -not $e[0].notesKnown } else { $e[0].billable -eq $true -and $e[0].billableHours -eq 1.5 -and $e[0].notes -eq 'Replaced the toner.' })
        Check "$($case.psa): time entries normalized (hours, billable, notes, date)" $ok ($e | ConvertTo-Json -Depth 2 -Compress -WarningAction SilentlyContinue)
    }
}
Use-Routes 'zendesk' @()
Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
    $null = Connect-Psa
    $res = Get-PsaTimeEntries -TicketId 11
    Check 'zendesk: no time field means supported is false with a reason, and no call' (-not $res.supported -and $res.reason -match 'Time Tracking' -and @($Mock.Calls).Count -eq 0) $res.reason
}
Use-Routes 'halopsa' @(@{ m = 'GET'; u = '*/api/Actions[?]*'; r = (O @{ actions = @() }) })
Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
    $null = Connect-Psa
    $res = Get-PsaTimeEntries -TicketIds @('11', '12', '13') -MaxTickets 2
    Check 'halopsa: ticket-by-ticket reads stop at -MaxTickets with a warning' (@(Get-Calls 'GET' '*/api/Actions*').Count -eq 2 -and @($res.warnings).Count -eq 1 -and $PsaState.Warnings.Count -eq 1) (Show-Calls)
}
Use-Routes 'connectwise' @(@{ m = 'GET'; u = '*/time/entries[?]*'; r = , @((O @{ id = 1; chargeToType = 'ServiceTicket'; chargeToId = 11; actualHours = 2; billableOption = 'DoNotBill'; timeStart = (Iso -3) }), (O @{ id = 2; chargeToType = 'ServiceTicket'; chargeToId = 12; actualHours = 1; billableOption = 'Billable'; timeStart = (Iso -400) })) })
Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
    $null = Connect-Psa
    $res = Get-PsaTimeEntries -CompanyId 42 -TicketIds @('11', '12') -After $Now.AddDays(-7) -Before $Now
    $u = Unesc (Get-LastCall).Uri
    Check 'connectwise: -CompanyId reads the company in one query with the date range (ticket ids ignored); out-of-range rows dropped' ($u -match 'conditions=company/id=42 and timeStart>=\[.*\] and timeStart<\[' -and @(Get-Calls 'GET' '*/time/entries*').Count -eq 1 -and @($res.entries).Count -eq 1 -and $res.entries[0].billable -eq $false -and $res.entries[0].billableHours -eq 0) $u
    $m = Get-ThrowMessage { Get-PsaTimeEntries }
    Check 'Get-PsaTimeEntries with no ticket says what it needs' ($m -match 'needs -TicketId or -TicketIds') $m
}

# ======== Get-PsaAgreements ========
$AgrFx = @(
    @{ psa = 'connectwise'; u = '*/finance/agreements[?]*'; r = , @((O @{ id = 1; name = 'Managed Services'; company = (O @{ id = 42 }); agreementStatus = 'Active'; billAmount = 1500; type = (O @{ name = 'MSP' }); startDate = (Iso -9000) }), (O @{ id = 2; name = 'Other'; company = (O @{ id = 43 }) })) }
    @{ psa = 'autotask'; u = '*/Contracts/query[?]*'; r = (O @{ items = @((O @{ id = 1; contractName = 'Managed Services'; companyID = 42; status = 1; setupFee = 1500 }), (O @{ id = 2; contractName = 'Other'; companyID = 43; status = 1 })); pageDetails = (O @{ nextPageUrl = $null }) }) }
    @{ psa = 'halopsa'; u = '*/ClientContract[?]*'; r = , @((O @{ id = 1; ref = 'Managed Services'; client_id = 42; active = $true; periodchargeamount = 1500 }), (O @{ id = 2; ref = 'Other'; client_id = 43 })) }
    @{ psa = 'kaseyabms'; u = '*/finance/contracts[?]*'; r = (O @{ Result = @((O @{ Id = 1; Name = 'Managed Services'; AccountId = 42; StatusName = 'Active'; Amount = 1500 }), (O @{ Id = 2; Name = 'Other'; AccountId = 43 })) }) }
    @{ psa = 'syncro'; u = '*/contracts[?]*'; r = (O @{ contracts = @((O @{ id = 1; name = 'Managed Services'; customer_id = 42; status = 'Active'; contract_amount = 1500 }), (O @{ id = 2; name = 'Other'; customer_id = 43 })) }) }
)
foreach ($case in $AgrFx) {
    Use-Routes $case.psa @(@{ m = 'GET'; u = $case.u; r = $case.r }, @{ m = 'GET'; u = '*/Contracts/entityInformation/fields'; r = (O @{ fields = @() }) })
    Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
        $null = Connect-Psa
        $res = Get-PsaAgreements -CompanyId 42
        $a = @($res.agreements)
        Check "$($case.psa): agreements for company 42 only, normalized" ($res.supported -and $a.Count -eq 1 -and $a[0].name -eq 'Managed Services' -and $a[0].active -and $a[0].amount -eq 1500) ($a | ConvertTo-Json -Depth 2 -Compress -WarningAction SilentlyContinue)
    }
}
Use-Routes 'zendesk' @()
Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') { $null = Connect-Psa; $res = Get-PsaAgreements -CompanyId 42; Check 'zendesk: agreements not supported, with a reason' (-not $res.supported -and $res.reason -and @($Mock.Calls).Count -eq 0) $res.reason }

# ======== Get-PsaInvoice ========
$InvFx = @(
    @{ psa = 'connectwise'; u = '*/finance/invoices[?]*'; r = , @((O @{ id = 9; invoiceNumber = 'INV-1001'; company = (O @{ id = 42 }); date = '2026-10-01T00:00:00Z'; total = 1650 })); derived = $true }
    @{ psa = 'autotask'; u = '*/Invoices/query[?]*'; r = (O @{ items = @((O @{ id = 9; invoiceNumber = 'INV-1001'; companyID = 42; invoiceDateTime = '2026-10-01T00:00:00Z'; fromDate = '2026-09-01T00:00:00Z'; toDate = '2026-09-30T00:00:00Z'; invoiceTotal = 1650 })); pageDetails = (O @{ nextPageUrl = $null }) }); derived = $false }
    @{ psa = 'halopsa'; u = '*/Invoice[?]search=*'; r = (O @{ invoices = @((O @{ id = 9; invoicenumber = 'INV-1001'; client_id = 42; invoice_date = '2026-10-01T00:00:00Z'; total = 1650 })) }); derived = $true }
)
foreach ($case in $InvFx) {
    Use-Routes $case.psa @(@{ m = 'GET'; u = $case.u; r = $case.r })
    Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
        $null = Connect-Psa
        $inv = Get-PsaInvoice -Number '#INV-1001'
        Check "$($case.psa): invoice found with company, total and a September period" ($inv.companyId -eq '42' -and $inv.total -eq 1650 -and $inv.periodStart.Month -eq 9 -and $inv.periodEnd.Month -eq 10 -and $inv.periodEnd.Day -eq 1 -and $inv.periodDerived -eq $case.derived) ($inv | ConvertTo-Json -Compress -WarningAction SilentlyContinue)
    }
}
foreach ($psa in @('kaseyabms', 'syncro', 'zendesk')) {
    Use-Routes $psa @()
    Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') { $null = Connect-Psa; $m = Get-ThrowMessage { Get-PsaInvoice -Number 'INV-1' }; Check "$($psa): invoices refused plainly" ($m -match "invoices can't be looked up") $m }
}

# ======== Get-PsaCompanyContacts and Get-PsaPrimaryContact ========
$Pat = @{ first = 'Pat'; last = 'Doe'; email = 'pat@contoso.com' }
$ConFx = @(
    @{ psa = 'connectwise'; primary = $true; email = $true; routes = @(
            @{ m = 'GET'; u = "$CW/company/companies/42"; r = (O @{ id = 42; defaultContact = (O @{ id = 5 }) }) }
            @{ m = 'GET'; u = '*/company/contacts[?]*'; r = , @((O @{ id = 5; firstName = 'Pat'; lastName = 'Doe'; communicationItems = @((O @{ communicationType = 'Email'; value = 'pat@contoso.com'; defaultFlag = $true })) }), (O @{ id = 6; firstName = 'Sam'; lastName = 'Lee' })) }
            @{ m = 'GET'; u = "$CW/company/contacts/5"; r = (O @{ id = 5; firstName = 'Pat'; lastName = 'Doe'; communicationItems = @((O @{ communicationType = 'Email'; value = 'pat@contoso.com'; defaultFlag = $true })) }) }) }
    @{ psa = 'autotask'; primary = $true; email = $true; routes = @(@{ m = 'GET'; u = '*/Contacts/query[?]*'; r = { param($c, $n) $s = AtSearch $c.Uri; $all = @((O @{ id = 5; firstName = 'Pat'; lastName = 'Doe'; emailAddress = 'pat@contoso.com'; primaryContact = $true }), (O @{ id = 6; firstName = 'Sam'; lastName = 'Lee'; primaryContact = $false })); if (@($s.filter | Where-Object { $_.field -eq 'primaryContact' }).Count) { $all = @($all[0]) }; return (O @{ items = $all; pageDetails = (O @{ nextPageUrl = $null }) }) } }) }
    @{ psa = 'halopsa'; primary = $true; email = $true; routes = @(@{ m = 'GET'; u = '*/Users[?]client_id=42*'; r = (O @{ users = @((O @{ id = 5; name = 'Pat Doe'; emailaddress = 'pat@contoso.com'; isprimarycontact = $true }), (O @{ id = 6; name = 'Sam Lee' })) }) }) }
    @{ psa = 'kaseyabms'; primary = $true; email = $true; routes = @(@{ m = 'GET'; u = '*/crm/contacts/summary[?]*'; r = (O @{ Result = @((O @{ Id = 5; FirstName = 'Pat'; LastName = 'Doe'; Emails = @((O @{ EmailAddress = 'pat@contoso.com' })); IsPoc = $true }), (O @{ Id = 6; FirstName = 'Sam'; LastName = 'Lee' })) }) }) }
    @{ psa = 'syncro'; primary = $false; email = $true; routes = @(@{ m = 'GET'; u = '*/contacts[?]customer_id=42*'; r = (O @{ contacts = @((O @{ id = 5; name = 'Pat Doe'; email = 'pat@contoso.com' }), (O @{ id = 6; name = 'Sam Lee' })); meta = (O @{ total_pages = 1 }) }) }
            @{ m = 'GET'; u = "$SY/customers/42"; r = (O @{ customer = (O @{ id = 42; firstname = 'Pat'; lastname = 'Doe'; email = 'pat@contoso.com' }) }) }) }
    @{ psa = 'zendesk'; primary = $false; email = $true; routes = @(@{ m = 'GET'; u = '*/organizations/42/users*'; r = (O @{ users = @((O @{ id = 5; name = 'Pat Doe'; email = 'pat@contoso.com'; active = $true }), (O @{ id = 6; name = 'Sam Lee'; active = $true })) }) }) }
)
foreach ($case in $ConFx) {
    Use-Routes $case.psa $case.routes
    Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
        $null = Connect-Psa
        $res = Get-PsaCompanyContacts -CompanyId 42
        $k = @($res.contacts)
        $ok = $k.Count -eq 2 -and $k[0].id -eq '5' -and $k[0].name -eq 'Pat Doe' -and $k[0].email -eq 'pat@contoso.com' -and $res.primarySupported -eq $case.primary -and $k[0].primary -eq $case.primary -and -not $k[1].primary
        Check "$($case.psa): company contacts normalized with the primary flag where the PSA has one" $ok ($k | ConvertTo-Json -Compress -WarningAction SilentlyContinue)
        $pc = Get-PsaPrimaryContact -CompanyId 42
        $want = $case.psa -ne 'zendesk'
        Check "$($case.psa): primary contact $(if ($want) { 'is Pat Doe' } else { 'is none (Zendesk has no primary contact)' })" ($(if ($want) { $null -ne $pc -and $pc.email -eq 'pat@contoso.com' -and $pc.name -eq 'Pat Doe' } else { $null -eq $pc })) ($pc | ConvertTo-Json -Compress -WarningAction SilentlyContinue)
    }
}

# ======== Add-PsaTicketRelation ========
$EmptyNotes = @{
    connectwise = @{ m = 'GET'; u = '*/service/tickets/11/notes*'; r = $null }
    autotask    = @{ m = 'GET'; u = '*/TicketNotes/query[?]*'; r = (O @{ items = @(); pageDetails = (O @{ nextPageUrl = $null }) }) }
    halopsa     = @{ m = 'GET'; u = '*/api/Actions[?]ticket_id=11*'; r = (O @{ actions = @() }) }
    kaseyabms   = @{ m = 'GET'; u = '*/servicedesk/tickets/11/notes*'; r = (O @{ Result = @() }) }
    syncro      = @{ m = 'GET'; u = "$SY/tickets/11"; r = (O @{ ticket = (O @{ id = 11; comments = @() }) }) }
    zendesk     = @{ m = 'GET'; u = '*/tickets/11/comments*'; r = (O @{ comments = @(); next_page = $null }) }
}
$RelFx = @(
    @{ psa = 'connectwise'; method = 'note-only'; extra = @(); link = $null }
    @{ psa = 'autotask'; method = 'native'; extra = @(@{ m = 'GET'; u = "$AT/Tickets/11"; r = (O @{ item = (O @{ id = 11; ticketType = 3 }) }) }); link = { param($l, $b) $l.Method -eq 'PATCH' -and $b.id -eq 12 -and $b.problemTicketID -eq 11 -and $b.ticketType -eq 2 } }
    @{ psa = 'halopsa'; method = 'native'; extra = @(); link = { param($l, $b) $l.Method -eq 'POST' -and $l.Uri -eq "$HALO/Tickets" -and $b[0].id -eq 12 -and $b[0].parent_id -eq 11 } }
    @{ psa = 'kaseyabms'; method = 'note-only'; extra = @(); link = $null }
    @{ psa = 'syncro'; method = 'note-only'; extra = @(); link = $null }
    @{ psa = 'zendesk'; method = 'native'; extra = @(@{ m = 'GET'; u = "$ZD/tickets/11"; r = (O @{ ticket = (O @{ id = 11; type = 'problem' }) }) }); link = { param($l, $b) $l.Method -eq 'PUT' -and $l.Uri -eq "$ZD/tickets/12" -and $b.ticket.problem_id -eq 11 -and $b.ticket.type -eq 'incident' } }
)
foreach ($case in $RelFx) {
    Use-Routes $case.psa (@($case.extra) + @($EmptyNotes[$case.psa]))
    Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
        $null = Connect-Psa
        $res = Add-PsaTicketRelation -Id 12 -RelatedId 11 -Reason 'Same printer.'
        $w = @(Write-Calls)
        $linkOk = if ($null -eq $case.link) { $w.Count -eq 1 } else { $w.Count -eq 2 -and [bool](& $case.link $w[0] (Read-Body $w[0])) }
        Check "$($case.psa): relation is $($case.method), plus one marked note on the older ticket" ($res.method -eq $case.method -and $res.note -eq 'written' -and $linkOk -and $w[-1].Body -match '\[related: 12 and 11\]' -and $w[-1].Body -match 'Related ticket: #12') "$($res.method) $($res.note) $(Show-Calls) $($w[-1].Body)"
    }
}
Use-Routes 'connectwise' @(@{ m = 'GET'; u = '*/service/tickets/11/notes*'; r = , @((O @{ id = 1; text = 'Related ticket: #12 looks like the same issue. [related: 12 and 11]'; internalAnalysisFlag = $true })) })
Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
    $null = Connect-Psa
    $res = Add-PsaTicketRelation -Id 12 -RelatedId 11
    Check 'a retried relation finds its marker and writes no second note' ($res.note -eq 'already-present' -and @(Write-Calls).Count -eq 0) (Show-Calls)
    $m = Get-ThrowMessage { Add-PsaTicketRelation -Id 11 -RelatedId 11 }
    Check 'a ticket cannot be related to itself' ($m -match 'itself') $m
}

# ======== child scope: the libraries used from functions inside a step ========
Use-Routes 'syncro' @(@{ m = 'GET'; u = '*/tickets[?]*'; r = (O @{ tickets = @((& $TicketFx.syncro.row 11 42 $false (Iso -5) (Iso -1))); meta = (O @{ total_pages = 1 }) }) })
Invoke-WithLib @('psa.ps1', 'psa-tickets.ps1') {
    function Step-Find { $null = Connect-Psa; return @(Find-PsaTickets -Open -CompanyId 42) }
    $r = @(Step-Find)
    Check 'Find-PsaTickets works from a function inside the step (child scope) and keeps FindTruncated in $PsaState' ($r.Count -eq 1 -and $PsaState.FindTruncated -eq $false) ''
}

Complete-Test
