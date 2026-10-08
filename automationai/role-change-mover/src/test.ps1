# Mock harness for role-change-mover.yml: fake Key Vault, CloudRadial, Microsoft Graph, PSAs and node I/O.
# Runs both step scripts exactly as they ship (extracted from the built .yml) through
# & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest. Placeholder data only (Contoso).
# Usage: node build.js --check; pwsh -NoProfile -File test.ps1   (needs js-yaml, or JS_YAML_PATH)
param([switch]$ShowNotes)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')
$ErrorActionPreference = 'Stop'

# ---------- extract the step scripts from the built workflow ----------
$tmp = Join-Path ([IO.Path]::GetTempPath()) "role-change-mover-test-$PID"
New-Item -ItemType Directory -Force $tmp | Out-Null
$extract = "const p=require('path');let y;try{y=require('js-yaml')}catch{try{y=require(p.join(process.argv[3],'node_modules','js-yaml'))}catch{y=require(process.env.JS_YAML_PATH)}};const w=y.load(require('fs').readFileSync(process.argv[1],'utf8'));for(const a of w.definition.activities){if(a.type==='powershell-script')require('fs').writeFileSync(p.join(process.argv[2],a.id+'.ps1'),a.properties.script)}"
& node -e $extract (Join-Path $PSScriptRoot '..\role-change-mover.yml') $tmp $Shared
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the step scripts (is js-yaml installed, or JS_YAML_PATH set?)' }
$ReadScript = Get-Content -Raw (Join-Path $tmp 'node-read.ps1')
$ApplyScript = Get-Content -Raw (Join-Path $tmp 'node-apply.ps1')
Remove-Item -Recurse -Force $tmp

