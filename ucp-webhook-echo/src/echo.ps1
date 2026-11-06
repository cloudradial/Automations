# Emails back everything the webhook delivered, so whoever is testing a CloudRadial (UCP) Automation can see
# exactly which values reached AutomationAI. Writes nothing anywhere else.
# Recipient: a toEmail value anywhere in the body (one address or a comma list), else the submitting user's email.
function Get-EchoProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Test-EchoScalar { param($v) return ($null -eq $v -or $v -is [string] -or $v.GetType().IsValueType) }
function Get-EchoPairs {
    param($o)
    if ($o -is [System.Collections.IDictionary]) { return @($o.Keys | ForEach-Object { @{ Name = [string]$_; Value = $o[$_] } }) }
    return @($o.PSObject.Properties | ForEach-Object { @{ Name = $_.Name; Value = $_.Value } })
}
# Flattens the body into one row per value: path, value, type and a check result.
function Add-EchoRows {
    param($rows, $v, [string]$path, [int]$depth = 0)
    if ($depth -gt 15) { $null = $rows.Add([ordered]@{ path = $path; value = '(nested too deep to list)'; type = 'object'; check = 'not listed' }); return }
    if (Test-EchoScalar $v) {
        $type = if ($null -eq $v) { 'null' } elseif ($v -is [string]) { 'string' } elseif ($v -is [bool]) { 'boolean' } else { 'number' }
        $s = if ($null -eq $v) { '' } elseif ($v -is [bool]) { ([string]$v).ToLowerInvariant() } else { [string]$v }
        $check = 'ok'
        if ($null -eq $v) { $check = 'null' }
        elseif ($s.Trim() -eq '') { $check = 'empty' }
        elseif ($s.Trim() -match '^@[A-Za-z_][A-Za-z0-9_]*$') { $check = 'token not replaced' }
        elseif ($s -match '(^|[\s"''(,])@[A-Za-z_][A-Za-z0-9_]*\b' -and $s -notmatch '^[^@\s]+@[^@\s]+$') { $check = 'may contain an unreplaced token' }
        $null = $rows.Add([ordered]@{ path = $path; value = $s; type = $type; check = $check }); return
    }
    if ($v -is [System.Collections.IDictionary] -or $v -is [System.Management.Automation.PSCustomObject]) {
        $pairs = @(Get-EchoPairs $v)
        if (-not $pairs.Count) { $null = $rows.Add([ordered]@{ path = $path; value = '{}'; type = 'object'; check = 'empty' }); return }
        foreach ($p in $pairs) { Add-EchoRows $rows $p.Value $(if ($path) { "$path.$($p.Name)" } else { $p.Name }) ($depth + 1) }
        return
    }
    if ($v -is [System.Collections.IEnumerable]) {
        $items = @($v)
        if (-not $items.Count) { $null = $rows.Add([ordered]@{ path = $path; value = '[]'; type = 'array'; check = 'empty' }); return }
        for ($i = 0; $i -lt $items.Count; $i++) { Add-EchoRows $rows $items[$i] "$path[$i]" ($depth + 1) }
        return
    }
    $null = $rows.Add([ordered]@{ path = $path; value = [string]$v; type = $v.GetType().Name; check = 'ok' })
}

$received = Get-NodeInput
$receivedAt = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
$warnings = New-Object System.Collections.ArrayList

