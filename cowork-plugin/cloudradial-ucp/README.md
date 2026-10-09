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

Copy any prompt into Claude and swap in your own company names or IDs. Claude confirms the company and the change before it writes anything to your portal. Every prompt below works through the CloudRadial API, in both the Claude (Cowork, Claude Desktop, Claude Code) and Codex versions of the plugin.

### Get started

| Say this | What happens | Skill |
|---|---|---|
| `Setup the CloudRadial Plugin` | Guided key entry, a live check, and encrypted storage on your computer | setup |
| `Tour the plugin` | Every skill and what it does | setup |
| `Is the CloudRadial plugin configured?` | Status check that never shows the keys | setup |
| `Clear my CloudRadial credentials` | Removes the stored keys | setup |

### Look up a client and prepare for a meeting

| Say this | What happens | Skill |
|---|---|---|
| `Look up Acme Corp in CloudRadial` | Company details with user and endpoint counts | portal-lookup |
| `Prepare me for my meeting with Contoso` | Meeting prep: lifecycle stage, flags and talking points | portal-lookup |
| `How is Acme Corp doing in their portal?` | Adoption snapshot | portal-lookup |
| `Show me overviews for Acme, Contoso and Globex` | Side-by-side comparison | portal-lookup |
| `Prep a QBR for Acme Corp` | Endpoints, assessments and feedback pulled into one view | portal-setup |
| `Build a client deliverable for Contoso: roadmap, budget, machine audit and licenses` | A vCIO deliverable built in the portal | client-deliverable |
| `Recreate this ScalePad deliverable in CloudRadial` *(attach the PDF)* | The roadmap, goals and budget rebuilt as Planner items | client-deliverable |

### Set up a client portal

Walk a new client through implementation, or set up one area at a time. The plugin does every step the API supports and gives you a short list of the steps that stay in the portal (branding, integrations, security roles, agent deployment).

| Portal area | Say this | What happens | Skill |
|---|---|---|---|
| Whole portal | `Onboard a new client called Acme Corp` | Starts the five-session implementation: creates what the API can, lists the rest | portal-setup |
| Whole portal | `What does Contoso need next?` | Lifecycle stage and the next checklist | portal-setup |
| Whole portal | `Walk me through Session 2 for company 42` | The service desk session: checks, creates and to-dos | portal-setup |
| Whole portal | `What can you set up for Contoso through the API, and what do I do in the portal?` | The API-versus-portal split for every area | portal-setup |
| Company | `Create a new company called Acme Corp` | New company | company-management |
| Company | `Change the account manager for Contoso to Jane Smith` | Company updated | company-management |
| Company groups | `Add Acme Corp to the "Office 365 Only" group` | Group membership updated | company-management |
| Users | `Add jane@contoso.com, Jane Doe, to Contoso's portal` | New portal user | user-management |
| Users | `Who has access to Contoso's portal?` | Users with names, emails and roles | user-management |
| Service catalog | `Build a service catalog for Acme Corp` | Request forms for password reset, new user, hardware and software | content-management |
| Service catalog | `Add a required "Start date" question to Contoso's New User form, with JSON field ID startDate` | New question on the form | content-management |
| Knowledge base | `Seed Contoso with 10 starter KB articles` | Ten articles on common IT topics | content-management |
| Knowledge base | `Write a KB article for Contoso about resetting MFA` | One article, step by step | content-management |
| Menus | `Add a "Get Help" menu tile to Contoso's portal that opens the service catalog` | New menu tile | content-management |
| Quickstarts | `Add a quickstart to Contoso's home page on connecting to the VPN` | New quickstart guide | reporting-admin |
| Media | `Upload this image to Contoso's media library` *(attach it)* | Image stored in the portal | reporting-admin |
| Replacement tokens | `Set Contoso's SupportPhone token to 555-0100` | Every form, article and automation using `@SupportPhone` for Contoso shows the new value | reporting-admin |
| Replacement tokens | `List Contoso's replacement tokens` | Company tokens and the partner-level ones it inherits | reporting-admin |
| Training | `Build a phishing-awareness training course for Contoso` | Course with lessons and a quiz | course-management |
| Training | `Build a course for Contoso from this YouTube video: <link>` | Lessons from the video | course-management |
| Training | `Build a course from this document` *(attach it)* | Lessons from the document | course-management |
| Assessments | `Create a CIS Controls assessment for Contoso with these 20 questions` | New assessment with the questions loaded | assessment-compliance |
| Assessments | `Turn this spreadsheet into an assessment for company 42` | The .xlsx imported as an assessment | assessment-compliance |
| Assessments | `Copy our Baseline Security template into a new assessment for Acme, one set per server` | Template questions duplicated per server | assessment-compliance |
| Flexible assets | `Set up flexible-asset tracking for Contoso's network devices` | Asset type, fields and records | assessment-compliance |
| Services | `Mark the Backup service as installed on Contoso's DC01` | Service install recorded | service-management |
| Domains | `Add contoso.com as a managed domain for Contoso` | Domain added | service-management |

