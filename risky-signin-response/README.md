# Respond to Risky Microsoft 365 Sign-ins Within the Hour

Every hour, this automation finds the people Microsoft flags as high risk in a client's Microsoft 365, opens a priority ticket, signs them out and makes them choose a new password. Your team stays in charge: no account is blocked unless you say so.

## What happens

**Every hour, in the background.** When Microsoft says a user's sign-ins look risky, your team gets a high-priority ticket in your PSA. If that user is an admin, the ticket is critical.

**The user is secured right away.** They are signed out of every session and asked for a new password the next time they sign in.

**Their manager hears about it.** The manager gets a short email saying Microsoft noticed unusual sign-in activity and what was done. It holds no technical detail.

**Blocking is your call.** If a technician decides an account must be blocked, they run the automation again for that account. It blocks it only if Microsoft still sees it as risky.

## What it protects

- **One ticket per incident.** A user who already has an open ticket is left alone, so the hourly run never opens a second ticket or signs them out again.
- **Risk details stay internal.** The location and sign-in detail go only into an internal ticket note, never into anything your client sees.
- **One client at a time.** You run one copy per client, so one client's users never show up on another client's ticket.
- **Safe to run again.** A repeated run doesn't write the same note twice.
- **You can try it first.** A preview run shows what it would do and changes nothing.

## Works with

ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk.

- **Kaseya BMS:** it has no ticket search, so the automation lists the client's open tickets and checks them itself.
- **If your PSA can't be searched:** the automation keeps a log in the client's admin-only report archive instead, so it still handles each user once.
- **Admins:** Microsoft doesn't let an automation change an admin's password settings, so the ticket note asks your team to reset it by hand.
- **Accounts synced from on-premises Active Directory, or signing in through another identity provider:** reset the password there. The automation can't.

## What you need

- Microsoft Entra ID P2 in the client's Microsoft 365 (included in Microsoft 365 E5, or as an add-on)
- That Microsoft 365 connected in AutomationAI, with the permissions listed in the technical details
- Your PSA and CloudRadial connected in AutomationAI
- Optional: a mailbox in the client's tenant to send the manager emails from

## Set it up

**Once per client, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/risky-signin-response/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. If this client's Microsoft 365 connection is saved under the company in **Companies**, open the workflow and set **Company** to that client on the steps **Find risky users**, **Respond to new risky users** and **Block confirmed accounts**. Do this again after every import.
4. Click **Publish**, then **Deploy** to the runner that holds this client's connections.
5. Go to **Routines > New**, pick this workflow and an hourly schedule.

You can also choose to include medium-risk users, or turn off the manager email.

**Test it.** Run the workflow once by hand in preview, and check that it lists the users Microsoft has at risk and changes nothing.

## Need more detail?

See the [technical details](https://github.com/cloudradial/Automations/tree/main/risky-signin-response#technical-details) for the permissions, settings and how a block is confirmed.

---

## Technical details

**Marketplace ID:** AAI-00046 | **Type:** Workflow (run hourly by a Routine, or by hand) | **Version:** 1.0.0

Every hour, find the users Microsoft flags as high risk, open a priority ticket, sign them out, require a new password and tell their manager. Accounts are blocked only when you confirm it.

## Files

Each version is published as a release, with `risky-signin-response.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/risky-signin-response/v1.0.0).

| What | Link |
|---|---|
| Download `risky-signin-response.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/risky-signin-response/v1.0.0) |
| View the current source | [`risky-signin-response.yml`](https://github.com/cloudradial/Automations/blob/main/risky-signin-response/risky-signin-response.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/risky-signin-response/src) |
| All files in this automation | [risky-signin-response](https://github.com/cloudradial/Automations/tree/main/risky-signin-response) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/risky-signin-response) |

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

**Download the workflow:** [`risky-signin-response.yml`](https://github.com/cloudradial/Automations/releases/tag/risky-signin-response/v1.0.0)

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

### Microsoft 365 secrets stored per company

Sometimes a client's Microsoft 365 secrets (`M365-TenantID`, `M365-ClientID` and `M365-ClientSecret`) are saved under the company in AutomationAI (**Companies**, policy *Require company*) instead of in the runner vault. In that case, open the workflow in the designer and set **Company** to that client on these steps: **Find risky users**, **Respond to new risky users** and **Block confirmed accounts**. Then publish and deploy.

- **Set it again after every import.** Importing a workflow clears the step Company setting, because the `.yml` doesn't carry it.
- **Without it,** the steps use the runner's shared secrets, so they sign in to the wrong tenant or fail.

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

`status` (`success`, `pending_confirmation` for a preview with work to do or a block waiting for confirm, `rejected`, `incomplete` or `error`), `message`, `public_note` (client-safe, no risk detail), `internal_note` (with the risk detail), `ticket_id` (the first ticket opened), `tickets`, `actions`, `warnings`, plus `counts`, `responses` (per user: outcome, ticket, priority, sign-out, password change, manager email) and `block` (requested, planned, blocked, skipped with reasons). `warnings` also carries what the shared PSA code reported, such as ConnectWise refusing to list ticket priorities. When that happens, `priority_fallback` is true on the user's response and the message and notes say which priority was requested instead of claiming it was set.

## Import & test

1. AutomationAI > **Workflows > Import** `risky-signin-response.yml`. **Publish** and **deploy** it to the runner that holds the client's secrets.
2. Run it by hand with the first step's Test Input (`preview` true). Check the message lists the users Microsoft has at risk and that nothing changed.
3. Run it with `{"preview": false}` against a test user you have marked at risk (for example by signing in from a Tor browser, or by confirming the test user compromised in Entra ID Protection). Check the ticket, its internal note, the sign-out, the password prompt at next sign-in and the manager email. Run it again and check no second ticket opens.
4. To block, run `{"confirm": true, "block_upns": "test.user@contoso.com"}`. Check sign-in is off and the ticket has a note. Turn sign-in back on and dismiss the risk when you're done.
5. **Attach a Routine:** Routines > New, pick this workflow and an hourly schedule (for example `5 * * * *`, five past every hour). A Routine runs the deployed version, so redeploy after every edit. Set `CloudRadial-CompanyId` and `PSA-CompanyId`, because a Routine sends no input.

To change the steps, edit `src/*.ps1`, then run `node src/build.js` (it pastes in the shared libraries) and `pwsh -NoProfile -File src/test.ps1`. Never edit the `.yml` by hand.
