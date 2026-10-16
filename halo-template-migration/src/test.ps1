# Strict-mode harness for Move HaloPSA Ticket Templates into CloudRadial Request Forms.
# Runs both PowerShell steps exactly as they are in halo-template-migration.yml (shared psa.ps1 and
# cloudradial.ps1 included), through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest,
# with the runner Key Vault, Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked. The AI Prompt step
# is simulated by handing the create step a judgment string.
# Placeholder data only (Contoso, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a step variable of the same
# name would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File halo-template-migration/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\halo-template-migration.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.properties&&a.properties.script)o[a.id]=a.properties.script;if(a.type==='ai-prompt'){o['judge.prompt']=a.properties.promptTemplate;o['judge.model']=a.properties.model;o['judge.system']=a.properties.systemMessage}if(a.id==='create')o['create.params']=JSON.stringify(a.properties.parameters)}o.webhook=String(d.definition.activities[0].properties.webhookEnabled);console.log(JSON.stringify(o))"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow has read, judge and create' ($Steps.Contains('read') -and $Steps.Contains('create') -and $Steps.Contains('judge.prompt'))
Check 'judge prompt reads the read facts, model blank' ($Steps['judge.prompt'] -like '*{{ nodes.read.output.facts_json }}*' -and $Steps['judge.model'] -eq '')
Check 'create is bound to read and judge' ($Steps['create.params'] -like '*nodes.read.output.plan_json*' -and $Steps['create.params'] -like '*nodes.judge.output.judgment*' -and $Steps['create.params'] -like '*nodes.read.output.skipped_json*')
Check 'webhook ships disabled' ($Steps['webhook'] -eq 'false')
Check 'shared libraries pasted' ($Steps['read'] -like '*function Connect-Psa*' -and $Steps['read'] -like '*function Connect-Cr*' -and $Steps['create'] -like '*function Invoke-CrApi*')

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
# read -> (AI text) -> create, the way the bindings wire them.
function Invoke-Flow {
    param($Body, [string]$Ai)
    $g = Invoke-Step 'read' ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    if ($g.error) { return @{ stage = 'read'; r = $g; out = $g.out } }
    $o = $g.out
    $c = Invoke-Step 'create' $null @{ request = $o.request_json; plan = $o.plan_json; skipped = $o.skipped_json; remaining = [string]$o.remaining; warnings_json = $o.warnings_json; actions_json = $o.actions_json; judgment = $Ai }
    return @{ stage = 'create'; r = $c; out = $c.out; read = $o }
}

