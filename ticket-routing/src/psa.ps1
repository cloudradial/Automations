# ---------- PSA calls (see reference/build-kit/PSA.md for the source of each one) ----------
# Uses the same Key Vault secret names as each PSA's catalog extension.

function Secret { param($n) Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $n -AsPlainText -ErrorAction SilentlyContinue }
function Get-Prop { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-Path { param($o, [string]$path) foreach ($n in $path -split '\.') { $o = Get-Prop $o $n; if ($null -eq $o) { return $null } }; return $o }
function Test-Blank { param($v) return ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v) -or [string]$v -eq '0') }

$script:PsaSecrets = @{
    connectwise = @('CW-ApiUrl', 'CW-CompanyID', 'CW-PublicKey', 'CW-PrivateKey', 'CW-ClientId')
    autotask    = @('Autotask-ApiUrl', 'Autotask-ApiIntegrationCode', 'Autotask-Username', 'Autotask-Secret')
    halopsa     = @('Halo-ApiUrl', 'Halo-ClientId', 'Halo-ClientSecret')
    kaseyabms   = @('KaseyaBMS-ApiUrl', 'KaseyaBMS-Username', 'KaseyaBMS-Password', 'KaseyaBMS-CompanyName')
    syncro      = @('Syncro-ApiUrl', 'Syncro-ApiKey')
    zendesk     = @('Zendesk-BaseUrl', 'Zendesk-Email', 'Zendesk-ApiToken')
}
$script:Conn = $null
$script:AtPicklists = $null

function Connect-Psa {
    param([string]$Psa)
    if (-not $script:PsaSecrets.ContainsKey($Psa)) { throw "psa '$Psa' isn't one of: $($script:PsaSecrets.Keys -join ', ')." }
    $v = @{}; $missing = @()
    foreach ($n in $script:PsaSecrets[$Psa]) { $v[$n] = Secret $n; if ([string]::IsNullOrWhiteSpace($v[$n])) { $missing += $n } }
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
                $authUrl = [string](Get-Prop $info 'auth_url'); if (-not $authUrl) { throw }
                $tok = Invoke-RestMethod -Method POST -Uri "$($authUrl.TrimEnd('/'))/token" -Body $form -ContentType 'application/x-www-form-urlencoded'
            }
            $c = @{ Base = "$base/api"; Headers = @{ Authorization = "Bearer $(Get-Prop $tok 'access_token')"; Accept = $json } }
        }
        'kaseyabms' {
            $base = $v['KaseyaBMS-ApiUrl'].TrimEnd('/')
            $r = Invoke-RestMethod -Method POST -Uri "$base/v2/security/authenticate" -Form @{ UserName = $v['KaseyaBMS-Username']; Password = $v['KaseyaBMS-Password']; Tenant = $v['KaseyaBMS-CompanyName']; GrantType = 'password' }
            $token = Get-Path $r 'Result.AccessToken'; if (-not $token) { $token = Get-Path $r 'result.accessToken' }
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
    $script:Conn = $c
    return $c
}

