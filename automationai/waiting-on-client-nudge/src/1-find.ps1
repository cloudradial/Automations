# === Step 1: Find tickets in Waiting ===
# Reads the run input (a Routine sends none, so every setting has a default), finds the tickets in the
# waiting status, reads each one's notes and decides what is due: a reminder, the closing notice and close,
# or a hold for P1/P2 tickets. This step changes nothing.

$raw = Get-NodeInput
if ($raw -is [string]) {
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = $null }
    else { try { $raw = $raw | ConvertFrom-Json } catch { throw 'The run input is not valid JSON. Leave it empty to use the defaults.' } }
}
$wrapped = Get-PsaProp $raw 'trigger'; if ($null -ne $wrapped) { $raw = $wrapped }

# The first non-blank input among the names (snake_case or camelCase). Values starting with @ are unfilled tokens.
function Get-NudgeInput {
    param([string[]]$Names, $Default)
    foreach ($n in $Names) {
        $v = Get-PsaProp $raw $n
        if ($null -eq $v) { continue }
        if ($v -is [string]) { $v = $v.Trim(); if (-not $v -or $v.StartsWith('@')) { continue } }
        return $v
    }
    return $Default
}
function ConvertTo-NudgeBool {
    param($Value, [string]$Name)
    if ($Value -is [bool]) { return $Value }
    $s = ([string]$Value).Trim().ToLowerInvariant()
    if ($s -in @('true', 'yes', 'y', '1')) { return $true }
    if ($s -in @('false', 'no', 'n', '0', '')) { return $false }
    throw "$Name must be true or false, not '$Value'."
}
function ConvertTo-NudgeInt {
    param($Value, [string]$Name, [int]$Min, [int]$Max)
    $n = 0
    if (-not [int]::TryParse(([string]$Value).Trim(), [ref]$n) -or $n -lt $Min -or $n -gt $Max) { throw "$Name must be a whole number from $Min to $Max, not '$Value'." }
    return $n
}

# ---- settings ----
$psa = Get-PsaType ([string](Get-NudgeInput @('psa') ''))
if (-not $psa) { throw 'No PSA is set up. Add the PSA-Type secret (connectwise, autotask, halopsa, kaseyabms, syncro or zendesk) to the runner Key Vault.' }
$defaultWaiting = @{ connectwise = 'Waiting Customer'; autotask = 'Waiting Customer'; halopsa = 'Waiting on User'; kaseyabms = 'Waiting on Customer'; syncro = 'Waiting on Customer'; zendesk = 'pending' }
$waiting = [string](Get-NudgeInput @('waiting_status_name', 'waitingStatusName') $defaultWaiting[$psa])

$daysIn = Get-NudgeInput @('reminder_days', 'reminderDays') '2,4'
$dayList = if ($daysIn -is [array]) { @($daysIn) } else { @(([string]$daysIn) -split '[,;\s]+' | Where-Object { $_ }) }
$reminderDays = @($dayList | ForEach-Object { ConvertTo-NudgeInt $_ 'Each reminder day' 1 365 } | Sort-Object -Unique)
$closeDay = ConvertTo-NudgeInt (Get-NudgeInput @('close_day', 'closeDay') 7) 'close_day' 1 365
if ($reminderDays.Count -and $closeDay -le $reminderDays[-1]) { throw "close_day ($closeDay) must be later than the last reminder day ($($reminderDays[-1]))." }
$preview = ConvertTo-NudgeBool (Get-NudgeInput @('preview', 'dryRun', 'dry_run') $false) 'preview'
$maxTickets = ConvertTo-NudgeInt (Get-NudgeInput @('max_tickets', 'maxTickets') 200) 'max_tickets' 1 1000
$closeStatus = [string](Get-NudgeInput @('close_status_name', 'closeStatusName') '')
$companyIn = [string](Get-NudgeInput @('company', 'company_id', 'companyId') '')

$conn = Connect-Psa $psa
$psaName = $PsaState.Names[$psa]

$companyId = ''; $companyName = ''
if ($companyIn) {
    if ($companyIn -match '^\d+$') { $companyId = $companyIn }
    else {
        $hits = @(Find-PsaCompany -Name $companyIn | Where-Object { $_.exact })
        if (-not $hits.Count) { throw "$psaName has no company named '$companyIn'. Use the exact company name or the PSA company id." }
        if ($hits.Count -gt 1) { throw "$psaName has $($hits.Count) companies named '$companyIn'. Use the PSA company id instead." }
        $companyId = $hits[0].id; $companyName = $hits[0].name
    }
}

# ---- find ----
$now = (Get-Date).ToUniversalTime()
$firstDay = if ($reminderDays.Count) { $reminderDays[0] } else { $closeDay }
# A ticket created less than $firstDay days ago can't be due yet, so the list is cut on the created date.
$found = @(Find-PsaTickets -Status $waiting -CreatedBefore $now.AddDays(-$firstDay) -CompanyId $companyId -Max $maxTickets)
$truncated = [bool]$PsaState.FindTruncated

$plan = New-Object System.Collections.ArrayList
$skipped = New-Object System.Collections.ArrayList
$warnings = New-Object System.Collections.ArrayList
if ($truncated) { $null = $warnings.Add("More than $maxTickets tickets are in '$waiting', so only the first $maxTickets were checked. Raise max_tickets or let the next run pick up the rest.") }

