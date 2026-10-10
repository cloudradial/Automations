# Strict-mode harness for Auto-Escalation.
# Runs each PowerShell step exactly as it is in auto-escalation.yml (the _shared libraries included),
# through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the runner
# Key Vault, Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked. Outputs pass through JSON between
# steps, as the runner does. Placeholder data only (Contoso, Example MSP).
# The shared libraries have their own tests (_shared/tests/run.ps1); this file tests the steps.
# Test variables start with T: a step runs in a child scope of this script, and a same-named step variable
# would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File auto-escalation/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

# ---- the steps, straight from the built workflow ----
$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\auto-escalation.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.type==='powershell-script')o[a.id]={s:a.properties.script,p:a.properties.parameters};}console.log(JSON.stringify(o));"
$TSteps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow has find, reassign, notify and note steps, all unbound (Routine)' ($TSteps.Contains('find') -and $TSteps.Contains('reassign') -and $TSteps.Contains('notify') -and $TSteps.Contains('note') -and -not @($TSteps.Values | Where-Object { @($_.p).Count }).Count)

# ---- runner mocks ----
$global:NodeIn = $null; $global:NodeOut = $null
function Get-NodeInput { param([string]$Name) return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Invoke-Step {
    param([string]$Id, $In = $null)
    $global:NodeIn = $In; $global:NodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $TSteps[$Id].s)) } catch { $err = [string]$_.Exception.Message }
    $o = $null; if ($null -ne $global:NodeOut) { $o = ($global:NodeOut | ConvertTo-Json -Depth 12 | ConvertFrom-Json) }
    return @{ out = $o; error = $err }
}
function Invoke-Flow {
    param($Body)
    $TIn = if ($null -eq $Body) { $null } else { $Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json }
    $TPrev = $null
    foreach ($TId in @('find', 'reassign', 'notify', 'note')) {
        $TS = Invoke-Step $TId $(if ($TId -eq 'find') { $TIn } else { $TPrev })
        if ($TS.error) { return @{ stage = $TId; out = $TS.out; error = $TS.error; find = $(if ($TId -eq 'find') { $TS.out } else { $global:TFindOut }) } }
        if ($TId -eq 'find') { $global:TFindOut = $TS.out }
        $TPrev = $TS.out
    }
    return @{ stage = 'note'; out = $TPrev; error = ''; find = $global:TFindOut }
}
function Get-TWrites { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and $_.Uri -notlike '*postmarkapp*' -and $_.Uri -notlike '*/auth/token' -and $_.Uri -notlike '*/security/authenticate' }) }
function Get-TPostmark { return @($Mock.Calls | Where-Object { $_.Uri -like 'https://api.postmarkapp.com/email' }) }
function Get-TEsc { param($R, [string]$Id) return (@($R.out.escalations | Where-Object { $_.id -eq $Id }) | Select-Object -First 1) }

# ---- placeholder data ----
$TPostmark = @{ 'Postmark-ServerToken' = 'pm-token'; 'Postmark-FromEmail' = 'alerts@example.com' }
$TPsa = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://cw.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
}
function Get-TSecrets { param([string]$P, [switch]$NoPostmark) $s = @{}; foreach ($k in $TPsa[$P].Keys) { $s[$k] = $TPsa[$P][$k] }; if (-not $NoPostmark) { foreach ($k in $TPostmark.Keys) { $s[$k] = $TPostmark[$k] } }; return $s }
function Get-TAgo { param([double]$Minutes) return [datetime]::UtcNow.AddMinutes(-$Minutes).ToString('yyyy-MM-ddTHH:mm:ssZ') }
$TMap = @{ 'Service Desk' = 'Tier 2'; 'Tier 2' = @{ queue = 'Tier 3'; assignee = 'escalations' } }
$TBody = @{ escalation_map = ($TMap | ConvertTo-Json -Compress); dispatcher_email = 'dispatch@example.com' }

