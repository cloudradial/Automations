# Strict-mode mock harness for the QBR Data Pack workflow.
# Runs the five steps embedded in ../qbr-data-pack.yml (run "node build.js" first) the way the runner does:
# each through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the node output passed
# to the next step as JSON. Mocks Get-AzKeyVaultSecret, Invoke-RestMethod, Get-NodeInput and Set-NodeOutput.
# Placeholder data only (Contoso, Fabrikam, Example MSP).
# Usage: pwsh -NoProfile -File automationai/qbr-data-pack/src/test.ps1   (needs node and js-yaml; set JS_YAML_PATH if needed)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

# ---- the steps, from the built .yml ----
$yml = Join-Path $PSScriptRoot '..\qbr-data-pack.yml'
$js = @'
let y; try { y = require('js-yaml'); } catch { try { y = require(require('path').join(process.argv[2], 'node_modules', 'js-yaml')); } catch { y = require(process.env.JS_YAML_PATH); } }
const a = y.load(require('fs').readFileSync(process.argv[1], 'utf8')).definition.activities;
const o = {}; for (const x of a) if (x.properties && x.properties.script) o[x.id] = x.properties.script;
process.stdout.write(Buffer.from(JSON.stringify(o)).toString('base64'));
'@
$b64 = node -e $js $yml (Join-Path $PSScriptRoot '..\..\_shared')
if ($LASTEXITCODE -ne 0 -or -not $b64) { throw 'Could not read the steps from qbr-data-pack.yml (is js-yaml available?).' }
$Steps = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) | ConvertFrom-Json
$StepIds = @('node-inputs', 'node-cloudradial', 'node-psa', 'node-m365', 'node-card')
foreach ($id in $StepIds) { if (-not $Steps.PSObject.Properties[$id]) { throw "Step $id missing from the .yml" } }
Check 'built .yml: shared libraries are injected' ($Steps.'node-cloudradial' -match 'function Set-CrPlannerCard' -and $Steps.'node-psa' -match 'function Connect-Psa' -and $Steps.'node-m365' -match 'function Connect-Graph' -and $Steps.'node-card' -match 'function Set-CrPlannerCard')

function Get-NodeInput { return $global:QbrNodeIn }
function Set-NodeOutput { param($o) $global:QbrNodeOut = $o }
function ConvertTo-NodeJson { param($o) return ($o | ConvertTo-Json -Depth 30 | ConvertFrom-Json) }
function Invoke-Step {
    param([string]$Id, $InputObject)
    $global:QbrNodeIn = $InputObject; $global:QbrNodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps.$Id)) } catch { $err = [string]$_.Exception.Message }
    return @{ out = $(if ($null -ne $global:QbrNodeOut) { ConvertTo-NodeJson $global:QbrNodeOut } else { $null }); error = $err }
}
function Invoke-Workflow {
    param($RunInput)
    $r = @{ out = $RunInput; error = '' }; $first = $true
    foreach ($id in $StepIds) {
        $r = Invoke-Step $id $(if ($first) { $RunInput } else { $r.out }); $first = $false
        if ($r.error) { return @{ step = $id } + $r }
    }
    return @{ step = 'node-card' } + $r
}

# ---- mock data ----
$Now = (Get-Date).ToUniversalTime()
$QLabel = "Q$([int][Math]::Ceiling($Now.Month / 3)) $($Now.Year)"
$QKey = "qbr-data-pack:$($Now.Year)-Q$([int][Math]::Ceiling($Now.Month / 3))"
function Iso { param([double]$DaysAgo) return $Now.AddDays(-$DaysAgo).ToString('yyyy-MM-ddTHH:mm:ssZ') }
function EP { param($Name, $Os, [double]$AgeYears, [double]$WarrantyDays, [bool]$Server = $false, [bool]$Virtual = $false, [int]$Company = 7, [int]$SeenDaysAgo = 1)
    return @{ companyEndpointId = (Get-Random); companyId = $Company; name = $Name; os = $Os; isServer = $Server; isVirtual = $Virtual
        manufacturedDate = $(if ($AgeYears -ge 0) { Iso ($AgeYears * 365.25) } else { $null }); biosDate = $null; cpuDate = $null
        expirationDate = $(if ($WarrantyDays -gt -9000) { Iso (-$WarrantyDays) } else { $null }); memory = 17179869184; windows11Readiness = 'Ready'; lastCheckIn = (Iso $SeenDaysAgo) }
}
$Endpoints = @(
    (EP 'CONTOSO-LT01' 'Microsoft Windows 11 Pro' 1.5 400),
    (EP 'CONTOSO-LT02' 'Microsoft Windows 11 Pro' 3.5 30),
    (EP 'CONTOSO-DT01' 'Microsoft Windows 10 Pro' 6 -100),
    (EP 'CONTOSO-DT02' 'Microsoft Windows 10 Pro' 8 -900 -SeenDaysAgo 45),
    (EP 'CONTOSO-MAC1' 'macOS 14.5' 2 60),
    (EP 'CONTOSO-SRV1' 'Microsoft Windows Server 2019' 5.5 -10 -Server $true),
    (EP 'CONTOSO-VM1' 'Microsoft Windows Server 2022' 1 -9999 -Server $true -Virtual $true),
    (EP 'CONTOSO-NAS' 'Linux' -1 -9999),
    (EP 'FABRIKAM-PC9' 'Microsoft Windows 10 Pro' 9 -900 -Company 8))   # stray row: must never be counted for Contoso
