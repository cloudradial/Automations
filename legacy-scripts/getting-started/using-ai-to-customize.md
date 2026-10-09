# Using AI to Generate Custom CloudRadial Scripts

CloudRadial's API follows standard REST and OData patterns that AI models understand well. This means you can use Claude, ChatGPT, or similar tools to generate working scripts customized for your specific situation—without needing to be a PowerShell expert.

## Why This Works

CloudRadial's API design follows predictable patterns:
- **Standard HTTP methods**: GET (read), POST (create), PUT (update), DELETE (remove)
- **Consistent authentication**: Basic Auth headers
- **OData query syntax**: Standard filtering, selection, and pagination
- **Predictable JSON responses**: Data is returned in consistent structures

Large language models are trained on these patterns, so they can generate working code from descriptions. The scripts they generate follow the same structure as the examples in this repository.

## The Process

### 1. Find a Starting Script

Look through this repository for a script similar to what you need. For example:
- Need to **create users**? Start with `user-management/bulk-create-users/`
- Need to **query endpoints**? Start with `monitoring/endpoint-check-in-status/`
- Need to **sync data**? Start with `user-management/psa-contact-sync/`

Don't worry if it's not a perfect match—you'll customize it in the next step.

### 2. Describe What You Want to Change

Write a clear description of what you need. Be specific about:
- What data you're working with
- What the output should look like
- Any special validation or error handling you need
- PowerShell version constraints

### 3. Paste Script + Description into AI

Open Claude, ChatGPT, or your preferred AI tool and provide:

```
I have this CloudRadial API PowerShell script:

[PASTE THE SCRIPT HERE]

I need to modify it to:
[DESCRIBE YOUR CHANGES HERE]

Please update the script to:
1. [Specific requirement 1]
2. [Specific requirement 2]
3. [Specific requirement 3]

The output should [describe expected result].
Assume PowerShell [version].
```

### 4. Test with -WhatIf First

Never run generated code directly in production. Always:

1. Save the script to your desktop or test folder
2. Run it with `-WhatIf` to preview changes: `.\my-script.ps1 -WhatIf`
3. Review the output carefully
4. Test in a non-production environment first
5. Then run in production

## Example 1: User Management

**Scenario**: You have a CSV of contractors who need temporary CloudRadial access for 30 days, after which their accounts should be automatically deactivated.

**Starting Script**: `user-management/bulk-create-users/bulk-create-users.ps1`

**Prompt for AI**:

```
I have this CloudRadial bulk user creation script:

[PASTE THE SCRIPT]

I need to modify it to:
1. Accept a -ExpirationDays parameter (default 30)
2. Set a custom date field on each user record with the expiration date
3. Log the expiration date for each user created so I can set calendar reminders
4. Add validation to ensure ExpirationDays is between 1 and 365

The script should calculate expiration as (today + ExpirationDays) and include it in the API request.
Assume PowerShell 5.1.
```

**What You'll Get**: A modified script that:
- Accepts the new parameter
- Calculates expiration dates
- Passes them to the API
- Logs them for reference
- Has input validation

## Example 2: Endpoint Monitoring

**Scenario**: You want to check endpoint health hourly and send a Teams notification if any endpoints haven't checked in for more than 4 hours.

**Starting Script**: `monitoring/endpoint-check-in-status/get-endpoint-status.ps1`

**Prompt for AI**:

```
I have this CloudRadial endpoint check-in status script:

[PASTE THE SCRIPT]

I need to modify it to:
1. Find all endpoints that haven't checked in for more than 4 hours
2. Generate a Teams webhook notification listing those endpoints
3. Include endpoint name, last check-in time, and company name
4. Send the notification only if there are unhealthy endpoints (not on every run)
5. Include a link back to the CloudRadial portal for further investigation

The Teams message should be formatted as a card with fields for each endpoint.
Assume PowerShell 5.1 and that I'll schedule this as a Windows Task.
```

**What You'll Get**: A script that:
- Queries endpoint health
- Filters for stale check-ins
- Formats a Teams card
- Sends notifications only when needed
- Is ready for Task Scheduler

## Example 3: Token Management

**Scenario**: You want to create endpoint name tokens automatically whenever a new endpoint is added to CloudRadial, so the portal always has current endpoint names for notifications and reports.

**Starting Script**: `tokens/endpoint-names-all-companies/create-endpoint-tokens.ps1`

**Prompt for AI**:

```
I have this CloudRadial token creation script:

[PASTE THE SCRIPT]

I need to modify it to:
1. Only create tokens for endpoints added in the last 24 hours
2. Check if a token already exists before creating a duplicate
3. Log the token values to a CSV file for audit purposes
4. Include error handling that continues on individual failures but reports them at the end
5. Return a summary (created: X, skipped: Y, failed: Z)

Assume PowerShell 5.1 and that this will run as a scheduled task daily.
```

**What You'll Get**: A production-ready script that:
- Prevents duplicates
- Handles failures gracefully
- Maintains an audit log
- Provides clear reporting
- Integrates with Task Scheduler

## Tips for Better Results

### Be Specific About Requirements

Bad: "Make it filter endpoints"
Good: "Filter endpoints where LastCheckIn is more than 4 hours ago and Status equals 'Unhealthy'"

### Mention Error Handling

```
Include try-catch blocks with:
- Specific error messages for API failures
- Retry logic for timeout errors
- Graceful exit on authentication failures
- A summary report of successes and failures
```

### Describe the Expected Output

```
The script should output:
- Console messages showing [what]
- A CSV file at [path] with columns [name1, name2, ...]
- An email notification sent to [recipient] with [format]
```

### Specify PowerShell Version

CloudRadial scripts support PowerShell 5.1 (built into Windows) and PowerShell 7+ (Core). Be explicit:

```
Assume PowerShell 5.1 (no PowerShell 7 features).
```

### Ask for Comments

```
Please add comments explaining:
- What each section does
- Why we use -WhatIf in certain places
- What the API response means
```

### Include -WhatIf Support

```
Add -WhatIf parameter support so the script shows what it would do without actually making changes.
```

## Security Reminders

### Never Paste API Keys

When sharing scripts or asking for help, use placeholder values:

Bad:
```powershell
$publicKey = "abc123def456ghi789"
$privateKey = "xyz987uvw654rts321"
```

Good:
```powershell
$publicKey = "YOUR_PUBLIC_KEY_HERE"
$privateKey = "YOUR_PRIVATE_KEY_HERE"
```

### Use Environment Variables

Always modify generated scripts to use environment variables:

```powershell
$publicKey = $env:CLOUDRADIAL_API_PUBLIC_KEY
$privateKey = $env:CLOUDRADIAL_API_PRIVATE_KEY

if (-not $publicKey -or -not $privateKey) {
    Write-Error "Set CLOUDRADIAL_API_PUBLIC_KEY and CLOUDRADIAL_API_PRIVATE_KEY environment variables"
    exit 1
}
```

### Don't Share Generated Scripts with Credentials

Before sharing a generated script with a colleague, clean out any credentials or sensitive data.

## Common Customization Requests

| Need | Start With | Key Ask |
|------|-----------|---------|
| **Scheduled automation** | Any script | "Add Windows Task Scheduler integration and logging" |
| **Integration with PSA** | `user-management/psa-contact-sync/` | "Map [PSA field] to [CloudRadial field]" |
| **Notifications** | `integrations/teams-notifications/` | "Send to Slack/Teams/Email when [condition]" |
| **Data validation** | Any script with -WhatIf | "Validate [field] against [rules]" |
| **Error recovery** | Any script | "Retry failed requests with exponential backoff" |
| **Filtering & selection** | Any GET request script | "Filter results by [criteria] and select only [fields]" |
| **Bulk operations** | `user-management/bulk-*` | "Instead of CSV, read from [source]" |

## Testing Checklist Before Production

- [ ] Run with `-WhatIf` and review output
- [ ] Test with sample data in a non-production company
- [ ] Check error handling: What happens if the API is down?
- [ ] Verify credentials are not hardcoded
- [ ] Check that logging works (if applicable)
- [ ] Validate that the script exits cleanly on errors
- [ ] Test with Edge cases (empty results, special characters, large datasets)
- [ ] Run in production on a small test set first

## Limitations & When Not to Use AI

AI-generated scripts work great for:
- Filtering and querying data
- Bulk operations (create, update, delete)
- API integrations
- Notifications
- Report generation

AI-generated scripts need review for:
- Complex business logic
- Data transformations
- Large-scale migrations
- Security-sensitive operations (always have a second person review)

When in doubt, ask for code review in this repository before running in production.

## Questions?

- Check the [authentication guide](authentication.md) for API basics
- Look at existing scripts in this repo for real-world examples
- Open an issue with your use case—the community can help
- Contact the CloudRadial Customer Success team

Happy automating!
