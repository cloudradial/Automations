# Hand Off Escalated Tickets Without Rereading the Whole History

When a technician escalates or hands off a ticket, one click adds an internal note that sums it up for whoever picks it up: the problem, what was already tried and what happened, what's been ruled out, where it stands, and the next steps. Nobody has to reread forty notes, and the client doesn't have to explain it all again.

## What happens

**A technician asks for it.** From ServiceAI, they run the **Escalation Handoff Summary** Action, or click a Quick Action labelled **Handoff summary**, optionally saying why it's being escalated and to whom.

**The ticket is read.** The automation reads the ticket, its notes oldest first, and the time logged on it, including the technicians' time-entry notes where your PSA has them.

**An internal note appears on the ticket** with:

- the problem and who it affects
- each step already tried, with its result
- what's been ruled out
- where it stands and what it's waiting on
- suggested next steps for the person taking over
- anything about the client worth knowing, such as a deadline or their mood
- facts worth confirming
- the hours logged and who logged them, copied from your PSA

The technician also gets a one-line answer in ServiceAI with the problem and the first next step.

## What it protects

- **One ticket only.** It reads only the ticket it was asked about. It can check the ticket belongs to the company sent, and stops if it doesn't.
- **No passwords in the note.** Passwords, PINs, codes and product keys in the notes are masked before the AI sees them, and masked again in the note.
- **Nothing else changes.** It adds one internal note. Status, owner, priority and board stay as they were, and the client never sees the note.
- **No duplicates.** Asking twice adds nothing. Once there's new activity on the ticket, a fresh summary can be added. Earlier summaries are left out of the history, so a summary never summarizes itself.
- **Notes are data.** The AI is told never to follow instructions written in a note.

## Works with

ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk.

- **Time entries:** read on ConnectWise, Autotask, HaloPSA, Kaseya BMS and Syncro. Zendesk has none, and when they can't be read the summary uses the notes only and says so.
- **Kaseya BMS:** its notes don't say whether the client or a technician wrote them, so the summary can't always tell who said what. The note says so.

## What you need

- AutomationAI, with your PSA connected and an AI provider on the runner
- ServiceAI, to run it from a ticket (it can also be run by hand in AutomationAI)

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/escalation-handoff-summary/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. Turn on the webhook in **Properties**, then click **Publish** and **Deploy** to your runner.

**In ServiceAI (Settings > Actions):**

1. Save the workflow's webhook secret in the ServiceAI **Secrets** manager as `aai_escalation_handoff`.
2. Create an Action called **Escalation Handoff Summary** (**Use in AI**) pointing at the workflow's webhook address. The body and parameters are in the [technical details](https://github.com/cloudradial/Automations/tree/main/escalation-handoff-summary#serviceai-action).
3. Optionally, add a Pod Quick Action labelled **Handoff summary** (Settings > AI Behavior > Pod Quick Actions).

**Test it.** Run it by hand on a ticket with some history and `"addNote": false`, and read the note it would add. Then run it without `addNote` and check the note on the ticket.

## Need more detail?

