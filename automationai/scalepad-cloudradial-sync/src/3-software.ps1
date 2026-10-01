#{{COMMON}}
# =====================================================================
# Step 3 - Installed software -> CloudRadial endpoint applications
# =====================================================================
$phase = 'software'
$results = ConvertTo-Dict (Get-P $ctx 'results')
$settings = Get-P $ctx 'settings'
$companyId = [int](Get-P $ctx 'companyId')
$spClientId = [string](Get-P $ctx 'scalePadClientId')
$counts = [ordered]@{ scalePadInstalls = 0; devicesWithSoftware = 0; scalePadDevices = 0; alreadyPresent = 0; toCreate = 0; created = 0; noDevice = 0; overCap = 0; errors = 0 }
$noDevice = New-Object System.Collections.Generic.HashSet[string]

function Split-Version { param([string]$v)
    $parts = @(([string]$v) -split '[^0-9]+' | Where-Object { $_ -ne '' } | Select-Object -First 3)
    $n = @(0, 0, 0)
    for ($i = 0; $i -lt $parts.Count; $i++) { $x = 0; if ([int]::TryParse(([string]$parts[$i]).Substring(0, [Math]::Min(9, ([string]$parts[$i]).Length)), [ref]$x)) { $n[$i] = $x } }
    return $n
}

