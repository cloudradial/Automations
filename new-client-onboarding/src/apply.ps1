# === NODE: Create the company and open the ticket ===
# Without confirm: works out every change and returns the preview. Nothing is written anywhere.
# With confirm: makes the changes in order and stops at the first failure:
#   1. create the CloudRadial company with its PSA link (or link an existing company that has no PSA link)
#   2. add primary_domain to the company
#   3. add the company to company_group
#   4. open one onboarding checklist ticket in the PSA (skipped when ticket_id was given)
# Then it writes the Microsoft 365 baseline report into the company's "Onboarding" report archive
# (Compliance > Reports, admins only) and adds an internal note to the ticket. Neither of those can undo
# the changes above, so a failure there becomes a warning and the report stays in the run output.
# Retry-safe: an open onboarding ticket found by the check step is reused instead of opening another, and
# the internal note goes through Add-PsaNote -Marker "new-client-onboarding: <ticket id> <note hash>" (the
# first 8 hex characters of the note text's SHA-256), so a rerun with the same outcome adds nothing, while a
# rerun that finished more work adds its new note. The marker holds no name or domain.
$ErrorActionPreference = 'Stop'
function Get-NcoProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Read-NcoState {
    param([string[]]$Need)
    $raw = Get-NodeInput
    if ($null -ne $raw -and $null -eq (Get-NcoProp $raw 'inputs') -and $null -ne (Get-NcoProp $raw 'output')) { $raw = Get-NcoProp $raw 'output' }
    $st = [ordered]@{}
    if ($raw -is [System.Collections.IDictionary]) { foreach ($k in $raw.Keys) { $st[[string]$k] = $raw[$k] } }
    elseif ($null -ne $raw) { foreach ($p in $raw.PSObject.Properties) { $st[$p.Name] = $p.Value } }
    foreach ($k in @('status', 'message', 'public_note', 'internal_note', 'ticket_id')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = '' } }
    foreach ($k in @('actions', 'warnings')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = @() } else { $st[$k] = @($st[$k]) } }
    foreach ($k in $Need) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { throw 'This step expects the output of the step before it. Run the workflow from the start.' } }
    return $st
}
# The step's own warnings first, then the ones _shared/psa.ps1 recorded in $PsaState.Warnings (a priority it
# couldn't set, a write answered with a redirect), each once and in its own words.
function Get-NcoWarnings {
    param($Own)
    $all = New-Object System.Collections.ArrayList
    foreach ($w in @(@($Own) + @($PsaState.Warnings))) { $t = [string]$w; if ($t -and -not $all.Contains($t)) { $null = $all.Add($t) } }
    return @($all)
}
function ConvertTo-NcoHtml { param($v) return [System.Net.WebUtility]::HtmlEncode([string]$v) }

$nco = Read-NcoState @('inputs', 'cloudradial', 'psa', 'm365')
$opt = $nco['inputs']
$ncoCr = $nco['cloudradial']
$ncoPsa = $nco['psa']
$m365 = $nco['m365']
$confirm = [bool](Get-NcoProp $opt 'confirm')
$name = [string](Get-NcoProp $opt 'company_name')
$domain = [string](Get-NcoProp $opt 'primary_domain')
$existing = [bool](Get-NcoProp $ncoCr 'existing')
$psaName = [string](Get-NcoProp $ncoPsa 'name')
$psaCompanyId = [string](Get-NcoProp $ncoPsa 'company_id')
$psaIdentifier = [string](Get-NcoProp $ncoPsa 'identifier')
$groupId = [int](Get-NcoProp $ncoCr 'group_id')
$groupName = [string](Get-NcoProp $ncoCr 'group_name')
$checklist = @(Get-NcoProp $opt 'checklist' | ForEach-Object { [string]$_ })
$warnings = @($nco['warnings'])
$actions = @($nco['actions'])
$m365Read = [string](Get-NcoProp $m365 'status') -eq 'read'

# Values the changes fill in as they run (a hashtable, changed in place).
$run = @{ company_id = [int](Get-NcoProp $ncoCr 'company_id'); ticket_id = [string](Get-NcoProp $opt 'ticket_id'); company_created = $false; ticket_opened = $false }
$openTicket = [string](Get-NcoProp $ncoPsa 'open_ticket')
if (-not $run.ticket_id -and $openTicket) { $run.ticket_id = $openTicket }

