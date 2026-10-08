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
| `get_resource` | Retrieve one resource by ID (optional `company_id` for company-scoped types) | `resource_type`, `id` |
| `create_resource` | Create a new resource | `resource_type`, `data` |
| `update_resource` | Partial update: PATCH by default, so fields you leave out are kept. `method: "PUT"` replaces the whole record | `resource_type`, `id`, `data` |
| `delete_resource` | Delete by ID (always confirm with the user first) | `resource_type`, `id` |
| `user_lookup` | Find users by email, name, or company | one of `email`/`name`/`company_id` |
| `manage_tokens` | List, get, set or delete replacement tokens (the @Token values forms and automations fill in), partner-level or per company. Not API keys. | `action` |
| `endpoint_update_warranty` | Trigger async warranty refresh by endpoint serial number | `serial_number` |
| `courseenrollment_complete` | Mark a course enrollment completed (optional score/comment) | `enrollment_id` |
| `courseenrollment_for_user` | Get a user's enrollment record for a specific course | `course_id`, `user_id` |
| `assessment_import` | Create or refresh an assessment from a question list or a template-layout .xlsx, or copy a template's questions into an existing assessment | `company_id` + one source |
| `raw_api_call` | Direct API call for advanced cases | `path` |

### OData parameter conventions

For `list_resources` and `count_resources`, pass OData parameters **without** the leading `$`:
`filter`, `select`, `orderby`, `top`, `skip`, `expand`, `search`. The server adds the `$` when
forwarding. Defaults to `top=100` if unspecified (pagination by default to avoid hammering the API).
Max page is 200 and the API returns no next-page link, so keep incrementing `skip` until a page comes back shorter than `top`.

### Field-name quirks

- Articles use `subject` (not `title`).
- Courses use `name` (not `title`). Assessments use `title` (not `name`).
- `archive_item` composite key — pass `archive_id` and `id`.
- `service_install` composite key — pass `endpoint_id` and `service_id` (or `id = serviceId` on update/delete).
- `endpoint_custom_property` — get/create/update/delete take `serial_number` and `property_name`; list with `filter: "companyEndpointId eq <id>"`.
- OData returns enum fields as names (for example `enclosure: "Desktop"`), not numbers.

### Errors

- **"credentials not configured"** → defer to the `setup` skill.
- **401/403 from CloudRadial** → stored credentials are invalid. Run `setup` to rotate.
- **404** → resource not found. Verify the ID, and for `catalog_question`, `course_lesson`, `domain`, `user`, `application_user` and `token` pass `company_id`.
- Every HTTP 4xx/5xx comes back as a tool error, not as data. Read the message and fix the call instead of retrying it unchanged.

## Resource Types

### assessment
Security and compliance assessments. Key fields: `assessmentId`, `companyId`, `title` (NOT `name`),
`category`, `type`, `status`, `dateConducted`, `dateNextDue`, `totalScore`, `maxScore`,
`compliantScore`, `partialScore`, `isArchived`. The four score fields are nullable numbers (blank until scored).

**`type` codes** (not documented in the API; observed in live data):

| `type` | Meaning |
|---|---|
| 10 | Template (category "Template", no `dateConducted`) |
| 20 | Assessment: the only type the portal's Assessments list shows. Its Date Run, Score and Status come from its latest run |
| 30 | Run: a dated copy of an assessment, titled "<assessment> - M/d/yy" |

Filter on `type eq 20` to match what the portal lists, or `type eq 30` for the history of runs.
`status` is a plain integer in the API with undocumented codes, so don't filter on it server-side;
show it as-is or compare it client-side.

**Notes:** `get_resource` works by `assessmentId`. There is no update or delete for assessments, and
no question-level API: rows are summary-level only (one row per assessment/run, not per question).
Don't pass `select` when listing assessments; it returns HTTP 500.

