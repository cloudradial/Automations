# Strict-mode mock harness for the License Reclamation workflow.
# Runs the three steps embedded in ../license-reclamation.yml (run "node build.js" first) the way the runner does:
# each through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the node output passed
# to the next step as JSON. Mocks Get-AzKeyVaultSecret, Invoke-RestMethod, Get-NodeInput and Set-NodeOutput.
# Placeholder data only (Contoso, Example MSP).
# Usage: pwsh -NoProfile -File license-reclamation/src/test.ps1   (needs node and js-yaml; set JS_YAML_PATH if needed)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

# ---- the steps, from the built .yml ----
$yml = Join-Path $PSScriptRoot '..\license-reclamation.yml'
$js = @'
let y; try { y = require('js-yaml'); } catch { try { y = require(require('path').join(process.argv[2], 'node_modules', 'js-yaml')); } catch { y = require(process.env.JS_YAML_PATH); } }
const a = y.load(require('fs').readFileSync(process.argv[1], 'utf8')).definition.activities;
const o = {}; for (const x of a) if (x.properties && x.properties.script) o[x.id] = x.properties.script;
process.stdout.write(Buffer.from(JSON.stringify(o)).toString('base64'));
'@
$b64 = node -e $js $yml (Join-Path $PSScriptRoot '..\..\_shared')
if ($LASTEXITCODE -ne 0 -or -not $b64) { throw 'Could not read the steps from license-reclamation.yml (is js-yaml available?).' }
$Steps = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) | ConvertFrom-Json
foreach ($id in @('node-inputs', 'node-scan', 'node-card')) { if (-not $Steps.PSObject.Properties[$id]) { throw "Step $id missing from the .yml" } }
Check 'built .yml: shared libraries are injected' ($Steps.'node-scan' -match 'function Connect-Graph' -and $Steps.'node-card' -match 'function Set-CrPlannerCard')

function Get-NodeInput { return $global:LrNodeIn }
function Set-NodeOutput { param($o) $global:LrNodeOut = $o }
function ConvertTo-NodeJson { param($o) return ($o | ConvertTo-Json -Depth 20 | ConvertFrom-Json) }
function Invoke-Step {
    param([string]$Id, $InputObject)
    $global:LrNodeIn = $InputObject; $global:LrNodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps.$Id)) } catch { $err = [string]$_.Exception.Message }
    return @{ out = $(if ($null -ne $global:LrNodeOut) { ConvertTo-NodeJson $global:LrNodeOut } else { $null }); error = $err }
}
# Runs the whole workflow with a run input. Stops at the first step that throws.
function Invoke-Workflow {
    param($RunInput)
    $r = Invoke-Step 'node-inputs' $RunInput; if ($r.error) { return @{ step = 'node-inputs' } + $r }
    $r = Invoke-Step 'node-scan' $r.out; if ($r.error) { return @{ step = 'node-scan' } + $r }
    $r = Invoke-Step 'node-card' $r.out; return @{ step = 'node-card' } + $r
}

# ---- mock tenant ----
$Tenant = '00000000-0000-0000-0000-0000000000c1'
$Now = (Get-Date).ToUniversalTime()
function Iso { param([int]$DaysAgo) return $Now.AddDays(-$DaysAgo).ToString('yyyy-MM-ddTHH:mm:ssZ') }
$Sku = @{ SPB = '11111111-0000-0000-0000-000000000001'; STD = '11111111-0000-0000-0000-000000000002'; PBIFREE = '11111111-0000-0000-0000-000000000003'; CUSTOM = '11111111-0000-0000-0000-000000000004'; FLOW = '11111111-0000-0000-0000-000000000005' }
$SkuList = @(
    @{ skuId = $Sku.SPB; skuPartNumber = 'SPB'; appliesTo = 'User' },
    @{ skuId = $Sku.STD; skuPartNumber = 'O365_BUSINESS_PREMIUM'; appliesTo = 'User' },
    @{ skuId = $Sku.PBIFREE; skuPartNumber = 'POWER_BI_STANDARD'; appliesTo = 'User' },
    @{ skuId = $Sku.CUSTOM; skuPartNumber = 'CONTOSO_CUSTOM_ADDON'; appliesTo = 'User' },
    @{ skuId = $Sku.FLOW; skuPartNumber = 'FLOW_FREE'; appliesTo = 'User' })
