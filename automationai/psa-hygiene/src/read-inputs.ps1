# === NODE: Read inputs ===
# Reads the run input and fills in defaults. A weekly Routine sends no input, so every field is optional:
#   stale_days          an open ticket with no update for this many days is stale (default 14)
#   unassigned_hours    an open ticket with no assignee for longer than this is flagged (default 24)
#   confirm             false (default) = report and preview only. true = make the fixes named in `fix`
#   fix                 comma-separated categories to fix. Only "missing_contact" can be fixed: it sets the
#                       contact when the company has exactly one primary contact. Nothing else is ever fixed.
#   to                  comma-separated email addresses for the report (default: the ServiceManager-Email secret)
#   archive_company_id  CloudRadial company number of YOUR OWN (MSP) company, to keep a copy in its Report Archive
#                       (default: the CloudRadial-InternalCompanyId secret). Never a client company: the report
#                       lists tickets from every client.
#   company_id          optional PSA company id: check only that company's tickets
#   ticket_id           optional internal ticket that gets the report as an internal note when Postmark isn't set up
#   max_tickets         stop after this many open tickets (default 2000)
#   psa                 optional PSA override (default: the PSA-Type secret)
# A value CloudRadial left as a literal @token (for example "@fix") counts as not given.
$ErrorActionPreference = 'Stop'
function Get-PhProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-PhText {
    param($o, [string[]]$Names)
    foreach ($n in $Names) {
        $v = Get-PhProp $o $n
        if ($null -eq $v) { continue }
        if ($v -is [array]) { $v = (@($v | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ }) -join ',') }
        $t = ([string]$v).Trim()
        if ($t -ne '' -and -not $t.StartsWith('@')) { return $t }
    }
    return ''
}
function Test-PhYes { param([string]$v, [bool]$Default) if ([string]::IsNullOrWhiteSpace($v)) { return $Default }; return (@('true', 'yes', 'y', '1') -contains $v.Trim().ToLowerInvariant()) }
function Get-PhSecret { param([string]$Name) $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue } catch { }; return $v }
function Stop-PhInput {
    param([string]$Msg)
    Set-NodeOutput ([ordered]@{ status = 'incomplete'; message = $Msg; public_note = ''; internal_note = "PSA hygiene check did not run: $Msg"; ticket_id = ''; actions = @(); warnings = @() })
    throw $Msg
}
function Get-PhWhole {
    param([string]$Text, [string]$Name, [int]$Default, [int]$Min, [int]$Maxv)
    if ($Text -eq '') { return $Default }
    if ($Text -notmatch '^\d+$' -or [int64]$Text -lt $Min -or [int64]$Text -gt $Maxv) { Stop-PhInput "$Name must be a whole number from $Min to $Maxv (it was '$Text'). Nothing was changed." }
    return [int]$Text
}

$runIn = Get-NodeInput
foreach ($k in @('trigger', 'body', 'input')) { $w = Get-PhProp $runIn $k; if ($null -ne $w) { $runIn = $w } }
if ($runIn -is [string]) {
    if ([string]::IsNullOrWhiteSpace($runIn)) { $runIn = $null }
    else { try { $runIn = $runIn | ConvertFrom-Json } catch { Stop-PhInput 'The run input is text that is not valid JSON. Nothing was changed.' } }
}

$staleDays = Get-PhWhole (Get-PhText $runIn @('stale_days', 'staleDays')) 'stale_days' 14 1 365
$unassignedHours = Get-PhWhole (Get-PhText $runIn @('unassigned_hours', 'unassignedHours')) 'unassigned_hours' 24 1 720
$maxTickets = Get-PhWhole (Get-PhText $runIn @('max_tickets', 'maxTickets')) 'max_tickets' 2000 1 10000
$confirm = Test-PhYes (Get-PhText $runIn @('confirm', 'approvedToWrite')) $false
$warnings = @()

# ---- Fix list: only missing_contact can be fixed ----
$fix = @()
$aliases = @{ 'missing_contact' = 'missing_contact'; 'missing_contacts' = 'missing_contact'; 'no_contact' = 'missing_contact'; 'contact' = 'missing_contact'; 'contacts' = 'missing_contact' }
$known = @('stale', 'stale_tickets', 'wrong_status', 'status', 'unassigned', 'closed_date_open')
foreach ($part in ((Get-PhText $runIn @('fix', 'fixes', 'fix_list')) -split '[,;\s]+')) {
    $t = $part.Trim().Trim('"', "'").ToLowerInvariant()
    if ($t -eq '') { continue }
    if ($aliases.ContainsKey($t)) { if ($fix -notcontains $aliases[$t]) { $fix += $aliases[$t] } }
    elseif ($known -contains $t) { $warnings += "'$t' can't be fixed automatically, so those tickets are only reported. The only safe fix is missing_contact." }
    else { Stop-PhInput "fix can only name missing_contact (it had '$t'). Nothing was changed." }
}
if ($confirm -and -not $fix.Count) { $warnings += 'confirm was true but fix was empty, so nothing was changed. Add fix: "missing_contact" to set missing contacts.' }

$companyId = Get-PhText $runIn @('company_id', 'companyId', 'psa_company_id')
if ($companyId -ne '' -and $companyId -notmatch '^\d+$') { Stop-PhInput "company_id must be the PSA's company number (it was '$companyId'). Nothing was changed." }

$archiveId = Get-PhText $runIn @('archive_company_id', 'archiveCompanyId')
if ($archiveId -eq '') { $sec = Get-PhSecret 'CloudRadial-InternalCompanyId'; if (-not [string]::IsNullOrWhiteSpace($sec)) { $archiveId = $sec.Trim() } }
if ($archiveId -ne '' -and $archiveId -notmatch '^\d+$') { Stop-PhInput "archive_company_id must be a CloudRadial company number (it was '$archiveId'). Nothing was changed." }

$ticketId = Get-PhText $runIn @('ticket_id', 'ticketId', 'TicketId')
if ($ticketId -ne '' -and $ticketId -notmatch '^\d+$') { Stop-PhInput "ticket_id must be a ticket number (it was '$ticketId'). Nothing was changed." }

# ---- Recipients ----
$toText = Get-PhText $runIn @('to', 'email', 'recipients')
if ($toText -eq '') { $sec = Get-PhSecret 'ServiceManager-Email'; if (-not [string]::IsNullOrWhiteSpace($sec)) { $toText = $sec.Trim() } }
$to = @()
foreach ($part in ($toText -split '[,;\s]+')) {
    $t = $part.Trim().Trim('"', "'", '<', '>')
    if ($t -eq '') { continue }
    if ($t -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') { if ($to -notcontains $t.ToLowerInvariant()) { $to += $t.ToLowerInvariant() } }
    else { Stop-PhInput "'$t' in to isn't an email address. Nothing was changed." }
}

Set-NodeOutput ([ordered]@{
        status        = 'running'
        message       = ''
        public_note   = ''
        internal_note = ''
        ticket_id     = $ticketId
        actions       = @()
        warnings      = @($warnings)
        inputs        = [ordered]@{
            stale_days         = $staleDays
            unassigned_hours   = $unassignedHours
            confirm            = $confirm
            fix                = @($fix)
            to                 = @($to)
            archive_company_id = $archiveId
            company_id         = $companyId
            ticket_id          = $ticketId
            max_tickets        = $maxTickets
            psa                = (Get-PhText $runIn @('psa', 'PSA'))
            checked_at         = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
    })
