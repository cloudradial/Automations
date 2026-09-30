# Walk Into Every Client Call Prepared

A one-page snapshot of any client's users, devices, warranties and portal setup gaps in seconds, with nothing changed.

**Formerly:** Portal Lookup | **Marketplace ID:** AAI-00014 | **Type:** Agent

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `portal-lookup.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/portal-lookup/portal-lookup.yml) |
| Download `portal-lookup.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/portal-lookup/portal-lookup.yml) |
| All files in this automation | [automationai/portal-lookup](https://github.com/cloudradial/Automations/tree/main/automationai/portal-lookup) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/portal-lookup) |
| Marketplace listing | [AAI-00014](https://automations.cloudradial.com/marketplace/AAI-00014) |

## How it works

A CloudRadial **AutomationAI workflow** that produces a read-only portal briefing for meeting prep: company footprint, users, endpoints, warranty posture and setup gaps. Name a company and it briefs on that one; name none and it gives a portal-wide snapshot.

It runs the [CloudRadial UCP Assistant](../cloudradial-ucp/) agent with a read-only goal, so there's no separate agent to maintain.

## Pieces

| File | Type | Role |
|---|---|---|
| [`portal-lookup.yml`](portal-lookup.yml) | `automationsWorkflow` | **Run inputs** (fills in defaults and writes the request) → **Portal Briefing** (an Agent node running `cloudradial-ucp-assistant`). |

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](../cloudradial-ucp/) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
2. Make sure the first-party extensions `cloudradial-v2-companies` (which also carries the user tools) and `cloudradial-v2-endpoints` are installed and connected.
3. On **Workflows → Import**, upload `portal-lookup.yml`, then **Publish** and **deploy** it to your runner.
4. Run it from **Test** or the Run dialog. Leave the Trigger input empty for a portal-wide snapshot, or send one of the inputs below.

## Inputs

All optional.

| Field | Default | What it does |
|---|---|---|
| `companyName` | — | Brief on one company by name. |
| `cloudradialCompanyId` | — | Brief on one company by CloudRadial companyId. |
| `warrantyWindowDays` | `90` | Days ahead that count a warranty as "expiring soon". |

Example: `{"companyName": "KMCO Group Ltd"}`

## Read-only

The goal tells the agent never to create, update or delete anything, and the Agent node keeps `autoApprove: false`, so any write it tried would wait in the Inbox for approval.

The briefing comes back as the agent's `answer`. To send it somewhere, add a [Deliver Result](../deliver-result/) Agent node after it, the way [Weekly Fleet Audit](../weekly-fleet-audit/) does.