$Domains = @(
    @{ companyDomainId = 1; companyId = 7; name = 'contoso.com'; dateExpires = (Iso -45); isDeleted = $false },
    @{ companyDomainId = 2; companyId = 7; name = 'contoso.net'; dateExpires = (Iso -300); isDeleted = $false },
    @{ companyDomainId = 3; companyId = 7; name = 'old-contoso.org'; dateExpires = (Iso 5); isDeleted = $true },
    @{ companyDomainId = 4; companyId = 8; name = 'fabrikam.com'; dateExpires = (Iso -10); isDeleted = $false })
$Certs = @(
    @{ id = 1; companyId = 7; name = 'portal.contoso.com'; expirationDate = (Iso -12); isDeleted = $false },
    @{ id = 2; companyId = 7; name = 'www.contoso.com'; expirationDate = (Iso -200); isDeleted = $false })
$OtherCards = @(
    @{ productId = 11; companyId = 7; subject = 'Upgrade firewall'; body = 'x'; status = 'Proposed'; isDeleted = $false },
    @{ productId = 12; companyId = 7; subject = 'Done thing'; body = 'x'; status = 'Completed'; isDeleted = $false },
    @{ productId = 13; companyId = 7; subject = 'Plan backup'; body = 'x'; status = 'In_Planning'; isDeleted = $false })
$Companies = @(@{ companyId = 7; name = 'Contoso Ltd'; psaKey = 250; psaIdentifier = 'ContosoLtd' }, @{ companyId = 8; name = 'Fabrikam'; psaKey = 260; psaIdentifier = 'Fabrikam' })
$CatList = @('Email', 'Email', 'Email', 'Email', 'Email', 'Printing', 'Printing', 'Printing', 'Network', 'Network', '', 'Security')
$SkuList = @(
    @{ skuId = 's1'; skuPartNumber = 'SPB'; appliesTo = 'User'; consumedUnits = 47; prepaidUnits = @{ enabled = 50; warning = 0; suspended = 0 } },
    @{ skuId = 's2'; skuPartNumber = 'EXCHANGESTANDARD'; appliesTo = 'User'; consumedUnits = 10; prepaidUnits = @{ enabled = 10; warning = 0; suspended = 0 } },
    @{ skuId = 's3'; skuPartNumber = 'FLOW_FREE'; appliesTo = 'User'; consumedUnits = 4; prepaidUnits = @{ enabled = 10000; warning = 0; suspended = 0 } },
    @{ skuId = 's4'; skuPartNumber = 'CONTOSO_CUSTOM_ADDON'; appliesTo = 'User'; consumedUnits = 4; prepaidUnits = @{ enabled = 5; warning = 0; suspended = 0 } })
# Syncro has to be listed: 38 created this period, 34 the one before; 40 and 36 resolved; 7 open.
function SyncroRows { param([int]$Cur, [int]$Prev, [string]$Field)
    $i = 0
    @(1..$Cur | ForEach-Object { $i++; @{ id = $i; customer_id = 250; problem_type = $CatList[$i % $CatList.Count]; $Field = (Iso (1 + ($_ % 80))) } }) + @(1..$Prev | ForEach-Object { $i++; @{ id = $i; customer_id = 250; problem_type = 'Old'; $Field = (Iso (95 + ($_ % 80))) } })
}

