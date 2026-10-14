# Strict-mode harness for Auto-Categorize New Ticket.
# Runs each PowerShell step exactly as it is in auto-categorize-ticket.yml (shared psa.ps1 and
# src/psa-categories.ps1 included), through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest,
# with the runner Key Vault, Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked. The AI Prompt step
# is simulated by handing the write step a judgment string.
# Placeholder data only (Contoso, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a step variable of the same
# name would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File auto-categorize-ticket/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\auto-categorize-ticket.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.properties&&a.properties.script)o[a.id]=a.properties.script;if(a.type==='ai-prompt'){o['judge.prompt']=a.properties.promptTemplate;o['judge.model']=a.properties.model;o['judge.system']=a.properties.systemMessage}if(a.id==='write')o['write.params']=JSON.stringify(a.properties.parameters)}o.webhook=String(d.definition.activities[0].properties.webhookEnabled);console.log(JSON.stringify(o))"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow has gather, judge and write' ($Steps.Contains('gather') -and $Steps.Contains('write') -and $Steps.Contains('judge.prompt'))
Check 'judge prompt reads the gather facts, model blank' ($Steps['judge.prompt'] -like '*{{ nodes.gather.output.facts_json }}*' -and $Steps['judge.model'] -eq '')
Check 'write is bound to gather and judge' ($Steps['write.params'] -like '*nodes.gather.output.state_json*' -and $Steps['write.params'] -like '*nodes.judge.output.judgment*')
Check 'webhook ships disabled' ($Steps['webhook'] -eq 'false')
Check 'shared psa.ps1 and psa-categories.ps1 pasted into both steps' ($Steps['gather'] -like '*function Invoke-Psa*' -and $Steps['gather'] -like '*function Get-PsaCategoryState*' -and $Steps['write'] -like '*function Set-PsaCategory*' -and $Steps['write'] -notlike '*# @@ src/psa-categories.ps1 @@*')

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
# gather -> (AI text) -> write, the way the bindings wire them.
function Invoke-Flow {
    param($Body, [string]$Ai)
    $g = Invoke-Step 'gather' ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    if ($g.error) { return @{ stage = 'gather'; r = $g; out = $g.out } }
    $o = $g.out
    $w = Invoke-Step 'write' $null @{ request = $o.request_json; state = $o.state_json; warnings_json = $o.warnings_json; actions_json = $o.actions_json; judgment = $Ai }
    return @{ stage = 'write'; r = $w; out = $w.out; gather = $o }
}
function Ai { param([string[]]$Picks, [double]$Conf = 0.9) return (@{ picks = @($Picks); confidence = $Conf; reason = 'The user reports the floor 2 printer is offline.' } | ConvertTo-Json -Compress) }

