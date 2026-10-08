# Mock harness for shared-mailbox-dl.yml: fake Key Vault, Microsoft Graph, Exchange Online (REST and the
# ExchangeOnlineManagement module), PSAs and node I/O. Runs both step scripts exactly as they ship (extracted from
# the built .yml) through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest.
# Placeholder data only (Contoso, Example MSP).
# Usage: node build.js --check; pwsh -NoProfile -File test.ps1 [-ShowNotes]   (needs js-yaml, or JS_YAML_PATH)
param([switch]$ShowNotes)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')
$ErrorActionPreference = 'Stop'

# ---------- extract the step scripts from the built workflow ----------
$tmp = Join-Path ([IO.Path]::GetTempPath()) "shared-mailbox-dl-test-$PID"
New-Item -ItemType Directory -Force $tmp | Out-Null
$extract = "const p=require('path');let y;try{y=require('js-yaml')}catch{try{y=require(p.join(process.argv[3],'node_modules','js-yaml'))}catch{y=require(process.env.JS_YAML_PATH)}};const w=y.load(require('fs').readFileSync(process.argv[1],'utf8'));for(const a of w.definition.activities){if(a.type==='powershell-script')require('fs').writeFileSync(p.join(process.argv[2],a.id+'.ps1'),a.properties.script)}"
& node -e $extract (Join-Path $PSScriptRoot '..\shared-mailbox-dl.yml') $tmp $Shared
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the step scripts (is js-yaml installed, or JS_YAML_PATH set?)' }
$ReadScript = Get-Content -Raw (Join-Path $tmp 'node-read.ps1')
$ApplyScript = Get-Content -Raw (Join-Path $tmp 'node-apply.ps1')
Remove-Item -Recurse -Force $tmp

