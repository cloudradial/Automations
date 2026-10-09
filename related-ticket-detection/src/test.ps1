# Strict-mode harness for Duplicate / Related Ticket Detection.
# Runs each PowerShell step exactly as it is in related-ticket-detection.yml (shared libraries
# psa.ps1, psa-tickets.ps1 and plan.ps1 included), through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest,
# with the runner Key Vault, Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked. The AI Prompt
# step is simulated by handing the write step a judgment string.
# Placeholder data only (Contoso, Fabrikam, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a step variable such as $t or $c
# would hide a same-named test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File related-ticket-detection/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

# ---- the steps, straight from the built workflow ----
$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\related-ticket-detection.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.type==='powershell-script')o[a.id]=a.properties.script;if(a.type==='ai-prompt'){o[a.id+'.prompt']=a.properties.promptTemplate;o[a.id+'.model']=a.properties.model;}}console.log(JSON.stringify(o));"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow has gather and write steps' ($Steps.Contains('gather') -and $Steps.Contains('write'))
Check 'judge prompt reads the gather output' ($Steps['judge.prompt'] -like '*{{ nodes.gather.output.facts_json }}*')
Check 'judge model is blank' ($Steps['judge.model'] -eq '')
Check '_shared/psa-tickets.ps1 is pasted into both PSA steps' ($Steps['gather'] -like '*function Find-PsaTickets*' -and $Steps['write'] -like '*function Add-PsaTicketRelation*')
Check '_shared/psa-tickets.ps1 in the yml matches the source' ($Steps['gather'].Contains((Get-Content -Raw (Join-Path $Shared 'psa-tickets.ps1')).Replace("`r`n", "`n").TrimEnd()))
Check 'no local psa-extra.ps1 left' (-not (Test-Path (Join-Path $PSScriptRoot 'psa-extra.ps1')) -and $Steps['gather'] -notlike '*# >>> src/psa-extra.ps1*')

# ---- runner mocks ----
$global:NodeIn = $null; $global:NodeParams = @{}; $global:NodeOut = $null
function Get-NodeInput { param([string]$Name) if ($Name) { if ($global:NodeParams.Contains($Name)) { return $global:NodeParams[$Name] }; return $null }; return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Invoke-Step {
    param([string]$Id, $In = $null, [hashtable]$Params = @{})
    $global:NodeIn = $In; $global:NodeParams = $Params; $global:NodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps[$Id])) } catch { $err = [string]$_.Exception.Message }
    $o = $null; if ($null -ne $global:NodeOut) { $o = ($global:NodeOut | ConvertTo-Json -Depth 12 | ConvertFrom-Json) }
    return @{ out = $o; error = $err }
}
# gather -> (AI text) -> write, the way the bindings wire them.
function Invoke-Flow {
    param($Body, [string]$Ai)
    $g = Invoke-Step 'gather' ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    if ($g.error) { return @{ stage = 'gather'; r = $g } }
    $o = $g.out
    $w = Invoke-Step 'write' $null @{ request = $o.request_json; source = $o.source_json; candidates = $o.candidates_json; suggested = $o.suggested_json; warnings_json = $o.warnings_json; actions_json = $o.actions_json; judgment = $Ai }
    return @{ stage = 'write'; r = $w; gather = $o }
}

# ---- placeholder data ----
$Psa = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://api-na.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices5.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    halopsa     = @{ 'PSA-Type' = 'halopsa'; 'Halo-ApiUrl' = 'https://halo.example.com'; 'Halo-ClientId' = 'hid'; 'Halo-ClientSecret' = 'hsec' }
    kaseyabms   = @{ 'PSA-Type' = 'kaseyabms'; 'KaseyaBMS-ApiUrl' = 'https://bms.example.com'; 'KaseyaBMS-Username' = 'api'; 'KaseyaBMS-Password' = 'pw'; 'KaseyaBMS-CompanyName' = 'examplemsp'; 'KaseyaBMS-NoteTypeId' = '3' }
    syncro      = @{ 'PSA-Type' = 'syncro'; 'Syncro-ApiUrl' = 'https://examplemsp.syncromsp.com/api/v1'; 'Syncro-ApiKey' = 'key' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
}
$TCW = 'https://api-na.example.com/v4_6_release/apis/3.0'; $TAT = 'https://webservices5.autotask.example/atservicesrest/v1.0'; $TZD = 'https://example.zendesk.com/api/v2'
$THA = 'https://halo.example.com'; $TKB = 'https://bms.example.com/v2'; $TSY = 'https://examplemsp.syncromsp.com/api/v1'
$TNow = (Get-Date).ToUniversalTime()
function TAgo { param([double]$Days) return $TNow.AddDays(-$Days).ToString('yyyy-MM-ddTHH:mm:ssZ') }
$TS = @{ list403 = $false; empty = $false }
# Notes written during a test, by ticket id, so a rerun sees the markers the first run left.
$TNotes = @{}
function TNote { param([string]$Id) if (-not $TNotes.Contains($Id)) { $TNotes[$Id] = New-Object System.Collections.ArrayList }; return , $TNotes[$Id] }
function TReset { param($Secrets) Reset-Mock $Secrets $Handler; $TNotes.Clear() }

