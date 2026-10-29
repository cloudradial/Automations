# ---------- src/datto.ps1: a small read-only Datto RMM API v2 client ----------
# Used by the Offline Device Sweep's first step. It only reads (sites and their devices); it has no write call.
# Secrets (the same names as the datto-rmm catalog extension): Datto-ApiUrl, Datto-ApiKey, Datto-ApiSecret.
# Checked against Datto's API help page (rmm.datto.com/help/en/Content/2SETUP/APIv2.htm, read 2026-10-16):
#   - the token URL is {API URL}/auth/oauth/token with the OAuth client public-client / public sent as Basic auth
#   - calls go to {API URL}/api/v2/..., lists return at most 250 rows a page with pageDetails.nextPageUrl (null at the end)
#   - tokens last 100 hours; reads are limited to 600 a minute account-wide, and over the limit Datto answers 429
#     and asks you to wait 60 seconds (it doesn't promise a Retry-After header; one is honored when sent)
# Unverified: grant_type=password with username = API key and password = API secret. Datto's own example is an
# image on that page; this matches the datto-rmm extension's invocation profile, not a live run.
# All state lives in $DattoState, changed in place, because the runner runs a step in a child scope.

$DattoState = @{
    Base        = ''
    Token       = ''
    MaxRetries  = 4
    MaxPages    = 400
    DefaultWait = 60     # seconds to wait after a 429 with no Retry-After (Datto's own advice)
    MaxWait     = 120
    Secrets     = @('Datto-ApiUrl', 'Datto-ApiKey', 'Datto-ApiSecret')
}

function Get-DattoSecret { param([string]$Name) $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue } catch { }; return $v }
function Get-DattoProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-DattoPath { param($o, [string]$Path) foreach ($n in $Path -split '\.') { $o = Get-DattoProp $o $n; if ($null -eq $o) { return $null } }; return $o }
function Get-DattoHttpStatus { param($Err) $code = 0; try { $code = [int]$Err.Exception.Response.StatusCode } catch { }; return $code }
function Get-DattoErrorText { param($Err) $d = $null; try { if ($Err.ErrorDetails -and $Err.ErrorDetails.Message) { $d = $Err.ErrorDetails.Message } } catch { }; if (-not $d) { $d = [string]$Err.Exception.Message }; return $d }
# Seconds to wait after a 429: the Retry-After header when Datto sends one, else 60. Never more than MaxWait.
function Get-DattoRetryAfter {
    param($Err)
    $s = 0
    try {
        $ra = $Err.Exception.Response.Headers.RetryAfter
        if ($null -ne $ra -and $null -ne $ra.Delta) { $s = [int][Math]::Ceiling($ra.Delta.TotalSeconds) }
        elseif ($null -ne $ra -and $null -ne $ra.Date) { $s = [int][Math]::Ceiling(($ra.Date.UtcDateTime - [datetime]::UtcNow).TotalSeconds) }
    } catch { }
    if ($s -le 0) { $s = $DattoState.DefaultWait }
    return [Math]::Min($s, $DattoState.MaxWait)
}
# The API URL secret as a base: trimmed, no trailing slash, and without /api or /api/v2 if it was pasted with one.
function ConvertTo-DattoBaseUrl {
    param([string]$Url)
    $u = ([string]$Url).Trim().TrimEnd('/')
    $u = $u -replace '(?i)/api(/v2)?$', ''
    if ($u -notmatch '^https://[^/\s]+') { throw "The Datto-ApiUrl secret must be your platform's https API address, for example https://<platform>-api.centrastage.net." }
    return $u
}