# ---- placeholder HaloPSA and CloudRadial ----
$THalo = 'https://halo.example.com'
$TCr = 'https://api.example.com'
$TSecrets = @{ 'Halo-ApiUrl' = $THalo; 'Halo-ClientId' = 'cid'; 'Halo-ClientSecret' = 'csecret'; 'CloudRadial-BaseUrl' = $TCr; 'CloudRadial-PublicKey' = 'pub'; 'CloudRadial-PrivateKey' = 'priv' }
$TH = @{ existing = @(); listFail = ''; postFail = ''; posts = (New-Object System.Collections.ArrayList) }
$TTemplates = @(
    @{ id = 12; name = 'New starter setup' }, @{ id = 15; name = 'Printer not working' },
    @{ id = 20; name = 'Old VPN request'; disabled = $true }, @{ id = 21; name = 'Laptop request' }
)
$TDetail = @{
    '12' = @{ id = 12; name = 'New starter setup'; tickettype_id = 3; priority_id = 4; status_id = 1; team = 'Service Desk'; category_1 = 'Accounts'; summary = 'New starter for Contoso'; details = '<p>Set up a new starter.</p><script>alert(1)</script><a href="javascript:void(0)" onclick="x()">link</a>'; customfields = @(@{ id = 103; name = 'CFCostCentre'; value = 'FIN-01' }) }
    '15' = @{ id = 15; name = 'Printer not working'; tickettype_id = 1; priority_id = 2; summary = 'Printer fault'; details = '' }
    '21' = @{ id = 21; name = 'Laptop request'; tickettype_id = 3 }
}
$TTypes = @{
    # Halo's real shape (verified 2026-10-16): link rows with no name, label or type; those are in /Field/{fieldid}.
    '3' = @{ id = 3; name = 'Service Request'; fields = @(
            @{ id = 9001; rtid = 3; fieldid = 101; seq = 1; endusernew = 2; technew = 1 },
            @{ id = 9002; rtid = 3; fieldid = 102; seq = 2; endusernew = 1; technew = 1 },
            @{ id = 9003; rtid = 3; fieldid = 103; seq = 3; endusernew = 1; technew = 1 },
            @{ id = 9004; rtid = 3; fieldid = 104; seq = 4; endusernew = 1; technew = 1 },
            @{ id = 9005; rtid = 3; fieldid = 1; seq = 5; endusernew = 1; technew = 1 },
            @{ id = 9006; rtid = 3; fieldid = 105; seq = 6; endusernew = 1; technew = 1 },
            @{ id = 9007; rtid = 3; fieldid = 106; seq = 7; endusernew = 0; technew = 1 }) }
    # A field-group row (fieldid 0, groupid 14), as Halo sends it; the group lists the fields.
    '1' = @{ id = 1; name = 'Incident'; fields = @(
            @{ id = 9101; rtid = 1; fieldid = 0; groupid = 14; seq = 1; endusernew = 1; technew = 1 }) }
}
$TRouter = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    if ($c.Method -eq 'POST' -and $u -eq "$THalo/auth/token") { return [pscustomobject]@{ access_token = 'tok' } }
    if ($c.Method -eq 'GET' -and $u -match '/api/Template\?') {
        if ($TH.listFail -eq '403') { New-HttpError 403 '{"message":"Forbidden"}' }
        if ($TH.listFail -eq 'odd') { return [pscustomobject]@{ total = 1; ticket_templates = @([pscustomobject]@{ tid = 12; title = 'New starter setup' }) } }
        $rows = @($TTemplates | Where-Object { $u -notmatch 'search=' -or $_.name -like "*$(([regex]::Match($u, 'search=([^&]*)')).Groups[1].Value)*" })
        return ([pscustomobject]@{ page_no = 1; page_size = 50; record_count = $rows.Count; stdrequests = @($rows | ForEach-Object { [pscustomobject]$_ }) })
    }
    if ($c.Method -eq 'GET' -and $u -match "/api/Template/(\d+)\?") { return ($TDetail[$Matches[1]] | ConvertTo-Json -Depth 6 | ConvertFrom-Json) }
    if ($c.Method -eq 'GET' -and $u -match "/api/TicketType/(\d+)\?") { return ($TTypes[$Matches[1]] | ConvertTo-Json -Depth 6 | ConvertFrom-Json) }
    if ($c.Method -eq 'GET' -and $u -match "/api/FieldGroup/14\?") { return [pscustomobject]@{ id = 14; name = 'Printer details'; fields = @([pscustomobject]@{ id = 7001; fieldid = 201; seq = 1 }, [pscustomobject]@{ id = 7002; fieldid = 202; seq = 2 }) } }
    if ($c.Method -eq 'GET' -and $u -match "/api/Field/(\d+)\?") { New-HttpError 400 '"Field kind must be specified"' }
    if ($c.Method -eq 'GET' -and $u -match "/api/FieldInfo/(\d+)\?") {
        $TDefs = @{
            '1'   = @{ id = 1; name = 'summary'; label = 'Summary'; type = 0 }
            '101' = @{ id = 101; name = 'CFStartDate'; label = 'Start date'; type = 4 }
            '102' = @{ id = 102; name = 'CFLicence'; label = 'Licence'; type = 2; values = @(@{ name = 'Business Basic' }, @{ name = 'Business Premium, annual' }) }
            '103' = @{ id = 103; name = 'CFCostCentre'; label = 'Cost centre'; type = 0 }
            '104' = @{ id = 104; name = 'CFAssetTag'; label = 'Asset tag'; type = 0 }
            '105' = @{ id = 105; name = 'CFMystery'; label = 'Mystery'; type = 77 }
            '106' = @{ id = 106; name = 'CFInternalCode'; label = 'Internal code'; type = 0 }
            '201' = @{ id = 201; name = 'CFPrinterLocation'; label = 'Printer location'; type = 0 }
            '202' = @{ id = 202; name = 'CFDept'; type = 2; values = @(@{ name = 'Finance' }, @{ name = 'Sales' }) }
        }
        if ($TDefs.Contains($Matches[1])) { return ($TDefs[$Matches[1]] | ConvertTo-Json -Depth 5 | ConvertFrom-Json) }
        New-HttpError 404 '{"message":"Not found"}'
    }
    if ($c.Method -eq 'GET' -and $u -eq "$THalo/api/Priority") { return , @([pscustomobject]@{ priorityid = 2; name = 'High' }, [pscustomobject]@{ priorityid = 4; name = 'Low' }) }
    if ($c.Method -eq 'GET' -and $u -eq "$THalo/api/Status") { return , @([pscustomobject]@{ id = 1; name = 'New' }) }
    if ($c.Method -eq 'GET' -and $u -like "$TCr/v2/odata/company*") { if ($u -match 'companyId eq 1&') { return [pscustomobject]@{ value = @([pscustomobject]@{ companyId = 1; name = 'Example MSP' }) } }; return [pscustomobject]@{ value = @() } }
    if ($c.Method -eq 'GET' -and $u -like "$TCr/v2/odata/catalog*") { return [pscustomobject]@{ value = @($TH.existing) } }
    if ($c.Method -eq 'POST' -and $u -eq "$TCr/v2/catalog") {
        $b = Read-Body $c
        if ($TH.postFail -and $b.subject -eq $TH.postFail) { New-HttpError 500 '{"message":"Error creating catalog item"}' }
        $null = $TH.posts.Add($b)
        return [pscustomobject]@{ companyCatalogId = 500 + $TH.posts.Count; questions = @($b.questions) }
    }
    return $null
}
function Reset-T { $TH.existing = @([pscustomobject]@{ companyCatalogId = 77; subject = 'Laptop request'; tags = 'halo-template:21' }); $TH.listFail = ''; $TH.postFail = ''; $TH.posts.Clear(); Reset-Mock $TSecrets $TRouter }
function Get-THaloWrites { return , @($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and $_.Uri -like "$THalo*" -and $_.Uri -notlike '*/auth/token' }) }
function Get-TCrWrites { return , @($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and $_.Uri -like "$TCr*" }) }
function Get-TRow { param($Out, [int]$Id) return @($Out.forms | Where-Object { $_.templateId -eq $Id })[0] }
$TAi = (@{ forms = @(
            @{ key = 't12'; shortDescription = 'Ask us to set up a new starter.'; description = 'Tell us about the new starter.'; questions = @(@{ fieldId = '102'; label = 'Which licence?'; info = ''; required = $false }, @{ fieldId = '999'; label = 'Invented' }, @{ fieldId = '101'; label = 'First day'; info = 'Their first working day.'; required = $true }) },
            @{ key = 't15'; shortDescription = 'Tell us a printer is not working.'; description = 'Report a printer fault.'; questions = @(@{ fieldId = 201; label = 'Where is the printer?'; required = $false }) }) } | ConvertTo-Json -Depth 6 -Compress)
