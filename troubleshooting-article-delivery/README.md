# Send the Right Fix-It Article the Moment a Ticket Arrives

When a new ticket matches one of your knowledge base articles, your client gets that article right away. If it solves the problem and they reply "fixed", the ticket closes on its own, with no technician needed.

## What happens

**A ticket comes in.** ServiceAI triage spots that it matches a published article in your knowledge base. Your client gets an email update on the ticket with the article's title and link, plus "Reply 'fixed' and we'll close this ticket. If it doesn't help, just reply and a technician will carry on."

**The client replies.** A clear "Fixed, thanks!" closes the ticket and adds a short note saying they can reply if the problem comes back. Anything less clear, such as "Still not working" or "It works now but Outlook is slow", leaves the ticket open for your team.

**Your team always sees what happened.** Each decision, including when it chose not to send anything, is written as an internal note on the ticket, along with why.

## What it protects

- **Only confident matches go out.** If triage isn't sure enough about the article, nothing is sent.
- **Clients only see their own articles.** The article must come from that client's own knowledge base or be one you share with every client. Another client's article is never sent.
- **Only published articles.** Drafts and articles scheduled for later are never sent.
- **No double emails.** If triage runs again on the same ticket, the client doesn't get the article twice.
- **Careful closing.** Only a short, clear "it's fixed" from the person the article went to closes a ticket. Questions, "but", "still" or "not" keep it open.

## Works with

ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk.

- **Replies:** not yet confirmed live. Closing depends on ServiceAI triage running when a client replies, not only on new tickets.
- **Autotask and HaloPSA:** some of the note and closing steps have not been tested live yet.

## What you need

- A CloudRadial knowledge base with published articles
- ServiceAI, with triage turned on
- AutomationAI, with your PSA and CloudRadial connected

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/troubleshooting-article-delivery/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. Turn on the webhook in **Properties**, then click **Publish** and **Deploy**.

**In ServiceAI (Settings > Actions):**

1. Save the workflow's webhook secret in the ServiceAI **Secrets** manager.
2. Create an Action called **Send Troubleshooting Article**, set to **Use in Triage**, pointing at the workflow's webhook address.
3. Add a triage rule in plain words: "When a new ticket matches a knowledge base article with high confidence, call the Send Troubleshooting Article action."
4. Create a second Action, **Troubleshooting Article Reply**, also **Use in Triage**, with a rule that calls it when a client replies to a ticket that got an article.

You can turn off automatic closing so a technician gets a note instead, or change how confident a match must be before it's sent.

**Test it.** Open a test ticket that matches a published article, check the client gets the link, then reply "Fixed, thanks" and check the ticket closes.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/troubleshooting-article-delivery#technical-details) cover every check, what counts as "fixed", the exact Action setup, and what is still being tested.

---

## Technical details

**Marketplace ID:** AAI-00053 | **Type:** Workflow (PowerShell steps, no AI) | **Version:** 1.0.0

## Files

