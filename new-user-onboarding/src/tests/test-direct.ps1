# Strict-mode harness for the direct workflow's Receive form data and Check and plan nodes,
# plus the agent workflow's Read the request node. Mocks the runner, Key Vault and Graph.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$dir = $(if ($env:NUO_NODE_DIR) { $env:NUO_NODE_DIR } else { $PSScriptRoot })
$env:RUNNER_KV_NAME = 'kv-test'
$tenant = '00000000-0000-0000-0000-000000000000'

function Get-NodeInput { return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText)
    if ($global:Secrets.Contains($Name)) { return $global:Secrets[$Name] }; return $null }
function New-404 { $ex = [System.Exception]::new('Not Found'); $ex | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = 404 }); return $ex }
function Invoke-RestMethod { param($Method, $Uri, $Headers, $Body)
    $global:Calls += "$Method $Uri"
    if ($Uri -like 'https://login.microsoftonline.com/*') { return [pscustomobject]@{ access_token = 'mock' } }
    if ($Uri -like '*/v1.0/organization*') { return [pscustomobject]@{ value = @([pscustomobject]@{ verifiedDomains = @([pscustomobject]@{ name = 'contoso.com'; isDefault = $true }) }) } }
    if ($Uri -like '*/v1.0/users/manager%40contoso.com*') { return [pscustomobject]@{ id = 'm1'; displayName = 'Pat Manager'; mail = 'manager@contoso.com'; userPrincipalName = 'manager@contoso.com' } }
    if ($Uri -like '*/v1.0/users/*') { throw (New-404) }
    if ($Uri -like '*/v1.0/users?*') { return [pscustomobject]@{ value = @() } }
    if ($Uri -like '*/v1.0/subscribedSkus*') { return [pscustomobject]@{ value = @(
        [pscustomobject]@{ skuId = '11111111-1111-1111-1111-111111111111'; skuPartNumber = 'SPB'; consumedUnits = 1; prepaidUnits = [pscustomobject]@{ enabled = 5 }; servicePlans = @([pscustomobject]@{ servicePlanName = 'EXCHANGE_S_STANDARD' }) },
        [pscustomobject]@{ skuId = '22222222-2222-2222-2222-222222222222'; skuPartNumber = 'O365_BUSINESS_ESSENTIALS'; consumedUnits = 0; prepaidUnits = [pscustomobject]@{ enabled = 2 }; servicePlans = @([pscustomobject]@{ servicePlanName = 'EXCHANGE_S_STANDARD' }) }) } }
    if ($Uri -like 'https://cr.example.com/v2/odata/company*') { return [pscustomobject]@{ value = @([pscustomobject]@{ companyId = 468; name = $global:CrCompanyName }) } }
    if ($Uri -like 'https://cr.example.com/v2/odata/user*') { return [pscustomobject]@{ value = @() } }
    if ($Uri -like '*/v1.0/groups?*') { return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'g1'; displayName = 'Sales Team'; groupTypes = @(); mailEnabled = $false; securityEnabled = $true; isAssignableToRole = $false; onPremisesSyncEnabled = $false }) } }
    throw "Unmocked call: $Method $Uri"
}

# Mimics the runner passing a node's output to the next node as JSON.
function RoundTrip { param($o) return ($o | ConvertTo-Json -Depth 20 | ConvertFrom-Json) }
$parse = Get-Content -Raw (Join-Path $dir 'node-node-parse.ps1')
$gates = Get-Content -Raw (Join-Path $dir 'node-node-gates.ps1')

function Invoke-Direct { param([hashtable]$Body, [hashtable]$Secrets)
    $global:Secrets = @{ 'M365-TenantId' = $tenant; 'M365-ClientId' = 'cid'; 'M365-ClientSecret' = 'sec' } + $Secrets
    $global:Calls = @()
    $global:NodeIn = [pscustomobject]@{ trigger = (RoundTrip $Body) }
    & ([scriptblock]::Create($parse))
    $global:NodeIn = RoundTrip $global:NodeOut
    & ([scriptblock]::Create($gates))
    return (RoundTrip $global:NodeOut)
}

