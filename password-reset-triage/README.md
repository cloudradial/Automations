# Resolve Password Reset Tickets Automatically

Password reset tickets close on their own when the person asking owns the account, and wait for a quick confirmation when someone else asked.

## What happens

When a password reset ticket comes in, ServiceAI hands it to this automation during triage. It checks who signed in to send the request and whose account needs resetting.

**When users ask for their own account.** Their Microsoft 365 password is reset to a temporary one and they're signed out everywhere. The ticket gets a friendly note telling them to sign in with the temporary password and choose a new one. The temporary password itself is shown only to your team.

**When someone asks for another person's account.** Nothing changes. The ticket gets a note saying someone will reach out shortly to confirm, so your team can check before acting.

**When the ticket doesn't say who asked.** Nothing happens, and the ticket stays with your team.

## What it protects

- **Admins are never reset from a ticket.** Accounts with an admin role are always left for a technician.
- **Guest and disabled accounts are skipped.** Your team handles those by hand.
- **Only the account owner gets an automatic reset.** A request for someone else always waits for a person to confirm.
- **The temporary password stays private.** It appears only in the run logs your team can see, never in the client's note.

## Works with

- **Microsoft 365:** the accounts it resets.
- **Your PSA:** tickets reach it through ServiceAI, which also posts the notes back. If your PSA names the ticket fields differently, a small change may be needed (see the technical details).

## What you need

- ServiceAI, connected to your PSA
- AutomationAI, with Microsoft 365 connected for the clients you want covered

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/password-reset-triage/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. In **Properties**, turn on the webhook. Copy its URL and secret.
4. Click **Publish**, then **Deploy** to the runner that holds your Microsoft 365 connection.

**In ServiceAI:**

1. Add an **Action** set to **Use in Triage**.
2. Point it at the webhook URL you copied, and save the secret with it.

If a client's Microsoft 365 connection is saved under that company in AutomationAI, set **Company** to that client on the two reset steps in the designer. Do this again after every import.

**Test it.** Raise a password reset ticket for a spare test account, signed in as that account, and check it is reset. Then raise one as a different user and check nothing changes.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/password-reset-triage#technical-details) cover how it reads each ticket, the safety checks and the full test steps.

---

## Technical details

**Formerly:** Password Reset (ServiceAI Triage) | **Marketplace ID:** AAI-00028 | **Type:** Workflow (ServiceAI Triage Action) | **Version:** 1.0.0

## Files

