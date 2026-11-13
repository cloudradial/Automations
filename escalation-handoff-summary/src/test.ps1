# Strict-mode harness for Escalation Handoff Summary. Runs the two PowerShell steps exactly as shipped in
# ../escalation-handoff-summary.yml (via build.js --dump), each through & ([scriptblock]::Create(...)) under
# Set-StrictMode -Version Latest, against the mock PSAs in mock-psa.ps1. The AI step is stood in for by a fixed
# summary JSON, the way the runner would hand it over.
# Placeholder data only (Contoso, Example MSP).
# Usage: pwsh -NoProfile -File test.ps1      (needs node and js-yaml: npm install in _shared, or set JS_YAML_PATH)
. (Join-Path $PSScriptRoot 'mock-psa.ps1')
# The note step reads its bound parameters by name.
function Get-NodeInput { param([string]$Name) if ($Name) { return Get-PsaPropMock $MockHarness.Input $Name }; return $MockHarness.Input }
function Get-PsaPropMock { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }

& node (Join-Path $PSScriptRoot 'build.js') --check
Check 'the .yml matches the source (build.js --check)' ($LASTEXITCODE -eq 0)
Import-Steps (Join-Path $PSScriptRoot 'build.js')
Check 'two PowerShell steps: gather and note' (($MockSteps.Keys -join ',') -eq 'node-gather,node-note') ($MockSteps.Keys -join ', ')

$Open = @{ connectwise = 'In Progress'; autotask = 'In Progress'; halopsa = 'In Progress'; kaseyabms = 'In Progress'; syncro = 'In Progress'; zendesk = 'open' }
# 301: the ticket being escalated. 302: another Contoso ticket that must never show up.
function New-EhsWorld {
    param([string]$Psa)
    Reset-World $Psa
    $s = $Open[$Psa]
    $null = Add-WorldTicket 301 $s -Created 3 -Summary 'Outlook keeps asking for a password' -Notes @(
        @{ d = 3; who = 'client'; text = 'Since Monday Outlook on my laptop keeps prompting for my password every few minutes.' },
        @{ d = 2.9; who = 'tech'; text = 'Cleared cached credentials in Credential Manager and rebuilt the Outlook profile. Prompt came back after an hour.' },
        @{ d = 2; who = 'tech'; internal = $true; text = 'Checked Entra sign-in logs: Conditional Access is not blocking. MFA is fine. Temporary password is Summer2026! for the test account. Password was reset on the test account.' },
        @{ d = 1; who = 'client'; text = 'Still happening and I have a board meeting tomorrow at 9.' }) -Time @(
        @{ d = 2.9; who = 'jlee'; hours = 1.5; notes = 'Rebuilt Outlook profile, cleared Credential Manager.' },
        @{ d = 2; who = 'amorgan'; hours = 0.75; notes = 'Reviewed sign-in logs and CA policies.' })
    $null = Add-WorldTicket 302 $s -Created 3 -Summary 'Printer jam' -Notes @(@{ d = 1; who = 'client'; text = 'Fabrikam secret printer note.' })
}
$Ai = @{
    problem = 'Outlook on the client''s laptop keeps asking for a password every few minutes since Monday.'
    impact = 'One user; they have a board meeting tomorrow at 9.'
    tried = @('Cleared cached credentials and rebuilt the Outlook profile: the prompt came back after an hour.', 'Checked Entra sign-in logs: Conditional Access and MFA are not blocking.')
    ruledOut = @('Conditional Access blocking the sign-in')
    currentState = 'Still prompting after the profile rebuild.'
    waitingOn = ''
    nextSteps = @('Check for a stale WAM token or a second account in Windows settings.', 'Test in a new Windows profile.')
    clientContext = 'Board meeting tomorrow at 9; they want it fixed before then.'
    openQuestions = @('Does it happen on other devices?')
} | ConvertTo-Json -Depth 5 -Compress
$Req = [pscustomobject]@{ ticketId = '301'; reason = 'Needs Tier 2 to look at the Microsoft 365 tenant'; escalateTo = 'Tier 2' }
function Invoke-Note { param($G, [string]$Summary) return ConvertTo-RoundTrip (Invoke-Step 'node-note' ([pscustomobject]@{ ctx = $G.ctx_json; facts = $G.facts_json; summary = $Summary })) }

