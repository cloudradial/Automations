# Strict-mode harness for the three steps of knowbe4.yml built from src/: "Pick the CloudRadial company",
# "Create or update CloudRadial records" and "Summarize assets & open PSA ticket". Runs each step exactly as it is in the .yml (extracted by
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
$Steps = @{ company = Get-Content -Raw (Join-Path $tmp 'resolve-company.ps1'); records = Get-Content -Raw (Join-Path $tmp 'create-assets.ps1'); ticket = Get-Content -Raw (Join-Path $tmp 'summarize-and-ticket.ps1') }
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
    [pscustomobject]@{ status = 'success'; action = 'created'; worse = $true; previousCount = $null; assetId = 1; assetName = 'sam.doe@contoso.com'; userId = 'u1'; email = 'sam.doe@contoso.com'; courseCount = 2; companyId = 12; flexibleAssetTypeId = 9 },
    [pscustomobject]@{ status = 'success'; action = 'unchanged'; worse = $false; previousCount = 1; assetId = 2; assetName = 'Alex Kim'; userId = 'u2'; email = ''; courseCount = 1; companyId = 12; flexibleAssetTypeId = 9 },
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
    Check "$($psa): overdue, created and failed counts" ($r.out.overdueCount -eq 2 -and $r.out.createdCount -eq 1 -and $r.out.failedCount -eq 1) "$($r.out.overdueCount)/$($r.out.createdCount)/$($r.out.failedCount)"
    Check "$($psa): the new user is marked new" ($body -match 'sam.doe@contoso.com - 2 incomplete course\(s\) \(new\)' -and $body -notmatch 'Alex Kim - 1 incomplete course\(s\) \(') $body
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

# ---- No duplicate tickets: only when something got worse ----
Reset-Mock (@{ 'PSA-Type' = 'connectwise' } + $S['connectwise']) $Handler
$same = @([pscustomobject]@{ status = 'success'; action = 'unchanged'; worse = $false; previousCount = 2; assetId = 1; assetName = 'sam.doe@contoso.com'; userId = 'u1'; email = 'sam.doe@contoso.com'; courseCount = 2; companyId = 12; flexibleAssetTypeId = 9 },
    [pscustomobject]@{ status = 'success'; action = 'updated'; worse = $false; previousCount = 3; assetId = 2; assetName = 'Alex Kim'; userId = 'u2'; email = ''; courseCount = 1; companyId = 12; flexibleAssetTypeId = 9 },
    [pscustomobject]@{ status = 'success'; action = 'completed'; worse = $false; previousCount = 2; assetId = 3; assetName = 'pat.lee@contoso.com'; userId = ''; email = 'pat.lee@contoso.com'; courseCount = 0; companyId = 12; flexibleAssetTypeId = 9 })
$r = Invoke-Step ticket @{ results = $same; companyId = 12; companyName = 'Contoso' }
Check 'nothing got worse: no ticket, no PSA calls, says why' (-not $r.err -and $Mock.Calls.Count -eq 0 -and -not $r.out.ticketId -and $r.out.ticketSkipped -match 'newly overdue' -and $r.out.overdueCount -eq 2 -and $r.out.completedCount -eq 1) "$(Show-Calls) / $(if ($r.out) { $r.out.message })"
$more = @($same[0], $same[1], $same[2]) | ForEach-Object { $_.PSObject.Copy() }; $more[1].worse = $true; $more[1].previousCount = 0
$r = Invoke-Step ticket @{ results = $more; companyId = 12; companyName = 'Contoso' }
$body = (Get-CreateCall 'connectwise' | Select-Object -First 1).Body
Check 'someone owes more: one ticket, marked, caught-up user left out' ($r.out.ticketId -eq '501' -and $body -match 'Alex Kim - 1 incomplete course\(s\) \(up from 0\)' -and $body -notmatch 'pat.lee') $body

