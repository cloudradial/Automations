# Strict-mode harness for hardware-order.yml: fake Key Vault, ConnectWise notes and node I/O. Runs the three
# PowerShell steps exactly as they ship (extracted from the built .yml) through & ([scriptblock]::Create(...))
# under Set-StrictMode -Version Latest. The two agent steps are replaced by fixed outputs.
# Placeholder data only (Contoso, Example MSP). Test variables start with T, so a step variable can't hide them.
# Usage: pwsh -NoProfile -File hardware-order/src/test.ps1   (needs node and js-yaml, or JS_YAML_PATH)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')
$ErrorActionPreference = 'Stop'

$TNodeExe = (Get-Command node -ErrorAction Stop).Source
& $TNodeExe (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$TJs = "const p=require('path');let y;try{y=require('js-yaml')}catch{try{y=require(p.join(process.argv[2],'node_modules','js-yaml'))}catch{y=require(process.env.JS_YAML_PATH)}};const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.properties&&a.properties.script)o[a.id]=a.properties.script;o['params:'+a.id]=((a.properties&&a.properties.parameters)||[]).map(x=>x.name+'='+x.expression).join(',');o['type:'+a.id]=a.type;if(a.type==='agent')o['ext:'+a.id]=a.properties.allowedExtensions.join(',')+'|'+a.properties.autoApprove+'|'+a.properties.model}o.order=d.definition.connections.map(c=>c.source+'>'+c.target).join(',');o.webhook=String(d.definition.activities[0].properties.webhookEnabled);console.log(JSON.stringify(o))"
$TSteps = (& $TNodeExe -e $TJs (Join-Path $PSScriptRoot '..\hardware-order.yml') $Shared) | ConvertFrom-Json -AsHashtable
Check 'workflow: steps in order, webhook off' ($TSteps.order -eq 'start>node-request,node-request>node-quote,node-quote>node-pick,node-pick>node-order,node-order>node-record,node-record>end' -and $TSteps.webhook -eq 'false') $TSteps.order
Check 'workflow: first step unbound, later steps bound to nodes.<id>.output' ($TSteps['params:node-request'] -eq '' -and $TSteps['params:node-pick'] -eq 'req={{ nodes.node-request.output }},quote={{ nodes.node-quote.output }}' -and $TSteps['params:node-record'] -eq 'plan={{ nodes.node-pick.output }},result={{ nodes.node-order.output }}') ''
Check 'workflow: agent steps limited to the two vendor extensions, blank model, no auto-approve' ($TSteps['ext:node-quote'] -eq 'ingram-micro,td-synnex|False|' -and $TSteps['ext:node-order'] -eq 'ingram-micro,td-synnex|False|') "$($TSteps['ext:node-quote']) / $($TSteps['ext:node-order'])"
Check 'workflow: no em or en dashes' (-not (@('node-request', 'node-pick', 'node-record') | Where-Object { $TSteps[$_] -match "[$([char]0x2013)$([char]0x2014)]" })) ''

# ---------- fake ConnectWise notes ----------
$TCw = 'https://cw.example/v4_6_release/apis/3.0'
$TSecrets = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = $TCw; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
$TNotes = @{}
$THandler = {
    param($c, $n)
    if ($c.Uri -match '/service/tickets/(\d+)/notes' -and $c.Method -eq 'GET') { $i = 0; return , @(@($TNotes[$Matches[1]]) | Where-Object { $_ } | ForEach-Object { $i++; [pscustomobject]@{ id = $i; text = $_.text; internalAnalysisFlag = (-not $_.public); detailDescriptionFlag = $_.public } }) }
    if ($c.Uri -match '/service/tickets/(\d+)/notes' -and $c.Method -eq 'POST') { $b = $c.Body | ConvertFrom-Json; $t = $Matches[1]; if (-not $TNotes.Contains($t)) { $TNotes[$t] = @() }; $TNotes[$t] += [pscustomobject]@{ text = $b.text; public = [bool]$b.detailDescriptionFlag }; return [pscustomobject]@{ id = 99 } }
    if ($c.Uri -match '/service/tickets/(\d+)$') { return [pscustomobject]@{ id = [int]$Matches[1]; summary = 'Order hardware'; company = [pscustomobject]@{ id = 250 } } }
    throw "Unmocked call: $($c.Method) $($c.Uri)"
}
$TNode = @{ In = $null; Out = $null }
function Get-NodeInput { return $TNode.In }
function Set-NodeOutput { param($o) $TNode.Out = $o }
function Invoke-TStep {
    param([string]$TId, $TIn = $null, [hashtable]$TParams = @{})
    $TNode.In = $TIn; $TNode.Out = $null; $terr = ''
    foreach ($k in $TParams.Keys) { Set-Variable -Name $k -Value ($TParams[$k] | ConvertTo-Json -Depth 20 -Compress) }
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $TSteps[$TId])) } catch { $terr = [string]$_.Exception.Message }
    foreach ($k in $TParams.Keys) { Remove-Variable -Name $k -ErrorAction SilentlyContinue }
    $tj = $null; if ($null -ne $TNode.Out) { $tj = ($TNode.Out | ConvertTo-Json -Depth 20 | ConvertFrom-Json) }
    return @{ out = $tj; err = $terr }
}
function Reset-T { Reset-Mock -Secrets $TSecrets.Clone() -Handler $THandler; $TNotes.Clear() }
$TBody = @{ ticketId = '12345'; company = 'Contoso Ltd'; requester_email = 'pat.doe@contoso.com'; items = "2 x 21MN0001US`n1 x 27 inch USB-C monitor"
    shipName = 'Contoso Ltd'; shipAttention = 'Pat Doe'; shipAddress1 = '1 Example Way'; shipCity = 'Springfield'; shipState = 'IL'; shipZip = '62701'; shipPhone = '555-0100' }
