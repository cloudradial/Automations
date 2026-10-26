# Create a Halo Ticket from a Template

When a client submits a CloudRadial request form, the HaloPSA ticket is created exactly as its Halo ticket template would create it: the right ticket type, team, priority and status, with every answer in its Halo custom field. Halo's mandatory fields no longer reject the ticket.

**Marketplace ID:** TBD | **Type:** Workflow (one PowerShell step, no AI) | **Version:** 1.0.0

## Files

Each version is published as a release, with `create-halo-ticket-from-template.yml` attached. Download the latest from the [**releases page**](https://github.com/cloudradial/Automations/releases?q=create-halo-ticket-from-template&expanded=true).

| What | Link |
|---|---|
| Download `create-halo-ticket-from-template.yml` (all versions) | [Releases](https://github.com/cloudradial/Automations/releases?q=create-halo-ticket-from-template&expanded=true) |
| View the current source | [`create-halo-ticket-from-template.yml`](https://github.com/cloudradial/Automations/blob/main/create-halo-ticket-from-template/create-halo-ticket-from-template.yml) |
| Step source, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/create-halo-ticket-from-template/src) |
| All files in this automation | [create-halo-ticket-from-template](https://github.com/cloudradial/Automations/tree/main/create-halo-ticket-from-template) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/create-halo-ticket-from-template) |

## Why it exists

CloudRadial's own ticket submission sends a form's answers in the ticket description, but it can't fill Halo **custom fields**. When a Halo ticket type makes custom fields mandatory, Halo rejects the ticket ("First Name is mandatory"), and the client still sees "submitted". CloudRadial then sends a Failed Ticket Advisory, and no ticket exists.

This workflow creates the ticket through Halo's API instead. Use it with the forms made by [Move HaloPSA Ticket Templates into CloudRadial Request Forms](https://github.com/cloudradial/Automations/tree/main/halo-template-migration). Each question's Field ID there is the Halo custom field name.

## How it works

One PowerShell step, no AI.

1. **Reads the submission.** It takes CloudRadial's form payload (`User`, `Company`, `Ticket` with its `Questions`), a flat body, or either one wrapped in `{trigger: ...}`.
   - **Answers:** found by each question's Field ID. A token nobody filled (`@CFfirstName`) counts as missing.
2. **Finds the Halo template.** It uses the form's `haloTemplateId` answer or a `templateId` input. Failing that, it looks for the template whose name the form's subject starts with.
3. **Reads Halo.** It reads the template, its ticket type, the ticket type's field groups, and each custom field's definition and list values.
4. **Maps the answers.**
   - Text, memo and date answers go in as written.
   - A list answer becomes the matching Halo option. An option Halo doesn't have is a warning.
   - A checkbox becomes true or false.
   - **Missing mandatory answers:** if Halo makes a field mandatory and the form didn't answer it, nothing is created and the run names the field.
   - **Mandatory built-in fields:** a form can't fill one (for example Delivery Address), so it's a warning that names the Halo setting to change.
5. **Creates the ticket.** It uses the template's ticket type, priority, status, team and category, under the client (`CompanyPsaId`) and the user (`UserPsaId`, or the email as reported-by), with the custom fields filled in.
   - **A form submission** creates the ticket.
   - **A manual run** previews it (`status: pending_confirmation`) unless `confirm` is true.

## Set it up

1. **Import and deploy.** Import `create-halo-ticket-from-template.yml`, add the Halo secrets below to the runner vault, enable the webhook in **Properties**, then **Publish** and **Deploy**.
2. **Set up the forms.** On each form made from a Halo template:
   - turn **Send to PSA** off, so CloudRadial doesn't also try to create the ticket
   - attach this workflow as the form's **AutomationAI Action**. Actions run on every submission, whether or not the form sends to the PSA.
3. **Test it.** Submit the form once, and check the Halo ticket's type, team, priority and custom fields.

## Required runner Key Vault secrets

By name only.

| Secret | For |
|---|---|
| `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret` | Reading templates and fields, and creating tickets. The Halo API application needs to read ticket templates, ticket types, field groups and custom fields, and to create tickets. |

## Required Graph permissions

None.

## Inputs

| Field | Required | Meaning |
|---|---|---|
| The form submission | Yes | CloudRadial's payload: `User.UserPsaId`, `User.UserEmail`, `Company.CompanyPsaId`, `Ticket.TicketSubject`, `Ticket.TicketDescription`, `Ticket.Questions` |
| `haloTemplateId` (a form answer) or `templateId` | No | The Halo template. Without it, the form's subject is matched to a template name. |
| `companyPsaId`, `userPsaId`, `userEmail`, `subject`, `description`, `fields` | No | The same values as a flat body, for a manual run. `fields` holds the answers by Halo field name. |
| `confirm` | No | A form submission creates the ticket. A manual run creates it only with `true`. |

## Output

| Field | Meaning |
|---|---|
| `status` | `success`, `pending_confirmation`, `incomplete` or `error` |
| `message` | What happened, in a sentence |
| `ticket_id` | The new Halo ticket number |
| `ticket` | The ticket that would be created (preview only) |
| `counts` | `ticketsCreated` and `fieldsFilled` |
| `actions`, `warnings` | What ran, and anything to check |

> The step logic lives in `src/create.ps1`. Run `node src/build.js` (it pastes `_shared/psa.ps1`) and `pwsh -NoProfile -File src/test.ps1` after changing it. Never edit the `.yml` by hand.

### Not yet proven live

- **The read side is proven.** The Halo template, ticket type, field group and custom field reads use the shapes proven by the migration workflow against a live Halo (2026-10-16 to 10-19), including "Visible - Required" being 3.
- **The ticket create is not proven yet.** That covers:
  - the custom field shape (`{id, name, value}`)
  - list values (the option id, and several ids joined with commas)
  - checkboxes (`true`/`false`)

  The first live submission will confirm them.
- **The AutomationAI Action payload** is assumed to be CloudRadial's form JSON. A flat body works too.
- **A retried submission can create a second ticket.** Check Halo before resubmitting a failed run.
