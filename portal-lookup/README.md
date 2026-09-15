# Portal Lookup (agent)

Read-only CloudRadial **custom agent** that assembles a portal briefing — company footprint, users, endpoints, and health gaps — for meeting prep. Given a company it produces a call-ready summary; with no company it produces a portal-wide snapshot.

Converted from the CloudRadial UCP marketplace item **CRA-00014 (Portal Lookup)**. This is an *agent* (`automationsAgent: 1`), not a deterministic workflow, because the task is analytical and open-ended.

## Install

1. In AutomationAI: **Agents → Custom → Import** and upload [`portal-lookup.agent.yml`](portal-lookup.agent.yml). Import is keyed on the `slug` (`cloudradial-portal-lookup`).
2. Ensure the required CloudRadial read extensions are installed + connected (they're first-party and auto-install):
   - `cloudradial-v2-companies`, `cloudradial-v2-users`, `cloudradial-v2-endpoints`.
3. Run it. Optionally pass a `companyName` (or `cloudradialCompanyId`); leave the goal as-is or paste it into the Goal field.

## Behavior

- **Strictly read-only** — never calls a create/update/delete tool, so there's no approval gate.
- **Self-sources** — needs no required input; `companyName` is an optional filter.
- Briefs on: company identity + account manager + PSA linkage + setup gaps; user count and roles; endpoint inventory and warranty posture (expired / expiring within `warrantyWindowDays`, default 90); anything unconfigured or stale.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `warrantyWindowDays` | `90` | Window for counting endpoints as "expiring soon" in the briefing. |

## Notes / limits

- **Extension coverage is the ceiling.** This agent uses the *typed* `cloudradial-v2-*` extension tools, not the UCP plugin's generic `raw_api_call`. If you want KB/catalog or service data in the briefing, add the corresponding content/service extension slugs to `requiredExtensionSlugs` — provided a typed tool exists for what you need.
- Custom agents need a **goal** to run (it's set both as the top-level `goal:` field and in the system prompt). If your uploader rejects the `goal:` field, remove that line and paste the same text into the Goal field at run time.
