# Strict-mode harness for first-30-days-week-one.yml. Runs each step the way the runner does (a child scope via
# [scriptblock]::Create, never dot-sourced). Covers Read the client, the hand-offs into the reused steps
# (portal setup reads Read the client's output; the licence settings step reads bound parameters as text),
# and the Week-one summary. The reused steps have their own full harnesses in their folders.
# Usage: pwsh -NoProfile -File first-30-days/src/test.ps1   (needs js-yaml: NODE_PATH or JS_YAML_PATH)
param([string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fail = 0; $pass = 0
function Check { param($Name, [bool]$Ok, $Detail) if ($Ok) { Write-Host "PASS $Name"; $script:pass++ } else { Write-Host "FAIL $Name :: $Detail"; $script:fail++ } }

$yml = Join-Path $Root 'first-30-days/first-30-days-week-one.yml'
$js = "let y;try{y=require('js-yaml')}catch{y=require(process.env.JS_YAML_PATH)};const w=y.load(require('fs').readFileSync(process.argv[1],'utf8'));process.stdout.write(JSON.stringify(w))"
$Wf = (node -e $js $yml | Out-String) | ConvertFrom-Json
$Acts = @($Wf.definition.activities)
function Get-Act { param([string]$Id) return @($Acts | Where-Object { $_.id -eq $Id })[0] }
function Get-Script { param([string]$Id) return [string](Get-Act $Id).properties.script }

# ---- structure ----
Check 'order: plan, setup, score, licences, summary' ((@($Acts | ForEach-Object { $_.id }) -join ',') -eq 'start,node-plan,node-setup-inputs,node-portal,node-score,node-lr-inputs,node-lr-scan,node-lr-card,node-summary,end') (@($Acts | ForEach-Object { $_.id }) -join ',')
Check 'connections: one straight chain' (@($Wf.definition.connections).Count -eq 9 -and @($Wf.definition.connections)[3].source -eq 'node-portal' -and @($Wf.definition.connections)[3].target -eq 'node-score') ''
Check 'webhook ships off' ((Get-Act 'start').properties.webhookEnabled -eq $false) ''
Check 'first step unbound, with a test input' (@((Get-Act 'node-plan').properties.parameters).Count -eq 0 -and (Get-Act 'node-plan').properties.testInput -match 'Contoso Ltd') ''
Check 'portal setup step unbound (reads Read the client)' (@((Get-Act 'node-setup-inputs').properties.parameters).Count -eq 0) ''
Check 'no agent step: every step is PowerShell' (@($Acts | Where-Object { $_.type -notin @('start', 'end', 'powershell-script') }).Count -eq 0) ''
$pp = @((Get-Act 'node-portal').properties.parameters | ForEach-Object { "$($_.name)=$($_.expression)" }) -join ' '
Check 'portal parameters: Read the client and the checked setup' ($pp -eq 'plan={{ nodes.node-plan.output }} setup={{ nodes.node-setup-inputs.output }}') $pp
Check 'portal: shared CloudRadial and company blocks injected' ((Get-Script 'node-portal') -match 'function Invoke-CrApi' -and (Get-Script 'node-portal') -match 'function Select-RunCompany') ''
foreach ($id in @('node-portal', 'node-score', 'node-lr-scan', 'node-lr-card')) { Check "$($id): Include all companies" ((Get-Act $id).properties.includeAllCompanies -eq $true) '' }
$sp = @((Get-Act 'node-score').properties.parameters | ForEach-Object { "$($_.name)=$($_.expression)" }) -join ' '
Check 'score parameters: company, companyId, mode from Read the client' ($sp -eq 'company={{ nodes.node-plan.output.company }} companyId={{ nodes.node-plan.output.company_id }} mode={{ nodes.node-plan.output.scoreMode }}') $sp
foreach ($n in @('company', 'companyId', 'mode')) { Check "score step reads '$n'" ((Get-Script 'node-score') -match "Get-Prop \`$in '$n'") '' }
Check 'shared libraries injected' ((Get-Script 'node-score') -match 'function Select-RunCompany' -and (Get-Script 'node-lr-card') -match 'function Set-CrPlannerCard' -and (Get-Script 'node-lr-scan') -match 'function Connect-Graph') ''
Check 'reused steps carry no test input of their own' (@($Acts | Where-Object { $_.id -ne 'node-plan' -and $_.PSObject.Properties['properties'] -and $_.properties.PSObject.Properties['testInput'] }).Count -eq 0) ''

# ---- runner stand-ins ----
function Get-NodeInput { return $global:F3In }
function Set-NodeOutput { param($o) $global:F3Out = $o }
function Invoke-Step {
    param([string]$Id, $InputObject)
    $global:F3In = $InputObject; $global:F3Out = $null; $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + (Get-Script $Id))) } catch { $err = [string]$_.Exception.Message }
    $o = if ($null -ne $global:F3Out) { $global:F3Out | ConvertTo-Json -Depth 20 | ConvertFrom-Json } else { $null }
    return @{ out = $o; error = $err }
}
$good = [pscustomobject]@{
    company = 'Contoso Ltd'; company_id = 7; mode = 'live'; days = 45; client_visible = $true
    users = @([pscustomobject]@{ firstName = 'Pat'; lastName = 'Lee'; email = 'pat.lee@contoso.com' })
    tokens = @([pscustomobject]@{ token = 'SupportPhone'; value = '555-0100' })
    menuTiles = @([pscustomobject]@{ name = 'Remote Support'; url = 'https://support.examplemsp.com'; category = 'Help' })
}

