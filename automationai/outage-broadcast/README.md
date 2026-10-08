# Tell Every Affected Client About an Outage in One Step

When a service goes down, a technician tells ServiceAI what is down and what to say, and every affected client's portal shows the notice, with an optional email to each primary contact and a full record on the problem ticket.

**Marketplace ID:** TBD | **Type:** Workflow (PowerShell steps, no AI)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `outage-broadcast.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/outage-broadcast/outage-broadcast.yml) |
| Download `outage-broadcast.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/outage-broadcast/outage-broadcast.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/automationai/outage-broadcast/src) |
| All files in this automation | [automationai/outage-broadcast](https://github.com/cloudradial/Automations/tree/main/automationai/outage-broadcast) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/outage-broadcast) |

## How it works

Three PowerShell steps, no AI. It previews by default and changes nothing until it is run again with `confirm: true`.

1. **Read the request.** Reads `affectedService`, `message`, `confirm` and the optional settings below. Accepts a flat body (ServiceAI Action, ChatAI `/broadcast`, manual run), the CloudRadial `{Ticket:{Questions}, Company}` shape, or either one wrapped in `{trigger: ...}`. A value left as a literal `@token`, `{{placeholder}}` or `<placeholder>` counts as not given. It refuses a missing service or message, a message over 2,000 characters, and a message with script or embedded content. The whole body is kept in the output (`received_body`, `received_keys`) so the first test can show which field ServiceAI uses for the signed-in technician.
2. **Find the affected companies.** Reads CloudRadial only. It uses the first of these that is given:
   1. `companies`: CloudRadial company names or ids.
   2. `companyGroup`: a CloudRadial company group name (active members only).
   3. Otherwise, in a broadcast, **every company with an endpoint that has a matching service installed** (CloudRadial `service` and `serviceinstall`, matched on the service name containing `affectedService`). In a resolved run, every company whose banner token or pinned Service Status article still shows this service.

   It stops with `incomplete` when more companies match than `maxCompanies` (default 50) and says how to go ahead. It also reads each company's current banner token and Service Status article, so the preview can say exactly what would be created, updated or cleared.
3. **Post the notice and record it.** Builds one plan for every company and runs it only with `confirm: true`:
   - **Portal banner token.** The CloudRadial API has **no news, announcement or banner resource** (checked against the v2 Swagger). So the notice goes into a company token, `@ServiceStatus` by default, as `"<service>: <message>"`. Put `@ServiceStatus` in the portal's home page banner or announcement content once, and every company's portal shows its own value. The first broadcast also creates an empty partner-level `@ServiceStatus`, so a portal with no outage shows nothing instead of the literal token.
   - **Service Status article.** One knowledge base article per company, `Service status: <service>`, in the `Service Status` category, pinned to the portal front page. A later broadcast for the same service updates it instead of adding another.
   - **Email (off by default).** With `emailContacts: true`, each company's primary contact is read from the PSA (through the company's PSA link in CloudRadial) and gets one email of their own through Postmark. Without the Postmark secrets nothing is emailed, and the ticket note lists who would have been.
   - **Problem ticket.** With `problemTicketId` (or `ticketId`), an internal note lists who ran it, every company and why it was included, what changed for each, the contacts, the client message and any warnings. Written through the shared six-PSA adapter. The note ends with a marker built from the mode, the service and the client message, so a ServiceAI **Retry** or a repeated run finds it already on the ticket and doesn't add it again. A new message (an update) gets its own note.

   A company whose banner already shows this exact notice is skipped, so a retried run (ServiceAI **Retry** replays the request) doesn't email anyone twice. The changes run in order and stop at the first failure, and the note says what ran and what didn't.

**Resolved mode** (`mode: resolved`): clears the banner token, but only where it still mentions this service, so another outage's notice is left alone. It marks the Service Status article `(resolved)` with the resolution text and unpins it, emails the primary contacts if `emailContacts` is on, and notes the problem ticket. `message` is optional here and defaults to a short resolution sentence.

**Scope:** every company gets the same client message and only its own token, article and email, so no client sees another client's name. The internal note on the problem ticket does list every affected company, so keep the problem ticket under your own (MSP) company in the PSA.

## Download & import

