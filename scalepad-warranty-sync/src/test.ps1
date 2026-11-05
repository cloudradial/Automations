# Strict-mode harness for ScalePad Warranty Sync.
# Runs the PowerShell step exactly as it is in scalepad-warranty-sync.yml (shared CloudRadial library included),
# through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the runner Key Vault,
# Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked. Placeholder data only (Contoso, Example MSP,
# Fabrikam, Northwind, Adatum).
# Test variables start with T: the step runs in a child scope of this script, and a step variable of the
# same name would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File scalepad-warranty-sync/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$TYml = Join-Path $PSScriptRoot '..\scalepad-warranty-sync.yml'
$TJs = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={ids:d.definition.activities.map(a=>a.id).join(',')};for(const a of d.definition.activities){if(a.type==='powershell-script'){o[a.id]=a.properties.script;o[a.id+'.params']=JSON.stringify(a.properties.parameters)}};o.webhook=String(d.definition.activities.find(a=>a.id==='start').properties.webhookEnabled);console.log(JSON.stringify(o));"
$TSteps = (& $node -e $TJs $TYml) | ConvertFrom-Json -AsHashtable
Check 'workflow is start, node-sync, end' ($TSteps['ids'] -eq 'start,node-sync,end') $TSteps['ids']
Check 'node-sync is unbound (reads Get-NodeInput)' ($TSteps['node-sync.params'] -eq '[]') $TSteps['node-sync.params']
Check 'webhook ships disabled' ($TSteps['webhook'] -eq 'false')
Check 'the shared CloudRadial library is pasted in' ($TSteps['node-sync'] -like '*function Set-CrPlannerCard*')

# ---- runner mocks ----
$global:NodeIn = $null; $global:NodeOut = $null
function Get-NodeInput { return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Invoke-Sync {
    param($Body)
    $global:NodeIn = $(if ($null -eq $Body) { $null } else { ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json) })
    $global:NodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $TSteps['node-sync'])) } catch { $err = [string]$_.Exception.Message }
    $o = $null; if ($null -ne $global:NodeOut) { $o = ($global:NodeOut | ConvertTo-Json -Depth 12 | ConvertFrom-Json) }
    return @{ out = $o; error = $err }
}

