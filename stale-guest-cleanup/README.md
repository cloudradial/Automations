# Find and Clean Up Unused Microsoft 365 Accounts and Guests

Once a month, see which of a client's Microsoft 365 accounts and guests haven't signed in for 90 days, then disable only the ones you approve.

## What happens

- **Once a month, a review is saved.** A plain report lists every inactive account and guest, with their last sign-in and how long they've been inactive. It goes into the client's **Account Reviews** report archive, which only admins can see. It never goes into the knowledge base.
- **Nothing changes on its own.** The monthly run only reviews. Your team reads the report and decides.
- **You approve, it disables.** Run it again by hand with the accounts you picked from the report. It turns off sign-in for each one and signs them out everywhere. That run is saved as its own report, so every change is on record.
- **Optionally, a ticket note.** Give it a ticket number and it adds an internal note to that ticket with the counts, the accounts and where the report is.

## What it protects

- **Admins are never disabled.** Anyone with an admin role is flagged "review manually".
- **Accounts synced from on-premises are never disabled.** They're flagged, because they have to be turned off in Active Directory.
- **It double-checks before disabling.** An approved account is only disabled if it's still inactive on that run. Anyone who signed in since is skipped, and the report says why.
- **New accounts are left alone.** Accounts created in the last 90 days are skipped.
- **It stops at the first problem** and reports what didn't run.
- **One client per run.** One client's accounts never show up in another client's report or ticket.
- **No duplicate notes.** If a run repeats, the ticket note isn't added twice.

## Works with

Microsoft 365. For the optional ticket note: ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk.

- **Microsoft 365:** the tenant needs Microsoft Entra ID P1 (included in Business Premium and E3/E5) to read last sign-in times.
- **Guests:** reviewed by default under the same rules. A guest who never accepted their invitation is listed once it's older than 90 days. You can leave guests out.

## What you need

- AutomationAI, with the client's Microsoft 365 connected (read access to users, sign-ins and admin roles, plus permission to disable accounts and sign them out for approval runs)
- Your CloudRadial API connected in AutomationAI, for the report
- Your PSA connected in AutomationAI, only if you want ticket notes

## Set it up

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/stale-guest-cleanup/v1.0.0).
2. In AutomationAI, go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy** to the runner that has this client's Microsoft 365 connection.
4. Give the runner the client's CloudRadial company number, so the scheduled run knows where to save the report.
5. Go to **Routines > New**, pick this workflow and a monthly schedule, for example 8am on the 1st. Add it again after any fresh import, and redeploy after every edit.

Optional: change how many days count as inactive, or leave guests out.

**Test it.** Run it once by hand, then check the client's Account Reviews archive for the report and that admins are flagged. Try disabling on a spare test account first.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/stale-guest-cleanup#technical-details) cover the exact rules, permissions, settings and how to test it.

---

## Technical details

**Marketplace ID:** AAI-00064 | **Type:** Workflow (run monthly by a Routine, or by hand) | **Version:** 1.0.0

## Files

