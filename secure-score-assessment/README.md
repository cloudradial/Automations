# Turn Microsoft Secure Score into a Client Assessment

Turn a client's Microsoft Secure Score into a CloudRadial assessment in one run. Every security control becomes a question with its current status, so the gaps are ready to walk through with the client.

## What happens

Your team runs it for one client at a time. When it finishes, a new assessment appears under that client in CloudRadial, named with the date it was taken.

- Each Microsoft Secure Score control is one question, grouped by category.
- Controls that are fully in place are marked **Compliant**. The rest are marked **Not compliant** and flagged, so they stand out for review.
- The assessment summary shows how many controls are compliant and the client's overall score.

## What happens behind the scenes

- **It only reads from Microsoft 365.** Nothing in the client's tenant is changed.
- **No duplicates.** If an assessment with the same name and date already exists for that client, it's skipped.
- **Retired controls are left out.** Microsoft's deprecated controls don't clutter the assessment.
- **Preview first if you like.** You can do a dry run that shows the counts without creating anything.

## Works with

Microsoft 365 and CloudRadial. No PSA is needed.

## What you need

- AutomationAI, with your CloudRadial API connected
- A Microsoft app registration that can read Secure Score, approved in each client tenant you run it against

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/secure-score-assessment/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.
4. If a client's Microsoft 365 connection is saved under that company in AutomationAI, open the workflow and set **Company** to that client on the **Import Secure Score** step. Do this again after every import.

**Each time you want an assessment:**

1. Open the workflow and run it from **Test**.
2. Tell it which CloudRadial company to create the assessment under and which Microsoft 365 tenant to read.
3. Optionally give the assessment a different name. Use a new name when you want a fresh snapshot on the same day.

**Test it.** Run it once for a test client, then open that client's assessments in CloudRadial and check the new one lists the controls.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/secure-score-assessment#technical-details) cover the exact inputs, the Microsoft permission it needs, and how the assessment is built.

---

## Technical details

**Formerly:** Secure Score Assessment script | **Marketplace ID:** AAI-00001 | **Type:** Workflow | **Version:** 1.0.0

## Files

Each version is published as a release, with `secure-score-assessment.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/secure-score-assessment/v1.0.0).

| What | Link |
|---|---|
| Download `secure-score-assessment.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/secure-score-assessment/v1.0.0) |
| View the current source | [`secure-score-assessment.yml`](https://github.com/cloudradial/Automations/blob/main/secure-score-assessment/secure-score-assessment.yml) |
| All files in this automation | [secure-score-assessment](https://github.com/cloudradial/Automations/tree/main/secure-score-assessment) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/secure-score-assessment) |
| Marketplace listing | [AAI-00001](https://automations.cloudradial.com/marketplace/AAI-00001) |

## How it works

Pulls a client tenant's **Microsoft Secure Score** from Graph, maps each control to a CloudRadial assessment question, and **creates + uploads** the assessment, the automated replacement for the old `Import-SecureScoreAssessment.ps1` / manual-import flow. This is a **deterministic PowerShell workflow** (not an agent): the spreadsheet is built in memory and uploaded, nothing is written to disk.

`Start → Import Secure Score (single PowerShell node) → End`:

1. Gets a Microsoft Graph app-only token for the **client's** tenant.
2. Reads `GET /security/secureScores?$top=1` and every `secureScoreControlProfiles` (paged), dropping deprecated controls.
3. Maps each control to an assessment question (Compliant when its current score meets its max), sorted by category then rank.
4. Skips if an assessment with the same title already exists for the company, then **`POST /v2/assessment`** → builds the xlsx in memory → **`POST /v2/assessment/upload`** (multipart).

## Install / run

1. On **Workflows → Import**, upload `secure-score-assessment.yml`, then **Publish** and **deploy** it to your runner.
2. Add the **runner Key Vault secrets**:
   - `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey`
   - `M365-ClientID`, `M365-ClientSecret`: an **Entra app registration** with the **`SecurityEvents.Read.All`** *application* permission, **admin-consented in each client tenant** you run this against (a multi-tenant app).
3. Run it from **Test** with the input below. No trigger webhook is needed.

### Microsoft 365 secrets stored per company

Sometimes a client's Microsoft 365 secrets (`M365-TenantID`, `M365-ClientID` and `M365-ClientSecret`) are saved under the company in AutomationAI (**Companies**, policy *Require company*) instead of in the runner vault. In that case, open the workflow in the designer and set **Company** to that client on the step: **Import Secure Score**. Then publish and deploy.

- **Set it again after every import.** Importing a workflow clears the step Company setting, because the `.yml` doesn't carry it.
- **Without it,** the step uses the runner's shared secrets, so they sign in to the wrong tenant or fail.

## Input

```json
{"companyId":123,"tenantId":"<client Entra tenant GUID>","assessmentTitle":"Microsoft Secure Score","mode":"apply"}
```

- `companyId`: the CloudRadial company the assessment is created under (required).
- `tenantId`: the **client's** Entra tenant id to pull Secure Score from (required).
- `assessmentTitle`: optional; the date is appended, and that title is the idempotency key.
- `mode`: `apply` (default) writes; `plan` previews the counts without creating anything.

## Notes

- **Idempotent by title:** a same-titled assessment for the company is skipped, so re-runs don't duplicate. (Change `assessmentTitle` for a fresh snapshot.)
- The `POST /v2/assessment` create endpoint is undocumented-but-functional; `POST /v2/assessment/upload` is the multipart xlsx import. Both are exercised here directly; the agent-style `cloudradial-v2-compliance` extension (0.2.2) wraps the create for other uses, but the upload is file-based so this workflow does it in PowerShell.
- **Requires:** AutomationAI + the CloudRadial API secrets + an Entra app with `SecurityEvents.Read.All`. No custom extension needed.
