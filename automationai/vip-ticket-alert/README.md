# Alert the Account Manager When a VIP Client Opens a Ticket

The moment a VIP client's ticket lands, their account manager gets a short email with the summary and a link, and the ticket records that they were told, once per ticket.

**Marketplace ID:** TBD | **Type:** Workflow (PowerShell steps, no AI)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `vip-ticket-alert.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/vip-ticket-alert/vip-ticket-alert.yml) |
| Download `vip-ticket-alert.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/vip-ticket-alert/vip-ticket-alert.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/automationai/vip-ticket-alert/src) |
| All files in this automation | [automationai/vip-ticket-alert](https://github.com/cloudradial/Automations/tree/main/automationai/vip-ticket-alert) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/vip-ticket-alert) |

## How it works

ServiceAI triage calls the **Notify VIP Ticket** Action when a new ticket looks like it comes from a VIP. The Action posts the ticket number, company, contact, summary and priority to this workflow. Three steps, no AI:

1. **Check the VIP list.** Compares the company name, PSA company id and contact email with the VIP list. **Not on the list:** the run ends with `status: success`, a plain reason, and no PSA call at all. **On the list:** it reads the ticket through the shared six-PSA adapter to make sure it exists and that no internal note marked `[vip-ticket-alert]` is on it yet. If one is, the run ends with `success` and nothing is sent again, so a ServiceAI retry or a second triage pass never alerts twice.
2. **Build the alert.** Writes the email: company, ticket number, summary, priority, contact and a link to the ticket in the PSA.
3. **Email the account manager and note the ticket.** Sends the email through Postmark (`Send-PmMail` from the shared `_shared/postmark.ps1`), then adds an **internal** note: "VIP ticket alert sent to ... by email.", ending with the `[vip-ticket-alert]` marker. The note is written with `Add-PsaNote -Marker`, so a note that is already there is never added again. If Postmark isn't set up or refuses the email, the internal note carries the whole alert instead and asks the team to tell the account manager. It never changes the ticket's status, priority or assignee, and never writes anything the client can see.

A normal call sends the alert and adds the note. `"preview": true` returns the email it would send (`status: pending_confirmation`) and sends nothing. It only writes notes and sends emails, which the service-desk rules exempt from the confirm pattern, so a normal call acts straight away; a live webhook that previewed because its body left out a flag would be the worse failure. The `[vip-ticket-alert]` marker stops a ServiceAI **Action Runs** Retry, or a second triage pass, from emailing or noting twice.

### Why a list in a secret, not a knowledge article

The VIP list is one runner secret, `VIP-Companies`, holding a comma-separated list. That is the simpler choice:

- Script steps can't read Knowledge, so a knowledge article would need an agent step (slower, costs AI turns, and recall returns chunks, not exact rows).
- A KB-article table (like the Ticket Routing pattern) needs CloudRadial API secrets and an HTML table parser, for a list that is usually under 20 names.
- The secret is per runner, so each MSP keeps its own list, and the `vip_list` input overrides it for a test.

If the list grows past what fits comfortably in one secret, move it to a KB article and read it with the shared `cloudradial.ps1`.

### The VIP list format

Entries are separated by commas, semicolons or new lines. Each entry is one of:

| Entry | Matches |
|---|---|
| `Contoso` | the company name, ignoring case and extra spaces |
| `42` | the PSA company id (Zendesk organization id, and so on) |
| `ceo@contoso.com` | that contact |
| `@contoso.com` | any contact at that domain |

Add `=address` to alert a specific person, and `|` between several: `Contoso=am@examplemsp.com|csm@examplemsp.com, Fabrikam, @tailspin.example`. An entry with no address uses the `alert_to` input, then the `VIP-AlertTo` secret.

## Download & import

**Download the workflow:** [`vip-ticket-alert.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/vip-ticket-alert/vip-ticket-alert.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required secrets](#required-runner-key-vault-secrets) to the runner, enable the webhook in **Properties**, then **Publish** and **Deploy**. Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

By name only. The PSA and Postmark names are the same as the catalog extensions, so one set serves both.

| Secret | For |
|---|---|
| `VIP-Companies` | The VIP list (format above). Required unless every run sends `vip_list`. |
| `VIP-AlertTo` | Optional. Who gets alerts for entries with no address of their own. |
| `Postmark-ServerToken`, `Postmark-FromEmail` | The alert email. Optional `Postmark-ApiUrl` (default `https://api.postmarkapp.com`). Without them, the alert goes in an internal note. |
| `PSA-TicketUrlTemplate` | Optional. A ticket link with `{id}`, for example `https://psa.examplemsp.com/tickets/{id}`. Needed for Kaseya BMS, and to override the built-in links for the other PSAs. |
| `PSA-Type` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` (a `psa` input overrides it) |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | Optional: `Autotask-NotePublishId`, `Autotask-NoteTypeId` |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Optional: `Halo-NoteOutcomeId` |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId` | |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | |

The ServiceAI Action also needs its own secret in the **ServiceAI Secrets manager**: `aai_notify_vip_ticket`, holding this workflow's webhook secret.

## Required Graph permissions

None. This workflow doesn't call Microsoft Graph.

The PSA API user needs to read tickets and their notes and add notes. If it can't, the run stops with a plain sentence naming the call and the HTTP status (for example "ConnectWise GET /service/tickets/1001 failed (HTTP 403)").

## Inputs

| Field | Required | Meaning |
|---|---|---|
| `ticketId` | Yes | The PSA ticket number. `ticket_id` and the CloudRadial `Ticket.TicketId` also work. |
| `companyName` | Yes, unless `companyId` or `contactEmail` is sent | The company on the ticket, exactly as in the PSA. `organizationName` and `Company.CompanyName` also work. |
| `companyId` | No | The PSA company id (`organizationId`, `CompanyPsaId`). Matches numeric list entries. |
| `contactEmail` | No | The ticket contact. Matches email and `@domain` entries, and appears in the alert. |
| `summary` | No | The ticket summary. Read from the ticket when it's missing. |
| `priority` | No | Shown in the alert. |
| `triggerSource` | No | Where the call came from, for the run history. |
| `vip_list` | No | Overrides the `VIP-Companies` secret. |
| `alert_to` | No | Who to alert when the matching entry names nobody. Overrides `VIP-AlertTo`. |
| `ticket_url_template`, `ticketUrl` | No | A link template with `{id}`, or the full link. |
| `psa` | No | Overrides the `PSA-Type` secret. |
| `preview` | No (default `false`) | `true` returns the email it would send and writes nothing. `dryRun` works too. |

## Output

`status` (`success`, `pending_confirmation`, `incomplete`, `rejected` or `error`), `message`, `public_note` (always empty: nothing goes to the client), `internal_note`, `ticket_id`, `vip`, `alerted`, `recipients`, `postmark_message_id`, `actions`, `warnings` and `chatReply`. A preview also returns `subject` and `email_text`.

## ServiceAI setup

**Action** (ServiceAI Settings > Actions > New):

| Setting | Value |
|---|---|
| Name | `Notify VIP Ticket` |
| Mode | **Use in Triage** |
| Method and URL | `POST`, this workflow's webhook URL (AutomationAI > the workflow > Properties > Webhook) |
| Headers | `Content-Type: application/json` and `X-Crauto-Webhook-Secret: {{secret.aai_notify_vip_ticket}}` |
| Parameters | `ticketId` (required, string, the PSA ticket number of the current ticket); `companyName` (required, string, the company name on the ticket, exactly as in the PSA); `contactEmail` (optional, string, the ticket contact email); `summary` (required, string, the ticket summary); `priority` (optional, string, the ticket priority) |

Body:

```json
{
  "ticketId": "{{ticketId}}",
  "companyName": "{{companyName}}",
  "contactEmail": "{{contactEmail}}",
  "summary": "{{summary}}",
  "priority": "{{priority}}",
  "triggerSource": "serviceai-triage"
}
```

**Triage rule:** *"When a new ticket comes from a company tagged Enterprise or VIP, or from a contact tagged VIP, call the **Notify VIP Ticket** action with the ticket number, company name, contact email, summary and priority. Call it once per ticket."*

The triage AI decides when to call the Action, so it may call it for a company that isn't on your list. That's safe: the workflow checks its own list and ends with "not on the VIP list". The workflow writes its own note, so ServiceAI doesn't need the response. The **Action Runs** page shows each call, and AutomationAI's run history shows what the workflow did.

## Import & test

1. Import `vip-ticket-alert.yml`, add the secrets above to the runner vault, then **Publish** and **Deploy** to that runner.
2. **Preview first.** In **Run**, use the first step's Test Input with a real ticket number and a company that is on `vip_list`. Set `"preview": true`. Expect `status: pending_confirmation` and the email text. Nothing is sent or written.
3. **Not VIP.** Run with a company that isn't on the list. Expect `status: success` and "isn't on the VIP list".
4. **Send.** Run again without `preview`, with `alert_to` set to your own address. Expect the email and an internal note on the ticket. Run it once more: expect "already sent" and no second email.
5. **Wire the trigger.** Enable the webhook in **Properties** (AutomationAI issues the URL and secret), redeploy, store the secret in ServiceAI as `aai_notify_vip_ticket`, and create the Action and triage rule above. Use **Send test** in the Action editor, then check **Action Runs** and the AutomationAI run history.

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. The step logic lives in `src/`: edit `check.ps1`, `build-alert.ps1`, `send.ps1` or `step.ps1`, run `node src/build.js` (it pastes in `_shared/psa.ps1` and `_shared/postmark.ps1`), then `pwsh -NoProfile -File src/test.ps1` (strict mode, mocked PSAs and Postmark). Never edit the `.yml` by hand.

### Not yet proven live

- The ticket notes read (`Get-PsaTicketNotes` in `_shared/psa.ps1`) for Autotask and HaloPSA, and the built-in ticket links for ConnectWise, Autotask, HaloPSA and Syncro. Each one is marked `Unverified` in the shared source. Set the `PSA-TicketUrlTemplate` secret if the link is wrong.
- The ServiceAI Triage body: the Action's `{{variable}}` placeholders are filled by the triage AI. Check the first call in **Action Runs**.