if ((Get-P $ctx 'phases' @()) -notcontains $phase) {
    $results[$phase] = [ordered]@{ ran = $false }
}
else {
    # serial -> companyEndpointId from the devices step, refreshed from CloudRadial so
    # devices created in this run (apply) or earlier runs are included.
    $epBySerial = @{}
    $prior = Get-P $results 'devices.serialMap'
    if ($null -ne $prior) { foreach ($p in (ConvertTo-Dict $prior).GetEnumerator()) { $epBySerial[[string]$p.Key] = [int]$p.Value } }
    $syncCreated = @{}   # endpoints the Sync itself created (tagNumber ScalePad) - no RMM keeps their list
    foreach ($e in @(Get-CrAll "/v2/odata/endpoint?`$filter=companyId eq $companyId&`$select=companyEndpointId,serialNumber,tagNumber")) {
        $s = Normalize-Serial (Get-P $e 'serialNumber'); if ($s) { $epBySerial[$s] = [int](Get-P $e 'companyEndpointId') }
        if ([string](Get-P $e 'tagNumber' '') -eq 'ScalePad') { $syncCreated[[int](Get-P $e 'companyEndpointId')] = $true }
    }

    # What each endpoint already has. The RMM names software differently from ScalePad
    # ("Google Chrome / Google LLC" vs "Google Chrome / Google") and re-syncs its list, so:
    #  - a device that already has software in CloudRadial is left alone (skipDevicesWithSoftware), and
    #  - otherwise matching is by endpoint + normalized product name, ignoring publisher and version.
    function Get-AppKey { param([string]$n)
        $t = $n.ToLowerInvariant() -replace '\(.*?\)', ' ' -replace '\b(x64|x86|64-bit|32-bit|en-us|en-gb)\b', ' ' -replace '\b\d+(\.\d+)+\b', ' ' -replace '[^a-z0-9]+', ' '
        return ($t -replace '\s+', ' ').Trim()
    }
    $appsByEp = @{}
    function Add-ExistingApp { param($eid, $name) if (-not $appsByEp.ContainsKey([int]$eid)) { $appsByEp[[int]$eid] = New-Object System.Collections.Generic.HashSet[string] }; $k = Get-AppKey ([string]$name); if ($k) { $null = $appsByEp[[int]$eid].Add($k) } }
    try { foreach ($a in @(Get-CrAll "/v2/odata/endpointapplication?`$filter=companyId eq $companyId&`$select=endpointId,name")) { Add-ExistingApp (Get-P $a 'endpointId' 0) (Get-P $a 'name') } }
    catch { Warn "Couldn't read existing software by company; reading per device. $($_.Exception.Message)" }

    $installs = @(Get-SpAll '/lifecycle-manager/v1/assets/software' @{ 'filter[client.id]' = "eq:$spClientId" } -PageSize 100)
    # The company-wide read has come back empty on a portal that had software, so confirm per device.
    $unreadable = 0
    $touch = @($installs | ForEach-Object { Normalize-Serial (Get-P $_ 'hardware_asset.serial_number') } | Where-Object { $_ -and $epBySerial.ContainsKey($_) } | Sort-Object -Unique)
    foreach ($sn in $touch) {
        $eid = $epBySerial[$sn]
        if ($appsByEp.ContainsKey([int]$eid)) { continue }
        try { foreach ($a in @(Get-CrAll "/v2/odata/endpointapplication?`$filter=endpointId eq $eid&`$select=endpointId,name")) { Add-ExistingApp $eid (Get-P $a 'name') } }
        catch {
            # Unknown is not empty: skip this device this run rather than risk writing a second copy.
            Add-ExistingApp $eid '__unreadable__'
            $unreadable++
            if ($unreadable -le 5) { Warn "Couldn't read existing software for endpoint $eid ($sn), so its software was left alone this run: $($_.Exception.Message)" }
        }
    }
    if ($unreadable -gt 5) { Warn "$unreadable devices' software couldn't be read and was left alone this run." }
    $skipWithSoftware = -not ([string](Get-P $settings 'skipDevicesWithSoftware' 'true') -match '^(false|no|0)$')
    $hadSoftware = @{}
    foreach ($k in $appsByEp.Keys) { if ($appsByEp[$k].Count -gt 0) { $hadSoftware[[int]$k] = $true } }
    $skippedDevices = New-Object System.Collections.Generic.HashSet[string]

    $counts.scalePadInstalls = $installs.Count
    $cap = [int](Get-P $settings 'maxSoftwareWrites' 2000)
    $devicesSeen = New-Object System.Collections.Generic.HashSet[string]
    $sample = New-Object System.Collections.ArrayList
    $writeCount = 0
    foreach ($i in $installs) {
        $serial = Normalize-Serial (Get-P $i 'hardware_asset.serial_number')
        if (-not $serial -or -not $epBySerial.ContainsKey($serial)) { $counts.noDevice++; $null = $noDevice.Add([string](Get-P $i 'hardware_asset.name' $serial)); continue }
        $epId = [int]$epBySerial[$serial]
        $null = $devicesSeen.Add($serial)
        $name = [string](Get-P $i 'product.name' '')
        if (Test-Blank $name) { continue }
        $isUnreadable = $appsByEp.ContainsKey($epId) -and $appsByEp[$epId].Contains('unreadable')
        if ($isUnreadable -or ($skipWithSoftware -and $hadSoftware.ContainsKey($epId) -and -not $syncCreated.ContainsKey($epId))) { $counts.alreadyPresent++; $null = $skippedDevices.Add($serial); continue }
        $key = Get-AppKey $name
        if (-not $appsByEp.ContainsKey($epId)) { $appsByEp[$epId] = New-Object System.Collections.Generic.HashSet[string] }
        if ($appsByEp[$epId].Contains($key)) { $counts.alreadyPresent++; continue }
        $null = $appsByEp[$epId].Add($key)
        $publisher = [string](Get-P $i 'publisher.name' '')
        if (Test-Blank $publisher) { $publisher = 'Unknown' }
        $counts.toCreate++
        if ($writeCount -ge $cap) { $counts.overCap++; continue }
        $display = [string](Get-P $i 'version.display' '')
        $v = Split-Version $display
        $body = [ordered]@{ companyId = $companyId; endpointId = $epId; name = $name; publisher = $publisher; display = $display; major = $v[0]; minor = $v[1]; version = $v[2]; category = [string](Get-P $i 'product.category' ''); comments = 'Added by ScalePad to CloudRadial Sync' }
        if ($sample.Count -lt 25) { $null = $sample.Add(@{ device = [string](Get-P $i 'hardware_asset.name'); product = $name; publisher = $publisher; version = $display }) }
        if ($apply) {
            try { $null = Invoke-Cr -Method POST -Path '/v2/endpointapplication' -Body $body; $counts.created++ }
            catch { $counts.errors++; if ($counts.errors -le 10) { Warn "Software create failed ($name on $serial): $($_.Exception.Message)" } }
        }
        $writeCount++
    }
    $counts.devicesSkippedHaveSoftware = $skippedDevices.Count
    if ($skippedDevices.Count -gt 0) { Warn "$($skippedDevices.Count) device(s) already have software in CloudRadial (usually from the RMM), so ScalePad's list wasn't added to them. Set skipDevicesWithSoftware to false to add missing items anyway." }
    $counts.devicesWithSoftware = $devicesSeen.Count
    $counts.scalePadDevices = @($installs | ForEach-Object { Normalize-Serial (Get-P $_ 'hardware_asset.serial_number') } | Where-Object { $_ } | Sort-Object -Unique).Count
    if ($counts.overCap -gt 0) { Warn "$($counts.overCap) software records were left for the next run (maxSoftwareWrites = $cap). Re-run to continue; existing records are skipped." }
    if ($noDevice.Count -gt 0 -and -not $apply) { Warn "Software for $($noDevice.Count) device(s) has no CloudRadial endpoint yet. In plan mode, devices the devices step would create aren't counted; run apply (devices then software) to include them." }
    # --- Diagnostics: how CloudRadial answers the existing-software reads (for troubleshooting duplicates) ---
    $diag = [ordered]@{ companyReadApps = 0; endpointsWithApps = $appsByEp.Keys.Count }
    foreach ($k in $appsByEp.Keys) { $diag.companyReadApps += $appsByEp[$k].Count }
    function Get-Probe { param([string]$label, [string]$path)
        try { $r = Invoke-Cr -Method GET -Path $path; $v = @(Get-P $r 'value' @()); return [ordered]@{ query = $label; rows = $v.Count; first = $(if ($v.Count) { ($v[0] | ConvertTo-Json -Depth 3 -Compress) } else { '' }) } }
        catch { return [ordered]@{ query = $label; error = $_.Exception.Message } }
    }
    $probeEp = if ($touch.Count) { [int]$epBySerial[$touch[0]] } else { 0 }
    $diag.probeEndpoint = [ordered]@{ serial = $(if ($touch.Count) { $touch[0] } else { '' }); companyEndpointId = $probeEp }
    $diag.probes = @(
        (Get-Probe 'company, top 1, all fields' "/v2/odata/endpointapplication?`$filter=companyId eq $companyId&`$top=1"),
        (Get-Probe 'no filter, top 1' "/v2/odata/endpointapplication?`$top=1"),
        (Get-Probe 'endpointId = companyEndpointId' "/v2/odata/endpointapplication?`$filter=endpointId eq $probeEp&`$top=3"),
        (Get-Probe 'endpoint by id, all fields' "/v2/odata/endpoint?`$filter=companyEndpointId eq $probeEp&`$top=1"),
        # SaaS: how does CloudRadial store software that isn't on a device?
        (Get-Probe 'SaaS? no device (endpointId eq 0)' "/v2/odata/endpointapplication?`$filter=companyId eq $companyId and endpointId eq 0&`$top=5"),
        (Get-Probe 'SaaS? no device (endpointId eq null)' "/v2/odata/endpointapplication?`$filter=companyId eq $companyId and endpointId eq null&`$top=5"),
        (Get-Probe 'cloud storage apps (isCloudStorage)' "/v2/odata/endpointapplication?`$filter=companyId eq $companyId and isCloudStorage eq true&`$top=5")
    )
    $results[$phase] = [ordered]@{ ran = $true; counts = $counts; diagnostics = $diag; sample = @($sample); devicesWithoutEndpoint = @($noDevice | Select-Object -First 50) }
}

$ctx.results = $results
$ctx.warnings = @(@(Get-P $ctx 'warnings' @()) + @($warnings))
$c = $counts
Set-NodeOutput @{ status = 'ok'; message = "Software: $($c.scalePadInstalls) installs in ScalePad, $($c.alreadyPresent) already in CloudRadial$(if ($c.devicesSkippedHaveSoftware) { " ($($c.devicesSkippedHaveSoftware) devices already have software)" }), $(if ($apply) { "$($c.created) created" } else { "$($c.toCreate) to create" }), $($c.noDevice) on devices not in CloudRadial, $($c.errors) errors."; ctx = $ctx }
