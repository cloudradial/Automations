# Mock runner and mock PSAs for test.ps1 (the same file ships in waiting-on-client-nudge/src and auto-close-resolved/src).
# Mocks Get-AzKeyVaultSecret, Invoke-RestMethod, Start-Sleep, Get-NodeInput and Set-NodeOutput.
# A small in-memory "world" of tickets and notes answers the list, notes, status and write calls of all six PSAs
# in each PSA's own JSON shape, and applies writes (notes, status changes) so a second run sees them.
# Placeholder data only (Contoso, Example MSP).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:RUNNER_KV_NAME = 'kv-test'

$MockTally = @{ pass = 0; fail = 0 }
function Check {
    param([string]$Name, [bool]$Ok, $Detail = '')
    if ($Ok) { $MockTally.pass++; Write-Host "PASS $Name" } else { $MockTally.fail++; Write-Host "FAIL $Name :: $Detail" -ForegroundColor Red }
}

$MockSecrets = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://cw.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    halopsa     = @{ 'PSA-Type' = 'halopsa'; 'Halo-ApiUrl' = 'https://halo.example.com'; 'Halo-ClientId' = 'cid'; 'Halo-ClientSecret' = 'sec' }
    kaseyabms   = @{ 'PSA-Type' = 'kaseyabms'; 'KaseyaBMS-ApiUrl' = 'https://bms.example.com'; 'KaseyaBMS-Username' = 'u'; 'KaseyaBMS-Password' = 'p'; 'KaseyaBMS-CompanyName' = 'Example MSP'; 'KaseyaBMS-NoteTypeId' = '4'; 'KaseyaBMS-ClosedStatusId' = '3' }
    syncro      = @{ 'PSA-Type' = 'syncro'; 'Syncro-ApiUrl' = 'https://example.syncromsp.com/api/v1'; 'Syncro-ApiKey' = 'key' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
}
$MockBase = @{
    connectwise = 'https://cw.example.com/v4_6_release/apis/3.0'; autotask = 'https://webservices.autotask.example/atservicesrest/v1.0'; halopsa = 'https://halo.example.com/api'
    kaseyabms = 'https://bms.example.com/v2'; syncro = 'https://example.syncromsp.com/api/v1'; zendesk = 'https://example.zendesk.com/api/v2'
}
# Status ids for the PSAs that key statuses by id. Every PSA's world uses the same names.
$MockStatusIds = [ordered]@{ 'New' = 1; 'In Progress' = 2; 'Closed' = 3; 'Waiting Customer' = 7; 'Waiting on User' = 4; 'Waiting on Customer' = 5; 'Resolved' = 9; 'Complete' = 5 }
$MockAtStatus = [ordered]@{ '1' = 'New'; '5' = 'Complete'; '7' = 'Waiting Customer'; '8' = 'In Progress'; '9' = 'Resolved' }
$MockHaloStatus = [ordered]@{ '1' = 'New'; '2' = 'In Progress'; '4' = 'Waiting on User'; '9' = 'Closed'; '10' = 'Resolved' }
$MockBmsStatus = [ordered]@{ '1' = 'New'; '2' = 'In Progress'; '3' = 'Closed'; '5' = 'Waiting on Customer'; '6' = 'Resolved' }
$MockCwStatus = [ordered]@{ '10' = 'New'; '11' = 'In Progress'; '12' = 'Waiting Customer'; '13' = 'Closed'; '14' = 'Resolved' }

$MockWorld = @{ psa = ''; tickets = (New-Object System.Collections.ArrayList); writes = (New-Object System.Collections.ArrayList); calls = (New-Object System.Collections.ArrayList); fail = ''; next = 5000; now = (Get-Date).ToUniversalTime() }
$MockHarness = @{ Input = $null; Output = $null }

function Get-AzKeyVaultSecret { [CmdletBinding()] param($VaultName, $Name, [switch]$AsPlainText) $s = $MockSecrets[$MockWorld.psa]; if ($s.Contains($Name)) { return $s[$Name] }; return $null }
function Start-Sleep { [CmdletBinding()] param([double]$Seconds = 0, [int]$Milliseconds = 0) }
function Get-NodeInput { return $MockHarness.Input }
function Set-NodeOutput { param($Output) $MockHarness.Output = $Output }

