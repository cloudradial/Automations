# Strict-mode harness for Dynamic Troubleshooting Article Delivery.
# Runs each PowerShell step exactly as it is in troubleshooting-article-delivery.yml (shared libraries and
# psa-extra included), through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the
# runner Key Vault, Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked. Outputs pass through JSON
# between steps, as the runner does. Placeholder data only (Contoso, Fabrikam, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a same-named step
# variable would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File automationai/troubleshooting-article-delivery/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in automationai/_shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\troubleshooting-article-delivery.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.type==='powershell-script')o[a.id]={s:a.properties.script,p:a.properties.parameters};}console.log(JSON.stringify(o));"
$TAll = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
$Steps = @{}; foreach ($k in $TAll.Keys) { $Steps[$k] = $TAll[$k].s }
Check 'workflow has parse, check and act steps' ($Steps.Contains('parse') -and $Steps.Contains('check') -and $Steps.Contains('act'))
Check 'first step binds trigger = {{ nodes.trigger.output }}; later steps unbound' ((@($TAll['parse'].p) | ConvertTo-Json -Compress) -eq '{"name":"trigger","expression":"{{ nodes.trigger.output }}"}' -and -not @($TAll['check'].p).Count -and -not @($TAll['act'].p).Count)

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
    $c = Invoke-Step 'check' $p.out
    if ($c.error) { return @{ stage = 'check'; r = $c } }
    $a = Invoke-Step 'act' $c.out
    return @{ stage = 'act'; r = $a; check = $c.out }
}

# ---- placeholder data ----
$TCR = 'https://api.example.cloudradial.test'
$TCW = 'https://cw.example.com/v4_6_release/apis/3.0'; $TAT = 'https://webservices.autotask.example/atservicesrest/v1.0'; $TZD = 'https://example.zendesk.com/api/v2'
$TCrSecrets = @{ 'CloudRadial-BaseUrl' = $TCR; 'CloudRadial-PublicKey' = 'pub'; 'CloudRadial-PrivateKey' = 'priv' }
$TPsa = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = $TCW; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
}
function Get-TSecrets { param([string]$P) $s = @{}; foreach ($h in @($TCrSecrets, $TPsa[$P])) { foreach ($k in $h.Keys) { $s[$k] = $h[$k] } }; return $s }
$TUrl = 'https://contoso.portal.example-msp.test/kb/article/321'
$TMarker = 'Ref: AAI troubleshooting article sent (article 321, to megan.bowen@contoso.com).'

function Reset-TScenario {
    $global:TS = @{
        notes = @(); article = [pscustomobject]@{ articleId = 321; companyId = 1; subject = 'Fix Outlook not opening'; datePublished = '2026-09-01T00:00:00Z'; url = $null }
        byTitle = @(); users = @([pscustomobject]@{ userId = 'u1'; email = 'megan.bowen@contoso.com'; firstName = 'Megan'; companyId = 1 })
        psaKeyCompanies = @([pscustomobject]@{ companyId = 1; name = 'Contoso'; psaKey = 101 })
        ticketStatus = 'New'; articleForbidden = $false; publicForbidden = $false; ticket404 = $false
    }
}
Reset-TScenario

