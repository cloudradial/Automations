# =====================================================================
#  ScalePad Warranty Sync - no-AI workflow step
#  Keeps CloudRadial endpoint warranty dates matched to ScalePad Lifecycle Manager, and keeps one
#  "Endpoint Warranty Renewal" Planner card per company listing the computers whose warranty has
#  ended. Nothing else is moved: no Planner cards from initiatives, contracts or insights, no
#  flexible assets, software, assessments or meetings. The card never mentions ScalePad.
#  Run input (all optional):
#    confirm            true makes the changes; anything else previews them (default)
#    companyIds         limit to these CloudRadial company ids ("12,40" or [12,40])
#    pairs              pair a CloudRadial company with a ScalePad client when the names differ or
#                       several match: {"28": "<ScalePad client id>"}
#    overwriteWarranty  false keeps a CloudRadial warranty date that differs from ScalePad's (default true)
#    fillPurchaseDate   false skips filling a blank purchase date (manufacturedDate) from ScalePad (default true)
#    warrantyCard       false skips the Planner card (default true)
#    expiringWithinDays also list warranties ending within this many days (default 0: ended only)
#    skipReplaceCard    false lists computers that are on the "Endpoint Hardware Refresh - Replace" card too (default true)
#    plannerCategory / plannerProductCategoryId   the card's category (default Efficiency / 7)
#    secretSuffix       read <secret>-<suffix> first (company-scoped secrets), then the plain name
#  Secrets (runner Key Vault): CloudRadial-BaseUrl, CloudRadial-PublicKey, CloudRadial-PrivateKey,
#  ScalePad-ApiUrl, ScalePad-ApiKey.
# =====================================================================
$ErrorActionPreference = 'Stop'

# ---- run input ----
$in = $null; try { $in = Get-NodeInput } catch { }
$t = Get-CrProp $in 'trigger'; if ($null -ne $t) { $in = $t }
if ($in -is [string]) { $in = $(if ($in.Trim().StartsWith('{')) { $in | ConvertFrom-Json } else { $null }) }
function Test-Yes { param($v, [bool]$Default) if ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v)) { return $Default }; if ($v -is [bool]) { return $v }; return ([string]$v).Trim() -match '^(?i)(true|yes|y|1)$' }
$Ws = @{
    Confirm        = Test-Yes (Get-CrProp $in 'confirm') $false
    Overwrite      = Test-Yes (Get-CrProp $in 'overwriteWarranty') $true
    FillPurchase   = Test-Yes (Get-CrProp $in 'fillPurchaseDate') $true
    Card           = Test-Yes (Get-CrProp $in 'warrantyCard') $true
    SkipReplace    = Test-Yes (Get-CrProp $in 'skipReplaceCard') $true
    ExpiringDays   = 0
    Category       = [string](Get-CrProp $in 'plannerCategory')
    CategoryId     = 7
    Suffix         = ([string](Get-CrProp $in 'secretSuffix')).Trim()
    CompanyIds     = @(@(Get-CrProp $in 'companyIds') | ForEach-Object { ([string]$_) -split '[,;\s]+' } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } | Select-Object -Unique)
    Pairs          = @{}
}
$d = 0; if ([int]::TryParse([string](Get-CrProp $in 'expiringWithinDays'), [ref]$d) -and $d -gt 0) { $Ws.ExpiringDays = [Math]::Min($d, 365) }
$d = 0; if ([int]::TryParse([string](Get-CrProp $in 'plannerProductCategoryId'), [ref]$d) -and $d -gt 0) { $Ws.CategoryId = $d }
if (-not $Ws.Category) { $Ws.Category = 'Efficiency' }
$pairsIn = Get-CrProp $in 'pairs'
if ($null -ne $pairsIn) {
    $kv = if ($pairsIn -is [System.Collections.IDictionary]) { @($pairsIn.GetEnumerator() | ForEach-Object { @{ k = [string]$_.Key; v = [string]$_.Value } }) } else { @($pairsIn.PSObject.Properties | ForEach-Object { @{ k = [string]$_.Name; v = [string]$_.Value } }) }
    foreach ($p in $kv) { if ($p.k -match '^\d+$' -and -not [string]::IsNullOrWhiteSpace($p.v)) { $Ws.Pairs[[int]$p.k] = $p.v.Trim() } }
}

