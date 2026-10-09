# Strict-mode harness for risky-signin-response.yml. Runs the five steps exactly as they are in the .yml
# (extracted by build.js --extract), each through & ([scriptblock]::Create(...)) under
# Set-StrictMode -Version Latest, passing each step's output to the next as JSON the way the runner does.
# Mocks Get-AzKeyVaultSecret, Invoke-RestMethod, Get-NodeInput, Set-NodeOutput and Start-Sleep.
# Placeholder data only (Contoso, Example MSP).
# Usage: pwsh -NoProfile -File automationai/risky-signin-response/src/test.ps1
#        (needs node and js-yaml; set JS_YAML_PATH if js-yaml isn't installed in automationai/_shared)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:RUNNER_KV_NAME = 'kv-test'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("rsr-test-" + [guid]::NewGuid().ToString('N'))
& node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { throw 'risky-signin-response.yml is out of date. Run node build.js first.' }
& node (Join-Path $PSScriptRoot 'build.js') --extract $tmp | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the steps.' }
$StepIds = @('node-inputs', 'node-find', 'node-respond', 'node-block', 'node-summary')
$Steps = @{}; foreach ($s in $StepIds) { $Steps[$s] = Get-Content -Raw (Join-Path $tmp "$s.ps1") }
Remove-Item -Recurse -Force $tmp

$Tally = @{ pass = 0; fail = 0 }
$Mock = @{ Secrets = @{}; Calls = (New-Object System.Collections.ArrayList); Opt = @{}; NextId = 5000; Notes = @{} }
# Notes written to each ticket (kept across runs until Clear-Notes), read back by the shared retry guard.
function Add-MockNote { param([string]$T, [string]$Text, [bool]$Public) if (-not $Mock.Notes.Contains($T)) { $Mock.Notes[$T] = @() }; $Mock.Notes[$T] += [pscustomobject]@{ text = $Text; public = $Public } }
function Get-MockNotes { param([string]$T) if ($Mock.Notes.Contains($T)) { return @($Mock.Notes[$T]) }; return @() }
function Clear-Notes { $Mock.Notes = @{} }
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
$Denied = '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}'

# ---- Directory ----
$G = 'https://graph.microsoft.com/v1.0'
function Get-Iso { param([double]$HoursAgo) return (Get-Date).ToUniversalTime().AddHours(-$HoursAgo).ToString('yyyy-MM-ddTHH:mm:ssZ') }
$Users = @{
    'u1' = @{ upn = 'alice@contoso.com'; name = 'Alice Example'; synced = $false; enabled = $true; level = 'high'; state = 'atRisk'; manager = 'm1' }
    'u2' = @{ upn = 'admin.ceo@contoso.com'; name = 'Casey Admin'; synced = $false; enabled = $true; level = 'high'; state = 'atRisk'; manager = '' }
    'u3' = @{ upn = 'synced.user@contoso.com'; name = 'Sam Synced'; synced = $true; enabled = $true; level = 'high'; state = 'atRisk'; manager = 'm1' }
    'u4' = @{ upn = 'medium.user@contoso.com'; name = 'Morgan Medium'; synced = $false; enabled = $true; level = 'medium'; state = 'atRisk'; manager = '' }
    'u5' = @{ upn = 'remediated@contoso.com'; name = 'Riley Fixed'; synced = $false; enabled = $true; level = 'high'; state = 'remediated'; manager = '' }
    'u6' = @{ upn = 'existing@contoso.com'; name = 'Ezra Existing'; synced = $false; enabled = $true; level = 'high'; state = 'atRisk'; manager = '' }
    'm1' = @{ upn = 'bob.manager@contoso.com'; name = 'Bob Manager'; synced = $false; enabled = $true; level = 'none'; state = 'none'; manager = '' }
}
function Find-UserKey { param([string]$IdOrUpn) foreach ($k in $Users.Keys) { if ($k -eq $IdOrUpn -or $Users[$k].upn -eq $IdOrUpn) { return $k } }; return $null }
function Get-RiskyRow { param([string]$k) $u = $Users[$k]; return [pscustomobject]@{ id = $k; userPrincipalName = $u.upn; userDisplayName = $u.name; riskLevel = $u.level; riskState = $u.state; riskDetail = 'none'; riskLastUpdatedDateTime = (Get-Iso 2); isDeleted = $false; isProcessing = $false } }
function Get-Detections {
    param([string]$k)
    if ($k -eq 'u1') {
        return @(
            [pscustomobject]@{ id = 'det-a1'; riskEventType = 'unfamiliarFeatures'; riskLevel = 'high'; riskState = 'atRisk'; ipAddress = '203.0.113.45'; location = [pscustomobject]@{ city = 'Lagos'; state = 'Lagos'; countryOrRegion = 'NG' }; detectedDateTime = (Get-Iso 3); activityDateTime = (Get-Iso 3.1); detectionTimingType = 'realtime'; source = 'IdentityProtection' },
            [pscustomobject]@{ id = 'det-a2'; riskEventType = 'leakedCredentials'; riskLevel = 'high'; riskState = 'atRisk'; ipAddress = $null; location = $null; detectedDateTime = (Get-Iso 20); activityDateTime = $null; detectionTimingType = 'offline'; source = 'IdentityProtection' })
    }
    if ($k -eq 'u2') { return @([pscustomobject]@{ id = 'det-c1'; riskEventType = 'anonymizedIPAddress'; riskLevel = 'high'; riskState = 'atRisk'; ipAddress = '198.51.100.7'; location = [pscustomobject]@{ city = ''; state = ''; countryOrRegion = 'NL' }; detectedDateTime = (Get-Iso 1); activityDateTime = (Get-Iso 1); detectionTimingType = 'realtime'; source = 'IdentityProtection' }) }
    return @()
}

