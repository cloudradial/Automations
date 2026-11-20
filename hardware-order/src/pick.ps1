# === NODE: Pick the best offers and post the quote ===
# Picks, for each line, the cheapest offer the account is allowed to buy that has enough stock (else the
# cheapest that can be backordered), groups the lines by vendor and checks the budget. With confirm true it
# adds the quote to the ticket as an internal note (once, marked [hardware-quote <PO>]). Orders nothing.
$ErrorActionPreference = 'Stop'
$req = Read-StepJson (Get-Variable -Name req -ValueOnly -ErrorAction SilentlyContinue)
$quote = Read-StepJson (Get-Variable -Name quote -ValueOnly -ErrorAction SilentlyContinue)
# The agent's answer may be wrapped (output / result / structuredOutput) or arrive as JSON text.
foreach ($k in @('output', 'result', 'structuredOutput', 'response')) { if ($null -ne $quote -and $null -eq (Get-StepProp $quote 'offers') -and $null -ne (Get-StepProp $quote $k)) { $quote = Read-StepJson (Get-StepProp $quote $k) } }
$warnings = New-Object System.Collections.ArrayList
$plan = [ordered]@{
    status = 'error'; message = ''; ticket_id = ''; po_number = ''; psa = ''; confirm = $false; orderable = $false; skip_order = $true
    orders = @(); unquoted = @(); total = 0; budget = 0; ship_to = $null; quote_text = ''; note = ''; warnings = @()
}
function Complete-HwPick { param([string]$Status, [string]$Msg) $plan.status = $Status; $plan.message = $Msg; $plan.warnings = @($warnings); Set-NodeOutput $plan }

if ($null -eq $req) { Complete-HwPick 'error' 'The Pick step got no output from the Read step.'; return }
foreach ($w in @(Get-StepProp $req 'warnings')) { if ($w) { $null = $warnings.Add([string]$w) } }
if (Test-StepTrue (Get-StepProp $req 'skip')) { Complete-HwPick ([string](Get-StepProp $req 'status')) ([string](Get-StepProp $req 'message')); return }
$plan.ticket_id = [string](Get-StepProp $req 'ticket_id'); $plan.po_number = [string](Get-StepProp $req 'po_number'); $plan.psa = [string](Get-StepProp $req 'psa')
$plan.confirm = Test-StepTrue (Get-StepProp $req 'confirm'); $plan.ship_to = Get-StepProp $req 'ship_to'
$plan.budget = [double](Get-StepProp $req 'budget')
if ($null -eq $quote -or $null -eq (Get-StepProp $quote 'offers')) { Complete-HwPick 'error' 'The pricing step returned no offers list, so nothing can be quoted. Nothing was ordered.'; return }
foreach ($e in @(Get-StepProp $quote 'vendorErrors')) { if ($e) { $null = $warnings.Add("Pricing: $e") } }

