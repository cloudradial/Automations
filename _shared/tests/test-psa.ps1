# Strict-mode tests for _shared/psa.ps1 on all six PSAs: connect, internal and public notes,
# create-ticket request shape, close, company lookup, PSA choice, retries and errors.
. (Join-Path $PSScriptRoot 'mock.ps1')

$S = @{
    connectwise = @{ 'CW-ApiUrl' = 'https://cw.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'Autotask-ApiUrl' = 'https://webservices.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    halopsa     = @{ 'Halo-ApiUrl' = 'https://halo.example.com'; 'Halo-ClientId' = 'cid'; 'Halo-ClientSecret' = 'sec' }
    kaseyabms   = @{ 'KaseyaBMS-ApiUrl' = 'https://bms.example.com'; 'KaseyaBMS-Username' = 'u'; 'KaseyaBMS-Password' = 'p'; 'KaseyaBMS-CompanyName' = 'Example MSP'; 'KaseyaBMS-NoteTypeId' = '4'; 'KaseyaBMS-NewStatusId' = '1'; 'KaseyaBMS-ClosedStatusId' = '3' }
    syncro      = @{ 'Syncro-ApiUrl' = 'https://example.syncromsp.com/api/v1'; 'Syncro-ApiKey' = 'key' }
    zendesk     = @{ 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
}
$CW = 'https://cw.example.com/v4_6_release/apis/3.0'; $AT = 'https://webservices.autotask.example/atservicesrest/v1.0'; $HALO = 'https://halo.example.com/api'
$BMS = 'https://bms.example.com/v2'; $SY = 'https://example.syncromsp.com/api/v1'; $ZD = 'https://example.zendesk.com/api/v2'
function Pick { param($v, $l, $d = $false) [pscustomobject]@{ value = $v; label = $l; isActive = $true; isDefaultValue = $d } }
$contoso = @(@{ id = 43; name = 'Contoso Ltd' }, @{ id = 42; name = 'Contoso' })

$Handler = {
    param($c, $n)
    $k = "$($c.Method) $($c.Uri)"
    switch -Wildcard -CaseSensitive ($k) {
        'POST https://halo.example.com/auth/token' { return [pscustomobject]@{ access_token = 'halo-token' } }
        'POST https://bms.example.com/v2/security/authenticate' { return [pscustomobject]@{ Result = [pscustomobject]@{ AccessToken = 'bms-token' } } }
        "GET $AT/TicketNotes/entityInformation/fields" { return [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'publish'; picklistValues = @((Pick '1' 'All Autotask Users'), (Pick '2' 'Internal Only')) },
                    [pscustomobject]@{ name = 'noteType'; picklistValues = @((Pick '13' 'System Workflow Note'), (Pick '1' 'Task Detail')) }) } }
        "GET $AT/Tickets/entityInformation/fields" { return [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'status'; picklistValues = @((Pick '1' 'New'), (Pick '5' 'Complete'), (Pick '8' 'In Progress')) },
                    [pscustomobject]@{ name = 'priority'; picklistValues = @((Pick '4' 'Critical'), (Pick '1' 'High'), (Pick '2' 'Medium' $true), (Pick '3' 'Low')) },
                    [pscustomobject]@{ name = 'queueID'; picklistValues = @((Pick '29683' 'Service Desk'), (Pick '29684' 'Projects')) }) } }
        "GET $CW/service/priorities*" { return @([pscustomobject]@{ id = 1; name = 'Priority 1 - Emergency Response' }, [pscustomobject]@{ id = 2; name = 'Priority 2 - Quick Response' }, [pscustomobject]@{ id = 3; name = 'Priority 3 - Normal Response' }) }
        "GET $CW/service/tickets/12345" { return [pscustomobject]@{ id = 12345; summary = 'Printer offline'; board = [pscustomobject]@{ id = 1 }; company = [pscustomobject]@{ id = 42 }; owner = [pscustomobject]@{ id = 7; identifier = 'jlee' }; status = [pscustomobject]@{ name = 'New' } } }
        "GET $CW/service/tickets/12345/notes*" { return @([pscustomobject]@{ id = 1; text = 'The printer at Contoso is offline.' }) }
        "GET $CW/service/boards/1/statuses*" { return @([pscustomobject]@{ id = 10; name = 'New'; defaultFlag = $true; closedStatus = $false }, [pscustomobject]@{ id = 11; name = 'Closed (resolved)'; defaultFlag = $false; closedStatus = $true }) }
        "POST $CW/service/tickets" { return [pscustomobject]@{ id = 501 } }
        "POST $AT/Tickets" { return [pscustomobject]@{ itemId = 502 } }
        "POST $HALO/Tickets" { return @([pscustomobject]@{ id = 503 }) }
        "POST $BMS/servicedesk/tickets" { return [pscustomobject]@{ Success = $true; Result = [pscustomobject]@{ Id = 504 } } }
        "POST $SY/tickets" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 505; number = 1005 } } }
        "POST $ZD/tickets" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 506 } } }
        "GET $CW/company/companies*" { return @($contoso | ForEach-Object { [pscustomobject]$_ }) }
        "GET $AT/Companies/query*" { return [pscustomobject]@{ items = @($contoso | ForEach-Object { [pscustomobject]@{ id = $_.id; companyName = $_.name } }) } }
        "GET $HALO/Client*" { return [pscustomobject]@{ clients = @($contoso | ForEach-Object { [pscustomobject]$_ }) } }
        "GET $BMS/crm/accounts*" { return [pscustomobject]@{ Result = @($contoso | ForEach-Object { [pscustomobject]@{ Id = $_.id; Name = $_.name } }) } }
        "GET $SY/customers*" { return [pscustomobject]@{ customers = @($contoso | ForEach-Object { [pscustomobject]@{ id = $_.id; business_name = $_.name } }) } }
        "GET $ZD/organizations/autocomplete*" { return [pscustomobject]@{ organizations = @($contoso | ForEach-Object { [pscustomobject]$_ }) } }
        "GET $AT/Tickets/12345" { return [pscustomobject]@{ item = [pscustomobject]@{ id = 12345; title = 'Printer offline'; description = 'd'; companyID = 42; status = 1; assignedResourceID = 0 } } }
        "GET $ZD/tickets/12345" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 12345; subject = 'Printer offline'; description = 'd'; organization_id = 42; status = 'open'; assignee_id = 99 } } }
    }
    return [pscustomobject]@{ id = 1 }
}

