# Catch Missing and Low-Detail Time Before It Costs You a Bill

Every morning, email the service manager a plain list of yesterday's closed tickets that have no time logged, time notes too short to bill from, or time entries with no billable setting.

**Marketplace ID:** TBD | **Type:** Workflow (run daily by a Routine, or by hand)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `time-entry-review.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/time-entry-review/time-entry-review.yml) |
| Download `time-entry-review.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/time-entry-review/time-entry-review.yml) |
| Step source, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/time-entry-review/src) |
| All files in this automation | [time-entry-review](https://github.com/cloudradial/Automations/tree/main/time-entry-review) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/time-entry-review) |

## How it works

The workflow reads your PSA and **never changes a ticket**. It works with ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk. No AI step is used; the rules are fixed.

Steps: **Read inputs > Find closed tickets > Review time entries > Email the service manager.**

1. **Read inputs** picks the day to review: `date`, or yesterday when no date is given. The day runs from midnight to midnight in `timezone` (UTC when no time zone is given).
2. **Find closed tickets** lists every ticket closed on that day, across all companies in the PSA (or one company when `company_id` is given). Where the PSA lists only ids, it looks up the company and technician names once each (a failed lookup shows "Company 5" or "Technician 29").
3. **Review time entries** reads each ticket's time and flags three things:
   - **No time logged:** the ticket was closed with no time entry, or only zero-hour entries.
   - **Short note:** a time entry whose note is shorter than `min_note_chars` characters (20 by default). When a PSA has both a note and an internal note on the entry, the longer one counts.
   - **No billable setting:** a time entry that has no billable choice set, in PSAs that have one.
4. **Email the service manager** sends one plain table (ticket, company, summary, technician, issue, hours, detail) through Postmark to the `to` addresses. If Postmark isn't set up, or there's no recipient, nothing is sent and the table stays in the run output as `report_html` and `report_text`.

Where each PSA keeps its time:

| PSA | Time entries read from | Billable setting |
|---|---|---|
| ConnectWise PSA | `/time/entries` charged to the ticket | `billableOption` (Billable, Do Not Bill, No Charge) |
| Autotask | `TimeEntries` for the ticket | `isNonBillable` |
| HaloPSA | The ticket's actions that have `timetaken` | Charge hours versus non-charge hours on the action |
| Kaseya BMS | Time logs for the ticket | `IsBillable` |
| Syncro | The ticket's timers. When a ticket has no timer, labour line items (a name containing labour, hour or time) count as time. | The timer's `billable` |
| Zendesk | **Zendesk has no native time entries.** If you use the Zendesk Time Tracking app, give its "Total time spent (sec)" field id as `zendesk_time_field_id`, and tickets closed with no tracked time are flagged. Notes and billable settings aren't available. Without that field id the run says the check isn't supported and ends `incomplete`. | Not available |

## Download & import

**Download the workflow:** [`time-entry-review.yml`](https://github.com/cloudradial/Automations/blob/main/time-entry-review/time-entry-review.yml)

Then in AutomationAI: **Workflows > Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), then publish and deploy it to the runner that holds your PSA secrets. **Attach a daily Routine after import** (the schedule isn't part of the export). Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

| Secret | Needed for |
|---|---|
| `PSA-Type` plus that PSA's secrets (`CW-*`, `Autotask-*`, `Halo-*`, `KaseyaBMS-*`, `Syncro-*` or `Zendesk-*`) | Reading tickets and time. Same names as the PSA's catalog extension. |
| `Postmark-ServerToken`, `Postmark-FromEmail` | Sending the email. Same names as the Postmark extension and Deliver Result. `Postmark-FromEmail` must be a verified Postmark sender. |
| `Postmark-ApiUrl` | Optional. Defaults to `https://api.postmarkapp.com`. |
| `ServiceManager-Email` | Optional. Who gets the email when the run has no `to` input, which is how a Routine runs. |

The PSA API account needs **read** access to tickets and time entries. If it can't read them, the run stops with a sentence saying so, for example: "The ConnectWise API account isn't allowed to read time entries (HTTP 403). Give it read access to time entries and run again."

## Required Graph permissions

None. This workflow doesn't use Microsoft Graph.

## Inputs

All inputs are optional. A daily Routine sends none, so it reviews yesterday (UTC) with the defaults.

| Input | Default | Meaning |
|---|---|---|
| `date` | yesterday | The day to review, as `yyyy-MM-dd`. It can't be in the future or more than a year ago. |
| `timezone` | UTC | The time zone the day is counted in, for example `Eastern Standard Time` or `America/New_York` |
| `min_note_chars` | `20` | A time entry note shorter than this is flagged. `0` turns the check off. |
| `check_billable` | `true` | Flag time entries with no billable setting |
| `to` | `ServiceManager-Email` secret | Comma-separated email addresses for the report |
| `company_id` | empty | Review only this PSA company (the PSA's own company id) |
| `zendesk_time_field_id` | empty | Zendesk only: the Time Tracking app's "Total time spent (sec)" ticket field id |
| `max_tickets` | `500` | Stop after this many closed tickets (a warning says so) |
| `psa` | `PSA-Type` secret | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` |

There's no `confirm` input, because this workflow never writes to the PSA.

## Output

`status` (`success`, `incomplete` when Zendesk time can't be checked, `error` when the PSA can't be read), `message`, `public_note` (empty; nothing here is client-facing), `internal_note`, `ticket_id` (empty), `actions`, `warnings`, plus `date`, `timezone`, `counts` (`tickets_closed`, `tickets_checked`, `no_time`, `short_note`, `missing_billable`, `entries_read`, `unreadable`), `findings` (one row per flagged ticket or time entry), `emailed_to`, `report_html` and `report_text`.

## Import & test

1. AutomationAI > **Workflows > Import** `time-entry-review.yml`. **Publish** and **deploy** it to the runner that holds your PSA and Postmark secrets.
2. Run it by hand with a day you know had closed tickets, for example `{"date": "2026-10-07", "to": "you@example-msp.com"}`. Check the email against the PSA: each flagged ticket should really have no time, a short note, or no billable setting. Nothing in the PSA changes.
3. **Attach a Routine:** Routines > New, pick this workflow and a daily schedule (for example `0 7 * * *`, 07:00 UTC). A Routine sends no input, so set the `ServiceManager-Email` secret, and remember the day is counted in UTC unless you run it with a `timezone`. A Routine runs the deployed version, so redeploy after every edit.

To change the steps, edit `src/*.ps1`, then run `node src/build.js` (it pastes in `_shared/psa.ps1`, `_shared/psa-tickets.ps1` and `_shared/postmark.ps1`) and `pwsh -NoProfile -File src/test.ps1`. Never edit the `.yml` by hand.

The ticket list and time entry calls come from `_shared/psa-tickets.ps1`, and the email from `_shared/postmark.ps1`. The PSA calls that haven't been proven by a live run are marked `Unverified` there.
