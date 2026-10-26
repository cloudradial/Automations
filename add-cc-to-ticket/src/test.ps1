# Strict-mode harness for Add CC to Ticket.
# Runs the PowerShell step exactly as it is in add-cc-to-ticket.yml (shared PSA library included), through
# & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the runner Key Vault,
# Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked. Each mock PSA keeps one ticket (1001) whose
# CC list the step's writes really change, so the read-back after a write sees what was written.
# Placeholder data only (Contoso, Fabrikam, Example MSP, example.com).
# Test variables start with T: the step runs in a child scope of this script, and a step variable of the
# same name would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File add-cc-to-ticket/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\add-cc-to-ticket.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={ids:d.definition.activities.map(a=>a.id).join(',')};for(const a of d.definition.activities){if(a.type==='powershell-script'){o[a.id]=a.properties.script;o[a.id+'.params']=JSON.stringify(a.properties.parameters)}};o.webhook=String(d.definition.activities.find(a=>a.id==='start').properties.webhookEnabled);console.log(JSON.stringify(o));"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow keeps the node ids start, node-2, end' ($Steps['ids'] -eq 'start,node-2,end') $Steps['ids']
Check 'node-2 is bound to the trigger output' ($Steps['node-2.params'] -like '*{{ nodes.trigger.output }}*')
Check 'webhook ships disabled' ($Steps['webhook'] -eq 'false')
Check 'the shared PSA library is pasted in' ($Steps['node-2'] -like '*function Invoke-Psa*' -and $Steps['node-2'] -like '*function Get-CcTicket*')

# ---- runner mocks ----
$global:NodeIn = $null; $global:NodeOut = $null
function Get-NodeInput { return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
# Runs node-2 with the body wrapped as the trigger parameter. Returns @{ out; error }.
function Invoke-Cc {
    param($Body, [switch]$Raw)
    $global:NodeIn = $(if ($Raw) { $Body } else { [pscustomobject]@{ trigger = ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json) } })
    $global:NodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps['node-2'])) } catch { $err = [string]$_.Exception.Message }
    $o = $null; if ($null -ne $global:NodeOut) { $o = ($global:NodeOut | ConvertTo-Json -Depth 12 | ConvertFrom-Json) }
    return @{ out = $o; error = $err }
}

# ---- placeholder PSAs ----
$TSecret = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://api-na.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'SECRET-cw-pub'; 'CW-PrivateKey' = 'SECRET-cw-priv'; 'CW-ClientId' = 'SECRET-cw-cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices5.autotask.example'; 'Autotask-ApiIntegrationCode' = 'SECRET-at-code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'SECRET-at-sec' }
    halopsa     = @{ 'PSA-Type' = 'halopsa'; 'Halo-ApiUrl' = 'https://example.halopsa.example'; 'Halo-ClientId' = 'SECRET-halo-id'; 'Halo-ClientSecret' = 'SECRET-halo-sec' }
    kaseyabms   = @{ 'PSA-Type' = 'kaseyabms'; 'KaseyaBMS-ApiUrl' = 'https://api.bms.example'; 'KaseyaBMS-Username' = 'api@example.com'; 'KaseyaBMS-Password' = 'SECRET-bms-pw'; 'KaseyaBMS-CompanyName' = 'examplemsp'; 'KaseyaBMS-NoteTypeId' = '3' }
    syncro      = @{ 'PSA-Type' = 'syncro'; 'Syncro-ApiUrl' = 'https://examplemsp.syncromsp.example/api/v1'; 'Syncro-ApiKey' = 'SECRET-syncro-key' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'SECRET-zd-tok' }
}
function Get-TSecrets { param([string]$P, [hashtable]$Extra = @{}) $s = @{}; foreach ($k in $TSecret[$P].Keys) { $s[$k] = $TSecret[$P][$k] }; foreach ($k in $Extra.Keys) { $s[$k] = $Extra[$k] }; return $s }
$TCW = 'https://api-na.example.com/v4_6_release/apis/3.0'; $TAT = 'https://webservices5.autotask.example/atservicesrest/v1.0'
$THA = 'https://example.halopsa.example/api'; $TBM = 'https://api.bms.example/v2'; $TZD = 'https://example.zendesk.com/api/v2'
$TAuth = @('POST https://example.halopsa.example/auth/token', 'POST https://api.bms.example/v2/security/authenticate')

# People: email -> PSA contact/user id and company. Unknown addresses get an id when a PSA first sees them.
$TDir = @{}
function Reset-TDir {
    $TDir.Clear()
    $TDir['megan.bowen@contoso.com'] = @{ id = 501; co = 42 }
    $TDir['adele.vance@contoso.com'] = @{ id = 502; co = 42 }
    $TDir['alex.wilber@contoso.com'] = @{ id = 503; co = 42 }
    $TDir['pat.lee@fabrikam.example'] = @{ id = 601; co = 77 }
}
function Get-TId { param([string]$Email) $k = $Email.ToLowerInvariant(); if (-not $TDir.ContainsKey($k)) { $TDir[$k] = @{ id = 900 + $TDir.Count; co = 0 } }; return $TDir[$k].id }
function Get-TEmail { param($Id) foreach ($k in $TDir.Keys) { if ([string]$TDir[$k].id -eq [string]$Id) { return $k } }; return '' }

# Ticket 1001, the same on every PSA: company 42, contact Megan, Adele already copied.
$TS = @{}
function Reset-T {
    Reset-TDir
    $TS.company = 42; $TS.contact = 'megan.bowen@contoso.com'; $TS.cc = @('adele.vance@contoso.com'); $TS.flag = $true; $TS.contactBlank = $false
    $TS.notes = New-Object System.Collections.ArrayList
    $TS.noteFail = 0; $TS.writeFail = 0; $TS.ignoreWrite = $false; $TS.writeRedirect = $false; $TS.notesReadFail = 0
}
function Add-TNote { param([string]$Text) if ($TS.noteFail) { New-HttpError $TS.noteFail '{"message":"Insufficient security level to add notes"}' }; $null = $TS.notes.Add($Text) }
function Set-TCc { param($List) if (-not $TS.ignoreWrite) { $TS.cc = @($List | Where-Object { $_ }) } }
function Invoke-TWrite { param([scriptblock]$Apply) if ($TS.writeFail) { New-HttpError $TS.writeFail '{"code":"InvalidObject","message":"automaticEmailCc: you do not have permission to update this field"}' }; & $Apply; if ($TS.writeRedirect) { New-HttpError 302 '' -Location 'https://api-na.example.com/v4_6_release/apis/3.0/service/tickets/1001' } }
function Get-TQuery { param([string]$Uri) $s = [uri]::UnescapeDataString(($Uri -split 'search=', 2)[1]); return ($s | ConvertFrom-Json) }
function Get-TFilter { param($Search, [string]$Field) foreach ($f in @($Search.filter)) { if ($f.field -eq $Field) { return $f.value } }; return $null }