# Like the real cmdlet, a JSON array reply is handed back as ONE object (", @(...)"), not item by item, and
# -MaximumRedirection is accepted (recorded as MaxRedirect, -1 when not sent) so the shared PSA code takes its no-redirect path.
function Invoke-RestMethod {
    [CmdletBinding()] param($Method = 'GET', $Uri, $Headers, $Body, $ContentType, $Form, [int]$MaximumRedirection = -1)
    $m = ([string]$Method).ToUpperInvariant(); $u = [uri]::UnescapeDataString([string]$Uri)
    $b = if ($Body -is [string]) { $Body } else { '' }
    $null = $Mock.Calls.Add([pscustomobject]@{ MaxRedirect = $MaximumRedirection; Method = $m; Uri = $u; Body = $b })
    if ($u -like 'https://login.microsoftonline.com/*') { return [pscustomobject]@{ access_token = 'mock'; expires_in = 3600 } }

    # Graph
    if ($m -eq 'GET' -and $u -like "$G/identityProtection/riskyUsers[?]*") {
        if ($Mock.Opt.Contains('Risky403')) { New-HttpError 403 $Denied }
        if ($Mock.Opt.Contains('NoP2')) { New-HttpError 403 '{"error":{"code":"Forbidden","message":"Your tenant is not licensed for this feature. Microsoft Entra ID P2 is required."}}' }
        if ($Mock.Opt.Contains('Empty')) { return [pscustomobject]@{ value = @() } }
        return [pscustomobject]@{ value = @(@('u1', 'u2', 'u3', 'u4', 'u6') | ForEach-Object { Get-RiskyRow $_ }) }
    }
    if ($m -eq 'GET' -and $u -like "$G/identityProtection/riskyUsers/*") {
        $k = ($u -split '/')[-1]
        if (-not $Users.ContainsKey($k) -or $k -eq 'm1') { New-HttpError 404 '{"error":{"code":"NotFound","message":"Not found"}}' }
        return (Get-RiskyRow $k)
    }
    if ($m -eq 'GET' -and $u -like "$G/identityProtection/riskDetections*") {
        if ($Mock.Opt.Contains('Det403')) { New-HttpError 403 $Denied }
        $k = if ($u -match "userId eq '([^']+)'") { $Matches[1] } else { '' }
        return [pscustomobject]@{ value = @(Get-Detections $k) }
    }
    if ($m -eq 'GET' -and $u -like "$G/directoryRoles*") {
        if ($Mock.Opt.Contains('Roles403')) { New-HttpError 403 $Denied }
        return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'r1'; displayName = 'Global Administrator'; members = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.user'; id = 'u2' }) }) }
    }
    if ($m -eq 'GET' -and $u -match '^https://graph\.microsoft\.com/v1\.0/users/([^/?]+)/manager') {
        $k = Find-UserKey $Matches[1]
        if ($null -eq $k -or -not $Users[$k].manager) { New-HttpError 404 '{"error":{"code":"Request_ResourceNotFound","message":"Resource manager does not exist."}}' }
        $mk = $Users[$k].manager
        return [pscustomobject]@{ id = $mk; displayName = $Users[$mk].name; mail = $Users[$mk].upn; userPrincipalName = $Users[$mk].upn }
    }
    if ($m -eq 'GET' -and $u -match '^https://graph\.microsoft\.com/v1\.0/users/([^/?]+)\?') {
        $k = Find-UserKey $Matches[1]
        if ($null -eq $k) { New-HttpError 404 '{"error":{"code":"Request_ResourceNotFound","message":"Resource does not exist."}}' }
        $x = $Users[$k]
        return [pscustomobject]@{ id = $k; userPrincipalName = $x.upn; displayName = $x.name; mail = $x.upn; accountEnabled = $x.enabled; onPremisesSyncEnabled = $(if ($x.synced) { $true } else { $null }) }
    }
    if ($m -eq 'POST' -and $u -like "$G/users/*/revokeSignInSessions") {
        if ($Mock.Opt.Contains('FailRevoke')) { New-HttpError 500 '{"error":{"message":"Mock server error"}}' }
        return [pscustomobject]@{ value = $true }
    }
    if ($m -eq 'PATCH' -and $u -like "$G/users/*") {
        if ($b -match 'passwordProfile' -and $u -like '*/users/u2') { New-HttpError 403 $Denied }
        if ($b -match 'passwordProfile' -and $u -like '*/users/u3') { New-HttpError 400 '{"error":{"message":"Unable to update the specified properties for on-premises mastered Directory Sync objects"}}' }
        return $null
    }
    if ($m -eq 'POST' -and $u -like "$G/users/*/sendMail") { return $null }

    # ConnectWise
    $cw = 'https://cw.example-msp.test/v4_6_release/apis/3.0'
    if ($m -eq 'GET' -and $u -like "$cw/service/tickets[?]conditions=*") {
        if ($Mock.Opt.Contains('SearchFail')) { New-HttpError 500 '{"message":"Mock search error"}' }
        $co = [pscustomobject]@{ id = 250; name = 'Contoso' }
        if ($Mock.Opt.Contains('OpenRisky') -and $u -match [regex]::Escape($Mock.Opt['OpenRisky'].upn)) { return , @([pscustomobject]@{ id = $Mock.Opt['OpenRisky'].id; summary = "[Risky sign-in] $($Mock.Opt['OpenRisky'].upn): Microsoft flagged high risk"; company = $co; closedFlag = $false; status = [pscustomobject]@{ name = 'New' } }) }
        if ($u -match 'existing@contoso\.com') { return , @([pscustomobject]@{ id = 4242; summary = '[Risky sign-in] existing@contoso.com: Microsoft flagged high risk'; company = $co; closedFlag = $false; status = [pscustomobject]@{ name = 'New' } }) }
        if ($u -match 'alice@contoso\.com') { return , @([pscustomobject]@{ id = 4100; summary = 'Printer for alice@contoso.com'; company = $co; closedFlag = $false; status = [pscustomobject]@{ name = 'New' } }) }
        return , @()
    }
    if ($m -eq 'GET' -and $u -like "$cw/service/priorities*") { return , @([pscustomobject]@{ id = 1; name = 'Priority 1 - Critical' }, [pscustomobject]@{ id = 2; name = 'Priority 2 - High' }, [pscustomobject]@{ id = 3; name = 'Priority 3 - Normal' }) }
    if ($m -eq 'GET' -and $u -like "$cw/company/companies*") {
        if ($Mock.Opt.Contains('NoPsaCompany')) { return , @() }
        # Strict: only a real name condition matches, so a lost condition shows up as no match.
        if ($u -match 'name="Contoso"' -or $u -match 'name contains "Contoso"') { return , @([pscustomobject]@{ id = 250; name = 'Contoso' }) }
        return , @()
    }
    if ($m -eq 'POST' -and $u -eq "$cw/service/tickets") { $Mock.NextId++; return [pscustomobject]@{ id = $Mock.NextId } }
    if ($m -eq 'POST' -and $u -like "$cw/service/tickets/*/notes") { $bo = $b | ConvertFrom-Json; Add-MockNote ($u -split '/')[-2] $bo.text ([bool]$bo.detailDescriptionFlag); return [pscustomobject]@{ id = 1 } }
    if ($m -eq 'GET' -and $u -match '/service/tickets/(\d+)/notes') { $i = 0; return , @(Get-MockNotes $Matches[1] | ForEach-Object { $i++; [pscustomobject]@{ id = $i; text = $_.text; internalAnalysisFlag = (-not $_.public); detailDescriptionFlag = $_.public } }) }

    # Zendesk
    $zd = 'https://examplemsp.zendesk.test/api/v2'
    if ($m -eq 'GET' -and $u -like "$zd/search*") {
        if ($u -match 'existing@contoso\.com') { return [pscustomobject]@{ results = @([pscustomobject]@{ id = 777; subject = '[Risky sign-in] existing@contoso.com: Microsoft flagged high risk'; organization_id = 360001; status = 'open' }) } }
        return [pscustomobject]@{ results = @() }
    }
    if ($m -eq 'GET' -and $u -like "$zd/organizations/autocomplete*") { return [pscustomobject]@{ organizations = @([pscustomobject]@{ id = 360001; name = 'Contoso' }, [pscustomobject]@{ id = 360002; name = 'Contoso Labs' }) } }
    if ($m -eq 'POST' -and $u -eq "$zd/tickets") { $Mock.NextId++; return [pscustomobject]@{ ticket = [pscustomobject]@{ id = $Mock.NextId } } }
    if ($m -eq 'PUT' -and $u -like "$zd/tickets/*") { $bo = $b | ConvertFrom-Json; Add-MockNote ($u -split '/')[-1] $bo.ticket.comment.body ([bool]$bo.ticket.comment.public); return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1 } } }
    if ($m -eq 'GET' -and $u -match '/tickets/(\d+)/comments') { $i = 0; return [pscustomobject]@{ comments = @(Get-MockNotes $Matches[1] | ForEach-Object { $i++; [pscustomobject]@{ id = $i; body = $_.text; public = $_.public; author_id = 1 } }); next_page = $null } }

    # Kaseya BMS
    $bms = 'https://bms.example-msp.test'
    if ($m -eq 'POST' -and $u -eq "$bms/v2/security/authenticate") { return [pscustomobject]@{ Success = $true; Result = [pscustomobject]@{ AccessToken = 'tok' } } }
    if ($m -eq 'POST' -and $u -eq "$bms/v2/servicedesk/tickets") { $Mock.NextId++; return [pscustomobject]@{ Success = $true; Result = [pscustomobject]@{ Id = $Mock.NextId } } }
    if ($m -eq 'POST' -and $u -like "$bms/v2/servicedesk/tickets/*/notes") { $bo = $b | ConvertFrom-Json; Add-MockNote ($u -split '/')[-2] $bo.Details (-not $bo.IsInternal); return [pscustomobject]@{ Success = $true } }
    if ($m -eq 'GET' -and $u -match '/v2/servicedesk/tickets/(\d+)/notes') { $i = 0; return [pscustomobject]@{ Success = $true; Result = @(Get-MockNotes $Matches[1] | ForEach-Object { $i++; [pscustomobject]@{ Id = $i; Details = $_.text; IsInternal = (-not $_.public) } }) } }
    if ($m -eq 'GET' -and $u -like "$bms/v2/servicedesk/tickets[?]*") {
        if ($Mock.Opt.Contains('SearchFail')) { New-HttpError 500 '{"message":"Mock list error"}' }
        $rows = @([pscustomobject]@{ Id = 9100; Title = 'Printer for alice@contoso.com'; StatusName = 'New'; AccountId = 88 })
        if ($Mock.Opt.Contains('BmsExisting')) { $rows += [pscustomobject]@{ Id = 9200; Title = '[Risky sign-in] alice@contoso.com: Microsoft flagged high risk'; StatusName = 'In Progress'; AccountId = 88 } }
        $rows += [pscustomobject]@{ Id = 9300; Title = '[Risky sign-in] synced.user@contoso.com: Microsoft flagged high risk'; StatusName = 'New'; AccountId = 99 }
        return [pscustomobject]@{ Success = $true; Result = @($rows); TotalRecords = @($rows).Count }
    }

    # CloudRadial
    $cr = 'https://portal.example-msp.test'
    if ($m -eq 'GET' -and $u -like "$cr/v2/odata/company*") { return [pscustomobject]@{ value = @([pscustomobject]@{ companyId = 9; name = 'Contoso' }) } }
    if ($m -eq 'GET' -and $u -like "$cr/api/beta/archive*") {
        if ($Mock.Opt.Contains('HasArchive')) { return , @([pscustomobject]@{ id = 66; companyId = 9; name = 'Risky Sign-ins' }) }
        return , @()
    }
    if ($m -eq 'POST' -and $u -eq "$cr/api/beta/archive") { $Mock.Opt['HasArchive'] = $true; return [pscustomobject]@{ id = 66 } }
    if ($m -eq 'GET' -and $u -like "$cr/v2/odata/archiveitem*") {
        if ($Mock.Opt.Contains('Logged') -and $u -match [regex]::Escape($Mock.Opt['Logged'])) { return [pscustomobject]@{ value = @([pscustomobject]@{ companyReportItemId = 1; subject = ([regex]::Match($u, "subject eq '([^']+)'").Groups[1].Value) }) } }
        return [pscustomobject]@{ value = @() }
    }
    if ($m -eq 'POST' -and $u -eq "$cr/v2/archiveitem") { return [pscustomobject]@{ companyReportItemId = 900 } }
    throw "Unmocked call: $m $u"
}

