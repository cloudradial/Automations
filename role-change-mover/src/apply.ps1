# Step 2: preview the plan, or apply it when confirm is true, then add an internal note to the ticket.
# Writes to Microsoft 365 only when confirm is true. Licences, distribution lists and other items Graph
# can't change are listed for a technician, never changed.
function ConvertFrom-RcMaybeJson { param($v) if ($v -is [string]) { $s = $v.Trim(); if ($s -match '^[\[{]') { try { return ($s | ConvertFrom-Json) } catch { } } }; return $v }
function Get-RcParam {
    param([string]$n)
    # A bound parameter may arrive as a variable, as a property of the node input, or as the whole node input.
    $v = Get-Variable -Name $n -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $v) { $all = $null; try { $all = ConvertFrom-RcMaybeJson (Get-NodeInput) } catch { }; $v = Get-PsaProp $all $n; if ($null -eq $v -and $null -ne (Get-PsaProp $all 'adds')) { $v = $all } }
    return (ConvertFrom-RcMaybeJson $v)
}
function Get-RcList { param($o, [string]$n) return @(@(Get-PsaProp $o $n) | Where-Object { $null -ne $_ }) }

$prep = Get-RcParam 'prep'
$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
foreach ($w in @(Get-PsaProp $prep 'warnings')) { if ($w) { $null = $warnings.Add([string]$w) } }
foreach ($a in @(Get-PsaProp $prep 'actions')) { if ($a) { $null = $actions.Add([string]$a) } }
$ticketId = [string](Get-PsaProp $prep 'ticket_id')
$confirm = (Get-PsaProp $prep 'confirm') -eq $true -or [string](Get-PsaProp $prep 'confirm') -match '^(?i)(true|yes|y|1)$'
$upn = [string](Get-PsaProp $prep 'upn')
$out = [ordered]@{
    status = 'error'; message = ''; public_note = ''; internal_note = ''; ticket_id = $ticketId
    actions = @(); warnings = @(); chatReply = ''
    confirm = $confirm; upn = $upn; user_id = [string](Get-PsaProp $prep 'user_id')
    old_department = [string](Get-PsaProp $prep 'old_department'); new_department = [string](Get-PsaProp $prep 'new_department')
    planned = @(); ran = @(); not_run = @(); failed = $null
    exchange = @(Get-RcList $prep 'exchange'); manual = @(Get-RcList $prep 'manual'); licenses = @(Get-RcList $prep 'licenses')
    note_written = $false
}
$publicText = @{
    pending_confirmation = 'Your role change request has been received. A technician will review it before anything changes.'
    success              = 'Your role change has been processed.'
    other                = 'We could not complete this role change automatically. A technician will follow up.'
}

# Adds the internal note when there is a ticket. A note failure is a warning, never a failed run.
function Write-RcNote {
    param([string]$Text, [string]$Title, [string]$Status)
    if (-not $ticketId) { return }
    try {
        $kind = Get-PsaType -Requested ([string](Get-PsaProp $prep 'psa'))
        if (-not $kind) { $null = $warnings.Add("No PSA is set up (PSA-Type secret), so no note was added to ticket $ticketId."); return }
        $null = Connect-Psa -Psa $kind
        # Retry guard: the marker names the outcome, the request code from the Read step (a hash, no names) and the
        # UTC day, so a ServiceAI Retry writes nothing twice. A retry that gets further (for example after a failed
        # change) has a different outcome, so its note is still written.
        $rcKey = [string](Get-PsaProp $prep 'request_key'); if (-not $rcKey) { $rcKey = 'no-request' }
        $rcOutcome = switch ($Status) { 'pending_confirmation' { 'preview' } 'success' { 'applied' } default { $Status } }
        $noteMarker = "role-change-mover: $rcOutcome $rcKey $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'))"
        $noteWrite = Add-PsaNote -Id $ticketId -Text $Text -Title $Title -Marker $noteMarker
        if ($noteWrite -eq 'already-present') { $null = $actions.Add("The internal note was already on ticket $ticketId, so it was not added again") }
        else { $out.note_written = $true; $null = $actions.Add("Added an internal note to ticket $ticketId") }
    }
    catch { $null = $warnings.Add("Couldn't add the note to ticket $($ticketId): $($_.Exception.Message)") }
}
function Complete-Rc {
    param([string]$Status, [string]$Msg, [string]$Note)
    $out.status = $Status; $out.message = $Msg; $out.chatReply = $Msg
    $out.internal_note = $(if ($Note) { $Note } else { $Msg })
    $out.public_note = $(if ($publicText.ContainsKey($Status)) { $publicText[$Status] } else { $publicText.other })
    Write-RcNote $out.internal_note $(if ($Status -eq 'pending_confirmation') { 'Role change plan (preview)' } else { 'Role change result' }) $Status
    $out.actions = @($actions); $out.warnings = @($warnings)
    Set-NodeOutput $out
    # The output is kept; the throw marks the run as failed in the run history.
    if (@('error', 'incomplete', 'rejected') -contains $Status) { throw $Msg }
}

