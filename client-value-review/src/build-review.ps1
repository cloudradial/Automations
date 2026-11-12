$cwApiUrl = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'CW-ApiUrl' -AsPlainText -ErrorAction SilentlyContinue
$cwCompanyId = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'CW-CompanyID' -AsPlainText -ErrorAction SilentlyContinue
$cwPublicKey = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'CW-PublicKey' -AsPlainText -ErrorAction SilentlyContinue
$cwPrivateKey = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'CW-PrivateKey' -AsPlainText -ErrorAction SilentlyContinue
$cwClientId = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'CW-ClientId' -AsPlainText -ErrorAction SilentlyContinue

$missingSecrets = @()
if ([string]::IsNullOrWhiteSpace($cwApiUrl)) { $missingSecrets += 'CW-ApiUrl' }
if ([string]::IsNullOrWhiteSpace($cwCompanyId)) { $missingSecrets += 'CW-CompanyID' }
if ([string]::IsNullOrWhiteSpace($cwPublicKey)) { $missingSecrets += 'CW-PublicKey' }
if ([string]::IsNullOrWhiteSpace($cwPrivateKey)) { $missingSecrets += 'CW-PrivateKey' }
if ([string]::IsNullOrWhiteSpace($cwClientId)) { $missingSecrets += 'CW-ClientId' }
if ($missingSecrets.Count -gt 0) {
  $msg = "Please add the following secret(s) to your runner Key Vault and re-run this workflow: $($missingSecrets -join ', ')"
  Set-NodeOutput @{ status = 'error'; message = $msg }
  throw $msg
}

$nodeInput = Get-NodeInput
if ($null -eq $nodeInput) { $nodeInput = @{} }

# Everything comes from the trigger payload: the portal form sends reviewTimeframe plus the ticket's company;
# manual runs can still pass clientName, startDate and endDate.
$trig = Get-NodeInput -Name 'trigger'
if ($trig -is [string]) { try { $trig = $trig | ConvertFrom-Json } catch { $trig = $null } }
function Get-TrigVal { param([string[]]$Path) $o = $trig; foreach ($p in $Path) { if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { $o = $o[$p] } else { $prop = $o.PSObject.Properties[$p]; $o = if ($prop) { $prop.Value } else { $null } } }; if ($null -ne $o -and ([string]$o).StartsWith('@')) { return $null }; return $o }
$companyName = [string](Get-TrigVal @('clientName'))
$startDateInput = Get-TrigVal @('startDate')
$endDateInput = Get-TrigVal @('endDate')
$reviewTimeframe = [string](Get-TrigVal @('reviewTimeframe'))
$hourlyRateInput = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'ValueReview-HourlyRate' -AsPlainText -ErrorAction SilentlyContinue
$clientEmail = [string](Get-TrigVal @('clientEmail'))
$psaCompanyId = [string](Get-TrigVal @('psaCompanyId'))
# The client comes from the ticket's company when the portal form sends it (the Client dropdown is only a fallback for manual runs).
$ticketCompanyName = [string](Get-TrigVal @('company', 'name'))
$ticketPsaId = [string](Get-TrigVal @('company', 'psaId'))
if (-not [string]::IsNullOrWhiteSpace($ticketCompanyName) -and -not $ticketCompanyName.StartsWith('{{')) { $companyName = $ticketCompanyName.Trim() }
if ($ticketPsaId -match '^\d+$') { $psaCompanyId = $ticketPsaId }

if ([string]::IsNullOrWhiteSpace($companyName) -and [string]::IsNullOrWhiteSpace($psaCompanyId)) {
  $msg = 'companyName or psaCompanyId is required.'
  Set-NodeOutput @{ status = 'error'; message = $msg }
  throw $msg
}

$today = (Get-Date).Date
# Review Timeframe from the form (30, 60 or 90 days, however the option is worded): count back from today.
$timeframeDays = 0
if ($reviewTimeframe -match '(\d+)') { $timeframeDays = [int]$Matches[1] }
if ($timeframeDays -gt 0) { $endDateInput = $today.ToString('yyyy-MM-dd'); $startDateInput = $today.AddDays(-$timeframeDays).ToString('yyyy-MM-dd') }
if ([string]::IsNullOrWhiteSpace([string]$endDateInput)) {
  $endDate = $today
} else {
  $endDate = ([datetime]$endDateInput).Date
}
if ([string]::IsNullOrWhiteSpace([string]$startDateInput)) {
  $startDate = $endDate.AddMonths(-12)
} else {
  $startDate = ([datetime]$startDateInput).Date
}
if ($startDate -gt $endDate) {
  $msg = 'startDate must be on or before endDate.'
  Set-NodeOutput @{ status = 'error'; message = $msg }
  throw $msg
}

$hourlyRate = 150.0
$hourlyRateFromVault = $false
if (-not [string]::IsNullOrWhiteSpace([string]$hourlyRateInput)) {
  $parsedRate = 0.0
  if ([double]::TryParse([string]$hourlyRateInput, [ref]$parsedRate) -and $parsedRate -gt 0) {
    $hourlyRate = $parsedRate
    $hourlyRateFromVault = $true
  }
}

$periodStart = $startDate.Date
$periodEndExclusive = $endDate.Date.AddDays(1)
$periodLabelStart = $periodStart.ToString('yyyy-MM-dd')
$periodLabelEnd = $endDate.Date.ToString('yyyy-MM-dd')

function Format-Usd([double]$value) {
  '$' + ([math]::Round($value,0).ToString('N0'))
}

function Format-Hours([double]$value) {
  ([math]::Round($value,1).ToString('N1'))
}

function HtmlEncode([string]$text) {
  if ($null -eq $text) { return '' }
  [System.Net.WebUtility]::HtmlEncode($text)
}

function Escape-CwValue([string]$text) {
  if ($null -eq $text) { return '' }
  $text.Replace('"','\"')
}

function New-CwHeaders {
  $pair = "{0}+{1}:{2}" -f $cwCompanyId, $cwPublicKey, $cwPrivateKey
  $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
  @{
    Authorization = "Basic $basic"
    clientId = $cwClientId
    Accept = 'application/json'
    'Content-Type' = 'application/json'
  }
}

function Invoke-CwGetAll {
  param(
    [string]$Path,
    [string]$Conditions,
    [string]$OrderBy
  )

  $headers = New-CwHeaders
  $page = 1
  $pageSize = 100
  $all = New-Object System.Collections.Generic.List[object]

  do {
    $query = @()
    if (-not [string]::IsNullOrWhiteSpace($Conditions)) {
      $query += 'conditions=' + [uri]::EscapeDataString($Conditions)
    }
    if (-not [string]::IsNullOrWhiteSpace($OrderBy)) {
      $query += 'orderBy=' + [uri]::EscapeDataString($OrderBy)
    }
    $query += 'page=' + $page
    $query += 'pageSize=' + $pageSize
    $uri = "$cwApiUrl$($Path)?" + ($query -join '&')

    Write-Information "GET $Path page $page"
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
    $items = @($response)
    foreach ($item in $items) { [void]$all.Add($item) }
    $count = @($items).Count
    $page++
  } while ($count -ge $pageSize)

  $all.ToArray()
}

function Invoke-CwFirst {
  param([string]$Path, [string]$Conditions, [string]$OrderBy)
  $query = @('conditions=' + [uri]::EscapeDataString($Conditions), 'orderBy=' + [uri]::EscapeDataString($OrderBy), 'page=1', 'pageSize=1')
  $uri = "$cwApiUrl$($Path)?" + ($query -join '&')
  $response = Invoke-RestMethod -Method Get -Uri $uri -Headers (New-CwHeaders) -ErrorAction Stop
  @($response) | Where-Object { $null -ne $_ } | Select-Object -First 1
}

function Format-ShortDate($value) {
  if ($null -eq $value -or [string]$value -eq '') { return '' }
  try { ([datetime]$value).ToString('MMM d, yyyy', [Globalization.CultureInfo]::InvariantCulture) } catch { [string]$value }
}

function Get-PropValue($obj, [string[]]$paths) {
  foreach ($path in $paths) {
    $current = $obj
    $ok = $true
    foreach ($segment in $path.Split('.')) {
      if ($null -eq $current) { $ok = $false; break }
      $prop = $current.PSObject.Properties[$segment]
      if ($null -eq $prop) { $ok = $false; break }
      $current = $prop.Value
    }
    if ($ok -and $null -ne $current -and [string]$current -ne '') { return $current }
  }
  $null
}

$gaps = New-Object System.Collections.Generic.List[string]
if (-not $hourlyRateFromVault) {
  [void]$gaps.Add('Key Vault secret ValueReview-HourlyRate is missing or invalid. The default rate of $150 was used.')
}
$cwMatches = @()
$cwCompany = $null
$tickets = @()
$timeEntries = @()
$agreements = @()
$invoices = @()
$ticketDetailsById = @{}
$lastInvoice = $null
$lastAgreement = $null

$lookupMethod = ''
if ($psaCompanyId -match '^\d+$') {
  try {
    $one = Invoke-RestMethod -Method Get -Uri "$cwApiUrl/company/companies/$psaCompanyId" -Headers (New-CwHeaders) -ErrorAction Stop
    if ($null -ne $one -and $one.id) { $cwMatches = @($one); $lookupMethod = 'PSA record ID' }
  } catch {
    [void]$gaps.Add("ConnectWise lookup by PSA record ID $psaCompanyId failed: $($_.Exception.Message)$(if ($_.ErrorDetails -and $_.ErrorDetails.Message) { ' Response: ' + $_.ErrorDetails.Message })")
  }
}

