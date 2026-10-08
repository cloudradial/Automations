# Strict-mode harness for SLA Breach Report.
# Runs each PowerShell step exactly as it is in sla-breach-report.yml (shared libraries and psa-extra.ps1
# included), through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the runner
# Key Vault, Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked. Outputs pass through JSON between
# steps, as the runner does. Placeholder data only (Contoso, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a same-named step variable
# would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File automationai/sla-breach-report/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in automationai/_shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

# ---- psa-extra.ps1 on its own, all six PSAs ----
& (Get-Command pwsh).Source -NoProfile -File (Join-Path $PSScriptRoot 'test-psa-extra.ps1') | Out-Host
Check 'psa-extra.ps1 unit tests (six PSAs) pass' ($LASTEXITCODE -eq 0)

# ---- the steps, straight from the built workflow ----
$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\sla-breach-report.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.type==='powershell-script')o[a.id]={s:a.properties.script,p:a.properties.parameters};}console.log(JSON.stringify(o));"
$TSteps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow has find and send steps, both unbound (Routine)' ($TSteps.Contains('find') -and $TSteps.Contains('send') -and -not @($TSteps.Values | Where-Object { @($_.p).Count }).Count)

# ---- runner mocks ----
$global:NodeIn = $null; $global:NodeOut = $null
function Get-NodeInput { param([string]$Name) return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Invoke-Step {
    param([string]$Id, $In = $null)
    $global:NodeIn = $In; $global:NodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $TSteps[$Id].s)) } catch { $err = [string]$_.Exception.Message }
    $o = $null; if ($null -ne $global:NodeOut) { $o = ($global:NodeOut | ConvertTo-Json -Depth 12 | ConvertFrom-Json) }
    return @{ out = $o; error = $err }
}
function Invoke-Flow {
    param($Body)
    $TIn = if ($null -eq $Body) { $null } else { $Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json }
    $f = Invoke-Step 'find' $TIn
    if ($f.error) { return @{ stage = 'find'; out = $f.out; error = $f.error } }
    $s = Invoke-Step 'send' $f.out
    return @{ stage = 'send'; out = $s.out; error = $s.error; find = $f.out }
}
function Get-TWrites { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and $_.Uri -notlike '*postmarkapp*' -and $_.Uri -notlike '*/auth/token' -and $_.Uri -notlike '*/security/authenticate' }) }
function Get-TPostmark { return @($Mock.Calls | Where-Object { $_.Uri -like 'https://api.postmarkapp.com/email' }) }

# ---- placeholder data ----
$TPostmark = @{ 'Postmark-ServerToken' = 'pm-token'; 'Postmark-FromEmail' = 'alerts@example.com' }
$TPsa = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://cw.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    halopsa     = @{ 'PSA-Type' = 'halopsa'; 'Halo-ApiUrl' = 'https://halo.example.com'; 'Halo-ClientId' = 'id'; 'Halo-ClientSecret' = 'sec' }
    kaseyabms   = @{ 'PSA-Type' = 'kaseyabms'; 'KaseyaBMS-ApiUrl' = 'https://bms.example.com'; 'KaseyaBMS-Username' = 'api'; 'KaseyaBMS-Password' = 'pw'; 'KaseyaBMS-CompanyName' = 'examplemsp' }
    syncro      = @{ 'PSA-Type' = 'syncro'; 'Syncro-ApiUrl' = 'https://example.syncromsp.com/api/v1'; 'Syncro-ApiKey' = 'key' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
}
function Get-TSecrets { param([string]$P, [switch]$NoPostmark) $s = @{}; foreach ($k in $TPsa[$P].Keys) { $s[$k] = $TPsa[$P][$k] }; if (-not $NoPostmark) { foreach ($k in $TPostmark.Keys) { $s[$k] = $TPostmark[$k] } }; return $s }
function Get-TAgo { param([double]$Hours) return [datetime]::UtcNow.AddHours(-$Hours).ToString('yyyy-MM-ddTHH:mm:ssZ') }
$TBody = @{ to = 'service.manager@example.com' }

