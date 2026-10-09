# ---------- _shared/psa.ps1: one adapter for six PSAs ----------
# ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk.
# Edit this file, then run: node automationai/_shared/inject.js <automation-folder>
# The source of each call, and whether it has been checked, is in reference/build-kit/PSA.md.
# Calls marked "Unverified" below have not been proven by a live run; check them before the first live write.
# Secrets use the same Key Vault names as each PSA's catalog extension.
# All state lives in the $PsaState hashtable and is changed in place, because the runner
# runs a step in a child scope where $script: variables don't behave.

$PsaState = @{
    Conn       = $null
    Picklists  = @{}
    MaxRetries = 4
    Secrets    = @{
        connectwise = @('CW-ApiUrl', 'CW-CompanyID', 'CW-PublicKey', 'CW-PrivateKey', 'CW-ClientId')
        autotask    = @('Autotask-ApiUrl', 'Autotask-ApiIntegrationCode', 'Autotask-Username', 'Autotask-Secret')
        halopsa     = @('Halo-ApiUrl', 'Halo-ClientId', 'Halo-ClientSecret')
        kaseyabms   = @('KaseyaBMS-ApiUrl', 'KaseyaBMS-Username', 'KaseyaBMS-Password', 'KaseyaBMS-CompanyName')
        syncro      = @('Syncro-ApiUrl', 'Syncro-ApiKey')
        zendesk     = @('Zendesk-BaseUrl', 'Zendesk-Email', 'Zendesk-ApiToken')
    }
    Names      = @{ connectwise = 'ConnectWise'; autotask = 'Autotask'; halopsa = 'HaloPSA'; kaseyabms = 'Kaseya BMS'; syncro = 'Syncro'; zendesk = 'Zendesk' }
    # Used by the note, status and list functions (here and in _shared/psa-tickets.ps1).
    Statuses      = $null                                     # status list cache (Autotask, HaloPSA, Kaseya BMS)
    UrlTemplate   = $null                                     # the PSA-TicketUrlTemplate secret, read once
    FindTruncated = $false                                    # Find-PsaTickets stopped at -Max with more to read
    Warnings      = (New-Object System.Collections.ArrayList) # plain sentences a step can copy into its output
    Lookups       = @{}                                       # Resolve-PsaTicketNames cache
    Sla           = @{}                                       # Get-PsaTicketSla cache (ConnectWise SLA definitions)
    MaxPages      = 50
    ReadBackWaits = @(3, 6)                                   # seconds between read-backs after a redirected note write
    MaxTicketLoop = 50
    # Redirect handling in Invoke-Psa (see "Redirects" in _shared/README.md).
    StopRedirects     = $null                                 # Invoke-RestMethod takes -MaximumRedirection (checked once)
    LastWriteRedirect = $null                                 # the last write answered with a redirect: @{ Method; Path; Code; Location }
    CwInfoHost        = ''                                    # the https host ConnectWise names in its own _info links
}