# ConnectWise: 1001 is the new ticket; 1002 is the same Outlook fault from the same contact; 1003 and 1004 are unrelated.
# 2001 is Fabrikam's (another company); 1005 is closed.
function TCwTicket { param($Id, $Sum, $Contact, $Days, $Co = 42, $Closed = $false) return [pscustomobject]@{ id = $Id; summary = $Sum; company = [pscustomobject]@{ id = $Co }; contact = [pscustomobject]@{ id = $Contact; name = "Contact $Contact" }; status = [pscustomobject]@{ name = $(if ($Closed) { 'Closed' } else { 'New' }) }; closedFlag = $Closed; dateEntered = (TAgo $Days); owner = $null } }
$TCwTickets = @{
    '1001' = (TCwTicket 1001 'Outlook keeps crashing when opening the calendar' 7 0.1)
    '1002' = (TCwTicket 1002 'Outlook crashing on calendar open' 7 1)
    '1003' = (TCwTicket 1003 'New laptop for starter' 8 2)
    '1004' = (TCwTicket 1004 'Printer offline in reception' 9 3)
    '1005' = (TCwTicket 1005 'Outlook calendar crash' 7 2 42 $true)
    '2001' = (TCwTicket 2001 'Outlook crashing on calendar open' 50 1 77)
}
$TDesc = @{ '1001' = 'Since this morning Outlook closes when I click the calendar. Megan, Contoso.'; '1002' = 'Outlook closes as soon as I open my calendar.'; '1003' = 'Please order a laptop.'; '1004' = 'The reception printer shows offline.'; '1005' = 'old'; '2001' = 'Fabrikam data' }

