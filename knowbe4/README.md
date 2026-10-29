# Chase Overdue Security Training Automatically

See who is behind on KnowBe4 security training right in your client's CloudRadial portal, and get one follow-up ticket per company listing them. It doubles as compliance evidence.

## What happens

The automation runs on a schedule you choose, or whenever your team starts it.

- **In CloudRadial,** each user with unfinished KnowBe4 training has one record under **KnowBe4 Incomplete Training**, showing their name, email and how many courses they still owe. Each run updates the same record, and when someone catches up their record shows 0 courses left.
- **In your PSA,** your team gets one service ticket for the company when someone is newly overdue or owes more courses than last time. It lists everyone still overdue. A run where nothing got worse opens no ticket, so a weekly schedule doesn't fill your board.

## What happens behind the scenes

- **It only reads from KnowBe4.** Nothing changes in KnowBe4.
- **Set up once.** The first run creates the **KnowBe4 Incomplete Training** record type in CloudRadial for you.
- **No duplicates.** Records are matched by email (or by name when there's no email) and updated in place. Records are never deleted.
- **One bad record won't stop the run.** If one user can't be saved, the rest still are.
- **A ticket problem won't fail the run.** If the ticket can't be opened, the training records are still saved and the run reports a warning.

## Works with

KnowBe4, CloudRadial, and any of these PSAs: ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro or Zendesk.

- **One company per setup:** each copy of the workflow covers one KnowBe4 account and one CloudRadial company.

## What you need

- A KnowBe4 account with API access
- AutomationAI, with CloudRadial and your PSA connected
- The client's company named the same in CloudRadial and your PSA (or a catch-all PSA company, see the technical details)

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/knowbe4/v1.2.0).
2. Go to **Workflows > Import** and upload it.
3. Add your KnowBe4 API details, your CloudRadial connection and your PSA connection to your runner's secure settings. Optionally add the board or queue the ticket should land on.
4. Tell it which client the records belong to: start each run with the client's CloudRadial company id, or save it in the runner's settings as `CloudRadial-CompanyId`. The workflow handles one client per KnowBe4 account, so set up a copy for each client you run it for.
5. Click **Publish**, then **Deploy**.
6. Run it on demand, or attach a schedule (a **Routine**) so it runs on its own.

Optionally, add your KnowBe4 admin's email address so the ticket lists them as the contact.

**Test it.** Run it once, then check the client's **KnowBe4 Incomplete Training** records in CloudRadial and the new ticket in your PSA.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/knowbe4#technical-details) cover each step, the settings it reads, what to check after the first run, and what it reports back.

---

## Technical details

**Formerly:** KnowBe4 Training Sync | **Marketplace ID:** AAI-00029 | **Type:** Workflow | **Version:** 1.2.0

## Files

