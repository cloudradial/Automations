# === Step 1: Find offline devices ===
# Reads the run input (a Routine sends none, so every setting has a default), reads every Datto RMM site and
# its devices, keeps the devices that have been offline longer than the threshold for their category, matches
# each site to a PSA company, and finds this workflow's open ticket for each company. Changes nothing in
# Datto RMM or the PSA. The next step opens or updates the tickets (or, in a preview, only lists them).
$ErrorActionPreference = 'Stop'

$raw = Get-NodeInput
if ($raw -is [string]) {
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = $null }
    else { try { $raw = $raw | ConvertFrom-Json } catch { $raw = 'bad-json' } }
}
$wrapped = Get-PsaProp $raw 'trigger'; if ($null -ne $wrapped) { $raw = $wrapped }

$odsOut = [ordered]@{ status = 'error'; message = ''; preview = $false; settings = $null; counts = $null; plan = @(); unmatchedSites = @(); warnings = @() }
function Stop-OdsRun {
    param([string]$Msg)
    $odsOut.status = 'error'; $odsOut.message = $Msg
    $odsOut.warnings = @(Get-OdsWarnings $odsOut.warnings)
    Set-NodeOutput $odsOut
    throw $Msg
}
if ($raw -is [string] -and $raw -eq 'bad-json') { Stop-OdsRun 'The run input is not valid JSON. Leave it empty to use the defaults.' }

