#{{COMMON}}
# =====================================================================
# Step 2 - Devices: workstations, servers and VMs (enrich or create)
# =====================================================================
$phase = 'devices'
$results = ConvertTo-Dict (Get-P $ctx 'results')
$settings = Get-P $ctx 'settings'
$companyId = [int](Get-P $ctx 'companyId')
$spClientId = [string](Get-P $ctx 'scalePadClientId')
$serialMap = [ordered]@{}   # serial -> companyEndpointId (used by the software step)

function Get-Platform { param($os, $manufacturer)
    $o = ([string]$os).ToLowerInvariant(); $mf = ([string]$manufacturer).ToLowerInvariant()
    if ($o -match 'mac|os x|darwin') { return 1 }
    if ($o -match 'linux|ubuntu|debian|centos|red hat|rhel') { return 2 }
    if ($o -match 'windows') { return 0 }
    if ($mf -match 'apple') { return 1 }
    return 0
}
# OData returns enclosure as the enum name ("Desktop", "Server") - accept a name or a number.
function Test-ServerEnclosure { param($v) $e = [string]$v; if ($e -match '^\d+$') { return ([int]$e -eq 80) }; return ($e -match '(?i)server') }
function Get-Enclosure { param($type, $model)
    switch ($type) { 'SERVER' { return 80 } 'VIRTUAL' { return 30 } }
    if (([string]$model) -match '(?i)laptop|notebook|book|thinkpad|latitude|elitebook|probook|zbook|surface|xps|inspiron \d{2}|vostro \d{2}|yoga|ideapad|travelmate|spectre|envy x|dragonfly') { return 10 }
    return 20
}

# ScalePad sometimes types a server as WORKSTATION; a Windows Server OS makes it a server here.
$ServerOsPattern = '(?i)windows\s*server|hyper-v\s*server'
$counts = [ordered]@{ scalePadDevices = 0; inScope = 0; serversByOs = 0; matched = 0; toEnrich = 0; toCreate = 0; enriched = 0; created = 0; unchanged = 0; skipped = 0; errors = 0 }
$planned = New-Object System.Collections.ArrayList
$skipped = New-Object System.Collections.ArrayList

