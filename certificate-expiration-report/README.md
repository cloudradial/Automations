# Certificate Expiration Report — AutomationAI workflow

An importable CloudRadial **AutomationAI workflow** (`automationsWorkflow: 1`) that sweeps SSL certificates across every company, flags any **expired** or **expiring** certificate, and writes one plain-language **Planner card per company**.

Converted from the CloudRadial marketplace item **CRA-00024 (Certificate Expiration Report)**. Requires: **AutomationAI** + the **CloudRadial** extension.

## Use in AutomationAI

1. **Download** [`certificate-expiration-report.yml`](certificate-expiration-report.yml).
2. **Import it:** in your AutomationAI portal go to **Workflows → Import** and upload the `.yml`.
3. **Prerequisites:** a registered **Runner**, with these secrets in the Runner's **Key Vault** (from your CloudRadial portal **Settings → API**):
   - `CloudRadial-BaseUrl` (e.g. `https://api.us.cloudradial.com`)
   - `CloudRadial-PublicKey`
   - `CloudRadial-PrivateKey`
4. **Run it:** use **Test** for an on-demand run, or attach a **Routine** to run it on a schedule (e.g. weekly). There is no webhook trigger and no required input — it runs across all companies by default.

> This is not a standalone script — it runs inside AutomationAI on your Runner. The workflow's one PowerShell node holds the logic; you configure it by editing the CONFIG block at the top of that node (below).

## What it does

1. Reads the CloudRadial API keys from the Runner Key Vault.
2. Resolves company names (`GET /v2/odata/company`).
3. Reads certificates (`GET /v2/odata/certificate`, field `expirationDate`; also `url`, `issuer`, `subject`) and classifies each as **expired / expiring / active / unknown** against the window.
4. For every company with flagged certificates, upserts a single **Planner card** (`POST`/`PATCH /v2/product`), reconciled by the deterministic subject so re-runs update the same card instead of duplicating it.
5. Also returns a structured summary + the full per-certificate dataset as node output.

## Configure (CONFIG block at the top of the PowerShell node)

| Setting | Default | Notes |
|---|---|---|
| `$WindowDays` | `30` | Certificates expiring within this many days are "expiring soon". |
| `$CompanyIdFilter` | `@()` (all) | e.g. `@(1,4,7)` to limit to specific companies. |
| `$PlannerCategory` / `$PlannerProductCategoryId` | `Efficiency` / `7` | Where the Planner card lands; partner-defined — change to your category. |
| `$CardSubject` | `Certificate Expiration Report` | Deterministic subject used to find/update the card. |
| `$WriteCards` | `$true` | Set `$false` to report only (node output), writing no cards. |

## Output

The node returns `status`, a human-readable `message`, `counts` (evaluated / expired / expiring / active / unknown / cards created / updated), and `certificates` (the full per-certificate dataset) for use by later nodes or delivery steps.
