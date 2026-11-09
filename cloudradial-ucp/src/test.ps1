# Strict-mode harness for Set Up a New Company's Read the setup step, run the way the runner runs it
# (child scope via [scriptblock]::Create, never dot-sourced). Placeholder data only.
# Usage: pwsh -NoProfile -File cloudradial-ucp/src/test.ps1
param([string]$ScriptPath = (Join-Path $PSScriptRoot 'read-setup.ps1'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Script = Get-Content -Raw $ScriptPath
$Node = @{ In = $null; Out = $null }
function Get-NodeInput { return $Node.In }
function Set-NodeOutput { param($o) $Node.Out = $o }
$tally = @{ pass = 0; fail = 0 }
function Check { param($n, [bool]$ok, $d = '') if ($ok) { $tally.pass++; Write-Host "PASS $n" } else { $tally.fail++; Write-Host "FAIL $n :: $d" -ForegroundColor Red } }
function Run { param($in) $Node.In = $in; $Node.Out = $null; try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Script)); return '' } catch { return [string]$_.Exception.Message } }

$full = '{"companyName":"Contoso Ltd","domain":"Contoso.com","companyGroup":"Managed","accountManager":"alex@examplemsp.com","psaKey":"123","users":[{"firstName":"Pat","lastName":"Lee","email":"Pat.Lee@contoso.com"}],"tokens":{"@SupportPhone":"555-0100"},"requestForms":[{"subject":"New laptop","category":"Hardware"}],"menuTiles":[{"name":"Support","url":"https://support.examplemsp.com","category":"Help"}]}' | ConvertFrom-Json
$e = Run @{ trigger = $full }
$o = $Node.Out
Check 'full: ok' ($e -eq '' -and $o.status -eq 'ok') $e
Check 'full: normalised plan' ($o.plan.domain -eq 'contoso.com' -and $o.plan.company.psaKey -eq 123 -and $o.plan.users[0].email -eq 'pat.lee@contoso.com' -and $o.plan.tokens[0].token -eq 'SupportPhone') ($o.plan | ConvertTo-Json -Depth 6 -Compress)
Check 'full: request carries the plan JSON' ($o.request -match 'SETTING UP A NEW COMPANY' -and $o.request -match '"name":"Contoso Ltd"') $o.request
Check 'full: message lists what will be set up' ($o.message -match 'default domain contoso.com' -and $o.message -match '1 users') $o.message

$e = Run @{ trigger = @{ companyName = 'Contoso Ltd' } }
Check 'name only: ok, empty lists' ($e -eq '' -and $Node.Out.status -eq 'ok' -and $Node.Out.counts.users -eq 0 -and -not $Node.Out.plan.company.Contains('psaKey')) $e

$e = Run '{"companyName":"Contoso Ltd","tokens":[{"token":"SupportPhone","value":"555-0100"}]}'
Check 'string input, token list form' ($e -eq '' -and $Node.Out.plan.tokens[0].value -eq '555-0100') $e

$e = Run $null
Check 'no input: rejected' ($e -match 'No run input' -and $Node.Out.status -eq 'rejected') $e
$e = Run @{ trigger = @{ domain = 'contoso.com' } }
Check 'no name: rejected' ($e -match 'companyName is required') $e
$e = Run @{ trigger = @{ companyName = 'Contoso'; domain = 'not a domain'; psaKey = 'abc'; users = @(@{ firstName = 'Pat'; lastName = 'Lee'; email = 'nope' }) } }
Check 'bad domain, psaKey and email: all named at once' ($e -match 'domain' -and $e -match 'psaKey' -and $e -match 'valid email') $e
$many = @(1..6 | ForEach-Object { @{ firstName = "User$_"; lastName = 'Test'; email = "user$_@contoso.com" } })
$e = Run @{ trigger = @{ companyName = 'Contoso'; users = $many } }
Check 'too many users: rejected with the bulk workflow named' ($e -match '6 users is more than the 5' -and $e -match 'Onboard Many Portal Users') $e
$e = Run @{ trigger = @{ companyName = 'Contoso'; menuTiles = @(@{ name = 'X'; url = 'ftp://x'; category = 'Help' }) } }
Check 'bad menu url: rejected' ($e -match 'menu tile') $e

# An existing company (company_id): add to it, never create or change it.
$e = Run @{ trigger = @{ company_id = 23; domain = 'contoso.com'; users = @(@{ firstName = 'Pat'; lastName = 'Lee'; email = 'pat.lee@contoso.com' }) } }
$o = $Node.Out
Check 'company_id: ok without a name' ($e -eq '' -and $o.status -eq 'ok' -and $o.companyId -eq 23 -and $o.plan.existingCompanyId -eq 23) $e
Check 'company_id: request says add to the existing company and never change it' ($o.request -match 'existing CloudRadial company 23' -and $o.request -match 'never create or change the company' -and $o.request -match '"existingCompanyId":23') $o.request
Check 'company_id: message lists only what will be added' ($o.message -match '^Ready to add to existing company 23: default domain contoso.com, 1 users\.$') $o.message
$e = Run '{"companyId":"23","companyName":"Contoso Ltd","menuTiles":[{"name":"Support","url":"https://support.examplemsp.com","category":"Help"}]}'
Check 'companyId alias as a string, with the name for the message' ($e -eq '' -and $Node.Out.companyId -eq 23 -and $Node.Out.message -match "existing company 23 \('Contoso Ltd'\)") $e
$e = Run @{ trigger = @{ companyName = 'Contoso Ltd'; domain = 'contoso.com' } }
Check 'no company_id: still a new company, existingCompanyId 0' ($e -eq '' -and $Node.Out.plan.existingCompanyId -eq 0 -and $Node.Out.request -match '^Set up a new CloudRadial company') $e
$e = Run @{ trigger = @{ company_id = 23; accountManager = 'alex@examplemsp.com'; psaKey = '5'; domain = 'contoso.com' } }
Check 'company_id with company fields: rejected, names them' ($e -match 'accountManager, psaKey only apply when this run creates the company' -and $Node.Out.status -eq 'rejected') $e
$e = Run @{ trigger = @{ company_id = 'abc'; domain = 'contoso.com' } }
Check 'company_id not a number: rejected' ($e -match "company_id must be a CloudRadial company number" -and $e -notmatch 'companyName is required') $e
$e = Run @{ trigger = @{ company_id = 0; domain = 'contoso.com' } }
Check 'company_id 0: rejected' ($e -match 'company_id must be') $e
$e = Run @{ trigger = @{ company_id = 23 } }
Check 'company_id with nothing to add: rejected' ($e -match 'Nothing to add to company 23' -and $Node.Out.status -eq 'rejected') $e

Write-Host "$($tally.pass) passed, $($tally.fail) failed"; if ($tally.fail) { exit 1 }
