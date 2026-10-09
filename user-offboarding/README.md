# Offboard a Departing Employee in One Reviewed Run

When someone leaves, their Microsoft 365 account is locked, signed out, stripped of groups and licences, and their mailbox kept as a shared mailbox, and you see every change before anything happens.

**Formerly:** User offboarding | **Marketplace ID:** TBD | **Type:** Workflow

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `user-offboarding.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/user-offboarding/user-offboarding.yml) |
| Download `user-offboarding.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/user-offboarding/user-offboarding.yml) |
| Source, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/user-offboarding/src) |
| All files in this automation | [user-offboarding](https://github.com/cloudradial/Automations/tree/main/user-offboarding) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/user-offboarding) |

## How it works

Two PowerShell steps. No AI is involved.

1. **Read the user and plan the offboarding.** Reads the user, their admin roles, groups, licences, manager, direct reports and devices from Microsoft Graph, and their mailbox from Exchange Online when the runner can reach it. Runs the safety checks and works out the plan. It writes nothing.
2. **Preview or offboard, then report.** With `confirm` false (the default) it changes nothing, returns the plan and adds it to the ticket as an internal note. With `confirm` true it makes the changes in a fixed order and stops at the first failure, saying what ran and what didn't. Then it writes the completion report.

### What it changes, in this order

| # | Change | How |
|---|---|---|
| 1 | Block sign-in | Graph |
| 2 | Reset the password to a random 24-character value | Graph. The password is made inside the change and never stored, logged, returned or put in a note. Nobody needs it. |
| 3 | Sign out of every session | Graph |
| 4 | Remove from every security group and Microsoft 365 group that doesn't assign a licence | Graph |
| 5 | Convert the mailbox to a shared mailbox, then check it really is shared | Exchange Online |
| 6 | Hide the mailbox from the global address list | Exchange Online |
| 7 | Forward new mail to the manager, or to `forward_to`, keeping a copy in the mailbox (optional) | Exchange Online |
| 8 | Remove from groups that assign a licence (group-based licensing) | Graph |
| 9 | Remove the directly assigned licences | Graph |

**Licences go last, and only when the mailbox is safe.** Steps 8 and 9 are planned only when the mailbox was found and will be converted to shared, is already shared, or doesn't exist, and `keep_licenses_days` is 0. Because the run stops at the first failure, a failed conversion means no licence is removed. They are also kept, with the reason in the report, when the mailbox has litigation hold, an in-place hold, an online archive, or is over 50 GB, because a shared mailbox like that still needs a licence.

### What it lists for a technician instead of changing

| Item | Why |
|---|---|
| Distribution lists and mail-enabled security groups | Graph can't change them. The report gives the exact `Remove-DistributionGroupMember` command for each. |
| Dynamic groups | Membership follows the user's attributes. |
| Groups synced from on-premises Active Directory | They change in Active Directory. |
| Sign-in, password and address list for a user synced from on-premises AD | Microsoft 365 can't change them. Sessions, cloud groups, the mailbox and licences are still handled. |
| Direct reports | They need a new manager. Reported only. |
| Registered and owned devices | Collect, wipe or reassign them. Reported only. |
| Admin roles (only when `allow_admin` is true) | Remove the role assignments by hand. |
| Existing mail forwarding | Check it is still wanted. |

### When Exchange Online isn't available

Graph can't convert a mailbox, hide it from the address list or set forwarding. The workflow reaches Exchange Online in one of two ways, in this order:

1. **The Exchange admin REST endpoint used by the `microsoft-exchange` catalog extension**, signed in with that extension's own secrets (`MicrosoftExchange-TenantId`, `MicrosoftExchange-ClientId`, `MicrosoftExchange-ClientSecret`). No module is needed. This is tried first.
2. **The ExchangeOnlineManagement PowerShell module with app-only certificate sign-in**, when REST can't be used, the module is installed on the runner and the certificate secrets below are set.

**If neither works, the run does not fail.** The mailbox steps are marked "Not done, do this in Exchange" in the internal note and the report, with the exact commands, for example:

```
Set-Mailbox -Identity 'sam.doe@contoso.com' -Type Shared
Set-Mailbox -Identity 'sam.doe@contoso.com' -HiddenFromAddressListsEnabled $true
Set-Mailbox -Identity 'sam.doe@contoso.com' -ForwardingAddress 'alex.kim@contoso.com' -DeliverToMailboxAndForward $true
```

**The licences stay on** so the mailbox isn't deleted (an unlicensed user mailbox is removed after 30 days). Once a technician has converted the mailbox, run the workflow again with `mailbox_already_shared` true and `confirm` true to remove the licences. A user with no Exchange Online plan has no mailbox to lose, so their licences are removed as normal.

### Safety checks (all fail closed)

- **Admin accounts are refused.** If the user holds any Entra directory role (directly or through a group), the run is rejected and nothing changes, unless `allow_admin` is true. If the roles can't be read, the run stops.
- **Nobody can offboard themselves.** The run is rejected when `requester_email` matches the user's UPN, mail or any proxy address, or `requester_office_id` matches their object id. From a portal form, fill these from the `@UserEmail` and `@UserOfficeId` tokens, which the requester can't change.
- **Tenant check.** When `company_tenant_id` and the `M365-TenantId` secret are both GUIDs and differ, the run is rejected.
- **Preview first.** Nothing changes until a run says `confirm: true`.

### The completion report

- **Internal ticket note** on `ticket_id`: every change made, what failed and what didn't run, what's left for a technician and why, the report-only items and the warnings. A preview run adds the plan instead.
- **Report Archive item** in the company's **Offboarding** archive (Compliance > Reports, admins only) with the same content, for runs with `confirm` true. It needs the CloudRadial company id (`company_id` input or `CloudRadial-CompanyId` secret); without it the report stays in the run output and the note, with a warning. Reports never go to the knowledge base.
- **Public ticket note**, only after a successful confirmed run: "The offboarding request has been processed." Nothing about groups, licences, devices or passwords is ever client-visible.

**A retry writes nothing twice.** Each internal note ends with a short marker line, such as `[offboarding success sam.doe@contoso.com]` or, for a preview, `[offboarding preview sam.doe@contoso.com 1a2b3c4d]` (a fingerprint of the plan). The public note the client sees never shows a marker: it ends with only an opaque `Ref: 1a2b3c4d` line, and its marker holds a fingerprint of the user, not the address. Before writing, the workflow reads the ticket's notes and skips a note whose marker is already there, so a ServiceAI Action Runs **Retry** or a rerun adds no duplicate. A preview with a different plan, or a run with a different result, still gets its own note. If the notes can't be read, the note is skipped with a warning rather than risk a second copy.

## Download & import

**Download the workflow:** [`user-offboarding.yml`](https://github.com/cloudradial/Automations/blob/main/user-offboarding/user-offboarding.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [secrets](#required-runner-key-vault-secrets), grant the [permissions](#required-microsoft-graph-permissions), then publish and deploy. Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

This is a per-company workflow: it reads the secrets of the runner it's deployed to, so deploy it to the runner for that client.

| Secret | Required | Used for |
|---|---|---|
| `M365-TenantId`, `M365-ClientId`, `M365-ClientSecret` | Yes | Microsoft Graph sign-in (the `Entra-*` and `Graph-*` names also work) |
| `MicrosoftExchange-TenantId`, `MicrosoftExchange-ClientId`, `MicrosoftExchange-ClientSecret` | For the mailbox steps | Exchange Online through the admin REST endpoint. The same names as the `microsoft-exchange` catalog extension, so one set serves both. |
| `MicrosoftExchange-CertificateThumbprint`, or `MicrosoftExchange-Certificate` (base64 PFX) with optional `MicrosoftExchange-CertificatePassword` | Optional | Exchange Online PowerShell app-only sign-in, the fallback when REST can't be used and the ExchangeOnlineManagement module is on the runner. Uses `MicrosoftExchange-ClientId` as the app id. A thumbprint needs the certificate installed on the runner. |
| `MicrosoftExchange-Organization` | Optional | The tenant's `.onmicrosoft.com` domain for the PowerShell sign-in. Found through Graph when it isn't set. |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | For the archive report | Writing the completion report to Report Archives |
| `CloudRadial-CompanyId` | Optional | The CloudRadial company id for the report, when the run doesn't send `company_id` |
| `PSA-Type` | For ticket notes | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` |
| The PSA's own secrets (`CW-*`, `Autotask-*`, `Halo-*`, `KaseyaBMS-*`, `Syncro-*`, `Zendesk-*`) | For ticket notes | Same names as the PSA's catalog extension. Kaseya BMS also needs `KaseyaBMS-NoteTypeId`. |

If a note or the archive write fails, the run still returns its result and adds a warning.

## Required Microsoft Graph permissions

Application permissions on the app registration, with admin consent:

| Permission | Why |
|---|---|
| `User.ReadWrite.All` | Read the user, manager, direct reports and licences; block sign-in; reset the password; sign out sessions; remove licences |
| `GroupMember.ReadWrite.All` | Read memberships and remove the user from groups |
| `RoleManagement.Read.Directory` | The admin check. Without it the run stops and changes nothing. |
| `Device.Read.All` | Optional. Lists the user's devices for the report. |
| `Organization.Read.All` | Optional. Finds the `.onmicrosoft.com` domain for the Exchange PowerShell sign-in. |

**The app also needs an Entra role to reset passwords**, because application permissions alone can't: assign it **User Administrator** (or **Privileged Authentication Administrator** to offboard admins with `allow_admin`).

**Exchange Online:** the app used by the `MicrosoftExchange-*` secrets needs the **Office 365 Exchange Online** application permission `Exchange.ManageAsApp`, with admin consent, and the **Exchange Administrator** role.

A missing permission stops the run with a sentence naming it.

## Inputs

Send a flat JSON body, or the CloudRadial `{Ticket:{TicketId, Questions:[{Id, Value}]}, Company:{CompanyTenantId}}` shape (each question's Field ID is the input name). A value that is blank, or still a literal `@token` or `{{field}}`, counts as missing.

| Input | Default | Meaning |
|---|---|---|
| `upn` | required | The departing user (UPN or object id) |
| `forward_to_manager` | `false` | Forward new mail to the user's manager |
| `forward_to` | none | Forward to this user instead (a UPN or email address in the same tenant). Wins over `forward_to_manager`. |
| `keep_licenses_days` | `0` | Keep the licences for this many days. `0` removes them once the mailbox is safe. |
| `confirm` | `false` | `false` previews and changes nothing. `true` makes the changes. |
| `allow_admin` | `false` | Let the workflow offboard a user who holds an admin role |
| `mailbox_already_shared` | `false` | A technician has converted the mailbox to shared by hand, so licences can go even when Exchange Online isn't reachable |
| `requester_email` | none | Who asked (`@UserEmail` from a portal form). Used to refuse self-offboarding. |
| `requester_office_id` | none | The requester's Entra object id (`@UserOfficeId`) |
| `psa` | secret `PSA-Type` | Which PSA holds the ticket |
| `ticket_id` | none | The ticket that gets the notes (`@TicketId`) |
| `company_tenant_id` | none | `@CompanyTenantId`, for the tenant check |
| `company_id` | secret `CloudRadial-CompanyId` | The CloudRadial company id for the Report Archive item |

**From a portal form or ticket webhook, always send `confirm: false`.** The request posts the plan to the ticket, and a technician reruns the workflow with `confirm: true` (Run dialog, or a ServiceAI Action in AI mode) once the plan looks right.

## Output

```json
{ "status": "pending_confirmation | success | incomplete | rejected | error",
  "message": "...", "public_note": "...", "internal_note": "...", "ticket_id": "...",
  "planned": [...], "ran": [...], "not_run": [...], "failed": null,
  "follow_up": [...], "licences_removed": true, "report": { "action": "created", "location": "..." },
  "actions": [...], "warnings": [...], "chatReply": "..." }
```

`success` with a non-empty `follow_up` means everything the workflow could do is done and a technician has items left (the message says how many). A run with `error`, `incomplete` or `rejected` keeps its output and is marked failed in the run history.

## Import & test

1. In AutomationAI, **Workflows → Import** `user-offboarding.yml`.
2. Add the [secrets](#required-runner-key-vault-secrets) to the client's runner Key Vault and grant the [permissions and roles](#required-microsoft-graph-permissions).
3. **Publish** and **deploy** to that runner.
4. Create a disposable test user with a licence, a mailbox, a manager and a couple of groups.
5. Open the first step's **Test Input**, set `upn` to the test user, keep `confirm` as `"false"`, and run it. Check the planned changes, the follow-up items and the ticket note. Nothing should change in Microsoft 365.
6. Run again with `confirm` as `"true"`. Check the user is blocked, signed out and out of the groups, the mailbox is shared and hidden, forwarding is set if asked, the licences are gone, and the report is in the company's **Offboarding** report archive.
7. To start it from the portal, turn on the webhook under **Properties → Webhook** (it mints the URL and secret), redeploy, and add a Webhook activity to the offboarding form's Automation that posts the inputs (with `confirm` false and the requester tokens) with the `X-Crauto-Webhook-Secret` header.

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. A run with `confirm` true locks the account and removes its access; test against a disposable user.

## Build from source

Edit `src/*.ps1` (or the libraries in `_shared`), never the `.yml`:

```
node user-offboarding/src/build.js            # rebuild the .yml
pwsh -NoProfile -File user-offboarding/src/test.ps1
```

The Exchange Online sign-in and cmdlet calls come from `_shared/exchange.ps1`, which the build pastes into both steps; the Graph, plan, PSA note and CloudRadial calls come from the other `_shared` libraries. The harness runs both steps from the built `.yml` under strict mode with a mocked Key Vault, Graph, Exchange Online (REST and the PowerShell module), CloudRadial and PSAs (ConnectWise, Autotask and HaloPSA notes, including reruns that must write nothing twice). js-yaml comes from `_shared/node_modules` (`npm install` there) or `JS_YAML_PATH`.
