# === NODE: Block confirmed accounts ===
# Only runs when block_upns is given. Each requested account is checked again now: it is planned only if
# Microsoft Entra ID Protection still has it at risk (riskState atRisk, any level), it is still turned on,
# and it isn't synced from on-premises (block those in Active Directory). Names from an earlier run are
# never trusted on their own.
# confirm false: nothing changes, the plan is only previewed. confirm true: for each account, turn off
# sign-in, then sign it out of every session. The plan stops at the first failure and says what didn't run.
# A blocked account's open "[Risky sign-in]" ticket gets an internal note, marked "risky-signin-block:
# <ticket id> <date>" so a retried run never adds it twice. The risk is never dismissed here.
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
    foreach ($k in @('actions', 'warnings', 'risky', 'responses')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = @() } else { $st[$k] = @($st[$k]) } }
    if (-not $st.Contains('inputs') -or $null -eq $st['inputs'] -or ($Needs -and -not $st.Contains($Needs))) { throw "This step expects the output of the $From step." }
    return $st
}
function Stop-RsRun {
    param($St, [string]$Msg, [string]$Status = 'error')
    $St['status'] = $Status; $St['message'] = $Msg; $St['internal_note'] = "Risky sign-in response stopped: $Msg"
    Set-NodeOutput $St
    throw $Msg
}

$rs = Read-RsState 'responses' 'Respond to new risky users'
$opt = $rs['inputs']
$confirm = [bool](Get-RsProp $opt 'confirm')
$wanted = @(@(Get-RsProp $opt 'block_upns') | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })

$targets = New-Object System.Collections.ArrayList
$skipped = New-Object System.Collections.ArrayList
$result = $null
if ($wanted.Count) {
    if ($null -eq $GraphState.Creds) { $null = Connect-Graph }
    foreach ($w in $wanted) {
        $u = $null
        try { $u = Get-GraphUser -Id $w -Select 'id,userPrincipalName,accountEnabled,onPremisesSyncEnabled' }
        catch { if ($_.Exception.Message -match '\(403 Forbidden\)') { Stop-RsRun $rs "Can't read the accounts to block. The app registration needs the User.Read.All application permission, with admin consent. Nothing was blocked." }; throw }
        if ($null -eq $u) { $null = $skipped.Add([ordered]@{ requested = $w; reason = 'No such user in this Microsoft 365 tenant.' }); continue }
        $id = [string](Get-RsProp $u 'id'); $upn = [string](Get-RsProp $u 'userPrincipalName')
        if (@($targets | Where-Object { $_.id -eq $id }).Count) { continue }
        $ru = $null
        try { $ru = Get-GraphRiskyUsers -UserId $id }
        catch {
            $m = [string]$_.Exception.Message
            if ($m -match '\(403 Forbidden\)') { Stop-RsRun $rs "Can't check whether the accounts are still at risk. The app registration needs the IdentityRiskyUser.Read.All application permission, with admin consent. Nothing was blocked." }
            throw
        }
        $state = [string](Get-RsProp $ru 'riskState')
        if ($state -ne 'atRisk') { $null = $skipped.Add([ordered]@{ requested = $w; reason = "Not at risk now (Microsoft shows $(if ($state) { $state } else { 'no risk' })), so it was not blocked." }); continue }
        if ((Get-RsProp $u 'accountEnabled') -eq $false) { $null = $skipped.Add([ordered]@{ requested = $w; reason = 'Sign-in is already turned off.' }); continue }
        if ((Get-RsProp $u 'onPremisesSyncEnabled') -eq $true) { $null = $skipped.Add([ordered]@{ requested = $w; reason = 'Synced from on-premises Active Directory. Disable it there; a change made in Microsoft 365 would not stick.' }); continue }
        $null = $targets.Add([ordered]@{ id = $id; upn = $upn; level = [string](Get-RsProp $ru 'riskLevel') })
    }
    $changePlan = New-ChangePlan 'Block risky Microsoft 365 accounts'
    foreach ($t in $targets) {
        Add-PlannedChange $changePlan "Turn off sign-in for $($t.upn)" { param($uid) Set-GraphAccountEnabled -UserId $uid -Enabled $false } -Arguments @($t.id)
        Add-PlannedChange $changePlan "Sign $($t.upn) out of every session" { param($uid) Revoke-GraphSessions -UserId $uid } -Arguments @($t.id)
    }
    $result = Invoke-ChangePlan $changePlan -Confirm $confirm
}

$blocked = @()
foreach ($t in $targets) { if ($null -ne $result -and @(@($result.ran) | Where-Object { $_.description -eq "Turn off sign-in for $($t.upn)" }).Count) { $blocked += $t.upn } }

# Note on each blocked account's ticket (this run's, or the open one found by the previous step).
if ($blocked.Count) {
    $rs['actions'] = @(@($rs['actions']) + "Turned off sign-in and ended sessions for: $($blocked -join ', ').")
    $psaOk = $false
    try { if ($null -eq $PsaState.Conn) { $null = Connect-Psa -Psa (Get-PsaType ([string](Get-RsProp $opt 'psa'))) }; $psaOk = $true }
    catch { $rs['warnings'] = @(@($rs['warnings']) + "Couldn't connect to the PSA to note the blocks: $($_.Exception.Message)") }
    foreach ($b in $blocked) {
        $resp = @($rs['responses'] | Where-Object { ([string](Get-RsProp $_ 'upn')).ToLowerInvariant() -eq $b.ToLowerInvariant() -and [string](Get-RsProp $_ 'ticket_id') }) | Select-Object -First 1
        if ($null -eq $resp) { $rs['warnings'] = @(@($rs['warnings']) + "No open risky sign-in ticket was found for $b on this run, so the block wasn't noted on a ticket."); continue }
        if (-not $psaOk) { continue }
        $tid = [string](Get-RsProp $resp 'ticket_id')
        $now = (Get-Date).ToUniversalTime()
        try {
            $w = Add-PsaNote -Id $tid -Text "A technician confirmed blocking $b. The automation turned off sign-in and signed the account out of every session at $($now.ToString('yyyy-MM-dd HH:mm')) UTC. Turn sign-in back on in Microsoft 365 once the account is safe, and dismiss the risk in Entra ID Protection." -Title 'Account blocked' -Marker "risky-signin-block: $tid $($now.ToString('yyyy-MM-dd'))"
            $rs['actions'] = @(@($rs['actions']) + $(if ($w -eq 'already-present') { "The block of $b was already noted on ticket $tid today, so it was not noted again." } else { "Noted the block of $b on ticket $tid." }))
        }
        catch { $rs['warnings'] = @(@($rs['warnings']) + "Couldn't note the block on ticket $($tid): $($_.Exception.Message)") }
    }
}
if ($null -ne $result -and $confirm -and $null -ne $result.failed) { $rs['warnings'] = @(@($rs['warnings']) + "A block failed: $($result.failed.description): $($result.failed.error)") }

$rs['block'] = [ordered]@{
    requested = @($wanted)
    planned   = @($targets | ForEach-Object { $_.upn })
    skipped   = @($skipped)
    blocked   = @($blocked)
    result    = $result
}
Set-NodeOutput $rs
