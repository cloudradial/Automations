# Strict-mode tests for _shared/cloudradial.ps1: connect, retry, OData and beta paging,
# Planner card create/update without duplicates, and Report Archive writes.
. (Join-Path $PSScriptRoot 'mock.ps1')

$CrBase = 'https://api.us.cloudradial.example'
$Sec = @{ 'CloudRadial-BaseUrl' = "$CrBase/"; 'CloudRadial-PublicKey' = 'pub'; 'CloudRadial-PrivateKey' = 'priv' }

# --- connect ---
Reset-Mock @{ 'CloudRadial-BaseUrl' = $CrBase } $null
Invoke-WithLib @('cloudradial.ps1') {
    $m = Get-ThrowMessage { Connect-Cr }
    Check 'Connect-Cr: missing secrets are named' ($m -match 'CloudRadial-PublicKey' -and $m -match 'CloudRadial-PrivateKey' -and $m -notmatch 'BaseUrl') $m
    $m = Get-ThrowMessage { Invoke-CrApi '/v2/odata/company' }
    Check 'calls before Connect-Cr say so' ($m -match 'Connect-Cr') $m
}

# --- retry and paging ---
Reset-Mock $Sec.Clone() {
    param($c, $n)
    if ($c.Uri -like '*/v2/odata/company*' -and $n -eq 1) { New-HttpError 429 '' '3' }
    if ($c.Uri -like '*/v2/odata/endpoint?$filter=companyId eq 7&$top=200&$skip=0') { return [pscustomobject]@{ value = @(1..200 | ForEach-Object { [pscustomobject]@{ companyEndpointId = $_ } }) } }
    if ($c.Uri -like '*/v2/odata/endpoint?$filter=companyId eq 7&$top=200&$skip=200') { return [pscustomobject]@{ value = @(201..250 | ForEach-Object { [pscustomobject]@{ companyEndpointId = $_ } }) } }
    if ($c.Uri -like '*/api/beta/archive?Skip=0&Take=100') { return @(1..100 | ForEach-Object { [pscustomobject]@{ id = $_ } }) }
    if ($c.Uri -like '*/api/beta/archive?Skip=100&Take=100') { return @([pscustomobject]@{ id = 101 }) }
    if ($c.Uri -like '*/v2/product/9') { New-HttpError 400 '{"message":"bad"}' }
    return [pscustomobject]@{ value = @([pscustomobject]@{ companyId = 7 }) }
}
Invoke-WithLib @('cloudradial.ps1') {
    $null = Connect-Cr
    $c = @(Get-CrAll '/v2/odata/company')
    $first = @($Mock.Calls)[0]
    Check 'Connect-Cr: basic auth from the key pair, trailing slash trimmed' ($first.Headers.Authorization -eq "Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('pub:priv')))" -and $first.Uri -like "$CrBase/v2/odata/company?*") $first.Uri
    Check 'Invoke-CrApi: 429 retried after Retry-After' ($c.Count -eq 1 -and (@($Mock.Sleeps) -join ',') -eq '3') "sleeps=$(@($Mock.Sleeps) -join ',')"
    $e = @(Get-CrAll '/v2/odata/endpoint?$filter=companyId eq 7')
    Check 'Get-CrAll: pages with $top/$skip until a short page' ($e.Count -eq 250 -and @(Get-Calls 'GET' '*/v2/odata/endpoint*').Count -eq 2) (Show-Calls)
    $a = @(Get-CrBetaAll '/api/beta/archive')
    Check 'Get-CrBetaAll: pages with Skip/Take' ($a.Count -eq 101 -and @(Get-Calls 'GET' '*/api/beta/archive*').Count -eq 2) (Show-Calls)
    $m = Get-ThrowMessage { Invoke-CrApi '/v2/product/9' -Method PATCH -Body @() }
    Check 'Invoke-CrApi: errors name the call and status, no retry on 400' ($m -match '^CloudRadial PATCH /v2/product/9 failed \(HTTP 400\)' -and @(Get-Calls 'PATCH' '*/v2/product/9').Count -eq 1) $m
}