function New-TBody { param([hashtable]$Add = @{}) $b = $TBody.Clone(); foreach ($k in $Add.Keys) { if ($null -eq $Add[$k]) { $b.Remove($k) } else { $b[$k] = $Add[$k] } }; return ($b | ConvertTo-Json) }
function New-TOffer { param($Line, $Vendor, $Price, $Avail, [bool]$Auth = $true, $Part = 'SKU1', $Mfr = '21MN0001US') [ordered]@{ line = $Line; vendor = $Vendor; partNumber = $Part; vendorPartNumber = $Mfr; description = "Item $Line from $Vendor"; unitPrice = $Price; currency = 'USD'; available = $Avail; authorized = $Auth; note = '' } }

# ---------- 1. Read the request ----------
Reset-T
$r = Invoke-TStep 'node-request' (New-TBody)
$o = $r.out
Check 'request: no error' ($r.err -eq '') $r.err
Check 'request: two lines with quantities' ($o.status -eq 'ok' -and @($o.lines).Count -eq 2 -and $o.lines[0].quantity -eq 2 -and $o.lines[0].text -eq '21MN0001US' -and $o.lines[1].quantity -eq 1) ($o | ConvertTo-Json -Compress -Depth 5)
Check 'request: part number detected, description not' ($o.lines[0].looks_like_part_number -and -not $o.lines[1].looks_like_part_number) ''
Check 'request: PO from the ticket, both vendors, preview' ($o.po_number -eq 'HW-12345' -and (@($o.vendors) -join ',') -eq 'ingram-micro,td-synnex' -and $o.confirm -eq $false) "$($o.po_number) $($o.vendors) $($o.confirm)"
Check 'request: ship-to filled, country US, email from requester' ($o.ship_to.zip -eq '62701' -and $o.ship_to.country -eq 'US' -and $o.ship_to.email -eq 'pat.doe@contoso.com') ''
Check 'request: wrote nothing' (@($Mock.Calls).Count -eq 0) (Show-Calls)

$r = Invoke-TStep 'node-request' (New-TBody @{ shipZip = $null })
Check 'request: missing zip stops with skip' ($r.out.status -eq 'incomplete' -and $r.out.skip -and $r.out.message -like '*ship zip*') $r.out.message
$r = Invoke-TStep 'node-request' (New-TBody @{ items = (1..6 | ForEach-Object { "1 x PART$_" }) -join "`n" })
Check 'request: more than 5 items refused' ($r.out.status -eq 'incomplete' -and $r.out.message -like '*at most 5*') $r.out.message
$r = Invoke-TStep 'node-request' (New-TBody @{ ticketId = $null; confirm = 'true' })
Check 'request: an order needs a ticket' ($r.out.status -eq 'incomplete' -and $r.out.message -like '*needs a ticket*') $r.out.message
$r = Invoke-TStep 'node-request' (New-TBody @{ vendors = 'dell' })
Check 'request: unknown vendor refused' ($r.out.status -eq 'error' -and $r.out.message -like '*Unknown vendor dell*') $r.out.message
$Mock.Secrets['HardwareOrder-Vendors'] = 'td-synnex'
$r = Invoke-TStep 'node-request' (New-TBody)
Check 'request: vendors from the HardwareOrder-Vendors secret' ((@($r.out.vendors) -join ',') -eq 'td-synnex') (@($r.out.vendors) -join ',')
$Mock.Secrets.Remove('HardwareOrder-Vendors')
# A CloudRadial form Action: answers at the top level by Field ID, next to the portal's ticket and user objects.
$TAction = @{ ticket = @{ id = 777 }; company = @{ name = 'Contoso Ltd' }; user = @{ email = 'pat.doe@contoso.com' }; items = '1 x 21MN0001US'
    shipAddress1 = '1 Example Way'; shipCity = 'Springfield'; shipState = 'IL'; shipZip = '62701'; confirm = 'false'; vendors = 'dell' } | ConvertTo-Json
