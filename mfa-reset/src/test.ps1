# Strict-mode harness for Self-Service MFA Reset.
# Runs each PowerShell step exactly as it is in mfa-reset.yml (shared libraries included), through
# & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the runner Key Vault,
# Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked. Outputs pass through JSON between steps,
# as the runner does. Placeholder data only (Contoso, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a same-named step
# variable would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File mfa-reset/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

# ---- the steps, straight from the built workflow ----
$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\mfa-reset.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.type==='powershell-script')o[a.id]=a.properties.script;}console.log(JSON.stringify(o));"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow has parse, verify and reset steps' ($Steps.Contains('parse') -and $Steps.Contains('verify') -and $Steps.Contains('reset'))
$TParams = (& $node -e "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));console.log(JSON.stringify(d.definition.activities.filter(a=>a.type==='powershell-script').map(a=>({id:a.id,p:a.properties.parameters}))))" $yml) | ConvertFrom-Json
Check 'first step binds trigger = {{ nodes.trigger.output }} (Password Reset pattern); later steps unbound' ((@($TParams | Where-Object { $_.id -eq 'parse' })[0].p | ConvertTo-Json -Compress) -eq '{"name":"trigger","expression":"{{ nodes.trigger.output }}"}' -and -not @($TParams | Where-Object { $_.id -ne 'parse' -and @($_.p).Count }).Count) ($TParams | ConvertTo-Json -Compress -Depth 5)

# ---- runner mocks ----
$global:NodeIn = $null; $global:NodeOut = $null
function Get-NodeInput { param([string]$Name) return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Invoke-Step {
    param([string]$Id, $In = $null)
    $global:NodeIn = $In; $global:NodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps[$Id])) } catch { $err = [string]$_.Exception.Message }
    $o = $null; if ($null -ne $global:NodeOut) { $o = ($global:NodeOut | ConvertTo-Json -Depth 12 | ConvertFrom-Json) }
    return @{ out = $o; error = $err }
}
# parse -> verify -> reset, each step reading the previous step's output (no bindings).
# By default the body arrives the way the runner hands it over with the "trigger" parameter bound
# ({trigger: <body>}, as in Password Reset); -Manual passes it unwrapped, like a manual Run input.
function Invoke-Flow {
    param($Body, [switch]$Manual)
    $TIn = $Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    if (-not $Manual) { $TIn = @{ trigger = $TIn } }
    $p = Invoke-Step 'parse' $TIn
    if ($p.error) { return @{ stage = 'parse'; r = $p } }
    $v = Invoke-Step 'verify' $p.out
    if ($v.error) { return @{ stage = 'verify'; r = $v } }
    $r = Invoke-Step 'reset' $v.out
    return @{ stage = 'reset'; r = $r; verify = $v.out }
}

# ---- placeholder data ----
$TTenant = '11111111-2222-3333-4444-555555555555'
$TGraphSecrets = @{ 'M365-TenantId' = $TTenant; 'M365-ClientId' = 'client-id'; 'M365-ClientSecret' = 'client-secret' }
$TPsa = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://cw.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
    none        = @{}
}
function Get-TSecrets { param([string]$P) $s = @{}; foreach ($k in $TGraphSecrets.Keys) { $s[$k] = $TGraphSecrets[$k] }; foreach ($k in $TPsa[$P].Keys) { $s[$k] = $TPsa[$P][$k] }; return $s }
$TCW = 'https://cw.example.com/v4_6_release/apis/3.0'; $TAT = 'https://webservices.autotask.example/atservicesrest/v1.0'; $TZD = 'https://example.zendesk.com/api/v2'
$TG = 'https://graph.microsoft.com/v1.0'; $TGB = 'https://graph.microsoft.com/beta'
$TTapCode = 'TAP-PLACEHOLDER-0000'

$TMethods = @{
    full = @(
        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.passwordAuthenticationMethod'; id = '28c10230-6103-485e-b985-444c60001490' }
        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'; id = 'ma1'; displayName = 'Megan iPhone' }
        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.phoneAuthenticationMethod'; id = 'ph1'; phoneNumber = '+1 555 010 4321'; phoneType = 'mobile' }
        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.fido2AuthenticationMethod'; id = 'fd1'; displayName = 'YubiKey'; model = 'YubiKey 5 NFC' }
        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.temporaryAccessPassAuthenticationMethod'; id = 'tp1' }
    )
    pwOnly = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.passwordAuthenticationMethod'; id = 'pw' })
    hw = @(
        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.passwordAuthenticationMethod'; id = 'pw' }
        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.phoneAuthenticationMethod'; id = 'ph1'; phoneNumber = '+1 555 010 4321'; phoneType = 'mobile' }
        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.hardwareOathAuthenticationMethod'; id = 'hw1' }
    )
}
function Reset-TScenario {
    $global:TS = @{ methods = 'full'; enabled = $true; direct = $false; group = $false; eligible = $false; eligibleLicense = $false
        risk = 'none'; riskForbidden = $false; authForbidden = $false; roleForbidden = $false; tap = 'ok'; phoneDefaultFirst = $false
        revokeFail = $false; atCompany = 42 }
    # Notes written to each ticket, read back by the retry guard (Test-PsaNoteMarker).
    $global:TNotes = @{}
}
function Add-TNote { param([string]$T, [string]$Text, [bool]$Public) if (-not $global:TNotes.Contains($T)) { $global:TNotes[$T] = @() }; $global:TNotes[$T] += [pscustomobject]@{ text = $Text; public = $Public } }
function Get-TNotes { param([string]$T) if ($global:TNotes.Contains($T)) { return @($global:TNotes[$T]) }; return @() }
Reset-TScenario

