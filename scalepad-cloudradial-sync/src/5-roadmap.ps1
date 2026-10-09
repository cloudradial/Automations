#{{COMMON}}
# =====================================================================
# Step 5 - Roadmap and budget: initiatives + contracts -> Planner cards
#   Subjects match the earlier migration ("ScalePad Initiative - <name>",
#   "ScalePad Contract - <name>") so existing cards are updated, not duplicated.
# =====================================================================
$phase = 'roadmap'
$results = ConvertTo-Dict (Get-P $ctx 'results')
$settings = Get-P $ctx 'settings'
$companyId = [int](Get-P $ctx 'companyId')
$spClientId = [string](Get-P $ctx 'scalePadClientId')
$counts = [ordered]@{ initiatives = 0; contracts = 0; toCreate = 0; toUpdate = 0; unchanged = 0; created = 0; updated = 0; errors = 0 }
$items = New-Object System.Collections.ArrayList
$currencies = New-Object System.Collections.Generic.HashSet[string]

# CloudRadial Planner status / priority codes (MatrixStatus / MatrixPriority).
$StatusMap = @{ New = 0; Proposed = 0; Approved = 10; InProgress = 30; OnHold = 20; Completed = 40; Declined = 50 }
$PriorityMap = @{ High = 1; Medium = 0; Low = -1; None = 0 }
# Keys are matched case-insensitively (ScalePad uses MONTHLY on contracts, Monthly on initiatives).
$MonthlyFactor = @{ MONTHLY = 1.0; BI_MONTHLY = 0.5; QUARTERLY = (1 / 3); SEMI_ANNUAL = (1 / 6); ANNUAL = (1 / 12); ANNUALLY = (1 / 12); YEARLY = (1 / 12); WEEKLY = (52 / 12); BI_WEEKLY = (26 / 12) }

function Get-QuarterSlot { param($fq)
    # CloudRadial scheduledQuarter = Nth upcoming quarter (1 = current); quarterOffset = N-1.
    $y = Get-P $fq 'year'; $qq = Get-P $fq 'quarter'
    if (-not $y -or -not $qq) { return $null }
    $now = (Get-Date).ToUniversalTime()
    $cur = $now.Year * 4 + [Math]::Floor(($now.Month - 1) / 3)
    $tgt = [int]$y * 4 + ([int]$qq - 1)
    return ($tgt - $cur + 1)
}
function ConvertTo-Html { param($s) return [System.Net.WebUtility]::HtmlEncode([string]$s) }
function Save-Card { param([string]$Subject, [hashtable]$Fields, [string]$Kind)
    $existing = $cards[$Subject.ToLowerInvariant()]
    if ($null -ne $existing) {
        # Keep whatever status and priority the partner has set since the card was created; write only what changed.
        $upd = @{}; foreach ($k in $Fields.Keys) { if ($k -notin @('status', 'priority')) { $upd[$k] = $Fields[$k] } }
        $upd = Get-ChangedFields $existing $upd
        if ($upd.Count -eq 0) { $counts.unchanged++; return }
        $counts.toUpdate++
        $null = $items.Add(@{ kind = $Kind; subject = $Subject; action = 'update'; productId = Get-P $existing 'productId'; fields = @($upd.Keys | Sort-Object) })
        if ($apply) {
            try { $null = Invoke-Cr -Method PATCH -Path "/v2/product/$(Get-P $existing 'productId')" -Body (New-PatchOps $upd); $counts.updated++ }
            catch { $counts.errors++; Warn "Update failed for '$Subject': $($_.Exception.Message)" }
        }
        return
    }
    $counts.toCreate++
    $null = $items.Add(@{ kind = $Kind; subject = $Subject; action = 'create' })
    if ($apply) {
        $body = [ordered]@{ companyId = $companyId; subject = $Subject; category = [string](Get-P $settings 'roadmapCategory' 'Efficiency'); productCategoryId = [int](Get-P $settings 'roadmapCategoryId' 7); isRequired = $false; isShowPrice = $false; isClientVisible = $false }
        foreach ($k in $Fields.Keys) { $body[$k] = $Fields[$k] }
        try { $null = Invoke-Cr -Method POST -Path '/v2/product' -Body $body; $counts.created++ }
        catch { $counts.errors++; Warn "Create failed for '$Subject': $($_.Exception.Message)" }
    }
}