# ---------- placeholder data ----------
$GraphBase = 'https://graph.microsoft.com'
$TenantGuid = '0a1b2c3d-0000-4000-8000-00000000c0de'
$BaseSecrets = @{
    'M365-TenantId' = $TenantGuid; 'M365-ClientId' = 'app-id'; 'M365-ClientSecret' = 'not-a-real-secret'
    'CloudRadial-BaseUrl' = 'https://cr.example'; 'CloudRadial-PublicKey' = 'pub'; 'CloudRadial-PrivateKey' = 'priv'
    'DepartmentMap-CompanyId' = '42'
}
$PsaSecrets = @{
    connectwise = @{ 'CW-ApiUrl' = 'https://cw.example/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'Autotask-ApiUrl' = 'https://at.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@examplemsp.com'; 'Autotask-Secret' = 's' }
    halopsa     = @{ 'Halo-ApiUrl' = 'https://halo.example'; 'Halo-ClientId' = 'id'; 'Halo-ClientSecret' = 's' }
    zendesk     = @{ 'Zendesk-BaseUrl' = 'https://zd.example'; 'Zendesk-Email' = 'agent@examplemsp.com'; 'Zendesk-ApiToken' = 't' }
}
$TemplateCsv = @(Get-Content (Join-Path $PSScriptRoot '..\department-map-template.csv'))
function ConvertTo-ArticleHtml { param([string[]]$Lines) '<p>Department map for Contoso</p>' + (($Lines | ForEach-Object { '<p>' + [System.Net.WebUtility]::HtmlEncode($_) + '</p>' }) -join '') }

$GroupDefs = @(
    @{ id = 'g-sales'; displayName = 'Sales Team'; mailEnabled = $false; securityEnabled = $true; groupTypes = @() }
    @{ id = 'g-saleslist'; displayName = 'sales@contoso.com list'; mailEnabled = $true; securityEnabled = $false; groupTypes = @() }
    @{ id = 'g-crm'; displayName = 'CRM Users'; mailEnabled = $false; securityEnabled = $true; groupTypes = @() }
    @{ id = 'g-mkt'; displayName = 'Marketing Team'; mailEnabled = $true; securityEnabled = $false; groupTypes = @('Unified') }
    @{ id = 'g-mktlist'; displayName = 'marketing@contoso.com list'; mailEnabled = $true; securityEnabled = $false; groupTypes = @() }
    @{ id = 'g-adobe'; displayName = 'Adobe Creative Cloud Users'; mailEnabled = $false; securityEnabled = $true; groupTypes = @() }
    @{ id = 'g-fin'; displayName = 'Finance Team'; mailEnabled = $false; securityEnabled = $true; groupTypes = @() }
    @{ id = 'g-finshare'; displayName = 'Finance Share Readers'; mailEnabled = $true; securityEnabled = $true; groupTypes = @() }
    @{ id = 'g-dyn'; displayName = 'All Marketing (dynamic)'; mailEnabled = $false; securityEnabled = $true; groupTypes = @('DynamicMembership') }
)
$Users = @{
    'sam.doe@contoso.com'  = @{ id = 'u-sam'; userPrincipalName = 'sam.doe@contoso.com'; displayName = 'Sam Doe'; accountEnabled = $true; jobTitle = 'Sales Representative'; department = 'Sales' }
    'alex.kim@contoso.com' = @{ id = 'u-alex'; userPrincipalName = 'alex.kim@contoso.com'; displayName = 'Alex Kim'; accountEnabled = $true; jobTitle = 'Marketing Manager'; department = 'Marketing' }
    'pat.lee@contoso.com'  = @{ id = 'u-pat'; userPrincipalName = 'pat.lee@contoso.com'; displayName = 'Pat Lee'; accountEnabled = $true; jobTitle = 'Sales Manager'; department = 'Sales' }
}

# Per-scenario state.
$Sc = @{}
function New-Scenario {
    param([string]$Psa = 'connectwise', [string[]]$Map = $TemplateCsv, [hashtable]$Over = @{})
    $Sc.Clear()
    $Sc.articles = @{ 'Role Change: Department Map' = (ConvertTo-ArticleHtml $Map) }
    $Sc.member = @('g-sales', 'g-saleslist', 'g-crm')
    $Sc.manager = 'u-pat'
    $Sc.dept = 'Sales'; $Sc.title = 'Sales Representative'
    $Sc.licenses = @(@{ skuId = 'f245ecc8-75af-4f8e-b61f-27d8114de5f3'; skuPartNumber = 'Microsoft_365_Business_Standard' })
    $Sc.forbid = @()     # Graph paths (regex) that answer 403
    $Sc.extraGroups = @()
    $Sc.notes = New-Object System.Collections.ArrayList   # ticket notes written so far, read back by the retry guard
    foreach ($k in $Over.Keys) { $Sc[$k] = $Over[$k] }
    $sec = $BaseSecrets.Clone(); foreach ($k in $PsaSecrets[$Psa].Keys) { $sec[$k] = $PsaSecrets[$Psa][$k] }
    $sec['PSA-Type'] = $Psa
    Reset-Mock $sec $Handler
}
function J { param($o) [pscustomobject]$o }
function Get-UserObj { param([string]$key) $u = $Users[$key].Clone(); if ($u.id -eq 'u-sam') { $u.department = $Sc.dept; $u.jobTitle = $Sc.title }; return (J $u) }

$Handler = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    $m = $c.Method
    if ($u -like 'https://login.microsoftonline.com/*') { return J @{ access_token = 'tok'; expires_in = 3599 } }
    # ---- CloudRadial ----
    if ($u -like 'https://cr.example/*') {
        if ($u -match "/v2/odata/article\?.*companyId eq (\d+) and subject eq '(.+?)'&") {
            $s = $Matches[2] -replace "''", "'"
            if ($Matches[1] -eq '42' -and $Sc.articles.Contains($s)) { return J @{ value = @(J @{ articleId = 7; subject = $s; companyId = 42 }) } }
            return J @{ value = @() }
        }
        if ($u -match '/v2/article/7$') { return J @{ body = @($Sc.articles.Values)[0] } }
        throw "unmocked CloudRadial $m $u"
    }
    # ---- Microsoft Graph ----
    if ($u -like "$GraphBase/*") {
        $p = $u.Substring($GraphBase.Length)
        foreach ($f in @($Sc.forbid)) { if ("$m $p" -match $f) { New-HttpError 403 '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}' } }
        $groups = @($GroupDefs) + @($Sc.extraGroups)
        if ($m -eq 'GET') {
            if ($p -match '^/v1\.0/users/([^/?]+)\?') { $k = $Matches[1]; if ($Users.ContainsKey($k)) { return Get-UserObj $k }; New-HttpError 404 '{"error":{"code":"Request_ResourceNotFound","message":"Resource does not exist."}}' }
            if ($p -match '^/v1\.0/users/u-sam/manager') { if ($Sc.manager) { $mk = @($Users.Keys | Where-Object { $Users[$_].id -eq $Sc.manager })[0]; return Get-UserObj $mk }; New-HttpError 404 '{"error":{"code":"Request_ResourceNotFound","message":"Resource manager does not exist."}}' }
            if ($p -match '^/v1\.0/users/u-sam/memberOf') {
                $v = @($Sc.member | ForEach-Object { $id = $_; $gd = @($groups | Where-Object { $_.id -eq $id })[0]; J @{ '@odata.type' = '#microsoft.graph.group'; id = $id; displayName = $gd.displayName } })
                $v += J @{ '@odata.type' = '#microsoft.graph.directoryRole'; id = 'r-1'; displayName = 'Directory Readers' }
                return J @{ value = $v }
            }
            if ($p -match '^/v1\.0/users/u-sam/licenseDetails') { return J @{ value = @($Sc.licenses | ForEach-Object { J $_ }) } }
            if ($p -match "^/v1\.0/groups\?\`$filter=displayName eq '(.+?)'&") {
                $name = $Matches[1] -replace "''", "'"
                return J @{ value = @($groups | Where-Object { $_.displayName -eq $name } | ForEach-Object { J $_ }) }
            }
            if ($p -match '^/v1\.0/groups/([^/?]+)\?') { $id = $Matches[1]; $hit = @($groups | Where-Object { $_.id -eq $id }); if ($hit.Count) { return J $hit[0] }; New-HttpError 404 '{"error":{"code":"Request_ResourceNotFound","message":"Resource does not exist."}}' }
        }
        if ($m -eq 'POST' -and $p -match '^/v1\.0/groups/([^/]+)/members/\$ref$') { return $null }
        if ($m -eq 'DELETE' -and $p -match '^/v1\.0/groups/([^/]+)/members/u-sam/\$ref$') { return $null }
        if ($m -eq 'PATCH' -and $p -eq '/v1.0/users/u-sam') { return $null }
        if ($m -eq 'PUT' -and $p -eq '/v1.0/users/u-sam/manager/$ref') { return $null }
        throw "unmocked Graph $m $p"
    }
    # ---- PSAs ----
    # Notes are kept in $Sc.notes, so a rerun in the same scenario sees what the first run wrote.
    if ($u -like 'https://cw.example/*' -and $m -eq 'POST' -and $u -like '*/service/tickets/12345/notes') { $b = $c.Body | ConvertFrom-Json; $null = $Sc.notes.Add((J @{ id = $Sc.notes.Count + 1; text = $b.text; internalAnalysisFlag = $b.internalAnalysisFlag; detailDescriptionFlag = $b.detailDescriptionFlag })); return J @{ id = $Sc.notes.Count } }
    if ($u -like 'https://cw.example/*' -and $m -eq 'GET' -and $u -like '*/service/tickets/12345/notes?*') { if ($u -like '*page=1') { return @($Sc.notes) }; return @() }
    if ($u -like 'https://at.example/*') {
        if ($m -eq 'GET' -and $u -like '*/TicketNotes/entityInformation/fields') { return J @{ fields = @((J @{ name = 'publish'; picklistValues = @((J @{ value = '1'; label = 'All Autotask Users'; isActive = $true }), (J @{ value = '2'; label = 'Internal Only'; isActive = $true })) }), (J @{ name = 'noteType'; picklistValues = @((J @{ value = '13'; label = 'System Workflow Note'; isActive = $true }), (J @{ value = '1'; label = 'Task Detail'; isActive = $true })) })) } }
        if ($m -eq 'POST' -and $u -like '*/Tickets/12345/Notes') { $b = $c.Body | ConvertFrom-Json; $null = $Sc.notes.Add((J @{ id = $Sc.notes.Count + 1; title = $b.title; description = $b.description; publish = $b.publish })); return J @{ itemId = $Sc.notes.Count } }
        if ($m -eq 'GET' -and $u -like '*/TicketNotes/query?search=*') { return J @{ items = @($Sc.notes); pageDetails = (J @{ nextPageUrl = $null }) } }
    }
    if ($u -like 'https://halo.example/*') {
        if ($u -like '*/auth/token') { return J @{ access_token = 'halo-tok' } }
        if ($m -eq 'POST' -and $u -like '*/api/Actions') { $b = @($c.Body | ConvertFrom-Json)[0]; $null = $Sc.notes.Add((J @{ id = $Sc.notes.Count + 1; note = $b.note; hiddenfromuser = $b.hiddenfromuser })); return @(J @{ id = $Sc.notes.Count }) }
        if ($m -eq 'GET' -and $u -like '*/api/Actions?ticket_id=12345*') { return J @{ actions = @($Sc.notes) } }
    }
    if ($u -like 'https://zd.example/*' -and $m -eq 'PUT' -and $u -like '*/tickets/12345') { $cm = ($c.Body | ConvertFrom-Json).ticket.comment; $null = $Sc.notes.Add((J @{ id = $Sc.notes.Count + 1; body = $cm.body; public = $cm.public; author_id = 1 })); return J @{ ticket = J @{ id = 12345 } } }
    if ($u -like 'https://zd.example/*' -and $m -eq 'GET' -and $u -like '*/tickets/12345/comments*') { return J @{ comments = @($Sc.notes); next_page = $null } }
    throw "unmocked $m $u"
}