**Download the workflow:** [`outage-broadcast.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/outage-broadcast/outage-broadcast.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required secrets](#required-runner-key-vault-secrets) to the MSP's runner, enable the webhook in **Properties**, then **Publish** and **Deploy**. Full steps are under [Import & test](#import--test).

This automation runs **across companies** with the MSP's own CloudRadial API keys and PSA connection.

## Required runner Key Vault secrets

By name only. Use the same names as the catalog extensions, so one set serves both.

| Secret | For |
|---|---|
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Reading companies, groups, services, tokens and articles, and writing tokens and articles. Required. |
| `PSA-Type` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` (a `psa` input overrides it). Needed for the problem ticket note and the primary contacts. Without it both are skipped with a warning. |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | Optional: `Autotask-NotePublishId`, `Autotask-NoteTypeId` |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Optional: `Halo-NoteOutcomeId` |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId` | |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | Zendesk organizations have no primary contact, so nobody is emailed on Zendesk. |
| `Postmark-ServerToken`, `Postmark-FromEmail` (optional `Postmark-ApiUrl`) | Only for `emailContacts: true`. The From address must be a verified Postmark sender. |

**ServiceAI Secrets manager:** `aai_outage_broadcast`, the workflow's webhook secret, sent as `X-Crauto-Webhook-Secret: {{secret.aai_outage_broadcast}}`.

## Required Graph permissions

None. This workflow doesn't call Microsoft Graph. The CloudRadial API keys need read access to companies, company groups, services, service installs, tokens and articles, and write access to tokens and articles. A key without access stops the run with the CloudRadial error (for example `HTTP 403`) before anything is changed.

## Inputs

| Field | Required | Meaning |
|---|---|---|
| `affectedService` | Yes | The service or system that is down, as it appears in CloudRadial's service list when you rely on service installs (for example `Contoso Hosted PBX`). |
| `message` | Yes for a broadcast | The plain-language update for clients. Plain text, up to 2,000 characters. Optional in resolved mode. |
| `confirm` | No (default `false`) | `false` returns a preview and changes nothing. `true` makes the changes. `approvedToBroadcast` and `approvedToWrite` are accepted as the same flag. |
| `mode` | No (default `broadcast`) | `broadcast` or `resolved`. |
| `problemTicketId` | No | The problem ticket that gets the internal note (`ticketId` also works). |
| `companies` | No | Company names or CloudRadial ids, as a list or a comma-separated string. Overrides the service-install search. |
| `companyGroup` | No | A CloudRadial company group name. Used when `companies` is empty. |
| `emailContacts` | No (default `false`) | `true` emails each company's PSA primary contact through Postmark. |
| `postBanner` | No (default `true`) | Set or clear the banner token. |
| `postArticle` | No (default `true`) | Publish or resolve the Service Status article. |
| `bannerToken` | No (default `ServiceStatus`) | The token name, without the `@`. |
| `articleCategory` | No (default `Service Status`) | The knowledge base category for the article. |
| `maxCompanies` | No (default `50`) | The run stops if more companies match. |
| `psa` | No | Overrides the `PSA-Type` secret. |
| `triggerSource` | No | `serviceai-ai`, `chatai` or `manual`. Recorded in the note. |

**ServiceAI Action "Outage Broadcast"** (Settings > Actions, **Use in AI**, POST to the workflow's webhook URL, headers `Content-Type: application/json` and `X-Crauto-Webhook-Secret: {{secret.aai_outage_broadcast}}`). Parameters: `affectedService` (required string), `message` (required string), `confirm` (optional boolean). Example body:

```json
{
  "affectedService": "<affectedService>",
  "message": "<message>",
  "confirm": false,
  "triggerSource": "serviceai-ai"
}
```

Add `"problemTicketId": "<ticket number>"` to the body (and as an optional parameter) when technicians run it from the problem ticket. The **Outage broadcast** chat Quick Action asks for the service and message, runs the Action with `confirm: false`, shows the preview, and runs it again with `confirm: true` only after the technician says yes.

**Portal setup, once:** add `@ServiceStatus` to the portal's home page banner or announcement content (Partner > Portal settings), and create a **Service Status** knowledge base category if you want it to have its own menu entry.

## Output

`status` (`pending_confirmation` for a preview, `success`, `incomplete`, `error`), `message`, `chatReply` (short, for the technician), `public_note` (client-safe wording of the notice), `internal_note` (the full record, also written to the problem ticket), `ticket_id`, `mode`, `affectedService`, `confirm`, `requestedBy`, `triggerSource`, `targetSource`, `companies` (id, name, why it was included), `recipients`, `plan` (planned, ran, not run, failed), `counts`, `note_written`, `received_keys`, `received_body`, `actions` and `warnings`.

## Import & test

1. Import `outage-broadcast.yml`, add the secrets above to the MSP's runner vault, then **Publish** and **Deploy** to that runner.
2. **Preview first.** In **Run**, use the first step's Test Input with `affectedService` set to a service that a test company has installed. Expect `status: pending_confirmation`, the company list in `chatReply`, and the planned changes in `plan.planned`. Nothing changes.
3. **Broadcast to one test company.** Run with `companies: "<test company>"`, `problemTicketId` set to a test ticket and `confirm: true`. Expect the company's `@ServiceStatus` token set, a pinned Service Status article, and an internal note on the ticket.
4. **Resolve it.** Run with `mode: resolved`, the same `companies` and `confirm: true`. Expect the token cleared, the article marked `(resolved)` and unpinned, and a second internal note.
5. **Wire the trigger.** Enable the webhook in **Properties**, redeploy, add the webhook secret to the ServiceAI Secrets manager as `aai_outage_broadcast`, and create the **Outage Broadcast** Action above. On the first ServiceAI run, read `received_keys` to find the field that carries the signed-in technician and record it in `reference/build-kit/TRIGGERS.md`.

> Webhook secrets are stripped from this export, so AutomationAI issues a new URL and secret on import. The step logic lives in `src/`: edit `parse.ps1`, `identify.ps1` or `broadcast.ps1`, run `node src/build.js` (it also pastes the PSA, Postmark, CloudRadial and plan code from `automationai/_shared/`), then `pwsh -NoProfile -File src/test.ps1` (strict mode, mocked CloudRadial, PSAs and Postmark). Never edit the `.yml` by hand.

### Not yet proven live

- The token write body (`type: "String"`) and that an empty `value` clears a company token.
- That a company `service` row always carries its `companyId` (the installing endpoint's company is the fallback), and that the OData `contains(tolower(name), ...)` filter works on `service`.
- That the OData `token` list accepts a `name eq` filter.
- Every PSA's primary-contact lookup (`Get-PsaPrimaryContact` in `_shared/psa-tickets.ps1`, marked `Unverified` or `Vendor docs` there).
- The ServiceAI field that names the signed-in technician.
