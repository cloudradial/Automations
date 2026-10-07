# === NODE: Check CloudRadial and the PSA ===
# Read-only. Makes sure the client isn't already in CloudRadial (by name, by domain and by PSA link),
# finds the company group, and finds the client's company in the PSA. Fails closed, with nothing changed,
# when CloudRadial or the PSA isn't set up, the client already exists, or the PSA match isn't exactly one.
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
function Stop-NcoCheck {
    param([string]$Status, [string]$Msg)
    $nco['status'] = $Status; $nco['message'] = $Msg; $nco['internal_note'] = "New client onboarding stopped before changing anything: $Msg"
    Set-NodeOutput $nco
    throw $Msg
}
function Get-NcoPlural { param([int]$n, [string]$one, [string]$many) if ($n -eq 1) { return "1 $one" }; return "$n $many" }

$nco = Read-NcoState @('inputs')
$opt = $nco['inputs']
$name = [string](Get-NcoProp $opt 'company_name')
$domain = [string](Get-NcoProp $opt 'primary_domain')
$existingId = [string](Get-NcoProp $opt 'company_id')
$groupName = [string](Get-NcoProp $opt 'company_group')
$warnings = @($nco['warnings'])

# ---- CloudRadial ----
try { $null = Connect-Cr }
catch { Stop-NcoCheck 'error' "CloudRadial isn't set up on this runner. $($_.Exception.Message.TrimEnd('.')). Nothing was changed." }

$ncoCr = [ordered]@{ existing = $false; company_id = 0; company_name = $name; psa_key = ''; psa_identifier = ''; has_domain = $false; group_id = 0; group_name = ''; in_group = $false; users = -1; endpoints = -1 }
$companies = @(Get-CrAll "/v2/odata/company?`$select=companyId,name,psaKey,psaIdentifier,endpointCount")
$domainRows = @(Get-CrAll "/v2/odata/domain?`$filter=$([uri]::EscapeDataString("name eq '$domain'"))&`$select=companyDomainId,companyId,name" | Where-Object { ([string](Get-NcoProp $_ 'name')).Trim().ToLowerInvariant() -eq $domain -and -not [bool](Get-NcoProp $_ 'isDeleted') })
$byName = @($companies | Where-Object { ([string](Get-NcoProp $_ 'name')).Trim() -ieq $name })

if ($existingId -ne '') {
    $co = @($companies | Where-Object { [string](Get-NcoProp $_ 'companyId') -eq $existingId }) | Select-Object -First 1
    if ($null -eq $co) { Stop-NcoCheck 'rejected' "CloudRadial has no company $existingId. Check company_id, or leave it empty to create the company. Nothing was changed." }
    $ncoCr.existing = $true; $ncoCr.company_id = [int]$existingId; $ncoCr.company_name = [string](Get-NcoProp $co 'name')
    $k = Get-NcoProp $co 'psaKey'; if ($null -ne $k -and [string]$k -ne '0') { $ncoCr.psa_key = [string]$k }
    $ncoCr.psa_identifier = [string](Get-NcoProp $co 'psaIdentifier')
    if ($ncoCr.company_name.Trim() -ine $name) { $warnings += "CloudRadial company $existingId is named '$($ncoCr.company_name)', not '$name'. It was used because company_id was given." }
    $other = @($domainRows | Where-Object { [string](Get-NcoProp $_ 'companyId') -ne $existingId }) | Select-Object -First 1
    if ($null -ne $other) { Stop-NcoCheck 'rejected' "The domain $domain already belongs to another CloudRadial company (company $(Get-NcoProp $other 'companyId')). Nothing was changed." }
    $ncoCr.has_domain = @($domainRows).Count -gt 0
    $ncoCr.users = @(Get-CrAll "/v2/odata/user?`$filter=$([uri]::EscapeDataString("companyId eq $existingId"))&`$select=userId,isDeleted" | Where-Object { -not [bool](Get-NcoProp $_ 'isDeleted') }).Count
    $ec = Get-NcoProp $co 'endpointCount'
    $ncoCr.endpoints = $(if ($null -ne $ec -and [string]$ec -match '^\d+$') { [int]$ec } else { @(Get-CrAll "/v2/odata/endpoint?`$filter=$([uri]::EscapeDataString("companyId eq $existingId"))&`$select=companyEndpointId").Count })
}
else {
    if ($byName.Count) { $id = Get-NcoProp $byName[0] 'companyId'; Stop-NcoCheck 'rejected' "$name is already in CloudRadial (company $id). To finish its onboarding, run again with company_id set to $id. Nothing was changed." }
    if (@($domainRows).Count) { $id = Get-NcoProp $domainRows[0] 'companyId'; Stop-NcoCheck 'rejected' "The domain $domain is already on CloudRadial company $id, so $name may already exist under another name. To finish that company's onboarding, run again with company_id set to $id. Nothing was changed." }
}

