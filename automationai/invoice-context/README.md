# Answer Invoice Questions with the Billing Context Already on the Ticket

When a client questions an invoice, the account manager finds an internal note on the ticket that already shows what was billed, how much time was logged and how much of it was billable, the tickets with the most time, and which agreements covered the period.

**Marketplace ID:** TBD | **Type:** Workflow (PowerShell steps plus one AI Prompt step)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `invoice-context.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/invoice-context/invoice-context.yml) |
| Download `invoice-context.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/invoice-context/invoice-context.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/automationai/invoice-context/src) |
| All files in this automation | [automationai/invoice-context](https://github.com/cloudradial/Automations/tree/main/automationai/invoice-context) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/invoice-context) |

## How it works

Three steps. Only step 2 uses AI, and it can't call any tools. The workflow only reads from the PSA, apart from the one internal note.

1. **Collect billing records (no AI).** Reads the ticket and checks it belongs to the company that was sent. Then it works out the billing period:
   - the `period` input (`2026-09`, `September 2026`, or `2026-09-01..2026-09-30`);
   - otherwise the invoice's own period, looked up by `invoiceNumber` where the PSA can do that (see the table). If the invoice belongs to **another company**, the run stops (`rejected`) and nothing about that invoice is read or posted. If the invoice has no service period, the calendar month before its date is used, with a warning;
   - otherwise last month, with a warning.

   For that company and period it reads the tickets, the time entries and the agreements, and adds them up: hours logged, billable and not billable, hours logged against an agreement, the tickets with the most time (`maxTickets`, default 5), and the agreements in effect. Time-entry notes are never copied anywhere.
2. **Summarize for the account manager (AI Prompt).** One AI call reads only those figures and writes 4 to 8 neutral sentences: what was billed, the time and how much was billable, the biggest tickets, how the agreements relate to the time, and what to check by hand. It is told not to judge whether the invoice is right, not to promise credits, and not to invent figures. No model is pinned, so the tenant's own provider is used.
3. **Post the internal note.** Adds one **internal** (technician-only) note to the ticket with the summary followed by the figures, which are copied from the PSA, never from the AI. If the AI answer is empty or unusable, a plain summary built from the figures is used and the note says so. Nothing is sent to the client and nothing else in the PSA is changed.

| PSA | Tickets | Time entries | Agreements | Invoice lookup by number |
|---|---|---|---|---|
| ConnectWise PSA | Yes | Yes, by company (`/time/entries`) | Yes (`/finance/agreements`) | Yes (`/finance/invoices`); period derived from the invoice date |
| Autotask | Yes | Yes, by ticket (`TimeEntries`) | Yes (`Contracts`) | Yes (`Invoices`), with the invoice's own from and to dates |
| HaloPSA | Yes | Yes, by ticket (actions with time) | Yes (`ClientContract`) | Yes (`Invoice`); period derived from the invoice date |
| Kaseya BMS | Yes | Yes, by ticket (`/timelogs`) | Yes (contracts) | Not supported: send `period` |
| Syncro | Yes | Yes, by ticket (`/ticket_timers`, or labour line items on the ticket) | Yes (contracts) | Not supported: send `period` |
| Zendesk | Yes | Not available (no time-entry API) | Not available | Not supported: send `period` |

Where time is kept per ticket, it is read for the company's tickets opened in the period or in the `lookbackDays` (default 60) before it, up to 50 tickets, with a warning when there are more.

This workflow posts an internal note only. It doesn't email the account manager. Pair it with `deliver-result` if an email is wanted.

### Why a workflow with one AI Prompt step, not an agent

The tracker row suggests an Agent node. This is a PowerShell workflow with a single AI Prompt step instead, because:

- **Reading and adding up billing records is fixed work**, so it runs in PowerShell the same way every time, across all six PSAs (rule 4 in the build rules: fixed rules don't need AI). The figures in the note are exact, not the model's arithmetic.
- **An agent pays one model turn per tool call** and stops at 25 turns; paging through a month of time entries would use most of them. Here the AI gets the totals in one prompt.
- The only judgment needed is a short, neutral write-up, which is what a single AI call does well. The AI step never sees the PSA or any other company's data.
- The note is written by a script step, so a ServiceAI Triage run never waits for approval in the Inbox.

## Download & import

**Download the workflow:** [`invoice-context.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/invoice-context/invoice-context.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required secrets](#required-runner-key-vault-secrets) to the runner, enable the webhook in **Properties** if ServiceAI calls it, then **Publish** and **Deploy**. Full steps are under [Import & test](#import--test).

The workflow reads one PSA (the runner's `PSA-Type`), and only the ticket's own company's records.

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
| `PSA-TicketUrlTemplate` (optional) | The ticket link in the note, with `{id}` for the ticket id. Without it, links are built from the API address (Kaseya BMS gets no link). |

**ServiceAI Secrets manager:** `aai_invoice_dispute_context`, the workflow's webhook secret, sent as `X-Crauto-Webhook-Secret`.

**PSA permissions:** the API member or key needs to read tickets, companies, time entries, agreements (contracts) and invoices, and add notes. In ConnectWise that means the Finance (agreements, invoices) and Time (time entries) inquire rights as well as Service Desk. A missing permission stops the run with a plain message naming the PSA and what to grant, for example `ConnectWise refused to read time entries (HTTP 403). Give the API user permission to read time entries, then run this again.`.

## Required Graph permissions

None. This workflow only talks to the PSA.

## Inputs

| Field | Required | Meaning |
|---|---|---|
| `ticketId` | Yes | The PSA ticket number of the invoice question. Autotask and Kaseya BMS numbers such as `T20261008.0001` and Syncro ticket numbers are looked up to the internal id. |
| `companyName` | Recommended | The company on the ticket, exactly as in the PSA. The run stops (`rejected`) if the ticket belongs to another company. |
| `companyId` | No | The PSA company id. Checked the same way. |
| `invoiceNumber` | No | The invoice in question. Looked up where the PSA supports it, to find the period and show the total. |
| `period` | No | The billing period: `2026-09`, `September 2026`, or `2026-09-01..2026-09-30`. Wins over the invoice's period. Defaults to last month when neither is given. |
| `maxTickets` | No (default 5) | How many top tickets by time to list, 1 to 20. |
| `lookbackDays` | No (default 60) | For PSAs that keep time per ticket: also read time on tickets opened this many days before the period, 0 to 365. |
| `addNote` | No (default `true`) | `false` writes nothing and returns the note as a preview (`status: pending_confirmation`). Use it for dry runs. |
| `psa` | No | Overrides the `PSA-Type` secret. |
| `triggerSource` | No | `serviceai-ai`, `serviceai-triage` or `manual`. Recorded only. |

Placeholder values ServiceAI leaves unfilled (`<invoiceNumber>`, `{{period}}` or a literal `@token`) count as not given.

There is no `confirm` input: the only write is the internal note, which the service-desk rules allow without one. `addNote: false` is the preview.

**ServiceAI Actions** (Settings > Actions). Use in AI and Use in Triage can't share one Action, so make two pointing at the same webhook URL, both with the header `X-Crauto-Webhook-Secret: {{secret.aai_invoice_dispute_context}}`:

| Action | Mode | Body |
|---|---|---|
| **Invoice Dispute Context** | Use in AI | `{"ticketId": "<ticketId>", "companyName": "<companyName>", "invoiceNumber": "<invoiceNumber>", "period": "<period>", "triggerSource": "serviceai-ai"}` |
| **Invoice Dispute Context (Triage)** | Use in Triage | the same body with `"triggerSource": "serviceai-triage"` |

Parameters: `ticketId` and `companyName` (required strings), `invoiceNumber` and `period` (optional strings, for example `2026-09`).

**Triage rule:** *"When a ticket questions or disputes an invoice or charge, call the Invoice Dispute Context action with the ticket number, company, invoice number and billing period if mentioned."*

**Pod Quick Action** (Settings > AI Behavior > Pod Quick Actions): label **Invoice context**, prompt *"Run the Invoice Dispute Context action for this ticket and summarize agreements, time entries and anything that explains the charge."*

## Output

`status` (`success`, `pending_confirmation`, `incomplete`, `rejected` or `error`), `message`, `public_note` (always empty: nothing is posted to the client), `internal_note` (the note text), `ticket_id`, `psa`, `period`, `summary`, `summarized_by` (`ai` or `figures`), `note_written`, `counts`, `actions`, `warnings` and `chatReply`. The first step's output also holds `figures_json`, the exact figures.

ServiceAI's Action Runs **Retry** (or a Routine running again) replays the request and writes nothing twice. The note ends with a marker such as `[invoice context 1001 2026-09-01T00:00:00Z to 2026-10-01T00:00:00Z]` (the ticket, the period and any invoice number). When a note with that marker is already on the ticket, nothing is added, `status` is `success` and `note_written` is `false`. A different period or invoice gets its own note.

## Import & test

1. Import `invoice-context.yml`, add the secrets above to the runner vault, then **Publish** and **Deploy** to that runner.
2. **Preview first.** In **Run**, use the first step's Test Input with a real ticket number, company and `period`, and `"addNote": false`. Expect `status: pending_confirmation`, the figures in the first step's `figures_json`, and the full note in `internal_note`. Nothing is written to the PSA. Check the hours against the PSA's own time report for that company and month.
3. **Invoice.** Try `invoiceNumber` without `period` on ConnectWise, Autotask or HaloPSA, and check the period and total in the note.
4. **Note.** Run again with `addNote` left out (true). Expect one internal note on the ticket and nothing else changed.
5. **Wire the trigger.** Enable the webhook in **Properties** (AutomationAI issues the URL and secret), redeploy, store the secret as `aai_invoice_dispute_context` in the ServiceAI Secrets manager, and create the two Actions, the triage rule and the Quick Action above.

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. The step logic lives in `src/`: edit `gather.ps1`, `note.ps1` or the `summarize.*.txt` prompts, run `node src/build.js` (it pastes `_shared/psa.ps1` and `_shared/psa-tickets.ps1` into the steps), then `pwsh -NoProfile -File src/test.ps1` (strict mode, mocked PSAs). Never edit the `.yml` by hand.

### Not yet proven live

The ticket lists, time entries, agreements and invoices come from the shared `_shared/psa-tickets.ps1`. Calls not yet in `reference/build-kit/PSA.md` carry an `Unverified` or `Vendor docs` comment there saying what to check, notably the ConnectWise `billableOption` values, Autotask `TimeEntries` by ticket, the HaloPSA action time fields and invoice search, and every Kaseya BMS and Syncro time and contract call. The AI Prompt step's property names (`promptTemplate`, `systemMessage`, `maxTokens`, `outputKey`) follow the Phishing Report Triage workflow and are also unverified.