# ---- placeholder ConnectWise: one ticket on board 1, its notes, and the board's combinations ----
$TCW = 'https://api-na.example.com/v4_6_release/apis/3.0'
$TCwSecrets = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = $TCW; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
$TC = @{ type = $null; subType = $null; item = $null; notes = (New-Object System.Collections.ArrayList); assoc = 'ok' }
function Reset-TCw { param($Type = $null, $SubType = $null, $Item = $null, [string]$Assoc = 'ok') $TC.type = $Type; $TC.subType = $SubType; $TC.item = $Item; $TC.notes.Clear(); $TC.assoc = $Assoc; Reset-Mock $TCwSecrets $TCwRouter }
$TCwAssoc = @(
    @{ type = @{ id = 10; name = 'Hardware' }; subType = @{ id = 20; name = 'Printer' }; item = @{ id = 30; name = 'Offline' } },
    @{ type = @{ id = 10; name = 'Hardware' }; subType = @{ id = 20; name = 'Printer' }; item = @{ id = 31; name = 'Paper jam' } },
    @{ type = @{ id = 10; name = 'Hardware' }; subType = @{ id = 22; name = 'Laptop' } },
    @{ type = @{ id = 11; name = 'Software' }; subType = @{ id = 21; name = 'Email' } }
)
$TCwRouter = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    if ($c.Method -eq 'GET' -and $u -match '/service/tickets/1001$') { return [pscustomobject]@{ id = 1001; summary = 'Floor 2 printer offline'; board = [pscustomobject]@{ id = 1; name = 'Service Desk' }; company = [pscustomobject]@{ id = 42 }; type = $TC.type; subType = $TC.subType; item = $TC.item; status = [pscustomobject]@{ name = 'New' } } }
    if ($c.Method -eq 'GET' -and $u -like '*/service/tickets/1001/notes*') { return , (@([pscustomobject]@{ id = 0; text = 'The printer on floor 2 shows offline for everyone.' }) + @(@($TC.notes) | ForEach-Object { [pscustomobject]@{ id = 1; text = $_; internalAnalysisFlag = $true } })) }
    if ($c.Method -eq 'POST' -and $u -like '*/service/tickets/1001/notes') { $null = $TC.notes.Add((Read-Body $c).text); return [pscustomobject]@{ id = 900 } }
    if ($c.Method -eq 'GET' -and $u -like '*/service/boards/1/typeSubTypeItemAssociations*') {
        if ($TC.assoc -eq '403') { New-HttpError 403 '{"code":"Unauthorized","message":"Security"}' }
        if ($TC.assoc -eq '404') { New-HttpError 404 '{"code":"NotFound"}' }
        return , @($TCwAssoc | ForEach-Object { $_ | ConvertTo-Json -Depth 4 | ConvertFrom-Json })
    }
    if ($c.Method -eq 'GET' -and $u -like '*/service/boards/1/types*') { return , @([pscustomobject]@{ id = 10; name = 'Hardware' }, [pscustomobject]@{ id = 11; name = 'Software' }) }
    if ($c.Method -eq 'GET' -and $u -like '*/service/boards/1/subtypes*') { return , @([pscustomobject]@{ id = 20; name = 'Printer'; typeAssociationIds = @(10) }, [pscustomobject]@{ id = 21; name = 'Email'; typeAssociationIds = @(11) }) }
    if ($c.Method -eq 'GET' -and $u -like '*/service/boards/1/items*') { return , @([pscustomobject]@{ id = 30; name = 'Offline' }) }
    if ($c.Method -eq 'PATCH' -and $u -like '*/service/tickets/1001') {
        foreach ($op in @(Read-Body $c)) { $v = [pscustomobject]@{ id = $op.value.id; name = @{ 10 = 'Hardware'; 11 = 'Software'; 20 = 'Printer'; 21 = 'Email'; 22 = 'Laptop'; 30 = 'Offline'; 31 = 'Paper jam' }[[int]$op.value.id] }; $TC[$op.path] = $v }
        return [pscustomobject]@{ id = 1001 }
    }
    return $null
}
function Get-TPatch { return , @($Mock.Calls | Where-Object { $_.Method -eq 'PATCH' }) }
function Get-TNotePosts { return , @($Mock.Calls | Where-Object { $_.Method -eq 'POST' -and $_.Uri -like '*/notes' }) }
function Get-TWrites { return , @($Mock.Calls | Where-Object { $_.Method -ne 'GET' }) }
$TBody = @{ ticketId = '1001' }

# 1. Preview: the AI's pick is shown and nothing is written.
Reset-TCw
$r = Invoke-Flow $TBody (Ai @('Hardware', 'Printer', 'Offline'))
Check 'cw preview: pending, names the pick, writes nothing' ($r.out.status -eq 'pending_confirmation' -and $r.out.message -like '*Would set*Hardware*Printer*Offline*' -and -not (Get-TWrites).Count) "$($r.r.error) $($r.out.message) $(Show-Calls)"
$facts = $r.gather.facts_json | ConvertFrom-Json
Check 'cw facts: three open levels, only the board''s values, ticket text included' (($facts.choose -join ',') -eq 'type,subtype,item' -and $facts.options.Count -eq 2 -and $facts.ticket.summary -eq 'Floor 2 printer offline' -and $facts.ticket.description -like '*shows offline*') ($r.gather.facts_json)

