# === Step 1: Verify the caller ===
# Edit this file, then run: node verify-the-caller/src/build.js
# action=send: sends a one-time 6-digit code to the ticket contact's email (Postmark) and/or mobile (Twilio), read
#   from the contact record in the PSA, never from the request. Adds an internal note holding the masked
#   destination, the expiry and an HMAC of the code (keyed by the VerifyCaller-Key secret), never the code.
# action=check: checks the code the caller read back against the newest send note, with a 10-minute expiry and
#   3 failed tries per code, and logs the result as an internal note.
# confirm=false (the default) is a preview: nothing is sent, checked or written.
# Accepts a flat {key:value} body (ServiceAI Action, manual run), the CloudRadial {Ticket:{...}} shape, or either
# one wrapped in {trigger:...}. Supported PSAs: ConnectWise PSA, Autotask and HaloPSA.
$ErrorActionPreference = 'Stop'

function Get-Prop { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
$Vc = @{ done = $false; ticket = ''; action = ''; code = ''; expiryMinutes = 10; maxTries = 3; maxSends = 3; sendWindowMinutes = 15 }
$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
$counts = [ordered]@{ emails_sent = 0; texts_sent = 0; notes_written = 0 }
# Anything that might carry the code (a vendor error, say) passes through here before it is output.
function Hide-VcCode { param([string]$s) if (-not $s) { return '' }; if ($Vc.code) { $s = $s.Replace($Vc.code, '******') }; return $s }
function Get-AllWarnings {
    $all = New-Object System.Collections.ArrayList
    foreach ($w in @(@($warnings) + @($PsaState.Warnings))) { $t = Hide-VcCode ([string]$w); if ($t -and -not $all.Contains($t)) { $null = $all.Add($t) } }
    return @($all)
}
function Write-VcOutput {
    param([string]$Status, [string]$Message, [string]$Note = '', $Verified = $false, [string]$Masked = '', [string]$Expires = '')
    $Vc.done = $true
    $m = Hide-VcCode $Message
    Set-NodeOutput ([ordered]@{
            status = $Status; message = $m; public_note = ''; internal_note = (Hide-VcCode $Note)
            ticket_id = $Vc.ticket; action = $Vc.action; verified = [bool]$Verified; destination_masked = $Masked; expires_utc = $Expires
            actions = @($actions | ForEach-Object { Hide-VcCode ([string]$_) }); warnings = @(Get-AllWarnings); counts = $counts; chatReply = $m
        })
}
function Stop-Run {
    param([string]$Status, [string]$Why)
    Write-VcOutput $Status $Why
    throw (Hide-VcCode $Why)
}
trap { if (-not $Vc.done) { Write-VcOutput 'error' "Verify the Caller failed: $($_.Exception.Message)" }; break }

# ---- the request ----
$raw = Get-NodeInput
if ($null -eq $raw) { Stop-Run 'incomplete' 'No input was received. Send at least ticket_id.' }
if ($raw -is [string]) { try { $raw = $raw | ConvertFrom-Json } catch { Stop-Run 'incomplete' 'The input was text that is not valid JSON.' } }
$wrap = Get-Prop $raw 'trigger'; if ($null -ne $wrap) { $raw = $wrap; if ($raw -is [string]) { try { $raw = $raw | ConvertFrom-Json } catch { Stop-Run 'incomplete' 'The trigger body was text that is not valid JSON.' } } }
$answers = @{}
if ($raw -is [System.Collections.IDictionary]) { foreach ($k in @($raw.Keys)) { $answers[[string]$k] = $raw[$k] } }
else { foreach ($p in $raw.PSObject.Properties) { $answers[$p.Name] = $p.Value } }
$crTicket = Get-Prop $raw 'Ticket'
if ($null -ne $crTicket) {
    foreach ($q in @(Get-Prop $crTicket 'Questions')) { $qid = [string](Get-Prop $q 'Id'); if ($qid) { $answers[$qid] = Get-Prop $q 'Value' } }
    $tid = Get-Prop $crTicket 'TicketId'; if ($null -ne $tid) { $answers['ticket_id'] = $tid }
}
# ServiceAI leaves unfilled placeholders (<code>, {{code}}, @code) in the body: they count as not given.
function Get-Field {
    param([string[]]$Names)
    foreach ($n in $Names) {
        if (-not $answers.ContainsKey($n)) { continue }
        $v = $answers[$n]
        if ($null -eq $v -or $v -is [System.Management.Automation.PSCustomObject] -or $v -is [System.Collections.IDictionary]) { continue }
        $s = ([string]$v).Trim()
        if (-not $s -or $s.StartsWith('@') -or $s -match '^\{\{.*\}\}$' -or $s -match '^<[^>]*>$') { continue }
        return $s
    }
    return ''
}
function Get-Flag { param([string[]]$Names, [bool]$Default) $s = (Get-Field $Names).ToLowerInvariant(); if (-not $s) { return $Default }; return (@('true', 'yes', '1', 'y') -contains $s) }

$ticketRef = Get-Field @('ticket_id', 'ticketId', 'TicketId', 'ticketNumber')
$Vc.ticket = $ticketRef
$action = (Get-Field @('action')).ToLowerInvariant(); if (-not $action) { $action = 'send' }
$Vc.action = $action
$channel = (Get-Field @('channel')).ToLowerInvariant(); if (-not $channel) { $channel = 'email' }
$confirm = Get-Flag @('confirm') $false
$psaAsked = Get-Field @('psa')
if (-not $ticketRef) { Stop-Run 'incomplete' 'ticket_id is missing. Send the PSA ticket number. Nothing was sent.' }
if (@('send', 'check') -notcontains $action) { Stop-Run 'incomplete' "action must be send or check; '$action' isn't. Nothing was sent." }
if (@('email', 'sms', 'both') -notcontains $channel) { Stop-Run 'incomplete' "channel must be email, sms or both; '$channel' isn't. Nothing was sent." }
$codeIn = ''
if ($action -eq 'check') {
    $codeIn = (Get-Field @('code', 'Code', 'verificationCode')) -replace '[\s-]', ''
    if (-not $codeIn) { Stop-Run 'incomplete' 'code is missing. Send the 6-digit code the caller read back. Nothing was checked.' }
    if ($codeIn -notmatch '^\d{6}$') { Stop-Run 'incomplete' 'The code must be 6 digits. Nothing was checked, and no try was used.' }
}

# ---- the key (required before anything is read, sent or written) ----
$key = [string](Get-PsaSecret 'VerifyCaller-Key')
if ([string]::IsNullOrWhiteSpace($key)) { Stop-Run 'error' 'The VerifyCaller-Key secret is missing. Add a random value of at least 32 characters to the runner Key Vault. Nothing was sent.' }
if ($key.Trim().Length -lt 16) { Stop-Run 'error' 'The VerifyCaller-Key secret is too short. Use a random value of at least 32 characters. Nothing was sent.' }
function Get-VcMac {
    param([string]$Nonce, [string]$TicketId, [string]$Code)
    $h = [System.Security.Cryptography.HMACSHA256]::new([System.Text.Encoding]::UTF8.GetBytes($key.Trim()))
    try { $b = $h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$Nonce|$TicketId|$Code")) } finally { $h.Dispose() }
    return ((@($b | ForEach-Object { $_.ToString('x2') })) -join '')
}
function Test-VcSame {
    param([string]$A, [string]$B)
    $x = [System.Text.Encoding]::ASCII.GetBytes($A); $y = [System.Text.Encoding]::ASCII.GetBytes($B)
    $diff = $x.Length -bxor $y.Length
    for ($i = 0; $i -lt [Math]::Min($x.Length, $y.Length); $i++) { $diff = $diff -bor ($x[$i] -bxor $y[$i]) }
    return $diff -eq 0
}

# ---- the ticket ----
$conn = Connect-Psa -Psa (Get-PsaType $psaAsked)
$psaName = Get-PsaName
if (@('connectwise', 'autotask', 'halopsa') -notcontains $conn.Psa) { Stop-Run 'unsupported' "Verify the Caller works with ConnectWise PSA, Autotask and HaloPSA. $psaName isn't supported yet. Nothing was sent." }
$sourceId = ''
try { $sourceId = Resolve-PsaTicketId $ticketRef } catch { Stop-Run 'incomplete' "Ticket $ticketRef wasn't found in $($psaName): $($_.Exception.Message)" }
$t = $null
try { $t = Get-PsaTicket -Id $sourceId } catch { Stop-Run 'incomplete' "Ticket $ticketRef couldn't be read from $($psaName): $($_.Exception.Message)" }
$notes = @()
try { $notes = @(Get-PsaTicketNotes -Id $sourceId -TextOnly | Where-Object { $null -ne $_ }) } catch { Stop-Run 'error' "The notes on ticket $ticketRef couldn't be read from $($psaName): $($_.Exception.Message)" }
$null = $actions.Add("Read ticket $ticketRef from $psaName.")

# The send notes on this ticket, newest first: @{ nonce; mac; expires; created; masked }.
$sendRx = "\[verify-caller $([regex]::Escape($sourceId))-([0-9a-f]{16})\]"
$sends = @(foreach ($n in $notes) {
        $tx = [string]$n['text']
        $m = [regex]::Match($tx, $sendRx); if (-not $m.Success) { continue }
        $mac = [regex]::Match($tx, 'Check value: ([0-9a-f]{64})'); $ex = [regex]::Match($tx, 'expires (\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)')
        if (-not $mac.Success -or -not $ex.Success) { continue }
        $to = [regex]::Match($tx, 'was sent (.+?) \(the contact')
        [pscustomobject]@{ nonce = $m.Groups[1].Value; mac = $mac.Groups[1].Value; expires = [datetime]::Parse($ex.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal); created = $n['created']; id = [string]$n['id']; masked = $(if ($to.Success) { $to.Groups[1].Value } else { '' }) }
    })
$sends = @($sends | Sort-Object -Property @{ Expression = { if ($_.created) { $_.created } else { [datetime]::MinValue } } }, @{ Expression = { $n = 0L; [void][long]::TryParse($_.id, [ref]$n); $n } } -Descending)
$now = (Get-Date).ToUniversalTime()

# ---------------------------------------------------------------- check ----
if ($action -eq 'check') {
    if (-not $sends.Count) {
        $why = "No verification code has been sent on ticket $ticketRef, so there's nothing to check. Run Verify the Caller with action send first."
        if ($confirm) {
            $note = "Caller verification check on ticket $ticketRef`: no code had been sent, so the caller was not verified."
            $null = Add-PsaNote -Id $sourceId -Text $note -Title 'Caller verification' -Internal -Marker "verify-caller-result $sourceId-none-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
            $counts.notes_written++; $null = $actions.Add('Logged the check as an internal note.')
            Write-VcOutput 'success' "Not verified: $why" $note $false; return
        }
        Write-VcOutput 'pending_confirmation' "Preview: $why" '' $false; return
    }
    $s = $sends[0]
    $resRx = "\[verify-caller-result $([regex]::Escape($sourceId))-$($s.nonce)-a(\d+)\]"
    $results = @(foreach ($n in $notes) { $tx = [string]$n['text']; $m = [regex]::Match($tx, $resRx); if ($m.Success) { [pscustomobject]@{ n = [int]$m.Groups[1].Value; text = $tx } } })
    $failed = @($results | Where-Object { $_.text -match 'Result: failed' }).Count
    $used = @($results | Where-Object { $_.text -match 'Result: verified' }).Count -gt 0
    $attempt = 1 + @($results | ForEach-Object { $_.n } | Measure-Object -Maximum).Maximum
    if ($null -eq $attempt -or $attempt -lt 1) { $attempt = 1 }
    $expiresIso = $s.expires.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    if ($used) { Write-VcOutput 'success' "The newest code on ticket $ticketRef was already used to verify the caller. A code works once; send a new one to verify again." '' $false $s.masked $expiresIso; return }
    if (-not $confirm) { Write-VcOutput 'pending_confirmation' "Preview: the code would be checked against the one sent $($s.masked) (expires $expiresIso UTC; $failed of $($Vc.maxTries) tries used). Nothing was checked or written; run again with confirm true." '' $false $s.masked $expiresIso; return }
    $result = ''; $verified = $false; $line = ''
    if ($failed -ge $Vc.maxTries) { $result = 'locked'; $line = "Result: locked. The code had already failed $($Vc.maxTries) times, so this try was not checked. Send a new code." }
    elseif ($now -gt $s.expires) { $result = 'expired'; $line = "Result: expired. The code expired at $expiresIso UTC, so it was not checked. Send a new code." }
    elseif (Test-VcSame (Get-VcMac $s.nonce $sourceId $codeIn) $s.mac) { $result = 'verified'; $verified = $true; $line = 'Result: verified. The caller read back the code sent to the contact on this ticket.' }
    else {
        $result = 'failed'; $left = $Vc.maxTries - ($failed + 1)
        $line = "Result: failed (try $($failed + 1) of $($Vc.maxTries)). $(if ($left -gt 0) { "$left tr$(if ($left -eq 1) { 'y' } else { 'ies' }) left." } else { 'No tries left: send a new code to try again.' })"
    }
    $head = if ($verified) { "Caller verified on ticket $ticketRef." } else { "Caller NOT verified on ticket $ticketRef." }
    $note = "$head`n$line`nCode sent $($s.masked). Checked $($now.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)) by Verify the Caller."
    $r = Add-PsaNote -Id $sourceId -Text $note -Title 'Caller verification' -Internal -Marker "verify-caller-result $sourceId-$($s.nonce)-a$attempt"
    if ($r -eq 'written') { $counts.notes_written++; $null = $actions.Add('Logged the result as an internal note.') }
    $msg = switch ($result) {
        'verified' { "Verified: the caller read back the right code. The result is logged on ticket $ticketRef." }
        'failed' { "Not verified: the code doesn't match. $(($line -split '\. ', 2)[1])" }
        'expired' { "Not verified: the code expired at $expiresIso UTC. Send a new code." }
        'locked' { "Not verified: the code has failed $($Vc.maxTries) times and is locked. Send a new code." }
    }
    Write-VcOutput 'success' $msg $note $verified $s.masked $expiresIso
    return
}

# ---------------------------------------------------------------- send ----
# Guard against flooding the client: at most maxSends codes per ticket in sendWindowMinutes.
$recent = @($sends | Where-Object { $_.expires -gt $now.AddMinutes($Vc.expiryMinutes - $Vc.sendWindowMinutes) })
if ($recent.Count -ge $Vc.maxSends) { Stop-Run 'rejected' "$($recent.Count) codes were already sent on ticket $ticketRef in the last $($Vc.sendWindowMinutes) minutes. Wait a few minutes before sending another. Nothing was sent." }

# The ticket's contact, read from the PSA. The code goes only to the email and mobile on that record.
$traw = $t['raw']
$contact = @{ id = ''; name = ''; email = ''; mobile = ''; active = $true }
switch ($conn.Psa) {
    'connectwise' {
        $contact.id = [string](Get-PsaPath $traw 'contact.id')
        if (-not (Test-PsaBlank $contact.id)) {
            # Vendor docs: GET /company/contacts/{id}; email and phones are communicationItems.
            # Unverified: a mobile is a Phone item whose type name says Mobile or Cell.
            $c = Invoke-PsaRead "/company/contacts/$($contact.id)" 'read the ticket contact' 'read company contacts'
            $contact.name = "$(Get-PsaProp $c 'firstName') $(Get-PsaProp $c 'lastName')".Trim()
            $contact.active = (Get-PsaProp $c 'inactiveFlag') -ne $true
            $items = @(Get-PsaProp $c 'communicationItems' | Where-Object { $null -ne $_ })
            $em = @(@($items | Where-Object { [string](Get-PsaProp $_ 'communicationType') -eq 'Email' -and (Get-PsaProp $_ 'defaultFlag') -eq $true }) + @($items | Where-Object { [string](Get-PsaProp $_ 'communicationType') -eq 'Email' })) | Select-Object -First 1
            if ($em) { $contact.email = [string](Get-PsaProp $em 'value') }
            $mo = @($items | Where-Object { [string](Get-PsaProp $_ 'communicationType') -eq 'Phone' -and [string](Get-PsaPath $_ 'type.name') -match '(?i)mobile|cell' }) | Select-Object -First 1
            if ($mo) { $contact.mobile = [string](Get-PsaProp $mo 'value') }
        }
    }
    'autotask' {
        $contact.id = [string](Get-PsaProp $traw 'contactID')
        if (-not (Test-PsaBlank $contact.id)) {
            # Vendor docs: GET /Contacts/{id} returns { item } with emailAddress, mobilePhone and isActive.
            $c = Get-PsaProp (Invoke-PsaRead "/Contacts/$($contact.id)" 'read the ticket contact' 'read contacts') 'item'
            $contact.name = "$(Get-PsaProp $c 'firstName') $(Get-PsaProp $c 'lastName')".Trim()
            $contact.active = [string](Get-PsaProp $c 'isActive') -ne '0' -and (Get-PsaProp $c 'isActive') -ne $false
            $contact.email = [string](Get-PsaProp $c 'emailAddress'); $contact.mobile = [string](Get-PsaProp $c 'mobilePhone')
        }
    }
    'halopsa' {
        $contact.id = [string](Get-PsaProp $traw 'user_id')
        if (-not (Test-PsaBlank $contact.id)) {
            # Unverified: GET /api/Users/{id} with emailaddress, mobilenumber and inactive.
            $c = Invoke-PsaRead "/Users/$($contact.id)" 'read the ticket contact' 'read users'
            $contact.name = [string](Get-PsaProp $c 'name')
            $contact.active = (Get-PsaProp $c 'inactive') -ne $true
            $contact.email = [string](Get-PsaProp $c 'emailaddress'); $contact.mobile = [string](Get-PsaFirst $c @('mobilenumber', 'mobilenumber2', 'mobile'))
        }
    }
}
if (Test-PsaBlank $contact.id) { Stop-Run 'incomplete' "Ticket $ticketRef has no contact in $psaName, so there's nobody to send a code to. Set the ticket's contact first. Nothing was sent." }
if (-not $contact.active) { Stop-Run 'rejected' "The contact on ticket $ticketRef ($($contact.name)) is inactive in $psaName, so no code was sent." }
$null = $actions.Add("Read the ticket contact$(if ($contact.name) { " ($($contact.name))" }) from $psaName.")

function Get-VcMaskedEmail { param([string]$e) $p = $e.Split('@'); if ($p.Count -ne 2) { return '***' }; return "$($p[0].Substring(0, 1))***@$($p[1])" }
function Get-VcMaskedPhone { param([string]$p) $d = $p -replace '\D', ''; if ($d.Length -lt 4) { return '***' }; return "***-***-$($d.Substring($d.Length - 4))" }
# E.164 for Twilio: +digits as stored, or a 10-digit number when the sending number is +1 (North America).
function Get-VcE164 {
    param([string]$p, [string]$From)
    $d = $p -replace '\D', ''
    if ($p.Trim().StartsWith('+') -and $d.Length -ge 8 -and $d.Length -le 15) { return "+$d" }
    if ($p.Trim().StartsWith('00') -and $d.Length -ge 10) { return "+$($d.Substring(2))" }
    if ($From.Trim().StartsWith('+1')) { if ($d.Length -eq 10) { return "+1$d" }; if ($d.Length -eq 11 -and $d.StartsWith('1')) { return "+$d" } }
    return ''
}
$email = $contact.email.Trim(); if ($email -and $email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { $null = $warnings.Add('The contact''s email in the PSA is not a valid address, so it was not used.'); $email = '' }
$tw = @{ sid = [string](Get-PsaSecret 'Twilio-AccountSid'); token = [string](Get-PsaSecret 'Twilio-AuthToken'); from = [string](Get-PsaSecret 'Twilio-FromNumber') }
$twMissing = @(); if ([string]::IsNullOrWhiteSpace($tw.sid)) { $twMissing += 'Twilio-AccountSid' }; if ([string]::IsNullOrWhiteSpace($tw.token)) { $twMissing += 'Twilio-AuthToken' }; if ([string]::IsNullOrWhiteSpace($tw.from)) { $twMissing += 'Twilio-FromNumber' }
$mobile = ''
if ($channel -ne 'email') {
    $why = ''
    if ($twMissing.Count) { $why = "Text messages aren't set up (add the $($twMissing -join ', ') secret$(if ($twMissing.Count -gt 1) { 's' }))." }
    elseif (-not $contact.mobile.Trim()) { $why = "The contact has no mobile number in $psaName." }
    else { $mobile = Get-VcE164 $contact.mobile $tw.from; if (-not $mobile) { $why = "The contact's mobile number in $psaName isn't in international format (+country code), so it can't be texted." } }
    if ($why) {
        if ($channel -eq 'sms') { Stop-Run 'incomplete' "$why No code was sent. Try channel email." }
        $null = $warnings.Add("$why The code went by email only.")
    }
}
$useEmail = $channel -ne 'sms'; $useSms = [bool]$mobile
if ($useEmail -and -not $email) {
    if (-not $useSms) { Stop-Run 'incomplete' "The contact on ticket $ticketRef has no email address in $psaName, so no code was sent.$(if ($channel -eq 'email') { ' Try channel sms if they have a mobile number.' })" }
    $null = $warnings.Add("The contact has no email address in $psaName, so the code went by text only.")
    $useEmail = $false
}
if ($useEmail -and -not (Test-PmConfigured)) {
    if (-not $useSms) { Stop-Run 'incomplete' 'Email isn''t set up (add the Postmark-ServerToken and Postmark-FromEmail secrets). No code was sent.' }
    $null = $warnings.Add('Email isn''t set up (Postmark secrets missing), so the code went by text only.')
    $useEmail = $false
}
$dest = @(); if ($useEmail) { $dest += "by email to $(Get-VcMaskedEmail $email)" }; if ($useSms) { $dest += "by text to $(Get-VcMaskedPhone $mobile)" }
$masked = $dest -join ' and '

if (-not $confirm) {
    $null = $actions.Add("Would send a code $masked.")
    Write-VcOutput 'pending_confirmation' "Preview: a 6-digit code would be sent $masked (the contact on ticket $ticketRef in $psaName). It expires $($Vc.expiryMinutes) minutes after sending. Nothing was sent; run again with confirm true." '' $false $masked
    return
}

# ---- make the code, send it, then record it ----
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $bytes = New-Object byte[] 4; $code = -1
    # Rejection sampling, so every code from 000000 to 999999 is equally likely.
    while ($code -lt 0) { $rng.GetBytes($bytes); $v = [BitConverter]::ToUInt32($bytes, 0); if ($v -lt 4294000000) { $code = $v % 1000000 } }
    $nb = New-Object byte[] 8; $rng.GetBytes($nb)
}
finally { $rng.Dispose() }
$Vc.code = $code.ToString('000000')
$nonce = (@($nb | ForEach-Object { $_.ToString('x2') })) -join ''
$expires = $now.AddMinutes($Vc.expiryMinutes)
$expiresIso = $expires.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
$body = "Your verification code is $($Vc.code). Your technician will ask you for it. It expires in $($Vc.expiryMinutes) minutes. If you didn't contact us, ignore this email."
$sent = @()
if ($useEmail) {
    $pm = Send-PmMail -To @($email) -Subject 'Your verification code' -Text $body -Tag 'verify-caller'
    if ($pm.sent) { $counts.emails_sent++; $sent += "by email to $(Get-VcMaskedEmail $email)" } else { $null = $warnings.Add("The email wasn't sent: $($pm.reason)") }
}
if ($useSms) {
    $smsBody = $body.Replace('ignore this email.', 'ignore this text.')
    $form = "To=$([uri]::EscapeDataString($mobile))&From=$([uri]::EscapeDataString($tw.from.Trim()))&Body=$([uri]::EscapeDataString($smsBody))"
    $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($tw.sid.Trim()):$($tw.token.Trim())"))
    $ok = $false; $why = ''
    for ($i = 1; $i -le 3 -and -not $ok; $i++) {
        try {
            $null = Invoke-RestMethod -Method POST -Uri "https://api.twilio.com/2010-04-01/Accounts/$([uri]::EscapeDataString($tw.sid.Trim()))/Messages.json" -Headers @{ Authorization = "Basic $auth"; Accept = 'application/json' } -Body $form -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
            $ok = $true
        }
        catch {
            $st = 0; try { $st = [int]$_.Exception.Response.StatusCode } catch { }
            if (($st -eq 429 -or $st -ge 500) -and $i -lt 3) { Start-Sleep -Seconds (2 * $i); continue }
            $d = ''; try { if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $d = $_.ErrorDetails.Message } } catch { }
            $msg = $d; try { $j = $d | ConvertFrom-Json -ErrorAction Stop; $mm = Get-Prop $j 'message'; if ($mm) { $msg = [string]$mm } } catch { }
            if (-not $msg) { $msg = [string]$_.Exception.Message }
            $why = if ($st -eq 401) { 'Twilio rejected the account SID or auth token (HTTP 401). Check the Twilio-AccountSid and Twilio-AuthToken secrets.' } else { "Twilio couldn't send the text$(if ($st) { " (HTTP $st)" }): $msg" }
            break
        }
    }
    if ($ok) { $counts.texts_sent++; $sent += "by text to $(Get-VcMaskedPhone $mobile)" } else { $null = $warnings.Add("The text wasn't sent: $why") }
}
if (-not $sent.Count) { Stop-Run 'error' "The code couldn't be sent, so nothing was written to ticket $ticketRef. $(@($warnings) -join ' ')" }
$masked = $sent -join ' and '
$null = $actions.Add("Sent a one-time code $masked.")
$mac = Get-VcMac $nonce $sourceId $Vc.code
$note = "Caller verification: a one-time code was sent $masked (the contact on this ticket, from $psaName).`nAsk the caller to read the 6-digit code back, then run Verify the Caller with action check and the code. It works once, allows $($Vc.maxTries) tries, and a new code replaces this one.`nThe code itself is not stored. Check value: $mac; expires $expiresIso"
try { $r = Add-PsaNote -Id $sourceId -Text $note -Title 'Caller verification' -Internal -Marker "verify-caller $sourceId-$nonce" }
catch { Stop-Run 'error' "The code was sent $masked, but the note that records it couldn't be added, so it can't be checked: $($_.Exception.Message) Send a new code." }
$counts.notes_written++; $null = $actions.Add('Recorded the code''s check value as an internal note (not the code).')
Write-VcOutput 'success' "A 6-digit code was sent $masked. Ask the caller to read it back, then run Verify the Caller with action check. It expires at $expiresIso UTC." $note $false $masked $expiresIso
