# Patch Compliance

A scheduled **workflow** that runs the shared **rmm-agent** to sweep Datto RMM patch status
and upsert one Planner card per client. This is one of the rmm-agent "commands" — see
[`../rmm-agent/README.md`](../rmm-agent/README.md) for the agent itself.

## Pieces

| File | Type | Role |
|---|---|---|
| [`patch-compliance.yml`](patch-compliance.yml) | `automationsWorkflow` | One agent node (`agentSlug: rmm-agent`, `autoApprove: true`). Lists Datto devices/sites, sorts each device into compliant / pending / failing / no policy / no data / not patchable, computes a per-site compliance %, matches sites → CloudRadial companies (site map, then Autotask company id, then exact normalized name), and upserts exactly one "Patch Compliance Report" Planner card per matched company. |

## Install / run

1. Publish the agent from [`../rmm-agent`](../rmm-agent) (**Agents → Custom**, slug `rmm-agent`).
2. Import `patch-compliance.yml` on **Workflows → Import**.
3. Schedule it as a Routine (e.g. weekly).
4. Optional input `siteUid` restricts the run to one Datto site; omit for the whole fleet.
5. Optional agent variable `siteCompanyMap` (JSON, e.g. `{"Woodward Labs": 42}`) forces a Datto site onto a CloudRadial company id when neither the PSA id nor the name matches.
6. First run: leave dry run on and check that `cardsPreviewed` is 1 per matched company. Then go live — dry run is set on the agent, not this workflow; see [Dry run and going live](../rmm-agent/README.md#dry-run-and-going-live) — run twice, and confirm the second run updates the same card instead of adding one.

## Confirm in your tenant

- Extensions: `datto-rmm`, `cloudradial-v2-companies`, `cloudradial-v2-services`.
- `autoApprove: true` — card upserts only, no destructive actions.
- Unmatched sites are reported in the output (`unmatchedSites`), never force-matched. Datto's built-in Managed / OnDemand sites stay unmatched unless you map them.
- Network devices, printers and ESXi hosts are counted as `notPatchable` and left out of every score; devices with no patch data are listed as `noData`, not failing.
- `cardsWritten` counts writes that actually ran; `cardsPreviewed` counts dry-run previews.
- PSA-id matching reads `autotaskCompanyId` from the Datto site and `psaIdentifier` from the CloudRadial company — confirm your Datto sites carry it (it's set when the Datto ↔ Autotask integration is on).
- Needs `rmm-agent` **0.4.1** or later.
