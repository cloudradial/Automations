# === Step 3: Post the handoff note ===
# Edit this file, then run: node escalation-handoff-summary/src/build.js
# Turns the AI's JSON into one internal (technician-only) note on the ticket, with the hours and people from the PSA
# copied in, never from the AI. Anything that looks like a password, PIN, key or code is masked again here, in case
# the AI repeated one. When the AI answer is unusable, a plain note from the newest notes is posted instead and says
# so. addNote=false returns the note as a preview and writes nothing. Nothing else on the ticket changes.
$ErrorActionPreference = 'Stop'

function Read-EhsJson { param($v) if ($null -eq $v) { return $null }; if ($v -isnot [string]) { return $v }; $s = $v.Trim(); if (-not $s) { return $null }; if ($s -match '(?s)\{.*\}') { try { return ($Matches[0] | ConvertFrom-Json) } catch { } }; return $null }
$stopState = @{ done = $false; ticket = '' }
$warnings = New-Object System.Collections.ArrayList
function Get-AllWarnings {
    param($Own)
    $all = New-Object System.Collections.ArrayList
    foreach ($w in @(@($Own) + @($PsaState.Warnings))) { $t = [string]$w; if ($t -and -not $all.Contains($t)) { $null = $all.Add($t) } }
    return @($all)
}
trap { if (-not $stopState.done) { $stopState.done = $true; Set-NodeOutput ([ordered]@{ status = 'error'; message = [string]$_.Exception.Message; public_note = ''; internal_note = "The handoff summary failed while writing the note: $($_.Exception.Message)"; ticket_id = $stopState.ticket; note_written = $false; actions = @(); warnings = @(Get-AllWarnings $warnings); chatReply = "The handoff summary failed: $($_.Exception.Message)" }) }; break }

$ctx = Read-EhsJson (Get-NodeInput -Name 'ctx')
if ($null -eq $ctx) { $stopState.done = $true; $why = 'The ticket history from the first step is missing. Run the workflow from the start.'; Set-NodeOutput ([ordered]@{ status = 'error'; message = $why; public_note = ''; internal_note = ''; ticket_id = ''; note_written = $false; actions = @(); warnings = @(); chatReply = $why }); throw $why }
$req = Get-PsaProp $ctx 'request'
$ticketRef = [string](Get-PsaProp $req 'ticketId'); $stopState.ticket = $ticketRef
$addNote = (Get-PsaProp $req 'addNote') -ne $false
$tk = Get-PsaProp $ctx 'ticket'
$psaName = [string](Get-PsaProp $ctx 'psaName')
$actions = New-Object System.Collections.ArrayList
foreach ($w in @(Get-PsaProp $ctx 'warnings')) { if ($w) { $null = $warnings.Add([string]$w) } }
foreach ($a in @(Get-PsaProp $ctx 'actions')) { if ($a) { $null = $actions.Add([string]$a) } }
if ((Get-PsaProp $ctx 'alreadyPresent') -eq $true) {
    $stopState.done = $true
    $msg = "A handoff summary for ticket $ticketRef at this point is already on it, so nothing was written again."
    Set-NodeOutput ([ordered]@{ status = 'success'; message = $msg; public_note = ''; internal_note = ''; ticket_id = $ticketRef; psa = [string](Get-PsaProp $req 'psa'); summarized_by = 'none'; note_written = $false; actions = @($actions); warnings = @(Get-AllWarnings $warnings); chatReply = "$msg It's the newest handoff note on #$ticketRef." })
    return
}