# Company group: must already exist, so a typo never creates a stray group.
if ($groupName -ne '') {
    $groups = @(Get-CrAll "/v2/odata/companygroup?`$select=companyGroupId,group")
    $g = @($groups | Where-Object { ([string](Get-NcoProp $_ 'group')).Trim() -ieq $groupName.Trim() }) | Select-Object -First 1
    if ($null -eq $g) {
        $names = @($groups | ForEach-Object { [string](Get-NcoProp $_ 'group') } | Sort-Object | Select-Object -First 20)
        Stop-NcoCheck 'incomplete' "CloudRadial has no company group named '$groupName'. Create it in the portal first, or use one of: $(if ($names.Count) { $names -join ', ' } else { 'none exist yet' }). Nothing was changed."
    }
    $ncoCr.group_id = [int](Get-NcoProp $g 'companyGroupId'); $ncoCr.group_name = [string](Get-NcoProp $g 'group')
    if ($ncoCr.existing) { $ncoCr.in_group = @(Get-CrAll "/v2/odata/companygroupcompany?`$filter=$([uri]::EscapeDataString("companyId eq $($ncoCr.company_id) and companyGroupId eq $($ncoCr.group_id)"))").Count -gt 0 }
}

# ---- PSA ----
$psaType = ''
try { $psaType = Get-PsaType ([string](Get-NcoProp $opt 'psa')) } catch { Stop-NcoCheck 'incomplete' "$($_.Exception.Message) Nothing was changed." }
if (-not $psaType) { Stop-NcoCheck 'error' 'No PSA is set up on this runner, so the onboarding ticket cannot be opened. Add the PSA-Type secret (connectwise, autotask, halopsa, kaseyabms, syncro or zendesk) and that PSA''s secrets. Nothing was changed.' }
try { $null = Connect-Psa -Psa $psaType }
catch { Stop-NcoCheck 'error' "Couldn't connect to the PSA. $($_.Exception.Message.TrimEnd('.')). Nothing was changed." }
$psaName = Get-PsaName

$ncoPsa = [ordered]@{ type = $psaType; name = $psaName; company_id = [string](Get-NcoProp $opt 'psa_company_id'); company_name = ''; identifier = ''; found_by = 'input' }
if ($ncoPsa.company_id -eq '') {
    $hits = @(Find-PsaCompany -Name $name)
    $exact = @($hits | Where-Object { $_.exact })
    if ($exact.Count -eq 0) {
        $near = @($hits | Select-Object -First 5 | ForEach-Object { "$($_.name) ($($_.id))" })
        Stop-NcoCheck 'incomplete' "$psaName has no company named exactly '$name'.$(if ($near.Count) { " Close matches: $($near -join ', ')." }) Add the client in $psaName first, or pass psa_company_id. Nothing was changed."
    }
    if ($exact.Count -gt 1) { Stop-NcoCheck 'incomplete' "$psaName has $($exact.Count) companies named '$name' (ids $(@($exact | ForEach-Object { $_.id }) -join ', ')). Pass psa_company_id to pick one. Nothing was changed." }
    $ncoPsa.company_id = [string]$exact[0].id; $ncoPsa.company_name = [string]$exact[0].name; $ncoPsa.found_by = 'name'
    if ($psaType -eq 'connectwise') { $ncoPsa.identifier = [string](Get-NcoProp $exact[0].raw 'identifier') }
}
if ($ncoPsa.identifier -eq '') { $ncoPsa.identifier = $ncoPsa.company_id }

# The PSA company must not already be linked to a different CloudRadial company.
$linked = @($companies | Where-Object {
        $cid = [string](Get-NcoProp $_ 'companyId')
        $cid -ne $existingId -and (([string](Get-NcoProp $_ 'psaKey')) -eq $ncoPsa.company_id -or (([string](Get-NcoProp $_ 'psaIdentifier')) -ne '' -and ([string](Get-NcoProp $_ 'psaIdentifier')) -ieq $ncoPsa.identifier))
    }) | Select-Object -First 1
if ($null -ne $linked) { Stop-NcoCheck 'rejected' "$psaName company $($ncoPsa.company_id) is already linked to CloudRadial company $(Get-NcoProp $linked 'companyId') ($(Get-NcoProp $linked 'name')). Nothing was changed." }
if ($ncoCr.existing -and $ncoCr.psa_key -ne '' -and $ncoCr.psa_key -ne $ncoPsa.company_id) { $warnings += "CloudRadial company $($ncoCr.company_id) is already linked to $psaName company $($ncoCr.psa_key), not $($ncoPsa.company_id). The link was left as it is." }

$nco['warnings'] = @($warnings)
$nco['cloudradial'] = $ncoCr
$nco['psa'] = $ncoPsa
$nco['message'] = $(if ($ncoCr.existing) { "Found CloudRadial company $($ncoCr.company_id) and $psaName company $($ncoPsa.company_id)." } else { "$name is not in CloudRadial yet. Found $psaName company $($ncoPsa.company_id)." })
Set-NodeOutput $nco