# What each PSA must send. auth: checks the headers of the first API call; note/public/close: [method, uri, body check].
$E = @{
    connectwise = @{
        auth   = { param($h) $h['Authorization'] -eq "Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('examplemsp+pub:priv')))" -and $h['clientId'] -eq 'cid' }
        note   = @('POST', "$CW/service/tickets/12345/notes", { param($b) $b.internalAnalysisFlag -eq $true -and $b.detailDescriptionFlag -eq $false -and $b.text -eq 'Checked the printer.' })
        public = @('POST', "$CW/service/tickets/12345/notes", { param($b) $b.internalAnalysisFlag -eq $false -and $b.detailDescriptionFlag -eq $true })
        create = @('POST', "$CW/service/tickets", { param($b) $b.summary -eq 'Printer offline' -and $b.company.id -eq 42 -and $b.priority.id -eq 2 -and $b.board.name -eq 'Service Desk' -and $b.initialDescription -like '*Contoso*' }, 'Service Desk', '501')
        close  = @('PATCH', "$CW/service/tickets/12345", { param($b) $b[0].op -eq 'replace' -and $b[0].path -eq 'status' -and $b[0].value.id -eq 11 })
    }
    autotask    = @{
        auth   = { param($h) $h['ApiIntegrationCode'] -eq 'code' -and $h['UserName'] -eq 'api@example.com' -and $h['Secret'] -eq 'sec' }
        note   = @('POST', "$AT/Tickets/12345/Notes", { param($b) $b.publish -eq 2 -and $b.noteType -eq 1 -and $b.ticketID -eq 12345 -and $b.title -eq 'Note' })
        public = @('POST', "$AT/Tickets/12345/Notes", { param($b) $b.publish -eq 1 })
        create = @('POST', "$AT/Tickets", { param($b) $b.companyID -eq 42 -and $b.title -eq 'Printer offline' -and $b.status -eq 1 -and $b.priority -eq 1 -and $b.queueID -eq 29683 -and $null -ne $b.dueDateTime -and (Get-LastCall).Body -match '"dueDateTime":"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ"' }, 'Service Desk', '502')
        close  = @('PATCH', "$AT/Tickets", { param($b) $b.id -eq 12345 -and $b.status -eq 5 })
    }
    halopsa     = @{
        auth   = { param($h) $h['Authorization'] -eq 'Bearer halo-token' }
        note   = @('POST', "$HALO/Actions", { param($b) $b[0].ticket_id -eq 12345 -and $b[0].hiddenfromuser -eq $true -and $b[0].outcome_id -eq 7 })
        public = @('POST', "$HALO/Actions", { param($b) $b[0].hiddenfromuser -eq $false })
        create = @('POST', "$HALO/Tickets", { param($b) $b[0].client_id -eq 42 -and $b[0].summary -eq 'Printer offline' -and $b[0].priority_id -eq 2 -and $b[0].team -eq 'Service Desk' }, 'Service Desk', '503')
        close  = @('POST', "$HALO/Tickets", { param($b) $b[0].id -eq 12345 -and $b[0].status_id -eq 9 })
    }
    kaseyabms   = @{
        auth   = { param($h) $h['Authorization'] -eq 'Bearer bms-token' }
        note   = @('POST', "$BMS/servicedesk/tickets/12345/notes", { param($b) $b.IsInternal -eq $true -and $b.TypeId -eq 4 -and $b.Details -eq 'Checked the printer.' -and $b.NoteDate })
        public = @('POST', "$BMS/servicedesk/tickets/12345/notes", { param($b) $b.IsInternal -eq $false })
        create = @('POST', "$BMS/servicedesk/tickets", { param($b) $b.AccountId -eq 42 -and $b.Title -eq 'Printer offline' -and $b.QueueId -eq 7 -and $b.StatusId -eq 1 -and $b.OpenDate }, '7', '504')
        close  = @('PATCH', "$BMS/servicedesk/tickets/12345", { param($b) $b[0].path -eq '/StatusId' -and $b[0].value -eq 3 })
    }
    syncro      = @{
        auth   = { param($h) $h['Authorization'] -eq 'Bearer key' }
        note   = @('POST', "$SY/tickets/12345/comment", { param($b) $b.hidden -eq $true -and $b.do_not_email -eq $true -and $b.subject -eq 'Note' })
        public = @('POST', "$SY/tickets/12345/comment", { param($b) $b.hidden -eq $false })
        create = @('POST', "$SY/tickets", { param($b) $b.customer_id -eq 42 -and $b.subject -eq 'Printer offline' -and $b.priority -eq '1 High' -and $b.problem_type -eq 'Hardware' -and $b.comments_attributes[0].body -like '*Contoso*' }, 'Hardware', '505')
        close  = @('PUT', "$SY/tickets/12345", { param($b) $b.status -eq 'Resolved' })
    }
    zendesk     = @{
        auth   = { param($h) $h['Authorization'] -eq "Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('agent@example.com/token:tok')))" }
        note   = @('PUT', "$ZD/tickets/12345", { param($b) $b.ticket.comment.public -eq $false -and $b.ticket.comment.body -eq 'Checked the printer.' })
        public = @('PUT', "$ZD/tickets/12345", { param($b) $b.ticket.comment.public -eq $true })
        create = @('POST', "$ZD/tickets", { param($b) $b.ticket.organization_id -eq 42 -and $b.ticket.priority -eq 'high' -and $b.ticket.group_id -eq 900 -and $b.ticket.comment.body -like '*Contoso*' }, '900', '506')
        close  = @('PUT', "$ZD/tickets/12345", { param($b) $b.ticket.status -eq 'solved' })
    }
}

function Test-CallShape { param([string]$Name, $Want)
    $l = Get-LastCall
    $ok = $false; $b = $null
    try { $b = Read-Body $l; $ok = ($l.Method -eq $Want[0] -and $l.Uri -eq $Want[1] -and [bool](& $Want[2] $b)) } catch { $ok = $false }
    Check $Name $ok "$(Show-Calls) / $(if ($l) { $l.Body })"
}

foreach ($psa in @('connectwise', 'autotask', 'halopsa', 'kaseyabms', 'syncro', 'zendesk')) {
    Reset-Mock (@{ 'PSA-Type' = $psa } + $S[$psa]) $Handler
    Invoke-WithLib @('psa.ps1') {
        $e = $E[$psa]
        $conn = Connect-Psa
        Check "$($psa): connect picks the PSA from PSA-Type" ($conn.Psa -eq $psa) $conn.Psa
        Add-PsaNote -Id '12345' -Text 'Checked the printer.'
        Check "$($psa): auth headers" ([bool](& $e.auth (Get-LastCall).Headers)) ((Get-LastCall).Headers | ConvertTo-Json -Compress)
        Test-CallShape "$($psa): internal note request" $e.note
        Add-PsaNote -Id '12345' -Text 'We replaced the toner.' -Public
        Test-CallShape "$($psa): public note request" $e.public
        $t = New-PsaTicket -CompanyId '42' -Summary 'Printer offline' -Description 'The printer at Contoso is offline.' -Priority high -Queue $e.create[3]
        Test-CallShape "$($psa): create-ticket request" $e.create
        Check "$($psa): create-ticket returns the new id" ($t.id -eq $e.create[4]) $t.id
        $null = Set-PsaStatus -Id '12345' -State closed
        Test-CallShape "$($psa): close request" $e.close
        $co = @(Find-PsaCompany -Name 'contoso')
        Check "$($psa): Find-PsaCompany puts the exact match first" ($co.Count -eq 2 -and $co[0].id -eq '42' -and $co[0].exact -and -not $co[1].exact) (($co | ForEach-Object { "$($_.id)=$($_.name)" }) -join ',')
    }
}

