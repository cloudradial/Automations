# Remind People Before Their Microsoft 365 Password Expires

Every day, email each person whose Microsoft 365 password is about to expire, with the date and how to change it, so nobody gets locked out and raises a ticket.

**Formerly:** Password Expiry Reminder to End User (tracker 9.6) | **Marketplace ID:** TBD | **Type:** Workflow (PowerShell, no AI, runs on a schedule)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `password-expiry-reminder.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/password-expiry-reminder/password-expiry-reminder.yml) |
| Download `password-expiry-reminder.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/password-expiry-reminder/password-expiry-reminder.yml) |
| Step source, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/password-expiry-reminder/src) |
| All files in this automation | [password-expiry-reminder](https://github.com/cloudradial/Automations/tree/main/password-expiry-reminder) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/password-expiry-reminder) |
| Shared Microsoft 365 and email code | [`_shared/graph.ps1` and `_shared/postmark.ps1`](https://github.com/cloudradial/Automations/tree/main/_shared) |

## How it works

The workflow runs against one Microsoft 365 tenant: the one whose app secrets are in the runner Key Vault. Run one copy (and one Routine) per client. It doesn't use a PSA and creates no tickets.

`Start > Read inputs > Find passwords that expire soon > Send reminders > End`

1. **Find passwords that expire soon** (read-only) reads each verified domain's password lifetime and every user. If no domain has an expiry policy, the run ends here with success and says so. Microsoft's default for new tenants is that passwords never expire, so this is a normal result, not an error.
2. For everyone else it works out the expiry date: the last password change plus the lifetime of the domain in their sign-in name. It skips:
   - disabled accounts and guests,
   - accounts set to never expire (`DisablePasswordExpiration`), or on a domain that never expires,
   - accounts with no email address (no mailbox to send to),
   - passwords that have already expired (Microsoft 365 asks them to change it at their next sign-in),
   - **accounts synced from on-premises Active Directory.** Their expiry is set by Active Directory, which this workflow can't read, so it never emails them a date that could be wrong. They are counted and named in `warnings`.
3. **Send reminders** emails each person on a reminder day (14, 7 and 1 days before expiry by default). The email greets them by first name, gives the exact expiry date and time, explains three ways to change the password (Ctrl+Alt+Del on a work PC, Outlook on the web, or the reset page), and says IT will never ask for their password. It never contains a password.

**The reminder rule.** A person is due when the number of whole days until their password expires (counted in `timeZone`, UTC by default) is one of `daysBeforeExpiry`. On a daily Routine that means one email per reminder day and never the same email two days running. A missed day isn't made up on its own: if the runner was down, run it once by hand with `catchUpDays` set to the number of days since the last good run plus one. A person whose reminder day fell in that window gets one email (for the nearest reminder day, with the real number of days left), and nobody gets more than one email per run. Leave `catchUpDays` at 1 on the Routine itself, or people get each reminder twice.

**Safe to run again the same day.** When sending through Graph, the step first reads the sender mailbox's Sent Items since midnight and skips anyone who already got today's reminder (this needs `Mail.ReadBasic.All`; without it the run warns and sends anyway). Postmark has no such check, so a second Postmark run on the same day emails people again.

**How it sends.** Through Microsoft Graph as the mailbox in `PasswordExpiry-Sender`, with a copy kept in that mailbox's Sent Items. If that secret isn't set and the Postmark secrets are, it sends through Postmark instead. One failed email is counted and the rest still go out. A refused permission or a missing sender mailbox stops the sending, and the message names what to fix.

**Report Archives.** This workflow doesn't write a CloudRadial report. The run output in Action Runs lists who was emailed and why others were skipped, which is enough for a daily job; a monthly archive report would need CloudRadial secrets and a company id that this workflow otherwise doesn't need.

## Download & import

**Download the workflow:** [`password-expiry-reminder.yml`](https://raw.githubusercontent.com/cloudradial/Automations/main/password-expiry-reminder/password-expiry-reminder.yml)

Then in AutomationAI: **Workflows > Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), **Publish**, **Deploy** to the runner that holds that client's secrets, and attach a daily **Routine** (the schedule isn't part of the export). Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

| Secret | Needed for |
|---|---|
| `M365-TenantId`, `M365-ClientId`, `M365-ClientSecret` (the `Entra-*` and `Graph-*` names work too) | Reading the client's domains and users, and sending through Graph |
| `PasswordExpiry-Sender` | The mailbox the reminders are sent from, for example `it-notices@contoso.com`. Use a real, licensed (or shared) mailbox people will recognise. |
| `PasswordExpiry-ResetUrl` (optional) | The page the email links to. Default `https://passwordreset.microsoftonline.com/` (Microsoft self-service password reset, which must be turned on for your users). `https://mysignins.microsoft.com/security-info/password/change` is a good choice when self-service reset is off. A run's `resetUrl` input overrides it. |
| `PasswordExpiry-TimeZone` (optional) | The time zone for "today" and the expiry date in the email, for example `Eastern Standard Time` or `America/New_York`. Default `UTC`. |
| `Postmark-ServerToken`, `Postmark-FromEmail` (optional, the alternative to `PasswordExpiry-Sender`) | Sending through Postmark. `Postmark-FromEmail` must be a verified Postmark sender. `Postmark-ApiUrl` is optional. Used only when `PasswordExpiry-Sender` isn't set. |

### Microsoft 365 secrets stored per company

When a client's Microsoft 365 secrets are saved under the company in AutomationAI (**Companies**, policy *Require company*) instead of in the runner vault, open the workflow in the designer and set **Company** to that client on **Find passwords that expire soon** and **Send reminders**, then publish and deploy. Set it again after every import: importing clears the step Company setting.

## Required Graph permissions

Add these application permissions to the Microsoft 365 app registration you already use (the one in the `M365-*` secrets), then grant admin consent in the client tenant. They add to what the app already has, so leave its existing permissions in place.

| Permission | Why |
|---|---|
| `User.Read.All` | Reading users, their last password change and password policies |
| `Domain.Read.All` | Reading each domain's password lifetime |
| `Mail.Send` | Sending the reminders as the `PasswordExpiry-Sender` mailbox (not needed with Postmark). To limit it to that one mailbox, use an Exchange application access policy. |
| `Mail.ReadBasic.All` (optional) | Reading the sender's Sent Items so a same-day rerun doesn't email anyone twice. Reads subjects and recipients only, never message bodies. |

If a permission is missing, the run stops with a sentence naming it, for example: "Can't read the tenant's password expiry settings. The app registration needs the Domain.Read.All application permission, with admin consent. No email was sent."

## Limitation: accounts synced from Active Directory

For accounts synced from on-premises Active Directory (`onPremisesSyncEnabled`), the password and its expiry live in Active Directory, and Microsoft 365 doesn't hold the real expiry date. The runner can't read Active Directory, so these accounts are never emailed. They are counted in `skippedSynced` and named in `warnings`. Remind them with Active Directory's own tools, or a script on a server that can read Active Directory.

## Inputs

All inputs are optional. A Routine sends none, so every one has a default.

| Input | Default | Meaning |
|---|---|---|
| `daysBeforeExpiry` | `14,7,1` | Days before expiry on which a reminder goes out, from 0 (the day it expires) to 365. A comma list or a JSON list. |
| `preview` | `false` | `true` lists who would be emailed today and sends nothing. `dryRun` and `dry_run` work too. Use it for the first run. |
| `catchUpDays` | `1` | How many days back to look for a missed reminder day (1 = today only, up to 30). Only for a one-off run after the Routine was off; see the reminder rule. |
| `resetUrl` | `PasswordExpiry-ResetUrl` secret, else `https://passwordreset.microsoftonline.com/` | The page the email links to. Must start with `https://`. |
| `timeZone` | `PasswordExpiry-TimeZone` secret, else `UTC` | Time zone for counting days and showing the expiry date |
| `onlyUsers` | everyone | Sign-in names, email addresses or user object ids to limit the run to, for testing, for example `"pat.doe@contoso.com"` |
| `company_tenant_id` | empty | Optional safety check: when given, it must be this runner's Microsoft 365 tenant (`M365-TenantId`) or the run is rejected before anything is read |

**Why `preview` and not `confirm`:** like [Waiting-on-Client Nudge](https://github.com/cloudradial/Automations/tree/main/waiting-on-client-nudge), this job runs on a schedule with nobody watching, so the default is to act. `preview: true` is the dry-run switch, and the first step's Test Input has it set.

Bad input fails closed: the run stops with a plain sentence and sends nothing. An `onlyUsers` value with nothing valid in it stops the run rather than email everyone.

## Output

`status` (`success`, `pending_confirmation` for a preview with people to email, `incomplete` when any email failed, `rejected` for a tenant mismatch, `error` for a setup problem), `message` (one plain sentence), `preview`, `sent_via`, `tenant_id`, `checked_at`, `counts` (`checked`, `expiringSoon`, `due`, `emailed`, `alreadySentToday`, `failed`, `skippedSynced`, `skippedNeverExpires`, `skippedDisabled`, `skippedGuests`, `skippedNoMail`, `skippedOther`, `alreadyExpired`), `emailed` (sign-in name, address, days left and expiry for each person emailed), `due` (everyone on a reminder day, with the result for each), `skipped` (accounts skipped for a reason worth reading), `actions` and `warnings`. `expiringSoon` counts everyone whose password expires within the largest reminder day, emailed today or not.

## Import & test

1. **Import** `password-expiry-reminder.yml` on **Workflows > Import**. Add the secrets above to the runner Key Vault, then **Publish** and **Deploy** to that runner.
2. **Preview everyone.** Run it from **Test** with `{"preview": true}` (the first step's Test Input). Check `message`, `counts` and `warnings`: the right people due, synced accounts listed, nobody emailed. If it says passwords never expire, the tenant has no expiry policy and there is nothing to do.
3. **One test account live.** Pick a test account whose password expires within 14 days, and run with `{"onlyUsers": "test.user@contoso.com", "daysBeforeExpiry": "<its days left>"}`. Check the email arrived from the sender mailbox and reads well, and that the link works.
4. **Run the same thing again.** With `Mail.ReadBasic.All` granted, nothing is sent and `alreadySentToday` is 1.
5. **Schedule it.** Attach a daily **Routine** with no input, every day including weekends (for example `0 8 * * *`, 08:00 daily), so no reminder day is skipped. A Routine runs the deployed version, so redeploy after every edit.

## Editing it

The three PowerShell steps are generated. Edit the files in `src/`, never the script inside the `.yml`:

| File | What it is |
|---|---|
| `src/read-inputs.ps1`, `src/find-expiring.ps1`, `src/send-reminders.ps1` | The three steps |
| `src/common.ps1` | Input, state and date helpers pasted into every step |
| `src/build.js` | Assembles the `.yml`: pastes `common.ps1`, then `_shared/graph.ps1` and `_shared/postmark.ps1` (through `_shared/inject.js`) |
| `src/test.ps1` | Strict-mode harness that runs the shipped steps against a mock tenant (built on `_shared/tests/mock.ps1`) |

```
cd password-expiry-reminder
node src/build.js                     # writes password-expiry-reminder.yml
pwsh -NoProfile -File src/test.ps1    # runs the shipped steps against the mock tenant
```

Both need js-yaml: set `JS_YAML_PATH`, or run `npm install` in `_shared`.

## Not yet proven live

Tested only against the mock tenant in `src/test.ps1`. Check these on the first preview and test runs:

- **`passwordValidityPeriodInDays`** on `/domains`: that a never-expire domain reads `2147483647` (or empty) and an expiring one reads its days.
- **`lastPasswordChangeDateTime`**, `passwordPolicies` and `onPremisesSyncEnabled` come back with `User.Read.All` on `$select`.
- **The Sent Items check:** the `sentDateTime` filter on `mailFolders/sentitems/messages` with `Mail.ReadBasic.All`.
- **The Ctrl+Alt+Del route** only works on Windows PCs joined to Entra ID that the person signs in to with this account. The Outlook on the web menu wording may change.
- **Exchange sending limits** (about 30 messages a minute per mailbox). Graph throttling is retried, but a very large first run may be slow.
