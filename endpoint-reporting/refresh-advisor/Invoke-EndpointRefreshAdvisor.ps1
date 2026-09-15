<#
.SYNOPSIS
Evaluate CloudRadial-managed endpoints against a hardware-lifecycle policy and create or update
per-category "refresh plan" Planner cards, one card per (company, recommendation category).

.DESCRIPTION
Turns raw endpoint inventory into an actionable, client-ready hardware refresh plan without
generating a card per device. On each run it:

  1. Pulls managed endpoints from the CloudRadial v2 OData API (scoped to -CompanyId, or every
     company with -AllCompanies), using NATIVE endpoint fields as the source of truth.
  2. Evaluates each device with a deterministic, first-match-wins policy (see NOTES), routing
     servers to Human review, virtual machines to a VM track, and physical computers to an
     age/OS/warranty assessment.
  3. Groups the devices that warrant attention by company and by recommendation category, and
     assigns each a triage priority (Critical / High / Medium / Low).
  4. Creates or updates ONE Planner card (a CloudRadial "product") per (company, category),
     e.g. "Endpoint Hardware Refresh - Replace", with the devices written in plain language
     grouped by priority tier.

Cards are reconciled by a deterministic subject and a body marker, so re-running updates the same
cards in place instead of creating duplicates.

Data source note: this uses native endpoint fields (manufacturedDate -> age, expirationDate ->
warranty, os / isServer / isVirtual / windows11Readiness / isssd / memory), not endpoint custom
properties. Missing fields degrade gracefully to "unknown"; unknown values never force a "fail".

Because it writes to your portal it supports -WhatIf. Run with -WhatIf first.

.PARAMETER PublicKey
CloudRadial API public key (Settings > API). Used as the HTTP Basic username.

.PARAMETER PrivateKey
CloudRadial API private key. Used as the HTTP Basic password.

.PARAMETER BaseUrl
API base URL. Defaults to https://api.us.cloudradial.com. Use https://api.eu.cloudradial.com for EU.

.PARAMETER CompanyId
One or more companyIds to process. Defaults to @(1) (the main company). Ignored with -AllCompanies.

.PARAMETER AllCompanies
Process every company in the portal instead of the -CompanyId list.

.PARAMETER SubjectPrefix
Card subject prefix; the category is appended (e.g. "Endpoint Hardware Refresh - Replace"). This is
the reconcile key, so keep it stable across runs. Defaults to "Endpoint Hardware Refresh - ".

.PARAMETER Category
Planner category name for the cards. Defaults to "Efficiency".

.PARAMETER ProductCategoryId
Planner product category id. Defaults to 7 (Efficiency).

.PARAMETER ReplaceAgeYears
Age (years) at or above which a physical workstation is recommended for Replace. Default 5.

.PARAMETER PlanAgeYears
Age (years) at or above which a physical workstation is recommended for Plan replacement. Default 3.

.EXAMPLE
PS> .\Invoke-EndpointRefreshAdvisor.ps1 -PublicKey abc -PrivateKey xyz -WhatIf
Dry run against the main company: shows the cards it would create/update, writes nothing.

.EXAMPLE
PS> .\Invoke-EndpointRefreshAdvisor.ps1 -PublicKey abc -PrivateKey xyz -CompanyId 1,4,7

.EXAMPLE
PS> .\Invoke-EndpointRefreshAdvisor.ps1 -PublicKey abc -PrivateKey xyz -AllCompanies -Verbose

.NOTES
Decision policy (first match wins):
  - isServer                                             -> Human review
  - isVirtual (not server): OS unsupported               -> Virtual machines (upgrade guest OS);
      else skip unless a real spec driver is present
  - age >= ReplaceAgeYears, or OS unsupported (and not
      Windows 11-ready), or RAM < 4 GB                   -> Replace
  - OS unsupported and Windows 11-ready                  -> Upgrade in place
  - age PlanAgeYears to < ReplaceAgeYears                -> Plan replacement
  - age < PlanAgeYears                                   -> Retain (carded only if warranty
      expired/expiring or RAM < 8 GB)
  - no age + unknown warranty + unknown OS               -> Needs data