$TBody = @{ companyId = 1 }

# 1. Preview: plans two forms, skips the inactive and the already-moved template, writes nothing.
Reset-T
$r = Invoke-Flow $TBody $TAi
Check 'preview: pending, two planned, nothing written' ($r.out.status -eq 'pending_confirmation' -and $r.out.counts.formsPlanned -eq 2 -and -not (Get-TCrWrites).Count -and -not (Get-THaloWrites).Count) "$($r.r.error) $($r.out.message) $(Show-Calls)"
Check 'preview: inactive and already-moved templates skipped' ((Get-TRow $r.out 20).note -like '*Inactive*' -and (Get-TRow $r.out 21).note -like '*Already moved*' -and (Get-TRow $r.out 21).catalogId -eq 77) ($r.out.forms | ConvertTo-Json -Depth 4 -Compress)
Check 'preview: the planned questions are named' ((Get-TRow $r.out 12).note -like '*Which licence?*First day*Anything else*') ((Get-TRow $r.out 12).note)
$facts = $r.read.facts_json | ConvertFrom-Json
$f12 = @($facts.forms | Where-Object { $_.key -eq 't12' })[0]; $f15 = @($facts.forms | Where-Object { $_.key -eq 't15' })[0]
Check 'facts: custom fields only, the fixed and built-in ones left out' ((@($f12.fields | ForEach-Object { $_.id }) -join ',') -eq '101,102,104,105') (@($f12.fields | ForEach-Object { $_.id }) -join ',')
Check 'facts: kinds mapped, unknown type becomes text with a warning' ((@($f12.fields | ForEach-Object { $_.kind }) -join ',') -eq 'date,choice,text,text' -and [bool](@($r.out.warnings) -match 'Mystery')) (@($f12.fields | ForEach-Object { $_.kind }) -join ',')
Check 'facts: a comma inside an option becomes a space' ((@($f12.fields | Where-Object { $_.id -eq '102' })[0].options -join '|') -eq 'Business Basic|Business Premium annual') ''
Check 'facts: list values read from /Field when the type has none' ((@($f15.fields | Where-Object { $_.id -eq '202' })[0].options -join '|') -eq 'Finance|Sales') ''
Check 'facts: incident type becomes a problem report, details tags stripped' ($f15.kind -eq 'problem' -and $f12.kind -eq 'request' -and $f12.details -notlike '*<*' -and $f12.details -notlike '*alert*') "$($f15.kind) $($f12.details)"

