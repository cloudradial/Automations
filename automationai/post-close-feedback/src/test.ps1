# Strict-mode harness for Post-Close Feedback.
# Runs each PowerShell step exactly as it is in post-close-feedback.yml (shared libraries included),
# through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the runner Key Vault,
# Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked.
# Placeholder data only (Contoso, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a step variable of the
# same name would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File automationai/post-close-feedback/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in automationai/_shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\post-close-feedback.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.type==='powershell-script'){o[a.id]=a.properties.script;o[a.id+'.params']=JSON.stringify(a.properties.parameters)}}console.log(JSON.stringify(o));"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow has parse, survey and route steps' ($Steps.Contains('parse') -and $Steps.Contains('survey') -and $Steps.Contains('route'))
Check 'parse is bound to the trigger output' ($Steps['parse.params'] -like '*{{ nodes.trigger.output }}*')

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
    $p = Invoke-Step 'parse' ([pscustomobject]@{ trigger = ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json) })
    if ($p.error) { return @{ stage = 'parse'; r = $p } }
    $s = Invoke-Step 'survey' $p.out
    if ($s.error) { return @{ stage = 'survey'; r = $s } }
    $r = Invoke-Step 'route' $s.out
    return @{ stage = 'route'; r = $r; parse = $p.out }
}

