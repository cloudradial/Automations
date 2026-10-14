# Strict-mode harness for Smart Acknowledgement.
# Runs both PowerShell steps exactly as they are in smart-acknowledgement.yml (shared psa.ps1, psa-tickets.ps1
# and cloudradial.ps1 included), through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest,
# with the runner Key Vault, Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked. The AI Prompt step
# is simulated by handing the send step a judgment string.
# Placeholder data only (Contoso, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a step variable of the same
# name would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File smart-acknowledgement/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\smart-acknowledgement.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.properties&&a.properties.script)o[a.id]=a.properties.script;if(a.type==='ai-prompt'){o['judge.prompt']=a.properties.promptTemplate;o['judge.model']=a.properties.model;o['judge.system']=a.properties.systemMessage}if(a.id==='send')o['send.params']=JSON.stringify(a.properties.parameters)}o.webhook=String(d.definition.activities[0].properties.webhookEnabled);console.log(JSON.stringify(o))"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow has gather, judge and send' ($Steps.Contains('gather') -and $Steps.Contains('send') -and $Steps.Contains('judge.prompt'))
Check 'judge reads the gather facts, model blank, told never to give a time' ($Steps['judge.prompt'] -like '*{{ nodes.gather.output.facts_json }}*' -and $Steps['judge.model'] -eq '' -and $Steps['judge.system'] -like '*Never mention any time*')
Check 'send is bound to gather and judge' ($Steps['send.params'] -like '*nodes.gather.output.ctx_json*' -and $Steps['send.params'] -like '*nodes.judge.output.judgment*')
Check 'webhook ships disabled' ($Steps['webhook'] -eq 'false')
Check 'shared libraries pasted' ($Steps['gather'] -like '*function Get-PsaTicketSla*' -and $Steps['gather'] -like '*function Get-CrAll*' -and $Steps['send'] -like '*function Add-PsaNote*')

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
    param($Body, [string]$Ai)
    $g = Invoke-Step 'gather' ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    if ($g.error) { return @{ stage = 'gather'; out = $g.out; error = $g.error } }
    $s = Invoke-Step 'send' $null @{ ctx = $g.out.ctx_json; judgment = $Ai }
    return @{ stage = 'send'; out = $s.out; error = $s.error; facts = ($g.out.facts_json | ConvertFrom-Json); ctx = ($g.out.ctx_json | ConvertFrom-Json) }
}
function Ai { param([string]$Para = 'Sorry to hear the printer on floor 2 is offline; we know how disruptive that is when everyone needs to print.', $Ids = @(301)) return (@{ paragraph = $Para; articleIds = @($Ids) } | ConvertTo-Json -Compress) }

# ---- placeholder ConnectWise ticket 1001, and CloudRadial company 7 with its articles ----
$TCW = 'https://api-na.example.com/v4_6_release/apis/3.0'; $TCR = 'https://api.cr.example.com'
$TBase = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = $TCW; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid'
    'CloudRadial-BaseUrl' = $TCR; 'CloudRadial-PublicKey' = 'crpub'; 'CloudRadial-PrivateKey' = 'crpriv'; 'Ack-ArticleUrlTemplate' = 'https://support.example-msp.test/app/kb/article/{id}' }
