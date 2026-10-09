# Domain Expiration Report

Sweep all managed domains across CloudRadial companies for upcoming expirations.

## What It Does

- Pulls all domain records across all companies (or filtered by company name)
- Classifies each domain: **Active**, **ExpiringSoon**, **Expired**, or **Unknown**
- Prints a color-coded summary to the console
- Exports a CSV with one row per domain

## Prerequisites

- PowerShell 5.1 or later
- CloudRadial API keys (Settings > API in your portal)

## Usage

```powershell
# All companies, default 90-day threshold
.\Get-DomainExpirationReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE"

# Single company, 30-day threshold
.\Get-DomainExpirationReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" `
    -CompanyName "Contoso" -ExpirationThresholdDays 30

# Custom output path
.\Get-DomainExpirationReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" `
    -OutputPath "C:\Reports\domains.csv"

# Dry run
.\Get-DomainExpirationReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" -WhatIf
```

## CSV Columns

| Column | Description |
|--------|-------------|
| CompanyName | Company that owns the domain |
| DomainName | Fully qualified domain name |
| Registrar | Domain registrar (if recorded) |
| Source | Where the domain was discovered (e.g., Office365) |
| IsVerified | Whether the domain is verified in CloudRadial |
| ExpirationDate | Expiration date (yyyy-MM-dd) |
| Status | Active, ExpiringSoon, Expired, or Unknown |
| DaysRemaining | Days until expiration (negative = overdue) |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-PublicKey` | *(required)* | API public key |
| `-PrivateKey` | *(required)* | API private key |
| `-BaseUrl` | `https://api.us.cloudradial.com` | API base URL |
| `-CompanyName` | *(all)* | Filter to one company (substring match) |
| `-ExpirationThresholdDays` | `90` | Days before expiry to flag as ExpiringSoon |
| `-OutputPath` | `DomainExpirationReport.csv` | Output CSV path |
| `-PageSize` | `200` | Records per API page (max 200) |

## Customization Tips

- **Office 365 domains**: Many domains sourced from O365 sync may not have registrar expiration dates. Filter by `Source` to separate them.
- **Alert integration**: Pipe expired/expiring domains to your PSA or Slack webhook for automated alerts.
- **Combine with certificate report**: Run alongside `Get-CertificateExpirationReport.ps1` for a full renewal calendar.