$base = @{ ticketId = '12345'; companyName = 'Contoso'; companyTenantId = $tenant; requestedBy = 'manager@contoso.com'; requestedByIsAdmin = 'true'
    firstName = 'Sam'; lastName = 'Starter'; startDate = '2026-10-12'; managerEmail = 'manager@contoso.com'; needsM365License = 'Yes'
    m365License = 'Microsoft 365 Business Premium'; securityGroups = 'Sales Team'; officeLocation = '@officeLocation'; confirm = 'false' }
$fail = 0
function Check { param($Name, [bool]$Ok, $Detail) if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name :: $Detail"; $script:fail++ } }
function Plan { param($o) return (@($o.plan) -join ' | ') }

$o = Invoke-Direct $base @{}
Check 'no usage-location secret -> US' ((Plan $o) -match 'usage location US') "$($o.status) $($o.reason) $(Plan $o)"
Check 'manager resolved' ((Plan $o) -match 'Set manager to manager@contoso.com') (Plan $o)
Check 'form licence used' ((Plan $o) -match 'Assign licence SPB') (Plan $o)
Check 'preview status' ($o.status -eq 'pending_confirmation') $o.status

$o = Invoke-Direct $base @{ 'Onboarding-UsageLocation' = ' gb ' }
Check 'secret usage location -> GB' ((Plan $o) -match 'usage location GB' -and $o.fields.usageLocation -eq 'GB') "$($o.status) $(Plan $o)"

$b = $base.Clone(); $b['usageLocation'] = 'ca'
$o = Invoke-Direct $b @{ 'Onboarding-UsageLocation' = 'GB' }
Check 'form usage location beats secret' ((Plan $o) -match 'usage location CA') (Plan $o)

$o = Invoke-Direct $base @{ 'Onboarding-UsageLocation' = 'USA' }
Check 'bad usage location -> incomplete' ($o.status -eq 'incomplete' -and $o.reason -match 'two-letter') "$($o.status) $($o.reason)"

$b = $base.Clone(); $b.Remove('m365License')
$o = Invoke-Direct $b @{ 'Onboarding-DefaultLicenceSku' = 'O365_BUSINESS_ESSENTIALS' }
Check 'default licence used' ((Plan $o) -match 'Assign licence O365_BUSINESS_ESSENTIALS' -and (@($o.warnings) -join ' ') -match 'runner default') "$($o.status) $(Plan $o) / $(@($o.warnings) -join ' ')"
Check 'default licence recorded on fields' ($o.fields.licenseSku -eq 'O365_BUSINESS_ESSENTIALS') $o.fields.licenseSku

$b = $base.Clone(); $b['m365License'] = '@m365License'
$o = Invoke-Direct $b @{}
Check 'no licence, no default -> warning only' ((Plan $o) -notmatch 'Assign licence' -and (@($o.warnings) -join ' ') -match 'No licence was requested') "$(Plan $o) / $(@($o.warnings) -join ' ')"

$b = $base.Clone(); $b.Remove('m365License'); $b['needsM365License'] = 'No'
$o = Invoke-Direct $b @{ 'Onboarding-DefaultLicenceSku' = 'SPB' }
Check 'licence No -> default ignored' ((Plan $o) -notmatch 'Assign licence') (Plan $o)

# A form Action: answers as top-level keys by the stock form's Field IDs, plus the portal's own objects.
$action = @{ firstName = 'Sam'; lastName = 'Starter'; department = 'Sales'; startDate = '2026-11-02'; companyFileAccess = @('Sales Team')
    mailDistributionGroups = $null; doesTheUserRequireAnEmailAccount = 'Yes'; email = $null
    ticket = @{ id = 106329; subject = 'Add a New User' }; company = @{ id = 468; name = 'Contoso'; psaId = '189'; tenantId = $tenant }
    user = @{ id = 7; name = 'Pat Manager'; email = 'manager@contoso.com'; isAdmin = $true } }
$o = Invoke-Direct $action @{}
Check 'action: read from the portal objects' ($o.source -eq 'action' -and $o.ticketId -eq '106329' -and $o.fields.companyId -eq '468' -and $o.fields.submittedByUpn -eq 'manager@contoso.com') "$($o.source) $($o.ticketId) $($o.fields.companyId) $($o.fields.submittedByUpn)"
Check 'action: tenant gate passes, preview only' ($o.status -eq 'pending_confirmation' -and -not $o.confirm) "$($o.status) $($o.reason)"
Check 'action: stock group Field ID used' ((Plan $o) -match 'Add to group Sales Team') (Plan $o)
Check 'action: note goes to the form ticket' ((Plan $o) -match 'internal note to PSA ticket 106329') (Plan $o)

$b = $action.Clone(); $b['confirm'] = 'true'; $b['requestedBy'] = 'someone@else.com'; $b['companyTenantId'] = '11111111-1111-1111-1111-111111111111'; $b['ticketId'] = '1'; $b['psa'] = 'autotask'
$o = Invoke-Direct $b @{}
Check 'action: typed confirm, requester, tenant, ticket and psa ignored' (-not $o.confirm -and $o.status -eq 'pending_confirmation' -and $o.fields.submittedByUpn -eq 'manager@contoso.com' -and $o.ticketId -eq '106329' -and $o.fields.psa -eq '') "$($o.confirm) $($o.status) $($o.fields.submittedByUpn) $($o.ticketId) $($o.fields.psa)"

$o = Invoke-Direct $action @{ 'Onboarding-Confirm' = 'true' }
Check 'action: Onboarding-Confirm secret confirms' ($o.confirm -and $o.confirmSource -eq 'secret' -and $o.status -eq 'ok') "$($o.confirm) $($o.confirmSource) $($o.status)"

$b = $action.Clone(); $b['company'] = @{ id = 468; name = 'Contoso'; tenantId = '11111111-1111-1111-1111-111111111111' }
$o = Invoke-Direct $b @{}
Check 'action: other tenant rejected' ($o.status -eq 'rejected' -and $o.reason -match 'Cross-tenant') "$($o.status) $($o.reason)"

$cr = @{ 'CloudRadial-BaseUrl' = 'https://cr.example.com'; 'CloudRadial-PublicKey' = 'p'; 'CloudRadial-PrivateKey' = 'k' }
$global:CrCompanyName = 'Contoso'
$o = Invoke-Direct $action $cr
Check 'action: portal user in the matching CloudRadial company' ($o.crCompanyId -eq '468' -and (Plan $o) -match 'portal user in Contoso') "$($o.crCompanyId) $(Plan $o)"
$global:CrCompanyName = 'Fabrikam'
$o = Invoke-Direct $action $cr
Check 'action: CloudRadial company of another client -> no portal user' ($o.crCompanyId -eq '' -and (Plan $o) -notmatch 'portal user' -and (@($o.followUp) -join ' ') -match "is 'Fabrikam', not 'Contoso'") "$($o.crCompanyId) $(Plan $o) / $(@($o.followUp) -join ' ')"

$b = $base.Clone(); $b['confirm'] = 'true'
$o = Invoke-Direct $b @{}
Check 'webhook: body confirm still works' ($o.confirm -and $o.confirmSource -eq 'request' -and $o.source -eq 'webhook' -and $o.status -eq 'ok') "$($o.confirm) $($o.confirmSource) $($o.source) $($o.status)"

# Agent workflow: Read the request puts the manager in the briefing.
$global:NodeIn = (Get-Content -Raw (Join-Path $dir 'agentwf-test.json') | ConvertFrom-Json)
& ([scriptblock]::Create((Get-Content -Raw (Join-Path $dir 'agentwf-inputs.ps1'))))
Check 'agent briefing has manager' ($global:NodeOut.briefing -match '- Manager: manager@contoso.com') $global:NodeOut.briefing
$global:NodeIn = [pscustomobject]@{ firstName = 'Sam'; lastName = 'Starter'; managerEmail = '@managerEmail' }
& ([scriptblock]::Create((Get-Content -Raw (Join-Path $dir 'agentwf-inputs.ps1'))))
Check 'agent briefing: unset manager listed as not answered' ($global:NodeOut.briefing -match 'Not answered: .*Manager') $global:NodeOut.briefing

if ($fail) { Write-Host "$fail failed"; exit 1 } else { Write-Host 'all passed' }