# The first non-blank input among the names (camelCase or snake_case). Values starting with @ are unfilled tokens.
function Get-OdsInput {
    param([string[]]$Names, $Default)
    foreach ($n in $Names) {
        $v = Get-PsaProp $raw $n
        if ($null -eq $v) { continue }
        if ($v -is [string]) { $v = $v.Trim(); if (-not $v -or $v.StartsWith('@')) { continue } }
        return $v
    }
    return $Default
}
function ConvertTo-OdsBool {
    param($Value, [string]$Name)
    if ($Value -is [bool]) { return $Value }
    $s = ([string]$Value).Trim().ToLowerInvariant()
    if ($s -in @('true', 'yes', 'y', '1')) { return $true }
    if ($s -in @('false', 'no', 'n', '0', '')) { return $false }
    throw "$Name must be true or false, not '$Value'."
}
function ConvertTo-OdsInt {
    param($Value, [string]$Name, [int]$Min, [int]$Max)
    $n = 0
    if (-not [int]::TryParse(([string]$Value).Trim(), [ref]$n) -or $n -lt $Min -or $n -gt $Max) { throw "$Name must be a whole number from $Min to $Max, not '$Value'." }
    return $n
}
# A list input: a JSON list, or text split on commas, semicolons or new lines.
function ConvertTo-OdsNames {
    param($Value)
    if ($null -eq $Value) { return @() }
    $items = if ($Value -is [array]) { @($Value) } else { $s = ([string]$Value).Trim(); if ($s.StartsWith('[')) { try { @($s | ConvertFrom-Json) } catch { throw "This list isn't valid JSON: $s" } } else { @($s -split '[,;\r\n]+') } }
    return @($items | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
}
$OdsCategoryNames = @{
    workstations = 'workstations'; workstation = 'workstations'; desktops = 'workstations'; desktop = 'workstations'
    laptops = 'laptops'; laptop = 'laptops'; notebooks = 'laptops'
    servers = 'servers'; server = 'servers'
    mobile = 'mobile'; mobiles = 'mobile'; phones = 'mobile'
    printers = 'printers'; printer = 'printers'
    network = 'network'; 'network devices' = 'network'; 'network device' = 'network'
    other = 'other'
}

# ---- settings (bad input fails closed: nothing is read or written) ----
$settings = @{}
try {
    $settings.preview = ConvertTo-OdsBool (Get-OdsInput @('preview', 'dryRun', 'dry_run') $false) 'preview'
    $settings.offlineDays = ConvertTo-OdsInt (Get-OdsInput @('offlineDays', 'offline_days') 7) 'offlineDays' 1 3650
    $settings.serverOfflineHours = ConvertTo-OdsInt (Get-OdsInput @('serverOfflineHours', 'server_offline_hours') 4) 'serverOfflineHours' 1 8760
    $cats = @(ConvertTo-OdsNames (Get-OdsInput @('includeCategories', 'include_categories') 'workstations, laptops, servers'))
    $settings.includeCategories = @(foreach ($cn in $cats) { $k = $cn.ToLowerInvariant(); if (-not $OdsCategoryNames.ContainsKey($k)) { throw "includeCategories has '$cn'. Use any of: workstations, laptops, servers, mobile, printers, network, other." }; $OdsCategoryNames[$k] }) | Select-Object -Unique
    if (-not @($settings.includeCategories).Count) { throw 'includeCategories needs at least one category.' }
    $settings.includeCategories = @($settings.includeCategories)
    $settings.ignoreSites = @(ConvertTo-OdsNames (Get-OdsInput @('ignoreSites', 'ignore_sites') $null))
    $settings.priority = Get-PsaPriorityHint ([string](Get-OdsInput @('priority') 'medium'))
    $settings.serverPriority = Get-PsaPriorityHint ([string](Get-OdsInput @('serverPriority', 'server_priority') 'high'))
    $settings.queue = [string](Get-OdsInput @('queue', 'psa_queue') '')
    # companyMap: { "<Datto site name or uid>": "<PSA company id or exact name>" }
    $mapIn = Get-OdsInput @('companyMap', 'company_map') $null
    $settings.companyMap = @{}
    if ($null -ne $mapIn) {
        $mapObj = $mapIn
        if ($mapIn -is [string]) { try { $mapObj = $mapIn | ConvertFrom-Json } catch { throw 'companyMap must be a JSON object, for example {"Contoso HQ": "42"}.' } }
        if ($mapObj -is [array] -or $mapObj -is [string] -or $mapObj -is [ValueType]) { throw 'companyMap must be a JSON object, for example {"Contoso HQ": "42"}.' }
        foreach ($kv in @((ConvertTo-OdsHash $mapObj).GetEnumerator())) {
            $mv = ([string]$kv.Value).Trim()
            if (-not $mv) { throw "companyMap gives no company for the site '$($kv.Key)'." }
            $settings.companyMap[([string]$kv.Key).Trim().ToLowerInvariant()] = $mv
        }
    }
    $psaType = Get-PsaType ([string](Get-OdsInput @('psa') ''))
    if (-not $psaType) { throw 'No PSA is set up. Add the PSA-Type secret (connectwise, autotask, halopsa, kaseyabms, syncro or zendesk) to the runner Key Vault.' }
    $settings.psa = $psaType
}
catch { Stop-OdsRun ([string]$_.Exception.Message) }
$odsNow = (Get-Date).ToUniversalTime()
$settings.today = $odsNow.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
$settings.checkedText = $odsNow.ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) + ' UTC'
$odsOut.preview = $settings.preview
$odsOut.settings = $settings

$counts = [ordered]@{ sites = 0; sitesSkipped = 0; devicesChecked = 0; offline = 0; offlineServers = 0; suspendedOrDeleted = 0; noDeviceType = 0; noLastSeen = 0; unmatchedSites = 0 }
$odsOut.counts = $counts
$warnings = New-Object System.Collections.ArrayList

# ---- connect (PSA first: its secrets are checked without a call, so a missing one stops before Datto is read) ----
try { $null = Connect-Psa $settings.psa } catch { Stop-OdsRun ([string]$_.Exception.Message) }
$psaName = $PsaState.Names[$settings.psa]
try { $null = Connect-Datto } catch { Stop-OdsRun ([string]$_.Exception.Message) }

