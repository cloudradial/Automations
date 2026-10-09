# Sync IT Glue Flexible Assets to CloudRadial

## Business Problem

You're an MSP using IT Glue for documentation and CloudRadial for your client portal. You've built out Flexible Asset Types in IT Glue (e.g., Network Devices, Backup Systems, ISP Information) and want your clients to see that same data in their CloudRadial portal under the Infrastructure tab — without manually recreating every schema and record.

This script automates the full migration: it reads your IT Glue Flexible Asset Type definitions and their data, then creates matching types and bulk-inserts all asset records into CloudRadial via the IT Glue-compatible V2 API. A CSV mapping file lets you control which IT Glue organizations map to which CloudRadial companies.

## Prerequisites

- **PowerShell 5.1** or later
- **IT Glue API key** — generate one at IT Glue > Account > Settings > API Keys
- **CloudRadial API keys** (Public + Private) — generate at Partner > Settings > Integrations > API > +Add API Key
- **Organization mapping CSV** — a file pairing IT Glue Org IDs to CloudRadial Company IDs (template included)

### Finding Your IDs

**IT Glue Organization IDs:** Navigate to any organization in IT Glue — the ID is in the URL:
```
https://yourcompany.itglue.com/12345/...
                                ^^^^^
```

**CloudRadial Company IDs:** Call the CloudRadial API to list companies:
```powershell
$publicKey  = "YOUR_PUBLIC_KEY"
$privateKey = "YOUR_PRIVATE_KEY"
$authHeader = @{
    Authorization = "Basic " + [Convert]::ToBase64String(
        [Text.Encoding]::ASCII.GetBytes("$($publicKey):$($privateKey)")
    )
}
$companies = Invoke-RestMethod -Uri "https://api.us.cloudradial.com/v2/odata/company" `
    -Headers $authHeader -Method Get
$companies.value | Select-Object id, name | Format-Table
```

## Usage

### 1. Create the mapping CSV

Create a file called `org-mapping.csv` with your org-to-company pairings:

```csv
ITGlueOrgId,CloudRadialCompanyId,OrgName
12345,1001,Contoso Ltd
12346,1002,Fabrikam Inc
12347,1003,Northwind Traders
```

The `OrgName` column is optional — it's used for logging readability only.

### 2. Set your credentials

**Option A: Environment variables (recommended for automation)**
```powershell
$env:ITGLUE_API_KEY              = "ITG.xxxxxxxxxxxxxxxxxxxx"
$env:CLOUDRADIAL_API_PUBLIC_KEY  = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
$env:CLOUDRADIAL_API_PRIVATE_KEY = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

**Option B: Pass as parameters** (see examples below)

### 3. Do a dry run first

Always run with `-WhatIf` before making real changes:

```powershell
.\Sync-ITGlueFlexibleAssets.ps1 -MappingFilePath ".\org-mapping.csv" -WhatIf
```

### 4. Run the sync

```powershell
.\Sync-ITGlueFlexibleAssets.ps1 -MappingFilePath ".\org-mapping.csv"
```

### 5. Filter to specific asset types (optional)

Sync only certain types instead of everything:

```powershell
.\Sync-ITGlueFlexibleAssets.ps1 `
    -MappingFilePath ".\org-mapping.csv" `
    -FlexibleAssetTypeFilter "Network Devices","Backup Systems"
```

### 6. EU or AU IT Glue data centers

```powershell
.\Sync-ITGlueFlexibleAssets.ps1 `
    -MappingFilePath ".\org-mapping.csv" `
    -ITGlueBaseUrl "https://api.eu.itglue.com"
```

## Expected Output

