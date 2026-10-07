# Triage Reported Phishing Emails into a Ticket with the Evidence

When a user reports a suspicious email, the technician gets a categorized ticket that already shows who really sent it, whether it passed SPF, DKIM and DMARC, where its links go and what is attached, with a risk verdict and, for malicious mail, a ready-to-review purge script.

**Marketplace ID:** TBD | **Type:** Workflow (PowerShell steps plus one AI Prompt step)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `phishing-report-triage.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/phishing-report-triage/phishing-report-triage.yml) |
| Download `phishing-report-triage.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/phishing-report-triage/phishing-report-triage.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/automationai/phishing-report-triage/src) |
| All files in this automation | [automationai/phishing-report-triage](https://github.com/cloudradial/Automations/tree/main/automationai/phishing-report-triage) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/phishing-report-triage) |

## How it works

Four steps. Only step 3 uses AI, and it can't call any tools.

1. **Read the report.** Takes the reporter's address and something to find the email by: its Internet Message-ID, or its subject and sender. Accepts a flat body (portal form, ServiceAI Action, manual run) or the CloudRadial `{Ticket:{Questions}, Company}` shape. If only a ticket id is sent, it reads the ticket and pulls the forwarded email's `From:`, `Subject:` and `Message-ID:` lines from it. Missing details stop the run with `status: incomplete`.
2. **Look up the email (no AI).** Signs in to Microsoft Graph with this company's app registration and checks that the report came from the same Microsoft 365 tenant. Then it finds the email in the reporter's own mailbox and checks:
   - **Authentication:** SPF, DKIM, DMARC and Microsoft composite authentication, from the `Authentication-Results` header.
   - **Sender:** a display name that shows a different address or domain, a reply-to on another domain, a sender domain that looks like the organization's own (for example `c0ntoso.com`), and punycode domains.
   - **Links:** every link, with Safe Links wrappers removed, its domain, IP-address links, URL shorteners, and link text that shows one site but points to another. URLs only ever appear defanged (`hxxps://example[.]com`).
   - **Attachments:** names and types only, never the content. Programs and scripts, macro-enabled Office files, HTML and SVG files, disk images (ISO, IMG, VHD), archives, OneNote files, double extensions such as `Invoice.pdf.html`, and attached emails are flagged.
   - **A rules score**, used when the AI answer is missing.

   The email body text is never copied into the output. **Graph can't count how many other mailboxes received the same email** (that needs Exchange Online or Defender), so the step doesn't try, and the note says so.
3. **Classify the risk (AI Prompt).** One AI call reads only the facts from step 2 and returns `{verdict: malicious | suspicious | likely-safe, confidence, reasons[]}`. No model is pinned, so the tenant's own provider is used. Everything from the email (subject, names, domains) is treated as data, never as instructions.
4. **Open or update the ticket.** Reads the AI answer. If it's empty or not valid JSON, it uses the rules score instead and says so. If the AI and the rules are two levels apart (malicious against likely-safe), it marks the email suspicious for a person to decide. Then, through the shared six-PSA adapter:
   - with a `ticket_id`, it adds the findings as an internal note on that ticket (after checking the ticket belongs to the same company);
   - otherwise, it opens a ticket titled `Phishing report (<verdict>): <subject>` for the company, with **high** priority for malicious, **medium** for suspicious or not found, and **low** for likely safe, and adds the findings as an internal note. The ticket description itself holds no findings.
   - **Malicious:** the internal note also carries a **draft** Security & Compliance search-and-purge (`New-ComplianceSearch` for the sender, subject and arrival dates, then `New-ComplianceSearchAction -Purge -PurgeType SoftDelete`) for a technician to review and run. **This workflow never purges, deletes or moves any email.**

`confirm` defaults to `false`: the run returns the verdict, the full note and what it would do (`status: pending_confirmation`) and writes nothing to the PSA. Send `confirm: true` to write. Portal forms and ServiceAI Triage Actions send `"confirm": "true"` in their body, because nobody is there to rerun them.

### This workflow or the certified Phishing Alert Triage agent?

The AutomationAI catalog also has a certified **Phishing Alert Triage** agent.

| Use | When |
|---|---|
| **This workflow** | An end user reports an email (portal form, help desk ticket, ServiceAI Triage). You want the same checks every time, a ticket in any of the six PSAs, one cheap AI call, and no approval waiting in the Inbox. |
| **Phishing Alert Triage agent** | A technician is investigating a security alert and wants an agent to explore it with the catalog extensions and ask before each change. Agent runs cost more, are limited to 25 turns, and their writes wait for approval in the Inbox. |

You can use both: this workflow for user reports, the agent for a technician's deeper follow-up on a malicious verdict.

## Download & import

**Download the workflow:** [`phishing-report-triage.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/phishing-report-triage/phishing-report-triage.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required secrets](#required-runner-key-vault-secrets) to the runner of the company it serves, enable the webhook in **Properties** if a form or ServiceAI calls it, then **Publish** and **Deploy**. Full steps are under [Import & test](#import--test).

The workflow is **per company**: it reads the running company's Microsoft 365 and PSA secrets, and never mixes one client's email into another client's ticket.

## Required runner Key Vault secrets

By name only. Use the same names as the catalog extensions, so one set serves both.

| Secret | For |
|---|---|
| `M365-TenantId`, `M365-ClientId`, `M365-ClientSecret` | Microsoft Graph sign-in (the `Entra-*` and `Graph-*` names also work) |
| `PSA-Type` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` (a `psa` input overrides it) |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | Optional: `Autotask-NotePublishId`, `Autotask-NoteTypeId`, `Autotask-NewStatusId`, `Autotask-BillingCodeId` |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Optional: `Halo-NoteOutcomeId` |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId` | Optional: `KaseyaBMS-NewStatusId`, `KaseyaBMS-TicketTypeId`, `KaseyaBMS-TicketSourceId`, `KaseyaBMS-PriorityId`, `KaseyaBMS-QueueId` |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | |

## Required Graph permissions

Application permissions on the `M365-*` app registration, with admin consent:

| Permission | Why |
|---|---|
| `Mail.Read` | Find the reported email and read its headers, links and attachment names. |
| `User.Read.All` | Confirm the reporter is a user in this tenant. |

`Mail.Read` as an application permission can read every mailbox in the tenant. **Scope it with an Exchange Online application access policy** (or RBAC for Applications) so the app can only read the mailboxes it should, for example:

```powershell
New-ApplicationAccessPolicy -AppId <M365-ClientId> -PolicyScopeGroupId PhishReportMailboxes@contoso.com -AccessRight RestrictAccess -Description 'Phishing report triage'
```

When a permission is missing, the lookup step stops with a plain sentence naming it (for example "The app registration needs the Mail.Read application permission").

The draft purge runs outside this workflow. The technician who runs it needs the **Compliance Search** and **Search And Purge** roles in Microsoft Purview.

## Inputs

| Field | Required | Meaning |
|---|---|---|
| `reporter_upn` | Yes | The reporter's address. **Map it to `@UserEmail`** on a portal form (CloudRadial sets it from the signed-in user, so nobody can point the lookup at someone else's mailbox). In ServiceAI, map it to the ticket contact's email. |
| `message_id` | One of these | The Internet Message-ID (`<...@...>`). The most exact. |
| `subject` and `sender` | One of these | Used when there's no Message-ID: the sender's emails from the last 30 days whose subject contains the text. Subject alone works too, by search. |
| `ticket_id` | No | Note this ticket instead of opening one. Alone (with `reporter_upn`), the workflow reads the forwarded email's details from the ticket. |
| `psa` | No | Overrides the `PSA-Type` secret. |
| `psa_company_id` or `company_name` | To open a ticket | The PSA's company id (`@CompanyPsaId`), or a name that matches exactly one PSA company (`@CompanyName`). |
| `company_tenant_id` | Recommended | `@CompanyTenantId`. When set, the run stops (`rejected`) unless it matches the Microsoft 365 tenant of this runner's app. |
| `psa_queue` | No | Board (ConnectWise), queue (Autotask, Kaseya BMS), team (HaloPSA), issue type (Syncro) or group id (Zendesk) for the new ticket. |
| `confirm` | No (default `false`) | `true` writes to the PSA. `false` returns a preview. |

**Portal form webhook body** (Partner > Automations, Webhook activity, absolute URL, header `{"X-Crauto-Webhook-Secret": "<secret>"}`):

```json
{
  "reporter_upn": "@UserEmail",
  "message_id": "@messageId",
  "subject": "@emailSubject",
  "sender": "@emailSender",
  "ticket_id": "@TicketId",
  "psa_company_id": "@CompanyPsaId",
  "company_name": "@CompanyName",
  "company_tenant_id": "@CompanyTenantId",
  "confirm": "true"
}
```

`messageId`, `emailSubject` and `emailSender` are the form questions' Field IDs. A question left blank arrives as the literal `@token`, which the workflow treats as not given.

**ServiceAI Triage Action:** a rule such as *"If a user reports a suspicious or phishing email, run the **Phishing Report Triage** action."* Map `ticket_id` to the ticket id and `reporter_upn` to the contact's email in the body template, and send `"confirm": "true"`. The workflow writes its own note, so the response is not needed.

## Output

`status` (`success`, `pending_confirmation`, `incomplete`, `rejected` or `error`), `message`, `public_note` (safe to show the reporter), `internal_note` (the full findings and any draft purge), `ticket_id`, `psa`, `verdict` (`malicious`, `suspicious`, `likely-safe` or `unknown` when the email wasn't found), `confidence`, `reasons`, `classified_by` (`ai`, `rules` or `not-found`), `rules_score`, `purge_drafted`, `planned`, `actions`, `warnings` and `chatReply`.

## Import & test

1. Import `phishing-report-triage.yml`, add the secrets above to the company's runner vault, then **Publish** and **Deploy** to that runner.
2. **Preview first.** In **Run**, use the first step's Test Input with a real `reporter_upn` and the Message-ID of a test email in that mailbox (Outlook: File > Properties > Internet headers, `Message-ID`). Leave `confirm` false. Expect `status: pending_confirmation`, a verdict, and the full note in `internal_note`. Nothing is written to the PSA.
3. **Write.** Run again with `"confirm": true` and `company_name` (or `psa_company_id`). Expect a new ticket with the findings as an internal note. Try `ticket_id` too.
4. **Wire the trigger.** Enable the webhook in **Properties** (AutomationAI issues the URL and secret), redeploy, and point the portal form's Webhook activity or the ServiceAI Action at it.

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. The step logic lives in `src/`: edit `parse.ps1`, `enrich.ps1`, `ticket.ps1` or the `classify.*.txt` prompts, run `node src/build.js`, then `pwsh -NoProfile -File src/test.ps1` (strict mode, mocked Graph and PSAs). Never edit the `.yml` by hand.
