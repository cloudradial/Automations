param([string]$Step, [string]$InFile, [string]$OutFile, [string]$ItemFile)
if ($ItemFile) { $item = Get-Content $ItemFile -Raw | ConvertFrom-Json }
$ErrorActionPreference = 'Stop'
$env:RUNNER_KV_NAME = 'kv'
$global:MockWrites = New-Object System.Collections.ArrayList
$secrets = @{ 'ScalePad-ApiUrl' = 'https://sp.test'; 'ScalePad-ApiKey' = 'k'; 'CloudRadial-BaseUrl' = 'https://cr.test'; 'CloudRadial-PublicKey' = 'p'; 'CloudRadial-PrivateKey' = 'q'; }
function Get-AzKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText, $ErrorAction) $secrets[$Name] }
function Get-NodeInput { Get-Content $InFile -Raw | ConvertFrom-Json }
function Set-NodeOutput { param($o) $o | ConvertTo-Json -Depth 30 | Set-Content $OutFile }
$global:MockAssessments = New-Object System.Collections.ArrayList
if ($env:ASSESS_EXISTS) { $null = $global:MockAssessments.Add([pscustomobject]@{ assessmentId = 600; companyId = 9; title = $env:ASSESS_EXISTS; isDeleted = $false }) }
# Like the live route: assessmentId 0 creates the assessment titled by "name" and returns 204 with no body.
function Send-CrMultipart { param($Path, $DataJson, $FileBytes, $FileName) $null = $global:MockWrites.Add("MULTIPART $Path data=$DataJson bytes=$($FileBytes.Length) file=$FileName"); [IO.File]::WriteAllBytes("$PSScriptRoot\last.xlsx", $FileBytes); $d = $DataJson | ConvertFrom-Json; if ($Path -eq '/v2/assessment/upload' -and $d.assessmentId -eq 0 -and $d.type -eq 30 -and -not $env:ASSESS_LAG) { $null = $global:MockAssessments.Add([pscustomobject]@{ assessmentId = 700 + $global:MockAssessments.Count; companyId = $d.companyId; title = $d.name; isDeleted = $false }) }; '' }
function Send-ArchiveUpload { param($ArchiveId, $FilePath, $FileName) if ($ArchiveId -le 0) { throw 'HTTP 400: Sequence contains no elements.' }; $null = $global:MockWrites.Add("UPLOAD archive=$ArchiveId file=$FileName") }
function Invoke-WebRequest { param($Method, $Uri, $Headers, $OutFile) [IO.File]::WriteAllBytes($OutFile, [byte[]](37, 80, 68, 70)); $null = $global:MockWrites.Add("DOWNLOAD $Uri") }