# ---- Create or update CloudRadial records ----
$Assets = @()
$RecHandler = {
    param($c, $n)
    $k = "$($c.Method) $($c.Uri)"
    switch -Wildcard -CaseSensitive ($k) {
        "GET $CR/v2/odata/flexibleasset*" { if ($c.Uri -match 'skip=0') { return [pscustomobject]@{ value = @($script:Assets) } }; return [pscustomobject]@{ value = @() } }
        "POST $CR/v2/flexible-asset" { return [pscustomobject]@{ flexibleAssetId = 700 } }
        "PATCH $CR/v2/flexible-asset/*" { return $null }
    }
    return $null
}
function Asset { param($id, $traits) [pscustomobject]@{ flexibleAssetId = $id; companyId = 12; flexibleAssetTypeId = 9; traitsJson = ($traits | ConvertTo-Json -Compress) } }
$Users = @(
    [pscustomobject]@{ userId = 'u1'; userName = 'Sam Doe'; email = 'Sam.Doe@contoso.com'; assetName = 'Sam.Doe@contoso.com'; courseCount = 2; coursesText = 'Phishing 101; Passwords' },
    [pscustomobject]@{ userId = 'u2'; userName = 'Alex Kim'; email = ''; assetName = 'Alex Kim'; courseCount = 3; coursesText = 'A; B; C' },
    [pscustomobject]@{ userId = 'u4'; userName = 'Jo New'; email = 'jo.new@contoso.com'; assetName = 'jo.new@contoso.com'; courseCount = 1; coursesText = 'Phishing 101' }
)
$script:Assets = @(
    (Asset 10 @{ user = 'Sam Doe'; email = 'sam.doe@contoso.com'; 'incomplete-courses' = 2; 'course-list' = 'Phishing 101; Passwords'; updated = '2026-10-01' }),
    (Asset 8 @{ user = 'Sam Doe'; email = 'sam.doe@contoso.com'; 'incomplete-courses' = 2; 'course-list' = 'Phishing 101; Passwords'; updated = '2026-09-24' }),
    (Asset 11 @{ 'User' = 'Alex Kim'; 'Email' = ''; 'Incomplete Courses' = '1'; 'Course List' = 'A'; 'Updated' = '2026-10-01' }),
    (Asset 12 @{ user = 'Pat Lee'; email = 'pat.lee@contoso.com'; 'incomplete-courses' = 2; 'course-list' = 'X; Y'; updated = '2026-10-01' }),
    (Asset 13 @{ user = 'Done Already'; email = 'done@contoso.com'; 'incomplete-courses' = 0; 'course-list' = 'All assigned training complete'; updated = '2026-09-01' })
)
Reset-Mock $CrSecrets $RecHandler
$r = Invoke-Step records @{ users = $Users; companyId = 12; flexibleAssetTypeId = 9 }
$it = @{}; foreach ($x in @($r.out.items)) { $it[[string]$x.assetName] = $x }
$posts = @($Mock.Calls | Where-Object { $_.Method -eq 'POST' }); $patches = @($Mock.Calls | Where-Object { $_.Method -eq 'PATCH' })
Check 'records: step finishes without error' (-not $r.err) $r.err
Check 'records: same courses, matched by email in any case, left unchanged' ($it['Sam.Doe@contoso.com'].action -eq 'unchanged' -and $it['Sam.Doe@contoso.com'].assetId -eq '10' -and -not $it['Sam.Doe@contoso.com'].worse) ($it['Sam.Doe@contoso.com'] | ConvertTo-Json -Compress)
Check 'records: matched by name when there is no email, portal-style trait names read, update and worse' ($it['Alex Kim'].action -eq 'updated' -and $it['Alex Kim'].worse -and $it['Alex Kim'].previousCount -eq 1) ($it['Alex Kim'] | ConvertTo-Json -Compress)
Check 'records: a new user gets one new record' ($it['jo.new@contoso.com'].action -eq 'created' -and $it['jo.new@contoso.com'].worse -and $posts.Count -eq 1) (Show-Calls)
Check 'records: a user who caught up is set to 0, not deleted' ($it['pat.lee@contoso.com'].action -eq 'completed' -and @($patches | Where-Object { $_.Uri -match '/12$' -and $_.Body -match 'All assigned training complete' }).Count -eq 1 -and @($Mock.Calls | Where-Object { $_.Method -eq 'DELETE' }).Count -eq 0) (Show-Calls)
Check 'records: an already-complete record is left alone' (-not $it.ContainsKey('done@contoso.com') -and @($patches | Where-Object { $_.Uri -match '/13$' }).Count -eq 0) (Show-Calls)
Check 'records: exactly two updates (Alex and Pat)' ($patches.Count -eq 2) (Show-Calls)
Check 'records: the older duplicate is reported, not deleted' (@($r.out.duplicates) -contains '8' -and $r.out.message -match '1 older duplicate') $r.out.message

$script:Assets = @()
Reset-Mock $CrSecrets $RecHandler
$r = Invoke-Step records @{ users = $Users; companyId = 12; flexibleAssetTypeId = 9 }
Check 'records: first run creates one record per user' (@($Mock.Calls | Where-Object { $_.Method -eq 'POST' }).Count -eq 3 -and @($r.out.items | Where-Object { $_.action -eq 'created' }).Count -eq 3) (Show-Calls)

$FailRead = { param($c, $n) if ($c.Method -eq 'GET') { throw 'HTTP 500' }; return $null }
Reset-Mock $CrSecrets $FailRead
$r = Invoke-Step records @{ users = $Users; companyId = 12; flexibleAssetTypeId = 9 }
Check "records: can't read existing records, so nothing is written" ($r.err -match 'avoid duplicates' -and @($Mock.Calls | Where-Object { $_.Method -ne 'GET' }).Count -eq 0) $r.err

Complete-Test
