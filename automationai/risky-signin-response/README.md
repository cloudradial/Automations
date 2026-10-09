# Respond to Risky Microsoft 365 Sign-ins Within the Hour

Every hour, find the users Microsoft flags as high risk, open a priority ticket, sign them out, require a new password and tell their manager. Accounts are blocked only when you confirm it.

**Marketplace ID:** TBD | **Type:** Workflow (run hourly by a Routine, or by hand)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `risky-signin-response.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/risky-signin-response/risky-signin-response.yml) |
| Download `risky-signin-response.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/risky-signin-response/risky-signin-response.yml) |
| Step source, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/automationai/risky-signin-response/src) |
| All files in this automation | [automationai/risky-signin-response](https://github.com/cloudradial/Automations/tree/main/automationai/risky-signin-response) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/risky-signin-response) |

## How it works

The workflow runs against one company: the Microsoft 365 tenant whose app secrets are in the runner Key Vault, and that company's account in your PSA. Run one copy (and one Routine) per client, so one client's users never appear in another client's ticket.

Steps: **Read inputs > Find risky users > Respond to new risky users > Block confirmed accounts > Summarize.** No AI step is used; the rules are fixed.

1. **Find risky users** (read-only) reads the users Microsoft Entra ID Protection has **at risk now** (risk state "at risk") at high risk, or at medium and high with `min_risk` set to medium. Users whose risk was remediated or dismissed are left out. For each one it reads the account, its manager, whether it holds a directory admin role, and its risk detections from the last `lookback_days` days (IP address, location, detection type and times).
2. **Respond to new risky users.** A user is new when the PSA has no open ticket for the company whose summary contains `[Risky sign-in] <sign-in name>` (found with the shared `Find-PsaTickets`, on all six PSAs). For each new user, without asking (this is what the automation is for), it:
   - opens a **high-priority** ticket for the company, or **critical** when the user holds an admin role. The ticket description is generic: it never holds the IP, location or detection types;
   - **signs the user out of every session**;
   - **requires a password change at next sign-in**. This is skipped for accounts synced from on-premises Active Directory (reset those there), and it has no effect when the user's domain is federated to another identity provider (reset it there). Microsoft 365 doesn't let an app change an admin's password settings, so for admins the note says to reset it by hand;
   - adds an **internal note** with the risk detail and what was done. This is the only place the risk detail is written. The note ends with `[risky-signin: <ticket id>]` (the shared `Add-PsaNote -Marker`), so a retried run never adds it twice; the marker holds no name or address;
   - emails the user's **manager** a short notice from the `Notify-FromMailbox` mailbox. It says only that Microsoft flagged unusual sign-in activity and what was done. No manager, or no mailbox secret, means no email and a warning.

   A user who already has an open ticket is left alone, so an hourly Routine never opens a second ticket or signs the user out again while the first ticket is open. When the account is safe, dismiss or remediate the risk in Entra ID Protection **before** closing the ticket: a user who is still at risk when their ticket is closed gets a new ticket on the next run.
3. **Block confirmed accounts.** Nothing is blocked automatically. With `confirm` false (the default) and `block_upns` set, the run previews the block. With `confirm` true, it blocks only the accounts in `block_upns` that Microsoft **still has at risk at that moment**, that are still turned on, and that aren't synced from on-premises. For each it turns off sign-in, signs the account out again, and adds an internal note to its open ticket, marked `[risky-signin-block: <ticket id> <date>]` so a retried confirm run notes the block only once that day. The risk is **never dismissed** automatically; dismiss it in Entra ID Protection once the account is safe.
4. **Summarize** returns the result in plain sentences.

With `preview` true the run reads everything, including the PSA, and says what it would do, but changes nothing.

**Safe to retry.** A rerun (ServiceAI **Retry** in Action Runs, or the next hourly Routine) finds the open ticket and leaves that user alone, and every ticket note is marker-guarded, so nothing is written twice. Every note is internal: the workflow writes no client-visible note.

**When the PSA can't be searched.** Kaseya BMS has no text search, so its open tickets for the company are listed and matched by the workflow. When a PSA search fails, or stops at its limit without a match, the workflow keeps a log instead: one item per handled user in the company's **Risky Sign-ins** report archive (Compliance > Reports, admins only). The log item holds the sign-in name, ticket number, time and detection ids, never the IP or location. A user logged there is handled again only when Microsoft updates their risk.

## Download & import

**Download the workflow:** [`risky-signin-response.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/risky-signin-response/risky-signin-response.yml)

Then in AutomationAI: **Workflows > Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), then publish and deploy it to the runner that holds that client's secrets. **Attach an hourly Routine after import** (the schedule isn't part of the export). Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

| Secret | Needed for |
|---|---|
| `M365-TenantId`, `M365-ClientId`, `M365-ClientSecret` (the `Entra-*` and `Graph-*` names work too) | Reading risky users and responding in the client's Microsoft 365 tenant |
| `PSA-Type` plus that PSA's secrets (`CW-*`, `Autotask-*`, `Halo-*`, `KaseyaBMS-*`, `Syncro-*` or `Zendesk-*`) | Opening and searching tickets. Same names as the PSA's catalog extension. Kaseya BMS also needs `KaseyaBMS-NoteTypeId` and its ticket id secrets. |
| `PSA-CompanyId` | The client's company id in the PSA. Recommended. Without it the workflow looks the company up by its CloudRadial name and needs exactly one exact match. |
| `CloudRadial-CompanyId` | The CloudRadial company number. Needed for the name lookup and the fallback log. A run's `company_id` input overrides it. |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | The name lookup and the fallback log |
| `Notify-FromMailbox` | The mailbox the manager email is sent from, for example `alerts@yourmsp.com` in the client tenant. Leave it out to send no manager email. |

## Required Graph permissions

Application permissions on the app registration, with admin consent in the client tenant. The tenant needs **Microsoft Entra ID P2** (included in Microsoft 365 E5, or as an add-on).

| Permission | Why |
|---|---|
| `IdentityRiskyUser.Read.All` | Reading which users are at risk, and checking again before a block |
| `IdentityRiskEvent.Read.All` | Reading the risk detections (IP, location, type, times) for the internal note |
| `User.Read.All` | Reading the account and its manager |
| `RoleManagement.Read.Directory` | Finding admins, so their tickets are critical. Without it the run warns and uses high priority. |
| `GroupMember.Read.All` | Only when an admin role is held through a role-assignable group |
| `User.RevokeSessions.All` (or `User.ReadWrite.All`) | Signing the user out |
| `User.ReadWrite.All` | Requiring a password change at next sign-in |
| `Mail.Send` | Emailing the manager from `Notify-FromMailbox`. Limit it to that mailbox with an Exchange application access policy. |
| `User.EnableDisableAccount.All` (or `User.ReadWrite.All`) | Blocking sign-in, on confirm runs only |

If the tenant lacks P2 or a risk permission, the run stops with a sentence naming it, for example: "Can't read risky users. The app registration needs the IdentityRiskyUser.Read.All application permission, with admin consent. Nothing was changed."

## Inputs

All inputs are optional. An hourly Routine sends none, so it responds to new high-risk users with the defaults.

| Input | Default | Meaning |
|---|---|---|
| `min_risk` | `high` | `high`: only high-risk users. `medium`: medium and high |
| `lookback_days` | `7` | How many days of risk detections go into the internal note (1 to 90) |
| `preview` | `false` | `true`: read and say what would happen, change nothing |
| `notify_manager` | `true` | Email each new risky user's manager |
| `confirm` | `false` | `false`: never block. `true`: block the accounts in `block_upns` that are still at risk |
| `block_upns` | empty | Comma-separated sign-in names to block. Only used when `confirm` is true. |
| `company_id` | `CloudRadial-CompanyId` secret | CloudRadial company number |
| `psa` | `PSA-Type` secret | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` |
| `psa_company_id` | `PSA-CompanyId` secret | The company's id in the PSA |
| `tenant_id` | empty | Optional safety check: when given, it must be this runner's Microsoft 365 tenant or the run is rejected |

## Output

`status` (`success`, `pending_confirmation` for a preview with work to do or a block waiting for confirm, `rejected`, `incomplete` or `error`), `message`, `public_note` (client-safe, no risk detail), `internal_note` (with the risk detail), `ticket_id` (the first ticket opened), `tickets`, `actions`, `warnings`, plus `counts`, `responses` (per user: outcome, ticket, priority, sign-out, password change, manager email) and `block` (requested, planned, blocked, skipped with reasons).

## Import & test

1. AutomationAI > **Workflows > Import** `risky-signin-response.yml`. **Publish** and **deploy** it to the runner that holds the client's secrets.
2. Run it by hand with the first step's Test Input (`preview` true). Check the message lists the users Microsoft has at risk and that nothing changed.
3. Run it with `{"preview": false}` against a test user you have marked at risk (for example by signing in from a Tor browser, or by confirming the test user compromised in Entra ID Protection). Check the ticket, its internal note, the sign-out, the password prompt at next sign-in and the manager email. Run it again and check no second ticket opens.
4. To block, run `{"confirm": true, "block_upns": "test.user@contoso.com"}`. Check sign-in is off and the ticket has a note. Turn sign-in back on and dismiss the risk when you're done.
5. **Attach a Routine:** Routines > New, pick this workflow and an hourly schedule (for example `5 * * * *`, five past every hour). A Routine runs the deployed version, so redeploy after every edit. Set `CloudRadial-CompanyId` and `PSA-CompanyId`, because a Routine sends no input.

To change the steps, edit `src/*.ps1`, then run `node src/build.js` (it pastes in the shared libraries) and `pwsh -NoProfile -File src/test.ps1`. Never edit the `.yml` by hand.
