# Step 1: read the request and plan it. Read-only: this step changes nothing and writes nothing.
# Finds the user and the mailbox, group or Team, refuses what must never be granted automatically
# (role-assignable, privileged-looking, dynamic and on-premises synced groups), checks whether the user already
# has the access, and works out who must approve. Its output feeds the Grant step.
# Accepts a flat body, the CloudRadial {Ticket:{...}, Company:{...}} shape, or either one wrapped in {trigger:...}.

$in = Get-NodeInput
if ($in -is [string]) { try { $in = $in | ConvertFrom-Json } catch { $in = $null } }
foreach ($wrap in @('trigger', 'body')) { $w = Get-OfProp $in $wrap; if ($w -is [string]) { try { $w = $w | ConvertFrom-Json } catch { $w = $null } }; if ($null -ne $w -and -not ($w -is [string])) { $in = $w } }

$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
$out = [ordered]@{
    status = 'ok'; message = ''; ticket_id = ''; psa = ''; confirm = $false; close_ticket = $true
    target = $null; resource = $null; access_type = ''; requester = ''; approved_by = ''
    already_has_access = $false; approvers = @(); approved = $false; approval = ''; needs_technician = $false
    change = $null; manual_command = ''; exchange_org = ''; exchange_mode = ''; exchange_unreachable = $false
    warnings = @(); actions = @()
}
function Stop-AccRead {
    param([string]$Status, [string]$Msg, [string]$Command = '')
    $out.status = $Status; $out.message = $Msg
    if ($Command) { $out.manual_command = $Command }
    $out.warnings = @($warnings); $out.actions = @($actions)
    Set-NodeOutput $out
}

# CloudRadial form answers arrive as Ticket.Questions [{Id, Value}]; flat bodies as plain fields.
$answers = @{}
$ticketObj = Get-OfProp $in 'Ticket'
foreach ($q in @(Get-OfProp $ticketObj 'Questions')) { $qid = [string](Get-OfProp $q 'Id'); if ($qid) { $answers[$qid.ToLowerInvariant()] = Get-OfProp $q 'Value' } }
$companyObj = Get-OfProp $in 'Company'
# A value is missing when it is blank or still an unfilled placeholder (<x>, {{x}} or a bare @token).
function Get-In {
    param([string[]]$Names)
    foreach ($n in $Names) {
        $v = Get-OfProp $in $n
        if ($null -eq $v -and $answers.ContainsKey($n.ToLowerInvariant())) { $v = $answers[$n.ToLowerInvariant()] }
        if ($null -eq $v -and $n -eq 'CompanyTenantId') { $v = Get-OfProp $companyObj 'CompanyTenantId' }
        if ($null -ne $v -and ($v -is [array] -or $v -is [System.Collections.IList])) { $v = (@($v | ForEach-Object { [string]$_ }) -join ',') }
        if ($null -eq $v -or $v -is [System.Management.Automation.PSCustomObject] -or $v -is [System.Collections.IDictionary]) { continue }
        $s = ([string]$v).Trim()
        if (-not $s -or $s -match '^@[A-Za-z][A-Za-z0-9_]*$' -or $s -match '^\{\{.*\}\}$' -or $s -match '^<[^>]*>$') { continue }
        return $s
    }
    return ''
}
function Get-InFlag { param([string[]]$Names, [bool]$Default) $s = Get-In $Names; if (-not $s) { return $Default }; return (Test-AccTrue $s) }