$CrBase = 'https://api.example-msp.test'
$Secrets = @{
    'CloudRadial-BaseUrl' = $CrBase; 'CloudRadial-PublicKey' = 'pk'; 'CloudRadial-PrivateKey' = 'sk'
    'M365-TenantId' = '00000000-0000-0000-0000-0000000000c1'; 'M365-ClientId' = 'app-id'; 'M365-ClientSecret' = 'not-a-real-secret'
}
$PsaSecrets = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://cw.example-msp.test/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'p'; 'CW-PrivateKey' = 'k'; 'CW-ClientId' = 'c' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://at.example-msp.test'; 'Autotask-ApiIntegrationCode' = 'i'; 'Autotask-Username' = 'u'; 'Autotask-Secret' = 's' }
    halopsa     = @{ 'PSA-Type' = 'halopsa'; 'Halo-ApiUrl' = 'https://halo.example-msp.test'; 'Halo-ClientId' = 'c'; 'Halo-ClientSecret' = 's' }
    kaseyabms   = @{ 'PSA-Type' = 'kaseyabms'; 'KaseyaBMS-ApiUrl' = 'https://bms.example-msp.test'; 'KaseyaBMS-Username' = 'u'; 'KaseyaBMS-Password' = 'p'; 'KaseyaBMS-CompanyName' = 'examplemsp' }
    syncro      = @{ 'PSA-Type' = 'syncro'; 'Syncro-ApiUrl' = 'https://examplemsp.syncromsp.test/api/v1'; 'Syncro-ApiKey' = 'k' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://examplemsp.zendesk.test'; 'Zendesk-Email' = 'agent@example-msp.test'; 'Zendesk-ApiToken' = 't' }
}
# Counts by span: the mock tells the current span from the previous one by its start date.
function IsCurrent { param([string]$Text) if ($Text -match '(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})') { return ([datetime]::Parse($Matches[1], [cultureinfo]::InvariantCulture) -gt $Now.AddDays(-100)) }; return $false }
function Pick { param([string]$Kind, [string]$Text) switch ($Kind) { 'opened' { if (IsCurrent $Text) { 38 } else { 34 } } 'closed' { if (IsCurrent $Text) { 40 } else { 36 } } default { 7 } } }