# ---------- runner ----------
$Node = @{ In = $null; Out = $null }
function Get-NodeInput { param($Name) return $Node.In }
function Set-NodeOutput { param($o) $Node.Out = $o }
function Invoke-Step {
    param([string]$Script, $Input0)
    $Node.In = $Input0; $Node.Out = $null; $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Script)) } catch { $err = [string]$_.Exception.Message }
    return @{ out = $Node.Out; err = $err }
}
# Runs both steps; the Read output reaches Apply through a JSON round trip, as it does on the runner.
function Invoke-Mover {
    param($Body)
    $r = Invoke-Step $ReadScript $Body
    $json = $null; if ($null -ne $r.out) { $json = ($r.out | ConvertTo-Json -Depth 20 | ConvertFrom-Json) }
    $a = Invoke-Step $ApplyScript ([pscustomobject]@{ prep = $json })
    if ($ShowNotes -and $null -ne $a.out) { Write-Host "----- $($a.out.status): $($a.out.message)`n$($a.out.internal_note)`n-----" -ForegroundColor DarkGray }
    return @{ read = $r.out; readErr = $r.err; out = $a.out; err = $a.err }
}
function Get-GraphWrites { return @($Mock.Calls | Where-Object { $_.Uri -like "$GraphBase/*" -and $_.Method -ne 'GET' }) }
function Get-PsaWrites { return @($Mock.Calls | Where-Object { $_.Uri -notlike "$GraphBase/*" -and $_.Uri -notlike 'https://cr.example/*' -and $_.Uri -notlike 'https://login.*' -and $_.Method -ne 'GET' -and $_.Uri -notlike '*/auth/token' }) }
function New-Body { param([hashtable]$Over = @{}) $b = [ordered]@{ upn = 'sam.doe@contoso.com'; new_department = 'Marketing'; new_title = 'Marketing Coordinator'; new_manager_upn = 'alex.kim@contoso.com'; confirm = 'false'; psa = ''; ticket_id = '12345' }; foreach ($k in $Over.Keys) { $b[$k] = $Over[$k] }; return [pscustomobject]$b }

