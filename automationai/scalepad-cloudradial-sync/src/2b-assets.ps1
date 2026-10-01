#{{COMMON}}
# =====================================================================
# Step 3 - Other ScalePad hardware to CloudRadial flexible assets
#   Network gear, mobiles, printers/imaging (any ScalePad type that isn't
#   synced as an endpoint) and in-scope devices with no serial number become
#   flexible assets, one type per kind of device ("Network Devices",
#   "Mobile Devices", "Printers & Imaging", ...), shown under Infrastructure.
#   Matched on the ScalePad asset id, so re-runs update rather than duplicate.
#   Rows an earlier version wrote to the single "ScalePad Assets" type are
#   moved to their device type. Native v2 routes: /v2/flexible-asset-type,
#   /v2/flexible-asset-field, /v2/flexible-asset (reads via /v2/odata).
# =====================================================================
$phase = 'assets'
$results = ConvertTo-Dict (Get-P $ctx 'results')
$settings = Get-P $ctx 'settings'
$companyId = [int](Get-P $ctx 'companyId')
$spClientId = [string](Get-P $ctx 'scalePadClientId')

# Field order = column order in the portal. nameKey is the trait key CloudRadial derives from the name.
$FieldDefs = @(
    @{ name = 'Name'; kind = 'Text'; order = 1; useForTitle = $true; showInList = $false; required = $true },   # shown as the NAME column already
    @{ name = 'Type'; kind = 'Text'; order = 2; showInList = $true },
    @{ name = 'Manufacturer'; kind = 'Text'; order = 3; showInList = $true },
    @{ name = 'Model'; kind = 'Text'; order = 4; showInList = $true },
    @{ name = 'Serial Number'; kind = 'Text'; order = 5; showInList = $true },
    @{ name = 'Warranty Expires'; kind = 'Date'; order = 6; showInList = $true },
    @{ name = 'Purchase Date'; kind = 'Date'; order = 7 },
    @{ name = 'Location'; kind = 'Text'; order = 8 },
    @{ name = 'Assigned User'; kind = 'Text'; order = 9 },
    @{ name = 'ScalePad ID'; kind = 'Text'; order = 10; hint = 'Used by the ScalePad to CloudRadial Sync to match this row. Do not edit.' }
)
# ScalePad hardware type -> CloudRadial flexible asset type. First match wins.
$TypeRules = @(
    @{ match = 'NETWORK|ROUTER|SWITCH|FIREWALL|ACCESS.?POINT|WIRELESS|WIFI|GATEWAY'; name = 'Network Devices'; icon = 'router'; what = 'network devices (routers, switches, firewalls, access points)' },
    @{ match = 'MOBILE|PHONE|TABLET'; name = 'Mobile Devices'; icon = 'smartphone'; what = 'mobile phones and tablets' },
    @{ match = 'IMAGING|PRINT|SCAN|COPIER|MFP|PLOTTER'; name = 'Printers & Imaging'; icon = 'printer'; what = 'printers, scanners and other imaging devices' },
    @{ match = 'STORAGE|NAS|SAN'; name = 'Storage Devices'; icon = 'hdd'; what = 'storage devices (NAS and SAN)' },
    @{ match = 'UPS|POWER|PDU'; name = 'Power Devices'; icon = 'battery'; what = 'UPS and power devices' },
    @{ match = '^WORKSTATION$|^DESKTOP$|^LAPTOP$'; name = 'Workstations (No Serial)'; icon = 'desktop'; what = 'workstations that have no serial number, so they cannot be matched to an endpoint' },
    @{ match = '^SERVER$'; name = 'Servers (No Serial)'; icon = 'server'; what = 'servers that have no serial number, so they cannot be matched to an endpoint' },
    @{ match = '^VIRTUAL'; name = 'Virtual Machines (No Serial)'; icon = 'server'; what = 'virtual machines that have no serial number, so they cannot be matched to an endpoint' }
)
$OtherRule = @{ name = 'Other Hardware'; icon = 'cpu'; what = 'other hardware' }
function Get-TypeRule { param([string]$spType)
    $single = [string](Get-P $settings 'flexibleAssetTypeName' '')
    if ($single) { return @{ name = $single; icon = 'router'; what = 'hardware that is not an endpoint' } }   # opt-in: everything in one type
    $rule = $OtherRule
    foreach ($r in $TypeRules) { if ($spType -match $r.match) { $rule = $r; break } }
    # Optional rename per ScalePad type, e.g. {"NETWORK": "Network Equipment"}.
    $names = ConvertTo-Dict (Get-P $settings 'flexibleAssetTypeNames' @{})
    if ($names.Contains($spType) -and [string]$names[$spType]) { return @{ name = [string]$names[$spType]; icon = $rule.icon; what = $rule.what } }
    return $rule
}
function ConvertTo-NameKey { param([string]$n) return (($n.Trim().ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')) }
function ConvertFrom-Traits { param($a)
    $raw = Get-P $a 'traitsJson'
    if ($raw -is [string] -and -not [string]::IsNullOrWhiteSpace($raw)) { try { return ConvertTo-Dict ($raw | ConvertFrom-Json) } catch { return [ordered]@{} } }
    return ConvertTo-Dict (Get-P $a 'traits')
}

$counts = [ordered]@{ scalePadAssets = 0; byType = [ordered]@{}; noSerialDevices = 0; typesCreated = 0; fieldsAdded = 0; toCreate = 0; toUpdate = 0; toMove = 0; unchanged = 0; created = 0; updated = 0; moved = 0; errors = 0 }
$planned = New-Object System.Collections.ArrayList
$typeIds = [ordered]@{}

# Finds (or, in apply, creates) one flexible asset type with the fields above, and reads this company's rows in it.
function Open-FlexType { param([string]$Name, [string]$Icon, [string]$What, [bool]$Create)
    $esc = $Name.Replace("'", "''")
    $t = @(Get-CrAll "/v2/odata/flexibleassettype?`$filter=name eq '$esc'") | Select-Object -First 1
    $id = if ($t) { [int](Get-P $t 'id') } else { 0 }
    $madeNow = $false
    if (-not $id -and $Create) {
        $null = $planned.Add(@{ action = 'create-type'; type = $Name; fields = @($FieldDefs | ForEach-Object { $_.name }) })
        if ($apply) {
            $body = [ordered]@{ name = $Name; description = "ScalePad Lifecycle Manager hardware: $What. Kept current by the ScalePad to CloudRadial Sync."; icon = $Icon; showInMenu = $true; fields = $FieldDefs }
            try {
                $resp = $null
                try { $resp = Invoke-Cr -Method POST -Path '/v2/flexible-asset-type' -Body $body }
                catch { $body.icon = 'router'; $resp = Invoke-Cr -Method POST -Path '/v2/flexible-asset-type' -Body $body }   # an icon name the portal doesn't know
                $id = [int](Get-P $resp 'id' (Get-P $resp 'flexibleAssetTypeId' 0))
                if (-not $id) { $again = @(Get-CrAll "/v2/odata/flexibleassettype?`$filter=name eq '$esc'") | Select-Object -First 1; if ($again) { $id = [int](Get-P $again 'id') } }
                if ($id) { $counts.typesCreated++; $madeNow = $true } else { throw 'the type was created but its id could not be read back' }
            }
            catch { $counts.errors++; Warn "Could not create the '$Name' flexible asset type: $($_.Exception.Message)" }
        }
    }
    $keyOf = @{}; foreach ($f in $FieldDefs) { $keyOf[$f.name] = ConvertTo-NameKey $f.name }
    $byId = @{}; $bySerial = @{}
    if ($id) {
        $fields = @(Get-CrAll "/v2/odata/flexibleassetfield?`$filter=flexibleAssetTypeId eq $id")
        $have = @{}; foreach ($f in $fields) { $have[[string](Get-P $f 'name')] = [string](Get-P $f 'nameKey' (ConvertTo-NameKey (Get-P $f 'name'))) }
        foreach ($f in $FieldDefs) {
            if ($have.ContainsKey($f.name)) { $keyOf[$f.name] = $have[$f.name]; continue }
            if ($fields.Count -eq 0 -and $madeNow) { continue }   # created inline just now
            if (-not $Create) { continue }
            $null = $planned.Add(@{ action = 'add-field'; type = $Name; field = $f.name })
            if ($apply) {
                try { $null = Invoke-Cr -Method POST -Path '/v2/flexible-asset-field' -Body ([ordered]@{ flexibleAssetTypeId = $id } + $f); $counts.fieldsAdded++ }
                catch { $counts.errors++; Warn "Could not add field '$($f.name)' to '$Name': $($_.Exception.Message)" }
            }
        }
        foreach ($a in @(Get-CrAll "/v2/odata/flexibleasset?`$filter=companyId eq $companyId and flexibleAssetTypeId eq $id")) {
            $tr = ConvertFrom-Traits $a
            $sid = [string](Get-P $tr $keyOf['ScalePad ID'] ''); $sn = Normalize-Serial (Get-P $tr $keyOf['Serial Number'] '')
            if ($sid) { $byId[$sid] = $a }
            if ($sn -and -not $bySerial.ContainsKey($sn)) { $bySerial[$sn] = $a }
        }
    }
    return @{ name = $Name; id = $id; keyOf = $keyOf; byId = $byId; bySerial = $bySerial }
}
function Find-Row { param($T, $vals)
    $m = $T.byId[$vals['ScalePad ID']]
    if ($null -eq $m -and $vals['Serial Number']) { $m = $T.bySerial[(Normalize-Serial $vals['Serial Number'])] }
    return $m
}

if ((Get-P $ctx 'phases' @()) -notcontains $phase) {
    $results[$phase] = [ordered]@{ ran = $false }
}
else {
    $deviceTypes = @(Get-P $settings 'deviceTypes' @('WORKSTATION', 'SERVER', 'VIRTUAL'))
    $assetTypes = @(Get-P $settings 'assetTypes' @())
    $includeNoSerial = [bool](Get-P $settings 'includeNoSerialDevices' $true)
    $legacyName = [string](Get-P $settings 'legacyFlexibleAssetTypeName' 'ScalePad Assets')

    $hw = @(Get-SpAll '/core/v1/assets/hardware' @{ 'filter[client.id]' = "eq:$spClientId" })
    $life = @(Get-SpAll '/lifecycle-manager/v1/assets/hardware/lifecycles' @{ 'filter[client_id]' = "eq:$spClientId" })
    $lifeBySerial = @{}
    foreach ($l in $life) { $s = Normalize-Serial (Get-P $l 'serial_number'); if ($s) { $lifeBySerial[$s] = $l } }

    $rows = New-Object System.Collections.ArrayList
    foreach ($d in $hw) {
        $type = ([string](Get-P $d 'type' '')).ToUpperInvariant()
        $serial = Normalize-Serial (Get-P $d 'serial_number')
        $isDeviceType = $type -in $deviceTypes
        $take = if ($isDeviceType) { $includeNoSerial -and -not $serial } elseif ($assetTypes.Count -gt 0) { $type -in $assetTypes } else { $true }
        if (-not $take) { continue }
        if ($isDeviceType) { $counts.noSerialDevices++ }
        $l = if ($serial) { $lifeBySerial[$serial] } else { $null }
        $rule = Get-TypeRule $type
        $label = if ($type) { (Get-Culture).TextInfo.ToTitleCase(($type -replace '_', ' ').ToLowerInvariant()) } else { 'Unknown' }
        if (-not $counts.byType.Contains($rule.name)) { $counts.byType[$rule.name] = 0 }
        $counts.byType[$rule.name]++
        $vals = [ordered]@{
            'Name'             = [string](Get-P $d 'name' $serial)
            'Type'             = $label
            'Manufacturer'     = [string](Get-P $d 'manufacturer.name' (Get-P $l 'manufacturer' ''))
            'Model'            = [string](Get-P $d 'model.description' (Get-P $d 'model.number' (Get-P $l 'model' '')))
            'Serial Number'    = [string](Get-P $d 'serial_number' '')
            'Warranty Expires' = Format-Day (Get-P $l 'warranty_expiry_date')
            'Purchase Date'    = Format-Day (Get-P $l 'purchase_date')
            'Location'         = [string](Get-P $d 'site.name' (Get-P $d 'location_name' ''))
            'Assigned User'    = [string](Get-P $d 'assigned_user_name' (Get-P $d 'assigned_user.name' ''))
            'ScalePad ID'      = [string](Get-P $d 'id')
        }
        if (Test-Blank $vals['Name']) { $vals['Name'] = "$label $($vals['ScalePad ID'])" }
        $null = $rows.Add(@{ vals = $vals; rule = $rule })
    }
    $counts.scalePadAssets = $rows.Count

    # Rows an earlier version put in the single legacy type are moved, not duplicated.
    $legacy = $null
    if ($rows.Count -gt 0 -and $legacyName -and -not ($rows | Where-Object { $_.rule.name -eq $legacyName })) { $legacy = Open-FlexType -Name $legacyName -Icon 'router' -What '' -Create:$false }

    $types = @{}
    foreach ($row in $rows) {
        $vals = $row.vals; $rule = $row.rule
        if (-not $types.ContainsKey($rule.name)) { $types[$rule.name] = Open-FlexType -Name $rule.name -Icon $rule.icon -What $rule.what -Create:$true; $typeIds[$rule.name] = $types[$rule.name].id }
        $T = $types[$rule.name]
        $traits = [ordered]@{}
        foreach ($k in $vals.Keys) { if (-not (Test-Blank $vals[$k])) { $traits[$T.keyOf[$k]] = [string]$vals[$k] } }

        $match = Find-Row $T $vals
        if ($null -ne $match) {
            $cur = ConvertFrom-Traits $match
            $merged = [ordered]@{}; foreach ($k in $cur.Keys) { $merged[$k] = $cur[$k] }
            $changed = @()
            foreach ($k in $traits.Keys) { if ([string](Get-P $cur $k '') -ne $traits[$k]) { $merged[$k] = $traits[$k]; $changed += $k } }
            if ($changed.Count -eq 0) { $counts.unchanged++; continue }
            $counts.toUpdate++
            $assetId = [int](Get-P $match 'id')
            $null = $planned.Add(@{ action = 'update'; asset = $vals['Name']; type = $rule.name; flexibleAssetId = $assetId; fields = $changed })
            if ($apply) {
                try {
                    $json = $merged | ConvertTo-Json -Depth 5 -Compress
                    try { $null = Invoke-Cr -Method PATCH -Path "/v2/flexible-asset/$assetId" -Body @(@{ op = 'replace'; path = '/traitsJson'; value = $json }) }
                    catch {
                        # Fallback: the IT Glue-compatible route takes traits as an object.
                        $b = @{ data = @{ type = 'flexible-assets'; id = $assetId; attributes = @{ traits = $merged } } } | ConvertTo-Json -Depth 8
                        $null = Invoke-WithRetry -What "CloudRadial PATCH /compatibility/flexible_assets/$assetId" -Call { Invoke-RestMethod -Method Patch -Uri "$crBase/compatibility/flexible_assets/$assetId" -Headers $crHeaders -Body $b -ContentType 'application/json' }
                    }
                    $counts.updated++
                }
                catch { $counts.errors++; Warn "Update failed for flexible asset $($vals['Name']): $($_.Exception.Message)" }
            }
            continue
        }

        $old = if ($null -ne $legacy -and $legacy.id) { Find-Row $legacy $vals } else { $null }
        if ($null -ne $old) { $counts.toMove++ } else { $counts.toCreate++ }
        $null = $planned.Add(@{ action = $(if ($null -ne $old) { 'move' } else { 'create' }); asset = $vals['Name']; type = $rule.name; serial = $vals['Serial Number']; from = $(if ($null -ne $old) { $legacyName }) })
        if (-not ($apply -and $T.id)) { continue }
        try {
            $null = Invoke-Cr -Method POST -Path '/v2/flexible-asset' -Body ([ordered]@{ companyId = $companyId; flexibleAssetTypeId = $T.id; traits = $traits })
            if ($null -ne $old) {
                $oldId = [int](Get-P $old 'id')
                try { $null = Invoke-Cr -Method DELETE -Path "/v2/flexible-asset/$oldId"; $counts.moved++ }
                catch { $counts.errors++; Warn "Moved '$($vals['Name'])' to '$($rule.name)' but couldn't remove the old copy from '$legacyName' (flexible asset $oldId): $($_.Exception.Message)" }
            }
            else { $counts.created++ }
        }
        catch { $counts.errors++; Warn "Create failed for flexible asset $($vals['Name']) in '$($rule.name)': $($_.Exception.Message)" }
    }
    $typeList = @($counts.byType.Keys)
    $results[$phase] = [ordered]@{
        ran = $true; counts = $counts
        flexibleAssetType = ($typeList -join ', '); flexibleAssetTypes = $typeList; flexibleAssetTypeIds = $typeIds
        legacyType = $(if ($null -ne $legacy -and $legacy.id) { $legacyName })
        planned = @($planned | Select-Object -First 150); plannedTotal = $planned.Count
    }
}

$ctx.results = $results
$ctx.warnings = @(@(Get-P $ctx 'warnings' @()) + @($warnings))
$c = $counts
$kinds = @($c.byType.GetEnumerator() | ForEach-Object { "$($_.Value) $($_.Key)" }) -join ', '
Set-NodeOutput @{ status = 'ok'; message = "Flexible assets: $($c.scalePadAssets) ScalePad assets that aren't endpoints$(if ($kinds) { " ($kinds)" }), $($c.noSerialDevices) of them devices with no serial; $(if ($apply) { "$($c.created) created, $($c.moved) moved from the old single type, $($c.updated) updated" } else { "$($c.toCreate) to create, $($c.toMove) to move from the old single type, $($c.toUpdate) to update" }), $($c.unchanged) unchanged, $($c.errors) errors."; ctx = $ctx }
