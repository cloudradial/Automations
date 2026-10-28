# See Every SLA Breach Before Your Clients Do

Once a week, your service manager gets one email listing every open ticket that has missed its SLA or is about to. Your team can catch up on late work before a client has to chase it.

## What happens

**Every week, one email.** It lists the late and nearly late tickets, grouped by client and then by technician, with the late ones first.

**Each row is easy to read.** It shows the ticket, its summary, priority and status, when it was due, and where it stands, for example "Breached, 1h 10m over" or "Near breach: 85% of the time used, 2h left".

**Quiet weeks still get an email.** If nothing is late, a short all-clear arrives instead.

Your clients don't see anything. The email goes only to your own service manager.

## What it protects

- **It never changes a ticket.** It only reads your PSA and sends a report.
- **It uses your own SLA rules where your PSA has them.** Otherwise it uses sensible default times by priority (4 hours for critical, 8 for high, 24 for medium, 72 for low).
- **Paused tickets are left out.** Tickets waiting on the client, pending, on hold or scheduled usually have their clock stopped, so they don't clutter the list.
- **Nothing reaches your clients.** No portal, ticket or client email is touched.

## Works with

ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk.

- **ConnectWise PSA:** due times are approximate, because ConnectWise counts business hours and this report doesn't.
- **Zendesk:** your Zendesk plan needs SLA policies to use Zendesk's own SLA times.

## What you need

- AutomationAI, with your PSA connected (read access to tickets is enough)
- Postmark set up in AutomationAI to send the email, with a verified sender address
- Your service manager's email address

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/sla-breach-report/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.
4. Save your service manager's email address in the runner's settings, so the weekly run knows who to send to.
5. Add a **Routine** that runs the workflow weekly, for example Mondays at 7am. Add it again after every import, because the schedule isn't part of the file.

**Optional settings.** You can report on one client only, change how close to the deadline counts as "near breach" (80% by default), change the default hours per priority, or ignore your PSA's SLA times and use the default hours for everything.

**Test it.** Run the workflow by hand with your own email address and one test client, then check a few tickets against your PSA's own SLA view.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/sla-breach-report#technical-details) cover how each PSA's SLA times are read, every setting, and the full import and test steps.

---

## Technical details

**Marketplace ID:** AAI-00049 | **Type:** Workflow (PowerShell steps, no AI), run weekly by a Routine | **Version:** 1.0.0

Every week the service manager gets one email listing the open tickets that have breached their SLA or are about to, grouped by company and technician, read straight from the PSA and without changing a single ticket.

## Files

