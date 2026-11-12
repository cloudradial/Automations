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

# === NODE: Read the ticket and board ===

# The portal form sends the ticket it opened; a manual run can pass ticketId (and confirm false for a preview).
$in = Get-NodeInput; $trig = J (P $in 'trigger'); if ($null -eq $trig) { $trig = $in }
# ---- settings: the client's TicketTriageSettings token, else the partner-wide one, else the defaults ----
$cfg = [ordered]@{ board = ''; priority = ''; aiType = $true; note = $true; source = 'defaults' }
try {
    $crB = (Sec 'CloudRadial-BaseUrl').Trim().TrimEnd('/'); $crPu = (Sec 'CloudRadial-PublicKey').Trim(); $crPr = (Sec 'CloudRadial-PrivateKey').Trim()
    $crH = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($crPu):$($crPr)")); Accept = 'application/json' }
    $coId = [string](P (P $trig 'company') 'id'); if (-not $coId) { $coId = [string](P (P $trig 'Company') 'CompanyId') }
    foreach ($cid in @($(if ($coId -match '^\d+$') { $coId }), '0')) { if (-not $cid) { continue }
        $tk = @((Invoke-RestMethod -Method Get -Uri "$crB/v2/odata/token?`$filter=$([uri]::EscapeDataString("name eq 'TicketTriageSettings' and companyId eq $cid"))" -Headers $crH).value) | Select-Object -First 1
        if ($tk -and [string]$tk.value) { $j = [string]$tk.value | ConvertFrom-Json; foreach ($k in @('board', 'priority', 'aiType', 'note')) { $pv = P $j $k; if ($null -ne $pv -and [string]$pv -ne '') { $cfg[$k] = $pv } }; $cfg.source = $(if ($cid -eq '0') { 'partner settings' } else { 'client settings' }); break } }
} catch { $cfg.source = "defaults (settings could not be read: $($_.Exception.Message))" }
$boardName = [string](P $trig 'board'); if (-not $boardName) { $boardName = [string]$cfg.board }
$tid = [string](P (P $trig 'ticket') 'id'); if (-not $tid) { $tid = [string](P (P $trig 'Ticket') 'TicketId') }; if (-not $tid) { $tid = [string](P $trig 'ticketId') }
$confirmTxt = [string](P $trig 'confirm'); $confirm = -not ($confirmTxt -match '^(?i)(false|0|no)$')
$formName = [string](P (P $trig 'ticket') 'subject'); if (-not $formName) { $formName = [string](P $trig 'subject') }
if (-not ($tid -match '^\d+$') -or [int64]$tid -le 0) { Set-NodeOutput ([ordered]@{ status = 'skipped'; message = 'No ticket came with this run, so nothing was triaged.'; ticketId = 0 }); return }
try { $t = Invoke-RestMethod -Method Get -Uri "$cwApiUrl/service/tickets/$tid" -Headers (New-CwHeader) } catch { throw "ConnectWise did not return ticket $($tid): $($_.Exception.Message) $(if ($_.ErrorDetails) { $_.ErrorDetails.Message })" }
# No board in the settings or the run: keep the ticket on the board it was opened on.
if (-not $boardName) { $boardName = [string]$t.board.name }
$desc = ''; try { $n = @(CwGet "/service/tickets/$tid/notes" 'detailDescriptionFlag=true' 5); if ($n.Count) { $desc = [string]$n[0].text } } catch { }
if (-not $desc) { try { $n = @(CwGet "/service/tickets/$tid/notes" '' 3); if ($n.Count) { $desc = [string]$n[0].text } } catch { } }
if ($desc.Length -gt 2500) { $desc = $desc.Substring(0, 2500) }
$b = @(CwGet '/service/boards' "name=""$($boardName.Replace('"','\"'))""" 5) | Select-Object -First 1
if (-not $b) { throw "There is no ConnectWise board named '$boardName'." }
$bid = [int]$b.id
$pairs = @(); try { $pairs = @(CwGet "/service/boards/$bid/typeSubTypeItemAssociations" '' 1000 | ForEach-Object { [ordered]@{ type = [string]$_.type.name; typeId = [int]$_.type.id; subType = [string]$(if ($_.subType) { $_.subType.name } else { '' }); subTypeId = [int]$(if ($_.subType) { $_.subType.id } else { 0 }) } }) } catch { }
try { $tNames = @{}; foreach ($t in @(CwGet "/service/boards/$bid/types" 'inactiveFlag=false' 1000)) { $tNames[[int]$t.id] = [string]$t.name }; foreach ($st in @(CwGet "/service/boards/$bid/subtypes" 'inactiveFlag=false' 1000)) { foreach ($x in @($st.typeAssociationIds)) { if ($x -and $tNames.ContainsKey([int]$x)) { $pairs += [ordered]@{ type = $tNames[[int]$x]; typeId = [int]$x; subType = [string]$st.name; subTypeId = [int]$st.id } } } } } catch { }
$pairs = @($pairs | Sort-Object { "$($_.type)|$($_.subType)" } -Unique)
if (-not $pairs.Count) { $pairs = @(CwGet "/service/boards/$bid/types" 'inactiveFlag=false' 1000 | ForEach-Object { [ordered]@{ type = [string]$_.name; typeId = [int]$_.id; subType = ''; subTypeId = 0 } }) }
$pri = @(CwGet '/service/priorities' '' 200); $pr = $null; if ([string]$cfg.priority) { $pr = ($pri | Where-Object { $_.name -ieq [string]$cfg.priority } | Select-Object -First 1); if (-not $pr) { $pr = ($pri | Where-Object { $_.name -like "*$($cfg.priority)*" } | Select-Object -First 1) } }; if (-not $pr) { $pr = ($pri | Where-Object { $_.name -match '(?i)medium' } | Select-Object -First 1) }; if (-not $pr) { $pr = ($pri | Where-Object { $_.name -match '(?i)normal' } | Select-Object -First 1) }
$statuses = @(CwGet "/service/boards/$bid/statuses" 'inactive=false' 200); $defStatus = ($statuses | Where-Object { $_.defaultFlag } | Select-Object -First 1); if (-not $defStatus) { $defStatus = $statuses | Select-Object -First 1 }
$options = ($pairs | ForEach-Object { if ($_.subType) { "$($_.type) > $($_.subType)" } else { $_.type } }) -join "`n"
$facts = [ordered]@{ form = $formName; summary = [string]$t.summary; description = $desc; company = [string]$t.company.name; contact = [string]$t.contactName }
Set-NodeOutput ([ordered]@{ status = 'ready'; ticketId = [int64]$tid; confirm = $confirm; settingsSource = [string]$cfg.source; aiType = [bool]([string]$cfg.aiType -notmatch '^(?i)(false|no|0)$'); addNote = [bool]([string]$cfg.note -notmatch '^(?i)(false|no|0)$'); boardId = $bid; boardName = [string]$b.name; currentBoard = [string]$t.board.name; currentStatus = [string]$t.status.name
    priorityId = [int]$(if ($pr) { $pr.id } else { 0 }); priorityName = [string]$(if ($pr) { $pr.name } else { '' }); defaultStatusId = [int]$(if ($defStatus) { $defStatus.id } else { 0 }); defaultStatusName = [string]$(if ($defStatus) { $defStatus.name } else { '' })
    statusOnBoard = [bool]($statuses | Where-Object { $_.name -eq $t.status.name }); options = $options; pairs_json = ($pairs | ConvertTo-Json -Compress -Depth 4); facts_json = ($facts | ConvertTo-Json -Compress) })
