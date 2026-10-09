# Bulk User Upload — Import Users from CSV

## Why This Matters

Before the v2 API, there was no way to bulk-add users to a CloudRadial company outside of the built-in PSA and Microsoft 365 sync integrations. If your Partner doesn't use a supported PSA, uses Google Workspace or a third-party email provider instead of M365, or has security policies that prevent enabling sync integrations, users had to be added one at a time through the portal.

This script changes that. It lets any Partner import dozens or hundreds of users from a simple CSV file in seconds — no PSA integration required, no M365 tenant connection needed, no manual data entry. It's the first bulk user management option that works regardless of the Partner's stack.

## Who This Is For

- **Partners without a supported PSA** — No ConnectWise, Datto, or HaloPSA? You can still bulk-provision users.
- **Google Workspace / third-party email Partners** — Users who aren't in M365 can now be loaded into CloudRadial in bulk.
- **Security-conscious Partners** — Some organizations don't want to grant sync permissions to external platforms. A CSV import keeps credential exposure minimal — just your API keys, nothing else.
- **Onboarding new clients** — When you land a new client with 50–200 users, this turns a multi-hour manual process into a 30-second script run.

## What You'll Need

- CloudRadial API credentials (PublicKey and PrivateKey)
- PowerShell 5.1 or later
- A CSV file with user data (see template below)
- Your target CloudRadial Company ID

## How to Find Your Company ID

**Option 1: Look in the Portal**
1. Log in to CloudRadial
2. Navigate to Companies
3. Click the company you want to import users into
4. Look at the URL in your browser—it contains the Company ID. For example, `https://app.cloudradial.com/companies/42` means the Company ID is `42`.

**Option 2: Query the API**
Open PowerShell and run:

```powershell
$creds = Read-Host "PublicKey" -AsSecureString | ConvertFrom-SecureString -AsPlainText
$key = Read-Host "PrivateKey" -AsSecureString | ConvertFrom-SecureString -AsPlainText
$encoded = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$creds`:$key"))
$header = @{ Authorization = "Basic $encoded" }

Invoke-RestMethod -Uri "https://api.us.cloudradial.com/v2/odata/company?`$filter=name eq 'Contoso'" `
  -Headers $header | Select-Object -ExpandProperty value | Select-Object id, name
```

Replace "Contoso" with your company name.

## Step 1: Prepare Your CSV

Your CSV file must contain these four required columns:
- **email** — User email address (checked for duplicates; case-insensitive)
- **firstName** — User's first name
- **lastName** — User's last name
- **userName** — CloudRadial login username

Optional columns (include them only if needed):
- **department** — Department name
- **title** — Job title
- **phoneNumber** — Work phone
- **mobilePhone** — Mobile phone
- **country** — Country code
- **streetAddress** — Street address
- **city** — City
- **state** — State/province
- **postalCode** — Postal code
- **psaKey** — ConnectWise PSA user ID (integer)
- **psaSiteKey** — ConnectWise PSA site ID (integer)
- **psaChildAccountKey** — ConnectWise PSA child account ID (integer)

Use the provided **users-template.csv** as a starting point. Export your user list from Active Directory, a spreadsheet, or another source and map it to these columns.

## Step 2: Set Your Credentials

Store your CloudRadial API credentials as environment variables so the script never hardcodes them.

**On Windows (PowerShell):**
```powershell
$env:CLOUDRADIAL_API_USERNAME = "your-public-key"
$env:CLOUDRADIAL_API_PASSWORD = "your-private-key"
```

To make these permanent for your session, add them to your PowerShell profile, or set them through System Settings > Environment Variables.

If you don't set these env vars, the script will prompt you interactively.

## Step 3: Do a Dry Run

Before importing for real, test the script in dry-run mode with the -WhatIf flag:

```powershell
.\Import-CloudRadialUsers.ps1 -CsvPath ".\users.csv" -CompanyId 42 -WhatIf
```

This shows you exactly what would happen—which users would be created, which would be skipped (because they already exist), and which would fail—without actually making any changes.

