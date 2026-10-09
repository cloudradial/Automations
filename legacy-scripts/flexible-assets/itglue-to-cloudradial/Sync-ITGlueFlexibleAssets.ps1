<#
.SYNOPSIS
Syncs IT Glue Flexible Asset Types and their asset data into CloudRadial UCP
via the IT Glue-compatible API.

.DESCRIPTION
This script automates the migration of Flexible Assets from IT Glue to
CloudRadial. It reads a CSV mapping file that pairs IT Glue Organization IDs
to CloudRadial Company IDs, then:

  1. Pulls all Flexible Asset Type definitions (schemas) from IT Glue
  2. Creates matching Flexible Asset Types in CloudRadial
  3. For each mapped organization, pulls Flexible Asset records from IT Glue
  4. Bulk-inserts those records into CloudRadial

Designed for MSPs migrating documentation from IT Glue into the CloudRadial
client portal. Supports -WhatIf for safe dry runs.

.PARAMETER ITGlueApiKey
Your IT Glue API key. If not provided, falls back to the
ITGLUE_API_KEY environment variable.

.PARAMETER ITGlueBaseUrl
IT Glue API base URL. Defaults to https://api.itglue.com.
Use https://api.eu.itglue.com for EU or https://api.au.itglue.com for AU.

.PARAMETER CRPublicKey
Your CloudRadial API Public Key. If not provided, falls back to the
CLOUDRADIAL_API_PUBLIC_KEY environment variable.

.PARAMETER CRPrivateKey
Your CloudRadial API Private Key. If not provided, falls back to the
CLOUDRADIAL_API_PRIVATE_KEY environment variable.

.PARAMETER CRBaseUrl
CloudRadial API base URL. Defaults to https://api.us.cloudradial.com.

.PARAMETER MappingFilePath
Path to a CSV file with columns: ITGlueOrgId, CloudRadialCompanyId, OrgName.
Each row maps one IT Glue organization to a CloudRadial company.

.PARAMETER FlexibleAssetTypeFilter
Optional. Comma-separated list of IT Glue Flexible Asset Type names to sync.
If omitted, all types are synced.

.PARAMETER PageSize
Number of records per API page. Defaults to 50. Max 1000 for IT Glue.

.PARAMETER WhatIf
Preview all actions without making any changes.

.EXAMPLE
PS> .\Sync-ITGlueFlexibleAssets.ps1 -MappingFilePath ".\org-mapping.csv"

Syncs all Flexible Asset Types and data using environment variables for keys.

.EXAMPLE
PS> .\Sync-ITGlueFlexibleAssets.ps1 `
    -ITGlueApiKey "ITG.xxxxxxxxxxxxxxxxxxxx" `
    -CRPublicKey "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -CRPrivateKey "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -MappingFilePath ".\org-mapping.csv" `
    -FlexibleAssetTypeFilter "Network Devices,Backup Systems" `
    -WhatIf

Dry run: previews what would be synced for only the specified asset types.

.NOTES
Author:  Nick Westgate (CloudRadial Customer Success)
Version: 1.0
Date:    2026-05-12

Requires: PowerShell 5.1+
API Docs: https://api.itglue.com/developer/
          https://developers.cloudradial.com/v2/docs/getting-started
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ITGlueApiKey,

    [Parameter(Mandatory = $false)]
    [ValidateSet(
        "https://api.itglue.com",
        "https://api.eu.itglue.com",
        "https://api.au.itglue.com"
    )]
    [string]$ITGlueBaseUrl = "https://api.itglue.com",

    [Parameter(Mandatory = $false)]
    [string]$CRPublicKey,

    [Parameter(Mandatory = $false)]
    [string]$CRPrivateKey,

    [Parameter(Mandatory = $false)]
    [string]$CRBaseUrl = "https://api.us.cloudradial.com",

    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$MappingFilePath,

    [Parameter(Mandatory = $false)]
    [string[]]$FlexibleAssetTypeFilter,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 1000)]
    [int]$PageSize = 50,

    [switch]$WhatIf
)

# ============================================================================
# CONFIGURATION & AUTH
# ============================================================================

$ErrorActionPreference = "Stop"