# ---- read Datto RMM ----
# Unverified: Datto's placeholder site names (the RMM Agent skips the same three).
$placeholderSites = @('deleted devices', 'managed', 'ondemand')
$sites = @()
try { $sites = @(Get-DattoSites) } catch { Stop-OdsRun "Couldn't list the Datto RMM sites: $($_.Exception.Message)" }
$ignore = @($settings.ignoreSites | ForEach-Object { $_.ToLowerInvariant() })
$wanted = @($settings.includeCategories)
$siteRows = New-Object System.Collections.ArrayList
foreach ($s in $sites) {
    $sName = ([string](Get-DattoProp $s 'name')).Trim(); $sUid = [string](Get-DattoProp $s 'uid')
    if (-not $sUid) { continue }
    $lname = $sName.ToLowerInvariant()
    $mapped = $settings.companyMap.ContainsKey($lname) -or $settings.companyMap.ContainsKey($sUid.ToLowerInvariant())
    if ($ignore -contains $lname -or $ignore -contains $sUid.ToLowerInvariant()) { $counts.sitesSkipped++; continue }
    # Datto's own placeholder sites never belong to a client, unless companyMap names them.
    if ($placeholderSites -contains $lname -and -not $mapped) { $counts.sitesSkipped++; continue }
    $counts.sites++
    $devices = @()
    try { $devices = @(Get-DattoSiteDevices $sUid) } catch { Stop-OdsRun "Couldn't read the devices at the Datto RMM site '$sName': $($_.Exception.Message)" }
    $offline = New-Object System.Collections.ArrayList
    $seen = @{}   # hostname (lower) -> online, recent, suspended
    foreach ($d in $devices) {
        $host0 = ([string](Get-DattoProp $d 'hostname')).Trim()
        if (-not $host0) { $host0 = [string](Get-DattoProp $d 'uid') }
        $hk = $host0.ToLowerInvariant()
        # Unverified: the suspended and deleted flags on a device record.
        if ((Get-DattoProp $d 'suspended') -eq $true -or (Get-DattoProp $d 'deleted') -eq $true) { $counts.suspendedOrDeleted++; $seen[$hk] = 'suspended'; continue }
        $cat = Get-DattoDeviceCategory $d
        if (-not $cat.key) { $counts.noDeviceType++; continue }
        if ($wanted -notcontains $cat.key) { continue }
        $counts.devicesChecked++
        $online = Get-DattoProp $d 'online'
        if ($online -eq $true) { $seen[$hk] = 'online'; continue }
        $last = ConvertFrom-DattoTime (Get-DattoProp $d 'lastSeen')
        if ($null -eq $last) { $counts.noLastSeen++; continue }
        $hours = ($odsNow - $last).TotalHours
        $isServer = $cat.key -eq 'servers'
        $limit = $(if ($isServer) { [double]$settings.serverOfflineHours } else { [double]$settings.offlineDays * 24 })
        if ($hours -lt $limit) { $seen[$hk] = 'recent'; continue }
        $seen[$hk] = 'offline'
        $null = $offline.Add(@{
                uid = [string](Get-DattoProp $d 'uid'); hostname = $host0; category = $cat.key; typeLabel = $cat.label; isServer = $isServer
                os = ([string](Get-DattoProp $d 'operatingSystem')).Trim(); siteName = $sName
                lastSeenText = $last.ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) + ' UTC'
                hoursOffline = [Math]::Round($hours, 1); isNew = $true
            })
    }
    $counts.offline += $offline.Count
    $counts.offlineServers += @($offline | Where-Object { $_.isServer }).Count
    $null = $siteRows.Add(@{ uid = $sUid; name = $sName; offline = @($offline); seen = $seen })
}
if ($counts.noDeviceType) { $null = $warnings.Add("$(Get-OdsPlural $counts.noDeviceType 'device had' 'devices had') no device type in Datto RMM, so they were not checked.") }
if ($counts.noLastSeen) { $null = $warnings.Add("$(Get-OdsPlural $counts.noLastSeen 'offline device has' 'offline devices have') no last seen date in Datto RMM, so they were not ticketed.") }

