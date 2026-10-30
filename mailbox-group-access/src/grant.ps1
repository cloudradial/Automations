# Step 2: give the access, only when confirm is true and the request is approved, then read it back.
# - The Read step stopped (refused, incomplete, error): passed on unchanged.
# - The user already has the access: success, nothing changed.
# - confirm false: nothing changed (pending_confirmation), with the plan and who must approve.
# - Not approved, or a person's own mailbox without a technician's approvedBy: nothing changed (pending_approval).
# - Otherwise: one change through Microsoft Graph (Microsoft 365 and security groups, Teams) or Exchange Online
#   (mailbox permissions, distribution lists, mail-enabled security groups, send-as), then a read-back.
#   When Exchange Online can't be reached, nothing changes and the exact command goes to the technician.
# Writes nothing to the ticket; the Note step does that.
function Get-AccParam {
    param([string]$n)
    # A bound parameter may arrive as a variable, as a property of the node input, or as the whole node input.
    $v = Get-Variable -Name $n -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $v) { $all = $null; try { $all = ConvertFrom-AccMaybeJson (Get-NodeInput) } catch { }; $v = Get-OfProp $all $n; if ($null -eq $v -and $null -ne (Get-OfProp $all 'access_type')) { $v = $all } }
    return (ConvertFrom-AccMaybeJson $v)
}

$prep = Get-AccParam 'prep'
$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
foreach ($w in @(Get-OfProp $prep 'warnings')) { if ($w) { $null = $warnings.Add([string]$w) } }
foreach ($a in @(Get-OfProp $prep 'actions')) { if ($a) { $null = $actions.Add([string]$a) } }
$out = [ordered]@{ status = 'error'; message = ''; granted = $false; verified = $false; warnings = @(); actions = @() }
# Everything the Read step worked out travels on to the Note step.
foreach ($k in @('ticket_id', 'psa', 'confirm', 'close_ticket', 'target', 'resource', 'access_type', 'requester', 'approved_by', 'already_has_access', 'approvers', 'approved', 'approval', 'needs_technician', 'change', 'manual_command', 'exchange_unreachable')) { $out[$k] = Get-OfProp $prep $k }
foreach ($k in @('approvers')) { $out[$k] = @(@($out[$k]) | Where-Object { $null -ne $_ }) }
function Complete-AccGrant {
    param([string]$Status, [string]$Msg)
    $out.status = $Status; $out.message = $Msg
    $out.warnings = @($warnings); $out.actions = @($actions)
    Set-NodeOutput $out
}

if ($null -eq $prep) { Complete-AccGrant 'error' 'The Grant step got no output from the Read step. Nothing was changed.'; return }
$prepStatus = [string](Get-OfProp $prep 'status')
if ($prepStatus -ne 'ok') { Complete-AccGrant $(if ($prepStatus) { $prepStatus } else { 'error' }) ([string](Get-OfProp $prep 'message')); return }

$target = Get-OfProp $prep 'target'; $resource = Get-OfProp $prep 'resource'; $change = Get-OfProp $prep 'change'
$accessType = [string](Get-OfProp $prep 'access_type')
$tn = [string](Get-OfProp $target 'name'); $rl = [string](Get-OfProp $resource 'label'); $rn = [string](Get-OfProp $resource 'name')
$desc = [string](Get-OfProp $change 'description')
$approvers = @($out.approvers)
$whoText = $(if ($approvers.Count) { (@($approvers | ForEach-Object { "$(Get-OfProp $_ 'name') ($(Get-OfProp $_ 'mail')), $(Get-OfProp $_ 'role')" }) -join '; or ') } else { 'nobody yet (see the warnings)' })
$ask = "$tn getting $($AccPhrase[$accessType]) the $rl $rn"