$Handler = {
    param($c, $n)
    $k = "$($c.Method) $($c.Uri)"
    $S = $global:TS
    $u = [uri]::UnescapeDataString($c.Uri)
    switch -Wildcard -CaseSensitive ($k) {
        # CloudRadial
        "GET $TCR/v2/odata/company[?]*" { if ($u -like '*companyId eq 2*') { return [pscustomobject]@{ value = @([pscustomobject]@{ companyId = 2; name = 'Fabrikam'; psaKey = 102 }) } }; if ($u -like '*psaKey eq 101*') { return [pscustomobject]@{ value = @($S.psaKeyCompanies) } }; return [pscustomobject]@{ value = @() } }
        "GET $TCR/v2/article/321" { if ($S.articleForbidden) { New-HttpError 403 '{"message":"The API key does not have access to articles."}' }; return [pscustomobject]@{ success = $true; data = $S.article } }
        "GET $TCR/v2/article/*" { New-HttpError 404 '{"message":"Not found"}' }
        "GET $TCR/v2/odata/article[?]*" { return [pscustomobject]@{ value = @($S.byTitle) } }
        "GET $TCR/v2/odata/user[?]*" { return [pscustomobject]@{ value = @($S.users | Where-Object { $u -like "*email eq '$($_.email)'*" }) } }
        # ConnectWise ticket 12345
        "GET $TCW/service/tickets/12345" { return [pscustomobject]@{ id = 12345; summary = 'Outlook will not open'; company = [pscustomobject]@{ id = 101 }; status = [pscustomobject]@{ name = $S.ticketStatus }; board = [pscustomobject]@{ id = 1 }; owner = $null } }
        "GET $TCW/service/tickets/404" { New-HttpError 404 '{"message":"Ticket not found"}' }
        "GET $TCW/service/tickets/12345/notes[?]*" { return @($S.notes | ForEach-Object { [pscustomobject]@{ id = 1; text = $_; internalAnalysisFlag = $true } }) }
        "POST $TCW/service/tickets/12345/notes" { if ($S.publicForbidden -and $c.Body -like '*"detailDescriptionFlag":true*') { New-HttpError 403 '{"message":"Member cannot add discussion notes."}' }; return [pscustomobject]@{ id = 2 } }
        # Autotask ticket 555
        "GET $TAT/Tickets/555" { return [pscustomobject]@{ item = [pscustomobject]@{ id = 555; title = 'Printer offline'; description = ''; companyID = 101; status = 1; assignedResourceID = $null } } }
        "GET $TAT/TicketNotes/query[?]*" { return [pscustomobject]@{ items = @($S.notes | ForEach-Object { [pscustomobject]@{ title = 'Troubleshooting article sent'; description = $_ } }) } }
        "GET $TAT/TicketNotes/entityInformation/fields" { return [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                    [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) } }
        "GET $TAT/Tickets/entityInformation/fields" { return [pscustomobject]@{ fields = @([pscustomobject]@{ name = 'status'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'New'; isActive = $true }, [pscustomobject]@{ value = '5'; label = 'Complete'; isActive = $true }) }) } }
        "PATCH $TAT/Tickets" { return [pscustomobject]@{ itemId = 555 } }
        "POST $TAT/Tickets/555/Notes" { return [pscustomobject]@{ itemId = 9 } }
        # Zendesk ticket 777
        "GET $TZD/tickets/777" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 777; subject = 'VPN drops'; description = ''; organization_id = 101; status = 'open'; assignee_id = $null } } }
        "GET $TZD/tickets/777/comments[?]*" { return [pscustomobject]@{ comments = @($S.notes | ForEach-Object { [pscustomobject]@{ body = $_; public = $false } }) } }
        "PUT $TZD/tickets/777" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 777 } } }
    }
    throw "Unexpected call in test: $k"
}
function Get-TWrites { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' }) }
function Get-TCwNotes { return @(Get-Calls 'POST' "$TCW/service/tickets/12345/notes" | ForEach-Object { Read-Body $_ }) }
$TSend = @{ ticketId = '12345'; contactEmail = 'megan.bowen@contoso.com'; articleTitle = 'Fix Outlook not opening'; articleUrl = $TUrl; confidence = 0.9; triggerSource = 'serviceai-triage' }
function New-TBody { param([hashtable]$Base, [hashtable]$Over = @{}) $b = @{}; foreach ($k in $Base.Keys) { $b[$k] = $Base[$k] }; foreach ($k in $Over.Keys) { $b[$k] = $Over[$k] }; return $b }

# ---- 1. Send (ConnectWise): public note with the link and the reply line, internal note with the marker ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody $TSend)
$o = $f.r.out
Check 'send: status success, sent' ($o.status -eq 'success' -and $o.sent -eq $true -and -not $f.r.error) "$($f.stage) $($f.r.error) $($o.status) $($o.reason)"
$TN = @(Get-TCwNotes)
Check 'send: one public (Discussion) note and one internal note' ($TN.Count -eq 2 -and $TN[0].detailDescriptionFlag -eq $true -and $TN[0].internalAnalysisFlag -eq $false -and $TN[1].internalAnalysisFlag -eq $true) (Show-Calls)
Check "send: public note has the link, greets by first name and says Reply 'fixed' and we'll close this" ($TN[0].text -like "*$TUrl*" -and $TN[0].text -like 'Hi Megan,*' -and $TN[0].text -like "*Reply 'fixed' and we'll close this ticket*") $TN[0].text
Check 'send: internal note carries the marker reply mode looks for' ($TN[1].text -like "*$TMarker*" -and $TN[1].text -like '*confidence 0.9*') $TN[1].text
Check 'send: no status change' (-not @(Get-Calls 'PATCH' "$TCW/*").Count)
Check 'send: no em dash in the output' (-not (($o | ConvertTo-Json -Depth 10).Contains([string][char]0x2014)))

# ---- 2. Dry run: everything checked, nothing written ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody $TSend @{ dry_run = $true })
Check 'dry run: pending_confirmation with the note it would write, no writes' ($f.r.out.status -eq 'pending_confirmation' -and $f.r.out.public_note -like "*$TUrl*" -and @(Get-TWrites).Count -eq 0) "$($f.r.out.status) $(Show-Calls)"

# ---- 3. Below the confidence threshold: nothing sent, internal note says why ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody $TSend @{ confidence = '60%' })
$TN = @(Get-TCwNotes)
Check 'low confidence: rejected, only an internal note' ($f.r.out.status -eq 'rejected' -and $f.r.out.decision -eq 'low-confidence' -and $TN.Count -eq 1 -and $TN[0].internalAnalysisFlag -eq $true -and $TN[0].text -like '*0.6 is below the 0.75 threshold*') "$($f.r.out.decision) $(Show-Calls)"
Check 'low confidence: CloudRadial never read' (-not @($Mock.Calls | Where-Object { $_.Uri -like "$TCR/*" }).Count)
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody $TSend @{ confidence = 0.6; min_confidence = 0.5 })
Check 'custom threshold: 0.6 sends when min_confidence is 0.5' ($f.r.out.decision -eq 'send' -and $f.r.out.sent -eq $true) $f.r.out.reason

