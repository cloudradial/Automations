# Let Users Reset Their Own Password Safely

Your clients reset their own Microsoft 365 password from the portal in seconds. Built-in checks stop anyone resetting someone else's password, an admin's, or an account that looks at risk.

## What your clients see in the portal

**A Password Reset form.** The client enters the email address of their own account and submits the form. A ticket is created, as with any other request.

**An answer on the ticket.** In moments, the ticket gets a reply. If it worked, it says their password has been reset. If it was refused, it says why in plain words, for example "You can only reset your own account". If something went wrong, it says a technician will follow up shortly.

At their next sign-in they use the temporary password and choose a new one. They're also signed out everywhere else.

## What it protects

- **People can only reset their own account.** The portal knows who is signed in, and that must match the account. A form answer can't change who the requester is.
- **Admins are never reset this way.** Any account with an admin role goes through a technician.
- **Disabled and at-risk accounts are refused.** A disabled account may be mid-offboarding, and an account Microsoft flags as at risk or compromised needs a person to look at it.
- **The wrong client's tenant is refused.** The request must match the Microsoft 365 tenant your connection signs in to.
- **The temporary password stays private.** It only goes in an internal note your technicians can see, never in the client's reply.
- **Every outcome is recorded.** Success, refusal or error, the ticket gets notes, and a retried request doesn't post them twice.

## Works with

Microsoft 365 (Entra ID), for the password reset itself. The notes go on the ticket in ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro or Zendesk.

## What you need

- A UCP portal with **Actions** on your request forms
- AutomationAI, with Microsoft 365 connected and allowed to reset passwords, read admin roles and check risky users
- Your PSA connected in AutomationAI, so the notes reach the ticket

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/password-reset/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.

If a client's Microsoft 365 connection is saved under that company rather than shared, open the workflow, set **Company** to that client on the Microsoft 365 steps, then publish and deploy. Do this again after every import.

**In your UCP portal:**

1. Open or create a **Password Reset** request form.
2. Add an **Email** question for the account to reset, and set its Field ID to `userPrincipalName`.
3. At the end of the form, add an **Action** question and pick **Password Reset**.
4. Make sure the company's Microsoft 365 tenant is set in the portal, so the tenant check can run.

**Test it.** As a client user, submit the form for a spare test account you own and check the ticket notes. Then submit it for a different address and check it's refused. A successful test really does change that account's password.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/password-reset#technical-details) cover each safety check, the Microsoft permissions needed, other ways to start it, and how to test each step.

---

## Technical details

**Formerly:** Password Reset (Self-Service) | **Marketplace ID:** AAI-00027 | **Type:** Workflow | **Version:** 1.0.0

## Files