$Handler = {
    param($c, $n)
    $k = "$($c.Method) $($c.Uri)"
    switch -Wildcard -CaseSensitive ($k) {
        # ---- ConnectWise ----
        "GET $TCW/company/companies*" { if ([uri]::UnescapeDataString($c.Uri) -like "*Contoso*") { return , @([pscustomobject]@{ id = 42; name = 'Contoso' }) }; return , @() }
        "GET $TCW/service/tickets/*/configurations*" { return , @() }
        "GET $TCW/service/tickets/*/notes*" { $id = ($c.Uri -split '/service/tickets/')[1].Split('/')[0]; if ($c.Uri -notlike '*page=1' -and $c.Uri -like '*page=*') { return , @() }; return , @(@([pscustomobject]@{ id = 1; text = $TDesc[$id]; internalAnalysisFlag = $false; detailDescriptionFlag = $true }) + @(TNote $id | ForEach-Object { [pscustomobject]@{ id = 2; text = $_; internalAnalysisFlag = $true; detailDescriptionFlag = $false } })) }
        "GET $TCW/service/tickets?conditions=*" {
            if ($TS.list403) { New-HttpError 403 '{"code":"Forbidden","message":"You do not have access to Service Tickets."}' }
            if ($TS.empty) { return , @() }
            return , @($TCwTickets['1004'], $TCwTickets['1003'], $TCwTickets['1002'], $TCwTickets['1001'])
        }
        "GET $TCW/service/tickets/*" { $id = ($c.Uri -split '/service/tickets/')[1].Split('?')[0]; if ($TCwTickets.Contains($id)) { return $TCwTickets[$id] }; New-HttpError 404 '{"message":"Ticket not found"}' }
        "POST $TCW/service/tickets/*/notes" { $id = ($c.Uri -split '/service/tickets/')[1].Split('/')[0]; $null = (TNote $id).Add((Read-Body $c).text); return [pscustomobject]@{ id = 9001 } }
        # ---- Autotask ----
        "GET $TAT/Tickets/entityInformation/fields" { return [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'status'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'New'; isActive = $true }, [pscustomobject]@{ value = '5'; label = 'Complete'; isActive = $true }) },
                    [pscustomobject]@{ name = 'ticketType'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'Service Request'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Incident'; isActive = $true }, [pscustomobject]@{ value = '4'; label = 'Problem'; isActive = $true }) }) } }
        "GET $TAT/TicketNotes/entityInformation/fields" { return [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                    [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '13'; label = 'System Workflow Note'; isActive = $true }, [pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) } }
        "GET $TAT/Tickets/query?search=*" {
            $s = [uri]::UnescapeDataString(($c.Uri -split 'search=')[1]) | ConvertFrom-Json
            if (@($s.filter | Where-Object { $_.field -eq 'ticketNumber' }).Count) { return [pscustomobject]@{ items = @([pscustomobject]@{ id = 5001; ticketNumber = 'T20261008.0001' }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
            return [pscustomobject]@{ items = @(
                    [pscustomobject]@{ id = 5002; ticketNumber = 'T20261007.0004'; title = 'VPN drops every few minutes'; description = 'The VPN disconnects for everyone at the branch.'; companyID = 42; status = 1; contactID = 11; configurationItemID = 77; createDate = (TAgo 1); ticketType = 4 },
                    [pscustomobject]@{ id = 5003; ticketNumber = 'T20261006.0002'; title = 'Request new mailbox'; description = 'New shared mailbox please.'; companyID = 42; status = 1; contactID = 12; createDate = (TAgo 2); ticketType = 1 },
                    [pscustomobject]@{ id = 5009; ticketNumber = 'T20261006.0009'; title = 'VPN drops'; description = 'Fabrikam VPN'; companyID = 77; status = 1; contactID = 99; createDate = (TAgo 2); ticketType = 1 }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } }
        }
        "GET $TAT/Tickets/5001" { return [pscustomobject]@{ item = [pscustomobject]@{ id = 5001; ticketNumber = 'T20261008.0001'; title = 'VPN keeps dropping'; description = 'VPN disconnects every few minutes at the branch office.'; companyID = 42; status = 1; contactID = 10; configurationItemID = 77; createDate = (TAgo 0.1); ticketType = 1; assignedResourceID = $null } } }
        "GET $TAT/Tickets/5002" { return [pscustomobject]@{ item = [pscustomobject]@{ id = 5002; title = 'VPN drops every few minutes'; companyID = 42; status = 1; ticketType = 4; createDate = (TAgo 1) } } }
        "GET $TAT/Companies/query*" { return [pscustomobject]@{ items = @([pscustomobject]@{ id = 42; companyName = 'Contoso' }) } }
        "PATCH $TAT/Tickets" { return [pscustomobject]@{ itemId = 5001 } }
        "POST $TAT/Tickets/*/Notes" { $null = (TNote ([string](Read-Body $c).ticketID)).Add((Read-Body $c).description); return [pscustomobject]@{ itemId = 3001 } }
        "GET $TAT/TicketNotes/query?search=*" { $s = [uri]::UnescapeDataString(($c.Uri -split 'search=')[1]) | ConvertFrom-Json; $tid = [string]@($s.filter)[0].value; return [pscustomobject]@{ items = @(TNote $tid | ForEach-Object { [pscustomobject]@{ id = 1; ticketID = [long]$tid; title = 'Note'; description = $_; publish = 2; noteType = 1; createDateTime = (TAgo 0) } }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
        # ---- HaloPSA ----
        "POST $THA/auth/token" { return [pscustomobject]@{ access_token = 'halo-token' } }
        "GET $THA/api/Client?search=*" { return [pscustomobject]@{ clients = @([pscustomobject]@{ id = 42; name = 'Contoso' }) } }
        "GET $THA/api/Tickets/4001?includedetails=true" { return [pscustomobject]@{ id = 4001; summary = 'Teams calls dropping'; details = 'Teams calls drop after a minute.'; client_id = 42; status_id = 1; user_id = 5; dateoccurred = (TAgo 0.1); agent_id = $null } }
        "GET $THA/api/Tickets?*client_id=42*" { return [pscustomobject]@{ record_count = 1; tickets = @([pscustomobject]@{ id = 4000; summary = 'Teams calls drop'; details = 'Calls in Teams drop.'; client_id = 42; status_id = 1; user_id = 6; dateoccurred = (TAgo 1); hasbeenclosed = $false }) } }
        "POST $THA/api/Tickets" { return , @([pscustomobject]@{ id = 4001 }) }
        "POST $THA/api/Actions" { $b = @(Read-Body $c)[0]; $null = (TNote ([string]$b.ticket_id)).Add($b.note); return , @([pscustomobject]@{ id = 1 }) }
        "GET $THA/api/Actions?ticket_id=*" { $tid = (($c.Uri -split 'ticket_id=')[1] -split '&')[0]; return [pscustomobject]@{ actions = @(TNote $tid | ForEach-Object { [pscustomobject]@{ id = 1; note = $_; hiddenfromuser = $true; datetime = (TAgo 0) } }) } }
        # ---- Zendesk ----
        "GET $TZD/organizations/autocomplete*" { return [pscustomobject]@{ organizations = @([pscustomobject]@{ id = 42; name = 'Contoso' }) } }
        "GET $TZD/tickets/3001" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 3001; subject = 'Cannot print to the office printer'; description = 'Printing fails with an error.'; organization_id = 42; requester_id = 9; status = 'new'; created_at = (TAgo 0.1); type = 'question' } } }
        "GET $TZD/tickets/3002" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 3002; subject = 'Office printer error'; organization_id = 42; status = 'open'; type = 'question'; created_at = (TAgo 1) } } }
        "GET $TZD/search?query=*" { return [pscustomobject]@{ results = @([pscustomobject]@{ id = 3002; subject = 'Office printer error'; description = 'The office printer shows an error when printing.'; organization_id = 42; requester_id = 9; status = 'open'; created_at = (TAgo 1); type = 'question' }); next_page = $null } }
        "GET $TZD/tickets/*/comments*" { $tid = ($c.Uri -split '/tickets/')[1].Split('/')[0]; return [pscustomobject]@{ comments = @(TNote $tid | ForEach-Object { [pscustomobject]@{ id = 1; body = $_; public = $false; author_id = 1; created_at = (TAgo 0) } }); next_page = $null } }
        "PUT $TZD/tickets/*" { $tid = ($c.Uri -split '/tickets/')[1].Split('/')[0].Split('?')[0]; $b = Read-Body $c; if ($b.ticket.PSObject.Properties['comment']) { $null = (TNote $tid).Add($b.ticket.comment.body) }; return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1 } } }
        # ---- Kaseya BMS and Syncro (list shape only) ----
        "POST $TKB/security/authenticate" { return [pscustomobject]@{ Result = [pscustomobject]@{ AccessToken = 'bms-token' } } }
        "GET $TKB/servicedesk/tickets?Filter.*" { return [pscustomobject]@{ Result = @([pscustomobject]@{ Id = 61; TicketNumber = 'T20261007.0001'; Title = 'Email bouncing'; AccountId = 42; StatusName = 'New'; OpenDate = (TAgo 1) }, [pscustomobject]@{ Id = 62; Title = 'Done'; AccountId = 42; StatusName = 'Completed'; OpenDate = (TAgo 1) }, [pscustomobject]@{ Id = 63; Title = 'Other'; AccountId = 77; StatusName = 'New'; OpenDate = (TAgo 1) }) } }
        "GET $TSY/tickets?*customer_id=42*" { return [pscustomobject]@{ tickets = @([pscustomobject]@{ id = 71; number = 1071; subject = 'Wi-Fi slow'; customer_id = 42; status = 'New'; contact_id = 3; created_at = (TAgo 1) }, [pscustomobject]@{ id = 72; number = 1072; subject = 'Old'; customer_id = 42; status = 'New'; created_at = (TAgo 30) }); meta = [pscustomobject]@{ total_pages = 1 } } }
        "GET $TSY/tickets?number=*" { return [pscustomobject]@{ tickets = @([pscustomobject]@{ id = 71; number = 1071 }) } }
    }
    throw "Unexpected call in test: $k"
}
function Get-WriteCalls { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and $_.Uri -notlike '*/auth/token' -and $_.Uri -notlike '*/security/authenticate' }) }
function Test-NoMerge { return -not @($Mock.Calls | Where-Object { $_.Method -eq 'DELETE' -or $_.Uri -match '(?i)merge|attachChildren' -or ($_.Body -match '(?i)"status"|closedFlag|"solved"|"closed"') }).Count }

