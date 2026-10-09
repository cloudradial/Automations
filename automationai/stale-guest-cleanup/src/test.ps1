# Strict-mode harness for stale-guest-cleanup.yml. Runs the four steps exactly as they are in the .yml
# (extracted by build.js --extract), each through & ([scriptblock]::Create(...)) under
# Set-StrictMode -Version Latest, passing each step's output to the next as JSON the way the runner does.
# Mocks Get-AzKeyVaultSecret, Invoke-RestMethod, Get-NodeInput, Set-NodeOutput and Start-Sleep.
# Placeholder data only (Contoso, Example MSP).
# Usage: pwsh -NoProfile -File automationai/stale-guest-cleanup/src/test.ps1
#        (needs node and js-yaml; set JS_YAML_PATH if js-yaml isn't installed in automationai/_shared)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:RUNNER_KV_NAME = 'kv-test'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("sgc-test-" + [guid]::NewGuid().ToString('N'))
& node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { throw 'stale-guest-cleanup.yml is out of date. Run node build.js first.' }
& node (Join-Path $PSScriptRoot 'build.js') --extract $tmp | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the steps.' }
$StepIds = @('node-inputs', 'node-find', 'node-disable', 'node-report')
$Steps = @{}; foreach ($s in $StepIds) { $Steps[$s] = Get-Content -Raw (Join-Path $tmp "$s.ps1") }
Remove-Item -Recurse -Force $tmp

$Tally = @{ pass = 0; fail = 0 }
$Mock = @{ Secrets = @{}; Calls = (New-Object System.Collections.ArrayList); Opt = @{}; Notes = (New-Object System.Collections.ArrayList) }
function Get-AzKeyVaultSecret { [CmdletBinding()] param($VaultName, $Name, [switch]$AsPlainText) if ($Mock.Secrets.Contains($Name)) { return $Mock.Secrets[$Name] }; return $null }
function Start-Sleep { [CmdletBinding()] param([double]$Seconds = 0, [int]$Milliseconds = 0) }
function Get-NodeInput { return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function New-HttpError {
    param([int]$Code, [string]$Body = '')
    $r = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Code)
    $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new("Response status code does not indicate success: $Code.", $r)
    $er = [System.Management.Automation.ErrorRecord]::new($ex, 'WebCmdletWebResponseException', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
    if ($Body) { $er.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Body) }
    throw $er
}

function Get-Iso { param([int]$DaysAgo) return (Get-Date).ToUniversalTime().AddDays(-$DaysAgo).ToString('yyyy-MM-ddTHH:mm:ssZ') }
function New-U {
    param([string]$Id, [string]$Upn, [int]$Created, $Last = $null, $NonInt = $null, [string]$Type = 'Member', [bool]$Enabled = $true, [bool]$Synced = $false)
    if ($Mock.Opt.Contains('DisabledIds') -and @($Mock.Opt['DisabledIds']) -contains $Id) { $Enabled = $false }
    $sia = $null
    if ($null -ne $Last -or $null -ne $NonInt) { $sia = [pscustomobject]@{ lastSignInDateTime = $(if ($null -ne $Last) { Get-Iso $Last }); lastNonInteractiveSignInDateTime = $(if ($null -ne $NonInt) { Get-Iso $NonInt }); lastSuccessfulSignInDateTime = $null } }
    return [pscustomobject]@{ id = $Id; userPrincipalName = $Upn; displayName = ($Upn -split '@')[0]; mail = $Upn; accountEnabled = $Enabled; userType = $Type
        createdDateTime = (Get-Iso $Created); onPremisesSyncEnabled = $(if ($Synced) { $true } else { $null }); signInActivity = $sia }
}
function Get-Users {
    if ($Mock.Opt.Contains('AllActive')) { return @((New-U 'aaaaaaaa-0000-0000-0000-000000000001' 'active@contoso.com' 400 5), (New-U 'aaaaaaaa-0000-0000-0000-000000000004' 'new.starter@contoso.com' 10)) }
    return @(
        (New-U 'aaaaaaaa-0000-0000-0000-000000000001' 'active@contoso.com' 400 5),
        (New-U 'aaaaaaaa-0000-0000-0000-000000000002' 'stale.member@contoso.com' 400 120 100),
        (New-U 'aaaaaaaa-0000-0000-0000-000000000003' 'never.member@contoso.com' 200),
        (New-U 'aaaaaaaa-0000-0000-0000-000000000004' 'new.starter@contoso.com' 10),
        (New-U 'aaaaaaaa-0000-0000-0000-000000000005' 'already.off@contoso.com' 400 300 -Enabled $false),
        (New-U 'aaaaaaaa-0000-0000-0000-000000000006' 'partner_example-msp.com#EXT#@contoso.com' 300 150 -Type 'Guest'),
        (New-U 'aaaaaaaa-0000-0000-0000-000000000007' 'vendor_example.org#EXT#@contoso.com' 200 -Type 'Guest'),
        (New-U 'aaaaaaaa-0000-0000-0000-000000000008' 'newguest_example.org#EXT#@contoso.com' 20 -Type 'Guest'),
        (New-U 'aaaaaaaa-0000-0000-0000-000000000009' 'old.admin@contoso.com' 900 200),
        (New-U 'aaaaaaaa-0000-0000-0000-000000000010' 'synced.user@contoso.com' 900 180 -Synced $true),
        (New-U 'aaaaaaaa-0000-0000-0000-000000000011' 'group.admin@contoso.com' 900 365),
        (New-U 'aaaaaaaa-0000-0000-0000-000000000012' 'background.only@contoso.com' 900 200 3))
}