See the [technical details](https://github.com/cloudradial/Automations/tree/main/escalation-handoff-summary#technical-details) for every setting, the ServiceAI Action, the output, and how to build and test it.

---

## Technical details

**Marketplace ID:** CRA-00010 | **Type:** Workflow (PowerShell steps plus one AI Prompt step) | **Version:** 1.0.0

## Files

Each version is published as a release, with `escalation-handoff-summary.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/escalation-handoff-summary/v1.0.0).

| What | Link |
|---|---|
| Download `escalation-handoff-summary.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/escalation-handoff-summary/v1.0.0) |
| View the current source | [`escalation-handoff-summary.yml`](https://github.com/cloudradial/Automations/blob/main/escalation-handoff-summary/escalation-handoff-summary.yml) |
| Build source and tests | [src/](https://github.com/cloudradial/Automations/tree/main/escalation-handoff-summary/src) |
| All files in this automation | [escalation-handoff-summary](https://github.com/cloudradial/Automations/tree/main/escalation-handoff-summary) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/escalation-handoff-summary) |

## How it works

`Start → Read the ticket history → Write the handoff summary → Post the handoff note → End`

| Step | What it does |
|---|---|
| **Read the ticket history** | Reads the ticket, checks it belongs to `companyId` or `companyName` when sent, then reads its notes oldest first and its time entries. Earlier handoff summaries are left out. A long ticket keeps its first note and the newest `maxNotes - 1`. Each note is tagged as from the client or a technician, plain-texted, trimmed to 1,500 characters and has secrets masked. Changes nothing. |
| **Write the handoff summary** | An AI Prompt step. It returns JSON: `problem`, `impact`, `tried`, `ruledOut`, `currentState`, `waitingOn`, `nextSteps`, `clientContext` and `openQuestions`. It may use only the facts given, and is told never to repeat a credential. The model is left blank, so it uses the runner's provider. |
| **Post the handoff note** | Builds the note from the AI's JSON, masks secrets again, and adds the status, first-note date, notes read, hours and people from the PSA (never from the AI). Then it adds one internal note. When the AI answer is unusable, the note lists the newest three notes instead and says so. |

The note carries a marker `[escalation-handoff <ticket>-<newest note>]`. A rerun with no new notes finds it and adds nothing; a new note on the ticket gives a new marker, so a fresh summary is allowed.

### Why a workflow with one AI Prompt step, not an agent

Reading a ticket's notes and time is fixed work, so it runs the same way every time in PowerShell across all six PSAs. The AI gets the whole history in one prompt instead of paying a model turn per tool call, and the note is written by a script step, so a ServiceAI run never waits for approval in the Inbox.

## Inputs

| Field | Required | What it does |
|---|---|---|
| `ticketId` | Yes | The PSA ticket number. Autotask and Kaseya BMS numbers such as `T20261008.0001` are looked up. |
| `reason` | No | Why it's being escalated, in the technician's words. It frames the summary and is shown at the top of the note. |
| `escalateTo` | No | Who it's going to, such as `Tier 2` or a name. |
| `companyName`, `companyId` | No | When sent, the run stops (`rejected`) if the ticket belongs to another company. |
| `maxNotes` | No (default 30) | The most notes to summarize, 5 to 100. |
| `includeTime` | No (default `true`) | `false` skips the time entries. |
| `addNote` | No (default `true`) | `false` writes nothing and returns the note as a preview (`status: pending_confirmation`). |
| `psa` | No | Overrides the `PSA-Type` secret. |
| `triggerSource` | No | `serviceai-ai` or `manual`. Recorded only. |

Placeholder values ServiceAI leaves unfilled (`<reason>`, `{{reason}}` or a literal `@reason`) count as not given.

## ServiceAI Action

**Escalation Handoff Summary**, **Use in AI**, pointing at the workflow's webhook URL with the header `X-Crauto-Webhook-Secret: {{secret.aai_escalation_handoff}}`.

Body:

```json
{"ticketId": "<ticketId>", "reason": "<reason>", "escalateTo": "<escalateTo>", "triggerSource": "serviceai-ai"}
```

Parameters: `ticketId` (required string), and `reason` and `escalateTo` (optional strings).

**Pod Quick Action** (Settings > AI Behavior > Pod Quick Actions): label **Handoff summary**, prompt *"Run the Escalation Handoff Summary action for this ticket. Ask me why it's being escalated and to whom if I haven't said, then show me the summary."*

## Output

`status` (`success`, `pending_confirmation`, `incomplete`, `rejected` or `error`), `message`, `public_note` (always empty), `internal_note` (the note), `ticket_id`, `psa`, `summarized_by` (`ai` or `notes`), `note_written`, `actions`, `warnings` and `chatReply` (the problem and the first next step, for ServiceAI to show the technician).

## Secrets

By name only. The PSA names are the same as the catalog extensions, so one set serves both.

| Secret | For |
|---|---|
| `PSA-Type` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` (a `psa` input overrides it) |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | Optional: `Autotask-NotePublishId`, `Autotask-NoteTypeId` |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Optional: `Halo-NoteOutcomeId` |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId` | |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | |
| `PSA-TicketUrlTemplate` (optional) | The ticket link in the note, with `{id}` for the ticket id. |

**ServiceAI Secrets manager:** `aai_escalation_handoff`, the workflow's webhook secret.

**PSA permissions:** read tickets, notes and time entries, and add notes.

## Developing

Edit the files in `src/` (`gather.ps1`, `note.ps1`, `summarize.prompt.txt`, `summarize.system.txt`), then run `node escalation-handoff-summary/src/build.js`. Never edit the `.yml`. Before pushing:

```
node escalation-handoff-summary/src/build.js --check
pwsh -NoProfile -File escalation-handoff-summary/src/test.ps1
```

The harness runs both PowerShell steps in strict mode, the way the runner does, against mock versions of all six PSAs (`mock-psa.ps1`, the shared Waiting-on-Client Nudge mock, extended to read one ticket and its ConnectWise and Autotask time entries). A fixed JSON stands in for the AI step's output. Test data is placeholder only.
