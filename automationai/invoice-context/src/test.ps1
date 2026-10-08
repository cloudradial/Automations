# Strict-mode harness for Invoice Context Gathering.
# Runs each PowerShell step exactly as it is in invoice-context.yml (shared libraries psa.ps1 and
# psa-tickets.ps1 included), through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the runner
# Key Vault, Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked. The AI Prompt step is simulated
# by handing the note step a summary string.
# Placeholder data only (Contoso, Fabrikam, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a step variable such as $t or $f
# would hide a same-named test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File automationai/invoice-context/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in automationai/_shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

# ---- the steps, straight from the built workflow ----
$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\invoice-context.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.type==='powershell-script')o[a.id]=a.properties.script;if(a.type==='ai-prompt'){o[a.id+'.prompt']=a.properties.promptTemplate;o[a.id+'.model']=a.properties.model;}}console.log(JSON.stringify(o));"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow has gather and note steps' ($Steps.Contains('gather') -and $Steps.Contains('note'))
Check 'summarize prompt reads the gather output' ($Steps['summarize.prompt'] -like '*{{ nodes.gather.output.facts_json }}*')
Check 'summarize model is blank' ($Steps['summarize.model'] -eq '')
Check '_shared/psa-tickets.ps1 in the yml matches the source' ($Steps['gather'].Contains((Get-Content -Raw (Join-Path $Shared 'psa-tickets.ps1')).Replace("`r`n", "`n").TrimEnd()))
Check 'no local psa-extra.ps1 left' (-not (Test-Path (Join-Path $PSScriptRoot 'psa-extra.ps1')) -and $Steps['gather'] -notlike '*# >>> src/psa-extra.ps1*' -and $Steps['note'] -notlike '*# >>> src/psa-extra.ps1*')

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
function Invoke-Flow {
    param($Body, [string]$Ai)
    $g = Invoke-Step 'gather' ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    if ($g.error) { return @{ stage = 'gather'; r = $g } }
    $o = $g.out
    $n = Invoke-Step 'note' $null @{ request = $o.request_json; figures = $o.figures_json; warnings_json = $o.warnings_json; actions_json = $o.actions_json; summary = $Ai }
    return @{ stage = 'note'; r = $n; gather = $o; fig = ($o.figures_json | ConvertFrom-Json) }
}

# ---- placeholder data ----
$Psa = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://api-na.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices5.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    halopsa     = @{ 'PSA-Type' = 'halopsa'; 'Halo-ApiUrl' = 'https://halo.example.com'; 'Halo-ClientId' = 'hid'; 'Halo-ClientSecret' = 'hsec' }
    kaseyabms   = @{ 'PSA-Type' = 'kaseyabms'; 'KaseyaBMS-ApiUrl' = 'https://bms.example.com'; 'KaseyaBMS-Username' = 'api'; 'KaseyaBMS-Password' = 'pw'; 'KaseyaBMS-CompanyName' = 'examplemsp' }
    syncro      = @{ 'PSA-Type' = 'syncro'; 'Syncro-ApiUrl' = 'https://examplemsp.syncromsp.com/api/v1'; 'Syncro-ApiKey' = 'key' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
}
$TCW = 'https://api-na.example.com/v4_6_release/apis/3.0'; $TAT = 'https://webservices5.autotask.example/atservicesrest/v1.0'; $TZD = 'https://example.zendesk.com/api/v2'
$THA = 'https://halo.example.com'; $TKB = 'https://bms.example.com/v2'; $TSY = 'https://examplemsp.syncromsp.com/api/v1'
$TS = @{ time403 = $false; empty = $false }
# Notes written during a test, by ticket id, so a rerun sees the marker the first run left.
$TNotes = @{}
function TNote { param([string]$Id) if (-not $TNotes.Contains($Id)) { $TNotes[$Id] = New-Object System.Collections.ArrayList }; return , $TNotes[$Id] }
function TReset { param($Secrets) Reset-Mock $Secrets $Handler; $TNotes.Clear() }