$TC = @{ email = 'pat.doe@contoso.com'; closed = $false; prio = 'Priority 3 - Normal Response'; notes = (New-Object System.Collections.ArrayList); crFilter = '' }
function Reset-TCw { param([hashtable]$Secrets = $TBase) $TC.email = 'pat.doe@contoso.com'; $TC.closed = $false; $TC.prio = 'Priority 3 - Normal Response'; $TC.notes.Clear(); $TC.crFilter = ''; Reset-Mock $Secrets $TCwRouter }
$TCwRouter = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    if ($c.Method -eq 'GET' -and $u -match '/service/tickets/1001$') { return [pscustomobject]@{ id = 1001; summary = 'Floor 2 printer offline'; board = [pscustomobject]@{ id = 1; name = 'Service Desk' }; company = [pscustomobject]@{ id = 42; name = 'Contoso' }; contactEmailAddress = $TC.email; contactName = 'Pat Doe'; priority = [pscustomobject]@{ id = 3; name = $TC.prio }; status = [pscustomobject]@{ name = $(if ($TC.closed) { 'Closed' } else { 'New' }) }; closedFlag = $TC.closed; dateEntered = (Get-Date).ToUniversalTime().AddMinutes(-2).ToString('yyyy-MM-ddTHH:mm:ssZ') } }
    if ($c.Method -eq 'GET' -and $u -like '*/service/tickets/1001/notes*') { return , (@([pscustomobject]@{ id = 1; text = 'The floor 2 printer shows offline and nothing prints.'; internalAnalysisFlag = $false; detailDescriptionFlag = $true }) + @(@($TC.notes) | ForEach-Object { $_ })) }
    if ($c.Method -eq 'POST' -and $u -like '*/service/tickets/1001/notes') { $b = Read-Body $c; $null = $TC.notes.Add([pscustomobject]@{ id = 900 + $TC.notes.Count; text = $b.text; internalAnalysisFlag = [bool]$b.internalAnalysisFlag; detailDescriptionFlag = [bool]$b.detailDescriptionFlag }); return [pscustomobject]@{ id = 900 } }
    if ($c.Method -eq 'GET' -and $u -like "$TCR/v2/odata/company*") { return [pscustomobject]@{ value = @([pscustomobject]@{ companyId = 7; name = 'Contoso'; psaKey = '42' }) } }
    if ($c.Method -eq 'GET' -and $u -like "$TCR/v2/odata/article*") {
        $TC.crFilter = $u
        $past = (Get-Date).ToUniversalTime().AddDays(-30).ToString('yyyy-MM-ddTHH:mm:ssZ'); $future = (Get-Date).ToUniversalTime().AddDays(10).ToString('yyyy-MM-ddTHH:mm:ssZ')
        return [pscustomobject]@{ value = @(
                [pscustomobject]@{ articleId = 301; companyId = 7; subject = 'Fix a printer that shows offline'; datePublished = $past; category = 'Printing' },
                [pscustomobject]@{ articleId = 302; companyId = 0; subject = 'Set up a new printer'; datePublished = $past; category = 'Printing' },
                [pscustomobject]@{ articleId = 303; companyId = 7; subject = 'Printer offline draft'; datePublished = $future; category = 'Printing' },
                [pscustomobject]@{ articleId = 304; companyId = 7; subject = 'Reset your VPN'; datePublished = $past; category = 'Network' }) }
    }
    return $null
}
function Get-TPosts { return , @($Mock.Calls | Where-Object { $_.Method -eq 'POST' -and $_.Uri -like '*/notes' }) }
function Get-TWrites { return , @($Mock.Calls | Where-Object { $_.Method -ne 'GET' }) }
$TBody = @{ ticketId = '1001' }

# 1. Preview: the whole message is returned and nothing is written.
Reset-TCw
$r = Invoke-Flow $TBody (Ai)
Check 'preview: pending, nothing written' ($r.out.status -eq 'pending_confirmation' -and -not (Get-TWrites).Count) "$($r.error) $($r.out.message) $(Show-Calls)"
$p = [string]$r.out.public_note
Check 'message: greeting, summary, ticket number, the AI paragraph' ($p -like 'Hello Pat,*' -and $p -like '*"Floor 2 printer offline", as ticket 1001.*' -and $p -like '*printer on floor 2 is offline*') $p
Check 'message: the medium target, never a resolution time' ($p -like '*We aim to respond within 1 business day.*' -and $p -notmatch '(?i)resolv') $p
Check 'message: the chosen article with its portal link' ($p -like '*this article may help:*Fix a printer that shows offline: https://support.example-msp.test/app/kb/article/301*') $p
Check 'articles offered: published and sharing words, own company or MSP-wide only' ((@($r.facts.articles | ForEach-Object { $_.id }) -join ',') -eq '301,302' -and $TC.crFilter -like '*companyId eq 7 or companyId eq 0*') "$((@($r.facts.articles | ForEach-Object { $_.id }) -join ',')) $($TC.crFilter)"