# ---- 1. Gather on every PSA: this ticket's notes, oldest first, who wrote them, nothing written ----
foreach ($psa in @('connectwise', 'autotask', 'halopsa', 'syncro', 'zendesk', 'kaseyabms')) {
    New-EhsWorld $psa
    $g = Invoke-Step 'node-gather' $Req
    $facts = $g.facts_json | ConvertFrom-Json
    $texts = @($facts.notes | ForEach-Object { $_.text })
    Check "$psa gather: 4 notes, oldest first" ($texts.Count -eq 4 -and $texts[0] -like 'Since Monday*' -and $texts[3] -like 'Still happening*') (@($texts) -join ' || ')
    Check "$psa gather: only ticket 301" ($g.facts_json -notmatch 'Fabrikam|Printer jam') ''
    Check "$psa gather: escalation reason and target passed on" ($facts.escalation.reason -like 'Needs Tier 2*' -and $facts.escalation.to -eq 'Tier 2') ($facts.escalation | ConvertTo-Json -Compress)
    Check "$psa gather: the password value never reaches the AI" ($g.facts_json -notmatch 'Summer2026' -and $g.facts_json -match 'password is \[hidden\]' -and $g.facts_json -match 'Password was reset') ''
    Check "$psa gather: nothing written" (@(Get-Writes).Count -eq 0) (@(Get-Writes | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')
    if ($psa -ne 'kaseyabms') { Check "$psa gather: client and technician notes told apart" ((@($facts.notes | ForEach-Object { $_.from }) -join ',') -eq 'client,technician,technician,client') (@($facts.notes | ForEach-Object { $_.from }) -join ',') }
    else { Check 'kaseyabms gather: author unknown, and a warning says so' ((@($facts.notes | Where-Object { $_.from -eq 'unknown' })).Count -eq 4 -and @($facts.gaps | Where-Object { $_ -like 'Kaseya BMS notes*' }).Count -eq 1) '' }
}

# ---- 2. Time entries where the PSA has them ----
New-EhsWorld 'connectwise'
$g = Invoke-Step 'node-gather' $Req
$facts = $g.facts_json | ConvertFrom-Json
Check 'cw time: 2.25 h, two people, entry notes passed on' ($facts.time.available -eq $true -and [double]$facts.time.totalHours -eq 2.25 -and @($facts.time.people).Count -eq 2 -and $facts.time.people[0].name -eq 'jlee' -and @($facts.time.entries).Count -eq 2) ($facts.time | ConvertTo-Json -Depth 5 -Compress)
New-EhsWorld 'autotask'
$g = Invoke-Step 'node-gather' $Req
Check 'autotask time: 2.25 h read' ([double]($g.facts_json | ConvertFrom-Json).time.totalHours -eq 2.25) ''
New-EhsWorld 'syncro'
$g = Invoke-Step 'node-gather' $Req
Check 'syncro time unreadable: the run goes on with a warning' ($g.status -eq 'ok' -and @(($g.facts_json | ConvertFrom-Json).gaps | Where-Object { $_ -like "Time entries couldn't be read*" }).Count -eq 1) $g.message
New-EhsWorld 'connectwise'
$g = Invoke-Step 'node-gather' ([pscustomobject]@{ ticketId = '301'; includeTime = 'false' })
Check 'includeTime false: no time read' (($g.facts_json | ConvertFrom-Json).time.available -eq $false -and @($MockWorld.calls | Where-Object { $_ -like '*/time/entries*' }).Count -eq 0) ''

# ---- 3. Live on ConnectWise: one internal, marked note; a retry adds nothing; new activity allows a new one ----
New-EhsWorld 'connectwise'
$g = Invoke-Step 'node-gather' $Req
$n = Invoke-Note $g $Ai
$posts = @(Get-Writes 'POST */service/tickets/*/notes')
$body = if ($posts.Count) { [string]$posts[0].Body.text } else { '' }
Check 'cw live: one note, on 301, internal' ($posts.Count -eq 1 -and $posts[0].Uri -like '*/tickets/301/notes' -and $posts[0].Body.internalAnalysisFlag -eq $true -and $posts[0].Body.detailDescriptionFlag -ne $true) (@($posts | ForEach-Object { $_.Uri }) -join '; ')
Check 'cw live: the note has the handoff sections' ($body -match 'Escalation handoff for #301 "Outlook keeps asking for a password", to Tier 2' -and $body -match "Why it's being escalated: Needs Tier 2" -and $body -match 'Tried so far:' -and $body -match 'Ruled out:' -and $body -match '1\. Check for a stale WAM token' -and $body -match 'Client context: Board meeting') $body
Check 'cw live: hours and people come from the PSA' ($body -match '2\.25 h logged \(jlee 1\.5 h, amorgan 0\.75 h\)' -and $body -match '4 note\(s\) read') $body
Check 'cw live: marked with the ticket and newest note' ($body -match '\[escalation-handoff 301-\d+\]') $body
Check 'cw live: no status, owner or priority change' (@(Get-Writes | Where-Object { $_.Method -in @('PATCH', 'PUT') }).Count -eq 0) ''
Check 'cw live: success, AI summary, chat reply leads with the problem' ($n.status -eq 'success' -and $n.note_written -eq $true -and $n.summarized_by -eq 'ai' -and $n.chatReply -like 'Outlook on the client*Next: Check for a stale WAM token*') $n.chatReply

$g2 = Invoke-Step 'node-gather' $Req
Check 'cw retry: the AI step is told to skip' ($g2.facts_json -eq '{"skip":true}' -and ($g2.ctx_json | ConvertFrom-Json).alreadyPresent -eq $true) $g2.message
$n2 = Invoke-Note $g2 '{"skip":true}'
Check 'cw retry: nothing added twice' (@(Get-Writes 'POST */service/tickets/*/notes').Count -eq 1 -and $n2.status -eq 'success' -and $n2.note_written -eq $false -and $n2.message -like '*already on it*') $n2.message
$gp = Invoke-Step 'node-gather' ([pscustomobject]@{ ticketId = '301'; addNote = $false })
Check 'preview after a summary: the earlier summary is left out of the history' (@(($gp.facts_json | ConvertFrom-Json).notes).Count -eq 4 -and $gp.facts_json -notmatch 'Escalation handoff for') ''

$t301 = Get-WorldTicket 301; $t301.notes.Add(@{ id = ($MockWorld.next++); text = 'Tier 1: client now also sees it on their phone.'; created = (Get-Date).ToUniversalTime(); client = $false; internal = $true }) | Out-Null
$g3 = Invoke-Step 'node-gather' $Req
$n3 = Invoke-Note $g3 $Ai
Check 'cw new activity: a fresh summary is allowed' (@(Get-Writes 'POST */service/tickets/*/notes').Count -eq 2 -and $n3.note_written -eq $true) $n3.message

# ---- 4. Preview, AI trouble and masking ----
New-EhsWorld 'halopsa'
$g = Invoke-Step 'node-gather' ([pscustomobject]@{ ticketId = '301'; addNote = $false })
$n = Invoke-Note $g $Ai
Check 'halo preview: nothing written, pending_confirmation with the note' (@(Get-Writes).Count -eq 0 -and $n.status -eq 'pending_confirmation' -and $n.internal_note -match 'Tried so far:') $n.message

New-EhsWorld 'zendesk'
$g = Invoke-Step 'node-gather' $Req
$leak = ($Ai | ConvertFrom-Json); $leak.tried = @('Gave the user the temporary password: Summer2026! and asked them to sign in.', 'Product key ABCDE-12345-FGHIJ-67890-KLMNO re-entered.')
$n = Invoke-Note $g ("Here is the summary: " + ($leak | ConvertTo-Json -Depth 5 -Compress))
$zb = [string]$n.internal_note
Check 'zendesk: AI JSON wrapped in prose is read' ($n.summarized_by -eq 'ai' -and $n.note_written -eq $true) $n.message
Check 'zendesk: a password or product key the AI repeated is masked' ($zb -notmatch 'Summer2026' -and $zb -notmatch 'ABCDE-12345' -and $zb -match 'temporary password: \[hidden\]') $zb
Check 'zendesk: the note is a private comment' (@(Get-Writes 'PUT */tickets/301' | Where-Object { $_.Body.ticket.comment.public -eq $false }).Count -eq 1) ''

New-EhsWorld 'autotask'
$g = Invoke-Step 'node-gather' $Req
$n = Invoke-Note $g 'Sorry, I cannot help with that.'
Check 'unusable AI answer: a plain note from the newest notes, said plainly' ($n.summarized_by -eq 'notes' -and $n.note_written -eq $true -and $n.internal_note -match 'The AI summary was not available' -and $n.internal_note -match 'Still happening' -and @($n.warnings | Where-Object { $_ -like 'The AI summary was empty or unreadable*' }).Count -eq 1) $n.internal_note

# ---- 5. Long tickets and earlier summaries ----
Reset-World 'connectwise'
$many = @(for ($i = 40; $i -ge 1; $i--) { @{ d = $i / 10; who = $(if ($i % 2) { 'client' } else { 'tech' }); text = "Note number $(41 - $i)" } })
$null = Add-WorldTicket 301 'In Progress' -Created 5 -Notes $many
$g = Invoke-Step 'node-gather' ([pscustomobject]@{ ticketId = '301'; maxNotes = 10 })
$facts = $g.facts_json | ConvertFrom-Json
Check 'maxNotes: the first note and the newest 9 are kept' (@($facts.notes).Count -eq 10 -and $facts.notes[0].text -eq 'Note number 1' -and $facts.notes[1].text -eq 'Note number 32' -and $facts.notes[9].text -eq 'Note number 40' -and $facts.notesLeftOut -eq 30) (@($facts.notes | ForEach-Object { $_.text }) -join ', ')

# ---- 6. Bad requests stop early and read nothing ----
New-EhsWorld 'connectwise'
Check 'no ticketId: incomplete' ((Get-ThrowMessage { Invoke-Step 'node-gather' ([pscustomobject]@{ reason = 'x' }) }) -like 'ticketId is missing*')
Check 'ServiceAI placeholder counts as not given' ((Get-ThrowMessage { Invoke-Step 'node-gather' ([pscustomobject]@{ ticketId = '<ticketId>' }) }) -like 'ticketId is missing*')
$g = Invoke-Step 'node-gather' ([pscustomobject]@{ ticketId = '301'; reason = '<reason>'; escalateTo = '{{escalateTo}}' })
Check 'unfilled reason and target are left blank' ((($g.facts_json | ConvertFrom-Json).escalation.reason) -eq '' -and (($g.facts_json | ConvertFrom-Json).escalation.to) -eq '') ''
Check 'bad maxNotes: plain message' ((Get-ThrowMessage { Invoke-Step 'node-gather' ([pscustomobject]@{ ticketId = '301'; maxNotes = 500 }) }) -like 'maxNotes must be a whole number from 5 to 100*')
Check 'companyId mismatch: rejected' ((Get-ThrowMessage { Invoke-Step 'node-gather' ([pscustomobject]@{ ticketId = '301'; companyId = '77' }) }) -like '*belongs to a different company*' -and $MockHarness.Output.status -eq 'rejected')
Check 'unknown ticket: incomplete, plain message' ((Get-ThrowMessage { Invoke-Step 'node-gather' ([pscustomobject]@{ ticketId = '999' }) }) -like "Ticket 999 couldn't be read*" -and $MockHarness.Output.status -eq 'incomplete')
Check 'CloudRadial {Ticket:{TicketId}} body is read' ((Invoke-Step 'node-gather' ([pscustomobject]@{ Ticket = [pscustomobject]@{ TicketId = 301 } })).status -eq 'ok')

Complete-Test