# ---------- 1. preview (ConnectWise) ----------
New-Scenario 'connectwise'
$r = Invoke-Mover (New-Body)
$o = $r.out
Check 'preview: read step ok' ($r.read.status -eq 'ok') "$($r.read.status) $($r.read.message)"
Check 'preview: status pending_confirmation, run not failed' ($o.status -eq 'pending_confirmation' -and -not $r.err) "$($o.status) / $($r.err)"
Check 'preview: no Microsoft 365 writes' (@(Get-GraphWrites).Count -eq 0) (Show-Calls)
Check 'preview: 6 changes planned in order' (@($o.planned).Count -eq 6 -and $o.planned[0] -like 'Add to Marketing Team*' -and $o.planned[1] -like 'Add to Adobe*' -and $o.planned[2] -like 'Remove from Sales Team*' -and $o.planned[3] -like 'Remove from CRM Users*' -and $o.planned[4] -like "Set department to 'Marketing' and job title to 'Marketing Coordinator'" -and $o.planned[5] -like 'Set manager to Alex Kim*') ($o.planned -join ' | ')
Check 'preview: distribution lists listed for Exchange, not planned' (@($o.exchange).Count -eq 2 -and @($o.exchange | Where-Object { $_.action -eq 'add' -and $_.name -eq 'marketing@contoso.com list' }).Count -eq 1 -and @($o.exchange | Where-Object { $_.action -eq 'remove' -and $_.name -eq 'sales@contoso.com list' }).Count -eq 1 -and -not ($o.planned -join ' ' -match 'list')) (($o.exchange | ConvertTo-Json -Depth 5 -Compress))
Check 'preview: licence differences flagged only' (@($o.licenses).Count -eq 2 -and @($o.licenses | Where-Object { $_.change -eq 'assign' -and $_.sku -eq 'Microsoft_365_Business_Premium' }).Count -eq 1 -and @($o.licenses | Where-Object { $_.change -eq 'remove' -and $_.sku -eq 'Microsoft_365_Business_Standard' }).Count -eq 1 -and @(Get-Calls 'POST' '*assignLicense*').Count -eq 0) (($o.licenses | ConvertTo-Json -Compress))
$note = @(Get-PsaWrites)
$nb = if ($note.Count) { Read-Body $note[0] } else { $null }
Check 'preview: one ConnectWise internal note' ($note.Count -eq 1 -and $note[0].Uri -like '*/service/tickets/12345/notes' -and $nb.internalAnalysisFlag -eq $true -and $nb.detailDescriptionFlag -eq $false -and $o.note_written) (Show-Calls)
Check 'preview: note holds the plan, Exchange items and licences' ($nb.text -match 'Preview only' -and $nb.text -match 'Change in Exchange' -and $nb.text -match 'marketing@contoso.com list' -and $nb.text -match 'Licences to review' -and $nb.text -match 'Sales to Marketing') $nb.text
Check 'preview: public note has no group or licence names' ($o.public_note -and $o.public_note -notmatch 'Team|list|Microsoft_365|CRM|Adobe') $o.public_note
Check 'preview: note marker is a code, with no names or addresses' ($nb.text -match '\n\[role-change-mover: preview [0-9a-f]{8} \d{4}-\d{2}-\d{2}\]$' -and (@($nb.text -split "`n")[-1]) -notmatch '@|contoso|Sam|Marketing') (@($nb.text -split "`n")[-1])
Check 'preview: message is a plain sentence' ($o.message -match '^Previewed 6 changes for sam\.doe@contoso\.com\. Nothing was changed' -and $o.message -match '2 lists need changing in Exchange') $o.message