$global:QbrT = @{}
function Set-Scenario {
    param([string]$Psa = 'connectwise', [hashtable]$Over = @{}, [hashtable]$ExtraSecrets = @{}, [string[]]$DropSecrets = @())
    $global:QbrT = @{
        companies = $Companies; endpoints = $Endpoints; domains = $Domains; certs = $Certs; cards = $OtherCards; newId = 501
        skus = $SkuList; verified = @('contoso.com', 'contoso.onmicrosoft.com'); orgError = 0; skuError = 0; psaError = 0; crEndpointError = 0
        psaCompanyRows = @(); syncroCreated = (SyncroRows 38 34 'created_at'); syncroResolved = (SyncroRows 40 36 'resolved_at'); syncroOpen = @(1..7 | ForEach-Object { @{ id = $_; customer_id = 250 } })
    }
    foreach ($k in $Over.Keys) { $global:QbrT[$k] = $Over[$k] }
    $s = $Secrets.Clone(); if ($Psa) { foreach ($k in $PsaSecrets[$Psa].Keys) { $s[$k] = $PsaSecrets[$Psa][$k] } }
    foreach ($k in $ExtraSecrets.Keys) { $s[$k] = $ExtraSecrets[$k] }
    foreach ($k in $DropSecrets) { $s.Remove($k) }
    Reset-Mock $s {
        param($c, $n)
        $T = $global:QbrT
        $u = [uri]::UnescapeDataString($c.Uri)
        # ---- Microsoft ----
        if ($u -like 'https://login.microsoftonline.com/*') { return [pscustomobject]@{ access_token = 'tok'; expires_in = 3599 } }
        if ($u -like 'https://graph.microsoft.com/*') {
            if ($c.Method -ne 'GET') { throw "Graph write attempted: $($c.Method) $u" }
            if ($u -like '*/organization*') { if ($T.orgError) { New-HttpError $T.orgError '{"error":{"message":"Insufficient privileges to complete the operation."}}' }; return (ConvertTo-NodeJson @{ value = @(@{ id = 't'; displayName = 'Contoso Ltd'; verifiedDomains = @($T.verified | ForEach-Object { @{ name = $_ } }) }) }) }
            if ($u -like '*/subscribedSkus*') { if ($T.skuError) { New-HttpError $T.skuError '{"error":{"message":"Insufficient privileges"}}' }; return (ConvertTo-NodeJson @{ value = $T.skus }) }
            throw "Unmocked Graph call: $($c.Method) $u"
        }
        # ---- CloudRadial ----
        if ($u -like "$CrBase/*") {
            $first = ($u -notmatch '\$skip=[1-9]')
            $cid = 0; if ($u -match 'companyId eq (\d+)') { $cid = [int]$Matches[1] }
            if ($c.Method -eq 'GET') {
                $rows = $null
                if ($u -match '/v2/odata/company\?') { $rows = @($T.companies | Where-Object { $_.companyId -eq $cid }) }
                elseif ($u -match '/v2/odata/endpoint\?') { if ($T.crEndpointError) { New-HttpError $T.crEndpointError '{"message":"Forbidden"}' }; $rows = @($T.endpoints | Where-Object { $_.companyId -eq $cid -or $_.name -like 'FABRIKAM*' }) }   # the stray Fabrikam row tests the step's own filter
                elseif ($u -match '/v2/odata/product\?') { $rows = @($T.cards | Where-Object { $_.companyId -eq $cid }) }
                elseif ($u -match '/v2/odata/domain\?') { $rows = @($T.domains | Where-Object { $_.companyId -eq $cid }) }
                elseif ($u -match '/v2/odata/certificate\?') { $rows = @($T.certs | Where-Object { $_.companyId -eq $cid }) }
                if ($null -ne $rows) { return (ConvertTo-NodeJson @{ value = @($(if ($first) { $rows })) }) }
            }
            if ($c.Method -eq 'POST' -and $u -match '/v2/product$') { return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ productId = $T.newId } } }
            if ($c.Method -eq 'PATCH' -and $u -match '/v2/product/(\d+)$') { return [pscustomobject]@{ success = $true } }
            throw "Unmocked CloudRadial call: $($c.Method) $u"
        }
        # ---- PSAs (GET only, except the HaloPSA and Kaseya BMS sign-in) ----
        $isAuth = ($u -like 'https://halo.example-msp.test/auth/token' -or $u -like 'https://bms.example-msp.test/v2/security/authenticate')
        if ($c.Method -ne 'GET' -and -not $isAuth) { throw "PSA write attempted: $($c.Method) $u" }
        if ($T.psaError -and -not $isAuth) { New-HttpError $T.psaError '{"message":"Internal error"}' }
        if ($u -like 'https://cw.example-msp.test/*') {
            if ($u -match '/company/companies\?') { return (ConvertTo-NodeJson @($T.psaCompanyRows)) }
            if ($u -notmatch 'company/id=250\b') { throw "ConnectWise call not filtered to company 250: $u" }
            if ($u -match '/service/tickets/count\?') { $k = if ($u -match 'closedFlag=false') { 'open' } elseif ($u -match 'closedDate') { 'closed' } else { 'opened' }; return [pscustomobject]@{ count = (Pick $k $u) } }
            if ($u -match '/service/tickets\?') { return (ConvertTo-NodeJson @($CatList | ForEach-Object { @{ id = 1; type = $(if ($_) { @{ id = 1; name = $_ } } else { $null }); board = @{ name = 'Help Desk' } } })) }
        }
        if ($u -like 'https://at.example-msp.test/*') {
            if ($u -match '/Tickets/entityInformation/fields') { return (ConvertTo-NodeJson @{ fields = @(@{ name = 'status'; picklistValues = @(@{ value = 1; label = 'New'; isActive = $true }, @{ value = 5; label = 'Complete'; isActive = $true }) }, @{ name = 'issueType'; picklistValues = @(@{ value = 1; label = 'Email'; isActive = $true }, @{ value = 2; label = 'Printing'; isActive = $true }, @{ value = 3; label = 'Network'; isActive = $true }, @{ value = 4; label = 'Security'; isActive = $true }) }) }) }
            if ($u -match '/Companies/query') { return (ConvertTo-NodeJson @{ items = @($T.psaCompanyRows) }) }
            $search = ''; if ($u -match 'search=(\{.*\})$') { $search = $Matches[1] }
            $j = $search | ConvertFrom-Json
            if (-not @($j.filter | Where-Object { $_.field -eq 'companyID' -and $_.value -eq 250 }).Count) { throw "Autotask call not filtered to company 250: $u" }
            if ($u -match '/Tickets/query/count') { $k = if (@($j.filter | Where-Object { $_.op -eq 'noteq' -and $_.field -eq 'status' -and $_.value -eq 5 }).Count) { 'open' } elseif ($search -match 'completedDate') { 'closed' } else { 'opened' }; return [pscustomobject]@{ queryCount = (Pick $k $search) } }
            if ($u -match '/Tickets/query\?') { $map = @{ Email = 1; Printing = 2; Network = 3; Security = 4 }; return (ConvertTo-NodeJson @{ items = @($CatList | ForEach-Object { @{ id = 1; issueType = $(if ($_) { $map[$_] } else { $null }) } }); pageDetails = @{ nextPageUrl = $null } }) }
        }
        if ($u -like 'https://halo.example-msp.test/*') {
            if ($u -like '*/auth/token') { return [pscustomobject]@{ access_token = 'halo-token' } }
            if ($u -match '/api/Client\?') { return (ConvertTo-NodeJson @{ clients = @($T.psaCompanyRows) }) }
            if ($u -notmatch 'client_id=250\b') { throw "HaloPSA call not filtered to client 250: $u" }
            if ($u -match 'page_size=100') { return (ConvertTo-NodeJson @{ record_count = 12; tickets = @($CatList | ForEach-Object { @{ id = 1; category_1 = $_ } }) }) }
            $k = if ($u -match 'open_only=true') { 'open' } elseif ($u -match 'dateclosed') { 'closed' } else { 'opened' }
            return [pscustomobject]@{ record_count = (Pick $k $u); tickets = @() }
        }
        if ($u -like 'https://bms.example-msp.test/*') {
            if ($u -like '*/security/authenticate') { return [pscustomobject]@{ Success = $true; Result = [pscustomobject]@{ AccessToken = 'bms-token' } } }
            if ($u -match '/crm/accounts') { return (ConvertTo-NodeJson @{ Result = @($T.psaCompanyRows) }) }
            if ($u -notmatch 'Filter\.AccountIds=250\b') { throw "Kaseya BMS call not filtered to account 250: $u" }
            if ($u -match 'PageSize=100') { return (ConvertTo-NodeJson @{ Success = $true; TotalRecords = 12; Result = @($CatList | ForEach-Object { @{ Id = 1; IssueTypeName = $_ } }) }) }
            $k = if ($u -match 'ExcludeCompleted=true') { 'open' } elseif ($u -match 'CompletedDateFrom') { 'closed' } else { 'opened' }
            return [pscustomobject]@{ Success = $true; TotalRecords = (Pick $k $u); Result = @() }
        }
        if ($u -like 'https://examplemsp.syncromsp.test/*') {
            if ($u -match '/customers\?') { return (ConvertTo-NodeJson @{ customers = @($T.psaCompanyRows) }) }
            if ($u -notmatch 'customer_id=250\b') { throw "Syncro call not filtered to customer 250: $u" }
            $all = if ($u -match 'created_after') { $T.syncroCreated } elseif ($u -match 'resolved_after') { $T.syncroResolved } else { $T.syncroOpen }
            $page = 1; if ($u -match '[?&]page=(\d+)') { $page = [int]$Matches[1] }
            $pages = [int][Math]::Max(1, [Math]::Ceiling(@($all).Count / 25))
            return (ConvertTo-NodeJson @{ tickets = @($all | Select-Object -Skip (($page - 1) * 25) -First 25); meta = @{ total_pages = $pages; page = $page } })
        }
        if ($u -like 'https://examplemsp.zendesk.test/*') {
            if ($u -match '/organizations/autocomplete') { return (ConvertTo-NodeJson @{ organizations = @($T.psaCompanyRows) }) }
            if ($u -notmatch 'organization:250\b') { throw "Zendesk call not filtered to organization 250: $u" }
            if ($u -match '/search/count\?') { $k = if ($u -match 'status<solved') { 'open' } elseif ($u -match 'solved>') { 'closed' } else { 'opened' }; return [pscustomobject]@{ count = (Pick $k $u) } }
            if ($u -match '/search\?') { return (ConvertTo-NodeJson @{ results = @($CatList | ForEach-Object { @{ id = 1; type = $(if ($_) { $_ } else { $null }) } }); next_page = $null }) }
        }
        throw "Unmocked call: $($c.Method) $u"
    }
}
function Get-CrWrites { return @($Mock.Calls | Where-Object { $_.Uri -like "$CrBase/*" -and $_.Method -ne 'GET' }) }
function Get-Patch { param($Call, [string]$Field) $ops = @($Call.Body | ConvertFrom-Json); $op = @($ops | Where-Object { $_.path -eq "/$Field" }) | Select-Object -First 1; if ($op) { return $op.value }; return $null }
function Get-OtherWrites { return @($Mock.Calls | Where-Object { $_.Uri -notlike "$CrBase/*" -and $_.Method -ne 'GET' -and $_.Uri -notmatch 'login\.microsoftonline\.com|/auth/token|/security/authenticate' }) }

