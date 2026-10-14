# Strict-mode harness for Resolution to KB Draft.
# Runs both PowerShell steps exactly as they are in kb-draft-from-resolution.yml (shared psa.ps1,
# psa-tickets.ps1 and cloudradial.ps1, and src/scrub.ps1 included), through & ([scriptblock]::Create(...))
# under Set-StrictMode -Version Latest, with the runner Key Vault, Invoke-RestMethod, Get-NodeInput and
# Set-NodeOutput mocked. The AI Prompt step is simulated by handing the save step a judgment string.
# Placeholder data only (Contoso, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a step variable of the same
# name would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File kb-draft-from-resolution/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\kb-draft-from-resolution.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.properties&&a.properties.script)o[a.id]=a.properties.script;if(a.type==='ai-prompt'){o['judge.prompt']=a.properties.promptTemplate;o['judge.model']=a.properties.model;o['judge.system']=a.properties.systemMessage}if(a.id==='save')o['save.params']=JSON.stringify(a.properties.parameters)}o.webhook=String(d.definition.activities[0].properties.webhookEnabled);console.log(JSON.stringify(o))"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow has gather, judge and save' ($Steps.Contains('gather') -and $Steps.Contains('save') -and $Steps.Contains('judge.prompt'))
Check 'judge reads the gather facts, model blank, told to stay general' ($Steps['judge.prompt'] -like '*{{ nodes.gather.output.facts_json }}*' -and $Steps['judge.model'] -eq '' -and $Steps['judge.system'] -like '*must be general*')
Check 'save is bound to gather and judge' ($Steps['save.params'] -like '*nodes.gather.output.ctx_json*' -and $Steps['save.params'] -like '*nodes.judge.output.judgment*')
Check 'webhook ships disabled' ($Steps['webhook'] -eq 'false')
Check 'scrub.ps1 and shared libraries pasted' ($Steps['gather'] -like '*function Invoke-KbScrub*' -and $Steps['save'] -like '*function Invoke-KbScrub*' -and $Steps['save'] -like '*function Invoke-CrApi*')

# ---- runner mocks ----
$global:NodeIn = $null; $global:NodeParams = @{}; $global:NodeOut = $null
function Get-NodeInput { param([string]$Name) if ($Name) { if ($global:NodeParams.Contains($Name)) { return $global:NodeParams[$Name] }; return $null }; return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Invoke-Step {
    param([string]$Id, $In = $null, [hashtable]$Params = @{})
    $global:NodeIn = $In; $global:NodeParams = $Params; $global:NodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps[$Id])) } catch { $err = [string]$_.Exception.Message }
    $o = $null; if ($null -ne $global:NodeOut) { $o = ($global:NodeOut | ConvertTo-Json -Depth 14 | ConvertFrom-Json) }
    return @{ out = $o; error = $err }
}
function Invoke-Flow {
    param($Body, [string]$Ai)
    $g = Invoke-Step 'gather' ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    if ($g.error) { return @{ stage = 'gather'; out = $g.out; error = $g.error } }
    $s = Invoke-Step 'save' $null @{ ctx = $g.out.ctx_json; judgment = $Ai }
    return @{ stage = 'save'; out = $s.out; error = $s.error; facts = ($g.out.facts_json | ConvertFrom-Json); ctx = ($g.out.ctx_json | ConvertFrom-Json) }
}
function Ai {
    param([bool]$Worth = $true, [string]$Subject = 'Printer shows offline after a Windows update', $Steps = @('Remove the printer from Printers & scanners.', 'Add it again with the vendor driver.', 'Print a test page.'), [string]$Cause = 'The update replaced the printer driver with a generic one.')
    return (@{ worthPublishing = $Worth; reason = 'A repeatable fix for a common printer fault.'; subject = $Subject; category = 'Printing'; appliesTo = 'Windows 11 network printers'; symptoms = @('The printer shows offline', 'Print jobs stay in the queue'); cause = $Cause; steps = @($Steps) } | ConvertTo-Json -Compress)
}

# ---- placeholder ConnectWise ticket 1001 and CloudRadial ----
$TCW = 'https://api-na.example.com/v4_6_release/apis/3.0'; $TCR = 'https://api.cr.example.com'
$TBase = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = $TCW; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid'
    'CloudRadial-BaseUrl' = $TCR; 'CloudRadial-PublicKey' = 'crpub'; 'CloudRadial-PrivateKey' = 'crpriv'; 'KbDraft-CompanyId' = '5' }
