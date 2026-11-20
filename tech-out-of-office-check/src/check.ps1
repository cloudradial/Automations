# Step 1: Check whether the assigned technician is out.
# Two ways in:
#   One ticket (ticketId in the body: a ServiceAI Action or a test run): reads the ticket and checks every member on
#     it (owner, resources, and the member the request names while there is no owner) against the In/Out Board and
#     the schedule.
#   A sweep (no ticketId: a Routine every few minutes): finds who is out right now, then their open tickets entered
#     in the last OOO-LookbackMinutes on the OOO-Boards boards, and hands each one to the act step.
# Nobody out, nobody assigned, or already handled: the act step does nothing and the run ends with status success.
$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
$stopState = @{ done = $false }
function Add-CheckPsaWarnings { foreach ($w in @($PsaState.Warnings)) { if ($w -and -not $warnings.Contains([string]$w)) { $null = $warnings.Add([string]$w) } } }
function Stop-Check {
    param([string]$Status, [string]$Why, [string]$TicketId = '')
    $stopState.done = $true
    Add-CheckPsaWarnings
    Set-NodeOutput ([ordered]@{ status = $Status; message = $Why; public_note = ''; internal_note = "Out-of-office check did not run: $Why"; ticket_id = $TicketId; actions = @($actions); warnings = @($warnings); chatReply = $Why; ctx_json = '' })
    throw $Why
}
function Stop-Quiet {
    param([string]$Why, [string]$TicketId, $Members = @(), $Evidence = @())
    $ctx = @{ skip = $true; ticket_id = $TicketId; result = [ordered]@{ status = 'success'; message = $Why; public_note = ''; internal_note = ''; ticket_id = $TicketId; out_members = @(); checked_members = @($Members); evidence = @($Evidence); changed = $false; actions = @($actions); warnings = @($warnings); chatReply = $Why } }
    Set-NodeOutput ([ordered]@{ status = 'success'; message = $Why; ticket_id = $TicketId; ctx_json = (ConvertTo-Json -InputObject $ctx -Depth 8 -Compress) })
}
trap { if (-not $stopState.done) { $stopState.done = $true; $m = [string]$_.Exception.Message; Add-CheckPsaWarnings; Set-NodeOutput ([ordered]@{ status = 'error'; message = $m; public_note = ''; internal_note = "Out-of-office check failed: $m"; ticket_id = ''; actions = @($actions); warnings = @($warnings); chatReply = 'The out-of-office check failed. See the run for details.'; ctx_json = '' }) }; break }

$in = Get-NodeInput
$a = Read-StepTrigger $in
$ticketId = Get-StepField $a @('ticketId', 'ticket_id', 'TicketId', 'id', 'ticketNumber')
$extraMember = Get-StepField $a @('member', 'assignee', 'assignedMember', 'memberIdentifier', 'technician')
$source = Get-StepField $a @('triggerSource', 'trigger_source')

$sweep = -not $ticketId
if ($ticketId -and $ticketId -notmatch '^\d{1,12}$') { Stop-Check 'rejected' "Ticket number '$ticketId' isn't a ConnectWise ticket number, so nothing was checked." }

