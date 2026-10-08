# === Step 3: Notify the dispatcher (Auto-Escalation) ===
# Sends one email per run to dispatcher_email through Postmark, listing every escalated ticket, why, and
# what was done. Without a dispatcher_email or the Postmark secrets, the internal note the next step writes
# on each ticket is the notification. Does nothing in preview or when nothing was escalated.
# Secrets (same names as the Postmark extension): Postmark-ServerToken, Postmark-FromEmail, Postmark-ApiUrl (optional).

function Get-EscProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-EscSecret { param([string]$Name) $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue } catch { }; return $v }
function ConvertTo-EscHtml { param($s) return [System.Net.WebUtility]::HtmlEncode([string]$s) }
function ConvertTo-EscHash {
    param($o)
    $h = [ordered]@{}
    if ($o -is [System.Collections.IDictionary]) { foreach ($k in @($o.Keys)) { $h[[string]$k] = $o[$k] } }
    elseif ($null -ne $o) { foreach ($p in @($o.PSObject.Properties)) { $h[$p.Name] = $p.Value } }
    return $h
}

$prev = ConvertTo-EscHash (Get-NodeInput)
$st = [string](Get-EscProp $prev 'status')
if ($st -notin @('success', 'pending_confirmation')) { Set-NodeOutput $prev; throw "The previous step didn't finish: $(Get-EscProp $prev 'message')" }
$settings = Get-EscProp $prev 'settings'
$escalations = @(@(Get-EscProp $prev 'escalations') | Where-Object { $null -ne $_ })
$actions = @(@(Get-EscProp $prev 'actions') | Where-Object { $_ })
$warnings = @(@(Get-EscProp $prev 'warnings') | Where-Object { $_ })
$preview = (Get-EscProp $prev 'preview') -eq $true
$to = @(@(Get-EscProp $settings 'dispatcher_email') | Where-Object { $_ })
$psaName = [string](Get-EscProp $prev 'psaName')

$emailed = $false; $delivery = ''
if ($preview) { $delivery = 'Preview: no email was sent.' }
elseif (-not $escalations.Count) { $delivery = 'Nothing was escalated, so no email was sent.' }
else {
    $token = Get-EscSecret 'Postmark-ServerToken'
    $from = [string](Get-EscProp $settings 'from'); if (-not $from) { $from = Get-EscSecret 'Postmark-FromEmail' }
    $api = Get-EscSecret 'Postmark-ApiUrl'; if (-not $api) { $api = 'https://api.postmarkapp.com' }
    $api = $api.TrimEnd('/') -replace '/email$', ''
    $stream = [string](Get-EscProp $settings 'message_stream'); if (-not $stream) { $stream = 'outbound' }
    if (-not $to.Count) { $delivery = 'No dispatcher_email was given, so the internal note on each ticket is the dispatcher notification.'; $warnings += $delivery }
    elseif (-not $token -or -not $from) { $delivery = 'Postmark is not set up (add the Postmark-ServerToken and Postmark-FromEmail secrets), so the internal note on each ticket is the dispatcher notification.'; $warnings += $delivery }
    else {
        $n = $escalations.Count
        $moved = @($escalations | Where-Object { (Get-EscProp $_ 'result') -in @('reassigned', 'partial') }).Count
        $subject = "Auto-Escalation: $n ticket$(if ($n -ne 1) { 's' }) escalated"
        $cell = 'padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:left;vertical-align:top;'
        $sb = New-Object System.Text.StringBuilder
        $null = $sb.Append('<div style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#111827;">')
        $null = $sb.Append("<p style=`"margin:0 0 12px;`">$n ticket$(if ($n -ne 1) { 's were' } else { ' was' }) escalated in $(ConvertTo-EscHtml $psaName). $moved moved up a tier. Any others were flagged without being moved, and the table says why. Each ticket also has an internal note with the same detail.</p>")
        $null = $sb.Append("<table style=`"border-collapse:collapse;width:100%;`"><tr style=`"background:#f3f4f6;`"><th style=`"$cell`">Ticket</th><th style=`"$cell`">Company</th><th style=`"$cell`">Summary</th><th style=`"$cell`">Priority</th><th style=`"$cell`">Technician</th><th style=`"$cell`">Why</th><th style=`"$cell`">What happened</th></tr>")
        foreach ($e in $escalations) {
            $prio = [string](Get-EscProp $e 'priorityLabel'); if (-not $prio) { $prio = [string](Get-EscProp $e 'priority') }
            $null = $sb.Append("<tr><td style=`"$cell`">$(ConvertTo-EscHtml (Get-EscProp $e 'number'))</td><td style=`"$cell`">$(ConvertTo-EscHtml (Get-EscProp $e 'company'))</td><td style=`"$cell`">$(ConvertTo-EscHtml (Get-EscProp $e 'summary'))</td><td style=`"$cell`">$(ConvertTo-EscHtml $prio)</td><td style=`"$cell`">$(ConvertTo-EscHtml (Get-EscProp $e 'technician'))</td><td style=`"$cell`">$(ConvertTo-EscHtml (Get-EscProp $e 'reason'))</td><td style=`"$cell`">$(ConvertTo-EscHtml (Get-EscProp $e 'outcome'))</td></tr>")
        }
        $null = $sb.Append('</table><p style="margin:16px 0 0;color:#6b7280;font-size:12px;">Sent by the AutomationAI Auto-Escalation workflow. A ticket is escalated once; the [Auto-Escalation] note stops it being escalated again.</p></div>')
        $text = (@($escalations | ForEach-Object { "- #$(Get-EscProp $_ 'number') $(Get-EscProp $_ 'company'): $(Get-EscProp $_ 'summary'). $(Get-EscProp $_ 'reason') $(Get-EscProp $_ 'outcome')" })) -join "`n"
        $body = @{ From = $from; To = ($to -join ','); Subject = $subject; HtmlBody = $sb.ToString(); TextBody = $text; MessageStream = $stream; Tag = 'auto-escalation' } | ConvertTo-Json -Depth 4 -Compress
        try {
            $r = Invoke-RestMethod -Method POST -Uri "$api/email" -Headers @{ 'X-Postmark-Server-Token' = $token; Accept = 'application/json' } -ContentType 'application/json' -Body $body -ErrorAction Stop
            $ec = Get-EscProp $r 'ErrorCode'
            if ($null -ne $ec -and [int]$ec -ne 0) { throw "Postmark error $ec`: $(Get-EscProp $r 'Message')" }
            $emailed = $true; $delivery = "The dispatcher was emailed ($($to -join ', '))."
            $actions += $delivery
        }
        catch {
            $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch { }
            $why = [string]$_.Exception.Message; try { if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $why = $_.ErrorDetails.Message } } catch { }
            $delivery = if ($code -eq 401 -or $code -eq 403) { "Postmark refused the dispatcher email (HTTP $code), so the internal note on each ticket is the notification. Check the Postmark-ServerToken secret and that the sender is verified." } else { "The dispatcher email couldn't be sent ($why), so the internal note on each ticket is the notification." }
            $warnings += $delivery
        }
    }
}

$prev.dispatcher_emailed = $emailed
$prev.delivery = $delivery
$prev.actions = @($actions)
$prev.warnings = @($warnings)
Set-NodeOutput $prev