function U { param($Name, $Upn, [bool]$Enabled, [int]$Created, $SignIn, [string[]]$Skus)
    $sia = $null; if ($null -ne $SignIn) { $sia = @{ lastSignInDateTime = (Iso $SignIn); lastNonInteractiveSignInDateTime = $null; lastSuccessfulSignInDateTime = $null } }
    return @{ id = [guid]::NewGuid().ToString(); displayName = $Name; userPrincipalName = $Upn; accountEnabled = $Enabled; userType = 'Member'; createdDateTime = (Iso $Created); signInActivity = $sia; assignedLicenses = @($Skus | ForEach-Object { @{ skuId = $Sku[$_]; disabledPlans = @() } }) }
}
$DefaultUsers = @(
    (U 'Alex Active' 'alex@contoso.com' $true 400 5 @('SPB')),
    (U 'Blake Idle' 'blake@contoso.com' $true 400 100 @('SPB', 'PBIFREE')),
    (U 'Casey Leaver' 'casey@contoso.com' $false 400 3 @('STD')),
    (U 'Drew Never' 'drew@contoso.com' $true 200 $null @('CUSTOM')),
    (U 'Eden Newstart' 'eden@contoso.com' $true 10 $null @('SPB')),
    (U 'Frankie Mailonly' 'frankie@contoso.com' $true 400 100 @('STD')),
    (U 'Gale Freebie' 'gale@contoso.com' $true 400 300 @('FLOW')),
    (U 'Harper Unlicensed' 'harper@contoso.com' $true 400 300 @()))
$DefaultCsv = "Report Refresh Date,User Principal Name,Display Name,Is Deleted,Last Activity Date`n2026-10-05,frankie@contoso.com,Frankie Mailonly,False,$($Now.AddDays(-3).ToString('yyyy-MM-dd'))`n2026-10-05,blake@contoso.com,Blake Idle,False,$($Now.AddDays(-120).ToString('yyyy-MM-dd'))"
$ConcealedCsv = "Report Refresh Date,User Principal Name,Display Name,Is Deleted,Last Activity Date`n2026-10-05,9F2A1C0B7E,4D1E0A,False,$($Now.AddDays(-3).ToString('yyyy-MM-dd'))"

$Secrets = @{ 'M365-TenantId' = $Tenant; 'M365-ClientId' = 'app-id'; 'M365-ClientSecret' = 'not-a-real-secret'; 'CloudRadial-BaseUrl' = 'https://api.example-msp.test'; 'CloudRadial-PublicKey' = 'pk'; 'CloudRadial-PrivateKey' = 'sk' }
$global:LrT = @{}
function Set-Scenario {
    param([hashtable]$Over = @{}, [hashtable]$ExtraSecrets = @{})
    $global:LrT = @{
        users = $DefaultUsers; csv = $DefaultCsv; usersError = 0; usersErrorBody = ''; reportsError = 0; skuError = 0
        companies = @(@{ companyId = 7; name = 'Contoso Ltd'; tenantId = $Tenant }, @{ companyId = 8; name = 'Fabrikam'; tenantId = '00000000-0000-0000-0000-0000000000f2' })
        cards = @(); newId = 501
    }
    foreach ($k in $Over.Keys) { $global:LrT[$k] = $Over[$k] }
    $s = $Secrets.Clone(); foreach ($k in $ExtraSecrets.Keys) { $s[$k] = $ExtraSecrets[$k] }
    Reset-Mock $s {
        param($c, $n)
        $T = $global:LrT
        $u = [uri]::UnescapeDataString($c.Uri)
        if ($u -like 'https://login.microsoftonline.com/*') { return [pscustomobject]@{ access_token = 'tok'; expires_in = 3599 } }
        if ($u -like 'https://graph.microsoft.com/*') {
            if ($c.Method -ne 'GET') { throw "Graph write attempted: $($c.Method) $u" }
            if ($u -like '*/subscribedSkus*') { if ($T.skuError) { New-HttpError $T.skuError '{"error":{"message":"Insufficient privileges to complete the operation."}}' }; return (ConvertTo-NodeJson @{ value = $T.skus }) }
            if ($u -like '*/v1.0/users?*') {
                if ($T.usersError) { New-HttpError $T.usersError $T.usersErrorBody }
                # Two pages, to prove paging.
                $all = @($T.users); $half = [int][Math]::Ceiling($all.Count / 2)
                if ($u -match 'page=2') { return (ConvertTo-NodeJson @{ value = @($all | Select-Object -Skip $half) }) }
                return (ConvertTo-NodeJson @{ value = @($all | Select-Object -First $half); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?page=2' })
            }
            if ($u -like '*/reports/getMailboxUsageDetail*') { if ($T.reportsError) { New-HttpError $T.reportsError '{"error":{"message":"Insufficient privileges"}}' }; return $T.csv }
            throw "Unmocked Graph call: $($c.Method) $u"
        }
        if ($u -like 'https://api.example-msp.test/*') {
            $skipZero = ($u -notmatch '\$skip=[1-9]')
            if ($c.Method -eq 'GET' -and $u -match '/v2/odata/company\?\$filter=companyId eq (\d+)') { $id = [int]$Matches[1]; return (ConvertTo-NodeJson @{ value = @($(if ($skipZero) { $T.companies | Where-Object { $_.companyId -eq $id } })) }) }
            if ($c.Method -eq 'GET' -and $u -match '/v2/odata/company') { return (ConvertTo-NodeJson @{ value = @($(if ($skipZero) { $T.companies })) }) }
            if ($c.Method -eq 'GET' -and $u -match '/v2/odata/product\?\$filter=companyId eq (\d+)') { $id = [int]$Matches[1]; return (ConvertTo-NodeJson @{ value = @($(if ($skipZero) { $T.cards | Where-Object { $_.companyId -eq $id } })) }) }
            if ($c.Method -eq 'POST' -and $u -match '/v2/product$') { return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ productId = $T.newId } } }
            if ($c.Method -eq 'PATCH' -and $u -match '/v2/product/(\d+)$') { return [pscustomobject]@{ success = $true } }
            throw "Unmocked CloudRadial call: $($c.Method) $u"
        }
        throw "Unmocked call: $($c.Method) $u"
    }
    $global:LrT.skus = $SkuList
}
function Get-CrWrites { return @($Mock.Calls | Where-Object { $_.Uri -like 'https://api.example-msp.test/*' -and $_.Method -ne 'GET' }) }
function Get-Patch { param($Call, [string]$Field) $ops = @($Call.Body | ConvertFrom-Json); $op = @($ops | Where-Object { $_.path -eq "/$Field" }) | Select-Object -First 1; if ($op) { return $op.value }; return $null }