$lookupAttempts = @()
if ((-not [string]::IsNullOrWhiteSpace($psaCompanyId)) -and ($psaCompanyId -notmatch '^\d+$')) {
  $lookupAttempts += [pscustomobject]@{ field = 'identifier'; value = $psaCompanyId }
}
if (-not [string]::IsNullOrWhiteSpace($companyName)) {
  $lookupAttempts += [pscustomobject]@{ field = 'identifier'; value = $companyName }
  $lookupAttempts += [pscustomobject]@{ field = 'name'; value = $companyName }
}

foreach ($attempt in $lookupAttempts) {
  if (@($cwMatches).Count -gt 0) { break }
  try {
    $conditions = $attempt.field + '="' + (Escape-CwValue $attempt.value) + '"'
    $cwMatches = @(Invoke-CwGetAll -Path '/company/companies' -Conditions $conditions -OrderBy 'name asc')
    if (@($cwMatches).Count -gt 0) { $lookupMethod = "$($attempt.field) '$($attempt.value)'" }
  } catch {
    [void]$gaps.Add("ConnectWise company lookup by $($attempt.field) failed: $($_.Exception.Message)$(if ($_.ErrorDetails -and $_.ErrorDetails.Message) { ' Response: ' + $_.ErrorDetails.Message })")
    $cwMatches = @()
  }
}

$lookupLabel = $companyName
if ([string]::IsNullOrWhiteSpace($lookupLabel)) { $lookupLabel = $psaCompanyId }

if (@($cwMatches).Count -gt 1) {
  $matchNames = @($cwMatches | ForEach-Object { [string]$_.name })
  [void]$gaps.Add("Multiple ConnectWise companies matched '$lookupLabel' by $($lookupMethod): $($matchNames -join ', ')")
} elseif (@($cwMatches).Count -eq 1) {
  $cwCompany = @($cwMatches)[0]
} else {
  [void]$gaps.Add("No ConnectWise company matched '$lookupLabel' by PSA record ID, identifier or name.")
}

if ([string]::IsNullOrWhiteSpace($companyName)) {
  if ($null -ne $cwCompany) { $companyName = [string]$cwCompany.name } else { $companyName = $lookupLabel }
}
$archiveTitle = "Value Review: $companyName ($periodLabelStart to $periodLabelEnd)"
$internalSubject = "Internal Value Review: $archiveTitle"

if ($null -ne $cwCompany) {
  $companyIdValue = [string]$cwCompany.id

  try {
    $ticketConditions = "company/id=$companyIdValue and dateEntered >= [$($periodStart.ToString('yyyy-MM-ddT00:00:00Z'))] and dateEntered < [$($periodEndExclusive.ToString('yyyy-MM-ddT00:00:00Z'))]"
    $tickets = @(Invoke-CwGetAll -Path '/service/tickets' -Conditions $ticketConditions -OrderBy 'dateEntered asc')
    if (@($tickets).Count -eq 0) { [void]$gaps.Add('No service tickets found in the period.') }
  } catch {
    [void]$gaps.Add("Ticket query failed: $($_.Exception.Message)$(if ($_.ErrorDetails -and $_.ErrorDetails.Message) { ' Response: ' + $_.ErrorDetails.Message })")
    $tickets = @()
  }

  try {
    $timeConditions = "company/id=$companyIdValue and timeStart >= [$($periodStart.ToString('yyyy-MM-ddT00:00:00Z'))] and timeStart < [$($periodEndExclusive.ToString('yyyy-MM-ddT00:00:00Z'))]"
    $timeEntries = @(Invoke-CwGetAll -Path '/time/entries' -Conditions $timeConditions -OrderBy 'timeStart asc')
    if (@($timeEntries).Count -eq 0) { [void]$gaps.Add('No time entries found in the period.') }
  } catch {
    [void]$gaps.Add("Time entry query failed: $($_.Exception.Message)$(if ($_.ErrorDetails -and $_.ErrorDetails.Message) { ' Response: ' + $_.ErrorDetails.Message })")
    $timeEntries = @()
  }

  try {
    $agreementConditions = "company/id=$companyIdValue and cancelledFlag=false"
    $agreementsRaw = @(Invoke-CwGetAll -Path '/finance/agreements' -Conditions $agreementConditions -OrderBy 'name asc')
    $agreements = @($agreementsRaw | Where-Object {
      $startOk = $true
      $endOk = $true
      $startVal = Get-PropValue $_ @('startDate')
      $endVal = Get-PropValue $_ @('endDate')
      if ($startVal) { $startOk = ([datetime]$startVal).Date -le $endDate.Date }
      if ($endVal) { $endOk = ([datetime]$endVal).Date -ge $startDate.Date }
      $startOk -and $endOk
    })
    if (@($agreements).Count -eq 0) {
      try { $lastAgreement = Invoke-CwFirst -Path '/finance/agreements' -Conditions "company/id=$companyIdValue" -OrderBy 'startDate desc' } catch { $lastAgreement = $null }
    }
  } catch {
    [void]$gaps.Add("Agreement query failed: $($_.Exception.Message)$(if ($_.ErrorDetails -and $_.ErrorDetails.Message) { ' Response: ' + $_.ErrorDetails.Message })")
    $agreements = @()
  }

  try {
    $invoiceConditions = "company/id=$companyIdValue and date >= [$($periodStart.ToString('yyyy-MM-ddT00:00:00Z'))] and date < [$($periodEndExclusive.ToString('yyyy-MM-ddT00:00:00Z'))]"
    $invoices = @(Invoke-CwGetAll -Path '/finance/invoices' -Conditions $invoiceConditions -OrderBy 'date asc')
    if (@($invoices).Count -eq 0) {
      try { $lastInvoice = Invoke-CwFirst -Path '/finance/invoices' -Conditions "company/id=$companyIdValue" -OrderBy 'date desc' } catch { $lastInvoice = $null }
    }
  } catch {
    [void]$gaps.Add("Invoice query failed: $($_.Exception.Message)$(if ($_.ErrorDetails -and $_.ErrorDetails.Message) { ' Response: ' + $_.ErrorDetails.Message })")
    $invoices = @()
  }

  $ticketIdsFromTime = @($timeEntries | ForEach-Object {
    $ticketId = Get-PropValue $_ @('chargeToId','ticket.id')
    $chargeType = [string](Get-PropValue $_ @('chargeToType'))
    if ($ticketId -and (($chargeType -eq 'ServiceTicket') -or (Get-PropValue $_ @('ticket.id')))) { [string]$ticketId }
  } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

  foreach ($ticket in @($tickets)) {
    if ($ticket.id) { $ticketDetailsById[[string]$ticket.id] = $ticket }
  }

  foreach ($ticketId in @($ticketIdsFromTime)) {
    if (-not $ticketDetailsById.ContainsKey([string]$ticketId)) {
      try {
        $headers = New-CwHeaders
        $uri = "$cwApiUrl/service/tickets/$ticketId"
        $ticketDetail = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
        if ($null -ne $ticketDetail) {
          $ticketDetailsById[[string]$ticketId] = $ticketDetail
        }
      } catch {
        [void]$gaps.Add("Ticket detail lookup failed for ticket #${ticketId}: $($_.Exception.Message)$(if ($_.ErrorDetails -and $_.ErrorDetails.Message) { ' Response: ' + $_.ErrorDetails.Message })")
      }
    }
  }
}

$ticketHoursMap = @{}
$ticketBillableMap = @{}
$ticketAgreementMap = @{}
$hoursByTechMap = @{}
$hoursByWorkTypeMap = @{}
$typeHoursMap = @{}
$hoursDelivered = 0.0
$coveredHours = 0.0

foreach ($entry in @($timeEntries)) {
  $ticketId = $null
  $chargeType = [string](Get-PropValue $entry @('chargeToType'))
  $chargeToId = Get-PropValue $entry @('chargeToId')
  $ticketObjId = Get-PropValue $entry @('ticket.id')
  if ($chargeToId -and ($chargeType -eq 'ServiceTicket')) { $ticketId = [string]$chargeToId }
  elseif ($ticketObjId) { $ticketId = [string]$ticketObjId }

  $hours = 0.0
  $hoursVal = Get-PropValue $entry @('actualHours','hoursActual')
  if ($null -ne $hoursVal -and [string]$hoursVal -ne '') { $hours = [double]$hoursVal }
  $hoursDelivered += $hours

  $billableOption = [string](Get-PropValue $entry @('billableOption','billable'))
  $agreementId = Get-PropValue $entry @('agreement.id','agreementId')
  $agreementName = [string](Get-PropValue $entry @('agreement.name'))
  $agreementCharged = $false
  if ($agreementId) { $agreementCharged = $true }
  if ($agreementCharged -or $billableOption -in @('NoCharge','DoNotBill')) {
    $coveredHours += $hours
  }

  $memberName = [string](Get-PropValue $entry @('member.name'))
  if ([string]::IsNullOrWhiteSpace($memberName)) { $memberName = 'Unknown' }
  if (-not $hoursByTechMap.ContainsKey($memberName)) { $hoursByTechMap[$memberName] = 0.0 }
  $hoursByTechMap[$memberName] = [double]$hoursByTechMap[$memberName] + $hours

  $workType = [string](Get-PropValue $entry @('workType.name','workRole.name'))
  if ([string]::IsNullOrWhiteSpace($workType)) { $workType = 'Unspecified' }
  if (-not $hoursByWorkTypeMap.ContainsKey($workType)) { $hoursByWorkTypeMap[$workType] = 0.0 }
  $hoursByWorkTypeMap[$workType] = [double]$hoursByWorkTypeMap[$workType] + $hours

  if ($ticketId) {
    if (-not $ticketHoursMap.ContainsKey($ticketId)) { $ticketHoursMap[$ticketId] = 0.0 }
    $ticketHoursMap[$ticketId] = [double]$ticketHoursMap[$ticketId] + $hours

    if (-not $ticketBillableMap.ContainsKey($ticketId)) { $ticketBillableMap[$ticketId] = New-Object System.Collections.Generic.List[string] }
    if (-not [string]::IsNullOrWhiteSpace($billableOption)) { [void]$ticketBillableMap[$ticketId].Add($billableOption) }

    if (-not $ticketAgreementMap.ContainsKey($ticketId)) { $ticketAgreementMap[$ticketId] = $false }
    if ($agreementCharged) { $ticketAgreementMap[$ticketId] = $true }

    $ticketType = 'Unspecified'
    if ($ticketDetailsById.ContainsKey($ticketId)) {
      $ticketTypeVal = Get-PropValue $ticketDetailsById[$ticketId] @('type.name')
      if ($ticketTypeVal) { $ticketType = [string]$ticketTypeVal }
    }
    if (-not $typeHoursMap.ContainsKey($ticketType)) { $typeHoursMap[$ticketType] = 0.0 }
    $typeHoursMap[$ticketType] = [double]$typeHoursMap[$ticketType] + $hours
  }
}

$amountPaid = 0.0
foreach ($invoice in @($invoices)) {
  $totalVal = Get-PropValue $invoice @('total')
  if ($null -ne $totalVal -and [string]$totalVal -ne '') { $amountPaid += [double]$totalVal }
}

$valueDelivered = $hoursDelivered * $hourlyRate
$clientSavings = $valueDelivered - $amountPaid
$hasInvoices = (@($invoices).Count -gt 0)
$savingsLabel = 'Client Savings'
$savingsDisplay = Format-Usd $clientSavings
$amountPaidDisplay = Format-Usd $amountPaid
if (-not $hasInvoices) {
  $amountPaidDisplay = 'No invoices'
  $savingsDisplay = 'N/A'
} elseif ($clientSavings -lt 0) {
  $savingsLabel = 'Investment above labor value'
  $savingsDisplay = Format-Usd([math]::Abs($clientSavings))
}

# When the period has no invoices or agreements, say so and point to the most recent ones on file.
$invoiceNote = ''
if (-not $hasInvoices) {
  if ($null -ne $lastInvoice) {
    $lastInvNumber = [string](Get-PropValue $lastInvoice @('invoiceNumber','identifier','id'))
    $lastInvDate = Format-ShortDate (Get-PropValue $lastInvoice @('date'))
    $lastInvTotalVal = Get-PropValue $lastInvoice @('total')
    $lastInvTotal = if ($null -ne $lastInvTotalVal -and [string]$lastInvTotalVal -ne '') { Format-Usd ([double]$lastInvTotalVal) } else { '' }
    $invoiceNote = "No invoices were recorded between $(Format-ShortDate $periodStart) and $(Format-ShortDate $endDate). The most recent invoice on file is #$lastInvNumber, dated $lastInvDate$(if ($lastInvTotal) { ", for $lastInvTotal" })."
  } else {
    $invoiceNote = 'No invoices are on file for this client.'
  }
  [void]$gaps.Add($invoiceNote)
}

$agreementNote = ''
if (@($agreements).Count -eq 0) {
  if ($null -ne $lastAgreement) {
    $lastAgrName = [string](Get-PropValue $lastAgreement @('name'))
    $lastAgrType = [string](Get-PropValue $lastAgreement @('type.name'))
    $lastAgrStart = Format-ShortDate (Get-PropValue $lastAgreement @('startDate'))
    $lastAgrEnd = Format-ShortDate (Get-PropValue $lastAgreement @('endDate'))
    $agreementNote = "No agreements were active between $(Format-ShortDate $periodStart) and $(Format-ShortDate $endDate). The most recent agreement on file is $lastAgrName$(if ($lastAgrType) { " ($lastAgrType)" }), which started $lastAgrStart$(if ($lastAgrEnd) { " and ended $lastAgrEnd" })."
  } else {
    $agreementNote = 'No agreements are on file for this client.'
  }
  [void]$gaps.Add($agreementNote)
}

$ticketsOpened = @($tickets).Count
$ticketsClosed = @($tickets | Where-Object { (Get-PropValue $_ @('closedDate','dateClosed')) }).Count
$afterHoursTickets = @($tickets | Where-Object {
  $entered = Get-PropValue $_ @('dateEntered')
  if (-not $entered) { return $false }
  $dt = [datetime]$entered
  $isWeekend = $dt.DayOfWeek -in @([System.DayOfWeek]::Saturday,[System.DayOfWeek]::Sunday)
  $isEarly = $dt.TimeOfDay -lt ([timespan]::FromHours(7))
  $isLate = $dt.TimeOfDay -ge ([timespan]::FromHours(18))
  ($isWeekend -or $isEarly -or $isLate)
}).Count

$closeHoursSamples = foreach ($ticket in @($tickets)) {
  $openedVal = Get-PropValue $ticket @('dateEntered')
  $closedVal = Get-PropValue $ticket @('closedDate','dateClosed')
  if ($openedVal -and $closedVal) {
    $opened = [datetime]$openedVal
    $closed = [datetime]$closedVal
    if ($closed -ge $opened) { ($closed - $opened).TotalHours }
  }
}
$avgHoursToClose = 0.0
if (@($closeHoursSamples).Count -gt 0) {
  $avgHoursToClose = ((@($closeHoursSamples) | Measure-Object -Average).Average)
}

$topTypes = @($typeHoursMap.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object {
  [pscustomobject]@{ type = $_.Key; hours = [double]$_.Value }
})

$hoursByTech = @($hoursByTechMap.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
  [pscustomobject]@{ technician = $_.Key; hours = [double]$_.Value }
})

