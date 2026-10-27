# Turn One Request into a Service Ticket and a Quote

When a client asks for something that needs both work and a purchase, like a new starter who needs a laptop, your team gets two linked tickets, both written to your own standards.

## What your clients see in the portal

**Nothing changes for them.** They fill in one request form as usual, for example **Add a New User**, and submit it once.
**What your team gets.** A service ticket for the work, and a quote request linked to it when something has to be bought. If nothing needs buying, only the service ticket is made. The quote request lists anything your quoting standards need that the client didn't give, under "Still needed before this can be quoted".

It also works on tickets being triaged in ServiceAI.

## What happens behind the scenes

- **An AI agent reads the request** and writes both tickets the way your team does, from three short standards documents you keep in AutomationAI Knowledge (service tickets, quote requests and your standard catalog).
- **For your forms, a fixed rule decides whether a quote is needed.** If the AI disagrees, the rule wins and the tickets are flagged for review.
- **If the AI isn't sure, or gives no answer,** the tickets use simple built-in templates, so the request is never lost.
- **Every ticket gets an internal note** saying how it was split, what's missing, and "REVIEW REQUIRED" when a person needs to look.
- **If the quote request fails,** the service ticket is kept and flagged so your team can raise the quote by hand.

## Works with

ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk.

- **ConnectWise PSA:** the PSA it has been run against. Set a service board for the service ticket and one for the quote (the quote goes to a service board too).
- **Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk:** supported, but not yet proven in a live run. Watch your first run.
- **Ticket type and subtype:** ConnectWise only. Other PSAs get the priority as a level (critical, high, medium or low).

## What you need