# --- PSA choice ---
Reset-Mock (@{ 'PSA-Type' = 'connectwise' } + $S['zendesk']) $Handler
Invoke-WithLib @('psa.ps1') {
    Check 'Get-PsaType: input beats the secret, aliases work' ((Get-PsaType 'zendesk-ticketing') -eq 'zendesk' -and (Get-PsaType 'Halo') -eq 'halopsa' -and (Get-PsaType 'kaseya') -eq 'kaseyabms') ''
    Check 'Get-PsaType: an unfilled @token falls back to PSA-Type' ((Get-PsaType '@PSA') -eq 'connectwise') ''
    $m = Get-ThrowMessage { Get-PsaType 'freshdesk' }
    Check 'Get-PsaType: unsupported PSA is a plain error' ($m -match "isn't supported") $m
}
Reset-Mock $S['connectwise'].Clone() $Handler
Invoke-WithLib @('psa.ps1') { Check 'Get-PsaType: no PSA-Type but CW secrets -> connectwise' ((Get-PsaType '') -eq 'connectwise') '' }
Reset-Mock @{} $Handler
Invoke-WithLib @('psa.ps1') {
    Check 'Get-PsaType: nothing set up -> empty' ((Get-PsaType '') -eq '') ''
    $m = Get-ThrowMessage { Connect-Psa }
    Check 'Connect-Psa: nothing set up names PSA-Type' ($m -match 'PSA-Type') $m
    $m = Get-ThrowMessage { Add-PsaNote '1' 'x' }
    Check 'calls before Connect-Psa say so' ($m -match 'Connect-Psa') $m
}
Reset-Mock @{ 'Autotask-ApiUrl' = 'https://webservices.autotask.example' } $Handler
Invoke-WithLib @('psa.ps1') {
    $m = Get-ThrowMessage { Connect-Psa 'autotask' }
    Check 'Connect-Psa: missing secrets are named' ($m -match 'Autotask-ApiIntegrationCode' -and $m -match 'Autotask-Secret' -and $m -notmatch 'Autotask-ApiUrl') $m
}

# --- Autotask details ---
Reset-Mock (@{ 'Autotask-NotePublishId' = '7'; 'Autotask-NoteTypeId' = '9' } + $S['autotask']) $Handler
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'autotask'
    Add-PsaNote '12345' 'x' -Title 'Ticket routing'
    $b = Read-Body (Get-LastCall)
    Check 'autotask: secret ids override the picklist, title passed through' ($b.publish -eq 7 -and $b.noteType -eq 9 -and $b.title -eq 'Ticket routing' -and @(Get-Calls 'GET' '*entityInformation*').Count -eq 0) (Show-Calls)
}
Reset-Mock $S['autotask'].Clone() $Handler
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'autotask'
    $null = New-PsaTicket -CompanyId 42 -Summary 'Printer offline'
    $b = Read-Body (Get-LastCall)
    Check 'autotask: no priority hint uses the default picklist value' ($b.priority -eq 2 -and -not $b.PSObject.Properties['queueID']) ((Get-LastCall).Body)
    Add-PsaNote '12345' 'a'; Add-PsaNote '12345' 'b'
    Check 'autotask: picklists are read once per entity' (@(Get-Calls 'GET' '*TicketNotes/entityInformation*').Count -eq 1) (Show-Calls)
    $m = Get-ThrowMessage { New-PsaTicket -CompanyId 42 -Summary 'x' -Queue 'Nope' }
    Check 'autotask: unknown queue is a plain error' ($m -match "no ticket queue named 'Nope'") $m
    $m = Get-ThrowMessage { Set-PsaAssignee '12345' '5' }
    Check 'autotask: assignee without role is a plain error' ($m -match 'role') $m
    Set-PsaAssignee '12345' '5' '29682885'
    $b = Read-Body (Get-LastCall)
    Check 'autotask: assignee sends resource and role' ($b.assignedResourceID -eq 5 -and $b.assignedResourceRoleID -eq 29682885) ((Get-LastCall).Body)
    $null = Set-PsaStatus '12345' -State open
    Check 'autotask: reopen sets New' ((Read-Body (Get-LastCall)).status -eq 1) ((Get-LastCall).Body)
    $t = Get-PsaTicket '12345'
    Check 'autotask: Get-PsaTicket normalizes' ($t.summary -eq 'Printer offline' -and $t.companyId -eq '42' -and $t.assigneeId -eq '') ($t | ConvertTo-Json -Compress -Depth 2)
}

# --- ConnectWise details ---
Reset-Mock $S['connectwise'].Clone() $Handler
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'cw'
    $null = New-PsaTicket -CompanyId 42 -Summary ('x' * 150) -Priority critical -Queue '12'
    $b = Read-Body (Get-LastCall)
    Check 'connectwise: summary trimmed to 100, critical -> Emergency, numeric board id' ($b.summary.Length -eq 100 -and $b.priority.id -eq 1 -and $b.board.id -eq 12) ((Get-LastCall).Body)
    Check 'connectwise: critical also sends impact and urgency High/High for the priority matrix' ($b.impact -eq 'High' -and $b.severity -eq 'High') ((Get-LastCall).Body)
    $null = New-PsaTicket -CompanyId 42 -Summary 'x' -Priority low
    $b = Read-Body (Get-LastCall)
    Check 'connectwise: low sends Low/Low' ($b.impact -eq 'Low' -and $b.severity -eq 'Low') ((Get-LastCall).Body)
    $null = New-PsaTicket -CompanyId 42 -Summary 'x'
    $b = Read-Body (Get-LastCall)
    Check 'connectwise: no priority hint sends no priority, impact or urgency' (-not $b.PSObject.Properties['priority'] -and -not $b.PSObject.Properties['impact'] -and -not $b.PSObject.Properties['severity']) ((Get-LastCall).Body)
    $null = Set-PsaStatus '12345' -State open
    Check 'connectwise: reopen picks the default status' ((Read-Body (Get-LastCall))[0].value.id -eq 10) ((Get-LastCall).Body)
    Set-PsaAssignee '12345' 'jlee'
    Check 'connectwise: assign by identifier' ((Read-Body (Get-LastCall))[0].value.identifier -eq 'jlee') ((Get-LastCall).Body)
    $t = Get-PsaTicket '12345'
    Check 'connectwise: Get-PsaTicket reads the first note as the description' ($t.description -like '*Contoso*' -and $t.assigneeId -eq 'jlee' -and $t.companyId -eq '42') ($t | ConvertTo-Json -Compress -Depth 2)
    $m = Get-ThrowMessage { New-PsaTicket -CompanyId 42 -Summary 'x' -Priority 'whenever' }
    Check 'priority hint must be known' ($m -match 'critical, high, medium, low') $m
}