$Handler = {
    param($c, $n)
    $k = "$($c.Method) $($c.Uri)"
    $S = $global:TS
    switch -Wildcard -CaseSensitive ($k) {
        'POST https://login.microsoftonline.com/*' { return [pscustomobject]@{ access_token = 'graph-token'; expires_in = 3600 } }
        "GET $TG/users/megan.bowen%40contoso.com*" { return [pscustomobject]@{ id = 'u1'; userPrincipalName = 'megan.bowen@contoso.com'; displayName = 'Megan Bowen'; mail = 'megan.bowen@contoso.com'; proxyAddresses = @('SMTP:megan.bowen@contoso.com', 'smtp:megan@contoso.example'); accountEnabled = $S.enabled } }
        "GET $TG/users/alex.wilber%40contoso.com*" { return [pscustomobject]@{ id = 'u2'; userPrincipalName = 'alex.wilber@contoso.com'; displayName = 'Alex Wilber'; mail = 'alex.wilber@contoso.com'; proxyAddresses = @(); accountEnabled = $true } }
        "GET $TG/users/nobody%40contoso.com*" { New-HttpError 404 '{"error":{"message":"Resource not found"}}' }
        "GET $TG/roleManagement/directory/roleAssignments*" {
            if ($S.roleForbidden) { New-HttpError 403 '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}' }
            if ($S.direct) { return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'ra1'; principalId = 'u1'; roleDefinitionId = '62e90394-69f5-4237-9190-012177145e10' }) } }
            return [pscustomobject]@{ value = @() }
        }
        "GET $TGB/roleManagement/directory/transitiveRoleAssignments*" {
            if ($S.group) { return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'ra2'; principalId = 'grp1'; roleDefinitionId = '729827e3-9c14-49f7-bb1b-9608f156bbb8' }) } }
            return [pscustomobject]@{ value = @() }
        }
        "GET $TG/roleManagement/directory/roleEligibilityScheduleInstances*" {
            if ($S.eligibleLicense) { New-HttpError 400 '{"error":{"code":"AadPremiumLicenseRequired","message":"The tenant needs an AAD Premium 2 license."}}' }
            if ($S.eligible) { return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'el1'; principalId = 'u1'; roleDefinitionId = 'fe930be7-5e62-47db-91af-98c3a49a38b1' }) } }
            return [pscustomobject]@{ value = @() }
        }
        "GET $TG/roleManagement/directory/roleDefinitions/62e90394*" { return [pscustomobject]@{ displayName = 'Global Administrator' } }
        "GET $TG/roleManagement/directory/roleDefinitions/729827e3*" { return [pscustomobject]@{ displayName = 'Helpdesk Administrator' } }
        "GET $TG/roleManagement/directory/roleDefinitions/*" { return [pscustomobject]@{ displayName = 'User Administrator' } }
        "GET $TG/identityProtection/riskyUsers/u1" {
            if ($S.riskForbidden) { New-HttpError 403 '{"error":{"message":"Insufficient privileges."}}' }
            if ($S.risk -eq 'none') { New-HttpError 404 '{"error":{"message":"Not found"}}' }
            if ($S.risk -eq 'atRisk') { return [pscustomobject]@{ id = 'u1'; riskLevel = 'medium'; riskState = 'atRisk' } }
            return [pscustomobject]@{ id = 'u1'; riskLevel = 'none'; riskState = 'remediated' }
        }
        "GET $TG/users/u1/authentication/methods" {
            if ($S.authForbidden) { New-HttpError 403 '{"error":{"code":"accessDenied","message":"Request Authorization failed"}}' }
            return [pscustomobject]@{ value = @($TMethods[$S.methods]) }
        }
        "DELETE $TG/users/u1/authentication/phoneMethods/*" { if ($S.phoneDefaultFirst -and $n -eq 1) { New-HttpError 400 '{"error":{"code":"badRequest","message":"Cannot delete the default method while other methods are registered."}}' }; return $null }
        "DELETE $TG/users/u1/authentication/*" { return $null }
        "POST $TG/users/u1/revokeSignInSessions" { if ($S.revokeFail) { New-HttpError 403 '{"error":{"message":"Insufficient privileges."}}' }; return [pscustomobject]@{ value = $true } }
        "POST $TG/users/u1/authentication/temporaryAccessPassMethods" {
            if ($S.tap -eq 'policy') { New-HttpError 400 '{"error":{"code":"badRequest","message":"Temporary Access Pass policy is not enabled for this user."}}' }
            return [pscustomobject]@{ id = 'newtap'; temporaryAccessPass = $TTapCode; startDateTime = '2026-10-07T15:00:00Z'; lifetimeInMinutes = 60; isUsableOnce = $true }
        }
        "GET $TCW/service/tickets/777/notes*" { $i = 0; return , @(Get-TNotes '777' | ForEach-Object { $i++; [pscustomobject]@{ id = $i; text = $_.text; internalAnalysisFlag = (-not $_.public); detailDescriptionFlag = $_.public; dateCreated = '2026-10-08T10:00:00Z' } }) }
        "GET $TCW/service/tickets/777" { return [pscustomobject]@{ id = 777; summary = 'Reset my MFA'; company = [pscustomobject]@{ id = 42 }; owner = $null; status = [pscustomobject]@{ name = 'New' } } }
        "POST $TCW/service/tickets/777/notes" { $b = $c.Body | ConvertFrom-Json; Add-TNote '777' $b.text ([bool]$b.detailDescriptionFlag); return [pscustomobject]@{ id = 9001 } }
        "GET $TAT/TicketNotes/entityInformation/fields" { return [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                    [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '13'; label = 'System Workflow Note'; isActive = $true }, [pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) } }
        "GET $TAT/Tickets/12345" { return [pscustomobject]@{ item = [pscustomobject]@{ id = 12345; title = 'MFA reset'; description = ''; companyID = $S.atCompany; status = 1; assignedResourceID = $null } } }
        "POST $TAT/Tickets/12345/Notes" { $b = $c.Body | ConvertFrom-Json; Add-TNote '12345' $b.description ($b.publish -ne 2); return [pscustomobject]@{ itemId = 3001 } }
        "GET $TAT/TicketNotes/query*" { $i = 0; return [pscustomobject]@{ items = @(Get-TNotes '12345' | ForEach-Object { $i++; [pscustomobject]@{ id = $i; ticketID = 12345; title = 'MFA reset'; description = $_.text; publish = $(if ($_.public) { 1 } else { 2 }); createDateTime = '2026-10-08T10:00:00Z' } }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
        "PUT $TZD/tickets/506" { $b = $c.Body | ConvertFrom-Json; Add-TNote '506' $b.ticket.comment.body ([bool]$b.ticket.comment.public); return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 506 } } }
        "GET $TZD/tickets/506/comments*" { $i = 0; return [pscustomobject]@{ comments = @(Get-TNotes '506' | ForEach-Object { $i++; [pscustomobject]@{ id = $i; body = $_.text; public = $_.public; author_id = 1; created_at = '2026-10-08T10:00:00Z' } }); next_page = $null } }
    }
    throw "Unexpected call in test: $k"
}
function Get-TGraphWrites { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and $_.Uri -like 'https://graph.microsoft.com/*' }) }
function Get-TPsaCalls { return @($Mock.Calls | Where-Object { $_.Uri -notlike 'https://graph.microsoft.com/*' -and $_.Uri -notlike 'https://login.microsoftonline.com/*' }) }
$TBase = @{ submittedByUpn = 'megan.bowen@contoso.com'; userOfficeId = ''; userPrincipalName = 'megan.bowen@contoso.com'; companyTenantId = $TTenant; ticketId = '777' }
function New-TBody { param([hashtable]$Over) $b = @{}; foreach ($k in $TBase.Keys) { $b[$k] = $TBase[$k] }; foreach ($k in $Over.Keys) { $b[$k] = $Over[$k] }; return $b }