$hoursByWorkType = @($hoursByWorkTypeMap.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
  [pscustomobject]@{ workType = $_.Key; hours = [double]$_.Value }
})

$agreementRows = @($agreements | ForEach-Object {
  $billAmount = 0.0
  $amountVal = Get-PropValue $_ @('amount','billAmount')
  if ($null -ne $amountVal -and [string]$amountVal -ne '') { $billAmount = [double]$amountVal }
  [pscustomobject]@{
    name = [string](Get-PropValue $_ @('name'))
    type = [string](Get-PropValue $_ @('type.name'))
    amount = $billAmount
    billingCycle = [string](Get-PropValue $_ @('billingCycle.name','billingCycle'))
    startDate = $(if (Get-PropValue $_ @('startDate')) { ([datetime](Get-PropValue $_ @('startDate'))).ToString('yyyy-MM-dd') } else { '' })
    endDate = $(if (Get-PropValue $_ @('endDate')) { ([datetime](Get-PropValue $_ @('endDate'))).ToString('yyyy-MM-dd') } else { '' })
  }
})

$invoiceRows = @($invoices | ForEach-Object {
  [pscustomobject]@{
    invoiceNumber = $(if (Get-PropValue $_ @('invoiceNumber','identifier','id')) { [string](Get-PropValue $_ @('invoiceNumber','identifier','id')) } else { '' })
    date = $(if (Get-PropValue $_ @('date')) { ([datetime](Get-PropValue $_ @('date'))).ToString('yyyy-MM-dd') } else { '' })
    type = [string](Get-PropValue $_ @('type.name','type'))
    total = $(if (Get-PropValue $_ @('total')) { [double](Get-PropValue $_ @('total')) } else { 0.0 })
  }
})

$fullTicketList = @($ticketHoursMap.Keys | ForEach-Object {
  $ticketId = [string]$_
  $ticket = $null
  if ($ticketDetailsById.ContainsKey($ticketId)) { $ticket = $ticketDetailsById[$ticketId] }
  $billableOptions = @()
  if ($ticketBillableMap.ContainsKey($ticketId)) { $billableOptions = @($ticketBillableMap[$ticketId].ToArray() | Select-Object -Unique) }
  [pscustomobject]@{
    id = $ticketId
    summary = $(if ($ticket) { [string](Get-PropValue $ticket @('summary')) } else { '' })
    type = $(if ($ticket) { [string](Get-PropValue $ticket @('type.name')) } else { '' })
    hours = [double]$ticketHoursMap[$ticketId]
    billableOptions = @($billableOptions)
  }
} | Sort-Object hours -Descending)

$flagItems = New-Object System.Collections.Generic.List[string]
foreach ($t in @($fullTicketList | Where-Object { $_.hours -gt 10 })) {
  [void]$flagItems.Add("Ticket #$($t.id) exceeded 10.0 hours ($([math]::Round($t.hours,1).ToString('N1'))h): $($t.summary)")
}
foreach ($entry in @($timeEntries)) {
  $billableOption = [string](Get-PropValue $entry @('billableOption','billable'))
  $agreementId = Get-PropValue $entry @('agreement.id','agreementId')
  if ($billableOption -eq 'NoCharge' -and -not $agreementId) {
    $ticketId = [string](Get-PropValue $entry @('chargeToId','ticket.id'))
    $member = [string](Get-PropValue $entry @('member.name'))
    if ([string]::IsNullOrWhiteSpace($member)) { $member = 'Unknown' }
    $hoursVal = Get-PropValue $entry @('actualHours','hoursActual')
    $hours = 0.0
    if ($hoursVal) { $hours = [double]$hoursVal }
    [void]$flagItems.Add("NoCharge entry without agreement on ticket #$ticketId by $member ($([math]::Round($hours,1).ToString('N1'))h)")
  }
}
$flags = @($flagItems.ToArray())