# --- ConnectWise: an API member that can't read priorities still opens the ticket ---
Reset-Mock $S['connectwise'].Clone() {
    param($c, $n)
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/service/priorities*') { New-HttpError 403 '{"code":"Security","message":"You do not have security permission to perform this action."}' }
    if ($c.Method -eq 'POST' -and $c.Uri -like '*/service/tickets') { return [pscustomobject]@{ id = 601 } }
    return [pscustomobject]@{ id = 1 }
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'cw'
    $t = New-PsaTicket -CompanyId 42 -Summary '[Risky sign-in] admin@contoso.com: Microsoft flagged medium risk' -Priority critical
    $b = Read-Body (Get-LastCall)
    Check 'connectwise: priorities 403 -> ticket still opened, no priority id, impact/urgency High/High sent' ($t.id -eq '601' -and -not $b.PSObject.Properties['priority'] -and $b.impact -eq 'High' -and $b.severity -eq 'High' -and (Get-LastCall).Method -eq 'POST') ((Get-LastCall).Body)
    Check 'connectwise: priorities 403 -> a warning says the matrix sets it from High/High and names the permission' (@($PsaState.Warnings | Where-Object { $_ -match "^ConnectWise wouldn't list ticket priorities" -and $_ -match 'impact and urgency \(High/High\)' -and $_ -match 'instead of being set to critical' -and $_ -match 'Inquire access to priorities' }).Count -eq 1) (@($PsaState.Warnings) -join ' | ')
}

# --- ConnectWise: an API member that can't read board statuses still changes status, by name ---
# The board has 'Waiting Customer' and 'Closed' (not 'Closed (resolved)'); a name the board lacks gets a 400.
$CwStat = @{ now = 'New' }
$CwBoardNames = @('New', 'Waiting Customer', 'Resolved', 'Closed')
Reset-Mock $S['connectwise'].Clone() {
    param($c, $n)
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/service/boards/*/statuses*') { New-HttpError 403 '{"code":"Security","message":"You do not have security permission to perform this action."}' }
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/service/tickets/12345') { return [pscustomobject]@{ id = 12345; board = [pscustomobject]@{ id = 1 }; status = [pscustomobject]@{ name = $CwStat.now } } }
    if ($c.Method -eq 'PATCH' -and $c.Uri -like '*/service/tickets/12345') {
        $want = [string](($c.Body | ConvertFrom-Json -NoEnumerate)[0].value.name)
        if ($CwBoardNames -notcontains $want) { New-HttpError 400 '{"code":"InvalidObject","message":"status is invalid"}' }
        $CwStat.now = $want; return [pscustomobject]@{ id = 12345 }
    }
    return [pscustomobject]@{ id = 1 }
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'cw'
    $r = Set-PsaStatus -Id '12345' -State open -StatusName 'Waiting Customer'
    $p = @(Get-Calls 'PATCH' '*/service/tickets/12345')
    Check 'connectwise: statuses 403 -> a named status is set by name, read back, one PATCH' ($r -eq 'Waiting Customer' -and $p.Count -eq 1 -and (Read-Body $p[0])[0].value.name -eq 'Waiting Customer') (Show-Calls)
    Check 'connectwise: statuses 403 -> a warning names the permission' (@($PsaState.Warnings | Where-Object { $_ -match "wouldn't list the statuses of board 1" -and $_ -match 'Table Setup' }).Count -eq 1) (@($PsaState.Warnings) -join ' | ')
    $CwStat.now = 'Resolved'
    $r = Close-PsaTicket -Id '12345' -NotStatus 'Resolved'
    $names = @(Get-Calls 'PATCH' '*/service/tickets/12345' | ForEach-Object { (Read-Body $_)[0].value.name })
    Check 'connectwise: statuses 403 -> close without a name tries the usual closed names, skips the current status, stops at the first the board has' ($r -eq 'Closed' -and ($names -join '|') -eq 'Waiting Customer|Closed (resolved)|Closed') ($names -join '|')
    $m = Get-ThrowMessage { Set-PsaStatus -Id '12345' -State open -StatusName 'Waiting on Client' }
    Check 'connectwise: statuses 403 -> an unknown name is a plain error naming what to fix, and the status is unchanged' ($m -match "Couldn't set a 'Waiting on Client' status on ConnectWise ticket 12345" -and $m -match 'Inquire access' -and $CwStat.now -eq 'Closed') $m
}
Reset-Mock $S['connectwise'].Clone() {
    param($c, $n)
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/service/boards/*/statuses*') { New-HttpError 500 '{"code":"ConnectWiseApi","message":"timeout"}' }
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/service/tickets/12345') { return [pscustomobject]@{ id = 12345; board = [pscustomobject]@{ id = 1 }; status = [pscustomobject]@{ name = 'New' } } }
    return [pscustomobject]@{ id = 1 }
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'cw'
    $m = Get-ThrowMessage { Set-PsaStatus -Id '12345' -StatusName 'Waiting Customer' }
    Check 'connectwise: a statuses read that fails for another reason still stops, with no PATCH' ($m -match 'HTTP 500' -and @(Get-Calls 'PATCH' '*').Count -eq 0) $m
}

# --- ConnectWise conditions: the exact query strings sent ---
Reset-Mock $S['connectwise'].Clone() {
    param($c, $n)
    if ($c.Uri -like '*/company/companies?conditions=name%3D*') { return @() }
    if ($c.Uri -like '*/company/companies?conditions=name%20contains*') { return @([pscustomobject]@{ id = 44; name = 'Contoso "East" Ltd' }) }
    if ($c.Uri -like '*/service/tickets/count*') { return [pscustomobject]@{ count = 3 } }
    if ($c.Uri -like '*/service/tickets?conditions=*') { return @([pscustomobject]@{ id = 1; dateEntered = '2026-09-30T12:00:00Z' }) }
    return $null
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'connectwise'
    $co = @(Find-PsaCompany -Name 'Contoso')
    $calls = @(Get-Calls 'GET' '*/company/companies*')
    Check 'connectwise: Find-PsaCompany exact condition sent in full' ($calls.Count -eq 2 -and $calls[0].Uri -ceq "$CW/company/companies?conditions=name%3D%22Contoso%22%20and%20deletedFlag%3Dfalse&pageSize=25") (Show-Calls)
    Check 'connectwise: Find-PsaCompany falls back to contains' ($calls[1].Uri -ceq "$CW/company/companies?conditions=name%20contains%20%22Contoso%22%20and%20deletedFlag%3Dfalse&pageSize=25" -and $co.Count -eq 1 -and $co[0].id -eq '44') (Show-Calls)
    $Mock.Calls.Clear()
    $null = @(Find-PsaCompany -Name 'Contoso "East"')
    Check 'connectwise: quotes in a name are escaped inside the condition' ((@(Get-Calls 'GET' '*/company/companies*')[0]).Uri -ceq "$CW/company/companies?conditions=name%3D%22Contoso%20%5C%22East%5C%22%22%20and%20deletedFlag%3Dfalse&pageSize=25") (Show-Calls)
    $Mock.Calls.Clear()
    $null = Get-PsaOpenCount 'jlee'
    Check 'connectwise: Get-PsaOpenCount condition sent in full' ((Get-LastCall).Uri -ceq "$CW/service/tickets/count?conditions=owner%2Fidentifier%3D%22jlee%22%20and%20closedFlag%3Dfalse") (Get-LastCall).Uri
    $null = Get-PsaOpenCount '7'
    Check 'connectwise: numeric owner id is unquoted' ((Get-LastCall).Uri -ceq "$CW/service/tickets/count?conditions=owner%2Fid%3D7%20and%20closedFlag%3Dfalse") (Get-LastCall).Uri
    $null = Get-PsaLastAssigned 'jlee'
    Check 'connectwise: Get-PsaLastAssigned condition sent in full' ((Get-LastCall).Uri -ceq "$CW/service/tickets?conditions=owner%2Fidentifier%3D%22jlee%22&orderBy=dateEntered%20desc&pageSize=1&fields=id,dateEntered") (Get-LastCall).Uri
}