# Unwrap the step parameter ("trigger"), then a "body" wrapper if the runner added one (only when "body" sits
# alone or next to "headers", so a form field that happens to be called "body" isn't mistaken for one).
$body = $received
$unwrapped = @()
foreach ($w in @('trigger', 'body')) {
    $inner = Get-EchoProp $body $w
    if ($null -eq $inner -or ($inner -is [string] -and -not $inner.Trim().StartsWith('{')) -or ((Test-EchoScalar $inner) -and -not ($inner -is [string]))) { continue }
    if ($w -eq 'body') { $others = @(Get-EchoPairs $body | Where-Object { $_.Name -notin @('body', 'headers', 'method', 'query') }); if ($others.Count) { continue } }
    $body = $inner; $unwrapped += $w
}
# CloudRadial pastes each @token's value into the Content as raw text, so an answer with a line break, a double quote
# or a backslash breaks the JSON. Recover a flat {"key": "value", ...} body by reading from one "key": to the next.
function Repair-EchoJson {
    param([string]$text)
    $t = $text.Trim()
    $end = $t.LastIndexOf('}'); if ($t.StartsWith('{') -and $end -gt 0) { $t = $t.Substring(1, $end - 1) } else { return $null }
    # The Content is usually one key per line, so a key must start a line; that keeps a ', "x":' inside a value
    # from being read as a key. A body on one line falls back to keys after { or ,.
    $keyPattern = if ($t -match '\n\s*"[A-Za-z_]') { '(?m)^[ \t]*,?[ \t]*"([A-Za-z_][A-Za-z0-9_.-]*)"[ \t]*:[ \t]*' } else { '(?:^|[{,])\s*"([A-Za-z_][A-Za-z0-9_.-]*)"\s*:\s*' }
    $ms = @([regex]::Matches($t, $keyPattern))
    if (-not $ms.Count) { return $null }
    $out = [ordered]@{}; $broken = @()
    for ($i = 0; $i -lt $ms.Count; $i++) {
        $from = $ms[$i].Index + $ms[$i].Length
        $to = if ($i + 1 -lt $ms.Count) { $ms[$i + 1].Index } else { $t.Length }
        $v = $t.Substring($from, $to - $from).Trim()
        if ($v.EndsWith(',')) { $v = $v.Substring(0, $v.Length - 1).TrimEnd() }
        if ($v.Length -ge 2 -and $v.StartsWith('"') -and $v.EndsWith('"')) {
            $inner = $v.Substring(1, $v.Length - 2)
            # PowerShell's parser accepts raw control characters (a pasted line break); strict parsers don't.
            $ok = $inner -notmatch '[\x00-\x1f]'; if ($ok) { try { $null = ('"' + $inner + '"') | ConvertFrom-Json -ErrorAction Stop } catch { $ok = $false } }
            if ($ok) { $v = ('"' + $inner + '"') | ConvertFrom-Json } else { $v = $inner; $broken += $ms[$i].Groups[1].Value }
        }
        else { $ok = $true; try { $v = $v | ConvertFrom-Json -ErrorAction Stop } catch { $ok = $false; $broken += $ms[$i].Groups[1].Value } }
        $out[$ms[$i].Groups[1].Value] = $v
    }
    return @{ body = $out; broken = @($broken) }
}

$shape = 'JSON object'
$brokenKeys = @()
if ($body -is [string]) {
    if ($body.Trim() -eq '') { $body = $null }
    else {
        $rawText = $body
        try { $body = $rawText | ConvertFrom-Json -ErrorAction Stop; $shape = 'JSON object (arrived as text and was parsed)' }
        catch {
            $fix = Repair-EchoJson $rawText
            if ($null -ne $fix) {
                $body = $fix.body; $brokenKeys = @($fix.broken)
                $shape = 'invalid JSON, repaired by reading one "key": value at a time'
                $null = $warnings.Add("The body wasn't valid JSON$(if ($brokenKeys.Count) { ". These values broke it (a line break, double quote or backslash, pasted in unescaped): $($brokenKeys -join ', ')" }). The workflow repaired it to read the values, but a normal JSON parser would reject this body.")
            }
            else { $shape = 'text that is not valid JSON'; $null = $warnings.Add("The body is text that isn't valid JSON and couldn't be repaired. A common cause is an unquoted @token, or a value with a double quote or line break in it.") }
        }
    }
}
if ($null -eq $body) { $shape = 'nothing (empty body)'; $null = $warnings.Add('No body was received. Check that the Webhook activity has Content, and that the workflow step is bound to {{ nodes.trigger.output }}.') }
elseif ($null -ne (Get-EchoProp $body 'Ticket') -and $null -ne (Get-EchoProp (Get-EchoProp $body 'Ticket') 'Questions')) { $shape = 'CloudRadial ticket shape {Ticket:{Questions:[...]}, Company:{...}}' }

