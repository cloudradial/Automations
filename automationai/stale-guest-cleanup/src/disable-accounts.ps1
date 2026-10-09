# === NODE: Disable confirmed accounts ===
# Only accounts named in disable_ids that are ALSO on this run's fresh inactive list (and not flagged as
# admin or synced) are planned. Ids from an earlier run are never trusted on their own.
# confirm false: nothing changes, the plan is only previewed. confirm true: for each account, turn off
# sign-in, then sign it out of every session. The plan stops at the first failure and says what didn't run.
$ErrorActionPreference = 'Stop'
function Read-SgState {
    $raw = Get-NodeInput
    if ($null -ne $raw -and $null -eq (Get-GraphProp $raw 'inputs') -and $null -ne (Get-GraphProp $raw 'output')) { $raw = Get-GraphProp $raw 'output' }
    $st = [ordered]@{}
    if ($raw -is [System.Collections.IDictionary]) { foreach ($k in $raw.Keys) { $st[[string]$k] = $raw[$k] } }
    elseif ($null -ne $raw) { foreach ($p in $raw.PSObject.Properties) { $st[$p.Name] = $p.Value } }
    foreach ($k in @('status', 'message', 'public_note', 'internal_note', 'ticket_id')) { if (-not $st.Contains($k)) { $st[$k] = '' } }
    foreach ($k in @('actions', 'warnings', 'candidates')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = @() } else { $st[$k] = @($st[$k]) } }
    if (-not $st.Contains('inputs') -or $null -eq $st['inputs']) { throw 'This step expects the output of the Find inactive accounts step.' }
    return $st
}

$sg = Read-SgState
$opt = $sg['inputs']
$confirm = [bool](Get-GraphProp $opt 'confirm')
$wanted = @(@(Get-GraphProp $opt 'disable_ids') | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
$candidates = @($sg['candidates'] | Where-Object { $null -ne $_ })

$targets = New-Object System.Collections.ArrayList
$skipped = New-Object System.Collections.ArrayList
foreach ($w in $wanted) {
    $hit = @($candidates | Where-Object { ([string](Get-GraphProp $_ 'id')).ToLowerInvariant() -eq $w -or ([string](Get-GraphProp $_ 'upn')).ToLowerInvariant() -eq $w }) | Select-Object -First 1
    if ($null -eq $hit) { $null = $skipped.Add([ordered]@{ requested = $w; reason = 'Not on this run''s inactive list (it signed in recently, is already disabled, is too new, is a guest while guests were excluded, or does not exist).' }); continue }
    if (-not [bool](Get-GraphProp $hit 'can_disable')) { $null = $skipped.Add([ordered]@{ requested = $w; reason = [string](Get-GraphProp $hit 'note') }); continue }
    if (@($targets | Where-Object { $_.id -eq [string](Get-GraphProp $hit 'id') }).Count) { continue }
    $null = $targets.Add([ordered]@{ id = [string](Get-GraphProp $hit 'id'); upn = [string](Get-GraphProp $hit 'upn'); kind = [string](Get-GraphProp $hit 'kind') })
}

$changePlan = New-ChangePlan 'Disable inactive Microsoft 365 accounts'
foreach ($t in $targets) {
    Add-PlannedChange $changePlan "Turn off sign-in for $($t.upn)" { param($uid) Set-GraphAccountEnabled -UserId $uid -Enabled $false } -Arguments @($t.id)
    Add-PlannedChange $changePlan "Sign $($t.upn) out of every session" { param($uid) Revoke-GraphSessions -UserId $uid } -Arguments @($t.id)
}
if ($confirm -and $targets.Count) { $null = Connect-Graph }
$result = Invoke-ChangePlan $changePlan -Confirm $confirm

# Which accounts ended up disabled (sign-in turned off), whatever happened to the session revoke.
$disabled = @()
foreach ($t in $targets) { if (@(@($result.ran) | Where-Object { $_.description -eq "Turn off sign-in for $($t.upn)" }).Count) { $disabled += $t.upn } }

$sg['disable'] = [ordered]@{
    requested = @($wanted)
    planned   = @($targets | ForEach-Object { $_.upn })
    skipped   = @($skipped)
    disabled  = @($disabled)
    result    = $result
}
if ($confirm) {
    if ($disabled.Count) { $sg['actions'] = @(@($sg['actions']) + "Turned off sign-in and ended sessions for: $($disabled -join ', ').") }
    if ($null -ne $result.failed) { $sg['warnings'] = @(@($sg['warnings']) + "A change failed: $($result.failed.description): $($result.failed.error)") }
}
Set-NodeOutput $sg