# Masks the value after password:, PIN is, key = and the like, and long key-shaped strings.
function Hide-EhsSecret {
    param([string]$s)
    if (-not $s) { return '' }
    # "password is Summer2026!" is masked; "password was reset" and "password is expired" are not.
    $s = [regex]::Replace($s, '(?i)\b(password|passwd|pwd|passcode|pin|mfa code|otp|one-time code|recovery code|api key|secret|token|product key)(\s*(?:=|:|\bis\b)\s*)(?!(?:reset|expired|wrong|incorrect|correct|not|being|now|still|the|a|an|set|changed|locked|working|required|needed|too|in|on)\b)("[^"]*"|''[^'']*''|\S+)', '$1$2[hidden]')
    $s = [regex]::Replace($s, '\b[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}\b', '[hidden]')
    $s = [regex]::Replace($s, '\b(?=[A-Za-z0-9+/_-]*\d)(?=[A-Za-z0-9+/_-]*[A-Za-z])[A-Za-z0-9+/_-]{32,}\b', '[hidden]')
    return $s
}
function Get-EhsLine { param($v, [int]$Max = 400) return (Get-PsaText (Hide-EhsSecret ([string]$v).Trim()) $Max) }
function Get-EhsList { param($v, [int]$Most, [int]$Max = 300) return @(@($v) | Where-Object { $null -ne $_ -and ([string]$_).Trim() } | Select-Object -First $Most | ForEach-Object { Get-EhsLine $_ $Max }) }

# ---- the AI summary ----
$ai = Read-EhsJson (Get-NodeInput -Name 'summary')
$problem = Get-EhsLine (Get-PsaProp $ai 'problem')
$tried = @(Get-EhsList (Get-PsaProp $ai 'tried') 8)
$next = @(Get-EhsList (Get-PsaProp $ai 'nextSteps') 4)
$by = 'ai'
if (-not $problem -or (-not $tried.Count -and -not $next.Count -and -not (Get-EhsLine (Get-PsaProp $ai 'currentState')))) { $by = 'notes' }