function Invoke-Psa {
    param([string]$Method, [string]$Path, $Body = $null)
    $p = @{ Method = $Method; Uri = "$($script:Conn.Base)$Path"; Headers = $script:Conn.Headers }
    if ($null -ne $Body) { $p.Body = ($Body | ConvertTo-Json -Depth 10 -Compress -AsArray:($Body -is [array])); $p.ContentType = 'application/json' }
    return Invoke-RestMethod @p
}
function Q { param([string]$s) [uri]::EscapeDataString($s) }
# ConnectWise conditions quote strings and leave numbers bare.
function CwOwner { param([string]$u) if ($u -match '^\d+$') { "owner/id=$u" } else { "owner/identifier=`"$u`"" } }

function Get-PsaTicket {
    param([string]$Id)
    switch ($script:Conn.Psa) {
        'connectwise' {
            $t = Invoke-Psa GET "/service/tickets/$Id"
            $desc = ''
            try { $n = @(Invoke-Psa GET "/service/tickets/$Id/notes?orderBy=$(Q 'id asc')&pageSize=1"); if ($n.Count) { $desc = [string](Get-Prop $n[0] 'text') } } catch { }
            $owner = Get-Prop $t 'owner'
            $a = @(@((Get-Prop $owner 'identifier'), (Get-Prop $owner 'id')) | Where-Object { -not (Test-Blank $_) } | ForEach-Object { [string]$_ })
            return @{ id = $Id; summary = [string](Get-Prop $t 'summary'); description = $desc; companyId = [string](Get-Path $t 'company.id'); status = [string](Get-Path $t 'status.name'); assigneeId = $(if ($a.Count) { $a[0] } else { '' }); assigneeIds = $a; raw = $t }
        }
        'autotask' {
            $t = Get-Prop (Invoke-Psa GET "/Tickets/$Id") 'item'
            if ($null -eq $t) { throw "Autotask returned no ticket $Id." }
            $a = Get-Prop $t 'assignedResourceID'
            return @{ id = $Id; summary = [string](Get-Prop $t 'title'); description = [string](Get-Prop $t 'description'); companyId = [string](Get-Prop $t 'companyID'); status = [string](Get-Prop $t 'status'); assigneeId = $(if (Test-Blank $a) { '' } else { [string]$a }); assigneeIds = @(); raw = $t }
        }
        'halopsa' {
            $t = Invoke-Psa GET "/Tickets/$($Id)?includedetails=true"
            $a = Get-Prop $t 'agent_id'
            return @{ id = $Id; summary = [string](Get-Prop $t 'summary'); description = [string](Get-Prop $t 'details'); companyId = [string](Get-Prop $t 'client_id'); status = [string](Get-Prop $t 'status_id'); assigneeId = $(if (Test-Blank $a) { '' } else { [string]$a }); assigneeIds = @(); raw = $t }
        }
        'kaseyabms' {
            $t = Get-Prop (Invoke-Psa GET "/servicedesk/tickets/$Id") 'Result'
            if ($null -eq $t) { throw "Kaseya BMS returned no ticket $Id." }
            $a = Get-Prop $t 'AssigneeId'
            return @{ id = $Id; summary = [string](Get-Prop $t 'Title'); description = [string](Get-Prop $t 'Details'); companyId = [string](Get-Prop $t 'AccountId'); status = [string](Get-Prop $t 'StatusName'); assigneeId = $(if (Test-Blank $a) { '' } else { [string]$a }); assigneeIds = @(); raw = $t }
        }
        'syncro' {
            $t = Get-Prop (Invoke-Psa GET "/tickets/$Id") 'ticket'
            if ($null -eq $t) { throw "Syncro returned no ticket $Id." }
            $c = @(Get-Prop $t 'comments' | Where-Object { $null -ne $_ })
            $desc = if ($c.Count) { [string](Get-Prop $c[0] 'body') } else { '' }
            $pt = [string](Get-Prop $t 'problem_type'); if ($pt) { $desc = "Issue type: $pt`n$desc" }
            $a = Get-Prop $t 'user_id'
            return @{ id = $Id; summary = [string](Get-Prop $t 'subject'); description = $desc; companyId = [string](Get-Prop $t 'customer_id'); status = [string](Get-Prop $t 'status'); assigneeId = $(if (Test-Blank $a) { '' } else { [string]$a }); assigneeIds = @(); raw = $t }
        }
        'zendesk' {
            $t = Get-Prop (Invoke-Psa GET "/tickets/$Id") 'ticket'
            if ($null -eq $t) { throw "Zendesk returned no ticket $Id." }
            $a = Get-Prop $t 'assignee_id'
            return @{ id = $Id; summary = [string](Get-Prop $t 'subject'); description = [string](Get-Prop $t 'description'); companyId = [string](Get-Prop $t 'organization_id'); status = [string](Get-Prop $t 'status'); assigneeId = $(if (Test-Blank $a) { '' } else { [string]$a }); assigneeIds = @(); raw = $t }
        }
    }
}

function Set-PsaAssignee {
    param([string]$Id, [string]$UserId, [string]$RoleId = '')
    switch ($script:Conn.Psa) {
        'connectwise' {
            $val = if ($UserId -match '^\d+$') { @{ id = [int]$UserId } } else { @{ identifier = $UserId } }
            $null = Invoke-Psa PATCH "/service/tickets/$Id" @([ordered]@{ op = 'replace'; path = 'owner'; value = $val })
        }
        'autotask' {
            if (-not $RoleId) { throw 'Autotask needs a PSA Role Id with the resource. Add it to the engineers table.' }
            $null = Invoke-Psa PATCH '/Tickets' ([ordered]@{ id = [long]$Id; assignedResourceID = [long]$UserId; assignedResourceRoleID = [long]$RoleId })
        }
        'halopsa' { $null = Invoke-Psa POST '/Tickets' @([ordered]@{ id = [long]$Id; agent_id = [long]$UserId }) }
        'kaseyabms' { $null = Invoke-Psa PATCH "/servicedesk/tickets/$Id" @([ordered]@{ op = 'replace'; path = '/AssigneeId'; value = [long]$UserId }) }
        'syncro' { $null = Invoke-Psa PUT "/tickets/$Id" @{ user_id = [long]$UserId } }
        'zendesk' { $null = Invoke-Psa PUT "/tickets/$Id" @{ ticket = @{ assignee_id = [long]$UserId } } }
    }
}