### Run the service day to day

| Say this | What happens | Skill |
|---|---|---|
| `Show me all unpublished articles for Contoso` | Draft content waiting for review | content-management |
| `Audit Contoso's portal content` | Articles, catalog items and menus by status, with gaps | content-management |
| `Who's completed the security training at Acme Corp?` | Enrollments with completion dates | course-management |
| `Who at Contoso hasn't finished their required training?` | Users with incomplete enrollments | course-management |
| `Which lesson did Sam stop at in the phishing course?` | Lesson-by-lesson progress | course-management |
| `How many users does Acme Corp have?` | Count by company | user-management |
| `Which of Contoso's users haven't completed security training?` | Users cross-checked with enrollments | user-management |
| `List all my companies` | Companies with endpoint counts | company-management |
| `Which companies have no portal logo?` | Branding audit across clients | company-management |

### Devices and lifecycle

| Say this | What happens | Skill |
|---|---|---|
| `How many endpoints does Acme Corp have?` | Device count | endpoint-reporting |
| `Which of Contoso's devices are out of warranty?` | Devices with expiration dates | endpoint-reporting |
| `Refresh warranty for all of Acme Corp's devices` | Warranty lookups queued by serial number | endpoint-reporting |
| `Show all software installed on endpoint 789` | Installed applications | endpoint-reporting |
| `Build a warranty expiration report for the next 6 months` | Devices expiring soon | endpoint-reporting |
| `Build hardware refresh cards for Contoso` | One Planner card per refresh category, each with a priority | endpoint-lifecycle-cards |
| `Which of Acme Corp's computers need replacing?` | The Replace list with reasons | endpoint-lifecycle-cards |

### Security, compliance and satisfaction

| Say this | What happens | Skill |
|---|---|---|
| `Show me Contoso's assessment scores` | Assessments with status, score and date | assessment-compliance |
| `How is Acme Corp doing on compliance?` | Passing, failing and in progress | assessment-compliance |
| `Which company has the lowest assessment score?` | Cross-company comparison | assessment-compliance |
| `Roll up assessment scores across all my clients` | Executive summary: totals, gaps, common issues, trends | assessment-export |
| `Which customers have the most assessment gaps?` | Clients ranked by gaps | assessment-export |
| `What feedback has Contoso submitted lately?` | Recent feedback | feedback-analysis |
| `Which of my clients have the lowest CSAT this quarter?` | Clients ranked by satisfaction | feedback-analysis |
| `Summarize themes in Contoso's recent feedback` | Grouped comment themes | feedback-analysis |

### Services, domains, certificates and reports

| Say this | What happens | Skill |
|---|---|---|
| `What services are installed for Acme Corp?` | Service installations | service-management |
| `Service coverage summary for Acme Corp` | Installed versus available | service-management |
| `Which of my managed domains expire in the next 90 days?` | Domain expiration sweep | service-management |
| `Which of Contoso's certificates expire in 30 days?` | Certificates with expiration dates | reporting-admin |
| `Show me Acme Corp's archived reports` | Archive items by date | reporting-admin |
| `Hit /v2/odata/company/$count via the API directly` | Raw API response, for anything not covered above | reporting-admin |

### What stays in the portal

The CloudRadial API doesn't cover these, so the plugin lists them for you instead of doing them: portal branding (logo, colors, theme), security roles and SSO, connecting integrations (PSA, Microsoft 365, RMM), deploying the endpoint agent, approval workflows and automations on a request form, the feedback widget and CSAT surveys, and scheduled report delivery.

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

Each skill below has a partner-facing **README** with example prompts to try. Click the skill name for its guide.

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
| **[assessment-compliance](skills/assessment-compliance/README.md)** | Review assessments, create an assessment from questions, a spreadsheet or a template, flexible assets |
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
