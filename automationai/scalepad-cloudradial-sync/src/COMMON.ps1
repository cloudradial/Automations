# ---- shared helpers (identical in every step of this workflow) ----
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-Secret { param([string]$Name) Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue }
function Get-P {
    # Safe property read under StrictMode. Path like 'hardware_asset.serial_number'.
    param($Obj, [string]$Path, $Default = $null)
    $cur = $Obj
    foreach ($part in $Path.Split('.')) {
        if ($null -eq $cur) { return $Default }
        if ($cur -is [System.Collections.IDictionary]) { if ($cur.Contains($part)) { $cur = $cur[$part] } else { return $Default } ; continue }
        $p = $cur.PSObject.Properties[$part]
        if (-not $p) { return $Default }
        $cur = $p.Value
    }
    if ($null -eq $cur) { return $Default }
    return $cur
}
function Test-Blank { param($v) if ($v -is [datetime]) { return ($v.Year -le 1) }; return ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v) -or [string]$v -match '^0001-01-01') }
# PowerShell 7 turns ISO date strings in API responses into [datetime]; normalize both ways.
function ConvertTo-IsoDate { param($v) if (Test-Blank $v) { return $null }; if ($v -is [datetime]) { return $v.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }; $d = [datetime]::MinValue; if ([datetime]::TryParse([string]$v, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$d)) { return $d.ToString('yyyy-MM-ddTHH:mm:ssZ') }; return [string]$v }
function Format-Day { param($v) $iso = ConvertTo-IsoDate $v; if (-not $iso) { return '' }; return $iso.Substring(0, [Math]::Min(10, $iso.Length)) }
function Normalize-Serial { param($s) if (Test-Blank $s) { return '' } ; return ([string]$s).Trim().ToUpperInvariant() }
function Normalize-Name { param($s) if (Test-Blank $s) { return '' } ; $t = ([string]$s).ToLowerInvariant() -replace '[^a-z0-9 ]', ' '; $t = ' ' + $t + ' '; foreach ($w in @('ltd','limited','inc','llc','plc','group','the','co','corp','corporation','company')) { $t = $t -replace " $w ", ' ' }; return ($t -replace '\s+', ' ').Trim() }

$warnings = New-Object System.Collections.ArrayList
function Warn { param([string]$m) $null = $warnings.Add($m) }

function ConvertTo-Dict {
    param($o)
    if ($null -eq $o) { return [ordered]@{} }
    if ($o -is [System.Collections.IDictionary]) { return $o }
    $h = [ordered]@{}
    foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }
    return $h
}

# Context from the previous step (or the run inputs on the first step).
# First step: the run's Trigger input (may be empty). Later steps: the previous step's ctx.
$nodeIn = Get-NodeInput
if ($nodeIn -is [string] -and $nodeIn.Trim().StartsWith('{')) { $nodeIn = $nodeIn | ConvertFrom-Json }
$ctx = Get-P $nodeIn 'ctx'
if ($null -eq $ctx) { $ctx = Get-P $nodeIn 'trigger' }
if ($ctx -is [string]) { $ctx = $(if ($ctx.Trim().StartsWith('{')) { $ctx | ConvertFrom-Json } else { $null }) }
if ($null -eq $ctx) { $ctx = $nodeIn }
$ctx = ConvertTo-Dict $ctx

$spBase = Get-Secret 'ScalePad-ApiUrl'
$spKey = Get-Secret 'ScalePad-ApiKey'
$crBase = Get-Secret 'CloudRadial-BaseUrl'
$crPub = Get-Secret 'CloudRadial-PublicKey'
$crPriv = Get-Secret 'CloudRadial-PrivateKey'
$missingSecrets = @()
foreach ($p in @(@{ n = 'ScalePad-ApiUrl'; v = $spBase }, @{ n = 'ScalePad-ApiKey'; v = $spKey }, @{ n = 'CloudRadial-BaseUrl'; v = $crBase }, @{ n = 'CloudRadial-PublicKey'; v = $crPub }, @{ n = 'CloudRadial-PrivateKey'; v = $crPriv })) { if (Test-Blank $p.v) { $missingSecrets += $p.n } }
if ($missingSecrets.Count -gt 0) {
    $m = "Please add the following secret(s) to your runner Key Vault and re-run this workflow: $($missingSecrets -join ', ')"
    Set-NodeOutput @{ status = 'error'; message = $m }
    throw $m
}
$spBase = $spBase.TrimEnd('/')
$crBase = $crBase.TrimEnd('/')
$spHeaders = @{ 'x-api-key' = $spKey; Accept = 'application/json' }
$crAuth = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($crPub):$($crPriv)"))
$crHeaders = @{ Authorization = $crAuth; Accept = 'application/json' }

