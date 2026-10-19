# Move HaloPSA Ticket Templates into CloudRadial Request Forms

Every HaloPSA ticket template becomes a CloudRadial Service Request or Problem Report form that raises the same kind of ticket, with the questions a requester actually needs to answer, so moving to the CloudRadial portal doesn't mean rebuilding your forms by hand.

**Marketplace ID:** TBD | **Type:** Workflow (PowerShell steps plus one AI Prompt step) | **Version:** 1.0.0

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
   - **Ticket routing uses CloudRadial's tokens by default** (`@DefaultBoard`, `@DefaultStatus`, `@DefaultPriority`, and a blank type), so Halo always accepts the ticket. With Halo's names on the form, Halo can reject the ticket, and the submitter still sees "submitted" (see CloudRadial's [Troubleshooting: Service Ticket Failures in HaloPSA](https://support.cloudradial.com/hc/en-us/articles/22172314482068-Troubleshooting-Service-Ticket-Failures-in-HaloPSA)). Each answer keeps its Halo field name as its `jsonId`, so an AutomationAI automation can apply the template's ticket type, team, priority and custom fields after the ticket exists. Set `psaValues: "halo"` to put Halo's names on the form instead.

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
| Custom field name (for example `CFcostCentre`) | The question's `jsonId`. It's also the question's `customFieldName` only with `psaValues: "halo"`. |
| Text, memo, date, checkbox and number fields | Text, memo, date, checkbox and number questions |
| Single and multiple choice fields | Dropdown and multi-select questions, with the Halo values as options |

Nothing is ever written to Halo, and an existing CloudRadial form is never changed or deleted.

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
| `sendToPsa` | No (default `true`) | `false` creates the forms without sending their tickets to the PSA. |
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
   - Submit one, and check the Halo ticket has the right ticket type, priority, category and team.
4. **Rerun.** Run once more. Expect "Nothing new to move" and nothing created.
5. **Move the rest.** Run without `templateIds` until `remaining` is 0, then add the forms to a package and publish it.

> The step logic lives in `src/`: edit `read.ps1`, `create.ps1` or the `judge.*.txt` prompts, then run `node src/build.js` (it pastes `_shared/psa.ps1` and `_shared/cloudradial.ps1`) and `pwsh -NoProfile -File src/test.ps1`. Never edit the `.yml` by hand.

### Not yet proven live

- **The Halo API calls** are the ones the HaloAPI PowerShell module uses (`/Template`, `/TicketType`, `/Field`, `/Priority`, `/Status`). **The property names are marked `Unverified` in `src/read.ps1`:**
  - the template's ticket type, priority, category, team, status and group
  - the ticket type's field list
  - the field type numbers
  - the inactive flag
- **The CloudRadial create call** was proven on a test form: `POST /v2/catalog` with inline questions and tags.
- **Halo's names on the form (`psaValues: "halo"`):** a test submission with them created no Halo ticket (2026-10-19), which is why tokens are the default. Applying the template's values to the ticket afterwards is a separate AutomationAI step. Check step 3 of Import & test before moving everything.