$r = Invoke-TStep 'node-request' $TAction
Check 'request: form Action runs live, ticket from the portal, answers cannot set run settings' ($r.out.status -eq 'ok' -and $r.out.confirm -eq $true -and $r.out.ticket_id -eq '777' -and $r.out.po_number -eq 'HW-777' -and (@($r.out.vendors) -join ',') -eq 'ingram-micro,td-synnex' -and $r.out.ship_to.name -eq 'Contoso Ltd') ($r.out | ConvertTo-Json -Compress -Depth 4)

# ---------- 2. Pick the best offers ----------
Reset-T
$TReq = (Invoke-TStep 'node-request' (New-TBody)).out
$TQuote = @{ summary = 'ok'; vendorErrors = @(); offers = @(
        (New-TOffer 1 'ingram-micro' 1050 10 $true 'IM-1'), (New-TOffer 1 'td-synnex' 999 1 $true 'TD-1'), (New-TOffer 1 'td-synnex' 900 50 $false 'TD-X'),
        (New-TOffer 2 'ingram-micro' 210 5 $true 'IM-2' 'MON27'), (New-TOffer 2 'td-synnex' 205 0 $true 'TD-2' 'MON27')) }
$r = Invoke-TStep 'node-pick' -TParams @{ req = $TReq; quote = $TQuote }
$o = $r.out
Check 'pick: no error' ($r.err -eq '') $r.err
Check 'pick: line 1 goes to the cheapest offer with enough stock, unauthorized ignored' ($o.orders[0].vendor -eq 'ingram-micro' -and $o.orders[0].lines[0].part_number -eq 'IM-1' -and $o.orders[0].lines[0].extended -eq 2100) ($o.orders | ConvertTo-Json -Compress -Depth 6)
Check 'pick: line 2 in stock only at Ingram, so one vendor and one PO' (@($o.orders).Count -eq 1 -and $o.orders[0].po_number -eq 'HW-12345' -and @($o.orders[0].lines).Count -eq 2 -and $o.total -eq 2310) "$(@($o.orders).Count) $($o.total)"
Check 'pick: preview writes nothing and skips the order' ($o.status -eq 'pending_confirmation' -and $o.skip_order -and @($Mock.Calls).Count -eq 0 -and $o.orderable) "$($o.status) $(Show-Calls)"
Check 'pick: quote text lists both lines and the total' ($o.quote_text -match 'Line 1: 2 x' -and $o.quote_text -match 'Total before tax and freight: 2310.00') $o.quote_text

$TReq2 = (Invoke-TStep 'node-request' (New-TBody @{ confirm = 'true' })).out
$TQuote2 = @{ summary = 'ok'; vendorErrors = @('td-synnex: 401 Unauthorized'); offers = @((New-TOffer 1 'td-synnex' 999 9 $true 'TD-1'), (New-TOffer 2 'ingram-micro' 210 5 $true 'IM-2' 'MON27')) }
$r = Invoke-TStep 'node-pick' -TParams @{ req = $TReq2; quote = $TQuote2 }
$o = $r.out
Check 'pick: two vendors get suffixed PO numbers' ((@($o.orders | ForEach-Object { $_.po_number }) -join ',') -eq 'HW-12345-TD,HW-12345-IM') (@($o.orders | ForEach-Object { $_.po_number }) -join ',')
Check 'pick: confirm adds the quote note once and hands over the order' ($o.status -eq 'ok' -and -not $o.skip_order -and @(Get-Calls POST "$TCw/service/tickets/12345/notes").Count -eq 1 -and $TNotes['12345'][0].text -match 'hardware-quote HW-12345') "$($o.status) $(Show-Calls)"
Check 'pick: vendor errors become warnings' (@($o.warnings | Where-Object { $_ -like 'Pricing: td-synnex: 401*' }).Count -eq 1) (@($o.warnings) -join ' | ')
$r = Invoke-TStep 'node-pick' -TParams @{ req = $TReq2; quote = $TQuote2 }
Check 'pick: a rerun does not add the quote again' (@(Get-Calls POST "$TCw/service/tickets/12345/notes").Count -eq 1) (Show-Calls)