# ---- placeholder data ----
$Psa = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://cw.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices5.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
}
$TCommon = @{ 'Postmark-ServerToken' = 'pm-token'; 'Postmark-FromEmail' = 'service@examplemsp.example'; 'CSAT-FeedbackUrl' = 'https://feedback.example.com/csat?ticket={ticketId}&score={score}'; 'CSAT-ServiceManagerEmail' = 'servicemanager@examplemsp.example' }
function Get-Secrets { param([string]$P, [hashtable]$Extra = @{}, [string[]]$Drop = @()) $s = @{}; foreach ($k in $Psa[$P].Keys) { $s[$k] = $Psa[$P][$k] }; foreach ($k in $TCommon.Keys) { if ($Drop -notcontains $k) { $s[$k] = $TCommon[$k] } }; foreach ($k in $Extra.Keys) { $s[$k] = $Extra[$k] }; return $s }
$TCW = 'https://cw.example.com/v4_6_release/apis/3.0'; $TAT = 'https://webservices5.autotask.example/atservicesrest/v1.0'; $TZD = 'https://example.zendesk.com/api/v2'
$TPM = 'https://api.postmarkapp.com/email'; $TCR = 'https://api.cloudradial.example'
$TSurveyNote = "How did we do on ticket 1001 (Printer on floor 2 not printing)?`n`nYour ticket is now closed."
$TScenario = @{ cwNotes = @(); atNotes = @(); zdComments = @(); noteFail = 0; cwStatus = 'Closed' }
$Handler = {
    param($c, $n)
    $k = "$($c.Method) $($c.Uri)"
    switch -Wildcard -CaseSensitive ($k) {
        "POST $TPM" { return [pscustomobject]@{ MessageID = 'pm-0002'; ErrorCode = 0 } }
        "POST $TCR/v2/feedback" { return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ id = 555 } } }
        "GET $TCW/service/tickets/1001/notes*" { return @($TScenario.cwNotes) }
        "GET $TCW/service/tickets/1001" { return [pscustomobject]@{ id = 1001; summary = 'Printer on floor 2 not printing'; company = [pscustomobject]@{ id = 42 }; status = [pscustomobject]@{ name = $TScenario.cwStatus }; owner = $null } }
        "POST $TCW/service/tickets/1001/notes" { if ($TScenario.noteFail) { New-HttpError $TScenario.noteFail '{"message":"Insufficient security level"}' }; return [pscustomobject]@{ id = 9001 } }
        "GET $TAT/TicketNotes/entityInformation/fields" { return [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                    [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '13'; label = 'System Workflow Note'; isActive = $true }, [pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) } }
        "GET $TAT/Tickets/entityInformation/fields" { return [pscustomobject]@{ fields = @([pscustomobject]@{ name = 'status'; picklistValues = @([pscustomobject]@{ value = '5'; label = 'Complete'; isActive = $true }, [pscustomobject]@{ value = '14'; label = 'Duplicate'; isActive = $true }) }) } }
        "GET $TAT/TicketNotes/query*" { return [pscustomobject]@{ items = @($TScenario.atNotes); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
        "GET $TAT/Tickets/1001" { return [pscustomobject]@{ item = [pscustomobject]@{ id = 1001; title = 'Printer out of toner'; description = 'Toner low.'; companyID = 42; status = 5; assignedResourceID = $null } } }
        "POST $TAT/Tickets/1001/Notes" { return [pscustomobject]@{ itemId = 3001 } }
        "GET $TZD/tickets/1001/comments*" { return [pscustomobject]@{ comments = @($TScenario.zdComments) } }
        "GET $TZD/tickets/1001" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1001; subject = 'New starter laptop'; description = 'Set up a laptop.'; organization_id = 77; status = 'solved'; assignee_id = $null } } }
        "PUT $TZD/tickets/1001" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1001 } } }
    }
    throw "Unexpected call in test: $k"
}
function Get-WriteCalls { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' }) }
function Reset-Scenario { $TScenario.cwNotes = @(); $TScenario.atNotes = @(); $TScenario.zdComments = @(); $TScenario.noteFail = 0; $TScenario.cwStatus = 'Closed' }
function New-CwNote { param([string]$Text, [bool]$Public, [int]$Id = 5) return [pscustomobject]@{ id = $Id; text = $Text; internalAnalysisFlag = (-not $Public); detailDescriptionFlag = $Public; resolutionFlag = $false; dateCreated = "2026-10-08T1$($Id):00:00Z" } }

# ---- 1. ConnectWise survey preview ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario
$f = Invoke-Flow @{ ticketId = '1001'; contactEmail = 'megan.bowen@contoso.com'; preview = $true }
$o = $f.r.out
Check 'survey preview: pending_confirmation, nothing posted' ($o.status -eq 'pending_confirmation' -and @(Get-WriteCalls).Count -eq 0) "$($o.status) $($f.r.error) $(Show-Calls)"
Check 'survey preview: five one-click answers with ticket and score' ($o.public_note -like 'How did we do on ticket 1001 (Printer on floor 2 not printing)?*' -and $o.public_note -like '*Excellent (5): https://feedback.example.com/csat?ticket=1001&score=5*' -and $o.public_note -like '*Very poor (1): https://feedback.example.com/csat?ticket=1001&score=1*') $o.public_note
Check 'survey preview: route step returned the survey result' ($o.mode -eq 'survey' -and $o.survey_sent -eq $false)

# ---- 2. ConnectWise survey act: public note ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario
$f = Invoke-Flow @{ ticketId = '1001'; contactEmail = 'megan.bowen@contoso.com' }
$o = $f.r.out
$nt = @(Get-Calls 'POST' "$TCW/service/tickets/1001/notes")
Check 'survey act: success, sent' ($o.status -eq 'success' -and $o.survey_sent -eq $true) "$($o.status) $($f.r.error)"
Check 'survey act: one public note (Discussion tab)' ($nt.Count -eq 1 -and (Read-Body $nt[0]).detailDescriptionFlag -eq $true -and (Read-Body $nt[0]).internalAnalysisFlag -eq $false -and (Read-Body $nt[0]).text -like 'How did we do on ticket 1001*')
Check 'survey act: no email, no other change' (@(Get-WriteCalls).Count -eq 1)

# ---- 3. Survey skips: duplicate, spam reason, already sent ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario; $TScenario.cwStatus = 'Closed - Duplicate'
$f = Invoke-Flow @{ ticketId = '1001' }
Check 'closed as duplicate: success, no survey' ($f.r.out.status -eq 'success' -and $f.r.out.message -like '*closed as Closed - Duplicate*' -and @(Get-WriteCalls).Count -eq 0) "$($f.r.out.message) $($f.r.error)"
Reset-Scenario
$f = Invoke-Flow @{ ticketId = '1001'; close_reason = 'Spam' }
Check 'close reason spam: no survey' ($f.r.out.message -like '*closed as Spam*' -and @(Get-WriteCalls).Count -eq 0) $f.r.out.message
$TScenario.cwNotes = @(New-CwNote $TSurveyNote $true)
$f = Invoke-Flow @{ ticketId = '1001' }
Check 'survey already sent: not sent again (safe retry)' ($f.r.out.status -eq 'success' -and $f.r.out.message -like '*already sent*' -and @(Get-WriteCalls).Count -eq 0) $f.r.out.message
$TScenario.cwNotes = @(New-CwNote $TSurveyNote $false)
$f = Invoke-Flow @{ ticketId = '1001' }
Check 'an internal copy of the survey text does not count as sent' ($f.r.out.survey_sent -eq $true) "$($f.r.out.message) $($f.r.error)"

# ---- 4. Autotask: status id read as a name, Duplicate skipped; survey link without {score} ----
Reset-Mock (Get-Secrets 'autotask') $Handler; Reset-Scenario
$f = Invoke-Flow @{ ticketId = '1001'; status = '14' }
Check 'autotask: status 14 read as Duplicate and skipped' ($f.r.out.message -like '*closed as Duplicate*') $f.r.out.message
$f = Invoke-Flow @{ ticketId = '1001'; feedback_url = 'https://feedback.example.com/rate' }
$atn = @(Get-Calls 'POST' "$TAT/Tickets/1001/Notes")
Check 'autotask: survey link gets ticket and score parameters' ($f.r.out.public_note -like '*Good (4): https://feedback.example.com/rate?ticket=1001&score=4*') $f.r.out.public_note
Check 'autotask: note published to all users' ($atn.Count -eq 1 -and (Read-Body $atn[0]).publish -eq 1)

# ---- 5. Zendesk survey: public comment ----
Reset-Mock (Get-Secrets 'zendesk') $Handler; Reset-Scenario
$f = Invoke-Flow @{ ticketId = '1001'; score_max = '3' }
$zn = @(Get-Calls 'PUT' "$TZD/tickets/1001")
Check 'zendesk: public comment with a 3-point scale' ($zn.Count -eq 1 -and (Read-Body $zn[0]).ticket.comment.public -eq $true -and (Read-Body $zn[0]).ticket.comment.body -like '*3 out of 3: https://*score=3*') "$($f.r.error)"

# ---- 6. Score mode, low score, ConnectWise: email the service manager, internal note ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario; $TScenario.cwNotes = @(New-CwNote $TSurveyNote $true)
$f = Invoke-Flow @{ mode = 'score'; ticketId = '1001'; score = '2'; comment = 'Took three days to hear back.'; contactEmail = 'megan.bowen@contoso.com' }
$o = $f.r.out
$pm = @(Get-Calls 'POST' $TPM)
$nt = @(Get-Calls 'POST' "$TCW/service/tickets/1001/notes")
Check 'low score: success, manager emailed' ($o.status -eq 'success' -and $o.low_score -eq $true -and $o.manager_emailed -eq $true) "$($o.status) $($f.r.error)"
Check 'low score: Postmark email to the service manager with the comment and link' ($pm.Count -eq 1 -and (Read-Body $pm[0]).To -eq 'servicemanager@examplemsp.example' -and (Read-Body $pm[0]).Subject -eq 'Low satisfaction score on ticket 1001: 2 out of 5' -and (Read-Body $pm[0]).TextBody -like '*Took three days*service_recid=1001*')
Check 'low score: internal note records score and email' ($nt.Count -eq 1 -and (Read-Body $nt[0]).internalAnalysisFlag -eq $true -and (Read-Body $nt[0]).text -like 'Satisfaction score received: 2 out of 5 from megan.bowen@contoso.com.*Comment: Took three days*service manager (servicemanager@examplemsp.example) was emailed*')
Check 'low score: no client-visible note' (-not @($nt | Where-Object { (Read-Body $_).detailDescriptionFlag }).Count)
Check 'low score: the note carries the [csat-score] marker' ((Read-Body $nt[0]).text -like '*[[]csat-score]*')

# ---- 6b. Rerun (ServiceAI Retry or a repeated survey click) after a good run: nothing is sent or written twice ----
$TWritten = (Read-Body $nt[0]).text
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario; $TScenario.cwNotes = @((New-CwNote $TWritten $false 6), (New-CwNote $TSurveyNote $true))
$f = Invoke-Flow @{ mode = 'score'; ticketId = '1001'; score = '2'; comment = 'Took three days to hear back.'; contactEmail = 'megan.bowen@contoso.com' }
Check 'rerun: score already recorded, no email and no note' ($f.r.out.status -eq 'success' -and $f.r.out.message -like '*already recorded*' -and @(Get-WriteCalls).Count -eq 0) "$($f.r.out.message) $(Show-Calls)"

# ---- 7. High score: note only ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario; $TScenario.cwNotes = @(New-CwNote $TSurveyNote $true)
$f = Invoke-Flow @{ mode = 'score'; ticketId = '1001'; score = 5 }
Check 'high score: note, no email' ($f.r.out.status -eq 'success' -and $f.r.out.low_score -eq $false -and -not @(Get-Calls 'POST' $TPM).Count -and @(Get-Calls 'POST' "$TCW/service/tickets/1001/notes").Count -eq 1) "$($f.r.error)"
Check 'mode inferred from score' ((Invoke-Flow @{ ticketId = '1001'; score = '4' }).r.out.mode -eq 'score')

# ---- 8. Score preview ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario; $TScenario.cwNotes = @(New-CwNote $TSurveyNote $true)
$f = Invoke-Flow @{ mode = 'score'; ticketId = '1001'; score = '1'; preview = 'true' }
Check 'score preview: pending_confirmation, nothing sent or written' ($f.r.out.status -eq 'pending_confirmation' -and $f.r.out.email_text -like '*rated 1 out of 5*' -and @(Get-WriteCalls).Count -eq 0) "$($f.r.out.status) $(Show-Calls)"

# ---- 9. Score gates: no survey, already scored, bad score ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario
$f = Invoke-Flow @{ mode = 'score'; ticketId = '1001'; score = '1' }
Check 'no survey sent: rejected' ($f.stage -eq 'parse' -and $f.r.out.status -eq 'rejected' -and $f.r.error -like '*No survey was sent*' -and @(Get-WriteCalls).Count -eq 0) $f.r.error
$f = Invoke-Flow @{ mode = 'score'; ticketId = '1001'; score = '1'; require_survey = 'false' }
Check 'require_survey false: accepted' ($f.r.out.status -eq 'success') $f.r.error
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario; $TScenario.cwNotes = @((New-CwNote "Satisfaction score received: 4 out of 5.`n[csat-score]" $false 6), (New-CwNote $TSurveyNote $true))
$f = Invoke-Flow @{ mode = 'score'; ticketId = '1001'; score = '1' }
Check 'already scored: ignored, nothing sent' ($f.r.out.status -eq 'success' -and $f.r.out.message -like '*already recorded*' -and @(Get-WriteCalls).Count -eq 0) $f.r.out.message
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario; $TScenario.cwNotes = @(New-CwNote $TSurveyNote $true)
$f = Invoke-Flow @{ mode = 'score'; ticketId = '1001'; score = '1'; company_psa_id = '99' }
Check 'score from another company (@CompanyPsaId mismatch): rejected, nothing written' ($f.r.out.status -eq 'rejected' -and $f.r.error -like '*different company*' -and @(Get-WriteCalls).Count -eq 0) $f.r.error
$f = Invoke-Flow @{ mode = 'score'; ticketId = '1001'; score = '5'; company_psa_id = '42' }
Check 'score from the same company: accepted' ($f.r.out.status -eq 'success') $f.r.error
foreach ($bad in @('0', '6', 'abc', '2.5')) {
    Reset-Mock (Get-Secrets 'connectwise') $Handler
    $f = Invoke-Flow @{ mode = 'score'; ticketId = '1001'; score = $bad }
    Check "bad score '$bad': rejected" ($f.r.out.status -eq 'rejected' -and $Mock.Calls.Count -eq 0) $f.r.error
}
$f = Invoke-Flow @{ mode = 'score'; ticketId = '1001' }
Check 'score mode with no score: incomplete' ($f.r.out.status -eq 'incomplete') $f.r.error

# ---- 10. Low score, Postmark not set up: the note asks the team to follow up ----
Reset-Mock (Get-Secrets 'connectwise' -Drop @('Postmark-ServerToken')) $Handler; Reset-Scenario; $TScenario.cwNotes = @(New-CwNote $TSurveyNote $true)
$f = Invoke-Flow @{ mode = 'score'; ticketId = '1001'; score = '1' }
Check 'no Postmark: success, not emailed, note asks for follow-up' ($f.r.out.status -eq 'success' -and $f.r.out.manager_emailed -eq $false -and $f.r.out.internal_note -like "*email was not sent because Postmark isn't set up*follow up*" -and $f.r.out.internal_note -notlike '*secret)..*') $f.r.out.internal_note

# ---- 11. Autotask low score recorded as CloudRadial feedback ----
Reset-Mock (Get-Secrets 'autotask' @{ 'CloudRadial-BaseUrl' = $TCR; 'CloudRadial-PublicKey' = 'crpub'; 'CloudRadial-PrivateKey' = 'crpriv' }) $Handler; Reset-Scenario
$TScenario.atNotes = @([pscustomobject]@{ id = 1; description = "How did we do on ticket 1001 (Printer out of toner)?"; publish = 1; createDateTime = '2026-10-08T09:00:00Z' })
$f = Invoke-Flow @{ mode = 'score'; ticketId = '1001'; score = '2'; cr_company_id = '9'; contactEmail = 'megan.bowen@contoso.com' }
$fb = @(Get-Calls 'POST' "$TCR/v2/feedback")
$atn = @(Get-Calls 'POST' "$TAT/Tickets/1001/Notes")
Check 'autotask score: CloudRadial feedback posted (negative, ticket and company ids)' ($f.r.out.cloudradial_recorded -eq $true -and $fb.Count -eq 1 -and (Read-Body $fb[0]).companyId -eq 9 -and (Read-Body $fb[0]).feedbackRating -eq -1 -and (Read-Body $fb[0]).ticketPsaId -eq 1001 -and (Read-Body $fb[0]).feedbackRatingNumber -eq 2) "$($f.r.error) $(Show-Calls)"
Check 'autotask score: internal note (Internal Only)' ($atn.Count -eq 1 -and (Read-Body $atn[0]).publish -eq 2)
Reset-Mock (Get-Secrets 'autotask') $Handler
$f = Invoke-Flow @{ mode = 'score'; ticketId = '1001'; score = '5'; cr_company_id = '9' }
Check 'no CloudRadial secrets: warning, still success' ($f.r.out.status -eq 'success' -and $f.r.out.cloudradial_recorded -eq $false -and @($f.r.out.warnings | Where-Object { $_ -like '*CloudRadial-BaseUrl*' }).Count -eq 1) $f.r.error

# ---- 12. Missing PSA permission (403) on the note ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario; $TScenario.noteFail = 403
$f = Invoke-Flow @{ ticketId = '1001' }
Check '403 on the survey note: error naming the call' ($f.stage -eq 'survey' -and $f.r.out.status -eq 'error' -and $f.r.error -like '*ConnectWise POST /service/tickets/1001/notes failed (HTTP 403)*') $f.r.error
$TScenario.cwNotes = @(New-CwNote $TSurveyNote $true)
$f = Invoke-Flow @{ mode = 'score'; ticketId = '1001'; score = '1' }
Check '403 after the manager email: error says the email went out' ($f.r.out.status -eq 'error' -and $f.r.out.manager_emailed -eq $true -and $f.r.error -like '*service manager was emailed*HTTP 403*') $f.r.error

# ---- 13. Empty and missing input ----
Reset-Mock (Get-Secrets 'connectwise' -Drop @('CSAT-FeedbackUrl')) $Handler; Reset-Scenario
$f = Invoke-Flow @{ ticketId = '1001' }
Check 'no survey link: incomplete, names the secret, no call' ($f.r.out.status -eq 'incomplete' -and $f.r.error -like '*CSAT-FeedbackUrl*' -and $Mock.Calls.Count -eq 0) $f.r.error
$f = Invoke-Flow @{ ticketId = '1001'; feedback_url = 'http://feedback.example.com/rate' }
Check 'plain http survey link: rejected' ($f.r.out.status -eq 'rejected')
$f = Invoke-Flow @{ ticketId = '@TicketId' }
Check 'literal @TicketId: incomplete' ($f.r.out.status -eq 'incomplete')
$f = Invoke-Flow @{ ticketId = '1001'; mode = 'delete' }
Check 'unknown mode: rejected' ($f.r.out.status -eq 'rejected')
$p = Invoke-Step 'parse' $null
Check 'no input at all: incomplete' ($p.out.status -eq 'incomplete') $p.error
$r = Invoke-Step 'route' $null
Check 'route with no input: error' ($r.out.status -eq 'error') $r.error

# ---- 14. CloudRadial shape (score from a portal form) ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario; $TScenario.cwNotes = @(New-CwNote $TSurveyNote $true)
$cr = @{ Ticket = @{ TicketId = 2222; Questions = @(@{ Id = 'ticketId'; Value = '1001' }, @{ Id = 'score'; Value = '5' }, @{ Id = 'comment'; Value = 'Quick and friendly.' }) }; Company = @{ CompanyName = 'Contoso'; CompanyId = 9 } }
$f = Invoke-Flow $cr
Check 'CloudRadial shape: the answered ticket (question) wins over the form ticket' ($f.r.out.status -eq 'success' -and $f.r.out.ticket_id -eq '1001' -and $f.r.out.score -eq 5) "$($f.r.out.ticket_id) $($f.r.error)"

Complete-Test
