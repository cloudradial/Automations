# Create Device Name Tokens â Dynamic Endpoint and Server Lists for Portal Forms

## Why This Matters

CloudRadial tracks endpoints and servers in the portal through the Data Agent and the Datto RMM integration. That device data is there â but it isn't available as a dropdown or multi-select list in ticket and service request forms. So when an end user needs to submit a request like "I'd like software installed on this machine" or "I'd like to order a license for this device," there's no way for them to pick from their actual devices. They're left typing free-text â misspelled hostnames, vague descriptions like "my laptop," or just leaving it blank.

This script bridges that gap. It pulls a company's active device names â either endpoints or servers, controlled by the `-DeviceType` flag â and stores them as a comma-separated value in a company-level token. CloudRadial forms treat comma-separated token values as individual answer options, so once the token exists, any multi-select or multi-choice question in any form â whether it's part of a Question Template or a standalone ticket form â can use it as an answer source. End users see a clean list of their own devices and pick from it.

The script creates @EndpointNames when run for endpoints (the default) and @ServerNames when run for servers. Run both to give your forms access to the full device inventory. Because tokens are company-level, each company's forms automatically show only their own devices. Run the script on a schedule and the lists stay current â new machines appear, decommissioned ones disappear, no manual maintenance required.

> **Coming soon:** A separate script for Flexible Asset tokens is planned as a future addition to this folder.

## Who This Is For

- **Partners building ticket and request forms** â "Which device is this about?" becomes a real dropdown instead of a free-text field. Works in any form type: tickets, service requests, change requests, onboarding forms.
- **Partners who already have device data flowing into CloudRadial** â Whether it comes from the Data Agent or the Datto RMM integration, this script takes data you already have and makes it usable in forms.
- **Partners managing multiple clients** â Run it with `-AllCompanies` and every client company gets updated device lists in one pass. No per-company maintenance.
- **Partners reducing ticket triage time** â When the exact device name is captured at submission, dispatch and triage workflows get structured data instead of guesswork.

## What You'll Need

- CloudRadial API credentials (PublicKey and PrivateKey)
- PowerShell 5.1 or later
- Knowledge of which company to target, or permission to run across all companies

## How Tokens Work

Tokens are dynamic @name placeholders that resolve to specific values per company. When a token's value is comma-separated, CloudRadial's multi-select and multi-choice question types treat each comma-separated item as an individual answer option.

This script:

1. Queries a company's active device inventory from CloudRadial's endpoint entity (both workstations and servers live here â the `-DeviceType` flag filters by the `isServer` property)
2. Extracts the device names (preferring machineName, falling back to name) from each device
3. Deduplicates and sorts the names, then stores them as a single comma-separated value in a company-level token
4. Any form question that references the token (e.g., @EndpointNames or @ServerNames) now shows those devices as selectable options

Because the token is set at the company level, each company's forms display only their own devices. Run the script again any time â it overwrites the token with the current device list, so the form options stay in sync with the actual inventory.

## Step 1: Set Your Credentials

Store your API credentials as environment variables so the script can access them:

**Windows (PowerShell):**
```powershell
$env:CLOUDRADIAL_API_USERNAME = "your_public_key"
$env:CLOUDRADIAL_API_PASSWORD = "your_private_key"
```

**Windows (Command Prompt):**
```cmd
set CLOUDRADIAL_API_USERNAME=your_public_key
set CLOUDRADIAL_API_PASSWORD=your_private_key
```

If the environment variables are not set, the script will prompt you to enter them at runtime.

## Step 2: Create Token for One Company

By default, the script queries endpoints and creates the @EndpointNames token. Use `-DeviceType Server` to query servers and create @ServerNames instead.

**Endpoints (default):**
```powershell
.\New-EndpointNamesToken.ps1 -CompanyId 42
```

**Servers:**
```powershell
.\New-EndpointNamesToken.ps1 -DeviceType Server -CompanyId 42
```

**By Company Name (works with either device type):**
```powershell
.\New-EndpointNamesToken.ps1 -CompanyName "Contoso"
.\New-EndpointNamesToken.ps1 -DeviceType Server -CompanyName "Contoso"
```

If your company name search returns multiple matches, the script will show you a menu to select the correct company.

## Step 3: Create Tokens for All Companies

