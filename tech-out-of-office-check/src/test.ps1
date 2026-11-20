# Strict-mode harness for Out-of-Office Check (ConnectWise).
# Runs each PowerShell step exactly as it is in tech-out-of-office-check.yml (shared libraries included),
# through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the runner Key Vault,
# Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked.
# Placeholder data only (Contoso, Example MSP). Test variables start with T (see vip-ticket-alert/src/test.ps1).
# Usage: pwsh -NoProfile -File tech-out-of-office-check/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\tech-out-of-office-check.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.type==='powershell-script')o[a.id]=a.properties.script;if(a.id==='check')o['check.params']=JSON.stringify(a.properties.parameters)}console.log(JSON.stringify(o));"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow has check and act steps' ($Steps.Contains('check') -and $Steps.Contains('act'))
Check 'check step is bound to the trigger output' ($Steps['check.params'] -like '*{{ nodes.trigger.output }}*')

# ---- runner mocks ----
$global:NodeIn = $null; $global:NodeOut = $null
function Get-NodeInput { return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Invoke-Step {
    param([string]$Id, $In = $null)
    $global:NodeIn = $In; $global:NodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps[$Id])) } catch { $err = [string]$_.Exception.Message }
    $o = $null; if ($null -ne $global:NodeOut) { $o = ($global:NodeOut | ConvertTo-Json -Depth 12 | ConvertFrom-Json) }
    return @{ out = $o; error = $err }
}
function Invoke-Flow {
    param($Body)
    $c = Invoke-Step 'check' ([pscustomobject]@{ trigger = ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json) })
    if ($c.error) { return @{ stage = 'check'; r = $c } }
    $s = Invoke-Step 'act' $c.out
    return @{ stage = 'act'; r = $s; check = $c.out }
}

