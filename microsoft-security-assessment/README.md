# Turn a Microsoft 365 Security Review into a Client Assessment

Review a client's Microsoft 365 security against 11 checks and keep a CloudRadial assessment up to date with the answers, the evidence and how to fix each gap, with a dated run each time so the client's score history builds up in the portal.

## What happens

Your team runs it for a client, by hand or on a monthly schedule:

- **It reviews the client's Microsoft 365** with fixed rules, no AI:
  - multi-factor sign-in for users and admins
  - self-service password reset
  - blocking old sign-in methods
  - the number of global admins
  - risky users and sign-ins
  - Microsoft Secure Score
- **It keeps one assessment for the client,** "Microsoft 365 Security Assessment", under **Compliance > Assessments**. The first run creates it, and later runs update the same one.
- **Each question shows the evidence,** how it was checked, a plain fix and a Microsoft reference. Gaps are flagged.
- **It adds a dated run,** so the portal shows today's score and the history of earlier runs.

## What it protects

- **It only reads Microsoft 365.** Nothing in the client's tenant is changed.
- **Honest answers.** When something can't be read, such as a missing licence or permission, that question is marked "Missing" with the reason in partner-only notes, instead of guessing.
- **No duplicates.** One assessment per client, updated in place, and at most one run a day.
- **Preview first.** A preview run scores the checks and writes nothing.

## Works with

Microsoft 365 and the CloudRadial portal. No PSA is needed.

- **The risky user and risky sign-in checks need Entra ID P2.** Without it those questions show "Missing".
- **Proven live:** the review. Writing the assessment and its dated run moved to CloudRadial's new assessment API in November. The API was checked live on its own, but this workflow hasn't done a full live run with it yet, so preview first.

## What you need

- AutomationAI, with the client's Microsoft 365 connected and allowed to read sign-in, policy and security settings
- Your CloudRadial API keys on the runner

## Set it up

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/microsoft-security-assessment/v1.0.0).
2. Add the read permissions to your Microsoft 365 app. The [technical details](https://github.com/cloudradial/Automations/tree/main/microsoft-security-assessment#install--run) list them, and the keys to add to the runner.
3. Go to **Workflows > Import** and upload it, then click **Publish** and **Deploy**.
4. Run it from **Test** with the client's name and `"mode": "plan"` to preview, then run it again to write the assessment.
5. Optional: add a monthly **Routine** to keep the assessment current.

**Test it.** Open the client's **Compliance > Assessments** and check the new run's score and evidence.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/microsoft-security-assessment#technical-details) list every check and what counts as compliant, the Microsoft permissions, and every run setting.

---

## Technical details

**Formerly:** Microsoft Security Assessment | **Marketplace ID:** Not yet listed | **Type:** Workflow (PowerShell, no AI) | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/microsoft-security-assessment/v1.0.0).