# ---- placeholder portal and ScalePad ----
$TCr = 'https://api.cloudradial.example'; $TSp = 'https://api.scalepad.example'
$TSec = @{ 'CloudRadial-BaseUrl' = $TCr; 'CloudRadial-PublicKey' = 'pub'; 'CloudRadial-PrivateKey' = 'priv'; 'ScalePad-ApiUrl' = "$TSp/"; 'ScalePad-ApiKey' = 'spkey' }
$TData = @{
    companies = @(@{ companyId = 2; name = 'Contoso Ltd' }, @{ companyId = 3; name = 'Example MSP' }, @{ companyId = 4; name = 'Fabrikam Inc' }, @{ companyId = 5; name = 'Northwind Traders' }, @{ companyId = 6; name = 'Adatum' })
    clients   = @(@{ id = 'sp-contoso'; name = 'Contoso Limited' }, @{ id = 'sp-example'; name = 'Example MSP' }, @{ id = 'sp-fab'; name = 'Fabrikam' }, @{ id = 'sp-nw1'; name = 'Northwind Traders' }, @{ id = 'sp-nw2'; name = 'Northwind Traders Ltd' }, @{ id = 'sp-other'; name = 'Tailspin Toys' })
    life      = @{
        'sp-contoso' = @(@{ serial_number = 'A1'; warranty_expiry_date = '2024-01-01T00:00:00Z'; purchase_date = '2020-01-01T00:00:00Z' }, @{ serial_number = 'A2'; warranty_expiry_date = '2030-01-01T00:00:00Z'; purchase_date = '2025-01-01T00:00:00Z' },
            @{ serial_number = 'A3'; warranty_expiry_date = '2025-06-01T00:00:00Z' }, @{ serial_number = 'A6'; warranty_expiry_date = '2022-03-01T00:00:00Z' }, @{ serial_number = 'Z9'; warranty_expiry_date = '2023-01-01T00:00:00Z' })
        'sp-example' = @(@{ serial_number = 'C1'; warranty_expiry_date = '2031-01-01T00:00:00Z' })
        'sp-fab'     = @(@{ serial_number = 'F1'; warranty_expiry_date = '2024-05-01T00:00:00Z' })
        'sp-nw1'     = @(@{ serial_number = 'N1'; warranty_expiry_date = '2029-01-01T00:00:00Z' })
    }
    endpoints = @{
        2 = @(@{ companyEndpointId = 11; serialNumber = 'A1'; name = 'Contoso-LT01'; expirationDate = $null; manufacturedDate = $null; isVirtual = $false },
            @{ companyEndpointId = 12; serialNumber = 'A2'; name = 'Contoso-LT02'; expirationDate = '2030-01-01T00:00:00Z'; manufacturedDate = '2025-01-01T00:00:00Z'; isVirtual = $false },
            @{ companyEndpointId = 13; serialNumber = ' a3 '; name = 'Contoso-DT03'; expirationDate = '2026-12-01T00:00:00Z'; manufacturedDate = '2021-01-01T00:00:00Z'; isVirtual = $false },
            @{ companyEndpointId = 14; serialNumber = ''; name = 'Contoso-VM01'; expirationDate = '2020-01-01T00:00:00Z'; manufacturedDate = $null; isVirtual = $true },
            @{ companyEndpointId = 15; serialNumber = 'B5'; name = 'Contoso-DT05'; expirationDate = '2023-01-01T00:00:00Z'; manufacturedDate = $null; isVirtual = $false },
            @{ companyEndpointId = 16; serialNumber = 'A6'; name = 'Contoso-Old & Slow'; expirationDate = '2022-03-01T00:00:00Z'; manufacturedDate = '2016-01-01T00:00:00Z'; isVirtual = $false })
        3 = @(@{ companyEndpointId = 31; serialNumber = 'C1'; name = 'Example-PC1'; expirationDate = '2031-01-01T00:00:00Z'; manufacturedDate = '2026-01-01T00:00:00Z'; isVirtual = $false })
        4 = @(@{ companyEndpointId = 41; serialNumber = 'F1'; name = 'Fabrikam-PC1'; expirationDate = '2024-05-01T00:00:00Z'; manufacturedDate = '2019-01-01T00:00:00Z'; isVirtual = $false })
        5 = @(@{ companyEndpointId = 51; serialNumber = 'N1'; name = 'Northwind-PC1'; expirationDate = $null; manufacturedDate = $null; isVirtual = $false })
    }
    products  = @{
        2 = @(@{ productId = 201; companyId = 2; subject = 'Endpoint Hardware Refresh - Replace'; status = 'Proposed'; body = '<ul><li><strong>Contoso-Old &amp; Slow</strong> (A6) is 10 years old.</li></ul>' })
        3 = @(@{ productId = 301; companyId = 3; subject = 'Endpoint Warranty Renewal'; status = 'Proposed'; body = '<p>old</p><p><em>Warranty Renewal Card: company 3</em></p>' })
        4 = @(@{ productId = 401; companyId = 4; subject = 'Endpoint Warranty Renewal'; status = 'Completed'; body = '<p>none</p>' })
        5 = @()
    }
}
$TFlags = @{ sp422 = $false }
$THandler = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    if ($c.Method -eq 'GET' -and $u -like "$TSp/*") {
        if ($c.Headers['x-api-key'] -ne 'spkey') { New-HttpError 401 }
        if ($TFlags.sp422 -and $u -like '*lifecycles*' -and $u -match 'page_size=200') { New-HttpError 422 '{"error":"page_size"}' }
        if ($u -like "$TSp/core/v1/clients*") { return [pscustomobject]@{ data = @($TData.clients | ForEach-Object { [pscustomobject]$_ }); next_cursor = $null } }
        if ($u -like "$TSp/lifecycle-manager/v1/assets/hardware/lifecycles*") {
            $cl = [regex]::Match($u, 'filter\[client_id\]=eq:([\w-]+)').Groups[1].Value
            $rows = if ($TData.life.Contains($cl)) { @($TData.life[$cl]) } else { @() }
            return [pscustomobject]@{ data = @($rows | ForEach-Object { [pscustomobject]$_ }); next_cursor = $null }
        }
        throw "unmocked ScalePad GET $u"
    }
    if ($c.Method -eq 'GET' -and $u -like "$TCr/v2/odata/company?*") { return [pscustomobject]@{ value = @($TData.companies | ForEach-Object { [pscustomobject]$_ }) } }
    if ($c.Method -eq 'GET' -and $u -match "^$([regex]::Escape($TCr))/v2/odata/endpoint\?\`$filter=companyId eq (\d+)") { $k = [int]$Matches[1]; return [pscustomobject]@{ value = @(@($(if ($TData.endpoints.Contains($k)) { $TData.endpoints[$k] })) | Where-Object { $_ } | ForEach-Object { [pscustomobject]$_ }) } }
    if ($c.Method -eq 'GET' -and $u -match "^$([regex]::Escape($TCr))/v2/odata/product\?\`$filter=companyId eq (\d+)") { $k = [int]$Matches[1]; return [pscustomobject]@{ value = @(@($(if ($TData.products.Contains($k)) { $TData.products[$k] })) | Where-Object { $_ } | ForEach-Object { [pscustomobject]$_ }) } }
    if ($c.Method -eq 'PATCH' -and $u -like "$TCr/v2/endpoint/id/*") { return [pscustomobject]@{ success = $true } }
    if ($c.Method -eq 'POST' -and $u -eq "$TCr/v2/product") { return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ productId = 900 } } }
    if ($c.Method -eq 'PATCH' -and $u -like "$TCr/v2/product/*") { return [pscustomobject]@{ success = $true } }
    throw "unmocked $($c.Method) $u"
}
function Get-Patch { param([int]$Id) $p = @(Get-Calls 'PATCH' "*/v2/endpoint/id/$Id"); if (-not $p.Count) { return $null }; return @((Read-Body $p[0])) }
# ConvertFrom-Json turns ISO date strings into [datetime]; read them back as the ISO text that was sent.
function Get-Op { param($Ops, [string]$Path) $o = @($Ops | Where-Object { $_.path -eq $Path }); if (-not $o.Count) { return $null }; $v = $o[0].value; if ($v -is [datetime]) { return $v.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }; return [string]$v }