# --- retries and errors ---
Reset-Mock $S['zendesk'].Clone() {
    param($c, $n)
    if ($c.Uri -like '*/tickets/777' -and $n -lt 3) { New-HttpError 429 '' '2' }
    if ($c.Uri -like '*/tickets/888') { New-HttpError 422 '{"error":"RecordInvalid","description":"Record validation errors"}' }
    return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 777; subject = 's'; description = 'd'; organization_id = 1; status = 'open'; assignee_id = $null } }
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'zendesk'
    $t = Get-PsaTicket '777'
    Check 'Invoke-Psa: 429 retried honoring Retry-After' ($t.id -eq '777' -and @(Get-Calls 'GET' '*/tickets/777').Count -eq 3 -and @($Mock.Sleeps).Count -eq 2 -and $Mock.Sleeps[0] -eq 2) "$(Show-Calls) sleeps=$(@($Mock.Sleeps) -join ',')"
    $m = Get-ThrowMessage { Add-PsaNote '888' 'x' }
    Check 'Invoke-PSA: other errors name the PSA, call and status' ($m -match '^Zendesk PUT /tickets/888 failed \(HTTP 422\)' -and $m -match 'RecordInvalid') $m
}

# --- child scope: library used from functions inside the step, state kept across calls ---
Reset-Mock (@{ 'PSA-Type' = 'syncro' } + $S['syncro']) $Handler
Invoke-WithLib @('psa.ps1') {
    function Step-Connect { $null = Connect-Psa }
    function Step-Note { Add-PsaNote '12345' 'From a nested function.' }
    Step-Connect; Step-Note
    Check 'state survives across step functions (child scope)' ((Get-LastCall).Uri -eq "$SY/tickets/12345/comment") (Show-Calls)
}

# --- open count and last assigned on Zendesk ---
Reset-Mock $S['zendesk'].Clone() {
    param($c, $n)
    if ($c.Uri -like '*/search/count*') { return [pscustomobject]@{ count = 4 } }
    if ($c.Uri -like '*/search?*') { return [pscustomobject]@{ results = @([pscustomobject]@{ created_at = '2026-09-30T12:00:00Z' }) } }
    return $null
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'zendesk'
    Check 'Get-PsaOpenCount: zendesk search count' ((Get-PsaOpenCount '99') -eq 4) (Show-Calls)
    $d = Get-PsaLastAssigned '99'
    Check 'Get-PsaLastAssigned: zendesk newest ticket date' ($d.Year -eq 2026 -and $d.Month -eq 9 -and $d.Day -eq 30) "$d"
}
Reset-Mock (@{ 'PSA-Type' = 'kaseyabms' } + $S['kaseyabms']) $Handler
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa
    Check 'Kaseya BMS: open count and last assigned return $null (not supported)' ($null -eq (Get-PsaOpenCount '5') -and $null -eq (Get-PsaLastAssigned '5')) ''
}

# --- Status names vs numbers: statuses are customized per partner, and some API roles can't list them ---
$Forbidden = '{"message":"You do not have permission to read this."}'
# Autotask: the status picklist can't be read.
Reset-Mock $S['autotask'].Clone() {
    param($c, $n)
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/Tickets/entityInformation/fields') { New-HttpError 403 $Forbidden }
    return [pscustomobject]@{ itemId = 12345 }
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'autotask'
    $r = Set-PsaStatus -Id '12345' -StatusName '8'
    $p = @(Get-Calls 'PATCH' '*/Tickets')
    Check 'autotask: a status number is sent as given, with no picklist read' ($r -eq '8' -and $p.Count -eq 1 -and (Read-Body $p[0]).status -eq 8 -and @(Get-Calls 'GET' '*entityInformation*').Count -eq 0) (Show-Calls)
    $m = Get-ThrowMessage { Set-PsaStatus -Id '12345' -StatusName 'Waiting Customer' }
    Check 'autotask: picklist 403 -> a status name stops with a plain sentence asking for the number, and nothing is changed' ($m -match "Autotask didn't list its ticket statuses" -and $m -match "'Waiting Customer'" -and $m -match 'Enter the status number' -and @(Get-Calls 'PATCH' '*').Count -eq 1) $m
    $r = Set-PsaStatus -Id '12345' -State closed
    Check 'autotask: picklist 403 -> closing with no name still uses Complete (5)' ($r -eq '5' -and (Read-Body @(Get-Calls 'PATCH' '*/Tickets')[-1]).status -eq 5) (Show-Calls)
    $m = Get-ThrowMessage { $null = Get-PsaStatusId 'Waiting Customer' }
    Check 'autotask: Get-PsaStatusId with no picklist asks for the number' ($m -match 'Enter the status number') $m
    Check 'autotask: Get-PsaStatusId passes a number through' ((Get-PsaStatusId ' 12 ') -eq '12') ''
}
Reset-Mock $S['autotask'].Clone() $Handler
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'autotask'
    $m = Get-ThrowMessage { Set-PsaStatus -Id '12345' -StatusName 'Waiting Customer' }
    Check 'autotask: an unknown name says a number works too' ($m -match "no ticket status named 'Waiting Customer'" -and $m -match 'or the status number') $m
    $m = Get-ThrowMessage { $null = Get-PsaStatusId 'Waiting Customer' }
    Check 'autotask: Get-PsaStatusId lists the statuses and says a number works too' ($m -match 'Its statuses are: Complete, In Progress, New' -and $m -match 'or the status number') $m
}
# HaloPSA: /Status can be read, then can't.
Reset-Mock $S['halopsa'].Clone() {
    param($c, $n)
    if ($c.Uri -eq 'https://halo.example.com/auth/token') { return [pscustomobject]@{ access_token = 'halo-token' } }
    if ($c.Method -eq 'GET' -and $c.Uri -eq "$HALO/Status") { return , @([pscustomobject]@{ id = 21; name = 'Waiting on User' }, [pscustomobject]@{ id = 9; name = 'Closed' }) }
    return [pscustomobject]@{ id = 12345 }
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'halopsa'
    $r = Set-PsaStatus -Id '12345' -State open -StatusName 'waiting on user'
    $p = @(Get-Calls 'POST' "$HALO/Tickets")
    Check 'halopsa: a status name is matched to its id (it used to be refused)' ($r -eq '21' -and $p.Count -eq 1 -and (Read-Body $p[0])[0].status_id -eq 21) (Show-Calls)
}
Reset-Mock $S['halopsa'].Clone() {
    param($c, $n)
    if ($c.Uri -eq 'https://halo.example.com/auth/token') { return [pscustomobject]@{ access_token = 'halo-token' } }
    if ($c.Method -eq 'GET' -and $c.Uri -eq "$HALO/Status") { New-HttpError 403 $Forbidden }
    return [pscustomobject]@{ id = 12345 }
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'halopsa'
    $m = Get-ThrowMessage { Set-PsaStatus -Id '12345' -State open -StatusName 'Waiting on User' }
    Check 'halopsa: /Status 403 -> a status name stops with a plain sentence asking for the number, no POST' ($m -match "HaloPSA didn't list its ticket statuses" -and $m -match 'Enter the status number' -and @(Get-Calls 'POST' "$HALO/Tickets").Count -eq 0) $m
    $r = Set-PsaStatus -Id '12345' -State open -StatusName '21'
    Check 'halopsa: /Status 403 -> a status number still works' ($r -eq '21' -and (Read-Body @(Get-Calls 'POST' "$HALO/Tickets")[-1])[0].status_id -eq 21) (Show-Calls)
}
# Kaseya BMS: the status lookup comes back empty.
Reset-Mock $S['kaseyabms'].Clone() {
    param($c, $n)
    if ($c.Uri -eq 'https://bms.example.com/v2/security/authenticate') { return [pscustomobject]@{ Result = [pscustomobject]@{ AccessToken = 'bms-token' } } }
    if ($c.Method -eq 'GET' -and $c.Uri -eq "$BMS/system/statuses/lookup") { return [pscustomobject]@{ Result = @() } }
    return [pscustomobject]@{ Result = [pscustomobject]@{ Id = 12345 } }
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'kaseyabms'
    $m = Get-ThrowMessage { Set-PsaStatus -Id '12345' -State open -StatusName 'Waiting on Customer' }
    Check 'kaseyabms: an empty status list -> a status name asks for the number, no PATCH' ($m -match "Kaseya BMS didn't list its ticket statuses" -and $m -match 'Enter the status number' -and @(Get-Calls 'PATCH' '*').Count -eq 0) $m
    $r = Set-PsaStatus -Id '12345' -State open -StatusName '14'
    Check 'kaseyabms: a status number is sent as given' ($r -eq '14' -and (Read-Body @(Get-Calls 'PATCH' "$BMS/servicedesk/tickets/12345")[-1])[0].value -eq 14) (Show-Calls)
}