# ---- 1. preview: everything read, nothing written ----
Set-Scenario
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7; preview = $true })
Check 'preview: runs to the end' ($r.step -eq 'node-card' -and -not $r.error) $r.error
Check 'preview: status pending_confirmation, card would be created' ($r.out.status -eq 'pending_confirmation' -and $r.out.cardAction -eq 'would-create') ($r.out | ConvertTo-Json -Depth 4 -Compress)
Check 'preview: no CloudRadial writes and no other writes' (@(Get-CrWrites).Count -eq 0 -and @(Get-OtherWrites).Count -eq 0) (Show-Calls)
Check 'preview: message says preview and nothing changed' ($r.out.message -match '^Preview only' -and $r.out.message -match 'Nothing was changed') $r.out.message
Check 'preview: card body still worked out' ($r.out.cardBody -match 'quarterly business review' -and $r.out.cardSubject -eq "QBR prep: $QLabel") $r.out.cardSubject

# ---- 2. a real run (ConnectWise): one card created ----
Set-Scenario
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
Check 'run: success and card created' ($r.out.status -eq 'success' -and $r.out.cardAction -eq 'created' -and $r.out.productId -eq '501') ($r.error + ' ' + $r.step)
$w = @(Get-CrWrites)
Check 'run: exactly one write, a POST to /v2/product' ($w.Count -eq 1 -and $w[0].Method -eq 'POST' -and $w[0].Uri -like '*/v2/product') (Show-Calls)
Check 'run: nothing written to the PSA or Microsoft 365' (@(Get-OtherWrites).Count -eq 0) (Show-Calls)
$card = $w[0].Body | ConvertFrom-Json
$body = [string]$card.body
Check 'card: company, subject, quarter key, internal only, open' ($card.companyId -eq 7 -and $card.subject -eq "QBR prep: $QLabel" -and $body.Contains($QKey) -and $card.isClientVisible -eq $false -and $card.status -eq 0 -and $card.notes -match '^Internal:') $card.subject
Check 'card: opening sentence says read-only and the span' ($body -match "quarterly business review \($QLabel\)" -and $body -match 'covers the 90 days from' -and $body -match 'Nothing was changed in any system') $body
Check 'card: device sentence' ($body -match 'Contoso Ltd has 8 managed devices: 6 workstations, 1 server and 1 virtual machine\.' -and $body -match '3 devices are 5 or more years old, 1 of them 7 or more\.') $body
Check 'card: warranty and OS sentences' ($body -match 'The warranty has expired on 3 devices, and 2 more end within 90 days\.' -and $body -match '2 devices run an operating system that no longer gets security updates\.') $body
Check 'card: ELM replacement and stale check-in' ($body -match '2 workstations are due for replacement' -and $body -match '1 device has not checked in for 30 days') $body
Check 'card: age table (physical devices only, Linux NAS has no age)' ($body -match '<td>Under 3 years</td><td>2</td>' -and $body -match '<td>3 to 5 years</td><td>1</td>' -and $body -match '<td>5 to 7 years</td><td>2</td>' -and $body -match '<td>7 years or more</td><td>1</td>' -and $body -match '<td>Unknown</td><td>1</td>') $body
Check 'card: warranties ending soon listed' ($body -match 'CONTOSO-LT02' -and $body -match 'CONTOSO-MAC1') $body
Check 'card: ticket sentence with trend' ($body -match 'In ConnectWise, 38 tickets were opened in the last 90 days, up 12% from 34 in the previous period, and 40 were closed, up 11% from 36 in the previous period\. 7 tickets are open now\.') $body
Check 'card: top category and table' ($body -match 'The most common ticket type was Email \(5 tickets\)' -and $body -match '<td>Printing</td><td>3</td>' -and $body -match 'first 12 of 38 tickets') $body
Check 'card: category table header and blank-category note' ($body -match '<th>Ticket type</th><th>Tickets</th>' -and $body -match '1 ticket opened this period has no ticket type\.') $body
Check 'card: internal note names the sources and a UTC time' ($card.notes -match 'ConnectWise company 250' -and $card.notes -match 'Gathered \d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC over 90 days' -and $card.notes -match [regex]::Escape($QKey)) $card.notes
Check 'card: ticket table' ($body -match '<td>Opened</td><td>38</td><td>34</td>' -and $body -match '<td>Closed</td><td>40</td><td>36</td>' -and $body -match '<td>Open now</td><td>7</td>') $body
Check 'card: licence sentence and table, free SKU left out' ($body -match 'Microsoft 365 has 65 paid licences across 3 subscriptions, with 61 assigned and 4 unassigned\.' -and $body -match 'The most unassigned is Microsoft 365 Business Premium, with 3 of 50 not in use' -and $body -match '<td>CONTOSO_CUSTOM_ADDON</td><td>5</td><td>4</td><td>1</td>' -and $body -notmatch 'FLOW_FREE') $body
Check 'card: domains and certificates (deleted domain left out)' ($body -match '1 domain has expired or will expire within 60 days, and 1 certificate has expired or will expire within 30 days' -and $body -match 'contoso\.com' -and $body -match 'portal\.contoso\.com' -and $body -notmatch 'old-contoso') $body
Check 'card: other open Planner cards counted (completed left out)' ($body -match 'There are 2 other open cards on this Planner board') $body
Check 'card: no other client''s data' ($body -notmatch 'Fabrikam|FABRIKAM|fabrikam') $body
Check 'card: plain summary' ($card.summary -eq "Numbers for the $QLabel review: 8 devices (3 aged 5 years or more), 38 tickets opened in 90 days, 4 unassigned licences, 2 domains or certificates expiring soon.") $card.summary
Check 'card: never says Microsoft Planner or Teams' ($body -notmatch 'Microsoft Planner|Teams') $body
Check 'card: no em dashes' ($body -notmatch [char]0x2014 -and $r.out.message -notmatch [char]0x2014) ''
Check 'output: sections carried to the end' ($r.out.tickets.openedCurrent -eq 38 -and $r.out.devices.total -eq 8 -and $r.out.licences.available -and $r.out.tickets.matchedBy -match 'psaKey') ($r.out.tickets | ConvertTo-Json -Compress)

