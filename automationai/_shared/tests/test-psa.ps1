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
    $null = Set-PsaStatus '12345' -State open
    Check 'connectwise: reopen picks the default status' ((Read-Body (Get-LastCall))[0].value.id -eq 10) ((Get-LastCall).Body)
    Set-PsaAssignee '12345' 'jlee'
    Check 'connectwise: assign by identifier' ((Read-Body (Get-LastCall))[0].value.identifier -eq 'jlee') ((Get-LastCall).Body)
    $t = Get-PsaTicket '12345'
    Check 'connectwise: Get-PsaTicket reads the first note as the description' ($t.description -like '*Contoso*' -and $t.assigneeId -eq 'jlee' -and $t.companyId -eq '42') ($t | ConvertTo-Json -Compress -Depth 2)
    $m = Get-ThrowMessage { New-PsaTicket -CompanyId 42 -Summary 'x' -Priority 'whenever' }
    Check 'priority hint must be known' ($m -match 'critical, high, medium, low') $m
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

Complete-Test
