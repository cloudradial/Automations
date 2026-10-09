# === Step 1: Find resolved tickets past the threshold ===
# Reads the run input (a Routine sends none, so every setting has a default), finds the tickets that have
# sat in the resolved status for at least resolved_days, reads each one's notes, and decides which to close.
# This step changes nothing.

$raw = Get-NodeInput
if ($raw -is [string]) {
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = $null }
    else { try { $raw = $raw | ConvertFrom-Json } catch { throw 'The run input is not valid JSON. Leave it empty to use the defaults.' } }
}
$wrapped = Get-PsaProp $raw 'trigger'; if ($null -ne $wrapped) { $raw = $wrapped }

# The first non-blank input among the names (snake_case or camelCase). Values starting with @ are unfilled tokens.
function Get-AcrInput {
    param([string[]]$Names, $Default)
    foreach ($n in $Names) {
        $v = Get-PsaProp $raw $n
        if ($null -eq $v) { continue }
        if ($v -is [string]) { $v = $v.Trim(); if (-not $v -or $v.StartsWith('@')) { continue } }
        return $v
    }
    return $Default
}
function ConvertTo-AcrBool {
    param($Value, [string]$Name)
    if ($Value -is [bool]) { return $Value }
    $s = ([string]$Value).Trim().ToLowerInvariant()
    if ($s -in @('true', 'yes', 'y', '1')) { return $true }
    if ($s -in @('false', 'no', 'n', '0', '')) { return $false }
    throw "$Name must be true or false, not '$Value'."
}
function ConvertTo-AcrInt {
    param($Value, [string]$Name, [int]$Min, [int]$Max)
    $n = 0
    if (-not [int]::TryParse(([string]$Value).Trim(), [ref]$n) -or $n -lt $Min -or $n -gt $Max) { throw "$Name must be a whole number from $Min to $Max, not '$Value'." }
    return $n
}

# ---- settings ----
$psa = Get-PsaType ([string](Get-AcrInput @('psa') ''))
if (-not $psa) { throw 'No PSA is set up. Add the PSA-Type secret (connectwise, autotask, halopsa, kaseyabms, syncro or zendesk) to the runner Key Vault.' }
$defaultResolved = @{ connectwise = 'Resolved'; autotask = 'Resolved'; halopsa = 'Resolved'; kaseyabms = 'Resolved'; syncro = 'Resolved'; zendesk = 'solved' }
$resolved = [string](Get-AcrInput @('resolved_status_name', 'resolvedStatusName') $defaultResolved[$psa])
$resolvedDays = ConvertTo-AcrInt (Get-AcrInput @('resolved_days', 'resolvedDays') 3) 'resolved_days' 1 365
$maxDays = ConvertTo-AcrInt (Get-AcrInput @('max_resolved_days', 'maxResolvedDays') 30) 'max_resolved_days' 1 3650
if ($maxDays -le $resolvedDays) { throw "max_resolved_days ($maxDays) must be more than resolved_days ($resolvedDays)." }
$preview = ConvertTo-AcrBool (Get-AcrInput @('preview', 'dryRun', 'dry_run') $false) 'preview'
$maxTickets = ConvertTo-AcrInt (Get-AcrInput @('max_tickets', 'maxTickets') 200) 'max_tickets' 1 1000
$closeStatus = [string](Get-AcrInput @('close_status_name', 'closeStatusName') '')
$companyIn = [string](Get-AcrInput @('company', 'company_id', 'companyId') '')

# Fail closed when closing would leave the ticket in the status it is already in.
if ($closeStatus -and $closeStatus -ieq $resolved) { throw "close_status_name and resolved_status_name are both '$resolved'. Closing must move the ticket to a different status." }
if ($psa -eq 'syncro' -and -not $closeStatus -and $resolved -ieq 'Resolved') { throw "In Syncro, Resolved is already the closed status, so there is nothing to close. Set resolved_status_name to the status your team uses for fixed tickets waiting to be closed, or set close_status_name." }
if ($psa -eq 'autotask' -and -not $closeStatus -and $resolved -imatch '^complete$') { throw "In Autotask, Complete is already the closed status. Set resolved_status_name to the status your team uses for fixed tickets waiting to be closed." }

$null = Connect-Psa $psa
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
# Untouched for at least resolved_days, and touched within max_resolved_days (older tickets are left alone,
# so a first run doesn't email clients about tickets resolved long ago).
$found = @(Find-PsaTickets -Status $resolved -UpdatedBefore $now.AddDays(-$resolvedDays) -UpdatedAfter $now.AddDays(-$maxDays) -CompanyId $companyId -Max $maxTickets)
$truncated = [bool]$PsaState.FindTruncated

