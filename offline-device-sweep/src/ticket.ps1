# === Step 2: Open or update tickets ===
# For each company the first step found: opens one ticket listing its offline devices (servers first, at the
# higher priority), or adds an internal note to this workflow's open ticket when the list changed (newly offline
# and recovered devices). A preview writes nothing and returns what would be ticketed. Returns the run summary.
$ErrorActionPreference = 'Stop'

$in = Get-NodeInput
if ($in -is [string]) { try { $in = $in | ConvertFrom-Json } catch { $in = $null } }
$out = [ordered]@{
    status = 'error'; message = ''; preview = $false; internal_note = ''; public_note = ''; ticket_id = ''
    counts = [ordered]@{ sites = 0; devicesChecked = 0; offline = 0; sitesDown = 0; ticketsCreated = 0; ticketsUpdated = 0; ticketsUnchanged = 0; wouldCreate = 0; wouldUpdate = 0; unmatchedSites = 0; failed = 0 }
    companies = @(); unmatchedSites = @(); warnings = @()
}
$s0 = Get-PsaProp $in 'settings'
if ($null -eq $s0 -or $null -eq (Get-PsaProp $in 'counts') -or [string](Get-PsaProp $in 'status') -ne 'success') {
    $out.message = 'This step needs the output of the Find offline devices step. Run the workflow from the start.'
    Set-NodeOutput $out
    throw $out.message
}
$settings = ConvertTo-OdsHash $s0
$settings.preview = [bool]$settings.preview
# The runner's JSON hand-off can turn date text into a [datetime]; the day marker needs yyyy-MM-dd text.
if ($settings.today -is [datetime]) { $settings.today = $settings.today.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) }
$c1 = ConvertTo-OdsHash (Get-PsaProp $in 'counts')
foreach ($k in @('sites', 'devicesChecked', 'offline', 'sitesDown', 'unmatchedSites')) { if ($c1.ContainsKey($k)) { $out.counts[$k] = [int]$c1[$k] } }
$out.preview = $settings.preview
$out.unmatchedSites = @(Get-PsaProp $in 'unmatchedSites' | Where-Object { $null -ne $_ })
$warnings = @(Get-PsaProp $in 'warnings' | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
$plan = @(ConvertTo-OdsList (Get-PsaProp $in 'plan'))

try { $null = Connect-Psa ([string]$settings.psa) }
catch { $out.message = [string]$_.Exception.Message; $out.warnings = @($warnings); Set-NodeOutput $out; throw $out.message }

$rows = New-Object System.Collections.ArrayList
$lines = New-Object System.Collections.ArrayList
foreach ($p in $plan) {
    $devs = @($p.devices | Where-Object { $null -ne $_ })
    $servers = @($devs | Where-Object { $_.isServer }).Count
    $row = [ordered]@{
        company = [string]$p.companyName; companyId = [string]$p.companyId; sites = @($p.sites); offline = $devs.Count; servers = $servers
        sitesDown = @(@($p.sitesDown) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.site })
        action = [string]$p.action; ticketId = [string]$p.ticketId; ticketUrl = [string]$p.ticketUrl
        devices = @($devs | ForEach-Object { [string]$_.hostname }); recovered = @(@($p.recovered) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.hostname })
        summary = ''; text = ''; error = [string]$p.error
    }
    $label = "$($row.company)$(if ($row.ticketId) { " (ticket #$($row.ticketId))" })"
    try {
        switch ($p.action) {
            'create' {
                $row.summary = Get-OdsSummary $p $settings
                $row.text = Get-OdsDescription $p $settings
                $prio = $(if ($servers) { [string]$settings.serverPriority } else { [string]$settings.priority })
                if ($settings.preview) { $row.action = 'would create'; $out.counts.wouldCreate++; $null = $lines.Add("$label would get a new $prio priority ticket: $($row.summary)."); break }
                $t = New-PsaTicket -CompanyId $row.companyId -Summary $row.summary -Description $row.text -Priority $prio -Queue ([string]$settings.queue)
                $row.ticketId = [string]$t.id; $row.ticketUrl = Get-PsaTicketUrl $t.id
                $row.action = 'created'; $out.counts.ticketsCreated++
                $null = $lines.Add("$($row.company): opened ticket #$($t.id), $($row.summary).")
                # The marker note. If it fails the ticket still stands; the next run finds it by its summary.
                try { $null = Add-PsaNote -Id $t.id -Text (Get-OdsOpenedNote $p $settings) -Title $OdsText.NoteTitle -Marker (Get-OdsMarker ([string]$settings.today)) }
                catch { $warnings += "Ticket #$($t.id) for $($row.company) was opened, but its internal note couldn't be added: $($_.Exception.Message)" }
            }
            'update' {
                $row.summary = "Note on ticket #$($row.ticketId)"
                $row.text = Get-OdsUpdateNote $p $settings
                if ($settings.preview) { $row.action = 'would update'; $out.counts.wouldUpdate++; $null = $lines.Add("$label would get an internal note: $(Get-OdsPlural $devs.Count 'device' 'devices') offline, $(Get-OdsPlural $row.recovered.Count 'recovered' 'recovered')."); break }
                $r = Add-PsaNote -Id $row.ticketId -Text $row.text -Title $OdsText.NoteTitle -Marker (Get-OdsMarker ([string]$settings.today))
                if ($r -eq 'already-present') { $row.action = 'unchanged'; $out.counts.ticketsUnchanged++; $null = $lines.Add("${label}: already noted today."); break }
                $row.action = 'updated'; $out.counts.ticketsUpdated++
                $null = $lines.Add("${label}: added a note, $(Get-OdsPlural $devs.Count 'device' 'devices') offline and $(Get-OdsPlural $row.recovered.Count 'recovered' 'recovered').")
            }
            'unchanged' { $out.counts.ticketsUnchanged++; $null = $lines.Add("${label}: nothing changed since the last note.") }
            'failed' { $out.counts.failed++; $null = $lines.Add("${label}: not checked. $($row.error)") }
            default { }
        }
    }
    catch {
        $row.action = 'failed'; $row.error = [string]$_.Exception.Message; $out.counts.failed++
        $null = $lines.Add("${label}: failed. $($row.error)")
    }
    if ($row.sitesDown.Count -and $row.action -in @('created', 'updated', 'would create', 'would update')) {
        $null = $lines.Add("$($row.company): the whole Datto RMM $(if ($row.sitesDown.Count -eq 1) { 'site' } else { 'sites' }) $($row.sitesDown -join ', ') may be down (power, internet or firewall).")
    }
    $null = $rows.Add($row)
}

