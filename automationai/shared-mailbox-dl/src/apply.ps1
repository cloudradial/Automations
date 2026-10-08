# Step 2: create the shared mailbox or distribution list, or hold it for a technician, then reply on the ticket.
# - preview true: nothing is created; the plan goes on the ticket as an internal note.
# - needs confirmation (someone outside the requester's department, or more than 25 members) and confirm false:
#   nothing is created; the plan and the reasons go on the ticket as an internal note.
# - otherwise: Exchange Online is signed in to first (so an unreachable Exchange creates nothing), then the
#   changes run in order and stop at the first failure. The internal note lists what ran, what failed and the
#   exact commands still to run. A public note with the new address goes on the ticket only when everything ran.
function ConvertFrom-SmMaybeJson { param($v) if ($v -is [string]) { $s = $v.Trim(); if ($s -match '^[\[{]') { try { return ($s | ConvertFrom-Json) } catch { } } }; return $v }
function Get-SmParam {
    param([string]$n)
    # A bound parameter may arrive as a variable, as a property of the node input, or as the whole node input.
    $v = Get-Variable -Name $n -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $v) { $all = $null; try { $all = ConvertFrom-SmMaybeJson (Get-NodeInput) } catch { }; $v = Get-OfProp $all $n; if ($null -eq $v -and $null -ne (Get-OfProp $all 'changes')) { $v = $all } }
    return (ConvertFrom-SmMaybeJson $v)
}
function Get-SmList { param($o, [string]$n) return @(@(Get-OfProp $o $n) | Where-Object { $null -ne $_ }) }
function Test-SmYes { param($v) return ($v -eq $true -or [string]$v -match '^(?i)(true|yes|y|1|on)$') }
# Turns a parameter object (a hashtable, or a PSCustomObject after the JSON hop between steps) into a hashtable.
function ConvertTo-SmHashtable {
    param($o)
    $h = [ordered]@{}
    if ($null -eq $o) { return $h }
    if ($o -is [System.Collections.IDictionary]) { foreach ($k in $o.Keys) { $h[[string]$k] = $o[$k] }; return $h }
    foreach ($p in $o.PSObject.Properties) { $v = $p.Value; if ($v -is [array]) { $v = @($v | ForEach-Object { [string]$_ }) }; $h[$p.Name] = $v }
    return $h
}

$prep = Get-SmParam 'prep'
$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
foreach ($w in @(Get-OfProp $prep 'warnings')) { if ($w) { $null = $warnings.Add([string]$w) } }
foreach ($a in @(Get-OfProp $prep 'actions')) { if ($a) { $null = $actions.Add([string]$a) } }
$ticketId = [string](Get-OfProp $prep 'ticket_id')
$confirm = Test-SmYes (Get-OfProp $prep 'confirm')
$isPreview = Test-SmYes (Get-OfProp $prep 'preview')
$needsConfirm = Test-SmYes (Get-OfProp $prep 'needs_confirmation')
$reasons = @(Get-SmList $prep 'confirmation_reasons' | ForEach-Object { [string]$_ })
$kindLabel = [string](Get-OfProp $prep 'kind_label'); if (-not $kindLabel) { $kindLabel = 'shared mailbox or distribution list' }
$address = [string](Get-OfProp $prep 'address')
$displayName = [string](Get-OfProp $prep 'display_name')
$changes = @(Get-SmList $prep 'changes')
$commands = @(Get-SmList $prep 'manual_commands' | ForEach-Object { [string]$_ })
$out = [ordered]@{
    status = 'error'; message = ''; public_note = ''; internal_note = ''; ticket_id = $ticketId
    actions = @(); warnings = @(); chatReply = ''
    kind = [string](Get-OfProp $prep 'kind'); address = $address; display_name = $displayName; alias = [string](Get-OfProp $prep 'alias')
    confirm = $confirm; preview = $isPreview; needs_confirmation = $needsConfirm; confirmation_reasons = @($reasons)
    planned = @(); ran = @(); not_run = @(); failed = $null; manual_commands = @()
    note_written = $false
}

