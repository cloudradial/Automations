# CloudRadial UCP MCP Server

An MCP (Model Context Protocol) server that exposes the CloudRadial API V2 as tools for Claude Desktop, Claude Code, and other MCP clients. Distributable to CloudRadial Partners — no Azure deployment required. The partner runs the server locally; their CloudRadial API keys never leave their machine.

## Available Tools

| Tool | What it does |
|------|--------------|
| `search_companies` | Search companies by partial name |
| `company_overview` | Snapshot of a company: details + user/endpoint counts + recent articles/feedback |
| `list_resources` | List any of 30 resource types with OData filtering, sorting, pagination |
| `count_resources` | Count a resource type with an optional filter |
| `get_resource` | Retrieve a single resource by ID (incl. composite keys) |
| `create_resource` | Create a new resource |
| `update_resource` | Update a resource: PATCH (default) changes only the fields given; PUT replaces the whole record |
| `delete_resource` | Delete a resource by ID |
| `user_lookup` | Find users by email, name, or company |
| `manage_tokens` | List / get / create / revoke replacement tokens (like @SupportPhone), not API keys |
| `endpoint_update_warranty` | Trigger an async warranty refresh for an endpoint by serial number |
| `courseenrollment_complete` | Mark a course enrollment as completed (with optional score/comment) |
| `courseenrollment_for_user` | Get a user's enrollment record for a specific course (null if not enrolled) |
| `assessment_import` | Create or refresh an assessment from questions or an .xlsx (through the upload; the API has no other create) |
| `raw_api_call` | Direct API call for advanced/custom use cases |

Plus `setup_status`, `configure_credentials`, `clear_credentials` for credential management.

Every tool returns an MCP error when CloudRadial answers with an HTTP error, with the status and CloudRadial's message.

Supported resource types (30): `company`, `user`, `application_user`, `article`, `endpoint`, `catalog`, `catalog_question`, `assessment`, `feedback`, `service`, `service_install`, `domain`, `course`, `course_enrollment`, `course_lesson`, `course_lesson_history`, `menu`, `product`, `archive_item`, `certificate`, `company_group`, `company_group_company`, `quickstart`, `flexible_asset`, `flexible_asset_type`, `flexible_asset_field`, `endpoint_application`, `endpoint_custom_property`, `media`, `token`.

Composite-key resources need extra args on `get_resource` / `update_resource` / `delete_resource`:

| Resource | Required args |
|----------|---------------|
| `archive_item` | `archive_id` + `id` |
| `service_install` | `endpoint_id` + `service_id` (or `id`=serviceId on update/delete) |
| `company_group_company` | `company_group_id` + `company_id` (create/delete only — no update) |
| `course_lesson_history` | `course_id` + `application_user_id` + `course_lesson_id` |
| `endpoint_custom_property` | `serial_number` + `property_name` (create: `serial_number`, data `{name, value, dataType}`) |

`application_user` has no OData endpoint — use `get_resource` / `create_resource` / `update_resource` / `delete_resource` by id only.

Some single-item endpoints are scoped by company: `catalog_question`, `course_lesson`, `course_lesson_history`, `domain`, `user`, `application_user` and `token`. Pass `company_id`, or let the tool look it up (all but `course_lesson_history` and `token`).

What the API can't do, so the tools refuse with a reason: update or delete an `assessment` (use `assessment_import`), update or delete a `flexible_asset_field`, delete a `course_enrollment`, or PUT a `flexible_asset`, `flexible_asset_type` or `course_enrollment`. `get_resource` reads `assessment` and `course_enrollment` through OData by id. To update a `flexible_asset`, pass the complete traits object as `data.traits`; keys you leave out are removed.

## Tests

```bash
npm test
```

Runs the tools against a mocked CloudRadial API (no keys or network needed) and checks that no skill file is cut off or corrupted.

## Install

### Prerequisites

- Node.js 18+
- CloudRadial API V2 keys (public + private). Generate them under **Account Setup → API Tokens** in your CloudRadial portal.

### Option A — Run from npm (recommended for partners)

Once published, partners add the server to their MCP client config with a single block. No clone, no build.

**Claude Desktop** — edit `claude_desktop_config.json` (Settings → Developer → Edit Config):

```json
{
  "mcpServers": {
    "cloudradial-ucp": {
      "command": "npx",
      "args": ["-y", "@cloudradial/ucp-mcp"],
      "env": {
        "CLOUDRADIAL_PUBLIC_KEY": "your-public-key",
        "CLOUDRADIAL_PRIVATE_KEY": "your-private-key",
        "CLOUDRADIAL_BASE_URL": "https://api.us.cloudradial.com"
      }
    }
  }
}
```

**Claude Code** — `claude mcp add cloudradial-ucp -- npx -y @cloudradial/ucp-mcp` (and set the three env vars in your shell or `.env`).

### Option B — Run from source

```bash
git clone https://github.com/cloudradial/helpers
cd helpers/cowork-plugin/cloudradial-ucp-mcp
npm install
npm run build
```

Then point your MCP client at the built entry:

```json
{
  "mcpServers": {
    "cloudradial-ucp": {
      "command": "node",
      "args": ["/absolute/path/to/cloudradial-ucp-mcp/dist/index.js"],
      "env": {
        "CLOUDRADIAL_PUBLIC_KEY": "your-public-key",
        "CLOUDRADIAL_PRIVATE_KEY": "your-private-key"
      }
    }
  }
}
```

## Environment Variables

| Variable | Required | Default |
|----------|----------|---------|
| `CLOUDRADIAL_PUBLIC_KEY`  | yes | — |
| `CLOUDRADIAL_PRIVATE_KEY` | yes | — |
| `CLOUDRADIAL_BASE_URL`    | no  | `https://api.us.cloudradial.com` |

The server authenticates to CloudRadial with HTTP Basic auth (`public:private`, base64). Keys live in your MCP client config or local environment — they are never transmitted anywhere except CloudRadial's API.

## Example Prompts

- "Look up Acme Corp in CloudRadial"
- "Give me an overview of company 42 before my meeting"
- "How many endpoints does company 42 have?"
- "Create a KB article for company 42 about password resets"
- "Find all users at Contoso whose email contains 'admin'"
- "List all out-of-warranty endpoints"

## Notes

- **OData pagination caps at 200.** The CloudRadial API returns at most 200 results per page. Use `top` and `skip` to paginate.
- **Field-name quirks.** Articles use `subject` (not `title`); courses use `name` (not `title`). The tool descriptions are loose — pass exactly what the API expects.
- **Composite-key resources.** `archive_item` needs both `archive_id` and `id`; `service_install` needs both `endpoint_id` and `service_id` (or `id` = serviceId on update/delete).

## Relationship to the Cowork Plugin

The sibling [`cloudradial-ucp/`](../cloudradial-ucp) directory contains a Cowork plugin that talks to CloudRadial through a partner-deployed Azure Function proxy. This MCP server is an alternative distribution that ports the same 11 operations to native MCP, eliminating the Azure Function deployment step for partners who use an MCP-capable client.

## License

MIT
