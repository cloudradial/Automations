# Strict-mode harness for Severity / Priority Scoring.
# Runs both PowerShell steps exactly as they are in priority-scoring.yml (shared psa.ps1, psa-tickets.ps1,
# postmark.ps1 and src/psa-priority.ps1 included), through & ([scriptblock]::Create(...)) under
# Set-StrictMode -Version Latest, with the runner Key Vault, Invoke-RestMethod, Get-NodeInput and
# Set-NodeOutput mocked. Placeholder data only (Contoso, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a step variable of the same
# name would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File priority-scoring/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\priority-scoring.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.properties&&a.properties.script)o[a.id]=a.properties.script;if(a.id==='apply')o['apply.params']=JSON.stringify(a.properties.parameters)}o.webhook=String(d.definition.activities[0].properties.webhookEnabled);o.ids=d.definition.activities.map(a=>a.id).join(',');console.log(JSON.stringify(o))"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow: start, score, apply, end' ($Steps['ids'] -eq 'start,score,apply,end') $Steps['ids']
Check 'apply is bound to the score context' ($Steps['apply.params'] -like '*{{ nodes.score.output.ctx_json }}*')
Check 'webhook ships disabled' ($Steps['webhook'] -eq 'false')
Check 'shared libraries and psa-priority.ps1 pasted' ($Steps['score'] -like '*function ConvertTo-PsaTicketRow*' -and $Steps['apply'] -like '*function Send-PmMail*' -and $Steps['apply'] -like '*function Set-PsaPriority*')

# ---- runner mocks ----
$global:NodeIn = $null; $global:NodeParams = @{}; $global:NodeOut = $null
function Get-NodeInput { param([string]$Name) if ($Name) { if ($global:NodeParams.Contains($Name)) { return $global:NodeParams[$Name] }; return $null }; return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Invoke-Step {
    param([string]$Id, $In = $null, [hashtable]$Params = @{})
    $global:NodeIn = $In; $global:NodeParams = $Params; $global:NodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps[$Id])) } catch { $err = [string]$_.Exception.Message }
    $o = $null; if ($null -ne $global:NodeOut) { $o = ($global:NodeOut | ConvertTo-Json -Depth 14 | ConvertFrom-Json) }
    return @{ out = $o; error = $err }
}
function Invoke-Flow {
    param($Body)
    $s = Invoke-Step 'score' ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    if ($s.error) { return @{ stage = 'score'; out = $s.out; error = $s.error } }
    $a = Invoke-Step 'apply' $null @{ ctx = $s.out.ctx_json }
    return @{ stage = 'apply'; out = $a.out; error = $a.error; ctx = ($s.out.ctx_json | ConvertFrom-Json) }
}