if (Test-AccTrue (Get-OfProp $prep 'already_has_access')) { Complete-AccGrant 'success' "$tn already has $($AccPhrase[$accessType]) the $rl $rn. Nothing needed to change."; return }
$approved = Test-AccTrue (Get-OfProp $prep 'approved')
$tech = Test-AccTrue (Get-OfProp $prep 'needs_technician')
if (-not (Test-AccTrue (Get-OfProp $prep 'confirm'))) {
    $more = $(if ($approved) { " $($out.approval)" } elseif ($tech) { " Because it is a person's own mailbox, a technician must run it with approvedBy set to one of: $whoText." } else { " It also needs approval from: $whoText." })
    Complete-AccGrant 'pending_confirmation' "Planned: $desc. Nothing was changed; run again with confirm set to true to go ahead.$more"
    return
}
if (-not $approved) {
    if ($tech) { Complete-AccGrant 'pending_approval' "$ask needs a technician, because it is a person's own mailbox. Nothing was changed. Run it again with approvedBy set to one of: $whoText, and confirm set to true."; return }
    Complete-AccGrant 'pending_approval' "$ask needs approval first. Nothing was changed. It can be approved by: $whoText. Run it again with approvedBy set to the approver's email address and confirm set to true."
    return
}

# ---------- grant ----------
$method = [string](Get-OfProp $change 'method')
try {
    if ($method -eq 'graph') {
        $null = Connect-Graph
        try {
            $null = Invoke-Graph -Method POST -Path ([string](Get-OfProp $change 'path')) -Body @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$(Get-OfProp $target 'id')" } -Permission ([string](Get-OfProp $change 'permission'))
            $null = $actions.Add("$desc (Microsoft Graph)")
        }
        catch { if ($GraphState.LastStatus -eq 400 -and $_.Exception.Message -match '(?i)already exist') { $null = $actions.Add("$tn was already there, so Microsoft Graph had nothing to add") } else { throw } }
    }
    else {
        if (-not (Connect-OfExchange -Organization ([string](Get-OfProp $prep 'exchange_org')))) {
            $out.exchange_unreachable = $true
            Complete-AccGrant 'incomplete' "Exchange Online couldn't be reached, so nothing was changed: $($OfExo.Reason.TrimEnd('.')). A technician can run the command in the internal note."
            return
        }
        $params = @{}
        $p = Get-OfProp $change 'parameters'
        if ($p -is [System.Collections.IDictionary]) { foreach ($k in $p.Keys) { $params[[string]$k] = $p[$k] } } else { foreach ($pp in $p.PSObject.Properties) { $params[$pp.Name] = $pp.Value } }
        # After the JSON hop between steps, nested values are objects and arrays; Exchange wants hashtables and string arrays.
        foreach ($k in @($params.Keys)) {
            $v = $params[$k]
            if ($v -is [System.Management.Automation.PSCustomObject]) { $h = @{}; foreach ($pp in $v.PSObject.Properties) { $h[$pp.Name] = @(@($pp.Value) | ForEach-Object { [string]$_ }) }; $params[$k] = $h }
            elseif ($v -is [array]) { $params[$k] = [string[]]@($v | ForEach-Object { [string]$_ }) }
        }
        $cmdlet = [string](Get-OfProp $change 'cmdlet')
        try { $null = Invoke-OfExo $cmdlet $params; $null = $actions.Add("$desc (Exchange Online $cmdlet)") }
        catch { if ($_.Exception.Message -match '(?i)already (has|exists|a member)|is already') { $null = $actions.Add("Exchange Online said $tn already had it") } else { throw } }
    }
}
catch {
    Complete-AccGrant 'error' "Couldn't give the access ($desc): $($_.Exception.Message) Nothing else was changed. A technician can run the command in the internal note."
    return
}
$out.granted = $true

# ---------- read it back ----------
$seen = $false
try {
    if ($method -eq 'exchange' -or (Test-AccNeedsExchange $resource $accessType)) { $null = Connect-OfExchange -Organization ([string](Get-OfProp $prep 'exchange_org')) }
    for ($i = 1; $i -le 3; $i++) {
        if (Test-AccHasAccess $resource $target $accessType) { $seen = $true; break }
        if ($i -lt 3) { Start-Sleep -Seconds 10 }
    }
}
catch { $null = $warnings.Add("The change was sent, but reading it back failed: $($_.Exception.Message)") }
$out.verified = $seen
if (-not $seen) {
    Complete-AccGrant 'incomplete' "$desc was sent, but reading it back didn't show it yet. Check it in a few minutes; running this again will confirm it without changing anything twice."
    return
}
$null = $actions.Add('Read it back: the access is in place')
Complete-AccGrant 'success' "Done: $desc."
