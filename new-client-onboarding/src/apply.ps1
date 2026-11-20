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
$run = @{ company_id = [int](Get-NcoProp $ncoCr 'company_id'); ticket_id = [string](Get-NcoProp $opt 'ticket_id'); company_created = $false; ticket_opened = $false; psa_company_id = ''; psa_created = $false; psa_contact_id = ''; psa_agreement_id = '' }
$openTicket = [string](Get-NcoProp $ncoPsa 'open_ticket')
if (-not $run.ticket_id -and $openTicket) { $run.ticket_id = $openTicket }

$global:NcoCrSecretSuffix = (([string](Get-NcoProp $opt 'cloudradial_company')).Trim().ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
$null = Connect-Cr
if ([string](Get-NcoProp $ncoPsa 'type')) { $null = Connect-Psa -Psa ([string](Get-NcoProp $ncoPsa 'type')) }

# ---- The ticket text ----
$summary = "New client onboarding: $name"
$descLines = @("Onboarding checklist for $name ($domain).", '')
for ($i = 0; $i -lt $checklist.Count; $i++) { $descLines += "[ ] $($i + 1). $($checklist[$i])" }
$description = $descLines -join "`n"

# ---- The plan ----
$plan = New-ChangePlan "New client onboarding: $name"
# ---- Step filter: a run does only the parts in nco_step (default psa, portal and ticket, as before) ----
$NcoStep = [string](Get-NcoProp $opt 'nco_step')
if (-not $NcoStep) { $NcoStep = 'psa,portal,ticket,other' }
if ($NcoStep) {
    ${function:NcoAddPlannedChangeAll} = ${function:Add-PlannedChange}
    function Add-PlannedChange {
        param($Plan, [string]$Description, [scriptblock]$Action, [object[]]$Arguments = @())
        $cat = 'other'
        if ($Description -match '^Create the \S+ (company|contact|agreement) ' -and $Description -notmatch '^Create the CloudRadial') { $cat = 'psa' }
        elseif ($Description -match '^(Create the CloudRadial company|Link CloudRadial company|Add the domain|Add the company to the company group)') { $cat = 'portal' }
        elseif ($Description -match '^Add Planner cards') { $cat = 'planner' }
        elseif ($Description -match '^Add prospect Planner cards') { $cat = 'landcards' }
        elseif ($Description -match 'ticket') { $cat = 'ticket' }
        if (@($NcoStep -split '\s*,\s*') -contains $cat) { NcoAddPlannedChangeAll -Plan $Plan -Description $Description -Action $Action -Arguments $Arguments }
    }
}
# ---- ConnectWise company, contact and agreement (only when the check step found no company) ----
$psaFoundBy = [string](Get-NcoProp $ncoPsa 'found_by')
if ($psaFoundBy -eq 'create') {
    $contactName = [string](Get-NcoProp $opt 'primary_contact_name')
    $contactEmail = [string](Get-NcoProp $opt 'primary_contact_email')
    $agType = [string](Get-NcoProp $opt 'agreement_type')
    $agName = [string](Get-NcoProp $opt 'agreement_name'); if (-not $agName) { $agName = "$name Managed Services" }
    Add-PlannedChange $plan "Create the $psaName company $name (identifier $psaIdentifier)" {
        param($State, $Name, $Ident)
        $find = { param($i) @(Invoke-Psa GET "/company/companies?conditions=$(ConvertTo-PsaQuery ('identifier="' + $i + '"'))&fields=id,identifier&pageSize=1" | Where-Object { $null -ne $_ }) | Select-Object -First 1 }
        $b = [ordered]@{ identifier = $Ident; name = $Name; site = @{ name = 'Main' } }
        $id = $null
        $PsaState.LastWriteRedirect = $null
        try { $r = Invoke-Psa POST '/company/companies' $b; $id = Get-PsaProp $r 'id' }
        catch { if ($null -eq $PsaState.LastWriteRedirect) { throw }; Start-Sleep -Seconds 3 }
        if (-not $id) { $hit = & $find $Ident; if ($hit) { $id = Get-PsaProp $hit 'id' } }
        if (-not $id) { throw "ConnectWise did not return the new company's id, and no company with identifier $Ident was found." }
        $State.psa_company_id = [string]$id; $State.psa_created = $true
        return $id
    } -Arguments @($run, $name, $psaIdentifier)
    if ($contactName) {
        Add-PlannedChange $plan "Create the $psaName contact $contactName$(if ($contactEmail) { " ($contactEmail)" })" {
            param($State, $Full, $Email)
            $parts = @($Full.Trim() -split '\s+', 2)
            $b = [ordered]@{ firstName = $parts[0]; company = @{ id = [int]$State.psa_company_id } }
            if ($parts.Count -gt 1) { $b.lastName = $parts[1] }
            if ($Email) {
                $types = @(Invoke-Psa GET '/company/communicationTypes?pageSize=100' | Where-Object { $null -ne $_ })
                $et = @($types | Where-Object { [string](Get-PsaProp $_ 'description') -match '(?i)^e-?mail$' -or [bool](Get-PsaProp $_ 'emailFlag') }) | Select-Object -First 1
                if ($et) { $b.communicationItems = @(@{ type = @{ id = [int](Get-PsaProp $et 'id') }; value = $Email; defaultFlag = $true; communicationType = 'Email' }) }
            }
            $PsaState.LastWriteRedirect = $null
            $id = $null
            try { $r = Invoke-Psa POST '/company/contacts' $b; $id = Get-PsaProp $r 'id' }
            catch { if ($null -eq $PsaState.LastWriteRedirect) { throw }; Start-Sleep -Seconds 3 }
            if (-not $id) { $hit = @(Invoke-Psa GET "/company/contacts?conditions=$(ConvertTo-PsaQuery ('company/id=' + [int]$State.psa_company_id))&fields=id&orderBy=$(ConvertTo-PsaQuery 'id desc')&pageSize=1" | Where-Object { $null -ne $_ }) | Select-Object -First 1; if ($hit) { $id = Get-PsaProp $hit 'id' } }
            if (-not $id) { throw 'ConnectWise did not return the new contact id.' }
            $State.psa_contact_id = [string]$id
            try { $null = Invoke-Psa PATCH "/company/companies/$($State.psa_company_id)" @(@{ op = 'replace'; path = 'defaultContact'; value = @{ id = [int]$id } }) } catch { }
            return $id
        } -Arguments @($run, $contactName, $contactEmail)
        Add-PlannedChange $plan "Create the $psaName agreement $agName" {
            param($State, $AgName, $AgType)
            $types = @(Invoke-Psa GET '/finance/agreements/types?pageSize=100' | Where-Object { $null -ne $_ -and -not [bool](Get-PsaProp $_ 'inactiveFlag') })
            if (-not $types.Count) { throw 'ConnectWise has no active agreement types.' }
            $t = $null
            if ($AgType) { $t = @($types | Where-Object { ([string](Get-PsaProp $_ 'name')).Trim() -ieq $AgType.Trim() }) | Select-Object -First 1; if (-not $t) { throw "ConnectWise has no agreement type named '$AgType'." } }
            if (-not $t) { $t = @($types | Where-Object { [string](Get-PsaProp $_ 'name') -match '(?i)managed' }) | Select-Object -First 1 }
            if (-not $t) { $t = $types[0] }
            $b = [ordered]@{ name = $AgName; type = @{ id = [int](Get-PsaProp $t 'id') }; company = @{ id = [int]$State.psa_company_id }; contact = @{ id = [int]$State.psa_contact_id }; startDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddT00:00:00Z'); noEndingDateFlag = $true; employeeCompNotExceed = 'Billing' }
            $PsaState.LastWriteRedirect = $null
            $id = $null
            try { $r = Invoke-Psa POST '/finance/agreements' $b; $id = Get-PsaProp $r 'id' }
            catch { if ($null -eq $PsaState.LastWriteRedirect) { throw }; Start-Sleep -Seconds 3 }
            if (-not $id) { $hit = @(Invoke-Psa GET "/finance/agreements?conditions=$(ConvertTo-PsaQuery ('company/id=' + [int]$State.psa_company_id))&fields=id&orderBy=$(ConvertTo-PsaQuery 'id desc')&pageSize=1" | Where-Object { $null -ne $_ }) | Select-Object -First 1; if ($hit) { $id = Get-PsaProp $hit 'id' } }
            if (-not $id) { throw 'ConnectWise did not return the new agreement id.' }
            $State.psa_agreement_id = [string]$id
            return $id
        } -Arguments @($run, $agName, $agType)
    }
    else { $warnings += "No primary_contact_name was given, so no $psaName contact or agreement is created. ConnectWise needs a contact on every agreement." }
}
if (-not $existing) {
    $body = [ordered]@{ name = $name }
    if ($psaIdentifier) { $body['psaIdentifier'] = $psaIdentifier }
    if ($psaCompanyId -match '^\d+$') { $body['psaKey'] = [long]$psaCompanyId }
    $am = [string](Get-NcoProp $opt 'account_manager'); if ($am) { $body['accountManager'] = $am }
    $te = [string](Get-NcoProp $opt 'territory'); if ($te) { $body['territory'] = $te }
    Add-PlannedChange $plan "Create the CloudRadial company $name$(if ($psaCompanyId -or $psaIdentifier) { ", linked to $psaName company $(if ($psaCompanyId) { $psaCompanyId } else { $psaIdentifier })" })" {
        param($State, $Body, $Name)
    if ([string]$State.psa_company_id -match '^\d+$') { $Body['psaKey'] = [long]$State.psa_company_id }
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
elseif (($psaCompanyId -or $psaIdentifier) -and ([string](Get-NcoProp $ncoCr 'psa_key')) -notmatch '^[1-9]\d*$' -and ($psaCompanyId -match '^[1-9]\d*$' -or -not [string](Get-NcoProp $ncoCr 'psa_identifier'))) {
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
    if ([string]$State.psa_company_id) { $CompanyId = [string]$State.psa_company_id }
        $t = New-PsaTicket -CompanyId $CompanyId -Summary $Summary -Description $Description -Priority 'medium' -Queue $Queue
        $State.ticket_id = [string]$t.id; $State.ticket_opened = $true
        return $t.id
    } -Arguments @($run, $psaCompanyId, $summary, $description, ([string](Get-NcoProp $opt 'ticket_queue')))
}
# ---- Land: recommended Planner cards for a prospect (no PSA, no Microsoft 365 access needed) ----
Add-PlannedChange $plan "Add prospect Planner cards: Managed Services proposal, Email security review, Microsoft 365 security baseline, Portal access" {
    param($State, $Domain)
    $cid = [int]$State.company_id
    if ($cid -le 0) { throw 'No CloudRadial company id for the prospect Planner cards.' }
    $existing = @(Get-CrAll "/v2/odata/product?`$filter=companyId eq $cid")
    $made = @()
    $made += Set-CrPlannerCard -CompanyId $cid -Subject 'Managed Services proposal' -Fields @{ isClientVisible = $true; category = 'Efficiency'; productCategoryId = 7; summary = 'Recommended: our managed services plan for your team.'; body = '<p>Recommended: day-to-day support, monitoring and patching for every user and device, with tickets, training and reports in this portal.</p>' } -Key 'nco:land:proposal' -Existing $existing
    $made += Set-CrPlannerCard -CompanyId $cid -Subject 'Email security review' -Fields @{ isClientVisible = $true; category = 'Efficiency'; productCategoryId = 7; summary = "Recommended: check SPF, DKIM and DMARC for $Domain."; body = "<p>Recommended: review how $Domain protects against spoofed email (SPF, DKIM, DMARC) and fix any gaps. We can check this from the outside before you sign.</p>" } -Key 'nco:land:email' -Existing $existing
    $made += Set-CrPlannerCard -CompanyId $cid -Subject 'Microsoft 365 security baseline' -Fields @{ isClientVisible = $true; category = 'Efficiency'; productCategoryId = 7; summary = 'Recommended: Secure Score assessment once Microsoft 365 is connected.'; body = '<p>Recommended: once you connect Microsoft 365, we run a Secure Score assessment and turn every gap into a plan in this Planner.</p>' } -Key 'nco:land:m365' -Existing $existing
    $made += Set-CrPlannerCard -CompanyId $cid -Subject 'Portal access for your team' -Fields @{ isClientVisible = $true; category = 'Efficiency'; productCategoryId = 7; summary = 'Recommended: give your team one place for tickets, training and reports.'; body = '<p>Recommended: every user gets this portal for tickets, requests, training and reports from day one.</p>' } -Key 'nco:land:portal' -Existing $existing
    $State.planner_cards = @($made | ForEach-Object { [string]$_.productId })
    return @($made).Count
} -Arguments @($run, $domain)
# ---- Planner cards: what the client already agreed to, what is in progress, and the next recommendation ----
$plannerProducts = @(([string](Get-NcoProp $opt 'products')) -split '[,\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$plannerAg = [string](Get-NcoProp $opt 'agreement_name'); if (-not $plannerAg) { $plannerAg = "$name Managed Services" }
Add-PlannedChange $plan "Add Planner cards: $plannerAg$(if ($plannerProducts.Count) { ', ' + ($plannerProducts -join ', ') }), Onboarding project, Connect Microsoft 365" {
    param($State, $Ag, $Products)
    $cid = [int]$State.company_id
    if ($cid -le 0) { throw 'No CloudRadial company id for the Planner cards.' }
    $existing = @(Get-CrAll "/v2/odata/product?`$filter=companyId eq $cid")
    $made = @()
    $agBody = '<p>Done: signed and active.</p>' + $(if ($State.psa_agreement_id) { "<p>ConnectWise agreement #$($State.psa_agreement_id).</p>" } else { '' })
    $made += Set-CrPlannerCard -CompanyId $cid -Subject $Ag -Fields @{ isClientVisible = $true; category = 'Efficiency'; productCategoryId = 7; summary = 'Done: managed services agreement signed and active.'; body = $agBody } -Key 'nco:agreement' -Existing $existing
    foreach ($p in @($Products)) { $made += Set-CrPlannerCard -CompanyId $cid -Subject $p -Fields @{ isClientVisible = $true; category = 'Efficiency'; productCategoryId = 7; summary = "Done: included in $Ag."; body = "<p>Done: included in $Ag.</p>" } -Key ('nco:service:' + $p.ToLowerInvariant()) -Existing $existing }
    $obBody = '<p>In progress: onboarding has started.</p>' + $(if ($State.ticket_id) { "<p>Onboarding ticket #$($State.ticket_id) tracks the checklist.</p>" } else { '' })
    $made += Set-CrPlannerCard -CompanyId $cid -Subject 'Onboarding project' -Fields @{ isClientVisible = $true; category = 'Efficiency'; productCategoryId = 7; summary = 'In progress: onboarding has started.'; body = $obBody } -Key 'nco:onboarding' -Existing $existing
    $made += Set-CrPlannerCard -CompanyId $cid -Subject 'Connect Microsoft 365' -Fields @{ isClientVisible = $true; category = 'Efficiency'; productCategoryId = 7; summary = 'Recommended: connect Microsoft 365 to your portal.'; body = '<p>Recommended next step: approve the Microsoft 365 connection in your portal so licensing, security and reporting data start flowing.</p>' } -Key 'nco:m365' -Existing $existing
    $State.planner_cards = @($made | ForEach-Object { [string]$_.productId })
    return @($made).Count
} -Arguments @($run, $plannerAg, $plannerProducts)
$result = Invoke-ChangePlan $plan -Confirm:$confirm
foreach ($r in @($result.ran)) { $actions += "$($r.description)." }
$failed = $result.failed
if ($run.psa_company_id) { $psaCompanyId = [string]$run.psa_company_id }

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
    if ($run.company_created) { $bits += "Created CloudRadial company $($run.company_id) for $name$(if ($psaCompanyId) { ", linked to $psaName company $psaCompanyId" })" } else { $bits += "Used CloudRadial company $($run.company_id)" }
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
$out['inputs'] = $opt
Set-NodeOutput $out