# ConnectWise tickets:
#   2001 high, Service Desk, idle 120 min (limit 60)      -> move to Tier 2
#   2002 critical, Alerts (no map entry), idle 30 (15)    -> note and notify only
#   2003 high, assigned and updated 10 min ago, but its SLA respond target passed -> note only, stays with the tech
#   2004 high, idle 180, already has an [Auto-Escalation] note -> skipped
#   2005 low, idle 60 (limit 480)                          -> fine
#   2006 waiting on client                                 -> skipped
#   2007 medium, Tier 2, idle 300 (limit 240)              -> move to Tier 3 and assign "escalations"
function New-TCw { param($Id, $Summary, $Co, $Board, $Prio, $PrioId, $Owner, $Idle, $Created, $Status = 'In Progress', $Sla = $null)
    $t = [ordered]@{ id = $Id; summary = $Summary; company = [pscustomobject]@{ id = $(if ($Co -eq 'Contoso Ltd') { 5 } else { 6 }); name = $Co }; status = [pscustomobject]@{ name = $Status }; priority = [pscustomobject]@{ id = $PrioId; name = $Prio }; board = [pscustomobject]@{ id = 1; name = $Board }; _info = [pscustomobject]@{ dateEntered = (Get-TAgo $Created); lastUpdated = (Get-TAgo $Idle) } }
    if ($Owner) { $t.owner = [pscustomobject]@{ id = 7; identifier = $Owner; name = "$Owner (name)" } }
    if ($Sla) { $t.sla = [pscustomobject]@{ id = $Sla }; $t.dateResponded = $null }
    return [pscustomobject]$t
}
$TCwTickets = @(
    (New-TCw 2001 'Server down' 'Contoso Ltd' 'Service Desk' 'Priority 2 - Quick Response' 2 'jlee' 120 200)
    (New-TCw 2002 'Firewall alert <WAN>' 'Contoso Ltd' 'Alerts' 'Priority 1 - Emergency Response' 1 $null 30 40)
    (New-TCw 2003 'Email slow' 'Example MSP' 'Service Desk' 'Priority 2 - Quick Response' 2 'spatel' 10 400 -Sla 5)
    (New-TCw 2004 'Laptop broken' 'Example MSP' 'Service Desk' 'Priority 2 - Quick Response' 2 'jlee' 180 300)
    (New-TCw 2005 'New mouse' 'Example MSP' 'Service Desk' 'Priority 4 - Low' 4 $null 60 60)
    (New-TCw 2006 'Quote' 'Example MSP' 'Service Desk' 'Priority 1 - Emergency Response' 1 $null 900 900 -Status 'Waiting on Client')
    (New-TCw 2007 'Database errors' 'Contoso Ltd' 'Tier 2' 'Priority 3 - Normal Response' 3 'jlee' 300 400)
)
$global:TCw = @{ tickets = $TCwTickets; failFind = 0; failPatch = ''; failNotes = ''; pm = 0 }
$TCwHandler = { param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    if ($c.Uri -like 'https://api.postmarkapp.com/email') { if ($global:TCw.pm) { New-HttpError $global:TCw.pm '{"ErrorCode":10,"Message":"Bad token"}' }; return [pscustomobject]@{ ErrorCode = 0; MessageID = 'm1' } }
    if ($c.Method -eq 'GET' -and $u -like '*/service/tickets[?]*') { if ($global:TCw.failFind) { New-HttpError $global:TCw.failFind '{"message":"denied"}' }; return , @($global:TCw.tickets) }
    if ($c.Method -eq 'GET' -and $u -match '/service/tickets/(\d+)/notes\?') {
        $TTid = $Matches[1]
        if ($global:TCw.failNotes -eq $TTid) { New-HttpError 500 'oops' }
        $TBase = if ($TTid -eq '2004') { [pscustomobject]@{ id = 1; text = '[Auto-Escalation] This ticket was escalated automatically.'; internalAnalysisFlag = $true; dateCreated = (Get-TAgo 200) } } else { [pscustomobject]@{ id = 1; text = 'Customer called'; internalAnalysisFlag = $false; dateCreated = (Get-TAgo 500) } }
        # Notes this test has POSTed are on the ticket too, so a rerun sees them (as the PSA would).
        $TPosted = @($Mock.Calls | Where-Object { $_.Method -eq 'POST' -and $_.Uri -like "*/service/tickets/$TTid/notes" } | ForEach-Object { [pscustomobject]@{ id = 50; text = (Read-Body $_).text; internalAnalysisFlag = $true; dateCreated = (Get-TAgo 0) } })
        return , @(@($TBase) + $TPosted)
    }
    if ($u -like '*/company/companies*') { if ($u -match 'name="Contoso Ltd"') { return , @([pscustomobject]@{ id = 5; name = 'Contoso Ltd' }) }; return , @() }
    if ($u -like '*/service/SLAs/5/priorities*') { return , @([pscustomobject]@{ priority = [pscustomobject]@{ id = 2 }; respondHours = 2; resolutionHours = 8 }) }
    if ($u -like '*/service/SLAs/5') { return [pscustomobject]@{ id = 5; respondHours = 4; resolutionHours = 24 } }
    if ($c.Method -eq 'PATCH' -and $u -match '/service/tickets/(\d+)$') { if ($global:TCw.failPatch -eq $Matches[1]) { New-HttpError 403 '{"message":"denied"}' }; return [pscustomobject]@{ id = [int]$Matches[1] } }
    if ($c.Method -eq 'POST' -and $u -match '/service/tickets/(\d+)/notes$') { return [pscustomobject]@{ id = 99 } }
    throw "unmocked $($c.Method) $u"
}
function Get-TCwNotes { return @(Get-Calls POST '*/service/tickets/*/notes') }
function Get-TCwNote { param([string]$Id) $x = @(Get-Calls POST "*/service/tickets/$Id/notes"); if ($x.Count) { return (Read-Body $x[0]) }; return $null }

