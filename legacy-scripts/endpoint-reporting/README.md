# Endpoint Warranty Report

Generate a warranty expiration report for all CloudRadial-managed endpoints.

## What It Does

- Pulls all endpoints across all companies (or filtered by company name)
- Classifies each device: **InWarranty**, **ExpiringSoon**, **Expired**, or **Unknown**
- Prints a color-coded summary to the console
- Exports a CSV with one row per endpoint

## Prerequisites

- PowerShell 5.1 or later
- CloudRadial API keys (Settings > API in your portal)

## Usage

```powershell
# All companies, default 90-day threshold
.\Get-EndpointWarrantyReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE"

# Single company, 60-day threshold
.\Get-EndpointWarrantyReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" `
    -CompanyName "Contoso" -ExpirationThresholdDays 60

# Custom output path
.\Get-EndpointWarrantyReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" `
    -OutputPath "C:\Reports\warranty.csv"

# Dry run (no file written)
.\Get-EndpointWarrantyReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" -WhatIf

# Verbose API logging
.\Get-EndpointWarrantyReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" -Verbose
```

## CSV Columns

| Column | Description |
|--------|-------------|
| CompanyName | Company the endpoint belongs to |
| EndpointName | Device hostname |
| SerialNumber | Hardware serial number |
| Manufacturer | Device manufacturer |
| Model | Device model |
| WarrantyStart | Reserved (not tracked by CloudRadial) |
| WarrantyEnd | Expiration date (yyyy-MM-dd) |
| Status | InWarranty, ExpiringSoon, Expired, or Unknown |
| DaysRemaining | Days until expiration (negative = overdue) |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-PublicKey` | *(required)* | API public key |
| `-PrivateKey` | *(required)* | API private key |
| `-BaseUrl` | `https://api.us.cloudradial.com` | API base URL (use `https://api.eu.cloudradial.com` for EU) |
| `-CompanyName` | *(all)* | Filter to one company (substring match) |
| `-ExpirationThresholdDays` | `90` | Days before expiry to flag as ExpiringSoon |
| `-OutputPath` | `EndpointWarrantyReport.csv` | Output CSV path |
| `-PageSize` | `200` | Records per API page (max 200) |

## Customization Tips

- **Schedule via RMM**: Run on a schedule and email the CSV, or push to a shared drive.
- **Combine with warranty refresh**: Use the CloudRadial `endpoint_update_warranty` API to trigger serial-number lookups before running this report.
- **Filter by status**: Pipe the output to `Import-Csv | Where-Object Status -eq "Expired"` for follow-up workflows.
