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

**Or install the single plugin file directly.** Download `cloudradial-ucp.plugin` from the [**releases page**](https://github.com/cloudradial/Automations/releases). It's one file that works on macOS, Windows, and Linux — then add it to your Claude app:

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

<!-- prompts:start -->
<!-- Generated from cowork-plugin/cloudradial-ucp/PROMPTS.md by scripts/sync-prompts.mjs. Edit PROMPTS.md, not this block. -->

## What you can do

Copy a prompt into Claude or Codex and swap in your own company names or IDs. Each one links to the full prompt in that skill's guide, which shows what to ask for, what you get, and what to watch for. The plugin confirms the company and shows you any change before it writes to your portal. Every prompt works through the CloudRadial API, in both the Claude (Cowork, Claude Desktop, Claude Code) and Codex versions of the plugin.

### Get started

| Say this | Skill | Full prompt |
|---|---|---|
| `Set up the CloudRadial plugin` | setup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/setup/README.md#set-up-the-plugin) |
| `Is the CloudRadial plugin configured?` | setup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/setup/README.md#check-the-connection) |
| `Give me a tour of the CloudRadial plugin` | setup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/setup/README.md#take-a-tour) |

### Look up a client and prepare for a meeting

| Say this | Skill | Full prompt |
|---|---|---|
| `Look up Acme Corp in CloudRadial` | portal-lookup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/portal-lookup/README.md#find-a-client) |
| `Prepare me for my meeting with Contoso` | portal-lookup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/portal-lookup/README.md#prepare-for-a-meeting) |
| `How is Acme Corp doing in their portal?` | portal-lookup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/portal-lookup/README.md#check-portal-adoption) |
| `Prep a QBR for Acme Corp` | portal-setup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/portal-setup/README.md#prep-a-qbr) |

### Set up a client portal

Walk a new client through implementation, or set up one area at a time. The plugin does every step the API supports and gives you a short list of the steps that stay in the portal.

| Say this | Skill | Full prompt |
|---|---|---|
| `What does Contoso need next?` | portal-setup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/portal-setup/README.md#plan-the-next-step) |
| `Walk me through Session 2 for company 42` | portal-setup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/portal-setup/README.md#run-an-implementation-session) |
| `Create a new company called Acme Corp` | company-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/company-management/README.md#create-a-company) |
| `Add jane@contoso.com, Jane Doe, to Contoso's portal` | user-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/user-management/README.md#add-a-user) |
| `Build a New User request form for Acme Corp` | content-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/content-management/README.md#build-a-request-form) |
| `Seed Contoso with 10 starter KB articles` | content-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/content-management/README.md#seed-a-knowledge-base) |
| `Add a "Get Help" menu tile to Contoso's portal` | content-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/content-management/README.md#add-a-menu-tile) |
| `Add a quickstart to Contoso's home page` | reporting-admin | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/reporting-admin/README.md#add-a-quickstart) |
| `Set Contoso's SupportPhone token to 555-0100` | reporting-admin | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/reporting-admin/README.md#set-a-replacement-token) |
| `Build a phishing-awareness course for Contoso` | course-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/course-management/README.md#build-a-training-course) |
| `Create a CIS Controls assessment for Contoso` | assessment-compliance | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/assessment-compliance/README.md#create-an-assessment-from-questions) |
| `Add contoso.com as a managed domain` | service-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/service-management/README.md#add-a-domain) |

### Run the service day to day

| Say this | Skill | Full prompt |
|---|---|---|
| `Who has completed the security training at Acme Corp?` | course-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/course-management/README.md#check-who-finished) |
| `Audit Contoso's portal content` | content-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/content-management/README.md#audit-portal-content) |
| `List all my companies` | company-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/company-management/README.md#list-and-audit-companies) |
| `Rename the "Office 365 Only" company group` | company-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/company-management/README.md#rename-a-company-group) |

### Devices and lifecycle

| Say this | Skill | Full prompt |
|---|---|---|
| `Which of Contoso's devices are out of warranty?` | endpoint-reporting | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/endpoint-reporting/README.md#warranty-report) |
| `Set the warranty end date on Contoso's laptop` | endpoint-reporting | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/endpoint-reporting/README.md#write-a-warranty-date-by-hand) |
| `Build hardware refresh cards for Contoso` | endpoint-lifecycle-cards | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/endpoint-lifecycle-cards/README.md#build-refresh-cards) |
| `Build a hardware refresh roadmap for Contoso` | client-deliverable | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/client-deliverable/README.md#build-a-refresh-roadmap) |

### Compliance and satisfaction

| Say this | Skill | Full prompt |
|---|---|---|
| `How is Contoso doing on compliance?` | assessment-compliance | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/assessment-compliance/README.md#check-compliance) |
| `Turn this spreadsheet into an assessment` | assessment-compliance | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/assessment-compliance/README.md#import-a-spreadsheet) |
| `Roll up assessment scores across all my clients` | assessment-export | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/assessment-export/README.md#roll-up-every-client) |
| `What feedback has Contoso submitted in the last 30 days?` | feedback-analysis | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/feedback-analysis/README.md#review-recent-feedback) |
| `Fix a feedback entry for ticket 123456` | feedback-analysis | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/feedback-analysis/README.md#fix-a-feedback-entry) |
| `Move feedback to another company` | feedback-analysis | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/feedback-analysis/README.md#move-feedback-to-another-company) |
| `Which of my clients have the lowest CSAT this quarter?` | feedback-analysis | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/feedback-analysis/README.md#compare-satisfaction) |

### Domains, certificates and reports

| Say this | Skill | Full prompt |
|---|---|---|
| `Which of my managed domains expire in the next 90 days?` | service-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/service-management/README.md#domain-expirations) |
| `Which of Contoso's certificates expire in the next 30 days?` | reporting-admin | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/reporting-admin/README.md#certificate-expirations) |

### What stays in the portal

The CloudRadial API doesn't cover these, so the plugin lists them for you instead of doing them: portal branding (logo, colors, theme), security roles and SSO, connecting integrations (PSA, Microsoft 365, RMM), deploying the endpoint agent, approval workflows and automations on a request form, the feedback widget and CSAT surveys, scheduled report delivery, a course's exam passing score, copying an assessment template, deleting assessments, and attaching files to archived reports.

For work that should run on its own (on a schedule, from a form, or from ServiceAI), use the matching [AutomationAI automations](https://github.com/cloudradial/Automations/tree/main).

<!-- prompts:end -->

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

## Skills (15)

Each skill below has a partner-facing **README** with full example prompts, what you get, and what to watch for. Click the skill name for its guide.

| Skill | What it does |
|-------|--------------|
| **[setup](skills/setup/README.md)** | First-run plugin setup + branded welcome tour — validates and stores credentials encrypted on your computer |
| **[portal-setup](skills/portal-setup/README.md)** | Walk a client through their 5-session CloudRadial implementation; 8 CSA pain-point playbooks; content seeding |
| **[portal-lookup](skills/portal-lookup/README.md)** | Look up companies, check portal status, assess LOMG lifecycle stage, prepare for meetings |
| **[content-management](skills/content-management/README.md)** | Create and manage articles, catalogs, menus, courses, lessons, and assessments |
| **[company-management](skills/company-management/README.md)** | Create, update, delete, and group companies; account managers; portal branding |
| **[user-management](skills/user-management/README.md)** | Look up users by email/name, list users by company, analyze user adoption |
| **[endpoint-reporting](skills/endpoint-reporting/README.md)** | List endpoints, warranty reports, device inventory, application audits |
| **[endpoint-lifecycle-cards](skills/endpoint-lifecycle-cards/README.md)** | Maintain one Planner card per hardware-refresh category (Replace, Plan, Upgrade, Retain…) with triage priority |
| **[course-management](skills/course-management/README.md)** | Create training courses and lessons (from a topic, document, or YouTube link); check enrollments |
| **[assessment-compliance](skills/assessment-compliance/README.md)** | Review assessments, create or refresh an assessment from questions or a spreadsheet, flexible assets |
| **[assessment-export](skills/assessment-export/README.md)** | Roll up assessment results across every client into an executive summary |
| **[client-deliverable](skills/client-deliverable/README.md)** | Build a vCIO-style deliverable: IT roadmap, goals, budget, machine audit, Microsoft licenses |
| **[feedback-analysis](skills/feedback-analysis/README.md)** | Analyze user feedback, CSAT trends, satisfaction reporting |
| **[service-management](skills/service-management/README.md)** | Services, service installs, domains, products, coverage analysis |
| **[reporting-admin](skills/reporting-admin/README.md)** | Archives, certificates, company groups, quickstarts, media, replacement tokens, raw API access |

## MCP tools (18)

The MCP server exposes 18 tools to Claude:

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
| `manage_tokens` | List, get, set or delete replacement tokens (`@SupportPhone` and the like), partner-level or per company. Not API keys. |
| `endpoint_update_warranty` | Trigger an async warranty refresh by endpoint serial number |
| `courseenrollment_complete` | Mark a course enrollment as completed (with optional score/comment) |
| `courseenrollment_for_user` | Get a user's enrollment record for a specific course |
| `assessment_import` | Create an assessment and load its questions from a list, a template-layout .xlsx, or a template assessment |
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