# --- Planner cards ---
$cards = @(
    [pscustomobject]@{ productId = 11; companyId = 7; subject = 'Endpoint Hardware Refresh - Replace'; body = '<p>old</p>'; status = 0 }
    [pscustomobject]@{ productId = 12; companyId = 7; subject = 'Renamed by a technician'; body = '<p>x</p><p><em>Refresh Plan Card: company 7 / Retain</em></p>'; status = 40 }
)
Reset-Mock $Sec.Clone() {
    param($c, $n)
    if ($c.Uri -like '*/v2/odata/product*') { return [pscustomobject]@{ value = $cards } }
    if ($c.Method -eq 'POST' -and $c.Uri -eq "$CrBase/v2/product") {
        if ($c.Body -match '"notes"' -and $c.Body -match 'Old portal') { New-HttpError 400 '{"message":"Unknown field notes"}' }
        return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ productId = 99 } }
    }
    if ($c.Method -eq 'PATCH' -and $c.Body -match '/notes' -and $c.Body -match 'Old portal') { New-HttpError 400 '{"message":"Unknown field notes"}' }
    return $null
}
Invoke-WithLib @('cloudradial.ps1') {
    $null = Connect-Cr
    $r = Set-CrPlannerCard -CompanyId 7 -Subject 'Endpoint Hardware Refresh - Replace' -Fields @{ body = '<p>2 computers</p>'; summary = '2 computers are due for replacement.'; priority = 1 }
    $c = Get-LastCall; $ops = Read-Body $c
    Check 'Set-CrPlannerCard: same subject updates the card (no duplicate)' ($r.action -eq 'updated' -and $r.productId -eq '11' -and $c.Method -eq 'PATCH' -and $c.Uri -eq "$CrBase/v2/product/11" -and $c.ContentType -eq 'application/json-patch+json' -and @(Get-Calls 'POST' '*/v2/product').Count -eq 0) "$($c.Method) $($c.Uri)"
    Check 'Set-CrPlannerCard: PATCH is json-patch replace ops' (@($ops | Where-Object { $_.op -eq 'replace' -and $_.path -eq '/summary' }).Count -eq 1 -and @($ops | Where-Object { $_.path -eq '/subject' }).Count -eq 1) $c.Body

    $r = Set-CrPlannerCard -CompanyId 7 -Subject 'Endpoint Hardware Refresh - Retain' -Key 'Refresh Plan Card: company 7 / Retain' -Fields @{ body = '<p>1 computer</p>'; status = 0 }
    $ops = Read-Body (Get-LastCall)
    Check 'Set-CrPlannerCard: finds a renamed card by its key and reopens it' ($r.action -eq 'updated' -and $r.productId -eq '12' -and @($ops | Where-Object { $_.path -eq '/status' -and $_.value -eq 0 }).Count -eq 1) (Get-LastCall).Body
    Check 'Set-CrPlannerCard: key added to the body' (@($ops | Where-Object { $_.path -eq '/body' -and $_.value -like '*<em>Refresh Plan Card: company 7 / Retain</em>*' }).Count -eq 1) (Get-LastCall).Body

    $r = Set-CrPlannerCard -CompanyId 7 -Subject 'Endpoint Hardware Refresh - Needs data' -Fields @{ body = '<p>3 computers</p>'; category = 'Efficiency'; productCategoryId = 7; priority = 0 }
    $c = Get-LastCall; $b = Read-Body $c
    Check 'Set-CrPlannerCard: no match creates one' ($r.action -eq 'created' -and $r.productId -eq '99' -and $c.Method -eq 'POST' -and $b.companyId -eq 7 -and $b.subject -eq 'Endpoint Hardware Refresh - Needs data' -and $b.isClientVisible -eq $false -and $b.status -eq 0 -and $b.productCategoryId -eq 7 -and $null -ne $b.datePublished) $c.Body
    Check 'Set-CrPlannerCard: a build''s own category is kept' ($b.category -eq 'Efficiency' -and $b.productCategoryId -eq 7) $c.Body
    $r = Set-CrPlannerCard -CompanyId 7 -Subject 'Reclaim unused Microsoft 365 licences' -Fields @{ body = '<p>2 licences</p>'; summary = '2 unused licences'; priority = 0 }
    $c = Get-LastCall; $b = Read-Body $c
    Check 'Set-CrPlannerCard: a new card with no category gets the default category and product category (CloudRadial requires one)' ($r.action -eq 'created' -and $c.Method -eq 'POST' -and $b.category -eq 'Efficiency' -and $b.productCategoryId -eq 7) $c.Body
    $r = Set-CrPlannerCard -CompanyId 7 -Subject 'Another new card' -Fields @{ body = 'x'; category = 'Security'; productCategoryId = 3 }
    $b = Read-Body (Get-LastCall)
    Check 'Set-CrPlannerCard: an explicit category and product category are never replaced' ($b.category -eq 'Security' -and $b.productCategoryId -eq 3) (Get-LastCall).Body
    $r = Set-CrPlannerCard -CompanyId 7 -Subject 'Endpoint Hardware Refresh - Replace' -Fields @{ summary = 'update only' }
    $c = Get-LastCall
    Check 'Set-CrPlannerCard: an update does not add a category' ($c.Method -eq 'PATCH' -and $c.Body -notmatch '/category' -and $c.Body -notmatch '/productCategoryId') $c.Body

    $before = $Mock.Calls.Count
    $r1 = Set-CrPlannerCard -CompanyId 7 -Subject 'Endpoint Hardware Refresh - Replace' -Existing $cards -Preview
    $r2 = Set-CrPlannerCard -CompanyId 7 -Subject 'Something new' -Existing $cards -Preview
    Check 'Set-CrPlannerCard: -Preview and -Existing make no calls' ($r1.action -eq 'would-update' -and $r2.action -eq 'would-create' -and $Mock.Calls.Count -eq $before) "$($r1.action) $($r2.action)"
    $r = Set-CrPlannerCard -CompanyId 8 -Subject 'Endpoint Hardware Refresh - Replace' -Existing $cards -Preview
    Check 'Set-CrPlannerCard: another company''s card is never matched' ($r.action -eq 'would-create') $r.action

    $r = Set-CrPlannerCard -CompanyId 7 -Subject 'Endpoint Hardware Refresh - Replace' -Existing $cards -Fields @{ body = 'Old portal'; notes = 'internal' }
    $patches = @(Get-Calls 'PATCH' "$CrBase/v2/product/11")
    Check 'Set-CrPlannerCard: update retries without optional fields an old portal refuses' ($r.optionalFieldsDropped -and (Get-LastCall).Body -notmatch '/notes' -and $patches.Count -ge 2) (Get-LastCall).Body
    $r = Set-CrPlannerCard -CompanyId 7 -Subject 'Brand new' -Existing $cards -Fields @{ body = 'Old portal'; notes = 'internal' }
    Check 'Set-CrPlannerCard: create retries without optional fields' ($r.action -eq 'created' -and $r.optionalFieldsDropped -and (Get-LastCall).Body -notmatch '"notes"') (Get-LastCall).Body
}

