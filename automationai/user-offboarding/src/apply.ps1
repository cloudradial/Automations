# Step 2: preview the offboarding plan, or carry it out when confirm is true, then write the completion report:
# an internal ticket note, a Report Archive item (archive "Offboarding", admins only) and a generic public note.
# Order matters and is fixed: sign-in, password and sessions first; then groups that don't assign a licence;
# then the mailbox (convert to shared, hide, forward); then licence groups and licences. The plan stops at the
# first failure, so licences are never removed after a failed mailbox conversion.
# The random password is made inside the change and never stored, logged or returned.
function ConvertFrom-OfMaybeJson { param($v) if ($v -is [string]) { $s = $v.Trim(); if ($s -match '^[\[{]') { try { return ($s | ConvertFrom-Json) } catch { } } }; return $v }
function Get-OfParam {
    param([string]$n)
    # A bound parameter may arrive as a variable, as a property of the node input, or as the whole node input.
    $v = Get-Variable -Name $n -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $v) { $all = $null; try { $all = ConvertFrom-OfMaybeJson (Get-NodeInput) } catch { }; $v = Get-OfProp $all $n; if ($null -eq $v -and $null -ne (Get-OfProp $all 'licence_plan')) { $v = $all } }
    return (ConvertFrom-OfMaybeJson $v)
}
function Get-OfList { param($o, [string]$n) return @(@(Get-OfProp $o $n) | Where-Object { $null -ne $_ }) }
function ConvertTo-OfHtml { param([string]$s) return [System.Net.WebUtility]::HtmlEncode($s) }

