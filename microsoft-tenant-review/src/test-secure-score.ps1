# Strict-mode harness for microsoft-tenant-review.yml's "Secure Score assessment" step. Runs the step from the built
# .yml as the runner does (child scope via [scriptblock]::Create) with Key Vault, Entra, Graph and CloudRadial mocked.
# Placeholder data only (Contoso).
# Usage: node microsoft-tenant-review/src/build.js; pwsh -NoProfile -File microsoft-tenant-review/src/test-secure-score.ps1
param([string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:RUNNER_KV_NAME = 'kv-test'
$yaml = Join-Path $Root '_shared/node_modules/js-yaml'
$js = "const y=require(process.argv[2]),fs=require('fs');const w=y.load(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(w.definition.activities.find(a=>a.id==='secure-score').properties.script)"
$script = node -e $js (Join-Path $Root 'microsoft-tenant-review/microsoft-tenant-review.yml') $yaml | Out-String
function Start-Sleep { param($Seconds) }
$fail = 0
function Check { param($Name, [bool]$Ok, $Detail) if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name :: $Detail"; $script:fail++ } }

$secrets = @{ 'CloudRadial-BaseUrl' = 'https://cr.example.com'; 'CloudRadial-PublicKey' = 'p'; 'CloudRadial-PrivateKey' = 'k'; 'M365-ClientID' = '11111111-2222-3333-4444-555555555555'; 'M365-ClientSecret' = 's' }
function Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText, $ErrorAction) $secrets[$Name] }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Get-NodeInput { $global:NodeIn }
function New-Jwt {
    $b = { param($s) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s)).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
    return (& $b '{"alg":"none"}') + '.' + (& $b '{"appid":"11111111-2222-3333-4444-555555555555","roles":["SecurityEvents.Read.All"]}') + '.sig'
}
function Invoke-RestMethod { [CmdletBinding()] param($Uri, $Method = 'GET', $Headers, $ContentType, $Body, $Form)
    if ($Uri -like 'https://login.microsoftonline.com/*') { return [pscustomobject]@{ access_token = (New-Jwt) } }
    if ($Uri -like 'https://graph.microsoft.com/*secureScores?*') {
        return [pscustomobject]@{ value = @([pscustomobject]@{ currentScore = 40; maxScore = 80; controlScores = @([pscustomobject]@{ controlName = 'MFARegistrationV2'; score = 10 }, [pscustomobject]@{ controlName = 'BlockLegacyAuthentication'; score = 0 }) }) } }
    if ($Uri -like 'https://graph.microsoft.com/*secureScoreControlProfiles*') {
        return [pscustomobject]@{ value = @(
                [pscustomobject]@{ id = 'MFARegistrationV2'; title = 'Ensure all users can complete MFA'; controlCategory = 'Identity'; rank = 1; maxScore = 10; deprecated = $false; remediation = '<p>Turn on MFA.</p>'; service = 'AzureAD' }
                [pscustomobject]@{ id = 'BlockLegacyAuthentication'; title = 'Block legacy authentication'; controlCategory = 'Identity'; rank = 2; maxScore = 8; deprecated = $false; remediation = '<p>Create a Conditional Access policy that blocks legacy sign-in.</p>'; service = 'AzureAD' }) } }
    if ($Uri -like 'https://cr.example.com/v2/odata/assessment*') { return [pscustomobject]@{ value = @($global:Assessments) } }
    if ($Uri -like 'https://cr.example.com/v2/odata/product*') { return [pscustomobject]@{ value = @() } }
    if ($Uri -like 'https://cr.example.com/v2/product*') { $global:Cards++; return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ productId = 900 } } }
    if ($Uri -like 'https://cr.example.com/v2/assessment*') {
        $global:CrWrites += , [pscustomobject]@{ Method = $Method; Uri = $Uri; Body = $(if ($Body) { $Body | ConvertFrom-Json } else { $null }) }
        if ($Method -eq 'POST' -and $Uri -eq 'https://cr.example.com/v2/assessment') { return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ assessmentId = 501; type = 20 } } }
        if ($Method -eq 'PUT') { return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ added = 0; updated = 2; removed = 0 } } }
        if ($Method -eq 'PATCH') { return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ updated = 2; scores = [pscustomobject]@{ totalScore = 0; maxScore = 4 } } } }
        if ($Method -eq 'POST' -and $Uri -like '*/run') { return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ assessmentId = 502; type = 30; totalScore = 0; compliantScore = 2; partialScore = 0; maxScore = 4; questionCount = 2 } } }
    }
    throw "Unmocked $Method $Uri"
}
function Invoke-Step { param($In, [object[]]$Existing = @())
    $global:NodeIn = $In; $global:NodeOut = $null; $global:CrWrites = @(); $global:Cards = 0; $global:Assessments = @($Existing)
    $err = $null; try { & ([scriptblock]::Create($script)) } catch { $err = $_.Exception.Message }
    return [pscustomobject]@{ err = $err; out = $(if ($null -ne $global:NodeOut) { $global:NodeOut | ConvertTo-Json -Depth 8 | ConvertFrom-Json } else { $null }) }
}
$in = [pscustomobject]@{ companyId = 7; tenantId = 'aaaaaaaa-0000-0000-0000-00000000c0de'; companyName = 'Contoso'; mode = 'apply' }
$day = (Get-Date).ToString('M/d/yy', [Globalization.CultureInfo]::InvariantCulture)

