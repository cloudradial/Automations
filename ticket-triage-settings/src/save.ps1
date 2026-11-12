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

# === NODE: Check and save the triage settings ===
# Reads the Ticket Triage Settings form, checks the board and priority exist in ConnectWise, and saves them as the
# TicketTriageSettings token: partner-wide, or for one client when a client name is given.
$in = Get-NodeInput; $trig = J (P $in 'trigger'); if ($null -eq $trig) { $trig = $in }
function Ans { param([string]$key, [string]$label) $v = P $trig $key; if ($null -eq $v -or [string]$v -eq '') { $qs = @(P (P $trig 'Ticket') 'Questions'); foreach ($q in $qs) { if ([string](P $q 'Id') -eq $key -or [string](P $q 'Label') -eq $label) { $v = P $q 'Value' } } }; $s = ([string]$v).Trim(); if ($s -match '^@') { $s = '' }; return $s }
$board = Ans 'triageBoard' 'Board'
$priority = Ans 'triagePriority' 'Priority'
$aiTxt = Ans 'triageAiType' 'Let AI set the Type and Subtype'; $aiType = -not ($aiTxt -match '^(?i)(no|false|0|off)')
$noteTxt = Ans 'triageNote' 'Add an internal note'; $note = -not ($noteTxt -match '^(?i)(no|false|0|off)')
$scope = Ans 'triageCompany' 'Apply to one client only (leave blank for all clients)'
$confirmTxt = [string](P $trig 'confirm'); $confirm = -not ($confirmTxt -match '^(?i)(false|0|no)$')
$problems = @()
if ($board -match '^(\d+)') { try { $b = Invoke-RestMethod -Method Get -Uri "$cwApiUrl/service/boards/$($Matches[1])" -Headers (New-CwHeader) } catch { $b = $null } } elseif ($board) { $b = @(CwGet '/service/boards' "name=""$($board.Replace('"','\"'))""" 5) | Select-Object -First 1 } else { $b = $null }
if (-not $board) { $problems += 'Pick a ConnectWise board.' } elseif (-not $b) { $problems += "There is no ConnectWise board named '$board'." }
$prName = ''; if ($priority) { $pri = @(CwGet '/service/priorities' '' 200); $pr = ($pri | Where-Object { $_.name -ieq $priority -or [string]$_.id -eq ($priority -replace '\D.*$','') } | Select-Object -First 1); if (-not $pr) { $pr = ($pri | Where-Object { $_.name -like "*$priority*" } | Select-Object -First 1) }; if ($pr) { $prName = [string]$pr.name } else { $problems += "There is no ConnectWise priority matching '$priority'. Options: $((@($pri | ForEach-Object { $_.name })) -join ', ')." } }
$crB = (Sec 'CloudRadial-BaseUrl').Trim().TrimEnd('/'); $crPu = (Sec 'CloudRadial-PublicKey').Trim(); $crPr = (Sec 'CloudRadial-PrivateKey').Trim()
$crH = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($crPu):$($crPr)")); Accept = 'application/json' }
$targetId = 0; $targetName = 'all clients'
if ($scope) { $esc = $scope.Replace("'", "''"); $hit = @((Invoke-RestMethod -Method Get -Uri "$crB/v2/odata/company?`$filter=$([uri]::EscapeDataString("name eq '$esc'"))" -Headers $crH).value) | Select-Object -First 1
    if ($hit) { $targetId = [int]$hit.companyId; $targetName = [string]$hit.name } else { $problems += "There is no portal company named '$scope'." } }
$settings = [ordered]@{ board = $(if ($b) { [string]$b.name } else { $board }); priority = $prName; aiType = $aiType; note = $note }
$summary = "Ticket triage settings for $($targetName): board $($settings.board), priority $(if ($prName) { $prName } else { 'Medium or Normal (default)' }), AI Type/Subtype $(if ($aiType) { 'on' } else { 'off' }), internal note $(if ($note) { 'on' } else { 'off' })."
if ($problems.Count) { $msg = "Settings were not saved. $($problems -join ' ')" }
elseif (-not $confirm) { $msg = "Preview: would save $summary" }
else {
    $body = @{ companyId = $targetId; token = 'TicketTriageSettings'; value = ($settings | ConvertTo-Json -Compress); type = 'String' } | ConvertTo-Json
    try { $null = Invoke-RestMethod -Method Post -Uri "$crB/v2/token" -Headers $crH -ContentType 'application/json' -Body $body; $msg = "Saved. $summary" }
    catch { $problems += "CloudRadial did not save the settings: $($_.Exception.Message) $(if ($_.ErrorDetails) { $_.ErrorDetails.Message })"; $msg = "Settings were not saved. $($problems -join ' ')" }
}
# Internal note on the request ticket the form opened
$tid = [string](P (P $trig 'ticket') 'id'); if (-not $tid) { $tid = [string](P (P $trig 'Ticket') 'TicketId') }
$noted = $false
if ($confirm -and $tid -match '^\d+$' -and [int64]$tid -gt 0) { try { $null = CwSend 'POST' "/service/tickets/$tid/notes" @{ text = "Ticket Triage Settings request.`n$msg"; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false }; $noted = $true } catch { } }
Set-NodeOutput ([ordered]@{ status = $(if ($problems.Count) { 'error' } elseif (-not $confirm) { 'preview' } else { 'success' }); message = $msg; settings = $settings; companyId = $targetId; ticketNoted = $noted })
