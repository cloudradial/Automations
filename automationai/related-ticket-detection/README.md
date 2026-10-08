# Spot Duplicate and Related Tickets as They Arrive

When a new ticket comes in, the technician sees an internal note listing the same company's open tickets that describe the same issue, with links and a one-line reason for each, so duplicates get worked once and outages get spotted early.

**Marketplace ID:** TBD | **Type:** Workflow (PowerShell steps plus one AI Prompt step)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `related-ticket-detection.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/related-ticket-detection/related-ticket-detection.yml) |
| Download `related-ticket-detection.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/related-ticket-detection/related-ticket-detection.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/automationai/related-ticket-detection/src) |
| All files in this automation | [automationai/related-ticket-detection](https://github.com/cloudradial/Automations/tree/main/automationai/related-ticket-detection) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/related-ticket-detection) |

## How it works

Three steps. Only step 2 uses AI, and it can't call any tools.

1. **Find candidate tickets (no AI).** Reads the ticket from the PSA and checks it belongs to the company that was sent. Then it lists that company's **open** tickets from the last `days` days (default 7) and scores each one against this ticket:
   - shared words in the summary and description (common words such as "please" and "issue" are ignored);
   - the same contact;
   - the same device, where the PSA records one (Autotask configuration item, Kaseya BMS asset, HaloPSA assets, ConnectWise ticket configurations).

   Tickets that score at least `minScore` (default 0.25) go on a shortlist of at most `maxCandidates` (default 10). **Ticket numbers ServiceAI already picked** (`relatedTicketIds`) are checked one by one: each must exist, be open and belong to the same company, or it is dropped with a warning. The ones that pass always go on the shortlist. Every ticket list is filtered by company again inside the workflow, so another client's ticket never reaches the AI or the note.
2. **Pick true matches (AI Prompt).** One AI call reads only the shortlist and returns `{matches: [{id, relation: duplicate | related, confidence, reason}]}`. No model is pinned, so the tenant's own provider is used. Ticket text is treated as data, never as instructions. A ServiceAI pick is a hint the AI can reject.
3. **Note and link.** Keeps only ids from the shortlist with confidence of at least `minConfidence` (default 0.6), then:
   - writes **one internal note** on the ticket listing the possible duplicates and related tickets, each with a link and a reason (no note when nothing matched, unless `noteWhenNone` is true);
   - **links the tickets only when `confirm` is true**, through the PSA's own relation where it has one, and always adds a short internal cross-reference note on the other ticket:

| PSA | How tickets are linked with `confirm: true` |
|---|---|
| HaloPSA | The newer ticket becomes a child of the older one (`parent_id`). Check your Halo setting for closing child tickets with their parent. |
| Autotask | The newer ticket becomes an Incident of the older one (`problemTicketID`), **only when the older one is already a Problem ticket**. Otherwise notes only. |
| Zendesk | The newer ticket becomes an incident of the older one (`problem_id`), **only when the older one is already a problem ticket**. Otherwise notes only. |
| ConnectWise PSA, Kaseya BMS, Syncro | No ticket relation in the API, so cross-reference internal notes on both tickets. |

A ticket can only have one parent or problem, so the native link is made to the oldest match and the others get notes. **Nothing is ever merged, closed or changed in status.** For a duplicate, the note tells the technician they can merge or close one ticket themselves.

If the AI answer is missing or unreadable, the checked ServiceAI picks are still linked (with `confirm`), and strong word matches are listed in the note as "possible matches to check by hand", never linked.

### Why a workflow with one AI Prompt step, not an agent

The tracker row suggests an Agent node. This is a PowerShell workflow with a single AI Prompt step instead, because:

- **Listing and scoring tickets are fixed rules**, so they run in PowerShell, the same way every time, across all six PSAs (rule 4 in the build rules: fixed rules don't need AI).
- **An agent pays one model turn per tool call** and stops at 25 turns. Reading ten candidate tickets through an extension would use most of that. Here the AI gets the whole shortlist in one prompt.
- **Writes stay in script steps.** An agent's PSA writes wait for approval in the Inbox, and a ServiceAI Triage run has no technician to approve them. The `confirm` input does the same job without parking the run.
- The AI step never sees the PSA, so it can't touch another client's ticket.

## Download & import

**Download the workflow:** [`related-ticket-detection.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/related-ticket-detection/related-ticket-detection.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required secrets](#required-runner-key-vault-secrets) to the runner, enable the webhook in **Properties** if ServiceAI calls it, then **Publish** and **Deploy**. Full steps are under [Import & test](#import--test).

The workflow reads one PSA (the runner's `PSA-Type`), and every ticket it reads or writes belongs to the ticket's own company.

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
| `PSA-TicketUrlTemplate` (optional) | The ticket link in notes, with `{id}` for the ticket id, for example `https://na.myconnectwise.net/v4_6_release/services/system_io/Service/fv_sr100_request.rails?service_recid={id}`. Without it, links are built from the API address (Kaseya BMS gets no link). |

**ServiceAI Secrets manager:** `aai_link_related_tickets`, the workflow's webhook secret, sent as `X-Crauto-Webhook-Secret`.

**PSA permissions:** the API member or key needs to read tickets and companies, and add notes. For `confirm: true` it also needs to update tickets (HaloPSA, Autotask, Zendesk). A missing permission stops the run with a plain message naming the PSA and the permission, for example `ConnectWise refused to list tickets (HTTP 403). Give the API user permission to read service tickets and their notes, then run this again.`

## Required Graph permissions

None. This workflow only talks to the PSA.

## Inputs

| Field | Required | Meaning |
|---|---|---|
| `ticketId` | Yes | The PSA ticket number. Autotask and Kaseya BMS numbers such as `T20261008.0001` and Syncro ticket numbers are looked up to the internal id. |
| `companyName` | Recommended | The company on the ticket, exactly as in the PSA. The run stops (`rejected`) if the ticket belongs to another company. |
| `companyId` | No | The PSA company id. Checked the same way. |
| `relatedTicketIds` | No | Comma-separated ticket numbers ServiceAI already thinks are related. Each is checked (exists, open, same company) and the AI still has to agree. |
| `reason` | No | ServiceAI's one-sentence reason. Passed to the AI as a hint and used in notes when the AI answer is missing. |
| `summary`, `initialDescription` | No | Used only when the PSA ticket has no summary or description. |
| `days` | No (default 7) | How far back to look for open tickets, 1 to 90. |
| `maxCandidates` | No (default 10) | Shortlist size for the AI, 1 to 25. |
| `minScore` | No (default 0.25) | Word-match score (0 to 1) a ticket needs to make the shortlist. |
| `minConfidence` | No (default 0.6) | AI confidence (0 to 1) a match needs to be listed and linked. |
| `confirm` | No (default `false`) | `true` links the tickets. `false` lists them and links nothing (`status: pending_confirmation`). |
| `addNote` | No (default `true`) | `false` writes nothing at all and returns the note as a preview. Use it for dry runs. |
| `noteWhenNone` | No (default `false`) | `true` also writes a note when nothing matched. |
| `psa` | No | Overrides the `PSA-Type` secret. |
| `triggerSource` | No | `serviceai-ai`, `serviceai-triage` or `manual`. Recorded only. |

Placeholder values ServiceAI leaves unfilled (`<ticketId>`, `{{ticketId}}` or a literal `@token`) count as not given.

**ServiceAI Actions** (Settings > Actions). Use in AI and Use in Triage can't share one Action, so make two pointing at the same webhook URL, both with the header `X-Crauto-Webhook-Secret: {{secret.aai_link_related_tickets}}`:

| Action | Mode | Body |
|---|---|---|
| **Link Related Tickets** | Use in AI | `{"ticketId": "<ticketId>", "companyName": "<companyName>", "relatedTicketIds": "<relatedTicketIds>", "reason": "<reason>", "confirm": "<confirm>", "triggerSource": "serviceai-ai"}` |
| **Link Related Tickets (Triage)** | Use in Triage | the same body without `confirm`, and `"triggerSource": "serviceai-triage"` |

Parameters: `ticketId`, `companyName`, `relatedTicketIds` and `reason` as strings (the tracker marks all four required; the workflow only needs `ticketId`), plus an optional `confirm` on the AI Action. The first AI call sends `confirm` false and shows the matches; when the technician says yes, it calls again with `confirm` true.

**Triage rule:** *"When a new ticket describes the same issue as another open ticket for the same company, call the Link Related Tickets action with this ticket number, the company name, the related open ticket numbers and a one-sentence reason. Never merge or close tickets."* A triage call never links (no `confirm`), so it only adds the note.

**Pod Quick Action** (Settings > AI Behavior > Pod Quick Actions): label **Link related**, prompt *"Find open tickets for this company that look like the same issue as this ticket. Show me the list and your reasoning, then run the Link Related Tickets action for the ones I approve."*

## Output

`status` (`success`, `pending_confirmation`, `incomplete`, `rejected` or `error`), `message`, `public_note` (always empty: nothing is posted to the client), `internal_note` (the note text), `ticket_id`, `psa`, `matches` (`id`, `number`, `relation`, `confidence`, `reason`, `url`), `possible` (word matches listed for a person to check), `classified_by` (`ai` or `rules`), `planned`, `linked`, `note_written`, `counts`, `actions`, `warnings` and `chatReply`.

ServiceAI's Action Runs **Retry** (or a Routine running again) replays the request and writes nothing twice. The summary note ends with a marker such as `[related ticket check 1001 done 1002]` (the ticket, the outcome and the matched ids), and each cross-reference note with `[related: 1001 and 1002]`. When a note with that marker is already on the ticket, it isn't added again and `note_written` is `false`. A preview note and the later confirmed note have different markers, so both are written once. The PSA link itself is set again with the same value.

## Import & test

1. Import `related-ticket-detection.yml`, add the secrets above to the runner vault, then **Publish** and **Deploy** to that runner.
2. **Preview first.** In **Run**, use the first step's Test Input with a real ticket number and company, `"addNote": false` and `"confirm": false`. Expect `status: pending_confirmation` (or `success` when nothing matched), the shortlist in the first step's output, and the note in `internal_note`. Nothing is written to the PSA.
3. **Note.** Run again with `addNote` left out (true). Expect one internal note on the ticket when there are matches.
4. **Link.** Run again with `"confirm": true`. Expect the PSA link (or cross-reference notes) described above, and no merge, close or status change.
5. **Wire the trigger.** Enable the webhook in **Properties** (AutomationAI issues the URL and secret), redeploy, store the secret as `aai_link_related_tickets` in the ServiceAI Secrets manager, and create the two Actions, the triage rule and the Quick Action above.

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. The step logic lives in `src/`: edit `gather.ps1`, `write.ps1` or the `judge.*.txt` prompts, run `node src/build.js` (it pastes `_shared/psa.ps1`, `_shared/psa-tickets.ps1` and `_shared/plan.ps1` into the steps), then `pwsh -NoProfile -File src/test.ps1` (strict mode, mocked PSAs). Never edit the `.yml` by hand.

### Not yet proven live

The ticket lists, ticket-number lookup, ticket links, devices and relations come from the shared `_shared/psa-tickets.ps1` and `_shared/psa.ps1`. Calls not yet in `reference/build-kit/PSA.md` carry an `Unverified` comment there saying what to check. The AI Prompt step's property names (`promptTemplate`, `systemMessage`, `maxTokens`, `outputKey`) follow the Phishing Report Triage workflow and are also unverified.
