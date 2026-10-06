---
name: assessment-compliance
description: >
  Review and analyze CloudRadial security assessments, compliance status, and flexible assets, and
  export completed assessment data across multiple customers into executive-level summaries.
  Use when the user says "check assessments", "compliance status", "security assessment",
  "flexible assets", "asset types", "how is [company] doing on compliance", "assessment results",
  "audit compliance", or needs to list, review, or analyze assessments and flexible asset data
  across CloudRadial portals. ALSO use for cross-customer reporting: "export assessments",
  "assessment export", "pull assessment data", "assessment executive summary", "compliance summary
  across customers", "roll up assessment scores", "how are all my clients doing on assessments",
  "consolidate assessment results", "assessment gaps report", or "which customers have the most
  gaps" — even if the user does not say the word "API".
metadata:
  version: "1.1.0"
---

# Assessment & Compliance

Review security assessments, compliance status, and flexible asset data across CloudRadial portals,
and export completed assessment results across all customers into an executive summary.

## How to Call the API

All CloudRadial work goes through MCP tools served by the `cloudradial-ucp` server. The plugin
auto-registers the server via `.mcp.json` — no Azure Function, no Chrome extension, no local config
file.

### Before any tool call

Call `setup_status` first to confirm credentials are stored. If it returns `configured: false`, defer
to the `setup` skill before doing CloudRadial work.

### Available MCP tools

| Tool | Purpose | Required args |
|------|---------|---------------|
| `setup_status` | Check credential state (never returns the keys) | — |
| `search_companies` | Search companies by partial name | `name` |
| `company_overview` | Snapshot: details, user/endpoint counts, recent articles + feedback | `company_id` |
| `list_resources` | List any of 30 resource types with OData filtering | `resource_type` |
| `count_resources` | Count a resource type with optional `filter` | `resource_type` |
| `get_resource` | Retrieve one resource by ID | `resource_type`, `id` |
| `create_resource` | Create a new resource | `resource_type`, `data` |
| `update_resource` | PUT (full) or PATCH (partial) update | `resource_type`, `id`, `data` |
| `delete_resource` | Delete by ID | `resource_type`, `id` |
| `user_lookup` | Find users by email, name, or company | one of `email`/`name`/`company_id` |
| `manage_tokens` | List, get, set or delete replacement tokens (the @Token values forms and automations fill in), partner-level or per company. Not API keys. | `action` |
| `endpoint_update_warranty` | Trigger async warranty refresh by endpoint serial number | `serial_number` |
| `courseenrollment_complete` | Mark a course enrollment completed (optional score/comment) | `enrollment_id` |
| `courseenrollment_for_user` | Get a user's enrollment record for a specific course | `course_id`, `user_id` |
| `assessment_import` | Create an assessment and fill it with questions (from a list, a template-layout .xlsx, or a template assessment) | `company_id` + one source |
| `raw_api_call` | Direct API call for advanced cases | `path` |

### OData parameter conventions

For `list_resources` and `count_resources`, pass OData parameters **without** the leading `$`:
`filter`, `select`, `orderby`, `top`, `skip`, `expand`, `search`. The server adds the `$` when
forwarding. Defaults to `top=100` if unspecified (pagination by default to avoid hammering the API).
Max page is 200; walk through larger pages by incrementing `skip`.

### Field-name quirks

- Articles use `subject` (not `title`).
- Courses use `name` (not `title`).
- `archive_item` composite key — pass `archive_id` and `id`.
- `service_install` composite key — pass `endpoint_id` and `service_id` (or `id = serviceId` on update/delete).

### Errors

- **"credentials not configured"** → defer to the `setup` skill.
- **401/403 from CloudRadial** → stored credentials are invalid. Run `setup` to rotate.
- **404** → resource not found, verify the ID.

## Resource Types

### assessment
Security and compliance assessments. Key fields: `assessmentId`, `companyId`, `name`, `status`,
`score`, `dateCompleted`.