- AutomationAI, with your PSA connected
- The board or queue each ticket should go to (PSAs other than ConnectWise use their default queue if you don't set one)
- AutomationAI Knowledge for your standards (recommended: the tickets still work without it, but read better with it)
- A UCP portal request form, or ServiceAI, to start it

## Set it up

**In AutomationAI:**

1. **Download** the [files](https://github.com/cloudradial/Automations/releases/tag/split-request-two-tickets/v1.1.0).
2. Import the **Split Request Classifier** agent first, on **Agents > Custom > Import**. The workflow can't find it otherwise.
3. Edit the three standards documents to match how your team works (keep their headings), then upload them to a **Knowledge** folder such as **Ticket Standards**.
4. Go to **Workflows > Import** and upload the **Split Request - Service + Quote** workflow.
5. Open the **Classify the request** step, choose **Ground on knowledge**, and attach the three documents. Use **Preview recall** to check your sections come back.
6. Add your PSA connection details, and the board or queue for the service ticket and for the quote.
7. In the ticket step, match the list of form questions to your own forms. On the stock **Add a New User** form, set the computer question's Field ID to `deviceType`, or the hardware won't reach the quote.
8. In **Properties**, turn on the webhook. Then click **Publish**, then **Deploy**.

**In your UCP portal:** point the request form's automation at the workflow's webhook address, with its secret.

**Test it.** Run it once with **Test draft** against a test company (it creates real tickets), then check your PSA for a service ticket, a quote request and a note on each.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/split-request-two-tickets#technical-details) cover how the pieces share the work, writing good Knowledge and the ServiceAI setup.

---

## Technical details

**Formerly:** Split Request, Service + Quote | **Marketplace ID:** AAI-00034 | **Type:** Workflow + Agent | **Version:** 1.1.0

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/split-request-two-tickets/v1.1.0).

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **Split Request Classifier** agent, [`split-request-classifier.agent.yml`](https://github.com/cloudradial/Automations/blob/main/split-request-two-tickets/split-request-classifier.agent.yml), on **Agents → Custom → Import**.
2. Import [`split-request-service-quote.yml`](https://github.com/cloudradial/Automations/blob/main/split-request-two-tickets/split-request-service-quote.yml) on **Workflows → Import**.

**Optional:** [`split-request-two-tickets.yml`](https://github.com/cloudradial/Automations/blob/main/split-request-two-tickets/split-request-two-tickets.yml) on **Workflows → Import**, with no agent needed. See How it works for when to use it.

| What | Link |
|---|---|
| View `split-request-service-quote.yml` (start here) | [GitHub](https://github.com/cloudradial/Automations/blob/main/split-request-two-tickets/split-request-service-quote.yml) |
| Download `split-request-service-quote.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/split-request-two-tickets/v1.1.0) |
| View `split-request-classifier.agent.yml` (agent) | [GitHub](https://github.com/cloudradial/Automations/blob/main/split-request-two-tickets/split-request-classifier.agent.yml) |
| Download `split-request-classifier.agent.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/split-request-two-tickets/v1.1.0) |
| View `split-request-two-tickets.yml` (optional) | [GitHub](https://github.com/cloudradial/Automations/blob/main/split-request-two-tickets/split-request-two-tickets.yml) |
| Download `split-request-two-tickets.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/split-request-two-tickets/v1.1.0) |
| View `knowledge/quote-request-standards.md` (upload to Knowledge) | [GitHub](https://github.com/cloudradial/Automations/blob/main/split-request-two-tickets/knowledge/quote-request-standards.md) |
| Download `knowledge/quote-request-standards.md` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/split-request-two-tickets/knowledge/quote-request-standards.md) |
| View `knowledge/service-ticket-standards.md` (upload to Knowledge) | [GitHub](https://github.com/cloudradial/Automations/blob/main/split-request-two-tickets/knowledge/service-ticket-standards.md) |
| Download `knowledge/service-ticket-standards.md` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/split-request-two-tickets/knowledge/service-ticket-standards.md) |
| View `knowledge/standard-catalog.md` (upload to Knowledge) | [GitHub](https://github.com/cloudradial/Automations/blob/main/split-request-two-tickets/knowledge/standard-catalog.md) |
| Download `knowledge/standard-catalog.md` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/split-request-two-tickets/knowledge/standard-catalog.md) |
| All files in this automation | [split-request-two-tickets](https://github.com/cloudradial/Automations/tree/main/split-request-two-tickets) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/split-request-two-tickets) |

## How it works

Turns one intake, a CloudRadial form submission or a ticket being triaged in ServiceAI, into a **service ticket** for the work and, when something has to be bought, a linked **quote request**. A classifier agent grounded on your **Knowledge** writes both tickets to your own service-desk and quoting standards.

## Pieces

| File | Type | Role |
|---|---|---|
| [`split-request-service-quote.yml`](https://github.com/cloudradial/Automations/blob/main/split-request-two-tickets/split-request-service-quote.yml) | `automationsWorkflow` | **Use this one.** Two nodes: *Classify the request* (agent) → *Split into service + quote tickets* (PowerShell, creates the tickets in ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro or Zendesk through the shared PSA library, notes them, and closes a ServiceAI source ticket). |
| [`split-request-classifier.agent.yml`](https://github.com/cloudradial/Automations/blob/main/split-request-two-tickets/split-request-classifier.agent.yml) | `automationsAgent` | The classifier (slug `split-request-classifier`, v0.2.2). Decides buy vs do, writes both tickets to your standards, lists missing information, cites the standards it used. Calls no PSA tools. |
| [`knowledge/service-ticket-standards.md`](https://github.com/cloudradial/Automations/blob/main/split-request-two-tickets/knowledge/service-ticket-standards.md) | Knowledge | Summary patterns, description layout, priority, type and subtype. |
| [`knowledge/quote-request-standards.md`](https://github.com/cloudradial/Automations/blob/main/split-request-two-tickets/knowledge/quote-request-standards.md) | Knowledge | What counts as a purchase, quote summary and layout, required information. |
| [`knowledge/standard-catalog.md`](https://github.com/cloudradial/Automations/blob/main/split-request-two-tickets/knowledge/standard-catalog.md) | Knowledge | Standard hardware, peripherals, phones and licences; role defaults; items that need approval. |
| [`src/test.ps1`](https://github.com/cloudradial/Automations/blob/main/split-request-two-tickets/src/test.ps1) | Test | Strict-mode harness for the PowerShell node (mocked ConnectWise and Zendesk). Not imported. |
| [`split-request-two-tickets.yml`](https://github.com/cloudradial/Automations/blob/main/split-request-two-tickets/split-request-two-tickets.yml) | `automationsWorkflow` | *Legacy:* Split Request - Support + Quote (new user + new PC only). Superseded by the Service + Quote workflow; see the end of this page. |

## How the pieces share the work

| Decision | Made by |
|---|---|
| **Whether** a quote is raised (structured form) | The form-profile table in the PowerShell node, deterministic. If the classifier disagrees, the table wins and the run is flagged for review. |
| **Whether** a quote is raised (free-text ServiceAI ticket) | The classifier. |
| **How** both tickets read, titles, descriptions, priority, type, subtype | The classifier, following your Knowledge documents. |
| Company lookup, ticket creation, notes, closing the source ticket | The PowerShell node only. |

If the classifier's output is missing, below the confidence threshold (0.6 by default), or flags more than one request, the tickets fall back to the **built-in templates** in the script. Knowledge makes the tickets better; the workflow never depends on it to run.

## Install / run

1. **Classifier agent.** Upload `split-request-classifier.agent.yml` on **Agents → Custom** (keyed on the slug, so it replaces an earlier version).
2. **Knowledge.** Edit the three files in `knowledge/` to your own standards (keep the headings, because the agent searches by them), then upload them to a Knowledge folder such as **Ticket Standards**.
3. **Workflow.** **Workflows → Import** `split-request-service-quote.yml`, then publish and deploy to the runner that holds your PSA secrets.
4. **Turn on grounding.** Open the **Classify the request** node → **Ground on knowledge** → attach the three documents (or the folder). Set **topK to about 12**, so all the relevant sections come back in one recall. Use **Preview recall** to check that the summary-format, priority and catalog sections appear. Grounding can't be exported (it points at your tenant's document IDs), so every install does this step.
5. **Key Vault secrets:**
   - `PSA-Type` and your PSA's own secrets, with the same names as its catalog extension (ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId`).
   - `PSA-ServiceQueue` and `PSA-QuoteQueue`: the board or queue for each ticket. ConnectWise also reads `CW-ServiceBoard` and `CW-SalesBoard`, and needs both. On ConnectWise the quote board is any service board, because Opportunities are not boards. Other PSAs use their default queue when none is set.
   - Optional: `PSA-SplitStatus` (ServiceAI path), and `CloudRadial-BaseUrl` / `-PublicKey` / `-PrivateKey` (only to resolve a CloudRadial `companyId`).
6. **Form profiles.** In the PowerShell node, edit `$FormProfiles` so `Fields` matches the question IDs on your forms. On the stock *Add a New User* form, give the computer question a Field ID of `deviceType` or the hardware detail won't reach the quote.
7. **Enable the webhook** (Properties → Webhook → Enable, exports ship with it OFF) and point your form's Automation at it, sending the secret in the `X-Crauto-Webhook-Secret` header. For ServiceAI, send `source: serviceai` and `psaTicketId`.

## How the nodes are wired

- **The classifier reads the intake from its goal.** The goal ends with `{{ nodes.trigger.output }}`. Without it the agent gets nothing to classify, says the request "was not provided", and every run falls back to the templates.
- **The ticket step reads two parameters:** `intake` = `{{ nodes.trigger.output }}` (the original form or ticket) and `classification` = `{{ nodes.node-classify.output }}`. Older copies passed only the classifier's output and relied on it echoing the intake under `payload`, which still works but no longer has to.
- **The classifier's `allowedExtensions` is never empty.** An empty list now hands the agent every installed extension (925 tools in Nick's Test on 2026-10-14), and the model refuses more than 128. It lists `cloudradial-v2-companies`, which the workflow needs anyway. The agent calls no tools.
- **ConnectWise redirects are handled.** ConnectWise staging has answered ticket creates with a redirect after making the ticket. The shared library finds that ticket instead of creating a second one, and says so in `warnings`.

## Writing good Knowledge for this agent

- **One rule per section, titled with the question it answers** ("Service ticket priority", "What counts as a purchase"). Recall returns sections, not whole documents.
- **Tables over prose.** Exact names in tables (priority names, types, catalog items) are copied verbatim into the tickets, so spell them exactly as they appear in your PSA.
- **Keep the three documents short.** Recall brings back the best-matching sections for the node's goal, and the goal names each section the agent needs. A long document spreads the rules across more sections than topK returns.
- On ConnectWise, priority, type and subtype names that don't exist on the board make ConnectWise reject the ticket. The workflow then retries without them and adds a warning, so check the run's `warnings` after changing them. Other PSAs get the priority as a level (critical, high, medium or low) read from its name; type and subtype are ConnectWise only.

## What lands on the tickets

- **Service ticket:** the classifier's summary and description (or the built-in template), with priority, type and subtype when your standards define them.
- **Quote request:** the classifier's summary and description, plus **"Still needed before this can be quoted"** listing anything your standards require that the request didn't give, and a link to the service ticket.
- **Internal note on every ticket:** the split, the classifier's confidence and reasoning, **who wrote the ticket text** (classifier with knowledge / mixed / default standards, or built-in templates), the standards applied, missing information, and a **REVIEW REQUIRED** line when a human needs to look.
- **Run output** adds `formattedBy`, `standardsSource`, `standardsApplied` and `missingInfo` to the existing ticket ids, `reviewRequired` and `warnings`.

## Confirm in your tenant

- **Knowledge recall works.** Upload one document and use the node's **Preview recall**. As of 2026-09-24, the only document in Nick's Test showed `embeddingStatus: failed` and recall returned HTTP 500, re-test with a fresh upload before relying on grounding.
- **ConnectWise names match** the priority, type and subtype tables in `service-ticket-standards.md`.
- The classifier has `dryRunDefault: false`, it only reads and returns text, so there's nothing to preview.
- **Your PSA.** ConnectWise is the PSA this has been run against. The other five go through the shared PSA library, and calls marked Unverified there need one supervised run first.

## Test it

Run it once from the designer (**Test draft**) against a test company. It creates real tickets. The trigger input has the shape the classifier expects:

```json
{
  "subject": "Add a New User: Alex Example",
  "formName": "Add a New User",
  "body": "New user Alex Example, Accountant in Finance, starting 2026-10-20. Needs a laptop with a docking station and a Microsoft 365 Business Premium licence.",
  "payload": {
    "company": "42",
    "formName": "Add a New User",
    "userName": "Alex Example",
    "email": "alex.example@contoso.com",
    "jobTitle": "Accountant",
    "department": "Finance",
    "startDate": "2026-10-20",
    "deviceType": "Laptop with docking station",
    "softwareLicenses": "Microsoft 365 Business Premium"
  }
}
```

`company` is the PSA company id, a ConnectWise identifier, or the exact company name. Expect a service ticket and a quote ticket, an internal note on each, and `status: success`. For the PowerShell node alone, run `pwsh -NoProfile -File split-request-two-tickets/src/test.ps1`.

## Tested (strict-mode harness, 2026-10-14)

`src/test.ps1`, 29 checks:

| Case | Result |
|---|---|
| ConnectWise, intake and classification as parameters | Both tickets on the right boards, with the classifier's text, priority, type and subtype, and an internal note on each |
| ConnectWise rejects the priority name | Ticket made again without priority, type and subtype; warning returned |
| ConnectWise makes the ticket, then answers with a redirect | Ticket found by search, never created twice; warning returned |
| Older wiring (intake echoed under `payload`) | Still works |
| No intake reached the step | Fails before creating anything, and says to bind `intake` |
| The quote ticket fails | Service ticket kept and noted, run flagged REVIEW REQUIRED, "raise it by hand" warning |
| No ConnectWise service board set | Refuses before creating anything |
| `PSA-ServiceQueue` / `PSA-QuoteQueue` set | Used ahead of the `CW-*` board secrets |
| Source ticket with a split status | Noted and set to that status |
| Zendesk | Both tickets for the organization, priority sent as a level, internal notes |

## Tested (mocked ConnectWise, 2026-09-25)

| Case | Result |
|---|---|
| New-user form + classifier with Knowledge | Classifier's titles, descriptions, priority, type and subtype used; missing delivery location listed on the quote |
| ConnectWise rejects the priority name | Ticket retried without priority/type/subtype; warning returned |
| Classifier says nothing to buy, form says laptop | Quote raised from the form; run flagged REVIEW REQUIRED |
| Classifier confidence 0.4 | Built-in templates used; no standards claimed in the note |
| Free-text ServiceAI ticket | Both tickets from the classifier, each noting the source ticket; source ticket left open (no split status set) |

---

## Legacy: Split Request, Support + Quote

`split-request-two-tickets.yml` creates two linked ConnectWise tickets from the *Add a New User* form only (new user + new PC). It reads the form's Field IDs directly (`firstName`, `lastName`, `department`, `jobTitle`, `email`, `softwareLicenses`, `companyFileAccess`, and `deviceType` if you add it) and needs the same `CW-*` board secrets. Keep it only if you already run it; new installs should use the Service + Quote workflow above.
