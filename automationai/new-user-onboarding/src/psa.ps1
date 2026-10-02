# ---------- PSA calls (see reference/build-kit/PSA.md for the source of each one) ----------
# Taken from Ticket Routing's psa.ps1, trimmed to what onboarding needs: connect and add an
# internal note. Uses the same Key Vault secret names as each PSA's catalog extension.
function Get-PsaSecret { param([string]$n) Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $n -AsPlainText -ErrorAction SilentlyContinue }
function Get-PsaProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-PsaPath { param($o, [string]$path) foreach ($n in $path -split '\.') { $o = Get-PsaProp $o $n; if ($null -eq $o) { return $null } }; return $o }

$script:PsaSecrets = @{
    connectwise = @('CW-ApiUrl', 'CW-CompanyID', 'CW-PublicKey', 'CW-PrivateKey', 'CW-ClientId')
    autotask    = @('Autotask-ApiUrl', 'Autotask-ApiIntegrationCode', 'Autotask-Username', 'Autotask-Secret')
    halopsa     = @('Halo-ApiUrl', 'Halo-ClientId', 'Halo-ClientSecret')
    kaseyabms   = @('KaseyaBMS-ApiUrl', 'KaseyaBMS-Username', 'KaseyaBMS-Password', 'KaseyaBMS-CompanyName')
    syncro      = @('Syncro-ApiUrl', 'Syncro-ApiKey')
    zendesk     = @('Zendesk-BaseUrl', 'Zendesk-Email', 'Zendesk-ApiToken')
}
$script:PsaConn = $null
$script:AtPicklists = $null

# Which PSA: the run's psa input, then the PSA-Type secret, then ConnectWise when its secrets are
# set (so runners set up before PSA-Type existed keep working). '' means none is configured.
function Get-PsaType {
    param([string]$Requested)
    $v = $Requested; if ([string]::IsNullOrWhiteSpace($v) -or $v.StartsWith('@')) { $v = Get-PsaSecret 'PSA-Type' }
    if ([string]::IsNullOrWhiteSpace($v)) { if (Get-PsaSecret 'CW-ApiUrl') { return 'connectwise' }; return '' }
    $v = $v.Trim().ToLowerInvariant()
    $alias = @{ 'cw' = 'connectwise'; 'connectwise-manage' = 'connectwise'; 'connectwise psa' = 'connectwise'; 'autotask-psa' = 'autotask'; 'halo' = 'halopsa'; 'halo-psa' = 'halopsa'; 'kaseya' = 'kaseyabms'; 'kaseya-bms' = 'kaseyabms'; 'zendesk-ticketing' = 'zendesk' }
    if ($alias.ContainsKey($v)) { $v = $alias[$v] }
    if (-not $script:PsaSecrets.ContainsKey($v)) { throw "PSA '$v' isn't supported. Use one of: $(($script:PsaSecrets.Keys | Sort-Object) -join ', ')." }
    return $v
}

function Connect-Psa {
    param([string]$Psa)
    if (-not $script:PsaSecrets.ContainsKey($Psa)) { throw "PSA '$Psa' isn't one of: $(($script:PsaSecrets.Keys | Sort-Object) -join ', ')." }
    $v = @{}; $missing = @()
    foreach ($n in $script:PsaSecrets[$Psa]) { $v[$n] = Get-PsaSecret $n; if ([string]::IsNullOrWhiteSpace($v[$n])) { $missing += $n } }
    if ($missing.Count) { throw "Add these secrets to the runner Key Vault: $($missing -join ', ')" }
    $json = 'application/json'
    switch ($Psa) {
        'connectwise' {
            $b = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($v['CW-CompanyID'])+$($v['CW-PublicKey']):$($v['CW-PrivateKey'])"))
            $c = @{ Base = $v['CW-ApiUrl'].TrimEnd('/'); Headers = @{ Authorization = "Basic $b"; clientId = $v['CW-ClientId']; Accept = $json } }
        }
        'autotask' {
            $c = @{ Base = ($v['Autotask-ApiUrl'].TrimEnd('/') -replace '/atservicesrest/v1\.0$', '') + '/atservicesrest/v1.0'
                Headers = @{ ApiIntegrationCode = $v['Autotask-ApiIntegrationCode']; UserName = $v['Autotask-Username']; Secret = $v['Autotask-Secret']; Accept = $json } }
        }
        'halopsa' {
            $base = $v['Halo-ApiUrl'].TrimEnd('/') -replace '/api$', ''
            $form = "grant_type=client_credentials&client_id=$([uri]::EscapeDataString($v['Halo-ClientId']))&client_secret=$([uri]::EscapeDataString($v['Halo-ClientSecret']))&scope=all"
            $tok = $null
            try { $tok = Invoke-RestMethod -Method POST -Uri "$base/auth/token" -Body $form -ContentType 'application/x-www-form-urlencoded' }
            catch {
                # Some instances run a separate auth server; /api/authinfo names it.
                $info = Invoke-RestMethod -Method GET -Uri "$base/api/authinfo"
                $authUrl = [string](Get-PsaProp $info 'auth_url'); if (-not $authUrl) { throw }
                $tok = Invoke-RestMethod -Method POST -Uri "$($authUrl.TrimEnd('/'))/token" -Body $form -ContentType 'application/x-www-form-urlencoded'
            }
            $c = @{ Base = "$base/api"; Headers = @{ Authorization = "Bearer $(Get-PsaProp $tok 'access_token')"; Accept = $json } }
        }
        'kaseyabms' {
            $base = $v['KaseyaBMS-ApiUrl'].TrimEnd('/')
            $r = Invoke-RestMethod -Method POST -Uri "$base/v2/security/authenticate" -Form @{ UserName = $v['KaseyaBMS-Username']; Password = $v['KaseyaBMS-Password']; Tenant = $v['KaseyaBMS-CompanyName']; GrantType = 'password' }
            $token = Get-PsaPath $r 'Result.AccessToken'; if (-not $token) { $token = Get-PsaPath $r 'result.accessToken' }
            if (-not $token) { throw 'Kaseya BMS sign-in returned no Result.AccessToken. Check the KaseyaBMS-* secrets.' }
            $c = @{ Base = "$base/v2"; Headers = @{ Authorization = "Bearer $token"; Accept = $json } }
        }
        'syncro' { $c = @{ Base = $v['Syncro-ApiUrl'].TrimEnd('/'); Headers = @{ Authorization = "Bearer $($v['Syncro-ApiKey'])"; Accept = $json } } }
        'zendesk' {
            $base = $v['Zendesk-BaseUrl'].TrimEnd('/'); if ($base -notmatch '/api/v2$') { $base += '/api/v2' }
            $b = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($v['Zendesk-Email'])/token:$($v['Zendesk-ApiToken'])"))
            $c = @{ Base = $base; Headers = @{ Authorization = "Basic $b"; Accept = $json } }
        }
    }
    $c.Psa = $Psa
    $script:PsaConn = $c
    return $c
}

