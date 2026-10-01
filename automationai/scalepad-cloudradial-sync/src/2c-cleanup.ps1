#{{COMMON}}
# =====================================================================
# Clean-up (opt-in) - remove duplicate software records the Sync wrote
#   Runs only when the run input has "cleanupDuplicateSoftware": true.
#   Looks only at records the Sync wrote (ScalePad's all-caps categories, or
#   the "Added by ScalePad to CloudRadial Sync" comment) - RMM software is never
#   touched. For each device + product + publisher + version it keeps the oldest
#   record and deletes the extra copies. Deletes happen only with
#   "mode": "apply" AND "confirmCleanup": true; otherwise it lists them.
# =====================================================================
$phase = 'cleanup'
$results = ConvertTo-Dict (Get-P $ctx 'results')
$settings = Get-P $ctx 'settings'
$companyId = [int](Get-P $ctx 'companyId')
$confirmed = [bool](Get-P $settings 'confirmCleanup' $false)
$doDelete = $apply -and $confirmed
$SyncTag = 'Added by ScalePad to CloudRadial Sync'
$counts = [ordered]@{ records = 0; syncRecords = 0; duplicateGroups = 0; toDelete = 0; deleted = 0; errors = 0 }
$sample = New-Object System.Collections.ArrayList

if ((Get-P $ctx 'phases' @()) -notcontains $phase) {
    $results[$phase] = [ordered]@{ ran = $false }
}
else {
    $fields = 'endpointApplicationId,endpointId,name,publisher,display,category,comments,dateCreated'
    $apps = @(Get-CrAll "/v2/odata/endpointapplication?`$filter=companyId eq $companyId&`$select=$fields")
    if ($apps.Count -eq 0) {
        # The company-level read has come back empty on a portal that had software - read per device.
        foreach ($e in @(Get-CrAll "/v2/odata/endpoint?`$filter=companyId eq $companyId&`$select=companyEndpointId")) {
            $eid = [int](Get-P $e 'companyEndpointId')
            try { $apps += @(Get-CrAll "/v2/odata/endpointapplication?`$filter=endpointId eq $eid&`$select=$fields") } catch { Warn "Couldn't read software for endpoint $($eid): $($_.Exception.Message)" }
        }
    }
    $counts.records = $apps.Count
    $mine = @($apps | Where-Object { ([string](Get-P $_ 'category' '')) -cmatch '^[A-Z]+$' -or ([string](Get-P $_ 'comments' '')) -eq $SyncTag })
    $counts.syncRecords = $mine.Count
    $groups = @($mine | Group-Object { '{0}|{1}|{2}|{3}' -f (Get-P $_ 'endpointId'), ([string](Get-P $_ 'name')).ToLowerInvariant(), ([string](Get-P $_ 'publisher')).ToLowerInvariant(), ([string](Get-P $_ 'display')) } | Where-Object { $_.Count -gt 1 })
    $counts.duplicateGroups = $groups.Count
    foreach ($g in $groups) {
        $ordered = @($g.Group | Sort-Object { [int](Get-P $_ 'endpointApplicationId') })
        foreach ($extra in @($ordered | Select-Object -Skip 1)) {
            $id = [int](Get-P $extra 'endpointApplicationId')
            $counts.toDelete++
            if ($sample.Count -lt 25) { $null = $sample.Add([ordered]@{ endpointApplicationId = $id; endpointId = Get-P $extra 'endpointId'; name = Get-P $extra 'name'; version = Get-P $extra 'display'; keep = [int](Get-P $ordered[0] 'endpointApplicationId') }) }
            if ($doDelete) {
                try { $null = Invoke-Cr -Method DELETE -Path "/v2/endpointapplication/$id"; $counts.deleted++ }
                catch { $counts.errors++; if ($counts.errors -le 10) { Warn "Couldn't delete software record $($id): $($_.Exception.Message)" } }
            }
        }
    }
    if ($counts.toDelete -gt 0 -and -not $doDelete) { Warn "$($counts.toDelete) duplicate software records found. Nothing was deleted - run with ""mode"": ""apply"" and ""confirmCleanup"": true to remove them." }
    $results[$phase] = [ordered]@{ ran = $true; counts = $counts; deleted = $doDelete; sample = @($sample) }
}

$ctx.results = $results
$ctx.warnings = @(@(Get-P $ctx 'warnings' @()) + @($warnings))
$c = $counts
Set-NodeOutput @{ status = 'ok'; message = "Clean-up: $($c.records) software records, $($c.syncRecords) written by the Sync, $($c.duplicateGroups) duplicated. $(if ($doDelete) { "$($c.deleted) duplicate copies deleted" } else { "$($c.toDelete) duplicate copies would be deleted (nothing deleted)" }), $($c.errors) errors."; ctx = $ctx }
