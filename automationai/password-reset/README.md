# Password Reset (Self-Service)

Self-service Microsoft 365 password reset, fired by a CloudRadial ticket webhook / ServiceAI. A
**broken-out** rebuild of the original single-node workflow — identical behaviour and output contract,
but with **one step per concern** so each gate is legible and independently testable.

Nodes: **Parse & Validate → Resolve & Ownership Gate → Safety Gates → Reset Password → Finish.**

## Why this is safe (ownership gate)

A requester may reset **only their own** account. The trusted, portal-injected `submittedByUpn`
(and `userOfficeId` = the submitter's Entra object id) is matched against the target:

- exact object-id match (`userOfficeId` == target `id`), else
- email match (`submittedByUpn` == the target's UPN / mail / any proxy address).

If the submitter is missing, or doesn't match the target, the run **fails closed** (`status: rejected`).
`submittedByUpn` is injected by CloudRadial from the authenticated session (falling back to the Ticket
object) — it is **never** a user-typed field.

## Trigger payload

| Field | Meaning |
|---|---|
| `userPrincipalName` (or `email`) | the account to reset (form field) |
| `submittedByUpn` | TRUSTED authenticated submitter (injected; falls back to Ticket `SubmittedByEmail`/`ContactEmail`/…) |
| `userOfficeId` | submitter's Entra object id (`@UserOfficeId`) — enables an exact id match |
| `companyTenantId` | requesting company's M365 tenant GUID — used for tenant scoping |
| `revokeSessions` | optional, defaults **true** |
| `ticketId` | for the note write-back |

Handles both a flat `{key:value}` body and the nested `{trigger:{Ticket:{Questions:[{Id,Value}]},Company:{…}}}` shape.

## Gates (all fail-closed), in order

1. **Ownership** — submitter must equal the target (above).
2. **Disabled** — a disabled account is not reset (possible offboarding/hold).
3. **Tenant scope** — if a valid `companyTenantId` GUID is present, it must match the tenant this runner is credentialed for (blocks cross-tenant).
4. **Privileged** — the target must hold **no** Entra directory role (admins go through a technician).
5. **Risk** — best-effort Identity Protection check; high-risk / at-risk / confirmed-compromised is blocked.

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
The workflow **returns** the notes; it does not post to the PSA itself — the caller (ServiceAI/CloudRadial)
writes them to the ticket.

## Required Runner Key Vault secrets

Graph app creds, first match wins: `M365-TenantId`/`-ClientId`/`-ClientSecret` (certified Microsoft 365
extension app — preferred, already holds `User.ReadWrite.All`/`Directory.ReadWrite.All`), else `Entra-*`,
else `Graph-*`. App also needs `RoleManagement.Read.Directory` + `IdentityRiskyUser.Read.All` and a
password-admin role, or the reset PATCH / gate reads return 403. `aiExtensions: microsoft-entra-id`.

## Import & test

1. AutomationAI → import `password-reset.yml`; **Publish** and **deploy** to the runner holding the secrets.
2. Wire the CloudRadial form/Automation (or ServiceAI Action) to the Start webhook's URL + secret.
3. Node 1's **Test Input** has `submittedByUpn` == the target — run it against a disposable account you own to see `status: success`; change `submittedByUpn` to a different address to see the ownership gate return `rejected`.

> Webhook secrets are stripped from this export — the portal issues a new URL/secret on import. A `success`
> run changes that account's password and revokes its sessions; test against a disposable account.
