# Turn Microsoft Secure Score into a Client Assessment

Reads a client's Microsoft Secure Score and builds it into a CloudRadial assessment, one question per control with its current status, so security gaps are ready to review with the client.

**Formerly:** Secure Score Assessment script | **Marketplace ID:** AAI-00001 | **Type:** Workflow

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `secure-score-assessment.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/secure-score-assessment/secure-score-assessment.yml) |
| Download `secure-score-assessment.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/secure-score-assessment/secure-score-assessment.yml) |
| View `test.ps1` (mocked strict-mode test: `pwsh -NoProfile -File test.ps1`) | [GitHub](https://github.com/cloudradial/Automations/blob/main/secure-score-assessment/test.ps1) |
| All files in this automation | [secure-score-assessment](https://github.com/cloudradial/Automations/tree/main/secure-score-assessment) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/secure-score-assessment) |
| Marketplace listing | [AAI-00001](https://automations.cloudradial.com/marketplace/AAI-00001) |

> **Draft (2026-10-06):** the workflow creates and refreshes the assessment, but CloudRadial's API can't create a **run** (a dated snapshot). After each run of this workflow, a person opens the assessment under **Compliance > Assessments** and clicks **Run**. The run copies the assessment's current answers. This stays a draft until CloudRadial offers a way to create a run (filed as AAI-125).

## How it works

Pulls a client tenant's **Microsoft Secure Score** from Graph, maps each control to a CloudRadial assessment question, and keeps one CloudRadial assessment per client up to date with the current answers. It replaces the old `Import-SecureScoreAssessment.ps1` / manual-import flow. This is a **deterministic PowerShell workflow** (not an agent): the spreadsheet is built in memory and uploaded, and nothing is written to disk.

`Start → Import Secure Score (single PowerShell node) → End`:

1. Gets a Microsoft Graph app-only token for the **client's** tenant.
2. Reads `GET /security/secureScores?$top=1` and every `secureScoreControlProfiles` (paged), dropping deprecated controls.
3. Maps each control to an assessment question (Compliant when its current score meets its max), sorted by category then rank. Each question carries an **Update Key** derived from its Secure Score control id.
4. Looks for the company's assessment with this title (type 20). It builds the xlsx in memory and sends it to **`POST /v2/assessment/upload`**:
   - **No assessment yet:** `assessmentId` 0 creates it, and the new id is found by title.
   - **Assessment exists:** its `assessmentId` is sent, which replaces the answers in place. It stays the same assessment, with no duplicate questions.

## Install / run

1. On **Workflows → Import**, upload `secure-score-assessment.yml`, then **Publish** and **deploy** it to your runner.
2. Add the **runner Key Vault secrets**:
   - `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey`
   - `M365-ClientID`, `M365-ClientSecret` — an **Entra app registration** with the **`SecurityEvents.Read.All`** *application* permission, **admin-consented in each client tenant** you run this against (a multi-tenant app).
3. Run it from **Test** with the input below. No trigger webhook is needed.
4. In the portal, open the assessment under **Compliance > Assessments** and click **Run** to record a dated snapshot.

## Input

```json
{"companyId":123,"tenantId":"<client Entra tenant GUID>","assessmentTitle":"Microsoft Secure Score","mode":"apply"}
```

- `companyId` — the CloudRadial company the assessment belongs to (required).
- `tenantId` — the **client's** Entra tenant id to pull Secure Score from (required).
- `assessmentTitle` — optional, default `Microsoft Secure Score`. This title is how the workflow finds the assessment to refresh. A different title creates a separate assessment.
- `mode` — `apply` (default) writes; `plan` says whether it would create or refresh, without writing.

## Notes

- **One assessment, refreshed in place.** Re-runs never duplicate. The assessment with the same title (type 20, ignoring case and surrounding spaces) gets its answers replaced. If the company's assessments can't be listed, the run stops with an error instead of risking a duplicate.
- **Why type 20.** The assessment type codes are undocumented. From live data (2026-10-02 to 10-06): 10 = template, 20 = assessment, 30 = run.
  - The portal's Assessments list shows only type 20 rows.
  - A run (type 30) is shown only when it shares its assessment's `updateKey`. An upload can't set that, so an uploaded type 30 run is never shown.
  - A `type: 0` upload is listed by the API but never shown.
- **Runs are created in the portal.** The portal's Run button uses the portal's own API, which refuses API keys (HTTP 401). The v2 API has no run endpoint.
- **Update Keys.** CloudRadial matches questions by the workbook's per-question **Update Key** when a file is re-uploaded into an assessment (verified live). Each key is derived from the Secure Score control id, so a control keeps its question even when Microsoft rewords it.
- **Retired controls.** Untested: what a re-upload does with a question that is missing from the new workbook. The upload probably adds and updates questions without deleting any, so the old question would stay with its old answer. A control Microsoft retires (now filtered out as deprecated) would then keep its last answer in the assessment until someone deletes it in the portal.
- **No create route.** `POST /v2/assessment` returns 404 Not Found (seen live on 2026-10-02). Like the portal's Import Assessment dialog, the upload takes a `data` part `{"name":"<title>","assessmentId":<0 or existing id>,"type":20,"companyId":<id>}` plus the xlsx, and returns 204 with no body.
- **Finding a new id.** The run lists `GET /v2/odata/assessment?$filter=companyId eq <id>` (no `$select`, which has returned 500) and matches the title and type, retrying after 3 and 10 seconds. If the new assessment still isn't listed, the run reports `created` without an `assessmentId`, and the next run refreshes it once it appears.
- **No description.** The upload can't set one, and sets `category` to "Import".
- **Requires:** AutomationAI + the CloudRadial API secrets + an Entra app with `SecurityEvents.Read.All`. No custom extension needed.

## Tested (mocked Graph and CloudRadial APIs, 2026-10-06)

`test.ps1` runs the workflow's PowerShell node in strict mode, as on the runner, against mocked Graph and CloudRadial APIs, with `POST /v2/assessment` mocked as 404. Every scenario also has a run (type 30), a hidden type 0 row and a deleted assessment with the same title, none of which may be matched.

- **plan:** reports create or refresh, and writes nothing.
- **create:** uploads with `assessmentId` 0 and `type` 20, and returns the new id.
- **refresh:** uploads into the existing assessment's id.
- **custom title:** creates its own assessment.
- **New assessment not listed yet:** retried, then reported without an id.
- **Assessment list fails:** stops before any write.
- **Update Keys:** one stable key per control, derived from the control id.

Graph's last page of control profiles has no `@odata.nextLink`. The previous version read that property directly, which throws in strict mode.

The workbook uses shared strings and a minimal `styles.xml`, the shape Excel writes, and strips XML-invalid control characters. That shape is the one proven live: a test assessment imported all its questions and answers.