# ---- match each site to a PSA company (companyMap first, then one exact name match; never a guess) ----
$companyCache = @{}
function Resolve-OdsCompany {
    param([string]$Text)
    if ($Text -match '^\d+$') { return @{ id = $Text; name = ''; reason = '' } }
    $key = $Text.ToLowerInvariant()
    if (-not $companyCache.ContainsKey($key)) {
        $hits = @(Find-PsaCompany -Name $Text | Where-Object { $_.exact })
        $companyCache[$key] = $(if ($hits.Count -eq 1) { @{ id = [string]$hits[0].id; name = [string]$hits[0].name; reason = '' } }
            elseif ($hits.Count -gt 1) { @{ id = ''; name = ''; reason = "$psaName has $($hits.Count) companies named '$Text'" } }
            else { @{ id = ''; name = ''; reason = "$psaName has no company named exactly '$Text'" } })
    }
    return $companyCache[$key]
}
$companies = [ordered]@{}
$unmatched = New-Object System.Collections.ArrayList
foreach ($sr in $siteRows) {
    $mapKey = $(if ($settings.companyMap.ContainsKey($sr.name.ToLowerInvariant())) { $sr.name.ToLowerInvariant() } elseif ($settings.companyMap.ContainsKey($sr.uid.ToLowerInvariant())) { $sr.uid.ToLowerInvariant() } else { '' })
    $m = $null
    try { $m = $(if ($mapKey) { Resolve-OdsCompany $settings.companyMap[$mapKey] } else { Resolve-OdsCompany $sr.name }) }
    catch { $m = @{ id = ''; name = ''; reason = "the company lookup failed: $($_.Exception.Message)" } }
    if (-not $m.id) {
        $why = $(if ($mapKey) { "$($m.reason) (from companyMap)" } else { $m.reason })
        $null = $unmatched.Add([ordered]@{ site = $sr.name; offline = @($sr.offline).Count; reason = $why })
        continue
    }
    if (-not $companies.Contains($m.id)) { $companies[$m.id] = @{ companyId = $m.id; companyName = $(if ($m.name) { $m.name } else { $sr.name }); sites = @(); devices = (New-Object System.Collections.ArrayList); seen = @{} } }
    $co = $companies[$m.id]
    $co.sites += $sr.name
    foreach ($d in $sr.offline) { $null = $co.devices.Add($d) }
    foreach ($k in $sr.seen.Keys) { if (-not $co.seen.ContainsKey($k) -or $sr.seen[$k] -eq 'offline') { $co.seen[$k] = $sr.seen[$k] } }
}
$counts.unmatchedSites = $unmatched.Count
foreach ($u in @($unmatched | Where-Object { $_.offline -gt 0 })) { $null = $warnings.Add("The Datto RMM site '$($u.site)' has $(Get-OdsPlural $u.offline 'offline device' 'offline devices') but no ticket was opened: $($u.reason). Add it to companyMap.") }
$quiet = @($unmatched | Where-Object { $_.offline -eq 0 }).Count
if ($quiet) { $null = $warnings.Add("$(Get-OdsPlural $quiet 'other Datto RMM site has' 'other Datto RMM sites have') no matching $psaName company. Nothing is offline there today; add them to companyMap so they are covered later.") }

# ---- this workflow's open tickets (one search for all companies, then per company if that search was cut short) ----
$openBy = @{}
$searchTruncated = $false
try {
    foreach ($t in @(Find-PsaTickets -Open -Text 'Offline devices' -Max 500 -Order newest)) {
        if (-not (Test-OdsSummary $t.summary) -or -not $t.companyId) { continue }
        if (-not $openBy.ContainsKey($t.companyId)) { $openBy[$t.companyId] = New-Object System.Collections.ArrayList }
        $null = $openBy[$t.companyId].Add($t)
    }
    $searchTruncated = [bool]$PsaState.FindTruncated
}
catch { Stop-OdsRun "Couldn't search $psaName for open Offline devices tickets, so nothing was changed: $($_.Exception.Message)" }

