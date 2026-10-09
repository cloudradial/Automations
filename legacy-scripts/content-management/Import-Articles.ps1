<#
.SYNOPSIS
    Bulk-creates KB articles in CloudRadial from a CSV file.

.DESCRIPTION
    Reads a CSV file with article definitions and creates each one via POST to the
    CloudRadial API. Articles use the "subject" field (not "title") per the API schema.

    The CSV must have columns: CompanyId, Subject, Category, Body, IsPublished
    - CompanyId: numeric company ID in CloudRadial
    - Subject: article title/headline
    - Category: article category for portal navigation
    - Body: HTML or plain-text body content
    - IsPublished: true/false (false = draft, recommended for review before publishing)

    Use -WhatIf to preview what would be created without making any API calls.

.PARAMETER PublicKey
    CloudRadial API public key.

.PARAMETER PrivateKey
    CloudRadial API private key.

.PARAMETER BaseUrl
    Base URL for the CloudRadial API. Defaults to https://api.us.cloudradial.com.

.PARAMETER CsvPath
    Path to the input CSV file. Required.

.PARAMETER StopOnError
    If set, stop processing on the first API error. By default, errors are logged
    and the script continues with the next row.

.EXAMPLE
    .\Import-Articles.ps1 -PublicKey "abc" -PrivateKey "xyz" -CsvPath ".\articles.csv"
    Creates all articles defined in the CSV.

.EXAMPLE
    .\Import-Articles.ps1 -PublicKey "abc" -PrivateKey "xyz" -CsvPath ".\articles.csv" -WhatIf
    Shows what would be created without making any API calls.

.EXAMPLE
    .\Import-Articles.ps1 -PublicKey "abc" -PrivateKey "xyz" -CsvPath ".\articles.csv" -StopOnError
    Creates articles but stops on the first failure.

.NOTES
    Requires PowerShell 5.1+.
    API endpoint: POST /v2/odata/article
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

    [Parameter(Mandatory)]
    [ValidateScript({
        if (-not (Test-Path $_)) { throw "CSV file not found: $_" }
        $true
    })]
    [string]$CsvPath,

    [switch]$StopOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Build auth header ---
$authBytes = [Text.Encoding]::ASCII.GetBytes("$($PublicKey):$($PrivateKey)")
$authHeader = @{ Authorization = "Basic " + [Convert]::ToBase64String($authBytes) }

# --- Read and validate CSV ---
Write-Host "Reading CSV from $CsvPath..." -ForegroundColor Cyan
$rows = Import-Csv -Path $CsvPath -Encoding UTF8

$requiredColumns = @("CompanyId", "Subject", "Category", "Body", "IsPublished")
$csvColumns = $rows[0].PSObject.Properties.Name
$missing = $requiredColumns | Where-Object { $_ -notin $csvColumns }
if ($missing) {
    throw "CSV is missing required columns: $($missing -join ', '). Expected: $($requiredColumns -join ', ')"
}

Write-Host "  Found $($rows.Count) article(s) to import." -ForegroundColor Green

# --- Process each row ---
$successCount = 0
$errorCount = 0
$articleUri = "$BaseUrl/v2/odata/article"

for ($i = 0; $i -lt $rows.Count; $i++) {
    $row = $rows[$i]
    $rowNum = $i + 1
    $displayName = "Row $rowNum: '$($row.Subject)' (Company $($row.CompanyId))"

    # Validate required fields
    if (-not $row.CompanyId -or -not $row.Subject) {
        Write-Warning "Skipping $displayName - CompanyId and Subject are required."
        $errorCount++
        continue
    }

    # Parse IsPublished to boolean
    $published = $false
    if ($row.IsPublished -match "^(true|1|yes)$") {
        $published = $true
    }

    # Build the article payload
    $body = @{
        companyId     = [int]$row.CompanyId
        subject       = $row.Subject
        category      = $row.Category
        body          = $row.Body
        datePublished = if ($published) { (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $null }
    } | ConvertTo-Json -Depth 5

    if ($PSCmdlet.ShouldProcess($displayName, "Create article via POST $articleUri")) {
        try {
            Write-Verbose "POST $articleUri"
            $result = Invoke-RestMethod -Uri $articleUri -Headers $authHeader -Method Post `
                -Body $body -ContentType "application/json"
            $newId = if ($result.articleId) { $result.articleId } else { "unknown" }
            Write-Host "  Created: $($row.Subject) (articleId: $newId)" -ForegroundColor Green
            $successCount++
        }
        catch {
            $errorMsg = $_.Exception.Message
            Write-Warning "  Failed: $displayName - $errorMsg"
            $errorCount++
            if ($StopOnError) {
                throw "Stopping on error (row $rowNum): $errorMsg"
            }
        }
    }
}

# --- Summary ---
Write-Host "`nImport Complete:" -ForegroundColor Cyan
Write-Host "  Succeeded: $successCount" -ForegroundColor Green
if ($errorCount -gt 0) {
    Write-Host "  Failed:    $errorCount" -ForegroundColor Red
}
Write-Host "  Total:     $($rows.Count)" -ForegroundColor Cyan
