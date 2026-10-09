<#
.SYNOPSIS
Import companies into CloudRadial from a CSV file using the v2 API.

.DESCRIPTION
Bulk imports companies into a CloudRadial partner tenant from a CSV file. Validates
CSV format, checks for existing companies by name, and handles API authentication,
rate limiting, and retries with exponential backoff. Supports dry-run mode (-WhatIf)
and resumable imports after errors (-Resume).

Credentials are read from environment variables CLOUDRADIAL_API_USERNAME and
CLOUDRADIAL_API_PASSWORD, with interactive fallback if not set.

User sync is disabled by default on created companies — the Partner controls when
to enable PSA or M365 sync after import.

.PARAMETER CsvPath
Mandatory. Path to the CSV file containing company data. Required column: name.
Optional columns: psaKey, psaIdentifier, territory, accountManager.

.PARAMETER PartnerId
Optional. The numeric ID of the partner tenant these companies belong to. If omitted,
the API uses the authenticated partner's default tenant.

.PARAMETER BaseUri
Optional. CloudRadial API base URL. Defaults to https://api.us.cloudradial.com.

.PARAMETER RequestsPerMinute
Optional. Rate limit for API requests. Defaults to 12 (5-second delay between requests).

.PARAMETER MaxRetries
Optional. Maximum number of retries for failed API calls. Defaults to 3.

.PARAMETER WhatIf
Optional. Show what would happen without making changes.

.PARAMETER Resume
Optional. Resume a previous import using the checkpoint file. Skips companies already
processed successfully.

.EXAMPLE
.\Import-CloudRadialCompanies.ps1 -CsvPath ".\companies.csv"

.EXAMPLE
.\Import-CloudRadialCompanies.ps1 -CsvPath ".\companies.csv" -WhatIf

.EXAMPLE
.\Import-CloudRadialCompanies.ps1 -CsvPath ".\companies.csv" -PartnerId 7 -Resume

#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CsvPath,

    [int]$PartnerId,

    [string]$BaseUri = "https://api.us.cloudradial.com",

    [int]$RequestsPerMinute = 12,

    [int]$MaxRetries = 3,

    [switch]$WhatIf,

    [switch]$Resume
)

# ============================================================================
# Configuration and Constants
# ============================================================================

$ErrorActionPreference = "Continue"
$InformationPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# TLS 1.2+
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13

$DelayBetweenRequests = [timespan]::FromSeconds(60 / $RequestsPerMinute)
$CheckpointFile = "$([IO.Path]::GetDirectoryName($CsvPath))\$([IO.Path]::GetFileNameWithoutExtension($CsvPath))_checkpoint_companies.txt"

$script:Stats = @{
    Total   = 0
    Created = 0
    Skipped = 0
    Failed  = 0
}

# ============================================================================
# Helper Functions
# ============================================================================

function Show-ApiError {
    param(
        [Parameter(Mandatory = $true)]
        $Response,

        [Parameter(Mandatory = $true)]
        [string]$ErrorContext
    )

    try {
        $body = $Response.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($body.message) {
            Write-Host "ERROR ($($Response.StatusCode)): $($body.message) [$ErrorContext]" -ForegroundColor Red
        }
        elseif ($body.error) {
            Write-Host "ERROR ($($Response.StatusCode)): $($body.error) [$ErrorContext]" -ForegroundColor Red
        }
        else {
            Write-Host "ERROR ($($Response.StatusCode)): $($Response.Content | Out-String) [$ErrorContext]" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "ERROR ($($Response.StatusCode)): $ErrorContext" -ForegroundColor Red
    }
}

function Invoke-ApiCall {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [object]$Body,

        [hashtable]$Headers,

        [string]$ErrorContext = "API Call"
    )

    $attemptCount = 0
    $lastException = $null

    while ($attemptCount -lt $MaxRetries) {
        try {
            $attemptCount++
            $params = @{
                Method          = $Method
                Uri             = $Uri
                Headers         = $Headers
                ContentType     = "application/json"
                ErrorAction     = "Stop"
                UseBasicParsing = $true
            }

            if ($Body) {
                $params["Body"] = $Body
            }

            $response = Invoke-WebRequest @params
            return $response

        }
        catch [System.Net.Http.HttpRequestException] {
            $lastException = $_
            $statusCode = $_.Exception.Response.StatusCode -as [int]

            # 429 Too Many Requests or 5xx errors: retry with backoff
            if ($statusCode -eq 429 -or ($statusCode -ge 500 -and $statusCode -lt 600)) {
                $backoff = [math]::Pow(2, ($attemptCount - 1))
                Write-Host "Rate limited or server error ($statusCode). Retrying in ${backoff}s (attempt $attemptCount/$MaxRetries)..." -ForegroundColor Yellow
                Start-Sleep -Seconds $backoff
                continue
            }

            # Other HTTP errors: fail immediately
            Show-ApiError -Response $_.Exception.Response -ErrorContext $ErrorContext
            return $null

        }
        catch {
            $lastException = $_
            Write-Host "ERROR: $($_.Exception.Message) [$ErrorContext]" -ForegroundColor Red
            return $null
        }
    }

    if ($lastException) {
        Write-Host "ERROR: Max retries exceeded [$ErrorContext]" -ForegroundColor Red
    }
    return $null
}

