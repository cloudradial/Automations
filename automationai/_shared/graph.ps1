# ---------- _shared/graph.ps1: Microsoft Graph for AutomationAI steps ----------
# Edit this file, then run: node automationai/_shared/inject.js <automation-folder>
# Signs in with the app registration's client credentials from the runner Key Vault.
# Each helper names the Graph application permission it needs; when Graph answers 403,
# the error says which permission to grant (with admin consent).
# All state lives in the $GraphState hashtable and is changed in place, because the runner
# runs a step in a child scope where $script: variables don't behave.

$GraphState = @{
    Base           = 'https://graph.microsoft.com'
    Headers        = $null
    Creds          = $null
    TenantId       = ''
    ExpiresAt      = [datetime]::MinValue
    MaxAttempts    = 5
    MaxWaitSeconds = 120
    LastStatus     = 0
}

# ---- small helpers (all Graph-prefixed so they don't clash with other shared files) ----
# The first secret that has a value, from a list of names.
function Get-GraphSecret { param([string[]]$Names) foreach ($n in $Names) { $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $n -AsPlainText -ErrorAction SilentlyContinue } catch { }; if (-not [string]::IsNullOrWhiteSpace($v)) { return $v } }; return $null }
function Get-GraphProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-GraphHttpStatus { param($Err) $c = 0; try { $c = [int]$Err.Exception.Response.StatusCode } catch { }; return $c }
function Get-GraphRetryAfter {
    param($Err, [int]$Attempt)
    $s = 0
    try {
        $ra = $Err.Exception.Response.Headers.RetryAfter
        if ($null -ne $ra -and $null -ne $ra.Delta) { $s = [int][Math]::Ceiling($ra.Delta.TotalSeconds) }
        elseif ($null -ne $ra -and $null -ne $ra.Date) { $s = [int][Math]::Ceiling(($ra.Date.UtcDateTime - [datetime]::UtcNow).TotalSeconds) }
    } catch { }
    if ($s -le 0) { $s = [int][Math]::Min(60, [Math]::Pow(2, $Attempt)) }
    return [int][Math]::Min($s, $GraphState.MaxWaitSeconds)
}
# Graph's own error message when there is one, otherwise the exception text.
function Get-GraphErrorText {
    param($Err)
    $d = $null; try { if ($Err.ErrorDetails -and $Err.ErrorDetails.Message) { $d = $Err.ErrorDetails.Message } } catch { }
    if ($d) { try { $j = $d | ConvertFrom-Json -ErrorAction Stop; $m = Get-GraphProp (Get-GraphProp $j 'error') 'message'; if (-not $m) { $m = Get-GraphProp $j 'error_description' }; if ($m) { return [string]$m } } catch { }; return $d }
    return [string]$Err.Exception.Message
}
function ConvertTo-GraphId { param([string]$Id) return [uri]::EscapeDataString($Id.Trim()) }