# Autotask note picklists are per tenant: match on the label, never a hard-coded number.
function Get-AtPicklist {
    param([string]$Entity, [string]$Field)
    if ($null -eq $script:AtPicklists) { $script:AtPicklists = @{} }
    if (-not $script:AtPicklists.ContainsKey($Entity)) { $script:AtPicklists[$Entity] = @(Get-Prop (Invoke-Psa GET "/$Entity/entityInformation/fields") 'fields') }
    $f = @($script:AtPicklists[$Entity] | Where-Object { [string](Get-Prop $_ 'name') -eq $Field }) | Select-Object -First 1
    return @(Get-Prop $f 'picklistValues' | Where-Object { $null -ne $_ -and (Get-Prop $_ 'isActive') -ne $false })
}
function Select-AtValue {
    param($Values, [string[]]$Patterns)
    foreach ($p in $Patterns) {
        $hit = @($Values | Where-Object { [string](Get-Prop $_ 'label') -match $p }) | Select-Object -First 1
        if ($hit) { return (Get-Prop $hit 'value') }
    }
    return $null
}

function Add-PsaNote {
    param([string]$Id, [string]$Text, [switch]$Internal)
    switch ($script:Conn.Psa) {
        'connectwise' { $null = Invoke-Psa POST "/service/tickets/$Id/notes" @{ text = $Text; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false } }
        'autotask' {
            $pub = Secret 'Autotask-NotePublishId'
            if (-not $pub) { $pub = Select-AtValue (Get-AtPicklist 'TicketNotes' 'publish') @('^Internal Only$', 'Internal') }
            $type = Secret 'Autotask-NoteTypeId'
            if (-not $type) { $vals = @(Get-AtPicklist 'TicketNotes' 'noteType' | Where-Object { [string](Get-Prop $_ 'value') -ne '13' -and [string](Get-Prop $_ 'label') -notmatch 'Workflow' }); $type = Select-AtValue $vals @('Internal', 'Task Detail', 'Detail', '.') }
            if ($null -eq $pub -or $null -eq $type) { throw 'Could not find the Autotask note publish and type values. Set the Autotask-NotePublishId and Autotask-NoteTypeId secrets.' }
            $null = Invoke-Psa POST "/Tickets/$Id/Notes" @{ ticketID = [long]$Id; title = 'Ticket routing'; description = $Text; noteType = [int]$type; publish = [int]$pub }
        }
        'halopsa' {
            $outcome = Secret 'Halo-NoteOutcomeId'; if (-not $outcome) { $outcome = 7 }
            $null = Invoke-Psa POST '/Actions' @(@{ ticket_id = [long]$Id; note = $Text; hiddenfromuser = $true; outcome_id = [int]$outcome })
        }
        'kaseyabms' {
            $type = Secret 'KaseyaBMS-NoteTypeId'
            if (-not $type) { throw 'Kaseya BMS notes need a note type id. Set the KaseyaBMS-NoteTypeId secret.' }
            $null = Invoke-Psa POST "/servicedesk/tickets/$Id/notes" @{ Details = $Text; IsInternal = $true; NoteDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); TypeId = [int]$type }
        }
        'syncro' { $null = Invoke-Psa POST "/tickets/$Id/comment" @{ subject = 'Ticket routing'; body = $Text; hidden = $true; do_not_email = $true } }
        'zendesk' { $null = Invoke-Psa PUT "/tickets/$Id" @{ ticket = @{ comment = @{ body = $Text; public = $false } } } }
    }
}

function Get-AtCompleteStatuses {
    $v = @(Get-AtPicklist 'Tickets' 'status' | Where-Object { [string](Get-Prop $_ 'label') -match '(?i)complete' } | ForEach-Object { [int](Get-Prop $_ 'value') })
    if (-not $v.Count) { $v = @(5) }
    return $v
}

