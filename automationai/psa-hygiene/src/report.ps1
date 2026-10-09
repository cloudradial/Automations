# === NODE: Report ===
# Emails the report to the `to` recipients through Postmark, keeps a copy in YOUR OWN company's Report Archive
# "PSA Hygiene" when archive_company_id is set (Compliance > Reports, admins only; never a client company and
# never the knowledge base), and returns the result. If Postmark isn't set up and ticket_id is given, the summary
# goes on that ticket as an internal note instead, once per day and set of inputs (a marker stops a retry adding it twice). Anything that can't be delivered becomes a warning, and the
# report stays in the run output as report_html.
$ErrorActionPreference = 'Stop'
function Get-PhProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Read-PhState {
    $raw = Get-NodeInput
    if ($null -ne $raw -and $null -eq (Get-PhProp $raw 'inputs') -and $null -ne (Get-PhProp $raw 'output')) { $raw = Get-PhProp $raw 'output' }
    $st = [ordered]@{}
    if ($raw -is [System.Collections.IDictionary]) { foreach ($k in $raw.Keys) { $st[[string]$k] = $raw[$k] } }
    elseif ($null -ne $raw) { foreach ($p in $raw.PSObject.Properties) { $st[$p.Name] = $p.Value } }
    foreach ($k in @('status', 'message', 'public_note', 'internal_note', 'ticket_id', 'psa', 'psa_name')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = '' } }
    foreach ($k in @('actions', 'warnings', 'issues')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = @() } else { $st[$k] = @($st[$k]) } }
    foreach ($k in @('inputs', 'counts', 'fix')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { throw "This step expects the output of the Fix missing contacts step (no '$k')." } }
    return $st
}
function ConvertTo-PhHtml { param($v) return [System.Net.WebUtility]::HtmlEncode([string]$v) }
function Get-PhHash { param([string]$s) $h = [System.Security.Cryptography.SHA256]::Create(); try { return (-join @($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)) | Select-Object -First 6 | ForEach-Object { $_.ToString('x2') })) } finally { $h.Dispose() } }
function Get-PhPlural { param([int]$n, [string]$one, [string]$many) if ($n -eq 1) { return "1 $one" }; return "$n $many" }

$ph = Read-PhState
$opt = $ph['inputs']
$cnt = $ph['counts']
$fix = $ph['fix']
$res = Get-PhProp $fix 'result'
$confirm = [bool](Get-PhProp $opt 'confirm')
$staleDays = [int](Get-PhProp $opt 'stale_days')
$unHours = [int](Get-PhProp $opt 'unassigned_hours')
$to = @(Get-PhProp $opt 'to' | Where-Object { $_ })
$archiveId = [string](Get-PhProp $opt 'archive_company_id')
$noteTicket = [string](Get-PhProp $opt 'ticket_id')
$psaName = [string]$ph['psa_name']; if (-not $psaName) { $psaName = 'the PSA' }
$issues = @($ph['issues'] | Where-Object { $null -ne $_ })
$warnings = @($ph['warnings'])
$actions = @($ph['actions'])
$skipped = @(Get-PhProp $fix 'skipped' | Where-Object { $null -ne $_ })
$planned = @(Get-PhProp $fix 'planned' | Where-Object { $_ })
$resStatus = [string](Get-PhProp $res 'status')
$today = [datetime]::UtcNow
$openN = [int](Get-PhProp $cnt 'open_tickets')
$nStale = [int](Get-PhProp $cnt 'stale'); $nContact = [int](Get-PhProp $cnt 'missing_contact'); $nStatus = [int](Get-PhProp $cnt 'wrong_status')

# ---- Status and message ----
$summary = ''
if ($openN -eq 0) { $summary = "There are no open tickets in $psaName." }
elseif (-not $issues.Count) { $summary = "All $(Get-PhPlural $openN 'open ticket' 'open tickets') in $psaName look tidy: none is stale, missing a contact or in a status that contradicts it." }
else {
    $parts = @()
    if ($nStale) { $parts += "$nStale stale (no update for $staleDays days or more)" }
    if ($nContact) { $parts += "$nContact missing a contact" }
    if ($nStatus) { $parts += "$nStatus with a status that contradicts the ticket" }
    $summary = "Checked $(Get-PhPlural $openN 'open ticket' 'open tickets') in $psaName and found $($parts -join ', ')."
}
$status = 'success'
$fixText = ''
switch ($resStatus) {
    'preview' { $status = 'pending_confirmation'; $fixText = "Nothing was changed. With confirm set to true, this run would set the contact on $(Get-PhPlural $planned.Count 'ticket' 'tickets') whose company has exactly one primary contact." }
    'done' { $fixText = "Set the contact on $(Get-PhPlural @(Get-PhProp $res 'ran').Count 'ticket' 'tickets') from the company's only primary contact." }
    'failed' { $status = 'error'; $fixText = [string](Get-PhProp $res 'message') }
    'empty' { $fixText = $(if ([bool](Get-PhProp $fix 'requested') -and $nContact) { 'No missing contact could be filled in safely, so nothing was changed.' } else { 'Nothing was changed.' }) }
    default { $fixText = 'Nothing was changed. This run only reports.' }
}
if ($skipped.Count) { $fixText += " $(Get-PhPlural $skipped.Count 'ticket without a contact was' 'tickets without a contact were') left alone; the report says why." }
$message = "$summary $fixText".Trim()

