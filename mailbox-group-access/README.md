# Give People Mailbox and Group Access Once It's Approved

In your UCP portal, clients ask for access to a shared mailbox, group, distribution list or Team. Once the person's manager or the group's owner approves, they get exactly that access in Microsoft 365 and the ticket is closed, with no technician needed.

## What your clients see in the portal

**A Mailbox or Group Access form.** The client says who needs access, to which mailbox, group, list or Team, and what kind, such as full access to a shared mailbox or membership of a Team. A ticket is created, as with any other request.

**When the manager asks, it's done in moments.** If the person submitting the form is the user's manager in Microsoft 365, or an owner of the group, the access is given straight away. The ticket gets a reply such as "Alex Kim now has full access to the Contoso Sales mailbox. It can take up to an hour to appear in Outlook." and is closed.

**Anyone else's request waits for approval.** The ticket says who can approve it. If you've set up a mailbox to send from, the manager is emailed and asked to reply on the ticket. Once they agree, a technician runs it once more with them as the approver.

## What it protects

- **Nobody approves their own access.** Only the user's manager or the group's owner, as set in Microsoft 365, or people you name for that client, can approve. A form answer can't change who asked.
- **Privileged groups are never granted.** Admin-looking groups, groups that can hold admin roles, dynamic groups and groups synced from on-premises go to a technician, with a note saying why.
- **Guests and blocked accounts are refused,** and access to a person's own mailbox always needs a technician.
- **One change, checked afterwards.** The access is read back before the client is told it's done, and nothing is ever removed.
- **No duplicates.** A retried request doesn't write its notes twice.

## Works with

Microsoft 365 (Exchange Online and Entra ID). The notes go on the ticket in ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro or Zendesk.

- **Proven live:** full access to a shared mailbox, with ConnectWise PSA.
- **Not yet run against a real account:** groups, Teams, distribution lists, send as, the approval email and the other five PSAs. They pass the same tests, so try one of each on a test account first.

## What you need

- A UCP portal with **Actions** on your request forms
- AutomationAI, with Microsoft 365 connected and allowed to read users and groups and change group membership
- Exchange Online connected too, for mailboxes and distribution lists (the same connection the Microsoft Exchange extension uses)
- Your PSA connected in AutomationAI, so the notes reach the ticket

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/mailbox-group-access/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy** to the runner that holds the client's Microsoft 365 connection.
4. Optionally, to email managers for approval, add a mailbox to send from to that runner. The [technical details](https://github.com/cloudradial/Automations/tree/main/mailbox-group-access#required-runner-key-vault-secrets) list exactly what to add.

If a client's Microsoft 365 connection is saved under that company rather than shared, open the workflow, set **Company** to that client on all three steps, then publish and deploy. Do this again after every import.

**In your UCP portal, create the form:**

1. Create a request form called **Mailbox or Group Access**.
2. Add an **Email** question, "Who needs access?", and set its Field ID to `targetUser`.
3. Add a **Text** question, "Which mailbox, group, list or Team?", and set its Field ID to `resource`. Its email address or its exact name both work.
4. Optionally, add a choice question, "What kind of access?", with Field ID `accessType` and the options Full access, Send as, Send on behalf, Member and Owner. Without it, mailboxes get full access and groups get membership.
5. At the end of the form, add an **Action** question and pick **Mailbox / Group Access Request**.
6. Make sure the company's Microsoft 365 tenant is set in the portal, and the form still sends tickets to your PSA.

**Approving a waiting request.** When the approver agrees on the ticket, open the workflow's **Test**, enter the same answers with the ticket number, set `approvedBy` to the approver's email and `confirm` to true, and run it.

**Test it.** Submit the form as a test user asking for access to a test shared mailbox, and check the ticket says it's waiting for approval. Then submit it as that user's manager, and check the access is given and the ticket closes. Remove the test access by hand afterwards.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/mailbox-group-access#technical-details) cover every access type, each safety check, who counts as an approver, the Microsoft permissions needed, other ways to start it, and what has been proven live.

---

## Technical details

**Formerly:** Mailbox / Group Access Request (tracker 10.2) | **Marketplace ID:** TBD | **Type:** Workflow (PowerShell, no AI) | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/mailbox-group-access/v1.0.0).

