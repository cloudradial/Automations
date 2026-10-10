# Step 1: Check the VIP list.
# Reads the ServiceAI Action body (or a flat or CloudRadial webhook body), checks the company and contact
# against the VIP list, and, for a VIP ticket, reads the ticket to make sure no alert was sent for it before.
# Not VIP, or already alerted: the later steps do nothing and the run ends with status success.
$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
$stopState = @{ done = $false }
# Adds the shared PSA library's warnings (for example a ConnectWise note redirect) after the step's own.
function Add-CheckPsaWarnings { foreach ($w in @($PsaState.Warnings)) { if ($w -and -not $warnings.Contains([string]$w)) { $null = $warnings.Add([string]$w) } } }
function Stop-Check {
    param([string]$Status, [string]$Why, [string]$TicketId = '')
    $stopState.done = $true
    Add-CheckPsaWarnings
    Set-NodeOutput ([ordered]@{ status = $Status; message = $Why; public_note = ''; internal_note = "VIP ticket alert did not run: $Why"; ticket_id = $TicketId; actions = @($actions); warnings = @($warnings); chatReply = $Why; ctx_json = '' })
    throw $Why
}
trap { if (-not $stopState.done) { $stopState.done = $true; $m = [string]$_.Exception.Message; Add-CheckPsaWarnings; Set-NodeOutput ([ordered]@{ status = 'error'; message = $m; public_note = ''; internal_note = "VIP ticket alert failed: $m"; ticket_id = ''; actions = @($actions); warnings = @($warnings); chatReply = 'The VIP ticket alert failed. See the run for details.'; ctx_json = '' }) }; break }

$in = Get-NodeInput
$a = Read-StepTrigger $in
$ticketId = Get-StepField $a @('ticketId', 'ticket_id', 'TicketId', 'ticketNumber', 'TicketNumber')
$companyName = Get-StepField $a @('companyName', 'company_name', 'CompanyName', 'organizationName', 'organization_name')
$companyId = Get-StepField $a @('companyId', 'company_id', 'organizationId', 'organization_id', 'CompanyPsaId')
$contact = Get-StepField $a @('contactEmail', 'contact_email', 'requesterEmail', 'requester_email', 'UserEmail')
$summary = Get-StepField $a @('summary', 'subject', 'title', 'TicketSubject')
$priority = Get-StepField $a @('priority', 'Priority')
$source = Get-StepField $a @('triggerSource', 'trigger_source')
$preview = Test-StepTrue (Get-StepField $a @('preview', 'dryRun', 'dry_run'))

if (-not $ticketId) { Stop-Check 'incomplete' 'The request has no ticket number, so no alert was sent.' }
if ($ticketId -notmatch '^[A-Za-z0-9-]{1,40}$') { Stop-Check 'rejected' "Ticket number '$ticketId' isn't valid, so no alert was sent." }
if (-not $companyName -and -not $companyId -and -not $contact) { Stop-Check 'incomplete' "Ticket $ticketId has no company name, so it can't be checked against the VIP list." $ticketId }

# ---- the VIP list: the vip_list input, else the VIP-Companies secret ----
# Entries are separated by commas, semicolons or new lines. Each one is a company name, a PSA company id,
# a contact email or an @domain, optionally followed by =recipient|recipient to alert someone specific.
$listRaw = Get-StepField $a @('vip_list', 'vipList', 'vip_companies')
$listFrom = 'the vip_list input'
if (-not $listRaw) { $listRaw = [string](Get-PsaSecret 'VIP-Companies'); $listFrom = 'the VIP-Companies secret' }
$entries = @(Get-StepList $listRaw)
if (-not $entries.Count) { Stop-Check 'incomplete' 'The VIP list is empty. Add the VIP-Companies secret (a comma-separated list of company names) or send vip_list.' $ticketId }