# ---- small helpers (all Psa-prefixed so they don't clash with other shared files) ----
function Get-PsaSecret { param([string]$Name) $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue } catch { }; return $v }
function Get-PsaProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-PsaPath { param($o, [string]$Path) foreach ($n in $Path -split '\.') { $o = Get-PsaProp $o $n; if ($null -eq $o) { return $null } }; return $o }
function Test-PsaBlank { param($v) return ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v) -or [string]$v -eq '0') }
function ConvertTo-PsaQuery { param([string]$s) return [uri]::EscapeDataString($s) }
function Get-PsaText { param([string]$s, [int]$Max) if ($null -eq $s) { return '' }; if ($s.Length -gt $Max) { return $s.Substring(0, $Max) }; return $s }
function Get-PsaName { if ($null -eq $PsaState.Conn) { return 'the PSA' }; return $PsaState.Names[$PsaState.Conn.Psa] }
function Get-PsaConn { if ($null -eq $PsaState.Conn) { throw 'Call Connect-Psa before any other PSA function.' }; return $PsaState.Conn }
# ConnectWise conditions quote strings and leave numbers bare.
function Get-PsaCwOwner { param([string]$u) if ($u -match '^\d+$') { return "owner/id=$u" }; return "owner/identifier=`"$u`"" }
function Get-PsaHttpStatus { param($Err) $c = 0; try { $c = [int]$Err.Exception.Response.StatusCode } catch { }; return $c }
function Get-PsaRetryAfter { param($Err, [int]$Attempt) $s = 0; try { $ra = $Err.Exception.Response.Headers.RetryAfter; if ($null -ne $ra -and $null -ne $ra.Delta) { $s = [int][Math]::Ceiling($ra.Delta.TotalSeconds) } elseif ($null -ne $ra -and $null -ne $ra.Date) { $s = [int][Math]::Ceiling(($ra.Date.UtcDateTime - [datetime]::UtcNow).TotalSeconds) } } catch { }; if ($s -le 0) { $s = [int][Math]::Min(30, [Math]::Pow(2, $Attempt)) }; return [Math]::Min($s, 120) }
# An API base URL from a secret: trimmed, no trailing slash, and no doubled slashes in the path
# ("https://host//v4_6_release/apis/3.0/" becomes "https://host/v4_6_release/apis/3.0"). The scheme's "//" stays.
function ConvertTo-PsaBaseUrl {
    param([string]$Url)
    $u = ([string]$Url).Trim()
    if ($u -match '^(?<s>[A-Za-z][A-Za-z0-9+.-]*://)(?<r>.*)$') { $u = $Matches['s'] + ($Matches['r'] -replace '/{2,}', '/') }
    else { $u = $u -replace '/{2,}', '/' }
    return $u.TrimEnd('/')
}
# The items of a list reply. Invoke-Psa hands back a one-item JSON array as just that item, so "-is [array]"
# can't tell a bare list from an object that holds the list: an object with one of $Names is the holder
# (the first of them that has items wins).
function Get-PsaListReply {
    param($Reply, [string[]]$Names)
    if ($null -eq $Reply) { return @() }
    if ($Reply -is [array]) { return @($Reply | Where-Object { $null -ne $_ }) }
    $holder = $false
    foreach ($n in $Names) {
        $has = if ($Reply -is [System.Collections.IDictionary]) { $Reply.Contains($n) } else { $null -ne $Reply.PSObject.Properties[$n] }
        if (-not $has) { continue }
        $holder = $true
        $items = @(Get-PsaProp $Reply $n | Where-Object { $null -ne $_ })
        if ($items.Count) { return $items }
    }
    if ($holder) { return @() }
    return @($Reply)
}
function Get-PsaErrorText { param($Err) $d = $null; try { if ($Err.ErrorDetails -and $Err.ErrorDetails.Message) { $d = $Err.ErrorDetails.Message } } catch { }; if (-not $d) { $d = [string]$Err.Exception.Message }; return $d }

# Normalizes a priority hint to critical, high, medium or low ('' when blank).
function Get-PsaPriorityHint {
    param([string]$Hint)
    $h = ([string]$Hint).Trim().ToLowerInvariant()
    if (-not $h) { return '' }
    if ($h -match '^(critical|urgent|emergency|p?1)$') { return 'critical' }
    if ($h -match '^(high|p?2)$') { return 'high' }
    if ($h -match '^(medium|normal|moderate|p?3)$') { return 'medium' }
    if ($h -match '^(low|p?4)$') { return 'low' }
    throw "Priority '$Hint' isn't one of: critical, high, medium, low."
}
$PsaState.PriorityPatterns = @{
    critical = @('(?i)critical', '(?i)urgent', '(?i)emergency', '(?i)\b(p|priority\s*)1\b')
    high     = @('(?i)high', '(?i)\b(p|priority\s*)2\b')
    medium   = @('(?i)medium', '(?i)normal', '(?i)moderate', '(?i)\b(p|priority\s*)3\b')
    low      = @('(?i)low', '(?i)\b(p|priority\s*)4\b')
}
# The first item whose label property matches one of the patterns, in pattern order.
function Select-PsaByLabel {
    param($Items, [string]$LabelProp, [string[]]$Patterns)
    foreach ($p in $Patterns) {
        $hit = @($Items | Where-Object { $null -ne $_ -and [string](Get-PsaProp $_ $LabelProp) -match $p }) | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

# Which PSA: the run's psa input, then the PSA-Type secret, then ConnectWise when its secrets are
# set (so runners set up before PSA-Type existed keep working). '' means none is configured.
function Get-PsaType {
    param([string]$Requested)
    $v = $Requested; if ([string]::IsNullOrWhiteSpace($v) -or $v.StartsWith('@')) { $v = Get-PsaSecret 'PSA-Type' }
    if ([string]::IsNullOrWhiteSpace($v)) { if (Get-PsaSecret 'CW-ApiUrl') { return 'connectwise' }; return '' }
    $v = $v.Trim().ToLowerInvariant()
    $alias = @{ 'cw' = 'connectwise'; 'connectwise-manage' = 'connectwise'; 'connectwise psa' = 'connectwise'; 'connectwise manage' = 'connectwise'; 'autotask-psa' = 'autotask'; 'datto autotask' = 'autotask'; 'halo' = 'halopsa'; 'halo-psa' = 'halopsa'; 'kaseya' = 'kaseyabms'; 'kaseya-bms' = 'kaseyabms'; 'kaseya bms' = 'kaseyabms'; 'bms' = 'kaseyabms'; 'syncromsp' = 'syncro'; 'zendesk-ticketing' = 'zendesk' }
    if ($alias.ContainsKey($v)) { $v = $alias[$v] }
    if (-not $PsaState.Secrets.ContainsKey($v)) { throw "PSA '$v' isn't supported. Use one of: $(($PsaState.Secrets.Keys | Sort-Object) -join ', ')." }
    return $v
}

# Reads the PSA's secrets, mints a token where the PSA needs one, and keeps the connection in $PsaState.
# With no -Psa it uses Get-PsaType. Returns @{ Psa; Base; Headers }.
function Connect-Psa {
    param([string]$Psa)
    if ([string]::IsNullOrWhiteSpace($Psa)) { $Psa = Get-PsaType ''; if (-not $Psa) { throw 'No PSA is set up. Add the PSA-Type secret (connectwise, autotask, halopsa, kaseyabms, syncro or zendesk) to the runner Key Vault.' } }
    $Psa = $Psa.Trim().ToLowerInvariant()
    if (-not $PsaState.Secrets.ContainsKey($Psa)) { $Psa = Get-PsaType $Psa }
    $v = @{}; $missing = @()
    foreach ($n in $PsaState.Secrets[$Psa]) { $v[$n] = Get-PsaSecret $n; if ([string]::IsNullOrWhiteSpace($v[$n])) { $missing += $n } }
    if ($missing.Count) { throw "Add these secrets to the runner Key Vault: $($missing -join ', ')" }
    $json = 'application/json'
    $c = $null
    switch ($Psa) {
        'connectwise' {
            $b = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($v['CW-CompanyID'])+$($v['CW-PublicKey']):$($v['CW-PrivateKey'])"))
            $c = @{ Base = (ConvertTo-PsaBaseUrl $v['CW-ApiUrl']); Headers = @{ Authorization = "Basic $b"; clientId = $v['CW-ClientId']; Accept = $json } }
        }
        'autotask' {
            $c = @{ Base = ((ConvertTo-PsaBaseUrl $v['Autotask-ApiUrl']) -replace '/atservicesrest/v1\.0$', '') + '/atservicesrest/v1.0'
                Headers = @{ ApiIntegrationCode = $v['Autotask-ApiIntegrationCode']; UserName = $v['Autotask-Username']; Secret = $v['Autotask-Secret']; Accept = $json } }
        }
        'halopsa' {
            $base = (ConvertTo-PsaBaseUrl $v['Halo-ApiUrl']) -replace '/api$', ''
            $form = "grant_type=client_credentials&client_id=$([uri]::EscapeDataString($v['Halo-ClientId']))&client_secret=$([uri]::EscapeDataString($v['Halo-ClientSecret']))&scope=all"
            $tok = $null
            try { $tok = Invoke-RestMethod -Method POST -Uri "$base/auth/token" -Body $form -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop }
            catch {
                # Some instances run a separate auth server; /api/authinfo names it.
                $info = Invoke-RestMethod -Method GET -Uri "$base/api/authinfo" -ErrorAction Stop
                $authUrl = [string](Get-PsaProp $info 'auth_url'); if (-not $authUrl) { throw "HaloPSA sign-in failed and /api/authinfo named no auth server: $(Get-PsaErrorText $_)" }
                $tok = Invoke-RestMethod -Method POST -Uri "$($authUrl.TrimEnd('/'))/token" -Body $form -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
            }
            $access = Get-PsaProp $tok 'access_token'; if (-not $access) { throw 'HaloPSA sign-in returned no access_token. Check the Halo-* secrets.' }
            $c = @{ Base = "$base/api"; Headers = @{ Authorization = "Bearer $access"; Accept = $json } }
        }
        'kaseyabms' {
            $base = (ConvertTo-PsaBaseUrl $v['KaseyaBMS-ApiUrl']) -replace '/v2$', ''
            # Unverified: the GrantType value 'password' (PSA.md).
            $r = Invoke-RestMethod -Method POST -Uri "$base/v2/security/authenticate" -Form @{ UserName = $v['KaseyaBMS-Username']; Password = $v['KaseyaBMS-Password']; Tenant = $v['KaseyaBMS-CompanyName']; GrantType = 'password' } -ErrorAction Stop
            $token = Get-PsaPath $r 'Result.AccessToken'; if (-not $token) { $token = Get-PsaPath $r 'result.accessToken' }
            if (-not $token) { throw 'Kaseya BMS sign-in returned no Result.AccessToken. Check the KaseyaBMS-* secrets.' }
            $c = @{ Base = "$base/v2"; Headers = @{ Authorization = "Bearer $token"; Accept = $json } }
        }
        'syncro' { $c = @{ Base = (ConvertTo-PsaBaseUrl $v['Syncro-ApiUrl']); Headers = @{ Authorization = "Bearer $($v['Syncro-ApiKey'])"; Accept = $json } } }
        'zendesk' {
            # Unverified: whether the Zendesk-BaseUrl secret already ends in /api/v2, so it is added when missing.
            $base = ConvertTo-PsaBaseUrl $v['Zendesk-BaseUrl']; if ($base -notmatch '/api/v2$') { $base += '/api/v2' }
            $b = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($v['Zendesk-Email'])/token:$($v['Zendesk-ApiToken'])"))
            $c = @{ Base = $base; Headers = @{ Authorization = "Basic $b"; Accept = $json } }
        }
    }
    $c.Psa = $Psa
    $PsaState.Conn = $c
    $PsaState.Picklists = @{}
    $PsaState.Statuses = $null; $PsaState.UrlTemplate = $null; $PsaState.Lookups = @{}; $PsaState.Sla = @{}
    $PsaState.LastWriteRedirect = $null; $PsaState.CwInfoHost = ''
    return $c
}

# ---- redirects (see "Redirects" in _shared/README.md) ----
# Invoke-Psa asks Invoke-RestMethod not to follow redirects (-MaximumRedirection 0), so a 3xx comes back as an
# error it can look at. A test mock without that parameter just doesn't get it.
function Test-PsaStopRedirects {
    if ($null -eq $PsaState.StopRedirects) {
        $ok = $false; try { $ok = (Get-Command Invoke-RestMethod -ErrorAction Stop).Parameters.ContainsKey('MaximumRedirection') } catch { }
        $PsaState.StopRedirects = $ok
    }
    return [bool]$PsaState.StopRedirects
}
# @{ Code; Location } when the error is a redirect (a 3xx, or Invoke-RestMethod refusing to follow one), else $null.
function Get-PsaRedirect {
    param($Err, [string]$Uri)
    $code = Get-PsaHttpStatus $Err
    # PowerShell 7 refuses an https-to-http redirect before -MaximumRedirection applies. That error's text is in
    # ErrorDetails (the exception only says "Operation is not valid"), with no status code and no Location.
    $msg = ''; try { $msg = [string]$Err.Exception.Message } catch { }
    try { if ($Err.ErrorDetails -and $Err.ErrorDetails.Message) { $msg += ' ' + [string]$Err.ErrorDetails.Message } } catch { }
    try { $msg += ' ' + [string]$Err.FullyQualifiedErrorId } catch { }
    if (-not (($code -ge 300 -and $code -lt 400) -or ($code -eq 0 -and $msg -match '(?i)redirect'))) { return $null }
    $loc = $null
    try { $l = $Err.Exception.Response.Headers.Location; if ($null -ne $l) { $loc = $(if ($l.IsAbsoluteUri) { $l } else { [uri]::new([uri]$Uri, $l) }) } } catch { }
    return @{ Code = $code; Location = $loc }
}
# Where a redirect from $From to $To may be followed with the PSA's credentials: the same host, or a sibling
# under the same parent domain (staging.example.com and api.example.com), and always https (an http address is
# upgraded, so credentials never go over http). $null when it isn't safe.
function Get-PsaRedirectTarget {
    param([string]$From, $To)
    if ($null -eq $To) { return $null }
    $f = $null; $t = $null
    try { $f = [uri]$From; $t = [uri]$To } catch { return $null }
    if (-not $t.IsAbsoluteUri -or $t.Scheme -notin @('http', 'https')) { return $null }
    $a = $f.Host.ToLowerInvariant(); $b = $t.Host.ToLowerInvariant()
    if ($a -ne $b) {
        $ia = $a.IndexOf('.'); $ib = $b.IndexOf('.')
        if ($ia -lt 1 -or $ib -lt 1) { return $null }
        $pa = $a.Substring($ia + 1); $pb = $b.Substring($ib + 1)
        if ($pa -ne $pb -or $pa.IndexOf('.') -lt 1) { return $null }
    }
    $ub = [UriBuilder]::new($t); $ub.Scheme = 'https'
    if ($t.Scheme -eq 'http' -and $t.IsDefaultPort) { $ub.Port = -1 }
    return $ub.Uri.AbsoluteUri
}
# Points the connection at $Target's host (https, same API path) for the rest of the run, and says so.
function Move-PsaBaseHost {
    param([string]$Target)
    $c = Get-PsaConn
    $old = [uri]$c.Base; $new = [uri]$Target
    if ($old.Scheme -eq 'https' -and $old.Authority -ieq $new.Authority) { return }
    $c.Base = "https://$($new.Authority)$($old.AbsolutePath.TrimEnd('/'))"
    Add-PsaWarning "$(Get-PsaName) redirected calls for $($old.Host) to $($new.Host), so the rest of this run used $($c.Base). Set the API URL secret to that address."
}
# ConnectWise names its own host in the _info links of its records. When a reply's links name another https
# host, it is remembered; Invoke-Psa only moves to it if a write is then redirected without a usable Location.
function Save-PsaCwInfoHost {
    param($Reply)
    if ($PsaState.CwInfoHost) { return }
    try {
        $first = $Reply
        if ($Reply -is [array]) { if (-not $Reply.Count) { return }; $first = $Reply[0] }
        if ($null -eq $first -or $first -is [string] -or $first -is [valuetype]) { return }
        $infos = @(Get-PsaProp $first '_info')
        foreach ($p in @($first.PSObject.Properties)) {
            $v = $p.Value
            if ($null -ne $v -and $v -isnot [string] -and $v -isnot [valuetype] -and $v -isnot [array]) { $infos += Get-PsaProp $v '_info' }
        }
        foreach ($i in @($infos | Where-Object { $null -ne $_ -and $_ -isnot [string] })) {
            foreach ($p in @($i.PSObject.Properties)) {
                if ([string]$p.Value -match '^https://([^/?#]+)/[^?#]*/apis/') { $PsaState.CwInfoHost = $Matches[1]; return }
            }
        }
    }
    catch { }
}

# One call to the connected PSA. Path is relative to the API base (or a full URL).
# Retries 429 (and 502, 503, 504 on GET) honoring Retry-After; other errors throw a plain message.
# A JSON array reply comes back as its items (Invoke-RestMethod itself hands it over as ONE [object[]], which
# "@(...) | Where-Object" would see as a single record), so a one-item list is just that item.
# Redirects are never followed blindly: a GET follows up to 3 to a safe https address (Get-PsaRedirectTarget);
# a write (POST, PUT, PATCH, DELETE) is never sent twice. It sets $PsaState.LastWriteRedirect and throws, and
# the caller checks whether the change was saved (Add-PsaNote reads the ticket back).
function Invoke-Psa {
    param([string]$Method, [string]$Path, $Body = $null, [string]$ContentType = 'application/json')
    $c = Get-PsaConn
    $isRead = ([string]$Method).ToUpperInvariant() -eq 'GET'
    $uri = if ($Path -match '^https?://') { $Path } else { "$($c.Base)$Path" }
    $hops = 0
    for ($i = 1; $i -le $PsaState.MaxRetries; $i++) {
        $p = @{ Method = $Method; Uri = $uri; Headers = $c.Headers; ErrorAction = 'Stop' }
        if (Test-PsaStopRedirects) { $p.MaximumRedirection = 0 }
        if ($null -ne $Body) { $p.Body = $(if ($Body -is [string]) { $Body } else { ConvertTo-Json -InputObject $Body -Depth 10 -Compress }); $p.ContentType = $ContentType }
        $r = $null; $err = $null
        try { $r = Invoke-RestMethod @p } catch { $err = $_ }
        if ($null -eq $err) {
            if ($isRead -and $c.Psa -eq 'connectwise') { Save-PsaCwInfoHost $r }
            return $r   # returning the variable hands back an array's items, not the array as one object
        }
        $rd = Get-PsaRedirect $err $uri
        if ($null -ne $rd) {
            $to = Get-PsaRedirectTarget $uri $rd.Location
            $codeText = $(if ($rd.Code) { " (HTTP $($rd.Code))" } else { '' })
            if ($isRead) {
                if ($to -and $hops -lt 3) {
                    $hops++
                    if ($uri.StartsWith($c.Base)) { Move-PsaBaseHost $to }
                    $uri = $to; $i--; continue
                }
                $where = $(if ($null -ne $rd.Location) { "to $(([uri]$rd.Location).GetLeftPart([UriPartial]::Authority))" } else { 'elsewhere' })
                throw "$(Get-PsaName) $Method $Path was redirected$codeText $where, which isn't followed (it must stay https on the same or a sibling host). Set the API URL secret to the address the PSA uses."
            }
            # A write may have been saved before the redirect, so it is never sent again here.
            if (-not $to -and $c.Psa -eq 'connectwise' -and $PsaState.CwInfoHost) { $to = Get-PsaRedirectTarget $uri "https://$($PsaState.CwInfoHost)/" }
            if ($to -and $uri.StartsWith($c.Base)) { Move-PsaBaseHost $to }
            $PsaState.LastWriteRedirect = @{ Method = $Method; Path = $Path; Code = $rd.Code; Location = [string]$rd.Location }
            throw "$(Get-PsaName) $Method $Path was answered with a redirect$codeText instead of a result, so the change may or may not have been saved. It was not sent again. Set the API URL secret to the address the PSA uses."
        }
        $code = Get-PsaHttpStatus $err
        if (($code -eq 429 -or ($isRead -and $code -in @(502, 503, 504))) -and $i -lt $PsaState.MaxRetries) { Start-Sleep -Seconds (Get-PsaRetryAfter $err $i); continue }
        throw "$(Get-PsaName) $Method $Path failed$(if ($code) { " (HTTP $code)" }): $(Get-PsaErrorText $err)"
    }
}

# Autotask picklists are per tenant: match on the label, never a hard-coded number.
function Get-PsaAtPicklist {
    param([string]$Entity, [string]$Field)
    if (-not $PsaState.Picklists.ContainsKey($Entity)) { $PsaState.Picklists[$Entity] = @(Get-PsaProp (Invoke-Psa GET "/$Entity/entityInformation/fields") 'fields') }
    $f = @($PsaState.Picklists[$Entity] | Where-Object { [string](Get-PsaProp $_ 'name') -eq $Field }) | Select-Object -First 1
    return @(Get-PsaProp $f 'picklistValues' | Where-Object { $null -ne $_ -and (Get-PsaProp $_ 'isActive') -ne $false })
}
function Select-PsaAtValue {
    param($Values, [string[]]$Patterns)
    $hit = Select-PsaByLabel $Values 'label' $Patterns
    if ($hit) { return (Get-PsaProp $hit 'value') }
    return $null
}
function Get-PsaAtCompleteStatuses {
    $v = @(Get-PsaAtPicklist 'Tickets' 'status' | Where-Object { [string](Get-PsaProp $_ 'label') -match '(?i)complete' } | ForEach-Object { [int](Get-PsaProp $_ 'value') })
    if (-not $v.Count) { $v = @(5) }
    return $v
}

# Normalized ticket: @{ id; summary; description; companyId; status; assigneeId; assigneeIds; raw }.
function Get-PsaTicket {
    param([string]$Id)
    $c = Get-PsaConn
    switch ($c.Psa) {
        'connectwise' {
            $t = Invoke-Psa GET "/service/tickets/$Id"
            $desc = ''
            try { $n = @(Invoke-Psa GET "/service/tickets/$Id/notes?orderBy=$(ConvertTo-PsaQuery 'id asc')&pageSize=1"); if ($n.Count -and $null -ne $n[0]) { $desc = [string](Get-PsaProp $n[0] 'text') } } catch { }
            $owner = Get-PsaProp $t 'owner'
            $a = @(@((Get-PsaProp $owner 'identifier'), (Get-PsaProp $owner 'id')) | Where-Object { -not (Test-PsaBlank $_) } | ForEach-Object { [string]$_ })
            return @{ id = $Id; summary = [string](Get-PsaProp $t 'summary'); description = $desc; companyId = [string](Get-PsaPath $t 'company.id'); status = [string](Get-PsaPath $t 'status.name'); assigneeId = $(if ($a.Count) { $a[0] } else { '' }); assigneeIds = $a; raw = $t }
        }
        'autotask' {
            $t = Get-PsaProp (Invoke-Psa GET "/Tickets/$Id") 'item'
            if ($null -eq $t) { throw "Autotask returned no ticket $Id." }
            $a = Get-PsaProp $t 'assignedResourceID'
            return @{ id = $Id; summary = [string](Get-PsaProp $t 'title'); description = [string](Get-PsaProp $t 'description'); companyId = [string](Get-PsaProp $t 'companyID'); status = [string](Get-PsaProp $t 'status'); assigneeId = $(if (Test-PsaBlank $a) { '' } else { [string]$a }); assigneeIds = @(); raw = $t }
        }
        'halopsa' {
            $t = Invoke-Psa GET "/Tickets/$($Id)?includedetails=true"
            $a = Get-PsaProp $t 'agent_id'
            return @{ id = $Id; summary = [string](Get-PsaProp $t 'summary'); description = [string](Get-PsaProp $t 'details'); companyId = [string](Get-PsaProp $t 'client_id'); status = [string](Get-PsaProp $t 'status_id'); assigneeId = $(if (Test-PsaBlank $a) { '' } else { [string]$a }); assigneeIds = @(); raw = $t }
        }
        'kaseyabms' {
            $t = Get-PsaProp (Invoke-Psa GET "/servicedesk/tickets/$Id") 'Result'
            if ($null -eq $t) { throw "Kaseya BMS returned no ticket $Id." }
            $a = Get-PsaProp $t 'AssigneeId'
            return @{ id = $Id; summary = [string](Get-PsaProp $t 'Title'); description = [string](Get-PsaProp $t 'Details'); companyId = [string](Get-PsaProp $t 'AccountId'); status = [string](Get-PsaProp $t 'StatusName'); assigneeId = $(if (Test-PsaBlank $a) { '' } else { [string]$a }); assigneeIds = @(); raw = $t }
        }
        'syncro' {
            $t = Get-PsaProp (Invoke-Psa GET "/tickets/$Id") 'ticket'
            if ($null -eq $t) { throw "Syncro returned no ticket $Id." }
            $cm = @(Get-PsaProp $t 'comments' | Where-Object { $null -ne $_ })
            $desc = if ($cm.Count) { [string](Get-PsaProp $cm[0] 'body') } else { '' }
            $pt = [string](Get-PsaProp $t 'problem_type'); if ($pt) { $desc = "Issue type: $pt`n$desc" }
            $a = Get-PsaProp $t 'user_id'
            return @{ id = $Id; summary = [string](Get-PsaProp $t 'subject'); description = $desc; companyId = [string](Get-PsaProp $t 'customer_id'); status = [string](Get-PsaProp $t 'status'); assigneeId = $(if (Test-PsaBlank $a) { '' } else { [string]$a }); assigneeIds = @(); raw = $t }
        }
        'zendesk' {
            $t = Get-PsaProp (Invoke-Psa GET "/tickets/$Id") 'ticket'
            if ($null -eq $t) { throw "Zendesk returned no ticket $Id." }
            $a = Get-PsaProp $t 'assignee_id'
            return @{ id = $Id; summary = [string](Get-PsaProp $t 'subject'); description = [string](Get-PsaProp $t 'description'); companyId = [string](Get-PsaProp $t 'organization_id'); status = [string](Get-PsaProp $t 'status'); assigneeId = $(if (Test-PsaBlank $a) { '' } else { [string]$a }); assigneeIds = @(); raw = $t }
        }
    }
}

