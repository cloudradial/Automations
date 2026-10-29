# Strict-mode harness for password-expiry-reminder.yml.
# Runs the three steps exactly as they are in the .yml (extracted by build.js --extract, so common.ps1,
# _shared/graph.ps1 and _shared/postmark.ps1 are included), each through & ([scriptblock]::Create(...)) under
# Set-StrictMode -Version Latest, passing each step's output to the next as JSON the way the runner does.
# Uses _shared/tests/mock.ps1 for the runner Key Vault, Invoke-RestMethod and Start-Sleep, and mocks
# Get-NodeInput and Set-NodeOutput here. Placeholder data only (Contoso, Fabrikam, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a step variable of the same
# name would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File password-expiry-reminder/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$TNode = (Get-Command node -ErrorAction Stop).Source
& $TNode (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$TTmp = Join-Path ([IO.Path]::GetTempPath()) ('pe-test-' + [guid]::NewGuid().ToString('N'))
& $TNode (Join-Path $PSScriptRoot 'build.js') --extract $TTmp | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the steps.' }
$TSteps = @{}; foreach ($s in @('node-inputs', 'node-find', 'node-send')) { $TSteps[$s] = Get-Content -Raw (Join-Path $TTmp "$s.ps1") }
Remove-Item -Recurse -Force $TTmp
$TYml = Get-Content -Raw (Join-Path $PSScriptRoot '..\password-expiry-reminder.yml')
Check 'built: three steps with the libraries pasted' ($TSteps['node-find'] -like '*function Get-GraphAll*' -and $TSteps['node-send'] -like '*function Send-PmMail*' -and $TSteps['node-inputs'] -like '*function Get-PeText*' -and $TSteps['node-inputs'] -notlike '*function Connect-Graph*')
Check 'built: webhook off, no input.* bindings, no em dashes' ($TYml -match 'webhookEnabled: false' -and $TYml -notmatch '\{\{\s*input\.' -and $TYml -notmatch '[\u2013\u2014]')

# ---- runner mocks ----
$global:NodeIn = $null; $global:NodeOut = $null
function Get-NodeInput { param([string]$Name) return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Invoke-TStep {
    param([string]$Id, $In)
    $global:NodeIn = $In; $global:NodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $TSteps[$Id])) } catch { $err = [string]$_.Exception.Message }
    $o = $null; if ($null -ne $global:NodeOut) { $o = ($global:NodeOut | ConvertTo-Json -Depth 12 | ConvertFrom-Json) }
    return @{ out = $o; error = $err }
}
function Invoke-TFlow {
    param($Body = $null)
    $in = $null; if ($null -ne $Body) { $in = ($Body | ConvertTo-Json -Depth 6 | ConvertFrom-Json) }
    $last = $null
    foreach ($id in @('node-inputs', 'node-find', 'node-send')) {
        $r = Invoke-TStep $id $in
        $last = @{ stage = $id; out = $r.out; error = $r.error }
        if ($r.error) { return $last }
        $in = $r.out
    }
    return $last
}

