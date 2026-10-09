<#
.SYNOPSIS
Create or update device name tokens for CloudRadial companies via the v2 API.

.DESCRIPTION
Populates a company-level token with a comma-separated list of active device names
(endpoints or servers) for one or more CloudRadial companies. The token can be used as
an answer source for multi-select and multi-choice questions in service catalog forms,
ticket forms, and portal content.

Use -DeviceType to choose between Endpoints and Servers. The default token name is set
automatically based on the device type (@EndpointNames or @ServerNames), but can be
overridden with -TokenName.

The script queries the CloudRadial device inventory (populated by the Data Agent or
Datto RMM integration), extracts device names (preferring machineName, falling back to
name), deduplicates and sorts them, then POSTs the comma-separated value to the token API.

Credentials are read from $env:CLOUDRADIAL_API_USERNAME and $env:CLOUDRADIAL_API_PASSWORD,
with interactive fallback via Read-Host.

.PARAMETER DeviceType
(Optional) Type of device to query. Valid values: "Endpoint", "Server".
Default: "Endpoint". Determines which API entity is queried and the default token name.

.PARAMETER CompanyId
(Optional) Integer company ID. If provided, creates token for that company only.
Mutually exclusive with -CompanyName and -AllCompanies.

.PARAMETER CompanyName
(Optional) String company name or partial name. Searches via OData filter contains(tolower(name)).
If multiple matches found, presents a menu for selection.
Mutually exclusive with -CompanyId and -AllCompanies.

.PARAMETER AllCompanies
(Optional) Switch. Iterates all companies in the workspace and creates tokens for each.
Mutually exclusive with -CompanyId and -CompanyName.

.PARAMETER BaseUri
(Optional) CloudRadial API base URL. Default: "https://api.us.cloudradial.com"

.PARAMETER TokenName
(Optional) Bare token name (no @ prefix) to create/update.
Default: "EndpointNames" when DeviceType is Endpoint, "ServerNames" when DeviceType is Server.

.PARAMETER CreateEmptyTokens
(Optional) Switch. If enabled, creates tokens for companies with zero active devices
(with empty value ""). Default behavior skips these companies.

.PARAMETER MaxRetries
(Optional) Maximum retry attempts for 429/5xx responses. Default: 3

.EXAMPLE
# Create @EndpointNames token for a specific company
.\New-EndpointNamesToken.ps1 -CompanyId 42

.EXAMPLE
# Create @ServerNames token for a specific company
.\New-EndpointNamesToken.ps1 -DeviceType Server -CompanyId 42

.EXAMPLE
# Create @EndpointNames tokens for all companies
.\New-EndpointNamesToken.ps1 -AllCompanies

.EXAMPLE
# Create @ServerNames tokens for all companies
.\New-EndpointNamesToken.ps1 -DeviceType Server -AllCompanies

.EXAMPLE
# Create token with a custom name for a company by name search
.\New-EndpointNamesToken.ps1 -CompanyName "Contoso" -TokenName "Computers"

.EXAMPLE
# Create tokens for all companies, including those with no devices
.\New-EndpointNamesToken.ps1 -AllCompanies -CreateEmptyTokens

.NOTES
Requires PowerShell 5.1 or later.
API credentials must be set via environment variables or entered at runtime.
Device data is sourced from the CloudRadial Data Agent or Datto RMM integration.
#>

param(
    [ValidateSet("Endpoint", "Server")]
    [string]$DeviceType = "Endpoint",
    [int]$CompanyId,
    [string]$CompanyName,
    [switch]$AllCompanies,
    [string]$BaseUri = "https://api.us.cloudradial.com",
    [string]$TokenName,
    [switch]$CreateEmptyTokens,
    [int]$MaxRetries = 3
)

# Set default token name based on device type if not explicitly provided
if (-not $TokenName) {
    $TokenName = switch ($DeviceType) {
        "Endpoint" { "EndpointNames" }
        "Server"   { "ServerNames" }
    }
}

#region Helper Functions

function Get-Base64Credentials {
    param(
        [string]$Username,
        [string]$Password
    )
    $credential = "$($Username):$($Password)"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($credential)
    return [System.Convert]::ToBase64String($bytes)
}

function Invoke-CloudRadialApi {
    param(
        [string]$Method,
        [string]$Uri,
        [object]$Body,
        [string]$AuthHeader,
        [int]$MaxRetries = 3
    )

    $attempt = 0
    $backoffMs = 1000

    while ($attempt -lt $MaxRetries) {
        try {
            $params = @{
                Method  = $Method
                Uri     = $Uri
                Headers = @{
                    "Authorization" = "Basic $AuthHeader"
                    "Content-Type"  = "application/json"
                }
            }

            if ($Body) {
                $params["Body"] = $Body | ConvertTo-Json -Depth 10
            }

            $response = Invoke-RestMethod @params -ErrorAction Stop
            return $response
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__

            if ($statusCode -in @(429, 500, 502, 503, 504)) {
                $attempt++
                if ($attempt -lt $MaxRetries) {
                    Write-Warning "API returned $statusCode. Retry $attempt/$MaxRetries in ${backoffMs}ms..."
                    Start-Sleep -Milliseconds $backoffMs
                    $backoffMs *= 2
                    continue
                }
            }

            throw $_
        }
    }
}

