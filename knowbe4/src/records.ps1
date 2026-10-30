# === NODE: Create or update CloudRadial records ===
# One KnowBe4 Incomplete Training record per user, kept up to date instead of added again on every run.
#   - Reads the company's existing records of this type once, and keys them by email (or user name when a
#     record has no email).
#   - Overdue user with a record: updates it when the courses changed, otherwise leaves it alone.
#   - Overdue user without a record: creates one.
#   - Record whose user is no longer overdue: set to 0 incomplete courses ("All assigned training complete"),
#     never deleted, so the history stays as evidence.
#   - Several records for one user (from runs before 1.2.0): the newest is kept up to date and the others are
#     reported as duplicates. Nothing is deleted.
# Each result says what happened (created, updated, unchanged, completed or error) and whether the user is
# newly overdue or owes more courses than last time (worse), which the ticket step uses.
# One bad record doesn't stop the run: it is reported with status error.
$ErrorActionPreference = 'Stop'
function Get-KbProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Stop-Kb { param([string]$Msg) Set-NodeOutput @{ status = 'error'; message = $Msg; items = @() }; throw $Msg }
# The stored traits as a dictionary with lower-case keys; the portal may normalize the key names.
function Get-KbTraits {
    param($a)
    $raw = Get-KbProp $a 'traitsJson'; $t = $null
    if ($raw -is [string] -and $raw.Trim()) { try { $t = $raw | ConvertFrom-Json } catch { $t = $null } } else { $t = Get-KbProp $a 'traits' }
    $d = @{}
    if ($t -is [System.Collections.IDictionary]) { foreach ($k in $t.Keys) { $d[([string]$k).ToLowerInvariant() -replace '[\s_]', '-'] = $t[$k] } }
    elseif ($null -ne $t) { foreach ($p in $t.PSObject.Properties) { $d[$p.Name.ToLowerInvariant() -replace '[\s_]', '-'] = $p.Value } }
    return $d
}
function Get-KbKey { param([string]$Email, [string]$Name) if ($Email.Trim()) { return 'e:' + $Email.Trim().ToLowerInvariant() }; if ($Name.Trim()) { return 'n:' + $Name.Trim().ToLowerInvariant() }; return '' }
function Get-KbCount { param($v) $n = 0; if ([int]::TryParse([string]$v, [ref]$n)) { return $n }; return 0 }
# Unverified live for this workflow: PATCH /v2/flexible-asset/{id} replacing traitsJson, with the IT Glue-compatible
# route as the fallback (the same pair as the ScalePad sync).
function Set-KbTraits {
    param([string]$Id, [hashtable]$Traits)
    $json = $Traits | ConvertTo-Json -Depth 5 -Compress
    try { $null = Invoke-CrApi -Path "/v2/flexible-asset/$Id" -Method PATCH -Body (ConvertTo-Json -InputObject @(@{ op = 'replace'; path = '/traitsJson'; value = $json }) -Depth 5) }
    catch { $null = Invoke-CrApi -Path "/compatibility/flexible_assets/$Id" -Method PATCH -Body @{ data = @{ type = 'flexible-assets'; id = $Id; attributes = @{ traits = $Traits } } } }
}

$users = @(Get-NodeInput -Name 'users' | Where-Object { $null -ne $_ })
$companyId = [string](Get-NodeInput -Name 'companyId')
$typeId = [string](Get-NodeInput -Name 'flexibleAssetTypeId')
if ($companyId -notmatch '^\d+$') { Stop-Kb "No CloudRadial company id reached this step ('$companyId')." }
if ($typeId -notmatch '^\d+$') { Stop-Kb "No flexible asset type id reached this step ('$typeId')." }
try { $null = Connect-Cr } catch { Stop-Kb $_.Exception.Message }
$today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')