$aiDup = '{"matches":[{"id":"1002","relation":"duplicate","confidence":0.92,"reason":"Same contact reporting the same Outlook calendar crash a day apart."}]}'
$base = @{ ticketId = '1001'; companyName = 'Contoso'; triggerSource = 'serviceai-triage' }
function New-Body { param([hashtable]$Over) $b = @{}; foreach ($k in $base.Keys) { $b[$k] = $base[$k] }; foreach ($k in $Over.Keys) { $b[$k] = $Over[$k] }; return $b }

# ---- 1. ConnectWise, confirm false: note written, nothing linked ----
TReset $Psa.connectwise; $TS.list403 = $false; $TS.empty = $false
$f = Invoke-Flow (New-Body @{}) $aiDup
$o = $f.r.out
Check 'cw preview: reached the write step' ($f.stage -eq 'write' -and -not $f.r.error) "$($f.stage) $($f.r.error) $($f.gather | ConvertTo-Json -Depth 3)"
Check 'cw preview: status pending_confirmation' ($o.status -eq 'pending_confirmation') $o.status
Check 'cw preview: list scoped to company 42 and open tickets' (@(Get-Calls 'GET' "$TCW/service/tickets?conditions=*" | Where-Object { [uri]::UnescapeDataString($_.Uri) -like '*closedFlag=false and company/id=42 and dateEntered>=*' }).Count -eq 1) (Show-Calls)
Check 'cw preview: shortlist puts 1002 first and leaves out the printer ticket' (@($f.gather.candidates_json | ConvertFrom-Json)[0].id -eq '1002' -and -not @(($f.gather.candidates_json | ConvertFrom-Json) | Where-Object { $_.id -eq '1004' }).Count) $f.gather.candidates_json
Check 'cw preview: 1002 flagged same contact' (@($f.gather.candidates_json | ConvertFrom-Json)[0].sameContact -eq $true)
Check 'cw preview: one internal note, on 1001 only' (@(Get-WriteCalls).Count -eq 1 -and (Get-WriteCalls)[0].Uri -eq "$TCW/service/tickets/1001/notes" -and (Read-Body (Get-WriteCalls)[0]).internalAnalysisFlag -eq $true) (Show-Calls)
Check 'cw preview: note lists #1002 as a duplicate with a link' ($o.internal_note -like '*Possible duplicates:*#1002*92% confident*https://na.example.com/v4_6_release/services/system_io/Service/fv_sr100_request.rails?service_recid=1002*') $o.internal_note
Check 'cw preview: note says how to link and that nothing is merged' ($o.internal_note -like '*confirm set to true*' -and $o.internal_note -like '*never merges or closes*')
Check 'cw preview: chatReply names the match' ($o.chatReply -like '*#1002 (duplicate)*confirm=true*') $o.chatReply
Check 'cw preview: planned one relation' (@($o.planned).Count -eq 1 -and $o.counts.linked -eq 0) ($o.planned -join ' | ')
Check 'cw preview: AI decided' ($o.classified_by -eq 'ai')

