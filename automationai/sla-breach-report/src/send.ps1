# === Step 2: Email the service manager (SLA Breach Report) ===
# Builds a plain-language HTML table of the flagged tickets, grouped by company and then technician, and
# sends it through Postmark to the "to" input. Without a "to" address or the Postmark secrets, the report
# stays in the run output (the html field). Never writes to a ticket.
# Secrets (same names as the Postmark extension): Postmark-ServerToken, Postmark-FromEmail, Postmark-ApiUrl (optional).

function Get-SlaProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-SlaSecret { param([string]$Name) $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue } catch { }; return $v }
function ConvertTo-SlaHtml { param($s) return [System.Net.WebUtility]::HtmlEncode([string]$s) }
function Format-SlaSpan {
    param([int]$Minutes)
    $m = [Math]::Abs($Minutes)
    if ($m -ge 2880) { return "$([int][Math]::Floor($m / 1440)) days" }
    if ($m -ge 60) { return "$([int][Math]::Floor($m / 60))h $($m % 60)m" }
    return "$m min"
}
function Format-SlaWhen {
    param($Value)
    # A value read back from JSON may already be a [datetime].
    if ($null -eq $Value -or ($Value -is [string] -and -not $Value)) { return 'not set' }
    if ($Value -is [datetime]) { $d = $(if ($Value.Kind -eq [DateTimeKind]::Local) { $Value.ToUniversalTime() } else { $Value }) }
    else { $d = [datetime]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal) }
    return $d.ToString('ddd d MMM, HH:mm', [Globalization.CultureInfo]::InvariantCulture) + ' UTC'
}

$prev = Get-NodeInput
if ($prev -is [string]) { $prev = $prev | ConvertFrom-Json }
$warnings = @(@(Get-SlaProp $prev 'warnings') | Where-Object { $_ })
$actions = @(@(Get-SlaProp $prev 'actions') | Where-Object { $_ })
$rows = @(@(Get-SlaProp $prev 'tickets') | Where-Object { $null -ne $_ })
$settings = Get-SlaProp $prev 'settings'
$counts = Get-SlaProp $prev 'counts'
$summary = [string](Get-SlaProp $prev 'message')
$psaName = [string](Get-SlaProp $prev 'psaName')
if ([string](Get-SlaProp $prev 'status') -ne 'success') {
    Set-NodeOutput $prev
    throw "The previous step didn't finish: $summary"
}