function Invoke-Psa {
    param([string]$Method, [string]$Path, $Body = $null)
    $p = @{ Method = $Method; Uri = "$($script:PsaConn.Base)$Path"; Headers = $script:PsaConn.Headers }
    if ($null -ne $Body) { $p.Body = ($Body | ConvertTo-Json -Depth 10 -Compress -AsArray:($Body -is [array])); $p.ContentType = 'application/json' }
    return Invoke-RestMethod @p
}

# Autotask note picklists are per tenant: match on the label, never a hard-coded number.
function Get-AtPicklist {
    param([string]$Entity, [string]$Field)
    if ($null -eq $script:AtPicklists) { $script:AtPicklists = @{} }
    if (-not $script:AtPicklists.ContainsKey($Entity)) { $script:AtPicklists[$Entity] = @(Get-PsaProp (Invoke-Psa GET "/$Entity/entityInformation/fields") 'fields') }
    $f = @($script:AtPicklists[$Entity] | Where-Object { [string](Get-PsaProp $_ 'name') -eq $Field }) | Select-Object -First 1
    return @(Get-PsaProp $f 'picklistValues' | Where-Object { $null -ne $_ -and (Get-PsaProp $_ 'isActive') -ne $false })
}
function Select-AtValue {
    param($Values, [string[]]$Patterns)
    foreach ($p in $Patterns) {
        $hit = @($Values | Where-Object { [string](Get-PsaProp $_ 'label') -match $p }) | Select-Object -First 1
        if ($hit) { return (Get-PsaProp $hit 'value') }
    }
    return $null
}

# Adds an internal (technician-only) note. Throws when the PSA rejects it.
function Add-PsaNote {
    param([string]$Id, [string]$Text, [string]$Title = 'Note')
    switch ($script:PsaConn.Psa) {
        'connectwise' { $null = Invoke-Psa POST "/service/tickets/$Id/notes" @{ text = $Text; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false } }
        'autotask' {
            $pub = Get-PsaSecret 'Autotask-NotePublishId'
            if (-not $pub) { $pub = Select-AtValue (Get-AtPicklist 'TicketNotes' 'publish') @('^Internal Only$', 'Internal') }
            $type = Get-PsaSecret 'Autotask-NoteTypeId'
            if (-not $type) { $vals = @(Get-AtPicklist 'TicketNotes' 'noteType' | Where-Object { [string](Get-PsaProp $_ 'value') -ne '13' -and [string](Get-PsaProp $_ 'label') -notmatch 'Workflow' }); $type = Select-AtValue $vals @('Internal', 'Task Detail', 'Detail', '.') }
            if ($null -eq $pub -or $null -eq $type) { throw 'Could not find the Autotask note publish and type values. Set the Autotask-NotePublishId and Autotask-NoteTypeId secrets.' }
            $null = Invoke-Psa POST "/Tickets/$Id/Notes" @{ ticketID = [long]$Id; title = $Title; description = $Text; noteType = [int]$type; publish = [int]$pub }
        }
        'halopsa' {
            $outcome = Get-PsaSecret 'Halo-NoteOutcomeId'; if (-not $outcome) { $outcome = 7 }
            $null = Invoke-Psa POST '/Actions' @(@{ ticket_id = [long]$Id; note = $Text; hiddenfromuser = $true; outcome_id = [int]$outcome })
        }
        'kaseyabms' {
            $type = Get-PsaSecret 'KaseyaBMS-NoteTypeId'
            if (-not $type) { throw 'Kaseya BMS notes need a note type id. Set the KaseyaBMS-NoteTypeId secret.' }
            $null = Invoke-Psa POST "/servicedesk/tickets/$Id/notes" @{ Details = $Text; IsInternal = $true; NoteDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); TypeId = [int]$type }
        }
        'syncro' { $null = Invoke-Psa POST "/tickets/$Id/comment" @{ subject = $Title; body = $Text; hidden = $true; do_not_email = $true } }
        'zendesk' { $null = Invoke-Psa PUT "/tickets/$Id" @{ ticket = @{ comment = @{ body = $Text; public = $false } } } }
    }
}

# Display names for messages.
$script:PsaNames = @{ connectwise = 'ConnectWise'; autotask = 'Autotask'; halopsa = 'HaloPSA'; kaseyabms = 'Kaseya BMS'; syncro = 'Syncro'; zendesk = 'Zendesk' }