$offers = @(Get-StepProp $quote 'offers' | Where-Object { $null -ne $_ })
$num = { param($v) $d = 0.0; if ($null -ne $v -and [double]::TryParse(([string]$v -replace '[^\d.\-]', ''), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }; return 0.0 }
$picked = @()
foreach ($l in @(Get-StepProp $req 'lines')) {
    $n = [int](Get-StepProp $l 'line'); $qty = [int](Get-StepProp $l 'quantity')
    $cands = @($offers | Where-Object { [int](Get-StepProp $_ 'line') -eq $n -and (Get-StepProp $_ 'authorized') -ne $false -and (& $num (Get-StepProp $_ 'unitPrice')) -gt 0 })
    if (-not $cands.Count) { $plan.unquoted += [ordered]@{ line = $n; text = [string](Get-StepProp $l 'text'); quantity = $qty }; continue }
    $inStock = @($cands | Where-Object { (& $num (Get-StepProp $_ 'available')) -ge $qty })
    $pool = $(if ($inStock.Count) { $inStock } else { $cands })
    $best = @($pool | Sort-Object { & $num (Get-StepProp $_ 'unitPrice') })[0]
    $unit = & $num (Get-StepProp $best 'unitPrice')
    $row = [ordered]@{
        line = $n; quantity = $qty; text = [string](Get-StepProp $l 'text'); vendor = ([string](Get-StepProp $best 'vendor')).ToLowerInvariant()
        part_number = [string](Get-StepProp $best 'partNumber'); mfr_part_number = [string](Get-StepProp $best 'vendorPartNumber')
        description = [string](Get-StepProp $best 'description'); unit_price = [math]::Round($unit, 2); extended = [math]::Round($unit * $qty, 2)
        available = [int](& $num (Get-StepProp $best 'available')); backorder = (-not $inStock.Count); offers_compared = $cands.Count
    }
    if ($row.backorder) { $null = $warnings.Add("Line ${n}: no vendor has $qty in stock; the cheapest offer ($($row.vendor)) would be backordered.") }
    $picked += $row
}
if ($plan.unquoted.Count) { $null = $warnings.Add("No vendor could price: $(@($plan.unquoted | ForEach-Object { "line $($_.line) ($($_.text))" }) -join ', ').") }

# ---- One order per vendor. With two vendors the PO numbers get a suffix, so each stays unique. ----
$vendors = @($picked | ForEach-Object { $_.vendor } | Select-Object -Unique)
$suffix = @{ 'ingram-micro' = 'IM'; 'td-synnex' = 'TD' }
foreach ($v in $vendors) {
    $rows = @($picked | Where-Object { $_.vendor -eq $v })
    $po = $(if ($vendors.Count -gt 1) { "$($plan.po_number)-$($suffix[$v])" } else { $plan.po_number })
    $sub = 0.0; foreach ($r in $rows) { $sub += $r.extended }
    $plan.orders += [ordered]@{ vendor = $v; po_number = $po; lines = $rows; subtotal = [math]::Round($sub, 2) }
}
$tot = 0.0; foreach ($r in $picked) { $tot += $r.extended }
$plan.total = [math]::Round($tot, 2)

# ---- The quote, as plain text for the ticket ----
$t = New-Object System.Collections.ArrayList
$null = $t.Add("Hardware quote for PO $($plan.po_number)")
foreach ($o in $plan.orders) {
    $null = $t.Add("$($o.vendor) (PO $($o.po_number)):")
    foreach ($r in $o.lines) { $null = $t.Add("- Line $($r.line): $($r.quantity) x $($r.description) [$($r.mfr_part_number)] at $($r.unit_price.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)) = $($r.extended.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture))$(if ($r.backorder) { ' (backorder)' }) (best of $($r.offers_compared))") }
}
$null = $t.Add("Total before tax and freight: $($plan.total.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture))")
foreach ($u in $plan.unquoted) { $null = $t.Add("Not quoted: line $($u.line), $($u.quantity) x $($u.text)") }
$plan.quote_text = $t -join "`n"

# ---- Can it be ordered? ----
if (-not $picked.Count) { Complete-HwPick 'incomplete' 'No vendor could price any item, so nothing can be ordered. Check the part numbers or descriptions.'; return }
$reasons = @()
if ($plan.unquoted.Count) { $reasons += 'some items could not be priced' }
if ($plan.budget -gt 0 -and $plan.total -gt $plan.budget) { $reasons += "the total $($plan.total) is over the budget $($plan.budget)" }
$plan.orderable = ($reasons.Count -eq 0)

if (-not $plan.confirm) {
    $plan.skip_order = $true
    Complete-HwPick 'pending_confirmation' "Preview: $($picked.Count) item(s) quoted, total $($plan.total).$(if ($reasons.Count) { ' It could not be ordered as it stands: ' + ($reasons -join '; ') + '.' }) Nothing was noted or ordered."
    return
}

# ---- confirm: note the quote on the ticket (once), then hand the plan to the order step ----
$plan.note = $plan.quote_text + "`n" + $(if ($plan.orderable) { 'Waiting for approval to order.' } else { "Not ordered: $($reasons -join '; '). A technician needs to adjust the request." })
if ($plan.ticket_id) {
    try {
        $null = Connect-Psa -Psa ([string](Get-StepProp $req 'psa'))
        $r = Add-PsaNote -Id $plan.ticket_id -Text $plan.note -Title 'Hardware quote' -Marker "hardware-quote $($plan.po_number)"
        if ($r -eq 'already-present') { $null = $warnings.Add('The quote note was already on the ticket, so it was not added again.') }
    }
    catch { $null = $warnings.Add("Couldn't add the quote to ticket $($plan.ticket_id): $($_.Exception.Message)") }
}
$plan.skip_order = (-not $plan.orderable)
if ($plan.orderable) { Complete-HwPick 'ok' "Quoted $($picked.Count) item(s), total $($plan.total). The order now waits for approval." }
else { Complete-HwPick 'incomplete' "Quoted, but not ordered: $($reasons -join '; ')." }
