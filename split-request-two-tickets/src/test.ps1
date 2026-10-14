# Strict-mode harness for Split Request - Service + Quote.
# Runs the "Split into service + quote tickets" step exactly as it is in split-request-service-quote.yml (shared
# PSA library included), through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the
# runner Key Vault, Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked.
# Placeholder data only (Contoso, Example MSP, example.com).
# Test variables start with T: the step runs in a child scope of this script, and a step variable of the
# same name would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File split-request-two-tickets/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot '..\..\_shared\inject.js') (Join-Path $PSScriptRoot '..') --check | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the shared PSA block is out of date: run node _shared/inject.js split-request-two-tickets' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\split-request-service-quote.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const a=d.definition.activities;const c=a.find(x=>x.id==='node-classify').properties;const n=a.find(x=>x.id==='node-2').properties;console.log(JSON.stringify({ids:a.map(x=>x.id).join(','),goal:c.goal,ext:(c.allowedExtensions||[]).join(','),params:JSON.stringify(n.parameters),script:n.script,webhook:String(d.definition.activities[0].properties.webhookEnabled)}))"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow keeps the node ids' ($Steps['ids'] -eq 'start,node-classify,end,node-2') $Steps['ids']
Check 'the classifier goal is bound to the trigger output' ($Steps['goal'] -like '*{{ nodes.trigger.output }}*')
Check 'the classifier is not given every extension' ($Steps['ext'] -eq 'cloudradial-v2-companies') $Steps['ext']
Check 'the ticket step binds intake and classification' ($Steps['params'] -like '*"intake"*{{ nodes.trigger.output }}*' -and $Steps['params'] -like '*"classification"*{{ nodes.node-classify.output }}*') $Steps['params']
Check 'webhook ships disabled' ($Steps['webhook'] -eq 'false')
Check 'the shared PSA library is pasted in' ($Steps['script'] -like '*function Invoke-Psa*' -and $Steps['script'] -notlike '*function New-CwTicket*')

# ---- runner mocks ----
$global:TIn = $null; $global:TOut = $null
function Get-NodeInput { param([string]$Name) if ($Name) { return (Get-SplitTestProp $global:TIn $Name) }; return $global:TIn }
function Get-SplitTestProp { param($o, $n) if ($null -eq $o) { return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Set-NodeOutput { param($o) $global:TOut = $o }
function Invoke-Split {
    param($In)
    $global:TIn = $(if ($null -eq $In) { $null } else { $In | ConvertTo-Json -Depth 12 | ConvertFrom-Json })
    $global:TOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps['script'])) } catch { $err = [string]$_.Exception.Message }
    $o = $null; if ($null -ne $global:TOut) { $o = ($global:TOut | ConvertTo-Json -Depth 12 | ConvertFrom-Json) }
    return @{ out = $o; error = $err }
}

# ---- placeholder intake and classifier answer ----
$TPayload = [ordered]@{ psa = 'connectwise'; company = '42'; formName = 'Add a New User'; subject = 'Alex Example'; userName = 'Alex Example'; email = 'alex.example@contoso.com'
    jobTitle = 'Accountant'; department = 'Finance'; startDate = '2026-10-20'; deviceType = 'Laptop with docking station'; softwareLicenses = 'Microsoft 365 Business Premium'; companyFileAccess = 'Finance shared drive' }
function New-TIntake { param([hashtable]$Set = @{}) $p = [ordered]@{}; foreach ($k in $TPayload.Keys) { $p[$k] = $TPayload[$k] }; foreach ($k in $Set.Keys) { $p[$k] = $Set[$k] }
    return [ordered]@{ subject = 'Add a New User: Alex Example'; formName = 'Add a New User'; body = 'New user Alex Example, Accountant in Finance, starting 2026-10-20. Needs a laptop.'; payload = $p } }
function New-TClass { param([switch]$NoPayload, $Payload = $null)
    $c = [ordered]@{ quoteItems = @('laptop', 'docking station'); serviceItems = @('Set up the account'); confidence = 0.95; multipleRequests = $false; reason = 'New user with hardware.'
        serviceTicket = [ordered]@{ summary = 'New User Setup - Alex Example'; description = 'Set up Alex Example.'; priority = 'Priority 3 - Normal Response'; type = 'Request'; subtype = 'New User' }
        quoteTicket = [ordered]@{ summary = 'Quote - Laptop - Alex Example'; description = 'Quote a laptop and dock.' }
        missingInfo = @(); standardsApplied = @('Service ticket summary format'); standardsSource = 'knowledge' }
    if (-not $NoPayload) { $c.payload = $(if ($Payload) { $Payload } else { (New-TIntake).payload }) }
    return $c }