function Get-BasicAuthHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PublicKey,

        [Parameter(Mandatory = $true)]
        [string]$PrivateKey
    )

    $credentials = "$($PublicKey):$($PrivateKey)"
    $encodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credentials))
    return @{
        Authorization = "Basic $encodedCredentials"
    }
}

function Get-Credentials {
    $username = $env:CLOUDRADIAL_API_USERNAME
    $password = $env:CLOUDRADIAL_API_PASSWORD

    if (-not $username) {
        $username = Read-Host -Prompt "Enter CloudRadial API PublicKey"
    }

    if (-not $password) {
        $securePassword = Read-Host -Prompt "Enter CloudRadial API PrivateKey" -AsSecureString
        $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($securePassword)
        )
    }

    return @{
        PublicKey  = $username
        PrivateKey = $password
    }
}

function Get-ExistingCompanies {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$AuthHeader
    )

    Write-Host "Fetching existing companies..." -ForegroundColor Cyan

    $existingCompanies = @{}
    $uri = "$BaseUri/v2/odata/company?`$select=id,name&`$top=1000"

    while ($uri) {
        $response = Invoke-ApiCall -Method "GET" -Uri $uri -Headers $AuthHeader -ErrorContext "Fetch existing companies"

        if (-not $response) {
            Write-Host "WARNING: Could not fetch all existing companies. Duplicate detection may be incomplete." -ForegroundColor Yellow
            break
        }

        try {
            $data = $response.Content | ConvertFrom-Json
            foreach ($company in $data.value) {
                $existingCompanies[$company.name.ToLower().Trim()] = $company.id
            }

            # Check for next page
            $uri = $data."@odata.nextLink"
        }
        catch {
            Write-Host "WARNING: Failed to parse existing companies response" -ForegroundColor Yellow
            break
        }
    }

    Write-Host "Found $($existingCompanies.Count) existing companies" -ForegroundColor Green
    return $existingCompanies
}

function Save-Checkpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CompanyName
    )

    Add-Content -Path $CheckpointFile -Value $CompanyName -ErrorAction SilentlyContinue
}

function Get-ProcessedCompanies {
    if (Test-Path $CheckpointFile) {
        return @(Get-Content -Path $CheckpointFile -ErrorAction SilentlyContinue) | Where-Object { $_ }
    }
    return @()
}