# ---- 1. preview: nothing written ----
Set-Scenario
$r = Invoke-Workflow ([pscustomobject]@{ days = 60; company_id = 7; preview = $true })
Check 'preview: runs to the end' ($r.step -eq 'node-card' -and -not $r.error) $r.error
Check 'preview: status pending_confirmation, card would be created' ($r.out.status -eq 'pending_confirmation' -and $r.out.cardAction -eq 'would-create') ($r.out | ConvertTo-Json -Depth 6 -Compress)
Check 'preview: no CloudRadial writes' (@(Get-CrWrites).Count -eq 0) (Show-Calls)
Check 'preview: message says preview and no licence changed' ($r.out.message -match '^Preview only' -and $r.out.message -match 'No licence was changed') $r.out.message

# ---- 2. a real run: create the card ----
Set-Scenario
$r = Invoke-Workflow ([pscustomobject]@{ days = 60; company_id = 7 })
$names = @($r.out.users | ForEach-Object { $_.name })
Check 'run: success and card created' ($r.out.status -eq 'success' -and $r.out.cardAction -eq 'created' -and $r.out.productId -eq '501') ($r.error + ' ' + ($r.out | ConvertTo-Json -Depth 6 -Compress))
Check 'run: lists the idle, disabled and never-signed-in users' (($names -join ',') -eq 'Blake Idle,Casey Leaver,Drew Never') ($names -join ',')
Check 'run: skips active, new, mailbox-active, free-only and unlicensed users' (-not ($names | Where-Object { $_ -match 'Alex|Eden|Frankie|Gale|Harper' })) ($names -join ',')
Check 'run: saving is SPB 22.00 + Business Standard 12.50, unknown price left out' ($r.out.monthlySaving -eq 34.5 -and $r.out.licenceCount -eq 3) "$($r.out.monthlySaving) / $($r.out.licenceCount)"
Check 'run: free POWER_BI_STANDARD is not counted' (@($r.out.users | Where-Object { $_.name -eq 'Blake Idle' })[0].licences.Count -eq 1)
$post = @(Get-CrWrites)
Check 'run: exactly one CloudRadial write, a POST to /v2/product' ($post.Count -eq 1 -and $post[0].Method -eq 'POST' -and $post[0].Uri -like '*/v2/product') (Show-Calls)
$card = $post[0].Body | ConvertFrom-Json
Check 'card: company, subject and key' ($card.companyId -eq 7 -and $card.subject -eq 'Reclaim unused Microsoft 365 licences' -and $card.body -match 'license-reclamation') $card.subject
Check 'card: plain sentences with count and saving' ($card.body -match '3 paid licences held by 3 users have not been used in the last 60 days, including 1 disabled account' -and $card.body -match '\$34\.50 a month' -and $card.body -match '\$414\.00 a year') $card.body
Check 'card: says CloudRadial Planner and list estimates, never Microsoft Planner or Teams' ($card.body -match 'CloudRadial Planner card' -and $card.body -match 'list-price estimates' -and $card.body -notmatch 'Microsoft Planner|Teams') $card.body
Check 'card: table rows with status and last sign-in' ($card.body -match 'Disabled but licensed' -and $card.body -match 'Never signed in' -and $card.body -match 'price unknown' -and $card.body -match 'CONTOSO_CUSTOM_ADDON') $card.body
Check 'card: internal only, open, high priority (a disabled account)' ($card.isClientVisible -eq $false -and $card.status -eq 0 -and $card.priority -eq 1 -and $card.notes -match '^Internal:') ($card | ConvertTo-Json -Compress)
Check 'card: no token dump in the summary' ($card.summary -eq '3 paid licences held by 3 users have not been used in 60 days, worth an estimated $34.50 a month.') $card.summary
Check 'graph: read-only (GET only)' (@($Mock.Calls | Where-Object { $_.Uri -like 'https://graph.microsoft.com/*' -and $_.Method -ne 'GET' }).Count -eq 0) (Show-Calls)
Check 'graph: users read across two pages with signInActivity' (@(Get-Calls 'GET' '*graph.microsoft.com/v1.0/users*').Count -eq 2 -and (Get-Calls 'GET' '*users?*')[0].Uri -match 'signInActivity') (Show-Calls)