# ---- 1. Dry run: every gate runs, nothing is removed or written ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ dry_run = 'true'; issue_tap = 'true' })
$o = $f.r.out
Check 'dry run: reached the reset step' ($f.stage -eq 'reset' -and -not $f.r.error) $f.r.error
Check 'dry run: status pending_confirmation, dry_run true' ($o.status -eq 'pending_confirmation' -and $o.dry_run -eq $true) $o.status
Check 'dry run: no Graph write (no DELETE, revoke or TAP)' (@(Get-TGraphWrites).Count -eq 0) (Show-Calls)
Check 'dry run: no PSA call at all' (@(Get-TPsaCalls).Count -eq 0) (Show-Calls)
Check 'dry run: role, eligibility and risk checks all ran' (@(Get-Calls 'GET' "$TG/roleManagement/directory/roleAssignments*").Count -eq 1 -and @(Get-Calls 'GET' "$TGB/roleManagement/directory/transitiveRoleAssignments*").Count -eq 1 -and @(Get-Calls 'GET' "$TG/roleManagement/directory/roleEligibilityScheduleInstances*").Count -eq 1 -and @(Get-Calls 'GET' "$TG/identityProtection/riskyUsers/u1").Count -eq 1)
Check 'dry run: transitive role check sends ConsistencyLevel eventual' (@(Get-Calls 'GET' "$TGB/roleManagement/directory/transitiveRoleAssignments*")[0].Headers['ConsistencyLevel'] -eq 'eventual')
Check 'dry run: internal note lists 4 methods, masked phone, not the password' ($o.internal_note -like '*Would remove (4)*' -and $o.internal_note -like '*Microsoft Authenticator app on Megan iPhone*' -and $o.internal_note -like '*ending 4321*' -and $o.internal_note -notlike '*555 010*' -and $o.internal_note -like '*Existing Temporary Access Pass*' -and $o.internal_note -notlike '*password*Authentication*') $o.internal_note
Check 'dry run: says it would issue a TAP' ($o.internal_note -like '*Would create a one-time Temporary Access Pass*')
Check 'dry run: public note lists no methods' ($o.public_note -notlike '*Authenticator*' -and $o.public_note -notlike '*4321*')
if ($env:SHOW_NOTE) { Write-Host "--- dry run note ---`n$($o.internal_note)" }

