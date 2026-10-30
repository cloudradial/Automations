# Show Every Client's Patch Compliance in Their Planner

Each client gets a current patch compliance score and a plain list of the devices that need attention, right in their Planner. It's ready for your next review meeting, with no spreadsheet to build.

## What happens

On a schedule you choose (weekly works well), the automation checks the patch status of every device in Datto RMM. For each client it works out a compliance score and writes one card in that client's Planner, called "Patch Compliance Report".

The card says, in plain sentences:

- the client's compliance score
- which devices have patches on the way
- which devices failed to install patches
- which devices have no patch policy at all (a setup gap to fix)
- which devices sent no patch information, so someone can check them

Each run updates the same card, so the Planner always shows the latest picture instead of piling up old cards.

## What it protects

- **Fair scores.** Network devices, printers and ESXi hosts can't be patched, so they're left out of every score. Devices that sent no patch information are listed, never counted as failing.
- **No guessing which client is which.** If a Datto site can't be matched to a client, it's skipped and listed in the run results for you to sort out.
- **Nothing is deleted or changed in Datto.** It only reads patch status and writes the one Planner card per client.
- **A safe first run.** The RMM Agent starts in preview mode, so you can see what it would write before any card is created.

## Works with

- **Datto RMM:** the only RMM it reads patch status from.
- **Autotask:** if your Datto and Autotask integration is on, sites are matched to clients using the Autotask company. Otherwise it matches by company name.
- Datto's built-in Managed and OnDemand sites are left out unless you match them to a client yourself.

## What you need

- AutomationAI, with Datto RMM and CloudRadial connected
- The **RMM Agent** (from Safe Device Fixes and Patch Checks Through Your RMM), up to date
- Your clients set up as companies in CloudRadial

## Set it up

1. Import the [RMM Agent](https://github.com/cloudradial/Automations/tree/main/rmm-agent) on **Agents > Custom > Import**, if you don't have it yet. If you do, make sure it's the latest version.
2. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/patch-compliance/v1.0.0).
3. Go to **Workflows > Import** and upload it.
4. Click **Publish**, then **Deploy**.
5. Schedule it as a weekly **Routine**.
6. Run it once while the RMM Agent is still in preview mode. Check that it would write one card for each client.
7. Take the RMM Agent out of preview mode. The [RMM Agent guide](https://github.com/cloudradial/Automations/blob/main/rmm-agent/README.md#dry-run-and-going-live) shows how.

**Optional settings.** You can run it for a single Datto site instead of your whole fleet. If a site's name doesn't match its client in CloudRadial, you can tell the RMM Agent which client that site belongs to.

**Test it.** Run it twice, then open a client's Planner and check there's one "Patch Compliance Report" card, updated by the second run rather than duplicated.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/patch-compliance#technical-details) cover how devices are sorted, how sites are matched to clients, and what the run reports back.

---

## Technical details

**Formerly:** Patch Compliance | **Marketplace ID:** AAI-00035 | **Type:** Workflow | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/patch-compliance/v1.0.0).

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **RMM Agent** agent, [`rmm-agent.agent.yml`](https://github.com/cloudradial/Automations/blob/main/rmm-agent/rmm-agent.agent.yml) from [Safe Device Fixes and Patch Checks Through Your RMM](https://github.com/cloudradial/Automations/tree/main/rmm-agent), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`patch-compliance.yml`](https://github.com/cloudradial/Automations/blob/main/patch-compliance/patch-compliance.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `patch-compliance.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/patch-compliance/patch-compliance.yml) |
| Download `patch-compliance.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/patch-compliance/v1.0.0) |
| Needs the agent | [RMM Agent](https://github.com/cloudradial/Automations/tree/main/rmm-agent) |
| All files in this automation | [patch-compliance](https://github.com/cloudradial/Automations/tree/main/patch-compliance) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/patch-compliance) |

## How it works

A scheduled **workflow** that runs the shared **rmm-agent** to sweep Datto RMM patch status
and upsert one Planner card per client. This is one of the rmm-agent "commands", see
[`../rmm-agent/README.md`](https://github.com/cloudradial/Automations/tree/main/rmm-agent) for the agent itself.

## Pieces

| File | Type | Role |
|---|---|---|
| [`patch-compliance.yml`](https://github.com/cloudradial/Automations/blob/main/patch-compliance/patch-compliance.yml) | `automationsWorkflow` | One agent node (`agentSlug: rmm-agent`, `autoApprove: true`). Lists Datto devices/sites, sorts each device into compliant / pending / failing / no policy / no data / not patchable, computes a per-site compliance %, matches sites → CloudRadial companies (site map, then Autotask company id, then exact normalized name), and upserts exactly one "Patch Compliance Report" Planner card per matched company. |

## Install / run

1. Publish the agent from [`../rmm-agent`](https://github.com/cloudradial/Automations/tree/main/rmm-agent) (**Agents → Custom**, slug `rmm-agent`).
2. Import `patch-compliance.yml` on **Workflows → Import**.
3. Schedule it as a Routine (e.g. weekly).
4. Optional input `siteUid` restricts the run to one Datto site; omit for the whole fleet.
5. Optional agent variable `siteCompanyMap` (JSON, e.g. `{"Contoso": 42}`) forces a Datto site onto a CloudRadial company id when neither the PSA id nor the name matches.
6. First run: leave dry run on and check that `cardsPreviewed` is 1 per matched company. Then go live, dry run is set on the agent, not this workflow; see [Dry run and going live](https://github.com/cloudradial/Automations/blob/main/rmm-agent/README.md#dry-run-and-going-live), run twice, and confirm the second run updates the same card instead of adding one.

## Confirm in your tenant

- Extensions: `datto-rmm`, `cloudradial-v2-companies`, `cloudradial-v2-services`.
- `autoApprove: true`, card upserts only, no destructive actions.
- Unmatched sites are reported in the output (`unmatchedSites`), never force-matched. Datto's built-in Managed / OnDemand sites stay unmatched unless you map them.
- Network devices, printers and ESXi hosts are counted as `notPatchable` and left out of every score; devices with no patch data are listed as `noData`, not failing.
- `cardsWritten` counts writes that actually ran; `cardsPreviewed` counts dry-run previews.
- PSA-id matching reads `autotaskCompanyId` from the Datto site and `psaIdentifier` from the CloudRadial company, confirm your Datto sites carry it (it's set when the Datto ↔ Autotask integration is on).
- Needs `rmm-agent` **0.4.1** or later.
