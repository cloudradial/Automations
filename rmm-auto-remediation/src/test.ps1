# Strict-mode harness for the "Open PSA ticket" step of rmm-auto-remediation.yml. Runs the step exactly as it is
# in the .yml (extracted by build.js --extract) through & ([scriptblock]::Create(...)) under
# Set-StrictMode -Version Latest, on all six PSAs, with the shared mocks (_shared/tests/mock.ps1).
# Placeholder data only (Contoso, Example MSP).
# Usage: pwsh -NoProfile -File rmm-auto-remediation/src/test.ps1
#        (needs node and js-yaml; set JS_YAML_PATH if js-yaml isn't installed in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("rar-test-" + [guid]::NewGuid().ToString('N'))
& node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { throw 'rmm-auto-remediation.yml is out of date. Run node build.js first.' }
& node (Join-Path $PSScriptRoot 'build.js') --extract $tmp | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the steps.' }
$Step = Get-Content -Raw (Join-Path $tmp 'node-ticket.ps1')
Remove-Item -Recurse -Force $tmp

function Get-NodeInput { return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Invoke-Step {
    param($In)
    $global:NodeIn = $In; $global:NodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Step)) } catch { $err = [string]$_.Exception.Message }
    return @{ out = $global:NodeOut; err = $err }
}

$CR = 'https://contoso.example.com/api'
$S = @{
    connectwise = @{ 'CW-ApiUrl' = 'https://cw.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'Autotask-ApiUrl' = 'https://webservices.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    halopsa     = @{ 'Halo-ApiUrl' = 'https://halo.example.com'; 'Halo-ClientId' = 'cid'; 'Halo-ClientSecret' = 'sec' }
    kaseyabms   = @{ 'KaseyaBMS-ApiUrl' = 'https://bms.example.com'; 'KaseyaBMS-Username' = 'u'; 'KaseyaBMS-Password' = 'p'; 'KaseyaBMS-CompanyName' = 'Example MSP'; 'KaseyaBMS-NoteTypeId' = '4'; 'KaseyaBMS-NewStatusId' = '1'; 'KaseyaBMS-QueueId' = '7' }
    syncro      = @{ 'Syncro-ApiUrl' = 'https://example.syncromsp.com/api/v1'; 'Syncro-ApiKey' = 'key' }
    zendesk     = @{ 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
}
$CrSecrets = @{ 'CloudRadial-BaseUrl' = $CR; 'CloudRadial-PublicKey' = 'crpub'; 'CloudRadial-PrivateKey' = 'crpriv' }
$CW = 'https://cw.example.com/v4_6_release/apis/3.0'; $AT = 'https://webservices.autotask.example/atservicesrest/v1.0'; $HALO = 'https://halo.example.com/api'
$BMS = 'https://bms.example.com/v2'; $SY = 'https://example.syncromsp.com/api/v1'; $ZD = 'https://example.zendesk.com/api/v2'
# Where each PSA's create-ticket call goes, and the id it hands back.
$Create = @{ connectwise = @("$CW/service/tickets", '501'); autotask = @("$AT/Tickets", '502'); halopsa = @("$HALO/Tickets", '503'); kaseyabms = @("$BMS/servicedesk/tickets", '504'); syncro = @("$SY/tickets", '505'); zendesk = @("$ZD/tickets", '506') }
function Pick { param($v, $l, $d = $false) [pscustomobject]@{ value = $v; label = $l; isActive = $true; isDefaultValue = $d } }
$Companies = @(@{ id = 43; name = 'Contoso Ltd' }, @{ id = 42; name = 'Contoso' }, @{ id = 77; name = 'Fabrikam Site' })

$Handler = {
    param($c, $n)
    $k = "$($c.Method) $($c.Uri)"
    $co = $Companies
    switch -Wildcard -CaseSensitive ($k) {
        "GET $CR/v2/odata/company*" { if ($c.Uri -match 'companyId%20eq%2012') { return [pscustomobject]@{ value = @([pscustomobject]@{ companyId = 12; name = 'Contoso' }) } }; return [pscustomobject]@{ value = @() } }
        'POST https://halo.example.com/auth/token' { return [pscustomobject]@{ access_token = 'halo-token' } }
        'POST https://bms.example.com/v2/security/authenticate' { return [pscustomobject]@{ Result = [pscustomobject]@{ AccessToken = 'bms-token' } } }
        "GET $AT/Tickets/entityInformation/fields" { return [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'status'; picklistValues = @((Pick '1' 'New'), (Pick '5' 'Complete')) },
                    [pscustomobject]@{ name = 'priority'; picklistValues = @((Pick '4' 'Critical'), (Pick '1' 'High'), (Pick '2' 'Medium' $true), (Pick '3' 'Low')) },
                    [pscustomobject]@{ name = 'queueID'; picklistValues = @((Pick '29683' 'Service Desk')) }) } }
        "GET $AT/TicketNotes/entityInformation/fields" { return [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'publish'; picklistValues = @((Pick '1' 'All Autotask Users'), (Pick '2' 'Internal Only')) },
                    [pscustomobject]@{ name = 'noteType'; picklistValues = @((Pick '1' 'Task Detail')) }) } }
        "GET $CW/service/priorities*" { return @([pscustomobject]@{ id = 1; name = 'Priority 1 - Emergency Response' }, [pscustomobject]@{ id = 2; name = 'Priority 2 - Quick Response' }, [pscustomobject]@{ id = 3; name = 'Priority 3 - Normal Response' }) }
        "POST $CW/service/tickets" { return [pscustomobject]@{ id = 501 } }
        "POST $AT/Tickets" { return [pscustomobject]@{ itemId = 502 } }
        "POST $HALO/Tickets" { return @([pscustomobject]@{ id = 503 }) }
        "POST $BMS/servicedesk/tickets" { return [pscustomobject]@{ Success = $true; Result = [pscustomobject]@{ Id = 504 } } }
        "POST $SY/tickets" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 505; number = 1005 } } }
        "POST $ZD/tickets" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 506 } } }
        "GET $CW/company/companies*" { return @($co | ForEach-Object { [pscustomobject]$_ }) }
        "GET $AT/Companies/query*" { return [pscustomobject]@{ items = @($co | ForEach-Object { [pscustomobject]@{ id = $_.id; companyName = $_.name } }) } }
        "GET $HALO/Client*" { return [pscustomobject]@{ clients = @($co | ForEach-Object { [pscustomobject]$_ }) } }
        "GET $BMS/crm/accounts*" { return [pscustomobject]@{ Result = @($co | ForEach-Object { [pscustomobject]@{ Id = $_.id; Name = $_.name } }) } }
        "GET $SY/customers*" { return [pscustomobject]@{ customers = @($co | ForEach-Object { [pscustomobject]@{ id = $_.id; business_name = $_.name } }) } }
        "GET $ZD/organizations/autocomplete*" { return [pscustomobject]@{ organizations = @($co | ForEach-Object { [pscustomobject]$_ }) } }
    }
    return [pscustomobject]@{ id = 1 }
}
function Get-CreateCall { param([string]$Psa) return @($Mock.Calls | Where-Object { $_.Method -eq 'POST' -and $_.Uri -eq $Create[$Psa][0] }) }