function Import-Company {
    param(
        [Parameter(Mandatory = $true)]
        [object]$CompanyData,

        [Parameter(Mandatory = $true)]
        [hashtable]$AuthHeader,

        [hashtable]$ExistingCompanies
    )

    $name = $CompanyData.name.Trim()
    $nameKey = $name.ToLower()

    # Check if already exists
    if ($ExistingCompanies.ContainsKey($nameKey)) {
        return @{
            Status   = "Skipped"
            Reason   = "Already exists (ID: $($ExistingCompanies[$nameKey]))"
            CompanyId = $ExistingCompanies[$nameKey]
        }
    }

    # Build company object — only required field is name
    $companyObject = @{
        name = $name
    }

    # Add partnerId if provided via parameter
    if ($PSBoundParameters.ContainsKey('PartnerId') -or $PartnerId -gt 0) {
        $companyObject["partnerId"] = $PartnerId
    }

    # Add optional string fields from CSV if present and non-empty
    $optionalStringFields = @("psaIdentifier", "territory", "accountManager")
    foreach ($field in $optionalStringFields) {
        if ($CompanyData.PSObject.Properties.Name -contains $field -and $CompanyData.$field) {
            $companyObject[$field] = $CompanyData.$field
        }
    }

    # Add optional integer fields from CSV if present and non-empty
    $optionalIntFields = @("psaKey")
    foreach ($field in $optionalIntFields) {
        if ($CompanyData.PSObject.Properties.Name -contains $field -and $CompanyData.$field) {
            $companyObject[$field] = [int]::Parse($CompanyData.$field)
        }
    }

    # If partnerId is in CSV and not set via parameter, use CSV value
    if (-not $companyObject.ContainsKey("partnerId")) {
        if ($CompanyData.PSObject.Properties.Name -contains "partnerId" -and $CompanyData.partnerId) {
            $companyObject["partnerId"] = [int]::Parse($CompanyData.partnerId)
        }
    }

    $body = $companyObject | ConvertTo-Json

    if ($WhatIf) {
        Write-Host "WHAT-IF: Would create company '$name'" -ForegroundColor Cyan
        return @{
            Status = "WhatIf"
            Reason = "Dry run mode"
        }
    }

    $uri = "$BaseUri/v2/company"
    $response = Invoke-ApiCall -Method "POST" -Uri $uri -Headers $AuthHeader -Body $body -ErrorContext "Create company '$name'"

    if ($response) {
        try {
            $createdCompany = $response.Content | ConvertFrom-Json
            Write-Host "Created: $name (ID: $($createdCompany.id))" -ForegroundColor Green
            return @{
                Status    = "Created"
                CompanyId = $createdCompany.id
            }
        }
        catch {
            Write-Host "ERROR: Could not parse response for '$name'" -ForegroundColor Red
            return @{
                Status = "Failed"
                Reason = "Invalid API response"
            }
        }
    }
    else {
        return @{
            Status = "Failed"
            Reason = "API error"
        }
    }
}

# ============================================================================
# Main Script
# ============================================================================

