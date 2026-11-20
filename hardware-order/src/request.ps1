# === NODE: Read the request ===
# Reads the Order Hardware form (a CloudRadial form Action, or a flat body from Test) and works out the lines,
# the ship-to address, the PO number and the vendors to ask. Writes nothing.
# Form answers (Field IDs): items (one line each, "2 x 20XW0026US" or "1 x ThinkPad T14 Gen 5 i7 16GB"), shipName,
# shipAttention, shipAddress1, shipAddress2, shipCity, shipState, shipZip, shipCountry, shipPhone, shipEmail,
# neededBy, budget, notes.
# Set by whoever runs it, never by a form answer: ticketId, confirm, vendors, psa.
$ErrorActionPreference = 'Stop'
$req = [ordered]@{
    status = 'ok'; message = ''; ticket_id = ''; company = ''; requester = ''; confirm = $false; psa = ''
    po_number = ''; vendors = @(); lines = @(); ship_to = [ordered]@{}; needed_by = ''; budget = 0; notes = ''
    warnings = @(); skip = $false
}
$warnings = New-Object System.Collections.ArrayList
function Stop-HwRequest { param([string]$Status, [string]$Msg) $req.status = $Status; $req.message = $Msg; $req.skip = $true; $req.warnings = @($warnings); Set-NodeOutput $req }

$raw = Get-Variable -Name trigger -ValueOnly -ErrorAction SilentlyContinue
if ($null -eq $raw) { $raw = Get-NodeInput }
$t = Read-StepTrigger $raw
$flat = $t.flat; $ans = $t.answers
# On a form Action the answers are the submitter's. Run settings come only from flat fields.
$both = @{}; foreach ($k in $flat.Keys) { $both[$k] = $flat[$k] }; foreach ($k in $ans.Keys) { if (-not $both.ContainsKey($k)) { $both[$k] = $ans[$k] } }
$req.ticket_id = Get-StepField $flat @('ticketId', 'ticket_id', 'ticket.id', 'Ticket.id', 'Ticket.TicketId')
$req.company = Get-StepField $flat @('company', 'company.name', 'Company.Name', 'Company.CompanyName')
$req.requester = Get-StepField $flat @('requester_email', 'user.email', 'User.Email', 'User.UserEmail')
$req.psa = Get-StepField $flat @('psa')
$req.confirm = $(if ($t.portal) { $true } else { Test-StepTrue (Get-StepField $flat @('confirm')) })
$vendorText = Get-StepField $flat @('vendors')
if (-not $vendorText) { try { $vendorText = [string](Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name 'HardwareOrder-Vendors' -AsPlainText -ErrorAction SilentlyContinue) } catch { } }
if (-not $vendorText) { $vendorText = 'ingram-micro,td-synnex' }
$known = @('ingram-micro', 'td-synnex')
$req.vendors = @($vendorText -split '[,;\s]+' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
$unknown = @($req.vendors | Where-Object { $known -notcontains $_ })
if ($unknown.Count) { Stop-HwRequest 'error' "Unknown vendor $($unknown -join ', '). Use ingram-micro and/or td-synnex. Nothing was ordered."; return }

# ---- Lines: "2 x part or description", one per line (or separated by ;) ----
$itemsText = Get-StepField $both @('items', 'hardware', 'products')
if (-not $itemsText) { Stop-HwRequest 'incomplete' 'The request has no items. Add one line per item, for example "2 x 20XW0026US". Nothing was ordered.'; return }
$lines = @()
foreach ($l in @($itemsText -split '[\r\n;]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    $qty = 1; $what = $l
    if ($l -match '^(\d{1,3})\s*(x|\*|pcs?|units?)?\s+(.+)$') { $qty = [int]$Matches[1]; $what = $Matches[3].Trim() }
    elseif ($l -match '^(.+?)\s+(x|\*)\s*(\d{1,3})$') { $qty = [int]$Matches[3]; $what = $Matches[1].Trim() }
    if ($qty -lt 1) { Stop-HwRequest 'incomplete' "The line '$l' has a quantity of 0. Nothing was ordered."; return }
    $isPart = ($what -notmatch '\s') -and ($what -match '\d') -and $what.Length -le 40
    $lines += [ordered]@{ line = $lines.Count + 1; quantity = $qty; text = $what; looks_like_part_number = $isPart }
}
if ($lines.Count -gt 5) { Stop-HwRequest 'incomplete' "The request has $($lines.Count) items; this workflow handles at most 5 per run. Split it into smaller requests. Nothing was ordered."; return }
$req.lines = @($lines)

# ---- Ship-to ----
$ship = [ordered]@{
    name = Get-StepField $both @('shipName', 'ship_name'); attention = Get-StepField $both @('shipAttention', 'ship_attention')
    address1 = Get-StepField $both @('shipAddress1', 'ship_address1'); address2 = Get-StepField $both @('shipAddress2', 'ship_address2')
    city = Get-StepField $both @('shipCity', 'ship_city'); state = Get-StepField $both @('shipState', 'ship_state')
    zip = Get-StepField $both @('shipZip', 'ship_zip', 'shipPostalCode'); country = (Get-StepField $both @('shipCountry', 'ship_country')).ToUpperInvariant()
    phone = Get-StepField $both @('shipPhone', 'ship_phone'); email = Get-StepField $both @('shipEmail', 'ship_email')
}
if (-not $ship.name) { $ship.name = $req.company }
if (-not $ship.country) { $ship.country = 'US' }
if (-not $ship.email) { $ship.email = $req.requester }
$missing = @(foreach ($k in @('name', 'address1', 'city', 'state', 'zip')) { if (-not $ship[$k]) { "ship $k" } })
if ($missing.Count) { Stop-HwRequest 'incomplete' "The ship-to address is missing: $($missing -join ', '). Nothing was ordered."; return }
if ($ship.country -ne 'US') { Stop-HwRequest 'incomplete' "Only US addresses are supported (the ship-to country is $($ship.country)). Nothing was ordered."; return }
$req.ship_to = $ship

$req.needed_by = Get-StepField $both @('neededBy', 'needed_by')
$b = (Get-StepField $both @('budget')) -replace '[^\d.]', ''
if ($b) { $d = 0.0; if ([double]::TryParse($b, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { $req.budget = $d } }
$req.notes = Get-StepField $both @('notes', 'comments')

# ---- PO number: stable per ticket, so a rerun can't place a second order under a new number ----
if ($req.ticket_id) { $req.po_number = 'HW-' + ($req.ticket_id -replace '[^A-Za-z0-9-]', '') }
elseif ($req.confirm) { Stop-HwRequest 'incomplete' 'An order needs a ticket (ticketId), so the PO number stays the same if the run is repeated. Nothing was ordered.'; return }
else { $req.po_number = 'HW-PREVIEW' }

$req.message = "$($lines.Count) item(s) to price at $($req.vendors -join ' and ')."
$req.warnings = @($warnings)
Set-NodeOutput $req