# ---- 1. Preview: plan only, nothing changes ----
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow ($TBody + @{ preview = $true })
Check 'Preview: pending_confirmation, nothing written, no email' ($TR.stage -eq 'note' -and $TR.out.status -eq 'pending_confirmation' -and @(Get-TWrites).Count -eq 0 -and @(Get-TPostmark).Count -eq 0) "$($TR.error) $(Show-Calls)"
Check 'Preview: 4 planned (2 moves, 2 note-only), 1 already escalated, 1 waiting skipped' (@($TR.out.escalations).Count -eq 4 -and $TR.out.counts.toReassign -eq 2 -and $TR.out.counts.noteOnly -eq 2 -and $TR.out.counts.alreadyEscalated -eq 1 -and $TR.out.counts.skipped -eq 1) ($TR.out.counts | ConvertTo-Json -Compress)
Check 'Preview: message says nothing changed and how to apply' ($TR.out.message -match '^Preview: 4 tickets would be escalated \(2 moved up a tier, 2 noted and flagged only\)\. Nothing was changed\.') $TR.out.message
Check 'Preview: outcome says what would happen' ((Get-TEsc $TR '2007').outcome -eq 'Would move it from Tier 2 to Tier 3 and assign it to escalations.') (Get-TEsc $TR '2007').outcome