$null = Connect-Cr
$null = Connect-Psa -Psa ([string](Get-NcoProp $ncoPsa 'type'))

# ---- The ticket text ----
$summary = "New client onboarding: $name"
$descLines = @("Onboarding checklist for $name ($domain).", '')
for ($i = 0; $i -lt $checklist.Count; $i++) { $descLines += "[ ] $($i + 1). $($checklist[$i])" }
$description = $descLines -join "`n"

# ---- The plan ----
$plan = New-ChangePlan "New client onboarding: $name"
if (-not $existing) {
    $body = [ordered]@{ name = $name; psaIdentifier = $psaIdentifier }
    if ($psaCompanyId -match '^\d+$') { $body['psaKey'] = [long]$psaCompanyId }
    $am = [string](Get-NcoProp $opt 'account_manager'); if ($am) { $body['accountManager'] = $am }
    $te = [string](Get-NcoProp $opt 'territory'); if ($te) { $body['territory'] = $te }
    Add-PlannedChange $plan "Create the CloudRadial company $name, linked to $psaName company $psaCompanyId" {
        param($State, $Body, $Name)
        $r = Invoke-CrApi -Path '/v2/company' -Method POST -Body $Body
        $id = Get-CrId $r @('companyId', 'data.companyId', 'id', 'data.id', 'value.companyId')
        if (-not $id) {
            # The create reply isn't documented, so look the new company up by name.
            $esc = $Name.Replace("'", "''")
            $hit = @(Get-CrAll "/v2/odata/company?`$filter=$([uri]::EscapeDataString("name eq '$esc'"))&`$select=companyId,name") | Select-Object -First 1
            $id = Get-CrId $hit @('companyId')
        }
        if (-not $id) { throw 'CloudRadial accepted the new company but did not return its id, and it could not be found by name.' }
        $State.company_id = [int]$id; $State.company_created = $true
        return $id
    } -Arguments @($run, $body, $name)
}
elseif (-not [string](Get-NcoProp $ncoCr 'psa_key') -and -not [string](Get-NcoProp $ncoCr 'psa_identifier')) {
    $ops = @(@{ op = 'replace'; path = '/psaIdentifier'; value = $psaIdentifier })
    if ($psaCompanyId -match '^\d+$') { $ops += @{ op = 'replace'; path = '/psaKey'; value = [long]$psaCompanyId } }
    Add-PlannedChange $plan "Link CloudRadial company $($run.company_id) to $psaName company $psaCompanyId" {
        param($State, $Ops) $null = Invoke-CrApi -Path "/v2/company/$($State.company_id)" -Method PATCH -Body $Ops -ContentType 'application/json-patch+json'
    } -Arguments @($run, $ops)
}
if (-not [bool](Get-NcoProp $ncoCr 'has_domain')) {
    Add-PlannedChange $plan "Add the domain $domain to the company" {
        param($State, $Domain) $null = Invoke-CrApi -Path '/v2/domain' -Method POST -Body ([ordered]@{ companyId = $State.company_id; name = $Domain; isDefault = $true })
    } -Arguments @($run, $domain)
}
if ($groupId -gt 0 -and -not [bool](Get-NcoProp $ncoCr 'in_group')) {
    Add-PlannedChange $plan "Add the company to the company group $groupName" {
        param($State, $GroupId) $null = Invoke-CrApi -Path '/v2/companygroupcompany' -Method POST -Body ([ordered]@{ companyGroupId = $GroupId; companyId = $State.company_id })
    } -Arguments @($run, $groupId)
}
if (-not $run.ticket_id) {
    Add-PlannedChange $plan "Open the onboarding checklist ticket in $psaName ($($checklist.Count) items)" {
        param($State, $CompanyId, $Summary, $Description, $Queue)
        $t = New-PsaTicket -CompanyId $CompanyId -Summary $Summary -Description $Description -Priority 'medium' -Queue $Queue
        $State.ticket_id = [string]$t.id; $State.ticket_opened = $true
        return $t.id
    } -Arguments @($run, $psaCompanyId, $summary, $description, ([string](Get-NcoProp $opt 'ticket_queue')))
}
$result = Invoke-ChangePlan $plan -Confirm:$confirm
foreach ($r in @($result.ran)) { $actions += "$($r.description)." }
$failed = $result.failed