Reset-T
$TReq3 = (Invoke-TStep 'node-request' (New-TBody @{ confirm = 'true'; budget = '$1,000' })).out
$r = Invoke-TStep 'node-pick' -TParams @{ req = $TReq3; quote = $TQuote }
Check 'pick: over budget is noted but not ordered' ($r.out.status -eq 'incomplete' -and $r.out.skip_order -and $r.out.message -like '*over the budget*' -and $TNotes['12345'][0].text -match 'Not ordered') $r.out.message
$TQuote4 = @{ summary = 'ok'; vendorErrors = @(); offers = @((New-TOffer 1 'ingram-micro' 1050 0 $true 'IM-1')) }
$r = Invoke-TStep 'node-pick' -TParams @{ req = $TReq; quote = $TQuote4 }
Check 'pick: an unpriced line blocks the order, a short line is a backorder' ($r.out.orderable -eq $false -and @($r.out.unquoted).Count -eq 1 -and $r.out.orders[0].lines[0].backorder) ($r.out | ConvertTo-Json -Compress -Depth 6)
$r = Invoke-TStep 'node-pick' -TParams @{ req = $TReq; quote = @{ output = (@{ summary = 'x'; vendorErrors = @(); offers = @((New-TOffer 1 'ingram-micro' 10 9), (New-TOffer 2 'ingram-micro' 10 9)) } | ConvertTo-Json -Depth 5) } }
Check 'pick: agent output wrapped as JSON text is read' ($r.err -eq '' -and $r.out.total -eq 30) "$($r.err) $($r.out.total)"
$r = Invoke-TStep 'node-pick' -TParams @{ req = (Invoke-TStep 'node-request' (New-TBody @{ shipZip = $null })).out; quote = @{ offers = @() } }
Check 'pick: a stopped request passes through' ($r.out.status -eq 'incomplete' -and $r.out.skip_order) $r.out.status

# ---------- 3. Record the order ----------
Reset-T
$TPlan = (Invoke-TStep 'node-pick' -TParams @{ req = $TReq2; quote = $TQuote2 }).out
Reset-T
$TOrd = @{ summary = 'done'; orders = @(
        @{ vendor = 'td-synnex'; po_number = 'HW-12345-TD'; status = 'placed'; order_number = 'SO-555'; message = 'Accepted.'; rejected_lines = @(); backordered_lines = @() },
        @{ vendor = 'ingram-micro'; po_number = 'HW-12345-IM'; status = 'partial'; order_number = '20-AB123'; message = 'One line backordered.'; rejected_lines = @(); backordered_lines = @('line 2: 1') }) }
$r = Invoke-TStep 'node-record' -TParams @{ plan = $TPlan; result = $TOrd }
$o = $r.out
Check 'record: no error, success' ($r.err -eq '' -and $o.status -eq 'success' -and $o.counts.orders_placed -eq 2) "$($r.err) $($o.status) $($o.message)"
Check 'record: internal note with both order numbers, then a public note' (@(Get-Calls POST "$TCw/service/tickets/12345/notes").Count -eq 2 -and $TNotes['12345'][0].text -match 'SO-555' -and $TNotes['12345'][0].text -match '20-AB123' -and $TNotes['12345'][1].public) (Show-Calls)
Check 'record: backorder becomes a warning' (@($o.warnings | Where-Object { $_ -like '*backordered line 2*' }).Count -eq 1) (@($o.warnings) -join ' | ')
$r = Invoke-TStep 'node-record' -TParams @{ plan = $TPlan; result = $TOrd }
Check 'record: a rerun adds no second note' (@(Get-Calls POST "$TCw/service/tickets/12345/notes").Count -eq 2) (Show-Calls)
Reset-T
$TOrd2 = @{ summary = 'x'; orders = @(@{ vendor = 'td-synnex'; po_number = 'HW-12345-TD'; status = 'denied'; order_number = ''; message = 'Approver denied it.'; rejected_lines = @(); backordered_lines = @() }) }
$r = Invoke-TStep 'node-record' -TParams @{ plan = $TPlan; result = $TOrd2 }
Check 'record: denied and missing orders are incomplete, no public note' ($r.out.status -eq 'incomplete' -and $r.out.counts.orders_not_placed -eq 2 -and -not $r.out.public_note -and @($TNotes['12345']).Count -eq 1) "$($r.out.status) $($r.out.message)"
$TPrev = (Invoke-TStep 'node-pick' -TParams @{ req = $TReq; quote = $TQuote }).out
Reset-T
$r = Invoke-TStep 'node-record' -TParams @{ plan = $TPrev; result = @{ summary = 'skipped'; orders = @() } }
Check 'record: a preview passes through and writes nothing' ($r.out.status -eq 'pending_confirmation' -and @($Mock.Calls).Count -eq 0) "$($r.out.status) $(Show-Calls)"

Complete-Test
