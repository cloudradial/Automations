# === NODE: Read inputs ===
# Reads the run input and fills in defaults. An hourly Routine sends no input, so every field is optional:
#   min_risk         high (default) = only high-risk users. medium = medium and high
#   lookback_days    how far back to read risk detections for the internal note (default 7, 1 to 90)
#   preview          false (default) = respond to new risky users. true = read and plan only, change nothing
#   notify_manager   true (default) = email each new risky user's manager through Notify-FromMailbox
#   confirm          false (default). true = block the accounts in block_upns (only those still at risk now)
#   block_upns       comma-separated sign-in names to block (only used when confirm is true)
#   company_id       CloudRadial company id (default: the CloudRadial-CompanyId secret)
#   psa              optional PSA override (default: the PSA-Type secret)
#   psa_company_id   the company's id in the PSA (default: the PSA-CompanyId secret, then a lookup by name)
#   tenant_id        optional Microsoft 365 tenant id; when given it must be this runner's tenant
# A value CloudRadial left as a literal @token (for example "@block_upns") counts as not given.
$ErrorActionPreference = 'Stop'
function Get-RsProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-RsText {
    param($o, [string[]]$Names)
    foreach ($n in $Names) {
        $v = Get-RsProp $o $n
        if ($null -eq $v) { continue }
        if ($v -is [array]) { $v = (@($v | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ }) -join ',') }
        $t = ([string]$v).Trim()
        if ($t -ne '' -and -not $t.StartsWith('@')) { return $t }
    }
    return ''
}
function Test-RsYes { param([string]$v, [bool]$Default) if ([string]::IsNullOrWhiteSpace($v)) { return $Default }; return (@('true', 'yes', 'y', '1') -contains $v.Trim().ToLowerInvariant()) }
function Get-RsSecret { param([string]$Name) $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue } catch { }; if ([string]::IsNullOrWhiteSpace($v)) { return '' }; return $v.Trim() }
function Stop-RsInput {
    param([string]$Msg)
    Set-NodeOutput ([ordered]@{ status = 'incomplete'; message = $Msg; public_note = ''; internal_note = "Risky sign-in response did not run: $Msg"; ticket_id = ''; actions = @(); warnings = @() })
    throw $Msg
}

$runIn = Get-NodeInput
foreach ($k in @('trigger', 'body', 'input')) { $w = Get-RsProp $runIn $k; if ($null -ne $w) { $runIn = $w } }
if ($runIn -is [string]) {
    if ([string]::IsNullOrWhiteSpace($runIn)) { $runIn = $null }
    else { try { $runIn = $runIn | ConvertFrom-Json } catch { Stop-RsInput 'The run input is text that is not valid JSON. Nothing was changed.' } }
}

$minRisk = (Get-RsText $runIn @('min_risk', 'minRisk', 'risk_level')).ToLowerInvariant()
if ($minRisk -eq '') { $minRisk = 'high' }
if (@('high', 'medium') -notcontains $minRisk) { Stop-RsInput "min_risk must be high or medium (it was '$minRisk'). Nothing was changed." }

$lbText = Get-RsText $runIn @('lookback_days', 'lookbackDays')
$lookback = 7
if ($lbText -ne '') {
    if ($lbText -notmatch '^\d+$' -or [int64]$lbText -lt 1 -or [int64]$lbText -gt 90) { Stop-RsInput "lookback_days must be a whole number from 1 to 90 (it was '$lbText'). Nothing was changed." }
    $lookback = [int]$lbText
}

$preview = Test-RsYes (Get-RsText $runIn @('preview', 'dry_run', 'dryRun')) $false
$notify = Test-RsYes (Get-RsText $runIn @('notify_manager', 'notifyManager')) $true
$confirm = Test-RsYes (Get-RsText $runIn @('confirm', 'approvedToWrite')) $false

$warnings = @()
$block = @()
foreach ($part in ((Get-RsText $runIn @('block_upns', 'blockUpns', 'block')) -split '[,;\s]+')) {
    $t = $part.Trim().Trim('"', "'")
    if ($t -eq '') { continue }
    if ($t -match '^[^@\s]+@[^@\s]+$' -or $t -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { if ($block -notcontains $t.ToLowerInvariant()) { $block += $t.ToLowerInvariant() } }
    else { $warnings += "Ignored '$t' in block_upns: it is not a sign-in name." }
}
if ($block.Count -and -not $confirm) { $warnings += 'block_upns was given but confirm is false, so this run only previews those blocks.' }
if ($confirm -and $preview) { $warnings += 'preview is true, so confirm was ignored and nothing was blocked.'; $confirm = $false }

$companyId = Get-RsText $runIn @('company_id', 'companyId', 'CompanyId')
if ($companyId -eq '') { $companyId = Get-RsSecret 'CloudRadial-CompanyId' }
if ($companyId -ne '' -and $companyId -notmatch '^\d+$') { Stop-RsInput "company_id must be the CloudRadial company number (it was '$companyId'). Nothing was changed." }

$psaCompany = Get-RsText $runIn @('psa_company_id', 'psaCompanyId', 'CompanyPsaId')
if ($psaCompany -eq '') { $psaCompany = Get-RsSecret 'PSA-CompanyId' }

$tenantIn = (Get-RsText $runIn @('tenant_id', 'tenantId', 'companyTenantId', 'CompanyTenantId')).ToLowerInvariant()
if ($tenantIn -ne '' -and $tenantIn -notmatch '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') { Stop-RsInput "tenant_id must be a Microsoft 365 tenant id (a GUID). It was '$tenantIn'. Nothing was changed." }

Set-NodeOutput ([ordered]@{
        status        = 'running'
        message       = ''
        public_note   = ''
        internal_note = ''
        ticket_id     = ''
        actions       = @()
        warnings      = @($warnings)
        inputs        = [ordered]@{
            min_risk       = $minRisk
            lookback_days  = $lookback
            preview        = $preview
            notify_manager = $notify
            confirm        = $confirm
            block_upns     = @($block)
            company_id     = $companyId
            psa            = (Get-RsText $runIn @('psa', 'PSA'))
            psa_company_id = $psaCompany
            tenant_id      = $tenantIn
        }
    })
