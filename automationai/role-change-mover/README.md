# Move a User to a New Department Without Missing Any Access

When someone changes department, their Microsoft 365 groups, department, title and manager are brought in line with your department map in one run, and you see every add and remove before anything changes.

**Formerly:** Role change (mover) | **Marketplace ID:** TBD | **Type:** Workflow

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `role-change-mover.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/role-change-mover/role-change-mover.yml) |
| Download `role-change-mover.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/role-change-mover/role-change-mover.yml) |
| Download the **Role Change: Department Map** KB article (paste into your portal) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/role-change-mover/kb-articles/role-change-department-map.txt) |
| Download `department-map-template.csv` (to build the map in Excel) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/role-change-mover/department-map-template.csv) |
| Source, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/automationai/role-change-mover/src) |
| All files in this automation | [automationai/role-change-mover](https://github.com/cloudradial/Automations/tree/main/automationai/role-change-mover) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/role-change-mover) |

## How it works

Two PowerShell steps. No AI is involved: the department map decides everything.

1. **Read the request, department map and user.** Reads your department map from a CloudRadial KB article, then reads the user, their manager, their direct group memberships and their licences from Microsoft Graph. It looks up every group the old and new departments name, and works out the plan. It writes nothing.
2. **Preview or apply, then note the ticket.** With `confirm` false (the default) it changes nothing and returns the plan. With `confirm` true it makes the changes in order and stops at the first failure, saying what ran and what didn't. Either way it adds an internal note to the ticket when you give a `ticket_id`.

The plan holds:

| Item | What happens |
|---|---|
| Groups to add | The new department's security and Microsoft 365 groups the user isn't in yet. |
| Groups to remove | The old department's groups the user is in, except any the new department also lists. |
| Department and title | The user's `department` is set to `new_department`, and `jobTitle` to `new_title` when you give one. |
| Manager | Set to `new_manager_upn` when you give one and it differs from the current manager. |
| Licences | **Flagged only, never changed.** The new department's `license_sku` values the user doesn't have, and the old department's that the new one doesn't use. |
| Change in Exchange | Distribution lists and mail-enabled security groups that need adding or removing. See below. |
| Change by hand | Dynamic groups (their membership follows the user's attributes) and groups synced from on-premises Active Directory. |

### Distribution lists and mail-enabled security groups

Microsoft Graph can't change the membership of distribution lists or mail-enabled security groups. The workflow spots them from what Microsoft 365 reports (mail-enabled and not security-enabled, or mail-enabled security), whatever `kind` the map gives, and lists them under **Change in Exchange** in the output and the ticket note instead of failing. A technician makes those changes in the Exchange admin center or with Exchange Online PowerShell. The workflow doesn't use the Exchange Online extension, so it works on runners that don't have its secrets.

If the map's `kind` disagrees with Microsoft 365, the run uses what Microsoft 365 says and adds a warning.

## The department map

The map is a CSV pasted into a CloudRadial KB article titled **Role Change: Department Map**. Keep it in the company whose id is in the `DepartmentMap-CompanyId` secret. An MSP that doesn't want client users to read group names can keep the article in its own MSP company and give each client's article its own title (set `DepartmentMap-ArticleTitle`).

```
department,group,kind,license_sku
Sales,Sales Team,security,
Sales,sales@contoso.com list,distribution,
Marketing,Marketing Team,m365,
Marketing,,,Microsoft_365_Business_Premium
```

| Column | What to put |
|---|---|
| `department` | The department name, as you want it on the user. Case and extra spaces don't matter when matching. |
| `group` | The group's display name, or its object id. Use the object id when two groups share a name. |
| `kind` | `security`, `distribution` or `m365`. Blank means "use what Microsoft 365 says". |
| `license_sku` | Optional. A SKU part number such as `SPE_E3`, or a SKU id. A row can hold only a licence, with `group` and `kind` blank. |

Start from the [KB article template](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/role-change-mover/kb-articles/role-change-department-map.txt) or [`department-map-template.csv`](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/role-change-mover/department-map-template.csv). Paste it as plain text, or as a table; a note above the header row is ignored.

**The run fails clearly, and changes nothing, when:**

- there's no article with that title in that company
- the table has no header row, a row has no department, or a `kind` isn't one of the three
- the new department isn't in the map
- a group named by the old or new department doesn't exist in Microsoft 365, or two groups share its name

Only the rows for the two departments in the request are checked against Microsoft 365 on each run.

## Download & import

**Download the workflow:** [`role-change-mover.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/role-change-mover/role-change-mover.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [secrets](#required-runner-key-vault-secrets), create the department map article, then publish and deploy. Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

This is a per-company workflow: it reads the secrets of the runner it's deployed to, so deploy it to the runner for that client.

| Secret | Required | Used for |
|---|---|---|
| `M365-TenantId`, `M365-ClientId`, `M365-ClientSecret` | Yes | Microsoft Graph sign-in (the `Entra-*` and `Graph-*` names also work) |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Yes | Reading the department map article |
| `DepartmentMap-CompanyId` | Yes | The CloudRadial company id that holds the department map article |
| `DepartmentMap-ArticleTitle` | No | The article's title, when it isn't `Role Change: Department Map` |
| `PSA-Type` | For ticket notes | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` |
| The PSA's own secrets (`CW-*`, `Autotask-*`, `Halo-*`, `KaseyaBMS-*`, `Syncro-*`, `Zendesk-*`) | For ticket notes | Adding the internal note. Same names as the PSA's catalog extension. Kaseya BMS also needs `KaseyaBMS-NoteTypeId`. |

If the note can't be added (no PSA set up, or the PSA refuses it), the run still returns the plan or result and adds a warning.

## Required Microsoft Graph permissions

Application permissions on the app registration, with admin consent:

| Permission | Why |
|---|---|
| `User.ReadWrite.All` | Read the user, manager and licences; set department, title and manager |
| `GroupMember.ReadWrite.All` | Add and remove group members |
| `Group.Read.All` | Look up groups by name or id and read the user's memberships |

A missing permission stops the run with a sentence naming it.

## Inputs

Send a flat JSON body, or the CloudRadial `{Ticket:{TicketId, Questions:[{Id, Value}]}}` shape (each question's Field ID is the input name). A value that is blank, or still a literal `@token` or `{{field}}`, counts as missing.

| Input | Default | Meaning |
|---|---|---|
| `upn` | required | The user who is moving (UPN or object id) |
| `new_department` | required | Their new department. Must be in the map. |
| `new_title` | keep current | Their new job title |
| `new_manager_upn` | keep current | Their new manager's UPN |
| `old_department` | the user's current Microsoft 365 department | The department whose groups are removed |
| `confirm` | `false` | `false` previews and changes nothing. `true` applies the plan. |
| `psa` | secret `PSA-Type` | Which PSA holds the ticket |
| `ticket_id` | none | The ticket that gets the internal note |
| `company_tenant_id` | none | Optional `@CompanyTenantId`. When it and `M365-TenantId` are both GUIDs and differ, the run is rejected. |
| `map_article` | secret `DepartmentMap-ArticleTitle`, then `Role Change: Department Map` | The department map article's title |
| `company_id` | none | The map's company id, used only when the `DepartmentMap-CompanyId` secret isn't set |

**From a portal form, always send `confirm: false`.** The form posts a preview to the ticket, and a technician reruns the workflow with `confirm: true` once the plan looks right.

## Output

```json
{ "status": "pending_confirmation | success | incomplete | rejected | error",
  "message": "...", "public_note": "...", "internal_note": "...", "ticket_id": "...",
  "planned": [...], "ran": [...], "not_run": [...], "failed": null,
  "exchange": [...], "manual": [...], "licenses": [...],
  "actions": [...], "warnings": [...], "chatReply": "..." }
```

Group, licence and manager details appear only in `internal_note` and the internal ticket note. `public_note` is a short, client-safe sentence. A run with `error`, `incomplete` or `rejected` keeps its output and is marked failed in the run history.

## Import & test

1. Create the **Role Change: Department Map** article from the template, with your real departments and groups.
2. In AutomationAI, **Workflows → Import** `role-change-mover.yml`.
3. Add the [secrets](#required-runner-key-vault-secrets) to the client's runner Key Vault and grant the [Graph permissions](#required-microsoft-graph-permissions).
4. **Publish** and **deploy** to that runner.
5. Open the first step's **Test Input**, set `upn` to a test user and `new_department` to a department in your map, keep `confirm` as `"false"`, and run it. Check the planned adds and removes, the Exchange items and the licence flags in the output and the ticket note.
6. Run again with `confirm` as `"true"` to apply. Rerunning afterwards should report that the user already matches the map.
7. To start it from the portal, turn on the webhook under **Properties → Webhook** (it mints the URL and secret), redeploy, and add a Webhook activity to the form's Automation that posts the inputs with the `X-Crauto-Webhook-Secret` header.

> Webhook secrets are stripped from this export, so the portal issues a new URL and secret on import. A run with `confirm` true changes the user's groups, department, title and manager; test against a user you own.

## Build from source

Edit `src/*.ps1` (or the libraries in `automationai/_shared`), never the `.yml`:

```
node automationai/role-change-mover/src/build.js            # rebuild the .yml and the KB article template
pwsh -NoProfile -File automationai/role-change-mover/src/test.ps1
```

The harness runs both steps from the built `.yml` under strict mode with a mocked Key Vault, CloudRadial, Graph and PSAs (ConnectWise, Autotask, HaloPSA and Zendesk notes). js-yaml comes from `automationai/_shared/node_modules` (`npm install` there) or `JS_YAML_PATH`.
