# === NODE: Summarize assets & open PSA ticket ===
# Tallies the records written for this run and opens ONE ticket for the company in whichever of the six PSAs the
# runner uses (ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro or Zendesk, through _shared/psa.ps1).
#   - Only when something got worse since the last run: a user who is newly overdue, or who owes more courses.
#     A run where nothing got worse opens no ticket, so a weekly schedule doesn't pile up duplicates.
#   - The ticket lists everyone still overdue and marks who is new or owes more.
#   - The PSA company: the CloudRadial company's name matched exactly in the PSA, then the PSA-CompanyId secret
#     as a catch-all (with a warning).
#   - The queue: PSA-ServiceQueue, or the older CW-ServiceBoard secret on ConnectWise.
#   - KnowBe4-AdminEmail (optional) is named in the ticket so the technician knows who to contact.
# A ticket problem never fails the run: the records are already saved, so it is reported as ticketWarning.
$ErrorActionPreference = 'Stop'
function Get-KbProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }

$results = @()
$resultsInput = Get-NodeInput -Name 'results'
if ($null -ne $resultsInput) { $results = @($resultsInput) }
$companyId = [string](Get-NodeInput -Name 'companyId')
$companyName = [string](Get-NodeInput -Name 'companyName')
if (-not $companyName) { $companyName = "Company $companyId" }

$createdAssets = @(foreach ($r in $results) {
    if ($null -eq $r -or [string](Get-KbProp $r 'status') -ne 'success' -or [string](Get-KbProp $r 'action') -eq 'completed') { continue }
    [pscustomobject]@{
        assetId = Get-KbProp $r 'assetId'; assetName = [string](Get-KbProp $r 'assetName'); userId = [string](Get-KbProp $r 'userId')
        email = [string](Get-KbProp $r 'email'); courseCount = Get-KbProp $r 'courseCount'; companyId = Get-KbProp $r 'companyId'
        flexibleAssetTypeId = Get-KbProp $r 'flexibleAssetTypeId'; action = [string](Get-KbProp $r 'action')
        worse = ((Get-KbProp $r 'worse') -eq $true); previousCount = Get-KbProp $r 'previousCount'
    }
})
$count = { param($a) @($results | Where-Object { $null -ne $_ -and [string](Get-KbProp $_ 'status') -eq 'success' -and [string](Get-KbProp $_ 'action') -eq $a }).Count }
$worse = @($createdAssets | Where-Object { $_.worse })
$failedCount = @($results | Where-Object { $null -ne $_ -and [string](Get-KbProp $_ 'status') -ne 'success' }).Count
$flexibleAssetTypeId = if ($createdAssets.Count -gt 0) { $createdAssets[0].flexibleAssetTypeId } else { $null }

$ticketId = $null; $psaName = ''; $psaCompanyId = ''; $warnings = @(); $ticketSkipped = $null
if ($createdAssets.Count -gt 0 -and -not $worse.Count) { $ticketSkipped = 'No ticket: nobody is newly overdue or owes more courses than last run.' }
if ($worse.Count -gt 0) {
    try {
        $null = Connect-Psa -Psa (Get-PsaType '')
        $psaName = Get-PsaName

        $hits = @(Find-PsaCompany -Name $companyName | Where-Object { $_.exact })
        if ($hits.Count -eq 1) { $psaCompanyId = [string]$hits[0].id }
        else {
            $fallback = ([string](Get-PsaSecret 'PSA-CompanyId')).Trim()
            if (-not $fallback) { throw "$psaName has $($hits.Count) companies named '$companyName'. Name the company the same in both, or set the PSA-CompanyId secret." }
            $psaCompanyId = $fallback
            $warnings += "Opened the ticket on the PSA-CompanyId company ($fallback), because $psaName has $($hits.Count) companies named '$companyName'."
        }

        $queue = ([string](Get-PsaSecret 'PSA-ServiceQueue')).Trim()
        if (-not $queue -and $PsaState.Conn.Psa -eq 'connectwise') { $queue = ([string](Get-PsaSecret 'CW-ServiceBoard')).Trim() }

        $lines = ($createdAssets | ForEach-Object {
            $who = if ($_.assetName) { $_.assetName } else { $_.email }
            $mail = if ($_.email -and $_.email -ne $who) { " <$($_.email)>" } else { '' }
            $tag = if ($_.action -eq 'created') { ' (new)' } elseif ($_.worse) { " (up from $($_.previousCount))" } else { '' }
            "- $who$mail - $($_.courseCount) incomplete course(s)$tag"
        }) -join "`n"
        $description = "These $companyName users are overdue on KnowBe4 security-awareness training. $($worse.Count) of them are newly overdue or owe more courses since the last check.`n$lines"
        $admin = ([string](Get-PsaSecret 'KnowBe4-AdminEmail')).Trim()
        if ($admin) { $description += "`n`nKnowBe4 admin for this company: $admin" }

        $t = New-PsaTicket -CompanyId $psaCompanyId -Summary "KnowBe4 security training overdue - $($createdAssets.Count) user(s)" -Description $description -Priority 'medium' -Queue $queue
        $ticketId = [string]$t.id
    }
    catch { $warnings += "PSA ticket not created: $($_.Exception.Message)" }
    foreach ($w in @($PsaState.Warnings)) { if ($w -and $warnings -notcontains $w) { $warnings += [string]$w } }
}

$message = "$($createdAssets.Count) KnowBe4 user(s) overdue (records: $(& $count 'created') created, $(& $count 'updated') updated, $(& $count 'unchanged') unchanged, $(& $count 'completed') now complete)"
if ($ticketId) { $message += "; opened $psaName ticket $ticketId" }
elseif ($ticketSkipped) { $message += "; $ticketSkipped" }
elseif (@($warnings | Where-Object { $_ -like 'PSA ticket not created*' }).Count) { $message += "; $(@($warnings | Where-Object { $_ -like 'PSA ticket not created*' })[0])" }
$ticketWarning = if ($warnings.Count) { $warnings -join ' ' } else { $null }

Set-NodeOutput @{
    status = 'success'; message = $message
    createdAssets = @($createdAssets); createdCount = (& $count 'created'); overdueCount = $createdAssets.Count; worseCount = $worse.Count; failedCount = $failedCount
    updatedCount = (& $count 'updated'); unchangedCount = (& $count 'unchanged'); completedCount = (& $count 'completed'); ticketSkipped = $ticketSkipped
    companyId = $companyId; companyName = $companyName; flexibleAssetTypeId = $flexibleAssetTypeId
    psa = $psaName; psaCompanyId = $psaCompanyId; ticketId = $ticketId; ticketNumber = $ticketId; ticketWarning = $ticketWarning
}