# ---- placeholder tenant: Contoso, 90-day passwords on contoso.com, never on fabrikam.com ----
$TTenant = '11111111-2222-3333-4444-555555555555'
$TSecrets = @{ 'M365-TenantId' = $TTenant; 'M365-ClientId' = 'client-id'; 'M365-ClientSecret' = 'client-secret'; 'PasswordExpiry-Sender' = 'it-notices@contoso.com' }
$TS = @{ Domains = @(); Users = @(); PageSize = 999; Fail = @(); Send403 = $false; Dom403 = $false; Sent = @(); Sent403 = $false }
$TNow = (Get-Date).ToUniversalTime()
function New-TD { param([string]$Name, $Days, [bool]$Verified = $true) return [pscustomobject]@{ id = $Name; isVerified = $Verified; passwordValidityPeriodInDays = $Days } }
# A user whose password has DaysLeft whole days left on a 90-day domain.
function New-TU {
    param([string]$Upn, [int]$DaysLeft = 30, [int]$Life = 90, [bool]$Enabled = $true, [string]$Type = 'Member', [bool]$Synced = $false, [string]$Policies = $null, [string]$Mail = '-', [string]$Given = '-', [switch]$NoDate)
    $n = ($Upn -split '@')[0]
    return [pscustomobject]@{
        id = [guid]::NewGuid().ToString(); userPrincipalName = $Upn; displayName = (($n -split '\.') | ForEach-Object { (Get-Culture).TextInfo.ToTitleCase($_) }) -join ' '
        givenName = $(if ($Given -eq '-') { (Get-Culture).TextInfo.ToTitleCase(($n -split '\.')[0]) } elseif ($Given) { $Given } else { $null })
        mail = $(if ($Mail -eq '-') { $Upn } elseif ($Mail) { $Mail } else { $null }); accountEnabled = $Enabled; userType = $Type
        passwordPolicies = $(if ($Policies) { $Policies } else { $null }); onPremisesSyncEnabled = $(if ($Synced) { $true } else { $null })
        lastPasswordChangeDateTime = $(if ($NoDate) { $null } elseif ($DaysLeft -eq 0) { $TNow.Date.AddDays(1).AddSeconds(-1).AddDays(-$Life).ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $TNow.AddDays($DaysLeft - $Life).ToString('yyyy-MM-ddTHH:mm:ssZ') })
    }
}
$TRouter = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    if ($u -like 'https://login.microsoftonline.com/*') { return [pscustomobject]@{ access_token = 'mock-token'; expires_in = 3600 } }
    if ($c.Method -eq 'GET' -and $u -like 'https://graph.microsoft.com/v1.0/domains*') {
        if ($TS.Dom403) { New-HttpError 403 '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}' }
        return [pscustomobject]@{ value = @($TS.Domains) }
    }
    if ($c.Method -eq 'GET' -and $u -like 'https://graph.microsoft.com/v1.0/users[?]*') {
        $all = @($TS.Users); $skip = 0
        if ($u -match 'skiptoken=(\d+)') { $skip = [int]$Matches[1] }
        $page = @($all | Select-Object -Skip $skip -First $TS.PageSize)
        $r = [ordered]@{ value = $page }
        if ($skip + $TS.PageSize -lt $all.Count) { $r['@odata.nextLink'] = "https://graph.microsoft.com/v1.0/users?`$skiptoken=$($skip + $TS.PageSize)" }
        return [pscustomobject]$r
    }
    if ($c.Method -eq 'GET' -and $u -like '*/mailFolders/sentitems/messages*') {
        if ($TS.Sent403) { New-HttpError 403 '{"error":{"code":"ErrorAccessDenied","message":"Access is denied."}}' }
        return [pscustomobject]@{ value = @($TS.Sent | ForEach-Object { [pscustomobject]@{ subject = 'Your Microsoft 365 password expires in 7 days'; toRecipients = @([pscustomobject]@{ emailAddress = [pscustomobject]@{ address = $_ } }) } }) }
    }
    if ($c.Method -eq 'POST' -and $u -like 'https://graph.microsoft.com/v1.0/users/*/sendMail') {
        if ($TS.Send403) { New-HttpError 403 '{"error":{"code":"ErrorAccessDenied","message":"Access is denied. Check credentials and try again."}}' }
        $to = (Read-Body $c).message.toRecipients[0].emailAddress.address
        if ($TS.Fail -contains $to) { New-HttpError 500 '{"error":{"code":"ErrorInternalServerError","message":"An internal server error occurred."}}' }
        return $null
    }
    if ($c.Method -eq 'POST' -and $u -like 'https://api.postmarkapp.com/email') { return [pscustomobject]@{ ErrorCode = 0; MessageID = 'pm-0001'; Message = 'OK' } }
    return $null
}
function Reset-T {
    param([hashtable]$Secrets = $TSecrets, $Users = @(), $Domains = @((New-TD 'contoso.com' 90), (New-TD 'contoso.onmicrosoft.com' 90)))
    $TS.Domains = @($Domains); $TS.Users = @($Users); $TS.PageSize = 999; $TS.Fail = @(); $TS.Send403 = $false; $TS.Dom403 = $false; $TS.Sent = @(); $TS.Sent403 = $false
    Reset-Mock $Secrets.Clone() $TRouter
}
function Get-TSends { return , @($Mock.Calls | Where-Object { $_.Method -eq 'POST' -and $_.Uri -like '*/sendMail' }) }
function Get-TSendTo { $a = Get-TSends; return , @($a | ForEach-Object { (Read-Body $_).message.toRecipients[0].emailAddress.address }) }
function Get-TSubject { param([string]$To) foreach ($c in (Get-TSends)) { $b = Read-Body $c; if ($b.message.toRecipients[0].emailAddress.address -eq $To) { return [string]$b.message.subject } }; return '' }
function Get-TText { param([string]$To) foreach ($c in (Get-TSends)) { $b = Read-Body $c; if ($b.message.toRecipients[0].emailAddress.address -eq $To) { return [string]$b.message.body.content } }; return '' }
function Get-TWarn { param($r) return (@($r.out.warnings) -join ' | ') }

