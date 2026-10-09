# === NODE: Respond to new risky users ===
# For each risky user from the previous step that doesn't already have an open "[Risky sign-in] <upn>"
# ticket in the PSA, without asking (this is what the automation is for):
#   1. opens a ticket for the company: high priority, critical when the user holds an admin role. The
#      ticket description is generic; the risk detail (IP, location, detection types, times) goes only in
#      an internal note
#   2. signs the user out of every session (User.RevokeSessions.All)
#   3. requires a password change at next sign-in (User.ReadWrite.All). Skipped for accounts synced from
#      on-premises, and has no effect for federated domains; the note says so
#   4. adds the internal note with the risk detail and what was done (Add-PsaNote -Marker, so a retried run
#      never adds it twice; the marker is "risky-signin: <ticket id>", with no name or address in it)
#   5. emails the user's manager a short notice with no risk detail (Mail.Send, from Notify-FromMailbox)
# The account is never blocked here; that needs a confirm run (next step).
# With preview true, it reads the PSA to show what it would do and changes nothing.
# The open-ticket search is the shared Find-PsaTickets (all six PSAs). When the search fails, or stops at its
# limit without a match, the step keeps a log of handled users in the company's "Risky Sign-ins" report
# archive instead (no risk detail in it).
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
function Add-RsWarning { param([string]$Text) $rs['warnings'] = @(@($rs['warnings']) + $Text) }
function Get-RsMarker { param([string]$Upn) return "[Risky sign-in] $Upn" }

# The open ticket whose summary holds the user's marker. Returns @{ supported; id; summary }.
# Uses the shared Find-PsaTickets (open tickets, only the company's when its PSA id is known), searching on
# the sign-in name and checking the marker here, because the PSAs treat brackets differently in their
# search syntax. Kaseya BMS has no text search, so its open tickets are read and matched here.
# supported is $false when the search stopped at its limit (FindTruncated) with no match, so the caller
# falls back to the report archive log rather than risk a second ticket.
function Find-RsOpenTicket {
    param([string]$Upn, [string]$CompanyId = '')
    $marker = Get-RsMarker $Upn
    $co = $(if ($CompanyId -match '^\d+$') { $CompanyId } else { '' })
    $rows = @(Find-PsaTickets -Open -Text $Upn -CompanyId $co -Max 200 -Order newest)
    $hit = @($rows | Where-Object { $null -ne $_ -and ([string]$_.summary).IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0 }) | Select-Object -First 1
    if ($null -ne $hit) { return @{ supported = $true; id = [string]$hit.id; summary = [string]$hit.summary } }
    if ($PsaState.FindTruncated) { return @{ supported = $false; id = ''; summary = '' } }
    return @{ supported = $true; id = ''; summary = '' }
}

# Fallback de-duplication: one item per handled risk in the company's "Risky Sign-ins" report archive.
# A time field as 'yyyy-MM-dd HH:mm:ss UTC'. The runner's JSON hand-off can turn ISO strings into dates.
function Get-RsTime {
    param($o, [string]$n)
    $v = Get-RsProp $o $n
    if ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v)) { return '' }
    $d = [datetime]::MinValue
    if ($v -is [datetime]) { $d = $v; if ($d.Kind -eq [DateTimeKind]::Local) { $d = $d.ToUniversalTime() } }
    elseif (-not [datetime]::TryParse([string]$v, [Globalization.CultureInfo]::InvariantCulture, ([Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal), [ref]$d)) { return [string]$v }
    return $d.ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
}
function Get-RsLogKey { param($U) return "Risky sign-in handled: $(Get-RsProp $U 'upn') $(Get-RsTime $U 'risk_updated')" }
function Test-RsLogged {
    param([int]$CompanyId, [string]$Key)
    $arch = Get-CrArchive -CompanyId $CompanyId -Name 'Risky Sign-ins'
    if ($null -eq $arch) { return $false }
    $esc = $Key.Replace("'", "''")
    $hit = @(Get-CrAll "/v2/odata/archiveitem?`$filter=$([uri]::EscapeDataString("companyId eq $CompanyId and companyReportFolderId eq $($arch.id) and subject eq '$esc'"))&`$select=companyReportItemId,subject") | Where-Object { [string](Get-CrProp $_ 'subject') -eq $Key }
    return (@($hit).Count -gt 0)
}

