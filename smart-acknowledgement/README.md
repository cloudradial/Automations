# Acknowledge Every New Ticket Personally

The moment a ticket arrives, the client gets a short, personal acknowledgement with their ticket number, when to expect a response and, when one fits, a knowledge base article to try while they wait, without ever being promised a fix time.

**Marketplace ID:** AAI-00059 | **Type:** Workflow (PowerShell steps plus one AI Prompt step) | **Version:** 1.0.0

## Files

Each version is published as a release, with `smart-acknowledgement.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/smart-acknowledgement/v1.0.0).

| What | Link |
|---|---|
| Download `smart-acknowledgement.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/smart-acknowledgement/v1.0.0) |
| View the current source | [`smart-acknowledgement.yml`](https://github.com/cloudradial/Automations/blob/main/smart-acknowledgement/smart-acknowledgement.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/smart-acknowledgement/src) |
| All files in this automation | [smart-acknowledgement](https://github.com/cloudradial/Automations/tree/main/smart-acknowledgement) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/smart-acknowledgement) |

## How it works

Three steps. Only step 2 uses AI, it can't call any tools, and it writes only one paragraph. Every fact in the message comes from the PSA or your settings, never from the AI.

1. **Read the ticket and plan the acknowledgement (read-only).**
   - **Reads:** the ticket, its contact and its priority. On Autotask and Zendesk, it also reads the contact for their email.
   - **Stops without sending** when the ticket is closed, when it has no contact email (the PSA would email no one), or when it was already acknowledged.
   - **The response target, never a resolution time:**
     - The PSA's own SLA *response* target, when the ticket has one that's still ahead. It's stated as a day and time in your `Ack-TimeZone`.
     - Otherwise, the target for the ticket's priority from `Ack-ResponseTargets`. The defaults are critical 1 hour, high 4 hours, medium 1 business day and low 2 business days.
   - **Knowledge base articles:** published CloudRadial articles from the ticket's own company (the company whose PSA link matches the ticket's) or MSP-wide articles, ranked by words they share with the ticket. Up to eight go to the AI step.
2. **Write the personal paragraph (AI Prompt).**
   - One to three sentences showing the request was understood, plus at most two article ids from the list.
   - The AI is told never to mention a time or promise a fix.
   - No model is pinned, so the tenant's own provider is used.
3. **Send the acknowledgement.**
   - The message is built around the paragraph:
     - a greeting
     - the ticket number and summary
     - the response target
     - the chosen articles, linked through `Ack-ArticleUrlTemplate`
     - "just reply to this email"
   - The paragraph is dropped, and standard wording used, when it mentions any time or day, promises a fix, mentions passwords or codes, or carries a link or address. Article ids that weren't offered are dropped too.
   - **`confirm` false (the default):** nothing is written. The run returns the exact message (`status: pending_confirmation`).
   - **`confirm` true:** the message is posted as a **public note**, so the PSA emails the ticket's contact. Then an internal note records what was stated. Both notes carry markers, so a rerun or a ServiceAI Retry never sends it twice.

The PSA decides who gets a public note's email: the ticket's contact, plus anyone your PSA copies on ticket updates.

### Should you use it with ServiceAI?

ServiceAI already posts a customer auto-response from its Auto-Response Template. Use this workflow when you want something that template can't do:
- the PSA's own SLA response time
- a paragraph about the specific request
- relevant articles from the client's own knowledge base

## Download & import

**Download the workflow:** [`smart-acknowledgement.yml`](https://github.com/cloudradial/Automations/releases/tag/smart-acknowledgement/v1.0.0)

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
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | Optional: `Autotask-NotePublishId`, `Autotask-NotePublicPublishId`, `Autotask-NoteTypeId` |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Optional: `Halo-NoteOutcomeId`, `Halo-PublicNoteOutcomeId` |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId` | |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` (optional) | Reading companies and articles. Read-only. Without them, no articles are offered. |
| `Ack-ArticleUrlTemplate` (optional) | The link to an article in your portal, with `{id}` for the article id, for example `https://support.example-msp.com/app/kb/article/{id}`. Without it, articles are named but not linked. |
| `Ack-MspCompanyId` (optional) | Your own CloudRadial company id, when your MSP-wide articles live under it rather than company 0. |
| `Ack-ResponseTargets` (optional) | Response targets by priority, for example `critical=30 minutes, high=2 hours, medium=1 business day, low=2 business days`. |
| `Ack-TimeZone` (optional) | The time zone for SLA times, for example `Eastern Standard Time` or `America/New_York`. Default UTC. |

**PSA permissions:** the API member or key needs to:
- read tickets, contacts and notes
- add public and internal notes

**CloudRadial keys:** read companies and articles.

## Required Graph permissions

None. This workflow only talks to the PSA and CloudRadial.

## Inputs

| Field | Required | Meaning |
|---|---|---|
| `ticketId` | Yes | The PSA ticket number. Autotask and Kaseya BMS numbers such as `T20261014.0001` and Syncro ticket numbers are looked up to the internal id. |
| `confirm` | No (default `false`) | `true` sends the acknowledgement. `false` returns the message and sends nothing. `approvedToWrite` works too. |
| `includeArticles` | No (default `true`) | `false` leaves articles out. |
| `crCompanyId` | No | The CloudRadial company whose articles to offer, when the ticket's PSA company isn't linked in CloudRadial. |
| `psa` | No | Overrides the `PSA-Type` secret. |

It accepts a flat JSON body, the CloudRadial `{Ticket: {...}, Company: {...}}` shape, or either one wrapped in `{trigger: ...}`. Placeholder values left unfilled (`<ticketId>`, `{{ticketId}}` or a bare `@token`) count as not given.

## Output

| Field | Meaning |
|---|---|
| `status` | `success`, `pending_confirmation`, `incomplete` or `error` |
| `message` | What happened, in a sentence |
| `public_note` | The acknowledgement text |
| `internal_note` | What was stated, and where the response target came from |
| `ticket_id` | The ticket number |
| `counts` | `acknowledgementsSent`, `notesWritten` and `articlesLinked` |
| `actions`, `warnings` | What ran, and anything to check |

## Import & test

1. Import `smart-acknowledgement.yml`, add the secrets above to the runner vault, then **Publish** and **Deploy** to that runner.
2. **Preview first.** Use a test ticket whose contact is your own address, and run the first step's Test Input with its number and `"confirm": false`. Expect `status: pending_confirmation` and the full message in `public_note`. Check the response line and any article links, and that nothing was sent.
3. **Send it.** Run again with `"confirm": true`. Expect one public note (and its email to the contact) and one internal note.
4. **Rerun.** Run once more. Expect "already acknowledged" and nothing sent.
5. **Wire the trigger.** Enable the webhook in **Properties**. AutomationAI issues the URL and secret, and the caller sends the secret in the `X-Crauto-Webhook-Secret` header. Then call it when a ticket is created:
   - from your PSA's ticket-created callback, or
   - from a ServiceAI Action with the body `{"ticketId": "<ticketId>", "confirm": "true"}`.

   If ServiceAI's own auto-response is also on, turn one of them off so clients don't get two acknowledgements.

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. The step logic lives in `src/`: edit `gather.ps1`, `send.ps1` or the `judge.*.txt` prompts, then run `node src/build.js` (it pastes `_shared/psa.ps1`, `psa-tickets.ps1` and `cloudradial.ps1`) and `pwsh -NoProfile -File src/test.ps1`. Never edit the `.yml` by hand.

### Not yet proven live

- **Already proven by the shared library:** reading the ticket and notes, and the public and internal notes.
- **SLA response targets:** they come from `Get-PsaTicketSla` in `_shared/psa-tickets.ps1`. Several of its fields carry `Unverified` comments there.
- **New in this step, not yet proven live:**
  - the Autotask `/Contacts/{id}` and Zendesk `/users/{id}` contact reads (the calls the catalog extensions make)
  - the article link format, which comes from your `Ack-ArticleUrlTemplate`

  Preview against a ticket of your own before turning on `confirm` from a trigger.