function TCwT { param($Id, $Sum, $Date, $Closed = $false) return [pscustomobject]@{ id = $Id; summary = $Sum; company = [pscustomobject]@{ id = 42 }; contact = [pscustomobject]@{ id = 7 }; status = [pscustomobject]@{ name = $(if ($Closed) { 'Closed' } else { 'In Progress' }) }; closedFlag = $Closed; dateEntered = $Date } }
function TCwTime { param($Id, $Ticket, $Date, $Hrs, $Bill, $Agr = $null) return [pscustomobject]@{ id = $Id; chargeToId = $Ticket; chargeToType = 'ServiceTicket'; timeStart = $Date; actualHours = $Hrs; hoursBilled = $(if ($Bill -eq 'Billable') { $Hrs } else { 0 }); billableOption = $Bill; member = [pscustomobject]@{ identifier = 'jlee' }; workType = [pscustomobject]@{ name = 'Remote' }; agreement = $(if ($Agr) { [pscustomobject]@{ id = $Agr } } else { $null }); notes = 'internal work notes' } }

$Handler = {
    param($c, $n)
    $k = "$($c.Method) $($c.Uri)"
    $u = [uri]::UnescapeDataString($c.Uri)
    switch -Wildcard -CaseSensitive ($k) {
        # ---- ConnectWise ----
        "GET $TCW/company/companies*" { if ($u -like '*Contoso*') { return @([pscustomobject]@{ id = 42; name = 'Contoso' }) }; return @() }
        "GET $TCW/service/tickets/1001/notes*" { if ($c.Uri -like '*page=*' -and $c.Uri -notlike '*page=1') { return @() }; return @(@([pscustomobject]@{ id = 1; text = 'We think the September invoice is too high.'; internalAnalysisFlag = $false; detailDescriptionFlag = $true }) + @(TNote '1001' | ForEach-Object { [pscustomobject]@{ id = 2; text = $_; internalAnalysisFlag = $true; detailDescriptionFlag = $false } })) }
        "GET $TCW/service/tickets/1001" { return (TCwT 1001 'Question about invoice INV-100' '2026-10-02T09:00:00Z') }
        "GET $TCW/service/tickets?conditions=*" {
            if ($TS.empty) { return @() }
            return @((TCwT 1011 'Printer setup for reception' '2026-09-15T10:00:00Z' $true), (TCwT 1010 'Server patching weekend' '2026-09-03T10:00:00Z'), (TCwT 1012 'Email migration to Microsoft 365' '2026-08-20T10:00:00Z'))
        }
        "GET $TCW/time/entries?conditions=*" {
            if ($TS.time403) { New-HttpError 403 '{"code":"Forbidden","message":"You do not have access to Time Entries."}' }
            if ($TS.empty) { return @() }
            return @((TCwTime 1 1010 '2026-09-04T09:00:00Z' 3.5 'Billable'), (TCwTime 2 1010 '2026-09-05T09:00:00Z' 1 'DoNotBill' 501), (TCwTime 3 1011 '2026-09-15T11:00:00Z' 0.5 'Billable'), (TCwTime 4 1012 '2026-09-10T09:00:00Z' 4 'Billable' 501))
        }
        "GET $TCW/finance/agreements?conditions=*" {
            if ($TS.empty) { return @() }
            return @([pscustomobject]@{ id = 501; name = 'Managed Services'; type = [pscustomobject]@{ name = 'Managed' }; company = [pscustomobject]@{ id = 42 }; agreementStatus = 'Active'; startDate = '2026-01-01T00:00:00Z'; endDate = $null; billAmount = 1500; billingCycle = [pscustomobject]@{ name = 'Monthly' }; applicationUnits = 'Hours'; applicationLimit = 20; applicationCycle = 'Monthly'; cancelledFlag = $false },
                [pscustomobject]@{ id = 502; name = 'Old block hours'; type = [pscustomobject]@{ name = 'Block' }; company = [pscustomobject]@{ id = 42 }; agreementStatus = 'Expired'; startDate = '2025-01-01T00:00:00Z'; endDate = '2026-06-30T00:00:00Z'; billAmount = 900; cancelledFlag = $false })
        }
        "GET $TCW/finance/invoices?conditions=*" {
            if ($u -like '*INV-100*') { return @([pscustomobject]@{ id = 900; invoiceNumber = 'INV-100'; company = [pscustomobject]@{ id = 42 }; date = '2026-10-01T00:00:00Z'; total = 2100.5 }) }
            if ($u -like '*INV-200*') { return @([pscustomobject]@{ id = 901; invoiceNumber = 'INV-200'; company = [pscustomobject]@{ id = 77 }; date = '2026-10-01T00:00:00Z'; total = 5000 }) }
            return @()
        }
        "POST $TCW/service/tickets/*/notes" { $id = ($c.Uri -split '/service/tickets/')[1].Split('/')[0]; $null = (TNote $id).Add((Read-Body $c).text); return [pscustomobject]@{ id = 9001 } }
        # ---- Autotask ----
        "GET $TAT/Tickets/entityInformation/fields" { return [pscustomobject]@{ fields = @([pscustomobject]@{ name = 'status'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'New'; isActive = $true }, [pscustomobject]@{ value = '5'; label = 'Complete'; isActive = $true }) }) } }
        "GET $TAT/Contracts/entityInformation/fields" { return [pscustomobject]@{ fields = @([pscustomobject]@{ name = 'contractType'; picklistValues = @([pscustomobject]@{ value = '7'; label = 'Recurring Service'; isActive = $true }) }) } }
        "GET $TAT/TicketNotes/entityInformation/fields" { return [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                    [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) } }
        "GET $TAT/Tickets/5001" { return [pscustomobject]@{ item = [pscustomobject]@{ id = 5001; title = 'Invoice query'; description = 'Please explain invoice 4410.'; companyID = 42; status = 1; createDate = '2026-10-03T09:00:00Z'; assignedResourceID = $null } } }
        "GET $TAT/Companies/query*" { return [pscustomobject]@{ items = @([pscustomobject]@{ id = 42; companyName = 'Contoso' }) } }
        "GET $TAT/Invoices/query?search=*" { return [pscustomobject]@{ items = @([pscustomobject]@{ id = 31; invoiceNumber = '4410'; companyID = 42; invoiceDateTime = '2026-10-02T00:00:00Z'; fromDate = '2026-09-01T00:00:00Z'; toDate = '2026-09-30T00:00:00Z'; invoiceTotal = 999 }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
        "GET $TAT/Tickets/query?search=*" { return [pscustomobject]@{ items = @([pscustomobject]@{ id = 5010; ticketNumber = 'T20260905.0001'; title = 'Firewall firmware update'; companyID = 42; status = 5; createDate = '2026-09-05T09:00:00Z' }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
        "GET $TAT/TimeEntries/query?search=*" { return [pscustomobject]@{ items = @([pscustomobject]@{ id = 81; ticketID = 5010; dateWorked = '2026-09-06T00:00:00Z'; hoursWorked = 2.0; hoursToBill = 2.0; isNonBillable = $false; resourceID = 29; contractID = 700; summaryNotes = 'x' }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
        "GET $TAT/Contracts/query?search=*" { return [pscustomobject]@{ items = @([pscustomobject]@{ id = 700; contractName = 'Contoso managed services'; contractType = 7; status = 1; startDate = '2026-01-01T00:00:00Z'; endDate = '2026-12-31T00:00:00Z'; companyID = 42 }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
        "POST $TAT/Tickets/*/Notes" { $null = (TNote ([string](Read-Body $c).ticketID)).Add((Read-Body $c).description); return [pscustomobject]@{ itemId = 3001 } }
        "GET $TAT/TicketNotes/query?search=*" { $s = [uri]::UnescapeDataString(($c.Uri -split 'search=')[1]) | ConvertFrom-Json; $tid = [string]@($s.filter)[0].value; return [pscustomobject]@{ items = @(TNote $tid | ForEach-Object { [pscustomobject]@{ id = 1; ticketID = [long]$tid; title = 'Note'; description = $_; publish = 2; noteType = 1; createDateTime = '2026-10-03T09:00:00Z' } }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
        # ---- Zendesk ----
        "GET $TZD/organizations/autocomplete*" { return [pscustomobject]@{ organizations = @([pscustomobject]@{ id = 42; name = 'Contoso' }) } }
        "GET $TZD/tickets/3001" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 3001; subject = 'Billing question'; description = 'Why was I charged?'; organization_id = 42; status = 'new'; created_at = '2026-10-03T09:00:00Z' } } }
        "GET $TZD/search?query=*" { return [pscustomobject]@{ results = @([pscustomobject]@{ id = 3002; subject = 'Laptop slow'; organization_id = 42; status = 'solved'; created_at = '2026-09-10T09:00:00Z' }); next_page = $null } }
        "GET $TZD/tickets/3001/comments*" { return [pscustomobject]@{ comments = @(TNote '3001' | ForEach-Object { [pscustomobject]@{ id = 1; body = $_; public = $false; author_id = 1; created_at = '2026-10-03T09:00:00Z' } }); next_page = $null } }
        "PUT $TZD/tickets/3001" { $b = Read-Body $c; if ($b.ticket.PSObject.Properties['comment']) { $null = (TNote '3001').Add($b.ticket.comment.body) }; return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 3001 } } }
        # ---- HaloPSA, Kaseya BMS and Syncro (library shape only) ----
        "POST $THA/auth/token" { return [pscustomobject]@{ access_token = 'halo-token' } }
        "GET $THA/api/Actions?ticket_id=4000*" { return [pscustomobject]@{ actions = @([pscustomobject]@{ id = 1; timetaken = 1.5; chargehours = 1.5; datetime = '2026-09-10T09:00:00Z'; who = 'Jo'; note = 'x' }, [pscustomobject]@{ id = 2; timetaken = 0; datetime = '2026-09-10T09:00:00Z' }, [pscustomobject]@{ id = 3; timetaken = 2; chargehours = 0; datetime = '2026-09-11T09:00:00Z'; who = 'Jo' }) } }
        "GET $THA/api/ClientContract?client_id=42" { return @([pscustomobject]@{ id = 9; ref = 'Contoso support'; client_id = 42; start_date = '2026-01-01T00:00:00Z'; end_date = $null; active = $true; periodchargeamount = 1200 }, [pscustomobject]@{ id = 10; ref = 'Fabrikam'; client_id = 77 }) }
        "GET $THA/api/Invoice?search=*" { return [pscustomobject]@{ invoices = @([pscustomobject]@{ id = 55; invoicenumber = 'H-55'; client_id = 42; invoice_date = '2026-10-01T00:00:00Z'; total = 300 }) } }
        "POST $TKB/security/authenticate" { return [pscustomobject]@{ Result = [pscustomobject]@{ AccessToken = 'bms-token' } } }
        "GET $TKB/timelogs?Filter.TicketId=61*" { return [pscustomobject]@{ Result = @([pscustomobject]@{ Id = 1; Timespent = 1.25; IsBillable = $true; FirstName = 'Jo'; StartDate = '2026-09-12T09:00:00Z'; AssigneeName = 'Jo' }) } }
        "GET $TKB/finance/contracts?Filter.AccountId=42*" { return [pscustomobject]@{ Result = @([pscustomobject]@{ Id = 3; Name = 'Contoso MSA'; AccountId = 42; StatusName = 'Active'; StartDate = '2026-01-01T00:00:00Z' }) } }
        "GET $TSY/ticket_timers?ticket_id=71*" { return [pscustomobject]@{ ticket_timers = @([pscustomobject]@{ id = 5; start_time = '2026-09-12T09:00:00Z'; active_duration = 5400; billable = $true; user_id = 4; notes = 'x' }); meta = [pscustomobject]@{ total_pages = 1 } } }
        "GET $TSY/contracts?customer_id=42" { return [pscustomobject]@{ contracts = @([pscustomobject]@{ id = 8; name = 'Contoso plan'; customer_id = 42; contract_amount = 800; status = 'Active' }) } }
    }
    throw "Unexpected call in test: $k"
}
function Get-WriteCalls { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and $_.Uri -notlike '*/auth/token' -and $_.Uri -notlike '*/security/authenticate' }) }

$aiText = 'Invoice INV-100 is dated 2026-10-01 with a total of 2,100.50. In September 2026, 9.0 hours were logged across three tickets, 8.0 of them billable. Most time went to #1010 (4.5 h) and #1012 (4.0 h). The Managed Services agreement was in effect, and 5.0 hours were logged against it. Check whether the billable hours on #1012 should have fallen under the agreement.'
$base = @{ ticketId = '1001'; companyName = 'Contoso'; period = '2026-09'; triggerSource = 'serviceai-ai' }
function New-Body { param([hashtable]$Over) $b = @{}; foreach ($k in $base.Keys) { $b[$k] = $base[$k] }; foreach ($k in $Over.Keys) { if ($null -eq $Over[$k]) { $b.Remove($k) } else { $b[$k] = $Over[$k] } }; return $b }

# ---- 1. ConnectWise preview (addNote false): figures only, nothing written ----
TReset $Psa.connectwise; $TS.time403 = $false; $TS.empty = $false
$f = Invoke-Flow (New-Body @{ addNote = $false }) $aiText
$o = $f.r.out; $TF = $f.fig
Check 'cw preview: reached the note step' ($f.stage -eq 'note' -and -not $f.r.error) "$($f.stage) $($f.r.error) $($f.r.out.message)"
Check 'cw preview: status pending_confirmation and nothing written' ($o.status -eq 'pending_confirmation' -and @(Get-WriteCalls).Count -eq 0) "$($o.status) $(Show-Calls)"
Check 'cw preview: period is September 2026 from the input' ($TF.period -eq 'September 2026' -and $f.gather.figures_json -like '*"periodStart":"2026-09-01T00:00:00Z","periodEnd":"2026-10-01T00:00:00Z"*' -and $TF.periodSource -eq 'input')
Check 'cw preview: time read for company 42 and the period' (@(Get-Calls 'GET' "$TCW/time/entries*" | Where-Object { [uri]::UnescapeDataString($_.Uri) -like '*company/id=42 and timeStart>=`[2026-09-01T00:00:00Z`] and timeStart<`[2026-10-01T00:00:00Z`]*' }).Count -eq 1) (Show-Calls)
Check 'cw preview: hours added up (9.0 total, 8.0 billable, 1.0 not, 5.0 on agreement)' ($TF.totalHours -eq 9 -and $TF.billableHours -eq 8 -and $TF.nonBillableHours -eq 1 -and $TF.hoursOnAgreements -eq 5) ($TF | ConvertTo-Json -Depth 2)
Check 'cw preview: top tickets by time are #1010 then #1012' (@($TF.topTickets).Count -eq 3 -and $TF.topTickets[0].number -eq '1010' -and $TF.topTickets[0].hours -eq 4.5 -and $TF.topTickets[1].number -eq '1012') ($TF.topTickets | ConvertTo-Json)
Check 'cw preview: only the agreement in effect is listed' (@($TF.agreements).Count -eq 1 -and $TF.agreements[0].name -eq 'Managed Services' -and $TF.agreements[0].hoursLogged -eq 5 -and $TF.agreements[0].coverage -eq '20 hours per Monthly')
Check 'cw preview: two tickets opened in the period, one closed since' ($TF.ticketsOpened -eq 2 -and $TF.ticketsOpenedClosed -eq 1) "$($TF.ticketsOpened) $($TF.ticketsOpenedClosed)"
Check 'cw preview: note has the AI summary and the figures' ($o.internal_note -like '*Summary:*9.0 hours*' -and $o.internal_note -like '*Time logged: 9.0 h (8.0 h billable, 1.0 h not billable) on 3 ticket(s)*' -and $o.internal_note -like '*#1010 "Server patching weekend": 4.5 h*' -and $o.internal_note -like '*Managed Services (Managed, Active): 1,500.00 per Monthly. Covers 20 hours per Monthly. 5.0 h logged against it.*') $o.internal_note
Check 'cw preview: time-entry notes never reach the AI or the note' ($f.gather.facts_json -notlike '*internal work notes*' -and $o.internal_note -notlike '*internal work notes*')
Check 'cw preview: summarized by AI, chatReply has the hours' ($o.summarized_by -eq 'ai' -and $o.chatReply -like '*9.0 h logged (8.0 h billable) on 3 ticket(s); most time on #1010 (4.5 h)*') $o.chatReply

# ---- 2. ConnectWise with addNote (the default): one internal note on the ticket ----
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{}) $aiText
$o = $f.r.out
$TW = @(Get-WriteCalls)
Check 'cw note: status success' ($o.status -eq 'success' -and $o.note_written -eq $true) "$($o.status) $($o.message) $($f.r.error)"
Check 'cw note: exactly one write, an internal note on 1001' ($TW.Count -eq 1 -and $TW[0].Uri -eq "$TCW/service/tickets/1001/notes" -and (Read-Body $TW[0]).internalAnalysisFlag -eq $true -and (Read-Body $TW[0]).detailDescriptionFlag -eq $false) (Show-Calls)
Check 'cw note: public_note stays empty' ($o.public_note -eq '')
Check 'cw note: ends with the retry marker' ((TNote '1001')[0] -like '*`[invoice context 1001 2026-09-01T00:00:00Z to 2026-10-01T00:00:00Z`]') ((TNote '1001') -join ' | ')

# ---- 2b. rerun (ServiceAI Retry or a Routine): the same period writes nothing twice ----
Reset-Mock $Psa.connectwise $Handler
$f = Invoke-Flow (New-Body @{}) $aiText
$o = $f.r.out
Check 'cw rerun: no second note' (@(Get-WriteCalls).Count -eq 0 -and (TNote '1001').Count -eq 1) (Show-Calls)
Check 'cw rerun: success, note_written false, says it was already there' ($o.status -eq 'success' -and $o.note_written -eq $false -and @($o.actions | Where-Object { $_ -like '*already on ticket 1001*' }).Count -eq 1) "$($o.status) $($o.message)"
Reset-Mock $Psa.connectwise $Handler
$f = Invoke-Flow (New-Body @{ period = '2026-08' }) $aiText
Check 'cw another period: a new note is written' (@(Get-WriteCalls).Count -eq 1 -and (TNote '1001').Count -eq 2) (Show-Calls)

# ---- 3. Invoice number: period derived from the invoice date ----
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ period = $null; invoiceNumber = 'INV-100'; addNote = $false }) $aiText
$TF = $f.fig
Check 'invoice: found and period derived as September 2026' ($TF.period -eq 'September 2026' -and $TF.periodSource -eq 'invoice' -and $TF.invoice.number -eq 'INV-100' -and $TF.invoice.total -eq 2100.5) ($TF | ConvertTo-Json -Depth 3)
Check 'invoice: warning says the period was derived' (@($f.r.out.warnings | Where-Object { $_ -like '*calendar month before its date*' }).Count -eq 1)
Check 'invoice: note shows the invoice' ($f.r.out.internal_note -like '*Invoice INV-100: dated 2026-10-01, total 2,100.50.*')

# ---- 4. Another company's invoice stops the run ----
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ period = $null; invoiceNumber = 'INV-200' }) $aiText
Check 'other company invoice: rejected, nothing read or written' ($f.stage -eq 'gather' -and $f.r.out.status -eq 'rejected' -and @(Get-WriteCalls).Count -eq 0 -and -not @(Get-Calls 'GET' "$TCW/time/entries*").Count) "$($f.stage) $($f.r.out.status) $(Show-Calls)"
Check 'other company invoice: message reveals nothing about it' ($f.r.out.message -notlike '*5000*' -and $f.r.out.message -like '*does not belong*')
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ period = $null; invoiceNumber = 'INV-999' }) $aiText
Check 'missing invoice and no period: incomplete' ($f.r.out.status -eq 'incomplete' -and $f.r.out.message -like '*Send period*') $f.r.out.message

