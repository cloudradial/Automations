# Strict-mode harness for psa-hygiene.yml. Runs the four steps exactly as they are in the .yml
# (extracted by build.js --extract), each through & ([scriptblock]::Create(...)) under
# Set-StrictMode -Version Latest, passing each step's output to the next as JSON the way the runner does.
# Mocks Get-AzKeyVaultSecret, Invoke-RestMethod, Get-NodeInput, Set-NodeOutput and Start-Sleep.
# Covers all six PSAs. Placeholder data only (Contoso, Fabrikam, Example MSP).
# Usage: pwsh -NoProfile -File automationai/psa-hygiene/src/test.ps1
#        (needs node and js-yaml; set JS_YAML_PATH if js-yaml isn't installed in automationai/_shared)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:RUNNER_KV_NAME = 'kv-test'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("phy-test-" + [guid]::NewGuid().ToString('N'))
& node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { throw 'psa-hygiene.yml is out of date. Run node build.js first.' }
& node (Join-Path $PSScriptRoot 'build.js') --extract $tmp | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the steps.' }
$StepIds = @('node-inputs', 'node-find', 'node-fix', 'node-report')
$Steps = @{}; foreach ($s in $StepIds) { $Steps[$s] = Get-Content -Raw (Join-Path $tmp "$s.ps1") }
Remove-Item -Recurse -Force $tmp

$Tally = @{ pass = 0; fail = 0 }
$Mock = @{ Secrets = @{}; Calls = (New-Object System.Collections.ArrayList); Opt = @{}; Notes = (New-Object System.Collections.ArrayList) }
function Get-AzKeyVaultSecret { [CmdletBinding()] param($VaultName, $Name, [switch]$AsPlainText) if ($Mock.Secrets.Contains($Name)) { return $Mock.Secrets[$Name] }; return $null }
function Start-Sleep { [CmdletBinding()] param([double]$Seconds = 0, [int]$Milliseconds = 0) }
function Get-NodeInput { return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function New-HttpError {
    param([int]$Code, [string]$Body = '')
    $r = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Code)
    $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new("Response status code does not indicate success: $Code.", $r)
    $er = [System.Management.Automation.ErrorRecord]::new($ex, 'WebCmdletWebResponseException', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
    if ($Body) { $er.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Body) }
    throw $er
}
function J { param($o) return ($o | ConvertTo-Json -Depth 20 | ConvertFrom-Json) }
function Get-Ago { param([double]$Hours) return [datetime]::UtcNow.AddHours(-$Hours).ToString('yyyy-MM-ddTHH:mm:ssZ') }

