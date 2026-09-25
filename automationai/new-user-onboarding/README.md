# New User Onboarding (agent)

A guarded onboarding **agent** that takes one new starter from request to ready for
day one. It's the brain behind the **New User Onboarding - Day One** playbook, which
calls it once per stage (`intake`, `procurement`, `access_plan`, `provision`,
`portal_training`, `verify`).

## Pieces

| File | Type | Role |
|---|---|---|
| [`form-webhook-mapping.md`](form-webhook-mapping.md) | Reference | How the CloudRadial *Add a New User* form maps, question by question, to the webhook JSON that starts the Day One playbook. |
| [`new-user-onboarding.agent.yml`](new-user-onboarding.agent.yml) | `automationsAgent` | The brain. Refuses privileged or sensitive group copies, purchases, changes to existing users and insecure credential handoff; reports what it verified, not what it attempted. Publish it → slug `new-user-onboarding`. |

## Install / run

1. Upload `new-user-onboarding.agent.yml` on **Agents → Custom** (import is keyed on the slug `new-user-onboarding`, so it overwrites an earlier copy).
2. Make sure these extensions are installed and connected: `connectwise-manage`, `microsoft-365`, `microsoft-entra-id`, `cloudradial-v2-companies`, `cloudradial-v2-training`, `1password-business`, `microsoft-teams`.
3. Set the agent variables: `credentialVault` (the 1Password vault for credential handoff — the agent stops rather than falling back to email or chat without it), `defaultLicenceSku`, `sensitiveGroupPatterns`, `hardwareBufferDays`, and `rmmPlatform` if the playbook checks device readiness.
4. Run it from the **New User Onboarding - Day One** playbook, or in the AI Playground with a `stage` and a `briefing`.

## Confirm in your tenant

- The 1Password extension slug is `1password-business` (earlier copies used `onepassword-business`, which doesn't exist in the catalog).
- Device/RMM readiness is deliberately not required — add `ninjaone-rmm-devices`, `datto-rmm` or `microsoft-intune` if you want it, and name it in `rmmPlatform`.
- The agent runs **dry-run by default** — see [Dry run and going live](#dry-run-and-going-live). Every mutating Microsoft 365, Entra and ConnectWise call is also approval-gated by the extension.

## Dry run and going live

`new-user-onboarding.agent.yml` ships with `dryRunDefault: true`. In dry run the agent does all its reads and shows you each write it *would* make, but changes nothing. AutomationAI has **no dry-run switch** on the workflow's Agent node, the deployment, or the agent's page. The setting lives only in the agent file, so going live means re-importing it:

1. Open `new-user-onboarding.agent.yml` and change `dryRunDefault: true` to `dryRunDefault: false`. Leave everything else the same.
2. On **Agents → Custom → Import**, upload the edited file. Import is keyed on the slug, so it replaces the installed agent in place. Workflows that use it pick up the change on their next run; nothing needs re-publishing.
3. Run once and confirm it's live: the verify stage should report accounts and tickets that actually exist, not planned ones. Mutating calls still wait for approval in the Inbox.
4. To go back to preview, set it to `true` and re-import.

The change applies to **every** workflow that uses this agent (the New User Onboarding - Day One playbook and any workflow that calls it). Keep the repo copy on `true`, so a fresh install always starts in preview.