# --- ConnectWise board moves: statuses and teams belong to a board ---
# Live on staging, moving a ticket to another board with only the board op failed with HTTP 400 "Service Status 16
# not found for Service Board 14" and "Service Team 25 not found for Service Board 14". The move now sends ONE
# json-patch with a status and team that exist on the new board, then reads the ticket back.
$TBoards = @{
    '1'  = [pscustomobject]@{ id = 1; name = 'Service Desk'; inactiveFlag = $false }
    '14' = [pscustomobject]@{ id = 14; name = 'Test Board'; inactiveFlag = $false }
    '15' = [pscustomobject]@{ id = 15; name = 'Tier 2'; inactiveFlag = $false }
    '16' = [pscustomobject]@{ id = 16; name = 'Old Board'; inactiveFlag = $true }
    '17' = [pscustomobject]@{ id = 17; name = 'Tier 3'; inactiveFlag = $false }
}
function CwSt { param($id, $name, [bool]$def = $false, [bool]$closed = $false) [pscustomobject]@{ id = $id; name = $name; defaultFlag = $def; closedStatus = $closed; inactive = $false } }
$TBoardStatuses = @{
    '1'  = @((CwSt 10 'New' $true), (CwSt 12 'In Progress'), (CwSt 13 'Waiting Vendor'), (CwSt 11 'Closed' $false $true))
    '14' = @((CwSt 20 'New (not responded)' $true), (CwSt 21 'In Progress'), (CwSt 22 'Closed' $false $true))
    '15' = @((CwSt 30 'Open'), (CwSt 31 'Assigned' $true), (CwSt 32 'Waiting Vendor' $false $true))
    '17' = @((CwSt 70 'Closed' $false $true), (CwSt 71 'Triage'), (CwSt 72 'Working'))
}
$TBoardTeams = @{
    '1'  = @([pscustomobject]@{ id = 25; name = 'Help Desk Team'; defaultFlag = $true })
    '14' = @([pscustomobject]@{ id = 40; name = 'Escalations'; defaultFlag = $false })
    '15' = @([pscustomobject]@{ id = 50; name = 'Tier 2 Team'; defaultFlag = $true })
    '17' = @([pscustomobject]@{ id = 60; name = 'help desk team'; defaultFlag = $false }, [pscustomobject]@{ id = 61; name = 'Night'; defaultFlag = $true })
}
# The board names a status-by-name PATCH may use when the statuses can't be listed (the rest get a 400).
$TBm = @{ board = '1'; status = 'In Progress'; team = 25; ignorePatch = $false; statuses403 = $false; boards403 = $false; byName = @('New (not responded)', 'In Progress') }
$TBoardHandler = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    if ($c.Method -eq 'GET' -and $u -eq "$CW/service/tickets/12345") {
        $b = $TBoards[$TBm.board]
        $t = [ordered]@{ id = 12345; board = [pscustomobject]@{ id = $b.id; name = $b.name }; status = [pscustomobject]@{ name = $TBm.status } }
        if ($TBm.team) { $t.team = [pscustomobject]@{ id = $TBm.team; name = 'Help Desk Team' } }
        return [pscustomobject]$t
    }
    if ($c.Method -eq 'GET' -and $u -match '/service/boards/(\d+)/statuses') { if ($TBm.statuses403) { New-HttpError 403 '{"code":"Security","message":"You do not have security permission to perform this action."}' }; return , @($TBoardStatuses[$Matches[1]]) }
    if ($c.Method -eq 'GET' -and $u -match '/service/boards/(\d+)/teams') { return , @($TBoardTeams[$Matches[1]]) }
    if ($c.Method -eq 'GET' -and $u -match '/service/boards/(\d+)$') { if ($TBoards.Contains($Matches[1])) { return $TBoards[$Matches[1]] }; New-HttpError 404 '{"code":"NotFound","message":"Service Board not found"}' }
    if ($c.Method -eq 'GET' -and $u -match '/service/boards\?conditions=name="([^"]*)"') {
        if ($TBm.boards403) { New-HttpError 403 '{"code":"Security","message":"denied"}' }
        $want = $Matches[1]; return , @($TBoards.Values | Where-Object { $_.name -eq $want })
    }
    if ($c.Method -eq 'PATCH' -and $u -eq "$CW/service/tickets/12345") {
        $ops = @(($c.Body | ConvertFrom-Json -NoEnumerate))
        $st = @($ops | Where-Object { $_.path -eq 'status' }) | Select-Object -First 1
        if ($null -ne $st -and $null -ne $st.value.PSObject.Properties['name'] -and $TBm.byName -notcontains [string]$st.value.name) { New-HttpError 400 '{"code":"InvalidObject","message":"status is invalid"}' }
        if (-not $TBm.ignorePatch) { $bo = @($ops | Where-Object { $_.path -eq 'board' })[0]; $TBm.board = [string]$bo.value.id }
        return [pscustomobject]@{ id = 12345 }
    }
    return [pscustomobject]@{ id = 1 }
}
function Get-TPatchOps { return @(Get-Calls 'PATCH' '*/service/tickets/12345' | ForEach-Object { , @(Read-Body $_) }) }
function Reset-TBoard { param([hashtable]$Set = @{}) $TBm.board = '1'; $TBm.status = 'In Progress'; $TBm.team = 25; $TBm.ignorePatch = $false; $TBm.statuses403 = $false; $TBm.boards403 = $false; foreach ($k in $Set.Keys) { $TBm[$k] = $Set[$k] }; Reset-Mock $S['connectwise'].Clone() $TBoardHandler }