# --- Report Archives (v2 archive folder API) ---
# The mock folder list answers the company filter the way the API does: only that company's folders.
$folders = New-Object System.Collections.ArrayList
$null = $folders.Add([pscustomobject]@{ companyReportFolderId = 5; companyId = 99; name = 'Weekly Fleet Audit' })   # another company, same name
$items = New-Object System.Collections.ArrayList
$ArchState = @{ dupOnCreate = $false; unwrapped = $false }
Reset-Mock $Sec.Clone() {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/v2/odata/archivefolder*') {
        $cid = [regex]::Match($u, 'companyId eq (\d+)').Groups[1].Value
        return [pscustomobject]@{ value = @($folders | Where-Object { [string]$_.companyId -eq $cid }) }
    }
    if ($c.Method -eq 'POST' -and $c.Uri -eq "$CrBase/v2/archivefolder") {
        $b = $c.Body | ConvertFrom-Json
        if ($ArchState.unwrapped) { return [pscustomobject]@{ archiveFolderId = 33; companyId = $b.companyId; name = $b.name; inboundEmailAddress = 'z@reports.example' } }
        if ($ArchState.dupOnCreate) { $null = $folders.Add([pscustomobject]@{ companyReportFolderId = 32; companyId = $b.companyId; name = $b.name }); New-HttpError 400 '{"success":false,"message":"A folder with this name already exists."}' }
        $null = $folders.Add([pscustomobject]@{ companyReportFolderId = 31; companyId = $b.companyId; name = $b.name; inboundEmailAddress = 'x@reports.example' })
        return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ archiveFolderId = 31; companyId = $b.companyId; name = $b.name; inboundEmailAddress = 'x@reports.example' } }
    }
    if ($c.Uri -like '*/api/beta/archive*') { throw 'the legacy archive route must not be used when v2 answers' }
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/v2/odata/archiveitem*') { return [pscustomobject]@{ value = @($items) } }
    if ($c.Method -eq 'POST' -and $c.Uri -eq "$CrBase/v2/archiveitem") { $null = $items.Add([pscustomobject]@{ companyReportItemId = 401; subject = ($c.Body | ConvertFrom-Json).subject }); return [pscustomobject]@{ companyReportItemId = 401 } }
    return $null
}
Invoke-WithLib @('cloudradial.ps1') {
    $null = Connect-Cr
    $r = Add-CrArchiveReport -CompanyId 7 -ArchiveName 'Weekly Fleet Audit' -Subject 'Fleet audit - Contoso' -Html '<p>All good.</p>' -Preview
    Check 'Add-CrArchiveReport: preview writes nothing' ($r.action -eq 'would-write' -and @($Mock.Calls | Where-Object { $_.Method -ne 'GET' }).Count -eq 0) (Show-Calls)
    $list = @(Get-Calls 'GET' '*/v2/odata/archivefolder*')
    Check 'Get-CrArchive: lists folders through v2, filtered to the company' ($list.Count -ge 1 -and [uri]::UnescapeDataString($list[0].Uri) -like '*$filter=companyId eq 7*') (Show-Calls)
    $r = Add-CrArchiveReport -CompanyId 7 -ArchiveName 'Weekly Fleet Audit' -Subject 'Fleet audit - Contoso' -Html '<p>All good.</p>'
    $create = @(Get-Calls 'POST' "$CrBase/v2/archivefolder")
    $post = @(Get-Calls 'POST' "$CrBase/v2/archiveitem")
    $b = Read-Body $post[0]
    Check 'Add-CrArchiveReport: creates the company''s folder through v2 (ignores another company''s)' ($create.Count -eq 1 -and (Read-Body $create[0]).companyId -eq 7 -and (Read-Body $create[0]).name -eq 'Weekly Fleet Audit' -and (Read-Body $create[0]).category -eq 'AutomationAI' -and $r.archiveId -eq 31) (Show-Calls)
    Check 'Add-CrArchiveReport: posts an HTML item into it' ($post.Count -eq 1 -and $b.archiveId -eq 31 -and $b.companyId -eq 7 -and $b.isHtml -eq $true -and $b.subject -eq 'Fleet audit - Contoso' -and $r.action -eq 'created' -and $r.location -match 'admins only') $post[0].Body
    Check 'Add-CrArchiveReport: never writes a KB article or uses the legacy route' (@($Mock.Calls | Where-Object { $_.Uri -like '*/article*' -or $_.Uri -like '*/api/beta/*' }).Count -eq 0) (Show-Calls)
    $Mock.Calls.Clear()
    $r = Add-CrArchiveReport -CompanyId 7 -ArchiveName 'weekly fleet audit' -Subject 'Fleet audit - Contoso' -Html '<p>Two warnings.</p>' -IsError
    $put = Get-LastCall
    Check 'Add-CrArchiveReport: the folder name matches in any case, and the same subject replaces the item' ($r.action -eq 'updated' -and $put.Method -eq 'PUT' -and $put.Uri -eq "$CrBase/v2/archiveitem/31/401" -and (Read-Body $put).isError -eq $true -and @(Get-Calls 'POST' '*').Count -eq 0) (Show-Calls)
    $a = Get-CrArchive -CompanyId 7 -Name 'Weekly Fleet Audit'
    Check 'Get-CrArchive: returns the id and the folder''s inbound address' ($a.id -eq 31 -and $a.inboundAddress -eq 'x@reports.example') ($a | ConvertTo-Json -Compress)
    $ArchState.unwrapped = $true
    $a = Get-CrArchive -CompanyId 6 -Name 'Monthly Review' -Create
    Check 'Get-CrArchive: a create reply without the data wrapper still gives the id and inbound address' ($a.id -eq 33 -and $a.inboundAddress -eq 'z@reports.example') ($a | ConvertTo-Json -Compress)
    $ArchState.unwrapped = $false
    $ArchState.dupOnCreate = $true
    $a = Get-CrArchive -CompanyId 8 -Name 'Onboarding' -Create
    Check 'Get-CrArchive: a 400 on create (made by another run meanwhile) finds the folder instead of failing' ($a.id -eq 32) ($a | ConvertTo-Json -Compress)
}

