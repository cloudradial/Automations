# Raise Ticket Priority to Match Its Real Impact

Outages, security incidents and tickets that block many people are raised to the right priority as soon as they arrive, with the reasoning on the ticket, while a possible P1 goes to a dispatcher to decide and no priority a technician set is ever lowered.

**Marketplace ID:** TBD | **Type:** Workflow (PowerShell steps, no AI) | **Version:** 1.0.0

## Files

Each version is published as a release, with `priority-scoring.yml` attached. Download the latest from the [**releases page**](https://github.com/cloudradial/Automations/releases?q=priority-scoring&expanded=true).

| What | Link |
|---|---|
| Download `priority-scoring.yml` (all versions) | [Releases](https://github.com/cloudradial/Automations/releases?q=priority-scoring&expanded=true) |
| View the current source | [`priority-scoring.yml`](https://github.com/cloudradial/Automations/blob/main/priority-scoring/priority-scoring.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/priority-scoring/src) |
| All files in this automation | [priority-scoring](https://github.com/cloudradial/Automations/tree/main/priority-scoring) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/priority-scoring) |

## How it works

Two steps, no AI. The rules are fixed, so the same ticket always gets the same score, and the note shows exactly why.

1. **Score the ticket (read-only).** Reads the ticket, its company and its contact, and adds up points:

| Rule | Points |
|---|---|
| Starting score | +10 |
| Something is down or compromised: *outage*, *is down*, *server down*, *no internet*, *ransomware*, *breach*, *hacked*, *compromised*, *malware*, *virus*, *data loss*, *security incident*, *encrypted files* | +40 |
| Someone is blocked: *can't / cannot / unable to* work, log in, sign in, access, connect, print, send, receive or open; *locked out*, *not working*, *keeps crashing* | +20 |
| Marked urgent: *urgent*, *asap*, *emergency*, *immediately*, *right away* | +10 |
| Many people affected: *everyone*, *all users*, *the whole office*, *company-wide*, *several users*, or 10 or more users, people, PCs or devices | +25 |
| A few people affected: 2 to 9 users, people, PCs or devices | +15 |
| The company or contact is on the VIP list | +15 |
| The company's tier is premium (or gold, platinum, enterprise) | +10 |
| The company's tier is basic (or bronze, break-fix) | -5 |
| Reads as a request or question: *how do I*, *how to*, *question*, *request*, *new user*, *set up*, *install*, *when convenient*, *no rush* | -10 |

   Each rule counts once, and the score is kept between 0 and 100. The level is **critical** at 70 or more, **high** at 45, **medium** at 25, and **low** below that.

2. **Set the priority and note the score.**
   - **`confirm` false (the default):** nothing is written. The run returns the score and what it would do (`status: pending_confirmation`).
   - **`confirm` true:** the steps below run.
     - **Raise only.** The ticket is set to the scored level, using the PSA's own priority for it. If the current priority is already at that level or higher, it's left as it is. This workflow never lowers a priority.
     - **Never above high.** A critical score sets **high**. It's also flagged as a **possible P1**: the dispatcher gets an email through Postmark with the summary, a link and the reasons, and a person decides whether it's critical. Without Postmark or a dispatcher address, the note says the dispatcher wasn't emailed, and the run ends `incomplete`.
     - **One internal note** with the score breakdown. It carries a marker, so a rerun or a ServiceAI Retry changes nothing again and never emails the dispatcher twice.

| PSA | How the priority is set |
|---|---|
| ConnectWise PSA | The board's priority whose name matches the level. If the API member can't list priorities, impact and urgency are set instead and the board's priority matrix picks it, with a warning. |
| Autotask | The `priority` picklist value whose label matches the level |
| HaloPSA | `priority_id` 1 to 4 (the out-of-box Critical to Low) |
| Kaseya BMS | The priority lookup whose name matches the level |
| Syncro | `priority` label (`1 High`, `2 Normal`, `3 Low`) |
| Zendesk | `priority` (`high`, `normal`, `low`) |

### Why fixed rules, not an agent

The tracker row suggests an Agent node. Scoring is a fixed rule set, so it runs in PowerShell (build rule 4: fixed rules don't need AI). That makes it:
- **Predictable:** the same ticket always scores the same.
- **Free to run:** there's no model call.
- **Explained:** the breakdown in the note is the exact calculation.

### Should you use it with ServiceAI triage?

ServiceAI triage can already set a priority. Use this workflow when you want:
- the same scoring on every ticket
- the never-lower and never-above-high guarantees
- a possible P1 sent to a person

## Download & import

**Download the workflow:** [`priority-scoring.yml`](https://github.com/cloudradial/Automations/releases?q=priority-scoring&expanded=true)

Then in AutomationAI:
1. **Workflows → Import**, and upload the `.yml`.
2. Add the [required secrets](#required-runner-key-vault-secrets) to the runner.
3. Enable the webhook in **Properties** if your PSA or ServiceAI calls it.
4. **Publish** and **Deploy**.

Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

By name only. The PSA and Postmark names are the same as the catalog extensions, so one set serves both.

| Secret | For |
|---|---|
| `PSA-Type` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` (a `psa` input overrides it) |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | Optional: `Autotask-NotePublishId`, `Autotask-NoteTypeId` |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Optional: `Halo-NoteOutcomeId` |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId` | |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | |
| `Postmark-ServerToken`, `Postmark-FromEmail` | The possible-P1 email. Optional `Postmark-ApiUrl`. |
| `Dispatcher-Email` | Who gets the possible-P1 email (the same secret Auto-Escalation uses). Several addresses are allowed, separated by commas. |
| `VIP-Companies` (optional) | The VIP list, in the same format as [VIP Ticket Alert](https://github.com/cloudradial/Automations/tree/main/vip-ticket-alert#the-vip-list-format): company names, PSA company ids, contact emails or `@domains`, separated by commas. Anything after `=` is ignored here. |
| `Priority-CompanyTiers` (optional) | Company tiers, for example `Contoso=premium, Fabrikam=basic`. A company name or PSA company id, `=`, then `premium` (or gold, platinum, enterprise), `standard` or `basic` (or bronze, break-fix). Unlisted companies are standard. |

**PSA permissions:** the API member or key needs to:
- read tickets, companies and notes
- update tickets
- add notes
- on ConnectWise, also read Service Desk priorities

## Required Graph permissions

None. This workflow only talks to the PSA and Postmark.

## Inputs

| Field | Required | Meaning |
|---|---|---|
| `ticketId` | Yes | The PSA ticket number. Autotask and Kaseya BMS numbers such as `T20261014.0001` and Syncro ticket numbers are looked up to the internal id. |
| `confirm` | No (default `false`) | `true` sets the priority, emails the dispatcher and writes the note. `false` changes nothing. `approvedToWrite` works too. |
| `addNote` | No (default `true`) | `false` skips the note when nothing is flagged. A possible P1 is always noted. |
| `dispatcher_email` | No | Overrides the `Dispatcher-Email` secret. |
| `vip_list` | No | Overrides the `VIP-Companies` secret. |
| `company_tiers` | No | Overrides the `Priority-CompanyTiers` secret. |
| `psa` | No | Overrides the `PSA-Type` secret. |

It accepts a flat JSON body, the CloudRadial `{Ticket: {...}, Company: {...}}` shape, or either one wrapped in `{trigger: ...}`. Placeholder values left unfilled (`<ticketId>`, `{{ticketId}}` or a bare `@token`) count as not given.

## Output

| Field | Meaning |
|---|---|
| `status` | `success`, `pending_confirmation`, `incomplete`, `rejected` or `error` |
| `message` | What happened, in a sentence |
| `public_note` | Always empty. Nothing is posted to the client. |
| `internal_note` | The score breakdown |
| `ticket_id` | The ticket number |
| `score` | 0 to 100 |
| `level` | The scored level |
| `priority_from` | The priority before the run |
| `possible_p1` | `true` when the ticket scored critical |
| `counts` | `prioritySet`, `dispatcherEmailed` and `notesWritten` |
| `actions`, `warnings` | What ran, and anything to check |

## Import & test

1. Import `priority-scoring.yml`, add the secrets above to the runner vault, then **Publish** and **Deploy** to that runner.
2. **Preview first.** Pick a test ticket whose priority is lower than it should be, and run the first step's Test Input with its number and `"confirm": false`. Expect `status: pending_confirmation`, the score and breakdown in `internal_note`, and nothing changed.
3. **Set it.** Run again with `"confirm": true`. Expect the priority raised (never above high) and one internal note. For a ticket that scores critical, also expect an email to the dispatcher.
4. **Rerun.** Run once more. Expect "already scored" and nothing written or sent.
5. **Wire the trigger.** Enable the webhook in **Properties**. AutomationAI issues the URL and secret, and the caller sends the secret in the `X-Crauto-Webhook-Secret` header. Then call it when a ticket is created:
   - from your PSA's ticket-created callback, or
   - from a ServiceAI Action with the body `{"ticketId": "<ticketId>", "confirm": "true"}`.

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. The step logic lives in `src/`: edit `score.ps1`, `apply.ps1` or `psa-priority.ps1`, then run `node src/build.js` (it pastes `src/psa-priority.ps1` and the shared `_shared/psa.ps1`, `psa-tickets.ps1` and `postmark.ps1`) and `pwsh -NoProfile -File src/test.ps1`. Never edit the `.yml` by hand.

### Not yet proven live

- **Already proven by the shared library:** reading the ticket and the internal note.
- **Shared with `New-PsaTicket`:** the priority matching (`$PsaState.PriorityPatterns`), including the ConnectWise impact and urgency fallback.
- **Marked `Unverified` in `src/psa-priority.ps1`:**
  - patching priority on an existing ConnectWise ticket
  - HaloPSA `priority_id` on update
  - the Kaseya BMS priority lookup
  - the Syncro priority label

  Check one supervised run on your PSA before turning on `confirm` from a trigger.
