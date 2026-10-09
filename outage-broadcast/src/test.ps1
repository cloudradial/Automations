# Strict-mode harness for Outage / Incident Broadcast.
# Runs each PowerShell step exactly as it is in outage-broadcast.yml (shared libraries included),
# through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the runner Key Vault,
# Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked. Outputs pass through JSON between steps,
# as the runner does. Placeholder data only (Contoso, Fabrikam, Northwind, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a same-named step
# variable would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File outage-broadcast/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\outage-broadcast.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.type==='powershell-script')o[a.id]={s:a.properties.script,p:a.properties.parameters};}console.log(JSON.stringify(o));"
$TAll = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
$Steps = @{}; foreach ($k in $TAll.Keys) { $Steps[$k] = $TAll[$k].s }
Check 'workflow has parse, identify and broadcast steps' ($Steps.Contains('parse') -and $Steps.Contains('identify') -and $Steps.Contains('broadcast'))
Check 'first step binds trigger = {{ nodes.trigger.output }}; later steps unbound' ((@($TAll['parse'].p) | ConvertTo-Json -Compress) -eq '{"name":"trigger","expression":"{{ nodes.trigger.output }}"}' -and -not @($TAll['identify'].p).Count -and -not @($TAll['broadcast'].p).Count)

$global:NodeIn = $null; $global:NodeOut = $null
function Get-NodeInput { param([string]$Name) return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Invoke-Step {
    param([string]$Id, $In = $null)
    $global:NodeIn = $In; $global:NodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps[$Id])) } catch { $err = [string]$_.Exception.Message }
    $o = $null; if ($null -ne $global:NodeOut) { $o = ($global:NodeOut | ConvertTo-Json -Depth 15 | ConvertFrom-Json) }
    return @{ out = $o; error = $err }
}
function Invoke-Flow {
    param($Body, [switch]$Manual)
    $TIn = $Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    if (-not $Manual) { $TIn = @{ trigger = $TIn } }
    $p = Invoke-Step 'parse' $TIn
    if ($p.error) { return @{ stage = 'parse'; r = $p } }
    $i = Invoke-Step 'identify' $p.out
    if ($i.error) { return @{ stage = 'identify'; r = $i } }
    $b = Invoke-Step 'broadcast' $i.out
    return @{ stage = 'broadcast'; r = $b; identify = $i.out }
}

# ---- placeholder data ----
$TCR = 'https://api.example.cloudradial.test'
$TCW = 'https://cw.example.com/v4_6_release/apis/3.0'; $TAT = 'https://webservices.autotask.example/atservicesrest/v1.0'; $TZD = 'https://example.zendesk.com/api/v2'
$TPM = 'https://api.postmarkapp.com/email'
$TCrSecrets = @{ 'CloudRadial-BaseUrl' = $TCR; 'CloudRadial-PublicKey' = 'pub'; 'CloudRadial-PrivateKey' = 'priv' }
$TPsa = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = $TCW; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
    none        = @{}
}
$TPostmark = @{ 'Postmark-ServerToken' = 'pm-token'; 'Postmark-FromEmail' = 'support@example-msp.test' }
function Get-TSecrets { param([string]$P, [switch]$Postmark) $s = @{}; foreach ($h in @($TCrSecrets, $TPsa[$P])) { foreach ($k in $h.Keys) { $s[$k] = $h[$k] } }; if ($Postmark) { foreach ($k in $TPostmark.Keys) { $s[$k] = $TPostmark[$k] } }; return $s }
$TSvc = 'Contoso Hosted PBX'
$TMsg = 'Phones are not ringing for incoming calls. We are working with the provider and will update you within the hour.'
$TBanner = "$($TSvc): $TMsg"

function Reset-TScenario {
    $global:TS = @{
        tokens = @(); partnerToken = $false
        articles = @([pscustomobject]@{ articleId = 500; companyId = 2; subject = 'Service status: Contoso Hosted PBX'; isFrontPage = $true; datePublished = '2026-10-01T10:00:00Z' })
        services = @(
            [pscustomobject]@{ serviceId = 11; companyId = 1; name = 'Contoso Hosted PBX Agent' }
            [pscustomobject]@{ serviceId = 12; companyId = 2; name = 'Contoso Hosted PBX Agent' }
            [pscustomobject]@{ serviceId = 13; companyId = 3; name = 'Contoso Hosted PBX Agent' })
        installed = @(11, 12); crForbidden = $false; noteForbidden = $false
        notes = (New-Object System.Collections.ArrayList)
    }
}
Reset-TScenario
$TCompanies = @(
    [pscustomobject]@{ companyId = 1; name = 'Contoso'; psaKey = 101 }
    [pscustomobject]@{ companyId = 2; name = 'Fabrikam'; psaKey = 102 }
    [pscustomobject]@{ companyId = 3; name = 'Northwind'; psaKey = 0 })