# ---- 5. Missing permission (403) ----
TReset $Psa.connectwise; $TS.time403 = $true
$f = Invoke-Flow (New-Body @{}) $aiText
Check '403: stops in gather with status error and nothing written' ($f.stage -eq 'gather' -and $f.r.out.status -eq 'error' -and @(Get-WriteCalls).Count -eq 0) "$($f.stage) $($f.r.out.status)"
Check '403: message names the PSA, HTTP 403 and the permission' ($f.r.out.message -like '*ConnectWise*time*HTTP 403*')  $f.r.out.message
$TS.time403 = $false

# ---- 6. Empty result, and an empty AI answer ----
TReset $Psa.connectwise; $TS.empty = $true
$f = Invoke-Flow (New-Body @{}) ''
$o = $f.r.out
Check 'empty: success with zero hours' ($o.status -eq 'success' -and $f.fig.totalHours -eq 0 -and @($f.fig.topTickets).Count -eq 0) "$($o.status) $($f.r.error)"
Check 'empty: fallback summary from the figures' ($o.summarized_by -eq 'figures' -and $o.internal_note -like '*0.0 hours were logged on 0 ticket(s)*' -and $o.internal_note -like '*No agreement was in effect*') $o.internal_note
Check 'empty: warning says the AI summary was empty' (@($o.warnings | Where-Object { $_ -like '*AI summary was empty*' }).Count -eq 1)
$TS.empty = $false
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ addNote = $false }) '{"summary":"json is not wanted"}'
Check 'JSON instead of text: fallback summary' ($f.r.out.summarized_by -eq 'figures')

