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

$in = '{"companyId":9,"tenantId":"00000000-0000-0000-0000-000000000000"}'
# upload: the data JSON the step must send (null = no upload).
$scenarios = [ordered]@{
    'plan-new'       = @{ input = '{"companyId":9,"tenantId":"00000000-0000-0000-0000-000000000000","mode":"plan"}'; expect = 'plan'; upload = $null }
    'plan-existing'  = @{ input = '{"companyId":9,"tenantId":"00000000-0000-0000-0000-000000000000","mode":"plan"}'; expect = 'plan'; existing = $true; upload = $null }
    'create'         = @{ input = $in; expect = 'created'; expectId = 700; upload = '{"name":"Microsoft Secure Score","assessmentId":0,"type":20,"companyId":9}' }
    'refresh'        = @{ input = $in; expect = 'refreshed'; existing = $true; expectId = 600; upload = '{"name":"Microsoft Secure Score","assessmentId":600,"type":20,"companyId":9}' }
    'custom-title'   = @{ input = '{"companyId":9,"tenantId":"00000000-0000-0000-0000-000000000000","assessmentTitle":"Contoso Secure Score"}'; expect = 'created'; expectId = 700; upload = '{"name":"Contoso Secure Score","assessmentId":0,"type":20,"companyId":9}' }
    'list-lags'      = @{ input = $in; expect = 'created'; lag = $true; expectId = $null; upload = '{"name":"Microsoft Secure Score","assessmentId":0,"type":20,"companyId":9}' }
    'list-fails'     = @{ input = $in; expect = 'error'; listFails = $true; upload = $null }
}
$failed = 0
foreach ($name in $scenarios.Keys) {
    if ($Scenario -and $name -ne $Scenario) { continue }
    $sc = $scenarios[$name]
    $global:Out = $null
    $global:Writes = New-Object System.Collections.ArrayList
    $global:Uploads = New-Object System.Collections.ArrayList
    $global:Assess = New-Object System.Collections.ArrayList
    $global:Sc = $sc
    if ($sc.Contains('existing')) { $null = $global:Assess.Add([pscustomobject]@{ assessmentId = 600; companyId = 9; title = 'microsoft secure score '; type = 20; isDeleted = $false }) }
    # Rows that must never be matched: a run (type 30), a hidden type 0 row, and a deleted assessment.
    $null = $global:Assess.Add([pscustomobject]@{ assessmentId = 610; companyId = 9; title = 'Microsoft Secure Score'; type = 30; isDeleted = $false })
    $null = $global:Assess.Add([pscustomobject]@{ assessmentId = 611; companyId = 9; title = 'Microsoft Secure Score'; type = 0; isDeleted = $false })
    $null = $global:Assess.Add([pscustomobject]@{ assessmentId = 612; companyId = 9; title = 'Microsoft Secure Score'; type = 20; isDeleted = $true })

    function global:Get-NodeInput { $global:Sc.input }
    function global:Set-NodeOutput { param($o) $global:Out = $o }
    function global:Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText, $ErrorAction) @{ 'CloudRadial-BaseUrl' = 'https://cr.test'; 'CloudRadial-PublicKey' = 'p'; 'CloudRadial-PrivateKey' = 'q'; 'M365-ClientID' = 'a'; 'M365-ClientSecret' = 's' }[$Name] }
    function global:Start-Sleep { param($Seconds) $null = $global:Writes.Add("sleep $Seconds") }
    # Like the live route (204, no body): assessmentId 0 with type 20 creates an assessment titled by
    # "name"; an existing assessmentId replaces its answers in place.
    function global:Send-CrMultipartMock { param($Path, $DataJson, $FileBytes, $FileName)
        $null = $global:Writes.Add("MULTIPART $Path data=$DataJson bytes=$($FileBytes.Length)")
        $null = $global:Uploads.Add($DataJson)
        $global:LastXlsx = $FileBytes
        $d = $DataJson | ConvertFrom-Json
        if ($Path -eq '/v2/assessment/upload' -and $d.assessmentId -eq 0 -and $d.type -eq 20 -and -not $global:Sc.Contains('lag')) { $null = $global:Assess.Add([pscustomobject]@{ assessmentId = 700; companyId = $d.companyId; title = $d.name; type = 20; isDeleted = $false }) }
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
    $problems = New-Object System.Collections.ArrayList
    if ($status -ne $sc.expect) { $null = $problems.Add("status '$status', expected '$($sc.expect)'") }
    if ($sc.Contains('expectId') -and $global:Out) { $got = $global:Out['assessmentId']; if ("$got" -ne "$($sc.expectId)") { $null = $problems.Add("assessmentId '$got', expected '$($sc.expectId)'") } }
    $sent = @($global:Uploads)
    if ($null -eq $sc.upload) { if ($sent.Count) { $null = $problems.Add("uploaded when it shouldn't: $($sent -join ' | ')") } }
    elseif ($sent.Count -ne 1 -or $sent[0] -ne $sc.upload) { $null = $problems.Add("upload data '$($sent -join ' | ')', expected '$($sc.upload)'") }
    if (@($global:Writes | Where-Object { $_ -like 'POST /v2/assessment' }).Count) { $null = $problems.Add('called POST /v2/assessment') }
    if ($problems.Count) { $failed++ }
    "[{0}] {1} {2}: {3}" -f $(if ($problems.Count) { 'FAIL' } else { 'PASS' }), $name, $status, $(if ($global:Out) { $global:Out['message'] } else { $err })
    foreach ($pr in $problems) { "   problem: $pr" }
    if ($problems.Count -and $err) { "   threw: $err" }
}

# The workbook carries a stable Update Key per control: the same control id gives the same key on every run.
$global:LastXlsx = $null
$global:Sc = $scenarios['create']; $global:Assess = New-Object System.Collections.ArrayList; $global:Uploads = New-Object System.Collections.ArrayList
Set-StrictMode -Version Latest; & ([scriptblock]::Create($run)); Set-StrictMode -Off
Add-Type -AssemblyName System.IO.Compression
$zip = New-Object System.IO.Compression.ZipArchive((New-Object System.IO.MemoryStream(, $global:LastXlsx)))
$sst = (New-Object System.IO.StreamReader($zip.GetEntry('xl/sharedStrings.xml').Open())).ReadToEnd()
$keys = @([regex]::Matches($sst, '[0-9a-f]{8}-[0-9a-f]{4}-3[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}') | ForEach-Object { $_.Value } | Select-Object -Unique)
$md5 = [System.Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes('cloudradial/secure-score-assessment/MFARegistrationV2'))
$md5[7] = ($md5[7] -band 0x0f) -bor 0x30; $md5[8] = ($md5[8] -band 0x3f) -bor 0x80
$expectKey = ([guid]::new([byte[]]$md5)).ToString()
if ($keys.Count -eq 2 -and $keys -contains $expectKey) { "[PASS] update-keys: 2 controls, 2 stable keys (MFARegistrationV2 -> $expectKey)" } else { $failed++; "[FAIL] update-keys: found $($keys.Count) keys ($($keys -join ', ')), expected 2 including $expectKey" }

if ($failed) { "$failed check(s) failed"; exit 1 }
'All scenarios passed.'
