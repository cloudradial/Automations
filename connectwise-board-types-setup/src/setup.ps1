$ErrorActionPreference = 'Stop'
Set-StrictMode -Off
function P { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function J { param($x) if ($x -is [string]) { try { return ($x | ConvertFrom-Json) } catch { return $null } }; return $x }
function Sec { param([string]$n) [string](Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $n -AsPlainText -ErrorAction SilentlyContinue) }
$cwApiUrl = (Sec 'CW-ApiUrl').Trim().TrimEnd('/'); $cwCompanyId = (Sec 'CW-CompanyID').Trim(); $cwPublicKey = (Sec 'CW-PublicKey').Trim(); $cwPrivateKey = (Sec 'CW-PrivateKey').Trim(); $cwClientId = (Sec 'CW-ClientId').Trim()
if (-not $cwApiUrl -or -not $cwPublicKey -or -not $cwPrivateKey) { throw 'CW-ApiUrl, CW-PublicKey or CW-PrivateKey is missing for this step.' }
function New-CwHeader { $pair = "{0}+{1}:{2}" -f $cwCompanyId, $cwPublicKey, $cwPrivateKey; @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair)); clientId = $cwClientId; Accept = 'application/json'; 'Content-Type' = 'application/json' } }
function CwGet { param([string]$Path, [string]$Cond = '', [int]$Size = 1000) $q = @("pageSize=$Size"); if ($Cond) { $q += 'conditions=' + [uri]::EscapeDataString($Cond) }; $r = Invoke-RestMethod -Method Get -Uri "$cwApiUrl$($Path)?$($q -join '&')" -Headers (New-CwHeader); @($r | ForEach-Object { $_ }) }

function CwSend { param([string]$Method, [string]$Path, $Body) $json = if ($Body -is [string]) { $Body } else { ConvertTo-Json -InputObject $Body -Depth 6 }; $r = $null; try { $r = Invoke-WebRequest -Method $Method -Uri "$cwApiUrl$Path" -Headers (New-CwHeader) -ContentType 'application/json' -Body $json -MaximumRedirection 0 -SkipHttpErrorCheck } catch { if ($_.Exception.Message -match '(?i)insecure redirect|current state of the object') { return [pscustomobject]@{ id = $null; savedWithRedirect = $true } }; throw }; $code = [int]$r.StatusCode; if ($code -ge 400) { throw "ConnectWise HTTP $($code): $(([string]$r.Content).Substring(0, [math]::Min(300, ([string]$r.Content).Length)))" }; $obj = $null; if ([string]$r.Content) { try { $obj = [string]$r.Content | ConvertFrom-Json } catch { } }; if (-not $obj -or -not $obj.id) { $loc = [string]$r.Headers['Location']; if ($loc -match '/(\d+)/?$') { $obj = [pscustomobject]@{ id = [int]$Matches[1] } } }; return $obj }

# ConnectWise's automation host forwards requests and redirects writes to plain http; use the API host ConnectWise reports.
try { $rawB = Invoke-WebRequest -Method Get -Uri "$cwApiUrl/service/boards?pageSize=1" -Headers (New-CwHeader); $mB = [regex]::Match([string]$rawB.Content, 'https://[^/"]+/[^/"]+/apis/3\.0'); if ($mB.Success) { $cwApiUrl = $mB.Value } } catch { }