| What | Link |
|---|---|
| View `microsoft-security-assessment.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/microsoft-security-assessment/microsoft-security-assessment.yml) |
| Download `microsoft-security-assessment.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/microsoft-security-assessment/v1.0.0) |
| All files in this automation | [microsoft-security-assessment](https://github.com/cloudradial/Automations/tree/main/microsoft-security-assessment) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/microsoft-security-assessment) |
| Source (for maintainers) | [src/](https://github.com/cloudradial/Automations/tree/main/microsoft-security-assessment/src) |

## How it works

```
Start -> Review Microsoft 365 security -> Create CloudRadial assessment -> Create assessment run -> End
```

1. **Review Microsoft 365 security** finds the CloudRadial company by ID or name and reads the tenant from Microsoft Graph. It scores **11 checks with fixed rules**, so it uses no AI: it runs the same on any AI provider and has no turn limit.
2. **Create CloudRadial assessment** keeps one assessment per company, named **Microsoft 365 Security Assessment**, under **Compliance > Assessments**:
   - The first run creates it.
   - Every later run updates its answers in place.
3. **Create assessment run** adds the dated run (for example *Microsoft 365 Security Assessment - 10/6/26*) with `POST /v2/assessment/{id}/run`. The run copies the answers and the assessment's `updateKey`, so the portal lists it under the assessment with its score. A run with the same title is never created twice.

Every question carries the evidence (Notes), how it was evaluated, a remediation summary and steps, a Microsoft Learn reference and risk-matrix values. Questions that aren't compliant are flagged.

## The checks

| Category | Question | Compliant (partial) |
|---|---|---|
| 1. Identity and MFA | Is MFA required for all users? | Security defaults on, or a Conditional Access policy requires MFA for All users and All cloud apps (MFA for only some users or apps, or report-only) |
| | Have users registered an MFA method? | 95% of members or more (80% or more) |
| | Have users registered for self-service password reset? | 80% or more (50% or more) |
| | Is legacy authentication blocked? | Security defaults on, or a Conditional Access policy blocks Exchange ActiveSync and other clients for All users |
| 2. Privileged access | Have all admin accounts registered an MFA method? | 100% (80% or more) |
| | Does a policy require MFA for admin roles? | Security defaults on, or a Conditional Access policy requires MFA for admin roles or All users |
| | Are there between 2 and 4 Global Administrators? | 2 to 4 (1, 5 or 6) |
| 3. Identity protection | Are there no users flagged as at risk? | No users At risk or Confirmed compromised |
| | Were there no high-risk sign-in detections in the last 30 days? | None |
| | Do Conditional Access policies respond to user and sign-in risk? | An enabled policy uses risk conditions (report-only) |
| 4. Security posture | Is the Microsoft Secure Score at least 70%? | 70% or more (50% or more) |

If Graph can't read an area (a missing permission or licence), its questions are answered **Missing**. The reason goes in **Partner Notes**, which clients don't see, and the rest of the assessment still imports. The risky-user and risk-detection checks need Entra ID P2. Without P2, the detections check is marked Missing rather than compliant, because Graph returns an empty list instead of an error.

## Install / run

1. Use the Microsoft 365 app registration you already have (the one in the `M365-*` secrets), or register one (client credentials) if you have none. Add these **application** permissions on Microsoft Graph to it, with admin consent. They add to what the app already has, so leave its existing permissions in place:
   - `Policy.Read.All`
   - `AuditLog.Read.All`
   - `RoleManagement.Read.Directory` (or `Directory.Read.All`)
   - `IdentityRiskyUser.Read.All`
   - `IdentityRiskEvent.Read.All`
   - `SecurityEvents.Read.All`
   - `Organization.Read.All`
2. Add the runner Key Vault secrets:

   | Secret | Used for |
   |---|---|
   | `M365-ClientID`, `M365-ClientSecret` | The Entra app |
   | `M365-TenantID` | The tenant to review. Not needed if the run input sends `tenantId`. |
   | `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | The CloudRadial v2 API |

3. On **Workflows → Import**, upload [`microsoft-security-assessment.yml`](microsoft-security-assessment.yml), then **Publish** and **deploy** it to your runner.
4. Run it from **Test**. Start with `{"companyName": "Contoso", "mode": "plan"}`, then run it with `"mode": "apply"`.
5. Open the company's **Compliance > Assessments**, open **Microsoft 365 Security Assessment**, and check today's run (step 3 creates it).
6. Attach a **Routine** (for example monthly) to keep the answers current.

## Run inputs

| Field | Default | What it does |
|---|---|---|
| `companyId` or `companyName` | required | The CloudRadial company. A name can be exact or a unique partial match. |
| `tenantId` | `M365-TenantID` | The Entra tenant to review. |
| `mode` | `apply` | `plan` scores the checks but writes nothing. |
| `assessmentTitle` | `Microsoft 365 Security Assessment` | The assessment's name. Runs are titled `<name> - M/d/yy`. |
| `runTitle` | `<name> - M/d/yy` | The run's title (step 3). |
| `assessmentType` | both | `20` updates only the assessment; step 3 is skipped. |

## Outputs

- **Review Microsoft 365 security:** every question with its answer and evidence, the counts, and any area Graph couldn't read.
- **Create CloudRadial assessment:** whether the assessment was `created` or `refreshed`, and its scores.
- **Create assessment run:** `success` with the run's id, score and whether it's linked to the assessment, or `skipped` when today's run already exists.

## How the assessment is written

The workflow uses the JSON assessment API (added to the CloudRadial API on 2026-11-13) through [`Sync-CrAssessment`](https://github.com/cloudradial/Automations/blob/main/_shared/cloudradial.ps1):

- **Create:** `POST /v2/assessment` with `type: 20` (the kind the Assessments list shows), client visible, with every question.
- **Refresh:** a later run updates the same assessment with `PUT /v2/assessment/{id}/questions`. Questions match on **updateKey**: each check has a permanent id (`-Id` in `src/1-review.ps1`) and its key is derived from it, so a reworded check updates the same question. Assessments first made by the older workbook upload used the same keys, so they're refreshed in place too.
- **Answers:** one `PATCH /v2/assessment/{id}/answers` sets every answer and the notes, and re-scores once.
- **Run:** `POST /v2/assessment/{id}/run` creates the dated type `30` copy with the same `updateKey`, which links it to the assessment, as the portal's Run button does. Verified live on 2026-11-13.

## Creating the run

A run is a copy of its assessment with type `30`, the date in the title and the **same `updateKey`**, which is what links it to the assessment. Step 3 creates it with `POST /v2/assessment/{id}/run`, the same assessment service as the portal's Run button, after step 2 has refreshed the answers, so the run carries this review. It skips a run whose title already exists, so a rerun the same day changes nothing; send `runTitle` for a second run that day.

## Troubleshooting

| Problem | Fix |
|---|---|
| "Please add these secrets..." | Add the named secrets to the runner Key Vault. |
| "matches N companies" | Send `companyId` instead of a partial name. |
| Questions show "couldn't be checked" | Read Partner Notes. Grant the named Graph permission, or the tenant lacks P1 or P2. |
| The run shows old answers | A run copies the assessment's answers when it's created. A run made by hand in the portal before the workflow ran keeps the older answers. |
| Step 3 `skipped`, run already exists | Today's run was made earlier. Send `runTitle` to add another. |

## Changing the workflow

The steps in `microsoft-security-assessment.yml` are built from [`src/`](src/):

| File | Step |
|---|---|
| `1-review.ps1` | Review Microsoft 365 security: the Graph reads and the 11 checks |
| `2-assessment.ps1` | Create CloudRadial assessment |
| `3-run.ps1` | Create assessment run |
| `common.ps1` | Question mapping and assessment lookups, plus [`_shared/cloudradial.ps1`](https://github.com/cloudradial/Automations/blob/main/_shared/cloudradial.ps1). The build inlines both into steps 2 and 3. |

From `src/`:

1. `npm install` (installs js-yaml).
2. `pwsh -File test.ps1` runs all three steps against a mocked Key Vault, Graph and CloudRadial API, in strict mode as on the runner. Use these flags for other scenarios:
   - `-Scenario good|bad|noperm|parent|exists|lost`
   - `-Mode plan`
   - `-Portal ok|deny`
3. `node build.js` writes `../microsoft-security-assessment.yml`.

When you add a check, give it a new `-Id`. When you reword or move one, keep its id, so its Update Key still matches the question already in each client's assessment.