# An int, or $null when this PSA can't count (the caller falls back and warns).
function Get-PsaOpenCount {
    param([string]$UserId)
    switch ($script:Conn.Psa) {
        'connectwise' { return [int](Get-Prop (Invoke-Psa GET "/service/tickets/count?conditions=$(Q "$(CwOwner $UserId) and closedFlag=false")") 'count') }
        'autotask' {
            $f = @([ordered]@{ op = 'eq'; field = 'assignedResourceID'; value = [long]$UserId }) + @(Get-AtCompleteStatuses | ForEach-Object { [ordered]@{ op = 'noteq'; field = 'status'; value = $_ } })
            $r = Invoke-Psa GET "/Tickets/query/count?search=$(Q (@{ filter = $f } | ConvertTo-Json -Depth 6 -Compress))"
            $n = Get-Prop $r 'queryCount'; if ($null -eq $n) { return $null }; return [int]$n
        }
        'halopsa' { $n = Get-Prop (Invoke-Psa GET "/Tickets?agent_id=$UserId&open_only=true&pageinate=true&page_size=1&page_no=1") 'record_count'; if ($null -eq $n) { return $null }; return [int]$n }
        'kaseyabms' { return $null }
        'syncro' {
            $r = Invoke-Psa GET "/tickets?user_id=$UserId&status=$(Q 'Not Closed')&page=1"
            $te = Get-Path $r 'meta.total_entries'; if ($null -ne $te) { return [int]$te }
            $n = @(Get-Prop $r 'tickets').Count; $pages = [int](Get-Path $r 'meta.total_pages')
            for ($p = 2; $p -le [Math]::Min($pages, 10); $p++) { $n += @(Get-Prop (Invoke-Psa GET "/tickets?user_id=$UserId&status=$(Q 'Not Closed')&page=$p") 'tickets').Count }
            if ($pages -gt 10) { return $null }
            return $n
        }
        'zendesk' { return [int](Get-Prop (Invoke-Psa GET "/search/count?query=$(Q "type:ticket assignee:$UserId status<solved")") 'count') }
    }
}

# The newest ticket currently assigned to the engineer: a date, [datetime]::MinValue
# when they have none, or $null when this PSA can't tell.
function Get-PsaLastAssigned {
    param([string]$UserId)
    $none = [datetime]::MinValue
    $date = { param($v) if (Test-Blank $v) { $none } else { [datetime]::Parse([string]$v, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal) } }
    switch ($script:Conn.Psa) {
        'connectwise' { $r = @(Invoke-Psa GET "/service/tickets?conditions=$(Q (CwOwner $UserId))&orderBy=$(Q 'dateEntered desc')&pageSize=1&fields=id,dateEntered"); if (-not $r.Count) { return $none }; return (& $date (Get-Prop $r[0] 'dateEntered')) }
        'autotask' {
            # The query API can't sort, so take the highest id from the last 90 days.
            $since = (Get-Date).ToUniversalTime().AddDays(-90).ToString('yyyy-MM-ddTHH:mm:ssZ')
            $s = @{ filter = @([ordered]@{ op = 'eq'; field = 'assignedResourceID'; value = [long]$UserId }, [ordered]@{ op = 'gt'; field = 'createDate'; value = $since }); IncludeFields = @('id', 'createDate'); MaxRecords = 500 }
            $r = Invoke-Psa GET "/Tickets/query?search=$(Q ($s | ConvertTo-Json -Depth 6 -Compress))"
            $top = @(Get-Prop $r 'items' | Where-Object { $null -ne $_ } | Sort-Object { [long](Get-Prop $_ 'id') } -Descending) | Select-Object -First 1
            if (-not $top) { return $none }; return (& $date (Get-Prop $top 'createDate'))
        }
        'halopsa' { $t = @(Get-Prop (Invoke-Psa GET "/Tickets?agent_id=$UserId&order=dateoccurred&orderdesc=true&pageinate=true&page_size=1&page_no=1") 'tickets'); if (-not $t.Count -or $null -eq $t[0]) { return $none }; return (& $date (Get-Prop $t[0] 'dateoccurred')) }
        'kaseyabms' { return $null }
        'syncro' {
            $latest = $none
            for ($p = 1; $p -le 10; $p++) {
                $r = Invoke-Psa GET "/tickets?user_id=$UserId&page=$p"
                foreach ($t in @(Get-Prop $r 'tickets' | Where-Object { $null -ne $_ })) { $d = & $date (Get-Prop $t 'created_at'); if ($d -gt $latest) { $latest = $d } }
                if ($p -ge [int](Get-Path $r 'meta.total_pages')) { break }
            }
            return $latest
        }
        'zendesk' { $t = @(Get-Prop (Invoke-Psa GET "/search?query=$(Q "type:ticket assignee:$UserId")&sort_by=created_at&sort_order=desc&per_page=1") 'results'); if (-not $t.Count -or $null -eq $t[0]) { return $none }; return (& $date (Get-Prop $t[0] 'created_at')) }
    }
}
