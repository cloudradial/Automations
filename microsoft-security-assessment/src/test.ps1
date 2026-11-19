# Mock harness for the three steps. Runs under strict mode like the runner.
#   pwsh -NoProfile -File test.ps1 [-Scenario good|bad|noperm|parent|exists|fail] [-Mode plan] [-Type 20|30]
#   Steps 2 and 3 get common.ps1 with _shared/cloudradial.ps1 pasted in, as build.js does.
param([string]$Scenario = 'good', [string]$Mode = 'apply', [string]$Type = '', [string]$OutDir = "$PSScriptRoot\out")
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null

$script:nodeInput = $null; $script:nodeOutput = $null; $script:calls = New-Object System.Collections.ArrayList
function Get-NodeInput { param([string]$Name) $script:nodeInput }
function Set-NodeOutput { param($o) $script:nodeOutput = $o }
function Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) @{ 'M365-ClientID' = 'cid'; 'M365-ClientSecret' = 'csec'; 'M365-TenantID' = '00000000-0000-0000-0000-000000000001'; 'CloudRadial-BaseUrl' = 'https://api.example.test/'; 'CloudRadial-PublicKey' = 'pub'; 'CloudRadial-PrivateKey' = 'priv' }[$Name] }
function New-HttpError { param([int]$Code, [string]$Msg)
    $resp = New-Object System.Net.Http.HttpResponseMessage([System.Net.HttpStatusCode]$Code)
    $ex = New-Object Microsoft.PowerShell.Commands.HttpResponseException($Msg, $resp)
    $er = New-Object System.Management.Automation.ErrorRecord($ex, 'Http', 'InvalidOperation', $null)
    $er.ErrorDetails = New-Object System.Management.Automation.ErrorDetails((@{ error = @{ code = 'Authorization_RequestDenied'; message = $Msg } } | ConvertTo-Json -Compress))
    throw $er
}
function Start-Sleep { param($Seconds) }
function J { param([string]$s) $s | ConvertFrom-Json }
$script:createdAssessment = $false; $script:upload = $null; $script:createBody = $null
function Invoke-RestMethod { [CmdletBinding()]
    param($Method = 'Get', $Uri, $Headers, $Body, $ContentType)
    $null = $script:calls.Add("$Method $Uri")
    $u = [uri]::UnescapeDataString([string]$Uri)
    switch -Regex ($u) {
        'oauth2/v2.0/token' { return J '{"access_token":"tok"}' }
        '/v2/odata/company\?' { return J '{"value":[{"companyId":9,"name":"Contoso Ltd"}]}' }
        '/v2/odata/assessment\?' { if ($u -match 'skip=([1-9]\d*)') { return [pscustomobject]@{ value = @() } }; return [pscustomobject]@{ value = $script:mockRows.ToArray() } }
        '/v2/assessment$' {
            $b = $Body | ConvertFrom-Json
            $null = $script:mockUploads.Add("POST /v2/assessment '$($b.title)' type $($b.type), $(@($b.questions).Count) questions, first key $($b.questions[0].updateKey)")
            if ($Scenario -eq 'fail') { New-HttpError 400 'The title is required.' }
            $id = 500 + $script:mockRows.Count
            $script:mockRows.Add([pscustomobject]@{ assessmentId = $id; title = $b.title; companyId = $b.companyId; type = 20; status = 0; visibility = 0; isDeleted = $false; updateKey = "key-$id"; compliantScore = 6; partialScore = 2; totalScore = -2; maxScore = 22 })
            return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ assessmentId = $id; type = 20 } } }
        '/v2/assessment/(\d+)/questions' { $b = $Body | ConvertFrom-Json; $null = $script:mockUploads.Add("PUT questions of $($Matches[1]): $(@($b.questions).Count), removeMissing $($b.removeMissing)"); return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ added = 0; updated = @($b.questions).Count; removed = 0 } } }
        '/v2/assessment/(\d+)/answers' { $b = $Body | ConvertFrom-Json; $null = $script:mockUploads.Add("PATCH answers of $($Matches[1]): $(@($b.answers).Count)"); return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ updated = @($b.answers).Count; scores = [pscustomobject]@{ totalScore = 4; maxScore = 22 } } } }
        '/v2/assessment/(\d+)/run$' {
            $b = $Body | ConvertFrom-Json
            $null = $script:mockUploads.Add("POST run of $($Matches[1]) '$($b.name)'")
            $src = @($script:mockRows | Where-Object { $_.assessmentId -eq [int]$Matches[1] })[0]
            $newId = 600 + $script:mockRows.Count
            $row = [pscustomobject]@{ assessmentId = $newId; title = $b.name; companyId = 9; type = 30; status = 0; visibility = 2; isDeleted = $false; updateKey = $src.updateKey; compliantScore = 6; partialScore = 2; totalScore = 4; maxScore = 22 }
            $script:mockRows.Add($row)
            return [pscustomobject]@{ success = $true; data = $row } }
        '/organization' { return J '{"value":[{"displayName":"Contoso"}]}' }
        'identitySecurityDefaultsEnforcementPolicy' { if ($Scenario -eq 'noperm') { New-HttpError 403 'Insufficient privileges to complete the operation.' }; return J '{"isEnabled":false}' }
        'conditionalAccess/policies' {
            if ($Scenario -eq 'noperm') { New-HttpError 403 'Insufficient privileges to complete the operation.' }
            if ($Scenario -eq 'bad') { return J '{"value":[{"displayName":"Sessions only","state":"enabled","conditions":{"users":{"includeUsers":["All"]},"applications":{"includeApplications":["All"]},"clientAppTypes":["all"]},"grantControls":null}]}' }
            return J @'
{"value":[
 {"displayName":"Require MFA - all users","state":"enabled","conditions":{"users":{"includeUsers":["All"],"includeRoles":[]},"applications":{"includeApplications":["All"]},"clientAppTypes":["all"],"userRiskLevels":[],"signInRiskLevels":[]},"grantControls":{"builtInControls":["mfa"]}},
 {"displayName":"Block legacy auth","state":"enabled","conditions":{"users":{"includeUsers":["All"]},"applications":{"includeApplications":["All"]},"clientAppTypes":["exchangeActiveSync","other"]},"grantControls":{"builtInControls":["block"]}},
 {"displayName":"Sign-in risk","state":"enabledForReportingButNotEnforced","conditions":{"users":{"includeUsers":["All"]},"applications":{"includeApplications":["All"]},"clientAppTypes":["all"],"signInRiskLevels":["high","medium"]},"grantControls":{"builtInControls":["mfa"]}}
],"@odata.nextLink":null}
'@ }
        'userRegistrationDetails' {
            if ($u -match 'skiptoken') { return J '{"value":[{"userPrincipalName":"u3@contoso.example","userType":"member","isAdmin":false,"isMfaRegistered":true,"isSsprRegistered":false},{"userPrincipalName":"guest@fabrikam.example","userType":"guest","isAdmin":false,"isMfaRegistered":false,"isSsprRegistered":false}]}' }
            if ($Scenario -eq 'bad') { return J '{"value":[{"userPrincipalName":"admin@contoso.example","userType":"member","isAdmin":true,"isMfaRegistered":false,"isSsprRegistered":false}]}' }
            return J '{"value":[{"userPrincipalName":"admin@contoso.example","userType":"member","isAdmin":true,"isMfaRegistered":true,"isSsprRegistered":true},{"userPrincipalName":"u2@contoso.example","userType":"member","isAdmin":false,"isMfaRegistered":true,"isSsprRegistered":true}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/reports/authenticationMethods/userRegistrationDetails?$skiptoken=abc"}'
        }
        'directoryRoles' { if ($Scenario -eq 'bad') { return [pscustomobject]@{ value = @(1..12 | ForEach-Object { [pscustomobject]@{ '@odata.type' = '#microsoft.graph.user'; userPrincipalName = "admin$_@contoso.example" } }) } }; return J '{"value":[{"@odata.type":"#microsoft.graph.user","userPrincipalName":"admin@contoso.example"},{"@odata.type":"#microsoft.graph.user","userPrincipalName":"breakglass@contoso.example"},{"@odata.type":"#microsoft.graph.servicePrincipal","displayName":"Some app"}]}' }
        'riskyUsers' { if ($Scenario -ne 'good') { New-HttpError 403 'Tenant is not licensed for Entra ID P2.' }; return J '{"value":[{"userPrincipalName":"u2@contoso.example","riskState":"remediated"}]}' }
        'riskDetections' { if ($Scenario -eq 'bad') { return J '{"value":[]}' }; if ($Scenario -ne 'good') { New-HttpError 403 'Tenant is not licensed for Entra ID P2.' }; return J '{"value":[{"riskLevel":"medium"}]}' }
        'secureScores' { if ($Scenario -eq 'bad') { return J '{"value":[{"currentScore":20.5,"maxScore":80}]}' }; return J '{"value":[{"currentScore":61,"maxScore":80}]}' }
        default { throw "Unmocked call: $Method $u" }
    }
}
# Assessments the mock company already has.
$base = 'Microsoft 365 Security Assessment'
$today = $base + ' - ' + (Get-Date).ToUniversalTime().ToString('M/d/yy', [System.Globalization.CultureInfo]::InvariantCulture)
$script:mockUploads = New-Object System.Collections.ArrayList
$script:mockRows = New-Object System.Collections.Generic.List[object]
$script:mockRows.Add([pscustomobject]@{ assessmentId = 12; title = 'Older one'; companyId = 9; type = 30; status = 0; visibility = 2; isDeleted = $false })
if ($Scenario -in @('parent', 'exists')) { $script:mockRows.Add([pscustomobject]@{ assessmentId = 77; title = $base; companyId = 9; type = 20; status = 0; visibility = 2; isDeleted = $false; updateKey = 'key-77' }) }
if ($Scenario -eq 'exists') { $script:mockRows.Add([pscustomobject]@{ assessmentId = 78; title = $today; companyId = 9; type = 30; status = 0; visibility = 2; isDeleted = $false; updateKey = 'key-77' }) }
$script:nodeInput = [pscustomobject]@{ companyName = 'Contoso'; mode = $Mode; assessmentType = $Type }
$Common = (Get-Content -Raw "$PSScriptRoot\common.ps1").Replace("#{{CLOUDRADIAL}}", (Get-Content -Raw "$PSScriptRoot\..\..\_shared\cloudradial.ps1"))
. "$PSScriptRoot\1-review.ps1"
$o1 = $script:nodeOutput
# The runner passes outputs between nodes as JSON.
$script:nodeInput = ($o1 | ConvertTo-Json -Depth 20) | ConvertFrom-Json
. ([scriptblock]::Create($Common))
. "$PSScriptRoot\2-assessment.ps1"
$o2 = $script:nodeOutput
$script:nodeInput = ($o2 | ConvertTo-Json -Depth 20) | ConvertFrom-Json
. ([scriptblock]::Create($Common))
. "$PSScriptRoot\3-run.ps1"
$o3 = $script:nodeOutput

"== $Scenario / $Mode / type '$Type' =="
"step1: $($o1.message)"
foreach ($q in $o1.questions) { '  [{0,2}] {1} | {2}{3}' -f $q.answer, $q.question, $q.notes, $(if ($q.partnerNotes) { "  (partner: $($q.partnerNotes))" }) }
"step2: $($o2.status) - $($o2.message)"
"step3: $($o3.status) - $($o3.message)"
foreach ($u in $script:mockUploads) { "write: $u" }
