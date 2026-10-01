param([switch]$NoAccountManager, [switch]$Empty, [string]$HtmlOut = '')
# Mock harness for audit.ps1 + email.ps1: fake Key Vault, CloudRadial API, and node I/O, in strict mode.
# Assembles audit.ps1 with the shared block from elm.ps1 the same way build-audit.js does.
$global:Out = $null; $global:In = $null; $global:Writes = 0
$env:RUNNER_KV_NAME = 'kv'
function Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText, $ErrorAction) @{ 'CloudRadial-BaseUrl' = 'https://api.test'; 'CloudRadial-PublicKey' = 'pk'; 'CloudRadial-PrivateKey' = 'sk' }[$Name] }
function Get-NodeInput { $global:In }
function Set-NodeOutput { param($o) $global:Out = $o }
function Start-Sleep { param($Seconds) }
$eps = @(
    @{ companyId = 1; name = "Alex's MacBook Air"; os = 'macOS 11.6'; manufacturer = 'Apple'; model = 'MacBook Air'; serialNumber = 'SN0001' },
    @{ companyId = 1; name = 'DESKTOP-0001'; os = 'Windows 11 Pro'; manufacturer = 'Dell'; model = 'Precision 5570'; serialNumber = 'SN0002'; manufacturedDate = '2022-06-22T00:00:00Z'; expirationDate = '2025-06-24T00:00:00Z'; memory = 34359738368 },
    @{ companyId = 1; name = 'CON-"QUOTE"\PC'; os = 'Windows 10 Pro'; manufacturedDate = '2016-03-01T00:00:00Z'; memory = 4294967296 },
    @{ companyId = 1; name = 'CON-SERVER'; os = 'Windows Server 2016'; isServer = $true; expirationDate = '2020-03-01T00:00:00Z' },
    @{ companyId = 1; name = 'win-10-test'; os = 'Windows 10 Pro'; isVirtual = $true; memory = 0 },
    @{ companyId = 1; name = 'OK-LAPTOP'; os = 'Windows 11 Pro'; manufacturedDate = '2025-01-10T00:00:00Z'; expirationDate = '2028-01-10T00:00:00Z'; memory = 17179869184 },
    @{ companyId = 1; name = 'Draytek'; os = '' },
    @{ companyId = 2; name = 'OLD-PC'; os = 'Windows 10 Pro'; manufacturedDate = '2017-01-01T00:00:00Z' },
    @{ companyId = 2; name = 'W11-READY'; os = 'Windows 10 Pro'; windows11Readiness = 'Capable'; manufacturedDate = '2023-05-01T00:00:00Z'; expirationDate = '2026-11-15T00:00:00Z' },
    @{ companyId = 3; name = 'ORPHAN-PC'; os = 'Windows 10 Pro'; manufacturedDate = '2016-01-01T00:00:00Z' }   # company 3 doesn't exist
)
$cos = @(@{ companyId = 1; name = 'Contoso <Ltd> & Co' }, @{ companyId = 2; name = 'Example MSP' }, @{ companyId = 4; name = 'Fabrikam' })
$mockAm = @{ 1 = 'Jordan Lee'; 2 = ''; 4 = 'Sam Patel' }
function Invoke-RestMethod { param($Uri, $Method, $Headers, $Body, $ContentType)
    $u = [uri]::UnescapeDataString($Uri)
    if ($Method -ne 'GET') { $global:Writes++; throw "audit must not write: $Method $u" }
    if ($u -match 'skip=([1-9])') { return [pscustomobject]@{ value = @() } }
    if ($u -match '/v2/odata/company') { return [pscustomobject]@{ value = @($cos | ForEach-Object { [pscustomobject]$_ }) } }
    if ($u -match '/v2/company/(\d+)$') { $c = [ordered]@{ companyId = [int]$Matches[1]; name = 'x' }; if (-not $NoAccountManager) { $c.accountManager = $mockAm[[int]$Matches[1]] }; return [pscustomobject]@{ success = $true; data = [pscustomobject]$c } }
    if ($u -match '/v2/odata/endpoint') { if ($Empty) { return [pscustomobject]@{ value = @() } }; return [pscustomobject]@{ value = @($eps | ForEach-Object { [pscustomobject]$_ }) } }
    throw "unmocked GET $u"
}
$elm = (Get-Content -Raw "$PSScriptRoot\..\..\endpoint-lifecycle-manager\src\elm.ps1") -replace "`r`n", "`n"
if ($elm -notmatch '(?ms)^# ---- shared: begin[^\n]*\n(.*?)^# ---- shared: end ----$') { throw 'shared markers missing in elm.ps1' }
$auditSrc = (Get-Content -Raw "$PSScriptRoot\audit.ps1").Replace('#@@ELM_SHARED@@', $Matches[1])

Set-StrictMode -Version Latest   # as on the runner
$global:In = [pscustomobject]@{ toEmail = @('team@example.com'); message = 'x' }
& ([scriptblock]::Create($auditSrc))
$audit = $global:Out
# Node output reaches the next step as JSON.
$global:In = ($audit | ConvertTo-Json -Depth 12) | ConvertFrom-Json
. "$PSScriptRoot\email.ps1"
Set-StrictMode -Off

$audit.message
"amCheck=$($audit.accountManagerCheck) writes=$global:Writes"
foreach ($c in $audit.companies) { "  [$($c.companyId)] $($c.name) | computers=$($c.computers) other=$($c.otherDevices) crit=$($c.critical) | $(($c.categories.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ') | wExp=$($c.warrantyExpired) wUnk=$($c.warrantyUnknown) | am='$($c.accountManager)' | urgent=$(@($c.urgent).Count) more=$($c.moreFlagged)" }
$e = $global:Out
"subject: $($e.subject)"
"$($e.message)"
# Simulate the Send Audit binding: the body is dropped into a JSON string as-is.
$bad = @(); if ($e.body -match '"') { $bad += 'double quote' }; if ($e.body -match '\\') { $bad += 'backslash' }; if ($e.body -match '[\r\n]') { $bad += 'newline' }
try { $null = ('{"body":"' + $e.body + '"}') | ConvertFrom-Json } catch { $bad += 'JSON parse' }
"binding-safe: $(if ($bad.Count) { 'NO - ' + ($bad -join ', ') } else { 'yes' })"
if ($HtmlOut) { Set-Content -Path $HtmlOut -Value $e.body -Encoding utf8; "html -> $HtmlOut" }