# ---- settings: input, else runner secret, else default ----
$inTypes = @(Get-OooNames (Get-OooSetting (Get-StepField $a @('in_types', 'inTypes')) 'OOO-InTypes' $OooDefaults.InTypes))
$schedTypes = @(Get-OooNames (Get-OooSetting (Get-StepField $a @('schedule_types', 'scheduleTypes')) 'OOO-ScheduleTypes' $OooDefaults.ScheduleTypes))
$whenOut = (Get-OooSetting (Get-StepField $a @('when_out', 'whenOut')) 'OOO-WhenOut' 'reassign').ToLowerInvariant()
if (@('flag', 'unassign', 'reassign') -notcontains $whenOut) { Stop-Check 'rejected' "when_out '$whenOut' isn't one of reassign, flag or unassign." $ticketId }
# Who can take the ticket: OOO-BackupPool (OOO-BackupMember still works), else the ticket's board team.
$backupRaw = Get-OooSetting (Get-StepField $a @('backup_pool', 'backupPool', 'backup', 'backup_member', 'backupMember')) 'OOO-BackupPool' ''
if (-not $backupRaw) { $backupRaw = Get-OooSetting '' 'OOO-BackupMember' '' }
$backupPool = @(Get-StepList $backupRaw)
$coverageArticle = Get-OooSetting (Get-StepField $a @('coverage_article', 'coverageArticle')) 'OOO-CoverageArticle' ''
$pickBy = (Get-OooSetting (Get-StepField $a @('pick_by', 'pickBy')) 'OOO-PickBy' 'fewest-open').ToLowerInvariant()
if (@('fewest-open', 'least-recent', 'list-order') -notcontains $pickBy) { Stop-Check 'rejected' "pick_by '$pickBy' isn't one of fewest-open, least-recent or list-order." $ticketId }
$timeZone = Get-OooSetting (Get-StepField $a @('time_zone', 'timeZone')) 'OOO-TimeZone' ''
if (-not (Test-OooTimeZone $timeZone)) { $null = $warnings.Add("Time zone '$timeZone' isn't known on this runner, so times are shown in UTC. Use an id like America/Los_Angeles or Pacific Standard Time."); $timeZone = '' }
$dispatchTo = @(Get-StepList (Get-OooSetting (Get-StepField $a @('dispatch_to', 'dispatchTo')) 'OOO-DispatchTo' ''))
$teamsFlow = Get-OooSetting (Get-StepField $a @('teams_flow_url', 'teamsFlowUrl')) 'OOO-TeamsFlowUrl' ''
# Writes happen only when confirm is true, or confirm is left out and the OOO-LiveMode secret is yes.
$confirmRaw = Get-StepField $a @('confirm')
$live = if ($confirmRaw) { Test-StepTrue $confirmRaw } else { Test-StepTrue (Get-OooSetting '' 'OOO-LiveMode' 'no') }
$nowIn = Get-StepField $a @('now')
$now = if ($nowIn) { ConvertTo-PsaDate $nowIn } else { [datetime]::UtcNow }
if ($null -eq $now) { Stop-Check 'rejected' "now '$nowIn' isn't a date." $ticketId }

# ---- ConnectWise only: the In/Out Board and schedule are ConnectWise features ----
$psa = Get-PsaType (Get-StepField $a @('psa'))
if ($psa -ne 'connectwise') { Stop-Check 'rejected' "This check reads the ConnectWise In/Out Board and schedule, so it only works with ConnectWise PSA (the PSA is set to '$psa')." $ticketId }
$conn = Connect-Psa 'connectwise'

# The context the act step needs for one ticket whose members include someone who is out, or a skip result.
function Get-OooTicketContext {
    param($t, [string]$ExtraMember, [string[]]$Actions)
    $tid = [string](Get-PsaProp $t 'id')
    $acts = New-Object System.Collections.ArrayList; foreach ($x in @($Actions)) { if ($x) { $null = $acts.Add([string]$x) } }
    # The member the request names counts only while the ticket has no owner saved yet. Once there is an owner,
    # the ticket itself says who is on it.
    $hasOwner = -not (Test-PsaBlank (Get-PsaPath $t 'owner.identifier'))
    if ($ExtraMember -and $hasOwner) { $null = $acts.Add("Ignored member '$ExtraMember' from the request because the ticket already has an owner.") }
    $members = @(Get-OooTicketMembers $t $(if ($hasOwner) { @() } else { @($ExtraMember) }))
    if (-not $members.Count) { return @{ skip = $true; why = "Ticket $tid has no technician assigned, so there was nothing to check."; members = @(); evidence = @(); actions = @($acts) } }
    # Once per ticket: the act step's internal note carries the [ooo-check] marker.
    $notes = @(Get-PsaTicketNotes -Id $tid -TextOnly)
    if (Test-PsaNoteMarker -Id $tid -Marker 'ooo-check' -Notes @($notes | Where-Object { $_.internal })) {
        return @{ skip = $true; why = "Ticket $tid was already handled by the out-of-office check, so it wasn't checked again."; members = $members; evidence = @(); actions = @($acts) }
    }
    $statuses = @()
    foreach ($m in $members) {
        $k = $m.ToLowerInvariant()
        if (-not $statusCache.ContainsKey($k)) { $statusCache[$k] = Get-OooMemberStatus -Identifier $m -Now $now -InTypes $inTypes -ScheduleTypes $schedTypes -TimeZone $timeZone }
        $statuses += , $statusCache[$k]
    }
    $null = $acts.Add("Checked $($members -join ', ') against the In/Out Board and schedule at $(Format-PsaDate $now).")
    $out = @($statuses | Where-Object { $_.out })
    if (-not $out.Count) { return @{ skip = $true; why = "Everyone on ticket $tid ($($members -join ', ')) is in, so nothing was changed."; members = $members; evidence = @($statuses | ForEach-Object { [ordered]@{ member = $_.identifier; evidence = @($_.evidence) } }); actions = @($acts) } }
    return @{
        skip = $false; ticket_id = $tid; summary = [string](Get-PsaProp $t 'summary'); company = [string](Get-PsaPath $t 'company.name')
        board = [string](Get-PsaPath $t 'board.name'); board_id = [string](Get-PsaPath $t 'board.id'); team_id = [string](Get-PsaPath $t 'team.id'); owner = [string](Get-PsaPath $t 'owner.identifier'); owner_id = [string](Get-PsaPath $t 'owner.id'); resources = [string](Get-PsaProp $t 'resources')
        members = $members; out = $out; when_out = $whenOut; backup_pool = $backupPool; pick_by = $pickBy; coverage_article = $coverageArticle; dispatch_to = $dispatchTo; teams_flow = $teamsFlow
        live = $live; now = (Format-PsaDate $now); time_zone = $timeZone; in_types = $inTypes; schedule_types = $schedTypes; source = $source
        actions = @($acts); warnings = @()
    }
}
$statusCache = @{}