# Resolve credentials from params or environment variables
if (-not $ITGlueApiKey) {
    $ITGlueApiKey = $env:ITGLUE_API_KEY
    if (-not $ITGlueApiKey) {
        Write-Error "IT Glue API key not provided. Use -ITGlueApiKey or set ITGLUE_API_KEY environment variable."
        exit 1
    }
}

if (-not $CRPublicKey) {
    $CRPublicKey = $env:CLOUDRADIAL_API_PUBLIC_KEY
    if (-not $CRPublicKey) {
        Write-Error "CloudRadial Public Key not provided. Use -CRPublicKey or set CLOUDRADIAL_API_PUBLIC_KEY environment variable."
        exit 1
    }
}

if (-not $CRPrivateKey) {
    $CRPrivateKey = $env:CLOUDRADIAL_API_PRIVATE_KEY
    if (-not $CRPrivateKey) {
        Write-Error "CloudRadial Private Key not provided. Use -CRPrivateKey or set CLOUDRADIAL_API_PRIVATE_KEY environment variable."
        exit 1
    }
}

# Build auth headers
$itGlueHeaders = @{
    "x-api-key"    = $ITGlueApiKey
    "Content-Type" = "application/vnd.api+json"
}

$crPair   = "$($CRPublicKey):$($CRPrivateKey)"
$crBase64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($crPair))
$crHeaders = @{
    "Authorization" = "Basic $crBase64"
    "Content-Type"  = "application/json"
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "Info"    { "Cyan" }
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error"   { "Red" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Invoke-ITGlueApi {
    <#
    .SYNOPSIS
    Makes a paginated GET request to the IT Glue API and returns all results.
    #>
    param(
        [string]$Endpoint,
        [hashtable]$QueryParams = @{}
    )

    $allData  = @()
    $page     = 1
    $hasMore  = $true

    while ($hasMore) {
        $QueryParams["page[number]"] = $page
        $QueryParams["page[size]"]   = $PageSize

        $queryString = ($QueryParams.GetEnumerator() | ForEach-Object {
            "$([Uri]::EscapeDataString($_.Key))=$([Uri]::EscapeDataString($_.Value))"
        }) -join "&"

        $uri = "$ITGlueBaseUrl/$Endpoint"
        if ($queryString) { $uri += "?$queryString" }

        try {
            $response = Invoke-RestMethod -Uri $uri -Headers $itGlueHeaders -Method Get
        }
        catch {
            Write-Log "IT Glue API error on $Endpoint (page $page): $($_.Exception.Message)" -Level Error
            throw
        }

        if ($response.data) {
            $allData += $response.data
        }

        # Check if there are more pages
        $totalPages = 1
        if ($response.meta -and $response.meta.'total-pages') {
            $totalPages = $response.meta.'total-pages'
        }
        elseif ($response.meta -and $response.meta.'total-count') {
            $totalPages = [math]::Ceiling($response.meta.'total-count' / $PageSize)
        }

        if ($page -ge $totalPages -or -not $response.data -or $response.data.Count -eq 0) {
            $hasMore = $false
        }
        else {
            $page++
        }
    }

    return $allData
}

function Invoke-CloudRadialApi {
    <#
    .SYNOPSIS
    Makes a POST request to the CloudRadial V2 API.
    #>
    param(
        [string]$Endpoint,
        [object]$Body
    )

    $uri      = "$CRBaseUrl/$Endpoint"
    $jsonBody = $Body | ConvertTo-Json -Depth 20

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $crHeaders -Method Post -Body $jsonBody
        return $response
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody  = ""
        if ($_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $errorBody = $reader.ReadToEnd()
            }
            catch { }
        }
        Write-Log "CloudRadial API error on $Endpoint (HTTP $statusCode): $errorBody" -Level Error
        throw
    }
}

function Coalesce {
    <#
    .SYNOPSIS
    Returns the first non-null argument. PowerShell 5.1-compatible
    replacement for the ?? operator.
    #>
    foreach ($arg in $args) {
        if ($null -ne $arg) { return $arg }
    }
    return $null
}

function Convert-ITGlueFieldKind {
    <#
    .SYNOPSIS
    Maps IT Glue field kinds to CloudRadial-compatible kinds.
    Most are identical since CloudRadial uses IT Glue-compatible format.
    #>
    param([string]$Kind)

    # CloudRadial's compatibility API accepts the same kinds as IT Glue
    $validKinds = @(
        "Text", "Textbox", "Number", "Checkbox", "Select",
        "Date", "Header", "Upload", "Password", "Tag"
    )

    if ($Kind -in $validKinds) {
        return $Kind
    }

    # Fallback for any unrecognized kinds
    Write-Log "Unknown field kind '$Kind' - defaulting to 'Text'" -Level Warning
    return "Text"
}

