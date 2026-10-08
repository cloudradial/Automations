# Ask Every Requester How It Went, and Hear About Bad Scores the Same Day

When a ticket closes, the requester gets a one-click satisfaction survey from the ticket itself, and any low score lands in the service manager's inbox with the comment and a link, while every score is noted on the ticket.

**Marketplace ID:** TBD | **Type:** Workflow (PowerShell steps, no AI)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `post-close-feedback.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/post-close-feedback/post-close-feedback.yml) |
| Download `post-close-feedback.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/post-close-feedback/post-close-feedback.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/automationai/post-close-feedback/src) |
| All files in this automation | [automationai/post-close-feedback](https://github.com/cloudradial/Automations/tree/main/automationai/post-close-feedback) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/post-close-feedback) |

## How it works

One workflow with **two entry points**, chosen by the `mode` input. Three steps, no AI.

**`mode: survey` (the default): a ticket closed.**

1. **Read the request.** Reads the ticket and its notes through the shared six-PSA adapter. It stops quietly (`status: success`, nothing posted) when the ticket was closed as a duplicate, spam, merged or cancelled (status or `close_reason`), or when a survey was already posted on it, so a webhook retry never sends twice.
2. **Send the survey.** Posts a **public** note, so the PSA emails the requester:

   ```
   How did we do on ticket 1001 (Printer on floor 2 not printing)?

   Your ticket is now closed. One click tells us how it went:
   Excellent (5): https://feedback.example.com/csat?ticket=1001&score=5
   Good (4): https://feedback.example.com/csat?ticket=1001&score=4
   Okay (3): ...
   Poor (2): ...
   Very poor (1): ...

   Thank you. If anything still isn't right, just reply to this ticket.
   ```

3. **Route low scores.** Nothing to do in survey mode; it returns the result.

**`mode: score`: the requester answered.** Whatever page the survey links point to sends the answer back to this same workflow with `ticketId` and `score` (and an optional `comment`).

1. **Read the request.** Checks the score is a whole number from 1 to `score_max`, that a survey was actually posted on this ticket (so nobody can score a ticket that was never surveyed), and that no score was recorded before (only the first answer counts).
2. **Send the survey.** Nothing to do in score mode.
3. **Route low scores.** When the score is at or below `threshold` (default 2 out of 5), it emails the service manager through Postmark with the score, the comment and a link to the ticket. Every score, high or low, is then added as an **internal** note ("Satisfaction score received: 2 out of 5 ..."). If Postmark isn't set up, the note says the email wasn't sent and asks the team to follow up. When a CloudRadial company id is sent, it also records the score as CloudRadial **feedback** (see below).

A normal call posts and sends. `"preview": true` returns what it would post or send (`status: pending_confirmation`) and writes nothing. It only writes notes and sends emails, which the service-desk rules exempt from the confirm pattern, so a normal call acts straight away; a live webhook that previewed because its body left out a flag would be the worse failure. Duplicate guards stop a retry from acting twice.

### Where the survey links go

The links point at the `feedback_url` input (or the `CSAT-FeedbackUrl` secret). `{ticketId}`, `{score}` and `{email}` are filled in; without `{score}`, `?ticket=...&score=...` is added. That page has to send the answer back to this workflow's webhook in score mode, with the secret header. Two ways to do that:

- **A CloudRadial portal form** ("Rate your support") with questions whose Field IDs are `ticketId`, `score` and `comment`, and a Webhook activity that posts `{"mode": "score", "ticketId": "@ticketId", "score": "@score", "comment": "@comment", "contactEmail": "@UserEmail", "company_psa_id": "@CompanyPsaId"}`. `@CompanyPsaId` is set by CloudRadial, so a client can't score another company's ticket. To record CloudRadial feedback as well, add `"cr_company_id"` with the company's CloudRadial id (no predefined token for it is documented, so it is a fixed value per company form). **[unverified]** whether a portal form can be opened with its answers filled in from the link, so the requester may have to pick the score again on the form.
- **Any survey tool or small web page** that can POST JSON with the `X-Crauto-Webhook-Secret` header (for example a Microsoft Form with a Power Automate flow). Keep the secret on the server side, never in the link.

### CloudRadial feedback

The CloudRadial v2 API has a `feedback` resource (`POST /v2/feedback`, `GET /v2/odata/feedback`), with `companyId` and `sentiment` required and fields for the ticket, the contact, a rating (positive, neutral, negative), a rating number and a comment. It stores feedback records; it has **no per-ticket survey page or link** to send people to, so the survey link has to be your own page or form.

What this workflow does with it: in score mode, when `cr_company_id` (the CloudRadial company id) is sent and the `CloudRadial-*` secrets are set, it posts the score as a feedback record (5-point scale: 4 or 5 positive, 3 neutral, 1 or 2 negative). That is what the reporting companion reads:

**Reporting companion:** [`automationai/feedback-csat-report`](https://github.com/cloudradial/Automations/tree/main/automationai/feedback-csat-report) turns CloudRadial feedback into a CSAT summary per client on a Planner card. Run it as a monthly Routine to see the scores this workflow collects.

## Download & import

**Download the workflow:** [`post-close-feedback.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/post-close-feedback/post-close-feedback.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required secrets](#required-runner-key-vault-secrets) to the runner, enable the webhook in **Properties**, then **Publish** and **Deploy**. Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

By name only. The PSA, Postmark and CloudRadial names are the same as the catalog extensions, so one set serves both.

| Secret | For |
|---|---|
| `CSAT-FeedbackUrl` | The survey page link (format above). Required unless every survey run sends `feedback_url`. Must start with `https://`. |
| `CSAT-ServiceManagerEmail` | Who hears about low scores (comma-separated for several). The `service_manager_email` input overrides it. |
| `Postmark-ServerToken`, `Postmark-FromEmail` | The low-score email. Optional `Postmark-ApiUrl` (default `https://api.postmarkapp.com`). Without them, the internal note asks the team to follow up. |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Optional. Records scores as CloudRadial feedback for the CSAT report. |
| `PSA-TicketUrlTemplate` | Optional. A ticket link with `{id}` for the low-score email. Needed for Kaseya BMS. |
| `PSA-Type` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` (a `psa` input overrides it) |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | Optional: `Autotask-NotePublishId`, `Autotask-NotePublicPublishId`, `Autotask-NoteTypeId` |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Optional: `Halo-NoteOutcomeId`, `Halo-PublicNoteOutcomeId` |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId` | |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | |

## Required Graph permissions

None. This workflow doesn't call Microsoft Graph.

The PSA API user needs to read tickets and notes and add public and internal notes on closed tickets. If it can't, the run stops with a plain sentence naming the call and the HTTP status (for example "ConnectWise POST /service/tickets/1001/notes failed (HTTP 403)").

## Inputs

| Field | Mode | Required | Meaning |
|---|---|---|---|
| `mode` | both | No | `survey` (default) or `score`. When it's missing and `score` is sent, score mode is used. |
| `ticketId` | both | Yes | The PSA ticket number. `ticket_id` and the CloudRadial `Ticket.TicketId` also work; a form question with the Field ID `ticketId` wins over the form's own ticket. |
| `contactEmail` | both | No | The requester. Used in the survey links (`{email}`) and the score note. The PSA emails the ticket's own contact. |
| `status`, `close_reason` | survey | No | How the ticket was closed. The status is read from the ticket when it's missing. |
| `skip_statuses` | survey | No | Statuses or reasons that get no survey, comma-separated (a word matches anywhere; `*` wildcards allowed). Default: `Duplicate, Spam, Merged, Cancelled, Canceled, Junk, No Response Needed`. |
| `feedback_url` | survey | No | Overrides the `CSAT-FeedbackUrl` secret. |
| `score_max` | both | No (default `5`) | The top of the scale, 2 to 10. A 5-point scale gets labels (Excellent to Very poor). |
| `score` | score | Yes | A whole number from 1 to `score_max`. `rating` also works. |
| `comment` | score | No | The requester's comment, quoted in the note and the email. |
| `threshold` | score | No (default `2`) | Scores at or below this email the service manager. |
| `service_manager_email` | score | No | Overrides the `CSAT-ServiceManagerEmail` secret. |
| `require_survey` | score | No (default `true`) | `false` accepts a score for a ticket with no survey note (for scores collected some other way). |
| `company_psa_id` | both | No | The PSA company id (`@CompanyPsaId` on a portal form, or `Company.CompanyPsaId`). When sent, the run stops (`rejected`) unless the ticket belongs to that company. |
| `cr_company_id` | score | No | The CloudRadial company id. When sent, the score is also recorded as CloudRadial feedback. |
| `psa` | both | No | Overrides the `PSA-Type` secret. |
| `preview` | both | No (default `false`) | `true` returns what it would post or send and writes nothing. `dryRun` works too. |

**Ticket closed webhook body:**

```json
{ "mode": "survey", "ticketId": "1001", "contactEmail": "megan.bowen@contoso.com", "status": "Closed" }
```

**Score webhook body:**

```json
{ "mode": "score", "ticketId": "1001", "score": "2", "comment": "Took three days to hear back.", "contactEmail": "megan.bowen@contoso.com" }
```

## Output

`status` (`success`, `pending_confirmation`, `incomplete`, `rejected` or `error`), `message`, `public_note` (the survey, in survey mode), `internal_note`, `ticket_id`, `mode`, `survey_sent`, `score`, `low_score`, `manager_emailed`, `postmark_message_id`, `cloudradial_recorded`, `actions` and `warnings`. A score preview also returns `email_text`.

## Wiring the trigger

The caller POSTs to the workflow's webhook URL with the secret in the **`X-Crauto-Webhook-Secret`** header.

- **Zendesk:** a webhook with a custom `X-Crauto-Webhook-Secret` header, and a trigger on "Status changed to Solved" that notifies it with `{"mode": "survey", "ticketId": "{{ticket.id}}", "contactEmail": "{{ticket.requester.email}}", "status": "{{ticket.status}}"}`. Use **Solved**, not Closed: Zendesk won't add comments to a closed ticket.
- **ConnectWise, Autotask, HaloPSA, Kaseya BMS, Syncro:** use the PSA's outbound webhook or callback on ticket close. **[unverified]** whether each can add a custom header; if not, put a small relay in between that adds it.
- **The score:** the survey page or portal form described above.

## Import & test

1. Import `post-close-feedback.yml`, add the secrets above to the runner vault, then **Publish** and **Deploy** to that runner.
2. **Survey preview.** In **Run**, use the first step's Test Input with a closed test ticket. Set `"preview": true`. Expect `status: pending_confirmation` and the survey in `public_note`. Nothing is posted.
3. **Skip.** Run with `"status": "Duplicate"`. Expect `success` and "no survey was sent".
4. **Send the survey.** Run without `preview` on a test ticket whose contact is you. Expect a public note and the PSA's email. Run it again: expect "already sent".
5. **Score.** Run with `"mode": "score"`, the same ticket, `"score": "1"`, and `"service_manager_email"` set to your address (no `preview`). Expect the low-score email and an internal note. Run it again: expect "already recorded". Try a ticket with no survey: expect `rejected`.
6. **Wire the triggers** as above, enable the webhook in **Properties**, and redeploy.

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. The step logic lives in `src/`: edit `parse.ps1`, `survey.ps1`, `route.ps1`, `step.ps1` or `psa-extra.ps1`, run `node src/build.js`, then `pwsh -NoProfile -File src/test.ps1` (strict mode, mocked PSAs, Postmark and CloudRadial). Never edit the `.yml` by hand.

### Not yet proven live

- `POST /v2/feedback`: the request shape is from the public v2 spec, but the meaning of `sentiment` and how the portal shows an API-created record aren't confirmed.
- **Whether the PSA emails the requester** for an API-added public note, and whether a note on a closed ticket reopens it, depend on each PSA's settings (ConnectWise board email settings, Autotask notification templates, HaloPSA outcomes).
- The ticket notes read (`Get-PsaNotes`), status-name lookup (`Get-PsaStatusName`) and ticket links (`Get-PsaTicketUrl`) in `src/psa-extra.ps1` for every PSA except where marked, and ConnectWise public notes on the Discussion tab. Each is marked `Unverified` in the source. `psa-extra.ps1` is a candidate to move into `_shared/psa.ps1`.
