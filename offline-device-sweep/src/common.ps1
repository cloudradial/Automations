# ---------- src/common.ps1: helpers shared by the Offline Device Sweep steps ----------
# Paste after _shared/psa.ps1. Every internal note this workflow writes ends with a marker for the day:
#   [offline-device-sweep: yyyy-MM-dd]
# A later run finds its own open ticket for a company by the summary ("Offline devices: ...") and reads the
# newest marked note to see which devices were offline last time. The marker also makes a rerun on the same
# day (an Action Runs Retry, or a manual run after the Routine) safe: Add-PsaNote -Marker skips a note whose
# marker is already on the ticket. Each note and the ticket description carry one plain line that lists
# the hostnames offline in that check ("Offline in this check: ..."), which is how recovered devices are found.

$OdsText = @{
    Marker        = 'offline-device-sweep'
    MarkerPattern = '(?i)\[offline-device-sweep(:[^\]]*)?\]'
    SummaryPrefix = 'Offline devices:'
    ListPrefix    = 'Offline in this check:'
    NoteTitle     = 'Offline Device Sweep'
}

function Get-OdsMarker { param([string]$Day) return "$($OdsText.Marker): $Day" }
function Test-OdsMarkerIn { param([string]$Text) return ([string]$Text -match $OdsText.MarkerPattern) }
function Test-OdsSummary { param([string]$Summary) return ([string]$Summary).Trim().StartsWith($OdsText.SummaryPrefix, [StringComparison]::OrdinalIgnoreCase) }
function Get-OdsPlural { param([int]$n, [string]$One, [string]$Many) if ($n -eq 1) { return "1 $One" }; return "$n $Many" }

# The hostnames on the "Offline in this check:" line of a note or description (the last such line), or $null
# when the text has no such line. "none" means an empty list.
function Get-OdsListedHosts {
    param([string]$Text)
    $plain = ConvertTo-PsaPlainText $Text
    $ms = [regex]::Matches($plain, '(?im)^\s*Offline in this check:[ \t]*(?<list>[^\r\n]*)$')
    if ($ms.Count -eq 0) { return $null }
    $list = $ms[$ms.Count - 1].Groups['list'].Value.Trim().TrimEnd('.').Trim()
    # The comma keeps an empty or one-name list a list, so "none" isn't mistaken for "no line" ($null).
    if (-not $list -or $list -ieq 'none') { return , @() }
    return , @($list -split '\s*,\s*' | Where-Object { $_ })
}
function Get-OdsListLine { param($Hosts) $h = @($Hosts | Where-Object { $_ }); if (-not $h.Count) { return "$($OdsText.ListPrefix) none." }; return "$($OdsText.ListPrefix) $($h -join ', ')." }

# A PSCustomObject (from the previous step's JSON) as a hashtable, one level deep.
function ConvertTo-OdsHash {
    param($o)
    $h = @{}
    if ($null -eq $o) { return $h }
    if ($o -is [System.Collections.IDictionary]) { foreach ($k in $o.Keys) { $h[[string]$k] = $o[$k] }; return $h }
    foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }
    return $h
}
function ConvertTo-OdsList { param($v) return @(@($v) | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-OdsHash $_ }) }
# The step's warnings, then the shared PSA library's (for example a ConnectWise priority it couldn't set), once each.
function Get-OdsWarnings { param($Have) $all = @($Have | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ }); foreach ($w in @($PsaState.Warnings)) { if ($w -and $all -notcontains $w) { $all += [string]$w } }; return @($all) }

# "6 hours ago", "1 day ago", "14 days ago".
function Format-OdsAgo {
    param([double]$Hours)
    if ($Hours -lt 48) { $h = [int][Math]::Floor($Hours); if ($h -lt 1) { return 'less than an hour ago' }; return "$(Get-OdsPlural $h 'hour' 'hours') ago" }
    return "$(Get-OdsPlural ([int][Math]::Floor($Hours / 24)) 'day' 'days') ago"
}
# What a level 1 tech should try first, by how long the device has been gone.
function Get-OdsFirstStep {
    param($d)
    $days = [double]$d.hoursOffline / 24
    if ($d.isServer) { return "Check the server's power and network connection first, then its host or hypervisor console. A server this long offline may be stopping the whole client from working." }
    if ($days -ge 90) { return 'This device looks retired. Confirm with the client, then remove it from Datto RMM so it stops showing up.' }
    if ($days -ge 30) { return 'Confirm with the client whether this device is still in use or has been decommissioned.' }
    return 'Check that the device has power and a network connection, or ask the user whether it is switched off or away from the office.'
}
function Format-OdsDevice {
    param($d)
    $what = @(@($d.typeLabel, $d.os) | Where-Object { $_ }) -join ', '
    $seen = $(if ($d.lastSeenText) { "last seen $($d.lastSeenText), $(Format-OdsAgo ([double]$d.hoursOffline))" } else { 'last seen date unknown' })
    $where = $(if ($d.siteName) { " Datto site: $($d.siteName)." } else { '' })
    return "- $($d.hostname)$(if ($what) { " ($what)" }): $seen. Suggested first step: $(Get-OdsFirstStep $d)$where"
}