# Like the real cmdlet, a JSON array reply is handed back as ONE object (", @(...)"), not item by item, and
# -MaximumRedirection is accepted (recorded as MaxRedirect, -1 when not sent) so the shared PSA code takes its no-redirect path.
function Invoke-RestMethod {
    [CmdletBinding()] param($Method = 'GET', $Uri, $Headers, $Body, $ContentType, $Form, [int]$MaximumRedirection = -1)
    $m = ([string]$Method).ToUpperInvariant(); $u = [string]$Uri
    $null = $Mock.Calls.Add([pscustomobject]@{ MaxRedirect = $MaximumRedirection; Method = $m; Uri = $u; Body = $(if ($Body -is [string]) { $Body } else { '' }) })
    if ($u -like 'https://login.microsoftonline.com/*') { return [pscustomobject]@{ access_token = 'mock'; expires_in = 3600 } }
    if ($u -like 'https://graph.microsoft.com/v1.0/users[?]*') {
        if ($Mock.Opt.Contains('Users403')) { New-HttpError 403 $Mock.Opt['Users403'] }
        $all = @(Get-Users)
        if ($u -like '*page=2*') { return [pscustomobject]@{ value = @($all | Select-Object -Skip 6) } }
        if ($all.Count -le 6) { return [pscustomobject]@{ value = $all } }
        return [pscustomobject]@{ value = @($all | Select-Object -First 6); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?page=2' }
    }
    if ($u -like 'https://graph.microsoft.com/v1.0/directoryRoles*') {
        if ($Mock.Opt.Contains('Roles403')) { New-HttpError 403 '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}' }
        return [pscustomobject]@{ value = @(
                [pscustomobject]@{ id = 'r1'; displayName = 'Global Administrator'; members = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.user'; id = 'aaaaaaaa-0000-0000-0000-000000000009' }) },
                [pscustomobject]@{ id = 'r2'; displayName = 'Exchange Administrator'; members = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.group'; id = 'g-admins' }) }) }
    }
    if ($u -like 'https://graph.microsoft.com/v1.0/groups/g-admins/transitiveMembers*') { return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'aaaaaaaa-0000-0000-0000-000000000011' }) } }
    if ($m -eq 'PATCH' -and $u -like 'https://graph.microsoft.com/v1.0/users/*') {
        if ($Mock.Opt.Contains('FailPatch') -and $u -like "*/$($Mock.Opt['FailPatch'])") { New-HttpError 500 '{"error":{"message":"Mock server error"}}' }
        return $null
    }
    if ($m -eq 'POST' -and $u -like 'https://graph.microsoft.com/v1.0/users/*/revokeSignInSessions') { return [pscustomobject]@{ value = $true } }
    if ($u -like 'https://portal.example-msp.test/api/beta/archive*' -and $m -eq 'GET') { return , @([pscustomobject]@{ id = 55; companyId = 9; name = 'Account Reviews' }) }
    if ($u -like 'https://portal.example-msp.test/v2/odata/archiveitem*') { return [pscustomobject]@{ value = @() } }
    if ($u -eq 'https://portal.example-msp.test/v2/archiveitem' -and $m -eq 'POST') { return [pscustomobject]@{ companyReportItemId = 777 } }
    # Ticket notes are kept in $Mock.Notes, so a rerun (KeepNotes) sees what the first run wrote.
    if ($u -like 'https://cw.example-msp.test/*/service/tickets/*/notes' -and $m -eq 'POST') {
        $b = $Body | ConvertFrom-Json; $null = $Mock.Notes.Add([pscustomobject]@{ id = $Mock.Notes.Count + 1; text = $b.text; internalAnalysisFlag = $b.internalAnalysisFlag; detailDescriptionFlag = $b.detailDescriptionFlag })
        return [pscustomobject]@{ id = $Mock.Notes.Count }
    }
    if ($u -like 'https://cw.example-msp.test/*/service/tickets/*/notes[?]*' -and $m -eq 'GET') { if ($u -like '*page=1') { return , @($Mock.Notes) }; return , @() }
    if ($u -like 'https://examplemsp.zendesk.test/api/v2/tickets/*' -and $m -eq 'PUT') {
        $c = ($Body | ConvertFrom-Json).ticket.comment; $null = $Mock.Notes.Add([pscustomobject]@{ id = $Mock.Notes.Count + 1; body = $c.body; public = $c.public; author_id = 1 })
        return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 123 } }
    }
    if ($u -like 'https://examplemsp.zendesk.test/api/v2/tickets/*/comments*' -and $m -eq 'GET') { return [pscustomobject]@{ comments = @($Mock.Notes); next_page = $null } }
    throw "Unmocked call: $m $u"
}

