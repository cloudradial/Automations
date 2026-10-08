# Nudge Clients Who Haven't Replied, Then Close the Ticket

Tickets waiting on the client get a polite reminder on day 2 and day 4, then close with a notice on day 7, so stalled tickets stop piling up and nobody has to chase them by hand.

**Formerly:** Waiting-on-Client Nudge (tracker 9.3) | **Marketplace ID:** TBD | **Type:** Workflow (PowerShell, no AI, runs on a schedule)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `waiting-on-client-nudge.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/waiting-on-client-nudge/waiting-on-client-nudge.yml) |
| Download `waiting-on-client-nudge.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/waiting-on-client-nudge/waiting-on-client-nudge.yml) |
| All files in this automation | [automationai/waiting-on-client-nudge](https://github.com/cloudradial/Automations/tree/main/automationai/waiting-on-client-nudge) |
| Build source (`src/`) | [automationai/waiting-on-client-nudge/src](https://github.com/cloudradial/Automations/tree/main/automationai/waiting-on-client-nudge/src) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/waiting-on-client-nudge) |
| Works with | [Auto-Close Resolved](https://github.com/cloudradial/Automations/tree/main/automationai/auto-close-resolved) (same marker pattern) |
| Shared PSA code | [`_shared/psa.ps1` and `_shared/psa-tickets.ps1`](https://github.com/cloudradial/Automations/tree/main/automationai/_shared) |

## How it works

A Routine runs the workflow once a day. It works in ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk, using the PSA named by the `PSA-Type` secret.

`Start → Find tickets in Waiting → Send reminders → Close with notice → Internal note per action → End`

1. **Find tickets in Waiting** lists the tickets in the waiting status (`Waiting Customer` in ConnectWise by default) and reads each ticket's notes. It changes nothing. For each ticket it works out how long it has been waiting and what is due:
   - **A reminder** on each reminder day (2 and 4 by default). A missed day isn't made up: if the run was off and the ticket is now on day 5, it gets one reminder, not two.
   - **The closing notice and close** on the close day (7 by default).
   - **A hold** for P1 and P2 (critical and high priority) tickets that reach the close day. They are never closed automatically; a technician gets an internal note instead.
   - **Nothing** if the client wrote the newest note on the ticket. The run lists these in its warnings so someone can move the ticket on.
2. **Send reminders** posts each reminder as a **public note**, so the PSA emails the client. The reminder is short and polite, and says the date the ticket will close.
3. **Close with notice** posts the closing notice as a public note, then closes the ticket. If the notice can't be posted, the ticket stays open. If the close fails after the notice went out, the next run retries the close without sending the notice again.
4. **Internal note per action** writes a technician-only note on every ticket that had an action, including failures and holds, and returns the run summary.

**How it counts the days, and why it never sends the same reminder twice.** Every note this workflow writes ends with a marker such as `[waiting-nudge: day 2, waiting since 2026-10-05T16:49Z]`. The wait starts at the latest of the ticket's newest note, its last update and (in Kaseya BMS) its last status change. After the first reminder, later runs read the start date from the marker, so the workflow's own notes don't restart the clock. A reminder for a day that already has a marker isn't sent again. A new note from a technician or the client starts a new wait. Don't edit or delete the markers.

**Safe to run again.** Because every run reads the markers first, rerunning the workflow (an Action Runs **Retry**, or the next Routine) never sends a reminder or closing notice twice and never closes a ticket twice. The public reminder and the closing notice also go through `Add-PsaNote -Marker`, which checks the ticket once more just before writing, so two runs that overlap still send the client one copy.

It only ever touches tickets whose status is exactly the waiting status. Tickets in any other status are left alone, even if the PSA's list filter returns them.

## Download & import

**Download the workflow:** [`waiting-on-client-nudge.yml`](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/waiting-on-client-nudge/waiting-on-client-nudge.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), **Publish**, **Deploy** to the runner that holds the secrets, and attach a daily **Routine** (the schedule isn't part of the export). Full steps are under [Import & test](#import--test).

## Inputs

All inputs are optional. A Routine sends no input, so every one has a default.

| Field | Default | What it does |
|---|---|---|
| `preview` | `false` | `true` lists what would happen and changes nothing. Use it for the first run. |
| `waiting_status_name` | per PSA: ConnectWise and Autotask `Waiting Customer`, HaloPSA `Waiting on User`, Kaseya BMS and Syncro `Waiting on Customer`, Zendesk `pending` | The exact status name your team uses for "waiting on the client". |
| `reminder_days` | `2,4` | Days of waiting on which a reminder goes out. A comma list or a JSON list. |
| `close_day` | `7` | Day on which the closing notice goes out and the ticket closes. Must be after the last reminder day. |
| `close_status_name` | the PSA's usual closed status | The status to close to. Kaseya BMS needs this or the `KaseyaBMS-ClosedStatusId` secret. |
| `company` | all companies | A PSA company name (exact) or PSA company id, to run for one client only. |
| `max_tickets` | `200` | Most tickets checked in one run (1 to 1000). The run warns when there were more. |
| `psa` | the `PSA-Type` secret | Overrides which PSA to use. |

The camelCase names from the tracker (`waitingStatusName`, `reminderDays`, `closeDay`) work too.

**Why `preview` and not `confirm`:** this card's job is to write to client tickets on a schedule with nobody watching, so the default is to act. `preview: true` is the dry-run switch. The first step's Test Input is `{"preview": true}`.

Bad input fails closed: the run stops with a plain sentence and writes nothing.

## Output

`status` (`success`, `incomplete` when any ticket had a problem, or `pending_confirmation` for a preview with work to do), `message` (one plain sentence), `internal_note` (one line per ticket, plus warnings), `public_note` (empty: this run spans many tickets), `ticket_id` (empty), `preview`, `counts` (`found`, `reminded`, `closed`, `held`, `skipped`, `client_replied`, `failed`), `actions` (one per ticket: what happened and any error), `skipped` and `warnings`.

## Required Runner Key Vault secrets

The same names as each PSA's catalog extension, so one set of secrets serves both.

| PSA | Secrets |
|---|---|
| All | `PSA-Type` (`connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk`) |
| ConnectWise PSA | `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` |
| Autotask | `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret`. Optional: `Autotask-NotePublishId`, `Autotask-NotePublicPublishId`, `Autotask-NoteTypeId` |
| HaloPSA | `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret`. Optional: `Halo-NoteOutcomeId`, `Halo-PublicNoteOutcomeId`, `Halo-ClosedStatusId` |
| Kaseya BMS | `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId`, and `KaseyaBMS-ClosedStatusId` (or the `close_status_name` input) |
| Syncro | `Syncro-ApiUrl`, `Syncro-ApiKey` |
| Zendesk | `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` |

The PSA API account needs to read tickets and notes, add public and internal notes, and change ticket status. A missing permission stops the run with a plain sentence naming the HTTP status (for example `HTTP 403`) and the permission to add, before anything is written.

## Required Graph permissions

None. This workflow only talks to the PSA.

## Import & test

1. **Import** `waiting-on-client-nudge.yml` on **Workflows → Import**. Add the secrets above to the runner Key Vault, then **Publish** and **Deploy** to that runner.
2. **Preview.** Run it from **Test** with `{"preview": true}` (the first step's Test Input). Check `message` and `actions`: the right tickets, the right reminder day, and P1/P2 tickets held. If nothing is found, set `waiting_status_name` to your exact status name.
3. **One client live.** Run it with `{"company": "<one test client>"}` and check those tickets in the PSA: the reminder is a public note the client was emailed, and each ticket has an internal note.
4. **Run it again straight away.** Nothing new should be written. That proves a reminder is never sent twice.
5. **Schedule it.** Attach a daily **Routine** with no input (or with your own `reminder_days`, `close_day` and status names).

## Editing it

The four PowerShell steps are generated. Edit the files in `src/`, never the script inside the `.yml`:

| File | What it is |
|---|---|
| `src/1-find.ps1` to `src/4-notes.ps1` | The four steps |
| `src/common.ps1` | Marker, message text and step-to-step helpers |
| `src/build.js` | Assembles the `.yml`: pastes `_shared/psa.ps1` and `_shared/psa-tickets.ps1` (through `_shared/inject.js`), then `common.ps1`, into every step |
| `src/test.ps1`, `src/mock-psa.ps1` | Strict-mode harness against mock versions of all six PSAs |

```
cd automationai/waiting-on-client-nudge/src
npm install
node build.js                         # writes ../waiting-on-client-nudge.yml
pwsh -NoProfile -File test.ps1        # runs the shipped steps against the mock PSAs
```

## Not yet proven live

The list calls and some note fields aren't in the build kit's PSA reference yet. Each has an `Unverified` comment in `_shared/psa-tickets.ps1` (`Find-PsaTickets`) or `_shared/psa.ps1` (`Get-PsaTicketNotes`, `Close-PsaTicket`). Check them on the first preview run in each PSA:

- **Default status names** are common defaults, not read from your PSA. In Autotask, HaloPSA and Kaseya BMS a wrong name stops the run with a list of the statuses that do exist; in the others the run just finds nothing.
- **ConnectWise:** the `dateEntered` condition; a note with a contact and no member counts as the client's.
- **Autotask:** the `TicketNotes` query and `createdByContactID` as the client marker; `lastActivityDate` as the update date.
- **HaloPSA:** the `status_id` list filter, `GET /api/Status`, `GET /api/Actions?ticket_id=`, and `who_type` 2 meaning the end user.
- **Kaseya BMS:** the notes API doesn't say who wrote a note, so a client reply restarts the wait instead of being flagged.
- **Syncro:** a visible comment with no `user_id` counts as the client's.
- **Zendesk:** `organization:<id>` in search (results are re-checked anyway).
