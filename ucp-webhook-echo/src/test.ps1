# Mock harness for ucp-webhook-echo.yml: fake Key Vault, Postmark and node I/O.
# Runs the step script exactly as it ships (extracted from the built .yml) through
# & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest. Placeholder data only (Contoso).
# Usage: node build.js --check; pwsh -NoProfile -File test.ps1   (needs js-yaml, or JS_YAML_PATH)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')
$ErrorActionPreference = 'Stop'

$tmp = Join-Path ([IO.Path]::GetTempPath()) "ucp-webhook-echo-test-$PID"
New-Item -ItemType Directory -Force $tmp | Out-Null
$extract = "const p=require('path');let y;try{y=require('js-yaml')}catch{try{y=require(p.join(process.argv[3],'node_modules','js-yaml'))}catch{y=require(process.env.JS_YAML_PATH)}};const w=y.load(require('fs').readFileSync(process.argv[1],'utf8'));for(const a of w.definition.activities){if(a.type==='powershell-script')require('fs').writeFileSync(p.join(process.argv[2],a.id+'.ps1'),a.properties.script)}"
& node -e $extract (Join-Path $PSScriptRoot '..\ucp-webhook-echo.yml') $tmp $Shared
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the step script (is js-yaml installed, or JS_YAML_PATH set?)' }
$EchoScript = Get-Content -Raw (Join-Path $tmp 'node-echo.ps1')
Remove-Item -Recurse -Force $tmp

$Node = @{ In = $null; Out = $null }
function Get-NodeInput { param($Name) return $Node.In }
function Set-NodeOutput { param($o) $Node.Out = $o }
function Invoke-Step {
    param($In)
    $Node.In = $In; $Node.Out = $null; $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $EchoScript)) } catch { $err = [string]$_.Exception.Message }
    return $err
}
$PmSecrets = @{ 'Postmark-ServerToken' = 'pm-token'; 'Postmark-FromEmail' = 'alerts@examplemsp.com' }
$PmOk = { param($c, $n) return [pscustomobject]@{ ErrorCode = 0; Message = 'OK'; MessageID = 'msg-1' } }
function Get-Sent { $c = @(Get-Calls 'POST' '*/email'); if (-not $c.Count) { return $null }; return (Read-Body $c[-1]) }

# --- flat body (the Webhook activity Content), as the runner passes it through the trigger parameter ---
Reset-Mock $PmSecrets.Clone() $PmOk
$flat = '{"toEmail":"tester@examplemsp.com","ticketId":"12345","companyName":"Contoso","UserEmail":"pat.lee@contoso.com","userIsAdmin":"true","startDate":"@startDate","notes":"","choices":["A","B"],"html":"<b>x</b>"}' | ConvertFrom-Json
$err = Invoke-Step @{ trigger = $flat }
$o = $Node.Out; $m = Get-Sent
Check 'flat: no error, success' ($err -eq '' -and $o.status -eq 'success') "$err $($o.status) $($o.message)"
Check 'flat: emailed toEmail, not UserEmail' ($m.To -eq 'tester@examplemsp.com' -and $o.email.messageId -eq 'msg-1') $m.To
Check 'flat: unreplaced token flagged in output, warning and subject' (($o.received.unreplacedTokens -join ',') -eq 'startDate' -and (@($o.warnings) -join ' ') -match 'startDate=@startDate' -and $m.Subject -match '1 token') $m.Subject
Check 'flat: empty value flagged' (($o.received.empty -join ',') -eq 'notes') ($o.received.empty -join ',')
Check 'flat: array values listed by index' (@($o.values | Where-Object { $_.path -eq 'choices[1]' -and $_.value -eq 'B' }).Count -eq 1) ''
Check 'flat: ticket id read and in subject' ($o.ticket_id -eq '12345' -and $m.Subject -match 'ticket 12345') $m.Subject
Check 'flat: HTML is encoded, raw input included' ($m.HtmlBody -notmatch '<b>x</b>' -and $m.HtmlBody -match '&lt;b&gt;x&lt;/b&gt;' -and $m.HtmlBody -match 'Raw step input' -and $m.TextBody -match '"toEmail"') ''
Check 'flat: unwrapped trigger only' (($o.received.unwrapped -join '>') -eq 'trigger') ($o.received.unwrapped -join '>')