Each version is published as a release, with `knowbe4.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/knowbe4/v1.2.0).

| What | Link |
|---|---|
| Download `knowbe4.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/knowbe4/v1.2.0) |
| View the current source | [`knowbe4.yml`](https://github.com/cloudradial/Automations/blob/main/knowbe4/knowbe4.yml) |
| Source of the built steps | [`src/`](https://github.com/cloudradial/Automations/tree/main/knowbe4/src): `company.ps1`, `records.ps1`, `ticket.ps1`, `build.js`, `test.ps1` |
| All files in this automation | [knowbe4](https://github.com/cloudradial/Automations/tree/main/knowbe4) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/knowbe4) |
| Marketplace listing | [AAI-00029](https://automations.cloudradial.com/marketplace/AAI-00029) |

## How it works

Reads **KnowBe4** users with incomplete security-awareness training, writes one CloudRadial **flexible asset** per user, and opens a single ticket for the company in whichever of the six PSAs the runner uses (`_shared/psa.ps1`), summarizing who is overdue.

Unlike the webhook-triggered workflows in this folder, this one is a **manual / scheduled sync**, the Start node's webhook is disabled and it takes no trigger payload. It scopes to one KnowBe4 account → one CloudRadial company.

## Steps

Each concern is its own node (read → ensure schema → write → summarize), so every stage is legible and testable.

| # | Node | Type | What it does |
|---|------|------|--------------|
| 0 | Pick the CloudRadial company | powershell (`src/company.ps1`) | Takes `companyId` from the run input, else the `CloudRadial-CompanyId` secret, and checks the company exists. A missing or wrong id stops the run before KnowBe4 is read. |
| 1 | Fetch incomplete KnowBe4 users | powershell | Pages `/v1/users` and `/v1/training/enrollments` (Bearer). An enrollment is *incomplete* when it has no `completion_date` and its `status` isn't passed/completed. Emits one row per user with their incomplete-course list. |
| 2 | Ensure CloudRadial flexible asset type | powershell | Looks the type up on the OData read surface; if missing, **creates it on the native `POST /v2/flexible-asset-type`** endpoint with its fields. (Writing to `/v2/odata/…` returns an empty body, use the native path.) |
| 3 | Create or update CloudRadial records | powershell (`src/records.ps1`) | Reads the company's existing records of the type once (`/v2/odata/flexibleasset`), keyed by email, else user name. An overdue user's record is updated when the courses changed (`PATCH /v2/flexible-asset/{id}` replacing `traitsJson`, with the IT Glue-compatible route as the fallback), left alone when not, and created (`POST /v2/flexible-asset`) when missing. A user who caught up is set to 0 courses; nothing is deleted. Older duplicates are reported. If the existing records can't be read, nothing is written. One bad record is reported as an error item and doesn't stop the rest. |
| 4 | Summarize assets & open PSA ticket | powershell (`src/ticket.ps1`) | Tallies results; if anyone is newly overdue or owes more courses than last run, finds the PSA company (the CloudRadial company's name, matched exactly, then the `PSA-CompanyId` catch-all with a warning) and opens **one ticket** listing everyone overdue, marking who is new or owes more. Otherwise it opens nothing and says why (`ticketSkipped`). A PSA problem surfaces as `ticketWarning` and never fails the run. |

CloudRadial's API can't create tickets, so the ticket is created **directly in the PSA**, the same approach as the other six-PSA workflows. Steps 0, 3 and 4 are built from `src/` by `node src/build.js`; edit those files, never the scripts in the `.yml`.

## Runner Key Vault secrets

| Secret | Used for |
|--------|----------|
| `KnowBe4-ApiUrl` | KnowBe4 reporting API base, e.g. `https://us.api.knowbe4.com` (region `us`/`eu`/`ca`/`uk`/`de`). A trailing region label is auto-stripped. |
| `KnowBe4-ApiKey` | KnowBe4 API token (Bearer) |
| `CloudRadial-BaseUrl` / `-PublicKey` / `-PrivateKey` | CloudRadial v2 API (Basic), flexible-asset writes + company lookup |
| `CloudRadial-CompanyId` | The client's CloudRadial company id, used when the run input has no `companyId` |
| `PSA-Type` | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk`, plus that PSA's secrets, the same names as its catalog extension (see `_shared/psa.ps1`) |
| `PSA-ServiceQueue` | *Optional.* The board, queue, team, issue type or group for the ticket. On ConnectWise the older `CW-ServiceBoard` still works. |
| `PSA-CompanyId` | *Optional.* A catch-all PSA company used when the client's company name doesn't match exactly one PSA company (the run then warns). Without it, no ticket is opened and the run warns. |
| `KnowBe4-AdminEmail` | *Optional.* Named in the ticket as the client's KnowBe4 admin |

## Scope & first-run checks

- **Company**, from the run's `companyId` or the `CloudRadial-CompanyId` secret (up to 1.0.0 it was fixed at `CompanyId = 1` in the *Create assets* node).
- **PSA**, any of the six, chosen by `PSA-Type`. Up to 1.0.0 the ticket was ConnectWise only and `KnowBe4-AdminEmail` was looked up as a ConnectWise contact; now it's named in the ticket text instead.
- **Trait keys**, records are written with `user`, `email`, `incomplete-courses`, `course-list`, `updated`. Matching reads them case-insensitively, with spaces or underscores treated as hyphens, so a portal that stores `Incomplete Courses` still matches. After the first run, `GET /v2/odata/flexibleasset` and confirm the stored keys.
- **Records from 1.0.0 and 1.1.0**, those versions added a new record per user on every run. 1.2.0 keeps the newest one up to date and lists the older ones in `duplicates`; delete them in the portal if you want them gone.
- **Type id**, step 2 reads the id via `id` → `flexibleAssetTypeId` → `flexibleAssetId` (handles all three).

## Installing

1. Download [`knowbe4.yml`](https://github.com/cloudradial/Automations/blob/main/knowbe4/knowbe4.yml) and import via **Workflows → Import**.
2. Add the Runner Key Vault secrets above.
3. **Publish** and **deploy** to the runner that holds the secrets (e.g. `han-prod`).
4. Run it manually with `{"companyId": <id>}`, or attach a schedule (Routine) and set `CloudRadial-CompanyId`.

## Output

`status`, `message`, `createdAssets[]` (everyone still overdue, with `action` and `worse`), `overdueCount`, `createdCount`, `updatedCount`, `unchangedCount`, `completedCount`, `worseCount`, `failedCount`, `ticketSkipped`, `companyId`, `companyName`, `flexibleAssetTypeId`, `psa`, `psaCompanyId`, `ticketId` / `ticketNumber`, and `ticketWarning` (set when the PSA leg was skipped or failed, or used the `PSA-CompanyId` catch-all).

## Tested

- `src/test.ps1`: 62 strict-mode checks on steps 0, 3 and 4, run exactly as they are in the `.yml`: the company from the run input, the secret, a leftover placeholder, and a missing, unknown or non-numeric id; a ticket on each of the six PSAs on the name-matched company listing the overdue users; `CW-ServiceBoard`, `PSA-ServiceQueue` and `KnowBe4-AdminEmail`; the `PSA-CompanyId` fallback; no match, no PSA, and nobody overdue; no ticket when nothing got worse, one when someone owes more. Records: unchanged, updated (matched by email in any case, or by name, with portal-style trait names), created, caught-up users set to 0, already-complete records left alone, older duplicates reported and never deleted, and nothing written when the existing records can't be read.
- Not yet run live on 1.2.0. The record update (`PATCH /v2/flexible-asset/{id}`) is the same call the ScalePad sync uses, but hasn't been proven by a KnowBe4 run. The PSA calls come from `_shared/psa.ps1`; those marked `Unverified` there haven't been proven by a live run, so check the first ticket in your PSA.
