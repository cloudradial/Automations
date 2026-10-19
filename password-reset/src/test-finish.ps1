# Strict-mode harness for Password Reset's Finish step: the output contract, and posting the internal note (with the
# temporary password) and the public note to the ticket on each of the six PSAs when postNotes is set.
# Runs the step exactly as it is in password-reset.yml (the shared PSA library included), through
# & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the runner Key Vault and Invoke-RestMethod
# mocked (_shared/tests/mock.ps1). Placeholder data only (Contoso, Example MSP, example.com).
# Test variables start with T: the step runs in a child scope of this script.
# Usage: pwsh -NoProfile -File password-reset/src/test-finish.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot '..\..\_shared\inject.js') (Join-Path $PSScriptRoot '..') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the shared PSA block is out of date: run node _shared/inject.js password-reset' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\password-reset.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));process.stdout.write(d.definition.activities.find(a=>a.id==='node-5').properties.script)"
$TStep = (& $node -e $js $yml) -join "`n"

$global:NodeIn = $null; $global:NodeOut = $null
function Get-NodeInput { return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Invoke-Finish {
    param($State)
    $global:NodeIn = ($State | ConvertTo-Json -Depth 8 | ConvertFrom-Json); $global:NodeOut = $null; $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $TStep)) } catch { $err = [string]$_.Exception.Message }
    $o = $null; if ($null -ne $global:NodeOut) { $o = ($global:NodeOut | ConvertTo-Json -Depth 8 | ConvertFrom-Json) }
    return @{ out = $o; error = $err }
}

# ---- placeholder PSAs: ticket 1001 keeps its notes so a read-back sees what was written ----
$TSecret = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = 'https://api-na.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'SECRET-cw-pub'; 'CW-PrivateKey' = 'SECRET-cw-priv'; 'CW-ClientId' = 'SECRET-cw-cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices5.autotask.example'; 'Autotask-ApiIntegrationCode' = 'SECRET-at-code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'SECRET-at-sec' }
    halopsa     = @{ 'PSA-Type' = 'halopsa'; 'Halo-ApiUrl' = 'https://example.halopsa.example'; 'Halo-ClientId' = 'SECRET-halo-id'; 'Halo-ClientSecret' = 'SECRET-halo-sec' }
    kaseyabms   = @{ 'PSA-Type' = 'kaseyabms'; 'KaseyaBMS-ApiUrl' = 'https://api.bms.example'; 'KaseyaBMS-Username' = 'api@example.com'; 'KaseyaBMS-Password' = 'SECRET-bms-pw'; 'KaseyaBMS-CompanyName' = 'examplemsp'; 'KaseyaBMS-NoteTypeId' = '3' }
    syncro      = @{ 'PSA-Type' = 'syncro'; 'Syncro-ApiUrl' = 'https://examplemsp.syncromsp.example/api/v1'; 'Syncro-ApiKey' = 'SECRET-syncro-key' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'SECRET-zd-tok' }
}
$TCW = 'https://api-na.example.com/v4_6_release/apis/3.0'; $TAT = 'https://webservices5.autotask.example/atservicesrest/v1.0'
$THA = 'https://example.halopsa.example/api'; $TBM = 'https://api.bms.example/v2'; $TSY = 'https://examplemsp.syncromsp.example/api/v1'; $TZD = 'https://example.zendesk.com/api/v2'
$TN = @{ notes = (New-Object System.Collections.ArrayList); fail = 0 }
function Reset-TNotes { $TN.notes.Clear(); $TN.fail = 0 }
function Add-TNote { param([string]$Text, [bool]$Pub) if ($TN.fail) { New-HttpError $TN.fail '{"message":"Insufficient security level to add notes"}' }; $null = $TN.notes.Add(@{ text = $Text; pub = $Pub }) }
$THandler = {
    param($c, $n)
    $k = "$($c.Method) $($c.Uri)"
    switch -Wildcard -CaseSensitive ($k) {
        "GET $TCW/service/tickets/1001/notes*" { return , @($TN.notes | ForEach-Object -Begin { $i = 0 } -Process { $i++; [pscustomobject]@{ id = $i; text = $_.text; internalAnalysisFlag = (-not $_.pub); detailDescriptionFlag = $_.pub; resolutionFlag = $false } }) }
        "POST $TCW/service/tickets/1001/notes" { $b = Read-Body $c; Add-TNote $b.text ([bool]$b.detailDescriptionFlag); return [pscustomobject]@{ id = 9001 } }
        "GET $TAT/TicketNotes/entityInformation/fields" { return [pscustomobject]@{ fields = @(
                    [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                    [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) } }
        "GET $TAT/TicketNotes/query*" { return [pscustomobject]@{ items = @($TN.notes | ForEach-Object { [pscustomobject]@{ id = 1; description = $_.text; publish = $(if ($_.pub) { 1 } else { 2 }) } }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
        "POST $TAT/Tickets/1001/Notes" { $b = Read-Body $c; Add-TNote $b.description ([int]$b.publish -eq 1); return [pscustomobject]@{ itemId = 3001 } }
        'POST https://example.halopsa.example/auth/token' { return [pscustomobject]@{ access_token = 'SECRET-halo-token' } }
        "GET $THA/Actions?ticket_id=1001*" { return [pscustomobject]@{ actions = @($TN.notes | ForEach-Object { [pscustomobject]@{ id = 1; note = $_.text; hiddenfromuser = (-not $_.pub) } }) } }
        "POST $THA/Actions" { $b = @(Read-Body $c)[0]; Add-TNote $b.note (-not [bool]$b.hiddenfromuser); return , @([pscustomobject]@{ id = 1 }) }
        'POST https://api.bms.example/v2/security/authenticate' { return [pscustomobject]@{ Result = [pscustomobject]@{ AccessToken = 'SECRET-bms-token' } } }
        "GET $TBM/servicedesk/tickets/1001/notes*" { return [pscustomobject]@{ Result = @($TN.notes | ForEach-Object { [pscustomobject]@{ Id = 1; Details = $_.text; IsInternal = (-not $_.pub) } }) } }
        "POST $TBM/servicedesk/tickets/1001/notes" { $b = Read-Body $c; Add-TNote $b.Details (-not [bool]$b.IsInternal); return [pscustomobject]@{ Result = [pscustomobject]@{ Id = 1 } } }
        "GET $TSY/tickets?number=1001" { return [pscustomobject]@{ tickets = @([pscustomobject]@{ id = 1001; number = '1001' }) } }
        "GET $TSY/tickets/1001" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1001; comments = @($TN.notes | ForEach-Object { [pscustomobject]@{ id = 1; body = $_.text; subject = 'Password reset'; hidden = (-not $_.pub); user_id = 5 } }) } } }
        "POST $TSY/tickets/1001/comment" { $b = Read-Body $c; Add-TNote $b.body (-not [bool]$b.hidden); return [pscustomobject]@{ comment = [pscustomobject]@{ id = 1 } } }
        "GET $TZD/tickets/1001/comments*" { return [pscustomobject]@{ comments = @($TN.notes | ForEach-Object { [pscustomobject]@{ id = 1; body = $_.text; public = $_.pub; author_id = 1 } }); next_page = $null } }
        "PUT $TZD/tickets/1001" { $b = Read-Body $c; Add-TNote $b.ticket.comment.body ([bool]$b.ticket.comment.public); return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 1001 } } }
    }
    throw "Unexpected call in test: $k"
}

