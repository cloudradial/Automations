#{{COMMON}}
# =====================================================================
# Step 1 - Resolve the client in ScalePad and CloudRadial, read options
# =====================================================================
$defaultPhases = @('devices', 'assets', 'saas', 'software', 'assessments', 'roadmap', 'insights', 'archive', 'meetings', 'followup')
$allPhases = @('cleanup') + $defaultPhases
$phasesIn = Get-P $ctx 'phases'
$phases = @()
if ($phasesIn -is [array]) { $phases = @($phasesIn | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() }) }
elseif (-not (Test-Blank $phasesIn)) { $phases = @(([string]$phasesIn).Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() }) }
if ($phases.Count -eq 0 -or $phases -contains 'all') { $phases = $defaultPhases }
if ([string](Get-P $ctx 'cleanupDuplicateSoftware' 'false') -match '^(true|yes|1)$') { $phases = @('cleanup') }
$unknown = @($phases | Where-Object { $_ -notin $allPhases })
if ($unknown.Count -gt 0) { Warn "Ignored unknown phase(s): $($unknown -join ', '). Valid: $($allPhases -join ', ')." }
$phases = @($phases | Where-Object { $_ -in $allPhases })

$settings = [ordered]@{
    deviceTypes            = @(([string](Get-P $ctx 'deviceTypes' 'WORKSTATION,SERVER,VIRTUAL')).Split(',') | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ })
    createMissingDevices   = -not ([string](Get-P $ctx 'createMissingDevices' 'true') -match '^(false|no|0)$')
    overwriteWarranty      = ([string](Get-P $ctx 'overwriteWarranty' 'false') -match '^(true|yes|1)$')
    assetTypes             = @(([string](Get-P $ctx 'assetTypes' '')).Split(',') | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ })
    includeNoSerialDevices = -not ([string](Get-P $ctx 'includeNoSerialDevices' 'true') -match '^(false|no|0)$')
    saasTypeName           = [string](Get-P $ctx 'saasTypeName' 'SaaS')
    # Blank = one flexible asset type per kind of device (Network Devices, Mobile Devices, ...).
    flexibleAssetTypeName  = [string](Get-P $ctx 'flexibleAssetTypeName' '')
    flexibleAssetTypeNames = (ConvertTo-Dict (Get-P $ctx 'flexibleAssetTypeNames' @{}))
    legacyFlexibleAssetTypeName = [string](Get-P $ctx 'legacyFlexibleAssetTypeName' 'ScalePad Assets')
    confirmCleanup         = ([string](Get-P $ctx 'confirmCleanup' 'false') -match '^(true|yes|1)$')
    skipDevicesWithSoftware = -not ([string](Get-P $ctx 'skipDevicesWithSoftware' 'true') -match '^(false|no|0)$')
    maxSoftwareWrites      = [int](Get-P $ctx 'maxSoftwareWrites' 2000)
    assessmentStatus       = [string](Get-P $ctx 'assessmentStatus' 'Completed')
    labelScoreMap          = Get-P $ctx 'labelScoreMap'
    roadmapCategory        = [string](Get-P $ctx 'roadmapCategory' 'Efficiency')
    roadmapCategoryId      = [int](Get-P $ctx 'roadmapCategoryId' 7)
    includeInactiveContracts = ([string](Get-P $ctx 'includeInactiveContracts' 'false') -match '^(true|yes|1)$')
    includeContracts       = -not ([string](Get-P $ctx 'includeContracts' 'true') -match '^(false|no|0)$')
    insightDeviceLimit     = [int](Get-P $ctx 'insightDeviceLimit' 25)
    insightCategory        = [string](Get-P $ctx 'insightCategory' (Get-P $ctx 'roadmapCategory' 'Efficiency'))
    insightCategoryId      = [int](Get-P $ctx 'insightCategoryId' (Get-P $ctx 'roadmapCategoryId' 7))
    meetingArchiveName     = [string](Get-P $ctx 'meetingArchiveName' 'ScalePad Meeting Notes')
    meetingLimit           = [int](Get-P $ctx 'meetingLimit' 0)   # 0 = every meeting (full migration)
    archiveName            = [string](Get-P $ctx 'archiveName' 'ScalePad QBR History')
    deliverableLimit       = [int](Get-P $ctx 'deliverableLimit' 0)   # 0 = every deliverable (full migration)
    reportTarget           = ([string](Get-P $ctx 'reportTarget' 'archive')).ToLowerInvariant()   # archive = admin-only (security roles)
    reportArchiveName      = [string](Get-P $ctx 'reportArchiveName' 'ScalePad Migration')
}
if ($settings.reportTarget -notin @('archive', 'article', 'none')) { Warn "reportTarget '$($settings.reportTarget)' isn't archive, article or none; using archive."; $settings.reportTarget = 'archive' }


# --- Mode: a run with no input migrates. "plan" previews without writing. ---
$modeIn = ([string](Get-P $ctx 'mode' '')).Trim().ToLowerInvariant()
$mode = if ($modeIn -eq 'plan') { 'plan' } else { 'apply' }
if ($modeIn -and $modeIn -notin @('plan', 'apply')) { Warn "mode '$modeIn' isn't plan or apply; using apply." }