foreach ($t in $found) {
    $label = "#$($t.number)$(if ($t.companyName) { " ($($t.companyName))" })"
    # Never act on a ticket in any other status.
    if ($t.status.Trim() -ine $waiting) { $null = $skipped.Add(@{ ticketId = $t.id; number = $t.number; reason = "status is '$($t.status)'" }); continue }

    $notes = @()
    try { $notes = @(Get-PsaTicketNotes -Id $t.id -Ticket $t) }
    catch { $null = $warnings.Add("Couldn't read the notes on ticket $label, so it was left alone: $($_.Exception.Message)"); $null = $skipped.Add(@{ ticketId = $t.id; number = $t.number; reason = 'notes unreadable' }); continue }

    $ours = @(); $others = @()
    foreach ($n in $notes) {
        $m = [regex]::Match($n.text, $NudgeMarkerPattern)
        if ($m.Success) { $ours += , @{ created = $n.created; tag = $m.Groups['tag'].Value.Trim().ToLowerInvariant(); since = (ConvertTo-PsaDate $m.Groups['since'].Value.Trim()) } }
        else { $others += , $n }
    }
    $lastOther = if ($others.Count) { $others[-1] } else { $null }
    $lastOtherAt = if ($null -ne $lastOther) { $lastOther.created } else { $null }
    # Markers written after the newest human note belong to the current wait. A newer human note starts a new wait.
    $cycle = @($ours | Where-Object { $null -eq $lastOtherAt -or ($null -ne $_.created -and $_.created -gt $lastOtherAt) })

    if (-not $cycle.Count -and $null -ne $lastOther -and $lastOther.fromClient) {
        $null = $warnings.Add("Ticket $label is still in '$waiting', but the client replied on $(Format-NudgeDay $lastOtherAt). No reminder was sent; move the ticket on.")
        $null = $skipped.Add(@{ ticketId = $t.id; number = $t.number; reason = 'client replied' }); continue
    }

    $since = $null
    $withSince = @($cycle | Where-Object { $null -ne $_.since })
    if ($withSince.Count) { $since = $withSince[-1].since }
    else {
        # The wait started at the latest of: the newest note, the last update (which includes the status change) and,
        # where the PSA records it, the last status change.
        $cands = @(@($lastOtherAt, $t.updated, $t.statusChanged) | Where-Object { $null -ne $_ } | Sort-Object)
        if ($cands.Count) { $since = $cands[-1] } elseif ($null -ne $t.created) { $since = $t.created }
    }
    if ($null -eq $since) { $null = $warnings.Add("Ticket $label has no dates to count the wait from, so it was left alone."); $null = $skipped.Add(@{ ticketId = $t.id; number = $t.number; reason = 'no dates' }); continue }

    $days = [int][Math]::Floor(($now - $since).TotalDays)
    $sentDays = @($cycle | ForEach-Object { if ($_.tag -match '^day (\d+)$') { [int]$Matches[1] } })
    $maxSent = if ($sentDays.Count) { [int](($sentDays | Measure-Object -Maximum).Maximum) } else { 0 }
    $closingSent = @($cycle | Where-Object { $_.tag -eq 'closing notice' }).Count -gt 0
    $held = @($cycle | Where-Object { $_.tag -eq 'close held' }).Count -gt 0
    $high = $t.priorityLevel -in @('critical', 'high')

    $item = [ordered]@{
        ticketId = $t.id; number = $t.number; summary = $t.summary; companyId = $t.companyId; companyName = $t.companyName
        priority = $t.priority; daysWaiting = $days; since = (Format-NudgeStamp $since); closeBy = (Format-NudgeStamp $since.AddDays($closeDay))
        action = ''; day = 0; reminderNo = 0; reminderTotal = $reminderDays.Count; notice = $false
        remindResult = ''; noticeResult = ''; closeResult = ''; closedStatus = ''; noteResult = ''; error = ''
    }
    if ($days -ge $closeDay) {
        if ($high) {
            if ($held) { $null = $skipped.Add(@{ ticketId = $t.id; number = $t.number; reason = 'high priority, already flagged' }); continue }
            $item.action = 'hold'
        }
        else { $item.action = 'close'; $item.notice = -not $closingSent }
    }
    else {
        $due = @($reminderDays | Where-Object { $_ -le $days -and $_ -gt $maxSent })
        if (-not $due.Count) { $null = $skipped.Add(@{ ticketId = $t.id; number = $t.number; reason = "nothing due (day $days)" }); continue }
        $item.action = 'remind'; $item.day = $due[-1]; $item.reminderNo = [array]::IndexOf($reminderDays, $due[-1]) + 1
    }
    $null = $plan.Add($item)
}

Set-NodeOutput ([ordered]@{
        settings  = [ordered]@{ psa = $psa; psaName = $psaName; preview = $preview; waitingStatus = $waiting; reminderDays = @($reminderDays); closeDay = $closeDay; closeStatus = $closeStatus; maxTickets = $maxTickets; companyId = $companyId; companyName = $companyName; runAt = (Format-NudgeStamp $now) }
        found     = $found.Count
        truncated = $truncated
        plan      = @($plan)
        skipped   = @($skipped)
        warnings  = @($warnings)
    })