# ---- Integrations (what this workflow can and can't do about users and endpoints) ----
$users = [int](Get-NcoProp $ncoCr 'users'); $endpoints = [int](Get-NcoProp $ncoCr 'endpoints')
$syncText = 'CloudRadial fills in users (from Microsoft 365 or the PSA) and endpoints (from the RMM or data agent) once those integrations are linked to this company in the portal. The CloudRadial API has no sync call, so this workflow cannot start a sync.'
if ($existing -and $users -ge 0) { $syncText += " Right now the company has $users users and $endpoints endpoints$(if ($users -eq 0 -and $endpoints -eq 0) { ', so its integrations have probably not run yet' })." }
else { $syncText += ' A new company starts with no users or endpoints.' }

# ---- Microsoft 365 baseline text ----
$m365Lines = @()
if ($m365Read) {
    $m365Lines += @(Get-NcoProp $m365 'summary' | ForEach-Object { [string]$_ })
    foreach ($g in @(Get-NcoProp $m365 'groups')) { $m365Lines += "Group $(Get-NcoProp $g 'name'): $(Get-NcoProp $g 'action')" }
    foreach ($p in @(Get-NcoProp $m365 'policies')) { $m365Lines += "Policy $(Get-NcoProp $p 'name'): $(Get-NcoProp $p 'action')" }
    $m365Lines += @(Get-NcoProp $m365 'next_steps' | ForEach-Object { "Next: $_" })
}
else { $m365Lines += "Microsoft 365 baseline was skipped: $(Get-NcoProp $m365 'reason')" }

# ---- Report (confirm runs only, Microsoft 365 read, company known) ----
$h = New-Object System.Text.StringBuilder
function Add-NcoHtml { param([string]$s) $null = $h.Append($s) }
Add-NcoHtml "<h2>Microsoft 365 security baseline for $(ConvertTo-NcoHtml $name)</h2>"
Add-NcoHtml "<p>Prepared $(ConvertTo-NcoHtml ((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm'))) UTC during new client onboarding. <strong>Nothing in this report has been applied.</strong> It shows what we would set up in the client's Microsoft 365 tenant.</p>"
if ($m365Read) {
    Add-NcoHtml '<ul>'; foreach ($l in @(Get-NcoProp $m365 'summary')) { Add-NcoHtml "<li>$(ConvertTo-NcoHtml $l)</li>" }; Add-NcoHtml '</ul>'
    Add-NcoHtml '<h3>Security groups</h3><table border="1" cellpadding="4" cellspacing="0" style="border-collapse:collapse"><tr><th>Group</th><th>What it is for</th><th>What would happen</th></tr>'
    foreach ($g in @(Get-NcoProp $m365 'groups')) { Add-NcoHtml "<tr><td>$(ConvertTo-NcoHtml (Get-NcoProp $g 'name'))</td><td>$(ConvertTo-NcoHtml (Get-NcoProp $g 'purpose'))</td><td>$(ConvertTo-NcoHtml (Get-NcoProp $g 'action'))</td></tr>" }
    Add-NcoHtml '</table><h3>Conditional Access policies (report-only first)</h3><table border="1" cellpadding="4" cellspacing="0" style="border-collapse:collapse"><tr><th>Policy</th><th>What it does</th><th>What would happen</th></tr>'
    foreach ($p in @(Get-NcoProp $m365 'policies')) { Add-NcoHtml "<tr><td>$(ConvertTo-NcoHtml (Get-NcoProp $p 'name'))</td><td>$(ConvertTo-NcoHtml (Get-NcoProp $p 'plain'))</td><td>$(ConvertTo-NcoHtml (Get-NcoProp $p 'action'))</td></tr>" }
    Add-NcoHtml '</table><h3>Before anything is applied</h3><ol>'
    foreach ($l in @(Get-NcoProp $m365 'next_steps')) { Add-NcoHtml "<li>$(ConvertTo-NcoHtml $l)</li>" }
    Add-NcoHtml '</ol>'
}
$html = $h.ToString()
$report = [ordered]@{ action = 'not-written'; location = '' }
$reportOk = $false
if ($confirm -and $m365Read -and $run.company_id -gt 0) {
    try {
        $w = Add-CrArchiveReport -CompanyId $run.company_id -ArchiveName 'Onboarding' -Subject 'Microsoft 365 security baseline (preview)' -Html $html -Category 'Onboarding'
        $report = [ordered]@{ action = [string]$w.action; location = [string]$w.location }
        $reportOk = $true
        $actions += 'Wrote the Microsoft 365 baseline report to the Onboarding report archive.'
    }
    catch { $warnings += "Couldn't write the Microsoft 365 baseline report to Report Archives: $($_.Exception.Message) The report is in report_html." }
}

