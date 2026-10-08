---
name: company-management
description: >
  Manage CloudRadial companies — create, update, delete, and organize them into groups.
  Use when the user says "list all companies", "create a new company", "add a company",
  "update company settings", "change account manager", "set portal branding",
  "company groups", "add company to group", "remove company from group",
  "audit company settings", "which companies have no logo", "compare companies",
  "cross-company report", "how many companies do I have", or needs to create, modify,
  organize, or audit companies across their CloudRadial portal. Also use when the user
  wants to manage company-level settings like messaging, branding, territory, or
  delegated admin status.
metadata:
  version: "1.0.0"
---

# Company Management

Create, update, organize, and audit companies across a CloudRadial portal.

## How to Call the API

All CloudRadial work goes through MCP tools served by the `cloudradial-ucp` server. The plugin auto-registers the server via `.mcp.json`.

### Before any tool call

Call `setup_status` first to confirm credentials are stored. If it returns `configured: false`, defer to the `setup` skill.

### Key MCP tools for this skill

| Tool | Purpose | Required args |
|------|---------|---------------|
| `search_companies` | Find companies by partial name | `name` |
| `company_overview` | Full snapshot: details, user/endpoint counts, recent articles + feedback | `company_id` |
| `list_resources` | List companies, company groups, or group memberships with OData filtering | `resource_type` |
| `count_resources` | Count any resource type | `resource_type` |
| `get_resource` | Get a single company by ID | `resource_type: "company"`, `id` |
| `create_resource` | Create a company, group, or group membership | `resource_type`, `data` |
| `update_resource` | Update company settings. PATCH by default: send only the fields to change | `resource_type`, `id`, `data` |
| `delete_resource` | Delete a company, group, or group membership | `resource_type`, `id` |

### OData conventions

Pass OData parameters **without** the leading `$`: `filter`, `select`, `orderby`, `top`, `skip`. Defaults to `top=100`. Max page is 200 and there's no next-page link, so keep incrementing `skip` until a page comes back shorter than `top`.

### Errors

- **"credentials not configured"** → defer to `setup` skill.
- **401/403** → stored credentials are invalid. Run `setup` to rotate.
- **404** → resource not found. Verify the ID, and for `catalog_question`, `course_lesson`, `domain`, `user`, `application_user` and `token` pass `company_id`.
- Every HTTP 4xx/5xx comes back as a tool error, not as data. Read the message and fix the call instead of retrying it unchanged.

## Resource Types

### company

The core resource. These are the only fields the API accepts on create and update:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Company display name (required on create) |
| `partnerId` | string | Parent partner ID |
| `psaKey` | int | PSA numeric key |
| `psaIdentifier` | string | PSA system identifier |
| `territory` | string | Sales territory or region |
| `accountManager` | string | Assigned account manager name |

**Portal-only settings:** branding (logo, theme color), messaging (digest and direct messages), feature sets and delegated admin can't be set through the API. `get_resource` may return some of them, but they aren't in the API spec, so treat them as hints and have the user check or change them in the portal.

Fields available via `list_resources` (OData, more limited):

| Field | Type | Description |
|-------|------|-------------|
| `companyId` | int | Unique identifier |
| `name` | string | Company display name |
| `agentFileName` | string | Data agent executable filename |
| `psaIdentifier` | string | PSA system identifier |
| `psaKey` | int | PSA numeric key |
| `endpointCount` | int | Number of managed endpoints |

For more detail (territory, account manager), use `get_resource` with the company ID — the OData listing only returns the limited field set.

### company_group

Groups for organizing companies. Fields: `companyGroupId`, `group` (the group name), `partnerId`.

### company_group_company

Membership records linking companies to groups. This is a **composite-key resource** — use `company_group_id` + `company_id` for get/delete operations.

Fields: `companyGroupId`, `companyId`, `partnerId`.

## Workflows

### List all companies

1. Call `list_resources` with `resource_type: "company"` to get names, IDs, and endpoint counts.
2. For full detail on any specific company, follow up with `get_resource` for that company ID.

### Create a new company

1. Call `create_resource` with `resource_type: "company"` and `data` containing at minimum `name`.
2. Optional fields: `territory`, `accountManager`, `psaKey`, `psaIdentifier`, `partnerId`. Branding and messaging are set in the portal afterwards.
3. After creation, the company will need users added and content seeded — suggest the user follow up with the portal-setup skill.

### Update company settings

1. Look up the company (by name via `search_companies` or by ID).
2. Call `update_resource` with `resource_type: "company"`, `id`, and `data` containing only the fields to change. The default method is PATCH, so fields you leave out are kept. Only use `method: "PUT"` with every field filled in, because PUT clears whatever you leave out.
3. Common updates: changing `accountManager` or `territory`, or fixing the PSA identifiers. For logo, theme color or messaging settings, tell the user to change them in the portal.

### Manage company groups

**List groups:** `list_resources` with `resource_type: "company_group"`.

**Create a group:** `create_resource` with `resource_type: "company_group"` and `data: {"group": "Group Name"}`.

**Add a company to a group:** `create_resource` with `resource_type: "company_group_company"` and `data: {"companyGroupId": <id>, "companyId": <id>}`.

**Remove a company from a group:** `delete_resource` with `resource_type: "company_group_company"`, `company_group_id`, and `company_id`.

**List companies in a group:** `list_resources` with `resource_type: "company_group_company"` and `filter: "companyGroupId eq <id>"`.

### Cross-company audit

To audit settings across all companies:

1. List all companies via `list_resources`.
2. For each company, call `get_resource` to get the full detail.
3. Compare settings and flag inconsistencies:
   - Companies with no account manager or territory assigned
   - Companies with no PSA identifier (not linked to the PSA)
   - Companies with zero endpoints (no device sync)
4. Branding (logo, theme color) and messaging can't be verified through the API. List them as checks for the user to do in the portal rather than reporting them as missing.

### Visual presentation

When presenting company lists, cross-company audits, or group memberships, use `show_widget` to render a visual card. Follow the same layout patterns as the portal-lookup skill:

- Header with title and count
- Stats row for summary numbers
- Table for company details
- Flags for issues found
- Use CSS variables for all colors

Widget title: `company_management_report` (snake_case).