$sp = @{
    '/core/v1/clients'                                   = @{ data = @(@{ id = 'cl1'; name = 'Contoso Group Ltd' }, @{ id = 'cl2'; name = 'Example MSP' }, @{ id = 'cl3'; name = 'No Match Ltd' }, @{ id = 'cl4'; name = 'Contoso Group' }); next_cursor = $null }
    '/core/v1/assets/hardware'                           = @(
        @{ data = @(@{ id = 'h1'; name = 'Contoso-LT68'; serial_number = 'SNLT680001'; type = 'WORKSTATION'; manufacturer = @{ name = 'Lenovo' }; model = @{ description = 'ThinkPad E14 Gen 7' }; software = @{ operating_system = 'Windows 11 Pro'; antivirus_info = @{ status = 'RUNNING' } }; configuration = @{ cpu = @{ name = 'Intel Core Ultra 5' }; ram_bytes = 17179869184 } },
                    @{ id = 'h2'; name = 'Contoso-DT01'; serial_number = 'SNDT010002'; type = 'WORKSTATION'; manufacturer = @{ name = 'Dell' }; model = @{ description = 'OptiPlex 7010' }; software = @{ operating_system = 'Windows 10 Pro' }; configuration = @{ ram_bytes = 8589934592 } }); next_cursor = 'c2' },
        @{ data = @(@{ id = 'h3'; name = 'Contoso-SRV01'; serial_number = 'SNSRV010003'; type = 'SERVER'; manufacturer = @{ name = 'HPE' }; model = @{ description = 'ProLiant DL380' }; software = @{ operating_system = 'Windows Server 2022' } },
                    @{ id = 'h4'; name = 'Draytek 2865'; serial_number = ''; type = 'NETWORK' }, @{ id = 'h6'; name = 'Reception PC'; serial_number = ''; type = 'WORKSTATION'; manufacturer = @{ name = 'HP' } },
                    @{ id = 'h8'; name = 'Contoso-TS02'; serial_number = 'TS02SER'; type = 'WORKSTATION'; manufacturer = @{ name = 'Dell' }; model = @{ description = 'OptiPlex 7090' } }, @{ id = 'h7'; name = 'Contoso-TS01'; serial_number = 'TS01SER'; type = 'WORKSTATION'; manufacturer = @{ name = 'Dell' }; model = @{ description = 'OptiPlex 7090' }; software = @{ operating_system = 'Windows Server 2019 Standard' } }, @{ id = 'h5'; name = 'MacBook'; serial_number = 'C02XYZ'; type = 'WORKSTATION'; manufacturer = @{ name = 'Apple' }; model = @{ description = 'MacBook Pro 14' } }); next_cursor = $null })
    '/lifecycle-manager/v1/assets/hardware/lifecycles'   = @{ data = @(@{ serial_number = 'SNLT680001'; purchase_date = '2026-02-09T00:00:00Z'; warranty_expiry_date = '2029-02-08T00:00:00Z' }, @{ serial_number = 'SNDT010002'; purchase_date = '2021-05-01T00:00:00Z'; warranty_expiry_date = '2024-05-01T00:00:00Z' }); next_cursor = $null }
    '/lifecycle-manager/v1/assets/software'              = @{ data = @(
            @{ hardware_asset = @{ serial_number = 'SNLT680001'; name = 'Contoso-LT68' }; product = @{ name = 'Microsoft 365 Apps'; category = 'Productivity' }; publisher = @{ name = 'Microsoft' }; version = @{ display = '16.0.18526.20168' } },
            @{ hardware_asset = @{ serial_number = 'SNLT680001'; name = 'Contoso-LT68' }; product = @{ name = 'Google Chrome' }; publisher = @{ name = 'Google' }; version = @{ display = '129.0.6668.90' } },
            @{ hardware_asset = @{ serial_number = 'SNDT010002'; name = 'Contoso-DT01' }; product = @{ name = 'Adobe Acrobat' }; publisher = @{ name = 'Adobe' }; version = @{ display = '24.3' } }); next_cursor = $null }
    '/lifecycle-manager/v1/assessments/criteria/labels'  = @{ data = @(@{ type_key = 'yn'; assessment_criterion_labels = @(@{ label_key = 'yes'; label = 'Yes' }, @{ label_key = 'partial'; label = 'Partially' }, @{ label_key = 'no'; label = 'No' }, @{ label_key = 'na'; label = 'Not Applicable' }) }) }
    '/lifecycle-manager/v1/assessments'                  = @{ data = @(@{ id = 'as1'; title = 'Security Baseline'; evaluated_at = '2026-08-01T00:00:00Z'; overall_score = 72 }); next_cursor = $null }
    '/lifecycle-manager/v1/assessments/as1'              = @{ assessment = @{ description = 'Annual baseline'; category_list = @(
                @{ title = 'Access Control'; question_list = @(
                        @{ title = 'MFA enforced for all users?'; description = 'Checks MFA.'; remediation_tips = 'Enable conditional access. Then audit.'; scoring_instructions = 'Yes if 100%.'; criteria_list = @(@{ label_key = 'yes'; display_label = 'Yes'; is_selected = $false }, @{ label_key = 'no'; display_label = 'No'; is_selected = $true }); public_comment = @{ text = 'Two admins lack MFA' }; linked_initiatives = @(@{ initiative_name = 'MFA Rollout' }) },
                        @{ title = 'Password policy set?'; description = 'Checks policy.'; criteria_list = @(@{ label_key = 'yes'; display_label = 'Yes'; is_selected = $true }, @{ label_key = 'partial'; display_label = 'Partially'; is_selected = $false }, @{ label_key = 'na'; display_label = 'Not Applicable'; is_selected = $false }) }) },
                @{ title = 'Backup'; question_list = @(@{ title = 'Offsite backups tested?'; description = 'Restore test.'; criteria_list = @(@{ label_key = 'yes'; display_label = 'Yes'; is_selected = $false }, @{ label_key = 'no'; display_label = 'No'; is_selected = $false }) }) }) } }
    '/lifecycle-manager/v2/initiatives'                  = @{ data = @(@{ id = 'in1'; name = 'Workstation Replacement Q1'; status = 'Approved'; priority = 'High'; fiscal_quarter = @{ year = 2027; quarter = 1 } }); next_cursor = $null }
    '/lifecycle-manager/v1/initiatives/in1'              = @{ initiative = @{ name = 'Workstation Replacement Q1'; status = 'Approved'; priority = 'High'; executive_summary = 'Replace 12 aging desktops.'; fiscal_quarter = @{ year = 2027; quarter = 1 }; budget = @{ currency = @{ code_alpha = 'GBP'; subunit_ratio = 100 }; line_items = @(@{ cost_subunits = 95000; unit_count = 12 }); recurring_line_items = @(@{ cost_subunits = 1200; unit_count = 12; frequency = 'Monthly' }) } } }
    '/core/v1/assets/saas'                               = @{ data = @(@{ id = 'sa1'; product = @{ name = 'Microsoft 365 Business Premium'; category = 'Productivity'; manufacturer = @{ name = 'Microsoft' }; manufacturer_sku = @{ name = 'SPB' } }; status = 'ACTIVE'; tenant_domain = 'contoso.example'; term = @{ starts_at = '2026-01-01T00:00:00Z'; ends_at = '2027-01-01T00:00:00Z'; is_auto_renewed = $true }; pool = @{ capacity = 40; utilized = 37 }; subscriptions = @(@{ billing_cycle_name = 'Monthly'; provider_name = 'Pax8' }) }); next_cursor = $null }
    '/lifecycle-manager/v1/insights'                     = @{ data = @(@{ insight_id = 'i1'; title = 'Warranty expired'; description = 'Devices out of warranty.'; affected_count = 12; trend_value = 2; risk_level = 'High'; category = 'WarrantyCoverage'; category_label = 'Warranty coverage'; asset_scope = 'Hardware'; state = 'normal' }, @{ insight_id = 'i2'; title = 'Backups healthy'; affected_count = 0; risk_level = 'Low'; category_label = 'Backup monitoring'; asset_scope = 'Hardware'; state = 'success' }) }
    '/lifecycle-manager/v1/insights/i1/assets'           = @{ data = @(@{ name = 'Contoso-DT01'; serial_number = 'SNDT010002'; warranty_expires_at = '2024-05-01T00:00:00Z' }); next_cursor = $null }
    '/lifecycle-manager/v1/action-items'                 = @{ data = @(@{ title = 'Order 12 replacement desktops'; due_at = '2027-01-15T00:00:00Z'; is_completed = $false; initiative_links = @{ initiative_name = 'Workstation Replacement Q1' }; meeting_links = @(@{ meeting_id = 'm1'; meeting_title = 'Q2 2026 QBR' }) }, @{ title = 'Review backup retention'; is_completed = $false; initiative_links = $null; meeting_links = @() }); next_cursor = $null }
    '/lifecycle-manager/v1/meetings'                     = @{ data = @(@{ id = 'm2'; title = 'Q3 2026 QBR'; type = 'QBR'; starts_at = '2026-10-15T14:00:00Z'; is_complete = $false; linked_deliverable_count = 0 }, @{ id = 'm1'; title = 'Q2 2026 QBR'; type = 'QBR'; starts_at = '2026-06-30T14:00:00Z'; is_complete = $true; linked_deliverable_count = 1; agenda_json = '{"type":"doc","content":[{"type":"heading","attrs":{"level":1},"content":[{"type":"text","text":"Review"}]},{"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"Warranty","marks":[{"type":"bold"}]},{"type":"text","text":" - 12 devices out"}]}]}]}]}' }); next_cursor = $null }
    '/lifecycle-manager/v1/goals'                        = @{ data = @(@{ title = 'Zero out-of-warranty devices'; status = 'OnTrack'; period = @{ year = 2027; half = 1 }; outcomes = @(@{ label = 'All desktops under warranty'; is_archived = $false }) }); next_cursor = $null }
    '/lifecycle-manager/v1/meetings/m1'                  = @{ meeting = @{ id = 'm1'; title = 'Q2 2026 QBR'; meeting_type = @{ name = 'Business Review' }; starts_at = '2026-06-30T14:00:00Z'; is_complete = $true; contact_attendees = @(@{ first_name = 'Alex'; last_name = 'Sam' }); agenda_json = '{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Discussed refresh budget."}]}]}' } }
    '/lifecycle-manager/v1/meetings/m2'                  = @{ meeting = @{ id = 'm2'; title = 'Q3 2026 QBR'; starts_at = '2026-10-15T14:00:00Z'; is_complete = $false } }
    '/core/v1/service/contracts'                         = @{ data = @(@{ name = 'CON001 Managed Support'; type = 'MANAGED_SERVICES'; status = 'ACTIVE'; term = @{ starts_at = '2025-01-01'; billing_period = 'MONTHLY'; is_auto_renew = $true }; total_price = @{ amount = 2400; iso_currency_code = 'GBP' } }, @{ name = 'SSL Certificate'; type = 'OTHER'; status = 'CANCELLED'; term = @{ billing_period = 'ANNUALLY' }; total_price = @{ amount = 60; iso_currency_code = 'GBP' } }); next_cursor = $null }
    '/lifecycle-manager/v1/deliverables'                 = @{ data = @(@{ id = 'dl1'; name = 'Q2 2026 QBR'; created_at = '2026-06-30T00:00:00Z' }); next_cursor = $null }
}
$cursorCall = @{}
# PRODUCT_STORE=<file>: Planner cards persist across harness runs (POST adds, PATCH applies ops), so a re-run can be checked.
function Get-ProductStore {
    if (Test-Path $env:PRODUCT_STORE) { return @(Get-Content $env:PRODUCT_STORE -Raw | ConvertFrom-Json) }
    return @([pscustomobject]@{ productId = 301; subject = 'ScalePad Initiative - Workstation Replacement Q1'; status = 'InProgress' }, [pscustomobject]@{ productId = 302; subject = 'ScalePad Insight - Backups healthy'; status = 'Proposed' })
}
function Update-ProductStore { param([string]$Method, [string]$Path, [string]$Body)
    $rows = @(Get-ProductStore)
    if ($Method -eq 'POST') { $o = $Body | ConvertFrom-Json; $o | Add-Member -NotePropertyName productId -NotePropertyValue (400 + $rows.Count) -Force; $rows += $o }
    else { $id = [int]($Path -replace '.*/', ''); $row = @($rows | Where-Object { $_.productId -eq $id })[0]; foreach ($op in @($Body | ConvertFrom-Json)) { $row | Add-Member -NotePropertyName ($op.path.TrimStart('/')) -NotePropertyValue $op.value -Force } }
    ConvertTo-Json -InputObject @($rows) -Depth 10 | Set-Content $env:PRODUCT_STORE
}
function Start-Sleep { param($Seconds) $null = $global:MockWrites.Add("sleep $Seconds") }
function Invoke-RestMethod {
    param($Method, $Uri, $Headers, $Body, $ContentType)
    $u = [uri]$Uri
    if ($u.Host -eq 'sp.test') {
        if ($env:FAIL_ROADMAP -and $u.AbsolutePath -eq '/lifecycle-manager/v2/initiatives') { throw 'HTTP 500: boom' }
        if ($env:INSIGHT_STRICT -and $u.AbsolutePath -eq '/lifecycle-manager/v1/insights' -and [uri]::UnescapeDataString($u.Query) -match 'eq:|page_size') { throw 'HTTP 422: Unprocessable Entity' }
        $v = $sp[$u.AbsolutePath]; if ($null -eq $v) { throw "unmocked SP $($u.AbsolutePath)" }
        if ($env:SP_SSL_ONCE -and $u.AbsolutePath -eq '/core/v1/assets/hardware' -and [int](Get-Variable -Name SslN -Scope Global -ValueOnly -ErrorAction SilentlyContinue) -lt [int]$env:SP_SSL_ONCE) { $global:SslN = 1 + [int](Get-Variable -Name SslN -Scope Global -ValueOnly -ErrorAction SilentlyContinue); $null = $global:MockWrites.Add('SSL fail once'); throw 'The SSL connection could not be established, see inner exception.' }
        if ($u.AbsolutePath -eq '/lifecycle-manager/v1/deliverables' -and $u.Query -match 'sort=') { $null = $global:MockWrites.Add('SP400 deliverables sort'); throw 'HTTP 400: sort field not allowed' }
        if ($u.AbsolutePath -eq '/lifecycle-manager/v1/assets/software' -and $u.Query -match 'page_size=(\d+)' -and [int]$Matches[1] -gt 100) { $null = $global:MockWrites.Add("SP400 software page_size $($Matches[1])"); throw 'HTTP 400: page_size must be <= 100' }
        if ($v -is [array]) { $page = if ($u.Query -match 'cursor=c2') { 1 } else { 0 }; return ($v[$page] | ConvertTo-Json -Depth 20 | ConvertFrom-Json) }
        return ($v | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
    }
    if ($u.Host -eq 'api.postmarkapp.com') { $null = $global:MockWrites.Add("POSTMARK to=$(($Body | ConvertFrom-Json).To) attach=$((($Body | ConvertFrom-Json).Attachments)[0].Name)"); return [pscustomobject]@{ ErrorCode = 0; MessageID = 'm1' } }
    if ($env:FAIL_ARCHIVEITEM -and $u.AbsolutePath -eq '/v2/archiveitem') { throw 'HTTP 500: archive write failed' }
    if ($env:ARTICLE_DUMP -and $u.AbsolutePath -eq '/v2/article') { Set-Content $env:ARTICLE_DUMP $Body }
    if ($env:ARCHIVEITEM_DUMP -and $u.AbsolutePath -eq '/v2/archiveitem') { Add-Content $env:ARCHIVEITEM_DUMP ($Body + '<<END>>') }
    if ($Method -in @('POST', 'PATCH', 'PUT', 'DELETE')) {
        $null = $global:MockWrites.Add("$Method $($u.PathAndQuery) $Body".Substring(0, [Math]::Min(420, "$Method $($u.PathAndQuery) $Body".Length)))
        if ($env:PRODUCT_STORE -and $u.AbsolutePath -match '^/v2/product(/\d+)?$') { Update-ProductStore $Method $u.AbsolutePath $Body }
        if ($u.AbsolutePath -eq '/v2/endpoint') { return [pscustomobject]@{ companyEndpointId = 9000 + $global:MockWrites.Count } }
        if ($u.AbsolutePath -eq '/v2/flexible-asset-type') { $global:FaTypeN = 1 + [int](Get-Variable -Name FaTypeN -Scope Global -ValueOnly -ErrorAction SilentlyContinue); return [pscustomobject]@{ id = 60 + $global:FaTypeN } }
        if ($env:FAIL_FAPATCH -and $u.AbsolutePath -like '/v2/flexible-asset/*') { throw 'HTTP 400: bad patch' }
        if ($u.AbsolutePath -eq '/v2/assessment') { throw 'HTTP 404: Not Found' }   # live 2026-10-02: there is no create route
        if ($env:ARCH_EMPTY -and $u.AbsolutePath -eq '/api/beta/archive') { $global:ArchMade = $true; return $null }
        if ($u.AbsolutePath -eq '/api/beta/archive') { return [pscustomobject]@{ id = 77; companyId = 9; name = 'ScalePad QBR History'; inboundAddress = 'contoso-qbr@archive.cloudradial.test' } }
        return [pscustomobject]@{ ok = $true }
    }
    $p = [uri]::UnescapeDataString($u.PathAndQuery)
    switch -Regex ($p) {
        '^/v2/odata/company\?\$filter=companyId eq 9' { return [pscustomobject]@{ value = @([pscustomobject]@{ companyId = 9; name = 'Contoso Group Ltd' }) } }
        '^/v2/odata/company\?\$select' { return [pscustomobject]@{ value = @([pscustomobject]@{ companyId = 9; name = 'Contoso Group Ltd' }, [pscustomobject]@{ companyId = 1; name = 'Example MSP' }) } }
        '^/v2/odata/endpoint\?' { return [pscustomobject]@{ value = @([pscustomobject]@{ companyEndpointId = 1718; serialNumber = 'SNLT680001'; name = 'Contoso-LT68'; manufacturer = 'Lenovo'; model = 'E14'; expirationDate = '2029-02-08T00:00:00Z'; manufacturedDate = $null; os = $null; cpu = $null; memory = 0 }, [pscustomobject]@{ companyEndpointId = 1800; serialNumber = 'TS02SER'; name = 'Contoso-TS02'; manufacturer = 'Dell'; model = 'OptiPlex 7090'; os = 'Windows Server 2016 Standard'; isServer = $false; isVirtual = $false; enclosure = 'Desktop'; cpu = 'x'; memory = 8 }) } }
        '^/v2/odata/endpointapplication\?\$filter=companyId eq 9&\$select=endpointApplicationId' { return [pscustomobject]@{ value = @(
            [pscustomobject]@{ endpointApplicationId = 11; endpointId = 1718; name = 'Windows 11'; publisher = 'Microsoft'; display = '24H2'; category = 'OPERATINGSYSTEM'; comments = $null },
            [pscustomobject]@{ endpointApplicationId = 12; endpointId = 1718; name = 'Windows 11'; publisher = 'Microsoft'; display = '24H2'; category = 'OPERATINGSYSTEM'; comments = $null },
            [pscustomobject]@{ endpointApplicationId = 13; endpointId = 1718; name = 'Zoom'; publisher = 'Zoom Video Communications'; display = '6.1'; category = 'COMMUNICATION'; comments = $null },
            [pscustomobject]@{ endpointApplicationId = 14; endpointId = 1718; name = 'Zoom'; publisher = 'Zoom Video Communications'; display = '6.1'; category = 'COMMUNICATION'; comments = $null },
            [pscustomobject]@{ endpointApplicationId = 15; endpointId = 1718; name = 'Google Chrome'; publisher = ''; display = '129'; category = ''; comments = $null },
            [pscustomobject]@{ endpointApplicationId = 16; endpointId = 1718; name = 'Google Chrome'; publisher = ''; display = '129'; category = ''; comments = $null }) } }
        '^/v2/odata/endpointapplication\?\$filter=companyId' { if ($env:SW_COMPANY_EMPTY) { return [pscustomobject]@{ value = @() } }; return [pscustomobject]@{ value = @([pscustomobject]@{ endpointId = 1718; name = 'Google Chrome'; publisher = 'Google' }) } }
        '^/v2/odata/endpointapplication\?\$filter=endpointId eq 9' { if ($env:SW_EP_FAIL) { throw 'HTTP 500: Internal Server Error' }; return [pscustomobject]@{ value = @() } }
        '^/v2/odata/endpointapplication' { return [pscustomobject]@{ value = @([pscustomobject]@{ endpointId = 1718; name = 'Google Chrome'; publisher = 'Google' }) } }
        '^/v2/odata/flexibleassettype' { if ($env:FA_EXISTS -and $p -notmatch "name eq '(ScalePad Assets|SaaS)'") { return [pscustomobject]@{ value = @() } }; if ($env:FA_EXISTS) { return [pscustomobject]@{ value = @([pscustomobject]@{ id = 41; name = 'ScalePad Assets' }) } }; return [pscustomobject]@{ value = @() } }
        '^/v2/odata/flexibleassetfield' { if ($env:FA_EXISTS) { return [pscustomobject]@{ value = @('Name','Type','Manufacturer','Model','Serial Number','Warranty Expires','ScalePad ID' | ForEach-Object { [pscustomobject]@{ name = $_; nameKey = ($_.ToLower() -replace ' ', '-') } }) } }; return [pscustomobject]@{ value = @() } }
        '^/v2/odata/flexibleasset\?' { if ($env:FA_EXISTS -and $p -notmatch 'flexibleAssetTypeId eq 41') { return [pscustomobject]@{ value = @() } }; if ($env:FA_EXISTS) { return [pscustomobject]@{ value = @([pscustomobject]@{ id = 501; companyId = 9; flexibleAssetTypeId = 41; traitsJson = '{"name":"Draytek 2865","type":"Router","scalepad-id":"h4","model":"old"}' }) } }; return [pscustomobject]@{ value = @() } }
        '^/v2/odata/archiveitem' { if ($env:ARCH_HAS) { return [pscustomobject]@{ value = @([pscustomobject]@{ companyReportItemId = 1; subject = 'ScalePad - Q2 2026 QBR (2026-06-30).pdf' }, [pscustomobject]@{ companyReportItemId = 3; subject = 'ScalePad sync report'; text = 'old report' }, [pscustomobject]@{ companyReportItemId = 2; subject = 'Meeting - Q2 2026 QBR (2026-06-30)'; text = '<h2>Q2 2026 QBR</h2><p>old notes</p>' }) } }; return [pscustomobject]@{ value = @() } }
        '^/v2/odata/article' { if ($env:ART_EXISTS) { return [pscustomobject]@{ value = @([pscustomobject]@{ articleId = 555; subject = 'ScalePad sync report' }) } }; return [pscustomobject]@{ value = @() } }
        '^/v2/odata/assessment' { if ($p -match '\$select') { throw 'HTTP 500: Internal Server Error' }; if ($p -match '\$skip=[1-9]') { return [pscustomobject]@{ value = @() } }; return [pscustomobject]@{ value = @($global:MockAssessments) } }
        '^/v2/odata/product' { if ($env:PRODUCT_SELECT_FAIL -and $p -match 'summary') { throw 'HTTP 400: Could not find a property named summary' }; if ($env:PRODUCT_STORE) { return [pscustomobject]@{ value = @(Get-ProductStore) } }; return [pscustomobject]@{ value = @([pscustomobject]@{ productId = 301; subject = 'ScalePad Initiative - Workstation Replacement Q1'; status = 'InProgress' }, [pscustomobject]@{ productId = 302; subject = 'ScalePad Insight - Backups healthy'; status = 'Proposed' }) } }
        '^/api/beta/archive\?' { if ($env:ARCH_EMPTY -and (Get-Variable -Name ArchMade -Scope Global -ErrorAction SilentlyContinue)) { return @([pscustomobject]@{ id = 86; companyId = 9; name = 'ScalePad QBR History' }, [pscustomobject]@{ id = 87; companyId = 9; name = 'ScalePad Migration' }) }; return @() }
        default { throw "unmocked CR GET $p" }
    }
}
$common = Get-Content "$PSScriptRoot\COMMON.ps1" -Raw
$body = (Get-Content "$PSScriptRoot\$Step" -Raw).Replace('#{{COMMON}}', $common)
$sb = [scriptblock]::Create($body)
Set-StrictMode -Version Latest   # the AutomationAI runner runs scripts in strict mode
try { . $sb } catch { "STEP THREW: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)"; exit 1 }
Set-StrictMode -Off
$o = Get-Content $OutFile -Raw | ConvertFrom-Json
"[$Step] $($o.message)"
foreach ($w in $global:MockWrites) { "   W: $w" }