$Handler = {
    param($c, $n)
    $k = "$($c.Method) $($c.Uri)"
    if ($TS.notesReadFail -and $c.Method -eq 'GET' -and $c.Uri -match '(?i)/notes|/Actions\?|/comments|TicketNotes/query') { New-HttpError $TS.notesReadFail '{"message":"Forbidden"}' }
    switch -Wildcard -CaseSensitive ($k) {
        # ConnectWise
        "GET $TCW/service/tickets/1001/notes*" { return , @($TS.notes | ForEach-Object -Begin { $i = 0 } -Process { $i++; [pscustomobject]@{ id = $i; text = $_; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false } }) }
        "GET $TCW/service/tickets/1001" { return [pscustomobject]@{ id = 1001; summary = 'Printer offline'; company = [pscustomobject]@{ id = $TS.company; identifier = $(if ($TS.company -eq 42) { 'ContosoLtd' } else { 'FabrikamInc' }) }; contact = [pscustomobject]@{ id = 55 }; contactEmailAddress = $(if ($TS.contactBlank) { '' } else { $TS.contact }); automaticEmailCc = ($TS.cc -join ';'); automaticEmailCcFlag = $TS.flag } }
        "GET $TCW/company/contacts/55" { return [pscustomobject]@{ id = 55; communicationItems = @([pscustomobject]@{ communicationType = 'Phone'; value = '555-0100'; defaultFlag = $true }, [pscustomobject]@{ communicationType = 'Email'; value = $TS.contact; defaultFlag = $true }) } }
        "PATCH $TCW/service/tickets/1001" { Invoke-TWrite { $ops = Read-Body $c; foreach ($o in @($ops)) { if ($o.path -eq 'automaticEmailCc') { Set-TCc ($o.value -split ';') }; if ($o.path -eq 'automaticEmailCcFlag' -and -not $TS.ignoreWrite) { $TS.flag = [bool]$o.value } } }; return [pscustomobject]@{ id = 1001 } }
        "POST $TCW/service/tickets/1001/notes" { Add-TNote (Read-Body $c).text; return [pscustomobject]@{ id = 9001 } }
        # Autotask
        "GET $TAT/Tickets/1001" { return [pscustomobject]@{ item = [pscustomobject]@{ id = 1001; title = 'Printer offline'; companyID = $TS.company; contactID = 501; status = 1 } } }
        "GET $TAT/Contacts/501" { return [pscustomobject]@{ item = [pscustomobject]@{ id = 501; emailAddress = $TS.contact } } }
        "GET $TAT/TicketAdditionalContacts/query*" { return [pscustomobject]@{ items = @($TS.cc | ForEach-Object { [pscustomobject]@{ id = 1; ticketID = 1001; contactID = (Get-TId $_) } }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
        "GET $TAT/Contacts/query*" {
            $s = Get-TQuery $c.Uri
            $ids = Get-TFilter $s 'id'; $mail = Get-TFilter $s 'emailAddress'; $co = Get-TFilter $s 'companyID'
            $rows = @()
            if ($null -ne $ids) { $rows = @(@($ids) | ForEach-Object { [pscustomobject]@{ id = $_; emailAddress = (Get-TEmail $_) } }) }
            elseif ($mail) { $e = ([string]$mail).ToLowerInvariant(); if ($TDir.ContainsKey($e) -and [string]$TDir[$e].co -eq [string]$co) { $rows = @([pscustomobject]@{ id = $TDir[$e].id; emailAddress = $e }) } }
            return [pscustomobject]@{ items = $rows; pageDetails = [pscustomobject]@{ nextPageUrl = $null } }
        }
        "POST $TAT/Tickets/1001/AdditionalContacts" { Invoke-TWrite { $b = Read-Body $c; Set-TCc (@($TS.cc) + (Get-TEmail $b.contactID)) }; return [pscustomobject]@{ itemId = 7001 } }
        "GET $TAT/TicketNotes/entityInformation/fields" { return [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                    [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) } }
        "GET $TAT/TicketNotes/query*" { return [pscustomobject]@{ items = @($TS.notes | ForEach-Object { [pscustomobject]@{ id = 1; description = $_; publish = 2 } }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
        "POST $TAT/Tickets/1001/Notes" { Add-TNote (Read-Body $c).description; return [pscustomobject]@{ itemId = 3001 } }
        # HaloPSA
        'POST https://example.halopsa.example/auth/token' { return [pscustomobject]@{ access_token = 'SECRET-halo-token' } }
        "GET $THA/Tickets/1001?includedetails=true" { return [pscustomobject]@{ id = 1001; summary = 'Printer offline'; client_id = $TS.company; user_id = 7; user_email = $TS.contact; emailcclist = ($TS.cc -join ';') } }
        "POST $THA/Tickets" { Invoke-TWrite { $b = @(Read-Body $c)[0]; Set-TCc ($b.emailcclist -split ';') }; return , @([pscustomobject]@{ id = 1001 }) }
        "POST $THA/Actions" { Add-TNote @(Read-Body $c)[0].note; return , @([pscustomobject]@{ id = 1 }) }
        "GET $THA/Actions?ticket_id=1001*" { return [pscustomobject]@{ actions = @($TS.notes | ForEach-Object { [pscustomobject]@{ id = 1; note = $_; hiddenfromuser = $true } }) } }
        # Kaseya BMS
        'POST https://api.bms.example/v2/security/authenticate' { return [pscustomobject]@{ Result = [pscustomobject]@{ AccessToken = 'SECRET-bms-token' } } }
        "GET $TBM/servicedesk/tickets/1001/notes*" { return [pscustomobject]@{ Result = @($TS.notes | ForEach-Object { [pscustomobject]@{ Id = 1; Details = $_; IsInternal = $true } }) } }
        "GET $TBM/servicedesk/tickets/1001" { return [pscustomobject]@{ Result = [pscustomobject]@{ Id = 1001; Title = 'Printer offline'; AccountId = $TS.company; ContactEmail = $TS.contact; CCs = @($TS.cc | ForEach-Object { [pscustomobject]@{ Id = (Get-TId $_); EmailAddress = $_; FullName = ''; EntityType = 1 } }) } } }
        "GET $TBM/servicedesk/tickets/ticketCcs/42?*" { $want = [uri]::UnescapeDataString((($c.Uri -split 'SearchString=', 2)[1] -split '&')[0]); return [pscustomobject]@{ Result = @($TDir.Keys | Where-Object { $_ -eq $want -and $TDir[$_].co -eq 42 } | ForEach-Object { [pscustomobject]@{ Id = $TDir[$_].id; EmailAddress = $_; FullName = ''; EntityType = 1 } }) } }
        "PATCH $TBM/servicedesk/tickets/1001" { Invoke-TWrite { $ops = @(Read-Body $c); $global:TBmsPatch = $ops; Set-TCc (@($ops[0].value) | ForEach-Object { $_.EmailAddress }) }; return [pscustomobject]@{ Success = $true } }
        "POST $TBM/servicedesk/tickets/1001/notes" { Add-TNote (Read-Body $c).Details; return [pscustomobject]@{ Result = [pscustomobject]@{ Id = 1 } } }
        # Zendesk
        "GET $TZD/tickets/1001/comments*" { return [pscustomobject]@{ comments = @($TS.notes | ForEach-Object { [pscustomobject]@{ id = 1; body = $_; public = $false; author_id = 1 } }); next_page = $null } }
        "GET $TZD/tickets/1001" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1001; subject = 'Printer offline'; organization_id = $TS.company; requester_id = 501; email_cc_ids = @($TS.cc | ForEach-Object { Get-TId $_ }); status = 'open'; assignee_id = $null } } }
        "GET $TZD/users/show_many?ids=*" { $ids = (($c.Uri -split 'ids=', 2)[1]) -split ','; return [pscustomobject]@{ users = @($ids | ForEach-Object { [pscustomobject]@{ id = [long]$_; email = $(if ([string]$_ -eq '501') { $TS.contact } else { Get-TEmail $_ }) } }) } }
        "PUT $TZD/tickets/1001" {
            $b = Read-Body $c
            if ($null -ne $b.ticket.PSObject.Properties['comment']) { Add-TNote $b.ticket.comment.body }
            if ($null -ne $b.ticket.PSObject.Properties['email_ccs']) { Invoke-TWrite { foreach ($x in @($b.ticket.email_ccs)) { $null = Get-TId $x.user_email; Set-TCc (@($TS.cc) + $x.user_email) } } }
            return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1001 } }
        }
    }
    throw "Unexpected call in test: $k"
}
function Get-WriteCalls { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and $TAuth -notcontains "$($_.Method) $($_.Uri)" }) }
function Get-NoteCalls { return @(Get-WriteCalls | Where-Object { $_.Uri -match '(?i)/notes$|/Actions$' -or ($_.Method -eq 'PUT' -and $_.Body -like '*"comment"*') }) }
$TBase = @{ ticketNumber = '1001'; ccEmail = 'alex.wilber@contoso.com'; requester_email = 'megan.bowen@contoso.com'; company_psa_id = '42' }
function New-TBody { param([hashtable]$Over = @{}) $b = @{}; foreach ($k in $TBase.Keys) { $b[$k] = $TBase[$k] }; foreach ($k in $Over.Keys) { if ($null -eq $Over[$k]) { $b.Remove($k) } else { $b[$k] = $Over[$k] } }; return $b }
function Test-CcInList { param([string]$E, $L) foreach ($x in @($L)) { if ([string]$x -ieq $E) { return $true } }; return $false }
function Test-NoDash { param($o) return (($o | ConvertTo-Json -Depth 8) -notmatch "[$([char]0x2013)$([char]0x2014)]") }
function Test-NoSecret { param($o) return (($o | ConvertTo-Json -Depth 8) -notmatch 'SECRET-') }
$TOutFields = @('status', 'message', 'ticket_id', 'cc_email', 'added', 'cc_list', 'actions', 'warnings', 'internal_note', 'public_note')
function Test-Shape { param($o) if ($null -eq $o) { return $false }; foreach ($f in $TOutFields) { if ($null -eq $o.PSObject.Properties[$f]) { return $false } }; return $true }