# ---- 2. Live (preview false, the default) ----
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow $TBody
Check 'Live: success' ($TR.stage -eq 'note' -and $TR.out.status -eq 'success') "$($TR.error) $($TR.out.message)"
$TP = @(Get-Calls PATCH '*/service/tickets/*')
$TP2001 = @($TP | Where-Object { $_.Uri -like '*/2001' }); $TP2007 = @($TP | Where-Object { $_.Uri -like '*/2007' })
Check 'Live: 2001 moved to Tier 2 (board), owner untouched' ($TP2001.Count -eq 1 -and (Read-Body $TP2001[0])[0].path -eq 'board' -and (Read-Body $TP2001[0])[0].value.name -eq 'Tier 2') (Show-Calls)
Check 'Live: 2007 moved to Tier 3 and assigned to the mapped user, one tier only' ($TP2007.Count -eq 2 -and (Read-Body $TP2007[0])[0].value.name -eq 'Tier 3' -and (Read-Body $TP2007[1])[0].path -eq 'owner' -and (Read-Body $TP2007[1])[0].value.identifier -eq 'escalations') (Show-Calls)
Check 'Live: no reassignment for the unmapped queue or the actively worked ticket' (@($TP | Where-Object { $_.Uri -like '*/2002' -or $_.Uri -like '*/2003' -or $_.Uri -like '*/2004' }).Count -eq 0) (Show-Calls)
$TPm = @(Get-TPostmark); $TPmBody = if ($TPm.Count) { $TPm[0].Body | ConvertFrom-Json } else { $null }
Check 'Live: one dispatcher email listing all 4, HTML-escaped' ($TPm.Count -eq 1 -and $TPmBody.To -eq 'dispatch@example.com' -and $TPmBody.Subject -eq 'Auto-Escalation: 4 tickets escalated' -and $TPmBody.HtmlBody -match 'Firewall alert &lt;WAN&gt;' -and $TPmBody.HtmlBody -match '2007') (Show-Calls)
Check 'Live: 4 internal notes, each starting with the marker' (@(Get-TCwNotes).Count -eq 4 -and -not @(Get-TCwNotes | Where-Object { $b = Read-Body $_; -not ($b.internalAnalysisFlag -eq $true -and $b.detailDescriptionFlag -eq $false -and $b.text.StartsWith('[Auto-Escalation] ')) }).Count) ((Get-TCwNotes | ForEach-Object { $_.Body }) -join ' || ')
$TN1 = Get-TCwNote 2001; $TN2 = Get-TCwNote 2002; $TN3 = Get-TCwNote 2003
Check 'Live: 2001 note gives the reason, the move and the email' ($TN1.text -match 'no update for 2 hours, past the 60-minute limit for high priority tickets' -and $TN1.text -match 'Auto-Escalation is going to move it from Service Desk to Tier 2\.' -and $TN1.text -match 'The dispatcher is being emailed') $TN1.text
$TCw2001 = @($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and $_.Uri -match '/service/tickets/2001(/notes)?$' })
Check 'Live: 2001 marker note is written before the move' ($TCw2001.Count -eq 2 -and $TCw2001[0].Method -eq 'POST' -and $TCw2001[1].Method -eq 'PATCH' -and (Get-TEsc $TR '2001').outcome -eq 'It was moved from Service Desk to Tier 2.') (($TCw2001 | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join ' ; ')
Check 'Live: no follow-up notes when everything went to plan' (-not @(Get-TCwNotes | Where-Object { (Read-Body $_).text.Contains('[Auto-Escalation: follow-up]') }).Count) ''
Check 'Live: 2002 note says why it was not moved' ($TN2.text -match "There is no escalation_map entry for Alerts, so it wasn't moved\.") $TN2.text
Check 'Live: 2003 note keeps it with the working tech and names the SLA' ($TN3.text -match 'Its SLA respond-by time .* has passed\.' -and $TN3.text -match 'stays with them') $TN3.text
Check 'Live: already-escalated 2004 gets nothing' ($null -eq (Get-TCwNote 2004)) ''
Check 'Live: message and contract' ($TR.out.message -match '^Escalated 4 tickets: 2 moved up a tier and 2 flagged without moving\. The dispatcher was emailed' -and $TR.out.public_note -eq '' -and $TR.out.internal_note -match 'Ticket 2001 \(Contoso Ltd\)' -and @($TR.out.actions).Count -ge 7) $TR.out.message
Check 'Live: no em dashes in notes or email' (-not (@(Get-TCwNotes | Where-Object { $_.Body -match [char]0x2014 }).Count) -and $TPmBody.HtmlBody -notmatch [char]0x2014) ''

# ---- 2b. company input: only that client's tickets are read, moved or noted ----
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow ($TBody + @{ company = '5' })
$TU = [uri]::UnescapeDataString((Get-Calls GET '*/service/tickets[?]*')[0].Uri)
$TOther = @($Mock.Calls | Where-Object { $_.Uri -match '/service/tickets/(2003|2004|2005|2006)(/|$|\?)' })
Check 'company=5 (id): filter sent to the PSA; only Contoso tickets escalated (2001, 2002, 2007)' ($TR.out.status -eq 'success' -and $TU -match 'company/id=5' -and (@($TR.out.escalations | ForEach-Object { $_.id } | Sort-Object) -join ',') -eq '2001,2002,2007') "$TU | $(($TR.out.escalations | ForEach-Object { $_.id }) -join ',')"
Check 'company=5: no read, move or note on any other company''s ticket, even though the mock returned them' ($TOther.Count -eq 0 -and @(Get-TCwNotes).Count -eq 3) (($TOther | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join ' ; ')
Check 'company=5: the message names the scope' ($TR.out.message -match '^Escalated 3 tickets for company 5: ') $TR.out.message
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow ($TBody + @{ company = 'Contoso Ltd'; preview = $true })
Check 'company by exact name (preview): looked up, only that company, nothing written' ($TR.out.status -eq 'pending_confirmation' -and @($TR.out.escalations).Count -eq 3 -and $TR.out.message -match 'would be escalated for Contoso Ltd' -and @(Get-TWrites).Count -eq 0) $TR.out.message
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow ($TBody + @{ company = 'Nobody Inc' })
Check 'unknown company name: rejected before any ticket is read; nothing written' ($TR.stage -eq 'find' -and $TR.out.status -eq 'rejected' -and $TR.out.message -match "has no company named 'Nobody Inc'" -and @(Get-Calls GET '*/service/tickets*').Count -eq 0 -and @(Get-TWrites).Count -eq 0) $TR.out.message

# ---- 3. max_tickets ----
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow ($TBody + @{ max_tickets = 1 })
Check 'max_tickets=1: only the most overdue ticket (2003, SLA passed) is escalated, the rest wait' (@($TR.out.escalations).Count -eq 1 -and $TR.out.escalations[0].id -eq '2003' -and $TR.out.ticket_id -eq '2003' -and @($TR.out.warnings) -match 'left for the next run') (($TR.out.escalations | ForEach-Object { $_.id }) -join ',')

# ---- 4. No Postmark: the note is the notification ----
Reset-Mock -Secrets (Get-TSecrets connectwise -NoPostmark) -Handler $TCwHandler
$TR = Invoke-Flow $TBody
Check 'No Postmark: success, no email, notes say they are the notification, plain warning' ($TR.out.status -eq 'success' -and @(Get-TPostmark).Count -eq 0 -and $TR.out.dispatcher_emailed -eq $false -and (Get-TCwNote 2001).text -match 'No dispatcher email is set up, so this note is the notification\.' -and @($TR.out.warnings) -match "Postmark isn't set up" -and @(Get-TCwNotes).Count -eq 4) ($TR.out.warnings -join ' | ')

# ---- 5. Postmark refuses ----
$global:TCw.pm = 401
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow $TBody
Check 'Postmark 401: escalations and notes still done, plain warning' ($TR.out.status -eq 'success' -and @(Get-Calls PATCH '*/2001').Count -eq 1 -and @($TR.out.warnings) -match "dispatcher email couldn't be sent.*\(HTTP 401\)") ($TR.out.warnings -join ' | ')
$TFollow = @(Get-TCwNotes | Where-Object { (Read-Body $_).text.StartsWith('[Auto-Escalation: follow-up] ') })
Check 'Postmark 401: one follow-up note per escalated ticket says the email failed' (@(Get-TCwNotes).Count -eq 8 -and $TFollow.Count -eq 4 -and (Read-Body $TFollow[0]).text -match 'dispatcher email could not be sent, so these notes are the notification') ((Get-TCwNotes | ForEach-Object { (Read-Body $_).text }) -join ' || ')
$global:TCw.pm = 0

# ---- 6. Routine with no input: live, empty map, no dispatcher ----
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow $null
Check 'No input (Routine): defaults, nothing moved (no map), notes added, no email' ($TR.out.status -eq 'success' -and @(Get-Calls PATCH '*').Count -eq 0 -and @(Get-TCwNotes).Count -eq 4 -and @(Get-TPostmark).Count -eq 0 -and @($TR.out.warnings) -match 'No dispatcher_email was given') "$($TR.error) $($TR.out.message)"

$TS2 = Get-TSecrets connectwise; $TS2['Dispatcher-Email'] = 'dispatch@example.com'; $TS2['AutoEscalation-Map'] = ($TMap | ConvertTo-Json -Compress)
Reset-Mock -Secrets $TS2 -Handler $TCwHandler
$TR = Invoke-Flow $null
Check 'No input (Routine) with the Dispatcher-Email and AutoEscalation-Map secrets: moves and emails' ($TR.out.status -eq 'success' -and @(Get-Calls PATCH '*/2001').Count -eq 1 -and @(Get-TPostmark).Count -eq 1 -and ((@(Get-TPostmark))[0].Body | ConvertFrom-Json).To -eq 'dispatch@example.com') "$($TR.error) $($TR.out.message)"

# ---- 7. Missing permission (403) on the ticket list, and on one reassignment ----
$global:TCw.failFind = 403
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow $TBody
Check '403 on list: stops at find with a plain sentence, nothing written' ($TR.stage -eq 'find' -and $TR.out.status -eq 'error' -and $TR.out.message -match 'refused to list tickets \(HTTP 403\)\. Give the API user permission to read service tickets' -and @(Get-TWrites).Count -eq 0) $TR.out.message
$global:TCw.failFind = 0
$global:TCw.failPatch = '2001'
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow $TBody
Check '403 on a move: incomplete, plain reason, others still done, note still added' ($TR.out.status -eq 'incomplete' -and (Get-TEsc $TR '2001').result -eq 'failed' -and (Get-TEsc $TR '2007').result -eq 'reassigned' -and @(Get-TCwNotes).Count -eq 5) "$($TR.out.message) | $((Get-TCwNote 2001).text)"
$T2001Notes = @(Get-Calls POST '*/service/tickets/2001/notes' | ForEach-Object { (Read-Body $_).text })
Check '403 on a move: the marker note went first, then a follow-up note gives the plain reason' ($T2001Notes.Count -eq 2 -and $T2001Notes[0].StartsWith('[Auto-Escalation] ') -and $T2001Notes[1] -match "^\[Auto-Escalation: follow-up\] It couldn't be moved to Tier 2 \(ConnectWise refused the change \(HTTP 403\)\. Give the API user permission to update service tickets\.\)\. A technician needs to finish") ($T2001Notes -join ' || ')
$TR = Invoke-Flow $TBody
Check '403 on a move, run again: the ticket is not moved, noted or emailed again' (@(Get-Calls PATCH '*/2001').Count -eq 1 -and @(Get-Calls POST '*/service/tickets/2001/notes').Count -eq 2 -and @(Get-TPostmark).Count -eq 1 -and $TR.out.message -match '^No open tickets need escalating\.') "$($TR.out.message) $(Show-Calls)"
$global:TCw.failPatch = ''

# ---- 8. Notes unreadable: fail closed for that ticket ----
$global:TCw.failNotes = '2001'
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow $TBody
Check 'Unreadable notes: that ticket is skipped (could already be escalated), the rest go ahead' ($TR.out.status -eq 'success' -and $null -eq (Get-TEsc $TR '2001') -and @(Get-Calls PATCH '*/2001').Count -eq 0 -and $TR.out.counts.notesUnreadable -eq 1 -and @($TR.out.warnings) -match 'Skipped ticket 2001') ($TR.out.counts | ConvertTo-Json -Compress)
$global:TCw.failNotes = ''

# ---- 9. Empty result ----
$global:TCw.tickets = @()
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow $TBody
Check 'Empty: success, nothing to escalate, no writes, no email' ($TR.out.status -eq 'success' -and $TR.out.message -match '^No open tickets need escalating\.' -and @(Get-TWrites).Count -eq 0 -and @(Get-TPostmark).Count -eq 0) $TR.out.message
$global:TCw.tickets = $TCwTickets

# ---- 10. Invalid input ----
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow @{ escalation_map = '{not json' }
Check 'Bad escalation_map JSON: rejected before reading the PSA' ($TR.stage -eq 'find' -and $TR.out.status -eq 'rejected' -and $TR.out.message -match "escalation_map isn't valid JSON" -and $Mock.Calls.Count -eq 0) $TR.out.message
$TR = Invoke-Flow @{ escalation_map = '{"Service Desk": {"role": "5"}}' }
Check 'Map entry with no queue or assignee: rejected' ($TR.out.status -eq 'rejected' -and $TR.out.message -match "names no queue and no assignee") $TR.out.message
$TR = Invoke-Flow @{ minutes_untouched_by_priority = '{"high": 0}' }
Check 'Zero minutes: rejected' ($TR.out.status -eq 'rejected' -and $TR.out.message -match 'minutes_untouched_by_priority needs a whole number') $TR.out.message
$TR = Invoke-Flow @{ dispatcher_email = 'dispatch' }
Check 'Bad dispatcher_email: rejected' ($TR.out.status -eq 'rejected' -and $TR.out.message -match "isn't an email address") $TR.out.message

# ---- 11. List-form map with one entry, and a "*" catch-all ----
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow @{ escalation_map = '[{"from":"*","assignee":"dispatch"}]'; preview = 'true' }
Check 'One-item list map with "*": every ticket not actively worked gets assigned to the dispatcher user' ($TR.out.status -eq 'pending_confirmation' -and (Get-TEsc $TR '2002').action -eq 'reassign' -and (Get-TEsc $TR '2002').toAssignee -eq 'dispatch' -and (Get-TEsc $TR '2003').action -eq 'note-only') (($TR.out.escalations | ForEach-Object { "$($_.id)=$($_.action)" }) -join ',')

# ---- 12. Autotask live: queue by picklist label, assignee with the resource's default role ----
$TAtFields = [pscustomobject]@{ fields = @(
        [pscustomobject]@{ name = 'status'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'New'; isActive = $true }, [pscustomobject]@{ value = '5'; label = 'Complete'; isActive = $true }) }
        [pscustomobject]@{ name = 'priority'; picklistValues = @([pscustomobject]@{ value = '4'; label = 'Critical'; isActive = $true }, [pscustomobject]@{ value = '1'; label = 'High'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Medium'; isActive = $true }, [pscustomobject]@{ value = '3'; label = 'Low'; isActive = $true }) }
        [pscustomobject]@{ name = 'queueID'; picklistValues = @([pscustomobject]@{ value = '29683'; label = 'Service Desk'; isActive = $true }, [pscustomobject]@{ value = '29684'; label = 'Tier 2'; isActive = $true }) }
    )
}
$TAtNoteFields = [pscustomobject]@{ fields = @(
        [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) }
        [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }, [pscustomobject]@{ value = '13'; label = 'System Workflow Note'; isActive = $true }) }
    )
}
Reset-Mock -Secrets (Get-TSecrets autotask) -Handler { param($c, $n)
    if ($c.Uri -like 'https://api.postmarkapp.com/email') { return [pscustomobject]@{ ErrorCode = 0 } }
    if ($c.Uri -like '*/Tickets/entityInformation/fields') { return $TAtFields }
    if ($c.Uri -like '*/TicketNotes/entityInformation/fields') { return $TAtNoteFields }
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/Tickets/query?*') { return [pscustomobject]@{ pageDetails = [pscustomobject]@{ nextPageUrl = $null }; items = @([pscustomobject]@{ id = 501; ticketNumber = 'T20261008.0001'; title = 'VPN down'; companyID = 42; status = 1; priority = 1; queueID = 29683; assignedResourceID = 29682885; createDate = (Get-TAgo 300); lastActivityDate = (Get-TAgo 90) }) } }
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/TicketNotes/query?*') { return [pscustomobject]@{ items = @() } }
    if ($c.Uri -like '*/Companies/42') { return [pscustomobject]@{ item = [pscustomobject]@{ companyName = 'Contoso Ltd' } } }
    if ($c.Uri -like '*/Resources/29682885') { return [pscustomobject]@{ item = [pscustomobject]@{ firstName = 'Jordan'; lastName = 'Lee' } } }
    if ($c.Uri -like '*/Resources/29682999') { return [pscustomobject]@{ item = [pscustomobject]@{ id = 29682999; defaultServiceDeskRoleID = 29683461 } } }
    if ($c.Method -eq 'PATCH' -and $c.Uri -like '*/Tickets') { return [pscustomobject]@{ itemId = 501 } }
    if ($c.Method -eq 'POST' -and $c.Uri -like '*/Tickets/501/Notes') { return [pscustomobject]@{ itemId = 1 } }
    throw "unmocked $($c.Method) $($c.Uri)"
}
$TR = Invoke-Flow @{ escalation_map = '{"Service Desk": {"queue": "Tier 2", "assignee": "29682999"}}'; dispatcher_email = 'dispatch@example.com' }
$TP = @(Get-Calls PATCH '*/Tickets')
Check 'AT live: queue moved by label, assignee sent with its default role' ($TR.out.status -eq 'success' -and $TP.Count -eq 2 -and (Read-Body $TP[0]).queueID -eq 29684 -and (Read-Body $TP[1]).assignedResourceID -eq 29682999 -and (Read-Body $TP[1]).assignedResourceRoleID -eq 29683461) "$($TR.error) $(Show-Calls)"
$TNote = Read-Body @(Get-Calls POST '*/Tickets/501/Notes')[0]
Check 'AT live: internal note (Internal Only publish) with the marker; dispatcher emailed' ($TNote.publish -eq 2 -and $TNote.title -eq 'Auto-Escalation' -and $TNote.description.StartsWith('[Auto-Escalation] ') -and @(Get-TPostmark).Count -eq 1) ($TNote | ConvertTo-Json -Compress)

