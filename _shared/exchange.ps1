# ---------- Exchange Online ----------
# Graph can't convert a mailbox to shared, hide it from the address list, set forwarding, or create a shared
# mailbox or distribution list, so these helpers reach Exchange Online two ways, in this order:
#   1. The Exchange admin REST endpoint the microsoft-exchange catalog extension uses
#      (POST https://outlook.office365.com/adminapi/beta/{tenant}/InvokeCommand), signed in with the
#      extension's own secrets: MicrosoftExchange-TenantId, MicrosoftExchange-ClientId, MicrosoftExchange-ClientSecret.
#   2. The ExchangeOnlineManagement module with app-only certificate auth, when the module is on the runner
#      and the secrets MicrosoftExchange-ClientId, MicrosoftExchange-Organization (or the -Organization the caller
#      passes, such as the tenant's .onmicrosoft.com domain found through Graph) and
#      MicrosoftExchange-CertificateThumbprint or MicrosoftExchange-Certificate (base64 PFX, with optional
#      MicrosoftExchange-CertificatePassword) are set.
# Either way the app registration needs the Exchange.ManageAsApp application permission (Office 365 Exchange Online)
# and the Exchange Administrator role.
# When neither works, Connect-OfExchange returns $false and $OfExo.Reason says why; the caller decides whether to
# list the Exchange steps for a technician or stop.
# In module mode every cmdlet that isn't Get-* runs with -Confirm:$false, so it can't stop to ask.
#
# All state lives in $OfExo, changed in place (the runner runs a step in a child scope, so no $script: variables):
#   Mode       'rest' or 'module' once connected, '' before
#   Connected  $true after a successful sign-in
#   Tried      $true after the first Connect-OfExchange, so a failed sign-in isn't retried in the same step
#   Reason     why the sign-in failed, as plain sentences joined with '; '
#   TenantId   the tenant the REST calls go to
#   Token      the REST bearer token
# The Of prefix (and the helper names) come from the first automation that used this code; keep them, so a step
# can use it next to the other libraries without name clashes.
$OfExo = @{ Mode = ''; Reason = ''; TenantId = ''; Token = ''; Connected = $false; Tried = $false }

function Get-OfSecret { param([string]$Name) $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue } catch { }; if ([string]::IsNullOrWhiteSpace([string]$v)) { return '' }; return ([string]$v).Trim() }
function Get-OfProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-OfErrorText {
    param($Err)
    $d = $null; try { if ($Err.ErrorDetails -and $Err.ErrorDetails.Message) { $d = $Err.ErrorDetails.Message } } catch { }
    if ($d) {
        try {
            $j = $d | ConvertFrom-Json -ErrorAction Stop
            $e = Get-OfProp $j 'error'
            # A sign-in error carries a code in "error" and the readable text in "error_description".
            $m = Get-OfProp $j 'error_description'
            if (-not $m) { $m = $(if ($e -is [string]) { $e } else { Get-OfProp $e 'message' }) }
            if (-not $m) { $m = Get-OfProp $j 'message' }
            if ($m) { return [string]$m }
        } catch { }
        return [string]$d
    }
    return [string]$Err.Exception.Message
}
function Get-OfHttpStatus { param($Err) $c = 0; try { $c = [int]$Err.Exception.Response.StatusCode } catch { }; return $c }
function Test-OfNotFound { param([string]$Text) return $Text -match "(?i)couldn't be found|could not be found|ManagementObjectNotFound|wasn't found|was not found" }