$periodDisplay = '{0} to {1}' -f (Format-ShortDate $periodStart), (Format-ShortDate $endDate)
$savingsColor = if (-not $hasInvoices) { '#1f2937' } elseif ($clientSavings -lt 0) { '#b45309' } else { '#15803d' }

function New-Tile([string]$Value, [string]$Label, [string]$Color) {
  "<td width='33%' valign='top' style='padding:4px;'><table role='presentation' width='100%' cellpadding='0' cellspacing='0' style='border:1px solid #e5e7eb;border-radius:6px;border-collapse:separate;'><tr><td align='center' style='padding:14px 6px 2px 6px;font-size:22px;font-weight:bold;color:$Color;'>$(HtmlEncode $Value)</td></tr><tr><td align='center' style='padding:0 6px 14px 6px;font-size:11px;color:#6b7280;'>$(HtmlEncode $Label)</td></tr></table></td>"
}

function New-Heading([string]$Text) {
  "<h2 style='font-size:16px;font-weight:bold;margin:24px 0 8px 0;color:#1f2937;'>$(HtmlEncode $Text)</h2>"
}

function New-Table {
  param([string[]]$Headers, [string[]]$Align, [object[]]$Rows, [string]$EmptyText)
  $head = for ($i = 0; $i -lt $Headers.Count; $i++) {
    "<th align='$($Align[$i])' style='background:#f3f4f6;font-weight:bold;padding:8px;border-bottom:1px solid #e5e7eb;text-align:$($Align[$i]);'>$(HtmlEncode $Headers[$i])</th>"
  }
  $body = @()
  if (@($Rows).Count -eq 0) {
    $body += "<tr><td colspan='$($Headers.Count)' style='padding:8px;border-bottom:1px solid #e5e7eb;color:#6b7280;'>$(HtmlEncode $EmptyText)</td></tr>"
  } else {
    $n = 0
    foreach ($r in $Rows) {
      $bg = if ($n % 2 -eq 1) { '#fafafa' } else { '#ffffff' }
      $cells = for ($i = 0; $i -lt $Headers.Count; $i++) {
        "<td align='$($Align[$i])' style='padding:8px;border-bottom:1px solid #e5e7eb;text-align:$($Align[$i]);'>$(HtmlEncode ([string]$r[$i]))</td>"
      }
      $body += "<tr style='background:$bg;'>$($cells -join '')</tr>"
      $n++
    }
  }
  "<table role='presentation' width='100%' cellpadding='0' cellspacing='0' style='border-collapse:collapse;font-size:13px;'><tr>$($head -join '')</tr>$($body -join '')</table>"
}

$wrapStart = "<html><body style='margin:0;padding:0;background:#ffffff;'><table role='presentation' width='100%' cellpadding='0' cellspacing='0' style='background:#ffffff;'><tr><td align='center'><table role='presentation' width='720' cellpadding='0' cellspacing='0' style='max-width:720px;width:100%;font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#1f2937;'><tr><td style='padding:24px;text-align:left;'>"
$wrapEnd = "</td></tr></table></td></tr></table></body></html>"

function New-ReportHeader([string]$Title) {
  "<div style='font-size:24px;font-weight:bold;color:#1f2937;'>$(HtmlEncode $Title)</div><div style='font-size:16px;margin-top:4px;'>$(HtmlEncode $companyName)</div><div style='font-size:12px;color:#6b7280;margin-top:2px;'>$(HtmlEncode $periodDisplay)</div><div style='border-top:1px solid #e5e7eb;margin-top:12px;font-size:1px;line-height:1px;'>&nbsp;</div>"
}

$kpiHtml = "<table role='presentation' width='100%' cellpadding='0' cellspacing='0' style='margin:12px 0 4px 0;'><tr>" +
  (New-Tile $amountPaidDisplay 'Amount Paid' '#1e3a8a') +
  (New-Tile (Format-Usd $valueDelivered) 'Value Delivered' '#1e3a8a') +
  (New-Tile $savingsDisplay $savingsLabel $savingsColor) +
  "</tr><tr>" +
  (New-Tile ([string]$ticketsClosed) 'Tickets Resolved' '#1f2937') +
  (New-Tile (Format-Hours $hoursDelivered) 'Hours Delivered' '#1f2937') +
  (New-Tile ([string]$afterHoursTickets) 'After-Hours Support' '#1f2937') +
  "</tr></table>"

$pStyle = "style='margin:0 0 8px 0;line-height:1.5;'"
$paidSentence = if ($hasInvoices) {
  "You paid $(Format-Usd $amountPaid) in invoiced services during the same period, and $($savingsLabel.ToLower()) was $savingsDisplay."
} else {
  $invoiceNote
}
$whatThisMeans = @(
  "<p $pStyle>$(HtmlEncode "During this review period, your team received $(Format-Hours $hoursDelivered) hours of support and service activity valued at $(Format-Usd $valueDelivered) using a standard rate of $(Format-Usd $hourlyRate) per hour.")</p>",
  "<p $pStyle>$(HtmlEncode $paidSentence)</p>",
  "<p $pStyle>$(HtmlEncode "Your support activity included $ticketsOpened ticket$(if ($ticketsOpened -ne 1) { 's' }) opened, $ticketsClosed resolved, and $afterHoursTickets after-hours request$(if ($afterHoursTickets -ne 1) { 's' }).")</p>"
) -join ''

$topTypeTableRows = @(foreach ($row in @($topTypes)) { ,@([string]$row.type, (Format-Hours $row.hours)) })
$agreementClientTableRows = @(foreach ($row in @($agreementRows)) { ,@([string]$row.name, [string]$row.type, (Format-Usd $row.amount)) })
$agreementEmpty = if ($agreementNote) { $agreementNote } else { 'No active agreements found.' }

$formulaFooter = "Calculation method: Value Delivered = Hours Delivered × Hourly Rate. Client Savings = Value Delivered − Amount Paid. Covered Hours = hours charged to an agreement or marked NoCharge/DoNotBill. Hourly rate used: $(Format-Usd $hourlyRate). Average Hours to Close is based on tickets opened in the period that also have a close date."
$footerHtml = "<p style='margin:24px 0 0 0;font-size:11px;line-height:1.5;color:#6b7280;'>$(HtmlEncode $formulaFooter) Generated $(Format-ShortDate (Get-Date)).</p>"



# ==== Brand: header banner and section headings (logo and tagline can be overridden with runner secrets) ====
$brandLogo = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'ValueReview-LogoUrl' -AsPlainText -ErrorAction SilentlyContinue
if ([string]::IsNullOrWhiteSpace($brandLogo)) { $brandLogo = '' }
$brandTagline = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'ValueReview-Tagline' -AsPlainText -ErrorAction SilentlyContinue
if ([string]::IsNullOrWhiteSpace($brandTagline)) { $brandTagline = '' }
function Get-BrandIcon { param([string]$Text)
    switch -Regex ($Text) { 'Service summary' { 'fa-chart-line' } 'What this means' { 'fa-lightbulb' } 'Ticket Types|issue types' { 'fa-ticket' } 'Agreement' { 'fa-file-contract' } 'asked for help' { 'fa-users' } 'Account health' { 'fa-heart-pulse' } 'Repeat' { 'fa-repeat' } 'Endpoint' { 'fa-laptop' } 'Microsoft 365|Security' { 'fa-shield-halved' } 'Technician' { 'fa-user-gear' } 'Invoice' { 'fa-receipt' } 'Ticket' { 'fa-list-check' } default { 'fa-circle-info' } } }
function Brand-Heading { param([string]$Text) return "<div style='display:flex;align-items:center;gap:10px;margin:22px 0 8px;padding:8px 12px;background:#E8F3F7;border:1px solid #B3D7E3;border-left:4px solid #B3C9D5;border-radius:10px'><span style='background:#001F54;color:#B3C9D5;width:32px;height:32px;border-radius:8px;display:inline-flex;align-items:center;justify-content:center'><i class='fal $(Get-BrandIcon $Text)'></i></span><span style='font-size:17px;font-weight:600;color:#001F54'>$(HtmlEncode $Text)</span></div>" }
function New-Heading { param([Parameter(Position = 0)][string]$Text) return (Brand-Heading $Text) }
function New-ReportHeader { param([Parameter(Position = 0)][string]$Title)
    return "<div style='background:linear-gradient(135deg,#001F54 0%,#09507B 55%,#1282A2 100%);color:#fff;padding:20px 24px;border-radius:12px;border-left:6px solid #B3C9D5;box-shadow:0 4px 14px rgba(0,31,84,.3);display:flex;align-items:center;gap:22px;flex-wrap:wrap;margin:0 0 12px'>$(if ($brandLogo) { "<div style='background:#fff;border-radius:10px;padding:6px 12px;display:inline-flex'><img src='$brandLogo' alt='Logo' style='height:48px;width:auto;display:block'></div>" })<div style='flex:1;min-width:220px'><div style='font-size:22px;font-weight:600'><i class='fal fa-chart-line' style='color:#B3C9D5'></i>&nbsp; $(HtmlEncode $Title): $(HtmlEncode $companyName)</div><div style='font-size:15px;opacity:.9;margin-top:6px'>$(HtmlEncode $periodLabelStart) to $(HtmlEncode $periodLabelEnd)</div>$(if ($brandTagline) { "<div style='font-size:12px;letter-spacing:.04em;text-transform:uppercase;color:#B3C9D5;margin-top:10px;font-weight:600'>$(HtmlEncode $brandTagline)</div>" })</div></div>" }

