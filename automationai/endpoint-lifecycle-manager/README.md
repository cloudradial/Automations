# Endpoint LifeCycle Manager

A CloudRadial **AutomationAI agent** that reviews managed computers per company and maintains one **Planner card per refresh category** — Replace, Plan replacement, Upgrade in place, Retain, Needs data, Human review, Virtual machines — each carrying a triage priority and listing that category's devices in plain language.

## Scope — CloudRadial portal only

This agent uses **only the CloudRadial portal's endpoints** — both **workstations and servers** (servers route to *Human review*, VMs to their own track). It needs **no RMM and no ScalePad** connection; every decision comes from native endpoint fields already in CloudRadial.

It is a **separate automation** from:
- *Endpoint Warranty Report* (**AAI-00021**) — the older warranty-focused report, and
- the **ScalePad → CloudRadial** lifecycle sync (**AAI-00030**), which brings *external* warranty/EOL data in.

Use this one when the source of truth is the CloudRadial portal itself.

## Download & import

**Download the agent:** [`endpoint-lifecycle-manager.agent.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager.agent.yml)

In AutomationAI: **Agents → Custom → Import**, upload the `.yml` (import is keyed on the slug `endpoint-warranty-refresh-advisor-planner-cards`). Run it on a **Routine** (scheduled); it takes no runtime input.

**Requires:** AutomationAI + these CloudRadial extensions installed and connected:
- `cloudradial-v2-endpoints` — read endpoints (workstations **and** servers)
- `cloudradial-v2-services` — read / create / update the Planner cards

## What it does

- Reads **native endpoint fields** (age from manufacture date, warranty expiry, OS, Windows 11 readiness, SSD/HDD, RAM, server/VM flags) and routes each computer through first-match decision tracks.
- Creates/updates **one card per (company, category)** via `cr_create_product` / `cr_patch_product`, reconciled by subject so re-runs update in place.
- Writes plain-language card bodies grouped by priority tier (Critical/High/Medium/Low).
- All decision logic is inline in the prompt — it does **not** call knowledge search or depend on grounding.

## Heads-up: this agent always writes

It has **no preview mode** (`dryRunDefault: false`) — every in-scope company with out-of-spec computers gets its cards created/updated. If you drive it from a workflow's Agent node, decide deliberately whether to enable **auto-approve**.

## Variables

| Variable | Default | What it does |
|---|---|---|
| `companyIds` | `1` | Companies to process — comma list (`1,4,7`) or blank for all. |
| `plannerCategory` | `Efficiency` | Planner category name for the cards. |
| `plannerProductCategoryId` | `7` | Planner category id. |
| `defaultTargetDays` | `30` | Fallback target-date offset. |
