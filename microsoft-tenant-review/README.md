# Microsoft Tenant Review

Review a client's Microsoft 365 tenant in one click: a scored security assessment from Microsoft Secure Score, plus Planner cards that turn unused licenses, missing MFA and stale accounts into savings and security wins.

## What your clients see in the portal

- **A security assessment** under **Compliance > Assessments**, named after the client (for example *Contoso Ltd Secure Score Assessment*), with the score and plain-language findings in four areas: identity, devices, apps and data.
- **Planner cards** written in plain, conversational language:
  - **Unused Microsoft 365 licenses:** licenses they pay for that nobody is using, by subscription.
  - **Accounts without MFA:** who still signs in with only a password.
  - **Stale Microsoft 365 accounts:** licensed accounts nobody has used in 90 days.

## What happens behind the scenes

- **Read-only in Microsoft 365.** It never changes anything in the client's tenant.
- **One card per finding, kept up to date.** Reruns update the cards instead of adding new ones.
- **Each run is dated,** so you can see how the score moves over time.

## Works with

Microsoft 365, with your multi-tenant app consented in the client's tenant. Any PSA (the PSA isn't used).

- **Stale accounts:** the last sign-in date needs Entra ID P1. Without it, the Microsoft 365 active-user report is used instead.

## What you need

- A UCP portal with **Actions** on your request forms
- AutomationAI, with CloudRadial connected
- The Microsoft 365 app you already use for client tenants, with the permissions in the [technical details](https://github.com/cloudradial/Automations/tree/main/microsoft-tenant-review#required-graph-permissions)
- The client's tenant ID saved on the company in CloudRadial

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://raw.githubusercontent.com/cloudradial/Automations/main/microsoft-tenant-review/microsoft-tenant-review.yml) (right-click > Save link as).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.

**In your UCP portal, add the Microsoft Tenant Review form:**

1. Create a request form called **Microsoft Tenant Review** in an admin-only category (for example **Operations**).
2. Add a **Comment** question, "Subject", with the default value `@CompanyName Microsoft 365 Tenant Review`, and tick **Use as subject**.
3. At the end of the form, add an **Action** question and pick **Microsoft Tenant Review**.

The [form file](https://github.com/cloudradial/Automations/blob/main/microsoft-tenant-review/forms/microsoft-tenant-review.json) has every setting.

**Test it.** Submit the form for one client, then open that client's **Assessments** and **Planner**.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/microsoft-tenant-review#technical-details) cover the checks, the Graph permissions and the limits of the CloudRadial API.

---

## Technical details

**Formerly:** Microsoft Security Assessment (form version) | **Marketplace ID:** CRA-00005 | **Type:** Workflow (PowerShell, no AI) | **Version:** 1.0.0

This is the portal-form version that builds the assessment from Secure Score. [microsoft-security-assessment](../microsoft-security-assessment/) is the manually run version that scores 11 Graph checks.

## Files

| What | Link |
|---|---|
| View `microsoft-tenant-review.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/microsoft-tenant-review/microsoft-tenant-review.yml) |
| Download `microsoft-tenant-review.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/microsoft-tenant-review/microsoft-tenant-review.yml) |
| Portal form | [forms/microsoft-tenant-review.json](https://github.com/cloudradial/Automations/blob/main/microsoft-tenant-review/forms/microsoft-tenant-review.json) |
| Step sources and build script | [src/](https://github.com/cloudradial/Automations/tree/main/microsoft-tenant-review/src) |
| All files in this automation | [microsoft-tenant-review](https://github.com/cloudradial/Automations/tree/main/microsoft-tenant-review) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/microsoft-tenant-review) |

## How it works

```
Start -> Secure Score assessment -> License and MFA review -> End
```

1. **Secure Score assessment** reads the company and its tenant ID from the form's ticket, signs in to the client's tenant, and reads Secure Score and its control profiles. It creates a CloudRadial assessment named `<Company> Secure Score Assessment (yyyy-MM-dd HH:mm UTC)` with a description, recommendations and four categories.
2. **License and MFA review** reads subscribed SKUs, users, MFA registration and last sign-in (or the Office 365 active-user report), then keeps three Planner cards: **Unused Microsoft 365 licenses** (Efficiency), **Accounts without MFA** (Security) and **Stale Microsoft 365 accounts** (Efficiency, 90 days).

### CloudRadial API limits

- The public API can't create an assessment **run**, so the assessment has no run until you start one from it in the portal.
- The assessment's source shows as **Imported File**. The API has no field to change it.

## Required runner Key Vault secrets

| Secret | Used for |
|---|---|
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Company, assessment and Planner cards |
| `M365-ClientID`, `M365-ClientSecret` | Signing in to the client's tenant (the tenant ID comes from the company) |

## Required Graph permissions

Application permissions on your multi-tenant app, with admin consent in the client's tenant. All are read-only.

- `SecurityEvents.Read.All` (Secure Score)
- `Organization.Read.All` (licenses)
- `User.Read.All` (users)
- `AuditLog.Read.All` (MFA registration and last sign-in)
- `Reports.Read.All` (active-user report, used when sign-in activity isn't available)

## Notes

- The webhook ships disabled. The form's **Action** question runs it.
- Exported from the AutomationAI test tenant (tenant version 0.0.6) on 2026-11-12, then split into `src/` with tenant-specific names removed. Build with `node src/build.js`. A strict-mode test harness (`src/test.ps1`) is still to be written.

## Tested

Run against a demo tenant in the test portal: assessment created, and the cards found 7 unused licenses, 1 account without MFA and 8 stale accounts.
