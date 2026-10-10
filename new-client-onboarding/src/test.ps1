# Strict-mode harness for new-client-onboarding.yml. Runs the four steps exactly as they are in the .yml
# (extracted by build.js --extract), each through & ([scriptblock]::Create(...)) under
# Set-StrictMode -Version Latest, passing each step's output to the next as JSON the way the runner does.
# Mocks Get-AzKeyVaultSecret, Invoke-RestMethod, Get-NodeInput, Set-NodeOutput and Start-Sleep.
# Placeholder data only (Contoso, Example MSP).
# Usage: pwsh -NoProfile -File new-client-onboarding/src/test.ps1
#        (needs node and js-yaml; set JS_YAML_PATH if js-yaml isn't installed in _shared)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:RUNNER_KV_NAME = 'kv-test'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("nco-test-" + [guid]::NewGuid().ToString('N'))
& node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { throw 'new-client-onboarding.yml is out of date. Run node build.js first.' }
& node (Join-Path $PSScriptRoot 'build.js') --extract $tmp | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the steps.' }
$StepIds = @('node-inputs', 'node-check', 'node-m365', 'node-apply')
$Steps = @{}; foreach ($s in $StepIds) { $Steps[$s] = Get-Content -Raw (Join-Path $tmp "$s.ps1") }
Remove-Item -Recurse -Force $tmp

$Tally = @{ pass = 0; fail = 0 }
$Mock = @{ Secrets = @{}; Calls = (New-Object System.Collections.ArrayList); Opt = @{}; Notes = @{} }
# Notes written to each ticket (kept across runs until Clear-Notes), read back by the shared retry guard.
function Add-MockNote { param([string]$T, [string]$Text, [bool]$Public) if (-not $Mock.Notes.Contains($T)) { $Mock.Notes[$T] = @() }; $Mock.Notes[$T] += [pscustomobject]@{ text = $Text; public = $Public } }
function Get-MockNotes { param([string]$T) if ($Mock.Notes.Contains($T)) { return @($Mock.Notes[$T]) }; return @() }
function Clear-Notes { $Mock.Notes = @{} }
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
$Denied = '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}'
$CR = 'https://portal.example-msp.test'
$CW = 'https://cw.example-msp.test/v4_6_release/apis/3.0'
$HALO = 'https://examplemsp.halo.test'
$GR = 'https://graph.microsoft.com/v1.0'

function Get-Companies {
    $rows = @([pscustomobject]@{ companyId = 7; name = 'Fabrikam Inc'; psaKey = 111; psaIdentifier = 'Fabrikam'; endpointCount = 12 })
    if ($Mock.Opt.Contains('NameTaken')) { $rows += [pscustomobject]@{ companyId = 8; name = 'contoso ltd'; psaKey = 0; psaIdentifier = $null; endpointCount = 0 } }
    if ($Mock.Opt.Contains('Existing')) { $rows += [pscustomobject]@{ companyId = 9001; name = 'Contoso Ltd'; psaKey = 0; psaIdentifier = $null; endpointCount = 4 } }
    if ($Mock.Opt.Contains('PsaLinked')) { $rows += [pscustomobject]@{ companyId = 12; name = 'Contoso (old)'; psaKey = 250; psaIdentifier = 'ContosoLtd'; endpointCount = 0 } }
    if ($Mock.Opt.Contains('Created')) { $rows += [pscustomobject]@{ companyId = 9001; name = 'Contoso Ltd'; psaKey = 250; psaIdentifier = 'ContosoLtd'; endpointCount = 0 } }
    return $rows
}

