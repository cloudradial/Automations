# Create Shared Mailboxes and Distribution Lists on Request

When someone asks for a shared mailbox or a distribution list, it is created in Microsoft 365 with the right name, members and owner, and the ticket gets the new address, while anything unusual waits for a technician.

**Formerly:** Shared mailbox / distribution list request | **Marketplace ID:** TBD | **Type:** Workflow

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `shared-mailbox-dl.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/shared-mailbox-dl/shared-mailbox-dl.yml) |
| Download `shared-mailbox-dl.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/shared-mailbox-dl/shared-mailbox-dl.yml) |
| Source, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/automationai/shared-mailbox-dl/src) |
| All files in this automation | [automationai/shared-mailbox-dl](https://github.com/cloudradial/Automations/tree/main/automationai/shared-mailbox-dl) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/shared-mailbox-dl) |

## How it works

Two PowerShell steps. No AI is involved.

1. **Check the request and plan it.** Works out the address, checks it isn't already used (in Microsoft Graph and in Exchange Online), checks that the requester and every member are users with a mailbox in the tenant, and decides whether a technician has to confirm the request. It writes nothing.
2. **Create it, or hold it for confirmation, then reply on the ticket.** Creates the shared mailbox or distribution list in Exchange Online, unless the request is held. Then it adds an internal note to the ticket, and a public note with the new address when it was created.

### What it creates

| Kind | Changes, in this order | Exchange cmdlet |
|---|---|---|
| Shared mailbox | Create the shared mailbox | `New-Mailbox -Shared` |
| | Give the requester full access (the owner) | `Add-MailboxPermission -AccessRights FullAccess` |
| | Give each member full access (it appears in their Outlook) | `Add-MailboxPermission -AccessRights FullAccess -AutoMapping $true` |
| | Let each `send_as` person send as the mailbox | `Add-RecipientPermission -AccessRights SendAs` |
| Distribution list | Create the list with the requester as owner, internal senders only unless `external_allowed` is true | `New-DistributionGroup -ManagedBy <requester> -RequireSenderAuthenticationEnabled` |
| | Add each member | `Add-DistributionGroupMember` |

The address is `alias@domain`. When no `alias` is sent, it is made from the display name: lower case, accents removed, spaces turned into hyphens, `&` turned into "and", and anything other than letters, numbers, dots, hyphens and underscores dropped (so "Accounts Payable & Billing (UK)" becomes `accounts-payable-and-billing-uk`). A sent alias is cleaned the same way, with a warning if it changed. When no `domain` is sent, the tenant's default domain is used; a sent domain must be verified in the tenant.

### When a technician has to confirm

The run holds the request, creates nothing, and puts the plan and the reasons on the ticket as an internal note when:

- anyone who would get access (a member or a `send_as` person) has a different Microsoft 365 department from the requester, or
- the requester has no department in Microsoft 365, or
- there are more than 25 members.

To create it, a technician runs the workflow again with the same inputs and `confirm` set to true. Every other request is created straight away, which is what the request card asks for. `preview` set to true always shows the plan and creates nothing, even with `confirm` true.

### Checks that stop the run (nothing is created)

| Check | Result |
|---|---|
| The address or alias is already used by a user, a group or any Exchange recipient (contact, room, public folder) | `rejected` |
| A member or `send_as` person isn't a user in the tenant, or has no mailbox | `incomplete`, naming each one |
| The requester (`requester_email`) isn't a user in the tenant | `incomplete` |
| `company_tenant_id` and the `M365-TenantId` secret are both GUIDs and differ | `rejected` |
| The domain isn't verified in the tenant | `incomplete` |
| A Microsoft Graph permission is missing | `error`, naming the permission |

### When Exchange Online isn't available

Graph can't create a shared mailbox or a distribution list. The workflow reaches Exchange Online in one of two ways, in this order:

1. **The Exchange admin REST endpoint used by the `microsoft-exchange` catalog extension**, signed in with that extension's own secrets (`MicrosoftExchange-TenantId`, `MicrosoftExchange-ClientId`, `MicrosoftExchange-ClientSecret`). No module is needed.
2. **The ExchangeOnlineManagement PowerShell module with app-only certificate sign-in**, when the module is installed on the runner and the certificate secrets below are set.

Both steps sign in before anything is created. **If neither way works, the run fails and nothing is created.** The message says why in a plain sentence, and the internal note lists the exact commands a technician can run instead, for example:

```
New-Mailbox -Shared -Name 'Contoso Sales Team' -DisplayName 'Contoso Sales Team' -Alias 'contoso-sales-team' -PrimarySmtpAddress 'contoso-sales-team@contoso.com'
Add-MailboxPermission -Identity 'contoso-sales-team@contoso.com' -User 'alex.kim@contoso.com' -AccessRights FullAccess -InheritanceType All -AutoMapping $true
Add-RecipientPermission -Identity 'contoso-sales-team@contoso.com' -Trustee 'sam.doe@contoso.com' -AccessRights SendAs -Confirm:$false
```

If a change fails after the mailbox or list was created (for example one send-as grant), the run stops there. The internal note says what was created, what failed, and the exact commands still to run. A new mailbox can take a minute to be visible, so each permission and member change is retried for up to a minute when Exchange says the new object can't be found yet.

### What goes on the ticket

- **Internal note** on `ticket_id`, every run: the plan or the result, the reasons a technician must confirm, the Exchange commands, and any warnings.
- **Public note**, only when everything was created: "The new shared mailbox Contoso Sales Team is ready at contoso-sales-team@contoso.com." It holds the new address only, never the members.

**A retry writes nothing twice.** Each note ends with a short marker line, such as `[shared_mailbox created contoso-sales-team@contoso.com]`. Before writing, the workflow reads the ticket's notes and skips a note whose marker is already there, so a ServiceAI Action Runs **Retry** or a rerun adds no duplicate. A rerun after a successful run finds the address taken by the mailbox or list it created; when the ticket already holds that run's note, it returns `success` saying the address was already created, and changes and writes nothing. A preview or failure with different content still gets its own note. If the notes can't be read, the note is skipped with a warning rather than risk a second copy.

All six PSAs are supported for the notes: ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk.

## Download & import

**Download the workflow:** [`shared-mailbox-dl.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/shared-mailbox-dl/shared-mailbox-dl.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [secrets](#required-runner-key-vault-secrets), grant the [permissions](#required-microsoft-graph-permissions), then publish and deploy. Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

This is a per-company workflow: it reads the secrets of the runner it's deployed to, so deploy it to the runner for that client.

| Secret | Required | Used for |
|---|---|---|
| `M365-TenantId`, `M365-ClientId`, `M365-ClientSecret` | Yes | Microsoft Graph sign-in (the `Entra-*` and `Graph-*` names also work) |
| `MicrosoftExchange-TenantId`, `MicrosoftExchange-ClientId`, `MicrosoftExchange-ClientSecret` | Yes, unless the certificate secrets are set | Exchange Online through the admin REST endpoint. The same names as the `microsoft-exchange` catalog extension, so one set serves both. |
| `MicrosoftExchange-CertificateThumbprint`, or `MicrosoftExchange-Certificate` (base64 PFX) with optional `MicrosoftExchange-CertificatePassword` | Optional | Exchange Online PowerShell app-only sign-in, tried when the REST sign-in isn't set up or fails and the ExchangeOnlineManagement module is on the runner. Uses `MicrosoftExchange-ClientId` as the app id. |
| `MicrosoftExchange-Organization` | Optional | The tenant's `.onmicrosoft.com` domain for the PowerShell sign-in. Found through Graph when it isn't set. |
| `PSA-Type` | For ticket notes | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` |
| The PSA's own secrets (`CW-*`, `Autotask-*`, `Halo-*`, `KaseyaBMS-*`, `Syncro-*`, `Zendesk-*`) | For ticket notes | Same names as the PSA's catalog extension. Kaseya BMS also needs `KaseyaBMS-NoteTypeId`. |

If a ticket note fails, the run still returns its result and adds a warning.

## Required Microsoft Graph permissions

Application permissions on the app registration, with admin consent:

| Permission | Why |
|---|---|
| `User.Read.All` | Read the requester and members (department, mailbox) and check the address isn't on a user |
| `Domain.Read.All` | Find the default domain and check a sent domain is verified |
| `Group.Read.All` | Optional. Checks the address isn't on a group through Graph. Without it the run warns and relies on the Exchange Online check, which also covers groups. |

**Exchange Online:** the app used by the `MicrosoftExchange-*` secrets needs the **Office 365 Exchange Online** application permission `Exchange.ManageAsApp`, with admin consent, and the **Exchange Administrator** role.

A missing permission stops the run with a sentence naming it.

## Inputs

Send a flat JSON body, or the CloudRadial `{Ticket:{TicketId, Questions:[{Id, Value}]}, Company:{CompanyTenantId}}` shape (each question's Field ID is the input name). A value that is blank, or still a literal `@token` or `{{field}}`, counts as missing.

| Input | Default | Meaning |
|---|---|---|
| `kind` | required | `shared_mailbox` or `distribution_list` (`shared`, `DL` and `distribution list` also work) |
| `display_name` | required | The name people see, up to 64 characters |
| `alias` | made from `display_name` | The part of the address before the `@`. Cleaned to letters, numbers, dots, hyphens and underscores. |
| `domain` | the tenant's default domain | The part after the `@`. Must be verified in the tenant. |
| `members` | none | Comma-separated UPNs or email addresses. Shared mailbox: full access. Distribution list: members. |
| `send_as` | none | Comma-separated UPNs or email addresses that can send as the shared mailbox. Ignored, with a warning, for a distribution list. |
| `requester_email` | required | Who asked, made an owner (`@UserEmail` from a portal form, which the requester can't change) |
| `external_allowed` | `false` | Distribution list only: accept mail from outside the organisation |
| `confirm` | `false` | `true` creates a request that needs a technician's confirmation |
| `preview` | `false` | `true` shows the plan and creates nothing |
| `psa` | secret `PSA-Type` | Which PSA holds the ticket |
| `ticket_id` | none | The ticket that gets the notes (`@TicketId`) |
| `company_tenant_id` | none | `@CompanyTenantId`, for the tenant check |

**From a portal form, always send `confirm: false`.** A request that needs confirmation then waits on the ticket, and a technician reruns it with `confirm: true` (Run dialog, or a ServiceAI Action in AI mode).

## Output

```json
{ "status": "success | pending_confirmation | incomplete | rejected | error",
  "message": "...", "public_note": "...", "internal_note": "...", "ticket_id": "...",
  "kind": "shared_mailbox", "address": "contoso-sales-team@contoso.com", "display_name": "...", "alias": "...",
  "needs_confirmation": false, "confirmation_reasons": [...],
  "planned": [...], "ran": [...], "not_run": [...], "failed": null, "manual_commands": [...],
  "actions": [...], "warnings": [...], "chatReply": "..." }
```

`manual_commands` holds the Exchange commands still to run when Exchange Online couldn't be reached or the run stopped part way. A run with `error`, `incomplete` or `rejected` keeps its output and is marked failed in the run history.

## Import & test

1. In AutomationAI, **Workflows → Import** `shared-mailbox-dl.yml`.
2. Add the [secrets](#required-runner-key-vault-secrets) to the client's runner Key Vault and grant the [permissions and roles](#required-microsoft-graph-permissions).
3. **Publish** and **deploy** to that runner.
4. Open the first step's **Test Input**. It ships with `preview` as `"true"`. Set `requester_email` and `members` to real test users in the tenant and run it. Check the address, the plan and the ticket note. Nothing should change in Microsoft 365.
5. Set `preview` to `"false"` and run again with members from the requester's department. Check the shared mailbox exists, each member has full access, send-as is set, and the ticket has the internal note and the public note with the address.
6. Run once more with a member from another department and a new `display_name`. The run should return `pending_confirmation` and create nothing. Rerun with `confirm` as `"true"` to create it.
7. To start it from the portal, turn on the webhook under **Properties → Webhook** (it mints the URL and secret), redeploy, and add a Webhook activity to the request form's Automation that posts the inputs (with `requester_email` set to `@UserEmail`, `ticket_id` to `@TicketId`, `company_tenant_id` to `@CompanyTenantId` and `confirm` false) with the `X-Crauto-Webhook-Secret` header.

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. The workflow never deletes anything; remove test mailboxes and lists by hand.

## Build from source

Edit `src/*.ps1` (or the libraries in `automationai/_shared`), never the `.yml`:

```
node automationai/shared-mailbox-dl/src/build.js            # rebuild the .yml
pwsh -NoProfile -File automationai/shared-mailbox-dl/src/test.ps1
```

The Exchange Online sign-in and cmdlet calls come from `automationai/_shared/exchange.ps1`, which the build pastes into both steps; the Graph, plan and PSA note calls come from the other `_shared` libraries. The harness runs both steps from the built `.yml` under strict mode with a mocked Key Vault, Graph, Exchange Online (REST and the PowerShell module) and PSAs (ConnectWise, Autotask and HaloPSA notes, including reruns that must write nothing twice). js-yaml comes from `automationai/_shared/node_modules` (`npm install` there) or `JS_YAML_PATH`.