# ---- Read the client ----
$r = Invoke-Step 'node-plan' $good
Check 'plan: ok, live' ($r.out.status -eq 'ok' -and $r.out.mode -eq 'live' -and $r.out.scoreMode -eq 'apply' -and $r.out.preview -eq $false -and -not $r.error) "$($r.error)"
Check 'plan: fields for the stages' ($r.out.company -eq 'Contoso Ltd' -and $r.out.company_id -eq 7 -and $r.out.days -eq 45 -and $r.out.client_visible -eq $true -and @($r.out.users).Count -eq 1 -and @($r.out.menuTiles).Count -eq 1) ($r.out | ConvertTo-Json -Compress -Depth 5)
Check 'plan: message names the company and live' ($r.out.message -match '^Ready for Contoso Ltd \(CloudRadial company 7\), live') $r.out.message
$planOut = $r.out

$r = Invoke-Step 'node-plan' ([pscustomobject]@{ company = 'Contoso Ltd'; company_id = '7'; users = $good.users })
Check 'plan: defaults are preview, 30 days, client visible' ($r.out.mode -eq 'preview' -and $r.out.scoreMode -eq 'plan' -and $r.out.preview -eq $true -and $r.out.days -eq 30 -and $r.out.client_visible -eq $true -and $r.out.company_id -eq 7) ($r.out | ConvertTo-Json -Compress)
Check 'plan: preview message says plan only' ($r.out.message -match 'plan only' -and $r.out.message -match 'preview only') $r.out.message

$r = Invoke-Step 'node-plan' ([pscustomobject]@{ trigger = ($good | ConvertTo-Json -Depth 5) })
Check 'plan: trigger wrapper holding JSON text' ($r.out.status -eq 'ok' -and $r.out.company_id -eq 7) $r.error

$r = Invoke-Step 'node-plan' ([pscustomobject]@{ mode = 'go'; days = 5; client_visible = 'maybe' })
Check 'plan: every problem listed at once' ($r.out.status -eq 'rejected' -and $r.error -match 'company is required' -and $r.error -match 'company_id is required' -and $r.error -match 'mode must be preview or live' -and $r.error -match 'days must be' -and $r.error -match 'client_visible must be' -and $r.error -match 'Portal setup needs') $r.error

$r = Invoke-Step 'node-plan' ([pscustomobject]@{ company = 'Contoso Ltd'; company_id = 'seven'; users = $good.users })
Check 'plan: company_id must be a number' ($r.error -match "company_id must be a CloudRadial company number") $r.error

