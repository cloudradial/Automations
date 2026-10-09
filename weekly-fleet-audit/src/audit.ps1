# =====================================================================
#  Weekly Fleet Audit - audit step (no AI)
#  Grades every managed computer with the Endpoint LifeCycle Manager rules
#  (age, warranty, OS support, RAM, server / VM) and checks each company for
#  an account manager. Read-only: nothing in CloudRadial is changed.
#  The rules are copied in from endpoint-lifecycle-manager/src/elm.ps1 at
#  build time (build-audit.js), so this report and the Planner cards agree.
#  Secrets (runner Key Vault): CloudRadial-BaseUrl, CloudRadial-PublicKey,
#  CloudRadial-PrivateKey.
# =====================================================================
$ErrorActionPreference = 'Stop'
function Get-Prop { param($o, $n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }

# ---- secrets ----
function Get-Secret { param([string]$Name) Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue }
$BaseUrl = Get-Secret 'CloudRadial-BaseUrl'; $PublicKey = Get-Secret 'CloudRadial-PublicKey'; $PrivateKey = Get-Secret 'CloudRadial-PrivateKey'
$missing = @(@{ n = 'CloudRadial-BaseUrl'; v = $BaseUrl }, @{ n = 'CloudRadial-PublicKey'; v = $PublicKey }, @{ n = 'CloudRadial-PrivateKey'; v = $PrivateKey } | Where-Object { [string]::IsNullOrWhiteSpace($_.v) } | ForEach-Object { $_.n })
if ($missing.Count) { $m = "Please add these secrets to your runner Key Vault and run again: $($missing -join ', ')"; Set-NodeOutput @{ status = 'error'; message = $m }; throw $m }
$BaseUrl = $BaseUrl.TrimEnd('/')
$headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${PublicKey}:${PrivateKey}")); Accept = 'application/json' }

$ci = [System.Globalization.CultureInfo]::InvariantCulture
$runDate = (Get-Date).ToUniversalTime()
$Categories = @('Replace', 'Plan replacement', 'Upgrade in place', 'Retain', 'Needs data', 'Human review', 'Virtual machines')
$TierRank = @{ Critical = 3; High = 2; Medium = 1; Low = 0 }
$DetailLimit = 3   # most urgent computers listed per company; the full list is on the Planner cards

#@@ELM_SHARED@@

# ---- 1. companies and account managers ----
$companies = @(Get-CrAll '/v2/odata/company')
$names = [ordered]@{}; $am = @{}; $amCheck = 'unavailable'
foreach ($co in $companies) { $names[[string](Get-Prop $co 'companyId')] = [string](Get-Prop $co 'name') }
if ($companies.Count -and $companies[0].PSObject.Properties['accountManager']) {
    $amCheck = 'ok'; foreach ($co in $companies) { $am[[string](Get-Prop $co 'companyId')] = ([string](Get-Prop $co 'accountManager')).Trim() }
}
else {
    # The OData list leaves accountManager out; the single-company read may include it.
    foreach ($id in @($names.Keys)) {
        $r = $null; try { $r = Invoke-CrApi -Path "/v2/company/$id" } catch { continue }
        $c = Get-Prop $r 'data'; if ($null -eq $c) { $c = $r }
        if ($null -eq $c -or $c -is [string] -or -not $c.PSObject.Properties['accountManager']) { if ($amCheck -ne 'ok') { break }; continue }
        $amCheck = 'ok'; $am[$id] = ([string](Get-Prop $c 'accountManager')).Trim()
    }
}

# ---- 2. grade every computer ----
$rows = [ordered]@{}
function Get-Row { param([string]$id)
    if (-not $rows.Contains($id)) {
        $cats = [ordered]@{}; foreach ($k in $Categories) { $cats[$k] = 0 }
        $amVal = $null; if ($amCheck -eq 'ok') { $amVal = $(if ($am.ContainsKey($id)) { $am[$id] } else { '' }) }
        $rows[$id] = [ordered]@{ companyId = $id; name = $(if ($names.Contains($id) -and $names[$id]) { $names[$id] } else { "Company $id" }); computers = 0; otherDevices = 0; flagged = 0
            critical = 0; high = 0; warrantyExpired = 0; warrantyExpiring = 0; warrantyUnknown = 0; accountManager = $amVal; categories = $cats; flaggedItems = (New-Object System.Collections.ArrayList) }
    }
    return $rows[$id]
}
foreach ($id in @($names.Keys)) { $null = Get-Row $id }   # every company gets a row, even with no computers

$endpoints = @(Get-CrAll '/v2/odata/endpoint')
$orphaned = 0
foreach ($ep in $endpoints) {
    $cid = [string](Get-Prop $ep 'companyId')
    # The endpoint list still returns endpoints of deleted companies (no deleted flag in the API).
    if ($names.Count -and -not $names.Contains($cid)) { $orphaned++; continue }
    $row = Get-Row $cid
    # Every key present: the runner runs in strict mode, where reading a missing key throws.
    $found = Get-Assessment $ep
    $a = @{ excluded = $false; flagged = $false; category = $null; tier = $null; line = $null }
    foreach ($k in @($found.Keys)) { $a[$k] = $found[$k] }
    if ($a.excluded) { $row.otherDevices++; continue }
    $row.computers++
    if (-not [bool](Get-Prop $ep 'isVirtual')) {
        switch ((Get-Warranty $ep).status) { 'expired' { $row.warrantyExpired++ } 'expiring' { $row.warrantyExpiring++ } 'unknown' { $row.warrantyUnknown++ } }
    }
    if (-not $a.flagged) { continue }
    $row.flagged++
    $row.categories[$a.category] = 1 + [int]$row.categories[$a.category]
    if ($a.tier -eq 'Critical') { $row.critical++ } elseif ($a.tier -eq 'High') { $row.high++ }
    $null = $row.flaggedItems.Add([ordered]@{ tier = $a.tier; category = $a.category; line = $a.line })
}

# ---- 3. sort and summarise ----
$list = @($rows.Values | Sort-Object -Property @{ Expression = { $_.critical }; Descending = $true }, @{ Expression = { $_.categories['Replace'] }; Descending = $true }, @{ Expression = { $_.flagged }; Descending = $true }, @{ Expression = { $_.name } })
$out = New-Object System.Collections.ArrayList
foreach ($r in $list) {
    $top = @($r.flaggedItems | Sort-Object -Property @{ Expression = { $TierRank[$_.tier] }; Descending = $true } | Where-Object { $TierRank[$_.tier] -ge 2 } | Select-Object -First $DetailLimit)
    $o = [ordered]@{}; foreach ($k in @($r.Keys)) { if ($k -ne 'flaggedItems') { $o[$k] = $r[$k] } }
    $o.urgent = $top; $o.moreFlagged = $r.flagged - $top.Count
    $null = $out.Add($o)
}
$totals = [ordered]@{ companies = $out.Count; computers = 0; flagged = 0; critical = 0; high = 0; warrantyExpired = 0; warrantyExpiring = 0; warrantyUnknown = 0; noAccountManager = 0; orphanedEndpoints = $orphaned }
$catTotals = [ordered]@{}; foreach ($k in $Categories) { $catTotals[$k] = 0 }
foreach ($r in $out) {
    foreach ($k in @('computers', 'flagged', 'critical', 'high', 'warrantyExpired', 'warrantyExpiring', 'warrantyUnknown')) { $totals[$k] += $r[$k] }
    foreach ($k in $Categories) { $catTotals[$k] += $r.categories[$k] }
    if ($amCheck -eq 'ok' -and -not $r.accountManager) { $totals.noAccountManager++ }
}
$totals.categories = $catTotals

$msg = "Audited $($totals.computers) computers across $($totals.companies) companies: $($totals.critical) critical, $($catTotals['Replace']) to replace, $($totals.warrantyExpired) with expired warranty, $($totals.warrantyUnknown) with no warranty date."
$msg += $(if ($amCheck -eq 'ok') { " $($totals.noAccountManager) $(if ($totals.noAccountManager -eq 1) { 'company has' } else { 'companies have' }) no account manager." } else { ' Account managers could not be checked.' })
Set-NodeOutput ([ordered]@{
    status              = 'ok'
    auditDate           = $runDate.ToString('yyyy-MM-dd', $ci)
    accountManagerCheck = $amCheck
    totals              = $totals
    companies           = @($out)
    message             = $msg
})
