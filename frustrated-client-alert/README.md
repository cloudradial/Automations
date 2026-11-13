# Catch Frustrated Clients Before They Escalate

Every 15 minutes, new client replies on open tickets are read for tone. When a client sounds frustrated, the ticket gets an internal note saying why, with their own words, and your service manager gets an email so someone can call them the same day.

## What happens

**Every 15 minutes, in the background.** The automation looks at open tickets that changed in the last 20 minutes and picks out the replies written by the client.

**Each new reply is scored.** One AI step reads the replies and rates each one: frustrated, impatient, or fine. Thanks, answers to questions and out-of-office replies are left alone.

**Frustrated clients get flagged.** For each frustrated or impatient reply:

- **The ticket gets an internal note** with the reason, the client's own words, and a suggested next step, such as calling them today.
- **Your service manager gets one email** listing the frustrated clients, each with a link to the ticket. By default only clear frustration is emailed; impatience is noted on the ticket only.

## What it protects

- **One alert per reply, one note per ticket.** Each reply is flagged at most once, even when runs overlap. A client who sends three upset emails in a minute gets one note, not three.
- **Nothing else changes.** It only adds internal notes and sends the email. Ticket status, priority and owner stay as they were, and the client never sees the note.
- **Client words are data.** The AI is told never to follow instructions written in a reply.
- **Preview first.** Run it with `"preview": true` to see what it would flag without writing anything.

## Works with

ConnectWise PSA, Autotask, HaloPSA, Syncro and Zendesk.

- **Kaseya BMS:** not yet. Its notes don't say who wrote them, so client replies can't be picked out. The run says so.
- **All PSAs:** it relies on the PSA marking which notes came from the client. Check one live run before you rely on it.

## What you need

- AutomationAI, with your PSA connected and an AI provider on the runner
- Postmark, connected in AutomationAI, for the email (without it, the alerts are only on the tickets)
- The address that should hear about frustrated clients

## Set it up

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/frustrated-client-alert/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. Add the `Sentiment-AlertEmail` secret to your runner with the address to alert, such as your service manager.
4. Click **Publish**, then **Deploy** to your runner.
5. Add a **Routine** that runs it every 15 minutes.

**Test it.** Run it once with `{"preview": true, "lookback_minutes": 240}` and check what it would flag. Then run it without preview on a test ticket where you replied as the client.

## Need more detail?

See the [technical details](https://github.com/cloudradial/Automations/tree/main/frustrated-client-alert#technical-details) for every setting, the output, and how to build and test it.

---

## Technical details

**Marketplace ID:** Not listed yet | **Type:** Workflow (PowerShell steps plus one AI Prompt step) | **Version:** 1.0.0

## Files

Each version is published as a release, with `frustrated-client-alert.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/frustrated-client-alert/v1.0.0).

| What | Link |
|---|---|
| Download `frustrated-client-alert.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/frustrated-client-alert/v1.0.0) |
| View the current source | [`frustrated-client-alert.yml`](https://github.com/cloudradial/Automations/blob/main/frustrated-client-alert/frustrated-client-alert.yml) |
| Build source and tests | [src/](https://github.com/cloudradial/Automations/tree/main/frustrated-client-alert/src) |
| All files in this automation | [frustrated-client-alert](https://github.com/cloudradial/Automations/tree/main/frustrated-client-alert) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/frustrated-client-alert) |

## How it works

`Start → Find new client replies → Score frustration → Alert on frustrated clients → End`

| Step | What it does |
|---|---|
| **Find new client replies** | Lists open tickets updated in the look-back window (newest first, up to `max_tickets`), reads their notes, and keeps the public notes the PSA marks as from the client, written inside the window, that don't already have an alert. Changes nothing. |
| **Score frustration** | An AI Prompt step. It rates each reply `high`, `medium` or `none`, with a one-sentence reason and the shortest quote that shows it. When there are no replies it is told to skip. The model is left blank, so it uses the runner's provider. |
| **Alert on frustrated clients** | Adds one internal note per ticket, at the highest level among its `medium` or `high` replies, with up to three of the client's quotes. The note carries a marker `[frustrated-client <ticket>-<note>]` for every reply it covers, so a later run never repeats any of them. Then it sends one email for the replies at `email_level`. A reply whose note fails is not emailed, so a rerun tries both again. |

The look-back window (20 minutes) is longer than the Routine interval (15 minutes), so a late or slow run doesn't miss replies. The overlap can't cause a second alert, because each alert's marker is checked first.

## Run input

A Routine sends no input, so every setting has a default. For a manual run, send any of these:

| Field | Default | What it does |
|---|---|---|
| `lookback_minutes` | `20` | How far back to look for client replies (5 to 1440). Keep it a little longer than the Routine interval. |
| `email_level` | `high` | `high` emails only clear frustration, `medium` emails impatience too, and `none` never emails (notes only). |
| `alert_email` | the `Sentiment-AlertEmail` secret, then `CSAT-ServiceManagerEmail` | Who gets the email. Several addresses can be separated by commas. |
| `preview` | `false` | `true` works everything out and writes nothing. |
| `max_tickets` | `100` | The most updated tickets to check per run (1 to 500). |
| `max_replies` | `25` | The most replies to score per run (1 to 50). The rest wait for the next run if they're still in the window. |
| `company` | all | A PSA company name or id, to watch one client only. |
| `psa` | the `PSA-Type` secret | Overrides which PSA to use. |

## Output

The last step returns `status` (`success`, `partial` when something needs a look, or `pending_confirmation` in preview), `message`, `checked`, `scored`, `flagged` (each with the ticket, level, reason, quote and link), `actions` and `warnings`.

## Secrets

| Name | Needed | What it is |
|---|---|---|
| Your PSA's secrets (`PSA-Type` and its connection) | Yes | The same names as your PSA's catalog extension. |
| `Sentiment-AlertEmail` | Recommended | Who gets the email. Falls back to `CSAT-ServiceManagerEmail`. |
| `Postmark-ServerToken`, `Postmark-FromEmail` | For the email | Postmark's server token and a verified sender. |

## Developing

Edit the files in `src/` (`find.ps1`, `alert.ps1`, `score.prompt.txt`, `score.system.txt`), then run `node frustrated-client-alert/src/build.js`. Never edit the `.yml`. Before pushing:

```
node frustrated-client-alert/src/build.js --check
pwsh -NoProfile -File frustrated-client-alert/src/test.ps1
```

The harness runs both PowerShell steps in strict mode, the way the runner does, against mock versions of all six PSAs (`mock-psa.ps1`, shared with Waiting-on-Client Nudge and Auto-Close Resolved, plus open-ticket list support). A fixed JSON stands in for the AI step's output. Test data is placeholder only.
