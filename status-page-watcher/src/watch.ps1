# ---------- Status Page Watcher ----------
# Reads vendor status pages (Atlassian Statuspage sites such as Zoom, Google Workspace, Slack, and
# optionally Microsoft 365 service health), finds incidents that started or ended since the last run,
# and either tells your technicians with a Signal (approve mode, the default) or hands the incident to
# the Outage / Incident Broadcast workflow through its webhook (auto mode).
# Preview only until confirm is true: without it nothing is sent and the remembered state is not saved.
# State lives in the CloudRadial token @StatusWatcherState on the partner company, so each incident is
# announced once and announced as resolved once.
Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

# ---------- input ----------
function Get-SwProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
$in = Get-NodeInput
if ($null -ne (Get-SwProp $in 'trigger')) { $in = Get-SwProp $in 'trigger' }
function In { param([string[]]$Names, $Default = $null) foreach ($n in $Names) { $v = Get-SwProp $in $n; if ($null -ne $v -and [string]$v -ne '') { return $v } }; return $Default }
function ConvertTo-SwBool { param($v, [bool]$Default) if ($null -eq $v -or [string]$v -eq '') { return $Default }; if ($v -is [bool]) { return $v }; return ([string]$v -match '^(true|1|yes|on)$') }

$confirm = ConvertTo-SwBool (In @('confirm')) $false
$mode = ([string](In @('mode') 'approve')).ToLower()
if ($mode -notin @('approve', 'auto')) { $mode = 'approve' }
$minImpact = ([string](In @('minImpact', 'min_impact') 'minor')).ToLower()
$crCompany = [string](In @('cloudradial_company') '')
$notifyCompanyId = [int](In @('notifyCompanyId', 'notify_company_id') 1)
$notifyUserIds = @(In @('notifyUserIds', 'notify_user_ids') @()) | Where-Object { $_ } | ForEach-Object { [string]$_ }
$notifyRoles = @(In @('notifyRoles', 'notify_roles') @()) | Where-Object { $_ } | ForEach-Object { [string]$_ }
$simulate = In @('simulate') $null
$stateToken = [string](In @('stateToken', 'state_token') 'StatusWatcherState')
$m365Tenants = @(In @('m365TenantIds', 'm365_tenant_ids') @()) | Where-Object { $_ } | ForEach-Object { [string]$_ }

# Feeds. Each: name, type (statuspage | google | slack), url, service (the CloudRadial service name Outage
# Broadcast targets), optional companies / companyGroup, optional products (Google: only these products).
$defaultFeeds = @(
    [ordered]@{ name = 'Zoom'; type = 'statuspage'; url = 'https://status.zoom.us'; service = 'Zoom' }
    [ordered]@{ name = 'Google Workspace'; type = 'google'; url = 'https://www.google.com/appsstatus/dashboard/incidents.json'; service = 'Google Workspace' }
    [ordered]@{ name = 'Slack'; type = 'slack'; url = 'https://slack-status.com/api/v2.0.0/current'; service = 'Slack' }
    [ordered]@{ name = 'Fathom'; type = 'statuspage'; url = 'https://status.fathom.video'; service = 'Fathom' }
    [ordered]@{ name = 'Dropbox'; type = 'statuspage'; url = 'https://status.dropbox.com'; service = 'Dropbox' }
    [ordered]@{ name = 'Atlassian'; type = 'statuspage'; url = 'https://status.atlassian.com'; service = 'Atlassian' }
)
$feeds = @(In @('feeds') $defaultFeeds)
$onlyFeeds = @(In @('onlyFeeds', 'only_feeds') @()) | ForEach-Object { ([string]$_).ToLower() }
if ($onlyFeeds.Count) { $feeds = @($feeds | Where-Object { $onlyFeeds -contains ([string](Get-SwProp $_ 'name')).ToLower() }) }

$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
$impactRank = @{ none = 0; maintenance = 0; minor = 1; low = 1; medium = 2; major = 2; high = 3; critical = 3 }
$minRank = if ($impactRank.ContainsKey($minImpact)) { $impactRank[$minImpact] } else { 1 }

