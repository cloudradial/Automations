# === NODE: Fix missing contacts (only on confirm) ===
# The only fix this workflow makes. It runs when `fix` names missing_contact:
#   - For each ticket found with no contact, it reads that ticket's company's active contacts.
#   - When the company has exactly one primary contact, it plans "set the contact to that person".
#   - Anything else (no primary, two or more, a PSA with no primary flag, no company) is skipped with a reason.
# Without confirm the plan is only previewed. With confirm the changes run in order through _shared/plan.ps1
# and stop at the first failure. Only tickets from this run's fresh list are touched.
$ErrorActionPreference = 'Stop'
function Get-PhProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Read-PhState {
    param([string[]]$Need)
    $raw = Get-NodeInput
    if ($null -ne $raw -and $null -eq (Get-PhProp $raw 'inputs') -and $null -ne (Get-PhProp $raw 'output')) { $raw = Get-PhProp $raw 'output' }
    $st = [ordered]@{}
    if ($raw -is [System.Collections.IDictionary]) { foreach ($k in $raw.Keys) { $st[[string]$k] = $raw[$k] } }
    elseif ($null -ne $raw) { foreach ($p in $raw.PSObject.Properties) { $st[$p.Name] = $p.Value } }
    foreach ($k in @('status', 'message', 'public_note', 'internal_note', 'ticket_id')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = '' } }
    foreach ($k in @('actions', 'warnings', 'issues')) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { $st[$k] = @() } else { $st[$k] = @($st[$k]) } }
    foreach ($k in $Need) { if (-not $st.Contains($k) -or $null -eq $st[$k]) { throw "This step expects the output of the previous step (no '$k')." } }
    return $st
}

# The step's own warnings first, then the ones _shared/psa.ps1 recorded in $PsaState.Warnings (a priority it
# couldn't set, a write answered with a redirect), each once and in its own words.
function Get-PhWarnings {
    param($Own)
    $all = New-Object System.Collections.ArrayList
    foreach ($w in @(@($Own) + @($PsaState.Warnings))) { $t = [string]$w; if ($t -and -not $all.Contains($t)) { $null = $all.Add($t) } }
    return @($all)
}

$ph = Read-PhState @('inputs', 'psa', 'counts')
$opt = $ph['inputs']
$confirm = [bool](Get-PhProp $opt 'confirm')
$wantContacts = @(Get-PhProp $opt 'fix') -contains 'missing_contact'
$warn = @($ph['warnings'])
$skipped = New-Object System.Collections.ArrayList
$fixInfo = [ordered]@{ requested = $wantContacts; confirmed = $confirm; planned = @(); skipped = @(); result = $null }
$missing = @($ph['issues'] | Where-Object { $null -ne $_ -and [string](Get-PhProp $_ 'category') -eq 'missing_contact' })

if ($wantContacts -and $missing.Count) {
    try { $null = Connect-Psa ([string]$ph['psa']) }
    catch { $ph['status'] = 'error'; $ph['message'] = "Couldn't connect to the PSA: $($_.Exception.Message) Nothing was changed."; $ph['warnings'] = @(Get-PhWarnings $warn); Set-NodeOutput $ph; throw $ph['message'] }
    $plan = New-ChangePlan 'Set missing ticket contacts'
    $cache = @{}
    foreach ($i in $missing) {
        $tid = [string](Get-PhProp $i 'ticket_id'); $num = [string](Get-PhProp $i 'number'); $coId = [string](Get-PhProp $i 'companyId'); $coName = [string](Get-PhProp $i 'company')
        $label = "ticket $num ($coName)"
        if (-not $coId) { $null = $skipped.Add([ordered]@{ ticket_id = $tid; number = $num; company = $coName; reason = 'The ticket has no company, so there is no primary contact to use.' }); continue }
        if (-not $cache.ContainsKey($coId)) {
            try { $cache[$coId] = Get-PsaCompanyContacts -CompanyId $coId }
            catch { $cache[$coId] = @{ error = $_.Exception.Message } }
        }
        $cc = $cache[$coId]
        if ($cc.Contains('error')) { $null = $skipped.Add([ordered]@{ ticket_id = $tid; number = $num; company = $coName; reason = "Couldn't read the company's contacts: $($cc['error'])" }); continue }
        if (-not [bool]$cc['primarySupported']) { $null = $skipped.Add([ordered]@{ ticket_id = $tid; number = $num; company = $coName; reason = "$(Get-PsaName) has no primary contact flag, so the contact has to be chosen by hand." }); continue }
        $prim = @($cc['contacts'] | Where-Object { $null -ne $_ -and [bool]$_.primary })
        if ($prim.Count -ne 1) {
            $why = if ($prim.Count -eq 0) { 'The company has no primary contact.' } else { "The company has $($prim.Count) primary contacts, so the right one has to be chosen by hand." }
            $null = $skipped.Add([ordered]@{ ticket_id = $tid; number = $num; company = $coName; reason = $why }); continue
        }
        $p = $prim[0]
        Add-PlannedChange $plan "Set the contact on $label to $($p.name)" { param($ticket, $contact) Set-PsaTicketContact -Id $ticket -ContactId $contact; 'contact set' } -Arguments @($tid, [string]$p.id)
    }
    $res = Invoke-ChangePlan $plan -Confirm:$confirm
    $fixInfo.planned = @($res.planned)
    $fixInfo.result = $res
    if ($confirm -and $res.status -in @('done', 'failed')) { $ph['actions'] = @($ph['actions']) + $res.message }
}
elseif ($wantContacts) { $fixInfo.result = @{ status = 'empty'; message = 'No tickets are missing a contact, so there was nothing to fix.'; planned = @(); ran = @(); notRun = @(); failed = $null } }
$fixInfo.skipped = @($skipped)
$ph['warnings'] = @(Get-PhWarnings $warn)
$ph['fix'] = $fixInfo
Set-NodeOutput $ph