# ---- 2. ConnectWise live: removes all but password, revokes, TAP only in the internal note ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ issue_tap = $true })
$o = $f.r.out
$dels = @(Get-Calls 'DELETE' "$TG/users/u1/authentication/*")
$note = @(Get-Calls 'POST' "$TCW/service/tickets/777/notes")
Check 'cw: status success' ($o.status -eq 'success' -and -not $f.r.error) "$($o.status) $($f.r.error) $($o.warnings -join ';')"
Check 'cw: four DELETEs, none for the password' ($dels.Count -eq 4 -and -not @($dels | Where-Object { $_.Uri -like '*password*' }).Count) (Show-Calls)
Check 'cw: right Graph segments' (@($dels | Where-Object { $_.Uri -like '*/microsoftAuthenticatorMethods/ma1' -or $_.Uri -like '*/phoneMethods/ph1' -or $_.Uri -like '*/fido2Methods/fd1' -or $_.Uri -like '*/temporaryAccessPassMethods/tp1' }).Count -eq 4)
Check 'cw: existing TAP removed before the new one is created' ([array]::IndexOf(@($Mock.Calls), @($dels | Where-Object { $_.Uri -like '*/temporaryAccessPassMethods/tp1' })[0]) -lt [array]::IndexOf(@($Mock.Calls), @(Get-Calls 'POST' "$TG/users/u1/authentication/temporaryAccessPassMethods")[0]))
Check 'cw: sessions revoked' ($o.sessions_revoked -eq $true -and @(Get-Calls 'POST' "$TG/users/u1/revokeSignInSessions").Count -eq 1)
$tapCall = @(Get-Calls 'POST' "$TG/users/u1/authentication/temporaryAccessPassMethods")
Check 'cw: TAP one-time, 60 minutes' ($tapCall.Count -eq 1 -and (Read-Body $tapCall[0]).isUsableOnce -eq $true -and (Read-Body $tapCall[0]).lifetimeInMinutes -eq 60)
Check 'cw: internal note on ticket 777 is internal and carries the TAP' ($note.Count -eq 1 -and (Read-Body $note[0]).internalAnalysisFlag -eq $true -and (Read-Body $note[0]).detailDescriptionFlag -eq $false -and (Read-Body $note[0]).text -like "*$TTapCode*" -and (Read-Body $note[0]).text -like '*Removed (4)*') (Show-Calls)
$TOutNoNote = ($o | Select-Object -Property * -ExcludeProperty internal_note | ConvertTo-Json -Depth 8)
Check 'cw: TAP appears nowhere but internal_note' ($TOutNoNote -notlike "*$TTapCode*" -and $o.public_note -notlike "*$TTapCode*")
Check 'cw: public note generic (no methods, mentions the code callback)' ($o.public_note -notlike '*Authenticator*' -and $o.public_note -notlike '*YubiKey*' -and $o.public_note -like '*technician will contact you*')
Check 'cw: counts and flags' ($o.methods_found -eq 4 -and $o.methods_removed -eq 4 -and $o.methods_not_removed -eq 0 -and $o.tap_issued -eq $true -and $o.note_written -eq $true)
Check 'cw: password never touched' (-not @($Mock.Calls | Where-Object { $_.Method -eq 'PATCH' }).Count)
if ($env:SHOW_NOTE) { Write-Host "--- cw note ---`n$($o.internal_note)`n--- public: $($o.public_note)" }