$userSelect = 'id,userPrincipalName,displayName,mail,mailNickname,accountEnabled,userType'
$groupSelect = 'id,displayName,mail,mailNickname,mailEnabled,securityEnabled,groupTypes,membershipRule,onPremisesSyncEnabled,isAssignableToRole,resourceProvisioningOptions'
# A tenant user by UPN, mail or any proxy address (or by display name with -ByName). $null when there is none.
function Find-AccUser {
    param([string]$Address, [switch]$ByName)
    if (-not $Address) { return $null }
    if (Test-AccEmail $Address) {
        $u = Get-GraphUser -Id $Address -Select $userSelect
        if ($null -ne $u) { return $u }
        $a = Format-AccOData $Address
        foreach ($f in @("mail eq '$a'", "proxyAddresses/any(x:x eq 'smtp:$a')")) {
            $hit = @(Get-GraphAll -Path "/v1.0/users?`$filter=$f&`$select=$userSelect" -Permission 'User.Read.All' -MaxPages 1)
            if ($hit.Count) { return $hit[0] }
        }
        return $null
    }
    if ($ByName) {
        $hit = @(Get-GraphAll -Path "/v1.0/users?`$filter=displayName eq '$(Format-AccOData $Address)'&`$select=$userSelect" -Permission 'User.Read.All' -MaxPages 1)
        if ($hit.Count -eq 1) { return $hit[0] }
    }
    return $null
}
function ConvertTo-AccPerson {
    param($u, [string]$Role = '')
    $m = [string](Get-GraphProp $u 'mail'); $p = [string](Get-GraphProp $u 'userPrincipalName')
    return [ordered]@{ id = [string](Get-GraphProp $u 'id'); upn = $p; mail = $(if ($m) { $m } else { $p }); name = [string](Get-GraphProp $u 'displayName'); alias = [string](Get-GraphProp $u 'mailNickname'); role = $Role; kind = '' }
}
# The user's manager in Microsoft 365, or $null when none is set.
function Get-AccManager {
    param([string]$UserId)
    if (-not $UserId) { return $null }
    try { return Invoke-Graph -Method GET -Path "/v1.0/users/$(ConvertTo-GraphId $UserId)/manager?`$select=id,displayName,mail,userPrincipalName" -Permission 'User.Read.All' }
    catch { if ($GraphState.LastStatus -eq 404) { return $null }; throw }
}
# Privileged-looking group names. Each comma-separated word or phrase matches anywhere in the name, ignoring case;
# spaces in a phrase also match hyphens, dots, underscores or nothing ("break glass" matches "Break-Glass").
function Test-AccSensitive {
    param([string[]]$Names, [string[]]$Patterns)
    foreach ($p in $Patterns) {
        $rx = '(?i)' + ((@($p.Trim() -split '\s+') | ForEach-Object { [regex]::Escape($_) }) -join '[\s._-]*')
        foreach ($n in $Names) { if ($n -and $n -match $rx) { return $p.Trim() } }
    }
    return ''
}