# ConnectWise: A breaches its SLA respond target (2h for priority 2, 3h old), B is near its default 24h target
# (20h old, medium), C is fine (low, 2h old), D waits on the client (skipped), E is near its SLA resolve target.
$TCwTickets = @(
    [pscustomobject]@{ id = 1001; summary = 'Server down'; company = [pscustomobject]@{ id = 5; name = 'Contoso Ltd' }; status = [pscustomobject]@{ name = 'New' }; priority = [pscustomobject]@{ id = 2; name = 'Priority 2 - Quick Response' }; board = [pscustomobject]@{ id = 1; name = 'Service Desk' }; owner = [pscustomobject]@{ id = 7; identifier = 'jlee'; name = 'Jordan Lee' }; sla = [pscustomobject]@{ id = 5 }; dateResponded = $null; _info = [pscustomobject]@{ dateEntered = (Get-TAgo 3); lastUpdated = (Get-TAgo 3) } }
    [pscustomobject]@{ id = 1002; summary = 'Printer <offline> & jammed'; company = [pscustomobject]@{ id = 5; name = 'Contoso Ltd' }; status = [pscustomobject]@{ name = 'In Progress' }; priority = [pscustomobject]@{ id = 3; name = 'Priority 3 - Normal Response' }; board = [pscustomobject]@{ id = 1; name = 'Service Desk' }; owner = [pscustomobject]@{ id = 8; identifier = 'spatel'; name = 'Sam Patel' }; _info = [pscustomobject]@{ dateEntered = (Get-TAgo 20); lastUpdated = (Get-TAgo 2) } }
    [pscustomobject]@{ id = 1003; summary = 'New mouse'; company = [pscustomobject]@{ id = 6; name = 'Example MSP' }; status = [pscustomobject]@{ name = 'New' }; priority = [pscustomobject]@{ id = 4; name = 'Priority 4 - Low' }; board = [pscustomobject]@{ id = 1; name = 'Service Desk' }; _info = [pscustomobject]@{ dateEntered = (Get-TAgo 2); lastUpdated = (Get-TAgo 2) } }
    [pscustomobject]@{ id = 1004; summary = 'Waiting on quote'; company = [pscustomobject]@{ id = 6; name = 'Example MSP' }; status = [pscustomobject]@{ name = 'Waiting on Client' }; priority = [pscustomobject]@{ id = 1; name = 'Priority 1 - Emergency Response' }; _info = [pscustomobject]@{ dateEntered = (Get-TAgo 100); lastUpdated = (Get-TAgo 50) } }
    [pscustomobject]@{ id = 1005; summary = 'VPN slow'; company = [pscustomobject]@{ id = 6; name = 'Example MSP' }; status = [pscustomobject]@{ name = 'In Progress' }; priority = [pscustomobject]@{ id = 2; name = 'Priority 2 - Quick Response' }; owner = [pscustomobject]@{ id = 7; identifier = 'jlee'; name = 'Jordan Lee' }; sla = [pscustomobject]@{ id = 5 }; dateResponded = (Get-TAgo 6); _info = [pscustomobject]@{ dateEntered = (Get-TAgo 7); lastUpdated = (Get-TAgo 1) } }
)
$global:TCw = @{ tickets = $TCwTickets; fail = 0; pm = 0 }
$TCwHandler = { param($c, $n)
    if ($c.Uri -like 'https://api.postmarkapp.com/email') { if ($global:TCw.pm) { New-HttpError $global:TCw.pm '{"ErrorCode":10,"Message":"Bad or missing Server API token."}' }; return [pscustomobject]@{ ErrorCode = 0; MessageID = 'm1' } }
    if ($c.Uri -like '*/service/tickets[?]*') { if ($global:TCw.fail) { New-HttpError $global:TCw.fail '{"message":"denied"}' }; return @($global:TCw.tickets) }
    if ($c.Uri -like '*/company/companies*') { if ([uri]::UnescapeDataString($c.Uri) -match 'name="Contoso Ltd"') { return @([pscustomobject]@{ id = 5; name = 'Contoso Ltd' }) }; return @() }
    if ($c.Uri -like '*/service/SLAs/5/priorities*') { return @([pscustomobject]@{ priority = [pscustomobject]@{ id = 2 }; respondHours = 2; resolutionHours = 8 }) }
    if ($c.Uri -like '*/service/SLAs/5') { return [pscustomobject]@{ id = 5; respondHours = 4; resolutionHours = 24 } }
    throw "unmocked $($c.Method) $($c.Uri)"
}

