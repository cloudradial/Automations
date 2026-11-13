# ---------- _shared/teams.ps1: Adaptive Cards to a Microsoft Teams channel ----------
# Edit this file, then run: node _shared/inject.js <automation-folder>
# Posts to a Teams channel through a Teams Workflows webhook (the "Post to a channel when a webhook request is
# received" workflow), which replaced the retired Office 365 Incoming Webhook connector. No Azure app, bot or
# Graph permission is needed. Setup steps: _shared/README.md, "Teams channel cards".
# Secrets (runner Key Vault), by name only. Each holds one workflow's webhook URL, which carries a signature,
# so treat it like a password:
#   Teams-WebhookUrl              the default channel
#   Teams-WebhookUrl-<Channel>    a named channel, for example Teams-WebhookUrl-ServiceDesk
# A named channel never falls back to the default one, so a card never lands in a channel nobody chose.
# Stands alone: it needs no other _shared file. Never throws, so a run still finishes when Teams is down.

function Get-TmSecret { param([string]$Name) $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue } catch { }; return $v }
# The secret name for a channel: Teams-WebhookUrl, or Teams-WebhookUrl-<Channel> with only letters, digits and hyphens.
function Get-TmSecretName { param([string]$Channel = '') $c = (([string]$Channel).Trim() -replace '[^A-Za-z0-9-]+', '-').Trim('-'); if ($c) { return "Teams-WebhookUrl-$c" }; return 'Teams-WebhookUrl' }
# $true when the channel's webhook secret is set.
function Test-TmConfigured { param([string]$Channel = '') return (-not [string]::IsNullOrWhiteSpace((Get-TmSecret (Get-TmSecretName $Channel)))) }

# Builds an Adaptive Card (1.4, the version Teams renders) as an ordered hashtable.
#   -Title    bold heading. -Subtitle  smaller line under it. -Text  body (Teams markdown: **bold**, lists, links).
#   -Facts    ordered hashtable or hashtable of label -> value; empty values are left out.
#   -LinkText/-LinkUrl  one "open" button (https links only).
#   -Style    default, good, attention, warning or accent: the heading colour.
function New-TmCard {
    param([string]$Title, [string]$Subtitle = '', [string]$Text = '', $Facts = $null, [string]$LinkText = '', [string]$LinkUrl = '', [string]$Style = 'default')
    $color = @{ good = 'Good'; attention = 'Attention'; warning = 'Warning'; accent = 'Accent' }[$Style.ToLowerInvariant()]
    if (-not $color) { $color = 'Default' }
    $body = New-Object System.Collections.ArrayList
    $null = $body.Add([ordered]@{ type = 'TextBlock'; text = $Title; weight = 'Bolder'; size = 'Medium'; wrap = $true; color = $color })
    if ($Subtitle) { $null = $body.Add([ordered]@{ type = 'TextBlock'; text = $Subtitle; isSubtle = $true; spacing = 'None'; wrap = $true }) }
    if ($Text) { $null = $body.Add([ordered]@{ type = 'TextBlock'; text = $Text; wrap = $true }) }
    if ($null -ne $Facts) {
        $list = New-Object System.Collections.ArrayList
        foreach ($k in @($Facts.Keys)) { $v = [string]$Facts[$k]; if ($v.Trim()) { $null = $list.Add([ordered]@{ title = [string]$k; value = $v }) } }
        if ($list.Count) { $null = $body.Add([ordered]@{ type = 'FactSet'; facts = @($list) }) }
    }
    $card = [ordered]@{ '$schema' = 'http://adaptivecards.io/schemas/adaptive-card.json'; type = 'AdaptiveCard'; version = '1.4'; body = @($body) }
    if ($LinkUrl -match '^https://') { $card.actions = @([ordered]@{ type = 'Action.OpenUrl'; title = $(if ($LinkText) { $LinkText } else { 'Open' }); url = $LinkUrl }) }
    return $card
}

# Posts one card to a channel. Pass the parts (as for New-TmCard) or a ready -Card.
# Returns @{ configured; sent; reason; channel }. configured is $false when the channel's secret isn't set.
# The webhook URL is never put in a reason or output. Retries 429 and 5xx twice. A card over 27 KB is refused
# before sending (Teams caps a message at about 28 KB): post a summary with a link instead.
function Send-TeamsCard {
    param([string]$Channel = '', [string]$Title = '', [string]$Subtitle = '', [string]$Text = '', $Facts = $null, [string]$LinkText = '', [string]$LinkUrl = '', [string]$Style = 'default', $Card = $null)
    $name = Get-TmSecretName $Channel
    $label = if ($name -eq 'Teams-WebhookUrl') { 'the default Teams channel' } else { "Teams channel $($name.Substring(17))" }
    $url = ([string](Get-TmSecret $name)).Trim()
    if (-not $url) { return @{ configured = $false; sent = $false; reason = "Teams isn't set up for $label (add the $name secret)."; channel = $name } }
    if ($url -notmatch '^https://') { return @{ configured = $true; sent = $false; reason = "The $name secret isn't an https URL, so nothing was posted. Paste the URL the Teams workflow gave you."; channel = $name } }
    if ($null -eq $Card) {
        if (-not $Title.Trim()) { return @{ configured = $true; sent = $false; reason = 'The card has no title.'; channel = $name } }
        $Card = New-TmCard -Title $Title -Subtitle $Subtitle -Text $Text -Facts $Facts -LinkText $LinkText -LinkUrl $LinkUrl -Style $Style
    }
    $payload = [ordered]@{ type = 'message'; attachments = @([ordered]@{ contentType = 'application/vnd.microsoft.card.adaptive'; contentUrl = $null; content = $Card }) }
    $json = ConvertTo-Json -InputObject $payload -Depth 20 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetByteCount($json)
    if ($bytes -gt 27000) { return @{ configured = $true; sent = $false; reason = "The card is too big for Teams ($bytes bytes; the limit is about 28 KB). Post a summary with a link instead."; channel = $name } }
    for ($i = 1; $i -le 3; $i++) {
        try {
            $null = Invoke-RestMethod -Method POST -Uri $url -Body $json -ContentType 'application/json; charset=utf-8' -ErrorAction Stop
            return @{ configured = $true; sent = $true; reason = ''; channel = $name }
        }
        catch {
            $status = 0; try { $status = [int]$_.Exception.Response.StatusCode } catch { }
            if (($status -eq 429 -or $status -ge 500) -and $i -lt 3) { Start-Sleep -Seconds (2 * $i); continue }
            $d = $null; try { if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $d = $_.ErrorDetails.Message } } catch { }
            if (-not $d) { $d = [string]$_.Exception.Message }
            $d = ($d -replace [regex]::Escape($url), '<webhook>' -replace 'https://\S+', '<url>')
            if ($d.Length -gt 300) { $d = $d.Substring(0, 300) + '...' }
            $why = if ($status -in @(401, 403, 404)) { "Teams refused the webhook for $label (HTTP $status). The workflow may be off or deleted: recreate it and update the $name secret." } else { "Teams couldn't post the card to $label$(if ($status) { " (HTTP $status)" }): $d" }
            return @{ configured = $true; sent = $false; reason = $why; channel = $name }
        }
    }
    return @{ configured = $true; sent = $false; reason = "Teams kept refusing the card for $label."; channel = $name }
}
# ---------- end _shared/teams.ps1 ----------
