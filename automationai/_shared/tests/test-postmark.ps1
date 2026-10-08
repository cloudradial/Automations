# Strict-mode tests for _shared/postmark.ps1: not set up, recipients, request shape, sender override,
# retries, refusals and the 401 message. Send-PmMail must never throw. Placeholder data only.
. (Join-Path $PSScriptRoot 'mock.ps1')

$PmSecrets = @{ 'Postmark-ServerToken' = 'pm-token'; 'Postmark-FromEmail' = 'alerts@examplemsp.com' }
$PmUrl = 'https://api.postmarkapp.com/email'

# --- not set up ---
Reset-Mock @{ 'Postmark-FromEmail' = 'alerts@examplemsp.com' }
Invoke-WithLib @('postmark.ps1') {
    $r = Send-PmMail -To 'manager@contoso.com' -Subject 'x' -Text 'y'
    Check 'missing token: configured false, names the secret, no call' (-not $r.configured -and -not $r.sent -and $r.reason -match 'Postmark-ServerToken' -and $r.reason -notmatch 'FromEmail' -and $Mock.Calls.Count -eq 0) $r.reason
    Check 'Test-PmConfigured is false without the token' (-not (Test-PmConfigured)) ''
}
Reset-Mock @{}
Invoke-WithLib @('postmark.ps1') {
    $r = Send-PmMail -To 'manager@contoso.com' -Subject 'x' -Text 'y'
    Check 'nothing set up: both secrets named' ($r.reason -match 'Postmark-ServerToken and Postmark-FromEmail secrets') $r.reason
}

# --- request shape ---
Reset-Mock $PmSecrets.Clone() { param($c, $n) return [pscustomobject]@{ ErrorCode = 0; Message = 'OK'; MessageID = 'msg-1' } }
Invoke-WithLib @('postmark.ps1') {
    Check 'Test-PmConfigured is true with both secrets' (Test-PmConfigured) ''
    $r = Send-PmMail -To @('manager@contoso.com; dispatch@contoso.com', 'not-an-address', 'manager@contoso.com') -Subject 'SLA report' -Html '<p>Hi</p>' -Text 'Hi' -Tag 'sla-breach-report'
    $l = Get-LastCall; $b = Read-Body $l
    Check 'sent: messageId and the cleaned recipient list come back' ($r.configured -and $r.sent -and $r.messageId -eq 'msg-1' -and ($r.to -join ',') -eq 'manager@contoso.com,dispatch@contoso.com') ($r | ConvertTo-Json -Compress)
    Check 'request: POST /email with the server token header' ($l.Method -eq 'POST' -and $l.Uri -eq $PmUrl -and $l.Headers['X-Postmark-Server-Token'] -eq 'pm-token' -and $l.ContentType -eq 'application/json') "$($l.Method) $($l.Uri)"
    Check 'request body: From, To, Subject, HtmlBody, TextBody, Tag, MessageStream' ($b.From -eq 'alerts@examplemsp.com' -and $b.To -eq 'manager@contoso.com,dispatch@contoso.com' -and $b.Subject -eq 'SLA report' -and $b.HtmlBody -eq '<p>Hi</p>' -and $b.TextBody -eq 'Hi' -and $b.Tag -eq 'sla-breach-report' -and $b.MessageStream -eq 'outbound') $l.Body
    $null = Send-PmMail -To 'manager@contoso.com' -Subject 'x' -Text 'Text only' -From 'servicedesk@examplemsp.com'
    $b = Read-Body (Get-LastCall)
    Check '-From overrides the sender; a text-only email has no HtmlBody' ($b.From -eq 'servicedesk@examplemsp.com' -and $b.TextBody -eq 'Text only' -and -not $b.PSObject.Properties['HtmlBody'] -and -not $b.PSObject.Properties['Tag']) (Get-LastCall).Body
    $Mock.Calls.Clear()
    $r = Send-PmMail -To @('nobody', '') -Subject 'x' -Text 'y'
    Check 'no valid recipient: not sent, no call' (-not $r.sent -and $r.configured -and $r.reason -match 'no valid recipient' -and $Mock.Calls.Count -eq 0) $r.reason
    $r = Send-PmMail -To 'manager@contoso.com' -Subject 'x'
    Check 'no body: not sent, no call' (-not $r.sent -and $r.reason -match 'no body' -and $Mock.Calls.Count -eq 0) $r.reason
}
Reset-Mock ($PmSecrets + @{ 'Postmark-ApiUrl' = 'https://pm.example.com/' }) { param($c, $n) return [pscustomobject]@{ ErrorCode = 0; MessageID = 'msg-2' } }
Invoke-WithLib @('postmark.ps1') {
    $null = Send-PmMail -To 'manager@contoso.com' -Subject 'x' -Text 'y'
    Check 'Postmark-ApiUrl overrides the endpoint' ((Get-LastCall).Uri -eq 'https://pm.example.com/email') (Get-LastCall).Uri
}

