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
            $base = $v['KaseyaBMS-ApiUrl'].TrimEnd('/') -replace '/v2$', ''
            # Unverified: the GrantType value 'password' (PSA.md).
            $r = Invoke-RestMethod -Method POST -Uri "$base/v2/security/authenticate" -Form @{ UserName = $v['KaseyaBMS-Username']; Password = $v['KaseyaBMS-Password']; Tenant = $v['KaseyaBMS-CompanyName']; GrantType = 'password' } -ErrorAction Stop
            $token = Get-PsaPath $r 'Result.AccessToken'; if (-not $token) { $token = Get-PsaPath $r 'result.accessToken' }
            if (-not $token) { throw 'Kaseya BMS sign-in returned no Result.AccessToken. Check the KaseyaBMS-* secrets.' }
            $c = @{ Base = "$base/v2"; Headers = @{ Authorization = "Bearer $token"; Accept = $json } }
        }
        'syncro' { $c = @{ Base = $v['Syncro-ApiUrl'].TrimEnd('/'); Headers = @{ Authorization = "Bearer $($v['Syncro-ApiKey'])"; Accept = $json } } }
        'zendesk' {
            # Unverified: whether the Zendesk-BaseUrl secret already ends in /api/v2, so it is added when missing.
            $base = $v['Zendesk-BaseUrl'].TrimEnd('/'); if ($base -notmatch '/api/v2$') { $base += '/api/v2' }
            $b = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($v['Zendesk-Email'])/token:$($v['Zendesk-ApiToken'])"))
            $c = @{ Base = $base; Headers = @{ Authorization = "Basic $b"; Accept = $json } }
        }
    }
    $c.Psa = $Psa
    $PsaState.Conn = $c
    $PsaState.Picklists = @{}
    return $c
}

# One call to the connected PSA. Path is relative to the API base (or a full URL).
# Retries 429 (and 502, 503, 504 on GET) honoring Retry-After; other errors throw a plain message.
function Invoke-Psa {
    param([string]$Method, [string]$Path, $Body = $null, [string]$ContentType = 'application/json')
    $c = Get-PsaConn
    $uri = if ($Path -match '^https?://') { $Path } else { "$($c.Base)$Path" }
    for ($i = 1; $i -le $PsaState.MaxRetries; $i++) {
        $p = @{ Method = $Method; Uri = $uri; Headers = $c.Headers; ErrorAction = 'Stop' }
        if ($null -ne $Body) { $p.Body = $(if ($Body -is [string]) { $Body } else { ConvertTo-Json -InputObject $Body -Depth 10 -Compress }); $p.ContentType = $ContentType }
        try { return Invoke-RestMethod @p }
        catch {
            $code = Get-PsaHttpStatus $_
            if (($code -eq 429 -or ($Method -eq 'GET' -and $code -in @(502, 503, 504))) -and $i -lt $PsaState.MaxRetries) { Start-Sleep -Seconds (Get-PsaRetryAfter $_ $i); continue }
            throw "$(Get-PsaName) $Method $Path failed$(if ($code) { " (HTTP $code)" }): $(Get-PsaErrorText $_)"
        }
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
function Add-PsaNote {
    param([string]$Id, [string]$Text, [string]$Title = 'Note', [switch]$Public, [switch]$Internal)
    $c = Get-PsaConn
    $pub = [bool]$Public
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
            $rows = @(Get-PsaProp $r 'clients'); if (-not @($rows | Where-Object { $null -ne $_ }).Count -and $r -is [array]) { $rows = @($r) }
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
# ---------- end _shared/psa.ps1 ----------