Each version is published as a release, with `troubleshooting-article-delivery.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/troubleshooting-article-delivery/v1.0.0).

| What | Link |
|---|---|
| Download `troubleshooting-article-delivery.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/troubleshooting-article-delivery/v1.0.0) |
| View the current source | [`troubleshooting-article-delivery.yml`](https://github.com/cloudradial/Automations/blob/main/troubleshooting-article-delivery/troubleshooting-article-delivery.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/troubleshooting-article-delivery/src) |
| All files in this automation | [troubleshooting-article-delivery](https://github.com/cloudradial/Automations/tree/main/troubleshooting-article-delivery) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/troubleshooting-article-delivery) |

## How it works

Three PowerShell steps, no AI. The judgment (which article fits the ticket) is ServiceAI triage's, and it sends its confidence; this workflow checks that judgment against CloudRadial before anything reaches the client. One webhook, two entry points.

1. **Read the request.** Reads `mode` (`send`, the default, or `reply`), `ticketId`, and for `send`: `contactEmail`, `articleTitle`, `articleUrl` (must be `https://`) and `confidence` (0 to 1; `90`, `"90%"` and `0.9` all mean 0.9). For `reply`: `replyText`. Accepts a flat body, the CloudRadial `{Ticket:{Questions}, Company}` shape, or either one wrapped in `{trigger: ...}`. A literal `@token`, `{{placeholder}}` or `<placeholder>` counts as not given.
2. **Check the ticket and the article.** Reads only. In `send` mode, in this order:
   1. The confidence must be at least `min_confidence` (default 0.75).
   2. The ticket must exist in the PSA and be open.
   3. The ticket's company must map to one CloudRadial company (the company whose PSA link, `psaKey`, is the ticket's company), or `companyId` names it.
   4. The article must exist in CloudRadial: found by the id in the link (`/kb/article/321`, `?articleId=321`) or, without one, by its exact title. It must belong to **that company's knowledge base or be MSP-wide** (company 0, or `mspCompanyId`). An article from another client's knowledge base is never sent, and the note never names that client.
   5. It must be **published**: a publish date that isn't in the future.
   6. The link must point at that article: the id in the link matches the title, or (for a title match) the link is the article's own URL, contains its id, or is on a CloudRadial host or one in `allowedLinkHosts`.
   7. The contact must not be a portal user of a different company.
   8. The article must not already have been sent on this ticket. ServiceAI **Retry** replays the request, so a repeat is quiet.

   In `reply` mode it checks that this workflow sent an article on the ticket (the marker in its internal note), that the reply came from that contact when `replyFrom` is sent, and that the reply **clearly says it's fixed**.
3. **Send or close, and note it.**
   - **Send:** a **public note** on the ticket, so the PSA emails the contact: a short greeting, the article title and link, and "Reply 'fixed' and we'll close this ticket. If it doesn't help, just reply and a technician will carry on." Then an internal note with the confidence, the checks, and a marker line that reply mode looks for.
   - **Retry guard:** every note this workflow writes carries a marker: internal notes end with it in brackets (for example `[AAI-TA sent 321]`), and the public note the contact sees ends with only an opaque `Ref: 1a2b3c4d` line, so no internal tag reaches the client. Before writing, it looks for that marker on the ticket, so a ServiceAI **Retry** never writes the same note twice, even when the first run stopped between the public and the internal note. A different reply from the contact gets its own note.
   - **Close (reply mode, clear yes):** closes the ticket through the shared six-PSA adapter (ConnectWise closed status, Autotask Complete, HaloPSA Closed, Kaseya BMS closed status id, Syncro Resolved, Zendesk solved), adds a short public note ("Reply here if the problem comes back"), and an internal note.
   - **Anything else** (low confidence, wrong company, unpublished, unclear reply, no article sent): no client-facing change, and an **internal note saying what was decided and why**. Only true repeats (already sent, already closed) and an unknown ticket write nothing.

**What counts as "fixed".** Conservative on purpose. Quoted email history and signatures are ignored. The reply must be 160 characters or less, ask no question, and contain a clear yes (`fixed`, `resolved`, `works now`, `working now`, `that worked`, `all good`, `all set`, `sorted`, `solved`, `did the trick`, `you can close`, and similar), with no negation or hedge (`not`, `no`, `still`, `but`, `again`, `sometimes`, `isn't`, `didn't`, `maybe`, and similar). "Fixed, thanks!" closes. "Still not working", "fixed?", "It works now but Outlook is slow" and "no longer an issue" all leave the ticket open with a note.

**No confirm step, on purpose.** A triage run has no technician. Sending the article is a public note, and closing is a status change made only after the client's own clear yes on a ticket this workflow sent the article to, so neither needs a preview. `autoClose: false` turns the close off (the technician gets a note instead). `dry_run: true` runs every check and returns the notes it would write, writing nothing.

## Download & import

**Download the workflow:** [`troubleshooting-article-delivery.yml`](https://github.com/cloudradial/Automations/releases/tag/troubleshooting-article-delivery/v1.0.0)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required secrets](#required-runner-key-vault-secrets) to the MSP's runner, enable the webhook in **Properties**, then **Publish** and **Deploy**. Full steps are under [Import & test](#import--test).

It runs with the MSP's PSA and CloudRadial keys, and every check keeps it to the ticket's own company: the article, the contact and the notes all belong to that one client.

## Required runner Key Vault secrets

By name only. Use the same names as the catalog extensions, so one set serves both.

| Secret | For |
|---|---|
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Reading companies, articles and portal users. Read-only. |
| `PSA-Type` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` (a `psa` input overrides it). Required. |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | Optional: `Autotask-NotePublishId`, `Autotask-NotePublicPublishId`, `Autotask-NoteTypeId` |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Optional: `Halo-NoteOutcomeId`, `Halo-PublicNoteOutcomeId`, `Halo-ClosedStatusId` |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId`, `KaseyaBMS-ClosedStatusId` | |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | |

**ServiceAI Secrets manager:** `aai_send_troubleshooting_article`, the workflow's webhook secret, sent as `X-Crauto-Webhook-Secret: {{secret.aai_send_troubleshooting_article}}`.

## Required Graph permissions

None. This workflow doesn't call Microsoft Graph. The CloudRadial API keys need read access to companies, articles and users, and the PSA account needs to read tickets and notes, add public and internal notes, and change ticket status. A key without access stops the run with the CloudRadial or PSA error (for example `HTTP 403`) before anything is sent.

## Inputs

| Field | Required | Meaning |
|---|---|---|
| `mode` | No (default `send`) | `send` delivers the article. `reply` checks a customer reply and closes on a clear yes. |
| `ticketId` | Yes | The PSA ticket number. |
| `contactEmail` | Yes for `send` | The ticket contact. Used for the greeting, the company check and the reply check. |
| `articleTitle` | Yes for `send` | The title of the matched CloudRadial article. |
| `articleUrl` | Yes for `send` | The `https://` link to the article. |
| `confidence` | Yes for `send` | The triage match confidence, 0 to 1. |
| `min_confidence` | No (default `0.75`) | Below this, nothing is sent. |
| `replyText` | Yes for `reply` | The customer's reply. |
| `replyFrom` | No | Who sent the reply. When given, it must be the contact the article went to. |
| `autoClose` | No (default `true`) | `false` notes a confirmed fix for a technician instead of closing. |
| `companyId` | No | The CloudRadial company id, when the ticket's PSA company isn't linked in CloudRadial. |
| `mspCompanyId` | No | The CloudRadial company that holds MSP-wide articles, if not company 0. |
| `allowedLinkHosts` | No | Extra hosts (comma-separated) an article link may use when it has no article id, for example your custom portal domain. |
| `dry_run` | No (default `false`) | `true` runs every check and writes nothing. |
| `psa` | No | Overrides the `PSA-Type` secret. |

**ServiceAI Action "Send Troubleshooting Article"** (Settings > Actions, **Use in Triage**, POST to the workflow's webhook URL, headers `Content-Type: application/json` and `X-Crauto-Webhook-Secret: {{secret.aai_send_troubleshooting_article}}`). Parameters: `ticketId`, `contactEmail`, `articleTitle`, `articleUrl` (required strings) and `confidence` (required number). Body:

```json
{
  "ticketId": "<ticketId>",
  "contactEmail": "<contactEmail>",
  "articleTitle": "<articleTitle>",
  "articleUrl": "<articleUrl>",
  "confidence": 0.9,
  "triggerSource": "serviceai-triage"
}
```

**Triage rule:** "When a new ticket matches a knowledge base article with high confidence and the customer auto-response did not already include it, call the **Send Troubleshooting Article** action with the ticket number, contact email, article title, link and confidence."

**Second Action for replies, "Troubleshooting Article Reply"** (Use in Triage, same URL and secret header). Body:

```json
{
  "mode": "reply",
  "ticketId": "<ticketId>",
  "replyText": "<the customer's latest reply>",
  "replyFrom": "<the reply sender's email>",
  "triggerSource": "serviceai-triage"
}
```

**Triage rule:** "When a customer replies to a ticket that has a note starting 'Troubleshooting article sent', call the **Troubleshooting Article Reply** action with the ticket number, the reply text and the sender's email." The workflow does its own strict check, so the rule can be broad.

## Output

`status` (`success`, `rejected`, `incomplete`, `error`, or `pending_confirmation` for a dry run), `message`, `chatReply`, `public_note`, `internal_note`, `ticket_id`, `mode`, `decision` (`send`, `close`, `low-confidence`, `wrong-company`, `unpublished`, `link-mismatch`, `link-unverified`, `no-article`, `wrong-contact`, `no-company`, `no-ticket`, `ticket-closed`, `already-sent`, `not-clear`, `no-article-sent`, `not-the-contact`, `fixed-no-autoclose`, `already-closed`, `cannot-confirm`), `reason`, `dry_run`, `confidence`, `min_confidence`, `article`, `company`, `sent`, `closed`, `note_written`, `received_keys`, `actions` and `warnings`.

## Import & test

1. Import `troubleshooting-article-delivery.yml`, add the secrets above to the MSP's runner vault, then **Publish** and **Deploy** to that runner.
2. **Dry run first.** In **Run**, use the first step's Test Input with a real open test ticket, its contact, and a published article from that company's knowledge base. Expect `status: pending_confirmation`, `decision: send`, and the public note text in `public_note`. Nothing is written.
3. **Send.** Run again with `dry_run: false`. Expect a public note with the link and the "Reply 'fixed'" line, and an internal note ending with the `Ref: AAI troubleshooting article sent` marker. Run it a second time: expect `decision: already-sent` and no new notes.
4. **Reply.** Run with `mode: reply`, the same `ticketId` and `replyText: "Still not working"`. Expect `decision: not-clear`, an internal note, the ticket still open. Then `replyText: "Fixed, thanks"`: expect `decision: close`, the ticket closed, a short public note and an internal note.
5. **Wire the triggers.** Enable the webhook in **Properties**, redeploy, add the secret to the ServiceAI Secrets manager as `aai_send_troubleshooting_article`, and create both Actions and both triage rules above. Watch **Action Runs** on the first live ticket.

> Webhook secrets are stripped from this export, so AutomationAI issues a new URL and secret on import. The step logic lives in `src/`: edit `parse.ps1`, `check.ps1` or `act.ps1`, run `node src/build.js` (it also pastes the PSA and CloudRadial code from `_shared/`), then `pwsh -NoProfile -File src/test.ps1` (strict mode, mocked CloudRadial and PSAs). Never edit the `.yml` by hand.

### Not yet proven live

- Whether ServiceAI triage fires an Action on a customer **reply** (not only on a new ticket). If it doesn't, the reply entry point needs another caller (for example a PSA workflow rule).
- The shape of `GET /v2/article/{id}` (a bare article or wrapped in `data`; both are read), and how MSP-wide articles are stored (company 0 is assumed; `mspCompanyId` covers a partner company).
- The portal's article link format. Links with `/kb/article/<id>`, `/article/<id>` or `?articleId=<id>` are matched by id; others need `allowedLinkHosts`.
- The shared adapter's note reads for Autotask and HaloPSA, and its public-note and close calls (marked `Unverified` in `_shared/psa.ps1`).