# Like the real cmdlet, a JSON array reply is handed back as ONE object (", @(...)"), not item by item, and
# -MaximumRedirection is accepted (recorded as MaxRedirect, -1 when not sent) so the shared PSA code takes its no-redirect path.
function Invoke-RestMethod {
    [CmdletBinding()] param($Method = 'GET', $Uri, $Headers, $Body, $ContentType, $Form, [int]$MaximumRedirection = -1)
    $m = ([string]$Method).ToUpperInvariant(); $u = [uri]::UnescapeDataString([string]$Uri)
    $null = $Mock.Calls.Add([pscustomobject]@{ MaxRedirect = $MaximumRedirection; Method = $m; Uri = $u; Body = $(if ($Body -is [string]) { $Body } else { '' }) })
    $page = { param($rows) if ($u -match 'skip=(\d+)' -and [int]$Matches[1] -gt 0) { return [pscustomobject]@{ value = @() } }; return [pscustomobject]@{ value = @($rows) } }
    # ---- CloudRadial ----
    if ($u -like "$CR/v2/odata/company[?]*" -and $m -eq 'GET') {
        if ($u -like '*name eq*') { if ($Mock.Opt.Contains('NoIdReply')) { $Mock.Opt['Created'] = $true }; return (& $page @(Get-Companies | Where-Object { $_.name -eq 'Contoso Ltd' })) }
        return (& $page @(Get-Companies))
    }
    if ($u -like "$CR/v2/odata/domain[?]*") {
        if ($Mock.Opt.Contains('DomainTaken')) { return (& $page @([pscustomobject]@{ companyDomainId = 3; companyId = 7; name = 'contoso.com' })) }
        if ($Mock.Opt.Contains('ExistingHasDomain')) { return (& $page @([pscustomobject]@{ companyDomainId = 4; companyId = 9001; name = 'contoso.com' })) }
        return (& $page @())
    }
    if ($u -like "$CR/v2/odata/companygroup[?]*") { return (& $page @([pscustomobject]@{ companyGroupId = 5; group = 'Managed Clients' }, [pscustomobject]@{ companyGroupId = 6; group = 'Break-Fix' })) }
    if ($u -like "$CR/v2/odata/companygroupcompany[?]*") { return (& $page @()) }
    if ($u -like "$CR/v2/odata/user[?]*") { return (& $page @([pscustomobject]@{ userId = 1 }, [pscustomobject]@{ userId = 2 }, [pscustomobject]@{ userId = 3; isDeleted = $true })) }
    if ($u -eq "$CR/v2/company" -and $m -eq 'POST') {
        if ($Mock.Opt.Contains('NoIdReply')) { return [pscustomobject]@{ success = $true } }
        return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ companyId = 9001; name = 'Contoso Ltd' } }
    }
    if ($u -like "$CR/v2/company/*" -and $m -eq 'PATCH') { return $null }
    if ($u -eq "$CR/v2/domain" -and $m -eq 'POST') {
        if ($Mock.Opt.Contains('FailDomain')) { New-HttpError 500 '{"message":"Mock server error"}' }
        return [pscustomobject]@{ data = [pscustomobject]@{ companyDomainId = 44 } }
    }
    if ($u -eq "$CR/v2/companygroupcompany" -and $m -eq 'POST') { return [pscustomobject]@{ companyGroupId = 5; companyId = 9001 } }
    if ($u -like "$CR/api/beta/archive*" -and $m -eq 'GET') { return , @() }
    if ($u -eq "$CR/api/beta/archive" -and $m -eq 'POST') { return [pscustomobject]@{ id = 66 } }
    if ($u -like "$CR/v2/odata/archiveitem*") { return [pscustomobject]@{ value = @() } }
    if ($u -eq "$CR/v2/archiveitem" -and $m -eq 'POST') { return [pscustomobject]@{ companyReportItemId = 777 } }
    # ---- ConnectWise ----
    if ($u -like "$CW/company/companies[?]*") {
        if ($Mock.Opt.Contains('PsaNone')) { return , @() }
        if ($Mock.Opt.Contains('PsaTwo')) { return , @([pscustomobject]@{ id = 250; name = 'Contoso Ltd'; identifier = 'ContosoLtd' }, [pscustomobject]@{ id = 251; name = 'Contoso Ltd'; identifier = 'ContosoLtd2' }) }
        if ($u -like '*name contains*') { return , @() }
        return , @([pscustomobject]@{ id = 250; name = 'Contoso Ltd'; identifier = 'ContosoLtd' })
    }
    if ($u -like "$CW/service/priorities*") { if ($Mock.Opt.Contains('PrioForbidden')) { New-HttpError 403 '{"code":"Forbidden","message":"You do not have access to Service Desk priorities."}' }; return , @([pscustomobject]@{ id = 8; name = 'Priority 3 - Normal Response' }, [pscustomobject]@{ id = 6; name = 'Priority 1 - Emergency Response' }) }
    if ($u -eq "$CW/service/tickets" -and $m -eq 'POST') { return [pscustomobject]@{ id = 5150 } }
    if ($u -like "$CW/service/tickets/*/notes" -and $m -eq 'POST') { $bo = $Body | ConvertFrom-Json; Add-MockNote ($u -split '/')[-2] $bo.text ([bool]$bo.detailDescriptionFlag); return [pscustomobject]@{ id = 1 } }
    if ($m -eq 'GET' -and $u -match '/service/tickets/(\d+)/notes') { $i = 0; return , @(Get-MockNotes $Matches[1] | ForEach-Object { $i++; [pscustomobject]@{ id = $i; text = $_.text; internalAnalysisFlag = (-not $_.public); detailDescriptionFlag = $_.public } }) }
    if ($m -eq 'GET' -and $u -like "$CW/service/tickets[?]conditions=*") {
        if ($Mock.Opt.Contains('ListFail')) { New-HttpError 500 '{"message":"Mock list error"}' }
        $rows = @([pscustomobject]@{ id = 3001; summary = 'New client onboarding: Fabrikam Inc'; company = [pscustomobject]@{ id = 250 }; closedFlag = $false; status = [pscustomobject]@{ name = 'New' } })
        if ($Mock.Opt.Contains('OpenTicket')) { $rows += [pscustomobject]@{ id = 5150; summary = 'New client onboarding: Contoso Ltd'; company = [pscustomobject]@{ id = 250 }; closedFlag = $false; status = [pscustomobject]@{ name = 'New' } } }
        $rows += [pscustomobject]@{ id = 3002; summary = 'New client onboarding: Contoso Ltd'; company = [pscustomobject]@{ id = 999 }; closedFlag = $false; status = [pscustomobject]@{ name = 'New' } }
        return , $rows
    }
    # ---- HaloPSA ----
    if ($u -eq "$HALO/auth/token") { return [pscustomobject]@{ access_token = 'mock' } }
    if ($u -like "$HALO/api/Client[?]*") { return [pscustomobject]@{ clients = @([pscustomobject]@{ id = 31; name = 'Contoso Ltd' }, [pscustomobject]@{ id = 32; name = 'Contoso Ltd Holdings' }) } }
    if ($u -eq "$HALO/api/Tickets" -and $m -eq 'POST') { return , @([pscustomobject]@{ id = 8080 }) }
    if ($u -eq "$HALO/api/Actions" -and $m -eq 'POST') { $bo = @($Body | ConvertFrom-Json)[0]; Add-MockNote ([string]$bo.ticket_id) $bo.note (-not $bo.hiddenfromuser); return , @([pscustomobject]@{ id = 1 }) }
    if ($m -eq 'GET' -and $u -match "^$([regex]::Escape($HALO))/api/Actions[?]ticket_id=(\d+)") { $i = 0; return [pscustomobject]@{ actions = @(Get-MockNotes $Matches[1] | ForEach-Object { $i++; [pscustomobject]@{ id = $i; note = $_.text; hiddenfromuser = (-not $_.public) } }) } }
    if ($m -eq 'GET' -and $u -like "$HALO/api/Tickets[?]*") { return [pscustomobject]@{ tickets = @(); record_count = 0 } }
    # ---- Microsoft Graph (read only) ----
    if ($u -like 'https://login.microsoftonline.com/*') {
        if ($Mock.Opt.Contains('NoConsent')) { New-HttpError 400 '{"error":"unauthorized_client","error_description":"AADSTS700016: Application not found in the directory."}' }
        return [pscustomobject]@{ access_token = 'mock'; expires_in = 3600 }
    }
    if ($u -like "$GR/organization*") {
        $doms = if ($Mock.Opt.Contains('WrongTenant')) { @([pscustomobject]@{ name = 'fabrikam.com' }) } else { @([pscustomobject]@{ name = 'contoso.onmicrosoft.com' }, [pscustomobject]@{ name = 'Contoso.com' }) }
        return [pscustomobject]@{ value = @([pscustomobject]@{ id = '00000000-0000-0000-0000-00000000c0de'; displayName = 'Contoso Ltd'; verifiedDomains = $doms }) }
    }
    if ($u -like "$GR/subscribedSkus*") {
        $plan = if ($Mock.Opt.Contains('NoP1')) { 'EXCHANGE_S_STANDARD' } else { 'AAD_PREMIUM' }
        return [pscustomobject]@{ value = @([pscustomobject]@{ skuPartNumber = 'SPB'; capabilityStatus = 'Enabled'; servicePlans = @([pscustomobject]@{ servicePlanName = $plan; provisioningStatus = 'Success' }) }) }
    }
    if ($u -like "$GR/policies/identitySecurityDefaultsEnforcementPolicy*") {
        if ($Mock.Opt.Contains('Policy403')) { New-HttpError 403 $Denied }
        return [pscustomobject]@{ isEnabled = (-not $Mock.Opt.Contains('NoP1')) }
    }
    if ($u -like "$GR/groups[?]*") {
        if ($Mock.Opt.Contains('Empty')) { return [pscustomobject]@{ value = @() } }
        return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'g1'; displayName = 'SG-All Staff' }, [pscustomobject]@{ id = 'g2'; displayName = 'Finance' }) }
    }
    if ($u -like "$GR/identity/conditionalAccess/policies*") {
        if ($Mock.Opt.Contains('Empty')) { return [pscustomobject]@{ value = @() } }
        return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'p1'; displayName = 'Block old sign-ins'; state = 'enabled'
                    conditions = [pscustomobject]@{ users = [pscustomobject]@{ includeUsers = @('All') }; applications = [pscustomobject]@{ includeApplications = @('All') }; clientAppTypes = @('exchangeActiveSync', 'other') }
                    grantControls = [pscustomobject]@{ operator = 'OR'; builtInControls = @('block') } }) }
    }
    throw "Unmocked call: $m $u"
}

