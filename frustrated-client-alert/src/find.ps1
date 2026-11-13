# === Step 1: Find new client replies ===
# Edit this file, then run: node frustrated-client-alert/src/build.js
# Reads the run input (a Routine sends none, so every setting has a default), finds open tickets updated in the
# look-back window, and collects the client replies written in that window that haven't been alerted on yet.
# It passes them to the AI step as facts_json and everything the alert step needs as ctx_json. Changes nothing.
# Secrets: the PSA's own (PSA-Type and its connection), optional Sentiment-AlertEmail (or CSAT-ServiceManagerEmail).

$raw = Get-NodeInput
if ($raw -is [string]) {
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = $null }
    else { try { $raw = $raw | ConvertFrom-Json } catch { throw 'The run input is not valid JSON. Leave it empty to use the defaults.' } }
}
$wrapped = Get-PsaProp $raw 'trigger'; if ($null -ne $wrapped) { $raw = $wrapped }

# The first non-blank input among the names (snake_case or camelCase). Values starting with @ are unfilled tokens.
function Get-FcaInput {
    param([string[]]$Names, $Default)
    foreach ($n in $Names) {
        $v = Get-PsaProp $raw $n
        if ($null -eq $v) { continue }
        if ($v -is [string]) { $v = $v.Trim(); if (-not $v -or $v.StartsWith('@')) { continue } }
        return $v
    }
    return $Default
}
function ConvertTo-FcaBool {
    param($Value, [string]$Name)
    if ($Value -is [bool]) { return $Value }
    $s = ([string]$Value).Trim().ToLowerInvariant()
    if ($s -in @('true', 'yes', 'y', '1')) { return $true }
    if ($s -in @('false', 'no', 'n', '0', '')) { return $false }
    throw "$Name must be true or false, not '$Value'."
}
function ConvertTo-FcaInt {
    param($Value, [string]$Name, [int]$Min, [int]$Max)
    $n = 0
    if (-not [int]::TryParse(([string]$Value).Trim(), [ref]$n) -or $n -lt $Min -or $n -gt $Max) { throw "$Name must be a whole number from $Min to $Max, not '$Value'." }
    return $n
}
function Get-FcaEmails { param($v) return @(@($v) | ForEach-Object { ([string]$_) -split '[,;\s]+' } | Where-Object { $_ -match '^[^@\s]+@[^@\s]+\.[^@\s]+$' }) }

# ---- settings ----
$psa = Get-PsaType ([string](Get-FcaInput @('psa') ''))
if (-not $psa) { throw 'No PSA is set up. Add the PSA-Type secret (connectwise, autotask, halopsa, kaseyabms, syncro or zendesk) to the runner Key Vault.' }
$lookback = ConvertTo-FcaInt (Get-FcaInput @('lookback_minutes', 'lookbackMinutes') 20) 'lookback_minutes' 5 1440
$maxTickets = ConvertTo-FcaInt (Get-FcaInput @('max_tickets', 'maxTickets') 100) 'max_tickets' 1 500
$maxReplies = ConvertTo-FcaInt (Get-FcaInput @('max_replies', 'maxReplies') 25) 'max_replies' 1 50
$preview = ConvertTo-FcaBool (Get-FcaInput @('preview', 'dryRun', 'dry_run') $false) 'preview'
$emailLevel = ([string](Get-FcaInput @('email_level', 'emailLevel') 'high')).ToLowerInvariant()
if ($emailLevel -notin @('high', 'medium', 'none')) { throw "email_level must be high, medium or none, not '$emailLevel'." }
$alertTo = @(Get-FcaEmails (Get-FcaInput @('alert_email', 'alertEmail') ''))
if (-not $alertTo.Count) { $alertTo = @(Get-FcaEmails ([string](Get-PsaSecret 'Sentiment-AlertEmail'))) }
if (-not $alertTo.Count) { $alertTo = @(Get-FcaEmails ([string](Get-PsaSecret 'CSAT-ServiceManagerEmail'))) }
$companyIn = [string](Get-FcaInput @('company', 'company_id', 'companyId') '')