Reset-TBoard
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'cw'
    Set-PsaQueue -Id '12345' -Queue 'Test Board'
    $p = @(Get-TPatchOps)
    $ops = if ($p.Count) { @($p[0]) } else { @() }
    $bo = @($ops | Where-Object { $_.path -eq 'board' }); $so = @($ops | Where-Object { $_.path -eq 'status' }); $to = @($ops | Where-Object { $_.path -eq 'team' })
    Check 'connectwise board move: ONE json-patch with board (by id), status and team' ($p.Count -eq 1 -and $ops.Count -eq 3 -and $bo.Count -eq 1 -and $bo[0].value.id -eq 14 -and $so.Count -eq 1 -and $to.Count -eq 1) (Show-Calls)
    Check 'connectwise board move: the same-name open status on the new board is kept (In Progress -> id 21)' ($so.Count -eq 1 -and $so[0].op -eq 'replace' -and $so[0].value.id -eq 21) ($ops | ConvertTo-Json -Compress)
    Check 'connectwise board move: a team the new board lacks is cleared (op remove)' ($to.Count -eq 1 -and $to[0].op -eq 'remove' -and $null -eq $to[0].PSObject.Properties['value']) ($ops | ConvertTo-Json -Compress)
    Check 'connectwise board move: the ticket is read back after the move' ((Get-LastCall).Method -eq 'GET' -and (Get-LastCall).Uri -eq "$CW/service/tickets/12345") (Show-Calls)
}
Reset-TBoard @{ status = 'Waiting Vendor' }
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'cw'
    Set-PsaQueue -Id '12345' -Queue '15'
    $ops = @(@(Get-TPatchOps)[0])
    $so = @($ops | Where-Object { $_.path -eq 'status' }); $to = @($ops | Where-Object { $_.path -eq 'team' })
    Check 'connectwise board move: a status the new board only has as closed is not used; its default open status is (Assigned, id 31)' ($so[0].value.id -eq 31) ($ops | ConvertTo-Json -Compress)
    Check 'connectwise board move: the new board''s default team is used when no team matches by name' ($to[0].op -eq 'replace' -and $to[0].value.id -eq 50) ($ops | ConvertTo-Json -Compress)
    Check 'connectwise board move by id: the board is read by id, not searched by name' (@(Get-Calls 'GET' "$CW/service/boards/15").Count -eq 1 -and @(Get-Calls 'GET' '*/service/boards[?]*').Count -eq 0) (Show-Calls)
}
Reset-TBoard @{ status = 'Waiting Vendor' }
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'cw'
    Set-PsaQueue -Id '12345' -Queue 'tier 3'
    $ops = @(@(Get-TPatchOps)[0])
    $so = @($ops | Where-Object { $_.path -eq 'status' }); $to = @($ops | Where-Object { $_.path -eq 'team' })
    Check 'connectwise board move: no same-name and no default open status -> the first open status (Triage, id 71)' ($so[0].value.id -eq 71) ($ops | ConvertTo-Json -Compress)
    Check 'connectwise board move: a team with the same name (any case) on the new board is kept by its new id' ($to[0].op -eq 'replace' -and $to[0].value.id -eq 60) ($ops | ConvertTo-Json -Compress)
}
Reset-TBoard @{ team = 0 }
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'cw'
    Set-PsaQueue -Id '12345' -Queue 'Test Board'
    $ops = @(@(Get-TPatchOps)[0])
    Check 'connectwise board move: a ticket with no team gets no team op when the new board has no default team' ($ops.Count -eq 2 -and -not @($ops | Where-Object { $_.path -eq 'team' }).Count) ($ops | ConvertTo-Json -Compress)
}
Reset-TBoard
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'cw'
    $m = Get-ThrowMessage { Set-PsaQueue -Id '12345' -Queue 'Help Desk' }
    Check 'connectwise board move: a board that does not exist is a plain sentence naming it, and nothing is changed' ($m -eq "ConnectWise has no service board named 'Help Desk'. Use the exact board name or its id." -and @(Get-Calls 'PATCH' '*').Count -eq 0) "$m / $(Show-Calls)"
    $m = Get-ThrowMessage { Set-PsaQueue -Id '12345' -Queue '99' }
    Check 'connectwise board move: a board id that does not exist (404) is a plain sentence, nothing changed' ($m -match 'no service board with id 99' -and @(Get-Calls 'PATCH' '*').Count -eq 0) $m
    $m = Get-ThrowMessage { Set-PsaQueue -Id '12345' -Queue 'Old Board' }
    Check 'connectwise board move: an inactive board is refused, nothing changed' ($m -match "board 'Old Board' is inactive" -and @(Get-Calls 'PATCH' '*').Count -eq 0) $m
    Set-PsaQueue -Id '12345' -Queue 'Service Desk'
    Check 'connectwise board move: a ticket already on the board is left alone (no PATCH)' (@(Get-Calls 'PATCH' '*').Count -eq 0) (Show-Calls)
}
Reset-TBoard @{ statuses403 = $true; status = 'Waiting Vendor' }
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'cw'
    Set-PsaQueue -Id '12345' -Queue 'Test Board'
    $p = @(Get-TPatchOps)
    $names = @($p | ForEach-Object { [string](@($_ | Where-Object { $_.path -eq 'status' })[0].value.name) })
    Check 'connectwise board move, statuses 403: board plus status BY NAME, current name first, then the usual open names, until one is accepted' (($names -join '|') -eq 'Waiting Vendor|New|New (not responded)' -and $TBm.board -eq '14') ($names -join '|')
    Check 'connectwise board move, statuses 403: every try carries the board op in the same patch' (-not @($p | Where-Object { -not @($_ | Where-Object { $_.path -eq 'board' -and $_.value.id -eq 14 }).Count }).Count) (Show-Calls)
    Check 'connectwise board move, statuses 403: a warning names the Table Setup permission' (@($PsaState.Warnings | Where-Object { $_ -match "wouldn't list the statuses of board 14" -and $_ -match 'Table Setup' }).Count -eq 1) (@($PsaState.Warnings) -join ' | ')
}
Reset-TBoard @{ statuses403 = $true; status = 'Waiting Vendor'; byName = @('Escalated') }
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'cw'
    $m = Get-ThrowMessage { Set-PsaQueue -Id '12345' -Queue 'Test Board' }
    Check 'connectwise board move, statuses 403 and no known name fits: a plain sentence naming the board and the permission; ticket unchanged' ($m -match "Couldn't move ConnectWise ticket 12345 to board 'Test Board'" -and $m -match 'Table Setup' -and $TBm.board -eq '1') $m
}
$TBm.byName = @('New (not responded)', 'In Progress')
Reset-TBoard @{ ignorePatch = $true }
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'cw'
    $m = Get-ThrowMessage { Set-PsaQueue -Id '12345' -Queue 'Test Board' }
    Check 'connectwise board move: a read-back still on the old board is a plain error' ($m -eq "ConnectWise accepted the move of ticket 12345 to board 'Test Board', but the ticket is still on 'Service Desk'.") $m
}
Reset-TBoard
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'cw'
    $m = Get-ThrowMessage { Set-PsaQueue -Id '12345' -Queue 'Test Board' }
    Check 'connectwise board move: the move goes through when the board, statuses and teams are readable' ($m -eq '' -and $TBm.board -eq '14') $m
}

