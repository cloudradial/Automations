# Mock harness for ticket-routing.yml: fake Key Vault, CloudRadial, all six PSAs, the classifier and node I/O.
# Runs the step scripts exactly as they ship (extracted from the built .yml) under strict mode.
# Usage: node build.js; pwsh ./test.ps1        (needs js-yaml from npm install, or JS_YAML_PATH)
param([switch]$ShowNotes)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$tmp = Join-Path ([IO.Path]::GetTempPath()) "ticket-routing-test-$PID"
New-Item -ItemType Directory -Force $tmp | Out-Null
$extract = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const w=y.load(require('fs').readFileSync(process.argv[1],'utf8'));for(const a of w.definition.activities){if(a.type==='powershell-script')require('fs').writeFileSync(process.argv[2]+'/'+a.id+'.ps1',a.properties.script)}"
Push-Location $here; try { node -e $extract (Join-Path $here '..\ticket-routing.yml') $tmp } finally { Pop-Location }
$prepareScript = Join-Path $tmp 'node-prepare.ps1'
$routeScript = Join-Path $tmp 'node-route.ps1'

# ---------- placeholder data (Contoso) ----------
$skillsCsv = @'
Skill,Role,Engineer,Skill Description
Network Firewall Basic L1 (General),Tickets,"Lee, Jordan","Basic firewall changes: single rules, NAT for one host, viewing logs"
Network Firewall Basic L1 (General),Tickets,"Patel, Riya","Basic firewall changes: single rules, NAT for one host, viewing logs"
Network Firewall Fortinet,Tickets,"Patel, Riya","FortiGate policy, VPN and SD-WAN changes"
Network Firewall Fortinet,Tickets,"Okafor, Chidi","FortiGate policy, VPN and SD-WAN changes"
Network Firewall Fortinet,Install,"Okafor, Chidi","FortiGate policy, VPN and SD-WAN changes"
Microsoft 365 Exchange Online,Tickets,"Hildebrand , Caleb","Mailboxes, shared mailboxes, mail flow and transport rules"
Microsoft 365 Exchange Online,Tickets,"Lee, Jordan","Mailboxes, shared mailboxes, mail flow and transport rules"
Role only,Service Manager,"Nguyen, Ava",#N/A
'@ -split "`r?`n"
function New-EngineersCsv { param([hashtable]$Over = @{})
    $rows = [ordered]@{
        'Lee, Jordan' = 'jordan.lee@example.com,101,29682833,Yes,25'
        'Patel, Riya' = 'riya.patel@example.com,102,29682833,Yes,20'
        'Okafor, Chidi' = 'chidi.okafor@example.com,103,29682833,Yes,'
        'Hildebrand, Caleb' = 'caleb.hildebrand@example.com,104,29682833,Yes,'
        'Nguyen, Ava' = 'ava.nguyen@example.com,105,29682833,Yes,'
    }
    foreach ($k in $Over.Keys) { $rows[$k] = $Over[$k] }
    @('Engineer,Email,PSA User Id,PSA Role Id,Active,Max Open Tickets') + @($rows.Keys | ForEach-Object { "`"$_`",$($rows[$_])" })
}
function ConvertTo-PastedHtml { param([string[]]$Lines) ($Lines | ForEach-Object { '<p>' + [System.Net.WebUtility]::HtmlEncode($_) + '</p>' }) -join "`n" }
function ConvertTo-TableHtml { param([string[]]$Lines)
    $rows = foreach ($l in $Lines) { if ($l -match '^\[') { "<tr><td>$l</td></tr>" } else { '<tr>' + ((($l | ConvertFrom-Csv -Header (1..6)).PSObject.Properties | Where-Object { $null -ne $_.Value } | ForEach-Object { "<td>$([System.Net.WebUtility]::HtmlEncode($_.Value))</td>" }) -join '') + '</tr>' } }
    "<table><tbody>$($rows -join '')</tbody></table>"
}

# ---------- mocks ----------
$global:Secrets = @{}
$global:Articles = @{}
$global:Writes = New-Object System.Collections.ArrayList
$global:Assigned = $false
$global:Counts = @{ '101' = 10; '102' = 4; '103' = 7; '104' = 30; '105' = 0 }
$global:LastDates = @{ '101' = '2026-09-29T10:00:00Z'; '102' = '2026-09-30T10:00:00Z'; '103' = '2026-09-20T10:00:00Z'; '104' = '2026-09-01T10:00:00Z' }
$global:FailAssign = $false
$global:NodeIn = $null; $global:NodeOut = $null
$env:RUNNER_KV_NAME = 'kv'
$mockSecrets = @{
    connectwise = @{ 'CW-ApiUrl' = 'https://cw.test/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'contoso'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'Autotask-ApiUrl' = 'https://at.test'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@contoso.example'; 'Autotask-Secret' = 's' }
    halopsa     = @{ 'Halo-ApiUrl' = 'https://halo.test'; 'Halo-ClientId' = 'id'; 'Halo-ClientSecret' = 's' }
    kaseyabms   = @{ 'KaseyaBMS-ApiUrl' = 'https://bms.test'; 'KaseyaBMS-Username' = 'u'; 'KaseyaBMS-Password' = 'p'; 'KaseyaBMS-CompanyName' = 'contoso'; 'KaseyaBMS-NoteTypeId' = '3' }
    syncro      = @{ 'Syncro-ApiUrl' = 'https://syn.test/api/v1'; 'Syncro-ApiKey' = 'k' }
    zendesk     = @{ 'Zendesk-BaseUrl' = 'https://zd.test'; 'Zendesk-Email' = 'agent@contoso.example'; 'Zendesk-ApiToken' = 't' }
}
function Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText, $ErrorAction) $global:Secrets[$Name] }
function Get-NodeInput { param($Name) $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function J { param($o) [pscustomobject]$o }
function Get-UserFromQuery { param([string]$u) if ($u -match '(?:owner/id=|assignedResourceID","value":|assignedResourceID.*?"value":|agent_id=|user_id=|assignee:)(\d+)') { return $Matches[1] }; throw "no user in $u" }
function Invoke-RestMethod { param($Method = 'GET', $Uri, $Headers, $Body, $ContentType, $Form)
    $u = [uri]::UnescapeDataString([string]$Uri)
    if ($Method -ne 'GET') {
        if ($u -match '/security/authenticate$') { if (-not $Form.ContainsKey('GrantType')) { throw 'GrantType required' }; return J @{ Success = $true; Result = J @{ AccessToken = 'tok' } } }
        if ($u -match '/auth/token$') { return J @{ access_token = 'tok' } }
        $null = $global:Writes.Add("$Method $($u -replace '^https://[^/]+', '') $Body")
        if ($global:FailAssign -and ($Body -match 'owner|assignedResourceID|agent_id|AssigneeId|user_id|assignee_id')) { throw 'HTTP 400: mock rejection' }
        return $null
    }
    # CloudRadial
    if ($u -match '^https://cr\.test/v2/odata/article.*subject eq ''(.+?)''') { $s = $Matches[1] -replace "''", "'"; if ($global:Articles.Contains($s)) { return J @{ value = @(J @{ articleId = [array]::IndexOf(@($global:Articles.Keys), $s) + 1; subject = $s }) } }; return J @{ value = @() } }
    if ($u -match '^https://cr\.test/v2/article/(\d+)$') { return J @{ body = $global:Articles[@($global:Articles.Keys)[[int]$Matches[1] - 1]] } }
    $a = $global:Assigned
    $desc = 'Please add a site-to-site VPN tunnel on the FortiGate at the Contoso Leeds office.'
    switch -Regex ($u) {
        # ConnectWise
        '^https://cw\.test/.*/service/tickets/12345$' { return J @{ id = 12345; summary = 'New VPN tunnel to Leeds'; owner = $(if ($a) { J @{ id = 101; identifier = 'jlee' } } else { $null }); company = J @{ id = 5 }; status = J @{ name = 'New' } } }
        '^https://cw\.test/.*/service/tickets/12345/notes' { return @(J @{ text = $desc }) }
        '^https://cw\.test/.*/service/tickets/count' { return J @{ count = $global:Counts[(Get-UserFromQuery $u)] } }
        '^https://cw\.test/.*/service/tickets\?conditions' { $id = Get-UserFromQuery $u; if ($global:LastDates.ContainsKey($id)) { return @(J @{ id = 1; dateEntered = $global:LastDates[$id] }) }; return @() }
        # Autotask
        '^https://at\.test/atservicesrest/v1\.0/Tickets/12345$' { return J @{ item = J @{ id = 12345; title = 'New VPN tunnel to Leeds'; description = $desc; assignedResourceID = $(if ($a) { 101 } else { $null }); companyID = 5; status = 1 } } }
        '^https://at\.test/atservicesrest/v1\.0/Tickets/entityInformation/fields$' { return J @{ fields = @(J @{ name = 'status'; picklistValues = @((J @{ value = '1'; label = 'New'; isActive = $true }), (J @{ value = '5'; label = 'Complete'; isActive = $true }), (J @{ value = '19'; label = 'Complete - Billed'; isActive = $true })) }) } }
        '^https://at\.test/atservicesrest/v1\.0/TicketNotes/entityInformation/fields$' { return J @{ fields = @((J @{ name = 'publish'; picklistValues = @((J @{ value = '1'; label = 'All Autotask Users'; isActive = $true }), (J @{ value = '2'; label = 'Internal Only'; isActive = $true })) }), (J @{ name = 'noteType'; picklistValues = @((J @{ value = '13'; label = 'System Workflow Note'; isActive = $true }), (J @{ value = '1'; label = 'Task Detail'; isActive = $true })) })) } }
        '^https://at\.test/atservicesrest/v1\.0/Tickets/query/count' { if ($u -notmatch '"noteq","field":"status","value":19') { throw 'complete statuses not excluded' }; return J @{ queryCount = $global:Counts[(Get-UserFromQuery $u)] } }
        '^https://at\.test/atservicesrest/v1\.0/Tickets/query\?' { $id = Get-UserFromQuery $u; if ($global:LastDates.ContainsKey($id)) { return J @{ items = @((J @{ id = 7; createDate = '2026-01-01T00:00:00Z' }), (J @{ id = 9; createDate = $global:LastDates[$id] })) } }; return J @{ items = @() } }
        # HaloPSA
        '^https://halo\.test/api/Tickets/12345' { return J @{ id = 12345; summary = 'New VPN tunnel to Leeds'; details = "<p>$desc</p>"; agent_id = $(if ($a) { 101 } else { 0 }); client_id = 5; status_id = 1 } }
        '^https://halo\.test/api/Tickets\?.*order=' { $id = Get-UserFromQuery $u; return J @{ record_count = 1; tickets = @(if ($global:LastDates.ContainsKey($id)) { J @{ dateoccurred = $global:LastDates[$id] } }) } }
        '^https://halo\.test/api/Tickets\?' { return J @{ record_count = $global:Counts[(Get-UserFromQuery $u)]; tickets = @() } }
        # Kaseya BMS
        '^https://bms\.test/v2/servicedesk/tickets/12345$' { return J @{ Success = $true; Result = J @{ Id = 12345; Title = 'New VPN tunnel to Leeds'; Details = $desc; AssigneeId = $(if ($a) { 101 } else { $null }); AccountId = 5 } } }
        # Syncro
        '^https://syn\.test/api/v1/tickets/12345$' { return J @{ ticket = J @{ id = 12345; subject = 'New VPN tunnel to Leeds'; problem_type = 'Network'; user_id = $(if ($a) { 101 } else { $null }); customer_id = 5; status = 'New'; comments = @(J @{ body = $desc }) } } }
        '^https://syn\.test/api/v1/tickets\?.*status=Not Closed' { $n = $global:Counts[(Get-UserFromQuery $u)]; return J @{ tickets = @(1..$n | Where-Object { $n } | ForEach-Object { J @{ id = $_ } }); meta = J @{ total_pages = 1; page = 1 } } }
        '^https://syn\.test/api/v1/tickets\?' { $id = Get-UserFromQuery $u; return J @{ tickets = @(if ($global:LastDates.ContainsKey($id)) { (J @{ id = 1; created_at = '2026-01-01T00:00:00Z' }), (J @{ id = 2; created_at = $global:LastDates[$id] }) }); meta = J @{ total_pages = 1; page = 1 } } }
        # Zendesk
        '^https://zd\.test/api/v2/tickets/12345$' { return J @{ ticket = J @{ id = 12345; subject = 'New VPN tunnel to Leeds'; description = $desc; assignee_id = $(if ($a) { 101 } else { $null }); organization_id = 5; status = 'new' } } }
        '^https://zd\.test/api/v2/search/count' { return J @{ count = $global:Counts[(Get-UserFromQuery $u)] } }
        '^https://zd\.test/api/v2/search\?' { $id = Get-UserFromQuery $u; return J @{ results = @(if ($global:LastDates.ContainsKey($id)) { J @{ created_at = $global:LastDates[$id] } }) } }
    }
    throw "unmocked GET $u"
}

# ---------- runner ----------
$global:Pass = 0; $global:Fail = 0
function Check { param([string]$Name, [bool]$Ok, [string]$Detail = '') if ($Ok) { $global:Pass++ } else { $global:Fail++; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red } }
function Invoke-Routing {
    param($Body, [string]$Psa = 'connectwise', $Ai = @{ skill = 'Network Firewall Fortinet'; role = 'Tickets'; confidence = 0.9; reason = 'The ticket asks for a FortiGate VPN tunnel.' },
        [string[]]$Settings = @(), [hashtable]$Engineers = @{}, [string]$Form = 'pasted', [switch]$Wrap, [switch]$NoSecretPsa)
    $global:Writes.Clear(); $global:NodeOut = $null
    $global:Secrets = @{ 'CloudRadial-BaseUrl' = 'https://cr.test'; 'CloudRadial-PublicKey' = 'p'; 'CloudRadial-PrivateKey' = 's'; 'Routing-CompanyId' = '9' } + $mockSecrets[$Psa]
    if (-not $NoSecretPsa) { $global:Secrets['PSA-Type'] = $Psa }
    $eng = @('[Settings]') + $Settings + @('', '[Engineers]') + (New-EngineersCsv $Engineers)
    $sk = @('Ticket routing skills for Contoso (example)', '[Skills]') + $skillsCsv
    $conv = if ($Form -eq 'table') { 'ConvertTo-TableHtml' } else { 'ConvertTo-PastedHtml' }
    $global:Articles = [ordered]@{ 'Ticket Routing: Skills' = (& $conv $sk); 'Ticket Routing: Engineers and Settings' = (& $conv $eng) }
    # Node I/O goes through JSON, as on the runner.
    $global:NodeIn = if ($Wrap) { [pscustomobject]@{ trigger = ($Body | ConvertTo-Json -Depth 10 | ConvertFrom-Json) } } else { $Body | ConvertTo-Json -Depth 10 | ConvertFrom-Json }
    & { Set-StrictMode -Version Latest; . $prepareScript }
    $prep = $global:NodeOut | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $aiOut = if ((Get-Prop2 $prep 'skip') -eq $true) { @{ skill = ''; role = ''; confidence = 0; reason = 'Skipped by the workflow.' } } else { $Ai }
    $global:NodeIn = [pscustomobject]@{ prep = $prep; ai = ($aiOut | ConvertTo-Json -Depth 5 | ConvertFrom-Json) }
    $global:NodeOut = $null
    & { Set-StrictMode -Version Latest; . $routeScript }
    $r = $global:NodeOut | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    if ($ShowNotes) { Write-Host "    [$($r.status)] $($r.message)`n      $($r.internal_note -replace "`n", "`n      ")" -ForegroundColor DarkGray }
    return [pscustomobject]@{ prep = $prep; r = $r; writes = @($global:Writes) }
}
function Get-Prop2 { param($o, $n) $p = $o.PSObject.Properties[$n]; if ($p) { $p.Value } else { $null } }
$body = @{ triggerSource = 'serviceai-triage'; ticketId = '12345'; confirm = 'true' }

Write-Host 'Preview writes nothing'
$x = Invoke-Routing @{ triggerSource = 'serviceai-triage'; ticketId = '12345'; confirm = 'false' } -Wrap
Check 'preview status' ($x.r.status -eq 'pending_confirmation') "$($x.r.status): $($x.r.message)"
Check 'preview no writes' ($x.writes.Count -eq 0) ($x.writes -join ' | ')
Check 'preview picks Patel (4 open < 7)' ($x.r.assignee.name -eq 'Patel, Riya') "$($x.r.assignee.name)"
Check 'preview default confirm is false' ((Invoke-Routing @{ ticketId = '12345' }).writes.Count -eq 0)

Write-Host 'Live assign on each PSA'
$expect = @{
    connectwise = @('PATCH /v4_6_release/apis/3.0/service/tickets/12345 [{"op":"replace","path":"owner","value":{"id":102}}]', 'POST /v4_6_release/apis/3.0/service/tickets/12345/notes')
    autotask    = @('PATCH /atservicesrest/v1.0/Tickets {', 'POST /atservicesrest/v1.0/Tickets/12345/Notes')
    halopsa     = @('POST /api/Tickets [{"id":12345,"agent_id":102}]', 'POST /api/Actions [{')
    kaseyabms   = @('PATCH /v2/servicedesk/tickets/12345 [{"op":"replace","path":"/AssigneeId","value":102}]', 'POST /v2/servicedesk/tickets/12345/notes')
    syncro      = @('PUT /api/v1/tickets/12345 {"user_id":102}', 'POST /api/v1/tickets/12345/comment')
    zendesk     = @('PUT /api/v2/tickets/12345 {"ticket":{"assignee_id":102}}', 'PUT /api/v2/tickets/12345 {"ticket":{"comment"')
}
foreach ($p in $expect.Keys) {
    $x = Invoke-Routing $body -Psa $p
    Check "$p status" ($x.r.status -eq 'success') "$($x.r.status): $($x.r.message)"
    Check "$p two writes" ($x.writes.Count -eq 2) ($x.writes -join ' | ')
    for ($i = 0; $i -lt 2; $i++) { Check "$p write $i" ($x.writes.Count -gt $i -and $x.writes[$i].StartsWith($expect[$p][$i])) "got: $(if ($x.writes.Count -gt $i) { $x.writes[$i] })" }
    if ($p -eq 'autotask') {
        Check 'autotask sends role' ($x.writes[0] -match '"assignedResourceRoleID":29682833' -and $x.writes[0] -match '"assignedResourceID":102') $x.writes[0]
        Check 'autotask note is Internal Only, Task Detail' ($x.writes[1] -match '"publish":2' -and $x.writes[1] -match '"noteType":1') $x.writes[1]
    }
    if ($p -eq 'halopsa') { Check 'halo note hidden with outcome' ($x.writes[1] -match '"hiddenfromuser":true' -and $x.writes[1] -match '"outcome_id":7') $x.writes[1] }
    if ($p -eq 'kaseyabms') { Check 'kaseya falls back to listed order with a warning' (@($x.r.warnings | Where-Object { $_ -match 'listed order' }).Count -eq 1 -and $x.r.tieBreak -eq 'listed-order') "$($x.r.tieBreak)"; Check 'kaseya note fields' ($x.writes[1] -match '"IsInternal":true' -and $x.writes[1] -match '"TypeId":3') $x.writes[1] }
    if ($p -eq 'syncro') { Check 'syncro note hidden' ($x.writes[1] -match '"hidden":true' -and $x.writes[1] -match '"do_not_email":true' -and $x.writes[1] -match '"subject"') $x.writes[1] }
    if ($p -eq 'zendesk') { Check 'zendesk note private' ($x.writes[1] -match '"public":false') $x.writes[1] }
}

Write-Host 'Already assigned'
$global:Assigned = $true
$x = Invoke-Routing $body
Check 'assigned rejected' ($x.r.status -eq 'rejected' -and $x.r.message -match 'Lee, Jordan') "$($x.r.status): $($x.r.message)"
Check 'assigned no writes' ($x.writes.Count -eq 0)
$x = Invoke-Routing (@{ reassign = 'true' } + $body)
Check 'reassign true routes it' ($x.r.status -eq 'success') $x.r.status
$global:Assigned = $false

Write-Host 'Unknown skill, no skill, low confidence'
$x = Invoke-Routing $body -Ai @{ skill = 'Network Firewall Palo Alto'; role = 'Tickets'; confidence = 0.95; reason = 'x' }
Check 'unknown skill is no match' ($x.r.status -eq 'incomplete' -and $x.r.noMatchApplied -and $x.r.message -match "isn't a skill") $x.r.message
Check 'unknown skill: note only' ($x.writes.Count -eq 1 -and $x.writes[0] -match '/notes') ($x.writes -join ' | ')
$x = Invoke-Routing $body -Ai @{ skill = ''; role = ''; confidence = 0.2; reason = 'Too vague.' }
Check 'empty skill is no match' ($x.r.status -eq 'incomplete' -and $x.writes.Count -eq 1)
$x = Invoke-Routing $body -Ai @{ skill = 'network firewall fortinet '; role = 'tickets'; confidence = 0.9; reason = 'x' }
Check 'case and spacing tolerated' ($x.r.status -eq 'success' -and $x.r.skill -eq 'Network Firewall Fortinet') "$($x.r.status) $($x.r.skill)"
$x = Invoke-Routing $body -Ai @{ skill = 'Network Firewall Fortinet'; role = 'Migrate'; confidence = 0.9; reason = 'x' }
Check 'unlisted role uses the whole skill' ($x.r.status -eq 'success' -and @($x.r.warnings | Where-Object { $_ -match "Role 'Migrate'" }).Count) $x.r.message
$x = Invoke-Routing $body -Ai '```json {"skill":"Network Firewall Fortinet","role":"Tickets","confidence":0.9,"reason":"x"} ```'
Check 'AI answer as fenced JSON text' ($x.r.status -eq 'success') "$($x.r.status) $($x.r.message)"
$low = @{ skill = 'Network Firewall Fortinet'; role = 'Tickets'; confidence = 0.5; reason = 'Could be basic.' }
$x = Invoke-Routing $body -Ai $low
Check 'low confidence leave-unassigned' ($x.r.status -eq 'incomplete' -and $x.writes.Count -eq 1 -and $x.r.message -match 'below minConfidence') $x.r.message
$x = Invoke-Routing $body -Ai $low -Settings @('noMatch: assign-fallback', 'fallbackEngineer: Lee , Jordan')
Check 'low confidence assign-fallback' ($x.r.status -eq 'success' -and $x.r.assignee.name -eq 'Lee, Jordan' -and $x.r.noMatchApplied -and $x.writes[0] -match '"id":101') "$($x.r.status) $($x.r.assignee.name) $($x.writes -join ' | ')"
$x = Invoke-Routing $body -Ai $low -Settings @('noMatch: recommend-only')
Check 'low confidence recommend-only' ($x.r.status -eq 'incomplete' -and $x.writes.Count -eq 1 -and $x.r.internal_note -match 'Suggested: Patel, Riya, Okafor, Chidi') $x.r.internal_note
$x = Invoke-Routing @{ ticketId = '12345'; confirm = 'false' } -Ai $low
Check 'no-match preview writes nothing' ($x.r.status -eq 'pending_confirmation' -and $x.writes.Count -eq 0)
$x = Invoke-Routing $body -Ai $low -Settings @('minConfidence: 0.4')
Check 'minConfidence setting applies' ($x.r.status -eq 'success')

Write-Host 'Limits and inactive engineers'
$x = Invoke-Routing $body -Engineers @{ 'Patel, Riya' = 'riya.patel@example.com,102,29682833,Yes,4'; 'Okafor, Chidi' = 'chidi.okafor@example.com,103,29682833,Yes,7' }
Check 'all at max is no match' ($x.r.status -eq 'incomplete' -and $x.r.message -match 'at their limit' -and $x.writes.Count -eq 1) $x.r.message
$x = Invoke-Routing $body -Engineers @{ 'Patel, Riya' = 'riya.patel@example.com,102,29682833,Yes,4' }
Check 'engineer at max skipped' ($x.r.assignee.name -eq 'Okafor, Chidi' -and @($x.r.candidates | Where-Object { $_.skipped -match 'limit' }).Count -eq 1) "$($x.r.assignee.name)"
$x = Invoke-Routing $body -Engineers @{ 'Patel, Riya' = 'riya.patel@example.com,102,29682833,Yes,4' } -Settings @('respectMaxOpen: no')
Check 'respectMaxOpen no ignores the limit' ($x.r.assignee.name -eq 'Patel, Riya')
$x = Invoke-Routing $body -Ai @{ skill = 'Microsoft 365 Exchange Online'; role = 'Tickets'; confidence = 0.9; reason = 'x' } -Engineers @{ 'Hildebrand, Caleb' = 'caleb.hildebrand@example.com,104,29682833,No,' } -Settings @('tieBreak: listed-order')
Check 'inactive engineer skipped' ($x.r.assignee.name -eq 'Lee, Jordan' -and @($x.r.candidates | Where-Object { $_.skipped -eq 'inactive' }).Count -eq 1) "$($x.r.assignee.name)"
Check 'spacing in names tidied' (@($x.r.candidates | Where-Object { $_.name -eq 'Hildebrand, Caleb' }).Count -eq 1)

Write-Host 'Tie-breaks'
foreach ($p in @('connectwise', 'autotask', 'halopsa', 'syncro', 'zendesk')) {
    $x = Invoke-Routing $body -Psa $p -Settings @('tieBreak: least-recently-assigned')
    Check "$p least-recently-assigned picks Okafor" ($x.r.assignee.name -eq 'Okafor, Chidi' -and $x.r.tieBreak -eq 'least-recently-assigned') "$($x.r.assignee.name) $($x.r.tieBreak) $($x.r.warnings -join ';')"
    $x = Invoke-Routing $body -Psa $p
    Check "$p least-open-tickets picks Patel" ($x.r.assignee.name -eq 'Patel, Riya' -and $x.r.tieBreak -eq 'least-open-tickets') "$($x.r.assignee.name) $($x.r.tieBreak) $($x.r.warnings -join ';')"
}
$x = Invoke-Routing $body -Psa kaseyabms -Settings @('tieBreak: least-recently-assigned')
Check 'kaseya least-recently-assigned falls back' ($x.r.tieBreak -eq 'listed-order' -and $x.r.assignee.name -eq 'Patel, Riya')
$x = Invoke-Routing $body -Settings @('tieBreak: listed-order')
Check 'listed-order picks the first listed' ($x.r.assignee.name -eq 'Patel, Riya')
$global:Counts['103'] = 4
$x = Invoke-Routing $body
Check 'count tie goes to listed order' ($x.r.assignee.name -eq 'Patel, Riya')
$global:Counts['103'] = 7
$picked = @{}; for ($i = 0; $i -lt 12; $i++) { $nm = (Invoke-Routing $body -Settings @("tieBreak: random")).r.assignee.name; $picked[[string]$nm] = 1 }
Check 'random picks among candidates' (@($picked.Keys | Where-Object { @('Patel, Riya', 'Okafor, Chidi') -notcontains $_ }).Count -eq 0) ($picked.Keys -join ';')

Write-Host 'Invalid table, inputs and failures'
$x = Invoke-Routing $body -Settings @('tieBreak: busiest')
Check 'invalid table stops' ($x.r.status -eq 'incomplete' -and $x.r.internal_note -match "tieBreak 'busiest'" -and $x.writes.Count -eq 0) $x.r.internal_note
$x = Invoke-Routing $body -Psa autotask -Engineers @{ 'Okafor, Chidi' = 'chidi.okafor@example.com,103,,Yes,' }
Check 'autotask without a role id stops' ($x.r.status -eq 'incomplete' -and $x.r.internal_note -match 'PSA Role Id') $x.r.internal_note
$x = Invoke-Routing @{ confirm = 'true' }
Check 'missing ticket id' ($x.r.status -eq 'incomplete' -and $x.r.message -match 'No ticket id') $x.r.message
$x = Invoke-Routing $body -NoSecretPsa
Check 'missing PSA' ($x.r.status -eq 'incomplete' -and $x.r.message -match 'PSA-Type') $x.r.message
$x = Invoke-Routing @{ id = 12345; ticketNumber = 'T20261001.0001'; title = 'New VPN tunnel to Leeds'; contactID = 30 } -Psa autotask -Wrap
Check 'raw Autotask ticket body (preview)' ($x.r.status -eq 'pending_confirmation' -and $x.r.ticket_id -eq '12345') "$($x.r.status) $($x.r.ticket_id)"
$raw = @{ id = 12345; ticketNumber = 'T20261001.0001'; title = 'New VPN tunnel to Leeds'; contactID = 30 }
$x = Invoke-Routing $raw -Psa autotask -Wrap -Settings @('liveAssign: yes')
Check 'triage raw body + liveAssign yes assigns' ($x.r.status -eq 'success' -and $x.writes.Count -eq 2) "$($x.r.status) $($x.writes.Count)"
$x = Invoke-Routing @{ ticketId = '12345'; confirm = 'false' } -Settings @('liveAssign: yes')
Check 'body confirm false overrides liveAssign' ($x.r.status -eq 'pending_confirmation' -and $x.writes.Count -eq 0)
$x = Invoke-Routing $raw -Settings @('liveAssign: maybe')
Check 'invalid liveAssign stops' ($x.r.status -eq 'incomplete' -and $x.r.internal_note -match 'liveAssign')
$x = Invoke-Routing @{ ticket = @{ id = 12345 }; confirm = 'true' }
Check 'nested ticket.id' ($x.r.status -eq 'success')
$x = Invoke-Routing @{ ticketId = '{{ticket.id}}'; confirm = 'true' }
Check 'unreplaced placeholder is missing' ($x.r.status -eq 'incomplete')
$x = Invoke-Routing $body -Form table
Check 'article in table form' ($x.r.status -eq 'success' -and $x.r.assignee.name -eq 'Patel, Riya') "$($x.r.status): $($x.r.message)"
$global:FailAssign = $true
$x = Invoke-Routing $body
Check 'assign rejected is an error, no note' ($x.r.status -eq 'error' -and $x.writes.Count -eq 1) "$($x.r.status) $($x.writes.Count)"
$global:FailAssign = $false

Write-Host 'Prepare output for the classifier'
$x = Invoke-Routing @{ ticketId = '12345' }
Check 'skill list has 3 skills, no Role only' (@($x.prep.skillList -split "`n").Count -eq 3 -and $x.prep.skillList -notmatch 'Role only') $x.prep.skillList
Check 'skill list carries roles' ($x.prep.skillList -match 'Network Firewall Fortinet: FortiGate policy, VPN and SD-WAN changes \[roles: Tickets, Install\]') $x.prep.skillList
Check 'halo html stripped' ((Invoke-Routing @{ ticketId = '12345' } -Psa halopsa).prep.description -notmatch '<p>')

Write-Host 'Test-RoutingTable.ps1 (generated from the same parser)'
$validator = Join-Path $here '..\Test-RoutingTable.ps1'
$skillsCsv | Set-Content (Join-Path $tmp 'skills.csv'); New-EngineersCsv | Set-Content (Join-Path $tmp 'engineers.csv')
$v = & pwsh -NoProfile -File $validator -SkillsPath (Join-Path $tmp 'skills.csv') -EngineersPath (Join-Path $tmp 'engineers.csv') -Psa autotask 2>&1
Check 'validator passes the sample CSVs' ($LASTEXITCODE -eq 0 -and ($v -join "`n") -match 'No errors' -and ($v -join "`n") -match 'Skills:\s+3') ($v -join ' / ')
ConvertTo-TableHtml (@('[Settings]', 'tieBreak: busiest', '[Engineers]') + (New-EngineersCsv)) | Set-Content (Join-Path $tmp 'eng.html')
ConvertTo-PastedHtml (@('[Skills]') + $skillsCsv) | Set-Content (Join-Path $tmp 'skills.html')
$v = & pwsh -NoProfile -Command "& '$validator' -ArticleHtmlPath '$(Join-Path $tmp 'eng.html')','$(Join-Path $tmp 'skills.html')'; exit `$LASTEXITCODE" 2>&1
Check 'validator reads article HTML and fails a bad setting' ($LASTEXITCODE -eq 1 -and ($v -join "`n") -match "tieBreak 'busiest'" -and ($v -join "`n") -match 'Engineers named: 5; engineers table: 5') ($v -join ' / ')

$kb = Join-Path $here '..\kb-articles'
$v = & pwsh -NoProfile -Command "& '$validator' -ArticleHtmlPath '$(Join-Path $kb 'ticket-routing-engineers-and-settings.txt')','$(Join-Path $kb 'ticket-routing-skills.txt')' -Psa connectwise; exit `$LASTEXITCODE" 2>&1
Check 'shipped KB article templates pass the validator' ($LASTEXITCODE -eq 0 -and ($v -join "`n") -match 'Engineers named: 3; engineers table: 3' -and ($v -join "`n") -match 'liveAssign=no') ($v -join ' / ')

Remove-Item -Recurse -Force $tmp
"`n$global:Pass passed, $global:Fail failed"
if ($global:Fail) { exit 1 }
