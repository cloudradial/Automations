# Escalate Forgotten Tickets Before They Breach

Every 15 minutes, tickets nobody has touched for too long, or whose SLA is about to run out, get an internal note saying why, move up one tier, and the dispatcher gets an email. A ticket is escalated once and never bounced around, even when a run is retried. Users can also [escalate their own ticket](#let-users-escalate-their-own-ticket) from a portal form.

**Marketplace ID:** AAI-00062 | **Type:** Workflow (PowerShell steps, no AI), run every 15 minutes by a Routine | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/auto-escalation/v1.0.0).

| What | Link |
|---|---|
| View `auto-escalation.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/auto-escalation/auto-escalation.yml) |
| Download `auto-escalation.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/auto-escalation/v1.0.0) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/auto-escalation/src) |
| Shared PSA and Postmark code | [`_shared/psa.ps1`, `psa-tickets.ps1` and `postmark.ps1`](https://github.com/cloudradial/Automations/tree/main/_shared) |
| All files in this automation | [auto-escalation](https://github.com/cloudradial/Automations/tree/main/auto-escalation) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/auto-escalation) |

## How it works

Four steps, no AI. It works with ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk.

1. **Find at-risk tickets.** Reads every open ticket (up to `max_scan`) and picks the ones that are:
   - **Untouched:** no update for longer than `minutes_untouched_by_priority` allows (critical 15, high 60, medium 240, low 480 minutes; a ticket with no priority counts as medium). "Last update" is the PSA's own last-activity time (ConnectWise `lastUpdated`, Autotask `lastActivityDate`, HaloPSA `lastactiondate`, Syncro and Zendesk `updated_at`).
   - **At SLA risk:** the PSA's own SLA target (the same fields as [SLA Breach Report](../sla-breach-report/)) has passed, or `sla_risk_percent` (80%) of the time is used. Set `check_sla: false` to use the untouched time only.

   Tickets whose status contains a word in `skip_statuses` (waiting, pending, on hold, scheduled) are left alone. The most overdue come first. Before planning, it reads each ticket's notes: **a ticket that already has an `[Auto-Escalation]` note is skipped**, and if the notes can't be read the ticket is skipped too, with a warning, because the workflow can't tell whether it was already escalated. It stops at `max_tickets` (10) per run; the rest wait for the next run.

   Then it plans one escalation per ticket:
   - **Move up one tier** when `escalation_map` has an entry for the ticket's queue (ConnectWise board, Autotask or Kaseya BMS queue, HaloPSA team, Syncro issue type, Zendesk group), matched by name or id, or a `"*"` catch-all entry.
   - **Note and notify only** when there's no entry for its queue, when it is already where the map sends it, or when **someone is actively working it**: a ticket that is only at SLA risk, updated recently and assigned to a technician stays with that technician. The workflow never reassigns away from a technician who is working the ticket.
2. **Mark and reassign up a tier.** For each planned ticket it first adds a technician-only note, for example: "[Auto-Escalation] This ticket was escalated automatically. It has had no update for 2 hours, past the 60-minute limit for high priority tickets. Auto-Escalation is going to move it from Service Desk to Tier 2. The dispatcher is being emailed a list of the escalated tickets." Only then does it move the ticket to the mapped queue and/or assign the mapped user. One tier per run, and only once per ticket. For Autotask, a user is assigned with the role in the map entry, or else the resource's default Service Desk role. A refused change (for example HTTP 403) is recorded in plain language, and the run carries on with the other tickets. Nothing is posted where the client can see it.
3. **Notify the dispatcher.** One email per run through Postmark to `dispatcher_email`, listing each ticket this run escalated, the company, why it was escalated and what was done. Without a dispatcher address or the Postmark secrets, the internal note on each ticket is the notification.
4. **Follow-up note and summary.** Adds a second internal note (`[Auto-Escalation: follow-up]`) only where something went wrong after the first note: the move failed, or the dispatcher email couldn't be sent. Then it returns the run summary.

### Safe to retry

The `[Auto-Escalation]` note is the record that a ticket was escalated, so it is written **before** the move, through `Add-PsaNote -Marker`, which checks the ticket for the note again just before writing.

- **A rerun** (an Action Runs **Retry**, or the next Routine) skips every ticket that already has the note in step 1, so it never moves a ticket a second time (for example on from Tier 2 to Tier 3) and never emails the dispatcher about it again.
- **Two runs that overlap** both plan the same ticket, but the second finds the note at the moment it writes, leaves the ticket alone and leaves it out of its email.
- **If the note can't be written,** the ticket isn't moved (and the run is `incomplete`), because without the note a retry couldn't tell the move had happened.
- **If a run stops between steps,** a retry doesn't repeat the move; tickets that were already marked are not emailed again either. The note on the ticket still says what happened.
- The follow-up note has its own marker, so it is written at most once per ticket.

### Preview

There's no approval step in AutomationAI, and a Routine every 15 minutes has nobody to approve, so this workflow runs live by default. **Set `preview: true` to see the plan without changing anything:** it reads tickets and notes, and returns `status: pending_confirmation` with what it would move, note and email. It writes nothing and sends nothing. Use it for the first run in any tenant, and whenever you change the map.

A preview also checks every board, queue, team or group the map would move a ticket to (`Test-PsaQueue`, read-only). When one doesn't exist, or can't take tickets (for example an inactive ConnectWise board, or a Kaseya BMS queue given by name), that ticket's outcome reads "Would be flagged, can't move it to Help Desk: ConnectWise has no service board named 'Help Desk'..." instead of "Would move it", and the message says how many can't be moved. Fix the map before the live run.

**ConnectWise board moves.** In ConnectWise, statuses and teams belong to a board. A move sets the board, a status that exists on the new board (the same status name if it has one, else its default open status) and a team on it (the same team name, else its default team, else none) in one change, then reads the ticket back to confirm it moved. Without this, ConnectWise refuses the move with "Service Status ... not found for Service Board ...". If the API member can't read board statuses, the move tries the status by name and the run warns you to give the security role Inquire access to service board statuses (System > Table Setup).

## Let users escalate their own ticket

A CloudRadial service-request form lets a user enter their **Ticket #** and a **Reason**, and the ticket is escalated for them. A form request **always** escalates: the untouched-time and SLA rules are only for the scheduled sweep. The same workflow does both; a `ticket_number` in the request switches it to single-ticket mode, and without one it runs the sweep exactly as before.

**What happens to the ticket:**

1. **Ownership check.** The ticket's company must be the requester's company (`company_psa_id`), and the requester (`requester_email`) must be the ticket's contact. Set `allow_company_colleagues: true` to let anyone at the same company escalate it. A request without a requester or company is refused (`status: rejected`, nothing changed) unless `technician_run: true`. A ticket the requester can't escalate gets the same message whether or not it exists, so nothing about another company's ticket is ever shown.
2. **Closed or already escalated.** A closed ticket isn't escalated ("Ticket 1234 is closed, so it wasn't escalated."). A ticket that already has the `[Auto-Escalation]` note isn't escalated again ("Ticket 1234 has already been escalated..."), so submitting the form twice does nothing more.
3. **Escalation.** Through the same escalation map as the sweep (`escalation_map` input or the `AutoEscalation-Map` secret): the internal `[Auto-Escalation]` note goes on first, with the requester and their reason; then the ticket moves up one tier; then the dispatcher gets the Postmark email with the requester and the reason. If its queue has no map entry, or the mapped board or queue can't be used, the ticket is flagged and noted instead of moved, the dispatcher is still emailed, and the message says so.
4. **The requester is told.** A short **public** note on the ticket: "Thanks for letting us know. This ticket has been escalated, and a member of our team will be in touch." It makes no promise about times. It is written once, even when the run is retried.

`preview: true` still changes nothing and returns what would happen.

**Form wiring (CloudRadial):**

1. Create a service-request form with two questions:
   - **Ticket #** (short text), **Field ID** `ticketNumber`.
   - **Reason** of type **Memo**, **Field ID** `reason`.
2. Add an **Automation Webhook** pointing at this workflow's webhook URL, with this body:

   ```json
   {"ticketNumber":"@ticketNumber","reason":"@reason","requester_email":"@UserEmail","company_psa_id":"@CompanyPsaId"}
   ```

   and this header (the secret by name only, never pasted into a ticket or chat):

   ```json
   {"X-Crauto-Webhook-Secret":"<secret>"}
   ```

   Add `"escalation_map"` and `"dispatcher_email"` to the body if the runner doesn't have the `AutoEscalation-Map` and `Dispatcher-Email` secrets.
3. **`@TicketId` is not the ticket to escalate.** It is the NEW request ticket the form itself creates. The ticket to escalate is the one the user types in the Ticket # question (`@ticketNumber`).
4. **Enable the webhook.** The workflow ships with its webhook disabled (the sweep runs on a Routine). Turn it on in the workflow's Start step, then Publish and Deploy.
5. **The escalation map must name boards or queues that exist.** Run a preview first (`preview: true` with a test ticket number and `technician_run: true`): a board that doesn't exist shows as "can't move it to ...".

`requester_email` and `company_psa_id` are only read from the webhook body's own fields, never from a question answer, because a user could type someone else's email into a question. An unfilled `@token` counts as missing, and a form request whose ticket number is missing is refused rather than running the sweep.

## Download & import

**Download the workflow:** [`auto-escalation.yml`](https://github.com/cloudradial/Automations/releases/tag/auto-escalation/v1.0.0)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required secrets](#required-runner-key-vault-secrets) to the runner, **Publish**, **Deploy**, run a preview, then attach a **Routine** every 15 minutes. Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

By name only. Use the same names as the catalog extensions, so one set serves both.

| Secret | For |
|---|---|
| `PSA-Type` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` (a `psa` input overrides it). |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | Optional: `Autotask-NotePublishId`, `Autotask-NoteTypeId` |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Optional: `Halo-NoteOutcomeId` |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId` | |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | |
| `Postmark-ServerToken`, `Postmark-FromEmail` | The dispatcher email (the same secrets as the Postmark extension and [Deliver Result](../deliver-result/)). `Postmark-FromEmail` must be a verified Postmark sender. Optional: `Postmark-ApiUrl`. |
| `Dispatcher-Email` (optional) | Who gets the email when the run has no `dispatcher_email` input. A Routine sends no input, so set this for the schedule. |
| `AutoEscalation-Map` (optional) | The escalation map as JSON, used when the run has no `escalation_map` input. Set this for the schedule, or nothing is ever moved (tickets are only noted). |

**PSA permissions:** the API user reads service tickets and their notes, updates the ticket's board, queue, team or group and its assignee, and adds internal notes. On ConnectWise it also reads service boards, their statuses and their teams (Inquire access under System > Table Setup) so a move lands on a valid status and team. A missing permission shows up as a plain sentence, for example "ConnectWise refused the change (HTTP 403). Give the API user permission to update service tickets."

## Required Graph permissions

None. This workflow doesn't call Microsoft Graph.

## Inputs

A Routine sends no input, so every field has a default.

| Field | Default | Meaning |
|---|---|---|
| `preview` | `false` | `true` returns the plan and changes nothing. |
| `escalation_map` | the `AutoEscalation-Map` secret, else none | Where each queue escalates to. See below. With no map, every at-risk ticket is noted and the dispatcher told, but nothing is moved. |
| `dispatcher_email` | the `Dispatcher-Email` secret | Who gets the email. Several are allowed, separated by commas. |
| `minutes_untouched_by_priority` | `{"critical":15,"high":60,"medium":240,"low":480}` | Minutes without an update before a ticket is escalated. Give any subset. |
| `sla_risk_percent` | `80` | Escalate once this much of the PSA's SLA time is used (1 to 100). |
| `check_sla` | `true` | `false` ignores SLA targets and uses the untouched time only. |
| `company` | (all companies) | Only this client: a PSA company id, or the exact company name (it must match one company). No other client's ticket is read, moved or noted, even if the PSA ignores the filter. Also accepted as `company_id` or `companyId`. |
| `max_tickets` | `10` | The most tickets escalated in one run (1 to 100). |
| `max_scan` | `500` | The most open tickets read in one run. |
| `skip_statuses` | `waiting,pending,on hold,scheduled` | Leave out tickets whose status contains any of these words. |
| `from`, `message_stream` | `Postmark-FromEmail`, `outbound` | Postmark sender and stream. |
| `psa` | `PSA-Type` | Overrides the PSA. |
| `ticket_number` | (none: the sweep runs) | Single-ticket mode: escalate just this ticket, as people see its number (`#1234`, `T20261013.0001`). Also accepted as `ticketNumber`, `ticketId` or `ticket`, or as the answer to a form question with that Field ID. See [Let users escalate their own ticket](#let-users-escalate-their-own-ticket). |
| `reason` | (none) | Single-ticket mode: why the user wants it escalated (the form's Memo question). Goes in the internal note and the dispatcher email. |
| `requester_email` | (none) | Single-ticket mode: who asked (`@UserEmail`). Must be the ticket's contact. |
| `company_psa_id` | (none) | Single-ticket mode: the requester's company in the PSA (`@CompanyPsaId`). Must be the ticket's company. |
| `allow_company_colleagues` | `false` | Single-ticket mode: `true` lets anyone at the ticket's company escalate it, not only its contact. |
| `technician_run` | `false` | Single-ticket mode: `true` skips the ownership check, for a technician running it by hand. Never put it in a portal form's webhook. |

**`escalation_map`** is JSON. The key is the queue a ticket is in now (name or id; `"*"` matches any queue without its own entry). The value is the next tier, as a queue name or id, or an object with `queue`, `assignee` (a user id, or a ConnectWise member identifier) and, for Autotask, an optional `role`:

```json
{
  "Service Desk": "Tier 2",
  "Tier 2": { "queue": "Tier 3", "assignee": "escalations" },
  "Alerts": { "assignee": "29682999", "role": "29683461" }
}
```

A list works too: `[{"from": "Service Desk", "queue": "Tier 2"}]`. The target can be a name or an id, except Kaseya BMS, which needs the numeric queue id. Syncro has no queues, so its "queue" is the issue type.

## Output

`status` (`success`, `pending_confirmation` for a preview, `incomplete` when a move or a marker note failed, `rejected` for invalid input, `error` when the PSA can't be read), `message`, `public_note` (empty for the sweep; in single-ticket mode, the public note the requester was sent), `internal_note` (one line per ticket), `mode` (`sweep` or `form`), `ticket_id` (when exactly one ticket was escalated), `preview`, `dispatcher_emailed`, `counts` (`open`, `skipped`, `atRisk`, `alreadyEscalated`, `notesUnreadable`, `selected`, `toReassign`, `noteOnly`, `overLimit`), `escalations` (per ticket: reason, action, target queue and assignee, result (`reassigned`, `partial`, `failed`, `note-only`, or `already-escalated` when another run got there first), outcome, error, noted), `actions` and `warnings`.

## Import & test

1. Import `auto-escalation.yml`, add the secrets above to the runner, then **Publish** and **Deploy** to that runner.
2. **Preview first.** In **Run**, use the first step's Test Input (it has `preview: true`) with your own queue names in `escalation_map` and `company` set to one test client. Expect `status: pending_confirmation` (or `success` with "No open tickets need escalating") and a list of what would happen. Nothing changes.
3. **One live ticket.** Make a test ticket for the test client in a mapped queue, wait past its untouched limit (or set `minutes_untouched_by_priority` to `{"low":1,"medium":1}`), then run with `preview: false` and `company` set to that client, so no other client's ticket can be touched. Expect one internal `[Auto-Escalation]` note, the ticket moved one tier, and one dispatcher email.
4. **Run it again** (or press **Retry** on the run in Action Runs). The same ticket must not move again, get another note or be emailed again: expect `alreadyEscalated: 1`.
5. **Schedule it.** Add the `AutoEscalation-Map` and `Dispatcher-Email` secrets, then a **Routine** that runs the deployed version every 15 minutes.

> Routines aren't part of an export, so attach the Routine after every import. The step logic lives in `src/`: edit `find.ps1`, `reassign.ps1`, `notify.ps1` or `note.ps1`, run `node src/build.js` (it pastes [`_shared/psa.ps1`, `psa-tickets.ps1` and `postmark.ps1`](../_shared/) through `_shared/inject.js`), then `pwsh -NoProfile -File src/test.ps1` (strict mode, mocked PSAs and Postmark). Never edit the `.yml` by hand.