Look for:
- **Green "Created:"** messages — users that will be added
- **Yellow "Skipped:"** messages — users already in the system
- **Red "Failed:"** messages — users with validation errors (check your CSV)

## Step 4: Run the Import

Once the dry run looks good, run the actual import:

```powershell
.\Import-CloudRadialUsers.ps1 -CsvPath ".\users.csv" -CompanyId 42
```

The script will:
1. Validate your CSV file
2. Check that the Company ID exists
3. Fetch a list of existing users (to skip duplicates)
4. Import each user from the CSV
5. Show a summary of how many were created, skipped, or failed

Rate limiting is applied automatically (default: 12 requests per minute) to avoid overwhelming the API.

## Step 5: Verify

**In the Portal:**
1. Log in to CloudRadial
2. Navigate to the company
3. Go to Users
4. Verify your new users appear and have the correct details

**Via the API:**
Query the newly created users:

```powershell
$header = @{ Authorization = "Basic $encoded" }  # From Step 2 Option 2

Invoke-RestMethod -Uri "https://api.us.cloudradial.com/v2/odata/user?`$filter=companyId eq 42&`$top=10" `
  -Headers $header | Select-Object -ExpandProperty value | Select-Object email, firstName, lastName
```

## Resuming After Errors

If the script stops due to network issues or API errors, you don't need to start from scratch. The script creates a checkpoint file that tracks which users were successfully imported.

To resume:

```powershell
.\Import-CloudRadialUsers.ps1 -CsvPath ".\users.csv" -CompanyId 42 -Resume
```

The -Resume flag skips users that were already processed in previous runs, picking up where you left off.

The checkpoint file is stored next to your CSV with a name like `users_checkpoint_42.txt`.

## Customization Tips

**Adjust Rate Limiting**
If the default rate limit is too aggressive or too conservative for your environment, change it:

```powershell
.\Import-CloudRadialUsers.ps1 -CsvPath ".\users.csv" -CompanyId 42 -RequestsPerMinute 30
```

Higher numbers = faster imports (but may hit API limits). Default is 12 per minute.

**Change Retry Behavior**
For unstable networks, increase retries:

```powershell
.\Import-CloudRadialUsers.ps1 -CsvPath ".\users.csv" -CompanyId 42 -MaxRetries 5
```

**Modify the Script**
This script is yours to customize. If your company has extra user fields, custom logic, or integrations, feel free to edit it. Some common modifications:
- Add more optional fields to the CSV
- Change the rate limit globally
- Integrate with your company's user provisioning system
- Add pre-import validation (check usernames are unique, etc.)

If you're not comfortable editing PowerShell, ask your team or use an AI assistant to help. The script follows standard PowerShell patterns and includes detailed comments.

## Troubleshooting

**"CSV file is empty"**
Check that your CSV has data rows below the headers.

**"Required column missing"**
Make sure your CSV has email, firstName, lastName, and userName columns (exact spelling, case-sensitive headers).

**"Company ID [X] not found"**
Double-check your Company ID. Log in to the portal and verify it exists.

**"ERROR (401): Unauthorized"**
Your API credentials are wrong. Check that CLOUDRADIAL_API_USERNAME and CLOUDRADIAL_API_PASSWORD are set correctly. The script will prompt you if they're not set.

**"ERROR (429): Too Many Requests"**
The API rate limit was exceeded. The script automatically backs off and retries, but if this keeps happening, decrease -RequestsPerMinute.

**Some users imported successfully, then the script stopped**
Run with -Resume to pick up where it left off.

**"ERROR: Could not fetch all existing users"**
The script couldn't retrieve the list of users already in the system. This is usually a temporary network issue. Try again—the script will fetch the list again on the next run.

## Next Steps

After importing users, consider:
- Assigning users to teams or roles via the portal or API
- Configuring user preferences (email digests, 365 integration, etc.)
- Setting up ticketing board overrides for specific users
- Running a user provisioning sync if you have PSA integration enabled
