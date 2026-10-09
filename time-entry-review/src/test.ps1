# Strict-mode harness for time-entry-review.yml. Runs the four steps exactly as they are in the .yml
# (extracted by build.js --extract), each through & ([scriptblock]::Create(...)) under
# Set-StrictMode -Version Latest, passing each step's output to the next as JSON the way the runner does.
# Mocks Get-AzKeyVaultSecret, Invoke-RestMethod, Get-NodeInput, Set-NodeOutput and Start-Sleep.
# Covers all six PSAs. Placeholder data only (Contoso, Example MSP).
# Usage: pwsh -NoProfile -File time-entry-review/src/test.ps1
#        (needs node and js-yaml; set JS_YAML_PATH if js-yaml isn't installed in _shared)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:RUNNER_KV_NAME = 'kv-test'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ter-test-" + [guid]::NewGuid().ToString('N'))
& node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { throw 'time-entry-review.yml is out of date. Run node build.js first.' }
& node (Join-Path $PSScriptRoot 'build.js') --extract $tmp | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the steps.' }
$StepIds = @('node-inputs', 'node-find', 'node-review', 'node-send')
$Steps = @{}; foreach ($s in $StepIds) { $Steps[$s] = Get-Content -Raw (Join-Path $tmp "$s.ps1") }
Remove-Item -Recurse -Force $tmp

$Tally = @{ pass = 0; fail = 0 }
$Mock = @{ Secrets = @{}; Calls = (New-Object System.Collections.ArrayList); Opt = @{} }
function Get-AzKeyVaultSecret { [CmdletBinding()] param($VaultName, $Name, [switch]$AsPlainText) if ($Mock.Secrets.Contains($Name)) { return $Mock.Secrets[$Name] }; return $null }
function Start-Sleep { [CmdletBinding()] param([double]$Seconds = 0, [int]$Milliseconds = 0) }
function Get-NodeInput { return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function New-HttpError {
    param([int]$Code, [string]$Body = '')
    $r = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Code)
    $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new("Response status code does not indicate success: $Code.", $r)
    $er = [System.Management.Automation.ErrorRecord]::new($ex, 'WebCmdletWebResponseException', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
    if ($Body) { $er.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Body) }
    throw $er
}

# The review day is yesterday (UTC), so the date checks in Read inputs always pass.
$Day = [datetime]::UtcNow.Date.AddDays(-1)
$DayText = $Day.ToString('yyyy-MM-dd')
function Get-At { param([double]$Hours) return $Day.AddHours($Hours).ToString('yyyy-MM-ddTHH:mm:ssZ') }
$LongNote = 'Replaced the toner cartridge and cleared the stuck print queue on the Contoso print server.'
$Sum = @{ '101' = 'Printer offline at front desk'; '102' = 'Password reset for Pat'; '103' = 'Outlook keeps asking for password' }
function J { param($o) return ($o | ConvertTo-Json -Depth 20 | ConvertFrom-Json) }

