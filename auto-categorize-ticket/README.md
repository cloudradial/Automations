# Categorize New Tickets Automatically

New tickets arrive with their type and subtype already filled in from your PSA's own list. They reach the right people and the right reports without a dispatcher sorting them by hand.

## What happens

When a new ticket comes in, the automation reads its summary and description and picks the best type (and subtype, where your PSA has them) from the categories your PSA already allows for that ticket. Your clients don't see anything different. Your team sees a ticket that's already categorized, with a short internal note explaining why.

If the automation isn't sure enough, it doesn't change the ticket. It leaves an internal note with its suggestion, so a technician can set it.

## What it protects

- **Nothing a technician set is ever overwritten.** Only blank or "not set yet" fields (such as Unclassified) are filled. The board is never changed.
- **Only real categories are used.** Every pick is checked against your PSA's list before it's saved. Anything that isn't there is dropped.
- **It starts in preview.** Until you turn on making changes, it only reports what it would set.
- **One note per ticket.** Running it again on the same ticket never adds a second note.
- **Your clients see nothing.** All notes are internal.

## Works with

ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk.

- **ConnectWise PSA:** fills type, subtype and item, using your board's own combinations.
- **Autotask and Kaseya BMS:** fills issue type and sub-issue type.
- **HaloPSA:** fills the category. **Syncro:** fills the issue type. **Zendesk:** fills the ticket type.
- **HaloPSA, Kaseya BMS and Syncro:** the category lookups haven't been proven on a live PSA yet, and parts of the ConnectWise lookup haven't either. Watch one run on your PSA before letting it make changes on its own.

## What you need

- AutomationAI, with your PSA's API details added to your runner
- A PSA account that can read tickets and category lists, update tickets and add notes
- An AI provider set up in AutomationAI (it uses your own)
- Something to start it when a ticket is created: your PSA's ticket-created callback, or a ServiceAI Action

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/auto-categorize-ticket/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. Add your PSA's API details to your runner. The technical details list exactly what's needed.
4. Turn on the webhook in **Properties**. AutomationAI gives you a URL and a secret.
5. Click **Publish**, then **Deploy**.

**Start it when a ticket is created:**

1. In ServiceAI, go to **Settings > Actions** and add an action that calls the webhook with the ticket number. Or point your PSA's ticket-created callback at it.
2. Leave it in preview at first. When you're happy with its picks, turn on making changes.

You can also choose how sure it has to be before it sets a category, and whether it adds the internal note.

**Test it.** Run it on a ticket with a blank type, check what it would set, then run it again with changes turned on and confirm the ticket is categorized with one internal note.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/auto-categorize-ticket#technical-details) cover how each step works, every PSA's fields, the full setup and test steps, and what hasn't been proven live yet.

---

## Technical details

**Marketplace ID:** AAI-00057 | **Type:** Workflow (PowerShell steps plus one AI Prompt step) | **Version:** 1.0.0

## Files

