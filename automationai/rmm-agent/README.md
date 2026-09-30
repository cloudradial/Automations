# Safe Device Fixes and Patch Checks Through Your RMM

The shared engine behind the device fix and patch compliance automations. It works through Datto RMM, matches sites to clients, and never acts without approval.

**Formerly:** RMM Agent (Datto) + command workflows | **Marketplace ID:** Not yet listed | **Type:** Agent

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `rmm-agent.agent.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/rmm-agent/rmm-agent.agent.yml) |
| Download `rmm-agent.agent.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/rmm-agent/rmm-agent.agent.yml) |
| All files in this automation | [automationai/rmm-agent](https://github.com/cloudradial/Automations/tree/main/automationai/rmm-agent) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/rmm-agent) |
| Works with | [Fix Common Workstation Alerts Without a Technician](https://github.com/cloudradial/Automations/tree/main/automationai/rmm-auto-remediation) |
| Works with | [Show Every Client's Patch Compliance in Their Planner](https://github.com/cloudradial/Automations/tree/main/automationai/patch-compliance) |

## How it works

A reusable RMM operations **agent** that uses the partner's RMM extension to resolve
issues automatically, plus thin **workflows** that each run it with a goal for one
trigger: an RMM alert webhook, a ServiceAI Triage Action on a ticket, or a schedule.
Each workflow is a `type: agent` node with a `goal` + `agentSlug` (the same pattern as
[Weekly Fleet Audit](../weekly-fleet-audit/)).

This build uses the **Datto RMM** extension (`datto-rmm`). To support another RMM, add
its extension slug to the agent's `requiredExtensionSlugs` and the workflow node's
`allowedExtensions`, and adjust the tool names in the system prompt.

## Pieces

| File | Type | Role |
|---|---|---|
| [`rmm-agent.agent.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/rmm-agent/rmm-agent.agent.yml) | `automationsAgent` | The brain. Safety-first system prompt, knows the Datto tools, matches sites→CloudRadial companies, upserts Planner cards. Publish it → slug `rmm-agent`. |
| [`../rmm-auto-remediation/rmm-auto-remediation.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/rmm-auto-remediation/rmm-auto-remediation.yml) | `automationsWorkflow` | **Command: remediate.** Webhook-triggered by a Datto alert; one agent node, `autoApprove: false` (you approve the fix). |
| [`../patch-compliance/patch-compliance.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/patch-compliance/patch-compliance.yml) | `automationsWorkflow` | **Command: patch compliance.** Scheduled; one agent node that sweeps patch status and upserts one Planner card per client. |

The **Datto RMM extension already exists in AutomationAI** (`datto-rmm`, MSPTechPro), these reference it, they don't redefine it. Its tools auth via OAuth2 (handled by the
extension); secrets are `Datto-ApiUrl` / `Datto-ApiKey` / `Datto-ApiSecret`.

## Install / run

1. Upload `rmm-agent.agent.yml` on **Agents → Custom** (publishes slug `rmm-agent`).
2. Import both workflows on **Workflows → Import**.
3. Set the agent variables on deploy, `cleanupComponentUid` (the Datto cleanup
   component's UID, from its web-UI URL), `diskFreeThresholdGb`, `autoRemediateServers`.
4. **Patch compliance:** schedule the *Patch Compliance* workflow (Routine), e.g. weekly.
5. **Remediation:** after import, open the workflow's **Properties → Webhook** and toggle **Enable webhook** on (exports must ship with it OFF or the import breaks), then point your Datto alert webhook at the generated hook.

## Confirm in your tenant

- Extension slugs: `datto-rmm` (confirmed), `cloudradial-v2-companies` /
  `cloudradial-v2-services` (confirmed from the migration workflow), and your PSA
  extension slug (`connectwise-manage`, the certified ConnectWise extension; swap it for `autotask-psa`, `halo-psa` or `syncro` if you use a different PSA).
- The agent runs **dry-run by default**, see [Dry run and going live](#dry-run-and-going-live).
- Remediation keeps `autoApprove: false` so the cleanup job and any ticket need your
  approval. Patch compliance uses `autoApprove: true` (card upserts only).

## Dry run and going live

`rmm-agent.agent.yml` ships with `dryRunDefault: true`. In dry run the agent does all its reads and shows you each write it *would* make, but changes nothing. AutomationAI has **no dry-run switch** on the workflow's Agent node, the deployment, or the agent's page. The setting lives only in the agent file, so going live means re-importing it:

1. Open `rmm-agent.agent.yml` and change `dryRunDefault: true` to `dryRunDefault: false`. Leave everything else the same.
2. On **Agents → Custom → Import**, upload the edited file. Import is keyed on the slug, so it replaces the installed agent in place. Workflows that use it pick up the change on their next run; nothing needs re-publishing.
3. Run once and confirm it's live: Patch Compliance should report `cardsWritten` of 1 or more and `cardsPreviewed: 0`. RMM Auto-Remediation stays approval-gated either way (`autoApprove: false`), so its live fixes still wait for you in the Inbox.
4. To go back to preview, set it to `true` and re-import.

The change applies to **every** workflow that uses this agent (Patch Compliance and RMM Auto-Remediation). Keep the repo copy on `true`, so a fresh install always starts in preview.