$r = Invoke-Step 'node-plan' ([pscustomobject]@{ company = 'Contoso Ltd'; company_id = 7; companyName = 'Contoso'; accountManager = 'a@b.com'; users = $good.users })
Check 'plan: company fields refused (never creates or changes the company)' ($r.error -match 'companyName isn''t used' -and $r.error -match 'accountManager isn''t used') $r.error

$r = Invoke-Step 'node-plan' ([pscustomobject]@{ company = '@CompanyName'; company_id = 7; domain = '@Domain'; users = @() })
Check 'plan: unfilled @tokens and empty lists count as missing' ($r.error -match 'company is required' -and $r.error -match 'Portal setup needs') $r.error

$r = Invoke-Step 'node-plan' ([pscustomobject]@{ company = 'Contoso Ltd'; company_id = 7; client_visible = 'false'; domain = 'contoso.com' })
Check 'plan: client_visible false (text) and a domain alone' ($r.out.status -eq 'ok' -and $r.out.client_visible -eq $false -and $r.out.domain -eq 'contoso.com' -and $r.out.message -match '\(internal\)') $r.error

$r = Invoke-Step 'node-plan' ''
Check 'plan: empty input' ($r.error -match 'No run input') $r.error
$r = Invoke-Step 'node-plan' '{not json'
Check 'plan: bad JSON' ($r.error -match 'not valid JSON') $r.error

# ---- hand-off: portal setup reads Read the client's output ----
$r = Invoke-Step 'node-setup-inputs' $planOut
Check 'setup hand-off: accepted, adds to existing company 7' ($r.out.status -eq 'ok' -and $r.out.companyId -eq 7 -and $r.out.message -match 'existing company 7' -and -not $r.error) "$($r.error)"
Check 'setup hand-off: request carries the plan' ($r.out.request -match '"existingCompanyId":7' -and $r.out.request -match 'pat\.lee@contoso\.com' -and $r.out.request -match 'Remote Support' -and $r.out.request -notmatch '"days"') $r.out.request

# ---- hand-off: licence settings read bound parameters, which arrive as text ----
$r = Invoke-Step 'node-lr-inputs' ([pscustomobject]@{ company = 'Contoso Ltd'; company_id = '7'; days = '45'; preview = 'False'; client_visible = 'True' })
Check 'licence hand-off: text values read' ($r.out.status -eq 'ok' -and $r.out.company -eq 'Contoso Ltd' -and $r.out.company_id -eq 7 -and $r.out.days -eq 45 -and $r.out.preview -eq $false -and $r.out.client_visible -eq $true) "$($r.error) $($r.out | ConvertTo-Json -Compress)"
$r = Invoke-Step 'node-lr-inputs' ([pscustomobject]@{ company = 'Contoso Ltd'; company_id = 7; days = 30; preview = $true; client_visible = $false })
Check 'licence hand-off: typed values read' ($r.out.preview -eq $true -and $r.out.client_visible -eq $false -and $r.out.days -eq 30) "$($r.error)"

# ---- Week-one summary ----
$setupOk = [pscustomobject]@{ companyId = '7'; answer = 'Added 1 user, 1 token and 1 menu tile to Contoso Ltd.'; actions = @('Created user pat.lee@contoso.com', 'Created token SupportPhone', 'Created menu tile Remote Support'); skipped = @(); manualSteps = @('Show the new menu tile to Everyone.') }
$scoreOk = [pscustomobject]@{ status = 'created'; message = 'Created assessment'; assessmentId = 179; controls = 460; compliant = 25; tenantScore = '87.93 / 267' }
$cardOk = [pscustomobject]@{ status = 'success'; message = "2 paid licences held by 2 users have not been used in 30 days, worth an estimated `$12.00 a month."; cardAction = 'updated'; licenceCount = 2; monthlySaving = 12; clientVisible = $true }
$planLive = [pscustomobject]@{ company = 'Contoso Ltd'; company_id = 7; mode = 'live' }