if ((Get-P $ctx 'phases' @()) -notcontains $phase) {
    $results[$phase] = [ordered]@{ ran = $false }
}
else {
    $cards = Get-CrCards $companyId

    # --- Initiatives ---
    $inits = @(Get-SpAll '/lifecycle-manager/v2/initiatives' @{ 'filter[client.id]' = "eq:$spClientId"; include_unscheduled = 'true' })
    $counts.initiatives = $inits.Count
    foreach ($i in $inits) {
        $name = [string](Get-P $i 'name' 'Initiative')
        $detail = $null
        try { $detail = Get-P (Get-SpOne "/lifecycle-manager/v1/initiatives/$(Get-P $i 'id')") 'initiative' } catch { Warn "Could not read initiative '$name' detail: $($_.Exception.Message)" }
        $src = if ($null -ne $detail) { $detail } else { $i }
        $ratio = [double](Get-P $src 'budget.currency.subunit_ratio' 100); if ($ratio -le 0) { $ratio = 100 }
        $cur = [string](Get-P $src 'budget.currency.code_alpha' '')
        if ($cur) { $null = $currencies.Add($cur) }
        $oneTime = 0.0
        foreach ($li in @(Get-P $src 'budget.line_items' @())) { $oneTime += ([double](Get-P $li 'cost_subunits' 0) / $ratio) * [double](Get-P $li 'unit_count' 1) }
        $monthly = 0.0
        foreach ($li in @(Get-P $src 'budget.recurring_line_items' @())) {
            $f = [string](Get-P $li 'frequency' 'Monthly'); $factor = if ($MonthlyFactor.ContainsKey($f)) { $MonthlyFactor[$f] } else { 1.0 }
            $monthly += ([double](Get-P $li 'cost_subunits' 0) / $ratio) * [double](Get-P $li 'unit_count' 1) * $factor
        }
        $summaryText = [string](Get-P $detail 'executive_summary' '')
        $status = [string](Get-P $src 'status' 'Proposed')
        $slot = Get-QuarterSlot (Get-P $src 'fiscal_quarter')
        $when = ''
        $fqY = Get-P $src 'fiscal_quarter.year'; $fqQ = Get-P $src 'fiscal_quarter.quarter'
        if ($fqY) { $when = "Q$fqQ $fqY" }
        $bodyHtml = "<p>$(ConvertTo-Html $(if ($summaryText) { $summaryText } else { "ScalePad initiative: $name." }))</p>" +
            "<p>Status in ScalePad: $status$(if ($when) { "; scheduled for $when" }). One-time budget: $([Math]::Round($oneTime, 2)) $cur; recurring: $([Math]::Round($monthly, 2)) $cur per month.</p>"
        $fields = @{
            summary = $(if ($summaryText) { $summaryText.Substring(0, [Math]::Min(250, $summaryText.Length)) } else { "ScalePad initiative$(if ($when) { " for $when" })." })
            body = $bodyHtml
            status = $(if ($StatusMap.ContainsKey($status)) { $StatusMap[$status] } else { 0 })
            priority = $(if ($PriorityMap.ContainsKey([string](Get-P $src 'priority' 'None'))) { $PriorityMap[[string](Get-P $src 'priority' 'None')] } else { 0 })
            projectUnits = 1; projectUnitPrice = [Math]::Round($oneTime, 2)
            monthlyUnits = 1; monthlyUnitPrice = [Math]::Round($monthly, 2)
        }
        if ($status -eq 'Completed') { $fields.productType = 1; $fields.scheduledQuarter = -1 }
        elseif ($null -ne $slot -and $slot -ge 1) { $fields.productType = 1; $fields.scheduledQuarter = [int]$slot; $fields.quarterOffset = [int]$slot - 1 }
        Save-Card -Subject ("ScalePad Initiative - $name") -Fields $fields -Kind 'initiative'
    }

    # --- Contracts ---
    if (Get-P $settings 'includeContracts' $true) {
        $contracts = @(Get-SpAll '/core/v1/service/contracts' @{ 'filter[client.id]' = "eq:$spClientId" })
        $inactive = @($contracts | Where-Object { ([string](Get-P $_ 'status' '')).ToUpperInvariant() -in @('CANCELLED', 'CANCELED', 'EXPIRED', 'TERMINATED', 'INACTIVE') })
        if ($inactive.Count -gt 0 -and -not (Get-P $settings 'includeInactiveContracts' $false)) {
            Warn "Skipped $($inactive.Count) cancelled or expired ScalePad contract(s): $((@($inactive | ForEach-Object { Get-P $_ 'name' }) | Select-Object -First 10) -join ', '). Set includeInactiveContracts to add them."
            $contracts = @($contracts | Where-Object { $_ -notin $inactive })
        }
        $counts.contracts = $contracts.Count
        foreach ($k in $contracts) {
            $name = [string](Get-P $k 'name' 'Contract')
            $cur = [string](Get-P $k 'total_price.iso_currency_code' '')
            if ($cur) { $null = $currencies.Add($cur) }
            $period = [string](Get-P $k 'term.billing_period' 'MONTHLY')
            $total = [double](Get-P $k 'total_price.amount' 0)
            $factor = if ($MonthlyFactor.ContainsKey($period)) { $MonthlyFactor[$period] } else { 0 }
            $starts = Format-Day (Get-P $k 'term.starts_at'); $ends = Format-Day (Get-P $k 'term.ends_at')
            $termText = (@($(if ($starts) { "starts $starts" }), $(if ($ends) { "ends $ends" })) | Where-Object { $_ }) -join ', '
            $fields = @{
                summary = "ScalePad $(([string](Get-P $k 'type' '')).Replace('_', ' ').ToLowerInvariant()) contract, $(([string](Get-P $k 'status' '')).ToLowerInvariant())$(if ($termText) { ", $termText" })."
                body = "<p>$(ConvertTo-Html ([string](Get-P $k 'description' $name)))</p><p>Billing: $($period.Replace('_', ' ').ToLowerInvariant()), $([Math]::Round($total, 2)) $cur per period$(if ((Get-P $k 'term.is_auto_renew' $false) -eq $true) { '; auto-renews' }).</p>"
            }
            if ($factor -gt 0) { $fields.monthlyUnits = 1; $fields.monthlyUnitPrice = [Math]::Round($total * $factor, 2) }
            elseif ($period -eq 'ONE_TIME') { $fields.projectUnits = 1; $fields.projectUnitPrice = [Math]::Round($total, 2) }
            Save-Card -Subject ("ScalePad Contract - $name") -Fields $fields -Kind 'contract'
        }
    }
    if ($currencies.Count -gt 0) { Warn "ScalePad amounts are in $(@($currencies) -join ', '). CloudRadial stores the number only - confirm the portal currency matches before relying on prices." }
    $results[$phase] = [ordered]@{ ran = $true; counts = $counts; items = @($items); currencies = @($currencies) }
}

$ctx.results = $results
$ctx.warnings = @(@(Get-P $ctx 'warnings' @()) + @($warnings))
$c = $counts
Set-NodeOutput @{ status = 'ok'; message = "Roadmap: $($c.initiatives) initiatives and $($c.contracts) contracts; $(if ($apply) { "$($c.created) cards created, $($c.updated) updated" } else { "$($c.toCreate) cards to create, $($c.toUpdate) to update" }), $($c.unchanged) unchanged, $($c.errors) errors."; ctx = $ctx }