# ---- 1. Success on each PSA ----
foreach ($TP in @('connectwise', 'autotask', 'halopsa', 'kaseyabms', 'zendesk')) {
    Reset-T; Reset-Mock (Get-TSecrets $TP) $Handler
    $r = Invoke-Cc (New-TBody)
    $o = $r.out
    Check "$TP add: status success, added" ($o.status -eq 'success' -and $o.added -eq $true -and -not $r.error) "$($o.status) $($o.message) $($r.error)"
    Check "$TP add: the ticket's CC list now has the address" (Test-CcInList 'alex.wilber@contoso.com' $TS.cc) ($TS.cc -join ';')
    Check "$TP add: the address already copied is kept" (Test-CcInList 'adele.vance@contoso.com' $TS.cc) ($TS.cc -join ';')
    Check "$TP add: cc_list output from the read-back" ((@($o.cc_list) -join ';') -like '*alex.wilber@contoso.com*' -and (@($o.cc_list) -join ';') -like '*adele.vance@contoso.com*') (@($o.cc_list) -join ';')
    Check "$TP add: an internal note naming the address and the requester, then a public note" ($TS.notes.Count -eq 2 -and $TS.notes[0] -like '*alex.wilber@contoso.com*megan.bowen@contoso.com*') ($TS.notes -join ' | ')
    Check "$TP add: the public note tells the new CC what the ticket is about and who asked" ($TS.notes[1] -like '*alex.wilber@contoso.com has been copied on ticket 1001, "Printer offline"*megan.bowen@contoso.com*' -and $o.public_note -eq $TS.notes[1]) "$($TS.notes -join ' | ') || $($o.public_note)"
    Check "$TP add: output shape, plain message, no secrets" ((Test-Shape $o) -and (Test-NoDash $o) -and (Test-NoSecret $o) -and $o.message -eq 'Added alex.wilber@contoso.com to the CC list on ticket 1001.' -and $o.ticket_id -eq '1001' -and $o.cc_email -eq 'alex.wilber@contoso.com') $o.message
    Check "$TP add: no warnings" (@($o.warnings).Count -eq 0) (@($o.warnings) -join ' | ')
}
# PSA-specific write shapes
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler; $TS.flag = $false; $TS.cc = @()
$r = Invoke-Cc (New-TBody)
$TPatch = @(Get-Calls 'PATCH' "$TCW/service/tickets/1001")
Check 'connectwise: json-patch replaces automaticEmailCc and turns automaticEmailCcFlag on' ($TPatch.Count -eq 1 -and $TPatch[0].Body -like '*"op":"replace","path":"automaticEmailCc","value":"alex.wilber@contoso.com"*' -and $TPatch[0].Body -like '*"path":"automaticEmailCcFlag","value":true*' -and $TS.flag -eq $true) $TPatch[0].Body
Check 'connectwise: internal note on the Internal tab' ((Read-Body @(Get-Calls 'POST' "$TCW/service/tickets/1001/notes")[0]).internalAnalysisFlag -eq $true)
Reset-T; Reset-Mock (Get-TSecrets 'autotask') $Handler
$r = Invoke-Cc (New-TBody)
$TPost = @(Get-Calls 'POST' "$TAT/Tickets/1001/AdditionalContacts")
Check 'autotask: adds the company contact by id to TicketAdditionalContacts' ($TPost.Count -eq 1 -and (Read-Body $TPost[0]).contactID -eq 503 -and (Read-Body $TPost[0]).ticketID -eq 1001) (Show-Calls)
Reset-T; Reset-Mock (Get-TSecrets 'halopsa') $Handler
$r = Invoke-Cc (New-TBody)
Check 'halopsa: POST /Tickets with id and the whole emailcclist' ((Read-Body @(Get-Calls 'POST' "$THA/Tickets")[0])[0].emailcclist -eq 'adele.vance@contoso.com;alex.wilber@contoso.com')
Reset-T; Reset-Mock (Get-TSecrets 'kaseyabms') $Handler; $global:TBmsPatch = $null
$r = Invoke-Cc (New-TBody @{ ccEmail = 'new.person@example.com' })
Check 'kaseyabms: json-patch replaces /Ccs, keeps the existing CC by id, adds an unknown address by email' ($r.out.status -eq 'success' -and $global:TBmsPatch[0].path -eq '/Ccs' -and @($global:TBmsPatch[0].value).Count -eq 2 -and @($global:TBmsPatch[0].value)[0].Id -eq 502 -and @($global:TBmsPatch[0].value)[1].EmailAddress -eq 'new.person@example.com' -and $null -eq @($global:TBmsPatch[0].value)[1].Id) "$($r.out.message) $($r.error)"
Reset-T; Reset-Mock (Get-TSecrets 'kaseyabms') $Handler; $global:TBmsPatch = $null
$r = Invoke-Cc (New-TBody)
Check 'kaseyabms: a known account contact is added by its Id and EntityType' (@($global:TBmsPatch[0].value)[1].Id -eq 503 -and @($global:TBmsPatch[0].value)[1].EntityType -eq 1) ($global:TBmsPatch | ConvertTo-Json -Depth 5 -Compress)
Reset-T; Reset-Mock (Get-TSecrets 'zendesk') $Handler
$r = Invoke-Cc (New-TBody)
$TPut = @(Get-WriteCalls | Where-Object { $_.Body -like '*email_ccs*' })
Check 'zendesk: PUT email_ccs with user_email and action put' ($TPut.Count -eq 1 -and $TPut[0].Body -eq '{"ticket":{"email_ccs":[{"user_email":"alex.wilber@contoso.com","action":"put"}]}}') $TPut[0].Body
Check 'zendesk: the internal note is a private comment, the CC note a public one' ((@(Get-NoteCalls)).Count -eq 2 -and (Read-Body @(Get-NoteCalls)[0]).ticket.comment.public -eq $false -and (Read-Body @(Get-NoteCalls)[1]).ticket.comment.public -eq $true)