### flexible_asset
Custom flexible assets used for tracking compliance data, configurations, or any structured data. Key
fields: `id` (the asset's ID), `companyId`, `flexibleAssetTypeId`, `name`, `resourceUrl`, `traitsJson`
(the field values as a JSON string). To update the values, call `update_resource` with
`data: { traits: { "<trait name>": "<new value>" } }`. Only traits the asset already has can be
changed (the API refuses new ones), and traits you leave out are kept.

### flexible_asset_type
Definitions for flexible asset types. Key fields: `id` (the type's ID), `name`, `description`, `icon`,
`showInMenu`.

### flexible_asset_field
Field definitions within flexible asset types. Key fields: `id` (the field's ID),
`flexibleAssetTypeId`, `name`, `nameKey`, `kind` (Text, Textbox, Date, Number, Checkbox, Select, Tag,
Upload, Percent, Header), `required`, `order`, `showInList`.

**Note:** flexible_asset_field supports list, get-by-ID and create only. The API can't update or
delete a field.

## Example Calls

**List a company's assessments (as the portal shows them):** Call `list_resources` with
`resource_type: "assessment"`, `filter: "companyId eq 42 and type eq 20"`.

**Count assessments for a company:** Call `count_resources` with `resource_type: "assessment"`,
`filter: "companyId eq 42 and type eq 20"`.

**Get one assessment:** Call `get_resource` with `resource_type: "assessment"`, `id: "<assessmentId>"`.

**List flexible assets for a company:** Call `list_resources` with `resource_type: "flexible_asset"`,
`filter: "companyId eq 42"`.

**List all flexible asset types (to understand what's tracked):** Call `list_resources` with
`resource_type: "flexible_asset_type"`.

**List fields for a flexible asset type:** Call `list_resources` with
`resource_type: "flexible_asset_field"`, `filter: "flexibleAssetTypeId eq <typeId>"`.

## API Reference

For exact field names and schema details, read `${CLAUDE_PLUGIN_ROOT}/references/api-reference.md`.

## Workflows

### Compliance Status for a Company

1. List the company's assessments with `filter: "companyId eq <id> and type eq 20"`, and its runs
   with `filter: "companyId eq <id> and type eq 30"`
2. For each assessment, note its latest run's `dateConducted` and `totalScore` out of `maxScore`,
   and `dateNextDue` if set
3. List flexible assets filtered by companyId to check configuration tracking
4. Summarize: total assessments, which have been run and which haven't, scores, overdue
   assessments (`dateNextDue` in the past), any red flags

### Flexible Asset Inventory

1. List flexible asset types to understand what categories exist (each type's ID is `id`)
2. For a specific type, list its fields with `filter: "flexibleAssetTypeId eq <id>"` to see the
   schema (`name`, `kind`, `required`)
3. List flexible assets filtered by `flexibleAssetTypeId` and/or `companyId`; the values are in
   `traitsJson`
4. Summarize the data — useful for understanding what custom tracking is in place

For a cross-company compliance roll-up, use the export workflow below.

## Creating an assessment

`create_resource` can't create an assessment: the API has no create endpoint, only the Excel upload.
Use `assessment_import`, which uploads the questions (as an assessment, `type` 20), then finds the new
`assessmentId` by title.

1. Resolve the company with `search_companies`. Confirm the company and the title with the user,
   because this writes to their portal.
2. Check for a duplicate first: `list_resources` `assessment` with
   `filter: "companyId eq <id> and type eq 20"`. If one with the same title exists, ask before
   creating another (the tool finds the new ID by title, so duplicate titles are ambiguous).
3. Call `assessment_import` with `company_id`, `title`, and exactly one question source:
   - `questions`: an array of objects keyed by template column. `Category` and `Question` are
     required; useful extras are `Explanation`, `Remediation`, `Remediation Summary`, `Reference`,
     `Order`, `Type`, `Responses`, `Answer`, `Update Key`, `Control Type`, `Risk`, `Likelihood`,
     `Owner`. Unknown column names are rejected, so use the template names. Give each question a
     stable `Update Key` if you'll refresh the answers later.
   - `file_path`: a local .xlsx the user already has in the CloudRadial assessment template layout.
   - `template_id`: copy every question from an existing template assessment into an assessment
     that already exists, so it also needs `assessment_id`. Add `apply_to` (`server`, `endpoint` or
     `user`) to duplicate the questions for each matching device or user. To start from a template
     for a new assessment, create the assessment first (from questions, a file, or in the portal).
4. To refresh an assessment that already exists, pass `assessment_id`. The upload updates it in
   place and matches questions by `Update Key`.
5. Report the `assessmentId` and how many questions went in. The client completes the assessment
   in the portal.

**Examples the user might say:** "Create a CIS Controls assessment for Contoso with these 20
questions", "Turn this spreadsheet into an assessment for company 42", "Copy our Baseline Security
template into Contoso's new assessment, one set of questions per server".

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

Any negative-scoring answer is a gap. At the summary level you get `totalScore` (the sum of the
answer scores, which can be negative), `maxScore` (every question compliant), `compliantScore` and
`partialScore`. Report the score as `totalScore` out of `maxScore`, and treat lower scores as
higher-risk customers. True per-question gap counts require question-level detail (Step 3).

## Workflow

### Step 1 — Pull completed assessments across all companies

Call `list_resources` with `resource_type: "assessment"` and **no** `companyId` filter so it spans
every company. Filter to completed runs and page through everything:

- `filter`: `type eq 30 and dateConducted ne null` for every completed run (use `type eq 20` instead
  for each assessment's current state). If the date filter is rejected, filter on `type` only and drop
  rows without `dateConducted` client-side. Don't filter on `status`: its codes aren't documented.
- `orderby`: `dateConducted desc`
- `top`: `200`, then repeat with `skip: 200`, `skip: 400`, ... until a page returns fewer than 200 rows.
- No `select`: it returns HTTP 500 on assessments.

Keep `assessmentId`, `companyId`, `title`, `type`, `status`, `totalScore`, `maxScore`,
`compliantScore`, `dateConducted` for every row. For pure counts (e.g. "how many completed this
quarter"), use `count_resources` with the same filter instead.

### Step 2 — Resolve company names

`assessment` rows carry `companyId`, not the customer name. Build a lookup with `list_resources`,
`resource_type: "company"`, `select: "companyId,name"` (page as needed), and map `companyId -> name`.
For a single known customer, `search_companies` is fine. Join the map so every row has a readable
**Customer name**.

### Step 3 — Question-level detail (individual responses, failed answers, tickets)

The `assessment` list resource does not expose per-question responses, failed/"Not Compliant"
answers, or linked PSA tickets. Two paths:

1. **The API has no question-level data.** There is no assessment question or answer entity in the
   v2 API, so don't probe `raw_api_call` for one.
2. **Portal export.** The reliable source is the per-run **Excel export** (Compliance > Assessments > run > three-dot menu > Export)
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

For **trends**, group run rows (`type` 30) by `companyId` + assessment `title` without its
" - M/d/yy" date suffix, order by `dateConducted`, and report
score movement between the earliest and latest run per group.

## Field availability (set expectations honestly)

| Requested field | Via API (`assessment` resource) | Reliable source |
|-----------------|--------------------------------|-----------------|
| Assessment name | Yes (`title`) | API |
| Customer name | Via `companyId` + company lookup | API |
| Completion date | Yes (`dateConducted`) | API |
| Score | Yes (`totalScore` of `maxScore`; `compliantScore`, `partialScore`) | API |
| Status | Numeric code only (`status`) | Portal shows the label |
| Individual question responses | Not in the API | Portal Excel export |
| Failed / "No" responses | Not in the API | Same as above |
| Remediation items / linked tickets | Not in the API | Portal Recommendations tab / run export |

## Honesty note

If question-level detail can't be retrieved from the API in a given portal, do not fabricate
per-question counts from the summary score. State clearly which fields came from the API and which
require the portal export, and flag any lowered confidence. Accuracy matters more than a
complete-looking table.

See `references/api-details.md` for exact OData query examples and pagination snippets.