function Get-Calls { param([string]$Method, [string]$Like) return @($Mock.Calls | Where-Object { $_.Method -eq $Method -and $_.Uri -like $Like }) }
function Check { param([string]$Name, [bool]$Ok, $Detail = '') if ($Ok) { $Tally.pass++; Write-Host "PASS $Name" } else { $Tally.fail++; Write-Host "FAIL $Name :: $Detail" -ForegroundColor Red } }
function RoundTrip { param($o) if ($null -eq $o) { return $null }; return ($o | ConvertTo-Json -Depth 30 | ConvertFrom-Json) }

$BaseSecrets = @{
    'M365-TenantId' = '00000000-0000-0000-0000-000000000000'; 'M365-ClientId' = 'cid'; 'M365-ClientSecret' = 'sec'
    'CloudRadial-BaseUrl' = 'https://portal.example-msp.test'; 'CloudRadial-PublicKey' = 'pub'; 'CloudRadial-PrivateKey' = 'priv'
    'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://cw.example-msp.test/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'p'; 'CW-PrivateKey' = 'k'; 'CW-ClientId' = 'c'
    'Zendesk-BaseUrl' = 'https://examplemsp.zendesk.test'; 'Zendesk-Email' = 'agent@example-msp.test'; 'Zendesk-ApiToken' = 't'
}

# Runs the workflow. Returns @{ out; error; stepReached }.
function Invoke-Workflow {
    param($RunInput, [hashtable]$Secrets = @{}, [hashtable]$Opt = @{})
    $Mock.Secrets = $BaseSecrets.Clone(); foreach ($k in $Secrets.Keys) { if ($null -eq $Secrets[$k]) { $Mock.Secrets.Remove($k) } else { $Mock.Secrets[$k] = $Secrets[$k] } }
    $Mock.Calls.Clear(); $Mock.Opt = $Opt
    if (-not $Opt.Contains('KeepNotes')) { $Mock.Notes.Clear() }
    $global:NodeIn = $(if ($RunInput -is [string] -or $null -eq $RunInput) { $RunInput } else { RoundTrip $RunInput })
    $global:NodeOut = $null
    foreach ($s in $StepIds) {
        try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps[$s])) }
        catch { return @{ out = (RoundTrip $global:NodeOut); error = [string]$_.Exception.Message; step = $s } }
        $global:NodeIn = RoundTrip $global:NodeOut
    }
    return @{ out = $global:NodeIn; error = ''; step = 'end' }
}
function Get-Writes { return @($Mock.Calls | Where-Object { $_.Method -in @('PATCH', 'POST', 'PUT', 'DELETE') -and $_.Uri -like 'https://graph.microsoft.com/*' }) }

