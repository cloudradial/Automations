# Strict-mode harness for Enterprise / VIP Ticket Alert.
# Runs each PowerShell step exactly as it is in vip-ticket-alert.yml (shared libraries included),
# through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the runner Key Vault,
# Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked.
# Placeholder data only (Contoso, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a step variable of the
# same name would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File vip-ticket-alert/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\vip-ticket-alert.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.type==='powershell-script')o[a.id]=a.properties.script;if(a.id==='check')o['check.params']=JSON.stringify(a.properties.parameters)}console.log(JSON.stringify(o));"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow has check, build and send steps' ($Steps.Contains('check') -and $Steps.Contains('build') -and $Steps.Contains('send'))
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
# check -> build -> send, each fed the previous output, the way the runner chains unbound steps.
function Invoke-Flow {
    param($Body)
    $c = Invoke-Step 'check' ([pscustomobject]@{ trigger = ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json) })
    if ($c.error) { return @{ stage = 'check'; r = $c } }
    $b = Invoke-Step 'build' $c.out
    if ($b.error) { return @{ stage = 'build'; r = $b } }
    $s = Invoke-Step 'send' $b.out
    return @{ stage = 'send'; r = $s; check = $c.out }
}

# ---- placeholder data ----
$Psa = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://api-na.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices5.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
}
$TPostmark = @{ 'Postmark-ServerToken' = 'pm-token'; 'Postmark-FromEmail' = 'alerts@examplemsp.example' }
function Get-Secrets { param([string]$P, [hashtable]$Extra = @{}, [switch]$NoPostmark) $s = @{}; foreach ($k in $Psa[$P].Keys) { $s[$k] = $Psa[$P][$k] }; if (-not $NoPostmark) { foreach ($k in $TPostmark.Keys) { $s[$k] = $TPostmark[$k] } }; foreach ($k in $Extra.Keys) { $s[$k] = $Extra[$k] }; return $s }
$TCW = 'https://api-na.example.com/v4_6_release/apis/3.0'; $TAT = 'https://webservices5.autotask.example/atservicesrest/v1.0'; $TZD = 'https://example.zendesk.com/api/v2'
$TPM = 'https://api.postmarkapp.com/email'
$TScenario = @{ cwNotes = @(); atNotes = @(); zdComments = @(); noteFail = 0; readFail = 0; postmarkFail = 0 }