# ---------- 1b. rerun of the same preview (ServiceAI Retry) ----------
$Mock.Calls.Clear()
$r = Invoke-Mover (New-Body)
Check 'rerun preview: no second note, nothing written' (@(Get-PsaWrites).Count -eq 0 -and @(Get-GraphWrites).Count -eq 0 -and $Sc.notes.Count -eq 1 -and -not $r.out.note_written) (Show-Calls)
Check 'rerun preview: says the note was already there' ((@($r.out.actions) -join ' ') -match 'already on ticket 12345') (@($r.out.actions) -join ' | ')

# ---------- 2. confirm (Autotask) ----------
New-Scenario 'autotask'
$r = Invoke-Mover (New-Body @{ confirm = 'true'; psa = 'autotask' })
$o = $r.out
Check 'confirm: status success' ($o.status -eq 'success' -and -not $r.err -and @($o.ran).Count -eq 6) "$($o.status) $($o.message) $($r.err)"
$adds = @(Get-Calls 'POST' "$GraphBase/v1.0/groups/*/members/`$ref")
$dels = @(Get-Calls 'DELETE' "$GraphBase/v1.0/groups/*/members/u-sam/`$ref")
Check 'confirm: adds the new groups by $ref' ($adds.Count -eq 2 -and $adds[0].Uri -like '*/groups/g-mkt/*' -and $adds[1].Uri -like '*/groups/g-adobe/*' -and (Read-Body $adds[0]).'@odata.id' -eq "$GraphBase/v1.0/directoryObjects/u-sam") (Show-Calls)
Check 'confirm: removes the old groups' ($dels.Count -eq 2 -and $dels[0].Uri -like '*/groups/g-sales/*' -and $dels[1].Uri -like '*/groups/g-crm/*') (Show-Calls)
Check 'confirm: never touches the distribution lists' (@($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and $_.Uri -match 'g-saleslist|g-mktlist' }).Count -eq 0) (Show-Calls)
$pb = Read-Body @(Get-Calls 'PATCH' "$GraphBase/v1.0/users/u-sam")[0]
Check 'confirm: PATCH sets department and job title' ($pb.department -eq 'Marketing' -and $pb.jobTitle -eq 'Marketing Coordinator') ($pb | ConvertTo-Json -Compress)
$mg = @(Get-Calls 'PUT' "$GraphBase/v1.0/users/u-sam/manager/`$ref")
Check 'confirm: manager set to the new manager' ($mg.Count -eq 1 -and (Read-Body $mg[0]).'@odata.id' -eq "$GraphBase/v1.0/users/u-alex") (Show-Calls)
$atNote = @(Get-Calls 'POST' 'https://at.example/*/Tickets/12345/Notes')
$atb = if ($atNote.Count) { Read-Body $atNote[0] } else { $null }
Check 'confirm: Autotask internal note with the result' ($atNote.Count -eq 1 -and $atb.publish -eq 2 -and $atb.noteType -eq 1 -and $atb.description -match 'Applied all 6' -and $atb.title -eq 'Role change result') (Show-Calls)
Check 'confirm: writes come after every read (stop-at-first-failure order)' ($o.ran[0].description -like 'Add to Marketing Team*' -and $o.ran[5].description -like 'Set manager*') ''
Check 'confirm: Autotask note ends with the applied marker' ($atb.description -match '\n\[role-change-mover: applied [0-9a-f]{8} \d{4}-\d{2}-\d{2}\]$') $atb.description
# 2b. Retry after the changes landed: Microsoft 365 now matches, so nothing is changed and no second note is written.
$Sc.member = @('g-mkt', 'g-adobe', 'g-saleslist'); $Sc.dept = 'Marketing'; $Sc.title = 'Marketing Coordinator'; $Sc.manager = 'u-alex'
$Mock.Calls.Clear()
$r = Invoke-Mover (New-Body @{ confirm = 'true'; psa = 'autotask' })
Check 'rerun confirm: success, no Graph writes' ($r.out.status -eq 'success' -and @(Get-GraphWrites).Count -eq 0) "$($r.out.status) $($r.out.message)"
Check 'rerun confirm: no second Autotask note' (@(Get-Calls 'POST' 'https://at.example/*/Tickets/12345/Notes').Count -eq 0 -and $Sc.notes.Count -eq 1) (Show-Calls)

