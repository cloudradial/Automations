# Turn a Microsoft 365 Security Review into a Client Assessment

Reads a client's Microsoft 365 tenant through Microsoft Graph, scores 11 security checks, and keeps a CloudRadial assessment up to date with the answers, evidence and remediation.

**Formerly:** Microsoft Security Assessment | **Marketplace ID:** Not yet listed | **Type:** Workflow (PowerShell, no AI)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `microsoft-security-assessment.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/microsoft-security-assessment/microsoft-security-assessment.yml) |
| Download `microsoft-security-assessment.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/microsoft-security-assessment/microsoft-security-assessment.yml) |
| All files in this automation | [microsoft-security-assessment](https://github.com/cloudradial/Automations/tree/main/microsoft-security-assessment) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/microsoft-security-assessment) |
| Source (for maintainers) | [src/](https://github.com/cloudradial/Automations/tree/main/microsoft-security-assessment/src) |

## How it works

```
Start -> Review Microsoft 365 security -> Create CloudRadial assessment -> Create assessment run (in development) -> End
```

1. **Review Microsoft 365 security** finds the CloudRadial company by ID or name and reads the tenant from Microsoft Graph. It scores **11 checks with fixed rules**, so it uses no AI: it runs the same on any AI provider and has no turn limit.
2. **Create CloudRadial assessment** keeps one assessment per company, named **Microsoft 365 Security Assessment**, under **Compliance > Assessments**:
   - The first run creates it.
   - Every later run updates its answers in place.
3. **Create assessment run (in development)** is meant to add the dated run (for example *Microsoft 365 Security Assessment - 10/6/26*). The public API can't create a run yet (see [Creating the run](#creating-the-run)), so for now **create the run from the assessment in the portal** after the workflow runs. The run copies the assessment's current answers.

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

1. Register an Entra app (client credentials). Give it these **application** permissions on Microsoft Graph, with admin consent:
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
5. Open the company's **Compliance > Assessments**, open **Microsoft 365 Security Assessment**, and create a run.
6. Attach a **Routine** (for example monthly) to keep the answers current.

## Run inputs

| Field | Default | What it does |
|---|---|---|
| `companyId` or `companyName` | required | The CloudRadial company. A name can be exact or a unique partial match. |
| `tenantId` | `M365-TenantID` | The Entra tenant to review. |
| `mode` | `apply` | `plan` scores the checks and builds the workbook but writes nothing. |
| `assessmentTitle` | `Microsoft 365 Security Assessment` | The assessment's name. Runs are titled `<name> - M/d/yy`. |
| `runTitle` | `<name> - M/d/yy` | The run's title (step 3). |
| `assessmentType` | both | `20` updates only the assessment; step 3 is skipped. |
| `portalUrl` | `CloudRadial-PortalUrl` secret | Step 3 only (in development): the partner portal, for example `https://contoso.us.cloudradial.com`. Leave it out today. |

## Outputs

- **Review Microsoft 365 security:** every question with its answer and evidence, the counts, and any area Graph couldn't read.
- **Create CloudRadial assessment:** whether the assessment was `created` or `refreshed`, and its scores.
- **Create assessment run:** `skipped` with the reminder to create the run in the portal, or with `portalUrl`, `unsupported` (HTTP 401, nothing created).

## How the assessment is written

The v2 API has no create or update endpoint for assessments (`POST /v2/assessment` returns 404). Everything goes through **`POST /v2/assessment/upload`** with an Excel workbook in the import format: sheet `Assessment`, the 51 columns of the [blank template](https://radials.io/blankassessment). The workbook is built in memory. These behaviours were verified live:

- **`type` codes** (not documented): `10` template, `20` assessment, `30` run. The workflow uploads type `20`, the kind the Assessments list shows. Type `0` creates a row the portal never shows.
- **Create:** `assessmentId: 0` creates the assessment, named by `name`. The upload returns no body, so the workflow finds the new assessment by title and type.
- **Update:** an upload with the existing `assessmentId` replaces the answers in place. It's the same row and `updateKey`, with no duplicate questions.
- **Question matching** uses the workbook's **Update Key** column. Each check has a permanent id (`-Id` in `src/1-review.ps1`), and its Update Key is derived from it, so it's the same on every run. A reworded check still updates its question. An assessment first uploaded without keys also switches to keys cleanly.

## Creating the run

A run is a copy of its assessment with type `30`, the date in the title and the **same `updateKey`**, which is what links it to the assessment. The portal creates one with `POST /api/assessments/run`, an internal portal API that accepts only a signed-in user (an API key gets HTTP 401). The v2 upload ignores `updateKey`, so an uploaded type 30 row isn't linked and never appears. Step 3 stays **in development** until CloudRadial offers a supported way to create a run. Until then it ends without creating anything, and you create the run in the portal.

## Troubleshooting

| Problem | Fix |
|---|---|
| "Please add these secrets..." | Add the named secrets to the runner Key Vault. |
| "matches N companies" | Send `companyId` instead of a partial name. |
| Questions show "couldn't be checked" | Read Partner Notes. Grant the named Graph permission, or the tenant lacks P1 or P2. |
| The run shows old answers | A run copies the assessment's answers when it's created. Run the workflow first, then create the run. |
| Step 3 `unsupported` | Expected today. Create the run in the portal. |

## Changing the workflow

The steps in `microsoft-security-assessment.yml` are built from [`src/`](src/):

| File | Step |
|---|---|
| `1-review.ps1` | Review Microsoft 365 security: the Graph reads and the 11 checks |
| `2-assessment.ps1` | Create CloudRadial assessment |
| `3-run.ps1` | Create assessment run (in development) |
| `common.ps1` | The workbook builder and upload helpers. The build inlines it into steps 2 and 3. |

From `src/`:

1. `npm install` (installs js-yaml).
2. `pwsh -File test.ps1` runs all three steps against a mocked Key Vault, Graph and CloudRadial API, in strict mode as on the runner. Use these flags for other scenarios:
   - `-Scenario good|bad|noperm|parent|exists|lost`
   - `-Mode plan`
   - `-Portal ok|deny`
3. `node build.js` writes `../microsoft-security-assessment.yml`.

When you add a check, give it a new `-Id`. When you reword or move one, keep its id, so its Update Key still matches the question already in each client's assessment.
