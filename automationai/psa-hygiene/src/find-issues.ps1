# === NODE: Find stale tickets, missing contacts and wrong status ===
# Lists every open ticket (read-only) and sorts out three kinds of problem:
#   stale            no update for stale_days days or more
#   missing_contact  no contact on the ticket
#   wrong_status     the status contradicts the ticket: a closed date is set but the ticket is open,
#                    or it is open with no assignee for longer than unassigned_hours
$ErrorActionPreference = 'Stop'
function Get-PhProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Read-PhState {
    param([string[]]$Need)
    $raw = Get-NodeInput
    if ($null -ne $raw -and $null -eq (Get-PhProp $raw 'inputs') -and $null -ne (Get-PhProp $raw 'output')) { $raw = Get-PhProp $raw 'output' }
    $st = [ordered]@{}
    if ($raw -is [System.Collections.IDictionary]) { foreach ($k in $raw.Keys) { $st[[string]$k] = $raw[$k] } }
    elseif ($null -ne $raw) { foreach ($p in $raw.PSObject.Properties) { $st[$p.Name] = $p.Value } }
    foreach ($k in @('status', 'message', 'public_note', 'internal_note', 'ticket_id')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = '' } }
    foreach ($k in @('actions', 'warnings')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = @() } else { $st[$k] = @($st[$k]) } }
    foreach ($k in $Need) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { throw "This step expects the output of the previous step (no '$k')." } }
    return $st
}
function Stop-PhRun {
    param($St, [string]$Msg)
    $St['status'] = 'error'; $St['message'] = $Msg; $St['internal_note'] = "PSA hygiene check stopped: $Msg"
    Set-NodeOutput $St
    throw $Msg
}
function Get-PhUtc { param($v) return (ConvertTo-PsaDate $v) }
function Get-PhShort { param([string]$s, [int]$n) $s = ($s -replace '\s+', ' ').Trim(); if ($s.Length -gt $n) { return $s.Substring(0, $n - 1) + '...' }; return $s }

$ph = Read-PhState @('inputs')
$opt = $ph['inputs']
$staleDays = [int](Get-PhProp $opt 'stale_days')
$unHours = [int](Get-PhProp $opt 'unassigned_hours')
try { $null = Connect-Psa (Get-PsaType ([string](Get-PhProp $opt 'psa'))) }
catch { Stop-PhRun $ph "Couldn't connect to the PSA: $($_.Exception.Message) Nothing was changed." }
$psaName = Get-PsaName
$psa = $PsaState.Conn.Psa

$open = @()
try { $open = @(Find-PsaTickets -Open -CompanyId ([string](Get-PhProp $opt 'company_id')) -Max ([int](Get-PhProp $opt 'max_tickets'))) }
catch {
    $m = $_.Exception.Message
    if ($m -match 'HTTP 40[13]') { Stop-PhRun $ph "The $psaName API account isn't allowed to read tickets ($(if ($m -match 'HTTP 401') { 'HTTP 401' } else { 'HTTP 403' })). Give it read access to service tickets and run again. Nothing was changed." }
    Stop-PhRun $ph "Couldn't list the open tickets: $m Nothing was changed."
}
# Company and technician names for the report (Autotask, Zendesk and others list only ids). A failed lookup
# leaves a plain fallback such as "Company 5".
Resolve-PsaTicketNames $open
$warn = @($ph['warnings'])
foreach ($w in @($PsaState.Warnings)) { if ($w -and $warn -notcontains $w) { $warn += $w } }
if ($PsaState.FindTruncated) { $warn += "Stopped at $(Get-PhProp $opt 'max_tickets') open tickets (max_tickets), so later tickets were not checked." }
$checkContacts = $psa -ne 'syncro'
if (-not $checkContacts) { $warn += 'Syncro tickets without a contact are addressed to the customer record itself, so missing contacts were not checked.' }

$now = [datetime]::UtcNow
$issues = New-Object System.Collections.ArrayList
$counts = [ordered]@{ open_tickets = $open.Count; stale = 0; missing_contact = 0; wrong_status = 0; tickets_with_issues = 0 }
foreach ($t in $open) {
    $base = [ordered]@{ ticket_id = [string]$t.id; number = [string]$t.number; summary = (Get-PhShort ([string]$t.summary) 80); companyId = [string]$t.companyId; company = [string]$t.companyName; status = [string]$t.status; assignee = $(if ($t.assigneeId -and $t.assigneeName) { [string]$t.assigneeName } else { [string]$t.assigneeId }) }
    if (-not $base.company -and $base.companyId) { $base.company = "Company $($base.companyId)" }
    $hit = $false
    $updated = Get-PhUtc $t.updated; $created = Get-PhUtc $t.created
    $last = if ($null -ne $updated) { $updated } else { $created }
    if ($null -ne $last) {
        $days = [int][Math]::Floor(($now - $last).TotalDays)
        if ($days -ge $staleDays) {
            $f = [ordered]@{}; foreach ($k in $base.Keys) { $f[$k] = $base[$k] }
            $f.category = 'stale'; $f.days = $days; $f.detail = "No update for $days days (last update $($last.ToString('yyyy-MM-dd')))."
            $null = $issues.Add($f); $counts.stale++; $hit = $true
        }
    }
    if ($checkContacts -and -not $t.contactId) {
        $f = [ordered]@{}; foreach ($k in $base.Keys) { $f[$k] = $base[$k] }
        $f.category = 'missing_contact'; $f.days = $(if ($null -ne $created) { [int][Math]::Floor(($now - $created).TotalDays) } else { 0 }); $f.detail = 'No contact on the ticket.'
        $null = $issues.Add($f); $counts.missing_contact++; $hit = $true
    }
    $closedAt = Get-PhUtc $t.closed
    if ($null -ne $closedAt) {
        $f = [ordered]@{}; foreach ($k in $base.Keys) { $f[$k] = $base[$k] }
        $f.category = 'wrong_status'; $f.days = [int][Math]::Floor(($now - $closedAt).TotalDays); $f.detail = "Has a closed date ($($closedAt.ToString('yyyy-MM-dd'))) but its status '$($base.status)' is open."
        $null = $issues.Add($f); $counts.wrong_status++; $hit = $true
    }
    if (-not $t.assigneeId -and $null -ne $created) {
        $hours = ($now - $created).TotalHours
        if ($hours -gt $unHours) {
            $f = [ordered]@{}; foreach ($k in $base.Keys) { $f[$k] = $base[$k] }
            $f.category = 'wrong_status'; $f.days = [int][Math]::Floor(($now - $created).TotalDays)
            $f.detail = "Open with no assignee for $(if ($hours -ge 48) { "$([int][Math]::Floor($hours / 24)) days" } else { "$([int][Math]::Floor($hours)) hours" })."
            $null = $issues.Add($f); $counts.wrong_status++; $hit = $true
        }
    }
    if ($hit) { $counts.tickets_with_issues++ }
}

$ph['warnings'] = $warn
$ph['psa'] = $psa
$ph['psa_name'] = $psaName
$ph['issues'] = @($issues)
$ph['counts'] = $counts
$ph['actions'] = @($ph['actions']) + "Checked $($open.Count) open ticket(s) in $psaName."
Set-NodeOutput $ph
