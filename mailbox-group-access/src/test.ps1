# Strict-mode harness for mailbox-group-access.yml: fake Key Vault, Microsoft Graph, Exchange Online (REST),
# PSAs (ConnectWise, Syncro, Zendesk) and node I/O. Runs the three step scripts exactly as they ship (extracted
# from the built .yml) through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest.
# Placeholder data only (Contoso, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a step variable of the same
# name would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File mailbox-group-access/src/test.ps1 [-ShowNotes]   (needs node and js-yaml, or JS_YAML_PATH)
param([switch]$ShowNotes)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')
$ErrorActionPreference = 'Stop'

# ---------- the built workflow ----------
$TNodeExe = (Get-Command node -ErrorAction Stop).Source
& $TNodeExe (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$TJs = "const p=require('path');let y;try{y=require('js-yaml')}catch{try{y=require(p.join(process.argv[2],'node_modules','js-yaml'))}catch{y=require(process.env.JS_YAML_PATH)}};const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={webhook:String(d.definition.activities[0].properties.webhookEnabled),params:{},conns:d.definition.connections.map(c=>c.source+'>'+c.target).join(',')};for(const a of d.definition.activities){if(a.properties&&a.properties.script){o[a.id]=a.properties.script;o.params[a.id]=(a.properties.parameters||[]).map(x=>x.name+'='+x.expression).join(';')}if(a.properties&&a.properties.testInput)o.testInput=a.properties.testInput}console.log(JSON.stringify(o))"
$TSteps = (& $TNodeExe -e $TJs (Join-Path $PSScriptRoot '..\mailbox-group-access.yml') $Shared) | ConvertFrom-Json -AsHashtable
Check 'workflow: three PowerShell steps in order, webhook ships off' ($TSteps.Contains('node-read') -and $TSteps.Contains('node-grant') -and $TSteps.Contains('node-note') -and $TSteps.webhook -eq 'false' -and $TSteps.conns -eq 'start>node-read,node-read>node-grant,node-grant>node-note,node-note>end') $TSteps.conns
Check 'workflow: first step unbound, later steps bound with nodes.<id>.output' ($TSteps.params['node-read'] -eq '' -and $TSteps.params['node-grant'] -eq 'prep={{ nodes.node-read.output }}' -and $TSteps.params['node-note'] -eq 'result={{ nodes.node-grant.output }}') ($TSteps.params | ConvertTo-Json -Compress)
Check 'workflow: test input is JSON with confirm false' ((($TSteps.testInput | ConvertFrom-Json).confirm) -eq 'false')
Check 'workflow: no em or en dashes in any script' (-not (@('node-read', 'node-grant', 'node-note') | Where-Object { $TSteps[$_] -match "[$([char]0x2013)$([char]0x2014)]" }))

# ---------- placeholder data ----------
$TGraph = 'https://graph.microsoft.com'
$TExo = 'https://outlook.office365.com/adminapi/beta'
$TTenant = '0a1b2c3d-0000-4000-8000-00000000c0de'
$TBaseSecrets = @{ 'M365-TenantId' = $TTenant; 'M365-ClientId' = 'app-id'; 'M365-ClientSecret' = 'not-a-real-secret' }
$TExoSecrets = @{ 'MicrosoftExchange-TenantId' = $TTenant; 'MicrosoftExchange-ClientId' = 'exo-app'; 'MicrosoftExchange-ClientSecret' = 'not-a-real-secret' }
$TCwUrl = 'https://cw.example/v4_6_release/apis/3.0'
$TSyUrl = 'https://contoso.syncromsp.example/api/v1'
$TZdUrl = 'https://example.zendesk.com/api/v2'
$TPsaSecrets = @{
    connectwise = @{ 'CW-ApiUrl' = $TCwUrl; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    syncro      = @{ 'Syncro-ApiUrl' = $TSyUrl; 'Syncro-ApiKey' = 'key' }
    zendesk     = @{ 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example-msp.test'; 'Zendesk-ApiToken' = 'tok' }
}
function New-TUser { param($Id, $Upn, $Name, [string]$Type = 'Member', [bool]$On = $true, [string]$Mail = '') @{ id = $Id; userPrincipalName = $Upn; displayName = $Name; mail = $(if ($Mail) { $Mail } else { $Upn }); mailNickname = ($Upn -split '@')[0]; accountEnabled = $On; userType = $Type; proxyAddresses = @("SMTP:$(if ($Mail) { $Mail } else { $Upn })") } }
function New-TGroup { param($Id, $Name, $Mail, [string[]]$Types = @(), [bool]$MailOn = $false, [bool]$SecOn = $true, [string[]]$Prov = @(), [bool]$Synced = $false, [bool]$Role = $false, [string]$Rule = $null) @{ id = $Id; displayName = $Name; mail = $Mail; mailNickname = $(if ($Mail) { ($Mail -split '@')[0] } else { $Name -replace '\s', '' }); mailEnabled = $MailOn; securityEnabled = $SecOn; groupTypes = $Types; resourceProvisioningOptions = $Prov; onPremisesSyncEnabled = $(if ($Synced) { $true } else { $null }); isAssignableToRole = $Role; membershipRule = $Rule } }

$TW = @{}
function New-TWorld {
    param([string]$Psa = 'connectwise', [bool]$Exo = $true, [hashtable]$Secrets = @{})
    $TW.Clear()
    $TW.users = @(
        (New-TUser 'u-alex' 'alex.kim@contoso.com' 'Alex Kim'), (New-TUser 'u-pat' 'pat.lee@contoso.com' 'Pat Lee'), (New-TUser 'u-sam' 'sam.doe@contoso.com' 'Sam Doe'),
        (New-TUser 'u-riley' 'riley.ross@contoso.com' 'Riley Ross'), (New-TUser 'u-casey' 'casey.ng@contoso.com' 'Casey Ng'), (New-TUser 'u-morgan' 'morgan.it@contoso.com' 'Morgan Reyes'),
        (New-TUser 'u-jo' 'jo_fabrikam.com#EXT#@contoso.onmicrosoft.com' 'Jo Guest' 'Guest' $true 'jo@fabrikam.com'), (New-TUser 'u-dee' 'dee.off@contoso.com' 'Dee Off' 'Member' $false),
        (New-TUser 'u-sales' 'sales@contoso.com' 'Contoso Sales'), (New-TUser 'u-room' 'boardroom@contoso.com' 'Boardroom')
    )
    $TW.users[0].proxyAddresses = @('SMTP:alex.kim@contoso.com', 'smtp:alex@contoso.com')
    $TW.users[1].proxyAddresses = @('SMTP:pat.lee@contoso.com', 'smtp:pat@contoso.com')
    $TW.managers = @{ 'u-alex' = 'u-pat'; 'u-riley' = 'u-casey'; 'u-sales' = 'u-sam' }
    $TW.groups = @(
        (New-TGroup 'g-mkt' 'Marketing' 'marketing@contoso.com' @('Unified') $true $false @('Team')),
        (New-TGroup 'g-proj' 'Project Falcon' 'falcon@contoso.com' @('Unified') $true $false),
        (New-TGroup 'g-vpn' 'VPN Users' $null @() $false $true),
        (New-TGroup 'g-dl' 'All Staff' 'allstaff@contoso.com' @() $true $false),
        (New-TGroup 'g-fin' 'Finance Files' 'finance-files@contoso.com' @() $true $true),
        (New-TGroup 'g-adm' 'Helpdesk Admins' $null @() $false $true),
        (New-TGroup 'g-role' 'Tier 1 Support' $null @() $false $true @() $false $true),
        (New-TGroup 'g-dyn' 'All Contoso Users' $null @('DynamicMembership') $false $true @() $false $false '(user.companyName -eq "Contoso")'),
        (New-TGroup 'g-sync' 'Accounts Legacy' $null @() $false $true @() $true),
        (New-TGroup 'g-dup1' 'Projects' 'projects-a@contoso.com' @('Unified') $true $false), (New-TGroup 'g-dup2' 'Projects' 'projects-b@contoso.com' @('Unified') $true $false)
    )
    $TW.members = @{}; $TW.owners = @{}
    foreach ($g in $TW.groups) { $TW.members[$g.id] = New-Object System.Collections.ArrayList; $TW.owners[$g.id] = New-Object System.Collections.ArrayList; $null = $TW.owners[$g.id].Add('u-sam') }
    $TW.recipients = @{
        'sales@contoso.com'      = @{ DisplayName = 'Contoso Sales'; RecipientTypeDetails = 'SharedMailbox'; PrimarySmtpAddress = 'sales@contoso.com'; Alias = 'sales'; ExternalDirectoryObjectId = 'u-sales' }
        'riley.ross@contoso.com' = @{ DisplayName = 'Riley Ross'; RecipientTypeDetails = 'UserMailbox'; PrimarySmtpAddress = 'riley.ross@contoso.com'; Alias = 'riley.ross'; ExternalDirectoryObjectId = 'u-riley' }
        'boardroom@contoso.com'  = @{ DisplayName = 'Boardroom'; RecipientTypeDetails = 'RoomMailbox'; PrimarySmtpAddress = 'boardroom@contoso.com'; Alias = 'boardroom'; ExternalDirectoryObjectId = 'u-room' }
        'printers@contoso.com'   = @{ DisplayName = 'Printer contact'; RecipientTypeDetails = 'MailContact'; PrimarySmtpAddress = 'printers@contoso.com'; Alias = 'printers'; ExternalDirectoryObjectId = '' }
    }
    $TW.mbxPerms = New-Object System.Collections.ArrayList     # @{ id; user; rights }
    $TW.recipPerms = New-Object System.Collections.ArrayList   # @{ id; trustee; rights }
    $TW.onBehalf = @{}                                          # mailbox -> display names
    $TW.forbid = @(); $TW.failOn = ''; $TW.dropWrites = $false
    $TW.exoLog = New-Object System.Collections.ArrayList; $TW.exoParams = New-Object System.Collections.ArrayList
    $TW.graphWrites = New-Object System.Collections.ArrayList; $TW.mails = New-Object System.Collections.ArrayList
    $TW.notes = New-Object System.Collections.ArrayList; $TW.closed = New-Object System.Collections.ArrayList
    $TW.psa = $Psa
    $sec = $TBaseSecrets.Clone()
    if ($Psa) { foreach ($k in $TPsaSecrets[$Psa].Keys) { $sec[$k] = $TPsaSecrets[$Psa][$k] }; $sec['PSA-Type'] = $Psa }
    if ($Exo) { foreach ($k in $TExoSecrets.Keys) { $sec[$k] = $TExoSecrets[$k] } }
    foreach ($k in $Secrets.Keys) { $sec[$k] = $Secrets[$k] }
    Reset-Mock $sec $THandler
}
function J { param($o) [pscustomobject]$o }
function Get-TVal { param($P, [string]$k) if ($P -is [System.Collections.IDictionary]) { if ($P.Contains($k)) { return $P[$k] }; return $null }; $x = $P.PSObject.Properties[$k]; if ($x) { return $x.Value }; return $null }
function Find-TUser { param([string]$k) $k = $k.ToLowerInvariant(); $x = @($TW.users | Where-Object { $_.id -eq $k -or $_.userPrincipalName.ToLowerInvariant() -eq $k }); if ($x.Count) { return $x[0] }; return $null }
function Find-TGroupByMail { param([string]$m) $x = @($TW.groups | Where-Object { $_.mail -and $_.mail -eq $m.ToLowerInvariant() }); if ($x.Count) { return $x[0] }; return $null }

# One Exchange cmdlet (the REST endpoint's InvokeCommand).
function Invoke-TExo {
    param([string]$Name, $P)
    $null = $TW.exoLog.Add($Name); $null = $TW.exoParams.Add(@{ name = $Name; p = $P })
    $id = ([string](Get-TVal $P 'Identity')).ToLowerInvariant()
    if ($TW.failOn -eq $Name) { throw "$Name couldn't be completed (simulated)." }
    switch ($Name) {
        'Get-Recipient' {
            if ($TW.recipients.Contains($id)) { return @(J $TW.recipients[$id]) }
            $hit = @($TW.recipients.Values | Where-Object { $_.Alias -eq $id -or $_.DisplayName.ToLowerInvariant() -eq $id })
            if ($hit.Count) { return @(J $hit[0]) }
            throw "The operation couldn't be performed because object '$id' couldn't be found on 'EXAMPLE.PROD.OUTLOOK.COM'."
        }
        'Get-MailboxPermission' { $u = ([string](Get-TVal $P 'User')).ToLowerInvariant(); return @($TW.mbxPerms | Where-Object { $_.id -eq $id -and $_.user -eq $u } | ForEach-Object { J @{ Identity = $_.id; User = $_.user; AccessRights = @($_.rights); Deny = $false; IsInherited = $false } }) }
        'Get-RecipientPermission' { $u = ([string](Get-TVal $P 'Trustee')).ToLowerInvariant(); return @($TW.recipPerms | Where-Object { $_.id -eq $id -and $_.trustee -eq $u } | ForEach-Object { J @{ Identity = $_.id; Trustee = $_.trustee; AccessRights = @($_.rights); AccessControlType = 'Allow' } }) }
        'Get-Mailbox' { return @(J @{ Identity = $id; GrantSendOnBehalfTo = @($(if ($TW.onBehalf.Contains($id)) { $TW.onBehalf[$id] } else { @() })) }) }
        'Get-DistributionGroupMember' { $g = Find-TGroupByMail $id; return @($TW.members[$g.id] | ForEach-Object { $u = Find-TUser $_; J @{ Name = $u.mailNickname; PrimarySmtpAddress = $u.mail; ExternalDirectoryObjectId = $u.id } }) }
        'Get-DistributionGroup' { $g = Find-TGroupByMail $id; return @(J @{ Identity = $id; ManagedBy = @($TW.owners[$g.id] | ForEach-Object { (Find-TUser $_).displayName }) }) }
        'Add-MailboxPermission' { if (-not $TW.dropWrites) { $null = $TW.mbxPerms.Add(@{ id = $id; user = ([string](Get-TVal $P 'User')).ToLowerInvariant(); rights = 'FullAccess' }) }; return @(J @{ Identity = $id }) }
        'Add-RecipientPermission' { if (-not $TW.dropWrites) { $null = $TW.recipPerms.Add(@{ id = $id; trustee = ([string](Get-TVal $P 'Trustee')).ToLowerInvariant(); rights = 'SendAs' }) }; return @(J @{ Identity = $id }) }
        'Set-Mailbox' {
            $add = @(Get-TVal (Get-TVal $P 'GrantSendOnBehalfTo') 'Add')
            if (-not $TW.dropWrites) { if (-not $TW.onBehalf.Contains($id)) { $TW.onBehalf[$id] = @() }; foreach ($a in $add) { $TW.onBehalf[$id] += (Find-TUser $a).displayName } }
            return @()
        }
        'Add-DistributionGroupMember' { $g = Find-TGroupByMail $id; if (-not $TW.dropWrites) { $null = $TW.members[$g.id].Add((Find-TUser ([string](Get-TVal $P 'Member'))).id) }; return @() }
        'Set-DistributionGroup' { $g = Find-TGroupByMail $id; if (-not $TW.dropWrites) { foreach ($a in @(Get-TVal (Get-TVal $P 'ManagedBy') 'Add')) { $null = $TW.owners[$g.id].Add((Find-TUser $a).id) } }; return @() }
    }
    throw "unmocked Exchange cmdlet $Name"
}
function Get-TExoWrites { return @($TW.exoLog | Where-Object { $_ -notlike 'Get-*' }) }
function Get-TExoCall { param([string]$Name) $x = @($TW.exoParams | Where-Object { $_.name -eq $Name }); if ($x.Count) { return $x[0].p }; return $null }
function Get-TWrites { return @(@(Get-TExoWrites) + @($TW.graphWrites)) }
function Get-TPsaWrites { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and ($_.Uri -like "$TCwUrl/*" -or $_.Uri -like "$TSyUrl/*" -or $_.Uri -like "$TZdUrl/*") }) }

$THandler = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    $m = $c.Method
    if ($u -like 'https://login.microsoftonline.com/*') { return J @{ access_token = 'tok'; expires_in = 3599 } }
    if ($u -like "$TExo/*/InvokeCommand") {
        $b = $c.Body | ConvertFrom-Json
        try { $r = @(Invoke-TExo $b.CmdletInput.CmdletName $b.CmdletInput.Parameters) }
        catch { $msg = $_.Exception.Message -replace '"', "'"; if ($msg -match "couldn't be found") { New-HttpError 404 "{`"error`":{`"code`":`"NotFound`",`"message`":`"$msg`"}}" }; New-HttpError 400 "{`"error`":{`"code`":`"BadRequest`",`"message`":`"$msg`"}}" }
        return J @{ value = $r }
    }
    if ($u -like "$TGraph/*") {
        $p = $u.Substring($TGraph.Length)
        foreach ($f in @($TW.forbid)) { if ("$m $p" -match $f) { New-HttpError 403 '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}' } }
        if ($m -eq 'GET') {
            if ($p -match '^/v1\.0/users/([^/?]+)/manager\?') { $x = Find-TUser $Matches[1]; if ($null -eq $x -or -not $TW.managers.Contains($x.id)) { New-HttpError 404 '{"error":{"code":"Request_ResourceNotFound","message":"Resource ''manager'' does not exist."}}' }; return J (Find-TUser $TW.managers[$x.id]) }
            if ($p -match '^/v1\.0/users/([^/?]+)\?') { $x = Find-TUser $Matches[1]; if ($null -eq $x) { New-HttpError 404 '{"error":{"code":"Request_ResourceNotFound","message":"Resource does not exist."}}' }; return J $x }
            if ($p -match '^/v1\.0/users\?\$filter=(.+?)&\$select') {
                $f = $Matches[1]; $hits = @()
                if ($f -match "^mail eq '(.+)'$") { $v = $Matches[1].ToLowerInvariant(); $hits = @($TW.users | Where-Object { ([string]$_.mail).ToLowerInvariant() -eq $v }) }
                elseif ($f -match "^proxyAddresses/any\(x:x eq 'smtp:(.+)'\)$") { $v = "smtp:$($Matches[1].ToLowerInvariant())"; $hits = @($TW.users | Where-Object { @($_.proxyAddresses | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains $v }) }
                elseif ($f -match "^displayName eq '(.+)'$") { $v = $Matches[1].Replace("''", "'"); $hits = @($TW.users | Where-Object { $_.displayName -eq $v }) }
                else { throw "unmocked user filter $f" }
                return J @{ value = @($hits | ForEach-Object { J $_ }) }
            }
            if ($p -match '^/v1\.0/groups\?\$filter=(.+?)&\$select') {
                $f = $Matches[1]; $hits = @()
                if ($f -match "^mail eq '(.+)'$") { $v = $Matches[1].ToLowerInvariant(); $hits = @($TW.groups | Where-Object { $_.mail -eq $v }) }
                elseif ($f -match "^proxyAddresses/any\(x:x eq 'smtp:(.+)'\)$") { $v = $Matches[1].ToLowerInvariant(); $hits = @($TW.groups | Where-Object { $_.mail -eq $v }) }
                elseif ($f -match "^displayName eq '(.+)'$") { $v = $Matches[1].Replace("''", "'"); $hits = @($TW.groups | Where-Object { $_.displayName -eq $v }) }
                else { throw "unmocked group filter $f" }
                return J @{ value = @($hits | ForEach-Object { J $_ }) }
            }
            if ($p -match '^/v1\.0/groups/([^/]+)/members\?') { return J @{ value = @($TW.members[$Matches[1]] | ForEach-Object { J @{ id = $_ } }) } }
            if ($p -match '^/v1\.0/groups/([^/]+)/owners\?') { return J @{ value = @($TW.owners[$Matches[1]] | ForEach-Object { $x = (Find-TUser $_).Clone(); $x['@odata.type'] = '#microsoft.graph.user'; J $x }) } }
        }
        if ($m -eq 'POST') {
            if ($p -match '^/v1\.0/groups/([^/]+)/(members|owners)/\$ref$') {
                $gid = $Matches[1]; $which = $Matches[2]; $uid = ([string](Read-Body $c).'@odata.id' -split '/')[-1]
                $null = $TW.graphWrites.Add("$which $gid $uid")
                if ($TW[$which][$gid] -contains $uid) { New-HttpError 400 '{"error":{"code":"Request_BadRequest","message":"One or more added object references already exist for the following modified properties: ''members''."}}' }
                if (-not $TW.dropWrites) { $null = $TW[$which][$gid].Add($uid) }
                return $null
            }
            if ($p -match '^/v1\.0/users/([^/]+)/sendMail$') { $null = $TW.mails.Add(@{ from = $Matches[1]; body = (Read-Body $c) }); return $null }
        }
        throw "unmocked Graph $m $p"
    }
    # ---- PSAs: notes are kept in $TW.notes and read back, so Add-PsaNote -Marker can find an earlier copy ----
    if ($u -like "$TCwUrl/*") {
        if ($m -eq 'GET' -and $u -like '*/service/tickets/12345/notes*') { $i = 0; return , @($TW.notes | ForEach-Object { $i++; J @{ id = $i; text = $_.text; internalAnalysisFlag = $_.internal; detailDescriptionFlag = (-not $_.internal); member = (J @{ identifier = 'api' }) } }) }
        if ($m -eq 'POST' -and $u -like '*/service/tickets/12345/notes') { $b = Read-Body $c; $null = $TW.notes.Add(@{ text = [string]$b.text; internal = [bool]$b.internalAnalysisFlag }); return J @{ id = $TW.notes.Count } }
        if ($m -eq 'GET' -and $u -like '*/service/tickets/12345') { return J @{ id = 12345; board = (J @{ id = 1 }); status = (J @{ name = $(if ($TW.closed.Count) { 'Closed' } else { 'New' }) }) } }
        if ($m -eq 'GET' -and $u -like '*/service/boards/1/statuses*') { return , @((J @{ id = 1; name = 'New'; closedStatus = $false }), (J @{ id = 5; name = 'Closed'; closedStatus = $true })) }
        if ($m -eq 'PATCH' -and $u -like '*/service/tickets/12345') { $null = $TW.closed.Add(($c.Body | ConvertFrom-Json -NoEnumerate)[0].value.id); return J @{ id = 12345 } }
    }
    if ($u -like "$TSyUrl/*") {
        if ($m -eq 'GET' -and $u -like '*/tickets/12345') { $i = 0; return J @{ ticket = (J @{ id = 12345; status = 'New'; comments = @($TW.notes | ForEach-Object { $i++; J @{ id = $i; body = $_.text; hidden = $_.internal; subject = 'x'; user_id = 1 } }) }) } }
        if ($m -eq 'POST' -and $u -like '*/tickets/12345/comment') { $b = Read-Body $c; $null = $TW.notes.Add(@{ text = [string]$b.body; internal = [bool]$b.hidden }); return J @{ comment = (J @{ id = 1 }) } }
        if ($m -eq 'PUT' -and $u -like '*/tickets/12345') { $null = $TW.closed.Add([string](Read-Body $c).status); return J @{ ticket = (J @{ id = 12345 }) } }
    }
    if ($u -like "$TZdUrl/*") {
        if ($m -eq 'GET' -and $u -like '*/tickets/12345/comments*') { $i = 0; return J @{ comments = @($TW.notes | ForEach-Object { $i++; J @{ id = $i; body = $_.text; public = (-not $_.internal); author_id = 9 } }); next_page = $null } }
        if ($m -eq 'PUT' -and $u -like '*/tickets/12345') {
            $t = (Read-Body $c).ticket
            if ($t.PSObject.Properties['comment']) { $null = $TW.notes.Add(@{ text = [string]$t.comment.body; internal = (-not [bool]$t.comment.public) }) }
            if ($t.PSObject.Properties['status']) { $null = $TW.closed.Add([string]$t.status) }
            return J @{ ticket = (J @{ id = 12345 }) }
        }
    }
    throw "unmocked $m $u"
}

# ---------- runner ----------
$TNode = @{ In = $null; Out = $null }
function Get-NodeInput { param($Name) return $TNode.In }
function Set-NodeOutput { param($o) $TNode.Out = $o }
function Invoke-TStep {
    param([string]$TId, $TIn)
    $TNode.In = $TIn; $TNode.Out = $null; $terr = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $TSteps[$TId])) } catch { $terr = [string]$_.Exception.Message }
    $tj = $null; if ($null -ne $TNode.Out) { $tj = ($TNode.Out | ConvertTo-Json -Depth 20 | ConvertFrom-Json) }
    return @{ out = $tj; err = $terr }
}
# Runs the three steps; each output reaches the next step through a JSON round trip, as it does on the runner.
function Invoke-TRequest {
    param($TBody)
    $r1 = Invoke-TStep 'node-read' $TBody
    $r2 = Invoke-TStep 'node-grant' ([pscustomobject]@{ prep = $r1.out })
    $r3 = Invoke-TStep 'node-note' ([pscustomobject]@{ result = $r2.out })
    if ($ShowNotes -and $null -ne $r3.out) { Write-Host "----- $($r3.out.status): $($r3.out.message)`n$($r3.out.internal_note)`n-- public: $($r3.out.public_note)`n-----" -ForegroundColor DarkGray }
    return @{ read = $r1.out; readErr = $r1.err; grant = $r2.out; grantErr = $r2.err; out = $r3.out; err = $r3.err }
}
function New-TBody {
    param([hashtable]$Over = @{})
    $b = [ordered]@{ ticketId = '12345'; targetUser = 'alex.kim@contoso.com'; resource = 'sales@contoso.com'; accessType = ''; requester_email = 'alex.kim@contoso.com'; approvedBy = ''; confirm = 'true' }
    foreach ($k in $Over.Keys) { $b[$k] = $Over[$k] }
    return [pscustomobject]$b
}
function Get-TInternal { return @($TW.notes | Where-Object { $_.internal }) }
function Get-TPublic { return @($TW.notes | Where-Object { -not $_.internal }) }

# =================== 1. preview: confirm false changes and writes nothing ===================
New-TWorld
$r = Invoke-TRequest (New-TBody @{ confirm = 'false'; approvedBy = 'pat.lee@contoso.com' })
Check 'preview: read ok, shared mailbox, default fullAccess' ($r.read.status -eq 'ok' -and $r.read.resource.kind -eq 'shared_mailbox' -and $r.read.access_type -eq 'fullAccess' -and -not $r.readErr) "$($r.read.status) $($r.read.message) $($r.readErr)"
Check 'preview: pending_confirmation, no change, no note, no email' ($r.out.status -eq 'pending_confirmation' -and @(Get-TWrites).Count -eq 0 -and @(Get-TPsaWrites).Count -eq 0 -and $TW.mails.Count -eq 0 -and -not $r.err) "$($r.out.status) $(Show-Calls)"
Check 'preview: message names the change and the approval' ($r.out.message -match 'Give Alex Kim full access to the shared mailbox Contoso Sales' -and $r.out.message -match 'Approved by Pat Lee') $r.out.message
Check 'preview: no PSA call at all' (@($Mock.Calls | Where-Object { $_.Uri -like "$TCwUrl/*" }).Count -eq 0) (Show-Calls)
New-TWorld
$r = Invoke-TRequest (New-TBody @{ confirm = 'false' })
Check 'preview without approval: says who must approve' ($r.out.status -eq 'pending_confirmation' -and $r.out.message -match 'needs approval from: Pat Lee' -and $r.out.message -match 'Sam Doe') $r.out.message

# =================== 2. fullAccess on a shared mailbox, approved by the manager (ConnectWise) ===================
New-TWorld
$r = Invoke-TRequest (New-TBody @{ approvedBy = 'pat.lee@contoso.com' })
$o = $r.out
Check 'fullAccess: success, no error' ($o.status -eq 'success' -and -not $r.err -and $o.counts.granted -eq 1) "$($o.status) $($o.message) $($r.err)"
$fa = Get-TExoCall 'Add-MailboxPermission'
Check 'fullAccess: Add-MailboxPermission with AutoMapping on' ((Get-TExoWrites) -join ',' -eq 'Add-MailboxPermission' -and (Get-TVal $fa 'User') -eq 'alex.kim@contoso.com' -and (Get-TVal $fa 'Identity') -eq 'sales@contoso.com' -and (Get-TVal $fa 'AutoMapping') -eq $true -and @(Get-TVal $fa 'AccessRights') -contains 'FullAccess') ($fa | ConvertTo-Json -Compress)
Check 'fullAccess: read back after the grant' ($r.grant.verified -eq $true -and @($TW.exoLog | Where-Object { $_ -eq 'Get-MailboxPermission' }).Count -eq 2) ($TW.exoLog -join ',')
Check 'fullAccess: internal then public note, then closed' ($TW.notes.Count -eq 2 -and $TW.notes[0].internal -and -not $TW.notes[1].internal -and $TW.closed.Count -eq 1 -and $TW.closed[0] -eq 5 -and $o.counts.ticketsClosed -eq 1) (Show-Calls)
Check 'fullAccess: public note says it can take up to an hour in Outlook' ($o.public_note -eq 'Alex Kim now has full access to the Contoso Sales mailbox (sales@contoso.com). It can take up to an hour to appear in Outlook.' -and $TW.notes[1].text -cmatch "^$([regex]::Escape($o.public_note))`nRef: [0-9a-f]{8}$") $TW.notes[1].text
Check 'fullAccess: internal note names the approver and carries the marker' ($TW.notes[0].text -match 'Approved by Pat Lee \(pat\.lee@contoso\.com\), Alex Kim''s manager' -and $TW.notes[0].text -match '\[mailbox-group-access done fullaccess sales@contoso\.com alex\.kim@contoso\.com\]$') $TW.notes[0].text

# =================== 3. already has the access ===================
New-TWorld
$null = $TW.mbxPerms.Add(@{ id = 'sales@contoso.com'; user = 'alex.kim@contoso.com'; rights = 'FullAccess' })
$r = Invoke-TRequest (New-TBody)
Check 'already has access: success without approval, nothing changed' ($r.out.status -eq 'success' -and $r.read.already_has_access -eq $true -and @(Get-TWrites).Count -eq 0 -and $r.out.counts.alreadyHadAccess -eq 1 -and -not $r.err) "$($r.out.status) $($r.out.message)"
Check 'already has access: public note says nothing needed to change, ticket closed' ($r.out.public_note -match 'already has full access' -and $TW.notes.Count -eq 2 -and $TW.closed.Count -eq 1) $r.out.public_note

# =================== 4. the other access types ===================
New-TWorld
$r = Invoke-TRequest (New-TBody @{ accessType = 'Send As'; approvedBy = 'pat@contoso.com' })
$sa = Get-TExoCall 'Add-RecipientPermission'
Check 'sendAs (approver named by an alias address): Add-RecipientPermission' ($r.out.status -eq 'success' -and (Get-TExoWrites) -join ',' -eq 'Add-RecipientPermission' -and (Get-TVal $sa 'Trustee') -eq 'alex.kim@contoso.com' -and @(Get-TVal $sa 'AccessRights') -contains 'SendAs') "$($r.out.status) $($r.out.message)"
Check 'sendAs: public note' ($r.out.public_note -match '^Alex Kim can now send email as Contoso Sales') $r.out.public_note
New-TWorld
$r = Invoke-TRequest (New-TBody @{ accessType = 'sendOnBehalf'; approvedBy = 'pat.lee@contoso.com' })
$sob = Get-TExoCall 'Set-Mailbox'
Check 'sendOnBehalf: Set-Mailbox -GrantSendOnBehalfTo @{Add=...}, read back by name' ($r.out.status -eq 'success' -and @(Get-TVal (Get-TVal $sob 'GrantSendOnBehalfTo') 'Add') -contains 'alex.kim@contoso.com' -and $r.grant.verified) "$($r.out.status) $($r.out.message) $($sob | ConvertTo-Json -Compress -Depth 5)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'Project Falcon'; approvedBy = 'sam.doe@contoso.com' })
Check 'M365 group by name, approved by the owner: Graph member add' ($r.out.status -eq 'success' -and $r.read.resource.kind -eq 'm365_group' -and $r.read.access_type -eq 'member' -and ($TW.graphWrites -join ',') -eq 'members g-proj u-alex' -and @(Get-TExoWrites).Count -eq 0) "$($r.out.status) $($r.out.message) $($TW.graphWrites -join ',')"
Check 'M365 group: approval names the owner' ($r.out.internal_note -match 'Approved by Sam Doe \(sam\.doe@contoso\.com\), an owner of the Microsoft 365 group Project Falcon' -and $r.out.public_note -eq 'Alex Kim is now a member of the Project Falcon group.') $r.out.internal_note
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'marketing@contoso.com'; approvedBy = 'pat.lee@contoso.com' })
Check 'Team: added through its Microsoft 365 group, public note mentions Teams' ($r.out.status -eq 'success' -and $r.read.resource.kind -eq 'team' -and ($TW.graphWrites -join ',') -eq 'members g-mkt u-alex' -and $r.out.public_note -match 'Microsoft Teams') "$($r.out.status) $($r.out.public_note)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'VPN Users'; accessType = 'owner'; approvedBy = 'pat.lee@contoso.com' })
Check 'security group owner: Graph owners add' ($r.out.status -eq 'success' -and $r.read.resource.kind -eq 'security_group' -and ($TW.graphWrites -join ',') -eq 'owners g-vpn u-alex' -and $r.out.public_note -eq 'Alex Kim is now an owner of the VPN Users group.') "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'allstaff@contoso.com'; requester_email = 'pat.lee@contoso.com' })
$dg = Get-TExoCall 'Add-DistributionGroupMember'
Check 'distribution list, requested by the manager: Add-DistributionGroupMember' ($r.out.status -eq 'success' -and $r.read.resource.kind -eq 'distribution_list' -and (Get-TExoWrites) -join ',' -eq 'Add-DistributionGroupMember' -and (Get-TVal $dg 'Member') -eq 'alex.kim@contoso.com' -and (Get-TVal $dg 'BypassSecurityGroupManagerCheck') -eq $true -and @($TW.graphWrites).Count -eq 0) "$($r.out.status) $($r.out.message)"
Check 'distribution list: requester approval recorded, read back through Exchange' ($r.out.internal_note -match 'Requested by Pat Lee' -and @($TW.exoLog | Where-Object { $_ -eq 'Get-DistributionGroupMember' }).Count -ge 1 -and $r.out.public_note -eq 'Alex Kim is now a member of the All Staff distribution list.') $r.out.internal_note
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'finance-files@contoso.com'; accessType = 'owner'; approvedBy = 'sam.doe@contoso.com' })
$sd = Get-TExoCall 'Set-DistributionGroup'
Check 'mail-enabled security group owner: Set-DistributionGroup -ManagedBy @{Add=...}' ($r.out.status -eq 'success' -and $r.read.resource.kind -eq 'mail_security_group' -and @(Get-TVal (Get-TVal $sd 'ManagedBy') 'Add') -contains 'alex.kim@contoso.com' -and $r.grant.verified) "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'allstaff@contoso.com'; accessType = 'sendAs'; approvedBy = 'sam.doe@contoso.com' })
Check 'distribution list sendAs: Add-RecipientPermission on the list' ($r.out.status -eq 'success' -and (Get-TExoWrites) -join ',' -eq 'Add-RecipientPermission' -and (Get-TVal (Get-TExoCall 'Add-RecipientPermission') 'Identity') -eq 'allstaff@contoso.com') "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'boardroom@contoso.com'; accessType = 'fullAccess'; approvedBy = 'pat.lee@contoso.com' })
Check 'room mailbox: fullAccess like a shared mailbox' ($r.out.status -eq 'success' -and $r.read.resource.kind -eq 'room_mailbox' -and (Get-TExoWrites) -join ',' -eq 'Add-MailboxPermission') "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ accessType = 'member' })
Check 'member on a mailbox: incomplete, lists the access types that apply' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'fullAccess, sendAs, sendOnBehalf' -and $r.err -and @(Get-TWrites).Count -eq 0) "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'VPN Users'; accessType = 'fullAccess' })
Check 'fullAccess on a security group: incomplete' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'accessType can be: member, owner') "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ accessType = 'read' })
Check 'unknown accessType: incomplete, nothing read' ($r.out.status -eq 'incomplete' -and @($Mock.Calls | Where-Object { $_.Uri -like "$TGraph/*" }).Count -eq 0) "$($r.out.status) $($r.out.message)"