$Out = @{
    warnings = (New-Object System.Collections.ArrayList); actions = (New-Object System.Collections.ArrayList); details = (New-Object System.Collections.ArrayList)
    counts   = [ordered]@{ companies = 0; endpointsChecked = 0; matched = 0; warrantyUpdated = 0; purchaseDateFilled = 0; differencesKept = 0; noSerial = 0; notInCloudRadial = 0; outOfWarranty = 0; cardsCreated = 0; cardsUpdated = 0; cardsClosed = 0; cardsReopened = 0; errors = 0 }
}
function Add-Warning { param([string]$m) if ($Out.warnings.Count -lt 60) { $null = $Out.warnings.Add($m) } }
function Send-Result {
    param([string]$Status, [string]$Message, [string]$Public = '')
    Set-NodeOutput ([ordered]@{
        status = $Status; message = $Message; public_note = $(if ($Public) { $Public } else { $Message }); internal_note = (@($Out.details) -join "`n")
        confirmed = $Ws.Confirm; actions = @($Out.actions | Select-Object -First 200); warnings = @($Out.warnings); counts = $Out.counts
    })
}

# ---- secrets (company-scoped first when secretSuffix is set) ----
function Get-WsSecret { param([string]$Name)
    if ($Ws.Suffix) { $v = Get-CrSecret "$Name-$($Ws.Suffix)"; if (-not [string]::IsNullOrWhiteSpace([string]$v)) { return [string]$v } }
    return [string](Get-CrSecret $Name)
}
$sec = [ordered]@{}; foreach ($n in @('CloudRadial-BaseUrl', 'CloudRadial-PublicKey', 'CloudRadial-PrivateKey', 'ScalePad-ApiUrl', 'ScalePad-ApiKey')) { $sec[$n] = Get-WsSecret $n }
$missing = @($sec.Keys | Where-Object { [string]::IsNullOrWhiteSpace($sec[$_]) })
if ($missing.Count) { $m = "Please add these secrets to your runner Key Vault (or set this step's Company) and run again: $($missing -join ', ')"; Send-Result 'error' $m; throw $m }
$null = Connect-Cr -BaseUrl $sec['CloudRadial-BaseUrl'] -PublicKey $sec['CloudRadial-PublicKey'] -PrivateKey $sec['CloudRadial-PrivateKey']
$Sp = @{ Base = $sec['ScalePad-ApiUrl'].Trim().TrimEnd('/'); Headers = @{ 'x-api-key' = $sec['ScalePad-ApiKey'].Trim(); Accept = 'application/json' } }

