# Let Users Add Colleagues to Ticket Updates

A requester adds a coworker to the email updates on one of their own open tickets from the portal, with no technician needed, and the ticket records who was added and by whom.

**Formerly:** Add CC to Ticket | **Marketplace ID:** AAI-00038 | **Type:** Workflow (one PowerShell step, no AI) | **Version:** 1.1.0

## Files

Each version is published as a release, with `add-cc-to-ticket.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/add-cc-to-ticket/v1.1.0).

| What | Link |
|---|---|
| Download `add-cc-to-ticket.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/add-cc-to-ticket/v1.1.0) |
| View the current source | [`add-cc-to-ticket.yml`](https://github.com/cloudradial/Automations/blob/main/add-cc-to-ticket/add-cc-to-ticket.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/add-cc-to-ticket/src) |
| All files in this automation | [add-cc-to-ticket](https://github.com/cloudradial/Automations/tree/main/add-cc-to-ticket) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/add-cc-to-ticket) |

## How it works

A CloudRadial service-request form asks for a ticket number and an email address, and its Automation Webhook posts them to this workflow together with who submitted the form. One step, **Add CC to ticket**, then:

1. **Checks the request.** It needs a ticket number and exactly one email address. With `allowed_domains` set, the address must be in one of those domains. Nothing is called until these pass.
2. **Reads the ticket** through the shared six-PSA adapter (`_shared/psa.ps1`): its company, its contact's email address and its current CC list.
3. **Checks the ticket belongs to the requester** (see [The ownership rule](#the-ownership-rule)). If it doesn't, the run ends with `status: rejected` and nothing changes.
4. **Adds the address** to the ticket's CC list, then reads the ticket again to confirm the address is there. If it was already on the list (or is the ticket's contact), the run ends with `success`, "nothing changed", and no note.
5. **Leaves an internal note**, for example "Added alex.wilber@contoso.com to the email CC list at the request of megan.bowen@contoso.com (self-service form).", and reads the notes back to confirm it saved. A note that fails becomes a warning; the CC is already added.
6. **Tells the new CC what the ticket is about** with one public note, for example "alex.wilber@contoso.com has been copied on ticket 1001, "Printer offline" at the request of megan.bowen@contoso.com, and will now receive email updates on it. To add information, reply to any update email." The PSA emails it to the ticket's contact and CC list, so the person just added learns why they are getting updates. It never includes internal notes. Send `"notify_cc": false` to skip it. A public note that fails becomes a warning.

It never changes the ticket's status, owner, contact or anything else, and the only client-visible note it writes is the one telling the new CC what the ticket is about. `"preview": true` returns what it would do (`status: pending_confirmation`) and changes nothing.

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

**Download the workflow:** [`add-cc-to-ticket.yml`](https://github.com/cloudradial/Automations/releases/tag/add-cc-to-ticket/v1.1.0)

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

A missing secret stops the run with a sentence naming it.

## Required Graph permissions

None. This workflow doesn't call Microsoft Graph.

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
| `notify_cc` | No (default `true`) | Adds the public note that tells the new CC what the ticket is about. `false` adds the CC with the internal note only. |
| `preview` | No (default `false`) | `true` returns what would happen and changes nothing. `dryRun` works too. |
| `psa` | No | Overrides the `PSA-Type` secret. |

The ticket number and address are read from the body first, then from the form's answers (`Ticket.Questions` by question Id). A value left as a literal `@token` counts as missing. On a CloudRadial **Action** the input is different. See [Form setup](#form-setup).

## Output

`status` (`success`, `rejected`, `error` or `pending_confirmation`), `message` (one plain sentence), `ticket_id`, `cc_email`, `added`, `cc_list` (the CC list after the change; empty when the request was refused), `actions`, `warnings`, `internal_note` (the note written, or why nothing was) and `public_note` (the public note written to the new CC; empty when none was). An `error` also fails the step, so it shows in the run history. Setup problems are errors: no ticket number, no address to add, more than one possible answer, or no `requester_email` / `company_psa_id`. Each message says what to fix. A `rejected` run is the rules working (not their ticket, a bad address, a domain not allowed) and doesn't fail the step.

## Form setup

### With an Action (portals with Actions)

Add a question of type **Action** at the end of the form and pick **Add CC to Ticket**. There's nothing to map. The portal sends each answer under its Field ID, plus its own `ticket`, `company` and `user` objects:

- **Which ticket:** with a **Ticket number** question, that ticket. Without one, the ticket the form itself creates. That suits a form like *Reset Password* that also asks who to copy.
- **Field IDs don't have to match.** `ticketNumber` and `ccEmail` are read first. Failing those, the one answer whose Field ID mentions "ticket" and looks like a ticket number is the ticket, and the one answer whose Field ID mentions "mail" or "cc" and is a single email address (not the submitter's own, and never `userPrincipalName`) is the address. So the Field IDs the portal makes from the labels, such as `emailAddressToAdd`, work. Two different possible answers stop the run with an error naming both Field IDs.
- **Left blank:** on the form's own ticket, the email question is optional. Left blank, the run succeeds and nobody is added. On an existing ticket (a ticket number question), a missing address is an error.
- **Who's asking and their company:** only from the portal's `user.email` and `company.psaId`. The ownership rule applies as usual, so on the form's own ticket the requester is its contact.
- **The switches** (`technician_run`, `allow_company_colleagues`, `allowed_domains`, `notify_cc`, `preview`, `psa`) can't be set from an Action, and a form answer with one of those Field IDs is ignored. An Action run uses the defaults: contact or CC only, any domain, public note on, live. If you need `allowed_domains`, use the Webhook activity below.

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
2. **Preview first.** In **Run**, use the step's Test Input with a real ticket number, its company's PSA id, the ticket contact's email as `requester_email`, and your own address as `ccEmail`. Keep `"preview": true`. Expect `status: pending_confirmation` and nothing changed on the ticket.
3. **Refusals.** Change `company_psa_id` to another company: expect `rejected` and "isn't one you can change". Change `requester_email` to someone who isn't on the ticket: expect `rejected`.
4. **Add.** Remove `preview`. Expect `success`, your address on the ticket's CC list in the PSA, an internal note, and a public note naming the ticket (you get it by email as the new CC). Run it again: expect "already on the CC list" and no second note.
5. **Wire the form.** Enable the webhook in **Properties** (AutomationAI issues the URL and secret), redeploy, and set up the form as above. Submit it from the portal as the ticket's contact, then check the run history and the ticket.

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. The step logic lives in `src/`: edit `step.ps1` (reading the body), `cc.ps1` (each PSA's contact and CC calls) or `add-cc.ps1` (the step), run `node src/build.js` (it pastes in `_shared/psa.ps1`), then `pwsh -NoProfile -File src/test.ps1` (strict mode, mocked PSAs). Never edit the `.yml` by hand.

## Tested

Mocked PSAs, in strict mode (`src/test.ps1`, 130 checks), plus live runs on ConnectWise from a CloudRadial form Action on DV (2026-10-19, the form's own ticket).

- Adding a CC on ConnectWise, Autotask, HaloPSA, Kaseya BMS and Zendesk, including each PSA's request shape, keeping the CCs already on the ticket, the read-back, the internal note and the public note to the new CC (on the Discussion tab in ConnectWise, a public comment in Zendesk), and `notify_cc: false`.
- Syncro refused with a plain sentence and no calls.
- Already on the list (any letter case), already the contact, and a ConnectWise ticket with the CC checkbox off.
- Ownership: wrong company (the message reveals nothing), a ConnectWise company identifier in place of its id, requester not the contact or a CC, requester already a CC, `allow_company_colleagues` (and that it never crosses companies), missing `requester_email` or `company_psa_id`, `technician_run`.
- Invalid addresses, `mailto:`, `allowed_domains`, bad or missing ticket numbers.
- Preview on three PSAs changes nothing; a preview of someone else's ticket is still refused.
- Autotask refuses an address that isn't a company contact.
- PSA errors carry the PSA's own text and no secrets; a missing secret is named; a write the PSA accepts but doesn't keep (Zendesk CCs off) is an error; a write answered with a redirect is read back and never resent.
- A refused note, or notes that can't be read back, become warnings.
- Literal `@tokens` count as missing; the CloudRadial `Ticket.Questions` shape (`Answer` or `Value`); `Ticket.TicketId` is never used as the target; ownership fields typed into form answers are ignored.
- Field IDs the portal makes from labels (`emailAddressToAdd`, `whichTicket`), two different email answers (an error naming both), the requester's own address and `userPrincipalName` never picked as the address, a blank optional question on the form's own ticket, and setup problems failing the step.

### Not yet proven live

Every PSA call in `src/cc.ps1` except ConnectWise (marked `Unverified`), in particular the Autotask additional-contacts write, the HaloPSA `emailcclist` update, the Kaseya BMS `Ccs` patch, and Zendesk `email_ccs`. Check the first run with `preview` and then on a test ticket.
