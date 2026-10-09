<#
.SYNOPSIS
    Generates an SSL certificate expiration report from CloudRadial.

.DESCRIPTION
    Pulls certificate records from the CloudRadial API (all companies or filtered by name),
    evaluates expiration status based on the expirationDate field, and exports a CSV report.

    Each certificate is classified as:
      - Valid        : expiration date is beyond the warning threshold
      - ExpiringSoon : expiration date is within the warning threshold
      - Expired      : expiration date has passed
      - Unknown      : no valid expiration date on record

.PARAMETER PublicKey
    CloudRadial API public key.

.PARAMETER PrivateKey
    CloudRadial API private key.

.PARAMETER BaseUrl
    Base URL for the CloudRadial API. Defaults to https://api.us.cloudradial.com.

.PARAMETER CompanyName
    Optional. Filter certificates to a single company (case-insensitive substring match).

.PARAMETER ExpirationThresholdDays
    Number of days to flag as "ExpiringSoon". Defaults to 30.

.PARAMETER OutputPath
    Path for the CSV report. Defaults to CertificateExpirationReport.csv in the current directory.

.PARAMETER PageSize
    Number of records per API page. Max 200. Defaults to 200.

.EXAMPLE
    .\Get-CertificateExpirationReport.ps1 -PublicKey "abc" -PrivateKey "xyz"
    Generates a certificate expiration report for all companies.

.EXAMPLE
    .\Get-CertificateExpirationReport.ps1 -PublicKey "abc" -PrivateKey "xyz" -CompanyName "Contoso" -ExpirationThresholdDays 60
    Report for Contoso certificates expiring within 60 days.

.EXAMPLE
    .\Get-CertificateExpirationReport.ps1 -PublicKey "abc" -PrivateKey "xyz" -WhatIf
    Shows what the script would do without writing any files.

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
    [int]$ExpirationThresholdDays = 30,

    [string]$OutputPath = "CertificateExpirationReport.csv",

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

# --- Fetch certificates ---
Write-Host "Fetching certificates..." -ForegroundColor Cyan
$certs = Get-AllPages -Uri "$BaseUrl/v2/odata/certificate" -Headers $authHeader -Top $PageSize
Write-Host "  Found $($certs.Count) certificates." -ForegroundColor Green

# --- Filter by company name if specified ---
if ($CompanyName) {
    $certs = $certs | Where-Object {
        $cName = $companyMap[$_.companyId]
        $cName -and $cName -like "*$CompanyName*"
    }
    Write-Host "  Filtered to $($certs.Count) certificates matching '$CompanyName'." -ForegroundColor Yellow
}

if ($certs.Count -eq 0) {
    Write-Host "`nNo certificates found." -ForegroundColor Yellow
    return
}

# --- Classify expiration status ---
$today = (Get-Date).Date
$thresholdDate = $today.AddDays($ExpirationThresholdDays)

$report = foreach ($cert in $certs) {
    $expDate = $null
    $status = "Unknown"
    $daysRemaining = $null

    if ($cert.expirationDate -and $cert.expirationDate -ne "0001-01-01T00:00:00Z") {
        try {
            $expDate = [datetime]::Parse($cert.expirationDate)
            if ($expDate.Year -le 1) {
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
                    $status = "Valid"
                }
            }
        }
        catch {
            $status = "Unknown"
        }
    }

    # Extract a short issuer name from the full CN string
    $issuerShort = $cert.issuer
    if ($issuerShort -match "CN=([^,]+)") {
        $issuerShort = $Matches[1]
    }

    [PSCustomObject]@{
        CompanyName    = $companyMap[$cert.companyId]
        CertificateName = $cert.name
        URL            = $cert.url
        Issuer         = $issuerShort
        SerialNumber   = $cert.serialNumber
        KeyLength      = $cert.publicKeyLength
        IsValid        = $cert.isValid
        ExpirationDate = if ($expDate) { $expDate.ToString("yyyy-MM-dd") } else { "" }
        Status         = $status
        DaysRemaining  = if ($null -ne $daysRemaining) { $daysRemaining } else { "" }
    }
}

# --- Summary ---
$grouped = $report | Group-Object Status
Write-Host "`nCertificate Expiration Summary:" -ForegroundColor Cyan
foreach ($g in $grouped | Sort-Object Name) {
    $color = switch ($g.Name) {
        "Expired"      { "Red" }
        "ExpiringSoon" { "Yellow" }
        "Valid"        { "Green" }
        default        { "Gray" }
    }
    Write-Host "  $($g.Name): $($g.Count)" -ForegroundColor $color
}
Write-Host "  Total: $($report.Count)" -ForegroundColor Cyan

# --- Export ---
if ($PSCmdlet.ShouldProcess($OutputPath, "Export $($report.Count) certificate records to CSV")) {
    $report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "`nReport saved to $OutputPath" -ForegroundColor Green
}