# ---- ScalePad reads ----
function Invoke-Sp { param([string]$Uri)
    for ($i = 1; $i -le 5; $i++) {
        try { return Invoke-RestMethod -Method Get -Uri $Uri -Headers $Sp.Headers -ErrorAction Stop }
        catch {
            $code = Get-CrHttpStatus $_
            $msg = [string]$_.Exception.Message
            $transient = (-not $code -and $msg -match 'SSL connection|could not be established|No such host|actively refused|forcibly closed|error occurred while sending|timed out|TaskCanceled')
            if (($code -eq 429 -or $code -ge 500 -or $transient) -and $i -lt 5) { Start-Sleep -Seconds (Get-CrRetryAfter $_ $i); continue }
            throw "ScalePad GET $(([uri]$Uri).AbsolutePath) failed$(if ($code) { " (HTTP $code)" }): $msg"
        }
    }
}
# Follows next_cursor. A 400/422 on the first page retries with a smaller page, the filter without "eq:",
# client_id in place of filter[client_id], then no page_size (ScalePad lists differ in what they accept).
function Get-SpAll { param([string]$Path, [hashtable]$Query = @{})
    $items = New-Object System.Collections.ArrayList
    $base = @{} + $Query; $size = 200; $variant = 0; $noSize = $false
    $cursor = $null
    for ($page = 1; $page -le 500; $page++) {
        $q = @{} + $base; if (-not $noSize) { $q['page_size'] = $size }; if ($cursor) { $q['cursor'] = $cursor }
        $qs = (@($q.GetEnumerator() | Sort-Object Key | ForEach-Object { [uri]::EscapeDataString($_.Key) + '=' + [uri]::EscapeDataString([string]$_.Value) })) -join '&'
        $resp = $null
        try { $resp = Invoke-Sp "$($Sp.Base)$Path$(if ($qs) { "?$qs" })" }
        catch {
            if ($page -eq 1 -and "$_" -match 'HTTP 4(00|22)') {
                $variant++
                if ($variant -eq 1 -and $size -gt 100) { $size = 100; $page = 0; continue }
                if ($variant -le 2 -and @($base.Values | Where-Object { "$_" -match '^eq:' }).Count) { $variant = 2; foreach ($k in @($base.Keys)) { $base[$k] = ([string]$base[$k]) -replace '^eq:', '' }; $page = 0; continue }
                if ($variant -le 3 -and $base.ContainsKey('filter[client_id]')) { $variant = 3; $base['client_id'] = ([string]$base['filter[client_id]']) -replace '^eq:', ''; $base.Remove('filter[client_id]'); $page = 0; continue }
                if (-not $noSize) { $variant = 4; $noSize = $true; $page = 0; continue }
            }
            throw
        }
        foreach ($x in @(@(Get-CrProp $resp 'data') | Where-Object { $null -ne $_ })) { $null = $items.Add($x) }
        $cursor = [string](Get-CrProp $resp 'next_cursor')
        if ([string]::IsNullOrWhiteSpace($cursor)) { break }
    }
    return @($items)
}

# ---- helpers ----
$Ci = [System.Globalization.CultureInfo]::InvariantCulture
$Today = (Get-Date).ToUniversalTime().Date
$TodayText = $Today.ToString('d MMM yyyy', $Ci)
function ConvertTo-Day { param($v)
    if ($null -eq $v) { return $null }
    if ($v -is [datetime]) { $dt = $v.ToUniversalTime() }
    elseif ($v -is [datetimeoffset]) { $dt = $v.UtcDateTime }
    else {
        $s = ([string]$v).Trim(); if (-not $s -or $s -match '^0001-01-01') { return $null }
        $o = [datetimeoffset]::MinValue
        if (-not [datetimeoffset]::TryParse($s, $Ci, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$o)) { return $null }
        $dt = $o.UtcDateTime
    }
    if ($dt.Year -le 1) { return $null }
    return $dt.Date
}
function Get-IsoDay { param([datetime]$Day) return $Day.ToString('yyyy-MM-ddT00:00:00Z', $Ci) }
function Get-Serial { param($s) $t = ([string]$s).Trim().ToUpperInvariant(); if ($t -match '^(N/?A|NONE|UNKNOWN|DEFAULT STRING|TO BE FILLED BY O\.E\.M\.|0+|SYSTEM SERIAL NUMBER)$') { return '' }; return $t }
function Get-NameKey { param($s) $t = ' ' + (([string]$s).ToLowerInvariant() -replace '[^a-z0-9 ]', ' ') + ' '; foreach ($w in @('ltd', 'limited', 'inc', 'llc', 'plc', 'group', 'the', 'co', 'corp', 'corporation', 'company')) { $t = $t -replace " $w ", ' ' }; return ($t -replace '\s+', ' ').Trim() }
function Enc { param($t) [System.Net.WebUtility]::HtmlEncode([string]$t) }
function Test-Completed { param($card) $s = [string](Get-CrProp $card 'status'); return ($s -eq '40' -or $s -match '(?i)^completed$') }