$TResolution = 'Called Pat Doe on 555-123-4567. The Contoso Ltd printer at 10.0.0.25 showed offline after the Windows update. Fixed by removing the printer and adding it again with the vendor driver from \\fs01\drivers\hp. Admin password: Hunter2! was used. Emailed pat.doe@contoso.com to confirm.'
$TC = @{ notes = (New-Object System.Collections.ArrayList); resFlag = $true; prior = @(); closed = $true; posted = (New-Object System.Collections.ArrayList) }
function Reset-TCw { param([hashtable]$Secrets = $TBase, [string]$Res = $TResolution) $TC.notes.Clear(); $TC.posted.Clear(); $TC.prior = @(); $TC.closed = $true; $TC.res = $Res; Reset-Mock $Secrets $TCwRouter }
$TCwRouter = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    if ($c.Method -eq 'GET' -and $u -match '/service/tickets/1001$') { return [pscustomobject]@{ id = 1001; summary = 'Contoso Ltd printer offline'; board = [pscustomobject]@{ id = 1; name = 'Service Desk' }; company = [pscustomobject]@{ id = 42; name = 'Contoso Ltd' }; contactEmailAddress = 'pat.doe@contoso.com'; contactName = 'Pat Doe'; priority = [pscustomobject]@{ id = 3; name = 'Priority 3 - Normal Response' }; status = [pscustomobject]@{ name = 'Closed' }; closedFlag = $TC.closed } }
    if ($c.Method -eq 'GET' -and $u -like '*/service/tickets/1001/notes*') {
        $base = @([pscustomobject]@{ id = 1; text = 'Hi, the printer on floor 2 is offline again. Pat'; internalAnalysisFlag = $false; detailDescriptionFlag = $true; resolutionFlag = $false; contact = [pscustomobject]@{ id = 5; name = 'Pat Doe' } })
        if ($TC.res) { $base += [pscustomobject]@{ id = 2; text = $TC.res; internalAnalysisFlag = $false; detailDescriptionFlag = $false; resolutionFlag = $true; member = [pscustomobject]@{ id = 7; identifier = 'jlee'; name = 'Jordan Lee' } } }
        return , ($base + @(@($TC.notes) | ForEach-Object { $_ }))
    }
    if ($c.Method -eq 'POST' -and $u -like '*/service/tickets/1001/notes') { $b = Read-Body $c; $null = $TC.notes.Add([pscustomobject]@{ id = 900 + $TC.notes.Count; text = $b.text; internalAnalysisFlag = [bool]$b.internalAnalysisFlag; detailDescriptionFlag = $false; resolutionFlag = $false }); return [pscustomobject]@{ id = 900 } }
    if ($c.Method -eq 'GET' -and $u -like "$TCR/v2/odata/article*") { return [pscustomobject]@{ value = @($TC.prior) } }
    if ($c.Method -eq 'POST' -and $u -eq "$TCR/v2/article") { $null = $TC.posted.Add((Read-Body $c)); return [pscustomobject]@{ articleId = 812 } }
    return $null
}
function Get-TWrites { return , @($Mock.Calls | Where-Object { $_.Method -ne 'GET' }) }
$TBody = @{ ticketId = '1001' }
$TLeaks = @('Pat', 'Doe', 'Contoso', '555-123-4567', '10.0.0.25', 'fs01', 'Hunter2', 'pat.doe@contoso.com', 'Jordan')

# 1. Preview: the AI only ever sees scrubbed text, and nothing is saved.
Reset-TCw
$r = Invoke-Flow $TBody (Ai)
$f = [string]$r.facts.resolution
$leaked = @($TLeaks | Where-Object { $f -like "*$_*" -or [string]$r.facts.summary -like "*$_*" })
Check 'scrub before AI: no client, person, phone, IP, path or password reaches the AI' (-not $leaked.Count -and $f -like '*the user*' -and $f -like '*the company printer*' -and $f -like '*the IP address*' -and $f -like '*\\server\share*' -and $f -like '*password: `[removed`]*') "leaked: $($leaked -join ', ') :: $f"
Check 'resolution taken from the ConnectWise resolution note' ((@($r.ctx.actions) -join ' ') -like '*notes marked as the resolution*' -and (@($r.ctx.removed) -join ',') -like '*a password or key*') (@($r.ctx.actions) -join ' | ')
Check 'preview: pending, draft returned, nothing written' ($r.out.status -eq 'pending_confirmation' -and $r.out.draft.subject -eq '[Draft] Printer shows offline after a Windows update' -and -not (Get-TWrites).Count) "$($r.error) $($r.out.message) $(Show-Calls)"
Check 'draft body: review banner, symptoms, cause, numbered steps' ($r.out.draft.body -like '<p><strong>Draft for review.</strong>*<h2>Symptoms</h2><ul><li>The printer shows offline</li>*<h2>Cause</h2>*<h2>How to fix it</h2><ol><li>Remove the printer from Printers &amp; scanners.</li>*') $r.out.draft.body

