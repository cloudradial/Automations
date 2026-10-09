# Content Bulk Import

Bulk-create KB articles in CloudRadial from a CSV file.

## What It Does

- Reads a CSV with article definitions (subject, category, body, publish flag)
- Creates each article via the CloudRadial API
- Supports `-WhatIf` to preview without creating anything
- Logs successes and failures with a final summary

## Prerequisites

- PowerShell 5.1 or later
- CloudRadial API keys (Settings > API in your portal)

## CSV Template

Create a CSV file with these columns:

```csv
CompanyId,Subject,Category,Body,IsPublished
4,"How to Reset Your Password","Account Help","<p>Go to Settings and click Reset Password.</p>",false
4,"VPN Setup Guide","Remote Access","<p>Download the VPN client from...</p>",false
4,"MFA Enrollment Steps","Security","<p>Open the Authenticator app...</p>",true
```

| Column | Required | Description |
|--------|----------|-------------|
| CompanyId | Yes | Numeric company ID in CloudRadial |
| Subject | Yes | Article headline (called "subject" in the API, not "title") |
| Category | Yes | Category for portal navigation |
| Body | Yes | HTML or plain-text content |
| IsPublished | Yes | `true` or `false` (use false to create as draft) |

## Usage

```powershell
# Import all articles
.\Import-Articles.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" `
    -CsvPath ".\articles.csv"

# Preview only (no API calls)
.\Import-Articles.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" `
    -CsvPath ".\articles.csv" -WhatIf

# Stop on first error
.\Import-Articles.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" `
    -CsvPath ".\articles.csv" -StopOnError
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-PublicKey` | *(required)* | API public key |
| `-PrivateKey` | *(required)* | API private key |
| `-BaseUrl` | `https://api.us.cloudradial.com` | API base URL |
| `-CsvPath` | *(required)* | Path to the input CSV file |
| `-StopOnError` | `false` | Stop on first failure instead of continuing |

## Customization Tips

- **Draft first**: Set `IsPublished` to `false` for all rows, then review in the portal before publishing.
- **HTML formatting**: The Body column accepts full HTML. Use `<p>`, `<ul>`, `<li>`, `<a>` tags for rich content.
- **Seeding new portals**: Pair with the implementation Session 3 checklist to bulk-load starter content.
- **Find company IDs**: Use the companion `company` endpoint or the Portal Lookup skill to look up IDs by name.