OS support: Windows 11 supported; Windows 10/8/7/XP/Vista unsupported (Win10 EOL 2025-10-14);
macOS 14+ supported, 13 and older unsupported, no version = unknown.
Priority: Critical = age >= 7 or OS past hard EOL (Win10 now / macOS <= 12) or RAM < 4;
High = age 5 to < 7, warranty expired, or OS unsupported; Medium = age 4.5 to < 5 or warranty
expiring <= 90 days; Low otherwise.
Native priority integer codes: Low = -1, Medium = 0, High = 1 (there is no Critical code, so
Critical caps to High and is labelled in the card body).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$PublicKey,
    [Parameter(Mandatory)][string]$PrivateKey,
    [string]$BaseUrl = 'https://api.us.cloudradial.com',
    [int[]]$CompanyId = @(1),
    [switch]$AllCompanies,
    [string]$SubjectPrefix = 'Endpoint Hardware Refresh - ',
    [string]$Category = 'Efficiency',
    [int]$ProductCategoryId = 7,
    [double]$ReplaceAgeYears = 5,
    [double]$PlanAgeYears = 3
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ci = [System.Globalization.CultureInfo]::InvariantCulture

$BaseUrl   = $BaseUrl.TrimEnd('/')
$authBytes = [Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $PublicKey, $PrivateKey))
$headers   = @{ Authorization = 'Basic ' + [Convert]::ToBase64String($authBytes); Accept = 'application/json' }
$runDate   = (Get-Date).ToUniversalTime()
$publishDate = $runDate.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

$PriorityInt = @{ 'Critical' = 1; 'High' = 1; 'Medium' = 0; 'Low' = -1 }
$TierRank    = @{ 'Critical' = 3; 'High' = 2; 'Medium' = 1; 'Low' = 0 }
$TierOrder   = @('Critical','High','Medium','Low')

function Invoke-CrApi {
    param([Parameter(Mandatory)][string]$Path, [string]$Method='GET', [object]$Body, [string]$ContentType='application/json')
    $url = if ($Path -match '^https?://') { $Path } else { "$BaseUrl$Path" }
    Write-Verbose "$Method $url"
    for ($attempt=1; $attempt -le 6; $attempt++) {
        try {
            $callArgs = @{ Uri=$url; Method=$Method; Headers=$headers; ContentType=$ContentType }
            if ($null -ne $Body) { $callArgs.Body = ($Body | ConvertTo-Json -Depth 12) }
            return Invoke-RestMethod @callArgs
        } catch {
            $code = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
            if (($code -eq 429 -or $code -ge 500) -and $attempt -lt 6) { Start-Sleep -Seconds ([Math]::Min(30,[Math]::Pow(2,$attempt))); continue }
            $detail = $null
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }
            throw ("CloudRadial API $Method $url failed (HTTP $code): $detail")
        }
    }
}

function Get-CrCollection {
    param([Parameter(Mandatory)][string]$Path)
    $rows = [System.Collections.Generic.List[object]]::new(); $skip=0; $page=100
    for ($p=0; $p -lt 1000; $p++) {
        $sep = if ($Path -match '\?') { '&' } else { '?' }
        $resp = Invoke-CrApi -Path ("${Path}${sep}`$top=$page&`$skip=$skip")
        if ($null -eq $resp) { break }
        $batch = @()
        $vp = $resp.PSObject.Properties['value']
        if ($vp -and $null -ne $vp.Value) { $batch = @($vp.Value) } elseif ($resp -is [System.Array]) { $batch = @($resp) }
        foreach ($r in $batch) { [void]$rows.Add($r) }
        if (@($batch).Count -lt $page) { break }
        $skip += $page
    }
    return $rows.ToArray()
}

function Get-Field { param($Obj,[string]$Name) if ($null -eq $Obj) { return $null }; $p=$Obj.PSObject.Properties[$Name]; if ($p) { return $p.Value }; return $null }
function HtmlEnc { param($t) $s=[string]$t; if ([string]::IsNullOrEmpty($s)) { return '' }; return ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;') }
function FriendlyDate { param([datetime]$d) return $d.ToString('d MMM yyyy',$ci) }
function Parse-Date { param($v) $d=[datetime]::MinValue; if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v) -and [datetime]::TryParse([string]$v,[ref]$d)) { return $d }; return $null }