# ---- 1b. The public note to the new CC ----
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TBody)
$TNotes = @(Get-Calls 'POST' "$TCW/service/tickets/1001/notes")
Check 'connectwise: the CC note goes on the Discussion tab (public), after the internal note' ($TNotes.Count -eq 2 -and (Read-Body $TNotes[0]).internalAnalysisFlag -eq $true -and (Read-Body $TNotes[1]).detailDescriptionFlag -eq $true -and (Read-Body $TNotes[1]).internalAnalysisFlag -eq $false) (Show-Calls)
Check 'the public note says nothing internal and has no dashes' ($r.out.public_note -notmatch '(?i)internal|technician_run|SECRET' -and (Test-NoDash $r.out)) $r.out.public_note
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TBody @{ notify_cc = 'false' })
Check 'notify_cc false: CC added, internal note only, no public note' ($r.out.status -eq 'success' -and $TS.notes.Count -eq 1 -and $r.out.public_note -eq '') "$($TS.notes -join ' | ')"

# ---- 2. Syncro: not supported, nothing called ----
Reset-T; Reset-Mock (Get-TSecrets 'syncro') $Handler
$r = Invoke-Cc (New-TBody)
Check 'syncro: error with a plain sentence, no calls' ($r.out.status -eq 'error' -and $r.out.message -eq "Syncro's API has no way to add a CC to a ticket, so nothing was changed." -and $Mock.Calls.Count -eq 0 -and $r.error) "$($r.out.message) / $(Show-Calls)"