# --- Test-PsaQueue: checks a target without changing anything ---
Reset-TBoard
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'cw'
    $r = Test-PsaQueue -Queue 'test board'
    Check 'Test-PsaQueue connectwise: an existing board by name -> ok, with its id and name' ($r.ok -and $r.id -eq '14' -and $r.name -eq 'Test Board' -and $r.reason -eq '') ($r | ConvertTo-Json -Compress)
    $r = Test-PsaQueue -Queue '15'
    Check 'Test-PsaQueue connectwise: an existing board by id -> ok' ($r.ok -and $r.name -eq 'Tier 2') ($r | ConvertTo-Json -Compress)
    $r = Test-PsaQueue -Queue 'Help Desk'
    Check 'Test-PsaQueue connectwise: a missing board -> not ok, the reason names it' (-not $r.ok -and $r.reason -match "no service board named 'Help Desk'") ($r | ConvertTo-Json -Compress)
    $r = Test-PsaQueue -Queue 'Old Board'
    Check 'Test-PsaQueue connectwise: an inactive board -> not ok' (-not $r.ok -and $r.reason -match 'inactive') ($r | ConvertTo-Json -Compress)
    $r = Test-PsaQueue -Queue ' '
    Check 'Test-PsaQueue: blank -> not ok' (-not $r.ok -and $r.reason -eq 'No queue was given.') ($r | ConvertTo-Json -Compress)
    Check 'Test-PsaQueue connectwise: only reads' (@($Mock.Calls | Where-Object { $_.Method -ne 'GET' }).Count -eq 0) (Show-Calls)
}
Reset-TBoard @{ boards403 = $true }
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'cw'
    $r = Test-PsaQueue -Queue 'Test Board'
    Check 'Test-PsaQueue connectwise: boards 403 -> ok (not known to be wrong), reason says it was not checked and names the permission' ($r.ok -and $r.reason -match "wasn't checked" -and $r.reason -match 'Table Setup') ($r | ConvertTo-Json -Compress)
}
Reset-Mock $S['autotask'].Clone() $Handler
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'autotask'
    $a = Test-PsaQueue 'service desk'; $b = Test-PsaQueue 'Tier 9'; $n = Test-PsaQueue '29684'; $x = Test-PsaQueue '1'
    Check 'Test-PsaQueue autotask: queue picklist by label and by value; missing ones are not ok' ($a.ok -and $a.id -eq '29683' -and -not $b.ok -and $b.reason -match "no ticket queue named 'Tier 9'" -and $n.ok -and $n.name -eq 'Projects' -and -not $x.ok) (@($a, $b, $n, $x) | ConvertTo-Json -Compress)
}
Reset-Mock $S['kaseyabms'].Clone() $Handler
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'kaseyabms'
    $a = Test-PsaQueue '7'; $b = Test-PsaQueue 'Tier 2'
    Check 'Test-PsaQueue kaseyabms: a numeric id passes, a name does not' ($a.ok -and -not $b.ok -and $b.reason -match 'numeric queue id') (@($a, $b) | ConvertTo-Json -Compress)
}
Reset-Mock $S['halopsa'].Clone() {
    param($c, $n)
    if ($c.Uri -eq 'https://halo.example.com/auth/token') { return [pscustomobject]@{ access_token = 'halo-token' } }
    if ($c.Method -eq 'GET' -and $c.Uri -eq "$HALO/Team") { return , @([pscustomobject]@{ id = 3; name = 'Service Desk' }, [pscustomobject]@{ id = 4; name = 'Tier 2' }) }
    return [pscustomobject]@{ id = 1 }
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'halopsa'
    $a = Test-PsaQueue 'tier 2'; $b = Test-PsaQueue '9'; $c2 = Test-PsaQueue '3'
    Check 'Test-PsaQueue halopsa: team by name or id; a missing one is not ok' ($a.ok -and $a.id -eq '4' -and -not $b.ok -and $b.reason -match 'no team with id 9' -and $c2.ok -and $c2.name -eq 'Service Desk') (@($a, $b, $c2) | ConvertTo-Json -Compress)
}
Reset-Mock $S['syncro'].Clone() $Handler
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'syncro'
    $a = Test-PsaQueue 'Network'
    Check 'Test-PsaQueue syncro: issue types are not checked (ok, with a reason), no call' ($a.ok -and $a.reason -match "aren't checked" -and @($Mock.Calls).Count -eq 0) ($a | ConvertTo-Json -Compress)
}
Reset-Mock $S['zendesk'].Clone() {
    param($c, $n)
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/groups?*') { return [pscustomobject]@{ groups = @([pscustomobject]@{ id = 21; name = 'Service Desk' }, [pscustomobject]@{ id = 22; name = 'Tier 2' }) } }
    return [pscustomobject]@{ id = 1 }
}
Invoke-WithLib @('psa.ps1') {
    $null = Connect-Psa 'zendesk'
    $a = Test-PsaQueue 'Tier 2'; $b = Test-PsaQueue 'Tier 3'; $c2 = Test-PsaQueue '21'
    Check 'Test-PsaQueue zendesk: group by name or id; a missing one is not ok' ($a.ok -and $a.id -eq '22' -and -not $b.ok -and $b.reason -match "no group named 'Tier 3'" -and $c2.ok -and $c2.name -eq 'Service Desk' -and @($Mock.Calls | Where-Object { $_.Method -ne 'GET' }).Count -eq 0) (@($a, $b, $c2) | ConvertTo-Json -Compress)
}

Complete-Test