# ---------- HTTP ----------
function Get-SwJson { param([string]$Url)
    $r = Invoke-WebRequest -Uri $Url -Method GET -TimeoutSec 25 -UseBasicParsing -SkipHttpErrorCheck -Headers @{ 'User-Agent' = 'CloudRadial-StatusWatcher/1.0'; 'Accept' = 'application/json' }
    if ([int]$r.StatusCode -ge 400) { throw "HTTP $([int]$r.StatusCode) from $Url" }
    return ([string]$r.Content | ConvertFrom-Json -Depth 30)
}
function Get-SwText { param([string]$s, [int]$Max = 600) $t = ([string]$s) -replace '<[^>]+>', ' ' -replace '\s+', ' '; $t = $t.Trim(); if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max - 1) + '...' }; return $t }

# ---------- read the feeds ----------
# Every open incident becomes: key, feed, service, title, impact, rank, status, url, update, started, companies, companyGroup
$open = New-Object System.Collections.ArrayList
$feedReport = New-Object System.Collections.ArrayList
foreach ($f in $feeds) {
    $fname = [string](Get-SwProp $f 'name'); $ftype = ([string](Get-SwProp $f 'type')).ToLower(); $furl = ([string](Get-SwProp $f 'url')).TrimEnd('/')
    $fsvc = [string](Get-SwProp $f 'service'); if (-not $fsvc) { $fsvc = $fname }
    $base = [ordered]@{ feed = $fname; service = $fsvc; companies = @(Get-SwProp $f 'companies'); companyGroup = [string](Get-SwProp $f 'companyGroup') }
    $count = 0
    try {
        if ($ftype -eq 'statuspage') {
            $j = Get-SwJson "$furl/api/v2/incidents/unresolved.json"
            foreach ($i in @(Get-SwProp $j 'incidents')) {
                $imp = ([string](Get-SwProp $i 'impact')).ToLower(); if (-not $imp) { $imp = 'none' }
                $ups = @(Get-SwProp $i 'incident_updates'); $upd = if ($ups.Count) { Get-SwText (Get-SwProp $ups[0] 'body') } else { '' }
                $comp = @(@(Get-SwProp $i 'components') | ForEach-Object { [string](Get-SwProp $_ 'name') } | Where-Object { $_ })
                $o = [ordered]@{}; foreach ($k in $base.Keys) { $o[$k] = $base[$k] }
                $o.key = "$($fname.ToLower()):$([string](Get-SwProp $i 'id'))"; $o.title = [string](Get-SwProp $i 'name'); $o.impact = $imp
                $o.rank = if ($impactRank.ContainsKey($imp)) { $impactRank[$imp] } else { 1 }
                $o.status = [string](Get-SwProp $i 'status'); $o.url = [string](Get-SwProp $i 'shortlink'); if (-not $o.url) { $o.url = $furl }
                $o.update = $upd; $o.started = [string](Get-SwProp $i 'created_at'); $o.components = $comp
                $null = $open.Add($o); $count++
            }
        }
        elseif ($ftype -eq 'google') {
            $products = @(Get-SwProp $f 'products') | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLower() }
            $cutoff = (Get-Date).ToUniversalTime().AddDays(-3)
            foreach ($i in @(Get-SwJson $furl)) {
                if ($null -ne (Get-SwProp $i 'end') -and [string](Get-SwProp $i 'end') -ne '') { continue }
                $begin = $null; try { $begin = [datetime]::Parse([string](Get-SwProp $i 'begin')).ToUniversalTime() } catch { }
                if ($begin -and $begin -lt $cutoff.AddDays(-27)) { continue }
                $prods = @(@(Get-SwProp $i 'affected_products') | ForEach-Object { [string](Get-SwProp $_ 'title') } | Where-Object { $_ })
                if ($products.Count -and -not @($prods | Where-Object { $products -contains $_.ToLower() }).Count) { continue }
                $sev = ([string](Get-SwProp $i 'severity')).ToLower()
                $mru = Get-SwProp $i 'most_recent_update'
                $o = [ordered]@{}; foreach ($k in $base.Keys) { $o[$k] = $base[$k] }
                $o.key = "$($fname.ToLower()):$([string](Get-SwProp $i 'id'))"
                $o.title = Get-SwText (Get-SwProp $i 'external_desc') 160
                $o.impact = $sev; $o.rank = if ($impactRank.ContainsKey($sev)) { $impactRank[$sev] } else { 1 }
                $o.status = [string](Get-SwProp $mru 'status'); $o.update = Get-SwText (Get-SwProp $mru 'text')
                $o.url = 'https://www.google.com/appsstatus/dashboard/' + [string](Get-SwProp $i 'uri'); $o.started = [string](Get-SwProp $i 'begin'); $o.components = $prods
                if ($prods.Count) { $o.service = "$fsvc ($($prods -join ', '))" }
                $null = $open.Add($o); $count++
            }
        }
        elseif ($ftype -eq 'slack') {
            $j = Get-SwJson $furl
            foreach ($i in @(Get-SwProp $j 'active_incidents')) {
                $ty = ([string](Get-SwProp $i 'type')).ToLower()
                $o = [ordered]@{}; foreach ($k in $base.Keys) { $o[$k] = $base[$k] }
                $o.key = "$($fname.ToLower()):$([string](Get-SwProp $i 'id'))"; $o.title = [string](Get-SwProp $i 'title')
                $o.impact = if ($ty -eq 'outage') { 'major' } elseif ($ty -eq 'incident') { 'minor' } else { 'none' }
                $o.rank = $impactRank[$o.impact]; $o.status = [string](Get-SwProp $i 'status'); $o.url = [string](Get-SwProp $i 'url')
                $notes = @(Get-SwProp $i 'notes'); $o.update = if ($notes.Count) { Get-SwText (Get-SwProp $notes[0] 'body') } else { '' }
                $o.started = [string](Get-SwProp $i 'date_created'); $o.components = @(Get-SwProp $i 'services')
                $null = $open.Add($o); $count++
            }
        }
        else { $null = $warnings.Add("$($fname): unknown feed type '$ftype', skipped.") ; continue }
        $null = $feedReport.Add("$($fname): $count open")
    }
    catch { $null = $warnings.Add("$($fname): couldn't read the status page ($($_.Exception.Message)).") ; $null = $feedReport.Add("$($fname): unreadable") }
}