# =================== 5. refused groups ===================
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'Helpdesk Admins'; approvedBy = 'pat.lee@contoso.com' })
Check 'privileged group name: rejected, nothing changed, noted' ($r.out.status -eq 'rejected' -and $r.out.message -match "matches 'admin'" -and @(Get-TWrites).Count -eq 0 -and $r.err -and @(Get-TInternal).Count -eq 1 -and @(Get-TPublic).Count -eq 0 -and $TW.closed.Count -eq 0) "$($r.out.status) $($r.out.message)"
New-TWorld -Secrets @{ 'Access-SensitiveGroupPatterns' = 'finance, payroll' }
$r = Invoke-TRequest (New-TBody @{ resource = 'finance-files@contoso.com'; approvedBy = 'pat.lee@contoso.com' })
Check 'Access-SensitiveGroupPatterns replaces the defaults' ($r.out.status -eq 'rejected' -and $r.out.message -match "matches 'finance'") "$($r.out.status) $($r.out.message)"
New-TWorld
$TW.groups += (New-TGroup 'g-bg' 'Break-Glass Accounts' $null @() $false $true)
$TW.members['g-bg'] = New-Object System.Collections.ArrayList; $TW.owners['g-bg'] = New-Object System.Collections.ArrayList
$r = Invoke-TRequest (New-TBody @{ resource = 'Break-Glass Accounts' })
Check 'phrase pattern "break glass" matches "Break-Glass"' ($r.out.status -eq 'rejected' -and $r.out.message -match "matches 'break glass'") "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'Tier 1 Support'; approvedBy = 'pat.lee@contoso.com' })
Check 'role-assignable group: rejected' ($r.out.status -eq 'rejected' -and $r.out.message -match 'Entra admin roles' -and @(Get-TWrites).Count -eq 0) "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'All Contoso Users'; approvedBy = 'pat.lee@contoso.com' })
Check 'dynamic group: rejected, names the rule' ($r.out.status -eq 'rejected' -and $r.out.message -match 'dynamic membership' -and $r.out.message -match 'user\.companyName' -and @(Get-TWrites).Count -eq 0) "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'Accounts Legacy'; approvedBy = 'pat.lee@contoso.com' })
Check 'on-premises synced group: rejected, the AD command is listed for a technician' ($r.out.status -eq 'rejected' -and $r.out.message -match 'on-premises Active Directory' -and $r.out.internal_note -match "Add-ADGroupMember -Identity 'Accounts Legacy' -Members 'alex\.kim'" -and $r.out.manual_command -like 'Add-ADGroupMember*' -and @(Get-TWrites).Count -eq 0) $r.out.internal_note