$r = Invoke-Step 'node-summary' ([pscustomobject]@{ plan = $planLive; setup = $setupOk; score = $scoreOk; card = $cardOk })
Check 'summary live: success with a one-line headline' ($r.out.status -eq 'success' -and $r.out.message -eq 'Week one for Contoso Ltd is done: score 87.93 / 267, 2 unused licence(s) worth about $12.00 a month.') "$($r.error) $($r.out.message)"
Check 'summary live: actions from every stage' (@($r.out.actions).Count -eq 5 -and @($r.out.actions) -contains 'Added Secure Score assessment 179' -and @($r.out.actions) -contains 'Planner card updated') (@($r.out.actions) -join ' | ')
Check 'summary live: manual steps include the assessment Run click and the card review' (@($r.out.manualSteps) -match 'choose Run' -and @($r.out.manualSteps) -match 'Review the ' -and @($r.out.manualSteps) -contains 'Show the new menu tile to Everyone.') (@($r.out.manualSteps) -join ' | ')
Check 'summary live: one line per stage' ($r.out.summary -match '- Portal setup: 3 change\(s\)\.' -and $r.out.summary -match '- Security: Microsoft Secure Score 87\.93 / 267, added to the portal as assessment 179' -and $r.out.summary -match '- Licences: 2 paid licences') $r.out.summary
Check 'summary live: one bullet per setup change, the long answer kept out' ($r.out.summary -match '\n    - Created token SupportPhone' -and $r.out.summary -notmatch 'Added 1 user, 1 token' -and $r.out.setupAnswer -match '^Added 1 user') $r.out.summary

$r = Invoke-Step 'node-summary' ([pscustomobject]@{
        plan = ($planLive | ConvertTo-Json); setup = ($setupOk | ConvertTo-Json -Depth 5); score = ($scoreOk | ConvertTo-Json); card = ($cardOk | ConvertTo-Json) })
Check 'summary: stage outputs that arrive as JSON text' ($r.out.status -eq 'success' -and $r.out.secureScore -eq '87.93 / 267' -and $r.out.licenceCount -eq 2) "$($r.error) $($r.out.message)"

$r = Invoke-Step 'node-summary' ([pscustomobject]@{
        plan = [pscustomobject]@{ company = 'Contoso Ltd'; company_id = 7; mode = 'preview' }
        setup = [pscustomobject]@{ companyId = '7'; answer = 'Dry run: would add 1 user.'; actions = @('Skipped domain create because the plan left domain empty.', 'Would create user pat.lee@contoso.com'); manualSteps = @() }
        score = [pscustomobject]@{ status = 'plan'; message = 'DRY RUN'; controls = 460; compliant = 25; tenantScore = '87.93 / 267' }
        card = [pscustomobject]@{ status = 'pending_confirmation'; message = 'Preview only: nothing written.'; cardAction = 'would-update'; licenceCount = 2; monthlySaving = 12 } })
Check 'summary preview: pending_confirmation, previewed headline' ($r.out.status -eq 'pending_confirmation' -and $r.out.message -match '^Week one for Contoso Ltd, previewed' -and $r.out.summary -match 'Security \(preview\)' -and $r.out.summary -match 'Portal setup: 1 change\(s\) to make \(preview\), 1 already there\.' -and $r.out.summary -notmatch '    - Skipped' -and @($r.out.actions).Count -eq 1) "$($r.error) $($r.out.summary)"
Check 'summary preview: no Run click asked for' (-not (@($r.out.manualSteps) -match 'choose Run')) (@($r.out.manualSteps) -join ' | ')