$Handler = {
    param($c, $n)
    $k = "$($c.Method) $($c.Uri)"
    $S = $global:TS
    $u = [uri]::UnescapeDataString($c.Uri)
    switch -Wildcard -CaseSensitive ($k) {
        "GET $TCR/v2/odata/company[?]*" { if ($S.crForbidden) { New-HttpError 403 '{"message":"The API key does not have access to companies."}' }; return [pscustomobject]@{ value = $TCompanies } }
        "GET $TCR/v2/odata/companygroup[?]*" { if ($u -like "*group eq 'Hosted Voice'*") { return [pscustomobject]@{ value = @([pscustomobject]@{ companyGroupId = 7; group = 'Hosted Voice'; isDeleted = $false }) } }; return [pscustomobject]@{ value = @() } }
        "GET $TCR/v2/odata/companygroupcompany[?]*" { return [pscustomobject]@{ value = @([pscustomobject]@{ companyGroupId = 7; companyId = 3; isDeleted = $false }, [pscustomobject]@{ companyGroupId = 7; companyId = 1; isDeleted = $true }) } }
        "GET $TCR/v2/odata/token[?]*" { $rows = @($S.tokens); if ($S.partnerToken) { $rows += [pscustomobject]@{ name = 'ServiceStatus'; companyId = 0; value = '' } }; return [pscustomobject]@{ value = $rows } }
        "GET $TCR/v2/odata/article[?]*" { return [pscustomobject]@{ value = @($S.articles) } }
        "GET $TCR/v2/odata/service[?]*" { if ($u -like "*'contoso hosted pbx'*") { return [pscustomobject]@{ value = @($S.services) } }; return [pscustomobject]@{ value = @() } }
        "GET $TCR/v2/odata/serviceinstall[?]*" { foreach ($sid in $S.installed) { if ($u -like "*serviceId eq $sid&*") { return [pscustomobject]@{ value = @([pscustomobject]@{ endpointId = 900 + $sid; serviceId = $sid; endpoint = [pscustomobject]@{ companyId = 0 } }) } } }; return [pscustomobject]@{ value = @() } }
        "POST $TCR/v2/token" { return [pscustomobject]@{ success = $true } }
        "POST $TCR/v2/article" { return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ articleId = 777 } } }
        "PUT $TCR/v2/article/*" { return [pscustomobject]@{ success = $true } }
        "GET $TCW/service/tickets/4242/notes[?]*" { return , @($S.notes | ForEach-Object { [pscustomobject]@{ id = 1; text = $_; internalAnalysisFlag = $true } }) }
        "POST $TCW/service/tickets/4242/notes" { if ($S.noteForbidden) { New-HttpError 403 '{"message":"Member does not have access to add notes."}' }; $null = $S.notes.Add((Read-Body $c).text); return [pscustomobject]@{ id = 1 } }
        "GET $TCW/company/companies/101" { return [pscustomobject]@{ id = 101; defaultContact = [pscustomobject]@{ id = 55 } } }
        "GET $TCW/company/companies/102" { return [pscustomobject]@{ id = 102; defaultContact = $null } }
        "GET $TCW/company/contacts/55" { return [pscustomobject]@{ id = 55; firstName = 'Megan'; lastName = 'Bowen'; communicationItems = @([pscustomobject]@{ communicationType = 'Phone'; value = '555 0100'; defaultFlag = $true }, [pscustomobject]@{ communicationType = 'Email'; value = 'megan.bowen@contoso.com'; defaultFlag = $true }) } }
        "GET $TAT/Contacts/query[?]*" { if ($u -like '*"value":101*') { return [pscustomobject]@{ items = @([pscustomobject]@{ firstName = 'Megan'; lastName = 'Bowen'; emailAddress = 'megan.bowen@contoso.com' }) } }; return [pscustomobject]@{ items = @([pscustomobject]@{ firstName = 'Alex'; lastName = 'Wilber'; emailAddress = 'alex.wilber@fabrikam.com' }) } }
        "GET $TAT/TicketNotes/entityInformation/fields" { return [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                    [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) } }
        "GET $TAT/TicketNotes/query[?]*" { return [pscustomobject]@{ items = @($S.notes | ForEach-Object { [pscustomobject]@{ id = 3; description = $_; publish = 2 } }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
        "POST $TAT/Tickets/4242/Notes" { $null = $S.notes.Add((Read-Body $c).description); return [pscustomobject]@{ itemId = 3 } }
        "GET $TZD/tickets/4242/comments[?]*" { return [pscustomobject]@{ comments = @($S.notes | ForEach-Object { [pscustomobject]@{ id = 5; body = $_; public = $false } }); next_page = $null } }
        "PUT $TZD/tickets/4242" { $null = $S.notes.Add((Read-Body $c).ticket.comment.body); return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 4242 } } }
        "POST $TPM" { return [pscustomobject]@{ ErrorCode = 0; Message = 'OK'; MessageID = 'm1' } }
    }
    throw "Unexpected call in test: $k"
}
function Get-TWrites { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' }) }
function Get-TCrWrites { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and $_.Uri -like "$TCR/*" }) }
$TBody = @{ affectedService = $TSvc; message = $TMsg; triggerSource = 'serviceai-ai' }
function New-TBody { param([hashtable]$Over = @{}) $b = @{}; foreach ($k in $TBody.Keys) { $b[$k] = $TBody[$k] }; foreach ($k in $Over.Keys) { $b[$k] = $Over[$k] }; return $b }