# ==== Brand from the client's portal (portalThemeColor, portalLogoUrl), else the MSP defaults above ====
function Apply-Brand { param([string]$Html, $B) if ([string]::IsNullOrEmpty($Html) -or $null -eq $B) { return $Html }; $map = [ordered]@{ '#001F54' = $B.primary; '#09507B' = $B.secondary; '#1282A2' = $B.accent; '#B3C9D5' = $B.light; '#E8F3F7' = $B.soft; '#B3D7E3' = $B.border }; foreach ($k in $map.Keys) { $val = [string]$map[$k]; if ($val -match '^#[0-9A-Fa-f]{6}$' -and $val -ne $k) { $Html = $Html.Replace($k, $val) } }; return $Html }
function Mix-Hex { param([string]$Hex, [string]$To, [double]$T) $a = $Hex.TrimStart('#'); $c = $To.TrimStart('#'); $o = '#'; for ($i = 0; $i -lt 6; $i += 2) { $x = [Convert]::ToInt32($a.Substring($i, 2), 16); $y = [Convert]::ToInt32($c.Substring($i, 2), 16); $o += ([int][math]::Round($x + ($y - $x) * $T)).ToString('X2') }; return $o }
$brand = [ordered]@{ primary = '#001F54'; secondary = '#09507B'; accent = '#1282A2'; light = '#B3C9D5'; soft = '#E8F3F7'; border = '#B3D7E3'; source = 'MSP default' }
$crCid = [string](Get-TrigVal @('company', 'id'))
if ($crCid -match '^\d+$') {
    try {
        $crBaseB = ([string](Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'CloudRadial-BaseUrl' -AsPlainText -ErrorAction Stop)).TrimEnd('/')
        $crPubB = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'CloudRadial-PublicKey' -AsPlainText -ErrorAction Stop
        $crPrivB = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'CloudRadial-PrivateKey' -AsPlainText -ErrorAction Stop
        $authB = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($crPubB):$($crPrivB)"))
        $coB = Invoke-RestMethod -Uri "$crBaseB/v2/company/$crCid" -Headers @{ Authorization = $authB; Accept = 'application/json' } -Method Get
        $cdB = if ($coB.PSObject.Properties['data']) { $coB.data } else { $coB }
        $logoB = [string]$cdB.portalLogoUrl; $themeB = ([string]$cdB.portalThemeColor).Trim()
        if ($logoB -match '^https?://') { $brandLogo = $logoB; $brand.source = 'client portal' }
        if ($themeB -match '^#?[0-9A-Fa-f]{6}$') { $t = '#' + $themeB.TrimStart('#').ToUpper()
            $brand.primary = Mix-Hex $t '#000000' 0.45; $brand.secondary = Mix-Hex $t '#000000' 0.2; $brand.accent = $t
            $brand.light = Mix-Hex $t '#FFFFFF' 0.65; $brand.soft = Mix-Hex $t '#FFFFFF' 0.9; $brand.border = Mix-Hex $t '#FFFFFF' 0.75; $brand.source = 'client portal' }
    } catch { }
}
function New-Table { param([string[]]$Headers, [string[]]$Align, [object[]]$Rows, [string]$EmptyText)
    if (-not @($Rows).Count) { return '<!--EMPTYTABLE-->' }
    $al = { param($i) if ($Align -and $i -lt $Align.Count -and $Align[$i]) { $Align[$i] } else { 'left' } }
    $th = for ($i = 0; $i -lt $Headers.Count; $i++) { "<th style='background:#001F54;color:#fff;text-align:$(& $al $i);padding:8px 10px;font-size:12px;letter-spacing:.03em;text-transform:uppercase;'>$(HtmlEncode $Headers[$i])</th>" }
    $n = 0; $trs = foreach ($r in $Rows) { $n++; $bg = if ($n % 2) { '#FFFFFF' } else { '#E8F3F7' }; $cells = @($r); $tds = for ($i = 0; $i -lt $cells.Count; $i++) { "<td style='padding:7px 10px;font-size:13px;color:#001F54;text-align:$(& $al $i);border-bottom:1px solid #B3D7E3;'>$(HtmlEncode ([string]$cells[$i]))</td>" }; "<tr style='background:$bg;'>$($tds -join '')</tr>" }
    return "<div style='border:1px solid #B3D7E3;border-radius:10px;overflow:hidden;margin:6px 0 4px;'><table style='width:100%;border-collapse:collapse;'><tr>$($th -join '')</tr>$($trs -join '')</table></div>"
}
function New-KpiTile { param([string]$Icon, [string]$Value, [string]$Label) "<td style='width:25%;padding:5px;vertical-align:top;'><div style='background:#E8F3F7;border:1px solid #B3D7E3;border-left:4px solid #1282A2;border-radius:10px;padding:12px;'><div style='display:flex;align-items:center;gap:8px;'><span style='background:#001F54;color:#B3C9D5;width:26px;height:26px;border-radius:7px;display:inline-flex;align-items:center;justify-content:center;font-size:12px;'><i class='fal $Icon'></i></span><span style='font-size:11px;letter-spacing:.04em;text-transform:uppercase;color:#09507B;font-weight:600;'>$(HtmlEncode $Label)</span></div><div style='font-size:22px;font-weight:700;color:#001F54;margin-top:8px;'>$(HtmlEncode $Value)</div></div></td>" }
$kpiHtml = "<table style='width:100%;border-collapse:collapse;margin:8px 0 4px;'><tr>" +
    (New-KpiTile 'fa-hand-holding-dollar' (Format-Usd $valueDelivered) 'Value delivered') + (New-KpiTile 'fa-file-invoice-dollar' (Format-Usd $amountPaid) 'Amount paid') +
    (New-KpiTile 'fa-piggy-bank' (Format-Usd ([math]::Abs([double]$clientSavings))) ([string]$(if ($savingsLabel) { $savingsLabel } else { 'Savings' }))) + (New-KpiTile 'fa-clock' "$([math]::Round([double]$hoursDelivered, 1)) h" 'Hours delivered') + "</tr><tr>" +
    (New-KpiTile 'fa-inbox-in' ([string]$ticketsOpened) 'Tickets opened') + (New-KpiTile 'fa-circle-check' ([string]$ticketsClosed) 'Tickets closed') +
    (New-KpiTile 'fa-stopwatch' "$([math]::Round([double]$avgHoursToClose, 1)) h" 'Avg time to resolve') + (New-KpiTile 'fa-moon' ([string]$afterHoursTickets) 'After-hours tickets') + "</tr></table>"