# =================== 6. approval ===================
New-TWorld
$r = Invoke-TRequest (New-TBody)
Check 'not approved: pending_approval, nothing changed, not a failed run' ($r.out.status -eq 'pending_approval' -and @(Get-TWrites).Count -eq 0 -and -not $r.err -and $TW.closed.Count -eq 0) "$($r.out.status) $($r.out.message) $($r.err)"
Check 'not approved: internal note names the manager and the mailbox owner, no public note' (@(Get-TInternal).Count -eq 1 -and @(Get-TPublic).Count -eq 0 -and $r.out.internal_note -match "Pat Lee \(pat\.lee@contoso\.com\), Alex Kim's manager" -and $r.out.internal_note -match 'Sam Doe \(sam\.doe@contoso\.com\), the owner of the shared mailbox' -and $r.out.internal_note -match 'approvedBy set to their email address and confirm set to true') $r.out.internal_note
Check 'not approved, no Access-NotifySender: no email' ($TW.mails.Count -eq 0 -and $r.out.counts.emailsSent -eq 0) ''
New-TWorld
$r = Invoke-TRequest (New-TBody @{ approvedBy = 'casey.ng@contoso.com' })
Check 'approvedBy someone who is not an approver: pending_approval with a warning' ($r.out.status -eq 'pending_approval' -and (@($r.out.warnings) -match "casey\.ng@contoso\.com isn't Alex Kim's manager").Count -eq 1 -and @(Get-TWrites).Count -eq 0) "$($r.out.status) $(@($r.out.warnings) -join ' | ')"
New-TWorld -Secrets @{ 'Access-NotifySender' = 'helpdesk@contoso.com' }
$r = Invoke-TRequest (New-TBody @{ managerEmail = 'someone.else@contoso.com' })
$mail = $TW.mails[0]
Check 'Access-NotifySender: the manager is emailed through Graph sendMail' ($r.out.status -eq 'pending_approval' -and $TW.mails.Count -eq 1 -and $mail.from -eq 'helpdesk@contoso.com' -and @($mail.body.message.toRecipients).Count -eq 1 -and $mail.body.message.toRecipients[0].emailAddress.address -eq 'pat.lee@contoso.com' -and $mail.body.message.body.content -match 'reply on ticket 12345' -and $r.out.counts.emailsSent -eq 1) ($mail | ConvertTo-Json -Depth 8 -Compress)
Check 'Access-NotifySender: the note says who was emailed' ($r.out.internal_note -match 'Emailed Pat Lee from helpdesk@contoso\.com asking for approval') $r.out.internal_note
Check 'managerEmail that is not the Microsoft 365 manager: warning, does not count' ((@($r.out.warnings) -match 'names someone\.else@contoso\.com as the manager').Count -eq 1) (@($r.out.warnings) -join ' | ')
$r = Invoke-TRequest (New-TBody @{ managerEmail = 'someone.else@contoso.com' })
Check 'pending approval rerun: no second note and no second email' ($r.out.status -eq 'pending_approval' -and $TW.notes.Count -eq 1 -and $TW.mails.Count -eq 1 -and (@($r.out.actions) -match 'already asks for this approval').Count -eq 1) "$($TW.notes.Count) $($TW.mails.Count) $(@($r.out.actions) -join ' | ')"
New-TWorld -Secrets @{ 'Access-Approvers' = 'morgan.it@contoso.com' }
$TW.managers.Remove('u-alex')
$r = Invoke-TRequest (New-TBody @{ resource = 'Project Falcon'; approvedBy = 'morgan.it@contoso.com' })
Check 'Access-Approvers: a listed approver can approve' ($r.out.status -eq 'success' -and $r.out.internal_note -match 'listed in the Access-Approvers secret') "$($r.out.status) $($r.out.message)"
New-TWorld
$TW.managers.Remove('u-alex'); $TW.owners['g-proj'].Clear()
$r = Invoke-TRequest (New-TBody @{ resource = 'Project Falcon' })
Check 'nobody can approve: pending_approval with a warning saying what to set' ($r.out.status -eq 'pending_approval' -and (@($r.out.warnings) -match 'Nobody can approve this yet').Count -eq 1) "$($r.out.status) $(@($r.out.warnings) -join ' | ')"