# ---- 3. price_overrides ----
Set-Scenario
$r = Invoke-Workflow ([pscustomobject]@{ days = 60; company_id = 7; price_overrides = '{"spb": 20, "CONTOSO_CUSTOM_ADDON": 3.5}' })
Check 'price_overrides: replace list prices and price unknown SKUs' ($r.out.monthlySaving -eq 36 -and @(Get-CrWrites)[0].Body -notmatch 'price unknown') "$($r.out.monthlySaving) $($r.error)"

# ---- 4. existing card is updated, not duplicated ----
Set-Scenario @{ cards = @(@{ productId = 321; companyId = 7; subject = 'Old title'; body = '<p>last month</p><p><em>license-reclamation</em></p>' }) }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
$w = @(Get-CrWrites)
Check 'update: PATCH the existing card found by key' ($r.out.cardAction -eq 'updated' -and $w.Count -eq 1 -and $w[0].Method -eq 'PATCH' -and $w[0].Uri -like '*/v2/product/321') (Show-Calls)
Check 'update: subject reset and card reopened' ((Get-Patch $w[0] 'subject') -eq 'Reclaim unused Microsoft 365 licences' -and (Get-Patch $w[0] 'status') -eq 0) $w[0].Body

# ---- 5. nothing reclaimable ----
$active = @((U 'Alex Active' 'alex@contoso.com' $true 400 5 @('SPB')))
Set-Scenario @{ users = $active; cards = @(@{ productId = 321; companyId = 7; subject = 'Reclaim unused Microsoft 365 licences'; body = 'x' }) }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
$w = @(Get-CrWrites)
Check 'empty + card exists: card updated to say nothing to reclaim and closed' ($r.out.status -eq 'success' -and $w.Count -eq 1 -and (Get-Patch $w[0] 'body') -match 'nothing to reclaim' -and (Get-Patch $w[0] 'status') -eq 40) (Show-Calls)
Set-Scenario @{ users = $active }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
Check 'empty + no card: nothing created' ($r.out.status -eq 'success' -and $r.out.cardAction -eq 'none' -and @(Get-CrWrites).Count -eq 0 -and $r.out.message -match 'nothing to reclaim') $r.out.message
Set-Scenario @{ users = @() }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
Check 'no users at all: clean success' ($r.out.status -eq 'success' -and -not $r.error) $r.error