$rows = New-Object System.Collections.ArrayList
if ($null -ne $body -and -not ($body -is [string])) { Add-EchoRows $rows $body ''; foreach ($r in $rows) { if ($r.path -in $brokenKeys) { $r.check = 'broke the JSON (repaired)' } } }
elseif ($body -is [string]) { $null = $rows.Add([ordered]@{ path = '(whole body)'; value = $body; type = 'string'; check = 'not JSON' }) }

# A CloudRadial ticket-shaped body: list each question by its Id as well.
$questions = New-Object System.Collections.ArrayList
$ticket = Get-EchoProp $body 'Ticket'
if ($null -ne $ticket -and -not (Test-EchoScalar $ticket)) {
    foreach ($q in @(Get-EchoProp $ticket 'Questions')) {
        if ($null -eq $q -or (Test-EchoScalar $q)) { continue }
        $qv = Get-EchoProp $q 'Value'; if ($null -eq $qv) { $qv = Get-EchoProp $q 'Answer' }
        $qs = if (Test-EchoScalar $qv) { [string]$qv } else { ConvertTo-Json -InputObject $qv -Depth 10 -Compress }
        $null = $questions.Add([ordered]@{ id = [string](Get-EchoProp $q 'Id'); value = $qs })
    }
}

$tokenRows = @($rows | Where-Object { $_.check -eq 'token not replaced' })
$maybeRows = @($rows | Where-Object { $_.check -eq 'may contain an unreplaced token' })
$emptyRows = @($rows | Where-Object { $_.check -in @('empty', 'null') })
if ($tokenRows.Count) { $null = $warnings.Add("$($tokenRows.Count) value(s) arrived as a literal @token, so CloudRadial didn't replace them: $((@($tokenRows | ForEach-Object { "$($_.path)=$($_.value)" }) -join ', ')). The token name is wrong, or the question has no Script / JSON Field ID.") }
if ($emptyRows.Count) { $null = $warnings.Add("$($emptyRows.Count) value(s) arrived empty: $((@($emptyRows | ForEach-Object { $_.path }) -join ', ')).") }

# Pretty JSON exactly as the step saw it (before unwrapping) and the body on its own.
$rawJson = if ($null -eq $received) { '(nothing)' } elseif ($received -is [string]) { $received } else { ConvertTo-Json -InputObject $received -Depth 20 }
$bodyJson = if ($null -eq $body) { '(nothing)' } elseif ($body -is [string]) { $body } else { ConvertTo-Json -InputObject $body -Depth 20 }
$bodyBytes = [System.Text.Encoding]::UTF8.GetByteCount($(if ($body -is [string]) { $body } elseif ($null -eq $body) { '' } else { ConvertTo-Json -InputObject $body -Depth 20 -Compress }))
$maxShow = 200000
if ($rawJson.Length -gt $maxShow) { $rawJson = $rawJson.Substring(0, $maxShow) + "`n... (cut at $maxShow characters; the run output has the full body)"; $null = $warnings.Add('The raw payload was longer than 200,000 characters, so the email shows the first part only.') }

$ticketId = ''
foreach ($k in @('ticketId', 'TicketId', 'ticket_id')) { $tv = Get-EchoProp $body $k; if ($null -ne $tv -and (Test-EchoScalar $tv) -and [string]$tv -notmatch '^@') { $ticketId = [string]$tv; break } }
if (-not $ticketId -and $null -ne $ticket -and -not (Test-EchoScalar $ticket)) { $tv = Get-EchoProp $ticket 'TicketId'; if ($null -ne $tv) { $ticketId = [string]$tv } }