# ---- match CloudRadial companies to ScalePad clients by name (pairs override) ----
$crCompanies = @(Get-CrAll "/v2/odata/company?`$select=companyId,name")
$crName = @{}; foreach ($c in $crCompanies) { $crName[[int](Get-CrProp $c 'companyId')] = [string](Get-CrProp $c 'name') }
$spClients = @(Get-SpAll '/core/v1/clients')
$spName = @{}; foreach ($s in $spClients) { $spName[[string](Get-CrProp $s 'id')] = [string](Get-CrProp $s 'name') }
$crByKey = @{}; foreach ($c in $crCompanies) { $k = Get-NameKey (Get-CrProp $c 'name'); if ($k) { if (-not $crByKey.ContainsKey($k)) { $crByKey[$k] = New-Object System.Collections.ArrayList }; $null = $crByKey[$k].Add([int](Get-CrProp $c 'companyId')) } }
$candidates = @{}   # CloudRadial companyId -> ScalePad client ids with the same name
foreach ($s in $spClients) {
    $k = Get-NameKey (Get-CrProp $s 'name'); if (-not $k -or -not $crByKey.ContainsKey($k)) { continue }
    foreach ($cid in @($crByKey[$k])) { if (-not $candidates.ContainsKey($cid)) { $candidates[$cid] = New-Object System.Collections.ArrayList }; $null = $candidates[$cid].Add([string](Get-CrProp $s 'id')) }
}
$targets = @{}   # CloudRadial companyId -> ScalePad client id (a hashtable: an [ordered] dictionary reads an int key as a position)
foreach ($cid in @($candidates.Keys | Sort-Object)) {
    $ids = @($candidates[$cid] | Select-Object -Unique)
    if ($Ws.Pairs.ContainsKey($cid)) { continue }
    if ($ids.Count -eq 1) { $targets[$cid] = $ids[0]; continue }
    Add-Warning "$($crName[$cid]) ($cid) matches $($ids.Count) ScalePad clients ($((@($ids | ForEach-Object { "$($spName[$_]) = $_" })) -join '; ')), so it was skipped. Pair it with {""pairs"": {""$cid"": ""<ScalePad client id>""}}."
}
foreach ($cid in @($Ws.Pairs.Keys)) {
    if (-not $crName.ContainsKey($cid)) { Add-Warning "pairs: CloudRadial company $cid wasn't found."; continue }
    if (-not $spName.ContainsKey($Ws.Pairs[$cid])) { Add-Warning "pairs: ScalePad client $($Ws.Pairs[$cid]) wasn't found, so $($crName[$cid]) ($cid) was skipped."; continue }
    $targets[$cid] = $Ws.Pairs[$cid]
}
if ($Ws.CompanyIds.Count) {
    foreach ($cid in $Ws.CompanyIds) { if (-not $targets.Contains($cid)) { Add-Warning "Company $cid has no ScalePad client with the same name$(if (-not $crName.ContainsKey($cid)) { ' (and was not found in CloudRadial)' }). Pair it with {""pairs"": {""$cid"": ""<ScalePad client id>""}}." } }
    foreach ($cid in @($targets.Keys)) { if ($cid -notin $Ws.CompanyIds) { $targets.Remove($cid) } }
}
$matchedSp = @($targets.Values); $unmatchedSp = @($spClients | Where-Object { [string](Get-CrProp $_ 'id') -notin $matchedSp }).Count
if (-not $targets.Count) {
    $m = "No CloudRadial company matched a ScalePad client$(if ($Ws.CompanyIds.Count) { ' in companyIds' }), so nothing was checked. Rename to match, or pair them with {""pairs"": {""<companyId>"": ""<ScalePad client id>""}}."
    Send-Result 'ok' $m; return
}