# ---------- placeholder data ----------
$GraphBase = 'https://graph.microsoft.com'
$ExoBase = 'https://outlook.office365.com/adminapi/beta'
$TenantGuid = '0a1b2c3d-0000-4000-8000-00000000c0de'
$BaseSecrets = @{ 'M365-TenantId' = $TenantGuid; 'M365-ClientId' = 'app-id'; 'M365-ClientSecret' = 'not-a-real-secret' }
$ExoRestSecrets = @{ 'MicrosoftExchange-TenantId' = $TenantGuid; 'MicrosoftExchange-ClientId' = 'exo-app'; 'MicrosoftExchange-ClientSecret' = 'not-a-real-secret' }
$ExoCertSecrets = @{ 'MicrosoftExchange-ClientId' = 'exo-app'; 'MicrosoftExchange-CertificateThumbprint' = 'ABCDEF0123456789' }
$PsaSecrets = @{
    connectwise = @{ 'CW-ApiUrl' = 'https://cw.example/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'Autotask-ApiUrl' = 'https://at.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@examplemsp.com'; 'Autotask-Secret' = 's' }
    halopsa     = @{ 'Halo-ApiUrl' = 'https://halo.example'; 'Halo-ClientId' = 'id'; 'Halo-ClientSecret' = 's' }
}
$BasePeople = @(
    @{ id = 'u-alex'; userPrincipalName = 'alex.kim@contoso.com'; displayName = 'Alex Kim'; mail = 'alex.kim@contoso.com'; department = 'Sales'; accountEnabled = $true; userType = 'Member'; proxyAddresses = @('SMTP:alex.kim@contoso.com') }
    @{ id = 'u-sam'; userPrincipalName = 'sam.doe@contoso.com'; displayName = 'Sam Doe'; mail = 'sam.doe@contoso.com'; department = 'sales'; accountEnabled = $true; userType = 'Member'; proxyAddresses = @('SMTP:sam.doe@contoso.com', 'smtp:sam@contoso.com') }
    @{ id = 'u-pat'; userPrincipalName = 'pat.lee@contoso.com'; displayName = 'Pat Lee'; mail = 'pat.lee@contoso.com'; department = 'Finance'; accountEnabled = $true; userType = 'Member'; proxyAddresses = @('SMTP:pat.lee@contoso.com') }
    @{ id = 'u-jo'; userPrincipalName = 'jo.room@contoso.com'; displayName = 'Jo Room'; mail = $null; department = 'Sales'; accountEnabled = $true; userType = 'Member'; proxyAddresses = @() }
)

$Sc = @{}
function New-Scenario {
    param([string]$Psa = 'connectwise', [string]$Exo = 'rest', [hashtable]$Over = @{})
    $Sc.Clear()
    $Sc.people = New-Object System.Collections.ArrayList
    foreach ($p in $BasePeople) { $null = $Sc.people.Add($p.Clone()) }
    $Sc.forbid = @()                 # Graph "METHOD path" regexes that answer 403
    $Sc.recipients = @{}             # Exchange recipients that already exist, by lower-case identity
    $Sc.groupsTaken = @()            # Graph groups that already hold an address
    $Sc.failOn = ''                  # Exchange cmdlet that fails
    $Sc.notFoundOnce = ''            # Exchange cmdlet that answers "couldn't be found" on its first call
    $Sc.module = ($Exo -eq 'module' -or $Exo -eq 'both')
    $Sc.exoTokenFail = $false
    $Sc.exoLog = New-Object System.Collections.ArrayList
    $Sc.exoParams = New-Object System.Collections.ArrayList
    $Sc.notes = New-Object System.Collections.ArrayList   # @{ text; internal } for every note written, read back by the marker check
    foreach ($k in $Over.Keys) { $Sc[$k] = $Over[$k] }
    $sec = $BaseSecrets.Clone()
    if ($Psa) { foreach ($k in $PsaSecrets[$Psa].Keys) { $sec[$k] = $PsaSecrets[$Psa][$k] }; $sec['PSA-Type'] = $Psa }
    if ($Exo -eq 'rest' -or $Exo -eq 'both') { foreach ($k in $ExoRestSecrets.Keys) { $sec[$k] = $ExoRestSecrets[$k] } }
    if ($Exo -eq 'module' -or $Exo -eq 'both') { foreach ($k in $ExoCertSecrets.Keys) { $sec[$k] = $ExoCertSecrets[$k] } }
    Reset-Mock $sec $Handler
}
function Add-SalesPeople { param([int]$Count) for ($i = 1; $i -le $Count; $i++) { $null = $Sc.people.Add(@{ id = "u-s$i"; userPrincipalName = "seller$i@contoso.com"; displayName = "Seller $i"; mail = "seller$i@contoso.com"; department = 'Sales'; accountEnabled = $true; userType = 'Member'; proxyAddresses = @() }) } }
function J { param($o) [pscustomobject]$o }
function Get-PVal { param($P, [string]$k) if ($P -is [System.Collections.IDictionary]) { if ($P.Contains($k)) { return $P[$k] }; return $null }; $x = $P.PSObject.Properties[$k]; if ($x) { return $x.Value }; return $null }
function Find-Person { param([scriptblock]$Where) return @($Sc.people | Where-Object $Where) }

# One Exchange cmdlet, shared by the REST and module mocks.
function Invoke-FakeExo {
    param([string]$Name, $P)
    $null = $Sc.exoLog.Add($Name); $null = $Sc.exoParams.Add(@{ name = $Name; p = $P })
    if ($Name -eq 'Get-Recipient') {
        $id = ([string](Get-PVal $P 'Identity')).ToLowerInvariant()
        if ($Sc.recipients.Contains($id)) { return @(J $Sc.recipients[$id]) }
        throw "The operation couldn't be performed because object '$id' couldn't be found on 'EXAMPLE.PROD.OUTLOOK.COM'."
    }
    if ($Sc.failOn -eq $Name) { throw "$Name couldn't be completed (simulated)." }
    if ($Sc.notFoundOnce -eq $Name) { $Sc.notFoundOnce = ''; throw "The operation couldn't be performed because object 'new' couldn't be found on 'EXAMPLE.PROD.OUTLOOK.COM'." }
    if (@('New-Mailbox', 'New-DistributionGroup') -contains $Name) {
        # What it creates now exists, so a rerun finds the address taken.
        $rec = @{ DisplayName = [string](Get-PVal $P 'DisplayName'); RecipientTypeDetails = $(if ($Name -eq 'New-Mailbox') { 'SharedMailbox' } else { 'MailUniversalDistributionGroup' }) }
        foreach ($k in @('PrimarySmtpAddress', 'Alias')) { $v = [string](Get-PVal $P $k); if ($v) { $Sc.recipients[$v.ToLowerInvariant()] = $rec } }
    }
    if (@('New-Mailbox', 'New-DistributionGroup', 'Add-MailboxPermission', 'Add-RecipientPermission', 'Add-DistributionGroupMember') -contains $Name) { return @(J @{ Identity = (Get-PVal $P 'Identity') }) }
    throw "unmocked Exchange cmdlet $Name"
}
function Get-ExoWrites { return @($Sc.exoLog | Where-Object { $_ -notlike 'Get-*' }) }
function Get-ExoCall { param([string]$Name, [int]$N = 0) return @($Sc.exoParams | Where-Object { $_.name -eq $Name })[$N].p }

$Handler = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    $m = $c.Method
    if ($u -like 'https://login.microsoftonline.com/*') {
        $scope = ''; if ($c.BodyObj -is [hashtable]) { $scope = [string]$c.BodyObj.scope }
        if ($scope -like 'https://outlook.office365.com/*') { $Sc.exoTokens = 1 + $(if ($Sc.Contains('exoTokens')) { $Sc.exoTokens } else { 0 }); if ($Sc.Contains('exoTokenFailFrom') -and $Sc.exoTokens -ge $Sc.exoTokenFailFrom) { New-HttpError 400 '{"error":"invalid_request","error_description":"The service is unavailable."}' } }
        if ($scope -like 'https://outlook.office365.com/*' -and $Sc.exoTokenFail) { New-HttpError 401 '{"error":"invalid_client","error_description":"AADSTS7000215: Invalid client secret provided."}' }
        return J @{ access_token = $(if ($scope -like 'https://outlook*') { 'exo-tok' } else { 'tok' }); expires_in = 3599 }
    }
    if ($u -like "$ExoBase/*/InvokeCommand") {
        $b = $c.Body | ConvertFrom-Json
        try { $r = @(Invoke-FakeExo $b.CmdletInput.CmdletName $b.CmdletInput.Parameters) }
        catch { $msg = $_.Exception.Message -replace '"', "'"; if ($msg -match "couldn't be found") { New-HttpError 404 "{`"error`":{`"code`":`"NotFound`",`"message`":`"$msg`"}}" }; New-HttpError 400 "{`"error`":{`"code`":`"BadRequest`",`"message`":`"$msg`"}}" }
        return J @{ value = $r }
    }
    if ($u -like "$GraphBase/*") {
        $p = $u.Substring($GraphBase.Length)
        foreach ($f in @($Sc.forbid)) { if ("$m $p" -match $f) { New-HttpError 403 '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}' } }
        if ($m -eq 'GET') {
            if ($p -match '^/v1\.0/domains') { return J @{ value = @((J @{ id = 'contoso.com'; isDefault = $true; isVerified = $true; isInitial = $false }), (J @{ id = 'contoso.onmicrosoft.com'; isDefault = $false; isVerified = $true; isInitial = $true }), (J @{ id = 'fabrikam.com'; isDefault = $false; isVerified = $false; isInitial = $false })) } }
            if ($p -match '^/v1\.0/users/([^/?]+)\?') {
                $k = $Matches[1].ToLowerInvariant(); $hit = @(Find-Person { $_.id -eq $k -or $_.userPrincipalName -eq $k })
                if (-not $hit.Count) { New-HttpError 404 '{"error":{"code":"Request_ResourceNotFound","message":"Resource does not exist."}}' }
                return J $hit[0]
            }
            if ($p -match '^/v1\.0/users\?\$filter=(.+?)&\$select') {
                $f = $Matches[1]; $hits = @()
                if ($f -match "^mail eq '(.+)'$") { $v = $Matches[1].ToLowerInvariant(); $hits = @(Find-Person { [string]$_.mail -eq $v }) }
                elseif ($f -match "^proxyAddresses/any\(x:x eq 'smtp:(.+)'\)$") { $v = $Matches[1].ToLowerInvariant(); $hits = @(Find-Person { @($_.proxyAddresses | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains "smtp:$v" }) }
                elseif ($f -match "^userPrincipalName eq '(.+)'$") { $v = $Matches[1].ToLowerInvariant(); $hits = @(Find-Person { $_.userPrincipalName -eq $v }) }
                elseif ($f -match "^mailNickname eq '(.+)'$") { $v = $Matches[1].ToLowerInvariant(); $hits = @(Find-Person { ($_.userPrincipalName -split '@')[0] -eq $v }) }
                else { throw "unmocked user filter $f" }
                return J @{ value = @($hits | ForEach-Object { J $_ }) }
            }
            if ($p -match '^/v1\.0/groups\?\$filter=(.+?)&\$select') {
                $f = $Matches[1]
                $hits = @($Sc.groupsTaken | Where-Object { $f -match [regex]::Escape($_.mail) -or $f -match "mailNickname eq '$([regex]::Escape(($_.mail -split '@')[0]))'" })
                return J @{ value = @($hits | ForEach-Object { J $_ }) }
            }
        }
        throw "unmocked Graph $m $p"
    }
    # Notes are kept in $Sc.notes and read back, so Add-PsaNote -Marker can find an earlier copy.
    if ($u -like 'https://cw.example/*') {
        if ($m -eq 'GET' -and $u -like '*/service/tickets/12345/notes*') { $i = 0; return , @($Sc.notes | ForEach-Object { $i++; J @{ id = $i; text = $_.text; internalAnalysisFlag = $_.internal; detailDescriptionFlag = (-not $_.internal); member = (J @{ identifier = 'api' }) } }) }
        if ($m -eq 'POST' -and $u -like '*/service/tickets/12345/notes') { $b = $c.Body | ConvertFrom-Json; $null = $Sc.notes.Add(@{ text = [string]$b.text; internal = [bool]$b.internalAnalysisFlag }); return J @{ id = $Sc.notes.Count } }
    }
    if ($u -like 'https://at.example/*') {
        if ($m -eq 'GET' -and $u -like '*/TicketNotes/query?*') { $i = 0; return J @{ items = @($Sc.notes | ForEach-Object { $i++; J @{ id = $i; description = $_.text; publish = $(if ($_.internal) { 2 } else { 1 }); creatorResourceID = 1 } }); pageDetails = (J @{ nextPageUrl = $null }) } }
        if ($m -eq 'GET' -and $u -like '*/TicketNotes/entityInformation/fields') { return J @{ fields = @((J @{ name = 'publish'; picklistValues = @((J @{ value = '1'; label = 'All Autotask Users'; isActive = $true }), (J @{ value = '2'; label = 'Internal Only'; isActive = $true })) }), (J @{ name = 'noteType'; picklistValues = @((J @{ value = '13'; label = 'System Workflow Note'; isActive = $true }), (J @{ value = '1'; label = 'Task Detail'; isActive = $true })) })) } }
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
function ConvertTo-FakeArgs { param($Bound) $h = @{}; foreach ($k in $Bound.Keys) { $h[$k] = $Bound[$k] }; return $h }
function Get-Recipient { [CmdletBinding()] param($Identity) Invoke-FakeExo 'Get-Recipient' @{ Identity = $Identity } }
function New-Mailbox { [CmdletBinding(SupportsShouldProcess)] param([switch]$Shared, $Name, $DisplayName, $Alias, $PrimarySmtpAddress) Invoke-FakeExo 'New-Mailbox' (ConvertTo-FakeArgs $PSBoundParameters) }
function Add-MailboxPermission { [CmdletBinding(SupportsShouldProcess)] param($Identity, $User, $AccessRights, $InheritanceType, $AutoMapping) Invoke-FakeExo 'Add-MailboxPermission' (ConvertTo-FakeArgs $PSBoundParameters) }
function Add-RecipientPermission { [CmdletBinding(SupportsShouldProcess)] param($Identity, $Trustee, $AccessRights) Invoke-FakeExo 'Add-RecipientPermission' (ConvertTo-FakeArgs $PSBoundParameters) }
function New-DistributionGroup { [CmdletBinding(SupportsShouldProcess)] param($Name, $DisplayName, $Alias, $PrimarySmtpAddress, $Type, $ManagedBy, $RequireSenderAuthenticationEnabled) Invoke-FakeExo 'New-DistributionGroup' (ConvertTo-FakeArgs $PSBoundParameters) }
function Add-DistributionGroupMember { [CmdletBinding(SupportsShouldProcess)] param($Identity, $Member, [switch]$BypassSecurityGroupManagerCheck) Invoke-FakeExo 'Add-DistributionGroupMember' (ConvertTo-FakeArgs $PSBoundParameters) }

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
function Invoke-Request {
    param($Body)
    $r = Invoke-Step $ReadScript $Body
    $json = $null; if ($null -ne $r.out) { $json = ($r.out | ConvertTo-Json -Depth 20 | ConvertFrom-Json) }
    $a = Invoke-Step $ApplyScript ([pscustomobject]@{ prep = $json })
    if ($ShowNotes -and $null -ne $a.out) { Write-Host "----- $($a.out.status): $($a.out.message)`n$($a.out.internal_note)`n-- public: $($a.out.public_note)`n-----" -ForegroundColor DarkGray }
    return @{ read = $r.out; readErr = $r.err; out = $a.out; err = $a.err }
}
function New-Body {
    param([hashtable]$Over = @{})
    $b = [ordered]@{ kind = 'shared_mailbox'; display_name = 'Contoso Sales Team'; members = 'alex.kim@contoso.com, sam.doe@contoso.com'; send_as = 'sam.doe@contoso.com'; requester_email = 'alex.kim@contoso.com'; confirm = 'false'; psa = ''; ticket_id = '12345' }
    foreach ($k in $Over.Keys) { $b[$k] = $Over[$k] }
    return [pscustomobject]$b
}
function Get-PsaNotes { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and ($_.Uri -like 'https://cw.example/*' -or $_.Uri -like 'https://at.example/*Notes' -or $_.Uri -like 'https://halo.example/api/Actions') }) }
$Addr = 'contoso-sales-team@contoso.com'