# ---- 3. same quarter re-run updates; last quarter's card is left alone ----
Set-Scenario 'connectwise' @{ cards = @($OtherCards) + @(@{ productId = 321; companyId = 7; subject = 'Renamed by vCIO'; body = "<p>old</p><p><em>$QKey</em></p>"; status = 'Proposed'; isDeleted = $false }) }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
$w = @(Get-CrWrites)
Check 'same quarter: PATCH the existing card found by its key, no new card' ($r.out.cardAction -eq 'updated' -and $w.Count -eq 1 -and $w[0].Method -eq 'PATCH' -and $w[0].Uri -like '*/v2/product/321') (Show-Calls)
Check 'same quarter: subject put back' ((Get-Patch $w[0] 'subject') -eq "QBR prep: $QLabel") $w[0].Body
Check 'same quarter: the QBR card is not counted as another open card' ($r.out.planner.open -eq 2) ($r.out.planner | ConvertTo-Json -Compress)
Set-Scenario 'connectwise' @{ cards = @(@{ productId = 320; companyId = 7; subject = 'QBR prep: Q1 2020'; body = '<p><em>qbr-data-pack:2020-Q1</em></p>'; status = 'Proposed'; isDeleted = $false }) }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
$w = @(Get-CrWrites)
Check 'new quarter: a new card, last quarter''s untouched' ($r.out.cardAction -eq 'created' -and $w.Count -eq 1 -and $w[0].Method -eq 'POST') (Show-Calls)