# Microsoft 365 service health: optional, one call per client tenant id given in m365TenantIds.
if ($m365Tenants.Count) {
    $cid = $null; $csec = $null
    try { $cid = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'M365-ClientID' -AsPlainText -ErrorAction SilentlyContinue; $csec = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'M365-ClientSecret' -AsPlainText -ErrorAction SilentlyContinue } catch { }
    if (-not $cid -or -not $csec) { $null = $warnings.Add('Microsoft 365: the M365-ClientID and M365-ClientSecret runner secrets are missing, so service health was skipped.') }
    else {
        foreach ($tid in $m365Tenants) {
            try {
                $tok = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$tid/oauth2/v2.0/token" -ContentType 'application/x-www-form-urlencoded' -Body @{ client_id = $cid; client_secret = $csec; scope = 'https://graph.microsoft.com/.default'; grant_type = 'client_credentials' }
                $h = @{ Authorization = "Bearer $($tok.access_token)" }
                $r = Invoke-RestMethod -Headers $h -Uri ("https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/issues?`$filter=" + [uri]::EscapeDataString("isResolved eq false and classification eq 'incident'"))
                $n = 0
                foreach ($i in @($r.value)) {
                    $o = [ordered]@{ feed = 'Microsoft 365'; service = "Microsoft 365 ($([string]$i.service))"; companies = @(); companyGroup = ''; tenantId = $tid }
                    $o.key = "m365:$($i.id)"; $o.title = [string]$i.title; $o.impact = 'major'; $o.rank = 2; $o.status = [string]$i.status
                    $o.url = 'https://admin.microsoft.com/#/servicehealth'; $o.update = Get-SwText $i.impactDescription; $o.started = [string]$i.startDateTime; $o.components = @([string]$i.feature)
                    $null = $open.Add($o); $n++
                }
                $null = $feedReport.Add("Microsoft 365 ($tid): $n open")
            }
            catch { $null = $warnings.Add("Microsoft 365 ($tid): couldn't read service health ($($_.Exception.Message)). The app needs ServiceHealth.Read.All with admin consent.") }
        }
    }
}