# =================== 7. a person's own mailbox needs a technician ===================
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'riley.ross@contoso.com'; requester_email = 'casey.ng@contoso.com' })
Check 'user mailbox: the requester (the owner''s manager) does not count, pending_approval' ($r.out.status -eq 'pending_approval' -and $r.read.needs_technician -eq $true -and $r.read.approved -eq $false -and @(Get-TWrites).Count -eq 0 -and $r.out.internal_note -match "only approvedBy counts here") "$($r.out.status) $($r.out.message)"
Check 'user mailbox: approvers are the mailbox user and their manager, not the target''s manager' ((@($r.read.approvers | ForEach-Object { $_.id }) -join ',') -eq 'u-riley,u-casey') (@($r.read.approvers | ForEach-Object { $_.id }) -join ',')
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'riley.ross@contoso.com'; confirm = 'false' })
Check 'user mailbox preview: says a technician must run it' ($r.out.status -eq 'pending_confirmation' -and $r.out.message -match "a technician must run it with approvedBy") $r.out.message
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'riley.ross@contoso.com'; approvedBy = 'casey.ng@contoso.com' })
Check 'user mailbox with the owner''s manager as approvedBy and confirm: granted' ($r.out.status -eq 'success' -and (Get-TExoWrites) -join ',' -eq 'Add-MailboxPermission') "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'riley.ross@contoso.com'; approvedBy = 'pat.lee@contoso.com' })
Check 'user mailbox: the target''s manager can''t approve someone else''s mailbox' ($r.out.status -eq 'pending_approval' -and @(Get-TWrites).Count -eq 0) "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ targetUser = 'riley.ross@contoso.com'; resource = 'riley.ross@contoso.com' })
Check 'access to your own mailbox: rejected' ($r.out.status -eq 'rejected' -and $r.out.message -match 'their own mailbox') "$($r.out.status) $($r.out.message)"