# Creates a ticket and returns @{ id; raw }.
#   -CompanyId  the PSA's own company id (Find-PsaCompany resolves a name to it)
#   -Priority   a hint: critical, high, medium or low. It is matched to the tenant's priority list where the PSA has one.
#   -Queue      optional board (ConnectWise), queue (Autotask, Kaseya BMS), team (HaloPSA), issue type (Syncro) or group id (Zendesk)
#   -Extra      optional hashtable of raw PSA fields merged into the body, for tenant-specific required ids
function New-PsaTicket {
    param([string]$CompanyId, [string]$Summary, [string]$Description = '', [string]$Priority = '', [string]$Queue = '', [hashtable]$Extra = @{})
    $c = Get-PsaConn
    if ([string]::IsNullOrWhiteSpace($CompanyId)) { throw 'New-PsaTicket needs a company id. Use Find-PsaCompany to look one up by name.' }
    if ([string]::IsNullOrWhiteSpace($Summary)) { throw 'New-PsaTicket needs a summary.' }
    $hint = Get-PsaPriorityHint $Priority
    $pats = @(); if ($hint) { $pats = $PsaState.PriorityPatterns[$hint] }
    $isNum = $Queue -match '^\d+$'
    $id = $null; $raw = $null
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: not in PSA.md yet. Body and /service/priorities lookup from the CW swagger clients.
            $b = [ordered]@{ summary = (Get-PsaText $Summary 100); company = @{ id = [int]$CompanyId }; initialDescription = $Description }
            if ($Queue) { $b.board = $(if ($isNum) { @{ id = [int]$Queue } } else { @{ name = $Queue } }) }
            if ($hint) { $pr = Select-PsaByLabel @(Invoke-Psa GET '/service/priorities?pageSize=100') 'name' $pats; if ($pr) { $b.priority = @{ id = [int](Get-PsaProp $pr 'id') } } }
            foreach ($k in $Extra.Keys) { $b[$k] = $Extra[$k] }
            $raw = Invoke-Psa POST '/service/tickets' $b
            $id = Get-PsaProp $raw 'id'
        }
        'autotask' {
            # From the at_create_ticket extension descriptor: title, companyID, status, priority and dueDateTime are required.
            $status = Get-PsaSecret 'Autotask-NewStatusId'
            if (-not $status) { $status = Select-PsaAtValue (Get-PsaAtPicklist 'Tickets' 'status') @('^New$', '(?i)^new') }
            if (-not $status) { $status = 1 }
            $prio = $null
            if ($hint) { $prio = Select-PsaAtValue (Get-PsaAtPicklist 'Tickets' 'priority') $pats }
            if ($null -eq $prio) { $def = @(Get-PsaAtPicklist 'Tickets' 'priority' | Where-Object { (Get-PsaProp $_ 'isDefaultValue') -eq $true }) | Select-Object -First 1; if ($def) { $prio = Get-PsaProp $def 'value' } }
            if ($null -eq $prio) { $prio = Select-PsaAtValue (Get-PsaAtPicklist 'Tickets' 'priority') $PsaState.PriorityPatterns['medium'] }
            if ($null -eq $prio) { throw 'Could not find an Autotask ticket priority. Pass -Priority, or -Extra @{ priority = <id> }.' }
            $due = (Get-Date).ToUniversalTime().AddDays($(switch ($hint) { 'critical' { 0.25 } 'high' { 1 } 'low' { 7 } default { 3 } }))
            $b = [ordered]@{ companyID = [long]$CompanyId; title = (Get-PsaText $Summary 255); description = (Get-PsaText $Description 8000); status = [int]$status; priority = [int]$prio; dueDateTime = $due.ToString('yyyy-MM-ddTHH:mm:ssZ') }
            if ($Queue) {
                $qv = if ($isNum) { $Queue } else { Select-PsaAtValue (Get-PsaAtPicklist 'Tickets' 'queueID') @("^$([regex]::Escape($Queue))$") }
                if ($null -eq $qv) { throw "Autotask has no ticket queue named '$Queue'." }
                $b.queueID = [int]$qv
            }
            $bc = Get-PsaSecret 'Autotask-BillingCodeId'; if ($bc) { $b.billingCodeID = [long]$bc }
            foreach ($k in $Extra.Keys) { $b[$k] = $Extra[$k] }
            $raw = Invoke-Psa POST '/Tickets' $b
            $id = Get-PsaProp $raw 'itemId'
        }
        'halopsa' {
            # Unverified: not in PSA.md yet. Halo priority ids are per tenant; 1 to 4 are the out-of-box Critical to Low.
            $b = [ordered]@{ summary = $Summary; details = $Description; client_id = [long]$CompanyId }
            if ($hint) { $b.priority_id = @{ critical = 1; high = 2; medium = 3; low = 4 }[$hint] }
            if ($Queue) { if ($isNum) { $b.team_id = [long]$Queue } else { $b.team = $Queue } }
            foreach ($k in $Extra.Keys) { $b[$k] = $Extra[$k] }
            $raw = Invoke-Psa POST '/Tickets' @($b)
            $first = @($raw)[0]
            $id = Get-PsaProp $first 'id'
        }
        'kaseyabms' {
            # Unverified: not in PSA.md yet. BMS needs tenant ids for status, type, source and priority; they come from
            # the optional KaseyaBMS-NewStatusId, -TicketTypeId, -TicketSourceId, -PriorityId and -QueueId secrets, or -Extra.
            $b = [ordered]@{ Title = $Summary; Details = $Description; AccountId = [long]$CompanyId; OpenDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
            foreach ($pair in @(@('StatusId', 'KaseyaBMS-NewStatusId'), @('TypeId', 'KaseyaBMS-TicketTypeId'), @('SourceId', 'KaseyaBMS-TicketSourceId'), @('PriorityId', 'KaseyaBMS-PriorityId'), @('QueueId', 'KaseyaBMS-QueueId'))) {
                $sv = Get-PsaSecret $pair[1]; if ($sv -and $sv -match '^\d+$') { $b[$pair[0]] = [int]$sv }
            }
            if ($Queue) { if (-not $isNum) { throw 'Kaseya BMS needs a numeric queue id for -Queue.' }; $b.QueueId = [int]$Queue }
            foreach ($k in $Extra.Keys) { $b[$k] = $Extra[$k] }
            $raw = Invoke-Psa POST '/servicedesk/tickets' $b
            $id = Get-PsaPath $raw 'Result.Id'; if ($null -eq $id) { $id = Get-PsaProp $raw 'Result' }
        }
        'syncro' {
            # Unverified: not in PSA.md yet. Syncro takes the description as the first comment, and priority as a label.
            $b = [ordered]@{ customer_id = [long]$CompanyId; subject = $Summary; status = 'New'; comments_attributes = @(@{ subject = 'Initial Issue'; body = $(if ($Description) { $Description } else { $Summary }); hidden = $false; do_not_email = $true }) }
            if ($hint) { $b.priority = @{ critical = '0 Urgent'; high = '1 High'; medium = '2 Normal'; low = '3 Low' }[$hint] }
            if ($Queue) { $b.problem_type = $Queue }
            foreach ($k in $Extra.Keys) { $b[$k] = $Extra[$k] }
            $raw = Invoke-Psa POST '/tickets' $b
            $id = Get-PsaPath $raw 'ticket.id'
        }
        'zendesk' {
            # Unverified: not in PSA.md yet. Zendesk priorities are fixed: urgent, high, normal, low.
            $t = [ordered]@{ subject = $Summary; comment = @{ body = $(if ($Description) { $Description } else { $Summary }) }; organization_id = [long]$CompanyId }
            if ($hint) { $t.priority = @{ critical = 'urgent'; high = 'high'; medium = 'normal'; low = 'low' }[$hint] }
            if ($Queue) { if (-not $isNum) { throw 'Zendesk needs a numeric group id for -Queue.' }; $t.group_id = [long]$Queue }
            foreach ($k in $Extra.Keys) { $t[$k] = $Extra[$k] }
            $raw = Invoke-Psa POST '/tickets' @{ ticket = $t }
            $id = Get-PsaPath $raw 'ticket.id'
        }
    }
    if (Test-PsaBlank $id) { throw "$(Get-PsaName) accepted the new ticket but returned no id." }
    return @{ id = [string]$id; raw = $raw }
}

