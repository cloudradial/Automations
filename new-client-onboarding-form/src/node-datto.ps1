# === NODE: Create Datto RMM site ===
# Creates the client's Datto RMM site (or reuses one with the same name), so new devices land under the right client.
# Secrets: Datto-ApiUrl, Datto-ApiKey, Datto-ApiSecret (the same ones Patch Compliance Report uses).
$ErrorActionPreference = 'Stop'
function P { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Out { param([string]$Status, [string]$Message, [hashtable]$More = @{}) $o = [ordered]@{ status = $Status; message = $Message }; foreach ($k in $More.Keys) { $o[$k] = $More[$k] }; Set-NodeOutput $o }
$in = Get-NodeInput
$prep = P $in 'prep'; if ($prep -is [string]) { try { $prep = $prep | ConvertFrom-Json } catch { $prep = $null } }
$name = ([string](P $prep 'companyName')).Trim(); $companyId = [string](P $prep 'companyId'); $psaId = [string](P $prep 'psaCompanyId')
$confirm = [bool](P $prep 'confirm'); $skip = [string](P $prep 'skip')
if (-not $name) { Out 'skipped' 'No client name came through, so no Datto RMM site was created.'; return }
if (-not $confirm) { Out 'preview' "Preview: would create the Datto RMM site '$name' (or reuse it if it already exists)."; return }
if ($skip) { Out 'skipped' "No Datto RMM site was created: $skip"; return }
$api = [string](Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'Datto-ApiUrl' -AsPlainText -ErrorAction SilentlyContinue)
$key = [string](Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'Datto-ApiKey' -AsPlainText -ErrorAction SilentlyContinue)
$sec = [string](Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'Datto-ApiSecret' -AsPlainText -ErrorAction SilentlyContinue)
if (-not $sec) { $sec = [string](Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'Datto-ApiSecretKey' -AsPlainText -ErrorAction SilentlyContinue) }
if (-not $api -or -not $key -or -not $sec) { Out 'error' 'Datto-ApiUrl, Datto-ApiKey or Datto-ApiSecret is missing from the runner Key Vault, so no Datto RMM site was created.'; return }
$api = ($api.Trim().TrimEnd('/')) -replace '/api$', ''
try {
    $basic = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('public-client:public'))
    $tok = Invoke-RestMethod -Method Post -Uri "$api/auth/oauth/token" -Headers @{ Authorization = $basic } -ContentType 'application/x-www-form-urlencoded' -Body "grant_type=password&username=$([uri]::EscapeDataString($key.Trim()))&password=$([uri]::EscapeDataString($sec.Trim()))"
    $h = @{ Authorization = "Bearer $($tok.access_token)"; Accept = 'application/json' }
    $sites = @(); $page = "$api/api/v2/account/sites?max=250"
    for ($i = 0; $i -lt 40 -and $page; $i++) { $r = Invoke-RestMethod -Method Get -Uri $page -Headers $h; $sites += @($r.sites); $page = [string]$r.pageDetails.nextPageUrl }
    $ex = $sites | Where-Object { ([string]$_.name).Trim() -ieq $name } | Select-Object -First 1
    if ($ex) { Out 'success' "The Datto RMM site '$name' already exists, so it was reused." @{ action = 'reused'; siteUid = [string]$ex.uid; siteId = [string]$ex.id; siteName = [string]$ex.name; portalUrl = [string]$ex.portalUrl }; return }
    $body = [ordered]@{ name = $name; description = "Created by AutomationAI new client onboarding on $((Get-Date).ToString('yyyy-MM-dd'))."; notes = "CloudRadial company $companyId. PSA company $psaId."; onDemand = $false; splashtopAutoInstall = $false } | ConvertTo-Json
    $new = Invoke-RestMethod -Method Put -Uri "$api/api/v2/site" -Headers $h -ContentType 'application/json' -Body $body
    Out 'success' "Created the Datto RMM site '$name'." @{ action = 'created'; siteUid = [string]$new.uid; siteId = [string]$new.id; siteName = [string]$new.name; portalUrl = [string]$new.portalUrl }
} catch { Out 'error' "Datto RMM did not accept the request: $($_.Exception.Message) $(if ($_.ErrorDetails) { $_.ErrorDetails.Message })" }
