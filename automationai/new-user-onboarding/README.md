# Get New Hires Ready for Day One

Takes a new starter from request to ready: plans access from a similar user without copying privileged groups, raises quotes instead of buying, and hands over credentials securely.

**Formerly:** New User Onboarding (agent) | **Marketplace ID:** Not yet listed | **Type:** Agent + Workflow

This folder has two ways to onboard. The agent workflow below plans and verifies each stage with AI. The [direct workflow](https://github.com/cloudradial/Automations/tree/main/automationai/new-user-onboarding#direct-workflow-create-a-new-hires-accounts-straight-from-the-form) does the same core account setup with PowerShell only and no AI.

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `new-user-onboarding.agent.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/new-user-onboarding/new-user-onboarding.agent.yml) |
| Download `new-user-onboarding.agent.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/new-user-onboarding/new-user-onboarding.agent.yml) |
| View `form-webhook-mapping.md` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/new-user-onboarding/form-webhook-mapping.md) |
| Download `form-webhook-mapping.md` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/new-user-onboarding/form-webhook-mapping.md) |
| View `new-user-onboarding-direct.yml` (no-AI workflow, see [below](https://github.com/cloudradial/Automations/tree/main/automationai/new-user-onboarding#direct-workflow-create-a-new-hires-accounts-straight-from-the-form)) | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/new-user-onboarding/new-user-onboarding-direct.yml) |
| Download `new-user-onboarding-direct.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/new-user-onboarding/new-user-onboarding-direct.yml) |
| Source for the PSA steps and the tests (`src/`, see [PSA](https://github.com/cloudradial/Automations/tree/main/automationai/new-user-onboarding#psa-both-workflows)) | [GitHub](https://github.com/cloudradial/Automations/tree/main/automationai/new-user-onboarding/src) |
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
| [`new-user-onboarding.yml`](new-user-onboarding.yml) | `automationsWorkflow` | **Read the request** (turns the webhook body into the briefing and drops unanswered `@token` values) → six Agent nodes, one per stage → **Note the ticket** (posts the result to the PSA ticket). Each stage gets the briefing and the previous stage's output as `context`, and passes a block on instead of acting. No Agent node calls the PSA, so the workflow works with any of the six PSAs. |
| [`src/`](src/) | Source and tests | `psa.ps1` holds the PSA calls both workflows use, and `build.js` pastes it into their PowerShell steps. `test.js` runs the strict-mode tests. Edit `psa.ps1`, never the block between the `src/psa.ps1` markers in a `.yml`. |

## Install / run

1. Upload `new-user-onboarding.agent.yml` on **Agents → Custom** (import is keyed on the slug `new-user-onboarding`, so it overwrites an earlier copy).
2. Make sure these extensions are installed and connected: `microsoft-365`, `microsoft-entra-id`, `cloudradial-v2-companies`, `cloudradial-v2-training`, `1password-business`, `microsoft-teams`. No PSA extension is needed.
3. For the ticket note, add `PSA-Type` and your PSA's secrets to the runner's Key Vault (see [PSA](#psa-both-workflows)), and deploy to that runner.
4. Set the agent variables: `credentialVault` (the 1Password vault for credential handoff — the agent stops rather than falling back to email or chat without it), `defaultLicenceSku`, `sensitiveGroupPatterns`, `hardwareBufferDays`, and `rmmPlatform` if the playbook checks device readiness.
5. On **Workflows → Import**, upload `new-user-onboarding.yml`. Enable the webhook under **Properties → Webhook**, then **Publish** and **deploy** it to your runner.
6. Point the *Add a New User* form's Webhook activity at the workflow's webhook URL, with the secret in the `X-Crauto-Webhook-Secret` header. The Content is the JSON in [form-webhook-mapping.md](form-webhook-mapping.md). Make the form changes it lists (Field IDs, the Manager question, the Security Groups and licence choices) in the package source, not in a client portal.
7. To test without the form, run the workflow from **Test** with a request body as the Trigger input. The **Read the request** node has a sample.
8. The ticket note is posted only when the request has `"confirm": "true"`. Without it, **Note the ticket** returns the note as `internal_note` and posts nothing. Add `"confirm": "true"` to the form's Content once you trust the runs.

## Stages

| Node | Stage | What it does | Extensions allowed |
|---|---|---|---|
| Intake | `intake` | Names, start date, role, requester check (from the CloudRadial requester fields and the client's CloudRadial users), mirror-from user, ticket. No start date → blocked. | `cloudradial-v2-companies`, `microsoft-entra-id` |
| Procurement | `procurement` | Lists quote requests for hardware, phone and software as `Quote:` items. Never buys. | none |
| Access plan | `access_plan` | Access from the mirror-from user; privileged or sensitive groups go to `needsApproval`. | `microsoft-entra-id`, `microsoft-365` |
| Provision | `provision` | Account, licence, mailbox, approved access; credential only through 1Password. | `microsoft-entra-id`, `microsoft-365`, `1password-business` |
| Portal and training | `portal_training` | CloudRadial portal user and onboarding courses. | `cloudradial-v2-companies`, `cloudradial-v2-training` |
| Verify | `verify` | Checks what exists now and reports each starter as ready or not. | `microsoft-entra-id`, `microsoft-365`, `cloudradial-v2-companies`, `cloudradial-v2-training`, `microsoft-teams` |
| Note the ticket | (PowerShell) | Posts one internal note to the form's ticket: the Verify result, the `Quote:` items, and anything that needs approval by name. Only when `confirm` is true. | none (calls the PSA directly) |

Every Agent node ships with `autoApprove: false`, so each change waits for approval in the Inbox. Each stage sees only the stage before it; **Verify** re-reads the live state rather than trusting earlier stages.

## Confirm in your tenant

- The 1Password extension slug is `1password-business` (earlier copies used `onepassword-business`, which doesn't exist in the catalog).
- Device/RMM readiness is deliberately not required, add `ninjaone-rmm-devices`, `datto-rmm` or `microsoft-intune` if you want it, and name it in `rmmPlatform`.
- The agent runs **dry-run by default**, see [Dry run and going live](#dry-run-and-going-live). Every mutating Microsoft 365 and Entra call is also approval-gated by the extension.

## PSA (both workflows)

The PSA writes happen in PowerShell steps, not in the agent, so both workflows work with **ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk**. Kaseya BMS has no working extension, so it couldn't work any other way. Each call is the one the PSA's catalog extension makes, or comes from the vendor's API docs. The secrets have the same names as each PSA's catalog extension, so one set of vault secrets serves both.

| Secret | Required | Value |
|---|---|---|
| `PSA-Type` | Yes, unless the request sends `psa` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk`. A runner with the `CW-*` secrets and no `PSA-Type` is treated as ConnectWise. |
| ConnectWise | If it's your PSA | `CW-ApiUrl` (including `/v4_6_release/apis/3.0`), `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` |
| Autotask | If it's your PSA | `Autotask-ApiUrl` (the zone host only, such as `https://webservices15.autotask.net`), `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret`. Optional: `Autotask-NotePublishId` and `Autotask-NoteTypeId`. |
| HaloPSA | If it's your PSA | `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret`. Optional: `Halo-NoteOutcomeId` (default 7, "Private Note"). |
| Kaseya BMS | If it's your PSA | `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, and **`KaseyaBMS-NoteTypeId`** (required, because note types are per tenant) |
| Syncro | If it's your PSA | `Syncro-ApiUrl` (`https://{sub}.syncromsp.com/api/v1`), `Syncro-ApiKey` |
| Zendesk | If it's your PSA | `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` |

How each PSA's note is kept internal:

| PSA | Call | Kept internal by |
|---|---|---|
| ConnectWise | `POST /service/tickets/{id}/notes` | `internalAnalysisFlag: true` |
| Autotask | `POST /Tickets/{id}/Notes`, titled "New user onboarding" | `publish` = "Internal Only". The `publish` and `noteType` ids differ per tenant, so they're read from `/TicketNotes/entityInformation/fields` by label, unless the two optional secrets set them. |
| HaloPSA | `POST /api/Actions` | `hiddenfromuser: true` |
| Kaseya BMS | `POST /v2/servicedesk/tickets/{id}/notes` | `IsInternal: true` |
| Syncro | `POST /tickets/{id}/comment` | `hidden: true`, `do_not_email: true` |
| Zendesk | `PUT /tickets/{id}` with a comment | `public: false` |

None of these notes has been posted to a real PSA from these workflows yet. The calls follow the catalog extensions and vendor docs and pass the mocked tests, so check the first note on each PSA by hand. The direct workflow's note contains the temporary password, so make sure it lands as internal before you set `confirm` to true.

## Dry run and going live

`new-user-onboarding.agent.yml` ships with `dryRunDefault: true`. In dry run the agent does all its reads and shows you each write it *would* make, but changes nothing. AutomationAI has **no dry-run switch** on the workflow's Agent node, the deployment, or the agent's page. The setting lives only in the agent file, so going live means re-importing it:

1. Open `new-user-onboarding.agent.yml` and change `dryRunDefault: true` to `dryRunDefault: false`. Leave everything else the same.
2. On **Agents → Custom → Import**, upload the edited file. Import is keyed on the slug, so it replaces the installed agent in place. Workflows that use it pick up the change on their next run; nothing needs re-publishing.
3. Run once and confirm it's live: the verify stage should report accounts and tickets that actually exist, not planned ones. Mutating calls still wait for approval in the Inbox.
4. To go back to preview, set it to `true` and re-import.

The change applies to **every** workflow that uses this agent (the New User Onboarding - Day One playbook and any workflow that calls it). Keep the repo copy on `true`, so a fresh install always starts in preview.


## Direct workflow: Create a New Hire's Accounts Straight From the Form

A submitted Add a New User form becomes a Microsoft 365 account with its licence, mailbox, groups and portal login, and the ticket gets a note of everything done. It checks the tenant first and never touches an existing account or grants admin access.

`new-user-onboarding-direct.yml` is a PowerShell-only workflow (no Agent nodes, no AI). Use it when you want predictable account creation from the form. Use the agent workflow above when you want access mirrored from a similar user, quotes raised and the result verified.

> **Untested in a live tenant.** Every node has been run against mocked Microsoft Graph, CloudRadial and PSA responses, but not against real ones. Keep `confirm` false until one preview and one live run have been checked end to end.

### How it works

One node per step, so each can be tested on its own:

| Node | What it does | Changes anything? |
|---|---|---|
| Receive form data | Reads the webhook body, flat `{key:value}` or the CloudRadial `{Ticket:{Questions:[...]},Company:{...}}` shape. Answers still left as `@token` count as not answered. | No |
| Check and plan | Fails closed on the checks under [Safety](https://github.com/cloudradial/Automations/tree/main/automationai/new-user-onboarding#safety). Resolves the sign-in name, manager, licence, groups and CloudRadial company, then writes the plan. Stops here with a preview when `confirm` is false. | No |
| Create Microsoft 365 user | Creates the account with a random 16-character temporary password (change forced at first sign-in) and sets the manager. | Yes |
| Assign licence and groups | Assigns the licence (Exchange Online creates the mailbox from it) and adds the approved groups. | Yes |
| Create portal user | Creates the CloudRadial portal user (`POST /v2/user`). | Yes |
| PSA ticket and manager | Uses the form's ticket. If there isn't one, it creates a ConnectWise ticket; with any other PSA it lists the ticket for a technician, because creating one needs queue and status ids that differ per tenant. Emails the manager that the account exists (no password). | Yes |
| Internal note and result | Builds the output and posts `internal_note` to the ticket as an internal note, in any of the six PSAs (see [PSA](https://github.com/cloudradial/Automations/tree/main/automationai/new-user-onboarding#psa-both-workflows)). | Yes, only when `confirm` is true |

It records the device type in the notes but doesn't order hardware. For quotes, use the agent workflow or [Split Request](https://github.com/cloudradial/Automations/tree/main/automationai/split-request-two-tickets).

### Requirements

No extensions. Every call is made from PowerShell with runner Key Vault secrets.

| Secret | Required | Used for |
|---|---|---|
| `M365-TenantId`, `M365-ClientId`, `M365-ClientSecret` | Yes | Microsoft Graph. The same secrets Password Reset uses (`Entra-*` and `Graph-*` names also work). |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | For the portal user | Without them the portal user is skipped and listed as follow-up. |
| `PSA-Type` and your PSA's secrets | For the ticket note | See [PSA](https://github.com/cloudradial/Automations/tree/main/automationai/new-user-onboarding#psa-both-workflows). Without them the note isn't posted, but it's still returned in `internal_note`. |
| `CW-ServiceBoard` | ConnectWise only, when the request has no ticket | The board for the new onboarding ticket. |
| `Onboarding-NotifySender` | No | A mailbox to email the manager from. Without it the manager isn't emailed. |
| `Onboarding-ProtectedGroupPatterns` | No | Extra comma-separated group name patterns to never add, on top of `admin`, `administrator`, `privileged` and `global`. |
| `Onboarding-DefaultLicenceSku` | No | The licence to use when the form says a licence is needed but none is chosen. Same values as `m365License`. Without it, the account gets no licence and a warning. |
| `Onboarding-UsageLocation` | No | Two-letter country code for new accounts, because the form doesn't ask for one. Without it, `US` is used. |

The Microsoft 365 app needs these Graph application permissions: `User.ReadWrite.All`, `GroupMember.ReadWrite.All`, `Organization.Read.All`, and `Mail.Send` if you set `Onboarding-NotifySender`. Password Reset confirmed the certified Microsoft 365 extension's app already has `User.ReadWrite.All`. The other three aren't verified yet, so check them in Entra before the first live run.


### Setup

1. On **Workflows → Import**, upload `new-user-onboarding-direct.yml`.
2. Add the secrets above to the runner's Key Vault. Deploy to the runner whose vault holds them.
3. Enable the webhook under **Properties → Webhook**, then **Publish** and **deploy**.
4. In the *Add a New User* form's automation, add a Webhook activity pointing at this workflow's webhook URL (it must be absolute), with the secret in the `X-Crauto-Webhook-Secret` header. Use the Content JSON from [form-webhook-mapping.md](https://github.com/cloudradial/Automations/blob/main/automationai/new-user-onboarding/form-webhook-mapping.md), plus the keys under Settings that you want to use.
5. The form's **Manager** question (Field ID `managerEmail`) sets and notifies the manager. Add it in the package source if your copy of the form doesn't have it yet. The Content in the mapping doc already includes `"managerEmail": "@managerEmail"`.
6. Leave `confirm` out of the Content at first, so every submission returns a preview. Once you trust the previews, add `"confirm": "true"` to the Content to let the form create accounts.

### Settings

Every input is optional apart from the name, and each has a default.

| Input | Default | Notes |
|---|---|---|
| `firstName`, `lastName` | none | Required. Missing either one returns `incomplete`. |
| `displayName` | first and last name | |
| `email` or `userPrincipalName` | built from `upnFormat` | Must be on a verified domain in the tenant. |
| `upnFormat` | `first.last` | Also `firstlast`, `flast` or `first`, at the tenant's default domain. Used only when no email is given. |
| `usageLocation` | `Onboarding-UsageLocation`, then `US` | Two-letter country code. A licence can't be assigned without it. Any other value stops the run. |
| `licenseSku` / `m365License` | `Onboarding-DefaultLicenceSku` when a licence is needed | A SKU id, a part number such as `SPB`, or a common name such as "Microsoft 365 Business Premium". `needsM365License: "No"` skips it. |
| `groups` / `securityGroups` / `mailGroups` | none | Names or ids, comma separated. Names must match the Entra display name exactly. It never copies a mirror-from user's groups. |
| `managerEmail` | none | The manager's email or UPN, from the form's Manager question. |
| `deviceType` / `newComputerType` | none | Recorded in the notes only. |
| `companyTenantId` | none | Send `@CompanyTenantId`. Required: a missing or different tenant is rejected. |
| `companyId`, `companyPsaId`, `companyName` | none | Used to match the CloudRadial company and, for a new ticket, the ConnectWise company. |
| `ticketId` | none | The form's ticket. Without it, a ConnectWise ticket is created; other PSAs list it for a technician. |
| `psa` | the `PSA-Type` secret | Which PSA the ticket is in. Overrides the secret for one request. |
| `confirm` (or `approvedToWrite`) | `false` | `false` returns a preview and changes nothing. |

### Safety

- Nothing changes unless `confirm` is `true`. A preview makes no writes, not even the ticket note.
- The request's `companyTenantId` must match this runner's `M365-TenantId`. If it's missing or different, the run is rejected.
- If the sign-in name is already used as a UPN, mail address or proxy address, the run is rejected. It never changes an existing account.
- It never assigns a directory role. It skips any group that is role-assignable or whose name matches a protected pattern, and lists it for a technician.
- It skips distribution lists, mail-enabled security groups and on-premises synced groups, which Graph can't change, and lists them for a technician.
- It never buys a licence. If the licence isn't in the tenant or has no free seat, the run stops before anything is created.
- The temporary password appears only in `internal_note`, which is also posted to the ticket as an internal note. It's never in `public_note`, `message` or the manager's email. Node outputs in the run history also carry it between steps, so limit who can see workflow runs.
- It warns when the requester isn't a portal admin for the client (`requestedByIsAdmin` is false).

### Output

| Field | Contents |
|---|---|
| `status` | `success`, `pending_confirmation` (preview), `incomplete` (partly done or missing input), `rejected` (a safety check failed) or `error` |
| `message`, `public_note` | Client-safe summary. No password. |
| `internal_note` | For technicians: what ran, the result, what needs a technician, warnings, and the temporary password when an account was created. |
| `ticket_id` | The form's ticket, or the one created |
| `upn`, `user_id` | The new account |
| `plan` | What the run would do (filled on a preview) |
| `actions`, `warnings`, `followUp` | Every action taken, anything worth checking, and anything left for a technician |
| `counts` | `accountsCreated`, `licencesAssigned`, `groupsAdded`, `portalUsersCreated` |

### Test before production

1. Run the workflow from **Test** with the sample Trigger input on **Receive form data**. Change `companyTenantId` to your test tenant id first. With `confirm` false it should return `pending_confirmation` and a plan, and write nothing.
2. Check the plan: the sign-in name, the licence, which groups are added, and which are left for a technician.
3. Run it once with `"confirm": "true"` for a throwaway test user. Check the account, licence, mailbox, groups, portal user and the ticket note, then delete the test user.
4. Submit the real form once with `confirm` left out, and check the preview shows real values instead of `@token` text.
5. Scheduled runs don't apply. This workflow runs from the form webhook.