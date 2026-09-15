# CloudRadial Scripts & Automations

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![CloudRadial API](https://img.shields.io/badge/CloudRadial-API%20v2-green)

## About This Repository

Production-ready PowerShell scripts and AI plugin skills that help MSP Partners extend CloudRadial using the API. Built by the CloudRadial Customer Success team from real Partner engagements.

## AI Plugins

Connect Claude directly to your CloudRadial portal — look up companies, build training courses, create assessments, manage endpoints, and more from a chat prompt.

| Plugin | Platform | Skills | Install |
|--------|----------|--------|---------|
| **[CloudRadial UCP Plugin](cowork-plugin/cloudradial-ucp/)** | Cowork, Claude Desktop | 12 skills | [Download .plugin](https://github.com/cloudradial/helpers/releases) |
| **[CloudRadial Codex Plugin](codex-plugin/)** | Claude Code, Codex | 12 skills | [Download .plugin](https://github.com/cloudradial/helpers/releases) |

Both plugins use the same MCP server and API — pick the one that matches your Claude app.

## Standalone Scripts

PowerShell scripts you can run directly, schedule via RMM, or customize with AI.

| Script | What It Does | Folder |
|--------|-------------|--------|
| **Secure Score Assessment** | Import Microsoft Secure Scores as CloudRadial Assessments (from export or Graph API) | [`secure-score-assessment/`](secure-score-assessment/) |
| **Company Bulk Import** | Bulk-create companies from a CSV template | [`company-management/bulk-import/`](company-management/bulk-import/) |
| **User Bulk Upload** | Bulk-create or update portal users from CSV | [`user-management/bulk-upload/`](user-management/bulk-upload/) |
| **Flexible Asset Sync** | Sync IT Glue Flexible Assets into CloudRadial | [`flexible-assets/itglue-to-cloudradial/`](flexible-assets/itglue-to-cloudradial/) |
| **Service Catalog Sync** | Sync service request question templates via API | [`service-catalog/question-template-sync/`](service-catalog/question-template-sync/) |
| **Endpoint Token Generator** | Populate dynamic endpoint-name tokens for portal content | [`tokens/endpoint-names/`](tokens/endpoint-names/) |
| **Endpoint Warranty Report** | Generate warranty expiration reports across companies | [`endpoint-reporting/`](endpoint-reporting/) |
| **Feedback & CSAT Report** | Export feedback data and calculate CSAT scores | [`feedback-analysis/`](feedback-analysis/) |
| **Domain Expiration Report** | Sweep managed domains for upcoming expirations | [`service-management/`](service-management/) |
| **Certificate Expiration Report** | Check SSL certificates nearing expiration | [`reporting-admin/`](reporting-admin/) |
| **Content Bulk Import** | Bulk-create KB articles from CSV | [`content-management/`](content-management/) |
| **Course Builder** | Create training courses and lessons from CSV | [`course-management/`](course-management/) |

## AutomationAI Workflows

Importable [AutomationAI](automationai/) workflows — `.yml` definitions you import into AutomationAI and run on your runner, triggered by a secure webhook (a CloudRadial form, an Automation, or a ServiceAI Action). Broken out into legible per-step nodes.

| Workflow | What It Does | Folder |
|----------|-------------|--------|
| **Password Reset (Self-Service)** | Self-service M365 password reset, gated so a requester can reset only their own account | [`automationai/password-reset/`](automationai/password-reset/) |
| **Password Reset (ServiceAI Triage)** | Ticket-triggered reset via a ServiceAI Action; resets when the authenticated submitter owns the account, else holds for confirmation | [`automationai/password-reset-triage/`](automationai/password-reset-triage/) |

## Quick Start

Get your first API call working in 15 minutes:

1. **Get your API keys** from Settings > API in your CloudRadial portal
2. **Read** [getting-started/authentication.md](getting-started/authentication.md) for the full walkthrough
3. **Run this example** in PowerShell:

```powershell
$publicKey = "YOUR_PUBLIC_KEY"
$privateKey = "YOUR_PRIVATE_KEY"
$authHeader = @{
    Authorization = "Basic " + [Convert]::ToBase64String(
        [Text.Encoding]::ASCII.GetBytes("$($publicKey):$($privateKey)")
    )
}
$response = Invoke-RestMethod -Uri "https://api.us.cloudradial.com/v2/odata/company" `
    -Headers $authHeader -Method Get
$response
```

## Using AI to Customize

Don't see exactly what you need? Use AI to generate it. CloudRadial's API follows standard REST and OData patterns that Claude understands well.

1. Start with an existing script from this repo
2. Describe your changes in plain English
3. Paste the script + description into Claude
4. Test with `-WhatIf` before running in production

See [getting-started/using-ai-to-customize.md](getting-started/using-ai-to-customize.md) for examples and prompt templates.

## Prerequisites

- PowerShell 5.1 or later
- CloudRadial API keys (Public + Private) from Settings > API
- For AI plugins: Claude Desktop, Cowork, or Claude Code

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT
