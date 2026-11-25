# Move HaloPSA Ticket Templates into CloudRadial Request Forms

Turn every HaloPSA ticket template into a CloudRadial request form that raises the same kind of ticket, asking only what a requester needs to answer, so moving to the UCP portal doesn't mean rebuilding your forms by hand.

## What happens

Your team runs it in AutomationAI, a few templates at a time:

- **It reads your Halo templates:** each one's ticket type, team, priority and the custom fields it uses.
- **AI drafts the form.** It keeps the questions a requester should answer and leaves out technician-only fields such as asset tags or billing codes. It also writes friendly labels, short hints and a one-line description.
- **The forms are created in your own company**, as Service Requests or Problem Reports, each ending with an "Anything else we should know?" box that becomes the ticket description.
- **You review them, then publish** them to your clients through a Partner Content package.

Your clients then see familiar request forms in the portal, and each submission becomes the right Halo ticket through [Create a Halo Ticket from a Template](https://github.com/cloudradial/Automations/tree/main/create-halo-ticket-from-template).

## What it protects

- **Preview first.** The first run creates nothing and lists each form it would make, with its questions.
- **Halo has the final say.** Every field Halo makes mandatory is on the form and required, the question types come from Halo rather than the AI, and a field the AI invents is dropped.
- **Nothing is changed in Halo,** and no existing CloudRadial form is changed or deleted.
- **No duplicates.** Each form is tagged with its Halo template, so a rerun skips templates already moved.

## Works with

- **HaloPSA** and the CloudRadial portal.
- **Proven live:** three Halo templates moved into forms, and a client's submission of a migrated form created the right Halo ticket.
- **Not yet proven on other Halo setups:** templates that use parts of Halo the tested templates didn't. Preview a few templates first.

## What you need

- AutomationAI, with your Halo API details and your CloudRadial API keys on the runner
- [Create a Halo Ticket from a Template](https://github.com/cloudradial/Automations/tree/main/create-halo-ticket-from-template), which turns each submission into the Halo ticket

## Set it up

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases?q=halo-template-migration&expanded=true).
2. Go to **Workflows > Import** and upload it.
3. Add your Halo and CloudRadial details to the runner. The [technical details](https://github.com/cloudradial/Automations/tree/main/halo-template-migration#required-runner-key-vault-secrets) list exactly what to add.
4. Click **Publish**, then **Deploy**.
5. **Preview** two or three templates into your own company. Then run it again to create them, and review the new forms in the portal.
6. On each new form, add an **Action** question and pick **Create a Halo Ticket from a Template**.
7. Run it again until every template is moved, then add the forms to a package under **Partner > Content** and **Publish** it.

**Test it.** Submit one migrated form, then check the Halo ticket's type, team, priority and custom fields, and that there's only one ticket.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/halo-template-migration#technical-details) cover how templates map to forms, how tickets reach Halo, every run setting, and what has been proven live.

---

## Technical details

**Marketplace ID:** AAI-00081 | **Type:** Workflow (PowerShell steps plus one AI Prompt step) | **Version:** 1.0.1

## Files

Each version is published as a release, with `halo-template-migration.yml` attached. Download the latest from the [**releases page**](https://github.com/cloudradial/Automations/releases?q=halo-template-migration&expanded=true).

| What | Link |
|---|---|
| Download `halo-template-migration.yml` (all versions) | [Releases](https://github.com/cloudradial/Automations/releases?q=halo-template-migration&expanded=true) |
| View the current source | [`halo-template-migration.yml`](https://github.com/cloudradial/Automations/blob/main/halo-template-migration/halo-template-migration.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/halo-template-migration/src) |
| All files in this automation | [halo-template-migration](https://github.com/cloudradial/Automations/tree/main/halo-template-migration) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/halo-template-migration) |

## How it works

Three steps. Only step 2 uses AI, and it can't call any tools.

1. **Read the Halo templates (no AI).** Reads your HaloPSA ticket templates, then for each one:
   - its ticket type, priority, category, team and status names
   - the custom fields of its ticket type (Halo names them `CF...`), with their kind and list values

   Built-in fields (summary, details, user, site and so on) and fields the template already fills in aren't asked. Templates already moved into the CloudRadial company are skipped, and so are inactive ones and templates named like a form that's already there.
2. **Draft the forms (AI Prompt).** One AI call decides which custom fields a requester should answer, leaving out technician-only fields such as asset tags or billing codes. It also gives each kept field a friendly label and an optional hint, and writes a one-line description of each form.
   - No model is pinned, so the tenant's own provider is used.
   - Template text is treated as data, never as instructions.
3. **Create the forms.** Each form is checked against what Halo returned:
   - A field the AI names that the template doesn't have is dropped.
   - Required Halo fields are always asked.
   - The question types always come from Halo, never from the AI.
   - **Ticket routing uses CloudRadial's tokens by default** (`@DefaultBoard`, `@DefaultStatus`, `@DefaultPriority`, and a blank type), so Halo always accepts the ticket. With Halo's names on the form, Halo can reject the ticket, and the submitter still sees "submitted" (see CloudRadial's [Troubleshooting: Service Ticket Failures in HaloPSA](https://support.cloudradial.com/hc/en-us/articles/22172314482068-Troubleshooting-Service-Ticket-Failures-in-HaloPSA)). Each question's Field ID (`jsonId`) is the Halo custom field name. **Every field Halo makes mandatory is on the form and required**, including fields hidden from end users that are mandatory on Halo's agent new-ticket screen. Set `psaValues: "halo"` to put Halo's names on the form instead.
   - **How the ticket reaches Halo** depends on `ticketRoute`. See [Getting the ticket into Halo](#getting-the-ticket-into-halo).

   Every form ends with an "Anything else we should know?" box, which becomes the ticket description.
   - **`confirm` false (the default):** nothing is created. The run lists the planned forms and their questions (`status: pending_confirmation`).
   - **`confirm` true:** each form is created with its questions in one call, and tagged `halo-template:<id>` so a rerun skips it.

| Halo | CloudRadial form |
|---|---|
| Template name | Form name (subject) |
| Template group, else ticket type name | Category (or the `category` input) |
| Template details | Form description (scripts and event handlers removed) |
| Incident-style ticket type | Problem Report; anything else is a Service Request (or set `usage`) |
| Ticket type, priority, `category_1`, team, status | By default, CloudRadial's tokens (`@DefaultBoard`, `@DefaultStatus`, `@DefaultPriority`, and a blank type and category). With `psaValues: "halo"`, Halo's own names. |
| Custom field name (for example `CFcostCentre`) | The question's Field ID (`jsonId`), which the Create a Halo Ticket workflow reads. `customFieldName` is set too. |
| Field mandatory in Halo (on the end-user or agent new-ticket screen) | A required question, even when Halo hides the field from end users |
| Text, memo, date, checkbox and number fields | Text, memo, date, checkbox and number questions |
| Single and multiple choice fields | Dropdown and multi-select questions, with the Halo values as options |

Nothing is ever written to Halo, and an existing CloudRadial form is never changed or deleted.

### Getting the ticket into Halo

CloudRadial's own ticket submission can't fill Halo **custom fields**. When a Halo ticket type makes a custom field mandatory, Halo rejects the ticket ("First Name is mandatory"), the requester still sees "submitted", and you get a Failed Ticket Advisory. So by default the forms are built for AutomationAI to create the ticket:

- **`ticketRoute: "automationai"` (the default).** The forms are made for [Create a Halo Ticket from a Template](https://github.com/cloudradial/Automations/tree/main/create-halo-ticket-from-template). Attach that workflow as each form's **AutomationAI Action**. It creates the Halo ticket the way the template would: ticket type, team, priority and status, with every answer in its custom field.
  - The forms are created with Send to PSA off, through the API. The form editor has no such switch.
  - If CloudRadial still sends the ticket, Halo rejects it when a custom field is mandatory, you get a Failed Ticket Advisory, and the Action still creates the real ticket.
  - For a form with **no** mandatory custom field, Halo could accept both, so check the first submission from each form for a duplicate ticket.
- **`ticketRoute: "psa"`.** CloudRadial's own submission only, with no AutomationAI. Use it only when the templates have no mandatory custom fields, or after making those fields not required in Halo. The run warns about each template that would be rejected.

### Getting the forms to every client

The CloudRadial API creates forms inside one company. It can't add them to a Partner Content package. So:
1. Run this into **your own company** (for example the one your team uses in the portal).
2. Review the forms there.
3. Add them to a package in **Partner > Content > Service Requests** (or **Problem Reports**), and **Publish** it.

## Download & import

**Download the workflow:** [`halo-template-migration.yml`](https://github.com/cloudradial/Automations/releases?q=halo-template-migration&expanded=true)

Then in AutomationAI:
1. **Workflows → Import**, and upload the `.yml`.
2. Add the [required secrets](#required-runner-key-vault-secrets) to the runner.
3. **Publish** and **Deploy**.

Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

By name only. The Halo names are the same as the `halo-psa` catalog extension's, so one set serves both.

| Secret | For |
|---|---|
| `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Reading HaloPSA |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Reading the company and creating the forms |

**HaloPSA permissions:** the API application needs to read ticket templates, ticket types, custom fields, priorities and statuses. A missing permission stops the run with a plain message naming it, before anything is created.

## Required Graph permissions

None. This workflow only talks to HaloPSA and CloudRadial.

## Inputs

| Field | Required | Meaning |
|---|---|---|
| `companyId` | Yes | The CloudRadial company the forms are created in. |
| `confirm` | No (default `false`) | `true` creates the forms. `false` creates nothing and lists what it would create. `approvedToWrite` works too. |
| `templateIds` | No | Halo template numbers to move, as a list or comma-separated. Without it, every template is considered. |
| `search` | No | Only templates whose name matches, using Halo's own search. |
| `maxTemplates` | No (default 10, up to 25) | Templates per run. Run it again for the next batch; already-moved ones are skipped. |
| `includeInactive` | No (default `false`) | Also move templates Halo marks inactive. |
| `usage` | No (default `auto`) | `request` or `problem` puts every form in that list. `auto` decides by ticket type. |
| `category` | No | One category for every form, instead of the template group or ticket type. |
| `ticketRoute` | No (default `automationai`) | `automationai` builds the forms for the Create a Halo Ticket Action. `psa` relies on CloudRadial's own submission. See [Getting the ticket into Halo](#getting-the-ticket-into-halo). The older `sendToPsa: true` means `psa`. |
| `psaValues` | No (default `tokens`) | `tokens` puts CloudRadial's tokens in the ticket routing fields, so Halo always accepts the ticket. `halo` puts Halo's ticket type, team, priority, status and custom-field names on the form directly. Use `halo` only after a test submission shows Halo accepts them. |

It accepts a flat JSON body, or one wrapped in `{trigger: ...}`.

## Output

| Field | Meaning |
|---|---|
| `status` | `success`, `pending_confirmation`, `incomplete` or `error` |
| `message` | What happened, in a sentence |
| `forms` | One row per template: the template id and name, Service Request or Problem Report, category, action (`planned`, `created`, `skipped`, `incomplete` or `error`), the CloudRadial form id, the question count and a note |
| `remaining` | Templates left for the next run |
| `counts` | `formsCreated`, `questionsCreated`, `formsPlanned`, `formsSkipped` and `formsFailed` |
| `actions`, `warnings` | What ran, and anything to check |

## Import & test

1. Import `halo-template-migration.yml`, add the secrets above to the runner vault, then **Publish** and **Deploy** to that runner.
2. **Preview first.** Run the first step's Test Input with your company number, two or three `templateIds` and `"confirm": false`. Expect `status: pending_confirmation` and each planned form's questions in `forms`.
3. **Create.** Run again with `"confirm": true`. Then:
   - Open the new forms in the portal.
   - With the default route, attach Create a Halo Ticket from a Template as each form's AutomationAI Action.
   - Submit one, and check the Halo ticket has the right ticket type, priority, category and team, every custom field filled, and no duplicate ticket.
4. **Rerun.** Run once more. Expect "Nothing new to move" and nothing created.
5. **Move the rest.** Run without `templateIds` until `remaining` is 0, then add the forms to a package and publish it.

> The step logic lives in `src/`: edit `read.ps1`, `create.ps1` or the `judge.*.txt` prompts, then run `node src/build.js` (it pastes `_shared/psa.ps1` and `_shared/cloudradial.ps1`) and `pwsh -NoProfile -File src/test.ps1`. Never edit the `.yml` by hand.

### Proven live

- **A live migration (run 028dcce8, 2026-10-16).** It read three Halo templates and created three forms with 17, 3 and 3 questions. Every option list, hint and the description flag were saved, and the PSA values and `halo-template:<id>` tags were set.
- **The CloudRadial create call:** `POST /v2/catalog` with inline questions and tags, followed by one update per question (the create alone keeps only each question's label, type and order).
- **Tickets from the migrated forms.** Halo's own names on a form (`psaValues: "halo"`) created no Halo ticket (2026-10-19), so tokens are now the default (#141). With tokens, a client submitted the migrated "New Starter Request" form on 2026-11-03 and [Create a Halo Ticket from a Template](https://github.com/cloudradial/Automations/tree/main/create-halo-ticket-from-template) created Halo ticket 14956 from the matching template.

### Not yet proven live

- **Halo property names beyond the templates tested.** The reads use the calls the HaloAPI PowerShell module uses (`/Template`, `/TicketType`, `/Field`, `/Priority`, `/Status`). They worked for the three templates in run 028dcce8, but `src/read.ps1` still marks these as `Unverified` for other Halo setups:
  - the template's ticket type, priority, category, team, status and group
  - the ticket type's field list and field groups
  - the field type numbers
  - the inactive flag
- **Send to PSA off, set through the API.** Whether CloudRadial always respects it, so a submission raises only the workflow's ticket, isn't confirmed yet.
