# Strict-mode harness for Phishing Report Triage.
# Runs each PowerShell step exactly as it is in phishing-report-triage.yml (shared libraries included),
# through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the runner Key Vault,
# Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked. The AI Prompt step is simulated by
# handing the ticket step a classification string.
# Placeholder data only (Contoso, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a step variable such as $g or $msg
# would hide a same-named test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File automationai/phishing-report-triage/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in automationai/_shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

# ---- the steps, straight from the built workflow ----
$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\phishing-report-triage.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.type==='powershell-script')o[a.id]=a.properties.script;if(a.type==='ai-prompt')o[a.id+'.prompt']=a.properties.promptTemplate;}console.log(JSON.stringify(o));"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow has parse, enrich and ticket steps' ($Steps.Contains('parse') -and $Steps.Contains('enrich') -and $Steps.Contains('ticket'))
Check 'classify prompt reads the enrichment output' ($Steps['classify.prompt'] -like '*{{ nodes.enrich.output.enrichment_json }}*')

# ---- runner mocks ----
$global:NodeIn = $null; $global:NodeParams = @{}; $global:NodeOut = $null
function Get-NodeInput { param([string]$Name) if ($Name) { if ($global:NodeParams.Contains($Name)) { return $global:NodeParams[$Name] }; return $null }; return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
# Runs one step; returns @{ out; error }. Outputs pass through JSON, as the runner does between steps.
function Invoke-Step {
    param([string]$Id, $In = $null, [hashtable]$Params = @{})
    $global:NodeIn = $In; $global:NodeParams = $Params; $global:NodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps[$Id])) } catch { $err = [string]$_.Exception.Message }
    $o = $null; if ($null -ne $global:NodeOut) { $o = ($global:NodeOut | ConvertTo-Json -Depth 12 | ConvertFrom-Json) }
    return @{ out = $o; error = $err }
}
# parse -> enrich -> (AI text) -> ticket, the way the bindings wire them.
function Invoke-Flow {
    param($Body, [string]$Ai)
    $p = Invoke-Step 'parse' ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    if ($p.error) { return @{ stage = 'parse'; r = $p } }
    $e = Invoke-Step 'enrich' $p.out
    if ($e.error) { return @{ stage = 'enrich'; r = $e } }
    $t = Invoke-Step 'ticket' $null @{ enrichment = $e.out.enrichment_json; request = $e.out.request_json; rules = $e.out.rules_json; warnings_json = $e.out.warnings_json; classification = $Ai }
    return @{ stage = 'ticket'; r = $t; enrich = $e.out }
}

# ---- placeholder data ----
$TenantId = '11111111-2222-3333-4444-555555555555'
$Graph = @{ 'M365-TenantId' = $TenantId; 'M365-ClientId' = 'client-id'; 'M365-ClientSecret' = 'client-secret' }
$Psa = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://cw.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
}
function Get-Secrets { param([string]$P) $s = @{}; foreach ($k in $Graph.Keys) { $s[$k] = $Graph[$k] }; foreach ($k in $Psa[$P].Keys) { $s[$k] = $Psa[$P][$k] }; return $s }
$TCW = 'https://cw.example.com/v4_6_release/apis/3.0'; $TAT = 'https://webservices.autotask.example/atservicesrest/v1.0'; $TZD = 'https://example.zendesk.com/api/v2'
$TGraph = 'https://graph.microsoft.com/v1.0'