$number = [string](Get-PsaProp $tk 'number'); if (-not $number) { $number = $ticketRef }
$to = [string](Get-PsaProp $req 'escalateTo'); $reason = [string](Get-PsaProp $req 'reason')
$lines = New-Object System.Collections.ArrayList
$null = $lines.Add("Escalation handoff for #$number `"$(Get-EhsLine (Get-PsaProp $tk 'summary') 200)`"$(if ($to) { ", to $to" }). Internal; not sent to the client.")
if ($reason) { $null = $lines.Add("Why it's being escalated: $(Get-EhsLine $reason 500)") }
$null = $lines.Add('')
if ($by -eq 'ai') {
    $null = $lines.Add("Problem: $problem")
    $impact = Get-EhsLine (Get-PsaProp $ai 'impact'); if ($impact) { $null = $lines.Add("Impact: $impact") }
    if ($tried.Count) { $null = $lines.Add(''); $null = $lines.Add('Tried so far:'); foreach ($x in $tried) { $null = $lines.Add("- $x") } }
    $ruled = @(Get-EhsList (Get-PsaProp $ai 'ruledOut') 5)
    if ($ruled.Count) { $null = $lines.Add(''); $null = $lines.Add('Ruled out:'); foreach ($x in $ruled) { $null = $lines.Add("- $x") } }
    $state = Get-EhsLine (Get-PsaProp $ai 'currentState'); $wait = Get-EhsLine (Get-PsaProp $ai 'waitingOn')
    if ($state -or $wait) { $null = $lines.Add(''); if ($state) { $null = $lines.Add("Where it stands: $state") }; if ($wait) { $null = $lines.Add("Waiting on: $wait") } }
    if ($next.Count) { $null = $lines.Add(''); $null = $lines.Add('Suggested next steps:'); $i = 0; foreach ($x in $next) { $i++; $null = $lines.Add("$i. $x") } }
    $cc = Get-EhsLine (Get-PsaProp $ai 'clientContext'); if ($cc) { $null = $lines.Add(''); $null = $lines.Add("Client context: $cc") }
    $oq = @(Get-EhsList (Get-PsaProp $ai 'openQuestions') 3)
    if ($oq.Count) { $null = $lines.Add(''); $null = $lines.Add('Worth confirming:'); foreach ($x in $oq) { $null = $lines.Add("- $x") } }
}
else {
    $null = $warnings.Add('The AI summary was empty or unreadable, so the note lists the ticket''s newest notes instead.')
    $desc = Get-EhsLine (Get-PsaProp $tk 'description') 600
    if ($desc) { $null = $lines.Add("Reported: $desc") }
    $null = $lines.Add('The AI summary was not available. Newest notes, oldest first:')
    $facts = Read-EhsJson (Get-NodeInput -Name 'facts')
    foreach ($n in @(@(Get-PsaProp $facts 'notes') | Where-Object { $null -ne $_ } | Select-Object -Last 3)) { $null = $lines.Add("- $(Get-PsaProp $n 'when') ($(Get-PsaProp $n 'from')): $(Get-EhsLine (Get-PsaProp $n 'text') 400)") }
}

# ---- facts from the PSA, never from the AI ----
$null = $lines.Add('')
$bits = New-Object System.Collections.ArrayList
$st = [string](Get-PsaProp $tk 'status'); if ($st) { $null = $bits.Add("status $st") }
$fn = [string](Get-PsaProp $tk 'firstNote'); if ($fn) { $null = $bits.Add("first note $fn") }
$null = $bits.Add("$(Get-PsaProp $ctx 'notesRead') note(s) read")
if ((Get-PsaProp $ctx 'timeAvailable') -eq $true) {
    $ppl = @(@(Get-PsaProp $ctx 'people') | Where-Object { $null -ne $_ } | ForEach-Object { "$(Get-PsaProp $_ 'name') $(Get-PsaProp $_ 'hours') h" })
    $null = $bits.Add("$(Get-PsaProp $ctx 'hours') h logged$(if ($ppl.Count) { " ($($ppl -join ', '))" })")
}
$null = $lines.Add("From $($psaName): $($bits -join '; ').")
$url = [string](Get-PsaProp $ctx 'url'); if ($url) { $null = $lines.Add($url) }
$all = @(Get-AllWarnings $warnings)
foreach ($w in $all) { $null = $lines.Add("Note: $w") }
$null = $lines.Add($(if ($by -eq 'ai') { 'Summarized by AI from the ticket''s notes and time entries; check the ticket before acting on it.' } else { 'Built from the ticket''s notes without AI.' }))
$note = ($lines -join "`n").Trim()

# ---- write it ----
$written = $false; $already = $false
if ($addNote) {
    $null = Connect-Psa -Psa (Get-PsaType ([string](Get-PsaProp $req 'psa')))
    $r = Add-PsaNote -Id ([string](Get-PsaProp $req 'sourceId')) -Text $note -Title 'Escalation handoff' -Internal -Marker ([string](Get-PsaProp $req 'marker'))
    $written = $r -eq 'written'; $already = $r -eq 'already-present'
    $null = $actions.Add($(if ($written) { "Added the handoff summary as an internal note on ticket $ticketRef." } else { "A handoff summary for this point in ticket $ticketRef was already on it, so it was not added again." }))
}

$headline = if ($by -eq 'ai') { $problem } else { "Ticket $ticketRef has no AI summary; its newest notes are listed." }
$nextLine = if ($next.Count) { " Next: $($next[0])" } else { '' }
$message = if ($written) { "Handoff summary added as an internal note on ticket $ticketRef." } elseif ($already) { "A handoff summary for ticket $ticketRef at this point was already on it, so nothing was written again." } else { "Handoff summary for ticket $ticketRef is ready. Nothing was written (addNote is false)." }
$stopState.done = $true
Set-NodeOutput ([ordered]@{
        status = $(if ($written -or $already) { 'success' } else { 'pending_confirmation' }); message = $message; public_note = ''; internal_note = $note
        ticket_id = $ticketRef; psa = [string](Get-PsaProp $req 'psa'); summarized_by = $by; note_written = $written
        actions = @($actions); warnings = @(Get-AllWarnings $warnings)
        chatReply = "$headline$nextLine$(if ($written) { " The full handoff summary is an internal note on #$ticketRef." } elseif ($already) { " The summary was already on #$ticketRef." } else { ' Nothing was written.' })"
    })
