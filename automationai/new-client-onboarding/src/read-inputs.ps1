# === NODE: Read inputs ===
# Reads the run input, checks it, and fills in defaults. Nothing is called here.
#   company_name     the new client's name, exactly as it should appear in CloudRadial (required)
#   primary_domain   the client's main email domain, for example contoso.com (required)
#   psa_company_id   the client's company id in the PSA. When empty, the PSA is searched by company_name
#                    and exactly one exact name match is needed
#   company_group    optional CloudRadial company group to add the company to (must already exist)
#   account_manager, territory   optional CloudRadial company fields
#   company_id       optional: an existing CloudRadial company to finish onboarding (for example one made by
#                    Add Companies to the Portal, or a rerun after a partial run). No company is created then
#   ticket_id        optional: an onboarding ticket that already exists. No new ticket is opened then
#   checklist        optional checklist for the ticket: a list, or text with one item per line (or split by ;)
#   ticket_queue     optional board / queue / team / issue type / group id for the ticket
#   tenant_id        optional Microsoft 365 tenant id. Default: the tenant that owns primary_domain
#   include_m365     false skips the Microsoft 365 baseline preview (default true)
#   psa              optional PSA override (connectwise, autotask, halopsa, kaseyabms, syncro, zendesk)
#   confirm          false (default) = preview only, nothing changes. true = create and open the ticket
# A value CloudRadial left as a literal @token (for example "@company_name") counts as not given.
$ErrorActionPreference = 'Stop'
function Get-NcoProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-NcoText {
    param($o, [string[]]$Names)
    foreach ($n in $Names) {
        $v = Get-NcoProp $o $n
        if ($null -eq $v) { continue }
        if ($v -is [array]) { $v = (@($v | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ }) -join "`n") }
        $t = ([string]$v).Trim()
        if ($t -ne '' -and -not $t.StartsWith('@')) { return $t }
    }
    return ''
}
function Test-NcoYes { param([string]$v, [bool]$Default) if ([string]::IsNullOrWhiteSpace($v)) { return $Default }; return (@('true', 'yes', 'y', '1') -contains $v.Trim().ToLowerInvariant()) }
function Stop-NcoInput {
    param([string]$Msg)
    Set-NodeOutput ([ordered]@{ status = 'incomplete'; message = $Msg; public_note = ''; internal_note = "New client onboarding did not run: $Msg"; ticket_id = ''; actions = @(); warnings = @() })
    throw $Msg
}

$runIn = Get-NodeInput
foreach ($k in @('trigger', 'body', 'input')) { $w = Get-NcoProp $runIn $k; if ($null -ne $w) { $runIn = $w } }
if ($runIn -is [string]) {
    if ([string]::IsNullOrWhiteSpace($runIn)) { $runIn = $null }
    else { try { $runIn = $runIn | ConvertFrom-Json } catch { Stop-NcoInput 'The run input is text that is not valid JSON. Nothing was changed.' } }
}

$name = (Get-NcoText $runIn @('company_name', 'companyName', 'name')) -replace '\s+', ' '
if ($name -eq '') { Stop-NcoInput 'company_name is required: the new client''s name as it should appear in CloudRadial. Nothing was changed.' }
if ($name.Length -gt 200) { Stop-NcoInput 'company_name is longer than 200 characters. Nothing was changed.' }

$domain = (Get-NcoText $runIn @('primary_domain', 'primaryDomain', 'domain')).ToLowerInvariant()
$domain = ($domain -replace '^https?://', '' -replace '^www\.', '').TrimEnd('/', '.')
if ($domain -eq '') { Stop-NcoInput 'primary_domain is required: the client''s main email domain, for example contoso.com. Nothing was changed.' }
if ($domain -notmatch '^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$') { Stop-NcoInput "primary_domain must be a domain name such as contoso.com (it was '$domain'). Nothing was changed." }

$psaCompanyId = Get-NcoText $runIn @('psa_company_id', 'psaCompanyId', 'CompanyPsaId')
if ($psaCompanyId -ne '' -and $psaCompanyId -notmatch '^\d+$') { Stop-NcoInput "psa_company_id must be the PSA's number for the company (it was '$psaCompanyId'). Nothing was changed." }

