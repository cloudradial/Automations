# Strict-mode harness for Verify the Caller. Runs the PowerShell step exactly as shipped in ../verify-the-caller.yml
# (via build.js --dump) through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, against the
# mock PSAs, Postmark and Twilio in mock-psa.ps1. The code a contact "received" is read from the captured email or
# text, and every output and note is checked for it.
# Placeholder data only (Contoso, Example MSP).
# Usage: pwsh -NoProfile -File test.ps1      (needs node and js-yaml: npm install in _shared, or set JS_YAML_PATH)
. (Join-Path $PSScriptRoot 'mock-psa.ps1')

& node (Join-Path $PSScriptRoot 'build.js') --check
Check 'the .yml matches the source (build.js --check)' ($LASTEXITCODE -eq 0)
Import-Steps (Join-Path $PSScriptRoot 'build.js')
Check 'one PowerShell step' (($MockSteps.Keys -join ',') -eq 'node-verify') ($MockSteps.Keys -join ', ')

# Every output and every note seen in the run, to prove no code ever leaks into them.
$Seen = @{ codes = (New-Object System.Collections.ArrayList); text = (New-Object System.Collections.ArrayList) }
function Run {
    param($In)
    $null = Get-ThrowMessage { Invoke-Step 'node-verify' ([pscustomobject]$In) }
    $o = $MockHarness.Output
    if ($null -ne $o) { $null = $Seen.text.Add(($o | ConvertTo-Json -Depth 10 -Compress)) }
    return $(if ($null -eq $o) { $null } else { $o | ConvertTo-Json -Depth 10 | ConvertFrom-Json })
}
function Get-LastCode {
    $all = @(@($MockWorld.emails | ForEach-Object { $_.Text }) + @($MockWorld.texts | ForEach-Object { $_.Text }))
    if (-not $all.Count) { return '' }
    $m = [regex]::Match([string]$all[-1], 'code is (\d{6})\.'); if ($m.Success) { $null = $Seen.codes.Add($m.Groups[1].Value); return $m.Groups[1].Value }; return ''
}
function Get-NoteCount { param([string]$Like) return @(Get-WorldNotes | Where-Object { $_ -like $Like }).Count }
function Close-World { foreach ($n in @(Get-WorldNotes)) { $null = $Seen.text.Add([string]$n) } }
function Send { param([string]$Channel = 'email', [bool]$Confirm = $true) return Run @{ ticket_id = '301'; action = 'send'; channel = $Channel; confirm = $(if ($Confirm) { 'true' } else { 'false' }) } }
function Test-Code { param([string]$Code, [bool]$Confirm = $true) return Run @{ ticket_id = '301'; action = 'check'; code = $Code; confirm = $Confirm } }
function Get-WrongCode { param([string]$Code) return ((([int]$Code) + 1) % 1000000).ToString('000000') }