# =================== 1. shared mailbox, same department: created directly (ConnectWise, REST) ===================
New-Scenario 'connectwise' 'rest'
$r = Invoke-Request (New-Body)
$o = $r.out
Check 'shared: read ok, alias derived from the display name' ($r.read.status -eq 'ok' -and $r.read.alias -eq 'contoso-sales-team' -and $r.read.address -eq $Addr -and -not $r.readErr) "$($r.read.status) $($r.read.message) $($r.readErr)"
Check 'shared: same department (case-insensitive) needs no confirmation' ($r.read.needs_confirmation -eq $false) (@($r.read.confirmation_reasons) -join ' | ')
Check 'shared: success, no error' ($o.status -eq 'success' -and -not $r.err) "$($o.status) $($o.message) $($r.err)"
Check 'shared: Exchange writes in order' ((Get-ExoWrites) -join ',' -eq 'New-Mailbox,Add-MailboxPermission,Add-MailboxPermission,Add-RecipientPermission') ((Get-ExoWrites) -join ',')
$nm = Get-ExoCall 'New-Mailbox'
Check 'shared: New-Mailbox -Shared with name, alias and address' ((Get-PVal $nm 'Shared') -eq $true -and (Get-PVal $nm 'Name') -eq 'Contoso Sales Team' -and (Get-PVal $nm 'Alias') -eq 'contoso-sales-team' -and (Get-PVal $nm 'PrimarySmtpAddress') -eq $Addr) ($nm | ConvertTo-Json -Compress)
$fa = Get-ExoCall 'Add-MailboxPermission' 0
Check 'shared: requester gets FullAccess first (owner)' ((Get-PVal $fa 'User') -eq 'alex.kim@contoso.com' -and @(Get-PVal $fa 'AccessRights') -contains 'FullAccess' -and (Get-PVal $fa 'Identity') -eq $Addr) ($fa | ConvertTo-Json -Compress)
Check 'shared: requester listed as a member is not added twice' (@($Sc.exoLog | Where-Object { $_ -eq 'Add-MailboxPermission' }).Count -eq 2 -and (Get-PVal (Get-ExoCall 'Add-MailboxPermission' 1) 'User') -eq 'sam.doe@contoso.com') ''
$sa = Get-ExoCall 'Add-RecipientPermission'
Check 'shared: send-as for sam' ((Get-PVal $sa 'Trustee') -eq 'sam.doe@contoso.com' -and @(Get-PVal $sa 'AccessRights') -contains 'SendAs') ($sa | ConvertTo-Json -Compress)
$notes = @(Get-PsaNotes)
Check 'shared: ConnectWise internal then public note' ($notes.Count -eq 2 -and (Read-Body $notes[0]).internalAnalysisFlag -eq $true -and (Read-Body $notes[1]).internalAnalysisFlag -eq $false -and (Read-Body $notes[1]).detailDescriptionFlag -eq $true) (Show-Calls)
Check 'shared: public note is the new address only' ($o.public_note -eq "The new shared mailbox Contoso Sales Team is ready at $Addr." -and (Read-Body $notes[1]).text -eq "$($o.public_note)`n[shared_mailbox ready $Addr]") $o.public_note
Check 'shared: internal note names the owner and what ran' ($o.internal_note -match 'Owner: Alex Kim' -and $o.internal_note -match 'send as' -and $o.internal_note -notmatch 'Warnings') $o.internal_note
Check 'shared: Exchange used REST with the extension secrets' ($r.read.exchange_mode -eq 'rest' -and @(Get-Calls 'POST' "$ExoBase/$TenantGuid/InvokeCommand").Count -ge 6) ''