# ---- 4. Retry (ServiceAI replays the request): already sent, nothing written ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$global:TS.notes = @("Troubleshooting article sent.`n$TMarker")
$f = Invoke-Flow (New-TBody $TSend)
Check 'retry: already-sent, success, no writes at all' ($f.r.out.decision -eq 'already-sent' -and $f.r.out.status -eq 'success' -and @(Get-TWrites).Count -eq 0) "$($f.r.out.decision) $(Show-Calls)"

# ---- 5. Article checks ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$global:TS.article = [pscustomobject]@{ articleId = 321; companyId = 2; subject = 'Fix Outlook not opening'; datePublished = '2026-09-01T00:00:00Z'; url = $null }
$f = Invoke-Flow (New-TBody $TSend)
$TN = @(Get-TCwNotes)
Check "wrong company: rejected, internal note only, never names the other company" ($f.r.out.decision -eq 'wrong-company' -and $TN.Count -eq 1 -and $TN[0].internalAnalysisFlag -eq $true -and $TN[0].text -notlike '*Fabrikam*') "$($f.r.out.decision) $(Show-Calls)"
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$global:TS.article = [pscustomobject]@{ articleId = 321; companyId = 1; subject = 'Fix Outlook not opening'; datePublished = (Get-Date).ToUniversalTime().AddDays(3).ToString('yyyy-MM-ddTHH:mm:ssZ'); url = $null }
$f = Invoke-Flow (New-TBody $TSend)
Check 'scheduled article: unpublished, not sent' ($f.r.out.decision -eq 'unpublished' -and $f.r.out.sent -eq $false -and @(Get-TCwNotes | Where-Object { $_.detailDescriptionFlag }).Count -eq 0) $f.r.out.reason
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$global:TS.article = [pscustomobject]@{ articleId = 321; companyId = 1; subject = 'Reset your VPN token'; datePublished = '2026-09-01T00:00:00Z'; url = $null }
$f = Invoke-Flow (New-TBody $TSend)
Check 'link points at a different article: not sent' ($f.r.out.decision -eq 'link-mismatch') $f.r.out.reason
# By title (no id in the link): MSP-wide article on an unknown host is refused, then allowed by allowedLinkHosts.
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$global:TS.byTitle = @([pscustomobject]@{ articleId = 88; companyId = 0; subject = 'Fix Outlook not opening'; datePublished = '2026-08-01T00:00:00Z'; url = $null })
$f = Invoke-Flow (New-TBody $TSend @{ articleUrl = 'https://help.example-msp.test/outlook' })
Check 'by title, unknown host: link-unverified, not sent' ($f.r.out.decision -eq 'link-unverified' -and $f.r.out.sent -eq $false) $f.r.out.reason
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$global:TS.byTitle = @([pscustomobject]@{ articleId = 88; companyId = 0; subject = 'Fix Outlook not opening'; datePublished = '2026-08-01T00:00:00Z'; url = $null })
$f = Invoke-Flow (New-TBody $TSend @{ articleUrl = 'https://help.example-msp.test/outlook'; allowedLinkHosts = 'help.example-msp.test' })
Check 'by title, MSP-wide article on an allowed host: sent' ($f.r.out.decision -eq 'send' -and $f.r.out.sent -eq $true -and $f.r.out.article.articleId -eq 88) $f.r.out.reason
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$global:TS.byTitle = @([pscustomobject]@{ articleId = 90; companyId = 2; subject = 'Fix Outlook not opening'; datePublished = '2026-08-01T00:00:00Z'; url = $null })
$f = Invoke-Flow (New-TBody $TSend @{ articleUrl = 'https://contoso.cloudradial.com/kb' })
Check "by title, only another company's article: wrong-company" ($f.r.out.decision -eq 'wrong-company') $f.r.out.reason
# Empty result: no article by that title.
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody $TSend @{ articleUrl = 'https://contoso.cloudradial.com/kb' })
Check 'empty result: no article, rejected with an internal note, nothing public' ($f.r.out.decision -eq 'no-article' -and $f.r.out.status -eq 'rejected' -and @(Get-TCwNotes).Count -eq 1 -and -not (Get-TCwNotes)[0].detailDescriptionFlag) "$($f.r.out.decision) $(Show-Calls)"