# Adds a note. Internal (technician-only) by default; -Public makes it visible to the client.
# Throws when the PSA rejects it.
# -Marker makes the write safe to repeat (a ServiceAI Action Runs "Retry" replays the whole request):
# when a note on the ticket already holds the marker nothing is written. An internal note gets "[marker]"
# as its last line. A public (client-visible) note never shows the marker: its last line is only the
# opaque "Ref: xxxxxxxx" (Get-PsaMarkerRef), and a "[marker]" the caller put in -Text is taken out.
# With -Marker it returns 'written' or 'already-present'; without it, nothing (so existing callers that
# don't discard the result are unchanged). If the notes can't be read, it throws rather than risk a
# second copy. Never put personal data (names, UPNs, email addresses) or internal tags in a marker.
function Add-PsaNote {
    param([string]$Id, [string]$Text, [string]$Title = 'Note', [switch]$Public, [switch]$Internal, [string]$Marker = '')
    $c = Get-PsaConn
    $tag = ''
    $pub = [bool]$Public
    if ($Marker) {
        $tag = Get-PsaMarkerTag $Marker
        if (Test-PsaNoteMarker -Id $Id -Marker $tag) { return 'already-present' }
        if ($pub) {
            $ref = Get-PsaMarkerRef $tag
            $Text = ([string]$Text) -replace [regex]::Escape($tag), ''
            if (-not (Test-PsaMarkerRefIn $Text $ref)) { $Text = "$($Text.TrimEnd())`n$ref" }
        }
        elseif ($Text.IndexOf($tag, [StringComparison]::OrdinalIgnoreCase) -lt 0) { $Text = "$($Text.TrimEnd())`n$tag" }
    }
    # A write answered with a redirect may still have been saved (ConnectWise did exactly that), so the note is
    # never sent twice: the ticket is read back, and only a note that isn't there is reported as a failure.
    $PsaState.LastWriteRedirect = $null
    try { Send-PsaNote -Id $Id -Text $Text -Title $Title -Pub $pub }
    catch {
        if ($null -eq $PsaState.LastWriteRedirect) { throw }
        $first = [string]$_.Exception.Message
        # ConnectWise staging saved the note but didn't list it on a read made straight after the redirect,
        # so the read-back is tried again after short waits before the note is reported as not saved.
        $found = $false
        $waits = @(0) + @($PsaState.ReadBackWaits | Where-Object { $null -ne $_ })
        $tries = 0
        foreach ($wait in $waits) {
            if ($wait -gt 0) { Start-Sleep -Seconds $wait }
            $tries++
            try { $found = Test-PsaNoteSaved -Id $Id -Text $Text -Tag $tag }
            catch { throw "$first Reading ticket $Id back to check also failed: $($_.Exception.Message)" }
            if ($found) { break }
        }
        if (-not $found) { throw "$first Reading ticket $Id back ($tries times over $(($waits | Measure-Object -Sum).Sum) seconds) found no such note, so it was not saved." }
        Add-PsaWarning "$(Get-PsaName) answered the note on ticket $Id with a redirect; reading the ticket back showed the note was saved, so it was not sent again."
    }
    if ($tag) { return 'written' }
}
# $true when the note just sent is on the ticket: by its marker (or a public note's Ref line) when it has one,
# otherwise by its text (case, spaces and line breaks ignored).
function Test-PsaNoteSaved {
    param([string]$Id, [string]$Text, [string]$Tag = '')
    $notes = @(Get-PsaTicketNotes -Id $Id -TextOnly)
    if ($Tag) { return (Test-PsaNoteMarker -Id $Id -Marker $Tag -Notes $notes) }
    $want = ((ConvertTo-PsaPlainText $Text) -replace '\s+', ' ').Trim()
    if (-not $want) { return $false }
    foreach ($n in $notes) {
        $have = ((ConvertTo-PsaPlainText ([string]$n.text)) -replace '\s+', ' ').Trim()
        if ($have.IndexOf($want, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}
# The PSA call behind Add-PsaNote (no marker check, no read-back).
function Send-PsaNote {
    param([string]$Id, [string]$Text, [string]$Title, [bool]$Pub)
    $c = Get-PsaConn
    switch ($c.Psa) {
        'connectwise' {
            # Public notes go on the Discussion tab (detailDescriptionFlag). Unverified for public notes; internal is [ext].
            $null = Invoke-Psa POST "/service/tickets/$Id/notes" @{ text = $Text; internalAnalysisFlag = (-not $pub); detailDescriptionFlag = $pub; resolutionFlag = $false }
        }
        'autotask' {
            $pv = $null
            if ($pub) {
                # Unverified: which publish label makes a note client-visible. Tries "All Autotask Users" style labels.
                $pv = Get-PsaSecret 'Autotask-NotePublicPublishId'
                if (-not $pv) { $pv = Select-PsaAtValue (Get-PsaAtPicklist 'TicketNotes' 'publish') @('(?i)^All Autotask Users$', '(?i)^All', '(?i)public') }
            }
            else {
                $pv = Get-PsaSecret 'Autotask-NotePublishId'
                if (-not $pv) { $pv = Select-PsaAtValue (Get-PsaAtPicklist 'TicketNotes' 'publish') @('^Internal Only$', 'Internal') }
            }
            $type = Get-PsaSecret 'Autotask-NoteTypeId'
            if (-not $type) { $vals = @(Get-PsaAtPicklist 'TicketNotes' 'noteType' | Where-Object { [string](Get-PsaProp $_ 'value') -ne '13' -and [string](Get-PsaProp $_ 'label') -notmatch 'Workflow' }); $type = Select-PsaAtValue $vals @('Internal', 'Task Detail', 'Detail', '.') }
            if ($null -eq $pv -or $null -eq $type) { throw 'Could not find the Autotask note publish and type values. Set the Autotask-NotePublishId and Autotask-NoteTypeId secrets.' }
            $null = Invoke-Psa POST "/Tickets/$Id/Notes" @{ ticketID = [long]$Id; title = $Title; description = $Text; noteType = [int]$type; publish = [int]$pv }
        }
        'halopsa' {
            # Unverified: outcome ids are per tenant; 7 is the built-in Private Note. Halo-NoteOutcomeId overrides it.
            $outcome = Get-PsaSecret $(if ($pub) { 'Halo-PublicNoteOutcomeId' } else { 'Halo-NoteOutcomeId' })
            if (-not $outcome) { $outcome = Get-PsaSecret 'Halo-NoteOutcomeId' }
            if (-not $outcome) { $outcome = 7 }
            $null = Invoke-Psa POST '/Actions' @(@{ ticket_id = [long]$Id; note = $Text; hiddenfromuser = (-not $pub); outcome_id = [int]$outcome })
        }
        'kaseyabms' {
            # Unverified: how to list note types, so the KaseyaBMS-NoteTypeId secret supplies one.
            $type = Get-PsaSecret 'KaseyaBMS-NoteTypeId'
            if (-not $type) { throw 'Kaseya BMS notes need a note type id. Set the KaseyaBMS-NoteTypeId secret.' }
            $null = Invoke-Psa POST "/servicedesk/tickets/$Id/notes" @{ Details = $Text; IsInternal = (-not $pub); NoteDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); TypeId = [int]$type }
        }
        'syncro' { $null = Invoke-Psa POST "/tickets/$Id/comment" @{ subject = $Title; body = $Text; hidden = (-not $pub); do_not_email = (-not $pub) } }
        'zendesk' { $null = Invoke-Psa PUT "/tickets/$Id" @{ ticket = @{ comment = @{ body = $Text; public = $pub } } } }
    }
}

# Assigns the ticket. Autotask also needs the resource's role id.
function Set-PsaAssignee {
    param([string]$Id, [string]$UserId, [string]$RoleId = '')
    $c = Get-PsaConn
    switch ($c.Psa) {
        'connectwise' {
            $val = if ($UserId -match '^\d+$') { @{ id = [int]$UserId } } else { @{ identifier = $UserId } }
            $null = Invoke-Psa PATCH "/service/tickets/$Id" @([ordered]@{ op = 'replace'; path = 'owner'; value = $val })
        }
        'autotask' {
            if (-not $RoleId) { throw 'Autotask needs the resource role id as well as the resource id.' }
            $null = Invoke-Psa PATCH '/Tickets' ([ordered]@{ id = [long]$Id; assignedResourceID = [long]$UserId; assignedResourceRoleID = [long]$RoleId })
        }
        'halopsa' { $null = Invoke-Psa POST '/Tickets' @([ordered]@{ id = [long]$Id; agent_id = [long]$UserId }) }
        'kaseyabms' { $null = Invoke-Psa PATCH "/servicedesk/tickets/$Id" @([ordered]@{ op = 'replace'; path = '/AssigneeId'; value = [long]$UserId }) }
        'syncro' { $null = Invoke-Psa PUT "/tickets/$Id" @{ user_id = [long]$UserId } }
        'zendesk' { $null = Invoke-Psa PUT "/tickets/$Id" @{ ticket = @{ assignee_id = [long]$UserId } } }
    }
}

# Closes or reopens a ticket. -StatusName picks an exact status (a name, or an id for HaloPSA and Kaseya BMS).
# Returns the status that was set.
function Set-PsaStatus {
    param([string]$Id, [ValidateSet('closed', 'open')][string]$State = 'closed', [string]$StatusName = '')
    $c = Get-PsaConn
    $closed = $State -eq 'closed'
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: not in PSA.md yet. Statuses belong to the ticket's board; closedStatus and defaultFlag pick one.
            $t = Invoke-Psa GET "/service/tickets/$Id"
            $boardId = Get-PsaPath $t 'board.id'
            if (Test-PsaBlank $boardId) { throw "ConnectWise ticket $Id has no board, so its statuses can't be read." }
            $all = @(Invoke-Psa GET "/service/boards/$boardId/statuses?pageSize=200" | Where-Object { $null -ne $_ -and (Get-PsaProp $_ 'inactive') -ne $true })
            $st = $null
            if ($StatusName) { $st = @($all | Where-Object { [string](Get-PsaProp $_ 'name') -eq $StatusName }) | Select-Object -First 1 }
            elseif ($closed) { $cl = @($all | Where-Object { (Get-PsaProp $_ 'closedStatus') -eq $true }); $st = Select-PsaByLabel $cl 'name' @('(?i)resolved', '(?i)closed', '(?i)complete', '.') }
            else { $op = @($all | Where-Object { (Get-PsaProp $_ 'closedStatus') -ne $true }); $st = @($op | Where-Object { (Get-PsaProp $_ 'defaultFlag') -eq $true }) | Select-Object -First 1; if (-not $st) { $st = Select-PsaByLabel $op 'name' @('(?i)^new', '(?i)open', '.') } }
            if (-not $st) { throw "No $(if ($StatusName) { "'$StatusName'" } else { $State }) status on ConnectWise board $boardId." }
            $null = Invoke-Psa PATCH "/service/tickets/$Id" @([ordered]@{ op = 'replace'; path = 'status'; value = @{ id = [int](Get-PsaProp $st 'id') } })
            return [string](Get-PsaProp $st 'name')
        }
        'autotask' {
            # Unverified: not in PSA.md yet. Uses the status picklist (Complete = 5 and New = 1 by default) and at_update_ticket's PATCH.
            $vals = Get-PsaAtPicklist 'Tickets' 'status'
            $pats = if ($StatusName) { @("^$([regex]::Escape($StatusName))$") } elseif ($closed) { @('(?i)^complete$', '(?i)complete') } else { @('(?i)^new$', '(?i)in progress') }
            $hit = Select-PsaByLabel $vals 'label' $pats
            $sv = if ($hit) { Get-PsaProp $hit 'value' } elseif ($StatusName) { $null } elseif ($closed) { 5 } else { 1 }
            if ($null -eq $sv) { throw "Autotask has no ticket status named '$StatusName'." }
            $null = Invoke-Psa PATCH '/Tickets' ([ordered]@{ id = [long]$Id; status = [int]$sv })
            return $(if ($hit) { [string](Get-PsaProp $hit 'label') } else { [string]$sv })
        }
        'halopsa' {
            # Unverified: not in PSA.md yet. 9 (Closed) and 1 (New) are Halo's out-of-box ids; Halo-ClosedStatusId and Halo-OpenStatusId override them.
            $sv = if ($StatusName) { $StatusName } elseif ($closed) { Get-PsaSecret 'Halo-ClosedStatusId' } else { Get-PsaSecret 'Halo-OpenStatusId' }
            if (-not $sv) { $sv = $(if ($closed) { 9 } else { 1 }) }
            if ([string]$sv -notmatch '^\d+$') { throw 'HaloPSA needs a numeric status id.' }
            $null = Invoke-Psa POST '/Tickets' @([ordered]@{ id = [long]$Id; status_id = [int]$sv })
            return [string]$sv
        }
        'kaseyabms' {
            # Unverified: not in PSA.md yet. Status ids are per tenant: KaseyaBMS-ClosedStatusId and KaseyaBMS-OpenStatusId.
            $sv = if ($StatusName) { $StatusName } elseif ($closed) { Get-PsaSecret 'KaseyaBMS-ClosedStatusId' } else { Get-PsaSecret 'KaseyaBMS-OpenStatusId' }
            if (-not $sv -or [string]$sv -notmatch '^\d+$') { throw "Kaseya BMS needs a status id. Set the KaseyaBMS-$(if ($closed) { 'Closed' } else { 'Open' })StatusId secret." }
            $null = Invoke-Psa PATCH "/servicedesk/tickets/$Id" @([ordered]@{ op = 'replace'; path = '/StatusId'; value = [int]$sv })
            return [string]$sv
        }
        'syncro' {
            # Unverified: not in PSA.md yet. Resolved and New are Syncro's default status labels.
            $sv = if ($StatusName) { $StatusName } elseif ($closed) { 'Resolved' } else { 'New' }
            $null = Invoke-Psa PUT "/tickets/$Id" @{ status = $sv }
            return $sv
        }
        'zendesk' {
            # The API can't set closed directly; solved closes on Zendesk's own schedule.
            $sv = if ($StatusName) { $StatusName.ToLowerInvariant() } elseif ($closed) { 'solved' } else { 'open' }
            $null = Invoke-Psa PUT "/tickets/$Id" @{ ticket = @{ status = $sv } }
            return $sv
        }
    }
}