function Get-Calls { param([string]$Method, [string]$Like) return @($Mock.Calls | Where-Object { $_.Method -eq $Method -and $_.Uri -like $Like }) }
function Check { param([string]$Name, [bool]$Ok, $Detail = '') if ($Ok) { $Tally.pass++; Write-Host "PASS $Name" } else { $Tally.fail++; Write-Host "FAIL $Name :: $Detail" -ForegroundColor Red } }
function RoundTrip { param($o) if ($null -eq $o) { return $null }; return ($o | ConvertTo-Json -Depth 30 | ConvertFrom-Json) }
function Get-Writes { return @($Mock.Calls | Where-Object { $_.Method -in @('PATCH', 'POST', 'PUT', 'DELETE') -and $_.Uri -notlike 'https://login.*' -and $_.Uri -notlike '*/security/authenticate' }) }
function Get-GraphWrites { return @(Get-Writes | Where-Object { $_.Uri -like 'https://graph.microsoft.com/*' }) }
function Get-Resp { param($o, [string]$Upn) return (@($o.responses | Where-Object { $_.upn -eq $Upn }) | Select-Object -First 1) }

$BaseSecrets = @{
    'M365-TenantId' = '00000000-0000-0000-0000-000000000000'; 'M365-ClientId' = 'cid'; 'M365-ClientSecret' = 'sec'
    'CloudRadial-BaseUrl' = 'https://portal.example-msp.test'; 'CloudRadial-PublicKey' = 'pub'; 'CloudRadial-PrivateKey' = 'priv'; 'CloudRadial-CompanyId' = '9'
    'Notify-FromMailbox' = 'alerts@example-msp.test'
    'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://cw.example-msp.test/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'p'; 'CW-PrivateKey' = 'k'; 'CW-ClientId' = 'c'
    'Zendesk-BaseUrl' = 'https://examplemsp.zendesk.test'; 'Zendesk-Email' = 'agent@example-msp.test'; 'Zendesk-ApiToken' = 't'
    'KaseyaBMS-ApiUrl' = 'https://bms.example-msp.test'; 'KaseyaBMS-Username' = 'u'; 'KaseyaBMS-Password' = 'p'; 'KaseyaBMS-CompanyName' = 'examplemsp'; 'KaseyaBMS-NoteTypeId' = '3'
}