function Get-TicketsFor {
    param([string]$Psa)
    if ($Mock.Opt.Contains('NoTickets')) { return @() }
    $ids = @('101', '102', '103')
    switch ($Psa) {
        'cw' { return @($ids | ForEach-Object { J @{ id = [int]$_; summary = $Sum[$_]; company = @{ id = 5; name = 'Contoso' }; contact = @{ id = 9; name = 'Pat Example' }; status = @{ name = 'Closed' }; closedFlag = $true; closedDate = (Get-At 10); owner = @{ identifier = 'jlee'; name = 'Jordan Lee' }; _info = @{ dateEntered = (Get-At -20); lastUpdated = (Get-At 10) } } }) }
        'at' { return @($ids | ForEach-Object { J @{ id = [int]$_; ticketNumber = "T$($DayText.Replace('-',''))-$_"; title = $Sum[$_]; companyID = 5; contactID = 9; status = 5; completedDate = (Get-At 10); createDate = (Get-At -20); lastActivityDate = (Get-At 10); assignedResourceID = 29 } }) }
        'halo' { return @($ids | ForEach-Object { J @{ id = [int]$_; summary = $Sum[$_]; client_id = 5; client_name = 'Contoso'; user_id = 9; user_name = 'Pat Example'; status_id = 9; agent_id = 3; agent_name = 'Jordan Lee'; dateoccurred = (Get-At -20); datecleared = (Get-At 10); lastactiondate = (Get-At 10) } }) + @(J @{ id = 199; summary = 'Closed the day before'; client_id = 5; client_name = 'Contoso'; user_id = 9; status_id = 9; agent_id = 3; dateoccurred = (Get-At -40); datecleared = (Get-At -5); lastactiondate = (Get-At -5) }) }
        'bms' { return @($ids | ForEach-Object { J @{ Id = [int]$_; TicketNumber = "TKT$_"; Title = $Sum[$_]; AccountId = 5; AccountName = 'Contoso'; ContactId = 9; ContactName = 'Pat Example'; StatusName = 'Completed'; CompletedDate = (Get-At 10); OpenDate = (Get-At -20); LastActivityUpdate = (Get-At 10); AssigneeId = 3; AssigneeName = 'Jordan Lee' } }) }
        'syncro' { return @($ids | ForEach-Object { J @{ id = [int]$_; number = 1000 + [int]$_; subject = $Sum[$_]; customer_id = 5; customer_business_then_name = 'Contoso'; contact_id = 9; contact_fullname = 'Pat Example'; status = 'Resolved'; resolved_at = (Get-At 10); created_at = (Get-At -20); updated_at = (Get-At 10); user_id = 3 } }) + @(J @{ id = 198; number = 1198; subject = 'Resolved two days ago'; customer_id = 5; status = 'Resolved'; resolved_at = (Get-At -30); created_at = (Get-At -50); updated_at = (Get-At -30); user_id = 3 }) }
        'zd' { return @($ids | ForEach-Object { J @{ id = [int]$_; subject = $Sum[$_]; organization_id = 5; requester_id = 9; status = 'solved'; assignee_id = 3; created_at = (Get-At -20); updated_at = (Get-At 10) } }) }
    }
}

