# === NODE: Email the service manager ===
# Builds a plain table of the findings and emails it through Postmark to the `to` recipients.
# Without Postmark (or without a recipient) the report stays in the run output as report_html and report_text.
# Never writes to a ticket.
$ErrorActionPreference = 'Stop'
function Get-TeProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Read-TeState {
    $raw = Get-NodeInput
    if ($null -ne $raw -and $null -eq (Get-TeProp $raw 'inputs') -and $null -ne (Get-TeProp $raw 'output')) { $raw = Get-TeProp $raw 'output' }
    $st = [ordered]@{}
    if ($raw -is [System.Collections.IDictionary]) { foreach ($k in $raw.Keys) { $st[[string]$k] = $raw[$k] } }
    elseif ($null -ne $raw) { foreach ($p in $raw.PSObject.Properties) { $st[$p.Name] = $p.Value } }
    foreach ($k in @('status', 'message', 'public_note', 'internal_note', 'ticket_id', 'psa_name', 'time_reason')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = '' } }
    foreach ($k in @('actions', 'warnings', 'findings')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = @() } else { $st[$k] = @($st[$k]) } }
    foreach ($k in @('inputs', 'counts', 'time_supported')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { throw "This step expects the output of the Review time entries step (no '$k')." } }
    return $st
}
function ConvertTo-TeHtml { param($v) return [System.Net.WebUtility]::HtmlEncode([string]$v) }
function Get-TePlural { param([int]$n, [string]$one, [string]$many) if ($n -eq 1) { return "1 $one" }; return "$n $many" }
function Get-TeDay { param($v) if ($v -is [datetime]) { return $v.ToString('yyyy-MM-dd') }; return [string]$v }

$te = Read-TeState
$opt = $te['inputs']
$cnt = $te['counts']
$day = Get-TeDay (Get-TeProp $opt 'date')
$tzName = [string](Get-TeProp $opt 'timezone')
$psaName = [string]$te['psa_name']; if (-not $psaName) { $psaName = 'the PSA' }
$minNote = [int](Get-TeProp $opt 'min_note_chars')
$to = @(Get-TeProp $opt 'to' | Where-Object { $_ })
$findings = @($te['findings'] | Where-Object { $null -ne $_ })
$warnings = @($te['warnings'])
$actions = @($te['actions'])
$timeOk = [bool]$te['time_supported']
$closedN = [int](Get-TeProp $cnt 'tickets_closed')
$noTime = [int](Get-TeProp $cnt 'no_time'); $short = [int](Get-TeProp $cnt 'short_note'); $noBill = [int](Get-TeProp $cnt 'missing_billable')

# ---- Summary sentence ----
$dayText = "$day ($tzName)"
$summary = ''
if ($closedN -eq 0) { $summary = "No tickets were closed in $psaName on $dayText." }
elseif (-not $timeOk) { $summary = "$(Get-TePlural $closedN 'ticket was' 'tickets were') closed in $psaName on $dayText, but their time couldn't be checked: $($te['time_reason'])" }
elseif (-not $findings.Count) { $summary = "All $(Get-TePlural $closedN 'ticket' 'tickets') closed in $psaName on $dayText have time logged with notes of at least $minNote characters$(if ([bool](Get-TeProp $opt 'check_billable')) { ' and a billable setting' })." }
else {
    $parts = @()
    if ($noTime) { $parts += "$(Get-TePlural $noTime 'was' 'were') closed with no time logged" }
    if ($short) { $parts += "$(Get-TePlural $short 'time entry has' 'time entries have') a note shorter than $minNote characters" }
    if ($noBill) { $parts += "$(Get-TePlural $noBill 'time entry has' 'time entries have') no billable setting" }
    $lead = "Of the $(Get-TePlural $closedN 'ticket' 'tickets') closed in $psaName on $dayText, "
    $summary = $lead + ($parts -join '; ') + '.'
    if ($noTime -and -not $short -and -not $noBill) { $summary = "$(Get-TePlural $noTime 'ticket' 'tickets') of the $closedN closed in $psaName on $dayText $(if ($noTime -eq 1) { 'was' } else { 'were' }) closed with no time logged." }
}