# Looks a company up by name. Returns @(@{ id; name; exact; raw }) with exact (case-insensitive) matches first.
function Find-PsaCompany {
    param([string]$Name)
    $c = Get-PsaConn
    $n = ([string]$Name).Trim()
    if (-not $n) { throw 'Find-PsaCompany needs a name.' }
    $rows = @(); $idProp = 'id'; $nameProp = 'name'
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: not in PSA.md yet. Uses the documented conditions syntax (strings in double quotes).
            $q = $n.Replace('\', '\\').Replace('"', '\"')
            # Build each condition first: an escaped quote inside a string inside $(...) ends the outer string.
            $exactCond = ConvertTo-PsaQuery ('name="' + $q + '" and deletedFlag=false')
            $rows = @(Invoke-Psa GET "/company/companies?conditions=$exactCond&pageSize=25")
            if (-not @($rows | Where-Object { $null -ne $_ }).Count) {
                $likeCond = ConvertTo-PsaQuery ('name contains "' + $q + '" and deletedFlag=false')
                $rows = @(Invoke-Psa GET "/company/companies?conditions=$likeCond&pageSize=25")
            }
        }
        'autotask' {
            # From the at_query_companies extension descriptor.
            $s = @{ filter = @([ordered]@{ op = 'eq'; field = 'companyName'; value = $n }) }
            $rows = @(Get-PsaProp (Invoke-Psa GET "/Companies/query?search=$(ConvertTo-PsaQuery ($s | ConvertTo-Json -Depth 5 -Compress))") 'items')
            if (-not @($rows | Where-Object { $null -ne $_ }).Count) {
                $s = @{ filter = @([ordered]@{ op = 'contains'; field = 'companyName'; value = $n }) }
                $rows = @(Get-PsaProp (Invoke-Psa GET "/Companies/query?search=$(ConvertTo-PsaQuery ($s | ConvertTo-Json -Depth 5 -Compress))") 'items')
            }
            $nameProp = 'companyName'
        }
        'halopsa' {
            # Unverified: not in PSA.md yet. GET /api/Client?search= (halo_query_clients) returns { clients: [...] }.
            $r = Invoke-Psa GET "/Client?search=$(ConvertTo-PsaQuery $n)&count=50"
            $rows = @(Get-PsaListReply $r @('clients'))
        }
        'kaseyabms' {
            # Unverified: not in PSA.md yet. The account list filter name is a guess; results are filtered here as well.
            $r = Invoke-Psa GET "/crm/accounts?Filter.Name=$(ConvertTo-PsaQuery $n)"
            $rows = @(Get-PsaProp $r 'Result'); $idProp = 'Id'; $nameProp = 'Name'
            if (@($rows | Where-Object { $null -ne $_ -and $null -eq (Get-PsaProp $_ 'Name') -and $null -ne (Get-PsaProp $_ 'AccountName') }).Count) { $nameProp = 'AccountName' }
            $rows = @($rows | Where-Object { $null -ne $_ -and ([string](Get-PsaProp $_ $nameProp)).IndexOf($n, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
        }
        'syncro' {
            # Unverified: not in PSA.md yet. GET /customers?query= returns { customers: [...] } with business_name.
            $rows = @(Get-PsaProp (Invoke-Psa GET "/customers?query=$(ConvertTo-PsaQuery $n)") 'customers'); $nameProp = 'business_name'
        }
        'zendesk' {
            # Unverified: not in PSA.md yet. Organization autocomplete matches names that start with the text.
            $rows = @(Get-PsaProp (Invoke-Psa GET "/organizations/autocomplete?name=$(ConvertTo-PsaQuery $n)") 'organizations')
        }
    }
    $out = @(foreach ($r in @($rows | Where-Object { $null -ne $_ })) {
            $nm = [string](Get-PsaProp $r $nameProp)
            if (-not $nm -and $c.Psa -eq 'syncro') { $nm = [string](Get-PsaProp $r 'fullname') }
            @{ id = [string](Get-PsaProp $r $idProp); name = $nm; exact = ($nm.Trim() -ieq $n); raw = $r }
        })
    return @(@($out | Where-Object { $_.exact }) + @($out | Where-Object { -not $_.exact }))
}

# How many open tickets the technician has: an int, or $null when this PSA can't count.
function Get-PsaOpenCount {
    param([string]$UserId)
    $c = Get-PsaConn
    switch ($c.Psa) {
        'connectwise' { return [int](Get-PsaProp (Invoke-Psa GET "/service/tickets/count?conditions=$(ConvertTo-PsaQuery "$(Get-PsaCwOwner $UserId) and closedFlag=false")") 'count') }
        'autotask' {
            # Unverified: the queryCount field name (PSA.md).
            $f = @([ordered]@{ op = 'eq'; field = 'assignedResourceID'; value = [long]$UserId }) + @(Get-PsaAtCompleteStatuses | ForEach-Object { [ordered]@{ op = 'noteq'; field = 'status'; value = $_ } })
            $r = Invoke-Psa GET "/Tickets/query/count?search=$(ConvertTo-PsaQuery (@{ filter = $f } | ConvertTo-Json -Depth 6 -Compress))"
            $n = Get-PsaProp $r 'queryCount'; if ($null -eq $n) { return $null }; return [int]$n
        }
        'halopsa' { $n = Get-PsaProp (Invoke-Psa GET "/Tickets?agent_id=$UserId&open_only=true&pageinate=true&page_size=1&page_no=1") 'record_count'; if ($null -eq $n) { return $null }; return [int]$n }
        'kaseyabms' { return $null }
        'syncro' {
            $r = Invoke-Psa GET "/tickets?user_id=$UserId&status=$(ConvertTo-PsaQuery 'Not Closed')&page=1"
            $te = Get-PsaPath $r 'meta.total_entries'; if ($null -ne $te) { return [int]$te }
            $n = @(Get-PsaProp $r 'tickets' | Where-Object { $null -ne $_ }).Count; $pages = [int](Get-PsaPath $r 'meta.total_pages')
            for ($p = 2; $p -le [Math]::Min($pages, 10); $p++) { $n += @(Get-PsaProp (Invoke-Psa GET "/tickets?user_id=$UserId&status=$(ConvertTo-PsaQuery 'Not Closed')&page=$p") 'tickets' | Where-Object { $null -ne $_ }).Count }
            if ($pages -gt 10) { return $null }
            return $n
        }
        'zendesk' { return [int](Get-PsaProp (Invoke-Psa GET "/search/count?query=$(ConvertTo-PsaQuery "type:ticket assignee:$UserId status<solved")") 'count') }
    }
}

# The newest ticket currently assigned to the technician: a date, [datetime]::MinValue
# when they have none, or $null when this PSA can't tell.
function Get-PsaLastAssigned {
    param([string]$UserId)
    $c = Get-PsaConn
    $none = [datetime]::MinValue
    $date = { param($v) if (Test-PsaBlank $v) { $none } else { [datetime]::Parse([string]$v, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal) } }
    switch ($c.Psa) {
        'connectwise' { $r = @(Invoke-Psa GET "/service/tickets?conditions=$(ConvertTo-PsaQuery (Get-PsaCwOwner $UserId))&orderBy=$(ConvertTo-PsaQuery 'dateEntered desc')&pageSize=1&fields=id,dateEntered" | Where-Object { $null -ne $_ }); if (-not $r.Count) { return $none }; return (& $date (Get-PsaProp $r[0] 'dateEntered')) }
        'autotask' {
            # The query API can't sort, so take the highest id from the last 90 days.
            $since = (Get-Date).ToUniversalTime().AddDays(-90).ToString('yyyy-MM-ddTHH:mm:ssZ')
            $s = @{ filter = @([ordered]@{ op = 'eq'; field = 'assignedResourceID'; value = [long]$UserId }, [ordered]@{ op = 'gt'; field = 'createDate'; value = $since }); IncludeFields = @('id', 'createDate'); MaxRecords = 500 }
            $r = Invoke-Psa GET "/Tickets/query?search=$(ConvertTo-PsaQuery ($s | ConvertTo-Json -Depth 6 -Compress))"
            $top = @(Get-PsaProp $r 'items' | Where-Object { $null -ne $_ } | Sort-Object { [long](Get-PsaProp $_ 'id') } -Descending) | Select-Object -First 1
            if (-not $top) { return $none }; return (& $date (Get-PsaProp $top 'createDate'))
        }
        'halopsa' { $t = @(Get-PsaProp (Invoke-Psa GET "/Tickets?agent_id=$UserId&order=dateoccurred&orderdesc=true&pageinate=true&page_size=1&page_no=1") 'tickets' | Where-Object { $null -ne $_ }); if (-not $t.Count) { return $none }; return (& $date (Get-PsaProp $t[0] 'dateoccurred')) }
        'kaseyabms' { return $null }
        'syncro' {
            $latest = $none
            for ($p = 1; $p -le 10; $p++) {
                $r = Invoke-Psa GET "/tickets?user_id=$UserId&page=$p"
                foreach ($t in @(Get-PsaProp $r 'tickets' | Where-Object { $null -ne $_ })) { $d = & $date (Get-PsaProp $t 'created_at'); if ($d -gt $latest) { $latest = $d } }
                if ($p -ge [int](Get-PsaPath $r 'meta.total_pages')) { break }
            }
            return $latest
        }
        'zendesk' { $t = @(Get-PsaProp (Invoke-Psa GET "/search?query=$(ConvertTo-PsaQuery "type:ticket assignee:$UserId")&sort_by=created_at&sort_order=desc&per_page=1") 'results' | Where-Object { $null -ne $_ }); if (-not $t.Count) { return $none }; return (& $date (Get-PsaProp $t[0] 'created_at')) }
    }
}
# ======== Notes, statuses, links and single-ticket changes ========
# Merged from the service-desk builds' src/psa-extra.ps1 files (October 2026). Lists of tickets, time,
# contracts, invoices, contacts and SLA targets are in _shared/psa-tickets.ps1, pasted after this file.

# A UTC [datetime], or $null for blank, '0', unparseable or placeholder dates (HaloPSA writes 1900-01-01 for none).
function ConvertTo-PsaDate {
    param($Value)
    if ($null -eq $Value) { return $null }
    $d = [datetime]::MinValue
    if ($Value -is [datetime]) { $d = $Value }
    elseif ($Value -is [datetimeoffset]) { $d = $Value.UtcDateTime }
    else {
        $s = ([string]$Value).Trim()
        if (-not $s -or $s -eq '0') { return $null }
        $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
        if (-not [datetime]::TryParse($s, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$d)) { return $null }
    }
    if ($d.Kind -eq [DateTimeKind]::Local) { $d = $d.ToUniversalTime() }
    elseif ($d.Kind -eq [DateTimeKind]::Unspecified) { $d = [datetime]::SpecifyKind($d, [DateTimeKind]::Utc) }
    if ($d.Year -lt 1971) { return $null }
    return $d
}
# yyyy-MM-ddTHH:mm:ssZ, or '' for no date.
function Format-PsaDate { param($Value) $d = ConvertTo-PsaDate $Value; if ($null -eq $d) { return '' }; return $d.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) }
# Plain text from a note body that may be HTML.
function ConvertTo-PsaPlainText {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $t = $Text -replace '(?i)<br\s*/?>', "`n" -replace '(?i)</p>', "`n" -replace '<[^>]+>', ''
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    return ($t -replace "(`r?`n){3,}", "`n`n").Trim()
}
# The first non-blank property of $o among $Names (dotted paths work).
function Get-PsaFirst { param($o, [string[]]$Names) foreach ($n in $Names) { $v = Get-PsaPath $o $n; if (-not (Test-PsaBlank $v)) { return $v } }; return $null }
function Get-PsaNumber { param($v) if (Test-PsaBlank $v) { return 0.0 }; $n = 0.0; if ([double]::TryParse([string]$v, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return $n }; return 0.0 }
function Add-PsaWarning { param([string]$Text) if ($Text -and -not $PsaState.Warnings.Contains($Text)) { $null = $PsaState.Warnings.Add($Text) } }
# critical, high, medium or low for a PSA priority label ('' when it matches none).
function Get-PsaPriorityLevel {
    param([string]$Label)
    if ([string]::IsNullOrWhiteSpace($Label)) { return '' }
    foreach ($k in @('critical', 'high', 'medium', 'low')) { foreach ($p in $PsaState.PriorityPatterns[$k]) { if ($Label -match $p) { return $k } } }
    return ''
}

# A GET where a 403 becomes a plain sentence about the API user's permissions.
function Invoke-PsaRead {
    param([string]$Path, [string]$What = 'read tickets', [string]$Need = 'read service tickets and their notes')
    try { return Invoke-Psa GET $Path }
    catch {
        $m = [string]$_.Exception.Message
        if ($m -match '\(HTTP 403\)') { throw "$(Get-PsaName) refused to $What (HTTP 403). Give the API user permission to $Need, then run this again." }
        throw
    }
}
# Kaseya BMS list replies are {Success, Result}; Result may be the list or hold it. Unverified: the list shape.
function Get-PsaBmsList {
    param($Reply)
    $res = Get-PsaProp $Reply 'Result'
    if ($null -eq $res) { return @() }
    if ($res -is [array]) { return @($res | Where-Object { $null -ne $_ }) }
    foreach ($n in @('Items', 'Data', 'Tickets', 'Records')) { $v = Get-PsaProp $res $n; if ($null -ne $v) { return @($v | Where-Object { $null -ne $_ }) } }
    return @($res)
}
# Autotask query with paging (pageDetails.nextPageUrl). Returns the items, up to -Max.
function Invoke-PsaAtQuery {
    param([string]$Entity, [object[]]$Filter, [string[]]$Fields = @(), [int]$Max = 500, [string]$What = '')
    $s = [ordered]@{ filter = @($Filter); MaxRecords = [Math]::Min(500, [Math]::Max(1, $Max)) }
    if ($Fields.Count) { $s.IncludeFields = $Fields }
    $path = "/$Entity/query?search=$(ConvertTo-PsaQuery ($s | ConvertTo-Json -Depth 8 -Compress))"
    $out = New-Object System.Collections.ArrayList
    for ($p = 1; $p -le $PsaState.MaxPages -and $path; $p++) {
        $r = if ($What) { Invoke-PsaRead $path $What } else { Invoke-Psa GET $path }
        foreach ($i in @(Get-PsaProp $r 'items' | Where-Object { $null -ne $_ })) { $null = $out.Add($i) }
        if ($out.Count -ge $Max) { break }
        $path = [string](Get-PsaPath $r 'pageDetails.nextPageUrl')
    }
    return @($out | Select-Object -First $Max)
}

# ---- statuses ----
# The PSA's ticket statuses as @(@{ id; name }), for the PSAs that key statuses by id (Autotask, HaloPSA,
# Kaseya BMS). ConnectWise (per board), Syncro and Zendesk use names, so they return @(). Cached per connection.
function Get-PsaStatusList {
    $c = Get-PsaConn
    if ($null -ne $PsaState.Statuses) { return @($PsaState.Statuses) }
    $list = @()
    switch ($c.Psa) {
        'autotask' { $list = @(Get-PsaAtPicklist 'Tickets' 'status' | ForEach-Object { @{ id = [string](Get-PsaProp $_ 'value'); name = [string](Get-PsaProp $_ 'label') } }) }
        'halopsa' {
            # Unverified: GET /api/Status (HaloAPI Get-HaloStatus) returns an array of { id, name }.
            $r = Invoke-Psa GET '/Status'
            $rows = @(Get-PsaProp $r 'statuses'); if (-not @($rows | Where-Object { $null -ne $_ }).Count) { $rows = @($r) }
            $list = @($rows | Where-Object { $null -ne $_ -and $null -ne (Get-PsaProp $_ 'name') } | ForEach-Object { @{ id = [string](Get-PsaProp $_ 'id'); name = [string](Get-PsaProp $_ 'name') } })
        }
        'kaseyabms' {
            # Vendor docs (BMS swagger): GET /v2/system/statuses/lookup returns { Result: [{ Id, Name, IsActive }] }.
            $r = Invoke-Psa GET '/system/statuses/lookup'
            $list = @(Get-PsaBmsList $r | Where-Object { (Get-PsaProp $_ 'IsActive') -ne $false } | ForEach-Object { @{ id = [string](Get-PsaProp $_ 'Id'); name = [string](Get-PsaProp $_ 'Name') } })
        }
    }
    $PsaState.Statuses = @($list)
    return @($list)
}
# The id for a status name (Autotask, HaloPSA, Kaseya BMS). A number is returned as given; the PSAs that
# use names (ConnectWise, Syncro, Zendesk) get the name back. Throws a plain sentence listing the statuses.
function Get-PsaStatusId {
    param([string]$Name)
    $n = ([string]$Name).Trim()
    if ($n -match '^\d+$') { return $n }
    $c = Get-PsaConn
    if ($c.Psa -notin @('autotask', 'halopsa', 'kaseyabms')) { return $n }
    $list = @(Get-PsaStatusList)
    $hit = @($list | Where-Object { $_.name.Trim() -ieq $n }) | Select-Object -First 1
    if (-not $hit) { throw "$(Get-PsaName) has no ticket status named '$n'. Its statuses are: $((@($list | ForEach-Object { $_.name }) | Sort-Object -Unique) -join ', ')." }
    return $hit.id
}
# A readable status name. Autotask, HaloPSA and Kaseya BMS hand out ids; the others already use names.
# An id with no match comes back unchanged.
function Get-PsaStatusName {
    param([string]$Status)
    $s = ([string]$Status).Trim()
    if ($s -notmatch '^\d+$') { return $s }
    $c = Get-PsaConn
    if ($c.Psa -notin @('autotask', 'halopsa', 'kaseyabms')) { return $s }
    $list = @(); try { $list = @(Get-PsaStatusList) } catch { $list = @() }
    $hit = @($list | Where-Object { $_.id -eq $s }) | Select-Object -First 1
    if ($hit) { return $hit.name }
    return $s
}

# ---- links ----
# A link a technician can open, or '' when this PSA's link can't be worked out. No API call.
#   -Template  wins when given (an unfilled @token counts as blank); {id} or {ticketId} becomes the ticket id.
#   Otherwise the optional PSA-TicketUrlTemplate secret (same placeholders), then the PSA's usual link.
function Get-PsaTicketUrl {
    param([string]$Id, [string]$Template = '')
    $tpl = ([string]$Template).Trim()
    if (-not $tpl -or $tpl.StartsWith('@')) {
        if ($null -eq $PsaState.UrlTemplate) { $PsaState.UrlTemplate = [string](Get-PsaSecret 'PSA-TicketUrlTemplate') }
        $tpl = $PsaState.UrlTemplate
    }
    if ($tpl) { return ($tpl -replace '\{(id|ticketId)\}', [uri]::EscapeDataString($Id)) }
    if ($null -eq $PsaState.Conn) { return '' }
    $u = $null; try { $u = [uri]$PsaState.Conn.Base } catch { return '' }
    $root = "$($u.Scheme)://$($u.Authority)"
    switch ($PsaState.Conn.Psa) {
        # Unverified: the ticket screen; the API host api-na.myconnectwise.net serves the UI as na.myconnectwise.net.
        'connectwise' { return "$($u.Scheme)://$($u.Host -replace '^api-', '')/v4_6_release/services/system_io/Service/fv_sr100_request.rails?service_recid=$Id" }
        # Unverified: the web UI host mirrors the API zone host (webservices5 -> ww5).
        'autotask' { return "$($u.Scheme)://$($u.Host -replace '^webservices', 'ww')/Mvc/ServiceDesk/TicketDetail.mvc?ticketId=$Id" }
        # Unverified: the HaloPSA agent ticket link.
        'halopsa' { return "$root/tickets?id=$Id" }
        'kaseyabms' { return '' }
        # Unverified: the Syncro ticket page.
        'syncro' { return "$root/tickets/$Id" }
        'zendesk' { return "$root/agent/tickets/$Id" }
    }
    return ''
}

# ---- notes ----
# A ticket's notes, oldest first: @(@{ id; text; title; created; internal; public; fromClient; author; raw }).
#   created     UTC [datetime] or $null
#   internal    $true for a technician-only note; public is its opposite
#   fromClient  best effort (see each PSA); $false when the PSA doesn't say
#   -Ticket     a Find-PsaTickets row or Get-PsaTicket result, so Zendesk can tell the requester's comments apart
#   -Newest     newest first instead;  -Max  keep only the newest N
#   -TextOnly   skip the extra Zendesk ticket read that works out fromClient
# A 403 becomes a plain permission sentence. Other read failures throw.
function Get-PsaTicketNotes {
    param([string]$Id, $Ticket = $null, [switch]$Newest, [int]$Max = 0, [switch]$TextOnly)
    $c = Get-PsaConn
    $what = "read the notes on ticket $Id"
    $notes = New-Object System.Collections.ArrayList
    $add = {
        param($nid, $text, $title, $created, $internal, $fromClient, $author, $raw)
        $null = $notes.Add(@{ id = [string]$nid; text = [string]$text; title = [string]$title; created = (ConvertTo-PsaDate $created); internal = [bool]$internal; public = (-not [bool]$internal); fromClient = [bool]$fromClient; author = [string]$author; raw = $raw })
    }
    switch ($c.Psa) {
        'connectwise' {
            # Vendor docs: GET /service/tickets/{id}/notes. A note is internal when only the Internal tab flag is set.
            # Unverified: a note with a contact and no member was written by the client.
            for ($p = 1; $p -le $PsaState.MaxPages; $p++) {
                $page = @(Invoke-PsaRead "/service/tickets/$Id/notes?orderBy=$(ConvertTo-PsaQuery 'id asc')&pageSize=100&page=$p" $what | Where-Object { $null -ne $_ })
                foreach ($n in $page) {
                    $internal = ((Get-PsaProp $n 'internalAnalysisFlag') -eq $true -and (Get-PsaProp $n 'detailDescriptionFlag') -ne $true -and (Get-PsaProp $n 'resolutionFlag') -ne $true)
                    & $add (Get-PsaProp $n 'id') (Get-PsaProp $n 'text') '' (Get-PsaFirst $n @('dateCreated', '_info.dateEntered', '_info.lastUpdated')) $internal ($null -ne (Get-PsaProp $n 'contact') -and $null -eq (Get-PsaProp $n 'member')) ([string](Get-PsaFirst $n @('member.identifier', 'contact.name', 'createdBy'))) $n
                }
                if ($page.Count -lt 100) { break }
            }
        }
        'autotask' {
            # Unverified: TicketNotes query by ticketID. Internal is the publish value whose label says Internal;
            # createdByContactID set means the client wrote it.
            $internalIds = @(Get-PsaAtPicklist 'TicketNotes' 'publish' | Where-Object { [string](Get-PsaProp $_ 'label') -match '(?i)internal' } | ForEach-Object { [string](Get-PsaProp $_ 'value') })
            foreach ($n in @(Invoke-PsaAtQuery 'TicketNotes' @([ordered]@{ op = 'eq'; field = 'ticketID'; value = [long]$Id }) @() 5000 $what)) {
                $byContact = Get-PsaProp $n 'createdByContactID'
                & $add (Get-PsaProp $n 'id') (Get-PsaProp $n 'description') (Get-PsaProp $n 'title') (Get-PsaFirst $n @('createDateTime', 'lastActivityDate')) ($internalIds -contains [string](Get-PsaProp $n 'publish')) (-not (Test-PsaBlank $byContact)) ([string](Get-PsaFirst $n @('creatorResourceID', 'createdByContactID'))) $n
            }
        }
        'halopsa' {
            # Unverified: GET /api/Actions?ticket_id= returns { actions } with note (or note_html), hiddenfromuser and
            # datetime; who_type 2 is taken to mean the end user wrote it.
            $r = Invoke-PsaRead "/Actions?ticket_id=$Id&excludesys=true&count=500" $what
            $rows = @(Get-PsaListReply $r @('actions'))
            foreach ($n in @($rows | Where-Object { $null -ne $_ })) {
                & $add (Get-PsaProp $n 'id') (ConvertTo-PsaPlainText ([string](Get-PsaFirst $n @('note', 'note_html')))) ([string](Get-PsaProp $n 'outcome')) (Get-PsaFirst $n @('datetime', 'actiondatecreated')) ((Get-PsaProp $n 'hiddenfromuser') -eq $true) ([string](Get-PsaProp $n 'who_type') -eq '2') ([string](Get-PsaProp $n 'who')) $n
            }
        }
        'kaseyabms' {
            # Vendor docs (BMS swagger): GET /v2/servicedesk/tickets/{id}/notes returns { Result: [{ Id, Details, CreatedOn,
            # IsInternal, CreatedByName }] }. It doesn't say whether the client wrote a note, so fromClient is $false.
            foreach ($n in @(Get-PsaBmsList (Invoke-PsaRead "/servicedesk/tickets/$Id/notes?PageSize=200" $what))) {
                & $add (Get-PsaProp $n 'Id') (Get-PsaProp $n 'Details') '' (Get-PsaFirst $n @('CreatedOn', 'NoteDate')) ((Get-PsaProp $n 'IsInternal') -eq $true) $false ([string](Get-PsaProp $n 'CreatedByName')) $n
            }
        }
        'syncro' {
            # PSA.md (Get ticket): the ticket carries its comments; hidden marks a private one.
            # Unverified: a visible comment with no user_id was written by the client.
            $t = Get-PsaProp (Invoke-PsaRead "/tickets/$Id" $what) 'ticket'
            foreach ($n in @(Get-PsaProp $t 'comments' | Where-Object { $null -ne $_ })) {
                $hidden = (Get-PsaProp $n 'hidden') -eq $true
                & $add (Get-PsaProp $n 'id') (Get-PsaProp $n 'body') (Get-PsaProp $n 'subject') (Get-PsaProp $n 'created_at') $hidden ((-not $hidden) -and (Test-PsaBlank (Get-PsaProp $n 'user_id'))) ([string](Get-PsaProp $n 'tech')) $n
            }
        }
        'zendesk' {
            # Vendor docs: GET /tickets/{id}/comments with next_page paging. The client wrote it when the author is the requester.
            $req = ''
            if (-not $TextOnly) {
                if ($null -ne $Ticket) { $req = [string](Get-PsaFirst $Ticket @('contactId', 'requesterId', 'raw.requester_id', 'requester_id')) }
                if (-not $req) { $req = [string](Get-PsaPath (Invoke-PsaRead "/tickets/$Id" $what) 'ticket.requester_id') }
            }
            $path = "/tickets/$Id/comments?sort_order=asc&per_page=100"
            for ($p = 1; $p -le $PsaState.MaxPages -and $path; $p++) {
                $r = Invoke-PsaRead $path $what
                foreach ($n in @(Get-PsaProp $r 'comments' | Where-Object { $null -ne $_ })) {
                    $author = [string](Get-PsaProp $n 'author_id')
                    & $add (Get-PsaProp $n 'id') (Get-PsaProp $n 'body') '' (Get-PsaProp $n 'created_at') ((Get-PsaProp $n 'public') -eq $false) ([bool]$req -and $author -eq $req) $author $n
                }
                $path = [string](Get-PsaProp $r 'next_page')
            }
        }
    }
    # Oldest first by date; notes without a date keep the PSA's order.
    $i = 0
    $keyed = @(foreach ($n in $notes) { $i++; [pscustomobject]@{ d = $(if ($null -eq $n.created) { [datetime]::MinValue } else { $n.created }); i = $i; n = $n } })
    $sorted = @($keyed | Sort-Object -Property @{ Expression = 'd' }, @{ Expression = 'i' } | ForEach-Object { $_.n })
    if ($Max -gt 0 -and $sorted.Count -gt $Max) { $sorted = @($sorted | Select-Object -Last $Max) }
    if ($Newest) { [array]::Reverse($sorted) }
    return @($sorted)
}

# "[marker]" for a marker given with or without its brackets.
function Get-PsaMarkerTag {
    param([string]$Marker)
    $m = ([string]$Marker).Trim()
    if ($m.StartsWith('[') -and $m.EndsWith(']')) { $m = $m.Substring(1, $m.Length - 2).Trim() }
    if (-not $m) { throw 'A note marker needs some text.' }
    if ($m -match '[\[\]\r\n]') { throw "A note marker can't contain brackets or line breaks ('$Marker')." }
    return "[$m]"
}
# The opaque line a public note shows instead of its marker: "Ref: " and the first 8 hex characters
# (lowercase) of the SHA-256 of "[marker]" lowercased, as UTF-8. It reveals nothing of the marker text.
function Get-PsaMarkerRef {
    param([string]$Marker)
    $tag = (Get-PsaMarkerTag $Marker).ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($tag)) } finally { $sha.Dispose() }
    return 'Ref: ' + ((@($h[0..3] | ForEach-Object { $_.ToString('x2') })) -join '')
}
# $true when $Text holds the "Ref: xxxxxxxx" line $Ref (case-insensitive, not part of a longer hex run).
function Test-PsaMarkerRefIn {
    param([string]$Text, [string]$Ref)
    if (-not $Text) { return $false }
    $hex = ([string]$Ref -replace '^(?i)Ref:\s*', '')
    return ($Text -match "(?i)(?<![0-9a-z])Ref:\s*$([regex]::Escape($hex))(?![0-9a-f])")
}
# $true when a note on the ticket already holds the marker (case-insensitive): either the full "[marker]"
# (internal notes, and public notes written before public notes switched to the opaque ref) or the
# "Ref: xxxxxxxx" line a public note carries. Pass -Notes to reuse notes already read with
# Get-PsaTicketNotes. Throws when the notes can't be read.
function Test-PsaNoteMarker {
    param([string]$Id, [string]$Marker, $Notes = $null)
    $tag = Get-PsaMarkerTag $Marker
    $ref = Get-PsaMarkerRef $tag
    if ($null -eq $Notes) {
        try { $Notes = @(Get-PsaTicketNotes -Id $Id -TextOnly) }
        catch { throw "Couldn't check ticket $Id for an earlier note marked $tag, so nothing was written: $($_.Exception.Message)" }
    }
    foreach ($n in @($Notes)) {
        if ($null -eq $n) { continue }
        $t = if ($n -is [string]) { $n } else { [string](Get-PsaProp $n 'text') }
        if ($t.IndexOf($tag, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
        if (Test-PsaMarkerRefIn $t $ref) { return $true }
    }
    return $false
}

# ---- single-ticket changes ----
# Closes a ticket to -StatusName, or to the PSA's usual closed status, and never to -NotStatus (for example
# the Resolved status a ticket is already in). Returns the status that was set.
function Close-PsaTicket {
    param([string]$Id, [string]$StatusName = '', [string]$NotStatus = '')
    $c = Get-PsaConn
    $StatusName = ([string]$StatusName).Trim(); $NotStatus = ([string]$NotStatus).Trim()
    if ($StatusName -and $NotStatus -and $StatusName -ieq $NotStatus) { throw "The closing status '$StatusName' is the status the ticket is already in. Choose a different closing status." }
    switch ($c.Psa) {
        'connectwise' {
            if ($StatusName) { return (Set-PsaStatus -Id $Id -StatusName $StatusName) }
            # Unverified (as Set-PsaStatus): the board's statuses with closedStatus set; skips -NotStatus.
            $t = Invoke-Psa GET "/service/tickets/$Id"
            $boardId = Get-PsaPath $t 'board.id'
            if (Test-PsaBlank $boardId) { throw "ConnectWise ticket $Id has no board, so its statuses can't be read." }
            $all = @(Invoke-Psa GET "/service/boards/$boardId/statuses?pageSize=200" | Where-Object { $null -ne $_ -and (Get-PsaProp $_ 'inactive') -ne $true -and (Get-PsaProp $_ 'closedStatus') -eq $true -and ([string](Get-PsaProp $_ 'name')).Trim() -ine $NotStatus })
            $st = Select-PsaByLabel $all 'name' @('(?i)^\W*closed\W*$', '(?i)closed', '(?i)complete', '(?i)resolved', '.')
            if (-not $st) { throw "ConnectWise board $boardId has no closed status other than '$NotStatus'. Set the closing status name." }
            return (Set-PsaStatus -Id $Id -StatusName ([string](Get-PsaProp $st 'name')))
        }
        'autotask' {
            if (-not $StatusName -and $NotStatus -imatch '^complete$') { throw "'$NotStatus' is already Autotask's closed status. Set the closing status name." }
            if ($StatusName) { return (Set-PsaStatus -Id $Id -StatusName $StatusName) }
            return (Set-PsaStatus -Id $Id -State closed)
        }
        { $_ -in @('halopsa', 'kaseyabms') } {
            if ($StatusName) { return (Set-PsaStatus -Id $Id -StatusName (Get-PsaStatusId $StatusName)) }
            return (Set-PsaStatus -Id $Id -State closed)
        }
        'syncro' {
            # Unverified (as Set-PsaStatus): Resolved is Syncro's default closed label.
            $target = if ($StatusName) { $StatusName } else { 'Resolved' }
            if ($target -ieq $NotStatus) { throw "In Syncro, '$NotStatus' is already the closed status, so there is nothing to close. Set the closing status name, or use a different status for tickets waiting to be closed." }
            return (Set-PsaStatus -Id $Id -StatusName $target)
        }
        'zendesk' {
            # Unverified: setting status closed through the API. Zendesk otherwise closes solved tickets on its own schedule.
            $target = if ($StatusName) { $StatusName.ToLowerInvariant() } elseif ($NotStatus -ieq 'solved') { 'closed' } else { 'solved' }
            return (Set-PsaStatus -Id $Id -StatusName $target)
        }
    }
}

# Moves a ticket to another board (ConnectWise), queue (Autotask, Kaseya BMS), team (HaloPSA), issue type (Syncro)
# or group (Zendesk). -Queue is a name or an id. Throws when the PSA refuses.
function Set-PsaQueue {
    param([string]$Id, [string]$Queue)
    $c = Get-PsaConn
    if ([string]::IsNullOrWhiteSpace($Queue)) { throw 'Set-PsaQueue needs a queue name or id.' }
    $q = $Queue.Trim(); $isNum = $q -match '^\d+$'
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: json-patch on board (a reference, so {id} or {name}). CW may refuse when the status doesn't exist on the new board.
            $val = if ($isNum) { @{ id = [int]$q } } else { @{ name = $q } }
            $null = Invoke-Psa PATCH "/service/tickets/$Id" @([ordered]@{ op = 'replace'; path = 'board'; value = $val })
        }
        'autotask' {
            # Unverified: PATCH /Tickets with queueID (the field at_create_ticket uses).
            $qv = if ($isNum) { $q } else { Select-PsaAtValue (Get-PsaAtPicklist 'Tickets' 'queueID') @("(?i)^$([regex]::Escape($q))$") }
            if ($null -eq $qv) { throw "Autotask has no ticket queue named '$q'." }
            $null = Invoke-Psa PATCH '/Tickets' ([ordered]@{ id = [long]$Id; queueID = [int]$qv })
        }
        'halopsa' {
            # Unverified: team_id or team (name) on the POST /Tickets update.
            $b = [ordered]@{ id = [long]$Id }; if ($isNum) { $b.team_id = [long]$q } else { $b.team = $q }
            $null = Invoke-Psa POST '/Tickets' @($b)
        }
        'kaseyabms' {
            # Unverified: json-patch on /QueueId.
            if (-not $isNum) { throw 'Kaseya BMS needs a numeric queue id.' }
            $null = Invoke-Psa PATCH "/servicedesk/tickets/$Id" @([ordered]@{ op = 'replace'; path = '/QueueId'; value = [int]$q })
        }
        'syncro' {
            # Unverified: Syncro has no queues; the issue type (problem_type) is the closest field.
            $null = Invoke-Psa PUT "/tickets/$Id" @{ problem_type = $q }
        }
        'zendesk' {
            # group_id on PUT /tickets is in PSA.md. Unverified: the GET /groups name lookup.
            $gid = $q
            if (-not $isNum) {
                $g = @(Get-PsaProp (Invoke-Psa GET '/groups?per_page=100') 'groups' | Where-Object { $null -ne $_ -and [string](Get-PsaProp $_ 'name') -ieq $q }) | Select-Object -First 1
                if (-not $g) { throw "Zendesk has no group named '$q'." }
                $gid = [string](Get-PsaProp $g 'id')
            }
            $null = Invoke-Psa PUT "/tickets/$Id" @{ ticket = @{ group_id = [long]$gid } }
        }
    }
}