# 2. Live: two forms created, PSA values from Halo, AI wording kept, invented field dropped.
Reset-T
$r = Invoke-Flow ($TBody + @{ confirm = $true }) $TAi
Check 'live: success, two created' ($r.out.status -eq 'success' -and $r.out.counts.formsCreated -eq 2 -and $TH.posts.Count -eq 2 -and (Get-TRow $r.out 12).catalogId -eq 501) "$($r.r.error) $($r.out.message)"
$b12 = @($TH.posts | Where-Object { $_.subject -eq 'New starter setup' })[0]; $b15 = @($TH.posts | Where-Object { $_.subject -eq 'Printer not working' })[0]
Check 'live: request form with Halo PSA values and the marker tag' ($b12.companyId -eq 1 -and $b12.catalogUsage -eq 10 -and $b12.psaType -eq 'Service Request' -and $b12.psaPriority -eq 'Low' -and $b12.psaBoard -eq 'Service Desk' -and $b12.psaCategory -eq 'Accounts' -and $b12.psaStatus -eq 'New' -and $b12.tags[0].tag -eq 'halo-template:12' -and $b12.category -eq 'Service Request') ($b12 | ConvertTo-Json -Depth 3 -Compress)
Check 'live: questions in the AI order with Halo types and options' ((@($b12.questions | ForEach-Object { "$($_.label)/$($_.type)/$($_.isRequired)" }) -join ';') -eq 'Which licence?/130/False;First day/40/True;Anything else we should know?/10/False' -and $b12.questions[0].options -eq 'Business Basic,Business Premium annual' -and $b12.questions[1].customFieldName -eq 'CFStartDate' -and $b12.questions[2].isDescription -eq $true) (@($b12.questions | ForEach-Object { "$($_.label)/$($_.type)/$($_.isRequired)" }) -join ';')
Check 'live: invented field dropped with a warning' ([bool](@($r.out.warnings) -match 'field 999')) ''
Check 'live: template HTML kept without script or handlers' ($b12.description -like '*Set up a new starter.*' -and $b12.description -notmatch '(?i)<script|onclick|javascript:') ($b12.description)
Check 'live: problem report with defaults where Halo had none' ($b15.catalogUsage -eq 0 -and $b15.selectText -eq 'REPORT' -and $b15.psaPriority -eq 'High' -and $b15.psaBoard -eq '@DefaultBoard' -and $b15.psaStatus -eq '@DefaultStatus' -and $b15.description -like '*Report a printer fault.*' -and @($b15.questions).Count -eq 2) ($b15 | ConvertTo-Json -Depth 3 -Compress)
Check 'live: never writes to Halo' (-not (Get-THaloWrites).Count) (Show-Calls)

# 3. No usable AI answer: every field is asked with Halo's labels.
Reset-T
$r = Invoke-Flow ($TBody + @{ confirm = $true; templateIds = @(12) }) 'Sorry, I cannot help with that.'
$b = $TH.posts[0]
Check 'no AI: Halo labels, every custom field asked' ($r.out.status -eq 'success' -and (@($b.questions | ForEach-Object { $_.label }) -join ';') -eq 'Start date;Licence;Asset tag;Mystery;Anything else we should know?' -and $b.shortDescription -eq 'New starter for Contoso' -and [bool](@($r.out.warnings) -match 'no usable answer')) "$($r.r.error) $(@($b.questions | ForEach-Object { $_.label }) -join ';')"

# 4. Rerun: everything already moved, nothing written.
Reset-T
$TH.existing = @([pscustomobject]@{ companyCatalogId = 501; subject = 'New starter setup'; tags = 'halo-template:12' }, [pscustomobject]@{ companyCatalogId = 502; subject = 'Printer not working'; tags = 'halo-template:15' }, [pscustomobject]@{ companyCatalogId = 77; subject = 'Laptop request'; tags = 'halo-template:21' })
$r = Invoke-Flow ($TBody + @{ confirm = $true }) '{"forms": []}'
Check 'rerun: nothing new, success, no writes' ($r.out.status -eq 'success' -and $r.out.message -like 'Nothing new*' -and -not (Get-TCrWrites).Count -and $r.read.facts_json -eq '{"skip": true}') "$($r.r.error) $($r.out.message)"

# 5. A form with the same name but no marker is left alone.
Reset-T
$TH.existing = @([pscustomobject]@{ companyCatalogId = 88; subject = 'Printer not working'; tags = '' })
$r = Invoke-Flow ($TBody + @{ confirm = $true }) $TAi
Check 'same name: skipped, the other created' ((Get-TRow $r.out 15).action -eq 'skipped' -and (Get-TRow $r.out 15).note -like '*already exists*' -and $TH.posts.Count -eq 2 -and @($TH.posts | Where-Object { $_.subject -eq 'Printer not working' }).Count -eq 0) "$($r.out.forms | ConvertTo-Json -Depth 3 -Compress)"

