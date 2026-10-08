# === NODE: Find closed tickets ===
# Lists the tickets closed on the review day (read-only) in whichever of the six PSAs is set up.
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
    foreach ($k in @('actions', 'warnings')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = @() } else { $st[$k] = @($st[$k]) } }
    foreach ($k in $Need) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { throw "This step expects the output of the previous step (no '$k')." } }
    return $st
}
function Stop-TeRun {
    param($St, [string]$Msg)
    $St['status'] = 'error'; $St['message'] = $Msg; $St['internal_note'] = "Time entry review stopped: $Msg"
    Set-NodeOutput $St
    throw $Msg
}

$te = Read-TeState @('inputs')
$opt = $te['inputs']
try { $null = Connect-Psa (Get-PsaType ([string](Get-TeProp $opt 'psa'))) }
catch { Stop-TeRun $te "Couldn't connect to the PSA: $($_.Exception.Message)" }
$psaName = Get-PsaName

$from = Format-PsaDate (Get-TeProp $opt 'range_from')
$to = Format-PsaDate (Get-TeProp $opt 'range_to')
$found = @()
try { $found = @(Find-PsaTickets -Closed -ClosedAfter $from -ClosedBefore $to -CompanyId ([string](Get-TeProp $opt 'company_id')) -Max ([int](Get-TeProp $opt 'max_tickets'))) }
catch {
    $m = $_.Exception.Message
    if ($m -match 'HTTP 40[13]') { Stop-TeRun $te "The $psaName API account isn't allowed to read tickets ($(if ($m -match 'HTTP 401') { 'HTTP 401' } else { 'HTTP 403' })). Give it read access to service tickets and run again." }
    Stop-TeRun $te "Couldn't list the tickets closed on $(Get-TeProp $opt 'date'): $m"
}
# Company and technician names for the report (Autotask, Zendesk and others list only ids). A failed lookup
# leaves a plain fallback such as "Company 5".
Resolve-PsaTicketNames $found
# Only the fields the next steps use, so the run output stays small (the rows also carry the raw PSA record).
$tickets = @($found | ForEach-Object { [ordered]@{ id = $_.id; number = $_.number; summary = $_.summary; companyId = $_.companyId; companyName = $_.companyName; assigneeId = $_.assigneeId; assigneeName = $_.assigneeName; status = $_.status; closed = (Format-PsaDate $_.closed) } })
$warn = @($te['warnings'])
foreach ($w in @($PsaState.Warnings)) { if ($w -and $warn -notcontains $w) { $warn += $w } }
if ($PsaState.FindTruncated) { $warn += "Stopped at $(Get-TeProp $opt 'max_tickets') closed tickets (max_tickets). Later tickets from that day were not reviewed." }
$te['warnings'] = $warn
$te['psa'] = $PsaState.Conn.Psa
$te['psa_name'] = $psaName
$te['tickets'] = @($tickets)
$te['actions'] = @($te['actions']) + "Listed $($tickets.Count) ticket(s) closed in $psaName between $from and $to."
Set-NodeOutput $te