# ---- Status and message ----
$status = ''; $message = ''
$planned = @($result.planned)
if (-not $confirm) {
    $status = $(if ($planned.Count) { 'pending_confirmation' } else { 'success' })
    $message = $(if ($planned.Count) { "Nothing was changed. With confirm set to true, this run would: $($planned -join '; ')." } else { 'CloudRadial is already set up for this client and the ticket already exists, so there is nothing to change.' })
    if ($m365Read) { $message += ' The Microsoft 365 baseline is in the m365 output and would be written to the Onboarding report archive and the ticket.' }
}
elseif ($null -ne $failed) {
    $status = 'error'
    $message = $result.message
    if ($run.company_created) { $message += " The company was created as CloudRadial company $($run.company_id). To finish, run again with company_id set to $($run.company_id)$(if ($run.ticket_id) { " and ticket_id set to $($run.ticket_id)" })." }
}
else {
    $status = 'success'
    $bits = @()
    if ($run.company_created) { $bits += "Created CloudRadial company $($run.company_id) for $name, linked to $psaName company $psaCompanyId" } else { $bits += "Used CloudRadial company $($run.company_id)" }
    if ($run.ticket_opened) { $bits += "opened onboarding ticket $($run.ticket_id) with a $($checklist.Count)-item checklist" } elseif ($run.ticket_id) { $bits += "used ticket $($run.ticket_id)" }
    $message = ($bits -join ' and ') + '.'
    if ($m365Read) { $message += ' The Microsoft 365 baseline was prepared but not applied.' }
}

# ---- Internal note ----
$noteLines = @("New client onboarding for $name ($domain).", $message, $syncText) + $m365Lines
if ($reportOk) { $noteLines += "Full baseline report: $($report.location)." }
$internal = $noteLines -join "`n"
if ($confirm -and $run.ticket_id) {
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hash = (-join @($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($internal)) | Select-Object -First 4 | ForEach-Object { $_.ToString('x2') }))
        $w = Add-PsaNote -Id $run.ticket_id -Text $internal -Title 'Onboarding: CloudRadial and Microsoft 365 baseline' -Marker "new-client-onboarding: $($run.ticket_id) $hash"
        $actions += $(if ($w -eq 'already-present') { "The same internal note was already on ticket $($run.ticket_id), so it was not added again." } else { "Added an internal note to ticket $($run.ticket_id)." })
    }
    catch { $warnings += "Couldn't add the internal note to ticket $($run.ticket_id): $($_.Exception.Message)" }
}

$public = ''
if ($confirm -and $status -eq 'success') { $public = 'We have set up your client portal and started your onboarding checklist. We will be in touch about each step.' }

$out = [ordered]@{
    status        = $status
    message       = $message
    public_note   = $public
    internal_note = $internal
    ticket_id     = $run.ticket_id
    actions       = @($actions)
    warnings      = @(Get-NcoWarnings $warnings)
    confirm       = $confirm
    company_id    = $run.company_id
    planned       = $planned
    cloudradial   = [ordered]@{ company_id = $run.company_id; company_name = $name; created = $run.company_created; existing = $existing; psa_link = "$psaName company $psaCompanyId"; domain = $domain; group = $groupName; integrations = $syncText }
    psa           = [ordered]@{ type = [string](Get-NcoProp $ncoPsa 'type'); company_id = $psaCompanyId; ticket_id = $run.ticket_id; ticket_opened = $run.ticket_opened; checklist = @($checklist) }
    m365          = $m365
    report        = $report
}
if ($m365Read -and -not $reportOk) { $out['report_html'] = $html }
Set-NodeOutput $out