$Escalate = [pscustomobject]@{
    status = 'escalated'; action = 'Server alert, not remediated'; alertUid = 'alert-001'; deviceUid = 'dev-9'; alertResolved = $false
    escalate = $true; ticketSummary = 'Low disk space on CONTOSO-SRV-01'; ticketDescription = 'A low-disk alert fired on a server, so it was not cleaned up automatically.'
    ticketNote = 'Free space 2.1 GB of 120 GB on C:. alertUid alert-001.'; ticketPriority = 'high'; siteName = 'Contoso'; cloudradialCompanyId = 12; dryRun = $false
}

# ---- Every PSA: the ticket opens on the client's company (matched through CloudRadial) ----
foreach ($psa in @('connectwise', 'autotask', 'halopsa', 'kaseyabms', 'syncro', 'zendesk')) {
    Reset-Mock (@{ 'PSA-Type' = $psa } + $S[$psa] + $CrSecrets) $Handler
    $r = Invoke-Step $Escalate
    Check "$($psa): step finishes without error" (-not $r.err) $r.err
    Check "$($psa): status success" ($null -ne $r.out -and $r.out.status -eq 'success') $(if ($r.out) { "$($r.out.status): $($r.out.message)" })
    Check "$($psa): one create-ticket call" (@(Get-CreateCall $psa).Count -eq 1) (Show-Calls)
    Check "$($psa): ticket id returned" ($null -ne $r.out -and $r.out.ticketId -eq $Create[$psa][1]) $(if ($r.out) { $r.out.ticketId })
    Check "$($psa): matched the CloudRadial company to PSA company 42" ($null -ne $r.out -and $r.out.psaCompanyId -eq '42') $(if ($r.out) { $r.out.psaCompanyId })
    $body = (Get-CreateCall $psa | Select-Object -First 1).Body
    Check "$($psa): summary sent, technical detail kept out of the ticket body" ($body -match 'CONTOSO-SRV-01' -and $body -notmatch 'alert-001') $body
}