$authBad = 'spf=fail (sender IP is 203.0.113.5) smtp.mailfrom=c0ntoso.com; dkim=none (message not signed) header.d=none;dmarc=fail action=quarantine header.from=c0ntoso.com;compauth=fail reason=000'
$authGood = 'spf=pass (sender IP is 198.51.100.7) smtp.mailfrom=fabrikam.example; dkim=pass (signature was verified) header.d=fabrikam.example;dmarc=pass action=none header.from=fabrikam.example;compauth=pass reason=100'
$TMsg = @{
    bad  = [pscustomobject]@{
        id = 'm1'; internetMessageId = '<phish-0001@c0ntoso.com>'; subject = 'Your password expires today'; receivedDateTime = '2026-10-06T14:05:00Z'; hasAttachments = $true; parentFolderId = 'inbox'
        from = [pscustomobject]@{ emailAddress = [pscustomobject]@{ name = 'Microsoft 365 Security'; address = 'alerts@c0ntoso.com' } }
        sender = [pscustomobject]@{ emailAddress = [pscustomobject]@{ name = 'Microsoft 365 Security'; address = 'alerts@c0ntoso.com' } }
        replyTo = @([pscustomobject]@{ emailAddress = [pscustomobject]@{ name = ''; address = 'collect@mailbox.example' } })
        internetMessageHeaders = @([pscustomobject]@{ name = 'Authentication-Results'; value = $authBad }, [pscustomobject]@{ name = 'Return-Path'; value = '<bounce@c0ntoso.com>' })
        body = [pscustomobject]@{ contentType = 'html'; content = '<p>Your password expires today.</p><a href="https://nam02.safelinks.protection.outlook.com/?url=https%3A%2F%2Flogin-contoso.example%2Fverify%3Fu%3D1&amp;data=05&amp;reserved=0">https://login.microsoftonline.com</a><p>Or visit http://203.0.113.9/keep</p>' }
    }
    good = [pscustomobject]@{
        id = 'm2'; internetMessageId = '<news-77@fabrikam.example>'; subject = 'October newsletter'; receivedDateTime = '2026-10-05T09:00:00Z'; hasAttachments = $false; parentFolderId = 'inbox'
        from = [pscustomobject]@{ emailAddress = [pscustomobject]@{ name = 'Fabrikam News'; address = 'news@fabrikam.example' } }
        sender = [pscustomobject]@{ emailAddress = [pscustomobject]@{ name = 'Fabrikam News'; address = 'news@fabrikam.example' } }
        replyTo = @()
        internetMessageHeaders = @([pscustomobject]@{ name = 'Authentication-Results'; value = $authGood })
        body = [pscustomobject]@{ contentType = 'html'; content = '<p>Hello.</p><a href="https://www.fabrikam.example/october">Read more</a>' }
    }
}
$TScenario = @{ message = 'bad'; graph403 = $false; empty = $false; atCompany = 42; findFail = $false }
$TState = @{ notes = @{}; tickets = (New-Object System.Collections.ArrayList) }
function Add-TNote { param([string]$TicketId, $Note) if (-not $TState.notes.Contains($TicketId)) { $TState.notes[$TicketId] = New-Object System.Collections.ArrayList }; $null = $TState.notes[$TicketId].Add($Note) }
function Get-TNotes { param([string]$TicketId) if ($TState.notes.Contains($TicketId)) { return @($TState.notes[$TicketId]) }; return @() }
function Get-TNoteCount { $n = 0; foreach ($k in $TState.notes.Keys) { $n += $TState.notes[$k].Count }; return $n }
# A new scenario: fresh secrets, calls, tickets and notes. A rerun of the same scenario clears only the calls.
function Reset-T { param([string]$P) Reset-Mock (Get-Secrets $P) $Handler; $TState.notes = @{}; $TState.tickets.Clear() }