# ---- 1. Preview (confirm missing): service installs pick the companies, nothing is written ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ problemTicketId = '4242'; requestedBy = 'jlee@example-msp.test' })
$o = $f.r.out
Check 'preview: reached the broadcast step without error' ($f.stage -eq 'broadcast' -and -not $f.r.error) "$($f.stage) $($f.r.error)"
Check 'preview: status pending_confirmation' ($o.status -eq 'pending_confirmation') $o.status
Check 'preview: no write of any kind (CloudRadial, PSA or email)' (@(Get-TWrites).Count -eq 0) (Show-Calls)
Check 'preview: companies with the service installed (Contoso, Fabrikam); Northwind has no install' ((@($o.companies | ForEach-Object { $_.name }) -join ',') -eq 'Contoso,Fabrikam') ($o.companies | ConvertTo-Json -Compress)
Check 'preview: plan lists banner, new article for Contoso, article update for Fabrikam, partner token' ((@($o.plan.planned) -join '|') -like '*partner-level @ServiceStatus*' -and (@($o.plan.planned) -join '|') -like '*Contoso: publish a Service Status article*' -and (@($o.plan.planned) -join '|') -like '*Fabrikam: update the pinned Service Status article*' -and (@($o.plan.planned) -join '|') -like '*Contoso: set the @ServiceStatus banner*') ($o.plan.planned -join ' | ')
Check 'preview: chatReply names the companies and asks for a yes' ($o.chatReply -like '*Contoso, Fabrikam*' -and $o.chatReply -like '*Say yes*') $o.chatReply
Check 'preview: requester recorded in internal_note' ($o.internal_note -like '*Run by: jlee@example-msp.test*') $o.internal_note
Check 'preview: received_keys logged for mapping the requester field' (@($o.received_keys) -contains 'requestedBy')
Check 'preview: no em dash anywhere in the output' (-not (($o | ConvertTo-Json -Depth 12).Contains([string][char]0x2014)))