# 1. A tenant where passwords never expire: success, users never read, nothing sent.
Reset-T -Users @((New-TU 'pat.doe@contoso.com' 7)) -Domains @((New-TD 'contoso.com' 2147483647), (New-TD 'contoso.onmicrosoft.com' $null))
$r = Invoke-TFlow
Check 'never expires: success with a clear message' ($r.out.status -eq 'success' -and $r.out.message -like '*set to never expire*' -and -not $r.error) "$($r.error) $($r.out.message)"
Check 'never expires: users not read, nothing sent' (-not @(Get-Calls 'GET' '*/v1.0/users[?]*').Count -and -not (Get-TSends).Count) (Show-Calls)

# 2. Mixed domains: contoso.com expires after 90 days, fabrikam.com never; an unverified domain is ignored.
Reset-T -Users @((New-TU 'pat.doe@contoso.com' 7), (New-TU 'sam.lee@fabrikam.com' 7), (New-TU 'kim.ray@old.example.com' 7)) -Domains @((New-TD 'contoso.com' 90), (New-TD 'fabrikam.com' 2147483647), (New-TD 'old.example.com' 90 $false))
$r = Invoke-TFlow
Check 'mixed domains: only the contoso.com user is emailed' ((Get-TSendTo) -join ',' -eq 'pat.doe@contoso.com' -and $r.out.status -eq 'success') "$((Get-TSendTo) -join ',') $($r.error)"
Check 'mixed domains: fabrikam counted as never expires, unverified domain skipped with a reason' ($r.out.counts.skippedNeverExpires -eq 1 -and $r.out.counts.skippedOther -eq 1 -and (@($r.out.skipped | ForEach-Object { $_.reason }) -join ' ') -like "*isn't a verified domain*") ($r.out.counts | ConvertTo-Json -Compress)

# 3. Each reminder day (14, 7, 1) gets an email; the days in between don't.
$TUsers = @((New-TU 'a.fourteen@contoso.com' 14), (New-TU 'b.seven@contoso.com' 7), (New-TU 'c.one@contoso.com' 1), (New-TU 'd.thirteen@contoso.com' 13), (New-TU 'e.eight@contoso.com' 8), (New-TU 'f.two@contoso.com' 2), (New-TU 'g.thirty@contoso.com' 30), (New-TU 'h.zero@contoso.com' 0))
Reset-T -Users $TUsers
$r = Invoke-TFlow
Check 'thresholds: 14, 7 and 1 emailed, nobody else' (((Get-TSendTo) | Sort-Object) -join ',' -eq 'a.fourteen@contoso.com,b.seven@contoso.com,c.one@contoso.com' -and $r.out.counts.emailed -eq 3) ((Get-TSendTo) -join ',')
Check 'thresholds: subjects say 14 days, 7 days, tomorrow' ((Get-TSubject 'a.fourteen@contoso.com') -eq 'Your Microsoft 365 password expires in 14 days' -and (Get-TSubject 'b.seven@contoso.com') -eq 'Your Microsoft 365 password expires in 7 days' -and (Get-TSubject 'c.one@contoso.com') -eq 'Your Microsoft 365 password expires tomorrow') "$(Get-TSubject 'c.one@contoso.com')"
Check 'thresholds: expiringSoon counts everyone within 14 days' ($r.out.counts.expiringSoon -eq 7 -and $r.out.counts.checked -eq 8) ($r.out.counts | ConvertTo-Json -Compress)
Check 'output: emailed list has days left and the expiry, no password' (@($r.out.emailed).Count -eq 3 -and @($r.out.emailed | Where-Object { $_.upn -eq 'b.seven@contoso.com' -and $_.daysLeft -eq 7 -and ($_.expires | ConvertTo-Json) -match '^"\d{4}-\d\d-\d\dT' }).Count -eq 1 -and ($r.out | ConvertTo-Json -Depth 8) -notmatch '(?i)"password"\s*:') ($r.out.emailed | ConvertTo-Json -Compress)
Reset-T -Users $TUsers
$r = Invoke-TFlow @{ daysBeforeExpiry = @(7, 0) }
Check 'daysBeforeExpiry as a JSON list with 0: 7 and today emailed' (((Get-TSendTo) | Sort-Object) -join ',' -eq 'b.seven@contoso.com,h.zero@contoso.com' -and (Get-TSubject 'h.zero@contoso.com') -eq 'Your Microsoft 365 password expires today') ((Get-TSendTo) -join ',')