# Sets a ticket's contact (the requester in Zendesk). Throws when the PSA rejects it.
function Set-PsaTicketContact {
    param([string]$Id, [string]$ContactId)
    $c = Get-PsaConn
    if ($ContactId -notmatch '^\d+$') { throw "Set-PsaTicketContact needs a numeric contact id (it was '$ContactId')." }
    switch ($c.Psa) {
        # Unverified: json-patch on contact, the same shape as owner (PSA.md).
        'connectwise' { $null = Invoke-Psa PATCH "/service/tickets/$Id" @([ordered]@{ op = 'replace'; path = 'contact'; value = @{ id = [int]$ContactId } }) }
        # Unverified: PATCH /Tickets with contactID, the at_update_ticket shape.
        'autotask' { $null = Invoke-Psa PATCH '/Tickets' ([ordered]@{ id = [long]$Id; contactID = [long]$ContactId }) }
        # Unverified: POST /Tickets with user_id updates the end user.
        'halopsa' { $null = Invoke-Psa POST '/Tickets' @([ordered]@{ id = [long]$Id; user_id = [long]$ContactId }) }
        # Vendor docs: PATCH /v2/servicedesk/tickets/{id} json-patch; ContactId is a ticket field. Unverified live.
        'kaseyabms' { $null = Invoke-Psa PATCH "/servicedesk/tickets/$Id" @([ordered]@{ op = 'replace'; path = '/ContactId'; value = [long]$ContactId }) }
        # Vendor docs: PUT /tickets/{id} takes contact_id in a flat body. Unverified live.
        'syncro' { $null = Invoke-Psa PUT "/tickets/$Id" @{ contact_id = [long]$ContactId } }
        # Vendor docs: requester_id on the ticket. Unverified live.
        'zendesk' { $null = Invoke-Psa PUT "/tickets/$Id" @{ ticket = @{ requester_id = [long]$ContactId } } }
    }
}