# ---- 1. The whole flow on each supported PSA ----
foreach ($psa in @('connectwise', 'autotask', 'halopsa')) {
    Reset-World $psa
    $p = Send -Confirm $false
    Check "$psa preview send: nothing sent or written, says where it would go" ($p.status -eq 'pending_confirmation' -and @(Get-Writes).Count -eq 0 -and $MockWorld.emails.Count -eq 0 -and $p.destination_masked -eq 'by email to m***@contoso.example') "$($p.status) $($p.destination_masked) $($p.message)"
    $s = Send
    $code = Get-LastCode
    Check "$psa send: one email, to the contact on the ticket only" ($s.status -eq 'success' -and $MockWorld.emails.Count -eq 1 -and $MockWorld.emails[0].To -eq 'megan.bowen@contoso.example' -and $code -match '^\d{6}$' -and $s.counts.emails_sent -eq 1) "$($s.status) $($s.message)"
    Check "$psa send: the email has the agreed wording" ($MockWorld.emails[0].Subject -eq 'Your verification code' -and $MockWorld.emails[0].Text -eq "Your verification code is $code. Your technician will ask you for it. It expires in 10 minutes. If you didn't contact us, ignore this email.") $MockWorld.emails[0].Text
    Check "$psa send: one internal note with the check value, expiry and marker" ((Get-NoteCount '*Check value: *expires 20*') -eq 1 -and (Get-NoteCount '*`[verify-caller 301-*`]*') -eq 1 -and [string]$MockHarness.Output.expires_utc -match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$' -and $s.verified -eq $false) $s.internal_note
    if ($psa -eq 'connectwise') { Check 'cw send: the note is internal' (@(Get-Writes 'POST */service/tickets/301/notes' | Where-Object { $_.Body.internalAnalysisFlag -eq $true -and $_.Body.detailDescriptionFlag -ne $true }).Count -eq 1) '' }
    if ($psa -eq 'autotask') { Check 'autotask send: the note is Internal Only' (@(Get-Writes 'POST */Tickets/301/Notes' | Where-Object { [int]$_.Body.publish -eq 2 }).Count -eq 1) '' }
    if ($psa -eq 'halopsa') { Check 'halo send: the note is hidden from the user' (@(Get-Writes 'POST */api/Actions' | Where-Object { $_.Body[0].hiddenfromuser -eq $true }).Count -eq 1) '' }
    $c = Test-Code $code
    Check "$psa check: the right code verifies and is logged" ($c.status -eq 'success' -and $c.verified -eq $true -and (Get-NoteCount 'Caller verified on ticket 301*Result: verified*') -eq 1 -and $c.destination_masked -eq 'by email to m***@contoso.example') "$($c.status) $($c.verified) $($c.message)"
    Close-World
}

# ---- 2. Wrong codes, lockout, expiry, single use ----
Reset-World 'connectwise'
$null = Send; $code = Get-LastCode; $wrong = Get-WrongCode $code
$c1 = Test-Code $wrong
Check 'wrong code: not verified, try 1 of 3 logged, 2 left' ($c1.verified -eq $false -and $c1.message -like 'Not verified*2 tries left*' -and (Get-NoteCount 'Caller NOT verified*Result: failed (try 1 of 3)*') -eq 1) $c1.message
$null = Test-Code $wrong; $c3 = Test-Code $wrong
Check 'third wrong code: no tries left' ($c3.verified -eq $false -and $c3.message -like '*No tries left*' -and (Get-NoteCount '*Result: failed (try 3 of 3)*') -eq 1) $c3.message
$c4 = Test-Code $code
Check 'after 3 failures even the right code is locked out' ($c4.verified -eq $false -and $c4.message -like '*locked*' -and (Get-NoteCount '*Result: locked*') -eq 1) $c4.message
Check 'every try has its own result note' ((Get-NoteCount '*`[verify-caller-result 301-*-a*`]*') -eq 4) (@(Get-WorldNotes) -join ' || ')
Close-World

Reset-World 'connectwise'
$null = Send; $code = Get-LastCode
$n = @($MockWorld.ticket.notes | Where-Object { $_.text -like '*Check value*' })[0]
$n.text = [regex]::Replace($n.text, 'expires \S+Z', 'expires 2020-01-01T00:00:00Z')
$e = Test-Code $code
Check 'expired code: not verified, says expired, logged' ($e.verified -eq $false -and $e.message -like '*expired at 2020-01-01T00:00:00Z*' -and (Get-NoteCount '*Result: expired*') -eq 1) $e.message
Close-World

Reset-World 'connectwise'
$null = Send; $code = Get-LastCode
$null = Test-Code $code; $before = @(Get-WorldNotes).Count
$u = Test-Code $code
Check 'a used code does not verify twice, and adds no note' ($u.verified -eq $false -and $u.message -like '*already used*' -and @(Get-WorldNotes).Count -eq $before) $u.message
Close-World

# ---- 3. A new code replaces the old one; flooding is refused ----
Reset-World 'connectwise'
$null = Send; $old = Get-LastCode
$null = Send; $new = Get-LastCode
$a = Test-Code $old
Check 'superseded code: the older code no longer works' ($a.verified -eq $false -or $old -eq $new) $a.message
$b = Test-Code $new
Check 'superseded code: the newest code works' ($b.verified -eq $true) $b.message
$null = Send
$f = Send
Check 'a 4th code within 15 minutes is refused, nothing sent' ($f.status -eq 'rejected' -and $MockWorld.emails.Count -eq 3 -and $f.message -like '*Wait a few minutes*') "$($f.status) $($MockWorld.emails.Count)"
Close-World

# ---- 4. Preview never checks a code ----
Reset-World 'connectwise'
$null = Send; $code = Get-LastCode; $w = @(Get-Writes).Count
$pc = Test-Code $code -Confirm $false
Check 'preview check: not evaluated, nothing written, tries untouched' ($pc.status -eq 'pending_confirmation' -and $pc.verified -eq $false -and @(Get-Writes).Count -eq $w -and $pc.message -like '*0 of 3 tries used*') $pc.message
Close-World

Reset-World 'connectwise'
$nc = Test-Code '123456'
Check 'check with no code sent: not verified, logged' ($nc.verified -eq $false -and $nc.message -like '*No verification code has been sent*' -and (Get-NoteCount '*no code had been sent*') -eq 1) $nc.message
Reset-World 'connectwise'
$np = Test-Code '123456' -Confirm $false
Check 'preview check with no code sent: nothing written' ($np.status -eq 'pending_confirmation' -and @(Get-Writes).Count -eq 0) $np.message
$bad = Test-Code '12a456'
Check 'a code that is not 6 digits: incomplete, no try used' ($bad.status -eq 'incomplete' -and @(Get-Writes).Count -eq 0 -and $bad.message -like 'The code must be 6 digits*') $bad.message
$sp = Test-Code '123 456' -Confirm $false
Check 'spaces in the code are ignored' ($sp.status -eq 'pending_confirmation') $sp.message

# ---- 5. Text messages ----
Reset-World 'connectwise'
$bt = Send 'both'; $code = Get-LastCode
Check 'both: one email and one text, to the PSA mobile in E.164' ($bt.status -eq 'success' -and $MockWorld.emails.Count -eq 1 -and $MockWorld.texts.Count -eq 1 -and $MockWorld.texts[0].To -eq '+15550101234' -and $MockWorld.texts[0].From -eq '+15550100000' -and $MockWorld.texts[0].Auth -like 'Basic *') "$($bt.message) $(@($MockWorld.texts | ForEach-Object { $_.To }) -join ',')"
Check 'both: one code in both messages, both destinations masked' ($MockWorld.emails[0].Text -like "*$code*" -and $MockWorld.texts[0].Text -like "*$code*" -and $MockWorld.texts[0].Text -like '*ignore this text.' -and $bt.destination_masked -eq 'by email to m***@contoso.example and by text to ***-***-1234') $bt.destination_masked
Check 'both: the code checks' ((Test-Code $code).verified -eq $true) ''
Close-World

Reset-World 'autotask'
$so = Send 'sms'; $code = Get-LastCode
Check 'sms only: one text, no email, and it checks' ($so.status -eq 'success' -and $MockWorld.texts.Count -eq 1 -and $MockWorld.emails.Count -eq 0 -and (Test-Code $code).verified -eq $true) $so.message
Close-World

Reset-World 'connectwise' -Twilio $false
$x = Send 'sms'
Check 'sms without Twilio secrets: incomplete, names them, nothing sent' ($x.status -eq 'incomplete' -and $x.message -like '*Twilio-AccountSid, Twilio-AuthToken, Twilio-FromNumber*' -and $MockWorld.texts.Count -eq 0 -and @(Get-Writes).Count -eq 0) $x.message
$y = Send 'both'
Check 'both without Twilio: email only, with a warning' ($y.status -eq 'success' -and $MockWorld.emails.Count -eq 1 -and @($y.warnings | Where-Object { $_ -like "Text messages aren't set up*email only*" }).Count -eq 1 -and $y.destination_masked -eq 'by email to m***@contoso.example') ($y.warnings -join ' | ')
Close-World

Reset-World 'connectwise' -Mobile ''
$z = Send 'sms'
Check 'sms with no mobile on the contact: incomplete' ($z.status -eq 'incomplete' -and $z.message -like '*no mobile number*') $z.message
Reset-World 'halopsa' -Mobile '07700 900123'
$MockWorld.secrets['Twilio-FromNumber'] = '+447700900000'
$z2 = Send 'sms'
Check 'a mobile without a country code (non-+1 sender): not texted' ($z2.status -eq 'incomplete' -and $z2.message -like '*international format*') $z2.message
Reset-World 'connectwise'
$MockWorld.twilioFail = 400
$tf = Send 'both'
Check 'Twilio refuses: email still sent, warning has the reason' ($tf.status -eq 'success' -and $tf.counts.texts_sent -eq 0 -and $tf.counts.emails_sent -eq 1 -and @($tf.warnings | Where-Object { $_ -like "The text wasn't sent: Twilio couldn't send the text (HTTP 400): The To number*" }).Count -eq 1) ($tf.warnings -join ' | ')
Close-World
Reset-World 'connectwise'
$MockWorld.twilioFail = 401
$tf2 = Send 'sms'
Check 'sms only and Twilio refuses: error, no note written' ($tf2.status -eq 'error' -and $tf2.message -like '*Twilio-AccountSid and Twilio-AuthToken*' -and (Get-NoteCount '*Check value*') -eq 0) $tf2.message
Close-World

# ---- 6. The contact ----
Reset-World 'connectwise' -NoEmail
$ne = Send 'email'
Check 'no email on the contact: incomplete, suggests sms' ($ne.status -eq 'incomplete' -and $ne.message -like '*no email address*Try channel sms*' -and $MockWorld.emails.Count -eq 0) $ne.message
$nb = Send 'both'
Check 'no email, both: text only, with a warning' ($nb.status -eq 'success' -and $MockWorld.texts.Count -eq 1 -and @($nb.warnings | Where-Object { $_ -like '*no email address*text only*' }).Count -eq 1) ($nb.warnings -join ' | ')
Close-World
Reset-World 'autotask' -NoContact
$nc = Send
Check 'no contact on the ticket: incomplete, nothing sent' ($nc.status -eq 'incomplete' -and $nc.message -like '*has no contact*' -and $MockWorld.emails.Count -eq 0) $nc.message
Reset-World 'halopsa' -NoContact
Check 'halo general user (0) counts as no contact' ((Send).status -eq 'incomplete') ''
Reset-World 'connectwise' -Inactive
$ia = Send
Check 'inactive contact: rejected, nothing sent' ($ia.status -eq 'rejected' -and $MockWorld.emails.Count -eq 0) $ia.message
Reset-World 'connectwise' -Postmark $false
$pm = Send
Check 'email not set up: incomplete, nothing written' ($pm.status -eq 'incomplete' -and $pm.message -like '*Postmark-ServerToken*' -and @(Get-Writes).Count -eq 0) $pm.message
Reset-World 'connectwise'
$MockWorld.postmarkFail = 422
$pf = Send
Check 'Postmark refuses: error, no note written' ($pf.status -eq 'error' -and (Get-NoteCount '*Check value*') -eq 0 -and $pf.message -like "*couldn't be sent*") $pf.message

# ---- 7. The key, the PSA and bad requests ----
Reset-World 'connectwise' -Key ''
$k = Send
Check 'no VerifyCaller-Key: error before anything is read or sent' ($k.status -eq 'error' -and $k.message -like 'The VerifyCaller-Key secret is missing*' -and @(Get-Writes).Count -eq 0 -and $MockWorld.emails.Count -eq 0) $k.message
Reset-World 'connectwise' -Key 'short'
Check 'a short VerifyCaller-Key: error' ((Send).message -like '*too short*') ''
Reset-World 'kaseyabms'
$kb = Send
Check 'Kaseya BMS: unsupported, said plainly' ($kb.status -eq 'unsupported' -and $kb.message -like '*ConnectWise PSA, Autotask and HaloPSA*') $kb.message
Reset-World 'connectwise'
Check 'unknown ticket: incomplete' ((Run @{ ticket_id = '999'; confirm = 'true' }).status -eq 'incomplete') ''
Check 'no ticket_id: incomplete' ((Run @{ action = 'send' }).message -like 'ticket_id is missing*') ''
Check 'ServiceAI placeholder counts as not given' ((Run @{ ticket_id = '<ticket_id>' }).message -like 'ticket_id is missing*') ''
Check 'bad action: incomplete' ((Run @{ ticket_id = '301'; action = 'reset' }).message -like 'action must be send or check*') ''
Check 'bad channel: incomplete' ((Run @{ ticket_id = '301'; channel = 'fax' }).message -like 'channel must be email, sms or both*') ''
Check 'check without a code: incomplete' ((Run @{ ticket_id = '301'; action = 'check' }).message -like 'code is missing*') ''
Check 'CloudRadial {Ticket:{TicketId}} body is read' ((Run @{ Ticket = [pscustomobject]@{ TicketId = 301 } }).status -eq 'pending_confirmation') ''
Check 'ticketId (camelCase) is read too' ((Run @{ ticketId = '301' }).status -eq 'pending_confirmation') ''
Check 'a {trigger:{...}} wrapper is read' ((Run @{ trigger = [pscustomobject]@{ ticket_id = '301' } }).status -eq 'pending_confirmation') ''
Check 'nothing written by any of those' (@(Get-Writes).Count -eq 0) (@(Get-Writes | ForEach-Object { $_.Uri }) -join '; ')

# ---- 8. The code never appears in an output or a note ----
$leaks = @(foreach ($cd in @($Seen.codes | Select-Object -Unique)) { foreach ($tx in $Seen.text) { if ([regex]::IsMatch([string]$tx, "(?<![0-9a-f])$cd(?![0-9a-f])")) { "$cd in: $([string]$tx)" } } })
Check "no code in any output or note ($($Seen.codes.Count) codes, $($Seen.text.Count) outputs and notes)" ($leaks.Count -eq 0 -and $Seen.codes.Count -ge 10) (@($leaks | Select-Object -First 2) -join ' || ')

Complete-Test