# ---- 13. Zendesk live: group by name ----
Reset-Mock -Secrets (Get-TSecrets zendesk) -Handler { param($c, $n)
    if ($c.Uri -like 'https://api.postmarkapp.com/email') { return [pscustomobject]@{ ErrorCode = 0 } }
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/search?*') { return [pscustomobject]@{ next_page = $null; results = @([pscustomobject]@{ id = 3001; subject = 'Cannot log in'; organization_id = 61; status = 'open'; priority = 'urgent'; group_id = 21; assignee_id = $null; created_at = (Get-TAgo 60); updated_at = (Get-TAgo 45); slas = [pscustomobject]@{ policy_metrics = @() } }) } }
    if ($c.Uri -like '*/tickets/3001/comments*') { return [pscustomobject]@{ comments = @([pscustomobject]@{ body = 'Help'; public = $true; created_at = (Get-TAgo 60) }) } }
    if ($c.Uri -like '*/organizations/61') { return [pscustomobject]@{ organization = [pscustomobject]@{ name = 'Contoso Ltd' } } }
    if ($c.Uri -like '*/groups/21') { return [pscustomobject]@{ group = [pscustomobject]@{ name = 'Service Desk' } } }
    if ($c.Uri -like '*/groups?*') { return [pscustomobject]@{ groups = @([pscustomobject]@{ id = 21; name = 'Service Desk' }, [pscustomobject]@{ id = 22; name = 'Tier 2' }) } }
    if ($c.Method -eq 'PUT' -and $c.Uri -like '*/tickets/3001') { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 3001 } } }
    throw "unmocked $($c.Method) $($c.Uri)"
}
$TR = Invoke-Flow $TBody
$TPut = @(Get-Calls PUT '*/tickets/3001')
Check 'Zendesk live: a private comment with the marker, then the group moved by name' ($TR.out.status -eq 'success' -and $TPut.Count -eq 2 -and (Read-Body $TPut[0]).ticket.comment.public -eq $false -and (Read-Body $TPut[0]).ticket.comment.body.StartsWith('[Auto-Escalation] ') -and (Read-Body $TPut[1]).ticket.group_id -eq 22) "$($TR.error) $(Show-Calls)"

