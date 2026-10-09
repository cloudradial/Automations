# === STEP: Read inputs ===
# Edit this file, then run: node automationai/qbr-data-pack/src/build.js
# Reads the run input (manual run or Routine). A Routine sends no input, so every field has a default.
#   company_id      CloudRadial company number; when blank, the CloudRadial-CompanyId secret is used
#   quarter_days    how many days the review covers (default 90, 30 to 366); tickets are compared with the same span before it
#   preview         true works everything out but leaves the Planner card alone (default false)
#   psa             optional; overrides the PSA-Type secret (connectwise, autotask, halopsa, kaseyabms, syncro, zendesk)
#   psa_company_id  optional; the PSA's own id for this client, when CloudRadial's PSA link is missing or wrong
# Read-only: the only write in this workflow is one internal CloudRadial Planner card.

function Get-QbrProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Test-QbrBlank { param($v) return ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v) -or ([string]$v).Trim().StartsWith('@')) }
function Stop-QbrInput {
    param([string]$Why)
    Set-NodeOutput ([ordered]@{ status = 'rejected'; message = $Why; public_note = ''; internal_note = $Why; ticket_id = ''; actions = @(); warnings = @() })
    throw $Why
}

$raw = Get-NodeInput
if ($raw -is [string]) {
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = $null }
    else { try { $raw = $raw | ConvertFrom-Json -ErrorAction Stop } catch { Stop-QbrInput 'The run input is not valid JSON. Send an object such as {"company_id": 9}.' } }
}
$wrap = Get-QbrProp $raw 'trigger'; if ($null -ne $wrap) { $raw = $wrap }
if ($raw -is [string]) { try { $raw = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $raw = $null } }

# company_id
$companyId = 0
$c = Get-QbrProp $raw 'company_id'; if (Test-QbrBlank $c) { $c = Get-QbrProp $raw 'companyId' }
if (-not (Test-QbrBlank $c)) {
    $n = 0
    if (-not [int]::TryParse(([string]$c).Trim(), [ref]$n) -or $n -le 0) { Stop-QbrInput "The company_id input must be a CloudRadial company number, such as 9. It was '$c'." }
    $companyId = $n
}

# quarter_days
$quarterDays = 90
$d = Get-QbrProp $raw 'quarter_days'
if (-not (Test-QbrBlank $d)) {
    $n = 0
    if (-not [int]::TryParse(([string]$d).Trim(), [ref]$n)) { Stop-QbrInput "The quarter_days input must be a whole number of days, such as 90. It was '$d'." }
    if ($n -lt 30 -or $n -gt 366) { Stop-QbrInput "The quarter_days input must be between 30 and 366. It was $n." }
    $quarterDays = $n
}

# preview
$preview = $false
$pv = Get-QbrProp $raw 'preview'
if (-not (Test-QbrBlank $pv)) { $preview = ([string]$pv).Trim() -match '^(?i)(true|yes|1)$' }

# psa and psa_company_id (optional overrides)
$psa = ''
$p = Get-QbrProp $raw 'psa'; if (-not (Test-QbrBlank $p)) { $psa = ([string]$p).Trim() }
$psaCompanyId = ''
$pc = Get-QbrProp $raw 'psa_company_id'
if (-not (Test-QbrBlank $pc)) {
    $psaCompanyId = ([string]$pc).Trim()
    if ($psaCompanyId -notmatch '^\d+$') { Stop-QbrInput "The psa_company_id input must be the PSA's numeric company id, such as 250. It was '$pc'." }
}

$now = (Get-Date).ToUniversalTime()
$q = [int][Math]::Ceiling($now.Month / 3)
Set-NodeOutput ([ordered]@{
        status         = 'ok'
        company_id     = $companyId
        quarter_days   = $quarterDays
        preview        = $preview
        psa            = $psa
        psa_company_id = $psaCompanyId
        runAt          = $now.ToString('yyyy-MM-ddTHH:mm:ssZ')
        quarterLabel   = "Q$q $($now.Year)"
        quarterKey     = "$($now.Year)-Q$q"
        warnings       = @()
    })
