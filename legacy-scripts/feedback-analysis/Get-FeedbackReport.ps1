<#
.SYNOPSIS
    Exports feedback data and calculates CSAT averages per company from CloudRadial.

.DESCRIPTION
    Pulls feedback entries from the CloudRadial API (all companies or filtered by name),
    exports a detailed CSV, and prints per-company CSAT summary statistics.

    The feedbackRating field values are mapped to numeric scores:
      Positive = 3, Neutral = 2, Negative = 1

    feedbackRatingNumber (0-10 scale) is used when available; otherwise the
    mapped feedbackRating value is used.

.PARAMETER PublicKey
    CloudRadial API public key.

.PARAMETER PrivateKey
    CloudRadial API private key.

.PARAMETER BaseUrl
    Base URL for the CloudRadial API. Defaults to https://api.us.cloudradial.com.

.PARAMETER CompanyName
    Optional. Filter feedback to a single company (case-insensitive substring match).

.PARAMETER DaysBack
    Only include feedback from the last N days. Default: all feedback.

.PARAMETER OutputPath
    Path for the CSV report. Defaults to FeedbackReport.csv in the current directory.

.PARAMETER PageSize
    Number of records per API page. Max 200. Defaults to 200.

.EXAMPLE
    .\Get-FeedbackReport.ps1 -PublicKey "abc" -PrivateKey "xyz"
    Exports all feedback across all companies.

.EXAMPLE
    .\Get-FeedbackReport.ps1 -PublicKey "abc" -PrivateKey "xyz" -CompanyName "Contoso" -DaysBack 90
    Exports Contoso's feedback from the last 90 days.

.EXAMPLE
    .\Get-FeedbackReport.ps1 -PublicKey "abc" -PrivateKey "xyz" -WhatIf
    Shows what would be exported without writing a file.

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

    [ValidateRange(1, 3650)]
    [int]$DaysBack,

    [string]$OutputPath = "FeedbackReport.csv",

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

# --- Fetch feedback ---
Write-Host "Fetching feedback entries..." -ForegroundColor Cyan
$feedbackUri = "$BaseUrl/v2/odata/feedback"
$filters = @()

if ($DaysBack) {
    $cutoff = (Get-Date).AddDays(-$DaysBack).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $filters += "dateCreated ge $cutoff"
}

if ($filters.Count -gt 0) {
    $feedbackUri += "?`$filter=$($filters -join ' and ')"
}

$feedback = Get-AllPages -Uri $feedbackUri -Headers $authHeader -Top $PageSize
Write-Host "  Found $($feedback.Count) feedback entries." -ForegroundColor Green

# --- Filter by company name if specified ---
if ($CompanyName) {
    $feedback = $feedback | Where-Object {
        $_.companyName -and $_.companyName -like "*$CompanyName*"
    }
    Write-Host "  Filtered to $($feedback.Count) entries matching '$CompanyName'." -ForegroundColor Yellow
}

if ($feedback.Count -eq 0) {
    Write-Host "`nNo feedback entries found." -ForegroundColor Yellow
    return
}

# --- Map rating to numeric score ---
function Get-NumericRating {
    param($FeedbackItem)
    # Prefer the numeric rating if it's set (non-zero)
    if ($FeedbackItem.feedbackRatingNumber -and $FeedbackItem.feedbackRatingNumber -gt 0) {
        return $FeedbackItem.feedbackRatingNumber
    }
    # Fall back to text-based rating
    switch ($FeedbackItem.feedbackRating) {
        "Positive" { return 3 }
        "Neutral"  { return 2 }
        "Negative" { return 1 }
        default    { return $null }
    }
}

# --- Build report rows ---
$report = foreach ($fb in $feedback) {
    $rating = Get-NumericRating -FeedbackItem $fb
    [PSCustomObject]@{
        CompanyName   = $fb.companyName
        UserEmail     = $fb.userEmail
        Rating        = $fb.feedbackRating
        RatingNumber  = if ($rating) { $rating } else { "" }
        Comment       = $fb.feedbackComment
        TicketSubject = $fb.ticketSubject
        Date          = if ($fb.dateCreated) { ([datetime]$fb.dateCreated).ToString("yyyy-MM-dd") } else { "" }
        Source        = $fb.source
    }
}

# --- Per-company CSAT summary ---
Write-Host "`nCSAT Summary by Company:" -ForegroundColor Cyan
Write-Host ("-" * 70) -ForegroundColor Gray

$companySummary = $feedback | Group-Object companyName | ForEach-Object {
    $ratings = $_.Group | ForEach-Object { Get-NumericRating -FeedbackItem $_ } | Where-Object { $null -ne $_ }
    $avg = if ($ratings.Count -gt 0) { ($ratings | Measure-Object -Average).Average } else { 0 }
    $positive = ($_.Group | Where-Object { $_.feedbackRating -eq "Positive" }).Count
    $total = $_.Count

    [PSCustomObject]@{
        Company       = $_.Name
        TotalFeedback = $total
        Positive      = $positive
        PositiveRate  = if ($total -gt 0) { [math]::Round(($positive / $total) * 100, 1) } else { 0 }
        AvgRating     = [math]::Round($avg, 2)
    }
} | Sort-Object AvgRating -Descending

foreach ($cs in $companySummary) {
    $color = if ($cs.PositiveRate -ge 80) { "Green" } elseif ($cs.PositiveRate -ge 50) { "Yellow" } else { "Red" }
    Write-Host ("  {0,-30} {1,5} entries  {2,6}% positive  avg {3}" -f $cs.Company, $cs.TotalFeedback, $cs.PositiveRate, $cs.AvgRating) -ForegroundColor $color
}

# --- Export ---
if ($PSCmdlet.ShouldProcess($OutputPath, "Export $($report.Count) feedback records to CSV")) {
    $report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "`nReport saved to $OutputPath" -ForegroundColor Green
}