# =================== 2. preview ===================
New-Scenario 'connectwise' 'rest'
$r = Invoke-Request (New-Body @{ preview = 'true' })
Check 'preview: pending_confirmation, nothing created' ($r.out.status -eq 'pending_confirmation' -and @(Get-ExoWrites).Count -eq 0 -and -not $r.err) "$($r.out.status) $((Get-ExoWrites) -join ',')"
Check 'preview: one internal note with the plan and commands, no public note' (@(Get-PsaNotes).Count -eq 1 -and $r.out.public_note -eq '' -and $r.out.internal_note -match 'Preview only' -and $r.out.internal_note -match "New-Mailbox -Shared -Name 'Contoso Sales Team'") $r.out.internal_note
Check 'preview: planned list' (@($r.out.planned).Count -eq 4) (@($r.out.planned) -join ' | ')

# =================== 3. someone outside the department: held (Autotask) ===================
New-Scenario 'autotask' 'rest'
$r = Invoke-Request (New-Body @{ members = 'sam.doe@contoso.com; pat.lee@contoso.com' })
Check 'cross-department: pending_confirmation, nothing created' ($r.out.status -eq 'pending_confirmation' -and @(Get-ExoWrites).Count -eq 0) "$($r.out.status) $((Get-ExoWrites) -join ',')"
Check 'cross-department: reason names Pat Lee and Finance' ((@($r.out.confirmation_reasons) -join ' ') -match 'Pat Lee \(Finance\)' -and $r.out.message -match 'confirm set to true') (@($r.out.confirmation_reasons) -join ' | ')
$an = @(Get-PsaNotes)
Check 'cross-department: Autotask internal note only' ($an.Count -eq 1 -and (Read-Body $an[0]).publish -eq 2 -and (Read-Body $an[0]).description -match 'Why it needs confirmation') (Show-Calls)
New-Scenario 'autotask' 'rest'
$r = Invoke-Request (New-Body @{ members = 'sam.doe@contoso.com; pat.lee@contoso.com'; confirm = 'true' })
Check 'cross-department + confirm: created' ($r.out.status -eq 'success' -and (Get-ExoWrites) -join ',' -eq 'New-Mailbox,Add-MailboxPermission,Add-MailboxPermission,Add-MailboxPermission,Add-RecipientPermission') "$($r.out.status) $($r.out.message) $((Get-ExoWrites) -join ',')"
$an = @(Get-PsaNotes)
Check 'cross-department + confirm: Autotask internal and public notes' ($an.Count -eq 2 -and (Read-Body $an[1]).publish -eq 1 -and $r.out.internal_note -match 'after a technician confirmed') $r.out.internal_note
New-Scenario 'connectwise' 'rest'
$r = Invoke-Request (New-Body @{ members = 'sam.doe@contoso.com'; send_as = 'pat.lee@contoso.com' })
Check 'send-as outside the department also needs confirmation' ($r.out.status -eq 'pending_confirmation' -and @(Get-ExoWrites).Count -eq 0) "$($r.out.status)"
New-Scenario 'connectwise' 'rest'
$r = Invoke-Request (New-Body @{ members = 'sam.doe@contoso.com'; preview = 'true'; confirm = 'true' })
Check 'preview wins over confirm' ($r.out.status -eq 'pending_confirmation' -and @(Get-ExoWrites).Count -eq 0) "$($r.out.status)"