# ---- 3. Autotask: default method refused first, retried; TAP policy off is a warning ----
Reset-Mock (Get-TSecrets 'autotask') $Handler; Reset-TScenario; $global:TS.phoneDefaultFirst = $true; $global:TS.tap = 'policy'
$f = Invoke-Flow (New-TBody @{ ticketId = '12345'; psaCompanyId = '42'; issue_tap = 'yes' })
$o = $f.r.out
$atNote = @(Get-Calls 'POST' "$TAT/Tickets/12345/Notes")
Check 'autotask: success after retrying the default method' ($o.status -eq 'success' -and $o.methods_removed -eq 4 -and @(Get-Calls 'DELETE' "$TG/users/u1/authentication/phoneMethods/ph1").Count -eq 2) "$($o.status) $($f.r.error) $(Show-Calls)"
Check 'autotask: TAP policy off -> warning naming the policy, no TAP' ($o.tap_issued -eq $false -and @($o.warnings | Where-Object { $_ -like '*Temporary Access Pass policy*' }).Count -eq 1)
Check 'autotask: note is Internal Only and not a workflow note type' ($atNote.Count -eq 1 -and (Read-Body $atNote[0]).publish -eq 2 -and (Read-Body $atNote[0]).noteType -eq 1)
Check 'autotask: public note does not promise a code' ($o.public_note -notlike '*one-time sign-in code*')

# ---- 4. Autotask ticket of another company: no note written ----
Reset-Mock (Get-TSecrets 'autotask') $Handler; Reset-TScenario; $global:TS.atCompany = 99
$f = Invoke-Flow (New-TBody @{ ticketId = '12345'; psaCompanyId = '42' })
$o = $f.r.out
Check 'scope: ticket of another company -> no note, warning' (-not @(Get-Calls 'POST' "$TAT/Tickets/12345/Notes").Count -and $o.note_written -eq $false -and @($o.warnings | Where-Object { $_ -like '*another company*' }).Count -eq 1) (Show-Calls)

# ---- 5. Ownership mismatch -> rejected, nothing removed, Zendesk private note ----
Reset-Mock (Get-TSecrets 'zendesk') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ userPrincipalName = 'alex.wilber@contoso.com'; ticketId = '506' })
$o = $f.r.out
$zn = @(Get-Calls 'PUT' "$TZD/tickets/506")
Check 'mismatch: rejected identity-mismatch' ($o.status -eq 'rejected' -and $o.category -eq 'identity-mismatch') "$($o.status) $($o.category) $($f.r.error)"
Check 'mismatch: no Graph write and methods never read' (@(Get-TGraphWrites).Count -eq 0 -and -not @(Get-Calls 'GET' "$TG/users/u2/authentication/methods").Count)
Check 'mismatch: Zendesk note is private and explains' ($zn.Count -eq 1 -and (Read-Body $zn[0]).ticket.comment.public -eq $false -and (Read-Body $zn[0]).ticket.comment.body -like '*DENIED*alex.wilber@contoso.com*')
Check 'mismatch: public note says own account only' ($o.public_note -like '*your own account*')

# ---- 6. Object id match wins even when the email differs (UPN renamed) ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ submittedByUpn = 'megan.old@contoso.com'; userOfficeId = 'U1'; dry_run = $true })
Check 'object id: exact id match passes' ($f.r.out.status -eq 'pending_confirmation' -and @($f.r.out.actions | Where-Object { $_ -like '*Entra object id*' }).Count -eq 1) "$($f.r.out.status) $($f.r.error)"
Reset-Mock (Get-TSecrets 'connectwise') $Handler
$f = Invoke-Flow (New-TBody @{ submittedByUpn = 'megan@contoso.example'; dry_run = $true })
Check 'proxy: smtp proxy address match passes' ($f.r.out.status -eq 'pending_confirmation') "$($f.r.out.status) $($f.r.out.category)"
Reset-Mock (Get-TSecrets 'connectwise') $Handler
$f = Invoke-Flow (New-TBody @{ submittedByUpn = '@UserEmail'; userOfficeId = '@UserOfficeId'; dry_run = $true })
Check 'identity: literal @tokens -> rejected identity-unverified' ($f.r.out.status -eq 'rejected' -and $f.r.out.category -eq 'identity-unverified') "$($f.r.out.status) $($f.r.out.category)"
# Stricter than Password Reset: a sent object id that doesn't match is refused, even when the email matches.
Reset-Mock (Get-TSecrets 'connectwise') $Handler
$f = Invoke-Flow (New-TBody @{ userOfficeId = 'u2'; issue_tap = $true })
Check 'object id: mismatch with matching email -> rejected identity-mismatch' ($f.r.out.status -eq 'rejected' -and $f.r.out.category -eq 'identity-mismatch' -and $f.r.out.internal_note -like '*Entra object id u2*' -and @(Get-TGraphWrites).Count -eq 0 -and -not @(Get-Calls 'GET' "$TG/users/u1/authentication/methods").Count) "$($f.r.out.status) $($f.r.out.category)"
Check 'object id: mismatch -> internal note on the ticket' (@(Get-Calls 'POST' "$TCW/service/tickets/777/notes").Count -eq 1)
Reset-Mock (Get-TSecrets 'connectwise') $Handler
$f = Invoke-Flow (New-TBody @{ userOfficeId = ''; dry_run = $true })
Check 'object id blank: falls back to the email match' ($f.r.out.status -eq 'pending_confirmation' -and @($f.r.out.actions | Where-Object { $_ -like '*matched on email address*' }).Count -eq 1) "$($f.r.out.status) $($f.r.out.category)"
Reset-Mock (Get-TSecrets 'connectwise') $Handler
$f = Invoke-Flow (New-TBody @{ userOfficeId = '@UserOfficeId'; dry_run = $true })
Check 'object id literal @token: counts as blank, email match used' ($f.r.out.status -eq 'pending_confirmation' -and @($f.r.out.actions | Where-Object { $_ -like '*matched on email address*' }).Count -eq 1) "$($f.r.out.status) $($f.r.out.category)"
Reset-Mock (Get-TSecrets 'connectwise') $Handler
$f = Invoke-Flow (New-TBody @{ submittedByUpn = 'alex.wilber@contoso.com'; userOfficeId = ''; dry_run = $true })
Check 'object id blank: email of another person -> rejected' ($f.r.out.status -eq 'rejected' -and $f.r.out.category -eq 'identity-mismatch')
# Manual run: input without the trigger wrapper.
Reset-Mock (Get-TSecrets 'connectwise') $Handler
$f = Invoke-Flow (New-TBody @{ dry_run = $true }) -Manual
Check 'manual run: unwrapped input works' ($f.r.out.status -eq 'pending_confirmation') "$($f.r.out.status) $($f.r.error)"
$p = Invoke-Step 'parse' @{ trigger = '{"submittedByUpn":"megan.bowen@contoso.com","dry_run":"true"}' }
Check 'trigger as a JSON string is parsed' (-not $p.error -and $p.out.upn -eq 'megan.bowen@contoso.com' -and $p.out.dry_run -eq $true) $p.error