# Runs the workflow. Returns @{ out; error; step }.
function Invoke-Workflow {
    param($RunInput, [hashtable]$Secrets = @{}, [hashtable]$Opt = @{})
    $Mock.Secrets = $BaseSecrets.Clone(); foreach ($k in $Secrets.Keys) { if ($null -eq $Secrets[$k]) { $Mock.Secrets.Remove($k) } else { $Mock.Secrets[$k] = $Secrets[$k] } }
    $Mock.Calls.Clear(); $Mock.Opt = $Opt
    $global:NodeIn = $(if ($RunInput -is [string] -or $null -eq $RunInput) { $RunInput } else { RoundTrip $RunInput })
    $global:NodeOut = $null
    foreach ($s in $StepIds) {
        try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps[$s])) }
        catch { return @{ out = (RoundTrip $global:NodeOut); error = [string]$_.Exception.Message; step = $s } }
        $global:NodeIn = RoundTrip $global:NodeOut
    }
    return @{ out = $global:NodeIn; error = ''; step = 'end' }
}

# 1. Preview (ConnectWise): nothing is written anywhere.
$r = Invoke-Workflow @{ preview = $true } @{ 'PSA-CompanyId' = '250' }
$o = $r.out
Check 'preview: no error' ($r.error -eq '') "$($r.step): $($r.error)"
Check 'preview: status pending_confirmation' ($o.status -eq 'pending_confirmation') $o.status
Check 'preview: high-risk atRisk users only (medium and remediated left out)' (@($o.responses).Count -eq 4 -and $null -eq (Get-Resp $o 'medium.user@contoso.com') -and $null -eq (Get-Resp $o 'remediated@contoso.com')) (@($o.responses | ForEach-Object { $_.upn }) -join ', ')
Check 'preview: three would be handled' ($o.counts.would_handle -eq 3) ($o.counts | ConvertTo-Json -Compress)
Check 'preview: existing open ticket found by marker' ((Get-Resp $o 'existing@contoso.com').outcome -eq 'already-open' -and (Get-Resp $o 'existing@contoso.com').ticket_id -eq '4242') ''
Check 'preview: unrelated ticket mentioning the user is not a match' ((Get-Resp $o 'alice@contoso.com').outcome -eq 'would-handle') ''
Check 'preview: admin would be critical' ((Get-Resp $o 'admin.ceo@contoso.com').priority -eq 'critical') ''
Check 'preview: synced user plan skips password change' (((Get-Resp $o 'synced.user@contoso.com').planned -join ' ') -match 'Skip the password change') ''
Check 'preview: no writes anywhere' (@(Get-Writes).Count -eq 0) (@(Get-Writes | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join '; ')

# 2. Live hourly run (Routine sends no input), ConnectWise, PSA-CompanyId secret.
$Mock.NextId = 5000
$r = Invoke-Workflow $null @{ 'PSA-CompanyId' = '250' }
$o = $r.out
Check 'live: no error' ($r.error -eq '') $r.error
Check 'live: status success' ($o.status -eq 'success') "$($o.status) $($o.message)"
$posts = @(Get-Calls POST 'https://cw.example-msp.test/v4_6_release/apis/3.0/service/tickets')
Check 'live: three tickets opened, none for the existing one' ($posts.Count -eq 3 -and $o.counts.handled -eq 3 -and $o.counts.already_open -eq 1) "$($posts.Count) $($o.counts | ConvertTo-Json -Compress)"
$tb = @($posts | ForEach-Object { $_.Body | ConvertFrom-Json })
Check 'live: summary carries the marker' (@($tb | Where-Object { $_.summary -like '`[Risky sign-in`] *@contoso.com: Microsoft flagged high risk' }).Count -eq 3) (@($tb | ForEach-Object { $_.summary }) -join ' | ')
Check 'live: company from PSA-CompanyId' (@($tb | Where-Object { $_.company.id -eq 250 }).Count -eq 3 -and @(Get-Calls GET '*/company/companies*').Count -eq 0) ''
$adminT = @($tb | Where-Object { $_.summary -match 'admin\.ceo' })[0]; $aliceT = @($tb | Where-Object { $_.summary -match 'alice' })[0]
Check 'live: admin ticket critical, others high' ($adminT.priority.id -eq 1 -and $aliceT.priority.id -eq 2) "$($adminT.priority.id) $($aliceT.priority.id)"
Check 'live: ticket description has no risk detail' (-not (@($tb | Where-Object { $_.initialDescription -match '203\.0\.113|198\.51\.100|Lagos|unfamiliar|leaked' }).Count)) ''
$notes = @(Get-Calls POST 'https://cw.example-msp.test/*/service/tickets/*/notes')
$aliceNote = @($notes | Where-Object { $_.Uri -like "*/tickets/$((Get-Resp $o 'alice@contoso.com').ticket_id)/notes" })
Check 'live: internal note per ticket' ($notes.Count -eq 3 -and @($notes | Where-Object { ($_.Body | ConvertFrom-Json).internalAnalysisFlag -eq $true -and ($_.Body | ConvertFrom-Json).detailDescriptionFlag -eq $false }).Count -eq 3) ''
$an = ($aliceNote[0].Body | ConvertFrom-Json).text
Check 'live: note has IP, location, detection types and times' ($an -match '203\.0\.113\.45' -and $an -match 'Lagos, Lagos, NG' -and $an -match 'Unfamiliar sign-in properties' -and $an -match 'Leaked credentials' -and $an -match 'detected \d{4}-\d\d-\d\d \d\d:\d\d:\d\d UTC') $an
Check 'live: note says how to block' ($an -match 'block_upns set to alice@contoso\.com') ''
Check 'ConnectWise calls are sent with -MaximumRedirection 0' ((@($Mock.Calls | Where-Object { $_.Uri -like 'https://cw.example-msp.test/*' }).Count -gt 0) -and -not @($Mock.Calls | Where-Object { $_.Uri -like 'https://cw.example-msp.test/*' -and $_.MaxRedirect -ne 0 }).Count) (@($Mock.Calls | Where-Object { $_.Uri -like 'https://cw.example-msp.test/*' } | ForEach-Object { "$($_.Method) $($_.MaxRedirect)" }) -join ', ')
Check 'live: sessions revoked for the three new users only' (@(Get-Calls POST '*/revokeSignInSessions').Count -eq 3 -and @(Get-Calls POST '*/users/u6/revokeSignInSessions').Count -eq 0) ''
$pw = @(Get-Calls PATCH 'https://graph.microsoft.com/v1.0/users/*' | Where-Object { $_.Body -match 'passwordProfile' })
Check 'live: password change required for alice, attempted for admin, never for synced' (@($pw | Where-Object { $_.Uri -like '*/u1' }).Count -eq 1 -and @($pw | Where-Object { $_.Uri -like '*/u3' }).Count -eq 0 -and (($pw[0].Body | ConvertFrom-Json).passwordProfile.forceChangePasswordNextSignIn -eq $true)) (@($pw | ForEach-Object { $_.Uri }) -join ', ')
Check 'live: admin password refusal is a warning, not an error' ((Get-Resp $o 'admin.ceo@contoso.com').password -eq 'manual-admin' -and (Get-Resp $o 'admin.ceo@contoso.com').outcome -eq 'handled' -and (@($o.warnings) -join ' ') -match 'admin role, so Microsoft 365') (@($o.warnings) -join ' | ')
Check 'live: synced note says reset on-premises' ((Get-Resp $o 'synced.user@contoso.com').password -eq 'skipped-synced') ''
Check 'live: no account blocked' (@(Get-Calls PATCH '*/users/*' | Where-Object { $_.Body -match 'accountEnabled' }).Count -eq 0) ''
$mail = @(Get-Calls POST 'https://graph.microsoft.com/v1.0/users/alerts@example-msp.test/sendMail')
Check 'live: manager emailed for alice and synced user (admin has no manager)' ($mail.Count -eq 2) $mail.Count
$mb = $mail[0].Body | ConvertFrom-Json
Check 'live: manager email goes to the manager' ($mb.message.toRecipients[0].emailAddress.address -eq 'bob.manager@contoso.com') ''
Check 'live: manager email has no risk detail' ($mb.message.body.content -match 'unusual sign-in activity' -and $mb.message.body.content -notmatch '203\.0\.113|Lagos|leaked|unfamiliar|high risk') $mb.message.body.content
$sm = @($mail | Where-Object { ($_.Body | ConvertFrom-Json).message.body.content -match 'Sam Synced' })[0].Body | ConvertFrom-Json
Check 'live: synced user email does not promise a password change' ($sm.message.body.content -notmatch 'set a new password') ''
Check 'live: warning for a user with no manager' ((@($o.warnings) -join ' ') -match 'admin\.ceo@contoso\.com has no manager') ''
Check 'live: message is plain sentences' ($o.message -match '^4 users are at high risk\.' -and $o.message -match 'existing@contoso\.com \(ticket 4242\)' -and $o.message -match 'holds an admin role') $o.message
Check 'live: public note has no detail' ($o.public_note -match 'unusual sign-in activity on 3 accounts' -and $o.public_note -notmatch '@|203\.') $o.public_note
Check 'live: internal note carries the detail' ($o.internal_note -match '203\.0\.113\.45') ''
Check 'live: ticket_id output' ($o.ticket_id -match '^50\d\d$' -and @($o.tickets).Count -eq 3) "$($o.ticket_id)"

# 2b. Zendesk with no PSA-CompanyId: the company is matched by its CloudRadial name (exact match only).
$Mock.NextId = 6500
$r = Invoke-Workflow @{ psa = 'zendesk' }
Check 'name lookup: CloudRadial name matched exactly to the Zendesk organization' ($r.error -eq '' -and @(Get-Calls GET '*/organizations/autocomplete*').Count -eq 1 -and @(Get-Calls POST 'https://examplemsp.zendesk.test/api/v2/tickets' | Where-Object { ($_.Body | ConvertFrom-Json).ticket.organization_id -eq 360001 }).Count -eq 3) "$($r.error)"
Check 'name lookup: the match is recorded in actions' ((@($r.out.actions) -join ' ') -match "Matched CloudRadial company 'Contoso' to Zendesk company 360001") (@($r.out.actions) -join ' | ')

# 3. min_risk medium adds medium-risk users.
$r = Invoke-Workflow @{ min_risk = 'medium'; preview = 'true' }
Check 'medium: medium-risk user included' ($null -ne (Get-Resp $r.out 'medium.user@contoso.com') -and @($r.out.responses).Count -eq 5) (@($r.out.responses | ForEach-Object { $_.upn }) -join ', ')

# 4. Zendesk.
$Mock.NextId = 6000
$r = Invoke-Workflow @{ psa = 'zendesk'; psa_company_id = '360001' }
$o = $r.out
Check 'zendesk: no error' ($r.error -eq '' -and $o.status -eq 'success') "$($r.error) $($o.status)"
Check 'zendesk: existing ticket found by search' ((Get-Resp $o 'existing@contoso.com').ticket_id -eq '777') ''
$zp = @(Get-Calls POST 'https://examplemsp.zendesk.test/api/v2/tickets' | ForEach-Object { ($_.Body | ConvertFrom-Json).ticket })
Check 'zendesk: three tickets, admin urgent, others high' ($zp.Count -eq 3 -and @($zp | Where-Object { $_.priority -eq 'urgent' }).Count -eq 1 -and @($zp | Where-Object { $_.priority -eq 'high' }).Count -eq 2 -and @($zp | Where-Object { $_.organization_id -eq 360001 }).Count -eq 3) ''
Check 'zendesk: opening comment has no risk detail' (-not @($zp | Where-Object { $_.comment.body -match '203\.0\.113|198\.51' }).Count) ''
$zn = @(Get-Calls PUT 'https://examplemsp.zendesk.test/api/v2/tickets/*' | ForEach-Object { ($_.Body | ConvertFrom-Json).ticket.comment })
Check 'zendesk: detail goes in private comments' ($zn.Count -eq 3 -and @($zn | Where-Object { $_.public -eq $false }).Count -eq 3 -and @($zn | Where-Object { $_.body -match '198\.51\.100\.7' }).Count -eq 1) ''

# 5. Kaseya BMS: its open tickets are listed (no text search) and matched here, scoped to the company.
$Mock.NextId = 7000
$r = Invoke-Workflow @{ psa = 'kaseyabms'; psa_company_id = '88' }
$o = $r.out
Check 'kaseya: no error' ($r.error -eq '' -and $o.status -eq 'success') "$($r.error) $($o.status) $($o.message)"
$kl = @(Get-Calls GET 'https://bms.example-msp.test/v2/servicedesk/tickets[?]*')
Check 'kaseya: open tickets listed for company 88 only' ($kl.Count -ge 1 -and @($kl | Where-Object { $_.Uri -match 'Filter\.AccountIds=88' -and $_.Uri -match 'Filter\.ExcludeCompleted=1' }).Count -eq $kl.Count) (@($kl | ForEach-Object { $_.Uri }) -join ' | ')
Check 'kaseya: four tickets; another company''s matching ticket is ignored' (@(Get-Calls POST 'https://bms.example-msp.test/v2/servicedesk/tickets').Count -eq 4 -and (Get-Resp $o 'alice@contoso.com').dedupe -eq 'psa' -and (Get-Resp $o 'synced.user@contoso.com').outcome -eq 'handled') ''
Check 'kaseya: no archive log needed' (@(Get-Calls POST 'https://portal.example-msp.test/v2/archiveitem').Count -eq 0) ''
$kn = @(Get-Calls POST 'https://bms.example-msp.test/v2/servicedesk/tickets/*/notes' | ForEach-Object { $_.Body | ConvertFrom-Json })
Check 'kaseya: internal notes' ($kn.Count -eq 4 -and @($kn | Where-Object { $_.IsInternal -eq $true }).Count -eq 4) ''
$r = Invoke-Workflow @{ psa = 'kaseyabms'; psa_company_id = '88' } @{} @{ BmsExisting = $true }
Check 'kaseya: open risky ticket found, user not handled again' ((Get-Resp $r.out 'alice@contoso.com').outcome -eq 'already-open' -and (Get-Resp $r.out 'alice@contoso.com').ticket_id -eq '9200' -and @(Get-Calls POST '*/users/u1/revokeSignInSessions').Count -eq 0 -and @(Get-Calls POST 'https://bms.example-msp.test/v2/servicedesk/tickets').Count -eq 3) "$((Get-Resp $r.out 'alice@contoso.com').outcome)"
# Kaseya BMS list failure: archive log fallback, then a rerun finds the log.
$r = Invoke-Workflow @{ psa = 'kaseyabms'; psa_company_id = '88' } @{} @{ SearchFail = $true }
$logs = @(Get-Calls POST 'https://portal.example-msp.test/v2/archiveitem' | ForEach-Object { $_.Body | ConvertFrom-Json })
Check 'kaseya list failure: each handled user logged in the Risky Sign-ins archive' ((Get-Resp $r.out 'alice@contoso.com').dedupe -eq 'archive' -and $logs.Count -eq 4 -and @($logs | Where-Object { $_.subject -like 'Risky sign-in handled: *' -and $_.archiveId -eq 66 }).Count -eq 4) (@($logs | ForEach-Object { $_.subject }) -join ' | ')
Check 'kaseya list failure: log holds no IP or location' (-not @($logs | Where-Object { $_.text -match '203\.0\.113|Lagos|198\.51' }).Count -and @($logs | Where-Object { $_.text -match 'det-a1' }).Count -eq 1) ''
$r = Invoke-Workflow @{ psa = 'kaseyabms'; psa_company_id = '88' } @{} @{ SearchFail = $true; HasArchive = $true; Logged = 'alice@contoso.com' }
Check 'kaseya list failure rerun: logged user not handled again' ((Get-Resp $r.out 'alice@contoso.com').outcome -eq 'already-open' -and @(Get-Calls POST '*/users/u1/revokeSignInSessions').Count -eq 0 -and @(Get-Calls POST 'https://bms.example-msp.test/v2/servicedesk/tickets').Count -eq 3) "$((Get-Resp $r.out 'alice@contoso.com').outcome)"

# 6. A PSA search failure falls back to the archive log instead of opening a duplicate blindly.
$r = Invoke-Workflow @{} @{ 'PSA-CompanyId' = '250' } @{ SearchFail = $true; HasArchive = $true; Logged = 'existing@contoso.com' }
Check 'search failure: falls back to the log, warns' ((Get-Resp $r.out 'existing@contoso.com').outcome -eq 'already-open' -and (Get-Resp $r.out 'alice@contoso.com').dedupe -eq 'archive' -and (@($r.out.warnings) -join ' ') -match "Couldn't search ConnectWise") (@($r.out.warnings) -join ' | ')

# 7. Missing IdentityRiskyUser.Read.All.
$r = Invoke-Workflow @{} @{} @{ Risky403 = $true }
Check '403 risky users: plain sentence' ($r.step -eq 'node-find' -and $r.error -eq "Can't read risky users. The app registration needs the IdentityRiskyUser.Read.All application permission, with admin consent. Nothing was changed.") $r.error
Check '403 risky users: status error, no writes' ($r.out.status -eq 'error' -and @(Get-Writes).Count -eq 0) ''

# 8. Tenant without Entra ID P2.
$r = Invoke-Workflow @{} @{} @{ NoP2 = $true }
Check 'no P2: says Entra ID P2' ($r.error -match 'doesn''t have Microsoft Entra ID P2' -and @(Get-Writes).Count -eq 0) $r.error

# 9. Missing IdentityRiskEvent.Read.All.
$r = Invoke-Workflow @{} @{} @{ Det403 = $true }
Check '403 detections: names IdentityRiskEvent.Read.All' ($r.error -match 'IdentityRiskEvent\.Read\.All application permission' -and @(Get-Writes).Count -eq 0) $r.error

# 10. Role read refused: users still ticketed, nobody critical, warning names the permission.
$r = Invoke-Workflow @{ preview = $true } @{} @{ Roles403 = $true }
Check 'roles 403: warning, admin not marked critical' ($r.error -eq '' -and (Get-Resp $r.out 'admin.ceo@contoso.com').priority -eq 'high' -and (@($r.out.warnings) -join ' ') -match 'RoleManagement\.Read\.Directory') (@($r.out.warnings) -join ' | ')

# 11. Empty result.
$r = Invoke-Workflow $null @{} @{ Empty = $true }
Check 'empty: success with a plain message' ($r.error -eq '' -and $r.out.status -eq 'success' -and $r.out.message -match '^No users are at high risk') "$($r.out.status) $($r.out.message)"
Check 'empty: no PSA or CloudRadial calls, no writes' (@($Mock.Calls | Where-Object { $_.Uri -like 'https://cw.*' -or $_.Uri -like 'https://portal.*' }).Count -eq 0 -and @(Get-Writes).Count -eq 0) ''

# 12. No Notify-FromMailbox: no mail, a warning.
$r = Invoke-Workflow @{} @{ 'PSA-CompanyId' = '250'; 'Notify-FromMailbox' = $null }
Check 'no mailbox: no mail, warning' (@(Get-Calls POST '*/sendMail').Count -eq 0 -and (@($r.out.warnings) -join ' ') -match 'Notify-FromMailbox' -and $r.out.status -eq 'success') (@($r.out.warnings) -join ' | ')

# 13. PSA company can't be matched: stop before any change.
$r = Invoke-Workflow @{} @{} @{ NoPsaCompany = $true }
Check 'no PSA company: error with the fix named' ($r.step -eq 'node-respond' -and $r.out.status -eq 'error' -and $r.error -match 'PSA-CompanyId') $r.error
Check 'no PSA company: nothing changed' (@(Get-GraphWrites).Count -eq 0 -and @(Get-Calls POST '*/service/tickets').Count -eq 0) ''

# 14. Revoke fails: reported as an error, ticket still opened.
$r = Invoke-Workflow @{} @{ 'PSA-CompanyId' = '250' } @{ FailRevoke = $true }
Check 'revoke failure: status error, tickets still opened' ($r.out.status -eq 'error' -and $r.out.counts.errors -eq 3 -and @(Get-Calls POST 'https://cw.example-msp.test/v4_6_release/apis/3.0/service/tickets').Count -eq 3 -and $r.out.message -match "Couldn't sign the user out") $r.out.message

# 15. Block preview: nothing blocked, only still-at-risk accounts planned.
$r = Invoke-Workflow @{ block_upns = 'alice@contoso.com, remediated@contoso.com; synced.user@contoso.com nobody@contoso.com' } @{ 'PSA-CompanyId' = '250' }
$o = $r.out
Check 'block preview: no error' ($r.error -eq '') $r.error
Check 'block preview: only alice planned' (@($o.block.planned).Count -eq 1 -and $o.block.planned[0] -eq 'alice@contoso.com') (@($o.block.planned) -join ', ')
Check 'block preview: skipped with reasons' (@($o.block.skipped).Count -eq 3 -and (@($o.block.skipped | ForEach-Object { $_.reason }) -join ' ') -match 'Not at risk now \(Microsoft shows remediated\)' -and (@($o.block.skipped | ForEach-Object { $_.reason }) -join ' ') -match 'Synced from on-premises' -and (@($o.block.skipped | ForEach-Object { $_.reason }) -join ' ') -match 'No such user') (@($o.block.skipped | ForEach-Object { "$($_.requested): $($_.reason)" }) -join ' | ')
Check 'block preview: no account disabled' (@(Get-Calls PATCH '*/users/*' | Where-Object { $_.Body -match 'accountEnabled' }).Count -eq 0) ''
Check 'block preview: pending_confirmation and says how' ($o.status -eq 'pending_confirmation' -and $o.message -match 'confirm set to true to block: alice@contoso\.com') $o.message

# 16. Block confirm (ConnectWise): blocks alice, notes her ticket.
$Mock.NextId = 8000
$r = Invoke-Workflow @{ confirm = 'true'; block_upns = 'alice@contoso.com,remediated@contoso.com' } @{ 'PSA-CompanyId' = '250' }
$o = $r.out
Check 'block confirm: no error' ($r.error -eq '' -and $o.status -eq 'success') "$($r.error) $($o.status) $($o.message)"
$dis = @(Get-Calls PATCH '*/users/*' | Where-Object { $_.Body -match 'accountEnabled' })
Check 'block confirm: only alice disabled' ($dis.Count -eq 1 -and $dis[0].Uri -like '*/users/u1' -and ($dis[0].Body | ConvertFrom-Json).accountEnabled -eq $false) (@($dis | ForEach-Object { $_.Uri }) -join ', ')
Check 'block confirm: alice signed out again after block' (@(Get-Calls POST '*/users/u1/revokeSignInSessions').Count -eq 2) ''
$tid = (Get-Resp $o 'alice@contoso.com').ticket_id
Check 'block confirm: block noted on her ticket' (@(Get-Calls POST "https://cw.example-msp.test/*/service/tickets/$tid/notes" | Where-Object { ($_.Body | ConvertFrom-Json).text -match 'confirmed blocking alice@contoso\.com' }).Count -eq 1) $tid
Check 'block confirm: message and public note' ($o.message -match 'Blocked sign-in and signed out: alice@contoso\.com' -and $o.public_note -match 'temporarily turned off sign-in for 1 account') $o.message

# 17. Block confirm on a user that is no longer at risk: rejected, nothing changed.
$r = Invoke-Workflow @{ confirm = $true; block_upns = 'remediated@contoso.com' } @{ 'PSA-CompanyId' = '250' } @{ Empty = $true }
Check 'block not at risk: rejected, nothing disabled' ($r.out.status -eq 'rejected' -and @(Get-Calls PATCH '*/users/*').Count -eq 0) "$($r.out.status) $($r.out.message)"

# 17b. Rerun writes nothing twice.
# The response note is marker-guarded: a second write of the same ticket's note is skipped.
Clear-Notes; $Mock.NextId = 8500
$r = Invoke-Workflow @{} @{ 'PSA-CompanyId' = '250' }
$TAliceT = [string](Get-Resp $r.out 'alice@contoso.com').ticket_id
Check 'rerun: first run notes carry the marker with the ticket id only' ((Get-MockNotes $TAliceT).Count -eq 1 -and ((Get-MockNotes $TAliceT)[0].text).Contains("[risky-signin: $TAliceT]") -and (Get-MockNotes $TAliceT)[0].public -eq $false) "$TAliceT"
Check 'rerun: no marker holds a name or address' (-not @($Mock.Notes.Values | ForEach-Object { $_ } | Where-Object { $_.text -match '\[risky-signin[^\]]*@' }).Count) ''
# The same run retried: the open ticket is found by its summary, so no second ticket, sign-out or note.
$r = Invoke-Workflow @{} @{ 'PSA-CompanyId' = '250' } @{ OpenRisky = @{ upn = 'alice@contoso.com'; id = [int]$TAliceT } }
Check 'rerun: alice already open, nothing written for her' ((Get-Resp $r.out 'alice@contoso.com').outcome -eq 'already-open' -and @(Get-Calls POST '*/users/u1/revokeSignInSessions').Count -eq 0 -and @(Get-Calls POST "https://cw.example-msp.test/*/service/tickets/$TAliceT/notes").Count -eq 0 -and (Get-MockNotes $TAliceT).Count -eq 1) "$((Get-Resp $r.out 'alice@contoso.com').outcome)"
# Block confirm retried the same day: the block note is written once.
Clear-Notes; $Mock.NextId = 8600
$r = Invoke-Workflow @{ confirm = 'true'; block_upns = 'alice@contoso.com' } @{ 'PSA-CompanyId' = '250' }
$TBlockT = [string](Get-Resp $r.out 'alice@contoso.com').ticket_id
$TBefore = @(Get-MockNotes $TBlockT | Where-Object { $_.text -match 'confirmed blocking' }).Count
$r = Invoke-Workflow @{ confirm = 'true'; block_upns = 'alice@contoso.com' } @{ 'PSA-CompanyId' = '250' } @{ OpenRisky = @{ upn = 'alice@contoso.com'; id = [int]$TBlockT } }
Check 'rerun block: block note written once, marked with ticket id and date' ($TBefore -eq 1 -and @(Get-MockNotes $TBlockT | Where-Object { $_.text -match 'confirmed blocking' }).Count -eq 1 -and @(Get-MockNotes $TBlockT | Where-Object { $_.text.Contains("[risky-signin-block: $TBlockT $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'))]") }).Count -eq 1 -and (@($r.out.actions) -join ' ') -match 'already noted') (@($r.out.actions) -join ' | ')
Check 'every ticket note this workflow writes is internal' (-not @($Mock.Notes.Values | ForEach-Object { $_ } | Where-Object { $_.public }).Count) ''

# 18. Bad input fails closed before any call.
$r = Invoke-Workflow @{ min_risk = 'low' }
Check 'bad min_risk: incomplete in Read inputs, no calls' ($r.step -eq 'node-inputs' -and $r.out.status -eq 'incomplete' -and $Mock.Calls.Count -eq 0) $r.error

# 19. Wrong tenant is rejected before reading anything.
$r = Invoke-Workflow @{ tenant_id = '11111111-1111-1111-1111-111111111111' }
Check 'wrong tenant: rejected' ($r.out.status -eq 'rejected' -and @(Get-Calls GET '*identityProtection*').Count -eq 0) "$($r.out.status) $($r.error)"

Write-Host "$($Tally.pass) passed, $($Tally.fail) failed"
if ($Tally.fail) { exit 1 }
exit 0