$Handler = {
    param($c, $n)
    $k = "$($c.Method) $($c.Uri)"
    $m = $TMsg[$TScenario.message]
    switch -Wildcard -CaseSensitive ($k) {
        'POST https://login.microsoftonline.com/*' { return [pscustomobject]@{ access_token = 'graph-token'; expires_in = 3600 } }
        "GET $TGraph/users/megan.bowen%40contoso.com*" { return [pscustomobject]@{ id = 'u1'; userPrincipalName = 'megan.bowen@contoso.com'; displayName = 'Megan Bowen'; mail = 'megan.bowen@contoso.com' } }
        "GET $TGraph/users/nobody%40contoso.com*" { New-HttpError 404 '{"error":{"message":"Resource not found"}}' }
        "GET $TGraph/users/u1/messages/*/attachments*" { return [pscustomobject]@{ value = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.fileAttachment'; name = 'Invoice.pdf.html'; contentType = 'text/html'; size = 2048; isInline = $false }) } }
        "GET $TGraph/users/u1/messages/*" { return $m }
        "GET $TGraph/users/u1/messages?*" {
            if ($TScenario.graph403) { New-HttpError 403 '{"error":{"code":"ErrorAccessDenied","message":"Access is denied. Check credentials and try again."}}' }
            if ($TScenario.empty) { return [pscustomobject]@{ value = @() } }
            return [pscustomobject]@{ value = @($m) }
        }
        "GET $TCW/service/priorities*" { return @([pscustomobject]@{ id = 1; name = 'Priority 1 - Emergency Response' }, [pscustomobject]@{ id = 2; name = 'Priority 2 - Quick Response' }, [pscustomobject]@{ id = 3; name = 'Priority 3 - Normal Response' }, [pscustomobject]@{ id = 4; name = 'Priority 4 - Schedule Maintenance' }) }
        "GET $TCW/company/companies*" { return @([pscustomobject]@{ id = 43; name = 'Contoso Ltd' }, [pscustomobject]@{ id = 42; name = 'Contoso' }) }
        "GET $TCW/service/tickets/777/notes*" { return @([pscustomobject]@{ id = 1; text = "Please check this.`n---------- Forwarded message ----------`nFrom: Microsoft 365 Security <alerts@c0ntoso.com>`nSubject: Your password expires today`nMessage-ID: <phish-0001@c0ntoso.com>" }) }
        "GET $TCW/service/tickets/777" { return [pscustomobject]@{ id = 777; summary = 'FW: Your password expires today'; company = [pscustomobject]@{ id = 42 }; owner = $null; status = [pscustomobject]@{ name = 'New' } } }
        # Tickets and notes the workflow writes are kept in $TState, so a rerun sees what the first run wrote.
        "POST $TCW/service/tickets" {
            $null = $TState.tickets.Add([pscustomobject]@{ id = 501; summary = (Read-Body $c).summary; company = [pscustomobject]@{ id = 42 }; closedFlag = $false; dateEntered = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); status = [pscustomobject]@{ name = 'New' } })
            return [pscustomobject]@{ id = 501 }
        }
        "GET $TCW/service/tickets[?]*" { if ($TScenario.findFail) { New-HttpError 403 '{"message":"Not allowed"}' }; if ($c.Uri -like '*page=1') { return @($TState.tickets) }; return @() }
        "POST $TCW/service/tickets/*/notes" { $b = Read-Body $c; Add-TNote ($c.Uri -replace '^.*/tickets/(\d+)/notes$', '$1') ([pscustomobject]@{ id = 9001; text = $b.text; internalAnalysisFlag = $b.internalAnalysisFlag; detailDescriptionFlag = $b.detailDescriptionFlag }); return [pscustomobject]@{ id = 9001 } }
        "GET $TCW/service/tickets/*/notes*" { if ($c.Uri -like '*page=1') { return @(Get-TNotes ($c.Uri -replace '^.*/tickets/(\d+)/notes.*$', '$1')) }; return @() }
        "GET $TAT/TicketNotes/query*" { return [pscustomobject]@{ items = @(Get-TNotes '12345'); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
        "GET $TAT/TicketNotes/entityInformation/fields" { return [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                    [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '13'; label = 'System Workflow Note'; isActive = $true }, [pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) } }
        "GET $TAT/Tickets/12345" { return [pscustomobject]@{ item = [pscustomobject]@{ id = 12345; title = 'Suspicious email'; description = 'Reported by Megan'; companyID = $TScenario.atCompany; status = 1; assignedResourceID = $null } } }
        "POST $TAT/Tickets/12345/Notes" { $b = Read-Body $c; Add-TNote '12345' ([pscustomobject]@{ id = 3001; title = $b.title; description = $b.description; publish = $b.publish }); return [pscustomobject]@{ itemId = 3001 } }
        "GET $TZD/organizations/autocomplete*" { return [pscustomobject]@{ organizations = @([pscustomobject]@{ id = 42; name = 'Contoso' }) } }
        "POST $TZD/tickets" {
            $null = $TState.tickets.Add([pscustomobject]@{ id = 506; subject = (Read-Body $c).ticket.subject; organization_id = 42; status = 'new'; created_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') })
            return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 506 } }
        }
        "PUT $TZD/tickets/506" { $cm = (Read-Body $c).ticket.comment; Add-TNote '506' ([pscustomobject]@{ id = 7001; body = $cm.body; public = $cm.public; author_id = 1 }); return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 506 } } }
        "GET $TZD/tickets/506/comments*" { return [pscustomobject]@{ comments = @(Get-TNotes '506'); next_page = $null } }
        "GET $TZD/search*" { return [pscustomobject]@{ results = @($TState.tickets); next_page = $null } }
    }
    throw "Unexpected call in test: $k"
}
function Get-WriteCalls { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and $_.Uri -notlike 'https://login.microsoftonline.com/*' }) }
function Test-NoPurge { return -not @($Mock.Calls | Where-Object { $_.Method -eq 'DELETE' -or $_.Uri -match '(?i)purge|compliance|/move|softDelete' }).Count }

