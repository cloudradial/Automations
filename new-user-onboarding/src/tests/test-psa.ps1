# Strict-mode harness for the PSA steps: the direct workflow's PSA ticket and manager and
# Internal note and result nodes, and the agent workflow's Note the ticket node, on all six PSAs.
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
    if ($Uri -like '*/auth/token') { return [pscustomobject]@{ access_token = 'halo-token' } }
    if ($Uri -like '*/v2/security/authenticate') { return [pscustomobject]@{ Result = [pscustomobject]@{ AccessToken = 'bms-token' } } }
    if ($Uri -like '*/TicketNotes/entityInformation/fields') { return [pscustomobject]@{ fields = @(
        [pscustomobject]@{ name = 'publish'; picklistValues = @([pscustomobject]@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, [pscustomobject]@{ value = '2'; label = 'Internal Only'; isActive = $true }) },
        [pscustomobject]@{ name = 'noteType'; picklistValues = @([pscustomobject]@{ value = '13'; label = 'System Workflow Note'; isActive = $true }, [pscustomobject]@{ value = '1'; label = 'Task Detail'; isActive = $true }) }) } }
    return [pscustomobject]@{ id = 1 }
}
function RoundTrip { param($o) return ($o | ConvertTo-Json -Depth 20 | ConvertFrom-Json) }
function Run { param([string]$File, $In) $global:Calls = @(); $global:NodeIn = (RoundTrip $In); & ([scriptblock]::Create((Get-Content -Raw (Join-Path $dir $File)))); return (RoundTrip $global:NodeOut) }