if (-not $sweep) {
    $t = Invoke-PsaRead "/service/tickets/$ticketId" "read ticket $ticketId" 'read service tickets'
    $null = $actions.Add("Read ticket $ticketId from ConnectWise.")
    $one = Get-OooTicketContext $t $extraMember @($actions)
    $actions.Clear(); foreach ($x in @($one.actions)) { $null = $actions.Add($x) }
    Add-CheckPsaWarnings
    if ($one.skip) { Stop-Quiet $one.why $ticketId $one.members $one.evidence; return }
    $one.warnings = @($warnings)
    $names = ($one.out | ForEach-Object { $_.identifier }) -join ', '
    Set-NodeOutput ([ordered]@{ status = 'success'; message = "Out right now on ticket ${ticketId}: $names."; ticket_id = $ticketId; ctx_json = (ConvertTo-Json -InputObject $one -Depth 8 -Compress) })
    return
}

# ---- sweep: who is out right now, then their recent open tickets ----
$boards = @(Get-StepList (Get-OooSetting (Get-StepField $a @('boards')) 'OOO-Boards' ''))
$lookRaw = Get-OooSetting (Get-StepField $a @('lookback_minutes', 'lookbackMinutes')) 'OOO-LookbackMinutes' '60'
$maxRaw = Get-OooSetting (Get-StepField $a @('max_tickets', 'maxTickets')) 'OOO-MaxTickets' '25'
if ($lookRaw -notmatch '^\d{1,5}$' -or [int]$lookRaw -lt 1) { Stop-Check 'rejected' "lookback_minutes '$lookRaw' isn't a number of minutes." }
if ($maxRaw -notmatch '^\d{1,3}$' -or [int]$maxRaw -lt 1) { Stop-Check 'rejected' "max_tickets '$maxRaw' isn't a number from 1 to 999." }
$lookback = [int]$lookRaw; $maxTickets = [int]$maxRaw
if (-not $boards.Count) { $null = $warnings.Add('OOO-Boards is not set, so tickets on every board were checked. Set it to the boards ServiceAI Triage assigns on, for example "Professional Services, Contoso Labs".') }