$aiMal = '{"verdict":"malicious","confidence":0.93,"reasons":["DMARC failed and the sender domain imitates contoso.com.","The link text shows a Microsoft sign-in page but goes elsewhere."]}'
$aiSafeFenced = "``````json`n{`"verdict`":`"likely-safe`",`"confidence`":0.8,`"reasons`":[`"Authentication passes and links stay on the sender's domain.`"]}`n``````"
$aiSafe = '{"verdict":"likely-safe","confidence":0.7,"reasons":["Looks fine."]}'
$base = @{ reporter_upn = 'megan.bowen@contoso.com'; message_id = '<phish-0001@c0ntoso.com>'; company_name = 'Contoso'; company_tenant_id = $TenantId }
function New-Body { param([hashtable]$Over) $b = @{}; foreach ($k in $base.Keys) { $b[$k] = $base[$k] }; foreach ($k in $Over.Keys) { $b[$k] = $Over[$k] }; return $b }

# ---- 1. ConnectWise preview: malicious, nothing written, purge drafted ----
Reset-T 'connectwise'; $TScenario.message = 'bad'; $TScenario.graph403 = $false; $TScenario.empty = $false
$f = Invoke-Flow (New-Body @{}) $aiMal
$o = $f.r.out
Check 'preview: reached the ticket step' ($f.stage -eq 'ticket' -and -not $f.r.error) $f.r.error
Check 'preview: status pending_confirmation' ($o.status -eq 'pending_confirmation') $o.status
Check 'preview: nothing written to the PSA' (@(Get-WriteCalls).Count -eq 0) (Show-Calls)
Check 'preview: verdict malicious from the AI' ($o.verdict -eq 'malicious' -and $o.classified_by -eq 'ai' -and $o.confidence -eq 0.93) "$($o.verdict) $($o.classified_by) $($o.confidence)"
Check 'preview: draft purge in the internal note' ($o.purge_drafted -and $o.internal_note -like '*New-ComplianceSearch*' -and $o.internal_note -like '*New-ComplianceSearchAction*-Purge -PurgeType SoftDelete*' -and $o.internal_note -like '*DRAFT ONLY*')
Check 'preview: purge query names the sender and subject' ($o.internal_note -like "*(From:alerts@c0ntoso.com) AND (Subject:`"Your password expires today`")*")
Check 'preview: no purge, delete or move call was made' (Test-NoPurge) (Show-Calls)
$en = $f.enrich.enrichment
Check 'enrich: DMARC, SPF and compauth failures read from Authentication-Results' ($en.auth.dmarc -eq 'fail' -and $en.auth.spf -eq 'fail' -and $en.auth.compauth -eq 'fail' -and $en.auth.dkim -eq 'none')
Check 'enrich: Safe Links unwrapped to the real domain' (@($en.links.domains) -contains 'login-contoso.example' -and -not (@($en.links.domains) -match 'safelinks').Count) ($en.links.domains -join ',')
Check 'enrich: IP-address link flagged' (@($en.flags | Where-Object { $_ -like '*IP address*203.0.113.9*' }).Count -eq 1)
Check 'enrich: link text mismatch flagged' (@($en.flags | Where-Object { $_ -like '*Link text shows*login.microsoftonline.com*' }).Count -eq 1) ($en.flags -join ' | ')
Check 'enrich: reply-to mismatch flagged' (@($en.flags | Where-Object { $_ -like '*collect@mailbox.example*' }).Count -eq 1)
Check 'enrich: look-alike of contoso.com flagged' (@($en.flags | Where-Object { $_ -like '*c0ntoso.com looks like*contoso.com*' }).Count -eq 1)
Check 'enrich: html attachment with a double extension flagged' (@($en.attachments)[0].risk -eq 'html' -and @($en.flags | Where-Object { $_ -like '*double extension*' }).Count -eq 1)
Check 'enrich: rules verdict malicious' ($f.enrich.rules.verdict -eq 'malicious' -and $f.enrich.rules.score -ge 6) $f.enrich.rules.score
Check 'enrich: other-recipient count is explained, not attempted' ($en.other_recipients -like '*cannot count*')
Check 'enrich: URLs in the note are defanged' ($o.internal_note.Contains('hxxps://login-contoso[.]example') -and -not $o.internal_note.Contains('https://login-contoso.example'))
Check 'enrich: the email body text is not copied out' ($f.enrich.enrichment_json -notlike '*Your password expires today.<*' -and $o.internal_note -notlike '*<p>*')
if ($env:SHOW_NOTE) { Write-Host "--- internal note (scenario 1) ---`n$($o.internal_note)`n--- message: $($o.message)`n--- public: $($o.public_note)" }