# =================== 8. Exchange Online unreachable or failing ===================
New-TWorld -Exo $false
$r = Invoke-TRequest (New-TBody @{ approvedBy = 'pat.lee@contoso.com' })
Check 'no Exchange secrets, mailbox: incomplete, nothing changed, the exact cmdlet in the note' ($r.out.status -eq 'incomplete' -and $r.out.message -match "Exchange Online couldn't be reached" -and $r.out.message -match 'MicrosoftExchange-TenantId' -and @(Get-TWrites).Count -eq 0 -and $r.err -and $r.out.internal_note -match "Add-MailboxPermission -Identity 'sales@contoso\.com' -User 'alex\.kim@contoso\.com' -AccessRights FullAccess -InheritanceType All -AutoMapping \`$true" -and $r.out.manual_command -like 'Add-MailboxPermission*') $r.out.internal_note
New-TWorld -Exo $false
$r = Invoke-TRequest (New-TBody @{ resource = 'allstaff@contoso.com'; approvedBy = 'pat.lee@contoso.com' })
Check 'no Exchange, distribution list: planned through Graph, then incomplete at the grant with the cmdlet' ($r.read.status -eq 'ok' -and $r.out.status -eq 'incomplete' -and $r.out.internal_note -match "Add-DistributionGroupMember -Identity 'allstaff@contoso\.com' -Member 'alex\.kim@contoso\.com'" -and @(Get-TWrites).Count -eq 0) "$($r.out.status) $($r.out.message)"
New-TWorld -Exo $false
$r = Invoke-TRequest (New-TBody @{ resource = 'Project Falcon'; approvedBy = 'pat.lee@contoso.com' })
Check 'no Exchange, Microsoft 365 group member: still granted through Graph' ($r.out.status -eq 'success' -and ($TW.graphWrites -join ',') -eq 'members g-proj u-alex') "$($r.out.status) $($r.out.message)"
New-TWorld
$TW.failOn = 'Add-MailboxPermission'
$r = Invoke-TRequest (New-TBody @{ approvedBy = 'pat.lee@contoso.com' })
Check 'Exchange cmdlet fails: error, the command for a technician, ticket left open' ($r.out.status -eq 'error' -and $r.out.message -match 'simulated' -and $r.out.internal_note -match 'Add-MailboxPermission -Identity' -and $TW.closed.Count -eq 0 -and @(Get-TPublic).Count -eq 0) "$($r.out.status) $($r.out.message)"
New-TWorld
$TW.dropWrites = $true
$r = Invoke-TRequest (New-TBody @{ approvedBy = 'pat.lee@contoso.com' })
Check 'read back does not show it: incomplete, retried, ticket left open' ($r.out.status -eq 'incomplete' -and $r.grant.granted -eq $true -and $r.grant.verified -eq $false -and $Mock.Sleeps -contains 10 -and $TW.closed.Count -eq 0 -and $r.out.message -match "reading it back didn't show it") "$($r.out.status) $($r.out.message)"

