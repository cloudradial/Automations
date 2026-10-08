# ---------- src/mail.ps1: staff email through Postmark ----------
# The identical file ships in automationai/time-entry-review/src and automationai/psa-hygiene/src.
# Same secret names as the Postmark catalog extension and automationai/deliver-result:
#   Postmark-ServerToken (required), Postmark-FromEmail (required, a verified sender), Postmark-ApiUrl (optional,
#   default https://api.postmarkapp.com).
# Send-PmMail returns @{ configured; sent; reason; messageId } and never throws, so a report still finishes
# when email fails. configured is $false when the token or sender is missing.
function Get-PmSecret { param([string]$Name) $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue } catch { }; return $v }
function Get-PmProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Test-PmConfigured { return (-not [string]::IsNullOrWhiteSpace((Get-PmSecret 'Postmark-ServerToken')) -and -not [string]::IsNullOrWhiteSpace((Get-PmSecret 'Postmark-FromEmail'))) }

function Send-PmMail {
    param([string[]]$To, [string]$Subject, [string]$Html, [string]$Text = '', [string]$Stream = 'outbound')
    $token = Get-PmSecret 'Postmark-ServerToken'
    $from = Get-PmSecret 'Postmark-FromEmail'
    if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($from)) {
        $miss = @(@('Postmark-ServerToken', 'Postmark-FromEmail') | Where-Object { [string]::IsNullOrWhiteSpace((Get-PmSecret $_)) })
        return @{ configured = $false; sent = $false; reason = "Postmark isn't set up (missing $($miss -join ' and '))."; messageId = '' }
    }
    $rcpt = @($To | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (-not $rcpt.Count) { return @{ configured = $true; sent = $false; reason = 'No recipient was given.'; messageId = '' } }
    $api = Get-PmSecret 'Postmark-ApiUrl'; if ([string]::IsNullOrWhiteSpace($api)) { $api = 'https://api.postmarkapp.com' }
    $body = [ordered]@{ From = $from.Trim(); To = ($rcpt -join ','); Subject = $Subject; HtmlBody = $Html; MessageStream = $Stream }
    if ($Text) { $body.TextBody = $Text }
    $h = @{ 'X-Postmark-Server-Token' = $token.Trim(); Accept = 'application/json' }
    for ($i = 1; $i -le 3; $i++) {
        try {
            $r = Invoke-RestMethod -Method POST -Uri "$($api.TrimEnd('/'))/email" -Headers $h -Body (ConvertTo-Json -InputObject $body -Depth 5 -Compress) -ContentType 'application/json' -ErrorAction Stop
            $code = Get-PmProp $r 'ErrorCode'
            if ($null -ne $code -and [int]$code -ne 0) { return @{ configured = $true; sent = $false; reason = "Postmark refused the email: $(Get-PmProp $r 'Message')"; messageId = '' } }
            return @{ configured = $true; sent = $true; reason = ''; messageId = [string](Get-PmProp $r 'MessageID') }
        }
        catch {
            $status = 0; try { $status = [int]$_.Exception.Response.StatusCode } catch { }
            if (($status -eq 429 -or $status -ge 500) -and $i -lt 3) { Start-Sleep -Seconds (2 * $i); continue }
            $d = $null; try { if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $d = $_.ErrorDetails.Message } } catch { }
            if (-not $d) { $d = [string]$_.Exception.Message }
            $msg = $d; try { $j = $d | ConvertFrom-Json -ErrorAction Stop; $m = Get-PmProp $j 'Message'; if ($m) { $msg = [string]$m } } catch { }
            $why = if ($status -eq 401) { 'Postmark rejected the server token (HTTP 401). Check the Postmark-ServerToken secret.' } else { "Postmark couldn't send the email$(if ($status) { " (HTTP $status)" }): $msg" }
            return @{ configured = $true; sent = $false; reason = $why; messageId = '' }
        }
    }
    return @{ configured = $true; sent = $false; reason = 'Postmark kept refusing the email.'; messageId = '' }
}
# ---------- end src/mail.ps1 ----------
