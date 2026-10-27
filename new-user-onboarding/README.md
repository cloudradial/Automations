# Get New Hires Ready for Day One

Your clients ask for a new starter in the portal, and AutomationAI takes it from request to ready for day one: account, access, quotes for equipment, portal login and training, with a note on the ticket that says what is done and what still needs your team.

## What your clients see in the portal

**They fill in the Add a New User form.** Name, start date, role, which coworker the new person should match, and any equipment or software they need.

**They get a ticket, as usual.** Behind the scenes the request is checked and worked through in stages. Your technicians see the full result as an internal note on that same ticket.

## What happens behind the scenes

- **Checks the request.** A request with no start date stops here.
- **Raises quotes, never buys.** Hardware, phones and software are listed as quote requests for your team.
- **Plans access from a similar coworker.** Admin and other sensitive groups are never copied without approval.
- **Sets up the account.** Microsoft 365 account, licence, mailbox and the approved access.
- **Hands over the password safely.** Only through 1Password, never by email or chat.
- **Adds portal access and training.** A UCP portal login and your onboarding courses.
- **Double checks.** A final step looks at what really exists and reports each starter as ready or not.
- **Can start your other workflows,** such as Split Request to raise the service ticket and the quote.

## What it protects

- **Nothing happens without you.** It starts in preview, and every change waits for approval in your AutomationAI Inbox.
- **Existing users are never changed.**
- **The requester can't be faked.** Who asked, and for which client, comes from the portal, never from a typed answer.

## Works with

ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk, for the ticket note.

- **All PSAs:** the note hasn't been posted to a live PSA yet, so check the first one by hand.
- **Kaseya BMS:** you also choose which note type to use.

This automation is still in testing. Keep it in preview until a full run has been checked from start to finish.

## What you need

- Microsoft 365 and Microsoft Entra ID, connected in AutomationAI
- CloudRadial, 1Password Business and Microsoft Teams, connected in AutomationAI
- A 1Password vault for handing over new passwords
- Your PSA connected on your AutomationAI runner, for the ticket note
- A UCP portal with **Actions** on your request forms

## Set it up

**Once, in AutomationAI:**