if ((Get-P $ctx 'phases' @()) -notcontains $phase) {
    $results[$phase] = [ordered]@{ ran = $false }
}
else {
    $hw = @(Get-SpAll '/core/v1/assets/hardware' @{ 'filter[client.id]' = "eq:$spClientId" })
    $life = @(Get-SpAll '/lifecycle-manager/v1/assets/hardware/lifecycles' @{ 'filter[client_id]' = "eq:$spClientId" })
    $lifeBySerial = @{}
    foreach ($l in $life) { $s = Normalize-Serial (Get-P $l 'serial_number'); if ($s) { $lifeBySerial[$s] = $l } }
    $counts.scalePadDevices = $hw.Count

    $crEps = @(Get-CrAll "/v2/odata/endpoint?`$filter=companyId eq $companyId&`$select=companyEndpointId,serialNumber,name,manufacturer,model,expirationDate,manufacturedDate,os,cpu,memory,isServer,isVirtual,enclosure")
    $crBySerial = @{}
    foreach ($e in $crEps) { $s = Normalize-Serial (Get-P $e 'serialNumber'); if ($s -and -not $crBySerial.ContainsKey($s)) { $crBySerial[$s] = $e } }

    $types = @(Get-P $settings 'deviceTypes' @('WORKSTATION', 'SERVER', 'VIRTUAL'))
    $today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddT00:00:00Z')
    foreach ($d in $hw) {
        $type = ([string](Get-P $d 'type' '')).ToUpperInvariant()
        $name = [string](Get-P $d 'name' '')
        $serial = Normalize-Serial (Get-P $d 'serial_number')
        if ($type -notin $types) { $counts.skipped++; $null = $skipped.Add(@{ device = $name; serial = $serial; reason = $(if ((Get-P $ctx 'phases' @()) -contains 'assets') { "type $type - kept as a flexible asset (assets phase)" } else { "type $type is not synced (deviceTypes)" }) }); continue }
        $counts.inScope++
        if (-not $serial) { $counts.skipped++; $null = $skipped.Add(@{ device = $name; serial = ''; reason = $(if ((Get-P $ctx 'phases' @()) -contains 'assets' -and (Get-P $settings 'includeNoSerialDevices' $true)) { 'no serial number - kept as a flexible asset (assets phase)' } else { 'no serial number' }) }); continue }

        $l = $lifeBySerial[$serial]
        $mf = [string](Get-P $d 'manufacturer.name' (Get-P $l 'manufacturer' ''))
        $model = [string](Get-P $d 'model.description' (Get-P $d 'model.number' (Get-P $l 'model' '')))
        $os = [string](Get-P $d 'software.operating_system' '')
        $cpu = [string](Get-P $d 'configuration.cpu.name' '')
        $ram = Get-P $d 'configuration.ram_bytes'
        $warranty = ConvertTo-IsoDate (Get-P $l 'warranty_expiry_date')
        $purchase = ConvertTo-IsoDate (Get-P $l 'purchase_date')
        $av = [string](Get-P $d 'software.antivirus_info.status' '')
        $existing = $crBySerial[$serial]
        $serverOs = ($os -match $ServerOsPattern) -or ([string](Get-P $existing 'os' '') -match $ServerOsPattern)
        $isServer = ($type -eq 'SERVER') -or $serverOs
        $encType = if ($serverOs -and $type -ne 'VIRTUAL') { 'SERVER' } else { $type }
        if ($serverOs -and $type -ne 'SERVER') { $counts.serversByOs++ }

        if ($null -ne $existing) {
            $counts.matched++
            $epId = [int](Get-P $existing 'companyEndpointId')
            $serialMap[$serial] = $epId
            $fields = @{}
            if ((Test-Blank (Get-P $existing 'manufacturer')) -and $mf) { $fields.manufacturer = $mf }
            if ((Test-Blank (Get-P $existing 'model')) -and $model) { $fields.model = $model }
            if (-not (Test-Blank $warranty)) {
                $cur = Get-P $existing 'expirationDate'
                if (Test-Blank $cur) { $fields.expirationDate = $warranty }
                elseif ((Format-Day $cur) -ne (Format-Day $warranty)) {
                    if (Get-P $settings 'overwriteWarranty' $false) { $fields.expirationDate = $warranty }
                    else { Warn "Warranty differs for $name ($serial): CloudRadial $(Format-Day $cur), ScalePad $(Format-Day $warranty). Left as is (overwriteWarranty is off)." }
                }
            }
            if ((Test-Blank (Get-P $existing 'manufacturedDate')) -and -not (Test-Blank $purchase)) { $fields.manufacturedDate = $purchase }
            if ((Test-Blank (Get-P $existing 'os')) -and $os) { $fields.os = $os }
            if ((Test-Blank (Get-P $existing 'cpu')) -and $cpu) { $fields.cpu = $cpu }
            if (((Test-Blank (Get-P $existing 'memory')) -or [double](Get-P $existing 'memory' 0) -eq 0) -and $ram) { $fields.memory = [int64]$ram }
            # Server typing is corrected, not just filled: a desktop record running Windows Server is a server.
            if ($isServer -and (Get-P $existing 'isServer' $false) -ne $true) { $fields.isServer = $true }
            if ($isServer -and $encType -eq 'SERVER' -and (Get-P $existing 'isVirtual' $false) -ne $true -and -not (Test-ServerEnclosure (Get-P $existing 'enclosure'))) { $fields.enclosure = 80 }
            if ($fields.Count -eq 0) { $counts.unchanged++; continue }
            $counts.toEnrich++
            $null = $planned.Add(@{ action = 'enrich'; device = $name; serial = $serial; companyEndpointId = $epId; fields = $fields })
            if ($apply) {
                try { $null = Invoke-Cr -Method PATCH -Path "/v2/endpoint/id/$epId" -Body (New-PatchOps $fields); $counts.enriched++ }
                catch { $counts.errors++; Warn "Enrich failed for $name ($serial): $($_.Exception.Message)" }
            }
            continue
        }

        if (-not (Get-P $settings 'createMissingDevices' $true)) { $counts.skipped++; $null = $skipped.Add(@{ device = $name; serial = $serial; reason = 'not in CloudRadial (createMissingDevices is off)' }); continue }
        $body = [ordered]@{
            companyId = $companyId; name = $(if ($name) { $name } else { $serial }); machineName = $name
            serialNumber = [string](Get-P $d 'serial_number'); manufacturer = $mf; model = $model
            platformType = (Get-Platform $os $mf); enclosure = (Get-Enclosure $encType $model)
            isServer = $isServer; isVirtual = ($type -eq 'VIRTUAL')
            os = $os; cpu = $cpu; tagNumber = 'ScalePad'
            isWindowsDefenderRunning = ($av -eq 'RUNNING' -and $os -match '(?i)windows')
            lastCheckIn = $today; lastOSUpdate = $today
        }
        foreach ($k in @($body.Keys)) { if ($body[$k] -is [string] -and [string]::IsNullOrWhiteSpace($body[$k])) { $body.Remove($k) } }
        if ($ram) { $body.memory = [int64]$ram }
        if (-not (Test-Blank $warranty)) { $body.expirationDate = $warranty }
        if (-not (Test-Blank $purchase)) { $body.manufacturedDate = $purchase }
        $counts.toCreate++
        $null = $planned.Add(@{ action = 'create'; device = $name; serial = $serial; type = $(if ($encType -ne $type) { "$type (server by OS)" } else { $type }); enclosure = $body.enclosure; platformType = $body.platformType })
        if ($apply) {
            try {
                $resp = Invoke-Cr -Method POST -Path '/v2/endpoint' -Body $body
                $newId = Get-P $resp 'companyEndpointId' (Get-P $resp 'id')
                if ($newId) { $serialMap[$serial] = [int]$newId }
                $counts.created++
            }
            catch { $counts.errors++; Warn "Create failed for $name ($serial): $($_.Exception.Message)" }
        }
    }
    $results[$phase] = [ordered]@{
        ran = $true; counts = $counts
        planned = @($planned | Select-Object -First 150); plannedTotal = $planned.Count
        skipped = @($skipped | Select-Object -First 100); skippedTotal = $skipped.Count
        serialMap = $serialMap
    }
}

$ctx.results = $results
$ctx.warnings = @(@(Get-P $ctx 'warnings' @()) + @($warnings))
$c = $counts
Set-NodeOutput @{ status = 'ok'; message = "Devices: $($c.inScope) in scope, $($c.matched) matched, $(if ($apply) { "$($c.enriched) enriched, $($c.created) created" } else { "$($c.toEnrich) to enrich, $($c.toCreate) to create" }), $($c.skipped) skipped, $($c.errors) errors.$(if ($c.serversByOs) { " $($c.serversByOs) typed as servers from a Windows Server OS." })"; ctx = $ctx }
