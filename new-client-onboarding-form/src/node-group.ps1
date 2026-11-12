# === NODE: Add to the portal group ===
# Adds the new company to the portal's company group (default 'All'), which carries the Sample Problem Reports,
# Sample Service Catalog and Sample Service Catalog Admin packages. Secrets: CloudRadial-BaseUrl, -PublicKey, -PrivateKey.
$ErrorActionPreference = 'Stop'
function P { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Out { param([string]$Status, [string]$Message, [hashtable]$More = @{}) $o = [ordered]@{ status = $Status; message = $Message }; foreach ($k in $More.Keys) { $o[$k] = $More[$k] }; Set-NodeOutput $o }
$in = Get-NodeInput
$prep = P $in 'prep'; if ($prep -is [string]) { try { $prep = $prep | ConvertFrom-Json } catch { $prep = $null } }
$groupName = [string](P $in 'groupName'); if (-not $groupName) { $groupName = 'All' }
$name = [string](P $prep 'companyName'); $companyId = 0; [int]::TryParse([string](P $prep 'companyId'), [ref]$companyId) | Out-Null
$confirm = [bool](P $prep 'confirm'); $skip = [string](P $prep 'skip')
if (-not $confirm) { Out 'preview' "Preview: would add $(if ($name) { $name } else { 'the new company' }) to the '$groupName' company group."; return }
if ($skip -or $companyId -le 0) { Out 'skipped' "The company was not added to '$groupName': $(if ($skip) { $skip } else { 'no CloudRadial company id came through.' })"; return }
$base = ([string](Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'CloudRadial-BaseUrl' -AsPlainText -ErrorAction SilentlyContinue)).Trim().TrimEnd('/')
$pub = [string](Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'CloudRadial-PublicKey' -AsPlainText -ErrorAction SilentlyContinue)
$priv = [string](Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'CloudRadial-PrivateKey' -AsPlainText -ErrorAction SilentlyContinue)
if (-not $base -or -not $pub -or -not $priv) { Out 'error' 'CloudRadial-BaseUrl, -PublicKey or -PrivateKey is missing for this step.'; return }
$h = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($pub.Trim()):$($priv.Trim())")); Accept = 'application/json' }
try {
    $groups = @((Invoke-RestMethod -Method Get -Uri "$base/v2/odata/companygroup" -Headers $h).value)
    $g = $groups | Where-Object { ([string]$_.group).Trim() -ieq $groupName } | Select-Object -First 1
    if (-not $g) { Out 'error' "There is no company group named '$groupName' in the portal."; return }
    $gid = [int]$g.companyGroupId
    $mem = @((Invoke-RestMethod -Method Get -Uri "$base/v2/odata/companygroupcompany?`$filter=$([uri]::EscapeDataString("companyGroupId eq $gid and companyId eq $companyId"))" -Headers $h).value)
    if ($mem.Count) { Out 'success' "$name is already in the '$groupName' company group." @{ action = 'already'; companyGroupId = $gid }; return }
    $null = Invoke-RestMethod -Method Post -Uri "$base/v2/companygroupcompany" -Headers $h -ContentType 'application/json' -Body (@{ companyGroupId = $gid; companyId = $companyId } | ConvertTo-Json)
    Out 'success' "Added $name to the '$groupName' company group, so it gets the Sample Problem Reports, Sample Service Catalog and Sample Service Catalog Admin packages." @{ action = 'added'; companyGroupId = $gid }
} catch { Out 'error' "The company was not added to '$groupName': $($_.Exception.Message) $(if ($_.ErrorDetails) { $_.ErrorDetails.Message })" }