# 2. The scrub keeps ordinary words: the names Will and Mark don't remove "will" and "mark".
$code = ($Steps['gather'] -split "`n" | Where-Object { $_ }) -join "`n"
$scrubFn = [regex]::Match($Steps['gather'], '(?s)# ---------- src/scrub\.ps1.*?# ---------- end src/scrub\.ps1 ----------').Value
$TOut = & ([scriptblock]::Create("Set-StrictMode -Version Latest`n$scrubFn`n" + '$n = Get-KbNames -Company ''Fabrikam Group'' -People @(''Mark Will''); (Invoke-KbScrub -Text ''Restart it and it will work. Mark the ticket solved. Mark Will reported it. Ask Will.'' -Companies $n.companies -People $n.people).text'))
Check 'scrub: names removed only as names' ($TOut -eq 'Restart it and it will work. the user the ticket solved. the user reported it. Ask the user.') $TOut

# 3. The AI put a detail back: it's taken out again and flagged.
Reset-TCw
$r = Invoke-Flow $TBody (Ai -Steps @('Call Pat Doe at 555-123-4567 to confirm.', 'Remove and re-add the printer.') -Cause 'Contoso Ltd used an old driver.')
Check 'AI leak: removed again from the draft, with a warning' ($r.out.draft.body -notmatch 'Pat|Doe|Contoso|555-123' -and (@($r.out.warnings) -join ' ') -like "*still had*taken out again*") "$($r.out.draft.body) $(@($r.out.warnings) -join ' | ')"
$r = Invoke-Flow $TBody (Ai -Steps @('Run <script>alert(1)</script> nowhere.'))
Check 'draft body is HTML-escaped' ($r.out.draft.body -like '*&lt;script&gt;*' -and $r.out.draft.body -notlike '*<script>*') $r.out.draft.body

# 4. Confirmed without the draft company: nothing saved.
$s = $TBase.Clone(); $s.Remove('KbDraft-CompanyId')
Reset-TCw $s
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai)
Check 'no KbDraft-CompanyId: incomplete, nothing saved' ($r.out.status -eq 'incomplete' -and $r.out.message -like '*KbDraft-CompanyId*' -and -not $TC.posted.Count -and -not (Get-TWrites).Count) "$($r.out.message) $(Show-Calls)"
$s['KbDraft-CompanyId'] = '0'
Reset-TCw $s
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai)
Check 'company 0 (seen by every client) is refused' ($r.out.status -eq 'incomplete' -and -not $TC.posted.Count) $r.out.message

# 5. Confirmed: saved under the MSP's company, dated 2099, and the ticket noted.
Reset-TCw
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai)
$pb = $(if ($TC.posted.Count) { $TC.posted[0] } else { $null })
Check 'confirm: article saved under company 5, dated 2099-12-31, marked as a draft' ($r.out.status -eq 'success' -and $TC.posted.Count -eq 1 -and $pb.companyId -eq 5 -and (@($Mock.Calls | Where-Object { $_.Method -eq 'POST' -and $_.Uri -eq "$TCR/v2/article" })[0].Body -like '*"datePublished": *"2099-12-31T00:00:00Z"*') -and $pb.subject -like '`[Draft`]*' -and $pb.author -eq 'AutomationAI draft (ticket 1001)' -and $pb.isFrontPage -eq $false) "$($r.error) $($r.out.message) $($pb | ConvertTo-Json -Compress)"
$note = @($TC.notes | Where-Object { $_.internalAnalysisFlag })
Check 'confirm: internal note names the article and why clients cannot see it' ($note.Count -eq 1 -and $note[0].text -like '*article 812*dated 2099-12-31*' -and $r.out.counts.draftsSaved -eq 1) "$($note | ConvertTo-Json -Compress)"

# 6. Rerun: the ticket's note marker stops a second draft.
$Mock.Calls.Clear()
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai)
Check 'rerun: already drafted, nothing written' ($r.out.status -eq 'success' -and $r.out.message -like '*already made*' -and -not (Get-TWrites).Count) "$($r.error) $($r.out.message) $(Show-Calls)"