# Signs in to Exchange Online once per step. Returns $true when connected; otherwise $false with $OfExo.Reason set.
function Connect-OfExchange {
    param([string]$Organization = '')
    if ($OfExo.Connected) { return $true }
    if ($OfExo.Tried) { return $false }
    $OfExo.Tried = $true
    $appId = Get-OfSecret 'MicrosoftExchange-ClientId'
    $tenant = Get-OfSecret 'MicrosoftExchange-TenantId'
    $clientSecret = Get-OfSecret 'MicrosoftExchange-ClientSecret'
    $thumb = Get-OfSecret 'MicrosoftExchange-CertificateThumbprint'
    $pfx = Get-OfSecret 'MicrosoftExchange-Certificate'
    $org = Get-OfSecret 'MicrosoftExchange-Organization'; if (-not $org) { $org = $Organization }
    $why = New-Object System.Collections.ArrayList

    # 1. The Exchange admin REST endpoint with the microsoft-exchange extension's secrets.
    if ($tenant -and $appId -and $clientSecret) {
        try {
            $r = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$tenant/oauth2/v2.0/token" -Body @{ client_id = $appId; client_secret = $clientSecret; scope = 'https://outlook.office365.com/.default'; grant_type = 'client_credentials' } -ErrorAction Stop
            $tok = [string](Get-OfProp $r 'access_token')
            if (-not $tok) { throw 'Microsoft sign-in returned no access token.' }
            $OfExo.Token = $tok; $OfExo.TenantId = $tenant; $OfExo.Mode = 'rest'; $OfExo.Connected = $true; $OfExo.Reason = ''
            return $true
        }
        catch { $null = $why.Add("Exchange Online sign-in with the MicrosoftExchange-* secrets failed: $(Get-OfErrorText $_)") }
    }
    elseif (-not ($thumb -or $pfx)) {
        $miss = @(); if (-not $tenant) { $miss += 'MicrosoftExchange-TenantId' }; if (-not $appId) { $miss += 'MicrosoftExchange-ClientId' }; if (-not $clientSecret) { $miss += 'MicrosoftExchange-ClientSecret' }
        $null = $why.Add("the runner has no Exchange Online secrets ($($miss -join ', ') missing)")
    }

    # 2. ExchangeOnlineManagement with a certificate.
    if ($thumb -or $pfx) {
        $hasModule = $false
        try { $hasModule = [bool](@(Get-Module -ListAvailable -Name ExchangeOnlineManagement -ErrorAction SilentlyContinue | Where-Object { $null -ne $_ }).Count) } catch { }
        if (-not $hasModule) { $null = $why.Add('the ExchangeOnlineManagement PowerShell module is not installed on the runner') }
        elseif (-not $appId) { $null = $why.Add('the MicrosoftExchange-ClientId secret is missing') }
        elseif (-not $org) { $null = $why.Add('the MicrosoftExchange-Organization secret (the tenant''s .onmicrosoft.com domain) is missing') }
        else {
            try {
                Import-Module ExchangeOnlineManagement -ErrorAction Stop
                $p = @{ AppId = $appId; Organization = $org; ShowBanner = $false; ErrorAction = 'Stop' }
                if ($pfx) {
                    $pw = Get-OfSecret 'MicrosoftExchange-CertificatePassword'
                    $p.Certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new([Convert]::FromBase64String($pfx), $pw, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
                }
                else { $p.CertificateThumbprint = $thumb }
                Connect-ExchangeOnline @p
                $OfExo.Mode = 'module'; $OfExo.Connected = $true; $OfExo.Reason = ''
                return $true
            }
            catch { $null = $why.Add("Exchange Online PowerShell sign-in failed: $($_.Exception.Message)") }
        }
    }
    $OfExo.Reason = ($why -join '; ')
    return $false
}

# Runs one Exchange cmdlet. Returns an array of result objects; throws a plain sentence on failure.
# REST retries 429, 503 and 504; a 401 or 403 names the permission and role the app registration needs.
function Invoke-OfExo {
    param([string]$Cmdlet, [hashtable]$Parameters = @{})
    if (-not $OfExo.Connected) { throw "Exchange Online isn't connected: $($OfExo.Reason)" }
    if ($OfExo.Mode -eq 'module') {
        $p = @{}; foreach ($k in $Parameters.Keys) { $p[$k] = $Parameters[$k] }; $p.ErrorAction = 'Stop'
        if ($Cmdlet -notlike 'Get-*') { $p.Confirm = $false }
        try { return @(& $Cmdlet @p) } catch { throw "Exchange Online $Cmdlet failed: $($_.Exception.Message)" }
    }
    $body = ConvertTo-Json -InputObject @{ CmdletInput = @{ CmdletName = $Cmdlet; Parameters = $Parameters } } -Depth 6 -Compress
    $h = @{ Authorization = "Bearer $($OfExo.Token)"; Accept = 'application/json' }
    for ($i = 1; $i -le 4; $i++) {
        try {
            $r = Invoke-RestMethod -Method POST -Uri "https://outlook.office365.com/adminapi/beta/$($OfExo.TenantId)/InvokeCommand" -Headers $h -Body $body -ContentType 'application/json' -ErrorAction Stop
            return @(@(Get-OfProp $r 'value') | Where-Object { $null -ne $_ })
        }
        catch {
            $code = Get-OfHttpStatus $_
            if ($code -in @(429, 503, 504) -and $i -lt 4) { Start-Sleep -Seconds ([Math]::Min(30, [Math]::Pow(2, $i))); continue }
            $txt = Get-OfErrorText $_
            if ($code -eq 403 -or $code -eq 401) { throw "Exchange Online refused $Cmdlet (HTTP $code). The app registration needs the Exchange.ManageAsApp application permission and the Exchange Administrator role. Exchange said: $txt" }
            throw "Exchange Online $Cmdlet failed$(if ($code) { " (HTTP $code)" }): $txt"
        }
    }
}

# The recipient with this identity (address, alias or name), or $null when there is none.
function Get-OfRecipient {
    param([string]$Identity)
    try { return @(Invoke-OfExo 'Get-Recipient' @{ Identity = $Identity })[0] }
    catch { if (Test-OfNotFound $_.Exception.Message) { return $null }; throw }
}

# The user's mailbox, or $null when they have none.
function Get-OfMailbox {
    param([string]$Identity)
    try { return @(Invoke-OfExo 'Get-Mailbox' @{ Identity = $Identity })[0] }
    catch { if (Test-OfNotFound $_.Exception.Message) { return $null }; throw }
}

# Mailbox size in bytes from Get-MailboxStatistics, or -1 when it can't be read.
function Get-OfMailboxBytes {
    param([string]$Identity)
    try {
        $s = @(Invoke-OfExo 'Get-MailboxStatistics' @{ Identity = $Identity })[0]
        $t = [string](Get-OfProp $s 'TotalItemSize')
        if ($t -match '\(([\d,\.]+) bytes\)') { return [double]($Matches[1] -replace '[,\.]', '') }
    } catch { }
    return -1
}
# ---------- end Exchange Online helpers ----------