# ---- Plain table ----
$issueText = @{ no_time = 'No time logged'; short_note = 'Short note'; missing_billable = 'No billable setting' }
$order = @{ no_time = 0; short_note = 1; missing_billable = 2 }
$rows = @($findings | Sort-Object { $order[[string](Get-TeProp $_ 'issue')] }, { [string](Get-TeProp $_ 'technician') }, { [string](Get-TeProp $_ 'number') })
$sb = New-Object System.Text.StringBuilder
$null = $sb.Append("<p>$(ConvertTo-TeHtml $summary)</p>")
if ($rows.Count) {
    $null = $sb.Append('<table border="1" cellpadding="4" cellspacing="0" style="border-collapse:collapse;font-family:Arial,sans-serif;font-size:13px"><tr><th>Ticket</th><th>Company</th><th>Summary</th><th>Technician</th><th>Issue</th><th>Hours</th><th>Detail</th></tr>')
    foreach ($r in $rows) {
        $null = $sb.Append("<tr><td>$(ConvertTo-TeHtml (Get-TeProp $r 'number'))</td><td>$(ConvertTo-TeHtml (Get-TeProp $r 'company'))</td><td>$(ConvertTo-TeHtml (Get-TeProp $r 'summary'))</td><td>$(ConvertTo-TeHtml (Get-TeProp $r 'technician'))</td><td>$(ConvertTo-TeHtml $issueText[[string](Get-TeProp $r 'issue')])</td><td>$(ConvertTo-TeHtml (Get-TeProp $r 'hours'))</td><td>$(ConvertTo-TeHtml (Get-TeProp $r 'detail'))</td></tr>")
    }
    $null = $sb.Append('</table>')
}
if ($warnings.Count) { $null = $sb.Append('<p>Notes:</p><ul>'); foreach ($w in $warnings) { $null = $sb.Append("<li>$(ConvertTo-TeHtml $w)</li>") }; $null = $sb.Append('</ul>') }
$null = $sb.Append('<p>This report only reads the PSA. Nothing was changed.</p>')
$html = $sb.ToString()
$text = $summary
if ($rows.Count) { $text += "`n`n" + ((@($rows | ForEach-Object { "Ticket $(Get-TeProp $_ 'number') ($(Get-TeProp $_ 'company')), $(Get-TeProp $_ 'technician'): $(Get-TeProp $_ 'detail')" })) -join "`n") }
$subject = "Time entry review for $day$(if ($findings.Count) { ": $(Get-TePlural $findings.Count 'item' 'items') to check" } else { '' })"

# ---- Send ----
$sent = $false
if ($to.Count) {
    $mail = Send-PmMail -To $to -Subject $subject -Html $html -Text $text
    if ($mail.sent) { $sent = $true; $actions += "Emailed the report to $($to -join ', ')." }
    elseif (-not $mail.configured) { $warnings += "$($mail.reason) The report is only in the run output." }
    else { $warnings += "$($mail.reason) The report is only in the run output." }
}

$status = 'success'
if ($closedN -gt 0 -and -not $timeOk) { $status = 'incomplete' }
$message = $summary
if ($sent) { $message += " The list was emailed to $($to -join ', ')." }
elseif ($findings.Count -or -not $timeOk) { $message += ' The list is in the run output (report_html); it was not emailed.' }

$emailed = @(); if ($sent) { $emailed = @($to) }
$out = [ordered]@{
    status        = $status
    message       = $message
    public_note   = ''
    internal_note = "Time entry review for $dayText in $psaName. $message Read-only: no ticket was changed."
    ticket_id     = ''
    actions       = @($actions)
    warnings      = @($warnings)
    date          = $day
    timezone      = $tzName
    counts        = $cnt
    findings      = @($rows)
    emailed_to    = @($emailed)
    report_html   = $html
    report_text   = $text
}
Set-NodeOutput $out
