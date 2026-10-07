---
name: endpoint-reporting
description: >
  Report on and analyze CloudRadial endpoints (managed devices). Use when the user says
  "list endpoints", "endpoint report", "warranty report", "how many devices",
  "check endpoints for [company]", "device inventory", "which endpoints are out of warranty",
  "endpoint applications", "endpoint custom properties", or needs to review, count, or
  analyze managed devices and their properties across CloudRadial portals.
metadata:
  version: "1.0.0"
---

# Endpoint Reporting

List, count, and analyze managed endpoints (devices) across CloudRadial portals using the CloudRadial MCP server.

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

### endpoint
Managed devices/endpoints. Key fields: `companyEndpointId` (the endpoint's ID), `companyId`, `name`, `os`, `osVersion`, `expirationDate` (warranty end, nullable), `lastCheckIn`, `manufacturer`, `model`, `serialNumber`, `isServer`, `isVirtual`, `enclosure`. OData returns `enclosure` and `windows11Readiness` as names (for example `"Desktop"`), not numbers.

### endpoint_application
Applications installed on endpoints. Key fields: `endpointApplicationId`, `endpointId` (the endpoint's `companyEndpointId`), `companyId`, `name`, `publisher`, `display`, `major`, `minor`, `version`, `installDate`.

### endpoint_custom_property
Custom properties attached to endpoints. Key fields: `endpointCustomPropertyId`, `companyEndpointId`, `serialNumber`, `name`, `value`, `dataType`. There is no `companyId` on this entity: filter on `companyEndpointId` (OR several IDs together in one filter for a batch). Endpoints with no custom properties never appear here, so start from the endpoint list, not this one. Get, create, update and delete one property with `serial_number` and `property_name` (create: `data: { name, value, dataType }`).

## Example Calls

**List endpoints for a company:** Call `list_resources` with `resource_type: "endpoint"`, `filter: "companyId eq 42"`.

**Count endpoints for a company:** Call `count_resources` with `resource_type: "endpoint"`, `filter: "companyId eq 42"`.

**Get a specific endpoint:** Call `get_resource` with `resource_type: "endpoint"`, `id: "789"` (the `companyEndpointId`).

**List applications on an endpoint:** Call `list_resources` with `resource_type: "endpoint_application"`, `filter: "endpointId eq 789"`.

**List custom properties for an endpoint:** Call `list_resources` with `resource_type: "endpoint_custom_property"`, `filter: "companyEndpointId eq 789"`.

**Read one custom property:** Call `get_resource` with `resource_type: "endpoint_custom_property"`, `serial_number: "<serial>"`, `property_name: "AssetTag"`.

## API Reference

For exact field names and schema details, read `${CLAUDE_PLUGIN_ROOT}/references/api-reference.md`.

## Workflows

### Endpoint Inventory for a Company

1. Count endpoints filtered by companyId with `count_resources`
2. List endpoints with key fields — `list_resources` with `resource_type: "endpoint"`, `filter: "companyId eq 42"`, `select: "companyEndpointId,name,os,manufacturer,model,lastCheckIn"`
3. Paginate with `top: "200"` and `skip` until a page returns fewer than 200 rows
4. Summarize: total count, OS distribution, manufacturer breakdown, and devices whose `lastCheckIn` is old (their data may be stale)

### Warranty Expiration Report

1. List endpoints for a company with warranty fields — `select: "companyEndpointId,name,serialNumber,expirationDate,manufacturer,model"`
2. Group by warranty status: expired, expiring within 30/60/90 days, current, unknown (blank `expirationDate`)
3. Flag critical items (expired or expiring soon)
4. Present as a prioritized list with counts per category
5. To refresh warranty data for a specific endpoint, call `endpoint_update_warranty` with its `serial_number` (async — CloudRadial fetches in the background)

A filter such as `expirationDate lt 2026-06-01T00:00:00Z` narrows the list server-side; if the API rejects it, pull the rows and compare dates client-side. Blank `expirationDate` means unknown, not expired.

### Application Audit

1. Identify the target endpoint(s) and their `companyEndpointId`
2. List `endpoint_application` records filtered by endpointId — `list_resources` with `resource_type: "endpoint_application"`, `filter: "endpointId eq 789"`
3. Group by publisher or application name
4. Flag outdated versions or unauthorized software if criteria are provided

### Custom Property Review

1. List the company's endpoints and collect their `companyEndpointId` values
2. List `endpoint_custom_property` with `filter: "companyEndpointId eq 789 or companyEndpointId eq 790 ..."` (about 40 IDs per call)
3. Group the rows by `companyEndpointId` and join them back to the endpoint list; endpoints with no rows have no custom properties

### Cross-Company Endpoint Summary

1. List all companies with `list_resources` / `resource_type: "company"`
2. For each company, count endpoints with `count_resources`
3. Flag companies with zero endpoints (not onboarded) or unusually high/low counts
4. Present as a ranked summary