if ($null -eq $prep) { Complete-Rc 'error' 'The Apply step got no output from the Read step.' ''; return }
$prepStatus = [string](Get-PsaProp $prep 'status')
if ($prepStatus -ne 'ok') {
    $m = [string](Get-PsaProp $prep 'message')
    Complete-Rc $(if ($prepStatus) { $prepStatus } else { 'error' }) $m "Role change for $(if ($upn) { $upn } else { 'an unknown user' }) was not planned.`n$m"
    return
}

$plan = $null; $result = $null
try {
    # ---------- the plan ----------
    $uid = [string](Get-PsaProp $prep 'user_id')
    $plan = New-ChangePlan "Role change for $upn"
    foreach ($g in @(Get-RcList $prep 'adds')) {
        Add-PlannedChange $plan "Add to $(Get-PsaProp $g 'name') ($(Get-PsaProp $g 'kind') group)" { param($gid, $u) Add-GraphGroupMember -GroupId $gid -UserId $u } -Arguments @([string](Get-PsaProp $g 'id'), $uid)
    }
    foreach ($g in @(Get-RcList $prep 'removes')) {
        Add-PlannedChange $plan "Remove from $(Get-PsaProp $g 'name') ($(Get-PsaProp $g 'kind') group)" { param($gid, $u) Remove-GraphGroupMember -GroupId $gid -UserId $u } -Arguments @([string](Get-PsaProp $g 'id'), $uid)
    }
    $prof = Get-PsaProp $prep 'profile'
    if ($null -ne $prof) {
        $body = [ordered]@{}; $parts = @()
        $d = Get-PsaProp $prof 'department'; if ($null -ne $d) { $body.department = [string]$d; $parts += "department to '$d'" }
        $t = Get-PsaProp $prof 'jobTitle'; if ($null -ne $t) { $body.jobTitle = [string]$t; $parts += "job title to '$t'" }
        if ($body.Count) {
            Add-PlannedChange $plan "Set $($parts -join ' and ')" { param($u, $b) $null = Invoke-Graph -Method PATCH -Path "/v1.0/users/$u" -Body $b -Permission 'User.ReadWrite.All'; 'updated' } -Arguments @($uid, $body)
        }
    }
    $mgr = Get-PsaProp $prep 'manager'
    if ($null -ne $mgr) {
        $mname = [string](Get-PsaProp $mgr 'name'); $mupn = [string](Get-PsaProp $mgr 'upn')
        Add-PlannedChange $plan "Set manager to $mname ($mupn)" { param($u, $m) Set-GraphManager -UserId $u -ManagerId $m; 'set' } -Arguments @($uid, [string](Get-PsaProp $mgr 'id'))
    }

    if (@($plan.changes).Count -and $confirm) { $null = Connect-Graph }
    $result = Invoke-ChangePlan -Plan $plan -Confirm $confirm
    $out.planned = @($result.planned); $out.not_run = @($result.notRun); $out.failed = $result.failed
    $out.ran = @(@($result.ran) | ForEach-Object { [ordered]@{ description = $_.description; result = [string]$_.output } })
}
catch {
    Complete-Rc 'error' "Couldn't run the role change for $($upn): $($_.Exception.Message)" ''
    return
}