function New-HttpError {
    param([int]$Code, [string]$Body = '')
    $r = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Code)
    $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new("Response status code does not indicate success: $Code.", $r)
    $er = [System.Management.Automation.ErrorRecord]::new($ex, 'WebCmdletWebResponseException', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
    if ($Body) { $er.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Body) }
    throw $er
}

# ---- building a world ----
function Get-Ago { param([double]$Days) return $MockWorld.now.AddDays(-$Days).AddHours(-1) }
function Get-Iso { param($d) if ($null -eq $d) { return $null }; return $d.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) }
function Get-Stamp { param($d) return $d.ToString('yyyy-MM-ddTHH:mmZ', [Globalization.CultureInfo]::InvariantCulture) }
function Reset-World {
    param([string]$Psa)
    $MockWorld.psa = $Psa; $MockWorld.tickets.Clear(); $MockWorld.writes.Clear(); $MockWorld.calls.Clear(); $MockWorld.fail = ''; $MockWorld.now = (Get-Date).ToUniversalTime()
}
# Notes: @{ d = days ago; who = 'tech' | 'client' | 'marker'; text; internal }
function Add-WorldTicket {
    param([int]$Id, [string]$Status, [string]$Prio = 'medium', [double]$Created = 10, [double]$Updated = -1, [array]$Notes = @(), [int]$CompanyId = 42, [string]$CompanyName = 'Contoso')
    $t = @{ id = $Id; status = $Status; prio = $Prio; created = (Get-Ago $Created); updated = $null; companyId = $CompanyId; companyName = $CompanyName; summary = "Contoso request $Id"; notes = (New-Object System.Collections.ArrayList) }
    $last = $t.created
    foreach ($n in $Notes) {
        $at = Get-Ago $n.d
        $null = $t.notes.Add(@{ id = ($MockWorld.next++); text = $n.text; created = $at; client = ($n.who -eq 'client'); internal = [bool]$(if ($n.Contains('internal')) { $n.internal } else { $false }) })
        if ($at -gt $last) { $last = $at }
    }
    $t.updated = $(if ($Updated -ge 0) { Get-Ago $Updated } else { $last })
    $t.statusChanged = $t.updated
    $null = $MockWorld.tickets.Add($t)
    return $t
}
function Get-WorldTicket { param($Id) return @($MockWorld.tickets | Where-Object { [string]$_.id -eq [string]$Id }) | Select-Object -First 1 }
function Add-WorldNote {
    param($Id, [string]$Text, [bool]$Internal)
    $t = Get-WorldTicket $Id
    if ($null -eq $t) { New-HttpError 404 'no such ticket' }
    $null = $t.notes.Add(@{ id = ($MockWorld.next++); text = $Text; created = (Get-Date).ToUniversalTime(); client = $false; internal = $Internal })
    $t.updated = (Get-Date).ToUniversalTime()
}
function Set-WorldStatus { param($Id, [string]$Name) $t = Get-WorldTicket $Id; $t.status = $Name; $t.updated = (Get-Date).ToUniversalTime(); $t.statusChanged = $t.updated }
function Get-PrioLabel {
    param($t)
    $isHigh = $t.prio -eq 'critical'
    switch ($MockWorld.psa) {
        'connectwise' { if ($isHigh) { return 'Priority 1 - Emergency Response' }; return 'Priority 3 - Normal Response' }
        'autotask' { if ($isHigh) { return 4 }; return 2 }
        'halopsa' { if ($isHigh) { return 1 }; return 3 }
        'kaseyabms' { if ($isHigh) { return 'Critical' }; return 'Medium' }
        'syncro' { if ($isHigh) { return '0 Urgent' }; return '2 Normal' }
        'zendesk' { if ($isHigh) { return 'urgent' }; return 'normal' }
    }
}
function Get-Query { param([string]$Uri) $q = @{}; $i = $Uri.IndexOf('?'); if ($i -lt 0) { return $q }; foreach ($pair in $Uri.Substring($i + 1).Split('&')) { $kv = $pair.Split('=', 2); $q[[uri]::UnescapeDataString($kv[0])] = $(if ($kv.Count -gt 1) { [uri]::UnescapeDataString($kv[1]) } else { '' }) }; return $q }
function Get-IdFrom { param([string]$Uri, [string]$Pattern) $m = [regex]::Match($Uri, $Pattern); return $m.Groups[1].Value }

