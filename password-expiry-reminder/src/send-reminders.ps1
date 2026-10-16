# === NODE: Send reminders ===
# Emails each person found by the step before. With preview true it lists them and sends nothing.
# Sends through Microsoft Graph as the mailbox in the PasswordExpiry-Sender secret (needs Mail.Send; a copy is
# kept in that mailbox's Sent Items). When that secret isn't set, it sends through Postmark when the
# Postmark-ServerToken and Postmark-FromEmail secrets are set. The email never contains a password.
# One failed email is counted and the rest still go out; a missing permission or sender mailbox stops the
# sending and counts the rest as failed.
# Safe to rerun the same day through Graph: before sending, it reads the sender's Sent Items since midnight
# (in timeZone; needs Mail.ReadBasic.All) and skips anyone who already got today's reminder. Without that
# permission it warns and sends anyway. Postmark has no such check, so a second Postmark run the same day sends again.
$ErrorActionPreference = 'Stop'

function New-PeMail {
    param($p, [string]$ResetUrl)
    $days = [int](Get-PeProp $p 'daysLeft')
    $when = if ($days -le 0) { 'today' } elseif ($days -eq 1) { 'tomorrow' } else { "in $days days" }
    $first = [string](Get-PeProp $p 'firstName'); if (-not $first.Trim()) { $first = 'there' }
    $subject = "Your Microsoft 365 password expires $when"
    $lines = @(
        "Hello $($first.Trim()),"
        ''
        "The Microsoft 365 password for $(Get-PeProp $p 'upn') expires $when, on $(Get-PeProp $p 'expiresText'). Please change it before then so you aren't locked out of your email, Teams and files."
        ''
        'You can change it in any of these ways:'
        '- On a work Windows PC you sign in to with this account, press Ctrl+Alt+Del and choose Change a password.'
        '- In Outlook on the web (https://outlook.office.com), select your picture or initials at the top right, choose View account, then Password.'
        "- Go to $ResetUrl and follow the steps."
        ''
        'Choose a new password you have not used before. After you change it, sign in again with the new password on your phone and any other devices.'
        ''
        "IT will never ask you for your password, by email, phone or chat. If you aren't sure this message is genuine, don't use the link: open Outlook on the web yourself, or contact your IT support team."
        ''
        'Thank you,'
        'Your IT support team'
    )
    return @{ subject = $subject; text = ($lines -join "`n"); when = $when }
}

$st = Read-PeState
if ([bool]$st['done']) { Set-NodeOutput $st; return }
$opt = $st['inputs']
$preview = [bool](Get-PeProp $opt 'preview')
$resetUrl = [string](Get-PeProp $opt 'resetUrl')
$counts = $st['counts']
$due = @($st['due'] | ForEach-Object { ConvertTo-PeHash $_ })
foreach ($p in $due) { $p['expires'] = Format-PeIso $p['expires'] }
$st['preview'] = $preview

$sender = Get-PeSecret @('PasswordExpiry-Sender')
$via = ''
if ($sender) { $via = 'graph' } elseif (Test-PmConfigured) { $via = 'postmark' }
$st['sent_via'] = $(if ($via -eq 'graph') { "Microsoft Graph as $sender" } elseif ($via -eq 'postmark') { 'Postmark' } else { '' })
$noSender = 'Add the PasswordExpiry-Sender secret (the mailbox to send from, with the Mail.Send permission) or the Postmark-ServerToken and Postmark-FromEmail secrets.'

if (-not $due.Count) {
    $st['status'] = 'success'
    $st['message'] = "Checked $(Get-PePlural $counts.checked 'account' 'accounts'). Nobody is on a reminder day today, so no email was sent."
    Set-NodeOutput $st
    return
}

$names = @($due | ForEach-Object { "$($_['upn']) ($(Get-PePlural ([int]$_['daysLeft']) 'day' 'days'))" })
if ($preview) {
    foreach ($p in $due) { $p['result'] = 'would be emailed' }
    $st['due'] = @($due)
    $st['status'] = 'pending_confirmation'
    $st['message'] = "Preview: $(Get-PePlural $due.Count 'person' 'people') would be emailed today: $(Join-PeNames $names). Nothing was sent."
    if (-not $via) { $st['warnings'] = @(@($st['warnings']) + "No way to send email is set up yet, so a live run would stop. $noSender") }
    $st['actions'] = @(@($st['actions']) + "Preview only: $(Get-PePlural $due.Count 'reminder' 'reminders') not sent.")
    Set-NodeOutput $st
    return
}
if (-not $via) { Stop-PeRun $st 'error' "$(Get-PePlural $due.Count 'person is' 'people are') due a password reminder, but no way to send email is set up. $noSender No email was sent." }
if ($via -eq 'graph') {
    try { $null = Connect-Graph } catch { Stop-PeRun $st 'error' "Couldn't sign in to Microsoft 365 to send the reminders: $($_.Exception.Message) No email was sent." }
}