$r = Invoke-Step 'node-summary' ([pscustomobject]@{ plan = $planLive; setup = [pscustomobject]@{ companyId = '9'; answer = 'x'; actions = @(); skipped = @('domain: already there'); manualSteps = @() }; score = [pscustomobject]@{ status = 'skipped'; message = 'exists'; tenantScore = '87.93 / 267' }; card = $null })
Check 'summary: missing card result and a company mismatch are flagged' ($r.out.status -eq 'incomplete' -and @($r.out.warnings) -match 'company 9' -and @($r.out.warnings) -match 'licence card' -and $r.out.message -match '2 thing\(s\) need a look') "$($r.error) $(@($r.out.warnings) -join ' | ')"
Check 'summary: skipped assessment explained' ($r.out.summary -match "already exists, so it wasn't added again" -and $r.out.summary -match '1 already there') $r.out.summary

$r = Invoke-Step 'node-summary' ([pscustomobject]@{ plan = $null; setup = $null; score = $null; card = $null })
Check 'summary: nothing at all still finishes' ($r.out.status -eq 'incomplete' -and -not $r.error -and $r.out.message -match 'the client') "$($r.error)"

# The agent step as it came back live (2026-11-09): {"result": "<sentence> {json with only an answer}"}.
$answer = "companyId: 1`nskipped company: existingCompanyId 1 was provided.`ncreated user: Pat Lee <pat.lee@contoso.com> for company 1.`ncreated token: SupportPhone for company 1.`nNo duplicate blocker was found."
$wrapped = [pscustomobject]@{ result = 'I will summarize the completed setup work. ' + ([pscustomobject]@{ answer = $answer; manualSteps = @('Invite the users.') } | ConvertTo-Json -Compress) }
$r = Invoke-Step 'node-summary' ([pscustomobject]@{ plan = [pscustomobject]@{ company = 'Fabrikam Services'; company_id = 1; mode = 'live' }; setup = $wrapped; score = $scoreOk; card = $cardOk })
Check 'summary: agent output wrapped in result is unwrapped' ($r.out.summary -match 'Portal setup: 2 change\(s\), 1 already there\.' -and $r.out.summary -match '    - created user: Pat Lee' -and @($r.out.manualSteps) -contains 'Invite the users.') $r.out.summary
Check 'summary: possessive for a name ending in s' (@(@($r.out.manualSteps) -match "open Fabrikam Services' Assessments").Count -eq 1) (@($r.out.manualSteps) -join ' | ')
$r = Invoke-Step 'node-summary' ([pscustomobject]@{ plan = $planLive; setup = [pscustomobject]@{ result = 'The agent stopped before finishing.' }; score = $scoreOk; card = $cardOk })
Check 'summary: result text with no JSON is kept as the answer' ($r.out.setupAnswer -eq 'The agent stopped before finishing.' -and $r.out.summary -match 'Portal setup: no changes') $r.out.summary