function Get-AllCompanies {
    param(
        [string]$BaseUri,
        [string]$AuthHeader,
        [int]$MaxRetries
    )

    $companies = @()
    $nextLink = "$BaseUri/v2/odata/company?\$select=companyId,name&\$orderby=name&\$top=200"

    while ($nextLink) {
        $response = Invoke-CloudRadialApi -Method Get -Uri $nextLink -AuthHeader $AuthHeader -MaxRetries $MaxRetries
        $companies += $response.value
        $nextLink = $response.'@odata.nextLink'
    }

    return $companies
}

function Find-CompaniesByName {
    param(
        [string]$Name,
        [string]$BaseUri,
        [string]$AuthHeader,
        [int]$MaxRetries
    )

    $filter = "contains(tolower(name), tolower('$([uri]::EscapeDataString($Name))'))"
    $uri = "$BaseUri/v2/odata/company?\$filter=$filter&\$select=companyId,name&\$orderby=name&\$top=200"

    $companies = @()
    $nextLink = $uri

    while ($nextLink) {
        $response = Invoke-CloudRadialApi -Method Get -Uri $nextLink -AuthHeader $AuthHeader -MaxRetries $MaxRetries
        $companies += $response.value
        $nextLink = $response.'@odata.nextLink'
    }

    return $companies
}

function Get-ActiveDevices {
    param(
        [string]$DeviceType,
        [int]$CompanyId,
        [string]$BaseUri,
        [string]$AuthHeader,
        [int]$MaxRetries
    )

    $devices = @()

    # Both endpoints and servers live on the /v2/odata/endpoint entity.
    # Servers are endpoints where isServer eq true.
    $serverFilter = switch ($DeviceType) {
        "Endpoint" { "(isServer eq false)" }
        "Server"   { "(isServer eq true)" }
    }

    $nextLink = "$BaseUri/v2/odata/endpoint?`$filter=(companyId eq $CompanyId) and (isBlocked eq false) and $serverFilter&`$select=companyEndpointId,companyId,machineName,name,isServer,isBlocked&`$orderby=machineName&`$top=200"

    while ($nextLink) {
        $response = Invoke-CloudRadialApi -Method Get -Uri $nextLink -AuthHeader $AuthHeader -MaxRetries $MaxRetries
        $devices += $response.value
        $nextLink = $response.'@odata.nextLink'
    }

    return $devices
}

function New-TokenValue {
    param(
        [object[]]$Devices
    )

    $deviceNames = @()

    foreach ($device in $Devices) {
        $deviceName = if ($device.machineName) { $device.machineName } else { $device.name }

        if ($deviceName -and $deviceName.Trim()) {
            $deviceNames += $deviceName.Trim()
        }
    }

    # Deduplicate and sort
    $deviceNames = $deviceNames | Select-Object -Unique | Sort-Object

    return ($deviceNames -join ",")
}

function Create-Token {
    param(
        [int]$CompanyId,
        [string]$Value,
        [string]$TokenName,
        [string]$BaseUri,
        [string]$AuthHeader,
        [int]$MaxRetries
    )

    $body = @{
        companyId = $CompanyId
        token     = $TokenName
        value     = $Value
    }

    $uri = "$BaseUri/v2/token"
    $response = Invoke-CloudRadialApi -Method Post -Uri $uri -Body $body -AuthHeader $AuthHeader -MaxRetries $MaxRetries

    return $response
}

function Format-TokenPreview {
    param(
        [string]$Value,
        [int]$MaxLength = 80
    )

    if ($Value.Length -gt $MaxLength) {
        return $Value.Substring(0, $MaxLength - 3) + "..."
    }
    return $Value
}

#endregion

#region Main Logic

# Load credentials
$apiUsername = $env:CLOUDRADIAL_API_USERNAME
$apiPassword = $env:CLOUDRADIAL_API_PASSWORD

if (-not $apiUsername) {
    $apiUsername = Read-Host "CloudRadial API Username (PublicKey)"
}

if (-not $apiPassword) {
    $apiPassword = Read-Host "CloudRadial API Password (PrivateKey)" -AsSecureString
    $apiPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemURI($apiPassword)
    )
}

$authHeader = Get-Base64Credentials -Username $apiUsername -Password $apiPassword

# Determine target companies
$targetCompanies = @()