# =================== 9. people and resources that can't be used ===================
New-TWorld
$r = Invoke-TRequest (New-TBody @{ targetUser = 'jo@fabrikam.com'; resource = 'Project Falcon'; approvedBy = 'sam.doe@contoso.com' })
Check 'guest: rejected' ($r.out.status -eq 'rejected' -and $r.out.message -match 'is a guest' -and @(Get-TWrites).Count -eq 0) "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ targetUser = 'jo@fabrikam.com'; resource = 'Project Falcon'; approvedBy = 'sam.doe@contoso.com'; allowGuest = 'true' })
Check 'guest with allowGuest: granted, with a warning' ($r.out.status -eq 'success' -and (@($r.out.warnings) -match 'is a guest').Count -eq 1) "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ targetUser = 'dee.off@contoso.com' })
Check 'disabled user: rejected' ($r.out.status -eq 'rejected' -and $r.out.message -match 'blocked from signing in') "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ targetUser = 'nobody@contoso.com' })
Check 'unknown user: incomplete' ($r.out.status -eq 'incomplete' -and $r.out.message -match "isn't a user in this Microsoft 365 tenant") "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'nothing@contoso.com' })
Check 'unknown resource: incomplete' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'No mailbox, group or Team called nothing@contoso\.com') "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'printers@contoso.com' })
Check 'mail contact: incomplete, not something to grant' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'MailContact') "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = 'Projects' })
Check 'two groups with the same name: incomplete, lists both' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'projects-a@contoso\.com' -and $r.out.message -match 'projects-b@contoso\.com') "$($r.out.status) $($r.out.message)"
New-TWorld
$TW.forbid = @('^GET /v1\.0/groups\?')
$r = Invoke-TRequest (New-TBody)
Check 'Graph 403 on groups: error naming Group.Read.All' ($r.out.status -eq 'error' -and $r.out.message -match 'Group\.Read\.All' -and $r.err) "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ company_tenant_id = '11111111-2222-4333-8444-555555555555' })
Check 'tenant mismatch: rejected, nothing read past the sign-in' ($r.out.status -eq 'rejected' -and $r.err -match 'tenant' -and @($Mock.Calls | Where-Object { $_.Uri -like "$TGraph/v1.0/users*" }).Count -eq 0) "$($r.out.status) $($r.err)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ company_tenant_id = $TTenant; approvedBy = 'pat.lee@contoso.com' })
Check 'matching tenant: allowed' ($r.out.status -eq 'success') "$($r.out.status) $($r.out.message)"