# ---- Add portal content (no AI), against a stand-in CloudRadial API ----
$global:companies = @([pscustomobject]@{ externalId = 'contoso'; name = 'Contoso Ltd'; aliases = @() })
function Set-DefaultCompany { param([string]$Company) $global:F3Co = $Company }
function Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) switch ($Name) { 'CloudRadial-BaseUrl' { 'https://api.example.test' } 'CloudRadial-PublicKey' { 'pub' } 'CloudRadial-PrivateKey' { 'priv' } default { $null } } }
function Start-Sleep { param($Seconds) }
function Reset-Cr {
    $global:Cr = @{
        posts               = New-Object System.Collections.ArrayList
        company             = @([pscustomobject]@{ companyId = 7; name = 'Contoso Ltd' })
        domain              = @([pscustomobject]@{ companyDomainId = 1; companyId = 3; name = 'taken.com'; isDefault = $true })
        companygroup        = @([pscustomobject]@{ companyGroupId = 4; group = 'Managed Clients' })
        companygroupcompany = @()
        user                = @([pscustomobject]@{ userId = 'u1'; companyId = 7; email = 'sam.roe@contoso.com' }, [pscustomobject]@{ userId = 'u2'; companyId = 3; email = 'alex.kim@contoso.com' })
        token               = @([pscustomobject]@{ companyId = 7; name = 'SupportPhone' })
        catalog             = @([pscustomobject]@{ companyCatalogId = 1; companyId = 7; subject = 'Request a new laptop' })
        menu                = @()
        failPost            = ''
        failMessage         = 'HTTP 400 Bad Request'
        refuseGroups        = $false
    }
}
function Invoke-RestMethod {
    param($Uri, $Method = 'GET', $Headers, $ContentType, $Body, $ErrorAction)
    $u = [uri]::UnescapeDataString([string]$Uri)
    if ($Method -eq 'POST') {
        $path = ([uri]$Uri).AbsolutePath
        $b = $Body | ConvertFrom-Json
        if ($global:Cr.failPost -and $path -eq $global:Cr.failPost) { throw $global:Cr.failMessage }
        if ($path -eq '/v2/menu' -and $global:Cr.refuseGroups -and $null -ne $b.PSObject.Properties['groups']) { throw 'HTTP 400 groups' }
        $null = $global:Cr.posts.Add([pscustomobject]@{ path = $path; body = $b })
        return [pscustomobject]@{ success = $true; data = $b }
    }
    if ($u -notmatch '/v2/odata/([a-z]+)\?(.*)$') { throw "unexpected GET $u" }
    $set = $Matches[1]; $q = $Matches[2]
    if ($q -match '\$skip=([1-9])') { return [pscustomobject]@{ value = @() } }
    $rows = @($global:Cr[$set])
    if ($q -match '\$filter=([^&]+)') {
        foreach ($c in ($Matches[1] -split ' and ')) {
            if ($c -match "^(\w+) eq '(.*)'$") { $f = $Matches[1]; $v = $Matches[2].Replace("''", "'"); $rows = @($rows | Where-Object { [string]$_.$f -ieq $v }) }
            elseif ($c -match '^(\w+) eq (\w+)$') { $f = $Matches[1]; $v = $Matches[2]; $rows = @($rows | Where-Object { $null -ne $_.PSObject.Properties[$f] -and [string]$_.$f -eq $v }) }
        }
    }
    return [pscustomobject]@{ value = @($rows) }
}

$checkOut = (Invoke-Step 'node-setup-inputs' ([pscustomobject]@{
            company = 'Contoso Ltd'; company_id = 7; domain = 'contoso.com'; companyGroup = 'Managed Clients'
            users = @([pscustomobject]@{ firstName = 'Pat'; lastName = 'Lee'; email = 'pat.lee@contoso.com' }, [pscustomobject]@{ firstName = 'Sam'; lastName = 'Roe'; email = 'sam.roe@contoso.com' }, [pscustomobject]@{ firstName = 'Alex'; lastName = 'Kim'; email = 'alex.kim@contoso.com' })
            tokens = @([pscustomobject]@{ token = 'SupportPhone'; value = '555-0199' }, [pscustomobject]@{ token = 'SupportEmail'; value = 'help@examplemsp.com' })
            requestForms = @([pscustomobject]@{ subject = 'Request a new laptop'; category = 'Hardware'; description = 'x' }, [pscustomobject]@{ subject = 'New starter'; category = 'People'; description = 'Who is starting and when.' })
            menuTiles = @([pscustomobject]@{ name = 'Remote Support'; url = 'https://support.examplemsp.com'; category = 'Help' })
        })).out
Check 'portal: the check step accepts the setup' ($checkOut.status -eq 'ok') ''
$planPreview = [pscustomobject]@{ company = 'Contoso Ltd'; company_id = 7; mode = 'preview' }

Reset-Cr
$r = Invoke-Step 'node-portal' ([pscustomobject]@{ plan = $planPreview; setup = $checkOut })
Check 'portal preview: nothing written' ($global:Cr.posts.Count -eq 0 -and $r.out.status -eq 'pending_confirmation' -and -not $r.error) "$($r.error) posts=$($global:Cr.posts.Count)"
Check 'portal preview: would-create list' (@($r.out.actions).Count -eq 6 -and @($r.out.actions | Where-Object { $_ -notmatch '^Would create ' }).Count -eq 0 -and $r.out.message -match '^Would add 6 record\(s\) to Contoso Ltd, 4 already there\. Preview') "$($r.out.message) | $(@($r.out.actions) -join ' | ')"
Check 'portal: switched to the run''s company secrets' ($global:F3Co -eq 'contoso') "$global:F3Co"
$sumR = Invoke-Step 'node-summary' ([pscustomobject]@{ plan = $planPreview; setup = $r.out; score = $scoreOk; card = $cardOk })
Check 'summary: portal preview reads as preview' ($sumR.out.summary -match 'Portal setup: 6 change\(s\) to make \(preview\), 4 already there\.' -and $sumR.out.summary -match '    - Would create user Pat Lee') $sumR.out.summary

