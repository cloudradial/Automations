# Password Reset (ServiceAI Triage)

The **triage** counterpart to [Password Reset (Self-Service)](https://github.com/cloudradial/helpers/tree/main/automationai/password-reset). Fired by a
**ServiceAI Action in Use-in-Triage mode**, where the trigger is a ticket. The ticket carries the target
user (email/UPN) + tenant **and** the authenticated requester (`submittedByUPN`), and the workflow decides
what to do based on who asked.

## Download & import

**Download the workflow:** [`password-reset-triage.yml`](https://github.com/cloudradial/helpers/blob/main/automationai/password-reset-triage/password-reset-triage.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), enable the webhook in **Properties** (the portal mints the URL + secret), then publish and deploy. Wire a ServiceAI **Use in Triage** Action at the webhook. Full steps are under [Import & test](#import--test) below.

## Decision logic

| Ticket carries | Outcome |
|---|---|
| **No `submittedByUPN`** | **Does not trigger** — returns `status: incomplete`, no action. The authenticated requester is required. |
| **`submittedByUPN` == target** | **Reset** — verified self-request. Sets a temp password + revokes sessions (subject to the safety gates below). `status: complete`. |
| **`submittedByUPN` != target** | **No reset** — returns `status: pending_confirmation` with a note that *"someone will reach out shortly to confirm"* before any change. Protects against someone requesting a reset on another user's account. |

`submittedByUPN` (and optional `submittedByOfficeId`) is the un-spoofable, portal-authenticated requester —
the same trust anchor as the self-service workflow's `@UserEmail`/`@UserOfficeId`. Match is by object id
first, then UPN/mail (case-insensitive).

## Reading fields from the ticket

*Use in Triage* posts the **raw PSA ticket payload**. The Parse node scans common field names for each value —
both top-level and inside a nested `contact` / `submitter` / `authenticatedUser` object:

- **Target email:** `userPrincipalName`, `contactEmail`, `contactEmailAddress`, `email`, `emailAddress`, `mail`, `userEmail`, …
- **Requester:** `submittedByUPN`, `submittedBy`, `submitterUpn`, `authenticatedUpn`, `requestedByUpn`, … (+ `submittedByOfficeId`, `userOfficeId`, … for the object id)
- **Tenant:** `companyTenantId`, `tenantId`, `customerTenantId` (falls back to the `M365-TenantId` secret)

**If your PSA uses a field name not listed, add it to the matching list in node 1.** (Ideally verify the exact
names against the deployed self-service workflow's Parse node — the designer was too busy to read live.)

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

`M365-TenantId`, `M365-ClientId`, `M365-ClientSecret` (certified Microsoft 365 extension app —
`User.ReadWrite.All` / `Directory.ReadWrite.All`). No PSA secrets needed for the return-contract design.

## Import & test

1. AutomationAI → import `password-reset-triage.yml`; **Publish** to the runner holding the M365 secrets.
2. Copy the Start webhook's URL + secret; point the ServiceAI Action + Secret at it.
3. Node 1's **Test Input** carries a sample where `submittedByUPN` == `contactEmail` → run against a disposable
   account to see `status: complete`. Change `submittedByUPN` to a different address to see `pending_confirmation`.

> A `complete` run changes that user's password and revokes sessions. Test against a disposable account.