```
[2026-05-12 10:30:00] [Info] ============================================
[2026-05-12 10:30:00] [Info] IT Glue -> CloudRadial Flexible Asset Sync
[2026-05-12 10:30:00] [Info] ============================================
[2026-05-12 10:30:00] [Info] Loading organization mapping from: .\org-mapping.csv
[2026-05-12 10:30:00] [Success] Loaded 3 organization mapping(s)
[2026-05-12 10:30:01] [Info] STEP 1: Fetching Flexible Asset Types from IT Glue...
[2026-05-12 10:30:02] [Success] Found 4 Flexible Asset Type(s) in IT Glue
[2026-05-12 10:30:02] [Info] STEP 2: Creating Flexible Asset Types in CloudRadial...
[2026-05-12 10:30:02] [Info] Processing type: Network Devices (IT Glue ID: 100)
[2026-05-12 10:30:02] [Info]   Found 8 field(s) for type: Network Devices
[2026-05-12 10:30:03] [Success]   Created 'Network Devices' in CloudRadial (ID: 1)
...
[2026-05-12 10:30:10] [Info] STEP 3: Syncing Flexible Assets per organization...
[2026-05-12 10:30:10] [Info] --- Organization: Contoso Ltd (ITG: 12345 -> CR: 1001) ---
[2026-05-12 10:30:11] [Info]   Found 12 'Network Devices' asset(s) to sync
[2026-05-12 10:30:12] [Success]   Created 12 'Network Devices' asset(s) for Contoso Ltd
...
[2026-05-12 10:30:30] [Success] SYNC COMPLETE
[2026-05-12 10:30:30] [Info] Asset Types processed:  4
[2026-05-12 10:30:30] [Info] Organizations mapped:   3
[2026-05-12 10:30:30] [Success] Assets created:       47
[2026-05-12 10:30:30] [Info] Assets failed:          0
```

## What Happens in CloudRadial After Sync

Once the script completes:

1. **New menu items** appear under the **Infrastructure** tab in the client portal
2. Assets display in a **grid format** based on your field schema
3. Clicking an asset shows the **full detail view** with all field data
4. Clients can **search and filter** their assets
5. You can rename the display names from **Partner > Settings > Account & Branding > Sidebar**

### Controlling Visibility

- **Feature Sets:** Enable/disable Flexible Assets per feature set to control which clients see them
- **Security Roles:** A new "Flexible Assets" permission section appears — configure Read, Write, Delete, and Full permissions per role

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| `API returned 401` (IT Glue) | Invalid or expired API key | Regenerate your IT Glue API key |
| `API returned 401` (CloudRadial) | Invalid Public/Private key pair | Check keys at Partner > Settings > Integrations > API |
| `Asset type name already exists` | You've already created this type in CloudRadial | The script skips duplicate types. Delete the existing type in CloudRadial first if you want to re-create it |
| `429 Too Many Requests` (IT Glue) | Rate limit exceeded (3000 requests per 5 min) | Reduce `-PageSize` or wait and re-run |
| Assets don't appear in portal | Feature set doesn't have Flexible Assets enabled | Enable at Partner > Feature Sets > edit the relevant set |
| Fields appear out of order | Field `order` values weren't preserved | Re-run — the script maps the `order` attribute from IT Glue |
| Tag fields show raw IDs | IT Glue tag references don't carry over | Tag fields will display the text values; cross-references to other IT Glue assets won't be linked |

## How It Works (Technical Details)

The script uses two APIs:

**IT Glue API** (`api.itglue.com`)
- `GET /flexible_asset_types?include=flexible_asset_fields` — pulls all type schemas
- `GET /flexible_asset_types/{id}/relationships/flexible_asset_fields` — pulls fields for a type
- `GET /flexible_assets?filter[organization-id]=X&filter[flexible-asset-type-id]=Y` — pulls asset records

**CloudRadial V2 Compatibility API** (`api.us.cloudradial.com`)
- `POST /compatibility/flexible_asset_types` — creates a type with fields
- `POST /compatibility/organizations/{orgId}/relationships/flexible_assets` — bulk inserts assets

The compatibility API uses the same JSON:API-style structure as IT Glue, so trait keys and field kinds transfer directly with minimal transformation.

## Tested Environments

- Windows 10 / Windows 11 with PowerShell 5.1
- PowerShell 7.x (cross-platform)
- IT Glue US, EU, and AU data centers
- CloudRadial UCP V2 API

## Related Resources

- [CloudRadial API Docs](https://developers.cloudradial.com/v2/docs/getting-started)
- [IT Glue API Docs](https://api.itglue.com/developer/)
- [Displaying IT Glue Flexible Assets in CloudRadial UCP](https://support.cloudradial.com/hc/en-us/articles/43441937976340)
- [CloudRadial API Platform Webinar (Video)](https://www.youtube.com/watch?v=6mVZwebgKew)
- [CloudRadial Security Roles](https://support.cloudradial.com/hc/en-us/articles/4454912863124)