# The open tickets every PSA returns, in neutral form:
#   201 stale (20 days), 202 no contact (Contoso, one primary), 203 no contact (Fabrikam, two primaries),
#   204 closed date on an open ticket, 205 unassigned for 3 days, 206 tidy, 207 unassigned for 2 hours (not flagged yet)
function Get-Spec {
    if ($Mock.Opt.Contains('NoTickets')) { return @() }
    return @(
        @{ id = 201; sum = 'VPN drops every afternoon'; co = 5; con = 9; asg = 3; created = 600; updated = 480; closed = $null },
        @{ id = 202; sum = 'New laptop for Pat'; co = 5; con = $null; asg = 3; created = 48; updated = 24; closed = $null },
        @{ id = 203; sum = 'Shared drive permissions'; co = 6; con = $null; asg = 3; created = 48; updated = 30; closed = $null },
        @{ id = 204; sum = 'Printer jam'; co = 5; con = 9; asg = 3; created = 200; updated = 20; closed = 72 },
        @{ id = 205; sum = 'Wi-Fi slow in boardroom'; co = 6; con = 11; asg = $null; created = 72; updated = 1; closed = $null },
        @{ id = 206; sum = 'Add user to Teams'; co = 5; con = 9; asg = 3; created = 1; updated = 1; closed = $null },
        @{ id = 207; sum = 'Monitor flickers'; co = 5; con = 9; asg = $null; created = 2; updated = 2; closed = $null })
}
$CoName = @{ 5 = 'Contoso'; 6 = 'Fabrikam' }
function Get-OpenFor {
    param([string]$Psa)
    $out = @()
    foreach ($s in (Get-Spec)) {
        $closedAt = $(if ($null -ne $s.closed) { Get-Ago $s.closed } else { $null })
        switch ($Psa) {
            'cw' { $out += J @{ id = $s.id; summary = $s.sum; company = @{ id = $s.co; name = $CoName[$s.co] }; contact = $(if ($s.con) { @{ id = $s.con; name = 'Pat Example' } } else { $null }); status = @{ name = 'In Progress' }; closedFlag = $false; closedDate = $closedAt; owner = $(if ($s.asg) { @{ identifier = 'jlee'; name = 'Jordan Lee' } } else { $null }); _info = @{ dateEntered = (Get-Ago $s.created); lastUpdated = (Get-Ago $s.updated) } } }
            'at' { $out += J @{ id = $s.id; ticketNumber = "T20261001.0$($s.id)"; title = $s.sum; companyID = $s.co; contactID = $s.con; status = 8; completedDate = $closedAt; createDate = (Get-Ago $s.created); lastActivityDate = (Get-Ago $s.updated); assignedResourceID = $s.asg } }
            'halo' { $out += J @{ id = $s.id; summary = $s.sum; client_id = $s.co; client_name = $CoName[$s.co]; user_id = $(if ($s.con) { $s.con } else { 0 }); user_name = ''; status_id = 2; status_name = 'In Progress'; agent_id = $(if ($s.asg) { $s.asg } else { 0 }); agent_name = $(if ($s.asg) { 'Jordan Lee' } else { '' }); dateoccurred = (Get-Ago $s.created); datecleared = $(if ($closedAt) { $closedAt } else { '1900-01-01T00:00:00' }); lastactiondate = (Get-Ago $s.updated) } }
            'bms' { $out += J @{ Id = $s.id; TicketNumber = "TKT$($s.id)"; Title = $s.sum; AccountId = $s.co; AccountName = $CoName[$s.co]; ContactId = $(if ($s.con) { $s.con } else { 0 }); ContactName = ''; StatusName = 'In Progress'; CompletedDate = $closedAt; OpenDate = (Get-Ago $s.created); LastActivityUpdate = (Get-Ago $s.updated); AssigneeId = $(if ($s.asg) { $s.asg } else { 0 }); AssigneeName = '' } }
            'syncro' { $out += J @{ id = $s.id; number = 1000 + $s.id; subject = $s.sum; customer_id = $s.co; customer_business_then_name = $CoName[$s.co]; contact_id = $s.con; status = 'In Progress'; resolved_at = $closedAt; created_at = (Get-Ago $s.created); updated_at = (Get-Ago $s.updated); user_id = $s.asg } }
            'zd' { $out += J @{ id = $s.id; subject = $s.sum; organization_id = $s.co; requester_id = $s.con; status = 'open'; assignee_id = $s.asg; created_at = (Get-Ago $s.created); updated_at = (Get-Ago $s.updated) } }
        }
    }
    return $out
}