# Connection-level failures (TLS handshake, DNS, reset, timeout) that are worth trying again.
$TransientPattern = 'SSL connection could not be established|could not be established|No such host|Name or service not known|actively refused|forcibly closed|connection was closed|error occurred while sending the request|timed out|TaskCanceled|operation was canceled'
function Invoke-WithRetry {
    param([scriptblock]$Call, [string]$What)
    for ($i = 1; $i -le 4; $i++) {
        try { return & $Call }
        catch {
            $code = $null
            try { $code = [int]$_.Exception.Response.StatusCode } catch { }
            $msg = [string]$_.Exception.Message
            if ($_.Exception.InnerException) { $msg += " ($($_.Exception.InnerException.Message))" }
            $isGet = $What -match ' GET '
            $retry = ($code -eq 429) -or (-not $code -and $msg -match $TransientPattern) -or ($isGet -and $code -in @(502, 503, 504))
            if ($retry -and $i -lt 4) { Start-Sleep -Seconds (5 * $i); continue }
            throw "$What failed$(if ($code) { " (HTTP $code)" }): $msg"
        }
    }
}
function Get-SpAll {
    # Follows ScalePad next_cursor until the set is complete. Query values are passed raw (filter[x]=eq:y).
    # Most lists take page_size 200; some (installed software) cap at 100, so a 400 on the first page retries at 100.
    param([string]$Path, [hashtable]$Query = @{}, [int]$MaxPages = 500, [int]$PageSize = 200)
    $items = New-Object System.Collections.ArrayList
    $cursor = $null
    # Variants tried in order when the first page is refused: smaller page, filter without the
    # "eq:" operator, client_id instead of filter[client.id], then no page_size at all.
    $variant = 0
    $noPageSize = $false
    $baseQuery = @{} + $Query
    for ($page = 1; $page -le $MaxPages; $page++) {
        $q = @{} + $baseQuery
        if (-not $noPageSize) { $q['page_size'] = $PageSize }
        if ($cursor) { $q['cursor'] = $cursor }
        $qs = ($q.GetEnumerator() | ForEach-Object { [uri]::EscapeDataString($_.Key) + '=' + [uri]::EscapeDataString([string]$_.Value) }) -join '&'
        $uri = "$spBase$Path" + $(if ($qs) { "?$qs" } else { '' })
        try { $resp = Invoke-WithRetry -What "ScalePad GET $Path" -Call { Invoke-RestMethod -Method Get -Uri $uri -Headers $spHeaders } }
        catch {
            if ($page -eq 1 -and "$_" -match 'HTTP 4(00|22)') {
                $variant++
                if ($variant -eq 1 -and $PageSize -gt 100) { $PageSize = 100; $page = 0; continue }
                if ($variant -le 2 -and @($baseQuery.Values | Where-Object { "$_" -match '^eq:' }).Count) { $variant = 2; foreach ($k in @($baseQuery.Keys)) { $baseQuery[$k] = ([string]$baseQuery[$k]) -replace '^eq:', '' }; $page = 0; continue }
                if ($variant -le 3 -and $baseQuery.ContainsKey('filter[client.id]')) { $variant = 3; $baseQuery['client_id'] = ([string]$baseQuery['filter[client.id]']) -replace '^eq:', ''; $baseQuery.Remove('filter[client.id]'); $page = 0; continue }
                if (-not $noPageSize) { $variant = 4; $noPageSize = $true; $page = 0; continue }
            }
            throw
        }
        foreach ($d in @(Get-P $resp 'data' @())) { if ($null -ne $d) { $null = $items.Add($d) } }
        $cursor = Get-P $resp 'next_cursor'
        if (Test-Blank $cursor) { break }
        if ($page -eq $MaxPages) { Warn "ScalePad $Path stopped at $MaxPages pages." }
    }
    return $items.ToArray()
}
function Get-SpOne { param([string]$Path) Invoke-WithRetry -What "ScalePad GET $Path" -Call { Invoke-RestMethod -Method Get -Uri "$spBase$Path" -Headers $spHeaders } }
function Invoke-Cr {
    param([string]$Method, [string]$Path, $Body, [string]$ContentType = 'application/json')
    $uri = if ($Path -match '^https?://') { $Path } else { "$crBase$Path" }
    $args2 = @{ Method = $Method; Uri = $uri; Headers = $crHeaders }
    if ($null -ne $Body) {
        $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 12 }
        if ($Method -eq 'PATCH' -and $json -notmatch '^\s*\[') { $json = "[$json]" }
        $args2.Body = $json
        $args2.ContentType = $(if ($Method -eq 'PATCH') { 'application/json-patch+json' } else { $ContentType })
    }
    return Invoke-WithRetry -What "CloudRadial $Method $Path" -Call { Invoke-RestMethod @args2 }
}
function Get-CrAll {
    # CloudRadial's OData lists stop at a server page (200 rows seen live) without an
    # @odata.nextLink, so page explicitly with $top/$skip until a short or empty page.
    # A nextLink, when one is returned, is still followed.
    param([string]$Path, [int]$PageSize = 100)
    $items = New-Object System.Collections.ArrayList
    if ($Path -match '[?&]\$(top|skip)=') {
        # Caller asked for a specific slice - honour it as-is.
        $resp = Invoke-Cr -Method GET -Path $Path
        foreach ($v in @(Get-P $resp 'value' @())) { if ($null -ne $v) { $null = $items.Add($v) } }
        return $items.ToArray()
    }
    $sep = if ($Path.Contains('?')) { '&' } else { '?' }
    $skip = 0; $prevFirst = $null
    for ($pageNo = 0; $pageNo -lt 2000; $pageNo++) {
        $resp = Invoke-Cr -Method GET -Path "$Path$($sep)`$top=$PageSize&`$skip=$skip"
        $rows = @(@(Get-P $resp 'value' @()) | Where-Object { $null -ne $_ })
        if ($rows.Count -eq 0) { break }
        $first = $rows[0] | ConvertTo-Json -Depth 3 -Compress
        if ($skip -gt 0 -and $first -eq $prevFirst) { break }   # server ignored $skip - stop rather than repeat
        $prevFirst = $first
        foreach ($v in $rows) { $null = $items.Add($v) }
        $next = Get-P $resp '@odata.nextLink'
        if ($next) {
            # The server offered its own paging - follow it for the rest.
            $guard = 0
            while ($next -and $guard -lt 2000) { $guard++; $r2 = Invoke-Cr -Method GET -Path $next; foreach ($v in @(Get-P $r2 'value' @())) { if ($null -ne $v) { $null = $items.Add($v) } }; $next = Get-P $r2 '@odata.nextLink' }
            break
        }
        if ($rows.Count -lt $PageSize) { break }
        $skip += $rows.Count
    }
    return $items.ToArray()
}
function Get-CrBetaAll {
    # /api/beta/* lists page with Skip/Take and return 10 rows by default.
    param([string]$Path, [int]$Take = 100, [int]$MaxPages = 50)
    $all = New-Object System.Collections.ArrayList
    $sep = if ($Path.Contains('?')) { '&' } else { '?' }
    for ($p = 0; $p -lt $MaxPages; $p++) {
        $raw = Invoke-Cr -Method GET -Path "$Path$($sep)Skip=$($p * $Take)&Take=$Take"
        $rows = @($raw)
        foreach ($k in @('value', 'data', 'items', 'archives')) { if ($rows.Count -eq 1 -and $null -ne (Get-P $rows[0] $k)) { $rows = @(Get-P $rows[0] $k @()) } }
        $rows = @($rows | Where-Object { $null -ne $_ })
        foreach ($r in $rows) { $null = $all.Add($r) }
        if ($rows.Count -lt $Take) { break }
    }
    return $all.ToArray()
}
function Get-CrArchive {
    # Finds a company report archive by name (legacy /api/beta/archive, which also returns
    # its inboundAddress); creates it when -Create is set. Returns $null when absent.
    # The create response doesn't reliably carry the id (a live run uploaded to archive 0), so the
    # id is read from any known shape and, failing that, the archive is looked up again by name.
    param([int]$CompanyId, [string]$Name, [switch]$Create, [string]$Category = 'ScalePad')
    function Get-ArchiveId { param($a) if ($null -eq $a) { return 0 }; if ($a -is [int] -or $a -is [long] -or ([string]$a -match '^\d+$')) { return [int]$a }; foreach ($k in @('id', 'archiveId', 'companyReportFolderId', 'data.id', 'data.archiveId')) { $v = Get-P $a $k; if ($v -and [string]$v -match '^\d+$' -and [int]$v -gt 0) { return [int]$v } }; return 0 }
    $script:ArchiveSeen = @()
    function Find-Archive {
        foreach ($path in @('/api/beta/archive')) {
            $list = @(); try { $list = @(Get-CrBetaAll $path) } catch { $script:ArchiveSeen += "GET $path failed: $($_.Exception.Message)"; continue }
            $first = if ($list.Count) { ($list[0] | ConvertTo-Json -Depth 2 -Compress) } else { '' }
            $script:ArchiveSeen += "GET $path returned $($list.Count) archive(s)$(if ($first) { '; first: ' + $first.Substring(0, [Math]::Min(300, $first.Length)) })"
            $hit = @($list | Where-Object {
                $n = [string](Get-P $_ 'name' (Get-P $_ 'archiveName' (Get-P $_ 'title' '')))
                $c = Get-P $_ 'companyId' (Get-P $_ 'company.companyId' $CompanyId)
                $_ -and $n.Trim().ToLowerInvariant() -eq $Name.Trim().ToLowerInvariant() -and ($c -as [int]) -eq $CompanyId
            }) | Select-Object -First 1
            if ($null -ne $hit) { return $hit }
        }
        return $null
    }
    $hit = Find-Archive
    if ($null -eq $hit -and $Create) {
        # A 400 here has meant "already exists" (the list missed it) - look again before giving up.
        try { $resp = Invoke-Cr -Method POST -Path '/api/beta/archive' -Body ([ordered]@{ companyId = $CompanyId; name = $Name; category = $Category }) }
        catch { $again = Find-Archive; if ($null -ne $again) { $resp = $again } else { throw "Couldn't create or find the '$Name' report archive: $($_.Exception.Message). Lookup: $($script:ArchiveSeen -join ' | ')" } }
        $id = Get-ArchiveId $resp
        $hit = if ($id -gt 0) { [pscustomobject]@{ id = $id; companyId = $CompanyId; name = $Name } } else { Find-Archive }
    }
    if ($null -eq $hit) { return $null }
    $id = Get-ArchiveId $hit
    if ($id -le 0) { throw "Found the '$Name' archive but couldn't read its id." }
    return [pscustomobject]@{ id = $id; companyId = $CompanyId; name = $Name; inboundAddress = (Get-P $hit 'inboundAddress') }
}
function New-PatchOps { param([hashtable]$Fields) return @($Fields.GetEnumerator() | ForEach-Object { @{ op = 'replace'; path = '/' + $_.Key; value = $_.Value } }) }

$mode = [string](Get-P $ctx 'mode' 'plan')
if ($mode -notin @('plan', 'apply')) { $mode = 'plan' }
$apply = ($mode -eq 'apply')
# ---- end shared helpers ----