# ---- 6. Contact and company checks ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$global:TS.users = @([pscustomobject]@{ userId = 'u9'; email = 'alex.wilber@fabrikam.com'; firstName = 'Alex'; companyId = 2 })
$f = Invoke-Flow (New-TBody $TSend @{ contactEmail = 'alex.wilber@fabrikam.com' })
Check 'contact of another company: wrong-contact, not sent' ($f.r.out.decision -eq 'wrong-contact' -and $f.r.out.sent -eq $false) $f.r.out.reason
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$global:TS.users = @()
$f = Invoke-Flow (New-TBody $TSend)
Check 'contact not a portal user: sent with a warning, plain greeting' ($f.r.out.sent -eq $true -and $f.r.out.public_note -like 'Hi, while*' -and (@($f.r.out.warnings) -join ' ') -like "*isn't a portal user*") (@($f.r.out.warnings) -join ' ')
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$global:TS.psaKeyCompanies = @()
$f = Invoke-Flow (New-TBody $TSend)
Check 'no CloudRadial company linked: incomplete, internal note' ($f.r.out.status -eq 'incomplete' -and $f.r.out.decision -eq 'no-company' -and @(Get-TCwNotes).Count -eq 1) $f.r.out.reason
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody $TSend @{ ticketId = '404' })
Check 'unknown ticket: rejected quietly (no note can be written)' ($f.r.out.decision -eq 'no-ticket' -and @(Get-TWrites).Count -eq 0) "$($f.r.out.decision) $($f.r.error)"
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$global:TS.ticketStatus = 'Closed (resolved)'
$f = Invoke-Flow (New-TBody $TSend)
Check 'closed ticket: nothing sent' ($f.r.out.decision -eq 'ticket-closed' -and @(Get-TCwNotes | Where-Object { $_.detailDescriptionFlag }).Count -eq 0) $f.r.out.reason

