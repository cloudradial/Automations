# Strict-mode harness for domain-expiration-report.yml. Runs each step as the runner does
# (child scope via [scriptblock]::Create) with Key Vault and CloudRadial mocked.
# Usage: pwsh -NoProfile -File domain-expiration-report/src/test.ps1   (needs js-yaml on NODE_PATH)
param([string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:RUNNER_KV_NAME = 'kv-test'
$js = "const y=require('js-yaml'),fs=require('fs');const w=y.load(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(w.definition.activities.find(a=>a.properties&&a.properties.script).properties.script)"
$fail = 0
function Check { param($Name, [bool]$Ok, $Detail) if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name :: $Detail"; $script:fail++ } }

function Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText, $ErrorAction) @{ 'CloudRadial-BaseUrl' = 'https://cr.example.com'; 'CloudRadial-PublicKey' = 'p'; 'CloudRadial-PrivateKey' = 'k' }[$Name] }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Get-NodeInput { $null }
function Invoke-RestMethod { param($Uri, $Method = 'GET', $Headers, $ContentType, $Body)
    $global:Calls += , "$Method $Uri"
    if ($Uri -like '*/v2/odata/company*') { return [pscustomobject]@{ value = @([pscustomobject]@{ companyId = 1; name = 'Contoso Ltd' }) } }
    if ($Uri -like '*/v2/odata/product*') { return [pscustomobject]@{ value = @() } }
    if ($Uri -like '*/v2/odata/domain*' -or $Uri -like '*/v2/odata/certificate*') {
        $soon = (Get-Date).ToUniversalTime().AddDays(10).ToString('o'); $gone = (Get-Date).ToUniversalTime().AddDays(-3).ToString('o'); $far = (Get-Date).ToUniversalTime().AddDays(400).ToString('o')
        return [pscustomobject]@{ value = @(
            [pscustomobject]@{ companyId = 1; name = 'contoso.com'; dateExpires = $soon; registrar = 'Example Registrar'; isDeleted = $false; url = 'https://contoso.com'; issuer = 'Example CA'; dateEnd = $soon; expirationDate = $soon }
            [pscustomobject]@{ companyId = 1; name = 'contoso.net'; dateExpires = $gone; registrar = ''; isDeleted = $false; url = 'https://contoso.net'; issuer = 'Example CA'; dateEnd = $gone; expirationDate = $gone }
            [pscustomobject]@{ companyId = 99; name = 'gone.example'; dateExpires = $soon; registrar = ''; isDeleted = $false; url = 'https://gone.example'; issuer = ''; dateEnd = $soon; expirationDate = $soon }
            [pscustomobject]@{ companyId = 2; name = 'fabrikam.com'; dateExpires = $far; registrar = ''; isDeleted = $false; url = 'https://fabrikam.com'; issuer = ''; dateEnd = $far; expirationDate = $far }
        ) } }
    if ($Method -in 'POST', 'PATCH') { return [pscustomobject]@{ success = $true } }
    throw "Unmocked $Method $Uri"
}

foreach ($n in @('domain-expiration-report')) {
    $script = node -e $js (Join-Path $Root "$n/$n.yml") | Out-String
    foreach ($write in $true, $false) {
        $s = $(if ($write) { $script } else { $script.Replace('$WriteCards = $true ', '$WriteCards = $false') })
        $global:NodeOut = $null; $global:Calls = @()
        $err = $null; try { & ([scriptblock]::Create($s)) } catch { $err = $_.Exception.Message }
        $o = $global:NodeOut | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $posts = @($global:Calls | Where-Object { $_ -like 'POST*' }).Count
        Check "$n write=$write : no error" ($null -eq $err -and $null -ne $o -and $o.status -ne 'error') "$err | $($o | ConvertTo-Json -Compress -Depth 3)"
        Check "$n write=$write : company name on rows" (($o | ConvertTo-Json -Depth 8) -match 'Contoso Ltd' -and ($o | ConvertTo-Json -Depth 8) -match 'Company 2') ($o | ConvertTo-Json -Compress -Depth 4)
        Check "$n write=$write : cards $(if ($write) { 'written for the flagged company only' } else { 'not written' })" ($posts -eq $(if ($write) { 1 } else { 0 })) "posts=$posts"
        if ($write) { Check "$n : company missing from the portal is skipped, not an error" ($o.counts.skippedMissingCompany -eq 1 -and $o.counts.errors -eq 0 -and $o.message -match 'No card for company id\(s\) 99') ($o | ConvertTo-Json -Compress -Depth 4) }
    }
}
if ($fail) { Write-Host "$fail failed"; exit 1 } else { Write-Host 'all passed' }