# 2. Confirmed and sure: all three blank fields set by id, and one internal note.
Reset-TCw
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai @('Hardware', 'Printer', 'Offline'))
$ops = @(Get-TPatch | ForEach-Object { @(Read-Body $_) })
Check 'cw confirm: success, three fields set' ($r.out.status -eq 'success' -and $r.out.counts.fieldsSet -eq 3) "$($r.r.error) $($r.out.message)"
Check 'cw confirm: one PATCH with type, subType and item ids' ((Get-TPatch).Count -eq 1 -and (($ops | ForEach-Object { "$($_.path)=$($_.value.id)" }) -join ',') -eq 'type=10,subType=20,item=30') (($ops | ConvertTo-Json -Compress -Depth 4))
Check 'cw confirm: internal note with the reasoning' ((Get-TNotePosts).Count -eq 1 -and (Read-Body (Get-TNotePosts)[0]).internalAnalysisFlag -eq $true -and (Read-Body (Get-TNotePosts)[0]).text -like '*Auto-categorized ticket 1001*confidence 0.90*Reason:*') ((Read-Body (Get-TNotePosts)[0]).text)

# 3. Rerun once categorized: nothing open, nothing written.
$Mock.Calls.Clear()
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai @('Software', 'Email'))
Check 'cw rerun: already categorized, nothing written' ($r.out.status -eq 'success' -and $r.out.message -like '*already has*' -and -not (Get-TWrites).Count) "$($r.out.message) $(Show-Calls)"

# 4. Low confidence: no field changes, the suggestion goes in a note.
Reset-TCw
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai @('Hardware', 'Printer') 0.4)
Check 'cw low confidence: no PATCH, suggestion noted' ($r.out.status -eq 'incomplete' -and -not (Get-TPatch).Count -and (Get-TNotePosts).Count -eq 1 -and (Read-Body (Get-TNotePosts)[0]).text -like '*Suggested category*below 0.70*') "$($r.out.message) $(Show-Calls)"
$Mock.Calls.Clear()
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai @('Hardware', 'Printer') 0.4)
Check 'cw low confidence rerun: the note is not added twice' (-not (Get-TNotePosts).Count -and (@($r.out.actions) -join ' ') -like '*already on ticket 1001*') (@($r.out.actions) -join ' | ')

# 5. An invented category is dropped; a child from the wrong parent stops the walk there.
Reset-TCw
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai @('Network', 'Firewall'))
Check 'cw invented value: nothing chosen, nothing written' ($r.out.status -eq 'incomplete' -and -not (Get-TWrites).Count -and (@($r.out.warnings) -join ' ') -like "*'Network'*isn't in the list*") "$($r.out.message) $(@($r.out.warnings) -join ' | ')"
Reset-TCw
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai @('Hardware', 'Email'))
$ops = @(Get-TPatch | ForEach-Object { @(Read-Body $_) })
Check 'cw wrong parent: only the type is set' ($r.out.status -eq 'success' -and (($ops | ForEach-Object { $_.path }) -join ',') -eq 'type' -and (@($r.out.warnings) -join ' ') -like "*'Email'*") "$(($ops | ConvertTo-Json -Compress -Depth 4)) $(@($r.out.warnings) -join ' | ')"