# ---- 2. ConnectWise confirm: ticket opened high priority, note internal ----
Reset-T 'connectwise'
$f = Invoke-Flow (New-Body @{ confirm = $true }) $aiMal
$o = $f.r.out
$create = @(Get-Calls 'POST' "$TCW/service/tickets")
$noteCall = @(Get-Calls 'POST' "$TCW/service/tickets/501/notes")
Check 'cw confirm: status success, ticket 501' ($o.status -eq 'success' -and $o.ticket_id -eq '501') "$($o.status) $($o.ticket_id) $($f.r.error)"
Check 'cw confirm: ticket for Contoso (42) at high priority' ($create.Count -eq 1 -and (Read-Body $create[0]).company.id -eq 42 -and (Read-Body $create[0]).priority.id -eq 2 -and (Read-Body $create[0]).summary -like 'Phishing report (Malicious)*') (Show-Calls)
Check 'cw confirm: ticket description holds no findings' ((Read-Body $create[0]).initialDescription -notlike '*DMARC*')
Check 'cw confirm: findings note is internal and carries the draft' ($noteCall.Count -eq 1 -and (Read-Body $noteCall[0]).internalAnalysisFlag -eq $true -and (Read-Body $noteCall[0]).detailDescriptionFlag -eq $false -and (Read-Body $noteCall[0]).text -like '*New-ComplianceSearch*')
Check 'cw confirm: no purge, delete or move call was made' (Test-NoPurge) (Show-Calls)
$TLast = @(([string](Read-Body $noteCall[0]).text) -split "`n")[-1]
Check 'cw confirm: note ends with a marker that is only a code (no names, addresses or domains)' ($TLast -match '^\[phishing-report-triage: [0-9a-f]{8}\]$') $TLast
Check 'cw confirm: public note has no marker, ref or address' ($o.public_note -notmatch '\[|Ref:|@|c0ntoso') $o.public_note
# 2b. ServiceAI Retry of the same run: finds ticket 501 by its marker, opens no second ticket, adds no second note.
$Mock.Calls.Clear()
$f = Invoke-Flow (New-Body @{ confirm = $true }) $aiMal
$o = $f.r.out
Check 'cw rerun: success on the same ticket 501' ($o.status -eq 'success' -and $o.ticket_id -eq '501' -and $o.message -like '*opened by an earlier run*') "$($o.status) $($o.ticket_id) $($o.message) $($f.r.error)"
Check 'cw rerun: no second ticket and no second note' (-not @(Get-Calls 'POST' "$TCW/service/tickets").Count -and -not @(Get-Calls 'POST' "$TCW/service/tickets/*/notes").Count -and (Get-TNoteCount) -eq 1) (Show-Calls)
Check 'cw rerun: actions say the note was already there' (@($o.actions | Where-Object { $_ -like '*already there*' }).Count -eq 1) ($o.actions -join ' | ')

