# Mock runner, mock PSAs, mock Postmark and mock Twilio for test.ps1.
# Mocks Get-AzKeyVaultSecret, Invoke-RestMethod, Start-Sleep, Get-NodeInput and Set-NodeOutput.
# A small in-memory "world" holds one ticket per PSA with its contact and notes, answers each PSA's ticket,
# contact and note calls in that PSA's own JSON shape, and applies note writes so a second run sees them.
# Emails and texts are captured (with their bodies) so the tests can read the code a contact received.
# Placeholder data only (Contoso, Example MSP).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:RUNNER_KV_NAME = 'kv-test'

$MockTally = @{ pass = 0; fail = 0 }
function Check {
    param([string]$Name, [bool]$Ok, $Detail = '')
    if ($Ok) { $MockTally.pass++; Write-Host "PASS $Name" } else { $MockTally.fail++; Write-Host "FAIL $Name :: $Detail" -ForegroundColor Red }
}

$MockPsaSecrets = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://cw.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    halopsa     = @{ 'PSA-Type' = 'halopsa'; 'Halo-ApiUrl' = 'https://halo.example.com'; 'Halo-ClientId' = 'cid'; 'Halo-ClientSecret' = 'sec' }
    kaseyabms   = @{ 'PSA-Type' = 'kaseyabms'; 'KaseyaBMS-ApiUrl' = 'https://bms.example.com'; 'KaseyaBMS-Username' = 'u'; 'KaseyaBMS-Password' = 'p'; 'KaseyaBMS-CompanyName' = 'Example MSP' }
}
$MockBase = @{ connectwise = 'https://cw.example.com/v4_6_release/apis/3.0'; autotask = 'https://webservices.autotask.example/atservicesrest/v1.0'; halopsa = 'https://halo.example.com/api' }
$MockShared = @{
    'VerifyCaller-Key' = 'example-test-key-0123456789abcdef0123456789'
    'Postmark-ServerToken' = 'pm-token'; 'Postmark-FromEmail' = 'support@examplemsp.example'
    'Twilio-AccountSid' = 'AC00000000000000000000000000000000'; 'Twilio-AuthToken' = 'tw-token'; 'Twilio-FromNumber' = '+15550100000'
}

$MockWorld = @{ psa = ''; secrets = @{}; ticket = $null; contact = $null; writes = (New-Object System.Collections.ArrayList); emails = (New-Object System.Collections.ArrayList); texts = (New-Object System.Collections.ArrayList); next = 5000; twilioFail = 0; postmarkFail = 0 }
$MockHarness = @{ Input = $null; Output = $null }

function Get-AzKeyVaultSecret { [CmdletBinding()] param($VaultName, $Name, [switch]$AsPlainText) $s = $MockWorld.secrets; if ($s.Contains($Name)) { return $s[$Name] }; return $null }
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
function Get-Iso { param($d) if ($null -eq $d) { return $null }; return $d.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) }
function Get-Query { param([string]$Uri) $q = @{}; $i = $Uri.IndexOf('?'); if ($i -lt 0) { return $q }; foreach ($pair in $Uri.Substring($i + 1).Split('&')) { $kv = $pair.Split('=', 2); $q[[uri]::UnescapeDataString($kv[0])] = $(if ($kv.Count -gt 1) { [uri]::UnescapeDataString($kv[1].Replace('+', ' ')) } else { '' }) }; return $q }

# A fresh world: ticket 301 for Contoso, contact Megan Bowen, one client note. -NoContact, -NoEmail, -Mobile and
# -Inactive shape the contact; -Twilio $false and -Postmark $false leave those secrets out; -Key overrides the key.
function Reset-World {
    param([string]$Psa, [switch]$NoContact, [switch]$NoEmail, [string]$Mobile = '+1 (555) 010-1234', [switch]$Inactive, [bool]$Twilio = $true, [bool]$Postmark = $true, [string]$Key = 'default')
    $MockWorld.psa = $Psa; $MockWorld.writes.Clear(); $MockWorld.emails.Clear(); $MockWorld.texts.Clear(); $MockWorld.twilioFail = 0; $MockWorld.postmarkFail = 0
    $s = @{}; foreach ($k in $MockPsaSecrets[$Psa].Keys) { $s[$k] = $MockPsaSecrets[$Psa][$k] }
    foreach ($k in $MockShared.Keys) { $s[$k] = $MockShared[$k] }
    if (-not $Twilio) { foreach ($k in @('Twilio-AccountSid', 'Twilio-AuthToken', 'Twilio-FromNumber')) { $s.Remove($k) } }
    if (-not $Postmark) { foreach ($k in @('Postmark-ServerToken', 'Postmark-FromEmail')) { $s.Remove($k) } }
    if ($Key -ne 'default') { if ($Key) { $s['VerifyCaller-Key'] = $Key } else { $s.Remove('VerifyCaller-Key') } }
    $MockWorld.secrets = $s
    $MockWorld.contact = $(if ($NoContact) { $null } else { @{ id = 77; first = 'Megan'; last = 'Bowen'; email = $(if ($NoEmail) { '' } else { 'megan.bowen@contoso.example' }); mobile = $Mobile; inactive = [bool]$Inactive } })
    $MockWorld.ticket = @{ id = 301; summary = 'Password reset request'; notes = (New-Object System.Collections.ArrayList) }
    $null = $MockWorld.ticket.notes.Add(@{ id = ($MockWorld.next++); text = 'Caller says they are Megan and need a password reset.'; created = (Get-Date).ToUniversalTime().AddMinutes(-30); client = $true; internal = $false })
}
function Add-WorldNote {
    param($Id, [string]$Text, [bool]$Internal)
    if ([string]$Id -ne '301') { New-HttpError 404 'no such ticket' }
    $null = $MockWorld.ticket.notes.Add(@{ id = ($MockWorld.next++); text = $Text; created = (Get-Date).ToUniversalTime(); client = $false; internal = $Internal })
}
function Get-WorldNotes { return @($MockWorld.ticket.notes | ForEach-Object { $_.text }) }

