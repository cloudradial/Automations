# CloudRadial UCP Plugin for Claude

Connect Claude to your CloudRadial UCP Portal. Once it's installed, just ask Claude in plain English — look up companies, build training courses, create assessments, refresh device warranty info, and manage 30+ other CloudRadial resource types. No scripts, no separate server to deploy, no copy-pasting API keys around.

## Install — start here

You install this once **for each Claude app you use** (Cowork, Claude Code, or Claude Desktop). The good news: you enter your CloudRadial keys only **once per computer** — they're stored securely on your computer and shared automatically with every Claude app on that machine.

> **Requirement:** Node.js must be installed and on your PATH. The plugin runs its MCP server locally by launching `node` — there's nothing to host and no service to deploy.

### Step 1 — Install the plugin

**From the community marketplace (recommended):**

```
/plugin marketplace add anthropics/claude-plugins-community
/plugin install cloudradial-ucp@claude-community
```

**Or install the single plugin file directly.** Download `cloudradial-ucp.plugin` from the [**releases page**](https://github.com/cloudradial/helpers/releases) — it's one file that works on macOS, Windows, and Linux — then add it to your Claude app:

- **Cowork:** drag the file into the Cowork window, and approve it when asked.
- **Claude Desktop:** drag the file into the app (or add it from the plugin gallery), then **quit and reopen** Claude Desktop.
- **Claude Code:** run `claude /plugin install <path-to-the-downloaded-file>`, then restart Claude Code.

> Using more than one of these apps? Install it into each one.

### Step 2 — Turn it on

Start a new conversation and type:

> **Setup the CloudRadial Plugin**

Claude will ask for your CloudRadial **public key** and **private key** (find them in your CloudRadial admin portal under **Settings → API**), check that they work, and store them securely on your computer (encrypted at rest). You only do this once per computer.

### Step 3 — Try something

Pick anything from **What you can do** below, or just ask Claude in your own words.

## What you can do

Copy any of these into Claude and swap in your own company names / IDs:

**🔎 Look things up**
> Look up Acme Corp in CloudRadial
>
> Give me a full overview of company 42 before my meeting
>
> Which of Contoso's endpoints are out of warranty?
>
> What feedback has company 42 submitted lately?

**📝 Create content & training**
> Create a security assessment for company 42
>
> Write a KB article for Contoso about resetting MFA
>
> Build a phishing-awareness training course for company 15
>
> Build a training course for Contoso from this YouTube video: *(paste link)*

**🔧 Maintain the portal**
> Refresh the warranty info for endpoint serial ABC12345
>
> Update warranty dates for all of Acme Corp's devices
>
> Set up flexible-asset tracking for Contoso
>
> Show me Contoso's flexible assets and how they're configured

> **How the last two work:** These combine Claude's own abilities with the plugin's MCP server. For the course: Claude reads/summarizes the YouTube video, then the plugin's server creates the course and its lessons in CloudRadial (`create_resource`). For flexible assets: Claude structures the data and the server writes the `flexible_asset` records into your portal. Both are fully done through the plugin — the only thing it *doesn't* do is bulk-import flexible assets directly from ITGlue (that's a separate standalone sync script).

## How it works

```
You in Claude
     |
     |  MCP tool calls (over stdio)
     v
Bundled MCP server  (server/index.mjs, inside the plugin, spawned by your Claude app)
     |
     |  HTTPS with HTTP Basic auth (keys from local encrypted store or env vars)
     v
CloudRadial API V2
```

There is **no Azure Function**, no Chrome extension, no separate server to deploy, no npm install at runtime. The plugin contains the MCP server itself — an esbuild-bundled JavaScript file (**pure JS, no native binaries — one build runs on every OS**). The plugin's `.mcp.json` tells your Claude app how to launch it with `node`; installing the plugin auto-registers the server. Credentials are stored **encrypted on your computer** (or supplied via environment variables — see below).

## Skills (11)

Each skill below has a partner-facing **README** with example prompts to try. Click the skill name for its guide.

| Skill | What it does |
|-------|--------------|
| **[setup](skills/setup/README.md)** | First-run plugin setup + branded welcome tour — validates and stores credentials encrypted on your computer |
| **[portal-setup](skills/portal-setup/README.md)** | Walk a client through their 5-session CloudRadial implementation; 8 CSA pain-point playbooks; content seeding |
| **[portal-lookup](skills/portal-lookup/README.md)** | Look up companies, check portal status, assess LOMG lifecycle stage, prepare for meetings |
| **[content-management](skills/content-management/README.md)** | Create and manage articles, catalogs, menus, courses, lessons, and assessments |
| **[user-management](skills/user-management/README.md)** | Look up users by email/name, list users by company, analyze user adoption |
| **[endpoint-reporting](skills/endpoint-reporting/README.md)** | List endpoints, warranty reports, device inventory, application audits |
| **[course-management](skills/course-management/README.md)** | Create training courses and lessons (from a topic, document, or YouTube link); check enrollments |
| **[assessment-compliance](skills/assessment-compliance/README.md)** | Review security assessments, compliance tracking, flexible-asset management |
| **[feedback-analysis](skills/feedback-analysis/README.md)** | Analyze user feedback, CSAT trends, satisfaction reporting |
| **[service-management](skills/service-management/README.md)** | Services, service installs, domains, products, coverage analysis |
| **[reporting-admin](skills/reporting-admin/README.md)** | Archives, certificates, company groups, media, tokens, raw API access |

## MCP tools (17)

The MCP server exposes 17 tools to Claude:

| Tool | Purpose |
|------|---------|
| `setup_status` | Check whether credentials are configured (returns hint only, never the keys) |
| `configure_credentials` | Validate and store credentials (encrypted, on your computer) |
| `clear_credentials` | Wipe stored credentials |
| `search_companies` | Search companies by partial name |
| `company_overview` | Full snapshot: details, counts, recent articles + feedback |
| `list_resources` | List any of 30 resource types with OData filtering |
| `count_resources` | Count any resource type with optional filter |
| `get_resource` | Retrieve a single resource by ID (incl. composite keys) |
| `create_resource` | Create a new resource |
| `update_resource` | Update a resource (PUT full / PATCH partial) |
| `delete_resource` | Delete a resource by ID |
| `user_lookup` | Find users by email, name, or company |
| `manage_tokens` | List / get / create / revoke CloudRadial API tokens |
| `endpoint_update_warranty` | Trigger an async warranty refresh by endpoint serial number |
| `courseenrollment_complete` | Mark a course enrollment as completed (with optional score/comment) |
| `courseenrollment_for_user` | Get a user's enrollment record for a specific course |
| `raw_api_call` | Direct API call for advanced use cases |

## 30 supported resource types

`company`, `user`, `application_user`, `article`, `endpoint`, `catalog`, `catalog_question`, `assessment`, `feedback`, `service`, `service_install`, `domain`, `course`, `course_enrollment`, `course_lesson`, `course_lesson_history`, `menu`, `product`, `archive_item`, `certificate`, `company_group`, `company_group_company`, `quickstart`, `flexible_asset`, `flexible_asset_type`, `flexible_asset_field`, `endpoint_application`, `endpoint_custom_property`, `media`, `token`.

Composite-key resources (need extra args on get/update/delete): `archive_item`, `service_install`, `company_group_company`, `course_lesson_history`. `application_user` has no OData listing — get by id only.

## Credentials & security

- **Stored encrypted on your computer.** Credentials are written to a local file encrypted with AES-256-GCM, using a key derived from your machine and user account — never in plain text, and usable only on the same computer under the same user. (If the optional OS-keychain module `@napi-rs/keyring` is present in the server, the plugin uses the OS keychain instead — Windows Credential Manager / macOS Keychain / Linux libsecret.)
- **Validated before storage.** The setup wizard makes a live `GET /v2/odata/company/$count` call before writing anything — bad keys never get saved.
- **Privacy note for setup.** Because setup happens in chat, your keys appear briefly in the conversation transcript when you paste them. If you prefer the keys never enter the LLM context, set `CLOUDRADIAL_PUBLIC_KEY` and `CLOUDRADIAL_PRIVATE_KEY` environment variables in your MCP client config instead — the server picks those up first and skips the local store entirely. For shared or CI hosts you can also set `CLOUDRADIAL_CRED_SECRET` (adds key-derivation entropy) or `CLOUDRADIAL_CRED_FILE` (relocates the encrypted store).
- **To rotate:** re-run the setup wizard (it overwrites the stored entry). To remove: ask Claude to run `clear_credentials`.

## Things to know

- **OData pagination caps at 200.** The CloudRadial API returns at most 200 results per page. The `list_resources` tool accepts `top` and `skip` for pagination.
- **Article uses `subject`, not `title`.** Course uses `name`, not `title`. Skills know this, but keep it in mind if you use `raw_api_call`.
- **EU partners:** during setup, choose `https://api.eu.cloudradial.com` as the base URL instead of the US default.

## Documentation

- **[DEPLOYMENT.md](DEPLOYMENT.md)** — Install steps for Claude Desktop, Claude Code, and Cowork, plus troubleshooting.
- **[references/api-reference.md](references/api-reference.md)** — CloudRadial API V2 field-level schema reference.
- **MCP server source:** [`../cloudradial-ucp-mcp/`](../cloudradial-ucp-mcp) — the Node project that powers the tools.

## License

MIT