# 1. Preview with a ConnectWise ticket.
$r = Invoke-Workflow @{ ticket_id = '123'; company_id = '9' }
$o = $r.out
Check 'preview: no error' ($r.error -eq '') $r.error
Check 'preview: status pending_confirmation' ($o.status -eq 'pending_confirmation') $o.status
$upns = @($o.candidates | ForEach-Object { $_.upn })
Check 'preview: 7 inactive accounts' ($upns.Count -eq 7) ($upns -join ', ')
Check 'preview: active, new, disabled, recent guest, background sign-in skipped' (-not (@('active@contoso.com', 'new.starter@contoso.com', 'already.off@contoso.com', 'newguest_example.org#EXT#@contoso.com', 'background.only@contoso.com') | Where-Object { $upns -contains $_ })) ($upns -join ', ')
Check 'preview: never-signed-in member listed' ($upns -contains 'never.member@contoso.com') ''
Check 'preview: never-signed-in guest listed' ($upns -contains 'vendor_example.org#EXT#@contoso.com') ''
$adm = @($o.candidates | Where-Object { $_.flag -eq 'admin' } | ForEach-Object { $_.upn })
Check 'preview: direct and group admins flagged' ($adm.Count -eq 2 -and $adm -contains 'old.admin@contoso.com' -and $adm -contains 'group.admin@contoso.com') ($adm -join ', ')
Check 'preview: synced account flagged' (@($o.candidates | Where-Object { $_.flag -eq 'synced' }).Count -eq 1) ''
Check 'preview: counts' ($o.counts.inactive_members -eq 5 -and $o.counts.inactive_guests -eq 2 -and $o.counts.can_disable -eq 4 -and $o.counts.users_read -eq 12) ($o.counts | ConvertTo-Json -Compress)
Check 'preview: paging followed' (@(Get-Calls GET '*users[?]page=2*').Count -eq 1) ''
Check 'preview: never-signed-in sorted first' ([bool]$o.candidates[0].never_signed_in) $o.candidates[0].upn
Check 'preview: no Graph writes' (@(Get-Writes).Count -eq 0) (@(Get-Writes | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')
$arch = @(Get-Calls POST 'https://portal.example-msp.test/v2/archiveitem')
Check 'preview: report written to archive' ($arch.Count -eq 1 -and $o.report.action -eq 'created') "$($arch.Count) $($o.report.action)"
$ab = $arch[0].Body | ConvertFrom-Json
Check 'preview: report is HTML in archive 55 with the subject' ($ab.isHtml -and $ab.archiveId -eq 55 -and $ab.subject -like 'Inactive accounts review *' -and $ab.text -match 'old\.admin@contoso\.com' -and $ab.text -match 'Never') $ab.subject
$note = @(Get-Calls POST 'https://cw.example-msp.test/*/service/tickets/123/notes')
Check 'preview: ConnectWise internal note' ($note.Count -eq 1 -and ($note[0].Body | ConvertFrom-Json).internalAnalysisFlag -eq $true) ''
Check 'preview: note points at the archive' (($note[0].Body | ConvertFrom-Json).text -match 'Account Reviews') ''
Check 'ConnectWise calls are sent with -MaximumRedirection 0' ((@($Mock.Calls | Where-Object { $_.Uri -like 'https://cw.example-msp.test/*' }).Count -gt 0) -and -not @($Mock.Calls | Where-Object { $_.Uri -like 'https://cw.example-msp.test/*' -and $_.MaxRedirect -ne 0 }).Count) (@($Mock.Calls | Where-Object { $_.Uri -like 'https://cw.example-msp.test/*' } | ForEach-Object { "$($_.Method) $($_.MaxRedirect)" }) -join ', ')
Check 'preview: message is plain and says nothing changed' ($o.message -match 'Nothing was changed' -and $o.message -match '7 accounts have not signed in for 90 days') $o.message
Check 'preview: no report_html when archived' ($null -eq $o.PSObject.Properties['report_html']) ''
$nt = ($note[0].Body | ConvertFrom-Json).text
Check 'preview: note ends with the review marker (no names in it)' ($nt -match "\n\[stale-guest-cleanup: review \d{4}-\d{2}-\d{2} 90d with guests\]$") $nt

# 1b. Rerun (ServiceAI Retry, or the Routine running twice): writes no second note.
$r = Invoke-Workflow @{ ticket_id = '123'; company_id = '9' } @{} @{ KeepNotes = $true }
Check 'rerun preview: no error' ($r.error -eq '') $r.error
Check 'rerun preview: no second ConnectWise note' (@(Get-Calls POST 'https://cw.example-msp.test/*/notes').Count -eq 0 -and $Mock.Notes.Count -eq 1) "$($Mock.Notes.Count) notes"
Check 'rerun preview: says the note was already there' ((@($r.out.actions) -join ' ') -match 'already on ticket 123') (@($r.out.actions) -join ' | ')

# 2. Guests excluded, company id from the secret, no ticket.
$r = Invoke-Workflow @{ include_guests = 'false' } @{ 'CloudRadial-CompanyId' = '9' }
$o = $r.out
Check 'no guests: only members listed' (@($o.candidates | Where-Object { $_.kind -eq 'guest' }).Count -eq 0 -and @($o.candidates).Count -eq 5) (@($o.candidates | ForEach-Object { $_.upn }) -join ', ')
Check 'no guests: secret company id used' (@(Get-Calls POST '*/v2/archiveitem').Count -eq 1) ''
Check 'no guests: no PSA call without ticket' (@($Mock.Calls | Where-Object { $_.Uri -like 'https://cw.*' }).Count -eq 0) ''

# 3. Confirm with Zendesk: two valid, one admin, one unknown, one guest by UPN.
$r = Invoke-Workflow @{ confirm = 'true'; psa = 'zendesk'; ticket_id = '123'; company_id = '9'; disable_ids = 'aaaaaaaa-0000-0000-0000-000000000002, vendor_example.org#EXT#@contoso.com;aaaaaaaa-0000-0000-0000-000000000009 ffffffff-ffff-ffff-ffff-ffffffffffff active@contoso.com not-an-id' }
$o = $r.out
Check 'confirm: no error' ($r.error -eq '') $r.error
Check 'confirm: status success' ($o.status -eq 'success') "$($o.status) $($o.message)"
$patches = @(Get-Calls PATCH 'https://graph.microsoft.com/v1.0/users/*')
Check 'confirm: two accounts disabled' ($patches.Count -eq 2 -and ($patches[0].Body | ConvertFrom-Json).accountEnabled -eq $false) (@($patches | ForEach-Object { $_.Uri }) -join '; ')
Check 'confirm: guest disabled by UPN resolves to its id' (@($patches | Where-Object { $_.Uri -like '*/users/aaaaaaaa-0000-0000-0000-000000000007' }).Count -eq 1) ''
Check 'confirm: sessions revoked for both' (@(Get-Calls POST '*/revokeSignInSessions').Count -eq 2) ''
Check 'confirm: admin never disabled' (@(Get-Calls PATCH '*/users/aaaaaaaa-0000-0000-0000-000000000009').Count -eq 0) ''
Check 'confirm: active account never disabled' (@(Get-Calls PATCH '*/users/aaaaaaaa-0000-0000-0000-000000000001').Count -eq 0) ''
Check 'confirm: three skipped with reasons' (@($o.skipped).Count -eq 3 -and (@($o.skipped | ForEach-Object { $_.reason }) -join ' ') -match 'admin role') (@($o.skipped | ForEach-Object { "$($_.requested): $($_.reason)" }) -join ' | ')
Check 'confirm: bad id warned' ((@($o.warnings) -join ' ') -match "Ignored 'not-an-id'") (@($o.warnings) -join ' | ')
$zd = @(Get-Calls PUT 'https://examplemsp.zendesk.test/api/v2/tickets/123')
Check 'confirm: Zendesk private note' ($zd.Count -eq 1 -and ($zd[0].Body | ConvertFrom-Json).ticket.comment.public -eq $false) ''
Check 'confirm: note lists the disabled accounts' (($zd[0].Body | ConvertFrom-Json).ticket.comment.body -match 'stale\.member@contoso\.com') ''
$cb = @(Get-Calls POST '*/v2/archiveitem')[0].Body | ConvertFrom-Json
Check 'confirm: change log written to archive' ($cb.subject -like 'Inactive accounts changes *' -and $cb.text -match 'sign-in turned off and signed out of every session') $cb.subject
Check 'confirm: disabled list output' (@($o.disabled).Count -eq 2) (@($o.disabled) -join ', ')
$zb = ($zd[0].Body | ConvertFrom-Json).ticket.comment.body
$zLast = @($zb -split "`n")[-1]
Check 'confirm: marker is a hash, with no sign-in names' ($zLast -match '^\[stale-guest-cleanup: disable [0-9a-f]{8}\]$' -and $zLast -notmatch '@|contoso|aaaaaaaa') $zLast

# 3b. Rerun of the same confirm after it worked: the two accounts are now disabled, so nothing is written again.
$r = Invoke-Workflow @{ confirm = 'true'; psa = 'zendesk'; ticket_id = '123'; company_id = '9'; disable_ids = 'aaaaaaaa-0000-0000-0000-000000000002, vendor_example.org#EXT#@contoso.com;aaaaaaaa-0000-0000-0000-000000000009 ffffffff-ffff-ffff-ffff-ffffffffffff active@contoso.com not-an-id' } @{} @{ KeepNotes = $true; DisabledIds = @('aaaaaaaa-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000007') }
Check 'rerun confirm: no Graph writes' (@(Get-Writes).Count -eq 0) (@(Get-Writes | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')
Check 'rerun confirm: no second Zendesk note' (@(Get-Calls PUT 'https://examplemsp.zendesk.test/*').Count -eq 0 -and $Mock.Notes.Count -eq 1) "$($Mock.Notes.Count) notes"
Check 'rerun confirm: says the note was already there' ((@($r.out.actions) -join ' ') -match 'already on ticket 123') (@($r.out.actions) -join ' | ')

# 4. Confirm where the second disable fails: stops and says what didn't run.
$r = Invoke-Workflow @{ confirm = $true; company_id = '9'; disable_ids = 'aaaaaaaa-0000-0000-0000-000000000002,aaaaaaaa-0000-0000-0000-000000000003' } @{} @{ FailPatch = 'aaaaaaaa-0000-0000-0000-000000000003' }
$o = $r.out
Check 'failure: status error' ($o.status -eq 'error') "$($o.status) $($o.message)"
Check 'failure: first account still reported disabled' (@($o.disabled).Count -eq 1 -and $o.message -match 'Disabled 1 account') $o.message
Check 'failure: sign-out for the failed account not run' ($o.message -match 'Not run: Sign never\.member@contoso\.com out') $o.message
Check 'failure: report marked as error' ((@(Get-Calls POST '*/v2/archiveitem')[0].Body | ConvertFrom-Json).isError -eq $true) ''

# 5. Missing AuditLog.Read.All: plain message, nothing written.
$r = Invoke-Workflow @{ ticket_id = '123'; company_id = '9' } @{} @{ Users403 = '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}' }
Check '403: run fails in Find step' ($r.step -eq 'node-find') $r.step
Check '403: plain permission message' ($r.error -eq "Can't read last sign-in times. The app registration needs the AuditLog.Read.All application permission (with User.Read.All), with admin consent. Nothing was changed.") $r.error
Check '403: output status error' ($r.out.status -eq 'error') ''
Check '403: no writes anywhere' (@($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and $_.Uri -notlike 'https://login.*' }).Count -eq 0) ''

# 6. Tenant without Entra ID P1.
$r = Invoke-Workflow @{} @{} @{ Users403 = '{"error":{"code":"Authentication_RequestFromNonPremiumTenantOrB2CTenant","message":"Neither tenant is B2C or tenant doesn''t have premium license"}}' }
Check 'no P1: says Entra ID P1' ($r.error -match 'Entra ID P1') $r.error

# 7. Missing role-read permission.
$r = Invoke-Workflow @{} @{} @{ Roles403 = $true }
Check 'roles 403: names RoleManagement.Read.Directory' ($r.error -match 'RoleManagement\.Read\.Directory application permission' -and $r.step -eq 'node-find') $r.error

# 8. Empty result: everyone active.
$r = Invoke-Workflow @{ company_id = '9'; ticket_id = '123' } @{} @{ AllActive = $true }
$o = $r.out
Check 'empty: success with no candidates' ($r.error -eq '' -and $o.status -eq 'success' -and @($o.candidates).Count -eq 0) "$($o.status) $($r.error)"
Check 'empty: plain message' ($o.message -match 'No Microsoft 365 accounts and guests have gone 90 days without signing in') $o.message
Check 'empty: report still written' (@(Get-Calls POST '*/v2/archiveitem').Count -eq 1) ''

# 9. Monthly Routine: no input at all, no company id anywhere.
$r = Invoke-Workflow $null
$o = $r.out
Check 'routine: defaults applied' ($r.error -eq '' -and $o.days -eq 90 -and $o.confirm -eq $false) "$($r.error)"
Check 'routine: no company id -> warning and report_html' ((@($o.warnings) -join ' ') -match 'No CloudRadial company id' -and $o.report_html -match '<table') ''
Check 'routine: no CloudRadial calls' (@($Mock.Calls | Where-Object { $_.Uri -like 'https://portal.*' }).Count -eq 0) ''
Check 'routine: no Graph writes' (@(Get-Writes).Count -eq 0) ''

# 10. Bad input fails closed before any call.
$r = Invoke-Workflow @{ days = 'ninety' }
Check 'bad days: incomplete in Read inputs' ($r.step -eq 'node-inputs' -and $r.out.status -eq 'incomplete' -and $r.error -match 'whole number') $r.error
Check 'bad days: no calls' ($Mock.Calls.Count -eq 0) ''

# 11. Confirm with nothing listed.
$r = Invoke-Workflow @{ confirm = 'yes'; company_id = '9' }
Check 'confirm without ids: incomplete, no writes' ($r.out.status -eq 'incomplete' -and @(Get-Writes).Count -eq 0) "$($r.out.status) $($r.out.message)"

# 12. Confirm where nothing requested is eligible.
$r = Invoke-Workflow @{ confirm = 'true'; company_id = '9'; disable_ids = 'old.admin@contoso.com,aaaaaaaa-0000-0000-0000-000000000010' }
Check 'confirm only flagged: rejected, no writes' ($r.out.status -eq 'rejected' -and @(Get-Writes).Count -eq 0 -and @($r.out.skipped).Count -eq 2) "$($r.out.status) $($r.out.message)"

# 13. Preview with ids lists what would be disabled.
$r = Invoke-Workflow @{ company_id = '9'; disable_ids = 'aaaaaaaa-0000-0000-0000-000000000002' }
Check 'preview with ids: says what would be disabled' ($r.out.message -match 'this run would disable: stale\.member@contoso\.com' -and @(Get-Writes).Count -eq 0) $r.out.message

# 14. Wrong tenant is rejected.
$r = Invoke-Workflow @{ tenant_id = '11111111-1111-1111-1111-111111111111' }
Check 'wrong tenant: rejected before reading users' ($r.out.status -eq 'rejected' -and @(Get-Calls GET '*v1.0/users[?]*').Count -eq 0) "$($r.out.status) $($r.error)"

# 15. Archive failure keeps the report in the output.
$r = Invoke-Workflow @{ company_id = '9' } @{ 'CloudRadial-PrivateKey' = $null }
Check 'archive failure: warning and report_html' ($r.error -eq '' -and (@($r.out.warnings) -join ' ') -match "Couldn't write the report" -and $r.out.report_html -match '<h2>') (@($r.out.warnings) -join ' | ')

Write-Host "$($Tally.pass) passed, $($Tally.fail) failed"
if ($Tally.fail) { exit 1 }
exit 0