1. **Download** both files from the [release page](https://github.com/cloudradial/Automations/releases/tag/new-user-onboarding/v1.1.0).
2. Go to **Agents > Custom > Import** and upload the New User Onboarding agent first.
3. In the agent's settings, pick your 1Password vault and your default licence.
4. Go to **Workflows > Import** and upload the workflow.
5. Click **Publish**, then **Deploy**.

**In your UCP portal:**

1. Open the **Add a New User** form.
2. At the end of the form, add an **Action** question and pick **New User Onboarding**.

**Test it.** Submit the form once as a client user and check the preview note on the ticket. Switch to live only once you trust the results.

Prefer no AI? A simpler version creates the same accounts straight from the form, without quotes or access mirroring. It's in the same folder.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/new-user-onboarding#technical-details) cover each stage, going live, the simpler no-AI version and every setting.

---

## Technical details

**Formerly:** New User Onboarding (agent) | **Marketplace ID:** AAI-00040 | **Type:** Agent + Workflow | **Version:** 1.1.0

This folder has two ways to onboard. The agent workflow below plans and verifies each stage with AI. The [direct workflow](https://github.com/cloudradial/Automations/tree/main/new-user-onboarding#direct-workflow-create-a-new-hires-accounts-straight-from-the-form) does the same core account setup with PowerShell only and no AI.

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/new-user-onboarding/v1.1.0).

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **New User Onboarding** agent, [`new-user-onboarding.agent.yml`](https://github.com/cloudradial/Automations/blob/main/new-user-onboarding/new-user-onboarding.agent.yml), on **Agents → Custom → Import**.
2. Import [`new-user-onboarding.yml`](https://github.com/cloudradial/Automations/blob/main/new-user-onboarding/new-user-onboarding.yml) on **Workflows → Import**.

**Optional:** [`new-user-onboarding-direct.yml`](https://github.com/cloudradial/Automations/blob/main/new-user-onboarding/new-user-onboarding-direct.yml) on **Workflows → Import**, with no agent needed. See How it works for when to use it.

| What | Link |
|---|---|
| View `new-user-onboarding.yml` (start here) | [GitHub](https://github.com/cloudradial/Automations/blob/main/new-user-onboarding/new-user-onboarding.yml) |
| Download `new-user-onboarding.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/new-user-onboarding/v1.1.0) |
| View `new-user-onboarding.agent.yml` (agent) | [GitHub](https://github.com/cloudradial/Automations/blob/main/new-user-onboarding/new-user-onboarding.agent.yml) |
| Download `new-user-onboarding.agent.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/new-user-onboarding/v1.1.0) |
| View `new-user-onboarding-direct.yml` (optional) | [GitHub](https://github.com/cloudradial/Automations/blob/main/new-user-onboarding/new-user-onboarding-direct.yml) |
| Download `new-user-onboarding-direct.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/new-user-onboarding/v1.1.0) |
| View `form-webhook-mapping.md` | [GitHub](https://github.com/cloudradial/Automations/blob/main/new-user-onboarding/form-webhook-mapping.md) |
| All files in this automation | [new-user-onboarding](https://github.com/cloudradial/Automations/tree/main/new-user-onboarding) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/new-user-onboarding) |
| Source (for maintainers) | [src/](https://github.com/cloudradial/Automations/tree/main/new-user-onboarding/src) |

## How it works

A guarded onboarding **agent** that takes one new starter from request to ready for
day one, plus the **workflow** that runs it. The *Add a New User* form starts the
workflow, either through an **Action** question or a Webhook activity. The workflow calls
the agent once per stage, in order: `intake`, `procurement`, `access_plan`, `provision`,
`portal_training`, `verify`.

The workflow can also start **other workflows** at two points, after intake and after
provision, through their webhooks. Split Request - Service + Quote can raise the service
ticket and the quote, and you can add your own, such as a group or device set-up
workflow, without editing this one. See [Hand-offs to other workflows](#hand-offs-to-other-workflows).

The **New User Onboarding - Day One** playbook runs the same stages, but a form can't
start a playbook yet (AutomationAI request AAI-143), so the workflow is the one to use
with the form.

> **Still in testing.** Keep the agent in dry run and every Agent node on
> `autoApprove: false` until a full run has been checked end to end.

## Pieces

| File | Type | Role |
|---|---|---|
| [`form-webhook-mapping.md`](https://github.com/cloudradial/Automations/blob/main/new-user-onboarding/form-webhook-mapping.md) | Reference | How the CloudRadial *Add a New User* form maps, question by question, to the webhook JSON that starts the Day One playbook. |
| [`new-user-onboarding.agent.yml`](https://github.com/cloudradial/Automations/blob/main/new-user-onboarding/new-user-onboarding.agent.yml) | `automationsAgent` | The brain. Refuses privileged or sensitive group copies, purchases, changes to existing users and insecure credential handoff; reports what it verified, not what it attempted. Publish it → slug `new-user-onboarding`. |
| [`new-user-onboarding.yml`](https://github.com/cloudradial/Automations/blob/main/new-user-onboarding/new-user-onboarding.yml) | `automationsWorkflow` | **Read the request** (turns the form's Action input or webhook body into the briefing and drops unanswered `@token` values) → six Agent nodes, one per stage, with a **Hand off** step after Intake and after Provision → **Note the ticket** (posts the result to the PSA ticket). Each stage gets the briefing and the previous stage's output as `context`, and passes a block on instead of acting. No Agent node calls the PSA, so the workflow works with any of the six PSAs. |
| [`src/`](https://github.com/cloudradial/Automations/tree/main/new-user-onboarding/src) | Source and tests | The PSA calls come from the shared library [`_shared/psa.ps1`](https://github.com/cloudradial/Automations/blob/main/_shared/psa.ps1), pasted into the PowerShell steps by `node _shared/inject.js new-user-onboarding`. `test.js` checks those blocks are current and runs the strict-mode tests. Edit `_shared/psa.ps1`, never the block between the `_shared/psa.ps1` markers in a `.yml`. |

## Install / run

1. Upload `new-user-onboarding.agent.yml` on **Agents → Custom** (import is keyed on the slug `new-user-onboarding`, so it overwrites an earlier copy).
2. Make sure these extensions are installed and connected: `microsoft-365`, `microsoft-entra-id`, `cloudradial-v2-companies`, `cloudradial-v2-training`, `1password-business`, `microsoft-teams`. No PSA extension is needed.
3. For the ticket note, add `PSA-Type` and your PSA's secrets to the runner's Key Vault (see [PSA](#psa-both-workflows)), and deploy to that runner.
4. Set the agent variables: `credentialVault` (the 1Password vault for credential handoff; the agent stops rather than falling back to email or chat without it), `defaultLicenceSku`, `sensitiveGroupPatterns`, `hardwareBufferDays`, and `rmmPlatform` if the playbook checks device readiness.
5. On **Workflows → Import**, upload `new-user-onboarding.yml`, then **Publish** and **deploy** it to your runner.
6. Start it from the *Add a New User* form, in one of two ways:
   - **Action (portals with Actions):** add a question of type **Action** at the end of the form and pick **New User Onboarding**. Nothing to map. The portal sends each answer under its Field ID, plus its own `ticket`, `company` and `user` objects. **Read the request** takes the ticket, the client (name, PSA id, Microsoft 365 tenant) and the requester (name, email, PSA contact) from those objects only. The stock form's Field IDs work as they are (for example `modelTheNewUsersAccountAccessFrom`, `doesTheUserRequireAnEmailAccount`, `mailDistributionGroups`, and the long equipment IDs CloudRadial cuts at 40 characters). An unanswered question arrives empty, and a choice list driven by an unset company token (such as `@CompanyComputerChoices`) arrives as the token text. Both are listed as "Not answered", so set those company tokens if you use those questions.
   - **Webhook activity:** enable the webhook under **Properties → Webhook**, and point the form's Webhook activity at the workflow's webhook URL, with the secret in the `X-Crauto-Webhook-Secret` header. The Content is the JSON in [form-webhook-mapping.md](https://github.com/cloudradial/Automations/blob/main/new-user-onboarding/form-webhook-mapping.md). Make the form changes it lists (Field IDs, the Manager question, the Security Groups and licence choices) in the package source, not in a client portal.

   Either way, the requester and the client come only from what CloudRadial fills in, never from a typed answer.
7. To test without the form, run the workflow from **Test** with a request body as the Trigger input. The **Read the request** node has a sample.
8. Nothing is written (no ticket note, no hand-off) until the request is **confirmed**. Without it, **Note the ticket** returns the note as `internal_note`, and the hand-off steps list what they would start. To confirm:
   - **Webhook activity:** add `"confirm": "true"` to the form's Content once you trust the runs.
   - **Action:** an Action can't send extra fields, so set the runner secret `NewUserOnboarding-Confirm` to `true` instead. That makes every run on that runner live, so set it only once a test run has been checked. On an Action, form answers named `confirm`, `psa` or `requestedBy` are ignored, so a question can't confirm a run, pick the PSA or change the requester.

### Microsoft 365 secrets stored per company

Sometimes a client's Microsoft 365 secrets (`M365-TenantID`, `M365-ClientID` and `M365-ClientSecret`) are saved under the company in AutomationAI (**Companies**, policy *Require company*) instead of in the runner vault. In that case, open the workflow in the designer and set **Company** to that client on these steps: **Check and plan**, **Create Microsoft 365 user**, **Assign licence and groups** and **PSA ticket and manager**. Then publish and deploy.

- **Set it again after every import.** Importing a workflow clears the step Company setting, because the `.yml` doesn't carry it.
- **Without it,** the steps use the runner's shared secrets, so they sign in to the wrong tenant or fail.

## Stages

| Node | Stage | What it does | Extensions allowed |
|---|---|---|---|
| Intake | `intake` | Names, start date, role, requester check (from the CloudRadial requester fields and the client's CloudRadial users), mirror-from user, ticket. No start date → blocked. | `cloudradial-v2-companies`, `microsoft-entra-id` |
| Hand off after intake | (PowerShell) | Starts the workflows in `NewUserOnboarding-AfterIntake`, by default Split Request - Service + Quote. Only when confirmed. | none (webhooks) |
| Procurement | `procurement` | Lists quote requests for hardware, phone and software as `Quote:` items. Never buys. | none |
| Access plan | `access_plan` | Access from the mirror-from user; privileged or sensitive groups go to `needsApproval`. | `microsoft-entra-id`, `microsoft-365` |
| Provision | `provision` | Account, licence, mailbox, approved access; credential only through 1Password. | `microsoft-entra-id`, `microsoft-365`, `1password-business` |
| Hand off after provision | (PowerShell) | Starts the workflows in `NewUserOnboarding-AfterProvision`, for example group or device set-up. Only when confirmed. | none (webhooks) |
| Portal and training | `portal_training` | CloudRadial portal user and onboarding courses. | `cloudradial-v2-companies`, `cloudradial-v2-training` |
| Verify | `verify` | Checks what exists now and reports each starter as ready or not. | `microsoft-entra-id`, `microsoft-365`, `cloudradial-v2-companies`, `cloudradial-v2-training`, `microsoft-teams` |
| Note the ticket | (PowerShell) | Posts one internal note to the form's ticket: the Verify result, the `Quote:` items, anything that needs approval by name, and the other workflows it started. Only when confirmed. | none (calls the PSA directly) |

Every Agent node ships with `autoApprove: false`, so each change waits for approval in the Inbox. Each stage sees only the stage before it; **Verify** re-reads the live state rather than trusting earlier stages.

## Hand-offs to other workflows

AutomationAI has no step that runs another workflow, so the two **Hand off** steps start other workflows through their webhooks. Add a workflow here instead of editing this one.

| Runner secret | Value |
|---|---|
| `NewUserOnboarding-AfterIntake` | Names of the workflows to start after Intake, comma separated, letters and digits only (for example `SplitRequest`). |
| `NewUserOnboarding-AfterProvision` | Names of the workflows to start after Provision (for example `AddToGroup`). |
| `NewUserOnboarding-<Name>-Url` | That workflow's full webhook URL (**Properties → Webhook** on that workflow, with its webhook enabled). Must start with `https://`. |
| `NewUserOnboarding-<Name>-Secret` | That workflow's webhook secret, sent in the `X-Crauto-Webhook-Secret` header. |

- **Split Request by default.** With no `NewUserOnboarding-AfterIntake` list, setting `NewUserOnboarding-SplitRequest-Url` (and its `-Secret`) is enough to start [Split Request - Service + Quote](https://github.com/cloudradial/Automations/tree/main/split-request-two-tickets) after intake. On its form profile, the stock form's computer question needs the Field ID `deviceType` (see that README).
- **What each workflow receives:** the same request the form sent (so a workflow built for the *Add a New User* form reads it unchanged), plus an `onboarding` block with `stage`, `starter`, `startDate`, `ticketId` and `briefing`.
- **Started, not finished.** A webhook starts a run and returns straight away. The step records each run id, and **Note the ticket** lists them. Each of those runs reports its own result in its own run history.
- **Only when confirmed.** Before that, the steps list what they would start. A workflow that can't be started (missing URL, `http://` address, the call refused) is a warning, and onboarding carries on.
- Secret values never appear in the run output.

## Confirm in your tenant

- The 1Password extension slug is `1password-business` (earlier copies used `onepassword-business`, which doesn't exist in the catalog).
- Device/RMM readiness is deliberately not required, add `ninjaone-rmm-devices`, `datto-rmm` or `microsoft-intune` if you want it, and name it in `rmmPlatform`.
- The agent runs **dry-run by default**, see [Dry run and going live](#dry-run-and-going-live). Every mutating Microsoft 365 and Entra call is also approval-gated by the extension.

## PSA (both workflows)

Both workflows use the shared PSA library, `_shared/psa.ps1`, the same code as the repo's other automations. It adds two things this workflow needs:

- **ConnectWise redirects are safe.** ConnectWise has answered note and ticket writes with a redirect after saving them. The library reads the ticket back instead of sending again, so the note holding the temporary password is never written twice or reported as failed.
- **Ticket numbers work.** A ticket number as the PSA shows it (for example an Autotask `T20261014.0001`) is turned into its id before the note is posted.

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
| Check and plan | Fails closed on the checks under [Safety](https://github.com/cloudradial/Automations/tree/main/new-user-onboarding#safety). Resolves the sign-in name, manager, licence, groups and CloudRadial company, then writes the plan. Stops here with a preview when `confirm` is false. | No |
| Create Microsoft 365 user | Creates the account with a random 16-character temporary password (change forced at first sign-in) and sets the manager. | Yes |
| Assign licence and groups | Assigns the licence (Exchange Online creates the mailbox from it) and adds the approved groups. | Yes |
| Create portal user | Creates the CloudRadial portal user (`POST /v2/user`). | Yes |
| PSA ticket and manager | Uses the form's ticket. If there isn't one, it creates the onboarding ticket in your PSA, for the company in `companyPsaId` (a PSA company id or ConnectWise identifier) or the exact `companyName`, on the `PSA-ServiceQueue` board or queue (ConnectWise also reads `CW-ServiceBoard`). If the company can't be matched or the PSA refuses, it's listed for a technician. Emails the manager that the account exists (no password). | Yes |
| Internal note and result | Builds the output and posts `internal_note` to the ticket as an internal note, in any of the six PSAs (see [PSA](https://github.com/cloudradial/Automations/tree/main/new-user-onboarding#psa-both-workflows)). | Yes, only when `confirm` is true |

It records the device type in the notes but doesn't order hardware. For quotes, use the agent workflow or [Split Request](https://github.com/cloudradial/Automations/tree/main/split-request-two-tickets).

### Requirements

No extensions. Every call is made from PowerShell with runner Key Vault secrets.

| Secret | Required | Used for |
|---|---|---|
| `M365-TenantId`, `M365-ClientId`, `M365-ClientSecret` | Yes | Microsoft Graph. The same secrets Password Reset uses (`Entra-*` and `Graph-*` names also work). |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | For the portal user | Without them the portal user is skipped and listed as follow-up. |
| `PSA-Type` and your PSA's secrets | For the ticket note | See [PSA](https://github.com/cloudradial/Automations/tree/main/new-user-onboarding#psa-both-workflows). Without them the note isn't posted, but it's still returned in `internal_note`. |
| `PSA-ServiceQueue` | No, used when the request has no ticket | The board (ConnectWise) or queue for the new onboarding ticket. Without it, other PSAs use their default queue. |
| `CW-ServiceBoard` | ConnectWise, when the request has no ticket and `PSA-ServiceQueue` isn't set | The board for the new onboarding ticket. |
| `Onboarding-NotifySender` | No | A mailbox to email the manager from. Without it the manager isn't emailed. |
| `Onboarding-ProtectedGroupPatterns` | No | Extra comma-separated group name patterns to never add, on top of `admin`, `administrator`, `privileged` and `global`. |
| `Onboarding-DefaultLicenceSku` | No | The licence to use when the form says a licence is needed but none is chosen. Same values as `m365License`. Without it, the account gets no licence and a warning. |
| `Onboarding-UsageLocation` | No | Two-letter country code for new accounts, because the form doesn't ask for one. Without it, `US` is used. |

The Microsoft 365 app needs these Graph application permissions: `User.ReadWrite.All`, `GroupMember.ReadWrite.All`, `Organization.Read.All`, and `Mail.Send` if you set `Onboarding-NotifySender`. Password Reset confirmed the certified Microsoft 365 extension's app already has `User.ReadWrite.All`. The other three aren't verified yet, so check them in Entra before the first live run.

### Setup

1. On **Workflows → Import**, upload `new-user-onboarding-direct.yml`.
2. Add the secrets above to the runner's Key Vault. Deploy to the runner whose vault holds them.
3. Enable the webhook under **Properties → Webhook**, then **Publish** and **deploy**.
4. In the *Add a New User* form's automation, add a Webhook activity pointing at this workflow's webhook URL (it must be absolute), with the secret in the `X-Crauto-Webhook-Secret` header. Use the Content JSON from [form-webhook-mapping.md](https://github.com/cloudradial/Automations/blob/main/new-user-onboarding/form-webhook-mapping.md), plus the keys under Settings that you want to use.
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
| `ticketId` | none | The form's ticket, as the PSA shows it (Autotask and Kaseya BMS ticket numbers are looked up). Without it, the onboarding ticket is created in your PSA. |
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