# ---- the mock API ----
function Invoke-RestMethod {
    [CmdletBinding()] param($Method = 'GET', $Uri, $Headers, $Body, $ContentType, $Form)
    $m = ([string]$Method).ToUpperInvariant(); $u = [string]$Uri
    $b = if ($Body -is [string] -and $Body -and [string]$ContentType -like "*json*") { $Body | ConvertFrom-Json -NoEnumerate } else { $null }
    $null = $MockWorld.calls.Add("$m $u")
    $isAuth = $u -match '/auth/token$|/security/authenticate$'
    if ($m -ne 'GET' -and -not $isAuth) { $null = $MockWorld.writes.Add([pscustomobject]@{ Method = $m; Uri = $u; Body = $b }) }
    if ($MockWorld.fail -and $u -like $MockWorld.fail) { New-HttpError 403 '{"message":"The API member does not have the Service Tickets inquire permission."}' }
    $api = $MockBase[$MockWorld.psa]
    switch ($MockWorld.psa) {
        'connectwise' {
            if ($m -eq 'GET' -and $u.StartsWith("$api/service/tickets?")) {
                $q = Get-Query $u
                if ([int]$q['page'] -gt 1) { return @() }
                return @($MockWorld.tickets | ForEach-Object { [pscustomobject]@{ id = $_.id; summary = $_.summary; company = [pscustomobject]@{ id = $_.companyId; name = $_.companyName }; status = [pscustomobject]@{ name = $_.status }; priority = [pscustomobject]@{ name = (Get-PrioLabel $_) }; dateEntered = (Get-Iso $_.created); closedDate = $null; board = [pscustomobject]@{ id = 1 }; _info = [pscustomobject]@{ lastUpdated = (Get-Iso $_.updated) } } })
            }
            if ($m -eq 'GET' -and $u -match '/service/tickets/(\d+)/notes') {
                $t = Get-WorldTicket (Get-IdFrom $u '/service/tickets/(\d+)/notes')
                return @($t.notes | Sort-Object { $_.id } -Descending | ForEach-Object {
                        $o = [ordered]@{ id = $_.id; text = $_.text; dateCreated = (Get-Iso $_.created); internalAnalysisFlag = $_.internal; detailDescriptionFlag = (-not $_.internal) }
                        if ($_.client) { $o.contact = [pscustomobject]@{ id = 9; name = 'Pat Example' } } else { $o.member = [pscustomobject]@{ identifier = 'jlee' } }
                        [pscustomobject]$o })
            }
            if ($m -eq 'POST' -and $u -match '/service/tickets/(\d+)/notes$') { Add-WorldNote $Matches[1] $b.text ([bool]$b.internalAnalysisFlag); return [pscustomobject]@{ id = $MockWorld.next } }
            if ($m -eq 'GET' -and $u -match '/service/tickets/(\d+)$') { $t = Get-WorldTicket $Matches[1]; return [pscustomobject]@{ id = $t.id; board = [pscustomobject]@{ id = 1 }; status = [pscustomobject]@{ name = $t.status } } }
            if ($m -eq 'GET' -and $u -like "$api/service/boards/1/statuses*") { return @($MockCwStatus.Keys | ForEach-Object { [pscustomobject]@{ id = [int]$_; name = $MockCwStatus[$_]; closedStatus = ($MockCwStatus[$_] -in @('Closed', 'Resolved')); defaultFlag = ($MockCwStatus[$_] -eq 'New'); inactive = $false } }) }
            if ($m -eq 'PATCH' -and $u -match '/service/tickets/(\d+)$') { Set-WorldStatus $Matches[1] $MockCwStatus[[string]$b[0].value.id]; return [pscustomobject]@{ id = 1 } }
            if ($m -eq 'GET' -and $u -like "$api/company/companies*") { return @([pscustomobject]@{ id = 42; name = 'Contoso' }) }
        }
        'autotask' {
            if ($m -eq 'GET' -and $u -like "$api/Tickets/entityInformation/fields") {
                return [pscustomobject]@{ fields = @(
                        [pscustomobject]@{ name = 'status'; picklistValues = @($MockAtStatus.Keys | ForEach-Object { [pscustomobject]@{ value = $_; label = $MockAtStatus[$_]; isActive = $true } }) },
                        [pscustomobject]@{ name = 'priority'; picklistValues = @([pscustomobject]@{ value = '4'; label = 'Critical'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Medium'; isActive = $true }) }) }
            }
            if ($m -eq 'GET' -and $u -like "$api/TicketNotes/entityInformation/fields") {
                return [pscustomobject]@{ fields = @(
                        [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                        [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) }
            }
            if ($m -eq 'GET' -and $u.StartsWith("$api/Tickets/query?")) {
                $s = (Get-Query $u)['search'] | ConvertFrom-Json
                $sv = [string]@($s.filter | Where-Object { $_.field -eq 'status' })[0].value
                return [pscustomobject]@{ items = @($MockWorld.tickets | Where-Object { $_.status -eq $MockAtStatus[$sv] } | ForEach-Object { [pscustomobject]@{ id = $_.id; ticketNumber = "T2026.$($_.id)"; title = $_.summary; companyID = $_.companyId; status = [int]$sv; priority = (Get-PrioLabel $_); createDate = (Get-Iso $_.created); lastActivityDate = (Get-Iso $_.updated); resolvedDateTime = (Get-Iso $_.statusChanged) } }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } }
            }
            if ($m -eq 'GET' -and $u.StartsWith("$api/TicketNotes/query?")) {
                $s = (Get-Query $u)['search'] | ConvertFrom-Json
                $t = Get-WorldTicket $s.filter[0].value
                return [pscustomobject]@{ items = @($t.notes | ForEach-Object { [pscustomobject]@{ id = $_.id; description = $_.text; createDateTime = (Get-Iso $_.created); publish = $(if ($_.internal) { 2 } else { 1 }); createdByContactID = $(if ($_.client) { 77 } else { $null }); creatorResourceID = $(if ($_.client) { $null } else { 29682885 }) } }) }
            }
            if ($m -eq 'POST' -and $u -match '/Tickets/(\d+)/Notes$') { Add-WorldNote $Matches[1] $b.description ([int]$b.publish -eq 2); return [pscustomobject]@{ itemId = $MockWorld.next } }
            if ($m -eq 'PATCH' -and $u -like "$api/Tickets") { Set-WorldStatus $b.id $MockAtStatus[[string]$b.status]; return [pscustomobject]@{ itemId = $b.id } }
        }
        'halopsa' {
            if ($u -eq 'https://halo.example.com/auth/token') { return [pscustomobject]@{ access_token = 'halo-token' } }
            if ($m -eq 'GET' -and $u -eq "$api/Status") { return @($MockHaloStatus.Keys | ForEach-Object { [pscustomobject]@{ id = [int]$_; name = $MockHaloStatus[$_] } }) }
            if ($m -eq 'GET' -and $u.StartsWith("$api/Tickets?")) {
                $q = Get-Query $u; if ([int]$q['page_no'] -gt 1) { return [pscustomobject]@{ tickets = @(); record_count = 0 } }
                $rows = @($MockWorld.tickets | Where-Object { $_.status -eq $MockHaloStatus[$q['status_id']] } | ForEach-Object { [pscustomobject]@{ id = $_.id; summary = $_.summary; client_id = $_.companyId; client_name = $_.companyName; status_id = [int]$q['status_id']; priority_id = (Get-PrioLabel $_); dateoccurred = (Get-Iso $_.created); lastactiondate = (Get-Iso $_.updated) } })
                return [pscustomobject]@{ tickets = $rows; record_count = $rows.Count }
            }
            if ($m -eq 'GET' -and $u.StartsWith("$api/Actions?")) {
                $t = Get-WorldTicket (Get-Query $u)['ticket_id']
                return [pscustomobject]@{ actions = @($t.notes | ForEach-Object { [pscustomobject]@{ id = $_.id; note = $_.text; datetime = (Get-Iso $_.created); hiddenfromuser = $_.internal; who_type = $(if ($_.client) { 2 } else { 1 }); who = $(if ($_.client) { 'Pat Example' } else { 'J Lee' }) } }) }
            }
            if ($m -eq 'POST' -and $u -eq "$api/Actions") { Add-WorldNote $b[0].ticket_id $b[0].note ([bool]$b[0].hiddenfromuser); return @([pscustomobject]@{ id = 1 }) }
            if ($m -eq 'POST' -and $u -eq "$api/Tickets") { if ($b[0].PSObject.Properties['status_id']) { Set-WorldStatus $b[0].id $MockHaloStatus[[string]$b[0].status_id] }; return @([pscustomobject]@{ id = $b[0].id }) }
        }
        'kaseyabms' {
            if ($u -eq 'https://bms.example.com/v2/security/authenticate') { return [pscustomobject]@{ Result = [pscustomobject]@{ AccessToken = 'bms-token' } } }
            if ($m -eq 'GET' -and $u -eq "$api/system/statuses/lookup") { return [pscustomobject]@{ Success = $true; Result = @($MockBmsStatus.Keys | ForEach-Object { [pscustomobject]@{ Id = [int]$_; Name = $MockBmsStatus[$_]; IsActive = $true } }) } }
            if ($m -eq 'GET' -and $u.StartsWith("$api/servicedesk/tickets?")) {
                $q = Get-Query $u; if ([int]$q['PageNumber'] -gt 1) { return [pscustomobject]@{ Result = @(); TotalRecords = 0 } }
                return [pscustomobject]@{ Success = $true; TotalRecords = $MockWorld.tickets.Count; Result = @($MockWorld.tickets | ForEach-Object { [pscustomobject]@{ Id = $_.id; TicketNumber = "T$($_.id)"; Title = $_.summary; AccountId = $_.companyId; AccountName = $_.companyName; StatusName = $_.status; PriorityName = (Get-PrioLabel $_); OpenDate = (Get-Iso $_.created); LastActivityUpdate = (Get-Iso $_.updated); LastStatusUpdate = (Get-Iso $_.statusChanged); CompletedDate = $null } }) }
            }
            if ($m -eq 'GET' -and $u -match '/servicedesk/tickets/(\d+)/notes') {
                $t = Get-WorldTicket $Matches[1]
                return [pscustomobject]@{ Success = $true; Result = @($t.notes | ForEach-Object { [pscustomobject]@{ Id = $_.id; Details = $_.text; CreatedOn = (Get-Iso $_.created); IsInternal = $_.internal; CreatedByName = 'J Lee' } }) }
            }
            if ($m -eq 'POST' -and $u -match '/servicedesk/tickets/(\d+)/notes$') { Add-WorldNote $Matches[1] $b.Details ([bool]$b.IsInternal); return [pscustomobject]@{ Success = $true } }
            if ($m -eq 'PATCH' -and $u -match '/servicedesk/tickets/(\d+)$') { Set-WorldStatus $Matches[1] $MockBmsStatus[[string]$b[0].value]; return [pscustomobject]@{ Success = $true } }
        }
        'syncro' {
            if ($m -eq 'GET' -and $u.StartsWith("$api/tickets?")) {
                $q = Get-Query $u
                return [pscustomobject]@{ tickets = @($MockWorld.tickets | ForEach-Object { [pscustomobject]@{ id = $_.id; number = 1000 + $_.id; subject = $_.summary; customer_id = $_.companyId; customer_business_then_name = $_.companyName; status = $_.status; priority = (Get-PrioLabel $_); created_at = (Get-Iso $_.created); updated_at = (Get-Iso $_.updated); resolved_at = $null } }); meta = [pscustomobject]@{ total_pages = 1; page = [int]$q['page'] } }
            }
            if ($m -eq 'GET' -and $u -match '/tickets/(\d+)$') {
                $t = Get-WorldTicket $Matches[1]
                return [pscustomobject]@{ ticket = [pscustomobject]@{ id = $t.id; status = $t.status; comments = @($t.notes | ForEach-Object { [pscustomobject]@{ id = $_.id; body = $_.text; created_at = (Get-Iso $_.created); hidden = $_.internal; user_id = $(if ($_.client) { $null } else { 5 }); tech = $(if ($_.client) { 'Pat Example' } else { 'J Lee' }) } }) } }
            }
            if ($m -eq 'POST' -and $u -match '/tickets/(\d+)/comment$') { Add-WorldNote $Matches[1] $b.body ([bool]$b.hidden); return [pscustomobject]@{ comment = [pscustomobject]@{ id = 1 } } }
            if ($m -eq 'PUT' -and $u -match '/tickets/(\d+)$') { Set-WorldStatus $Matches[1] $b.status; return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1 } } }
        }
        'zendesk' {
            if ($m -eq 'GET' -and $u.StartsWith("$api/search?")) {
                return [pscustomobject]@{ next_page = $null; results = @($MockWorld.tickets | ForEach-Object { [pscustomobject]@{ id = $_.id; subject = $_.summary; organization_id = $_.companyId; status = $_.status; priority = (Get-PrioLabel $_); created_at = (Get-Iso $_.created); updated_at = (Get-Iso $_.updated); requester_id = 900 } }) }
            }
            if ($m -eq 'GET' -and $u -match '/tickets/(\d+)/comments') {
                $t = Get-WorldTicket $Matches[1]
                return [pscustomobject]@{ comments = @($t.notes | Sort-Object { $_.id } -Descending | ForEach-Object { [pscustomobject]@{ id = $_.id; body = $_.text; public = (-not $_.internal); author_id = $(if ($_.client) { 900 } else { 1 }); created_at = (Get-Iso $_.created) } }) }
            }
            if ($m -eq 'PUT' -and $u -match '/tickets/(\d+)$') {
                $id = $Matches[1]; $tk = $b.ticket
                if ($tk.PSObject.Properties['comment']) { Add-WorldNote $id $tk.comment.body (-not [bool]$tk.comment.public) }
                if ($tk.PSObject.Properties['status']) { Set-WorldStatus $id $tk.status }
                return [pscustomobject]@{ ticket = [pscustomobject]@{ id = [int]$id } }
            }
            if ($m -eq 'GET' -and $u -match '/tickets/(\d+)$') { $t = Get-WorldTicket $Matches[1]; return [pscustomobject]@{ ticket = [pscustomobject]@{ id = $t.id; requester_id = 900; status = $t.status } } }
        }
    }
    throw "Mock has no route for $m $u"
}

# ---- running the shipped steps ----
$MockSteps = [ordered]@{}
function Import-Steps {
    param([string]$BuildJs)
    $json = & node $BuildJs --dump
    if ($LASTEXITCODE -ne 0) { throw 'build.js --dump failed' }
    foreach ($s in @($json | ConvertFrom-Json)) { $MockSteps[$s.id] = $s.script }
}
# One step, the way the runner runs it: a child scope under strict mode, never dot-sourced.
function Invoke-Step {
    param([string]$Id, $StepInput)
    $MockHarness.Input = $StepInput; $MockHarness.Output = $null
    & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $MockSteps[$Id]))
    return $MockHarness.Output
}
# The runner hands each step the previous step's output as JSON.
function ConvertTo-RoundTrip { param($o) if ($null -eq $o) { return $null }; return ($o | ConvertTo-Json -Depth 30 | ConvertFrom-Json) }
function Invoke-Workflow {
    param($RunInput)
    $ids = @($MockSteps.Keys)
    $o = Invoke-Step $ids[0] $RunInput
    foreach ($id in $ids[1..($ids.Count - 1)]) { $o = Invoke-Step $id (ConvertTo-RoundTrip $o) }
    return (ConvertTo-RoundTrip $o)
}
function Get-ThrowMessage { param([scriptblock]$Body) try { $null = & $Body; return '' } catch { return [string]$_.Exception.Message } }
function Get-Writes { param([string]$Like = '*') return @($MockWorld.writes | Where-Object { "$($_.Method) $($_.Uri)" -like $Like }) }
function Complete-Test { Write-Host "$($MockTally.pass) passed, $($MockTally.fail) failed"; if ($MockTally.fail) { exit 1 }; exit 0 }