$psaReady = @{ done = $false; ok = $false }
function Connect-SmPsa {
    if ($psaReady.done) { return $psaReady.ok }
    $psaReady.done = $true
    $kindPsa = Get-PsaType -Requested ([string](Get-OfProp $prep 'psa'))
    if (-not $kindPsa) { $null = $warnings.Add("No PSA is set up (PSA-Type secret), so nothing was written to ticket $ticketId."); return $false }
    try { $null = Connect-Psa -Psa $kindPsa; $psaReady.ok = $true } catch { $null = $warnings.Add("Couldn't connect to the PSA for ticket $($ticketId): $($_.Exception.Message)") }
    return $psaReady.ok
}
# Notes never fail the run; a failure becomes a warning.
# Every note carries a stable marker, so a ServiceAI Action Runs "Retry" (or a rerun) writes nothing twice.
function Write-SmNote {
    param([string]$Text, [string]$Title, [string]$Marker, [switch]$Public)
    if (-not $ticketId) { return }
    if (-not (Connect-SmPsa)) { return }
    $which = $(if ($Public) { 'public' } else { 'internal' })
    try {
        $res = $(if ($Public) { Add-PsaNote -Id $ticketId -Text $Text -Title $Title -Public -Marker $Marker } else { Add-PsaNote -Id $ticketId -Text $Text -Title $Title -Marker $Marker })
        if ($res -eq 'already-present') { $null = $actions.Add("The $which note was already on ticket $ticketId, so it wasn't added again"); return }
        if (-not $Public) { $out.note_written = $true }
        $null = $actions.Add("Added a$(if ($Public) { '' } else { 'n' }) $which note to ticket $ticketId")
    }
    catch { $null = $warnings.Add("Couldn't add the $which note to ticket $($ticketId): $($_.Exception.Message)") }
}
# A short fingerprint of a note, so a different preview or a different failure gets its own note.
function Get-SmFingerprint { param([string]$s) $h = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s)); return ([System.BitConverter]::ToString($h) -replace '-', '').Substring(0, 8).ToLowerInvariant() }
$markerKind = $(if ($out.kind) { $out.kind } else { 'mailbox-or-list' })
$markerAddr = $(if ($address) { $address } else { 'no-address' })
$doneMarker = "$markerKind created $markerAddr"
# $true when an earlier run already created this address and noted it on the ticket (a Retry after success).
function Test-SmAlreadyDone {
    if (-not $ticketId -or -not $address) { return $false }
    if (-not (Connect-SmPsa)) { return $false }
    try { return (Test-PsaNoteMarker -Id $ticketId -Marker $doneMarker) } catch { return $false }
}
function Complete-Sm {
    param([string]$Status, [string]$Msg, [string]$Note, [string]$Public = '')
    $out.status = $Status; $out.message = $Msg; $out.chatReply = $Msg
    $text = $(if ($Note) { $Note } else { $Msg })
    if ($warnings.Count) { $text += "`n`nWarnings:`n" + (@($warnings | ForEach-Object { "- $_" }) -join "`n") }
    $out.internal_note = $text
    $out.public_note = $Public
    $mk = $(if ($Status -eq 'success') { $doneMarker } else { "$markerKind $Status $markerAddr $(Get-SmFingerprint $text)" })
    Write-SmNote $out.internal_note $(if ($Status -eq 'pending_confirmation') { "New $kindLabel request (not created yet)" } else { "New $kindLabel" }) $mk
    if ($Public) { Write-SmNote $Public "New $kindLabel" "$markerKind ready $markerAddr" -Public }
    $out.actions = @($actions); $out.warnings = @($warnings)
    Set-NodeOutput $out
    # The output is kept; the throw marks the run as failed in the run history.
    if (@('error', 'incomplete', 'rejected') -contains $Status) { throw $Msg }
}
function Format-SmSection { param([string]$Heading, [string[]]$Items) if (-not @($Items).Count) { return '' }; return "`n`n$Heading`n" + (@($Items | ForEach-Object { "- $_" }) -join "`n") }

if ($null -eq $prep) { Complete-Sm 'error' 'The Apply step got no output from the Read step.' ''; return }
$prepStatus = [string](Get-OfProp $prep 'status')
if ($prepStatus -ne 'ok') {
    $m = [string](Get-OfProp $prep 'message')
    # A Retry after a successful run finds the address taken by the mailbox or list that run created. Say so and write nothing.
    if ($prepStatus -eq 'rejected' -and $m -match 'already used' -and (Test-SmAlreadyDone)) {
        $msg = "The $kindLabel $address was already created by an earlier run for ticket $ticketId. Nothing was changed."
        $out.status = 'success'; $out.message = $msg; $out.chatReply = $msg; $out.internal_note = ''; $out.public_note = ''
        $null = $actions.Add("Ticket $ticketId already notes that $address was created, so no note was added")
        $out.actions = @($actions); $out.warnings = @($warnings)
        Set-NodeOutput $out
        return
    }
    $note = "The $kindLabel request$(if ($address) { " for $address" }) was not carried out.`n$m"
    if ($commands.Count -and (Test-SmYes (Get-OfProp $prep 'exchange_unreachable'))) { $out.manual_commands = @($commands); $note += Format-SmSection 'To create it by hand in Exchange Online PowerShell, run:' $commands }
    Complete-Sm $(if ($prepStatus) { $prepStatus } else { 'error' }) $m $note
    return
}

$planList = @($changes | ForEach-Object { [string](Get-OfProp $_ 'description') })
$out.planned = @($planList)
$head = "Request for a $kindLabel $displayName ($address)."
$planText = Format-SmSection 'Planned changes, in this order:' $planList
$cmdText = Format-SmSection 'Exchange Online PowerShell equivalent:' $commands