# ---- 3. Already there: no change, no note ----
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TBody @{ ccEmail = 'Adele.Vance@contoso.com' })
Check 'already on the list (any case): success, not added, no change' ($r.out.status -eq 'success' -and $r.out.added -eq $false -and $r.out.message -like '*already on the CC list for ticket 1001, so nothing changed.') $r.out.message
Check 'already on the list: no writes, no note' (@(Get-WriteCalls).Count -eq 0) (Show-Calls)
Reset-T; Reset-Mock (Get-TSecrets 'zendesk') $Handler
$r = Invoke-Cc (New-TBody @{ ccEmail = 'megan.bowen@contoso.com' })
Check 'the ticket contact: success, no change, no writes' ($r.out.status -eq 'success' -and $r.out.added -eq $false -and $r.out.message -like '*already the contact*' -and @(Get-WriteCalls).Count -eq 0) "$($r.out.message) $(Show-Calls)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler; $TS.flag = $false
$r = Invoke-Cc (New-TBody @{ ccEmail = 'adele.vance@contoso.com' })
Check 'connectwise: on the list but CC turned off: turns it on' ($r.out.status -eq 'success' -and $r.out.added -eq $true -and $TS.flag -eq $true -and $TS.notes[0] -like 'Turned on the email CC list*') "$($r.out.message) $($r.error)"

# ---- 4. Ownership ----
foreach ($TP in @('connectwise', 'zendesk')) {
    Reset-T; Reset-Mock (Get-TSecrets $TP) $Handler; $TS.company = 77
    $r = Invoke-Cc (New-TBody)
    Check "$TP wrong company: rejected, nothing written" ($r.out.status -eq 'rejected' -and @(Get-WriteCalls).Count -eq 0 -and -not $r.error) "$($r.out.status) $($r.out.message) $(Show-Calls)"
    Check "$TP wrong company: the message names nothing about the ticket" ($r.out.message -eq "Ticket 1001 isn't one you can change, so nothing was changed." -and @($r.out.cc_list).Count -eq 0 -and ($r.out.message + ($r.out.actions -join ' ')) -notmatch 'adele|megan|77') ($r.out | ConvertTo-Json -Depth 5 -Compress)
}
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TBody @{ company_psa_id = 'contosoltd' })
Check 'connectwise: company_psa_id may be the company identifier instead of its id' ($r.out.status -eq 'success') "$($r.out.message) $($r.error)"
$r = Invoke-Cc (New-TBody @{ company_psa_id = 'FabrikamInc'; ccEmail = 'new.person@example.com' })
Check 'connectwise: another company identifier is rejected' ($r.out.status -eq 'rejected') $r.out.message
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TBody @{ requester_email = 'alex.wilber@contoso.com'; ccEmail = 'pat.lee@fabrikam.example' })
Check 'requester not the contact or a CC: rejected, nothing written' ($r.out.status -eq 'rejected' -and $r.out.message -like "Only the ticket's contact*" -and @(Get-WriteCalls).Count -eq 0 -and @($r.out.cc_list).Count -eq 0) "$($r.out.message) $(Show-Calls)"
Reset-T; Reset-Mock (Get-TSecrets 'halopsa') $Handler
$r = Invoke-Cc (New-TBody @{ requester_email = 'ADELE.VANCE@contoso.com' })
Check 'requester already on the CC list: allowed' ($r.out.status -eq 'success' -and $r.out.added -eq $true -and $TS.notes[0] -like '*at the request of ADELE.VANCE@contoso.com*') "$($r.out.message) $($r.error)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler; $TS.contactBlank = $true
$r = Invoke-Cc (New-TBody)
Check 'connectwise: contact email read from the contact record when the ticket has none' ($r.out.status -eq 'success' -and @(Get-Calls 'GET' "$TCW/company/contacts/55").Count -ge 1) "$($r.out.message) $($r.error)"
Reset-T; Reset-Mock (Get-TSecrets 'autotask') $Handler
$r = Invoke-Cc (New-TBody @{ requester_email = 'alex.wilber@contoso.com'; ccEmail = 'adele.vance@contoso.com'; allow_company_colleagues = $true })
Check 'allow_company_colleagues: a colleague at the same company may add (here: already copied, no change)' ($r.out.status -eq 'success' -and $r.out.added -eq $false) "$($r.out.message) $($r.error)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TBody @{ requester_email = 'alex.wilber@contoso.com'; ccEmail = 'new.person@example.com'; allow_company_colleagues = 'true' })
Check 'allow_company_colleagues: colleague adds a new CC, the action says why' ($r.out.status -eq 'success' -and $r.out.added -eq $true -and (@($r.out.actions) -join ' ') -like '*allow_company_colleagues*') "$($r.out.message) $($r.error)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler; $TS.company = 77
$r = Invoke-Cc (New-TBody @{ allow_company_colleagues = $true })
Check 'allow_company_colleagues never crosses companies' ($r.out.status -eq 'rejected' -and @(Get-WriteCalls).Count -eq 0) $r.out.message

# ---- 5. Missing requester or company ----
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TBody @{ requester_email = $null })
Check 'no requester_email: error (a setup problem fails the step), no calls at all' ($r.out.status -eq 'error' -and $r.error -and $r.out.message -like "*didn't include requester_email*@UserEmail*" -and $Mock.Calls.Count -eq 0) "$($r.out.message) $(Show-Calls)"
$r = Invoke-Cc (New-TBody @{ company_psa_id = '' })
Check 'blank company_psa_id: error, no calls' ($r.out.status -eq 'error' -and $r.error -and $r.out.message -like '*company_psa_id*' -and $Mock.Calls.Count -eq 0) $r.out.message
# ---- 6. technician_run ----
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TBody @{ requester_email = $null; company_psa_id = $null; technician_run = $true })
Check 'technician_run with neither: allowed, says so in warnings and the note' ($r.out.status -eq 'success' -and $r.out.added -eq $true -and (@($r.out.warnings) -join ' ') -like '*technician_run*' -and $TS.notes[0] -like '*a technician (technician_run)*') "$($r.out.message) $($r.error)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler; $TS.company = 77
$r = Invoke-Cc (New-TBody @{ requester_email = $null; technician_run = $true })
Check 'technician_run still checks the company when it is sent' ($r.out.status -eq 'rejected' -and @(Get-WriteCalls).Count -eq 0) $r.out.message
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TBody @{ technician_run = $true; requester_email = 'pat.lee@fabrikam.example' })
Check 'technician_run with both sent: the ownership rule still applies' ($r.out.status -eq 'rejected' -and @(Get-WriteCalls).Count -eq 0) $r.out.message