# =================== 4. requester with no department; more than 25 members ===================
New-Scenario 'connectwise' 'rest'
$Sc.people[0].department = $null
$r = Invoke-Request (New-Body)
Check 'requester without a department: pending_confirmation' ($r.out.status -eq 'pending_confirmation' -and (@($r.out.confirmation_reasons) -join ' ') -match 'has no department' -and @(Get-ExoWrites).Count -eq 0) (@($r.out.confirmation_reasons) -join ' | ')
New-Scenario 'connectwise' 'rest'
Add-SalesPeople 26
$r = Invoke-Request (New-Body @{ kind = 'distribution_list'; send_as = ''; members = (@(1..26 | ForEach-Object { "seller$_@contoso.com" }) -join ',') })
Check 'more than 25 members: pending_confirmation' ($r.out.status -eq 'pending_confirmation' -and (@($r.out.confirmation_reasons) -join ' ') -match '26 members, more than 25' -and @(Get-ExoWrites).Count -eq 0) (@($r.out.confirmation_reasons) -join ' | ')
New-Scenario 'connectwise' 'rest'
Add-SalesPeople 25
$r = Invoke-Request (New-Body @{ kind = 'distribution_list'; send_as = ''; members = (@(1..25 | ForEach-Object { "seller$_@contoso.com" }) -join ',') })
Check 'exactly 25 members in the department: created' ($r.out.status -eq 'success' -and @($Sc.exoLog | Where-Object { $_ -eq 'Add-DistributionGroupMember' }).Count -eq 25) "$($r.out.status) $($r.out.message)"