# Like the real cmdlet, a JSON array reply is handed back as ONE object (", @(...)"), not item by item, and
# -MaximumRedirection is accepted (recorded as MaxRedirect, -1 when not sent) so the shared PSA code takes its no-redirect path.
function Invoke-RestMethod {
    [CmdletBinding()] param($Method = 'GET', $Uri, $Headers, $Body, $ContentType, $Form, [int]$MaximumRedirection = -1)
    $m = ([string]$Method).ToUpperInvariant(); $u = [string]$Uri; $d = [uri]::UnescapeDataString($u)
    $null = $Mock.Calls.Add([pscustomobject]@{ MaxRedirect = $MaximumRedirection; Method = $m; Uri = $u; Decoded = $d; Body = $(if ($Body -is [string]) { $Body } else { '' }); Headers = $Headers })
    # Postmark
    if ($u -eq 'https://api.postmark.test/email' -and $m -eq 'POST') {
        if ($Mock.Opt.Contains('PostmarkRefuse')) { return [pscustomobject]@{ ErrorCode = 300; Message = 'Invalid ''From'' address.' } }
        return [pscustomobject]@{ ErrorCode = 0; Message = 'OK'; MessageID = 'msg-1' }
    }
    # ConnectWise
    if ($u -like 'https://cw.example-msp.test/v4_6_release/apis/3.0/service/tickets[?]*' -and $m -eq 'GET') { if ($d -like '*page=1*') { return , @(Get-TicketsFor 'cw') }; return , @() }
    if ($u -like 'https://cw.example-msp.test/v4_6_release/apis/3.0/time/entries[?]*') {
        if ($Mock.Opt.Contains('Time403')) { New-HttpError 403 '{"code":"Forbidden","message":"You do not have access to this resource."}' }
        if ($d -match 'chargeToId=101') { return , @(J @{ id = 1; actualHours = 1.5; notes = $LongNote; internalNotes = ''; billableOption = 'Billable'; member = @{ identifier = 'jlee'; name = 'Jordan Lee' }; timeStart = (Get-At 9) }) }
        if ($d -match 'chargeToId=103') { return , @(J @{ id = 3; actualHours = 0.5; notes = 'fixed'; internalNotes = 'ok'; billableOption = $null; member = @{ identifier = 'slee'; name = 'Sam Lee' }; timeStart = (Get-At 9) }) }
        return , @()
    }
    # Autotask
    $at = 'https://webservices.example-msp.test/atservicesrest/v1.0'
    if ($u -eq "$at/Tickets/entityInformation/fields") { return J @{ fields = @(@{ name = 'status'; picklistValues = @(@{ value = '1'; label = 'New'; isActive = $true }, @{ value = '5'; label = 'Complete'; isActive = $true }) }) } }
    if ($u -like "$at/Tickets/query[?]*") { return J @{ items = @(Get-TicketsFor 'at'); pageDetails = @{ count = 3; nextPageUrl = $null } } }
    if ($u -like "$at/Companies/query[?]*") { return J @{ items = @(@{ id = 5; companyName = 'Contoso' }) } }
    if ($u -eq "$at/Resources/29") { return J @{ item = @{ id = 29; firstName = 'Jordan'; lastName = 'Lee' } } }
    if ($u -like "$at/TimeEntries/query[?]*") {
        if ($d -match '"value":101') { return J @{ items = @(@{ id = 1; hoursWorked = 1.5; summaryNotes = $LongNote; internalNotes = $null; isNonBillable = $false; resourceID = 29; dateWorked = (Get-At 9) }) } }
        if ($d -match '"value":103') { return J @{ items = @(@{ id = 3; hoursWorked = 0.25; summaryNotes = 'done'; internalNotes = ''; isNonBillable = $null; resourceID = 29; dateWorked = (Get-At 9) }) } }
        return J @{ items = @() }
    }
    # HaloPSA
    if ($u -eq 'https://halo.example-msp.test/auth/token') { return [pscustomobject]@{ access_token = 'halo-token' } }
    if ($u -like 'https://halo.example-msp.test/api/Tickets[?]*') { return J @{ tickets = @(Get-TicketsFor 'halo'); record_count = 4 } }
    if ($u -like 'https://halo.example-msp.test/api/Actions[?]*') {
        if ($d -match 'ticket_id=101&') { return J @{ actions = @(@{ id = 1; timetaken = 1.5; note = "<p>$LongNote</p>"; actionchargehours = 1.5; actionnonchargehours = 0; who = 'Jordan Lee'; datetime = (Get-At 9) }, @{ id = 2; timetaken = 0; note = 'Emailed the user' }) } }
        if ($d -match 'ticket_id=102&') { return J @{ actions = @(@{ id = 4; timetaken = 0; note = 'Closed' }) } }
        return J @{ actions = @(@{ id = 3; timetaken = 0.5; note = 'ok'; actionchargehours = 0; actionnonchargehours = 0; who = 'Sam Lee'; datetime = (Get-At 9) }) }
    }
    # Kaseya BMS
    if ($u -eq 'https://bms.example-msp.test/v2/security/authenticate') { return J @{ Success = $true; Result = @{ AccessToken = 'bms-token' } } }
    if ($u -like 'https://bms.example-msp.test/v2/servicedesk/tickets[?]*') { $r = @(Get-TicketsFor 'bms'); return J @{ Success = $true; Result = $r; TotalRecords = $r.Count } }
    if ($u -like 'https://bms.example-msp.test/v2/timelogs[?]*') {
        if ($d -match 'TicketId=101&') { return J @{ Success = $true; Result = @(@{ Id = 1; Timespent = 1.5; Notes = $LongNote; InternalNotes = ''; IsBillable = $true; FirstName = 'Jordan'; LastName = 'Lee'; StartDate = (Get-At 9) }) } }
        if ($d -match 'TicketId=103&') { return J @{ Success = $true; Result = @(@{ Id = 3; Timespent = 0.5; Notes = 'ok'; InternalNotes = ''; IsBillable = $null; FirstName = 'Sam'; LastName = 'Lee'; StartDate = (Get-At 9) }) } }
        return J @{ Success = $true; Result = @() }
    }
    # Syncro
    $sy = 'https://examplemsp.syncro.test/api/v1'
    if ($u -like "$sy/tickets[?]*") { return J @{ tickets = @(Get-TicketsFor 'syncro'); meta = @{ total_pages = 1; page = 1 } } }
    if ($u -like "$sy/ticket_timers[?]*") {
        if ($d -match 'ticket_id=101&') { return J @{ ticket_timers = @(@{ id = 1; active_duration = 5400; billable = $true; notes = $LongNote; user_id = 3; start_time = (Get-At 9) }); meta = @{ total_pages = 1 } } }
        if ($d -match 'ticket_id=103&') { return J @{ ticket_timers = @(@{ id = 3; active_duration = 900; billable = $null; notes = 'ok'; user_id = 3; start_time = (Get-At 9) }); meta = @{ total_pages = 1 } } }
        return J @{ ticket_timers = @(); meta = @{ total_pages = 1 } }
    }
    if ($u -like "$sy/tickets/*" -and $m -eq 'GET') { return J @{ ticket = @{ id = 102; line_items = @(@{ id = 7; name = 'Hardware: USB cable'; item = 'Cable'; quantity = 1; description = 'USB cable' }) } } }
    # Zendesk
    $zd = 'https://examplemsp.zendesk.test/api/v2'
    if ($u -like "$zd/search[?]*") { return J @{ results = @(Get-TicketsFor 'zd'); next_page = $null; count = 3 } }
    if ($u -like "$zd/tickets/*" -and $m -eq 'GET') {
        $id = ($u -split '/')[-1]
        $val = switch ($id) { '101' { 5400 } '102' { $null } default { 900 } }
        return J @{ ticket = @{ id = [int]$id; custom_fields = @(@{ id = 360001; value = $val }, @{ id = 360002; value = 'other' }); updated_at = (Get-At 10) } }
    }
    throw "Unmocked call: $m $u"
}