function Convert-TraitKeyToNameKey {
    <#
    .SYNOPSIS
    Converts an IT Glue trait key to the hyphenated name-key format
    expected by CloudRadial. IT Glue trait keys are typically the
    hyphenated, lowercase version of the field name.
    #>
    param([string]$TraitKey)

    # IT Glue already uses hyphenated lowercase keys in traits
    return $TraitKey
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

Write-Log "============================================" -Level Info
Write-Log "IT Glue -> CloudRadial Flexible Asset Sync" -Level Info
Write-Log "============================================" -Level Info

if ($WhatIf) {
    Write-Log "*** DRY RUN MODE - No changes will be made ***" -Level Warning
}

# --- Load Organization Mapping ---
Write-Log "Loading organization mapping from: $MappingFilePath" -Level Info
$orgMapping = Import-Csv -Path $MappingFilePath

if (-not $orgMapping -or $orgMapping.Count -eq 0) {
    Write-Error "Mapping file is empty or could not be parsed. Ensure CSV has columns: ITGlueOrgId, CloudRadialCompanyId, OrgName"
    exit 1
}

# Validate CSV columns
$requiredColumns = @("ITGlueOrgId", "CloudRadialCompanyId")
foreach ($col in $requiredColumns) {
    if ($col -notin $orgMapping[0].PSObject.Properties.Name) {
        Write-Error "Mapping CSV missing required column: $col. Expected columns: ITGlueOrgId, CloudRadialCompanyId, OrgName"
        exit 1
    }
}

Write-Log "Loaded $($orgMapping.Count) organization mapping(s)" -Level Success

# --- Step 1: Pull Flexible Asset Types from IT Glue ---
Write-Log "" -Level Info
Write-Log "STEP 1: Fetching Flexible Asset Types from IT Glue..." -Level Info
$itGlueTypes = Invoke-ITGlueApi -Endpoint "flexible_asset_types" -QueryParams @{
    "include" = "flexible_asset_fields"
}

if (-not $itGlueTypes -or $itGlueTypes.Count -eq 0) {
    Write-Log "No Flexible Asset Types found in IT Glue. Nothing to sync." -Level Warning
    exit 0
}

Write-Log "Found $($itGlueTypes.Count) Flexible Asset Type(s) in IT Glue" -Level Success

# Apply filter if specified
if ($FlexibleAssetTypeFilter) {
    $itGlueTypes = $itGlueTypes | Where-Object { $_.attributes.name -in $FlexibleAssetTypeFilter }
    Write-Log "Filtered to $($itGlueTypes.Count) type(s): $($FlexibleAssetTypeFilter -join ', ')" -Level Info
}

# --- Step 2: Create Flexible Asset Types in CloudRadial ---
Write-Log "" -Level Info
Write-Log "STEP 2: Creating Flexible Asset Types in CloudRadial..." -Level Info

# Track the mapping of IT Glue type IDs to CloudRadial type IDs
$typeIdMapping = @{}

foreach ($itgType in $itGlueTypes) {
    $typeName = $itgType.attributes.name
    Write-Log "Processing type: $typeName (IT Glue ID: $($itgType.id))" -Level Info

    # Build the fields array from IT Glue's included relationships
    $fields = @()

    # IT Glue returns fields in the relationships or as included resources
    $itgFields = @()
    if ($itgType.attributes.'flexible-asset-fields') {
        $itgFields = $itgType.attributes.'flexible-asset-fields'
    }
    elseif ($itgType.relationships -and $itgType.relationships.'flexible-asset-fields') {
        # Fields might be in the included section of the response
        $fieldIds = $itgType.relationships.'flexible-asset-fields'.data | ForEach-Object { $_.id }
        # Pull fields separately if not embedded
        if ($fieldIds) {
            $itgFields = Invoke-ITGlueApi -Endpoint "flexible_asset_types/$($itgType.id)/relationships/flexible_asset_fields"
        }
    }

    if (-not $itgFields -or $itgFields.Count -eq 0) {
        # Try fetching fields directly
        Write-Log "  Fetching fields for type $typeName separately..." -Level Info
        $itgFields = Invoke-ITGlueApi -Endpoint "flexible_asset_types/$($itgType.id)/relationships/flexible_asset_fields"
    }

    foreach ($field in $itgFields) {
        $fieldAttrs = if ($field.attributes) { $field.attributes } else { $field }
        $fieldObj = @{
            "attributes" = @{
                "name"          = $fieldAttrs.name
                "order"         = [int](Coalesce $fieldAttrs.'order' $fieldAttrs.'field-order' 0)
                "kind"          = Convert-ITGlueFieldKind -Kind (Coalesce $fieldAttrs.kind $fieldAttrs.'field-kind' "Text")
                "required"      = [bool](Coalesce $fieldAttrs.required $false)
                "hint"          = $fieldAttrs.hint
                "default-value" = $fieldAttrs.'default-value'
                "tag-type"      = $fieldAttrs.'tag-type'
                "decimals"      = $fieldAttrs.decimals
                "expiration"    = [bool](Coalesce $fieldAttrs.expiration $false)
                "use-for-title" = [bool](Coalesce $fieldAttrs.'use-for-title' $false)
                "show-in-list"  = [bool](Coalesce $fieldAttrs.'show-in-list' $true)
            }
            "type" = "flexible_asset_fields"
        }
        $fields += $fieldObj
    }

    Write-Log "  Found $($fields.Count) field(s) for type: $typeName" -Level Info

    # Build the CloudRadial payload
    $crTypePayload = @{
        "data" = @{
            "attributes" = @{
                "name"         = $typeName
                "description"  = $itgType.attributes.description
                "icon"         = $itgType.attributes.icon
                "show-in-menu" = $true
            }
            "relationships" = @{
                "flexible-asset-fields" = @{
                    "data" = $fields
                }
            }
            "type" = "flexible_asset_types"
        }
    }

    if ($WhatIf) {
        Write-Log "  [WhatIf] Would create asset type '$typeName' with $($fields.Count) field(s)" -Level Warning
        # Use a placeholder ID for WhatIf tracking
        $typeIdMapping[$itgType.id] = "WHATIF-$($itgType.id)"
    }
    else {
        try {
            $crResponse = Invoke-CloudRadialApi -Endpoint "compatibility/flexible_asset_types" -Body $crTypePayload
            $crTypeId = Coalesce $crResponse.data.id $crResponse.id
            $typeIdMapping[$itgType.id] = $crTypeId
            Write-Log "  Created '$typeName' in CloudRadial (ID: $crTypeId)" -Level Success
        }
        catch {
            if ($_.Exception.Message -match "already exists" -or $_.Exception.Message -match "unique") {
                Write-Log "  Asset type '$typeName' already exists in CloudRadial - skipping type creation" -Level Warning
                Write-Log "  To sync assets for this type, you may need to look up the existing CloudRadial type ID" -Level Warning
                continue
            }
            else {
                Write-Log "  Failed to create type '$typeName': $($_.Exception.Message)" -Level Error
                continue
            }
        }
    }
}

# --- Step 3: Sync Flexible Assets per Organization ---
Write-Log "" -Level Info
Write-Log "STEP 3: Syncing Flexible Assets per organization..." -Level Info

$totalAssetsCreated = 0
$totalAssetsFailed  = 0

foreach ($mapping in $orgMapping) {
    $itgOrgId = $mapping.ITGlueOrgId
    $crCompanyId = $mapping.CloudRadialCompanyId
    $orgName = if ($mapping.OrgName) { $mapping.OrgName } else { "Org $itgOrgId" }

    Write-Log "" -Level Info
    Write-Log "--- Organization: $orgName (ITG: $itgOrgId -> CR: $crCompanyId) ---" -Level Info

    foreach ($itgType in $itGlueTypes) {
        $typeName = $itgType.attributes.name
        $crTypeId = $typeIdMapping[$itgType.id]

        if (-not $crTypeId) {
            Write-Log "  Skipping type '$typeName' - no CloudRadial type ID available" -Level Warning
            continue
        }

        Write-Log "  Fetching '$typeName' assets for $orgName from IT Glue..." -Level Info

        # Pull flexible assets for this org and type from IT Glue
        $itgAssets = Invoke-ITGlueApi -Endpoint "flexible_assets" -QueryParams @{
            "filter[organization-id]"         = $itgOrgId
            "filter[flexible-asset-type-id]"  = $itgType.id
        }

        if (-not $itgAssets -or $itgAssets.Count -eq 0) {
            Write-Log "  No '$typeName' assets found for $orgName - skipping" -Level Info
            continue
        }

        Write-Log "  Found $($itgAssets.Count) '$typeName' asset(s) to sync" -Level Info

        # Build the bulk insert payload for CloudRadial
        $assetDataArray = @()

        foreach ($asset in $itgAssets) {
            $traits = @{}

            # IT Glue stores field values in attributes.traits as key-value pairs
            if ($asset.attributes.traits) {
                $traitSource = $asset.attributes.traits
                # Handle both PSCustomObject and Hashtable
                if ($traitSource -is [System.Management.Automation.PSCustomObject]) {
                    $traitSource.PSObject.Properties | ForEach-Object {
                        $traits[$_.Name] = if ($_.Value -is [PSCustomObject] -and $_.Value.values) {
                            # Tag fields come as objects with a .values property
                            ($_.Value.values | ForEach-Object { Coalesce $_.name $_ }) -join ", "
                        }
                        else {
                            [string]$_.Value
                        }
                    }
                }
                elseif ($traitSource -is [hashtable]) {
                    foreach ($key in $traitSource.Keys) {
                        $traits[$key] = [string]$traitSource[$key]
                    }
                }
            }

            $assetObj = @{
                "attributes" = @{
                    "organization-id"        = [int]$crCompanyId
                    "flexible-asset-type-id" = $crTypeId
                    "archived"               = [bool](Coalesce $asset.attributes.archived $false)
                    "traits"                 = $traits
                }
                "type" = "flexible_assets"
            }
            $assetDataArray += $assetObj
        }

        if ($WhatIf) {
            Write-Log "  [WhatIf] Would create $($assetDataArray.Count) '$typeName' asset(s) for $orgName in CloudRadial" -Level Warning
            $totalAssetsCreated += $assetDataArray.Count
        }
        else {
            # Bulk insert via the organizations endpoint
            $bulkPayload = @{ "data" = $assetDataArray }

            try {
                $crResponse = Invoke-CloudRadialApi `
                    -Endpoint "compatibility/organizations/$crCompanyId/relationships/flexible_assets" `
                    -Body $bulkPayload

                $totalAssetsCreated += $assetDataArray.Count
                Write-Log "  Created $($assetDataArray.Count) '$typeName' asset(s) for $orgName" -Level Success
            }
            catch {
                $totalAssetsFailed += $assetDataArray.Count
                Write-Log "  Failed to create assets for $orgName / $typeName : $($_.Exception.Message)" -Level Error

                # Fallback: try inserting one at a time
                Write-Log "  Attempting individual inserts as fallback..." -Level Warning
                $totalAssetsFailed -= $assetDataArray.Count  # Reset to recount

                foreach ($singleAsset in $assetDataArray) {
                    $singlePayload = @{ "data" = $singleAsset }
                    try {
                        Invoke-CloudRadialApi `
                            -Endpoint "compatibility/flexible_assets" `
                            -Body $singlePayload | Out-Null
                        $totalAssetsCreated++
                        Write-Log "    Created individual asset" -Level Success
                    }
                    catch {
                        $totalAssetsFailed++
                        Write-Log "    Failed: $($_.Exception.Message)" -Level Error
                    }
                }
            }
        }
    }
}

# ============================================================================
# SUMMARY
# ============================================================================
Write-Log "" -Level Info
Write-Log "============================================" -Level Info
Write-Log "SYNC COMPLETE" -Level Success
Write-Log "============================================" -Level Info
Write-Log "Asset Types processed:  $($itGlueTypes.Count)" -Level Info
Write-Log "Organizations mapped:   $($orgMapping.Count)" -Level Info
Write-Log "Assets created:         $totalAssetsCreated" -Level Success
Write-Log "Assets failed:          $totalAssetsFailed" -Level $(if ($totalAssetsFailed -gt 0) { "Error" } else { "Info" })
if ($WhatIf) {
    Write-Log "*** This was a DRY RUN - no changes were made ***" -Level Warning
}
Write-Log "============================================" -Level Info
