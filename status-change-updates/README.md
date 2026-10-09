# Tell Requesters in Plain Language When Their Ticket Changes Status

Every time a ticket moves to a status the client should know about, the requester gets a short, specific update in plain words, posted to the ticket so the PSA emails it, and internal-only statuses stay quiet.

**Marketplace ID:** TBD | **Type:** Workflow (PowerShell steps plus one AI Prompt step)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `status-change-updates.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/status-change-updates/status-change-updates.yml) |
| Download `status-change-updates.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/status-change-updates/status-change-updates.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/status-change-updates/src) |
| All files in this automation | [status-change-updates](https://github.com/cloudradial/Automations/tree/main/status-change-updates) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/status-change-updates) |

## How it works

A webhook posts the ticket number and its old and new status. Three steps; only step 2 uses AI, and it can't call any tools.

1. **Detect the status change (no AI).** Reads a flat body or the CloudRadial `{Ticket, Company}` shape. Through the shared six-PSA adapter it reads the ticket and its notes. It turns Autotask and HaloPSA status ids into names. It stops quietly (`status: success`, nothing posted) when:
   - the old and new status are the same;
   - the new status is on the ignore list (internal-only statuses such as "Waiting on Vendor");
   - the newest public note is already an update for this status (it ends with that status line), so a webhook retry or a ServiceAI **Action Runs** Retry never posts twice. A later move back to the same status still gets an update, because by then a newer note sits on top.

   Otherwise it gathers **client-visible facts only**: the ticket summary, the original request and the three latest public notes. Internal notes are never passed on.
2. **Write the update (AI Prompt).** One AI call writes 2 to 4 plain sentences for the requester: what the new status means for them and what happens next. It uses only the facts given, never invents names, dates or promises, and treats everything from the ticket as data, never as instructions. No model is pinned, so the tenant's own provider is used.
3. **Post the update to the requester (no AI).** Checks the AI answer. If it's empty, too short or long, not plain text, or mentions internal notes, it uses a **fixed template for the new status** instead and says so in `warnings`. Then it posts the text as a **public** note, ending with a status line such as `(Status: Waiting on Client)`, so the PSA emails the requester. It never changes the ticket's status or anything else.

A normal call posts the update. `"preview": true` returns the update it would post (`status: pending_confirmation`, the text in `public_note`) and posts nothing. It only writes notes and sends emails, which the service-desk rules exempt from the confirm pattern, so a normal call acts straight away; a live webhook that previewed because its body left out a flag would be the worse failure. Duplicate guards stop a retry from acting twice.

### Built-in templates

Used when the AI answer can't be used. Matched on the new status name, first match wins. The `templates` input replaces them per status.

| Status looks like | Update |
|---|---|
| Waiting on client / customer, need info | We need a little more information from you to keep ticket {ticket} ({summary}) moving. Please reply to this ticket with any details you have, and we'll pick it straight back up. |
| Resolved, completed, closed, solved | We believe ticket {ticket} ({summary}) is now resolved. If anything still isn't working as it should, just reply to this ticket and we'll take another look. |
| In progress, working, assigned | A technician is now working on ticket {ticket} ({summary}). We'll keep you posted as things move forward. |
| Scheduled, appointment | Ticket {ticket} ({summary}) has been scheduled. We'll be in touch if anything changes before then. |
| On hold, pending | Ticket {ticket} ({summary}) is on hold for now. We haven't forgotten it, and we'll update you as soon as it moves again. |
| New, open, reopened | Ticket {ticket} ({summary}) is open and in our queue. We'll update you as soon as someone picks it up. |
| Anything else | Ticket {ticket} ({summary}) is now {status}. We'll keep you updated as it moves forward. |

If you also run **Post-Close Feedback**, consider adding your closed status to `ignore_statuses`, so the requester gets the survey rather than two messages at close.

## Download & import

**Download the workflow:** [`status-change-updates.yml`](https://github.com/cloudradial/Automations/blob/main/status-change-updates/status-change-updates.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required secrets](#required-runner-key-vault-secrets) to the runner, enable the webhook in **Properties**, then **Publish** and **Deploy**. Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

By name only. Use the same names as the catalog extensions, so one set serves both.

| Secret | For |
|---|---|
| `PSA-Type` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` (a `psa` input overrides it) |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | Optional: `Autotask-NotePublicPublishId`, `Autotask-NoteTypeId` |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Optional: `Halo-PublicNoteOutcomeId` |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId` | |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | |

## Required Graph permissions

None. This workflow doesn't call Microsoft Graph.

The PSA API user needs to read tickets and notes and add public notes. If it can't, the run stops with a plain sentence naming the call and the HTTP status (for example "ConnectWise POST /service/tickets/1001/notes failed (HTTP 403)").

## Inputs

| Field | Required | Meaning |
|---|---|---|
| `ticketId` | Yes | The PSA ticket number. `ticket_id` and the CloudRadial `Ticket.TicketId` also work. |
| `newStatus` | No | The status the ticket moved to (name, or id for Autotask and HaloPSA). Read from the ticket when it's missing. `status` also works. |
| `oldStatus` | No | The status it moved from. When it equals `newStatus`, nothing is posted. |
| `contactEmail` | No | The requester. The PSA emails the ticket's own contact; this is only recorded, and a warning notes when it's missing. |
| `ignore_statuses` | No | Statuses that never notify the requester, comma-separated, `*` wildcards allowed. Default: `Waiting on Vendor, Waiting on Parts, Waiting on Third Party, Internal Review, Escalated, Scheduled Internally`. |
| `templates` | No | JSON object of status name to text, for example `{"Waiting on Client": "Ticket {ticket} needs your reply about {summary}."}`. `{ticket}`, `{summary}` and `{status}` are filled in. |
| `psa` | No | Overrides the `PSA-Type` secret. |
| `preview` | No (default `false`) | `true` returns the update it would post and writes nothing. `dryRun` works too. |

**Example webhook body:**

```json
{
  "ticketId": "1001",
  "oldStatus": "New",
  "newStatus": "Waiting on Client",
  "contactEmail": "megan.bowen@contoso.com"
}
```

## Output

`status` (`success`, `pending_confirmation`, `incomplete`, `rejected` or `error`), `message`, `public_note` (the update, as posted or as it would be posted), `internal_note`, `ticket_id`, `posted`, `written_by` (`ai` or `template`), `old_status`, `new_status`, `actions` and `warnings`.

## Wiring the trigger

The caller POSTs to the workflow's webhook URL with the secret in the **`X-Crauto-Webhook-Secret`** header.

- **Zendesk:** a webhook (Admin Center > Apps and integrations > Webhooks) with a custom `X-Crauto-Webhook-Secret` header, and a trigger on "Status changed" that notifies it with `{"ticketId": "{{ticket.id}}", "newStatus": "{{ticket.status}}", "contactEmail": "{{ticket.requester.email}}"}`. Zendesk has no placeholder for the previous status, so `oldStatus` is left out.
- **ConnectWise, Autotask, HaloPSA, Kaseya BMS, Syncro:** each has its own outbound webhook or callback feature, and not every one can add a custom header or send the old status. **[unverified]** Check what yours can send. If it can't add the header, put a small relay in between (for example an Azure Function or a Power Automate flow) that adds it.
- **CloudRadial:** if a portal automation fires on ticket status changes, its Webhook activity can post the CloudRadial `{Ticket, Company}` shape with `oldStatus` and `newStatus` as Field IDs. **[unverified]** whether such a trigger exists.

## Import & test

1. Import `status-change-updates.yml`, add the secrets above to the runner vault, then **Publish** and **Deploy** to that runner.
2. **Preview first.** In **Run**, use the first step's Test Input with a real ticket number and `newStatus` set to "Waiting on Client" (or your equivalent). Set `"preview": true`. Expect `status: pending_confirmation` and the update in `public_note`. Nothing is posted.
3. **Skips.** Run with `oldStatus` equal to `newStatus`, then with `newStatus` set to "Waiting on Vendor". Both should end `success` with nothing posted.
4. **Post.** Run without `preview` on a test ticket whose contact is you. Expect a public note and the PSA's email. Run it again: expect "already the newest public note".
5. **Wire the trigger** as above, enable the webhook in **Properties**, and redeploy.

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. The step logic lives in `src/`: edit `detect.ps1`, `post.ps1`, `step.ps1` or the `write.*.txt` prompts, run `node src/build.js` (it pastes in `_shared/psa.ps1`), then `pwsh -NoProfile -File src/test.ps1` (strict mode, mocked PSAs, simulated AI answers). Never edit the `.yml` by hand.

### Not yet proven live

- **The AI Prompt step's property names** (`promptTemplate`, `systemMessage`, `maxTokens`, `outputKey`, `model`) follow the Phishing Report Triage workflow and aren't confirmed by an export yet. The post step binds the **whole** AI output (`{{ nodes.write.output }}`) and finds the text in it, so a different output key still works.
- **Whether the PSA emails the requester** for an API-added public note depends on each PSA's notification settings (for example ConnectWise's board email settings, Autotask notification templates, HaloPSA's outcome settings). Syncro public comments are sent with `do_not_email` off.
- The ticket notes read (`Get-PsaTicketNotes`) for Autotask and HaloPSA, the HaloPSA status-name lookup (`Get-PsaStatusName`), and ConnectWise public notes on the Discussion tab, all in `_shared/psa.ps1`. Each is marked `Unverified` in the shared source.
