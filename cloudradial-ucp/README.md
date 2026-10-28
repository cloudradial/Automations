# Run Portal Admin Tasks by Asking

Ask about your clients' portals in plain English, and get answers, audits and reports back. When you ask for a change, it shows you exactly what will change and waits for your approval first.

## What happens

This is the **CloudRadial UCP Assistant**, an AI agent in AutomationAI that works across your CloudRadial portal. Your team asks it questions in the **AI Playground**, and other automations run it behind the scenes. Your clients only notice once an approved change shows up in their portal.

Things you can ask it to do:

- **Look up and brief.** "Give me an overview of Contoso." Company overviews, user lookups, device inventory and warranty status, installed services, flexible assets, and a quick snapshot before a client meeting.
- **Audit.** "Which companies have no account manager?" Companies missing an account manager or branding, users who are stale or have never signed in, devices out of warranty or getting old, and services no one is using.
- **Report.** "How many users does each company have?" Counts and totals across your companies, in plain language.
- **Make changes, when you ask.** Create or update companies, users, devices, services, tokens and flexible assets. It removes a flexible asset type only when you name that exact type and no company has anything in it.

Eight automations run it for you, such as Add Many Training Courses at Once and Walk Into Every Client Call Prepared. The [technical details](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp#technical-details) list them all.

## What it protects

- **Every change needs your approval.** It says exactly what will change before it makes any create, update or delete.
- **No guessing.** It finds each company, user or device by name first. If more than one matches, it asks which one you mean.
- **Preview by default.** Out of the box it describes changes but doesn't make them.

## Works with

CloudRadial: companies, users, devices, services, tokens, and compliance and flexible assets. No PSA is needed.

- **Articles, courses and feedback:** not covered out of the box. You can add them once those CloudRadial extensions are installed (see the technical details).

## What you need

- AutomationAI
- These CloudRadial extensions, installed and connected in AutomationAI: companies (which includes users), endpoints, services, tokens and compliance

## Set it up

1. **Download** the [agent file](https://github.com/cloudradial/Automations/releases/tag/cloudradial-ucp/v1.0.0).
2. In AutomationAI, go to **Agents > Custom > Import** and upload it. Importing it again later replaces the one you have.
3. Open the **AI Playground**, or import one of the automations above that runs it.

It starts in preview mode. When you're ready for it to make changes, the [technical details](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp#dry-run-and-going-live) show how to switch it over. That switch applies to every automation that uses it.

**Test it.** In the **AI Playground**, ask it for an overview of one of your companies and check the answer matches your portal.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp#technical-details) cover the extensions it uses, how preview mode works, and how to widen what it can reach.

---

## Technical details

**Formerly:** CloudRadial UCP Assistant | **Marketplace ID:** AAI-00031 | **Type:** Agent | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/cloudradial-ucp/v1.0.0).

**Import** [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/cloudradial-ucp/cloudradial-ucp.agent.yml) on **Agents → Custom → Import**. An agent only runs from a workflow that gives it a goal; these automations run this one:

- [Add Many Client Companies at Once](https://github.com/cloudradial/Automations/tree/main/add-companies-to-portal)
- [Add Many KB Articles at Once](https://github.com/cloudradial/Automations/tree/main/bulk-create-kb-articles)
- [Add Many Training Courses at Once](https://github.com/cloudradial/Automations/tree/main/bulk-create-training-courses)
- [Load Your Request Forms into Any Portal](https://github.com/cloudradial/Automations/tree/main/import-service-catalog)
- [Bring IT Glue Documentation into the Portal](https://github.com/cloudradial/Automations/tree/main/itglue-to-flexible-assets)
- [Onboard Many Portal Users at Once](https://github.com/cloudradial/Automations/tree/main/onboard-users-to-portal)
- [Walk Into Every Client Call Prepared](https://github.com/cloudradial/Automations/tree/main/portal-lookup)
- [Remove a Flexible Asset Type You No Longer Use](https://github.com/cloudradial/Automations/tree/main/remove-empty-flexible-asset-type)

| What | Link |
|---|---|
| View `cloudradial-ucp.agent.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/cloudradial-ucp/cloudradial-ucp.agent.yml) |
| Download `cloudradial-ucp.agent.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/cloudradial-ucp/v1.0.0) |
| Used by | [Add Many Client Companies at Once](https://github.com/cloudradial/Automations/tree/main/add-companies-to-portal) |
| Used by | [Add Many KB Articles at Once](https://github.com/cloudradial/Automations/tree/main/bulk-create-kb-articles) |
| Used by | [Add Many Training Courses at Once](https://github.com/cloudradial/Automations/tree/main/bulk-create-training-courses) |
| Used by | [Load Your Request Forms into Any Portal](https://github.com/cloudradial/Automations/tree/main/import-service-catalog) |
| Used by | [Bring IT Glue Documentation into the Portal](https://github.com/cloudradial/Automations/tree/main/itglue-to-flexible-assets) |
| Used by | [Onboard Many Portal Users at Once](https://github.com/cloudradial/Automations/tree/main/onboard-users-to-portal) |
| Used by | [Walk Into Every Client Call Prepared](https://github.com/cloudradial/Automations/tree/main/portal-lookup) |
| Used by | [Remove a Flexible Asset Type You No Longer Use](https://github.com/cloudradial/Automations/tree/main/remove-empty-flexible-asset-type) |
| All files in this automation | [cloudradial-ucp](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/cloudradial-ucp) |
| Marketplace listing | [AAI-00031](https://automations.cloudradial.com/marketplace/AAI-00031) |

## How it works

A general-purpose CloudRadial **AutomationAI agent**, the platform-native analog of the **CloudRadial UCP MCP plugin**. It reasons over the CloudRadial extension tools to look up, brief, audit, report on, and (with approval) change companies, users, endpoints, services, tokens and flexible assets across the portal.

## Download & import

**Download the agent:** [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/releases/tag/cloudradial-ucp/v1.0.0)

In AutomationAI: **Agents → Custom → Import**, upload the `.yml` (import is keyed on the slug `cloudradial-ucp-assistant`). Make sure these first-party CloudRadial extensions are installed and connected: `cloudradial-v2-companies` (which also carries the user tools), `cloudradial-v2-endpoints`, `cloudradial-v2-services`, `cloudradial-v2-tokens`, `cloudradial-v2-compliance` (assessments, certificates and flexible assets, added in 0.1.4).

Run it interactively in the **AI Playground**, or from a workflow that gives it a goal. Two workflows run it:
- [Portal Lookup](https://github.com/cloudradial/Automations/tree/main/portal-lookup), a read-only briefing.
- [Remove Empty Flexible Asset Type](https://github.com/cloudradial/Automations/tree/main/remove-empty-flexible-asset-type), which deletes one empty type and waits for your approval first.

Pass a `request` (a question, an audit/report ask, or a change to make) and optionally a `companyName` to focus on one company.

## What it does

- **Look up & brief**, company overviews, user lookups, endpoint inventory and warranty posture, service installs, flexible assets, meeting-prep snapshots.
- **Audit**, companies missing an account manager or branding, stale users, out-of-warranty endpoints, orphaned services.
- **Report**, counts and rollups across companies, in plain language.
- **Change (approval-gated)**, create/update companies, users, endpoints, services, tokens and flexible assets, only when explicitly asked. It deletes a flexible asset type only when asked for that exact type and no company has a row in it.

## Governance

Read-first. Every create/update/delete is mutating and approval-gated, the agent states exactly what will change before doing it and never guesses an id. It runs dry by default.

## Dry run and going live

`cloudradial-ucp.agent.yml` ships with `dryRunDefault: true`. In dry run the agent does all its reads and describes each change it *would* make, but changes nothing. AutomationAI has **no dry-run switch** on the workflow's Agent node, the deployment, or the agent's page. The setting lives only in the agent file, so going live means re-importing it:

1. Open `cloudradial-ucp.agent.yml` and change `dryRunDefault: true` to `dryRunDefault: false`. Leave everything else the same.
2. On **Agents → Custom → Import**, upload the edited file. Import is keyed on the slug, so it replaces the installed agent in place.
3. To go back to preview, set it to `true` and re-import.

The change applies to every workflow that uses this agent. Portal Lookup is read-only either way. Remove Empty Flexible Asset Type keeps `autoApprove: false`, so even when the agent is live its delete waits in the **Inbox** until you approve it. Keep the repo copy on `true`, so a fresh install always starts in preview.

## Extending its reach

This build requires only default (catalog) CloudRadial extensions, so it never stalls on a missing one. To widen coverage (content/articles, courses, feedback), add the corresponding extension slugs to `requiredExtensionSlugs` once they're installed in your workspace.
