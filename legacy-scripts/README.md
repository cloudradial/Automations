# Legacy Scripts

The original standalone PowerShell scripts that call the CloudRadial API. They're kept here for reference and are no longer updated. Most are replaced by an AutomationAI automation in the [repo root](../), which runs on your runner instead of a workstation or RMM.

## Scripts

| Script | What it does | Folder | Replaced by |
|--------|-------------|--------|-------------|
| **Secure Score Assessment** | Import Microsoft Secure Scores as CloudRadial Assessments (from export or Graph API) | [`secure-score-assessment/`](secure-score-assessment/) | [`secure-score-assessment`](../secure-score-assessment/) |
| **Company Bulk Import** | Bulk-create companies from a CSV template | [`company-management/bulk-import/`](company-management/bulk-import/) | [`add-companies-to-portal`](../add-companies-to-portal/) |
| **User Bulk Upload** | Bulk-create or update portal users from CSV | [`user-management/bulk-upload/`](user-management/bulk-upload/) | [`onboard-users-to-portal`](../onboard-users-to-portal/) |
| **Flexible Asset Sync** | Sync IT Glue Flexible Assets into CloudRadial | [`flexible-assets/itglue-to-cloudradial/`](flexible-assets/itglue-to-cloudradial/) | [`itglue-to-flexible-assets`](../itglue-to-flexible-assets/) |
| **Service Catalog Sync** | Sync service request question templates via API | [`service-catalog/question-template-sync/`](service-catalog/question-template-sync/) | [`import-service-catalog`](../import-service-catalog/) |
| **Endpoint Token Generator** | Populate dynamic endpoint-name tokens for portal content | [`tokens/endpoint-names/`](tokens/endpoint-names/) | [`endpoint-names-token`](../endpoint-names-token/) |
| **Endpoint Warranty Report** | Generate warranty expiration reports across companies | [`endpoint-reporting/`](endpoint-reporting/) | [`endpoint-lifecycle-manager`](../endpoint-lifecycle-manager/) |
| **Feedback & CSAT Report** | Export feedback data and calculate CSAT scores | [`feedback-analysis/`](feedback-analysis/) | [`feedback-csat-report`](../feedback-csat-report/) |
| **Domain Expiration Report** | Sweep managed domains for upcoming expirations | [`service-management/`](service-management/) | [`domain-expiration-report`](../domain-expiration-report/) |
| **Certificate Expiration Report** | Check SSL certificates nearing expiration | [`reporting-admin/`](reporting-admin/) | [`certificate-expiration-report`](../certificate-expiration-report/) |
| **Content Bulk Import** | Bulk-create KB articles from CSV | [`content-management/`](content-management/) | [`bulk-create-kb-articles`](../bulk-create-kb-articles/) |
| **Course Builder** | Create training courses and lessons from CSV | [`course-management/`](course-management/) | [`bulk-create-training-courses`](../bulk-create-training-courses/) |

Also here: [`getting-started/`](getting-started/) (API authentication and AI customization guides), [`helpers/`](helpers/) (shared script helpers) and `apply-client-deliverable.sh`.

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

CloudRadial's API follows standard REST and OData patterns that Claude understands well.

1. Start with an existing script from this folder
2. Describe your changes in plain English
3. Paste the script + description into Claude
4. Test with `-WhatIf` before running in production

See [getting-started/using-ai-to-customize.md](getting-started/using-ai-to-customize.md) for examples and prompt templates.

## Prerequisites

- PowerShell 5.1 or later
- CloudRadial API keys (Public + Private) from Settings > API