function Get-AgeYears {
    param($Ep)
    foreach ($f in @('manufacturedDate','biosDate','cpuDate')) {
        $d = Parse-Date (Get-Field $Ep $f)
        if ($null -ne $d) { return [pscustomobject]@{ Years=[math]::Round(($runDate-$d).TotalDays/365.25,2); Estimated=($f -ne 'manufacturedDate') } }
    }
    return $null
}
function Get-Warranty {
    param($Ep) $d=Parse-Date (Get-Field $Ep 'expirationDate')
    if ($null -eq $d) { return [pscustomobject]@{Status='unknown';Date=$null} }
    if ($d -lt $runDate) { return [pscustomobject]@{Status='expired';Date=$d} }
    if ($d -le $runDate.AddDays(90)) { return [pscustomobject]@{Status='expiring';Date=$d} }
    return [pscustomobject]@{Status='active';Date=$d}
}
function Get-OsType { param([string]$os) if ($os -match '(?i)windows') { return 'windows' }; if ($os -match '(?i)mac\s?os|os x') { return 'macos' }; return 'noncomputer' }
function Get-MacMajor { param([string]$os) if ($os -match '(?i)mac\s?os[^\d]*(\d+)') { return [int]$Matches[1] }; return $null }
function Get-OsSupport {
    param([string]$os,[string]$type)
    if ($type -eq 'windows') {
        if ($os -match '(?i)windows\s*11') { return 'supported' }
        if ($os -match '(?i)windows\s*(10|8|7|xp|vista)') { return 'unsupported' }
        return 'unknown'
    }
    if ($type -eq 'macos') {
        $maj = Get-MacMajor $os
        if ($null -eq $maj) { return 'unknown' }
        if ($maj -ge 14) { return 'supported' }
        return 'unsupported'
    }
    return 'unknown'
}
function Get-RamGb { param($Ep) $m=Get-Field $Ep 'memory'; if ($null -eq $m) { return $null }; $b=0.0; if ([double]::TryParse([string]$m,[System.Globalization.NumberStyles]::Float,$ci,[ref]$b) -and $b -gt 0) { return [math]::Round($b/1073741824,1) }; return $null }
function Get-Win11Ready { param($Ep) $r=[string](Get-Field $Ep 'windows11Readiness'); return ($r -match '(?i)installed|capable') }
function Get-Identity {
    param($Ep)
    $mk = ([string](Get-Field $Ep 'manufacturer')).Trim(); $md = ([string](Get-Field $Ep 'model')).Trim(); $sn = ([string](Get-Field $Ep 'serialNumber')).Trim()
    $id = (@($mk,$md) | Where-Object { $_ }) -join ' '
    if ($sn) { $id = if ($id) { "$id, serial $sn" } else { "serial $sn" } }
    return $id
}
function Get-Tier {
    param([string]$mode,$age,[string]$warranty,[string]$osSupport,[string]$osType,$macMajor,$ramGb)
    if ($mode -eq 'vm') {
        if ($osSupport -eq 'unsupported') { return 'High' }
        if ($null -ne $ramGb -and $ramGb -lt 4) { return 'High' }
        return 'Low'
    }
    $hardEol = ($osType -eq 'windows' -and $osSupport -eq 'unsupported') -or ($osType -eq 'macos' -and $null -ne $macMajor -and $macMajor -le 12)
    if (($null -ne $age -and $age -ge 7) -or $hardEol -or ($null -ne $ramGb -and $ramGb -lt 4)) { return 'Critical' }
    if (($null -ne $age -and $age -ge $ReplaceAgeYears) -or $warranty -eq 'expired' -or $osSupport -eq 'unsupported') { return 'High' }
    if (($null -ne $age -and $age -ge 4.5) -or $warranty -eq 'expiring') { return 'Medium' }
    return 'Low'
}

