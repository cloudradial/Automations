# === STEP: Read inputs ===
# Edit this file, then run: node automationai/license-reclamation/src/build.js
# Reads the run input (manual run or Routine). A Routine sends no input, so every field has a default.
#   days             inactivity threshold in days (default 60, 14 to 365)
#   price_overrides  optional JSON map of skuPartNumber to monthly price, e.g. {"SPB": 20.5}
#   company_id       CloudRadial company id; when blank, the CloudRadial-CompanyId secret or the tenant match is used
#   preview          optional; true works everything out but leaves the Planner card alone
# Read-only: nothing in this workflow removes or changes a licence.

function Get-LrProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Test-LrBlank { param($v) return ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v) -or ([string]$v).Trim().StartsWith('@')) }
function Stop-LrInput {
    param([string]$Why)
    Set-NodeOutput ([ordered]@{ status = 'rejected'; message = $Why; public_note = ''; internal_note = $Why; ticket_id = ''; actions = @(); warnings = @() })
    throw $Why
}

$raw = Get-NodeInput
if ($raw -is [string]) {
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = $null }
    else { try { $raw = $raw | ConvertFrom-Json -ErrorAction Stop } catch { Stop-LrInput 'The run input is not valid JSON. Send an object such as {"days": 60}.' } }
}
$wrap = Get-LrProp $raw 'trigger'; if ($null -ne $wrap) { $raw = $wrap }
if ($raw -is [string]) { try { $raw = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $raw = $null } }

# days
$days = 60
$d = Get-LrProp $raw 'days'
if (-not (Test-LrBlank $d)) {
    $n = 0
    if (-not [int]::TryParse(([string]$d).Trim(), [ref]$n)) { Stop-LrInput "The days input must be a whole number of days, such as 60. It was '$d'." }
    if ($n -lt 14 -or $n -gt 365) { Stop-LrInput "The days input must be between 14 and 365. It was $n." }
    $days = $n
}

# price_overrides: a JSON string or an object, skuPartNumber -> monthly price
$overrides = [ordered]@{}
$po = Get-LrProp $raw 'price_overrides'
if (-not (Test-LrBlank $po) -or ($null -ne $po -and $po -isnot [string])) {
    if ($po -is [string]) { try { $po = $po | ConvertFrom-Json -ErrorAction Stop } catch { Stop-LrInput 'The price_overrides input is not valid JSON. Use a map such as {"SPB": 20.5}.' } }
    $pairs = @()
    if ($null -ne $po -and ($po.GetType().IsValueType -or $po -is [string] -or $po -is [array])) { Stop-LrInput 'The price_overrides input must be a map of SKU to monthly price, such as {"SPB": 20.5}.' }
    if ($po -is [System.Collections.IDictionary]) { $pairs = @($po.Keys | ForEach-Object { @{ k = [string]$_; v = $po[$_] } }) }
    elseif ($null -ne $po) { $pairs = @($po.PSObject.Properties | ForEach-Object { @{ k = [string]$_.Name; v = $_.Value } }) }
    foreach ($p in $pairs) {
        $price = 0.0
        if (-not [double]::TryParse(([string]$p.v).Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$price) -or $price -lt 0) {
            Stop-LrInput "The price_overrides value for $($p.k) must be a monthly price such as 20.5. It was '$($p.v)'."
        }
        $overrides[$p.k.Trim().ToUpperInvariant()] = [Math]::Round($price, 2)
    }
}

# company_id
$companyId = 0
$c = Get-LrProp $raw 'company_id'; if (Test-LrBlank $c) { $c = Get-LrProp $raw 'companyId' }
if (-not (Test-LrBlank $c)) {
    $n = 0
    if (-not [int]::TryParse(([string]$c).Trim(), [ref]$n) -or $n -le 0) { Stop-LrInput "The company_id input must be a CloudRadial company number, such as 9. It was '$c'." }
    $companyId = $n
}

# preview
$preview = $false
$pv = Get-LrProp $raw 'preview'
if (-not (Test-LrBlank $pv)) { $preview = ([string]$pv).Trim() -match '^(?i)(true|yes|1)$' }

Set-NodeOutput ([ordered]@{
        status          = 'ok'
        days            = $days
        price_overrides = $overrides
        company_id      = $companyId
        preview         = $preview
    })
