# ---------- _shared/cloudradial.ps1: CloudRadial API for AutomationAI steps ----------
# Edit this file, then run: node _shared/inject.js <automation-folder>
# Lifted from endpoint-lifecycle-manager/src/elm.ps1 and the ScalePad sync's archive helpers.
# Secrets (runner Key Vault): CloudRadial-BaseUrl, CloudRadial-PublicKey, CloudRadial-PrivateKey.
# Reports for a client go to Report Archives (Compliance > Reports, admins only), never to the
# knowledge base, and never carry another client's data.
# All state lives in the $CrState hashtable and is changed in place, because the runner
# runs a step in a child scope where $script: variables don't behave.

$CrState = @{
    Base        = $null
    Headers     = $null
    MaxAttempts = 6
    # A new Planner card needs a category: POST /v2/product answers 400 "The Category field is required" without one.
    # These are Endpoint LifeCycle Manager's defaults; a build's own category and productCategoryId always win.
    CardCategory          = 'Efficiency'
    CardProductCategoryId = 7
}

# ---- small helpers (all Cr-prefixed so they don't clash with other shared files) ----
function Get-CrSecret { param([string]$Name) $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue } catch { }; return $v }
function Get-CrProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-CrHttpStatus { param($Err) $c = 0; try { $c = [int]$Err.Exception.Response.StatusCode } catch { }; return $c }
function Get-CrRetryAfter { param($Err, [int]$Attempt) $s = 0; try { $ra = $Err.Exception.Response.Headers.RetryAfter; if ($null -ne $ra -and $null -ne $ra.Delta) { $s = [int][Math]::Ceiling($ra.Delta.TotalSeconds) } elseif ($null -ne $ra -and $null -ne $ra.Date) { $s = [int][Math]::Ceiling(($ra.Date.UtcDateTime - [datetime]::UtcNow).TotalSeconds) } } catch { }; if ($s -le 0) { $s = [int][Math]::Min(30, [Math]::Pow(2, $Attempt)) }; return [Math]::Min($s, 120) }
function Get-CrId { param($o, [string[]]$Names) foreach ($n in $Names) { $v = $o; foreach ($part in $n -split '\.') { $v = Get-CrProp $v $part }; if ($null -ne $v -and [string]$v -match '^\d+$' -and [long]$v -gt 0) { return [int]$v } }; return 0 }

# Reads the API keys from the runner Key Vault (or takes them as parameters). Returns @{ Base }.
function Connect-Cr {
    param([string]$BaseUrl, [string]$PublicKey, [string]$PrivateKey)
    if ([string]::IsNullOrWhiteSpace($BaseUrl)) { $BaseUrl = Get-CrSecret 'CloudRadial-BaseUrl' }
    if ([string]::IsNullOrWhiteSpace($PublicKey)) { $PublicKey = Get-CrSecret 'CloudRadial-PublicKey' }
    if ([string]::IsNullOrWhiteSpace($PrivateKey)) { $PrivateKey = Get-CrSecret 'CloudRadial-PrivateKey' }
    $missing = @()
    if ([string]::IsNullOrWhiteSpace($BaseUrl)) { $missing += 'CloudRadial-BaseUrl' }
    if ([string]::IsNullOrWhiteSpace($PublicKey)) { $missing += 'CloudRadial-PublicKey' }
    if ([string]::IsNullOrWhiteSpace($PrivateKey)) { $missing += 'CloudRadial-PrivateKey' }
    if ($missing.Count) { throw "Add these secrets to the runner Key Vault: $($missing -join ', ')" }
    $CrState.Base = $BaseUrl.Trim().TrimEnd('/')
    $CrState.Headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($PublicKey.Trim()):$($PrivateKey.Trim())")); Accept = 'application/json' }
    return @{ Base = $CrState.Base }
}

