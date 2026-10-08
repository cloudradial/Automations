# ---------- _shared/postmark.ps1: staff email through Postmark ----------
# Edit this file, then run: node automationai/_shared/inject.js <automation-folder>
# Same secret names as the Postmark catalog extension and automationai/deliver-result:
#   Postmark-ServerToken (required), Postmark-FromEmail (required, a verified sender),
#   Postmark-ApiUrl (optional, default https://api.postmarkapp.com).
# Emails go to staff (service manager, dispatcher, account manager). Messages to a ticket's requester go
# through a public PSA note instead, so the PSA emails them. Stands alone: it needs no other _shared file.

function Get-PmSecret { param([string]$Name) $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue } catch { }; return $v }
function Get-PmProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Test-PmEmail { param([string]$s) return ([string]$s -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') }
# $true when both required secrets are set.
function Test-PmConfigured { return (-not [string]::IsNullOrWhiteSpace((Get-PmSecret 'Postmark-ServerToken')) -and -not [string]::IsNullOrWhiteSpace((Get-PmSecret 'Postmark-FromEmail'))) }
# Text made safe to put inside HTML.
function ConvertTo-PmHtml { param([string]$s) if ($null -eq $s) { return '' }; return [System.Net.WebUtility]::HtmlEncode($s) }

# Sends one email. Never throws, so a report or alert still finishes when email fails; the caller falls back
# (usually to an internal note) when sent is $false.
#   -To       one or more addresses, or one comma/semicolon separated string. Invalid addresses are dropped.
#   -Html / -Text  at least one is needed. -Tag and -Stream (default 'outbound') are passed to Postmark.
#   -From     overrides the Postmark-FromEmail secret (it must still be a verified sender).
# Returns @{ configured; sent; reason; messageId; to }. configured is $false when the token or sender is missing.
# Retries 429 and 5xx twice. A 401 names the Postmark-ServerToken secret.
function Send-PmMail {
    param([string[]]$To, [string]$Subject, [string]$Html = '', [string]$Text = '', [string]$Tag = '', [string]$Stream = 'outbound', [string]$From = '')
    $rcpt = @(@($To) | ForEach-Object { ([string]$_) -split '[,;]' } | ForEach-Object { $_.Trim() } | Where-Object { Test-PmEmail $_ } | Select-Object -Unique)
    $token = Get-PmSecret 'Postmark-ServerToken'
    $sender = if ($From.Trim()) { $From.Trim() } else { [string](Get-PmSecret 'Postmark-FromEmail') }
    if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($sender)) {
        $miss = @(); if ([string]::IsNullOrWhiteSpace($token)) { $miss += 'Postmark-ServerToken' }; if ([string]::IsNullOrWhiteSpace($sender)) { $miss += 'Postmark-FromEmail' }
        return @{ configured = $false; sent = $false; reason = "Postmark isn't set up (add the $($miss -join ' and ') secret$(if ($miss.Count -gt 1) { 's' }))."; messageId = ''; to = @($rcpt) }
    }
    if (-not $rcpt.Count) { return @{ configured = $true; sent = $false; reason = 'There is no valid recipient address.'; messageId = ''; to = @() } }
    if (-not $Html -and -not $Text) { return @{ configured = $true; sent = $false; reason = 'The email has no body.'; messageId = ''; to = @($rcpt) } }
    $api = Get-PmSecret 'Postmark-ApiUrl'; if ([string]::IsNullOrWhiteSpace($api)) { $api = 'https://api.postmarkapp.com' }
    $body = [ordered]@{ From = $sender.Trim(); To = ($rcpt -join ','); Subject = $Subject; MessageStream = $Stream }
    if ($Html) { $body.HtmlBody = $Html }
    if ($Text) { $body.TextBody = $Text }
    if ($Tag) { $body.Tag = $Tag }
    $h = @{ 'X-Postmark-Server-Token' = $token.Trim(); Accept = 'application/json' }
    for ($i = 1; $i -le 3; $i++) {
        try {
            $r = Invoke-RestMethod -Method POST -Uri "$($api.TrimEnd('/'))/email" -Headers $h -Body (ConvertTo-Json -InputObject $body -Depth 5 -Compress) -ContentType 'application/json' -ErrorAction Stop
            $code = Get-PmProp $r 'ErrorCode'
            if ($null -ne $code -and [int]$code -ne 0) { return @{ configured = $true; sent = $false; reason = "Postmark refused the email: $(Get-PmProp $r 'Message')"; messageId = ''; to = @($rcpt) } }
            return @{ configured = $true; sent = $true; reason = ''; messageId = [string](Get-PmProp $r 'MessageID'); to = @($rcpt) }
        }
        catch {
            $status = 0; try { $status = [int]$_.Exception.Response.StatusCode } catch { }
            if (($status -eq 429 -or $status -ge 500) -and $i -lt 3) { Start-Sleep -Seconds (2 * $i); continue }
            $d = $null; try { if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $d = $_.ErrorDetails.Message } } catch { }
            if (-not $d) { $d = [string]$_.Exception.Message }
            $msg = $d; try { $j = $d | ConvertFrom-Json -ErrorAction Stop; $m = Get-PmProp $j 'Message'; if ($m) { $msg = [string]$m } } catch { }
            $why = if ($status -eq 401) { 'Postmark rejected the server token (HTTP 401). Check the Postmark-ServerToken secret.' } else { "Postmark couldn't send the email$(if ($status) { " (HTTP $status)" }): $msg" }
            return @{ configured = $true; sent = $false; reason = $why; messageId = ''; to = @($rcpt) }
        }
    }
    return @{ configured = $true; sent = $false; reason = 'Postmark kept refusing the email.'; messageId = ''; to = @($rcpt) }
}
# ---------- end _shared/postmark.ps1 ----------