# =================== 5. distribution list (HaloPSA, Exchange PowerShell module) ===================
New-Scenario 'halopsa' 'module'
$r = Invoke-Request (New-Body @{ kind = 'DL'; display_name = 'Accounts Payable & Billing (UK)'; members = 'sam.doe@contoso.com, alex.kim@contoso.com' })
$o = $r.out
Check 'DL: alias cleaned from the display name' ($r.read.alias -eq 'accounts-payable-and-billing-uk' -and $r.read.kind -eq 'distribution_list') "$($r.read.alias) $($r.read.message)"
Check 'DL: created through the module' ($o.status -eq 'success' -and $r.read.exchange_mode -eq 'module' -and (Get-ExoWrites) -join ',' -eq 'New-DistributionGroup,Add-DistributionGroupMember,Add-DistributionGroupMember') "$($o.status) $($o.message) $((Get-ExoWrites) -join ',')"
$dg = Get-ExoCall 'New-DistributionGroup'
Check 'DL: requester is the owner, internal senders only' (@(Get-PVal $dg 'ManagedBy') -contains 'alex.kim@contoso.com' -and (Get-PVal $dg 'RequireSenderAuthenticationEnabled') -eq $true -and (Get-PVal $dg 'Type') -eq 'Distribution') ($dg | ConvertTo-Json -Compress)
Check 'DL: members added with the manager check bypassed' ((Get-PVal (Get-ExoCall 'Add-DistributionGroupMember' 0) 'BypassSecurityGroupManagerCheck') -eq $true) ''
Check 'DL: send_as ignored with a warning' (-not ($Sc.exoLog -contains 'Add-RecipientPermission') -and (@($o.warnings) -match 'send_as only applies').Count -eq 1) (@($o.warnings) -join ' | ')
$hn = @(Get-PsaNotes)
Check 'DL: HaloPSA private then public note' ($hn.Count -eq 2 -and @(Read-Body $hn[0])[0].hiddenfromuser -eq $true -and @(Read-Body $hn[1])[0].hiddenfromuser -eq $false -and $o.public_note -eq 'The new distribution list Accounts Payable & Billing (UK) is ready at accounts-payable-and-billing-uk@contoso.com.') $o.public_note
New-Scenario 'connectwise' 'rest'
$r = Invoke-Request (New-Body @{ kind = 'distribution_list'; send_as = ''; external_allowed = 'true' })
Check 'DL external_allowed: accepts outside senders' ($r.out.status -eq 'success' -and (Get-PVal (Get-ExoCall 'New-DistributionGroup') 'RequireSenderAuthenticationEnabled') -eq $false) "$($r.out.status)"

# =================== 6. address already used ===================
New-Scenario 'connectwise' 'rest'
$null = $Sc.people.Add(@{ id = 'u-room'; userPrincipalName = 'room1@contoso.com'; displayName = 'Room One'; mail = 'room1@contoso.com'; department = ''; accountEnabled = $true; userType = 'Member'; proxyAddresses = @('SMTP:room1@contoso.com', 'smtp:sales@contoso.com') })
$r = Invoke-Request (New-Body @{ alias = 'Sales' })
Check 'address on a user''s proxyAddresses: rejected, nothing created' ($r.out.status -eq 'rejected' -and $r.out.message -match 'already used by Room One' -and @(Get-ExoWrites).Count -eq 0 -and $r.err) "$($r.out.status) $($r.out.message)"
New-Scenario 'connectwise' 'rest' @{ groupsTaken = @(@{ id = 'g-1'; displayName = 'Contoso Sales (Teams)'; mail = 'contoso-sales-team@contoso.com' }) }
$r = Invoke-Request (New-Body)
Check 'address on a group: rejected' ($r.out.status -eq 'rejected' -and $r.out.message -match 'the group Contoso Sales \(Teams\)') "$($r.out.status) $($r.out.message)"
New-Scenario 'connectwise' 'rest' @{ recipients = @{ 'contoso-sales-team' = @{ DisplayName = 'Sales contact'; RecipientTypeDetails = 'MailContact' } } }
$r = Invoke-Request (New-Body)
Check 'alias used in Exchange only: rejected, no by-hand commands' ($r.out.status -eq 'rejected' -and $r.out.internal_note -notmatch 'by hand' -and @($r.out.manual_commands).Count -eq 0 -and $r.out.message -match 'alias contoso-sales-team is already used in Exchange Online by Sales contact \(MailContact\)' -and @(Get-ExoWrites).Count -eq 0) "$($r.out.status) $($r.out.message)"

# =================== 7. members that can't be added ===================
New-Scenario 'connectwise' 'rest'
$r = Invoke-Request (New-Body @{ members = 'sam.doe@contoso.com, nobody@contoso.com, jo.room@contoso.com' })
Check 'unknown and mailbox-less members: incomplete, nothing created' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'nobody@contoso.com \(not found' -and $r.out.message -match 'jo.room@contoso.com \(has no mailbox\)' -and @(Get-ExoWrites).Count -eq 0) "$($r.out.status) $($r.out.message)"
New-Scenario 'connectwise' 'rest'
$r = Invoke-Request (New-Body @{ members = 'sam@contoso.com' })
Check 'member found by proxy address' ($r.out.status -eq 'success' -and (Get-PVal (Get-ExoCall 'Add-MailboxPermission' 1) 'User') -eq 'sam.doe@contoso.com') "$($r.out.status) $($r.out.message)"
New-Scenario 'connectwise' 'rest'
$r = Invoke-Request (New-Body @{ requester_email = 'stranger@fabrikam.com' })
Check 'requester not in the tenant: incomplete' ($r.out.status -eq 'incomplete' -and $r.out.message -match "isn't a user in this Microsoft 365 tenant") "$($r.out.status) $($r.out.message)"
New-Scenario 'connectwise' 'rest'
$r = Invoke-Request (New-Body @{ members = 'sam.doe' })
Check 'member that is not an address: incomplete' ($r.out.status -eq 'incomplete' -and @($Mock.Calls | Where-Object { $_.Uri -like "$GraphBase/*" }).Count -eq 0) "$($r.out.status) $($r.out.message)"