function Get-Calls { param([string]$Method, [string]$Like) return @($Mock.Calls | Where-Object { $_.Method -eq $Method -and $_.Uri -like $Like }) }
function Get-PsaWrites { return @($Mock.Calls | Where-Object { $_.Method -in @('PATCH', 'POST', 'PUT', 'DELETE') -and $_.Uri -notlike 'https://api.postmark.test/*' -and $_.Uri -notlike '*/auth/token' -and $_.Uri -notlike '*/security/authenticate' }) }
function Check { param([string]$Name, [bool]$Ok, $Detail = '') if ($Ok) { $Tally.pass++; Write-Host "PASS $Name" } else { $Tally.fail++; Write-Host "FAIL $Name :: $Detail" -ForegroundColor Red } }
function RoundTrip { param($o) if ($null -eq $o) { return $null }; return ($o | ConvertTo-Json -Depth 30 | ConvertFrom-Json) }

$BaseSecrets = @{
    'Postmark-ServerToken' = 'pm-token'; 'Postmark-FromEmail' = 'reports@example-msp.test'; 'Postmark-ApiUrl' = 'https://api.postmark.test'
    'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://cw.example-msp.test/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'p'; 'CW-PrivateKey' = 'k'; 'CW-ClientId' = 'c'
    'Autotask-ApiUrl' = 'https://webservices.example-msp.test'; 'Autotask-ApiIntegrationCode' = 'i'; 'Autotask-Username' = 'api@example-msp.test'; 'Autotask-Secret' = 's'
    'Halo-ApiUrl' = 'https://halo.example-msp.test'; 'Halo-ClientId' = 'hc'; 'Halo-ClientSecret' = 'hs'
    'KaseyaBMS-ApiUrl' = 'https://bms.example-msp.test'; 'KaseyaBMS-Username' = 'u'; 'KaseyaBMS-Password' = 'p'; 'KaseyaBMS-CompanyName' = 'examplemsp'
    'Syncro-ApiUrl' = 'https://examplemsp.syncro.test/api/v1'; 'Syncro-ApiKey' = 'k'
    'Zendesk-BaseUrl' = 'https://examplemsp.zendesk.test'; 'Zendesk-Email' = 'agent@example-msp.test'; 'Zendesk-ApiToken' = 't'
}

