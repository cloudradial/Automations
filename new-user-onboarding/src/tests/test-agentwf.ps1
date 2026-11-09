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

# The shape the portal actually sends for an Action (seen on DV, 2026-10-14): the answers as top-level keys by Field
# ID (null when unanswered, a literal @token when a token-driven choice list is empty), next to lowercase ticket,
# company and user objects. Placeholder data. The last three answers try to set the requester, confirm and the PSA.
$portal = [ordered]@{
    firstName = 'Sam'; lastName = 'Starter'; department = 'Sales'; jobTitle = 'Account Executive'; officeLocation = 'Main Office'; startDate = '2026-11-02'
    modelTheNewUsersAccountAccessFrom = 'alex@contoso.com'; softwareLicenses = $null; companyFileAccess = $null; isVpnRemoteAccessRequired = 'No'
    otherAdditions = $null; doesTheUserRequireAnEmailAccount = 'Yes'; email = $null; mailDistributionGroups = $null
    willTheNewUserBeUsingAnExistingOrNewComp = 'New'; whichExistingEndpointWillBeUsedForTheNew = $null
    whatTypeOfNewComputerDoesTheNewUserRequi = '@CompanyComputerChoices'; whichPrinterDoesTheUserNeedAccessTo = '@CompanyPrinters'
    otherEquipment = $null; doesThisUserNeedADeskPhone = 'No'
    requestedBy = 'attacker@example.com'; confirm = 'true'; psa = 'zendesk'
    ticket = [ordered]@{ id = 104901; reference = '104901'; subject = 'Add a New User'; description = 'Please fill out the form.'; estimatedTime = 0.0; checklist = @() }
    company = [ordered]@{ id = 1; name = 'Contoso'; psaId = 189; psaIdentifier = 'ConnectWise'; tenantId = '00000000-0000-0000-0000-000000000002' }
    user = [ordered]@{ id = 'u-1'; name = 'Pat Manager'; email = 'pat.manager@contoso.com'; psaId = 614; psaSiteId = 2 }
}
$global:Secrets = @{}
$o = Run 'agentwf-inputs.ps1' $portal
Check 'portal shape: answers, ticket and start date' ($o.starter -eq 'Sam Starter' -and $o.startDate -eq '2026-11-02' -and $o.ticketId -eq '104901' -and $o.source -eq 'action') "$($o.starter) / $($o.ticketId) / $($o.source)"
Check 'portal shape: requester and company from user and company' ($o.fields.requestedBy -eq 'pat.manager@contoso.com' -and $o.fields.requestedByName -eq 'Pat Manager' -and $o.fields.requestedByPsaId -eq '614' -and $o.fields.companyName -eq 'Contoso' -and $o.fields.companyPsaId -eq '189' -and $o.fields.companyTenantId -eq '00000000-0000-0000-0000-000000000002') ($o.fields | ConvertTo-Json -Compress)
Check 'portal shape: a requestedBy answer cannot set the requester' ($o.briefing -notmatch 'attacker@example.com') $o.briefing
Check 'portal shape: confirm and psa answers are ignored' ($o.confirm -eq $false -and $o.confirmSource -eq '' -and $o.psa -eq '') "$($o.confirm) / $($o.psa)"
Check 'portal shape: stock and 40-character Field IDs' ($o.fields.mirrorFromUser -eq 'alex@contoso.com' -and $o.fields.needsEmail -eq 'Yes' -and $o.fields.vpnRequired -eq 'No' -and $o.fields.computerSource -eq 'New' -and $o.fields.deskPhone -eq 'No') ($o.fields | ConvertTo-Json -Compress)
Check 'portal shape: null answers and empty @token lists are not answered' ($o.briefing -match 'Not answered: .*Software' -and $o.briefing -match 'Not answered: .*New computer type' -and $o.briefing -match 'Not answered: .*Printer' -and $o.briefing -notmatch '@Company') $o.briefing
$p2 = RoundTrip $portal; $p2.user.email = $null
$o = Run 'agentwf-inputs.ps1' $p2
Check 'portal shape: no user email -> requester not answered, answer still ignored' ($o.briefing -match 'Not answered: Requested by \(email\)' -and $o.briefing -notmatch 'attacker@example.com') $o.briefing
$global:Secrets = @{ 'NewUserOnboarding-Confirm' = 'true' }
$o = Run 'agentwf-inputs.ps1' $portal
Check 'portal shape: the confirm secret still confirms' ($o.confirm -eq $true -and $o.confirmSource -eq 'secret') "$($o.confirm) $($o.confirmSource)"
$global:Secrets = @{}

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