# --- retries and refusals ---
Reset-Mock $PmSecrets.Clone() { param($c, $n) if ($n -lt 3) { New-HttpError 429 '{"ErrorCode":429,"Message":"Rate limit"}' }; return [pscustomobject]@{ ErrorCode = 0; MessageID = 'msg-3' } }
Invoke-WithLib @('postmark.ps1') {
    $r = Send-PmMail -To 'manager@contoso.com' -Subject 'x' -Text 'y'
    Check '429 is retried twice, then sent' ($r.sent -and $r.messageId -eq 'msg-3' -and $Mock.Calls.Count -eq 3 -and @($Mock.Sleeps).Count -eq 2) "calls=$($Mock.Calls.Count) sleeps=$(@($Mock.Sleeps) -join ',')"
}
Reset-Mock $PmSecrets.Clone() { param($c, $n) New-HttpError 401 '{"ErrorCode":10,"Message":"Bad or missing Server API token."}' }
Invoke-WithLib @('postmark.ps1') {
    $r = Send-PmMail -To 'manager@contoso.com' -Subject 'x' -Text 'y'
    Check '401 names the Postmark-ServerToken secret and is not retried' (-not $r.sent -and $r.configured -and $r.reason -match 'HTTP 401\)\. Check the Postmark-ServerToken secret' -and $Mock.Calls.Count -eq 1) $r.reason
}
Reset-Mock $PmSecrets.Clone() { param($c, $n) New-HttpError 422 '{"ErrorCode":300,"Message":"Invalid email request"}' }
Invoke-WithLib @('postmark.ps1') {
    $r = Send-PmMail -To 'manager@contoso.com' -Subject 'x' -Text 'y'
    Check '422 gives Postmark''s own message, never throws' (-not $r.sent -and $r.reason -match '\(HTTP 422\): Invalid email request') $r.reason
}
Reset-Mock $PmSecrets.Clone() { param($c, $n) return [pscustomobject]@{ ErrorCode = 406; Message = 'Inactive recipient' } }
Invoke-WithLib @('postmark.ps1') {
    $r = Send-PmMail -To 'manager@contoso.com' -Subject 'x' -Text 'y'
    Check 'a non-zero ErrorCode in a 200 reply counts as not sent' (-not $r.sent -and $r.reason -match 'Inactive recipient') $r.reason
}
Reset-Mock $PmSecrets.Clone() { param($c, $n) New-HttpError 503 '' }
Invoke-WithLib @('postmark.ps1') {
    $r = Send-PmMail -To 'manager@contoso.com' -Subject 'x' -Text 'y'
    Check '503 three times: not sent, plain reason' (-not $r.sent -and $r.reason -match 'HTTP 503' -and $Mock.Calls.Count -eq 3) $r.reason
}

# --- child scope and the html helper ---
Reset-Mock $PmSecrets.Clone() { param($c, $n) return [pscustomobject]@{ ErrorCode = 0; MessageID = 'msg-4' } }
Invoke-WithLib @('postmark.ps1') {
    function Step-Send { return (Send-PmMail -To 'manager@contoso.com' -Subject 'x' -Html "<p>$(ConvertTo-PmHtml 'Contoso & <Example>')</p>") }
    $r = Step-Send
    Check 'works from a function inside the step; ConvertTo-PmHtml encodes' ($r.sent -and (Read-Body (Get-LastCall)).HtmlBody -eq '<p>Contoso &amp; &lt;Example&gt;</p>') (Get-LastCall).Body
}

Complete-Test
