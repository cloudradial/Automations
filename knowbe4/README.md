# Chase Overdue Security Training Automatically

See who is behind on KnowBe4 security training right in your client's CloudRadial portal, and get one follow-up ticket per company listing them. It doubles as compliance evidence.

## What happens

The automation runs on a schedule you choose, or whenever your team starts it.

- **In CloudRadial,** each user with unfinished KnowBe4 training gets a record under **KnowBe4 Incomplete Training**, showing their name, email and how many courses they still owe.
- **In your PSA,** if anyone is overdue, your team gets one service ticket for the company that lists who still needs to finish. No ticket is opened when everyone is up to date.

## What happens behind the scenes

- **It only reads from KnowBe4.** Nothing changes in KnowBe4.
- **Set up once.** The first run creates the **KnowBe4 Incomplete Training** record type in CloudRadial for you.
- **One bad record won't stop the run.** If one user can't be saved, the rest still are.
- **A ticket problem won't fail the run.** If the ticket can't be opened, the training records are still saved and the run reports a warning.

## Works with

KnowBe4, CloudRadial and ConnectWise PSA.

- **One company per setup:** each copy of the workflow covers one KnowBe4 account and one CloudRadial company.
- **Other PSAs:** not supported. The ticket step is built for ConnectWise only.

## What you need

- A KnowBe4 account with API access
- AutomationAI, with CloudRadial and ConnectWise PSA connected
- A ConnectWise service board for the tickets

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/knowbe4/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. Add your KnowBe4 API details, your CloudRadial and ConnectWise connections, and the service board to your runner's secure settings.
4. Open the workflow and choose the CloudRadial client the records belong to. The workflow handles one client, so import a copy for each client you run it for.
5. Click **Publish**, then **Deploy**.
6. Run it on demand, or attach a schedule (a **Routine**) so it runs on its own.

Optionally, add your KnowBe4 admin's email address so the ticket lists them as the contact.

**Test it.** Run it once, then check the client's **KnowBe4 Incomplete Training** records in CloudRadial and the new ticket on your ConnectWise board.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/knowbe4#technical-details) cover each step, the settings it reads, what to check after the first run, and what it reports back.

---

## Technical details

**Formerly:** KnowBe4 Training Sync | **Marketplace ID:** AAI-00029 | **Type:** Workflow | **Version:** 1.0.0

## Files

Each version is published as a release, with `knowbe4.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/knowbe4/v1.0.0).

| What | Link |
|---|---|
| Download `knowbe4.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/knowbe4/v1.0.0) |
| View the current source | [`knowbe4.yml`](https://github.com/cloudradial/Automations/blob/main/knowbe4/knowbe4.yml) |
| All files in this automation | [knowbe4](https://github.com/cloudradial/Automations/tree/main/knowbe4) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/knowbe4) |
| Marketplace listing | [AAI-00029](https://automations.cloudradial.com/marketplace/AAI-00029) |

## How it works

Reads **KnowBe4** users with incomplete security-awareness training, writes one CloudRadial **flexible asset** per user, and opens a single **ConnectWise** service ticket for the company summarizing who is overdue.

Unlike the webhook-triggered workflows in this folder, this one is a **manual / scheduled sync**, the Start node's webhook is disabled and it takes no trigger payload. It scopes to one KnowBe4 account → one CloudRadial company.

## Steps

Each concern is its own node (read → ensure schema → write → summarize), so every stage is legible and testable.

| # | Node | Type | What it does |
|---|------|------|--------------|
| 1 | Fetch incomplete KnowBe4 users | powershell | Pages `/v1/users` and `/v1/training/enrollments` (Bearer). An enrollment is *incomplete* when it has no `completion_date` and its `status` isn't passed/completed. Emits one row per user with their incomplete-course list. |
| 2 | Ensure CloudRadial flexible asset type | powershell | Looks the type up on the OData read surface; if missing, **creates it on the native `POST /v2/flexible-asset-type`** endpoint with its fields. (Writing to `/v2/odata/…` returns an empty body, use the native path.) |
| 3 | Create CloudRadial flexible assets | foreach | `POST /v2/flexible-asset` per user (companyId + flexibleAssetTypeId + traits). `failurePolicy: continue` so one bad user doesn't abort the batch. Bulk looping lives in deterministic PowerShell, not an agent. |
| 4 | Summarize assets & open PSA ticket | powershell | Tallies results; if any users are overdue, resolves the company's PSA identifier from CloudRadial and opens **one ConnectWise ticket** listing them. Wrapped in try/catch, a PSA problem surfaces as `ticketWarning` and never fails the run. |

CloudRadial's API can't create tickets, so the ticket is created **directly in ConnectWise**, the same approach as the Password Reset write-backs.

## Runner Key Vault secrets

| Secret | Used for |
|--------|----------|
| `KnowBe4-ApiUrl` | KnowBe4 reporting API base, e.g. `https://us.api.knowbe4.com` (region `us`/`eu`/`ca`/`uk`/`de`). A trailing region label is auto-stripped. |
| `KnowBe4-ApiKey` | KnowBe4 API token (Bearer) |
| `CloudRadial-BaseUrl` / `-PublicKey` / `-PrivateKey` | CloudRadial v2 API (Basic), flexible-asset writes + company lookup |
| `CW-ApiUrl` / `-CompanyID` / `-PublicKey` / `-PrivateKey` / `-ClientId` | ConnectWise Manage, ticket create |
| `CW-ServiceBoard` | Service board the ticket lands on |
| `KnowBe4-AdminEmail` | *Optional.* If set, matched as the ticket's CW contact for the company admin |

## Scope & first-run checks

- **Company**, `CompanyId = 1` is set in the *Create assets* node; change it for another company. PSA assumed **ConnectWise** (swap the ticket block for Autotask if needed).
- **Trait keys**, assets are written with `user`, `email`, `incomplete-courses`, `course-list`, `updated`. After the first run, `GET /v2/odata/flexibleasset` and confirm the stored `traits` keys; adjust the `$traits` hashtable if the portal normalizes them.
- **Type id**, step 2 reads the id via `id` → `flexibleAssetTypeId` → `flexibleAssetId` (handles all three).

## Installing

1. Download [`knowbe4.yml`](https://github.com/cloudradial/Automations/blob/main/knowbe4/knowbe4.yml) and import via **Workflows → Import**.
2. Add the Runner Key Vault secrets above.
3. **Publish** and **deploy** to the runner that holds the secrets (e.g. `han-prod`).
4. Run it manually, or attach a schedule (Routine).

## Output

`status`, `message`, `createdAssets[]`, `createdCount`, `failedCount`, `companyId`, `flexibleAssetTypeId`, `ticketId` / `ticketNumber`, and `ticketWarning` (set only if the PSA leg was skipped or failed).