# Recipient, searched anywhere in the body (a UCP Action nests answers and user metadata): first a toEmail
# answer, then a Ticket.Questions entry with Id toEmail, then the submitting user's email.
$to = @()
$toPatterns = @('(^|\.)to_?email(\[\d+\])?$', '(^|\.)(user\.email|useremail|requestedby|submittedbyemail|contact\.email|requester\.email)$')
foreach ($pat in $toPatterns) {
    $hits = @($rows | Where-Object { $_.path -match $pat })
    if ($pat -like '*to_?email*') { $hits += @($questions | Where-Object { $_.id -match '^to_?email$' } | ForEach-Object { @{ value = $_.value } }) }
    $to = @($hits | ForEach-Object { ([string]$_.value) -split '[,;]' } | ForEach-Object { $_.Trim() } | Where-Object { Test-PmEmail $_ } | Select-Object -Unique)
    if ($to.Count) { break }
}

# ---------- email ----------
$e = { param($s) ConvertTo-PmHtml ([string]$s) }
$td = 'style="border:1px solid #d0d7de;padding:4px 8px;vertical-align:top;font-family:Consolas,monospace;font-size:12px"'
$th = 'style="border:1px solid #d0d7de;padding:4px 8px;background:#f6f8fa;text-align:left;font-size:12px"'
$checkColour = @{ 'ok' = '#1a7f37'; 'empty' = '#9a6700'; 'null' = '#9a6700'; 'token not replaced' = '#cf222e'; 'may contain an unreplaced token' = '#9a6700'; 'not JSON' = '#cf222e'; 'not listed' = '#57606a'; 'broke the JSON (repaired)' = '#cf222e' }
$verdict = if ($null -eq $body) { 'Nothing was received.' } elseif ($body -is [string]) { "A body arrived, but it isn't valid JSON." } elseif ($shape -like 'invalid JSON*') { "The webhook arrived as invalid JSON$(if ($brokenKeys.Count) { " ($($brokenKeys.Count) value(s) broke it)" }); it was repaired so the values below could be read." } elseif ($tokenRows.Count) { "The webhook arrived, but $($tokenRows.Count) token(s) weren't replaced." } else { 'The webhook arrived and every value was replaced.' }
$sb = New-Object System.Text.StringBuilder
$null = $sb.Append('<div style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#1f2328">')
$null = $sb.Append("<h2 style=""margin:0 0 4px"">UCP webhook test: what AutomationAI received</h2><p style=""margin:0 0 12px;color:#57606a"">$(& $e $receivedAt)</p>")
$null = $sb.Append("<p style=""font-size:15px""><b>$(& $e $verdict)</b></p>")
$null = $sb.Append("<table style=""border-collapse:collapse;margin-bottom:12px""><tr><th $th>Body shape</th><td $td>$(& $e $shape)</td></tr><tr><th $th>Body size</th><td $td>$bodyBytes bytes</td></tr><tr><th $th>Values</th><td $td>$($rows.Count) total, $($tokenRows.Count) unreplaced token(s), $($emptyRows.Count) empty</td></tr><tr><th $th>Ticket id</th><td $td>$(if ($ticketId) { & $e $ticketId } else { '(none)' })</td></tr><tr><th $th>Unwrapped</th><td $td>$(if ($unwrapped.Count) { & $e ($unwrapped -join ' > ') } else { '(no wrapper)' })</td></tr></table>")
if ($warnings.Count) { $null = $sb.Append('<h3 style="margin:16px 0 4px">Check these</h3><ul>'); foreach ($w in $warnings) { $null = $sb.Append("<li>$(& $e $w)</li>") }; $null = $sb.Append('</ul>') }
$null = $sb.Append("<h3 style=""margin:16px 0 4px"">Every value ($($rows.Count))</h3><table style=""border-collapse:collapse""><tr><th $th>Key</th><th $th>Value</th><th $th>Type</th><th $th>Check</th></tr>")
foreach ($r in $rows) { $c = if ($checkColour.Contains($r.check)) { $checkColour[$r.check] } else { '#1f2328' }; $null = $sb.Append("<tr><td $td>$(& $e $r.path)</td><td $td>$(& $e $r.value)</td><td $td>$(& $e $r.type)</td><td $td><span style=""color:$c"">$(& $e $r.check)</span></td></tr>") }
$null = $sb.Append('</table>')
if ($questions.Count) { $null = $sb.Append("<h3 style=""margin:16px 0 4px"">Form questions by Id ($($questions.Count))</h3><table style=""border-collapse:collapse""><tr><th $th>Id</th><th $th>Value</th></tr>"); foreach ($q in $questions) { $null = $sb.Append("<tr><td $td>$(& $e $q.id)</td><td $td>$(& $e $q.value)</td></tr>") }; $null = $sb.Append('</table>') }
$null = $sb.Append('<h3 style="margin:16px 0 4px">Raw step input (exactly as the runner passed it)</h3>')
$null = $sb.Append("<pre style=""background:#f6f8fa;border:1px solid #d0d7de;padding:8px;font-size:12px;white-space:pre-wrap;word-break:break-all"">$(& $e $rawJson)</pre>")
$null = $sb.Append("<p style=""color:#57606a;font-size:12px"">Sent by the UCP Webhook Echo workflow. PowerShell $(& $e ([string]$PSVersionTable.PSVersion)). The same data is in this run's output in AutomationAI.</p></div>")
$html = $sb.ToString()
$text = "UCP webhook test: what AutomationAI received ($receivedAt)`n$verdict`nBody shape: $shape`nBody size: $bodyBytes bytes`n`n" + $(if ($warnings.Count) { "Check these:`n" + ((@($warnings) | ForEach-Object { "- $_" }) -join "`n") + "`n`n" } else { '' }) + "Every value:`n" + ((@($rows) | ForEach-Object { "$($_.path) = $($_.value)  [$($_.check)]" }) -join "`n") + "`n`nRaw step input:`n$rawJson`n"