function Update-GraphToken {
    $c = $GraphState.Creds
    if ($null -eq $c) { throw 'Call Connect-Graph before any other Graph function.' }
    $r = $null
    try { $r = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$($c.TenantId)/oauth2/v2.0/token" -Body @{ client_id = $c.ClientId; client_secret = $c.ClientSecret; scope = 'https://graph.microsoft.com/.default'; grant_type = 'client_credentials' } -ErrorAction Stop }
    catch { throw "Couldn't get a Microsoft Graph token for tenant $($c.TenantId): $(Get-GraphErrorText $_). Check the M365-TenantId, M365-ClientId and M365-ClientSecret secrets." }
    $tok = Get-GraphProp $r 'access_token'
    if (-not $tok) { throw 'Microsoft sign-in returned no access token. Check the M365-ClientId and M365-ClientSecret secrets.' }
    $GraphState.Headers = @{ Authorization = "Bearer $tok"; 'Content-Type' = 'application/json' }
    $exp = 3600; $e = Get-GraphProp $r 'expires_in'; if ($null -ne $e -and [string]$e -match '^\d+$') { $exp = [int]$e }
    $GraphState.ExpiresAt = (Get-Date).AddSeconds([Math]::Max(60, $exp - 300))
}

# Signs in with client credentials. With no parameters it reads the runner Key Vault, trying each
# name in turn: M365-TenantId / M365-TenantID / Entra-TenantID / Graph-TenantId, M365-ClientId /
# M365-ClientID / Entra-ClientID / Graph-ClientId, and M365-ClientSecret / Entra-ClientSecret / Graph-ClientSecret.
# Returns @{ TenantId }.
function Connect-Graph {
    param([string]$TenantId, [string]$ClientId, [string]$ClientSecret)
    if ([string]::IsNullOrWhiteSpace($TenantId)) { $TenantId = Get-GraphSecret @('M365-TenantId', 'M365-TenantID', 'Entra-TenantID', 'Graph-TenantId') }
    if ([string]::IsNullOrWhiteSpace($ClientId)) { $ClientId = Get-GraphSecret @('M365-ClientId', 'M365-ClientID', 'Entra-ClientID', 'Graph-ClientId') }
    if ([string]::IsNullOrWhiteSpace($ClientSecret)) { $ClientSecret = Get-GraphSecret @('M365-ClientSecret', 'Entra-ClientSecret', 'Graph-ClientSecret') }
    $missing = @()
    if ([string]::IsNullOrWhiteSpace($TenantId)) { $missing += 'M365-TenantId' }
    if ([string]::IsNullOrWhiteSpace($ClientId)) { $missing += 'M365-ClientId' }
    if ([string]::IsNullOrWhiteSpace($ClientSecret)) { $missing += 'M365-ClientSecret' }
    if ($missing.Count) { throw "Add these secrets to the runner Key Vault: $($missing -join ', ') (the Entra-* and Graph-* names work too)." }
    $GraphState.Creds = @{ TenantId = $TenantId.Trim(); ClientId = $ClientId.Trim(); ClientSecret = $ClientSecret }
    $GraphState.TenantId = $TenantId.Trim()
    Update-GraphToken
    return @{ TenantId = $GraphState.TenantId }
}

# One Graph call. Path is '/v1.0/...', '/beta/...', a path without a version (v1.0 is added), or a full URL.
# Retries 429, 503 and 504 honoring Retry-After, refreshes the token once on 401, and on 403 throws a
# message naming -Permission. Other failures throw "Microsoft Graph <method> <path> failed (HTTP n): <reason>".
# $GraphState.LastStatus holds the last HTTP status, so a caller can treat 404 as "not found".
function Invoke-Graph {
    param([string]$Method = 'GET', [string]$Path, $Body = $null, [string]$Permission = '', [hashtable]$Headers = @{})
    if ($null -eq $GraphState.Creds) { throw 'Call Connect-Graph before any other Graph function.' }
    $uri = if ($Path -match '^https?://') { $Path } elseif ($Path -match '^/(v1\.0|beta)/') { "$($GraphState.Base)$Path" } else { "$($GraphState.Base)/v1.0/$($Path.TrimStart('/'))" }
    $short = $uri.Replace($GraphState.Base, '')
    $reauth = $false
    for ($i = 1; $i -le $GraphState.MaxAttempts; $i++) {
        if ((Get-Date) -ge $GraphState.ExpiresAt) { Update-GraphToken }
        $h = @{}; foreach ($k in $GraphState.Headers.Keys) { $h[$k] = $GraphState.Headers[$k] }; foreach ($k in $Headers.Keys) { $h[$k] = $Headers[$k] }
        $p = @{ Method = $Method; Uri = $uri; Headers = $h; ErrorAction = 'Stop' }
        if ($null -ne $Body) { $p.Body = $(if ($Body -is [string]) { $Body } else { ConvertTo-Json -InputObject $Body -Depth 10 -Compress }) }
        try {
            $r = Invoke-RestMethod @p
            $GraphState.LastStatus = 200
            return $r
        }
        catch {
            $code = Get-GraphHttpStatus $_
            $GraphState.LastStatus = $code
            if ($code -in @(429, 503, 504) -and $i -lt $GraphState.MaxAttempts) { Start-Sleep -Seconds (Get-GraphRetryAfter $_ $i); continue }
            if ($code -eq 401 -and -not $reauth) { $reauth = $true; Update-GraphToken; continue }
            $why = Get-GraphErrorText $_
            if ($code -eq 403) {
                $need = if ($Permission) { "the $Permission application permission" } else { 'a Microsoft Graph application permission it does not have' }
                throw "Microsoft Graph refused $Method $short (403 Forbidden). The app registration needs $need, with admin consent. Graph said: $why"
            }
            throw "Microsoft Graph $Method $short failed$(if ($code) { " (HTTP $code)" }): $why"
        }
    }
}

# Every item from a list call, following @odata.nextLink. Wrap the result in @(...).
function Get-GraphAll {
    param([string]$Path, [string]$Permission = '', [int]$MaxPages = 500)
    $rows = New-Object System.Collections.ArrayList
    $next = $Path; $n = 0
    while ($next -and $n -lt $MaxPages) {
        $n++
        $r = Invoke-Graph -Method GET -Path $next -Permission $Permission
        foreach ($v in @(Get-GraphProp $r 'value')) { if ($null -ne $v) { $null = $rows.Add($v) } }
        $next = [string](Get-GraphProp $r '@odata.nextLink')
    }
    return @($rows)
}

# A user by id or UPN, or $null when there is no such user. Needs User.Read.All.
function Get-GraphUser {
    param([string]$Id, [string]$Select = 'id,userPrincipalName,displayName,mail,accountEnabled,usageLocation,jobTitle,department,assignedLicenses')
    try { return Invoke-Graph -Method GET -Path "/v1.0/users/$(ConvertTo-GraphId $Id)?`$select=$Select" -Permission 'User.Read.All' }
    catch { if ($GraphState.LastStatus -eq 404) { return $null }; throw }
}

# Adds a user to a group. Returns 'added' or 'already-member'. Needs GroupMember.ReadWrite.All.
# Mail-enabled security groups and distribution lists can't be changed through Graph.
function Add-GraphGroupMember {
    param([string]$GroupId, [string]$UserId)
    try { $null = Invoke-Graph -Method POST -Path "/v1.0/groups/$GroupId/members/`$ref" -Body @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$UserId" } -Permission 'GroupMember.ReadWrite.All'; return 'added' }
    catch { if ($GraphState.LastStatus -eq 400 -and $_.Exception.Message -match 'already exist') { return 'already-member' }; throw }
}

# Removes a user from a group. Returns 'removed' or 'not-member'. Needs GroupMember.ReadWrite.All.
function Remove-GraphGroupMember {
    param([string]$GroupId, [string]$UserId)
    try { $null = Invoke-Graph -Method DELETE -Path "/v1.0/groups/$GroupId/members/$UserId/`$ref" -Permission 'GroupMember.ReadWrite.All'; return 'removed' }
    catch { if ($GraphState.LastStatus -eq 404) { return 'not-member' }; throw }
}

# Sets the user's manager. Needs User.ReadWrite.All.
function Set-GraphManager {
    param([string]$UserId, [string]$ManagerId)
    $null = Invoke-Graph -Method PUT -Path "/v1.0/users/$(ConvertTo-GraphId $UserId)/manager/`$ref" -Body @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$ManagerId" } -Permission 'User.ReadWrite.All'
}

# Signs the user out of every session (refresh tokens revoked). Needs User.RevokeSessions.All (or User.ReadWrite.All).
function Revoke-GraphSessions {
    param([string]$UserId)
    $null = Invoke-Graph -Method POST -Path "/v1.0/users/$(ConvertTo-GraphId $UserId)/revokeSignInSessions" -Permission 'User.RevokeSessions.All (or User.ReadWrite.All)'
}

# Turns sign-in on or off. Needs User.EnableDisableAccount.All (or User.ReadWrite.All).
# Disabling an admin account also needs a privileged role, which app permissions can't grant.
function Set-GraphAccountEnabled {
    param([string]$UserId, [bool]$Enabled)
    $null = Invoke-Graph -Method PATCH -Path "/v1.0/users/$(ConvertTo-GraphId $UserId)" -Body @{ accountEnabled = $Enabled } -Permission 'User.EnableDisableAccount.All (or User.ReadWrite.All)'
}

# Adds and/or removes licences by SKU id (GUID). Needs LicenseAssignment.ReadWrite.All (or User.ReadWrite.All).
# The user must have a usage location before a licence can be added.
function Set-GraphLicense {
    param([string]$UserId, [string[]]$Add = @(), [string[]]$Remove = @())
    $toAdd = @($Add | Where-Object { $_ } | ForEach-Object { @{ skuId = [string]$_; disabledPlans = @() } })
    $toRemove = @($Remove | Where-Object { $_ } | ForEach-Object { [string]$_ })
    if (-not $toAdd.Count -and -not $toRemove.Count) { return }
    try { $null = Invoke-Graph -Method POST -Path "/v1.0/users/$(ConvertTo-GraphId $UserId)/assignLicense" -Body @{ addLicenses = $toAdd; removeLicenses = $toRemove } -Permission 'LicenseAssignment.ReadWrite.All (or User.ReadWrite.All)' }
    catch { if ($_.Exception.Message -match '(?i)usage location') { throw "The user has no usage location, so Microsoft 365 can't assign a licence. Set usageLocation first. ($($_.Exception.Message))" }; throw }
}

# Last sign-in times (signInActivity). With -UserId, one user; without, every user.
# Needs AuditLog.Read.All plus User.Read.All, and an Entra ID P1 tenant.
function Get-GraphSignInActivity {
    param([string]$UserId = '')
    $sel = 'id,userPrincipalName,displayName,accountEnabled,signInActivity'
    $perm = 'AuditLog.Read.All (with User.Read.All)'
    if ($UserId) { return Invoke-Graph -Method GET -Path "/v1.0/users/$(ConvertTo-GraphId $UserId)?`$select=$sel" -Permission $perm }
    # Graph caps the page size at 120 when signInActivity is selected.
    return @(Get-GraphAll -Path "/v1.0/users?`$select=$sel&`$top=120" -Permission $perm)
}

# The user's registered sign-in methods (each has id and @odata.type). Needs UserAuthenticationMethod.Read.All.
function Get-GraphAuthMethods {
    param([string]$UserId)
    return @(Get-GraphAll -Path "/v1.0/users/$(ConvertTo-GraphId $UserId)/authentication/methods" -Permission 'UserAuthenticationMethod.Read.All')
}

# Removes one sign-in method. Pass -Method (an item from Get-GraphAuthMethods), or -MethodId and -MethodType.
# Needs UserAuthenticationMethod.ReadWrite.All. The password method can't be removed.
function Remove-GraphAuthMethod {
    param([string]$UserId, $Method = $null, [string]$MethodId = '', [string]$MethodType = '')
    if ($null -ne $Method) { $MethodId = [string](Get-GraphProp $Method 'id'); $MethodType = [string](Get-GraphProp $Method '@odata.type') }
    $t = ($MethodType -replace '^#?microsoft\.graph\.', '')
    $seg = @{
        microsoftAuthenticatorAuthenticationMethod = 'microsoftAuthenticatorMethods'
        phoneAuthenticationMethod                  = 'phoneMethods'
        fido2AuthenticationMethod                  = 'fido2Methods'
        emailAuthenticationMethod                  = 'emailMethods'
        softwareOathAuthenticationMethod           = 'softwareOathMethods'
        windowsHelloForBusinessAuthenticationMethod = 'windowsHelloForBusinessMethods'
        temporaryAccessPassAuthenticationMethod    = 'temporaryAccessPassMethods'
        platformCredentialAuthenticationMethod     = 'platformCredentialMethods'
    }
    if ($t -eq 'passwordAuthenticationMethod') { throw "The password method can't be removed. Reset the password instead." }
    if (-not $MethodId -or -not $seg.ContainsKey($t)) { throw "Can't remove sign-in method '$MethodType' ($MethodId): unknown method type." }
    $null = Invoke-Graph -Method DELETE -Path "/v1.0/users/$(ConvertTo-GraphId $UserId)/authentication/$($seg[$t])/$MethodId" -Permission 'UserAuthenticationMethod.ReadWrite.All'
}

# Risky users from Identity Protection. With -UserId, that user (or $null when not flagged); with -AtRiskOnly,
# only riskState atRisk. Needs IdentityRiskyUser.Read.All and an Entra ID P2 tenant.
function Get-GraphRiskyUsers {
    param([string]$UserId = '', [switch]$AtRiskOnly)
    $perm = 'IdentityRiskyUser.Read.All'
    if ($UserId) {
        try { return Invoke-Graph -Method GET -Path "/v1.0/identityProtection/riskyUsers/$UserId" -Permission $perm }
        catch { if ($GraphState.LastStatus -eq 404) { return $null }; throw }
    }
    $q = if ($AtRiskOnly) { "?`$filter=$([uri]::EscapeDataString("riskState eq 'atRisk'"))" } else { '' }
    return @(Get-GraphAll -Path "/v1.0/identityProtection/riskyUsers$q" -Permission $perm)
}

# A random temporary password with upper, lower, digit and symbol, avoiding look-alike characters.
function New-GraphTempPassword {
    param([int]$Length = 16)
    if ($Length -lt 8) { $Length = 8 }
    $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnpqrstuvwxyz', '23456789', '!@#$%^&*-_=+')
    $all = -join $sets
    $rng = [System.Security.Cryptography.RandomNumberGenerator]
    $chars = New-Object System.Collections.Generic.List[char]
    foreach ($s in $sets) { $chars.Add($s[$rng::GetInt32($s.Length)]) }
    while ($chars.Count -lt $Length) { $chars.Add($all[$rng::GetInt32($all.Length)]) }
    for ($i = $chars.Count - 1; $i -gt 0; $i--) { $j = $rng::GetInt32($i + 1); $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp }
    return -join $chars
}
# ---------- end _shared/graph.ps1 ----------