# ---- 7. Safety gates ----
$TGates = @(
    @{ name = 'disabled'; set = { $global:TS.enabled = $false }; cat = 'disabled' }
    @{ name = 'direct admin role'; set = { $global:TS.direct = $true }; cat = 'privilege'; like = '*Global Administrator*' }
    @{ name = 'role through a role-assignable group'; set = { $global:TS.group = $true }; cat = 'privilege'; like = '*through a role-assignable group (Helpdesk Administrator)*' }
    @{ name = 'eligible (PIM) role'; set = { $global:TS.eligible = $true }; cat = 'privilege'; like = '*eligible (PIM)*' }
    @{ name = 'at-risk user'; set = { $global:TS.risk = 'atRisk' }; cat = 'risk' }
)
foreach ($TGate in $TGates) {
    Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario; & $TGate.set
    $f = Invoke-Flow (New-TBody @{})
    $o = $f.r.out
    $ok = $o.status -eq 'rejected' -and $o.category -eq $TGate.cat -and @(Get-TGraphWrites).Count -eq 0 -and -not @(Get-Calls 'GET' "$TG/users/u1/authentication/methods").Count
    if ($TGate.Contains('like')) { $ok = $ok -and $o.internal_note -like $TGate.like }
    Check "gate: $($TGate.name) -> rejected, nothing touched" $ok "$($o.status) $($o.category) $($f.r.error) $($o.internal_note)"
    Check "gate: $($TGate.name) -> internal note written to the ticket" (@(Get-Calls 'POST' "$TCW/service/tickets/777/notes").Count -eq 1 -and (Read-Body @(Get-Calls 'POST' "$TCW/service/tickets/777/notes")[0]).internalAnalysisFlag -eq $true)
}
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ companyTenantId = '99999999-8888-7777-6666-555555555555' })
Check 'gate: other tenant -> rejected before any user lookup' ($f.r.out.status -eq 'rejected' -and $f.r.out.category -eq 'tenant-scope' -and -not @(Get-Calls 'GET' "$TG/users/*").Count) "$($f.r.out.status) $(Show-Calls)"
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ userPrincipalName = 'nobody@contoso.com'; submittedByUpn = 'nobody@contoso.com' })
Check 'gate: unknown account -> rejected' ($f.r.out.status -eq 'rejected' -and $f.r.out.category -eq 'resolution')
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario; $global:TS.eligibleLicense = $true; $global:TS.riskForbidden = $true
$f = Invoke-Flow (New-TBody @{ dry_run = $true })
Check 'no P2: eligibility licence error and unreadable risk are warnings, run continues' ($f.r.out.status -eq 'pending_confirmation' -and @($f.r.out.warnings | Where-Object { $_ -like '*Entra ID P2*' }).Count -eq 2) "$($f.r.out.status) $($f.r.error) $($f.r.out.warnings -join ' | ')"