# --- Send first sign-in ---
$tid = '00000000-0000-0000-0000-000000000001'
$global:Created = [DateTime]::UtcNow.ToString('o')
function Invoke-RestMethod { param($Method, $Uri, $Headers, $Body, $ContentType, $Form)
    $global:Calls += [pscustomobject]@{ Method = [string]$Method; Uri = [string]$Uri; Body = $(if ($Body -is [string]) { $Body } else { '' }); Headers = $Headers }
    if ($Uri -like 'https://login.microsoftonline.com/*') { return [pscustomobject]@{ access_token = 'graph-token' } }
    if ($Method -eq 'Get' -and $Uri -like '*/v1.0/users/sam.starter%40contoso.com*') { return [pscustomobject]@{ id = 'u-new'; userPrincipalName = 'sam.starter@contoso.com'; createdDateTime = $global:Created } }
    if ($Method -eq 'Get' -and $Uri -like '*/v1.0/users/*') { $ex = [System.Exception]::new('Not Found'); $ex | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = 404 }); throw $ex }
    if ($Uri -like '*/v1.0/organization*') { return [pscustomobject]@{ value = @([pscustomobject]@{ verifiedDomains = @([pscustomobject]@{ name = 'contoso.com'; isDefault = $true }) }) } }
    if ($Method -eq 'Patch' -and $Uri -like '*/v1.0/users/u-new' -and $global:PatchFails) { throw 'Response status code does not indicate success: 403 (Forbidden).' }
    return [pscustomobject]@{ id = 1 }
}
$credReq = (Run 'agentwf-inputs.ps1' ([ordered]@{ firstName = 'Sam'; lastName = 'Starter'; startDate = '2026-11-02'; managerEmail = 'pat.manager@contoso.com'; companyTenantId = $tid; requestedBy = 'pat.manager@contoso.com'; ticketId = '104900'; confirm = 'true' }))
$prov = [ordered]@{ starters = @([ordered]@{ name = 'Sam Starter'; upn = 'Sam.Starter@contoso.com'; done = @('Created the account') }); summary = 'Account created.' }
$m365 = @{ 'M365-TenantId' = $tid; 'M365-ClientId' = 'cid'; 'M365-ClientSecret' = 'sec'; 'NewUserOnboarding-NotifySender' = 'it@msp.example' }
function Mails { return @($global:Calls | Where-Object { $_.Uri -like '*/sendMail' }) }
function CredRun { param($Req, $Prov) return (Run 'agentwf-credential.ps1' ([ordered]@{ request = $Req; provision = $Prov })) }
Check 'credential: Read the request stamps receivedUtc and the recipient answer' ($credReq.receivedUtc -and $credReq.fields.managerEmail -eq 'pat.manager@contoso.com') ($credReq | ConvertTo-Json -Compress -Depth 3)

$global:Secrets = $m365.Clone(); $global:PatchFails = $false
$o = CredRun $credReq $prov
$patch = @($global:Calls | Where-Object { $_.Method -eq 'Patch' })
$m = Mails
Check 'credential: sets a forced-change password on the new account' ($patch.Count -eq 1 -and ($patch[0].Body | ConvertFrom-Json).passwordProfile.forceChangePasswordNextSignIn -eq $true -and $o.tempPassword.Length -eq 16 -and $o.upn -eq 'sam.starter@contoso.com') "$($o.status) $(Show) $(@($o.followUp) -join ' ')"
Check 'credential: emails it to the manager by default, once' ($m.Count -eq 1 -and $m[0].Body.Contains($o.tempPassword) -and $o.passwordEmailedTo -eq 'pat.manager@contoso.com' -and $o.status -eq 'done') "$($o.status) $(Show) / $(@($o.followUp) -join ' ')"

$r = RoundTrip $credReq; $r.fields | Add-Member -NotePropertyName passwordRecipientEmail -NotePropertyValue 'office@contoso.com'
$o = CredRun $r $prov
$m = Mails
$mgrMail = @($m | Where-Object { ($_.Body | ConvertFrom-Json).message.toRecipients[0].emailAddress.address -eq 'pat.manager@contoso.com' })
Check 'credential: recipient answer gets the password, manager gets none' ($m.Count -eq 2 -and $o.passwordEmailedTo -eq 'office@contoso.com' -and $mgrMail.Count -eq 1 -and -not $mgrMail[0].Body.Contains($o.tempPassword)) "$(Show) / $(@($o.followUp) -join ' ')"