$out.companies = @($rows)
$out.warnings = @(Get-OdsWarnings $warnings)
$cn = $out.counts
$pending = $cn.wouldCreate + $cn.wouldUpdate
if ($settings.preview) {
    $out.status = $(if ($cn.failed) { 'incomplete' } elseif ($pending) { 'pending_confirmation' } else { 'success' })
    $out.message = "Preview: $(Get-OdsPlural $cn.offline 'offline device' 'offline devices') across $(Get-OdsPlural $cn.sites 'site' 'sites'). Would open $(Get-OdsPlural $cn.wouldCreate 'ticket' 'tickets') and update $(Get-OdsPlural $cn.wouldUpdate 'ticket' 'tickets'). Nothing was changed."
}
else {
    $out.status = $(if ($cn.failed) { 'incomplete' } else { 'success' })
    $out.message = "Checked $(Get-OdsPlural $cn.devicesChecked 'device' 'devices') across $(Get-OdsPlural $cn.sites 'Datto RMM site' 'Datto RMM sites') and found $(Get-OdsPlural $cn.offline 'offline device' 'offline devices'). Opened $(Get-OdsPlural $cn.ticketsCreated 'ticket' 'tickets') and updated $(Get-OdsPlural $cn.ticketsUpdated 'ticket' 'tickets')$(if ($cn.failed) { "; $(Get-OdsPlural $cn.failed 'company' 'companies') failed" })."
}
if ($cn.unmatchedSites) { $out.message += " $(Get-OdsPlural $cn.unmatchedSites 'site has' 'sites have') no PSA company match (see warnings)." }
$note = @("Offline Device Sweep: $($out.message)")
if ($lines.Count) { $note += ''; $note += @($lines) }
if ($out.warnings.Count) { $note += ''; $note += 'Warnings:'; $note += @($out.warnings | ForEach-Object { "- $_" }) }
$out.internal_note = $note -join "`n"
Set-NodeOutput $out