# 6. A technician already set the type: only the blank subtype and item are open, and the type is never sent.
Reset-TCw -Type ([pscustomobject]@{ id = 10; name = 'Hardware' })
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai @('Printer', 'Offline'))
$ops = @(Get-TPatch | ForEach-Object { @(Read-Body $_) })
$facts = $r.gather.facts_json | ConvertFrom-Json
Check 'cw type set: AI chooses subtype and item under Hardware only' (($facts.choose -join ',') -eq 'subtype,item' -and $facts.fixed.type -eq 'Hardware' -and ((@($facts.options) | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } }) -join ',') -eq 'Printer,Laptop') ($r.gather.facts_json)
Check 'cw type set: PATCH sets subType and item, never type' ((($ops | ForEach-Object { $_.path }) -join ',') -eq 'subType,item') (($ops | ConvertTo-Json -Compress -Depth 4))
# "Unclassified" counts as blank; a set item below a blank subtype stays as it is.
Reset-TCw -Type ([pscustomobject]@{ id = 99; name = 'Unclassified' })
$r = Invoke-Flow $TBody (Ai @('Hardware'))
Check 'cw Unclassified type is open' ((($r.gather.facts_json | ConvertFrom-Json).choose -join ',') -eq 'type,subtype,item') ($r.gather.facts_json)
Reset-TCw -Type ([pscustomobject]@{ id = 10; name = 'Hardware' }) -Item ([pscustomobject]@{ id = 30; name = 'Offline' })
$r = Invoke-Flow $TBody (Ai @('Printer'))
Check 'cw item set below a blank subtype: only subtype open' ((($r.gather.facts_json | ConvertFrom-Json).choose -join ',') -eq 'subtype') ($r.gather.facts_json)

# 7. No combinations endpoint: the types, subtypes and items lists are used instead.
Reset-TCw -Assoc '404'
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai @('Software', 'Email'))
$ops = @(Get-TPatch | ForEach-Object { @(Read-Body $_) })
Check 'cw lists fallback: subtypes follow typeAssociationIds, ids set' ($r.out.status -eq 'success' -and (($ops | ForEach-Object { "$($_.path)=$($_.value.id)" }) -join ',') -eq 'type=11,subType=21') "$($r.r.error) $(($ops | ConvertTo-Json -Compress -Depth 4))"

# 8. A role that can't read board types: stops with a plain sentence, nothing written.
Reset-TCw -Assoc '403'
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai @('Hardware'))
Check 'cw 403: stops before the AI, says which permission' ($r.stage -eq 'gather' -and $r.out.status -eq 'incomplete' -and $r.out.message -like '*HTTP 403*permission to read service board types*' -and -not (Get-TWrites).Count) "$($r.out.message)"

# 9. Bad input fails closed.
Reset-TCw
$r = Invoke-Flow @{ confirm = $true } (Ai @('Hardware'))
Check 'no ticketId: incomplete, nothing read' ($r.stage -eq 'gather' -and $r.out.status -eq 'incomplete' -and $r.out.message -like 'ticketId is missing*' -and -not $Mock.Calls.Count) $r.out.message
$r = Invoke-Flow ($TBody + @{ minConfidence = '2' }) (Ai @('Hardware'))
Check 'bad minConfidence: incomplete' ($r.out.status -eq 'incomplete' -and $r.out.message -like 'minConfidence must be*') $r.out.message
# The CloudRadial shape and an unreadable AI answer.
$r = Invoke-Flow @{ Ticket = @{ TicketId = '1001'; Questions = @() } } 'Sorry, I cannot help with that.'
Check 'CloudRadial shape read; unreadable AI answer chooses nothing' ($r.out.status -eq 'incomplete' -and (@($r.out.warnings) -join ' ') -like '*no readable answer*') "$($r.r.error) $($r.out.message)"