# ---- 1. preview (no input): reads only ----
Reset-Mock $TSec.Clone() $THandler
$r = Invoke-Sync $null
Check 'preview: no error' (-not $r.error) $r.error
Check 'preview: nothing written' (@($Mock.Calls | Where-Object { $_.Method -ne 'GET' }).Count -eq 0) (Show-Calls)
Check 'preview: says nothing was changed and how to confirm' ($r.out.message -like 'Preview, nothing was changed.*' -and $r.out.message -like '*"confirm": true*') $r.out.message
Check 'preview: counts the planned changes' ($r.out.counts.warrantyUpdated -eq 2 -and $r.out.counts.purchaseDateFilled -eq 1 -and $r.out.counts.cardsCreated -eq 1 -and $r.out.counts.cardsClosed -eq 1 -and $r.out.counts.cardsReopened -eq 1) ($r.out.counts | ConvertTo-Json -Compress)
Check 'preview: output contract fields' ($null -ne $r.out.status -and $null -ne $r.out.public_note -and $null -ne $r.out.internal_note -and $null -ne $r.out.actions -and $null -ne $r.out.warnings) ($r.out | ConvertTo-Json -Compress)
Check 'duplicate ScalePad names are held with the ids to pair' (@($r.out.warnings | Where-Object { $_ -like 'Northwind Traders (5) matches 2 ScalePad clients*sp-nw1*sp-nw2*' }).Count -eq 1) ($r.out.warnings -join ' | ')
Check 'unmatched ScalePad clients are counted in the message' ($r.out.message -like '*ScalePad clients have no CloudRadial company*') $r.out.message

