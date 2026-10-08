# Strict-mode tests for psa-extra.ps1 across all six PSAs: Find-PsaTickets, Resolve-PsaTicketNames,
# Get-PsaTicketSla, Set-PsaQueue and Get-PsaTicketNotes. The same file ships in sla-breach-report/src and
# auto-escalation/src, next to identical copies of psa-extra.ps1.
# Runs _shared/psa.ps1 + psa-extra.ps1 + each test body as one script through & ([scriptblock]::Create(...))
# under Set-StrictMode -Version Latest, with the Key Vault and Invoke-RestMethod mocked. Placeholder data only.
# Usage: pwsh -NoProfile -File src/test-psa-extra.ps1
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')
$TLib = (Get-Content -Raw (Join-Path $Shared 'psa.ps1')) + "`n" + (Get-Content -Raw (Join-Path $PSScriptRoot 'psa-extra.ps1'))
function Invoke-Extra { param([scriptblock]$Body) & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $TLib + "`n" + $Body.ToString())) }

$TSecrets = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://cw.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    halopsa     = @{ 'PSA-Type' = 'halopsa'; 'Halo-ApiUrl' = 'https://halo.example.com'; 'Halo-ClientId' = 'id'; 'Halo-ClientSecret' = 'sec' }
    kaseyabms   = @{ 'PSA-Type' = 'kaseyabms'; 'KaseyaBMS-ApiUrl' = 'https://bms.example.com'; 'KaseyaBMS-Username' = 'api'; 'KaseyaBMS-Password' = 'pw'; 'KaseyaBMS-CompanyName' = 'examplemsp' }
    syncro      = @{ 'PSA-Type' = 'syncro'; 'Syncro-ApiUrl' = 'https://example.syncromsp.com/api/v1'; 'Syncro-ApiKey' = 'key' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
}
$TNowIso = { param([double]$Hours) [datetime]::UtcNow.AddHours($Hours).ToString('yyyy-MM-ddTHH:mm:ssZ') }
$TAtFields = [pscustomobject]@{ fields = @(
        [pscustomobject]@{ name = 'status'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'New'; isActive = $true }, [pscustomobject]@{ value = '5'; label = 'Complete'; isActive = $true }, [pscustomobject]@{ value = '7'; label = 'Waiting Customer'; isActive = $true }) }
        [pscustomobject]@{ name = 'priority'; picklistValues = @([pscustomobject]@{ value = '4'; label = 'Critical'; isActive = $true }, [pscustomobject]@{ value = '1'; label = 'High'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Medium'; isActive = $true }, [pscustomobject]@{ value = '3'; label = 'Low'; isActive = $true }) }
        [pscustomobject]@{ name = 'queueID'; picklistValues = @([pscustomobject]@{ value = '29683'; label = 'Service Desk'; isActive = $true }, [pscustomobject]@{ value = '29684'; label = 'Tier 2'; isActive = $true }) }
    )
}
$TAtNoteFields = [pscustomobject]@{ fields = @([pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) }) }

# ---- Find-PsaTickets ----
Reset-Mock -Secrets $TSecrets.connectwise -Handler { param($c, $n)
    if ($c.Uri -like '*/service/tickets[?]*') { return @([pscustomobject]@{ id = 11; summary = 'Printer offline'; company = [pscustomobject]@{ id = 5; name = 'Contoso Ltd' }; status = [pscustomobject]@{ name = 'New' }; priority = [pscustomobject]@{ id = 2; name = 'Priority 2 - Quick Response' }; board = [pscustomobject]@{ id = 1; name = 'Service Desk' }; owner = [pscustomobject]@{ id = 7; identifier = 'jlee'; name = 'Jordan Lee' }; _info = [pscustomobject]@{ dateEntered = (& $TNowIso -5); lastUpdated = (& $TNowIso -3) } }) }
    return @()
}
$TR = Invoke-Extra { $null = Connect-Psa; @{ rows = @(Find-PsaTickets -UpdatedBefore ([datetime]::UtcNow.AddHours(-1)) -Max 50) } }
$TUri = [uri]::UnescapeDataString((Get-Calls GET '*/service/tickets[?]*')[0].Uri)
Check 'CW find: open-only and updated-before conditions, oldest id first' ($TUri -match 'closedFlag=false and lastUpdated < \[\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\]' -and $TUri -match 'orderBy=id asc' -and $TUri -match 'pageSize=100&page=1') $TUri
Check 'CW find: normalized row' ($TR.rows.Count -eq 1 -and $TR.rows[0].priority -eq 'high' -and $TR.rows[0].companyName -eq 'Contoso Ltd' -and $TR.rows[0].assigneeId -eq 'jlee' -and $TR.rows[0].queueName -eq 'Service Desk' -and $TR.rows[0].updated -is [datetime]) ($TR.rows | ConvertTo-Json -Depth 3)

