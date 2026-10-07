---
name: assessment-export
description: >
  Export completed CloudRadial assessment data across multiple customers via the API and build
  executive-level summaries. Use when the user says "export assessments", "assessment export",
  "pull assessment data", "assessment executive summary", "compliance summary across customers",
  "roll up assessment scores", "how are all my clients doing on assessments", "consolidate
  assessment results", "assessment gaps report", "which customers have the most gaps", or needs to
  extract completed assessment results (name, customer, score, completion date, status) across all
  companies from one place rather than opening each client individually. Reach for this skill
  whenever assessment reporting, cross-customer compliance roll-ups, or executive assessment
  summaries come up, even if the user does not say the word "API".
metadata:
  version: "1.0.0"
---

# Assessment Export & Executive Summary

Pull completed assessment data across every company in a CloudRadial portal through the API, then
consolidate it into an executive summary: totals, gaps, common issues, remediation opportunities,
and per-customer + overall trends.

This exists because CloudRadial's native per-run Excel/Word exports are generated one client at a
time. The API is the fastest way to get a single cross-customer dataset for leadership reporting.

## How to Call the API

All CloudRadial work goes through MCP tools served by the `cloudradial-ucp` server. Relevant tools:

| Tool | Purpose |
|------|---------|
| `setup_status` | Confirm credentials are stored (call first) |
| `list_resources` | List a resource type with OData filtering (`assessment`, `company`) |
| `count_resources` | Count a resource type with an optional `filter` |
| `search_companies` | Resolve a company name to an ID |
| `get_resource` | Read one assessment by `assessmentId` |

### Before you start

Call `setup_status`. If it returns `configured: false`, or any call returns 401/403, stop and run
the `setup` skill first. Everything here depends on stored credentials. Any HTTP 4xx/5xx comes back
as a tool error, not as data.

### OData conventions

For `list_resources` / `count_resources`, pass OData params **without** the leading `$`: `filter`,
`select`, `orderby`, `top`, `skip`. The server adds the `$`. Default page is `top=100`, max `200`.
The API returns no next-page link, so keep incrementing `skip` until a page comes back shorter than
`top`. Don't pass `select` for `assessment`: it returns HTTP 500.

## The `assessment` resource

Key fields: `assessmentId`, `companyId`, `title` (NOT `name`), `category`, `type`, `status`,
`dateConducted`, `totalScore`, `maxScore`, `compliantScore`, `partialScore`. The score fields are
nullable numbers (blank until scored).

**`type` codes** (not documented in the API; observed in live data):

| `type` | Meaning |
|---|---|
| 10 | Template (category "Template", no `dateConducted`) |
| 20 | Assessment: the only type the portal's Assessments list shows. Its Date Run, Score and Status come from its latest run |
| 30 | Run: a dated copy of an assessment, titled "<assessment> - M/d/yy" |

`status` is a plain integer with undocumented codes, so don't filter on it server-side.

**Important:** `get_resource` works by `assessmentId`, but the resource returns **summary-level data
only** (one row per assessment/run, not per question). The API has no question or answer entity. See
"Getting question-level detail" below before promising it.

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
higher-risk customers. For true per-question gap counts you need question-level detail (below).

## Workflow

### Step 1 — Pull completed assessments across all companies

Call `list_resources` with `resource_type: "assessment"` and **no** `companyId` filter so it spans
every company. Filter to completed runs and page through everything:

- `filter`: `type eq 30 and dateConducted ne null` for every completed run (use `type eq 20` for
  each assessment's current state, as the portal lists it). If the date filter is rejected, filter on
  `type` only and drop rows without `dateConducted` client-side. Don't filter on `status`.
- `orderby`: `dateConducted desc`
- `top`: `200`, then repeat with `skip: 200`, `skip: 400`, ... until a page returns fewer than 200
  rows.

Keep `assessmentId`, `companyId`, `title`, `type`, `status`, `totalScore`, `maxScore`,
`compliantScore`, `dateConducted` for every row.

If you only need counts (e.g. "how many completed this quarter"), use `count_resources` with the
same filter instead of paging.

### Step 2 — Resolve company names

`assessment` rows carry `companyId`, not the customer name. Build a lookup:

- Call `list_resources` with `resource_type: "company"`, `select: "companyId,name"`, paging as
  needed, and map `companyId -> name`. (For a one-off single customer, `search_companies` is fine.)

Join the map onto your assessment rows so every row has a readable **Customer name**.

### Step 3 — Getting question-level detail (individual responses, failed answers, tickets)

The `assessment` list resource does not expose per-question responses, failed/"Not Compliant"
answers, or linked PSA tickets. Two paths:

1. **The API has no question-level data.** There is no assessment question or answer entity in the
   v2 API, so don't probe `raw_api_call` for one.
2. **Portal export.** The reliable source is the per-run **Excel export** (Compliance > Assessments > run > three-dot menu >
   Export) or the **Word report** (run > Recommendations > Report). State this to the user rather
   than inventing question-level figures from the summary data — see the honesty note below.

### Step 4 — Build the outputs

Produce two deliverables.

**A. Cross-customer roll-up spreadsheet** (use the `xlsx` skill). One row per completed assessment:

| Column | Source |
|--------|--------|
| Customer | company name map (Step 2) |
| Assessment name | `title` |
| Completion date | `dateConducted` |
| Status | `status` (numeric code) |
| Score | `totalScore` / `maxScore` |
| Gaps (negative answers) | question-level detail if available, else leave blank / note "see run export" |

Add a summary tab: total assessments completed, count of customers assessed, average/median score,
lowest-scoring customers, and (if question-level data was obtained) total gaps.

**B. Executive summary** (short written document — use the `docx` skill for a client/leadership
deliverable, or markdown if the user just wants text). Use this structure:

```
# Assessment Executive Summary — [period]
## Overview
Total assessments completed, customers assessed, overall score posture.
## Gaps Identified
Count and severity of gaps; lowest-scoring areas/customers.
## Most Common Issues
Recurring alignment/security themes across customers (requires question-level detail).
## Remediation Opportunities
Highest-impact fixes; customers with the most open gaps.
## Trends
Per-customer movement across runs (group by customer + assessment title, order by dateConducted)
and overall direction.
```

For **trends**, compare runs over time: group run rows (`type` 30) by `companyId` + assessment
`title` without its " - M/d/yy" date suffix, order by `dateConducted`, and report score movement
between the earliest and latest run per group.

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

If question-level detail cannot be retrieved from the API in a given portal, do not fabricate
per-question counts from the summary score. State clearly which fields came from the API and which
require the portal export, and flag any lowered confidence. Accuracy matters more than a complete-
looking table.

## Reference

See `references/api-details.md` for exact OData query examples and pagination snippets.