# ---- HTML report ----
$phHtml = New-Object System.Text.StringBuilder
function Add-PhHtml { param([string]$s) $null = $phHtml.Append($s) }
function Add-PhTable {
    param([string]$Title, $Rows, [string]$Empty)
    Add-PhHtml "<h3>$(ConvertTo-PhHtml $Title)</h3>"
    $list = @($Rows)
    if (-not $list.Count) { Add-PhHtml "<p>$(ConvertTo-PhHtml $Empty)</p>"; return }
    Add-PhHtml '<table border="1" cellpadding="4" cellspacing="0" style="border-collapse:collapse;font-family:Arial,sans-serif;font-size:13px"><tr><th>Ticket</th><th>Company</th><th>Summary</th><th>Status</th><th>Assigned to</th><th>Detail</th></tr>'
    foreach ($r in @($list | Select-Object -First 200)) {
        Add-PhHtml "<tr><td>$(ConvertTo-PhHtml (Get-PhProp $r 'number'))</td><td>$(ConvertTo-PhHtml (Get-PhProp $r 'company'))</td><td>$(ConvertTo-PhHtml (Get-PhProp $r 'summary'))</td><td>$(ConvertTo-PhHtml (Get-PhProp $r 'status'))</td><td>$(ConvertTo-PhHtml (Get-PhProp $r 'assignee'))</td><td>$(ConvertTo-PhHtml (Get-PhProp $r 'detail'))</td></tr>"
    }
    Add-PhHtml '</table>'
    if ($list.Count -gt 200) { Add-PhHtml "<p>And $($list.Count - 200) more, not shown. They are in the workflow run output.</p>" }
}
$byDays = { -[int](Get-PhProp $_ 'days') }
Add-PhHtml "<h2>PSA hygiene check, $($today.ToString('yyyy-MM-dd'))</h2><p>$(ConvertTo-PhHtml $message)</p>"
Add-PhTable "Stale tickets (no update for $staleDays days or more)" @($issues | Where-Object { [string](Get-PhProp $_ 'category') -eq 'stale' } | Sort-Object $byDays) 'None.'
Add-PhTable 'Tickets with no contact' @($issues | Where-Object { [string](Get-PhProp $_ 'category') -eq 'missing_contact' } | Sort-Object $byDays) 'None.'
Add-PhTable "Status contradicts the ticket (closed date on an open ticket, or no assignee for more than $unHours hours)" @($issues | Where-Object { [string](Get-PhProp $_ 'category') -eq 'wrong_status' } | Sort-Object $byDays) 'None.'
if ($planned.Count -or $skipped.Count) {
    Add-PhHtml "<h3>Missing contacts: $(if ($confirm) { 'changes' } else { 'what confirm would change' })</h3>"
    if ($planned.Count) {
        Add-PhHtml '<ul>'
        $ranSet = @(Get-PhProp $res 'ran' | Where-Object { $null -ne $_ } | ForEach-Object { [string](Get-PhProp $_ 'description') })
        foreach ($d in $planned) {
            $state = if (-not $confirm) { 'not changed yet' } elseif ($ranSet -contains $d) { 'done' } else { 'not done' }
            Add-PhHtml "<li>$(ConvertTo-PhHtml $d) ($state)</li>"
        }
        Add-PhHtml '</ul>'
    }
    if ($skipped.Count) {
        Add-PhHtml '<p>Left alone:</p><ul>'
        foreach ($s in $skipped) { Add-PhHtml "<li>Ticket $(ConvertTo-PhHtml (Get-PhProp $s 'number')) ($(ConvertTo-PhHtml (Get-PhProp $s 'company'))): $(ConvertTo-PhHtml (Get-PhProp $s 'reason'))</li>" }
        Add-PhHtml '</ul>'
    }
}
if ($warnings.Count) { Add-PhHtml '<p>Notes:</p><ul>'; foreach ($w in $warnings) { Add-PhHtml "<li>$(ConvertTo-PhHtml $w)</li>" }; Add-PhHtml '</ul>' }
Add-PhHtml '<p>Only a missing contact is ever fixed, and only when the company has exactly one primary contact and the run says confirm. Everything else needs a person.</p>'
$html = $phHtml.ToString()
$text = $message
$subject = $(if ($confirm -and $resStatus -in @('done', 'failed')) { "PSA hygiene changes $($today.ToString('yyyy-MM-dd HH:mm')) UTC" } else { "PSA hygiene $($today.ToString('yyyy-MM-dd'))" })
$emailSubject = "$subject$(if ($issues.Count) { ": $(Get-PhPlural $issues.Count 'item' 'items') to check" } else { '' })"

