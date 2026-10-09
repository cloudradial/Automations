# Let Users Reset Their Own MFA Safely

A user who lost their phone or authenticator resets their own multi-factor authentication from the portal in seconds, and built-in checks stop anyone resetting another person's, an admin's, a disabled or an at-risk account.

**Marketplace ID:** TBD | **Type:** Workflow (PowerShell steps, no AI)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `mfa-reset.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/mfa-reset/mfa-reset.yml) |
| Download `mfa-reset.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/mfa-reset/mfa-reset.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/mfa-reset/src) |
| All files in this automation | [mfa-reset](https://github.com/cloudradial/Automations/tree/main/mfa-reset) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/mfa-reset) |

## How it works

Three steps, no AI. It has the same shape as [Password Reset](../password-reset/), with a stricter ownership gate.

1. **Read the request.** Reads the submitter from the portal's trusted tokens (`@UserEmail` and `@UserOfficeId`), plus the account to reset. When no account is named, the account is the submitter's own. Accepts a flat body (portal form, ServiceAI Action, manual run) or the CloudRadial `{Ticket:{Questions}, Company}` shape. A value left as a literal `@token` counts as not given.

   **How the body arrives:** the same pattern as Password Reset. The step has a `trigger` parameter bound to `{{ nodes.trigger.output }}`, so a webhook run hands it `{trigger: <body>}` and the step unwraps it. A manual run's input without that wrapper is read as the body itself. Because the binding needs a value, a manual run must have non-empty input: use the first step's Test Input.
2. **Check the requester and the account.** Changes nothing. Every check fails closed (`status: rejected`):
   1. **Tenant.** If the portal sends `@CompanyTenantId`, it must be the Microsoft 365 tenant this runner's app signs in to.
   2. **Ownership.** The submitter must be the account. **When `@UserOfficeId` is sent, only an exact Entra object id match passes**, and a mismatch is refused even if the email matches. Only when it is blank (or a literal `@token`) does `@UserEmail` have to match the account's UPN, mail or an SMTP proxy address. This is stricter than Password Reset, which falls back to the email match on an id mismatch, because clearing MFA is the higher-risk change. These tokens come from the signed-in portal session, and a form answer can't override them. With neither token present, the request is refused.
   3. **Disabled.** A disabled account isn't reset (it may be offboarding or on hold).
   4. **Admin roles.** The account must hold no Entra directory role: not directly, not through a role-assignable group, and not as an eligible (PIM) assignment. Admins go through a technician.
   5. **Risk.** An account Identity Protection marks as at risk, compromised or high risk isn't reset, because clearing MFA would let an attacker enroll their own device. When the tenant or the app can't read risk (no Entra ID P2, or no permission), this check is skipped with a warning.
3. **Clear MFA and record it.** Removes **every registered sign-in method except the password**: Microsoft Authenticator, phone, FIDO2 security keys and passkeys, email, software OATH codes, Windows Hello for Business, macOS platform credentials, and any existing Temporary Access Pass. The password is never changed. If Graph refuses a method on the first try (it can refuse the default method while others remain), it tries once more. Then it signs the user out of every session, so they re-enroll at their next sign-in.
   - **`issue_tap: true`:** also creates a **one-time Temporary Access Pass that lasts 60 minutes** and puts it **only** in the internal ticket note, so a technician can relay it after verifying the user (for example by calling a number already on file). The Temporary Access Pass policy must be on. If it isn't, the reset still completes and the note says how to turn it on.
   - **Ticket note:** the method detail (phone numbers masked to the last four digits), anything that couldn't be removed, and any Temporary Access Pass go **only in an internal note** on the ticket, written through the shared six-PSA adapter (ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro, Zendesk). A rejected request gets an internal note too, saying why. With `psaCompanyId` set, the note is written only if the ticket belongs to that company.
   - **Public note:** generic. It says MFA was reset and to set it up again at the next sign-in. It never lists methods and never holds the pass. It is returned in the output for the portal to show; the workflow writes no client-visible note to the ticket.
   - **Safe to retry.** The internal note ends with `[mfa-reset: <ticket id>]` (a refused request with `[mfa-reset-request: <ticket id>]`), written with the shared `Add-PsaNote -Marker`. The marker holds only the ticket id, never the account or the pass. Before removing anything, the step reads the ticket's notes; if the marker is already there (ServiceAI **Retry** in Action Runs, or the same request run twice), it changes nothing, creates no second pass (which would replace the one a technician is relaying), adds no note and returns `status: success` with `category: already-done`. If the notes can't be read, it stops with `category: psa-error` before changing anything.

A method type the workflow can't remove (for example a hardware OATH token) is left in place, and the run ends `incomplete` with the method named in the internal note for a technician.

### No confirm step, but a dry run

Most write automations take `confirm` and preview by default. This one doesn't, on purpose: a user resetting their own MFA is the same person approving it, and the ownership gate already proves that, so it matches Password Reset. Instead, **`dry_run: true` runs every check and lists what would be removed without removing anything**. A dry run makes no Graph change, creates no pass, signs nobody out and writes no ticket note. It returns `status: pending_confirmation` with the would-remove list in `internal_note`. Use it for the first test in any tenant.

## Download & import

**Download the workflow:** [`mfa-reset.yml`](https://github.com/cloudradial/Automations/blob/main/mfa-reset/mfa-reset.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required secrets](#required-runner-key-vault-secrets) to the runner of the company it serves, enable the webhook in **Properties**, then **Publish** and **Deploy**. Full steps are under [Import & test](#import--test).

The workflow is **per company**: it reads the running company's Microsoft 365 and PSA secrets, and never writes one client's details into another client's ticket.

## Required runner Key Vault secrets

By name only. Use the same names as the catalog extensions, so one set serves both.

| Secret | For |
|---|---|
| `M365-TenantId`, `M365-ClientId`, `M365-ClientSecret` | Microsoft Graph sign-in (the `Entra-*` and `Graph-*` names also work) |
| `PSA-Type` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` (a `psa` input overrides it). Without it, the note is only in the run output. |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | Optional: `Autotask-NotePublishId`, `Autotask-NoteTypeId` |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Optional: `Halo-NoteOutcomeId` |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId` | |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | |

## Required Graph permissions

Application permissions on the `M365-*` app registration, with admin consent:

| Permission | Why |
|---|---|
| `UserAuthenticationMethod.ReadWrite.All` | List and remove the user's sign-in methods, and create the Temporary Access Pass. |
| `User.Read.All` | Find the account and read its addresses and enabled state. |
| `RoleManagement.Read.Directory` | Check direct, group-based and eligible (PIM) admin roles. |
| `User.RevokeSessions.All` | Sign the user out everywhere after the reset (`User.ReadWrite.All` also works). |
| `IdentityRiskyUser.Read.All` (optional) | The at-risk check. Needs Entra ID P2. Without it, the check is skipped with a warning. |

**For `issue_tap`:** turn on the **Temporary Access Pass** policy (Entra admin center > Protection > Authentication methods > Policies) for the users it serves, and allow one-time passes of 60 minutes.

When a required permission is missing, the step stops before changing anything with a plain sentence naming it, for example "The app registration needs the RoleManagement.Read.Directory application permission, with admin consent." A missing `User.RevokeSessions.All` is found only after the methods are removed, so that run ends `incomplete` with the same sentence in its warnings and internal note.

## Inputs

| Field | Required | Meaning |
|---|---|---|
| `submittedByUpn` | Yes (or `userOfficeId`) | **Map it to `@UserEmail`.** The signed-in submitter. Never a form question. |
| `userOfficeId` | Recommended | **Map it to `@UserOfficeId`.** The submitter's Entra object id. When sent, it must equal the account's object id exactly; the email match is used only when it is blank. |
| `userPrincipalName` | No | The account to reset. Blank means the submitter's own account, which is the usual case. |
| `companyTenantId` | Recommended | `@CompanyTenantId`. When set, the run is refused unless it matches this runner's Microsoft 365 tenant. |
| `ticketId` | Recommended | `@TicketId`. The ticket that gets the internal note. |
| `psaCompanyId` | No | `@CompanyPsaId`. When set, the note is written only if the ticket belongs to this company. |
| `psa` | No | Overrides the `PSA-Type` secret. |
| `issue_tap` | No (default `false`) | `true` creates a one-time, 60-minute Temporary Access Pass, in the internal note only. |
| `dry_run` | No (default `false`) | `true` runs every check and lists what would be removed, and changes nothing. |
| `revokeSessions` | No (default `true`) | `false` skips signing the user out. |

**Portal form webhook body** (Partner > Automations, Webhook activity, absolute URL, method POST, content type `application/json`, header `{"X-Crauto-Webhook-Secret": "<secret>"}`):

```json
{
  "submittedByUpn": "@UserEmail",
  "userOfficeId": "@UserOfficeId",
  "companyTenantId": "@CompanyTenantId",
  "ticketId": "@TicketId",
  "psaCompanyId": "@CompanyPsaId",
  "issue_tap": "false"
}
```

The form itself needs no questions about whose account it is. Don't add a question with a Field ID that matches a predefined token.

## Output

`status` (`success`, `rejected`, `incomplete`, `error`, or `pending_confirmation` for a dry run), `message`, `public_note` (safe to show the user), `internal_note` (the full detail and any pass), `chatReply`, `ticket_id`, `user_id`, `upn`, `dry_run`, `category` (why a request was refused: `tenant-scope`, `resolution`, `identity-unverified`, `identity-mismatch`, `disabled`, `privilege` or `risk`; `already-done` for a rerun that found the reset recorded on the ticket; `graph-error` or `psa-error` for an error), `methods_found`, `methods_removed`, `methods_not_removed`, `sessions_revoked`, `tap_issued`, `note_written`, `actions`, `warnings` and `audit`. The Temporary Access Pass appears only in `internal_note`, never in a top-level field or the public note.

## Import & test

1. Import `mfa-reset.yml`, add the secrets above to the company's runner vault, then **Publish** and **Deploy** to that runner.
2. **Dry run first.** In **Run**, use the first step's Test Input with `submittedByUpn` set to a test account you own and `dry_run: true`. Expect `status: pending_confirmation` and the would-remove list in `internal_note`. Nothing changes.
3. **Check a refusal.** Set `userPrincipalName` to a different account and run again. Expect `status: rejected`, `category: identity-mismatch`.
4. **Live run.** On a disposable test account with an authenticator registered, run with `dry_run: false` (and `issue_tap: true` if the policy is on) and a `ticketId`. Expect `status: success`, the methods gone in Entra, and an internal note on the ticket.
5. **Wire the trigger.** Enable the webhook in **Properties** (AutomationAI issues the URL and secret), redeploy, and point the portal form's Webhook activity at it with the body above.

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. A live run removes that account's MFA methods and signs it out, so test on a disposable account. The step logic lives in `src/`: edit `parse.ps1`, `verify.ps1` or `reset.ps1`, run `node src/build.js`, then `pwsh -NoProfile -File src/test.ps1` (strict mode, mocked Graph and PSAs). Never edit the `.yml` by hand.
