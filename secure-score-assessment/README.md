# Turn Microsoft Secure Score into a Client Assessment

Reads a client's Microsoft Secure Score and builds it into a CloudRadial assessment, one question per control with its current status, so security gaps are ready to review with the client.

**Formerly:** Secure Score Assessment script | **Marketplace ID:** AAI-00001 | **Type:** Workflow

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `secure-score-assessment.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/secure-score-assessment/secure-score-assessment.yml) |
| Download `secure-score-assessment.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/secure-score-assessment/secure-score-assessment.yml) |
| All files in this automation | [secure-score-assessment](https://github.com/cloudradial/Automations/tree/main/secure-score-assessment) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/secure-score-assessment) |
| Marketplace listing | [AAI-00001](https://automations.cloudradial.com/marketplace/AAI-00001) |

## How it works

Pulls a client tenant's **Microsoft Secure Score** from Graph, maps each control to a CloudRadial assessment question, and **creates + uploads** the assessment — the automated replacement for the old `Import-SecureScoreAssessment.ps1` / manual-import flow. This is a **deterministic PowerShell workflow** (not an agent): the spreadsheet is built in memory and uploaded, nothing is written to disk.

`Start → Import Secure Score (single PowerShell node) → End`:

1. Gets a Microsoft Graph app-only token for the **client's** tenant.
2. Reads `GET /security/secureScores?$top=1` and every `secureScoreControlProfiles` (paged), dropping deprecated controls.
3. Maps each control to an assessment question (Compliant when its current score meets its max), sorted by category then rank.
4. Skips if an assessment with the same title already exists for the company, then **`POST /v2/assessment`** → builds the xlsx in memory → **`POST /v2/assessment/upload`** (multipart).

## Install / run

1. On **Workflows → Import**, upload `secure-score-assessment.yml`, then **Publish** and **deploy** it to your runner.
2. Add the **runner Key Vault secrets**:
   - `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey`
   - `M365-ClientID`, `M365-ClientSecret` — an **Entra app registration** with the **`SecurityEvents.Read.All`** *application* permission, **admin-consented in each client tenant** you run this against (a multi-tenant app).
3. Run it from **Test** with the input below. No trigger webhook is needed.

## Input

```json
{"companyId":123,"tenantId":"<client Entra tenant GUID>","assessmentTitle":"Microsoft Secure Score","mode":"apply"}
```

- `companyId` — the CloudRadial company the assessment is created under (required).
- `tenantId` — the **client's** Entra tenant id to pull Secure Score from (required).
- `assessmentTitle` — optional; the date is appended, and that title is the idempotency key.
- `mode` — `apply` (default) writes; `plan` previews the counts without creating anything.

## Notes

- **Idempotent by title:** a same-titled assessment for the company is skipped, so re-runs don't duplicate. (Change `assessmentTitle` for a fresh snapshot.)
- The `POST /v2/assessment` create endpoint is undocumented-but-functional; `POST /v2/assessment/upload` is the multipart xlsx import. Both are exercised here directly — the agent-style `cloudradial-v2-compliance` extension (0.2.2) wraps the create for other uses, but the upload is file-based so this workflow does it in PowerShell.
- **Requires:** AutomationAI + the CloudRadial API secrets + an Entra app with `SecurityEvents.Read.All`. No custom extension needed.
