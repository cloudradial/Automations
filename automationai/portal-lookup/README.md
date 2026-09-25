# Portal Lookup

A CloudRadial **AutomationAI agent** that produces a read-only portal briefing — company footprint, users, endpoints, warranty posture, and setup gaps — for meeting prep. Given a company it briefs on that company; with none it gives a portal-wide snapshot.

## Download & import

**Download the agent:** [`portal-lookup.agent.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/portal-lookup/portal-lookup.agent.yml)

In AutomationAI: **Agents → Custom → Import**, upload the `.yml` (import is keyed on the slug `cloudradial-portal-lookup`). Make sure these first-party CloudRadial extensions are installed and connected: `cloudradial-v2-companies` (which also carries the user tools), `cloudradial-v2-endpoints`. Run it, optionally passing a `companyName` (or `cloudradialCompanyId`); with none it gives a portal-wide snapshot.

## Settings

| Variable | Default | What it does |
|---|---|---|
| `warrantyWindowDays` | `90` | Days ahead to count an endpoint warranty as "expiring soon" in the briefing. |

Strictly read-only — it never creates, updates, or deletes anything.
