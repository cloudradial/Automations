# Endpoint LifeCycle Manager

A CloudRadial **AutomationAI agent and workflow** that reviews managed computers per company against industry refresh standards and maintains one **Planner card per refresh category** — Replace, Plan replacement, Upgrade in place, Retain, Needs data, Human review, Virtual machines — each carrying a triage priority and listing that category's devices in plain language.

## Scope — CloudRadial portal only

This agent uses **only the CloudRadial portal's endpoints** — both **workstations and servers** (servers route to *Human review*, VMs to their own track). It needs **no RMM and no ScalePad** connection; every decision comes from native endpoint fields already in CloudRadial.

Use it when the CloudRadial portal is the source of truth. To bring ScalePad Lifecycle Manager data into CloudRadial first, use the [ScalePad to CloudRadial Sync](../scalepad-cloudradial-sync/) workflow; this agent then works from whatever the endpoints hold.

## Pieces

| File | Type | Role |
|---|---|---|
| [`endpoint-lifecycle-manager.agent.yml`](endpoint-lifecycle-manager.agent.yml) | `automationsAgent` | The decision tracks, categories and card format. Slug `endpoint-warranty-refresh-advisor-planner-cards`. |
| [`endpoint-lifecycle-manager.yml`](endpoint-lifecycle-manager.yml) | `automationsWorkflow` | Runs the agent with its goal - one Agent node. Attach a Routine to it to run on a schedule. |

## Download & import

1. On **Agents → Custom → Import**, upload [`endpoint-lifecycle-manager.agent.yml`](endpoint-lifecycle-manager.agent.yml) (keyed on the slug `endpoint-warranty-refresh-advisor-planner-cards`). Set its variables below.
2. On **Workflows → Import**, upload [`endpoint-lifecycle-manager.yml`](endpoint-lifecycle-manager.yml), then **Publish** and **deploy** it to your runner.
3. Run it from **Test**, or attach a **Routine** (e.g. monthly). It takes no run input.

**Requires:** AutomationAI + these CloudRadial extensions installed and connected:
- `cloudradial-v2-endpoints` — read endpoints (workstations **and** servers)
- `cloudradial-v2-services` — read / create / update the Planner cards

## What it does

- Reads **native endpoint fields** (age from manufacture date, warranty expiry, OS, Windows 11 readiness, SSD/HDD, RAM, server/VM flags) and routes each computer through first-match decision tracks.
- Creates/updates **one card per (company, category)** via `cr_create_product` / `cr_patch_product`, reconciled by subject so re-runs update in place.
- Writes plain-language card bodies grouped by priority tier (Critical/High/Medium/Low).
- All decision logic is inline in the prompt — it does **not** call knowledge search or depend on grounding.

## Heads-up: this agent always writes

It has **no preview mode** (`dryRunDefault: false`) — every in-scope company with out-of-spec computers gets its cards created/updated. The workflow ships with `autoApprove: false`, so each card write waits for approval in the Inbox. Set it to `true` once you trust an unattended scheduled run.

## Variables

| Variable | Default | What it does |
|---|---|---|
| `companyIds` | `1` | Companies to process — comma list (`1,4,7`) or blank for all. |
| `plannerCategory` | `Efficiency` | Planner category name for the cards. |
| `plannerProductCategoryId` | `7` | Planner category id. |
| `defaultTargetDays` | `30` | Fallback target-date offset. |
