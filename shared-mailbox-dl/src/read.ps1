# Step 1: read the request, check it against Microsoft 365 and Exchange Online, and work out the plan.
# Writes nothing. Checks the address is free, every member and the requester exist in the tenant, and whether the
# request needs a technician's confirmation (a member outside the requester's department, or more than 25 members).
# Its output feeds the Apply step.
function Test-SmGuid { param([string]$s) return ([string]$s).Trim() -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' }
function Test-SmTrue { param($v) return ([string]$v).Trim() -match '^(?i)(true|yes|y|1|on)$' }
function Test-SmEmail { param([string]$s) return $s -match '^[^@\s<>,;]+@[^@\s<>,;]+\.[^@\s<>,;]+$' }
function Format-SmQuote { param([string]$s) return "'" + $s.Replace("'", "''") + "'" }
function Format-SmOData { param([string]$s) return [uri]::EscapeDataString($s.Replace("'", "''")) }
# Lowercase letters, digits, dots, hyphens and underscores; no leading, trailing or doubled dots; at most 64 characters.
function ConvertTo-SmAlias {
    param([string]$s)
    $t = ([string]$s).Normalize([Text.NormalizationForm]::FormD)
    $t = -join @($t.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [Globalization.UnicodeCategory]::NonSpacingMark })
    $t = $t.ToLowerInvariant().Trim() -replace '&', ' and ' -replace '[\s/\\]+', '-' -replace '[^a-z0-9._-]', ''
    $t = $t -replace '\.{2,}', '.' -replace '-{2,}', '-' -replace '^[.\-_]+', '' -replace '[.\-_]+$', ''
    if ($t.Length -gt 64) { $t = $t.Substring(0, 64) -replace '[.\-_]+$', '' }
    return $t
}
# A comma (or semicolon, space or new line) separated list of addresses, de-duplicated. "Name <addr>" keeps addr.
function Split-SmList {
    param([string]$s)
    $seen = @{}; $list = New-Object System.Collections.ArrayList
    foreach ($p in @(([string]$s) -split '[,;\r\n]+')) {
        $v = $p.Trim(); if ($v -match '<([^>]+)>') { $v = $Matches[1].Trim() }
        foreach ($w in @($v -split '\s+')) { $w = $w.Trim().Trim('"', "'"); if (-not $w) { continue }; $k = $w.ToLowerInvariant(); if (-not $seen.ContainsKey($k)) { $seen[$k] = $true; $null = $list.Add($w) } }
    }
    return @($list)
}

$in = Get-NodeInput
if ($in -is [string]) { try { $in = $in | ConvertFrom-Json } catch { $in = $null } }
foreach ($wrap in @('trigger', 'body')) { $w = Get-OfProp $in $wrap; if ($w -is [string]) { try { $w = $w | ConvertFrom-Json } catch { $w = $null } }; if ($null -ne $w -and -not ($w -is [string])) { $in = $w } }

$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
$out = [ordered]@{
    status = 'ok'; message = ''; ticket_id = ''; psa = ''; confirm = $false; preview = $false
    kind = ''; kind_label = ''; display_name = ''; alias = ''; domain = ''; address = ''
    requester = $null; members = @(); send_as = @(); external_allowed = $false
    needs_confirmation = $false; confirmation_reasons = @()
    changes = @(); manual_commands = @(); exchange_mode = ''; exchange_org = ''; exchange_unreachable = $false
    warnings = @(); actions = @()
}
function Stop-SmRead {
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
        if ($null -ne $v -and ($v -is [array] -or $v -is [System.Collections.IList])) { $v = (@($v | ForEach-Object { [string]$_ }) -join ',') }
        if ($null -eq $v -or $v -is [System.Management.Automation.PSCustomObject] -or $v -is [System.Collections.IDictionary]) { continue }
        $s = ([string]$v).Trim()
        if ($s -eq '' -or $s.StartsWith('@') -or $s.StartsWith('{{')) { continue }
        return $s
    }
    return ''
}

# Finds a tenant user by UPN, mail or any proxy address. Returns $null when there is none.
$userSelect = 'id,userPrincipalName,displayName,mail,department,accountEnabled,userType'
function Find-SmUser {
    param([string]$Address)
    $u = Get-GraphUser -Id $Address -Select $userSelect
    if ($null -ne $u) { return $u }
    if (-not (Test-SmEmail $Address)) { return $null }
    $a = Format-SmOData $Address
    foreach ($f in @("mail eq '$a'", "proxyAddresses/any(x:x eq 'smtp:$a')")) {
        $hit = @(Get-GraphAll -Path "/v1.0/users?`$filter=$f&`$select=$userSelect" -Permission 'User.Read.All' -MaxPages 1)
        if ($hit.Count) { return $hit[0] }
    }
    return $null
}
function Get-SmDept { param($u) return ([string](Get-GraphProp $u 'department')).Trim() }
function Get-SmAddr { param($u) $m = [string](Get-GraphProp $u 'mail'); if ($m) { return $m }; return [string](Get-GraphProp $u 'userPrincipalName') }

