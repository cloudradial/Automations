# Contributing to CloudRadial Scripts & Automations

We welcome contributions from MSP Partners. Whether it's a new script that solves a real business problem, improvements to existing code, or bug reports—your input helps the entire community.

## How to Contribute

### Submitting a Script

1. **Fork the repository** on GitHub
2. **Create a feature branch** for your work: `git checkout -b feature/my-script-name`
3. **Add your automation** as a new top-level folder, with a README in the same format as the existing ones (the standalone scripts in `legacy-scripts/` are no longer updated)
4. **Include documentation** (see Script Standards section)
5. **Test thoroughly** before submitting—especially with `-WhatIf` for scripts that make changes
6. **Create a pull request** with a clear description of what the script does and the business problem it solves

### Reporting Issues

Use GitHub Issues to report:
- **Script Requests**: Describe a business problem you need to solve (e.g., "I need to bulk create users from a CSV and assign them to specific departments")
- **Bug Reports**: Which script, what happened, what you expected to happen, and any error messages
- **Documentation Issues**: Unclear instructions, missing examples, incorrect API endpoints

## Script Standards

All scripts in this repository should follow these guidelines:

### Comment Block & Metadata

Every script must start with a synopsis block:

```powershell
<#
.SYNOPSIS
Brief description of what the script does

.DESCRIPTION
Longer explanation of the business problem it solves and when to use it

.PARAMETER ApiPublicKey
Description of the parameter

.PARAMETER ApiPrivateKey
Description of the parameter

.EXAMPLE
PS> .\my-script.ps1 -ApiPublicKey "abc123" -ApiPrivateKey "xyz789"

.NOTES
Author: Your Name
Version: 1.0
Date: 2026-04-29
#>
```

### Parameter Validation

Use `param()` with type constraints and validation:

```powershell
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApiPublicKey,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApiPrivateKey,

    [Parameter(Mandatory = $false)]
    [int]$Timeout = 30
)
```

### Credentials: Never Hardcode

Always use environment variables or secure prompts—never hardcode credentials:

```powershell
# Good: Use environment variables
$publicKey = $env:CLOUDRADIAL_API_PUBLIC_KEY
$privateKey = $env:CLOUDRADIAL_API_PRIVATE_KEY

# Good: Prompt the user
$publicKey = Read-Host "Enter your CloudRadial API Public Key" -AsSecureString
$privateKey = Read-Host "Enter your CloudRadial API Private Key" -AsSecureString

# Never do this:
# $publicKey = "hardcoded_key_12345"  # BAD!
```

### Support -WhatIf

Include `-WhatIf` support for any script that modifies data:

```powershell
param(
    # ... other parameters ...
    [switch]$WhatIf
)

if ($WhatIf) {
    Write-Host "What if: Would create user $($user.displayName)" -ForegroundColor Yellow
    return
}

# Perform actual operation
```

### Error Handling

Include try-catch blocks and meaningful error messages:

```powershell
try {
    $response = Invoke-RestMethod -Uri $uri -Headers $authHeader -Method Post -Body $body
}
catch {
    Write-Error "Failed to create user: $($_.Exception.Message)"
    exit 1
}
```

### Documentation

Each script folder must include a **README.md** that explains:

- **Business Problem**: What real-world situation does this script solve?
- **Prerequisites**: Any setup required before running
- **Usage**: Step-by-step instructions with examples
- **Expected Output**: What should the user expect to see?
- **Troubleshooting**: Common issues and solutions
- **Tested Environments**: PowerShell versions, OS versions tested on

Example README structure:

```markdown
# Bulk User Creation from CSV

## Business Problem
You have 50 new employees joining and need to provision CloudRadial portal accounts for all of them at once, assigning each to the correct department and location.

## Prerequisites
- PowerShell 5.1 or later
- CSV file with columns: FirstName, LastName, Email, Department, Location

## Usage
1. Create a CSV file named `users.csv`
2. Run: `.\bulk-create-users.ps1 -CsvPath ".\users.csv"`
3. Review the output for any failures

## Expected Output
Console output showing each user created, plus a summary:
```
Created: john.doe@company.com (Engineering)
Created: jane.smith@company.com (Sales)
...
Total created: 50, Failed: 0
```

## Troubleshooting
- **"API returned 401"**: Check that your API keys are valid
- **"CSV file not found"**: Ensure the file path is correct
```

## Testing Before Submission

1. **Test with sample data** relevant to MSP scenarios
2. **Use `-WhatIf`** first to preview changes
3. **Check error cases**: What happens if a user already exists? If the API is unreachable?
4. **Verify in a test tenant** before using in production
5. **Document any edge cases** you discover

## Code Style

- Use **camelCase** for variable names: `$publicKey`, `$responseData`
- Use **PascalCase** for function names: `New-CloudRadialUser`, `Get-EndpointStatus`
- Keep lines under 120 characters for readability
- Use **inline comments** for complex logic, not for obvious code
- Consistent indentation (4 spaces, no tabs)

## Issue Templates

### Script Request

```
Title: [Request] Brief description of what you need

**Business Problem**
Describe the situation where you'd use this script

**Proposed Script**
What should the script do? (e.g., "Bulk create users from a CSV")

**Example Use Case**
When and how would you run this?
```

### Bug Report

```
Title: [Bug] Script name - brief description

**Which Script**
e.g., `user-management/bulk-create-users.ps1`

**What Happened**
Describe the error or unexpected behavior

**Expected Behavior**
What should have happened?

**Error Messages**
Paste any PowerShell errors or API responses

**Environment**
- PowerShell version: (Get-Host).Version
- OS: Windows Server 2019 / Windows 10 / etc.
- CloudRadial version: (if known)
```

## Questions?

- Check existing scripts and their READMEs for examples
- Review [legacy-scripts/getting-started/authentication.md](legacy-scripts/getting-started/authentication.md) for API basics
- Open an issue in this repository—the community is here to help

Thank you for contributing to CloudRadial automation!