# Like the real cmdlet, a JSON array reply is handed back as ONE object (", @(...)"), not item by item.
function Invoke-RestMethod {
    [CmdletBinding()] param($Method = 'GET', $Uri, $Headers, $Body, $ContentType, $Form, [int]$MaximumRedirection = -1)
    $m = ([string]$Method).ToUpperInvariant(); $u = [string]$Uri
    $b = if ($Body -is [string] -and $Body -and [string]$ContentType -like '*json*') { $Body | ConvertFrom-Json -NoEnumerate } else { $null }
    $isAuth = $u -match '/auth/token$|/security/authenticate$'
    if ($m -ne 'GET' -and -not $isAuth) { $null = $MockWorld.writes.Add([pscustomobject]@{ Method = $m; Uri = $u; Body = $b; Raw = [string]$Body }) }
    if ($u -eq 'https://api.postmarkapp.com/email') {
        if ($MockWorld.postmarkFail) { New-HttpError $MockWorld.postmarkFail '{"ErrorCode":300,"Message":"Invalid email request"}' }
        $null = $MockWorld.emails.Add([pscustomobject]@{ To = $b.To; Subject = $b.Subject; Text = $b.TextBody }); return [pscustomobject]@{ ErrorCode = 0; MessageID = 'pm-1' }
    }
    if ($u -like 'https://api.twilio.com/2010-04-01/Accounts/*/Messages.json') {
        if ($MockWorld.twilioFail) { New-HttpError $MockWorld.twilioFail '{"code":21211,"message":"The To number is not a valid phone number."}' }
        $q = Get-Query "?$Body"; $null = $MockWorld.texts.Add([pscustomobject]@{ To = $q['To']; From = $q['From']; Text = $q['Body']; Auth = [string]$Headers.Authorization }); return [pscustomobject]@{ sid = 'SM1' }
    }
    $api = if ($MockBase.Contains($MockWorld.psa)) { $MockBase[$MockWorld.psa] } else { '' }
    $t = $MockWorld.ticket; $c = $MockWorld.contact
    switch ($MockWorld.psa) {
        'connectwise' {
            if ($m -eq 'GET' -and $u -match '/service/tickets/(\d+)/notes') {
                if ($Matches[1] -ne '301') { return , @() }
                $q = Get-Query $u; if ([int]$q['page'] -gt 1) { return , @() }
                return , @($t.notes | ForEach-Object { $o = [ordered]@{ id = $_.id; text = $_.text; dateCreated = (Get-Iso $_.created); internalAnalysisFlag = $_.internal; detailDescriptionFlag = (-not $_.internal) }; if ($_.client) { $o.contact = [pscustomobject]@{ id = 77 } } else { $o.member = [pscustomobject]@{ identifier = 'jlee' } }; [pscustomobject]$o })
            }
            if ($m -eq 'POST' -and $u -match '/service/tickets/(\d+)/notes$') { Add-WorldNote $Matches[1] $b.text ([bool]$b.internalAnalysisFlag); return [pscustomobject]@{ id = $MockWorld.next } }
            if ($m -eq 'GET' -and $u -match '/service/tickets/(\d+)$') {
                if ($Matches[1] -ne '301') { New-HttpError 404 '{"code":"NotFound","message":"Ticket not found"}' }
                $o = [ordered]@{ id = 301; summary = $t.summary; company = [pscustomobject]@{ id = 42; name = 'Contoso' }; status = [pscustomobject]@{ name = 'New' }; contactEmailAddress = 'attacker@fabrikam.example' }
                if ($c) { $o.contact = [pscustomobject]@{ id = $c.id; name = "$($c.first) $($c.last)" } }
                return [pscustomobject]$o
            }
            if ($m -eq 'GET' -and $u -match '/company/contacts/(\d+)$') {
                $items = @(); if ($c.email) { $items += [pscustomobject]@{ type = [pscustomobject]@{ id = 1; name = 'Email' }; value = $c.email; defaultFlag = $true; communicationType = 'Email' } }
                $items += [pscustomobject]@{ type = [pscustomobject]@{ id = 2; name = 'Direct' }; value = '5550109999'; defaultFlag = $true; communicationType = 'Phone' }
                if ($c.mobile) { $items += [pscustomobject]@{ type = [pscustomobject]@{ id = 4; name = 'Mobile' }; value = $c.mobile; defaultFlag = $false; communicationType = 'Phone' } }
                return [pscustomobject]@{ id = $c.id; firstName = $c.first; lastName = $c.last; inactiveFlag = $c.inactive; communicationItems = $items }
            }
        }
        'autotask' {
            if ($m -eq 'GET' -and $u -like "$api/TicketNotes/entityInformation/fields") {
                return [pscustomobject]@{ fields = @(
                        [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                        [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) }
            }
            if ($m -eq 'GET' -and $u.StartsWith("$api/TicketNotes/query?")) {
                return [pscustomobject]@{ items = @($t.notes | ForEach-Object { [pscustomobject]@{ id = $_.id; description = $_.text; createDateTime = (Get-Iso $_.created); publish = $(if ($_.internal) { 2 } else { 1 }); createdByContactID = $(if ($_.client) { 77 } else { $null }); creatorResourceID = $(if ($_.client) { $null } else { 29682885 }) } }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } }
            }
            if ($m -eq 'GET' -and $u -match '/Tickets/(\d+)$') {
                if ($Matches[1] -ne '301') { New-HttpError 404 '{"errors":["not found"]}' }
                return [pscustomobject]@{ item = [pscustomobject]@{ id = 301; title = $t.summary; description = 'Password reset.'; companyID = 42; status = 1; contactID = $(if ($c) { $c.id } else { $null }) } }
            }
            if ($m -eq 'GET' -and $u -match '/Contacts/(\d+)$') { return [pscustomobject]@{ item = [pscustomobject]@{ id = $c.id; firstName = $c.first; lastName = $c.last; emailAddress = $c.email; mobilePhone = $c.mobile; phone = '5550109999'; isActive = $(if ($c.inactive) { 0 } else { 1 }) } } }
            if ($m -eq 'POST' -and $u -match '/Tickets/(\d+)/Notes$') { Add-WorldNote $Matches[1] $b.description ([int]$b.publish -eq 2); return [pscustomobject]@{ itemId = $MockWorld.next } }
        }
        'halopsa' {
            if ($u -eq 'https://halo.example.com/auth/token') { return [pscustomobject]@{ access_token = 'halo-token' } }
            if ($m -eq 'GET' -and $u -match '/api/Tickets/(\d+)\?includedetails') {
                if ($Matches[1] -ne '301') { New-HttpError 404 'not found' }
                return [pscustomobject]@{ id = 301; summary = $t.summary; details = 'Password reset.'; client_id = 42; client_name = 'Contoso'; status_id = 1; user_id = $(if ($c) { $c.id } else { 0 }); user_emailaddress = 'attacker@fabrikam.example' }
            }
            if ($m -eq 'GET' -and $u.StartsWith("$api/Actions?")) { return [pscustomobject]@{ actions = @($t.notes | ForEach-Object { [pscustomobject]@{ id = $_.id; note = $_.text; datetime = (Get-Iso $_.created); hiddenfromuser = $_.internal; who_type = $(if ($_.client) { 2 } else { 1 }); who = 'J Lee' } }) } }
            if ($m -eq 'GET' -and $u -match '/api/Users/(\d+)$') { return [pscustomobject]@{ id = $c.id; name = "$($c.first) $($c.last)"; emailaddress = $c.email; mobilenumber = $c.mobile; phonenumber = '5550109999'; inactive = $c.inactive } }
            if ($m -eq 'POST' -and $u -eq "$api/Actions") { Add-WorldNote $b[0].ticket_id $b[0].note ([bool]$b[0].hiddenfromuser); return , @([pscustomobject]@{ id = 1 }) }
        }
        'kaseyabms' {
            if ($u -eq 'https://bms.example.com/v2/security/authenticate') { return [pscustomobject]@{ Result = [pscustomobject]@{ AccessToken = 'bms-token' } } }
        }
    }
    throw "Mock has no route for $m $u"
}

# ---- running the shipped step ----
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
function Get-ThrowMessage { param([scriptblock]$Body) try { $null = & $Body; return '' } catch { return [string]$_.Exception.Message } }
function Get-Writes { param([string]$Like = '*') return @($MockWorld.writes | Where-Object { "$($_.Method) $($_.Uri)" -like $Like }) }
function Complete-Test { Write-Host "$($MockTally.pass) passed, $($MockTally.fail) failed"; if ($MockTally.fail) { exit 1 }; exit 0 }