function Get-Assessment {
    param($Ep)
    $name = [string](Get-Field $Ep 'name'); $os = [string](Get-Field $Ep 'os')
    $isServer = [bool](Get-Field $Ep 'isServer'); $isVirtual = [bool](Get-Field $Ep 'isVirtual')
    $osType = Get-OsType $os
    if ($osType -eq 'noncomputer') { return [pscustomobject]@{ Flagged=$false; Excluded=$true } }

    $ageObj = Get-AgeYears $Ep; $age = if ($ageObj) { $ageObj.Years } else { $null }; $ageEst = if ($ageObj) { $ageObj.Estimated } else { $false }
    $war = Get-Warranty $Ep; $osSupport = Get-OsSupport $os $osType; $macMajor = if ($osType -eq 'macos') { Get-MacMajor $os } else { $null }
    $ramGb = Get-RamGb $Ep; $win11Ready = Get-Win11Ready $Ep
    $ident = Get-Identity $Ep

    $ageClause = if ($null -eq $age) { 'has no age on file' } elseif ($ageEst) { "is about $age years old (estimated)" } else { "is about $age years old" }
    $warClause = switch ($war.Status) {
        'expired'  { "and its warranty expired on $(FriendlyDate $war.Date)" }
        'expiring' { "and its warranty is expiring on $(FriendlyDate $war.Date)" }
        'active'   { "with an active warranty through $(FriendlyDate $war.Date)" }
        default    { 'with no warranty date on file' }
    }
    $osClause = if ([string]::IsNullOrWhiteSpace($os)) { '' } else {
        $sup = switch ($osSupport) { 'supported' {', which is supported'} 'unsupported' {', which is no longer supported'} default {''} }
        " It is running $os$sup."
    }
    $identText = if ($ident) { " ($(HtmlEnc $ident))" } else { '' }
    $lead = "<strong>$(HtmlEnc $name)</strong>$identText"

    if ($isServer) {
        $tier = Get-Tier 'std' $age $war.Status $osSupport $osType $macMajor $ramGb
        $line = "$lead $ageClause $warClause.$osClause A technician should review this server and decide the right next step."
        return [pscustomobject]@{ Flagged=$true; Excluded=$false; Category='Human review'; Tier=$tier; Line=$line }
    }
    if ($isVirtual) {
        $flag=$false; $action=$null
        if ($osSupport -eq 'unsupported') { $flag=$true; $action='upgrade or rebuild the guest OS to a supported version (no hardware refresh needed)' }
        elseif ($null -ne $ramGb -and $ramGb -lt 4) { $flag=$true; $action='increase its assigned memory' }
        elseif ($null -ne $ramGb -and $ramGb -lt 8) { $flag=$true; $action='review and tune its assigned resources' }
        if (-not $flag) { return [pscustomobject]@{ Flagged=$false; Excluded=$false } }
        $tier = Get-Tier 'vm' $age $war.Status $osSupport $osType $macMajor $ramGb
        $osTxt = if ([string]::IsNullOrWhiteSpace($os)) { 'an unknown OS' } else { $os }
        $line = "$lead is a virtual machine running $osTxt. Recommended action: $action."
        return [pscustomobject]@{ Flagged=$true; Excluded=$false; Category='Virtual machines'; Tier=$tier; Line=$line }
    }

    $rec = $null
    if (($null -ne $age -and $age -ge $ReplaceAgeYears) -or ($osSupport -eq 'unsupported' -and -not $win11Ready) -or ($null -ne $ramGb -and $ramGb -lt 4)) { $rec='Replace' }
    elseif ($osSupport -eq 'unsupported' -and $win11Ready) { $rec='Upgrade in place' }
    elseif ($null -ne $age -and $age -ge $PlanAgeYears -and $age -lt $ReplaceAgeYears) { $rec='Plan replacement' }
    elseif ($null -ne $age -and $age -lt $PlanAgeYears) { $rec='Retain' }
    elseif ($null -eq $age -and $war.Status -eq 'unknown' -and $osSupport -eq 'unknown') { $rec='Needs data' }
    else { $rec='Retain' }

    $flag = switch ($rec) {
        'Replace' { $true } 'Plan replacement' { $true } 'Upgrade in place' { $true } 'Needs data' { $true }
        'Retain' { ($war.Status -in @('expired','expiring')) -or ($null -ne $ramGb -and $ramGb -lt 8) }
        default { $false }
    }
    if (-not $flag) { return [pscustomobject]@{ Flagged=$false; Excluded=$false } }

    $tier = Get-Tier 'std' $age $war.Status $osSupport $osType $macMajor $ramGb
    $action = switch ($rec) {
        'Replace'          { 'replace this device' }
        'Upgrade in place' { 'upgrade it to Windows 11 in place; the hardware is capable' }
        'Plan replacement' { 'plan its replacement this cycle, and extend the warranty or upgrade components as a bridge' }
        'Retain'           { 'extend the warranty or apply a targeted upgrade' }
        'Needs data'       { 'collect its age, warranty, and OS details so it can be evaluated next time' }
    }
    $line = "$lead $ageClause $warClause.$osClause Recommended action: $action."
    return [pscustomobject]@{ Flagged=$true; Excluded=$false; Category=$rec; Tier=$tier; Line=$line }
}