# --- CloudRadial ticket shape, recipient falls back to UserEmail ---
Reset-Mock $PmSecrets.Clone() $PmOk
$crShape = '{"UserEmail":"pat.lee@contoso.com","Ticket":{"TicketId":678,"Questions":[{"Id":"firstName","Value":"Sam"},{"Id":"startDate","Value":"2026-10-12"}]},"Company":{"CompanyTenantId":"00000000-0000-0000-0000-000000000000"}}' | ConvertFrom-Json
$err = Invoke-Step @{ trigger = $crShape }
$o = $Node.Out; $m = Get-Sent
Check 'ticket shape: recognised, questions listed by Id' ($err -eq '' -and $o.received.shape -match 'ticket shape' -and @($o.questions).Count -eq 2 -and $o.questions[0].id -eq 'firstName') "$err $($o.received.shape)"
Check 'ticket shape: UserEmail used as recipient, TicketId found' ($m.To -eq 'pat.lee@contoso.com' -and $o.ticket_id -eq '678') "$($m.To) $($o.ticket_id)"
Check 'ticket shape: nested paths' (@($o.values | Where-Object { $_.path -eq 'Ticket.Questions[1].Value' }).Count -eq 1) ''

# --- nested UCP Action-style payload (the live shape isn't captured yet; this is a placeholder guess) ---
Reset-Mock $PmSecrets.Clone() $PmOk
$action = '{"subject":"Test automation","description":"Testing","ticket":{"id":"901","number":"T901"},"company":{"name":"Contoso"},"user":{"name":"Pat Lee","email":"pat.lee@contoso.com"},"fields":{"favouriteColour":"Blue","toEmail":"tester@examplemsp.com"}}' | ConvertFrom-Json
$err = Invoke-Step @{ trigger = $action }
Check 'nested: toEmail answer wins over user.email' ($err -eq '' -and (Get-Sent).To -eq 'tester@examplemsp.com') "$err $((Get-Sent).To)"
Reset-Mock $PmSecrets.Clone() $PmOk
$action.fields.PSObject.Properties.Remove('toEmail')
$err = Invoke-Step @{ trigger = $action }
Check 'nested: falls back to user.email' ($err -eq '' -and (Get-Sent).To -eq 'pat.lee@contoso.com' -and @($Node.Out.values | Where-Object { $_.path -eq 'fields.favouriteColour' }).Count -eq 1) "$err $((Get-Sent).To)"
Reset-Mock $PmSecrets.Clone() $PmOk
$err = Invoke-Step @{ trigger = @{ companyName = 'Contoso' } }
Check 'no recipient: incomplete, says to add toEmail' ($err -eq '' -and $Node.Out.status -eq 'incomplete' -and $Node.Out.message -match 'field key toEmail' -and @(Get-Calls 'POST' '*').Count -eq 0) $Node.Out.message

# --- body arrives as JSON text inside a {body, headers} wrapper ---
Reset-Mock $PmSecrets.Clone() $PmOk
$err = Invoke-Step @{ trigger = @{ body = '{"toEmail":"tester@examplemsp.com","companyName":"Contoso"}'; headers = @{ 'Content-Type' = 'application/json' } } }
$o = $Node.Out
Check 'wrapped text: parsed and unwrapped' ($err -eq '' -and $o.status -eq 'success' -and $o.received.shape -match 'parsed' -and ($o.received.unwrapped -join '>') -eq 'trigger>body') "$err $($o.received.shape) $($o.received.unwrapped -join '>')"

# --- a form field called "body" is not treated as a wrapper ---
Reset-Mock $PmSecrets.Clone() $PmOk
$err = Invoke-Step @{ trigger = @{ toEmail = 'tester@examplemsp.com'; body = @{ text = 'hello' } } }
$o = $Node.Out
Check 'field named body: kept as a value' ($err -eq '' -and @($o.values | Where-Object { $_.path -eq 'body.text' }).Count -eq 1) (($o.values | ForEach-Object { $_.path }) -join ',')