# ---- 2. confirm: warranty and purchase dates, the card ----
Reset-Mock $TSec.Clone() $THandler
$r = Invoke-Sync @{ confirm = $true }
Check 'confirm: no error' (-not $r.error -and $r.out.status -eq 'ok') "$($r.error) $($r.out.status)"
$p11 = Get-Patch 11
Check 'blank warranty and purchase date filled (json-patch to /v2/endpoint/id/11)' ($null -ne $p11 -and (Get-Op $p11 '/expirationDate') -eq '2024-01-01T00:00:00Z' -and (Get-Op $p11 '/manufacturedDate') -eq '2020-01-01T00:00:00Z' -and (@(Get-Calls 'PATCH' '*/v2/endpoint/id/11')[0].ContentType -eq 'application/json-patch+json')) ($p11 | ConvertTo-Json -Compress)
Check 'matching dates are left alone' ($null -eq (Get-Patch 12)) (Show-Calls)
$p13 = Get-Patch 13
Check 'a differing warranty is replaced; the serial match ignores case and spaces; a set purchase date is kept' ($null -ne $p13 -and (Get-Op $p13 '/expirationDate') -eq '2025-06-01T00:00:00Z' -and $null -eq (Get-Op $p13 '/manufacturedDate')) ($p13 | ConvertTo-Json -Compress)
Check 'no serial and not-in-ScalePad computers are not patched' ($null -eq (Get-Patch 14) -and $null -eq (Get-Patch 15)) (Show-Calls)
$post = @(Get-Calls 'POST' '*/v2/product')
Check 'one warranty card created, for Contoso only' ($post.Count -eq 1 -and (Read-Body $post[0]).companyId -eq 2) (Show-Calls)
$card = Read-Body $post[0]
Check 'card subject and fields' ($card.subject -eq 'Endpoint Warranty Renewal' -and $card.category -eq 'Efficiency' -and $card.productCategoryId -eq 7 -and $card.priority -eq 0 -and $card.isClientVisible -eq $false) ($card | ConvertTo-Json -Compress)
Check 'card lists the expired computers (updated date used)' ($card.body -like '*<strong>Contoso-LT01</strong> (A1): warranty ended 1 Jan 2024*' -and $card.body -like '*Contoso-DT03*warranty ended 1 Jun 2025*' -and $card.body -like '*<strong>Contoso-DT05</strong> (B5): warranty ended 1 Jan 2023*') $card.body
Check 'card leaves out the future warranty, the VM and the computer on the Replace card' ($card.body -notlike '*Contoso-LT02*' -and $card.body -notlike '*Contoso-VM01*' -and $card.body -notlike '*Old &amp; Slow*' -and $card.body -like '*One more computer is out of warranty and already on the Endpoint Hardware Refresh - Replace card*') $card.body
Check 'card summary counts 3' ($card.summary -eq '3 computers are out of warranty.') $card.summary
Check 'the card never mentions ScalePad' (("$($card.subject) $($card.body) $($card.summary) $($card.notes)") -notmatch '(?i)scale\s*pad') "$($card.body) $($card.notes)"
Check 'card carries the marker' ($card.body -like '*Warranty Renewal Card: company 2*') $card.body
$p3 = @(Get-Calls 'PATCH' '*/v2/product/301')
Check 'Example MSP: nothing out of warranty, so its open card is closed' ($p3.Count -eq 1 -and (Get-Op (Read-Body $p3[0]) '/status') -eq '40') (Show-Calls)
$p4 = @(Get-Calls 'PATCH' '*/v2/product/401')
Check 'Fabrikam: a completed card is reopened when a warranty has ended' ($p4.Count -eq 1 -and (Get-Op (Read-Body $p4[0]) '/status') -eq '0' -and (Get-Op (Read-Body $p4[0]) '/body') -like '*Fabrikam-PC1*') (Show-Calls)
Check 'an update never sets priority (the partner''s choice is kept)' ($null -eq (Get-Op (Read-Body $p4[0]) '/priority')) ((Read-Body $p4[0]) | ConvertTo-Json -Compress)
Check 'Northwind (held) and Adatum (no client) are not touched' (@(Get-Calls 'GET' '*companyId eq 5*').Count -eq 0 -and @(Get-Calls 'GET' '*companyId eq 6*').Count -eq 0) (Show-Calls)
Check 'confirm: counts' ($r.out.counts.companies -eq 3 -and $r.out.counts.warrantyUpdated -eq 2 -and $r.out.counts.notInCloudRadial -eq 1 -and $r.out.counts.noSerial -eq 1 -and $r.out.counts.outOfWarranty -eq 4) ($r.out.counts | ConvertTo-Json -Compress)