$companyId = Get-NcoText $runIn @('company_id', 'companyId')
if ($companyId -ne '' -and $companyId -notmatch '^\d+$') { Stop-NcoInput "company_id must be a CloudRadial company number (it was '$companyId'). Nothing was changed." }

$ticketId = Get-NcoText $runIn @('ticket_id', 'ticketId', 'TicketId')
if ($ticketId -ne '' -and $ticketId -notmatch '^\d+$') { Stop-NcoInput "ticket_id must be a ticket number (it was '$ticketId'). Nothing was changed." }

$tenantIn = (Get-NcoText $runIn @('tenant_id', 'tenantId', 'CompanyTenantId')).ToLowerInvariant()
if ($tenantIn -ne '' -and $tenantIn -notmatch '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') { Stop-NcoInput "tenant_id must be a Microsoft 365 tenant id (a GUID). It was '$tenantIn'. Nothing was changed." }

# The checklist: a list, or text with one item per line (or split by ; or |). Numbering and boxes are stripped.
$defaultChecklist = @(
    'Confirm the signed agreement, the billing contact and the service start date.',
    'Collect admin access: Microsoft 365 (through GDAP), the domain registrar and line-of-business apps.',
    'Link the company to its Microsoft 365 tenant in CloudRadial and check that users sync.',
    'Install the RMM agent on every computer and check that endpoints appear in CloudRadial.',
    'Document the network: firewall, switches, Wi-Fi, internet provider and IP ranges.',
    'Confirm backups for servers and Microsoft 365, and run a test restore.',
    'Create two break-glass admin accounts and store them in the password vault.',
    'Review the Microsoft 365 security baseline report with the client and agree a rollout date.',
    'Send the portal welcome email and walk the main contact through the portal.',
    'Hold the 30-day check-in and close out onboarding.'
)
$items = @()
$rawList = Get-NcoProp $runIn 'checklist'
$parts = @()
if ($rawList -is [array]) { $parts = @($rawList | ForEach-Object { [string]$_ }) }
else { $t = Get-NcoText $runIn @('checklist'); if ($t -ne '') { $parts = @($t -split '\r?\n|;|\|') } }
foreach ($p in $parts) {
    $s = ([string]$p).Trim() -replace '^(\[\s?[xX ]?\s?\]|[-*]|\d+[.)])\s*', ''
    $s = $s.Trim()
    if ($s -ne '' -and -not $s.StartsWith('@')) { $items += $s }
}
$warnings = @()
if ($items.Count -gt 50) { $warnings += "The checklist had $($items.Count) items; only the first 50 are used."; $items = @($items | Select-Object -First 50) }
$usedDefault = $items.Count -eq 0
if ($usedDefault) { $items = $defaultChecklist }

Set-NodeOutput ([ordered]@{
        status        = 'running'
        message       = ''
        public_note   = ''
        internal_note = ''
        ticket_id     = $ticketId
        actions       = @()
        warnings      = @($warnings)
        inputs        = [ordered]@{
            company_name      = $name
            primary_domain    = $domain
            psa_company_id    = $psaCompanyId
            company_group     = (Get-NcoText $runIn @('company_group', 'companyGroup', 'group'))
            account_manager   = (Get-NcoText $runIn @('account_manager', 'accountManager'))
            territory         = (Get-NcoText $runIn @('territory'))
            company_id        = $companyId
            ticket_id         = $ticketId
            checklist         = @($items)
            checklist_default = $usedDefault
            ticket_queue      = (Get-NcoText $runIn @('ticket_queue', 'ticketQueue', 'queue', 'board'))
            tenant_id         = $tenantIn
            include_m365      = (Test-NcoYes (Get-NcoText $runIn @('include_m365', 'includeM365')) $true)
            psa               = (Get-NcoText $runIn @('psa', 'PSA'))
            confirm           = (Test-NcoYes (Get-NcoText $runIn @('confirm', 'approvedToWrite')) $false)
        }
    })
