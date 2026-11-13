# === Step 1: Close tickets the client has thanked us for ===
# Edit this file, then run: node thank-you-close/src/build.js
# Finds tickets in your Resolved and waiting-on-client statuses whose newest note is a short "thanks, all sorted"
# from the client, and closes them with an internal note. Fixed rules, no AI: a reply with a question, a "but",
# "still", "not" or a new problem is left for a technician. Preview writes nothing.
# Secrets: the PSA's own (PSA-Type and its connection).

$raw = Get-NodeInput
if ($raw -is [string]) {
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = $null }
    else { try { $raw = $raw | ConvertFrom-Json } catch { throw 'The run input is not valid JSON. Leave it empty to use the defaults.' } }
}
$wrapped = Get-PsaProp $raw 'trigger'; if ($null -ne $wrapped) { $raw = $wrapped }

function Get-TycInput {
    param([string[]]$Names, $Default)
    foreach ($n in $Names) {
        $v = Get-PsaProp $raw $n
        if ($null -eq $v) { continue }
        if ($v -is [string]) { $v = $v.Trim(); if (-not $v -or $v.StartsWith('@')) { continue } }
        return $v
    }
    return $Default
}
function ConvertTo-TycBool {
    param($Value, [string]$Name)
    if ($Value -is [bool]) { return $Value }
    $s = ([string]$Value).Trim().ToLowerInvariant()
    if ($s -in @('true', 'yes', 'y', '1')) { return $true }
    if ($s -in @('false', 'no', 'n', '0', '')) { return $false }
    throw "$Name must be true or false, not '$Value'."
}
function ConvertTo-TycInt {
    param($Value, [string]$Name, [int]$Min, [int]$Max)
    $n = 0
    if (-not [int]::TryParse(([string]$Value).Trim(), [ref]$n) -or $n -lt $Min -or $n -gt $Max) { throw "$Name must be a whole number from $Min to $Max, not '$Value'." }
    return $n
}

# ---- the rules (fixed, no AI) ----
# The reply above any quoted email history or signature, on one line.
function Get-TycReplyText {
    param([string]$Text)
    $keep = New-Object System.Collections.ArrayList
    foreach ($line in ((ConvertTo-PsaPlainText $Text) -split "`r?`n")) {
        $l = $line.Trim()
        if ($l -match '^(?i)(on .+ wrote:|from:|sent:|-{2,}\s*original message|sent from my|>|_{5,}|-- ?$|(kind |best |warm )?regards,?$)') { break }
        if ($l) { $null = $keep.Add($l) }
    }
    return (($keep -join ' ') -replace '\s+', ' ').Trim()
}
$TycThanks = '(?i)\b(thanks|thank\s*you|thx|ty|cheers|appreciated?|much obliged|all\s+(good|sorted|set|fixed|working)|sorted|that\s+(worked|fixed it|did it|did the trick)|works? (now|again|fine|great)|working (now|again|fine)|(issue|problem) (is )?(resolved|fixed|gone)|perfect|brilliant|awesome)\b'
$TycNot = '(?i)(\?|\b(not|no longer|isn''t|doesn''t|didn''t|won''t|can''t|cannot|still|but|however|although|again|another|also|issue persists|error|broken|fail\w*|can you|could you|would you|please (check|look|help|call|advise)|one more|quick question|unfortunately|except)\b)'
# @{ ok; why }: ok when the reply is a short thank-you with nothing else asked or reported.
function Test-TycThankYou {
    param([string]$Reply)
    if (-not $Reply) { return @{ ok = $false; why = 'empty reply' } }
    $words = @($Reply -split '\s+' | Where-Object { $_ }).Count
    if ($words -gt 40) { return @{ ok = $false; why = "reply is long ($words words)" } }
    if ($Reply -match $TycNot) { return @{ ok = $false; why = "reply also says '$($Matches[0].Trim())'" } }
    if ($Reply -notmatch $TycThanks) { return @{ ok = $false; why = 'reply is not a thank-you' } }
    return @{ ok = $true; why = '' }
}