# ---- Phase 1: pull endpoints and assess ----
if ($AllCompanies) {
    $endpoints = @(Get-CrCollection '/v2/odata/Endpoint')
} else {
    $clause = @($CompanyId | ForEach-Object { "companyId eq $([int]$_)" }) -join ' or '
    $endpoints = @(Get-CrCollection ("/v2/odata/Endpoint?`$filter=$clause"))
}

$counts = [ordered]@{ evaluated=0; flaggedEndpoints=0; excludedNonComputer=0; skippedHealthy=0; companiesProcessed=0; cardsCreated=0; cardsUpdated=0; errors=0 }
$buckets = @{}
foreach ($ep in @($endpoints)) {
    $cid = [string](Get-Field $ep 'companyId')
    if (-not $AllCompanies -and ($CompanyId -notcontains [int]$cid)) { continue }
    $a = Get-Assessment $ep
    if ($a.Excluded) { $counts.excludedNonComputer++; continue }
    $counts.evaluated++
    if (-not $a.Flagged) { $counts.skippedHealthy++; continue }
    $counts.flaggedEndpoints++
    if (-not $buckets.ContainsKey($cid)) { $buckets[$cid] = @{} }
    if (-not $buckets[$cid].ContainsKey($a.Category)) { $buckets[$cid][$a.Category] = [System.Collections.Generic.List[object]]::new() }
    [void]$buckets[$cid][$a.Category].Add([pscustomobject]@{ Tier=$a.Tier; Line=$a.Line })
}

