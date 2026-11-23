# Stop Tickets Landing on Technicians Who Are Out

When a ticket is assigned to a technician who is out of the office, it moves to a teammate who is in within a few minutes. An internal note says why, and the dispatcher hears about it. Nobody's ticket sits untouched while they are on holiday.

## What your team sees

- **The ticket moves to someone who is in.** By default that's the least busy member of the ticket's team. You can rotate tickets round the team or follow your own "who covers for whom" list instead.
- **One internal note on the ticket,** for example: "Ticket 1001 is assigned to someone who is out. PDoe: In/Out Board: Vacation until Monday 10 PM. The ticket was reassigned from PDoe to BKim, who is in."
- **An email to the dispatcher** (and a Teams post if you want one) for each ticket it handled.
- **The ticket leaves the out technician's calendar,** because their schedule entry moves to the new owner.

## What happens behind the scenes

- Every few minutes it checks who is out right now, using the ConnectWise **In/Out Board** and **Out of Office** schedule entries (PTO, vacation, sick and partial days).
- It looks only at recent tickets owned by those people, on the boards you choose, and never handles the same ticket twice.
- A ticket is never left without an owner. If nobody on the team is free, it stays where it is and the dispatcher is told.
- Until you switch it to live, every run is a preview: it shows what it would do and changes nothing.
- No AI is involved. It follows fixed rules you can read and change.

## Works with

ConnectWise PSA. It works alongside ServiceAI Triage, which keeps assigning tickets as usual.

## What you need

- AutomationAI with a runner that already has your ConnectWise API details (the ConnectWise Manage extension setup)
- A Postmark account, if you want the dispatcher email

## Set it up

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/tech-out-of-office-check/v1.0.0).
2. In AutomationAI, go to **Workflows > Import** and upload it. Click **Publish**, then **Deploy**.
3. Add your boards, time zone and dispatcher email to the runner. The [technical details](https://github.com/cloudradial/Automations/tree/main/tech-out-of-office-check#settings) list exactly what to add.
4. **Preview.** Open the workflow, click **Run** with `{"confirm": "false"}` and check which tickets it would move and to whom. Nothing changes.
5. **Schedule it.** Under **Routines**, run it every 5 minutes with no input.
6. **Go live** by setting `OOO-LiveMode` to `yes` once the previews look right.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/tech-out-of-office-check#technical-details) cover every setting, how the replacement is picked, the coverage table and what has been tested.

---

## Technical details

**Marketplace ID:** AAI-00091 | **Type:** Workflow (PowerShell steps, no AI), run every few minutes by a Routine | **PSA:** ConnectWise PSA only | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/tech-out-of-office-check/v1.0.0).

