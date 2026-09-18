# Patch Compliance

A scheduled **workflow** that runs the shared **rmm-agent** to sweep Datto RMM patch status
and upsert one Planner card per client. This is one of the rmm-agent "commands" — see
[`../rmm-agent/README.md`](../rmm-agent/README.md) for the agent itself.

## Pieces

| File | Type | Role |
|---|---|---|
| [`patch-compliance.yml`](patch-compliance.yml) | `automationsWorkflow` | One agent node (`agentSlug: rmm-agent`, `autoApprove: true`). Lists Datto devices/sites, computes a per-site compliance %, matches sites → CloudRadial companies by normalized name, and upserts one "Patch Compliance Report" Planner card per matched company. |

## Install / run

1. Publish the agent from [`../rmm-agent`](../rmm-agent) (**Agents → Custom**, slug `rmm-agent`).
2. Import `patch-compliance.yml` on **Workflows → Import**.
3. Schedule it as a Routine (e.g. weekly).
4. Optional input `siteUid` restricts the run to one Datto site; omit for the whole fleet.

## Confirm in your tenant

- Extensions: `datto-rmm`, `cloudradial-v2-companies`, `cloudradial-v2-services`.
- `autoApprove: true` — card upserts only, no destructive actions.
- Unmatched sites are reported in the output (`unmatchedSites`), never force-matched.
