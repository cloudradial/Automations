# RMM Auto-Remediation

A webhook-triggered **workflow** that runs the shared **rmm-agent** to triage a Datto RMM
alert and, for a safe case, remediate it. This is one of the rmm-agent "commands" — see
[`../rmm-agent/README.md`](../rmm-agent/README.md) for the agent itself.

## Pieces

| File | Type | Role |
|---|---|---|
| [`rmm-auto-remediation.yml`](rmm-auto-remediation.yml) | `automationsWorkflow` | One agent node (`agentSlug: rmm-agent`, `autoApprove: false` — you approve the fix). Reads the alert + device; **servers → open a PSA ticket, never remediate**; a workstation low-disk alert → run the cleanup component, poll to completion, re-check free space, then resolve the alert or open a ticket. |

## Install / run

1. Publish the agent from [`../rmm-agent`](../rmm-agent) (**Agents → Custom**, slug `rmm-agent`)
   and set its `cleanupComponentUid` variable on the deployment.
2. Import `rmm-auto-remediation.yml` on **Workflows → Import**.
3. Open **Properties → Webhook** and enable it (exports ship with it OFF), then point your
   Datto alert webhook at the generated hook.
4. Trigger payload: `alertUid` (required), plus `deviceUid` / `siteUid` (usually supplied).

## Confirm in your tenant

- Extensions: `datto-rmm`, `connectwise-manage` (set your real PSA slug if different).
- `autoApprove: false` — the cleanup job and any ticket wait for your approval in the Inbox.
- **Safety:** servers are never auto-remediated (ticket only); technical detail stays in the
  internal note.