# ---- 14. Retry safety: a rerun writes nothing twice, moves nothing twice and emails nothing twice ----
# The mock returns the notes this test has POSTed, as the PSA would, but never changes a ticket's board,
# so without the marker check a rerun would move 2001 and 2007 again (Tier 2 to Tier 3, and so on).
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TR = Invoke-Flow $TBody
$TBefore = @{ patch = @(Get-Calls PATCH '*').Count; notes = @(Get-TCwNotes).Count; pm = @(Get-TPostmark).Count }
$TR = Invoke-Flow $TBody
Check 'Rerun (Action Runs Retry or the next Routine): no move, note or email the second time' ($TBefore.patch -eq 3 -and $TBefore.notes -eq 4 -and $TBefore.pm -eq 1 -and @(Get-Calls PATCH '*').Count -eq 3 -and @(Get-TCwNotes).Count -eq 4 -and @(Get-TPostmark).Count -eq 1 -and $TR.out.counts.alreadyEscalated -eq 5) "$($TBefore | ConvertTo-Json -Compress) $($TR.out.message)"

# The run stopped after step 2 (notes written, tickets moved) and is retried from the start.
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TS = Invoke-Step 'find' ($TBody | ConvertTo-Json | ConvertFrom-Json)
$TS = Invoke-Step 'reassign' $TS.out
$TR = Invoke-Flow $TBody
Check 'Retry after a run stopped mid-way: the moved tickets are not moved or noted again' (@(Get-Calls PATCH '*').Count -eq 3 -and @(Get-TCwNotes).Count -eq 4 -and @(Get-TPostmark).Count -eq 0 -and $TR.out.message -match '^No open tickets need escalating\.') "$($TR.out.message) $(Show-Calls)"

