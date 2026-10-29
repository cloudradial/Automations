# Strict-mode harness for the two steps of knowbe4.yml built from src/: "Pick the CloudRadial company" and
# "Summarize assets & open PSA ticket". Runs each step exactly as it is in the .yml (extracted by
# build.js --extract) under Set-StrictMode -Version Latest, on all six PSAs, with the shared mocks
# (_shared/tests/mock.ps1). Placeholder data only (Contoso, Example MSP).
# Usage: pwsh -NoProfile -File knowbe4/src/test.ps1
#        (needs node and js-yaml; set JS_YAML_PATH if js-yaml isn't installed in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("kb4-test-" + [guid]::NewGuid().ToString('N'))
& node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { throw 'knowbe4.yml is out of date. Run node build.js first.' }
& node (Join-Path $PSScriptRoot 'build.js') --extract $tmp | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the steps.' }
$Steps = @{ company = Get-Content -Raw (Join-Path $tmp 'resolve-company.ps1'); ticket = Get-Content -Raw (Join-Path $tmp 'summarize-and-ticket.ps1') }
Remove-Item -Recurse -Force $tmp

function Get-NodeInput { param([string]$Name) if ($Name) { return $global:NodeIn[$Name] }; return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Invoke-Step {
    param([string]$Which, [hashtable]$In)
    $global:NodeIn = $In; $global:NodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps[$Which])) } catch { $err = [string]$_.Exception.Message }
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

# ---- Pick the CloudRadial company ----
Reset-Mock $CrSecrets $Handler
$r = Invoke-Step company @{ trigger = [pscustomobject]@{ companyId = 12 } }
Check 'company: from the run input' (-not $r.err -and $r.out.companyId -eq 12 -and $r.out.companyName -eq 'Contoso') "$($r.err) $(if ($r.out) { $r.out.message })"

Reset-Mock ($CrSecrets + @{ 'CloudRadial-CompanyId' = '12' }) $Handler
$r = Invoke-Step company @{ trigger = '' }
Check 'company: from the CloudRadial-CompanyId secret when the run has no input' (-not $r.err -and $r.out.companyId -eq 12) $r.err
$r = Invoke-Step company @{ trigger = '{"companyId":"{{companyId}}"}' }
Check 'company: an unreplaced placeholder falls back to the secret' (-not $r.err -and $r.out.companyId -eq 12) $r.err

Reset-Mock $CrSecrets $Handler
$r = Invoke-Step company @{ trigger = $null }
Check 'company: none given, the run stops with a plain message' ($r.err -match 'No CloudRadial company was given' -and $r.out.status -eq 'error') $r.err
$r = Invoke-Step company @{ trigger = [pscustomobject]@{ companyId = 99 } }
Check 'company: an unknown id stops the run' ($r.err -match 'has no company 99') $r.err
$r = Invoke-Step company @{ trigger = [pscustomobject]@{ companyId = 'Contoso' } }
Check 'company: a name instead of an id stops the run' ($r.err -match 'not a number|isn.t a number') $r.err

# ---- Summarize and open the ticket ----
$Results = @(
    [pscustomobject]@{ status = 'success'; assetId = 1; assetName = 'sam.doe@contoso.com'; userId = 'u1'; email = 'sam.doe@contoso.com'; courseCount = 2; companyId = 12; flexibleAssetTypeId = 9 },
    [pscustomobject]@{ status = 'success'; assetId = 2; assetName = 'Alex Kim'; userId = 'u2'; email = ''; courseCount = 1; companyId = 12; flexibleAssetTypeId = 9 },
    [pscustomobject]@{ status = 'error'; message = 'boom'; assetName = 'x'; userId = 'u3'; email = ''; courseCount = 1; companyId = 12 }
)
$In = @{ results = $Results; companyId = 12; companyName = 'Contoso' }