$subject = "UCP webhook test$(if ($ticketId) { " (ticket $ticketId)" }): $(if ($shape -like 'invalid JSON*') { "invalid JSON, repaired$(if ($brokenKeys.Count) { " (broken: $($brokenKeys -join ', '))" })" } elseif ($tokenRows.Count) { "$($tokenRows.Count) token(s) not replaced" } elseif ($null -eq $body) { 'nothing received' } else { "$($rows.Count) values received" })"
$mail = if ($to.Count) { Send-PmMail -To $to -Subject $subject -Html $html -Text $text -Tag 'ucp-webhook-echo' } else { @{ configured = (Test-PmConfigured); sent = $false; reason = 'There is no recipient: add a form question with the field key toEmail, or make sure the payload carries the submitting user''s email.'; messageId = ''; to = @() } }
if (-not $mail.sent) { $null = $warnings.Add("The email wasn't sent: $($mail.reason)") }

$status = if ($mail.sent) { 'success' } else { 'incomplete' }
$message = if ($mail.sent) { "Emailed the received payload to $($mail.to -join ', '). $verdict" } else { "Received the payload, but the email wasn't sent: $($mail.reason) $verdict" }
Set-NodeOutput ([ordered]@{
    status = $status; message = $message; public_note = ''; internal_note = $message; ticket_id = $ticketId
    actions = @($(if ($mail.sent) { "Emailed $($mail.to -join ', ') (Postmark message $($mail.messageId))" })); warnings = @($warnings)
    email = [ordered]@{ sent = [bool]$mail.sent; to = @($mail.to); messageId = [string]$mail.messageId; reason = [string]$mail.reason; subject = $subject }
    received = [ordered]@{ at = $receivedAt; shape = $shape; bytes = $bodyBytes; unwrapped = @($unwrapped); valueCount = $rows.Count; unreplacedTokens = @($tokenRows | ForEach-Object { $_.path }); empty = @($emptyRows | ForEach-Object { $_.path }); maybeTokens = @($maybeRows | ForEach-Object { $_.path }) }
    values = @($rows); questions = @($questions); raw = $bodyJson
})