$plan = New-Object System.Collections.ArrayList
$skipped = New-Object System.Collections.ArrayList
$warnings = New-Object System.Collections.ArrayList
if ($truncated) { $null = $warnings.Add("More than $maxTickets tickets are in '$resolved', so only the first $maxTickets were checked. Raise max_tickets or let the next run pick up the rest.") }

foreach ($t in $found) {
    $label = "#$($t.number)$(if ($t.companyName) { " ($($t.companyName))" })"
    # Never act on a ticket in any other status.
    if ($t.status.Trim() -ine $resolved) { $null = $skipped.Add(@{ ticketId = $t.id; number = $t.number; reason = "status is '$($t.status)'" }); continue }

    $notes = @()
    try { $notes = @(Get-PsaTicketNotes -Id $t.id -Ticket $t) }
    catch { $null = $warnings.Add("Couldn't read the notes on ticket $label, so it was left alone: $($_.Exception.Message)"); $null = $skipped.Add(@{ ticketId = $t.id; number = $t.number; reason = 'notes unreadable' }); continue }

    $ours = @(); $others = @()
    foreach ($n in $notes) {
        # Our own public final notice shows only an opaque Ref line; the internal "closed" note holds the marker.
        if (Test-AcrOwnPublic $n) { continue }
        $m = [regex]::Match($n.text, $AcrMarkerPattern)
        if ($m.Success) { $ours += , @{ created = $n.created; tag = $m.Groups['tag'].Value.Trim().ToLowerInvariant(); since = (ConvertTo-PsaDate $m.Groups['since'].Value.Trim()) } }
        else { $others += , $n }
    }
    $lastOther = if ($others.Count) { $others[-1] } else { $null }
    $lastOtherAt = if ($null -ne $lastOther) { $lastOther.created } else { $null }
    $cycle = @($ours | Where-Object { $null -eq $lastOtherAt -or ($null -ne $_.created -and $_.created -gt $lastOtherAt) })

    # Stop if the client replied after the ticket was resolved.
    if (-not $cycle.Count -and $null -ne $lastOther -and $lastOther.fromClient) {
        $null = $warnings.Add("Ticket $label is in '$resolved', but the client replied on $(Format-AcrDay $lastOtherAt). It wasn't closed; check the reply.")
        $null = $skipped.Add(@{ ticketId = $t.id; number = $t.number; reason = 'client replied' }); continue
    }

    $since = $null
    $withSince = @($cycle | Where-Object { $null -ne $_.since })
    if ($withSince.Count) { $since = $withSince[-1].since }
    else {
        # Resolved since the latest of: the newest note, the last update, the last status change and the resolved date.
        $cands = @(@($lastOtherAt, $t.updated, $t.statusChanged, $t.closed) | Where-Object { $null -ne $_ } | Sort-Object)
        if ($cands.Count) { $since = $cands[-1] }
    }
    if ($null -eq $since) { $null = $warnings.Add("Ticket $label has no dates to count from, so it was left alone."); $null = $skipped.Add(@{ ticketId = $t.id; number = $t.number; reason = 'no dates' }); continue }

    $days = [int][Math]::Floor(($now - $since).TotalDays)
    if ($days -lt $resolvedDays) { $null = $skipped.Add(@{ ticketId = $t.id; number = $t.number; reason = "resolved $days days ago" }); continue }
    if (-not $withSince.Count -and $days -gt $maxDays) { $null = $skipped.Add(@{ ticketId = $t.id; number = $t.number; reason = 'resolved too long ago' }); continue }

    $null = $plan.Add([ordered]@{
            ticketId = $t.id; number = $t.number; summary = $t.summary; companyId = $t.companyId; companyName = $t.companyName
            daysResolved = $days; since = (Format-AcrStamp $since)
            action = 'close'; notice = -not (@($cycle | Where-Object { $_.tag -in @('final notice', 'closed') }).Count -gt 0)
            noticeResult = ''; closeResult = ''; closedStatus = ''; noteResult = ''; error = ''
        })
}

Set-NodeOutput ([ordered]@{
        settings  = [ordered]@{ psa = $psa; psaName = $psaName; preview = $preview; resolvedStatus = $resolved; resolvedDays = $resolvedDays; maxResolvedDays = $maxDays; closeStatus = $closeStatus; maxTickets = $maxTickets; companyId = $companyId; companyName = $companyName; runAt = (Format-AcrStamp $now) }
        found     = $found.Count
        truncated = $truncated
        plan      = @($plan)
        skipped   = @($skipped)
        warnings  = @($warnings)
    })