if ($CompanyId) {
    $targetCompanies = @(@{ companyId = $CompanyId; name = "Company $CompanyId" })
}
elseif ($CompanyName) {
    Write-Host "Searching for companies matching '$CompanyName'..." -ForegroundColor Cyan
    $matches = Find-CompaniesByName -Name $CompanyName -BaseUri $BaseUri -AuthHeader $authHeader -MaxRetries $MaxRetries

    if ($matches.Count -eq 0) {
        Write-Error "No companies found matching '$CompanyName'"
        exit 1
    }

    if ($matches.Count -eq 1) {
        $targetCompanies = $matches
    }
    else {
        Write-Host "`nMultiple matches found:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $matches.Count; $i++) {
            Write-Host "$($i + 1). [$($matches[$i].companyId)] $($matches[$i].name)"
        }

        $selection = Read-Host "Select company (enter number)"
        if ($selection -as [int] -gt 0 -and $selection -as [int] -le $matches.Count) {
            $targetCompanies = @($matches[([int]$selection - 1)])
        }
        else {
            Write-Error "Invalid selection"
            exit 1
        }
    }
}
elseif ($AllCompanies) {
    Write-Host "Fetching all companies..." -ForegroundColor Cyan
    $targetCompanies = Get-AllCompanies -BaseUri $BaseUri -AuthHeader $authHeader -MaxRetries $MaxRetries
    Write-Host "Found $($targetCompanies.Count) companies." -ForegroundColor Green
}
else {
    Write-Host "No target specified. Choose an option:" -ForegroundColor Yellow
    Write-Host "  1. Single company (by ID)"
    Write-Host "  2. Single company (by name)"
    Write-Host "  3. All companies"

    $choice = Read-Host "Enter choice (1-3)"

    switch ($choice) {
        "1" {
            $CompanyId = Read-Host "Enter CompanyId"
            $targetCompanies = @(@{ companyId = [int]$CompanyId; name = "Company $CompanyId" })
        }
        "2" {
            $CompanyName = Read-Host "Enter company name (or part of it)"
            $matches = Find-CompaniesByName -Name $CompanyName -BaseUri $BaseUri -AuthHeader $authHeader -MaxRetries $MaxRetries
            if ($matches.Count -eq 0) {
                Write-Error "No companies found"
                exit 1
            }
            if ($matches.Count -gt 1) {
                Write-Host "`nMultiple matches:" -ForegroundColor Yellow
                for ($i = 0; $i -lt $matches.Count; $i++) {
                    Write-Host "$($i + 1). [$($matches[$i].companyId)] $($matches[$i].name)"
                }
                $selection = Read-Host "Select (enter number)"
                $targetCompanies = @($matches[([int]$selection - 1)])
            }
            else {
                $targetCompanies = $matches
            }
        }
        "3" {
            Write-Host "Fetching all companies..." -ForegroundColor Cyan
            $targetCompanies = Get-AllCompanies -BaseUri $BaseUri -AuthHeader $authHeader -MaxRetries $MaxRetries
            Write-Host "Found $($targetCompanies.Count) companies." -ForegroundColor Green
        }
        default {
            Write-Error "Invalid choice"
            exit 1
        }
    }
}

# Process each company
Write-Host "`nDevice type: $DeviceType | Token: @$TokenName" -ForegroundColor Cyan

$created = 0
$skipped = 0
$failed = 0

foreach ($company in $targetCompanies) {
    Write-Host "`n--- [$($company.companyId)] $($company.name) ---" -ForegroundColor Cyan

    try {
        $devices = Get-ActiveDevices -DeviceType $DeviceType -CompanyId $company.companyId -BaseUri $BaseUri -AuthHeader $authHeader -MaxRetries $MaxRetries
        $deviceLabel = if ($DeviceType -eq "Endpoint") { "endpoints" } else { "servers" }
        Write-Host "Found $($devices.Count) active $deviceLabel."

        if ($devices.Count -eq 0 -and -not $CreateEmptyTokens) {
            Write-Host "Skipping (no $deviceLabel, -CreateEmptyTokens not set)" -ForegroundColor Yellow
            $skipped++
            continue
        }

        $tokenValue = New-TokenValue -Devices $devices

        if (-not $tokenValue -and -not $CreateEmptyTokens) {
            Write-Host "Skipping (no valid device names)" -ForegroundColor Yellow
            $skipped++
            continue
        }

        Write-Host "Creating token '@$TokenName'..." -ForegroundColor Cyan
        $preview = Format-TokenPreview -Value $tokenValue
        Write-Host "Token value: $preview" -ForegroundColor Gray

        Create-Token -CompanyId $company.companyId -Value $tokenValue -TokenName $TokenName `
            -BaseUri $BaseUri -AuthHeader $authHeader -MaxRetries $MaxRetries | Out-Null

        Write-Host "Success" -ForegroundColor Green
        $created++
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

# Summary
Write-Host "`n========== SUMMARY ==========" -ForegroundColor Cyan
Write-Host "Created: $created" -ForegroundColor Green
Write-Host "Skipped: $skipped" -ForegroundColor Yellow
Write-Host "Failed:  $failed" -ForegroundColor Red
Write-Host "============================="

if ($failed -gt 0) {
    exit 1
}
