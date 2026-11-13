# Strict-mode tests for _shared/teams.ps1: not set up, named channels, card shape, link rules, size limit,
# retries, refusals, and that the webhook URL never leaks into a reason. Send-TeamsCard must never throw.
# Placeholder data only.
. (Join-Path $PSScriptRoot 'mock.ps1')

$TmUrl = 'https://prod-01.westus.logic.example/workflows/abc/triggers/manual/paths/invoke?sig=SECRET123'
$TmDesk = 'https://prod-02.westus.logic.example/workflows/def/triggers/manual/paths/invoke?sig=DESK456'

# --- not set up ---
Reset-Mock @{}
Invoke-WithLib @('teams.ps1') {
    $r = Send-TeamsCard -Title 'Kudos' -Text 'x'
    Check 'no secret: configured false, names Teams-WebhookUrl, no call' (-not $r.configured -and -not $r.sent -and $r.reason -match 'add the Teams-WebhookUrl secret' -and $Mock.Calls.Count -eq 0) $r.reason
    Check 'Test-TmConfigured is false without the secret' (-not (Test-TmConfigured)) ''
}
Reset-Mock @{ 'Teams-WebhookUrl' = $TmUrl }
Invoke-WithLib @('teams.ps1') {
    $r = Send-TeamsCard -Channel 'Service Desk' -Title 'Kudos'
    Check 'named channel never falls back to the default one' (-not $r.configured -and $r.reason -match 'Teams-WebhookUrl-Service-Desk' -and $r.channel -eq 'Teams-WebhookUrl-Service-Desk' -and $Mock.Calls.Count -eq 0) $r.reason
}
Reset-Mock @{ 'Teams-WebhookUrl' = 'http://not-https.example/hook' }
Invoke-WithLib @('teams.ps1') {
    $r = Send-TeamsCard -Title 'Kudos'
    Check 'non-https secret: not sent, URL not echoed' (-not $r.sent -and $r.configured -and $r.reason -match "isn't an https URL" -and $r.reason -notmatch 'not-https' -and $Mock.Calls.Count -eq 0) $r.reason
}

# --- card shape ---
Reset-Mock @{ 'Teams-WebhookUrl' = $TmUrl; 'Teams-WebhookUrl-ServiceDesk' = $TmDesk } { param($c, $n) return $null }
Invoke-WithLib @('teams.ps1') {
    $facts = [ordered]@{ Ticket = '#1001 Printer offline'; Rated = '5 out of 5'; From = 'pat@contoso.example'; Empty = '  ' }
    $r = Send-TeamsCard -Title 'Kudos from Contoso' -Subtitle 'Ticket #1001' -Text 'Great work!' -Facts $facts -LinkText 'Open ticket' -LinkUrl 'https://psa.example/ticket/1001' -Style 'good'
    $l = Get-LastCall; $b = Read-Body $l; $card = $b.attachments[0].content
    Check 'sent to the default channel' ($r.configured -and $r.sent -and $r.channel -eq 'Teams-WebhookUrl' -and $l.Method -eq 'POST' -and $l.Uri -eq $TmUrl -and $l.ContentType -like 'application/json*') ($r | ConvertTo-Json -Compress)
    Check 'payload: a message with one Adaptive Card attachment' ($b.type -eq 'message' -and @($b.attachments).Count -eq 1 -and $b.attachments[0].contentType -eq 'application/vnd.microsoft.card.adaptive' -and $card.type -eq 'AdaptiveCard' -and $card.version -eq '1.4') $l.Body
    Check 'card: title (good colour), subtitle, text, facts without empty ones' ($card.body[0].text -eq 'Kudos from Contoso' -and $card.body[0].color -eq 'Good' -and $card.body[1].text -eq 'Ticket #1001' -and $card.body[2].text -eq 'Great work!' -and $card.body[3].type -eq 'FactSet' -and (@($card.body[3].facts | ForEach-Object { $_.title }) -join ',') -eq 'Ticket,Rated,From') $l.Body
    Check 'card: one Open ticket button' (@($card.actions).Count -eq 1 -and $card.actions[0].type -eq 'Action.OpenUrl' -and $card.actions[0].title -eq 'Open ticket' -and $card.actions[0].url -eq 'https://psa.example/ticket/1001') $l.Body
    $null = Send-TeamsCard -Channel 'ServiceDesk' -Title 'Plain' -LinkUrl 'javascript:alert(1)'
    $l = Get-LastCall; $card = (Read-Body $l).attachments[0].content
    Check 'named channel posts to its own URL; a non-https link gets no button' ($l.Uri -eq $TmDesk -and -not $card.PSObject.Properties['actions'] -and $card.body[0].color -eq 'Default' -and @($card.body).Count -eq 1) $l.Body
    $Mock.Calls.Clear()
    $r = Send-TeamsCard -Title '  '
    Check 'no title: not sent, no call' (-not $r.sent -and $r.reason -match 'no title' -and $Mock.Calls.Count -eq 0) $r.reason
    $r = Send-TeamsCard -Title 'Big' -Text ('x' * 30000)
    Check 'too big: refused before sending, says to post a summary' (-not $r.sent -and $r.reason -match 'too big for Teams' -and $Mock.Calls.Count -eq 0) $r.reason
    $own = New-TmCard -Title 'Built elsewhere' -Style 'attention'
    $r = Send-TeamsCard -Card $own
    Check 'a ready -Card is sent as is' ($r.sent -and (Read-Body (Get-LastCall)).attachments[0].content.body[0].color -eq 'Attention') ''
    function Step-Post { return (Send-TeamsCard -Title 'From a function') }
    Check 'works from a function inside the step (child scope)' ((Step-Post).sent) ''
}