# ---- 7. Bad input fails closed ----
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ period = 'last quarter-ish' }) $aiText
Check 'bad period: incomplete before any PSA call' ($f.r.out.status -eq 'incomplete' -and $f.r.out.message -like '*wasn''t understood*' -and $Mock.Calls.Count -eq 0) "$($f.r.out.message) $(Show-Calls)"
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ period = 'September 2026'; addNote = $false }) $aiText
Check 'period as a month name works' ($f.fig.period -eq 'September 2026')
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ period = '2026-09-01..2026-09-15'; addNote = $false }) $aiText
Check 'period as a date range works' ($f.fig.period -eq '2026-09-01 to 2026-09-15' -and $f.gather.figures_json -like '*"periodEnd":"2026-09-16T00:00:00Z"*') $f.fig.period
TReset $Psa.connectwise
$f = Invoke-Flow (New-Body @{ companyName = 'Fabrikam' }) $aiText
Check 'company mismatch: rejected' ($f.r.out.status -eq 'rejected' -and @(Get-WriteCalls).Count -eq 0)
TReset $Psa.connectwise
$f = Invoke-Flow @{ ticketId = '@TicketId'; companyName = 'Contoso' } $aiText
Check 'literal token ticketId: incomplete' ($f.r.out.status -eq 'incomplete' -and $f.r.out.message -like '*ticketId is missing*')