# Ticket summary, for example "Offline devices: 3 not seen for 7+ days".
function Get-OdsSummary {
    param($Item, $Settings)
    $devs = @($Item.devices); $servers = @($devs | Where-Object { $_.isServer }).Count; $others = $devs.Count - $servers
    $sh = [int]$Settings.serverOfflineHours; $od = [int]$Settings.offlineDays
    if ($servers -and -not $others) { return "$($OdsText.SummaryPrefix) $(Get-OdsPlural $servers 'server' 'servers') not seen for $sh+ hours" }
    if ($others -and -not $servers) { return "$($OdsText.SummaryPrefix) $($others) not seen for $od+ days" }
    return "$($OdsText.SummaryPrefix) $($devs.Count) not seen recently, including $(Get-OdsPlural $servers 'server' 'servers')"
}
# The device lines: servers first, under their own heading, then everything else.
function Get-OdsDeviceBlock {
    param($Devices, $Settings)
    $devs = @($Devices); $lines = @()
    $srv = @($devs | Where-Object { $_.isServer }); $rest = @($devs | Where-Object { -not $_.isServer })
    if ($srv.Count) {
        $lines += "Servers first: $(Get-OdsPlural $srv.Count 'server has' 'servers have') not been seen for $($Settings.serverOfflineHours) hours or more. Check these before anything else."
        $lines += @($srv | ForEach-Object { Format-OdsDevice $_ })
        if ($rest.Count) { $lines += '' }
    }
    if ($rest.Count) {
        # "other" only reads right when the servers are listed above.
        $noun = $(if ($srv.Count) { @('other device has', 'other devices have') } else { @('device has', 'devices have') })
        $lines += "$(Get-OdsPlural $rest.Count $noun[0] $noun[1]) not been seen for $($Settings.offlineDays) days or more:"
        $lines += @($rest | ForEach-Object { Format-OdsDevice $_ })
    }
    return $lines
}
function Get-OdsDescription {
    param($Item, $Settings)
    $devs = @($Item.devices)
    $lines = @("Offline Device Sweep found $(Get-OdsPlural $devs.Count 'device' 'devices') at $($Item.companyName) that Datto RMM has not seen for a while. Please check each one and update this ticket.", '')
    $lines += Get-OdsDeviceBlock $devs $Settings
    $lines += ''
    $lines += "Checked on $($Settings.checkedText). Datto RMM $(if (@($Item.sites).Count -eq 1) { 'site' } else { 'sites' }): $(@($Item.sites) -join ', ')."
    $lines += Get-OdsListLine @($devs | ForEach-Object { $_.hostname })
    return ($lines -join "`n")
}
# The internal note written right after the ticket is created (it carries the first marker).
function Get-OdsOpenedNote {
    param($Item, $Settings)
    $devs = @($Item.devices)
    return (@("Offline Device Sweep opened this ticket on $($Settings.checkedText) for $(Get-OdsPlural $devs.Count 'device' 'devices') that Datto RMM has not seen recently. Later runs add a note here when the list changes instead of opening another ticket.", (Get-OdsListLine @($devs | ForEach-Object { $_.hostname }))) -join "`n")
}
# The internal note on an existing ticket: what is newly offline, still offline, and back.
function Get-OdsUpdateNote {
    param($Item, $Settings)
    $devs = @($Item.devices); $new = @($devs | Where-Object { $_.isNew }); $still = @($devs | Where-Object { -not $_.isNew }); $rec = @($Item.recovered)
    $parts = @()
    if ($new.Count) { $parts += "$(Get-OdsPlural $new.Count 'device is' 'devices are') newly offline" }
    if ($still.Count) { $parts += "$(Get-OdsPlural $still.Count 'device is' 'devices are') still offline" }
    if ($rec.Count) { $parts += "$(Get-OdsPlural $rec.Count 'device has' 'devices have') recovered" }
    $lines = @("Offline Device Sweep checked $($Item.companyName) again on $($Settings.checkedText): $($parts -join ', ').")
    if (-not $devs.Count) { $lines += 'Nothing on this ticket is offline any more. Close the ticket once you are happy everything is working.' }
    if (@($new | Where-Object { $_.isServer }).Count) { $lines += 'A server is newly offline, so consider raising this ticket''s priority.' }
    if ($new.Count) { $lines += ''; $lines += 'Newly offline:'; $lines += @($new | ForEach-Object { Format-OdsDevice $_ }) }
    if ($still.Count) { $lines += ''; $lines += 'Still offline:'; $lines += @($still | ForEach-Object { Format-OdsDevice $_ }) }
    if ($rec.Count) { $lines += ''; $lines += 'Recovered:'; $lines += @($rec | ForEach-Object { "- $($_.hostname) $($_.reason)." }) }
    $lines += ''
    $lines += Get-OdsListLine @($devs | ForEach-Object { $_.hostname })
    return ($lines -join "`n")
}
# ---------- end src/common.ps1 ----------
