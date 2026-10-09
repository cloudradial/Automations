# Certificate Expiration Report

Check SSL certificates across CloudRadial companies for upcoming expirations.

## What It Does

- Pulls all certificate records across all companies (or filtered by company name)
- Classifies each certificate: **Valid**, **ExpiringSoon**, **Expired**, or **Unknown**
- Extracts a short issuer name from the full CN string
- Prints a color-coded summary to the console
- Exports a CSV with one row per certificate

## Prerequisites

- PowerShell 5.1 or later
- CloudRadial API keys (Settings > API in your portal)

## Usage

```powershell
# All companies, default 30-day threshold
.\Get-CertificateExpirationReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE"

# Single company, 60-day threshold
.\Get-CertificateExpirationReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" `
    -CompanyName "Contoso" -ExpirationThresholdDays 60

# Custom output path
.\Get-CertificateExpirationReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" `
    -OutputPath "C:\Reports\certs.csv"

# Dry run
.\Get-CertificateExpirationReport.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" -WhatIf
```

## CSV Columns

| Column | Description |
|--------|-------------|
| CompanyName | Company the certificate belongs to |
| CertificateName | Display name of the certificate |
| URL | URL the certificate is associated with |
| Issuer | Certificate issuer (short CN name) |
| SerialNumber | Certificate serial number |
| KeyLength | Public key length in bits |
| IsValid | Whether CloudRadial considers the cert valid |
| ExpirationDate | Expiration date (yyyy-MM-dd) |
| Status | Valid, ExpiringSoon, Expired, or Unknown |
| DaysRemaining | Days until expiration (negative = overdue) |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-PublicKey` | *(required)* | API public key |
| `-PrivateKey` | *(required)* | API private key |
| `-BaseUrl` | `https://api.us.cloudradial.com` | API base URL |
| `-CompanyName` | *(all)* | Filter to one company (substring match) |
| `-ExpirationThresholdDays` | `30` | Days before expiry to flag as ExpiringSoon |
| `-OutputPath` | `CertificateExpirationReport.csv` | Output CSV path |
| `-PageSize` | `200` | Records per API page (max 200) |

## Customization Tips

- **Combine with domain report**: Run alongside `Get-DomainExpirationReport.ps1` for a complete renewal calendar.
- **RMM scheduling**: Run weekly and alert on any ExpiringSoon or Expired certificates.
- **Filter by issuer**: After export, use `Import-Csv | Where-Object Issuer -like "*LetsEncrypt*"` to focus on auto-renew certs that may have failed.