| What | Link |
|---|---|
| View `tech-out-of-office-check.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/tech-out-of-office-check/tech-out-of-office-check.yml) |
| Download `tech-out-of-office-check.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/tech-out-of-office-check/v1.0.0) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/tech-out-of-office-check/src) |
| All files in this automation | [tech-out-of-office-check](https://github.com/cloudradial/Automations/tree/main/tech-out-of-office-check) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/tech-out-of-office-check) |

## The problem it fixes

Dispatchers keep track of who is out in ConnectWise: the **In/Out Board** for ad-hoc absences ("out until 2 PM") and **Out of Office schedule entries** for planned PTO and partial days. ServiceAI Triage doesn't read either one when it assigns a ticket. It only skips members who are inactive or on the Agent ID Exclusions list. So a ticket can land on someone who is on PTO for the week.

## How it works

Triage assigns tickets as usual. A Routine runs this workflow every few minutes with no input (a **sweep**). Two steps, no AI:

1. **Find tickets assigned to someone who is out.**
   - **Who is out right now:** every In/Out Board record whose Date Back is still ahead and whose type isn't an "in" type, and every calendar entry covering now (Activities, PTO and other non-ticket schedule types) whose type or name matches an out-of-office name. An Activity's own type is matched too when the API member can read Activities. If nobody is out, the run stops here after two reads.
   - **Their recent tickets:** open tickets owned by those people, entered in the last `OOO-LookbackMinutes` (60), on the `OOO-Boards` boards. Tickets that already carry the `[ooo-check]` note are skipped, so overlapping runs never handle a ticket twice. At most `OOO-MaxTickets` (25) per run; the next run picks up the rest.
2. **Handle each ticket and tell the dispatcher.** Depending on `when_out`:

   | `when_out` | What happens when the **owner** is out |
   |---|---|
   | `reassign` (default) | Picks a replacement and makes them the owner. Candidates are the `OOO-BackupPool` list when it's set, otherwise the members of the ticket's team on its board (every team on the board when the ticket has none). Members who are inactive or out are skipped, and `OOO-PickBy` decides who wins (see below). The out technician's schedule entry on the ticket moves to the replacement, so the ticket leaves their calendar. If nobody qualifies, the ticket stays with the original technician and is flagged. |
   | `flag` | Leaves the assignment alone. The dispatcher decides. |
   | `unassign` | Removes the owner, so the ticket goes back to the dispatch queue. Opt-in only: it undoes ServiceAI's assignment. |

   **How the replacement is picked** (`OOO-PickBy`):

   | `OOO-PickBy` | Who gets the ticket |
   |---|---|
   | `fewest-open` (default) | The candidate with the fewest open tickets. |
   | `least-recent` | The candidate whose newest assigned ticket is oldest, so tickets rotate round the team. (It goes by the newest ticket they own, not a stored rotation.) |
   | `list-order` | The first person in an ordered list who is in. The list comes from the [coverage table](#coverage-table) when `OOO-CoverageArticle` is set, otherwise from `OOO-BackupPool`. |

   <a id="coverage-table"></a>**Coverage table (for `list-order`).** A ConnectWise **Knowledge Base article** that dispatchers maintain in ConnectWise like any other article, so it needs no extra product. Name it in `OOO-CoverageArticle` (its title, or its ID). One row per line, `who: first, second, ...`, or a two-column table:

   ```
   # Who covers for whom. Lines starting with # are notes.
   PDoe: BKim, CDiaz
   RPatel: TNguyen, BKim
   Board Professional Services: CDiaz, RPatel, TNguyen
   Board Contoso Labs: TNguyen, CDiaz
   *: CDiaz, BKim
   ```

   For a ticket whose owner is out, the workflow uses the owner's own row (their Member ID or Member #), else the ticket's board row, else the `*` row, and gives the ticket to the first person in that row who is active and in. The note and email say which row was used. If no row matches, or the article can't be read, it falls back to the ticket's team (`fewest-open`) with a warning. The article is read once per run.

   **Check who is on the board teams first:** shared or admin accounts (an `Admin` or integration login, a dispatcher who never takes tickets) are candidates too, and an empty one looks least busy. Take them off the team, or set `OOO-BackupPool` to the technicians who should get tickets.

   Then it emails the dispatcher (Postmark), posts to Teams if a Power Automate flow is set up, and adds one internal note:

   ```
   Out-of-office check: ticket 1001 is assigned to someone who is out.
   - PDoe: In/Out Board: Vacation until Mon 10/19 10:00 PM Pacific Daylight Time
   The ticket was reassigned from PDoe to BKim, who is in (from the ticket's team, fewest open tickets (1)).
   Dispatcher told by: email to dispatch@examplemsp.example.
   [ooo-check]
   ```

**One ticket on demand.** A run with a `ticketId` (a Test run, or any webhook call) checks just that ticket the same way, whatever its age or board. That's how to test it, and it still works as a ServiceAI Action.

## Going live safely

Until live mode is on, every run is a **preview**: it returns `status: pending_confirmation` with the note it would add, and changes, notes and sends nothing. Turn it on with the `OOO-LiveMode` secret (`yes`). A body that sends `confirm` overrides the secret for that run (`false` always previews, `true` always writes).

## Download & import

1. **Workflows > Import**, upload [`tech-out-of-office-check.yml`](https://github.com/cloudradial/Automations/releases/tag/tech-out-of-office-check/v1.0.0).
2. Check the [settings](#settings). The ConnectWise secrets are the same as the ConnectWise Manage extension's, so they're usually already on the runner.
3. **Publish** and **Deploy** to that runner.
4. Run a preview (see [Test](#test)), then attach the [Routine](#schedule-it).

## Settings

Every setting is a runner Key Vault secret. Only the ConnectWise ones are required, and if the ConnectWise Manage extension is already set up on the runner, those are already there. Everything else has a default that works.

### Required (already there if the ConnectWise Manage extension is set up)

| Secret | Example |
|---|---|
| `CW-ApiUrl` | `https://api-na.myconnectwise.net/v4_6_release/apis/3.0` (use the address ConnectWise redirects to, if it redirects) |
| `CW-CompanyID` | `examplemsp` |
| `CW-PublicKey`, `CW-PrivateKey` | The API member key pair (System > Members > API Members) |
| `CW-ClientId` | The integration client id from developer.connectwise.com |

The API member needs to read and list service tickets and notes, the In/Out Board, schedule entries and members, and add notes. To change the ticket it also needs:

- **Service Desk > Service Tickets: Edit**. Without it the run still notes the ticket and alerts the dispatcher, and returns `incomplete` with a warning.
- **System > Table Setup: Inquire** (service board teams), to find the ticket's team. Without it, set `OOO-BackupPool`.
- **Knowledge Base: Inquire**, only when `OOO-CoverageArticle` is set, to read the coverage table.
- **Edit access to schedule entries** (which security role module lists it isn't confirmed yet), to move the out technician's schedule entry. Without it the owner still changes and a warning names the entry to move by hand.

 Also give it **Sales > Activities: Inquire** if your team books time off as Activities with their own type (for example an "Out of Office" activity type); without it, an Activity is still caught when its summary contains an out-of-office word.

### Set these when you go live

| Secret | What to put | Default if not set |
|---|---|---|
| `OOO-LiveMode` | `yes` once the previews look right | `no` (preview only: nothing is changed, noted or sent) |
| `OOO-Boards` | The boards ServiceAI Triage assigns on, comma separated, for example `Professional Services, Contoso Labs` | Every board (with a warning) |
| `OOO-TimeZone` | Your dispatch time zone: `America/Los_Angeles`, `America/Denver`, `America/Chicago` or `America/New_York` (Windows names like `Pacific Standard Time` work too) | UTC |
| `OOO-DispatchTo` | Who gets the alert, for example `dispatch@yourmsp.com` (several: separate with commas). Needs `Postmark-ServerToken` and `Postmark-FromEmail`. | No email. The internal note is still written. |
| `OOO-TeamsFlowUrl` | A Power Automate "When an HTTP request is received" flow URL that posts to your dispatch channel. It receives `{ title, text, ticketId }`. | No Teams post |

### Only if you want a different behavior

| Secret | What to put | Default if not set |
|---|---|---|
| `OOO-WhenOut` | `reassign`, `flag` or `unassign` | `reassign` |
| `OOO-PickBy` | `fewest-open`, `least-recent` or `list-order` (see [How the replacement is picked](#how-it-works)) | `fewest-open` |
| `OOO-CoverageArticle` | For `list-order`: the title (or ID) of the ConnectWise Knowledge Base article holding the [coverage table](#coverage-table), for example `Out-of-Office Coverage` | none (`OOO-BackupPool` order) |
| `OOO-LookbackMinutes` | How far back a sweep looks for new tickets. Keep it longer than the Routine interval. | `60` |
| `OOO-MaxTickets` | Most tickets one sweep handles | `25` |
| `OOO-BackupPool` | Who can take a ticket, in order: Member IDs (`jsmith`) or Member #s (`303`), separated by commas. Use it when the board teams don't match who covers whom. (`OOO-BackupMember` still works as a one-person list.) | The ticket's team on its board |
| `OOO-ScheduleTypes` | Schedule type names that mean "out", comma separated. Change this only if your Out of Office type has a different name. | `Out of Office, PTO, Vacation, Holiday, Sick, Wellness` |
| `OOO-InTypes` | In/Out Board types that mean "in" | `In Office, In` |
| `PSA-Type` | `connectwise` | ConnectWise when `CW-ApiUrl` is set |

### Example: a typical West Coast setup

```
OOO-LiveMode      yes
OOO-TimeZone      America/Los_Angeles
OOO-DispatchTo    dispatch@yourmsp.com
OOO-Boards        Professional Services, Contoso Labs
```

That's it: within a few minutes of ServiceAI assigning a ticket to someone who is out, it moves to the least-busy teammate who is in, with an internal note, and the dispatcher gets an email.

## Inputs

| Field | Required | Meaning |
|---|---|---|
| `ticketId` | No | Check one ConnectWise ticket. `ticket_id` and `id` also work. Leave it out (as a Routine does) to sweep. |
| `member` | No | The technician Triage assigned: a member identifier (`pdoe`) or a Member # (`303`), which is looked up. Used only while the ticket has no owner saved yet; once it has one, the ticket's owner and resources decide and `member` is ignored. |
| `confirm` | No | `true` or `false`. Overrides `OOO-LiveMode` for this run. |
| `when_out`, `pick_by`, `coverage_article`, `backup_pool`, `boards`, `lookback_minutes`, `max_tickets`, `dispatch_to`, `time_zone`, `teams_flow_url`, `in_types`, `schedule_types` | No | Override the matching secret for this run. |
| `now` | No | A date and time to check against instead of the current time, for testing. |
| `triggerSource` | No | Where the call came from, for the run history. |

## Output

The standard contract: `status` (`success`, `pending_confirmation`, `incomplete`, `rejected` or `error`), `message`, `public_note` (always empty), `internal_note`, `ticket_id`, `actions`, `warnings` and `chatReply`. For one ticket, plus `out_members` (each member's identifier, `reasons` and `back` time), `plan` (`reassign`, `flag` or `unassign`), `replacement` (who got the ticket), `considered` (each candidate, their rank and why they were or weren't picked) and `changed`. For a sweep, plus `out_now` (who is out), `tickets` (one entry per ticket handled, with the same fields) and `skipped` (tickets left alone and why). A preview sweep returns `pending_confirmation`; a sweep where any ticket needs a person returns `incomplete`.

## Schedule it

AutomationAI **Routines > New**: pick this workflow and a short interval, for example `*/5 * * * *` (every 5 minutes; use `*/2` if your tenant allows it). A Routine sends no input, so every setting comes from the secrets, and it runs the deployed version, so redeploy after every edit. Routines aren't part of an export, so attach it again after every import.

**ServiceAI Triage needs nothing extra.** Triage keeps assigning owners as usual. If you set up a ServiceAI Action for this workflow (for example "Out-of-Office Check (ConnectWise)") and a Triage rule that runs it, remove the rule: the Routine replaces it. (If both stay, the `[ooo-check]` note stops a ticket being handled twice.)

## Test

1. **One ticket, preview.** In AutomationAI, open the workflow's **Test** run and send `{"ticketId":"<a ticket the out technician owns>","confirm":"false","now":"<a time they're out>"}`. Check `out_members`, `replacement` and `considered`.
2. **One ticket, live.** The same with `"confirm":"true"`. Check the new owner, that the out technician is gone from the ticket's resources and schedule, the internal note and the email.
3. **Sweep, preview.** Send `{"confirm":"false"}` (no ticket). Check `out_now` and `tickets`: every recent ticket owned by someone who is out, with who it would go to.
4. **Sweep, live.** Create a ticket ServiceAI Triage assigns to a technician you marked out, send `{}` with `OOO-LiveMode` on (or `{"confirm":"true"}`), and check the ticket moved.
5. Attach the Routine and watch the run history for a day.

## What has been proven on a live ConnectWise

Tested on ConnectWise staging (October 2026), one ticket at a time: the In/Out Board, an Out of Office Activity (matched by its activity type), Member # lookup, time zones, preview mode, `reassign` to the ticket's board team with `fewest-open` (`GET /service/boards/{id}/teams/{id}`), moving the schedule entry (`PATCH /schedule/entries/{id}`), `unassign`, the refused-change fallback, one internal note per ticket, repeat-run protection, ignoring a stray `member` once the ticket has an owner, and the HTML dispatcher email.

Not yet proven:

- The sweep: listing the In/Out Board and schedule for every member at once, and the `in (...)` conditions on `owner/identifier` and `board/name`.
- `least-recent` and `list-order` on a live tenant, including which Knowledge Base article fields hold the body (`issue` and `resolution` are read).
- The shortest interval AutomationAI Routines allow.
- Whether ServiceAI Triage ever assigns a ticket again after this workflow moves it.

### For developers

The step scripts live in `src/`. `build.js` embeds them, with `_shared/psa.ps1` and `_shared/postmark.ps1`, into `tech-out-of-office-check.yml`. `test.ps1` runs the shipped steps under strict mode against a mocked ConnectWise, Postmark and Teams flow.

```
node src/build.js
pwsh -NoProfile -File src/test.ps1
```
