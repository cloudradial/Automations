# === NODE: Read inputs ===
# Reads the run input and fills in defaults. A daily Routine sends no input, so every field is optional:
#   daysBeforeExpiry   days before expiry on which a reminder goes out (default "14,7,1"; a comma list or a JSON list, 0 to 365)
#   preview            true = list who would be emailed and send nothing (default false; dryRun and dry_run work too)
#   catchUpDays        how many days back a run looks for a reminder day it may have missed (default 1 = today only, 1 to 30)
#   resetUrl           the page the email links to (default: the PasswordExpiry-ResetUrl secret, else https://passwordreset.microsoftonline.com/)
#   timeZone           the time zone used for "today" and the expiry date in the email (default: the PasswordExpiry-TimeZone secret, else UTC)
#   onlyUsers          sign-in names, email addresses or object ids to limit the run to, for testing (default: everyone)
#   company_tenant_id  optional Microsoft 365 tenant id; when given it must be this runner's tenant (M365-TenantId)
# Bad input stops the run with a plain sentence and nothing is read or sent.
$ErrorActionPreference = 'Stop'
function Stop-PeInput {
    param([string]$Msg)
    Set-NodeOutput ([ordered]@{ status = 'incomplete'; message = $Msg; counts = (New-PeCounts); due = @(); emailed = @(); skipped = @(); actions = @(); warnings = @() })
    throw $Msg
}

$runIn = Get-NodeInput
foreach ($k in @('trigger', 'body', 'input')) { $w = Get-PeProp $runIn $k; if ($null -ne $w) { $runIn = $w } }
if ($runIn -is [string]) {
    if ([string]::IsNullOrWhiteSpace($runIn)) { $runIn = $null }
    else { try { $runIn = $runIn | ConvertFrom-Json } catch { Stop-PeInput 'The run input is text that is not valid JSON. No email was sent.' } }
}
$warnings = @()

# Reminder days, largest first.
$thrText = Get-PeText $runIn @('daysBeforeExpiry', 'days_before_expiry', 'reminderDays', 'reminder_days')
if ($thrText -eq '') { $thrText = '14,7,1' }
$thr = @()
foreach ($part in ($thrText.Trim().TrimStart('[').TrimEnd(']') -split '[,;\s]+')) {
    $t = $part.Trim().Trim('"', "'")
    if ($t -eq '') { continue }
    if ($t -notmatch '^\d+$' -or [int64]$t -gt 365) { Stop-PeInput "daysBeforeExpiry must be whole numbers from 0 to 365, for example 14,7,1 (it was '$thrText'). No email was sent." }
    if ($thr -notcontains [int]$t) { $thr += [int]$t }
}
if (-not $thr.Count) { Stop-PeInput 'daysBeforeExpiry has no days in it. Use whole numbers, for example 14,7,1. No email was sent.' }
$thr = @($thr | Sort-Object -Descending)

$prevText = Get-PeText $runIn @('preview', 'dryRun', 'dry_run')
$preview = $false
if ($prevText -ne '') {
    $pv = $prevText.ToLowerInvariant()
    if (@('true', 'yes', 'y', '1') -contains $pv) { $preview = $true }
    elseif (@('false', 'no', 'n', '0') -notcontains $pv) { Stop-PeInput "preview must be true or false (it was '$prevText'). No email was sent." }
}

$catchText = Get-PeText $runIn @('catchUpDays', 'catch_up_days')
$catchUp = 1
if ($catchText -ne '') {
    if ($catchText -notmatch '^\d+$' -or [int64]$catchText -lt 1 -or [int64]$catchText -gt 30) { Stop-PeInput "catchUpDays must be a whole number from 1 to 30 (it was '$catchText'). No email was sent." }
    $catchUp = [int]$catchText
}

$resetUrl = Get-PeText $runIn @('resetUrl', 'reset_url')
$resetFrom = 'input'
if ($resetUrl -eq '') { $resetUrl = Get-PeSecret @('PasswordExpiry-ResetUrl'); $resetFrom = 'the PasswordExpiry-ResetUrl secret' }
if ($resetUrl -eq '') { $resetUrl = 'https://passwordreset.microsoftonline.com/'; $resetFrom = 'default' }
if ($resetUrl -notmatch '^https://[^\s<>"]+$') { Stop-PeInput "resetUrl (from $resetFrom) must be a web address starting with https:// (it was '$resetUrl'). No email was sent." }

$tzText = Get-PeText $runIn @('timeZone', 'time_zone')
if ($tzText -eq '') { $tzText = Get-PeSecret @('PasswordExpiry-TimeZone') }
if ($tzText -eq '') { $tzText = 'UTC' }
try { $null = [TimeZoneInfo]::FindSystemTimeZoneById($tzText) }
catch { Stop-PeInput "timeZone '$tzText' isn't a time zone this runner knows. Use a name such as UTC, Eastern Standard Time or America/New_York. No email was sent." }

$only = @()
foreach ($part in ((Get-PeText $runIn @('onlyUsers', 'only_users')) -split '[,;\s]+')) {
    $t = $part.Trim().Trim('"', "'", '[', ']')
    if ($t -eq '') { continue }
    if ($t -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$' -or $t -match '^[^@\s]+@[^@\s]+$') { if ($only -notcontains $t.ToLowerInvariant()) { $only += $t.ToLowerInvariant() } }
    else { $warnings += "Ignored '$t' in onlyUsers: it is neither a sign-in name, an email address nor a user object id." }
}
if ((Get-PeText $runIn @('onlyUsers', 'only_users')) -ne '' -and -not $only.Count) { Stop-PeInput 'onlyUsers was given but has no valid sign-in name, email address or user object id in it, so the run stopped rather than email everyone. No email was sent.' }

$tenantIn = (Get-PeText $runIn @('company_tenant_id', 'companyTenantId', 'CompanyTenantId', 'tenant_id', 'tenantId')).ToLowerInvariant()
if ($tenantIn -ne '' -and $tenantIn -notmatch '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') { Stop-PeInput "company_tenant_id must be a Microsoft 365 tenant id (a GUID). It was '$tenantIn'. No email was sent." }

Set-NodeOutput ([ordered]@{
        status     = 'running'
        message    = ''
        preview    = $preview
        done       = $false
        tenant_id  = ''
        checked_at = ''
        sent_via   = ''
        counts     = (New-PeCounts)
        due        = @()
        emailed    = @()
        skipped    = @()
        actions    = @()
        warnings   = @($warnings)
        inputs     = [ordered]@{
            daysBeforeExpiry  = @($thr)
            preview           = $preview
            catchUpDays       = $catchUp
            resetUrl          = $resetUrl
            timeZone          = $tzText
            onlyUsers         = @($only)
            company_tenant_id = $tenantIn
        }
    })