# ---- 2. ConnectWise, confirm true: cross-reference note on 1002, summary note on 1001 ----
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ confirm = $true }) $aiDup
$o = $f.r.out
Check 'cw confirm: status success' ($o.status -eq 'success') "$($o.status) $($o.message) $($f.r.error)"
Check 'cw confirm: cross-reference note on 1002' (@(Get-Calls 'POST' "$TCW/service/tickets/1002/notes").Count -eq 1 -and (Read-Body (Get-Calls 'POST' "$TCW/service/tickets/1002/notes")[0]).text -like '*#1001*Nothing was merged or closed*') (Show-Calls)
Check 'cw confirm: summary note on 1001 says linked' (@(Get-Calls 'POST' "$TCW/service/tickets/1001/notes").Count -eq 1 -and $o.internal_note -like '*Linked:*notes only*') $o.internal_note
Check 'cw confirm: nothing merged, closed or patched' ((Test-NoMerge) -and -not @(Get-Calls 'PATCH' '*').Count) (Show-Calls)
Check 'cw confirm: linked count 1' ($o.counts.linked -eq 1)

# ---- 2b. rerun (ServiceAI Retry or a Routine): the same confirmed run writes nothing twice ----
Reset-Mock $Psa.connectwise $Handler
$f = Invoke-Flow (New-Body @{ confirm = $true }) $aiDup
$o = $f.r.out
Check 'cw rerun: no second summary or cross-reference note' (-not @(Get-Calls 'POST' "$TCW/service/tickets/*/notes").Count) (Show-Calls)
Check 'cw rerun: still success, note_written false' ($o.status -eq 'success' -and $o.note_written -eq $false) "$($o.status) $($o.note_written)"
Check 'cw rerun: one copy of each note' ((TNote '1001').Count -eq 1 -and (TNote '1002').Count -eq 1 -and (TNote '1001')[0] -like '*`[related ticket check 1001 done 1002`]') ((TNote '1001') -join ' | ')
# A preview first, then the confirmed run: both summary notes are written once (they say different things).
TReset $Psa.connectwise
$null = Invoke-Flow (New-Body @{}) $aiDup
$null = Invoke-Flow (New-Body @{}) $aiDup
$null = Invoke-Flow (New-Body @{ confirm = $true }) $aiDup
Check 'cw preview twice then confirm: two summary notes on 1001, one cross-reference on 1002' ((TNote '1001').Count -eq 2 -and (TNote '1002').Count -eq 1) ((TNote '1001') -join ' | ')