$Handler = {
    param($c, $n)
    $k = "$($c.Method) $($c.Uri)"
    switch -Wildcard -CaseSensitive ($k) {
        "POST $TPM" { if ($TScenario.postmarkFail) { New-HttpError $TScenario.postmarkFail '{"ErrorCode":300,"Message":"Invalid email request"}' }; return [pscustomobject]@{ MessageID = 'pm-0001'; ErrorCode = 0 } }
        "GET $TCW/service/tickets/1001/notes*" { return , @($TScenario.cwNotes) }
        "GET $TCW/service/tickets/1001" { if ($TScenario.readFail) { New-HttpError $TScenario.readFail '{"message":"You do not have access to this record."}' }; return [pscustomobject]@{ id = 1001; summary = 'Email is down for the whole office'; company = [pscustomobject]@{ id = 42 }; status = [pscustomobject]@{ name = 'New' }; owner = $null } }
        "POST $TCW/service/tickets/1001/notes" { if ($TScenario.noteFail) { New-HttpError $TScenario.noteFail '{"message":"Insufficient security level"}' }; return [pscustomobject]@{ id = 9001 } }
        "GET $TAT/TicketNotes/entityInformation/fields" { return [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                    [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '13'; label = 'System Workflow Note'; isActive = $true }, [pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) } }
        "GET $TAT/TicketNotes/query*" { return [pscustomobject]@{ items = @($TScenario.atNotes); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
        "GET $TAT/Tickets/1001" { return [pscustomobject]@{ item = [pscustomobject]@{ id = 1001; title = 'Server offline'; description = 'The file server is offline.'; companyID = 42; status = 1; assignedResourceID = $null } } }
        "POST $TAT/Tickets/1001/Notes" { return [pscustomobject]@{ itemId = 3001 } }
        "GET $TZD/tickets/1001/comments*" { return [pscustomobject]@{ comments = @($TScenario.zdComments) } }
        "GET $TZD/tickets/1001" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1001; subject = 'Laptop will not start'; description = 'It beeps.'; organization_id = 77; status = 'new'; assignee_id = $null } } }
        "PUT $TZD/tickets/1001" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1001 } } }
    }
    throw "Unexpected call in test: $k"
}
function Get-WriteCalls { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' }) }
function Reset-Scenario { $TScenario.cwNotes = @(); $TScenario.atNotes = @(); $TScenario.zdComments = @(); $TScenario.noteFail = 0; $TScenario.readFail = 0; $TScenario.postmarkFail = 0 }
$base = @{ ticketId = '1001'; companyName = 'Contoso'; contactEmail = 'megan.bowen@contoso.com'; summary = 'Email is down for the whole office'; priority = 'High'; triggerSource = 'serviceai-triage' }
function New-Body { param([hashtable]$Over) $b = @{}; foreach ($k in $base.Keys) { $b[$k] = $base[$k] }; foreach ($k in $Over.Keys) { $b[$k] = $Over[$k] }; return $b }

# ---- 1. ConnectWise preview: VIP, nothing sent or written ----
Reset-Mock (Get-Secrets 'connectwise' @{ 'VIP-Companies' = 'Fabrikam, Contoso = am@example.com|csm@example.com' }) $Handler; Reset-Scenario
$f = Invoke-Flow (New-Body @{ preview = $true })
$o = $f.r.out
Check 'preview: reached the send step' ($f.stage -eq 'send' -and -not $f.r.error) "$($f.stage) $($f.r.error)"
Check 'preview: status pending_confirmation' ($o.status -eq 'pending_confirmation') $o.status
Check 'preview: nothing sent or written' (@(Get-WriteCalls).Count -eq 0) (Show-Calls)
Check 'preview: recipients from the VIP-Companies entry' ((@($o.recipients) -join ',') -eq 'am@example.com,csm@example.com') (@($o.recipients) -join ',')
Check 'preview: email text has summary, priority and ConnectWise link' ($o.email_text -like '*Summary: Email is down for the whole office*' -and $o.email_text -like '*Priority: High*' -and $o.email_text -like '*https://na.example.com/v4_6_release/services/system_io/Service/fv_sr100_request.rails?service_recid=1001*') $o.email_text
Check 'preview: chatReply and public_note present' ($o.chatReply -like 'Preview:*' -and $o.public_note -eq '')

# ---- 2. ConnectWise act: Postmark email, then internal note ----
Reset-Mock (Get-Secrets 'connectwise' @{ 'VIP-Companies' = 'Contoso=am@example.com' }) $Handler; Reset-Scenario
$f = Invoke-Flow (New-Body @{ })
$o = $f.r.out
$pm = @(Get-Calls 'POST' $TPM)
$nt = @(Get-Calls 'POST' "$TCW/service/tickets/1001/notes")
Check 'cw act: status success, alerted' ($o.status -eq 'success' -and $o.alerted -eq $true -and $o.postmark_message_id -eq 'pm-0001') "$($o.status) $($f.r.error)"
Check 'cw act: one Postmark email to the account manager' ($pm.Count -eq 1 -and (Read-Body $pm[0]).To -eq 'am@example.com' -and (Read-Body $pm[0]).Subject -like 'VIP ticket from Contoso:*' -and $pm[0].Headers['X-Postmark-Server-Token'] -eq 'pm-token') (Show-Calls)
Check 'cw act: internal note on the Internal tab' ($nt.Count -eq 1 -and (Read-Body $nt[0]).internalAnalysisFlag -eq $true -and (Read-Body $nt[0]).detailDescriptionFlag -eq $false -and (Read-Body $nt[0]).text -like 'VIP ticket alert sent to am@example.com*')
Check 'cw act: no other ticket change' (@(Get-WriteCalls | Where-Object { $_.Method -in @('PATCH', 'PUT') }).Count -eq 0)
Check 'cw act: the token is not in the output' (($o | ConvertTo-Json -Depth 8) -notlike '*pm-token*')
Check 'cw act: the note carries the [vip-ticket-alert] marker' ((Read-Body $nt[0]).text -like '*[[]vip-ticket-alert]*')

# ---- 2b. Rerun (ServiceAI Retry or a Routine) after a good run: nothing is sent or written twice ----
$TWritten = (Read-Body $nt[0]).text
Reset-Mock (Get-Secrets 'connectwise' @{ 'VIP-Companies' = 'Contoso=am@example.com' }) $Handler; Reset-Scenario
$TScenario.cwNotes = @([pscustomobject]@{ id = 9001; text = $TWritten; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false; dateCreated = '2026-10-08T09:00:00Z' })
$f = Invoke-Flow (New-Body @{ })
Check 'rerun: success, already sent' ($f.r.out.status -eq 'success' -and $f.r.out.alerted -eq $false -and $f.r.out.message -like '*already sent*') "$($f.r.out.message) $($f.r.error)"
Check 'rerun: no email and no note' (@(Get-WriteCalls).Count -eq 0) (Show-Calls)

# ---- 3. Not VIP: success, no PSA call at all ----
Reset-Mock (Get-Secrets 'connectwise' @{ 'VIP-Companies' = 'Fabrikam' }) $Handler; Reset-Scenario
$f = Invoke-Flow (New-Body @{ })
$o = $f.r.out
Check 'not VIP: status success with a reason' ($o.status -eq 'success' -and $o.vip -eq $false -and $o.message -like "*Contoso isn't on the VIP list*") "$($o.status) $($o.message) $($f.r.error)"
Check 'not VIP: no calls made' ($Mock.Calls.Count -eq 0) (Show-Calls)

# ---- 4. Autotask: alert already sent for this ticket -> no second alert ----
Reset-Mock (Get-Secrets 'autotask' @{ 'VIP-Companies' = 'Contoso'; 'VIP-AlertTo' = 'am@example.com' }) $Handler; Reset-Scenario
$TScenario.atNotes = @([pscustomobject]@{ id = 1; description = "VIP ticket alert sent to am@example.com by email.`n[vip-ticket-alert]"; publish = 2; createDateTime = '2026-10-08T09:00:00Z' })
$f = Invoke-Flow (New-Body @{ })
$o = $f.r.out
Check 'dedupe: success, not alerted again' ($o.status -eq 'success' -and $o.alerted -eq $false -and $o.message -like '*already sent*') "$($o.message) $($f.r.error)"
Check 'dedupe: nothing sent or written' (@(Get-WriteCalls).Count -eq 0) (Show-Calls)

# ---- 5. Autotask act: recipients from VIP-AlertTo, note Internal Only ----
Reset-Mock (Get-Secrets 'autotask' @{ 'VIP-Companies' = 'Contoso'; 'VIP-AlertTo' = 'am@example.com' }) $Handler; Reset-Scenario
$TScenario.atNotes = @([pscustomobject]@{ id = 1; description = 'VIP ticket alert sent to am@example.com by email.'; publish = 1; createDateTime = '2026-10-08T09:00:00Z' })
$f = Invoke-Flow (New-Body @{ summary = '' })
$o = $f.r.out
$atn = @(Get-Calls 'POST' "$TAT/Tickets/1001/Notes")
Check 'autotask: a public note with the same words does not count as sent' ($o.status -eq 'success' -and $o.alerted -eq $true) "$($o.status) $($f.r.error)"
Check 'autotask: summary read from the ticket, Autotask link' ((Read-Body @(Get-Calls 'POST' $TPM)[0]).TextBody -like '*Summary: Server offline*https://ww5.autotask.example/Mvc/ServiceDesk/TicketDetail.mvc?ticketId=1001*')
Check 'autotask: internal note (publish Internal Only)' ($atn.Count -eq 1 -and (Read-Body $atn[0]).publish -eq 2 -and (Read-Body $atn[0]).noteType -eq 1)

# ---- 6. Zendesk, Postmark not set up: the alert goes in the internal note ----
Reset-Mock (Get-Secrets 'zendesk' @{ 'VIP-Companies' = '@contoso.com=csm@example.com' } -NoPostmark) $Handler; Reset-Scenario
$f = Invoke-Flow (New-Body @{ companyName = 'Contoso Ltd' })
$o = $f.r.out
$zn = @(Get-Calls 'PUT' "$TZD/tickets/1001")
Check 'zendesk: matched on the contact domain' ($f.check.message -like "*matched contact domain '@contoso.com'*") $f.check.message
Check 'zendesk: no Postmark call, status success, not alerted' (-not @(Get-Calls 'POST' $TPM).Count -and $o.status -eq 'success' -and $o.alerted -eq $false) "$($o.status) $($f.r.error)"
Check 'zendesk: private comment carries the alert text' ($zn.Count -eq 1 -and (Read-Body $zn[0]).ticket.comment.public -eq $false -and (Read-Body $zn[0]).ticket.comment.body -like "*Postmark isn't set up*Summary:*https://example.zendesk.com/agent/tickets/1001*" -and (Read-Body $zn[0]).ticket.comment.body -notlike '*secrets)..*')
Check 'zendesk: warning names the Postmark secrets' (@($o.warnings | Where-Object { $_ -like '*Postmark-ServerToken*' }).Count -eq 1)

# ---- 7. Postmark refuses (422): fall back to the internal note ----
Reset-Mock (Get-Secrets 'connectwise' @{ 'VIP-Companies' = 'Contoso=am@example.com' }) $Handler; Reset-Scenario; $TScenario.postmarkFail = 422
$f = Invoke-Flow (New-Body @{ })
$o = $f.r.out
Check 'postmark 422: success with the alert in an internal note' ($o.status -eq 'success' -and $o.alerted -eq $false -and $o.internal_note -like '*HTTP 422*Invalid email request*') "$($o.internal_note) $($f.r.error)"

# ---- 8. Missing PSA permission (403) ----
Reset-Mock (Get-Secrets 'connectwise' @{ 'VIP-Companies' = 'Contoso=am@example.com' }) $Handler; Reset-Scenario; $TScenario.readFail = 403
$f = Invoke-Flow (New-Body @{ })
Check '403 on ticket read: stops at check with a plain error' ($f.stage -eq 'check' -and $f.r.out.status -eq 'error' -and $f.r.error -like '*ConnectWise GET /service/tickets/1001 failed (HTTP 403)*') "$($f.stage) $($f.r.error)"
Check '403 on ticket read: nothing sent' (@(Get-WriteCalls).Count -eq 0)
Reset-Mock (Get-Secrets 'connectwise' @{ 'VIP-Companies' = 'Contoso=am@example.com' }) $Handler; Reset-Scenario; $TScenario.noteFail = 403
$f = Invoke-Flow (New-Body @{ })
Check '403 on the note after the email: error says the email went out' ($f.r.out.status -eq 'error' -and $f.r.out.alerted -eq $true -and $f.r.error -like '*was emailed to am@example.com, but the internal note could not be added*HTTP 403*') $f.r.error
Reset-Mock (Get-Secrets 'connectwise' @{ 'VIP-Companies' = 'Contoso' } -NoPostmark) $Handler; Reset-Scenario; $TScenario.noteFail = 403
$f = Invoke-Flow (New-Body @{ })
Check '403 on the note with no email: error' ($f.r.out.status -eq 'error' -and $f.r.out.alerted -eq $false -and $f.r.error -like '*HTTP 403*') $f.r.error

# ---- 9. Empty and missing input: fail closed ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario
$f = Invoke-Flow (New-Body @{})
Check 'empty VIP list: incomplete, names the secret' ($f.stage -eq 'check' -and $f.r.out.status -eq 'incomplete' -and $f.r.error -like '*VIP-Companies*') $f.r.error
$f = Invoke-Flow (New-Body @{ ticketId = '@TicketId'; vip_list = 'Contoso' })
Check 'literal @TicketId: incomplete' ($f.r.out.status -eq 'incomplete' -and $f.r.error -like '*no ticket number*') $f.r.error
$f = Invoke-Flow (New-Body @{ ticketId = '1001; DROP'; vip_list = 'Contoso' })
Check 'bad ticket id: rejected' ($f.r.out.status -eq 'rejected') $f.r.error
$f = Invoke-Flow @{ ticketId = '1001'; vip_list = 'Contoso' }
Check 'no company or contact: incomplete' ($f.r.out.status -eq 'incomplete') $f.r.error
Check 'fail closed: no calls made' ($Mock.Calls.Count -eq 0) (Show-Calls)
$c = Invoke-Step 'check' $null
Check 'no input at all: incomplete' ($c.out.status -eq 'incomplete') $c.error

# ---- 10. CloudRadial shape, company id entry, alert_to input ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario
$cr = @{ Ticket = @{ TicketId = 1001; Questions = @(@{ Id = 'vip_list'; Value = '42' }, @{ Id = 'alert_to'; Value = 'am@example.com' }) }; Company = @{ CompanyName = 'Contoso'; CompanyPsaId = 42 }; preview = 'true' }
$f = Invoke-Flow $cr
Check 'CloudRadial shape: VIP by PSA company id, preview' ($f.r.out.status -eq 'pending_confirmation' -and $f.check.message -like "*matched company id '42'*" -and (@($f.r.out.recipients) -join ',') -eq 'am@example.com') "$($f.check.message) $($f.r.error)"

# ---- 11. Each later step stands on its own ----
$b = Invoke-Step 'build' $null
Check 'build with no input: error, plain message' ($b.out.status -eq 'error' -and $b.error -like '*Run the workflow from the start*')
$skipCtx = '{"skip":true,"ticket_id":"1001","result":{"status":"success","message":"Fabrikam isn''t on the VIP list.","ticket_id":"1001"}}'
$b = Invoke-Step 'build' ([pscustomobject]@{ ctx_json = $skipCtx })
$s = Invoke-Step 'send' $b.out
Check 'skip passes through build and send unchanged' ($s.out.status -eq 'success' -and $s.out.message -like 'Fabrikam*' -and -not $s.error) $s.error
$s = Invoke-Step 'send' $null
Check 'send with no input: error' ($s.out.status -eq 'error') $s.error

Complete-Test
