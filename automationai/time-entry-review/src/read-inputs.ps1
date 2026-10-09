# === NODE: Read inputs ===
# Reads the run input and fills in defaults. A daily Routine sends no input, so every field is optional:
#   date                   the day to review, yyyy-MM-dd (default: yesterday in `timezone`, or in UTC)
#   timezone               optional time zone for that day, for example "Eastern Standard Time" or "America/New_York"
#   min_note_chars         a time entry note shorter than this is flagged (default 20, 0 turns the check off)
#   check_billable         flag time entries with no billable setting, where the PSA has one (default true)
#   to                     comma-separated email addresses for the report (default: the ServiceManager-Email secret)
#   company_id             optional PSA company id: review only that company's tickets
#   zendesk_time_field_id  Zendesk only: the Time Tracking app's "Total time spent (sec)" ticket field id
#   max_tickets            stop after this many closed tickets (default 500)
#   psa                    optional PSA override (default: the PSA-Type secret)
# This workflow only reads the PSA. It never changes a ticket.
# A value CloudRadial left as a literal @token (for example "@date") counts as not given.
$ErrorActionPreference = 'Stop'
function Get-TeProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-TeText {
    param($o, [string[]]$Names)
    foreach ($n in $Names) {
        $v = Get-TeProp $o $n
        if ($null -eq $v) { continue }
        if ($v -is [array]) { $v = (@($v | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ }) -join ',') }
        if ($v -is [datetime]) { $v = $v.ToString('yyyy-MM-dd') }
        $t = ([string]$v).Trim()
        if ($t -ne '' -and -not $t.StartsWith('@')) { return $t }
    }
    return ''
}
function Test-TeYes { param([string]$v, [bool]$Default) if ([string]::IsNullOrWhiteSpace($v)) { return $Default }; return (@('true', 'yes', 'y', '1') -contains $v.Trim().ToLowerInvariant()) }
function Get-TeSecret { param([string]$Name) $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue } catch { }; return $v }
function Stop-TeInput {
    param([string]$Msg)
    Set-NodeOutput ([ordered]@{ status = 'incomplete'; message = $Msg; public_note = ''; internal_note = "Time entry review did not run: $Msg"; ticket_id = ''; actions = @(); warnings = @() })
    throw $Msg
}
function Get-TeWhole {
    param([string]$Text, [string]$Name, [int]$Default, [int]$Min, [int]$Maxv)
    if ($Text -eq '') { return $Default }
    if ($Text -notmatch '^\d+$' -or [int64]$Text -lt $Min -or [int64]$Text -gt $Maxv) { Stop-TeInput "$Name must be a whole number from $Min to $Maxv (it was '$Text'). Nothing was read." }
    return [int]$Text
}

$runIn = Get-NodeInput
foreach ($k in @('trigger', 'body', 'input')) { $w = Get-TeProp $runIn $k; if ($null -ne $w) { $runIn = $w } }
if ($runIn -is [string]) {
    if ([string]::IsNullOrWhiteSpace($runIn)) { $runIn = $null }
    else { try { $runIn = $runIn | ConvertFrom-Json } catch { Stop-TeInput 'The run input is text that is not valid JSON.' } }
}

# ---- Time zone and day ----
$tzText = Get-TeText $runIn @('timezone', 'timeZone', 'time_zone', 'tz')
$tz = [TimeZoneInfo]::Utc
if ($tzText -ne '') {
    try { $tz = [TimeZoneInfo]::FindSystemTimeZoneById($tzText) }
    catch { Stop-TeInput "timezone '$tzText' isn't a time zone this runner knows. Use a name like 'Eastern Standard Time' or 'America/New_York', or leave it empty for UTC." }
}
$dateText = Get-TeText $runIn @('date', 'day', 'review_date')
$day = [datetime]::MinValue
if ($dateText -eq '') {
    $nowLocal = [TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz)
    $day = $nowLocal.Date.AddDays(-1)
}
else {
    if (-not [datetime]::TryParseExact($dateText, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$day)) { Stop-TeInput "date must look like 2026-10-07 (it was '$dateText')." }
    $todayLocal = [TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz).Date
    if ($day -gt $todayLocal) { Stop-TeInput "date $dateText is in the future." }
    if ($day -lt $todayLocal.AddDays(-366)) { Stop-TeInput "date $dateText is more than a year ago." }
}
$startLocal = [datetime]::SpecifyKind($day, [DateTimeKind]::Unspecified)
$fromUtc = [TimeZoneInfo]::ConvertTimeToUtc($startLocal, $tz)
$toUtc = [TimeZoneInfo]::ConvertTimeToUtc($startLocal.AddDays(1), $tz)

$minNote = Get-TeWhole (Get-TeText $runIn @('min_note_chars', 'minNoteChars')) 'min_note_chars' 20 0 2000
$maxTickets = Get-TeWhole (Get-TeText $runIn @('max_tickets', 'maxTickets')) 'max_tickets' 500 1 5000
$checkBillable = Test-TeYes (Get-TeText $runIn @('check_billable', 'checkBillable')) $true

$companyId = Get-TeText $runIn @('company_id', 'companyId', 'psa_company_id')
if ($companyId -ne '' -and $companyId -notmatch '^\d+$') { Stop-TeInput "company_id must be the PSA's company number (it was '$companyId')." }
$zdField = Get-TeText $runIn @('zendesk_time_field_id', 'zendeskTimeFieldId')
if ($zdField -ne '' -and $zdField -notmatch '^\d+$') { Stop-TeInput "zendesk_time_field_id must be a number (it was '$zdField')." }

# ---- Recipients ----
$toText = Get-TeText $runIn @('to', 'email', 'recipients')
$warnings = @()
if ($toText -eq '') { $sec = Get-TeSecret 'ServiceManager-Email'; if (-not [string]::IsNullOrWhiteSpace($sec)) { $toText = $sec.Trim() } }
$to = @()
foreach ($part in ($toText -split '[,;\s]+')) {
    $t = $part.Trim().Trim('"', "'", '<', '>')
    if ($t -eq '') { continue }
    if ($t -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') { if ($to -notcontains $t.ToLowerInvariant()) { $to += $t.ToLowerInvariant() } }
    else { Stop-TeInput "'$t' in to isn't an email address." }
}
if (-not $to.Count) { $warnings += 'No recipient (the to input or the ServiceManager-Email secret), so the report is only in the run output.' }

Set-NodeOutput ([ordered]@{
        status        = 'running'
        message       = ''
        public_note   = ''
        internal_note = ''
        ticket_id     = ''
        actions       = @()
        warnings      = @($warnings)
        inputs        = [ordered]@{
            date                  = $day.ToString('yyyy-MM-dd')
            timezone              = $(if ($tzText -ne '') { $tz.Id } else { 'UTC' })
            range_from            = $fromUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
            range_to              = $toUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
            min_note_chars        = $minNote
            check_billable        = $checkBillable
            to                    = @($to)
            company_id            = $companyId
            zendesk_time_field_id = $zdField
            max_tickets           = $maxTickets
            psa                   = (Get-TeText $runIn @('psa', 'PSA'))
        }
    })