# ---- 7. The address ----
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
foreach ($TBad in @('alex.wilber@contoso.com; pat.lee@fabrikam.example', 'alex.wilber', 'alex wilber@contoso.com', 'a@b', '"x"@contoso.com')) {
    $r = Invoke-Cc (New-TBody @{ ccEmail = $TBad })
    Check "invalid address '$TBad': rejected" ($r.out.status -eq 'rejected' -and $r.out.message -like "*isn't a single email address, so nothing was changed.") $r.out.message
}
$r = Invoke-Cc (New-TBody @{ ccEmail = 'mailto:Alex.Wilber@contoso.com' })
Check 'mailto: prefix is dropped' ($r.out.cc_email -eq 'Alex.Wilber@contoso.com' -and $r.out.status -eq 'success') "$($r.out.cc_email) $($r.out.message)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TBody @{ ccEmail = 'pat.lee@fabrikam.example'; allowed_domains = 'contoso.com, @example.com' })
Check 'allowed_domains: another domain is rejected, no calls' ($r.out.status -eq 'rejected' -and $r.out.message -like '*allowed domain (contoso.com, example.com)*' -and $Mock.Calls.Count -eq 0) $r.out.message
$r = Invoke-Cc (New-TBody @{ allowed_domains = 'Contoso.com' })
Check 'allowed_domains: an allowed domain is added' ($r.out.status -eq 'success' -and $r.out.added -eq $true) $r.out.message
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TBody @{ ticketNumber = '1001; DROP' })
Check 'bad ticket number: rejected, no calls' ($r.out.status -eq 'rejected' -and $Mock.Calls.Count -eq 0) $r.out.message
$r = Invoke-Cc (New-TBody @{ ticketNumber = $null })
Check 'no ticket number: error that names the Field ID, and the step fails' ($r.out.status -eq 'error' -and $r.error -and $r.out.message -like 'The request has no ticket number, so nothing was changed.*ticketNumber*') $r.out.message
$r = Invoke-Cc (New-TBody @{ ccEmail = $null })
Check 'no address: error that names the Field ID, and the step fails' ($r.out.status -eq 'error' -and $r.error -and $r.out.message -like 'The request has no email address to add, so nothing was changed.*ccEmail*') $r.out.message
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TBody @{ ticketNumber = '#1001' })
Check 'a leading # on the ticket number is fine' ($r.out.status -eq 'success' -and $r.out.ticket_id -eq '1001') $r.out.message

# ---- 8. Preview ----
foreach ($TP in @('connectwise', 'autotask', 'kaseyabms')) {
    Reset-T; Reset-Mock (Get-TSecrets $TP) $Handler
    $r = Invoke-Cc (New-TBody @{ preview = $true })
    Check "$TP preview: pending_confirmation, nothing written" ($r.out.status -eq 'pending_confirmation' -and $r.out.added -eq $false -and @(Get-WriteCalls).Count -eq 0 -and $TS.notes.Count -eq 0 -and -not $r.error) "$($r.out.status) $($r.out.message) $(Show-Calls)"
    Check "$TP preview: says what would happen" ($r.out.message -like 'Preview: alex.wilber@contoso.com would be added*' -and (@($r.out.cc_list) -join ';') -like '*alex.wilber@contoso.com*' -and $r.out.internal_note -like 'Added alex.wilber*' -and (@($r.out.actions) -join ' ') -like '*Would *') "$($r.out.message) / $(@($r.out.actions) -join ' | ')"
}
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler; $TS.company = 77
$r = Invoke-Cc (New-TBody @{ preview = $true })
Check 'preview on someone else''s ticket is still rejected' ($r.out.status -eq 'rejected') $r.out.status

# ---- 9. Autotask: only a contact of the ticket's company ----
Reset-T; Reset-Mock (Get-TSecrets 'autotask') $Handler
$r = Invoke-Cc (New-TBody @{ ccEmail = 'pat.lee@fabrikam.example' })
Check 'autotask: an address that is not a company contact is refused, nothing written' ($r.out.status -eq 'rejected' -and $r.out.message -like "Autotask can only copy contacts of the ticket's company*pat.lee@fabrikam.example isn't one*" -and @(Get-WriteCalls).Count -eq 0) "$($r.out.message) $(Show-Calls)"

# ---- 10. PSA errors carry the PSA's own text, never secrets ----
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler; $TS.writeFail = 400
$r = Invoke-Cc (New-TBody)
Check 'PSA refuses the write (400): status error with the PSA error text' ($r.out.status -eq 'error' -and $r.out.message -like "Couldn't add alex.wilber@contoso.com to ticket 1001: ConnectWise PATCH /service/tickets/1001 failed (HTTP 400)*you do not have permission to update this field*" -and $r.error) $r.out.message
Check 'PSA error: no secrets or auth headers in the output, no note' ((Test-NoSecret $r.out) -and ($r.out | ConvertTo-Json -Depth 5) -notmatch 'Basic |Authorization' -and $TS.notes.Count -eq 0)
Reset-T; Reset-Mock (Get-TSecrets 'connectwise' @{ 'CW-PrivateKey' = '' }) $Handler
$r = Invoke-Cc (New-TBody)
Check 'missing secret: error naming it, no calls' ($r.out.status -eq 'error' -and $r.out.message -like '*CW-PrivateKey*' -and $Mock.Calls.Count -eq 0) $r.out.message
Reset-T; Reset-Mock (Get-TSecrets 'zendesk') $Handler; $TS.ignoreWrite = $true
$r = Invoke-Cc (New-TBody)
Check 'write accepted but not on the read-back (Zendesk CCs turned off): error, no note' ($r.out.status -eq 'error' -and $r.out.message -like "Zendesk accepted the CC change on ticket 1001, but reading the ticket back shows*" -and $TS.notes.Count -eq 0) $r.out.message
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler; $TS.writeRedirect = $true
$r = Invoke-Cc (New-TBody)
Check 'write answered with a redirect but saved: success with a warning, sent once' ($r.out.status -eq 'success' -and @(Get-Calls 'PATCH' "$TCW/service/tickets/1001").Count -eq 1 -and (@($r.out.warnings) -join ' ') -like '*redirect; reading the ticket back showed it was saved*') "$($r.out.message) $($r.error) / $(@($r.out.warnings) -join ' | ')"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler; $TS.writeRedirect = $true; $TS.ignoreWrite = $true
$r = Invoke-Cc (New-TBody)
Check 'write answered with a redirect and not saved: error, not resent' ($r.out.status -eq 'error' -and @(Get-Calls 'PATCH' "$TCW/service/tickets/1001").Count -eq 1 -and $r.out.message -like '*isn''t on its CC list*') $r.out.message

