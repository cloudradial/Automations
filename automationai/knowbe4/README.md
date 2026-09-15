# KnowBe4 Training Sync

Reads **KnowBe4** users with incomplete security-awareness training, writes one CloudRadial **flexible asset** per user, and opens a single **ConnectWise** service ticket for the company summarizing who is overdue.

Unlike the webhook-triggered workflows in this folder, this one is a **manual / scheduled sync** — the Start node's webhook is disabled and it takes no trigger payload. It scopes to one KnowBe4 account → one CloudRadial company.

## Steps

Each concern is its own node (read → ensure schema → write → summarize), so every stage is legible and testable.

| # | Node | Type | What it does |
|---|------|------|--------------|
| 1 | Fetch incomplete KnowBe4 users | powershell | Pages `/v1/users` and `/v1/training/enrollments` (Bearer). An enrollment is *incomplete* when it has no `completion_date` and its `status` isn't passed/completed. Emits one row per user with their incomplete-course list. |
| 2 | Ensure CloudRadial flexible asset type | powershell | Looks the type up on the OData read surface; if missing, **creates it on the native `POST /v2/flexible-asset-type`** endpoint with its fields. (Writing to `/v2/odata/…` returns an empty body — use the native path.) |
| 3 | Create CloudRadial flexible assets | foreach | `POST /v2/flexible-asset` per user (companyId + flexibleAssetTypeId + traits). `failurePolicy: continue` so one bad user doesn't abort the batch. Bulk looping lives in deterministic PowerShell, not an agent. |
| 4 | Summarize assets & open PSA ticket | powershell | Tallies results; if any users are overdue, resolves the company's PSA identifier from CloudRadial and opens **one ConnectWise ticket** listing them. Wrapped in try/catch — a PSA problem surfaces as `ticketWarning` and never fails the run. |

CloudRadial's API can't create tickets, so the ticket is created **directly in ConnectWise** — the same approach as the Password Reset write-backs.

## Runner Key Vault secrets

| Secret | Used for |
|--------|----------|
| `KnowBe4-ApiUrl` | KnowBe4 reporting API base, e.g. `https://us.api.knowbe4.com` (region `us`/`eu`/`ca`/`uk`/`de`). A trailing region label is auto-stripped. |
| `KnowBe4-ApiKey` | KnowBe4 API token (Bearer) |
| `CloudRadial-BaseUrl` / `-PublicKey` / `-PrivateKey` | CloudRadial v2 API (Basic) — flexible-asset writes + company lookup |
| `CW-ApiUrl` / `-CompanyID` / `-PublicKey` / `-PrivateKey` / `-ClientId` | ConnectWise Manage — ticket create |
| `CW-ServiceBoard` | Service board the ticket lands on |
| `KnowBe4-AdminEmail` | *Optional.* If set, matched as the ticket's CW contact for the company admin |

## Scope & first-run checks

- **Company** — `CompanyId = 1` is set in the *Create assets* node; change it for another company. PSA assumed **ConnectWise** (swap the ticket block for Autotask if needed).
- **Trait keys** — assets are written with `user`, `email`, `incomplete-courses`, `course-list`, `updated`. After the first run, `GET /v2/odata/flexibleasset` and confirm the stored `traits` keys; adjust the `$traits` hashtable if the portal normalizes them.
- **Type id** — step 2 reads the id via `id` → `flexibleAssetTypeId` → `flexibleAssetId` (handles all three).

## Installing

1. Download [`knowbe4.yml`](knowbe4.yml) and import via **Workflows → Import**.
2. Add the Runner Key Vault secrets above.
3. **Publish** and **deploy** to the runner that holds the secrets (e.g. `han-prod`).
4. Run it manually, or attach a schedule (Routine).

## Output

`status`, `message`, `createdAssets[]`, `createdCount`, `failedCount`, `companyId`, `flexibleAssetTypeId`, `ticketId` / `ticketNumber`, and `ticketWarning` (set only if the PSA leg was skipped or failed).