# ---- 2. Confirm with ConnectWise: writes happen, internal note on the problem ticket ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ problemTicketId = '4242'; confirm = $true })
$o = $f.r.out
Check 'cw confirm: status success' ($o.status -eq 'success' -and -not $f.r.error) "$($o.status) $($f.r.error) $($o.message)"
$tok = @(Get-Calls 'POST' "$TCR/v2/token")
Check 'cw confirm: partner token plus one banner per company' ($tok.Count -eq 3 -and (Read-Body $tok[0]).companyId -eq 0 -and (Read-Body $tok[0]).value -eq '' -and (Read-Body $tok[1]).companyId -eq 1 -and (Read-Body $tok[1]).value -eq $TBanner -and (Read-Body $tok[1]).token -eq 'ServiceStatus') (Show-Calls)
$post = @(Get-Calls 'POST' "$TCR/v2/article"); $put = @(Get-Calls 'PUT' "$TCR/v2/article/500")
Check 'cw confirm: Contoso article created pinned in Service Status, Fabrikam article 500 updated' ($post.Count -eq 1 -and (Read-Body $post[0]).companyId -eq 1 -and (Read-Body $post[0]).category -eq 'Service Status' -and (Read-Body $post[0]).isFrontPage -eq $true -and $put.Count -eq 1 -and (Read-Body $put[0]).companyId -eq 2) (Show-Calls)
Check 'cw confirm: article body never names another client' ((Read-Body $post[0]).body -notlike '*Fabrikam*' -and (Read-Body $put[0]).body -notlike '*Contoso,*')
$note = @(Get-Calls 'POST' "$TCW/service/tickets/4242/notes")
Check 'cw confirm: one internal note on problem ticket 4242' ($note.Count -eq 1 -and (Read-Body $note[0]).internalAnalysisFlag -eq $true -and (Read-Body $note[0]).text -like '*Affected companies (2)*' -and $o.note_written -eq $true) (Show-Calls)
Check 'cw confirm: no email without emailContacts' (@(Get-Calls 'POST' $TPM).Count -eq 0)
Check 'cw confirm: actions recorded' (@($o.actions).Count -ge 6) (@($o.actions).Count)
Check 'cw confirm: the note ends with its retry marker' ($o.note_marker -like 'outage-broadcast broadcast *' -and (Read-Body $note[0]).text.TrimEnd().EndsWith("[$($o.note_marker)]")) "$($o.note_marker) :: $((Read-Body $note[0]).text)"

# ---- 2b. Rerun of the same confirmed broadcast (ServiceAI Retry): the problem ticket note is not written twice ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler
$f = Invoke-Flow (New-TBody @{ problemTicketId = '4242'; confirm = $true })
$o2 = $f.r.out
Check 'rerun: same marker, no second note on the problem ticket' ($o2.note_marker -eq $o.note_marker -and @(Get-Calls 'POST' "$TCW/service/tickets/4242/notes").Count -eq 0 -and $global:TS.notes.Count -eq 1 -and $o2.note_written -eq $false) (Show-Calls)
Check 'rerun: the action says the note was already there' ((@($o2.actions | ForEach-Object { $_.result }) -join ' ') -like '*already on the ticket*') ($o2.actions | ConvertTo-Json -Compress)
Reset-Mock (Get-TSecrets 'connectwise') $Handler
$f = Invoke-Flow (New-TBody @{ problemTicketId = '4242'; confirm = $true; message = 'Calls are back for most users. Next update at 3 PM.' })
Check 'rerun: a new client message is a new note' ($f.r.out.note_written -eq $true -and $global:TS.notes.Count -eq 2 -and $f.r.out.note_marker -ne $o.note_marker) (Show-Calls)

# ---- 3. Confirm with Autotask, emailContacts and Postmark: one email per company to its own contact ----
Reset-Mock (Get-TSecrets 'autotask' -Postmark) $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ problemTicketId = '4242'; confirm = 'true'; emailContacts = 'yes' })
$o = $f.r.out
$mails = @(Get-Calls 'POST' $TPM)
Check 'at email: status success' ($o.status -eq 'success') "$($o.status) $($o.message) $($f.r.error)"
Check 'at email: two emails, each to one company contact only' ($mails.Count -eq 2 -and (Read-Body $mails[0]).To -eq 'megan.bowen@contoso.com' -and (Read-Body $mails[1]).To -eq 'alex.wilber@fabrikam.com') (Show-Calls)
Check 'at email: Postmark token header and From secret used' ($mails[0].Headers['X-Postmark-Server-Token'] -eq 'pm-token' -and (Read-Body $mails[0]).From -eq 'support@example-msp.test')
Check 'at email: email names no other client' ((Read-Body $mails[0]).TextBody -notlike '*Fabrikam*' -and (Read-Body $mails[1]).TextBody -notlike '*Contoso,*')
$atNote = @(Get-Calls 'POST' "$TAT/Tickets/4242/Notes")
Check 'at email: Autotask internal note (publish Internal Only) lists the recipients' ($atNote.Count -eq 1 -and (Read-Body $atNote[0]).publish -eq 2 -and (Read-Body $atNote[0]).description -like '*megan.bowen@contoso.com*') (Show-Calls)
Reset-Mock (Get-TSecrets 'autotask' -Postmark) $Handler
$f = Invoke-Flow (New-TBody @{ problemTicketId = '4242'; confirm = 'true'; emailContacts = 'yes' })
Check 'at rerun: no second Autotask note' (@(Get-Calls 'POST' "$TAT/Tickets/4242/Notes").Count -eq 0 -and $global:TS.notes.Count -eq 1) (Show-Calls)

