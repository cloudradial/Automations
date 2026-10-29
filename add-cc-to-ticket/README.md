# Let Users Add Colleagues to Ticket Updates

In your UCP portal, clients can copy a coworker on a ticket's email updates themselves. No call, no email to the help desk, no technician needed.

## What your clients see in the portal

**When they open a ticket.** Any request form can ask for "Email of a coworker to keep updated". The client types a coworker's address, and that person is copied on the new ticket from the start.

**On a ticket that's already open.** An "Add someone to a ticket" form lets the client pick one of their tickets by number and add a coworker to it.

Either way, the coworker gets an email with the ticket's details, then every update after that. The email says who asked for them to be added and what the ticket is about, and reminds them that IT will never ask for a password by email.

## What it protects

- **Clients can only change their own tickets.** The ticket must belong to their company, and they must be its contact or already copied on it. Otherwise nothing changes.
- **Only the copy list changes.** Status, owner and contact stay as they were.
- **Your team can see what happened.** An internal note on the ticket says who was added, who asked, and whether the coworker was emailed.
- **The email only shows what the client already sees.** Never internal notes or anything about another ticket.

## Works with

ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS and Zendesk.

- **Autotask:** the coworker must already be a contact at that company.
- **Syncro:** not supported. Syncro has no way to copy someone on a ticket.

## What you need