# ---- 8. Missing permissions: fail closed with a plain sentence ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario; $global:TS.roleForbidden = $true
$f = Invoke-Flow (New-TBody @{})
Check '403 roles: stops in verify naming RoleManagement.Read.Directory' ($f.stage -eq 'verify' -and $f.r.error -like '*RoleManagement.Read.Directory*' -and $f.r.out.status -eq 'error') "$($f.stage) $($f.r.error)"
Check '403 roles: nothing removed' (@(Get-TGraphWrites).Count -eq 0)
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario; $global:TS.authForbidden = $true
$f = Invoke-Flow (New-TBody @{})
Check '403 methods: stops naming UserAuthenticationMethod permission' ($f.r.error -like '*UserAuthenticationMethod.Read*' -and $f.r.out.status -eq 'error') "$($f.stage) $($f.r.error)"
Check '403 methods: nothing removed, no note' (@(Get-TGraphWrites).Count -eq 0 -and -not @(Get-Calls 'POST' "$TCW/service/tickets/777/notes").Count)
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario; $global:TS.revokeFail = $true
$f = Invoke-Flow (New-TBody @{})
Check '403 revoke: incomplete, warning names User.RevokeSessions.All' ($f.r.out.status -eq 'incomplete' -and @($f.r.out.warnings | Where-Object { $_ -like '*User.RevokeSessions.All*' }).Count -eq 1) "$($f.r.out.status) $($f.r.error)"

# ---- 9. Empty result: only a password registered ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario; $global:TS.methods = 'pwOnly'
$f = Invoke-Flow (New-TBody @{})
$o = $f.r.out
Check 'empty: success, nothing removed, no revoke' ($o.status -eq 'success' -and $o.methods_found -eq 0 -and @(Get-TGraphWrites).Count -eq 0) "$($o.status) $(Show-Calls)"
Check 'empty: notes say so' ($o.internal_note -like '*nothing (only the password was registered)*' -and $o.public_note -like '*no MFA sign-in methods*')

# ---- 10. A method type this workflow can't remove -> incomplete ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario; $global:TS.methods = 'hw'
$f = Invoke-Flow (New-TBody @{})
$o = $f.r.out
Check 'hardware token: incomplete, phone removed, token left for a technician' ($o.status -eq 'incomplete' -and $o.methods_removed -eq 1 -and $o.methods_not_removed -eq 1 -and $o.internal_note -like '*hardwareOathAuthenticationMethod*can''t remove*' -and $o.public_note -like '*technician needs to finish*') "$($o.status) $($o.internal_note)"

# ---- 11. No ticket id / no PSA ----
Reset-Mock (Get-TSecrets 'none') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ ticketId = '' })
Check 'no ticket: success, note only in output' ($f.r.out.status -eq 'success' -and $f.r.out.note_written -eq $false -and @($f.r.out.warnings | Where-Object { $_ -like '*No ticket id*' }).Count -eq 1) "$($f.r.out.status) $($f.r.error)"
Reset-Mock (Get-TSecrets 'none') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{})
Check 'no PSA set up: success, warning' ($f.r.out.status -eq 'success' -and @($f.r.out.warnings | Where-Object { $_ -like '*No PSA is set up*' }).Count -eq 1) "$($f.r.out.status) $($f.r.out.warnings -join ';')"