# ---- 3. addNote false and confirm false: a pure preview writes nothing ----
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ addNote = $false }) $aiDup
Check 'pure preview: nothing written' (@(Get-WriteCalls).Count -eq 0 -and $f.r.out.status -eq 'pending_confirmation' -and $f.r.out.internal_note -like '*#1002*') (Show-Calls)

# ---- 4. empty result ----
TReset $Psa.connectwise; $TS.empty = $true
$f = Invoke-Flow (New-Body @{ confirm = $true }) '{"matches":[]}'
$o = $f.r.out
Check 'empty: status success, no match message' ($o.status -eq 'success' -and $o.message -like 'No related open tickets*') "$($o.status) $($o.message) $($f.r.error)"
Check 'empty: nothing written (noteWhenNone is off)' (@(Get-WriteCalls).Count -eq 0) (Show-Calls)
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ noteWhenNone = $true }) '{"matches":[]}'
Check 'empty with noteWhenNone: one note saying nothing matched' (@(Get-WriteCalls).Count -eq 1 -and $f.r.out.internal_note -like '*No open ticket for this company looks like the same issue*') "$(Show-Calls) $($f.r.out.internal_note)"
$TS.empty = $false

# ---- 5. missing permission (403) ----
TReset $Psa.connectwise; $TS.list403 = $true
$f = Invoke-Flow (New-Body @{}) $aiDup
Check '403: stops in gather with status error' ($f.stage -eq 'gather' -and $f.r.out.status -eq 'error') "$($f.stage) $($f.r.out.status)"
Check '403: message names the HTTP 403, the PSA and the permission' ($f.r.out.message -like '*ConnectWise*list tickets*HTTP 403*permission to read service tickets*') $f.r.out.message
Check '403: nothing written' (@(Get-WriteCalls).Count -eq 0)
$TS.list403 = $false

# ---- 6. ServiceAI picks are checked: other company, closed and missing tickets are dropped ----
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ relatedTicketIds = '1002, #2001; 1005 9999'; reason = 'Same Outlook calendar crash.' }) $aiDup
$o = $f.r.out
$TSug = @($f.gather.suggested_json | ConvertFrom-Json)
Check 'suggested: 1002 valid' (@($TSug | Where-Object { $_.ref -eq '1002' -and $_.valid }).Count -eq 1) $f.gather.suggested_json
Check 'suggested: Fabrikam ticket 2001 dropped as another company' (@($TSug | Where-Object { $_.ref -eq '2001' -and -not $_.valid -and $_.why -like '*different company*' }).Count -eq 1)
Check 'suggested: closed 1005 and missing 9999 dropped' (@($TSug | Where-Object { $_.ref -eq '1005' -and $_.why -like '*closed*' }).Count -eq 1 -and @($TSug | Where-Object { $_.ref -eq '9999' -and $_.why -like '*not found*' }).Count -eq 1)
Check 'suggested: Fabrikam data never reaches the AI or the note' ($f.gather.facts_json -notlike '*2001*' -and $o.internal_note -notlike '*Fabrikam data*') $f.gather.facts_json
Check 'suggested: warnings explain the drops' (@($o.warnings | Where-Object { $_ -like '*2001*different company*' }).Count -eq 1)

# ---- 7. AI answer empty: ServiceAI pick kept, word matches only listed ----
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ relatedTicketIds = '1002'; reason = 'Same Outlook calendar crash.'; confirm = $true }) ''
$o = $f.r.out
Check 'no AI: classified by rules, ServiceAI pick linked' ($o.classified_by -eq 'rules' -and @($o.matches).Count -eq 1 -and $o.matches[0].id -eq '1002' -and $o.counts.linked -eq 1) "$($o.classified_by) $($o | ConvertTo-Json -Depth 4)"
Check 'no AI: warning says the AI answer was empty' (@($o.warnings | Where-Object { $_ -like '*AI answer was empty*' }).Count -eq 1)
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ confirm = $true }) 'not json at all'
Check 'unreadable AI and no ServiceAI pick: nothing linked' ($f.r.out.counts.linked -eq 0 -and -not @(Get-Calls 'POST' "$TCW/service/tickets/1002/notes").Count) (Show-Calls)