# Autotask assigns a resource together with a role. Returns the resource's default Service Desk role id, or ''.
# The other PSAs don't need a role and get '' with no call.
function Get-PsaDefaultRole {
    param([string]$UserId)
    $c = Get-PsaConn
    if ($c.Psa -ne 'autotask' -or [string]::IsNullOrWhiteSpace($UserId)) { return '' }
    # Unverified: defaultServiceDeskRoleID on the Resources entity.
    $v = Get-PsaPath (Invoke-Psa GET "/Resources/$UserId") 'item.defaultServiceDeskRoleID'
    if (Test-PsaBlank $v) { return '' }
    return [string]$v
}

# A run's "company" input as a PSA company: a numeric id is used as given; a name must match exactly one
# company (Find-PsaCompany, case-insensitive). Returns @{ id; name }, or @{ id = ''; name = '' } for blank or an
# unfilled @token. Throws a plain sentence when the name matches none or several.
function Resolve-PsaCompanyId {
    param([string]$Company)
    $v = ([string]$Company).Trim()
    if (-not $v -or $v.StartsWith('@')) { return @{ id = ''; name = '' } }
    if ($v -match '^\d+$') { return @{ id = $v; name = '' } }
    $hits = @(Find-PsaCompany -Name $v | Where-Object { $_.exact })
    if (-not $hits.Count) { throw "$(Get-PsaName) has no company named '$v'. Use the exact company name or the PSA company id." }
    if ($hits.Count -gt 1) { throw "$(Get-PsaName) has $($hits.Count) companies named '$v'. Use the PSA company id instead." }
    return @{ id = [string]$hits[0].id; name = [string]$hits[0].name }
}

