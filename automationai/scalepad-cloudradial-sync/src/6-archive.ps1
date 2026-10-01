#{{COMMON}}
# =====================================================================
# Step 6 - Deliverable PDFs -> CloudRadial Report Archive
#   1. Download the PDF from ScalePad to the run's temp folder.
#   2. Upload it to the archive (POST /api/beta/archive/{id}/item).
#   3. If that route rejects the file, list it in the migration report
#      (written to the portal by the summary step) as a manual upload.
#   Nothing is kept after the run.
# =====================================================================
$phase = 'archive'
$results = ConvertTo-Dict (Get-P $ctx 'results')
$settings = Get-P $ctx 'settings'
$companyId = [int](Get-P $ctx 'companyId')
$spClientId = [string](Get-P $ctx 'scalePadClientId')
$counts = [ordered]@{ deliverables = 0; alreadyArchived = 0; toArchive = 0; uploaded = 0; needsManual = 0; errors = 0 }
$items = New-Object System.Collections.ArrayList

if (-not (Get-Command Send-ArchiveUpload -ErrorAction SilentlyContinue)) {
    function script:Send-ArchiveUpload {
        param([int]$ArchiveId, [string]$FilePath, [string]$FileName)
        Add-Type -AssemblyName System.Net.Http
        $client = New-Object System.Net.Http.HttpClient
        $client.DefaultRequestHeaders.Add('Authorization', $crAuth)
        $form = New-Object System.Net.Http.MultipartFormDataContent
        $fc = New-Object System.Net.Http.ByteArrayContent(, [System.IO.File]::ReadAllBytes($FilePath))
        $fc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/pdf')
        $form.Add($fc, 'file', $FileName)
        $resp = $client.PostAsync("$crBase/api/beta/archive/$ArchiveId/item", $form).GetAwaiter().GetResult()
        $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $client.Dispose()
        if (-not $resp.IsSuccessStatusCode) { throw "HTTP $([int]$resp.StatusCode): $text" }
        return $text
    }
}

if ((Get-P $ctx 'phases' @()) -notcontains $phase) {
    $results[$phase] = [ordered]@{ ran = $false }
}
else {
    $archiveName = [string](Get-P $settings 'archiveName' 'ScalePad QBR History')
    $archive = Get-CrArchive -CompanyId $companyId -Name $archiveName -Create:$apply -Category 'QBR'
    if ($null -eq $archive) { Warn "Archive '$archiveName' doesn't exist yet; apply will create it." }
    $archiveId = [int](Get-P $archive 'id' 0)

    $archivedSubjects = New-Object System.Collections.Generic.HashSet[string]
    if ($archiveId -gt 0) {
        try {
            # Documented archive-item list first (paged), then the legacy one; compare names without .pdf.
            # (The legacy list alone did not return usable names, so a re-run uploaded the same PDF again.)
            $existingItems = @()
            try { $existingItems = @(Get-CrAll "/v2/odata/archiveitem?`$filter=companyId eq $companyId and companyReportFolderId eq $archiveId&`$select=companyReportItemId,subject") } catch { }
            try { $existingItems += @(Get-CrBetaAll "/api/beta/archive/$archiveId/item") } catch { }
            foreach ($it in $existingItems) { foreach ($k in @('subject', 'name', 'fileName', 'filename', 'title', 'originalName')) { $nm = [string](Get-P $it $k ''); if ($nm) { $null = $archivedSubjects.Add(($nm -replace '(?i)\.pdf$', '').Trim().ToLowerInvariant()) } } }
        } catch { Warn "Could not list existing archive items; duplicates are possible. $($_.Exception.Message)" }
    }

    # ScalePad has answered this list with 400/422 depending on sort and page size, so fall back
    # step by step, and never let a failed read stop the migration report.
    $deliverables = @()
    $readOk = $false
    foreach ($try in @(@{ q = @{ 'filter[client.id]' = "eq:$spClientId"; sort = '-created_at' }; ps = 100 }, @{ q = @{ 'filter[client.id]' = "eq:$spClientId" }; ps = 100 }, @{ q = @{ 'filter[client.id]' = "eq:$spClientId" }; ps = 25 })) {
        try { $deliverables = @(Get-SpAll '/lifecycle-manager/v1/deliverables' $try.q -PageSize $try.ps); $readOk = $true; break }
        catch { $lastErr = "$_" }
    }
    if (-not $readOk) { $counts.errors++; Warn "Could not read ScalePad deliverables, so no PDFs were archived: $lastErr" }
    $deliverables = @($deliverables | Sort-Object { ConvertTo-IsoDate (Get-P $_ 'created_at') } -Descending)
    $counts.deliverables = $deliverables.Count
    $limit = [int](Get-P $settings 'deliverableLimit' 0)
    if ($limit -le 0) { $limit = [int]::MaxValue }   # default: every deliverable
    foreach ($d in @($deliverables | Select-Object -First $limit)) {
        $dname = [string](Get-P $d 'name' 'Deliverable')
        $created = Format-Day (Get-P $d 'created_at')
        $subject = "ScalePad - $dname$(if ($created) { " ($created)" })"
        $safeName = (($subject -replace '[\\/:*?"<>|]', '-')).ToLowerInvariant()
        if ($archivedSubjects.Contains($subject.ToLowerInvariant()) -or $archivedSubjects.Contains($safeName)) { $counts.alreadyArchived++; continue }
        $counts.toArchive++
        $item = [ordered]@{ deliverable = $dname; subject = $subject; action = 'archive' }
        if ($apply) {
            $file = Join-Path ([System.IO.Path]::GetTempPath()) ("sp-" + [guid]::NewGuid().ToString('N') + '.pdf')
            try {
                $null = Invoke-WithRetry -What "ScalePad PDF $dname" -Call { Invoke-WebRequest -Method Get -Uri "$spBase/lifecycle-manager/v1/deliverables/$(Get-P $d 'id')/pdf" -Headers @{ 'x-api-key' = $spKey; Accept = 'application/pdf' } -OutFile $file }
                $fileName = (($subject -replace '[\\/:*?"<>|]', '-') + '.pdf')
                if ($archiveId -le 0) { throw "the '$archiveName' archive has no id, so nothing was uploaded" }
                $null = Send-ArchiveUpload -ArchiveId $archiveId -FilePath $file -FileName $fileName
                $counts.uploaded++; $item.method = 'api'
            }
            catch { $counts.errors++; $item.error = $_.Exception.Message; Warn "Couldn't upload '$subject' to the '$archiveName' archive: $($_.Exception.Message). Re-run to retry - uploaded PDFs are skipped." }
            finally { if (Test-Path $file) { Remove-Item $file -Force -ErrorAction SilentlyContinue } }
        }
        $null = $items.Add($item)
    }
    if ($limit -lt [int]::MaxValue -and $deliverables.Count -gt $limit) { Warn "Only the newest $limit of $($deliverables.Count) deliverables were processed (deliverableLimit)." }
    $results[$phase] = [ordered]@{ ran = $true; counts = $counts; archiveName = $archiveName; archiveId = $archiveId; items = @($items) }
}

$ctx.results = $results
$ctx.warnings = @(@(Get-P $ctx 'warnings' @()) + @($warnings))
$c = $counts
Set-NodeOutput @{ status = 'ok'; message = "Archive: $($c.deliverables) deliverables, $($c.alreadyArchived) already archived, $(if ($apply) { "$($c.uploaded) uploaded" } else { "$($c.toArchive) to archive" }), $($c.errors) errors."; ctx = $ctx }