# The internal note: the only place the risk detail is written.
function Get-RsNote {
    param($U, [string[]]$Done, [string]$Mode)
    $L = New-Object System.Collections.ArrayList
    $null = $L.Add("Microsoft Entra ID Protection has $(Get-RsProp $U 'upn') at $(Get-RsProp $U 'risk_level') risk (state: $(Get-RsProp $U 'risk_state'); last updated $(Get-RsTime $U 'risk_updated'); reason: $(if (Get-RsProp $U 'risk_detail') { Get-RsProp $U 'risk_detail' } else { 'none given' })).")
    $roles = @(Get-RsProp $U 'admin_roles' | Where-Object { $_ })
    if ($roles.Count) { $null = $L.Add("This account holds an admin role ($($roles -join ', ')), so the ticket is critical.") }
    elseif (-not [bool](Get-RsProp $U 'admin_known')) { $null = $L.Add('Admin roles could not be checked on this run, so the ticket is high priority. Check whether this account is an admin.') }
    $dets = @(Get-RsProp $U 'detections' | Where-Object { $null -ne $_ })
    if ($dets.Count) {
        $null = $L.Add("Recent risk detections ($($dets.Count), newest first):")
        foreach ($d in @($dets | Select-Object -First 15)) {
            $bits = @("$(Get-RsProp $d 'label') ($(Get-RsProp $d 'level') risk)", "detected $(Get-RsTime $d 'detected')")
            if (Get-RsProp $d 'activity') { $bits += "activity $(Get-RsTime $d 'activity')" }
            if (Get-RsProp $d 'ip') { $bits += "IP $(Get-RsProp $d 'ip')" }
            if (Get-RsProp $d 'location') { $bits += "location $(Get-RsProp $d 'location')" }
            if (Get-RsProp $d 'timing') { $bits += "$(Get-RsProp $d 'timing') detection" }
            $null = $L.Add("- $($bits -join ', ').")
        }
        if ($dets.Count -gt 15) { $null = $L.Add("- and $($dets.Count - 15) more.") }
    }
    else { $null = $L.Add("No risk detections were found in the last $([int](Get-RsProp $opt 'lookback_days')) days. Check Entra ID Protection > Risk detections for older ones.") }
    $null = $L.Add('What the automation did:')
    foreach ($x in $Done) { $null = $L.Add("- $x") }
    if ([bool](Get-RsProp $U 'synced')) { $null = $L.Add('This account is synced from on-premises Active Directory. Reset its password there; Microsoft 365 can''t require the change for a synced account.') }
    else { $null = $L.Add('If the user''s domain is federated to another identity provider, the password change set in Microsoft 365 has no effect. Reset the password at that provider.') }
    $null = $L.Add("To block the account, run the Risky sign-in response workflow with confirm set to true and block_upns set to $(Get-RsProp $U 'upn'). It only blocks the account if it is still at risk at that time.")
    $null = $L.Add('The risk is not dismissed automatically. Once the account is safe, dismiss it in Entra ID Protection > Risky users.')
    if ($Mode -eq 'archive') { $null = $L.Add('The PSA couldn''t be searched for open tickets on this run, so this user is logged as handled in the company''s Risky Sign-ins report archive to stop a second ticket.') }
    return ($L -join "`n")
}

$rs = Read-RsState 'risky' 'Find risky users'
$opt = $rs['inputs']
$preview = [bool](Get-RsProp $opt 'preview')
$notify = [bool](Get-RsProp $opt 'notify_manager')
$risky = @($rs['risky'] | Where-Object { $null -ne $_ })
$cid = [string](Get-RsProp $opt 'company_id')
$responses = New-Object System.Collections.ArrayList