# ---- settings ----
$psa = Get-PsaType ([string](Get-TycInput @('psa') ''))
if (-not $psa) { throw 'No PSA is set up. Add the PSA-Type secret (connectwise, autotask, halopsa, kaseyabms, syncro or zendesk) to the runner Key Vault.' }
$defaultStatuses = @{ connectwise = 'Waiting Customer,Resolved'; autotask = 'Waiting Customer,Resolved'; halopsa = 'Waiting on User,Resolved'; kaseyabms = 'Waiting on Customer,Resolved'; syncro = 'Waiting on Customer,Resolved'; zendesk = 'pending,solved' }
$stIn = Get-TycInput @('statuses', 'status_names', 'statusNames') $defaultStatuses[$psa]
$statuses = @(@($(if ($stIn -is [array]) { $stIn } else { ([string]$stIn) -split '[,;]' })) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
if (-not $statuses.Count) { throw 'statuses must name at least one status to watch.' }
$minAge = ConvertTo-TycInt (Get-TycInput @('min_age_minutes', 'minAgeMinutes') 30) 'min_age_minutes' 0 1440
$maxAgeDays = ConvertTo-TycInt (Get-TycInput @('max_age_days', 'maxAgeDays') 14) 'max_age_days' 1 90
$maxTickets = ConvertTo-TycInt (Get-TycInput @('max_tickets', 'maxTickets') 200) 'max_tickets' 1 1000
$preview = ConvertTo-TycBool (Get-TycInput @('preview', 'dryRun', 'dry_run') $false) 'preview'
$closeStatus = [string](Get-TycInput @('close_status_name', 'closeStatusName') '')
if ($psa -eq 'kaseyabms') { throw 'Kaseya BMS notes don''t say who wrote them, so a client''s thank-you can''t be told apart. Thank-You Close doesn''t work on Kaseya BMS yet.' }

$null = Connect-Psa $psa
$psaName = $PsaState.Names[$psa]
$now = (Get-Date).ToUniversalTime()
$warnings = New-Object System.Collections.ArrayList
$results = New-Object System.Collections.ArrayList
$skipped = New-Object System.Collections.ArrayList
$counts = @{ found = 0; closed = 0 }

foreach ($st in $statuses) {
    $found = @()
    try { $found = @(Find-PsaTickets -Status $st -UpdatedAfter $now.AddDays(-$maxAgeDays) -Max $maxTickets) }
    catch { $null = $warnings.Add("Couldn't list the tickets in '$st': $($_.Exception.Message)"); continue }
    if ([bool]$PsaState.FindTruncated) { $null = $warnings.Add("More than $maxTickets tickets are in '$st', so only $maxTickets were checked.") }
    foreach ($t in $found) {
        if (([string]$t.status).Trim() -ine $st) { continue }
        $counts.found++
        $label = "#$($t.number)"
        $notes = @()
        try { $notes = @(Get-PsaTicketNotes -Id $t.id -Ticket $t) }
        catch { $null = $warnings.Add("Couldn't read the notes on ticket $($label): $($_.Exception.Message)"); continue }
        $last = @($notes | Where-Object { $null -ne $_ }) | Select-Object -Last 1
        if ($null -eq $last -or -not $last.fromClient -or $last.internal) { continue }
        $marker = "thank-you-close $($t.id)-$(if ($last.id) { $last.id } else { 'last' })"
        if (Test-PsaNoteMarker -Id $t.id -Marker $marker -Notes $notes) { continue }
        if ($null -ne $last.created -and $last.created -gt $now.AddMinutes(-$minAge)) { $null = $skipped.Add(@{ ticketId = $t.id; number = $t.number; reason = "the reply is under $minAge minutes old" }); continue }
        $reply = Get-TycReplyText $last.text
        $verdict = Test-TycThankYou $reply
        if (-not $verdict.ok) { $null = $skipped.Add(@{ ticketId = $t.id; number = $t.number; reason = $verdict.why }); continue }

        $quote = Get-PsaText $reply 160
        $item = [ordered]@{ ticketId = [string]$t.id; number = [string]$t.number; summary = [string]$t.summary; companyName = [string]$t.companyName; status = $st; reply = $quote; closedStatus = ''; result = '' }
        if ($preview) { $item.result = 'would close'; $null = $results.Add($item); continue }
        try {
            $item.closedStatus = [string](Close-PsaTicket -Id $t.id -StatusName $closeStatus -NotStatus $(if ($st -match '(?i)resolved|solved') { $st } else { '' }))
            $counts.closed++
            $item.result = 'closed'
        }
        catch { $item.result = 'close failed'; $null = $warnings.Add("Couldn't close ticket $($label): $($_.Exception.Message)"); $null = $results.Add($item); continue }
        $note = "Closed by Thank-You Close: the client's latest reply was a thank-you with nothing else asked.`nThey wrote: `"$quote`"`nIf they reply again, reopen the ticket as usual."
        try { $null = Add-PsaNote -Id $t.id -Text $note -Title 'Closed after client thank-you' -Internal -Marker $marker }
        catch { $null = $warnings.Add("Ticket $label was closed, but the internal note couldn't be added: $($_.Exception.Message)") }
        $null = $results.Add($item)
    }
}

$n = @($results).Count
$msg = if ($preview) { "Preview only, nothing was changed: would close $n ticket(s) after a client thank-you." } else { "Closed $($counts.closed) ticket(s) after a client thank-you." }
$msg += " Checked $($counts.found) ticket(s) in $($statuses -join ', '); $(@($skipped).Count) left for a technician."
Set-NodeOutput ([ordered]@{
        status = $(if ($preview) { 'pending_confirmation' } elseif (@($warnings).Count) { 'partial' } else { 'success' })
        message = $msg; public_note = ''; internal_note = $msg; ticket_id = ''
        psa = $psaName; preview = $preview; statuses = @($statuses)
        closed = @($results); skipped = @($skipped); warnings = @($warnings)
    })