$r = RoundTrip $credReq; $r.fields | Add-Member -NotePropertyName passwordRecipientEmail -NotePropertyValue 'someone@gmail.com'
$o = CredRun $r $prov
Check 'credential: outside address refused, password still set for the note' ($o.passwordEmailedTo -eq '' -and $o.tempPassword -and @(Mails | Where-Object { $_.Body.Contains($o.tempPassword) }).Count -eq 0 -and (@($o.followUp) -join ' ') -match 'AllowExternalPasswordRecipient') "$(Show) / $(@($o.followUp) -join ' ')"
$global:Secrets = $m365 + @{ 'NewUserOnboarding-AllowExternalPasswordRecipient' = 'true' }
$o = CredRun $r $prov
Check 'credential: outside address allowed by the secret' ($o.passwordEmailedTo -eq 'someone@gmail.com') "$(Show) / $(@($o.followUp) -join ' ')"

$global:Secrets = $m365.Clone()
$r = RoundTrip $credReq; $r.confirm = $false
$o = CredRun $r $prov
Check 'credential: preview calls nothing' ($o.status -eq 'preview' -and $global:Calls.Count -eq 0 -and -not $o.tempPassword) "$($o.status) $(Show)"
$o = CredRun $credReq ([ordered]@{ starters = @([ordered]@{ name = 'Sam Starter' }); summary = 'x' })
Check 'credential: no upn from Provision -> skipped, no calls' ($o.status -eq 'skipped' -and $global:Calls.Count -eq 0) "$($o.status) $(Show)"
$o = CredRun $credReq ([ordered]@{ output = ($prov | ConvertTo-Json -Depth 5) })
Check 'credential: unwraps a wrapped Provision result' ($o.status -eq 'done') "$($o.status) $(@($o.followUp) -join ' ')"
$r = RoundTrip $credReq; $r.fields.companyTenantId = '99999999-0000-0000-0000-000000000000'
$o = CredRun $r $prov
Check 'credential: other tenant -> rejected, nothing changed' ($o.status -eq 'rejected' -and @($global:Calls | Where-Object { $_.Method -eq 'Patch' }).Count -eq 0) "$($o.status) $(Show)"
$global:Created = [DateTime]::UtcNow.AddDays(-30).ToString('o')
$o = CredRun $credReq $prov
Check 'credential: an older account is never changed' ($o.status -eq 'rejected' -and @($global:Calls | Where-Object { $_.Method -eq 'Patch' }).Count -eq 0 -and (@($o.followUp) -join ' ') -match "wasn't created by this run") "$($o.status) $(Show)"
$global:Created = [DateTime]::UtcNow.ToString('o')
$o = CredRun $credReq ([ordered]@{ starters = @([ordered]@{ name = 'Someone'; upn = 'ghost@contoso.com' }); summary = 'x' })
Check 'credential: account not found -> not done, nothing changed' ($o.status -eq 'not_done' -and @($global:Calls | Where-Object { $_.Method -eq 'Patch' }).Count -eq 0) "$($o.status) $(Show)"
$global:PatchFails = $true
$o = CredRun $credReq $prov
Check 'credential: reset refused -> error, no email' ($o.status -eq 'error' -and @(Mails).Count -eq 0 -and -not $o.tempPassword -and (@($o.followUp) -join ' ') -match 'password admin role') "$($o.status) $(Show)"
$global:PatchFails = $false
$global:Secrets = @{ 'M365-TenantId' = $tid; 'M365-ClientId' = 'cid'; 'M365-ClientSecret' = 'sec' }
$o = CredRun $credReq $prov
Check 'credential: no sender -> follow-up, password in the note' (@(Mails).Count -eq 0 -and $o.tempPassword -and (@($o.followUp) -join ' ') -match 'NewUserOnboarding-NotifySender') "$($o.status) $(@($o.followUp) -join ' ')"

# Note the ticket carries the first sign-in result and the password.
$o = Run 'agentwf-note.ps1' ([ordered]@{ request = $noteReq; access = $null; verify = '{"summary":"Ready."}'; credential = [ordered]@{ status = 'done'; upn = 'sam.starter@contoso.com'; tempPassword = 'Temp-Pass-123!'; passwordEmailedTo = 'pat.manager@contoso.com'; actions = @('Emailed the sign-in name and temporary password to pat.manager@contoso.com'); warnings = @(); followUp = @() } })
Check 'note: first sign-in section and password' ($o.internal_note -match 'First sign-in:' -and $o.internal_note -match 'also emailed to pat.manager@contoso.com;.*Temp-Pass-123!') $o.internal_note

if ($fail) { Write-Host "$fail failed"; exit 1 } else { Write-Host 'all passed' }
