param([string]$InputJson = '{}', [switch]$RejectNotes, [int]$FailCompany = 0)
# Mock harness for elm.ps1: fake Key Vault, CloudRadial API, and node I/O.
$global:Writes = New-Object System.Collections.ArrayList
$global:Out = $null
$env:RUNNER_KV_NAME = 'kv'
function Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText, $ErrorAction) @{ 'CloudRadial-BaseUrl' = 'https://api.test'; 'CloudRadial-PublicKey' = 'pk'; 'CloudRadial-PrivateKey' = 'sk' }[$Name] }
function Get-NodeInput { $InputJson | ConvertFrom-Json }
function Set-NodeOutput { param($o) $global:Out = $o }
function Start-Sleep { param($Seconds) }
$eps = @(
    @{ companyId = 1; name = "Alex's MacBook Air"; os = 'macOS 11.6'; manufacturer = 'Apple'; model = 'MacBook Air'; serialNumber = 'SN0001' },
    @{ companyId = 1; name = 'DESKTOP-0001'; os = 'Windows 11 Pro'; manufacturer = 'Dell'; model = 'Precision 5570'; serialNumber = 'SN0002'; enclosure = 'Desktop'; manufacturedDate = '2022-06-22T00:00:00Z'; expirationDate = '2025-06-24T00:00:00Z'; memory = 34359738368 },
    @{ companyId = 1; name = "Sam's MacBook Pro"; os = 'macOS'; manufacturer = 'Apple' },
    @{ companyId = 1; name = 'CON-SERVER'; os = 'Windows Server 2016'; isServer = $true; expirationDate = '2020-03-01T00:00:00Z' },
    @{ companyId = 1; name = 'win-10-test'; os = 'Windows 10 Pro'; isVirtual = $true; memory = 0 },
    @{ companyId = 1; name = 'OK-LAPTOP'; os = 'Windows 11 Pro'; manufacturedDate = '2025-01-10T00:00:00Z'; expirationDate = '2028-01-10T00:00:00Z'; memory = 17179869184 },
    @{ companyId = 1; name = 'Draytek'; os = '' },
    @{ companyId = 2; name = 'OLD-PC'; os = 'Windows 10 Pro'; manufacturedDate = '2017-01-01T00:00:00Z' },
    @{ companyId = 2; name = 'OLD-LAPTOP'; os = 'Windows 10 Pro'; manufacturedDate = '2018-03-01T00:00:00Z'; enclosure = '10' },
    @{ companyId = 3; name = 'ORPHAN-PC'; os = 'Windows 10 Pro'; manufacturedDate = '2016-01-01T00:00:00Z' }   # company 3 doesn't exist
)
$cards = @(
    @{ productId = 145; companyId = 1; subject = 'Endpoint Hardware Refresh - Replace'; status = 'Proposed'; body = '' },
    @{ productId = 146; companyId = 1; subject = 'Endpoint Hardware Refresh - Plan replacement'; status = 'Proposed'; body = '' },
    @{ productId = 147; companyId = 1; subject = 'Endpoint Hardware Refresh - Upgrade in place'; status = 'Proposed'; body = '' },
    @{ productId = 148; companyId = 1; subject = 'Endpoint Hardware Refresh - Needs data'; status = 'Completed'; body = '' },
    @{ productId = 149; companyId = 1; subject = 'Endpoint Hardware Refresh - Human review'; status = 'Proposed'; body = '' },
    @{ productId = 150; companyId = 1; subject = 'Endpoint Hardware Refresh - Virtual machines'; status = 'Proposed'; body = '' },
    @{ productId = 151; companyId = 1; subject = 'Laptop Refresh'; status = 'Proposed'; body = '' }
)
function Invoke-RestMethod { param($Uri, $Method, $Headers, $Body, $ContentType)
    $u = [uri]::UnescapeDataString($Uri)
    if ($Method -ne 'GET') {
        $null = $global:Writes.Add("$Method $($u -replace 'https://api.test','') $Body")
        if ($RejectNotes -and $Body -match 'notes') { throw 'HTTP 400: unknown field notes' }
        if ($FailCompany -and ($Body -match "company $FailCompany /" -or $Body -match "`"companyId`":\s*$FailCompany\b")) { throw 'HTTP 400: mock rejection' }
        if ($Method -eq 'POST') { return [pscustomobject]@{ success = $true; message = ''; data = [pscustomobject]@{ productId = 900 } } }
        return $null
    }
    if ($u -match 'skip=([1-9])') { return [pscustomobject]@{ value = @() } }
    if ($u -match '/v2/odata/company') { return [pscustomobject]@{ value = @(1, 2 | ForEach-Object { [pscustomobject]@{ companyId = $_ } }) } }
    if ($u -match '/v2/odata/endpoint') { $f = $eps; if ($u -match 'companyId eq (\d+)' -and $u -notmatch ' or ') { $f = @($eps | Where-Object { $_.companyId -eq [int]$Matches[1] }) }; return [pscustomobject]@{ value = @($f | ForEach-Object { [pscustomobject]$_ }) } }
    if ($u -match '/v2/odata/product.*companyId eq (\d+)') { $c = [int]$Matches[1]; return [pscustomobject]@{ value = @($cards | Where-Object { $_.companyId -eq $c } | ForEach-Object { [pscustomobject]$_ }) } }
    throw "unmocked GET $u"
}
Set-StrictMode -Version Latest   # as on the runner
. "$PSScriptRoot\elm.ps1"
Set-StrictMode -Off
$o = $global:Out
$o.message
"optionalFieldsDropped: $($o.optionalFieldsDropped) | pricingApplied: $($o.pricingApplied) | estimatedTotal: $(if ($o.Contains('estimatedTotal')) { $o.estimatedTotal }) | warnings: $(@($o.warnings) -join ' / ')"
foreach ($r in $o.results) { "  [$($r.companyId)] $($r.category) | $($r.action) | $($r.priority) | id=$($r.productId) | n=$($r.deviceCount) | est=$($r.estimatedPrice) | $($r.note)" }
"--- writes"
foreach ($w in $global:Writes) { "  " + $w.Substring(0, [Math]::Min(260, $w.Length)) }
