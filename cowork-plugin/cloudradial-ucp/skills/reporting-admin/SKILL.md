---
name: reporting-admin
description: >
  Access CloudRadial archives, certificates, company groups, media files, quickstarts,
  replacement tokens, and raw API calls. Use when the user says "archived reports",
  "certificates", "company groups", "media files", "tokens", "company tokens",
  "replacement tokens", "set the @SupportPhone token", "manage tokens", "raw API call",
  "quickstart guides", "bulk export", "cross-company report", or needs to access
  archive items, certificates, company groupings, media management, token values,
  or make advanced raw API calls not covered by other skills.
metadata:
  version: "1.0.0"
---

# Reporting & Administration

Access archives, certificates, company groups, media, tokens, and advanced API operations across CloudRadial portals.

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

## Resource Types

### archive_item
Archived reports and documents. Key fields: `companyReportItemId`, `companyReportFolderId`, `companyId`, `subject`, `text`, `dateUploaded`.

**Note:** archive_item is a composite-key resource. Getting a specific item requires both `archive_id` (the folder) and `id` (the item).

### certificate
Certificates tracked in the portal. Key fields: `id` (the certificate's ID), `companyId`, `companyDomainId`, `name`, `url`, `expirationDate`, `issuer`, `isValid`, `thumbprint`. Creating one requires `companyId`, `name` and `url`.

### company_group
Logical groupings of companies. Key fields: `companyGroupId`, `group` (the group's name; there is no `name` or `description`), `partnerId`. Create with `data: { group: "Managed Plus" }`. Membership lives in `company_group_company` (`companyGroupId`, `companyId`).

### quickstart
Quickstart guides on a company's portal home page. Key fields: `quickstartId`, `companyId`, `subject` (NOT `name`), `description`, `category`, `body` (HTML), `icon`, `iconColor`, `datePublished`, `isText`. Creating one requires `companyId`, `subject`, `description`, `category`, `icon`, `iconColor`, `datePublished` and `isText`.

### media
Media files (images, documents) stored in the portal. Key fields: `partnerMediaId` (the media file's ID), `originalName`, `contentType`, `description`, `length`, `width`, `height`, `viewToken`. Create with `create_resource` and `data: { originalName, data (base64), length, width, height, contentType, description }`; `width` and `height` are required, so use 0 for non-images.

### token
**Replacement tokens**, not API keys: the named values (like `@SupportPhone`) that portal forms, articles and automations fill in. A token lives at partner level (`companyId` 0) or on one company, and a company token overrides the partner token of the same name. Manage them with `manage_tokens`. Token names are case-sensitive.

## Example Calls

**List archived reports for a company:** Call `list_resources` with `resource_type: "archive_item"`, `filter: "companyId eq 42"`.

**Get a specific archive item (requires both IDs):** Call `get_resource` with `resource_type: "archive_item"`, `archive_id: "10"`, `id: "55"`.

**List certificates for a company:** Call `list_resources` with `resource_type: "certificate"`, `filter: "companyId eq 42"`.

**List company groups:** Call `list_resources` with `resource_type: "company_group"`.

**List quickstart guides:** Call `list_resources` with `resource_type: "quickstart"`.

**List media files:** Call `list_resources` with `resource_type: "media"`.

### Token Management

The `manage_tokens` tool reads and writes replacement tokens. Leave `company_id` out (or 0) for partner-level tokens.

**List partner-level tokens:** Call `manage_tokens` with `action: "list"`.

**List one company's tokens:** Call `manage_tokens` with `action: "list"`, `company_id: 42`.

**Set a token (creates or updates):** Call `manage_tokens` with `action: "create"`, `company_id: 42`, `token_name: "SupportPhone"`, `value: "555-0100"`. Confirm the value with the user first: every form, article and automation using `@SupportPhone` for that company changes.

**Delete a token:** Call `manage_tokens` with `action: "revoke"`, `company_id: 42`, `token_name: "SupportPhone"`. The partner-level token of the same name, if any, applies again.

**Never create a token whose name matches a predefined token** such as `UserEmail`, `CompanyName` or `TicketId`. The predefined value always wins.

### Raw API Calls

For advanced operations not covered by the standard tools, use `raw_api_call` to hit any CloudRadial API endpoint directly.

**GET example:** Call `raw_api_call` with `method: "GET"`, `path: "/v2/odata/company/$count"`.

**GET example with query params:** Call `raw_api_call` with `method: "GET"`, `path: "/v2/odata/company"`, `query: { "$top": 5, "$select": "companyId,name" }`.

**POST example with a body:** Call `raw_api_call` with `method: "POST"`, `path: "/v2/companygroup"`, `body: { "group": "Managed Plus" }`. Confirm any write with the user first.

A raw `PATCH` body must be a JSON Patch array (`[{ "op": "replace", "path": "/name", "value": "Contoso Ltd" }]`); `update_resource` builds that for you, so prefer it.

## API Reference

For exact field names and schema details, read `${CLAUDE_PLUGIN_ROOT}/references/api-reference.md`.

## Workflows

### Certificate Expiration Report

1. List certificates for a company (or all companies), paging with `top: "200"` and `skip`
2. Check `expirationDate` against the current date
3. Flag certificates expiring within 30/60/90 days, and any where `isValid` is false
4. Present as a prioritized action list

### Archive Report History

1. List archive items for a company with `orderby: "dateUploaded desc"`
2. Note subjects and dates to understand reporting history
3. Get specific items for detailed content (`archive_id` = `companyReportFolderId`, `id` = `companyReportItemId`)

### Company Group Overview

1. List all company groups (`resource_type: "company_group"`); the group's name is in `group`
2. List memberships with `resource_type: "company_group_company"` (filter `companyGroupId eq <id>` for one group)
3. Join `companyId` to the company list and present group membership, including companies in no group
