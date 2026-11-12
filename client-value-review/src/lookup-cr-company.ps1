$nodeInput = Get-NodeInput
if ($null -eq $nodeInput) { $nodeInput = @{} }

$companyName = [string](Get-NodeInput -Name 'companyName')
$stopAfterBuild = ([string](Get-NodeInput -Name 'stopAfterBuild')) -eq 'true'

$cwCompanyName = [string](Get-NodeInput -Name 'cwCompanyName')

$cwIdentifier = [string](Get-NodeInput -Name 'cwIdentifier')

$psaCompanyId = [string](Get-NodeInput -Name 'psaCompanyId')

if ($stopAfterBuild) {
  Set-NodeOutput @{
    status = 'success'
    message = 'Skipped CloudRadial lookup because ConnectWise company was not uniquely resolved.'
    crMatchCount = 0
    crMatches = @()
    crCompanyFound = $false
    crCompanyId = $null
    archiveAllowed = $false
    archiveGapText = 'CloudRadial archive skipped because ConnectWise company was not uniquely resolved.'
  }
  return
}

$crPublicKey = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'CloudRadial-PublicKey' -AsPlainText -ErrorAction SilentlyContinue
$crPrivateKey = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'CloudRadial-PrivateKey' -AsPlainText -ErrorAction SilentlyContinue
$crBaseUrl = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'CloudRadial-BaseUrl' -AsPlainText -ErrorAction SilentlyContinue

$missingSecrets = @()
if ([string]::IsNullOrWhiteSpace($crPublicKey)) { $missingSecrets += 'CloudRadial-PublicKey' }
if ([string]::IsNullOrWhiteSpace($crPrivateKey)) { $missingSecrets += 'CloudRadial-PrivateKey' }
if ([string]::IsNullOrWhiteSpace($crBaseUrl)) { $missingSecrets += 'CloudRadial-BaseUrl' }
if ($missingSecrets.Count -gt 0) {
  Set-NodeOutput @{
    status = 'success'
    message = 'CloudRadial lookup skipped because required secrets are missing.'
    crMatchCount = 0
    crMatches = @()
    crCompanyFound = $false
    crCompanyId = $null
    archiveAllowed = $false
    archiveGapText = "CloudRadial company lookup skipped because required secret(s) are missing: $($missingSecrets -join ', ')"
  }
  return
}

function Invoke-CrOData {
  param([string]$EntitySet, [string]$Filter, [string]$Select)
  $pair = '{0}:{1}' -f $crPublicKey, $crPrivateKey
  $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
  $headers = @{ Authorization = "Basic $basic"; Accept = 'application/json' }
  $query = @()
  if ($Filter) { $query += '$filter=' + [uri]::EscapeDataString($Filter) }
  if ($Select) { $query += '$select=' + [uri]::EscapeDataString($Select) }
  $uri = "$crBaseUrl/v2/odata/$EntitySet"
  if ($query.Count -gt 0) { $uri += '?' + ($query -join '&') }
  Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
}

try {
  $candidates = @(@($companyName, $cwCompanyName, $cwIdentifier) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
  $matches = @()
  $matchedOn = ''
  if ($psaCompanyId -match '^\d+$') {
    $result = Invoke-CrOData -EntitySet 'Company' -Filter "psaKey eq $psaCompanyId" -Select 'companyId,name,psaKey'
    $found = if ($null -ne $result -and $null -ne $result.value) { @($result.value) } else { @() }
    if (@($found).Count -gt 0) { $matches = $found; $matchedOn = "PSA key $psaCompanyId" }
  }
  foreach ($candidate in $candidates) {
    if (@($matches).Count -gt 0) { break }
    $safeName = ([string]$candidate).Replace("'","''")
    $result = Invoke-CrOData -EntitySet 'Company' -Filter "name eq '$safeName'" -Select 'companyId,name'
    $found = if ($null -ne $result -and $null -ne $result.value) { @($result.value) } else { @() }
    if (@($found).Count -gt 0) { $matches = $found; $matchedOn = [string]$candidate; break }
  }

  if (@($matches).Count -eq 1) {
    Set-NodeOutput @{
      status = 'success'
      message = "Resolved one CloudRadial company match on '$matchedOn'."
      crMatchCount = 1
      crMatches = @($matches)
      crCompanyFound = $true
      crCompanyId = @($matches)[0].companyId
      archiveAllowed = $true
      archiveGapText = ''
    }
    return
  }

  if (@($matches).Count -gt 1) {
    Set-NodeOutput @{
      status = 'success'
      message = 'Multiple CloudRadial companies matched; archive will be skipped.'
      crMatchCount = @($matches).Count
      crMatches = @($matches)
      crCompanyFound = $false
      crCompanyId = $null
      archiveAllowed = $false
      archiveGapText = "Multiple CloudRadial companies matched '$matchedOn': $((@($matches) | ForEach-Object { $_.name }) -join ', '). Archive post skipped."
    }
    return
  }

  Set-NodeOutput @{
    status = 'success'
    message = 'No CloudRadial company matched; archive will be skipped.'
    crMatchCount = 0
    crMatches = @()
    crCompanyFound = $false
    crCompanyId = $null
    archiveAllowed = $false
    archiveGapText = "No CloudRadial company matched $(($candidates | ForEach-Object { "'$_'" }) -join ' or '); archive post skipped."
  }
} catch {
  Set-NodeOutput @{
    status = 'success'
    message = 'CloudRadial lookup failed; archive will be skipped.'
    crMatchCount = 0
    crMatches = @()
    crCompanyFound = $false
    crCompanyId = $null
    archiveAllowed = $false
    archiveGapText = "CloudRadial company lookup failed: $($_.Exception.Message)"
  }
}