function Invoke-RestMethod {
    [CmdletBinding()] param($Method = 'GET', $Uri, $Headers, $Body, $ContentType, $Form)
    $m = ([string]$Method).ToUpperInvariant(); $u = [string]$Uri; $d = [uri]::UnescapeDataString($u)
    $null = $Mock.Calls.Add([pscustomobject]@{ Method = $m; Uri = $u; Decoded = $d; Body = $(if ($Body -is [string]) { $Body } else { '' }) })
    $isWrite = $m -in @('PATCH', 'PUT') -or ($m -eq 'POST' -and $u -like '*/api/Tickets')
    if ($isWrite -and $Mock.Opt.Contains('FailPatch')) { New-HttpError 500 '{"message":"Mock server error"}' }
    # Postmark
    if ($u -eq 'https://api.postmark.test/email' -and $m -eq 'POST') { return [pscustomobject]@{ ErrorCode = 0; Message = 'OK'; MessageID = 'msg-1' } }
    # CloudRadial
    if ($u -like 'https://portal.example-msp.test/api/beta/archive*' -and $m -eq 'GET') { return @([pscustomobject]@{ id = 55; companyId = 1; name = 'PSA Hygiene' }) }
    if ($u -like 'https://portal.example-msp.test/v2/odata/archiveitem*') { return [pscustomobject]@{ value = @() } }
    if ($u -eq 'https://portal.example-msp.test/v2/archiveitem' -and $m -eq 'POST') { return [pscustomobject]@{ companyReportItemId = 777 } }
    # ConnectWise
    $cw = 'https://cw.example-msp.test/v4_6_release/apis/3.0'
    if ($u -like "$cw/service/tickets[?]*" -and $m -eq 'GET') {
        if ($Mock.Opt.Contains('Tickets403')) { New-HttpError 403 '{"code":"Forbidden","message":"You do not have access to this resource."}' }
        if ($d -like '*page=1*') { return @(Get-OpenFor 'cw') }; return @()
    }
    if ($u -like "$cw/company/companies/*") { $id = ($u -split '/')[-1]; return J @{ id = [int]$id; defaultContact = $(if ($id -eq '5') { @{ id = 9 } } else { $null }) } }
    if ($u -like "$cw/company/contacts[?]*") {
        if ($d -match 'company/id=5 ') { return @(J @{ id = 9; firstName = 'Pat'; lastName = 'Example' }; J @{ id = 10; firstName = 'Sam'; lastName = 'Example' }) }
        return @(J @{ id = 11; firstName = 'Alex'; lastName = 'Fabrikam'; defaultFlag = $true }; J @{ id = 12; firstName = 'Jo'; lastName = 'Fabrikam'; defaultFlag = $true })
    }
    if ($u -like "$cw/service/tickets/*/notes[?]*" -and $m -eq 'GET') { return @($Mock.Notes | ForEach-Object { [pscustomobject]@{ id = 1; text = $_; internalAnalysisFlag = $true } }) }
    if ($u -like "$cw/service/tickets/*/notes" -and $m -eq 'POST') { $null = $Mock.Notes.Add(($Body | ConvertFrom-Json).text); return [pscustomobject]@{ id = 1 } }
    if ($u -like "$cw/service/tickets/*" -and $m -eq 'PATCH') { return [pscustomobject]@{ id = 1 } }
    # Autotask
    $at = 'https://webservices.example-msp.test/atservicesrest/v1.0'
    if ($u -eq "$at/Tickets/entityInformation/fields") { return J @{ fields = @(@{ name = 'status'; picklistValues = @(@{ value = '1'; label = 'New'; isActive = $true }, @{ value = '5'; label = 'Complete'; isActive = $true }, @{ value = '8'; label = 'In Progress'; isActive = $true }) }) } }
    if ($u -like "$at/Tickets/query[?]*") { return J @{ items = @(Get-OpenFor 'at'); pageDetails = @{ nextPageUrl = $null } } }
    if ($u -like "$at/Companies/query[?]*") { return J @{ items = @(@{ id = 5; companyName = 'Contoso' }, @{ id = 6; companyName = 'Fabrikam' }) } }
    if ($u -like "$at/Contacts/query[?]*") {
        if ($d -match '"companyID","value":5') { return J @{ items = @(@{ id = 9; firstName = 'Pat'; lastName = 'Example'; primaryContact = $true }, @{ id = 10; firstName = 'Sam'; lastName = 'Example'; primaryContact = $false }) } }
        return J @{ items = @(@{ id = 11; firstName = 'Alex'; lastName = 'Fabrikam'; primaryContact = $true }, @{ id = 12; firstName = 'Jo'; lastName = 'Fabrikam'; primaryContact = $true }) }
    }
    if ($u -eq "$at/Tickets" -and $m -eq 'PATCH') { return [pscustomobject]@{ itemId = 202 } }
    # HaloPSA
    if ($u -eq 'https://halo.example-msp.test/auth/token') { return [pscustomobject]@{ access_token = 'halo-token' } }
    if ($u -like 'https://halo.example-msp.test/api/Tickets[?]*') { return J @{ tickets = @(Get-OpenFor 'halo'); record_count = 7 } }
    if ($u -like 'https://halo.example-msp.test/api/Users[?]*') {
        if ($d -match 'client_id=5&') { return J @{ users = @(@{ id = 9; name = 'Pat Example'; isprimarycontact = $true }, @{ id = 10; name = 'Sam Example'; isprimarycontact = $false }) } }
        return J @{ users = @(@{ id = 11; name = 'Alex Fabrikam'; isprimarycontact = $false }) }
    }
    if ($u -eq 'https://halo.example-msp.test/api/Tickets' -and $m -eq 'POST') { return @([pscustomobject]@{ id = 202 }) }
    # Kaseya BMS
    if ($u -eq 'https://bms.example-msp.test/v2/security/authenticate') { return J @{ Success = $true; Result = @{ AccessToken = 'bms-token' } } }
    if ($u -like 'https://bms.example-msp.test/v2/servicedesk/tickets[?]*') { $r = @(Get-OpenFor 'bms'); return J @{ Success = $true; Result = $r; TotalRecords = $r.Count } }
    if ($u -like 'https://bms.example-msp.test/v2/crm/contacts/summary[?]*') {
        if ($d -match 'AccountId=5&') { return J @{ Success = $true; Result = @(@{ Id = 9; FirstName = 'Pat'; LastName = 'Example'; IsPoc = $true; Emails = @(@{ EmailAddress = 'pat@contoso.com' }) }, @{ Id = 10; FirstName = 'Sam'; LastName = 'Example'; IsPoc = $false; Emails = @() }) } }
        return J @{ Success = $true; Result = @() }
    }
    if ($u -like 'https://bms.example-msp.test/v2/servicedesk/tickets/*' -and $m -eq 'PATCH') { return J @{ Success = $true } }
    # Syncro
    if ($u -like 'https://examplemsp.syncro.test/api/v1/tickets[?]*') { return J @{ tickets = @(Get-OpenFor 'syncro'); meta = @{ total_pages = 1 } } }
    # Zendesk
    if ($u -like 'https://examplemsp.zendesk.test/api/v2/search[?]*') { return J @{ results = @(Get-OpenFor 'zd'); next_page = $null } }
    if ($u -like 'https://examplemsp.zendesk.test/api/v2/organizations/*/users*') { return J @{ users = @(@{ id = 9; name = 'Pat Example'; email = 'pat@contoso.com'; active = $true }) } }
    if ($u -like 'https://examplemsp.zendesk.test/api/v2/tickets/*' -and $m -eq 'PUT') { return J @{ ticket = @{ id = 1 } } }
    throw "Unmocked call: $m $u"
}