# A ticket number as people see it, turned into the PSA's internal id. ConnectWise, HaloPSA and Zendesk show
# the id itself; Autotask and Kaseya BMS show numbers like T20261008.0001; Syncro shows a number that differs
# from its id. A leading # is ignored. Throws when the ticket isn't found.
function Resolve-PsaTicketId {
    param([string]$Ref)
    $c = Get-PsaConn
    $r = ([string]$Ref).Trim().TrimStart('#')
    if (-not $r) { throw 'No ticket number was given.' }
    switch ($c.Psa) {
        'autotask' {
            if ($r -match '^\d+$') { return $r }
            # Unverified: querying Tickets by ticketNumber.
            $hit = @(Invoke-PsaAtQuery 'Tickets' @([ordered]@{ op = 'eq'; field = 'ticketNumber'; value = $r }) @('id', 'ticketNumber') 1) | Select-Object -First 1
            if (-not $hit) { throw "Autotask has no ticket $r." }
            return [string](Get-PsaProp $hit 'id')
        }
        'kaseyabms' {
            if ($r -match '^\d+$') { return $r }
            # Unverified: the Filter.TicketNumber list filter.
            $hit = @(Get-PsaBmsList (Invoke-Psa GET "/servicedesk/tickets?Filter.TicketNumber=$(ConvertTo-PsaQuery $r)&PageSize=5") | Where-Object { [string](Get-PsaProp $_ 'TicketNumber') -eq $r }) | Select-Object -First 1
            if (-not $hit) { throw "Kaseya BMS has no ticket $r." }
            return [string](Get-PsaProp $hit 'Id')
        }
        'syncro' {
            if ($r -notmatch '^\d+$') { throw "Syncro ticket numbers are numeric; '$r' isn't." }
            # Unverified: GET /tickets?number= filters on the number customers see. Falls back to treating it as the id.
            $rows = @()
            try { $rows = @(Get-PsaProp (Invoke-Psa GET "/tickets?number=$r") 'tickets' | Where-Object { $null -ne $_ -and [string](Get-PsaProp $_ 'number') -eq $r }) } catch { $rows = @() }
            if ($rows.Count) { return [string](Get-PsaProp $rows[0] 'id') }
            return $r
        }
        default {
            if ($r -notmatch '^\d+$') { throw "$(Get-PsaName) ticket numbers are numeric; '$r' isn't." }
            return $r
        }
    }
}
# ---------- end _shared/psa.ps1 ----------
