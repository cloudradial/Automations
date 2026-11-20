# === NODE: Record the order on the ticket ===
# Reads what the order step placed, adds an internal note with the vendor order numbers (once, marked
# [hardware-order <PO>]) and a short public note for the requester, and returns the standard result.
$ErrorActionPreference = 'Stop'
$plan = Read-StepJson (Get-Variable -Name plan -ValueOnly -ErrorAction SilentlyContinue)
$res = Read-StepJson (Get-Variable -Name result -ValueOnly -ErrorAction SilentlyContinue)
foreach ($k in @('output', 'result', 'structuredOutput', 'response')) { if ($null -ne $res -and $null -eq (Get-StepProp $res 'orders') -and $null -ne (Get-StepProp $res $k)) { $res = Read-StepJson (Get-StepProp $res $k) } }
$warnings = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
$out = [ordered]@{
    status = 'error'; message = ''; public_note = ''; internal_note = ''; ticket_id = ''; po_number = ''
    actions = @(); warnings = @(); counts = [ordered]@{ orders_planned = 0; orders_placed = 0; orders_not_placed = 0 }
    total = 0; quote = ''; orders = @()
}
function Complete-HwRecord { param([string]$Status, [string]$Msg) $out.status = $Status; $out.message = $Msg; if (-not $out.internal_note) { $out.internal_note = $Msg }; $out.actions = @($actions); $out.warnings = @($warnings); Set-NodeOutput $out }

if ($null -eq $plan) { Complete-HwRecord 'error' 'The Record step got no output from the Pick step.'; return }
foreach ($w in @(Get-StepProp $plan 'warnings')) { if ($w) { $null = $warnings.Add([string]$w) } }
$out.ticket_id = [string](Get-StepProp $plan 'ticket_id'); $out.po_number = [string](Get-StepProp $plan 'po_number')
$out.total = Get-StepProp $plan 'total'; $out.quote = [string](Get-StepProp $plan 'quote_text')
$planned = @(Get-StepProp $plan 'orders' | Where-Object { $null -ne $_ })
$out.counts.orders_planned = $planned.Count
if (Test-StepTrue (Get-StepProp $plan 'skip_order')) {
    $out.internal_note = [string](Get-StepProp $plan 'note')
    Complete-HwRecord ([string](Get-StepProp $plan 'status')) ([string](Get-StepProp $plan 'message'))
    return
}
if ($null -eq $res -or $null -eq (Get-StepProp $res 'orders')) { Complete-HwRecord 'error' "The order step returned no result for PO $($out.po_number). Check the vendor portal for that PO before running again."; return }

$got = @(Get-StepProp $res 'orders' | Where-Object { $null -ne $_ })
$lines = New-Object System.Collections.ArrayList
foreach ($p in $planned) {
    $po = [string](Get-StepProp $p 'po_number'); $vendor = [string](Get-StepProp $p 'vendor')
    $r = $got | Where-Object { [string](Get-StepProp $_ 'po_number') -eq $po } | Select-Object -First 1
    $st = $(if ($r) { ([string](Get-StepProp $r 'status')).ToLowerInvariant() } else { 'not_ordered' })
    $num = $(if ($r) { [string](Get-StepProp $r 'order_number') } else { '' })
    $msg = $(if ($r) { [string](Get-StepProp $r 'message') } else { 'The order step did not report this order.' })
    $row = [ordered]@{ vendor = $vendor; po_number = $po; status = $st; order_number = $num; message = $msg }
    $out.orders += $row
    if (@('placed', 'partial') -contains $st -and $num) {
        $out.counts.orders_placed++
        $null = $actions.Add("Placed $vendor order $num (PO $po)$(if ($st -eq 'partial') { ', partly' })")
        $null = $lines.Add("$vendor order $num (PO $po): $st. $msg".Trim())
        foreach ($x in @(Get-StepProp $r 'rejected_lines')) { if ($x) { $null = $warnings.Add("PO ${po}: rejected $x") } }
        foreach ($x in @(Get-StepProp $r 'backordered_lines')) { if ($x) { $null = $warnings.Add("PO ${po}: backordered $x") } }
    }
    else {
        $out.counts.orders_not_placed++
        $null = $lines.Add("$vendor PO ${po}: not placed ($st). $msg".Trim())
    }
}
$out.internal_note = "Hardware order for PO $($out.po_number)`n" + ($lines -join "`n")
if ($out.counts.orders_placed -gt 0) {
    $out.public_note = "Your hardware has been ordered (reference $($out.po_number)). We'll update this ticket when it ships."
}
if ($out.ticket_id) {
    try {
        $null = Connect-Psa -Psa ([string](Get-StepProp $plan 'psa'))
        $w = Add-PsaNote -Id $out.ticket_id -Text $out.internal_note -Title 'Hardware order' -Marker "hardware-order $($out.po_number)"
        if ($w -eq 'written') { $null = $actions.Add("Added the order note to ticket $($out.ticket_id)") }
        if ($out.public_note -and $w -eq 'written') { Add-PsaNote -Id $out.ticket_id -Text $out.public_note -Public | Out-Null; $null = $actions.Add('Told the requester on the ticket') }
    }
    catch { $null = $warnings.Add("Couldn't note ticket $($out.ticket_id): $($_.Exception.Message)") }
}
if ($out.counts.orders_placed -eq $planned.Count) { Complete-HwRecord 'success' "Ordered: $(@($out.orders | ForEach-Object { "$($_.vendor) $($_.order_number)" }) -join ', ') for PO $($out.po_number)." }
elseif ($out.counts.orders_placed -gt 0) { Complete-HwRecord 'incomplete' "Only $($out.counts.orders_placed) of $($planned.Count) orders were placed for PO $($out.po_number). See the ticket note." }
else { Complete-HwRecord 'incomplete' "Nothing was ordered for PO $($out.po_number): $(@($out.orders | ForEach-Object { "$($_.vendor) $($_.status)" }) -join ', ')." }