# ---- 8. AI names a ticket that wasn't shortlisted ----
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ confirm = $true }) '{"matches":[{"id":"2001","relation":"duplicate","confidence":0.99,"reason":"x"}]}'
Check 'AI off-list id ignored' (@($f.r.out.matches).Count -eq 0 -and @($f.r.out.warnings | Where-Object { $_ -like '*2001*not on the shortlist*' }).Count -eq 1 -and -not @(Get-Calls 'POST' "$TCW/service/tickets/2001/notes").Count) ($f.r.out | ConvertTo-Json -Depth 4)
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{}) '{"matches":[{"id":"1002","relation":"related","confidence":0.4,"reason":"maybe"}]}'
Check 'low-confidence pick ignored' (@($f.r.out.matches).Count -eq 0 -and $f.r.out.status -eq 'success')

# ---- 9. wrong company and bad input fail closed ----
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ companyName = 'Fabrikam' }) $aiDup
Check 'company mismatch: rejected in gather, nothing written' ($f.stage -eq 'gather' -and $f.r.out.status -eq 'rejected' -and @(Get-WriteCalls).Count -eq 0) "$($f.stage) $($f.r.out.status) $($f.r.out.message)"
TReset $Psa.connectwise
$f = Invoke-Flow @{ companyName = 'Contoso'; ticketId = '<ticketId>' } $aiDup
Check 'placeholder ticketId: incomplete' ($f.stage -eq 'gather' -and $f.r.out.status -eq 'incomplete' -and $f.r.out.message -like '*ticketId is missing*') $f.r.out.message
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ days = 'lots' }) $aiDup
Check 'bad days: incomplete' ($f.r.out.status -eq 'incomplete' -and $f.r.out.message -like '*days must be a whole number*') $f.r.out.message
TReset $Psa.connectwise
$f = Invoke-Flow @{ Ticket = @{ TicketId = '1001'; Questions = @() }; Company = @{ CompanyName = 'Contoso' } } $aiDup
Check 'CloudRadial body shape accepted' ($f.stage -eq 'write' -and $f.r.out.status -eq 'pending_confirmation') "$($f.stage) $($f.r.out.status) $($f.r.error)"

# ---- 10. Autotask: ticket number resolved, same device, incident of a Problem ticket on confirm ----
TReset $Psa.autotask
$f = Invoke-Flow (New-Body @{ ticketId = 'T20261008.0001'; confirm = $true }) '{"matches":[{"id":"5002","relation":"related","confidence":0.85,"reason":"Both report the branch VPN dropping."}]}'
$o = $f.r.out
Check 'at: reached the write step' ($f.stage -eq 'write' -and -not $f.r.error) "$($f.stage) $($f.r.error) $($f.r.out.message)"
Check 'at: Fabrikam ticket 5009 filtered out of the candidates' (-not @(($f.gather.candidates_json | ConvertFrom-Json) | Where-Object { $_.id -eq '5009' }).Count) $f.gather.candidates_json
Check 'at: 5002 matched on the same device' (@(($f.gather.candidates_json | ConvertFrom-Json) | Where-Object { $_.id -eq '5002' -and $_.sameDevice }).Count -eq 1)
$TPatch = @(Get-Calls 'PATCH' "$TAT/Tickets")
Check 'at: 5001 made an incident of problem 5002' ($TPatch.Count -eq 1 -and (Read-Body $TPatch[0]).problemTicketID -eq 5002 -and (Read-Body $TPatch[0]).ticketType -eq 2 -and (Read-Body $TPatch[0]).id -eq 5001) (Show-Calls)
Check 'at: cross-reference note on 5002 and summary note on 5001' (@(Get-Calls 'POST' "$TAT/Tickets/5002/Notes").Count -eq 1 -and @(Get-Calls 'POST' "$TAT/Tickets/5001/Notes").Count -eq 1)
Check 'at: status success and nothing closed' ($o.status -eq 'success' -and (Test-NoMerge)) "$($o.status) $(Show-Calls)"
Check 'at: link to the Autotask ticket' ($o.internal_note -like '*https://ww5.autotask.example/Mvc/ServiceDesk/TicketDetail.mvc?ticketId=5002*') $o.internal_note