- A UCP portal with **Actions** on your request forms
- AutomationAI, with your PSA connected
- A way to send the email: Postmark, or a Microsoft 365 mailbox. Without one, your PSA sends the coworker a short note about the ticket instead.

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/add-cc-to-ticket/v1.2.0).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.
4. To send the email, add your Postmark or Microsoft 365 mailbox details to your AutomationAI runner. The [technical details](https://github.com/cloudradial/Automations/tree/main/add-cc-to-ticket#sending-the-email-to-the-coworker) list exactly what to add.

**In your UCP portal, add the question to any request form:**

1. Open the form, for example **Password Reset** or **New Hardware**.
2. Add an **Email** question, "Email of a coworker to keep updated". Leave it optional.
3. At the end of the form, add an **Action** question and pick **Add CC to Ticket**.
4. Make sure the form still sends tickets to your PSA.

If the client leaves the question blank, nobody is added. If the form already asks for another email address, such as a manager's, open this question's options and set its Field ID to `ccEmail`.

**Optionally, add an "Add someone to a ticket" form:**

1. Create a new request form called **Add someone to a ticket**.
2. Add a **Text** question, "Ticket number".
3. Add an **Email** question, "Email address to add".
4. At the end of the form, add an **Action** question and pick **Add CC to Ticket**.

Keep the word "ticket" in the ticket question and "email" in the email question. That's how the automation finds them.

**Test it.** Submit each form once from the portal as a client user, then check the ticket in your PSA lists the coworker.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/add-cc-to-ticket#technical-details) cover how each PSA handles it, extra settings such as limiting which email domains can be added, and how it was tested.

---

## Technical details

**Formerly:** Add CC to Ticket | **Marketplace ID:** AAI-00038 | **Type:** Workflow (one PowerShell step, no AI) | **Version:** 1.2.0

## Files

Each version is published as a release, with `add-cc-to-ticket.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/add-cc-to-ticket/v1.2.0).

| What | Link |
|---|---|
| Download `add-cc-to-ticket.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/add-cc-to-ticket/v1.2.0) |
| View the current source | [`add-cc-to-ticket.yml`](https://github.com/cloudradial/Automations/blob/main/add-cc-to-ticket/add-cc-to-ticket.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/add-cc-to-ticket/src) |
| All files in this automation | [add-cc-to-ticket](https://github.com/cloudradial/Automations/tree/main/add-cc-to-ticket) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/add-cc-to-ticket) |

## How it works

A CloudRadial service-request form asks for a ticket number and an email address, and its Automation Webhook posts them to this workflow together with who submitted the form. One step, **Add CC to ticket**, then:

1. **Checks the request.** It needs a ticket number and exactly one email address. With `allowed_domains` set, the address must be in one of those domains. Nothing is called until these pass.
2. **Reads the ticket** through the shared six-PSA adapter (`_shared/psa.ps1`): its company, its contact's email address, its current CC list, and the client-facing details the email uses.
3. **Checks the ticket belongs to the requester** (see [The ownership rule](#the-ownership-rule)). If it doesn't, the run ends with `status: rejected` and nothing changes.
4. **Adds the address** to the ticket's CC list, then reads the ticket again to confirm the address is there. If it was already on the list (or is the ticket's contact), the run ends with `success`, "nothing changed", no note and no email.
5. **Emails the new CC the ticket's details** directly, through Postmark or a Microsoft 365 mailbox (see [Sending the email to the coworker](#sending-the-email-to-the-coworker)). The email is sent before the internal note so that one note records both the change and whether the email went. A failed email becomes a warning, never a failed run; the CC is already added.
6. **Leaves an internal note**, for example "Added alex.wilber@contoso.com to the email CC list at the request of megan.bowen@contoso.com (self-service form). Emailed alex.wilber@contoso.com the ticket's details through Postmark.", and reads the notes back to confirm it saved. A note that fails becomes a warning.
7. **Falls back to a public note** only when no email went (no email transport is set up, or the email failed): "alex.wilber@contoso.com has been copied on ticket 1001, "Printer offline" at the request of megan.bowen@contoso.com, and will now receive email updates on it. To add information, reply to any update email." The PSA emails it to the ticket's contact and CC list. Posting it only when no direct email went means a PSA that emails CCs on public notes doesn't send the coworker two emails. A public note that fails becomes a warning.

`"notify_cc": false` turns off both the email and the public note. It never changes the ticket's status, owner, contact or anything else. `"preview": true` returns what it would do (`status: pending_confirmation`), including the email it would send, and changes and sends nothing.

### Sending the email to the coworker

The email goes to the one address just added, from the first of these that is set up:

1. **Postmark**, when the `Postmark-ServerToken` and `Postmark-FromEmail` secrets are set (optional `Postmark-ApiUrl`). Your MSP sends it, whatever the client's Microsoft 365 setup. It is tagged `add-cc` in Postmark.
2. **Microsoft 365 (Graph)**, when the `AddCc-NotifySender` secret names a mailbox. It is sent with Graph `sendMail` from that mailbox, using the `M365-TenantId`, `M365-ClientId` and `M365-ClientSecret` secrets (the `Entra-*` and `Graph-*` names work too). The app needs the `Mail.Send` application permission. This is the same pattern as `Onboarding-NotifySender` in New User Onboarding.
3. **Neither:** no email, and the public note above is used as before.

The email, as the harness sends it (placeholder data):

```text
Subject: You've been copied on ticket 1001: Printer offline

Hello,

megan.bowen@contoso.com asked for you to be kept up to date on this ticket.

Ticket: 1001
Subject: Printer offline
Status: In Progress
Priority: Medium
Contact: Megan Bowen
Company: Contoso Ltd
Opened: 27 October 2026

The original request:
The printer on the second floor shows offline for everyone since this morning. We tried turning it off and on.

You'll now get an email each time the ticket is updated. To add information, reply to any of those update emails.

Our IT team will never ask for your password by email.
```

It is sent as plain text and simple HTML. With no summary, the subject is "You've been copied on ticket 1001". Any detail the PSA doesn't give is left out, never an error. Where each one comes from:

- **Status, priority, contact, company and date opened:** the ticket itself, read with `ConvertTo-PsaTicketRow` (`_shared/psa-tickets.ps1`). Autotask shows its ticket number (for example `T20261027.0001`) and its picklist labels, and its contact and company names come from the contact and company records. Zendesk's company name comes from the organization. A HaloPSA status known only by its id is left out.
- **The original request:** the ticket's description (ConnectWise: its first note, used only when that note isn't internal), with HTML stripped and cut to about 1,500 characters with "..." when longer. `"email_include_description": false` leaves it out.
- **Never included:** internal notes, technician-only fields, the assignee, or anything about another ticket or client.

### What each PSA supports

| PSA | How the CC is added | Notes |
|---|---|---|
| ConnectWise PSA | The ticket's `automaticEmailCc` list (semicolon separated) and its CC checkbox `automaticEmailCcFlag`, by json-patch | Any address. ConnectWise caps the list at 1000 characters. If the address is on the list but the checkbox is off, it turns the checkbox on. |
| Autotask | A **TicketAdditionalContacts** row | Only an active contact of the ticket's company can be added (an Autotask rule). Any other address stops with a plain sentence and nothing changes. At most 30 additional contacts. |
| HaloPSA | The ticket's `emailcclist` | Any address. |
| Kaseya BMS | The ticket's `Ccs` list, by json-patch | A known contact or employee is added by id; any other address as an email address. |
| Zendesk | `email_ccs` with `action: put` | Any address (Zendesk creates the user if needed). The **CCs** feature must be on in Zendesk; if it's off, the read-back catches it and the run says so. |
| Syncro | Not supported | Syncro's API has no ticket CC. The run stops with "Syncro's API has no way to add a CC to a ticket, so nothing was changed." and makes no call. |

Every CC call above comes from the vendor's published API reference and is marked `Unverified` in [`src/cc.ps1`](https://github.com/cloudradial/Automations/blob/main/add-cc-to-ticket/src/cc.ps1) until a live run proves it.

## The ownership rule

A form submitter must never be able to copy someone onto another person's ticket. The webhook body carries two values CloudRadial fills in at submit time, which the submitter can't change:

- `requester_email`, sent as `@UserEmail`
- `company_psa_id`, sent as `@CompanyPsaId`

The CC is added only when **both** hold:

1. The ticket's company in the PSA is `company_psa_id` (on ConnectWise, its id or its identifier).
2. The requester is the ticket's contact, or is already on its CC list.

`"allow_company_colleagues": true` relaxes the second part to "anyone at the ticket's company". The first part always applies.

If `requester_email` or `company_psa_id` is missing (or arrives as a literal `@UserEmail` because the token wasn't filled), the run stops with `status: error` (a setup problem, so the step fails and shows in the run history) and nothing is called. A technician running it by hand in the designer can send `"technician_run": true` instead: the checks it has data for still run, and the output says which were skipped. Never put `technician_run` in a client-facing form's webhook body.

These fields are only read from the webhook body (or, on an Action, from the portal's own `user` and `company` objects), never from a form answer, so adding a question with the same Field ID can't override them. A refusal never says whose ticket it is: a ticket from another company gets "Ticket 1001 isn't one you can change, so nothing was changed."

## Download & import

**Download the workflow:** [`add-cc-to-ticket.yml`](https://github.com/cloudradial/Automations/releases/tag/add-cc-to-ticket/v1.2.0)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required secrets](#required-runner-key-vault-secrets) to the runner, enable the webhook in **Properties**, then **Publish** and **Deploy**. Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

By name only. The names are the same as the PSA catalog extensions, so one set serves both.

| Secret | For |
|---|---|
| `PSA-Type` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` (a `psa` input overrides it) |
| ConnectWise: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | |
| Autotask: `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret` | Optional: `Autotask-NotePublishId`, `Autotask-NoteTypeId` |
| HaloPSA: `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Optional: `Halo-NoteOutcomeId` |
| Kaseya BMS: `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId` | |
| Syncro: `Syncro-ApiUrl`, `Syncro-ApiKey` | Not needed: Syncro isn't supported. |
| Zendesk: `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` | |
| Optional, the email by Postmark: `Postmark-ServerToken`, `Postmark-FromEmail` (a verified sender), `Postmark-ApiUrl` (default `https://api.postmarkapp.com`) | The same names as the Postmark catalog extension. Used first when the first two are set. |
| Optional, the email by Microsoft 365: `AddCc-NotifySender` (the mailbox to send from), `M365-TenantId`, `M365-ClientId`, `M365-ClientSecret` | Used when Postmark isn't set up. The `Entra-*` and `Graph-*` names work for the three app secrets. |

A missing PSA secret stops the run with a sentence naming it. A missing or wrong email secret only becomes a warning, and the public note is used instead.

## Required Graph permissions

None, unless you send the email through Microsoft 365. Then the app registration in the `M365-*` secrets needs the `Mail.Send` application permission, with admin consent, for the `AddCc-NotifySender` mailbox. Graph is never called when Postmark is set up or neither is. If Graph refuses, the warning names `Mail.Send`.

The PSA API user needs to read tickets, contacts (users in HaloPSA and Zendesk) and notes, update tickets (Autotask: create ticket additional contacts) and add notes. If the PSA refuses a call, the run stops with its own error text, for example "ConnectWise PATCH /service/tickets/1001 failed (HTTP 403): ...". Secrets and auth headers are never in the output.

## Inputs

| Field | Required | Meaning |
|---|---|---|
| `ticketNumber` | Yes | The existing ticket, as people see it (`1001`, `#1001`, or an Autotask number like `T20261008.0001`). `ticket_number`, `ticketId` and `ticket_id` also work. |
| `ccEmail` | Yes | The one address to add. `cc_email`, `cc`, `email` and `contactEmail` also work. A list, a display name or a malformed address is refused. |
| `requester_email` | Yes | Who submitted the form. Send `@UserEmail`. `requesterEmail`, `UserEmail` and `User.Email` also work. |
| `company_psa_id` | Yes | The submitter's company in the PSA. Send `@CompanyPsaId`. `companyPsaId`, `CompanyPsaId` and `Company.CompanyPsaId` also work. |
| `allow_company_colleagues` | No (default `false`) | `true` lets anyone at the ticket's company add a CC, not only its contact and CCs. |
| `allowed_domains` | No | Comma-separated domains the new address must be in, for example `contoso.com, contoso.co.uk`. |
| `technician_run` | No (default `false`) | For a technician running it by hand: allows a run without `requester_email` or `company_psa_id`. |
| `notify_cc` | No (default `true`) | Tells the new CC what the ticket is about: by email, or by the public note when no email went. `false` adds the CC with the internal note only, with no email and no public note. |
| `email_include_description` | No (default `true`) | Puts the ticket's original request (up to about 1,500 characters) in the email. `false` leaves it out. `emailIncludeDescription` works too. |
| `preview` | No (default `false`) | `true` returns what would happen and changes nothing. `dryRun` works too. |
| `psa` | No | Overrides the `PSA-Type` secret. |

The ticket number and address are read from the body first, then from the form's answers (`Ticket.Questions` by question Id). A value left as a literal `@token` counts as missing. On a CloudRadial **Action** the input is different. See [Form setup](#form-setup).

## Output

`status` (`success`, `rejected`, `error` or `pending_confirmation`), `message` (one plain sentence), `ticket_id`, `cc_email`, `added`, `cc_list` (the CC list after the change; empty when the request was refused), `actions`, `warnings`, `internal_note` (the note written, or why nothing was), `public_note` (the public note written to the new CC; empty when none was), `emailed` (`true` when the email to the new CC was sent), `email_transport` (`postmark`, `graph` or empty: the transport used, or that a preview would use; a failed send keeps it, with `emailed` false), and `email_subject` and `email_body` (the plain-text email sent, or that a preview would send; empty when there was none). An `error` also fails the step, so it shows in the run history. Setup problems are errors: no ticket number, no address to add, more than one possible answer, or no `requester_email` / `company_psa_id`. Each message says what to fix. A `rejected` run is the rules working (not their ticket, a bad address, a domain not allowed) and doesn't fail the step.

## Form setup

### With an Action (portals with Actions)

Add a question of type **Action** at the end of the form and pick **Add CC to Ticket**. There's nothing to map. The portal sends each answer under its Field ID, plus its own `ticket`, `company` and `user` objects:

- **Which ticket:** with a **Ticket number** question, that ticket. Without one, the ticket the form itself creates. That suits a form like *Reset Password* that also asks who to copy.
- **Field IDs don't have to match.** `ticketNumber` and `ccEmail` are read first. Failing those, the one answer whose Field ID mentions "ticket" and looks like a ticket number is the ticket, and the one answer whose Field ID mentions "mail" or "cc" and is a single email address (not the submitter's own, and never `userPrincipalName`) is the address. So the Field IDs the portal makes from the labels, such as `emailAddressToAdd`, work. Two different possible answers stop the run with an error naming both Field IDs.
- **Left blank:** on the form's own ticket, the email question is optional. Left blank, the run succeeds and nobody is added. On an existing ticket (a ticket number question), a missing address is an error.
- **Who's asking and their company:** only from the portal's `user.email` and `company.psaId`. The ownership rule applies as usual, so on the form's own ticket the requester is its contact.
- **The switches** (`technician_run`, `allow_company_colleagues`, `allowed_domains`, `notify_cc`, `preview`, `psa`) can't be set from an Action, and a form answer with one of those Field IDs is ignored. An Action run uses the defaults: contact or CC only, any domain, the email (or public note) on with the original request, live. If you need `allowed_domains`, use the Webhook activity below.

### With a Webhook activity

On the CloudRadial service-request form:

1. Add a question **Ticket number** (Text) with **Script / JSON Field ID** `ticketNumber`.
2. Add a question **Email address to add** (Email) with Field ID `ccEmail`.
3. On the form's **Automation** tab, add a **Webhook** activity:

| Setting | Value |
|---|---|
| URL | This workflow's webhook URL (AutomationAI > the workflow > Properties > Webhook). Use the full `https://` address. |
| Method | `POST` |
| Request Headers | `{"X-Crauto-Webhook-Secret":"<secret>"}` with the secret AutomationAI issued |
| Body | `{"ticketNumber":"@ticketNumber","ccEmail":"@ccEmail","requester_email":"@UserEmail","company_psa_id":"@CompanyPsaId"}` |

Keep `requester_email` and `company_psa_id` last in the body, as above.

Don't use `@TicketId` for the target ticket: it's the **new** ticket the form itself creates, not the one the requester wants to change. That's why the form asks for the ticket number.

## Import & test

1. Import `add-cc-to-ticket.yml`, add the secrets above to the runner vault, then **Publish** and **Deploy** to that runner.
2. **Preview first.** In **Run**, use the step's Test Input with a real ticket number, its company's PSA id, the ticket contact's email as `requester_email`, and your own address as `ccEmail`. Keep `"preview": true`. Expect `status: pending_confirmation` and nothing changed on the ticket. With an email transport set up, check `email_transport`, `email_subject` and `email_body` show the email it would send.
3. **Refusals.** Change `company_psa_id` to another company: expect `rejected` and "isn't one you can change". Change `requester_email` to someone who isn't on the ticket: expect `rejected`.
4. **Add.** Remove `preview`. Expect `success`, your address on the ticket's CC list in the PSA, and an internal note. With an email transport set up, expect `emailed: true`, one email in your inbox with the ticket's details, and no public note. Without one, expect a public note naming the ticket instead (you get it by email as the new CC). Run it again: expect "already on the CC list", no second note and no second email.
5. **Wire the form.** Enable the webhook in **Properties** (AutomationAI issues the URL and secret), redeploy, and set up the form as above. Submit it from the portal as the ticket's contact, then check the run history and the ticket.

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. The step logic lives in `src/`: edit `step.ps1` (reading the body), `cc.ps1` (each PSA's contact and CC calls), `email.ps1` (the email to the new CC) or `add-cc.ps1` (the step), run `node src/build.js` (it pastes in `_shared/psa.ps1`, `psa-tickets.ps1`, `postmark.ps1` and `graph.ps1`), then `pwsh -NoProfile -File src/test.ps1` (strict mode, mocked PSAs). Never edit the `.yml` by hand.

## Tested

Mocked PSAs, Postmark and Graph, in strict mode (`src/test.ps1`, 163 checks), plus live runs on ConnectWise from a CloudRadial form Action on DV (2026-10-19, the form's own ticket).

- Adding a CC on ConnectWise, Autotask, HaloPSA, Kaseya BMS and Zendesk, including each PSA's request shape, keeping the CCs already on the ticket, the read-back, the internal note and the public note to the new CC (on the Discussion tab in ConnectWise, a public comment in Zendesk), and `notify_cc: false`.
- Syncro refused with a plain sentence and no calls.
- Already on the list (any letter case), already the contact, and a ConnectWise ticket with the CC checkbox off.
- Ownership: wrong company (the message reveals nothing), a ConnectWise company identifier in place of its id, requester not the contact or a CC, requester already a CC, `allow_company_colleagues` (and that it never crosses companies), missing `requester_email` or `company_psa_id`, `technician_run`.
- Invalid addresses, `mailto:`, `allowed_domains`, bad or missing ticket numbers.
- Preview on three PSAs changes nothing; a preview of someone else's ticket is still refused.
- Autotask refuses an address that isn't a company contact.
- PSA errors carry the PSA's own text and no secrets; a missing secret is named; a write the PSA accepts but doesn't keep (Zendesk CCs off) is an error; a write answered with a redirect is read back and never resent.
- A refused note, or notes that can't be read back, become warnings.
- The email to the new CC: through Postmark (subject, every detail, the original request, the closing lines, the HTML part, tag `add-cc`, and no public note), through Graph from `AddCc-NotifySender` (one `sendMail`, HTML), Postmark winning when both are set, no transport (the public note as before), Postmark refusing and Graph refusing with 403 or missing its `M365-*` secrets (a warning and the public note instead), `notify_cc: false` (neither), preview (the email returned, nothing sent, no Graph sign-in), already on the list or the contact (no email), a ConnectWise internal first note left out, HTML stripped and the request cut to 1,500 characters on HaloPSA, `email_include_description: false`, a ticket with no summary or optional details, and Autotask's ticket number, picklist labels, contact and company names.
- Literal `@tokens` count as missing; the CloudRadial `Ticket.Questions` shape (`Answer` or `Value`); `Ticket.TicketId` is never used as the target; ownership fields typed into form answers are ignored.
- Field IDs the portal makes from labels (`emailAddressToAdd`, `whichTicket`), two different email answers (an error naming both), the requester's own address and `userPrincipalName` never picked as the address, a blank optional question on the form's own ticket, and setup problems failing the step.

### Not yet proven live

Every PSA call in `src/cc.ps1` except ConnectWise (marked `Unverified`), in particular the Autotask additional-contacts write, the HaloPSA `emailcclist` update, the Kaseya BMS `Ccs` patch, and Zendesk `email_ccs`. Check the first run with `preview` and then on a test ticket.

The direct email to the new CC (1.2.0) has only run against mocks. Not yet proven live:

- Sending through Postmark and through Graph `sendMail` from the `AddCc-NotifySender` mailbox, and how each looks in a real inbox.
- The extra reads the email makes: each PSA's status, priority, contact and company names and date opened, the Autotask `/Companies/{id}` and Zendesk `/organizations/{id}` reads, and on ConnectWise that the first note is the original request with its flags as expected.
- Whether a PSA also emails the new CC on its own when they are added, which would mean two emails. Check this on the first live run.