Each version is published as a release, with `auto-categorize-ticket.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/auto-categorize-ticket/v1.0.0).

| What | Link |
|---|---|
| Download `auto-categorize-ticket.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/auto-categorize-ticket/v1.0.0) |
| View the current source | [`auto-categorize-ticket.yml`](https://github.com/cloudradial/Automations/blob/main/auto-categorize-ticket/auto-categorize-ticket.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/auto-categorize-ticket/src) |
| All files in this automation | [auto-categorize-ticket](https://github.com/cloudradial/Automations/tree/main/auto-categorize-ticket) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/auto-categorize-ticket) |

## How it works

Three steps. Only step 2 uses AI, and it can't call any tools.

1. **Read the ticket and its categories (no AI).** Reads the ticket and the category values your PSA allows for it. On ConnectWise that's the ticket's own board.
   - **Open fields:** a field is open when it's blank, or set to a "not set yet" value such as `Unclassified`, `Uncategorized`, `Unknown` or `None`. The open fields are the first blank one and the blank ones right after it.
   - **Never changed:** a field a technician already set, anything below it, and the board.
2. **Pick the category (AI Prompt).** One AI call reads the ticket summary and description and returns `{picks, confidence, reason}`.
   - It sees only the allowed names for the open fields, as a tree, so a subtype can only come from under its type.
   - No model is pinned, so the tenant's own provider is used.
   - Ticket text is treated as data, never as instructions.
3. **Set the category and note it.** Every pick is checked against the PSA's list under the level above it. A name that isn't there is dropped, along with everything below it. Then:
   - **`confirm` false (the default):** nothing is written. The run returns what it would set (`status: pending_confirmation`).
   - **`confirm` true and confidence at least `minConfidence` (default 0.7):** sets the open fields and adds one internal note with the reasoning.
   - **`confirm` true and lower confidence:** changes no field and adds an internal note with the suggestion, so a technician can set it.

| PSA | Fields |
|---|---|
| ConnectWise PSA | Type > Subtype > Item, from the board's type, subtype and item combinations |
| Autotask | Issue Type > Sub-Issue Type, from the ticket picklists |
| HaloPSA | Category (`category_1`) |
| Kaseya BMS | Issue Type > Sub-Issue Type |
| Syncro | Issue type (`problem_type`) |
| Zendesk | Type (question, incident, problem, task) |

Notes carry a marker, so a rerun or a ServiceAI Retry never adds a second note. A ticket that's already categorized is left alone: the AI step is told to skip it, and nothing is written.

### Should you use it with ServiceAI triage?

ServiceAI triage can already set a ticket's type and category. Use this workflow when triage leaves a gap:
- tickets triage doesn't see
- a PSA or board it doesn't categorize
- when you want the category checked against the board's own combinations before it's written

## Download & import

**Download the workflow:** [`auto-categorize-ticket.yml`](https://github.com/cloudradial/Automations/releases/tag/auto-categorize-ticket/v1.0.0)

Then in AutomationAI:
1. **Workflows → Import**, and upload the `.yml`.
2. Add the [required secrets](#required-runner-key-vault-secrets) to the runner.
3. Enable the webhook in **Properties** if your PSA or ServiceAI calls it.
4. **Publish** and **Deploy**.

Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

By name only. Use the same names as the catalog extensions, so one set serves both.

| Secret | For |
|---|---|
| `PSA-Type` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` (a `psa` input overrides it) |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | Optional: `Autotask-NotePublishId`, `Autotask-NoteTypeId` |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Optional: `Halo-NoteOutcomeId` |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId` | |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | |

**PSA permissions:** the API member or key needs to:
- read tickets
- read the category lists (on ConnectWise, service board types, subtypes and items)
- update tickets
- add notes

A missing permission stops the run with a plain message naming it, before anything is changed.

## Required Graph permissions

None. This workflow only talks to the PSA.

## Inputs

| Field | Required | Meaning |
|---|---|---|
| `ticketId` | Yes | The PSA ticket number. Autotask and Kaseya BMS numbers such as `T20261014.0001` and Syncro ticket numbers are looked up to the internal id. |
| `confirm` | No (default `false`) | `true` sets the fields and writes the note. `false` changes nothing and returns what it would do. `approvedToWrite` works too. |
| `minConfidence` | No (default 0.7) | AI confidence (0 to 1) needed to set the fields. Below it, a confirmed run only notes the suggestion. |
| `addNote` | No (default `true`) | `false` sets the fields without the internal note. |
| `psa` | No | Overrides the `PSA-Type` secret. |

It accepts a flat JSON body, the CloudRadial `{Ticket: {...}, Company: {...}}` shape, or either one wrapped in `{trigger: ...}`. Placeholder values left unfilled (`<ticketId>`, `{{ticketId}}` or a literal `@token`) count as not given.

## Output

| Field | Meaning |
|---|---|
| `status` | `success`, `pending_confirmation`, `incomplete`, `rejected` or `error` |
| `message` | What happened, in a sentence |
| `public_note` | Always empty. Nothing is posted to the client. |
| `internal_note` | The note text |
| `ticket_id` | The ticket number |
| `suggested` | The chosen value per field |
| `counts` | `fieldsSet` and `notesWritten` |
| `actions`, `warnings` | What ran, and anything to check |

## Import & test

1. Import `auto-categorize-ticket.yml`, add the secrets above to the runner vault, then **Publish** and **Deploy** to that runner.
2. **Preview first.** Pick a ticket whose type is blank, and run the first step's Test Input with its number and `"confirm": false`. Expect:
   - `status: pending_confirmation`
   - the would-set values in `message`
   - nothing changed on the ticket
3. **Set it.** Run again with `"confirm": true`. Expect the blank fields set and one internal note with the reasoning.
4. **Rerun.** Run once more. Expect "already has its type, subtype, item set" and nothing written.
5. **Wire the trigger.** Enable the webhook in **Properties**. AutomationAI issues the URL and secret, and the caller sends the secret in the `X-Crauto-Webhook-Secret` header. Then call it when a ticket is created:
   - from your PSA's ticket-created callback, or
   - from a ServiceAI Action with the body `{"ticketId": "<ticketId>", "confirm": "true"}`.

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. The step logic lives in `src/`: edit `gather.ps1`, `write.ps1`, `psa-categories.ps1` or the `judge.*.txt` prompts, then run `node src/build.js` (it pastes `src/psa-categories.ps1` and `_shared/psa.ps1`) and `pwsh -NoProfile -File src/test.ps1`. Never edit the `.yml` by hand.

### Not yet proven live

- **Already proven by the shared library:** reading the ticket, the ticket-number lookup and the internal note.
- **ConnectWise and Autotask:** the category calls are the ones their catalog extensions make: board types, subtypes and items on ConnectWise, and the ticket picklists on Autotask.
- **Marked `Unverified` in `src/psa-categories.ps1`:**
  - the ConnectWise type, subtype and item combinations and items lists
  - the HaloPSA category list
  - the Kaseya BMS issue-type lookups
  - the Syncro ticket settings

  Check one supervised run on your PSA before turning on `confirm` from a trigger.
