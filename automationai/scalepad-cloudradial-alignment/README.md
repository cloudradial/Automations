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
| [`scalepad-to-cloudradial-migration-map.md`](scalepad-to-cloudradial-migration-map.md) | grounding doc | Section-by-section map (ScalePad → CloudRadial home → API/import route → policy-evaluable?). Attach in a Knowledge folder and ground the agent on it. |

## Install / run

1. Upload `scalepad-cloudradial-alignment.agent.yml` on **Agents → Custom** (publishes slug
   `scalepad-cloudradial-alignment`).
2. Put `scalepad-to-cloudradial-migration-map.md` in a **Knowledge** folder and ground the
   agent on it (Agents → this agent → Knowledge).
3. Import `scalepad-cloudradial-alignment.yml` on **Workflows → Import**.
4. **First run:** `mode: plan`, one company — by `companyId`, or `scalePadClientName` for the
   crosswalk. Review the `planned` array + `policySpecification`, then re-run `mode: apply`
   and approve writes in the Inbox.

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
- **Grounding:** if `knowledge_search` returns an error, the agent runs without the map —
  confirm the Knowledge grounding is attached before relying on a run.
- The agent runs **dry-run by default**; turn it off on the deployment when ready. Warranty/EOL
  writes go to endpoint `expirationDate` directly (never `update-warranty`).