function Get-Calls { param([string]$Method, [string]$Like) return @($Mock.Calls | Where-Object { $_.Method -eq $Method -and $_.Uri -like $Like }) }
function Get-Writes { return @($Mock.Calls | Where-Object { $_.Method -in @('PATCH', 'POST', 'PUT', 'DELETE') -and $_.Uri -notlike 'https://login.*' -and $_.Uri -notlike "$HALO/auth/*" }) }
function Check { param([string]$Name, [bool]$Ok, $Detail = '') if ($Ok) { $Tally.pass++; Write-Host "PASS $Name" } else { $Tally.fail++; Write-Host "FAIL $Name :: $Detail" -ForegroundColor Red } }
function RoundTrip { param($o) if ($null -eq $o) { return $null }; return ($o | ConvertTo-Json -Depth 30 | ConvertFrom-Json) }

$BaseSecrets = @{
    'CloudRadial-BaseUrl' = $CR; 'CloudRadial-PublicKey' = 'pub'; 'CloudRadial-PrivateKey' = 'priv'
    'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = $CW; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'p'; 'CW-PrivateKey' = 'k'; 'CW-ClientId' = 'c'
    'Halo-ApiUrl' = $HALO; 'Halo-ClientId' = 'hc'; 'Halo-ClientSecret' = 'hs'
    'M365-ClientId' = 'cid'; 'M365-ClientSecret' = 'sec'
}
$Base = @{ company_name = 'Contoso Ltd'; primary_domain = 'contoso.com' }