# ---- per company ----
foreach ($cid in @($targets.Keys | Sort-Object)) {
    $spId = $targets[$cid]; $cname = $crName[$cid]
    $Out.counts.companies++
    $co = @{ matched = 0; updated = 0; filled = 0; kept = 0; noSerial = 0; notInCr = 0; expired = 0; expiring = 0; replaceSkipped = 0; card = '' }
    try {
        $life = @(Get-SpAll '/lifecycle-manager/v1/assets/hardware/lifecycles' @{ 'filter[client_id]' = "eq:$spId" })
        $bySerial = @{}
        foreach ($l in $life) { $sn = Get-Serial (Get-CrProp $l 'serial_number'); if ($sn) { $bySerial[$sn] = @{ warranty = ConvertTo-Day (Get-CrProp $l 'warranty_expiry_date'); purchase = ConvertTo-Day (Get-CrProp $l 'purchase_date'); seen = $false } } }
        $eps = @(Get-CrAll "/v2/odata/endpoint?`$filter=companyId eq $cid&`$select=companyEndpointId,serialNumber,name,expirationDate,manufacturedDate,isVirtual")
        $warrantyOf = New-Object System.Collections.ArrayList   # @{ name; serial; ends } for the card
        foreach ($ep in $eps) {
            $Out.counts.endpointsChecked++
            $epId = [int](Get-CrProp $ep 'companyEndpointId'); $name = [string](Get-CrProp $ep 'name'); $sn = Get-Serial (Get-CrProp $ep 'serialNumber')
            $curW = ConvertTo-Day (Get-CrProp $ep 'expirationDate'); $curP = ConvertTo-Day (Get-CrProp $ep 'manufacturedDate')
            $ends = $curW
            if (-not $sn) { $co.noSerial++ }
            elseif ($bySerial.ContainsKey($sn)) {
                $spRow = $bySerial[$sn]; $spRow.seen = $true; $co.matched++
                $ops = New-Object System.Collections.ArrayList; $what = @()
                if ($null -ne $spRow.warranty -and $spRow.warranty -ne $curW) {
                    if ($null -eq $curW -or $Ws.Overwrite) { $null = $ops.Add(@{ op = 'replace'; path = '/expirationDate'; value = (Get-IsoDay $spRow.warranty) }); $what += "warranty $(if ($curW) { $curW.ToString('yyyy-MM-dd', $Ci) } else { 'blank' }) -> $($spRow.warranty.ToString('yyyy-MM-dd', $Ci))"; $ends = $spRow.warranty; $co.updated++ }
                    else { $co.kept++; Add-Warning "$cname - $name ($sn): warranty is $($curW.ToString('yyyy-MM-dd', $Ci)) in CloudRadial and $($spRow.warranty.ToString('yyyy-MM-dd', $Ci)) in ScalePad. Left as is (overwriteWarranty is false)." }
                }
                if ($Ws.FillPurchase -and $null -eq $curP -and $null -ne $spRow.purchase) { $null = $ops.Add(@{ op = 'replace'; path = '/manufacturedDate'; value = (Get-IsoDay $spRow.purchase) }); $what += "purchase date blank -> $($spRow.purchase.ToString('yyyy-MM-dd', $Ci))"; $co.filled++ }
                if ($ops.Count) {
                    $null = $Out.actions.Add("$(if ($Ws.Confirm) { 'Updated' } else { 'Would update' }) $cname - $name ($sn): $($what -join '; ')")
                    if ($Ws.Confirm) { $null = Invoke-CrApi -Path "/v2/endpoint/id/$epId" -Method PATCH -Body @($ops) -ContentType 'application/json-patch+json' }
                }
            }
            if ($null -ne $ends -and -not [bool](Get-CrProp $ep 'isVirtual')) { $null = $warrantyOf.Add(@{ name = $name; serial = $sn; ends = $ends }) }
        }
        $co.notInCr = @($bySerial.Values | Where-Object { -not $_.seen }).Count
        $Out.counts.matched += $co.matched; $Out.counts.warrantyUpdated += $co.updated; $Out.counts.purchaseDateFilled += $co.filled
        $Out.counts.differencesKept += $co.kept; $Out.counts.noSerial += $co.noSerial; $Out.counts.notInCloudRadial += $co.notInCr

        # ---- the warranty renewal card ----
        if ($Ws.Card) {
            $cards = @(Get-CrAll "/v2/odata/product?`$filter=companyId eq $cid")
            $subject = 'Endpoint Warranty Renewal'
            $marker = "Warranty Renewal Card: company $cid"
            $card = @($cards | Where-Object { ([string](Get-CrProp $_ 'subject')).Trim() -ieq $subject -or ([string](Get-CrProp $_ 'body')).Contains($marker) }) | Select-Object -First 1
            # Computers the Endpoint LifeCycle Manager already recommends replacing are left off: they need a quote, not a warranty.
            $replaceBody = ''
            if ($Ws.SkipReplace) { $rc = @($cards | Where-Object { ([string](Get-CrProp $_ 'subject')).Trim() -eq 'Endpoint Hardware Refresh - Replace' -and -not (Test-Completed $_) }) | Select-Object -First 1; if ($null -ne $rc) { $replaceBody = [string](Get-CrProp $rc 'body') } }
            $limit = $Today.AddDays($Ws.ExpiringDays)
            $expired = New-Object System.Collections.ArrayList; $expiring = New-Object System.Collections.ArrayList
            foreach ($w in @($warrantyOf | Sort-Object { $_.ends })) {
                if ($w.ends -ge $Today -and ($Ws.ExpiringDays -le 0 -or $w.ends -gt $limit)) { continue }
                if ($replaceBody -and $w.name -and $replaceBody.Contains("<strong>$(Enc $w.name)</strong>")) { $co.replaceSkipped++; continue }
                if ($w.ends -lt $Today) { $null = $expired.Add($w) } else { $null = $expiring.Add($w) }
            }
            $co.expired = $expired.Count; $co.expiring = $expiring.Count; $Out.counts.outOfWarranty += $expired.Count
            $verb = if ($Ws.Confirm) { '' } else { 'would be ' }
            if (-not ($expired.Count + $expiring.Count)) {
                if ($null -ne $card -and -not (Test-Completed $card)) {
                    $fields = @{ status = 40; summary = "No computers are out of warranty as of $TodayText."; body = "<p>No computers at this company are out of warranty as of $TodayText.</p>" }
                    $r = Set-CrPlannerCard -CompanyId $cid -Subject $subject -Fields $fields -Key $marker -Existing $cards -Preview:(-not $Ws.Confirm)
                    $Out.counts.cardsClosed++; $co.card = "$($verb)closed (card $($r.productId))"
                    $null = $Out.actions.Add("$(if ($Ws.Confirm) { 'Closed' } else { 'Would close' }) the warranty renewal card for $($cname): nothing is out of warranty.")
                }
            }
            else {
                $line = { param($w) "<li><strong>$(Enc $(if ($w.name) { $w.name } else { $w.serial }))</strong>$(if ($w.serial -and $w.name) { " ($(Enc $w.serial))" }): warranty $(if ($w.ends -lt $Today) { 'ended' } else { 'ends' }) $($w.ends.ToString('d MMM yyyy', $Ci))</li>" }
                $sb = New-Object System.Text.StringBuilder
                $n = $expired.Count
                if ($n) { $null = $sb.Append("<p>$(if ($n -eq 1) { 'One computer at this company is' } else { "$n computers at this company are" }) out of warranty.</p>") }
                $null = $sb.Append('<h4>What we recommend</h4><p>Renew or extend the manufacturer warranty so hardware repairs stay covered. If a computer is due for replacement instead, we will include it in a hardware refresh quote.</p>')
                if ($n) { $null = $sb.Append('<h4>Warranty ended</h4><ul>'); foreach ($w in $expired) { $null = $sb.Append((& $line $w)) }; $null = $sb.Append('</ul>') }
                if ($expiring.Count) { $null = $sb.Append("<h4>Warranty ending in the next $($Ws.ExpiringDays) days</h4><ul>"); foreach ($w in $expiring) { $null = $sb.Append((& $line $w)) }; $null = $sb.Append('</ul>') }
                if ($co.replaceSkipped) { $null = $sb.Append("<p>$(if ($co.replaceSkipped -eq 1) { 'One more computer is' } else { "$($co.replaceSkipped) more computers are" }) out of warranty and already on the Endpoint Hardware Refresh - Replace card.</p>") }
                $summary = if ($n) { "$(if ($n -eq 1) { 'One computer is' } else { "$n computers are" }) out of warranty$(if ($expiring.Count) { " and $($expiring.Count) more end soon" })." } else { "$(if ($expiring.Count -eq 1) { 'One warranty ends' } else { "$($expiring.Count) warranties end" }) in the next $($Ws.ExpiringDays) days." }
                $fields = @{ body = $sb.ToString(); summary = $summary; category = $Ws.Category; productCategoryId = $Ws.CategoryId
                    notes = "Internal: company $cid. Warranty dates checked $($TodayText): $($co.matched) computers matched, $n ended, $($expiring.Count) ending soon, $($co.replaceSkipped) left to the Replace card." }
                $reopen = ($null -ne $card -and (Test-Completed $card))
                if ($null -eq $card) { $fields.priority = 0 }
                if ($reopen) { $fields.status = 0 }
                $r = Set-CrPlannerCard -CompanyId $cid -Subject $subject -Fields $fields -Key $marker -Existing $cards -Preview:(-not $Ws.Confirm)
                if ($null -eq $card) { $Out.counts.cardsCreated++; $co.card = "$($verb)created" } elseif ($reopen) { $Out.counts.cardsReopened++; $co.card = "$($verb)reopened (card $($r.productId))" } else { $Out.counts.cardsUpdated++; $co.card = "$($verb)updated (card $($r.productId))" }
                if ($r.optionalFieldsDropped) { Add-Warning "$($cname): this portal didn't take the card's internal notes, so the card was written without them." }
                $null = $Out.actions.Add("$(if ($Ws.Confirm) { 'Wrote' } else { 'Would write' }) the warranty renewal card for $($cname): $summary")
            }
        }
        $null = $Out.details.Add("$cname ($cid): $($co.matched) of $($eps.Count) computers matched, $($co.updated) warranty dates $(if ($Ws.Confirm) { 'updated' } else { 'to update' }), $($co.filled) purchase dates $(if ($Ws.Confirm) { 'filled' } else { 'to fill' }), $($co.noSerial) without a serial, $($co.notInCr) ScalePad devices not in CloudRadial$(if ($Ws.Card) { "; $($co.expired) out of warranty$(if ($co.card) { ", card $($co.card)" })" }).")
    }
    catch { $Out.counts.errors++; $null = $Out.details.Add("$cname ($cid): failed - $($_.Exception.Message)"); Add-Warning "$cname ($cid) failed: $($_.Exception.Message)" }
}

$c = $Out.counts
$what = "$($c.companies) compan$(if ($c.companies -eq 1) { 'y' } else { 'ies' }): $($c.matched) computers matched, $($c.warrantyUpdated) warranty dates $(if ($Ws.Confirm) { 'updated' } else { 'to update' }), $($c.purchaseDateFilled) purchase dates $(if ($Ws.Confirm) { 'filled' } else { 'to fill' })$(if ($Ws.Card) { ", $($c.outOfWarranty) computers out of warranty" })$(if ($c.errors) { ", $($c.errors) failed" })."
$msg = if ($Ws.Confirm) { "Warranty sync for $what" } else { "Preview, nothing was changed. Warranty sync for $what Run again with {""confirm"": true} to make the changes." }
if ($unmatchedSp) { $msg += " $unmatchedSp ScalePad clients have no CloudRadial company with the same name." }
Send-Result $(if ($c.errors -and $c.errors -ge $c.companies) { 'failed' } elseif ($c.errors) { 'completed_with_errors' } else { 'ok' }) $msg
if ($c.errors -and $c.errors -ge $c.companies) { throw $msg }
