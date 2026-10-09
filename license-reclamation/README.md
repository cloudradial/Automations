# Find Unused Microsoft 365 Licences and Show the Monthly Saving

Every month, each client's CloudRadial Planner board gets one card listing the paid Microsoft 365 licences nobody has used in 60 days, with an estimated monthly saving, so you can raise it at the next review. Nothing is removed automatically.

**Marketplace ID:** TBD | **Type:** Workflow (PowerShell, no AI, read-only in Microsoft 365)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `license-reclamation.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/license-reclamation/license-reclamation.yml) |
| Download `license-reclamation.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/license-reclamation/license-reclamation.yml) |
| Build source and test harness (`src/`) | [license-reclamation/src](https://github.com/cloudradial/Automations/tree/main/license-reclamation/src) |
| All files in this automation | [license-reclamation](https://github.com/cloudradial/Automations/tree/main/license-reclamation) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/license-reclamation) |

## How it works

A per-company AutomationAI workflow with three PowerShell steps and no AI, so it has no turn limit and works with any AI provider. It runs for the one company whose Microsoft 365 secrets are on the runner, and never puts one client's users on another client's card.

`Start → Read inputs → Find unused licences → Update Planner card → End`

1. **Read inputs** reads `days`, `price_overrides`, `company_id` and `preview`. A Routine sends no input, so every field has a default.
2. **Find unused licences** reads Microsoft 365 through Graph. It changes nothing.
   - It reads the tenant's subscriptions and every user's licences, account status and last sign-in (the latest of interactive, non-interactive and successful sign-ins).
   - When the app has Reports.Read.All, it also reads mailbox activity. A user who signed in long ago but still uses their mailbox is not listed.
   - A user is listed when they hold a paid licence and have not signed in or used their mailbox in `days` days, or have never done either. Accounts created within `days` days are skipped as too new to judge.
   - A **disabled** account that still holds a paid licence is always listed, as "Disabled but licensed".
   - Free and trial SKUs are ignored: a built-in list (such as `FLOW_FREE`, `POWER_BI_STANDARD`, `TEAMS_EXPLORATORY`) plus any SKU named free, viral or trial, or not assigned to users.
   - The saving uses a built-in table of Microsoft list prices (US dollars per user per month, annual commitment) for common SKUs such as `O365_BUSINESS_ESSENTIALS`, `O365_BUSINESS_PREMIUM`, `SPB`, `ENTERPRISEPACK`, `SPE_E3`, `SPE_E5` and `EXCHANGESTANDARD`. `price_overrides` replaces any of them. A SKU with no price shows "price unknown" and is left out of the total.
3. **Update Planner card** writes one CloudRadial Planner card on the company's board, with the subject **Reclaim unused Microsoft 365 licences** and the stable key `license-reclamation`.
   - Each month it updates the same card instead of adding another, even if someone renamed it.
   - The card says how many licences are unused and the estimated monthly and yearly saving, notes that prices are list estimates, then shows a table of user, licence, last sign-in and status (up to 50 users; the rest are in the run output).
   - It is created internal only (not client visible). If you make it visible, later updates leave that setting alone.
   - Priority is high when the saving is $100 a month or more, or a disabled account holds a licence. Otherwise it is medium.
   - When nothing is reclaimable, an existing card is updated to say so and marked completed. If there is no card yet, none is created.

### Which company the card goes to

The first of these that is set wins:

1. The run's `company_id` input.
2. The `CloudRadial-CompanyId` secret on the runner.
3. The CloudRadial company whose Microsoft 365 tenant id matches the tenant the runner signs in to.

If the chosen company is linked to a different Microsoft 365 tenant, the run stops and writes nothing.

### Output

`status` (`success`, `pending_confirmation` for a preview, `rejected` for bad input, `error`), `message` (a plain sentence), `internal_note`, `actions`, `warnings`, `companyId`, `companyName`, `cardAction` (`created`, `updated`, `would-create`, `would-update`, `none`), `productId`, `licenceCount`, `monthlySaving` and `users` (one entry per user with their licences, prices, last sign-in and last mailbox activity).

## Download & import

**Download the workflow:** [`license-reclamation.yml`](https://github.com/cloudradial/Automations/blob/main/license-reclamation/license-reclamation.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), then **Publish** and **Deploy** it to the runner that holds this company's Microsoft 365 secrets. Then attach the monthly Routine (see [Import & test](#import--test)). A Routine isn't part of the export, so it has to be added after every fresh import.

## Required runner Key Vault secrets

| Secret | What it is |
|---|---|
| `M365-TenantId` | The client's Microsoft 365 tenant id (`Entra-TenantID` and `Graph-TenantId` also work) |
| `M365-ClientId` | The app registration's client id (`Entra-ClientID` and `Graph-ClientId` also work) |
| `M365-ClientSecret` | The app registration's client secret (`Entra-ClientSecret` and `Graph-ClientSecret` also work) |
| `CloudRadial-BaseUrl` | Your CloudRadial API base URL |
| `CloudRadial-PublicKey` | CloudRadial API public key |
| `CloudRadial-PrivateKey` | CloudRadial API private key |
| `CloudRadial-CompanyId` | Optional. The CloudRadial company number this runner's tenant belongs to, so a Routine knows which board to use |

## Required Graph permissions

Application permissions on the app registration, with admin consent:

| Permission | Why | If it's missing |
|---|---|---|
| `AuditLog.Read.All` (with `User.Read.All`) | Last sign-in times. The tenant also needs Microsoft Entra ID P1 (included in Business Premium and E3/E5). | The run stops with a plain sentence naming the permission, or saying the tenant needs Entra ID P1. |
| `Organization.Read.All` (or `Directory.Read.All`) | The tenant's subscriptions and SKU names | The run stops with a plain sentence naming the permission. |
| `Reports.Read.All` | Optional. Mailbox activity | The run carries on with sign-in times only and says so on the card. |

If Microsoft 365 reports hide user names in the tenant, mailbox activity can't be matched to users. The card says so. To include it, turn off **Display concealed user, group, and site names in all reports** in the Microsoft 365 admin center under **Settings > Org settings > Reports**.

## Inputs

| Field | Default | What it does |
|---|---|---|
| `days` | `60` | How long a licence must go unused before it is listed (14 to 365). |
| `price_overrides` | none | A JSON map of SKU part number to monthly price, such as `{"SPB": 20.5, "SPE_E3": 33}`. Use your real cost or add a SKU the table doesn't know. |
| `company_id` | none | The CloudRadial company number, for a manual run. When blank, the `CloudRadial-CompanyId` secret or the tenant match is used. |
| `preview` | `false` | `true` works everything out and returns the result, but leaves the Planner card alone. |

**Why there's no `confirm` input:** this workflow never changes a licence or anything else in Microsoft 365. Its only write is the internal Planner card, which is updated in place, and a Routine sends no input, so a `confirm` that defaults to `false` would stop the monthly run from ever posting. Use `preview: true` to see the result first.

Example manual run: `{"days": 60, "company_id": 7, "preview": true}`

## Import & test

1. Import, add the secrets, then **Publish** and **Deploy** to the runner holding this company's Microsoft 365 secrets.
2. **Preview.** Run it from **Test** with `{"company_id": <company number>, "preview": true}`. The run ends with `status: pending_confirmation`, `cardAction: would-create` (or `would-update`), the user list in `users`, and no card written.
3. **Real run.** Run it again without `preview`. Check the company's CloudRadial Planner board for **Reclaim unused Microsoft 365 licences**. Run it a second time and confirm the same card was updated (`cardAction: updated`), not duplicated.
4. **Schedule it.** Attach a monthly **Routine** (for example 07:00 on the 1st). A Routine sends no input, so add the `CloudRadial-CompanyId` secret, or make sure the company's Microsoft 365 tenant id is set in CloudRadial.

Strict-mode test harness (mocked Key Vault, Graph and CloudRadial):

```
node license-reclamation/src/build.js --check
pwsh -NoProfile -File license-reclamation/src/test.ps1
```

## Editing it

The three PowerShell steps are generated. Edit `src/inputs.ps1`, `src/scan.ps1` or `src/card.ps1`, then run `node license-reclamation/src/build.js`. It writes the `.yml` and pastes in the shared Graph and CloudRadial libraries from [`_shared`](../_shared/). Never edit the scripts inside the `.yml`. The price and free-SKU tables are at the top of `src/scan.ps1`.
