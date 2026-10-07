---
name: portal-lookup
description: >
  Look up a CloudRadial partner or client portal to review their setup status.
  Use when the user says "look up a partner", "check portal status", "find a company
  in CloudRadial", "how is [company] doing in their portal", "prepare for a meeting
  with [company]", "partner overview", "company overview", or needs to find information
  about a specific company, its users, endpoints, articles, or portal configuration
  before a call or implementation session.
metadata:
  version: "1.1.0"
---

# Portal Lookup

Retrieve and summarize a client's CloudRadial portal status using the CloudRadial MCP server.

## How to Call the API

All CloudRadial work goes through MCP tools served by the `cloudradial-ucp` server. The plugin auto-registers the server via `.mcp.json` — no Azure Function, no Chrome extension, no local config file.

### Before any tool call

Call `setup_status` first to confirm credentials are stored. If it returns `configured: false`, defer to the `setup` skill before doing CloudRadial work.

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
| `raw_api_call` | Direct API call for advanced cases | `path` |

### OData parameter conventions

For `list_resources` and `count_resources`, pass OData parameters **without** the leading `$`: `filter`, `select`, `orderby`, `top`, `skip`, `expand`, `search`. The server adds the `$` when forwarding. Defaults to `top=100` if unspecified (pagination by default to avoid hammering the API). Max page is 200 and the API returns no next-page link, so keep incrementing `skip` until a page comes back shorter than `top`.

### Field-name quirks

- Articles use `subject` (not `title`).
- Courses use `name` (not `title`).
- `archive_item` composite key — pass `archive_id` and `id`.
- `service_install` composite key — pass `endpoint_id` and `service_id` (or `id = serviceId` on update/delete).
- `endpoint_custom_property` — get/create/update/delete take `serial_number` and `property_name`; list with `filter: "companyEndpointId eq <id>"`.
- OData returns enum fields as names (for example `enclosure: "Desktop"`), not numbers.

### Errors

- **"credentials not configured"** → defer to the `setup` skill.
- **401/403 from CloudRadial** → stored credentials are invalid. Run `setup` to rotate.
- **404** → resource not found. Verify the ID, and for `catalog_question`, `course_lesson`, `domain`, `user`, `application_user` and `token` pass `company_id`.
- Every HTTP 4xx/5xx comes back as a tool error, not as data. Read the message and fix the call instead of retrying it unchanged.

## API Reference

If you need to check exact field names, required parameters, or available filters for any resource type, read the API reference at `${CLAUDE_PLUGIN_ROOT}/references/api-reference.md`.

## Workflow

1. **Identify the company.** If the user provides a company name, call `search_companies` with `name: "<company name>"`. If they provide a company ID, skip to step 2. If multiple matches are returned, present the top matches and ask the user to confirm which one.

2. **Pull the overview.** Call `company_overview` with `company_id: "<id>"`. This returns company details, user count, endpoint count, recent articles, and recent feedback in a single batch.

3. **Enrich with counts.** Call `count_resources` for these resource types filtered by companyId:
   - `article` — total KB articles
   - `course` — total training courses
   - `assessment` — total assessments (add `and type eq 20` to the filter: type 20 rows are what the portal lists; 10 are templates and 30 are runs)
   - `feedback` — total feedback entries

4. **Pull recent feedback.** Call `list_resources` with `resource_type: "feedback"`, `filter: "companyId eq <id>"`, `orderby: "dateCreated desc"`, `top: "5"`, `select: "feedbackId,feedbackRating,feedbackRatingNumber,feedbackComment,userEmail,userFirstName,ticketSubject,dateCreated"`. `feedbackRating` comes back as an enum name, not a number.

5. **Classify LOMG stage** based on the data:
   - **Land**: Few users, no articles, no endpoints
   - **Onboard**: Articles being created, users being added
   - **Manage**: Consistent endpoints, regular feedback, published articles
   - **Grow**: Courses deployed, assessments running, high engagement

6. **Identify flags:**
   - Negative feedback that may be unaddressed
   - Zero endpoints (no device sync)
   - Portal branding (logo, theme color): the API can't read it, so list it as something to check in the portal, not as a finding
   - Low user count relative to endpoint count
   - No assessments or courses (growth opportunities)

7. **Generate a visual presentation.** Use `show_widget` to render an inline HTML card summarizing the meeting prep. The widget MUST follow this layout:

## Visual Presentation Template

When presenting a company overview or meeting prep, ALWAYS render a visual widget using `show_widget` with the following HTML structure. Replace the placeholder values with real data from the API calls above.