# =================== 8. missing permissions (403) ===================
New-Scenario 'connectwise' 'rest' @{ forbid = @('^GET /v1\.0/users') }
$r = Invoke-Request (New-Body)
Check '403 on users: error naming User.Read.All' ($r.out.status -eq 'error' -and $r.out.message -match 'User\.Read\.All' -and $r.out.message -match 'Nothing was created' -and $r.err) "$($r.out.status) $($r.out.message)"
New-Scenario 'connectwise' 'rest' @{ forbid = @('^GET /v1\.0/domains') }
$r = Invoke-Request (New-Body)
Check '403 on domains: error naming Domain.Read.All' ($r.out.status -eq 'error' -and $r.out.message -match 'Domain\.Read\.All') "$($r.out.status) $($r.out.message)"
New-Scenario 'connectwise' 'rest' @{ forbid = @('^GET /v1\.0/groups') }
$r = Invoke-Request (New-Body)
Check '403 on groups: warning, checked in Exchange, still created' ($r.out.status -eq 'success' -and (@($r.out.warnings) -match 'Group\.Read\.All').Count -eq 1 -and $r.out.internal_note -match 'Group\.Read\.All') "$($r.out.status) $(@($r.out.warnings) -join ' | ')"

# =================== 9. Exchange Online unreachable or failing ===================
New-Scenario 'connectwise' 'none'
$r = Invoke-Request (New-Body)
Check 'no Exchange secrets: error, nothing created' ($r.out.status -eq 'error' -and $r.out.message -match "Exchange Online couldn't be reached" -and $r.out.message -match 'MicrosoftExchange-TenantId' -and @(Get-ExoWrites).Count -eq 0 -and $r.err) "$($r.out.status) $($r.out.message)"
Check 'no Exchange secrets: internal note has the exact commands' ($r.out.internal_note -match "New-Mailbox -Shared -Name 'Contoso Sales Team' -DisplayName 'Contoso Sales Team' -Alias 'contoso-sales-team' -PrimarySmtpAddress '$Addr'" -and $r.out.internal_note -match "Add-RecipientPermission -Identity '$Addr' -Trustee 'sam.doe@contoso.com' -AccessRights SendAs" -and @($r.out.manual_commands).Count -eq 4 -and @(Get-PsaNotes).Count -eq 1) $r.out.internal_note
New-Scenario 'connectwise' 'both' @{ exoTokenFail = $true }
$r = Invoke-Request (New-Body)
Check 'REST sign-in fails: falls back to the module' ($r.out.status -eq 'success' -and $r.read.exchange_mode -eq 'module' -and $Sc.connected -eq 'exo-app|contoso.onmicrosoft.com|ABCDEF0123456789') "$($r.out.status) $($r.read.exchange_mode) $($r.out.message)"
New-Scenario 'connectwise' 'rest' @{ exoTokenFail = $true }
$r = Invoke-Request (New-Body)
Check 'REST sign-in fails, no module: error with the reason' ($r.out.status -eq 'error' -and $r.out.message -match 'Invalid client secret' -and @(Get-ExoWrites).Count -eq 0) "$($r.out.status) $($r.out.message)"
New-Scenario 'connectwise' 'rest' @{ exoTokenFailFrom = 2 }
$r = Invoke-Request (New-Body)
Check 'Exchange lost between the steps: error, nothing created, commands in the note' ($r.read.status -eq 'ok' -and $r.out.status -eq 'error' -and @(Get-ExoWrites).Count -eq 0 -and $r.out.internal_note -match 'New-Mailbox -Shared' -and $r.out.message -notmatch '\.\.') "$($r.out.status) $($r.out.message)"
New-Scenario 'connectwise' 'rest' @{ failOn = 'Add-RecipientPermission' }
$r = Invoke-Request (New-Body)
Check 'send-as fails: error, says what exists and what is left' ($r.out.status -eq 'error' -and $r.out.internal_note -match 'was created, but the run stopped part way' -and @($r.out.manual_commands).Count -eq 1 -and $r.out.manual_commands[0] -like 'Add-RecipientPermission*' -and $r.out.public_note -eq '') $r.out.internal_note
New-Scenario 'connectwise' 'rest' @{ failOn = 'New-Mailbox' }
$r = Invoke-Request (New-Body)
Check 'create fails: error, nothing created, all commands listed' ($r.out.status -eq 'error' -and $r.out.internal_note -match 'Nothing was created' -and @($r.out.manual_commands).Count -eq 4 -and @($Sc.exoLog | Where-Object { $_ -like 'Add-*' }).Count -eq 0) $r.out.internal_note
New-Scenario 'connectwise' 'rest' @{ notFoundOnce = 'Add-MailboxPermission' }
$r = Invoke-Request (New-Body)
Check 'new mailbox not visible yet: permission retried' ($r.out.status -eq 'success' -and @($Sc.exoLog | Where-Object { $_ -eq 'Add-MailboxPermission' }).Count -eq 3 -and $Mock.Sleeps -contains 15) "$($r.out.status) $($r.out.message)"