function Get-Calls { param([string]$Method, [string]$Like) return @($Mock.Calls | Where-Object { $_.Method -eq $Method -and $_.Uri -like $Like }) }
function Get-PsaWrites { return @($Mock.Calls | Where-Object { $_.Method -in @('PATCH', 'POST', 'PUT', 'DELETE') -and $_.Uri -notlike 'https://api.postmark.test/*' -and $_.Uri -notlike 'https://portal.example-msp.test/*' -and $_.Uri -notlike '*/auth/token' -and $_.Uri -notlike '*/security/authenticate' }) }
function Check { param([string]$Name, [bool]$Ok, $Detail = '') if ($Ok) { $Tally.pass++; Write-Host "PASS $Name" } else { $Tally.fail++; Write-Host "FAIL $Name :: $Detail" -ForegroundColor Red } }
function RoundTrip { param($o) if ($null -eq $o) { return $null }; return ($o | ConvertTo-Json -Depth 30 | ConvertFrom-Json) }

$BaseSecrets = @{
    'Postmark-ServerToken' = 'pm-token'; 'Postmark-FromEmail' = 'reports@example-msp.test'; 'Postmark-ApiUrl' = 'https://api.postmark.test'
    'CloudRadial-BaseUrl' = 'https://portal.example-msp.test'; 'CloudRadial-PublicKey' = 'pub'; 'CloudRadial-PrivateKey' = 'priv'
    'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://cw.example-msp.test/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'p'; 'CW-PrivateKey' = 'k'; 'CW-ClientId' = 'c'
    'Autotask-ApiUrl' = 'https://webservices.example-msp.test'; 'Autotask-ApiIntegrationCode' = 'i'; 'Autotask-Username' = 'api@example-msp.test'; 'Autotask-Secret' = 's'
    'Halo-ApiUrl' = 'https://halo.example-msp.test'; 'Halo-ClientId' = 'hc'; 'Halo-ClientSecret' = 'hs'
    'KaseyaBMS-ApiUrl' = 'https://bms.example-msp.test'; 'KaseyaBMS-Username' = 'u'; 'KaseyaBMS-Password' = 'p'; 'KaseyaBMS-CompanyName' = 'examplemsp'
    'Syncro-ApiUrl' = 'https://examplemsp.syncro.test/api/v1'; 'Syncro-ApiKey' = 'k'
    'Zendesk-BaseUrl' = 'https://examplemsp.zendesk.test'; 'Zendesk-Email' = 'agent@example-msp.test'; 'Zendesk-ApiToken' = 't'
}

