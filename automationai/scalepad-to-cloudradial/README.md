# ScalePad to CloudRadial Migration

A CloudRadial **AutomationAI agent** that migrates a partner's **ScalePad Lifecycle Manager** data into their CloudRadial portal — warranty/lifecycle backfill, vCIO roadmap initiatives, and a policy specification for the parts that have no API.

## Download & import

**Download the agent:** [`scalepad-to-cloudradial.agent.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/scalepad-to-cloudradial/scalepad-to-cloudradial.agent.yml)

In AutomationAI: **Agents → Custom → Import**, upload the `.yml` (import is keyed on the slug `scalepad-to-cloudradial`). Make sure these extensions are installed and connected:

- **`lifecycle-manager`** — the ScalePad extension (third-party; needs `ScalePad-ApiUrl` / `ScalePad-ApiKey`, and a **Lifecycle Manager Pro or higher** tenant, or the LM endpoints return 402).
- **`cloudradial-v2-companies`**, **`cloudradial-v2-services`**, **`cloudradial-v2-endpoints`**.

It runs **dry by default**. Before the first production run, prove one `cr_create_product` write manually, and don't enable auto-approve until a create has succeeded.

## What it does

1. **Phase 1 — warranty & lifecycle backfill** (the priority): writes ScalePad warranty dates onto CloudRadial endpoints, prioritising non-Dell/Lenovo devices (the data CloudRadial can't pull natively and that's lost when the ScalePad subscription lapses).
2. **Phase 2 — roadmap import:** ScalePad initiatives → CloudRadial Planner items (`Product`), idempotent by subject, imported **unscheduled / Proposed** so a human schedules them at the QBR.
3. **Phase 3 — policy specification (report only):** DMI can't be migrated, so it reports the ScalePad insight definitions as a policy spec for a human to configure.

It **never writes to ScalePad**, and never creates a Product without first checking for an existing one.

## Variables

| Variable | Default | What it does |
|---|---|---|
| `partnerName` | *(required)* | The partner being migrated. |
| `defaultPriority` | `Low` | Priority for ScalePad initiatives with priority None. |
| `setClientScoring` | `false` | Whether to set Client Scoring points on imported Planner items. |
| `warrantyOnly` | `false` | Run the warranty backfill only (skip roadmap import). |
| `customPropertyPrefix` | `sp_` | Prefix for imported endpoint custom properties. |

## Region note

ScalePad Core / Lifecycle Manager are US-only (`https://api.scalepad.com`). Set the CloudRadial base URL to the partner's region (e.g. `https://api.eu.cloudradial.com` for EU portals).

**Requires:** AutomationAI + the ScalePad (`lifecycle-manager`) and CloudRadial extensions.
