# Turn Microsoft Secure Score into a Client Assessment

Pulls a client tenant's **Microsoft Secure Score** from Graph, maps each control to a CloudRadial assessment question, and **creates + uploads** the assessment — the automated replacement for the old `Import-SecureScoreAssessment.ps1` / manual-import flow. This is a **deterministic PowerShell workflow** (not an agent): the spreadsheet is built in memory and uploaded, nothing is written to disk.

**Formerly:** Secure Score Assessment script (**AAI-00001**) | **Type:** Workflow (PowerShell)

## How it works

`Start → Import Secure Score (single PowerShell node) → End`:

1. Gets a Microsoft Graph app-only token for the **client's** tenant.
2. Reads `GET /security/secureScores?$top=1` and every `secureScoreControlProfiles` (paged), dropping deprecated controls.
3. Maps each control to an assessment question (Compliant when its current score meets its max), sorted by category then rank.
4. Skips if an assessment with the same title already exists for the company. Otherwise it builds the xlsx in memory and sends it to **`POST /v2/assessment/upload`** (multipart) with `assessmentId` 0, which creates the assessment. It then finds the new `assessmentId` by title.

## Install / run

1. On **Workflows → Import**, upload `secure-score-assessment.yml`, then **Publish** and **deploy** it to your runner.
2. Add the **runner Key Vault secrets**:
   - `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey`
   - `M365-ClientID`, `M365-ClientSecret` — an **Entra app registration** with the **`SecurityEvents.Read.All`** *application* permission, **admin-consented in each client tenant** you run this against (a multi-tenant app).
3. Run it from **Test** with the input below. No trigger webhook is needed.

## Input

```json
{"companyId":9,"tenantId":"<client Entra tenant GUID>","assessmentTitle":"Microsoft Secure Score","mode":"apply"}
```

- `companyId` — the CloudRadial company the assessment is created under (required).
- `tenantId` — the **client's** Entra tenant id to pull Secure Score from (required).
- `assessmentTitle` — optional; the date is appended, and that title is the idempotency key.
- `mode` — `apply` (default) writes; `plan` previews the counts without creating anything.

## Notes

- **Idempotent by title:** a same-titled assessment for the company (ignoring case and surrounding spaces) is skipped, so re-runs don't duplicate. Change `assessmentTitle` for a fresh snapshot. If the company's assessments can't be listed, the run stops with an error instead of risking a duplicate.
- **The upload creates the assessment.** The v2 API has no create route: `POST /v2/assessment` returns 404 Not Found (seen live on 2026-10-02). Like the portal's Import Assessment dialog, `POST /v2/assessment/upload` takes a `data` part `{"name":"<title>","assessmentId":0,"type":0,"companyId":<id>}` plus the xlsx, creates the assessment titled by `name`, and returns 204 with no body.
- **Finding the new id.** The run lists `GET /v2/odata/assessment?$filter=companyId eq <id>` (no `$select`, which has returned 500) and matches the title, retrying after 3 and 10 seconds. If it still isn't listed, the run reports `created` without an `assessmentId` and says to check Compliance > Assessments.
- **No description or category.** The upload can't set them, so the assessment has neither.
- **Requires:** AutomationAI + the CloudRadial API secrets + an Entra app with `SecurityEvents.Read.All`. No custom extension needed.

## Tested (mocked Graph and CloudRadial APIs, 2026-10-02)

`test.ps1` runs the workflow's PowerShell node in strict mode, as on the runner, against mocked Graph and CloudRadial APIs, with `POST /v2/assessment` mocked as 404. Five scenarios:

- **plan:** previews without writing.
- **apply:** sends only the upload and returns the new `assessmentId`.
- **Duplicate title:** skipped.
- **New assessment not listed yet:** retried, then reported without an id.
- **Assessment list fails:** stops before any write.

Graph's last page of control profiles has no `@odata.nextLink`. The previous version read that property directly, which throws in strict mode.

## Files

| File | What |
|---|---|
| [`secure-score-assessment.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/secure-score-assessment/secure-score-assessment.yml) | The workflow export to import. |
| [`test.ps1`](https://github.com/cloudradial/Automations/blob/main/automationai/secure-score-assessment/test.ps1) | Mocked strict-mode test of the PowerShell node: `pwsh -NoProfile -File test.ps1`. |
