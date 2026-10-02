# Runs the workflow's PowerShell node against mocked Graph and CloudRadial APIs, in strict mode
# like the AutomationAI runner. Placeholder data only (Contoso, companyId 9).
#   pwsh -NoProfile -File test.ps1            # all scenarios
param([string]$Scenario = '')
$ErrorActionPreference = 'Stop'

# Pull the script block out of the .yml (the block scalar under "script: |-", indented 10 spaces).
$lines = Get-Content "$PSScriptRoot\secure-score-assessment.yml"
$start = [Array]::FindIndex($lines, [Predicate[string]] { param($l) $l -match '^\s+script: \|-$' })
$body = New-Object System.Collections.ArrayList
for ($i = $start + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -ne '' -and $lines[$i] -notmatch '^ {10}') { break }
    $null = $body.Add($(if ($lines[$i].Length -ge 10) { $lines[$i].Substring(10) } else { '' }))
}
$script = $body -join "`n"

$scenarios = [ordered]@{
    'plan'           = @{ input = '{"companyId":9,"tenantId":"00000000-0000-0000-0000-000000000000","mode":"plan"}'; expect = 'plan' }
    'apply'          = @{ input = '{"companyId":9,"tenantId":"00000000-0000-0000-0000-000000000000"}'; expect = 'created'; expectId = $true }
    'duplicate'      = @{ input = '{"companyId":9,"tenantId":"00000000-0000-0000-0000-000000000000"}'; expect = 'skipped'; existing = $true }
    'list-lags'      = @{ input = '{"companyId":9,"tenantId":"00000000-0000-0000-0000-000000000000"}'; expect = 'created'; lag = $true; expectId = $false }
    'list-fails'     = @{ input = '{"companyId":9,"tenantId":"00000000-0000-0000-0000-000000000000"}'; expect = 'error'; listFails = $true }
}
$failed = 0
foreach ($name in $scenarios.Keys) {
    if ($Scenario -and $name -ne $Scenario) { continue }
    $sc = $scenarios[$name]
    $global:Out = $null
    $global:Writes = New-Object System.Collections.ArrayList
    $global:Assess = New-Object System.Collections.ArrayList
    $global:Sc = $sc
    $today = Get-Date -Format 'yyyy-MM-dd'
    if ($sc.Contains('existing')) { $null = $global:Assess.Add([pscustomobject]@{ assessmentId = 600; companyId = 9; title = "microsoft secure score ($today) "; isDeleted = $false }) }
    $null = $global:Assess.Add([pscustomobject]@{ assessmentId = 601; companyId = 9; title = "Microsoft Secure Score ($today)"; isDeleted = $true })

    function global:Get-NodeInput { $global:Sc.input }
    function global:Set-NodeOutput { param($o) $global:Out = $o }
    function global:Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText, $ErrorAction) @{ 'CloudRadial-BaseUrl' = 'https://cr.test'; 'CloudRadial-PublicKey' = 'p'; 'CloudRadial-PrivateKey' = 'q'; 'M365-ClientID' = 'a'; 'M365-ClientSecret' = 's' }[$Name] }
    function global:Start-Sleep { param($Seconds) $null = $global:Writes.Add("sleep $Seconds") }
    # Like the live route: assessmentId 0 creates the assessment titled by "name" and returns 204 with no body.
    function global:Send-CrMultipartMock { param($Path, $DataJson, $FileBytes, $FileName)
        $null = $global:Writes.Add("MULTIPART $Path data=$DataJson bytes=$($FileBytes.Length)")
        $d = $DataJson | ConvertFrom-Json
        if ($Path -eq '/v2/assessment/upload' -and $d.assessmentId -eq 0 -and -not $global:Sc.Contains('lag')) { $null = $global:Assess.Add([pscustomobject]@{ assessmentId = 700; companyId = $d.companyId; title = $d.name; isDeleted = $false }) }
        ''
    }
    function global:Invoke-RestMethod { param($Uri, $Method = 'GET', $Headers, $Body, $ContentType)
        $u = [uri]$Uri; $p = [uri]::UnescapeDataString($u.PathAndQuery)
        if ($u.Host -eq 'login.microsoftonline.com') { return [pscustomobject]@{ access_token = 't' } }
        if ($p -like '/v1.0/security/secureScores*') { return [pscustomobject]@{ value = @([pscustomobject]@{ currentScore = 40; maxScore = 100; controlScores = @([pscustomobject]@{ controlName = 'MFARegistrationV2'; score = 9 }, [pscustomobject]@{ controlName = 'BlockLegacyAuthentication'; score = 0 }) }) } }
        if ($p -eq '/v1.0/security/secureScoreControlProfiles') { return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'MFARegistrationV2'; title = 'Ensure all users can complete MFA'; controlCategory = 'Identity'; rank = 1; maxScore = 9; service = 'AzureAD'; deprecated = $false; remediation = '<p>Enable MFA.</p>' }); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/security/secureScoreControlProfiles?$skiptoken=2' } }
        # Last page carries no @odata.nextLink property at all (strict mode must not read it directly).
        if ($p -like '/v1.0/security/secureScoreControlProfiles?*skiptoken*') { return [pscustomobject]@{ value = @([pscustomobject]@{ id = 'BlockLegacyAuthentication'; title = 'Block legacy authentication'; controlCategory = 'Identity'; rank = 2; maxScore = 8; service = 'AzureAD'; deprecated = $false; remediation = 'Use Conditional Access.' }, [pscustomobject]@{ id = 'OldThing'; title = 'Deprecated'; controlCategory = 'Apps'; rank = 9; maxScore = 1; service = 'EXO'; deprecated = $true; remediation = '' }) } }
        if ($u.Host -eq 'cr.test') {
            if ($Method -ne 'GET') { $null = $global:Writes.Add("$Method $p"); if ($u.AbsolutePath -eq '/v2/assessment') { throw 'HTTP 404: Not Found' }; return $null }
            if ($p -like '/v2/odata/assessment*') {
                if ($p -match '\$select') { throw 'HTTP 500: Internal Server Error' }
                if ($global:Sc.Contains('listFails')) { throw 'HTTP 500: Internal Server Error' }
                if ($p -match '\$skip=[1-9]') { return [pscustomobject]@{ value = @() } }
                return [pscustomobject]@{ value = @($global:Assess) }
            }
        }
        throw "unmocked $Method $Uri"
    }
    $run = $script -replace 'function Send-CrMultipart \{', 'function Send-CrMultipart-Real {' -replace 'Send-CrMultipart -Path', 'Send-CrMultipartMock -Path'
    $err = $null
    Set-StrictMode -Version Latest   # the AutomationAI runner runs scripts in strict mode
    try { & ([scriptblock]::Create($run)) } catch { $err = $_.Exception.Message }
    Set-StrictMode -Off

    $status = if ($global:Out) { [string]$global:Out['status'] } else { '' }
    $ok = $status -eq $sc.expect
    if ($ok -and $sc.Contains('expectId')) { $hasId = $null -ne $global:Out['assessmentId']; $ok = $hasId -eq $sc.expectId }
    if (@($global:Writes | Where-Object { $_ -like 'POST /v2/assessment' }).Count) { $ok = $false; $err = "called POST /v2/assessment. $err" }
    if (-not $ok) { $failed++ }
    "[{0}] {1} {2}: {3}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $status, $(if ($global:Out) { $global:Out['message'] } else { $err })
    if (-not $ok -and $err) { "   threw: $err" }
    foreach ($w in $global:Writes) { "   W: $w" }
}
if ($failed) { "$failed scenario(s) failed"; exit 1 }
'All scenarios passed.'