# ---- step states as the earlier steps hand them over (placeholder data) ----
$TPassword = 'Xq7-PLACEHOLDER-pw'
function New-TDone { param([bool]$Post = $true, [string]$Ticket = '1001')
    return [ordered]@{ status = 'ok'; ticket_id = $Ticket; ticketId = $Ticket; upn = 'megan.bowen@contoso.com'; resolvedUpn = 'megan.bowen@contoso.com'; submittedByUpn = 'megan.bowen@contoso.com'
        userId = 'u-1'; passwordResetDone = $true; tempPassword = $TPassword; postNotes = $Post; actions = @('Ownership verified for megan.bowen@contoso.com', 'Reset password and set force-change at next sign-in'); warnings = @() }
}
function New-TRejected { param([bool]$Post = $true)
    return [ordered]@{ status = 'rejected'; ticket_id = '1001'; postNotes = $Post; message = 'You can only reset your own account. If you need a reset for another user, please contact the service desk.'
        public_note = 'You can only reset your own account. If you need a reset for another user, please contact the service desk.'
        internal_note = "Password reset DENIED: submitter 'alex.wilber@contoso.com' requested a reset for 'megan.bowen@contoso.com' (a different account)."; category = 'identity-mismatch'; actions = @(); warnings = @() }
}
function Test-NoPassword { param($o) $w = [string](ConvertTo-Json -InputObject @($o.warnings) -Depth 4 -Compress); return ($w -notmatch [regex]::Escape($TPassword) -and [string]$o.public_note -notmatch [regex]::Escape($TPassword)) }

# ---- 1. success: both notes on each PSA, the password only in the internal one ----
foreach ($TP in @('connectwise', 'autotask', 'halopsa', 'kaseyabms', 'syncro', 'zendesk')) {
    Reset-TNotes; Reset-Mock $TSecret[$TP] $THandler
    $r = Invoke-Finish (New-TDone)
    $int = @($TN.notes | Where-Object { -not $_.pub }); $pub = @($TN.notes | Where-Object { $_.pub })
    Check "$TP success: status success, notes_posted both, no error" ($r.out.status -eq 'success' -and $r.out.notes_posted -eq 'both' -and -not $r.error) "$($r.out.notes_posted) $($r.error) $(@($r.out.warnings) -join ' ')"
    Check "$TP success: one internal note with the temporary password" ($int.Count -eq 1 -and $int[0].text -like "*Temporary password*$TPassword*") (($TN.notes | ForEach-Object { "$($_.pub): $($_.text)" }) -join ' | ')
    Check "$TP success: one public note, no password in it" ($pub.Count -eq 1 -and $pub[0].text -like 'Your password has been reset*' -and $pub[0].text -notlike "*$TPassword*") (($pub | ForEach-Object { $_.text }) -join ' | ')
    Check "$TP success: no password in warnings or the public note" (Test-NoPassword $r.out)
}