# === NODE: Set up board types and subtypes ===
# Adds the Type > Subtype pairs a service desk uses to a ConnectWise board. Reuses what exists; never renames or deletes.
$in = Get-NodeInput; $trig = J (P $in 'trigger'); if ($null -eq $trig) { $trig = $in }
$boardName = [string](P $trig 'board'); if (-not $boardName) { throw 'Pass board: the name of the ConnectWise board to set up, for example {"board": "Service Desk"}.' }
$plan = [ordered]@{
  'Account & Access' = @('Password Reset', 'MFA', 'Locked Out', 'Permissions')
  'Email' = @('Outlook', 'Mailbox Access', 'Spam or Phishing', 'Shared Mailbox')
  'Hardware' = @('Computer or Laptop', 'Monitor or Peripheral', 'New Hardware Request')
  'Network' = @('Internet Down', 'Wi-Fi', 'VPN or Remote Access', 'Slow Performance')
  'Phone' = @('Desk Phone', 'Voicemail', 'Teams Calling')
  'Printer' = @('Replacement', 'Toner/Ink', 'Not Printing', 'Scanning')
  'Security' = @('Suspicious Email', 'Security Alert', 'Lost or Stolen Device')
  'Software' = @('Installation', 'Error or Crash', 'Licensing', 'Microsoft 365 Apps')
  'User Management' = @('New User', 'User Change', 'User Offboarding')
  'General' = @('Question', 'Training', 'Other')
}
$b = @(CwGet '/service/boards' "name=""$($boardName.Replace('"','\"'))""" 5) | Select-Object -First 1
if (-not $b) { throw "There is no ConnectWise board named '$boardName'." }
$bid = [int]$b.id; $log = @(); $err = @(); $want = @{}
$types = @{}; foreach ($t in @(CwGet "/service/boards/$bid/types" '' 1000)) { $types[([string]$t.name).ToLower()] = [int]$t.id }
$subs = @{}; foreach ($s in @(CwGet "/service/boards/$bid/subtypes" '' 1000)) { $subs[([string]$s.name).ToLower()] = [int]$s.id }
$assoc = @{}; try { foreach ($a in @(CwGet "/service/boards/$bid/typeSubTypeItemAssociations" '' 1000)) { if ($a.type -and $a.subType) { $assoc["$($a.type.id)|$($a.subType.id)"] = $true } } } catch { $err += "Could not read existing pairs: $($_.Exception.Message)" }
$post = { param($path, $body) CwSend 'POST' $path $body }
foreach ($tn in $plan.Keys) {
  $tid = $types[$tn.ToLower()]
  if (-not $tid) { try { $r = & $post "/service/boards/$bid/types" @{ name = $tn; category = 'Reactive' }; $tid = [int]$r.id; $types[$tn.ToLower()] = $tid; $log += "Type created: $tn" } catch { $err += "Type $($tn): $($_.Exception.Message) $(if ($_.ErrorDetails) { $_.ErrorDetails.Message })"; continue } }
  foreach ($sn in $plan[$tn]) {
    $sid = $subs[$sn.ToLower()]
    if (-not $sid) { try { $r = & $post "/service/boards/$bid/subtypes" @{ name = $sn }; $sid = [int]$r.id; $subs[$sn.ToLower()] = $sid; $log += "Subtype created: $sn" } catch { $err += "Subtype $($sn): $($_.Exception.Message) $(if ($_.ErrorDetails) { $_.ErrorDetails.Message })"; continue } }
    if (-not $want.ContainsKey($sid)) { $want[$sid] = New-Object System.Collections.Generic.HashSet[int] }; $null = $want[$sid].Add($tid)
  }
}
foreach ($sid in $want.Keys) {
  $cur = @(); try { $cur = @((Invoke-RestMethod -Method Get -Uri "$cwApiUrl/service/boards/$bid/subtypes/$sid" -Headers (New-CwHeader)).typeAssociationIds) } catch { }
  $all = New-Object System.Collections.Generic.HashSet[int]; foreach ($x in $cur) { if ($x) { $null = $all.Add([int]$x) } }; $before = $all.Count; foreach ($x in $want[$sid]) { $null = $all.Add([int]$x) }
  if ($all.Count -ne $before) { try { $null = CwSend 'PATCH' "/service/boards/$bid/subtypes/$sid" @(@{ op = 'replace'; path = 'typeAssociationIds'; value = @($all) }); $log += "Linked subtype $sid to types $(@($all) -join ',')" } catch { $err += "Link subtype $($sid): $($_.Exception.Message)" } }
}
$tn = @{}; foreach ($t in @(CwGet "/service/boards/$bid/types" '' 1000)) { $tn[[int]$t.id] = [string]$t.name }
$final = @(foreach ($st in @(CwGet "/service/boards/$bid/subtypes" '' 1000)) { foreach ($x in @($st.typeAssociationIds)) { if ($x -and $tn.ContainsKey([int]$x)) { "$($tn[[int]$x]) > $($st.name)" } } }) | Sort-Object -Unique
Set-NodeOutput ([ordered]@{ status = $(if ($err.Count) { 'warning' } else { 'success' }); board = [string]$b.name; changes = $log.Count; pairs = $final.Count; log = $log; errors = $err; boardPairs = $final })
