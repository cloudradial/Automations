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
| `get_resource` | Retrieve one resource by ID | `resource_type`, `id` |
| `create_resource` | Create a new resource | `resource_type`, `data` |
| `update_resource` | PUT (full) or PATCH (partial) update | `resource_type`, `id`, `data` |
| `delete_resource` | Delete by ID | `resource_type`, `id` |
| `user_lookup` | Find users by email, name, or company | one of `email`/`name`/`company_id` |
| `manage_tokens` | List, get, set or delete replacement tokens (the @Token values forms and automations fill in), partner-level or per company. Not API keys. | `action` |
| `endpoint_update_warranty` | Trigger async warranty refresh by endpoint serial number | `serial_number` |
| `courseenrollment_complete` | Mark a course enrollment completed (optional score/comment) | `enrollment_id` |
| `courseenrollment_for_user` | Get a user's enrollment record for a specific course | `course_id`, `user_id` |
| `raw_api_call` | Direct API call for advanced cases | `path` |

### OData parameter conventions

For `list_resources` and `count_resources`, pass OData parameters **without** the leading `$`: `filter`, `select`, `orderby`, `top`, `skip`, `expand`, `search`. The server adds the `$` when forwarding. Defaults to `top=100` if unspecified (pagination by default to avoid hammering the API). Max page is 200; walk through larger pages by incrementing `skip`.

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

### endpoint
Managed devices/endpoints. Key fields: `endpointId`, `companyId`, `name`, `operatingSystem`, `warrantyExpirationDate`, `lastSeen`, `manufacturer`, `model`, `serialNumber`.

### endpoint_application
Applications installed on endpoints. Key fields: `endpointApplicationId`, `endpointId`, `name`, `version`, `publisher`.

### endpoint_custom_property
Custom properties attached to endpoints. Key fields: `endpointCustomPropertyId`, `endpointId`, `name`, `value`.

## Example Calls

**List endpoints for a company:** Call `list_resources` with `resource_type: "endpoint"`, `filter: "companyId eq 42"`.

**Count endpoints for a company:** Call `count_resources` with `resource_type: "endpoint"`, `filter: "companyId eq 42"`.

**Get a specific endpoint:** Call `get_resource` with `resource_type: "endpoint"`, `id: "789"`.

**List applications on an endpoint:** Call `list_resources` with `resource_type: "endpoint_application"`, `filter: "endpointId eq 789"`.

**List custom properties for an endpoint:** Call `list_resources` with `resource_type: "endpoint_custom_property"`, `filter: "endpointId eq 789"`.

## API Reference

For exact field names and schema details, read `${CLAUDE_PLUGIN_ROOT}/references/api-reference.md`.

## Workflows

### Endpoint Inventory for a Company

1. Count endpoints filtered by companyId
2. List endpoints with key fields: `select=endpointId,name,operatingSystem,manufacturer,model,