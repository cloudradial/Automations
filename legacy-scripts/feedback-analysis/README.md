# Feedback & CSAT Report

Export feedback data and calculate per-company CSAT averages from CloudRadial.

## What It Does

- Pulls feedback entries across all companies (or filtered by company name / date range)
- Calculates CSAT averages and positive-feedback rates per company
- Prints a color-coded summary table to the console
- Exports a detailed CSV with one row per feedback entry

## Prerequisites

- PowerShell 5.1 or later
- CloudRadial API keys (Settings > API in your portal)

## Usage

```powershell
# All companies, all time
.\Get-FeedbackReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE"

# Single company, last 90 days
.\Get-FeedbackReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" `
    -CompanyName "Contoso" -DaysBack 90

# Custom output path
.\Get-FeedbackReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" `
    -OutputPath "C:\Reports\csat.csv"

# Dry run
.\Get-FeedbackReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" -WhatIf
```

## CSV Columns

| Column | Description |
|--------|-------------|
| CompanyName | Company that submitted the feedback |
| UserEmail | Email of the user who rated |
| Rating | Positive, Neutral, or Negative |
| RatingNumber | Numeric score (1-10 if available, otherwise mapped 1-3) |
| Comment | User's free-text comment |
| TicketSubject | The ticket this feedback is attached to |
| Date | Date the feedback was submitted (yyyy-MM-dd) |
| Source | Where the feedback came from (e.g., StatusView) |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-PublicKey` | *(required)* | API public key |
| `-PrivateKey` | *(required)* | API private key |
| `-BaseUrl` | `https://api.us.cloudradial.com` | API base URL |
| `-CompanyName` | *(all)* | Filter to one company (substring match) |
| `-DaysBack` | *(all time)* | Only include feedback from the last N days |
| `-OutputPath` | `FeedbackReport.csv` | Output CSV path |
| `-PageSize` | `200` | Records per API page (max 200) |

## Customization Tips

- **QBR prep**: Run with `-DaysBack 90 -CompanyName "ClientName"` before quarterly reviews.
- **Trend tracking**: Schedule monthly and compare CSVs over time.
- **Negative follow-up**: Pipe to `Import-Csv | Where-Object Rating -eq "Negative"` to find unhappy users.
