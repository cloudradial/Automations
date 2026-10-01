#{{COMMON}}
# =====================================================================
# Insights and recommendations -> Planner cards (+ a table in the report)
#   Each ScalePad insight that currently affects something becomes a
#   Proposed Planner card "ScalePad Insight - <title>": priority from the
#   risk level, the description, affected count, 30-day trend and (for
#   hardware insights) the affected devices. Re-runs refresh the card's
#   text only - status and priority the partner has changed are kept.
#   Insights with nothing affected, or not yet evaluated, go in the report only.
# =====================================================================
$phase = 'insights'
$results = ConvertTo-Dict (Get-P $ctx 'results')
$settings = Get-P $ctx 'settings'
$companyId = [int](Get-P $ctx 'companyId')
$spClientId = [string](Get-P $ctx 'scalePadClientId')
$counts = [ordered]@{ insights = 0; active = 0; toCreate = 0; toUpdate = 0; created = 0; updated = 0; closed = 0; reopened = 0; errors = 0 }
$items = New-Object System.Collections.ArrayList
$table = New-Object System.Collections.ArrayList
$PriorityMap = @{ high = 1; medium = 0; low = -1 }
function ConvertTo-Html { param($s) return [System.Net.WebUtility]::HtmlEncode([string]$s) }

if ((Get-P $ctx 'phases' @()) -notcontains $phase) {
    $results[$phase] = [ordered]@{ ran = $false }
}
else {
    $cards = @{}
    foreach ($p in @(Get-CrAll "/v2/odata/product?`$filter=companyId eq $companyId&`$select=productId,subject,status")) { $cards[([string](Get-P $p 'subject')).ToLowerInvariant()] = $p }
    function Test-CardCompleted { param($card) $st = [string](Get-P $card 'status' ''); return ($st -eq '40' -or $st -match '(?i)^completed$') }

    # The insights list takes only a client filter (no paging parameters).
    $insights = @(Get-SpAll '/lifecycle-manager/v1/insights' @{ 'filter[client.id]' = "eq:$spClientId" } -MaxPages 1)
    $counts.insights = $insights.Count
    $maxDevices = [int](Get-P $settings 'insightDeviceLimit' 25)

    foreach ($i in $insights) {
        $title = [string](Get-P $i 'title' 'Insight')
        $affected = [int](Get-P $i 'affected_count' 0)
        $trend = Get-P $i 'trend_value'
        $risk = [string](Get-P $i 'risk_level' '')
        $state = [string](Get-P $i 'state' '')
        $cat = [string](Get-P $i 'category_label' (Get-P $i 'category' ''))
        $null = $table.Add([ordered]@{ insight = $title; category = $cat; risk = $risk; affected = $affected; trend = $trend; state = $state })
        if ($affected -le 0 -or $state -in @('prerequisite', 'initial')) {
            # Cleared: close its card if one is still open.
            $open = $cards[("ScalePad Insight - $title").ToLowerInvariant()]
            if ($affected -le 0 -and $null -ne $open -and -not (Test-CardCompleted $open)) {
                $counts.closed++
                $null = $items.Add(@{ subject = "ScalePad Insight - $title"; action = 'complete' })
                if ($apply) {
                    try { $null = Invoke-Cr -Method PATCH -Path "/v2/product/$(Get-P $open 'productId')" -Body (New-PatchOps @{ status = 40; summary = "Resolved - 0 affected as of $(Format-Day (Get-Date))." }) }
                    catch { $counts.errors++; Warn "Couldn't close the card for '$title': $($_.Exception.Message)" }
                }
            }
            continue
        }
        $counts.active++

        # Affected devices, for hardware insights.
        $devices = @()
        if ([string](Get-P $i 'asset_scope' '') -eq 'Hardware') {
            try {
                $q = @{ client_id = $spClientId }
                $devices = @(Get-SpAll "/lifecycle-manager/v1/insights/$(Get-P $i 'insight_id')/assets" $q -PageSize 100 -MaxPages 3)
            } catch { Warn "Couldn't list devices for insight '$title': $($_.Exception.Message)" }
        }
        $trendText = if ($null -eq $trend) { '' } elseif ([int]$trend -gt 0) { " (up $trend in 30 days)" } elseif ([int]$trend -lt 0) { " (down $([Math]::Abs([int]$trend)) in 30 days)" } else { ' (no change in 30 days)' }
        $body = "<p>$(ConvertTo-Html (Get-P $i 'description' ''))</p><p><b>Affected:</b> $affected$(ConvertTo-Html $trendText). <b>Risk:</b> $(ConvertTo-Html $risk). <b>Category:</b> $(ConvertTo-Html $cat).</p>"
        if ($devices.Count) {
            $body += '<p><b>Affected devices:</b></p><ul>' + ((@($devices | Select-Object -First $maxDevices | ForEach-Object { "<li>$(ConvertTo-Html (Get-P $_ 'name' '')) - $(ConvertTo-Html (Get-P $_ 'serial_number' ''))$(if (Get-P $_ 'warranty_expires_at') { ', warranty ' + (Format-Day (Get-P $_ 'warranty_expires_at')) })</li>" })) -join '') + '</ul>'
            if ($devices.Count -gt $maxDevices) { $body += "<p>...and $($devices.Count - $maxDevices) more in ScalePad.</p>" }
        }
        $body += '<p><i>From ScalePad Lifecycle Manager insights, via the ScalePad to CloudRadial Sync.</i></p>'
        $summary = "$affected affected$trendText - $risk risk, $cat."
        $subject = "ScalePad Insight - $title"

        $existing = $cards[$subject.ToLowerInvariant()]
        if ($null -ne $existing) {
            $counts.toUpdate++
            $null = $items.Add(@{ subject = $subject; action = 'update'; affected = $affected })
            if ($apply) {
                # Text only: keep whatever status/priority the partner has set since.
                $fix = @{ summary = $summary; body = $body }
                if (Test-CardCompleted $existing) { $fix.status = 0; $counts.reopened++ }   # the insight is back - reopen as Proposed
                try { $null = Invoke-Cr -Method PATCH -Path "/v2/product/$(Get-P $existing 'productId')" -Body (New-PatchOps $fix); $counts.updated++ }
                catch { $counts.errors++; Warn "Update failed for '$subject': $($_.Exception.Message)" }
            }
            continue
        }
        $counts.toCreate++
        $null = $items.Add(@{ subject = $subject; action = 'create'; affected = $affected; risk = $risk })
        if ($apply) {
            $new = [ordered]@{ companyId = $companyId; subject = $subject; summary = $summary; body = $body
                category = [string](Get-P $settings 'insightCategory' (Get-P $settings 'roadmapCategory' 'Efficiency')); productCategoryId = [int](Get-P $settings 'insightCategoryId' (Get-P $settings 'roadmapCategoryId' 7))
                status = 0; priority = $(if ($PriorityMap.ContainsKey($risk.ToLowerInvariant())) { $PriorityMap[$risk.ToLowerInvariant()] } else { 0 })
                isRequired = $false; isShowPrice = $false; isClientVisible = $false }
            try { $null = Invoke-Cr -Method POST -Path '/v2/product' -Body $new; $counts.created++ }
            catch { $counts.errors++; Warn "Create failed for '$subject': $($_.Exception.Message)" }
        }
    }
    $results[$phase] = [ordered]@{ ran = $true; counts = $counts; items = @($items); table = @($table) }
}

$ctx.results = $results
$ctx.warnings = @(@(Get-P $ctx 'warnings' @()) + @($warnings))
$c = $counts
Set-NodeOutput @{ status = 'ok'; message = "Insights: $($c.insights) in ScalePad, $($c.active) with affected assets; $(if ($apply) { "$($c.created) Planner cards created, $($c.updated) updated" } else { "$($c.toCreate) cards to create, $($c.toUpdate) to update" })$(if ($c.closed) { ", $($c.closed) closed as resolved" })$(if ($c.reopened) { ", $($c.reopened) reopened" }), $($c.errors) errors."; ctx = $ctx }