# ---- Email ----
$sent = $false; $pmConfigured = Test-PmConfigured
if ($to.Count) {
    $mail = Send-PmMail -To $to -Subject $emailSubject -Html $html -Text $text
    if ($mail.sent) { $sent = $true; $actions += "Emailed the report to $($to -join ', ')." }
    else { $warnings += "$($mail.reason) The report wasn't emailed." }
}
else { $warnings += 'No recipient (the to input or the ServiceManager-Email secret), so the report wasn''t emailed.' }

# ---- Archive (your own company only) ----
$report = $null
if ($archiveId) {
    try {
        $null = Connect-Cr
        $report = Add-CrArchiveReport -CompanyId ([int]$archiveId) -ArchiveName 'PSA Hygiene' -Subject $subject -Html $html -IsError:($status -eq 'error')
        $actions += "Saved the report to the PSA Hygiene archive (item '$subject')."
    }
    catch { $warnings += "Couldn't write the report to the Report Archive: $($_.Exception.Message)" }
}

# ---- Internal note fallback when Postmark isn't set up ----
$noted = $false
if (-not $sent -and -not $pmConfigured -and $noteTicket) {
    try {
        $null = Connect-Psa ([string]$ph['psa'])
        $lines = @("PSA hygiene check: $message")
        foreach ($i in @($issues | Select-Object -First 50)) { $lines += "- Ticket $(Get-PhProp $i 'number') ($(Get-PhProp $i 'company')): $(Get-PhProp $i 'detail')" }
        if ($issues.Count -gt 50) { $lines += "And $($issues.Count - 50) more in the workflow run output." }
        # Retry guard: the same day and the same inputs give the same marker, so a ServiceAI Retry or a re-run Routine
        # finds the note already on the ticket and adds nothing. A run with other settings (or a confirm run) gets its own.
        $inKey = (@('company_id', 'stale_days', 'unassigned_hours', 'max_tickets', 'confirm') | ForEach-Object { "$_=$([string](Get-PhProp $opt $_))" }) -join '|'
        $inKey += "|fix=$(@(Get-PhProp $opt 'fix') -join ',')"
        $marker = "psa-hygiene $($today.ToString('yyyy-MM-dd')) $(Get-PhHash $inKey)"
        $nr = Add-PsaNote -Id $noteTicket -Text ($lines -join "`n") -Title 'PSA hygiene check' -Marker $marker
        $noted = $true
        $actions += $(if ($nr -eq 'already-present') { "The summary was already on ticket $noteTicket from an earlier run today, so it wasn't added again." } else { "Added the summary to ticket $noteTicket as an internal note." })
    }
    catch { $warnings += "Couldn't add the internal note to ticket $($noteTicket): $($_.Exception.Message)" }
}

if (-not $sent -and -not $noted -and $null -eq $report) { $message += ' The report is only in the run output (report_html).' }
elseif ($sent) { $message += " The report was emailed to $($to -join ', ')." }

$out = [ordered]@{
    status        = $status
    message       = $message
    public_note   = ''
    internal_note = "PSA hygiene check in $psaName. $message"
    ticket_id     = $noteTicket
    actions       = @($actions)
    warnings      = @($warnings)
    counts        = $cnt
    issues        = @($issues | Select-Object -First 1000)
    fix           = [ordered]@{ planned = @($planned); skipped = @($skipped); changed = @(Get-PhProp $res 'ran' | Where-Object { $null -ne $_ } | ForEach-Object { [string](Get-PhProp $_ 'description') }); failed = (Get-PhProp $res 'failed') }
    report        = $report
}
if (-not $sent -and $null -eq $report) { $out.report_html = $html }
Set-NodeOutput $out
