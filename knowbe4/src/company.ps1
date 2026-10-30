# === NODE: Pick the CloudRadial company ===
# The client this run covers. Each copy of the workflow covers one KnowBe4 account and one CloudRadial company.
# The company id comes from the run input (companyId), then the CloudRadial-CompanyId secret. The step checks
# that the company exists before anything is read from KnowBe4, so a wrong id stops the run early.
$ErrorActionPreference = 'Stop'
function Get-KbProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Stop-Kb { param([string]$Msg) Set-NodeOutput @{ status = 'error'; message = $Msg }; throw $Msg }

$trigger = Get-NodeInput -Name 'trigger'
if ($trigger -is [string]) { $t = $trigger.Trim(); if ($t.StartsWith('{')) { try { $trigger = $t | ConvertFrom-Json } catch { $trigger = $null } } else { $trigger = $null } }
$raw = ([string](Get-KbProp $trigger 'companyId')).Trim()
$from = 'the run input'
if (-not $raw -or $raw.StartsWith('@') -or $raw.StartsWith('{{')) { $raw = ([string](Get-CrSecret 'CloudRadial-CompanyId')).Trim(); $from = 'the CloudRadial-CompanyId secret' }
if (-not $raw) { Stop-Kb 'No CloudRadial company was given. Start the run with a companyId, or set the CloudRadial-CompanyId secret.' }
if ($raw -notmatch '^\d+$' -or $raw -eq '0') { Stop-Kb "The CloudRadial company id from $from isn't a number ('$raw')." }

try { $null = Connect-Cr } catch { Stop-Kb $_.Exception.Message }
$co = @(Get-CrProp (Invoke-CrApi -Path "/v2/odata/company?`$filter=$([uri]::EscapeDataString("companyId eq $raw"))&`$select=companyId,name") 'value') | Select-Object -First 1
$name = [string](Get-CrProp $co 'name')
if (-not $name) { Stop-Kb "CloudRadial has no company $raw (from $from)." }

Set-NodeOutput @{ status = 'success'; message = "Covering CloudRadial company $raw ($name)."; companyId = [int]$raw; companyName = $name }