function Invoke-Workflow {
    param($RunInput, [hashtable]$Secrets = @{}, [hashtable]$Opt = @{})
    $Mock.Secrets = $BaseSecrets.Clone(); foreach ($k in $Secrets.Keys) { if ($null -eq $Secrets[$k]) { $Mock.Secrets.Remove($k) } else { $Mock.Secrets[$k] = $Secrets[$k] } }
    $Mock.Calls.Clear(); $Mock.Opt = $Opt
    $global:NodeIn = $(if ($RunInput -is [string] -or $null -eq $RunInput) { $RunInput } else { RoundTrip $RunInput })
    $global:NodeOut = $null
    foreach ($s in $StepIds) {
        try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps[$s])) }
        catch { return @{ out = (RoundTrip $global:NodeOut); error = [string]$_.Exception.Message; step = $s } }
        $global:NodeIn = RoundTrip $global:NodeOut
    }
    return @{ out = $global:NodeIn; error = ''; step = 'end' }
}
function Get-Cat { param($o, [string]$Cat) return ((@($o.issues | Where-Object { $_.category -eq $Cat } | ForEach-Object { [string]$_.ticket_id }) | Sort-Object) -join ',') }

# 1. ConnectWise report with a fix preview.
$r = Invoke-Workflow @{ fix = 'missing_contact'; to = 'service.manager@example-msp.test'; archive_company_id = '1' }
$o = $r.out
Check 'preview: no error' ($r.error -eq '') "$($r.step) $($r.error)"
Check 'preview: status pending_confirmation' ($o.status -eq 'pending_confirmation') $o.status
Check 'preview: stale 201' ((Get-Cat $o 'stale') -eq '201') (Get-Cat $o 'stale')
Check 'preview: missing contact 202,203' ((Get-Cat $o 'missing_contact') -eq '202,203') (Get-Cat $o 'missing_contact')
Check 'preview: wrong status 204,205 (207 too new)' ((Get-Cat $o 'wrong_status') -eq '204,205') (Get-Cat $o 'wrong_status')
Check 'preview: counts' ($o.counts.open_tickets -eq 7 -and $o.counts.tickets_with_issues -eq 5) ($o.counts | ConvertTo-Json -Compress)
Check 'preview: plans only 202 (one primary)' (@($o.fix.planned).Count -eq 1 -and @($o.fix.planned)[0] -eq 'Set the contact on ticket 202 (Contoso) to Pat Example') (@($o.fix.planned) -join '; ')
Check 'preview: 203 skipped, two primaries' (@($o.fix.skipped).Count -eq 1 -and @($o.fix.skipped)[0].reason -match '2 primary contacts') (@($o.fix.skipped | ForEach-Object { $_.reason }) -join '; ')
Check 'preview: no PSA writes' (@(Get-PsaWrites).Count -eq 0) (@(Get-PsaWrites | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')
Check 'preview: message says nothing changed' ($o.message -match 'Checked 7 open tickets in ConnectWise and found 1 stale \(no update for 14 days or more\), 2 missing a contact, 2 with a status that contradicts the ticket\.' -and $o.message -match 'Nothing was changed\. With confirm set to true') $o.message
$pm = @(Get-Calls POST 'https://api.postmark.test/email')
Check 'preview: emailed once' ($pm.Count -eq 1) ''
$pb = $pm[0].Body | ConvertFrom-Json
Check 'preview: email has the three tables' ($pb.HtmlBody -match 'Stale tickets' -and $pb.HtmlBody -match 'Tickets with no contact' -and $pb.HtmlBody -match 'Status contradicts the ticket' -and $pb.HtmlBody -match 'not changed yet') ''
Check 'preview: archive written to own company' (@(Get-Calls POST 'https://portal.example-msp.test/v2/archiveitem').Count -eq 1 -and $o.report.action -eq 'created') ''
$ab = @(Get-Calls POST 'https://portal.example-msp.test/v2/archiveitem')[0].Body | ConvertFrom-Json
Check 'preview: archive item in company 1, archive 55' ($ab.companyId -eq 1 -and $ab.archiveId -eq 55 -and $ab.subject -like 'PSA hygiene *') $ab.subject
Check 'preview: no report_html when delivered' ($null -eq $o.PSObject.Properties['report_html']) ''

# 2. Confirm with ConnectWise: sets 202's contact only.
$r = Invoke-Workflow @{ fix = 'missing_contact'; confirm = $true; to = 'service.manager@example-msp.test' }
$o = $r.out
Check 'confirm cw: success' ($r.error -eq '' -and $o.status -eq 'success') "$($o.status) $($r.error)"
$pw = @(Get-PsaWrites)
Check 'confirm cw: one PATCH on 202' ($pw.Count -eq 1 -and $pw[0].Method -eq 'PATCH' -and $pw[0].Uri -like '*/service/tickets/202') (@($pw | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')
$pbody = $pw[0].Body | ConvertFrom-Json
Check 'confirm cw: json-patch contact id 9' (@($pbody)[0].op -eq 'replace' -and @($pbody)[0].path -eq 'contact' -and @($pbody)[0].value.id -eq 9) $pw[0].Body
Check 'confirm cw: changed listed' (@($o.fix.changed).Count -eq 1) ''
Check 'confirm cw: message' ($o.message -match 'Set the contact on 1 ticket from the company''s only primary contact') $o.message
Check 'confirm cw: email subject says changes' ((@(Get-Calls POST 'https://api.postmark.test/email')[0].Body | ConvertFrom-Json).Subject -like 'PSA hygiene changes *') ''

# 3. Confirm with Autotask.
$r = Invoke-Workflow @{ psa = 'autotask'; fix = 'contacts'; confirm = 'true' }
$o = $r.out
Check 'confirm autotask: success' ($r.error -eq '' -and $o.status -eq 'success') "$($o.status) $($r.error)"
Check 'autotask: same findings' ((Get-Cat $o 'stale') -eq '201' -and (Get-Cat $o 'missing_contact') -eq '202,203' -and (Get-Cat $o 'wrong_status') -eq '204,205') ''
$pw = @(Get-PsaWrites)
Check 'confirm autotask: PATCH /Tickets with contactID 9' ($pw.Count -eq 1 -and $pw[0].Uri -like '*/atservicesrest/v1.0/Tickets' -and ($pw[0].Body | ConvertFrom-Json).contactID -eq 9 -and ($pw[0].Body | ConvertFrom-Json).id -eq 202) (@($pw | ForEach-Object { "$($_.Method) $($_.Uri) $($_.Body)" }) -join '; ')
Check 'autotask: company names resolved' (@($o.issues | Where-Object { $_.ticket_id -eq '203' })[0].company -eq 'Fabrikam') ''

# 4. HaloPSA and Kaseya BMS confirm.
$r = Invoke-Workflow @{ psa = 'halopsa'; fix = 'missing_contact'; confirm = $true }
$o = $r.out
# HaloPSA and Kaseya BMS: _shared/psa-tickets.ps1 counts a ticket with a closed date as closed, so -Open drops
# 204 (closed date on an open ticket) and only the unassigned ticket 205 is a wrong status there.
Check 'halo: findings' ($r.error -eq '' -and (Get-Cat $o 'stale') -eq '201' -and (Get-Cat $o 'missing_contact') -eq '202,203' -and (Get-Cat $o 'wrong_status') -eq '205') "$(Get-Cat $o 'wrong_status') $($r.error)"
$pw = @(Get-PsaWrites)
Check 'halo: POST Tickets user_id 9 on 202' ($pw.Count -eq 1 -and @($pw[0].Body | ConvertFrom-Json)[0].user_id -eq 9) (@($pw | ForEach-Object { $_.Body }) -join '; ')
Check 'halo: 203 skipped, no primary' (@($o.fix.skipped)[0].reason -match 'no primary contact') ''
$r = Invoke-Workflow @{ psa = 'kaseyabms'; fix = 'missing_contact'; confirm = $true }
$o = $r.out
Check 'bms: findings' ($r.error -eq '' -and (Get-Cat $o 'missing_contact') -eq '202,203' -and (Get-Cat $o 'wrong_status') -eq '205') "$($r.error)"
$pw = @(Get-PsaWrites)
Check 'bms: PATCH ContactId 9 on 202' ($pw.Count -eq 1 -and $pw[0].Uri -like '*/v2/servicedesk/tickets/202' -and @($pw[0].Body | ConvertFrom-Json)[0].path -eq '/ContactId') (@($pw | ForEach-Object { "$($_.Uri) $($_.Body)" }) -join '; ')

# 5. Syncro: contacts not checked; Zendesk: no primary flag, so nothing is fixed.
$r = Invoke-Workflow @{ psa = 'syncro'; fix = 'missing_contact'; confirm = $true }
$o = $r.out
Check 'syncro: no missing-contact check, warned' ($r.error -eq '' -and (Get-Cat $o 'missing_contact') -eq '' -and ((@($o.warnings) -join ' ') -match 'Syncro tickets without a contact')) "$($r.error)"
Check 'syncro: stale and wrong status found' ((Get-Cat $o 'stale') -eq '201' -and (Get-Cat $o 'wrong_status') -eq '204,205') ''
Check 'syncro: no writes' (@(Get-PsaWrites).Count -eq 0) ''
$r = Invoke-Workflow @{ psa = 'zendesk'; fix = 'missing_contact'; confirm = $true }
$o = $r.out
Check 'zendesk: missing requester found' ($r.error -eq '' -and (Get-Cat $o 'missing_contact') -eq '202,203') "$($r.error)"
Check 'zendesk: no closed-date contradiction possible, unassigned still found' ((Get-Cat $o 'wrong_status') -eq '205') (Get-Cat $o 'wrong_status')
Check 'zendesk: skipped, no primary flag, no writes' (@($o.fix.skipped).Count -eq 2 -and @($o.fix.skipped)[0].reason -match 'no primary contact flag' -and @(Get-PsaWrites).Count -eq 0) (@($o.fix.skipped | ForEach-Object { $_.reason }) -join '; ')

# 6. Confirm without a fix list changes nothing.
$r = Invoke-Workflow @{ confirm = $true }
Check 'confirm without fix: no writes, warned' ($r.error -eq '' -and @(Get-PsaWrites).Count -eq 0 -and ((@($r.out.warnings) -join ' ') -match 'fix was empty')) (@($r.out.warnings) -join ' | ')
Check 'confirm without fix: no contact lookups' (@(Get-Calls GET '*/company/contacts*').Count -eq 0) ''

# 7. A fix that fails stops and says so.
$r = Invoke-Workflow @{ fix = 'missing_contact'; confirm = $true } @{} @{ FailPatch = $true }
Check 'failed fix: status error' ($r.out.status -eq 'error' -and $r.out.message -match "stopped because 'Set the contact on ticket 202") $r.out.message

# 8. Missing permission (403) on tickets.
$r = Invoke-Workflow @{ to = 'service.manager@example-msp.test' } @{} @{ Tickets403 = $true }
Check '403: stops in Find step' ($r.step -eq 'node-find') $r.step
Check '403: plain permission message' ($r.error -eq "The ConnectWise API account isn't allowed to read tickets (HTTP 403). Give it read access to service tickets and run again. Nothing was changed.") $r.error
Check '403: no email, no writes' (@(Get-Calls POST 'https://api.postmark.test/email').Count -eq 0 -and @(Get-PsaWrites).Count -eq 0) ''

# 9. Empty result.
$r = Invoke-Workflow @{ to = 'service.manager@example-msp.test' } @{} @{ NoTickets = $true }
Check 'empty: success and plain message' ($r.error -eq '' -and $r.out.status -eq 'success' -and $r.out.message -match '^There are no open tickets in ConnectWise') "$($r.out.message) $($r.error)"

# 10. Weekly Routine: no input. Recipient and archive company from secrets.
$r = Invoke-Workflow $null @{ 'ServiceManager-Email' = 'dispatch@example-msp.test'; 'CloudRadial-InternalCompanyId' = '1' }
$o = $r.out
Check 'routine: success, report only' ($r.error -eq '' -and $o.status -eq 'success' -and @(Get-PsaWrites).Count -eq 0) "$($o.status) $($r.error)"
Check 'routine: says it only reports' ($o.message -match 'Nothing was changed\. This run only reports\.') $o.message
Check 'routine: emailed the secret recipient' ((@(Get-Calls POST 'https://api.postmark.test/email')[0].Body | ConvertFrom-Json).To -eq 'dispatch@example-msp.test') ''
Check 'routine: archived to the internal company' (((@(Get-Calls POST 'https://portal.example-msp.test/v2/archiveitem')[0].Body | ConvertFrom-Json).companyId) -eq 1) ''
$r = Invoke-Workflow $null @{ 'CloudRadial-CompanyId' = '9' }
Check 'routine: a client CloudRadial-CompanyId is never used for the archive' ($r.error -eq '' -and @(Get-Calls POST 'https://portal.example-msp.test/*').Count -eq 0 -and @(Get-Calls GET 'https://portal.example-msp.test/*').Count -eq 0) ''

# 11. No Postmark: internal note fallback on the given ticket.
$Mock.Notes.Clear()
$r = Invoke-Workflow @{ ticket_id = '9001'; to = 'service.manager@example-msp.test' } @{ 'Postmark-ServerToken' = $null }
$o = $r.out
$note = @(Get-Calls POST 'https://cw.example-msp.test/*/service/tickets/9001/notes')
Check 'no postmark: internal note on 9001' ($note.Count -eq 1 -and ($note[0].Body | ConvertFrom-Json).internalAnalysisFlag -eq $true -and ($note[0].Body | ConvertFrom-Json).text -match 'Ticket 201') ''
Check 'no postmark: warning names the secret' ((@($o.warnings) -join ' ') -match 'add the Postmark-ServerToken secret') (@($o.warnings) -join ' | ')
Check 'no postmark, no archive: report_html kept' ($o.report_html -match '<table') ''
Check 'no postmark: the note ends with its retry marker' (($note[0].Body | ConvertFrom-Json).text.TrimEnd() -match '\[psa-hygiene \d{4}-\d{2}-\d{2} [0-9a-f]{12}\]$') ($note[0].Body | ConvertFrom-Json).text
# Rerun of the same request (ServiceAI Retry or the Routine run again): the summary note is not added twice.
$r = Invoke-Workflow @{ ticket_id = '9001'; to = 'service.manager@example-msp.test' } @{ 'Postmark-ServerToken' = $null }
Check 'rerun: no second summary note on 9001' (@(Get-Calls POST 'https://cw.example-msp.test/*/service/tickets/9001/notes').Count -eq 0 -and $Mock.Notes.Count -eq 1 -and ((@($r.out.actions) -join ' ') -match 'already on ticket 9001')) (@($r.out.actions) -join ' | ')
# A run with other settings is a different report, so it gets its own note.
$r = Invoke-Workflow @{ ticket_id = '9001'; to = 'service.manager@example-msp.test'; stale_days = 30 } @{ 'Postmark-ServerToken' = $null }
Check 'rerun with other settings: one new note' (@(Get-Calls POST 'https://cw.example-msp.test/*/service/tickets/9001/notes').Count -eq 1 -and $Mock.Notes.Count -eq 2) ''

# 12. Nothing delivered at all: report only in the output.
$r = Invoke-Workflow @{} @{ 'Postmark-ServerToken' = $null }
Check 'no delivery: message says output only' ($r.out.message -match 'only in the run output') $r.out.message

# 13. Archive failure becomes a warning.
$r = Invoke-Workflow @{ archive_company_id = '1' } @{ 'CloudRadial-PrivateKey' = $null }
Check 'archive failure: warning, run finishes' ($r.error -eq '' -and ((@($r.out.warnings) -join ' ') -match "Couldn't write the report to the Report Archive")) (@($r.out.warnings) -join ' | ')

# 14. Bad input fails closed before any call.
$r = Invoke-Workflow @{ stale_days = 'two weeks' }
Check 'bad stale_days: incomplete, no calls' ($r.step -eq 'node-inputs' -and $r.out.status -eq 'incomplete' -and $Mock.Calls.Count -eq 0) $r.error
$r = Invoke-Workflow @{ fix = 'delete_everything'; confirm = $true }
Check 'unknown fix: rejected before any call' ($r.step -eq 'node-inputs' -and $r.error -match 'fix can only name missing_contact' -and $Mock.Calls.Count -eq 0) $r.error
$r = Invoke-Workflow @{ fix = 'stale,missing_contact' }
Check 'unfixable category: warned, still reports' ($r.error -eq '' -and ((@($r.out.warnings) -join ' ') -match "'stale' can't be fixed automatically")) (@($r.out.warnings) -join ' | ')
$r = Invoke-Workflow @{ archive_company_id = 'Contoso' }
Check 'bad archive id: incomplete' ($r.step -eq 'node-inputs' -and $r.error -match 'archive_company_id') $r.error

# 15. stale_days and company filter reach the PSA query.
$r = Invoke-Workflow @{ stale_days = 30; company_id = '5' }
Check 'stale_days 30: 201 no longer stale' ($r.error -eq '' -and (Get-Cat $r.out 'stale') -eq '') (Get-Cat $r.out 'stale')
Check 'company filter in conditions' (@(Get-Calls GET 'https://cw.example-msp.test/*/service/tickets[?]*')[0].Decoded -match 'closedFlag=false and company/id=5') ''

Write-Host "$($Tally.pass) passed, $($Tally.fail) failed"
if ($Tally.fail) { exit 1 }
exit 0