# Mints the Bearer token. Throws a plain sentence when a secret is missing or Datto refuses the key and secret.
function Connect-Datto {
    $v = @{}; $missing = @()
    foreach ($n in $DattoState.Secrets) { $v[$n] = Get-DattoSecret $n; if ([string]::IsNullOrWhiteSpace($v[$n])) { $missing += $n } }
    if ($missing.Count) { throw "Datto RMM isn't set up. Add these secrets to the runner Key Vault: $($missing -join ', ')." }
    $DattoState.Base = ConvertTo-DattoBaseUrl $v['Datto-ApiUrl']
    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('public-client:public'))
    $form = "grant_type=password&username=$([uri]::EscapeDataString($v['Datto-ApiKey']))&password=$([uri]::EscapeDataString($v['Datto-ApiSecret']))"
    $tok = $null
    for ($i = 1; $i -le $DattoState.MaxRetries; $i++) {
        $err = $null
        try { $tok = Invoke-RestMethod -Method POST -Uri "$($DattoState.Base)/auth/oauth/token" -Headers @{ Authorization = "Basic $basic"; Accept = 'application/json' } -Body $form -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop }
        catch { $err = $_ }
        if ($null -eq $err) { break }
        $code = Get-DattoHttpStatus $err
        if ($code -eq 429 -and $i -lt $DattoState.MaxRetries) { Start-Sleep -Seconds (Get-DattoRetryAfter $err); continue }
        if ($code -in @(400, 401, 403)) { throw "Datto RMM refused the sign-in (HTTP $code). Check that Datto-ApiKey and Datto-ApiSecret are the API key and secret key of an enabled Datto RMM API user, and that Datto-ApiUrl is your platform's API address (for example https://<platform>-api.centrastage.net)." }
        $why = $(if ($code) { "HTTP $code" } else { Get-DattoErrorText $err })
        throw "Couldn't reach Datto RMM to sign in ($why). Check that Datto-ApiUrl is your platform's API address, for example https://<platform>-api.centrastage.net."
    }
    $access = [string](Get-DattoProp $tok 'access_token')
    if (-not $access) { throw 'Datto RMM sign-in returned no access token. Check the Datto-ApiKey and Datto-ApiSecret secrets.' }
    $DattoState.Token = $access
    return $true
}

# One GET. $Path is a path under the API URL, or a full link Datto handed back (it must be on the same host,
# so the token is never sent anywhere else). Retries 429 (and 502, 503, 504), and signs in again once on a 401.
function Invoke-Datto {
    param([string]$Path)
    if (-not $DattoState.Token) { throw 'Call Connect-Datto before reading Datto RMM.' }
    $uri = $Path
    if ($Path -match '^https?://') {
        $want = ([uri]$DattoState.Base).Authority; $got = ''
        try { $got = ([uri]$Path).Authority } catch { }
        if ($Path -notmatch '^https://' -or $got -ine $want) { throw "Datto RMM handed back a next-page link on another host ($got), which isn't followed." }
    }
    else { $uri = "$($DattoState.Base)$Path" }
    $reauth = $false
    for ($i = 1; $i -le $DattoState.MaxRetries; $i++) {
        $err = $null; $r = $null
        try { $r = Invoke-RestMethod -Method GET -Uri $uri -Headers @{ Authorization = "Bearer $($DattoState.Token)"; Accept = 'application/json' } -ErrorAction Stop }
        catch { $err = $_ }
        if ($null -eq $err) { return $r }
        $code = Get-DattoHttpStatus $err
        $short = ($uri -replace '^https://[^/]+', '') -replace '\?.*$', ''
        if ($code -eq 429 -and $i -lt $DattoState.MaxRetries) { Start-Sleep -Seconds (Get-DattoRetryAfter $err); continue }
        if ($code -in @(502, 503, 504) -and $i -lt $DattoState.MaxRetries) { Start-Sleep -Seconds ([Math]::Min(30, [Math]::Pow(2, $i))); continue }
        if ($code -eq 401 -and -not $reauth) { $reauth = $true; $null = Connect-Datto; $i--; continue }
        if ($code -eq 429) { throw "Datto RMM kept answering GET $short with HTTP 429 (too many requests). Datto allows 600 reads a minute across the whole account; run the sweep again later or at a quieter time." }
        if ($code -eq 403) { throw "Datto RMM refused GET $short (HTTP 403). Give the API user access to all sites and devices, or wait 5 minutes if Datto blocked the runner's address after too many requests." }
        throw "Datto RMM GET $short failed$(if ($code) { " (HTTP $code)" }): $(Get-DattoErrorText $err)"
    }
}