# ---- build the report ----
$day = Format-SlaWhen (Get-SlaProp $prev 'generatedAt')
$subject = "SLA breach report: $(@($rows | Where-Object { (Get-SlaProp $_ 'state') -eq 'breached' }).Count) breached, $(@($rows | Where-Object { (Get-SlaProp $_ 'state') -eq 'near' }).Count) near breach"
$sb = New-Object System.Text.StringBuilder
$cell = 'padding:6px 8px;border-bottom:1px solid #e5e7eb;text-align:left;vertical-align:top;'
$null = $sb.Append('<div style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#111827;">')
$null = $sb.Append("<h1 style=`"font-size:20px;margin:0 0 8px;`">SLA breach report</h1>")
$null = $sb.Append("<p style=`"margin:0 0 12px;`">$(ConvertTo-SlaHtml $summary)</p>")
$null = $sb.Append("<p style=`"margin:0 0 16px;color:#4b5563;`">Read from $(ConvertTo-SlaHtml $psaName) on $(ConvertTo-SlaHtml $day). Where $(ConvertTo-SlaHtml $psaName) has its own SLA dates for a ticket, those are used. Otherwise the target is the default number of hours for the ticket's priority, counted from when it was created. Breached tickets come first in each group.</p>")
if (-not $rows.Count) {
    $null = $sb.Append('<p style="margin:0;">Nothing needs attention this week.</p>')
}
foreach ($co in @($rows | Group-Object { [string](Get-SlaProp $_ 'company') } | Sort-Object Name)) {
    $null = $sb.Append("<h2 style=`"font-size:17px;margin:20px 0 6px;`">$(ConvertTo-SlaHtml $co.Name) ($($co.Count) ticket$(if ($co.Count -ne 1) { 's' }))</h2>")
    foreach ($tech in @($co.Group | Group-Object { [string](Get-SlaProp $_ 'technician') } | Sort-Object Name)) {
        $null = $sb.Append("<h3 style=`"font-size:15px;margin:12px 0 4px;color:#374151;`">$(ConvertTo-SlaHtml $tech.Name)</h3>")
        $null = $sb.Append("<table style=`"border-collapse:collapse;width:100%;margin-bottom:8px;`"><tr style=`"background:#f3f4f6;`"><th style=`"$cell`">Ticket</th><th style=`"$cell`">Summary</th><th style=`"$cell`">Priority</th><th style=`"$cell`">Status</th><th style=`"$cell`">Target</th><th style=`"$cell`">Where it stands</th><th style=`"$cell`">Measured by</th></tr>")
        foreach ($r in $tech.Group) {
            $state = [string](Get-SlaProp $r 'state'); $left = Get-SlaProp $r 'minutesLeft'; $kind = [string](Get-SlaProp $r 'targetKind')
            $what = switch ($kind) { 'respond' { 'Respond by' } 'resolve' { 'Resolve by' } default { 'Due' } }
            $stand = if ($state -eq 'breached') {
                if ($null -ne $left) { "Breached, $(Format-SlaSpan ([int]$left)) over" } else { "Breached ($(ConvertTo-SlaHtml $psaName) marks it out of SLA)" }
            }
            else { "Near breach: $(Get-SlaProp $r 'percentUsed')% of the time used, $(Format-SlaSpan ([int]$left)) left" }
            $color = if ($state -eq 'breached') { '#b91c1c' } else { '#b45309' }
            $prio = [string](Get-SlaProp $r 'priorityLabel'); if (-not $prio) { $prio = [string](Get-SlaProp $r 'priority') }
            $null = $sb.Append("<tr><td style=`"$cell`">$(ConvertTo-SlaHtml (Get-SlaProp $r 'number'))</td><td style=`"$cell`">$(ConvertTo-SlaHtml (Get-SlaProp $r 'summary'))</td><td style=`"$cell`">$(ConvertTo-SlaHtml $prio)</td><td style=`"$cell`">$(ConvertTo-SlaHtml (Get-SlaProp $r 'status'))</td><td style=`"$cell`">$what $(ConvertTo-SlaHtml (Format-SlaWhen (Get-SlaProp $r 'target')))</td><td style=`"$cell color:$color;font-weight:600;`">$(ConvertTo-SlaHtml $stand)</td><td style=`"$cell`">$(ConvertTo-SlaHtml (Get-SlaProp $r 'slaSource'))</td></tr>")
        }
        $null = $sb.Append('</table>')
    }
}
$null = $sb.Append('<p style="margin:16px 0 0;color:#6b7280;font-size:12px;">Sent by the AutomationAI SLA Breach Report. It reads tickets only and changes nothing.</p></div>')
$html = $sb.ToString()
$text = "$summary`n`n" + ((@($rows | ForEach-Object { "- $(Get-SlaProp $_ 'company') / $(Get-SlaProp $_ 'technician'): #$(Get-SlaProp $_ 'number') $(Get-SlaProp $_ 'summary') ($(if ((Get-SlaProp $_ 'state') -eq 'breached') { 'breached' } else { 'near breach' }))" })) -join "`n")

# ---- send it ----
$to = @(@(Get-SlaProp $settings 'to') | Where-Object { $_ })
$sent = $false; $status = 'success'; $delivery = ''
$token = Get-SlaSecret 'Postmark-ServerToken'
$from = [string](Get-SlaProp $settings 'from'); if (-not $from) { $from = Get-SlaSecret 'Postmark-FromEmail' }
$api = Get-SlaSecret 'Postmark-ApiUrl'; if (-not $api) { $api = 'https://api.postmarkapp.com' }
$api = $api.TrimEnd('/') -replace '/email$', ''
$stream = [string](Get-SlaProp $settings 'message_stream'); if (-not $stream) { $stream = 'outbound' }
if (-not $to.Count) {
    $delivery = 'No "to" address was given, so the report is only in the run output.'
    $warnings += $delivery
}
elseif (-not $token -or -not $from) {
    $delivery = 'Postmark is not set up (add the Postmark-ServerToken and Postmark-FromEmail secrets), so the report is only in the run output.'
    $warnings += $delivery
}
else {
    $body = @{ From = $from; To = ($to -join ','); Subject = $subject; HtmlBody = $html; TextBody = $text; MessageStream = $stream; Tag = 'sla-breach-report' } | ConvertTo-Json -Depth 4 -Compress
    try {
        $r = Invoke-RestMethod -Method POST -Uri "$api/email" -Headers @{ 'X-Postmark-Server-Token' = $token; Accept = 'application/json' } -ContentType 'application/json' -Body $body -ErrorAction Stop
        $ec = Get-SlaProp $r 'ErrorCode'
        if ($null -ne $ec -and [int]$ec -ne 0) { throw "Postmark error $ec`: $(Get-SlaProp $r 'Message')" }
        $sent = $true; $delivery = "Emailed the report to $($to -join ', ')."
        $actions += $delivery
    }
    catch {
        $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        $why = [string]$_.Exception.Message; try { if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $why = $_.ErrorDetails.Message } } catch { }
        $delivery = if ($code -eq 401 -or $code -eq 403) { "Postmark refused the email (HTTP $code). Check the Postmark-ServerToken secret and that the sender is verified." } else { "The report couldn't be emailed: $why" }
        $warnings += $delivery
        $status = 'incomplete'
    }
}

Set-NodeOutput ([ordered]@{
        status = $status; message = "$summary $delivery".Trim(); public_note = ''
        internal_note = "SLA Breach Report ran against $psaName. $summary $delivery".Trim(); ticket_id = ''
        email_sent = $sent; recipients = @($to); subject = $subject; counts = $counts; tickets = @($rows); html = $html
        actions = @($actions); warnings = @($warnings)
    })
