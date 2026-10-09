<#
.SYNOPSIS
    Export and import CloudRadial Service Catalog Question Templates across companies or environments.

.DESCRIPTION
    Sync-QuestionTemplates.ps1 provides a production-grade tool for Partners to manage CloudRadial Question Templates (reusable sets of form fields for Service Catalog items).

    Use this script to:
    - List all Question Templates available in a company
    - Export a template (with all questions and conditional logic) to a JSON file
    - Import a template to another company, with automatic remapping of conditional logic

    The script uses the CloudRadial v2 OData API with Basic Authentication. API credentials are read from environment variables (CLOUDRADIAL_API_USERNAME and CLOUDRADIAL_API_PASSWORD) or prompted interactively.

    When importing, the script appends "(Imported {date})" to the template subject to avoid confusion, and automatically remaps conditional logic (childQuestionIds) so show/hide rules work correctly in the target company.

.PARAMETER Action
    Specifies the operation: List, Export, or Import.
    - List: Display all Question Templates available in the source company.
    - Export: Export a specific template (and all its questions) to a JSON file.
    - Import: Import a previously exported template to a target company.

.PARAMETER BaseUri
    CloudRadial API base URL. Default: https://api.us.cloudradial.com

.PARAMETER TemplateId
    (Export only) Numeric template ID to export. Use -TemplateName as an alternative.

.PARAMETER TemplateName
    (Export only) Partial or full template name to filter. Supports substring matching.

.PARAMETER FilePath
    (Export/Import) Path to the JSON export file.
    - Export: If not specified, defaults to ./QuestionTemplate_Export_{subject}_{date}.json
    - Import: Required; must be a previously exported JSON file.

.PARAMETER TargetCompanyId
    (Import only) Destination company ID. If omitted, defaults to the source company ID from the export file.

.PARAMETER MaxRetries
    Number of retry attempts for API calls on 429 or 5xx errors. Default: 3

.PARAMETER ThrottleMs
    Milliseconds to wait between API calls. Default: 500

.EXAMPLE
    # List all templates in the source company
    .\Sync-QuestionTemplates.ps1 -Action List

.EXAMPLE
    # Export a template by name
    .\Sync-QuestionTemplates.ps1 -Action Export -TemplateName "Support Request"

.EXAMPLE
    # Export a template by ID to a specific file
    .\Sync-QuestionTemplates.ps1 -Action Export -TemplateId 12345 -FilePath C:\backup\template.json

.EXAMPLE
    # Import a template to a different company
    .\Sync-QuestionTemplates.ps1 -Action Import -FilePath C:\backup\template.json -TargetCompanyId 999

.NOTES
    Author: CloudRadial Customer Success
    Requires: PowerShell 5.1 or later
    API Credentials: Set CLOUDRADIAL_API_USERNAME and CLOUDRADIAL_API_PASSWORD environment variables, or you will be prompted.
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('List', 'Export', 'Import')]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [string]$BaseUri = 'https://api.us.cloudradial.com',

    [Parameter(Mandatory = $false)]
    [int]$TemplateId,

    [Parameter(Mandatory = $false)]
    [string]$TemplateName,

    [Parameter(Mandatory = $false)]
    [string]$FilePath,

    [Parameter(Mandatory = $false)]
    [int]$TargetCompanyId,

    [Parameter(Mandatory = $false)]
    [int]$MaxRetries = 3,

    [Parameter(Mandatory = $false)]
    [int]$ThrottleMs = 500
)

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

function Get-CloudRadialCredentials {
    <#
    .SYNOPSIS
        Retrieve API credentials from environment variables or prompt interactively.
    #>
    param()

    $username = $env:CLOUDRADIAL_API_USERNAME
    $password = $env:CLOUDRADIAL_API_PASSWORD

    if (-not $username) {
        $username = Read-Host "Enter CloudRadial API Public Key (username)"
    }
    if (-not $password) {
        $securePass = Read-Host "Enter CloudRadial API Private Key (password)" -AsSecureString
        $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($securePass)
        )
    }

    return @{
        Username = $username
        Password = $password
    }
}