# Every row of a paged list: follows pageDetails.nextPageUrl until it is null.
function Get-DattoList {
    param([string]$Path, [string]$ItemsName)
    $out = New-Object System.Collections.ArrayList
    $next = $Path
    for ($p = 1; $p -le $DattoState.MaxPages -and $next; $p++) {
        $r = Invoke-Datto $next
        foreach ($row in @(Get-DattoProp $r $ItemsName | Where-Object { $null -ne $_ })) { $null = $out.Add($row) }
        $next = [string](Get-DattoPath $r 'pageDetails.nextPageUrl')
        if ($p -eq $DattoState.MaxPages -and $next) { throw "Datto RMM returned more than $($DattoState.MaxPages) pages for $($Path -replace '\?.*$', ''), so the list was not finished." }
    }
    return @($out)
}
function Get-DattoSites { return @(Get-DattoList '/api/v2/account/sites?max=250' 'sites') }
function Get-DattoSiteDevices { param([string]$SiteUid) return @(Get-DattoList "/api/v2/site/$([uri]::EscapeDataString($SiteUid))/devices?max=250" 'devices') }

# A Datto time as a UTC [datetime], or $null. Unverified: lastSeen's format. The help page doesn't show it, so
# epoch milliseconds, epoch seconds and ISO text are all accepted.
function ConvertFrom-DattoTime {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { if ($Value.Kind -eq [DateTimeKind]::Local) { return $Value.ToUniversalTime() }; return [datetime]::SpecifyKind($Value, [DateTimeKind]::Utc) }
    $s = ([string]$Value).Trim()
    if (-not $s -or $s -eq '0') { return $null }
    $n = 0.0
    if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) {
        if ($n -le 0) { return $null }
        $ms = $(if ($n -gt 100000000000) { $n } else { $n * 1000 })
        return [DateTimeOffset]::FromUnixTimeMilliseconds([long]$ms).UtcDateTime
    }
    $d = [datetime]::MinValue
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    if ([datetime]::TryParse($s, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$d)) { return $d }
    return $null
}

# Which sweep category a device is in: @{ key; label }. key is workstations, laptops, servers, mobile, printers,
# network, other, or '' when Datto gave no device type. Unverified: the deviceType.category values. These are
# the categories the Datto RMM web UI shows (Desktop, Laptop, Server, ESXi Host, Printer, Network Device, Mobile).
function Get-DattoDeviceCategory {
    param($Device)
    $cat = [string](Get-DattoPath $Device 'deviceType.category')
    $cls = [string](Get-DattoProp $Device 'deviceClass')
    $label = $(if ($cat) { $cat } elseif ($cls) { $cls } else { '' })
    $k = ($cat + ' ' + $cls).Trim().ToLowerInvariant()
    if (-not $k) { return @{ key = ''; label = '' } }
    if ($k -match 'server|esxi') { return @{ key = 'servers'; label = $label } }
    if ($k -match 'laptop|notebook') { return @{ key = 'laptops'; label = $label } }
    if ($k -match 'desktop|workstation') { return @{ key = 'workstations'; label = $label } }
    if ($k -match 'mobile|phone|tablet') { return @{ key = 'mobile'; label = $label } }
    if ($k -match 'printer') { return @{ key = 'printers'; label = $label } }
    if ($k -match 'network|router|switch|firewall|snmp') { return @{ key = 'network'; label = $label } }
    # A Datto agent device ("device" class) with an unrecognised category is treated as a workstation.
    if ($cls -ieq 'device' -and -not $cat) { return @{ key = 'workstations'; label = 'Device' } }
    return @{ key = 'other'; label = $label }
}
# ---------- end src/datto.ps1 ----------