| What | Link |
|---|---|
| View `mailbox-group-access.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/mailbox-group-access/mailbox-group-access.yml) |
| Download `mailbox-group-access.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/mailbox-group-access/v1.0.0) |
| Source, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/mailbox-group-access/src) |
| All files in this automation | [mailbox-group-access](https://github.com/cloudradial/Automations/tree/main/mailbox-group-access) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/mailbox-group-access) |

## How it works

Three PowerShell steps. No AI is involved.

1. **Read the request and plan it (read-only).** Finds the user and the mailbox, group or Team in Microsoft 365, refuses anything that must never be granted automatically, checks whether the user already has the access, and works out who can approve it. It changes and writes nothing.
2. **Give the access and read it back.** Only when `confirm` is true and the request is approved. It makes one change, then reads it back to check it is in place.
3. **Note the ticket and close it.** Adds an internal note with what happened. When the access was given, it also adds a short public note for the requester and closes the ticket (unless `closeTicket` is false). When approval is still needed, the internal note says who can approve and, if `Access-NotifySender` is set, the manager is emailed.

**`confirm` false (the default) changes nothing and writes nothing.** The run returns the plan, who must approve, and the notes it would write, with `status: pending_confirmation`.

### What it changes

| Resource | Access types (the first is the default) | Change | How |
|---|---|---|---|
| Shared, room or equipment mailbox | `fullAccess`, `sendAs`, `sendOnBehalf` | Full access with AutoMapping on, so it appears in Outlook | `Add-MailboxPermission -AccessRights FullAccess -InheritanceType All -AutoMapping $true` |
| | | Send as | `Add-RecipientPermission -AccessRights SendAs` |
| | | Send on behalf | `Set-Mailbox -GrantSendOnBehalfTo @{Add=...}` |
| Microsoft 365 group, or a Team | `member`, `owner`, `sendAs` | Member or owner of the group (adding to the group is how Team membership works) | Microsoft Graph `groups/{id}/members/$ref` or `owners/$ref` |
| Security group | `member`, `owner` | Member or owner | Microsoft Graph |
| Distribution list, mail-enabled security group | `member`, `owner`, `sendAs` | Member, owner, or send as the list | `Add-DistributionGroupMember`, `Set-DistributionGroup -ManagedBy @{Add=...}`, `Add-RecipientPermission` |
| A person's own (user) mailbox | `fullAccess`, `sendAs`, `sendOnBehalf` | As for a shared mailbox, but only with a technician (see below) | Exchange Online |

The resource is found by email address (or any proxy address) or by display name. Two groups with the same name, a mail contact, or anything else that isn't a mailbox, group or Team stops the run as `incomplete`.

If the user already has the access, the run is a `success` and nothing changes. With `confirm` true it still notes the ticket ("already has full access, so nothing needed to change") and closes it.

### What it never grants

These stop the run as `rejected`, with an internal note saying why. Nothing changes.

| Check | Why |
|---|---|
| A role-assignable group (`isAssignableToRole`) | Membership can give Microsoft Entra admin roles. A Privileged Role Administrator has to decide. |
| A group whose name matches a privileged pattern | Default patterns: `admin`, `global`, `privileged`, `break glass`, `domain admins`. Each matches anywhere in the name, ignoring case, and a space also matches a hyphen, dot or underscore. `Access-SensitiveGroupPatterns` replaces the list. |
| A dynamic group | Its rule decides who is in it. The note quotes the rule. |
| A group synced from on-premises Active Directory | It can only be changed there. The note gives the `Add-ADGroupMember` command for a technician. |
| A user who is blocked from signing in, or a guest | A guest is allowed only when a technician sends `allowGuest: true`. |
| `company_tenant_id` and the `M365-TenantId` secret are both GUIDs and differ | The request is for another tenant. |
| A user asking for access to their own mailbox | It is already theirs. |

### Who can approve

The request is **approved** when `approvedBy` is one of these people, or when the requester (`requester_email`) is one of them:

- the user's **manager** in Microsoft 365 (`/users/{id}/manager`)
- an **owner** of the group or Team (Microsoft Graph owners)
- for a shared, room or equipment mailbox, the **manager set on the mailbox's own account**, which this workflow treats as the mailbox's owner (Exchange has no owner for a shared mailbox)
- anyone listed in the optional `Access-Approvers` secret

`approvedBy` and `requester_email` are matched to the person's account, so an alias or proxy address works too. `managerEmail` never counts: only Microsoft 365 decides who the manager is, and a `managerEmail` that doesn't match adds a warning.

When it isn't approved, the run returns `pending_approval` and changes nothing. The internal note names everyone who can approve. When the `Access-NotifySender` secret is set, the user's manager (or, with no manager, up to five owners) is emailed from that mailbox through Microsoft Graph and asked to reply on the ticket. A technician then runs it again with `approvedBy` set to the approver's address and `confirm` true.

**A person's own mailbox needs a technician.** For `fullAccess` or `sendAs` on a user mailbox, the requester's own say-so never counts, even when they are that person's manager: only `approvedBy` does, and the approvers are the mailbox's owner and the owner's manager (not the requesting user's manager). `sendOnBehalf` on a user mailbox has the same approvers, but the requester can be one of them.