# Two runs overlap: both plan before either writes, so only the check inside Add-PsaNote -Marker stands between them.
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler $TCwHandler
$TA = (Invoke-Step 'find' ($TBody | ConvertTo-Json | ConvertFrom-Json)).out
$TB = (Invoke-Step 'find' ($TBody | ConvertTo-Json | ConvertFrom-Json)).out
$TA = (Invoke-Step 'note' (Invoke-Step 'notify' (Invoke-Step 'reassign' $TA).out).out).out
$TPatchA = @(Get-Calls PATCH '*').Count; $TNotesA = @(Get-TCwNotes).Count
$TB2 = (Invoke-Step 'reassign' $TB).out
$TB = (Invoke-Step 'note' (Invoke-Step 'notify' $TB2).out).out
Check 'Overlapping runs: the second finds the marker just before writing and moves, notes and emails nothing' ($TPatchA -eq 3 -and @(Get-Calls PATCH '*').Count -eq 3 -and @(Get-TCwNotes).Count -eq $TNotesA -and @(Get-TPostmark).Count -eq 1 -and -not @($TB2.escalations | Where-Object { $_.result -ne 'already-escalated' }).Count) "$($TB.message) $(Show-Calls)"
Check 'Overlapping runs: the second run says so in plain words' ($TB.status -eq 'success' -and $TB.message -match '^Nothing new was escalated\. 4 tickets were already escalated by another run and left alone\.') $TB.message

