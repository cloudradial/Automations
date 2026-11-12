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
- **The right client every time.** You name the client, and it uses that client's own Microsoft 365 connection and CloudRadial details. If the client isn't set up in AutomationAI, or a tenant you type doesn't match theirs, it stops before reading or writing anything.

## Works with

Microsoft 365 and CloudRadial. No PSA is needed.

## What you need

- AutomationAI, with each client added under **Companies** with its Microsoft 365 and CloudRadial details
- Your Microsoft 365 app registration (the one in the `M365-*` secrets) with **SecurityEvents.Read.All** added, approved in each client tenant you run it against. It adds to the app's existing permissions.

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/secure-score-assessment/v1.1.0).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.

**Each time you want an assessment:**

1. Open the workflow and run it from **Test**.
2. Tell it which client (its name in AutomationAI **Companies**) and which CloudRadial company to create the assessment under. It reads that client's own Microsoft 365 tenant.
3. Optionally give the assessment a different name. Use a new name when you want a fresh snapshot on the same day.

**Test it.** Run it once for a test client, then open that client's assessments in CloudRadial and check the new one lists the controls.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/secure-score-assessment#technical-details) cover the exact inputs, the Microsoft permission it needs, and how the assessment is built.

---

## Technical details

**Formerly:** Secure Score Assessment script | **Marketplace ID:** AAI-00001 | **Type:** Workflow | **Version:** 1.1.0

## Files

Each version is published as a release, with `secure-score-assessment.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/secure-score-assessment/v1.1.0).

| What | Link |
|---|---|
| Download `secure-score-assessment.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/secure-score-assessment/v1.1.0) |
| View the current source | [`secure-score-assessment.yml`](https://github.com/cloudradial/Automations/blob/main/secure-score-assessment/secure-score-assessment.yml) |
| All files in this automation | [secure-score-assessment](https://github.com/cloudradial/Automations/tree/main/secure-score-assessment) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/secure-score-assessment) |
| Marketplace listing | [AAI-00001](https://automations.cloudradial.com/marketplace/AAI-00001) |

## How it works

Pulls a client tenant's **Microsoft Secure Score** from Graph, maps each control to a CloudRadial assessment question, and **creates + uploads** the assessment, the automated replacement for the old `Import-SecureScoreAssessment.ps1` / manual-import flow. This is a **deterministic PowerShell workflow** (not an agent): the spreadsheet is built in memory and uploaded, nothing is written to disk.

`Start → Import Secure Score (single PowerShell node) → End`:

1. Switches to the client the run names (`company`), so every secret it reads is that client's, and takes the tenant from that client's `M365-TenantID`. Then gets a Microsoft Graph app-only token for that tenant.
2. Reads `GET /security/secureScores?$top=1` and every `secureScoreControlProfiles` (paged), dropping deprecated controls.
3. Maps each control to an assessment question (Compliant when its current score meets its max), sorted by category then rank.
4. Skips if an assessment with the same title already exists for the company, then builds the xlsx in memory and sends it to **`POST /v2/assessment/upload`** (multipart) with `assessmentId: 0` and `type: 20`, which creates the assessment with every question and answer. The upload returns no body, so the new assessment is found afterwards by title. A large tenant can make the upload outlast CloudRadial's gateway (HTTP 504) while the import still finishes, so a 5xx or timeout means it keeps looking for up to about 3 minutes before reporting an error.

## Install / run

1. On **Workflows → Import**, upload `secure-score-assessment.yml`, then **Publish** and **deploy** it to your runner.
2. Add the **runner Key Vault secrets**:
   - `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey`
   - `M365-ClientID`, `M365-ClientSecret`: the Microsoft 365 app registration you already use. **Add** the **`SecurityEvents.Read.All`** *application* permission (not Delegated) to it and **admin-consent it in each client tenant** you run this against (a multi-tenant app). It adds to what the app already has, so leave its existing permissions in place.
3. Run it from **Test** with the input below. No trigger webhook is needed.

### Which client's secrets it uses

A step's **Company** decides whose secrets it reads: the client's Microsoft 365 tenant **and** its CloudRadial portal. A client's secrets are saved under the company in AutomationAI (**Companies**, policy *Require company*).

- **`company` in the run input (recommended).** The step ships with **Include all companies** on (`includeAllCompanies: true`, which import keeps). The script matches `company` to one AutomationAI company by external id, then by name or alias, and calls `Set-DefaultCompany` ([`_shared/company.ps1`](https://github.com/cloudradial/Automations/blob/main/_shared/company.ps1)). No match, or more than one, stops the run before anything is read.
- **No `company` input.** The step's own **Company** setting applies, or the runner's shared secrets when none is set. Import clears that setting, so set it again in the designer after every import if you rely on it.
- **The tenant comes from the client.** `tenantId` defaults to the company's `M365-TenantID` secret. If you also send `tenantId` and it differs, the run stops, so a typo can't put one client's score under another.

## Input

```json
{"company":"Contoso Ltd","companyId":123,"assessmentTitle":"Microsoft Secure Score","mode":"apply"}
```

- `company`: the AutomationAI company (name, external id or alias) whose secrets to use. Leave it out to use the step's own Company setting.
- `companyId`: the CloudRadial company the assessment is created under (required).
- `tenantId`: optional. Defaults to the company's `M365-TenantID` secret; when both are set they must match.
- `assessmentTitle`: optional; the date is appended, and that title is the idempotency key.
- `mode`: `apply` (default) writes; `plan` previews the counts without creating anything.

## Notes

- **Idempotent by title:** a same-titled assessment for the company is skipped, so re-runs don't duplicate. (Change `assessmentTitle` for a fresh snapshot.)
- The v2 API has no create endpoint: `POST /v2/assessment` returns 404. `POST /v2/assessment/upload` with `assessmentId: 0` creates the assessment, the same way the portal's Import Assessment dialog does and the same way [Microsoft Security Assessment](https://github.com/cloudradial/Automations/tree/main/microsoft-security-assessment) works. The upload is file-based, so this workflow does it in PowerShell.
- **Requires:** AutomationAI + the CloudRadial API secrets + your Microsoft 365 app with `SecurityEvents.Read.All` added. No custom extension needed.
- **If Graph refuses** (HTTP 403), the step stops before creating anything and names the app id and the application permissions its token holds in that tenant, so you can see whether `SecurityEvents.Read.All` is missing, Delegated instead of Application, or not consented yet.
