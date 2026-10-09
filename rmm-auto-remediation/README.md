# Fix Common Workstation Alerts Without a Technician

Workstation RMM alerts get a safe fix, a re-check and are resolved after you approve, and anything that can't be fixed safely becomes a PSA ticket.

**Formerly:** RMM Auto-Remediation | **Marketplace ID:** Not yet listed | **Type:** Workflow

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **RMM Agent** agent, [`rmm-agent.agent.yml`](https://github.com/cloudradial/Automations/blob/main/rmm-agent/rmm-agent.agent.yml) from [Safe Device Fixes and Patch Checks Through Your RMM](https://github.com/cloudradial/Automations/tree/main/rmm-agent), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`rmm-auto-remediation.yml`](https://github.com/cloudradial/Automations/blob/main/rmm-auto-remediation/rmm-auto-remediation.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `rmm-auto-remediation.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/rmm-auto-remediation/rmm-auto-remediation.yml) |
| Download `rmm-auto-remediation.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/rmm-auto-remediation/rmm-auto-remediation.yml) |
| Needs the agent | [RMM Agent](https://github.com/cloudradial/Automations/tree/main/rmm-agent) |
| All files in this automation | [rmm-auto-remediation](https://github.com/cloudradial/Automations/tree/main/rmm-auto-remediation) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/rmm-auto-remediation) |

## How it works

A webhook-triggered **workflow** that runs the shared **rmm-agent** to triage a Datto RMM
alert and, for a safe case, remediate it. This is one of the rmm-agent "commands", see
[`../rmm-agent/README.md`](https://github.com/cloudradial/Automations/tree/main/rmm-agent) for the agent itself.

## Pieces

| File | Type | Role |
|---|---|---|
| [`rmm-auto-remediation.yml`](https://github.com/cloudradial/Automations/blob/main/rmm-auto-remediation/rmm-auto-remediation.yml) | `automationsWorkflow` | One agent node (`agentSlug: rmm-agent`, `autoApprove: false`, you approve the fix). Reads the alert + device; **servers → open a PSA ticket, never remediate**; a workstation low-disk alert → run the cleanup component, poll to completion, re-check free space, then resolve the alert or open a ticket. |

## Install / run

1. Publish the agent from [`../rmm-agent`](https://github.com/cloudradial/Automations/tree/main/rmm-agent) (**Agents → Custom**, slug `rmm-agent`)
   and set its `cleanupComponentUid` variable on the deployment.
2. Import `rmm-auto-remediation.yml` on **Workflows → Import**.
3. Open **Properties → Webhook** and enable it (exports ship with it OFF), then point your
   Datto alert webhook at the generated hook.
4. Trigger payload: `alertUid` (required), plus `deviceUid` / `siteUid` (usually supplied).

## Confirm in your tenant

- Extensions: `datto-rmm`, `connectwise-manage` (set your real PSA slug if different).
- Dry run is set on the agent, not this workflow, see [Dry run and going live](https://github.com/cloudradial/Automations/blob/main/rmm-agent/README.md#dry-run-and-going-live). While the agent is in dry run, remediation only previews the cleanup job and ticket.
- `autoApprove: false`, the cleanup job and any ticket wait for your approval in the Inbox.
- **Safety:** servers are never auto-remediated (ticket only); technical detail stays in the
  internal note.