# ---- 8. Autotask: invoice period from the invoice, time by ticket, contract type label, note ----
TReset $Psa.autotask
$f = Invoke-Flow (New-Body @{ ticketId = '5001'; period = $null; invoiceNumber = '4410' }) $aiText
$o = $f.r.out; $TF = $f.fig
Check 'at: reached the note step' ($f.stage -eq 'note' -and -not $f.r.error) "$($f.stage) $($f.r.error) $($f.r.out.message)"
Check 'at: period from the invoice fromDate and toDate' ($TF.period -eq 'September 2026' -and $TF.periodSource -eq 'invoice' -and -not @($o.warnings | Where-Object { $_ -like '*calendar month*' }).Count) ($TF | ConvertTo-Json -Depth 2)
$TQ = @(Get-Calls 'GET' "$TAT/TimeEntries/query*")
Check 'at: time queried with ticketID in the company tickets' ($TQ.Count -eq 1 -and [uri]::UnescapeDataString($TQ[0].Uri) -like '*"op":"eq","field":"ticketID","value":5010*') (Show-Calls)
Check 'at: 2.0 h billable on #T20260905.0001, against the contract' ($TF.totalHours -eq 2 -and $TF.billableHours -eq 2 -and $TF.hoursOnAgreements -eq 2 -and $TF.topTickets[0].number -eq 'T20260905.0001')
Check 'at: contract type label read from the picklist' ($TF.agreements[0].type -eq 'Recurring Service')
Check 'at: one internal note on 5001' (@(Get-WriteCalls).Count -eq 1 -and (Get-WriteCalls)[0].Uri -eq "$TAT/Tickets/5001/Notes" -and (Read-Body (Get-WriteCalls)[0]).publish -eq 2) (Show-Calls)