# ---- placeholder ConnectWise ----
$TCW = 'https://api-na.example.com/v4_6_release/apis/3.0'
$TCwSecrets = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = $TCW; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'SECRET-cw-pub'; 'CW-PrivateKey' = 'SECRET-cw-priv'; 'CW-ClientId' = 'cid'
    'CW-ServiceBoard' = 'Professional Services'; 'CW-SalesBoard' = 'Test Board' }
$TCw = @{ next = 2001; made = (New-Object System.Collections.ArrayList); rejectExtras = $false; redirectFirst = $false; failQuote = $false }
function Reset-TCw { param([hashtable]$Secrets = $TCwSecrets) $TCw.next = 2001; $TCw.made.Clear(); $TCw.rejectExtras = $false; $TCw.redirectFirst = $false; $TCw.failQuote = $false; Reset-Mock $Secrets $TCwRouter }
$TCwRouter = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    if ($c.Method -eq 'POST' -and $u -like '*/service/tickets') {
        $b = $c.Body | ConvertFrom-Json
        if ($TCw.rejectExtras -and $b.PSObject.Properties['priority']) { New-HttpError 400 '{"code":"InvalidObject","message":"priority not found"}' }
        if ($TCw.failQuote -and $b.board.name -eq 'Test Board') { New-HttpError 400 '{"code":"InvalidObject","message":"board not found"}' }
        $id = $TCw.next; $TCw.next++
        $null = $TCw.made.Add([pscustomobject]@{ id = $id; summary = [string]$b.summary; board = [string]$b.board.name; company = [int]$b.company.id; body = $b })
        if ($TCw.redirectFirst -and $TCw.made.Count -eq 1) { New-HttpError 302 '' -Location 'https://api-staging.example.com/v4_6_release/apis/3.0/service/tickets' }
        return [pscustomobject]@{ id = $id; summary = [string]$b.summary }
    }
    if ($c.Method -eq 'GET' -and $u -like '*/service/tickets?*summary="*') {
        return , @($TCw.made | ForEach-Object { [pscustomobject]@{ id = $_.id; summary = $_.summary; dateEntered = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') } })
    }
    if ($c.Method -eq 'POST' -and $u -like '*/service/tickets/*/notes') { return [pscustomobject]@{ id = 9000 + $n } }
    if ($c.Method -eq 'GET' -and $u -like '*/company/companies?*identifier="Contoso"*') { return , @([pscustomobject]@{ id = 42; identifier = 'Contoso' }) }
    if ($c.Method -eq 'GET' -and $u -like '*/company/companies?*') { return , @() }
    if ($c.Method -eq 'GET' -and $u -match '/service/tickets/555$') { return [pscustomobject]@{ id = 555; board = [pscustomobject]@{ id = 1; name = 'Professional Services' }; status = [pscustomobject]@{ id = 16; name = 'New' } } }
    if ($c.Method -eq 'GET' -and $u -like '*/service/boards/1/statuses*') { return , @([pscustomobject]@{ id = 16; name = 'New'; closedStatus = $false }, [pscustomobject]@{ id = 99; name = 'Split'; closedStatus = $true }) }
    if ($c.Method -eq 'PATCH' -and $u -like '*/service/tickets/555') { return [pscustomobject]@{ id = 555 } }
    return $null
}
function Get-TNotes { return @($Mock.Calls | Where-Object { $_.Method -eq 'POST' -and $_.Uri -like '*/service/tickets/*/notes' }) }

# 1. ConnectWise, parameters wiring (intake + classification): both tickets, on the right boards, with notes.
Reset-TCw
$r = Invoke-Split ([ordered]@{ intake = (New-TIntake); classification = (New-TClass -NoPayload) })
Check 'cw: success' ($r.error -eq '' -and $r.out.status -eq 'success') "$($r.error) $(Show-Calls)"
Check 'cw: two tickets, service on the service board, quote on the quote board' ($TCw.made.Count -eq 2 -and $TCw.made[0].board -eq 'Professional Services' -and $TCw.made[1].board -eq 'Test Board' -and $TCw.made[0].company -eq 42) (($TCw.made | ForEach-Object { "$($_.id) $($_.board)" }) -join '; ')
Check 'cw: the classifier text, priority, type and subtype are used' ($TCw.made[0].summary -eq 'New User Setup - Alex Example' -and $TCw.made[0].body.priority.name -eq 'Priority 3 - Normal Response' -and $TCw.made[0].body.type.name -eq 'Request' -and $TCw.made[0].body.subType.name -eq 'New User') ($TCw.made[0].body | ConvertTo-Json -Compress -Depth 5)
Check 'cw: output names both tickets and the PSA' ($r.out.serviceTicketId -eq 2001 -and $r.out.quoteTicketId -eq 2002 -and $r.out.psa -eq 'ConnectWise' -and $r.out.formattedBy -like 'classifier*') ($r.out | ConvertTo-Json -Compress -Depth 4)
$notes = @(Get-TNotes)
Check 'cw: an internal note on each ticket' ($notes.Count -eq 2 -and $notes[0].Uri -like '*/tickets/2001/notes' -and $notes[1].Uri -like '*/tickets/2002/notes' -and (Read-Body $notes[0]).internalAnalysisFlag -eq $true) (Show-Calls)
Check 'cw: the note says where each ticket went' ((Read-Body $notes[0]).text -like '*Service ticket: #2001 on board Professional Services*' -and (Read-Body $notes[0]).text -like '*Quote ticket: #2002 on board Test Board*') (Read-Body $notes[0]).text
Check 'cw: writes never follow a redirect' (-not @($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and $_.MaxRedirect -ne 0 }).Count) (Show-Calls)

# 2. ConnectWise rejects the priority name: the ticket is made again without priority, type and subtype.
Reset-TCw; $TCw.rejectExtras = $true
$r = Invoke-Split ([ordered]@{ intake = (New-TIntake); classification = (New-TClass -NoPayload) })
Check 'cw reject: still succeeds' ($r.error -eq '' -and $r.out.serviceTicketId -eq 2001) "$($r.error)"
Check 'cw reject: retried without the names, with a warning' ($TCw.made.Count -eq 2 -and -not $TCw.made[0].body.PSObject.Properties['priority'] -and (@($r.out.warnings) -join ' ') -like '*rejected the priority/type/subtype*') (@($r.out.warnings) -join ' | ')

# 3. ConnectWise makes the ticket and answers with a redirect: found by search, never created twice.
Reset-TCw; $TCw.redirectFirst = $true
$r = Invoke-Split ([ordered]@{ intake = (New-TIntake); classification = (New-TClass -NoPayload) })
$posts = @($Mock.Calls | Where-Object { $_.Method -eq 'POST' -and $_.Uri -like '*/service/tickets' })
Check 'cw redirect: succeeds with the ticket it made' ($r.error -eq '' -and $r.out.serviceTicketId -eq 2001 -and $r.out.quoteTicketId -eq 2002) "$($r.error) $(Show-Calls)"
Check 'cw redirect: the service ticket was not sent twice' ($TCw.made.Count -eq 2 -and @($TCw.made | Where-Object { $_.summary -eq 'New User Setup - Alex Example' }).Count -eq 1) (($TCw.made | ForEach-Object { $_.summary }) -join '; ')
Check 'cw redirect: says so in the warnings' ((@($r.out.warnings) -join ' ') -like '*redirect*') (@($r.out.warnings) -join ' | ')

# 4. Older wiring: no parameters, the classifier's output (with the intake echoed under payload) is the node input.
Reset-TCw
$r = Invoke-Split (New-TClass)
Check 'old wiring: still works from the echoed payload' ($r.error -eq '' -and $r.out.serviceTicketId -eq 2001 -and $TCw.made[0].company -eq 42) "$($r.error)"

# 5. The classifier answered but the intake reached nobody: a clear error, nothing created.
Reset-TCw
$r = Invoke-Split (New-TClass -NoPayload)
Check 'no intake: fails before creating anything, and says how to fix it' ($r.error -like "*Bind the step's 'intake' parameter*" -and $TCw.made.Count -eq 0) $r.error

# 6. Company given as a ConnectWise identifier.
Reset-TCw
$r = Invoke-Split ([ordered]@{ intake = (New-TIntake @{ company = 'Contoso' }); classification = (New-TClass -NoPayload) })
Check 'cw identifier: resolved to the company id' ($r.error -eq '' -and $TCw.made[0].company -eq 42) "$($r.error) $(Show-Calls)"

# 7. The quote ticket fails after the service ticket exists: reported, not thrown, and the service ticket still gets its note.
Reset-TCw; $TCw.failQuote = $true
$r = Invoke-Split ([ordered]@{ intake = (New-TIntake); classification = (New-TClass -NoPayload) })
Check 'quote fails: run still succeeds, flagged for review' ($r.error -eq '' -and $r.out.serviceTicketId -eq 2001 -and $r.out.quoteTicketId -eq 0 -and $r.out.reviewRequired -eq $true) "$($r.error) $($r.out | ConvertTo-Json -Compress -Depth 3)"
Check 'quote fails: says to raise it by hand, and the note says so' ((@($r.out.warnings) -join ' ') -like '*raise it by hand*' -and (Read-Body @(Get-TNotes)[0]).text -like '*Quote ticket: NOT CREATED*') (@($r.out.warnings) -join ' | ')

# 8. ConnectWise with no service board anywhere: a clear error, nothing created.
$TNoBoards = @{}; foreach ($k in $TCwSecrets.Keys) { if ($k -notlike '*Board') { $TNoBoards[$k] = $TCwSecrets[$k] } }
Reset-TCw $TNoBoards
$r = Invoke-Split ([ordered]@{ intake = (New-TIntake); classification = (New-TClass -NoPayload) })
Check 'cw no board: refuses before creating anything' ($r.error -like 'No service board set*' -and $TCw.made.Count -eq 0) $r.error

# 9. PSA-ServiceQueue / PSA-QuoteQueue win over the CW-* board secrets.
$TQ = @{}; foreach ($k in $TCwSecrets.Keys) { $TQ[$k] = $TCwSecrets[$k] }; $TQ['PSA-ServiceQueue'] = 'Service Desk'; $TQ['PSA-QuoteQueue'] = 'Sales'
Reset-TCw $TQ
$r = Invoke-Split ([ordered]@{ intake = (New-TIntake); classification = (New-TClass -NoPayload) })
Check 'queue secrets: PSA-ServiceQueue and PSA-QuoteQueue are used' ($r.error -eq '' -and $TCw.made[0].board -eq 'Service Desk' -and $TCw.made[1].board -eq 'Sales') (($TCw.made | ForEach-Object { $_.board }) -join ', ')

# 10. A source ticket: noted and closed with the split status.
Reset-TCw
$r = Invoke-Split ([ordered]@{ intake = (New-TIntake @{ psaTicketId = '555'; closeSourceTicket = 'true'; splitClosedStatus = 'Split' }); classification = (New-TClass -NoPayload) })
$patch = @($Mock.Calls | Where-Object { $_.Method -eq 'PATCH' -and $_.Uri -like '*/service/tickets/555' })
Check 'source ticket: noted and set to the split status' ($r.error -eq '' -and @(Get-TNotes | Where-Object { $_.Uri -like '*/tickets/555/notes' }).Count -eq 1 -and $patch.Count -eq 1 -and (Read-Body $patch[0])[0].value.id -eq 99) "$($r.error) $(Show-Calls)"

# 11. Zendesk: the same split through the shared library, priority sent as a level.
$TZdUrl = 'https://example.zendesk.com/api/v2'
$TZd = @{ next = 3001; made = (New-Object System.Collections.ArrayList) }
$TZdRouter = {
    param($c, $n)
    if ($c.Method -eq 'POST' -and $c.Uri -eq "$TZdUrl/tickets") { $b = $c.Body | ConvertFrom-Json; $id = $TZd.next; $TZd.next++; $null = $TZd.made.Add($b.ticket); return [pscustomobject]@{ ticket = [pscustomobject]@{ id = $id } } }
    if ($c.Method -eq 'PUT' -and $c.Uri -like "$TZdUrl/tickets/*") { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1 } } }
    return $null
}
Reset-Mock @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'SECRET-zd-tok' } $TZdRouter
$zc = New-TClass -NoPayload; $zc.serviceTicket.priority = 'High'
$r = Invoke-Split ([ordered]@{ intake = (New-TIntake @{ psa = 'zendesk'; company = '77' }); classification = $zc })
Check 'zendesk: both tickets made for the organization' ($r.error -eq '' -and $TZd.made.Count -eq 2 -and $TZd.made[0].organization_id -eq 77 -and $r.out.psa -eq 'Zendesk') "$($r.error) $(Show-Calls)"
Check 'zendesk: priority sent as a level, no ConnectWise fields' ($TZd.made[0].priority -eq 'high' -and -not $TZd.made[0].PSObject.Properties['type']) ($TZd.made[0] | ConvertTo-Json -Compress -Depth 4)
Check 'zendesk: an internal note on each ticket, default queue named' (@($Mock.Calls | Where-Object { $_.Method -eq 'PUT' }).Count -eq 2 -and $r.out.internalSummary -like '*Service ticket: #3001 in the default queue*') "$(Show-Calls) $($r.out.internalSummary)"

Complete-Test