# 4. Between reminder days: with catchUpDays 1 (default) a missed day isn't made up; catchUpDays 2 picks up
#    yesterday's reminder day, one email per person, for the nearest reminder day.
$TBetween = @((New-TU 'p.six@contoso.com' 6), (New-TU 'q.thirteen@contoso.com' 13), (New-TU 'r.seven@contoso.com' 7), (New-TU 's.five@contoso.com' 5))
Reset-T -Users $TBetween
$r = Invoke-TFlow
Check 'between: default rule emails only the exact reminder day' ((Get-TSendTo) -join ',' -eq 'r.seven@contoso.com') ((Get-TSendTo) -join ',')
Reset-T -Users $TBetween
$r = Invoke-TFlow @{ catchUpDays = 2 }
Check 'between: catchUpDays 2 catches 6 and 13, never 5, one email each' (((Get-TSendTo) | Sort-Object) -join ',' -eq 'p.six@contoso.com,q.thirteen@contoso.com,r.seven@contoso.com' -and (Get-TSends).Count -eq 3) ((Get-TSendTo) -join ',')
Check 'between: the email states the real days left' ((Get-TSubject 'p.six@contoso.com') -eq 'Your Microsoft 365 password expires in 6 days' -and @($r.out.due | Where-Object { $_.upn -eq 'p.six@contoso.com' -and $_.reminderDay -eq 7 }).Count -eq 1) (Get-TSubject 'p.six@contoso.com')

# 5. Already expired: no email, listed in skipped.
Reset-T -Users @((New-TU 'old.pass@contoso.com' -2), (New-TU 'b.seven@contoso.com' 7))
$r = Invoke-TFlow @{ daysBeforeExpiry = '14,7,1,0'; catchUpDays = 5 }
Check 'expired: not emailed, counted and explained' ((Get-TSendTo) -join ',' -eq 'b.seven@contoso.com' -and $r.out.counts.alreadyExpired -eq 1 -and (@($r.out.skipped | ForEach-Object { $_.reason }) -join ' ') -like '*already expired*next sign-in*') "$((Get-TSendTo) -join ',') $($r.out.counts | ConvertTo-Json -Compress)"

# 6. Skips: disabled, guest, no mailbox, DisablePasswordExpiration, no change date.
Reset-T -Users @((New-TU 'off.user@contoso.com' 7 -Enabled $false), (New-TU 'partner_example-msp.com#EXT#@contoso.com' 7 -Type 'Guest'), (New-TU 'scanner@contoso.com' 7 -Mail ''), (New-TU 'svc.backup@contoso.com' 7 -Policies 'DisablePasswordExpiration'), (New-TU 'svc.both@contoso.com' 7 -Policies 'DisablePasswordExpiration, DisableStrongPassword'), (New-TU 'no.date@contoso.com' 7 -NoDate), (New-TU 'b.seven@contoso.com' 7))
$r = Invoke-TFlow
$TC = $r.out.counts
Check 'skips: only the normal user is emailed' ((Get-TSendTo) -join ',' -eq 'b.seven@contoso.com') ((Get-TSendTo) -join ',')
Check 'skips: each counted' ($TC.skippedDisabled -eq 1 -and $TC.skippedGuests -eq 1 -and $TC.skippedNoMail -eq 1 -and $TC.skippedNeverExpires -eq 2 -and $TC.skippedOther -eq 1 -and $TC.checked -eq 7) ($TC | ConvertTo-Json -Compress)

# 7. Synced from on-premises: never emailed, counted and named in warnings.
Reset-T -Users @((New-TU 'onprem.user@contoso.com' 7 -Synced $true), (New-TU 'b.seven@contoso.com' 7))
$r = Invoke-TFlow
Check 'synced: not emailed, counted, warning names them and Active Directory' ((Get-TSendTo) -join ',' -eq 'b.seven@contoso.com' -and $r.out.counts.skippedSynced -eq 1 -and (Get-TWarn $r) -like '*onprem.user@contoso.com*' -and (Get-TWarn $r) -like '*Active Directory*') (Get-TWarn $r)