# 7. A draft already in CloudRadial (the note failed last time): not saved again, the note is added.
Reset-TCw; $TC.prior = @([pscustomobject]@{ articleId = 700; subject = '[Draft] Printer shows offline'; author = 'AutomationAI draft (ticket 1001)' })
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai)
$artGet = @($Mock.Calls | Where-Object { $_.Uri -like "$TCR/v2/odata/article*" } | ForEach-Object { [uri]::UnescapeDataString($_.Uri) })
Check 'existing draft: found by author, not saved again, note added' ($r.out.status -eq 'success' -and -not $TC.posted.Count -and @($TC.notes | Where-Object { $_.text -like '*article 700*' }).Count -eq 1 -and $artGet[0] -like "*companyId eq 5 and author eq 'AutomationAI draft (ticket 1001)'*") "$($r.out.message) $($artGet -join ' ')"

# 8. Not worth an article: nothing saved; with confirm, the ticket says why.
Reset-TCw
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai -Worth $false)
Check 'not worth publishing: success, nothing saved, ticket noted' ($r.out.status -eq 'success' -and -not $TC.posted.Count -and @($TC.notes | Where-Object { $_.text -like '*No knowledge base draft*' }).Count -eq 1) "$($r.out.message)"

# 9. Too little to write from, an unreadable AI answer, the resolutionNotes input.
Reset-TCw -Res 'Fixed.'
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai)
Check 'too little resolution text: incomplete, nothing read further' ($r.stage -eq 'gather' -and $r.out.status -eq 'incomplete' -and $r.out.message -like '*too little resolution text*') $r.out.message
Reset-TCw
$r = Invoke-Flow ($TBody + @{ confirm = $true }) 'Sorry, I cannot.'
Check 'unreadable AI answer: incomplete, nothing saved' ($r.out.status -eq 'incomplete' -and -not $TC.posted.Count) $r.out.message
Reset-TCw
$r = Invoke-Flow ($TBody + @{ resolutionNotes = 'Outlook kept prompting for a password because the cached credential was stale. Removed it from Credential Manager and signed in again.' }) (Ai)
Check 'resolutionNotes input used first' ([string]$r.facts.resolution -like 'Outlook kept prompting*' -and (@($r.ctx.actions) -join ' ') -like '*resolutionNotes input*') $r.facts.resolution
$r = Invoke-Flow @{ confirm = $true } (Ai)
Check 'no ticketId: incomplete' ($r.stage -eq 'gather' -and $r.out.status -eq 'incomplete') $r.out.message

# ---- Autotask: the ticket's resolution field, and the contact read for scrubbing ----
$TAT = 'https://webservices5.autotask.example/atservicesrest/v1.0'
$TAtRouter = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    if ($c.Method -eq 'GET' -and $u -eq "$TAT/Tickets/1001") { return [pscustomobject]@{ item = [pscustomobject]@{ id = 1001; ticketNumber = 'T20261014.0001'; title = 'VPN drops'; description = 'Sam says the VPN drops.'; companyID = 42; contactID = 5; priority = 2; status = 5; resolution = 'Sam Lee at Fabrikam had an old VPN client. Updated the client to the current version and reset the saved profile, and the drops stopped.' } } }
    if ($u -like "$TAT/Contacts/5*") { return [pscustomobject]@{ item = [pscustomobject]@{ id = 5; firstName = 'Sam'; lastName = 'Lee'; emailAddress = 'sam.lee@fabrikam.example' } } }
    if ($u -like "$TAT/Companies/42*") { return [pscustomobject]@{ item = [pscustomobject]@{ id = 42; companyName = 'Fabrikam' } } }
    if ($u -eq "$TAT/Tickets/entityInformation/fields") { return [pscustomobject]@{ fields = @([pscustomobject]@{ name = 'status'; picklistValues = @([pscustomobject]@{ value = '5'; label = 'Complete'; isActive = $true }) }, [pscustomobject]@{ name = 'priority'; picklistValues = @([pscustomobject]@{ value = '2'; label = 'Medium'; isActive = $true }) }) } }
    return [pscustomobject]@{ items = @(); pageDetails = [pscustomobject]@{ nextPageUrl = $null } }
}
Reset-Mock @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices5.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' } $TAtRouter
$r = Invoke-Flow $TBody (Ai)
Check 'autotask: resolution field used, contact and company scrubbed' ($r.out.status -eq 'pending_confirmation' -and [string]$r.facts.resolution -like 'the user at the company had an old VPN client*' -and (@($r.ctx.actions) -join ' ') -like "*ticket's resolution field*") "$($r.error) $($r.facts.resolution)"

Complete-Test