function New-BasicAuthHeader {
    <#
    .SYNOPSIS
        Create a Basic Authentication header for CloudRadial API.
    #>
    param(
        [string]$Username,
        [string]$Password
    )

    $pair = "${Username}:${Password}"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)
    return @{
        'Authorization' = "Basic $base64"
    }
}

function Invoke-CloudRadialApiCall {
    <#
    .SYNOPSIS
        Make an API call to CloudRadial with retry logic for 429 and 5xx errors.
    #>
    param(
        [string]$Uri,
        [string]$Method = 'Get',
        [hashtable]$Headers,
        [object]$Body,
        [int]$MaxRetries = 3,
        [int]$ThrottleMs = 500
    )

    $retryCount = 0
    $backoffMs = 1000

    while ($retryCount -lt $MaxRetries) {
        try {
            $params = @{
                Uri     = $Uri
                Method  = $Method
                Headers = $Headers
            }

            if ($Body) {
                $params['Body'] = $Body
                $params['ContentType'] = 'application/json;odata.metadata=minimal;odata.streaming=true'
            }

            # Throttle between calls
            Start-Sleep -Milliseconds $ThrottleMs

            $response = Invoke-WebRequest @params -ErrorAction Stop
            return $response.Content | ConvertFrom-Json
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.Value__
            $retryCount++

            # Retry on 429 (throttled) or 5xx (server error)
            if ($statusCode -eq 429 -or ($statusCode -ge 500 -and $statusCode -lt 600)) {
                if ($retryCount -lt $MaxRetries) {
                    Write-Host "API call throttled or failed (HTTP $statusCode). Retrying in ${backoffMs}ms..." -ForegroundColor Yellow
                    Start-Sleep -Milliseconds $backoffMs
                    $backoffMs *= 2
                    continue
                }
            }

            Write-Error "API call failed: $($_.Exception.Message)"
            throw
        }
    }

    Write-Error "Max retries exceeded for $Uri"
    throw
}

function Get-AllCatalogItems {
    <#
    .SYNOPSIS
        Fetch all catalog items (with paging) via OData.
    #>
    param(
        [string]$BaseUri,
        [hashtable]$Headers
    )

    $allItems = @()
    $nextLink = "$BaseUri/v2/odata/Catalog"

    while ($nextLink) {
        $response = Invoke-CloudRadialApiCall -Uri $nextLink -Headers $Headers
        $allItems += $response.value

        $nextLink = $response.'@odata.nextLink'
        if ($nextLink) {
            Write-Host "Fetching next page..." -ForegroundColor Cyan
        }
    }

    return $allItems
}

function Get-QuestionsByTemplate {
    <#
    .SYNOPSIS
        Fetch all questions for a specific template by companyCatalogId.
    #>
    param(
        [string]$BaseUri,
        [hashtable]$Headers,
        [int]$TemplateCatalogId
    )

    $filter = "`$filter=companyCatalogId eq $TemplateCatalogId"
    $uri = "$BaseUri/v2/odata/CatalogQuestion?$filter"

    $response = Invoke-CloudRadialApiCall -Uri $uri -Headers $Headers
    return $response.value
}

function ConvertTo-OdataJson {
    <#
    .SYNOPSIS
        Convert a PowerShell object to JSON suitable for OData POST operations.
    #>
    param(
        [object]$Object
    )

    return $Object | ConvertTo-Json -Depth 20
}

# =============================================================================
# ACTION HANDLERS
# =============================================================================

function Invoke-ListAction {
    param(
        [string]$BaseUri,
        [hashtable]$Headers
    )

    Write-Host "Fetching all catalog items..." -ForegroundColor Cyan

    try {
        $allItems = Get-AllCatalogItems -BaseUri $BaseUri -Headers $Headers

        # Filter to templates (catalogUsage = 'Template' or catalogType = 99)
        $templates = $allItems | Where-Object {
            $_.catalogUsage -eq 'Template'
        }

        if ($templates.Count -eq 0) {
            Write-Host "No Question Templates found in this company." -ForegroundColor Yellow
            return
        }

        Write-Host "Found $($templates.Count) Question Template(s):`n" -ForegroundColor Green

        # Fetch question count for each template
        $templateList = @()
        foreach ($template in $templates) {
            $questions = Get-QuestionsByTemplate -BaseUri $BaseUri -Headers $Headers -TemplateCatalogId $template.companyCatalogId
            $questionCount = $questions.Count

            $templateList += [PSCustomObject]@{
                'ID'              = $template.companyCatalogId
                'Subject'         = $template.subject
                'Category'        = $template.category
                'Company ID'      = $template.companyId
                'Question Count'  = $questionCount
            }
        }

        $templateList | Format-Table -AutoSize

        Write-Host "`nTo export a template, use:`n" -ForegroundColor Cyan
        Write-Host "  .\Sync-QuestionTemplates.ps1 -Action Export -TemplateId <ID> -FilePath <path>`n" -ForegroundColor White
    }
    catch {
        Write-Error "Failed to list templates: $_"
    }
}

