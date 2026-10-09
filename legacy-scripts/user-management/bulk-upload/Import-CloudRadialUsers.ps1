<#
.SYNOPSIS
    Import users into CloudRadial from a CSV file using the v2 API.

.DESCRIPTION
    Bulk imports users into a CloudRadial company from a CSV file. Validates CSV format,
    checks for existing users, and handles API authentication, rate limiting, and retries
    with exponential backoff. Supports dry-run mode (-WhatIf) and resumable imports after
    errors (-Resume).

    Credentials are read from environment variables CLOUDRADIAL_API_USERNAME and
    CLOUDRADIAL_API_PASSWORD, with interactive fallback if not set.

.PARAMETER CsvPath
    Mandatory. Path to the CSV file containing user data. Required columns: email,
    firstName, lastName, userName. Optional columns: department, title, phoneNumber,
    mobilePhone, country, streetAddress, city, state, postalCode, psaKey,
    psaSiteKey, psaChildAccountKey.

.PARAMETER CompanyId
    Mandatory. The numeric ID of the CloudRadial company to import users into.

.PARAMETER BaseUri
    Optional. CloudRadial API base URL. Defaults to https://api.us.cloudradial.com.

.PARAMETER RequestsPerMinute
    Optional. Rate limit for API requests. Defaults to 12 (5-second delay between requests).

.PARAMETER MaxRetries
    Optional. Maximum number of retries for failed API calls. Defaults to 3.

.PARAMETER WhatIf
    Optional. Show what would happen without making changes.

.PARAMETER Resume
    Optional. Resume a previous import using the checkpoint file. Skips users already
    processed successfully.

.EXAMPLE
    .\Import-CloudRadialUsers.ps1 -CsvPath ".\users.csv" -CompanyId 42

.EXAMPLE
    .\Import-CloudRadialUsers.ps1 -CsvPath ".\users.csv" -CompanyId 42 -WhatIf

.EXAMPLE
    .\Import-CloudRadialUsers.ps1 -CsvPath ".\users.csv" -CompanyId 42 -Resume

#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CsvPath,

    [Parameter(Mandatory = $true)]
    [int]$CompanyId,

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
$CheckpointFile = "$([IO.Path]::GetDirectoryName($CsvPath))\$([IO.Path]::GetFileNameWithoutExtension($CsvPath))_checkpoint_$($CompanyId).txt"

$script:Stats = @{
    Total     = 0
    Created   = 0
    Skipped   = 0
    Failed    = 0
    Processed = @{}
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

function Test-CompanyExists {
    param(
        [Parameter(Mandatory = $true)]
        [int]$CompanyId,

        [Parameter(Mandatory = $true)]
        [hashtable]$AuthHeader
    )

    Write-Host "Verifying company ID $CompanyId exists..." -ForegroundColor Cyan

    $uri = "$BaseUri/v2/odata/company?`$filter=id eq $CompanyId&`$top=1"
    $response = Invoke-ApiCall -Method "GET" -Uri $uri -Headers $AuthHeader -ErrorContext "Verify company exists"

    if (-not $response) {
        return $false
    }

    try {
        $data = $response.Content | ConvertFrom-Json
        if ($data.value -and $data.value.Count -gt 0) {
            Write-Host "Company found: $($data.value[0].name)" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Host "ERROR: Failed to parse company response" -ForegroundColor Red
    }

    return $false
}

function Get-ExistingUsers {
    param(
        [Parameter(Mandatory = $true)]
        [int]$CompanyId,

        [Parameter(Mandatory = $true)]
        [hashtable]$AuthHeader
    )

    Write-Host "Fetching existing users for company $CompanyId..." -ForegroundColor Cyan

    $existingUsers = @{}
    $uri = "$BaseUri/v2/odata/user?`$filter=companyId eq $CompanyId&`$select=id,email&`$top=1000"

    while ($uri) {
        $response = Invoke-ApiCall -Method "GET" -Uri $uri -Headers $AuthHeader -ErrorContext "Fetch existing users"

        if (-not $response) {
            Write-Host "WARNING: Could not fetch all existing users" -ForegroundColor Yellow
            break
        }

        try {
            $data = $response.Content | ConvertFrom-Json
            foreach ($user in $data.value) {
                $existingUsers[$user.email.ToLower()] = $user.id
            }

            # Check for next page
            $uri = $data."@odata.nextLink"
        }
        catch {
            Write-Host "WARNING: Failed to parse existing users response" -ForegroundColor Yellow
            break
        }
    }

    Write-Host "Found $($existingUsers.Count) existing users" -ForegroundColor Green
    return $existingUsers
}

function Save-Checkpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Email
    )

    Add-Content -Path $CheckpointFile -Value $Email -ErrorAction SilentlyContinue
}