# 2. Confirmed: a public note (the PSA emails the contact), then an internal note.
Reset-TCw
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai)
$posts = Get-TPosts
Check 'confirm: public note then internal note' ($r.out.status -eq 'success' -and $posts.Count -eq 2 -and (Read-Body $posts[0]).internalAnalysisFlag -ne $true -and (Read-Body $posts[1]).internalAnalysisFlag -eq $true -and $r.out.counts.acknowledgementsSent -eq 1) "$($r.error) $(Show-Calls)"
Check 'confirm: internal note says what was promised and that no resolution time was given' ((Read-Body $posts[1]).text -like '*Acknowledgement sent to pat.doe@contoso.com for ticket 1001*No resolution time was given*Articles: 301*') ((Read-Body $posts[1]).text)

# 3. Rerun: already acknowledged, so nothing is sent again and the run ends success.
$Mock.Calls.Clear()
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai)
Check 'rerun: already acknowledged, nothing sent' ($r.out.status -eq 'success' -and $r.out.message -like '*already acknowledged*' -and -not (Get-TWrites).Count) "$($r.error) $($r.out.message) $(Show-Calls)"

# 4. A paragraph that promises a fix or a time is dropped; the standard wording is used.
Reset-TCw
$r = Invoke-Flow $TBody (Ai 'We will have this fixed within 2 hours, do not worry.')
Check 'AI promise dropped: no time in the message, warning says why' ([string]$r.out.public_note -notmatch '2 hours' -and (@($r.out.warnings) -join ' ') -like '*left out because it promised a fix*' -and $r.out.internal_note -like '*Standard wording was used*') "$($r.out.public_note) $(@($r.out.warnings) -join ' | ')"
$r = Invoke-Flow $TBody (Ai 'Please reply with your password so we can check your account.')
Check 'AI asking for a password dropped' ([string]$r.out.public_note -notmatch '(?i)password' -and (@($r.out.warnings) -join ' ') -like '*credentials*') $r.out.public_note
$r = Invoke-Flow $TBody (Ai 'We are on it.' @(999, 304, 301, 302))
Check 'AI article ids: unknown dropped, at most two kept' ((@($r.out.warnings) -join ' ') -like '*article 999*' -and ([regex]::Matches([string]$r.out.public_note, '/app/kb/article/')).Count -eq 2) "$($r.out.public_note) $(@($r.out.warnings) -join ' | ')"
$r = Invoke-Flow $TBody 'not json at all'
Check 'unreadable AI answer: standard wording, still a complete message' ($r.out.status -eq 'pending_confirmation' -and [string]$r.out.public_note -like '*as ticket 1001.*We aim to respond*' -and (@($r.out.warnings) -join ' ') -like '*no readable answer*') $r.out.public_note

# 5. Priority targets come from the Ack-ResponseTargets secret.
$s = $TBase.Clone(); $s['Ack-ResponseTargets'] = 'critical=30 minutes, high=2 hours'
Reset-TCw $s; $TC.prio = 'Priority 2 - High'
$r = Invoke-Flow $TBody (Ai)
Check 'high priority with the targets secret: within 2 hours' ([string]$r.out.public_note -like '*We aim to respond within 2 hours.*') $r.out.public_note

# 6. No article link template: titles are named, not linked. No CloudRadial: no articles, still sent.
$s = $TBase.Clone(); $s.Remove('Ack-ArticleUrlTemplate')
Reset-TCw $s
$r = Invoke-Flow $TBody (Ai)
Check 'no link template: article named without a link' ([string]$r.out.public_note -like "*Fix a printer that shows offline (in your support portal's knowledge base)*") $r.out.public_note
$s = $TBase.Clone(); foreach ($k in @('CloudRadial-BaseUrl', 'CloudRadial-PublicKey', 'CloudRadial-PrivateKey')) { $s.Remove($k) }
Reset-TCw $s
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai 'Thanks, we are looking into it.' @(301))
Check 'no CloudRadial: no articles offered, acknowledgement still sent' ($r.out.status -eq 'success' -and -not @($r.facts.articles).Count -and [string]$r.out.public_note -notlike '*article*' -and (Get-TPosts).Count -eq 2) "$($r.error) $($r.out.public_note)"