# --- Match every ScalePad client to a CloudRadial company by name ---
$spClients = @(Get-SpAll '/core/v1/clients')
$crCos = @(Get-CrAll "/v2/odata/company?`$select=companyId,name")
$crById = @{}; $crByName = @{}
foreach ($c in $crCos) {
    $crById[[int](Get-P $c 'companyId')] = $c
    $k = Normalize-Name (Get-P $c 'name'); if ($k) { if (-not $crByName.ContainsKey($k)) { $crByName[$k] = @() }; $crByName[$k] += $c }
}
$spById = @{}; foreach ($s in $spClients) { $spById[[string](Get-P $s 'id')] = $s }
$pairs = New-Object System.Collections.ArrayList
$unmatched = New-Object System.Collections.ArrayList
foreach ($s in $spClients) {
    $hits = @($crByName[(Normalize-Name (Get-P $s 'name'))] | Where-Object { $_ })
    if ($hits.Count -eq 1) { $null = $pairs.Add([ordered]@{ scalePadClientId = [string](Get-P $s 'id'); scalePadClientName = [string](Get-P $s 'name'); companyId = [int](Get-P $hits[0] 'companyId'); companyName = [string](Get-P $hits[0] 'name') }) }
    elseif ($hits.Count -gt 1) { $null = $unmatched.Add("$(Get-P $s 'name') (matches $($hits.Count) CloudRadial companies)") }
    else { $null = $unmatched.Add([string](Get-P $s 'name')) }
}

# --- Optional limits: one company, a list, or a cap ---
$limitIds = @()
foreach ($k in @('companyId', 'companyIds')) {
    $v = Get-P $ctx $k
    if ($v -is [array]) { $limitIds += @($v | ForEach-Object { [int]$_ } | Where-Object { $_ -gt 0 }) }
    elseif (-not (Test-Blank $v) -and [string]$v -ne '0') { $limitIds += @(([string]$v).Split(',') | ForEach-Object { [int]$_.Trim() } | Where-Object { $_ -gt 0 }) }
}
$collisions = @($pairs | Group-Object { $_.companyId } | Where-Object { $_.Count -gt 1 })
$collidedIds = @($collisions | ForEach-Object { [int]$_.Name })
foreach ($g in $collisions) {
    $null = $unmatched.Add("$((@($g.Group | ForEach-Object { $_.scalePadClientName })) -join ' and ') all match CloudRadial company '$($g.Group[0].companyName)' ($($g.Name)) - not migrated. Run with {""companyId"": $($g.Name), ""scalePadClientId"": ""<ScalePad id>""} to pick one: $((@($g.Group | ForEach-Object { "$($_.scalePadClientName) = $($_.scalePadClientId)" })) -join '; ').")
}
$spIdIn = [string](Get-P $ctx 'scalePadClientId' '')
$spNameIn = [string](Get-P $ctx 'scalePadClientName' '')
$targets = @($pairs | Where-Object { $_.companyId -notin $collidedIds })
if (-not (Test-Blank $spIdIn)) {
    $targets = @($pairs | Where-Object { $_.scalePadClientId -eq $spIdIn })
    if ($targets.Count -eq 0) {
        # Named explicitly: pair it even when the names differ.
        $s = $spById[$spIdIn]; if ($null -eq $s) { $s = Get-SpOne "/core/v1/clients/$spIdIn" }
        $cid = if ($limitIds.Count -eq 1) { $limitIds[0] } else { 0 }
        if ($cid -le 0 -or -not $crById.ContainsKey($cid)) { throw "ScalePad client $spIdIn doesn't match a CloudRadial company by name. Send companyId as well." }
        $targets = @([ordered]@{ scalePadClientId = $spIdIn; scalePadClientName = [string](Get-P $s 'name' (Get-P $s 'data.name' '')); companyId = $cid; companyName = [string](Get-P $crById[$cid] 'name') })
    }
}
elseif (-not (Test-Blank $spNameIn)) { $targets = @($targets | Where-Object { (Normalize-Name $_.scalePadClientName) -eq (Normalize-Name $spNameIn) }) }
if ($limitIds.Count -gt 0 -and (Test-Blank $spIdIn)) {
    $targets = @($targets | Where-Object { $_.companyId -in $limitIds })
    $missing = @($limitIds | Where-Object { $_ -notin @($targets | ForEach-Object { $_.companyId }) })
    foreach ($m in $missing) { Warn "CloudRadial company $m $(if ($crById.ContainsKey($m)) { "('$(Get-P $crById[$m] 'name')') has no ScalePad client with the same name - send scalePadClientId to pair it" } else { 'was not found' })." }
}
$max = [int](Get-P $ctx 'maxCompanies' 0)
if ($max -gt 0 -and $targets.Count -gt $max) { Warn "Limited to the first $max of $($targets.Count) matched companies (maxCompanies)."; $targets = @($targets | Select-Object -First $max) }

$items = @($targets | ForEach-Object {
    [ordered]@{
        mode = $mode; phases = $phases; settings = $settings
        companyId = $_.companyId; companyName = $_.companyName
        scalePadClientId = $_.scalePadClientId; scalePadClientName = $_.scalePadClientName
        results = [ordered]@{}; warnings = @($warnings)
    }
})
$names = (@($targets | Select-Object -First 8 | ForEach-Object { "$($_.companyName) ($($_.companyId))" }) -join ', ') + $(if ($targets.Count -gt 8) { ', ...' } else { '' })
Set-NodeOutput @{
    status = 'ok'
    message = "$(if ($mode -eq 'apply') { 'Migrating' } else { 'Previewing (plan mode, no writes)' }) $($targets.Count) compan$(if ($targets.Count -eq 1) { 'y' } else { 'ies' }) matched by name: $names. Phases: $($phases -join ', ').$(if ($unmatched.Count) { " $($unmatched.Count) ScalePad clients have no CloudRadial company with the same name." })"
    mode = $mode; phases = $phases
    targets = $items
    matched = @($targets | ForEach-Object { [ordered]@{ companyId = $_.companyId; companyName = $_.companyName; scalePadClientId = $_.scalePadClientId; scalePadClientName = $_.scalePadClientName } })
    unmatched = @($unmatched | Select-Object -First 500)
    warnings = @($warnings)
}
