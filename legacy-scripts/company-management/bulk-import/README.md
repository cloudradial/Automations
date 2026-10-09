# Bulk Company Import — Import Companies from CSV

## Why This Matters

When a Partner manages hundreds or thousands of client companies, adding them one at a time through the CloudRadial portal isn't practical. If the Partner doesn't use a supported PSA integration that auto-syncs companies, there was no bulk option — until now.

This script lets any Partner import dozens, hundreds, or thousands of companies from a simple CSV file. No PSA integration required, no manual data entry. It's the same pattern as the [Bulk User Upload](../../user-management/bulk-upload/) script, adapted for the company endpoint.

## Who This Is For

- **Partners with large client lists** — Importing 50, 500, or 5,000+ companies in one run instead of clicking through the portal.
- **Partners without a supported PSA** — No ConnectWise, Datto, or HaloPSA? You can still bulk-provision companies.
- **New Partner onboarding** — When a Partner signs up and needs their entire client roster loaded into CloudRadial on day one.
- **Migration scenarios** — Moving from another platform and need to seed CloudRadial with your existing company list.

## What You'll Need

- CloudRadial API credentials (PublicKey and PrivateKey)
- PowerShell 5.1 or later
- A CSV file with company data (see template below)

## Step 1: Prepare Your CSV

Your CSV file must contain one required column:

- **name** — Company name (checked for duplicates; case-insensitive)

Optional columns (include them only if needed):

- **psaKey** — PSA key for the company (integer, e.g. ConnectWise company rec ID)
- **psaIdentifier** — PSA identifier string (e.g. the company slug in your PSA)
- **territory** — Territory assigned to the company
- **accountManager** — Account manager name for the company

Use the provided `companies-template.csv` as a starting point. Export your company list from your PSA, a spreadsheet, or another source and map it to these columns.

> **Tip:** At minimum you only need the `name` column. If you're just seeding company shells to configure later, a single-column CSV works fine.

## Step 2: Set Your Credentials

Store your CloudRadial API credentials as environment variables so the script never hardcodes them.

On Windows (PowerShell):

```powershell
$env:CLOUDRADIAL_API_USERNAME = "your-public-key"
$env:CLOUDRADIAL_API_PASSWORD = "your-private-key"
```

To make these permanent, add them to your PowerShell profile or set them through **System Settings > Environment Variables**.

If you don't set these env vars, the script will prompt you interactively.

## Step 3: Do a Dry Run

Before importing for real, test the script in dry-run mode with the `-WhatIf` flag:

```powershell
.\Import-CloudRadialCompanies.ps1 -CsvPath ".\companies.csv" -WhatIf
```

This shows you exactly what would happen — which companies would be created, which would be skipped (because they already exist), and which would fail — without actually making any changes.

Look for:

- **Green "Created:" messages** — companies that will be added
- **Yellow "Skipped:" messages** — companies already in the system or duplicates in CSV
- **Red "Failed:" messages** — companies with errors (check your CSV)

## Step 4: Run the Import

Once the dry run looks good, run the actual import:

```powershell
.\Import-CloudRadialCompanies.ps1 -CsvPath ".\companies.csv"
```

The script will:

1. Validate your CSV file
2. Verify API credentials
3. Fetch a list of existing companies (to skip duplicates)
4. Import each company from the CSV
5. Show a summary of how many were created, skipped, or failed

Rate limiting is applied automatically (default: 12 requests per minute) to avoid overwhelming the API.

### With a Partner ID

If you need to assign companies to a specific partner tenant:

```powershell
.\Import-CloudRadialCompanies.ps1 -CsvPath ".\companies.csv" -PartnerId 7
```

## Step 5: Verify

**In the Portal:**

1. Log in to CloudRadial
2. Navigate to **Companies**
3. Verify your new companies appear

**Via the API:**

```powershell
$header = @{ Authorization = "Basic $encoded" }

Invoke-RestMethod -Uri "https://api.us.cloudradial.com/v2/odata/company?`$top=10&`$orderby=id desc" `
    -Headers $header | Select-Object -ExpandProperty value | Select-Object id, name
```

## Resuming After Errors

If the script stops due to network issues or API errors, you don't need to start from scratch. The script creates a checkpoint file that tracks which companies were successfully imported.

To resume:

```powershell
.\Import-CloudRadialCompanies.ps1 -CsvPath ".\companies.csv" -Resume
```

The `-Resume` flag skips companies that were already processed in previous runs, picking up where you left off.

The checkpoint file is stored next to your CSV with a name like `companies_checkpoint_companies.txt`.

## Customization Tips

**Adjust Rate Limiting**

If the default rate limit is too aggressive or too conservative for your environment, change it:

```powershell
.\Import-CloudRadialCompanies.ps1 -CsvPath ".\companies.csv" -RequestsPerMinute 30
```

Higher numbers = faster imports (but may hit API limits). Default is 12 per minute.

**Change Retry Behavior**

For unstable networks, increase retries:

```powershell
.\Import-CloudRadialCompanies.ps1 -CsvPath ".\companies.csv" -MaxRetries 5
```

**Modify the Script**

This script is yours to customize. Some common modifications:

- Add post-import steps (e.g., immediately create a default user for each company)
- Chain with the [Bulk User Upload](../../user-management/bulk-upload/) script to import companies first, then users
- Integrate with your PSA export to auto-map `psaKey` and `psaIdentifier`

## Troubleshooting

**"CSV file is empty"**
Check that your CSV has data rows below the headers.

**"Required column missing"**
Make sure your CSV has a `name` column (exact spelling, case-sensitive header).

**"API authentication failed"**
Your API credentials are wrong. Check that `CLOUDRADIAL_API_USERNAME` and `CLOUDRADIAL_API_PASSWORD` are set correctly.

**"ERROR (429): Too Many Requests"**
The API rate limit was exceeded. The script automatically backs off and retries, but if this keeps happening, decrease `-RequestsPerMinute`.

**Some companies imported successfully, then the script stopped**
Run with `-Resume` to pick up where it left off.

**"WARNING: Could not fetch all existing companies"**
The script couldn't retrieve the full list of existing companies. This is usually a temporary network issue. Try again — the script will fetch the list again on the next run. Note: if this happens, some duplicates may slip through (they can be cleaned up in the portal).

## Next Steps

After importing companies, consider:

- **Importing users** into each company using the [Bulk User Upload](../../user-management/bulk-upload/) script
- Configuring PSA or M365 sync for companies that need it
- Setting up service installations and portal content per company
- Assigning companies to groups for reporting
