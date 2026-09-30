# Get New Hires Ready for Day One

Takes a new starter from request to ready: plans access from a similar user without copying privileged groups, raises quotes instead of buying, and hands over credentials securely.

**Formerly:** New User Onboarding (agent) | **Marketplace ID:** Not yet listed | **Type:** Agent

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `new-user-onboarding.agent.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/new-user-onboarding/new-user-onboarding.agent.yml) |
| Download `new-user-onboarding.agent.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/new-user-onboarding/new-user-onboarding.agent.yml) |
| View `form-webhook-mapping.md` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/new-user-onboarding/form-webhook-mapping.md) |
| Download `form-webhook-mapping.md` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/new-user-onboarding/form-webhook-mapping.md) |
| All files in this automation | [automationai/new-user-onboarding](https://github.com/cloudradial/Automations/tree/main/automationai/new-user-onboarding) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/new-user-onboarding) |

## How it works

A guarded onboarding **agent** that takes one new starter from request to ready for
day one, plus the **workflow** that runs it. The workflow reads the *Add a New User*
form's webhook and calls the agent once per stage, in order: `intake`, `procurement`,
`access_plan`, `provision`, `portal_training`, `verify`. The **New User Onboarding -
Day One** playbook runs the same stages.

> **Still in testing.** Keep the agent in dry run and every Agent node on
> `autoApprove: false` until a full run has been checked end to end.

## Pieces

| File | Type | Role |
|---|---|---|
| [`form-webhook-mapping.md`](form-webhook-mapping.md) | Reference | How the CloudRadial *Add a New User* form maps, question by question, to the webhook JSON that starts the Day One playbook. |
| [`new-user-onboarding.agent.yml`](new-user-onboarding.agent.yml) | `automationsAgent` | The brain. Refuses privileged or sensitive group copies, purchases, changes to existing users and insecure credential handoff; reports what it verified, not what it attempted. Publish it → slug `new-user-onboarding`. |
| [`new-user-onboarding.yml`](new-user-onboarding.yml) | `automationsWorkflow` | **Read the request** (turns the webhook body into the briefing and drops unanswered `@token` values) → six Agent nodes, one per stage. Each stage gets the briefing and the previous stage's output as `context`, and passes a block on instead of acting. |

## Install / run

1. Upload `new-user-onboarding.agent.yml` on **Agents → Custom** (import is keyed on the slug `new-user-onboarding`, so it overwrites an earlier copy).
2. Make sure these extensions are installed and connected: `connectwise-manage`, `microsoft-365`, `microsoft-entra-id`, `cloudradial-v2-companies`, `cloudradial-v2-training`, `1password-business`, `microsoft-teams`.
3. Set the agent variables: `credentialVault` (the 1Password vault for credential handoff — the agent stops rather than falling back to email or chat without it), `defaultLicenceSku`, `sensitiveGroupPatterns`, `hardwareBufferDays`, and `rmmPlatform` if the playbook checks device readiness.
4. On **Workflows → Import**, upload `new-user-onboarding.yml`. Enable the webhook under **Properties → Webhook**, then **Publish** and **deploy** it to your runner.
5. Point the *Add a New User* form's Webhook activity at the workflow's webhook URL, with the secret in the `X-Crauto-Webhook-Secret` header. The Content is the JSON in [form-webhook-mapping.md](form-webhook-mapping.md).
6. To test without the form, run the workflow from **Test** with a request body as the Trigger input. The **Read the request** node has a sample.

## Stages

| Node | Stage | What it does | Extensions allowed |
|---|---|---|---|
| Intake | `intake` | Names, start date, role, requester check, mirror-from user, ticket. No start date → blocked. | `connectwise-manage`, `cloudradial-v2-companies`, `microsoft-entra-id` |
| Procurement | `procurement` | Quote requests for hardware, phone and software. Never buys. | `connectwise-manage` |
| Access plan | `access_plan` | Access from the mirror-from user; privileged or sensitive groups go to `needsApproval`. | `microsoft-entra-id`, `microsoft-365` |
| Provision | `provision` | Account, licence, mailbox, approved access; credential only through 1Password. | `microsoft-entra-id`, `microsoft-365`, `1password-business`, `connectwise-manage` |
| Portal and training | `portal_training` | CloudRadial portal user and onboarding courses. | `cloudradial-v2-companies`, `cloudradial-v2-training` |
| Verify | `verify` | Checks what exists now, reports ready or not, notes the ticket. | all of the above plus `microsoft-teams` |

Every Agent node ships with `autoApprove: false`, so each change waits for approval in the Inbox. Each stage sees only the stage before it; **Verify** re-reads the live state rather than trusting earlier stages.

## Confirm in your tenant

- The 1Password extension slug is `1password-business` (earlier copies used `onepassword-business`, which doesn't exist in the catalog).
- Device/RMM readiness is deliberately not required, add `ninjaone-rmm-devices`, `datto-rmm` or `microsoft-intune` if you want it, and name it in `rmmPlatform`.
- The agent runs **dry-run by default**, see [Dry run and going live](#dry-run-and-going-live). Every mutating Microsoft 365, Entra and ConnectWise call is also approval-gated by the extension.

## Dry run and going live

`new-user-onboarding.agent.yml` ships with `dryRunDefault: true`. In dry run the agent does all its reads and shows you each write it *would* make, but changes nothing. AutomationAI has **no dry-run switch** on the workflow's Agent node, the deployment, or the agent's page. The setting lives only in the agent file, so going live means re-importing it:

1. Open `new-user-onboarding.agent.yml` and change `dryRunDefault: true` to `dryRunDefault: false`. Leave everything else the same.
2. On **Agents → Custom → Import**, upload the edited file. Import is keyed on the slug, so it replaces the installed agent in place. Workflows that use it pick up the change on their next run; nothing needs re-publishing.
3. Run once and confirm it's live: the verify stage should report accounts and tickets that actually exist, not planned ones. Mutating calls still wait for approval in the Inbox.
4. To go back to preview, set it to `true` and re-import.

The change applies to **every** workflow that uses this agent (the New User Onboarding - Day One playbook and any workflow that calls it). Keep the repo copy on `true`, so a fresh install always starts in preview.