# ---- 1. ConnectWise, Postmark set ----
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow $TBody
Check 'CW: run succeeds' ($TR.stage -eq 'send' -and -not $TR.error -and $TR.out.status -eq 'success') "$($TR.error) $($TR.out | ConvertTo-Json -Depth 3 -Compress)"
Check 'CW: 1 breached (PSA SLA respond target), 2 near breach, 1 skipped' ($TR.find.counts.breached -eq 1 -and $TR.find.counts.nearBreach -eq 2 -and $TR.find.counts.skipped -eq 1 -and $TR.find.counts.psaSla -eq 2 -and $TR.find.counts.defaultHours -eq 1) ($TR.find.counts | ConvertTo-Json -Compress)
$TA = @($TR.out.tickets | Where-Object { $_.id -eq '1001' })[0]
Check 'CW: breached row carries the SLA source and target kind' ($TA.state -eq 'breached' -and $TA.slaSource -eq 'PSA SLA' -and $TA.targetKind -eq 'respond' -and $TA.company -eq 'Contoso Ltd' -and $TA.technician -eq 'Jordan Lee') ($TA | ConvertTo-Json -Compress)
Check 'CW: report-only, no PSA writes' (@(Get-TWrites).Count -eq 0) ((Get-TWrites | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')
$TPm = @(Get-TPostmark)
$TPmBody = if ($TPm.Count) { $TPm[0].Body | ConvertFrom-Json } else { $null }
Check 'CW: one Postmark email to the service manager with the server token header' ($TPm.Count -eq 1 -and $TPmBody.To -eq 'service.manager@example.com' -and $TPmBody.From -eq 'alerts@example.com' -and $TPm[0].Headers['X-Postmark-Server-Token'] -eq 'pm-token' -and $TPmBody.MessageStream -eq 'outbound') (Show-Calls)
Check 'CW: HTML grouped by company then technician, HTML-escaped' ($TPmBody.HtmlBody -match '<h2[^>]*>Contoso Ltd \(2 tickets\)</h2>' -and $TPmBody.HtmlBody -match '<h2[^>]*>Example MSP \(1 ticket\)</h2>' -and $TPmBody.HtmlBody -match '<h3[^>]*>Jordan Lee</h3>' -and $TPmBody.HtmlBody -match 'Printer &lt;offline&gt; &amp; jammed' -and $TPmBody.HtmlBody.IndexOf('Contoso Ltd') -lt $TPmBody.HtmlBody.IndexOf('Example MSP (')) ''
Check 'CW: subject and plain message' ($TPmBody.Subject -eq 'SLA breach report: 1 breached, 2 near breach' -and $TR.out.email_sent -eq $true -and $TR.out.message -match '^1 open ticket has breached SLA and 2 are close to it \(80% or more of the time used\), out of 4 open tickets checked\.') $TR.out.message
Check 'CW: output contract fields' ($null -ne $TR.out.PSObject.Properties['public_note'] -and $null -ne $TR.out.PSObject.Properties['internal_note'] -and $null -ne $TR.out.PSObject.Properties['ticket_id'] -and @($TR.out.actions).Count -ge 2) ''
Check 'CW: no em dashes in the email' ($TPmBody.HtmlBody -notmatch [char]0x2014) ''

# ---- 2. Routine with no input: defaults, no "to", output only ----
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow $null
Check 'No input (Routine): defaults work, report kept in output, warning says why' ($TR.out.status -eq 'success' -and $TR.out.email_sent -eq $false -and @(Get-TPostmark).Count -eq 0 -and @($TR.out.warnings) -match 'No "to" address' -and $TR.out.html -match 'SLA breach report') ($TR.out.warnings -join ' | ')

$TS2 = Get-TSecrets connectwise; $TS2['ServiceManager-Email'] = 'service.manager@example.com'
Reset-Mock -Secrets $TS2 -Handler $TCwHandler
$TR = Invoke-Flow $null
Check 'No input (Routine) with the ServiceManager-Email secret: emailed to it' ($TR.out.status -eq 'success' -and $TR.out.email_sent -eq $true -and ((@(Get-TPostmark))[0].Body | ConvertFrom-Json).To -eq 'service.manager@example.com') ($TR.out.warnings -join ' | ')

# ---- 3. Custom thresholds ----
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow @{ to = 'a@example.com; b@example.com'; near_breach_percent = 95; sla_hours_by_priority = '{"medium":12}'; use_psa_sla = 'false' }
Check 'Custom thresholds: medium 12h breaches B, PSA SLA ignored, two recipients' ($TR.find.counts.breached -ge 1 -and @($TR.out.tickets | Where-Object { $_.id -eq '1002' -and $_.state -eq 'breached' -and $_.slaSource -eq 'Default hours' }).Count -eq 1 -and $TR.find.counts.psaSla -eq 0 -and (@(Get-TPostmark)[0].Body | ConvertFrom-Json).To -eq 'a@example.com,b@example.com') ($TR.find.counts | ConvertTo-Json -Compress)

# ---- 3b. company input: only that client's tickets ----
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow ($TBody + @{ company = '5' })
$TU = [uri]::UnescapeDataString((Get-Calls GET '*/service/tickets[?]*')[0].Uri)
Check 'company=5 (id): filter sent to the PSA; only Contoso rows, even though the mock returned every company' ($TR.out.status -eq 'success' -and $TU -match 'company/id=5' -and @($TR.out.tickets).Count -eq 2 -and -not @($TR.out.tickets | Where-Object { $_.company -ne 'Contoso Ltd' }).Count -and $TR.find.companyId -eq '5') "$TU | $(($TR.out.tickets | ForEach-Object { $_.company }) -join ',')"
Check 'company=5: the message and subject name the scope' ($TR.find.message -match 'checked for company 5\.' -and ((@(Get-TPostmark))[0].Body | ConvertFrom-Json).Subject -match '^SLA breach report for company 5: ') $TR.find.message
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow ($TBody + @{ company = 'Contoso Ltd' })
Check 'company by exact name: looked up, then only that company' ($TR.out.status -eq 'success' -and $TR.find.companyId -eq '5' -and $TR.find.companyName -eq 'Contoso Ltd' -and @($TR.out.tickets).Count -eq 2 -and ((@(Get-TPostmark))[0].Body | ConvertFrom-Json).Subject -match '^SLA breach report for Contoso Ltd: ') "$($TR.error) $($TR.out.message)"
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow ($TBody + @{ company = 'Nobody Inc' })
Check 'unknown company name: rejected before any ticket is read' ($TR.stage -eq 'find' -and $TR.out.status -eq 'rejected' -and $TR.out.message -match "has no company named 'Nobody Inc'" -and @(Get-Calls GET '*/service/tickets*').Count -eq 0) $TR.out.message

# ---- 4. Empty result ----
$global:TCw.tickets = @()
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow $TBody
Check 'Empty: success, all-clear message, all-clear email still sent' ($TR.out.status -eq 'success' -and $TR.out.message -match '^No open tickets have breached' -and (@(Get-TPostmark)[0].Body | ConvertFrom-Json).HtmlBody -match 'Nothing needs attention') $TR.out.message
$global:TCw.tickets = $TCwTickets

# ---- 5. Missing permission (403) ----
$global:TCw.fail = 403
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow $TBody
Check '403: stops at find with a plain sentence naming the permission' ($TR.stage -eq 'find' -and $TR.out.status -eq 'error' -and $TR.out.message -match 'refused to list tickets \(HTTP 403\)\. Give the API user permission to read service tickets' -and @(Get-TPostmark).Count -eq 0) $TR.out.message
$global:TCw.fail = 0

# ---- 6. Postmark refuses ----
$global:TCw.pm = 401
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow $TBody
Check 'Postmark 401: incomplete, report kept in output, plain warning' ($TR.out.status -eq 'incomplete' -and $TR.out.email_sent -eq $false -and @($TR.out.warnings) -match 'Postmark refused the email \(HTTP 401\)' -and $TR.out.html) ($TR.out.warnings -join ' | ')
$global:TCw.pm = 0

# ---- 7. Invalid input and no PSA ----
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow @{ near_breach_percent = 150 }
Check 'Invalid near_breach_percent: rejected, nothing read' ($TR.out.status -eq 'rejected' -and $TR.out.message -match 'near_breach_percent must be a number from 1 to 100' -and $Mock.Calls.Count -eq 0) $TR.out.message
$TR = Invoke-Flow @{ sla_hours_by_priority = '{"someday":3}' }
Check 'Invalid sla_hours_by_priority key: rejected' ($TR.out.status -eq 'rejected' -and $TR.out.message -match "Priority 'someday' isn't one of") $TR.out.message
$TR = Invoke-Flow @{ to = 'not-an-address' }
Check 'Invalid to: rejected' ($TR.out.status -eq 'rejected' -and $TR.out.message -match "isn't an email address") $TR.out.message
Reset-Mock -Secrets $TPostmark
$TR = Invoke-Flow $TBody
Check 'No PSA set up: error naming the PSA-Type secret' ($TR.out.status -eq 'error' -and $TR.out.message -match 'PSA-Type') $TR.out.message

# ---- 8. Autotask, no Postmark secrets ----
$TAtFields = [pscustomobject]@{ fields = @(
        [pscustomobject]@{ name = 'status'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'New'; isActive = $true }, [pscustomobject]@{ value = '5'; label = 'Complete'; isActive = $true }, [pscustomobject]@{ value = '7'; label = 'Waiting Customer'; isActive = $true }) }
        [pscustomobject]@{ name = 'priority'; picklistValues = @([pscustomobject]@{ value = '4'; label = 'Critical'; isActive = $true }, [pscustomobject]@{ value = '1'; label = 'High'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Medium'; isActive = $true }, [pscustomobject]@{ value = '3'; label = 'Low'; isActive = $true }) }
        [pscustomobject]@{ name = 'queueID'; picklistValues = @([pscustomobject]@{ value = '29683'; label = 'Service Desk'; isActive = $true }) }
    )
}
Reset-Mock -Secrets (Get-TSecrets autotask -NoPostmark) -Handler { param($c, $n)
    if ($c.Uri -like '*/Tickets/entityInformation/fields') { return $TAtFields }
    if ($c.Uri -like '*/Tickets/query?*') {
        return [pscustomobject]@{ pageDetails = [pscustomobject]@{ nextPageUrl = $null }; items = @(
                [pscustomobject]@{ id = 501; ticketNumber = 'T20261008.0001'; title = 'VPN down'; companyID = 42; status = 1; priority = 4; queueID = 29683; assignedResourceID = 29682885; createDate = (Get-TAgo 3); lastActivityDate = (Get-TAgo 3); firstResponseDueDateTime = (Get-TAgo 1); firstResponseDateTime = $null }
                [pscustomobject]@{ id = 502; ticketNumber = 'T20261008.0002'; title = 'Outlook crash'; companyID = 42; status = 1; priority = 1; queueID = 29683; assignedResourceID = $null; createDate = (Get-TAgo 7); lastActivityDate = (Get-TAgo 7) }
                [pscustomobject]@{ id = 503; ticketNumber = 'T20261008.0003'; title = 'Quote'; companyID = 42; status = 7; priority = 4; queueID = 29683; createDate = (Get-TAgo 90); lastActivityDate = (Get-TAgo 90) }
                [pscustomobject]@{ id = 504; ticketNumber = 'T20261008.0004'; title = 'New starter'; companyID = 43; status = 1; priority = 3; queueID = 29683; createDate = (Get-TAgo 1); lastActivityDate = (Get-TAgo 1); resolvedDueDateTime = (Get-TAgo -240) }
            )
        }
    }
    if ($c.Uri -like '*/Companies/42') { return [pscustomobject]@{ item = [pscustomobject]@{ companyName = 'Contoso Ltd' } } }
    if ($c.Uri -like '*/Companies/43') { return [pscustomobject]@{ item = [pscustomobject]@{ companyName = 'Example MSP' } } }
    if ($c.Uri -like '*/Resources/29682885') { return [pscustomobject]@{ item = [pscustomobject]@{ firstName = 'Jordan'; lastName = 'Lee' } } }
    throw "unmocked $($c.Method) $($c.Uri)"
}
$TR = Invoke-Flow $TBody
Check 'AT: first-response due breach + default-hours near breach, waiting skipped' ($TR.out.status -eq 'success' -and $TR.find.counts.breached -eq 1 -and $TR.find.counts.nearBreach -eq 1 -and $TR.find.counts.skipped -eq 1 -and @($TR.out.tickets | Where-Object { $_.number -eq 'T20261008.0002' -and $_.technician -eq 'Unassigned' -and $_.slaSource -eq 'Default hours' }).Count -eq 1) ($TR.find.counts | ConvertTo-Json -Compress)
Check 'AT: no Postmark secrets, output only with a plain warning; no writes' ($TR.out.email_sent -eq $false -and @($TR.out.warnings) -match 'Postmark is not set up' -and @(Get-TWrites).Count -eq 0 -and @(Get-TPostmark).Count -eq 0) ($TR.out.warnings -join ' | ')

# ---- 9. HaloPSA, Kaseya BMS, Syncro, Zendesk (read paths, one breach each) ----
$TOthers = @(
    @{ psa = 'halopsa'; handler = { param($c, $n)
            if ($c.Uri -like 'https://api.postmarkapp.com/email') { return [pscustomobject]@{ ErrorCode = 0 } }
            if ($c.Uri -like '*/auth/token') { return [pscustomobject]@{ access_token = 'tok' } }
            if ($c.Uri -like '*/api/Tickets?*') { return [pscustomobject]@{ record_count = 2; tickets = @(
                        [pscustomobject]@{ id = 101; summary = 'Email bouncing'; client_id = 12; client_name = 'Contoso Ltd'; status_id = 2; priority_id = 1; team = 'Service Desk'; agent_id = 3; agent_name = 'Jordan Lee'; dateoccurred = (Get-TAgo 5); lastactiondate = (Get-TAgo 5); respondbydate = '1900-01-01T00:00:00'; fixbydate = '1900-01-01T00:00:00'; responsedate = '1900-01-01T00:00:00' }
                        [pscustomobject]@{ id = 102; summary = 'Slow PC'; client_id = 12; client_name = 'Contoso Ltd'; status_id = 2; priority_id = 3; team = 'Service Desk'; agent_id = 3; agent_name = 'Jordan Lee'; dateoccurred = (Get-TAgo 3); lastactiondate = (Get-TAgo 3); respondbydate = (Get-TAgo -0.5); responsedate = '1900-01-01T00:00:00' }) }
            }
            throw "unmocked $($c.Method) $($c.Uri)" }; breached = 1; near = 1
    }
    @{ psa = 'kaseyabms'; handler = { param($c, $n)
            if ($c.Uri -like 'https://api.postmarkapp.com/email') { return [pscustomobject]@{ ErrorCode = 0 } }
            if ($c.Uri -like '*/v2/security/authenticate') { return [pscustomobject]@{ Success = $true; Result = [pscustomobject]@{ AccessToken = 'tok' } } }
            if ($c.Uri -like '*/v2/servicedesk/tickets?*') { return [pscustomobject]@{ Success = $true; Result = @([pscustomobject]@{ Id = 900; TicketNumber = 'BMS-900'; Title = 'Laptop slow'; AccountId = 4; AccountName = 'Contoso Ltd'; StatusName = 'New'; PriorityName = 'High'; AssigneeId = 8; AssigneeName = 'Jordan Lee'; OpenDate = (Get-TAgo 9); DueDate = (Get-TAgo 1) }, [pscustomobject]@{ Id = 901; Title = 'Done'; StatusName = 'Completed'; OpenDate = (Get-TAgo 30) }) } }
            throw "unmocked $($c.Method) $($c.Uri)" }; breached = 1; near = 0
    }
    @{ psa = 'syncro'; handler = { param($c, $n)
            if ($c.Uri -like 'https://api.postmarkapp.com/email') { return [pscustomobject]@{ ErrorCode = 0 } }
            if ($c.Uri -like '*/tickets[?]*') { return [pscustomobject]@{ tickets = @([pscustomobject]@{ id = 77; number = 1077; subject = 'Backup failed'; customer_id = 9; customer_business_then_name = 'Contoso Ltd'; status = 'New'; priority = '1 High'; user_id = 5; user = [pscustomobject]@{ full_name = 'Jordan Lee' }; created_at = (Get-TAgo 10); updated_at = (Get-TAgo 5); due_date = (Get-TAgo 1) }); meta = [pscustomobject]@{ total_pages = 1 } } }
            throw "unmocked $($c.Method) $($c.Uri)" }; breached = 1; near = 0
    }
    @{ psa = 'zendesk'; handler = { param($c, $n)
            if ($c.Uri -like 'https://api.postmarkapp.com/email') { return [pscustomobject]@{ ErrorCode = 0 } }
            if ($c.Uri -like '*/search?*') { return [pscustomobject]@{ next_page = $null; results = @(
                        [pscustomobject]@{ id = 3001; subject = 'Cannot log in'; organization_id = 61; status = 'open'; priority = 'urgent'; group_id = 21; assignee_id = 71; created_at = (Get-TAgo 3); updated_at = (Get-TAgo 2); slas = [pscustomobject]@{ policy_metrics = @([pscustomobject]@{ metric = 'first_reply_time'; stage = 'active'; breach_at = (Get-TAgo 1) }) } }
                        [pscustomobject]@{ id = 3002; subject = 'Met already'; organization_id = 61; status = 'open'; priority = 'high'; created_at = (Get-TAgo 30); updated_at = (Get-TAgo 2); slas = [pscustomobject]@{ policy_metrics = @([pscustomobject]@{ metric = 'first_reply_time'; stage = 'achieved'; breach_at = $null }) } }
                        [pscustomobject]@{ id = 3003; subject = 'No SLA policy'; organization_id = 61; status = 'pending'; priority = 'normal'; created_at = (Get-TAgo 30); updated_at = (Get-TAgo 2) }
                        [pscustomobject]@{ id = 3004; subject = 'No SLA sideload'; organization_id = 61; status = 'open'; priority = 'normal'; created_at = (Get-TAgo 30); updated_at = (Get-TAgo 2) }) }
            }
            if ($c.Uri -like '*/tickets/3004?include=slas') { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 3004; slas = [pscustomobject]@{ policy_metrics = @() } } } }
            if ($c.Uri -like '*/organizations/61') { return [pscustomobject]@{ organization = [pscustomobject]@{ name = 'Contoso Ltd' } } }
            if ($c.Uri -like '*/users/71') { return [pscustomobject]@{ user = [pscustomobject]@{ name = 'Jordan Lee' } } }
            if ($c.Uri -like '*/groups/21') { return [pscustomobject]@{ group = [pscustomobject]@{ name = 'Service Desk' } } }
            throw "unmocked $($c.Method) $($c.Uri)" }; breached = 2; near = 0
    }
)
foreach ($TO in $TOthers) {
    Reset-Mock -Secrets (Get-TSecrets $TO.psa) -Handler $TO.handler
    $TR = Invoke-Flow $TBody
    Check "$($TO.psa): $($TO.breached) breached, $($TO.near) near, emailed, no writes" ($TR.out.status -eq 'success' -and $TR.find.counts.breached -eq $TO.breached -and $TR.find.counts.nearBreach -eq $TO.near -and $TR.out.email_sent -eq $true -and @(Get-TWrites).Count -eq 0) "$($TR.error) $($TR.find.counts | ConvertTo-Json -Compress) $(Show-Calls)"
}

Complete-Test