# ---- placeholder ConnectWise ticket 1001 ----
$TCW = 'https://api-na.example.com/v4_6_release/apis/3.0'
$TBase = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = $TCW; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid'; 'Dispatcher-Email' = 'dispatch@example-msp.test'; 'Postmark-ServerToken' = 'pm-token'; 'Postmark-FromEmail' = 'alerts@example-msp.test' }
$TPrio = @(@{ id = 1; name = 'Priority 1 - Emergency Response' }, @{ id = 2; name = 'Priority 2 - Quick Response' }, @{ id = 15; name = 'Priority 2 - High' }, @{ id = 3; name = 'Priority 3 - Normal Response' }, @{ id = 4; name = 'Priority 4 - Schedule Maintenance' }, @{ id = 7; name = 'Priority 5 - Low' })
$TC = @{ summary = ''; desc = ''; prio = $null; notes = (New-Object System.Collections.ArrayList); prio403 = $false; contact = 'pat.doe@contoso.com' }
function Reset-TCw {
    param([string]$Summary, [string]$Desc = '', [int]$PrioId = 3, [hashtable]$Secrets = $TBase)
    $TC.summary = $Summary; $TC.desc = $Desc; $TC.prio = @($TPrio | Where-Object { $_.id -eq $PrioId })[0]; $TC.notes.Clear(); $TC.prio403 = $false
    Reset-Mock $Secrets $TCwRouter
}
$TCwRouter = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    if ($c.Method -eq 'GET' -and $u -match '/service/tickets/1001$') { return [pscustomobject]@{ id = 1001; summary = $TC.summary; initialDescription = $TC.desc; board = [pscustomobject]@{ id = 1; name = 'Service Desk' }; company = [pscustomobject]@{ id = 42; identifier = 'Contoso'; name = 'Contoso' }; contactEmailAddress = $TC.contact; contact = [pscustomobject]@{ id = 5; name = 'Pat Doe' }; priority = [pscustomobject]@{ id = $TC.prio.id; name = $TC.prio.name }; status = [pscustomobject]@{ name = 'New' }; closedFlag = $false } }
    if ($c.Method -eq 'GET' -and $u -like '*/service/tickets/1001/notes*') { return , (@([pscustomobject]@{ id = 1; text = $TC.desc; internalAnalysisFlag = $false; detailDescriptionFlag = $true }) + @(@($TC.notes) | ForEach-Object { [pscustomobject]@{ id = 2; text = $_; internalAnalysisFlag = $true } })) }
    if ($c.Method -eq 'POST' -and $u -like '*/service/tickets/1001/notes') { $null = $TC.notes.Add((Read-Body $c).text); return [pscustomobject]@{ id = 900 } }
    if ($c.Method -eq 'GET' -and $u -like '*/service/priorities*') { if ($TC.prio403) { New-HttpError 403 '{"code":"Unauthorized","message":"Security"}' }; return , @($TPrio | ForEach-Object { [pscustomobject]$_ }) }
    if ($c.Method -eq 'PATCH' -and $u -like '*/service/tickets/1001') { foreach ($op in @(Read-Body $c)) { if ($op.path -eq 'priority') { $TC.prio = @($TPrio | Where-Object { $_.id -eq [int]$op.value.id })[0] } }; return [pscustomobject]@{ id = 1001 } }
    if ($c.Method -eq 'POST' -and $u -like 'https://api.postmarkapp.com/email') { return [pscustomobject]@{ MessageID = 'pm-1'; ErrorCode = 0; Message = 'OK' } }
    return $null
}
function Get-TPatch { return , @($Mock.Calls | Where-Object { $_.Method -eq 'PATCH' }) }
function Get-TMail { return , @($Mock.Calls | Where-Object { $_.Uri -like 'https://api.postmarkapp.com/*' }) }
function Get-TNotes { return , @($Mock.Calls | Where-Object { $_.Method -eq 'POST' -and $_.Uri -like '*/notes' }) }
function Get-TWrites { return , @($Mock.Calls | Where-Object { $_.Method -ne 'GET' }) }
$TBody = @{ ticketId = '1001' }

# 1. An outage for everyone: scored critical, capped at high, flagged as a possible P1. Preview writes nothing.
Reset-TCw 'Server is down' 'The file server is down for everyone in the office.'
$r = Invoke-Flow $TBody
Check 'outage preview: critical score, plan says high and dispatcher, nothing written' ($r.out.status -eq 'pending_confirmation' -and $r.out.level -eq 'critical' -and $r.out.possible_p1 -eq $true -and $r.out.message -like '*Would set the priority to high, email the dispatcher*' -and -not (Get-TWrites).Count) "$($r.error) $($r.out.message) $(Show-Calls)"
Check 'outage score: 10 + 40 down + 25 everyone = 75' ($r.out.score -eq 75 -and $r.out.internal_note -like '*+40 something is down or compromised (is down)*' -and $r.out.internal_note -like '*+25 many people affected (everyone)*') $r.out.internal_note

# 2. Confirmed: raised to high (never critical), the dispatcher emailed, one internal note.
Reset-TCw 'Server is down' 'The file server is down for everyone in the office.'
$r = Invoke-Flow ($TBody + @{ confirm = $true })
$ops = @(Get-TPatch | ForEach-Object { @(Read-Body $_) })
Check 'outage confirm: priority set to the high one, not Emergency' ((Get-TPatch).Count -eq 1 -and $ops[0].path -eq 'priority' -and $ops[0].value.id -eq 15 -and $r.out.counts.prioritySet -eq 1) "$($r.error) $(($ops | ConvertTo-Json -Compress -Depth 4))"
$mail = @(Get-TMail); $mb = $(if ($mail.Count) { Read-Body $mail[0] } else { $null })
Check 'outage confirm: dispatcher emailed about a possible P1' ($mail.Count -eq 1 -and $mb.To -eq 'dispatch@example-msp.test' -and $mb.Subject -eq 'Possible P1: ticket 1001 for Contoso' -and $r.out.counts.dispatcherEmailed -eq 1) "$(Show-Calls) $($mb | ConvertTo-Json -Compress)"
$nb = Read-Body @(Get-TNotes)[0]
Check 'outage confirm: one internal note with the breakdown and the P1 line' ((Get-TNotes).Count -eq 1 -and $nb.internalAnalysisFlag -eq $true -and $nb.text -like '*Priority score for ticket 1001: 75 of 100*POSSIBLE P1*' -and $r.out.status -eq 'success') "$($r.out.status) $($nb.text)"

