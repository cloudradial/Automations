# Strict-mode harness for secure-score-assessment.yml. Runs the step as the runner does (child scope via
# [scriptblock]::Create) with Key Vault, Entra, Graph and CloudRadial mocked.
# Usage: pwsh -NoProfile -File secure-score-assessment/src/test.ps1   (needs js-yaml on NODE_PATH)
param([string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:RUNNER_KV_NAME = 'kv-test'
$js = "const y=require('js-yaml'),fs=require('fs');const w=y.load(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(w.definition.activities.find(a=>a.properties&&a.properties.script).properties.script)"
$script = node -e $js (Join-Path $Root 'secure-score-assessment/secure-score-assessment.yml') | Out-String
# The upload uses HttpClient, so rename the script's own Send-CrMultipart and let the mock below stand in for it.
$script = $script.Replace('function Send-CrMultipart {', 'function Send-CrMultipart-Real {')
function Send-CrMultipart { param([string]$Path, [string]$DataJson, [byte[]]$FileBytes, [string]$FileName)
    $global:Uploads += , ($DataJson | ConvertFrom-Json)
    if ($global:UploadFail) { if ($global:UploadFail -match '504') { $d = $DataJson | ConvertFrom-Json; $global:Assessments += , [pscustomobject]@{ assessmentId = 502; title = $d.name; type = $d.type; companyId = $d.companyId } }; throw $global:UploadFail }
    if (-not $global:UploadLost) { $d = $DataJson | ConvertFrom-Json; $global:Assessments += , [pscustomobject]@{ assessmentId = 501; title = $d.name; type = $d.type; companyId = $d.companyId } }
    return ''
}
function Start-Sleep { param($Seconds) }
$fail = 0
function Check { param($Name, [bool]$Ok, $Detail) if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name :: $Detail"; $script:fail++ } }

function Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText, $ErrorAction)
    @{ 'CloudRadial-BaseUrl' = 'https://cr.example.com'; 'CloudRadial-PublicKey' = 'p'; 'CloudRadial-PrivateKey' = 'k'; 'M365-ClientID' = '11111111-2222-3333-4444-555555555555'; 'M365-ClientSecret' = 's' }[$Name] }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Get-NodeInput { $global:NodeIn }
function New-Jwt { param([string[]]$Roles)
    $b = { param($s) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s)).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
    $claims = [ordered]@{ appid = '11111111-2222-3333-4444-555555555555' }; if ($Roles) { $claims.roles = $Roles }
    return (& $b '{"alg":"none"}') + '.' + (& $b ($claims | ConvertTo-Json -Compress)) + '.sig'
}
function Invoke-RestMethod { param($Uri, $Method = 'GET', $Headers, $ContentType, $Body, $Form)
    $global:Calls += , "$Method $Uri"
    if ($Uri -like 'https://login.microsoftonline.com/*') { return [pscustomobject]@{ access_token = (New-Jwt $global:Roles) } }
    if ($Uri -like 'https://graph.microsoft.com/*secureScores?*') {
        if ($global:Deny) { throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Response status code does not indicate success: 403 (Forbidden).', [System.Net.Http.HttpResponseMessage]::new(403)) }
        return [pscustomobject]@{ value = @([pscustomobject]@{ currentScore = 40; maxScore = 80; controlScores = @([pscustomobject]@{ controlName = 'MFARegistrationV2'; score = 10 }) }) } }
    if ($Uri -like 'https://graph.microsoft.com/*secureScoreControlProfiles*') {
        return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'MFARegistrationV2'; title = 'Ensure all users can complete MFA'; controlCategory = 'Identity'; rank = 1; maxScore = 10; deprecated = $false; implementationCost = 'Low'; userImpact = 'Low'; threats = @('Account breach'); remediation = 'Turn on MFA.'; actionUrl = 'https://example.com'; service = 'AzureAD'; tier = 'Core' }) } }
    if ($Uri -like 'https://cr.example.com/v2/odata/assessment*') { return [pscustomobject]@{ value = @($global:Assessments) } }
    if ($Method -eq 'POST') { $global:Writes++; throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Response status code does not indicate success: 404 (Not Found).', [System.Net.Http.HttpResponseMessage]::new(404)) }
    throw "Unmocked $Method $Uri"
}
function Invoke-Step { param($In, [string[]]$Roles, [switch]$Deny, [switch]$UploadLost, [string]$UploadFail = '', [object[]]$Existing = @())
    $global:NodeIn = $In; $global:Roles = $Roles; $global:Deny = [bool]$Deny; $global:NodeOut = $null; $global:Calls = @(); $global:Writes = 0
    $global:Uploads = @(); $global:Assessments = @($Existing); $global:UploadLost = [bool]$UploadLost; $global:UploadFail = $UploadFail
    $err = $null; try { & ([scriptblock]::Create($script)) } catch { $err = $_.Exception.Message }
    return [pscustomobject]@{ err = $err; out = $(if ($null -ne $global:NodeOut) { $global:NodeOut | ConvertTo-Json -Depth 6 | ConvertFrom-Json } else { $null }) }
}
$in = [pscustomobject]@{ companyId = 1; tenantId = '00000000-0000-0000-0000-000000000001'; mode = 'plan' }

