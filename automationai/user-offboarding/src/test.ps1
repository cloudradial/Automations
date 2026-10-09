# Mock harness for user-offboarding.yml: fake Key Vault, Microsoft Graph, Exchange Online (REST and the
# ExchangeOnlineManagement module), CloudRadial, PSAs and node I/O. Runs both step scripts exactly as they ship
# (extracted from the built .yml) through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest.
# Placeholder data only (Contoso, Example MSP).
# Usage: node build.js --check; pwsh -NoProfile -File test.ps1 [-ShowNotes]   (needs js-yaml, or JS_YAML_PATH)
param([switch]$ShowNotes)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')
$ErrorActionPreference = 'Stop'

# ---------- extract the step scripts from the built workflow ----------
$tmp = Join-Path ([IO.Path]::GetTempPath()) "user-offboarding-test-$PID"
New-Item -ItemType Directory -Force $tmp | Out-Null
$extract = "const p=require('path');let y;try{y=require('js-yaml')}catch{try{y=require(p.join(process.argv[3],'node_modules','js-yaml'))}catch{y=require(process.env.JS_YAML_PATH)}};const w=y.load(require('fs').readFileSync(process.argv[1],'utf8'));for(const a of w.definition.activities){if(a.type==='powershell-script')require('fs').writeFileSync(p.join(process.argv[2],a.id+'.ps1'),a.properties.script)}"
& node -e $extract (Join-Path $PSScriptRoot '..\user-offboarding.yml') $tmp $Shared
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the step scripts (is js-yaml installed, or JS_YAML_PATH set?)' }
$ReadScript = Get-Content -Raw (Join-Path $tmp 'node-read.ps1')
$ApplyScript = Get-Content -Raw (Join-Path $tmp 'node-apply.ps1')
Remove-Item -Recurse -Force $tmp