Each version is published as a release, with `sla-breach-report.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/sla-breach-report/v1.0.0).

| What | Link |
|---|---|
| Download `sla-breach-report.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/sla-breach-report/v1.0.0) |
| View the current source | [`sla-breach-report.yml`](https://github.com/cloudradial/Automations/blob/main/sla-breach-report/sla-breach-report.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/sla-breach-report/src) |
| All files in this automation | [sla-breach-report](https://github.com/cloudradial/Automations/tree/main/sla-breach-report) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/sla-breach-report) |

## How it works

Two steps, no AI. It works with ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk.

1. **List breached and near-breach tickets.** Reads every open ticket (up to `max_tickets`) and works out each one's SLA target:
   - **The PSA's own SLA, where it has one.** Before the first response the target is the respond-by time, and after it the resolve-by time.

     | PSA | Fields used |
     |---|---|
     | ConnectWise PSA | The ticket's SLA (`/service/SLAs/{id}` and its priority overrides: respond and resolution hours), counted from when the ticket was entered, plus `isInSla`. CW applies business hours and this count doesn't, so treat CW targets as approximate. |
     | Autotask | `firstResponseDueDateTime` until `firstResponseDateTime` is set, then `resolvedDueDateTime`, then `dueDateTime`. `serviceLevelAgreementHasBeenMet = false` counts as breached. |
     | HaloPSA | `respondbydate` until `responsedate` is set, then `fixbydate`. Halo's `1900-01-01` "no date" is ignored. |
     | Kaseya BMS | The ticket's due date. |
     | Syncro | `due_date`. |
     | Zendesk | SLA policy metrics (`include=slas`): the earliest active `breach_at`. A paused or met SLA isn't reported. Needs a Zendesk plan with SLA policies. |
   - **Otherwise the default hours** in `sla_hours_by_priority` (critical 4, high 8, medium 24, low 72), counted from when the ticket was created. A ticket with no priority counts as medium.
   - A ticket is **breached** when its target has passed (or the PSA says the SLA was missed), and **near breach** when it has used `near_breach_percent` (80%) or more of the time. Tickets whose status contains one of `skip_statuses` (waiting, pending, on hold, scheduled) are left out, because their clock is usually stopped.
2. **Email the service manager.** Builds a plain-language HTML table grouped by company, then by technician, with breached tickets first. Each row shows the ticket, summary, priority, status, target time, where it stands ("Breached, 1h 10m over" or "Near breach: 85% of the time used, 2h left") and whether it was measured by the PSA's SLA or the default hours. It sends one email through Postmark to `to`. A week with nothing to report still sends a short all-clear.

**Report only.** The workflow never writes to a ticket; the test harness checks that it makes no PSA write at all. Without a `to` address or the Postmark secrets, nothing is sent and the full HTML report is in the run output (`html`), with a warning saying why. A rerun (ServiceAI Retry or the Routine running again) sends the report email again and still writes nothing to a ticket.

**Scope.** By default the email covers every client in the PSA, the same as the PSA's own SLA reports, and goes only to your own service manager. Set `company` to report on one client only. Nothing is written into any client's portal or ticket.

## Download & import

**Download the workflow:** [`sla-breach-report.yml`](https://github.com/cloudradial/Automations/releases/tag/sla-breach-report/v1.0.0)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required secrets](#required-runner-key-vault-secrets) to the runner, **Publish**, **Deploy**, and attach a weekly **Routine**. Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

By name only. Use the same names as the catalog extensions, so one set serves both.

| Secret | For |
|---|---|
| `PSA-Type` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` (a `psa` input overrides it). |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | Read tickets and SLA definitions |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | Read tickets, companies and resources |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Read tickets |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName` | Read tickets |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | Read tickets |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | Read tickets, SLA metrics, organizations, users and groups |
| `Postmark-ServerToken`, `Postmark-FromEmail` | Send the email (the same secrets as the Postmark extension and [Deliver Result](../deliver-result/)). `Postmark-FromEmail` must be a verified Postmark sender. |
| `Postmark-ApiUrl` (optional) | Defaults to `https://api.postmarkapp.com`. |
| `ServiceManager-Email` (optional) | Who gets the report when the run has no `to` input. A Routine sends no input, so set this for the weekly schedule. |

**PSA permissions:** the API user only needs to **read** service tickets (and, for ConnectWise, service SLAs). If it can't list tickets, the run stops with a plain sentence such as "ConnectWise refused to list tickets (HTTP 403). Give the API user permission to read service tickets and their notes, then run this again."

## Required Graph permissions

None. This workflow doesn't call Microsoft Graph.

## Inputs

A Routine sends no input, so every field has a default.

| Field | Default | Meaning |
|---|---|---|
| `to` | the `ServiceManager-Email` secret | The service manager's email address. Several are allowed, separated by commas. Without it (and without the secret), the report is only in the run output. |
| `near_breach_percent` | `80` | Flag a ticket as near breach once it has used this much of its SLA time (1 to 100). |
| `sla_hours_by_priority` | `{"critical":4,"high":8,"medium":24,"low":72}` | Default hours to resolve, by priority, for tickets the PSA has no SLA dates for. Give any subset; the rest keep their defaults. `urgent`, `normal`, `P1` and similar names are accepted. |
| `use_psa_sla` | `true` | `false` ignores the PSA's SLA dates and uses the default hours for every ticket. |
| `skip_statuses` | `waiting,pending,on hold,scheduled` | Leave out tickets whose status contains any of these words. |
| `company` | (all companies) | Only this client: a PSA company id, or the exact company name (it must match one company). Every other client's tickets are left out, even if the PSA ignores the filter. Also accepted as `company_id` or `companyId`. |
| `max_tickets` | `500` | The most open tickets to read (1 to 5000). The run warns when it stops at the limit. |
| `from` | `Postmark-FromEmail` | A different verified sender. |
| `message_stream` | `outbound` | The Postmark message stream. |
| `psa` | `PSA-Type` | Overrides the PSA. |

There's no `confirm` input because the workflow never changes anything.

## Output

`status` (`success`, `incomplete` when the email couldn't be sent, `rejected` for invalid input, `error` when the PSA can't be read), `message`, `public_note` (empty: nothing goes to a client), `internal_note`, `ticket_id` (empty), `email_sent`, `recipients`, `subject`, `counts` (`open`, `skipped`, `breached`, `nearBreach`, `psaSla`, `defaultHours`, `slaPausedOrMet`), `tickets` (one row per flagged ticket: company, technician, state, target, percent used, SLA source), `html` (the full report), `actions` and `warnings`.

## Import & test

1. Import `sla-breach-report.yml`, add the secrets above to the runner, then **Publish** and **Deploy** to that runner.
2. **First run.** In **Run**, use the first step's Test Input with `to` set to your own address and `company` set to one test client. Expect `status: success` and one email. Check a few rows against the PSA: the same tickets should show as late in its own SLA view.
3. **Check the fallback.** Run again with `use_psa_sla: false` and a small `sla_hours_by_priority` such as `{"medium":1}`. More tickets should appear, all measured by "Default hours".
4. **Schedule it.** Add the `ServiceManager-Email` secret to the runner (a Routine sends no input, so this is where the address comes from), then add a **Routine** that runs the deployed version weekly, for example Monday 07:00. Every other setting uses its default.

> Routines aren't part of an export, so attach the Routine after every import. The step logic lives in `src/`: edit `find.ps1` or `send.ps1`, run `node src/build.js` (it pastes `_shared/psa.ps1`, `_shared/psa-tickets.ps1` and `_shared/postmark.ps1` into the steps), then `pwsh -NoProfile -File src/test.ps1` (strict mode, mocked PSAs and Postmark). Never edit the `.yml` by hand. The ticket list, SLA and name lookups come from [`_shared/psa-tickets.ps1`](../_shared/), and the email from `_shared/postmark.ps1`.
