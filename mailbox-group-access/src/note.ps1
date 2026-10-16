# Step 3: note the ticket, ask for approval when it is needed, and close the ticket when the access is in place.
# - confirm false: writes nothing and sends nothing; the notes it would write are in the output.
# - success: an internal note with what changed, a short public note for the requester, then the ticket is closed
#   when closeTicket is true.
# - pending_approval: an internal note naming who must approve and, when the Access-NotifySender secret is set,
#   an email to the user's manager (or the owners) asking them to reply on the ticket.
# - rejected, incomplete, error: an internal note with the reason and any command for a technician.
# Every note carries a marker starting "mailbox-group-access", so a rerun or a ServiceAI Retry writes nothing twice.
# Notes, email and closing never fail the run; a failure becomes a warning.
function Get-AccProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Test-AccYes { param($v) return ($v -eq $true -or ([string]$v).Trim() -match '^(?i)(true|yes|y|1|on)$') }
function ConvertFrom-AccJson { param($v) if ($v -is [string]) { $s = $v.Trim(); if ($s -match '^[\[{]') { try { return ($s | ConvertFrom-Json) } catch { } } }; return $v }
function Get-AccParam {
    param([string]$n)
    $v = Get-Variable -Name $n -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $v) { $all = $null; try { $all = ConvertFrom-AccJson (Get-NodeInput) } catch { }; $v = Get-AccProp $all $n; if ($null -eq $v -and $null -ne (Get-AccProp $all 'granted')) { $v = $all } }
    return (ConvertFrom-AccJson $v)
}
function Get-AccFingerprint { param([string]$s) $h = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s)); return ([System.BitConverter]::ToString($h) -replace '-', '').Substring(0, 8).ToLowerInvariant() }
function Format-AccSection { param([string]$Heading, [string[]]$Items) $i = @($Items | Where-Object { $_ }); if (-not $i.Count) { return '' }; return "`n`n$Heading`n" + (@($i | ForEach-Object { "- $_" }) -join "`n") }

$res = Get-AccParam 'result'
$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
foreach ($w in @(Get-AccProp $res 'warnings')) { if ($w) { $null = $warnings.Add([string]$w) } }
foreach ($a in @(Get-AccProp $res 'actions')) { if ($a) { $null = $actions.Add([string]$a) } }
$status = [string](Get-AccProp $res 'status'); if (-not $status) { $status = 'error' }
$msg = [string](Get-AccProp $res 'message'); if ($null -eq $res) { $msg = 'The Note step got no output from the Grant step. Nothing was changed.' }
$ticketId = [string](Get-AccProp $res 'ticket_id')
$confirm = Test-AccYes (Get-AccProp $res 'confirm')
$target = Get-AccProp $res 'target'; $resource = Get-AccProp $res 'resource'; $change = Get-AccProp $res 'change'
$accessType = [string](Get-AccProp $res 'access_type')
$tn = [string](Get-AccProp $target 'name'); $tu = [string](Get-AccProp $target 'upn')
$rn = [string](Get-AccProp $resource 'name'); $rm = [string](Get-AccProp $resource 'mail'); $rl = [string](Get-AccProp $resource 'label'); $kind = [string](Get-AccProp $resource 'kind')
$approvers = @(@(Get-AccProp $res 'approvers') | Where-Object { $null -ne $_ })
$command = [string](Get-AccProp $res 'manual_command')
$already = Test-AccYes (Get-AccProp $res 'already_has_access')
$phrase = $(switch ($accessType) { 'fullAccess' { 'full access to' } 'sendAs' { 'send-as permission on' } 'sendOnBehalf' { 'send-on-behalf permission on' } 'member' { 'membership of' } 'owner' { 'ownership of' } default { 'access to' } })
$out = [ordered]@{
    status = $status; message = $msg; public_note = ''; internal_note = ''; ticket_id = $ticketId
    counts = [ordered]@{ granted = 0; alreadyHadAccess = 0; notesWritten = 0; emailsSent = 0; ticketsClosed = 0 }
    target = $tu; resource = $(if ($rm) { $rm } else { $rn }); access_type = $accessType; approved = (Test-AccYes (Get-AccProp $res 'approved'))
    manual_command = ''; actions = @(); warnings = @()
}
if ($status -eq 'success') { if ($already) { $out.counts.alreadyHadAccess = 1 } elseif (Test-AccYes (Get-AccProp $res 'granted')) { $out.counts.granted = 1 } }

