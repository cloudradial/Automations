# Split Request — Service + Quote

Turns one intake — a CloudRadial form submission or a ticket being triaged in ServiceAI — into a **service ticket** for the work and, when something has to be bought, a linked **quote request**. A classifier agent grounded on your **Knowledge** writes both tickets to your own service-desk and quoting standards.

## Pieces

| File | Type | Role |
|---|---|---|
| [`split-request-service-quote.yml`](split-request-service-quote.yml) | `automationsWorkflow` | **Use this one.** Two nodes: *Classify the request* (agent) → *Split into service + quote tickets* (PowerShell, creates the ConnectWise tickets, notes, and closes a ServiceAI source ticket). |
| [`split-request-classifier.agent.yml`](split-request-classifier.agent.yml) | `automationsAgent` | The classifier (slug `split-request-classifier`, v0.2.0). Decides buy vs do, writes both tickets to your standards, lists missing information, cites the standards it used. Calls no PSA tools. |
| [`knowledge/service-ticket-standards.md`](knowledge/service-ticket-standards.md) | Knowledge | Summary patterns, description layout, priority, type and subtype. |
| [`knowledge/quote-request-standards.md`](knowledge/quote-request-standards.md) | Knowledge | What counts as a purchase, quote summary and layout, required information. |
| [`knowledge/standard-catalog.md`](knowledge/standard-catalog.md) | Knowledge | Standard hardware, peripherals, phones and licences; role defaults; items that need approval. |
| [`split-request-two-tickets.yml`](split-request-two-tickets.yml) | `automationsWorkflow` | *Legacy:* Split Request — Support + Quote (new user + new PC only). Superseded by the Service + Quote workflow; see the end of this page. |

## How the pieces share the work

| Decision | Made by |
|---|---|
| **Whether** a quote is raised (structured form) | The form-profile table in the PowerShell node — deterministic. If the classifier disagrees, the table wins and the run is flagged for review. |
| **Whether** a quote is raised (free-text ServiceAI ticket) | The classifier. |
| **How** both tickets read — titles, descriptions, priority, type, subtype | The classifier, following your Knowledge documents. |
| Company lookup, ticket creation, notes, closing the source ticket | The PowerShell node only. |

If the classifier's output is missing, below the confidence threshold (0.6 by default), or flags more than one request, the tickets fall back to the **built-in templates** in the script. Knowledge makes the tickets better; the workflow never depends on it to run.

## Install / run

1. **Classifier agent.** Upload `split-request-classifier.agent.yml` on **Agents → Custom** (keyed on the slug, so it replaces v0.1.0).
2. **Knowledge.** Edit the three files in `knowledge/` to your own standards (keep the headings — the agent searches by them), then upload them to a Knowledge folder such as **Ticket Standards**.
3. **Workflow.** **Workflows → Import** `split-request-service-quote.yml`, then publish and deploy to the runner that holds the `CW-*` secrets.
4. **Turn on grounding.** Open the **Classify the request** node → **Ground on knowledge** → attach the three documents (or the folder). Set **topK to about 12**, so all the relevant sections come back in one recall. Use **Preview recall** to check that the summary-format, priority and catalog sections appear. Grounding can't be exported (it points at your tenant's document IDs), so every install does this step.
5. **Key Vault secrets:** `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId`, `CW-ServiceBoard`, `CW-SalesBoard`; optional `PSA-SplitStatus` (ServiceAI path) and `CloudRadial-BaseUrl` / `-PublicKey` / `-PrivateKey` (only to resolve a CloudRadial `companyId`).
6. **Form profiles.** In the PowerShell node, edit `$FormProfiles` so `Fields` matches the question IDs on your forms. On the stock *Add a New User* form, give the computer question a Field ID of `deviceType` or the hardware detail won't reach the quote.
7. **Enable the webhook** (Properties → Webhook → Enable — exports ship with it OFF) and point your form's Automation at it, sending the secret in the `X-Crauto-Webhook-Secret` header. For ServiceAI, send `source: serviceai` and `psaTicketId`.

## Writing good Knowledge for this agent

- **One rule per section, titled with the question it answers** ("Service ticket priority", "What counts as a purchase"). Recall returns sections, not whole documents.
- **Tables over prose.** Exact names in tables (priority names, types, catalog items) are copied verbatim into the tickets, so spell them exactly as they appear in ConnectWise.
- **Keep the three documents short.** Recall brings back the best-matching sections for the node's goal, and the goal names each section the agent needs. A long document spreads the rules across more sections than topK returns.
- Priority, type and subtype names that don't exist on the board make ConnectWise reject the ticket. The workflow then retries without them and adds a warning, so check the run's `warnings` after changing them.

## What lands on the tickets

- **Service ticket:** the classifier's summary and description (or the built-in template), with priority, type and subtype when your standards define them.
- **Quote request:** the classifier's summary and description, plus **"Still needed before this can be quoted"** listing anything your standards require that the request didn't give, and a link to the service ticket.
- **Internal note on every ticket:** the split, the classifier's confidence and reasoning, **who wrote the ticket text** (classifier with knowledge / mixed / default standards, or built-in templates), the standards applied, missing information, and a **REVIEW REQUIRED** line when a human needs to look.
- **Run output** adds `formattedBy`, `standardsSource`, `standardsApplied` and `missingInfo` to the existing ticket ids, `reviewRequired` and `warnings`.

## Confirm in your tenant

- **Knowledge recall works.** Upload one document and use the node's **Preview recall**. As of 2026-09-24, the only document in Nick's Test showed `embeddingStatus: failed` and recall returned HTTP 500 — re-test with a fresh upload before relying on grounding.
- **ConnectWise names match** the priority, type and subtype tables in `service-ticket-standards.md`.
- The classifier has `dryRunDefault: false` — it only reads and returns text, so there's nothing to preview.
- Only ConnectWise Manage is implemented in the PowerShell node; HaloPSA and Autotask are stubs.

## Tested (mocked ConnectWise, 2026-09-25)

| Case | Result |
|---|---|
| New-user form + classifier with Knowledge | Classifier's titles, descriptions, priority, type and subtype used; missing delivery location listed on the quote |
| ConnectWise rejects the priority name | Ticket retried without priority/type/subtype; warning returned |
| Classifier says nothing to buy, form says laptop | Quote raised from the form; run flagged REVIEW REQUIRED |
| Classifier confidence 0.4 | Built-in templates used; no standards claimed in the note |
| Free-text ServiceAI ticket | Both tickets from the classifier, each noting the source ticket; source ticket left open (no split status set) |

---

## Legacy: Split Request — Support + Quote

`split-request-two-tickets.yml` creates two linked ConnectWise tickets from the *Add a New User* form only (new user + new PC). It reads the form's Field IDs directly (`firstName`, `lastName`, `department`, `jobTitle`, `email`, `softwareLicenses`, `companyFileAccess`, and `deviceType` if you add it) and needs the same `CW-*` board secrets. Keep it only if you already run it; new installs should use the Service + Quote workflow above.