# ---- Autotask: issue type > sub-issue type from the picklists ----
$TAT = 'https://webservices5.autotask.example/atservicesrest/v1.0'
$TA = @{ issue = $null; sub = $null }
$TAtRouter = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    if ($c.Method -eq 'GET' -and $u -eq "$TAT/Tickets/1001") { return [pscustomobject]@{ item = [pscustomobject]@{ id = 1001; title = 'Floor 2 printer offline'; description = 'Shows offline.'; companyID = 42; issueType = $TA.issue; subIssueType = $TA.sub; status = 1 } } }
    if ($u -eq "$TAT/Tickets/entityInformation/fields") { return [pscustomobject]@{ fields = @(
                [pscustomobject]@{ name = 'issueType'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'Hardware'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Software'; isActive = $true }) },
                [pscustomobject]@{ name = 'subIssueType'; picklistValues = @([pscustomobject]@{ value = '5'; label = 'Printer'; parentValue = '1'; isActive = $true }, [pscustomobject]@{ value = '6'; label = 'Email'; parentValue = '2'; isActive = $true }) }) } }
    if ($u -eq "$TAT/TicketNotes/entityInformation/fields") { return [pscustomobject]@{ fields = @(
                [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) } }
    if ($c.Method -eq 'PATCH' -and $u -eq "$TAT/Tickets") { $b = Read-Body $c; if ($b.PSObject.Properties['issueType']) { $TA.issue = $b.issueType }; if ($b.PSObject.Properties['subIssueType']) { $TA.sub = $b.subIssueType }; return [pscustomobject]@{ itemId = 1001 } }
    if ($c.Method -eq 'POST' -and $u -like "$TAT/Tickets/1001/Notes") { return [pscustomobject]@{ itemId = 77 } }
    return [pscustomobject]@{ items = @(); pageDetails = [pscustomobject]@{ nextPageUrl = $null } }
}
Reset-Mock @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices5.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' } $TAtRouter
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai @('Hardware', 'Printer'))
$p = @($Mock.Calls | Where-Object { $_.Method -eq 'PATCH' })
$pb = $(if ($p.Count) { Read-Body $p[0] } else { $null })
Check 'autotask: issue and sub-issue type set by picklist value' ($r.out.status -eq 'success' -and $p.Count -eq 1 -and $pb.id -eq 1001 -and $pb.issueType -eq 1 -and $pb.subIssueType -eq 5) "$($r.r.error) $($r.out.message) $(Show-Calls)"
Check 'autotask: internal note added' (@($Mock.Calls | Where-Object { $_.Method -eq 'POST' -and $_.Uri -like '*/Tickets/1001/Notes' }).Count -eq 1) (Show-Calls)
$TA.issue = 1; $TA.sub = $null; $Mock.Calls.Clear()
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai @('Printer'))
$pb = Read-Body @($Mock.Calls | Where-Object { $_.Method -eq 'PATCH' })[0]
Check 'autotask: issue type set by a technician is kept, sub-issue filled' ($r.out.status -eq 'success' -and -not $pb.PSObject.Properties['issueType'] -and $pb.subIssueType -eq 5) "$($r.out.message) $(Show-Calls)"

# ---- Zendesk: the fixed type list ----
$TZdUrl = 'https://example.zendesk.com/api/v2'
$TZ = @{ type = $null }
$TZdRouter = {
    param($c, $n)
    if ($c.Method -eq 'GET' -and $c.Uri -eq "$TZdUrl/tickets/1001") { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1001; subject = 'Floor 2 printer offline'; description = 'Shows offline.'; organization_id = 42; type = $TZ.type; status = 'new' } } }
    if ($c.Method -eq 'PUT' -and $c.Uri -eq "$TZdUrl/tickets/1001") { $b = Read-Body $c; if ($b.ticket.PSObject.Properties['type']) { $TZ.type = $b.ticket.type }; return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1001 } } }
    if ($c.Method -eq 'GET' -and $c.Uri -like "$TZdUrl/tickets/1001/comments*") { return [pscustomobject]@{ comments = @(); next_page = $null } }
    return $null
}
Reset-Mock @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' } $TZdRouter
$r = Invoke-Flow ($TBody + @{ confirm = $true }) (Ai @('incident'))
$puts = @($Mock.Calls | Where-Object { $_.Method -eq 'PUT' })
Check 'zendesk: type set to incident, then an internal comment' ($r.out.status -eq 'success' -and $TZ.type -eq 'incident' -and $puts.Count -eq 2 -and (Read-Body $puts[1]).ticket.comment.public -eq $false) "$($r.r.error) $($r.out.message) $(Show-Calls)"
$r = Invoke-Flow $TBody (Ai @('incident'))
Check 'zendesk: a type already set is left alone' ($r.out.status -eq 'success' -and $r.out.message -like '*already has*') $r.out.message

Complete-Test