foreach ($psa in @('connectwise', 'autotask', 'halopsa', 'kaseyabms', 'syncro', 'zendesk')) {
    Reset-Mock (@{ 'PSA-Type' = $psa } + $S[$psa]) $Handler
    $r = Invoke-Step ticket $In
    Check "$($psa): step finishes without error" (-not $r.err) $r.err
    Check "$($psa): one create-ticket call, ticket id returned" (@(Get-CreateCall $psa).Count -eq 1 -and $r.out.ticketId -eq $Create[$psa][1]) "$(if ($r.out) { "$($r.out.message) / $($r.out.ticketWarning)" }) / $(Show-Calls)"
    Check "$($psa): ticket on PSA company 42, matched by name" ($r.out.psaCompanyId -eq '42') $r.out.psaCompanyId
    $body = (Get-CreateCall $psa | Select-Object -First 1).Body
    Check "$($psa): the ticket lists the overdue users" ($body -match 'sam.doe@contoso.com' -and $body -match 'Alex Kim' -and $body -match '2 incomplete') $body
    Check "$($psa): created and failed counts" ($r.out.createdCount -eq 2 -and $r.out.failedCount -eq 1) "$($r.out.createdCount)/$($r.out.failedCount)"
}

Reset-Mock (@{ 'PSA-Type' = 'connectwise'; 'CW-ServiceBoard' = 'Help Desk'; 'KnowBe4-AdminEmail' = 'it.admin@contoso.com' } + $S['connectwise']) $Handler
$r = Invoke-Step ticket $In
$body = (Get-CreateCall 'connectwise' | Select-Object -First 1).Body
Check 'ConnectWise: the older CW-ServiceBoard secret still sets the board' ($body -match 'Help Desk') $body
Check 'the KnowBe4 admin is named in the ticket' ($body -match 'it.admin@contoso.com') $body

Reset-Mock (@{ 'PSA-Type' = 'halopsa'; 'PSA-ServiceQueue' = '15' } + $S['halopsa']) $Handler
$r = Invoke-Step ticket $In
Check 'PSA-ServiceQueue is used' (@(Get-CreateCall 'halopsa').Count -eq 1 -and (Get-CreateCall 'halopsa')[0].Body -match '15') (Show-Calls)

Reset-Mock (@{ 'PSA-Type' = 'syncro'; 'PSA-CompanyId' = '900' } + $S['syncro']) $Handler
$r = Invoke-Step ticket @{ results = $Results; companyId = 13; companyName = 'Northwind' }
Check 'no name match: PSA-CompanyId used, with a warning' ($r.out.psaCompanyId -eq '900' -and $r.out.ticketId -eq '505' -and $r.out.ticketWarning -match 'PSA-CompanyId') "$($r.out.message) / $($r.out.ticketWarning)"

Reset-Mock (@{ 'PSA-Type' = 'syncro' } + $S['syncro']) $Handler
$r = Invoke-Step ticket @{ results = $Results; companyId = 13; companyName = 'Northwind' }
Check 'no name match and no fallback: no ticket, a warning, the run still succeeds' (-not $r.err -and $r.out.status -eq 'success' -and -not $r.out.ticketId -and $r.out.ticketWarning -match 'PSA ticket not created' -and @(Get-CreateCall 'syncro').Count -eq 0) "$($r.err) $($r.out.ticketWarning)"

Reset-Mock @{} $Handler
$r = Invoke-Step ticket $In
Check 'no PSA set up: a warning, the run still succeeds' (-not $r.err -and $r.out.status -eq 'success' -and $r.out.ticketWarning -match 'PSA ticket not created') "$($r.err) $(if ($r.out) { $r.out.ticketWarning })"

Reset-Mock (@{ 'PSA-Type' = 'connectwise' } + $S['connectwise']) $Handler
$r = Invoke-Step ticket @{ results = @($Results[2]); companyId = 12; companyName = 'Contoso' }
Check 'nobody overdue: no PSA calls, no ticket' (-not $r.err -and $Mock.Calls.Count -eq 0 -and -not $r.out.ticketId -and $r.out.createdCount -eq 0) (Show-Calls)
$r = Invoke-Step ticket @{ results = $null; companyId = 12; companyName = 'Contoso' }
Check 'no results at all: no failure' (-not $r.err -and $r.out.createdCount -eq 0) $r.err

Complete-Test