# Autotask rerun: the incident link is set again (same value), but no note is added twice.
Reset-Mock $Psa.autotask $Handler
$f = Invoke-Flow (New-Body @{ ticketId = 'T20261008.0001'; confirm = $true }) '{"matches":[{"id":"5002","relation":"related","confidence":0.85,"reason":"Both report the branch VPN dropping."}]}'
Check 'at rerun: no note written twice' (-not @(Get-Calls 'POST' "$TAT/Tickets/*/Notes").Count -and (TNote '5001').Count -eq 1 -and (TNote '5002').Count -eq 1 -and $f.r.out.status -eq 'success') "$(Show-Calls) $($f.r.out.message)"

# ---- 11. Zendesk: the other ticket isn't a problem, so notes only ----
TReset $Psa.zendesk
$f = Invoke-Flow (New-Body @{ ticketId = '3001'; confirm = $true }) '{"matches":[{"id":"3002","relation":"duplicate","confidence":0.9,"reason":"Same printer error from the same person."}]}'
$o = $f.r.out
Check 'zd: search scoped to the organization and open tickets' (@(Get-Calls 'GET' "$TZD/search?query=*" | Where-Object { [uri]::UnescapeDataString($_.Uri) -like '*type:ticket status<solved organization:42 created>=*' }).Count -eq 1) (Show-Calls)
Check 'zd: no type change, private notes only' (-not @(Get-WriteCalls | Where-Object { $_.Body -like '*problem_id*' }).Count -and @(Get-WriteCalls | Where-Object { $_.Body -like '*"public":false*' }).Count -eq 2) (Show-Calls)
Check 'zd: link to the agent view' ($o.internal_note -like '*https://example.zendesk.com/agent/tickets/3002*') $o.internal_note

# ---- 12. HaloPSA: parent ticket on confirm ----
TReset $Psa.halopsa
$f = Invoke-Flow (New-Body @{ ticketId = '4001'; confirm = $true }) '{"matches":[{"id":"4000","relation":"related","confidence":0.8,"reason":"Both describe Teams calls dropping."}]}'
$THalo = @(Get-Calls 'POST' "$THA/api/Tickets")
Check 'halo: 4001 made a child of 4000' ($THalo.Count -eq 1 -and @(Read-Body $THalo[0])[0].parent_id -eq 4000 -and @(Read-Body $THalo[0])[0].id -eq 4001) "$(Show-Calls) $($f.r.out.message)"
Check 'halo: two private actions (cross-reference and summary)' (@(Get-Calls 'POST' "$THA/api/Actions").Count -eq 2)

# ---- 13. _shared/psa-tickets.ps1 list calls for Kaseya BMS and Syncro (shape and company filter) ----
$TLib = (Get-Content -Raw (Join-Path $Shared 'psa.ps1')) + "`n" + (Get-Content -Raw (Join-Path $Shared 'psa-tickets.ps1'))
function Invoke-Lib { param([string]$Body) & ([scriptblock]::Create("Set-StrictMode -Version Latest`n$TLib`n$Body")) }
TReset $Psa.kaseyabms
$TRows = @(Invoke-Lib '$null = Connect-Psa; @(Find-PsaTickets -CompanyId 42 -Open -CreatedAfter ((Get-Date).AddDays(-7)) -Order newest)')
Check 'bms: open tickets for company 42 only' (@($TRows).Count -eq 1 -and $TRows[0].id -eq '61' -and $TRows[0].number -eq 'T20261007.0001') ($TRows | ConvertTo-Json -Depth 2)
TReset $Psa.syncro
$TRows = @(Invoke-Lib '$null = Connect-Psa; @(Find-PsaTickets -CompanyId 42 -Open -CreatedAfter ((Get-Date).AddDays(-7)) -Order newest)')
Check 'syncro: open tickets from the window only, with status Not Closed' (@($TRows).Count -eq 1 -and $TRows[0].id -eq '71' -and @(Get-Calls 'GET' "$TSY/tickets?status=Not%20Closed&customer_id=42*").Count -eq 1) "$(Show-Calls) $($TRows | ConvertTo-Json -Depth 2)"
$TId = Invoke-Lib '$null = Connect-Psa; Resolve-PsaTicketId 1071'
Check 'syncro: ticket number 1071 resolves to id 71' ($TId -eq '71') $TId
$TSup = Invoke-Lib '$null = Connect-Psa; Get-PsaCapabilities'
Check 'syncro: relation is notes only' ($TSup.relation -eq 'note')

Complete-Test