try {
    if ($null -eq $in) { Stop-AccRead 'incomplete' 'No request was received. Send at least ticketId, targetUser and resource. Nothing was changed.'; return }

    # ---------- 1. the request ----------
    $out.ticket_id = Get-In @('ticketId', 'ticket_id', 'TicketId', 'ticketNumber')
    if (-not $out.ticket_id) { $tv = Get-OfProp $ticketObj 'TicketId'; if ($null -ne $tv) { $out.ticket_id = [string]$tv } }
    $out.psa = Get-In @('psa')
    $out.confirm = Get-InFlag @('confirm', 'approvedToWrite') $false
    $out.close_ticket = Get-InFlag @('closeTicket', 'close_ticket') $true
    $allowGuest = Get-InFlag @('allowGuest', 'allow_guest') $false
    $targetIn = Get-In @('targetUser', 'target_user', 'target', 'user', 'userPrincipalName', 'upn')
    $resIn = Get-In @('resource', 'mailbox', 'group', 'team', 'resource_email', 'resourceName')
    $atIn = Get-In @('accessType', 'access_type', 'access', 'permission')
    $out.requester = Get-In @('requester_email', 'requesterEmail', 'UserEmail', 'submittedByUpn')
    $managerIn = Get-In @('managerEmail', 'manager_email')
    $out.approved_by = Get-In @('approvedBy', 'approved_by')
    $tenantIn = Get-In @('company_tenant_id', 'companyTenantId', 'CompanyTenantId')

    if (-not $out.ticket_id) { Stop-AccRead 'incomplete' 'The request has no ticketId, so there is no ticket to note. Nothing was changed.'; return }
    if (-not $targetIn) { Stop-AccRead 'incomplete' 'The request has no targetUser (the person who should get access). Nothing was changed.'; return }
    if (-not (Test-AccEmail $targetIn)) { Stop-AccRead 'incomplete' "targetUser '$targetIn' isn't an email address or user principal name. Nothing was changed."; return }
    if (-not $resIn) { Stop-AccRead 'incomplete' 'The request has no resource (the mailbox, group or Team to get access to). Nothing was changed.'; return }
    $accessType = ''
    if ($atIn) {
        $accessType = $(switch -Regex ($atIn.ToLowerInvariant() -replace '[\s_-]+', '') {
                '^(fullaccess|full|readandmanage|fullmailboxaccess)$' { 'fullAccess' }
                '^(sendas)$' { 'sendAs' }
                '^(sendonbehalf|sendonbehalfof|onbehalf|onbehalfof)$' { 'sendOnBehalf' }
                '^(member|membership|members|join)$' { 'member' }
                '^(owner|owners|ownership)$' { 'owner' }
                default { '' }
            })
        if (-not $accessType) { Stop-AccRead 'incomplete' "accessType '$atIn' isn't one this workflow grants. Use fullAccess, sendAs, sendOnBehalf, member or owner. Nothing was changed."; return }
    }
    foreach ($e in @(@($out.requester, $out.approved_by, $managerIn) | Where-Object { $_ })) {
        if (-not (Test-AccEmail $e)) { Stop-AccRead 'incomplete' "'$e' isn't an email address. requester_email, managerEmail and approvedBy must be email addresses. Nothing was changed."; return }
    }

    # ---------- 2. the tenant ----------
    $graphConn = Connect-Graph
    if ($tenantIn -and (Test-AccGuid $tenantIn)) {
        if (Test-AccGuid $graphConn.TenantId) {
            if ($tenantIn.ToLowerInvariant() -ne ([string]$graphConn.TenantId).ToLowerInvariant()) { Stop-AccRead 'rejected' "This request is for Microsoft 365 tenant $tenantIn, but this runner signs in to tenant $($graphConn.TenantId). Nothing was changed."; return }
        }
        else { $null = $warnings.Add('The M365-TenantId secret is a domain name, so the request''s tenant id could not be compared with it.') }
    }

    # ---------- 3. the person who gets access ----------
    $tu = Find-AccUser $targetIn
    if ($null -eq $tu) { Stop-AccRead 'incomplete' "$targetIn isn't a user in this Microsoft 365 tenant. Nothing was changed."; return }
    $target = ConvertTo-AccPerson $tu
    $out.target = $target
    if ((Get-GraphProp $tu 'accountEnabled') -eq $false) { Stop-AccRead 'rejected' "$($target.name) ($($target.upn)) is blocked from signing in, so no access was given. Nothing was changed."; return }
    $utype = [string](Get-GraphProp $tu 'userType')
    if ($utype -eq 'Guest' -and -not $allowGuest) { Stop-AccRead 'rejected' "$($target.name) ($($target.upn)) is a guest, not a member of this organisation. A technician can run this again with allowGuest set to true if a guest should have this access. Nothing was changed."; return }
    if ($utype -eq 'Guest') { $null = $warnings.Add("$($target.name) is a guest; allowGuest was set, so the request was allowed.") }
    $null = $actions.Add("Found $($target.name) ($($target.upn)) in Microsoft 365")

    # ---------- 4. the mailbox, group or Team ----------
    $resource = $null
    $hits = New-Object System.Collections.ArrayList
    $filters = $(if (Test-AccEmail $resIn) { $a = Format-AccOData $resIn; @("mail eq '$a'", "proxyAddresses/any(x:x eq 'smtp:$a')") } else { @("displayName eq '$(Format-AccOData $resIn)'") })
    foreach ($f in $filters) {
        foreach ($g in @(Get-GraphAll -Path "/v1.0/groups?`$filter=$f&`$select=$groupSelect" -Permission 'Group.Read.All' -MaxPages 1)) {
            if (-not @($hits | Where-Object { (Get-GraphProp $_ 'id') -eq (Get-GraphProp $g 'id') }).Count) { $null = $hits.Add($g) }
        }
        if ($hits.Count) { break }
    }
    if ($hits.Count -gt 1) { Stop-AccRead 'incomplete' "More than one group is called '$resIn': $(@($hits | ForEach-Object { "$(Get-GraphProp $_ 'displayName') ($(if (Get-GraphProp $_ 'mail') { Get-GraphProp $_ 'mail' } else { Get-GraphProp $_ 'id' }))" }) -join ', '). Send the group's email address instead. Nothing was changed."; return }

    $mbxUser = $null
    if ($hits.Count -eq 1) {
        $g = $hits[0]
        $types = @(@(Get-GraphProp $g 'groupTypes') | ForEach-Object { [string]$_ })
        $prov = @(@(Get-GraphProp $g 'resourceProvisioningOptions') | ForEach-Object { [string]$_ })
        $mailOn = (Get-GraphProp $g 'mailEnabled') -eq $true; $secOn = (Get-GraphProp $g 'securityEnabled') -eq $true
        $kind = $(if ($types -contains 'Unified') { $(if ($prov -contains 'Team') { 'team' } else { 'm365_group' }) } elseif ($mailOn -and $secOn) { 'mail_security_group' } elseif ($mailOn) { 'distribution_list' } else { 'security_group' })
        $resource = [ordered]@{ kind = $kind; label = $AccKinds[$kind]; id = [string](Get-GraphProp $g 'id'); name = [string](Get-GraphProp $g 'displayName'); mail = [string](Get-GraphProp $g 'mail'); alias = [string](Get-GraphProp $g 'mailNickname'); mailbox_user_id = '' }
        $out.resource = $resource
        $null = $actions.Add("Found the $($resource.label) $($resource.name) in Microsoft 365")
        $rname = "The $($resource.label) $($resource.name)"
        # Never granted automatically: these need a person with the right role, or a change somewhere else.
        if ((Get-GraphProp $g 'isAssignableToRole') -eq $true) { Stop-AccRead 'rejected' "$rname can be given Microsoft Entra admin roles, so membership of it is never granted automatically. A Privileged Role Administrator has to decide this one. Nothing was changed."; return }
        $patSecret = Get-OfSecret 'Access-SensitiveGroupPatterns'
        $patterns = @($(if ($patSecret) { $patSecret -split '[,;\r\n]+' } else { @('admin', 'global', 'privileged', 'break glass', 'domain admins') }) | Where-Object { $_.Trim() })
        $hit = Test-AccSensitive @($resource.name, $resource.alias, (($resource.mail -split '@')[0])) $patterns
        if ($hit) { Stop-AccRead 'rejected' "$rname looks like a privileged group (its name matches '$hit'), so access to it is never granted automatically. A technician has to decide this one. Nothing was changed."; return }
        if ($types -contains 'DynamicMembership') { Stop-AccRead 'rejected' "$rname has dynamic membership, so people can't be added to it by hand. Its rule decides who is in it: $([string](Get-GraphProp $g 'membershipRule')). Change the user's attributes or the rule instead. Nothing was changed."; return }
        if ((Get-GraphProp $g 'onPremisesSyncEnabled') -eq $true) {
            $cmd = "Add-ADGroupMember -Identity $(Format-AccQuote $resource.name) -Members $(Format-AccQuote (($target.upn -split '@')[0]))"
            Stop-AccRead 'rejected' "$rname is synced from on-premises Active Directory, so it can only be changed there. A technician can add $($target.name) in Active Directory and let Entra Connect sync. Nothing was changed." $cmd
            return
        }
    }
    else {
        # Not a group: a mailbox. Exchange Online says which kind.
        $mbxUser = Find-AccUser $resIn -ByName
        $org = Get-OfSecret 'MicrosoftExchange-Organization'
        if (-not $org -and ((Get-OfSecret 'MicrosoftExchange-CertificateThumbprint') -or (Get-OfSecret 'MicrosoftExchange-Certificate'))) {
            try { $ini = @(Get-GraphAll -Path '/v1.0/domains?$select=id,isInitial' -Permission 'Domain.Read.All' | Where-Object { (Get-GraphProp $_ 'isInitial') -eq $true }); if ($ini.Count) { $org = [string](Get-GraphProp $ini[0] 'id') } } catch { }
        }
        $out.exchange_org = $org
        if (-not (Connect-OfExchange -Organization $org)) {
            $out.exchange_unreachable = $true
            if ($null -eq $mbxUser) { Stop-AccRead 'incomplete' "No group called $resIn was found, and Exchange Online couldn't be reached to look for a mailbox: $($OfExo.Reason.TrimEnd('.')). Nothing was changed."; return }
            $guess = ConvertTo-AccPerson $mbxUser
            $at = $(if ($accessType) { $accessType } else { 'fullAccess' })
            $tmp = [ordered]@{ kind = 'shared_mailbox'; label = 'mailbox'; id = $guess.id; name = $guess.name; mail = $guess.mail; alias = $guess.alias; mailbox_user_id = $guess.id }
            $cmd = (Get-AccChange $tmp $target $at).command
            Stop-AccRead 'incomplete' "Exchange Online couldn't be reached, so it can't be checked whether $($guess.mail) is a shared or a personal mailbox, or what access $($target.name) already has: $($OfExo.Reason.TrimEnd('.')). Nothing was changed. A technician can check the approval and run the command in the internal note." $cmd
            return
        }
        $out.exchange_mode = $OfExo.Mode
        $rec = $null
        try { $rec = Get-OfRecipient $(if ($null -ne $mbxUser) { [string](Get-GraphProp $mbxUser 'userPrincipalName') } else { $resIn }) }
        catch { if ($_.Exception.Message -match '(?i)matches multiple') { Stop-AccRead 'incomplete' "More than one mailbox matches '$resIn'. Send its email address instead. Nothing was changed."; return }; throw }
        if ($null -eq $rec) { Stop-AccRead 'incomplete' "No mailbox, group or Team called $resIn was found in this Microsoft 365 tenant. Check the name or send its email address. Nothing was changed."; return }
        $rtd = [string](Get-OfProp $rec 'RecipientTypeDetails')
        $kind = $(switch ($rtd) { 'SharedMailbox' { 'shared_mailbox' } 'RoomMailbox' { 'room_mailbox' } 'EquipmentMailbox' { 'equipment_mailbox' } 'UserMailbox' { 'user_mailbox' } default { '' } })
        $rmail = [string](Get-OfProp $rec 'PrimarySmtpAddress')
        if (-not $kind) { Stop-AccRead 'incomplete' "$resIn is a $(if ($rtd) { $rtd } else { 'recipient' }) in Exchange Online, not a mailbox, group or Team this workflow can give access to. Nothing was changed."; return }
        if ($null -eq $mbxUser -and $rmail) { $mbxUser = Find-AccUser $rmail }
        $mp = $(if ($null -ne $mbxUser) { ConvertTo-AccPerson $mbxUser } else { $null })
        $resource = [ordered]@{ kind = $kind; label = $AccKinds[$kind]; id = $(if ($mp) { $mp.id } else { [string](Get-OfProp $rec 'ExternalDirectoryObjectId') }); name = [string](Get-OfProp $rec 'DisplayName'); mail = $rmail; alias = [string](Get-OfProp $rec 'Alias'); mailbox_user_id = $(if ($mp) { $mp.id } else { [string](Get-OfProp $rec 'ExternalDirectoryObjectId') }) }
        if (-not $resource.name) { $resource.name = $rmail }
        $out.resource = $resource
        $null = $actions.Add("Found the $($resource.label) $($resource.name) ($rmail) in Exchange Online")
        if ($resource.mailbox_user_id -and $resource.mailbox_user_id -eq $target.id) { Stop-AccRead 'rejected' "$($target.name) already owns the mailbox $rmail; it is their own mailbox. Nothing was changed."; return }
    }

    # ---------- 5. which access ----------
    $allowed = @($AccAllowed[$resource.kind])
    if (-not $accessType) { $accessType = $allowed[0] }
    if ($allowed -notcontains $accessType) { Stop-AccRead 'incomplete' "$accessType doesn't apply to the $($resource.label) $($resource.name). For it, accessType can be: $($allowed -join ', '). Nothing was changed."; return }
    $out.access_type = $accessType
    $change = Get-AccChange $resource $target $accessType
    $out.change = $change
    $out.manual_command = $change.command

    # ---------- 6. does the user already have it? ----------
    if ((Test-AccNeedsExchange $resource $accessType) -and -not $OfExo.Connected) {
        $org = Get-OfSecret 'MicrosoftExchange-Organization'; $out.exchange_org = $org
        if (-not (Connect-OfExchange -Organization $org)) {
            $out.exchange_unreachable = $true
            Stop-AccRead 'incomplete' "Exchange Online couldn't be reached, so what access $($target.name) already has to the $($resource.label) $($resource.name) couldn't be checked: $($OfExo.Reason.TrimEnd('.')). Nothing was changed. A technician can check the approval and run the command in the internal note." $change.command
            return
        }
        $out.exchange_mode = $OfExo.Mode
    }
    if (Test-AccHasAccess $resource $target $accessType) {
        $out.already_has_access = $true
        $out.message = "$($target.name) already has $($AccPhrase[$accessType]) the $($resource.label) $($resource.name). Nothing needs to change."
        $out.warnings = @($warnings); $out.actions = @($actions)
        Set-NodeOutput $out
        return
    }
    $null = $actions.Add("Checked that $($target.name) doesn't have $($AccPhrase[$accessType]) it yet")

    # ---------- 7. who can approve ----------
    $approvers = New-Object System.Collections.ArrayList
    function Add-AccApprover { param($u, [string]$Role, [string]$Kind) if ($null -eq $u) { return }; $p = ConvertTo-AccPerson $u $Role; $p.kind = $Kind; if (-not $p.id -or @($approvers | Where-Object { $_.id -eq $p.id }).Count) { return }; $null = $approvers.Add($p) }
    $isUserMailbox = $resource.kind -eq 'user_mailbox'
    if ($isUserMailbox) {
        # A person's own mailbox: only that person or their manager can approve, and a technician must run it.
        if ($resource.mailbox_user_id) { Add-AccApprover (Get-GraphUser -Id $resource.mailbox_user_id -Select $userSelect) "the owner of the mailbox $($resource.mail)" owner }
        Add-AccApprover (Get-AccManager $resource.mailbox_user_id) "the manager of $($resource.name), whose mailbox it is" manager
        $out.needs_technician = @('fullAccess', 'sendAs') -contains $accessType
    }
    else {
        Add-AccApprover (Get-AccManager $target.id) "$($target.name)'s manager" manager
        if ($AccMailboxKinds -contains $resource.kind) {
            # A shared, room or equipment mailbox has no owner in Exchange; the manager set on its account is its owner.
            Add-AccApprover (Get-AccManager $resource.mailbox_user_id) "the owner of the $($resource.label) $($resource.name), set as the manager on its account" owner
        }
        else {
            foreach ($o in @(Get-GraphAll -Path "/v1.0/groups/$($resource.id)/owners?`$select=$userSelect&`$top=999" -Permission 'Group.Read.All')) {
                if ([string](Get-GraphProp $o '@odata.type') -match 'servicePrincipal') { continue }
                Add-AccApprover $o "an owner of the $($resource.label) $($resource.name)" owner
            }
        }
    }
    foreach ($e in @((Get-OfSecret 'Access-Approvers') -split '[,;\s]+' | Where-Object { Test-AccEmail $_ })) { Add-AccApprover (Find-AccUser $e) 'listed in the Access-Approvers secret' listed }
    # The target can't approve their own access (only a group's existing owner could, and they would already have it).
    $approvers = @($approvers | Where-Object { $_.id -ne $target.id })
    $out.approvers = @($approvers)
    $null = $actions.Add("Found $($approvers.Count) $(if ($approvers.Count -eq 1) { 'person' } else { 'people' }) who can approve")

    # An email matches an approver by address, or by the account it belongs to (an alias or proxy address).
    $who = @{}
    function Find-AccApprover {
        param([string]$Email)
        if (-not $Email) { return $null }
        $k = $Email.ToLowerInvariant()
        foreach ($a in $approvers) { if (@($a.mail, $a.upn) | Where-Object { $_ -and $_.ToLowerInvariant() -eq $k }) { return $a } }
        if (-not $who.ContainsKey($k)) { $u = Find-AccUser $Email; $who[$k] = $(if ($null -ne $u) { [string](Get-GraphProp $u 'id') } else { '' }) }
        if ($who[$k]) { foreach ($a in $approvers) { if ($a.id -eq $who[$k]) { return $a } } }
        return $null
    }
    $ok = Find-AccApprover $out.approved_by
    if ($null -ne $ok) { $out.approved = $true; $out.approval = "Approved by $($ok.name) ($($ok.mail)), $($ok.role)." }
    elseif ($out.approved_by) { $null = $warnings.Add("approvedBy $($out.approved_by) isn't $(if ($isUserMailbox) { "$($resource.name) or their manager" } else { "$($target.name)'s manager or an owner of the $($resource.label)" }), so it doesn't count as approval.") }
    if (-not $out.approved -and $out.requester -and -not $out.needs_technician) {
        $ok = Find-AccApprover $out.requester
        if ($null -ne $ok) { $out.approved = $true; $out.approval = "Requested by $($ok.name) ($($ok.mail)), who is $($ok.role), so the request is its own approval." }
    }
    if ($managerIn) {
        $mgr = @($approvers | Where-Object { $_.kind -eq 'manager' })
        if (-not @($mgr | Where-Object { $_.mail -ieq $managerIn -or $_.upn -ieq $managerIn }).Count) {
            $null = $warnings.Add("The request names $managerIn as the manager, but Microsoft 365 $(if ($mgr.Count) { "has $(@($mgr | ForEach-Object { $_.mail }) -join ', ')" } else { 'has no manager set' }). Only Microsoft 365 counts for approval.")
        }
    }
    if (-not $out.approved -and -not $approvers.Count) { $null = $warnings.Add("Nobody can approve this yet: $(if ($isUserMailbox) { "$($resource.name) has no account the workflow can read" } else { "$($target.name) has no manager set in Microsoft 365 and the $($resource.label) has no owner" }). Set one (or add the Access-Approvers secret) and run it again.") }

    $out.message = "Planned: $($change.description)."
    $out.warnings = @($warnings); $out.actions = @($actions)
    Set-NodeOutput $out
}
catch {
    Stop-AccRead 'error' "Couldn't check the access request: $($_.Exception.Message) Nothing was changed."
}
