# Close Resolved Tickets Automatically After a Final Notice

Tickets left in Resolved for 3 days get a short final notice to the client and are closed with an internal note, so the board only shows work that is really open.

**Formerly:** Auto-Close Resolved (tracker 10.5) | **Marketplace ID:** TBD | **Type:** Workflow (PowerShell, no AI, runs on a schedule)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `auto-close-resolved.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/auto-close-resolved/auto-close-resolved.yml) |
| Download `auto-close-resolved.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/auto-close-resolved/auto-close-resolved.yml) |
| All files in this automation | [automationai/auto-close-resolved](https://github.com/cloudradial/Automations/tree/main/automationai/auto-close-resolved) |
| Build source (`src/`) | [automationai/auto-close-resolved/src](https://github.com/cloudradial/Automations/tree/main/automationai/auto-close-resolved/src) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/auto-close-resolved) |
| Works with | [Waiting-on-Client Nudge](https://github.com/cloudradial/Automations/tree/main/automationai/waiting-on-client-nudge) (same PSA code) |

## How it works

A Routine runs the workflow once a day. It works in ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk, using the PSA named by the `PSA-Type` secret.

`Start → Find resolved tickets past threshold → Send final notice → Close with internal note → End`

1. **Find resolved tickets past threshold** lists the tickets in the resolved status (`Resolved` by default, `solved` in Zendesk) that nobody has touched for at least `resolved_days`, and reads each ticket's notes. It changes nothing.
   - **Left open:** a ticket whose newest note is from the client (they replied after it was resolved). The run lists these in its warnings.
   - **Left alone:** tickets last touched more than `max_resolved_days` ago (30 by default). Without this, the first run would email clients about tickets resolved months ago. Raise it on purpose if you want to clear an old backlog.
2. **Send final notice** posts a short notice as a **public note**, so the PSA emails the client: the ticket is being closed, and they can reply if the problem isn't fixed. If the notice can't be posted, the ticket stays resolved.
3. **Close with internal note** writes a technician-only note, then closes the ticket, then returns the run summary. The note goes first because Zendesk refuses notes on a closed ticket. If the close fails, a second internal note says so.

**Never twice.** Every note this workflow writes ends with a marker such as `[auto-close-resolved: final notice, resolved since 2026-10-04T16:49Z]`. If a close failed after the notice went out, a later run retries the close without sending the notice again. Because the workflow's own notes count as a touch, that retry happens once the ticket has again gone `resolved_days` untouched. Don't edit or delete the markers.

It only ever touches tickets whose status is exactly the resolved status, and it never "closes" a ticket to the status it is already in.

## Download & import

**Download the workflow:** [`auto-close-resolved.yml`](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/auto-close-resolved/auto-close-resolved.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), **Publish**, **Deploy** to the runner that holds the secrets, and attach a daily **Routine** (the schedule isn't part of the export). Full steps are under [Import & test](#import--test).

## Inputs

All inputs are optional. A Routine sends no input, so every one has a default.

| Field | Default | What it does |
|---|---|---|
| `preview` | `false` | `true` lists what would happen and changes nothing. Use it for the first run. |
| `resolved_status_name` | `Resolved` (Zendesk `solved`) | The exact status name your team uses for "fixed, waiting to close". |
| `resolved_days` | `3` | Days a ticket must sit untouched in that status before it closes. |
| `max_resolved_days` | `30` | Tickets untouched for longer than this are left alone. Must be more than `resolved_days`. |
| `close_status_name` | the PSA's usual closed status | The status to close to: ConnectWise picks the board's closed status that isn't the resolved one, Autotask `Complete`, HaloPSA `Halo-ClosedStatusId` or 9, Kaseya BMS `KaseyaBMS-ClosedStatusId`, Zendesk `closed`. |
| `company` | all companies | A PSA company name (exact) or PSA company id, to run for one client only. |
| `max_tickets` | `200` | Most tickets checked in one run (1 to 1000). The run warns when there were more. |
| `psa` | the `PSA-Type` secret | Overrides which PSA to use. |

**Why `preview` and not `confirm`:** this card's job is to write to client tickets on a schedule with nobody watching, so the default is to act. `preview: true` is the dry-run switch. The first step's Test Input is `{"preview": true}`.

**Syncro and Autotask:** in Syncro, `Resolved` is already the closed status, and in Autotask `Complete` is. If your resolved status is the closed one, the run stops and says so. Set `resolved_status_name` to the status your team uses for "fixed, waiting to close" (for example a custom `Pending Close`).

Bad input fails closed: the run stops with a plain sentence and writes nothing.

## Output

`status` (`success`, `incomplete` when any ticket had a problem, or `pending_confirmation` for a preview with work to do), `message` (one plain sentence), `internal_note` (one line per ticket, plus warnings), `public_note` (empty: this run spans many tickets), `ticket_id` (empty), `preview`, `counts` (`found`, `closed`, `skipped`, `client_replied`, `failed`), `actions` (one per ticket: what happened and any error), `skipped` and `warnings`.

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

The PSA API account needs to read tickets and notes, add public and internal notes, and change ticket status. A missing permission stops the run with the PSA's own message (for example `HTTP 403`), before anything is written.

## Required Graph permissions

None. This workflow only talks to the PSA.

## Import & test

1. **Import** `auto-close-resolved.yml` on **Workflows → Import**. Add the secrets above to the runner Key Vault, then **Publish** and **Deploy** to that runner.
2. **Preview.** Run it from **Test** with `{"preview": true}` (the first step's Test Input). Check `message` and `actions`. If nothing is found, set `resolved_status_name` to your exact status name.
3. **One client live.** Run it with `{"company": "<one test client>"}` and check those tickets in the PSA: a public final notice the client was emailed, an internal note, and the ticket closed (not still resolved).
4. **Run it again straight away.** Nothing new should be written.
5. **Schedule it.** Attach a daily **Routine** with no input (or with your own status names and `resolved_days`).

## Editing it

The three PowerShell steps are generated. Edit the files in `src/`, never the script inside the `.yml`:

| File | What it is |
|---|---|
| `src/1-find.ps1` to `src/3-close.ps1` | The three steps |
| `src/common.ps1` | Marker, notice text and step-to-step helpers |
| `src/psa-extra.ps1` | `Find-PsaTickets`, `Get-PsaTicketNotes`, `Close-PsaTicket` and helpers for all six PSAs. The same file ships in `waiting-on-client-nudge/src`; keep them identical. A candidate to move into `_shared`. |
| `src/build.js` | Assembles the `.yml`: pastes `_shared/psa.ps1` (through `_shared/inject.js`), `psa-extra.ps1` and `common.ps1` into every step |
| `src/test.ps1`, `src/mock-psa.ps1` | Strict-mode harness against mock versions of all six PSAs |

```
cd automationai/auto-close-resolved/src
npm install
node build.js                         # writes ../auto-close-resolved.yml
pwsh -NoProfile -File test.ps1        # runs the shipped steps against the mock PSAs
```

## Not yet proven live

The list calls and some note fields aren't in the build kit's PSA reference yet. Each has an `Unverified` comment in `src/psa-extra.ps1`. Check them on the first preview run in each PSA:

- **Default status names** are common defaults, not read from your PSA. In Autotask, HaloPSA and Kaseya BMS a wrong name stops the run with a list of the statuses that do exist; in the others the run just finds nothing.
- **ConnectWise:** the `lastUpdated` conditions; a note with a contact and no member counts as the client's.
- **Autotask:** `Resolved` isn't an out-of-box status; the `TicketNotes` query and `createdByContactID` as the client marker; `lastActivityDate` as the update date.
- **HaloPSA:** the `status_id` list filter, `GET /api/Status`, `GET /api/Actions?ticket_id=`, and `who_type` 2 meaning the end user. Halo has no date filter here, so dates are checked after listing.
- **Kaseya BMS:** the notes API doesn't say who wrote a note, so a client reply after resolution restarts the clock instead of stopping the close. Most setups reopen a ticket when the client replies, which takes it out of Resolved.
- **Syncro:** a visible comment with no `user_id` counts as the client's.
- **Zendesk:** setting status `closed` through the API, and `organization:<id>` in search.