# --- tokens pasted in raw: a memo with a line break, a description with quotes and a backslash ---
Reset-Mock $PmSecrets.Clone() $PmOk
$rawBody = "{`n  `"toEmail`": `"tester@examplemsp.com`",`n  `"testMemo`": `"line one`nline two`",`n  `"TicketDescription`": `"<p class=`"x`">Path C:\temp</p>`",`n  `"testNumber`": `"42`",`n  `"testText`": `"hello, `"world`": ok`"`n}"
$err = Invoke-Step @{ trigger = $rawBody }
$o = $Node.Out; $m = Get-Sent
Check 'raw tokens: repaired, still emailed' ($err -eq '' -and $o.status -eq 'success' -and $o.received.shape -like 'invalid JSON*' -and $m.To -eq 'tester@examplemsp.com') "$err $($o.status) $($o.received.shape)"
$memo = @($o.values | Where-Object { $_.path -eq 'testMemo' })
Check 'raw tokens: memo kept with its line break, flagged' ($memo.Count -eq 1 -and $memo[0].value -eq "line one`nline two" -and $memo[0].check -eq 'broke the JSON (repaired)') ($memo | ConvertTo-Json -Compress)
$desc = @($o.values | Where-Object { $_.path -eq 'TicketDescription' })
Check 'raw tokens: quotes and backslash kept' ($desc.Count -eq 1 -and $desc[0].value -eq '<p class="x">Path C:\temp</p>') ($desc | ConvertTo-Json -Compress)
Check 'raw tokens: valid values not flagged, warning names the broken keys' (@($o.values | Where-Object { $_.path -eq 'testNumber' -and $_.check -eq 'ok' }).Count -eq 1 -and (@($o.warnings) -join ' ') -match 'testMemo, TicketDescription' -and $m.Subject -match 'invalid JSON') ((@($o.warnings) -join ' ') + ' / ' + $m.Subject)

# --- an unquoted token value is repaired and flagged ---
Reset-Mock $PmSecrets.Clone() $PmOk
$err = Invoke-Step @{ trigger = '{"toEmail": tester@examplemsp.com}' }
$o = $Node.Out
Check 'unquoted value: repaired, flagged, sent' ($err -eq '' -and $o.status -eq 'success' -and (@($o.warnings) -join ' ') -match 'broke it.*toEmail' -and (Get-Sent).To -eq 'tester@examplemsp.com') "$err $($o.status) $(@($o.warnings) -join ' ')"

# --- text that can't be repaired: no recipient, so not sent, but the output still has it ---
Reset-Mock $PmSecrets.Clone() $PmOk
$err = Invoke-Step @{ trigger = '{not json at all' }
$o = $Node.Out
Check 'bad JSON: incomplete, warned, nothing sent' ($err -eq '' -and $o.status -eq 'incomplete' -and (@($o.warnings) -join ' ') -match "isn't valid JSON" -and @(Get-Calls 'POST' '*').Count -eq 0) "$err $($o.status)"

# --- nothing received ---
Reset-Mock $PmSecrets.Clone() $PmOk
$err = Invoke-Step $null
$o = $Node.Out
Check 'empty: incomplete, explains the binding' ($err -eq '' -and $o.status -eq 'incomplete' -and (@($o.warnings) -join ' ') -match 'nodes.trigger.output') "$err"
$err = Invoke-Step @{ trigger = @{} }
Check 'empty object: no error' ($err -eq '' -and $Node.Out.status -eq 'incomplete') $err

# --- Postmark not set up ---
Reset-Mock @{} $PmOk
$err = Invoke-Step @{ trigger = $flat }
$o = $Node.Out
Check 'no Postmark: incomplete, names the secrets, payload still in output' ($err -eq '' -and $o.status -eq 'incomplete' -and $o.message -match 'Postmark-ServerToken' -and @($o.values).Count -gt 5) $o.message

# --- Postmark refuses ---
Reset-Mock $PmSecrets.Clone() { param($c, $n) New-HttpError 422 '{"ErrorCode":300,"Message":"Invalid email request"}' }
$err = Invoke-Step @{ trigger = $flat }
Check 'Postmark 422: incomplete with the reason' ($err -eq '' -and $Node.Out.status -eq 'incomplete' -and $Node.Out.message -match 'Invalid email request') $Node.Out.message

# --- a single-value body and a hashtable input (no trigger wrapper) ---
Reset-Mock $PmSecrets.Clone() $PmOk
$err = Invoke-Step @{ toEmail = 'tester@examplemsp.com' }
Check 'unwrapped hashtable: one value, sent' ($err -eq '' -and $Node.Out.status -eq 'success' -and @($Node.Out.values).Count -eq 1) "$err"

Complete-Test