Reset-Mock -Secrets $TSecrets.connectwise -Handler { param($c, $n) New-HttpError 403 '{"message":"denied"}' }
$TMsg = Get-ThrowMessage { Invoke-Extra { $null = Connect-Psa; Find-PsaTickets } }
Check 'CW find: 403 becomes a plain permission sentence' ($TMsg -match 'ConnectWise refused to list tickets \(HTTP 403\)\. Give the API user permission') $TMsg

Reset-Mock -Secrets $TSecrets.autotask -Handler { param($c, $n)
    if ($c.Uri -like '*/Tickets/entityInformation/fields') { return $TAtFields }
    if ($c.Uri -like '*/Tickets/query?*') { return [pscustomobject]@{ items = @([pscustomobject]@{ id = 501; ticketNumber = 'T20261008.0001'; title = 'VPN down'; companyID = 42; status = 1; priority = 4; queueID = 29683; assignedResourceID = 29682885; createDate = (& $TNowIso -6); lastActivityDate = (& $TNowIso -4) }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
    if ($c.Uri -like '*/Companies/42') { return [pscustomobject]@{ item = [pscustomobject]@{ companyName = 'Contoso Ltd' } } }
    if ($c.Uri -like '*/Resources/29682885') { return [pscustomobject]@{ item = [pscustomobject]@{ firstName = 'Jordan'; lastName = 'Lee' } } }
    return $null
}
$TR = Invoke-Extra { $null = Connect-Psa; $r = @(Find-PsaTickets -UpdatedBefore ([datetime]::UtcNow.AddHours(-1))); Resolve-PsaTicketNames $r; @{ rows = $r } }
$TSearch = [uri]::UnescapeDataString((Get-Calls GET '*/Tickets/query?*')[0].Uri) -replace '^.*search=', '' | ConvertFrom-Json
Check 'AT find: excludes Complete statuses and filters lastActivityDate' (@($TSearch.filter | Where-Object { $_.op -eq 'noteq' -and $_.field -eq 'status' -and $_.value -eq 5 }).Count -eq 1 -and @($TSearch.filter | Where-Object { $_.op -eq 'lt' -and $_.field -eq 'lastActivityDate' }).Count -eq 1) ($TSearch | ConvertTo-Json -Depth 5 -Compress)
Check 'AT find: labels from picklists, names resolved' ($TR.rows[0].priority -eq 'critical' -and $TR.rows[0].status -eq 'New' -and $TR.rows[0].queueName -eq 'Service Desk' -and $TR.rows[0].number -eq 'T20261008.0001' -and $TR.rows[0].companyName -eq 'Contoso Ltd' -and $TR.rows[0].assigneeName -eq 'Jordan Lee') ($TR.rows[0] | ConvertTo-Json -Depth 2)

Reset-Mock -Secrets $TSecrets.halopsa -Handler { param($c, $n)
    if ($c.Uri -like '*/auth/token') { return [pscustomobject]@{ access_token = 'tok' } }
    if ($c.Uri -like '*/api/Tickets?*') { return [pscustomobject]@{ record_count = 1; tickets = @([pscustomobject]@{ id = 101; summary = 'Email bouncing'; client_id = 12; client_name = 'Contoso Ltd'; status_id = 2; priority_id = 1; team = 'Service Desk'; agent_id = 3; agent_name = 'Jordan Lee'; dateoccurred = (& $TNowIso -5); lastactiondate = '1900-01-01T00:00:00'; last_update = (& $TNowIso -2); respondbydate = '1900-01-01T00:00:00'; fixbydate = (& $TNowIso 2); responsedate = '1900-01-01T00:00:00' }) } }
    return $null
}
$TR = Invoke-Extra { $null = Connect-Psa; $r = @(Find-PsaTickets); @{ rows = $r; sla = (Get-PsaTicketSla $r[0]) } }
Check 'Halo find: open_only paging, P1 is critical, 1900 lastactiondate falls back to last_update' ((Get-Calls GET '*/api/Tickets?*')[0].Uri -match 'open_only=true&pageinate=true&page_size=100&page_no=1' -and $TR.rows[0].priority -eq 'critical' -and $TR.rows[0].updated -gt [datetime]::UtcNow.AddHours(-3)) (Show-Calls)
Check 'Halo SLA: 1900 respond-by ignored, fix-by used' ($TR.sla.source -eq 'psa' -and $TR.sla.kind -eq 'resolve' -and $TR.sla.target -gt [datetime]::UtcNow) ($TR.sla | ConvertTo-Json -Depth 2)

Reset-Mock -Secrets $TSecrets.kaseyabms -Handler { param($c, $n)
    if ($c.Uri -like '*/v2/security/authenticate') { return [pscustomobject]@{ Success = $true; Result = [pscustomobject]@{ AccessToken = 'tok' } } }
    if ($c.Uri -like '*/v2/servicedesk/tickets?*') { return [pscustomobject]@{ Success = $true; Result = @([pscustomobject]@{ Id = 900; TicketNumber = 'BMS-900'; Title = 'Laptop slow'; AccountId = 4; AccountName = 'Contoso Ltd'; StatusName = 'New'; PriorityName = 'High'; QueueId = 3; QueueName = 'Service Desk'; AssigneeId = 8; AssigneeName = 'Jordan Lee'; OpenDate = (& $TNowIso -9); DueDate = (& $TNowIso -1) }, [pscustomobject]@{ Id = 901; Title = 'Done'; StatusName = 'Completed'; OpenDate = (& $TNowIso -30) }) } }
    return $null
}
$TR = Invoke-Extra { $null = Connect-Psa; $r = @(Find-PsaTickets); @{ rows = $r; sla = (Get-PsaTicketSla $r[0]) } }
Check 'BMS find: completed tickets dropped client-side; DueDate is the SLA target' ($TR.rows.Count -eq 1 -and $TR.rows[0].number -eq 'BMS-900' -and $TR.sla.kind -eq 'due' -and $TR.sla.target -lt [datetime]::UtcNow) (Show-Calls)

Reset-Mock -Secrets $TSecrets.syncro -Handler { param($c, $n)
    if ($c.Uri -like '*/tickets[?]*') { return [pscustomobject]@{ tickets = @([pscustomobject]@{ id = 77; number = 1077; subject = 'Old'; customer_id = 9; customer_business_then_name = 'Contoso Ltd'; status = 'New'; priority = '1 High'; user_id = 5; created_at = (& $TNowIso -10); updated_at = (& $TNowIso -5); due_date = (& $TNowIso -1) }, [pscustomobject]@{ id = 78; number = 1078; subject = 'Fresh'; customer_id = 9; status = 'In Progress'; priority = '2 Normal'; created_at = (& $TNowIso -1); updated_at = (& $TNowIso -0.1) }); meta = [pscustomobject]@{ total_pages = 1 } } }
    return $null
}
$TR = Invoke-Extra { $null = Connect-Psa; @{ rows = @(Find-PsaTickets -UpdatedBefore ([datetime]::UtcNow.AddHours(-1))) } }
Check 'Syncro find: Not Closed status, updated-before applied client-side' ((Get-Calls GET '*/tickets[?]*')[0].Uri -match 'status=Not%20Closed&page=1' -and $TR.rows.Count -eq 1 -and $TR.rows[0].id -eq '77' -and $TR.rows[0].priority -eq 'high') (Show-Calls)

Reset-Mock -Secrets $TSecrets.zendesk -Handler { param($c, $n)
    if ($c.Uri -like '*/search?*') { return [pscustomobject]@{ results = @([pscustomobject]@{ id = 3001; subject = 'Cannot log in'; organization_id = 61; status = 'open'; priority = 'urgent'; group_id = 21; assignee_id = 71; created_at = (& $TNowIso -3); updated_at = (& $TNowIso -2); slas = [pscustomobject]@{ policy_metrics = @([pscustomobject]@{ metric = 'first_reply_time'; stage = 'active'; breach_at = (& $TNowIso -1) }, [pscustomobject]@{ metric = 'requester_wait_time'; stage = 'active'; breach_at = (& $TNowIso 5) }) } }); next_page = $null } }
    if ($c.Uri -like '*/organizations/61') { return [pscustomobject]@{ organization = [pscustomobject]@{ name = 'Contoso Ltd' } } }
    if ($c.Uri -like '*/users/71') { return [pscustomobject]@{ user = [pscustomobject]@{ name = 'Jordan Lee' } } }
    if ($c.Uri -like '*/groups/21') { return [pscustomobject]@{ group = [pscustomobject]@{ name = 'Service Desk' } } }
    return $null
}
$TR = Invoke-Extra { $null = Connect-Psa; $r = @(Find-PsaTickets -UpdatedBefore ([datetime]::UtcNow.AddHours(-1))); Resolve-PsaTicketNames $r; @{ rows = $r; sla = (Get-PsaTicketSla $r[0]) } }
$TUri = [uri]::UnescapeDataString((Get-Calls GET '*/search?*')[0].Uri)
Check 'Zendesk find: unsolved, updated< and SLA sideload in the search' ($TUri -match 'type:ticket status<solved updated<\d{4}-' -and $TUri -match 'include=tickets\(slas\)') $TUri
Check 'Zendesk find: names resolved; SLA uses the earliest active breach_at' ($TR.rows[0].companyName -eq 'Contoso Ltd' -and $TR.rows[0].assigneeName -eq 'Jordan Lee' -and $TR.rows[0].queueName -eq 'Service Desk' -and $TR.rows[0].priority -eq 'critical' -and $TR.sla.kind -eq 'respond' -and $TR.sla.target -lt [datetime]::UtcNow) ($TR.sla | ConvertTo-Json -Depth 2)

# ---- Get-PsaTicketSla (ConnectWise and Autotask) ----
Reset-Mock -Secrets $TSecrets.connectwise -Handler { param($c, $n)
    if ($c.Uri -like '*/service/SLAs/5/priorities*') { return @([pscustomobject]@{ priority = [pscustomobject]@{ id = 2 }; respondHours = 2; resolutionHours = 8 }) }
    if ($c.Uri -like '*/service/SLAs/5') { return [pscustomobject]@{ id = 5; respondHours = 4; resolutionHours = 24 } }
    return $null
}
$TR = Invoke-Extra {
    $null = Connect-Psa
    $a = New-PsaTicketRow 1 $null 'A' 5 'Contoso Ltd' 'New' 'Priority 2' 1 'Service Desk' 'jlee' '' ([datetime]::UtcNow.AddHours(-3)) $null ([pscustomobject]@{ sla = [pscustomobject]@{ id = 5 }; priority = [pscustomobject]@{ id = 2 }; dateResponded = $null })
    $b = New-PsaTicketRow 2 $null 'B' 5 'Contoso Ltd' 'New' 'Priority 3' 1 'Service Desk' 'jlee' '' ([datetime]::UtcNow.AddHours(-3)) $null ([pscustomobject]@{ sla = [pscustomobject]@{ id = 5 }; priority = [pscustomobject]@{ id = 3 }; dateResponded = ([datetime]::UtcNow.AddHours(-2)).ToString('o') })
    $x = New-PsaTicketRow 3 $null 'C' 5 'Contoso Ltd' 'New' 'Priority 3' 1 'Service Desk' 'jlee' '' ([datetime]::UtcNow.AddHours(-3)) $null ([pscustomobject]@{ isInSla = $false })
    @{ a = (Get-PsaTicketSla $a); b = (Get-PsaTicketSla $b); x = (Get-PsaTicketSla $x) }
}
Check 'CW SLA: priority override, respond target before a response' ($TR.a.kind -eq 'respond' -and [Math]::Abs(($TR.a.target - [datetime]::UtcNow.AddHours(-1)).TotalMinutes) -lt 2) ($TR.a | ConvertTo-Json -Depth 2)
Check 'CW SLA: resolve target after a response, base SLA for an unlisted priority' ($TR.b.kind -eq 'resolve' -and [Math]::Abs(($TR.b.target - [datetime]::UtcNow.AddHours(21)).TotalMinutes) -lt 2) ($TR.b | ConvertTo-Json -Depth 2)
Check 'CW SLA: isInSla=false with no SLA id is a breach' ($TR.x.breached -eq $true -and $null -eq $TR.x.target) ($TR.x | ConvertTo-Json -Depth 2)
Check 'CW SLA: definitions read once (cached)' ((Get-Calls GET '*/service/SLAs/5').Count -eq 1) (Show-Calls)

Reset-Mock -Secrets $TSecrets.autotask -Handler { param($c, $n) return $null }
$TR = Invoke-Extra {
    $null = Connect-Psa
    $a = New-PsaTicketRow 1 $null 'A' 42 '' 'New' 'High' 1 '' '' '' ([datetime]::UtcNow.AddHours(-3)) $null ([pscustomobject]@{ firstResponseDueDateTime = ([datetime]::UtcNow.AddHours(-1)).ToString('o'); firstResponseDateTime = $null; resolvedDueDateTime = ([datetime]::UtcNow.AddHours(5)).ToString('o'); serviceLevelAgreementHasBeenMet = $false })
    $b = New-PsaTicketRow 2 $null 'B' 42 '' 'New' 'High' 1 '' '' '' ([datetime]::UtcNow.AddHours(-3)) $null ([pscustomobject]@{ dueDateTime = ([datetime]::UtcNow.AddHours(5)).ToString('o') })
    @{ a = (Get-PsaTicketSla $a); b = (Get-PsaTicketSla $b) }
}
Check 'AT SLA: first response due used before a response; SLA-not-met flag kept' ($TR.a.kind -eq 'respond' -and $TR.a.breached -eq $true) ($TR.a | ConvertTo-Json -Depth 2)
Check 'AT SLA: falls back to dueDateTime' ($TR.b.kind -eq 'due' -and $TR.b.target -gt [datetime]::UtcNow) ($TR.b | ConvertTo-Json -Depth 2)

# ---- Set-PsaQueue ----
Reset-Mock -Secrets $TSecrets.connectwise
Invoke-Extra { $null = Connect-Psa; Set-PsaQueue 11 'Tier 2' }
$TB = Read-Body (Get-LastCall)
Check 'CW queue: json-patch replaces board by name' ((Get-LastCall).Method -eq 'PATCH' -and (Get-LastCall).Uri -like '*/service/tickets/11' -and $TB[0].op -eq 'replace' -and $TB[0].path -eq 'board' -and $TB[0].value.name -eq 'Tier 2') (Get-LastCall).Body

Reset-Mock -Secrets $TSecrets.autotask -Handler { param($c, $n) if ($c.Uri -like '*/Tickets/entityInformation/fields') { return $TAtFields }; return $null }
Invoke-Extra { $null = Connect-Psa; Set-PsaQueue 501 'tier 2' }
$TB = Read-Body (Get-LastCall)
Check 'AT queue: name matched to the queueID picklist' ((Get-LastCall).Method -eq 'PATCH' -and $TB.id -eq 501 -and $TB.queueID -eq 29684) (Get-LastCall).Body
$TMsg = Get-ThrowMessage { Invoke-Extra { $null = Connect-Psa; Set-PsaQueue 501 'Nowhere' } }
Check 'AT queue: unknown queue name throws plainly' ($TMsg -eq "Autotask has no ticket queue named 'Nowhere'.") $TMsg

Reset-Mock -Secrets $TSecrets.halopsa -Handler { param($c, $n) if ($c.Uri -like '*/auth/token') { return [pscustomobject]@{ access_token = 'tok' } }; return $null }
Invoke-Extra { $null = Connect-Psa; Set-PsaQueue 101 'Tier 2'; Set-PsaQueue 101 '4' }
$TC = @(Get-Calls POST '*/api/Tickets')
Check 'Halo queue: team name or team_id' ($TC.Count -eq 2 -and (Read-Body $TC[0])[0].team -eq 'Tier 2' -and (Read-Body $TC[1])[0].team_id -eq 4) (Show-Calls)

Reset-Mock -Secrets $TSecrets.kaseyabms -Handler { param($c, $n) if ($c.Uri -like '*/v2/security/authenticate') { return [pscustomobject]@{ Result = [pscustomobject]@{ AccessToken = 'tok' } } }; return $null }
Invoke-Extra { $null = Connect-Psa; Set-PsaQueue 900 '7' }
$TB = Read-Body (Get-LastCall)
Check 'BMS queue: json-patch /QueueId' ((Get-LastCall).Method -eq 'PATCH' -and $TB[0].path -eq '/QueueId' -and $TB[0].value -eq 7) (Get-LastCall).Body
$TMsg = Get-ThrowMessage { Invoke-Extra { $null = Connect-Psa; Set-PsaQueue 900 'Tier 2' } }
Check 'BMS queue: a name is refused' ($TMsg -match 'numeric queue id') $TMsg

Reset-Mock -Secrets $TSecrets.syncro
Invoke-Extra { $null = Connect-Psa; Set-PsaQueue 77 'Network' }
Check 'Syncro queue: issue type (problem_type)' ((Get-LastCall).Method -eq 'PUT' -and (Read-Body (Get-LastCall)).problem_type -eq 'Network') (Get-LastCall).Body

Reset-Mock -Secrets $TSecrets.zendesk -Handler { param($c, $n) if ($c.Uri -like '*/groups?*') { return [pscustomobject]@{ groups = @([pscustomobject]@{ id = 21; name = 'Service Desk' }, [pscustomobject]@{ id = 22; name = 'Tier 2' }) } }; return $null }
Invoke-Extra { $null = Connect-Psa; Set-PsaQueue 3001 'Tier 2' }
Check 'Zendesk queue: group name looked up, group_id set' ((Get-LastCall).Method -eq 'PUT' -and (Read-Body (Get-LastCall)).ticket.group_id -eq 22) (Get-LastCall).Body

# ---- Get-PsaDefaultRole ----
Reset-Mock -Secrets $TSecrets.autotask -Handler { param($c, $n) if ($c.Uri -like '*/Resources/29682885') { return [pscustomobject]@{ item = [pscustomobject]@{ id = 29682885; defaultServiceDeskRoleID = 29683461 } } }; return $null }
$TR = Invoke-Extra { $null = Connect-Psa; @{ role = (Get-PsaDefaultRole 29682885) } }
Check 'AT default role: read from the resource' ($TR.role -eq '29683461') $TR.role
Reset-Mock -Secrets $TSecrets.zendesk
$TR = Invoke-Extra { $null = Connect-Psa; @{ role = (Get-PsaDefaultRole 71) } }
Check 'Zendesk default role: none needed, no call' ($TR.role -eq '' -and $Mock.Calls.Count -eq 0) (Show-Calls)

# ---- Get-PsaTicketNotes ----
$TNoteCases = @(
    @{ psa = 'connectwise'; like = '*/service/tickets/11/notes?*'; reply = @([pscustomobject]@{ text = '[Auto-Escalation] moved'; internalAnalysisFlag = $true; dateCreated = (& $TNowIso -1) }, [pscustomobject]@{ text = 'Customer says hi'; internalAnalysisFlag = $false; dateCreated = (& $TNowIso -2) }); id = 11 }
    @{ psa = 'autotask'; like = '*/TicketNotes/query?*'; reply = [pscustomobject]@{ items = @([pscustomobject]@{ description = '[Auto-Escalation] moved'; publish = 2; createDateTime = (& $TNowIso -1) }, [pscustomobject]@{ description = 'Customer says hi'; publish = 1; createDateTime = (& $TNowIso -2) }) }; id = 501 }
    @{ psa = 'halopsa'; like = '*/api/Actions?*'; reply = [pscustomobject]@{ actions = @([pscustomobject]@{ note = '[Auto-Escalation] moved'; hiddenfromuser = $true; datetime = (& $TNowIso -1) }, [pscustomobject]@{ note = 'Customer says hi'; hiddenfromuser = $false; datetime = (& $TNowIso -2) }) }; id = 101 }
    @{ psa = 'kaseyabms'; like = '*/servicedesk/tickets/900/notes'; reply = [pscustomobject]@{ Result = @([pscustomobject]@{ Details = '[Auto-Escalation] moved'; IsInternal = $true; NoteDate = (& $TNowIso -1) }, [pscustomobject]@{ Details = 'Customer says hi'; IsInternal = $false; NoteDate = (& $TNowIso -2) }) }; id = 900 }
    @{ psa = 'syncro'; like = '*/tickets/77'; reply = [pscustomobject]@{ ticket = [pscustomobject]@{ comments = @([pscustomobject]@{ body = '[Auto-Escalation] moved'; hidden = $true; created_at = (& $TNowIso -1) }, [pscustomobject]@{ body = 'Customer says hi'; hidden = $false; created_at = (& $TNowIso -2) }) } }; id = 77 }
    @{ psa = 'zendesk'; like = '*/tickets/3001/comments'; reply = [pscustomobject]@{ comments = @([pscustomobject]@{ body = '[Auto-Escalation] moved'; public = $false; created_at = (& $TNowIso -1) }, [pscustomobject]@{ body = 'Customer says hi'; public = $true; created_at = (& $TNowIso -2) }) }; id = 3001 }
)
foreach ($TCase in $TNoteCases) {
    $global:TCaseNow = $TCase
    Reset-Mock -Secrets $TSecrets[$TCase.psa] -Handler { param($c, $n)
        if ($c.Uri -like '*/auth/token') { return [pscustomobject]@{ access_token = 'tok' } }
        if ($c.Uri -like '*/v2/security/authenticate') { return [pscustomobject]@{ Result = [pscustomobject]@{ AccessToken = 'tok' } } }
        if ($c.Uri -like '*/TicketNotes/entityInformation/fields') { return $TAtNoteFields }
        if ($c.Uri -like $global:TCaseNow.like) { return $global:TCaseNow.reply }
        return $null
    }
    $global:TNoteId = [string]$TCase.id
    $TR = Invoke-Extra { $null = Connect-Psa; @{ notes = @(Get-PsaTicketNotes $global:TNoteId) } }
    Check "$($TCase.psa) notes: text, internal flag and date" ($TR.notes.Count -eq 2 -and $TR.notes[0].text -eq '[Auto-Escalation] moved' -and $TR.notes[0].internal -eq $true -and $TR.notes[1].internal -eq $false -and $TR.notes[0].created -is [datetime]) (Show-Calls)
}

Complete-Test
