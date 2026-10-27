# Triage Reported Phishing Emails into a Ticket with the Evidence

When one of your clients' users reports a suspicious email, your team gets a ticket that already shows who really sent it, where its links go, what is attached and how risky it looks.

## What your clients see in the portal

**A "Report a suspicious email" form.** The user gives the email's subject and sender (or its message ID if they have it) and submits.
**What your team gets.** A ticket for that client with a risk verdict (high priority if malicious, medium if suspicious, low if it looks safe). An internal note lists the evidence: sender checks, look-alike names and domains, every link (shown safely, so nobody clicks it), and risky attachment types. For a malicious email, it adds a draft clean-up script for a technician to review.

It can also start from a help desk ticket through ServiceAI.

## What it protects

- **Users can only report their own email.** It looks only in the mailbox of the person who submitted the form.
- **Nothing is ever deleted.** The workflow never purges, deletes or moves an email. Clean-up is a draft a technician runs.
- **The email's text stays out of the ticket.** Only the facts are copied. Attachments are listed by name and type, never opened.
- **One client's email never lands in another client's ticket.** Each run checks the report came from that client's own Microsoft 365.
- **A person decides close calls.** If the AI and the built-in rules strongly disagree, the email is marked suspicious for your team to check.- **No duplicates.** Running it again for the same email adds nothing twice.

## Works with

ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk.

- **Microsoft 365 only:** the email has to be in a Microsoft 365 mailbox.
- **How many people got it:** not checked. Microsoft's mail lookup can't count other mailboxes that received the same email, and the note says so.

## What you need

- AutomationAI, with your PSA connected
- Microsoft 365 connected in AutomationAI for each client, with an app that can read mail and look up users (admin consent given). We recommend limiting which mailboxes it can read.
- A UCP portal form, or ServiceAI, to start it
- For the clean-up script: the technician who runs it needs the Compliance Search and Search And Purge roles in Microsoft Purview

## Set it up

**Once per client, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/phishing-report-triage/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. Add that client's Microsoft 365 and PSA connection details to the runner that serves them. If the client's Microsoft 365 details are saved under the company in AutomationAI instead, open the **Look up the email** step and set **Company** to that client. Do this again after every import.
4. In **Properties**, turn on the webhook. AutomationAI gives you its address and secret.
5. Click **Publish**, then **Deploy**.

**In your UCP portal, add the form:**

1. Create a request form called **Report a suspicious email**.
2. Add questions for the email's **Subject** and **Sender**, and an optional one for its **Message ID**. Set their Field IDs to `emailSubject`, `emailSender` and `messageId`.
3. In the form's automation, add a **Webhook** step pointing at the workflow's address, with its secret.

**Optionally, in ServiceAI:** add a triage rule in plain words, such as "If a user reports a suspicious or phishing email, run the Phishing Report Triage action."

**Test it.** Run it once by hand in AutomationAI first: a manual run shows the verdict and the note but writes nothing. Then submit the form as a client user and check the new ticket in your PSA.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/phishing-report-triage#technical-details) cover every check, the exact permissions, and when to use the certified Phishing Alert Triage agent instead.

---

## Technical details

**Marketplace ID:** AAI-00044 | **Type:** Workflow (PowerShell steps plus one AI Prompt step) | **Version:** 1.0.0

## Files

Each version is published as a release, with `phishing-report-triage.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/phishing-report-triage/v1.0.0).

| What | Link |
|---|---|
| Download `phishing-report-triage.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/phishing-report-triage/v1.0.0) |
| View the current source | [`phishing-report-triage.yml`](https://github.com/cloudradial/Automations/blob/main/phishing-report-triage/phishing-report-triage.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/phishing-report-triage/src) |
| All files in this automation | [phishing-report-triage](https://github.com/cloudradial/Automations/tree/main/phishing-report-triage) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/phishing-report-triage) |

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

**Retry-safe.** The findings note ends with a marker made from the reported email (a short code from its Internet Message-ID, never a name or address), so a ServiceAI Action Runs **Retry** adds nothing twice. Without a `ticket_id`, a confirm run first looks for an open ticket for the company from the last 3 days, titled `Phishing report`, that already holds this report's marker, and reuses it instead of opening a second ticket. If that lookup fails, the run says so in `warnings` and opens the ticket anyway, because a missing phishing ticket is worse than a duplicate.

`confirm` defaults to `false`: the run returns the verdict, the full note and what it would do (`status: pending_confirmation`) and writes nothing to the PSA. Send `confirm: true` to write. Portal forms and ServiceAI Triage Actions send `"confirm": "true"` in their body, because nobody is there to rerun them.

### This workflow or the certified Phishing Alert Triage agent?

The AutomationAI catalog also has a certified **Phishing Alert Triage** agent.

| Use | When |
|---|---|
| **This workflow** | An end user reports an email (portal form, help desk ticket, ServiceAI Triage). You want the same checks every time, a ticket in any of the six PSAs, one cheap AI call, and no approval waiting in the Inbox. |
| **Phishing Alert Triage agent** | A technician is investigating a security alert and wants an agent to explore it with the catalog extensions and ask before each change. Agent runs cost more, are limited to 25 turns, and their writes wait for approval in the Inbox. |

You can use both: this workflow for user reports, the agent for a technician's deeper follow-up on a malicious verdict.

## Download & import

**Download the workflow:** [`phishing-report-triage.yml`](https://github.com/cloudradial/Automations/releases/tag/phishing-report-triage/v1.0.0)

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

### Microsoft 365 secrets stored per company

Sometimes a client's Microsoft 365 secrets (`M365-TenantID`, `M365-ClientID` and `M365-ClientSecret`) are saved under the company in AutomationAI (**Companies**, policy *Require company*) instead of in the runner vault. In that case, open the workflow in the designer and set **Company** to that client on the step: **Look up the email**. Then publish and deploy.

- **Set it again after every import.** Importing a workflow clears the step Company setting, because the `.yml` doesn't carry it.
- **Without it,** the step uses the runner's shared secrets, so they sign in to the wrong tenant or fail.

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