function Invoke-ExportAction {
    param(
        [string]$BaseUri,
        [hashtable]$Headers,
        [int]$TemplateId,
        [string]$TemplateName,
        [string]$FilePath,
        [int]$MaxRetries,
        [int]$ThrottleMs
    )

    if (-not $TemplateId -and -not $TemplateName) {
        Write-Error "Either -TemplateId or -TemplateName must be specified for Export."
        return
    }

    try {
        $allItems = Get-AllCatalogItems -BaseUri $BaseUri -Headers $Headers
        $templates = $allItems | Where-Object {
            $_.catalogUsage -eq 'Template' -or $_.catalogType -eq 99
        }

        $template = $null

        if ($TemplateId) {
            $template = $templates | Where-Object { $_.companyCatalogId -eq $TemplateId }
            if (-not $template) {
                Write-Error "Template with ID $TemplateId not found."
                return
            }
        }
        elseif ($TemplateName) {
            $matches = $templates | Where-Object { $_.subject -like "*$TemplateName*" }
            if ($matches.Count -eq 0) {
                Write-Error "No templates matching '$TemplateName' found."
                return
            }
            elseif ($matches.Count -gt 1) {
                Write-Host "Multiple templates match '$TemplateName':`n" -ForegroundColor Yellow
                $matches | ForEach-Object { Write-Host "  ID: $($_.companyCatalogId) - $($_.subject)" }
                Write-Error "Please specify -TemplateId to disambiguate."
                return
            }
            else {
                $template = $matches[0]
            }
        }

        Write-Host "Exporting template: $($template.subject) (ID: $($template.companyCatalogId))" -ForegroundColor Cyan

        # Fetch all questions for this template
        $questions = Get-QuestionsByTemplate -BaseUri $BaseUri -Headers $Headers -TemplateCatalogId $template.companyCatalogId

        Write-Host "Found $($questions.Count) question(s)." -ForegroundColor Green

        # Build export object
        $exportDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss UTC')
        $exportObject = @{
            ExportDate      = $exportDate
            SourceCompanyId = $template.companyId
            Template        = @{
                companyCatalogId           = $template.companyCatalogId
                companyId                  = $template.companyId
                subject                    = $template.subject
                category                   = $template.category
                catalogUsage               = $template.catalogUsage
                isAllowedCompanyChanges    = $template.isAllowedCompanyChanges
                psaBoard                   = $template.psaBoard
                psaStatus                  = $template.psaStatus
                psaPriority                = $template.psaPriority
            }
            Questions       = @()
        }

        # Add each question to the export (preserve all fields)
        foreach ($question in $questions) {
            $exportObject.Questions += @{
                companyCatalogQuestionId = $question.companyCatalogQuestionId
                companyCatalogId         = $question.companyCatalogId
                companyId                = $question.companyId
                label                    = $question.label
                info                     = $question.info
                options                  = $question.options
                placeholder              = $question.placeholder
                defaultValue             = $question.defaultValue
                order                    = $question.order
                type                     = $question.type
                isRequired               = $question.isRequired
                isSubject                = $question.isSubject
                isDescription            = $question.isDescription
                jsonId                   = $question.jsonId
                isIncludeInTicket        = $question.isIncludeInTicket
                isUserLookup             = $question.isUserLookup
                customFieldName          = $question.customFieldName
                childQuestionIds         = $question.childQuestionIds
                isDeleted                = $question.isDeleted
            }
        }

        # Determine output path
        if (-not $FilePath) {
            $safeSubject = $template.subject -replace '[^\w\-]', '_'
            $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
            $FilePath = ".\QuestionTemplate_Export_${safeSubject}_${timestamp}.json"
        }

        # Write export to file
        $exportObject | ConvertTo-Json -Depth 20 | Out-File -FilePath $FilePath -Encoding UTF8
        Write-Host "Template exported successfully to: $FilePath" -ForegroundColor Green
        Write-Host "`nExport summary:" -ForegroundColor Cyan
        Write-Host "  Template: $($template.subject)" -ForegroundColor White
        Write-Host "  Questions: $($questions.Count)" -ForegroundColor White
        Write-Host "  Source Company ID: $($template.companyId)" -ForegroundColor White
    }
    catch {
        Write-Error "Export failed: $_"
    }
}