# ---------- placeholder data ----------
$GraphBase = 'https://graph.microsoft.com'
$ExoBase = 'https://outlook.office365.com/adminapi/beta'
$TenantGuid = '0a1b2c3d-0000-4000-8000-00000000c0de'
$BaseSecrets = @{
    'M365-TenantId' = $TenantGuid; 'M365-ClientId' = 'app-id'; 'M365-ClientSecret' = 'not-a-real-secret'
    'CloudRadial-BaseUrl' = 'https://cr.example'; 'CloudRadial-PublicKey' = 'pub'; 'CloudRadial-PrivateKey' = 'priv'
}
$ExoRestSecrets = @{ 'MicrosoftExchange-TenantId' = $TenantGuid; 'MicrosoftExchange-ClientId' = 'exo-app'; 'MicrosoftExchange-ClientSecret' = 'not-a-real-secret' }
$ExoCertSecrets = @{ 'MicrosoftExchange-ClientId' = 'exo-app'; 'MicrosoftExchange-CertificateThumbprint' = 'ABCDEF0123456789'; 'MicrosoftExchange-Organization' = 'contoso.onmicrosoft.com' }
$PsaSecrets = @{
    connectwise = @{ 'CW-ApiUrl' = 'https://cw.example/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'Autotask-ApiUrl' = 'https://at.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@examplemsp.com'; 'Autotask-Secret' = 's' }
    halopsa     = @{ 'Halo-ApiUrl' = 'https://halo.example'; 'Halo-ClientId' = 'id'; 'Halo-ClientSecret' = 's' }
}
$GroupDefs = @(
    @{ id = 'g-sales'; displayName = 'Sales Team'; mailEnabled = $false; securityEnabled = $true; groupTypes = @(); onPremisesSyncEnabled = $null; mail = $null }
    @{ id = 'g-team'; displayName = 'Contoso Sales (Teams)'; mailEnabled = $true; securityEnabled = $false; groupTypes = @('Unified'); onPremisesSyncEnabled = $null; mail = 'salesteam@contoso.com' }
    @{ id = 'g-list'; displayName = 'All Staff list'; mailEnabled = $true; securityEnabled = $false; groupTypes = @(); onPremisesSyncEnabled = $null; mail = 'allstaff@contoso.com' }
    @{ id = 'g-mesg'; displayName = 'Finance Share'; mailEnabled = $true; securityEnabled = $true; groupTypes = @(); onPremisesSyncEnabled = $null; mail = 'financeshare@contoso.com' }
    @{ id = 'g-dyn'; displayName = 'All Sales (dynamic)'; mailEnabled = $false; securityEnabled = $true; groupTypes = @('DynamicMembership'); onPremisesSyncEnabled = $null; mail = $null }
    @{ id = 'g-onprem'; displayName = 'VPN Users'; mailEnabled = $false; securityEnabled = $true; groupTypes = @(); onPremisesSyncEnabled = $true; mail = $null }
    @{ id = 'g-lic'; displayName = 'M365 E3 Licensing'; mailEnabled = $false; securityEnabled = $true; groupTypes = @(); onPremisesSyncEnabled = $null; mail = $null }
)
$People = @{
    'u-sam'  = @{ id = 'u-sam'; userPrincipalName = 'sam.doe@contoso.com'; displayName = 'Sam Doe'; mail = 'sam.doe@contoso.com'; accountEnabled = $true; proxyAddresses = @('SMTP:sam.doe@contoso.com', 'smtp:sam@contoso.com') }
    'u-alex' = @{ id = 'u-alex'; userPrincipalName = 'alex.kim@contoso.com'; displayName = 'Alex Kim'; mail = 'alex.kim@contoso.com'; accountEnabled = $true; proxyAddresses = @() }
    'u-pat'  = @{ id = 'u-pat'; userPrincipalName = 'pat.lee@contoso.com'; displayName = 'Pat Lee'; mail = 'pat.lee@contoso.com'; accountEnabled = $true; proxyAddresses = @() }
}

$Sc = @{}
function New-Scenario {
    param([string]$Psa = 'connectwise', [string]$Exo = 'rest', [hashtable]$Over = @{})
    $Sc.Clear()
    $Sc.member = @('g-sales', 'g-team', 'g-list', 'g-mesg', 'g-dyn', 'g-onprem', 'g-lic')
    $Sc.roles = @()
    $Sc.manager = 'u-alex'
    $Sc.enabled = $true; $Sc.synced = $null
    $Sc.states = @(@{ skuId = 'sku-bs'; assignedByGroup = $null; state = 'Active' }, @{ skuId = 'sku-e3'; assignedByGroup = 'g-lic'; state = 'Active' })
    $Sc.plans = @(@{ service = 'exchange'; capabilityStatus = 'Enabled' })
    $Sc.mailbox = 'UserMailbox'      # $null means no mailbox
    $Sc.hidden = $false; $Sc.fwd = $null; $Sc.lit = $false; $Sc.bytes = '2,254,857,830'
    $Sc.failConvert = $false; $Sc.convertNoop = $false
    $Sc.forbid = @()                 # Graph "METHOD path" regexes that answer 403
    $Sc.module = ($Exo -eq 'module')
    $Sc.exoLog = New-Object System.Collections.ArrayList
    $Sc.order = New-Object System.Collections.ArrayList
    $Sc.archives = New-Object System.Collections.ArrayList
    $Sc.notes = New-Object System.Collections.ArrayList   # @{ text; internal } for every note written, read back by the marker check
    foreach ($k in $Over.Keys) { $Sc[$k] = $Over[$k] }
    $sec = $BaseSecrets.Clone()
    if ($Psa) { foreach ($k in $PsaSecrets[$Psa].Keys) { $sec[$k] = $PsaSecrets[$Psa][$k] }; $sec['PSA-Type'] = $Psa }
    if ($Exo -eq 'rest') { foreach ($k in $ExoRestSecrets.Keys) { $sec[$k] = $ExoRestSecrets[$k] } }
    if ($Exo -eq 'module') { foreach ($k in $ExoCertSecrets.Keys) { $sec[$k] = $ExoCertSecrets[$k] } }
    Reset-Mock $sec $Handler
}
function J { param($o) [pscustomobject]$o }
function New-Mailbox {
    return J @{ RecipientTypeDetails = $Sc.mailbox; HiddenFromAddressListsEnabled = $Sc.hidden; ForwardingSmtpAddress = $Sc.fwd; ForwardingAddress = $null; LitigationHoldEnabled = $Sc.lit; InPlaceHolds = @(); ArchiveStatus = 'None' }
}
# One Exchange cmdlet, shared by the REST and module mocks. Records the order of every change.
function Invoke-FakeExo {
    param([string]$Name, $P)
    $null = $Sc.exoLog.Add("$Name $(($P | ConvertTo-Json -Compress -Depth 4))")
    switch ($Name) {
        'Get-Mailbox' { if ($null -eq $Sc.mailbox) { throw "The operation couldn't be performed because object '$($P.Identity)' couldn't be found on 'EXAMPLE.PROD.OUTLOOK.COM'." }; return @(New-Mailbox) }
        'Get-MailboxStatistics' { return @(J @{ TotalItemSize = "2.1 GB ($($Sc.bytes) bytes)" }) }
        'Set-Mailbox' {
            $keys = @(if ($P -is [System.Collections.IDictionary]) { $P.Keys } else { $P.PSObject.Properties.Name })
            $label = if ($keys -contains 'Type') { 'Type' } elseif ($keys -contains 'HiddenFromAddressListsEnabled') { 'Hidden' } elseif ($keys -contains 'ForwardingAddress') { 'Forward' } else { 'Other' }
            $null = $Sc.order.Add("exo:Set-Mailbox:$label")
            $type = $null; if ($keys -contains 'Type') { $type = $(if ($P -is [System.Collections.IDictionary]) { $P['Type'] } else { $P.Type }) }
            if ($type -eq 'Shared') { if ($Sc.failConvert) { throw 'The mailbox couldn''t be converted (simulated).' }; if (-not $Sc.convertNoop) { $Sc.mailbox = 'SharedMailbox' } }
            return @()
        }
    }
    throw "unmocked Exchange cmdlet $Name"
}

$Handler = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    $m = $c.Method
    if ($u -like 'https://login.microsoftonline.com/*') {
        $scope = ''; if ($c.BodyObj -is [hashtable]) { $scope = [string]$c.BodyObj.scope }
        if ($scope -like 'https://outlook.office365.com/*' -and $Sc.Contains('exoTokenFail') -and $Sc.exoTokenFail) { New-HttpError 401 '{"error":"invalid_client","error_description":"AADSTS7000215: Invalid client secret provided."}' }
        return J @{ access_token = $(if ($scope -like 'https://outlook*') { 'exo-tok' } else { 'tok' }); expires_in = 3599 }
    }
    # ---- Exchange Online REST (InvokeCommand) ----
    if ($u -like "$ExoBase/*/InvokeCommand") {
        $b = $c.Body | ConvertFrom-Json
        try { $r = @(Invoke-FakeExo $b.CmdletInput.CmdletName $b.CmdletInput.Parameters) }
        catch { $msg = $_.Exception.Message -replace '"', "'"; if ($msg -match "couldn't be found") { New-HttpError 404 "{`"error`":{`"code`":`"NotFound`",`"message`":`"$msg`"}}" }; New-HttpError 400 "{`"error`":{`"code`":`"BadRequest`",`"message`":`"$msg`"}}" }
        return J @{ value = $r }
    }
    # ---- CloudRadial ----
    if ($u -like 'https://cr.example/*') {
        if ($m -eq 'GET' -and $u -like '*/api/beta/archive?*') { return @($Sc.archives) }
        if ($m -eq 'POST' -and $u -eq 'https://cr.example/api/beta/archive') { $b = $c.Body | ConvertFrom-Json; $null = $Sc.archives.Add((J @{ id = 31; companyId = $b.companyId; name = $b.name })); return J @{ success = $true } }
        if ($m -eq 'GET' -and $u -like '*/v2/odata/archiveitem*') { return J @{ value = @() } }
        if ($m -eq 'POST' -and $u -eq 'https://cr.example/v2/archiveitem') { return J @{ companyReportItemId = 401 } }
        throw "unmocked CloudRadial $m $u"
    }
    # ---- Microsoft Graph ----
    if ($u -like "$GraphBase/*") {
        $p = $u.Substring($GraphBase.Length)
        foreach ($f in @($Sc.forbid)) { if ("$m $p" -match $f) { New-HttpError 403 '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}' } }
        if ($m -eq 'GET') {
            if ($p -match '^/v1\.0/users/([^/?]+)\?') {
                $k = $Matches[1]; $hit = @($People.Values | Where-Object { $_.id -eq $k -or $_.userPrincipalName -eq $k })
                if (-not $hit.Count) { New-HttpError 404 '{"error":{"code":"Request_ResourceNotFound","message":"Resource does not exist."}}' }
                $o = $hit[0].Clone()
                if ($o.id -eq 'u-sam') {
                    $o.accountEnabled = $Sc.enabled; $o.onPremisesSyncEnabled = $Sc.synced
                    $o.licenseAssignmentStates = @($Sc.states | ForEach-Object { J $_ }); $o.assignedLicenses = @($Sc.states | ForEach-Object { J @{ skuId = $_.skuId } })
                    $o.assignedPlans = @($Sc.plans | ForEach-Object { J $_ })
                }
                return J $o
            }
            if ($p -match '^/v1\.0/users/u-sam/transitiveMemberOf/microsoft\.graph\.directoryRole') { return J @{ value = @($Sc.roles | ForEach-Object { J @{ id = "r-$_"; displayName = $_ } }) } }
            if ($p -match '^/v1\.0/users/u-sam/memberOf') { return J @{ value = @(@($Sc.member | ForEach-Object { $id = $_; $g = @($GroupDefs | Where-Object { $_.id -eq $id })[0].Clone(); $g['@odata.type'] = '#microsoft.graph.group'; J $g }) + @(J @{ '@odata.type' = '#microsoft.graph.administrativeUnit'; id = 'au-1'; displayName = 'Sales AU' })) } }
            if ($p -match '^/v1\.0/users/u-sam/licenseDetails') { return J @{ value = @((J @{ skuId = 'sku-bs'; skuPartNumber = 'O365_BUSINESS_PREMIUM' }), (J @{ skuId = 'sku-e3'; skuPartNumber = 'SPE_E3' })) } }
            if ($p -match '^/v1\.0/users/u-sam/manager') { if ($Sc.manager) { return J $People[$Sc.manager] }; New-HttpError 404 '{"error":{"code":"Request_ResourceNotFound","message":"Resource manager does not exist."}}' }
            if ($p -match '^/v1\.0/users/u-sam/directReports') { return J @{ value = @(J @{ id = 'u-pat'; displayName = 'Pat Lee'; userPrincipalName = 'pat.lee@contoso.com' }) } }
            if ($p -match '^/v1\.0/users/u-sam/registeredDevices') { return J @{ value = @(J @{ id = 'd-1'; displayName = 'CONTOSO-LT-042'; operatingSystem = 'Windows'; trustType = 'AzureAd' }) } }
            if ($p -match '^/v1\.0/users/u-sam/ownedDevices') { return J @{ value = @(J @{ id = 'd-1'; displayName = 'CONTOSO-LT-042'; operatingSystem = 'Windows'; trustType = 'AzureAd' }) } }
            if ($p -match '^/v1\.0/organization') { return J @{ value = @(J @{ verifiedDomains = @((J @{ name = 'contoso.com'; isInitial = $false }), (J @{ name = 'contoso.onmicrosoft.com'; isInitial = $true })) }) } }
        }
        if ($m -eq 'PATCH' -and $p -eq '/v1.0/users/u-sam') { $b = $c.Body | ConvertFrom-Json; if ($b.PSObject.Properties['passwordProfile']) { $Sc.password = $b.passwordProfile.password; $null = $Sc.order.Add('graph:password') } else { $null = $Sc.order.Add('graph:disable') }; return $null }
        if ($m -eq 'POST' -and $p -eq '/v1.0/users/u-sam/revokeSignInSessions') { $null = $Sc.order.Add('graph:revoke'); return J @{ value = $true } }
        if ($m -eq 'DELETE' -and $p -match '^/v1\.0/groups/([^/]+)/members/u-sam/\$ref$') { $null = $Sc.order.Add("graph:remove:$($Matches[1])"); return $null }
        if ($m -eq 'POST' -and $p -eq '/v1.0/users/u-sam/assignLicense') { $null = $Sc.order.Add('graph:licence'); return $null }
        throw "unmocked Graph $m $p"
    }
    # ---- PSAs ----
    # Notes are kept in $Sc.notes and read back, so Add-PsaNote -Marker can find an earlier copy.
    if ($u -like 'https://cw.example/*') {
        if ($m -eq 'GET' -and $u -like '*/service/tickets/12345/notes*') { $i = 0; return , @($Sc.notes | ForEach-Object { $i++; J @{ id = $i; text = $_.text; internalAnalysisFlag = $_.internal; detailDescriptionFlag = (-not $_.internal); member = (J @{ identifier = 'api' }) } }) }
        if ($m -eq 'POST' -and $u -like '*/service/tickets/12345/notes') { $b = $c.Body | ConvertFrom-Json; $null = $Sc.notes.Add(@{ text = [string]$b.text; internal = [bool]$b.internalAnalysisFlag }); return J @{ id = $Sc.notes.Count } }
    }
    if ($u -like 'https://at.example/*') {
        if ($m -eq 'GET' -and $u -like '*/TicketNotes/entityInformation/fields') { return J @{ fields = @((J @{ name = 'publish'; picklistValues = @((J @{ value = '1'; label = 'All Autotask Users'; isActive = $true }), (J @{ value = '2'; label = 'Internal Only'; isActive = $true })) }), (J @{ name = 'noteType'; picklistValues = @((J @{ value = '13'; label = 'System Workflow Note'; isActive = $true }), (J @{ value = '1'; label = 'Task Detail'; isActive = $true })) })) } }
        if ($m -eq 'GET' -and $u -like '*/TicketNotes/query?*') { $i = 0; return J @{ items = @($Sc.notes | ForEach-Object { $i++; J @{ id = $i; description = $_.text; publish = $(if ($_.internal) { 2 } else { 1 }); creatorResourceID = 1 } }); pageDetails = (J @{ nextPageUrl = $null }) } }
        if ($m -eq 'POST' -and $u -like '*/Tickets/12345/Notes') { $b = $c.Body | ConvertFrom-Json; $null = $Sc.notes.Add(@{ text = [string]$b.description; internal = ([string]$b.publish -eq '2') }); return J @{ itemId = $Sc.notes.Count } }
    }
    if ($u -like 'https://halo.example/*') {
        if ($u -like '*/auth/token') { return J @{ access_token = 'halo-tok' } }
        if ($m -eq 'GET' -and $u -like '*/api/Actions?ticket_id=12345*') { $i = 0; return J @{ actions = @($Sc.notes | ForEach-Object { $i++; J @{ id = $i; note = $_.text; hiddenfromuser = $_.internal; who_type = 1 } }) } }
        if ($m -eq 'POST' -and $u -like '*/api/Actions') { $b = @($c.Body | ConvertFrom-Json)[0]; $null = $Sc.notes.Add(@{ text = [string]$b.note; internal = [bool]$b.hiddenfromuser }); return @(J @{ id = $Sc.notes.Count }) }
    }
    throw "unmocked $m $u"
}

# ---------- Exchange Online PowerShell module mocks (module mode) ----------
function Get-Module { [CmdletBinding()] param([switch]$ListAvailable, [string]$Name) if ($Sc.module) { return J @{ Name = 'ExchangeOnlineManagement'; Version = '3.5.0' } }; return $null }
function Import-Module { [CmdletBinding()] param([string]$Name) }
function Connect-ExchangeOnline { [CmdletBinding()] param($AppId, $Organization, $CertificateThumbprint, $Certificate, [switch]$ShowBanner) $Sc.connected = "$AppId|$Organization|$CertificateThumbprint" }
function Get-Mailbox { [CmdletBinding()] param($Identity) Invoke-FakeExo 'Get-Mailbox' @{ Identity = $Identity } }
function Get-MailboxStatistics { [CmdletBinding()] param($Identity) Invoke-FakeExo 'Get-MailboxStatistics' @{ Identity = $Identity } }
# _shared/exchange.ps1 runs every non-Get cmdlet with -Confirm:$false in module mode, so Set-Mailbox takes -Confirm.
function Set-Mailbox { [CmdletBinding(SupportsShouldProcess)] param($Identity, $Type, $HiddenFromAddressListsEnabled, $ForwardingAddress, $DeliverToMailboxAndForward) $h = @{ Identity = $Identity }; foreach ($k in $PSBoundParameters.Keys) { if ($k -ne 'Identity' -and $k -ne 'Confirm') { $h[$k] = $PSBoundParameters[$k] } }; Invoke-FakeExo 'Set-Mailbox' $h }

# ---------- runner ----------
$Node = @{ In = $null; Out = $null }
function Get-NodeInput { param($Name) return $Node.In }
function Set-NodeOutput { param($o) $Node.Out = $o }
function Invoke-Step {
    param([string]$Script, $Input0)
    $Node.In = $Input0; $Node.Out = $null; $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Script)) } catch { $err = [string]$_.Exception.Message }
    return @{ out = $Node.Out; err = $err }
}
# Runs both steps; the Read output reaches Apply through a JSON round trip, as it does on the runner.
function Invoke-Offboard {
    param($Body)
    $r = Invoke-Step $ReadScript $Body
    $json = $null; if ($null -ne $r.out) { $json = ($r.out | ConvertTo-Json -Depth 20 | ConvertFrom-Json) }
    $a = Invoke-Step $ApplyScript ([pscustomobject]@{ prep = $json })
    if ($ShowNotes -and $null -ne $a.out) { Write-Host "----- $($a.out.status): $($a.out.message)`n$($a.out.internal_note)`n-----" -ForegroundColor DarkGray }
    return @{ read = $r.out; readErr = $r.err; out = $a.out; err = $a.err }
}
function New-Body { param([hashtable]$Over = @{}) $b = [ordered]@{ upn = 'sam.doe@contoso.com'; forward_to_manager = 'true'; keep_licenses_days = '0'; confirm = 'false'; requester_email = 'alex.kim@contoso.com'; psa = ''; ticket_id = '12345'; company_id = '42' }; foreach ($k in $Over.Keys) { $b[$k] = $Over[$k] }; return [pscustomobject]$b }
function Get-GraphWrites { return @($Mock.Calls | Where-Object { $_.Uri -like "$GraphBase/*" -and $_.Method -ne 'GET' }) }
function Get-ExoWrites { return @($Sc.exoLog | Where-Object { $_ -like 'Set-*' }) }
function Get-PsaNotes { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and ($_.Uri -like 'https://cw.example/*' -or $_.Uri -like 'https://at.example/*Notes' -or $_.Uri -like 'https://halo.example/api/Actions') }) }
function Get-ArchiveWrites { return @(Get-Calls 'POST' 'https://cr.example/v2/archiveitem') }
function Get-Index { param([string]$Like) for ($i = 0; $i -lt $Sc.order.Count; $i++) { if ($Sc.order[$i] -like $Like) { return $i } }; return -1 }

# =================== 1. preview (ConnectWise, Exchange over REST) ===================
New-Scenario 'connectwise' 'rest'
$r = Invoke-Offboard (New-Body)
$o = $r.out
Check 'preview: read step is ok' ($r.read.status -eq 'ok' -and -not $r.readErr) "$($r.read.status) $($r.read.message) $($r.readErr)"
Check 'preview: pending_confirmation, no error' ($o.status -eq 'pending_confirmation' -and -not $r.err) "$($o.status) $($r.err)"
Check 'preview: no Graph writes' (@(Get-GraphWrites).Count -eq 0) (Show-Calls)
Check 'preview: no Exchange writes' (@(Get-ExoWrites).Count -eq 0) ($Sc.exoLog -join ' | ')
Check 'preview: no archive item, no public note' (@(Get-ArchiveWrites).Count -eq 0 -and @(Get-PsaNotes).Count -eq 1) (Show-Calls)
$pl = @($o.planned)
$iOf = { param($like) for ($i = 0; $i -lt $pl.Count; $i++) { if ($pl[$i] -like $like) { return $i } }; return -1 }
Check 'preview: plan holds every change' ($pl.Count -eq 10 -and (& $iOf 'Block sign-in') -eq 0 -and (& $iOf 'Reset the password*') -eq 1 -and (& $iOf 'Sign out*') -eq 2) ($pl -join ' | ')
Check 'preview: order is groups, mailbox, licence group, licences' ((& $iOf 'Remove from Sales Team*') -lt (& $iOf 'Convert the mailbox*') -and (& $iOf 'Convert the mailbox*') -lt (& $iOf 'Hide from*') -and (& $iOf 'Forward new mail to Alex Kim*') -gt 0 -and (& $iOf 'Remove from M365 E3 Licensing*') -gt (& $iOf 'Forward new mail*') -and (& $iOf 'Remove the licences: O365_BUSINESS_PREMIUM') -eq 9) ($pl -join ' | ')
Check 'preview: distribution list, mail-enabled security, dynamic and synced groups are not in the Graph plan' (-not ($pl -match 'All Staff|Finance Share|dynamic|VPN')) ($pl -join ' | ')
Check 'preview: those are follow-up items with commands' ((@($o.follow_up) -match "Remove-DistributionGroupMember -Identity 'allstaff@contoso.com' -Member 'sam.doe@contoso.com'").Count -eq 1 -and (@($o.follow_up) -match 'Finance Share').Count -eq 1 -and (@($o.follow_up) -match 'dynamic group').Count -eq 1 -and (@($o.follow_up) -match 'VPN Users in on-premises').Count -eq 1) (@($o.follow_up) -join ' | ')
Check 'preview: internal note posted to ConnectWise, internal tab' ((Read-Body @(Get-PsaNotes)[0]).internalAnalysisFlag -eq $true -and (Read-Body @(Get-PsaNotes)[0]).text -match 'Preview only') ((@(Get-PsaNotes)[0]).Body)
Check 'preview: report-only items in the note' ($o.internal_note -match 'Pat Lee' -and $o.internal_note -match 'CONTOSO-LT-042') $o.internal_note
Check 'preview: public note is generic' ($o.public_note -notmatch 'sam|Sales|licen|password' -and $o.public_note -match 'technician will review') $o.public_note
Check 'preview: Exchange read through REST with the extension secrets' ($r.read.exchange.mode -eq 'rest' -and $r.read.exchange.mailbox -eq 'user' -and @(Get-Calls 'POST' "$ExoBase/$TenantGuid/InvokeCommand").Count -ge 2) ($r.read.exchange | ConvertTo-Json -Compress)

# =================== 2. confirm (ConnectWise, REST) ===================
New-Scenario 'connectwise' 'rest'
$r = Invoke-Offboard (New-Body @{ confirm = 'true' })
$o = $r.out
Check 'confirm: success' ($o.status -eq 'success' -and -not $r.err) "$($o.status) $($o.message) $($r.err)"
Check 'confirm: security first' (($Sc.order[0..2] -join ',') -eq 'graph:disable,graph:password,graph:revoke') ($Sc.order -join ',')
Check 'confirm: mailbox converted before any licence goes' ((Get-Index 'exo:Set-Mailbox:Type') -gt 0 -and (Get-Index 'exo:Set-Mailbox:Type') -lt (Get-Index 'graph:remove:g-lic') -and (Get-Index 'graph:remove:g-lic') -lt (Get-Index 'graph:licence')) ($Sc.order -join ',')
Check 'confirm: non-licence groups removed before the mailbox' ((Get-Index 'graph:remove:g-sales') -lt (Get-Index 'exo:Set-Mailbox:Type') -and (Get-Index 'graph:remove:g-team') -gt 0 -and (Get-Index 'graph:remove:g-list') -eq -1 -and (Get-Index 'graph:remove:g-dyn') -eq -1) ($Sc.order -join ',')
Check 'confirm: hidden and forwarded to the manager' (($Sc.exoLog -match 'HiddenFromAddressListsEnabled":true').Count -eq 1 -and ($Sc.exoLog -match 'ForwardingAddress":"alex.kim@contoso.com"').Count -eq 1) ($Sc.exoLog -join ' | ')
$lic = Read-Body @(Get-Calls 'POST' "$GraphBase/v1.0/users/u-sam/assignLicense")[0]
Check 'confirm: only the direct licence is removed' (@($lic.removeLicenses).Count -eq 1 -and $lic.removeLicenses[0] -eq 'sku-bs') ($lic | ConvertTo-Json -Compress)
$pw = [string]$Sc.password
$everything = ($o | ConvertTo-Json -Depth 20) + (@($Mock.Calls | Where-Object { $_.Uri -notlike "$GraphBase/v1.0/users/u-sam" } | ForEach-Object { $_.Body }) -join ' ')
Check 'confirm: password is random and never output, noted or reported' ($pw.Length -eq 24 -and -not $everything.Contains($pw)) "len $($pw.Length)"
$ar = @(Get-ArchiveWrites)
$arBody = Read-Body $ar[0]
Check 'confirm: completion report in archive Offboarding' ($ar.Count -eq 1 -and (Read-Body @(Get-Calls 'POST' 'https://cr.example/api/beta/archive')[0]).name -eq 'Offboarding' -and $arBody.text -match 'Convert the mailbox' -and $arBody.text -match 'allstaff@contoso.com' -and $arBody.isError -eq $false) (Show-Calls)
$notes = @(Get-PsaNotes)
Check 'confirm: internal report note plus a generic public note' ($notes.Count -eq 2 -and (Read-Body $notes[0]).internalAnalysisFlag -eq $true -and (Read-Body $notes[1]).detailDescriptionFlag -eq $true -and (Read-Body $notes[1]).text -cmatch "^The offboarding request has been processed\.`nRef: [0-9a-f]{8}$") (($notes | ForEach-Object { $_.Body }) -join ' || ')
Check 'confirm: message says what is left' ($o.message -match 'Offboarded sam.doe@contoso.com with 10 changes' -and $o.message -match 'left for a technician' -and $o.licences_removed -eq $true) $o.message

# =================== 3. no Exchange on the runner (Autotask) ===================
New-Scenario 'autotask' 'none'
$r = Invoke-Offboard (New-Body @{ confirm = 'true'; psa = 'autotask' })
$o = $r.out
Check 'no Exchange: run still succeeds' ($o.status -eq 'success' -and -not $r.err) "$($o.status) $($o.message) $($r.err)"
Check 'no Exchange: licences and licence group kept' ((Get-Index 'graph:licence') -eq -1 -and (Get-Index 'graph:remove:g-lic') -eq -1 -and $o.licences_removed -eq $false) ($Sc.order -join ',')
Check 'no Exchange: security and cloud groups still done' ((Get-Index 'graph:disable') -eq 0 -and (Get-Index 'graph:remove:g-sales') -gt 0) ($Sc.order -join ',')
Check 'no Exchange: exact commands for a technician' ((@($o.follow_up) -match "^Not done, do this in Exchange: Set-Mailbox -Identity 'sam.doe@contoso.com' -Type Shared$").Count -eq 1 -and (@($o.follow_up) -match 'HiddenFromAddressListsEnabled \$true').Count -eq 1 -and (@($o.follow_up) -match "ForwardingAddress 'alex.kim@contoso.com' -DeliverToMailboxAndForward").Count -eq 1) (@($o.follow_up) -join ' | ')
Check 'no Exchange: says why licences stayed' ($o.internal_note -match "Licences kept: O365_BUSINESS_PREMIUM .*isn't lost" -and $o.internal_note -match 'MicrosoftExchange-TenantId') $o.internal_note
$atNotes = @(Get-Calls 'POST' 'https://at.example/atservicesrest/v1.0/Tickets/12345/Notes')
Check 'no Exchange: Autotask internal note then public note' ($atNotes.Count -eq 2 -and (Read-Body $atNotes[0]).publish -eq 2 -and (Read-Body $atNotes[1]).publish -eq 1) (Show-Calls)

# =================== 4. no Exchange, technician already converted the mailbox ===================
New-Scenario 'connectwise' 'none'
$r = Invoke-Offboard (New-Body @{ confirm = 'true'; mailbox_already_shared = 'true' })
Check 'mailbox_already_shared: licences removed' ($r.out.status -eq 'success' -and (Get-Index 'graph:licence') -gt (Get-Index 'graph:remove:g-lic')) ($Sc.order -join ',')
Check 'mailbox_already_shared: no convert command left, hide still listed' ((@($r.out.follow_up) -match '-Type Shared').Count -eq 0 -and (@($r.out.follow_up) -match 'HiddenFromAddressListsEnabled').Count -eq 1) (@($r.out.follow_up) -join ' | ')

# =================== 5. Exchange Online PowerShell module with a certificate (HaloPSA) ===================
New-Scenario 'halopsa' 'module'
$r = Invoke-Offboard (New-Body @{ confirm = 'true'; psa = 'halopsa' })
Check 'module: connects with the certificate' ($Sc.connected -eq 'exo-app|contoso.onmicrosoft.com|ABCDEF0123456789' -and $r.read.exchange.mode -eq 'module') "$($Sc.connected) $($r.read.exchange.mode) $($r.read.exchange.reason)"
Check 'module: converts, then removes licences' ($r.out.status -eq 'success' -and (Get-Index 'exo:Set-Mailbox:Type') -lt (Get-Index 'graph:licence')) "$($r.out.message) / $($Sc.order -join ',')"
Check 'module: no REST Exchange calls' (@(Get-Calls 'POST' "$ExoBase/*").Count -eq 0) (Show-Calls)
$halo = @(Get-Calls 'POST' 'https://halo.example/api/Actions')
Check 'module: HaloPSA private note then public note' ($halo.Count -eq 2 -and (Read-Body $halo[0])[0].hiddenfromuser -eq $true -and (Read-Body $halo[1])[0].hiddenfromuser -eq $false) (Show-Calls)

# =================== 6. module listed but not installed, no REST secrets ===================
New-Scenario 'connectwise' 'module' @{ module = $false }
$r = Invoke-Offboard (New-Body)
Check 'module missing: says so, keeps licences' ($r.read.exchange.available -eq $false -and $r.read.exchange.reason -match 'ExchangeOnlineManagement PowerShell module is not installed' -and -not ($r.out.planned -match 'licences')) "$($r.read.exchange.reason)"

# =================== 7. mailbox conversion fails: licences must stay ===================
New-Scenario 'connectwise' 'rest' @{ failConvert = $true }
$r = Invoke-Offboard (New-Body @{ confirm = 'true' })
$o = $r.out
Check 'convert fails: run marked failed with output kept' ($o.status -eq 'error' -and $r.err -match 'Convert the mailbox') "$($o.status) $($r.err)"
Check 'convert fails: no licence or licence group removed' ((Get-Index 'graph:licence') -eq -1 -and (Get-Index 'graph:remove:g-lic') -eq -1) ($Sc.order -join ',')
Check 'convert fails: report lists what ran, failed and did not run' ((Read-Body @(Get-ArchiveWrites)[0]).isError -eq $true -and $o.internal_note -match 'Not done because an earlier change failed' -and @($o.not_run) -match 'Remove the licences') $o.internal_note
Check 'convert fails: no public "processed" note' (@(Get-PsaNotes).Count -eq 1) (Show-Calls)

New-Scenario 'connectwise' 'rest' @{ convertNoop = $true }
$r = Invoke-Offboard (New-Body @{ confirm = 'true' })
Check 'convert accepted but not shared: licences stay' ($r.out.status -eq 'error' -and (Get-Index 'graph:licence') -eq -1 -and $r.out.failed.error -match 'still isn''t shared') "$($r.out.failed | ConvertTo-Json -Compress)"

# =================== 8. admin accounts and self-offboarding fail closed ===================
New-Scenario 'connectwise' 'rest' @{ roles = @('Global Administrator') }
$r = Invoke-Offboard (New-Body @{ confirm = 'true' })
Check 'admin: rejected, nothing changed' ($r.out.status -eq 'rejected' -and $r.err -match 'admin roles \(Global Administrator\)' -and @(Get-GraphWrites).Count -eq 0 -and @(Get-ExoWrites).Count -eq 0) "$($r.out.status) $($r.err)"
New-Scenario 'connectwise' 'rest' @{ roles = @('Global Administrator') }
$r = Invoke-Offboard (New-Body @{ confirm = 'true'; allow_admin = 'true' })
Check 'admin with allow_admin: proceeds, warns, reports the role' ($r.out.status -eq 'success' -and (@($r.out.warnings) -match 'Privileged Authentication Administrator').Count -eq 1 -and $r.out.internal_note -match 'Admin role still assigned, remove by hand: Global Administrator') "$($r.out.status) $($r.out.message)"
New-Scenario 'connectwise' 'rest'
$r = Invoke-Offboard (New-Body @{ confirm = 'true'; requester_email = 'SAM@contoso.com' })
Check 'self: requester matching a proxy address is rejected' ($r.out.status -eq 'rejected' -and $r.err -match 'their own account' -and @(Get-GraphWrites).Count -eq 0) "$($r.out.status) $($r.err)"
New-Scenario 'connectwise' 'rest'
$r = Invoke-Offboard (New-Body @{ confirm = 'true'; requester_email = ''; requester_office_id = 'u-sam' })
Check 'self: requester office id matching is rejected' ($r.out.status -eq 'rejected' -and @(Get-GraphWrites).Count -eq 0) "$($r.out.status) $($r.err)"
New-Scenario 'connectwise' 'rest'
$r = Invoke-Offboard (New-Body @{ requester_email = 'sam.doe@contoso.com' })
Check 'self: same UPN rejected before any Graph call' ($r.out.status -eq 'rejected' -and @($Mock.Calls | Where-Object { $_.Uri -like "$GraphBase/*" }).Count -eq 0) (Show-Calls)

# =================== 9. missing permissions (403) ===================
New-Scenario 'connectwise' 'rest' @{ forbid = @('^GET /v1\.0/users/u-sam/transitiveMemberOf') }
$r = Invoke-Offboard (New-Body @{ confirm = 'true' })
Check '403 on roles: fails closed naming the permission' ($r.out.status -eq 'error' -and $r.err -match 'RoleManagement\.Read\.Directory' -and @(Get-GraphWrites).Count -eq 0) $r.err
New-Scenario 'connectwise' 'rest' @{ forbid = @('^DELETE /v1\.0/groups/g-team/') }
$r = Invoke-Offboard (New-Body @{ confirm = 'true' })
Check '403 on a group: stops, names GroupMember.ReadWrite.All, licences untouched' ($r.out.status -eq 'error' -and $r.err -match 'GroupMember\.ReadWrite\.All' -and (Get-Index 'graph:licence') -eq -1 -and (Get-Index 'exo:Set-Mailbox:Type') -eq -1) "$($r.err)"

# =================== 10. empty results ===================
New-Scenario 'connectwise' 'rest'
$r = Invoke-Offboard (New-Body @{ upn = 'nobody@contoso.com' })
Check 'unknown user: incomplete, nothing changed' ($r.out.status -eq 'incomplete' -and $r.err -match 'No Microsoft 365 user' -and @(Get-GraphWrites).Count -eq 0) "$($r.out.status) $($r.err)"
New-Scenario 'connectwise' 'rest' @{ member = @(); states = @(); plans = @(); mailbox = $null; enabled = $false; manager = $null }
$r = Invoke-Offboard (New-Body @{ confirm = 'true' })
Check 'bare user: only password and sessions, no mailbox steps' ($r.out.status -eq 'success' -and ($Sc.order -join ',') -eq 'graph:password,graph:revoke' -and $r.read.exchange.mailbox -eq 'none') "$($r.out.message) / $($Sc.order -join ',')"
Check 'bare user: warns about no manager and already blocked' ((@($r.out.warnings) -match 'has no manager').Count -eq 1 -and (@($r.out.warnings) -match 'already blocked').Count -eq 1) (@($r.out.warnings) -join ' | ')
$r = Invoke-Offboard $null
Check 'no input: incomplete' ($r.out.status -eq 'incomplete') "$($r.out.status)"

# =================== 11. keep licences, tenant mismatch, synced user, no company id ===================
New-Scenario 'connectwise' 'rest'
$r = Invoke-Offboard (New-Body @{ confirm = 'true'; keep_licenses_days = '30' })
Check 'keep_licenses_days: mailbox converted, licences kept with a date' ($r.out.status -eq 'success' -and (Get-Index 'exo:Set-Mailbox:Type') -gt 0 -and (Get-Index 'graph:licence') -eq -1 -and $r.out.internal_note -match 'kept for 30 days as asked') $r.out.internal_note
New-Scenario 'connectwise' 'rest'
$r = Invoke-Offboard (New-Body @{ keep_licenses_days = 'thirty' })
Check 'keep_licenses_days not a number: incomplete' ($r.out.status -eq 'incomplete') "$($r.out.status)"
New-Scenario 'connectwise' 'rest'
$r = Invoke-Offboard (New-Body @{ company_tenant_id = '11111111-2222-4333-8444-555555555555' })
Check 'tenant mismatch: rejected' ($r.out.status -eq 'rejected' -and $r.err -match 'tenant') "$($r.out.status) $($r.err)"
New-Scenario 'connectwise' 'rest' @{ synced = $true }
$r = Invoke-Offboard (New-Body @{ confirm = 'true' })
Check 'synced user: no sign-in or password change, AD steps listed' ($r.out.status -eq 'success' -and (Get-Index 'graph:disable') -eq -1 -and (Get-Index 'graph:password') -eq -1 -and (Get-Index 'graph:revoke') -eq 0 -and (@($r.out.follow_up) -match 'on-premises Active Directory').Count -ge 2) (@($r.out.follow_up) -join ' | ')
New-Scenario 'connectwise' 'rest'
$r = Invoke-Offboard (New-Body @{ confirm = 'true'; company_id = '' })
Check 'no company id: no archive write, warning, still success' ($r.out.status -eq 'success' -and @(Get-ArchiveWrites).Count -eq 0 -and (@($r.out.warnings) -match 'No CloudRadial company id').Count -eq 1) (@($r.out.warnings) -join ' | ')
New-Scenario 'connectwise' 'rest'
$r = Invoke-Offboard ([pscustomobject]@{ Ticket = [pscustomobject]@{ TicketId = 12345; Questions = @([pscustomobject]@{ Id = 'upn'; Value = 'sam.doe@contoso.com' }, [pscustomobject]@{ Id = 'forward_to'; Value = '@forward_to' }) }; Company = [pscustomobject]@{ CompanyTenantId = $TenantGuid } })
Check 'CloudRadial form shape: parsed, literal token ignored, preview' ($r.out.status -eq 'pending_confirmation' -and $r.read.ticket_id -eq '12345' -and -not ($r.out.planned -match 'Forward')) "$($r.out.status) $($r.read.message)"
New-Scenario 'connectwise' 'rest' @{ lit = $true }
$r = Invoke-Offboard (New-Body)
Check 'litigation hold: licences kept' (-not ($r.out.planned -match 'licences') -and $r.out.internal_note -match 'litigation hold') $r.out.internal_note

# =================== rerun writes nothing twice (ServiceAI Action Runs Retry) ===================
New-Scenario 'connectwise' 'rest'
$null = Invoke-Offboard (New-Body)
$first = @(Get-PsaNotes).Count
$r = Invoke-Offboard (New-Body)
Check 'rerun preview: no second internal note' ($first -eq 1 -and @(Get-PsaNotes).Count -eq 1 -and $Sc.notes[0].text -match '\[offboarding preview sam\.doe@contoso\.com [0-9a-f]{8}\]' -and (@($r.out.actions) -match 'already on ticket 12345').Count -eq 1) "$first / $(@(Get-PsaNotes).Count) / $(@($r.out.actions) -join ' | ')"
$null = Invoke-Offboard (New-Body @{ forward_to_manager = 'false' })
Check 'preview with a different plan: gets its own note' (@(Get-PsaNotes).Count -eq 2) (Show-Calls)
$null = Invoke-Offboard (New-Body @{ confirm = 'true' })
$afterConfirm = @(Get-PsaNotes).Count
$r = Invoke-Offboard (New-Body @{ confirm = 'true' })
Check 'rerun confirm: report and public note not written again' ($afterConfirm -eq 4 -and @(Get-PsaNotes).Count -eq 4 -and (@($r.out.actions) -match 'already on ticket').Count -eq 2) "$afterConfirm / $(@(Get-PsaNotes).Count) / $(@($r.out.actions) -join ' | ')"
New-Scenario 'autotask' 'none'
$null = Invoke-Offboard (New-Body @{ confirm = 'true'; psa = 'autotask' })
$n1 = @(Get-PsaNotes).Count
$null = Invoke-Offboard (New-Body @{ confirm = 'true'; psa = 'autotask' })
Check 'rerun on Autotask: nothing written twice' ($n1 -ge 1 -and @(Get-PsaNotes).Count -eq $n1) "$n1 / $(@(Get-PsaNotes).Count)"
$pub = @($Sc.notes | Where-Object { -not $_.internal })
Check 'public notes: only the message and an opaque Ref, no marker, address or internal status word' ($pub.Count -ge 1 -and @($pub | Where-Object { $_.text -match '\[|@|sam\.doe|success|pending|preview|error|incomplete|rejected' -or $_.text -notmatch '\nRef: [0-9a-f]{8}$' }).Count -eq 0) (@($pub | ForEach-Object { $_.text }) -join ' || ')
$int = @($Sc.notes | Where-Object { $_.internal })
Check 'internal notes keep the readable marker' (@($int | Where-Object { $_.text -match '\[offboarding success sam\.doe@contoso\.com\]$' }).Count -eq 1) (@($int | ForEach-Object { $_.text }) -join ' || ')

Complete-Test
