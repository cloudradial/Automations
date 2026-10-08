# Strict-mode harness for Status Change Updates.
# Runs each PowerShell step exactly as it is in status-change-updates.yml (shared libraries included),
# through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the runner Key Vault,
# Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked. The AI Prompt step is simulated by handing
# the post step an AI answer (a string, an object, or nothing).
# Placeholder data only (Contoso, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a step variable of the
# same name would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File automationai/status-change-updates/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in automationai/_shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\status-change-updates.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.type==='powershell-script'){o[a.id]=a.properties.script;o[a.id+'.params']=JSON.stringify(a.properties.parameters)}if(a.type==='ai-prompt'){o[a.id+'.prompt']=a.properties.promptTemplate;o[a.id+'.model']=a.properties.model}}console.log(JSON.stringify(o));"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow has detect, write (AI Prompt) and post steps' ($Steps.Contains('detect') -and $Steps.Contains('write.prompt') -and $Steps.Contains('post'))
Check 'AI step reads the detect facts and leaves model blank' ($Steps['write.prompt'] -like '*{{ nodes.detect.output.facts_json }}*' -and $Steps['write.model'] -eq '')
Check 'post step is bound to the detect context and the whole AI output' ($Steps['post.params'] -like '*{{ nodes.detect.output.ctx_json }}*' -and $Steps['post.params'] -like '*{{ nodes.write.output }}*')

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
# detect -> (AI answer) -> post, the way the bindings wire them.
function Invoke-Flow {
    param($Body, $Ai)
    $d = Invoke-Step 'detect' ([pscustomobject]@{ trigger = ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json) })
    if ($d.error) { return @{ stage = 'detect'; r = $d } }
    $p = Invoke-Step 'post' ([pscustomobject]@{ ctx = $d.out.ctx_json; ai = $Ai })
    return @{ stage = 'post'; r = $p; detect = $d.out }
}

