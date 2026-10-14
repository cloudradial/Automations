# Turn Resolved Tickets into Knowledge Base Drafts

When a ticket is fixed, the fix becomes a clean, general knowledge base article draft in your CloudRadial portal, with every client name, person, address and password taken out, waiting for a technician to review and publish.

**Marketplace ID:** TBD | **Type:** Workflow (PowerShell steps plus one AI Prompt step) | **Version:** 1.0.0

## Files

Each version is published as a release, with `kb-draft-from-resolution.yml` attached. Download the latest from the [**releases page**](https://github.com/cloudradial/Automations/releases?q=kb-draft-from-resolution&expanded=true).

| What | Link |
|---|---|
| Download `kb-draft-from-resolution.yml` (all versions) | [Releases](https://github.com/cloudradial/Automations/releases?q=kb-draft-from-resolution&expanded=true) |
| View the current source | [`kb-draft-from-resolution.yml`](https://github.com/cloudradial/Automations/blob/main/kb-draft-from-resolution/kb-draft-from-resolution.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/kb-draft-from-resolution/src) |
| All files in this automation | [kb-draft-from-resolution](https://github.com/cloudradial/Automations/tree/main/kb-draft-from-resolution) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/kb-draft-from-resolution) |

## How it works

Three steps. Only step 2 uses AI, and it can't call any tools.

1. **Read the resolution (read-only).** Reads the ticket and how it was fixed, taking the first of these that exists:
   1. the `resolutionNotes` input
   2. the ticket's own resolution field (Autotask resolution, HaloPSA clearance note, Kaseya BMS Resolution)
   3. ConnectWise notes marked as the resolution
   4. the newest technician notes

   It stops when there is too little text to write from, and it stops quietly when a draft was already made from this ticket.

   **Before anything reaches the AI**, it takes out:
   - the client company's name
   - the contact's and technicians' names
   - email addresses and the client's domains
   - phone numbers, IP addresses and server paths (`\\server\share`)
   - passwords, PINs, keys and tokens (the value after `password:`, `PIN is` and the like) and product keys

   A single-word name is only removed as written, with a capital, so the name Will never removes the word "will".
2. **Draft the article (AI Prompt).** Returns structured fields, not HTML:
   - `worthPublishing` and `reason`
   - `subject`, `category` and `appliesTo`
   - `symptoms`, `cause` and `steps`

   It's told to write only what the facts support, keep it general, and say `worthPublishing: false` for one-off fixes. No model is pinned, so the tenant's own provider is used.
3. **Save the draft for review.**
   - **Cleaned again.** Every field is cleaned again, in case the AI put a detail back; a warning says so. A draft with no title or no steps isn't saved.
   - **Article layout:** a "Draft for review" banner, then Applies to, Symptoms, Cause and numbered "How to fix it" steps.
   - **`confirm` false (the default):** nothing is saved. The run returns the draft (`status: pending_confirmation`).
   - **`confirm` true:** the draft is saved in CloudRadial and an internal note on the ticket names it.
   - **One draft per ticket:** the article's author is "AutomationAI draft (ticket N)" and the ticket note carries a marker.

### How a draft stays out of clients' sight

CloudRadial has no draft state for articles: an article is live once it's created. So a draft is kept hidden two ways:

- **It's saved under your own CloudRadial company** (the `KbDraft-CompanyId` secret), never the client's company. Company `0` is refused, because MSP-wide articles there are shown to every client.
- **Its publish date is 2099-12-31**, so it isn't shown until someone sets a real date.

To publish one, review it, move it to the right company (or MSP-wide), set the publish date, and remove the banner and `[Draft]` from the title.

### Should you use it with ServiceAI?

ServiceAI can already write knowledge base articles from tickets and send them to Hudu. Use this workflow when you want the draft in your **CloudRadial portal's** knowledge base, with the details taken out before the AI sees them.

## Download & import

**Download the workflow:** [`kb-draft-from-resolution.yml`](https://github.com/cloudradial/Automations/releases?q=kb-draft-from-resolution&expanded=true)

Then in AutomationAI:
1. **Workflows → Import**, and upload the `.yml`.
2. Add the [required secrets](#required-runner-key-vault-secrets) to the runner.
3. Enable the webhook in **Properties**.
4. **Publish** and **Deploy**.

Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

By name only. The PSA and CloudRadial names are the same as the catalog extensions, so one set serves both.

| Secret | For |
|---|---|
| `PSA-Type` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` (a `psa` input overrides it) |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | Optional: `Autotask-NotePublishId`, `Autotask-NoteTypeId` |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Optional: `Halo-NoteOutcomeId` |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId` | |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Saving the draft. The keys need to read and create articles. |
| `KbDraft-CompanyId` | **Required to save.** Your own CloudRadial company id, where drafts wait for review. Not `0`. |

**PSA permissions:** the API member or key needs to:
- read tickets, contacts and notes
- add internal notes

## Required Graph permissions

None. This workflow only talks to the PSA and CloudRadial.

## Inputs

| Field | Required | Meaning |
|---|---|---|
| `ticketId` | Yes | The PSA ticket number. Autotask and Kaseya BMS numbers such as `T20261014.0001` and Syncro ticket numbers are looked up to the internal id. |
| `confirm` | No (default `false`) | `true` saves the draft and notes the ticket. `false` returns the draft and saves nothing. `approvedToWrite` works too. |
| `resolutionNotes` | No | The fix, when you want to give it directly instead of reading it from the ticket. It's cleaned like everything else. |
| `category` | No | The article category. Without it, the AI suggests one. |
| `psa` | No | Overrides the `PSA-Type` secret. |

It accepts a flat JSON body, the CloudRadial `{Ticket: {...}, Company: {...}}` shape, or either one wrapped in `{trigger: ...}`. Placeholder values left unfilled (`<ticketId>`, `{{ticketId}}` or a bare `@token`) count as not given.

## Output

| Field | Meaning |
|---|---|
| `status` | `success`, `pending_confirmation`, `incomplete` or `error` |
| `message` | What happened, in a sentence |
| `public_note` | Always empty. Nothing is posted to the client. |
| `internal_note` | The ticket note text |
| `ticket_id` | The ticket number |
| `draft` | `subject`, `category`, `author` and the HTML `body` |
| `counts` | `draftsSaved` and `notesWritten` |
| `actions`, `warnings` | What ran, and anything to check |

## Import & test

1. Import `kb-draft-from-resolution.yml`, add the secrets above to the runner vault, then **Publish** and **Deploy** to that runner.
2. **Preview first.** Pick a closed test ticket with a real fix in its resolution, and run the first step's Test Input with its number and `"confirm": false`. Then check two things:
   - The first step's `facts_json` has no client name, person, address or password.
   - The run's `draft` reads as a general article.
3. **Save it.** Run again with `"confirm": true`. Then:
   - Expect one article in your `KbDraft-CompanyId` company, titled `[Draft] ...` and dated 2099-12-31, and one internal note on the ticket.
   - **Open the portal as a client user** and confirm the draft isn't visible.
4. **Rerun.** Run once more. Expect "already made" and nothing saved.
5. **Wire the trigger.** Enable the webhook in **Properties**. AutomationAI issues the URL and secret, and the caller sends the secret in the `X-Crauto-Webhook-Secret` header. Call it when a ticket is closed:
   - from your PSA's ticket-closed callback, or
   - from a ServiceAI Action with the body `{"ticketId": "<ticketId>", "confirm": "true"}`.

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. The step logic lives in `src/`: edit `gather.ps1`, `save.ps1`, `scrub.ps1` or the `judge.*.txt` prompts, then run `node src/build.js` (it pastes `src/scrub.ps1` and `_shared/psa.ps1`, `psa-tickets.ps1` and `cloudradial.ps1`) and `pwsh -NoProfile -File src/test.ps1`. Never edit the `.yml` by hand.

### Not yet proven live

- **Already proven by the shared library:** reading the ticket and notes, and the internal note.
- **Not yet proven live:**
  - **Clients can't see a future-dated article.** Troubleshooting Article Delivery treats future-dated articles as not yet visible. Confirm it in step 3 above with a client login before relying on it.
  - **Filtering articles by `author`** to find an existing draft.
  - **The HaloPSA and Kaseya BMS resolution field names**, marked `Unverified` in `gather.ps1`.
  - **The Autotask `/Contacts/{id}` and Zendesk `/users/{id}` contact reads.**
- **Redaction is a safety net, not a guarantee.** Read every draft before publishing it.