# 8. Preview (dry run): lists who would be emailed and sends nothing. dryRun works as an alias.
Reset-T -Users $TUsers
$r = Invoke-TFlow @{ preview = $true }
Check 'preview: pending_confirmation, nothing sent, three would be emailed' ($r.out.status -eq 'pending_confirmation' -and -not (Get-TSends).Count -and @($r.out.due | Where-Object { $_.result -eq 'would be emailed' }).Count -eq 3 -and $r.out.message -like '*Nothing was sent*') "$($r.error) $($r.out.message)"
Check 'preview: no Sent Items read, no writes at all' (-not @($Mock.Calls | Where-Object { $_.Method -eq 'POST' -and $_.Uri -notlike 'https://login.*' }).Count) (Show-Calls)
Reset-T -Users $TUsers
$r = Invoke-TFlow @{ dryRun = 'true' }
Check 'dryRun alias: nothing sent' ($r.out.preview -eq $true -and -not (Get-TSends).Count) $r.out.message
Reset-T -Users @((New-TU 'b.seven@contoso.com' 30))
$r = Invoke-TFlow @{ preview = $true }
Check 'preview with nobody due: success' ($r.out.status -eq 'success' -and $r.out.message -like '*Nobody is on a reminder day today*') $r.out.message

# 9. The email itself.
Reset-T -Users @((New-TU 'pat.doe@contoso.com' 7), (New-TU 'no.given@contoso.com' 7 -Given ''))
$r = Invoke-TFlow
$TBody = Get-TText 'pat.doe@contoso.com'
$TExp = $TNow.AddDays(7).ToString('dddd d MMMM yyyy', [Globalization.CultureInfo]::InvariantCulture)
Check 'email: greets by first name and gives the exact expiry date' ($TBody -like 'Hello Pat,*' -and $TBody -like "*on $TExp at *(UTC)*") $TBody
Check 'email: how to change it (Ctrl+Alt+Del, Outlook on the web, default reset page)' ($TBody -like '*Ctrl+Alt+Del*Change a password*' -and $TBody -like '*Outlook on the web*' -and $TBody -like '*https://passwordreset.microsoftonline.com/*') $TBody
Check 'email: IT will never ask for the password, no em dashes' ($TBody -like '*IT will never ask you for your password*' -and $TBody -notmatch '[\u2013\u2014]') $TBody
Check 'email: no given name falls back to the first word of the display name' ((Get-TText 'no.given@contoso.com') -like 'Hello No,*') (Get-TText 'no.given@contoso.com')
Check 'email: sent as the PasswordExpiry-Sender mailbox, kept in Sent Items' (@((Get-TSends) | Where-Object { $_.Uri -like '*/users/it-notices%40contoso.com/sendMail' -and (Read-Body $_).saveToSentItems -eq $true }).Count -eq 2) (((Get-TSends) | ForEach-Object { $_.Uri }) -join ' ')
$TSec = $TSecrets.Clone(); $TSec['PasswordExpiry-ResetUrl'] = 'https://mysignins.microsoft.com/security-info/password/change'
Reset-T -Secrets $TSec -Users @((New-TU 'pat.doe@contoso.com' 7))
$r = Invoke-TFlow
Check 'resetUrl from the PasswordExpiry-ResetUrl secret' ((Get-TText 'pat.doe@contoso.com') -like '*https://mysignins.microsoft.com/security-info/password/change*') (Get-TText 'pat.doe@contoso.com')
Reset-T -Secrets $TSec -Users @((New-TU 'pat.doe@contoso.com' 7))
$r = Invoke-TFlow @{ resetUrl = 'https://support.example-msp.test/password' }
Check 'resetUrl input overrides the secret' ((Get-TText 'pat.doe@contoso.com') -like '*https://support.example-msp.test/password*') (Get-TText 'pat.doe@contoso.com')
Reset-T -Users @((New-TU 'pat.doe@contoso.com' 7))
$r = Invoke-TFlow @{ timeZone = 'Eastern Standard Time' }
Check 'timeZone: named in the expiry date' ($r.out.status -eq 'success' -and (Get-TText 'pat.doe@contoso.com') -like '*(Eastern Standard Time)*') "$($r.error) $(Get-TText 'pat.doe@contoso.com')"