# =================== 10. empty result, inputs and request shapes ===================
New-Scenario 'connectwise' 'rest'
$r = Invoke-Request (New-Body @{ members = ''; send_as = '' })
Check 'no members: requester only, with a warning' ($r.out.status -eq 'success' -and (Get-ExoWrites) -join ',' -eq 'New-Mailbox,Add-MailboxPermission' -and (@($r.out.warnings) -match 'only the requester').Count -eq 1) "$($r.out.status) $((Get-ExoWrites) -join ',')"
New-Scenario 'connectwise' 'rest'
$r = Invoke-Request (New-Body @{ alias = 'Sales Team!'; domain = 'contoso.onmicrosoft.com' })
Check 'given alias cleaned, given domain used' ($r.out.status -eq 'success' -and $r.out.address -eq 'sales-team@contoso.onmicrosoft.com' -and (@($r.out.warnings) -match "cleaned up to 'sales-team'").Count -eq 1) "$($r.out.address) $(@($r.out.warnings) -join ' | ')"
New-Scenario 'connectwise' 'rest'
$r = Invoke-Request (New-Body @{ domain = 'fabrikam.com' })
Check 'unverified domain: incomplete' ($r.out.status -eq 'incomplete' -and $r.out.message -match "fabrikam.com isn't a verified domain") "$($r.out.status) $($r.out.message)"
New-Scenario 'connectwise' 'rest'
$r = Invoke-Request (New-Body @{ company_tenant_id = '11111111-2222-4333-8444-555555555555' })
Check 'tenant mismatch: rejected' ($r.out.status -eq 'rejected' -and $r.err -match 'tenant') "$($r.out.status) $($r.err)"
New-Scenario 'connectwise' 'rest'
$r = Invoke-Request (New-Body @{ kind = 'room' })
Check 'unknown kind: incomplete' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'shared_mailbox or distribution_list') "$($r.out.status)"
New-Scenario 'connectwise' 'rest'
$r = Invoke-Request (New-Body @{ requester_email = '@UserEmail' })
Check 'literal @UserEmail: incomplete, no owner' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'requester_email') "$($r.out.status)"
New-Scenario 'connectwise' 'rest'
$r = Invoke-Request $null
Check 'no input: incomplete' ($r.out.status -eq 'incomplete') "$($r.out.status)"
New-Scenario 'connectwise' 'rest'
$form = [pscustomobject]@{ Ticket = [pscustomobject]@{ TicketId = 12345; Questions = @([pscustomobject]@{ Id = 'kind'; Value = 'Shared mailbox' }, [pscustomobject]@{ Id = 'display_name'; Value = 'Contoso Sales Team' }, [pscustomobject]@{ Id = 'members'; Value = @('sam.doe@contoso.com') }, [pscustomobject]@{ Id = 'send_as'; Value = '@send_as' }, [pscustomobject]@{ Id = 'requester_email'; Value = 'alex.kim@contoso.com' }) }; Company = [pscustomobject]@{ CompanyTenantId = $TenantGuid } }
$r = Invoke-Request $form
Check 'CloudRadial form shape: parsed, literal token ignored, created' ($r.out.status -eq 'success' -and $r.read.ticket_id -eq '12345' -and -not ($Sc.exoLog -contains 'Add-RecipientPermission')) "$($r.out.status) $($r.read.message)"
New-Scenario '' 'rest'
$r = Invoke-Request (New-Body)
Check 'no PSA set up: still created, warning' ($r.out.status -eq 'success' -and (@($r.out.warnings) -match 'No PSA is set up').Count -eq 1) "$($r.out.status) $(@($r.out.warnings) -join ' | ')"

# =================== rerun writes nothing twice (ServiceAI Action Runs Retry) ===================
New-Scenario 'connectwise' 'rest'
$null = Invoke-Request (New-Body @{ preview = 'true' })
$r = Invoke-Request (New-Body @{ preview = 'true' })
Check 'rerun preview: no second internal note' (@(Get-PsaNotes).Count -eq 1 -and $Sc.notes[0].text -match '\[shared_mailbox pending_confirmation contoso-sales-team@contoso\.com [0-9a-f]{8}\]' -and (@($r.out.actions) -match 'already on ticket 12345').Count -eq 1) "$(@(Get-PsaNotes).Count) / $(@($r.out.actions) -join ' | ')"
$null = Invoke-Request (New-Body)
$created = @(Get-ExoWrites).Count
$r = Invoke-Request (New-Body)
Check 'rerun after success: success, nothing created or noted again' ($r.out.status -eq 'success' -and -not $r.err -and @(Get-PsaNotes).Count -eq 3 -and @(Get-ExoWrites).Count -eq $created -and $r.out.message -match 'already created by an earlier run') "$($r.out.status) $($r.out.message) $($r.err) / $(@(Get-PsaNotes).Count)"
New-Scenario 'connectwise' 'rest' @{ recipients = @{ $Addr = @{ DisplayName = 'Someone Else'; RecipientTypeDetails = 'UserMailbox' } } }
$r = Invoke-Request (New-Body)
Check 'address taken with no earlier success note: still rejected' ($r.out.status -eq 'rejected' -and $r.err -match 'already used') "$($r.out.status) $($r.err)"
New-Scenario 'autotask' 'rest'
$null = Invoke-Request (New-Body @{ kind = 'distribution_list'; send_as = ''; confirm = 'true' })
$n1 = @(Get-PsaNotes).Count
$r = Invoke-Request (New-Body @{ kind = 'distribution_list'; send_as = ''; confirm = 'true' })
Check 'rerun on Autotask: nothing written twice' ($n1 -ge 1 -and @(Get-PsaNotes).Count -eq $n1 -and $r.out.status -eq 'success') "$n1 / $(@(Get-PsaNotes).Count) $($r.out.status) $($r.out.message)"

Complete-Test