# 3. Rerun: already scored, so the priority isn't touched and the dispatcher isn't emailed again.
$Mock.Calls.Clear()
$r = Invoke-Flow ($TBody + @{ confirm = $true })
Check 'rerun: already scored, nothing written or sent' ($r.out.status -eq 'success' -and $r.out.message -like '*already scored*' -and -not (Get-TWrites).Count) "$($r.out.message) $(Show-Calls)"

# 4. Never lower: an Emergency ticket that reads like a request keeps its priority.
Reset-TCw 'Question about signatures' 'How do I set up an email signature? No rush.' -PrioId 1
$r = Invoke-Flow ($TBody + @{ confirm = $true })
Check 'never lower: critical kept, no PATCH, still noted' (-not (Get-TPatch).Count -and $r.out.level -eq 'low' -and $r.out.message -like '*never lowers*' -and (Get-TNotes).Count -eq 1 -and $r.out.possible_p1 -eq $false) "$($r.out.message) $(Show-Calls)"

# 5. A single blocked user on a low ticket: raised to medium.
Reset-TCw 'Login problem' "I can't log in to the accounting app." -PrioId 7
$r = Invoke-Flow ($TBody + @{ confirm = $true })
$ops = @(Get-TPatch | ForEach-Object { @(Read-Body $_) })
Check 'blocked user: 10 + 20 = 30, low raised to medium' ($r.out.score -eq 30 -and $r.out.level -eq 'medium' -and $ops.Count -eq 1 -and $ops[0].value.id -eq 3) "$($r.out.score) $($r.out.message) $(($ops | ConvertTo-Json -Compress -Depth 4))"

# 6. VIP and premium tier lift an ordinary fault to high; the counts of people work too.
$s = $TBase.Clone(); $s['VIP-Companies'] = 'Fabrikam, Contoso=am@example-msp.test'; $s['Priority-CompanyTiers'] = 'Contoso=premium, Fabrikam=basic'
Reset-TCw 'Outlook' 'Outlook is not working on my laptop.' -Secrets $s
$r = Invoke-Flow $TBody
Check 'VIP + premium: 10 + 20 + 15 + 10 = 55, high' ($r.out.score -eq 55 -and $r.out.level -eq 'high' -and $r.out.internal_note -like '*+15 VIP (contoso is on the VIP list)*' -and $r.out.internal_note -like '*+10 premium company*') "$($r.out.score) $($r.out.internal_note)"
Reset-TCw 'Printing' '12 users cannot print since this morning.'
$r = Invoke-Flow $TBody
Check '12 users blocked: 10 + 20 + 25 = 55, high' ($r.out.score -eq 55 -and $r.out.internal_note -like '*12 affected*') "$($r.out.score) $($r.out.internal_note)"
$r = Invoke-Flow ($TBody + @{ vip_list = '@contoso.com'; company_tiers = '42=basic' })
Check 'inputs override: @domain VIP and tier by company id' ($r.out.internal_note -like '*VIP (@contoso.com*' -and $r.out.internal_note -like '*-5 basic company*') $r.out.internal_note

# 7. A possible P1 with no Postmark: incomplete, and the note says the dispatcher wasn't emailed.
$s = $TBase.Clone(); $s.Remove('Postmark-ServerToken')
Reset-TCw 'Ransomware' 'Files are encrypted on every PC, ransomware note on screen, all staff affected.' -Secrets $s
$r = Invoke-Flow ($TBody + @{ confirm = $true })
Check 'P1 without Postmark: incomplete, note says not emailed' ($r.out.status -eq 'incomplete' -and -not (Get-TMail).Count -and (Read-Body @(Get-TNotes)[0]).text -like "*dispatcher wasn't emailed*Postmark-ServerToken*") "$($r.out.status) $(Show-Calls)"

# 8. A role that can't list priorities: impact and urgency go through the board's matrix, with a warning.
Reset-TCw 'Login problem' "I can't log in to the accounting app." -PrioId 7
$TC.prio403 = $true
$r = Invoke-Flow ($TBody + @{ confirm = $true })
$ops = @(Get-TPatch | ForEach-Object { @(Read-Body $_) })
Check 'priorities 403: impact and severity set instead, warning names the permission' ((($ops | ForEach-Object { "$($_.path)=$($_.value)" }) -join ',') -eq 'impact=Medium,severity=Medium' -and (@($r.out.warnings) -join ' ') -like '*Inquire access to Service Desk priorities*') "$(($ops | ConvertTo-Json -Compress -Depth 4)) $(@($r.out.warnings) -join ' | ')"