# 10. Graph send failure: counted, the rest still go out, status incomplete.
Reset-T -Users $TUsers; $TS.Fail = @('b.seven@contoso.com')
$r = Invoke-TFlow
Check 'send failure: counted, others sent, incomplete' ($r.out.status -eq 'incomplete' -and $r.out.counts.failed -eq 1 -and $r.out.counts.emailed -eq 2 -and (@($r.out.actions) -join ' ') -like "*Couldn't email b.seven@contoso.com*") "$($r.out.message) $($r.out.counts | ConvertTo-Json -Compress)"
Reset-T -Users $TUsers; $TS.Send403 = $true
$r = Invoke-TFlow
Check 'Mail.Send missing: stops after the first refusal, names the permission' ($r.out.status -eq 'incomplete' -and $r.out.counts.failed -eq 3 -and $r.out.counts.emailed -eq 0 -and (Get-TSends).Count -eq 1 -and $r.out.message -like '*Mail.Send*') "$($r.out.message) $((Get-TSends).Count)"

# 11. Same-day rerun through Graph: anyone in Sent Items since midnight is skipped.
Reset-T -Users $TUsers; $TS.Sent = @('b.seven@contoso.com')
$r = Invoke-TFlow
Check 'rerun: already emailed today is skipped, others sent' (((Get-TSendTo) | Sort-Object) -join ',' -eq 'a.fourteen@contoso.com,c.one@contoso.com' -and $r.out.counts.alreadySentToday -eq 1 -and $r.out.status -eq 'success' -and $r.out.message -like "*already had today's reminder*") "$((Get-TSendTo) -join ',') $($r.out.message)"
Check 'rerun: Sent Items read since midnight' (@(Get-Calls 'GET' '*mailFolders/sentitems/messages*sentDateTime%20ge%20*').Count -eq 1) (Show-Calls)
Reset-T -Users $TUsers; $TS.Sent403 = $true
$r = Invoke-TFlow
Check 'rerun check refused: warns about Mail.ReadBasic.All and still sends' ($r.out.counts.emailed -eq 3 -and (Get-TWarn $r) -like '*Mail.ReadBasic.All*') (Get-TWarn $r)

# 12. Postmark when PasswordExpiry-Sender isn't set.
$TPm = $TSecrets.Clone(); $TPm.Remove('PasswordExpiry-Sender'); $TPm['Postmark-ServerToken'] = 'pm-token'; $TPm['Postmark-FromEmail'] = 'it@example-msp.test'
Reset-T -Secrets $TPm -Users $TUsers
$r = Invoke-TFlow
$TPmCalls = @(Get-Calls 'POST' 'https://api.postmarkapp.com/email')
$TPmBody = if ($TPmCalls.Count) { Read-Body $TPmCalls[0] } else { $null }
Check 'postmark: three emails, no Graph sendMail' ($TPmCalls.Count -eq 3 -and -not (Get-TSends).Count -and $r.out.counts.emailed -eq 3 -and $r.out.sent_via -eq 'Postmark') "$($TPmCalls.Count) $($r.out.message)"
Check 'postmark: from the Postmark sender, plain subject and text' ($null -ne $TPmBody -and $TPmBody.From -eq 'it@example-msp.test' -and $TPmBody.Subject -like 'Your Microsoft 365 password expires*' -and $TPmBody.TextBody -like 'Hello *IT will never ask you for your password*') ($TPmBody | ConvertTo-Json -Compress)
$TNone = $TSecrets.Clone(); $TNone.Remove('PasswordExpiry-Sender')
Reset-T -Secrets $TNone -Users $TUsers
$r = Invoke-TFlow
Check 'no sender set up: error, nothing sent, names both options' ($r.out.status -eq 'error' -and -not (Get-TSends).Count -and $r.out.message -like '*PasswordExpiry-Sender*Postmark-ServerToken*') $r.out.message
Reset-T -Secrets $TNone -Users $TUsers
$r = Invoke-TFlow @{ preview = $true }
Check 'no sender set up, preview: warns' ($r.out.status -eq 'pending_confirmation' -and (Get-TWarn $r) -like '*a live run would stop*') (Get-TWarn $r)