# ---------- 3. missing permission (403) ----------
New-Scenario 'connectwise' -Over @{ forbid = @('^POST /v1\.0/groups/g-adobe/members') }
$r = Invoke-Mover (New-Body @{ confirm = 'true' })
$o = $r.out
Check '403 on write: stops at the first failure and says so' ($o.status -eq 'error' -and @($o.ran).Count -eq 1 -and @($o.not_run).Count -eq 4 -and $o.failed.description -like 'Add to Adobe*') "$($o.status) ran=$(@($o.ran).Count) notRun=$(@($o.not_run).Count)"
Check '403 on write: message names GroupMember.ReadWrite.All' ($o.message -match 'GroupMember\.ReadWrite\.All' -and $o.message -match 'Made 1 of 6 changes') $o.message
Check '403 on write: run marked failed, output kept, note still written' ($r.err -and $o.note_written -and (Read-Body @(Get-PsaWrites)[0]).text -match 'Not run:') $r.err
Check '403 on write: no remove ran after the failure' (@(Get-Calls 'DELETE' "$GraphBase/*").Count -eq 0) (Show-Calls)
# 3b. Retry once the permission is fixed: the run finishes, and its result note is written (the earlier note was the failure).
$Sc.forbid = @(); $Mock.Calls.Clear()
$r = Invoke-Mover (New-Body @{ confirm = 'true' })
Check 'retry after failure: success note written as a second note' ($r.out.status -eq 'success' -and $r.out.note_written -and $Sc.notes.Count -eq 2 -and (Read-Body @(Get-PsaWrites)[0]).text -match 'Applied all') "$($r.out.status) notes=$($Sc.notes.Count)"
New-Scenario 'connectwise' -Over @{ forbid = @('^GET /v1\.0/groups\?') }
$r = Invoke-Mover (New-Body)
Check '403 on read: plain error naming Group.Read.All, nothing written' ($r.out.status -eq 'error' -and $r.out.message -match 'Group\.Read\.All' -and @(Get-GraphWrites).Count -eq 0 -and $r.err) "$($r.out.status) $($r.out.message)"
New-Scenario 'connectwise' -Over @{ forbid = @('^GET /v1\.0/users/u-sam/memberOf') }
$r = Invoke-Mover (New-Body)
Check '403 on memberOf: error names GroupMember.Read.All' ($r.out.status -eq 'error' -and $r.out.message -match 'GroupMember\.Read\.All') $r.out.message

# ---------- 4. empty result: already matches ----------
New-Scenario 'connectwise' -Over @{ member = @('g-mkt', 'g-adobe', 'g-mktlist'); dept = 'Marketing'; title = 'Marketing Coordinator'; manager = 'u-alex'; licenses = @(@{ skuId = 'cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46'; skuPartNumber = 'Microsoft_365_Business_Premium' }) }
$r = Invoke-Mover (New-Body @{ confirm = 'true' })
$o = $r.out
Check 'empty: success with nothing to change' ($o.status -eq 'success' -and -not $r.err -and @($o.planned).Count -eq 0 -and $o.message -match 'already matches') "$($o.status) $($o.message)"
Check 'empty: no Graph writes, no exchange or licence items' (@(Get-GraphWrites).Count -eq 0 -and @($o.exchange).Count -eq 0 -and @($o.licenses).Count -eq 0) (Show-Calls)
Check 'empty: same department means nothing removed' (@(Get-Calls 'DELETE' "$GraphBase/*").Count -eq 0) ''