# 9. Bad input fails closed.
Reset-TCw 'x'
$r = Invoke-Flow @{ confirm = $true }
Check 'no ticketId: incomplete, nothing read' ($r.stage -eq 'score' -and $r.out.status -eq 'incomplete' -and -not $Mock.Calls.Count) "$($r.out.message)"

# ---- Zendesk and Autotask ----
$TZdUrl = 'https://example.zendesk.com/api/v2'
$TZ = @{ prio = 'normal' }
$TZdRouter = {
    param($c, $n)
    if ($c.Method -eq 'GET' -and $c.Uri -eq "$TZdUrl/tickets/1001") { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1001; subject = 'VPN down'; description = 'The VPN is down for everyone.'; organization_id = 42; requester_id = 5; priority = $TZ.prio; status = 'new' } } }
    if ($c.Method -eq 'GET' -and $c.Uri -like "$TZdUrl/organizations/42*") { return [pscustomobject]@{ organization = [pscustomobject]@{ id = 42; name = 'Contoso' } } }
    if ($c.Method -eq 'GET' -and $c.Uri -like "$TZdUrl/tickets/1001/comments*") { return [pscustomobject]@{ comments = @(); next_page = $null } }
    if ($c.Method -eq 'PUT' -and $c.Uri -eq "$TZdUrl/tickets/1001") { $b = Read-Body $c; if ($b.ticket.PSObject.Properties['priority']) { $TZ.prio = $b.ticket.priority }; return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1001 } } }
    if ($c.Method -eq 'POST' -and $c.Uri -like 'https://api.postmarkapp.com/email') { return [pscustomobject]@{ MessageID = 'pm-2'; ErrorCode = 0 } }
    return $null
}
$s = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok'; 'Dispatcher-Email' = 'dispatch@example-msp.test'; 'Postmark-ServerToken' = 'pm'; 'Postmark-FromEmail' = 'alerts@example-msp.test' }
Reset-Mock $s $TZdRouter
$r = Invoke-Flow ($TBody + @{ confirm = $true })
Check 'zendesk: normal raised to high, dispatcher emailed' ($TZ.prio -eq 'high' -and $r.out.counts.dispatcherEmailed -eq 1 -and $r.out.status -eq 'success') "$($r.error) $($r.out.message) $(Show-Calls)"

$TAT = 'https://webservices5.autotask.example/atservicesrest/v1.0'
$TA = @{ prio = 2 }
$TAtRouter = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    if ($c.Method -eq 'GET' -and $u -eq "$TAT/Tickets/1001") { return [pscustomobject]@{ item = [pscustomobject]@{ id = 1001; ticketNumber = 'T20261014.0001'; title = 'Cannot connect'; description = 'Unable to connect to the VPN.'; companyID = 42; priority = $TA.prio; status = 1 } } }
    if ($u -eq "$TAT/Tickets/entityInformation/fields") { return [pscustomobject]@{ fields = @(
                [pscustomobject]@{ name = 'priority'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'High'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Medium'; isActive = $true }, [pscustomobject]@{ value = '3'; label = 'Low'; isActive = $true }, [pscustomobject]@{ value = '4'; label = 'Critical'; isActive = $true }) },
                [pscustomobject]@{ name = 'status'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'New'; isActive = $true }) }) } }
    if ($u -eq "$TAT/TicketNotes/entityInformation/fields") { return [pscustomobject]@{ fields = @(
                [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) } }
    if ($c.Method -eq 'PATCH' -and $u -eq "$TAT/Tickets") { $TA.prio = (Read-Body $c).priority; return [pscustomobject]@{ itemId = 1001 } }
    if ($c.Method -eq 'POST' -and $u -like "$TAT/Tickets/1001/Notes") { return [pscustomobject]@{ itemId = 77 } }
    if ($u -like "$TAT/Companies/42*") { return [pscustomobject]@{ item = [pscustomobject]@{ id = 42; companyName = 'Contoso' } } }
    return [pscustomobject]@{ items = @(); pageDetails = [pscustomobject]@{ nextPageUrl = $null } }
}
Reset-Mock @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices5.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' } $TAtRouter
$r = Invoke-Flow ($TBody + @{ confirm = $true; vip_list = 'Contoso'; company_tiers = 'Contoso=premium' })
Check 'autotask: medium raised to the High picklist value' ($TA.prio -eq 1 -and $r.out.counts.prioritySet -eq 1) "$($r.error) $($r.out.score) $($r.out.message) $(Show-Calls)"

Complete-Test
