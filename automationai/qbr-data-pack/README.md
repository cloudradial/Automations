# Have Every Client's QBR Numbers Ready on One Planner Card

Before a quarterly business review, one run gathers a client's device age and warranty picture, ticket trends from your PSA, Microsoft 365 licence usage, and expiring domains and certificates, and puts them on one internal CloudRadial Planner card for the vCIO. Nothing else is changed anywhere.

**Marketplace ID:** TBD | **Type:** Workflow (PowerShell, no AI, read-only except one internal Planner card)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `qbr-data-pack.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/qbr-data-pack/qbr-data-pack.yml) |
| Download `qbr-data-pack.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/qbr-data-pack/qbr-data-pack.yml) |
| Build source and test harness (`src/`) | [automationai/qbr-data-pack/src](https://github.com/cloudradial/Automations/tree/main/automationai/qbr-data-pack/src) |
| All files in this automation | [automationai/qbr-data-pack](https://github.com/cloudradial/Automations/tree/main/automationai/qbr-data-pack) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/qbr-data-pack) |

## How it works

A per-company AutomationAI workflow with five PowerShell steps and no AI, so it has no turn limit and works with any AI provider. It reads from CloudRadial, your PSA and (optionally) Microsoft 365, and writes one card. It never chains other automations, so nothing that can write runs as a side effect.

`Start → Read inputs → Read CloudRadial data → Read PSA ticket trends → Read Microsoft 365 licences → Post QBR-prep card → End`

1. **Read inputs** reads `company_id`, `quarter_days`, `preview`, `psa` and `psa_company_id`. A Routine sends no input, so every field has a default.
2. **Read CloudRadial data** finds the company, then reads only that company's records:
   - **Devices:** the count of workstations, servers and virtual machines; physical devices by age (under 3, 3 to 5, 5 to 7, 7 or more years, unknown); warranty expired, ending within 90 days, active or unknown; operating systems that no longer get security updates; devices that haven't checked in for 30 days; and how many workstations are due for replacement. Age, warranty, operating system support and "due for replacement" use the same rules as [Endpoint LifeCycle Manager](../endpoint-lifecycle-manager/) (age from the manufacture date, else the BIOS or processor date, shown as estimated).
   - **Planner:** how many other open cards are on the company's board.
   - **Domains** that have expired or expire within 60 days, and **certificates** that have expired or expire within 30 days.
3. **Read PSA ticket trends** counts this client's tickets opened and closed in the last `quarter_days` days and in the same span before it, the tickets open now, and the top 5 categories of the tickets opened this period. It works with ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk, using GET calls only.
   - The client is found in the PSA by `psa_company_id`, then by the PSA link on the CloudRadial company, then by an exact name match. If none matches, or no PSA is set up, this section says "not available" and the run carries on.
   - "Category" is the ticket type (ConnectWise, Zendesk), issue type (Autotask, Kaseya BMS, Syncro) or category (HaloPSA).
4. **Read Microsoft 365 licences** (optional) reads the tenant's subscriptions and shows licences purchased, assigned and unassigned per paid SKU. Free and trial SKUs are left out. It is skipped with a note on the card when the runner has no Microsoft 365 secrets, when the app lacks `Organization.Read.All`, or when the tenant can't be confirmed as this client's (see below).
5. **Post QBR-prep card** writes one CloudRadial Planner card on the company's board with the subject **QBR prep: Q4 2026** (the quarter the run falls in) and the stable key `qbr-data-pack:2026-Q4`.
   - A second run in the same quarter updates that card instead of adding another, even if someone renamed it. Next quarter's run makes a new card and leaves this one alone.
   - The card opens with plain sentences (devices, tickets, licences, expiring items, other open cards), then compact tables. Anything that couldn't be read is said in a sentence instead of a table.
   - It is created internal only (not client visible), open, medium priority. If you make it visible, later updates leave that setting alone.

### Which company the card goes to

1. The run's `company_id` input.
2. Otherwise the `CloudRadial-CompanyId` secret on the runner.

With neither, the run stops with a plain message and writes nothing.

### Keeping one client's data on one card

- Every CloudRadial list is filtered to the company, and filtered again in the step.
- Every PSA call is filtered to the client's PSA company id.
- Microsoft 365 licences are only included when the tenant on the runner is confirmed as this client's: the tenant id on the CloudRadial company matches, or one of the tenant's verified domains is one of the company's domains in CloudRadial. When the company has no domains in CloudRadial, the tenant is trusted only if the company came from the runner's `CloudRadial-CompanyId` secret. Otherwise the licence section is left out with a note.

### Output

`status` (`success`, `pending_confirmation` for a preview, `rejected` for bad input, `error`), `message` (a plain sentence), `internal_note`, `actions`, `warnings`, `companyId`, `companyName`, `quarterLabel`, `cardAction` (`created`, `updated`, `would-create`, `would-update`), `productId`, `cardSubject`, `cardBody`, and the gathered sections: `devices`, `tickets`, `licences`, `domains`, `certificates` and `planner`.

## Download & import

**Download the workflow:** [`qbr-data-pack.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/qbr-data-pack/qbr-data-pack.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), then **Publish** and **Deploy** it to the runner that holds them. To prepare every QBR automatically, attach a Routine (see [Import & test](#import--test)). A Routine isn't part of the export, so it has to be added after every fresh import.

## Required runner Key Vault secrets

| Secret | What it is |
|---|---|
| `CloudRadial-BaseUrl` | Your CloudRadial API base URL |
| `CloudRadial-PublicKey` | CloudRadial API public key |
| `CloudRadial-PrivateKey` | CloudRadial API private key |
| `CloudRadial-CompanyId` | Optional. The CloudRadial company number this runner belongs to, so a Routine knows which company to prepare |
| `PSA-Type` | Optional. `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk`. Without it (and without `CW-ApiUrl`), ticket trends are left out |
| That PSA's own secrets | The same names as its catalog extension: `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId`; or `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret`; or `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret`; or `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`; or `Syncro-ApiUrl`, `Syncro-ApiKey`; or `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` |
| `M365-TenantId` | Optional. The client's Microsoft 365 tenant id (`Entra-TenantID` and `Graph-TenantId` also work) |
| `M365-ClientId` | Optional. The app registration's client id (`Entra-ClientID` and `Graph-ClientId` also work) |
| `M365-ClientSecret` | Optional. The app registration's client secret (`Entra-ClientSecret` and `Graph-ClientSecret` also work) |

## Required Graph permissions

Only needed for the optional licence section. Application permission on the app registration, with admin consent:

| Permission | Why | If it's missing |
|---|---|---|
| `Organization.Read.All` (or `Directory.Read.All`) | The tenant's verified domains (to confirm it's this client's) and its subscriptions | The licence section is left out, and the card says which permission to grant. The rest of the card is still posted. |

## Inputs

| Field | Default | What it does |
|---|---|---|
| `company_id` | none | The CloudRadial company number. When blank, the `CloudRadial-CompanyId` secret is used. |
| `quarter_days` | `90` | How many days the review covers (30 to 366). Tickets are compared with the same number of days before that. |
| `preview` | `false` | `true` gathers everything and returns the card text in `cardBody`, but writes nothing. |
| `psa` | none | Overrides the `PSA-Type` secret for this run. |
| `psa_company_id` | none | The PSA's own numeric id for this client, when CloudRadial's PSA link is missing or wrong. |

**Why there's no `confirm` input:** this workflow never changes anything in CloudRadial, the PSA or Microsoft 365. Its only write is one internal Planner card, which is updated in place, and a Routine sends no input, so a `confirm` that defaults to `false` would stop a scheduled run from ever posting. Use `preview: true` to see the card first.

Example manual run: `{"company_id": 9, "quarter_days": 90, "preview": true}`

## Import & test

1. Import, add the secrets, then **Publish** and **Deploy** to the runner holding them.
2. **Preview.** Run it from **Test** with `{"company_id": <company number>, "preview": true}`. The run ends with `status: pending_confirmation`, `cardAction: would-create` (or `would-update`), the card text in `cardBody`, and no card written.
3. **Real run.** Run it again without `preview`. Check the company's CloudRadial Planner board for **QBR prep: Q<n> <year>**. Run it a second time and confirm the same card was updated (`cardAction: updated`), not duplicated.
4. **Check the numbers** against the company's endpoint list, the PSA's ticket list for that client, and the Microsoft 365 admin center's licence page.
5. **Schedule it (optional).** Attach a **Routine**, for example two weeks before each quarter's reviews. A Routine sends no input, so add the `CloudRadial-CompanyId` secret to the runner.

Strict-mode test harness (mocked Key Vault, CloudRadial, all six PSAs and Graph):

```
node automationai/qbr-data-pack/src/build.js --check
pwsh -NoProfile -File automationai/qbr-data-pack/src/test.ps1
```

### Calls not yet proven live

Each has an `Unverified` comment in `src/psa-tickets.ps1`. Check them on the first run against each PSA, then update `reference/build-kit/PSA.md`.

- **CloudRadial:** that `psaKey` on the company is the PSA's own company id for every PSA (it is used before a name match).
- **ConnectWise:** date conditions in square brackets on `dateEntered` and `closedDate`.
- **Autotask:** the `queryCount` field name, `completedDate` as the closed date, and `IncludeFields` with `pageDetails.nextPageUrl` paging.
- **HaloPSA:** the `datesearch` values `dateoccurred` and `dateclosed`, `closed_only`, and `category_1` on the ticket list.
- **Kaseya BMS:** `Filter.AccountIds`, `Filter.OpenDate*`, `Filter.CompletedDate*`, `Filter.ExcludeCompleted` and `TotalRecords`, taken from the public Swagger.
- **Syncro:** `customer_id`, `created_after` and `resolved_after` (from the Swagger); counts are worked out from the listed tickets, up to 1,000 per count.
- **Zendesk:** `organization:<id>` with `created>` and `solved>` times in a search count.

## Editing it

The five PowerShell steps are generated. Edit the files in `src/` (`inputs.ps1`, `cloudradial-data.ps1`, `psa-tickets.ps1`, `m365-licences.ps1`, `card.ps1`), then run `node automationai/qbr-data-pack/src/build.js`. It writes the `.yml` and pastes in the shared CloudRadial, PSA and Graph libraries from [`_shared`](../_shared/). Never edit the scripts inside the `.yml`.

**Optional AI summary.** The card is complete without AI. If you want a three-sentence executive summary, add an AI Prompt step between **Read Microsoft 365 licences** and **Post QBR-prep card** that reads the gathered numbers, and have it pass the input through with an added field. The card step would need a small change to print that field. This isn't shipped because the AI Prompt step's properties aren't documented yet.