# 1. Graph refuses: the message names the app, what it has, and what to add; nothing is written.
$r = Invoke-Step $in @('User.Read.All', 'Organization.Read.All') -Deny
Check '403: error output' ($null -ne $r.out -and $r.out.status -eq 'error') ($r | ConvertTo-Json -Compress -Depth 5)
Check '403: names the app and its current permissions' ($r.out.message -match '11111111-2222-3333-4444-555555555555' -and $r.out.message -match 'Organization\.Read\.All, User\.Read\.All') $r.out.message
Check '403: says to add SecurityEvents.Read.All as Application, keeping existing' ($r.out.message -match 'Add SecurityEvents\.Read\.All' -and $r.out.message -match 'not Delegated' -and $r.out.message -match 'existing permissions stay') $r.out.message
Check '403: run fails and nothing is written' ($null -ne $r.err -and $global:Writes -eq 0) "err=$($r.err) writes=$($global:Writes)"
$r = Invoke-Step $in @() -Deny
Check '403 with no roles: says none' ($r.out.message -match 'permissions in tenant [0-9a-f-]+: none\.') $r.out.message

# 2. Permission granted, plan mode: previews and writes nothing.
$r = Invoke-Step $in @('SecurityEvents.Read.All')
Check 'plan: previews the controls' ($null -eq $r.err -and $r.out.status -eq 'plan' -and $r.out.controls -eq 1) ($r | ConvertTo-Json -Compress -Depth 5)
Check 'plan: nothing written' ($global:Writes -eq 0) "writes=$($global:Writes)"

# 3. Apply: the upload creates the assessment (assessmentId 0, type 20); POST /v2/assessment (404) is never called.
$apply = [pscustomobject]@{ companyId = 1; tenantId = '00000000-0000-0000-0000-000000000001'; mode = 'apply' }
$r = Invoke-Step $apply @('SecurityEvents.Read.All')
$u = @($global:Uploads)
Check 'apply: created through one upload, no create call' ($null -eq $r.err -and $r.out.status -eq 'created' -and $global:Writes -eq 0 -and $u.Count -eq 1) ($r | ConvertTo-Json -Compress -Depth 5)
Check 'apply: upload is a new type 20 assessment for the company' ($u.Count -eq 1 -and $u[0].assessmentId -eq 0 -and $u[0].type -eq 20 -and $u[0].companyId -eq 1 -and $u[0].name -match '^Microsoft Secure Score \(\d{4}-\d{2}-\d{2}\)$') ($u | ConvertTo-Json -Compress)
Check 'apply: reports the new assessmentId' ($r.out.assessmentId -eq 501) ($r.out | ConvertTo-Json -Compress)
$r = Invoke-Step $apply @('SecurityEvents.Read.All') -UploadLost
Check 'apply: upload accepted but not found is an error' ($null -ne $r.err -and $r.out.status -eq 'error' -and $r.out.message -match 'no assessment titled') ($r | ConvertTo-Json -Compress -Depth 5)
$r = Invoke-Step $apply @('SecurityEvents.Read.All') -UploadFail 'HTTP 504: gateway timeout'
Check 'apply: upload 504 but created is still success' ($null -eq $r.err -and $r.out.status -eq 'created' -and $r.out.assessmentId -eq 502) ($r | ConvertTo-Json -Compress -Depth 5)
$r = Invoke-Step $apply @('SecurityEvents.Read.All') -UploadFail 'HTTP 400: bad workbook'
Check 'apply: upload 400 stops the run' ($null -ne $r.err -and $r.err -match 'HTTP 400') ($r | ConvertTo-Json -Compress -Depth 5)
$today = "Microsoft Secure Score ($(Get-Date -Format 'yyyy-MM-dd'))"
$r = Invoke-Step $apply @('SecurityEvents.Read.All') -Existing @([pscustomobject]@{ assessmentId = 9; title = $today; type = 20; companyId = 1 })
Check 'apply: same title already there is skipped, no upload' ($r.out.status -eq 'skipped' -and @($global:Uploads).Count -eq 0) ($r | ConvertTo-Json -Compress -Depth 5)

if ($fail) { Write-Host "$fail failed"; exit 1 } else { Write-Host 'all passed' }
