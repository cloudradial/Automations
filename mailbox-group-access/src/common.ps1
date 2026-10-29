# ---------- src/common.ps1: helpers the Read and Grant steps share (pasted in by build.js) ----------
# Needs _shared/graph.ps1 and _shared/exchange.ps1 above it.
function Test-AccGuid { param([string]$s) return ([string]$s).Trim() -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' }
function Test-AccTrue { param($v) return ($v -eq $true -or ([string]$v).Trim() -match '^(?i)(true|yes|y|1|on)$') }
function Test-AccEmail { param([string]$s) return $s -match '^[^@\s<>,;]+@[^@\s<>,;]+\.[^@\s<>,;]+$' }
function Format-AccQuote { param([string]$s) return "'" + ([string]$s).Replace("'", "''") + "'" }
function Format-AccOData { param([string]$s) return [uri]::EscapeDataString(([string]$s).Replace("'", "''")) }
function ConvertFrom-AccMaybeJson { param($v) if ($v -is [string]) { $s = $v.Trim(); if ($s -match '^[\[{]') { try { return ($s | ConvertFrom-Json) } catch { } } }; return $v }

$AccKinds = @{
    team = 'Team'; m365_group = 'Microsoft 365 group'; security_group = 'security group'; mail_security_group = 'mail-enabled security group'
    distribution_list = 'distribution list'; shared_mailbox = 'shared mailbox'; room_mailbox = 'room mailbox'; equipment_mailbox = 'equipment mailbox'; user_mailbox = 'user mailbox'
}
# How each access type reads in a sentence: "already has <phrase> the shared mailbox Contoso Sales".
$AccPhrase = @{ fullAccess = 'full access to'; sendAs = 'send-as permission on'; sendOnBehalf = 'send-on-behalf permission on'; member = 'membership of'; owner = 'ownership of' }
$AccMailboxKinds = @('shared_mailbox', 'room_mailbox', 'equipment_mailbox', 'user_mailbox')
# Groups whose membership only Exchange Online can change (Graph can read them, not write them).
$AccExchangeGroupKinds = @('distribution_list', 'mail_security_group')
# The access types each kind of resource takes; the first is the default.
$AccAllowed = @{
    team = @('member', 'owner', 'sendAs'); m365_group = @('member', 'owner', 'sendAs'); security_group = @('member', 'owner')
    mail_security_group = @('member', 'owner', 'sendAs'); distribution_list = @('member', 'owner', 'sendAs')
    shared_mailbox = @('fullAccess', 'sendAs', 'sendOnBehalf'); room_mailbox = @('fullAccess', 'sendAs', 'sendOnBehalf'); equipment_mailbox = @('fullAccess', 'sendAs', 'sendOnBehalf'); user_mailbox = @('fullAccess', 'sendAs', 'sendOnBehalf')
}

# Every way a user can be named, lower case: object id, UPN, mail, display name and alias.
function Get-AccUserKeys {
    param($User)
    return @(@('id', 'upn', 'mail', 'name', 'alias') | ForEach-Object { ([string](Get-OfProp $User $_)).Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
}
# $true when one of $Values (Exchange strings, or objects such as Get-DistributionGroupMember rows) names $User.
function Test-AccNamed {
    param($Values, $User)
    $keys = @(Get-AccUserKeys $User)
    foreach ($v in @($Values)) {
        if ($null -eq $v) { continue }
        $cands = @()
        if ($v -is [string]) { $cands = @($v) }
        else { $cands = @(@('ExternalDirectoryObjectId', 'PrimarySmtpAddress', 'WindowsLiveID', 'UserPrincipalName', 'Alias', 'Name', 'DisplayName', 'Identity') | ForEach-Object { [string](Get-OfProp $v $_) }) }
        foreach ($c in $cands) { $k = ([string]$c).Trim().ToLowerInvariant(); if ($k -and $keys -contains $k) { return $true } }
    }
    return $false
}
function Get-AccRights { param($Row) return (@(Get-OfProp $Row 'AccessRights') | ForEach-Object { [string]$_ }) -join ',' }

# The one change that gives the access, with the exact command a technician can run instead.
# Graph changes carry path and permission; Exchange changes carry cmdlet and parameters.
function Get-AccChange {
    param($Resource, $Target, [string]$AccessType)
    $kind = [string](Get-OfProp $Resource 'kind')
    $rid = [string](Get-OfProp $Resource 'id')
    $ident = [string](Get-OfProp $Resource 'mail'); if (-not $ident) { $ident = [string](Get-OfProp $Resource 'name') }
    $qi = Format-AccQuote $ident
    $tu = [string](Get-OfProp $Target 'upn'); $qu = Format-AccQuote $tu
    $tid = [string](Get-OfProp $Target 'id')
    $tn = [string](Get-OfProp $Target 'name'); $rn = [string](Get-OfProp $Resource 'name'); $label = $AccKinds[$kind]
    $c = [ordered]@{ method = 'exchange'; cmdlet = ''; parameters = [ordered]@{}; path = ''; permission = ''; description = ''; command = '' }
    switch ($AccessType) {
        'fullAccess' {
            $c.cmdlet = 'Add-MailboxPermission'; $c.parameters = [ordered]@{ Identity = $ident; User = $tu; AccessRights = @('FullAccess'); InheritanceType = 'All'; AutoMapping = $true }
            $c.description = "Give $tn full access to the $label $rn, with AutoMapping on so it appears in Outlook"
            $c.command = "Add-MailboxPermission -Identity $qi -User $qu -AccessRights FullAccess -InheritanceType All -AutoMapping `$true"
        }
        'sendAs' {
            $c.cmdlet = 'Add-RecipientPermission'; $c.parameters = [ordered]@{ Identity = $ident; Trustee = $tu; AccessRights = @('SendAs') }
            $c.description = "Let $tn send as the $label $rn"
            $c.command = "Add-RecipientPermission -Identity $qi -Trustee $qu -AccessRights SendAs -Confirm:`$false"
        }
        'sendOnBehalf' {
            $c.cmdlet = 'Set-Mailbox'; $c.parameters = [ordered]@{ Identity = $ident; GrantSendOnBehalfTo = @{ Add = @($tu) } }
            $c.description = "Let $tn send on behalf of the $label $rn"
            $c.command = "Set-Mailbox -Identity $qi -GrantSendOnBehalfTo @{Add=$qu}"
        }
        'member' {
            if ($AccExchangeGroupKinds -contains $kind) {
                $c.cmdlet = 'Add-DistributionGroupMember'; $c.parameters = [ordered]@{ Identity = $ident; Member = $tu; BypassSecurityGroupManagerCheck = $true }
                $c.command = "Add-DistributionGroupMember -Identity $qi -Member $qu -BypassSecurityGroupManagerCheck"
            }
            else {
                $c.method = 'graph'; $c.path = "/v1.0/groups/$rid/members/`$ref"; $c.permission = 'GroupMember.ReadWrite.All'
                $c.command = "New-MgGroupMember -GroupId '$rid' -DirectoryObjectId '$tid'"
            }
            $c.description = "Add $tn to the $label $rn"
        }
        'owner' {
            if ($AccExchangeGroupKinds -contains $kind) {
                $c.cmdlet = 'Set-DistributionGroup'; $c.parameters = [ordered]@{ Identity = $ident; ManagedBy = @{ Add = @($tu) }; BypassSecurityGroupManagerCheck = $true }
                $c.command = "Set-DistributionGroup -Identity $qi -ManagedBy @{Add=$qu} -BypassSecurityGroupManagerCheck"
            }
            else {
                $c.method = 'graph'; $c.path = "/v1.0/groups/$rid/owners/`$ref"; $c.permission = 'GroupMember.ReadWrite.All (or Group.ReadWrite.All)'
                $c.command = "New-MgGroupOwner -GroupId '$rid' -DirectoryObjectId '$tid'"
            }
            $c.description = "Make $tn an owner of the $label $rn"
        }
    }
    return $c
}

# $true when the change would need Exchange Online to make or to check.
function Test-AccNeedsExchange {
    param($Resource, [string]$AccessType)
    $kind = [string](Get-OfProp $Resource 'kind')
    if ($AccMailboxKinds -contains $kind) { return $true }
    if ($AccessType -eq 'sendAs') { return $true }
    return $false
}

# Does the target already have this access? Reads Graph for Graph groups, and Exchange Online for mailboxes,
# send-as, and (when Exchange is connected) distribution list and mail-enabled security group changes.
function Test-AccHasAccess {
    param($Resource, $Target, [string]$AccessType)
    $kind = [string](Get-OfProp $Resource 'kind')
    $rid = [string](Get-OfProp $Resource 'id')
    $ident = [string](Get-OfProp $Resource 'mail'); if (-not $ident) { $ident = [string](Get-OfProp $Resource 'name') }
    $tid = [string](Get-OfProp $Target 'id'); $tu = [string](Get-OfProp $Target 'upn')
    $exoGroup = ($AccExchangeGroupKinds -contains $kind) -and $OfExo.Connected
    switch ($AccessType) {
        'member' {
            if ($exoGroup) {
                $rows = @(Invoke-OfExo 'Get-DistributionGroupMember' @{ Identity = $ident; ResultSize = 'Unlimited' })
                return (Test-AccNamed $rows $Target)
            }
            $ids = @(Get-GraphAll -Path "/v1.0/groups/$rid/members?`$select=id&`$top=999" -Permission 'GroupMember.Read.All (or Group.Read.All)' | ForEach-Object { [string](Get-GraphProp $_ 'id') })
            return ($ids -contains $tid)
        }
        'owner' {
            if ($exoGroup) {
                $g = @(Invoke-OfExo 'Get-DistributionGroup' @{ Identity = $ident })[0]
                return (Test-AccNamed @(Get-OfProp $g 'ManagedBy') $Target)
            }
            $ids = @(Get-GraphAll -Path "/v1.0/groups/$rid/owners?`$select=id&`$top=999" -Permission 'Group.Read.All' | ForEach-Object { [string](Get-GraphProp $_ 'id') })
            return ($ids -contains $tid)
        }
        'fullAccess' {
            $rows = @()
            try { $rows = @(Invoke-OfExo 'Get-MailboxPermission' @{ Identity = $ident; User = $tu }) } catch { if (-not (Test-OfNotFound $_.Exception.Message)) { throw } }
            return [bool](@($rows | Where-Object { (Get-AccRights $_) -match '(?i)\bFullAccess\b' -and (Get-OfProp $_ 'Deny') -ne $true -and [string](Get-OfProp $_ 'Deny') -ne 'True' }).Count)
        }
        'sendAs' {
            $rows = @()
            try { $rows = @(Invoke-OfExo 'Get-RecipientPermission' @{ Identity = $ident; Trustee = $tu }) } catch { if (-not (Test-OfNotFound $_.Exception.Message)) { throw } }
            return [bool](@($rows | Where-Object { (Get-AccRights $_) -match '(?i)\bSendAs\b' -and [string](Get-OfProp $_ 'AccessControlType') -ne 'Deny' }).Count)
        }
        'sendOnBehalf' {
            $m = @(Invoke-OfExo 'Get-Mailbox' @{ Identity = $ident })[0]
            return (Test-AccNamed @(Get-OfProp $m 'GrantSendOnBehalfTo') $Target)
        }
    }
    return $false
}
# ---------- end src/common.ps1 ----------
