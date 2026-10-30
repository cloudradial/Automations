# === Step 2: Wake offline desktops (opt-in) ===
# Off unless the run input says wake: true. Then, for each offline desktop the first step found, it asks an
# online Windows desktop or laptop on the same subnet to send a Wake-on-LAN packet, by running your Datto RMM
# wake component there as a quick job. A few minutes later it reads the site again: a desktop that came back
# is left off the new ticket (or noted as recovered on the open one); one still offline is ticketed as usual,
# with a line saying a wake-up was tried. A preview sends nothing and says what it would send.
# Gates: desktops only (never servers, laptops, printers or network devices); never at a site that looks down;
# never for a company already noted today (a rerun or Retry sends nothing twice); at most wakeMax wake-ups a run.
# A failed wake never stops the tickets: the step warns and hands on what the first step found.
# Returns the first step's output, with the plan updated and a wake summary added.
$ErrorActionPreference = 'Stop'

$in = Get-NodeInput
if ($in -is [string]) { try { $in = $in | ConvertFrom-Json } catch { $in = $null } }
if ($null -eq (Get-PsaProp $in 'settings') -or [string](Get-PsaProp $in 'status') -ne 'success') {
    $msg = 'This step needs the output of the Find offline devices step. Run the workflow from the start.'
    Set-NodeOutput ([ordered]@{ status = 'error'; message = $msg })
    throw $msg
}
$settings = ConvertTo-OdsHash (Get-PsaProp $in 'settings')
if (-not ($settings.ContainsKey('wake') -and [bool]$settings.wake)) { Set-NodeOutput $in; return }

$preview = [bool]$settings.preview
$out = ConvertTo-OdsHash $in
$plan = @(ConvertTo-OdsList (Get-PsaProp $in 'plan'))
foreach ($p in $plan) { $p.devices = @(ConvertTo-OdsList $p.devices); $p.recovered = @(ConvertTo-OdsList $p.recovered); $p.woke = @(ConvertTo-OdsList $p.woke) }
$sites = @{}
foreach ($s in @(ConvertTo-OdsList (Get-PsaProp $in 'wakeSites'))) { $s.peers = @(ConvertTo-OdsList $s.peers); $sites[[string]$s.siteUid] = $s }
$warnings = @(Get-PsaProp $in 'warnings' | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
$wake = [ordered]@{ requested = $true; preview = $preview; component = [string]$settings.wakeComponent; waitMinutes = [int]$settings.wakeWaitMinutes; wouldWake = 0; sent = 0; cameBack = 0; stillOffline = 0; skipped = @(); attempts = @() }
$skipped = New-Object System.Collections.ArrayList
function Skip-OdsWake { param($Dev, [string]$Company, [string]$Why) $Dev.wakeNote = "No wake-up was sent: $Why."; $null = $skipped.Add([ordered]@{ hostname = [string]$Dev.hostname; company = $Company; reason = $Why }) }
function Complete-OdsWake {
    $wake.skipped = @($skipped)
    $out.plan = @($plan); $out.wake = $wake; $out.warnings = @(Get-OdsWarnings $warnings)
    Set-NodeOutput $out
}

# ---- which desktops to try ----
$targets = New-Object System.Collections.ArrayList
foreach ($p in $plan) {
    if ($p.action -notin @('create', 'update', 'unchanged') -or [bool]$p.alreadyToday) { continue }
    foreach ($d in @($p.devices)) {
        if ([string]$d.category -ne 'workstations') { continue }
        $site = $(if ($sites.ContainsKey([string]$d.siteUid)) { $sites[[string]$d.siteUid] } else { $null })
        if ($null -eq $site) { Skip-OdsWake $d $p.companyName 'its Datto site was not read'; continue }
        if ([bool]$site.down) { Skip-OdsWake $d $p.companyName 'the whole site may be down, so nothing there could send it'; continue }
        if (-not @($site.peers).Count) { Skip-OdsWake $d $p.companyName 'no Windows desktop or laptop at its site is online to send it'; continue }
        if ($targets.Count -ge [int]$settings.wakeMax) { Skip-OdsWake $d $p.companyName "this run already tried $($settings.wakeMax), the wakeMax limit"; continue }
        $null = $targets.Add(@{ dev = $d; item = $p; site = $site })
    }
}
if (-not $targets.Count) { Complete-OdsWake; return }

try {
    $null = Connect-Datto
    $component = Find-DattoComponent ([string]$settings.wakeComponent)
}
catch {
    $warnings += "No wake-ups were sent, so the tickets list every offline device: $($_.Exception.Message)"
    Complete-OdsWake; return
}
if ($null -eq $component) {
    foreach ($t in $targets) { Skip-OdsWake $t.dev $t.item.companyName "Datto RMM has no component named '$($settings.wakeComponent)'" }
    $warnings += "No wake-ups were sent: Datto RMM has no component named '$($settings.wakeComponent)'. Import the wake component from this automation's datto-component folder, or set wakeComponent to its name."
    Complete-OdsWake; return
}

# ---- pick a peer on the same subnet for each (the first three parts of the IPv4 address match) ----
# Unverified: a /24 subnet. The audit gives addresses but not masks, so a larger subnet may be missed.
$nicCache = @{}
function Get-OdsNics { param([string]$Uid) if (-not $nicCache.ContainsKey($Uid)) { try { $nicCache[$Uid] = @(Get-DattoDeviceNics $Uid) } catch { $nicCache[$Uid] = @() } }; return @($nicCache[$Uid]) }
function Get-OdsNet { param([string]$Ip) if (-not $Ip) { return '' }; return ($Ip -replace '\.\d{1,3}$', '') }
$ready = New-Object System.Collections.ArrayList
foreach ($t in $targets) {
    $nics = @(Get-OdsNics ([string]$t.dev.uid))
    if (-not $nics.Count) { Skip-OdsWake $t.dev $t.item.companyName 'Datto RMM has no MAC address for it'; continue }
    $nets = @($nics | ForEach-Object { Get-OdsNet $_.ipv4 } | Where-Object { $_ } | Select-Object -Unique)
    if (-not $nets.Count) { Skip-OdsWake $t.dev $t.item.companyName 'Datto RMM has no IPv4 address for it, so a peer on its network could not be picked'; continue }
    $peer = $null
    foreach ($pr in @($t.site.peers)) {
        if (@(Get-OdsNics ([string]$pr.uid) | Where-Object { $nets -contains (Get-OdsNet $_.ipv4) }).Count) { $peer = $pr; break }
    }
    if ($null -eq $peer) { Skip-OdsWake $t.dev $t.item.companyName 'no online Windows desktop or laptop is on its network'; continue }
    $null = $ready.Add(@{ dev = $t.dev; item = $t.item; peer = $peer; macs = (@($nics | ForEach-Object { $_.mac } | Select-Object -Unique) -join ',') })
}

# ---- preview: say what would be sent ----
if ($preview) {
    foreach ($r in $ready) { $r.dev.wakeNote = "A wake-up would be sent from $($r.peer.hostname) before ticketing."; $wake.wouldWake++ }
    Complete-OdsWake; return
}

# ---- send ----
$sentAt = (Get-Date).ToUniversalTime()
$sentText = $sentAt.ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture) + ' UTC'
$sent = New-Object System.Collections.ArrayList
foreach ($r in $ready) {
    try {
        $job = Start-DattoQuickJob -DeviceUid ([string]$r.peer.uid) -ComponentUid $component.uid -JobName "Offline Device Sweep wake $($r.dev.hostname)" -Variables @{ MacAddress = $r.macs }
        $r.jobUid = $job; $wake.sent++
        $null = $sent.Add($r)
    }
    catch { Skip-OdsWake $r.dev $r.item.companyName "the Datto job on $($r.peer.hostname) could not be started ($($_.Exception.Message))" }
}