# One CloudRadial call. Path is relative to the base URL (or a full URL).
# Retries 429, GET 5xx and dropped connections, honoring Retry-After; other errors throw a plain message.
function Invoke-CrApi {
    param([string]$Path, [string]$Method = 'GET', $Body = $null, [string]$ContentType = 'application/json')
    if ($null -eq $CrState.Headers) { throw 'Call Connect-Cr before any other CloudRadial function.' }
    $url = if ($Path -match '^https?://') { $Path } else { "$($CrState.Base)$Path" }
    for ($i = 1; $i -le $CrState.MaxAttempts; $i++) {
        try {
            $a = @{ Uri = $url; Method = $Method; Headers = $CrState.Headers; ContentType = $ContentType; ErrorAction = 'Stop' }
            if ($null -ne $Body) { $a.Body = $(if ($Body -is [string]) { $Body } else { ConvertTo-Json -InputObject $Body -Depth 12 }) }
            return Invoke-RestMethod @a
        }
        catch {
            $code = Get-CrHttpStatus $_
            $msg = [string]$_.Exception.Message
            $transient = (-not $code -and $msg -match 'SSL connection|could not be established|No such host|actively refused|forcibly closed|error occurred while sending|timed out|TaskCanceled')
            if (($code -eq 429 -or ($Method -eq 'GET' -and $code -ge 500) -or $transient) -and $i -lt $CrState.MaxAttempts) { Start-Sleep -Seconds (Get-CrRetryAfter $_ $i); continue }
            $detail = $msg; try { if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message } } catch { }
            throw "CloudRadial $Method $Path failed$(if ($code) { " (HTTP $code)" }): $detail"
        }
    }
}

# Every row of a /v2/odata list. Those lists stop at 200 rows with no nextLink, so this pages with $top/$skip.
# Wrap the result in @(...).
function Get-CrAll {
    param([string]$Path, [int]$PageSize = 200, [int]$MaxPages = 500)
    $rows = New-Object System.Collections.ArrayList; $skip = 0
    for ($n = 0; $n -lt $MaxPages; $n++) {
        $sep = if ($Path -match '\?') { '&' } else { '?' }
        $resp = Invoke-CrApi -Path "$Path$sep`$top=$PageSize&`$skip=$skip"
        $batch = @(); $v = Get-CrProp $resp 'value'
        if ($null -ne $v) { $batch = @($v) } elseif ($resp -is [array]) { $batch = @($resp) }
        $batch = @($batch | Where-Object { $null -ne $_ })
        foreach ($r in $batch) { $null = $rows.Add($r) }
        if ($batch.Count -lt $PageSize) { break }
        $skip += $PageSize
    }
    return @($rows)
}

# Every row of a legacy /api/beta list. Those page with Skip/Take and return 10 rows by default.
function Get-CrBetaAll {
    param([string]$Path, [int]$Take = 100, [int]$MaxPages = 50)
    $all = New-Object System.Collections.ArrayList
    $sep = if ($Path.Contains('?')) { '&' } else { '?' }
    for ($p = 0; $p -lt $MaxPages; $p++) {
        $raw = Invoke-CrApi -Path "$Path$($sep)Skip=$($p * $Take)&Take=$Take"
        $rows = @($raw)
        foreach ($k in @('value', 'data', 'items', 'archives')) { if ($rows.Count -eq 1 -and $null -ne (Get-CrProp $rows[0] $k)) { $rows = @(Get-CrProp $rows[0] $k) } }
        $rows = @($rows | Where-Object { $null -ne $_ })
        foreach ($r in $rows) { $null = $all.Add($r) }
        if ($rows.Count -lt $Take) { break }
    }
    return @($all)
}