# ---- 3. Autotask confirm on an existing ticket: likely safe, fenced AI JSON ----
Reset-T 'autotask'; $TScenario.message = 'good'; $TScenario.atCompany = 42
$f = Invoke-Flow (New-Body @{ message_id = '<news-77@fabrikam.example>'; ticket_id = '12345'; psa_company_id = '42'; company_name = ''; confirm = 'true' }) $aiSafeFenced
$o = $f.r.out
$atNote = @(Get-Calls 'POST' "$TAT/Tickets/12345/Notes")
Check 'autotask: status success on ticket 12345' ($o.status -eq 'success' -and $o.ticket_id -eq '12345') "$($o.status) $($f.r.error)"
Check 'autotask: verdict likely-safe from fenced AI JSON' ($o.verdict -eq 'likely-safe' -and $o.classified_by -eq 'ai')
Check 'autotask: internal note (publish Internal Only, not a workflow note type)' ($atNote.Count -eq 1 -and (Read-Body $atNote[0]).publish -eq 2 -and (Read-Body $atNote[0]).noteType -eq 1)
Check 'autotask: no new ticket and no purge draft' (-not @(Get-Calls 'POST' "$TAT/Tickets").Count -and -not $o.purge_drafted -and $o.internal_note -notlike '*ComplianceSearch*')
$Mock.Calls.Clear()
$f = Invoke-Flow (New-Body @{ message_id = '<news-77@fabrikam.example>'; ticket_id = '12345'; psa_company_id = '42'; company_name = ''; confirm = 'true' }) $aiSafeFenced
Check 'autotask rerun: success, no second note' ($f.r.out.status -eq 'success' -and -not @(Get-Calls 'POST' "$TAT/Tickets/12345/Notes").Count -and (Get-TNoteCount) -eq 1) "$($f.r.out.status) $($f.r.error) $(Show-Calls)"