# Simulate: add one made-up incident so the whole path can be shown without a real outage.
if ($null -ne $simulate -and [string]$simulate -ne '' -and [string]$simulate -ne 'false') {
    $sf = if ($simulate -is [string] -and $simulate -ne 'true') { $simulate } else { [string](Get-SwProp $simulate 'feed') }
    if (-not $sf) { $sf = 'Zoom' }
    $feedDef = @($feeds | Where-Object { ([string](Get-SwProp $_ 'name')) -ieq $sf }) | Select-Object -First 1
    $svc = if ($feedDef) { [string](Get-SwProp $feedDef 'service') } else { $sf }
    $o = [ordered]@{ feed = $sf; service = $svc; companies = @($(if ($feedDef) { Get-SwProp $feedDef 'companies' })); companyGroup = [string]$(if ($feedDef) { Get-SwProp $feedDef 'companyGroup' }) }
    $o.key = "$($sf.ToLower()):simulated-$((Get-Date).ToUniversalTime().ToString('yyyyMMdd'))"
    $o.title = [string](Get-SwProp $simulate 'title'); if (-not $o.title -or $o.title -eq 'True') { $o.title = "$sf is having trouble (simulated incident)" }
    $o.impact = 'major'; $o.rank = 2; $o.status = 'investigating'; $o.url = if ($feedDef) { [string](Get-SwProp $feedDef 'url') } else { '' }
    $o.update = "$sf is investigating reports that some users can't connect. This is a simulated incident for testing."
    $o.started = (Get-Date).ToUniversalTime().ToString('o'); $o.components = @(); $o.simulated = $true
    $null = $open.Add($o)
}

# ---------- CloudRadial (state token and Signals) ----------
function Get-SwSecret { param([string]$Name) $v = $null; $n = if ($crCompany) { "$Name-$((($crCompany.ToLower()) -replace '[^a-z0-9]+', '-').Trim('-'))" } else { $Name }; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $n -AsPlainText -ErrorAction SilentlyContinue } catch { }; if (-not $v) { throw "The runner Key Vault has no $n secret." }; return $v }
$crBase = (Get-SwSecret 'CloudRadial-BaseUrl').Trim().TrimEnd('/')
$crAuth = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$((Get-SwSecret 'CloudRadial-PublicKey').Trim()):$((Get-SwSecret 'CloudRadial-PrivateKey').Trim())"))
function Invoke-Sw { param([string]$Path, [string]$Method = 'GET', $Body = $null)
    $a = @{ Uri = "$crBase$Path"; Method = $Method; Headers = @{ Authorization = $crAuth }; ContentType = 'application/json'; ErrorAction = 'Stop' }
    if ($null -ne $Body) { $a.Body = ConvertTo-Json -InputObject $Body -Depth 10 -Compress }
    return Invoke-RestMethod @a
}

# Remembered state: { "<key>": { "t": title, "s": service, "f": feed, "a": announcedUtc } }
$state = [ordered]@{}
$stateRead = $false
try {
    $tr = Invoke-Sw "/v2/odata/token?`$filter=$([uri]::EscapeDataString("companyId eq $notifyCompanyId and name eq '$stateToken'"))"
    $row = @(Get-SwProp $tr 'value') | Select-Object -First 1
    $raw = [string](Get-SwProp $row 'value')
    if ($raw) { $p = $raw | ConvertFrom-Json -AsHashtable; foreach ($k in $p.Keys) { $state[$k] = $p[$k] } }
    $stateRead = $true
}
catch { $null = $warnings.Add("Couldn't read the @$stateToken token ($($_.Exception.Message)); every open incident counts as new this run.") }