# ---------- 5. the department map fails clearly ----------
New-Scenario 'connectwise' -Over @{ articles = @{} }
$r = Invoke-Mover (New-Body)
Check 'no map article: incomplete, names the article, no Graph calls' ($r.out.status -eq 'incomplete' -and $r.out.message -match "no KB article titled 'Role Change: Department Map'" -and @($Mock.Calls | Where-Object { $_.Uri -like "$GraphBase/*" }).Count -eq 0 -and $r.err) "$($r.out.status) $($r.out.message)"
Check 'no map article: internal note says why' ((Read-Body @(Get-PsaWrites)[0]).text -match 'was not planned') (Show-Calls)
$Mock.Calls.Clear()
$r = Invoke-Mover (New-Body)
Check 'no map article rerun: the same note is not added again' (@(Get-PsaWrites).Count -eq 0 -and $Sc.notes.Count -eq 1) (Show-Calls)
New-Scenario 'connectwise' -Map (@($TemplateCsv) + 'Marketing,Brand Approvers,security,')
$r = Invoke-Mover (New-Body)
Check 'unknown group: incomplete, names the group, nothing written' ($r.out.status -eq 'incomplete' -and $r.out.message -match "no group is named 'Brand Approvers'" -and @(Get-GraphWrites).Count -eq 0) $r.out.message
New-Scenario 'connectwise' -Map (@($TemplateCsv) + 'Marketing,9f8e7d6c-0000-4000-8000-000000000001,security,')
$r = Invoke-Mover (New-Body)
Check 'unknown object id: incomplete, names the id' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'no group has the object id 9f8e7d6c') $r.out.message
New-Scenario 'connectwise' -Map @('department,group,kind,license_sku', 'Marketing,Marketing Team,teams,')
$r = Invoke-Mover (New-Body)
Check 'bad kind: incomplete with the row' ($r.out.status -eq 'incomplete' -and $r.out.message -match "kind 'teams'") $r.out.message
New-Scenario 'connectwise' -Map @('Some notes with no table')
$r = Invoke-Mover (New-Body)
Check 'no header: incomplete, shows the header to use' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'department,group,kind,license_sku') $r.out.message
New-Scenario 'connectwise'
$r = Invoke-Mover (New-Body @{ new_department = 'Legal' })
Check 'new department not in map: incomplete' ($r.out.status -eq 'incomplete' -and $r.out.message -match "'Legal' isn't in the department map") $r.out.message

# ---------- 6. mail-enabled security, dynamic groups, old department ----------
New-Scenario 'halopsa' -Map (@($TemplateCsv) + 'Finance,All Marketing (dynamic),security,')
$r = Invoke-Mover (New-Body @{ new_department = 'Finance'; new_title = ''; new_manager_upn = ''; psa = 'halopsa' })
$o = $r.out
Check 'mail-enabled security: listed for Exchange with a kind warning' (@($o.exchange | Where-Object { $_.name -eq 'Finance Share Readers' -and $_.kind -eq 'mail-enabled security' }).Count -eq 1 -and @($o.warnings | Where-Object { $_ -match "lists 'Finance Share Readers' as security" }).Count -eq 1) (($o.exchange | ConvertTo-Json -Compress) + ' ' + ($o.warnings -join ' | '))
Check 'dynamic group: listed as change by hand, not planned' (@($o.manual | Where-Object { $_.name -eq 'All Marketing (dynamic)' -and $_.reason -match 'dynamic' }).Count -eq 1 -and -not ($o.planned -join ' ' -match 'dynamic')) (($o.manual | ConvertTo-Json -Compress))
Check 'old department defaults to the Graph department' ($r.read.old_department -eq 'Sales' -and @($o.planned | Where-Object { $_ -like 'Remove from Sales Team*' }).Count -eq 1) "$($r.read.old_department)"
Check 'no title or manager given: only department changes' (@($o.planned | Where-Object { $_ -like "Set department to 'Finance'" }).Count -eq 1 -and @($o.planned | Where-Object { $_ -like 'Set manager*' }).Count -eq 0) ($o.planned -join ' | ')
$halo = @(Get-Calls 'POST' 'https://halo.example/api/Actions')
Check 'HaloPSA: hidden note' ($halo.Count -eq 1 -and (Read-Body $halo[0])[0].hiddenfromuser -eq $true) (Show-Calls)
$Mock.Calls.Clear()
$r = Invoke-Mover (New-Body @{ new_department = 'Finance'; new_title = ''; new_manager_upn = ''; psa = 'halopsa' })
Check 'HaloPSA rerun: no second note' (@(Get-Calls 'POST' 'https://halo.example/api/Actions').Count -eq 0 -and $Sc.notes.Count -eq 1) (Show-Calls)
New-Scenario 'connectwise'
$r = Invoke-Mover (New-Body @{ old_department = 'Finance' })
Check 'old_department input overrides Graph: removes Finance groups only' ($r.read.old_department -eq 'Finance' -and @($r.out.planned | Where-Object { $_ -like 'Remove from*' }).Count -eq 0 -and @($r.read.unchanged | Where-Object { $_ -match 'Finance Team' }).Count -eq 1) ($r.out.planned -join ' | ')