# ---- 2. postNotes not set: nothing posted, the contract unchanged ----
Reset-TNotes; Reset-Mock $TSecret['connectwise'] $THandler
$r = Invoke-Finish (New-TDone -Post $false)
Check 'postNotes not set: no PSA calls, notes_posted not-requested, notes still in the output' ($Mock.Calls.Count -eq 0 -and $r.out.notes_posted -eq 'not-requested' -and $r.out.internal_note -like "*$TPassword*" -and $r.out.status -eq 'success') "$(Show-Calls) $($r.out.notes_posted)"
Check 'postNotes not set: no tempPassword field in the output' ($null -eq $r.out.PSObject.Properties['tempPassword'])

# ---- 3. a refusal from a gate: both notes posted, the run still succeeds ----
Reset-TNotes; Reset-Mock $TSecret['connectwise'] $THandler
$r = Invoke-Finish (New-TRejected)
Check 'rejected: both notes posted, status rejected, no throw' ($r.out.status -eq 'rejected' -and $r.out.notes_posted -eq 'both' -and $TN.notes.Count -eq 2 -and -not $r.error) "$($r.out.notes_posted) $($r.error)"
Check 'rejected: the user sees "You can only reset your own account"' (@($TN.notes | Where-Object { $_.pub -and $_.text -like 'You can only reset your own account*' }).Count -eq 1) (($TN.notes | ForEach-Object { $_.text }) -join ' | ')
# A retry of the same request (Action Runs "Retry") doesn't post the same notes again.
Reset-Mock $TSecret['connectwise'] $THandler
$r = Invoke-Finish (New-TRejected)
Check 'rejected retried: no duplicate notes' ($TN.notes.Count -eq 2 -and @(Get-Calls 'POST' "$TCW/service/tickets/1001/notes").Count -eq 0 -and $r.out.notes_posted -eq 'both') "notes=$($TN.notes.Count) $(Show-Calls)"

# ---- 4. the reset failed: notes posted, then the run fails ----
Reset-TNotes; Reset-Mock $TSecret['zendesk'] $THandler
$s = New-TDone; $s.passwordResetDone = $false; $s.tempPassword = ''
$r = Invoke-Finish $s
Check 'reset not confirmed: status error, both notes posted, then the run fails' ($r.out.status -eq 'error' -and $r.out.notes_posted -eq 'both' -and $r.error -like '*NOT confirmed*' -and $r.out.passwordReset -eq $false) "$($r.out.status) $($r.out.notes_posted) $($r.error)"
Check 'reset not confirmed: the user is told a technician will follow up' (@($TN.notes | Where-Object { $_.pub -and $_.text -like 'Something went wrong*' }).Count -eq 1)

# ---- 5. posting fails or can't happen: warnings, the notes stay in the output ----
Reset-TNotes; Reset-Mock @{} $THandler
$r = Invoke-Finish (New-TDone)
Check 'no PSA set up: warning, notes_posted none, still success' ($r.out.status -eq 'success' -and $r.out.notes_posted -eq 'none' -and (@($r.out.warnings) -join ' ') -like '*No PSA is set up*' -and $Mock.Calls.Count -eq 0) "$(@($r.out.warnings) -join ' ')"
Check 'no PSA set up: no password in the warnings' (Test-NoPassword $r.out)
Reset-TNotes; Reset-Mock $TSecret['connectwise'] $THandler
$r = Invoke-Finish (New-TDone -Ticket '')
Check 'no ticket number: warning, nothing called' ($r.out.notes_posted -eq 'none' -and (@($r.out.warnings) -join ' ') -like '*no ticket number*' -and $Mock.Calls.Count -eq 0) "$(@($r.out.warnings) -join ' ') $(Show-Calls)"
Reset-TNotes; $TN.fail = 403; Reset-Mock $TSecret['connectwise'] $THandler
$r = Invoke-Finish (New-TDone)
Check 'PSA refuses the notes: warnings name the ticket, still success, notes_posted none' ($r.out.status -eq 'success' -and $r.out.notes_posted -eq 'none' -and (@($r.out.warnings) -join ' ') -like "*Couldn't post the internal note to ConnectWise ticket 1001*" -and -not $r.error) "$(@($r.out.warnings) -join ' ')"
Check 'PSA refuses the notes: no password and no secrets in the warnings' ((Test-NoPassword $r.out) -and ([string](ConvertTo-Json -InputObject @($r.out.warnings) -Compress) -notmatch 'SECRET-')) "$(@($r.out.warnings) -join ' ')"

Complete-Test
