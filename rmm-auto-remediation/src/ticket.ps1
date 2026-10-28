# === NODE: Open PSA ticket ===
# Opens the escalation ticket the RMM agent asked for, in whichever of the six PSAs the runner uses
# (ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro or Zendesk, through _shared/psa.ps1).
# The agent never opens tickets itself: it returns escalate, ticketSummary, ticketDescription, ticketNote,
# ticketPriority, siteName, cloudradialCompanyId and dryRun, and this step reads them from the previous output.
#   - escalate false: nothing to do; the agent's result is passed on.
#   - dryRun true: preview only; says which ticket would be opened and opens nothing.
#   - otherwise: finds the PSA company (CloudRadial company name, then the Datto site name, then the
#     PSA-CompanyId secret as a catch-all), opens the ticket on the PSA-ServiceQueue queue when that secret
#     is set, and adds ticketNote as an internal note.
# A ticket that can't be opened fails the step, so the run shows the alert still needs a person.
$ErrorActionPreference = 'Stop'
function Get-RrProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
# The agent's result, unwrapped from a JSON string or an output/result/response wrapper.
function Get-RrAgentResult {
    param($v)
    for ($i = 0; $i -lt 4; $i++) {
        if ($v -is [string]) { $t = $v.Trim(); if ($t.StartsWith('{')) { try { $v = $t | ConvertFrom-Json } catch { return $null } } else { return $null } }
        if ($null -eq $v) { return $null }
        if ($null -ne (Get-RrProp $v 'escalate') -or $null -ne (Get-RrProp $v 'status')) { return $v }
        $next = $null; foreach ($k in @('output', 'result', 'response')) { $x = Get-RrProp $v $k; if ($null -ne $x) { $next = $x; break } }
        if ($null -eq $next) { return $v }
        $v = $next
    }
    return $v
}
function Get-RrText { param($o, [string]$n) $v = Get-RrProp $o $n; if ($null -eq $v) { return '' }; return ([string]$v).Trim() }
function Test-RrTrue { param($v) return ($v -eq $true -or ([string]$v).Trim().ToLowerInvariant() -in @('true', 'yes', '1')) }

$agent = Get-RrAgentResult (Get-NodeInput)
$out = [ordered]@{
    status = ''; message = ''; ticketId = ''; psa = ''; psaCompanyId = ''
    escalate = $false; dryRun = $false
    action = (Get-RrText $agent 'action'); deviceUid = (Get-RrText $agent 'deviceUid'); alertUid = (Get-RrText $agent 'alertUid')
    alertResolved = (Test-RrTrue (Get-RrProp $agent 'alertResolved')); notes = (Get-RrText $agent 'notes')
    actions = @(); warnings = @()
}
function Complete-Rr { param([string]$Status, [string]$Msg) $out.status = $Status; $out.message = $Msg; foreach ($w in @($PsaState.Warnings)) { if ($w -and $out.warnings -notcontains $w) { $out.warnings += [string]$w } }; Set-NodeOutput $out }
function Stop-Rr { param([string]$Msg) Complete-Rr 'error' $Msg; throw $Msg }

if ($null -eq $agent) { Stop-Rr "The agent step returned nothing this step can read, so no ticket was opened. Check the agent's output." }
$out.escalate = Test-RrTrue (Get-RrProp $agent 'escalate')
$out.dryRun = Test-RrTrue (Get-RrProp $agent 'dryRun')
if (-not $out.escalate) {
    $why = $out.notes; if (-not $why) { $why = $out.action }
    Complete-Rr 'success' ("No ticket needed." + $(if ($why) { " $why" }))
    return
}

$summary = Get-RrText $agent 'ticketSummary'
if (-not $summary) { $summary = 'RMM alert needs a technician' + $(if ($out.deviceUid) { " (device $($out.deviceUid))" }) }
$description = Get-RrText $agent 'ticketDescription'
if (-not $description) { $description = 'The RMM agent escalated this alert without a description. See the internal note and the AutomationAI run.' }
$note = Get-RrText $agent 'ticketNote'
$priority = Get-RrText $agent 'ticketPriority'; if ($priority -notin @('critical', 'high', 'medium', 'low')) { $priority = 'high' }
$site = Get-RrText $agent 'siteName'
$crId = Get-RrText $agent 'cloudradialCompanyId'; if ($crId -notmatch '^\d+$' -or $crId -eq '0') { $crId = '' }
$where = if ($site) { " for site $site" } else { '' }