Each version is published as a release, with `password-reset-triage.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/password-reset-triage/v1.0.0).

| What | Link |
|---|---|
| Download `password-reset-triage.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/password-reset-triage/v1.0.0) |
| View the current source | [`password-reset-triage.yml`](https://github.com/cloudradial/Automations/blob/main/password-reset-triage/password-reset-triage.yml) |
| All files in this automation | [password-reset-triage](https://github.com/cloudradial/Automations/tree/main/password-reset-triage) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/password-reset-triage) |
| Marketplace listing | [AAI-00028](https://automations.cloudradial.com/marketplace/AAI-00028) |

## How it works

The **triage** counterpart to [Password Reset (Self-Service)](https://github.com/cloudradial/Automations/tree/main/password-reset). Fired by a
**ServiceAI Action in Use-in-Triage mode**, where the trigger is a ticket. The ticket carries the target
user (email/UPN) + tenant **and** the authenticated requester (`submittedByUPN`), and the workflow decides
what to do based on who asked.

## Download & import

**Download the workflow:** [`password-reset-triage.yml`](https://github.com/cloudradial/Automations/releases/tag/password-reset-triage/v1.0.0)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), enable the webhook in **Properties** (the portal mints the URL + secret), then publish and deploy. Wire a ServiceAI **Use in Triage** Action at the webhook. Full steps are under [Import & test](#import--test) below.

### Microsoft 365 secrets stored per company

Sometimes a client's Microsoft 365 secrets (`M365-TenantID`, `M365-ClientID` and `M365-ClientSecret`) are saved under the company in AutomationAI (**Companies**, policy *Require company*) instead of in the runner vault. In that case, open the workflow in the designer and set **Company** to that client on these steps: **Resolve & Decide** and **Reset If Verified**. Then publish and deploy.

- **Set it again after every import.** Importing a workflow clears the step Company setting, because the `.yml` doesn't carry it.
- **Without it,** the steps use the runner's shared secrets, so they sign in to the wrong tenant or fail.

## Decision logic

| Ticket carries | Outcome |
|---|---|
| **No `submittedByUPN`** | **Does not trigger**, returns `status: incomplete`, no action. The authenticated requester is required. |
| **`submittedByUPN` == target** | **Reset**, verified self-request. Sets a temp password + revokes sessions (subject to the safety gates below). `status: complete`. |
| **`submittedByUPN` != target** | **No reset**, returns `status: pending_confirmation` with a note that *"someone will reach out shortly to confirm"* before any change. Protects against someone requesting a reset on another user's account. |

`submittedByUPN` (and optional `submittedByOfficeId`) is the un-spoofable, portal-authenticated requester, the same trust anchor as the self-service workflow's `@UserEmail`/`@UserOfficeId`. Match is by object id
first, then UPN/mail (case-insensitive).

## Reading fields from the ticket

*Use in Triage* posts the **raw PSA ticket payload**. The Parse node scans common field names for each value, both top-level and inside a nested `contact` / `submitter` / `authenticatedUser` object:

- **Target email:** `userPrincipalName`, `contactEmail`, `contactEmailAddress`, `email`, `emailAddress`, `mail`, `userEmail`, …
- **Requester:** `submittedByUPN`, `submittedBy`, `submitterUpn`, `authenticatedUpn`, `requestedByUpn`, … (+ `submittedByOfficeId`, `userOfficeId`, … for the object id)
- **Tenant:** `companyTenantId`, `tenantId`, `customerTenantId` (falls back to the `M365-TenantId` secret)

**If your PSA uses a field name not listed, add it to the matching list in node 1** (the Parse & Validate step).

## Safety gates (reset path only)

Applied only when a reset would proceed: user-not-found, **guest (B2B)**, **disabled**, and **privileged role**
(Global/Privileged/Auth/Security/User/Helpdesk/Exchange/SharePoint/App Admin) are all fail-closed. A ticket
must never auto-reset an admin.

## Output contract (same shape as the self-service workflow)

```json
{ "status": "complete" | "pending_confirmation" | "incomplete",
  "message": "...", "public_note": "...", "internal_note": "...",
  "upn": "...", "requester": "...", "ticket_id": "..." }
```

- `complete` → `internal_note` carries the **temporary password** (admin-visible only, in the AutomationAI run
  and the ServiceAI action-run log); `public_note` is the safe customer message.
- `pending_confirmation` → `public_note` is *"someone will reach out shortly to confirm"*; no password changed.
- `incomplete` → generic `public_note`, reason in `internal_note`.

**Posting the note to the ticket:** the workflow returns `public_note`/`internal_note`; ServiceAI (which owns
the PSA connection) posts them. If you want the workflow to write the ticket note itself (matching the
self-service workflow's direct-PSA-API note), tell me the PSA + secret names and I'll add that step.

## Required Runner Key Vault secrets

`M365-TenantId`, `M365-ClientId`, `M365-ClientSecret` (the certified Microsoft 365 extension app, which already holds `User.ReadWrite.All` / `Directory.ReadWrite.All`, so there is nothing to add; leave its existing permissions in place). No PSA secrets needed for the return-contract design.

## Import & test

1. AutomationAI → import `password-reset-triage.yml`; **Publish** to the runner holding the M365 secrets.
2. Copy the Start webhook's URL + secret; point the ServiceAI Action + Secret at it.
3. Node 1's **Test Input** carries a sample where `submittedByUPN` == `contactEmail` → run against a disposable
   account to see `status: complete`. Change `submittedByUPN` to a different address to see `pending_confirmation`.

> A `complete` run changes that user's password and revokes sessions. Test against a disposable account.
