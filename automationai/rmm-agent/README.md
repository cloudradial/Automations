# RMM Agent (Datto) + command workflows

A reusable Datto RMM operations **agent**, plus two thin **workflows** that each run
it with a goal — the "a command that uses the agent" pattern (a `type: agent` node
with a `goal` + `agentSlug`, exactly like the ScalePad migration workflow).

## Pieces

| File | Type | Role |
|---|---|---|
| [`rmm-agent.agent.yml`](rmm-agent.agent.yml) | `automationsAgent` | The brain. Safety-first system prompt, knows the Datto tools, matches sites→CloudRadial companies, upserts Planner cards. Publish it → slug `rmm-agent`. |
| [`../rmm-auto-remediation/rmm-auto-remediation.yml`](../rmm-auto-remediation/rmm-auto-remediation.yml) | `automationsWorkflow` | **Command: remediate.** Webhook-triggered by a Datto alert; one agent node, `autoApprove: false` (you approve the fix). |
| [`../patch-compliance/patch-compliance.yml`](../patch-compliance/patch-compliance.yml) | `automationsWorkflow` | **Command: patch compliance.** Scheduled; one agent node that sweeps patch status and upserts one Planner card per client. |

The **Datto RMM extension already exists in AutomationAI** (`datto-rmm`, MSPTechPro) —
these reference it, they don't redefine it. Its tools auth via OAuth2 (handled by the
extension); secrets are `Datto-ApiUrl` / `Datto-ApiKey` / `Datto-ApiSecret`.

## Install / run

1. Upload `rmm-agent.agent.yml` on **Agents → Custom** (publishes slug `rmm-agent`).
2. Import both workflows on **Workflows → Import**.
3. Set the agent variables on deploy — `cleanupComponentUid` (the Datto cleanup
   component's UID, from its web-UI URL), `diskFreeThresholdGb`, `autoRemediateServers`.
4. **Patch compliance:** schedule the *Patch Compliance* workflow (Routine) — e.g. weekly.
5. **Remediation:** after import, open the workflow's **Properties → Webhook** and toggle **Enable webhook** on (exports must ship with it OFF or the import breaks), then point your Datto alert webhook at the generated hook.

## Confirm in your tenant

- Extension slugs: `datto-rmm` (confirmed), `cloudradial-v2-companies` /
  `cloudradial-v2-services` (confirmed from the migration workflow), and your PSA
  extension slug (`connectwise-manage` is a placeholder — set your real CW slug).
- The agent runs **dry-run by default**; turn it off on the deployment when ready.
- Remediation keeps `autoApprove: false` so the cleanup job and any ticket need your
  approval. Patch compliance uses `autoApprove: true` (card upserts only).
