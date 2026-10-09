# === NODE: Find inactive accounts (read-only) ===
# Reads every user with its last sign-in times (needs AuditLog.Read.All and Entra ID P1) and who holds a
# directory admin role (needs RoleManagement.Read.Directory). An account is listed when it is turned on,
# is older than the threshold, and has no sign-in (interactive, non-interactive or successful) inside it.
# Guests that never signed in are listed once their invitation is older than the threshold.
# Admins and accounts synced from on-premises Active Directory are listed but flagged, and are never disabled.
# Changes nothing. A missing permission stops the run with a sentence naming it.
$ErrorActionPreference = 'Stop'
function Read-SgState {
    $raw = Get-NodeInput
    if ($null -ne $raw -and $null -eq (Get-GraphProp $raw 'inputs') -and $null -ne (Get-GraphProp $raw 'output')) { $raw = Get-GraphProp $raw 'output' }
    $st = [ordered]@{}
    if ($raw -is [System.Collections.IDictionary]) { foreach ($k in $raw.Keys) { $st[[string]$k] = $raw[$k] } }
    elseif ($null -ne $raw) { foreach ($p in $raw.PSObject.Properties) { $st[$p.Name] = $p.Value } }
    foreach ($k in @('status', 'message', 'public_note', 'internal_note', 'ticket_id')) { if (-not $st.Contains($k)) { $st[$k] = '' } }
    foreach ($k in @('actions', 'warnings')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = @() } else { $st[$k] = @($st[$k]) } }
    if (-not $st.Contains('inputs') -or $null -eq $st['inputs']) { throw 'This step expects the output of the Read inputs step.' }
    return $st
}
function Stop-SgRun {
    param($St, [string]$Msg)
    $St['status'] = 'error'; $St['message'] = $Msg; $St['internal_note'] = "Inactive account review stopped: $Msg"
    Set-NodeOutput $St
    throw $Msg
}
function ConvertTo-SgDate {
    param($v)
    if ($null -eq $v) { return $null }
    if ($v -is [datetime]) { if ($v.Kind -eq [DateTimeKind]::Unspecified) { return [datetime]::SpecifyKind($v, [DateTimeKind]::Utc) }; return $v.ToUniversalTime() }
    $t = [string]$v; if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    $d = [datetime]::MinValue
    if ([datetime]::TryParse($t, [Globalization.CultureInfo]::InvariantCulture, ([Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal), [ref]$d)) { return $d }
    return $null
}

$sg = Read-SgState
$opt = $sg['inputs']
$days = [int](Get-GraphProp $opt 'days')
$includeGuests = [bool](Get-GraphProp $opt 'include_guests')

try { $conn = Connect-Graph } catch { Stop-SgRun $sg "Couldn't sign in to Microsoft 365: $($_.Exception.Message) Nothing was changed." }
$tenantWanted = [string](Get-GraphProp $opt 'tenant_id')
if ($tenantWanted -and $tenantWanted -ne ([string]$conn.TenantId).ToLowerInvariant()) {
    $sg['status'] = 'rejected'; $sg['message'] = 'The run asked for a different Microsoft 365 tenant than the one this runner is set up for, so nothing was read or changed.'
    $sg['internal_note'] = "Inactive account review rejected: tenant_id $tenantWanted is not this runner's tenant."
    Set-NodeOutput $sg
    throw $sg['message']
}

# 1. Users with sign-in activity. Graph caps the page at 120 when signInActivity is selected.
$sel = 'id,userPrincipalName,displayName,mail,accountEnabled,userType,createdDateTime,onPremisesSyncEnabled,signInActivity'
$users = @()
try { $users = @(Get-GraphAll -Path "/v1.0/users?`$select=$sel&`$top=120" -Permission 'AuditLog.Read.All') }
catch {
    $m = [string]$_.Exception.Message
    if ($m -match '\(403 Forbidden\)' -and $m -match '(?i)premium licen|AAD Premium|P1') { Stop-SgRun $sg "Can't read last sign-in times because this Microsoft 365 tenant doesn't have Entra ID P1 (included in Microsoft 365 Business Premium and E3/E5). Nothing was changed." }
    if ($m -match '\(403 Forbidden\)') { Stop-SgRun $sg "Can't read last sign-in times. The app registration needs the AuditLog.Read.All application permission (with User.Read.All), with admin consent. Nothing was changed." }
    Stop-SgRun $sg "Couldn't read the Microsoft 365 user list: $m Nothing was changed."
}

# 2. Who holds a directory admin role (active assignments, including through role-assignable groups).
$admins = @{}
try {
    $roles = @(Get-GraphAll -Path "/v1.0/directoryRoles?`$select=id,displayName&`$expand=members" -Permission 'RoleManagement.Read.Directory')
    foreach ($r in $roles) {
        $roleName = [string](Get-GraphProp $r 'displayName')
        foreach ($mbr in @(Get-GraphProp $r 'members')) {
            if ($null -eq $mbr) { continue }
            $ids = @([string](Get-GraphProp $mbr 'id'))
            if ([string](Get-GraphProp $mbr '@odata.type') -match 'group$') {
                $ids = @(Get-GraphAll -Path "/v1.0/groups/$(Get-GraphProp $mbr 'id')/transitiveMembers?`$select=id" -Permission 'GroupMember.Read.All' | ForEach-Object { [string](Get-GraphProp $_ 'id') })
            }
            foreach ($i in $ids) { if (-not $i) { continue }; if (-not $admins.ContainsKey($i)) { $admins[$i] = @() }; if ($admins[$i] -notcontains $roleName) { $admins[$i] += $roleName } }
        }
    }
}
catch {
    $m = [string]$_.Exception.Message
    if ($m -match 'GroupMember\.Read\.All' -and $m -match '\(403 Forbidden\)') { Stop-SgRun $sg "Can't see who holds an admin role through a group. The app registration needs the GroupMember.Read.All application permission, with admin consent. Nothing was changed." }
    if ($m -match '\(403 Forbidden\)') { Stop-SgRun $sg "Can't check who holds an admin role. The app registration needs the RoleManagement.Read.Directory application permission, with admin consent. Nothing was changed." }
    Stop-SgRun $sg "Couldn't read the admin roles: $m Nothing was changed."
}

# 3. Sort every account into skipped or listed.
$now = (Get-Date).ToUniversalTime()
$cutoff = $now.AddDays(-$days)
$counts = [ordered]@{ users_read = $users.Count; members_reviewed = 0; guests_reviewed = 0; skipped_disabled = 0; skipped_new = 0; skipped_guests = 0; inactive_members = 0; inactive_guests = 0; flagged_admin = 0; flagged_synced = 0; can_disable = 0 }
$rows = New-Object System.Collections.ArrayList
foreach ($u in $users) {
    if ($null -eq $u) { continue }
    $isGuest = ([string](Get-GraphProp $u 'userType')) -ieq 'Guest'
    if ($isGuest -and -not $includeGuests) { $counts.skipped_guests++; continue }
    if ((Get-GraphProp $u 'accountEnabled') -eq $false) { $counts.skipped_disabled++; continue }
    if ($isGuest) { $counts.guests_reviewed++ } else { $counts.members_reviewed++ }
    $created = ConvertTo-SgDate (Get-GraphProp $u 'createdDateTime')
    if ($null -ne $created -and $created -gt $cutoff) { $counts.skipped_new++; continue }
    $sia = Get-GraphProp $u 'signInActivity'
    $last = $null
    foreach ($f in @('lastSignInDateTime', 'lastNonInteractiveSignInDateTime', 'lastSuccessfulSignInDateTime')) {
        $d = ConvertTo-SgDate (Get-GraphProp $sia $f)
        if ($null -ne $d -and ($null -eq $last -or $d -gt $last)) { $last = $d }
    }
    if ($null -ne $last -and $last -gt $cutoff) { continue }

    $id = [string](Get-GraphProp $u 'id')
    $flag = ''; $why = ''; $roleText = ''
    if ($admins.ContainsKey($id)) { $flag = 'admin'; $roleText = (@($admins[$id]) -join ', '); $why = "Holds an admin role ($roleText). Review manually; this workflow never disables admins." }
    elseif ((Get-GraphProp $u 'onPremisesSyncEnabled') -eq $true) { $flag = 'synced'; $why = 'Synced from on-premises Active Directory. Disable it there; a change made in Microsoft 365 would not stick.' }
    $row = [ordered]@{
        id            = $id
        upn           = [string](Get-GraphProp $u 'userPrincipalName')
        name          = [string](Get-GraphProp $u 'displayName')
        kind          = $(if ($isGuest) { 'guest' } else { 'member' })
        last_sign_in  = $(if ($null -ne $last) { $last.ToString('yyyy-MM-dd') } else { '' })
        never_signed_in = ($null -eq $last)
        days_inactive = $(if ($null -ne $last) { [int][Math]::Floor(($now - $last).TotalDays) } elseif ($null -ne $created) { [int][Math]::Floor(($now - $created).TotalDays) } else { -1 })
        created       = $(if ($null -ne $created) { $created.ToString('yyyy-MM-dd') } else { '' })
        flag          = $flag
        roles         = $roleText
        note          = $why
        can_disable   = ($flag -eq '')
    }
    $null = $rows.Add($row)
    if ($isGuest) { $counts.inactive_guests++ } else { $counts.inactive_members++ }
    if ($flag -eq 'admin') { $counts.flagged_admin++ } elseif ($flag -eq 'synced') { $counts.flagged_synced++ } else { $counts.can_disable++ }
}
# Never-signed-in first, then the longest inactive.
$sorted = @($rows | Sort-Object -Property @{ Expression = { [bool]$_.never_signed_in }; Descending = $true }, @{ Expression = { [int]$_.days_inactive }; Descending = $true }, @{ Expression = { [string]$_.upn } })

$sg['tenant_id'] = [string]$conn.TenantId
$sg['checked_at'] = $now.ToString('yyyy-MM-dd HH:mm') + ' UTC'
$sg['counts'] = $counts
$sg['candidates'] = @($sorted)
$listed = $counts.inactive_members + $counts.inactive_guests
$sg['actions'] = @(@($sg['actions']) + "Checked $($users.Count) Microsoft 365 accounts for sign-ins in the last $days days: $listed inactive ($($counts.inactive_members) members, $($counts.inactive_guests) guests).")
Set-NodeOutput $sg
