# Strict-mode harness for secure-score-assessment.yml. Runs the step as the runner does (child scope via
# [scriptblock]::Create) with Key Vault, Entra, Graph and CloudRadial mocked.
# Usage: pwsh -NoProfile -File secure-score-assessment/src/test.ps1   (needs js-yaml on NODE_PATH)
param([string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:RUNNER_KV_NAME = 'kv-test'
$js = "const y=require('js-yaml'),fs=require('fs');const w=y.load(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(w.definition.activities.find(a=>a.properties&&a.properties.script).properties.script)"
$script = node -e $js (Join-Path $Root 'secure-score-assessment/secure-score-assessment.yml') | Out-String
function Start-Sleep { param($Seconds) }
$fail = 0
function Check { param($Name, [bool]$Ok, $Detail) if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name :: $Detail"; $script:fail++ } }

# Secrets follow the active company, the way the runner switches them after Set-DefaultCompany.
# The step's own (default) secrets have no tenant, so the older cases below send tenantId.
$global:ActiveCompany = ''
$base = @{ 'CloudRadial-BaseUrl' = 'https://cr.example.com'; 'CloudRadial-PublicKey' = 'p'; 'CloudRadial-PrivateKey' = 'k'; 'M365-ClientID' = '11111111-2222-3333-4444-555555555555'; 'M365-ClientSecret' = 's' }
$contoso = $base.Clone(); $contoso['M365-TenantID'] = 'aaaaaaaa-0000-0000-0000-00000000c0de'
$global:SecretsByCompany = @{ '' = $base; 'CON-1' = $contoso }
function Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText, $ErrorAction)
    $global:SecretsByCompany[$global:ActiveCompany][$Name] }
function Set-DefaultCompany { param([string]$Company, [string]$Source) $global:ActiveCompany = $Company }
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
    if ($Uri -like 'https://cr.example.com/v2/assessment*') {
        $global:Writes++; $global:CrWrites += , [pscustomobject]@{ Method = $Method; Uri = $Uri; Body = $(if ($Body) { $Body | ConvertFrom-Json } else { $null }) }
        if ($global:CrFail) { throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Response status code does not indicate success: 400 (Bad Request).', [System.Net.Http.HttpResponseMessage]::new(400)) }
        if ($Method -eq 'POST' -and $Uri -eq 'https://cr.example.com/v2/assessment') { return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ assessmentId = 501; type = 20 } } }
        if ($Method -eq 'PUT') { return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ added = 0; updated = 1; removed = 0 } } }
        if ($Method -eq 'PATCH') { return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ updated = 1; scores = [pscustomobject]@{ totalScore = -2; maxScore = 2 } } } }
        if ($Method -eq 'POST' -and $Uri -like '*/run') { return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ assessmentId = 502; type = 30; totalScore = -2; compliantScore = 0; partialScore = 0; maxScore = 2; questionCount = 1 } } }
    }
    throw "Unmocked $Method $Uri"
}
function Invoke-Step { param($In, [string[]]$Roles, [switch]$Deny, [switch]$CrFail, [object[]]$Existing = @())
    $global:NodeIn = $In; $global:Roles = $Roles; $global:Deny = [bool]$Deny; $global:NodeOut = $null; $global:Calls = @(); $global:Writes = 0
    $global:CrWrites = @(); $global:Assessments = @($Existing); $global:CrFail = [bool]$CrFail
    $global:ActiveCompany = ''
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

# 3. Apply: one assessment created or refreshed from JSON, answered, then a dated run. No workbook upload.
$apply = [pscustomobject]@{ companyId = 1; tenantId = '00000000-0000-0000-0000-000000000001'; mode = 'apply' }
$r = Invoke-Step $apply @('SecurityEvents.Read.All')
$w = @($global:CrWrites)
$create = @($w | Where-Object { $_.Method -eq 'POST' -and $_.Uri -eq 'https://cr.example.com/v2/assessment' })
Check 'apply: created as one type 20 assessment titled Microsoft Secure Score, no upload' ($null -eq $r.err -and $r.out.status -eq 'created' -and $create.Count -eq 1 -and $create[0].Body.type -eq 20 -and $create[0].Body.companyId -eq 1 -and $create[0].Body.title -eq 'Microsoft Secure Score' -and @($w | Where-Object { $_.Uri -like '*upload*' }).Count -eq 0) ($r | ConvertTo-Json -Compress -Depth 5)
Check 'apply: one question per control, keyed on the control id' (@($create[0].Body.questions).Count -eq 1 -and $create[0].Body.questions[0].updateKey -eq 'MFARegistrationV2' -and $create[0].Body.questions[0].category -eq 'Identity' -and $create[0].Body.questions[0].remediationInfo -eq 'Turn on MFA.') ($create | ConvertTo-Json -Compress -Depth 6)
$ans = @($w | Where-Object { $_.Method -eq 'PATCH' })
Check 'apply: answered by control id in one call' ($ans.Count -eq 1 -and $ans[0].Uri -like '*/v2/assessment/501/answers?companyId=1' -and $ans[0].Body.answers[0].updateKey -eq 'MFARegistrationV2') ($ans | ConvertTo-Json -Compress -Depth 6)
$run = @($w | Where-Object { $_.Method -eq 'POST' -and $_.Uri -like '*/run' })
Check 'apply: then a dated run named the portal way' ($run.Count -eq 1 -and $run[0].Body.name -match '^Microsoft Secure Score - \d{1,2}/\d{1,2}/\d{2}$' -and $r.out.runId -eq 502 -and $r.out.assessmentId -eq 501) ($r.out | ConvertTo-Json -Compress)
$r = Invoke-Step $apply @('SecurityEvents.Read.All') -Existing @([pscustomobject]@{ assessmentId = 77; title = 'Microsoft Secure Score'; type = 'Assessment'; companyId = 1; isDeleted = $false })
$w = @($global:CrWrites)
Check 'apply again: the same assessment refreshed in place (deprecated controls removed), never created twice' ($r.out.status -eq 'created' -and $r.out.assessmentAction -eq 'updated' -and @($w | Where-Object { $_.Uri -eq 'https://cr.example.com/v2/assessment' }).Count -eq 0 -and @($w | Where-Object { $_.Method -eq 'PUT' -and $_.Uri -like '*/v2/assessment/77/questions*' -and $_.Body.removeMissing }).Count -eq 1 -and @($w | Where-Object { $_.Uri -like '*/77/run' }).Count -eq 1) ($r | ConvertTo-Json -Compress -Depth 5)
$todayRun = "Microsoft Secure Score - $((Get-Date).ToString('M/d/yy', [Globalization.CultureInfo]::InvariantCulture))"
$r = Invoke-Step $apply @('SecurityEvents.Read.All') -Existing @([pscustomobject]@{ assessmentId = 78; title = $todayRun; type = 'Assessment_Run'; companyId = 1; isDeleted = $false })
Check 'apply: today''s run already there is skipped, nothing written' ($r.out.status -eq 'skipped' -and @($global:CrWrites).Count -eq 0) ($r | ConvertTo-Json -Compress -Depth 5)
$r = Invoke-Step $apply @('SecurityEvents.Read.All') -CrFail
Check 'apply: a CloudRadial 400 fails the run with a plain message' ($null -ne $r.err -and $r.out.status -eq 'error' -and $r.out.message -match 'HTTP 400') ($r | ConvertTo-Json -Compress -Depth 5)
$r = Invoke-Step ([pscustomobject]@{ companyId = 1; tenantId = '00000000-0000-0000-0000-000000000001'; mode = 'plan' }) @('SecurityEvents.Read.All') -Existing @([pscustomobject]@{ assessmentId = 77; title = 'Microsoft Secure Score'; type = 'Assessment'; companyId = 1; isDeleted = $false })
Check 'plan: says it would refresh the existing assessment, writes nothing' ($r.out.status -eq 'plan' -and $r.out.message -match 'refresh the assessment' -and $r.out.assessmentId -eq 77 -and @($global:CrWrites).Count -eq 0) ($r | ConvertTo-Json -Compress -Depth 5)

# 4. Which client: the company input picks the AutomationAI company, and the tenant comes from its secrets.
$byName = [pscustomobject]@{ company = 'Contoso Ltd'; companyId = 1; mode = 'plan' }
$r = Invoke-Step $byName @('SecurityEvents.Read.All')
Check 'company without Include all companies: error, no Graph call' ($null -ne $r.err -and $r.out.status -eq 'error' -and $r.out.message -match 'Include all companies' -and @($global:Calls).Count -eq 0) ($r | ConvertTo-Json -Compress -Depth 5)
$global:companies = @([pscustomobject]@{ externalId = 'CON-1'; secretSuffix = 'con-1'; name = 'Contoso Ltd'; aliases = @(); secretPolicies = @() })
$r = Invoke-Step $byName @('SecurityEvents.Read.All')
Check 'company: switches to it and signs in to its saved tenant' ($null -eq $r.err -and $r.out.status -eq 'plan' -and $global:ActiveCompany -eq 'CON-1' -and @($global:Calls)[0] -match 'login\.microsoftonline\.com/aaaaaaaa-0000-0000-0000-00000000c0de/') ($r | ConvertTo-Json -Compress -Depth 5)
$r = Invoke-Step ([pscustomobject]@{ company = 'Contoso Ltd'; companyId = 1; tenantId = '00000000-0000-0000-0000-000000000001'; mode = 'plan' }) @('SecurityEvents.Read.All')
Check 'company: a different tenantId is refused before any call' ($null -ne $r.err -and $r.out.message -match "doesn't match the Microsoft 365 tenant saved for the AutomationAI company 'Contoso Ltd'" -and @($global:Calls).Count -eq 0) ($r | ConvertTo-Json -Compress -Depth 5)
$r = Invoke-Step ([pscustomobject]@{ company = 'contoso ltd'; companyId = 1; tenantId = 'aaaaaaaa-0000-0000-0000-00000000c0de'; mode = 'plan' }) @('SecurityEvents.Read.All')
Check 'company: the matching tenantId is fine' ($null -eq $r.err -and $r.out.status -eq 'plan') ($r | ConvertTo-Json -Compress -Depth 5)
$r = Invoke-Step ([pscustomobject]@{ company = 'Tailspin Toys'; companyId = 1; mode = 'plan' }) @('SecurityEvents.Read.All')
Check 'unknown company: error, nothing switched or called' ($null -ne $r.err -and $r.out.message -match "No AutomationAI company matches 'Tailspin Toys'" -and $global:ActiveCompany -eq '' -and @($global:Calls).Count -eq 0) ($r | ConvertTo-Json -Compress -Depth 5)
$r = Invoke-Step ([pscustomobject]@{ companyId = 1; mode = 'plan' }) @('SecurityEvents.Read.All')
Check 'no company and no tenant anywhere: error' ($null -ne $r.err -and $r.out.message -match "No Microsoft 365 tenant for this step's Company setting") ($r | ConvertTo-Json -Compress -Depth 5)
$r = Invoke-Step ([pscustomobject]@{ company = 'Contoso Ltd'; mode = 'plan' }) @('SecurityEvents.Read.All')
Check 'missing companyId: error' ($null -ne $r.err -and $r.out.message -match 'Need companyId') ($r | ConvertTo-Json -Compress -Depth 5)
Remove-Variable -Name companies -Scope Global

if ($fail) { Write-Host "$fail failed"; exit 1 } else { Write-Host 'all passed' }