# ---- 4. the other five PSAs ----
foreach ($p in @('autotask', 'halopsa', 'kaseyabms', 'syncro', 'zendesk')) {
    Set-Scenario $p
    $r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
    $t = $r.out.tickets
    Check "$($p): ticket counts" ($r.out.status -eq 'success' -and $t.available -and $t.openedCurrent -eq 38 -and $t.openedPrevious -eq 34 -and $t.closedCurrent -eq 40 -and $t.closedPrevious -eq 36 -and $t.openNow -eq 7) ("$($r.error) " + ($t | ConvertTo-Json -Compress -Depth 4))
    $topName = if ($p -eq 'syncro') { @($t.categories)[0].name } else { 'Email' }
    Check "$($p): top category Email first" (@($t.categories).Count -gt 0 -and @($t.categories)[0].name -eq 'Email' -and $topName -eq 'Email') ($t.categories | ConvertTo-Json -Compress)
    Check "$($p): one card write, no PSA writes" (@(Get-CrWrites).Count -eq 1 -and @(Get-OtherWrites).Count -eq 0) (Show-Calls)
}

# ---- 5. PSA not available: the run carries on ----
Set-Scenario ''
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
$body = [string](@(Get-CrWrites)[0].Body | ConvertFrom-Json).body
Check 'no PSA set up: success, section says not available' ($r.out.status -eq 'success' -and -not $r.out.tickets.available -and $body -match 'No PSA is set up on this runner, so ticket trends are not available') $r.error
Set-Scenario 'connectwise' @{ companies = @(@{ companyId = 7; name = 'Contoso Ltd'; psaKey = 0; psaIdentifier = '' }) }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
Check 'client not matched in the PSA: success, says how to fix' ($r.out.status -eq 'success' -and $r.out.tickets.reason -match 'psa_company_id') $r.out.tickets.reason
Set-Scenario 'connectwise' @{ companies = @(@{ companyId = 7; name = 'Contoso Ltd'; psaKey = 0; psaIdentifier = '' }) }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7; psa_company_id = '250' })
Check 'psa_company_id input wins' ($r.out.tickets.available -and $r.out.tickets.matchedBy -eq 'psa_company_id input' -and $r.out.tickets.openedCurrent -eq 38) $r.out.tickets.reason
Set-Scenario 'autotask' @{ companies = @(@{ companyId = 7; name = 'Contoso Ltd'; psaKey = 0; psaIdentifier = '' }); psaCompanyRows = @(@{ id = 250; companyName = 'Contoso Ltd' }) }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
Check 'Autotask: exact name match finds the company' ($r.out.tickets.available -and $r.out.tickets.matchedBy -match 'exact name match' -and $r.out.tickets.psaCompanyId -eq '250') $r.out.tickets.reason
Set-Scenario 'connectwise' @{ psaError = 500 }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
Check 'PSA error: section not available, run still posts the card' ($r.out.status -eq 'success' -and -not $r.out.tickets.available -and $r.out.tickets.reason -match 'HTTP 500' -and @(Get-CrWrites).Count -eq 1) $r.out.tickets.reason
Set-Scenario 'connectwise' @{} @{} @('CW-PrivateKey')
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
Check 'PSA secret missing: named, run continues' ($r.out.status -eq 'success' -and $r.out.tickets.reason -match 'CW-PrivateKey') $r.out.tickets.reason