# ---- 11. The note is non-fatal ----
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler; $TS.noteFail = 403
$r = Invoke-Cc (New-TBody)
Check 'note refused (403): success, CC added, warning with the PSA text' ($r.out.status -eq 'success' -and $r.out.added -eq $true -and (@($r.out.warnings) -join ' ') -like "*was added, but the internal note on ticket 1001 couldn't be added*HTTP 403*Insufficient security level*" -and -not $r.error) "$($r.out.status) / $(@($r.out.warnings) -join ' | ')"
Reset-T; Reset-Mock (Get-TSecrets 'halopsa') $Handler; $TS.notesReadFail = 403
$r = Invoke-Cc (New-TBody)
Check 'note sent but notes unreadable: success with a warning' ($r.out.status -eq 'success' -and (@($r.out.warnings) -join ' ') -like '*couldn''t be read back*') (@($r.out.warnings) -join ' | ')

# ---- 12. Leftover @tokens and the CloudRadial shape ----
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TBody @{ requester_email = '@UserEmail' })
Check 'literal @UserEmail counts as missing: error' ($r.out.status -eq 'error' -and $r.out.message -like '*requester_email*' -and $Mock.Calls.Count -eq 0) $r.out.message
$r = Invoke-Cc (New-TBody @{ company_psa_id = '@CompanyPsaId'; technician_run = '@technician_run' })
Check 'literal @CompanyPsaId counts as missing, and a literal @token is not true' ($r.out.status -eq 'error' -and $r.out.message -like '*company_psa_id*') $r.out.message
$r = Invoke-Cc (New-TBody @{ ccEmail = '@ccEmail' })
Check 'literal @ccEmail counts as missing' ($r.out.status -eq 'error' -and $r.out.message -like '*no email address*') $r.out.message
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$TCr = @{ ticketNumber = '@ticketNumber'; ccEmail = '@ccEmail'; requester_email = 'megan.bowen@contoso.com'; company_psa_id = '42'
    Ticket = @{ TicketId = 2002; Questions = @(@{ Id = 'ticketNumber'; Answer = 'Ticket #1001' }, @{ Id = 'ccEmail'; Answer = 'alex.wilber@contoso.com' }, @{ Id = 'technician_run'; Answer = 'true' }) }
}
$r = Invoke-Cc $TCr
Check 'CloudRadial shape: answers used when the body tokens were left unfilled' ($r.out.status -eq 'success' -and $r.out.ticket_id -eq '1001' -and $r.out.added -eq $true) "$($r.out.message) $($r.error)"
Check 'CloudRadial shape: Ticket.TicketId (the new ticket) is never the target' (@($Mock.Calls | Where-Object { $_.Uri -like '*2002*' }).Count -eq 0) (Show-Calls)
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$TCr = @{ Ticket = @{ TicketId = 2002; Questions = @(@{ Id = 'ticketNumber'; Value = '1001' }, @{ Id = 'ccEmail'; Value = 'alex.wilber@contoso.com' }, @{ Id = 'technician_run'; Answer = 'true' }, @{ Id = 'requester_email'; Answer = 'megan.bowen@contoso.com' }, @{ Id = 'company_psa_id'; Answer = '42' }) } }
$r = Invoke-Cc $TCr
Check 'ownership fields typed into form answers are ignored: error, no calls' ($r.out.status -eq 'error' -and $r.out.message -like '*requester_email and company_psa_id*' -and $Mock.Calls.Count -eq 0) "$($r.out.message) $(Show-Calls)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$TCr = @{ Ticket = @{ TicketId = 2002; Questions = @(@{ Id = 'ticketNumber'; Value = '1001' }, @{ Id = 'ccEmail'; Value = 'alex.wilber@contoso.com' }) }; Company = @{ CompanyName = 'Contoso'; CompanyPsaId = 42 }; User = @{ Email = 'megan.bowen@contoso.com' } }
$r = Invoke-Cc $TCr
Check 'CloudRadial shape: Company.CompanyPsaId and User.Email are read' ($r.out.status -eq 'success') "$($r.out.message) $($r.error)"
# A CloudRadial Action on the form (the shape seen on DV, 2026-10-14): the answers as top-level keys by Field ID, next
# to the portal's own lowercase ticket, company and user objects, and no Questions. Placeholder data.
function New-TPortal { param([hashtable]$Answers = @{}, $UserEmail = 'megan.bowen@contoso.com', $TicketId = 1001)
    $b = [ordered]@{ userPrincipalName = 'megan.bowen@contoso.com'; ccEmail = 'alex.wilber@contoso.com' }
    foreach ($k in $Answers.Keys) { if ($null -eq $Answers[$k]) { $b.Remove($k) } else { $b[$k] = $Answers[$k] } }
    $b['ticket'] = [ordered]@{ id = $TicketId; reference = [string]$TicketId; subject = 'Reset Password'; description = ''; estimatedTime = 0; checklist = @() }
    $b['company'] = [ordered]@{ id = 7; name = 'Contoso'; psaId = 42; psaIdentifier = 'ConnectWise'; tenantId = '00000000-0000-0000-0000-000000000002' }
    $b['user'] = [ordered]@{ id = 'u-1'; name = 'Megan Bowen'; email = $UserEmail; psaId = 501; psaSiteId = 2 }
    return $b
}
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TPortal)
Check 'Action: no ticket-number question -> the form''s own ticket (ticket.id) is the target' ($r.out.status -eq 'success' -and $r.out.ticket_id -eq '1001' -and $r.out.added -eq $true) "$($r.out.message) $($r.error)"
Check 'Action: requester from user.email, in the note' ($TS.notes.Count -ge 1 -and $TS.notes[0] -like '*alex.wilber@contoso.com*megan.bowen@contoso.com*') ($TS.notes -join ' | ')
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TPortal @{ ticketNumber = '#1001' } -TicketId 2002)
Check 'Action: a ticket-number answer wins over the form''s own ticket' ($r.out.status -eq 'success' -and $r.out.ticket_id -eq '1001' -and @($Mock.Calls | Where-Object { $_.Uri -like '*2002*' }).Count -eq 0) "$($r.out.message) $(Show-Calls)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TPortal @{ requester_email = 'megan.bowen@contoso.com'; company_psa_id = '42'; technician_run = 'true' } -UserEmail $null)
Check 'Action: requester, company and technician_run answers are ignored -> error, no calls' ($r.out.status -eq 'error' -and $r.out.message -like '*requester_email*' -and $Mock.Calls.Count -eq 0) "$($r.out.message) $(Show-Calls)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TPortal @{ requester_email = 'attacker@fabrikam.com'; preview = 'true'; notify_cc = 'false' })
Check 'Action: a requester_email answer cannot replace user.email' ($r.out.status -eq 'success' -and ($TS.notes -join ' ') -notlike '*attacker@fabrikam.com*') "$($r.out.message) $($TS.notes -join ' | ')"
Check 'Action: preview and notify_cc answers are ignored (real change, public note sent)' ($r.out.added -eq $true -and $TS.notes.Count -eq 2) "$($r.out.status) notes=$($TS.notes.Count)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TPortal -UserEmail 'adele.vance@contoso.com' -TicketId 1001)
Check 'Action: the ownership check still runs on the form''s own ticket (a CC can add, a stranger cannot)' ($r.out.status -eq 'success') "$($r.out.message)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TPortal -UserEmail 'lee.gu@fabrikam.com')
Check 'Action: someone who is not on the ticket is refused' ($r.out.status -eq 'rejected' -and @($Mock.Calls | Where-Object { $_.Method -ne 'GET' }).Count -eq 0) "$($r.out.message) $(Show-Calls)"
# Field IDs the portal made from the question labels (seen on DV, 2026-10-26: ticketNumber plus emailAddressToAdd).
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TPortal @{ ccEmail = $null; ticketNumber = '1001'; emailAddressToAdd = 'alex.wilber@contoso.com' } -TicketId 2002)
Check 'Action: an email question with another Field ID is used (emailAddressToAdd)' ($r.out.status -eq 'success' -and $r.out.ticket_id -eq '1001' -and $r.out.cc_email -eq 'alex.wilber@contoso.com' -and (Test-CcInList 'alex.wilber@contoso.com' $TS.cc)) "$($r.out.message) $($r.error)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TPortal @{ ccEmail = $null; whichTicket = '#1001'; emailToCopy = 'alex.wilber@contoso.com' } -TicketId 2002)
Check 'Action: a ticket question with another Field ID wins over the form''s own ticket' ($r.out.status -eq 'success' -and $r.out.ticket_id -eq '1001' -and @($Mock.Calls | Where-Object { $_.Uri -like '*2002*' }).Count -eq 0) "$($r.out.message) $(Show-Calls)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TPortal @{ ccEmail = $null; managerEmail = 'alex.wilber@contoso.com'; backupEmail = 'adele.vance@contoso.com' })
Check 'Action: two different email answers -> error naming both Field IDs, no calls, step fails' ($r.out.status -eq 'error' -and $r.error -and $r.out.message -like '*backupEmail, managerEmail*ccEmail*' -and $Mock.Calls.Count -eq 0) "$($r.out.message) $(Show-Calls)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TPortal @{ ccEmail = $null; contactEmail2 = 'MEGAN.BOWEN@contoso.com' })
Check 'Action: the requester''s own address in an email answer is not picked; own ticket, nobody named -> success, no writes' ($r.out.status -eq 'success' -and $r.out.added -eq $false -and $r.out.message -like 'Nobody was named*1001*' -and @(Get-WriteCalls).Count -eq 0 -and -not $r.error) "$($r.out.message) $(Show-Calls)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TPortal @{ ccEmail = $null; userPrincipalName = 'alex.wilber@contoso.com' })
Check 'Action: a userPrincipalName answer is never used as the address to add' ($r.out.status -eq 'success' -and $r.out.added -eq $false -and @(Get-WriteCalls).Count -eq 0) "$($r.out.message) $(Show-Calls)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TPortal @{ ccEmail = $null; ticketNumber = '1001' } -TicketId 2002)
Check 'Action: an existing ticket with no address -> error (the form is set up wrong), step fails' ($r.out.status -eq 'error' -and $r.error -and $r.out.message -like '*no email address*' -and $Mock.Calls.Count -eq 0) "$($r.out.message) $(Show-Calls)"
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc (New-TPortal @{ ccEmail = $null; ticketNumber = '1001'; notesEmail = 'not an address' } -TicketId 2002)
Check 'Action: an email-named answer that isn''t an address is not picked' ($r.out.status -eq 'error' -and $r.out.message -like '*no email address*') $r.out.message
Reset-T; Reset-Mock (Get-TSecrets 'connectwise') $Handler
$r = Invoke-Cc ((New-TBody) | ConvertTo-Json -Compress) -Raw
Check 'a flat JSON string body works' ($r.out.status -eq 'success') "$($r.out.message) $($r.error)"
$r = Invoke-Cc $null -Raw
Check 'no input at all: error, plain message' ($r.out.status -eq 'error' -and (Test-Shape $r.out)) $r.out.message

# ---- 13. psa input overrides PSA-Type ----
Reset-T; Reset-Mock (Get-TSecrets 'zendesk' @{ 'PSA-Type' = 'connectwise' }) $Handler
$r = Invoke-Cc (New-TBody @{ psa = 'zendesk' })
Check 'psa input picks Zendesk over the PSA-Type secret' ($r.out.status -eq 'success' -and @(Get-Calls 'GET' "$TZD/tickets/1001").Count -ge 1) "$($r.out.message) $($r.error)"

Complete-Test
