# Close Tickets When the Client Says Thanks

When a client replies "thanks, that worked" to a Resolved or waiting-on-client ticket, the ticket closes on its own, with an internal note quoting their reply. Your board only shows work that still needs someone, and nobody has to close tickets by hand after a happy reply.

## What happens

**Every hour, in the background.** The automation looks at tickets in your Resolved and waiting-on-client statuses and reads the newest note on each.

**A short thank-you closes the ticket.** When the newest note is from the client and is just a thank-you or a "that fixed it", the ticket is closed and gets an internal note with the client's words.

**Anything else is left for your team.** A reply that asks a question, says "but", "still" or "not", reports another problem, or runs long stays open for a technician, exactly as it is.

## What it protects

- **Fixed rules, no AI.** The same reply always gets the same answer, and you can read the rules in the technical details.
- **Your technician gets the last word.** If a technician wrote after the client's thanks, the ticket is left alone.
- **A moment to see it first.** A reply has to be at least 30 minutes old before the ticket closes.
- **One close per reply.** Each reply is acted on once, even if the run repeats.
- **Only the statuses you choose.** Tickets in any other status, such as In Progress, are never touched.
- **Preview first.** Run it with `"preview": true` to see which tickets it would close.

## Works with

ConnectWise PSA, Autotask, HaloPSA, Syncro and Zendesk.

- **Kaseya BMS:** not yet. Its notes don't say who wrote them, so the run stops with a plain reason.
- **All PSAs:** it relies on the PSA marking which notes came from the client, and on your status names. Check the defaults below match yours.
- **ConnectWise:** many boards move a ticket to a status such as "Customer Responded" when the client replies. Add that status to `statuses` only if tickets in it are otherwise finished, because a thank-you on a ticket a technician is still working would close it.

## What you need

- AutomationAI, with your PSA connected

## Set it up

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/thank-you-close/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy** to your runner.
4. Add a **Routine** that runs it every hour.

**Test it.** Run it once with `{"preview": true}` and check the tickets it lists. If your status names differ from the defaults, add `statuses` to the Routine's input.

## Need more detail?

See the [technical details](https://github.com/cloudradial/Automations/tree/main/thank-you-close#technical-details) for the rules, every setting and how to build and test it.

---

## Technical details

**Marketplace ID:** CRA-00013 | **Type:** Workflow (one PowerShell step) | **Version:** 1.0.0

## Files

Each version is published as a release, with `thank-you-close.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/thank-you-close/v1.0.0).

| What | Link |
|---|---|
| Download `thank-you-close.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/thank-you-close/v1.0.0) |
| View the current source | [`thank-you-close.yml`](https://github.com/cloudradial/Automations/blob/main/thank-you-close/thank-you-close.yml) |
| Build source and tests | [src/](https://github.com/cloudradial/Automations/tree/main/thank-you-close/src) |
| All files in this automation | [thank-you-close](https://github.com/cloudradial/Automations/tree/main/thank-you-close) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/thank-you-close) |

## How it works

`Start → Close tickets the client thanked us for → End`

For each watched status, it lists the tickets updated in the last `max_age_days`, then reads each ticket's notes. A ticket closes only when all of these hold:

1. The newest note was written by the client (as the PSA marks it) and isn't internal.
2. That note is at least `min_age_minutes` old.
3. No earlier run already acted on it (marker `[thank-you-close <ticket>-<note>]`).
4. The reply, cut at any quoted email history or sign-off, is 40 words or fewer.
5. It contains no question mark and none of: not, no longer, isn't, doesn't, didn't, won't, can't, cannot, still, but, however, although, again, another, also, error, broken, fail, can/could/would you, please check/look/help/call/advise, one more, quick question, unfortunately, except.
6. It says thanks or that it's fixed: thanks, thank you, thx, ty, cheers, appreciated, all good/sorted/set/fixed/working, sorted, that worked/fixed it/did it/did the trick, works or working now/again/fine, issue or problem resolved/fixed/gone, perfect, brilliant, awesome.

It then closes the ticket (to `close_status_name`, or the PSA's usual closed status, never back to the Resolved status it's in) and adds the internal note. A ticket that fails to close is reported and left as it was.

## Run input

A Routine sends no input, so every setting has a default.

| Field | Default | What it does |
|---|---|---|
| `statuses` | the PSA's waiting status and `Resolved` (Zendesk: `pending,solved`) | The status names to watch, comma separated. ConnectWise and Autotask: `Waiting Customer,Resolved`. HaloPSA: `Waiting on User,Resolved`. Syncro: `Waiting on Customer,Resolved`. |
| `min_age_minutes` | `30` | How old the client's reply must be before the ticket closes (0 to 1440). |
| `max_age_days` | `14` | Only tickets updated in this many days are checked (1 to 90). |
| `close_status_name` | the PSA's usual closed status | The status to close to. |
| `preview` | `false` | `true` lists what it would close and writes nothing. |
| `max_tickets` | `200` | The most tickets to check per status (1 to 1000). |
| `psa` | the `PSA-Type` secret | Overrides which PSA to use. |

## Output

`status` (`success`, `partial` when something needs a look, or `pending_confirmation` in preview), `message`, `closed` (each ticket with the reply that closed it and the result), `skipped` (each with the reason), and `warnings`.

## Secrets

Your PSA's secrets only (`PSA-Type` and its connection), with the same names as your PSA's catalog extension.

## Developing

Edit `src/close.ps1`, then run `node thank-you-close/src/build.js`. Never edit the `.yml`. Before pushing:

```
node thank-you-close/src/build.js --check
pwsh -NoProfile -File thank-you-close/src/test.ps1
```

The harness runs the step in strict mode, the way the runner does, against mock versions of the PSAs (`mock-psa.ps1`, shared with Waiting-on-Client Nudge, Auto-Close Resolved and Frustrated Client Alert). Test data is placeholder only.