# ---- 4. Zendesk confirm: unreadable AI answer falls back to the rules score ----
Reset-T 'zendesk'; $TScenario.message = 'bad'
$f = Invoke-Flow (New-Body @{ confirm = $true }) 'I think this one is probably bad but I am not sure.'
$o = $f.r.out
$zc = @(Get-Calls 'POST' "$TZD/tickets")
$zn = @(Get-Calls 'PUT' "$TZD/tickets/506")
Check 'zendesk: rules fallback used' ($o.classified_by -eq 'rules' -and $o.verdict -eq 'malicious' -and @($o.warnings | Where-Object { $_ -like '*rules score was used*' }).Count -eq 1) "$($o.classified_by) $($o.verdict) $($f.r.error)"
Check 'zendesk: ticket for organization 42 at high priority' ($zc.Count -eq 1 -and (Read-Body $zc[0]).ticket.priority -eq 'high' -and (Read-Body $zc[0]).ticket.organization_id -eq 42)
Check 'zendesk: findings note is private' ($zn.Count -eq 1 -and (Read-Body $zn[0]).ticket.comment.public -eq $false -and (Read-Body $zn[0]).ticket.comment.body -like '*New-ComplianceSearch*')
$Mock.Calls.Clear()
$f2 = Invoke-Flow (New-Body @{ confirm = $true }) 'I think this one is probably bad but I am not sure.'
Check 'zendesk rerun: same ticket 506, no second ticket or comment' ($f2.r.out.ticket_id -eq '506' -and -not @(Get-Calls 'POST' "$TZD/tickets").Count -and -not @(Get-Calls 'PUT' "$TZD/tickets/506").Count -and (Get-TNoteCount) -eq 1) "$($f2.r.out.status) $($f2.r.error) $(Show-Calls)"
$t = Invoke-Step 'ticket' $null @{ enrichment = $f.enrich.enrichment_json; request = $f.enrich.request_json; rules = $f.enrich.rules_json; warnings_json = '[]'; classification = '' }
Check 'zendesk: empty AI answer -> rules' ($t.out.classified_by -eq 'rules' -and @($t.out.warnings | Where-Object { $_ -like '*was empty*' }).Count -eq 1) $t.error

# ---- 5. Missing Mail.Read: 403 names the permission ----
Reset-T 'connectwise'; $TScenario.graph403 = $true
$f = Invoke-Flow (New-Body @{}) $aiMal
Check '403: stops at the lookup naming Mail.Read' ($f.stage -eq 'enrich' -and $f.r.error -like '*Mail.Read*' -and $f.r.out.status -eq 'error') "$($f.stage) $($f.r.error)"
Check '403: nothing written' (@(Get-WriteCalls).Count -eq 0)
$TScenario.graph403 = $false

# ---- 6. Empty result: the email isn't in the mailbox ----
Reset-T 'connectwise'; $TScenario.empty = $true
$f = Invoke-Flow (New-Body @{}) '{"verdict":"suspicious","confidence":0,"reasons":["The email was not found, so it could not be checked."]}'
$o = $f.r.out
Check 'empty: verdict unknown, preview, no purge' ($o.verdict -eq 'unknown' -and $o.status -eq 'pending_confirmation' -and -not $o.purge_drafted) "$($o.verdict) $($o.status) $($f.r.error)"
Check 'empty: note says it was not found' ($o.internal_note -like '*could not be found*')
Check 'empty: medium priority planned' (@($o.planned)[0] -like 'Open a medium priority ticket*') (@($o.planned) -join ';')
$TScenario.empty = $false