# --- Report Archives on a portal without the v2 folder routes: the legacy route, for the rest of the run ---
$archives = New-Object System.Collections.ArrayList
$null = $archives.Add([pscustomobject]@{ id = 5; companyId = 99; name = 'Weekly Fleet Audit' })
$items.Clear()
Reset-Mock $Sec.Clone() {
    param($c, $n)
    if ($c.Uri -like '*/v2/odata/archivefolder*' -or $c.Uri -like '*/v2/archivefolder*') { New-HttpError 404 '' }
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/api/beta/archive?*') { return @($archives) }
    if ($c.Method -eq 'POST' -and $c.Uri -eq "$CrBase/api/beta/archive") { $b = $c.Body | ConvertFrom-Json; $null = $archives.Add([pscustomobject]@{ id = 41; companyId = $b.companyId; name = $b.name; inboundAddress = 'y@reports.example' }); return [pscustomobject]@{ success = $true } }
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/v2/odata/archiveitem*') { return [pscustomobject]@{ value = @($items) } }
    if ($c.Method -eq 'POST' -and $c.Uri -eq "$CrBase/v2/archiveitem") { $null = $items.Add([pscustomobject]@{ companyReportItemId = 402; subject = ($c.Body | ConvertFrom-Json).subject }); return [pscustomobject]@{ companyReportItemId = 402 } }
    return $null
}
Invoke-WithLib @('cloudradial.ps1') {
    $null = Connect-Cr
    $r = Add-CrArchiveReport -CompanyId 7 -ArchiveName 'Weekly Fleet Audit' -Subject 'Fleet audit - Contoso' -Html '<p>All good.</p>'
    Check 'legacy portal: a 404 on the v2 folder list falls back to /api/beta/archive' ($r.action -eq 'created' -and $r.archiveId -eq 41 -and @(Get-Calls 'POST' "$CrBase/api/beta/archive").Count -eq 1 -and @(Get-Calls 'GET' '*/v2/odata/archivefolder*').Count -eq 1) (Show-Calls)
    $null = Get-CrArchive -CompanyId 7 -Name 'Weekly Fleet Audit'
    Check 'legacy portal: the v2 route is not tried again in the same run' (@(Get-Calls 'GET' '*/v2/odata/archivefolder*').Count -eq 1) (Show-Calls)
}

