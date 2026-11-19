# Live QBR Dashboard

A Quarterly Business Review that's always up to date, right in your client's portal: ticket trends, projects, devices, security and an overall health score, filled from ConnectWise, Datto RMM, CloudRadial and Microsoft 365. QBR prep goes from hours of exporting to zero.

## What your clients see in the portal

A **Quarterly Business Review** dashboard with four widgets:

- **QBR Overview:** tickets this quarter, % resolved within 3 days, median resolve time, CSAT, managed devices, Microsoft Secure Score, and an overall health score with Service, Security, Lifecycle and Adoption sub-scores.
- **Ticket Volume:** tickets created vs closed for the last 6 months, plus the top ticket types.
- **Projects:** open ConnectWise projects with progress, due date and status.
- **Security and Device Lifecycle:** MFA, patch, antivirus and check-in coverage, Secure Score, Windows 10 exposure, the device fleet by lifecycle stage and an estimated refresh budget.

## What happens behind the scenes

- **ConnectWise:** ticket counts by month, resolve times, ticket types and open projects for the client.
- **Datto RMM:** devices, patch and antivirus status, check-ins and operating systems.
- **CloudRadial:** CSAT from feedback, and portal or Signal adoption.
- **Microsoft 365:** Secure Score and MFA registration, when your app has the permissions.
- **Writes the @CH company tokens** the widgets display. Anything it can't read shows a dash, never a made-up number.

## Works with

ConnectWise PSA, Datto RMM and Microsoft 365.

## What you need

- AutomationAI, with ConnectWise, Datto RMM and CloudRadial connected
- Optional: your Microsoft 365 app with **SecurityEvents.Read.All** (Secure Score) and **AuditLog.Read.All** (MFA registration)
- A **Routine** to refresh it (daily works well)

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://raw.githubusercontent.com/cloudradial/Automations/main/qbr-dashboard/qbr-dashboard.yml) (right-click > Save link as).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.
4. Run it once with **Test** for your client (input below), then add a daily **Routine** with the same input.

```json
{"companyId": 1, "psaCompanyId": 250, "tenantId": "<client's Microsoft 365 tenant id>", "confirm": true}
```

**In your UCP portal, add the dashboard** for the client: **Account > Dashboards > Add Dashboard**, named **Quarterly Business Review**, then four **Custom HTML** widgets (2 wide by 3 high, in a 2x2 grid) with the HTML from [widgets/widgets.json](https://github.com/cloudradial/Automations/blob/main/qbr-dashboard/widgets/widgets.json). Or use `POST /v2/dashboard` and `POST /v2/dashboard/{id}/widget?companyId=`.

**Test it.** Reload the dashboard: no `@CH` text should show.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/qbr-dashboard#technical-details) cover the inputs, the scoring and the widgets.

---

## Technical details

**Marketplace ID:** CRA-00022 | **Type:** Workflow (one PowerShell step, no AI) plus a 4-widget dashboard | **Version:** 1.0.0

Built on the [Client Health](../client-health/) dashboard template, filled by a plain script instead of an agent.

## Files

| What | Link |
|---|---|
| View `qbr-dashboard.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/qbr-dashboard/qbr-dashboard.yml) |
| Download `qbr-dashboard.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/qbr-dashboard/qbr-dashboard.yml) |
| Widget HTML and demo token values | [widgets/](https://github.com/cloudradial/Automations/tree/main/qbr-dashboard/widgets) |
| Step source, widget template builder and build script | [src/](https://github.com/cloudradial/Automations/tree/main/qbr-dashboard/src) |

## Inputs

| Input | Default | What it does |
|---|---|---|
| `companyId` | required | The CloudRadial company whose tokens to write |
| `psaCompanyId` | the company's PSA id | The client's ConnectWise company id |
| `tenantId` | the company's tenant id | Microsoft 365 tenant for Secure Score and MFA |
| `sites` | all sites | Datto RMM site names to include |
| `refreshCostPerDevice` | `1400` | Used for the estimated refresh budget |
| `timeZone` | `America/New_York` | Time zone for the reporting period and Updated date |
| `cloudradial_company` | none | Use that portal's `CloudRadial-*-<name>` runner secrets |
| `confirm` | `true` | `false` previews without writing tokens |

## Scoring

- **Service:** % of tickets closed in the last 90 days that were resolved within 3 days.
- **Security:** average of MFA, patch, antivirus and Secure Score (whichever are available).
- **Lifecycle:** % of devices that are current (not Windows 10, seen in the last 90 days).
- **Adoption:** % of the company's users active in the portal in 90 days, or Signal desktops signed in.
- **Overall:** the average of the four.

## Required runner Key Vault secrets

| Secret | Used for |
|---|---|
| `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | Tickets and projects |
| `Datto-ApiUrl`, `Datto-ApiKey`, `Datto-ApiSecret` | Devices |
| `M365-ClientId`, `M365-ClientSecret` | Optional. Secure Score and MFA |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Feedback, users and tokens |

## Notes

- The webhook ships disabled. Run it from a Routine or manually.
- Tested live in the AutomationAI test tenant on 2026-11-19: 134 tokens written from ConnectWise, Datto RMM and Microsoft Secure Score. Build with `node src/build.js`.