Each version is published as a release, with `password-reset.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/password-reset/v1.0.0).

| What | Link |
|---|---|
| Download `password-reset.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/password-reset/v1.0.0) |
| View the current source | [`password-reset.yml`](https://github.com/cloudradial/Automations/blob/main/password-reset/password-reset.yml) |
| Test harness for the Parse & Validate step | [`src/test-parse.ps1`](https://github.com/cloudradial/Automations/blob/main/password-reset/src/test-parse.ps1) |
| Test harness for the Finish step (notes on all six PSAs) | [`src/test-finish.ps1`](https://github.com/cloudradial/Automations/blob/main/password-reset/src/test-finish.ps1) |
| All files in this automation | [password-reset](https://github.com/cloudradial/Automations/tree/main/password-reset) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/password-reset) |
| Marketplace listing | [AAI-00027](https://automations.cloudradial.com/marketplace/AAI-00027) |

## How it works

Self-service Microsoft 365 password reset, fired by a CloudRadial ticket webhook / ServiceAI. A
**broken-out** rebuild of the original single-node workflow, identical behaviour and output contract,
but with **one step per concern** so each gate is legible and independently testable.

Nodes: **Parse & Validate → Resolve & Ownership Gate → Safety Gates → Reset Password → Finish.**

## Download & import

**Download the workflow:** [`password-reset.yml`](https://github.com/cloudradial/Automations/releases/tag/password-reset/v1.0.0)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), enable the webhook in **Properties** (the portal mints the URL + secret), then publish and deploy. Full steps are under [Import & test](#import--test) below.

### Microsoft 365 secrets stored per company

Sometimes a client's Microsoft 365 secrets (`M365-TenantID`, `M365-ClientID` and `M365-ClientSecret`) are saved under the company in AutomationAI (**Companies**, policy *Require company*) instead of in the runner vault. In that case, open the workflow in the designer and set **Company** to that client on these steps: **Resolve & Ownership Gate**, **Safety Gates** and **Reset Password**. Then publish and deploy.

- **Set it again after every import.** Importing a workflow clears the step Company setting, because the `.yml` doesn't carry it.
- **Without it,** the steps use the runner's shared secrets, so they sign in to the wrong tenant or fail.

## Why this is safe (ownership gate)

A requester may reset **only their own** account. The trusted, portal-injected `submittedByUpn`
(and `userOfficeId` = the submitter's Entra object id) is matched against the target:

- exact object-id match (`userOfficeId` == target `id`), else
- email match (`submittedByUpn` == the target's UPN / mail / any proxy address).

If the submitter is missing, or doesn't match the target, the run **fails closed** (`status: rejected`).
`submittedByUpn` is injected by CloudRadial from the authenticated session (falling back to the Ticket
object), it is **never** a user-typed field.

## Trigger payload

| Field | Meaning |
|---|---|
| `userPrincipalName` (or `email`) | the account to reset (form field) |
| `submittedByUpn` | TRUSTED authenticated submitter (injected; falls back to Ticket `SubmittedByEmail`/`ContactEmail`/…) |
| `userOfficeId` | submitter's Entra object id (`@UserOfficeId`), enables an exact id match |
| `companyTenantId` | requesting company's M365 tenant GUID, used for tenant scoping |
| `revokeSessions` | optional, defaults **true** |
| `ticketId` | the ticket the notes go on |
| `postNotes` | optional, `true` makes Finish post the notes to the ticket itself (see [Notes on the ticket](#notes-on-the-ticket)). Leave it unset when the caller posts the returned notes, so they aren't written twice. Always on for a form Action. |

Handles both a flat `{key:value}` body and the nested `{trigger:{Ticket:{Questions:[{Id,Value}]},Company:{…}}}` shape.

### Starting it from a form Action

On portals with Actions, add a question of type **Action** to the form and pick **Password Reset**. There's nothing to map. The portal sends each answer under its Field ID (so the form needs a `userPrincipalName` question for the account to reset), plus its own `ticket`, `company` and `user` objects. From an Action:

- **The submitter** is the portal's `user.email`, **the ticket** is `ticket.id` (the ticket the form creates), and **the tenant** is `company.tenantId`. Set the company's Microsoft 365 tenant in the portal so the tenant-scope gate can check it.
- **A form answer can't set** `submittedByUpn`, `userOfficeId`, `companyTenantId`, `ticketId` or `revokeSessions`. Answers with those Field IDs are ignored, and sessions are always revoked.
- The Action doesn't send the submitter's Entra object id, so ownership is matched by email (the submitter's portal email against the target's UPN, mail or proxy addresses).
- An Action doesn't post the returned notes to the ticket, so Finish posts them itself. This needs the PSA secrets below. See [Notes on the ticket](#notes-on-the-ticket).

## Gates (all fail-closed), in order

1. **Ownership**, submitter must equal the target (above).
2. **Disabled**, a disabled account is not reset (possible offboarding/hold).
3. **Tenant scope**, if a valid `companyTenantId` GUID is present, it must match the tenant this runner is credentialed for (blocks cross-tenant).
4. **Privileged**, the target must hold **no** Entra directory role (admins go through a technician).
5. **Risk**, best-effort Identity Protection check; high-risk / at-risk / confirmed-compromised is blocked.

## Action & output

Resolve → strong 16-char temporary password (`forceChangePasswordNextSignIn`) → revoke sign-in sessions.
Emits the same contract as the original single-node version:

```json
{ "status": "success" | "rejected" | "incomplete" | "error",
  "message": "...", "public_note": "...", "internal_note": "...",
  "ticket_id": "...", "user_id": "...", "upn": "...", "passwordReset": true,
  "actions": [...], "warnings": [...], "audit": { ... } }
```

The **temporary password appears only in `internal_note`** (never a top-level field, never in `public_note`).

`status: success` and `passwordReset: true` are reported **only** when the Reset Password step confirms the reset. If Microsoft Graph refuses it (for example 403 because the app lacks a password-reset role), Finish returns `status: error` with "Something went wrong resetting your password. A technician will follow up shortly." and the run fails, so it shows in the run history. Resetting passwords as an app needs both a Graph application permission (`User-PasswordProfile.ReadWrite.All` or `User.ReadWrite.All`, admin-consented) and an Entra role on the app's service principal (Helpdesk Administrator for non-admin users).
### Notes on the ticket

The workflow always **returns** both notes. Who writes them to the ticket depends on how it was started:

| Started by | Who posts the notes |
|---|---|
| A CloudRadial form **Action** | **Finish**, because the portal doesn't post a workflow's notes. |
| A webhook body with `"postNotes": true` | **Finish**. |
| A legacy CloudRadial Automation or a ServiceAI Action (no `postNotes`) | The caller, from the returned notes, as before. Finish posts nothing, so the notes aren't written twice. |

When Finish posts, it writes them on whichever of the six PSAs is set up (`PSA-Type` and that PSA's secrets, through `_shared/psa.ps1`), for every outcome (success, refusal or error), so the user always gets an answer on the ticket:

- **The internal note** (technician-only) holds the details and, on success, **the temporary password**. That's the only place the password is written.
- **The public note** is what the user sees, for example "Your password has been reset…" or "You can only reset your own account…". It never contains the password.
- **A retried request** (for example Action Runs > Retry after a refusal) doesn't post the same notes twice.
- **If a note can't be posted** (no PSA set up, no ticket number, or the PSA refuses), the run adds a warning (`notes_posted: none`) and keeps both notes in its output. A successful reset still reports success. Warnings never contain the password.

The output adds `notes_posted`: `both`, `internal`, `public`, `none` or `not-requested`.

## Required Runner Key Vault secrets

Graph app creds, first match wins: `M365-TenantId`/`-ClientId`/`-ClientSecret` (certified Microsoft 365
extension app, preferred, already holds `User.ReadWrite.All`/`Directory.ReadWrite.All`), else `Entra-*`,
else `Graph-*`. Add `RoleManagement.Read.Directory` + `IdentityRiskyUser.Read.All` to that app (they add to its
existing permissions, so leave those in place) and assign it a password-admin role, or the reset PATCH / gate reads return 403. `aiExtensions: microsoft-entra-id`.

To post the notes (a form Action, or `postNotes: true`), also the PSA secrets, the same names as each PSA's catalog extension:

| PSA | Secrets |
|---|---|
| All | `PSA-Type`: `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` (a runner with only the `CW-*` secrets is treated as ConnectWise) |
| ConnectWise | `CW-ApiUrl` (the full `https://<host>/v4_6_release/apis/3.0`), `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` |
| Autotask | `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret`. Optional: `Autotask-NotePublishId`, `Autotask-NotePublicPublishId`, `Autotask-NoteTypeId` |
| HaloPSA | `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret`. Optional: `Halo-NoteOutcomeId`, `Halo-PublicNoteOutcomeId` |
| Kaseya BMS | `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId` |
| Syncro | `Syncro-ApiUrl`, `Syncro-ApiKey` |
| Zendesk | `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` |

## Import & test

1. AutomationAI → import `password-reset.yml`; **Publish** and **deploy** to the runner holding the secrets.
2. Wire the CloudRadial form to it: an Action question (see [Starting it from a form Action](#starting-it-from-a-form-action)), or a form Automation or ServiceAI Action pointed at the Start webhook's URL and secret.
3. After changing a step, run the strict-mode tests: `pwsh -NoProfile -File password-reset/src/test-parse.ps1` (every input shape) and `pwsh -NoProfile -File password-reset/src/test-finish.ps1` (the notes on all six PSAs). After editing `_shared/psa.ps1`, run `node _shared/inject.js password-reset` to refresh Finish's copy.
4. Node 1's **Test Input** has `submittedByUpn` == the target, run it against a disposable account you own to see `status: success`; change `submittedByUpn` to a different address to see the ownership gate return `rejected`.

> Webhook secrets are stripped from this export, the portal issues a new URL/secret on import. A `success`
> run changes that account's password and revokes its sessions; test against a disposable account.