# ---- 4. emailContacts on but no Postmark secrets: other writes run, nobody is emailed, a warning says why ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ problemTicketId = '4242'; confirm = $true; emailContacts = $true })
$o = $f.r.out
Check 'no postmark: success, banners still set' ($o.status -eq 'success' -and @(Get-Calls 'POST' "$TCR/v2/token").Count -eq 3) "$($o.status) $($o.message)"
Check 'no postmark: no email sent, warning names the secrets' (@(Get-Calls 'POST' $TPM).Count -eq 0 -and (@($o.warnings) -join ' ') -like '*Postmark-ServerToken*') (@($o.warnings) -join ' ')
Check 'no postmark: Fabrikam has no CW default contact, Contoso contact listed as not emailed' ($o.internal_note -like '*not emailed, Postmark is not set up*megan.bowen@contoso.com*' -and $o.internal_note -like '*Fabrikam*no email (no primary contact*') $o.internal_note

# ---- 5. Retry of an already-posted notice: nothing changes and nobody is emailed twice ----
Reset-Mock (Get-TSecrets 'connectwise' -Postmark) $Handler; Reset-TScenario
$global:TS.partnerToken = $true
$global:TS.tokens = @([pscustomobject]@{ name = 'ServiceStatus'; companyId = 1; value = $TBanner }, [pscustomobject]@{ name = 'ServiceStatus'; companyId = 2; value = $TBanner })
$global:TS.articles = @()
$f = Invoke-Flow (New-TBody @{ confirm = $true; emailContacts = $true; postArticle = $false })
$o = $f.r.out
Check 'retry: success with nothing to change' ($o.status -eq 'success' -and $o.plan.status -eq 'empty') "$($o.status) $($o.plan.status)"
Check 'retry: no write and no email' (@(Get-TWrites).Count -eq 0) (Show-Calls)

# ---- 6. Resolved mode: clears only banners that show this service, marks the article resolved ----
Reset-Mock (Get-TSecrets 'zendesk') $Handler; Reset-TScenario
$global:TS.partnerToken = $true
$global:TS.tokens = @([pscustomobject]@{ name = 'ServiceStatus'; companyId = 1; value = $TBanner }, [pscustomobject]@{ name = 'ServiceStatus'; companyId = 3; value = 'Northwind VPN: maintenance tonight.' })
$f = Invoke-Flow (New-TBody @{ mode = 'resolved'; message = ''; problemTicketId = '4242'; confirm = $true })
$o = $f.r.out
Check 'resolved: status success' ($o.status -eq 'success') "$($o.status) $($o.message) $($f.r.error)"
Check 'resolved: targets Contoso (banner) and Fabrikam (open article), not Northwind' ((@($o.companies | ForEach-Object { $_.name }) -join ',') -eq 'Contoso,Fabrikam') ($o.companies | ConvertTo-Json -Compress)
$tok = @(Get-Calls 'POST' "$TCR/v2/token")
Check 'resolved: Contoso banner cleared (empty value), Northwind untouched' ($tok.Count -eq 1 -and (Read-Body $tok[0]).companyId -eq 1 -and (Read-Body $tok[0]).value -eq '') (Show-Calls)
$put = @(Get-Calls 'PUT' "$TCR/v2/article/500")
Check 'resolved: Fabrikam article marked resolved and unpinned' ($put.Count -eq 1 -and (Read-Body $put[0]).subject -eq 'Service status: Contoso Hosted PBX (resolved)' -and (Read-Body $put[0]).isFrontPage -eq $false -and (Read-Body $put[0]).body -like '*has been resolved*') (Show-Calls)
$zd = @(Get-Calls 'PUT' "$TZD/tickets/4242")
Check 'resolved: Zendesk private comment on the problem ticket' ($zd.Count -eq 1 -and (Read-Body $zd[0]).ticket.comment.public -eq $false -and (Read-Body $zd[0]).ticket.comment.body -like '*Outage broadcast (resolved)*') (Show-Calls)
Check 'resolved: no new article created' (@(Get-Calls 'POST' "$TCR/v2/article").Count -eq 0)
Reset-Mock (Get-TSecrets 'zendesk') $Handler
$f = Invoke-Flow (New-TBody @{ mode = 'resolved'; message = ''; problemTicketId = '4242'; confirm = $true })
Check 'resolved rerun: no second Zendesk comment' (@(Get-Calls 'PUT' "$TZD/tickets/4242").Count -eq 0 -and $global:TS.notes.Count -eq 1) (Show-Calls)