$r = Invoke-Step $in
$w = @($global:CrWrites)
$create = @($w | Where-Object { $_.Method -eq 'POST' -and $_.Uri -eq 'https://cr.example.com/v2/assessment' })
Check 'apply: one client-visible assessment named for the client, created from JSON' ($null -eq $r.err -and $r.out.status -eq 'created' -and $create.Count -eq 1 -and $create[0].Body.title -eq 'Contoso Secure Score Assessment' -and $create[0].Body.visibility -eq 2 -and $create[0].Body.category -eq 'Microsoft 365 Security' -and $create[0].Body.recommendations -match 'Identity') ($r | ConvertTo-Json -Compress -Depth 6)
Check 'apply: one question per control, keyed on the control id, plain-text remediation' (@($create[0].Body.questions).Count -eq 2 -and $create[0].Body.questions[0].updateKey -eq 'MFARegistrationV2' -and $create[0].Body.questions[1].remediationInfo -eq 'Create a Conditional Access policy that blocks legacy sign-in.') ($create | ConvertTo-Json -Compress -Depth 6)
$ans = @($w | Where-Object { $_.Method -eq 'PATCH' })[0].Body.answers
Check 'apply: compliant and not-compliant answers by control id' (@($ans).Count -eq 2 -and $ans[0].value -eq 2 -and $ans[1].value -eq -2 -and $ans[1].isFlagged -eq $true) ($ans | ConvertTo-Json -Compress)
$run = @($w | Where-Object { $_.Uri -like '*/run' })
Check 'apply: then a dated run, and the Planner cards still written' ($run.Count -eq 1 -and $run[0].Body.name -eq "Contoso Secure Score Assessment - $day" -and $r.out.runId -eq 502 -and $global:Cards -ge 1 -and @($r.out.plannerCards).Count -ge 1) ($r.out | ConvertTo-Json -Compress -Depth 4)

$old = [pscustomobject]@{ assessmentId = 77; title = 'Contoso Secure Score Assessment'; type = 20; companyId = 7; isDeleted = $false }
$todays = [pscustomobject]@{ assessmentId = 78; title = "Contoso Secure Score Assessment - $day"; type = 30; companyId = 7; isDeleted = $false }
$r = Invoke-Step $in @($old, $todays)
$w = @($global:CrWrites)
Check 'second review the same day: same assessment refreshed in place, new run numbered (2)' ($r.out.status -eq 'created' -and $r.out.assessmentAction -eq 'updated' -and @($w | Where-Object { $_.Uri -eq 'https://cr.example.com/v2/assessment' }).Count -eq 0 -and @($w | Where-Object { $_.Method -eq 'PUT' -and $_.Uri -like '*/v2/assessment/77/questions*' }).Count -eq 1 -and @($w | Where-Object { $_.Uri -like '*/77/run' })[0].Body.name -eq "Contoso Secure Score Assessment - $day (2)") ($r | ConvertTo-Json -Compress -Depth 6)

$r = Invoke-Step ([pscustomobject]@{ companyId = 7; tenantId = 'aaaaaaaa-0000-0000-0000-00000000c0de'; companyName = 'Contoso'; mode = 'plan' }) @($old)
Check 'plan: says it would refresh the existing assessment, writes nothing' ($r.out.status -eq 'plan' -and $r.out.assessmentId -eq 77 -and @($global:CrWrites).Count -eq 0 -and $global:Cards -eq 0) ($r | ConvertTo-Json -Compress -Depth 6)

$r = Invoke-Step ([pscustomobject]@{ companyId = 7; tenantId = '00000000-0000-0000-0000-000000000000'; companyName = 'Contoso' })
Check 'no Microsoft 365 tenant: skipped, nothing written' ($r.out.status -eq 'skipped' -and @($global:CrWrites).Count -eq 0) ($r | ConvertTo-Json -Compress -Depth 6)

if ($fail) { Write-Host "$fail failed"; exit 1 } else { Write-Host 'all passed' }
