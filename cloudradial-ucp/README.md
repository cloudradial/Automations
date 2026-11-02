# Run Portal Admin Tasks by Asking

Set up new client companies and run your clients' portals by asking in plain English. When you ask for a change, it shows you exactly what will change and waits for your approval first.

## What happens

This is the **CloudRadial UCP Assistant**, an AI agent in AutomationAI for setting up and running your CloudRadial portal. Your team asks it questions in the **AI Playground**, and other automations run it behind the scenes. Your clients only notice once an approved change shows up in their portal.

Things you can ask it to do:

- **Set up a new client.** "Set up Contoso Ltd with the domain contoso.com and add Pat Lee as a user." It checks the company isn't already there, then adds the company, its domain, its company group, its first users, its tokens, starter request forms and menu tiles. The **Set Up a New Company** workflow in this folder does the same from a short form.
- **Look up and audit.** "Which companies have no account manager?" Companies, users, services, tokens, articles, request forms and menus.
- **Report.** "How many users does each company have?" Counts and totals across your companies, in plain language.
- **Make changes, when you ask.** Create or update companies, users, services, tokens, articles, request forms and menus.

Devices, warranties, assessments, flexible assets, feedback and training courses are handled by its sibling, [Report on Devices, Compliance and Training by Asking](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp-reporting).

## What it protects

- **Every change needs your approval.** It says exactly what will change before it makes any create, update or delete.
- **No duplicates.** It looks for the company and its domain before setting up a new client, and stops if either is already there.
- **No guessing.** It finds each company, user or form by name first. If more than one matches, it asks which one you mean.
- **Preview by default.** Out of the box it describes changes but doesn't make them.

## Works with

CloudRadial: companies, users, domains, company groups, services, tokens, articles, request forms and menus. No PSA is needed.

- **Logo, theme, messaging, integrations and security roles:** CloudRadial only lets you set these in the portal, so it lists them as steps for you to finish.
- **Menu tiles:** it can't choose who sees a new tile yet, so it reminds you to show each one to Everyone.

## What you need

- AutomationAI
- These CloudRadial extensions, installed and connected in AutomationAI: companies, tokens, services and content

## Set it up