### When Exchange Online isn't available

Mailbox permissions, distribution lists, mail-enabled security groups and send-as need Exchange Online. It is reached the same way as in [shared-mailbox-dl](https://github.com/cloudradial/Automations/tree/main/shared-mailbox-dl): first the Exchange admin REST endpoint used by the `microsoft-exchange` catalog extension (the `MicrosoftExchange-*` secrets), then the ExchangeOnlineManagement module with a certificate, when it is installed on the runner.

**If neither works, nothing changes and the run is `incomplete`.** The internal note gives the exact command for a technician, for example:

```
Add-MailboxPermission -Identity 'sales@contoso.com' -User 'alex.kim@contoso.com' -AccessRights FullAccess -InheritanceType All -AutoMapping $true
```

Microsoft 365 groups, Teams and security groups only need Microsoft Graph, so they still work without Exchange Online (unless the request is `sendAs`).

### Read back

After the change, the access is read back (Graph membership or ownership, or `Get-MailboxPermission`, `Get-RecipientPermission`, `Get-Mailbox`, `Get-DistributionGroupMember`, `Get-DistributionGroup`), up to three times 10 seconds apart. If it still isn't there, the run is `incomplete`, the ticket stays open, and running it again confirms it without changing anything twice.

### What goes on the ticket

- **Internal note**, every run with `confirm` true: the request, what was done or why not, the approval, any command for a technician, and warnings.
- **Public note**, only when the access is in place, for example: "Alex Kim now has full access to the Contoso Sales mailbox (sales@contoso.com). It can take up to an hour to appear in Outlook."
- **Closed**, when the access is in place and `closeTicket` is true (the default), to the PSA's usual closed status.

**A rerun writes nothing twice.** Every internal note ends with a marker starting `mailbox-group-access`, such as `[mailbox-group-access done fullaccess sales@contoso.com alex.kim@contoso.com]`. The public note shows only an opaque `Ref: 1a2b3c4d` line. Before writing, the workflow reads the ticket's notes and skips a note that is already there, so a ServiceAI Action Runs **Retry** or a rerun adds nothing. A rerun after success finds the access already in place, writes no new note and doesn't close the ticket again. A repeated `pending_approval` run doesn't email the approver again (this check reads the ticket, so it needs the PSA).

All six PSAs are supported: ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk.

## Download & import

**Download the workflow:** [`mailbox-group-access.yml`](https://github.com/cloudradial/Automations/releases/tag/mailbox-group-access/v1.0.0)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [secrets](#required-runner-key-vault-secrets), grant the [permissions](#required-microsoft-graph-permissions), then publish and deploy. Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

This is a per-company workflow: it reads the secrets of the runner it's deployed to, so deploy it to the runner for that client. Secrets are listed by name only.

| Secret | Required | Used for |
|---|---|---|
| `M365-TenantId`, `M365-ClientId`, `M365-ClientSecret` | Yes | Microsoft Graph sign-in (the `Entra-*` and `Graph-*` names also work) |
| `MicrosoftExchange-TenantId`, `MicrosoftExchange-ClientId`, `MicrosoftExchange-ClientSecret` | For mailboxes, distribution lists, mail-enabled security groups and send-as, unless the certificate secrets are set | Exchange Online through the admin REST endpoint. The same names as the `microsoft-exchange` catalog extension. |
| `MicrosoftExchange-CertificateThumbprint`, or `MicrosoftExchange-Certificate` (base64 PFX) with optional `MicrosoftExchange-CertificatePassword` | Optional | Exchange Online PowerShell app-only sign-in, when the REST sign-in isn't set up or fails and the ExchangeOnlineManagement module is on the runner |
| `MicrosoftExchange-Organization` | Optional | The tenant's `.onmicrosoft.com` domain for the PowerShell sign-in. Found through Graph (`Domain.Read.All`) when it isn't set. |
| `PSA-Type` | For ticket notes | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` (a `psa` input overrides it) |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | For ticket notes | |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | For ticket notes | Optional: `Autotask-NotePublishId`, `Autotask-NotePublicPublishId`, `Autotask-NoteTypeId` |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | For ticket notes | Optional: `Halo-NoteOutcomeId`, `Halo-PublicNoteOutcomeId`, `Halo-ClosedStatusId` |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId` | For ticket notes | `KaseyaBMS-ClosedStatusId` to close tickets |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | For ticket notes | |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | For ticket notes | |
| `Access-NotifySender` | Optional | The mailbox (UPN) the approval request email is sent from. Without it, no email is sent. Needs `Mail.Send`. |
| `Access-SensitiveGroupPatterns` | Optional | Comma-separated words or phrases that mark a group as privileged, replacing the defaults (`admin, global, privileged, break glass, domain admins`). Keep the defaults in the list when you add your own. |
| `Access-Approvers` | Optional | Comma-separated email addresses of people who can approve any request for this client, such as the client's IT lead. Useful when managers aren't set in Microsoft 365. |

If a ticket note, the email or the close fails, the run still returns its result and adds a warning.

### Microsoft 365 secrets stored per company

When a client's Microsoft 365 secrets (`M365-*` and `MicrosoftExchange-*`) are saved under the company in AutomationAI (**Companies**, policy *Require company*) instead of in the runner vault, open the workflow in the designer and set **Company** to that client on all three steps, then publish and deploy.

- **Set it again after every import.** Importing a workflow clears the step Company setting, because the `.yml` doesn't carry it.
- **Without it,** the steps use the runner's shared secrets, so they sign in to the wrong tenant or fail.

## Required Microsoft Graph permissions

Add these application permissions to the Microsoft 365 app registration you already use (the one in the `M365-*` secrets), then grant admin consent. They add to what the app already has, so leave its existing permissions in place.

| Permission | Why |
|---|---|
| `User.Read.All` | Find the user, their manager, the approvers, and a mailbox's account and its manager |
| `Group.Read.All` | Find the group or Team, classify it, and read its members and owners |
| `GroupMember.ReadWrite.All` | Add a member or owner to a Microsoft 365 group, Team or security group. Adding an owner may need `Group.ReadWrite.All` in some tenants (see below). |
| `Mail.Send` | Only when `Access-NotifySender` is set: email the approver |
| `Domain.Read.All` | Optional: find the `.onmicrosoft.com` domain for the Exchange PowerShell sign-in when `MicrosoftExchange-Organization` isn't set |

**Exchange Online:** the app used by the `MicrosoftExchange-*` secrets needs the **Office 365 Exchange Online** application permission `Exchange.ManageAsApp`, with admin consent, and the **Exchange Administrator** role (or a custom role group with the Mail Recipients and Distribution Groups roles).

Role-assignable groups are always refused, so `RoleManagement.ReadWrite.Directory` is never needed. A missing permission stops the run with a sentence naming it.

## Inputs

Send a flat JSON body, the CloudRadial `{Ticket:{TicketId, Questions:[{Id, Value}]}, Company:{CompanyTenantId}}` shape (each question's Field ID is the input name), either one wrapped in `{trigger: ...}`, or start it from a [form Action](#starting-it-from-a-form-action). A value that is blank, or still an unfilled placeholder (`<targetUser>`, `{{targetUser}}` or a bare `@token`), counts as not given.

| Input | Default | Meaning |
|---|---|---|
| `ticketId` | required | The PSA ticket that gets the notes (`@TicketId`) |
| `targetUser` | required | UPN or email address of the person who should get access |
| `resource` | required | Email address or display name of the mailbox, group or Team |
| `accessType` | `fullAccess` for a mailbox, `member` for a group | `fullAccess`, `sendAs`, `sendOnBehalf`, `member` or `owner` ("Send As", "full access" and similar spellings also work) |
| `requester_email` | none | Who asked (`@UserEmail` from a portal form, which the requester can't change). Counts as approval when they are the manager or an owner. |
| `managerEmail` | none | The manager the requester named. Informational only; never counts as approval. |
| `approvedBy` | none | The approver's email address, set by a technician after the approver agreed |
| `confirm` | `false` | `true` makes the change (when approved) and writes to the ticket. `false` changes and writes nothing. |
| `closeTicket` | `true` | `false` leaves the ticket open after a success |
| `allowGuest` | `false` | `true` lets a guest user get the access |
| `company_tenant_id` | none | `@CompanyTenantId`, for the tenant check |
| `psa` | secret `PSA-Type` | Which PSA holds the ticket |

### Starting it from a form Action

On portals with Actions, add a question of type **Action** to the form and pick **Mailbox / Group Access Request**. There's nothing to map. The portal sends each answer under its Field ID (so the form needs `targetUser` and `resource` questions, and optionally `accessType` and `managerEmail`), plus its own `ticket`, `company` and `user` objects. From an Action:

- **The requester** is the portal's `user.email`, **the ticket** is `ticket.id` (the ticket the form creates), and **the tenant** is `company.tenantId`.
- **The run is live** (`confirm` true). It only changes something when the requester is an approver; any other request waits as `pending_approval`.
- **A form answer can't set** `ticketId`, `requester_email`, `approvedBy`, `company_tenant_id`, `psa`, `confirm` or `allowGuest`. Answers with those Field IDs are ignored, so a requester can't approve their own request.
- **To grant a waiting request,** a technician runs the workflow from **Test** with a flat body: the same answers, the `ticketId`, `approvedBy` set to the approver and `confirm` true.

**From a form Automation (Webhook activity) or ServiceAI,** send `requester_email` as `@UserEmail` and `confirm` as `true`. A request from the user's manager (or the group's owner) is then granted straight away; any other request waits on the ticket as `pending_approval`, and the manager is emailed when `Access-NotifySender` is set. Only `@UserEmail` should fill `requester_email`: a value the requester can type would let them approve their own request.

## Output

```json
{ "status": "success | pending_confirmation | pending_approval | incomplete | rejected | error",
  "message": "...", "public_note": "...", "internal_note": "...", "ticket_id": "12345",
  "counts": { "granted": 1, "alreadyHadAccess": 0, "notesWritten": 2, "emailsSent": 0, "ticketsClosed": 1 },
  "target": "alex.kim@contoso.com", "resource": "sales@contoso.com", "access_type": "fullAccess", "approved": true,
  "manual_command": "", "actions": [...], "warnings": [...] }
```

`manual_command` holds the command for a technician when Exchange Online couldn't be reached, the change failed, or the group is synced from on-premises. A run with `error`, `incomplete` or `rejected` keeps its output and is marked failed in the run history; `pending_confirmation` and `pending_approval` are not failures.

## Import & test

1. In AutomationAI, **Workflows → Import** `mailbox-group-access.yml`.
2. Add the [secrets](#required-runner-key-vault-secrets) to the client's runner Key Vault and grant the [permissions and roles](#required-microsoft-graph-permissions).
3. **Publish** and **deploy** to that runner.
4. **Preview first.** Open the first step's **Test Input**. It ships with `confirm` as `"false"`. Set `targetUser` to a test user, `resource` to a test shared mailbox and `ticketId` to a test ticket, and run it. Expect `pending_confirmation`, the planned change, and the people who can approve. Nothing should change in Microsoft 365 and nothing should be written to the ticket.
5. **Pending approval.** Set `confirm` to `"true"` and leave `approvedBy` empty (with `requester_email` set to the test user themself). Expect `pending_approval`, one internal note naming the approvers, and nothing changed. With `Access-NotifySender` set, check the manager's email.
6. **Grant.** Run again with `approvedBy` set to the test user's manager. Expect `success`, the access in Microsoft 365, an internal note, a public note and the ticket closed.
7. **Rerun.** Run the same input once more. Expect `success` saying the user already has the access, no new notes, and the ticket not closed again.
8. Repeat 6 for a Microsoft 365 group (`accessType` `member`) and a distribution list, and check a privileged group name returns `rejected`.
9. To start it from a portal form, add the [form Action](#starting-it-from-a-form-action). To start it from a form Automation or ServiceAI instead, turn on the webhook under **Properties → Webhook** (it mints the URL and secret), redeploy, and post the inputs with the `X-Crauto-Webhook-Secret` header: from a request form's Automation (Webhook activity), or from a ServiceAI Action such as "Grant Access Request".

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. The workflow never removes access; take test access away by hand.

## Proven live

On 2026-10-29 the workflow ran in AutomationAI against a real Microsoft 365 test tenant and ConnectWise PSA, giving a user full access to a shared mailbox:

1. **Pending approval.** With `confirm` true and no approver, the run returned `pending_approval`. It wrote one internal note that named the user's manager, and nothing changed.
2. **Grant.** With `approvedBy` set to that manager, the run returned `success`. It added full access with AutoMapping and read it back in place. It wrote the internal and public notes and closed the ticket.
3. **Rerun.** The same input again returned `success` with `alreadyHadAccess` 1. It wrote no notes and didn't close the ticket again.
4. **Note redirect.** ConnectWise answered the note calls with a redirect. The workflow read the ticket back to check the notes were there, and didn't send them again.

## Not yet proven live

Everything below passes the strict-mode mock harness, but hasn't been run against a real tenant yet:

- **The other five PSAs.** Notes, the rerun check and closing the ticket are proven only on ConnectWise PSA. Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk haven't been run live, and several of their close calls in `_shared/psa.ps1` carry `Unverified` comments.
- **The approval email** through Graph `sendMail` from `Access-NotifySender`. It wasn't set in the live test.
- **Microsoft 365 groups, Teams, security groups and distribution lists.** Only a shared mailbox has been granted live.
- **Send as and send on behalf.** Only full access has been granted live.
- **The `rejected` path for a privileged group.** No privileged group has been tried live.
- **Team detection** reads the group's `resourceProvisioningOptions` through Graph v1.0. If a tenant doesn't return it, a Team is treated as a Microsoft 365 group, which is granted the same way.
- **Owners of distribution lists and mail-enabled security groups** are read from Microsoft Graph owners for approval. Whether Exchange's `ManagedBy` always shows up there hasn't been checked.
- **Adding a group owner through Graph** with only `GroupMember.ReadWrite.All`. Some tenants may need `Group.ReadWrite.All`.
- **Hashtable parameters through the Exchange REST endpoint** (`-GrantSendOnBehalfTo @{Add=...}` and `-ManagedBy @{Add=...}`), and the read-back of `GrantSendOnBehalfTo` and `ManagedBy`, which Exchange may return as display names or ids.
- **Treating the manager of a shared mailbox's account as its owner** is this workflow's own convention. The live grant was approved by the user's manager, so this path hasn't been run. Set those managers in Microsoft 365, or use `Access-Approvers`.

Preview against a test user and a test ticket before turning on `confirm` from a trigger.

## Build from source

Edit `src/*.ps1` (or the libraries in `_shared`), never the `.yml`:

```
node mailbox-group-access/src/build.js            # rebuild the .yml
pwsh -NoProfile -File mailbox-group-access/src/test.ps1
```

`src/common.ps1` holds the helpers the Read and Grant steps share (the change for each access type, and the check for existing access); `build.js` pastes it into both. The Graph, Exchange Online and PSA calls come from `_shared/graph.ps1`, `_shared/exchange.ps1` and `_shared/psa.ps1`. The harness runs all three steps from the built `.yml` under strict mode with a mocked Key Vault, Graph, Exchange Online and PSAs (ConnectWise, Syncro and Zendesk, including reruns that must write nothing twice). js-yaml comes from `_shared/node_modules` (`npm install` there) or `JS_YAML_PATH`.