# ---- 6. Microsoft 365: missing permission, missing secrets, wrong tenant ----
Set-Scenario 'connectwise' @{ orgError = 403 }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
$body = [string](@(Get-CrWrites)[0].Body | ConvertFrom-Json).body
Check '403 from Graph: skipped with a sentence naming Organization.Read.All, card still posted' ($r.out.status -eq 'success' -and -not $r.out.licences.available -and $body -match 'Organization\.Read\.All') $body
Set-Scenario 'connectwise' @{ skuError = 403 }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
Check '403 on subscribedSkus: same plain sentence' ($r.out.licences.reason -match 'Grant the app registration the Organization\.Read\.All') $r.out.licences.reason
Set-Scenario 'connectwise' @{} @{} @('M365-TenantId', 'M365-ClientId', 'M365-ClientSecret')
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
Check 'no M365 secrets: skipped with a note, no Graph calls' ($r.out.status -eq 'success' -and $r.out.licences.reason -match 'not connected' -and @($Mock.Calls | Where-Object { $_.Uri -like '*graph.microsoft.com*' -or $_.Uri -like '*login.microsoftonline*' }).Count -eq 0) $r.out.licences.reason
Set-Scenario 'connectwise' @{ verified = @('fabrikam.com') }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
$body = [string](@(Get-CrWrites)[0].Body | ConvertFrom-Json).body
Check 'tenant not this client''s: licences left out' (-not $r.out.licences.available -and $r.out.licences.reason -match 'Couldn''t confirm' -and $body -notmatch 'Business Premium') $r.out.licences.reason

# ---- 7. empty company ----
Set-Scenario 'connectwise' @{ endpoints = @(); domains = @(); certs = @(); cards = @(); skus = @() }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
$body = [string](@(Get-CrWrites)[0].Body | ConvertFrom-Json).body
Check 'empty: card still renders' ($r.out.status -eq 'success' -and $body -match 'No managed devices are recorded' -and $body -match 'no domains expire within 60 days, and no certificates expire within 30 days' -and $body -match 'There are 0 other open cards') $body
Check 'empty: Microsoft 365 skipped (no domains to confirm the tenant against, company from input)' ($r.out.licences.reason -match 'Couldn''t confirm') $r.out.licences.reason
Set-Scenario 'connectwise' @{ domains = @(); skus = @() } @{ 'CloudRadial-CompanyId' = '7' }
$r = Invoke-Workflow $null
Check 'Routine (no input): company from the secret, 90 days, tenant trusted by the secret' ($r.out.status -eq 'success' -and $r.out.companyId -eq 7 -and $r.out.tickets.days -eq 90 -and $r.out.licences.available -and $r.out.internal_note -match 'CloudRadial-CompanyId secret') "$($r.error) $($r.out.licences.reason)"
Set-Scenario 'connectwise' @{ crEndpointError = 403 }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
Check 'CloudRadial endpoints refused: device section not available, card still posted' ($r.out.status -eq 'success' -and -not $r.out.devices.available -and ([string](@(Get-CrWrites)[0].Body | ConvertFrom-Json).body) -match 'Device data was not available') $r.error

# ---- 8. which company and inputs ----
Set-Scenario
$r = Invoke-Workflow ''
Check 'no company: rejected with a plain sentence' ($r.step -eq 'node-cloudradial' -and $r.out.status -eq 'rejected' -and $r.error -match 'company_id' -and $r.error -match 'CloudRadial-CompanyId' -and @(Get-CrWrites).Count -eq 0) $r.error
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 99 })
Check 'unknown company: error, nothing written' ($r.error -match 'company 99' -and @(Get-CrWrites).Count -eq 0) $r.error
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 'Contoso' })
Check 'company_id not a number: rejected' ($r.step -eq 'node-inputs' -and $r.out.status -eq 'rejected') $r.error
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7; quarter_days = 7 })
Check 'quarter_days too small: rejected' ($r.error -match 'between 30 and 366') $r.error
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7; psa_company_id = 'abc' })
Check 'psa_company_id not a number: rejected' ($r.error -match 'psa_company_id') $r.error
Set-Scenario
$r = Invoke-Workflow ([pscustomobject]@{ trigger = [pscustomobject]@{ company_id = '7'; quarter_days = '120'; preview = 'yes' } })
Check 'trigger wrapper, string numbers and preview yes' ($r.out.status -eq 'pending_confirmation' -and $r.out.tickets.days -eq 120 -and $r.out.cardBody -match 'covers the 120 days') $r.error
$r = Invoke-Workflow ([pscustomobject]@{ company_id = '@CompanyId'; quarter_days = '@days' })
Check 'unfilled @tokens are treated as missing' ($r.step -eq 'node-cloudradial' -and $r.out.status -eq 'rejected') $r.error
Set-Scenario 'connectwise' @{} @{} @('CloudRadial-PrivateKey')
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
Check 'CloudRadial secret missing: named' ($r.step -eq 'node-cloudradial' -and $r.error -match 'CloudRadial-PrivateKey') $r.error

Complete-Test
