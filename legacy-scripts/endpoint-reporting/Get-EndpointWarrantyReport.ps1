<#
.SYNOPSIS
    Generates a warranty status report for all CloudRadial-managed endpoints.

.DESCRIPTION
    Pulls endpoints from the CloudRadial API (all companies or filtered by company name),
    evaluates warranty status based on the expirationDate field, and exports a CSV report.

    Each endpoint is classified as:
      - InWarranty     : expiration date is beyond the warning threshold
      - ExpiringSoon   : expiration date is within the warning threshold
      - Expired        : expiration date has passed
      - Unknown        : no expiration date on record

.PARAMETER PublicKey
    CloudRadial API public key. Found in Settings > API in your portal.

.PARAMETER PrivateKey
    CloudRadial API private key.

.PARAMETER BaseUrl
    Base URL for the CloudRadial API. Defaults to https://api.us.cloudradial.com.
    EU partners should use https://api.eu.cloudradial.com.

.PARAMETER CompanyName
    Optional. Filter endpoints to a single company (case-insensitive substring match).

.PARAMETER ExpirationThresholdDays
    Number of days to flag as "ExpiringSoon". Defaults to 90.

.PARAMETER OutputPath
    Path for the CSV report. Defaults to EndpointWarrantyReport.csv in the current directory.

.PARAMETER PageSize
    Number of records per API page. Max 200. Defaults to 200.

.EXAMPLE
    .\Get-EndpointWarrantyReport.ps1 -PublicKey "abc" -PrivateKey "xyz"
    Generates a warranty report for all companies, exported to EndpointWarrantyReport.csv.

.EXAMPLE
    .\Get-EndpointWarrantyReport.ps1 -PublicKey "abc" -PrivateKey "xyz" -CompanyName "Contoso" -ExpirationThresholdDays 60
    Generates a warranty report for Contoso endpoints, flagging anything expiring within 60 days.

.EXAMPLE
    .\Get-EndpointWarrantyReport.ps1 -PublicKey "abc" -PrivateKey "xyz" -WhatIf
    Shows what the script would do without making any file writes.

.NOTES
    Requires PowerShell 5.1+.
    API docs: https://api.us.cloudradial.com/v2/odata/$metadata
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PublicKey,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PrivateKey,

    [string]$BaseUrl = "https://api.us.cloudradial.com",

    [string]$CompanyName,

    [ValidateRange(1, 365)]
    [int]$ExpirationThresholdDays = 90,

    [string]$OutputPath = "EndpointWarrantyReport.csv",

    [ValidateRange(1, 200)]
    [int]$PageSize = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Build auth header ---
$authBytes = [Text.Encoding]::ASCII.GetBytes("$($PublicKey):$($PrivateKey)")
$authHeader = @{ Authorization = "Basic " + [Convert]::ToBase64String($authBytes) }

# --- Helper: page through an OData collection ---
function Get-AllPages {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [int]$Top
    )
    $all = [System.Collections.Generic.List[object]]::new()
    $skip = 0
    do {
        $separator = if ($Uri.Contains("?")) { "&" } else { "?" }
        $pagedUri = "$Uri$separator`$top=$Top&`$skip=$skip"
        Write-Verbose "GET $pagedUri"
        try {
            $response = Invoke-RestMethod -Uri $pagedUri -Headers $Headers -Method Get -ContentType "application/json"
        }
        catch {
            Write-Error "API request failed: $($_.Exception.Message)"
            return $all
        }
        $items = if ($response.value) { $response.value } else { @() }
        foreach ($item in $items) { $all.Add($item) }
        $skip += $Top
    } while ($items.Count -eq $Top)
    return $all
}

# --- Build company lookup (id -> name) ---
Write-Host "Fetching companies..." -ForegroundColor Cyan
$companies = Get-AllPages -Uri "$BaseUrl/v2/odata/company?`$select=companyId,name" -Headers $authHeader -Top $PageSize
$companyMap = @{}
foreach ($c in $companies) {
    $companyMap[$c.companyId] = $c.name
}
Write-Host "  Found $($companies.Count) companies." -ForegroundColor Green

# --- Fetch endpoints ---
Write-Host "Fetching endpoints..." -ForegroundColor Cyan
$endpointSelect = "companyEndpointId,companyId,name,serialNumber,expirationDate,manufacturer,model"
$endpointUri = "$BaseUrl/v2/odata/endpoint?`$select=$endpointSelect"
$endpoints = Get-AllPages -Uri $endpointUri -Headers $authHeader -Top $PageSize
Write-Host "  Found $($endpoints.Count) endpoints." -ForegroundColor Green

# --- Filter by company name if specified ---
if ($CompanyName) {
    $endpoints = $endpoints | Where-Object {
        $cName = $companyMap[$_.companyId]
        $cName -and $cName -like "*$CompanyName*"
    }
    Write-Host "  Filtered to $($endpoints.Count) endpoints matching '$CompanyName'." -ForegroundColor Yellow
}

# --- Classify warranty status ---
$today = (Get-Date).Date
$thresholdDate = $today.AddDays($ExpirationThresholdDays)
$nullDate = [datetime]::Parse("0001-01-01T00:00:00Z")

$report = foreach ($ep in $endpoints) {
    $expDate = $null
    $status = "Unknown"
    $daysRemaining = $null

    if ($ep.expirationDate -and $ep.expirationDate -ne "0001-01-01T00:00:00Z") {
        try {
            $expDate = [datetime]::Parse($ep.expirationDate)
            if ($expDate -le $nullDate.AddDays(1)) {
                $status = "Unknown"
                $expDate = $null
            }
            else {
                $daysRemaining = ($expDate - $today).Days
                if ($expDate -lt $today) {
                    $status = "Expired"
                }
                elseif ($expDate -le $thresholdDate) {
                    $status = "ExpiringSoon"
                }
                else {
                    $status = "InWarranty"
                }
            }
        }
        catch {
            $status = "Unknown"
        }
    }

    [PSCustomObject]@{
        CompanyName   = $companyMap[$ep.companyId]
        EndpointName  = $ep.name
        SerialNumber  = $ep.serialNumber
        Manufacturer  = $ep.manufacturer
        Model         = $ep.model
        WarrantyStart = ""  # Not tracked in CloudRadial; included for CSV template completeness
        WarrantyEnd   = if ($expDate) { $expDate.ToString("yyyy-MM-dd") } else { "" }
        Status        = $status
        DaysRemaining = if ($null -ne $daysRemaining) { $daysRemaining } else { "" }
    }
}

# --- Summary ---
$grouped = $report | Group-Object Status
Write-Host "`nWarranty Summary:" -ForegroundColor Cyan
foreach ($g in $grouped | Sort-Object Name) {
    $color = switch ($g.Name) {
        "Expired"      { "Red" }
        "ExpiringSoon" { "Yellow" }
        "InWarranty"   { "Green" }
        default        { "Gray" }
    }
    Write-Host "  $($g.Name): $($g.Count)" -ForegroundColor $color
}
Write-Host "  Total: $($report.Count)" -ForegroundColor Cyan

# --- Export ---
if ($PSCmdlet.ShouldProcess($OutputPath, "Export $($report.Count) endpoint warranty records to CSV")) {
    $report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "`nReport saved to $OutputPath" -ForegroundColor Green
}