# ---------- the notes ----------
$what = $(if ($rm) { "the $rl $rn ($rm)" } elseif ($rn) { "the $rl $rn" } else { 'the requested mailbox or group' })
$isMailbox = $kind -match '_mailbox$'
$isTeam = $kind -eq 'team'
$public = ''
$internal = ''
$who = $(if ($tn) { "$tn ($tu)" } else { 'Someone' })
$head = "Access request for $who to $what$(if ($accessType) { ": $($phrase -replace ' (to|on|of)$', '')" })."
$approval = [string](Get-AccProp $res 'approval')
$approverLines = @($approvers | ForEach-Object { "$(Get-AccProp $_ 'name') ($(Get-AccProp $_ 'mail')), $(Get-AccProp $_ 'role')" })
$done = $(switch ($accessType) {
        'fullAccess' { "$tn now has full access to the $rn mailbox$(if ($rm) { " ($rm)" }). It can take up to an hour to appear in Outlook." }
        'sendAs' { "$tn can now send email as $rn$(if ($rm) { " ($rm)" }). It can take up to an hour to start working in Outlook." }
        'sendOnBehalf' { "$tn can now send email on behalf of $rn$(if ($rm) { " ($rm)" }). It can take up to an hour to start working in Outlook." }
        'member' { $(if ($isTeam) { "$tn is now a member of the $rn team. It can take a little while to show in Microsoft Teams." } else { "$tn is now a member of the $rn $(if ($kind -eq 'distribution_list') { 'distribution list' } else { 'group' })." }) }
        'owner' { "$tn is now an owner of the $rn $(if ($isTeam) { 'team' } else { 'group' })." }
        default { '' }
    })
$had = $(switch ($accessType) {
        'fullAccess' { "$tn already has full access to the $rn mailbox$(if ($rm) { " ($rm)" }), so nothing needed to change. If it isn't showing in Outlook yet, it can take up to an hour." }
        'sendAs' { "$tn can already send email as $rn, so nothing needed to change." }
        'sendOnBehalf' { "$tn can already send email on behalf of $rn, so nothing needed to change." }
        'member' { "$tn is already a member of $rn, so nothing needed to change." }
        'owner' { "$tn is already an owner of $rn, so nothing needed to change." }
        default { '' }
    })
switch ($status) {
    'success' {
        if ($already) { $internal = "$head`n$tn already had this access, so nothing was changed."; $public = $had }
        else {
            $internal = "$head`nDone: $([string](Get-AccProp $change 'description')). Read back afterwards: the access is in place."
            if ($approval) { $internal += "`n$approval" }
            $public = $done
        }
    }
    'pending_confirmation' {
        $internal = "$head`nNot done yet: confirm was false, so nothing was changed.$(if ($approval) { "`n$approval" })" + (Format-AccSection 'People who can approve it:' $approverLines)
    }
    'pending_approval' {
        $internal = "$head`nNot done yet: it needs approval, so nothing was changed." + (Format-AccSection 'Any one of these people can approve it:' $approverLines)
        $internal += $(if ($approverLines.Count) { "`n`nWhen one of them approves, run" } else { "`n`nNobody in Microsoft 365 can approve it yet (see the warnings). When an approver is set and agrees, run" }) + " this workflow again with approvedBy set to their email address and confirm set to true."
        if (Test-AccYes (Get-AccProp $res 'needs_technician')) { $internal += " Because it is $rn's own mailbox, only approvedBy counts here; the requester's own say-so doesn't." }
    }
    default {
        $internal = "$head`nNot done: $msg"
        if ($command) { $out.manual_command = $command; $internal += Format-AccSection 'A technician can do it by hand (after checking the approval):' @($command) }
    }
}
function Get-AccNoteText { param([string]$Text) if ($warnings.Count) { return $Text + "`n`nWarnings:`n" + (@($warnings | ForEach-Object { "- $_" }) -join "`n") }; return $Text }

# ---------- PSA ----------
$psaReady = @{ done = $false; ok = $false }
function Connect-AccPsa {
    if ($psaReady.done) { return $psaReady.ok }
    $psaReady.done = $true
    if (-not $ticketId) { return $false }
    try {
        $kindPsa = Get-PsaType -Requested ([string](Get-AccProp $res 'psa'))
        if (-not $kindPsa) { $null = $warnings.Add("No PSA is set up (PSA-Type secret), so nothing was written to ticket $ticketId."); return $false }
        $null = Connect-Psa -Psa $kindPsa; $psaReady.ok = $true
    }
    catch { $null = $warnings.Add("Couldn't connect to the PSA for ticket $($ticketId): $($_.Exception.Message)") }
    return $psaReady.ok
}
# Returns 'written', 'already-present' or '' (not written).
function Write-AccNote {
    param([string]$Text, [string]$Title, [string]$Marker, [switch]$Public)
    if (-not (Connect-AccPsa)) { return '' }
    $which = $(if ($Public) { 'public' } else { 'internal' })
    try {
        $r = $(if ($Public) { Add-PsaNote -Id $ticketId -Text $Text -Title $Title -Public -Marker $Marker } else { Add-PsaNote -Id $ticketId -Text $Text -Title $Title -Marker $Marker })
        if ($r -eq 'already-present') { $null = $actions.Add("The $which note was already on ticket $ticketId, so it wasn't added again"); return 'already-present' }
        $out.counts.notesWritten++
        $null = $actions.Add("Added a$(if ($Public) { '' } else { 'n' }) $which note to ticket $ticketId")
        return 'written'
    }
    catch { $null = $warnings.Add("Couldn't add the $which note to ticket $($ticketId): $($_.Exception.Message)"); return '' }
}
function Add-AccPsaWarnings { foreach ($w in @($PsaState.Warnings)) { if ($w -and -not $warnings.Contains([string]$w)) { $null = $warnings.Add([string]$w) } } }