# --- retries and refusals ---
Reset-Mock @{ 'Teams-WebhookUrl' = $TmUrl } { param($c, $n) if ($n -lt 3) { New-HttpError 429 '' }; return $null }
Invoke-WithLib @('teams.ps1') {
    $r = Send-TeamsCard -Title 'Kudos'
    Check '429 retried twice, then sent' ($r.sent -and $Mock.Calls.Count -eq 3 -and @($Mock.Sleeps).Count -eq 2) "calls=$($Mock.Calls.Count)"
}
Reset-Mock @{ 'Teams-WebhookUrl' = $TmUrl } { param($c, $n) New-HttpError 404 '{"error":{"code":"WorkflowNotFound","message":"The workflow could not be found."}}' }
Invoke-WithLib @('teams.ps1') {
    $r = Send-TeamsCard -Title 'Kudos'
    Check '404: says the workflow may be off or deleted, names the secret, no retry' (-not $r.sent -and $r.reason -match 'may be off or deleted' -and $r.reason -match 'Teams-WebhookUrl secret' -and $Mock.Calls.Count -eq 1) $r.reason
}
Reset-Mock @{ 'Teams-WebhookUrl' = $TmUrl } { param($c, $n) New-HttpError 400 "{`"error`":`"Bad card posted to $TmUrl`"}" }
Invoke-WithLib @('teams.ps1') {
    $r = Send-TeamsCard -Title 'Kudos'
    Check '400: plain reason, the webhook URL and signature never appear' (-not $r.sent -and $r.reason -match 'HTTP 400' -and $r.reason -notmatch 'SECRET123' -and $r.reason -notmatch 'logic\.example') $r.reason
}
Reset-Mock @{ 'Teams-WebhookUrl' = $TmUrl } { param($c, $n) New-HttpError 503 '' }
Invoke-WithLib @('teams.ps1') {
    $r = Send-TeamsCard -Title 'Kudos'
    Check '503 three times: not sent, never throws' (-not $r.sent -and $r.reason -match 'HTTP 503' -and $Mock.Calls.Count -eq 3) $r.reason
}

Complete-Test