# ---- 7. Missing permission (403) ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$global:TS.articleForbidden = $true
$f = Invoke-Flow (New-TBody $TSend)
Check '403 CloudRadial article read: check step fails with a plain message, nothing written' ($f.stage -eq 'check' -and $f.r.error -like '*HTTP 403*does not have access to articles*' -and @(Get-TWrites).Count -eq 0) "$($f.stage) $($f.r.error)"
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$global:TS.publicForbidden = $true
$f = Invoke-Flow (New-TBody $TSend)
$TN = @(Get-TCwNotes | Where-Object { $_.internalAnalysisFlag })
Check '403 PSA public note: status error, internal note explains' ($f.r.out.status -eq 'error' -and $f.r.out.sent -eq $false -and $TN.Count -eq 1 -and $TN[0].text -like '*could not be posted*HTTP 403*') "$($f.r.out.status) $(Show-Calls)"

# ---- 8. Reply mode (Autotask): a clear yes closes the ticket ----
Reset-Mock (Get-TSecrets 'autotask') $Handler; Reset-TScenario
$global:TS.notes = @($TMarker)
$f = Invoke-Flow @{ mode = 'reply'; ticketId = '555'; replyText = "Fixed, thanks!`n`nOn Mon, Oct 5, 2026 at 9:00 AM Example MSP wrote:`n> Reply 'fixed' and we'll close this ticket. It is not working yet?" }
$o = $f.r.out
$TPatch = @(Get-Calls 'PATCH' "$TAT/Tickets")
$TAtNotes = @(Get-Calls 'POST' "$TAT/Tickets/555/Notes" | ForEach-Object { Read-Body $_ })
Check 'reply fixed: success, closed (quoted history ignored)' ($o.status -eq 'success' -and $o.closed -eq $true -and $o.decision -eq 'close') "$($o.decision) $($o.reason) $($f.r.error)"
Check 'reply fixed: status set to Complete (5)' ($TPatch.Count -eq 1 -and (Read-Body $TPatch[0]).status -eq 5 -and (Read-Body $TPatch[0]).id -eq 555) (Show-Calls)
Check 'reply fixed: public note then internal note with the closed marker' ($TAtNotes.Count -eq 2 -and $TAtNotes[0].publish -eq 1 -and $TAtNotes[1].publish -eq 2 -and $TAtNotes[1].description -like '*Ref: AAI troubleshooting article closed*') ($TAtNotes | ConvertTo-Json -Compress)

# ---- 9. Reply mode: anything short of a clear yes leaves the ticket open, with an internal note ----
foreach ($TReply in @('Still not working', 'fixed?', 'It works now but Outlook is slow', 'Thanks, I will try it later', 'no longer an issue', 'Not fixed')) {
    Reset-Mock (Get-TSecrets 'autotask') $Handler; Reset-TScenario
    $global:TS.notes = @($TMarker)
    $f = Invoke-Flow @{ mode = 'reply'; ticketId = '555'; replyText = $TReply }
    $TAtNotes = @(Get-Calls 'POST' "$TAT/Tickets/555/Notes" | ForEach-Object { Read-Body $_ })
    Check "reply '$TReply': not closed, one internal note" ($f.r.out.decision -eq 'not-clear' -and $f.r.out.closed -eq $false -and -not @(Get-Calls 'PATCH' "$TAT/Tickets").Count -and $TAtNotes.Count -eq 1 -and $TAtNotes[0].publish -eq 2) "$($f.r.out.decision) $($f.r.out.reason)"
}
Reset-Mock (Get-TSecrets 'autotask') $Handler; Reset-TScenario
$f = Invoke-Flow @{ mode = 'reply'; ticketId = '555'; replyText = 'fixed' }
Check 'reply with no article sent: no-op, internal note, not closed' ($f.r.out.decision -eq 'no-article-sent' -and -not @(Get-Calls 'PATCH' "$TAT/Tickets").Count -and @(Get-Calls 'POST' "$TAT/Tickets/555/Notes").Count -eq 1) $f.r.out.reason
Reset-Mock (Get-TSecrets 'autotask') $Handler; Reset-TScenario
$global:TS.notes = @($TMarker)
$f = Invoke-Flow @{ mode = 'reply'; ticketId = '555'; replyText = 'fixed'; replyFrom = 'someone@fabrikam.com' }
Check 'reply from someone else: not-the-contact, not closed' ($f.r.out.decision -eq 'not-the-contact' -and -not @(Get-Calls 'PATCH' "$TAT/Tickets").Count) $f.r.out.reason
Reset-Mock (Get-TSecrets 'autotask') $Handler; Reset-TScenario
$global:TS.notes = @($TMarker)
$f = Invoke-Flow @{ mode = 'reply'; ticketId = '555'; replyText = 'All good now, thank you'; autoClose = $false }
Check 'reply fixed with autoClose off: not closed, technician told' ($f.r.out.decision -eq 'fixed-no-autoclose' -and -not @(Get-Calls 'PATCH' "$TAT/Tickets").Count) $f.r.out.reason