Reset-Cr
$r = Invoke-Step 'node-portal' ([pscustomobject]@{ plan = $planLive; setup = ($checkOut | ConvertTo-Json -Depth 10) })
$paths = @($global:Cr.posts | ForEach-Object { $_.path }) -join ','
Check 'portal live: creates only the new records, in order' ($paths -eq '/v2/domain,/v2/companygroupcompany,/v2/user,/v2/token,/v2/catalog,/v2/menu' -and $r.out.status -eq 'success') "$paths $($r.error)"
Check 'portal live: an existing token is never sent (POST overwrites)' (@($global:Cr.posts | Where-Object { $_.path -eq '/v2/token' -and $_.body.token -eq 'SupportPhone' }).Count -eq 0) ''
Check 'portal live: duplicates skipped with a reason' (@(@($r.out.skipped) -match 'sam\.roe@contoso\.com>: already in Contoso Ltd').Count -eq 1 -and @(@($r.out.skipped) -match "request form 'Request a new laptop'").Count -eq 1 -and @(@($r.out.skipped) -match 'token @SupportPhone').Count -eq 1) (@($r.out.skipped) -join ' | ')
Check 'portal live: user in another company warned, not moved' (@(@($r.out.warnings) -match 'alex\.kim@contoso\.com is already a portal user in another company \(3\)').Count -eq 1) (@($r.out.warnings) -join ' | ')
$d = @($global:Cr.posts | Where-Object { $_.path -eq '/v2/domain' })[0].body
Check 'portal live: first domain becomes the default' ($d.isDefault -eq $true -and $d.companyId -eq 7 -and $d.name -eq 'contoso.com') ($d | ConvertTo-Json -Compress)
$f = @($global:Cr.posts | Where-Object { $_.path -eq '/v2/catalog' })[0].body
Check 'portal live: request form defaults' ($f.isSelfApproval -eq $false -and $f.isAppendSubject -eq $true -and $f.isSendToPsa -eq $true -and $f.selectText -eq 'REQUEST' -and $f.subject -eq 'New starter') ($f | ConvertTo-Json -Compress)
$m = @($global:Cr.posts | Where-Object { $_.path -eq '/v2/menu' })[0].body
Check 'portal live: menu tile order 0, editRights 0, shown to Everyone' ($m.order -eq 0 -and $m.editRights -eq 0 -and @($m.groups) -contains 'Everyone') ($m | ConvertTo-Json -Compress)
Check 'portal live: no Everyone manual step when groups were set' (@(@($r.out.manualSteps) -match 'to Everyone').Count -eq 0) (@($r.out.manualSteps) -join ' | ')

Reset-Cr
$global:Cr.domain = @($global:Cr.domain) + @([pscustomobject]@{ companyDomainId = 2; companyId = 7; name = 'contoso.com'; isDefault = $true })
$global:Cr.companygroupcompany = @([pscustomobject]@{ companyGroupId = 4; companyId = 7 })
$global:Cr.user = @($global:Cr.user) + @([pscustomobject]@{ userId = 'u3'; companyId = 7; email = 'pat.lee@contoso.com' })
$global:Cr.token = @($global:Cr.token) + @([pscustomobject]@{ companyId = 7; name = 'SupportEmail' })
$global:Cr.catalog = @($global:Cr.catalog) + @([pscustomobject]@{ companyCatalogId = 2; companyId = 7; subject = 'New starter' })
$global:Cr.menu = @([pscustomobject]@{ companyMenuId = 9; companyId = 7; name = 'Remote Support' })
$r = Invoke-Step 'node-portal' ([pscustomobject]@{ plan = $planLive; setup = $checkOut })
Check 'portal re-run: everything already there, nothing written' ($global:Cr.posts.Count -eq 0 -and @($r.out.actions).Count -eq 0 -and $r.out.message -match '^Nothing to add to Contoso Ltd, 10 already there\.') "$($r.out.message) $($r.error)"