# =================== 10. input shapes and placeholders ===================
New-TWorld
$r = Invoke-TRequest (New-TBody @{ targetUser = '<targetUser>' })
Check 'placeholder <targetUser>: incomplete' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'no targetUser') "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ resource = '{{resource}}' })
Check 'placeholder {{resource}}: incomplete' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'no resource') "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ approvedBy = '@approvedBy'; accessType = '{{accessType}}'; requester_email = '@UserEmail' })
Check 'placeholder @approvedBy, {{accessType}}, @UserEmail: ignored, defaults used, pending_approval' ($r.out.status -eq 'pending_approval' -and $r.read.access_type -eq 'fullAccess' -and $r.read.approved_by -eq '' -and $r.read.requester -eq '') "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ ticketId = '' })
Check 'no ticketId: incomplete' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'no ticketId') "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest $null
Check 'no input: incomplete' ($r.out.status -eq 'incomplete') "$($r.out.status)"
New-TWorld
$TForm = [pscustomobject]@{ trigger = [pscustomobject]@{ Ticket = [pscustomobject]@{ TicketId = 12345; Questions = @([pscustomobject]@{ Id = 'targetUser'; Value = 'alex.kim@contoso.com' }, [pscustomobject]@{ Id = 'resource'; Value = 'Project Falcon' }, [pscustomobject]@{ Id = 'accessType'; Value = 'Member' }, [pscustomobject]@{ Id = 'confirm'; Value = 'true' }) }; Company = [pscustomobject]@{ CompanyTenantId = $TTenant }; requester_email = 'sam.doe@contoso.com' } }
$r = Invoke-TRequest $TForm
Check 'CloudRadial {Ticket:{Questions}} wrapped in {trigger}: parsed and granted' ($r.out.status -eq 'success' -and $r.read.ticket_id -eq '12345' -and ($TW.graphWrites -join ',') -eq 'members g-proj u-alex') "$($r.out.status) $($r.read.message)"
New-TWorld
$r = Invoke-TRequest ((New-TBody @{ approvedBy = 'pat.lee@contoso.com' }) | ConvertTo-Json -Compress)
Check 'a JSON string body works too' ($r.out.status -eq 'success') "$($r.out.status) $($r.out.message)"
New-TWorld
$r = Invoke-TRequest (New-TBody @{ approvedBy = 'pat.lee@contoso.com'; closeTicket = 'false' })
Check 'closeTicket false: granted and noted, not closed' ($r.out.status -eq 'success' -and $TW.notes.Count -eq 2 -and $TW.closed.Count -eq 0) "$($r.out.status) $($TW.closed.Count)"
New-TWorld ''
$r = Invoke-TRequest (New-TBody @{ approvedBy = 'pat.lee@contoso.com' })
Check 'no PSA set up: still granted, with a warning' ($r.out.status -eq 'success' -and (@($r.out.warnings) -match 'No PSA is set up').Count -eq 1) "$($r.out.status) $(@($r.out.warnings) -join ' | ')"