# ---- 9. Zendesk: no time or agreements, no invoice lookup ----
TReset $Psa.zendesk
$f = Invoke-Flow (New-Body @{ ticketId = '3001' }) ''
$o = $f.r.out
Check 'zd: success with time and agreements marked not available' ($o.status -eq 'success' -and $o.internal_note -like '*Time entries: not available from Zendesk.*' -and $o.internal_note -like '*Agreements: not available from Zendesk.*') "$($o.status) $($f.r.error) $($o.internal_note)"
Check 'zd: one private comment' (@(Get-WriteCalls).Count -eq 1 -and (Get-WriteCalls)[0].Body -like '*"public":false*')
TReset $Psa.zendesk
$f = Invoke-Flow (New-Body @{ ticketId = '3001'; period = $null; invoiceNumber = 'Z-1' }) ''
Check 'zd: invoice number without a period is incomplete' ($f.r.out.status -eq 'incomplete' -and @(Get-WriteCalls).Count -eq 0) $f.r.out.message

# ---- 10. _shared/psa-tickets.ps1 time, agreement and invoice calls for HaloPSA, Kaseya BMS and Syncro ----
$TLib = (Get-Content -Raw (Join-Path $Shared 'psa.ps1')) + "`n" + (Get-Content -Raw (Join-Path $Shared 'psa-tickets.ps1'))
function Invoke-Lib { param([string]$Body) & ([scriptblock]::Create("Set-StrictMode -Version Latest`n$TLib`n$Body")) }
$TRange = '-After ([datetime]"2026-09-01T00:00:00Z") -Before ([datetime]"2026-10-01T00:00:00Z")'
TReset $Psa.halopsa
$TT = @(Invoke-Lib "`$null = Connect-Psa; @((Get-PsaTimeEntries -CompanyId 42 $TRange -TicketIds @('4000')).entries)")
Check 'halo: actions with time become entries (1.5 billable, 2.0 not)' ($TT.Count -eq 2 -and $TT[0].billableHours -eq 1.5 -and $TT[1].billable -ne $true -and $TT[1].billableHours -eq 0) ($TT | ConvertTo-Json -Depth 2)
$TA = @(Invoke-Lib '$null = Connect-Psa; @((Get-PsaAgreements -CompanyId 42).agreements)')
Check 'halo: only this client''s contracts' ($TA.Count -eq 1 -and $TA[0].name -eq 'Contoso support' -and $TA[0].amount -eq 1200)
$TI = Invoke-Lib '$null = Connect-Psa; Get-PsaInvoice -Number H-55'
Check 'halo: invoice found with a derived period' ($TI.companyId -eq '42' -and $TI.periodDerived -and $TI.periodStart.Month -eq 9) ($TI | ConvertTo-Json -Depth 2)
TReset $Psa.kaseyabms
$TT = @(Invoke-Lib "`$null = Connect-Psa; @((Get-PsaTimeEntries -CompanyId 42 $TRange -TicketIds @('61')).entries)")
Check 'bms: timelogs read' ($TT.Count -eq 1 -and $TT[0].hours -eq 1.25 -and $TT[0].billable)
$TA = @(Invoke-Lib '$null = Connect-Psa; @((Get-PsaAgreements -CompanyId 42).agreements)')
Check 'bms: contracts read' ($TA.Count -eq 1 -and $TA[0].name -eq 'Contoso MSA')
$TE = Invoke-Lib '$null = Connect-Psa; try { $null = Get-PsaInvoice -Number 1; "no error" } catch { $_.Exception.Message }'
Check 'bms: invoice lookup says it is not supported' ($TE -like "*can't be looked up*") $TE
TReset $Psa.syncro
$TT = @(Invoke-Lib "`$null = Connect-Psa; @((Get-PsaTimeEntries -CompanyId 42 $TRange -TicketIds @('71')).entries)")
Check 'syncro: ticket timer of 1.5 h' ($TT.Count -eq 1 -and $TT[0].hours -eq 1.5) ($TT | ConvertTo-Json -Depth 2)
$TA = @(Invoke-Lib '$null = Connect-Psa; @((Get-PsaAgreements -CompanyId 42).agreements)')
Check 'syncro: contracts read' ($TA.Count -eq 1 -and $TA[0].amount -eq 800)

Complete-Test
