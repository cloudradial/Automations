# Escalate Forgotten Tickets Before They Breach

Every 15 minutes, tickets nobody has touched for too long, or whose SLA is about to run out, move up one tier, the dispatcher gets an email, and each ticket gets an internal note saying why. A ticket is escalated once and never bounced around.

**Marketplace ID:** TBD | **Type:** Workflow (PowerShell steps, no AI), run every 15 minutes by a Routine

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `auto-escalation.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/auto-escalation/auto-escalation.yml) |
| Download `auto-escalation.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/auto-escalation/auto-escalation.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/automationai/auto-escalation/src) |
| All files in this automation | [automationai/auto-escalation](https://github.com/cloudradial/Automations/tree/main/automationai/auto-escalation) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/auto-escalation) |

## How it works

Four steps, no AI. It works with ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk.

1. **Find at-risk tickets.** Reads every open ticket (up to `max_scan`) and picks the ones that are:
   - **Untouched:** no update for longer than `minutes_untouched_by_priority` allows (critical 15, high 60, medium 240, low 480 minutes; a ticket with no priority counts as medium). "Last update" is the PSA's own last-activity time (ConnectWise `lastUpdated`, Autotask `lastActivityDate`, HaloPSA `lastactiondate`, Syncro and Zendesk `updated_at`).
   - **At SLA risk:** the PSA's own SLA target (the same fields as [SLA Breach Report](../sla-breach-report/)) has passed, or `sla_risk_percent` (80%) of the time is used. Set `check_sla: false` to use the untouched time only.

   Tickets whose status contains a word in `skip_statuses` (waiting, pending, on hold, scheduled) are left alone. The most overdue come first. Before planning, it reads each ticket's notes: **a ticket that already has an `[Auto-Escalation]` note is skipped**, and if the notes can't be read the ticket is skipped too, with a warning, because the workflow can't tell whether it was already escalated. It stops at `max_tickets` (10) per run; the rest wait for the next run.

   Then it plans one escalation per ticket:
   - **Move up one tier** when `escalation_map` has an entry for the ticket's queue (ConnectWise board, Autotask or Kaseya BMS queue, HaloPSA team, Syncro issue type, Zendesk group), matched by name or id, or a `"*"` catch-all entry.
   - **Note and notify only** when there's no entry for its queue, when it is already where the map sends it, or when **someone is actively working it**: a ticket that is only at SLA risk, updated recently and assigned to a technician stays with that technician. The workflow never reassigns away from a technician who is working the ticket.
2. **Reassign up a tier.** Moves each planned ticket to the mapped queue and/or assigns the mapped user. One tier per run, and only once per ticket. For Autotask, a user is assigned with the role in the map entry, or else the resource's default Service Desk role. A refused change (for example HTTP 403) is recorded in plain language, and the run carries on with the other tickets.
3. **Notify the dispatcher.** One email per run through Postmark to `dispatcher_email`, listing each ticket, the company, why it was escalated and what was done. Without a dispatcher address or the Postmark secrets, the internal note on each ticket is the notification.
4. **Internal note with the reason.** Adds a technician-only note to each escalated ticket, for example: "[Auto-Escalation] This ticket was escalated automatically. It has had no update for 2 hours, past the 60-minute limit for high priority tickets. It was moved from Service Desk to Tier 2. The dispatcher was emailed." The `[Auto-Escalation]` tag at the start is what stops the ticket being escalated again. Nothing is posted where the client can see it.

### Preview

There's no approval step in AutomationAI, and a Routine every 15 minutes has nobody to approve, so this workflow runs live by default. **Set `preview: true` to see the plan without changing anything:** it reads tickets and notes, and returns `status: pending_confirmation` with what it would move, note and email. It writes nothing and sends nothing. Use it for the first run in any tenant, and whenever you change the map.

## Download & import

**Download the workflow:** [`auto-escalation.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/auto-escalation/auto-escalation.yml)

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

**PSA permissions:** the API user reads service tickets and their notes, updates the ticket's board, queue, team or group and its assignee, and adds internal notes. A missing permission shows up as a plain sentence, for example "ConnectWise refused the change (HTTP 403). Give the API user permission to update service tickets."

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

`status` (`success`, `pending_confirmation` for a preview, `incomplete` when a move or a note failed, `rejected` for invalid input, `error` when the PSA can't be read), `message`, `public_note` (always empty), `internal_note` (one line per ticket), `ticket_id` (when exactly one ticket was escalated), `preview`, `dispatcher_emailed`, `counts` (`open`, `skipped`, `atRisk`, `alreadyEscalated`, `notesUnreadable`, `selected`, `toReassign`, `noteOnly`, `overLimit`), `escalations` (per ticket: reason, action, target queue and assignee, result, outcome, error, noted), `actions` and `warnings`.

## Import & test

1. Import `auto-escalation.yml`, add the secrets above to the runner, then **Publish** and **Deploy** to that runner.
2. **Preview first.** In **Run**, use the first step's Test Input (it has `preview: true`) with your own queue names in `escalation_map` and `company` set to one test client. Expect `status: pending_confirmation` (or `success` with "No open tickets need escalating") and a list of what would happen. Nothing changes.
3. **One live ticket.** Make a test ticket for the test client in a mapped queue, wait past its untouched limit (or set `minutes_untouched_by_priority` to `{"low":1,"medium":1}`), then run with `preview: false` and `company` set to that client, so no other client's ticket can be touched. Expect the ticket moved one tier, one dispatcher email and one internal `[Auto-Escalation]` note.
4. **Run it again.** The same ticket must not move again: expect `alreadyEscalated: 1`.
5. **Schedule it.** Add the `AutoEscalation-Map` and `Dispatcher-Email` secrets, then a **Routine** that runs the deployed version every 15 minutes.

> Routines aren't part of an export, so attach the Routine after every import. The step logic lives in `src/`: edit `find.ps1`, `reassign.ps1`, `notify.ps1`, `note.ps1` or `psa-extra.ps1`, run `node src/build.js`, then `pwsh -NoProfile -File src/test.ps1` (strict mode, mocked PSAs and Postmark). Never edit the `.yml` by hand. `src/psa-extra.ps1` is the same file as in [SLA Breach Report](../sla-breach-report/) and is a candidate to move into [`_shared`](../_shared/).