# =================== 11. a rerun writes nothing twice ===================
New-TWorld
$null = Invoke-TRequest (New-TBody @{ approvedBy = 'pat.lee@contoso.com' })
$TN1 = $TW.notes.Count; $TW1 = @(Get-TWrites).Count
$r = Invoke-TRequest (New-TBody @{ approvedBy = 'pat.lee@contoso.com' })
Check 'rerun after success: already has access, no second note, no second change, not closed again' ($r.out.status -eq 'success' -and $r.read.already_has_access -and $TW.notes.Count -eq $TN1 -and @(Get-TWrites).Count -eq $TW1 -and $TW.closed.Count -eq 1 -and (@($r.out.actions) -match 'already noted by an earlier run').Count -eq 1) "$($TW.notes.Count)/$TN1 $($TW.closed.Count) $(@($r.out.actions) -join ' | ')"
New-TWorld
$null = Invoke-TRequest (New-TBody @{ resource = 'Helpdesk Admins' })
$r = Invoke-TRequest (New-TBody @{ resource = 'Helpdesk Admins' })
Check 'rerun of a refusal: one internal note' ($r.out.status -eq 'rejected' -and $TW.notes.Count -eq 1) "$($TW.notes.Count)"
Check 'public notes never show a marker or a status word' (@(Get-TPublic | Where-Object { $_.text -match '\[|mailbox-group-access|rejected|pending|success' }).Count -eq 0) ''

# =================== 12. Syncro and Zendesk ===================
New-TWorld 'syncro'
$r = Invoke-TRequest (New-TBody @{ approvedBy = 'pat.lee@contoso.com' })
$TSy = @(Get-TPsaWrites)
Check 'Syncro: hidden comment, public comment, then Resolved' ($r.out.status -eq 'success' -and $TSy.Count -eq 3 -and (Read-Body $TSy[0]).hidden -eq $true -and (Read-Body $TSy[1]).hidden -eq $false -and (Read-Body $TSy[1]).do_not_email -eq $false -and $TW.closed[0] -eq 'Resolved') "$($r.out.status) $(Show-Calls)"
$null = Invoke-TRequest (New-TBody @{ approvedBy = 'pat.lee@contoso.com' })
Check 'Syncro rerun: nothing written twice' (@(Get-TPsaWrites).Count -eq 3) (Show-Calls)
New-TWorld 'zendesk'
$r = Invoke-TRequest (New-TBody @{ resource = 'Project Falcon'; approvedBy = 'sam.doe@contoso.com' })
$TZd = @(Get-TPsaWrites)
Check 'Zendesk: private comment, public comment, then solved' ($r.out.status -eq 'success' -and $TZd.Count -eq 3 -and (Read-Body $TZd[0]).ticket.comment.public -eq $false -and (Read-Body $TZd[1]).ticket.comment.public -eq $true -and (Read-Body $TZd[2]).ticket.status -eq 'solved') "$($r.out.status) $(Show-Calls)"
New-TWorld 'zendesk'
$r = Invoke-TRequest (New-TBody @{ resource = 'Helpdesk Admins' })
Check 'Zendesk refusal: one private comment, not solved' ($r.out.status -eq 'rejected' -and @(Get-TPsaWrites).Count -eq 1 -and (Read-Body @(Get-TPsaWrites)[0]).ticket.comment.public -eq $false -and $TW.closed.Count -eq 0) (Show-Calls)

Complete-Test