$mockSecrets = @{
    connectwise = @{ 'CW-ApiUrl' = 'https://cw.example.com/v4_6_release/apis/3.0'; 'CW-CompanyID' = 'example'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'Autotask-ApiUrl' = 'https://webservices.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    halopsa     = @{ 'Halo-ApiUrl' = 'https://halo.example.com'; 'Halo-ClientId' = 'cid'; 'Halo-ClientSecret' = 'sec' }
    kaseyabms   = @{ 'KaseyaBMS-ApiUrl' = 'https://bms.example.com'; 'KaseyaBMS-Username' = 'u'; 'KaseyaBMS-Password' = 'p'; 'KaseyaBMS-CompanyName' = 'Example MSP'; 'KaseyaBMS-NoteTypeId' = '4' }
    syncro      = @{ 'Syncro-ApiUrl' = 'https://example.syncromsp.com/api/v1'; 'Syncro-ApiKey' = 'key' }
    zendesk     = @{ 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
}
# The call each PSA's note should end with, and what its body must contain.
$expect = @{
    connectwise = @('POST', 'https://cw.example.com/v4_6_release/apis/3.0/service/tickets/12345/notes', '"internalAnalysisFlag":true')
    autotask    = @('POST', 'https://webservices.autotask.example/atservicesrest/v1.0/Tickets/12345/Notes', '"publish":2')
    halopsa     = @('POST', 'https://halo.example.com/api/Actions', '"hiddenfromuser":true')
    kaseyabms   = @('POST', 'https://bms.example.com/v2/servicedesk/tickets/12345/notes', '"IsInternal":true')
    syncro      = @('POST', 'https://example.syncromsp.com/api/v1/tickets/12345/comment', '"hidden":true')
    zendesk     = @('PUT', 'https://example.zendesk.com/api/v2/tickets/12345', '"public":false')
}
$fail = 0
function Check { param($Name, [bool]$Ok, $Detail) if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name :: $Detail"; $script:fail++ } }
function Last { return @($global:Calls)[-1] }
function Show { return (@($global:Calls | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join ' ; ') }

$finishState = [ordered]@{ status = 'ok'; confirm = $true; ticketId = '12345'; upn = 'sam.starter@contoso.com'; userId = 'u1'; tempPassword = 'not-a-real-password'
    fields = [ordered]@{ displayName = 'Sam Starter'; psa = ''; startDate = '2026-10-12'; submittedByUpn = 'manager@contoso.com'; deviceType = ''; otherAdditions = '' }
    actions = @('Created the account'); warnings = @(); followUp = @(); plan = @() }

# --- Direct workflow: internal note on each PSA, picked by the PSA-Type secret ---
foreach ($psa in @('connectwise', 'autotask', 'halopsa', 'kaseyabms', 'syncro', 'zendesk')) {
    $global:Secrets = @{ 'PSA-Type' = $psa } + $mockSecrets[$psa]
    $o = Run 'node-node-finish.ps1' $finishState
    $l = Last; $e = $expect[$psa]
    Check "direct note: $psa" ($l.Method -eq $e[0] -and $l.Uri -eq $e[1] -and $l.Body.Contains($e[2]) -and (@($o.actions) -join ' ') -match 'Posted the internal note to') "$(Show) / $($l.Body) / $(@($o.warnings) -join ' ')"
}
# Autotask details: label-matched ids, never System Workflow Note, and a title.
$global:Secrets = @{ 'PSA-Type' = 'autotask' } + $mockSecrets['autotask']
$o = Run 'node-node-finish.ps1' $finishState
$b = (Last).Body | ConvertFrom-Json
Check 'autotask: Internal Only publish, Task Detail type, titled' ($b.publish -eq 2 -and $b.noteType -eq 1 -and $b.title -eq 'New user onboarding' -and $b.ticketID -eq 12345) ((Last).Body)
Check 'autotask: headers' ((Last).Headers['ApiIntegrationCode'] -eq 'code' -and (Last).Headers['UserName'] -eq 'api@example.com') 'headers'
$global:Secrets = @{ 'PSA-Type' = 'autotask'; 'Autotask-NotePublishId' = '7'; 'Autotask-NoteTypeId' = '9' } + $mockSecrets['autotask']
$o = Run 'node-node-finish.ps1' $finishState
$b = (Last).Body | ConvertFrom-Json
Check 'autotask: secret ids override the picklist' ($b.publish -eq 7 -and $b.noteType -eq 9 -and @($global:Calls | Where-Object { $_.Uri -like '*entityInformation*' }).Count -eq 0) (Show)

# psa input beats the secret; aliases work.
$s = RoundTrip $finishState; $s.fields.psa = 'zendesk-ticketing'
$global:Secrets = @{ 'PSA-Type' = 'connectwise' } + $mockSecrets['zendesk']
$o = Run 'node-node-finish.ps1' $s
Check 'psa input (alias) beats PSA-Type' ((Last).Uri -eq $expect['zendesk'][1]) (Show)
# No PSA-Type but ConnectWise secrets: falls back to ConnectWise (runners set up before PSA-Type).
$global:Secrets = $mockSecrets['connectwise'].Clone()
$o = Run 'node-node-finish.ps1' $finishState
Check 'no PSA-Type + CW secrets -> ConnectWise' ((Last).Uri -eq $expect['connectwise'][1]) (Show)
# Nothing set up: no calls, a clear warning.
$global:Secrets = @{}
$o = Run 'node-node-finish.ps1' $finishState
Check 'no PSA -> warning, no calls' ($global:Calls.Count -eq 0 -and (@($o.warnings) -join ' ') -match 'No PSA is set up') "$(Show) / $(@($o.warnings) -join ' ')"
$global:Secrets = @{ 'PSA-Type' = 'freshdesk' }
$o = Run 'node-node-finish.ps1' $finishState
Check 'unsupported PSA -> warning' ($global:Calls.Count -eq 0 -and (@($o.warnings) -join ' ') -match "isn't supported") (@($o.warnings) -join ' ')
$global:Secrets = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices.autotask.example' }
$o = Run 'node-node-finish.ps1' $finishState
Check 'missing PSA secrets -> warning names them' ((@($o.warnings) -join ' ') -match 'Autotask-ApiIntegrationCode') (@($o.warnings) -join ' ')
$k = $mockSecrets['kaseyabms'].Clone(); $k.Remove('KaseyaBMS-NoteTypeId'); $global:Secrets = @{ 'PSA-Type' = 'kaseyabms' } + $k
$o = Run 'node-node-finish.ps1' $finishState
Check 'kaseya without note type -> warning' ((@($o.warnings) -join ' ') -match 'KaseyaBMS-NoteTypeId') (@($o.warnings) -join ' ')
# Preview: nothing posted.
$s = RoundTrip $finishState; $s.confirm = $false; $s.status = 'pending_confirmation'
$global:Secrets = @{ 'PSA-Type' = 'autotask' } + $mockSecrets['autotask']
$o = Run 'node-node-finish.ps1' $s
Check 'direct preview posts nothing' ($global:Calls.Count -eq 0 -and $o.status -eq 'pending_confirmation') (Show)

# --- Direct workflow: no ticket on a non-ConnectWise PSA is left for a technician ---
$psaState = [ordered]@{ status = 'ok'; ticketId = ''; upn = 'sam.starter@contoso.com'; managerMail = ''; fields = [ordered]@{ displayName = 'Sam Starter'; psa = '' }; actions = @(); warnings = @(); followUp = @() }
$global:Secrets = @{ 'PSA-Type' = 'autotask' } + $mockSecrets['autotask']
$o = Run 'node-node-psa.ps1' $psaState
Check 'no ticket on Autotask -> follow-up, no calls' ($global:Calls.Count -eq 0 -and (@($o.followUp) -join ' ') -match 'Create the onboarding ticket in Autotask by hand') "$(Show) / $(@($o.followUp) -join ' ')"

# --- Agent workflow: Note the ticket ---
$verify = '{"starters":[{"name":"Sam Starter","startDate":"2026-10-12","ready":false,"done":["Account sam.starter@contoso.com exists"],"awaitingHuman":["Quote: Laptop - new starter, no spare device"],"skipped":[]}],"summary":"Sam Starter is not ready yet: the laptop is waiting on a quote."}'
$access = [ordered]@{ starters = @(); summary = 'Access planned.'; needsApproval = @([ordered]@{ starter = 'Sam Starter'; item = 'Finance Share'; heldBy = 'alex@contoso.com'; whyFlagged = 'matches the sensitive pattern finance' }) }
$req = [ordered]@{ ticketId = '12345'; confirm = $true; psa = 'autotask'; starter = 'Sam Starter' }
$global:Secrets = $mockSecrets['autotask'].Clone()
$o = Run 'agentwf-note.ps1' ([ordered]@{ request = $req; access = $access; verify = $verify })
$b = (Last).Body | ConvertFrom-Json
Check 'agent note: posted to Autotask' ($o.status -eq 'posted' -and (Last).Uri -eq $expect['autotask'][1]) "$($o.status) $(Show) $(@($o.warnings) -join ' ')"
Check 'agent note: has summary, quote and approval' ($b.description -match 'not ready yet' -and $b.description -match 'Quote: Laptop' -and $b.description -match 'Finance Share \(held by alex@contoso.com') $b.description
$o = Run 'agentwf-note.ps1' ([ordered]@{ request = $req; access = $access; verify = [ordered]@{ output = ($verify | ConvertFrom-Json) } })
Check 'agent note: unwraps output' ($o.internal_note -match 'Quote: Laptop') $o.internal_note
$r2 = RoundTrip $req; $r2.confirm = $false
$o = Run 'agentwf-note.ps1' ([ordered]@{ request = $r2; access = $access; verify = $verify })
Check 'agent note: preview posts nothing' ($global:Calls.Count -eq 0 -and $o.status -eq 'preview' -and $o.internal_note -match 'Quote: Laptop') "$($o.status) $(Show)"
$o = Run 'agentwf-note.ps1' ([ordered]@{ request = $req; access = $null; verify = $null })
Check 'agent note: empty verify still notes' ($o.status -eq 'posted' -and $o.internal_note -match 'returned nothing') "$($o.status) $($o.internal_note)"
foreach ($psa in @('connectwise', 'halopsa', 'kaseyabms', 'syncro', 'zendesk')) {
    $r3 = RoundTrip $req; $r3.psa = $psa; $global:Secrets = $mockSecrets[$psa].Clone()
    $o = Run 'agentwf-note.ps1' ([ordered]@{ request = $r3; access = $access; verify = $verify })
    Check "agent note: $psa" ($o.status -eq 'posted' -and (Last).Uri -eq $expect[$psa][1]) "$($o.status) $(Show) $(@($o.warnings) -join ' ')"
}

if ($fail) { Write-Host "$fail failed"; exit 1 } else { Write-Host 'all passed' }