# 13. Paging: users come back two at a time.
Reset-T -Users @((New-TU 'u.one@contoso.com' 7), (New-TU 'u.two@contoso.com' 30), (New-TU 'u.three@contoso.com' 14), (New-TU 'u.four@contoso.com' 40), (New-TU 'u.five@contoso.com' 1)); $TS.PageSize = 2
$r = Invoke-TFlow
Check 'paging: every page read, everyone checked' ($r.out.counts.checked -eq 5 -and @(Get-Calls 'GET' '*/v1.0/users[?]*').Count -eq 3 -and $r.out.counts.emailed -eq 3) "$($r.out.counts.checked) $(Show-Calls)"

# 14. onlyUsers: a test run that targets one account.
Reset-T -Users $TUsers
$r = Invoke-TFlow @{ onlyUsers = 'B.Seven@contoso.com, nobody@contoso.com' }
Check 'onlyUsers: only that account checked and emailed, unknown one warned' ((Get-TSendTo) -join ',' -eq 'b.seven@contoso.com' -and $r.out.counts.checked -eq 1 -and (Get-TWarn $r) -like "*no Microsoft 365 account matches 'nobody@contoso.com'*") "$((Get-TSendTo) -join ',') $(Get-TWarn $r)"
Reset-T -Users $TUsers
$r = Invoke-TFlow @{ onlyUsers = 'not-an-account' }
Check 'onlyUsers with nothing valid: stops rather than email everyone' ($r.stage -eq 'node-inputs' -and $r.out.status -eq 'incomplete' -and -not $Mock.Calls.Count) $r.out.message

# 15. Tenant mismatch: rejected before anything is read.
Reset-T -Users $TUsers
$r = Invoke-TFlow @{ company_tenant_id = '99999999-8888-7777-6666-555555555555' }
Check 'tenant mismatch: rejected, nothing read or sent' ($r.out.status -eq 'rejected' -and -not @(Get-Calls 'GET' 'https://graph.microsoft.com/*').Count -and -not (Get-TSends).Count) "$($r.out.status) $(Show-Calls)"
Reset-T -Users $TUsers
$r = Invoke-TFlow @{ company_tenant_id = $TTenant.ToUpperInvariant() }
Check 'tenant match (any case): runs' ($r.out.status -eq 'success' -and $r.out.counts.emailed -eq 3) "$($r.error) $($r.out.message)"

# 16. Bad input and missing permissions fail closed with a plain sentence.
foreach ($TBad in @(@{ daysBeforeExpiry = 'soon' }, @{ daysBeforeExpiry = '400' }, @{ preview = 'maybe' }, @{ resetUrl = 'http://phish.example.com' }, @{ timeZone = 'Mars/Olympus' }, @{ catchUpDays = 0 }, @{ company_tenant_id = 'contoso' })) {
    Reset-T -Users $TUsers
    $r = Invoke-TFlow $TBad
    Check "bad input $(($TBad.Keys)[0])=$(($TBad.Values)[0]): incomplete, nothing read" ($r.stage -eq 'node-inputs' -and $r.out.status -eq 'incomplete' -and -not $Mock.Calls.Count -and $r.out.message -like '*No email was sent*') $r.out.message
}
Reset-T -Users $TUsers; $TS.Dom403 = $true
$r = Invoke-TFlow
Check 'Domain.Read.All missing: error naming it' ($r.out.status -eq 'error' -and $r.out.message -like '*Domain.Read.All*' -and -not (Get-TSends).Count) $r.out.message
Reset-T -Secrets @{} -Users $TUsers
$r = Invoke-TFlow
Check 'no Microsoft 365 secrets: error naming them' ($r.out.status -eq 'error' -and $r.out.message -like '*M365-TenantId*') $r.out.message
Reset-T -Users $TUsers
$r = Invoke-TFlow '@daysBeforeExpiry'
Check 'unexpanded token as input text: treated as invalid JSON, nothing read' ($r.stage -eq 'node-inputs' -and $r.out.status -eq 'incomplete') $r.out.message
Reset-T -Users $TUsers
$r = Invoke-TFlow @{ daysBeforeExpiry = '@daysBeforeExpiry'; resetUrl = '@resetUrl' }
Check 'literal @tokens count as not given: defaults used' ($r.out.status -eq 'success' -and $r.out.counts.emailed -eq 3) "$($r.error) $($r.out.message)"

Complete-Test
