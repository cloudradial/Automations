# ScalePad → CloudRadial Alignment

A reusable **agent** that maps a client's ScalePad Lifecycle Manager data to its CloudRadial
home, plus a thin **workflow** that runs it with a goal — the "a command that uses the agent"
pattern (a `type: agent` node with a `goal` + `agentSlug`, same shape as the RMM agent and the
LifeCycle Manager migration workflow). Grounded on a migration map so its field-level
decisions are traceable.

## Pieces

| File | Type | Role |
|---|---|---|
| [`scalepad-cloudradial-alignment.agent.yml`](scalepad-cloudradial-alignment.agent.yml) | `automationsAgent` | The brain. Reads ScalePad + current CloudRadial state, maps each item to its home, produces a plan (writes only on approval). Publish it → slug `scalepad-cloudradial-alignment`. Dry-run by default. |
| [`scalepad-cloudradial-alignment.yml`](scalepad-cloudradial-alignment.yml) | `automationsWorkflow` | **Command: align.** One agent node, `autoApprove: false` (you approve each write). Static goal — the agent reads `mode`/`phase`/company from its input bag. |
| [`knowledge/scalepad-to-cloudradial-migration-map.md`](knowledge/scalepad-to-cloudradial-migration-map.md) | Knowledge | Section-by-section map (ScalePad → CloudRadial home → API/import route → policy-evaluable?), the endpoint field map, and the guardrails. Upload to Knowledge and ground the workflow's agent node on it. |

## Install / run

1. Upload `scalepad-cloudradial-alignment.agent.yml` on **Agents → Custom** (publishes slug
   `scalepad-cloudradial-alignment`).
2. Upload `knowledge/scalepad-to-cloudradial-migration-map.md` to a **Knowledge** folder.
3. Import `scalepad-cloudradial-alignment.yml` on **Workflows → Import**.
4. **Turn on grounding.** Open the workflow's agent node → **Ground on knowledge** → attach the
   map. Set **topK to about 10**, and use **Preview recall** to check that the endpoint field
   map and guardrails sections come back. Grounding lives on the node, not the agent, and
   can't be exported, so every install does this step.
5. **First run:** `mode: plan`, one company — by `companyId`, or `scalePadClientName` for the
   crosswalk. Review the `planned` array + `policySpecification`, then re-run `mode: apply`
   and approve writes in the Inbox.

## Run inputs

Every input is optional — the agent never stops to ask. Defaults are shown.

| Input | Default | Notes |
|---|---|---|
| `companyId` | — | CloudRadial company to align. |
| `scalePadClientName` | — | Or name the ScalePad client; it's matched through the crosswalk. |
| `mode` | `plan` | `apply` writes approved changes, and only when a company is named — a portfolio-wide `apply` runs as `plan`. |
| `phase` | `all` | `warranty`, `software`, `roadmap` run from the APIs. `assessments`, `archive` and IT Glue `flexible-assets` need source files (below). |
| `createPlaceholders` | `false` | Create placeholder endpoints for ScalePad assets the portal doesn't have (tagged Source = ScalePad). |
| `maxCompanies` | `3` | With no company named, how many crosswalked clients to plan for. |
| `flexibleAssetTypeFilter` | — | Limit flexible-asset sync to these type names. |

Example first run: `{"mode":"plan","companyId":1,"phase":"warranty"}`

**Data the APIs can't reach** — the agent lists these in `unmapped` with what's needed:

| Phase | Source to supply |
|---|---|
| Assessments | The ScalePad assessment Excel export, for CloudRadial's assessment upload |
| Archive | Historical QBR PDFs, for the report archive (API, archive email or drag-drop) |
| Flexible assets | IT Glue flexible assets — sync with the IT Glue → CloudRadial PowerShell script (support KB 49183488579860) |

## Confirm in your tenant

- **Extension slugs:** `lifecycle-manager` (ScalePad), `cloudradial-v2-companies`,
  `cloudradial-v2-endpoints`, `cloudradial-v2-services` — confirmed from the LifeCycle Manager
  migration workflow.
- **Missing-phase caveat:** the flexible-assets / assessments / archive phases need
  extensions that expose those tools. A plan run without them reports those items as
  `unmapped` (toolset constraint), not an error — add the extensions to enable those phases.
- **Company mapping:** confirm the client resolves to a real client company, **not
  `companyId 1`** (the partner's own record). Check `clientsMapped[].matchConfidence`; if it
  falls back to 1 or lands in `unresolvedClients`, pass an explicit `companyId`.
- **Grounding:** the map only reaches the agent when the node's **Ground on knowledge** is on
  and the document's embedding status is *ready*. Without it the agent runs on its prompt
  alone — confirm with **Preview recall** before relying on a run. (As of 2026-09-25 the
  map in Nick's Test shows embedding *failed*, recall returns HTTP 500, and the node has
  grounding off.)
- The agent runs **dry-run by default** — see [Dry run and going live](#dry-run-and-going-live). Warranty/EOL
  writes go to endpoint `expirationDate` directly (never `update-warranty`).

## Dry run and going live

`scalepad-cloudradial-alignment.agent.yml` ships with `dryRunDefault: true`. In dry run the agent does all its reads and shows you each write it *would* make, but changes nothing. AutomationAI has **no dry-run switch** on the workflow's Agent node, the deployment, or the agent's page. The setting lives only in the agent file, so going live means re-importing it:

1. Open `scalepad-cloudradial-alignment.agent.yml` and change `dryRunDefault: true` to `dryRunDefault: false`. Leave everything else the same.
2. On **Agents → Custom → Import**, upload the edited file. Import is keyed on the slug, so it replaces the installed agent in place. Workflows that use it pick up the change on their next run; nothing needs re-publishing.
3. Run once and confirm it's live: the run should report the endpoint, software and Planner writes it applied, not an apply-plan. Writes still need approval unless the Agent node has auto-approve on.
4. To go back to preview, set it to `true` and re-import.

The change applies to **every** workflow that uses this agent (the ScalePad to CloudRadial Alignment workflow). Keep the repo copy on `true`, so a fresh install always starts in preview.