**Note:** Assessments support listing but NOT get-by-ID, and return summary-level data only (one row
per assessment/run, not per question).

### flexible_asset
Custom flexible assets used for tracking compliance data, configurations, or any structured data. Key
fields: `flexibleAssetId`, `companyId`, `flexibleAssetTypeId`, `name`.

### flexible_asset_type
Definitions for flexible asset types. Key fields: `flexibleAssetTypeId`, `name`, `description`.

### flexible_asset_field
Field definitions within flexible asset types. Key fields: `flexibleAssetFieldId`,
`flexibleAssetTypeId`, `name`, `fieldType`.

**Note:** flexible_asset_field supports listing but NOT get-by-ID.

## Example Calls

**List all assessments:** Call `list_resources` with `resource_type: "assessment"`.

**Count assessments for a company:** Call `count_resources` with `resource_type: "assessment"`,
`filter: "companyId eq 42"`.

**List flexible assets for a company:** Call `list_resources` with `resource_type: "flexible_asset"`,
`filter: "companyId eq 42"`.

**List all flexible asset types (to understand what's tracked):** Call `list_resources` with
`resource_type: "flexible_asset_type"`.

**List fields for a flexible asset type:** Call `list_resources` with
`resource_type: "flexible_asset_field"`, `filter: "flexibleAssetTypeId eq <typeId>"`.

## Creating an assessment

`create_resource` can't create an assessment: the portal builds one from an Excel import. Use
`assessment_import`, which creates the assessment and imports its questions in one call.

1. Resolve the company with `search_companies`. Confirm the company and the title with the user,
   because this writes to their portal.
2. Check for a duplicate first: `list_resources` `assessment` with `filter: "companyId eq <id>"`.
   If one with the same title exists, ask before creating another.
3. Call `assessment_import` with `company_id`, `title`, optional `category` (default `Security`)
   and `description`, and exactly one question source:
   - `questions`: an array of objects keyed by template column. `Category` and `Question` are
     required; useful extras are `Explanation`, `Remediation`, `Remediation Summary`, `Reference`,
     `Order`, `Type`, `Responses`, `Control Type`, `Risk`, `Likelihood`, `Owner`.
     Unknown column names are rejected, so use the template names.
   - `file_path`: a local .xlsx the user already has in the CloudRadial assessment template layout.
   - `template_id`: copy every question from an existing template assessment. Add `apply_to`
     (`server`, `endpoint` or `user`) to duplicate the questions for each matching device or user.
4. To add questions to an assessment that already exists, pass `assessment_id` instead of `title`.
5. Report the `assessmentId` and how many questions went in. The client completes the assessment
   in the portal.

**Examples the user might say:** "Create a CIS Controls assessment for Contoso with these 20
questions", "Turn this spreadsheet into an assessment for company 42", "Copy our Baseline Security
template into a new assessment for Acme, one set of questions per server".

For Microsoft Secure Score specifically, the AutomationAI workflow
[Turn Microsoft Secure Score into a Client Assessment](https://github.com/cloudradial/Automations/tree/main/automationai/secure-score-assessment)
reads Secure Score from Graph and builds the assessment on its own.

---

# Cross-Customer Executive Summary Export

Use this workflow when the goal is to pull completed assessment data across **every** company at once
and consolidate it into an executive summary (totals, gaps, common issues, remediation, trends).
CloudRadial's native per-run Excel/Word exports are generated one client at a time, so the API is the
fastest way to get a single cross-customer dataset for leadership reporting.

## Scoring model (how to quantify gaps)

CloudRadial scores each assessment question on this scale:

- **+2** Compliant
- **+1** Partially Compliant
- **0** N/A
- **-1** Missing
- **-2** Not Compliant

Any negative-scoring answer is a gap. At the summary level you get the overall `score`; treat lower
scores and lower completion as higher-risk customers. True per-question gap counts require
question-level detail (Step 3).

## Workflow

### Step 1 — Pull completed assessments across all companies

Call `list_resources` with `resource_type: "assessment"` and **no** `companyId` filter so it spans
every company. Filter to completed runs and page through everything:

- `filter`: try `dateCompleted ne null` first; if that field rejects it, fall back to a status filter
  (e.g. `status eq 'Completed'`) or pull all and filter client-side.
- `orderby`: `dateCompleted desc`
- `top`: `200`, then repeat with `skip: 200`, `skip: 400`, ... until a page returns fewer than 200 rows.

Keep `assessmentId`, `companyId`, `name`, `status`, `score`, `dateCompleted` for every row. For pure
counts (e.g. "how many completed this quarter"), use `count_resources` with the same filter instead.

### Step 2 — Resolve company names

`assessment` rows carry `companyId`, not the customer name. Build a lookup with `list_resources`,
`resource_type: "company"`, `select: "companyId,name"` (page as needed), and map `companyId -> name`.
For a single known customer, `search_companies` is fine. Join the map so every row has a readable
**Customer name**.

### Step 3 — Question-level detail (individual responses, failed answers, tickets)

The `assessment` list resource does not expose per-question responses, failed/"Not Compliant"
answers, or linked PSA tickets. Two paths:

1. **Probe the API.** Use `raw_api_call` to look for a run/question endpoint under `/v2/odata/`
   (inspect the returned shape before relying on it). If a question-level endpoint returns
   responses/scores, use it to count negative-scored answers per assessment.
2. **Portal fallback.** If the API doesn't expose question-level data in this portal, the reliable
   source is the per-run **Excel export** (Compliance > Assessments > run > three-dot menu > Export)
   or the **Word report** (run > Recommendations > Report). Tell the user rather than inventing
   question-level figures from the summary score — see the honesty note below.

### Step 4 — Build the outputs

**A. Cross-customer roll-up spreadsheet** (use the `xlsx` skill). One row per completed assessment:
Customer, Assessment name, Completion date, Status, Score, Gaps (from Step 3 if available, else blank
with "see run export"). Add a summary tab: total assessments completed, customers assessed,
average/median score, lowest-scoring customers, and total gaps if obtained.

**B. Executive summary** (use the `docx` skill for a leadership deliverable, or markdown for plain
text). Structure:

```
# Assessment Executive Summary — [period]
## Overview            (totals, customers assessed, overall score posture)
## Gaps Identified      (count + severity; lowest-scoring areas/customers)
## Most Common Issues   (recurring themes; requires question-level detail)
## Remediation Opportunities  (highest-impact fixes; customers with most gaps)
## Trends               (per-customer movement across runs + overall direction)
```

For **trends**, group rows by `companyId` + assessment `name`, order by `dateCompleted`, and report
score movement between the earliest and latest run per group.

## Field availability (set expectations honestly)

| Requested field | Via API (`assessment` resource) | Reliable source |
|-----------------|--------------------------------|-----------------|
| Assessment name | Yes (`name`) | API |
| Customer name | Via `companyId` + company lookup | API |
| Completion date | Yes (`dateCompleted`) | API |
| Score / completion % | Yes (`score`) | API |
| Status | Yes (`status`) | API |
| Individual question responses | Not in summary resource | Probe `raw_api_call`; else portal Excel export |
| Failed / "No" responses | Not in summary resource | Same as above |
| Remediation items / linked tickets | Not in summary resource | Portal Recommendations tab / run export |

## Honesty note

If question-level detail can't be retrieved from the API in a given portal, do not fabricate
per-question counts from the summary score. State clearly which fields came from the API and which
require the portal export, and flag any lowered confidence. Accuracy matters more than a
complete-looking table.

See `references/api-details.md` for exact OData query examples, `raw_api_call` paths, and pagination
snippets.