# Who already got a reminder today (Graph only), so a rerun or an Action Runs Retry doesn't email them twice.
$sentToday = @{}
if ($via -eq 'graph') {
    $tzId = [string](Get-PeProp $opt 'timeZone'); if (-not $tzId) { $tzId = 'UTC' }
    $tz = [TimeZoneInfo]::FindSystemTimeZoneById($tzId)
    $localMidnight = [TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $tz).Date
    $sinceUtc = [TimeZoneInfo]::ConvertTimeToUtc([datetime]::SpecifyKind($localMidnight, [DateTimeKind]::Unspecified), $tz).ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    try {
        $sentPath = "/v1.0/users/$(ConvertTo-GraphId $sender)/mailFolders/sentitems/messages?`$filter=$([uri]::EscapeDataString("sentDateTime ge $sinceUtc"))&`$select=subject,toRecipients&`$top=100"
        foreach ($msg in @(Get-GraphAll -Path $sentPath -Permission 'Mail.ReadBasic.All')) {
            if (-not ([string](Get-GraphProp $msg 'subject')).StartsWith('Your Microsoft 365 password expires')) { continue }
            foreach ($r in @(Get-GraphProp $msg 'toRecipients')) { $a = [string](Get-GraphProp (Get-GraphProp $r 'emailAddress') 'address'); if ($a) { $sentToday[$a.ToLowerInvariant()] = $true } }
        }
    }
    catch { $st['warnings'] = @(@($st['warnings']) + "Couldn't check $sender's Sent Items for reminders already sent today, so a second run today would email people again. Add the Mail.ReadBasic.All application permission to make reruns safe. ($($_.Exception.Message))") }
}

$emailed = New-Object System.Collections.ArrayList
$acts = @($st['actions'])
$stopWhy = ''
foreach ($p in $due) {
    $to = [string]$p['mail']
    if ($sentToday.ContainsKey($to.ToLowerInvariant())) { $p['result'] = 'already emailed today'; $counts.alreadySentToday++; $acts += "Skipped ${to}: already got today's reminder."; continue }
    if ($stopWhy) { $p['result'] = 'not sent'; $counts.failed++; $acts += "Didn't email ${to}: $stopWhy"; continue }
    $m = New-PeMail $p $resetUrl
    $ok = $false; $why = ''
    if ($via -eq 'graph') {
        $msg = @{ message = @{ subject = $m.subject; body = @{ contentType = 'Text'; content = $m.text }; toRecipients = @(@{ emailAddress = @{ address = $to; name = [string]$p['name'] } }) }; saveToSentItems = $true }
        try { $null = Invoke-Graph -Method POST -Path "/v1.0/users/$(ConvertTo-GraphId $sender)/sendMail" -Body $msg -Permission 'Mail.Send'; $ok = $true }
        catch {
            $why = [string]$_.Exception.Message
            if ($GraphState.LastStatus -eq 403) { $stopWhy = "the app registration can't send as $sender. It needs the Mail.Send application permission, with admin consent (and, if an application access policy limits it, access to that mailbox)." }
            elseif ($GraphState.LastStatus -eq 404) { $stopWhy = "the sender mailbox $sender wasn't found. Check the PasswordExpiry-Sender secret: it must be a licensed mailbox in this tenant." }
            if ($stopWhy) { $why = $stopWhy }
        }
    }
    else {
        $r = Send-PmMail -To $to -Subject $m.subject -Text $m.text -Tag 'password-expiry'
        if ($r.sent) { $ok = $true } else { $why = [string]$r.reason }
    }
    if ($ok) {
        $p['result'] = 'emailed'; $counts.emailed++
        $null = $emailed.Add([ordered]@{ upn = [string]$p['upn']; mail = $to; daysLeft = [int]$p['daysLeft']; expires = (Format-PeIso $p['expires']) })
        $acts += "Emailed ${to}: the password expires $($m.when), on $($p['expiresText'])."
    }
    else { $p['result'] = 'failed'; $counts.failed++; $acts += "Couldn't email ${to}: $why" }
}

$st['due'] = @($due)
$st['emailed'] = @($emailed)
$st['actions'] = @($acts)
$sentNames = @($emailed | ForEach-Object { "$($_['upn']) ($(Get-PePlural ([int]$_['daysLeft']) 'day' 'days'))" })
$msgText = "Emailed $(Get-PePlural $counts.emailed 'person' 'people') whose Microsoft 365 password expires soon$(if ($sentNames.Count) { ": $(Join-PeNames $sentNames)" })."
if ($counts.alreadySentToday) { $msgText += " $(Get-PePlural $counts.alreadySentToday 'person' 'people') already had today's reminder, so $(if ($counts.alreadySentToday -eq 1) { 'was' } else { 'were' }) not emailed again." }
if ($counts.failed) {
    $st['status'] = 'incomplete'
    $msgText += " $(Get-PePlural $counts.failed 'email' 'emails') couldn't be sent$(if ($stopWhy) { ": $stopWhy" } else { '; see actions.' })"
}
else { $st['status'] = 'success' }
$st['message'] = $msgText
Set-NodeOutput $st