```html
<div style="max-width:720px;margin:0 auto;font-family:var(--font-sans)">
  <!-- Header -->
  <div style="display:flex;align-items:center;gap:12px;margin-bottom:16px">
    <div style="width:40px;height:40px;border-radius:50%;background:linear-gradient(135deg,#D4A574,#C4956A);display:flex;align-items:center;justify-content:center;font-weight:500;font-size:16px;color:#fff;flex-shrink:0">C</div>
    <div>
      <h1 style="font-size:20px;font-weight:500;margin:0;color:var(--color-text-primary)">Meeting prep — {COMPANY_NAME}</h1>
      <p style="font-size:13px;color:var(--color-text-secondary);margin:0">Account Manager: {ACCOUNT_MANAGER}</p>
    </div>
    <span style="margin-left:auto;background:var(--color-background-success);color:var(--color-text-success);font-size:12px;font-weight:500;padding:4px 12px;border-radius:var(--border-radius-md)">{LOMG_STAGE}</span>
  </div>

  <!-- Portal snapshot stats -->
  <div style="background:var(--color-background-primary);border:0.5px solid var(--color-border-tertiary);border-radius:var(--border-radius-lg);padding:1rem 1.25rem;margin-bottom:12px">
    <p style="font-weight:500;font-size:14px;margin:0 0 12px;color:var(--color-text-primary)">Portal snapshot</p>
    <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(100px,1fr));gap:8px">
      <!-- Repeat this block for each stat: Users, Endpoints, Articles, Courses, Assessments -->
      <div style="background:var(--color-background-secondary);border-radius:var(--border-radius-md);padding:10px;text-align:center">
        <div style="font-size:22px;font-weight:500;color:var(--color-text-info)">{VALUE}</div>
        <div style="font-size:11px;color:var(--color-text-secondary);text-transform:uppercase;letter-spacing:0.3px">{LABEL}</div>
      </div>
    </div>
  </div>

  <!-- Recent feedback table -->
  <div style="background:var(--color-background-primary);border:0.5px solid var(--color-border-tertiary);border-radius:var(--border-radius-lg);padding:1rem 1.25rem;margin-bottom:12px">
    <p style="font-weight:500;font-size:14px;margin:0 0 12px;color:var(--color-text-primary)">Recent feedback</p>
    <table style="width:100%;font-size:13px;border-collapse:collapse">
      <tr style="border-bottom:0.5px solid var(--color-border-tertiary)">
        <td style="padding:6px 0;color:var(--color-text-secondary);font-weight:500">Date</td>
        <td style="padding:6px 0;color:var(--color-text-secondary);font-weight:500">Ticket</td>
        <td style="padding:6px 0;color:var(--color-text-secondary);font-weight:500">Rating</td>
        <td style="padding:6px 0;color:var(--color-text-secondary);font-weight:500">Comment</td>
      </tr>
      <!-- Repeat for each feedback entry -->
      <tr style="border-bottom:0.5px solid var(--color-border-tertiary)">
        <td style="padding:6px 0;color:var(--color-text-secondary)">{DATE}</td>
        <td style="padding:6px 0">{TICKET_SUBJECT}</td>
        <td style="padding:6px 0"><span style="background:{RATING_BG};color:#fff;font-size:11px;font-weight:500;padding:2px 8px;border-radius:var(--border-radius-md)">{RATING}</span></td>
        <td style="padding:6px 0;color:var(--color-text-secondary)">{COMMENT}</td>
      </tr>
    </table>
  </div>

  <!-- Flags -->
  <div style="background:var(--color-background-primary);border:0.5px solid var(--color-border-tertiary);border-radius:var(--border-radius-lg);padding:1rem 1.25rem;margin-bottom:12px">
    <p style="font-weight:500;font-size:14px;margin:0 0 8px;color:var(--color-text-primary)">Flags</p>
    <!-- Repeat for each flag. Use color-text-danger for warnings, color-text-warning for cautions, color-text-success for positives -->
    <p style="font-size:13px;color:var(--color-text-secondary);margin:4px 0;display:flex;align-items:center;gap:8px">
      <span style="width:8px;height:8px;border-radius:50%;background:var(--color-text-danger);flex-shrink:0"></span>
      {FLAG_TEXT}
    </p>
  </div>

  <!-- Suggested talking points -->
  <div style="background:var(--color-background-primary);border:0.5px solid var(--color-border-tertiary);border-radius:var(--border-radius-lg);padding:1rem 1.25rem">
    <p style="font-weight:500;font-size:14px;margin:0 0 8px;color:var(--color-text-primary)">Suggested talking points</p>
    <!-- Repeat for each point -->
    <p style="font-size:13px;color:var(--color-text-secondary);margin:4px 0;display:flex;align-items:baseline;gap:8px">
      <span style="color:var(--color-text-info);font-weight:500;flex-shrink:0">{N}.</span>
      {TALKING_POINT}
    </p>
  </div>
</div>
```

### Rating badge colors
- **Positive**: `var(--color-text-success)` background
- **Negative**: `var(--color-text-danger)` background
- **Neutral**: `var(--color-text-warning)` background

### LOMG stage badge colors
- **Land**: `var(--color-background-warning)` / `var(--color-text-warning)`
- **Onboard**: `var(--color-background-info)` / `var(--color-text-info)`
- **Manage**: `var(--color-background-success)` / `var(--color-text-success)`
- **Grow**: Use purple — `background:#EEEDFE;color:#534AB7`

### Widget title
Use `company_meeting_prep` as the widget title (snake_case, specific to this company).

### Important
- Always call `show_widget` with `read_me` first if this is the first widget in the conversation.
- Populate every section with real data — never use placeholder values.
- If a section has no data (e.g., no feedback), show "No feedback submitted yet" instead of hiding the section.
- Keep talking points specific and actionable based on the actual data — don't use generic advice.

## Context: CloudRadial LOMG Framework

This lookup supports the Land, Onboard, Manage, Grow (LOMG) lifecycle. When presenting results, frame them in terms of where the client is in their journey:

- **Land**: Company exists but minimal setup — few users, no articles, no endpoints
- **Onboard**: Active implementation — articles being created, users being added, catalogs being configured
- **Manage**: Operational portal — consistent endpoint count, regular feedback, published articles
- **Grow**: Mature usage — courses deployed, assessments running, high user engagement