# ---- 7. Company group and named companies ----
Reset-Mock (Get-TSecrets 'none') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ companyGroup = 'Hosted Voice' })
Check 'group: only active members (Northwind), preview' ((@($f.r.out.companies | ForEach-Object { $_.name }) -join ',') -eq 'Northwind' -and $f.r.out.status -eq 'pending_confirmation') ($f.r.out | ConvertTo-Json -Depth 4 -Compress)
Reset-Mock (Get-TSecrets 'none') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ companies = @('Fabrikam', '1', 'Tailspin') })
Check 'named: Fabrikam and company 1 picked, unknown name warned' ((@($f.r.out.companies | ForEach-Object { $_.name }) -join ',') -eq 'Fabrikam,Contoso' -and (@($f.r.out.warnings) -join ' ') -like "*'Tailspin'*") ($f.r.out | ConvertTo-Json -Depth 4 -Compress)
Reset-Mock (Get-TSecrets 'none') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ companyGroup = 'No Such Group' })
Check 'group: unknown group is incomplete, nothing written' ($f.r.out.status -eq 'incomplete' -and $f.r.out.message -like '*No Such Group*' -and @(Get-TWrites).Count -eq 0) $f.r.out.message

# ---- 8. Empty result: no company has the service ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ affectedService = 'Tailspin Fax'; confirm = $true; problemTicketId = '4242' })
Check 'empty: success, plain message, nothing written' ($f.r.out.status -eq 'success' -and $f.r.out.message -like '*nothing to post*' -and @(Get-TWrites).Count -eq 0) "$($f.r.out.status) $($f.r.out.message)"

# ---- 9. Over the company limit ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ maxCompanies = '1'; confirm = $true })
Check 'limit: incomplete, says how to go ahead, nothing written' ($f.r.out.status -eq 'incomplete' -and $f.r.out.message -like '*maxCompanies set to 2*' -and @(Get-TWrites).Count -eq 0) $f.r.out.message

# ---- 10. Missing permission (403) ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$global:TS.crForbidden = $true
$f = Invoke-Flow (New-TBody @{ confirm = $true })
Check '403 CloudRadial: identify step fails with a plain message, nothing written' ($f.stage -eq 'identify' -and $f.r.error -like '*HTTP 403*does not have access to companies*' -and @(Get-TWrites).Count -eq 0) "$($f.stage) $($f.r.error)"
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$global:TS.noteForbidden = $true
$f = Invoke-Flow (New-TBody @{ confirm = $true; problemTicketId = '4242' })
Check '403 PSA note: broadcast still succeeds, warning names the failure' ($f.r.out.status -eq 'success' -and $f.r.out.note_written -eq $false -and (@($f.r.out.warnings) -join ' ') -like '*ticket 4242 failed*HTTP 403*') (@($f.r.out.warnings) -join ' ')

# ---- 11. Input checks ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow @{ affectedService = '@affectedService'; message = '{{message}}' }
Check 'input: literal @token and {{placeholder}} count as missing' ($f.r.out.status -eq 'incomplete' -and $f.r.out.message -like '*affectedService is missing*' -and $Mock.Calls.Count -eq 0) $f.r.out.message
$f = Invoke-Flow @{ affectedService = $TSvc }
Check 'input: broadcast without a message is incomplete' ($f.r.out.status -eq 'incomplete' -and $f.r.out.message -like '*message is missing*') $f.r.out.message
$f = Invoke-Flow @{ affectedService = $TSvc; message = 'Down <script>alert(1)</script>' }
Check 'input: script in the message is refused' ($f.r.out.status -eq 'incomplete' -and $f.r.out.message -like '*script*') $f.r.out.message
$f = Invoke-Flow @{ affectedService = $TSvc; message = 'x'; mode = 'explode' }
Check 'input: unknown mode is refused' ($f.r.out.status -eq 'incomplete' -and $f.r.out.message -like "*mode 'explode'*") $f.r.out.message
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ approvedToBroadcast = 'true' }) -Manual
Check 'input: manual unwrapped input works; approvedToBroadcast counts as confirm' ($f.r.out.status -eq 'success' -and $f.r.out.confirm -eq $true -and @(Get-Calls 'POST' "$TCR/v2/token").Count -eq 3) "$($f.r.out.status) $($f.r.out.message)"

Complete-Test
