# Fix Common Workstation Alerts Without a Technician

Workstation RMM alerts get a safe fix, a re-check and are resolved after you approve, and anything that can't be fixed safely becomes a ticket in your PSA: ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro or Zendesk.

**Formerly:** RMM Auto-Remediation | **Marketplace ID:** AAI-00036 | **Type:** Workflow (agent plus one PowerShell step) | **Version:** 1.1.0

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/rmm-auto-remediation/v1.1.0).

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **RMM Agent** agent, [`rmm-agent.agent.yml`](https://github.com/cloudradial/Automations/blob/main/rmm-agent/rmm-agent.agent.yml) from [Safe Device Fixes and Patch Checks Through Your RMM](https://github.com/cloudradial/Automations/tree/main/rmm-agent), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`rmm-auto-remediation.yml`](https://github.com/cloudradial/Automations/blob/main/rmm-auto-remediation/rmm-auto-remediation.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `rmm-auto-remediation.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/rmm-auto-remediation/rmm-auto-remediation.yml) |
| Download `rmm-auto-remediation.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/rmm-auto-remediation/v1.1.0) |
| Needs the agent | [RMM Agent](https://github.com/cloudradial/Automations/tree/main/rmm-agent) (1.1.0 or later) |
| Source of the ticket step | [`src/`](https://github.com/cloudradial/Automations/tree/main/rmm-auto-remediation/src): `ticket.ps1`, `build.js`, `test.ps1` |
| All files in this automation | [rmm-auto-remediation](https://github.com/cloudradial/Automations/tree/main/rmm-auto-remediation) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/rmm-auto-remediation) |

## How it works

A webhook-triggered **workflow** that runs the shared **rmm-agent** to triage a Datto RMM
alert and, for a safe case, remediate it. The agent never opens tickets: when an alert needs a
person it returns the ticket text, and the **Open PSA ticket** step opens it in whichever of the
six PSAs the runner uses (`_shared/psa.ps1`). This is one of the rmm-agent "commands", see
[`../rmm-agent/README.md`](https://github.com/cloudradial/Automations/tree/main/rmm-agent) for the agent itself.

## Pieces

| File | Type | Role |
|---|---|---|
| [`rmm-auto-remediation.yml`](https://github.com/cloudradial/Automations/blob/main/rmm-auto-remediation/rmm-auto-remediation.yml) | `automationsWorkflow` | Built by `src/build.js`. **Agent** node (`agentSlug: rmm-agent`, `autoApprove: false`, you approve the fix, extensions `datto-rmm` and `cloudradial-v2-companies`): reads the alert and device; **servers are escalated, never remediated**; a workstation low-disk alert runs the cleanup component, polls to completion, re-checks free space, then resolves the alert or escalates. Any other alert is escalated. **Open PSA ticket** (PowerShell, `src/ticket.ps1`): when the agent escalates, opens the ticket and adds the technical detail as an internal note. |
| [`src/`](https://github.com/cloudradial/Automations/tree/main/rmm-auto-remediation/src) | source | `ticket.ps1` (edit this, then `node src/build.js`), `build.js`, and `test.ps1` (strict-mode checks on all six PSAs). |

## Install / run

1. Publish the agent from [`../rmm-agent`](https://github.com/cloudradial/Automations/tree/main/rmm-agent) (**Agents → Custom**, slug `rmm-agent`)
   and set its `cleanupComponentUid` variable on the deployment.
2. Import `rmm-auto-remediation.yml` on **Workflows → Import**.
3. Open **Properties → Webhook** and enable it (exports ship with it OFF), then point your
   Datto alert webhook at the generated hook.
4. Trigger payload: `alertUid` (required), plus `deviceUid` / `siteUid` (usually supplied).
5. Runner Key Vault secrets for the ticket step:
   - `PSA-Type` (`connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk`) and that PSA's secrets, the same names as its catalog extension (see `_shared/psa.ps1`).
   - `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey`, so the client's CloudRadial company name can be matched to its PSA company.
   - Optional `PSA-CompanyId`: a catch-all PSA company (for example your own) used when the client's company can't be matched. Without it, an unmatched alert fails the step so it isn't missed.
   - Optional `PSA-ServiceQueue`: the board, queue, team, issue type or group for the ticket.

## Confirm in your tenant

- Extensions: `datto-rmm` and `cloudradial-v2-companies` on the agent node. No PSA extension is needed: the ticket step calls the PSA's API with the runner secrets above.
- **Company matching for the ticket:** the CloudRadial company the agent matched (by name in the PSA), then the Datto site name, then `PSA-CompanyId`.
- Dry run is set on the agent, not this workflow, see [Dry run and going live](https://github.com/cloudradial/Automations/blob/main/rmm-agent/README.md#dry-run-and-going-live). While the agent is in dry run, remediation only previews the cleanup job, and the ticket step only says which ticket it would open.
- `autoApprove: false`, the cleanup job waits for your approval in the Inbox. The escalation ticket is opened by the PowerShell step without a second approval, so an alert that needs a person always reaches your PSA.
- **Safety:** servers are never auto-remediated (ticket only); technical detail stays in the
  internal note.

## Tested

- `src/test.ps1`: 46 strict-mode checks on the ticket step, run exactly as it is in the `.yml`: a ticket on each of the six PSAs on the client's matched company, wrapped agent output, no escalation, dry run, the site-name and `PSA-CompanyId` fallbacks, an unmatched company, a missing PSA, missing ticket fields and unreadable agent output.
- Not yet run live. The PSA calls come from `_shared/psa.ps1`; those marked `Unverified` there haven't been proven by a live run, so run the agent in dry run first and check the first real ticket in your PSA.