# ---- Existing records, newest first per user ----
try { $existing = @(Get-CrAll "/v2/odata/flexibleasset?`$filter=$([uri]::EscapeDataString("companyId eq $companyId and flexibleAssetTypeId eq $typeId"))") }
catch { Stop-Kb "Couldn't read the existing KnowBe4 records, so nothing was written (to avoid duplicates): $($_.Exception.Message)" }
$byKey = @{}; $duplicates = @()
foreach ($a in @($existing | Sort-Object { Get-KbCount (Get-CrId $_ @('flexibleAssetId', 'id')) } -Descending)) {
    $t = Get-KbTraits $a
    $key = Get-KbKey ([string]$t['email']) ([string]$t['user'])
    if (-not $key) { continue }
    $rec = @{ id = [string](Get-CrId $a @('flexibleAssetId', 'id')); traits = $t }
    if ($byKey.ContainsKey($key)) { $duplicates += $rec.id } else { $byKey[$key] = $rec }
}

$items = New-Object System.Collections.ArrayList
$seen = @{}
foreach ($u in $users) {
    $name = [string](Get-KbProp $u 'userName'); $email = [string](Get-KbProp $u 'email')
    $count = Get-KbCount (Get-KbProp $u 'courseCount'); $list = [string](Get-KbProp $u 'coursesText')
    $key = Get-KbKey $email $name
    $row = [ordered]@{ status = 'success'; action = ''; worse = $false; assetId = $null; assetName = [string](Get-KbProp $u 'assetName'); userId = [string](Get-KbProp $u 'userId'); email = $email; courseCount = $count; previousCount = $null; companyId = [int]$companyId; flexibleAssetTypeId = [int]$typeId }
    $traits = @{ user = $name; email = $email; 'incomplete-courses' = $count; 'course-list' = $list; updated = $today }
    try {
        $old = if ($key -and $byKey.ContainsKey($key)) { $byKey[$key] } else { $null }
        if ($key) { $seen[$key] = $true }
        if ($old) {
            $was = Get-KbCount $old.traits['incomplete-courses']
            $row.assetId = $old.id; $row.previousCount = $was; $row.worse = ($count -gt $was)
            if ($was -eq $count -and [string]$old.traits['course-list'] -eq $list) { $row.action = 'unchanged' }
            else { Set-KbTraits $old.id $traits; $row.action = 'updated' }
        }
        else {
            $created = Invoke-CrApi -Path '/v2/flexible-asset' -Method POST -Body @{ companyId = [int]$companyId; flexibleAssetTypeId = [int]$typeId; traits = $traits }
            $row.assetId = Get-CrId $created @('flexibleAssetId', 'id'); $row.action = 'created'; $row.worse = $true
        }
    }
    catch { $row.status = 'error'; $row.message = $_.Exception.Message }
    $null = $items.Add([pscustomobject]$row)
}

# ---- Users who caught up: their record goes to 0, it isn't deleted ----
$completed = 0
foreach ($key in @($byKey.Keys)) {
    if ($seen.ContainsKey($key)) { continue }
    $old = $byKey[$key]
    if ((Get-KbCount $old.traits['incomplete-courses']) -eq 0) { continue }
    $t = @{ user = [string]$old.traits['user']; email = [string]$old.traits['email']; 'incomplete-courses' = 0; 'course-list' = 'All assigned training complete'; updated = $today }
    $row = [ordered]@{ status = 'success'; action = 'completed'; worse = $false; assetId = $old.id; assetName = $(if ($t.email) { $t.email } else { $t.user }); userId = ''; email = $t.email; courseCount = 0; previousCount = Get-KbCount $old.traits['incomplete-courses']; companyId = [int]$companyId; flexibleAssetTypeId = [int]$typeId }
    try { Set-KbTraits $old.id $t; $completed++ } catch { $row.status = 'error'; $row.message = $_.Exception.Message }
    $null = $items.Add([pscustomobject]$row)
}

$n = { param($a) @($items | Where-Object { $_.status -eq 'success' -and $_.action -eq $a }).Count }
$msg = "KnowBe4 records: $(& $n 'created') created, $(& $n 'updated') updated, $(& $n 'unchanged') unchanged, $completed now complete"
$errs = @($items | Where-Object { $_.status -ne 'success' }).Count
if ($errs) { $msg += ", $errs failed" }
if ($duplicates.Count) { $msg += ". $($duplicates.Count) older duplicate record(s) left as they are (ids $($duplicates -join ', '))" }
Set-NodeOutput @{ status = 'success'; message = $msg; items = @($items); duplicates = @($duplicates) }