$relevant = @($open | Where-Object { $_.rank -ge $minRank })
$new = @($relevant | Where-Object { -not $state.Contains($_.key) })
$newKeys = @($new | ForEach-Object { $_.key })
$openKeys = @($open | ForEach-Object { $_.key })
$feedsRead = @($feedReport | Where-Object { $_ -notmatch 'unreadable' } | ForEach-Object { ($_ -split ':')[0].ToLower() })
# Resolved: remembered incidents no longer open, but only for feeds read successfully this run (an unreadable page is not a recovery).
$resolved = @(@($state.Keys) | Where-Object { $openKeys -notcontains $_ -and ($feedsRead -contains (($_ -split ':')[0])) -and $_ -notmatch ':simulated-' })

function Send-SwSignal { param([string]$Title, [string]$Body, [int]$Priority, [string]$Link, [string]$Key)
    $b = [ordered]@{ companyIds = @($notifyCompanyId); priority = $Priority; title = $Title.Substring(0, [Math]::Min(200, $Title.Length)); body = $Body.Substring(0, [Math]::Min(2000, $Body.Length)); expiresAt = (Get-Date).ToUniversalTime().AddDays(1).ToString('o'); dedupeKey = $Key }
    if ($notifyUserIds.Count) { $b.users = @($notifyUserIds) }
    if ($notifyRoles.Count) { $b.roles = @($notifyRoles) }
    if ($Link -match '^https://') { $b.deepLinkUrl = $Link; $b.deepLinkLabel = 'Open status page' }
    $r = Invoke-Sw '/v2/signalmessage' 'POST' $b
    return [string](Get-SwProp (Get-SwProp $r 'data') 'id')
}
function Send-SwBroadcast { param($Payload)
    $url = $null; $sec = $null
    try { $url = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'StatusWatcher-OutageWebhookUrl' -AsPlainText -ErrorAction SilentlyContinue; $sec = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'StatusWatcher-OutageWebhookSecret' -AsPlainText -ErrorAction SilentlyContinue } catch { }
    if (-not $url -or -not $sec) { throw 'auto mode needs the StatusWatcher-OutageWebhookUrl and StatusWatcher-OutageWebhookSecret runner secrets (the Outage / Incident Broadcast webhook).' }
    $null = Invoke-RestMethod -Method POST -Uri $url -Headers @{ 'X-Crauto-Webhook-Secret' = $sec } -ContentType 'application/json' -Body (ConvertTo-Json -InputObject $Payload -Depth 10 -Compress)
    return 'sent to Outage Broadcast'
}
function New-SwPayload { param($i, [string]$Mode, [string]$Message)
    $p = [ordered]@{ mode = $Mode; affectedService = [string]$i.service; message = $Message; confirm = $true; triggerSource = 'status-watcher'; requestedBy = 'Status Page Watcher' }
    $comps = @($i.companies | Where-Object { $_ }); if ($comps.Count) { $p.companies = $comps }
    if ($i.companyGroup) { $p.companyGroup = [string]$i.companyGroup }
    if ($crCompany) { $p.cloudradial_company = $crCompany }
    return $p
}

$plan = New-Object System.Collections.ArrayList
foreach ($i in $new) {
    $clientMsg = "$($i.feed) is reporting a problem: $($i.title). $(if ($i.update) { $i.update + ' ' })We're watching it and will update you when it's fixed. You don't need to report it."
    $techTitle = "$($i.feed) incident: $($i.title)"
    $techBody = "$($i.feed) reports a $($i.impact) incident ($($i.status)). $($i.update) To tell affected clients, run Outage Broadcast for '$($i.service)'$(if ($mode -eq 'approve') { ' (ChatAI /broadcast, or the workflow with the payload in this run).' } else { '.' })"
    $null = $plan.Add([ordered]@{ kind = 'new'; incident = $i; techTitle = $techTitle; techBody = $techBody; payload = (New-SwPayload $i 'broadcast' $clientMsg) })
}
foreach ($k in $resolved) {
    $s = $state[$k]; $ri = [ordered]@{ key = $k; feed = [string](Get-SwProp $s 'f'); service = [string](Get-SwProp $s 's'); title = [string](Get-SwProp $s 't'); companies = @(Get-SwProp $s 'c'); companyGroup = [string](Get-SwProp $s 'g'); url = '' }
    $null = $plan.Add([ordered]@{ kind = 'resolved'; incident = $ri; techTitle = "Resolved: $($ri.feed) $($ri.title)"; techBody = "$($ri.feed) has resolved: $($ri.title)."; payload = (New-SwPayload $ri 'resolved' "$($ri.feed) has fixed the problem: $($ri.title). Everything should be working again.") })
}

