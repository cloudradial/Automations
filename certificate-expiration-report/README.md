# Certificate Expiration Report

Read-mostly CloudRadial workflow that sweeps SSL certificates across companies, flags any **expired** or **expiring within N days**, and writes one plain-language **Planner card per company**.

Converted from the CloudRadial UCP marketplace item **CRA-00024 (Certificate Expiration Report)**. Data source: `GET /v2/odata/certificate` (field `expirationDate`; also `url`, `issuer`, `subject`). Delivery: `POST/PATCH /v2/product` (Planner card).

## What it does

1. Loads CloudRadial API credentials from the Runner Key Vault.
2. Resolves company names (`/v2/odata/company`).
3. Reads certificates (`/v2/odata/certificate`), classifies each as **expired / expiring / active / unknown** against `$WindowDays`.
4. For every company with flagged certificates, upserts a single Planner card (subject "Certificate Expiration Report") in plain sentences.
5. Returns a structured summary + the full per-certificate dataset as node output.

## Configuration (in the PowerShell node)

| Setting | Default | Notes |
|---|---|---|
| `$WindowDays` | `30` | Certificates expiring within this many days are "expiring soon". |
| `$CompanyIdFilter` | `@()` (all) | e.g. `@(1,4,7)` to scope. |
| `$PlannerCategory` / `$PlannerProductCategoryId` | `Efficiency` / `7` | Planner card placement; partner-defined — change to your category. |
| `$CardSubject` | `Certificate Expiration Report` | Deterministic subject used to find/update the card. |
| `$WriteCards` | `$true` | Set `$false` to report only (node output), no cards written. |

## Runner Key Vault secrets

`CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` (Basic auth).

## Schedule

Intended to run on a **Routine** (e.g. weekly). Each run refreshes the same per-company card rather than creating duplicates.