if ($risky.Count) {
    # ---- Graph (a fresh sign-in: each step has its own state) ----
    if (-not $preview) { try { $null = Connect-Graph } catch { Stop-RsRun $rs "Couldn't sign in to Microsoft 365: $($_.Exception.Message) Nothing was changed." } }

    # ---- PSA connection and the company's PSA id ----
    $psaOk = $false
    try { $null = Connect-Psa -Psa (Get-PsaType ([string](Get-RsProp $opt 'psa'))); $psaOk = $true }
    catch {
        if (-not $preview) { Stop-RsRun $rs "$($risky.Count) risky user(s) found, but the PSA isn't set up, so no ticket could be opened and nothing was changed: $($_.Exception.Message)" }
        Add-RsWarning "The PSA isn't set up, so this preview couldn't check for open tickets: $($_.Exception.Message)"
    }
    $psaCompany = [string](Get-RsProp $opt 'psa_company_id')
    $crOk = $false
    if ($cid -match '^\d+$') { try { $null = Connect-Cr; $crOk = $true } catch { Add-RsWarning "Couldn't connect to CloudRadial: $($_.Exception.Message)" } }
    if ($psaOk -and -not $psaCompany) {
        $why = ''
        if (-not $crOk) { $why = 'Set the PSA-CompanyId secret, or the CloudRadial-CompanyId and CloudRadial-* API secrets so the company can be looked up by name.' }
        else {
            try {
                $co = @(Get-CrProp (Invoke-CrApi -Path "/v2/odata/company?`$filter=$([uri]::EscapeDataString("companyId eq $cid"))&`$select=companyId,name") 'value') | Select-Object -First 1
                $cname = [string](Get-CrProp $co 'name')
                if (-not $cname) { $why = "CloudRadial company $cid wasn't found. Set the PSA-CompanyId secret." }
                else {
                    $hits = @(Find-PsaCompany $cname | Where-Object { $_.exact })
                    if ($hits.Count -eq 1) { $psaCompany = [string]$hits[0].id; $rs['actions'] = @(@($rs['actions']) + "Matched CloudRadial company '$cname' to $(Get-PsaName) company $psaCompany by name.") }
                    elseif ($hits.Count -gt 1) { $why = "$(Get-PsaName) has $($hits.Count) companies named '$cname'. Set the PSA-CompanyId secret to the right one." }
                    else { $why = "$(Get-PsaName) has no company named exactly '$cname'. Set the PSA-CompanyId secret." }
                }
            }
            catch { $why = "Couldn't look up the PSA company by name: $($_.Exception.Message) Set the PSA-CompanyId secret." }
        }
        if ($why) {
            if (-not $preview) { Stop-RsRun $rs "$($risky.Count) risky user(s) found, but the company's PSA id isn't known, so no ticket could be opened and nothing was changed. $why" }
            Add-RsWarning "The company's PSA id isn't known, so a real run would stop. $why"
        }
    }
    $mailbox = ''
    try { $mailbox = [string](Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'Notify-FromMailbox' -AsPlainText -ErrorAction SilentlyContinue) } catch { }
    $mailbox = $mailbox.Trim()
    if ($notify -and -not $mailbox) { Add-RsWarning 'The Notify-FromMailbox secret is not set, so no manager was emailed.' }

    foreach ($u in $risky) {
        $upn = [string](Get-RsProp $u 'upn'); $uid = [string](Get-RsProp $u 'id'); $name = [string](Get-RsProp $u 'name'); if (-not $name) { $name = $upn }
        $isAdmin = [bool](Get-RsProp $u 'is_admin')
        $synced = [bool](Get-RsProp $u 'synced')
        $prio = if ($isAdmin) { 'critical' } else { 'high' }
        $r = [ordered]@{ upn = $upn; name = $name; risk_level = [string](Get-RsProp $u 'risk_level'); is_admin = $isAdmin; priority = $prio; outcome = ''; dedupe = ''; ticket_id = ''; revoked = ''; password = ''; manager_mail = ''; note = ''; planned = @(); errors = @() }

        # ---- 1. Already handled? ----
        $existing = ''; $known = $false; $mode = 'psa'
        if ($psaOk) {
            try { $f = Find-RsOpenTicket $upn $psaCompany; if ($f.supported) { $known = $true; $existing = $f.id } else { $mode = 'archive'; Add-RsWarning "$(Get-PsaName) has too many open tickets to be sure $upn has none, so the report archive log was used instead." } }
            catch { $mode = 'archive'; Add-RsWarning "Couldn't search $(Get-PsaName) for an open ticket for $($upn), so the report archive log was used instead: $($_.Exception.Message)" }
            if ($mode -eq 'archive') {
                if ($crOk) {
                    try { if (Test-RsLogged ([int]$cid) (Get-RsLogKey $u)) { $existing = 'logged' }; $known = $true }
                    catch { Add-RsWarning "Couldn't read the Risky Sign-ins report archive: $($_.Exception.Message)" }
                }
                else { Add-RsWarning "$(Get-PsaName) couldn't be searched for open tickets and there's no CloudRadial company to keep a log in, so $upn couldn't be checked. Set the CloudRadial-CompanyId and CloudRadial-* secrets." }
            }
        }
        $r.dedupe = $mode
        if ($existing) {
            $r.outcome = 'already-open'; $r.ticket_id = $(if ($existing -eq 'logged') { '' } else { $existing })
            $null = $responses.Add($r); continue
        }
        if (-not $known -and -not $preview) {
            $r.outcome = 'error'; $r.errors = @("Couldn't tell whether $upn already has an open ticket, so nothing was done for this user to avoid a duplicate. See the warnings.")
            $null = $responses.Add($r); continue
        }

        # ---- Preview: say what would happen ----
        $mgr = Get-RsProp $u 'manager'
        $mgrMail = [string](Get-RsProp $mgr 'mail')
        if ($preview) {
            $plan = @("Open a $prio-priority ticket '$(Get-RsMarker $upn): Microsoft flagged $($r.risk_level) risk'", "Sign $upn out of every session")
            $plan += $(if ($synced) { 'Skip the password change (synced from on-premises; reset it there)' } else { "Require $upn to change their password at next sign-in" })
            $plan += 'Add an internal note with the risk detail'
            $plan += $(if (-not $notify) { 'Skip the manager email (notify_manager is false)' } elseif (-not $mgrMail) { 'Skip the manager email (no manager with a mailbox)' } elseif (-not $mailbox) { 'Skip the manager email (no Notify-FromMailbox secret)' } else { "Email the manager ($mgrMail)" })
            $r.outcome = 'would-handle'; $r.planned = @($plan)
            $null = $responses.Add($r); continue
        }

        # ---- 2. Ticket ----
        $done = @()
        $summary = "$(Get-RsMarker $upn): Microsoft flagged $($r.risk_level) risk"
        $desc = "Microsoft Entra ID Protection flagged $name ($upn) as $($r.risk_level) risk. This ticket was opened automatically. The user was signed out of all sessions and asked to set a new password at next sign-in where Microsoft 365 allows it. The risk details are in an internal note. Please review the activity with the user and decide whether the account should be blocked."
        if ($isAdmin) { $desc += ' This account holds an admin role, so the ticket is critical.' }
        try { $t = New-PsaTicket -CompanyId $psaCompany -Summary $summary -Description $desc -Priority $prio; $r.ticket_id = [string]$t.id; $done += "Opened $prio-priority ticket $($t.id)." }
        catch { $r.errors = @(@($r.errors) + "Couldn't open a ticket: $($_.Exception.Message)") }

        # ---- 3. Sign out everywhere ----
        try { Revoke-GraphSessions -UserId $uid; $r.revoked = 'done'; $done += 'Signed the user out of every session.' }
        catch { $r.revoked = 'failed'; $r.errors = @(@($r.errors) + "Couldn't sign the user out: $($_.Exception.Message)"); $done += "Signing the user out failed: $($_.Exception.Message)" }

        # ---- 4. Password change at next sign-in ----
        if ($synced) { $r.password = 'skipped-synced'; $done += 'Did not require a password change: the account is synced from on-premises Active Directory.' }
        else {
            try {
                $null = Invoke-Graph -Method PATCH -Path "/v1.0/users/$uid" -Body @{ passwordProfile = @{ forceChangePasswordNextSignIn = $true } } -Permission 'User.ReadWrite.All'
                $r.password = 'required'; $done += 'Required a password change at next sign-in.'
            }
            catch {
                $why = [string]$_.Exception.Message
                if ($isAdmin -and $why -match '\(403 Forbidden\)') {
                    # Expected: app permissions can't change a privileged user's password settings.
                    $r.password = 'manual-admin'
                    $done += 'Did not require a password change: Microsoft 365 does not let an app change an admin''s password settings. Reset this admin''s password by hand.'
                    Add-RsWarning "$upn holds an admin role, so Microsoft 365 wouldn't let the automation require a password change. Reset it by hand (ticket $($r.ticket_id))."
                }
                else { $r.password = 'failed'; $r.errors = @(@($r.errors) + "Couldn't require a password change: $why"); $done += "Requiring a password change failed: $why" }
            }
        }

        # ---- 5. Internal note with the risk detail ----
        $note = Get-RsNote $u $done $mode
        $r.note = $note
        if ($r.ticket_id) {
            try { $null = Add-PsaNote -Id $r.ticket_id -Text $note -Title 'Risky sign-in detail' -Marker "risky-signin: $($r.ticket_id)" }
            catch { Add-RsWarning "Couldn't add the internal note to ticket $($r.ticket_id): $($_.Exception.Message) The detail is in this run's internal_note." }
        }

        # ---- 6. Manager email (no risk detail) ----
        if (-not $r.ticket_id) { $r.manager_mail = 'skipped: no ticket was opened' }
        elseif (-not $notify) { $r.manager_mail = 'skipped: notify_manager is false' }
        elseif (-not $mgrMail) { $r.manager_mail = 'skipped: no manager with a mailbox'; Add-RsWarning "$upn has no manager with a mailbox in Microsoft 365, so no manager was emailed." }
        elseif (-not $mailbox) { $r.manager_mail = 'skipped: no Notify-FromMailbox secret' }
        else {
            $mgrName = [string](Get-RsProp $mgr 'name'); if (-not $mgrName) { $mgrName = 'there' }
            $pw = if ($r.password -eq 'required') { ' and they will be asked to set a new password the next time they sign in' } else { '' }
            $body = "Hello $mgrName,`n`nMicrosoft flagged unusual sign-in activity on $name's account. As a precaution we signed them out of their devices$pw. Our team has opened a ticket and is looking into it.`n`nYou don't need to do anything. If $name mentions a sign-in they didn't make, or can't get back in, please let us know.`n`nThank you"
            $msg = @{ message = @{ subject = "Security check on $name's account"; body = @{ contentType = 'Text'; content = $body }; toRecipients = @(@{ emailAddress = @{ address = $mgrMail } }) }; saveToSentItems = $false }
            try { $null = Invoke-Graph -Method POST -Path "/v1.0/users/$([uri]::EscapeDataString($mailbox))/sendMail" -Body $msg -Permission 'Mail.Send'; $r.manager_mail = "sent to $mgrMail" }
            catch { $r.manager_mail = 'failed'; Add-RsWarning "Couldn't email the manager of $($upn): $($_.Exception.Message)" }
        }

        # ---- 7. Archive log when the PSA can't be searched ----
        if ($mode -eq 'archive' -and $r.ticket_id) {
            $html = "<p>Handled risky user $([System.Net.WebUtility]::HtmlEncode($upn)) on $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC. $(Get-PsaName) ticket $([System.Net.WebUtility]::HtmlEncode($r.ticket_id)). Risk last updated $([System.Net.WebUtility]::HtmlEncode((Get-RsTime $u 'risk_updated'))).</p><p>Detection ids: $([System.Net.WebUtility]::HtmlEncode((@(Get-RsProp $u 'detections' | Where-Object { $null -ne $_ } | ForEach-Object { Get-RsProp $_ 'id' }) -join ', ')))</p><p>The risk detail is in the ticket's internal note.</p>"
            try { $null = Add-CrArchiveReport -CompanyId ([int]$cid) -ArchiveName 'Risky Sign-ins' -Subject (Get-RsLogKey $u) -Html $html -Category 'Security' }
            catch { Add-RsWarning "Couldn't log $upn as handled in the Risky Sign-ins archive, so the next run may open a second ticket: $($_.Exception.Message)" }
        }

        $r.outcome = $(if (@($r.errors).Count) { 'error' } else { 'handled' })
        $null = $responses.Add($r)
    }
}

$rs['responses'] = @($responses)
Set-NodeOutput $rs
