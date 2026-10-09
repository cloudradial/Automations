#{{COMMON}}
# =====================================================================
# SaaS subscriptions -> CloudRadial flexible asset type "SaaS"
#   CloudRadial's software records (endpointapplication) always belong to a
#   device, and its API has no SaaS or licence route, so ScalePad SaaS assets
#   (Microsoft 365, Google Workspace, ... with seats and terms) become rows of
#   a flexible asset type named "SaaS". Matched on the ScalePad SaaS id, so
#   re-runs update rather than duplicate.
# =====================================================================
$phase = 'saas'
$results = ConvertTo-Dict (Get-P $ctx 'results')
$settings = Get-P $ctx 'settings'
$companyId = [int](Get-P $ctx 'companyId')
$spClientId = [string](Get-P $ctx 'scalePadClientId')

# Field order = column order in the portal. nameKey is the trait key CloudRadial derives from the name.
$FieldDefs = @(
    @{ name = 'Name'; kind = 'Text'; order = 1; useForTitle = $true; showInList = $false; required = $true },   # shown as the NAME column already
    @{ name = 'Vendor'; kind = 'Text'; order = 2; showInList = $true },
    @{ name = 'SKU'; kind = 'Text'; order = 3 },
    @{ name = 'Category'; kind = 'Text'; order = 4 },
    @{ name = 'Status'; kind = 'Text'; order = 5; showInList = $true },
    @{ name = 'Licenses'; kind = 'Number'; order = 6; showInList = $true },
    @{ name = 'Assigned'; kind = 'Number'; order = 7; showInList = $true },
    @{ name = 'Renewal Date'; kind = 'Date'; order = 8; showInList = $true },
    @{ name = 'Term Start'; kind = 'Date'; order = 9 },
    @{ name = 'Auto Renew'; kind = 'Text'; order = 10 },
    @{ name = 'Billing'; kind = 'Text'; order = 11 },
    @{ name = 'Provider'; kind = 'Text'; order = 12 },
    @{ name = 'Tenant Domain'; kind = 'Text'; order = 13 },
    @{ name = 'ScalePad ID'; kind = 'Text'; order = 14; hint = 'Used by the ScalePad to CloudRadial Sync to match this row. Do not edit.' }
)
function ConvertTo-NameKey { param([string]$n) return (($n.Trim().ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')) }
function ConvertFrom-Traits { param($a)
    $raw = Get-P $a 'traitsJson'
    if ($raw -is [string] -and -not [string]::IsNullOrWhiteSpace($raw)) { try { return ConvertTo-Dict ($raw | ConvertFrom-Json) } catch { return [ordered]@{} } }
    return ConvertTo-Dict (Get-P $a 'traits')
}

$counts = [ordered]@{ scalePadAssets = 0; typeCreated = $false; fieldsAdded = 0; toCreate = 0; toUpdate = 0; unchanged = 0; created = 0; updated = 0; errors = 0 }
$planned = New-Object System.Collections.ArrayList

if ((Get-P $ctx 'phases' @()) -notcontains $phase) {
    $results[$phase] = [ordered]@{ ran = $false }
}
else {
    $typeName = [string](Get-P $settings 'saasTypeName' 'SaaS')
    $saas = @(Get-SpAll '/core/v1/assets/saas' @{ 'filter[client.id]' = "eq:$spClientId" })
    $rows = New-Object System.Collections.ArrayList
    foreach ($a in $saas) {
        $sub = @(Get-P $a 'subscriptions' @()) | Select-Object -First 1
        $auto = Get-P $a 'term.is_auto_renewed' (Get-P $sub 'term.is_auto_renewed')
        $vals = [ordered]@{
            'Name'          = [string](Get-P $a 'product.name' (Get-P $sub 'friendly_name' ''))
            'Vendor'        = [string](Get-P $a 'product.manufacturer.name' '')
            'SKU'           = $(if (([string](Get-P $a 'product.manufacturer_sku.name' '')) -ne ([string](Get-P $a 'product.name' ''))) { [string](Get-P $a 'product.manufacturer_sku.name' '') } else { '' })
            'Category'      = [string](Get-P $a 'product.category' '')
            'Status'        = [string](Get-P $a 'status' '')
            'Licenses'      = [string](Get-P $a 'pool.capacity' (Get-P $sub 'license_count' ''))
            'Assigned'      = [string](Get-P $a 'pool.utilized' '')
            'Renewal Date'  = Format-Day (Get-P $a 'term.ends_at' (Get-P $sub 'term.ends_at'))
            'Term Start'    = Format-Day (Get-P $a 'term.starts_at' (Get-P $sub 'term.starts_at'))
            'Auto Renew'    = $(if ($null -eq $auto) { '' } elseif ($auto -eq $true) { 'Yes' } else { 'No' })
            'Billing'       = [string](Get-P $sub 'billing_cycle_name' '')
            'Provider'      = [string](Get-P $sub 'provider_name' '')
            'Tenant Domain' = [string](Get-P $a 'tenant_domain' '')
            'ScalePad ID'   = [string](Get-P $a 'id')
        }
        if (Test-Blank $vals['Name']) { $vals['Name'] = "SaaS $($vals['ScalePad ID'])" }
        $null = $rows.Add($vals)
    }
    $counts.scalePadAssets = $rows.Count

    # --- the flexible asset type and its fields ---
    $esc = $typeName.Replace("'", "''")
    $type = @(Get-CrAll "/v2/odata/flexibleassettype?`$filter=name eq '$esc'") | Select-Object -First 1
    $typeId = if ($type) { [int](Get-P $type 'id') } else { 0 }
    if (-not $typeId -and $rows.Count -gt 0) {
        $null = $planned.Add(@{ action = 'create-type'; type = $typeName; fields = @($FieldDefs | ForEach-Object { $_.name }) })
        if ($apply) {
            $body = [ordered]@{ name = $typeName; description = 'SaaS subscriptions from ScalePad (product, vendor, seats, term). Kept current by the ScalePad to CloudRadial Sync.'; icon = 'cloud'; showInMenu = $true; fields = $FieldDefs }
            try {
                $resp = Invoke-Cr -Method POST -Path '/v2/flexible-asset-type' -Body $body
                $typeId = [int](Get-P $resp 'id' (Get-P $resp 'flexibleAssetTypeId' 0))
                if (-not $typeId) { $again = @(Get-CrAll "/v2/odata/flexibleassettype?`$filter=name eq '$esc'") | Select-Object -First 1; if ($again) { $typeId = [int](Get-P $again 'id') } }
                if ($typeId) { $counts.typeCreated = $true } else { throw 'the type was created but its id could not be read back' }
            }
            catch { $counts.errors++; Warn "Could not create the '$typeName' flexible asset type: $($_.Exception.Message)" }
        }
    }

    $keyOf = @{}
    foreach ($f in $FieldDefs) { $keyOf[$f.name] = ConvertTo-NameKey $f.name }
    $existingAssets = @()
    if ($typeId) {
        $fields = @(Get-CrAll "/v2/odata/flexibleassetfield?`$filter=flexibleAssetTypeId eq $typeId")
        $have = @{}
        foreach ($f in $fields) { $have[[string](Get-P $f 'name')] = [string](Get-P $f 'nameKey' (ConvertTo-NameKey (Get-P $f 'name'))) }
        foreach ($f in $FieldDefs) {
            if ($have.ContainsKey($f.name)) { $keyOf[$f.name] = $have[$f.name]; continue }
            if ($fields.Count -eq 0 -and $counts.typeCreated) { continue }   # created inline just now
            $null = $planned.Add(@{ action = 'add-field'; field = $f.name })
            if ($apply) {
                try { $null = Invoke-Cr -Method POST -Path '/v2/flexible-asset-field' -Body ([ordered]@{ flexibleAssetTypeId = $typeId } + $f); $counts.fieldsAdded++ }
                catch { $counts.errors++; Warn "Could not add field '$($f.name)' to '$typeName': $($_.Exception.Message)" }
            }
        }
        $existingAssets = @(Get-CrAll "/v2/odata/flexibleasset?`$filter=companyId eq $companyId and flexibleAssetTypeId eq $typeId")
    }
    $idKey = $keyOf['ScalePad ID']; $serialKey = 'no-serial-field'
    $byId = @{}; $bySerial = @{}
    foreach ($a in $existingAssets) {
        $t = ConvertFrom-Traits $a
        $sid = [string](Get-P $t $idKey ''); $sn = Normalize-Serial (Get-P $t $serialKey '')
        if ($sid) { $byId[$sid] = $a }
        if ($sn -and -not $bySerial.ContainsKey($sn)) { $bySerial[$sn] = $a }
    }

    foreach ($vals in $rows) {
        $traits = [ordered]@{}
        foreach ($k in $vals.Keys) { if (-not (Test-Blank $vals[$k])) { $traits[$keyOf[$k]] = [string]$vals[$k] } }
        $match = $byId[$vals['ScalePad ID']]
        if ($null -eq $match -and $vals['Serial Number']) { $match = $bySerial[(Normalize-Serial $vals['Serial Number'])] }
        if ($null -ne $match) {
            $cur = ConvertFrom-Traits $match
            $merged = [ordered]@{}; foreach ($k in $cur.Keys) { $merged[$k] = $cur[$k] }
            $changed = @()
            foreach ($k in $traits.Keys) { if ([string](Get-P $cur $k '') -ne $traits[$k]) { $merged[$k] = $traits[$k]; $changed += $k } }
            if ($changed.Count -eq 0) { $counts.unchanged++; continue }
            $counts.toUpdate++
            $assetId = [int](Get-P $match 'id')
            $null = $planned.Add(@{ action = 'update'; asset = $vals['Name']; flexibleAssetId = $assetId; fields = $changed })
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
        $counts.toCreate++
        $null = $planned.Add(@{ action = 'create'; asset = $vals['Name']; type = $vals['Type']; serial = $vals['Serial Number'] })
        if ($apply -and $typeId) {
            try { $null = Invoke-Cr -Method POST -Path '/v2/flexible-asset' -Body ([ordered]@{ companyId = $companyId; flexibleAssetTypeId = $typeId; traits = $traits }); $counts.created++ }
            catch { $counts.errors++; Warn "Create failed for flexible asset $($vals['Name']): $($_.Exception.Message)" }
        }
    }
    $results[$phase] = [ordered]@{
        ran = $true; counts = $counts; flexibleAssetType = $typeName; flexibleAssetTypeId = $typeId
        planned = @($planned | Select-Object -First 150); plannedTotal = $planned.Count
    }
}

$ctx.results = $results
$ctx.warnings = @(@(Get-P $ctx 'warnings' @()) + @($warnings))
$c = $counts
Set-NodeOutput @{ status = 'ok'; message = "SaaS: $($c.scalePadAssets) ScalePad SaaS subscriptions, $(if ($apply) { "$($c.created) created, $($c.updated) updated" } else { "$($c.toCreate) to create, $($c.toUpdate) to update" }), $($c.unchanged) unchanged, $($c.errors) errors."; ctx = $ctx }