function Invoke-ImportAction {
    param(
        [string]$BaseUri,
        [hashtable]$Headers,
        [string]$FilePath,
        [int]$TargetCompanyId,
        [int]$MaxRetries,
        [int]$ThrottleMs
    )

    if (-not $FilePath) {
        Write-Error "-FilePath is required for Import."
        return
    }

    if (-not (Test-Path -Path $FilePath)) {
        Write-Error "File not found: $FilePath"
        return
    }

    try {
        Write-Host "Reading export file: $FilePath" -ForegroundColor Cyan
        $exportContent = Get-Content -Path $FilePath -Raw | ConvertFrom-Json

        $sourceCompanyId = $exportContent.SourceCompanyId
        $importDate = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $template = $exportContent.Template
        $questions = $exportContent.Questions

        # Use provided TargetCompanyId, or default to source
        $destCompanyId = if ($TargetCompanyId) { $TargetCompanyId } else { $sourceCompanyId }

        Write-Host "Importing template from export (created: $($exportContent.ExportDate))" -ForegroundColor Cyan
        Write-Host "  Source Company ID: $sourceCompanyId" -ForegroundColor White
        Write-Host "  Target Company ID: $destCompanyId" -ForegroundColor White
        Write-Host "  Questions to import: $($questions.Count)" -ForegroundColor White

        # Prepare template object for creation
        $newTemplateName = "$($template.subject) (Imported $importDate)"
        $templatePayload = @{
            companyId                  = $destCompanyId
            subject                    = $newTemplateName
            category                   = $template.category
            catalogUsage               = 'Template'
            isAllowedCompanyChanges    = $template.isAllowedCompanyChanges
            psaBoard                   = $template.psaBoard
            psaStatus                  = $template.psaStatus
            psaPriority                = $template.psaPriority
        } | ConvertTo-Json -Depth 10

        Write-Host "`nCreating template: $newTemplateName" -ForegroundColor Cyan

        # POST the new template
        $createTemplateUri = "$BaseUri/v2/catalog"
        $templateResponse = Invoke-CloudRadialApiCall `
            -Uri $createTemplateUri `
            -Method Post `
            -Headers $Headers `
            -Body $templatePayload `
            -MaxRetries $MaxRetries `
            -ThrottleMs $ThrottleMs

        $newTemplateCatalogId = $templateResponse.companyCatalogId
        Write-Host "Template created with ID: $newTemplateCatalogId" -ForegroundColor Green

        # Track old question ID -> new question ID for conditional logic remapping
        $idMapping = @{}

        # Create each question
        Write-Host "`nCreating questions..." -ForegroundColor Cyan
        foreach ($question in $questions) {
            $questionPayload = @{
                companyCatalogId  = $newTemplateCatalogId
                companyId         = $destCompanyId
                label             = $question.label
                info              = $question.info
                options           = $question.options
                placeholder       = $question.placeholder
                defaultValue      = $question.defaultValue
                order             = $question.order
                type              = $question.type
                isRequired        = $question.isRequired
                isSubject         = $question.isSubject
                isDescription     = $question.isDescription
                jsonId            = $question.jsonId
                isIncludeInTicket = $question.isIncludeInTicket
                isUserLookup      = $question.isUserLookup
                customFieldName   = $question.customFieldName
                childQuestionIds  = ''  # Will be remapped after all questions created
                isDeleted         = $question.isDeleted
            } | ConvertTo-Json -Depth 10

            $createQuestionUri = "$BaseUri/v2/catalogquestion"
            $questionResponse = Invoke-CloudRadialApiCall `
                -Uri $createQuestionUri `
                -Method Post `
                -Headers $Headers `
                -Body $questionPayload `
                -MaxRetries $MaxRetries `
                -ThrottleMs $ThrottleMs

            $oldQuestionId = $question.companyCatalogQuestionId
            $newQuestionId = $questionResponse.companyCatalogQuestionId
            $idMapping[$oldQuestionId] = $newQuestionId

            Write-Host "  Created question: $($question.label) (old ID: $oldQuestionId -> new ID: $newQuestionId)" -ForegroundColor Green
        }

        # Remap conditional logic (childQuestionIds)
        Write-Host "`nRemapping conditional logic..." -ForegroundColor Cyan
        $questionsToUpdate = @()

        foreach ($question in $questions) {
            if ($question.childQuestionIds) {
                $oldChildIds = @($question.childQuestionIds -split ',' | Where-Object { $_ })
                $newChildIds = @()

                foreach ($oldChildId in $oldChildIds) {
                    if ($idMapping.ContainsKey([int]$oldChildId)) {
                        $newChildIds += $idMapping[[int]$oldChildId]
                    }
                }

                if ($newChildIds.Count -gt 0) {
                    $questionsToUpdate += @{
                        OldId       = $question.companyCatalogQuestionId
                        NewId       = $idMapping[$question.companyCatalogQuestionId]
                        ChildIds    = $newChildIds -join ','
                        Label       = $question.label
                    }
                }
            }
        }

        foreach ($update in $questionsToUpdate) {
            $updatePayload = @{
                companyCatalogQuestionId = $update.NewId
                childQuestionIds         = $update.ChildIds
            } | ConvertTo-Json -Depth 10

            $updateUri = "$BaseUri/v2/catalogquestion/$($update.NewId)"

            try {
                Invoke-CloudRadialApiCall `
                    -Uri $updateUri `
                    -Method Put `
                    -Headers $Headers `
                    -Body $updatePayload `
                    -MaxRetries $MaxRetries `
                    -ThrottleMs $ThrottleMs

                Write-Host "  Remapped conditional logic for: $($update.Label)" -ForegroundColor Green
            }
            catch {
                Write-Host "  Warning: Could not remap conditional logic for $($update.Label): $_" -ForegroundColor Yellow
            }
        }

        Write-Host "`nImport completed successfully!" -ForegroundColor Green
        Write-Host "`nImport summary:" -ForegroundColor Cyan
        Write-Host "  New Template ID: $newTemplateCatalogId" -ForegroundColor White
        Write-Host "  Template Name: $newTemplateName" -ForegroundColor White
        Write-Host "  Questions Created: $($questions.Count)" -ForegroundColor White
        Write-Host "  Conditional Logic Remapped: $($questionsToUpdate.Count)" -ForegroundColor White
        Write-Host "`nYour template is ready to use in company $destCompanyId." -ForegroundColor Cyan
    }
    catch {
        Write-Error "Import failed: $_"
    }
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

try {
    # Get credentials
    Write-Host "CloudRadial Question Template Sync Tool" -ForegroundColor Cyan
    Write-Host "======================================`n" -ForegroundColor Cyan

    $creds = Get-CloudRadialCredentials
    $authHeaders = New-BasicAuthHeader -Username $creds.Username -Password $creds.Password

    # Dispatch to action handler
    switch ($Action) {
        'List' {
            Invoke-ListAction -BaseUri $BaseUri -Headers $authHeaders
        }
        'Export' {
            Invoke-ExportAction -BaseUri $BaseUri -Headers $authHeaders `
                -TemplateId $TemplateId -TemplateName $TemplateName -FilePath $FilePath `
                -MaxRetries $MaxRetries -ThrottleMs $ThrottleMs
        }
        'Import' {
            Invoke-ImportAction -BaseUri $BaseUri -Headers $authHeaders `
                -FilePath $FilePath -TargetCompanyId $TargetCompanyId `
                -MaxRetries $MaxRetries -ThrottleMs $ThrottleMs
        }
    }
}
catch {
    Write-Error "Fatal error: $_"
    exit 1
}