function Invoke-Workflow {
    param([hashtable]$Add = @{}, [hashtable]$Secrets = @{}, [hashtable]$Opt = @{}, $Raw = $null)
    $Mock.Secrets = $BaseSecrets.Clone(); foreach ($k in $Secrets.Keys) { if ($null -eq $Secrets[$k]) { $Mock.Secrets.Remove($k) } else { $Mock.Secrets[$k] = $Secrets[$k] } }
    $Mock.Calls.Clear(); $Mock.Opt = $Opt
    $in = $Base.Clone(); foreach ($k in $Add.Keys) { if ($null -eq $Add[$k]) { $in.Remove($k) } else { $in[$k] = $Add[$k] } }
    $global:NodeIn = $(if ($null -ne $Raw) { $Raw } else { RoundTrip $in })
    $global:NodeOut = $null
    foreach ($s in $StepIds) {
        try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps[$s])) }
        catch { return @{ out = (RoundTrip $global:NodeOut); error = [string]$_.Exception.Message; step = $s } }
        $global:NodeIn = RoundTrip $global:NodeOut
    }
    return @{ out = $global:NodeIn; error = ''; step = 'end' }
}

# 1. Preview, ConnectWise, new client.
$r = Invoke-Workflow @{ company_group = 'managed clients' }
$o = $r.out
Check 'preview: no error' ($r.error -eq '') $r.error
Check 'preview: status pending_confirmation' ($o.status -eq 'pending_confirmation') $o.status
Check 'preview: nothing written anywhere' (@(Get-Writes).Count -eq 0) (@(Get-Writes | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')
Check 'preview: four changes planned' (@($o.planned).Count -eq 4) (@($o.planned) -join ' | ')
Check 'preview: plan names the PSA link' ($o.planned[0] -eq 'Create the CloudRadial company Contoso Ltd, linked to ConnectWise company 250') $o.planned[0]
Check 'preview: message says nothing changed' ($o.message -like 'Nothing was changed. With confirm set to true, this run would:*') $o.message
Check 'preview: m365 read for the right tenant' ($o.m365.status -eq 'read' -and $o.m365.tenant_name -eq 'Contoso Ltd') $o.m365.status
Check 'preview: token requested for the domain tenant' (@(Get-Calls POST 'https://login.microsoftonline.com/contoso.com/*').Count -eq 1) ''
$grp = @($o.m365.groups)
Check 'preview: SG-All Staff exists, two would be created' ($grp[0].exists -and -not $grp[1].exists -and -not $grp[2].exists -and $grp[2].name -eq 'SG-Break Glass Exclusion') ($grp | ConvertTo-Json -Compress)
$pol = @($o.m365.policies)
Check 'preview: MFA policies would be created report-only' ($pol[0].would_create -and $pol[1].would_create -and $pol[0].definition.state -eq 'enabledForReportingButNotEnforced') ''
Check 'preview: legacy auth already covered' (-not $pol[2].would_create -and $pol[2].action -match "covered by the existing policy 'Block old sign-ins' \(on\)") $pol[2].action
Check 'preview: break-glass group excluded in every definition' (@($pol | Where-Object { @($_.definition.conditions.users.excludeGroups).Count -eq 1 }).Count -eq 3) ''
Check 'preview: no report written, report_html kept' ($o.report.action -eq 'not-written' -and $o.report_html -match 'SG-Break Glass Exclusion') ''
Check 'preview: no Graph writes' (@($Mock.Calls | Where-Object { $_.Uri -like 'https://graph.*' -and $_.Method -ne 'GET' }).Count -eq 0) ''

# 2. Confirm, ConnectWise.
$r = Invoke-Workflow @{ company_group = 'Managed Clients'; account_manager = 'Alex Example'; confirm = 'true' }
$o = $r.out
Check 'confirm: no error' ($r.error -eq '') $r.error
Check 'confirm: status success' ($o.status -eq 'success') "$($o.status) $($o.message)"
$cb = (Get-Calls POST "$CR/v2/company")[0].Body | ConvertFrom-Json
Check 'confirm: company created with PSA link' ($cb.name -eq 'Contoso Ltd' -and $cb.psaKey -eq 250 -and $cb.psaIdentifier -eq 'ContosoLtd' -and $cb.accountManager -eq 'Alex Example') ($cb | ConvertTo-Json -Compress)
$db = (Get-Calls POST "$CR/v2/domain")[0].Body | ConvertFrom-Json
Check 'confirm: domain added to the new company' ($db.companyId -eq 9001 -and $db.name -eq 'contoso.com' -and $db.isDefault) ($db | ConvertTo-Json -Compress)
$gb = (Get-Calls POST "$CR/v2/companygroupcompany")[0].Body | ConvertFrom-Json
Check 'confirm: added to the group' ($gb.companyGroupId -eq 5 -and $gb.companyId -eq 9001) ''
$tk = @(Get-Calls POST "$CW/service/tickets")
$tb = $tk[0].Body | ConvertFrom-Json
Check 'confirm: one CW ticket for company 250' ($tk.Count -eq 1 -and $tb.company.id -eq 250 -and $tb.summary -eq 'New client onboarding: Contoso Ltd' -and $tb.priority.id -eq 8) ($tb | ConvertTo-Json -Compress)
Check 'confirm: ticket carries the 10-item checklist' ($tb.initialDescription -match '\[ \] 1\. Confirm the signed agreement' -and $tb.initialDescription -match '\[ \] 10\. ') $tb.initialDescription
$ab = @(Get-Calls POST "$CR/v2/archiveitem")
Check 'confirm: baseline report in the Onboarding archive' ($ab.Count -eq 1 -and ($ab[0].Body | ConvertFrom-Json).archiveId -eq 66 -and ($ab[0].Body | ConvertFrom-Json).companyId -eq 9001) ''
Check 'confirm: archive created as Onboarding' (((Get-Calls POST "$CR/api/beta/archive")[0].Body | ConvertFrom-Json).name -eq 'Onboarding') ''
$nb = (Get-Calls POST "$CW/service/tickets/5150/notes")[0].Body | ConvertFrom-Json
Check 'confirm: CW internal note with the baseline' ($nb.internalAnalysisFlag -eq $true -and $nb.text -match 'CA001 - Require MFA for admins' -and $nb.text -match 'no sync call') ''
Check 'ConnectWise calls are sent with -MaximumRedirection 0' ((@($Mock.Calls | Where-Object { $_.Uri -like 'https://cw.example-msp.test/*' }).Count -gt 0) -and -not @($Mock.Calls | Where-Object { $_.Uri -like 'https://cw.example-msp.test/*' -and $_.MaxRedirect -ne 0 }).Count) (@($Mock.Calls | Where-Object { $_.Uri -like 'https://cw.example-msp.test/*' } | ForEach-Object { "$($_.Method) $($_.MaxRedirect)" }) -join ', ')
Check 'confirm: message plain' ($o.message -eq 'Created CloudRadial company 9001 for Contoso Ltd, linked to ConnectWise company 250 and opened onboarding ticket 5150 with a 10-item checklist. The Microsoft 365 baseline was prepared but not applied.') $o.message
Check 'confirm: ticket_id output' ($o.ticket_id -eq '5150' -and $o.company_id -eq 9001) ''
Check 'confirm: no Graph writes' (@($Mock.Calls | Where-Object { $_.Uri -like 'https://graph.*' -and $_.Method -ne 'GET' }).Count -eq 0) ''

# 3. Already in CloudRadial by name.
$r = Invoke-Workflow @{ confirm = 'true' } @{} @{ NameTaken = $true }
Check 'duplicate name: rejected in check step' ($r.step -eq 'node-check' -and $r.out.status -eq 'rejected' -and $r.error -match 'already in CloudRadial \(company 8\)') $r.error
Check 'duplicate name: no writes' (@(Get-Writes).Count -eq 0) ''

# 4. Domain already on another company.
$r = Invoke-Workflow @{ confirm = 'true' } @{} @{ DomainTaken = $true }
Check 'duplicate domain: rejected' ($r.out.status -eq 'rejected' -and $r.error -match 'contoso\.com is already on CloudRadial company 7') $r.error
Check 'duplicate domain: no writes' (@(Get-Writes).Count -eq 0) ''

# 5. PSA company already linked to another CloudRadial company.
$r = Invoke-Workflow @{ confirm = 'true' } @{} @{ PsaLinked = $true }
Check 'PSA already linked: rejected' ($r.out.status -eq 'rejected' -and $r.error -match 'already linked to CloudRadial company 12') $r.error

# 6. CloudRadial secrets missing.
$r = Invoke-Workflow @{} @{ 'CloudRadial-PrivateKey' = $null }
Check 'no CloudRadial: plain error naming the secret' ($r.out.status -eq 'error' -and $r.error -match "^CloudRadial isn't set up on this runner\. Add these secrets to the runner Key Vault: CloudRadial-PrivateKey\. Nothing was changed\.$") $r.error
Check 'no CloudRadial: no calls at all' ($Mock.Calls.Count -eq 0) ''

# 7. Graph not set up, HaloPSA, confirm: CloudRadial and ticket still done, M365 skipped with a note.
$r = Invoke-Workflow @{ confirm = 'yes'; psa = 'halo'; psa_company_id = '31' } @{ 'M365-ClientSecret' = $null }
$o = $r.out
Check 'no Graph: success' ($r.error -eq '' -and $o.status -eq 'success') "$($r.error) $($o.status)"
Check 'no Graph: skipped warning' ((@($o.warnings) -join ' ') -match 'Microsoft 365 baseline skipped: Microsoft 365 is not set up') (@($o.warnings) -join ' | ')
Check 'no Graph: no Graph calls' (@($Mock.Calls | Where-Object { $_.Uri -like '*microsoft*' }).Count -eq 0) ''
$hb = (Get-Calls POST "$HALO/api/Tickets")[0].Body | ConvertFrom-Json
Check 'Halo: ticket for client 31' (@($hb)[0].client_id -eq 31 -and @($hb)[0].details -match '\[ \] 1\.') ''
Check 'Halo: PSA search skipped when psa_company_id given' (@(Get-Calls GET "$HALO/api/Client*").Count -eq 0) ''
$hn = (Get-Calls POST "$HALO/api/Actions")[0].Body | ConvertFrom-Json
Check 'Halo: private note says baseline skipped' (@($hn)[0].hiddenfromuser -eq $true -and @($hn)[0].ticket_id -eq 8080 -and @($hn)[0].note -match 'baseline was skipped') ''
Check 'no Graph: no report written' (@(Get-Calls POST "$CR/v2/archiveitem").Count -eq 0) ''
Check 'Halo: psaIdentifier falls back to the id' ((((Get-Calls POST "$CR/v2/company")[0].Body | ConvertFrom-Json).psaIdentifier) -eq '31') ''

# 8. Halo name search: exactly one exact match among close ones.
$r = Invoke-Workflow @{ psa = 'halopsa' }
Check 'Halo search: exact match picked' ($r.error -eq '' -and $r.out.psa.company_id -eq '31') "$($r.error)"

# 9. Missing Policy.Read.All: stops before any write.
$r = Invoke-Workflow @{ confirm = 'true' } @{} @{ Policy403 = $true }
Check '403: fails in M365 step' ($r.step -eq 'node-m365' -and $r.out.status -eq 'error') "$($r.step) $($r.error)"
Check '403: plain sentence naming Policy.Read.All' ($r.error -eq "Can't read the client's security defaults setting. The app registration needs the Policy.Read.All application permission, with admin consent in the client's tenant (or set include_m365 to false). Nothing was changed.") $r.error
Check '403: no writes' (@(Get-Writes).Count -eq 0) ''

# 10. include_m365 false skips the 403 entirely.
$r = Invoke-Workflow @{ include_m365 = 'false' } @{} @{ Policy403 = $true }
Check 'include_m365 false: no Graph calls' ($r.error -eq '' -and @($Mock.Calls | Where-Object { $_.Uri -like '*microsoft*' }).Count -eq 0) $r.error

# 11. App not consented in the client's tenant: skipped, not failed.
$r = Invoke-Workflow @{} @{} @{ NoConsent = $true }
Check 'no consent: skipped with a note' ($r.error -eq '' -and $r.out.m365.status -eq 'skipped' -and $r.out.m365.reason -match 'not have consented') $r.out.m365.reason

# 12. tenant_id that doesn't own the domain.
$r = Invoke-Workflow @{ tenant_id = '11111111-1111-1111-1111-111111111111'; confirm = 'true' } @{} @{ WrongTenant = $true }
Check 'wrong tenant: rejected' ($r.step -eq 'node-m365' -and $r.out.status -eq 'rejected' -and $r.error -match 'does not own the domain contoso\.com') $r.error
Check 'wrong tenant: token asked for the given tenant' (@(Get-Calls POST 'https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/*').Count -eq 1) ''
Check 'wrong tenant: no writes' (@(Get-Writes).Count -eq 0) ''

# 13. Empty tenant without P1.
$r = Invoke-Workflow @{} @{} @{ Empty = $true; NoP1 = $true }
$o = $r.out
Check 'empty: all three groups would be created' (@($o.m365.groups | Where-Object { -not $_.exists }).Count -eq 3) ''
Check 'empty: CA not possible without P1' (@($o.m365.policies | Where-Object { $_.action -like 'Not possible*' }).Count -eq 3) ''
Check 'empty: CA list never read without P1' (@(Get-Calls GET '*conditionalAccess*').Count -eq 0) ''
Check 'empty: next step says turn security defaults on' ((@($o.m365.next_steps) -join ' ') -match 'Turn security defaults on') ''

# 14. PSA match problems.
$r = Invoke-Workflow @{} @{} @{ PsaNone = $true }
Check 'PSA none: incomplete' ($r.out.status -eq 'incomplete' -and $r.error -match "ConnectWise has no company named exactly 'Contoso Ltd'") $r.error
$r = Invoke-Workflow @{} @{} @{ PsaTwo = $true }
Check 'PSA two: incomplete with ids' ($r.out.status -eq 'incomplete' -and $r.error -match 'ids 250, 251') $r.error

# 15. Unknown company group.
$r = Invoke-Workflow @{ company_group = 'VIP' }
Check 'group missing: incomplete, lists groups' ($r.out.status -eq 'incomplete' -and $r.error -match 'Break-Fix, Managed Clients') $r.error

# 16. Existing company plus existing ticket: no create, no new ticket, note on that ticket.
$r = Invoke-Workflow @{ company_id = '9001'; ticket_id = '4242'; confirm = 'true'; checklist = "1. Kick-off call`n2. Collect admin access" } @{} @{ Existing = $true }
$o = $r.out
Check 'existing: success' ($r.error -eq '' -and $o.status -eq 'success') "$($r.error) $($o.message)"
Check 'existing: no company create, no new ticket' (@(Get-Calls POST "$CR/v2/company").Count -eq 0 -and @(Get-Calls POST "$CW/service/tickets").Count -eq 0) ''
Check 'existing: PSA link patched' (@(Get-Calls PATCH "$CR/v2/company/9001").Count -eq 1) ''
Check 'existing: domain added' (@(Get-Calls POST "$CR/v2/domain").Count -eq 1) ''
Check 'existing: note on ticket 4242 with user count' (((Get-Calls POST "$CW/service/tickets/4242/notes")[0].Body | ConvertFrom-Json).text -match 'has 2 users and 4 endpoints') ''
Check 'existing: custom checklist parsed' (@($o.psa.checklist).Count -eq 2 -and $o.psa.checklist[0] -eq 'Kick-off call') (@($o.psa.checklist) -join ' | ')

# 17. Mid-plan failure after the company is created.
$r = Invoke-Workflow @{ confirm = 'true' } @{} @{ FailDomain = $true }
$o = $r.out
Check 'failure: status error' ($r.error -eq '' -and $o.status -eq 'error') "$($r.error) $($o.status)"
Check 'failure: says what ran, what did not, and how to finish' ($o.message -match "stopped because 'Add the domain contoso\.com to the company' failed" -and $o.message -match 'Not run: Open the onboarding checklist ticket' -and $o.message -match 'run again with company_id set to 9001') $o.message
Check 'failure: no ticket opened' (@(Get-Calls POST "$CW/service/tickets").Count -eq 0) ''

# 18. Company create reply without an id: looked up by name.
$r = Invoke-Workflow @{ confirm = 'true' } @{} @{ NoIdReply = $true }
Check 'no id reply: company found by name' ($r.error -eq '' -and $r.out.status -eq 'success' -and $r.out.company_id -eq 9001) "$($r.error) $($r.out.message)"

# 18b. Rerun writes nothing twice.
# The internal note ends with a marker of the ticket id and a hash of the note, never the name or domain.
Clear-Notes
$r = Invoke-Workflow @{ company_id = '9001'; ticket_id = '4242'; confirm = 'true' } @{} @{ Existing = $true }
Check 'rerun: first run writes one internal note with the marker' (@(Get-MockNotes '4242').Count -eq 1 -and (Get-MockNotes '4242')[0].text -match '\[new-client-onboarding: 4242 [0-9a-f]{8}\]' -and (Get-MockNotes '4242')[0].public -eq $false) (@(Get-MockNotes '4242' | ForEach-Object { $_.text }) -join ' || ')
Check 'rerun: marker holds no name or domain' (-not ((Get-MockNotes '4242')[0].text -match '\[new-client-onboarding:[^\]]*(Contoso|contoso\.com)'))
# ServiceAI Retry of the same run: the domain is on the company now and the same note is already there.
$r = Invoke-Workflow @{ company_id = '9001'; ticket_id = '4242'; confirm = 'true' } @{} @{ Existing = $true; ExistingHasDomain = $true }
$TFirst = @(Get-MockNotes '4242').Count
$r = Invoke-Workflow @{ company_id = '9001'; ticket_id = '4242'; confirm = 'true' } @{} @{ Existing = $true; ExistingHasDomain = $true }
Check 'rerun: the same outcome adds no second note' ($r.error -eq '' -and @(Get-MockNotes '4242').Count -eq $TFirst -and @(Get-Calls POST "$CW/service/tickets/4242/notes").Count -eq 0 -and (@($r.out.actions) -join ' ') -match 'already on ticket 4242') "$TFirst $(@(Get-MockNotes '4242').Count) $(@($r.out.actions) -join ' | ')"
# A rerun with company_id and no ticket_id finds the open onboarding ticket (this PSA company's only) and reuses it.
Clear-Notes
$r = Invoke-Workflow @{ company_id = '9001'; confirm = 'true' } @{} @{ Existing = $true; ExistingHasDomain = $true; OpenTicket = $true }
Check 'rerun: open onboarding ticket reused, no second ticket' ($r.error -eq '' -and $r.out.ticket_id -eq '5150' -and @(Get-Calls POST "$CW/service/tickets").Count -eq 0 -and @(Get-MockNotes '5150').Count -eq 1 -and @(Get-MockNotes '3002').Count -eq 0) "$($r.error) $($r.out.ticket_id) $($r.out.message)"
Check 'rerun: the search is scoped to the PSA company' (@(Get-Calls GET "$CW/service/tickets?conditions=*" | Where-Object { $_.Uri -match 'company/id=250' -and $_.Uri -match 'closedFlag=false' }).Count -eq 1) ''
$r = Invoke-Workflow @{ company_id = '9001' } @{} @{ Existing = $true; ExistingHasDomain = $true; OpenTicket = $true }
Check 'rerun preview: no ticket planned when one is already open' (-not @($r.out.planned | Where-Object { $_ -like 'Open the onboarding*' }).Count -and @(Get-Writes).Count -eq 0) "$($r.out.status) $(@($r.out.planned) -join ' | ')"
$r = Invoke-Workflow @{ company_id = '9001'; confirm = 'true' } @{} @{ Existing = $true; ExistingHasDomain = $true; ListFail = $true }
Check 'ticket search fails: a warning, the run goes on' ($r.error -eq '' -and $r.out.status -eq 'success' -and (@($r.out.warnings) -join ' ') -match "Couldn't check ConnectWise for an open onboarding ticket") (@($r.out.warnings) -join ' | ')
Check 'every ticket note this workflow writes is internal' (-not @($Mock.Notes.Values | ForEach-Object { $_ } | Where-Object { $_.public }).Count) ''

# 19. Bad input fails closed before any call.
$r = Invoke-Workflow @{ primary_domain = $null }
Check 'no domain: incomplete in Read inputs' ($r.step -eq 'node-inputs' -and $r.out.status -eq 'incomplete' -and $Mock.Calls.Count -eq 0) $r.error
$r = Invoke-Workflow @{ primary_domain = 'not a domain' }
Check 'bad domain: incomplete' ($r.step -eq 'node-inputs' -and $r.error -match 'must be a domain name') $r.error
$r = Invoke-Workflow @{} @{} @{} '{"company_name":"@company_name","primary_domain":"contoso.com"}'
Check 'literal @token: treated as missing' ($r.step -eq 'node-inputs' -and $r.error -match 'company_name is required') $r.error

# A warning from _shared/psa.ps1 reaches the output: ConnectWise refuses to list ticket priorities (403), so the
# onboarding ticket opens at the board's default priority and New-PsaTicket records a warning in $PsaState.Warnings.
$r = Invoke-Workflow @{ confirm = 'true' } @{} @{ PrioForbidden = $true }
$o = $r.out
$tk = @(Get-Calls POST "$CW/service/tickets")
Check 'shared warning: the ticket still opens, with no priority set' ($r.error -eq '' -and $o.status -eq 'success' -and $tk.Count -eq 1 -and $null -eq ($tk[0].Body | ConvertFrom-Json).PSObject.Properties['priority']) "$($r.error) $($o.status)"
Check 'shared warning: $PsaState.Warnings reaches the output warnings, once' (@($o.warnings | Where-Object { $_ -like "ConnectWise wouldn't list ticket priorities*" }).Count -eq 1) (@($o.warnings) -join ' | ')

Write-Host "$($Tally.pass) passed, $($Tally.fail) failed"
if ($Tally.fail) { exit 1 }
exit 0
