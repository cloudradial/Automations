# Datto RMM component: Wake-on-LAN
# Create it in Datto RMM as a PowerShell component (Category: Scripts), named "Wake-on-LAN" (or set the sweep's
# wakeComponent input to the name you chose), with one String variable named MacAddress.
# Offline Device Sweep runs it as a quick job on an online Windows desktop or laptop on the same network as the
# offline desktop, and passes that desktop's MAC addresses (12 hex characters each, comma-separated).
# It sends the standard magic packet (6 x FF, then the MAC 16 times) over UDP port 9, to the all-hosts broadcast
# and to the broadcast address of each of this device's IPv4 networks. It changes nothing on this device.
# Exit 0 when at least one packet was sent, 1 when none could be.
$ErrorActionPreference = 'Stop'

$macs = @(([string]$env:MacAddress) -split '[,;\s]+' | ForEach-Object { ($_ -replace '[^0-9A-Fa-f]', '').ToUpperInvariant() } | Where-Object { $_.Length -eq 12 } | Select-Object -Unique)
if (-not $macs.Count) { Write-Output 'No valid MAC address was given in the MacAddress variable.'; exit 1 }

# The all-hosts broadcast, then each local network's directed broadcast (from address and prefix length).
$targets = @('255.255.255.255')
try {
    foreach ($a in @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixLength -lt 32 })) {
        $ip = [uint32[]]($a.IPAddress -split '\.'); $n = ($ip[0] -shl 24) -bor ($ip[1] -shl 16) -bor ($ip[2] -shl 8) -bor $ip[3]
        $host32 = [uint32]([math]::Pow(2, 32 - $a.PrefixLength) - 1)
        $b = $n -bor $host32
        $targets += (@(24, 16, 8, 0) | ForEach-Object { ($b -shr $_) -band 255 }) -join '.'
    }
}
catch { Write-Output "Couldn't read this device's networks, so only the all-hosts broadcast is used: $($_.Exception.Message)" }
$targets = @($targets | Select-Object -Unique)

$sent = 0
$udp = New-Object System.Net.Sockets.UdpClient
try {
    $udp.EnableBroadcast = $true
    foreach ($m in $macs) {
        $macBytes = [byte[]](0..5 | ForEach-Object { [Convert]::ToByte($m.Substring($_ * 2, 2), 16) })
        $packet = [byte[]](@(0xFF) * 6 + @(1..16 | ForEach-Object { $macBytes }))
        foreach ($t in $targets) {
            try { $null = $udp.Send($packet, $packet.Length, $t, 9); $sent++ }
            catch { Write-Output "Couldn't send to $t for $m`: $($_.Exception.Message)" }
        }
        Write-Output "Magic packet for $m sent to $($targets -join ', ') on UDP port 9."
    }
}
finally { $udp.Close() }

if (-not $sent) { Write-Output 'No magic packet could be sent.'; exit 1 }
exit 0