Each version is published as a release, with `stale-guest-cleanup.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/stale-guest-cleanup/v1.0.0).

| What | Link |
|---|---|
| Download `stale-guest-cleanup.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/stale-guest-cleanup/v1.0.0) |
| View the current source | [`stale-guest-cleanup.yml`](https://github.com/cloudradial/Automations/blob/main/stale-guest-cleanup/stale-guest-cleanup.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/stale-guest-cleanup/src) |
| All files in this automation | [stale-guest-cleanup](https://github.com/cloudradial/Automations/tree/main/stale-guest-cleanup) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/stale-guest-cleanup) |

## How it works

The workflow runs against one company: the Microsoft 365 tenant whose app secrets are in the runner Key Vault. Run one copy (and one Routine) per client, so one client's accounts never appear in another client's report or ticket.

Steps: **Read inputs > Find inactive accounts > Disable confirmed accounts > Report and note.** No AI step is used; the rules are fixed.

1. **Find inactive accounts** (read-only) reads every user with its last sign-in times, and who holds a directory admin role. An account is listed when:
   - it is turned on (already-disabled accounts are skipped),
   - it was created more than `days` days ago (newer accounts are skipped), and
   - it has no sign-in of any kind (interactive, background or successful) in the last `days` days, or has never signed in.

   Guests follow the same rules, so a guest who never accepted or used an invitation is listed once the invitation is older than `days` days. Set `include_guests` to false to leave guests out.
2. Two kinds of account are listed but **flagged and never disabled** by this workflow:
   - **Admin, review manually:** it holds a directory admin role, directly or through a role-assignable group.
   - **Synced from on-premises:** it comes from Active Directory, so it has to be disabled there.
3. **Disable confirmed accounts.** Nothing is disabled automatically. With `confirm` false (the default) nothing changes. With `confirm` true, the workflow disables only the accounts in `disable_ids` that are **also on this run's fresh list** and not flagged. Ids from an earlier run are never trusted on their own: an account that has signed in since, or was disabled already, is skipped and the report says why. For each account it turns off sign-in, then signs it out of every session. It stops at the first failure and reports what didn't run.
4. **Report and note** writes a plain-language HTML report into the company's **Account Reviews** report archive (Compliance > Reports, visible to admins only, never the knowledge base). A review run is saved as "Inactive accounts review YYYY-MM-DD" (a rerun the same day replaces it); a confirm run is saved as "Inactive accounts changes YYYY-MM-DD HH:mm UTC", so every change is logged. When `ticket_id` is given, it adds an **internal** note to that ticket in any of the six supported PSAs (ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro, Zendesk) with the counts, the accounts and where the report is. The note is retry-safe: it ends with a marker (the review day and settings, or a short code for the accounts a confirm run was asked to disable, never their names), so a ServiceAI Retry or a Routine that runs twice does not add it again.

If the report or note can't be written, the run still finishes, says so in `warnings`, and returns the report as `report_html`.

## Download & import

**Download the workflow:** [`stale-guest-cleanup.yml`](https://github.com/cloudradial/Automations/releases/tag/stale-guest-cleanup/v1.0.0)

Then in AutomationAI: **Workflows > Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), then publish and deploy it to the runner that holds that client's secrets. **Attach a monthly Routine after import** (the schedule isn't part of the export). Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

| Secret | Needed for |
|---|---|
| `M365-TenantId`, `M365-ClientId`, `M365-ClientSecret` (the `Entra-*` and `Graph-*` names work too) | Reading and disabling the client's Microsoft 365 accounts |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Writing the report into Report Archives |
| `CloudRadial-CompanyId` | The CloudRadial company the report belongs to. Needed for a Routine, which sends no input. A run's `company_id` input overrides it. |
| `PSA-Type` plus that PSA's secrets (`CW-*`, `Autotask-*`, `Halo-*`, `KaseyaBMS-*`, `Syncro-*` or `Zendesk-*`) | Only when a run passes `ticket_id`. Same names as the PSA's catalog extension. |

### Microsoft 365 secrets stored per company

Sometimes a client's Microsoft 365 secrets (`M365-TenantID`, `M365-ClientID` and `M365-ClientSecret`) are saved under the company in AutomationAI (**Companies**, policy *Require company*) instead of in the runner vault. In that case, open the workflow in the designer and set **Company** to that client on these steps: **Find inactive accounts** and **Disable confirmed accounts**. Then publish and deploy.

- **Set it again after every import.** Importing a workflow clears the step Company setting, because the `.yml` doesn't carry it.
- **Without it,** the steps use the runner's shared secrets, so they sign in to the wrong tenant or fail.

## Required Graph permissions

Application permissions on the app registration, with admin consent in the client tenant:

| Permission | Why |
|---|---|
| `AuditLog.Read.All` with `User.Read.All` | Last sign-in times. The tenant also needs **Entra ID P1** (included in Microsoft 365 Business Premium and E3/E5). |
| `RoleManagement.Read.Directory` | Finding admins, so they are flagged and never disabled |
| `GroupMember.Read.All` | Only when an admin role is held through a role-assignable group |
| `User.EnableDisableAccount.All` (or `User.ReadWrite.All`) | Turning off sign-in, on confirm runs only |
| `User.RevokeSessions.All` (or `User.ReadWrite.All`) | Signing disabled accounts out, on confirm runs only |

If a permission is missing, the run stops with a sentence naming it, for example: "Can't read last sign-in times. The app registration needs the AuditLog.Read.All application permission (with User.Read.All), with admin consent. Nothing was changed."

## Inputs

All inputs are optional. A monthly Routine sends none, so it runs a review with the defaults.

| Input | Default | Meaning |
|---|---|---|
| `days` | `90` | How many days without a sign-in counts as inactive (30 to 3650) |
| `include_guests` | `true` | Also review guest accounts |
| `confirm` | `false` | `false`: review only, nothing changes. `true`: disable the accounts in `disable_ids` |
| `disable_ids` | empty | Comma-separated sign-in names or user object ids to disable. Only used when `confirm` is true. |
| `company_id` | `CloudRadial-CompanyId` secret | CloudRadial company number for the report |
| `tenant_id` | empty | Optional safety check: when given, it must be this runner's Microsoft 365 tenant or the run is rejected |
| `psa` | `PSA-Type` secret | Which PSA the ticket is in (`connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro`, `zendesk`) |
| `ticket_id` | empty | A ticket to add an internal note to |

## Output

`status` (`pending_confirmation` when a review found accounts that could be disabled, `success`, `rejected`, `incomplete` or `error`), `message`, `public_note` (client-safe), `internal_note`, `ticket_id`, `actions`, `warnings`, plus `candidates` (each listed account with its sign-in name, kind, last sign-in, days inactive, flag and whether it can be disabled), `counts`, `disabled`, `skipped` (with reasons), `report` (where it was written) and `report_html` when it couldn't be archived.

## Import & test

1. AutomationAI > **Workflows > Import** `stale-guest-cleanup.yml`. **Publish** and **deploy** it to the runner that holds the client's secrets.
2. Run it by hand with the first step's Test Input (`confirm` false). Check that the Account Reviews archive has the report and that admins are flagged. Nothing changes on a review run.
3. To disable accounts, run again with `confirm` true and `disable_ids` set to the sign-in names you approved from the report, for example `{"confirm": true, "disable_ids": "old.user@contoso.com, vendor_example.org#EXT#@contoso.com"}`. Try it first on a disposable test account.
4. **Attach a Routine:** Routines > New, pick this workflow and a monthly schedule (for example `0 8 1 * *`, 08:00 on the 1st). A Routine runs the deployed version, so redeploy after every edit. Set the `CloudRadial-CompanyId` secret, because a Routine sends no input.

To change the steps, edit `src/*.ps1`, then run `node src/build.js` (it pastes in the shared libraries) and `pwsh -NoProfile -File src/test.ps1`. Never edit the `.yml` by hand.
