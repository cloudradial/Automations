# Review Messy ScalePad Data Before You Migrate

Optional. When ScalePad data is messy, it matches clients and plans the move so you can approve a reviewed plan before the migration runs.

**Formerly:** ScalePad → CloudRadial Alignment | **Marketplace ID:** Not yet listed | **Type:** Agent + Workflow

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **ScalePad to CloudRadial Alignment** agent, [`scalepad-cloudradial-alignment.agent.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/scalepad-cloudradial-alignment/scalepad-cloudradial-alignment.agent.yml), on **Agents → Custom → Import**.
2. Import [`scalepad-cloudradial-alignment.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/scalepad-cloudradial-alignment/scalepad-cloudradial-alignment.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `scalepad-cloudradial-alignment.yml` (start here) | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/scalepad-cloudradial-alignment/scalepad-cloudradial-alignment.yml) |
| Download `scalepad-cloudradial-alignment.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/scalepad-cloudradial-alignment/scalepad-cloudradial-alignment.yml) |
| View `scalepad-cloudradial-alignment.agent.yml` (agent) | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/scalepad-cloudradial-alignment/scalepad-cloudradial-alignment.agent.yml) |
| Download `scalepad-cloudradial-alignment.agent.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/scalepad-cloudradial-alignment/scalepad-cloudradial-alignment.agent.yml) |
| View `knowledge/scalepad-to-cloudradial-migration-map.md` (upload to Knowledge) | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/scalepad-cloudradial-alignment/knowledge/scalepad-to-cloudradial-migration-map.md) |
| Download `knowledge/scalepad-to-cloudradial-migration-map.md` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/scalepad-cloudradial-alignment/knowledge/scalepad-to-cloudradial-migration-map.md) |
| All files in this automation | [automationai/scalepad-cloudradial-alignment](https://github.com/cloudradial/Automations/tree/main/automationai/scalepad-cloudradial-alignment) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/scalepad-cloudradial-alignment) |

## How it works

> **Optional.** A migration only needs the [ScalePad to CloudRadial Sync](https://github.com/cloudradial/Automations/tree/main/automationai/scalepad-cloudradial-sync) workflow. Use this agent when the data is messy, unclear client matches, devices typed wrong, conflicting warranty dates, and you want a reviewed plan before applying.

The **judgment** half of a ScalePad Lifecycle Manager → CloudRadial migration: an **agent** that matches clients, reads both sides and returns a plan, plus a thin **workflow** that runs it with a goal. Grounded on a migration map so its field-level decisions are traceable.

The **bulk** half, devices, servers, installed software, assessments, roadmap and budget, deliverable PDFs, is the deterministic [ScalePad to CloudRadial Sync](https://github.com/cloudradial/Automations/tree/main/automationai/scalepad-cloudradial-sync) workflow, which follows every ScalePad page. The agent tells you what the sync will move and what needs a human; it makes at most 10 corrections itself.

It needs the `lifecycle-manager` (ScalePad) extension at **1.2.0 or later**: 1.0.0 returns only the first page of every ScalePad list.

## Pieces

| File | Type | Role |
|---|---|---|
| [`scalepad-cloudradial-alignment.agent.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/scalepad-cloudradial-alignment/scalepad-cloudradial-alignment.agent.yml) | `automationsAgent` | The brain (v0.2.7). Reads ScalePad and CloudRadial, maps each item to its home, and returns a plan: one entry per phase for the Sync workflow (with the inputs to run), grouped skips, and up to 10 direct corrections. Publish it → slug `scalepad-cloudradial-alignment`. Dry-run by default. |
| [`scalepad-cloudradial-alignment.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/scalepad-cloudradial-alignment/scalepad-cloudradial-alignment.yml) | `automationsWorkflow` | **Command: align.** One agent node, `autoApprove: false` (you approve each write). Static goal — the agent reads `mode`/`phase`/company from its input bag. |
| [`knowledge/scalepad-to-cloudradial-migration-map.md`](https://github.com/cloudradial/Automations/blob/main/automationai/scalepad-cloudradial-alignment/knowledge/scalepad-to-cloudradial-migration-map.md) | Knowledge | Section-by-section map (ScalePad → CloudRadial home → API/import route → policy-evaluable?), the endpoint field map, and the guardrails. Upload to Knowledge and ground the workflow's agent node on it. |

## Install / run

1. Upload `scalepad-cloudradial-alignment.agent.yml` on **Agents → Custom** (publishes slug
   `scalepad-cloudradial-alignment`).
2. Upload `knowledge/scalepad-to-cloudradial-migration-map.md` to a **Knowledge** folder.
3. Import `scalepad-cloudradial-alignment.yml` on **Workflows → Import**.
4. **Turn on grounding.** Open the workflow's agent node → **Ground on knowledge** → attach the
   map. Set **topK to about 10**, and use **Preview recall** to check that the endpoint field
   map and guardrails sections come back. Grounding lives on the node, not the agent, and
   can't be exported, so every install does this step.
5. **First run:** `mode: plan`, one company, by `companyId`, or `scalePadClientName` for the
   crosswalk. Review the `planned` array + `policySpecification`, then re-run `mode: apply`
   and approve writes in the Inbox.

## Run inputs

Nothing to wire after import. The workflow's **Run inputs** step reads the **Trigger input** box of the Run dialog (or a Routine's input), leaving it empty is fine, fills in every default, and is already bound to the agent's inputs. To change a run, send any of these fields as JSON, for example `{"companyId": 9, "mode": "plan"}`, and leave the rest out. An empty run plans for up to three crosswalked clients.

Every input is optional, the agent never stops to ask. Defaults are shown.

| Input | Default | Notes |
|---|---|---|
| `companyId` |, | CloudRadial company to align. |
| `scalePadClientName` |, | Or name the ScalePad client; it's matched through the crosswalk. |
| `mode` | `plan` | `apply` writes approved changes, and only when a company is named, a portfolio-wide `apply` runs as `plan`. |
| `phase` | `all` | Which phase to review, the Sync's names: `devices`, `assets`, `software`, `assessments`, `roadmap`, `archive`. All of them come from the APIs. |
| `createPlaceholders` | `false` | Kept for compatibility. Missing devices are created by the Sync workflow (`createMissingDevices`); the agent flags any that look wrong first. |
| `maxCompanies` | `3` | With no company named, how many crosswalked clients to plan for. |

Example first run: `{"mode":"plan","companyId":1,"phase":"devices"}`

**What it hands to the Sync workflow.** For devices, assets, software, assessments, roadmap and archive the plan carries one `planned` entry with `action: "workflow"` and the count, plus a single **`syncRun`**, the exact run input for the Sync, for example `{"companyId":9,"scalePadClientId":"…","mode":"plan","phases":"all"}`. Paste it as the Sync's run input. `phases` only ever uses the Sync's six names, initiatives and contracts are `roadmap`, deliverable PDFs are `archive`.

**Flexible assets come from ScalePad.** ScalePad hardware that isn't an endpoint — network, mobile and imaging devices — and devices with no serial number go to one flexible asset type per kind of device (**Network Devices**, **Mobile Devices**, **Printers & Imaging**, and so on) through the Sync's `assets` phase. For a one-off fix the agent uses the `cloudradial-v2-compliance` tools (0.2.1 or later — 0.2.0's `cr_patch_flexible_asset` can't change anything). No IT Glue tooling is involved.

## Confirm in your tenant

- **Extension slugs:** `lifecycle-manager` (ScalePad), `cloudradial-v2-companies`,
  `cloudradial-v2-endpoints`, `cloudradial-v2-services` — confirmed from the LifeCycle Manager
  migration workflow — and `cloudradial-v2-compliance` (flexible assets; 0.2.1 or later).
- **ScalePad paging:** with the catalog `lifecycle-manager` 1.0.0 every list returns only its first page, so counts come out low. Check the installed version is 1.2.0 or later.
- **Company mapping:** confirm the client resolves to a real client company, **not
  `companyId 1`** (the partner's own record). Check `clientsMapped[].matchConfidence`; if it
  falls back to 1 or lands in `unresolvedClients`, pass an explicit `companyId`.
- **Grounding:** the map only reaches the agent when the node's **Ground on knowledge** is on
  and the document's embedding status is *ready*. Without it the agent runs on its prompt
  alone, confirm with **Preview recall** before relying on a run. (As of 2026-09-25 the
  map in Nick's Test shows embedding *failed*, recall returns HTTP 500, and the node has
  grounding off.)
- The agent runs **dry-run by default**, see [Dry run and going live](#dry-run-and-going-live). Warranty/EOL
  writes go to endpoint `expirationDate` directly (never `update-warranty`).

## Dry run and going live

`scalepad-cloudradial-alignment.agent.yml` ships with `dryRunDefault: true`. In dry run the agent does all its reads and shows you each write it *would* make, but changes nothing. AutomationAI has **no dry-run switch** on the workflow's Agent node, the deployment, or the agent's page. The setting lives only in the agent file, so going live means re-importing it:

1. Open `scalepad-cloudradial-alignment.agent.yml` and change `dryRunDefault: true` to `dryRunDefault: false`. Leave everything else the same.
2. On **Agents → Custom → Import**, upload the edited file. Import is keyed on the slug, so it replaces the installed agent in place. Workflows that use it pick up the change on their next run; nothing needs re-publishing.
3. Run once and confirm it's live: any direct corrections (at most 10) should show as applied, not planned. Writes still need approval unless the Agent node has auto-approve on. Bulk changes always go through the Sync workflow, which has its own `mode`.
4. To go back to preview, set it to `true` and re-import.

The change applies to **every** workflow that uses this agent (the ScalePad to CloudRadial Alignment workflow). Keep the repo copy on `true`, so a fresh install always starts in preview.