# The marker note can't be written: fail closed, the ticket isn't moved.
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler { param($c, $n)
    if ($c.Method -eq 'POST' -and $c.Uri -like '*/service/tickets/2001/notes') { New-HttpError 403 '{"message":"denied"}' }
    $TRes = & $TCwHandler $c $n; if ($TRes -is [array]) { return , $TRes }; return $TRes
}
$TR = Invoke-Flow $TBody
Check 'Marker note refused (403): 2001 is not moved, the run is incomplete and says why' ($TR.out.status -eq 'incomplete' -and @(Get-Calls PATCH '*/2001').Count -eq 0 -and @(Get-Calls PATCH '*/2007').Count -eq 2 -and (Get-TEsc $TR '2001').error -match 'permission to add ticket notes' -and $TR.out.message -match '1 escalation note could not be added, so that ticket was not moved') "$($TR.out.message) | $((Get-TEsc $TR '2001') | ConvertTo-Json -Compress)"

# ---- 15. A warning from _shared/psa.ps1 reaches the output ----
# ConnectWise saves the escalation note on 2001, then answers the POST with an insecure redirect (what staging
# did). Add-PsaNote reads the ticket back, finds the note and records a warning in $PsaState.Warnings; the run's
# warnings must carry it, once, through the notify and note steps.
Reset-Mock -Secrets (Get-TSecrets connectwise) -Handler { param($c, $n)
    if ($c.Method -eq 'POST' -and $c.Uri -like '*/service/tickets/2001/notes') {
        $TEr = [System.Management.Automation.ErrorRecord]::new([System.InvalidOperationException]::new(), 'InsecureRedirection,Microsoft.PowerShell.Commands.InvokeRestMethodCommand', 'InvalidOperation', $null); $TEr.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('Cannot follow an insecure redirection by default. Reissue the command specifying the -AllowInsecureRedirect switch.'); throw $TEr
    }
    $TRes = & $TCwHandler $c $n; if ($TRes -is [array]) { return , $TRes }; return $TRes
}
$TR = Invoke-Flow $TBody
$TWant = 'ConnectWise answered the note on ticket 2001 with a redirect; reading the ticket back showed the note was saved, so it was not sent again.'
Check 'Shared warning: the redirected note on 2001 was saved, sent once, and 2001 still moved' ($TR.out.status -eq 'success' -and @(Get-Calls POST '*/service/tickets/2001/notes').Count -eq 1 -and @(Get-Calls PATCH '*/2001').Count -eq 1) "$($TR.error) $(Show-Calls)"
Check 'Shared warning: $PsaState.Warnings reaches the run output warnings, once' (@($TR.out.warnings | Where-Object { $_ -eq $TWant }).Count -eq 1) ($TR.out.warnings -join ' | ')

Complete-Test