# --- per-company CloudRadial keys ($global:NcoCrSecretSuffix) ---
Reset-Mock (@{ 'CloudRadial-BaseUrl' = $CrBase; 'CloudRadial-PublicKey' = 'pub'; 'CloudRadial-PrivateKey' = 'priv'; 'CloudRadial-PublicKey-fabrikam' = 'pubF' }) $null
Invoke-WithLib @('cloudradial.ps1') {
    Check 'Get-CrSecret: no suffix set reads the shared keys (strict mode)' ((Get-CrSecret 'CloudRadial-PublicKey') -eq 'pub') ''
    $global:NcoCrSecretSuffix = 'fabrikam'
    try {
        Check 'Get-CrSecret: a suffix reads <Name>-<suffix>' ((Get-CrSecret 'CloudRadial-PublicKey') -eq 'pubF') ''
        $m = Get-ThrowMessage { Get-CrSecret 'CloudRadial-PrivateKey' }
        Check 'Get-CrSecret: a missing suffixed secret is named, never the shared one used instead' ($m -like '*CloudRadial-PrivateKey-fabrikam*') $m
    }
    finally { Remove-Variable -Name NcoCrSecretSuffix -Scope Global -ErrorAction SilentlyContinue }
}

# --- assessments from JSON (Sync-CrAssessment) ---
$AsRows = New-Object System.Collections.ArrayList
Reset-Mock $Sec.Clone() {
    param($c, $n)
    if ($c.Method -eq 'GET' -and $c.Uri -like '*/v2/odata/assessment*') { return [pscustomobject]@{ value = @($AsRows) } }
    if ($c.Method -eq 'POST' -and $c.Uri -eq "$CrBase/v2/assessment") { return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ assessmentId = 301; type = 20 } } }
    if ($c.Method -eq 'PUT' -and $c.Uri -like '*/v2/assessment/*/questions*') { $q = @((Read-Body $c).questions); return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ added = 0; updated = $q.Count; removed = $(if ((Read-Body $c).PSObject.Properties['removeMissing'] -and (Read-Body $c).removeMissing) { 3 } else { 0 }) } } }
    if ($c.Method -eq 'PATCH' -and $c.Uri -like '*/answers*') { return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ updated = @((Read-Body $c).answers).Count; scores = [pscustomobject]@{ totalScore = 1; maxScore = 4 } } } }
    if ($c.Method -eq 'POST' -and $c.Uri -like '*/run') { return [pscustomobject]@{ success = $true; data = [pscustomobject]@{ assessmentId = 302; type = 30; totalScore = 1; compliantScore = 2; partialScore = 1; maxScore = 4; questionCount = 2 } } }
    return $null
}
Invoke-WithLib @('cloudradial.ps1') {
    $null = Connect-Cr
    $qs = @(@{ updateKey = 'mfa'; label = 'MFA for all users'; category = 'Identity'; value = 2; publicNotes = '12 of 12' }, @{ updateKey = 'backup'; label = 'Backups tested'; category = 'Data'; value = 1; remediationInfo = 'Test a restore.' })
    $r = Sync-CrAssessment -CompanyId 7 -Title 'Contoso Security Review' -Questions $qs -Category 'Security' -RunName 'Contoso Security Review - 11/13/26'
    $create = Read-Body @(Get-Calls 'POST' "$CrBase/v2/assessment")[0]
    Check 'assessment: created from JSON as type 20 with its questions, no upload' ($r.action -eq 'created' -and $r.assessmentId -eq 301 -and $create.type -eq 20 -and $create.companyId -eq 7 -and @($create.questions).Count -eq 2 -and @(Get-Calls 'POST' '*/upload*').Count -eq 0) (Show-Calls)
    Check 'assessment: questions carry structure only, choice type and the five answer options' ($create.questions[0].type -eq 80 -and @($create.questions[0].answerOptions).Count -eq 5 -and $null -eq $create.questions[0].PSObject.Properties['value'] -and $create.questions[1].remediationInfo -eq 'Test a restore.') ($create.questions | ConvertTo-Json -Depth 5 -Compress)
    $ans = Read-Body @(Get-Calls 'PATCH' '*/v2/assessment/301/answers?companyId=7')[0]
    Check 'assessment: answers set in one call by updateKey, with notes' (@($ans.answers).Count -eq 2 -and $ans.answers[0].updateKey -eq 'mfa' -and $ans.answers[0].value -eq 2 -and $ans.answers[0].publicNotes -eq '12 of 12' -and $ans.answers[1].value -eq 1) ($ans | ConvertTo-Json -Depth 5 -Compress)
    $run = Read-Body @(Get-Calls 'POST' '*/v2/assessment/301/run')[0]
    Check 'assessment: a run is created after the answers, and its scores returned' ($r.runId -eq 302 -and $run.name -eq 'Contoso Security Review - 11/13/26' -and $run.companyId -eq 7 -and $r.scores.totalScore -eq 1 -and (@($Mock.Calls).IndexOf(@(Get-Calls 'PATCH' '*/answers*')[0]) -lt @($Mock.Calls).IndexOf(@(Get-Calls 'POST' '*/run')[0]))) (Show-Calls)
}
$null = $AsRows.Add([pscustomobject]@{ assessmentId = 290; companyId = 7; title = 'Contoso Security Review'; type = 'Assessment_Run'; isDeleted = $false })
$null = $AsRows.Add([pscustomobject]@{ assessmentId = 280; companyId = 7; title = 'contoso security review '; type = 'Assessment'; isDeleted = $false })
$Mock.Calls.Clear()
Invoke-WithLib @('cloudradial.ps1') {
    $null = Connect-Cr
    $qs = @(@{ updateKey = 'mfa'; label = 'MFA for all users'; value = -2 })
    $p = Sync-CrAssessment -CompanyId 7 -Title 'Contoso Security Review' -Questions $qs -Preview
    Check 'assessment preview: finds the existing assessment, writes nothing' ($p.action -eq 'would-update' -and $p.assessmentId -eq 280 -and @($Mock.Calls | Where-Object { $_.Method -ne 'GET' }).Count -eq 0) (Show-Calls)
    $r = Sync-CrAssessment -CompanyId 7 -Title 'Contoso Security Review' -Questions $qs -RemoveMissing
    $put = Read-Body @(Get-Calls 'PUT' '*/v2/assessment/280/questions?companyId=7')[0]
    Check 'assessment rerun: the same assessment refreshed in place (title matched case-insensitively, runs ignored), never created again' ($r.action -eq 'updated' -and $r.assessmentId -eq 280 -and @(Get-Calls 'POST' "$CrBase/v2/assessment").Count -eq 0 -and $put.removeMissing -eq $true -and $r.removed -eq 3 -and $r.runId -eq 0 -and @(Get-Calls 'POST' '*/run').Count -eq 0) (Show-Calls)
    $m = Get-ThrowMessage { Sync-CrAssessment -CompanyId 7 -Title 'X' -Questions @(@{ updateKey = 'a'; label = 'A' }, @{ updateKey = 'A'; label = 'B' }) }
    Check 'assessment: duplicate updateKeys refused before any write' ($m -match "share the updateKey") $m
}
$big = @(1..1500 | ForEach-Object { @{ updateKey = "c$_"; label = "Control $_"; value = 2 } })
$AsRows.Clear(); $Mock.Calls.Clear()
Invoke-WithLib @('cloudradial.ps1') {
    $null = Connect-Cr
    $r = Sync-CrAssessment -CompanyId 7 -Title 'Big' -Questions $big
    Check 'assessment: over 1,000 questions are sent in chunks of 1,000' ($r.added -eq 1500 -and @((Read-Body @(Get-Calls 'POST' "$CrBase/v2/assessment")[0]).questions).Count -eq 1000 -and @((Read-Body @(Get-Calls 'PUT' '*/questions*')[0]).questions).Count -eq 500 -and @(Get-Calls 'PATCH' '*/answers*').Count -eq 2) (Show-Calls)
}

Complete-Test
