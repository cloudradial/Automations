# === NODE: Review time entries ===
# Reads each closed ticket's time entries (read-only) and flags:
#   no_time           the ticket was closed with no time logged (or only zero-hour entries)
#   short_note        a time entry whose note is shorter than min_note_chars
#   missing_billable  a time entry with no billable setting, where the PSA has one
$ErrorActionPreference = 'Stop'
function Get-TeProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Read-TeState {
    param([string[]]$Need)
    $raw = Get-NodeInput
    if ($null -ne $raw -and $null -eq (Get-TeProp $raw 'inputs') -and $null -ne (Get-TeProp $raw 'output')) { $raw = Get-TeProp $raw 'output' }
    $st = [ordered]@{}
    if ($raw -is [System.Collections.IDictionary]) { foreach ($k in $raw.Keys) { $st[[string]$k] = $raw[$k] } }
    elseif ($null -ne $raw) { foreach ($p in $raw.PSObject.Properties) { $st[$p.Name] = $p.Value } }
    foreach ($k in @('status', 'message', 'public_note', 'internal_note', 'ticket_id')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = '' } }
    foreach ($k in @('actions', 'warnings', 'tickets')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = @() } else { $st[$k] = @($st[$k]) } }
    foreach ($k in $Need) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { throw "This step expects the output of the previous step (no '$k')." } }
    return $st
}
function Stop-TeRun {
    param($St, [string]$Msg)
    $St['status'] = 'error'; $St['message'] = $Msg; $St['internal_note'] = "Time entry review stopped: $Msg"
    Set-NodeOutput $St
    throw $Msg
}
function Get-TeShort { param([string]$s, [int]$n) $s = ($s -replace '\s+', ' ').Trim(); if ($s.Length -gt $n) { return $s.Substring(0, $n - 1) + '...' }; return $s }

$te = Read-TeState @('inputs', 'psa')
$opt = $te['inputs']
$minNote = [int](Get-TeProp $opt 'min_note_chars')
$checkBillable = [bool](Get-TeProp $opt 'check_billable')
$zdField = [string](Get-TeProp $opt 'zendesk_time_field_id')
$tickets = @($te['tickets'] | Where-Object { $null -ne $_ })
$warn = @($te['warnings'])
$findings = New-Object System.Collections.ArrayList
$counts = [ordered]@{ tickets_closed = $tickets.Count; tickets_checked = 0; no_time = 0; short_note = 0; missing_billable = 0; entries_read = 0; unreadable = 0 }
$timeSupported = $true; $timeReason = ''

if ($tickets.Count) {
    try { $null = Connect-Psa ([string]$te['psa']) }
    catch { Stop-TeRun $te "Couldn't connect to the PSA: $($_.Exception.Message)" }
}
$psaName = Get-PsaName

foreach ($t in $tickets) {
    $tid = [string](Get-TeProp $t 'id')
    $base = [ordered]@{ ticket_id = $tid; number = [string](Get-TeProp $t 'number'); summary = (Get-TeShort ([string](Get-TeProp $t 'summary')) 80); company = [string](Get-TeProp $t 'companyName'); companyId = [string](Get-TeProp $t 'companyId'); assignee = [string](Get-TeProp $t 'assigneeName') }
    if (-not $base.assignee) { $base.assignee = [string](Get-TeProp $t 'assigneeId') }
    if (-not $base.company -and $base.companyId) { $base.company = "Company $($base.companyId)" }
    $res = $null
    try { $res = Get-PsaTimeEntries -TicketId $tid -ZendeskTimeFieldId $zdField }
    catch {
        $m = $_.Exception.Message
        if ($m -match 'HTTP 40[13]') { Stop-TeRun $te "The $psaName API account isn't allowed to read time entries ($(if ($m -match 'HTTP 401') { 'HTTP 401' } else { 'HTTP 403' })). Give it read access to time entries and run again." }
        $counts.unreadable++
        $warn += "Couldn't read the time on ticket $($base.number): $m"
        continue
    }
    if (-not [bool]$res.supported) {
        $timeSupported = $false; $timeReason = [string]$res.reason
        if ([string]$te['psa'] -eq 'zendesk' -and $timeReason -notmatch 'zendesk_time_field_id') { $timeReason += ' Put that field id in the zendesk_time_field_id input.' }
        break
    }
    foreach ($w in @($res.warnings)) { if ($w -and $warn -notcontains $w) { $warn += [string]$w } }
    $counts.tickets_checked++
    $entries = @($res.entries | Where-Object { $null -ne $_ })
    $counts.entries_read += $entries.Count
    $hours = 0.0; foreach ($e in $entries) { $hours += [double]$e.hours }
    if ($hours -le 0) {
        $counts.no_time++
        $f = [ordered]@{}; foreach ($k in $base.Keys) { $f[$k] = $base[$k] }
        $f.issue = 'no_time'; $f.detail = 'Closed with no time logged.'; $f.technician = $base.assignee; $f.hours = 0; $f.entry_id = ''
        $null = $findings.Add($f)
    }
    foreach ($e in $entries) {
        if ([double]$e.hours -le 0) { continue }
        $who = [string]$e.member; if (-not $who) { $who = $base.assignee }
        if ($minNote -gt 0 -and [bool]$e.notesKnown) {
            $len = ([string]$e.notes).Trim().Length
            if ($len -lt $minNote) {
                $counts.short_note++
                $f = [ordered]@{}; foreach ($k in $base.Keys) { $f[$k] = $base[$k] }
                $f.issue = 'short_note'
                $f.detail = $(if ($len -eq 0) { 'Time entry has no note.' } else { "Time entry note is only $len characters: `"$(Get-TeShort ([string]$e.notes) 60)`"" })
                $f.technician = $who; $f.hours = [double]$e.hours; $f.entry_id = [string]$e.id
                $null = $findings.Add($f)
            }
        }
        if ($checkBillable -and [bool]$e.billableKnown -and $null -eq $e.billable) {
            $counts.missing_billable++
            $f = [ordered]@{}; foreach ($k in $base.Keys) { $f[$k] = $base[$k] }
            $f.issue = 'missing_billable'; $f.detail = 'Time entry has no billable setting.'; $f.technician = $who; $f.hours = [double]$e.hours; $f.entry_id = [string]$e.id
            $null = $findings.Add($f)
        }
    }
}
if (-not $timeSupported) { $warn += $timeReason }

$te['warnings'] = $warn
$te['findings'] = @($findings)
$te['counts'] = $counts
$te['time_supported'] = $timeSupported
$te['time_reason'] = $timeReason
$te['actions'] = @($te['actions']) + $(if ($timeSupported) { "Read $($counts.entries_read) time entr$(if ($counts.entries_read -eq 1) { 'y' } else { 'ies' }) on $($counts.tickets_checked) ticket(s)." } else { "Skipped the time check: $timeReason" })
Set-NodeOutput $te