# ---- wait, then read the sites again ----
if ($sent.Count) {
    Start-Sleep -Seconds ([int]$settings.wakeWaitMinutes * 60)
    $online = @{}
    foreach ($su in @($sent | ForEach-Object { [string]$_.dev.siteUid } | Select-Object -Unique)) {
        try { foreach ($d in @(Get-DattoSiteDevices $su)) { $online[[string](Get-DattoProp $d 'uid')] = ((Get-DattoProp $d 'online') -eq $true) } }
        catch { $warnings += "Couldn't read the Datto RMM site $su again after the wake-ups, so its devices are ticketed as still offline: $($_.Exception.Message)" }
    }
    $mins = [int]$settings.wakeWaitMinutes
    foreach ($r in $sent) {
        $back = $online.ContainsKey([string]$r.dev.uid) -and $online[[string]$r.dev.uid]
        $result = Get-DattoJobResult ([string]$r.jobUid) ([string]$r.peer.uid)
        $wake.attempts += [ordered]@{ hostname = [string]$r.dev.hostname; company = [string]$r.item.companyName; peer = [string]$r.peer.hostname; jobUid = [string]$r.jobUid; jobStatus = $result; cameBack = [bool]$back }
        if ($back) {
            $wake.cameBack++
            $r.dev.wakeNote = "Came back online after a wake-up sent from $($r.peer.hostname) at $sentText."
            $r.item.woke = @($r.item.woke) + @([ordered]@{ hostname = [string]$r.dev.hostname; reason = "came back online after a wake-up sent from $($r.peer.hostname)" })
            continue
        }
        $wake.stillOffline++
        $why = $(if ($result -and $result -notmatch '(?i)^success') { " The Datto job on $($r.peer.hostname) ended as '$result', so the packet may not have been sent." } else { '' })
        $r.dev.wakeNote = "A wake-up was sent from $($r.peer.hostname) at $sentText; it was still offline $(Get-OdsPlural $mins 'minute' 'minutes') later.$why"
    }
}

# ---- take the desktops that came back off the plan ----
foreach ($p in $plan) {
    if (-not @($p.woke).Count) { continue }
    $why = @{}; foreach ($w in @($p.woke)) { $why[([string]$w.hostname).ToLowerInvariant()] = [string]$w.reason }
    $gone = @($p.devices | Where-Object { $why.ContainsKey(([string]$_.hostname).ToLowerInvariant()) })
    $p.devices = @($p.devices | Where-Object { -not $why.ContainsKey(([string]$_.hostname).ToLowerInvariant()) })
    if ($p.action -eq 'create') {
        if (-not @($p.devices).Count) { $p.action = 'woke' }
        continue
    }
    # On an open ticket a desktop that was on its last list has recovered; one that was newly offline never reached it.
    foreach ($g in @($gone | Where-Object { -not [bool]$_.isNew })) { $p.recovered = @($p.recovered) + @([ordered]@{ hostname = [string]$g.hostname; reason = $why[([string]$g.hostname).ToLowerInvariant()] }) }
    $changed = (@($p.devices | Where-Object { [bool]$_.isNew }).Count -gt 0) -or (@($p.recovered).Count -gt 0) -or (-not [bool]$p.hadList -and @($p.devices).Count -gt 0) -or [bool]$p.newDown
    $p.action = $(if ($changed) { 'update' } else { 'unchanged' })
}
Complete-OdsWake