$null = Connect-Psa $psa
$psaName = $PsaState.Names[$psa]
$companyId = ''
if ($companyIn) {
    if ($companyIn -match '^\d+$') { $companyId = $companyIn }
    else {
        $hits = @(Find-PsaCompany -Name $companyIn | Where-Object { $_.exact })
        if ($hits.Count -ne 1) { throw "$psaName has $(if ($hits.Count) { "$($hits.Count) companies" } else { 'no company' }) named '$companyIn'. Use the PSA company id instead." }
        $companyId = $hits[0].id
    }
}

# ---- find ----
$now = (Get-Date).ToUniversalTime()
$cutoff = $now.AddMinutes(-$lookback)
$found = @(Find-PsaTickets -Open -UpdatedAfter $cutoff -CompanyId $companyId -Max $maxTickets -Order newest)
$warnings = New-Object System.Collections.ArrayList
if ([bool]$PsaState.FindTruncated) { $null = $warnings.Add("More than $maxTickets tickets changed in the last $lookback minutes, so only the newest $maxTickets were checked.") }

$replies = New-Object System.Collections.ArrayList
$facts = New-Object System.Collections.ArrayList
$noClientFlag = $false
foreach ($t in $found) {
    if ($replies.Count -ge $maxReplies) { $null = $warnings.Add("More than $maxReplies new client replies arrived, so only $maxReplies were scored. The rest are checked on the next run if they're still in the window."); break }
    $notes = @()
    try { $notes = @(Get-PsaTicketNotes -Id $t.id -Ticket $t) }
    catch { $null = $warnings.Add("Couldn't read the notes on ticket #$($t.number): $($_.Exception.Message)"); continue }
    if ($psa -eq 'kaseyabms') { $noClientFlag = $true; continue }
    $fresh = @($notes | Where-Object { $_.fromClient -and -not $_.internal -and $null -ne $_.created -and $_.created -ge $cutoff })
    foreach ($n in $fresh) {
        if ($replies.Count -ge $maxReplies) { break }
        $marker = "frustrated-client $($t.id)-$(if ($n.id) { $n.id } else { $n.created.ToString('yyyyMMddHHmmss') })"
        # Already alerted on this reply (an earlier run with an overlapping window)?
        if (Test-PsaNoteMarker -Id $t.id -Marker $marker -Notes $notes) { continue }
        $key = "r$($replies.Count + 1)"
        $text = (ConvertTo-PsaPlainText $n.text).Trim()
        if (-not $text) { continue }
        $null = $replies.Add([ordered]@{ key = $key; ticketId = [string]$t.id; number = [string]$t.number; summary = [string]$t.summary; companyName = [string]$t.companyName; priority = [string]$t.priority; author = [string]$n.author; created = (Format-PsaDate $n.created); marker = $marker; text = (Get-PsaText $text 1500) })
        $null = $facts.Add([ordered]@{ key = $key; ticketSubject = (Get-PsaText ([string]$t.summary) 200); reply = (Get-PsaText $text 1500) })
    }
}
if ($noClientFlag) { $null = $warnings.Add('Kaseya BMS notes don''t say who wrote them, so client replies can''t be picked out there. This automation doesn''t work on Kaseya BMS yet.') }

$ctx = [ordered]@{
    psa = $psa; psaName = $psaName; preview = $preview; lookbackMinutes = $lookback; emailLevel = $emailLevel; alertTo = @($alertTo)
    runAt = (Format-PsaDate $now); ticketsChecked = $found.Count; replies = @($replies); warnings = @($warnings)
}
$factsObj = if ($replies.Count) { [ordered]@{ replies = @($facts) } } else { [ordered]@{ skip = $true } }
Set-NodeOutput ([ordered]@{
        status     = 'ok'
        message    = "Checked $($found.Count) ticket(s) updated in the last $lookback minutes; $($replies.Count) new client repl$(if ($replies.Count -eq 1) { 'y' } else { 'ies' }) to score."
        facts_json = (ConvertTo-Json -InputObject $factsObj -Depth 6 -Compress)
        ctx_json   = (ConvertTo-Json -InputObject $ctx -Depth 8 -Compress)
        replies    = $replies.Count
        warnings   = @($warnings)
    })
