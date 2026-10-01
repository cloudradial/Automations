# Keep Every Client's Hardware Refresh Plan Current

Every computer is checked against age, warranty and Windows 11 readiness, and each client's refresh plan in Planner stays sorted by priority.

**Formerly:** Endpoint LifeCycle Manager | **Marketplace ID:** Not yet listed | **Type:** Agent

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `endpoint-lifecycle-manager.agent.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager.agent.yml) |
| Download `endpoint-lifecycle-manager.agent.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager.agent.yml) |
| All files in this automation | [automationai/endpoint-lifecycle-manager](https://github.com/cloudradial/Automations/tree/main/automationai/endpoint-lifecycle-manager) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/endpoint-lifecycle-manager) |

## How it works

A CloudRadial **AutomationAI agent and workflow** that reviews managed computers per company against industry refresh standards and maintains one **Planner card per refresh category** — Replace, Plan replacement, Upgrade in place, Retain, Needs data, Human review, Virtual machines — each carrying a triage priority and listing that category's devices in plain language.

## Scope, CloudRadial portal only

This agent uses **only the CloudRadial portal's endpoints**, both **workstations and servers** (servers route to *Human review*, VMs to their own track). It needs **no RMM and no ScalePad** connection; every decision comes from native endpoint fields already in CloudRadial.

Use it when the CloudRadial portal is the source of truth. To bring ScalePad Lifecycle Manager data into CloudRadial first, use the [ScalePad to CloudRadial Sync](../scalepad-cloudradial-sync/) workflow; this agent then works from whatever the endpoints hold.

## Pieces

| File | Type | Role |
|---|---|---|
| [`endpoint-lifecycle-manager.agent.yml`](endpoint-lifecycle-manager.agent.yml) | `automationsAgent` | The decision tracks, categories and card format. Slug `endpoint-warranty-refresh-advisor-planner-cards`, v0.4.0. |
| [`endpoint-lifecycle-manager.yml`](endpoint-lifecycle-manager.yml) | `automationsWorkflow` | Runs the agent with its goal - one Agent node. Attach a Routine to it to run on a schedule. |

## Download & import

1. On **Agents → Custom → Import**, upload [`endpoint-lifecycle-manager.agent.yml`](endpoint-lifecycle-manager.agent.yml) (keyed on the slug `endpoint-warranty-refresh-advisor-planner-cards`). Set its variables below.
2. On **Workflows → Import**, upload [`endpoint-lifecycle-manager.yml`](endpoint-lifecycle-manager.yml), then **Publish** and **deploy** it to your runner.
3. Run it from **Test**, or attach a **Routine** (e.g. monthly). It takes no run input.

**Requires:** AutomationAI + these CloudRadial extensions installed and connected:
- `cloudradial-v2-endpoints`, read endpoints (workstations **and** servers)
- `cloudradial-v2-services`, read / create / update the Planner cards

## What it does

- Reads **native endpoint fields** (age from manufacture date, warranty expiry, OS, Windows 11 readiness, SSD/HDD, RAM, server/VM flags) and routes each computer through first-match decision tracks.
- Creates/updates **one card per (company, category)** via `cr_create_product` / `cr_patch_product`, reconciled by subject so re-runs update in place.
- Writes a **client-readable card body**: an opening sentence with the count, **What we recommend**, each device under its tier (Critical / High / Medium / Low) with model, serial, age, warranty date, OS and the action, then a **Summary** of tier counts.
- Adds an **internal note** to every card (not shown to clients): the company, how many computers were evaluated, and the tier counts on the card.
- **Places cards on the Planner roadmap** by urgency when `scheduleOnRoadmap` is on (the default): Critical and High, Human review and Needs data go in the next quarter, Medium the one after, Low the third. If the Services extension rejects the roadmap fields, the card is written without them and the run reports `roadmapFieldsDropped`.
- **Closes cards whose category is empty.** When no computer lands in a category any more, its card is marked **Completed** with a one-line note, not left open as a placeholder. If devices return to that category later, the card reopens (on the roadmap again when `scheduleOnRoadmap` is on).
- **Critical stays visible.** Planner has no Critical priority, so a Critical card is stored as High, but its summary opens with "Critical:" and the body uses the Critical heading.
- All decision logic is inline in the prompt, it does **not** call knowledge search or depend on grounding.

## Heads-up: this agent always writes

It has **no preview mode** (`dryRunDefault: false`) — every in-scope company with out-of-spec computers gets its cards created/updated. The workflow ships with `autoApprove: false`, so each card write waits for approval in the Inbox. Set it to `true` once you trust an unattended scheduled run.

## Variables

| Variable | Default | What it does |
|---|---|---|
| `companyIds` | `1` | Companies to process, comma list (`1,4,7`) or blank for all. |
| `plannerCategory` | `Efficiency` | Planner category name for the cards. |
| `plannerProductCategoryId` | `7` | Planner category id. |
| `scheduleOnRoadmap` | `true` | Put cards on the Planner roadmap by urgency. Set `false` to leave them Proposed and "Not scheduled". |
| `defaultTargetDays` | `30` | Fallback target-date offset. |
