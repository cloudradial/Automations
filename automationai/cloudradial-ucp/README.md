# CloudRadial UCP Assistant

A general-purpose CloudRadial **AutomationAI agent** — the platform-native analog of the **CloudRadial UCP MCP plugin**. It reasons over the CloudRadial extension tools to look up, brief, audit, report on, and (with approval) change companies, users, endpoints, services, and tokens across the portal.

## Download & import

**Download the agent:** [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/cloudradial-ucp/cloudradial-ucp.agent.yml)

In AutomationAI: **Agents → Custom → Import**, upload the `.yml` (import is keyed on the slug `cloudradial-ucp-assistant`). Make sure these first-party CloudRadial extensions are installed and connected: `cloudradial-v2-companies` (which also carries the user tools), `cloudradial-v2-endpoints`, `cloudradial-v2-services`, `cloudradial-v2-tokens`.

Run it interactively in the **AI Playground**, or give it a goal. Pass a `request` (a question, an audit/report ask, or a change to make) and optionally a `companyName` to focus on one company.

## What it does

- **Look up & brief** — company overviews, user lookups, endpoint inventory and warranty posture, service installs, meeting-prep snapshots.
- **Audit** — companies missing an account manager or branding, stale users, out-of-warranty endpoints, orphaned services.
- **Report** — counts and rollups across companies, in plain language.
- **Change (approval-gated)** — create/update companies, users, endpoints, services, and tokens, only when explicitly asked.

## Governance

Read-first. Every create/update/delete is mutating and approval-gated — the agent states exactly what will change before doing it and never guesses an id. It runs dry by default.

## Extending its reach

This build ships with the five confirmed-available CloudRadial extensions so it never stalls on a missing one. To widen coverage (content/articles, assessments, courses, feedback), add the corresponding extension slugs to `requiredExtensionSlugs` once they're installed in your workspace.