$sent = 0; $failed = 0
foreach ($p in $plan) {
    $i = $p.incident
    $what = if ($mode -eq 'auto') { "broadcast to clients through Outage Broadcast ($($p.payload.mode))" } else { 'Signal your technicians' }
    if (-not $confirm) { $null = $actions.Add([ordered]@{ action = "$($p.kind): $($i.feed) - $($i.title): $what"; result = 'preview' }); continue }
    try {
        $res = if ($mode -eq 'auto') { Send-SwBroadcast $p.payload } else { 'Signal ' + (Send-SwSignal $p.techTitle $p.techBody $(if ($p.kind -eq 'new') { 1 } else { 0 }) ([string]$i.url) "statuswatcher-$($i.key)-$($p.kind)") }
        $null = $actions.Add([ordered]@{ action = "$($p.kind): $($i.feed) - $($i.title): $what"; result = $res }); $sent++
        if ($p.kind -eq 'new') { $state[$i.key] = [ordered]@{ t = $i.title; s = $i.service; f = $i.feed; c = @($i.companies); g = $i.companyGroup; a = (Get-Date).ToUniversalTime().ToString('o') } }
        else { $state.Remove($i.key) }
    }
    catch { $failed++; $null = $actions.Add([ordered]@{ action = "$($p.kind): $($i.feed) - $($i.title): $what"; result = "failed: $($_.Exception.Message)" }) }
}

# Save state (only on confirm). Simulated incidents are never remembered, so the demo can be repeated.
foreach ($k in @($state.Keys)) { if ($k -match ':simulated-') { $state.Remove($k) } }
if ($confirm -and $plan.Count) {
    try {
        $keep = [ordered]@{}; foreach ($k in @($state.Keys) | Select-Object -Last 40) { $keep[$k] = $state[$k] }
        $null = Invoke-Sw '/v2/token' 'POST' ([ordered]@{ companyId = $notifyCompanyId; token = $stateToken; value = (ConvertTo-Json -InputObject $keep -Depth 5 -Compress); type = 'String' })
    }
    catch { $null = $warnings.Add("Couldn't save @$stateToken ($($_.Exception.Message)); the same incidents will be announced again next run.") }
}

$summary = "$($open.Count) open incident(s) across $($feedReport.Count) feed(s); $($new.Count) new at '$minImpact' or worse, $($resolved.Count) resolved."
$status = if ($failed) { 'partial' } elseif (-not $confirm -and $plan.Count) { 'pending_confirmation' } else { 'success' }
$msg = if (-not $plan.Count) { "Nothing new. $summary" } elseif (-not $confirm) { "Preview only, nothing sent. $summary Run with confirm true to $(if ($mode -eq 'auto') { 'broadcast' } else { 'Signal your technicians' })." } else { "Done. $summary $sent sent$(if ($failed) { ", $failed failed" })." }
Set-NodeOutput ([ordered]@{
    status = $status; message = $msg; mode = $mode; confirm = $confirm
    internal_note = "Status Page Watcher: $msg`n" + (($actions | ForEach-Object { " - $($_.action): $($_.result)" }) -join "`n")
    feeds = @($feedReport); incidents = @($open | ForEach-Object { [ordered]@{ feed = $_.feed; title = $_.title; impact = $_.impact; status = $_.status; url = $_.url; new = ($newKeys -contains $_.key) } })
    broadcastPayloads = @($plan | ForEach-Object { $_.payload })
    actions = @($actions); warnings = @($warnings)
    counts = [ordered]@{ open = $open.Count; new = $new.Count; resolved = $resolved.Count; sent = $sent; failed = $failed }
    stateRead = $stateRead
})