# ---------- hold: preview, or a request a technician has to confirm ----------
if ($isPreview) {
    Complete-Sm 'pending_confirmation' "Previewed the $kindLabel $address. Nothing was created; run again without preview to create it." ("$head`nPreview only. Nothing was created." + $(if ($needsConfirm) { Format-SmSection 'This request also needs a technician''s confirmation:' $reasons } else { '' }) + $planText + $cmdText)
    return
}
if ($needsConfirm -and -not $confirm) {
    Complete-Sm 'pending_confirmation' "The $kindLabel $address needs a technician's confirmation before it is created: $($reasons -join ' ') Nothing was created; run again with confirm set to true to create it." ("$head`nNot created yet. A technician needs to confirm it, then run this workflow again with confirm set to true." + (Format-SmSection 'Why it needs confirmation:' $reasons) + $planText + $cmdText)
    return
}

# ---------- create ----------
$result = $null
# Sign in before anything is created, so an unreachable Exchange leaves nothing half made.
if (-not (Connect-OfExchange -Organization ([string](Get-OfProp $prep 'exchange_org')))) {
    $out.manual_commands = @($commands)
    Complete-Sm 'error' "Exchange Online couldn't be reached, so the $kindLabel $address was not created: $($OfExo.Reason.TrimEnd(".")). Nothing was created; the exact commands are in the internal note." ("$head`nNothing was created because Exchange Online couldn't be reached: $($OfExo.Reason)" + (Format-SmSection 'To create it by hand in Exchange Online PowerShell, run:' $commands))
    return
}
try {
    $plan = New-ChangePlan "Create $address"
    foreach ($c in $changes) {
        $cmdlet = [string](Get-OfProp $c 'cmdlet')
        $params = ConvertTo-SmHashtable (Get-OfProp $c 'parameters')
        $isNew = $cmdlet -like 'New-*'
        Add-PlannedChange $plan ([string](Get-OfProp $c 'description')) {
            param($cmd, $prm, $new)
            $h = @{}; foreach ($k in $prm.Keys) { $h[$k] = $prm[$k] }
            if ($new) { $null = Invoke-OfExo $cmd $h; return 'created' }
            # A brand-new recipient can take a minute to be visible to the next cmdlet.
            for ($i = 1; $i -le 5; $i++) {
                try { $null = Invoke-OfExo $cmd $h; return 'done' }
                catch {
                    $msg = $_.Exception.Message
                    if ($msg -match '(?i)already (has|exists|a member)|is already') { return 'already set' }
                    if ((Test-OfNotFound $msg) -and $i -lt 5) { Start-Sleep -Seconds 15; continue }
                    throw
                }
            }
        } -Arguments @($cmdlet, $params, $isNew)
    }
    $result = Invoke-ChangePlan -Plan $plan -Confirm $true
    $out.not_run = @($result.notRun); $out.failed = $result.failed
    $out.ran = @(@($result.ran) | ForEach-Object { [ordered]@{ description = $_.description; result = [string]$_.output } })
}
catch {
    Complete-Sm 'error' "Couldn't create the $kindLabel $($address): $($_.Exception.Message)" ''
    return
}

$ranList = @(@($result.ran) | ForEach-Object { [string]$_.description })
if ($result.status -eq 'done') {
    $who = Get-OfProp $prep 'requester'
    $note = "$head`nCreated$(if ($needsConfirm) { ' after a technician confirmed it' }). Owner: $(Get-OfProp $who 'name') ($(Get-OfProp $who 'upn'))." + (Format-SmSection 'Done:' $ranList)
    if ($needsConfirm) { $note += Format-SmSection 'It needed confirmation because:' $reasons }
    $public = $(if ([string](Get-OfProp $prep 'kind') -eq 'shared_mailbox') { "The new shared mailbox $displayName is ready at $address." } else { "The new distribution list $displayName is ready at $address." })
    Complete-Sm 'success' "Created the $kindLabel $displayName at $address with $($ranList.Count) change$(if ($ranList.Count -ne 1) { 's' })." $note $public
    return
}

# Stopped part way: say exactly what exists and what is left.
$failedDesc = [string]$result.failed.description
$idx = [array]::IndexOf([string[]]$planList, $failedDesc)
$left = @(); if ($idx -ge 0) { $left = @($commands | Select-Object -Skip $idx) }
$out.manual_commands = @($left)
$created = @($result.ran).Count -gt 0
$note = "$head`n$(if ($created) { "The $kindLabel was created, but the run stopped part way." } else { 'Nothing was created.' })" +
    (Format-SmSection 'Done:' $ranList) +
    (Format-SmSection 'Failed:' @("$($failedDesc): $($result.failed.error)")) +
    (Format-SmSection 'Not done because an earlier change failed:' @($result.notRun)) +
    (Format-SmSection 'To finish by hand in Exchange Online PowerShell, run:' $left)
Complete-Sm 'error' $result.message $note
