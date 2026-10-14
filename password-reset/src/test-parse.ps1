# Strict-mode harness for Password Reset's first step (Parse & Validate): who submitted, the target, the tenant and
# the ticket, for each shape the request arrives in. Runs the step exactly as it is in password-reset.yml, through
# & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with Get-NodeInput and Set-NodeOutput mocked.
# Placeholder data only (Contoso, Fabrikam, example.com).
# Usage: pwsh -NoProfile -File password-reset/src/test-parse.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$node = (Get-Command node -ErrorAction Stop).Source
$yml = Join-Path $PSScriptRoot '..\password-reset.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));process.stdout.write(d.definition.activities.find(a=>a.id==='node-1').properties.script)"
$Step = (& $node -e $js $yml) -join "`n"

$global:NodeIn = $null; $global:NodeOut = $null
function Get-NodeInput { return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Invoke-Parse { param($Body)
    $global:NodeIn = [pscustomobject]@{ trigger = ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json) }; $global:NodeOut = $null; $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Step)) } catch { $err = [string]$_.Exception.Message }
    return @{ out = $(if ($null -ne $global:NodeOut) { $global:NodeOut | ConvertTo-Json -Depth 6 | ConvertFrom-Json } else { $null }); error = $err }
}
$fail = 0; $pass = 0
function Check { param($Name, [bool]$Ok, $Detail) if ($Ok) { $script:pass++; Write-Host "PASS $Name" } else { $script:fail++; Write-Host "FAIL $Name :: $Detail" -ForegroundColor Red } }

# The prod webhook body (the form's Webhook activity with tokens mapped by hand).
$r = Invoke-Parse ([ordered]@{ userPrincipalName = 'megan.bowen@contoso.com'; submittedByUpn = 'megan.bowen@contoso.com'; userOfficeId = '00000000-0000-0000-0000-000000000001'; companyTenantId = '00000000-0000-0000-0000-000000000002'; ticketId = '1001'; revokeSessions = 'false' })
Check 'webhook body: fields as sent' ($r.out.status -eq 'ok' -and $r.out.upn -eq 'megan.bowen@contoso.com' -and $r.out.submittedByUpn -eq 'megan.bowen@contoso.com' -and $r.out.ticketId -eq '1001' -and $r.out.companyTenantId -eq '00000000-0000-0000-0000-000000000002' -and $r.out.revokeSessions -eq $false) ($r.out | ConvertTo-Json -Compress)

# The older CloudRadial shape: Ticket.Questions, Company, and the submitter on the ticket.
$r = Invoke-Parse ([ordered]@{ Ticket = [ordered]@{ TicketId = 2002; ContactEmail = 'megan.bowen@contoso.com'; Questions = @([ordered]@{ Id = 'userPrincipalName'; Value = 'megan.bowen@contoso.com' }) }; Company = [ordered]@{ CompanyTenantId = '00000000-0000-0000-0000-000000000002' } })
Check 'Ticket.Questions shape: unchanged' ($r.out.status -eq 'ok' -and $r.out.ticketId -eq '2002' -and $r.out.submittedByUpn -eq 'megan.bowen@contoso.com' -and $r.out.companyTenantId -eq '00000000-0000-0000-0000-000000000002') ($r.out | ConvertTo-Json -Compress)

# A CloudRadial Action (the shape seen on DV, 2026-10-14): answers at the top level, the portal's objects beside them.
function New-TPortal { param([hashtable]$Answers = @{}, $UserEmail = 'megan.bowen@contoso.com')
    $b = [ordered]@{ userPrincipalName = 'megan.bowen@contoso.com'; ccEmail = 'alex.wilber@contoso.com' }
    foreach ($k in $Answers.Keys) { $b[$k] = $Answers[$k] }
    $b['ticket'] = [ordered]@{ id = 104901; reference = '104901'; subject = 'Reset Password'; description = ''; estimatedTime = 0; checklist = @() }
    $b['company'] = [ordered]@{ id = 7; name = 'Contoso'; psaId = 42; psaIdentifier = 'ConnectWise'; tenantId = '00000000-0000-0000-0000-000000000002' }
    $b['user'] = [ordered]@{ id = 'u-1'; name = 'Megan Bowen'; email = $UserEmail; psaId = 501; psaSiteId = 2 }
    return $b
}
$r = Invoke-Parse (New-TPortal)
Check 'Action: submitter from user.email, ticket from ticket.id, tenant from company.tenantId' ($r.out.status -eq 'ok' -and $r.out.upn -eq 'megan.bowen@contoso.com' -and $r.out.submittedByUpn -eq 'megan.bowen@contoso.com' -and $r.out.ticketId -eq '104901' -and $r.out.companyTenantId -eq '00000000-0000-0000-0000-000000000002') ($r.out | ConvertTo-Json -Compress)
$r = Invoke-Parse (New-TPortal @{ submittedByUpn = 'alex.wilber@contoso.com'; userOfficeId = '00000000-0000-0000-0000-000000000009'; companyTenantId = '00000000-0000-0000-0000-000000000003'; ticketId = '1'; revokeSessions = 'false' })
Check 'Action: submitter, office id, tenant, ticket and revokeSessions answers are ignored' ($r.out.submittedByUpn -eq 'megan.bowen@contoso.com' -and $r.out.userOfficeId -eq '' -and $r.out.companyTenantId -eq '00000000-0000-0000-0000-000000000002' -and $r.out.ticketId -eq '104901' -and $r.out.revokeSessions -eq $true) ($r.out | ConvertTo-Json -Compress)
$r = Invoke-Parse (New-TPortal @{ submittedByUpn = 'megan.bowen@contoso.com' } -UserEmail $null)
Check 'Action: no user.email -> no submitter, even if an answer names one (the ownership gate then refuses)' ($r.out.status -eq 'ok' -and $r.out.submittedByUpn -eq '') ($r.out | ConvertTo-Json -Compress)
$r = Invoke-Parse (New-TPortal @{ userPrincipalName = $null })
Check 'Action: no target -> incomplete, ticket kept for the note' ($r.out.status -eq 'incomplete' -and $r.out.ticket_id -eq '104901' -and $r.error -like '*userPrincipalName*') "$($r.out | ConvertTo-Json -Compress) / $($r.error)"

Write-Host "$pass passed, $fail failed"
if ($fail) { exit 1 }
