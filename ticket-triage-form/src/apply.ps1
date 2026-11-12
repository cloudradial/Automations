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

# === NODE: Apply the triage ===
$in = Get-NodeInput; $rd = J (P $in 'read'); $ai = [string](P $in 'pick')
if ([string](P $rd 'status') -ne 'ready') { Set-NodeOutput ([ordered]@{ status = 'skipped'; message = [string](P $rd 'message') }); return }
$tid = [int64](P $rd 'ticketId'); $confirm = [bool](P $rd 'confirm'); $pairs = @(J (P $rd 'pairs_json'))
$pick = $null; $m = [regex]::Match($ai, '\{[\s\S]*\}'); if ($m.Success) { try { $pick = $m.Value | ConvertFrom-Json } catch { } }
$wantT = [string](P $pick 'type'); $wantS = [string](P $pick 'subtype'); $why = [string](P $pick 'reason')
$hit = $pairs | Where-Object { $_.type -ieq $wantT -and ([string]$_.subType -ieq $wantS -or (-not $wantS -and -not $_.subType)) } | Select-Object -First 1
if (-not $hit) { $hit = $pairs | Where-Object { $_.type -ieq $wantT } | Select-Object -First 1 }
$ops = @(@{ op = 'replace'; path = 'board'; value = @{ id = [int](P $rd 'boardId') } })
if ([int](P $rd 'priorityId') -gt 0) { $ops += @{ op = 'replace'; path = 'priority'; value = @{ id = [int](P $rd 'priorityId') } } }
if (-not [bool](P $rd 'statusOnBoard') -and [int](P $rd 'defaultStatusId') -gt 0) { $ops += @{ op = 'replace'; path = 'status'; value = @{ id = [int](P $rd 'defaultStatusId') } } }
if (-not [bool](P $rd 'aiType')) { $hit = $null; $why = '' }
if ($hit) { $ops += @{ op = 'replace'; path = 'type'; value = @{ id = [int]$hit.typeId } }; if ([int]$hit.subTypeId -gt 0) { $ops += @{ op = 'replace'; path = 'subType'; value = @{ id = [int]$hit.subTypeId } } } }
$typeText = if ($hit) { "$($hit.type)$(if ($hit.subType) { " > $($hit.subType)" })" } elseif (-not [bool](P $rd 'aiType')) { 'left as is (AI type selection is off in the settings)' } else { 'not set (the AI choice did not match this board)' }
$note = "Auto-triaged by AutomationAI ($(P $rd 'settingsSource')).`n- Board: $(P $rd 'boardName')`n- Priority: $(P $rd 'priorityName')`n- Type: $typeText$(if ($why) { "`n- Why: $why" })"
if (-not $confirm) { Set-NodeOutput ([ordered]@{ status = 'preview'; ticketId = $tid; message = "Preview: ticket $tid would be set to $(P $rd 'boardName'), $(P $rd 'priorityName'), $typeText."; note = $note; aiRaw = $ai }); return }
$warnings = @()
try { $null = CwSend 'PATCH' "/service/tickets/$tid" $ops }
catch { Set-NodeOutput ([ordered]@{ status = 'error'; ticketId = $tid; message = "ConnectWise did not accept the triage for ticket $($tid): $($_.Exception.Message) $(if ($_.ErrorDetails) { $_.ErrorDetails.Message })" }); return }
if ([bool](P $rd 'addNote')) { try { $null = CwSend 'POST' "/service/tickets/$tid/notes" @{ text = $note; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false } } catch { $warnings += "The triage was applied but the internal note was not saved: $($_.Exception.Message)" } }
Set-NodeOutput ([ordered]@{ status = $(if ($warnings.Count) { 'warning' } else { 'success' }); ticketId = $tid; message = "Ticket $tid triaged: $(P $rd 'boardName'), $(P $rd 'priorityName'), $typeText."; note = $note; warnings = $warnings })
