# Getting Started: Your First CloudRadial API Call

This guide walks you through making your first authenticated call to the CloudRadial API. By the end, you'll understand how authentication works and have a working script you can build on.

**Time Required**: 15 minutes
**What You'll Need**: PowerShell 5.1+, CloudRadial API keys, access to your CloudRadial portal

## Step 1: Get Your API Keys

1. Log in to your CloudRadial portal
2. Navigate to **Settings > API**
3. You'll see two keys displayed:
   - **Public Key** (username for authentication)
   - **Private Key** (password for authentication)
4. Copy both—you'll need them for every API call

**Important**: Keep your Private Key secure. Treat it like a password. Never commit it to source control or share it in Slack/email.

## Step 2: Understand Basic Authentication

CloudRadial uses **Basic Authentication** over HTTPS. This is a standard HTTP authentication method that works like this:

1. Combine your Public Key and Private Key with a colon: `PublicKey:PrivateKey`
2. Encode that string in Base64
3. Add it to the HTTP `Authorization` header as `Basic [encoded-string]`

PowerShell makes this easy with built-in functions:

```powershell
$publicKey = "your_public_key_here"
$privateKey = "your_private_key_here"

# Create the credentials string
$credString = "$($publicKey):$($privateKey)"

# Convert to Base64
$encodedCreds = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($credString))

# Build the Authorization header
$authHeader = @{
    Authorization = "Basic $encodedCreds"
}
```

That's it. The `$authHeader` is what you'll pass to every API request.

## Step 3: Make Your First GET Request

Let's query the `/v2/odata/company` endpoint to list all companies in your CloudRadial portal:

```powershell
$publicKey = "your_public_key_here"
$privateKey = "your_private_key_here"

# Build auth header
$credString = "$($publicKey):$($privateKey)"
$encodedCreds = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($credString))
$authHeader = @{
    Authorization = "Basic $encodedCreds"
}

# Make the API call
$uri = "https://api.us.cloudradial.com/v2/odata/company"
$response = Invoke-RestMethod -Uri $uri -Headers $authHeader -Method Get

# Display the results
$response | ConvertTo-Json
```

**Expected Response Structure**:

```json
{
  "@odata.context": "https://api.us.cloudradial.com/v2/$metadata#company",
  "value": [
    {
      "id": "12345678-1234-1234-1234-123456789abc",
      "name": "Acme Corporation",
      "createdDate": "2025-01-15T14:30:00Z",
      "status": "Active"
    },
    {
      "id": "87654321-4321-4321-4321-abcdefg12345",
      "name": "Beta Industries",
      "createdDate": "2025-02-20T09:15:00Z",
      "status": "Active"
    }
  ]
}
```

Each item in the `value` array is a company. You can use the `id` field to query for more details about specific companies.

## Step 4: Try an OData Query

The CloudRadial API supports OData query parameters to filter, select, and limit results. This is powerful when you have many companies and want specific data.

### Filter by Company Name

```powershell
$uri = "https://api.us.cloudradial.com/v2/odata/company?`$filter=contains(name, 'Acme')"
$response = Invoke-RestMethod -Uri $uri -Headers $authHeader -Method Get
$response.value
```

This returns only companies with "Acme" in the name.

### Select Specific Fields

```powershell
$uri = "https://api.us.cloudradial.com/v2/odata/company?`$select=id,name,status"
$response = Invoke-RestMethod -Uri $uri -Headers $authHeader -Method Get
$response.value
```

This returns only the `id`, `name`, and `status` fields, reducing payload size.

### Limit Results

```powershell
$uri = "https://api.us.cloudradial.com/v2/odata/company?`$top=10"
$response = Invoke-RestMethod -Uri $uri -Headers $authHeader -Method Get
$response.value
```

This returns only the first 10 companies.

### Combine Filters

```powershell
$uri = "https://api.us.cloudradial.com/v2/odata/company?`$filter=contains(name, 'Acme')&`$select=id,name&`$top=5"
$response = Invoke-RestMethod -Uri $uri -Headers $authHeader -Method Get
$response.value
```

**Note**: In PowerShell strings, OData parameters starting with `$` need to be escaped with a backtick: `$filter` becomes `` `$filter ``.

## Step 5: Store Credentials Safely

In production, never hardcode credentials in scripts. Use environment variables:

### Set Environment Variables (One Time)

On Windows:
```powershell
[Environment]::SetEnvironmentVariable("CLOUDRADIAL_API_PUBLIC_KEY", "your_public_key", "User")
[Environment]::SetEnvironmentVariable("CLOUDRADIAL_API_PRIVATE_KEY", "your_private_key", "User")
```

Restart PowerShell to load the new variables.

### Use Environment Variables in Your Script

```powershell
$publicKey = $env:CLOUDRADIAL_API_PUBLIC_KEY
$privateKey = $env:CLOUDRADIAL_API_PRIVATE_KEY

if (-not $publicKey -or -not $privateKey) {
    Write-Error "API keys not found. Set CLOUDRADIAL_API_PUBLIC_KEY and CLOUDRADIAL_API_PRIVATE_KEY environment variables."
    exit 1
}

# Rest of script...
```

### Alternative: Prompt for Credentials

For scripts you run occasionally, prompt the user:

```powershell
$publicKey = Read-Host "Enter CloudRadial API Public Key"
$privateKey = Read-Host "Enter CloudRadial API Private Key" -AsSecureString

# Convert secure string back to plain text for API use
$privateKeyPlain = [System.Net.NetworkCredential]::new('', $privateKey).Password

# Rest of script...
```

## API Base URL Reference

- **US Region**: https://api.us.cloudradial.com
- **EU Region**: https://api.eu.cloudradial.com
- **API Version**: All endpoints use `/v2/`

All examples in this guide assume US region. If your portal is in the EU, replace `api.us.cloudradial.com` with `api.eu.cloudradial.com`.

## Common OData Operators

| Operator | Example | Description |
|----------|---------|-------------|
| `eq` | `status eq 'Active'` | Equals |
| `ne` | `status ne 'Inactive'` | Not equals |
| `gt` | `createdDate gt 2025-01-01` | Greater than |
| `lt` | `createdDate lt 2025-12-31` | Less than |
| `contains` | `contains(name, 'Acme')` | String contains |
| `startswith` | `startswith(name, 'A')` | String starts with |
| `and` | `status eq 'Active' and name eq 'Acme'` | Logical AND |
| `or` | `status eq 'Active' or status eq 'Trial'` | Logical OR |

## What's Next?

Now that you understand authentication and basic GET requests, explore:

- **Quick Win Scripts**: Check out the scripts in this repo to see real-world examples
- **User Management**: Learn how to create, update, and list users via the API
- **Using AI to Customize**: Read [using-ai-to-customize.md](using-ai-to-customize.md) to generate custom scripts for your specific needs
- **CloudRadial API Documentation**: For detailed endpoint reference, check your portal's API documentation

## Troubleshooting

**Error: "401 Unauthorized"**
- Check that your API keys are correct (copy from Settings > API again)
- Verify you're using the right region (us or eu)
- Make sure the Base64 encoding is correct (the $authHeader should look like `Basic Zm9v...`)

**Error: "The underlying connection was closed"**
- Ensure you're using HTTPS (not HTTP)
- Check your internet connection

**Error: "404 Not Found"**
- Verify the endpoint URL is correct
- Check that you're on the right API region

**Getting an empty value array**
- This might be correct if you have no companies set up yet
- Double-check your filter syntax if using OData filters

**Questions?** Open an issue in this repository or contact CloudRadial support.