$plan = New-Object System.Collections.ArrayList
foreach ($co in $companies.Values) {
    $devs = @($co.devices | Sort-Object -Property @{ Expression = { -not $_.isServer } }, @{ Expression = { -[double]$_.hoursOffline } })
    $item = [ordered]@{ companyId = $co.companyId; companyName = $co.companyName; sites = @($co.sites | Select-Object -Unique); devices = @($devs); recovered = @(); action = 'none'; ticketId = ''; ticketUrl = ''; alreadyToday = $false; error = '' }
    try {
        $rows = @(); if ($openBy.ContainsKey($co.companyId)) { $rows = @($openBy[$co.companyId]) }
        if (-not $rows.Count -and $searchTruncated -and $devs.Count) {
            $rows = @(Find-PsaTickets -Open -CompanyId $co.companyId -Text 'Offline devices' -Max 50 -Order newest | Where-Object { Test-OdsSummary $_.summary })
        }
        if (-not $rows.Count) {
            if ($devs.Count) { $item.action = 'create'; $null = $plan.Add($item) }
            continue
        }
        $tk = $rows[0]
        if ($rows.Count -gt 1) { $null = $warnings.Add("$($co.companyName) has $($rows.Count) open Offline devices tickets. Only the newest, #$($tk.number), is updated; close or merge the others.") }
        $item.ticketId = [string]$tk.id; $item.ticketUrl = [string]$tk.url
        $notes = @(Get-PsaTicketNotes -Id $tk.id -TextOnly)
        $marked = @($notes | Where-Object { Test-OdsMarkerIn $_.text })
        $item.alreadyToday = [bool](Test-PsaNoteMarker -Id $tk.id -Marker (Get-OdsMarker $settings.today) -Notes $notes)
        $prev = $null
        for ($i = $marked.Count - 1; $i -ge 0 -and $null -eq $prev; $i--) { $prev = Get-OdsListedHosts $marked[$i].text }
        if ($null -eq $prev) { $prev = Get-OdsListedHosts $tk.description }
        $prevKeys = @(@($prev) | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
        $nowKeys = @($devs | ForEach-Object { $_.hostname.ToLowerInvariant() })
        foreach ($d in $devs) { $d.isNew = ($null -ne $prev -and $prevKeys -notcontains $d.hostname.ToLowerInvariant()) }
        $item.recovered = @(@($prev) | Where-Object { $_ -and $nowKeys -notcontains $_.ToLowerInvariant() } | ForEach-Object {
                $hn = [string]$_
                $st = $(if ($co.seen.ContainsKey($hn.ToLowerInvariant())) { $co.seen[$hn.ToLowerInvariant()] } else { '' })
                $why = switch ($st) { 'online' { 'is back online in Datto RMM' } 'recent' { 'checked in to Datto RMM recently' } 'suspended' { 'is suspended or deleted in Datto RMM' } default { 'is no longer in Datto RMM' } }
                [ordered]@{ hostname = $hn; reason = $why }
            })
        # A ticket with no device list yet (opened by hand, or its list line was edited away) gets the current list once.
        $changed = (@($devs | Where-Object { $_.isNew }).Count -gt 0) -or ($item.recovered.Count -gt 0) -or ($null -eq $prev -and $devs.Count -gt 0)
        $item.action = $(if ($item.alreadyToday) { 'unchanged' } elseif ($changed) { 'update' } else { 'unchanged' })
        $null = $plan.Add($item)
    }
    catch { $item.action = 'failed'; $item.error = [string]$_.Exception.Message; $null = $plan.Add($item) }
}
if ($searchTruncated) { $null = $warnings.Add("$psaName had more than 500 open tickets matching 'Offline devices', so companies with nothing offline today were not checked for recovered devices.") }

$odsOut.status = 'success'
$odsOut.message = "Read $(Get-OdsPlural $counts.sites 'Datto RMM site' 'Datto RMM sites') and found $(Get-OdsPlural $counts.offline 'offline device' 'offline devices')."
$odsOut.plan = @($plan)
$odsOut.unmatchedSites = @($unmatched)
$odsOut.warnings = @(Get-OdsWarnings @($warnings))
Set-NodeOutput $odsOut