# Creates or updates one Planner card (a CloudRadial "product") for a company, so a run never duplicates a card.
# It finds the company's card whose subject matches -Subject, or whose body holds -Key, and updates it; otherwise it creates one.
#   -Fields    the card's other fields: body, summary, notes, category, productCategoryId, priority (1 high, 0 medium, -1 low),
#              status (0 open, 20 scheduled, 40 completed), productType, scheduledQuarter, quarterOffset, and so on
#   -Key       a stable marker. It is added to the end of the body when missing, so the card is found again after its subject changes
#   -Existing  the company's cards when already read (saves a call per card); otherwise they are read here
#   -Preview   work out what would happen without writing
# Returns @{ action = created | updated | would-create | would-update; productId; optionalFieldsDropped }.
function Set-CrPlannerCard {
    param([int]$CompanyId, [string]$Subject, [hashtable]$Fields = @{}, [string]$Key = '', $Existing = $null, [switch]$Preview)
    if ([string]::IsNullOrWhiteSpace($Subject)) { throw 'Set-CrPlannerCard needs a subject.' }
    $cards = if ($null -ne $Existing) { @($Existing) } else { @(Get-CrAll "/v2/odata/product?`$filter=companyId eq $CompanyId") }
    $want = $Subject.Trim()
    $card = @($cards | Where-Object {
            $null -ne $_ -and ($null -eq (Get-CrProp $_ 'companyId') -or [int](Get-CrProp $_ 'companyId') -eq $CompanyId) -and (
                ([string](Get-CrProp $_ 'subject')).Trim() -ieq $want -or ($Key -and ([string](Get-CrProp $_ 'body')).Contains($Key)))
        }) | Select-Object -First 1
    $f = [ordered]@{ subject = $want }
    foreach ($k in $Fields.Keys) { if ($k -ne 'subject') { $f[$k] = $Fields[$k] } }
    if ($Key -and $f.Contains('body') -and -not ([string]$f['body']).Contains($Key)) { $f['body'] = "$($f['body'])<p><em>$Key</em></p>" }
    $optional = @('notes', 'productType', 'scheduledQuarter', 'quarterOffset')
    $dropped = $false

    if ($null -ne $card) {
        $id = [string](Get-CrProp $card 'productId')
        if ($Preview) { return @{ action = 'would-update'; productId = $id; optionalFieldsDropped = $false } }
        $ops = @($f.GetEnumerator() | ForEach-Object { @{ op = 'replace'; path = "/$($_.Key)"; value = $_.Value } })
        try { $null = Invoke-CrApi -Path "/v2/product/$id" -Method PATCH -Body $ops -ContentType 'application/json-patch+json' }
        catch {
            # Older portals may not take notes or the roadmap fields: write the card without them.
            $core = @($ops | Where-Object { $_.path.TrimStart('/') -notin $optional })
            if ($core.Count -eq $ops.Count) { throw }
            $null = Invoke-CrApi -Path "/v2/product/$id" -Method PATCH -Body $core -ContentType 'application/json-patch+json'
            $dropped = $true
        }
        return @{ action = 'updated'; productId = $id; optionalFieldsDropped = $dropped }
    }

    if ($Preview) { return @{ action = 'would-create'; productId = ''; optionalFieldsDropped = $false } }
    $body = [ordered]@{ companyId = $CompanyId; datePublished = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ'); isRequired = $false; isShowPrice = $false; isClientVisible = $false; status = 0 }
    foreach ($k in $f.Keys) { $body[$k] = $f[$k] }
    if ([string]::IsNullOrWhiteSpace([string]$body['category'])) { $body['category'] = $CrState.CardCategory }
    if (-not $body.Contains('productCategoryId') -or $null -eq $body['productCategoryId']) { $body['productCategoryId'] = $CrState.CardProductCategoryId }
    $new = $null
    try { $new = Invoke-CrApi -Path '/v2/product' -Method POST -Body $body }
    catch {
        $had = @($optional | Where-Object { $body.Contains($_) })
        if (-not $had.Count) { throw }
        foreach ($k in $had) { $body.Remove($k) }
        $new = Invoke-CrApi -Path '/v2/product' -Method POST -Body $body
        $dropped = $true
    }
    # POST replies { success, message, data = { productId, ... } }.
    $newId = Get-CrId $new @('productId', 'data.productId')
    return @{ action = 'created'; productId = $(if ($newId) { [string]$newId } else { '' }); optionalFieldsDropped = $dropped }
}

# Finds a company's report archive by name through the legacy /api/beta/archive list (which ignores
# companyId, so it is filtered here), and creates it with -Create. Returns @{ id; companyId; name; inboundAddress } or $null.
# The create reply doesn't always carry the new id, so the archive is looked up again by name.
function Get-CrArchive {
    param([int]$CompanyId, [string]$Name, [switch]$Create, [string]$Category = 'AutomationAI')
    $find = {
        $list = @(Get-CrBetaAll '/api/beta/archive')
        @($list | Where-Object {
                $n = [string](Get-CrProp $_ 'name'); if (-not $n) { $n = [string](Get-CrProp $_ 'archiveName') }
                $c = Get-CrProp $_ 'companyId'
                $n.Trim() -ieq $Name.Trim() -and ($null -eq $c -or [int]$c -eq $CompanyId)
            }) | Select-Object -First 1
    }
    $hit = & $find
    if ($null -eq $hit -and $Create) {
        $resp = $null
        # A 400 here has meant "already exists" when the list missed it, so look again before giving up.
        try { $resp = Invoke-CrApi -Path '/api/beta/archive' -Method POST -Body ([ordered]@{ companyId = $CompanyId; name = $Name; category = $Category }) }
        catch { $again = & $find; if ($null -eq $again) { throw "Couldn't create or find the '$Name' report archive: $($_.Exception.Message)" }; $resp = $again }
        $id = Get-CrId $resp @('id', 'archiveId', 'companyReportFolderId', 'data.id', 'data.archiveId')
        if (-not $id -and ([string]$resp -match '^\d+$')) { $id = [int][string]$resp }
        $hit = if ($id) { [pscustomobject]@{ id = $id; companyId = $CompanyId; name = $Name } } else { & $find }
    }
    if ($null -eq $hit) { return $null }
    $aid = Get-CrId $hit @('id', 'archiveId', 'companyReportFolderId')
    if (-not $aid) { throw "Found the '$Name' archive but couldn't read its id." }
    return @{ id = $aid; companyId = $CompanyId; name = $Name; inboundAddress = [string](Get-CrProp $hit 'inboundAddress') }
}

# Writes an HTML report into a company's Report Archive (Compliance > Reports, admins only), creating the archive
# when needed. An item with the same subject is replaced, so a re-run updates the report instead of piling up.
# Never falls back to a knowledge base article: if this throws, keep the report in the run output.
# Returns @{ action = created | updated | would-write; archiveId; itemId; location }.
function Add-CrArchiveReport {
    param([int]$CompanyId, [string]$ArchiveName, [string]$Subject, [string]$Html, [string]$Category = 'AutomationAI', [switch]$IsError, [switch]$Preview)
    if ([string]::IsNullOrWhiteSpace($ArchiveName) -or [string]::IsNullOrWhiteSpace($Subject)) { throw 'Add-CrArchiveReport needs an archive name and a subject.' }
    $where = "Report archive '$ArchiveName' (Compliance > Reports, admins only), item '$Subject'"
    $arch = Get-CrArchive -CompanyId $CompanyId -Name $ArchiveName -Create:(-not $Preview) -Category $Category
    if ($Preview) { return @{ action = 'would-write'; archiveId = $(if ($arch) { $arch.id } else { 0 }); itemId = 0; location = $where } }
    $aid = [int]$arch.id
    $esc = $Subject.Replace("'", "''")
    $prev = $null
    try { $prev = @(Get-CrAll "/v2/odata/archiveitem?`$filter=$([uri]::EscapeDataString("companyId eq $CompanyId and companyReportFolderId eq $aid and subject eq '$esc'"))&`$select=companyReportItemId,subject") | Where-Object { ([string](Get-CrProp $_ 'subject')) -eq $Subject } | Select-Object -First 1 } catch { $prev = $null }
    $item = [ordered]@{ companyId = $CompanyId; archiveId = $aid; subject = $Subject; text = $Html; isHtml = $true; isError = [bool]$IsError }
    $iid = Get-CrId $prev @('companyReportItemId')
    if ($iid) {
        $null = Invoke-CrApi -Path "/v2/archiveitem/$aid/$iid" -Method PUT -Body $item
        return @{ action = 'updated'; archiveId = $aid; itemId = $iid; location = $where }
    }
    $r = Invoke-CrApi -Path '/v2/archiveitem' -Method POST -Body $item
    return @{ action = 'created'; archiveId = $aid; itemId = (Get-CrId $r @('companyReportItemId', 'id', 'data.companyReportItemId', 'data.id')); location = $where }
}
# ---------- end _shared/cloudradial.ps1 ----------