# ==== Service summary (client) and Account health (MSP): richer ticket insight with inline charts ====
function Get-TkText { param($o, [string]$k) if ($null -eq $o) { return '' }; $p = $o.PSObject.Properties[$k]; if (-not $p -or $null -eq $p.Value) { return '' }; $v = $p.Value; if ($v -is [string]) { return $v.Trim() }; $n = $v.PSObject.Properties['name']; if ($n -and $n.Value) { return ([string]$n.Value).Trim() }; return ([string]$v).Trim() }
function Get-TkDate { param($o, [string[]]$Keys) foreach ($k in $Keys) { $v = $null; if ($k -like '_info.*') { $i = $o.PSObject.Properties['_info']; if ($i -and $i.Value) { $q = $i.Value.PSObject.Properties[$k.Substring(6)]; if ($q) { $v = $q.Value } } } else { $q = $o.PSObject.Properties[$k]; if ($q) { $v = $q.Value } }; if ($v) { $d = [datetime]::MinValue; if ([datetime]::TryParse([string]$v, [ref]$d)) { return $d.ToUniversalTime() } } }; return $null }
function New-BarChart { param([string]$Title, [object[]]$Items, [string]$Note = '')
    if (-not @($Items).Count) { return '' }
    $max = (@($Items | ForEach-Object { [double]$_.value }) | Measure-Object -Maximum).Maximum; if (-not $max -or $max -le 0) { $max = 1 }
    $rows = foreach ($it in $Items) { $pct = if ([double]$it.value -le 0) { 0 } else { [math]::Max(2, [math]::Round(([double]$it.value / $max) * 100, 0)) }
        "<tr><td style='width:34%;padding:4px 8px 4px 0;font-size:13px;color:#374151;'>$(HtmlEncode $it.label)</td><td style='padding:4px 0;'><div style='background:#E8F3F7;border-radius:4px;height:16px;width:100%;'><div style='background:$($it.color);border-radius:4px;height:16px;width:$pct%;'></div></div></td><td style='width:18%;padding:4px 0 4px 8px;text-align:right;font-size:13px;font-weight:600;color:#111827;'>$(HtmlEncode $it.display)</td></tr>" }
    $n = if ($Note) { "<p style='margin:4px 0 0 0;font-size:12px;color:#6b7280;'>$(HtmlEncode $Note)</p>" } else { '' }
    return "<p style='margin:18px 0 6px 0;font-size:14px;font-weight:600;color:#111827;'>$(HtmlEncode $Title)</p><table style='width:100%;border-collapse:collapse;'>$($rows -join '')</table>$n"
}
function New-PairChart { param([string]$Title, [object[]]$Rows)
    if (-not @($Rows).Count) { return '' }
    $max = (@($Rows | ForEach-Object { [math]::Max([double]$_.a, [double]$_.b) }) | Measure-Object -Maximum).Maximum; if (-not $max -or $max -le 0) { $max = 1 }
    $bar = { param($v, $c) $p = if ([double]$v -le 0) { 0 } else { [math]::Max(2, [math]::Round(([double]$v / $max) * 100, 0)) }; "<div style='background:$c;border-radius:3px;height:9px;width:$p%;margin:1px 0;'></div>" }
    $trs = foreach ($r in $Rows) { "<tr><td style='width:22%;padding:3px 8px 3px 0;font-size:12px;color:#374151;'>$(HtmlEncode $r.label)</td><td style='padding:3px 0;'>$(& $bar $r.a '#1282A2')$(& $bar $r.b '#09507B')</td><td style='width:14%;padding:3px 0 3px 8px;text-align:right;font-size:12px;color:#111827;'>$($r.a) / $($r.b)</td></tr>" }
    return "<p style='margin:18px 0 6px 0;font-size:14px;font-weight:600;color:#111827;'>$(HtmlEncode $Title)</p><p style='margin:0 0 4px 0;font-size:12px;color:#6b7280;'><span style='color:#1282A2;'>&#9632;</span> Opened &nbsp; <span style='color:#09507B;'>&#9632;</span> Closed</p><table style='width:100%;border-collapse:collapse;'>$($trs -join '')</table>"
}
$tk = @($tickets)
$weekRows = @(); $ws = $periodStart.Date
while ($ws -lt $periodEndExclusive) { $we = $ws.AddDays(7); if ($we -gt $periodEndExclusive) { $we = $periodEndExclusive }
    $o = @($tk | Where-Object { $d = Get-TkDate $_ @('dateEntered', '_info.dateEntered'); $d -and $d -ge $ws -and $d -lt $we }).Count
    $c = @($tk | Where-Object { $d = Get-TkDate $_ @('closedDate', '_info.closedDate'); $d -and $d -ge $ws -and $d -lt $we }).Count
    $weekRows += [pscustomobject]@{ label = "Week of $($ws.ToString('d MMM'))"; a = $o; b = $c }; $ws = $we }
$palette = @('#1282A2', '#09507B', '#B3C9D5', '#001F54', '#4F86A6', '#C2410C', '#B3C9D5')
$pi = 0; $sourceItems = @($tk | Group-Object { $s = Get-TkText $_ 'source'; if ($s) { $s } else { 'Not recorded' } } | Sort-Object Count -Descending | ForEach-Object { [pscustomobject]@{ label = $_.Name; value = $_.Count; display = "$($_.Count) ($([math]::Round(100 * $_.Count / [math]::Max(1, $tk.Count), 0))%)"; color = $palette[($pi++) % $palette.Count] } })
$portalCount = @($tk | Where-Object { (Get-TkText $_ 'source') -match '(?i)portal|cloudradial|web' }).Count
$portalPct = if ($tk.Count) { [math]::Round(100 * $portalCount / $tk.Count, 0) } else { 0 }
$priorityItems = @($tk | Group-Object { $p = Get-TkText $_ 'priority'; if ($p) { $p } else { 'Not set' } } | Sort-Object Name | ForEach-Object { [pscustomobject]@{ label = $_.Name; value = $_.Count; display = [string]$_.Count; color = '#B3C9D5' } })
$typeCountItems = @($tk | Group-Object { $p = Get-TkText $_ 'type'; if ($p) { $p } else { 'Unspecified' } } | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { [pscustomobject]@{ label = $_.Name; value = $_.Count; display = [string]$_.Count; color = '#001F54' } })
$requesterRows = @($tk | Where-Object { (Get-TkText $_ 'contactName') -or (Get-TkText $_ 'contact') } | Group-Object { $n = Get-TkText $_ 'contactName'; if (-not $n) { $n = Get-TkText $_ 'contact' }; $n } | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { ,@([string]$_.Name, [string]$_.Count) })
$respond = @($tk | ForEach-Object { $m = 0.0; [double]::TryParse([string](Get-TkText $_ 'respondMinutes'), [ref]$m) | Out-Null; $m } | Where-Object { $_ -gt 0 })
$avgRespondText = if ($respond.Count) { $m = ($respond | Measure-Object -Average).Average; if ($m -ge 60) { "$([math]::Round($m / 60, 1)) hours" } else { "$([math]::Round($m, 0)) minutes" } } else { 'not recorded' }
$speedHtml = "<table style='width:100%;border-collapse:separate;border-spacing:8px 0;margin:8px 0 0 0;'><tr>" +
    "<td style='background:#E8F3F7;border:1px solid #B3D7E3;border-radius:10px;padding:14px;text-align:center;'><div style='font-size:22px;font-weight:700;color:#001F54;'>$portalPct%</div><div style='font-size:12px;color:#6b7280;'>of requests came through the portal</div></td>" +
    "<td style='background:#E8F3F7;border:1px solid #B3D7E3;border-radius:10px;padding:14px;text-align:center;'><div style='font-size:22px;font-weight:700;color:#001F54;'>$(HtmlEncode $avgRespondText)</div><div style='font-size:12px;color:#6b7280;'>average first response</div></td>" +
    "<td style='background:#E8F3F7;border:1px solid #B3D7E3;border-radius:10px;padding:14px;text-align:center;'><div style='font-size:22px;font-weight:700;color:#001F54;'>$([math]::Round([double]$avgHoursToClose, 1)) h</div><div style='font-size:12px;color:#6b7280;'>average time to resolve</div></td></tr></table>"
$chartsHtml = (New-Heading 'Service summary') + $speedHtml +
    (New-PairChart 'Tickets opened and closed by week' $weekRows) +
    (New-BarChart 'How requests came in' $sourceItems $(if ($portalPct -lt 50 -and $tk.Count) { 'Requests through the portal are routed and answered faster than email or phone.' } else { '' })) +
    (New-BarChart 'Tickets by priority' $priorityItems) +
    (New-BarChart 'Top issue types' $typeCountItems) +
    (New-BarChart 'Value delivered vs. amount paid' @([pscustomobject]@{ label = 'Value delivered'; value = [double]$valueDelivered; display = (Format-Usd $valueDelivered); color = '#09507B' }, [pscustomobject]@{ label = 'Amount paid'; value = [double]$amountPaid; display = (Format-Usd $amountPaid); color = '#B3C9D5' })) +
    $(if ($requesterRows.Count) { (New-Heading 'Who asked for help most') + (New-Table -Headers @('Contact', 'Tickets') -Align @('left', 'right') -Rows $requesterRows -EmptyText '') } else { '' })
$effRate = if ([double]$hoursDelivered -gt 0) { [double]$amountPaid / [double]$hoursDelivered } else { 0 }
$coveragePct = if ([double]$hoursDelivered -gt 0) { [math]::Round(100 * [double]$coveredHours / [double]$hoursDelivered, 0) } else { 0 }
$repeatRows = @($tk | Group-Object { ((Get-TkText $_ 'summary').ToLowerInvariant() -replace '[^a-z0-9 ]', '' -replace '\s+', ' ').Trim() } | Where-Object { $_.Name -and $_.Count -ge 2 } | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { ,@((Get-TkText $_.Group[0] 'summary'), [string]$_.Count) })
$mspHtml = (New-Heading 'Account health') +
    (New-BarChart 'Effective hourly rate vs. standard rate' @([pscustomobject]@{ label = 'Effective rate'; value = $effRate; display = (Format-Usd $effRate); color = $(if ($effRate -ge $hourlyRate) { '#09507B' } else { '#C2410C' }) }, [pscustomobject]@{ label = 'Standard rate'; value = [double]$hourlyRate; display = (Format-Usd $hourlyRate); color = '#B3C9D5' }) 'Effective rate = amount paid divided by hours delivered in the period.') +
    (New-BarChart 'Agreement coverage' @([pscustomobject]@{ label = 'Covered hours'; value = [double]$coveredHours; display = "$([math]::Round([double]$coveredHours, 1)) h"; color = '#09507B' }, [pscustomobject]@{ label = 'All hours delivered'; value = [double]$hoursDelivered; display = "$([math]::Round([double]$hoursDelivered, 1)) h ($coveragePct% covered)"; color = '#1282A2' })) +
    $(if ($repeatRows.Count) { (New-Heading 'Repeat issues: automation or project candidates') + (New-Table -Headers @('Issue', 'Times logged') -Align @('left', 'right') -Rows $repeatRows -EmptyText '') } else { '' })

