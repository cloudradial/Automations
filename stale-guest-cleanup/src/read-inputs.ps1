# === NODE: Read inputs ===
# Reads the run input and fills in defaults. A monthly Routine sends no input, so every field is optional:
#   days             how long without a sign-in counts as inactive (default 90, between 30 and 3650)
#   include_guests   also review guest accounts (default true)
#   confirm          false (default) = review only, nothing changes. true = disable the accounts in disable_ids
#   disable_ids      comma-separated user object ids or sign-in names to disable (only used when confirm is true)
#   company_id       CloudRadial company id for the report (default: the CloudRadial-CompanyId secret)
#   tenant_id        optional Microsoft 365 tenant id; when given it must be this runner's tenant
#   psa, ticket_id   optional PSA override, and a ticket that gets an internal note
# A value CloudRadial left as a literal @token (for example "@ticket_id") counts as not given.
$ErrorActionPreference = 'Stop'
function Get-SgProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-SgText {
    param($o, [string[]]$Names)
    foreach ($n in $Names) {
        $v = Get-SgProp $o $n
        if ($null -eq $v) { continue }
        if ($v -is [array]) { $v = (@($v | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ }) -join ',') }
        $t = ([string]$v).Trim()
        if ($t -ne '' -and -not $t.StartsWith('@')) { return $t }
    }
    return ''
}
function Test-SgYes { param([string]$v, [bool]$Default) if ([string]::IsNullOrWhiteSpace($v)) { return $Default }; return (@('true', 'yes', 'y', '1') -contains $v.Trim().ToLowerInvariant()) }
function Stop-SgInput {
    param([string]$Msg)
    Set-NodeOutput ([ordered]@{ status = 'incomplete'; message = $Msg; public_note = ''; internal_note = "Inactive account review did not run: $Msg"; ticket_id = ''; actions = @(); warnings = @() })
    throw $Msg
}

$runIn = Get-NodeInput
foreach ($k in @('trigger', 'body', 'input')) { $w = Get-SgProp $runIn $k; if ($null -ne $w) { $runIn = $w } }
if ($runIn -is [string]) {
    if ([string]::IsNullOrWhiteSpace($runIn)) { $runIn = $null }
    else { try { $runIn = $runIn | ConvertFrom-Json } catch { Stop-SgInput 'The run input is text that is not valid JSON. Nothing was changed.' } }
}

$daysText = Get-SgText $runIn @('days', 'inactiveDays', 'inactive_days')
$days = 90
if ($daysText -ne '') {
    if ($daysText -notmatch '^\d+$' -or [int64]$daysText -lt 30 -or [int64]$daysText -gt 3650) { Stop-SgInput "days must be a whole number from 30 to 3650 (it was '$daysText'). Nothing was changed." }
    $days = [int]$daysText
}
$includeGuests = Test-SgYes (Get-SgText $runIn @('include_guests', 'includeGuests')) $true
$confirm = Test-SgYes (Get-SgText $runIn @('confirm', 'approvedToWrite')) $false

$warnings = @()
$ids = @()
foreach ($part in ((Get-SgText $runIn @('disable_ids', 'disableIds')) -split '[,;\s]+')) {
    $t = $part.Trim().Trim('"', "'")
    if ($t -eq '') { continue }
    if ($t -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$' -or $t -match '^[^@\s]+@[^@\s]+$') { if ($ids -notcontains $t.ToLowerInvariant()) { $ids += $t.ToLowerInvariant() } }
    else { $warnings += "Ignored '$t' in disable_ids: it is neither a user object id nor a sign-in name." }
}
if (-not $confirm -and $ids.Count) { $warnings += 'disable_ids was given but confirm is false, so this run only previews those accounts.' }

$companyId = Get-SgText $runIn @('company_id', 'companyId', 'CompanyId')
if ($companyId -eq '') {
    $sec = $null
    try { $sec = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'CloudRadial-CompanyId' -AsPlainText -ErrorAction SilentlyContinue } catch { }
    if (-not [string]::IsNullOrWhiteSpace($sec)) { $companyId = $sec.Trim() }
}
if ($companyId -ne '' -and $companyId -notmatch '^\d+$') { Stop-SgInput "company_id must be the CloudRadial company number (it was '$companyId'). Nothing was changed." }

$tenantIn = (Get-SgText $runIn @('tenant_id', 'tenantId', 'companyTenantId', 'CompanyTenantId')).ToLowerInvariant()
if ($tenantIn -ne '' -and $tenantIn -notmatch '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') { Stop-SgInput "tenant_id must be a Microsoft 365 tenant id (a GUID). It was '$tenantIn'. Nothing was changed." }

Set-NodeOutput ([ordered]@{
        status        = 'running'
        message       = ''
        public_note   = ''
        internal_note = ''
        ticket_id     = (Get-SgText $runIn @('ticket_id', 'ticketId', 'TicketId'))
        actions       = @()
        warnings      = @($warnings)
        inputs        = [ordered]@{
            days           = $days
            include_guests = $includeGuests
            confirm        = $confirm
            disable_ids    = @($ids)
            company_id     = $companyId
            tenant_id      = $tenantIn
            psa            = (Get-SgText $runIn @('psa', 'PSA'))
        }
    })