# ---- 3. overwriteWarranty false ----
Reset-Mock $TSec.Clone() $THandler
$r = Invoke-Sync @{ confirm = $true; overwriteWarranty = $false; companyIds = '2' }
$p13 = Get-Patch 13
Check 'overwriteWarranty false: a differing date is kept and reported' ($null -eq $p13 -and $r.out.counts.differencesKept -eq 1 -and @($r.out.warnings | Where-Object { $_ -like '*Contoso-DT03*Left as is*' }).Count -eq 1) ($r.out.warnings -join ' | ')
Check 'overwriteWarranty false: a blank warranty is still filled' ((Get-Op (Get-Patch 11) '/expirationDate') -eq '2024-01-01T00:00:00Z') (Show-Calls)
Check 'companyIds limits the run' ($r.out.counts.companies -eq 1 -and @(Get-Calls 'GET' '*companyId eq 3*').Count -eq 0) (Show-Calls)

# ---- 4. pairs settles a duplicate name ----
Reset-Mock $TSec.Clone() $THandler
$r = Invoke-Sync @{ confirm = $true; companyIds = '5'; pairs = @{ '5' = 'sp-nw1' } }
Check 'pairs: the held company is synced with the chosen client' ((Get-Op (Get-Patch 51) '/expirationDate') -eq '2029-01-01T00:00:00Z' -and @($r.out.warnings | Where-Object { $_ -like '*Northwind*matches 2*' }).Count -eq 0) "$($r.error) $(Show-Calls)"
Check 'pairs: no card when nothing is out of warranty' (@(Get-Calls 'POST' '*/v2/product').Count -eq 0) (Show-Calls)
Reset-Mock $TSec.Clone() $THandler
$r = Invoke-Sync @{ companyIds = '6' }
Check 'a company with no ScalePad client says how to pair it' ($r.out.message -like 'No CloudRadial company matched*' -and @($r.out.warnings | Where-Object { $_ -like 'Company 6 has no ScalePad client*' }).Count -eq 1) "$($r.out.message) $($r.out.warnings -join ' | ')"

# ---- 5. card switches ----
Reset-Mock $TSec.Clone() $THandler
$r = Invoke-Sync @{ confirm = $true; companyIds = '2'; warrantyCard = $false }
Check 'warrantyCard false: dates only, no card calls' (@(Get-Calls 'POST' '*/v2/product').Count -eq 0 -and @(Get-Calls 'GET' '*/v2/odata/product*').Count -eq 0 -and $null -ne (Get-Patch 11)) (Show-Calls)
Reset-Mock $TSec.Clone() $THandler
$r = Invoke-Sync @{ confirm = $true; companyIds = '2'; skipReplaceCard = $false; expiringWithinDays = 30 }
$card = Read-Body @(Get-Calls 'POST' '*/v2/product')[0]
Check 'skipReplaceCard false: the Replace-card computer is listed too' ($card.body -like '*Contoso-Old &amp; Slow*' -and $card.summary -like '4 computers*') $card.summary

# ---- 6. secrets, ScalePad page size ----
Reset-Mock @{ 'CloudRadial-BaseUrl' = $TCr; 'CloudRadial-PublicKey' = 'pub'; 'CloudRadial-PrivateKey' = 'priv' } $THandler
$r = Invoke-Sync $null
Check 'missing ScalePad secrets are named and nothing is called' ($r.out.status -eq 'error' -and $r.error -like '*ScalePad-ApiUrl, ScalePad-ApiKey*' -and $Mock.Calls.Count -eq 0) "$($r.error) $(Show-Calls)"
$TSuffixed = @{}; foreach ($k in $TSec.Keys) { $TSuffixed["$k-29684092"] = $TSec[$k] }
Reset-Mock $TSuffixed $THandler
$r = Invoke-Sync @{ secretSuffix = '29684092'; companyIds = '3' }
Check 'secretSuffix reads the company-scoped secrets' (-not $r.error -and $r.out.counts.companies -eq 1) "$($r.error)"
$TFlags.sp422 = $true
Reset-Mock $TSec.Clone() $THandler
$r = Invoke-Sync @{ companyIds = '3' }
$TFlags.sp422 = $false
Check 'ScalePad 422 on page_size 200 retries at 100' (-not $r.error -and $r.out.counts.matched -eq 1 -and @(Get-Calls 'GET' '*page_size=100*').Count -ge 1) "$($r.error) $(Show-Calls)"

Complete-Test