# ---- 7. Parse: fail closed, literal @tokens, CloudRadial shape ----
Reset-T 'connectwise'
$p = Invoke-Step 'parse' ([pscustomobject]@{ reporter_upn = '@UserEmail'; message_id = '<x@y.example>' })
Check 'parse: literal @UserEmail counts as missing -> incomplete' ($p.error -like '*reporter was not identified*' -and $p.out.status -eq 'incomplete') $p.error
$p = Invoke-Step 'parse' ([pscustomobject]@{ reporter_upn = 'megan.bowen@contoso.com' })
Check 'parse: nothing to find the email by -> incomplete' ($p.error -like '*nothing to find the email by*')
$p = Invoke-Step 'parse' $null
Check 'parse: no input -> incomplete' ($p.out.status -eq 'incomplete')
$cr = [pscustomobject]@{ trigger = [pscustomobject]@{ reporter_upn = 'megan.bowen@contoso.com'; Ticket = [pscustomobject]@{ TicketId = 4321; Questions = @([pscustomobject]@{ Id = 'subject'; Value = 'Your password expires today' }, [pscustomobject]@{ Id = 'sender'; Value = 'Microsoft 365 Security <alerts@c0ntoso.com>' }) }; Company = [pscustomobject]@{ CompanyTenantId = $TenantId; CompanyName = 'Contoso' } } }
$p = Invoke-Step 'parse' $cr
$rq = $p.out.request
Check 'parse: CloudRadial nested shape' (-not $p.error -and $rq.subject -eq 'Your password expires today' -and $rq.sender -eq 'alerts@c0ntoso.com' -and $rq.ticket_id -eq '4321' -and $rq.company_tenant_id -eq $TenantId -and $rq.company_name -eq 'Contoso' -and $rq.confirm -eq $false) "$($p.error) $($p.out | ConvertTo-Json -Compress)"
$p = Invoke-Step 'parse' ([pscustomobject]@{ reporter_upn = 'megan.bowen@contoso.com'; ticket_id = '777'; psa = 'connectwise' })
$rq = $p.out.request
Check 'parse: ticket only -> forwarded From, Subject and Message-ID read from the ticket' ($rq.message_id -eq '<phish-0001@c0ntoso.com>' -and $rq.sender -eq 'alerts@c0ntoso.com' -and $rq.subject -eq 'Your password expires today') "$($p.error) $($rq | ConvertTo-Json -Compress)"
Check 'parse: ticket lookup made no writes' (@(Get-WriteCalls).Count -eq 0)

# ---- 8. Scope: wrong tenant, wrong company, unknown reporter ----
Reset-T 'connectwise'
$f = Invoke-Flow (New-Body @{ company_tenant_id = '99999999-8888-7777-6666-555555555555' }) $aiMal
Check 'scope: another tenant -> rejected before any mailbox read' ($f.stage -eq 'enrich' -and $f.r.out.status -eq 'rejected' -and -not @(Get-Calls 'GET' "$TGraph/users/u1/messages*").Count) $f.r.error
$f = Invoke-Flow (New-Body @{ reporter_upn = 'nobody@contoso.com' }) $aiMal
Check 'scope: reporter not in the tenant -> rejected' ($f.r.out.status -eq 'rejected') $f.r.error
Reset-T 'autotask'; $TScenario.atCompany = 99
$f = Invoke-Flow (New-Body @{ ticket_id = '12345'; psa_company_id = '42'; confirm = $true }) $aiMal
Check 'scope: ticket of another company -> rejected, no note' ($f.r.out.status -eq 'rejected' -and -not @(Get-Calls 'POST' "$TAT/Tickets/12345/Notes").Count) "$($f.r.out.status) $($f.r.error)"
$TScenario.atCompany = 42

# ---- 9. AI and rules two levels apart -> suspicious for a person ----
Reset-T 'connectwise'; $TScenario.message = 'bad'
$f = Invoke-Flow (New-Body @{}) $aiSafe
$o = $f.r.out
Check 'disagree: AI likely-safe vs rules malicious -> suspicious, no purge' ($o.verdict -eq 'suspicious' -and -not $o.purge_drafted -and @($o.warnings | Where-Object { $_ -like '*AI said likely-safe*' }).Count -eq 1) "$($o.verdict) $($f.r.error)"

# ---- 10. The earlier-run lookup fails: a warning, and the ticket is still opened ----
Reset-T 'connectwise'; $TScenario.findFail = $true
$f = Invoke-Flow (New-Body @{ confirm = $true }) $aiMal
$o = $f.r.out
Check 'lookup failure: ticket still opened, with a warning' ($o.status -eq 'success' -and @(Get-Calls 'POST' "$TCW/service/tickets").Count -eq 1 -and @($o.warnings | Where-Object { $_ -like '*earlier run*' }).Count -eq 1) "$($o.status) $($f.r.error) $($o.warnings -join ' | ')"
$TScenario.findFail = $false

Complete-Test