try {
    if ($null -eq $in) { Stop-SmRead 'incomplete' 'No request was received. Send at least kind, display_name and requester_email. Nothing was created.'; return }

    # ---------- 1. the request ----------
    $out.ticket_id = Get-In @('ticket_id', 'ticketId', 'TicketId')
    if (-not $out.ticket_id) { $out.ticket_id = [string](Get-OfProp $ticketObj 'TicketId') }
    $out.psa = Get-In @('psa')
    $out.confirm = Test-SmTrue (Get-In @('confirm'))
    $out.preview = Test-SmTrue (Get-In @('preview'))
    $kindIn = (Get-In @('kind', 'type', 'request_type')).ToLowerInvariant() -replace '[\s-]+', '_'
    $kind = $(switch -Regex ($kindIn) {
            '^(shared_mailbox|shared|mailbox|sharedmailbox|shared_inbox)$' { 'shared_mailbox' }
            '^(distribution_list|distribution_group|distribution|dl|list|distributionlist|group)$' { 'distribution_list' }
            default { '' }
        })
    if (-not $kind) { Stop-SmRead 'incomplete' "kind must be shared_mailbox or distribution_list$(if ($kindIn) { ", not '$kindIn'" }). Nothing was created."; return }
    $out.kind = $kind
    $label = $(if ($kind -eq 'shared_mailbox') { 'shared mailbox' } else { 'distribution list' })
    $out.kind_label = $label
    $name = (Get-In @('display_name', 'displayName', 'name')) -replace '\s+', ' '
    if (-not $name) { Stop-SmRead 'incomplete' "The request has no display_name for the new $label. Nothing was created."; return }
    if ($name.Length -gt 64) { Stop-SmRead 'incomplete' "The display name '$name' is longer than 64 characters. Nothing was created."; return }
    if ($name -match '["\\<>\[\]:;|]') { Stop-SmRead 'incomplete' "The display name '$name' has a character Exchange doesn't accept in a name (one of `" \ < > [ ] : ; |). Nothing was created."; return }
    $out.display_name = $name
    $aliasIn = Get-In @('alias', 'mail_nickname', 'mailNickname')
    $alias = ConvertTo-SmAlias $(if ($aliasIn) { ($aliasIn -split '@')[0] } else { $name })
    if (-not $alias) { Stop-SmRead 'incomplete' "Couldn't make an email alias from '$(if ($aliasIn) { $aliasIn } else { $name })'. Send an alias of letters and numbers. Nothing was created."; return }
    if ($aliasIn -and $alias -ne ($aliasIn -split '@')[0]) { $null = $warnings.Add("The alias '$aliasIn' was cleaned up to '$alias'.") }
    $out.alias = $alias
    $domainIn = (Get-In @('domain')).TrimStart('@').ToLowerInvariant()
    if (-not $domainIn -and $aliasIn -match '@(.+)$') { $domainIn = $Matches[1].ToLowerInvariant() }
    $memberList = @(Split-SmList (Get-In @('members', 'member_upns')))
    $sendAsList = @(Split-SmList (Get-In @('send_as', 'sendAs', 'send_as_upns')))
    $out.external_allowed = Test-SmTrue (Get-In @('external_allowed', 'externalAllowed', 'allow_external_senders'))
    if ($kind -eq 'distribution_list' -and $sendAsList.Count) { $null = $warnings.Add("send_as only applies to a shared mailbox, so it was ignored for this distribution list ($($sendAsList -join ', ')).") ; $sendAsList = @() }
    if ($kind -eq 'shared_mailbox' -and $out.external_allowed) { $null = $warnings.Add('external_allowed only applies to a distribution list, so it was ignored. A shared mailbox already receives mail from outside the organisation.'); $out.external_allowed = $false }
    $reqEmail = Get-In @('requester_email', 'requesterEmail', 'UserEmail', 'submittedByUpn')
    $tenantIn = Get-In @('company_tenant_id', 'companyTenantId', 'CompanyTenantId')
    if (-not $reqEmail) { Stop-SmRead 'incomplete' "The request has no requester_email, so there is nobody to make the owner. From a portal form, send @UserEmail. Nothing was created."; return }
    $bad = @(@($memberList + $sendAsList) | Where-Object { -not (Test-SmEmail $_) })
    if ($bad.Count) { Stop-SmRead 'incomplete' "These aren't email addresses or user principal names: $($bad -join ', '). Nothing was created."; return }

    # ---------- 2. tenant, domain and address ----------
    $graphConn = Connect-Graph
    if ($tenantIn -and (Test-SmGuid $tenantIn)) {
        if (Test-SmGuid $graphConn.TenantId) {
            if ($tenantIn.ToLowerInvariant() -ne ([string]$graphConn.TenantId).ToLowerInvariant()) { Stop-SmRead 'rejected' "This request is for Microsoft 365 tenant $tenantIn, but this runner signs in to tenant $($graphConn.TenantId). Nothing was created."; return }
        }
        else { $null = $warnings.Add('The M365-TenantId secret is a domain name, so the request''s tenant id could not be compared with it.') }
    }
    $domains = @(Get-GraphAll -Path '/v1.0/domains?$select=id,isDefault,isVerified,isInitial' -Permission 'Domain.Read.All')
    $verified = @($domains | Where-Object { (Get-GraphProp $_ 'isVerified') -eq $true })
    if ($domainIn) {
        $match = @($verified | Where-Object { ([string](Get-GraphProp $_ 'id')).ToLowerInvariant() -eq $domainIn })
        if (-not $match.Count) { Stop-SmRead 'incomplete' "$domainIn isn't a verified domain in this Microsoft 365 tenant. Use one of: $(@($verified | ForEach-Object { Get-GraphProp $_ 'id' }) -join ', '). Nothing was created."; return }
        $domain = [string](Get-GraphProp $match[0] 'id')
    }
    else {
        $def = @($verified | Where-Object { (Get-GraphProp $_ 'isDefault') -eq $true })
        if (-not $def.Count) { Stop-SmRead 'error' 'Microsoft 365 returned no default domain for this tenant, so the address could not be worked out. Send a domain. Nothing was created.'; return }
        $domain = ([string](Get-GraphProp $def[0] 'id')).ToLowerInvariant()
    }
    $out.domain = $domain
    $address = "$alias@$domain"
    $out.address = $address
    $null = $actions.Add("Read the tenant's domains (using $domain)")

    # The address must be free (Graph: users always; groups when the app can read them).
    $a = Format-SmOData $address
    $taken = New-Object System.Collections.ArrayList
    foreach ($f in @("proxyAddresses/any(x:x eq 'smtp:$a')", "userPrincipalName eq '$a'", "mailNickname eq '$(Format-SmOData $alias)'")) {
        foreach ($u in @(Get-GraphAll -Path "/v1.0/users?`$filter=$f&`$select=id,displayName,userPrincipalName" -Permission 'User.Read.All' -MaxPages 1)) { $null = $taken.Add("$(Get-GraphProp $u 'displayName') ($(Get-GraphProp $u 'userPrincipalName'))") }
    }
    try {
        foreach ($f in @("proxyAddresses/any(x:x eq 'smtp:$a')", "mailNickname eq '$(Format-SmOData $alias)'")) {
            foreach ($g in @(Get-GraphAll -Path "/v1.0/groups?`$filter=$f&`$select=id,displayName,mail" -Permission 'Group.Read.All' -MaxPages 1)) { $null = $taken.Add("the group $(Get-GraphProp $g 'displayName')") }
        }
    }
    catch {
        if ($GraphState.LastStatus -eq 403) { $null = $warnings.Add('The app can''t read groups (Group.Read.All), so groups were checked through Exchange Online only.') } else { throw }
    }
    $taken = @($taken | Select-Object -Unique)
    if ($taken.Count) { Stop-SmRead 'rejected' "The address $address (alias $alias) is already used by $($taken -join ', '). Choose another alias. Nothing was created."; return }

    # ---------- 3. the requester and the members ----------
    $req = Find-SmUser $reqEmail
    if ($null -eq $req) { Stop-SmRead 'incomplete' "The requester $reqEmail isn't a user in this Microsoft 365 tenant, so they can't be the owner. Nothing was created."; return }
    $reqDept = Get-SmDept $req
    $reqId = [string](Get-GraphProp $req 'id')
    $out.requester = [ordered]@{ id = $reqId; upn = [string](Get-GraphProp $req 'userPrincipalName'); address = (Get-SmAddr $req); name = [string](Get-GraphProp $req 'displayName'); department = $reqDept }

    $missing = New-Object System.Collections.ArrayList
    $resolved = @{}
    function Resolve-SmPeople {
        param([string[]]$List)
        $rows = New-Object System.Collections.ArrayList
        foreach ($m in @($List)) {
            $k = $m.ToLowerInvariant()
            if (-not $resolved.ContainsKey($k)) {
                $u = Find-SmUser $m
                if ($null -eq $u) { $resolved[$k] = $null; $null = $missing.Add("$m (not found in this tenant)"); continue }
                if (-not [string](Get-GraphProp $u 'mail')) { $resolved[$k] = $null; $null = $missing.Add("$m (has no mailbox)"); continue }
                $resolved[$k] = [ordered]@{ id = [string](Get-GraphProp $u 'id'); upn = [string](Get-GraphProp $u 'userPrincipalName'); address = (Get-SmAddr $u); name = [string](Get-GraphProp $u 'displayName'); department = (Get-SmDept $u); enabled = ((Get-GraphProp $u 'accountEnabled') -ne $false) }
            }
            $r = $resolved[$k]
            if ($null -eq $r) { continue }
            if (@($rows | Where-Object { $_.id -eq $r.id }).Count) { continue }
            $null = $rows.Add($r)
        }
        return @($rows)
    }
    $members = @(Resolve-SmPeople $memberList)
    $sendAs = @(Resolve-SmPeople $sendAsList)
    $missing = @($missing | Select-Object -Unique)
    if ($missing.Count) { Stop-SmRead 'incomplete' "These people can't be added: $($missing -join ', '). Every member must be a user with a mailbox in this Microsoft 365 tenant. Nothing was created."; return }
    foreach ($p in @($members + $sendAs)) { if (-not $p.enabled) { $null = $warnings.Add("$($p.name) ($($p.upn)) is blocked from signing in.") } }
    $out.members = @($members); $out.send_as = @($sendAs)
    $null = $actions.Add("Read the requester and $(@($members).Count) member$(if (@($members).Count -ne 1) { 's' }) from Microsoft 365")
    if (-not $members.Count) { $null = $warnings.Add($(if ($kind -eq 'shared_mailbox') { 'No members were listed, so only the requester gets access.' } else { 'No members were listed, so the distribution list starts empty.' })) }

    # ---------- 4. does a technician need to confirm? ----------
    $reasons = New-Object System.Collections.ArrayList
    $everyone = @(@($members) + @($sendAs) | Where-Object { $_.id -ne $reqId })
    $seenIds = @{}; $everyone = @($everyone | Where-Object { if ($seenIds.ContainsKey($_.id)) { $false } else { $seenIds[$_.id] = $true; $true } })
    if (-not $reqDept) {
        if ($everyone.Count) { $null = $reasons.Add("The requester $($out.requester.name) has no department in Microsoft 365, so the department check can't be made.") }
    }
    else {
        $outside = @($everyone | Where-Object { $_.department.ToLowerInvariant() -ne $reqDept.ToLowerInvariant() })
        if ($outside.Count) { $null = $reasons.Add("$($outside.Count) $(if ($outside.Count -eq 1) { 'person is' } else { 'people are' }) outside the requester's department ($reqDept): $(@($outside | ForEach-Object { "$($_.name) ($(if ($_.department) { $_.department } else { 'no department' }))" }) -join ', ').") }
    }
    if ($members.Count -gt 25) { $null = $reasons.Add("The list has $($members.Count) members, more than 25.") }
    $out.confirmation_reasons = @($reasons)
    $out.needs_confirmation = $reasons.Count -gt 0

    # ---------- 5. the plan, as Exchange cmdlets ----------
    $changes = New-Object System.Collections.ArrayList
    function Add-SmChange {
        param([string]$Description, [string]$Cmdlet, [System.Collections.Specialized.OrderedDictionary]$Parameters, [string]$Command)
        $null = $changes.Add([ordered]@{ description = $Description; cmdlet = $Cmdlet; parameters = $Parameters; command = $Command })
    }
    $qa = Format-SmQuote $address
    $reqAddr = $out.requester.address
    if ($kind -eq 'shared_mailbox') {
        Add-SmChange "Create the shared mailbox $name ($address)" 'New-Mailbox' ([ordered]@{ Shared = $true; Name = $name; DisplayName = $name; Alias = $alias; PrimarySmtpAddress = $address }) "New-Mailbox -Shared -Name $(Format-SmQuote $name) -DisplayName $(Format-SmQuote $name) -Alias $(Format-SmQuote $alias) -PrimarySmtpAddress $qa"
        $full = @(@($out.requester) + @($members | Where-Object { $_.id -ne $reqId }))
        foreach ($p in $full) {
            $what = $(if ($p.id -eq $reqId) { "Give $($p.name) (the requester, owner) full access" } else { "Give $($p.name) full access" })
            Add-SmChange $what 'Add-MailboxPermission' ([ordered]@{ Identity = $address; User = $p.upn; AccessRights = @('FullAccess'); InheritanceType = 'All'; AutoMapping = $true }) "Add-MailboxPermission -Identity $qa -User $(Format-SmQuote $p.upn) -AccessRights FullAccess -InheritanceType All -AutoMapping `$true"
        }
        foreach ($p in $sendAs) {
            Add-SmChange "Let $($p.name) send as $address" 'Add-RecipientPermission' ([ordered]@{ Identity = $address; Trustee = $p.upn; AccessRights = @('SendAs') }) "Add-RecipientPermission -Identity $qa -Trustee $(Format-SmQuote $p.upn) -AccessRights SendAs -Confirm:`$false"
        }
    }
    else {
        $auth = -not $out.external_allowed
        Add-SmChange "Create the distribution list $name ($address) owned by $($out.requester.name)$(if ($out.external_allowed) { ', accepting mail from outside the organisation' } else { ', internal senders only' })" 'New-DistributionGroup' ([ordered]@{ Name = $name; DisplayName = $name; Alias = $alias; PrimarySmtpAddress = $address; Type = 'Distribution'; ManagedBy = @($out.requester.upn); RequireSenderAuthenticationEnabled = $auth }) "New-DistributionGroup -Name $(Format-SmQuote $name) -DisplayName $(Format-SmQuote $name) -Alias $(Format-SmQuote $alias) -PrimarySmtpAddress $qa -Type Distribution -ManagedBy $(Format-SmQuote $out.requester.upn) -RequireSenderAuthenticationEnabled `$$($auth.ToString().ToLowerInvariant())"
        foreach ($p in $members) {
            Add-SmChange "Add $($p.name) to the list" 'Add-DistributionGroupMember' ([ordered]@{ Identity = $address; Member = $p.upn; BypassSecurityGroupManagerCheck = $true }) "Add-DistributionGroupMember -Identity $qa -Member $(Format-SmQuote $p.upn) -BypassSecurityGroupManagerCheck"
        }
    }
    $out.changes = @($changes)
    $out.manual_commands = @($changes | ForEach-Object { $_.command })

    # ---------- 6. Exchange Online: reachable, and the address free there too ----------
    $org = Get-OfSecret 'MicrosoftExchange-Organization'
    if (-not $org) { $ini = @($domains | Where-Object { (Get-GraphProp $_ 'isInitial') -eq $true }); if ($ini.Count) { $org = [string](Get-GraphProp $ini[0] 'id') } }
    $out.exchange_org = $org
    if (-not (Connect-OfExchange -Organization $org)) {
        $out.exchange_unreachable = $true
        Stop-SmRead 'error' "Exchange Online couldn't be reached, so the $label $address was not created: $($OfExo.Reason.TrimEnd(".")). Nothing was created; the exact commands are in the internal note."
        return
    }
    $out.exchange_mode = $OfExo.Mode
    foreach ($id in @($address, $alias)) {
        $hit = $null
        try { $hit = Get-OfRecipient $id }
        catch { if ($_.Exception.Message -match '(?i)matches multiple') { $hit = [pscustomobject]@{ DisplayName = 'more than one existing recipient'; RecipientTypeDetails = '' } } else { throw } }
        if ($null -ne $hit) {
            $what = [string](Get-OfProp $hit 'DisplayName'); $t = [string](Get-OfProp $hit 'RecipientTypeDetails')
            Stop-SmRead 'rejected' "The $(if ($id -eq $alias) { "alias $alias" } else { "address $address" }) is already used in Exchange Online by $what$(if ($t) { " ($t)" }). Choose another alias. Nothing was created."
            return
        }
    }
    $null = $actions.Add("Checked $address is free in Exchange Online ($($OfExo.Mode))")

    $out.message = "Planned the $label $address."
    $out.warnings = @($warnings); $out.actions = @($actions)
    Set-NodeOutput $out
}
catch {
    Stop-SmRead 'error' "Couldn't check the $(if ($out.kind_label) { $out.kind_label } else { 'shared mailbox or distribution list' }) request: $($_.Exception.Message) Nothing was created."
}