# Runs the workflow. Returns @{ out; error; step }.
function Invoke-Workflow {
    param($RunInput, [hashtable]$Secrets = @{}, [hashtable]$Opt = @{})
    $Mock.Secrets = $BaseSecrets.Clone(); foreach ($k in $Secrets.Keys) { if ($null -eq $Secrets[$k]) { $Mock.Secrets.Remove($k) } else { $Mock.Secrets[$k] = $Secrets[$k] } }
    $Mock.Calls.Clear(); $Mock.Opt = $Opt
    $global:NodeIn = $(if ($RunInput -is [string] -or $null -eq $RunInput) { $RunInput } else { RoundTrip $RunInput })
    $global:NodeOut = $null
    foreach ($s in $StepIds) {
        try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps[$s])) }
        catch { return @{ out = (RoundTrip $global:NodeOut); error = [string]$_.Exception.Message; step = $s } }
        $global:NodeIn = RoundTrip $global:NodeOut
    }
    return @{ out = $global:NodeIn; error = ''; step = 'end' }
}
function Get-Issues { param($o, [string]$Issue) return @($o.findings | Where-Object { $_.issue -eq $Issue } | ForEach-Object { [string]$_.ticket_id }) }

# 1. ConnectWise, emailed.
$r = Invoke-Workflow @{ date = $DayText; to = 'service.manager@example-msp.test' }
$o = $r.out
Check 'cw: no error' ($r.error -eq '') "$($r.step) $($r.error)"
Check 'cw: status success' ($o.status -eq 'success') $o.status
Check 'cw: three tickets reviewed' ($o.counts.tickets_closed -eq 3 -and $o.counts.tickets_checked -eq 3) ($o.counts | ConvertTo-Json -Compress)
Check 'cw: 102 closed with no time' (((Get-Issues $o 'no_time') -join ',') -eq '102') ((Get-Issues $o 'no_time') -join ',')
Check 'cw: 103 short note' (((Get-Issues $o 'short_note') -join ',') -eq '103') ((Get-Issues $o 'short_note') -join ',')
Check 'ConnectWise calls are sent with -MaximumRedirection 0' ((@($Mock.Calls | Where-Object { $_.Uri -like 'https://cw.example-msp.test/*' }).Count -gt 0) -and -not @($Mock.Calls | Where-Object { $_.Uri -like 'https://cw.example-msp.test/*' -and $_.MaxRedirect -ne 0 }).Count) (@($Mock.Calls | Where-Object { $_.Uri -like 'https://cw.example-msp.test/*' } | ForEach-Object { "$($_.Method) $($_.MaxRedirect)" }) -join ', ')
Check 'cw: 103 missing billable' (((Get-Issues $o 'missing_billable') -join ',') -eq '103') ''
Check 'cw: longer of notes and internal notes used' (@($o.findings | Where-Object { $_.issue -eq 'short_note' })[0].detail -match 'only 5 characters') @($o.findings)[1].detail
$cond = @(Get-Calls GET 'https://cw.example-msp.test/*/service/tickets[?]*')[0].Decoded
Check 'cw: closed-on-day conditions' ($cond -match "closedFlag=true and closedDate>=\[$($DayText)T00:00:00Z\] and closedDate<\[$($Day.AddDays(1).ToString('yyyy-MM-dd'))T00:00:00Z\]") $cond
$pm = @(Get-Calls POST 'https://api.postmark.test/email')
Check 'cw: one email sent' ($pm.Count -eq 1) $pm.Count
$pb = $pm[0].Body | ConvertFrom-Json
Check 'cw: email to the service manager from the Postmark sender' ($pb.To -eq 'service.manager@example-msp.test' -and $pb.From -eq 'reports@example-msp.test' -and $pb.MessageStream -eq 'outbound') ($pm[0].Body)
Check 'cw: server token header' ($pm[0].Headers['X-Postmark-Server-Token'] -eq 'pm-token') ''
Check 'cw: email is a plain table' ($pb.HtmlBody -match '<table' -and $pb.HtmlBody -match 'Password reset for Pat' -and $pb.HtmlBody -match 'No time logged' -and $pb.HtmlBody -match 'Jordan Lee') ''
Check 'cw: subject counts items' ($pb.Subject -eq "Time entry review for $($DayText): 3 items to check") $pb.Subject
Check 'cw: never writes to the PSA' (@(Get-PsaWrites).Count -eq 0) (@(Get-PsaWrites | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')
Check 'cw: plain message' ($o.message -match '^Of the 3 tickets closed in ConnectWise on' -and $o.message -match 'emailed to service.manager@example-msp.test') $o.message
Check 'cw: emailed_to set' (@($o.emailed_to).Count -eq 1) ''

# 2-5. The other five PSAs give the same findings.
foreach ($case in @(@('autotask', 'Autotask'), @('halopsa', 'HaloPSA'), @('kaseyabms', 'Kaseya BMS'), @('syncro', 'Syncro'))) {
    $r = Invoke-Workflow @{ date = $DayText; psa = $case[0]; to = 'service.manager@example-msp.test' }
    $o = $r.out
    $tag = $case[0]
    Check "$($tag): no error" ($r.error -eq '') "$($r.step) $($r.error)"
    Check "$($tag): three tickets in range" ($o.counts.tickets_closed -eq 3) ($o.counts | ConvertTo-Json -Compress)
    Check "$($tag): no time on 102" (((Get-Issues $o 'no_time') -join ',') -eq '102') ((Get-Issues $o 'no_time') -join ',')
    Check "$($tag): short note on 103" (((Get-Issues $o 'short_note') -join ',') -eq '103') ((Get-Issues $o 'short_note') -join ',')
    Check "$($tag): missing billable on 103" (((Get-Issues $o 'missing_billable') -join ',') -eq '103') ((Get-Issues $o 'missing_billable') -join ',')
    Check "$($tag): message names the PSA" ($o.message -match [regex]::Escape($case[1])) $o.message
    Check "$($tag): no PSA writes" (@(Get-PsaWrites).Count -eq 0) ''
}
$r = Invoke-Workflow @{ date = $DayText; psa = 'autotask' }
Check 'autotask: company name resolved' (@($r.out.findings)[0].company -eq 'Contoso') @($r.out.findings)[0].company
Check 'autotask: technician name looked up for the ticket closed with no time' (@($r.out.findings | Where-Object { $_.issue -eq 'no_time' })[0].technician -eq 'Jordan Lee') ($r.out.findings | ConvertTo-Json -Depth 4 -Compress)
$r = Invoke-Workflow @{ date = $DayText; psa = 'syncro' }
Check 'syncro: non-labour line item is not time' ((Get-Issues $r.out 'no_time') -contains '102') ''
Check 'syncro: line items read only when there is no timer' (@(Get-Calls GET 'https://examplemsp.syncro.test/api/v1/tickets/102').Count -eq 1 -and @(Get-Calls GET 'https://examplemsp.syncro.test/api/v1/tickets/101').Count -eq 0) ''

# 6. Zendesk without the Time Tracking field: says it can't check.
$r = Invoke-Workflow @{ date = $DayText; psa = 'zendesk'; to = 'service.manager@example-msp.test' }
$o = $r.out
Check 'zendesk: no error' ($r.error -eq '') "$($r.step) $($r.error)"
Check 'zendesk: incomplete' ($o.status -eq 'incomplete') $o.status
Check 'zendesk: says no native time' ($o.message -match 'Zendesk has no native time entries' -and ((@($o.warnings) -join ' ') -match 'zendesk_time_field_id')) $o.message
Check 'zendesk: nothing flagged' (@($o.findings).Count -eq 0) ''
Check 'zendesk: no ticket reads' (@(Get-Calls GET 'https://examplemsp.zendesk.test/api/v2/tickets/*').Count -eq 0) ''

# 7. Zendesk with the Time Tracking field id.
$r = Invoke-Workflow @{ date = $DayText; psa = 'zendesk'; zendesk_time_field_id = '360001' }
$o = $r.out
Check 'zendesk field: success' ($r.error -eq '' -and $o.status -eq 'success') "$($o.status) $($r.error)"
Check 'zendesk field: only no-time flagged' (((Get-Issues $o 'no_time') -join ',') -eq '102' -and @($o.findings).Count -eq 1) (@($o.findings | ForEach-Object { "$($_.ticket_id) $($_.issue)" }) -join '; ')
$zq = @(Get-Calls GET 'https://examplemsp.zendesk.test/api/v2/search*')[0].Decoded
Check 'zendesk field: solved search for the day' ($zq -match 'status>=solved' -and $zq -match "solved<$($Day.AddDays(1).ToString('yyyy-MM-dd'))T00:00:00Z") $zq

# 8. Missing permission (403) on time entries.
$r = Invoke-Workflow @{ date = $DayText } @{} @{ Time403 = $true }
Check '403: stops in Review step' ($r.step -eq 'node-review') $r.step
Check '403: plain permission message' ($r.error -eq "The ConnectWise API account isn't allowed to read time entries (HTTP 403). Give it read access to time entries and run again.") $r.error
Check '403: status error' ($r.out.status -eq 'error') $r.out.status
Check '403: no email sent' (@(Get-Calls POST 'https://api.postmark.test/email').Count -eq 0) ''

# 9. Empty result.
$r = Invoke-Workflow @{ date = $DayText; to = 'service.manager@example-msp.test' } @{} @{ NoTickets = $true }
$o = $r.out
Check 'empty: success' ($r.error -eq '' -and $o.status -eq 'success') "$($o.status) $($r.error)"
Check 'empty: plain message' ($o.message -match '^No tickets were closed in ConnectWise on') $o.message
Check 'empty: email still sent' (@(Get-Calls POST 'https://api.postmark.test/email').Count -eq 1) ''
Check 'empty: subject without count' ((@(Get-Calls POST 'https://api.postmark.test/email')[0].Body | ConvertFrom-Json).Subject -eq "Time entry review for $DayText") ''

# 10. No Postmark: report only in the output.
$r = Invoke-Workflow @{ date = $DayText; to = 'service.manager@example-msp.test' } @{ 'Postmark-ServerToken' = $null }
$o = $r.out
Check 'no postmark: success, not emailed' ($o.status -eq 'success' -and @($o.emailed_to).Count -eq 0) $o.status
Check 'no postmark: warning names the secret' ((@($o.warnings) -join ' ') -match "Postmark isn't set up \(add the Postmark-ServerToken secret\)") (@($o.warnings) -join ' | ')
Check 'no postmark: report_html in output' ($o.report_html -match '<table' -and $o.message -match 'not emailed') $o.message
Check 'no postmark: no calls to Postmark' (@(Get-Calls POST 'https://api.postmark.test/email').Count -eq 0) ''

# 11. Postmark refuses the sender.
$r = Invoke-Workflow @{ date = $DayText; to = 'service.manager@example-msp.test' } @{} @{ PostmarkRefuse = $true }
Check 'postmark refused: warning' ((@($r.out.warnings) -join ' ') -match "Postmark refused the email: Invalid 'From' address") (@($r.out.warnings) -join ' | ')

# 12. Daily Routine: no input. Yesterday in UTC, recipient from the secret.
$r = Invoke-Workflow $null @{ 'ServiceManager-Email' = 'dispatch@example-msp.test' }
$o = $r.out
Check 'routine: no error' ($r.error -eq '') "$($r.step) $($r.error)"
Check 'routine: yesterday in UTC' ($o.date -eq $DayText -or ($o.date -is [datetime] -and $o.date.ToString('yyyy-MM-dd') -eq $DayText)) $o.date
Check 'routine: timezone UTC' ($o.timezone -eq 'UTC') $o.timezone
Check 'routine: emailed the secret recipient' ((@(Get-Calls POST 'https://api.postmark.test/email')[0].Body | ConvertFrom-Json).To -eq 'dispatch@example-msp.test') ''

# 13. Time zone moves the day's window.
$r = Invoke-Workflow @{ date = $DayText; timezone = 'America/New_York' }
$cond = @(Get-Calls GET 'https://cw.example-msp.test/*/service/tickets[?]*')[0].Decoded
$ny = [TimeZoneInfo]::FindSystemTimeZoneById('America/New_York')
$exp = [TimeZoneInfo]::ConvertTimeToUtc([datetime]::SpecifyKind($Day, 'Unspecified'), $ny).ToString('yyyy-MM-ddTHH:mm:ssZ')
Check 'timezone: window starts at local midnight' ($r.error -eq '' -and $cond -match [regex]::Escape("closedDate>=[$exp]")) "$cond $($r.error)"

# 14. min_note_chars 0 and check_billable false turn those checks off.
$r = Invoke-Workflow @{ date = $DayText; min_note_chars = 0; check_billable = $false }
Check 'checks off: only no-time flagged' (@($r.out.findings).Count -eq 1 -and @($r.out.findings)[0].issue -eq 'no_time') (@($r.out.findings | ForEach-Object { $_.issue }) -join ',')

# 15. Bad input fails closed before any call.
$r = Invoke-Workflow @{ date = $Day.AddDays(3).ToString('yyyy-MM-dd') }
Check 'future date: incomplete in Read inputs' ($r.step -eq 'node-inputs' -and $r.out.status -eq 'incomplete' -and $r.error -match 'in the future') $r.error
$r = Invoke-Workflow @{ date = '07/10/2026' }
Check 'bad date format: incomplete' ($r.step -eq 'node-inputs' -and $r.error -match 'date must look like') $r.error
$r = Invoke-Workflow @{ timezone = 'Mars/Olympus' }
Check 'bad timezone: incomplete' ($r.step -eq 'node-inputs' -and $r.error -match "isn't a time zone") $r.error
$r = Invoke-Workflow @{ to = 'not-an-email' }
Check 'bad recipient: incomplete, no calls' ($r.step -eq 'node-inputs' -and $Mock.Calls.Count -eq 0) $r.error
$r = Invoke-Workflow @{ min_note_chars = 'twenty' }
Check 'bad min_note_chars: incomplete' ($r.step -eq 'node-inputs' -and $r.error -match 'whole number') $r.error

# 16. No PSA configured.
$r = Invoke-Workflow @{ date = $DayText } @{ 'PSA-Type' = $null; 'CW-ApiUrl' = $null }
Check 'no psa: plain error in Find step' ($r.step -eq 'node-find' -and $r.error -match 'No PSA is set up') $r.error

Write-Host "$($Tally.pass) passed, $($Tally.fail) failed"
if ($Tally.fail) { exit 1 }
exit 0