# ==== Report sanity: only show numbers that mean something, and say what actually happened ====
$hasMoney = ([double]$amountPaid -gt 0 -or [double]$valueDelivered -gt 0)
$hasHours = ([double]$hoursDelivered -gt 0)
$stillOpen = [math]::Max(0, [int]$ticketsOpened - [int]$ticketsClosed)
$highPri = @($tk | Where-Object { (Get-TkText $_ 'priority') -match '(?i)priority\s*[12]\b|emergency|critical|urgent|high|quick' }).Count
$resolveText = if ([int]$ticketsClosed -gt 0 -and [double]$avgHoursToClose -gt 0) { "$([math]::Round([double]$avgHoursToClose, 1)) h" } elseif ([int]$ticketsClosed -gt 0) { 'under 1 h' } else { 'none closed yet' }
# Issue categories: the ConnectWise type when set, else read from the ticket summary
$issueRules = [ordered]@{ 'Passwords and sign-in' = 'password|passcode|log ?in|sign.?in|mfa|authenticat|locked out|lockout|reset'; 'Email and calendar' = 'e-?mail|outlook|mailbox|calendar|exchange|spam|phish'; 'Printing and scanning' = 'print|scan|copier|toner'; 'Network and internet' = 'network|wi-?fi|internet|vpn|remote|connect|slow|offline|firewall'; 'Software and apps' = 'software|install|licen[cs]e|app\b|application|update|teams|office|excel|word|pdf|adobe|ehr|emr|epic'; 'Computers and devices' = 'laptop|computer|\bpc\b|desktop|monitor|keyboard|mouse|hardware|device|dock|phone|tablet|ipad'; 'People and access' = 'new (user|hire|starter)|onboard|offboard|terminat|leaver|access|permission|share|folder' }
function Get-IssueCategory { param($t) $ty = Get-TkText $t 'type'; if ($ty -and $ty -notmatch '^(?i)unspecified|none|other$') { return $ty }; $s = (Get-TkText $t 'summary'); foreach ($k in $issueRules.Keys) { if ($s -match "(?i)$($issueRules[$k])") { return $k } }; return 'General support' }
$issueGroups = @($tk | Group-Object { Get-IssueCategory $_ } | Sort-Object Count -Descending)
$typeCountItems = @($issueGroups | Select-Object -First 6 | ForEach-Object { [pscustomobject]@{ label = $_.Name; value = $_.Count; display = "$($_.Count) ($([math]::Round(100 * $_.Count / [math]::Max(1, $tk.Count), 0))%)"; color = '#001F54' } })
$busiest = $weekRows | Sort-Object a -Descending | Select-Object -First 1
$topReq = if ($requesterRows.Count) { $requesterRows[0] } else { $null }
$days = if ($timeframeDays -gt 0) { $timeframeDays } else { [int](($periodEndExclusive - $periodStart).TotalDays) }
# KPI tiles: money and hours only when the PSA has them
$tiles = @()
if ($hasMoney) { $tiles += ,@('fa-hand-holding-dollar', (Format-Usd $valueDelivered), 'Value delivered'); $tiles += ,@('fa-file-invoice-dollar', (Format-Usd $amountPaid), 'Amount paid') }
if ($hasHours) { $tiles += ,@('fa-clock', "$([math]::Round([double]$hoursDelivered, 1)) h", 'Hours delivered') }
$tiles += ,@('fa-inbox-in', [string]$ticketsOpened, 'Requests opened'); $tiles += ,@('fa-circle-check', [string]$ticketsClosed, 'Resolved'); $tiles += ,@('fa-hourglass-half', [string]$stillOpen, 'Still open')
$tiles += ,@('fa-comments', "$portalPct%", 'Through portal or chat'); $tiles += ,@('fa-bolt', [string]$highPri, 'High priority')
if ([int]$ticketsClosed -gt 0) { $tiles += ,@('fa-stopwatch', $resolveText, 'Avg time to resolve') }
if ([int]$afterHoursTickets -gt 0) { $tiles += ,@('fa-moon', [string]$afterHoursTickets, 'After hours') }
$tiles = @($tiles | Select-Object -First 8)
$kpiRows = @(); for ($i = 0; $i -lt $tiles.Count; $i += 4) { $kpiRows += '<tr>' + (($tiles[$i..([math]::Min($i + 3, $tiles.Count - 1))] | ForEach-Object { New-KpiTile $_[0] $_[1] $_[2] }) -join '') + '</tr>' }
$kpiHtml = "<table style='width:100%;border-collapse:collapse;margin:8px 0 4px;'>$($kpiRows -join '')</table>"
$speedCells = @("<td style='background:#E8F3F7;border:1px solid #B3D7E3;border-radius:10px;padding:14px;text-align:center;'><div style='font-size:22px;font-weight:700;color:#001F54;'>$portalPct%</div><div style='font-size:12px;color:#09507B;'>of requests came through the portal or chat</div></td>")
if ($respond.Count) { $speedCells += "<td style='background:#E8F3F7;border:1px solid #B3D7E3;border-radius:10px;padding:14px;text-align:center;'><div style='font-size:22px;font-weight:700;color:#001F54;'>$(HtmlEncode $avgRespondText)</div><div style='font-size:12px;color:#09507B;'>average first response</div></td>" }
$speedCells += "<td style='background:#E8F3F7;border:1px solid #B3D7E3;border-radius:10px;padding:14px;text-align:center;'><div style='font-size:22px;font-weight:700;color:#001F54;'>$(HtmlEncode $resolveText)</div><div style='font-size:12px;color:#09507B;'>average time to resolve</div></td>"
$speedHtml = "<table style='width:100%;border-collapse:separate;border-spacing:8px 0;margin:8px 0 0 0;'><tr>$($speedCells -join '')</tr></table>"
$chartsHtml = (New-Heading 'Service summary') + $speedHtml +
    (New-PairChart 'Requests opened and resolved by week' $weekRows) +
    (New-BarChart 'What people needed help with' $typeCountItems) +
    (New-BarChart 'How requests came in' $sourceItems) +
    (New-BarChart 'Requests by priority' $priorityItems) +
    $(if ($hasMoney) { New-BarChart 'Value delivered vs. amount paid' @([pscustomobject]@{ label = 'Value delivered'; value = [double]$valueDelivered; display = (Format-Usd $valueDelivered); color = '#09507B' }, [pscustomobject]@{ label = 'Amount paid'; value = [double]$amountPaid; display = (Format-Usd $amountPaid); color = '#B3C9D5' }) } else { '' }) +
    $(if ($requesterRows.Count) { (New-Heading 'Who asked for help most') + (New-Table -Headers @('Contact', 'Requests') -Align @('left', 'right') -Rows $requesterRows -EmptyText '') } else { '' })
# "What this means", written from what happened
$pStyleW = "style='margin:6px 0;font-size:14px;line-height:1.6;color:#001F54;'"
$wt = @()
$wt += "In the last $days days your team raised <b>$ticketsOpened requests</b>$(if ($tk.Count) { ", and <b>$portalPct%</b> of them came in through the portal or chat, where they are logged and routed straight to the right technician" })."
if ($issueGroups.Count) { $wt += "The most common need was <b>$(HtmlEncode $issueGroups[0].Name)</b> ($($issueGroups[0].Count) requests)$(if ($issueGroups.Count -gt 1) { ", followed by $(HtmlEncode $issueGroups[1].Name) ($($issueGroups[1].Count))" })." }
if ($busiest -and [int]$busiest.a -gt 0) { $wt += "The busiest week was the $(HtmlEncode ($busiest.label -replace '^Week', 'week')) with $($busiest.a) requests." }
if ($topReq) { $wt += "$(HtmlEncode $topReq[0]) raised the most requests ($($topReq[1]))." }
$wt += $(if ([int]$ticketsClosed -gt 0) { "$ticketsClosed were resolved$(if ($resolveText -notmatch 'none') { " in an average of $resolveText" }) and $stillOpen are still in progress." } else { "All $stillOpen are still in progress; resolved work will show here at the next review." })
if ($hasMoney) { $wt += "The work delivered was worth $(Format-Usd $valueDelivered) at standard rates, against $(Format-Usd $amountPaid) paid." }
if ($highPri) { $wt += "$highPri request$(if ($highPri -ne 1) { 's were' } else { ' was' }) high priority." }
if (-not $hasMoney -and -not $hasHours) { $footerHtml = "<p style='margin:24px 0 0 0;font-size:11px;line-height:1.5;color:#6b7280;'>Based on tickets in your PSA for this period. Generated $(Format-ShortDate (Get-Date)).</p>" }
$whatThisMeans = ($wt | ForEach-Object { "<p $pStyleW>$_</p>" }) -join ''