1. **Download** the [agent and workflow files](https://github.com/cloudradial/Automations/releases/tag/cloudradial-ucp/v2.0.0).
2. In AutomationAI, go to **Agents > Custom > Import** and upload the agent file. Importing it again later replaces the one you have.
3. Go to **Workflows > Import** and upload `set-up-new-company.yml`.
4. To set up a client, open **Set Up a New Company**, choose **Run**, and fill in the company name plus anything else you have.

It starts in preview mode. When you're ready for it to make changes, the [technical details](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp#dry-run-and-going-live) show how to switch it over. That switch applies to every automation that uses it.

**Test it.** Run **Set Up a New Company** for a made-up company in preview mode, and check the list of records it says it would create.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp#technical-details) cover the extensions it uses, the run input, how preview mode works, and what changed in 2.0.

---

## Technical details

**Formerly:** CloudRadial UCP Assistant | **Marketplace ID:** AAI-00031 | **Type:** Agent + goal workflow | **Version:** 2.0.0

## Files

Each version is published as a release, with this automation's `.yml` files attached. Download them from the [**release**](https://github.com/cloudradial/Automations/releases/tag/cloudradial-ucp/v2.0.0).

| What | Link |
|---|---|
| View `cloudradial-ucp.agent.yml` (agent 0.2.0) | [GitHub](https://github.com/cloudradial/Automations/blob/main/cloudradial-ucp/cloudradial-ucp.agent.yml) |
| View `set-up-new-company.yml` (goal workflow) | [GitHub](https://github.com/cloudradial/Automations/blob/main/cloudradial-ucp/set-up-new-company.yml) |
| Download both | [Release](https://github.com/cloudradial/Automations/releases/tag/cloudradial-ucp/v2.0.0) |
| Sibling agent | [CloudRadial UCP Reporting](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp-reporting) |
| Used by | [Add Many Client Companies at Once](https://github.com/cloudradial/Automations/tree/main/add-companies-to-portal) |
| Used by | [Add Many KB Articles at Once](https://github.com/cloudradial/Automations/tree/main/bulk-create-kb-articles) |
| Used by | [Load Your Request Forms into Any Portal](https://github.com/cloudradial/Automations/tree/main/import-service-catalog) |
| Used by | [Onboard Many Portal Users at Once](https://github.com/cloudradial/Automations/tree/main/onboard-users-to-portal) |
| All files in this automation | [cloudradial-ucp](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/cloudradial-ucp) |
| Marketplace listing | [AAI-00031](https://automations.cloudradial.com/marketplace/AAI-00031) |

## How it works

A general-purpose CloudRadial **AutomationAI agent** (slug `cloudradial-ucp-assistant`), the platform-native version of the **CloudRadial UCP MCP plugin** for portal setup and administration. It reasons over the CloudRadial extension tools to look up, audit, report on and (with approval) change companies, users, domains, company groups, services, tokens and portal content.

**Extensions** (88 tools): `cloudradial-v2-companies` (companies, users, domains, company groups), `cloudradial-v2-tokens`, `cloudradial-v2-services` and `cloudradial-v2-content` (articles, request forms and questions, menus, quickstarts, media). They use the runner secrets `CloudRadial-BaseUrl`, `CloudRadial-PublicKey` and `CloudRadial-PrivateKey`.

### Why two agents

All eight CloudRadial extensions together have 163 tools, and AutomationAI on OpenAI rejects a run with more than 128. So the plugin's reach is split across two agents:

| Agent | Extensions | Tools |
|---|---|---|
| **CloudRadial UCP Assistant** (this one): portal setup and admin | companies, tokens, services, content | 88 |
| [**CloudRadial UCP Reporting**](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp-reporting): devices, compliance, feedback, training | companies, endpoints, compliance, feedback, training | 103 |

A workflow's Agent node can narrow the tools further with `allowedExtensions`.

### Plugin features not in either agent

These plugin tools have no extension equivalent: `company_overview` and `count_resources` (the agents build the same answer from list calls), `endpoint_update_warranty`, the spreadsheet upload in `assessment_import`, and `raw_api_call`.

## Set Up a New Company (goal workflow)

`Start → Read the setup → Set up the company (Agent node running cloudradial-ucp-assistant) → End`

**Read the setup** is a PowerShell step that checks the run input before the agent starts. It stops the run, and names every problem at once, if the company name is missing, an email or domain is malformed, or a list is over the per-run limit. Then it writes one request for the agent.

**Run input** (only `companyName` is required):

| Field | What it is | Limit |
|---|---|---|
| `companyName` | The new company's name | required |
| `domain` | Its default email domain, such as `contoso.com` | |
| `companyGroup` | An existing company group to add it to | |
| `accountManager`, `territory`, `psaIdentifier`, `psaKey` | Company fields, set only when given | |
| `users` | `[{"firstName","lastName","email"}]` | 5 |
| `tokens` | `[{"token","value"}]` or `{"SupportPhone":"555-0100"}` | 5 |
| `requestForms` | `[{"subject","category","description"}]` | 3 |
| `menuTiles` | `[{"name","url","category"}]` | 3 |

The limits keep one run inside the agent's 25-turn budget. Add more users or forms afterwards with [Onboard Many Portal Users at Once](https://github.com/cloudradial/Automations/tree/main/onboard-users-to-portal) and [Load Your Request Forms into Any Portal](https://github.com/cloudradial/Automations/tree/main/import-service-catalog).

**The agent** checks for an existing company with that name and an existing domain first, and stops if either exists. It creates the company, reads it back for its id, then creates the domain (as the default), the group membership, users, tokens, request forms and menu tiles. It never updates or deletes anything in this run. Its Agent node allows only the companies, tokens and content extensions, and has `autoApprove: false`, so each create waits in the **Inbox** for approval.

**Output:** `companyId`, `answer`, `actions` (created or would create), `skipped`, and `manualSteps` (logo and theme, messaging, the PSA and Microsoft 365 links, security roles, showing each new menu tile to Everyone, inviting the users).

**Compared with [New Client Onboarding](https://github.com/cloudradial/Automations/tree/main/new-client-onboarding):** that is a no-AI workflow that creates the company, domain and group membership, opens the onboarding checklist ticket in your PSA and writes a Microsoft 365 baseline report. Use it for your standard onboarding. Use this one when you also want users, tokens, request forms and menu tiles.

## Dry run and going live

`cloudradial-ucp.agent.yml` ships with `dryRunDefault: true`. In dry run the agent does all its reads and describes each change it *would* make, but changes nothing. AutomationAI has **no dry-run switch** on the workflow's Agent node, the deployment, or the agent's page. The setting lives only in the agent file, so going live means re-importing it:

1. Open `cloudradial-ucp.agent.yml` and change `dryRunDefault: true` to `dryRunDefault: false`. Leave everything else the same.
2. On **Agents → Custom → Import**, upload the edited file. Import is keyed on the slug, so it replaces the installed agent in place.
3. To go back to preview, set it to `true` and re-import.

The change applies to every workflow that uses this agent. Each of them keeps `autoApprove: false`, so even when the agent is live every create still waits in the **Inbox** until you approve it. Keep the repo copy on `true`, so a fresh install always starts in preview.

## What changed in 2.0

- **Agent 0.2.0.** It now requires `cloudradial-v2-content`, and it no longer requires `cloudradial-v2-endpoints` or `cloudradial-v2-compliance`. Those moved to the new [CloudRadial UCP Reporting](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp-reporting) agent, with feedback and training.
- **Moved to the Reporting agent:** Walk Into Every Client Call Prepared (Portal Lookup), Remove a Flexible Asset Type You No Longer Use, Bring IT Glue Documentation into the Portal, and Add Many Training Courses at Once. Import the Reporting agent before updating them.
- **New:** the Set Up a New Company goal workflow, and step-by-step company setup rules in the agent's instructions.
- **Company updates:** `cr_patch_company` sends plain fields, while the CloudRadial API documents company PATCH as JSON Patch. The agent stops and reports a 400 rather than falling back to a full replace. This hasn't been checked on a live update yet.
