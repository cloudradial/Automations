---
name: service-management
description: >
  Manage CloudRadial services, service installations, domains, and products. Use when the
  user says "list services", "check service installs", "what services does [company] have",
  "domain list", "managed domains", "products", "service catalog details",
  "what's installed for [company]", or needs to review, create, or manage services,
  service installations, domains, or products in CloudRadial portals.
metadata:
  version: "1.0.0"
---

# Service Management

Review and manage services, service installations, domains, and products across CloudRadial portals.

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

### service
Services tracked for a company. Key fields: `serviceId`, `companyId`, `name`, `description`, `category`. Creating one requires `companyId` and `name`.

### service_install
Links a service to an endpoint: which endpoints have the service, and in what state. Key fields: `endpointId` (the endpoint's `companyEndpointId`), `serviceId`, `status`, `startupType`, `fullVersion`, `version`, `major`, `minor`. There is no install ID and no `companyId`: the key is `endpointId` + `serviceId`. To scope installs to a company, list the company's endpoints first and filter installs on their IDs.

### domain
Managed domains tracked in the portal. Key fields: `companyDomainId` (the domain's ID), `companyId`, `name`, `registrar`, `hostingCompany`, `dateExpires`, `isVerified`, `isOffice365`, `isDefault`. Creating one requires `companyId` and `name`. Pass `company_id` to `get_resource`, `update_resource` and `delete_resource` for a domain (the tool looks it up if you leave it out).

### product
A Planner (roadmap) item: a recommended project, purchase or recurring service on a company's IT roadmap, not a catalog of things for sale. Key fields: `productId`, `companyId`, `subject` (the item's title), `summary`, `body` (HTML), `category`, `productCategoryId`, `status`, `priority`, `scheduledQuarter`, `monthlyUnits`, `monthlyUnitPrice`, `projectUnits`, `projectUnitPrice`. Creating one requires `companyId`, `subject`, `summary`, `body`, `category`, `productCategoryId`, `datePublished`, `isRequired` and `isShowPrice`. The client-deliverable skill covers building Planner items.

## Example Calls

**List services for a company:** Call `list_resources` with `resource_type: "service"`, `filter: "companyId eq 42"`.

**List service installs for one endpoint:** Call `list_resources` with `resource_type: "service_install"`, `filter: "endpointId eq 789"`.

**List service installs for a company:** List the company's endpoints (`resource_type: "endpoint"`, `filter: "companyId eq 42"`, `select: "companyEndpointId,name"`), then call `list_resources` with `resource_type: "service_install"`, `filter: "endpointId eq 789 or endpointId eq 790 ..."` (about 40 IDs per call).

**List domains for a company:** Call `list_resources` with `resource_type: "domain"`, `filter: "companyId eq 42"`.

**List Planner items for a company:** Call `list_resources` with `resource_type: "product"`, `filter: "companyId eq 42"`.

## API Reference

For exact field names and schema details, read `${CLAUDE_PLUGIN_ROOT}/references/api-reference.md`.

## Workflows

### Service Coverage for a Company

1. List the company's services with `list_resources` / `resource_type: "service"`, `filter: "companyId eq 42"`
2. List the company's endpoints, then the service installs for those endpoint IDs (see Example Calls)
3. Cross-reference to see which endpoints have each service, and flag endpoints missing a service or with a stopped `status`
4. Summarize: services tracked, endpoints covered per service, coverage percentage

### Domain Expiration Report

1. List domains filtered by companyId (or all domains) — `list_resources` with `resource_type: "domain"`
2. Check `dateExpires` against the current date
3. Flag domains expiring within 30/60/90 days
4. Present as a prioritized list

### Cross-Company Service Audit

1. List all companies, then for each company its services and endpoints (paginate with `top: "200"` and `skip` until a short page)
2. List service installs for each company's endpoint IDs
3. Group by company and compare against that company's service list
4. Identify companies with low service coverage
5. Present as a gap analysis
