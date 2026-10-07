# Step 1: read the request and the user, run the safety checks and work out the offboarding plan.
# Writes nothing. Reads the user, roles, groups, licences, manager, direct reports and devices from Microsoft
# Graph, and the mailbox from Exchange Online when the runner can reach it. Its output feeds the Apply step.
function Test-OfGuid { param([string]$s) return ([string]$s).Trim() -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' }
function Test-OfTrue { param($v) return ([string]$v).Trim() -match '^(?i)(true|yes|y|1|on)$' }
function Format-OfQuote { param([string]$s) return "'" + $s.Replace("'", "''") + "'" }

$in = Get-NodeInput
if ($in -is [string]) { try { $in = $in | ConvertFrom-Json } catch { $in = $null } }
foreach ($wrap in @('trigger', 'body')) { $w = Get-OfProp $in $wrap; if ($w -is [string]) { try { $w = $w | ConvertFrom-Json } catch { $w = $null } }; if ($null -ne $w -and -not ($w -is [string])) { $in = $w } }

$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
$out = [ordered]@{
    status = 'ok'; message = ''; ticket_id = ''; psa = ''; confirm = $false; company_id = ''
    upn = ''; user_id = ''; display_name = ''; synced = $false; already_disabled = $false
    security = [ordered]@{ disable = $false; reset_password = $false; revoke = $true }
    groups_remove = @(); groups_licence = @(); exchange_groups = @(); manual = @()
    licences = @(); licence_plan = [ordered]@{ remove = $false; reason = ''; keep_until = '' }
    exchange = [ordered]@{ available = $false; mode = ''; reason = ''; org = ''; mailbox = 'unknown'; convert = $false; hide = $false; forward_to = ''; forward_name = ''; current_forwarding = ''; manual_commands = @() }
    roles = @(); direct_reports = @(); devices = @()
    warnings = @(); actions = @()
}
function Stop-OfRead {
    param([string]$Status, [string]$Msg)
    $out.status = $Status; $out.message = $Msg
    $out.warnings = @($warnings); $out.actions = @($actions)
    Set-NodeOutput $out
}

# CloudRadial form answers arrive as Ticket.Questions [{Id, Value}]; flat bodies as plain fields.
$answers = @{}
$ticketObj = Get-OfProp $in 'Ticket'
foreach ($q in @(Get-OfProp $ticketObj 'Questions')) { $qid = [string](Get-OfProp $q 'Id'); if ($qid) { $answers[$qid.ToLowerInvariant()] = Get-OfProp $q 'Value' } }
$companyObj = Get-OfProp $in 'Company'
# A value is missing when it is blank or still an unreplaced token (@Field or {{field}}).
function Get-In {
    param([string[]]$Names)
    foreach ($n in $Names) {
        $v = Get-OfProp $in $n
        if ($null -eq $v -and $answers.ContainsKey($n.ToLowerInvariant())) { $v = $answers[$n.ToLowerInvariant()] }
        if ($null -eq $v -and $n -eq 'CompanyTenantId') { $v = Get-OfProp $companyObj 'CompanyTenantId' }
        if ($null -eq $v -or $v -is [System.Management.Automation.PSCustomObject] -or $v -is [System.Collections.IDictionary]) { continue }
        $s = ([string]$v).Trim()
        if ($s -eq '' -or $s.StartsWith('@') -or $s.StartsWith('{{')) { continue }
        return $s
    }
    return ''
}

try {
    if ($null -eq $in) { Stop-OfRead 'incomplete' 'No request was received. Send at least upn.'; return }

    # ---------- 1. the request ----------
    $out.ticket_id = Get-In @('ticket_id', 'ticketId', 'TicketId')
    if (-not $out.ticket_id) { $out.ticket_id = [string](Get-OfProp $ticketObj 'TicketId') }
    $out.psa = Get-In @('psa')
    $out.confirm = Test-OfTrue (Get-In @('confirm'))
    $out.company_id = Get-In @('company_id', 'companyId', 'cloudradial_company_id')
    if (-not $out.company_id) { $out.company_id = Get-OfSecret 'CloudRadial-CompanyId' }
    $upn = Get-In @('upn', 'userPrincipalName', 'user_upn', 'email')
    $fwdManager = Test-OfTrue (Get-In @('forward_to_manager', 'forwardToManager'))
    $fwdTo = Get-In @('forward_to', 'forwardTo')
    $daysIn = Get-In @('keep_licenses_days', 'keep_licences_days', 'keepLicensesDays')
    $allowAdmin = Test-OfTrue (Get-In @('allow_admin', 'allowAdmin'))
    $alreadyShared = Test-OfTrue (Get-In @('mailbox_already_shared', 'mailboxAlreadyShared'))
    $reqEmail = Get-In @('requester_email', 'requesterEmail', 'submittedByUpn', 'UserEmail')
    $reqOid = Get-In @('requester_office_id', 'requesterOfficeId', 'userOfficeId', 'UserOfficeId')
    $tenantIn = Get-In @('company_tenant_id', 'companyTenantId', 'CompanyTenantId')
    $out.upn = $upn
    if (-not $upn) { Stop-OfRead 'incomplete' 'The request has no upn (the departing user). Nothing was changed.'; return }
    if ($upn -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$' -and -not (Test-OfGuid $upn)) { Stop-OfRead 'incomplete' "'$upn' isn't a user principal name or object id. Nothing was changed."; return }
    $days = 0
    if ($daysIn) {
        if ($daysIn -notmatch '^\d{1,3}$') { Stop-OfRead 'incomplete' "keep_licenses_days must be a whole number of days (0 to 999), not '$daysIn'. Nothing was changed."; return }
        $days = [int]$daysIn
    }
    if ($fwdTo -and $fwdTo -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { Stop-OfRead 'incomplete' "forward_to must be an email address or UPN, not '$fwdTo'. Nothing was changed."; return }
    if ($reqEmail -and $reqEmail.ToLowerInvariant() -eq $upn.ToLowerInvariant()) { Stop-OfRead 'rejected' "The requester ($reqEmail) asked to offboard their own account. A technician must handle that. Nothing was changed."; return }

    # ---------- 2. the user ----------
    $graphConn = Connect-Graph
    if ($tenantIn -and (Test-OfGuid $tenantIn)) {
        if (Test-OfGuid $graphConn.TenantId) {
            if ($tenantIn.ToLowerInvariant() -ne ([string]$graphConn.TenantId).ToLowerInvariant()) { Stop-OfRead 'rejected' "This request is for Microsoft 365 tenant $tenantIn, but this runner signs in to tenant $($graphConn.TenantId). Nothing was changed."; return }
        }
        else { $null = $warnings.Add('The M365-TenantId secret is a domain name, so the request''s tenant id could not be compared with it.') }
    }
    $user = Get-GraphUser -Id $upn -Select 'id,userPrincipalName,displayName,mail,accountEnabled,proxyAddresses,onPremisesSyncEnabled,assignedLicenses,licenseAssignmentStates,assignedPlans'
    if ($null -eq $user) { Stop-OfRead 'incomplete' "No Microsoft 365 user was found for $upn. Nothing was changed."; return }
    $uid = [string](Get-GraphProp $user 'id')
    $realUpn = [string](Get-GraphProp $user 'userPrincipalName')
    $out.user_id = $uid; $out.upn = $realUpn; $out.display_name = [string](Get-GraphProp $user 'displayName')
    $null = $actions.Add("Read $realUpn from Microsoft 365")

    # The requester can't offboard themselves (matched on the portal's own identity tokens).
    $mine = @($realUpn, [string](Get-GraphProp $user 'mail')) + @(@(Get-GraphProp $user 'proxyAddresses') | ForEach-Object { ([string]$_) -replace '^(?i)smtp:', '' })
    $mine = @($mine | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    if (($reqOid -and $reqOid.ToLowerInvariant() -eq $uid.ToLowerInvariant()) -or ($reqEmail -and $mine -contains $reqEmail.ToLowerInvariant())) {
        Stop-OfRead 'rejected' "The requester asked to offboard their own account ($realUpn). A technician must handle that. Nothing was changed."; return
    }

    # Admin roles (fail closed: if the roles can't be read, nothing happens).
    $roles = @(Get-GraphAll -Path "/v1.0/users/$uid/transitiveMemberOf/microsoft.graph.directoryRole?`$select=id,displayName" -Permission 'RoleManagement.Read.Directory (or Directory.Read.All)')
    $out.roles = @($roles | ForEach-Object { [string](Get-GraphProp $_ 'displayName') })
    if ($roles.Count) {
        if (-not $allowAdmin) { Stop-OfRead 'rejected' "$realUpn holds admin roles ($($out.roles -join ', ')). Admin accounts are offboarded by a technician; to let this workflow do it, run it again with allow_admin set to true. Nothing was changed."; return }
        $null = $warnings.Add("$realUpn holds admin roles ($($out.roles -join ', ')) and allow_admin is true. The app registration needs a privileged role (such as Privileged Authentication Administrator) to block sign-in and reset the password of an admin. Remove the role assignments by hand.")
    }

    $synced = (Get-GraphProp $user 'onPremisesSyncEnabled') -eq $true
    $out.synced = $synced
    $out.already_disabled = (Get-GraphProp $user 'accountEnabled') -eq $false
    $manual = New-Object System.Collections.ArrayList
    if ($synced) {
        $null = $manual.Add([ordered]@{ item = 'Disable the account and reset its password in on-premises Active Directory'; reason = 'The user is synced from on-premises Active Directory, so Microsoft 365 can''t change their sign-in or password.' })
        $null = $warnings.Add("$realUpn is synced from on-premises Active Directory. Sign-in, password and address list changes must be made in Active Directory.")
    }
    else {
        $out.security.disable = -not $out.already_disabled
        $out.security.reset_password = $true
    }
    if ($out.already_disabled) { $null = $warnings.Add("$realUpn was already blocked from signing in.") }

    # ---------- 3. licences ----------
    $skuNames = @{}
    foreach ($d in @(Get-GraphAll -Path "/v1.0/users/$uid/licenseDetails?`$select=skuId,skuPartNumber" -Permission 'User.Read.All')) { $skuNames[[string](Get-GraphProp $d 'skuId')] = [string](Get-GraphProp $d 'skuPartNumber') }
    function Get-OfSkuName { param([string]$Id) if ($skuNames.ContainsKey($Id) -and $skuNames[$Id]) { return $skuNames[$Id] }; return $Id }
    $direct = New-Object System.Collections.ArrayList
    $byGroup = @{}
    $states = @(@(Get-GraphProp $user 'licenseAssignmentStates') | Where-Object { $null -ne $_ })
    if ($states.Count) {
        foreach ($s in $states) {
            $sku = [string](Get-GraphProp $s 'skuId'); $grp = [string](Get-GraphProp $s 'assignedByGroup')
            if ($grp) { if (-not $byGroup.ContainsKey($grp)) { $byGroup[$grp] = New-Object System.Collections.ArrayList }; $null = $byGroup[$grp].Add((Get-OfSkuName $sku)) }
            elseif (-not @($direct | Where-Object { $_.skuId -eq $sku }).Count) { $null = $direct.Add([ordered]@{ skuId = $sku; sku = (Get-OfSkuName $sku) }) }
        }
    }
    else {
        foreach ($l in @(Get-GraphProp $user 'assignedLicenses')) { $sku = [string](Get-GraphProp $l 'skuId'); if ($sku) { $null = $direct.Add([ordered]@{ skuId = $sku; sku = (Get-OfSkuName $sku) }) } }
    }
    $out.licences = @($direct)
    $hasExchangePlan = @(@(Get-GraphProp $user 'assignedPlans') | Where-Object { ([string](Get-GraphProp $_ 'service')) -eq 'exchange' -and ([string](Get-GraphProp $_ 'capabilityStatus')) -eq 'Enabled' }).Count -gt 0

    # ---------- 4. groups ----------
    $memberOf = @(Get-GraphAll -Path "/v1.0/users/$uid/memberOf?`$select=id,displayName,groupTypes,mailEnabled,securityEnabled,onPremisesSyncEnabled,mail" -Permission 'GroupMember.Read.All (or Group.Read.All)')
    $graphGroups = New-Object System.Collections.ArrayList; $licGroups = New-Object System.Collections.ArrayList; $exGroups = New-Object System.Collections.ArrayList
    foreach ($g in $memberOf) {
        if (([string](Get-GraphProp $g '@odata.type')) -ne '#microsoft.graph.group') { continue }
        $gid = [string](Get-GraphProp $g 'id'); $name = [string](Get-GraphProp $g 'displayName'); $mail = [string](Get-GraphProp $g 'mail')
        $types = @(@(Get-GraphProp $g 'groupTypes') | ForEach-Object { [string]$_ })
        $mailOn = (Get-GraphProp $g 'mailEnabled') -eq $true; $secOn = (Get-GraphProp $g 'securityEnabled') -eq $true
        $lic = @(if ($byGroup.ContainsKey($gid)) { $byGroup[$gid] })
        $licNote = $(if ($lic.Count) { " It assigns $($lic -join ', ')." } else { '' })
        if ((Get-GraphProp $g 'onPremisesSyncEnabled') -eq $true) { $null = $manual.Add([ordered]@{ item = "Remove from $name in on-premises Active Directory"; reason = "The group is synced from on-premises Active Directory.$licNote" }); continue }
        if ($types -contains 'DynamicMembership') { $null = $manual.Add([ordered]@{ item = "Check the dynamic group $name"; reason = "Its membership follows the user's attributes, so change the attributes or the rule.$licNote" }); continue }
        $kind = ''
        if ($types -contains 'Unified') { $kind = 'Microsoft 365 group' }
        elseif ($mailOn -and -not $secOn) { $kind = 'distribution list' }
        elseif ($mailOn -and $secOn) { $kind = 'mail-enabled security group' }
        else { $kind = 'security group' }
        if ($kind -eq 'distribution list' -or $kind -eq 'mail-enabled security group') {
            $null = $exGroups.Add([ordered]@{ id = $gid; name = $name; kind = $kind; mail = $mail; command = "Remove-DistributionGroupMember -Identity $(Format-OfQuote $(if ($mail) { $mail } else { $gid })) -Member $(Format-OfQuote $realUpn) -BypassSecurityGroupManagerCheck -Confirm:`$false" })
            continue
        }
        $row = [ordered]@{ id = $gid; name = $name; kind = $kind; licences = @($lic) }
        if ($lic.Count) { $null = $licGroups.Add($row) } else { $null = $graphGroups.Add($row) }
    }
    $out.groups_remove = @($graphGroups); $out.groups_licence = @($licGroups); $out.exchange_groups = @($exGroups)
    $null = $actions.Add("Read $(@($memberOf).Count) group and role memberships")

    # ---------- 5. mailbox, through Exchange Online when it can be reached ----------
    $org = Get-OfSecret 'MicrosoftExchange-Organization'
    if (-not $org) {
        try {
            $orgs = @(Get-GraphProp (Invoke-Graph -Method GET -Path '/v1.0/organization?$select=verifiedDomains' -Permission 'Organization.Read.All') 'value')
            foreach ($d in @(Get-GraphProp $orgs[0] 'verifiedDomains')) { if ((Get-GraphProp $d 'isInitial') -eq $true) { $org = [string](Get-GraphProp $d 'name') } }
        } catch { }
    }
    $ex = $out.exchange
    $ex.org = $org
    $exOk = Connect-OfExchange -Organization $org
    $ex.available = $exOk; $ex.mode = $OfExo.Mode; $ex.reason = $OfExo.Reason
    $keepReason = ''
    $mb = $null
    if ($exOk) {
        $mb = Get-OfMailbox $realUpn
        if ($null -eq $mb) { $ex.mailbox = 'none' }
        else {
            $rtd = [string](Get-OfProp $mb 'RecipientTypeDetails')
            $ex.mailbox = $(switch ($rtd) { 'UserMailbox' { 'user' } 'SharedMailbox' { 'shared' } default { $rtd } })
            $fs = [string](Get-OfProp $mb 'ForwardingSmtpAddress'); $fa = [string](Get-OfProp $mb 'ForwardingAddress')
            $ex.current_forwarding = $(if ($fs) { $fs -replace '^(?i)smtp:', '' } else { $fa })
            $ex.convert = $ex.mailbox -eq 'user'
            $ex.hide = (@('user', 'shared') -contains $ex.mailbox) -and ((Get-OfProp $mb 'HiddenFromAddressListsEnabled') -ne $true)
            $holds = @()
            if ((Get-OfProp $mb 'LitigationHoldEnabled') -eq $true) { $holds += 'litigation hold' }
            if (@(@(Get-OfProp $mb 'InPlaceHolds') | Where-Object { $_ }).Count) { $holds += 'an in-place or retention hold' }
            if (([string](Get-OfProp $mb 'ArchiveStatus')) -eq 'Active') { $holds += 'an online archive' }
            $bytes = Get-OfMailboxBytes $realUpn
            if ($bytes -gt 50GB) { $holds += "a mailbox of $([Math]::Round($bytes / 1GB, 1)) GB (over the 50 GB shared mailbox limit)" }
            if ($holds.Count) { $keepReason = "The mailbox has $($holds -join ', '), and a shared mailbox like that still needs a licence. Licences were kept; review them by hand." }
        }
        $null = $actions.Add("Read the mailbox from Exchange Online ($($ex.mailbox))")
    }
    else {
        $ex.mailbox = $(if ($hasExchangePlan) { 'unknown' } else { 'none' })
        $null = $warnings.Add("Exchange Online couldn't be reached: $($ex.reason). The mailbox steps are listed for a technician instead.")
    }
    if ($synced -and $ex.hide) { $ex.hide = $false; $null = $manual.Add([ordered]@{ item = 'Hide the user from the address list in on-premises Active Directory (msExchHideFromAddressLists)'; reason = 'The user is synced from on-premises Active Directory.' }) }

    # Forwarding target: forward_to wins, then the manager when forward_to_manager is true.
    $target = $null
    if ($fwdTo) {
        $target = Get-GraphUser -Id $fwdTo -Select 'id,userPrincipalName,displayName,mail,accountEnabled'
        if ($null -eq $target) { $null = $warnings.Add("No Microsoft 365 user was found for forward_to ($fwdTo), so mail won't be forwarded.") }
    }
    elseif ($fwdManager) {
        try { $target = Invoke-Graph -Method GET -Path "/v1.0/users/$uid/manager?`$select=id,userPrincipalName,displayName,mail,accountEnabled" -Permission 'User.Read.All' }
        catch { if ($GraphState.LastStatus -ne 404) { throw }; $target = $null }
        if ($null -eq $target) { $null = $warnings.Add("forward_to_manager is true, but $realUpn has no manager in Microsoft 365, so mail won't be forwarded.") }
    }
    if ($null -ne $target) {
        $tUpn = [string](Get-GraphProp $target 'userPrincipalName'); $tMail = [string](Get-GraphProp $target 'mail')
        if ([string](Get-GraphProp $target 'id') -eq $uid) { $null = $warnings.Add('The forwarding target is the departing user, so mail won''t be forwarded.') }
        elseif ((Get-GraphProp $target 'accountEnabled') -eq $false) { $null = $warnings.Add("The forwarding target $tUpn is blocked from signing in, so mail won't be forwarded.") }
        elseif ($ex.mailbox -eq 'none') { $null = $warnings.Add("$realUpn has no mailbox, so there is nothing to forward.") }
        else { $ex.forward_to = $(if ($tMail) { $tMail } else { $tUpn }); $ex.forward_name = [string](Get-GraphProp $target 'displayName') }
    }
    if ($ex.current_forwarding -and -not $ex.forward_to) { $null = $warnings.Add("The mailbox already forwards to $($ex.current_forwarding). Check that this is still wanted.") }

    # Exchange steps for a technician when Exchange Online can't be reached.
    if (-not $exOk -and $hasExchangePlan) {
        $q = Format-OfQuote $realUpn
        $cmds = @(); if (-not $alreadyShared) { $cmds += "Set-Mailbox -Identity $q -Type Shared" }
        if (-not $synced) { $cmds += "Set-Mailbox -Identity $q -HiddenFromAddressListsEnabled `$true" }
        if ($ex.forward_to) { $cmds += "Set-Mailbox -Identity $q -ForwardingAddress $(Format-OfQuote $ex.forward_to) -DeliverToMailboxAndForward `$true" }
        $ex.manual_commands = @($cmds)
    }

    # ---------- 6. licence decision (licences only go once the mailbox is safe) ----------
    $lp = $out.licence_plan
    $anyLicence = ($direct.Count + $licGroups.Count) -gt 0
    if (-not $anyLicence) { $lp.reason = 'The user has no licences that this workflow can remove.' }
    elseif ($days -gt 0) { $lp.keep_until = (Get-Date).AddDays($days).ToString('yyyy-MM-dd'); $lp.reason = "Licences are kept for $days days as asked. Remove them on or after $($lp.keep_until) by running this workflow again with keep_licenses_days 0 and confirm true." }
    elseif ($exOk) {
        if ($keepReason) { $lp.reason = $keepReason }
        elseif (@('none', 'user', 'shared') -contains $ex.mailbox) { $lp.remove = $true; $lp.reason = $(if ($ex.mailbox -eq 'user') { 'Licences are removed after the mailbox is converted to shared.' } else { 'The mailbox is safe without a licence.' }) }
        else { $lp.reason = "The mailbox type is $($ex.mailbox), so licences were kept. Review them by hand." }
    }
    elseif ($alreadyShared) { $lp.remove = $true; $lp.reason = 'mailbox_already_shared is true, so the technician has confirmed the mailbox was converted to shared.'; $null = $warnings.Add('Licences are removed because mailbox_already_shared is true. Make sure the mailbox really is shared, or its mail will be lost after 30 days.') }
    elseif (-not $hasExchangePlan) { $lp.remove = $true; $lp.reason = 'The user has no Exchange Online mailbox licence, so there is no mailbox to lose.' }
    else { $lp.reason = "Exchange Online couldn't be reached, so the mailbox wasn't converted to shared. Licences stay on so the mailbox isn't lost. Convert it in Exchange, then run this workflow again with mailbox_already_shared true and confirm true." }

    # ---------- 7. report-only items ----------
    try { $out.direct_reports = @(Get-GraphAll -Path "/v1.0/users/$uid/directReports?`$select=id,displayName,userPrincipalName" -Permission 'User.Read.All' | ForEach-Object { "$(Get-GraphProp $_ 'displayName') ($(Get-GraphProp $_ 'userPrincipalName'))" }) }
    catch { $null = $warnings.Add("Couldn't read who reports to $($realUpn): $($_.Exception.Message)") }
    $devs = New-Object System.Collections.ArrayList; $seen = @{}
    foreach ($rel in @('registeredDevices', 'ownedDevices')) {
        try {
            foreach ($d in @(Get-GraphAll -Path "/v1.0/users/$uid/$rel`?`$select=id,displayName,operatingSystem,trustType" -Permission 'Device.Read.All (or Directory.Read.All)')) {
                $did = [string](Get-GraphProp $d 'id'); if (-not $did -or $seen.ContainsKey($did)) { continue }; $seen[$did] = $true
                $null = $devs.Add("$(Get-GraphProp $d 'displayName') ($(Get-GraphProp $d 'operatingSystem'), $(Get-GraphProp $d 'trustType'))")
            }
        }
        catch { $null = $warnings.Add("Couldn't read the user's $($rel): $($_.Exception.Message)") }
    }
    $out.devices = @($devs)
    $out.manual = @($manual)
    $out.message = "Planned the offboarding of $realUpn."
    $out.warnings = @($warnings); $out.actions = @($actions)
    Set-NodeOutput $out
}
catch {
    Stop-OfRead 'error' "Couldn't plan the offboarding of $($upn): $($_.Exception.Message) Nothing was changed."
}