Reset-Cr; $global:Cr.failPost = '/v2/user'; $global:Cr.refuseGroups = $true
$r = Invoke-Step 'node-portal' ([pscustomobject]@{ plan = $planLive; setup = $checkOut })
Check 'portal: a failed create is reported, never called created' ($r.out.status -eq 'partial' -and @(@($r.out.failed) -match '^user Pat Lee <pat\.lee@contoso\.com>: ').Count -eq 1 -and @(@($r.out.actions) -match 'user Pat Lee').Count -eq 0) "$(@($r.out.failed) -join ' | ') $($r.error)"
Check 'portal: tile added without groups when refused, with a manual step' (@($r.out.actions) -contains "Created menu tile 'Remote Support'" -and @($r.out.manualSteps) -contains "Show the menu tile 'Remote Support' to Everyone.") (@($r.out.manualSteps) -join ' | ')
$sumR = Invoke-Step 'node-summary' ([pscustomobject]@{ plan = $planLive; setup = $r.out; score = $scoreOk; card = $cardOk })
Check 'summary: failed portal records flagged' ($sumR.out.status -eq 'incomplete' -and $sumR.out.summary -match '1 failed\.' -and $sumR.out.summary -match '    - Failed user Pat Lee' -and @(@($sumR.out.warnings) -match "couldn't be added").Count -eq 1) "$($sumR.out.summary) | $(@($sumR.out.warnings) -join ' | ')"
Check 'portal: a plain failure carries no deleted-user hint' (@(@($r.out.failed) -match 'deleted portal user').Count -eq 0) (@($r.out.failed) -join ' | ')

# The error CloudRadial gave live (2026-11-09) when the email belonged to a soft-deleted user: indented JSON.
Reset-Cr; $global:Cr.failPost = '/v2/user'
$global:Cr.failMessage = "CloudRadial POST /v2/user failed (HTTP 400): `n{`n  `"success`": false,`n  `"message`": `"Failed to create user due to a database error. Check logs for details.`"`n}"
$r = Invoke-Step 'node-portal' ([pscustomobject]@{ plan = $planLive; setup = $checkOut })
$f = [string]@(@($r.out.failed) -match '^user Pat Lee')[0]
Check 'portal: database error on a user explains the deleted-user cause, on one line' ($f -match 'database error' -and $f -match 'deleted portal user' -and $f -notmatch "`n") $f

Reset-Cr; $global:Cr.company = @()
$r = Invoke-Step 'node-portal' ([pscustomobject]@{ plan = $planLive; setup = $checkOut })
Check 'portal: missing company stops before any write' ($r.out.status -eq 'error' -and $r.error -match 'company 7 was not found' -and $global:Cr.posts.Count -eq 0) $r.error
$r = Invoke-Step 'node-portal' ([pscustomobject]@{ plan = $planLive; setup = [pscustomobject]@{ status = 'rejected'; message = 'bad email' } })
Check 'portal: a rejected check stops it' ($r.out.status -eq 'error' -and $r.error -match 'bad email') $r.error
$r = Invoke-Step 'node-portal' ([pscustomobject]@{ plan = [pscustomobject]@{ company = 'Nobody'; company_id = 7; mode = 'live' }; setup = $checkOut })
Check 'portal: unknown AutomationAI company stops it' ($r.out.status -eq 'error' -and $r.error -match "No AutomationAI company matches 'Nobody'") $r.error

Write-Host "$pass passed, $fail failed"
if ($fail) { exit 1 }
