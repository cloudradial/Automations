# === NODE: Find risky users (read-only) ===
# Reads the users Microsoft Entra ID Protection has at risk now (riskState atRisk) at min_risk or above
# (needs IdentityRiskyUser.Read.All and Entra ID P2), their recent risk detections for the internal note
# (needs IdentityRiskEvent.Read.All), their account details and manager (User.Read.All), and who holds a
# directory admin role (RoleManagement.Read.Directory). Changes nothing.
# A missing licence or permission for the risk data stops the run with a plain sentence naming it.
# A missing role-read permission only warns: those users are still ticketed, at high priority.
$ErrorActionPreference = 'Stop'
function Get-RsProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Read-RsState {
    param([string]$Needs, [string]$From)
    $raw = Get-NodeInput
    if ($null -ne $raw -and $null -eq (Get-RsProp $raw 'inputs') -and $null -ne (Get-RsProp $raw 'output')) { $raw = Get-RsProp $raw 'output' }
    $st = [ordered]@{}
    if ($raw -is [System.Collections.IDictionary]) { foreach ($k in $raw.Keys) { $st[[string]$k] = $raw[$k] } }
    elseif ($null -ne $raw) { foreach ($p in $raw.PSObject.Properties) { $st[$p.Name] = $p.Value } }
    foreach ($k in @('status', 'message', 'public_note', 'internal_note', 'ticket_id', 'tenant_id', 'checked_at')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = '' } }
    foreach ($k in @('actions', 'warnings', 'risky')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = @() } else { $st[$k] = @($st[$k]) } }
    if (-not $st.Contains('inputs') -or $null -eq $st['inputs'] -or ($Needs -and -not $st.Contains($Needs))) { throw "This step expects the output of the $From step." }
    return $st
}
function Stop-RsRun {
    param($St, [string]$Msg, [string]$Status = 'error')
    $St['status'] = $Status; $St['message'] = $Msg; $St['internal_note'] = "Risky sign-in response stopped: $Msg"
    Set-NodeOutput $St
    throw $Msg
}
function ConvertTo-RsIso {
    param($v)
    if ($null -eq $v) { return '' }
    if ($v -is [datetime]) { $d = $v; if ($d.Kind -eq [DateTimeKind]::Unspecified) { $d = [datetime]::SpecifyKind($d, [DateTimeKind]::Utc) }; return $d.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    $t = [string]$v; if ([string]::IsNullOrWhiteSpace($t)) { return '' }
    $d = [datetime]::MinValue
    if ([datetime]::TryParse($t, [Globalization.CultureInfo]::InvariantCulture, ([Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal), [ref]$d)) { return $d.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    return $t
}
# Plain names for Identity Protection detection types; anything else is shown as Microsoft names it.
$RsLabels = @{
    unfamiliarFeatures = 'Unfamiliar sign-in properties'; anonymizedIPAddress = 'Sign-in from an anonymous IP address'; maliciousIPAddress = 'Sign-in from a malicious IP address'
    unlikelyTravel = 'Atypical travel'; impossibleTravel = 'Impossible travel'; leakedCredentials = 'Leaked credentials'; passwordSpray = 'Password spray'
    investigationsThreatIntelligence = 'Microsoft threat intelligence'; adminConfirmedUserCompromised = 'Admin confirmed the user compromised'; newCountry = 'Sign-in from a new country'
    suspiciousInboxForwarding = 'Suspicious inbox forwarding'; mcasSuspiciousInboxManipulationRules = 'Suspicious inbox manipulation rules'; anomalousToken = 'Anomalous token'
    tokenIssuerAnomaly = 'Token issuer anomaly'; suspiciousBrowser = 'Suspicious browser'; malwareInfectedIPAddress = 'Sign-in from a malware-linked IP address'
    attackerinTheMiddle = 'Attacker in the middle'; suspiciousAPITraffic = 'Suspicious API traffic'; mfaFraud = 'User reported MFA fraud'; suspiciousSendingPatterns = 'Suspicious sending patterns'
    anomalousUserActivity = 'Anomalous user activity'; generic = 'Additional risk detected'
}

$rs = Read-RsState '' 'Read inputs'
$opt = $rs['inputs']
$levels = @('high'); if ([string](Get-RsProp $opt 'min_risk') -eq 'medium') { $levels = @('high', 'medium') }
$lookback = [int](Get-RsProp $opt 'lookback_days')

try { $conn = Connect-Graph } catch { Stop-RsRun $rs "Couldn't sign in to Microsoft 365: $($_.Exception.Message) Nothing was changed." }
$rs['tenant_id'] = [string]$conn.TenantId
$tenantWanted = [string](Get-RsProp $opt 'tenant_id')
if ($tenantWanted -and $tenantWanted -ne ([string]$conn.TenantId).ToLowerInvariant()) {
    Stop-RsRun $rs 'The run asked for a different Microsoft 365 tenant than the one this runner is set up for, so nothing was read or changed.' 'rejected'
}
$rs['checked_at'] = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC'

# 1. Users at risk now.
$all = @()
try { $all = @(Get-GraphRiskyUsers -AtRiskOnly) }
catch {
    $m = [string]$_.Exception.Message
    if ($m -match '(?i)licen[cs]|premium|\bP2\b') { Stop-RsRun $rs "Can't read risky users because this Microsoft 365 tenant doesn't have Microsoft Entra ID P2 (included in Microsoft 365 E5 and Entra ID Governance). Nothing was changed." }
    if ($m -match '\(403 Forbidden\)') { Stop-RsRun $rs "Can't read risky users. The app registration needs the IdentityRiskyUser.Read.All application permission, with admin consent. Nothing was changed." }
    Stop-RsRun $rs "Couldn't read risky users from Microsoft Entra ID Protection: $m Nothing was changed."
}
$atRisk = @($all | Where-Object {
        $null -ne $_ -and [string](Get-RsProp $_ 'riskState') -eq 'atRisk' -and $levels -contains ([string](Get-RsProp $_ 'riskLevel')).ToLowerInvariant() -and (Get-RsProp $_ 'isDeleted') -ne $true
    })
$rs['counts'] = [ordered]@{ at_risk_any_level = @($all | Where-Object { $null -ne $_ }).Count; at_risk_in_scope = $atRisk.Count }

# 2. Who holds a directory admin role. Only read when someone is at risk.
$admins = @{}
$adminKnown = $true
if ($atRisk.Count) {
    try {
        foreach ($r in @(Get-GraphAll -Path "/v1.0/directoryRoles?`$select=id,displayName&`$expand=members" -Permission 'RoleManagement.Read.Directory')) {
            $roleName = [string](Get-RsProp $r 'displayName')
            foreach ($mbr in @(Get-RsProp $r 'members')) {
                if ($null -eq $mbr) { continue }
                $ids = @([string](Get-RsProp $mbr 'id'))
                if ([string](Get-RsProp $mbr '@odata.type') -match 'group$') { $ids = @(Get-GraphAll -Path "/v1.0/groups/$(Get-RsProp $mbr 'id')/transitiveMembers?`$select=id" -Permission 'GroupMember.Read.All' | ForEach-Object { [string](Get-RsProp $_ 'id') }) }
                foreach ($i in $ids) { if (-not $i) { continue }; if (-not $admins.ContainsKey($i)) { $admins[$i] = @() }; if ($admins[$i] -notcontains $roleName) { $admins[$i] += $roleName } }
            }
        }
    }
    catch {
        $adminKnown = $false
        $m = [string]$_.Exception.Message
        $perm = if ($m -match 'GroupMember\.Read\.All') { 'GroupMember.Read.All' } else { 'RoleManagement.Read.Directory' }
        $rs['warnings'] = @(@($rs['warnings']) + $(if ($m -match '\(403 Forbidden\)') { "Couldn't check which risky users hold an admin role, so none is marked critical. The app registration needs the $perm application permission, with admin consent." } else { "Couldn't check which risky users hold an admin role, so none is marked critical: $m" }))
    }
}

# 3. Each risky user's account, manager and recent detections.
$since = (Get-Date).ToUniversalTime().AddDays(-$lookback).ToString('yyyy-MM-ddTHH:mm:ssZ')
$rows = New-Object System.Collections.ArrayList
foreach ($ru in $atRisk) {
    $id = [string](Get-RsProp $ru 'id')
    $upn = [string](Get-RsProp $ru 'userPrincipalName')
    $u = $null
    try { $u = Get-GraphUser -Id $id -Select 'id,userPrincipalName,displayName,mail,accountEnabled,onPremisesSyncEnabled' }
    catch { if ($_.Exception.Message -match '\(403 Forbidden\)') { Stop-RsRun $rs "Can't read the risky users' accounts. The app registration needs the User.Read.All application permission, with admin consent. Nothing was changed." }; throw }
    if ($null -eq $u) { $rs['warnings'] = @(@($rs['warnings']) + "Risky user $upn no longer exists in the directory, so it was skipped."); continue }
    if (Get-RsProp $u 'userPrincipalName') { $upn = [string](Get-RsProp $u 'userPrincipalName') }

    $mgr = $null
    try {
        $mr = Invoke-Graph -Method GET -Path "/v1.0/users/$id/manager?`$select=id,displayName,mail,userPrincipalName" -Permission 'User.Read.All'
        if ($null -ne $mr) { $mgr = [ordered]@{ id = [string](Get-RsProp $mr 'id'); name = [string](Get-RsProp $mr 'displayName'); mail = [string](Get-RsProp $mr 'mail'); upn = [string](Get-RsProp $mr 'userPrincipalName') } }
    }
    catch { if ($GraphState.LastStatus -ne 404) { $rs['warnings'] = @(@($rs['warnings']) + "Couldn't read the manager of $($upn): $($_.Exception.Message)") } }

    $dets = @()
    try {
        $f = [uri]::EscapeDataString("userId eq '$id' and detectedDateTime ge $since")
        $dets = @(Get-GraphAll -Path "/v1.0/identityProtection/riskDetections?`$filter=$f&`$top=50" -Permission 'IdentityRiskEvent.Read.All' -MaxPages 2)
    }
    catch {
        $m = [string]$_.Exception.Message
        if ($m -match '(?i)licen[cs]|premium|\bP2\b') { Stop-RsRun $rs "Can't read risk detections because this Microsoft 365 tenant doesn't have Microsoft Entra ID P2. Nothing was changed." }
        if ($m -match '\(403 Forbidden\)') { Stop-RsRun $rs "Can't read the risk detections. The app registration needs the IdentityRiskEvent.Read.All application permission, with admin consent. Nothing was changed." }
        Stop-RsRun $rs "Couldn't read the risk detections for $($upn): $m Nothing was changed."
    }
    $detail = @($dets | Where-Object { $null -ne $_ } | ForEach-Object {
            $loc = Get-RsProp $_ 'location'
            $place = @(@((Get-RsProp $loc 'city'), (Get-RsProp $loc 'state'), (Get-RsProp $loc 'countryOrRegion')) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ', '
            $type = [string](Get-RsProp $_ 'riskEventType')
            [ordered]@{
                id       = [string](Get-RsProp $_ 'id')
                type     = $type
                label    = $(if ($RsLabels.ContainsKey($type)) { $RsLabels[$type] } else { $type })
                level    = [string](Get-RsProp $_ 'riskLevel')
                detected = (ConvertTo-RsIso (Get-RsProp $_ 'detectedDateTime'))
                activity = (ConvertTo-RsIso (Get-RsProp $_ 'activityDateTime'))
                ip       = [string](Get-RsProp $_ 'ipAddress')
                location = $place
                timing   = [string](Get-RsProp $_ 'detectionTimingType')
                source   = [string](Get-RsProp $_ 'source')
            }
        } | Sort-Object { $_.detected } -Descending)

    $roles = @(); if ($admins.ContainsKey($id)) { $roles = @($admins[$id]) }
    $null = $rows.Add([ordered]@{
            id           = $id
            upn          = $upn
            name         = $(if (Get-RsProp $u 'displayName') { [string](Get-RsProp $u 'displayName') } else { [string](Get-RsProp $ru 'userDisplayName') })
            enabled      = ((Get-RsProp $u 'accountEnabled') -ne $false)
            synced       = ((Get-RsProp $u 'onPremisesSyncEnabled') -eq $true)
            risk_level   = [string](Get-RsProp $ru 'riskLevel')
            risk_state   = [string](Get-RsProp $ru 'riskState')
            risk_detail  = [string](Get-RsProp $ru 'riskDetail')
            risk_updated = (ConvertTo-RsIso (Get-RsProp $ru 'riskLastUpdatedDateTime'))
            admin_roles  = @($roles)
            is_admin     = ($roles.Count -gt 0)
            admin_known  = $adminKnown
            manager      = $mgr
            detections   = @($detail)
        })
}

$rs['risky'] = @($rows)
Set-NodeOutput $rs