# ---- placeholder data ----
$TCW = 'https://api-na.example.com/v4_6_release/apis/3.0'
$TPM = 'https://api.postmarkapp.com/email'
$TFlow = 'https://prod-00.westus.logic.example/workflows/abc/triggers/manual/paths/invoke'
$TNow = '2026-10-13T20:00:00Z'
function New-TSecrets { param([hashtable]$Extra = @{}) $s = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = "$TCW"; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid'; 'Postmark-ServerToken' = 'pm'; 'Postmark-FromEmail' = 'alerts@examplemsp.example'; 'OOO-DispatchTo' = 'dispatch@examplemsp.example' }; foreach ($k in $Extra.Keys) { $s[$k] = $Extra[$k] }; return $s }
$TS = @{}
function Reset-TScenario {
    $TS.owner = 'jsmith'; $TS.resources = 'jsmith'; $TS.notes = @(); $TS.board = @{}; $TS.sched = @{}
    $TS.members = @{ jsmith = @{ inactiveFlag = $false }; backup = @{ inactiveFlag = $false } }; $TS.flowFail = $false; $TS.acts = @(); $TS.actById = @{}
    $TS.teamId = 3; $TS.team = @(@{ id = 10; identifier = 'jsmith'; inactiveFlag = $false }, @{ id = 11; identifier = 'backup'; inactiveFlag = $false }, @{ id = 12; identifier = 'alee'; inactiveFlag = $false })
    $TS.open = @{ backup = 5; alee = 2 }; $TS.entries = @{ jsmith = @([pscustomobject]@{ id = 801; objectId = 1001; type = [pscustomobject]@{ identifier = 'S' } }) }; $TS.teamFail = $false
}
function Get-TTeamRecs { return , @($TS.team | ForEach-Object { [pscustomobject]$_ }) }
function New-TBoard { param([string]$Type, [string]$Back, [string]$Info = '') return [pscustomobject]@{ id = 1; member = [pscustomobject]@{ identifier = 'x' }; inOutType = [pscustomobject]@{ id = 2; name = $Type }; dateBack = $Back; additionalInfo = $Info } }
function New-TSched { param([string]$Type, [string]$Name, [string]$Start, [string]$End) return [pscustomobject]@{ id = 5; name = $Name; type = [pscustomobject]@{ id = 3; name = $Type }; dateStart = $Start; dateEnd = $End } }
function Get-TMember { param([string]$Uri) $u = [uri]::UnescapeDataString($Uri); if ($u -match '(?:member|owner|assignTo)/identifier="([^"]+)"') { return $Matches[1] }; if ($u -match 'identifier="([^"]+)"') { return $Matches[1] }; return '' }

$Handler = {
    param($c, $n)
    $k = "$($c.Method) $($c.Uri)"
    switch -Wildcard -CaseSensitive ($k) {
        "POST $TPM" { return [pscustomobject]@{ MessageID = 'pm-1'; ErrorCode = 0 } }
        "POST $TFlow" { if ($TS.flowFail) { New-HttpError 500 'flow down' }; return [pscustomobject]@{ ok = $true } }
        "GET $TCW/service/tickets/1001/notes*" { return , @($TS.notes) }
        "GET $TCW/service/tickets/1001" { $o = if ($TS.owner) { [pscustomobject]@{ id = 7; identifier = $TS.owner } } else { $null }; return [pscustomobject]@{ id = 1001; summary = 'Printer offline'; company = [pscustomobject]@{ id = 42; name = 'Contoso' }; board = [pscustomobject]@{ id = 14; name = 'Service Desk' }; team = $(if ($TS.teamId) { [pscustomobject]@{ id = $TS.teamId; name = 'Tier 1' } } else { $null }); owner = $o; resources = $TS.resources } }
        "POST $TCW/service/tickets/1001/notes" { return [pscustomobject]@{ id = 9001 } }
        "PATCH $TCW/service/tickets/1001" { return [pscustomobject]@{ id = 1001 } }
        "GET $TCW/system/inOutBoards*" { $m = Get-TMember $c.Uri; if ($TS.board.ContainsKey($m)) { return , @($TS.board[$m]) }; return , @() }
        "GET $TCW/schedule/entries?conditions=objectId*" { $m = Get-TMember $c.Uri; if ($TS.entries.ContainsKey($m)) { return , @($TS.entries[$m]) }; return , @() }
        "PATCH $TCW/schedule/entries/*" { return [pscustomobject]@{ id = 801 } }
        "GET $TCW/service/boards/14/teams/3" { if ($TS.teamFail) { New-HttpError 403 '{"message":"no access"}' }; return [pscustomobject]@{ id = 3; name = 'Tier 1'; members = @($TS.team | ForEach-Object { $_.id }) } }
        "GET $TCW/service/boards/14/teams?*" { if ($TS.teamFail) { New-HttpError 403 '{"message":"no access"}' }; return , @([pscustomobject]@{ id = 3; members = @($TS.team | ForEach-Object { $_.id }) }) }
        "GET $TCW/service/tickets/count*" { $u = [uri]::UnescapeDataString($c.Uri); $m = if ($u -match 'identifier="([^"]+)"') { $Matches[1] } else { '' }; $n = if ($TS.open.ContainsKey($m)) { $TS.open[$m] } else { 0 }; return [pscustomobject]@{ count = $n } }
        "GET $TCW/system/members?conditions=id%20in*" { return (Get-TTeamRecs) }
        "GET $TCW/schedule/entries*" { $m = Get-TMember $c.Uri; if ($TS.sched.ContainsKey($m)) { return , @($TS.sched[$m]) }; return , @() }
        "GET $TCW/sales/activities/*" { $aid = ($c.Uri -split '/')[-1]; if ($TS.actById.ContainsKey($aid)) { return $TS.actById[$aid] }; New-HttpError 404 '{}' }
        "GET $TCW/sales/activities*" { return , @($TS.acts) }
        "GET $TCW/system/members/303" { return [pscustomobject]@{ id = 303; identifier = 'pdoe'; inactiveFlag = $false } }
        "GET $TCW/system/members/999" { New-HttpError 404 '{"message":"not found"}' }
        "GET $TCW/system/members*" { $m = Get-TMember $c.Uri; if ($TS.members.ContainsKey($m)) { return , @([pscustomobject]@{ id = 11; identifier = $m; inactiveFlag = $TS.members[$m].inactiveFlag }) }; return , @() }
    }
    throw "Unexpected call in test: $k"
}
function Get-Writes { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' }) }

# 1. Owner out on the In/Out Board, live mode off: preview, nothing written.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z' 'Dentist')
Reset-Mock (New-TSecrets) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'preview: status pending_confirmation' ($f.r.out.status -eq 'pending_confirmation') ($f.r.out | ConvertTo-Json -Depth 6)
Check 'preview: nothing written or sent' (@(Get-Writes).Count -eq 0) (Show-Calls)
Check 'preview: note names the In/Out Board and Date Back' ($f.r.out.internal_note -like '*In/Out Board: Out of Office until Wed 10/14 4:00 PM UTC (Dentist)*') $f.r.out.internal_note
Check 'schedule query is limited to entries covering now' (@(Get-Calls 'GET' "$TCW/schedule/entries*" | Where-Object { [uri]::UnescapeDataString($_.Uri) -like '*"jsmith" and dateStart<=`[2026-10-13T20:00:00Z`] and dateEnd>`[2026-10-13T20:00:00Z`]*' }).Count -eq 1) (Show-Calls)

# 1b. Times in the dispatcher's time zone, and an unknown zone falls back to UTC with a warning.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Gone for the day' '10/15/2026 05:00:00')
Reset-Mock (New-TSecrets @{ 'OOO-TimeZone' = 'America/Chicago' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'time zone: Central shown' ($f.r.out.internal_note -like '*Gone for the day until Thu 10/15 12:00 AM Central*') $f.r.out.internal_note
Check 'time zone: short US zone in the email text' ($f.r.out.alert_text -like '*Gone for the day (In/Out Board), until Thu 10/15 12:00 AM CDT*') $f.r.out.alert_text
Check 'time zone: back stays UTC' ((([datetime]@($f.r.out.out_members)[0].back).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm')) -eq '2026-10-15T05:00') (@($f.r.out.out_members)[0].back)
Reset-Mock (New-TSecrets @{ 'OOO-TimeZone' = 'Mars/Olympus' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'unknown time zone: UTC with a warning' ($f.r.out.internal_note -like '*until Thu 10/15 5:00 AM UTC*' -and (@($f.r.out.warnings) -join ' ') -like "*isn't known on this runner*") ($f.r.out | ConvertTo-Json -Depth 6)

# 2. In Office record with a future Date Back counts as in; a past Date Back too.
Reset-TScenario; $TS.board['jsmith'] = @((New-TBoard 'In Office' '2026-10-20T16:00:00Z'), (New-TBoard 'Out of Office' '2026-10-12T16:00:00Z'))
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'in: success and nothing changed' ($f.r.out.status -eq 'success' -and $f.r.out.changed -eq $false -and @(Get-Writes).Count -eq 0) ($f.r.out | ConvertTo-Json -Depth 6)
Check 'in: evidence explains each record' ((@(@($f.r.out.evidence)[0].evidence) -join ' ') -like "*type 'In Office'*Counted as in*Not counted: Date Back is not after*") ($f.r.out.evidence | ConvertTo-Json -Depth 6)
Check 'in: message says everyone is in' ($f.r.out.message -like '*is in, so nothing was changed*') $f.r.out.message

# 3. Out of Office schedule entry, live, flag: note with marker, email, no PATCH.
Reset-TScenario; $TS.sched['jsmith'] = @(New-TSched 'Out of Office' 'Wellness' '2026-10-13T18:00:00Z' '2026-10-13T22:00:00Z')
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes'; 'OOO-WhenOut' = 'flag' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
$note = Read-Body (@(Get-Calls 'POST' "$TCW/service/tickets/1001/notes")[0])
Check 'flag: success' ($f.r.out.status -eq 'success' -and $f.r.out.plan -eq 'flag') ($f.r.out | ConvertTo-Json -Depth 6)
Check 'flag: internal note with the [ooo-check] marker' ($null -ne $note -and $note.internalAnalysisFlag -eq $true -and $note.text.Contains('[ooo-check]') -and $note.text -like '*Schedule: Out of Office*until Tue 10/13 10:00 PM UTC*') ($note | ConvertTo-Json)
Check 'flag: dispatcher emailed' (@(Get-Calls 'POST' $TPM).Count -eq 1)
Check 'flag: assignment untouched' (@(Get-Calls 'PATCH' "$TCW/service/tickets/1001").Count -eq 0)

# 3a. An Activity on the calendar: schedule type 'C', matched by its activity type name.
Reset-TScenario; $TS.sched['jsmith'] = @([pscustomobject]@{ id = 3474; objectId = 1046; name = 'Dentist'; type = [pscustomobject]@{ id = 2; identifier = 'C' }; dateStart = '2026-10-13T17:00:00Z'; dateEnd = '2026-10-13T23:00:00Z' })
$TS.actById = @{ '1046' = [pscustomobject]@{ id = 1046; type = [pscustomobject]@{ name = 'Out of Office' } } }
Reset-Mock (New-TSecrets) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'activity entry: out by activity type' ($f.r.out.status -eq 'pending_confirmation' -and (@(@($f.r.out.out_members)[0].reasons) -join ' ') -like '*Activity: Out of Office*') ($f.r.out | ConvertTo-Json -Depth 6)

# 3b. Default is reassign to the ticket's team: the in member with the fewest open tickets, and the out owner's
#     schedule entry on the ticket moves to them.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z')
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
$p = Read-Body (@(Get-Calls 'PATCH' "$TCW/service/tickets/1001")[0])
$se = Read-Body (@(Get-Calls 'PATCH' "$TCW/schedule/entries/801")[0])
Check 'default: reassign to fewest open (alee)' ($f.r.out.status -eq 'success' -and $f.r.out.plan -eq 'reassign' -and $f.r.out.replacement -eq 'alee' -and @($p)[0].op -eq 'replace' -and @($p)[0].value.identifier -eq 'alee') ($f.r.out | ConvertTo-Json -Depth 6)
Check 'default: team read from the ticket''s team' (@(Get-Calls 'GET' "$TCW/service/boards/14/teams/3").Count -eq 1) (Show-Calls)
Check 'default: schedule entry moved to alee' (@($se)[0].path -eq 'member' -and @($se)[0].value.identifier -eq 'alee') ($se | ConvertTo-Json -Depth 5)
Check 'default: note says who and why' ($f.r.out.internal_note -like '*reassigned from jsmith to alee, who is in (from the ticket''s team, fewest open tickets (2))*') $f.r.out.internal_note
$mail = Read-Body (@(Get-Calls 'POST' $TPM)[0]); if ($env:SHOWMAIL) { Write-Host "SUBJECT: $($mail.Subject)"; Write-Host $mail.TextBody; Set-Content -Path "$env:SHOWMAIL/mail-$(@(Get-ChildItem $env:SHOWMAIL).Count).html" -Value $mail.HtmlBody }
Check 'email: subject names the outcome' ($mail.Subject -eq 'Ticket 1001 reassigned to alee: jsmith is out') ($mail | ConvertTo-Json)
Check 'email: text has headline, details, why and what to do on separate lines' ($mail.TextBody -like "Ticket 1001 was reassigned from jsmith to alee because jsmith is out.*`nTicket: #1001 Printer offline`nCompany: Contoso`nBoard: Service Desk*Why jsmith is out:`n  - Out of Office (In/Out Board), until Wed 10/14 4:00 PM UTC*What to do: Nothing, unless alee*") $mail.TextBody
Check 'email: HTML body sent' ($mail.HtmlBody -like '*<b>Ticket 1001 was reassigned from jsmith to alee*<li>Out of Office <span*(In/Out Board)</span>, until <b>Wed 10/14 4:00 PM UTC</b></li>*What to do*') $mail.HtmlBody
Check 'default: out owner never considered' (-not ((@($f.r.out.considered) -join ' ') -like '*jsmith*')) ($f.r.out.considered | ConvertTo-Json)

# 3d. The least-loaded member is out too: the next one is picked. No team on the ticket: all board teams.
Reset-TScenario; $TS.teamId = $null; $TS.open = @{ backup = 1; alee = 0 }; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z'); $TS.board['alee'] = @(New-TBoard 'Vacation' '2026-10-17T16:00:00Z')
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'next in: alee out skipped, backup picked, singular count' ($f.r.out.replacement -eq 'backup' -and (@($f.r.out.considered) -join ' ') -like '*alee (0 open tickets): out*backup (1 open ticket): in. Picked.*' -and @(Get-Calls 'GET' "$TCW/service/boards/14/teams?*").Count -eq 1) ($f.r.out | ConvertTo-Json -Depth 6)

# 3e. Nobody on the team is in: left with the owner (never unassigned), flagged, dispatcher told.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z'); $TS.board['alee'] = @(New-TBoard 'Vacation' '2026-10-17T16:00:00Z'); $TS.board['backup'] = @(New-TBoard 'Sick' '2026-10-14T16:00:00Z')
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'nobody in: flag, no PATCH, email sent' ($f.r.out.plan -eq 'flag' -and @(Get-Calls 'PATCH' "$TCW/service/tickets/1001").Count -eq 0 -and @(Get-Calls 'POST' $TPM).Count -eq 1 -and $f.r.out.internal_note -like '*left with jsmith for the dispatcher*') ($f.r.out | ConvertTo-Json -Depth 6)

# 3f. Team can't be read (403): flagged with a hint, not an error.
Reset-TScenario; $TS.teamFail = $true; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z')
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'team 403: flag with a hint' ($f.r.out.status -eq 'success' -and $f.r.out.plan -eq 'flag' -and (@($f.r.out.warnings) -join ' ') -like '*service board teams*OOO-BackupPool*') ($f.r.out | ConvertTo-Json -Depth 6)

# 3g. Preview shows who it would pick and writes nothing.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z')
Reset-Mock (New-TSecrets) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'preview: names the replacement, no writes' ($f.r.out.status -eq 'pending_confirmation' -and $f.r.out.replacement -eq 'alee' -and @(Get-Writes).Count -eq 0) ($f.r.out | ConvertTo-Json -Depth 6)
Check 'preview: email text says would' ($f.r.out.subject -like 'Preview: Ticket 1001 reassigned to alee*' -and $f.r.out.alert_text -like 'Ticket 1001 would be reassigned from jsmith to alee*') ($f.r.out | ConvertTo-Json -Depth 6)
Check 'preview: says would, not was' ($f.r.out.internal_note -like '*would be reassigned from jsmith to alee*' -and $f.r.out.internal_note -notlike '*was reassigned*' -and $f.r.out.message -like '*It would go to alee*') ($f.r.out | ConvertTo-Json -Depth 6)
Check 'considered: every candidate with a count' ((@($f.r.out.considered) -join ' ') -like '*alee (2 open tickets): in. Picked.*backup (5 open tickets): not picked, more open tickets than alee.*') ($f.r.out.considered | ConvertTo-Json)

# 3h. Schedule entry move refused: still success (owner changed) with a warning.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z')
$TNoSched = { param($c, $n) if ($c.Method -eq 'PATCH' -and $c.Uri -like '*/schedule/entries/*') { New-HttpError 403 '{"message":"denied"}' }; & $Handler $c $n }
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes' }) $TNoSched
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'entry move refused: success with warning' ($f.r.out.status -eq 'success' -and $f.r.out.changed -eq $true -and (@($f.r.out.warnings) -join ' ') -like '*Schedule entry 801 still has jsmith*') ($f.r.out | ConvertTo-Json -Depth 6)

# 3c. Nothing covering now: nearby entries and activities show up in evidence only.
Reset-TScenario; $TS.acts = @([pscustomobject]@{ id = 77; name = 'Out of Office'; type = [pscustomobject]@{ name = 'Out of Office' }; dateStart = '2026-10-13T19:00:00Z'; dateEnd = '2026-10-13T23:00:00Z' })
Reset-Mock (New-TSecrets) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'diagnostics: activity listed, not counted' ($f.r.out.status -eq 'success' -and (@(@($f.r.out.evidence)[0].evidence) -join ' ') -like "*Activity 77 (activities are not checked)*") ($f.r.out.evidence | ConvertTo-Json -Depth 6)

# 4. Unassign.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z')
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes'; 'OOO-WhenOut' = 'unassign' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
$p = Read-Body (@(Get-Calls 'PATCH' "$TCW/service/tickets/1001")[0])
Check 'unassign: owner removed' ($f.r.out.changed -eq $true -and @($p)[0].op -eq 'remove' -and @($p)[0].path -eq 'owner') ($p | ConvertTo-Json)

# 4b. Unassign refused (403): falls back to a flag, note and email still go out, status incomplete.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z')
$TDeny = { param($c, $n) if ($c.Method -eq 'PATCH') { New-HttpError 403 '{"code":"Security","message":"You do not have security permission to perform this action."}' }; & $Handler $c $n }
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes'; 'OOO-WhenOut' = 'unassign' }) $TDeny
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
$note = Read-Body (@(Get-Calls 'POST' "$TCW/service/tickets/1001/notes")[0])
$mail = Read-Body (@(Get-Calls 'POST' $TPM)[0]); if ($env:SHOWMAIL) { Write-Host "SUBJECT: $($mail.Subject)"; Write-Host $mail.TextBody; Set-Content -Path "$env:SHOWMAIL/mail-$(@(Get-ChildItem $env:SHOWMAIL).Count).html" -Value $mail.HtmlBody }
Check 'unassign refused: email says action needed' ($mail.Subject -eq 'Action needed: ticket 1001 is assigned to jsmith, who is out' -and $mail.TextBody -like '*tried to remove jsmith as owner, but ConnectWise refused*What to do: Remove the owner by hand.*') ($mail | ConvertTo-Json)
Check 'unassign refused: incomplete, note and email still sent' ($f.r.out.status -eq 'incomplete' -and $f.r.out.plan -eq 'flag' -and $null -ne $note -and $note.text -like '*ConnectWise refused*' -and @(Get-Calls 'POST' $TPM).Count -eq 1 -and (@($f.r.out.warnings) -join ' ') -like '*Service Tickets: Edit*') ($f.r.out | ConvertTo-Json -Depth 6)

# 5. Reassign to an active backup who is in (OOO-BackupMember still works as a one-member pool).
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z')
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes'; 'OOO-WhenOut' = 'reassign'; 'OOO-BackupMember' = 'backup' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
$p = Read-Body (@(Get-Calls 'PATCH' "$TCW/service/tickets/1001")[0])
Check 'reassign: backup made owner' ($f.r.out.plan -eq 'reassign' -and @($p)[0].path -eq 'owner' -and @($p)[0].value.identifier -eq 'backup') ($p | ConvertTo-Json -Depth 5)

# 6. Reassign when the backup is out too: flagged instead.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z'); $TS.board['backup'] = @(New-TBoard 'Vacation' '2026-10-17T16:00:00Z')
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes'; 'OOO-WhenOut' = 'reassign'; 'OOO-BackupMember' = 'backup' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'backup out: flagged, no PATCH, warning' ($f.r.out.plan -eq 'flag' -and @(Get-Calls 'PATCH' "$TCW/service/tickets/1001").Count -eq 0 -and (@($f.r.out.warnings) -join ' ') -like '*backup (5 open tickets): out*' -and @(Get-Calls 'GET' "$TCW/service/boards/*").Count -eq 0) ($f.r.out | ConvertTo-Json -Depth 6)

# 7. Inactive backup: flagged instead.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z'); $TS.members.backup.inactiveFlag = $true
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes'; 'OOO-WhenOut' = 'reassign'; 'OOO-BackupMember' = 'backup' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'inactive backup: flagged with a warning' ($f.r.out.plan -eq 'flag' -and (@($f.r.out.warnings) -join ' ') -like '*inactive*') ($f.r.out | ConvertTo-Json -Depth 6)

# 8. Resource-only member out with unassign: left alone with a warning.
Reset-TScenario; $TS.owner = 'backup'; $TS.resources = 'backup, jsmith'; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z')
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes'; 'OOO-WhenOut' = 'unassign' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'resource only: no PATCH, warning, note written' (@(Get-Calls 'PATCH' "$TCW/service/tickets/1001").Count -eq 0 -and (@($f.r.out.warnings) -join ' ') -like '*resources list*' -and @(Get-Calls 'POST' "$TCW/service/tickets/1001/notes").Count -eq 1) ($f.r.out | ConvertTo-Json -Depth 6)

# 9. The member the Action names is checked even when the ticket has no owner yet.
Reset-TScenario; $TS.owner = ''; $TS.resources = ''; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z')
Reset-Mock (New-TSecrets) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; member = 'jsmith'; now = $TNow }
Check 'action member: found out, no-owner warning' ($f.r.out.status -eq 'pending_confirmation' -and @($f.r.out.out_members)[0].identifier -eq 'jsmith' -and (@($f.r.out.warnings) -join ' ') -like '*no owner saved*' -and $f.r.out.internal_note -like '*no owner saved yet*') ($f.r.out | ConvertTo-Json -Depth 6)

# 9b. A Member # (record id) is looked up and checked by identifier.
Reset-TScenario; $TS.owner = ''; $TS.resources = ''; $TS.board['pdoe'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z')
Reset-Mock (New-TSecrets) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; member = '303'; now = $TNow }
Check 'member #303: resolved to pdoe and found out' ($f.r.out.status -eq 'pending_confirmation' -and @($f.r.out.out_members)[0].identifier -eq 'pdoe') ($f.r.out | ConvertTo-Json -Depth 6)
Reset-Mock (New-TSecrets) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; member = '999'; now = $TNow }
Check 'unknown member #: error naming it' ($f.r.out.status -eq 'error' -and $f.r.out.message -like '*no member #999*') ($f.r.out | ConvertTo-Json -Depth 6)

# 9c. The ticket already has an owner who is in: the member the Action names (out) is ignored, nothing is sent.
Reset-TScenario; $TS.owner = 'backup'; $TS.resources = 'backup'; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z')
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; member = 'jsmith'; now = $TNow }
Check 'owner set: stray member ignored, nothing written' ($f.r.out.status -eq 'success' -and @(Get-Writes).Count -eq 0 -and $f.r.out.message -like '*(backup) is in*' -and (@($f.r.out.actions) -join ' ') -like "*Ignored member 'jsmith'*") ($f.r.out | ConvertTo-Json -Depth 6)

# 10. Nobody assigned.
Reset-TScenario; $TS.owner = ''; $TS.resources = ''
Reset-Mock (New-TSecrets) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'unassigned ticket: success, no availability reads' ($f.r.out.status -eq 'success' -and @(Get-Calls 'GET' "$TCW/system/inOutBoards*").Count -eq 0) ($f.r.out | ConvertTo-Json -Depth 6)

# 11. Already handled: the marker stops a second run.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z'); $TS.notes = @([pscustomobject]@{ id = 1; text = "Out-of-office check: earlier`n[ooo-check]"; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false; dateCreated = '2026-10-13T19:00:00Z' })
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'already handled: success, nothing written' ($f.r.out.status -eq 'success' -and @(Get-Writes).Count -eq 0 -and $f.r.out.message -like '*already handled*') ($f.r.out | ConvertTo-Json -Depth 6)

# 12. confirm false overrides live mode; confirm true overrides it off.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z')
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow; confirm = 'false' }
Check 'confirm false: preview even in live mode' ($f.r.out.status -eq 'pending_confirmation' -and @(Get-Writes).Count -eq 0)
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z')
Reset-Mock (New-TSecrets) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow; confirm = 'true' }
Check 'confirm true: writes with live mode off' ($f.r.out.status -eq 'success' -and @(Get-Calls 'POST' "$TCW/service/tickets/1001/notes").Count -eq 1)

# 13. Teams flow posts; a failing flow is a warning, not an error.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z')
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes'; 'OOO-TeamsFlowUrl' = $TFlow }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'teams: posted' (@(Get-Calls 'POST' $TFlow).Count -eq 1 -and $f.r.out.internal_note -like '*email to dispatch@examplemsp.example and Teams*') $f.r.out.internal_note
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z'); $TS.flowFail = $true
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes'; 'OOO-TeamsFlowUrl' = $TFlow }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'teams down: success with a warning' ($f.r.out.status -eq 'success' -and (@($f.r.out.warnings) -join ' ') -like '*Teams alert was not posted*') ($f.r.out | ConvertTo-Json -Depth 6)

# 14. Guard rails.
Reset-TScenario; Reset-Mock (New-TSecrets @{ 'PSA-Type' = 'autotask' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'not ConnectWise: rejected' ($f.stage -eq 'check' -and $f.r.out.status -eq 'rejected') ($f.r | ConvertTo-Json -Depth 6)
Reset-Mock (New-TSecrets @{ 'OOO-PickBy' = 'random' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'bad pick_by: rejected' ($f.r.out.status -eq 'rejected' -and $f.r.out.message -like '*fewest-open, least-recent or list-order*') ($f.r.out | ConvertTo-Json -Depth 6)
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z')
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes'; 'OOO-BackupPool' = 'nobody, backup' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'backup pool: unknown member noted, next one picked' ($f.r.out.replacement -eq 'backup' -and (@($f.r.out.considered) -join ' ') -like "*'nobody' isn't a ConnectWise member*") ($f.r.out | ConvertTo-Json -Depth 6)
Reset-Mock (New-TSecrets @{ 'OOO-WhenOut' = 'delete' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'bad when_out: rejected' ($f.r.out.status -eq 'rejected')

# 15. A ConnectWise read failure is an error with a plain message.
Reset-TScenario
$TBad = { param($c, $n) if ($c.Uri -like '*/service/tickets/1001') { New-HttpError 403 '{"message":"no access"}' }; & $Handler $c $n }
Reset-Mock (New-TSecrets) $TBad
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'ticket read 403: error naming the permission' ($f.r.out.status -eq 'error' -and $f.r.out.message -like '*HTTP 403*') ($f.r.out | ConvertTo-Json -Depth 6)

# ---- pick methods ----
# 16. least-recent: the one whose newest assigned ticket is oldest wins, even with more open tickets.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z'); $TS.last = @{ alee = '2026-10-13T19:00:00Z'; backup = '2026-10-01T10:00:00Z' }
$TLast = { param($c, $n) $u = [uri]::UnescapeDataString($c.Uri); if ($c.Method -eq 'GET' -and $u -like "$TCW/service/tickets?conditions=*orderBy=dateEntered desc*") { $m = Get-TMember $c.Uri; if ($TS.last.ContainsKey($m)) { return , @([pscustomobject]@{ id = 9; dateEntered = $TS.last[$m] }) }; return , @() }; & $Handler $c $n }
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes'; 'OOO-PickBy' = 'least-recent' }) $TLast
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'least-recent: backup picked (last ticket longest ago)' ($f.r.out.replacement -eq 'backup' -and (@($f.r.out.considered) -join ' ') -like '*backup (newest ticket 2026-10-01T10:00:00Z): in. Picked.*alee (newest ticket 2026-10-13T19:00:00Z): not picked, backup has gone longer without a ticket.*' -and $f.r.out.internal_note -like '*longest since their last ticket*' -and @(Get-Calls 'GET' "$TCW/service/tickets/count*").Count -eq 0) ($f.r.out | ConvertTo-Json -Depth 6)

# 17. list-order with a backup list: the first available in the list wins regardless of load.
Reset-TScenario; $TS.members.alee = @{ inactiveFlag = $false }; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z')
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes'; 'OOO-PickBy' = 'list-order'; 'OOO-BackupPool' = 'backup, alee' }) $Handler
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'list-order: first in the list (backup) picked' ($f.r.out.replacement -eq 'backup' -and (@($f.r.out.considered) -join ' ') -like '*backup (#1 in the list): in. Picked.*alee (#2 in the list): not picked, backup is earlier in the list.*') ($f.r.out | ConvertTo-Json -Depth 6)

# ---- list-order from a coverage article in the ConnectWise Knowledge Base ----
$TKb = { param($c, $n) $u = [uri]::UnescapeDataString($c.Uri); if ($c.Method -eq 'GET' -and $u -like "$TCW/service/knowledgeBaseArticles*") { if ($TS.kbFail) { New-HttpError 403 '{"message":"no access"}' }; if ($null -eq $TS.kb) { return , @() }; return , @($TS.kb) }; & $TSweepOrHandler $c $n }
function New-TKb { param([string]$Issue) return [pscustomobject]@{ id = 55; title = 'Out-of-Office Coverage'; issue = $Issue; resolution = '' } }
$TSweepOrHandler = $Handler
$CovSecrets = @{ 'OOO-LiveMode' = 'yes'; 'OOO-PickBy' = 'list-order'; 'OOO-CoverageArticle' = 'Out-of-Office Coverage' }

# 22. The out owner's own row wins; first available in it gets the ticket.
Reset-TScenario; $TS.members.alee = @{ inactiveFlag = $false }; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z'); $TS.kbFail = $false
$TS.kb = New-TKb "# who covers for whom`nJSmith: backup, alee`nBoard Service Desk: alee`n*: alee"
Reset-Mock (New-TSecrets $CovSecrets) $TKb
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'coverage: tech row used, backup picked' ($f.r.out.replacement -eq 'backup' -and $f.r.out.internal_note -like '*from the coverage table (the jsmith row), first available in the list*' -and (@($f.r.out.considered) -join ' ') -like '*backup (#1 in the list): in. Picked.*') ($f.r.out | ConvertTo-Json -Depth 6)
$kbq = @($Mock.Calls | Where-Object { [uri]::UnescapeDataString($_.Uri) -like '*knowledgeBaseArticles?conditions=title="Out-of-Office Coverage"*' }).Count
Check 'coverage: article looked up by title' ($kbq -eq 1) (Show-Calls)

# 23. HTML table with no row for the tech: the board row is used; a first choice who is out is skipped.
Reset-TScenario; $TS.members.alee = @{ inactiveFlag = $false }; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z'); $TS.board['backup'] = @(New-TBoard 'Vacation' '2026-10-17T16:00:00Z'); $TS.kbFail = $false
$TS.kb = New-TKb '<table><tr><th>Who is out</th><th>Who covers, in order</th></tr><tr><td>Board Service Desk</td><td>backup, alee</td></tr><tr><td>*</td><td>backup</td></tr></table>'
Reset-Mock (New-TSecrets $CovSecrets) $TKb
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'coverage: board row from an HTML table, out first choice skipped' ($f.r.out.replacement -eq 'alee' -and $f.r.out.internal_note -like '*the Service Desk board row*' -and (@($f.r.out.considered) -join ' ') -like '*backup (#1 in the list): out*alee (#2 in the list): in. Picked.*') ($f.r.out | ConvertTo-Json -Depth 6)

# 24. A row keyed by Member # (the owner's id) counts as the tech row; * is the last resort.
Reset-TScenario; $TS.members.alee = @{ inactiveFlag = $false }; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z'); $TS.kbFail = $false
$TS.kb = New-TKb "*: backup`n7: alee"
Reset-Mock (New-TSecrets $CovSecrets) $TKb
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'coverage: Member # row beats *' ($f.r.out.replacement -eq 'alee' -and $f.r.out.internal_note -like '*the jsmith row*') ($f.r.out | ConvertTo-Json -Depth 6)
$TS.kb = New-TKb "*: backup"
Reset-Mock (New-TSecrets $CovSecrets) $TKb
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'coverage: * row as last resort' ($f.r.out.replacement -eq 'backup' -and $f.r.out.internal_note -like '*the * row*') ($f.r.out | ConvertTo-Json -Depth 6)

# 25. No matching row: the team with fewest-open, with a warning. Missing article and 403: team with a warning.
Reset-TScenario; $TS.members.alee = @{ inactiveFlag = $false }; $TS.board['jsmith'] = @(New-TBoard 'Out of Office' '2026-10-14T16:00:00Z'); $TS.kbFail = $false
$TS.kb = New-TKb "Board Help Desk: backup"
Reset-Mock (New-TSecrets $CovSecrets) $TKb
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'coverage: no row, team fewest-open with warning' ($f.r.out.replacement -eq 'alee' -and (@($f.r.out.warnings) -join ' ') -like '*has no row for jsmith*') ($f.r.out | ConvertTo-Json -Depth 6)
$TS.kb = $null
Reset-Mock (New-TSecrets $CovSecrets) $TKb
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'coverage: missing article, team with warning' ($f.r.out.status -eq 'success' -and $f.r.out.replacement -ne '' -and (@($f.r.out.warnings) -join ' ') -like '*no Knowledge Base article titled*') ($f.r.out | ConvertTo-Json -Depth 6)
$TS.kbFail = $true
Reset-Mock (New-TSecrets $CovSecrets) $TKb
$f = Invoke-Flow @{ ticketId = '1001'; now = $TNow }
Check 'coverage: 403, permission hint' ((@($f.r.out.warnings) -join ' ') -like '*Inquire access to the Knowledge Base*') ($f.r.out | ConvertTo-Json -Depth 6)

# ---- sweep (a Routine: no input) ----
$TSweep = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri); $k = "$($c.Method) $u"
    if ($k -like "GET $TCW/system/inOutBoards?conditions=dateBack>*") { $all = @(); foreach ($m in $TS.board.Keys) { foreach ($b in @($TS.board[$m])) { $all += [pscustomobject]@{ id = 1; member = [pscustomobject]@{ identifier = $m }; inOutType = $b.inOutType; dateBack = $b.dateBack } } }; return , $all }
    if ($k -like "GET $TCW/schedule/entries?conditions=dateStart<=*") { $all = @(); foreach ($m in $TS.sched.Keys) { foreach ($e in @($TS.sched[$m])) { $all += [pscustomobject]@{ id = $e.id; member = [pscustomobject]@{ identifier = $m }; type = $e.type; name = $e.name; dateStart = $e.dateStart; dateEnd = $e.dateEnd } } }; $all += [pscustomobject]@{ id = 99; member = [pscustomobject]@{ identifier = 'alee' }; type = [pscustomobject]@{ identifier = 'S' }; name = 'Ticket work'; dateStart = '2026-10-13T19:00:00Z'; dateEnd = '2026-10-13T21:00:00Z' }; return , $all }
    if ($k -like "GET $TCW/service/tickets?conditions=closedFlag=false*") { return , @($TS.sweepTickets) }
    if ($k -match "^GET $([regex]::Escape($TCW))/service/tickets/(200\d)/notes") { $tid = $Matches[1]; if ($TS.sweepNotes.ContainsKey($tid)) { return , @($TS.sweepNotes[$tid]) }; return , @() }
    if ($k -match "^(POST|PATCH) $([regex]::Escape($TCW))/service/tickets/(200\d)") { return [pscustomobject]@{ id = 1 } }
    if ($k -match "^GET $([regex]::Escape($TCW))/schedule/entries\?conditions=objectId=(200\d)") { return , @() }
    & $Handler $c $n
}
function New-TTicket { param([string]$Id, [string]$Owner) return [pscustomobject]@{ id = [int]$Id; summary = "Ticket $Id"; company = [pscustomobject]@{ name = 'Contoso' }; board = [pscustomobject]@{ id = 14; name = 'Service Desk' }; team = [pscustomobject]@{ id = 3 }; owner = [pscustomobject]@{ identifier = $Owner }; resources = $Owner } }

# 18. Nobody out: one board read, one schedule read, no ticket list.
Reset-TScenario; $TS.sweepTickets = @(); $TS.sweepNotes = @{}
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes'; 'OOO-Boards' = 'Service Desk' }) $TSweep
$f = Invoke-Flow @{ now = $TNow }
Check 'sweep, nobody out: success, no ticket list' ($f.r.out.status -eq 'success' -and $f.r.out.message -like 'Nobody is out right now*' -and @($Mock.Calls | Where-Object { [uri]::UnescapeDataString($_.Uri) -like '*service/tickets?conditions=closedFlag*' }).Count -eq 0 -and @(Get-Writes).Count -eq 0) ($f.r.out | ConvertTo-Json -Depth 6)

# 19. jsmith out: 2001 reassigned, 2002 already handled and skipped; query scoped to owner, board and window.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Vacation' '2026-10-17T16:00:00Z')
$TS.sweepTickets = @((New-TTicket '2001' 'jsmith'), (New-TTicket '2002' 'jsmith'))
$TS.sweepNotes = @{ '2002' = @([pscustomobject]@{ id = 1; text = "Out-of-office check: earlier`n[ooo-check]"; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false; dateCreated = '2026-10-13T19:30:00Z' }) }
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes'; 'OOO-Boards' = 'Service Desk'; 'OOO-LookbackMinutes' = '30' }) $TSweep
$f = Invoke-Flow @{ now = $TNow }
$q = @($Mock.Calls | Where-Object { [uri]::UnescapeDataString($_.Uri) -like '*service/tickets?conditions=closedFlag*' } | ForEach-Object { [uri]::UnescapeDataString($_.Uri) })
$t1 = @($f.r.out.tickets | Where-Object { $_.ticket_id -eq '2001' })
Check 'sweep: query scoped to out owners, board and window' ($q.Count -eq 1 -and $q[0] -like '*dateEntered>=`[2026-10-13T19:30:00Z`]*owner/identifier in ("jsmith")*board/name in ("Service Desk")*') ($q -join ' | ')
Check 'sweep: alee (ticket work only) not treated as out' (-not ((@($f.r.out.out_now | ForEach-Object { $_.identifier }) -join ',') -like '*alee*') -and (@($f.r.out.out_now | ForEach-Object { $_.identifier }) -join ',') -eq 'jsmith') ($f.r.out.out_now | ConvertTo-Json -Depth 5)
Check 'sweep: 2001 reassigned to alee' ($f.r.out.status -eq 'success' -and $t1.Count -eq 1 -and $t1[0].changed -eq $true -and $t1[0].replacement -eq 'alee' -and @(Get-Calls 'PATCH' "$TCW/service/tickets/2001").Count -eq 1) ($f.r.out | ConvertTo-Json -Depth 6)
Check 'sweep: 2002 skipped as already handled' ((@($f.r.out.skipped | ForEach-Object { "$($_.ticket_id): $($_.why)" }) -join ' ') -like '*2002: *already handled*' -and @(Get-Calls 'PATCH' "$TCW/service/tickets/2002").Count -eq 0) ($f.r.out | ConvertTo-Json -Depth 6)
Check 'sweep: one email, message counts' (@(Get-Calls 'POST' $TPM).Count -eq 1 -and $f.r.out.message -eq '1 ticket assigned to someone who is out: 1 reassigned.') $f.r.out.message

# 20. Preview sweep: pending_confirmation, nothing written.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Vacation' '2026-10-17T16:00:00Z'); $TS.sweepTickets = @((New-TTicket '2001' 'jsmith')); $TS.sweepNotes = @{}
Reset-Mock (New-TSecrets @{ 'OOO-Boards' = 'Service Desk' }) $TSweep
$f = Invoke-Flow @{ now = $TNow }
Check 'sweep preview: pending, no writes, names the replacement' ($f.r.out.status -eq 'pending_confirmation' -and @(Get-Writes).Count -eq 0 -and @($f.r.out.tickets)[0].replacement -eq 'alee') ($f.r.out | ConvertTo-Json -Depth 6)

# 21. No OOO-Boards: every board, with a warning. Cap: only OOO-MaxTickets handled, with a warning.
Reset-TScenario; $TS.board['jsmith'] = @(New-TBoard 'Vacation' '2026-10-17T16:00:00Z'); $TS.sweepTickets = @((New-TTicket '2001' 'jsmith'), (New-TTicket '2003' 'jsmith')); $TS.sweepNotes = @{}
Reset-Mock (New-TSecrets @{ 'OOO-LiveMode' = 'yes'; 'OOO-MaxTickets' = '1' }) $TSweep
$f = Invoke-Flow @{ now = $TNow }
$q = @($Mock.Calls | Where-Object { [uri]::UnescapeDataString($_.Uri) -like '*service/tickets?conditions=closedFlag*' } | ForEach-Object { [uri]::UnescapeDataString($_.Uri) })
Check 'sweep: no board filter, warning, capped at 1' ($q[0] -notlike '*board/name*' -and (@($f.r.out.warnings) -join ' ') -like '*OOO-Boards is not set*' -and (@($f.r.out.warnings) -join ' ') -like '*only the first 1*' -and @($f.r.out.tickets).Count -eq 1) ($f.r.out | ConvertTo-Json -Depth 6)

# 26. Sweep with a coverage article: the article is read once for all tickets.
Reset-TScenario; $TS.members.alee = @{ inactiveFlag = $false }; $TS.board['jsmith'] = @(New-TBoard 'Vacation' '2026-10-17T16:00:00Z'); $TS.sweepTickets = @((New-TTicket '2001' 'jsmith'), (New-TTicket '2003' 'jsmith')); $TS.sweepNotes = @{}; $TS.kbFail = $false
$TS.kb = New-TKb "jsmith: alee, backup"
$TSweepOrHandler = $TSweep
Reset-Mock (New-TSecrets ($CovSecrets + @{ 'OOO-Boards' = 'Service Desk' })) $TKb
$f = Invoke-Flow @{ now = $TNow }
$kbq = @($Mock.Calls | Where-Object { [uri]::UnescapeDataString($_.Uri) -like '*knowledgeBaseArticles*' }).Count
Check 'sweep + coverage: both tickets to alee, article read once' (@($f.r.out.tickets | Where-Object { $_.replacement -eq 'alee' }).Count -eq 2 -and $kbq -eq 1) ($f.r.out | ConvertTo-Json -Depth 6)

Write-Host "$($TestTally.pass) passed, $($TestTally.fail) failed"
if ($TestTally.fail) { exit 1 }