# 7. Fail closed: no contact email, closed ticket, no ticketId.
Reset-TCw; $TC.email = ''
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai)
Check 'no contact email: incomplete, nothing sent' ($r.stage -eq 'gather' -and $r.out.status -eq 'incomplete' -and -not (Get-TWrites).Count) "$($r.out.message)"
Reset-TCw; $TC.closed = $true
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai)
Check 'closed ticket: success, nothing sent' ($r.out.status -eq 'success' -and $r.out.message -like '*already closed*' -and -not (Get-TWrites).Count) "$($r.error) $($r.out.message)"
Reset-TCw
$r = Invoke-Flow @{ confirm = $true } (Ai)
Check 'no ticketId: incomplete, nothing read' ($r.stage -eq 'gather' -and $r.out.status -eq 'incomplete' -and -not $Mock.Calls.Count) $r.out.message

# ---- Autotask: the PSA's own SLA response target, in the MSP's time zone ----
$TAT = 'https://webservices5.autotask.example/atservicesrest/v1.0'
$TA = @{ due = $null; notes = (New-Object System.Collections.ArrayList) }
$TAtRouter = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    if ($c.Method -eq 'GET' -and $u -eq "$TAT/Tickets/1001") { return [pscustomobject]@{ item = [pscustomobject]@{ id = 1001; ticketNumber = 'T20261014.0001'; title = 'Cannot connect to VPN'; description = 'VPN fails from home.'; companyID = 42; contactID = 5; priority = 2; status = 1; createDate = (Get-Date).ToUniversalTime().AddMinutes(-3).ToString('yyyy-MM-ddTHH:mm:ssZ'); firstResponseDueDateTime = $TA.due } } }
    if ($u -like "$TAT/Contacts/5*") { return [pscustomobject]@{ item = [pscustomobject]@{ id = 5; firstName = 'Sam'; lastName = 'Lee'; emailAddress = 'sam.lee@contoso.com' } } }
    if ($u -eq "$TAT/Tickets/entityInformation/fields") { return [pscustomobject]@{ fields = @(
                [pscustomobject]@{ name = 'priority'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'High'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Medium'; isActive = $true }) },
                [pscustomobject]@{ name = 'status'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'New'; isActive = $true }, [pscustomobject]@{ value = '5'; label = 'Complete'; isActive = $true }) }) } }
    if ($u -eq "$TAT/TicketNotes/entityInformation/fields") { return [pscustomobject]@{ fields = @(
                [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) } }
    if ($c.Method -eq 'POST' -and $u -like "$TAT/Tickets/1001/Notes") { $null = $TA.notes.Add((Read-Body $c)); return [pscustomobject]@{ itemId = 77 } }
    return [pscustomobject]@{ items = @(); pageDetails = [pscustomobject]@{ nextPageUrl = $null } }
}
$TA.due = (Get-Date).ToUniversalTime().AddHours(3).ToString('yyyy-MM-ddTHH:mm:ssZ')
Reset-Mock @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices5.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec'; 'Ack-TimeZone' = 'UTC' } $TAtRouter
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai 'Sorry the VPN is giving you trouble from home.' @())
Check 'autotask: the SLA response target is stated as a time' ([string]$r.out.public_note -match 'We aim to respond by \w+day \d{1,2} \w+, \d{1,2}:\d{2} [AP]M \(UTC\)\.' -and $r.out.internal_note -like "*Autotask's SLA response target*") "$($r.error) $($r.out.public_note)"
Check 'autotask: public note to the contact, then an internal one' ($TA.notes.Count -eq 2 -and $TA.notes[0].publish -eq 1 -and $TA.notes[1].publish -eq 2) "$(($TA.notes | ConvertTo-Json -Compress -Depth 3))"

Complete-Test