# 6. Batches: maxTemplates 1 moves one and says how many are left.
Reset-T
$r = Invoke-Flow ($TBody + @{ maxTemplates = 1 }) $TAi
Check 'batch: one planned, one remaining' ($r.out.counts.formsPlanned -eq 1 -and $r.out.remaining -eq 1 -and $r.out.message -like '*1 more template*run it again*') "$($r.out.message)"

# 7. templateIds picks one; a missing id is a warning; a bad id stops.
Reset-T
$r = Invoke-Flow ($TBody + @{ templateIds = '15, 99' }) $TAi
Check 'templateIds: only 15, missing 99 warned' ($r.out.counts.formsPlanned -eq 1 -and (Get-TRow $r.out 15).action -eq 'planned' -and [bool](@($r.out.warnings) -match 'template 99')) "$($r.out.message) $($r.out.warnings)"
Reset-T
$r = Invoke-Flow ($TBody + @{ templateIds = @('abc') }) $TAi
Check 'templateIds: a non-number stops before reading' ($r.stage -eq 'read' -and $r.out.status -eq 'incomplete' -and $r.out.message -like '*abc*' -and -not @($Mock.Calls).Count) "$($r.out.message)"

# 8. Input checks.
Reset-T
$r = Invoke-Flow @{ confirm = $true } $TAi
Check 'no companyId: incomplete, nothing read' ($r.out.status -eq 'incomplete' -and $r.out.message -like '*companyId is missing*' -and -not @($Mock.Calls).Count) "$($r.out.message)"
Reset-T
$r = Invoke-Flow @{ companyId = 99 } $TAi
Check 'unknown company: incomplete, Halo not read' ($r.out.status -eq 'incomplete' -and $r.out.message -like '*no company 99*' -and -not @($Mock.Calls | Where-Object { $_.Uri -like "$THalo*" }).Count) "$($r.out.message)"
Reset-T
$r = Invoke-Flow ($TBody + @{ usage = 'sometimes' }) $TAi
Check 'bad usage: incomplete' ($r.out.status -eq 'incomplete' -and $r.out.message -like '*usage must be*') "$($r.out.message)"
Reset-T
$r = Invoke-Flow ($TBody + @{ usage = 'request' }) $TAi
Check 'usage request: the incident template becomes a request' (@(($r.read.plan_json | ConvertFrom-Json) | Where-Object { $_.templateId -eq 15 })[0].usage -eq 'request') ''

# 9. One create fails: the other is created and the run says so.
Reset-T
$TH.postFail = 'Printer not working'
$r = Invoke-Flow ($TBody + @{ confirm = $true }) $TAi
Check 'one fails: incomplete, error row, other created' ($r.out.status -eq 'incomplete' -and (Get-TRow $r.out 15).action -eq 'error' -and (Get-TRow $r.out 12).action -eq 'created' -and $r.out.counts.formsFailed -eq 1) "$($r.out.status) $($r.out.message)"

# 10. Halo refuses the template list: a plain error naming the permission.
Reset-T
$TH.listFail = '403'
$r = Invoke-Flow $TBody $TAi
Check 'halo 403: error with the permission to grant, nothing created' ($r.stage -eq 'read' -and $r.out.status -eq 'error' -and $r.out.message -like '*refused to read the ticket templates*' -and -not (Get-TCrWrites).Count) "$($r.out.message)"

# 11. A template list in an unknown shape stops and names what Halo sent, instead of "nothing new".
Reset-T
$TH.listFail = 'odd'
$r = Invoke-Flow $TBody $TAi
Check 'unknown list shape: incomplete, names the properties, nothing created' ($r.stage -eq 'read' -and $r.out.status -eq 'incomplete' -and $r.out.message -like '*total, ticket_templates*' -and -not (Get-TCrWrites).Count) "$($r.out.status) $($r.out.message)"

# 12. Missing secrets stop cleanly.
Reset-Mock @{ 'CloudRadial-BaseUrl' = $TCr; 'CloudRadial-PublicKey' = 'pub'; 'CloudRadial-PrivateKey' = 'priv' } $TRouter
$TH.existing = @()
$r = Invoke-Flow $TBody $TAi
Check 'no Halo secrets: error naming them' ($r.out.status -eq 'error' -and $r.out.message -like '*Halo-ApiUrl*') "$($r.out.message)"

Complete-Test