# ---------- the note and the message ----------
$who = [string](Get-PsaProp $prep 'display_name'); if (-not $who) { $who = $upn }
$from = [string](Get-PsaProp $prep 'old_department'); $to = [string](Get-PsaProp $prep 'new_department')
$lines = New-Object System.Collections.ArrayList
$null = $lines.Add("Role change for $who ($upn): $(if ($from) { "$from to $to" } else { "to $to" }).")
function Add-RcSection {
    param([string]$Heading, [string[]]$Items)
    if (-not @($Items).Count) { return }
    $null = $lines.Add(''); $null = $lines.Add($Heading)
    foreach ($i in $Items) { $null = $lines.Add("- $i") }
}
$ex = @($out.exchange | ForEach-Object { "$(if ((Get-PsaProp $_ 'action') -eq 'add') { 'Add to' } else { 'Remove from' }) $(Get-PsaProp $_ 'name') ($(Get-PsaProp $_ 'kind'))" })
$man = @($out.manual | ForEach-Object { "$(if ((Get-PsaProp $_ 'action') -eq 'add') { 'Add to' } else { 'Remove from' }) $(Get-PsaProp $_ 'name'). $(Get-PsaProp $_ 'reason')" })
$lic = @($out.licenses | ForEach-Object { "$(if ((Get-PsaProp $_ 'change') -eq 'assign') { 'Assign' } else { 'Remove' }) $(Get-PsaProp $_ 'sku'). $(Get-PsaProp $_ 'reason')" })
$extra = @()
if ($ex.Count) { $extra += "$($ex.Count) $(if ($ex.Count -eq 1) { 'list needs' } else { 'lists need' }) changing in Exchange" }
if ($man.Count) { $extra += "$($man.Count) $(if ($man.Count -eq 1) { 'group needs' } else { 'groups need' }) changing by hand" }
if ($lic.Count) { $extra += "$($lic.Count) licence $(if ($lic.Count -eq 1) { 'difference needs' } else { 'differences need' }) review" }
$extraText = if ($extra.Count) { " Also, $($extra -join ', ')." } else { '' }

$status = 'success'; $msg = ''
switch ($result.status) {
    'preview' {
        $status = 'pending_confirmation'
        $null = $lines.Add('Preview only. Nothing was changed. Run again with confirm set to true to apply the Microsoft 365 changes.')
        Add-RcSection 'Microsoft 365 changes planned:' @($result.planned)
        $msg = "Previewed $(@($result.planned).Count) changes for $upn. Nothing was changed; run again with confirm set to true to apply them.$extraText"
    }
    'empty' {
        $null = $lines.Add('The groups, department, title and manager already match the department map. Nothing was changed in Microsoft 365.')
        $msg = "$upn already matches the department map for $to. Nothing was changed.$extraText"
    }
    'done' {
        $null = $lines.Add("Applied all $(@($result.ran).Count) Microsoft 365 changes.")
        Add-RcSection 'Done:' @(@($result.ran) | ForEach-Object { $_.description })
        $msg = "Applied $(@($result.ran).Count) changes for $upn.$extraText"
    }
    default {
        $status = 'error'
        $null = $lines.Add("Stopped part way. $($result.message)")
        Add-RcSection 'Done:' @(@($result.ran) | ForEach-Object { $_.description })
        Add-RcSection 'Not run:' @($result.notRun)
        $msg = $result.message
    }
}
Add-RcSection 'Change in Exchange (Microsoft Graph cannot change distribution lists or mail-enabled security groups):' $ex
Add-RcSection 'Change by hand:' $man
Add-RcSection 'Licences to review (not changed by this workflow):' $lic
Add-RcSection 'Already as planned:' @(Get-RcList $prep 'unchanged')
Add-RcSection 'Warnings:' @($warnings)
Complete-Rc $status $msg ($lines -join "`n")
