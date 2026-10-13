# Strict-mode harness for the agent workflow's own PowerShell steps: Read the request (every input shape, the
# stock form's Field IDs, the confirm gate), the two hand-off steps, and the hand-off lines in Note the ticket.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$dir = $(if ($env:NUO_NODE_DIR) { $env:NUO_NODE_DIR } else { $PSScriptRoot })
$env:RUNNER_KV_NAME = 'kv-test'

function Get-NodeInput { return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText)
    if ($global:Secrets.Contains($Name)) { return $global:Secrets[$Name] }; return $null }
function Invoke-RestMethod { param($Method, $Uri, $Headers, $Body, $ContentType, $Form)
    $global:Calls += [pscustomobject]@{ Method = [string]$Method; Uri = [string]$Uri; Body = $(if ($Body -is [string]) { $Body } else { '' }); Headers = $Headers }
    if ($Uri -like '*fail*') { throw 'Response status code does not indicate success: 401 (Unauthorized).' }
    if ($Uri -like 'https://automationai.example.com/api/hooks/*') { return [pscustomobject]@{ runId = "run-$(@($global:Calls).Count)" } }
    return [pscustomobject]@{ id = 1 }
}
function RoundTrip { param($o) return ($o | ConvertTo-Json -Depth 20 | ConvertFrom-Json) }
function Run { param([string]$File, $In) $global:Calls = @(); $global:NodeIn = $(if ($In -is [string]) { $In } else { RoundTrip $In }); & ([scriptblock]::Create((Get-Content -Raw (Join-Path $dir $File)))); return (RoundTrip $global:NodeOut) }
$fail = 0
function Check { param($Name, [bool]$Ok, $Detail) if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name :: $Detail"; $script:fail++ } }
function Show { return (@($global:Calls | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join ' ; ') }

# The CloudRadial Action shape, with the stock form's Field IDs (some cut at 40 characters, as the portal does).
$action = [ordered]@{
    Ticket = [ordered]@{ TicketId = 104900; Subject = 'Add a New User'; Questions = @(
        [ordered]@{ Id = 'firstName'; Value = 'Sam' }, [ordered]@{ Id = 'lastName'; Value = 'Starter' }
        [ordered]@{ Id = 'department'; Value = 'Sales' }, [ordered]@{ Id = 'jobTitle'; Value = 'Account Executive' }
        [ordered]@{ Id = 'startDate'; Value = '2026-11-02' }
        [ordered]@{ Id = 'modelTheNewUsersAccountAccessFrom'; Value = 'alex@contoso.com' }
        [ordered]@{ Id = 'companyFileAccess'; Value = @('Sales Team', 'All Staff') }
        [ordered]@{ Id = 'doesTheUserRequireAnEmailAccount'; Answer = 'Yes' }
        [ordered]@{ Id = 'mailDistributionGroups'; Value = 'sales@contoso.com' }
        [ordered]@{ Id = 'willTheNewUserBeUsingAnExistingOrNewComp'; Value = 'New' }
        [ordered]@{ Id = 'whatTypeOfNewComputerDoesTheNewUserRequi'; Value = 'Laptop' }
        [ordered]@{ Id = 'isVpnRemoteAccessRequired'; Value = 'No' }
        [ordered]@{ Id = 'doesThisUserNeedADeskPhone'; Value = '@doesThisUserNeedADeskPhone' }
        # A typed answer trying to set the requester: must be ignored.
        [ordered]@{ Id = 'requestedBy'; Value = 'attacker@example.com' }
        [ordered]@{ Id = 'confirm'; Value = 'true' }
    ) }
    User = [ordered]@{ Email = 'pat.manager@contoso.com'; FullName = 'Pat Manager'; OfficeId = 'aad-1'; IsAdmin = $false }
    Company = [ordered]@{ CompanyName = 'Contoso'; CompanyPsaId = '189'; TenantId = '00000000-0000-0000-0000-000000000001' }
}

# --- Read the request ---
$global:Secrets = @{}
$o = Run 'agentwf-inputs.ps1' $action
Check 'action: names, start date, ticket' ($o.starter -eq 'Sam Starter' -and $o.startDate -eq '2026-11-02' -and $o.ticketId -eq '104900' -and $o.source -eq 'action') "$($o.starter) / $($o.startDate) / $($o.ticketId) / $($o.source)"
Check 'action: requester and company from User and Company' ($o.fields.requestedBy -eq 'pat.manager@contoso.com' -and $o.fields.requestedByName -eq 'Pat Manager' -and $o.fields.companyName -eq 'Contoso' -and $o.fields.companyPsaId -eq '189') ($o.fields | ConvertTo-Json -Compress)
Check 'action: a typed answer cannot set the requester' ($o.briefing -notmatch 'attacker@example.com') $o.briefing
Check 'action: stock Field IDs map to the briefing' ($o.fields.mirrorFromUser -eq 'alex@contoso.com' -and $o.fields.securityGroups -eq 'Sales Team, All Staff' -and $o.fields.needsEmail -eq 'Yes' -and $o.fields.mailGroups -eq 'sales@contoso.com' -and $o.fields.vpnRequired -eq 'No') ($o.fields | ConvertTo-Json -Compress)
Check 'action: 40-character Field IDs match' ($o.fields.computerSource -eq 'New' -and $o.fields.newComputerType -eq 'Laptop') ($o.fields | ConvertTo-Json -Compress)
Check 'action: unfilled @token counts as not answered' ($o.briefing -match 'Not answered: .*Desk phone' -and $o.briefing -notmatch '- Desk phone') $o.briefing
Check 'action: a typed confirm answer does not confirm' ($o.confirm -eq $false -and $o.confirmSource -eq '' -and $o.message -match 'Preview only') "$($o.confirm) / $($o.message)"
Check 'action: original request kept for hand-offs' ($o.request.Ticket.TicketId -eq 104900) ($o.request | ConvertTo-Json -Compress -Depth 5)

$global:Secrets = @{ 'NewUserOnboarding-Confirm' = 'true' }
$o = Run 'agentwf-inputs.ps1' $action
Check 'action: NewUserOnboarding-Confirm secret confirms' ($o.confirm -eq $true -and $o.confirmSource -eq 'secret') "$($o.confirm) $($o.confirmSource)"

$global:Secrets = @{}
$o = Run 'agentwf-inputs.ps1' ([ordered]@{ trigger = $action })
Check 'action wrapped in trigger' ($o.starter -eq 'Sam Starter' -and $o.ticketId -eq '104900') "$($o.starter) $($o.ticketId)"
$o = Run 'agentwf-inputs.ps1' ($action | ConvertTo-Json -Depth 10 -Compress)
Check 'action as a JSON string' ($o.starter -eq 'Sam Starter') $o.starter

$flatBody = [ordered]@{ ticketId = '12345'; requestedBy = 'manager@contoso.com'; firstName = 'Sam'; lastName = 'Starter'; startDate = '2026-10-12'; confirm = 'true'; psa = 'autotask' }
$o = Run 'agentwf-inputs.ps1' $flatBody
Check 'flat webhook body still works, body confirm' ($o.source -eq 'webhook' -and $o.confirm -eq $true -and $o.confirmSource -eq 'request' -and $o.psa -eq 'autotask' -and $o.ticketId -eq '12345') ($o | ConvertTo-Json -Compress -Depth 3)
$o = Run 'agentwf-inputs.ps1' ([ordered]@{ firstName = 'Sam' })
Check 'no start date -> message says intake will block' ($o.hasStartDate -eq $false -and $o.message -match 'no start date') $o.message
$o = Run 'agentwf-inputs.ps1' ''
Check 'empty trigger input -> runs, nothing answered' ($o.starter -eq '' -and $o.briefing -match 'Not answered') $o.briefing

# --- Hand-offs ---
$req = (Run 'agentwf-inputs.ps1' $action)
$req.confirm = $true
$hook = 'https://automationai.example.com/api/hooks/tenant/hook-split'
$global:Secrets = @{}
$o = Run 'agentwf-handoff-intake.ps1' ([ordered]@{ request = $req })
Check 'handoff: nothing set up -> none, no calls' ($o.status -eq 'none' -and $global:Calls.Count -eq 0) "$($o.status) $(Show)"

$global:Secrets = @{ 'NewUserOnboarding-SplitRequest-Url' = $hook; 'NewUserOnboarding-SplitRequest-Secret' = 'hook-secret' }
$o = Run 'agentwf-handoff-intake.ps1' ([ordered]@{ request = $req })
$c = @($global:Calls)[0]
Check 'handoff: SplitRequest by default after intake' ($o.status -eq 'done' -and $global:Calls.Count -eq 1 -and $c.Uri -eq $hook -and $o.handoffs[0].runId -eq 'run-1') "$($o.status) $(Show) $($o.message)"
Check 'handoff: secret sent as X-Crauto-Webhook-Secret' ($c.Headers['X-Crauto-Webhook-Secret'] -eq 'hook-secret') ($c.Headers | ConvertTo-Json -Compress)
$sent = $c.Body | ConvertFrom-Json
Check 'handoff: body is the original form request plus onboarding' ($sent.Ticket.TicketId -eq 104900 -and @($sent.Ticket.Questions).Count -ge 10 -and $sent.onboarding.starter -eq 'Sam Starter' -and $sent.onboarding.stage -eq 'AfterIntake' -and $sent.onboarding.briefing -match 'Sam') $c.Body
Check 'handoff: no secret value in the output' (($o | ConvertTo-Json -Depth 10) -notmatch 'hook-secret') ($o | ConvertTo-Json -Compress -Depth 5)

$o = Run 'agentwf-handoff-provision.ps1' ([ordered]@{ request = $req })
Check 'handoff: SplitRequest default is only for AfterIntake' ($o.status -eq 'none' -and $global:Calls.Count -eq 0) "$($o.status) $(Show)"

$global:Secrets = @{
    'NewUserOnboarding-AfterProvision' = 'AddToGroup, Laptop;Bad-Name'
    'NewUserOnboarding-AddToGroup-Url' = 'https://automationai.example.com/api/hooks/tenant/hook-group'
    'NewUserOnboarding-Laptop-Url' = 'http://insecure.example.com/hook'
}
$o = Run 'agentwf-handoff-provision.ps1' ([ordered]@{ request = $req })
Check 'handoff: list from the stage secret, no secret header when unset' ($global:Calls.Count -eq 1 -and @($global:Calls)[0].Uri -like '*hook-group' -and -not @($global:Calls)[0].Headers.ContainsKey('X-Crauto-Webhook-Secret')) (Show)
Check 'handoff: http URL and bad name skipped with reasons' ((@($o.handoffs | Where-Object { $_.name -eq 'Laptop' })[0].status -eq 'skipped') -and (@($o.warnings) -join ' ') -match "Skipped 'Bad-Name'") ($o | ConvertTo-Json -Compress -Depth 5)
Check 'handoff: stage in the body' ((@($global:Calls)[0].Body | ConvertFrom-Json).onboarding.stage -eq 'AfterProvision') @($global:Calls)[0].Body

$global:Secrets = @{ 'NewUserOnboarding-AfterIntake' = 'Broken,SplitRequest'; 'NewUserOnboarding-Broken-Url' = 'https://automationai.example.com/fail'; 'NewUserOnboarding-SplitRequest-Url' = $hook }
$o = Run 'agentwf-handoff-intake.ps1' ([ordered]@{ request = $req })
Check 'handoff: one failure is a warning, the rest still run' ($o.status -eq 'partial' -and $global:Calls.Count -eq 2 -and (@($o.warnings) -join ' ') -match "Couldn't start Broken" -and @($o.handoffs | Where-Object { $_.status -eq 'started' }).Count -eq 1) "$($o.status) $(Show) $(@($o.warnings) -join ' ')"

$r2 = RoundTrip $req; $r2.confirm = $false
$global:Secrets = @{ 'NewUserOnboarding-SplitRequest-Url' = $hook }
$o = Run 'agentwf-handoff-intake.ps1' ([ordered]@{ request = $r2 })
Check 'handoff: preview calls nothing' ($o.status -eq 'preview' -and $global:Calls.Count -eq 0 -and $o.message -match 'Would start SplitRequest') "$($o.status) $(Show) $($o.message)"

# --- Note the ticket lists the hand-offs ---
$global:Secrets = @{}
$noteReq = [ordered]@{ ticketId = '104900'; confirm = $false; psa = ''; starter = 'Sam Starter' }
$hIntake = [ordered]@{ handoffs = @([ordered]@{ name = 'SplitRequest'; status = 'started'; runId = 'run-7'; message = 'Started SplitRequest (run run-7).' }) }
$o = Run 'agentwf-note.ps1' ([ordered]@{ request = $noteReq; access = $null; verify = '{"summary":"Sam Starter is not ready yet."}'; handoffIntake = $hIntake; handoffProvision = ($hIntake | ConvertTo-Json -Depth 5 -Compress) })
Check 'note: lists hand-off runs (object and JSON text)' ($o.internal_note -match 'Other workflows for this request' -and ([regex]::Matches($o.internal_note, 'run-7')).Count -eq 2) $o.internal_note
$o = Run 'agentwf-note.ps1' ([ordered]@{ request = $noteReq; access = $null; verify = $null; handoffIntake = [ordered]@{ status = 'none'; handoffs = @() }; handoffProvision = $null })
Check 'note: no hand-offs -> no hand-off section' ($o.internal_note -notmatch 'Other workflows') $o.internal_note

if ($fail) { Write-Host "$fail failed"; exit 1 } else { Write-Host 'all passed' }