# ---- Phase 2: upsert one card per (company, category) ----
$results = [System.Collections.Generic.List[object]]::new()
$productsByCompany = @{}
foreach ($cid in @($buckets.Keys)) {
    $counts.companiesProcessed++
    if (-not $productsByCompany.ContainsKey($cid)) {
        $productsByCompany[$cid] = @(Get-CrCollection ("/v2/odata/Product?`$filter=companyId eq $([int]$cid)"))
    }
    $existing = @($productsByCompany[$cid])
    foreach ($category in @($buckets[$cid].Keys)) {
        $devices = @($buckets[$cid][$category].ToArray())
        try {
            $subject = "$SubjectPrefix$category"
            $marker  = "Refresh Plan Card: company $cid / $category"
            $topTier = ($devices | Sort-Object { $TierRank[$_.Tier] } -Descending | Select-Object -First 1).Tier
            $priorityInt = $PriorityInt[$topTier]

            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.Append("<p>This card lists $($devices.Count) device(s) in the '$category' category, most urgent first.</p>")
            foreach ($t in $TierOrder) {
                $inTier = @($devices | Where-Object { $_.Tier -eq $t })
                if (@($inTier).Count -eq 0) { continue }
                [void]$sb.Append("<p><strong>$t</strong></p><ul>")
                foreach ($d in $inTier) { [void]$sb.Append("<li>$($d.Line)</li>") }
                [void]$sb.Append("</ul>")
            }
            [void]$sb.Append("<p><em>$marker</em></p>")
            $body = $sb.ToString()
            $summary = "$($devices.Count) device(s) in $category (top priority $topTier)."

            $plan = @($existing | Where-Object {
                $s=[string](Get-Field $_ 'subject'); $b=[string](Get-Field $_ 'body')
                ($s.Trim() -eq $subject) -or ($b -and $b.Contains($marker))
            } | Select-Object -First 1)

            if (@($plan).Count -gt 0) {
                $cardId = Get-Field $plan[0] 'productId'
                if ($PSCmdlet.ShouldProcess("company $cid / $category (productId $cardId)", 'Update refresh card')) {
                    $patch = @(
                        @{ op='replace'; path='/subject'; value=$subject },
                        @{ op='replace'; path='/body'; value=$body },
                        @{ op='replace'; path='/summary'; value=$summary },
                        @{ op='replace'; path='/category'; value=$Category },
                        @{ op='replace'; path='/productCategoryId'; value=$ProductCategoryId },
                        @{ op='replace'; path='/priority'; value=$priorityInt }
                    )
                    $null = Invoke-CrApi -Path ("/v2/product/$cardId") -Method 'PATCH' -Body $patch -ContentType 'application/json-patch+json'
                    $counts.cardsUpdated++
                }
                [void]$results.Add([pscustomobject]@{ CompanyId=$cid; Category=$category; Priority=$topTier; Action='updated'; ProductId=$cardId; DeviceCount=$devices.Count })
            } else {
                if ($PSCmdlet.ShouldProcess("company $cid / $category", 'Create refresh card')) {
                    $create = [ordered]@{
                        companyId=[int]$cid; productCategoryId=$ProductCategoryId; category=$Category; subject=$subject
                        datePublished=$publishDate; body=$body; summary=$summary
                        isRequired=$false; isShowPrice=$false; isClientVisible=$false; priority=$priorityInt
                    }
                    $new = Invoke-CrApi -Path '/v2/product' -Method 'POST' -Body $create
                    $newId = Get-Field $new 'productId'
                    $counts.cardsCreated++
                    [void]$results.Add([pscustomobject]@{ CompanyId=$cid; Category=$category; Priority=$topTier; Action='created'; ProductId=$newId; DeviceCount=$devices.Count })
                } else {
                    [void]$results.Add([pscustomobject]@{ CompanyId=$cid; Category=$category; Priority=$topTier; Action='would create'; ProductId=$null; DeviceCount=$devices.Count })
                }
            }
        } catch {
            $counts.errors++
            [void]$results.Add([pscustomobject]@{ CompanyId=$cid; Category=$category; Priority='n/a'; Action='error'; ProductId=$null; DeviceCount=@($devices).Count })
            Write-Warning "company $cid / $category failed: $($_.Exception.Message)"
        }
    }
}

# ---- Summary ----
$scope = if ($AllCompanies) { 'all companies' } else { "companyId [$($CompanyId -join ', ')]" }
$whatIfNote = if ($WhatIfPreference) { '  (WhatIf - nothing written)' } else { '' }
Write-Host ""
Write-Host "Endpoint Refresh Advisor" -ForegroundColor Cyan
Write-Host "Scope: $scope$whatIfNote"
Write-Host ("Evaluated {0} endpoints; flagged {1} across {2} companies; excluded {3}; skipped healthy {4}." -f `
    $counts.evaluated, $counts.flaggedEndpoints, $counts.companiesProcessed, $counts.excludedNonComputer, $counts.skippedHealthy)
Write-Host ("Cards created: {0}  updated: {1}  errors: {2}" -f $counts.cardsCreated, $counts.cardsUpdated, $counts.errors)
$results | Sort-Object CompanyId, Category | Format-Table -AutoSize | Out-Host

[pscustomobject]@{
    Scope = $scope
    Evaluated = $counts.evaluated
    Flagged = $counts.flaggedEndpoints
    ExcludedNonComputer = $counts.excludedNonComputer
    SkippedHealthy = $counts.skippedHealthy
    CompaniesProcessed = $counts.companiesProcessed
    CardsCreated = $counts.cardsCreated
    CardsUpdated = $counts.cardsUpdated
    Errors = $counts.errors
    Results = @($results.ToArray())
}
