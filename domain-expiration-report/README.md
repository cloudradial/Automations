# Domain Expiration Report

Read-mostly CloudRadial workflow that sweeps managed domains across companies, flags any **expired** or **expiring within N days**, and writes one plain-language **Planner card per company** summarizing what needs renewing.

Converted from the CloudRadial UCP marketplace item **CRA-00023 (Domain Expiration Report)**. Data source: `GET /v2/odata/domain` (field `dateExpires`). Delivery: `POST/PATCH /v2/product` (Planner card).

## What it does

1. Loads CloudRadial API credentials from the Runner Key Vault.
2. Resolves company names (`/v2/odata/company`).
3. Reads domains (`/v2/odata/domain`), classifies each as **expired / expiring / active / unknown** against `$WindowDays`.
4. For every company with flagged domains, upserts a single Planner card (reconciled by the deterministic subject "Domain Expiration Report") in plain sentences.
5. Returns a structured summary + the full per-domain dataset as node output.

## Configuration (in the PowerShell node)

| Setting | Default | Notes |
|---|---|---|
| `$WindowDays` | `60` | Domains expiring within this many days are "expiring soon". |
| `$CompanyIdFilter` | `@()` (all) | e.g. `@(1,4,7)` to scope. |
| `$PlannerCategory` / `$PlannerProductCategoryId` | `Efficiency` / `7` | Planner card placement; partner-defined — change to your category. |
| `$CardSubject` | `Domain Expiration Report` | Deterministic subject used to find/update the card. |
| `$WriteCards` | `$true` | Set `$false` to report only (node output), no cards written. |

## Runner Key Vault secrets

`CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` (Basic auth).

## Schedule

Intended to run on a **Routine** (e.g. weekly). Each run refreshes the same per-company card rather than creating duplicates.