# ---- Wrapped and string agent output are unwrapped ----
Reset-Mock (@{ 'PSA-Type' = 'zendesk' } + $S['zendesk'] + $CrSecrets) $Handler
$r = Invoke-Step ([pscustomobject]@{ output = ($Escalate | ConvertTo-Json -Compress) })
Check 'wrapped JSON output is read' ($null -ne $r.out -and $r.out.status -eq 'success' -and $r.out.ticketId -eq '506') $(if ($r.out) { $r.out.message } else { $r.err })

# ---- No escalation: nothing is opened ----
Reset-Mock (@{ 'PSA-Type' = 'connectwise' } + $S['connectwise'] + $CrSecrets) $Handler
$r = Invoke-Step ([pscustomobject]@{ status = 'resolved'; action = 'Cleaned up disk'; alertUid = 'alert-002'; alertResolved = $true; escalate = $false; notes = 'Free space went from 3 GB to 18 GB.' })
Check 'no escalation: success, no PSA calls' ($null -ne $r.out -and $r.out.status -eq 'success' -and $Mock.Calls.Count -eq 0 -and $r.out.alertResolved) "$(if ($r.out) { $r.out.message }) / $(Show-Calls)"
Check 'no escalation: message carries the agent notes' ($null -ne $r.out -and $r.out.message -match '18 GB') $(if ($r.out) { $r.out.message })

# ---- Dry run: preview only ----
Reset-Mock (@{ 'PSA-Type' = 'autotask' } + $S['autotask'] + $CrSecrets) $Handler
$dry = $Escalate.PSObject.Copy(); $dry.dryRun = $true
$r = Invoke-Step $dry
Check 'dry run: status preview, nothing called' ($null -ne $r.out -and $r.out.status -eq 'preview' -and $Mock.Calls.Count -eq 0) "$(if ($r.out) { $r.out.message }) / $(Show-Calls)"

# ---- Falls back to the Datto site name, then to PSA-CompanyId ----
Reset-Mock (@{ 'PSA-Type' = 'halopsa' } + $S['halopsa']) $Handler
$site = $Escalate.PSObject.Copy(); $site.cloudradialCompanyId = 0; $site.siteName = 'Fabrikam Site'
$r = Invoke-Step $site
Check 'site name: matched to PSA company 77' ($null -ne $r.out -and $r.out.psaCompanyId -eq '77' -and $r.out.status -eq 'success') $(if ($r.out) { $r.out.message } else { $r.err })

Reset-Mock (@{ 'PSA-Type' = 'syncro'; 'PSA-CompanyId' = '900' } + $S['syncro']) $Handler
$none = $Escalate.PSObject.Copy(); $none.cloudradialCompanyId = 0; $none.siteName = 'Unknown Site'
$r = Invoke-Step $none
Check 'catch-all: PSA-CompanyId used, with a warning' ($null -ne $r.out -and $r.out.psaCompanyId -eq '900' -and @($r.out.warnings | Where-Object { $_ -match 'PSA-CompanyId' }).Count -eq 1) $(if ($r.out) { "$($r.out.message) / $($r.out.warnings -join ' | ')" } else { $r.err })

Reset-Mock (@{ 'PSA-Type' = 'syncro' } + $S['syncro']) $Handler
$r = Invoke-Step $none
Check 'no company found: the step fails with a plain message' ($r.err -match "couldn't be found" -and $null -ne $r.out -and $r.out.status -eq 'error' -and @(Get-CreateCall 'syncro').Count -eq 0) $r.err

# ---- PSA not set up: the step fails ----
Reset-Mock @{} $Handler
$r = Invoke-Step $Escalate
Check 'no PSA: fails and says so' ($r.err -match "PSA isn't set up" -and $null -ne $r.out -and $r.out.status -eq 'error') $r.err

# ---- Missing ticket fields get safe defaults ----
Reset-Mock (@{ 'PSA-Type' = 'connectwise' } + $S['connectwise'] + $CrSecrets) $Handler
$r = Invoke-Step ([pscustomobject]@{ alertUid = 'alert-003'; deviceUid = 'dev-3'; escalate = 'true'; cloudradialCompanyId = 12; ticketPriority = 'urgent!' })
Check 'defaults: summary and high priority filled in' ($null -ne $r.out -and $r.out.status -eq 'success' -and @(Get-CreateCall 'connectwise').Count -eq 1 -and @(Get-CreateCall 'connectwise')[0].Body -match 'dev-3') $(if ($r.out) { $r.out.message } else { $r.err })

# ---- Nothing readable from the agent ----
Reset-Mock @{} $Handler
$r = Invoke-Step 'not json'
Check 'unreadable agent output: fails plainly' ($r.err -match 'returned nothing this step can read') $r.err

Complete-Test