$key = "$accessType $(if ($rm) { $rm } else { [string](Get-AccProp $resource 'id') }) $tu".ToLowerInvariant().Trim() -replace '\s+', ' '
$title = "Access request: $(if ($rn) { $rn } else { 'mailbox or group' })"
if (-not $confirm) {
    # confirm false: nothing is written or sent. The output shows what would be written.
    $out.internal_note = Get-AccNoteText $internal
    $out.public_note = $(if ($status -eq 'success') { $public } else { '' })
    if ($status -eq 'success') { $out.message = "$msg Nothing was written to the ticket, because confirm was false." }
    $null = $actions.Add('confirm was false, so nothing was written to the ticket and no email was sent')
}
elseif ($status -eq 'success') {
    $out.internal_note = Get-AccNoteText $internal
    $out.public_note = $public
    $first = Write-AccNote $out.internal_note $title "mailbox-group-access done $key"
    if ($public) { $null = Write-AccNote $public $title "mailbox-group-access public $(Get-AccFingerprint $key)" -Public }
    if (Test-AccYes (Get-AccProp $res 'close_ticket')) {
        if ($first -eq 'written') {
            try { $st = Close-PsaTicket -Id $ticketId; $out.counts.ticketsClosed = 1; $null = $actions.Add("Closed ticket $ticketId ($st)") }
            catch { $null = $warnings.Add("Couldn't close ticket $($ticketId): $($_.Exception.Message)") }
        }
        elseif ($first -eq 'already-present') { $null = $actions.Add("Ticket $ticketId was already noted by an earlier run, so it wasn't closed again") }
        else { $null = $warnings.Add("Ticket $ticketId was not closed, because its note couldn't be written.") }
    }
}
elseif ($status -eq 'pending_approval') {
    $base = Get-AccNoteText $internal
    $marker = "mailbox-group-access pending_approval $(Get-AccFingerprint "$key $base")"
    $seen = $false
    if (Connect-AccPsa) { try { $seen = Test-PsaNoteMarker -Id $ticketId -Marker $marker } catch { $seen = $false } }
    $emailLine = ''
    $sender = ''; try { $sender = [string](Get-GraphSecret @('Access-NotifySender')) } catch { }
    if ($sender -and -not $seen) {
        $to = @($approvers | Where-Object { [string](Get-AccProp $_ 'kind') -eq 'manager' -and (Get-AccProp $_ 'mail') })
        if (-not $to.Count) { $to = @($approvers | Where-Object { Get-AccProp $_ 'mail' } | Select-Object -First 5) }
        if ($to.Count) {
            $body = "Hello,`n`n$tn has asked for $phrase $what (ticket $ticketId).`n`nYou can approve this as $([string](Get-AccProp $to[0] 'role')). Please reply on ticket $ticketId, or to your IT support team, to say whether to go ahead. Nothing changes until someone approves it.`n`nThank you."
            $mail = @{ message = @{ subject = "Approval needed: access to $rn for $tn (ticket $ticketId)"; body = @{ contentType = 'Text'; content = $body }; toRecipients = @($to | ForEach-Object { @{ emailAddress = @{ address = [string](Get-AccProp $_ 'mail'); name = [string](Get-AccProp $_ 'name') } } }) }; saveToSentItems = $false }
            try {
                $null = Connect-Graph
                $null = Invoke-Graph -Method POST -Path "/v1.0/users/$(ConvertTo-GraphId $sender)/sendMail" -Body $mail -Permission 'Mail.Send'
                $out.counts.emailsSent = $to.Count
                $emailLine = "`n`nEmailed $(@($to | ForEach-Object { Get-AccProp $_ 'name' }) -join ', ') from $sender asking for approval."
                $null = $actions.Add("Emailed $(@($to | ForEach-Object { Get-AccProp $_ 'mail' }) -join ', ') asking for approval")
            }
            catch { $null = $warnings.Add("Couldn't email the approver: $($_.Exception.Message)") }
        }
    }
    elseif ($seen) { $null = $actions.Add("Ticket $ticketId already asks for this approval, so no note or email was sent again") }
    $out.internal_note = (Get-AccNoteText $internal) + $emailLine
    if (-not $seen) { $null = Write-AccNote $out.internal_note $title $marker }
}
else {
    $out.internal_note = Get-AccNoteText $internal
    $null = Write-AccNote $out.internal_note $title "mailbox-group-access $status $(Get-AccFingerprint "$key $($out.internal_note)")"
}

Add-AccPsaWarnings
$out.actions = @($actions); $out.warnings = @($warnings)
Set-NodeOutput $out
# The output is kept; the throw marks the run as failed in the run history.
if (@('error', 'incomplete', 'rejected') -contains $status) { throw $msg }