# ---------- 7. request shapes and guards ----------
New-Scenario 'zendesk'
$cr = [pscustomobject]@{ Ticket = [pscustomobject]@{ TicketId = '12345'; Questions = @([pscustomobject]@{ Id = 'upn'; Value = 'sam.doe@contoso.com' }, [pscustomobject]@{ Id = 'new_department'; Value = 'Marketing' }, [pscustomobject]@{ Id = 'new_title'; Value = '@new_title' }) }; Company = [pscustomobject]@{ CompanyTenantId = $TenantGuid } }
$r = Invoke-Mover ([pscustomobject]@{ trigger = $cr })
Check 'CloudRadial form shape: parsed, literal @token treated as missing' ($r.out.status -eq 'pending_confirmation' -and $r.read.ticket_id -eq '12345' -and @($r.out.planned | Where-Object { $_ -like "Set department to 'Marketing'" }).Count -eq 1) "$($r.out.status) $($r.out.message) $($r.out.planned -join ' | ')"
$zd = @(Get-Calls 'PUT' 'https://zd.example/api/v2/tickets/12345')
Check 'Zendesk: private comment' ($zd.Count -eq 1 -and (Read-Body $zd[0]).ticket.comment.public -eq $false) (Show-Calls)
$Mock.Calls.Clear()
$r = Invoke-Mover ([pscustomobject]@{ trigger = $cr })
Check 'Zendesk rerun: no second comment' (@(Get-Calls 'PUT' 'https://zd.example/*').Count -eq 0 -and $Sc.notes.Count -eq 1) (Show-Calls)
New-Scenario 'connectwise'
$r = Invoke-Mover (New-Body @{ company_tenant_id = '11111111-2222-4333-8444-555555555555' })
Check 'tenant mismatch: rejected, nothing read from Graph users' ($r.out.status -eq 'rejected' -and @(Get-Calls 'GET' "$GraphBase/v1.0/users*").Count -eq 0) "$($r.out.status) $($r.out.message)"
New-Scenario 'connectwise'
$r = Invoke-Mover (New-Body @{ ticket_id = '' })
Check 'no ticket_id: no PSA call' ($r.out.status -eq 'pending_confirmation' -and @(Get-PsaWrites).Count -eq 0 -and -not $r.out.note_written) (Show-Calls)
New-Scenario 'connectwise'
$r = Invoke-Mover (New-Body @{ upn = 'nobody@contoso.com' })
Check 'unknown user: incomplete' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'No Microsoft 365 user was found for nobody@contoso.com') $r.out.message
New-Scenario 'connectwise'
$r = Invoke-Mover (New-Body @{ new_manager_upn = 'nobody@contoso.com' })
Check 'unknown manager: incomplete' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'new manager nobody@contoso.com') $r.out.message
New-Scenario 'connectwise'
$r = Invoke-Mover (New-Body @{ upn = '' })
Check 'missing upn: incomplete, no calls' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'no upn' -and @($Mock.Calls | Where-Object { $_.Uri -notlike 'https://cw.example/*' }).Count -eq 0) $r.out.message
New-Scenario 'connectwise' -Over @{}
$Mock.Secrets.Remove('DepartmentMap-CompanyId')
$r = Invoke-Mover (New-Body)
Check 'no DepartmentMap-CompanyId: incomplete, names the secret' ($r.out.status -eq 'incomplete' -and $r.out.message -match 'DepartmentMap-CompanyId') $r.out.message
New-Scenario 'connectwise'
$Mock.Secrets.Remove('PSA-Type'); foreach ($k in @($PsaSecrets.connectwise.Keys)) { $Mock.Secrets.Remove($k) }
$r = Invoke-Mover (New-Body)
Check 'no PSA set up: plan still returned, note skipped with a warning' ($r.out.status -eq 'pending_confirmation' -and @($r.out.warnings | Where-Object { $_ -match 'No PSA is set up' }).Count -eq 1) ($r.out.warnings -join ' | ')

New-Scenario 'connectwise'
$rd = Invoke-Step $ReadScript (New-Body)
$a = Invoke-Step $ApplyScript ($rd.out | ConvertTo-Json -Depth 20)
Check 'Apply step: accepts the Read output unwrapped, as JSON text' ($a.out.status -eq 'pending_confirmation' -and @($a.out.planned).Count -eq 6) "$($a.out.status) $($a.out.message)"

Complete-Test