To create tokens for every company in your workspace:

**Endpoints:**
```powershell
.\New-EndpointNamesToken.ps1 -AllCompanies
```

**Servers:**
```powershell
.\New-EndpointNamesToken.ps1 -DeviceType Server -AllCompanies
```

**Both (run the script twice):**
```powershell
.\New-EndpointNamesToken.ps1 -AllCompanies
.\New-EndpointNamesToken.ps1 -DeviceType Server -AllCompanies
```

By default, the script skips companies that have no active devices of the selected type. If you want to create empty tokens for these companies (useful for consistency), add the -CreateEmptyTokens switch:

```powershell
.\New-EndpointNamesToken.ps1 -AllCompanies -CreateEmptyTokens
```

## Step 4: Verify in the Portal

After running the script, verify that the tokens were created:

1. Log in to CloudRadial as a Partner Admin
2. Navigate to Settings > Tokens (or similar, depending on your UI version)
3. Search for "EndpointNames" or "ServerNames" (depending on which you created)
4. You should see one token per company, with device names listed as comma-separated values

## Using the Token in Forms

Once a token exists for a company, any multi-select or multi-choice question can use it as its answer source. This works in Question Templates, standalone ticket forms, and service request forms â the token doesn't need to be tied to a Question Template to work.

**Common form scenarios:**

- "Which computer needs attention?" â Add a multi-choice question with @EndpointNames as the answer source. The end user picks their workstation from the list.
- "Select the machines for software deployment" â Use a multi-select question so the user can choose multiple endpoints in one request.
- "Which server should receive the update?" â Use @ServerNames as the answer source for server-specific requests.
- "Which device should receive the new license?" â Use @EndpointNames or @ServerNames depending on whether the license applies to workstations or servers.

You can also reference these tokens in portal content (knowledge base articles, dashboards) to display a company's device lists outside of forms.

## Scheduling This Script

To keep your tokens fresh as endpoints change, schedule the script to run regularly:

**Windows Task Scheduler:**
1. Open Task Scheduler
2. Create a new task
3. Set the trigger (daily, weekly, or as needed)
4. Set the action to run both device types:
   ```
   powershell.exe -File C:\path\to\New-EndpointNamesToken.ps1 -AllCompanies
   powershell.exe -File C:\path\to\New-EndpointNamesToken.ps1 -DeviceType Server -AllCompanies
   ```
5. Run with credentials that have the CLOUDRADIAL_API_USERNAME and CLOUDRADIAL_API_PASSWORD environment variables set

**RMM/Automation Platform:**
If you use ConnectWise Automate, Datto RMM, or similar, create a scheduled script task that runs the PowerShell script on your desired interval (e.g., daily or weekly). Schedule both device types if you want both tokens kept current.

## Customization Tips

### Change the Token Name
If you want to use a different token name (e.g., @Computers or @MyEndpoints), pass the -TokenName parameter:

```powershell
.\New-EndpointNamesToken.ps1 -AllCompanies -TokenName "Computers"
```

### Filter Devices Differently
The script includes all active devices by default (isBlocked eq false). If you need different filtering logic â for example, excluding certain device types, filtering by location, or applying custom business rules â edit the `Get-ActiveDevices` function to adjust the OData filter.

### Adapt with AI
Use tools like GitHub Copilot or ChatGPT to help customize the script for your specific workflow, such as:
- Excluding devices by name pattern (e.g., skip test machines)
- Creating different tokens for device subsets (e.g., @ProductionServers, @TestEndpoints)
- Adding logging or notifications when the script runs
- Integrating with your RMM tool's API

## Troubleshooting

**"No companies found matching..."**
- Check the company name spelling and try a partial search
- Verify you have access to view that company in CloudRadial

**"API returned 429"**
- Your API calls are being rate-limited. The script retries automatically, but if it continues, wait a few minutes and try again.

**"API returned 401"**
- Your PublicKey or PrivateKey is incorrect. Verify credentials in Settings > API Keys.

**Token created but device names are blank or incorrect**
- Some devices may have missing or empty machineName and name fields. Check the Endpoints or Servers page in CloudRadial to see what data is available.
- Edit the device details to populate the machine name field.

**Script hangs or takes a long time**
- For workspaces with thousands of devices, pagination takes time. This is normal. Monitor the output and be patient.
