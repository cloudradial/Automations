# === Step 1: Read the ticket history ===
# Edit this file, then run: node escalation-handoff-summary/src/build.js
# Reads one ticket, its notes and (where the PSA has them) its time entries, and hands the AI step a trimmed,
# ordered history to summarize. Accepts a flat {key:value} body (ServiceAI Action, manual run), the CloudRadial
# {Ticket:{...}, Company:{...}} shape, or either one wrapped in {trigger:...}.
# Read-only: this step never writes to the PSA. Earlier handoff summaries are left out of the history, so a summary
# never summarizes itself.
$ErrorActionPreference = 'Stop'

function Get-Prop { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
$stopState = @{ done = $false }
$warnings = New-Object System.Collections.ArrayList
function Get-AllWarnings {
    param($Own)
    $all = New-Object System.Collections.ArrayList
    foreach ($w in @(@($Own) + @($PsaState.Warnings))) { $t = [string]$w; if ($t -and -not $all.Contains($t)) { $null = $all.Add($t) } }
    return @($all)
}
function Stop-Run {
    param([string]$Status, [string]$Why, [string]$TicketId = '')
    $stopState.done = $true
    Set-NodeOutput ([ordered]@{
            status = $Status; message = $Why; public_note = ''; internal_note = "Escalation handoff summary stopped before anything was written: $Why"
            ticket_id = $TicketId; actions = @(); warnings = @(Get-AllWarnings $warnings); chatReply = $Why
        })
    throw $Why
}
trap { if (-not $stopState.done) { $stopState.done = $true; Set-NodeOutput ([ordered]@{ status = 'error'; message = [string]$_.Exception.Message; public_note = ''; internal_note = "Escalation handoff summary failed while reading the ticket: $($_.Exception.Message)"; ticket_id = ''; actions = @(); warnings = @(Get-AllWarnings $warnings); chatReply = "The handoff summary failed: $($_.Exception.Message)" }) }; break }

# ---- the request ----
$raw = Get-NodeInput
if ($null -eq $raw) { Stop-Run 'incomplete' 'No input was received. Send at least ticketId.' }
if ($raw -is [string]) { try { $raw = $raw | ConvertFrom-Json } catch { Stop-Run 'incomplete' 'The input was text that is not valid JSON.' } }
$wrap = Get-Prop $raw 'trigger'; if ($null -ne $wrap) { $raw = $wrap; if ($raw -is [string]) { try { $raw = $raw | ConvertFrom-Json } catch { Stop-Run 'incomplete' 'The trigger body was text that is not valid JSON.' } } }

$answers = @{}
if ($raw -is [System.Collections.IDictionary]) { foreach ($k in @($raw.Keys)) { $answers[[string]$k] = $raw[$k] } }
else { foreach ($p in $raw.PSObject.Properties) { $answers[$p.Name] = $p.Value } }
$crTicket = Get-Prop $raw 'Ticket'
if ($null -ne $crTicket) {
    foreach ($q in @(Get-Prop $crTicket 'Questions')) { $qid = [string](Get-Prop $q 'Id'); if ($qid) { $answers[$qid] = Get-Prop $q 'Value' } }
    $tid = Get-Prop $crTicket 'TicketId'; if ($null -ne $tid) { $answers['ticketId'] = $tid }
}
$crCompany = Get-Prop $raw 'Company'
if ($null -ne $crCompany) { foreach ($pair in @(@('CompanyName', 'companyName'), @('CompanyPsaId', 'companyId'))) { $v = Get-Prop $crCompany $pair[0]; if ($null -ne $v) { $answers[$pair[1]] = $v } } }
# ServiceAI leaves unfilled placeholders (<reason>, {{reason}}, @reason) in the body: they count as not given.
function Get-Field {
    param([string[]]$Names)
    foreach ($n in $Names) {
        if (-not $answers.ContainsKey($n)) { continue }
        $v = $answers[$n]
        if ($null -eq $v -or $v -is [System.Management.Automation.PSCustomObject] -or $v -is [System.Collections.IDictionary]) { continue }
        $s = ([string]$v).Trim()
        if (-not $s -or $s.StartsWith('@') -or $s -match '^\{\{.*\}\}$' -or $s -match '^<[^>]*>$') { continue }
        return $s
    }
    return ''
}
function Get-Flag { param([string[]]$Names, [bool]$Default) $s = (Get-Field $Names).ToLowerInvariant(); if (-not $s) { return $Default }; return (@('true', 'yes', '1', 'y') -contains $s) }
function Get-Int {
    param([string[]]$Names, [int]$Default, [int]$Min, [int]$Max)
    $s = Get-Field $Names; if (-not $s) { return $Default }
    $n = 0; if (-not [int]::TryParse($s, [ref]$n) -or $n -lt $Min -or $n -gt $Max) { Stop-Run 'incomplete' "$($Names[0]) must be a whole number from $Min to $Max; '$s' isn't. Nothing was read." }
    return $n
}

$f = [ordered]@{
    ticketId      = (Get-Field @('ticketId', 'ticket_id', 'TicketId', 'ticketNumber'))
    companyName   = (Get-Field @('companyName', 'company_name', 'CompanyName'))
    companyId     = (Get-Field @('companyId', 'company_id', 'psa_company_id', 'CompanyPsaId'))
    reason        = (Get-PsaText (Get-Field @('reason', 'escalationReason', 'why')) 500)
    escalateTo    = (Get-PsaText (Get-Field @('escalateTo', 'escalate_to', 'handoffTo', 'to')) 120)
    psa           = (Get-Field @('psa'))
    triggerSource = (Get-Field @('triggerSource', 'trigger_source'))
    maxNotes      = (Get-Int @('maxNotes') 30 5 100)
    includeTime   = (Get-Flag @('includeTime') $true)
    addNote       = (Get-Flag @('addNote') $true)
    sourceId      = ''; marker = ''
}
if (-not $f.ticketId) { Stop-Run 'incomplete' 'ticketId is missing. Send the PSA ticket number to summarize. Nothing was read.' }

# ---- the ticket and its company ----
$actions = New-Object System.Collections.ArrayList
$conn = Connect-Psa -Psa (Get-PsaType $f.psa)
$f.psa = $conn.Psa
$psaName = Get-PsaName
try { $f.sourceId = Resolve-PsaTicketId $f.ticketId } catch { Stop-Run 'incomplete' "Ticket $($f.ticketId) wasn't found in $($psaName): $($_.Exception.Message)" $f.ticketId }
$t = $null
try { $t = Get-PsaTicket -Id $f.sourceId } catch { Stop-Run 'incomplete' "Ticket $($f.ticketId) couldn't be read from $($psaName): $($_.Exception.Message)" $f.ticketId }
$companyId = [string]$t['companyId']
if ($f.companyId -and $companyId -and $f.companyId -ne $companyId) { Stop-Run 'rejected' "Ticket $($f.ticketId) belongs to a different company than the companyId sent ($($f.companyId)). Nothing was read." $f.ticketId }
if ($f.companyName -and $companyId) {
    $hits = @(); try { $hits = @(Find-PsaCompany -Name $f.companyName) } catch { $null = $warnings.Add("The company name couldn't be checked in $($psaName): $($_.Exception.Message)") }
    if ($hits.Count -and -not @($hits | Where-Object { [string]$_.id -eq $companyId }).Count) { Stop-Run 'rejected' "Ticket $($f.ticketId) does not belong to '$($f.companyName)' in $psaName. Nothing was read." $f.ticketId }
}
$status = ''; try { $status = Get-PsaStatusName ([string]$t['status']) } catch { $status = [string]$t['status'] }
$null = $actions.Add("Read ticket $($f.ticketId) from $psaName.")

# ---- the notes, oldest first, without earlier handoff summaries ----
$all = @()
try { $all = @(Get-PsaTicketNotes -Id $f.sourceId | Where-Object { $null -ne $_ }) } catch { Stop-Run 'error' "The notes on ticket $($f.ticketId) couldn't be read from $($psaName): $($_.Exception.Message)" $f.ticketId }
$ownTag = '[escalation-handoff '
$earlier = @($all | Where-Object { ([string]$_['text']).Contains($ownTag) })
$history = @($all | Where-Object { -not ([string]$_['text']).Contains($ownTag) -and ([string]$_['text']).Trim() } | Sort-Object -Property @{ Expression = { if ($_['created']) { $_['created'] } else { [datetime]::MinValue } } }, @{ Expression = { $n = 0L; [void][long]::TryParse([string]$_['id'], [ref]$n); $n } })
$dropped = 0
if ($history.Count -gt $f.maxNotes) {
    # Keep the first note (how it started) and the newest ones (where it stands).
    $dropped = $history.Count - $f.maxNotes
    $history = @(@($history[0]) + @($history | Select-Object -Last ($f.maxNotes - 1)))
    $null = $warnings.Add("The ticket has $($all.Count - $earlier.Count) notes; the first and the newest $($f.maxNotes - 1) were summarized, and $dropped in between were left out.")
}
$description = (ConvertTo-PsaPlainText ([string]$t['description'])).Trim()
if ($description.Contains($ownTag)) { $description = '' }
$firstText = if ($history.Count) { (ConvertTo-PsaPlainText ([string]$history[0]['text'])).Trim() } else { '' }
if ($description -and $firstText -and ($firstText.StartsWith($description.Substring(0, [Math]::Min(80, $description.Length))))) { $description = '' }
if (-not $history.Count -and -not $description) { Stop-Run 'incomplete' "Ticket $($f.ticketId) has no description or notes to summarize yet. Nothing was written." $f.ticketId }
$null = $actions.Add("Read $($all.Count) note(s)$(if ($earlier.Count) { ", $($earlier.Count) of them earlier handoff summaries (left out)" }).")

# Masks the value after password:, PIN is, key = and the like, and long key-shaped strings, before the AI sees
# them. The same function is in note.ps1, which masks the AI's answer again.
function Hide-EhsSecret {
    param([string]$s)
    if (-not $s) { return '' }
    # "password is Summer2026!" is masked; "password was reset" and "password is expired" are not.
    $s = [regex]::Replace($s, '(?i)\b(password|passwd|pwd|passcode|pin|mfa code|otp|one-time code|recovery code|api key|secret|token|product key)(\s*(?:=|:|\bis\b)\s*)(?!(?:reset|expired|wrong|incorrect|correct|not|being|now|still|the|a|an|set|changed|locked|working|required|needed|too|in|on)\b)("[^"]*"|''[^'']*''|\S+)', '$1$2[hidden]')
    $s = [regex]::Replace($s, '\b[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}\b', '[hidden]')
    $s = [regex]::Replace($s, '\b(?=[A-Za-z0-9+/_-]*\d)(?=[A-Za-z0-9+/_-]*[A-Za-z])[A-Za-z0-9+/_-]{32,}\b', '[hidden]')
    return $s
}
function Get-EhsClean { param([string]$s, [int]$Max) return (Get-PsaText (Hide-EhsSecret (ConvertTo-PsaPlainText $s).Trim()) $Max) }

$kbmsWho = $conn.Psa -eq 'kaseyabms'
$noteRows = @(foreach ($n in $history) {
        $who = if ($n['fromClient']) { 'client' } elseif ($kbmsWho) { 'unknown' } else { 'technician' }
        [ordered]@{
            when = $(if ($n['created']) { ([datetime]$n['created']).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC' } else { '' })
            from = $who; author = [string]$n['author']; visibility = $(if ($n['internal']) { 'internal' } else { 'public' })
            text = (Get-EhsClean ([string]$n['text']) 1500)
        }
    })
if ($kbmsWho) { $null = $warnings.Add('Kaseya BMS notes do not say whether the client or a technician wrote them, so the summary can''t always tell who said what.') }

# ---- time entries, where the PSA has them ----
$time = [ordered]@{ available = $false; totalHours = 0.0; people = @(); entries = @() }
if ($f.includeTime) {
    try {
        $tr = Get-PsaTimeEntries -TicketId $f.sourceId -Max 200
        foreach ($w in @($tr['warnings'])) { if ($w) { $null = $warnings.Add([string]$w) } }
        if ($tr['supported']) {
            $rows = @($tr['entries'] | Where-Object { $null -ne $_ } | Sort-Object -Property @{ Expression = { if ($_['date']) { $_['date'] } else { [datetime]::MinValue } } })
            $total = 0.0; foreach ($e in $rows) { $total += [double]$e['hours'] }
            $people = @($rows | Where-Object { $_['member'] } | Group-Object -Property { [string]$_['member'] } | ForEach-Object { $h = 0.0; foreach ($e in $_.Group) { $h += [double]$e['hours'] }; [ordered]@{ name = $_.Name; hours = [Math]::Round($h, 2) } } | Sort-Object -Property @{ Expression = { $_.hours } } -Descending)
            $time.available = $true; $time.totalHours = [Math]::Round($total, 2); $time.people = @($people)
            $time.entries = @($rows | Where-Object { ([string]$_['notes']).Trim() } | Select-Object -Last 15 | ForEach-Object {
                    [ordered]@{ when = $(if ($_['date']) { ([datetime]$_['date']).ToUniversalTime().ToString('yyyy-MM-dd') } else { '' }); who = [string]$_['member']; hours = $_['hours']; notes = (Get-EhsClean ([string]$_['notes']) 600) } })
            $null = $actions.Add("Read $($rows.Count) time entr$(if ($rows.Count -eq 1) { 'y' } else { 'ies' }) ($($time.totalHours) h).")
        }
        elseif ($tr['reason']) { $null = $warnings.Add("Time entries weren't read: $($tr['reason'])") }
    }
    catch { $null = $warnings.Add("Time entries couldn't be read from $($psaName), so the summary uses the notes only: $($_.Exception.Message)") }
}

# The marker is the ticket plus its newest note, so a retried run adds nothing twice, while new activity on the
# ticket allows a fresh summary.
$newest = if ($history.Count) { [string]$history[-1]['id'] } else { 'start' }
$f.marker = "escalation-handoff $($f.sourceId)-$newest"
# Already summarized at this point (a retry, or a second click): skip the AI call; the note step reports it.
$already = $false
if ($f.addNote -and $earlier.Count) { try { $already = [bool](Test-PsaNoteMarker -Id $f.sourceId -Marker $f.marker -Notes $all) } catch { $already = $false } }

$opened = if ($history.Count -and $history[0]['created']) { ([datetime]$history[0]['created']).ToUniversalTime().ToString('yyyy-MM-dd') } else { '' }
$ticketFacts = [ordered]@{
    number = $f.ticketId; summary = [string]$t['summary']; company = $f.companyName; status = $status
    firstNote = $opened; description = (Get-EhsClean $description 2000)
}
$warnings = @(Get-AllWarnings $warnings)
# What the AI sees: this one ticket only. Ids, links and secrets names never go in.
$facts = [ordered]@{
    ticket = $ticketFacts
    escalation = [ordered]@{ reason = $f.reason; to = $f.escalateTo }
    notes = @($noteRows); notesLeftOut = $dropped
    time = $time
    gaps = @($warnings)
}
$ctx = [ordered]@{
    request = $f; psaName = $psaName; ticket = $ticketFacts; url = (Get-PsaTicketUrl $f.sourceId)
    notesRead = $history.Count; earlierSummaries = $earlier.Count; alreadyPresent = $already; hours = $time.totalHours; timeAvailable = $time.available; people = @($time.people)
    warnings = @($warnings); actions = @($actions)
}
Set-NodeOutput ([ordered]@{
        status = 'ok'
        message = "Read ticket $($f.ticketId): $($history.Count) note(s)$(if ($time.available) { ", $($time.totalHours) h logged" })$(if ($already) { '; a handoff summary for this point is already on it' })."
        ctx_json = ($ctx | ConvertTo-Json -Depth 8 -Compress)
        facts_json = $(if ($already) { '{"skip":true}' } else { $facts | ConvertTo-Json -Depth 8 })
    })