# ---- 12. Rerun (ServiceAI Retry, or the same request twice) writes nothing twice ----
# ConnectWise: the first run resets and writes the marked internal note; the rerun finds the marker
# before any Graph change, so nothing is removed, no second pass is created and no note is added.
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$f = Invoke-Flow (New-TBody @{ issue_tap = $true })
Check 'rerun cw: first run succeeds and writes one marked internal note' ($f.r.out.status -eq 'success' -and @(Get-TNotes '777').Count -eq 1 -and (Get-TNotes '777')[0].text.Contains('[mfa-reset: 777]') -and (Get-TNotes '777')[0].public -eq $false) "$($f.r.out.status) $($f.r.error)"
$TFirstTap = @(Get-TNotes '777')[0].text
Reset-Mock (Get-TSecrets 'connectwise') $Handler
$f = Invoke-Flow (New-TBody @{ issue_tap = $true })
$o = $f.r.out
Check 'rerun cw: success, already-done, nothing changed' ($o.status -eq 'success' -and $o.category -eq 'already-done' -and $o.note_written -eq $false -and -not $f.r.error) "$($o.status) $($o.category) $($f.r.error)"
Check 'rerun cw: no Graph write (no DELETE, revoke or new pass)' (@(Get-TGraphWrites).Count -eq 0 -and -not @(Get-Calls 'GET' "$TG/users/u1/authentication/methods").Count) (Show-Calls)
Check 'rerun cw: no second note' (@(Get-Calls 'POST' "$TCW/service/tickets/777/notes").Count -eq 0 -and @(Get-TNotes '777').Count -eq 1 -and (Get-TNotes '777')[0].text -eq $TFirstTap)
Check 'rerun cw: the TAP is not in any output field, and the marker never holds it' (($o | ConvertTo-Json -Depth 8) -notlike "*$TTapCode*" -and $TFirstTap -notmatch "\[[^\]]*$TTapCode[^\]]*\]" -and $TFirstTap -like "*$TTapCode*")
# Autotask: same guard through the Autotask notes query.
Reset-Mock (Get-TSecrets 'autotask') $Handler; Reset-TScenario
$null = Invoke-Flow (New-TBody @{ ticketId = '12345'; psaCompanyId = '42' })
Reset-Mock (Get-TSecrets 'autotask') $Handler
$f = Invoke-Flow (New-TBody @{ ticketId = '12345'; psaCompanyId = '42' })
Check 'rerun autotask: nothing removed, no second note' ($f.r.out.category -eq 'already-done' -and @(Get-TGraphWrites).Count -eq 0 -and -not @(Get-Calls 'POST' "$TAT/Tickets/12345/Notes").Count -and @(Get-TNotes '12345').Count -eq 1) "$($f.r.out.status) $($f.r.out.category) $($f.r.error)"
# A rejected request retried: the refusal note is written once.
Reset-Mock (Get-TSecrets 'zendesk') $Handler; Reset-TScenario
$null = Invoke-Flow (New-TBody @{ userPrincipalName = 'alex.wilber@contoso.com'; ticketId = '506' })
Reset-Mock (Get-TSecrets 'zendesk') $Handler
$f = Invoke-Flow (New-TBody @{ userPrincipalName = 'alex.wilber@contoso.com'; ticketId = '506' })
Check 'rerun rejected (Zendesk): refusal note written once, marker holds only the ticket id' ($f.r.out.status -eq 'rejected' -and -not @(Get-Calls 'PUT' "$TZD/tickets/506").Count -and @(Get-TNotes '506').Count -eq 1 -and (Get-TNotes '506')[0].text.Contains('[mfa-reset-request: 506]')) "$(Show-Calls)"
# The marker is checked before any change: unreadable notes stop the run with nothing changed.
Reset-Mock (Get-TSecrets 'autotask') $Handler; Reset-TScenario
$TSaved = $Handler
$Handler2 = { param($c, $n) if ($c.Method -eq 'GET' -and $c.Uri -like '*/TicketNotes/query*') { New-HttpError 403 '{"errors":["denied"]}' }; return (& $TSaved $c $n) }
Reset-Mock (Get-TSecrets 'autotask') $Handler2
$f = Invoke-Flow (New-TBody @{ ticketId = '12345' })
Check 'notes unreadable: error psa-error, nothing removed, no note' ($f.r.out.status -eq 'error' -and $f.r.out.category -eq 'psa-error' -and @(Get-TGraphWrites).Count -eq 0 -and -not @(Get-Calls 'POST' "$TAT/Tickets/12345/Notes").Count) "$($f.r.out.status) $($f.r.out.category) $($f.r.error)"
# No note this workflow writes is public, so no personal data or marker reaches the client.
Check 'every ticket note is internal' (-not @(foreach ($TK in @($global:TNotes.Keys)) { Get-TNotes $TK | Where-Object { $_.public } }).Count)

# ---- 13. Parse ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-TScenario
$p = Invoke-Step 'parse' $null
Check 'parse: no input -> incomplete' ($p.out.status -eq 'incomplete' -and $p.error)
$p = Invoke-Step 'parse' ([pscustomobject]@{ submittedByUpn = '@UserEmail'; userOfficeId = '@UserOfficeId'; userPrincipalName = '@targetUpn' })
Check 'parse: only literal @tokens -> incomplete' ($p.out.status -eq 'incomplete') $p.error
$p = Invoke-Step 'parse' ([pscustomobject]@{ submittedByUpn = 'megan.bowen@contoso.com'; userPrincipalName = '@targetUpn' })
Check 'parse: no target -> the submitter''s own account, defaults safe' ($p.out.upn -eq 'megan.bowen@contoso.com' -and $p.out.target_source -eq 'submitter' -and $p.out.dry_run -eq $false -and $p.out.issue_tap -eq $false -and $p.out.revokeSessions -eq $true)
$cr = [pscustomobject]@{ trigger = [pscustomobject]@{ submittedByUpn = 'megan.bowen@contoso.com'; userOfficeId = 'u1'; Ticket = [pscustomobject]@{ TicketId = 4321; Questions = @([pscustomobject]@{ Id = 'dry_run'; Value = 'Yes' }) }; Company = [pscustomobject]@{ CompanyTenantId = $TTenant; CompanyPsaId = '42' } } }
$p = Invoke-Step 'parse' $cr
Check 'parse: CloudRadial nested shape' (-not $p.error -and $p.out.ticket_id -eq '4321' -and $p.out.companyTenantId -eq $TTenant -and $p.out.psaCompanyId -eq '42' -and $p.out.dry_run -eq $true -and $p.out.userOfficeId -eq 'u1') "$($p.error) $($p.out | ConvertTo-Json -Compress)"

Complete-Test