# 1. Members who might be out: an In/Out Board record that isn't back yet, or a non-ticket schedule entry covering
#    now (Activities, PTO and other schedule types; type S entries are ticket work and are skipped). Each one is
#    then checked with the same rules as a single ticket.
# Unverified on a live ConnectWise: listing the In/Out Board and schedule entries for every member at once.
$nowLit = Format-OooCwDate $now
$maybe = New-Object System.Collections.ArrayList
$addMaybe = { param([string]$m) if ($m -and -not (@($maybe) -contains $m)) { $null = $maybe.Add($m) } }
foreach ($b in @(Invoke-Psa GET "/system/inOutBoards?conditions=$(ConvertTo-PsaQuery "dateBack>$nowLit")&pageSize=1000" | Where-Object { $null -ne $_ })) { & $addMaybe ([string](Get-PsaPath $b 'member.identifier')) }
foreach ($e in @(Invoke-Psa GET "/schedule/entries?conditions=$(ConvertTo-PsaQuery "dateStart<=$nowLit and dateEnd>$nowLit")&pageSize=1000" | Where-Object { $null -ne $_ })) {
    if ([string](Get-PsaPath $e 'type.identifier') -eq 'S') { continue }
    & $addMaybe ([string](Get-PsaPath $e 'member.identifier'))
}
$outNow = @()
foreach ($m in $maybe) {
    $st = Get-OooMemberStatus -Identifier $m -Now $now -InTypes $inTypes -ScheduleTypes $schedTypes -TimeZone $timeZone
    $statusCache[$m.ToLowerInvariant()] = $st
    if ($st.out) { $outNow += , [ordered]@{ identifier = $st.identifier; reasons = @($st.reasons); back = $st.back } }
}
$null = $actions.Add("Checked the In/Out Board and schedule at $(Format-PsaDate $now): $(if ($outNow.Count) { "out now: $(@($outNow | ForEach-Object { $_.identifier }) -join ', ')" } else { 'nobody is out' }).")
$done = [ordered]@{ status = 'success'; public_note = ''; internal_note = ''; ticket_id = ''; mode = 'sweep'; out_now = @($outNow); tickets = @(); changed = $false }
if (-not $outNow.Count) {
    Add-CheckPsaWarnings
    $why = 'Nobody is out right now, so no tickets were checked.'
    $r = $done; $r.message = $why; $r.skipped = @(); $r.actions = @($actions); $r.warnings = @($warnings); $r.chatReply = $why
    Set-NodeOutput ([ordered]@{ status = 'success'; message = $why; ctx_json = (ConvertTo-Json -InputObject @{ skip = $true; result = $r } -Depth 8 -Compress) })
    return
}

# 2. Their open tickets entered in the lookback window (oldest first), on the chosen boards.
# Unverified on a live ConnectWise: the "in (...)" condition on owner/identifier and board/name.
$quote = { param([string]$v) '"' + $v.Replace('\', '\\').Replace('"', '\"') + '"' }
$since = Format-OooCwDate $now.AddMinutes(-$lookback)
$cond = "closedFlag=false and dateEntered>=$since and owner/identifier in ($(@($outNow | ForEach-Object { & $quote $_.identifier }) -join ','))"
if ($boards.Count) { $cond += " and board/name in ($(@($boards | ForEach-Object { & $quote $_ }) -join ','))" }
$found = @(Invoke-PsaRead "/service/tickets?conditions=$(ConvertTo-PsaQuery $cond)&orderBy=$(ConvertTo-PsaQuery 'id asc')&pageSize=$([Math]::Min(1000, $maxTickets + 1))" 'list service tickets' 'read service tickets' | Where-Object { $null -ne $_ })
$null = $actions.Add("Found $($found.Count) open ticket$(if ($found.Count -ne 1) { 's' }) entered in the last $lookback minutes$(if ($boards.Count) { " on $($boards -join ', ')" }) owned by someone who is out.")
if ($found.Count -gt $maxTickets) { $null = $warnings.Add("More than $maxTickets tickets matched, so only the first $maxTickets were handled. The next run picks up the rest (raise OOO-MaxTickets if this keeps happening)."); $found = @($found[0..($maxTickets - 1)]) }

$items = @(); $skipped = @()
foreach ($t in $found) {
    $c = Get-OooTicketContext $t '' @()
    if ($c.skip) { $skipped += , [ordered]@{ ticket_id = [string](Get-PsaProp $t 'id'); why = $c.why }; continue }
    $items += , $c
}
Add-CheckPsaWarnings
if (-not $items.Count) {
    $why = if ($found.Count) { "None of the $($found.Count) matching ticket$(if ($found.Count -ne 1) { 's' }) needed a change (already handled, or the owner is in)." } else { "Out now: $(@($outNow | ForEach-Object { $_.identifier }) -join ', '). None of their tickets entered in the last $lookback minutes are open$(if ($boards.Count) { " on $($boards -join ', ')" })." }
    $r = $done; $r.message = $why; $r.skipped = @($skipped); $r.actions = @($actions); $r.warnings = @($warnings); $r.chatReply = $why
    Set-NodeOutput ([ordered]@{ status = 'success'; message = $why; ctx_json = (ConvertTo-Json -InputObject @{ skip = $true; result = $r } -Depth 8 -Compress) })
    return
}
$ctx = @{ skip = $false; mode = 'sweep'; live = $live; items = @($items); skipped = @($skipped); out_now = @($outNow); actions = @($actions); warnings = @($warnings); message = '' }
Set-NodeOutput ([ordered]@{ status = 'success'; message = "Sweep: $($items.Count) ticket$(if ($items.Count -ne 1) { 's' }) to handle."; ctx_json = (ConvertTo-Json -InputObject $ctx -Depth 10 -Compress) })