# ==== QBR prep brief (for the QBR prep Planner card; the Endpoint refresh plan is added by that step) ====
$tp = @()
if ($issueGroups.Count) { $ig = $issueGroups[0]; $tp += "<b>$(HtmlEncode $ig.Name)</b> drove $($ig.Count) of $($tk.Count) requests ($([math]::Round(100 * $ig.Count / [math]::Max(1, $tk.Count), 0))%). Worth asking what is behind it and whether a project would fix it for good." }
if ($tk.Count) { $tp += $(if ($portalPct -ge 60) { "<b>$portalPct%</b> of requests came through the portal or chat. Recognize the team for adopting it." } else { "Only <b>$portalPct%</b> of requests came through the portal or chat. Show them how to submit from the portal for faster routing." }) }
if ($stillOpen) { $tp += "<b>$stillOpen request$(if ($stillOpen -ne 1) { 's are' } else { ' is' }) still open.</b> Review the oldest before the meeting so there are no surprises." }
if ($highPri) { $tp += "<b>$highPri high-priority request$(if ($highPri -ne 1) { 's' }).</b> Check whether any point to a recurring problem." }
if ($topReq) { $tp += "<b>$(HtmlEncode $topReq[0])</b> raised $($topReq[1]) requests. A quick check-in or some training could help." }
if ($busiest -and [int]$busiest.a -gt 0) { $tp += "The busiest week was the $(HtmlEncode ($busiest.label -replace '^Week', 'week')) with $($busiest.a) requests. Ask if anything changed that week." }
$tpHtml = if ($tp.Count) { (New-Heading 'Talking points for the meeting') + "<ul style='margin:6px 0 0 18px;color:#001F54;font-size:14px;line-height:1.6;'>" + (($tp | ForEach-Object { "<li>$_</li>" }) -join '') + '</ul>' } else { '' }
$qbrHtml = "<div style='background:linear-gradient(135deg,#001F54 0%,#09507B 55%,#1282A2 100%);color:#fff;padding:16px 20px;border-radius:12px;border-left:6px solid #B3C9D5;box-shadow:0 4px 14px rgba(0,31,84,.3);margin:0 0 10px;'><div style='font-size:19px;font-weight:600;'><i class='fal fa-calendar-check' style='color:#B3C9D5;'></i>&nbsp; QBR prep: $(HtmlEncode $companyName)</div><div style='font-size:14px;opacity:.9;margin-top:4px;'>The last $days days, $(HtmlEncode $periodStart.ToString('d MMM')) to $(HtmlEncode $periodEndExclusive.AddDays(-1).ToString('d MMM yyyy')). Everything below comes from your PSA and the portal.</div></div>" +
    $kpiHtml +
    (New-PairChart 'Requests opened and resolved by week' $weekRows) +
    (New-BarChart 'What people needed help with' $typeCountItems) +
    '<!--ENDPOINT-PLAN-->' + $tpHtml + '<!--ENDPOINT-TALK-->'
$clientReportHtmlBase = $wrapStart +
  (New-ReportHeader 'Value Review') +
  $kpiHtml +
  $chartsHtml +
  (New-Heading 'What this means') + $whatThisMeans +
  (New-Heading 'Top 5 Ticket Types by Hours') + (New-Table -Headers @('Ticket Type', 'Hours') -Align @('left', 'right') -Rows $topTypeTableRows -EmptyText 'No ticket type hours available.') +
  (New-Heading 'Agreements') + (New-Table -Headers @('Name', 'Type', 'Monthly Amount') -Align @('left', 'left', 'right') -Rows $agreementClientTableRows -EmptyText $agreementEmpty) +
  $footerHtml +
  $wrapEnd

$techTableRows = @(foreach ($row in @($hoursByTech)) { ,@([string]$row.technician, (Format-Hours $row.hours)) })
$workTypeTableRows = @(foreach ($row in @($hoursByWorkType)) { ,@([string]$row.workType, (Format-Hours $row.hours)) })
$ticketTableRows = @(foreach ($row in @($fullTicketList)) { ,@([string]$row.id, [string]$row.summary, [string]$row.type, (Format-Hours $row.hours), ((@($row.billableOptions)) -join ', ')) })
$agreementInternalTableRows = @(foreach ($row in @($agreementRows)) { ,@([string]$row.name, [string]$row.type, (Format-Usd $row.amount), [string]$row.billingCycle, [string]$row.startDate, [string]$row.endDate) })
$invoiceTableRows = @(foreach ($row in @($invoiceRows)) { ,@([string]$row.invoiceNumber, [string]$row.date, [string]$row.type, (Format-Usd $row.total)) })
$invoiceEmpty = if ($invoiceNote) { $invoiceNote } else { 'No invoice detail available.' }
$flagRows = if (@($flags).Count -gt 0) { '<ul><li>' + ((@($flags) | ForEach-Object { HtmlEncode $_ }) -join '</li><li>') + '</li></ul>' } else { '<p>No flagged tickets or entries.</p>' }

# <!--START_HERE--> is replaced by Finalize Review Outputs with the data gaps and flags box.
$internalSectionsHtml = $wrapStart +
  (New-ReportHeader 'Internal Value Review') +
  $kpiHtml +
  $mspHtml +
  '<!--START_HERE-->' +
  "<p $pStyle><strong>Covered Hours:</strong> $(Format-Hours $coveredHours) &nbsp;|&nbsp; <strong>Average Hours to Close:</strong> $(Format-Hours $avgHoursToClose) &nbsp;|&nbsp; <strong>Tickets Opened:</strong> $ticketsOpened</p>" +
  (New-Heading 'Hours by Technician') + (New-Table -Headers @('Technician', 'Hours') -Align @('left', 'right') -Rows $techTableRows -EmptyText 'No technician hours available.') +
  (New-Heading 'Hours by Work Type') + (New-Table -Headers @('Work Type', 'Hours') -Align @('left', 'right') -Rows $workTypeTableRows -EmptyText 'No work type hours available.') +
  (New-Heading 'Full Ticket List') + (New-Table -Headers @('ID', 'Summary', 'Type', 'Hours', 'Billable Option') -Align @('left', 'left', 'left', 'right', 'left') -Rows $ticketTableRows -EmptyText 'No ticket detail available.') +
  (New-Heading 'Top 5 Ticket Types by Hours') + (New-Table -Headers @('Ticket Type', 'Hours') -Align @('left', 'right') -Rows $topTypeTableRows -EmptyText 'No ticket type hours available.') +
  (New-Heading 'Agreements') + (New-Table -Headers @('Name', 'Type', 'Amount', 'Cycle', 'Start', 'End') -Align @('left', 'left', 'right', 'left', 'left', 'left') -Rows $agreementInternalTableRows -EmptyText $agreementEmpty) +
  (New-Heading 'Invoices in Period') + (New-Table -Headers @('Invoice #', 'Date', 'Type', 'Total') -Align @('left', 'left', 'left', 'right') -Rows $invoiceTableRows -EmptyText $invoiceEmpty) +
  $footerHtml +
  $wrapEnd

$clientNotifyText = "Your value review for $companyName covering $(Format-ShortDate $periodStart) to $(Format-ShortDate $endDate) is now available in your CloudRadial portal."

$kpis = [pscustomobject]@{
  amountPaid = [math]::Round($amountPaid,0)
  valueDelivered = [math]::Round($valueDelivered,0)
  clientSavings = [math]::Round($clientSavings,0)
  clientSavingsDisplayValue = [math]::Round([math]::Abs($clientSavings),0)
  savingsLabel = $savingsLabel
  hasInvoices = $hasInvoices
  invoiceNote = $invoiceNote
  agreementNote = $agreementNote
  ticketsOpened = $ticketsOpened
  ticketsClosed = $ticketsClosed
  hoursDelivered = [math]::Round($hoursDelivered,1)
  coveredHours = [math]::Round($coveredHours,1)
  averageHoursToClose = [math]::Round($avgHoursToClose,1)
  afterHoursTickets = $afterHoursTickets
  hourlyRate = [math]::Round($hourlyRate,0)
}

$emptyRx = "<div style='display:flex;align-items:center;gap:10px;margin:22px 0 8px;[^>]*>(?:(?!</div>).)*</div>\s*<!--EMPTYTABLE-->"
$clientReportHtmlBase = [regex]::Replace($clientReportHtmlBase, $emptyRx, '', 'Singleline').Replace('<!--EMPTYTABLE-->', '')
$internalSectionsHtml = [regex]::Replace($internalSectionsHtml, $emptyRx, '', 'Singleline').Replace('<!--EMPTYTABLE-->', '')
$qbrHtml = Apply-Brand ([regex]::Replace($qbrHtml, $emptyRx, '', 'Singleline').Replace('<!--EMPTYTABLE-->', '')) $brand
$clientReportHtmlBase = Apply-Brand $clientReportHtmlBase $brand
$internalSectionsHtml = Apply-Brand $internalSectionsHtml $brand
$stopAfterBuild = [bool](@($cwMatches).Count -ne 1)

Set-NodeOutput @{
  status = 'success'
  message = "Built value review data for $companyName."
  brand = $brand
  qbrHtml = $qbrHtml
  companyName = $companyName
  cwCompanyName = $(if ($cwCompany) { [string]$cwCompany.name } else { '' })
  cwIdentifier = $(if ($cwCompany) { [string]$cwCompany.identifier } else { '' })
  psaCompanyId = $(if ($cwCompany) { [string]$cwCompany.id } else { $psaCompanyId })
  lookupMethod = $lookupMethod
  periodStart = $periodLabelStart
  periodEnd = $periodLabelEnd
  hourlyRate = [math]::Round($hourlyRate,0)
  archiveTitle = $archiveTitle
  internalSubject = $internalSubject
  clientNotifySubject = 'Your value review is ready'
  clientNotifyText = $clientNotifyText
  clientEmail = $clientEmail
  formulaFooter = $formulaFooter
  cwResolved = [bool]($null -ne $cwCompany)
  cwMatchCount = @($cwMatches).Count
  cwMatches = @($cwMatches | ForEach-Object { [pscustomobject]@{ id = $_.id; name = $_.name } })
  stopAfterBuild = $stopAfterBuild
  gaps = @($gaps.ToArray())
  kpis = $kpis
  agreements = @($agreementRows)
  invoices = @($invoiceRows)
  hoursByTechnician = @($hoursByTech)
  hoursByWorkType = @($hoursByWorkType)
  topTicketTypes = @($topTypes)
  flags = @($flags)
  fullTicketList = @($fullTicketList)
  clientReportHtmlBase = $clientReportHtmlBase
  internalSectionsHtml = $internalSectionsHtml
}