try {
    Write-Host "CloudRadial Bulk Company Import" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host ""

    # Validate CSV file
    Write-Host "Validating CSV file: $CsvPath" -ForegroundColor Cyan
    $csv = @(Import-Csv -Path $CsvPath -ErrorAction Stop)

    if ($csv.Count -eq 0) {
        Write-Host "ERROR: CSV file is empty" -ForegroundColor Red
        exit 1
    }

    # Check required columns
    $requiredColumns = @("name")
    $csvColumns = $csv[0].PSObject.Properties.Name

    foreach ($col in $requiredColumns) {
        if ($col -notin $csvColumns) {
            Write-Host "ERROR: Required column missing: $col" -ForegroundColor Red
            exit 1
        }
    }

    # Validate no blank names
    $blankNames = @($csv | Where-Object { -not $_.name -or $_.name.Trim() -eq "" })
    if ($blankNames.Count -gt 0) {
        Write-Host "WARNING: $($blankNames.Count) rows have blank company names and will be skipped" -ForegroundColor Yellow
    }

    # Check for duplicate names in CSV
    $csvNames = $csv | Where-Object { $_.name -and $_.name.Trim() -ne "" } | ForEach-Object { $_.name.ToLower().Trim() }
    $duplicateNames = $csvNames | Group-Object | Where-Object { $_.Count -gt 1 }
    if ($duplicateNames.Count -gt 0) {
        Write-Host "WARNING: $($duplicateNames.Count) duplicate company names found in CSV. Only the first occurrence of each will be imported." -ForegroundColor Yellow
        foreach ($dup in $duplicateNames) {
            Write-Host "  - '$($dup.Name)' appears $($dup.Count) times" -ForegroundColor Yellow
        }
    }

    Write-Host "CSV validated. Found $($csv.Count) companies to process." -ForegroundColor Green
    Write-Host ""

    # Get credentials
    $creds = Get-Credentials
    $authHeader = Get-BasicAuthHeader -PublicKey $creds.PublicKey -PrivateKey $creds.PrivateKey

    # Verify credentials work with a simple API call
    Write-Host "Verifying API credentials..." -ForegroundColor Cyan
    $testResponse = Invoke-ApiCall -Method "GET" -Uri "$BaseUri/v2/odata/company?`$top=1" -Headers $authHeader -ErrorContext "Verify credentials"
    if (-not $testResponse) {
        Write-Host "ERROR: API authentication failed. Check your credentials." -ForegroundColor Red
        exit 1
    }
    Write-Host "API credentials verified." -ForegroundColor Green
    Write-Host ""

    # Get existing companies for duplicate detection
    $existingCompanies = Get-ExistingCompanies -AuthHeader $authHeader
    Write-Host ""

    # Handle resume mode
    $processedCompanies = @()
    if ($Resume -and (Test-Path $CheckpointFile)) {
        $processedCompanies = Get-ProcessedCompanies
        Write-Host "Resume mode: Skipping $($processedCompanies.Count) already-processed companies" -ForegroundColor Yellow
        Write-Host ""
    }

    # Track names we've already seen in this CSV to handle in-file duplicates
    $seenInCsv = @{}

    # Import companies
    $script:Stats.Total = $csv.Count
    $lastRequestTime = [datetime]::MinValue

    foreach ($row in $csv) {
        $name = $row.name

        # Skip blank names
        if (-not $name -or $name.Trim() -eq "") {
            Write-Host "Skipped: (blank name on row)" -ForegroundColor Yellow
            $script:Stats.Skipped++
            continue
        }

        $nameKey = $name.ToLower().Trim()

        # Skip in-file duplicates
        if ($seenInCsv.ContainsKey($nameKey)) {
            Write-Host "Skipped: '$name' (duplicate in CSV)" -ForegroundColor Yellow
            $script:Stats.Skipped++
            continue
        }
        $seenInCsv[$nameKey] = $true

        # Check if already processed in a previous run
        if ($nameKey -in ($processedCompanies | ForEach-Object { $_.ToLower().Trim() })) {
            Write-Host "Skipped: '$name' (already processed in previous run)" -ForegroundColor Yellow
            $script:Stats.Skipped++
            continue
        }

        # Rate limiting
        $timeSinceLastRequest = [datetime]::Now - $lastRequestTime
        if ($timeSinceLastRequest -lt $DelayBetweenRequests) {
            Start-Sleep -Milliseconds ($DelayBetweenRequests - $timeSinceLastRequest).TotalMilliseconds
        }

        # Import the company
        $result = Import-Company -CompanyData $row -AuthHeader $authHeader -ExistingCompanies $existingCompanies

        switch ($result.Status) {
            "Created" {
                $script:Stats.Created++
                Save-Checkpoint -CompanyName $nameKey
                # Add to existing companies so subsequent duplicates are caught
                $existingCompanies[$nameKey] = $result.CompanyId
            }
            "WhatIf" {
                $script:Stats.Created++
            }
            "Skipped" {
                Write-Host "Skipped: '$name' ($($result.Reason))" -ForegroundColor Yellow
                $script:Stats.Skipped++
                Save-Checkpoint -CompanyName $nameKey
            }
            "Failed" {
                Write-Host "Failed: '$name' ($($result.Reason))" -ForegroundColor Red
                $script:Stats.Failed++
            }
        }

        $lastRequestTime = [datetime]::Now
    }

    # Summary
    Write-Host ""
    Write-Host "Import Summary" -ForegroundColor Cyan
    Write-Host "==============" -ForegroundColor Cyan
    Write-Host "Total processed: $($script:Stats.Total)" -ForegroundColor White
    Write-Host "Created: $($script:Stats.Created)" -ForegroundColor Green
    Write-Host "Skipped: $($script:Stats.Skipped)" -ForegroundColor Yellow
    Write-Host "Failed: $($script:Stats.Failed)" -ForegroundColor Red

    if ($WhatIf) {
        Write-Host ""
        Write-Host "Note: This was a dry run (WhatIf). No companies were actually created." -ForegroundColor Cyan
    }

    if ($script:Stats.Failed -gt 0 -and -not $WhatIf) {
        Write-Host ""
        Write-Host "To resume from where it left off, run:" -ForegroundColor Yellow
        Write-Host "  .\Import-CloudRadialCompanies.ps1 -CsvPath `"$CsvPath`" -Resume" -ForegroundColor Yellow
    }

    exit 0

}
catch {
    Write-Host "FATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