# ---- 6. missing permissions ----
Set-Scenario @{ usersError = 403; usersErrorBody = '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}' }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
Check '403 on sign-in data: fails at the scan with the AuditLog.Read.All sentence' ($r.step -eq 'node-scan' -and $r.error -match 'Grant the app registration the AuditLog\.Read\.All application permission' -and $r.out.status -eq 'error') $r.error
Check '403: no card written' (@(Get-CrWrites).Count -eq 0) (Show-Calls)
Set-Scenario @{ usersError = 403; usersErrorBody = '{"error":{"code":"Authentication_RequestFromNonPremiumTenantOrB2CTenant","message":"Neither tenant is B2C or tenant doesn''t have premium license"}}' }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
Check '403 non-premium tenant: says Entra ID P1 is needed' ($r.error -match 'Entra ID P1') $r.error
Set-Scenario @{ skuError = 403 }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
Check '403 on subscribedSkus: names Organization.Read.All' ($r.step -eq 'node-scan' -and $r.error -match 'Organization\.Read\.All') $r.error
Set-Scenario @{ reportsError = 403 }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
$names = @($r.out.users | ForEach-Object { $_.name })
Check 'no Reports.Read.All: still runs on sign-in only, with a warning on the card' ($r.out.status -eq 'success' -and @($r.out.warnings) -match 'Reports\.Read\.All' -and ($names -contains 'Frankie Mailonly') -and @(Get-CrWrites)[0].Body -match 'Reports.Read.All') ($names -join ',')
Set-Scenario @{ csv = $ConcealedCsv }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
Check 'concealed report names: warning, mailbox data ignored' (@($r.out.warnings) -match 'concealed' -and (@($r.out.users | ForEach-Object { $_.name }) -contains 'Frankie Mailonly')) ($r.out.warnings -join ' | ')
Set-Scenario @{} @{ 'M365-ClientSecret' = '' }
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 7 })
Check 'missing M365 secret: named' ($r.step -eq 'node-scan' -and $r.error -match 'M365-ClientSecret') $r.error

# ---- 7. which company ----
Set-Scenario @{} @{ 'CloudRadial-CompanyId' = '7' }
$r = Invoke-Workflow $null
Check 'Routine (no input): defaults to 60 days, company from CloudRadial-CompanyId secret' ($r.out.status -eq 'success' -and $r.out.companyId -eq 7 -and $r.out.internal_note -match 'CloudRadial-CompanyId secret' -and $r.out.internal_note -match '60-day') $r.error
Set-Scenario
$r = Invoke-Workflow ''
Check 'no input, no secret: company found by tenant match' ($r.out.status -eq 'success' -and $r.out.companyId -eq 7 -and $r.out.internal_note -match 'tenant match') $r.error
Set-Scenario @{ companies = @(@{ companyId = 8; name = 'Fabrikam' }) }
$r = Invoke-Workflow ''
Check 'no company found: plain message naming company_id and the secret' ($r.step -eq 'node-card' -and $r.error -match 'company_id' -and $r.error -match 'CloudRadial-CompanyId' -and @(Get-CrWrites).Count -eq 0) $r.error
Set-Scenario
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 8 })
Check 'company linked to another tenant: refuses, writes nothing' ($r.error -match 'different Microsoft 365 tenant' -and @(Get-CrWrites).Count -eq 0) $r.error
Set-Scenario
$r = Invoke-Workflow ([pscustomobject]@{ company_id = 99 })
Check 'unknown company_id: plain message' ($r.error -match 'company 99' -and @(Get-CrWrites).Count -eq 0) $r.error

# ---- 8. inputs ----
Set-Scenario
$r = Invoke-Workflow ([pscustomobject]@{ days = 'sixty' })
Check 'days not a number: rejected' ($r.step -eq 'node-inputs' -and $r.out.status -eq 'rejected' -and $r.error -match 'whole number') $r.error
$r = Invoke-Workflow ([pscustomobject]@{ days = 5 })
Check 'days too small: rejected' ($r.error -match 'between 14 and 365') $r.error
$r = Invoke-Workflow ([pscustomobject]@{ price_overrides = '{not json' })
Check 'bad price_overrides JSON: rejected' ($r.error -match 'price_overrides') $r.error
$r = Invoke-Workflow ([pscustomobject]@{ price_overrides = [pscustomobject]@{ SPB = 'cheap' } })
Check 'bad override price: rejected' ($r.error -match 'SPB') $r.error
$r = Invoke-Workflow ([pscustomobject]@{ days = '@days'; company_id = '@CompanyId' })
Check 'unfilled @tokens are treated as missing' ($r.step -ne 'node-inputs') $r.error
Set-Scenario
$r = Invoke-Workflow ([pscustomobject]@{ trigger = [pscustomobject]@{ days = '90'; company_id = '7' } })
Check 'trigger wrapper and string numbers accepted' ($r.out.status -eq 'success' -and $r.out.internal_note -match '90-day') $r.error

Complete-Test