$prep = Get-OfParam 'prep'
$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
foreach ($w in @(Get-OfProp $prep 'warnings')) { if ($w) { $null = $warnings.Add([string]$w) } }
foreach ($a in @(Get-OfProp $prep 'actions')) { if ($a) { $null = $actions.Add([string]$a) } }
$ticketId = [string](Get-OfProp $prep 'ticket_id')
$confirm = (Get-OfProp $prep 'confirm') -eq $true -or [string](Get-OfProp $prep 'confirm') -match '^(?i)(true|yes|y|1)$'
$upn = [string](Get-OfProp $prep 'upn')
$exPrep = Get-OfProp $prep 'exchange'
$lp = Get-OfProp $prep 'licence_plan'
$out = [ordered]@{
    status = 'error'; message = ''; public_note = ''; internal_note = ''; ticket_id = $ticketId
    actions = @(); warnings = @(); chatReply = ''
    confirm = $confirm; upn = $upn; user_id = [string](Get-OfProp $prep 'user_id')
    planned = @(); ran = @(); not_run = @(); failed = $null
    follow_up = @(); licences_removed = $false; report = $null; note_written = $false
}
$publicText = @{
    pending_confirmation = 'We have received the offboarding request. A technician will review it before any changes are made.'
    success              = 'The offboarding request has been processed.'
    other                = 'We could not complete the offboarding request automatically. A technician will follow up.'
}
$psaReady = @{ done = $false; ok = $false }
function Connect-OfPsa {
    if ($psaReady.done) { return $psaReady.ok }
    $psaReady.done = $true
    $kind = Get-PsaType -Requested ([string](Get-OfProp $prep 'psa'))
    if (-not $kind) { $null = $warnings.Add("No PSA is set up (PSA-Type secret), so nothing was written to ticket $ticketId."); return $false }
    try { $null = Connect-Psa -Psa $kind; $psaReady.ok = $true } catch { $null = $warnings.Add("Couldn't connect to the PSA for ticket $($ticketId): $($_.Exception.Message)") }
    return $psaReady.ok
}
# Notes never fail the run; a failure becomes a warning.
# Every note carries a stable marker, so a ServiceAI Action Runs "Retry" (or a rerun) writes nothing twice.
function Write-OfNote {
    param([string]$Text, [string]$Title, [string]$Marker, [switch]$Public)
    if (-not $ticketId) { return }
    if (-not (Connect-OfPsa)) { return }
    $kind = $(if ($Public) { 'public' } else { 'internal' })
    try {
        $res = $(if ($Public) { Add-PsaNote -Id $ticketId -Text $Text -Title $Title -Public -Marker $Marker } else { Add-PsaNote -Id $ticketId -Text $Text -Title $Title -Marker $Marker })
        if ($res -eq 'already-present') { $null = $actions.Add("The $kind note was already on ticket $ticketId, so it wasn't added again"); return }
        if (-not $Public) { $out.note_written = $true }
        $null = $actions.Add("Added a$(if ($Public) { '' } else { 'n' }) $kind note to ticket $ticketId")
    }
    catch { $null = $warnings.Add("Couldn't add the $kind note to ticket $($ticketId): $($_.Exception.Message)") }
}
# A short fingerprint of the planned changes, so a preview with different changes gets its own note.
function Get-OfFingerprint { param([string]$s) $h = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s)); return ([System.BitConverter]::ToString($h) -replace '-', '').Substring(0, 8).ToLowerInvariant() }
function Complete-Of {
    param([string]$Status, [string]$Msg, [string]$Note, [switch]$PublicToo)
    $out.status = $Status; $out.message = $Msg; $out.chatReply = $Msg
    $out.internal_note = $(if ($Note) { $Note } else { $Msg })
    $out.public_note = $(if ($publicText.ContainsKey($Status)) { $publicText[$Status] } else { $publicText.other })
    $who0 = $(if ($upn) { $upn } else { 'unknown user' })
    $mk = $(if ($Status -eq 'pending_confirmation') { "offboarding preview $who0 $(Get-OfFingerprint (@($out.planned) -join "`n"))" } else { "offboarding $Status $who0" })
    Write-OfNote $out.internal_note $(if ($Status -eq 'pending_confirmation') { 'Offboarding plan (preview)' } else { 'Offboarding report' }) $mk
    # The client sees only the opaque "Ref: xxxxxxxx" Add-PsaNote derives from this marker; the user is a fingerprint.
    if ($PublicToo) { Write-OfNote $out.public_note 'Offboarding' "offboarding public $Status $(Get-OfFingerprint $who0.ToLowerInvariant())" -Public }
    $out.actions = @($actions); $out.warnings = @($warnings)
    Set-NodeOutput $out
    # The output is kept; the throw marks the run as failed in the run history.
    if (@('error', 'incomplete', 'rejected') -contains $Status) { throw $Msg }
}

if ($null -eq $prep) { Complete-Of 'error' 'The Apply step got no output from the Read step.' ''; return }
$prepStatus = [string](Get-OfProp $prep 'status')
if ($prepStatus -ne 'ok') {
    $m = [string](Get-OfProp $prep 'message')
    Complete-Of $(if ($prepStatus) { $prepStatus } else { 'error' }) $m "Offboarding of $(if ($upn) { $upn } else { 'an unknown user' }) was not planned.`n$m"
    return
}

$uid = [string](Get-OfProp $prep 'user_id')
$who = [string](Get-OfProp $prep 'display_name'); if (-not $who) { $who = $upn }
$exAvailable = (Get-OfProp $exPrep 'available') -eq $true
$exOrg = [string](Get-OfProp $exPrep 'org')
$removeLicences = (Get-OfProp $lp 'remove') -eq $true
$sec = Get-OfProp $prep 'security'
$plan = $null; $result = $null
try {
    # ---------- the plan, in a fixed order ----------
    $plan = New-ChangePlan "Offboard $upn"
    if ((Get-OfProp $sec 'disable') -eq $true) { Add-PlannedChange $plan 'Block sign-in' { param($u) Set-GraphAccountEnabled -UserId $u -Enabled $false; 'blocked' } -Arguments @($uid) }
    if ((Get-OfProp $sec 'reset_password') -eq $true) {
        Add-PlannedChange $plan 'Reset the password to a random value that is not recorded anywhere' {
            param($u)
            $pw = New-GraphTempPassword -Length 24
            try { $null = Invoke-Graph -Method PATCH -Path "/v1.0/users/$u" -Body @{ passwordProfile = @{ password = $pw; forceChangePasswordNextSignIn = $true } } -Permission 'User.ReadWrite.All (plus an Entra role that can reset passwords, such as User Administrator, assigned to the app)' }
            finally { $pw = $null }
            'reset'
        } -Arguments @($uid)
    }
    if ((Get-OfProp $sec 'revoke') -eq $true) { Add-PlannedChange $plan 'Sign out of every session' { param($u) Revoke-GraphSessions -UserId $u; 'revoked' } -Arguments @($uid) }
    foreach ($g in @(Get-OfList $prep 'groups_remove')) {
        Add-PlannedChange $plan "Remove from $(Get-OfProp $g 'name') ($(Get-OfProp $g 'kind'))" { param($gid, $u) Remove-GraphGroupMember -GroupId $gid -UserId $u } -Arguments @([string](Get-OfProp $g 'id'), $uid)
    }
    if ($exAvailable) {
        $connectEx = { param($o) if (-not (Connect-OfExchange -Organization $o)) { throw "Exchange Online couldn't be reached: $($OfExo.Reason)" } }
        if ((Get-OfProp $exPrep 'convert') -eq $true) {
            Add-PlannedChange $plan 'Convert the mailbox to a shared mailbox' {
                param($u, $o, $c)
                & $c $o
                $null = Invoke-OfExo 'Set-Mailbox' @{ Identity = $u; Type = 'Shared' }
                # Check it took before anything later (licence removal) relies on it.
                for ($i = 1; $i -le 3; $i++) {
                    $mb = Get-OfMailbox $u
                    if (([string](Get-OfProp $mb 'RecipientTypeDetails')) -eq 'SharedMailbox') { return 'converted' }
                    if ($i -lt 3) { Start-Sleep -Seconds 10 }
                }
                throw 'Exchange accepted the change, but the mailbox still isn''t shared. Licences were left on.'
            } -Arguments @($upn, $exOrg, $connectEx)
        }
        if ((Get-OfProp $exPrep 'hide') -eq $true) {
            Add-PlannedChange $plan 'Hide from the global address list' { param($u, $o, $c) & $c $o; $null = Invoke-OfExo 'Set-Mailbox' @{ Identity = $u; HiddenFromAddressListsEnabled = $true }; 'hidden' } -Arguments @($upn, $exOrg, $connectEx)
        }
        $fwd = [string](Get-OfProp $exPrep 'forward_to')
        if ($fwd) {
            $fname = [string](Get-OfProp $exPrep 'forward_name')
            Add-PlannedChange $plan "Forward new mail to $(if ($fname) { "$fname ($fwd)" } else { $fwd }), keeping a copy in the mailbox" { param($u, $t, $o, $c) & $c $o; $null = Invoke-OfExo 'Set-Mailbox' @{ Identity = $u; ForwardingAddress = $t; DeliverToMailboxAndForward = $true }; 'forwarding' } -Arguments @($upn, $fwd, $exOrg, $connectEx)
        }
    }
    if ($removeLicences) {
        foreach ($g in @(Get-OfList $prep 'groups_licence')) {
            Add-PlannedChange $plan "Remove from $(Get-OfProp $g 'name') ($(Get-OfProp $g 'kind'), assigns $(@(Get-OfProp $g 'licences') -join ', '))" { param($gid, $u) Remove-GraphGroupMember -GroupId $gid -UserId $u } -Arguments @([string](Get-OfProp $g 'id'), $uid)
        }
        $lics = @(Get-OfList $prep 'licences')
        if ($lics.Count) {
            Add-PlannedChange $plan "Remove the licences: $(@($lics | ForEach-Object { Get-OfProp $_ 'sku' }) -join ', ')" { param($u, $ids) Set-GraphLicense -UserId $u -Remove $ids; 'removed' } -Arguments @($uid, [string[]]@($lics | ForEach-Object { [string](Get-OfProp $_ 'skuId') }))
        }
    }

    if (@($plan.changes).Count -and $confirm) { $null = Connect-Graph }
    $result = Invoke-ChangePlan -Plan $plan -Confirm $confirm
    $out.planned = @($result.planned); $out.not_run = @($result.notRun); $out.failed = $result.failed
    $out.ran = @(@($result.ran) | ForEach-Object { [ordered]@{ description = $_.description; result = [string]$_.output } })
    $out.licences_removed = @($result.ran | Where-Object { $_.description -like 'Remove the licences*' }).Count -gt 0
}
catch {
    Complete-Of 'error' "Couldn't run the offboarding of $($upn): $($_.Exception.Message)" ''
    return
}

# ---------- what a technician still has to do, and what was left alone ----------
$followUp = New-Object System.Collections.ArrayList
$exReason = [string](Get-OfProp $exPrep 'reason')
$exCmds = @(Get-OfList $exPrep 'manual_commands')
if (-not $exAvailable -and $exCmds.Count) {
    foreach ($c in $exCmds) { $null = $followUp.Add("Not done, do this in Exchange: $c") }
}
foreach ($g in @(Get-OfList $prep 'exchange_groups')) { $null = $followUp.Add("Remove from the $(Get-OfProp $g 'kind') $(Get-OfProp $g 'name') in Exchange (Graph can't change it): $(Get-OfProp $g 'command')") }
foreach ($m in @(Get-OfList $prep 'manual')) { $null = $followUp.Add("$(Get-OfProp $m 'item'). $(Get-OfProp $m 'reason')") }
$keptLic = @()
if (-not $removeLicences) {
    $why = [string](Get-OfProp $lp 'reason')
    foreach ($l in @(Get-OfList $prep 'licences')) { $keptLic += "$(Get-OfProp $l 'sku') (assigned directly)" }
    foreach ($g in @(Get-OfList $prep 'groups_licence')) { $keptLic += "$(@(Get-OfProp $g 'licences') -join ', ') (through the group $(Get-OfProp $g 'name'), which the user stays in)" }
    if ($keptLic.Count) { $null = $followUp.Add("Licences kept: $($keptLic -join '; '). $why") }
}
$reportOnly = New-Object System.Collections.ArrayList
foreach ($r in @(Get-OfList $prep 'direct_reports')) { $null = $reportOnly.Add("Reports to this user, needs a new manager: $r") }
foreach ($d in @(Get-OfList $prep 'devices')) { $null = $reportOnly.Add("Registered or owned device, collect and wipe or reassign: $d") }
foreach ($r in @(Get-OfList $prep 'roles')) { $null = $reportOnly.Add("Admin role still assigned, remove by hand: $r") }
$curFwd = [string](Get-OfProp $exPrep 'current_forwarding')
if ($curFwd -and -not [string](Get-OfProp $exPrep 'forward_to')) { $null = $reportOnly.Add("The mailbox already forwards to $curFwd. Check this is still wanted.") }
$out.follow_up = @($followUp)

# ---------- the note, the report and the message ----------
$lines = New-Object System.Collections.ArrayList
$null = $lines.Add("Offboarding of $who ($upn).")
function Add-OfSection {
    param([string]$Heading, [string[]]$Items)
    if (-not @($Items).Count) { return }
    $null = $lines.Add(''); $null = $lines.Add($Heading)
    foreach ($i in $Items) { $null = $lines.Add("- $i") }
}
$sections = New-Object System.Collections.ArrayList
function Add-OfReport { param([string]$Heading, [string[]]$Items) if (@($Items).Count) { $null = $sections.Add(@{ h = $Heading; items = @($Items) }) }; Add-OfSection $Heading $Items }

$left = $(if ($followUp.Count) { " $($followUp.Count) $(if ($followUp.Count -eq 1) { 'item is' } else { 'items are' }) left for a technician." } else { '' })
$status = 'success'; $msg = ''; $isRun = $false
switch ($result.status) {
    'preview' {
        $status = 'pending_confirmation'
        $null = $lines.Add('Preview only. Nothing was changed. Run again with confirm set to true to make these changes.')
        Add-OfSection 'Changes planned, in this order:' @($result.planned)
        $msg = "Previewed $(@($result.planned).Count) changes to offboard $upn. Nothing was changed; run again with confirm set to true to make them.$left"
    }
    'empty' {
        $isRun = $confirm
        $null = $lines.Add('There was nothing for this workflow to change.')
        $msg = "There was nothing to change for $upn.$left"
    }
    'done' {
        $isRun = $true
        $null = $lines.Add("Made all $(@($result.ran).Count) changes.")
        Add-OfReport 'Changed:' @(@($result.ran) | ForEach-Object { $_.description })
        $msg = "Offboarded $upn with $(@($result.ran).Count) changes.$left"
    }
    default {
        $isRun = $true
        $status = 'error'
        $null = $lines.Add("Stopped part way. $($result.message)")
        Add-OfReport 'Changed:' @(@($result.ran) | ForEach-Object { $_.description })
        Add-OfReport 'Failed:' @("$($result.failed.description): $($result.failed.error)")
        Add-OfReport 'Not done because an earlier change failed:' @($result.notRun)
        $msg = $result.message
    }
}
if ($status -eq 'pending_confirmation') {
    Add-OfSection 'Not done by this workflow (for a technician):' @($followUp)
    Add-OfSection 'For your information (not changed):' @($reportOnly)
}
else {
    Add-OfReport 'Not done by this workflow (for a technician):' @($followUp)
    Add-OfReport 'For your information (not changed):' @($reportOnly)
}
# Completion report in the company's Report Archive (admins only). Only for runs that changed something.
if ($isRun) {
    $cid = [string](Get-OfProp $prep 'company_id')
    if ($cid -notmatch '^\d+$') { $null = $warnings.Add('No CloudRadial company id was given (company_id input or CloudRadial-CompanyId secret), so the completion report was not written to Report Archives. It is in this run''s output and the internal note.') }
    else {
        $html = New-Object System.Text.StringBuilder
        $null = $html.Append("<h2>Offboarding report: $(ConvertTo-OfHtml $who)</h2><p>$(ConvertTo-OfHtml $upn). Run on $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC. Result: $(ConvertTo-OfHtml $msg)</p>")
        foreach ($s in $sections) { $null = $html.Append("<h3>$(ConvertTo-OfHtml $s.h)</h3><ul>"); foreach ($i in $s.items) { $null = $html.Append("<li>$(ConvertTo-OfHtml $i)</li>") }; $null = $html.Append('</ul>') }
        if ($warnings.Count) { $null = $html.Append('<h3>Warnings</h3><ul>'); foreach ($w in $warnings) { $null = $html.Append("<li>$(ConvertTo-OfHtml $w)</li>") }; $null = $html.Append('</ul>') }
        try {
            $null = Connect-Cr
            $rep = Add-CrArchiveReport -CompanyId ([int]$cid) -ArchiveName 'Offboarding' -Subject "Offboarding: $who ($upn) $((Get-Date).ToString('yyyy-MM-dd'))" -Html $html.ToString() -Category 'Offboarding' -IsError:($status -eq 'error')
            $out.report = $rep
            $null = $actions.Add("Wrote the completion report to $($rep.location)")
        }
        catch { $null = $warnings.Add("Couldn't write the completion report to Report Archives: $($_.Exception.Message) It is in this run's output and the internal note.") }
    }
}
Add-OfSection 'Warnings:' @($warnings)
$note = $lines -join "`n"
Complete-Of $status $msg $note -PublicToo:($isRun -and $status -eq 'success')
