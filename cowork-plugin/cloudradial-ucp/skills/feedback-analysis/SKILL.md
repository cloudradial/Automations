---
name: feedback-analysis
description: "Analyze, log, update, move and delete CloudRadial portal feedback and user satisfaction data. Use when the user says \"update feedback\", \"change the feedback rating\", \"fix a feedback entry\", \"move feedback to another company\", \"log feedback\", \"add a feedback entry\", \"delete feedback\", or \"check feedback\", \"CSAT\", \"satisfaction\", \"what feedback has [company] submitted\", \"recent feedback\", \"feedback report\", \"are users happy\", \"NPS\", \"survey results\", or needs to list, review, or analyze feedback entries from CloudRadial portals.\n"
metadata:
  version: "1.0.0"
---

# Feedback Analysis

List, analyze, create, update, move and delete user feedback and satisfaction data across CloudRadial portals. Updating feedback is one of the most common requests, so handle it end to end.

## How to Call the API

All CloudRadial work goes through MCP tools served by the `cloudradial-ucp` server. The plugin auto-registers the server via `.mcp.json`: no Azure Function, no Chrome extension, no local config file.

### Before any tool call

Call `setup_status` first to confirm credentials are stored. If it returns `configured: false`, defer to the `setup` skill before doing CloudRadial work.

### Available MCP tools

| Tool | Purpose | Required args |
|------|---------|---------------|
| `setup_status` | Check credential state (never returns the keys) | None |
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
- `archive_item` composite key: pass `archive_id` and `id`.
- `service_install` composite key: pass `endpoint_id` and `service_id` (or `id = serviceId` on update/delete).
- `endpoint_custom_property`: get/create/update/delete take `serial_number` and `property_name`; list with `filter: "companyEndpointId eq <id>"`.
- OData returns enum fields as names (for example `enclosure: "Desktop"`), not numbers.

### Errors

- **"credentials not configured"** → defer to the `setup` skill.
- **401/403 from CloudRadial** → stored credentials are invalid. Run `setup` to rotate.
- **404** → resource not found. Verify the ID, and for `catalog_question`, `course_lesson`, `domain`, `user`, `application_user` and `token` pass `company_id`.
- Every HTTP 4xx/5xx comes back as a tool error, not as data. Read the message and fix the call instead of retrying it unchanged.

## Resource Type: feedback

User feedback and CSAT entries, usually one per rated ticket. Key fields: `feedbackId`, `companyId`, `companyName`, `userId`, `userEmail`, `userFirstName`, `userLastName`, `feedbackRating`, `feedbackRatingNumber`, `feedbackComment`, `feedbackWantsFollowUp`, `sentiment`, `source`, `ticketPsaId`, `ticketSubject`, `agentFirstName`, `agentLastName`, `dateCreated`.

- `feedbackRating` is an enum (spec values 1, 0, -1); OData returns its name, not the number. Check the names in the rows you get before grouping on them.
- `feedbackRatingNumber` is the numeric rating; use it for averages.
- There is no category field. Group by `source` (where the feedback came from, an enum name), by agent, or by themes in `feedbackComment` and `ticketSubject`.

## Example Calls

**List feedback for a company:** Call `list_resources` with `resource_type: "feedback"`, `filter: "companyId eq 42"`.

**Recent feedback (sorted newest first):** Call `list_resources` with `resource_type: "feedback"`, `filter: "companyId eq 42"`, `orderby: "dateCreated desc"`, `top: "10"`.

**Count feedback entries:** Call `count_resources` with `resource_type: "feedback"`, `filter: "companyId eq 42"`.

**Get a specific feedback entry:** Call `get_resource` with `resource_type: "feedback"`, `id: "567"`.

**Feedback where the user asked for a follow-up:** Call `list_resources` with `resource_type: "feedback"`, `filter: "companyId eq 42 and feedbackWantsFollowUp eq true"`.

## Writing Feedback

Create, update (including moving to another company) and delete all work through the API. Tested on a live portal.

**Find the entry first.** Users describe feedback by person, ticket or date, not by ID. Search with `list_resources`, for example `filter: "companyId eq 42 and ticketPsaId eq 123456"`, `filter: "userEmail eq 'sam@contoso.com'"`, or `orderby: "dateCreated desc"`. Show the matching rows (date, user, ticket, rating, comment) and confirm which `feedbackId` to change before writing. If more than one row matches, ask.

**Update an entry:** Call `update_resource` with `resource_type: "feedback"`, `id: "<feedbackId>"` and only the fields that change, for example `data: { feedbackRating: "Positive", feedbackRatingNumber: 5, feedbackComment: "..." }`. PATCH keeps the fields you leave out. Read the entry back with `get_resource` and show the before and after.
- `feedbackRating` accepts the names `Positive`, `Neutral` and `Negative` (`Positive` is saved as 1). Any other value fails with HTTP 400 "Invalid patch data".
- Keep `feedbackRating`, `feedbackRatingNumber` and `sentiment` consistent so CSAT reports don't contradict themselves. On rows with a star score, `sentiment` equals `feedbackRatingNumber` (1 to 5); thumbs-only rows have 0 in both. Copy the pattern from existing rows on the same portal.

**Move an entry to another company:** Update `companyId` to the target company. CloudRadial updates `companyName` and `companyPsaId` to match on its own, so don't send them. Read the entry back to confirm. (Rows left behind by deleted companies keep their old name; that's a different case.)

**Create an entry:** Call `create_resource` with `resource_type: "feedback"`. `companyId` and `sentiment` are required; add `userEmail`, `userFirstName`, `userLastName`, `ticketPsaId`, `ticketSubject`, `feedbackRating`, `feedbackRatingNumber`, `feedbackComment` and `feedbackWantsFollowUp` as the user gives them. `companyName` and `companyPsaId` are filled in from the company. Use it for feedback collected outside the portal (phone, email, a migrated survey tool).

**Delete an entry:** Call `delete_resource` with `resource_type: "feedback"`, `id`. Always confirm with the user first and name the entry (date, user, ticket). Deleting removes it from CSAT history.

**Bulk changes:** For more than a few entries, list the rows that will change in a table, get one approval for the batch, then update one at a time and report each result (updated / failed with the error).

## API Reference

For exact field names and schema details, read `${CLAUDE_PLUGIN_ROOT}/references/api-reference.md`.

## Workflows

### Feedback Review for a Company

1. List feedback filtered by companyId, sorted by `dateCreated desc`
2. Note `feedbackRating`, `feedbackRatingNumber` and `feedbackComment`
3. Calculate the average `feedbackRatingNumber`
4. Highlight negative feedback, common complaints, and entries with `feedbackWantsFollowUp` true
5. Summarize: total feedback count, average rating, recent trends, actionable items

### Satisfaction Trend Analysis

1. List all feedback for a company over time (page with `top: "200"` and `skip` until a short page)
2. Group by month or quarter of `dateCreated`
3. Track rating trends: improving, declining, or stable
4. Identify agents or recurring ticket themes with consistently low ratings
5. Present as a trend summary

### Cross-Company Satisfaction Report

1. List all feedback across companies (paginate until a page returns fewer rows than `top`)
2. Group by `companyId` (`companyName` is on each row)
3. Calculate average `feedbackRatingNumber` per company
4. Flag companies with no feedback (disengaged) or low ratings (at risk)
5. Rank companies by satisfaction level
6. Present as a summary useful for QBR prep or account reviews