# ---- placeholder data ----
$Psa = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://cw.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices5.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
}
function Get-Secrets { param([string]$P) $s = @{}; foreach ($k in $Psa[$P].Keys) { $s[$k] = $Psa[$P][$k] }; return $s }
$TCW = 'https://cw.example.com/v4_6_release/apis/3.0'; $TAT = 'https://webservices5.autotask.example/atservicesrest/v1.0'; $TZD = 'https://example.zendesk.com/api/v2'
$TCwNotesDefault = @(
    [pscustomobject]@{ id = 3; text = 'Called vendor, RMA 5531 opened, cost 240 USD.'; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false; dateCreated = '2026-10-08T10:00:00Z' },
    [pscustomobject]@{ id = 2; text = 'Could you send a photo of the error on the printer screen?'; internalAnalysisFlag = $false; detailDescriptionFlag = $true; resolutionFlag = $false; dateCreated = '2026-10-08T09:30:00Z' },
    [pscustomobject]@{ id = 1; text = 'The printer on floor 2 shows an error and will not print.'; internalAnalysisFlag = $false; detailDescriptionFlag = $true; resolutionFlag = $false; dateCreated = '2026-10-08T09:00:00Z' }
)
$TScenario = @{ cwNotes = $TCwNotesDefault; noteFail = 0; cwStatus = 'Waiting on Client' }
$Handler = {
    param($c, $n)
    $k = "$($c.Method) $($c.Uri)"
    switch -Wildcard -CaseSensitive ($k) {
        "GET $TCW/service/tickets/1001/notes*" { return @($TScenario.cwNotes) }
        "GET $TCW/service/tickets/1001" { return [pscustomobject]@{ id = 1001; summary = 'Printer on floor 2 not printing'; company = [pscustomobject]@{ id = 42 }; status = [pscustomobject]@{ name = $TScenario.cwStatus }; owner = $null } }
        "POST $TCW/service/tickets/1001/notes" { if ($TScenario.noteFail) { New-HttpError $TScenario.noteFail '{"message":"Insufficient security level"}' }; return [pscustomobject]@{ id = 9001 } }
        "GET $TAT/TicketNotes/entityInformation/fields" { return [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                    [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '13'; label = 'System Workflow Note'; isActive = $true }, [pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) } }
        "GET $TAT/Tickets/entityInformation/fields" { return [pscustomobject]@{ fields = @([pscustomobject]@{ name = 'status'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'New'; isActive = $true }, [pscustomobject]@{ value = '5'; label = 'Complete'; isActive = $true }, [pscustomobject]@{ value = '7'; label = 'Waiting Customer'; isActive = $true }) }) } }
        "GET $TAT/Tickets/1001/Notes" { return [pscustomobject]@{ items = @([pscustomobject]@{ id = 1; description = 'Replaced the toner; test page printed.'; publish = 1; createDateTime = '2026-10-08T11:00:00Z' }, [pscustomobject]@{ id = 2; description = 'Internal: toner billed to stock.'; publish = 2; createDateTime = '2026-10-08T11:05:00Z' }) } }
        "GET $TAT/Tickets/1001" { return [pscustomobject]@{ item = [pscustomobject]@{ id = 1001; title = 'Printer out of toner'; description = 'Printer says toner low.'; companyID = 42; status = 5; assignedResourceID = $null } } }
        "POST $TAT/Tickets/1001/Notes" { return [pscustomobject]@{ itemId = 3001 } }
        "GET $TZD/tickets/1001/comments*" { return [pscustomobject]@{ comments = @() } }
        "GET $TZD/tickets/1001" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1001; subject = 'New starter laptop'; description = 'Please set up a laptop for our new starter.'; organization_id = 77; status = 'pending'; assignee_id = $null } } }
        "PUT $TZD/tickets/1001" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1001 } } }
    }
    throw "Unexpected call in test: $k"
}
function Get-WriteCalls { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' }) }
function Reset-Scenario { $TScenario.cwNotes = $TCwNotesDefault; $TScenario.noteFail = 0; $TScenario.cwStatus = 'Waiting on Client' }
$TAiGood = 'We need one more thing from you on ticket 1001: please send a photo of the error on the printer screen. Once we have it, we will carry on straight away.'
$base = @{ ticketId = '1001'; oldStatus = 'New'; newStatus = 'Waiting on Client'; contactEmail = 'megan.bowen@contoso.com' }
function New-Body { param([hashtable]$Over) $b = @{}; foreach ($k in $base.Keys) { $b[$k] = $base[$k] }; foreach ($k in $Over.Keys) { $b[$k] = $Over[$k] }; return $b }

# ---- 1. ConnectWise preview: AI text, nothing posted, internal notes kept out ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario
$f = Invoke-Flow (New-Body @{}) $TAiGood
$o = $f.r.out
Check 'preview: status pending_confirmation, written by the AI' ($o.status -eq 'pending_confirmation' -and $o.written_by -eq 'ai') "$($o.status) $($f.r.error)"
Check 'preview: public_note is the AI text plus the status line' ($o.public_note -eq "$TAiGood`n`n(Status: Waiting on Client)") $o.public_note
Check 'preview: nothing posted' (@(Get-WriteCalls).Count -eq 0) (Show-Calls)
$facts = $f.detect.facts_json | ConvertFrom-Json
Check 'facts: latest public notes and the request, newest first' ($facts.recent_public_updates[0] -like 'Could you send a photo*' -and $facts.request -like 'The printer on floor 2*' -and $facts.new_status -eq 'Waiting on Client' -and $facts.skip -eq $false)
Check 'facts: the internal note never reaches the AI' ($f.detect.facts_json -notlike '*RMA 5531*' -and $f.detect.facts_json -notlike '*240 USD*')

# ---- 2. ConnectWise confirm: public note on the Discussion tab ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario
$f = Invoke-Flow (New-Body @{ confirm = 'true' }) ([pscustomobject]@{ update = $TAiGood })
$o = $f.r.out
$nt = @(Get-Calls 'POST' "$TCW/service/tickets/1001/notes")
Check 'cw confirm: success, posted, AI object answer read' ($o.status -eq 'success' -and $o.posted -eq $true -and $o.written_by -eq 'ai') "$($o.status) $($f.r.error)"
Check 'cw confirm: public note (Discussion), not internal' ($nt.Count -eq 1 -and (Read-Body $nt[0]).detailDescriptionFlag -eq $true -and (Read-Body $nt[0]).internalAnalysisFlag -eq $false -and (Read-Body $nt[0]).text -like '*(Status: Waiting on Client)')
Check 'cw confirm: no status or other ticket change' (@(Get-WriteCalls).Count -eq 1)

# ---- 3. Autotask, status ids, empty AI answer -> template ----
Reset-Mock (Get-Secrets 'autotask') $Handler; Reset-Scenario
$f = Invoke-Flow (New-Body @{ oldStatus = '1'; newStatus = '5'; confirm = $true }) ''
$o = $f.r.out
$atn = @(Get-Calls 'POST' "$TAT/Tickets/1001/Notes")
Check 'autotask: status ids read as names' ($o.old_status -eq 'New' -and $o.new_status -eq 'Complete') "$($o.old_status) $($o.new_status) $($f.r.error)"
Check 'autotask: empty AI -> resolved template, with a warning' ($o.written_by -eq 'template' -and $o.public_note -like 'We believe ticket 1001 (Printer out of toner) is now resolved*' -and @($o.warnings | Where-Object { $_ -like '*AI answer was empty*' }).Count -eq 1) $o.public_note
Check 'autotask: note published to all users' ($atn.Count -eq 1 -and (Read-Body $atn[0]).publish -eq 1)
Check 'autotask: internal note text kept out of the facts' ($f.detect.facts_json -notlike '*billed to stock*' -and $f.detect.facts_json -like '*Replaced the toner*')

# ---- 4. Unusable AI answers -> template ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario
$f = Invoke-Flow (New-Body @{}) 'SKIP'
Check 'AI SKIP on a real change -> template' ($f.r.out.written_by -eq 'template' -and $f.r.out.public_note -like 'We need a little more information from you to keep ticket 1001*') $f.r.out.public_note
$f = Invoke-Flow (New-Body @{}) 'As the internal note says, the vendor RMA is open and we are waiting.'
Check 'AI mentioning internal notes -> template' ($f.r.out.written_by -eq 'template')
$f = Invoke-Flow (New-Body @{}) '{"foo": 1, "bar": 2}'
Check 'AI JSON with no text -> template' ($f.r.out.written_by -eq 'template')
$f = Invoke-Flow (New-Body @{}) "``````text`n`"$TAiGood`"`n``````"
Check 'AI fenced and quoted -> cleaned' ($f.r.out.written_by -eq 'ai' -and $f.r.out.public_note.StartsWith('We need one more thing')) $f.r.out.public_note
$f = Invoke-Flow (New-Body @{ newStatus = 'Escalated to Tier 3 Review'; ignore_statuses = 'Waiting on Vendor' }) $null
Check 'no AI output and an unknown status -> generic template' ($f.r.out.public_note -like 'Ticket 1001 (Printer on floor 2 not printing) is now Escalated to Tier 3 Review*') $f.r.out.public_note
$f = Invoke-Flow (New-Body @{ templates = '{"waiting on client":"Ticket {ticket} needs your reply about {summary}."}' }) ''
Check 'templates input wins over the built-in set' ($f.r.out.public_note -like 'Ticket 1001 needs your reply about Printer on floor 2 not printing.*') $f.r.out.public_note

# ---- 5. Skips: unchanged, ignored, already posted ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario
$f = Invoke-Flow (New-Body @{ oldStatus = 'waiting on client'; confirm = $true }) $TAiGood
Check 'old == new: success, nothing posted, no PSA call' ($f.r.out.status -eq 'success' -and $f.r.out.posted -eq $false -and $f.r.out.message -like '*still Waiting on Client*' -and $Mock.Calls.Count -eq 0) "$($f.r.out.message) $(Show-Calls)"
$f = Invoke-Flow (New-Body @{ newStatus = 'Waiting on Vendor'; confirm = $true }) $TAiGood
Check 'default ignore list: Waiting on Vendor skipped' ($f.r.out.status -eq 'success' -and $f.r.out.message -like '*internal status*' -and @(Get-WriteCalls).Count -eq 0) $f.r.out.message
$f = Invoke-Flow (New-Body @{ newStatus = 'Parts Ordered'; ignore_statuses = 'Parts*, Internal Review'; confirm = $true }) $TAiGood
Check 'custom ignore list with a wildcard' ($f.r.out.message -like '*Parts Ordered is an internal status*' -and @(Get-WriteCalls).Count -eq 0) $f.r.out.message
$TScenario.cwNotes = @([pscustomobject]@{ id = 4; text = "Earlier update.`n`n(Status: Waiting on Client)"; internalAnalysisFlag = $false; detailDescriptionFlag = $true; resolutionFlag = $false; dateCreated = '2026-10-08T12:00:00Z' }) + $TCwNotesDefault
$f = Invoke-Flow (New-Body @{ confirm = $true }) $TAiGood
Check 'already posted for this status: skipped (safe ServiceAI or webhook retry)' ($f.r.out.status -eq 'success' -and $f.r.out.message -like '*already the newest public note*' -and @(Get-WriteCalls).Count -eq 0) $f.r.out.message

# ---- 6. Zendesk: no old status, new status read from the ticket, public comment ----
Reset-Mock (Get-Secrets 'zendesk') $Handler; Reset-Scenario
$f = Invoke-Flow @{ ticketId = '1001'; confirm = $true } 'Thanks for your patience. Ticket 1001 is waiting for a reply from you before we set up the new laptop.'
$zn = @(Get-Calls 'PUT' "$TZD/tickets/1001")
Check 'zendesk: status from the ticket, public comment' ($f.r.out.new_status -eq 'pending' -and $zn.Count -eq 1 -and (Read-Body $zn[0]).ticket.comment.public -eq $true -and (Read-Body $zn[0]).ticket.comment.body -like '*(Status: pending)') "$($f.r.out.new_status) $($f.r.error)"
Check 'zendesk: warning when no contactEmail is sent' (@($f.r.out.warnings | Where-Object { $_ -like '*No contactEmail*' }).Count -eq 1)

# ---- 7. Missing PSA permission (403) on the note ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario; $TScenario.noteFail = 403
$f = Invoke-Flow (New-Body @{ confirm = $true }) $TAiGood
Check '403: error with a plain message naming the call' ($f.r.out.status -eq 'error' -and $f.r.out.posted -eq $false -and $f.r.error -like '*ConnectWise POST /service/tickets/1001/notes failed (HTTP 403)*') $f.r.error

# ---- 8. Empty and missing input: fail closed ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario
$f = Invoke-Flow @{ newStatus = 'Waiting on Client' } $TAiGood
Check 'no ticket number: incomplete, no call' ($f.stage -eq 'detect' -and $f.r.out.status -eq 'incomplete' -and $Mock.Calls.Count -eq 0) $f.r.error
$f = Invoke-Flow @{ ticketId = '@TicketId'; newStatus = 'Waiting on Client' } $TAiGood
Check 'literal @TicketId: incomplete' ($f.r.out.status -eq 'incomplete')
$f = Invoke-Flow @{ ticketId = '10 01' } $TAiGood
Check 'bad ticket number: rejected' ($f.r.out.status -eq 'rejected')
$d = Invoke-Step 'detect' $null
Check 'no input at all: incomplete' ($d.out.status -eq 'incomplete') $d.error
$p = Invoke-Step 'post' ([pscustomobject]@{ ctx = ''; ai = 'x' })
Check 'post with no context: error' ($p.out.status -eq 'error' -and $p.error -like '*Run the workflow from the start*') $p.error

# ---- 9. CloudRadial shape ----
Reset-Mock (Get-Secrets 'connectwise') $Handler; Reset-Scenario
$cr = @{ Ticket = @{ TicketId = 1001; Questions = @(@{ Id = 'oldStatus'; Value = 'New' }, @{ Id = 'newStatus'; Value = 'Waiting on Client' }) }; Company = @{ CompanyName = 'Contoso' } }
$f = Invoke-Flow $cr $TAiGood
Check 'CloudRadial shape: preview built' ($f.r.out.status -eq 'pending_confirmation' -and $f.r.out.ticket_id -eq '1001' -and $f.r.out.old_status -eq 'New') "$($f.r.out.status) $($f.r.error)"

Complete-Test