if ($out.dryRun) {
    Complete-Rr 'preview' "Preview: would open a $priority ticket$where, '$summary'. Nothing was opened, because the agent ran as a preview."
    return
}

# ---- PSA ----
try { $conn = Connect-Psa -Psa (Get-PsaType ''); $out.psa = Get-PsaName }
catch { Stop-Rr "The alert needs a ticket ('$summary'), but the PSA isn't set up, so none was opened: $($_.Exception.Message)" }

# ---- The PSA company: CloudRadial company name, then the Datto site name, then PSA-CompanyId ----
$psaCo = ''; $tried = @()
if ($crId) {
    try {
        $null = Connect-Cr
        $co = @(Get-CrProp (Invoke-CrApi -Path "/v2/odata/company?`$filter=$([uri]::EscapeDataString("companyId eq $crId"))&`$select=companyId,name") 'value') | Select-Object -First 1
        $cname = [string](Get-CrProp $co 'name')
        if ($cname) {
            $hits = @(Find-PsaCompany -Name $cname | Where-Object { $_.exact })
            if ($hits.Count -eq 1) { $psaCo = [string]$hits[0].id; $out.actions += "Matched CloudRadial company '$cname' to $(Get-PsaName) company $psaCo by name." }
            else { $tried += "$(Get-PsaName) has $($hits.Count) companies named '$cname'" }
        }
        else { $tried += "CloudRadial company $crId wasn't found" }
    }
    catch { $tried += "couldn't look up CloudRadial company $($crId): $($_.Exception.Message)" }
}
if (-not $psaCo -and $site) {
    try {
        $hits = @(Find-PsaCompany -Name $site | Where-Object { $_.exact })
        if ($hits.Count -eq 1) { $psaCo = [string]$hits[0].id; $out.actions += "Matched Datto site '$site' to $(Get-PsaName) company $psaCo by name." }
        else { $tried += "$(Get-PsaName) has $($hits.Count) companies named '$site'" }
    }
    catch { $tried += "couldn't look up '$site' in $(Get-PsaName): $($_.Exception.Message)" }
}
if (-not $psaCo) {
    $fallback = ([string](Get-PsaSecret 'PSA-CompanyId')).Trim()
    if ($fallback) {
        $psaCo = $fallback
        $out.warnings += "Opened the ticket on the PSA-CompanyId company ($fallback), because the client's own company wasn't found ($($tried -join '; '))."
    }
    else {
        $why = if ($tried.Count) { " ($($tried -join '; '))" } else { ' (the agent matched no CloudRadial company and named no site)' }
        Stop-Rr "The alert needs a ticket ('$summary'), but its $(Get-PsaName) company couldn't be found$why. Set the PSA-CompanyId secret to a catch-all company, or map the Datto site in the agent's siteCompanyMap variable."
    }
}
$out.psaCompanyId = $psaCo

# ---- Open the ticket and add the internal note ----
$queue = ([string](Get-PsaSecret 'PSA-ServiceQueue')).Trim()
try { $t = New-PsaTicket -CompanyId $psaCo -Summary $summary -Description $description -Priority $priority -Queue $queue }
catch { Stop-Rr "Couldn't open the $(Get-PsaName) ticket '$summary': $($_.Exception.Message)" }
$out.ticketId = [string]$t.id
$out.actions += "Opened $(Get-PsaName) ticket $($t.id): $summary"
if ($note) {
    try {
        $marker = if ($out.alertUid) { "rmm-alert: $($out.alertUid)" } else { '' }
        $null = Add-PsaNote -Id $out.ticketId -Text $note -Title 'RMM detail' -Internal -Marker $marker
        $out.actions += 'Added the technical detail as an internal note.'
    }
    catch { $out.warnings += "The ticket was opened, but the internal note wasn't added: $($_.Exception.Message)" }
}
Complete-Rr 'success' "Opened $(Get-PsaName) ticket $($out.ticketId)$where`: $summary"
