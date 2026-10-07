# Step 1: read the request, the department map and the user, and work out the plan.
# Writes nothing. Its output feeds the Apply step, which previews or applies the plan and notes the ticket.
function Get-RcProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-RcSecret { param([string]$Name) $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue } catch { }; return $v }
function Test-RcGuid { param([string]$s) return ([string]$s).Trim() -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' }

$in = Get-NodeInput
if ($in -is [string]) { try { $in = $in | ConvertFrom-Json } catch { $in = $null } }
foreach ($wrap in @('trigger', 'body')) { $w = Get-RcProp $in $wrap; if ($w -is [string]) { try { $w = $w | ConvertFrom-Json } catch { $w = $null } }; if ($null -ne $w -and -not ($w -is [string])) { $in = $w } }

$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
$out = [ordered]@{
    status = 'ok'; message = ''; ticket_id = ''; psa = ''; confirm = $false
    upn = ''; user_id = ''; display_name = ''
    old_department = ''; new_department = ''
    current = [ordered]@{ department = ''; jobTitle = ''; manager = '' }
    profile = $null; manager = $null
    adds = @(); removes = @(); exchange = @(); manual = @(); licenses = @(); unchanged = @()
    warnings = @(); actions = @()
}
function Stop-Read {
    param([string]$Status, [string]$Msg)
    $out.status = $Status; $out.message = $Msg
    $out.warnings = @($warnings); $out.actions = @($actions)
    Set-NodeOutput $out
}

# CloudRadial form answers arrive as Ticket.Questions [{Id, Value}]; flat bodies as plain fields.
$answers = @{}
$ticketObj = Get-RcProp $in 'Ticket'
foreach ($q in @(Get-RcProp $ticketObj 'Questions')) { $qid = [string](Get-RcProp $q 'Id'); if ($qid) { $answers[$qid.ToLowerInvariant()] = Get-RcProp $q 'Value' } }
# A value is missing when it is blank or still an unreplaced token (@Field or {{field}}).
function Get-In {
    param([string[]]$Names)
    foreach ($n in $Names) {
        $v = Get-RcProp $in $n
        if ($null -eq $v -and $answers.ContainsKey($n.ToLowerInvariant())) { $v = $answers[$n.ToLowerInvariant()] }
        if ($null -eq $v -or $v -is [System.Management.Automation.PSCustomObject] -or $v -is [System.Collections.IDictionary]) { continue }
        $s = ([string]$v).Trim()
        if ($s -eq '' -or $s.StartsWith('@') -or $s.StartsWith('{{')) { continue }
        return $s
    }
    return ''
}

try {
    if ($null -eq $in) { Stop-Read 'incomplete' 'No request was received. Send at least upn and new_department.'; return }

    # ---------- 1. the request ----------
    $out.ticket_id = Get-In @('ticket_id', 'ticketId', 'TicketId')
    if (-not $out.ticket_id) { $out.ticket_id = [string](Get-RcProp $ticketObj 'TicketId') }
    $out.psa = Get-In @('psa')
    $out.confirm = (Get-In @('confirm')) -match '^(?i)(true|yes|y|1)$'
    $upn = Get-In @('upn', 'userPrincipalName', 'user_upn', 'email')
    $newDept = Get-In @('new_department', 'newDepartment', 'department')
    $newTitle = Get-In @('new_title', 'newTitle', 'job_title', 'jobTitle')
    $newMgr = Get-In @('new_manager_upn', 'newManagerUpn', 'manager_upn', 'manager')
    $oldDeptIn = Get-In @('old_department', 'oldDepartment')
    $tenantIn = Get-In @('company_tenant_id', 'companyTenantId', 'CompanyTenantId')
    $out.upn = $upn; $out.new_department = $newDept
    $miss = @(); if (-not $upn) { $miss += 'upn' }; if (-not $newDept) { $miss += 'new_department' }
    if ($miss.Count) { Stop-Read 'incomplete' "The request has no $($miss -join ' or '). Nothing was changed."; return }
    if ($upn -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$' -and -not (Test-RcGuid $upn)) { Stop-Read 'incomplete' "'$upn' isn't a user principal name or object id. Nothing was changed."; return }

    # ---------- 2. the department map ----------
    $companyId = ([string](Get-RcSecret 'DepartmentMap-CompanyId')).Trim()
    if (-not $companyId) { $companyId = Get-In @('company_id', 'companyId') }
    if ($companyId -notmatch '^\d+$') { Stop-Read 'incomplete' 'No department map company was set. Add the DepartmentMap-CompanyId secret (the CloudRadial company id that holds the department map article).'; return }
    $title = Get-In @('map_article'); if (-not $title) { $title = ([string](Get-RcSecret 'DepartmentMap-ArticleTitle')).Trim() }; if (-not $title) { $title = 'Role Change: Department Map' }
    $null = Connect-Cr
    $f = "companyId eq $companyId and subject eq '$($title -replace "'", "''")'"
    $found = @(Get-CrProp (Invoke-CrApi -Path "/v2/odata/article?`$filter=$([uri]::EscapeDataString($f))&`$select=articleId,subject,companyId") 'value' | Where-Object { $null -ne $_ })
    # Only an article in this company counts, so another client's map is never read.
    $found = @($found | Where-Object { $null -eq (Get-CrProp $_ 'companyId') -or [string](Get-CrProp $_ 'companyId') -eq $companyId })
    if (-not $found.Count) { Stop-Read 'incomplete' "The department map wasn't found: there is no KB article titled '$title' in CloudRadial company $companyId. Create it from the template in the README. Nothing was changed."; return }
    if ($found.Count -gt 1) { $null = $warnings.Add("$($found.Count) articles in company $companyId are titled '$title'. The first one was used.") }
    $art = Invoke-CrApi -Path "/v2/article/$(Get-CrProp $found[0] 'articleId')"
    $html = Get-CrProp $art 'body'; if ($null -eq $html) { $html = Get-CrProp (Get-CrProp $art 'data') 'body' }
    $map = Read-RcDepartmentMap @(ConvertFrom-RcArticleBody ([string]$html))
    foreach ($w in @($map.Warnings)) { $null = $warnings.Add($w) }
    if (@($map.Errors).Count) { Stop-Read 'incomplete' ("The department map has errors, so nothing was changed. Fix them in the '$title' article:`n- " + (@($map.Errors) -join "`n- ")); return }
    $null = $actions.Add("Read the department map '$title' ($(@($map.Rows).Count) rows)")
    $newRows = @(Select-RcDepartment $map.Rows $newDept)
    if (-not $newRows.Count) { Stop-Read 'incomplete' "'$newDept' isn't in the department map. Add its groups to the '$title' article, or check the spelling. Nothing was changed."; return }

    # ---------- 3. the user ----------
    $graphConn = Connect-Graph
    if ($tenantIn -and (Test-RcGuid $tenantIn)) {
        if (Test-RcGuid $graphConn.TenantId) {
            if ($tenantIn.ToLowerInvariant() -ne ([string]$graphConn.TenantId).ToLowerInvariant()) { Stop-Read 'rejected' "This request is for Microsoft 365 tenant $tenantIn, but this runner signs in to tenant $($graphConn.TenantId). Nothing was changed."; return }
        }
        else { $null = $warnings.Add('The M365-TenantId secret is a domain name, so the request''s tenant id could not be compared with it.') }
    }
    $user = Get-GraphUser -Id $upn -Select 'id,userPrincipalName,displayName,accountEnabled,jobTitle,department'
    if ($null -eq $user) { Stop-Read 'incomplete' "No Microsoft 365 user was found for $upn. Nothing was changed."; return }
    $uid = [string](Get-GraphProp $user 'id')
    $out.user_id = $uid; $out.upn = [string](Get-GraphProp $user 'userPrincipalName'); $out.display_name = [string](Get-GraphProp $user 'displayName')
    $curDept = [string](Get-GraphProp $user 'department'); $curTitle = [string](Get-GraphProp $user 'jobTitle')
    $out.current.department = $curDept; $out.current.jobTitle = $curTitle
    if ((Get-GraphProp $user 'accountEnabled') -eq $false) { $null = $warnings.Add("$($out.upn) is blocked from signing in. Check this is a mover and not a leaver.") }
    $null = $actions.Add("Read $($out.upn) from Microsoft 365")

    $oldDept = if ($oldDeptIn) { $oldDeptIn } else { $curDept }
    $out.old_department = $oldDept
    $oldRows = @()
    if (-not $oldDept) { $null = $warnings.Add('No old department was given and the user has none in Microsoft 365, so nothing will be removed.') }
    else {
        $oldRows = @(Select-RcDepartment $map.Rows $oldDept)
        if (-not $oldRows.Count) { $null = $warnings.Add("The old department '$oldDept' isn't in the department map, so no groups will be removed.") }
    }
    $sameDept = $oldDept -and ((($oldDept.Trim() -replace '\s+', ' ').ToLowerInvariant()) -eq (($newDept.Trim() -replace '\s+', ' ').ToLowerInvariant()))
    if ($sameDept) { $oldRows = @() }

    # Current manager (none is fine).
    $curMgr = $null
    try { $curMgr = Invoke-Graph -Method GET -Path "/v1.0/users/$uid/manager?`$select=id,userPrincipalName,displayName" -Permission 'User.Read.All' }
    catch { if ($GraphState.LastStatus -ne 404) { throw } }
    $curMgrId = [string](Get-GraphProp $curMgr 'id'); $out.current.manager = [string](Get-GraphProp $curMgr 'userPrincipalName')

    # Direct group memberships, including distribution lists.
    $member = @{}
    foreach ($m in @(Get-GraphAll -Path "/v1.0/users/$uid/memberOf?`$select=id,displayName" -Permission 'GroupMember.Read.All (or Group.Read.All)')) {
        $t = [string](Get-GraphProp $m '@odata.type')
        if ($t -and $t -ne '#microsoft.graph.group') { continue }
        $member[[string](Get-GraphProp $m 'id')] = $true
    }
    $null = $actions.Add("Read $($member.Count) group memberships")

    # ---------- 4. resolve each group the two departments name ----------
    $resolved = @{}
    $badGroups = New-Object System.Collections.ArrayList
    $sel = 'id,displayName,mail,mailEnabled,securityEnabled,groupTypes,onPremisesSyncEnabled'
    foreach ($r in @($newRows + $oldRows | Where-Object { $_.group })) {
        $ref = [string]$r.group
        $key = $ref.ToLowerInvariant()
        if ($resolved.ContainsKey($key)) { continue }
        $grp = $null
        if (Test-RcGuid $ref) {
            try { $grp = Invoke-Graph -Method GET -Path "/v1.0/groups/$($ref.Trim())?`$select=$sel" -Permission 'Group.Read.All' }
            catch { if ($GraphState.LastStatus -ne 404) { throw } }
            if ($null -eq $grp) { $null = $badGroups.Add("$($r.department): no group has the object id $ref") ; continue }
        }
        else {
            $flt = "displayName eq '$($ref -replace "'", "''")'"
            $hits = @(Get-GraphAll -Path "/v1.0/groups?`$filter=$([uri]::EscapeDataString($flt))&`$select=$sel" -Permission 'Group.Read.All')
            if (-not $hits.Count) { $null = $badGroups.Add("$($r.department): no group is named '$ref'"); continue }
            if ($hits.Count -gt 1) { $null = $badGroups.Add("$($r.department): $($hits.Count) groups are named '$ref'. Use its object id in the map instead"); continue }
            $grp = $hits[0]
        }
        $types = @(Get-GraphProp $grp 'groupTypes' | Where-Object { $_ })
        $mail = (Get-GraphProp $grp 'mailEnabled') -eq $true
        $sec = (Get-GraphProp $grp 'securityEnabled') -eq $true
        $actual = if ($types -contains 'Unified') { 'm365' } elseif ($mail -and -not $sec) { 'distribution' } elseif ($mail -and $sec) { 'mail-enabled security' } else { 'security' }
        $how = 'graph'
        if ($types -contains 'DynamicMembership') { $how = 'dynamic' }
        elseif ((Get-GraphProp $grp 'onPremisesSyncEnabled') -eq $true) { $how = 'onprem' }
        elseif ($actual -eq 'distribution' -or $actual -eq 'mail-enabled security') { $how = 'exchange' }
        if ($r.kind -and $r.kind -ne $actual) { $null = $warnings.Add("The map lists '$ref' as $($r.kind), but Microsoft 365 says it is a $actual group. It was treated as a $actual group.") }
        $resolved[$key] = @{ id = [string](Get-GraphProp $grp 'id'); name = [string](Get-GraphProp $grp 'displayName'); kind = $actual; how = $how }
    }
    if ($badGroups.Count) { Stop-Read 'incomplete' ("The department map names groups that don't exist in Microsoft 365, so nothing was changed. Fix these rows in the '$title' article:`n- " + (@($badGroups) -join "`n- ")); return }
    $null = $actions.Add("Matched $($resolved.Count) groups from the map")

    # ---------- 5. the plan ----------
    $newIds = @{}; foreach ($r in @($newRows | Where-Object { $_.group })) { $newIds[$resolved[([string]$r.group).ToLowerInvariant()].id] = $true }
    $adds = New-Object System.Collections.ArrayList; $removes = New-Object System.Collections.ArrayList
    $exchange = New-Object System.Collections.ArrayList; $manual = New-Object System.Collections.ArrayList; $unchanged = New-Object System.Collections.ArrayList
    $seen = @{}
    $why = @{
        exchange = 'Microsoft Graph cannot change distribution lists or mail-enabled security groups. Change it in the Exchange admin center or with Exchange Online PowerShell.'
        dynamic  = 'Its membership is dynamic, so it follows the user''s attributes and cannot be changed by hand.'
        onprem   = 'It syncs from on-premises Active Directory. Change it there.'
    }
    foreach ($pair in @(@{ rows = $newRows; action = 'add' }, @{ rows = $oldRows; action = 'remove' })) {
        foreach ($r in @($pair.rows | Where-Object { $_.group })) {
            $gi = $resolved[([string]$r.group).ToLowerInvariant()]
            if ($pair.action -eq 'remove' -and $newIds.ContainsKey($gi.id)) { continue }   # in both departments: keep
            if ($seen.ContainsKey("$($pair.action)|$($gi.id)")) { continue }
            $seen["$($pair.action)|$($gi.id)"] = $true
            $isMember = $member.ContainsKey($gi.id)
            if (($pair.action -eq 'add' -and $isMember) -or ($pair.action -eq 'remove' -and -not $isMember)) { $null = $unchanged.Add("$($gi.name) ($(if ($isMember) { 'already a member' } else { 'not a member' }))"); continue }
            $entry = [ordered]@{ action = $pair.action; id = $gi.id; name = $gi.name; kind = $gi.kind }
            switch ($gi.how) {
                'graph' { if ($pair.action -eq 'add') { $null = $adds.Add($entry) } else { $null = $removes.Add($entry) } }
                'exchange' { $entry.reason = $why.exchange; $null = $exchange.Add($entry) }
                default { $entry.reason = $why[$gi.how]; $null = $manual.Add($entry) }
            }
        }
    }
    $out.adds = @($adds); $out.removes = @($removes); $out.exchange = @($exchange); $out.manual = @($manual); $out.unchanged = @($unchanged)

    # Department and title.
    $patch = [ordered]@{}
    if ($curDept -cne $newDept) { $patch.department = $newDept }
    if ($newTitle -and $curTitle -cne $newTitle) { $patch.jobTitle = $newTitle }
    if ($patch.Count) { $out.profile = $patch }

    # Manager.
    if ($newMgr) {
        $mgr = Get-GraphUser -Id $newMgr -Select 'id,userPrincipalName,displayName,accountEnabled'
        if ($null -eq $mgr) { Stop-Read 'incomplete' "No Microsoft 365 user was found for the new manager $newMgr. Nothing was changed."; return }
        $mid = [string](Get-GraphProp $mgr 'id')
        if ($mid -eq $uid) { Stop-Read 'incomplete' "$($out.upn) can't be their own manager. Nothing was changed."; return }
        if ($mid -ne $curMgrId) { $out.manager = [ordered]@{ id = $mid; upn = [string](Get-GraphProp $mgr 'userPrincipalName'); name = [string](Get-GraphProp $mgr 'displayName') } }
    }

    # Licences: flagged only, never changed.
    $newSkus = @($newRows | Where-Object { $_.license } | ForEach-Object { ([string]$_.license).Trim() } | Select-Object -Unique)
    $oldSkus = @($oldRows | Where-Object { $_.license } | ForEach-Object { ([string]$_.license).Trim() } | Select-Object -Unique)
    if ($newSkus.Count -or $oldSkus.Count) {
        $has = @{}
        foreach ($l in @(Get-GraphAll -Path "/v1.0/users/$uid/licenseDetails" -Permission 'User.Read.All')) {
            foreach ($k in @('skuId', 'skuPartNumber')) { $v = [string](Get-GraphProp $l $k); if ($v) { $has[$v.ToLowerInvariant()] = $true } }
        }
        $lic = New-Object System.Collections.ArrayList
        foreach ($s in $newSkus) { if (-not $has.ContainsKey($s.ToLowerInvariant())) { $null = $lic.Add([ordered]@{ sku = $s; change = 'assign'; reason = "$newDept uses $s and the user doesn't have it." }) } }
        $newLower = @($newSkus | ForEach-Object { $_.ToLowerInvariant() })
        foreach ($s in $oldSkus) { if ($newLower -notcontains $s.ToLowerInvariant() -and $has.ContainsKey($s.ToLowerInvariant())) { $null = $lic.Add([ordered]@{ sku = $s; change = 'remove'; reason = "$oldDept uses $s and $newDept doesn't." }) } }
        $out.licenses = @($lic)
        $null = $actions.Add('Compared licences with the map')
    }

    $out.message = "Plan ready for $($out.upn): $(@($adds).Count) groups to add, $(@($removes).Count) to remove."
    $out.warnings = @($warnings); $out.actions = @($actions)
    Set-NodeOutput $out
}
catch {
    Stop-Read 'error' "Couldn't build the role change plan: $($_.Exception.Message)"
}