$norm = { param([string]$s) return (($s -replace '\s+', ' ').Trim().ToLowerInvariant()) }
$cn = & $norm $companyName
$ce = ([string]$contact).ToLowerInvariant()
$cd = if ($ce -match '@(.+)$') { '@' + $Matches[1] } else { '' }
$match = $null
foreach ($e in $entries) {
    $key = $e; $rcp = @()
    if ($e -match '^(.*?)\s*=\s*(.+)$') { $key = $Matches[1]; $rcp = @($Matches[2] -split '[|\s]+' | Where-Object { $_ }) }
    $k = & $norm $key
    if (-not $k) { continue }
    $hit = $false; $kind = ''
    if ($k.StartsWith('@')) { $hit = ($cd -and $k -eq $cd); $kind = 'contact domain' }
    elseif ($k.Contains('@')) { $hit = ($ce -and $k -eq $ce); $kind = 'contact' }
    elseif ($k -match '^\d+$') { $hit = ($companyId -and $k -eq $companyId); $kind = 'company id' }
    else { $hit = ($cn -and $k -eq $cn); $kind = 'company' }
    if ($hit) { $match = @{ entry = $key.Trim(); kind = $kind; recipients = $rcp }; break }
}
$who = if ($companyName) { $companyName } elseif ($companyId) { "company $companyId" } else { $contact }
if ($null -eq $match) {
    $why = "$who isn't on the VIP list, so no alert was needed for ticket $ticketId."
    $ctx = @{ skip = $true; ticket_id = $ticketId; result = [ordered]@{ status = 'success'; message = $why; public_note = ''; internal_note = ''; ticket_id = $ticketId; vip = $false; alerted = $false; recipients = @(); actions = @(); warnings = @(); chatReply = $why } }
    Set-NodeOutput ([ordered]@{ status = 'success'; message = $why; vip = $false; ticket_id = $ticketId; ctx_json = (ConvertTo-Json -InputObject $ctx -Depth 8 -Compress) })
    return
}

# ---- who gets the alert ----
$recipients = @($match.recipients)
$rcpFrom = "the VIP list entry for $($match.entry)"
if (-not $recipients.Count) { $recipients = @(Get-StepList (Get-StepField $a @('alert_to', 'alertTo'))); $rcpFrom = 'the alert_to input' }
if (-not $recipients.Count) { $recipients = @(Get-StepList ([string](Get-PsaSecret 'VIP-AlertTo'))); $rcpFrom = 'the VIP-AlertTo secret' }
$bad = @($recipients | Where-Object { -not (Test-StepEmail $_) })
foreach ($b in $bad) { $null = $warnings.Add("'$b' isn't an email address, so it was skipped.") }
$recipients = @($recipients | Where-Object { Test-StepEmail $_ })
if (-not $recipients.Count) { $null = $warnings.Add('No account manager address is set (VIP list entry, alert_to input or VIP-AlertTo secret), so the alert goes in an internal note only.') }

# ---- read the ticket: it must exist, and must not have been alerted already ----
$psaIn = Get-StepField $a @('psa')
$conn = Connect-Psa (Get-PsaType $psaIn)
$t = Get-PsaTicket $ticketId
if (-not $summary) { $summary = [string]$t.summary }
if (-not $companyId) { $companyId = [string]$t.companyId }
$null = $actions.Add("Read ticket $ticketId from $(Get-PsaName).")
# The send step writes its internal note with the [vip-ticket-alert] marker; a public note with the marker doesn't count.
$notes = @(Get-PsaTicketNotes -Id $ticketId -Newest -TextOnly)
$prior = Test-PsaNoteMarker -Id $ticketId -Marker 'vip-ticket-alert' -Notes @($notes | Where-Object { $_.internal })
if ($prior) {
    $why = "A VIP alert for ticket $ticketId was already sent, so it wasn't sent again."
    Add-CheckPsaWarnings
    $ctx = @{ skip = $true; ticket_id = $ticketId; result = [ordered]@{ status = 'success'; message = $why; public_note = ''; internal_note = ''; ticket_id = $ticketId; vip = $true; alerted = $false; recipients = @(); actions = @($actions); warnings = @($warnings); chatReply = $why } }
    Set-NodeOutput ([ordered]@{ status = 'success'; message = $why; vip = $true; ticket_id = $ticketId; ctx_json = (ConvertTo-Json -InputObject $ctx -Depth 8 -Compress) })
    return
}
# Get-PsaTicketUrl falls back to the PSA-TicketUrlTemplate secret, then the PSA's usual link.
$tplUrl = Get-StepField $a @('ticket_url_template', 'ticketUrlTemplate')
$url = Get-StepField $a @('ticketUrl', 'ticket_url')
if (-not $url) { $url = Get-PsaTicketUrl $ticketId $tplUrl }
if (-not $url) { $null = $warnings.Add("A link to the ticket can't be built for $(Get-PsaName). Set the PSA-TicketUrlTemplate secret, for example https://psa.example.com/tickets/{id}.") }

Add-CheckPsaWarnings
$ctx = @{
    skip = $false; ticket_id = $ticketId; psa = $conn.Psa; psa_name = (Get-PsaName); company = $who; company_id = $companyId; contact = $contact
    summary = $summary; priority = $priority; source = $source; match = $match; list_from = $listFrom; recipients = $recipients; recipients_from = $rcpFrom
    ticket_url = $url; preview = $preview; actions = @($actions); warnings = @($warnings)
}
Set-NodeOutput ([ordered]@{ status = 'success'; message = "$who is on the VIP list (matched $($match.kind) '$($match.entry)')."; vip = $true; ticket_id = $ticketId; ctx_json = (ConvertTo-Json -InputObject $ctx -Depth 8 -Compress) })
