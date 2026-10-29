# Strict-mode harness for secure-score-assessment.yml. Runs the step as the runner does (child scope via
# [scriptblock]::Create) with Key Vault, Entra, Graph and CloudRadial mocked.
# Usage: pwsh -NoProfile -File secure-score-assessment/src/test.ps1   (needs js-yaml on NODE_PATH)
param([string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:RUNNER_KV_NAME = 'kv-test'
$js = "const y=require('js-yaml'),fs=require('fs');const w=y.load(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(w.definition.activities.find(a=>a.properties&&a.properties.script).properties.script)"
$script = node -e $js (Join-Path $Root 'secure-score-assessment/secure-score-assessment.yml') | Out-String
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
    if ($Uri -like 'https://cr.example.com/v2/odata/assessment*') { return [pscustomobject]@{ value = @() } }
    if ($Method -eq 'POST') { $global:Writes++; return [pscustomobject]@{ assessmentId = 7 } }
    throw "Unmocked $Method $Uri"
}
function Invoke-Step { param($In, [string[]]$Roles, [switch]$Deny)
    $global:NodeIn = $In; $global:Roles = $Roles; $global:Deny = [bool]$Deny; $global:NodeOut = $null; $global:Calls = @(); $global:Writes = 0
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

# 3. Apply: creates the assessment, then uploads. The upload uses HttpClient, which isn't mocked, so the run is
#    expected to stop there on the fake host; this checks nothing before it trips strict mode.
$r = Invoke-Step ([pscustomobject]@{ companyId = 1; tenantId = '00000000-0000-0000-0000-000000000001'; mode = 'apply' }) @('SecurityEvents.Read.All')
Check 'apply: creates the assessment and reaches the upload' ($global:Writes -eq 1 -and $r.err -match 'cr\.example\.com') "writes=$($global:Writes) err=$($r.err)"

if ($fail) { Write-Host "$fail failed"; exit 1 } else { Write-Host 'all passed' }