# ---- 10. Zendesk reply: solved, private and public comments; retry after close is quiet ----
Reset-Mock (Get-TSecrets 'zendesk') $Handler; Reset-TScenario
$global:TS.notes = @($TMarker)
$f = Invoke-Flow @{ mode = 'reply'; ticketId = '777'; replyText = 'Yes that worked' }
$TZ = @(Get-Calls 'PUT' "$TZD/tickets/777" | ForEach-Object { Read-Body $_ })
Check 'zendesk reply: solved, then a public and a private comment' ($f.r.out.closed -eq $true -and $TZ.Count -eq 3 -and $TZ[0].ticket.status -eq 'solved' -and $TZ[1].ticket.comment.public -eq $true -and $TZ[2].ticket.comment.public -eq $false) ($TZ | ConvertTo-Json -Depth 5 -Compress)
Reset-Mock (Get-TSecrets 'zendesk') $Handler; Reset-TScenario
$global:TS.notes = @($TMarker, 'Ref: AAI troubleshooting article closed.')
$f = Invoke-Flow @{ mode = 'reply'; ticketId = '777'; replyText = 'Yes that worked' }
Check 'zendesk retry after close: already-closed, nothing written' ($f.r.out.decision -eq 'already-closed' -and @(Get-TWrites).Count -eq 0) $f.r.out.decision

# ---- 11. Input checks ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody $TSend @{ ticketId = '@TicketId' })
Check 'input: literal @token ticketId is missing' ($f.r.out.status -eq 'incomplete' -and $f.r.out.message -like '*ticketId is missing*' -and $Mock.Calls.Count -eq 0) $f.r.out.message
$f = Invoke-Flow (New-TBody $TSend @{ confidence = 'high' })
Check 'input: non-numeric confidence refused' ($f.r.out.status -eq 'incomplete' -and $f.r.out.message -like '*confidence must be a number*') $f.r.out.message
$f = Invoke-Flow (New-TBody $TSend @{ articleUrl = 'http://contoso.portal.example-msp.test/kb/article/321' })
Check 'input: http link refused' ($f.r.out.status -eq 'incomplete' -and $f.r.out.message -like '*https*') $f.r.out.message
$f = Invoke-Flow (New-TBody $TSend @{ contactEmail = 'not-an-email' })
Check 'input: bad contact email refused' ($f.r.out.status -eq 'incomplete') $f.r.out.message
$f = Invoke-Flow @{ mode = 'reply'; ticketId = '555' }
Check 'input: reply without replyText refused' ($f.r.out.status -eq 'incomplete' -and $f.r.out.message -like '*replyText*') $f.r.out.message
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody $TSend @{ confidence = 90 }) -Manual
Check 'input: manual unwrapped input; 90 means 0.9' ($f.r.out.sent -eq $true -and [double]$f.r.out.confidence -eq 0.9) "$($f.r.out.confidence) $($f.r.out.reason)"

Complete-Test