function Get-ProcessedEmails {
    if (Test-Path $CheckpointFile) {
        return @(Get-Content -Path $CheckpointFile -ErrorAction SilentlyContinue) | Where-Object { $_ }
    }
    return @()
}

function Import-User {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$UserData,

        [Parameter(Mandatory = $true)]
        [int]$CompanyId,

        [Parameter(Mandatory = $true)]
        [hashtable]$AuthHeader,

        [hashtable]$ExistingUsers
    )

    $email = $UserData.email.ToLower()

    # Check if already exists
    if ($ExistingUsers.ContainsKey($email)) {
        return @{
            Status = "Skipped"
            Reason = "Already exists in company"
            UserId = $ExistingUsers[$email]
        }
    }

    # Build user object
    $userObject = @{
        email     = $UserData.email
        firstName = $UserData.firstName
        lastName  = $UserData.lastName
        userName  = $UserData.userName
        companyId = $CompanyId
    }

    # Add optional fields if present
    $optionalFields = @(
        "phoneNumber",
        "mobilePhone",
        "department",
        "title",
        "country",
        "streetAddress",
        "city",
        "state",
        "postalCode"
    )


    $intFields = @(
        "psaKey",
        "psaSiteKey",
        "psaChildAccountKey"
    )

    foreach ($field in $optionalFields) {
        if ($UserData.PSObject.Properties.Name -contains $field -and $UserData.$field) {
            $userObject[$field] = $UserData.$field
        }
    }


    foreach ($field in $intFields) {
        if ($UserData.PSObject.Properties.Name -contains $field -and $UserData.$field) {
            $userObject[$field] = [int]::Parse($UserData.$field)
        }
    }

    $body = $userObject | ConvertTo-Json

    if ($WhatIf) {
        Write-Host "WHAT-IF: Would create user $email" -ForegroundColor Cyan
        return @{
            Status = "WhatIf"
            Reason = "Dry run mode"
        }
    }

    $uri = "$BaseUri/v2/user"
    $response = Invoke-ApiCall -Method "POST" -Uri $uri -Headers $AuthHeader -Body $body -ErrorContext "Create user $email"

    if ($response) {
        try {
            $createdUser = $response.Content | ConvertFrom-Json
            Write-Host "Created: $email (ID: $($createdUser.id))" -ForegroundColor Green
            return @{
                Status = "Created"
                UserId = $createdUser.id
            }
        }
        catch {
            Write-Host "ERROR: Could not parse response for $email" -ForegroundColor Red
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
    Write-Host "CloudRadial Bulk User Import" -ForegroundColor Cyan
    Write-Host "=============================" -ForegroundColor Cyan
    Write-Host ""

    # Validate CSV file
    Write-Host "Validating CSV file: $CsvPath" -ForegroundColor Cyan
    $csv = @(Import-Csv -Path $CsvPath -ErrorAction Stop)

    if ($csv.Count -eq 0) {
        Write-Host "ERROR: CSV file is empty" -ForegroundColor Red
        exit 1
    }

    # Check required columns
    $requiredColumns = @("email", "firstName", "lastName", "userName")
    $csvColumns = $csv[0].PSObject.Properties.Name

    foreach ($col in $requiredColumns) {
        if ($col -notin $csvColumns) {
            Write-Host "ERROR: Required column missing: $col" -ForegroundColor Red
            exit 1
        }
    }

    Write-Host "CSV validated. Found $($csv.Count) users to import." -ForegroundColor Green
    Write-Host ""

    # Get credentials
    $creds = Get-Credentials
    $authHeader = Get-BasicAuthHeader -PublicKey $creds.PublicKey -PrivateKey $creds.PrivateKey

    # Verify company exists
    if (-not (Test-CompanyExists -CompanyId $CompanyId -AuthHeader $authHeader)) {
        Write-Host "ERROR: Company ID $CompanyId not found" -ForegroundColor Red
        exit 1
    }

    Write-Host ""

    # Get existing users
    $existingUsers = Get-ExistingUsers -CompanyId $CompanyId -AuthHeader $authHeader
    Write-Host ""

    # Handle resume mode
    $processedEmails = @()
    if ($Resume -and (Test-Path $CheckpointFile)) {
        $processedEmails = Get-ProcessedEmails
        Write-Host "Resume mode: Skipping $($processedEmails.Count) already-processed users" -ForegroundColor Yellow
        Write-Host ""
    }

    # Import users
    $script:Stats.Total = $csv.Count
    $lastRequestTime = [datetime]::MinValue

    foreach ($row in $csv) {
        $email = $row.email.ToLower()

        # Check if already processed
        if ($email -in $processedEmails) {
            Write-Host "Skipped: $email (already processed in previous run)" -ForegroundColor Yellow
            $script:Stats.Skipped++
            continue
        }

        # Rate limiting
        $timeSinceLastRequest = [datetime]::Now - $lastRequestTime
        if ($timeSinceLastRequest -lt $DelayBetweenRequests) {
            Start-Sleep -Milliseconds ($DelayBetweenRequests - $timeSinceLastRequest).TotalMilliseconds
        }

        # Import the user
        $result = Import-User -UserData $row -CompanyId $CompanyId -AuthHeader $authHeader -ExistingUsers $existingUsers

        switch ($result.Status) {
            "Created" {
                $script:Stats.Created++
                Save-Checkpoint -Email $email
            }
            "WhatIf" {
                $script:Stats.Created++
            }
            "Skipped" {
                Write-Host "Skipped: $email ($($result.Reason))" -ForegroundColor Yellow
                $script:Stats.Skipped++
                Save-Checkpoint -Email $email
            }
            "Failed" {
                Write-Host "Failed: $email ($($result.Reason))" -ForegroundColor Red
                $script:Stats.Failed++
            }
        }

        $lastRequestTime = [datetime]::Now
    }

    # Summary
    Write-Host ""
    Write-Host "Import Summary" -ForegroundColor Cyan
    Write-Host "==============" -ForegroundColor Cyan
    Write-Host "Total processed:  $($script:Stats.Total)" -ForegroundColor White
    Write-Host "Created:          $($script:Stats.Created)" -ForegroundColor Green
    Write-Host "Skipped:          $($script:Stats.Skipped)" -ForegroundColor Yellow
    Write-Host "Failed:           $($script:Stats.Failed)" -ForegroundColor Red

    if ($WhatIf) {
        Write-Host ""
        Write-Host "Note: This was a dry run (WhatIf). No users were actually created." -ForegroundColor Cyan
    }

    if ($script:Stats.Failed -gt 0 -and -not $WhatIf) {
        Write-Host ""
        Write-Host "To resume from where it left off, run:" -ForegroundColor Yellow
        Write-Host "  .\Import-CloudRadialUsers.ps1 -CsvPath `"$CsvPath`" -CompanyId $CompanyId -Resume" -ForegroundColor Yellow
    }

    exit 0

}
catch {
    Write-Host "FATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
