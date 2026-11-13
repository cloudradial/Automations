# Client Value Review

Turn 30, 60 or 90 days of PSA tickets into a branded value review for a client, with Planner cards for the endpoints that need attention and a QBR prep card your account manager can work from.

## What your clients see in the portal

Nothing until you share it. The review is posted to the client's **Report Archives**, which only your team can see. When you're ready, walk the client through it in the QBR or share it from there.

The review uses the client's own portal colors and logo, so it looks like part of their portal:
- **Service summary:** tickets opened and closed, hours delivered, average time to close, and charts by week.
- **What they asked for help with:** the top issue types, in plain words.
- **Value delivered:** hours delivered at your hourly rate, compared with what the client paid.
- **Endpoints:** how many computers to replace, plan to replace, upgrade or keep.

## What happens behind the scenes

- **Endpoint lifecycle Planner cards.** One card per refresh category (Replace, Plan replacement, Upgrade in place, Retain, Needs data, Human review, Virtual machines), each listing its computers in plain language. Reruns update the cards instead of adding new ones.
- **QBR prep card.** A Planner card with the period's numbers, an endpoint refresh plan and talking points for the meeting.
- **An internal account health section** for your team only. It never goes to the client.
- **Money is hidden when there's nothing to show,** for example when the client has no agreements or no billable hours.

## Works with

ConnectWise PSA. Other PSAs aren't supported yet.

## What you need

- A UCP portal with **Actions** on your request forms
- AutomationAI, with ConnectWise and CloudRadial connected
- Endpoints in CloudRadial (from your RMM) for the lifecycle cards

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://raw.githubusercontent.com/cloudradial/Automations/main/client-value-review/client-value-review.yml) (right-click > Save link as).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.
4. Optionally set your hourly rate, logo and tagline (see the [technical details](https://github.com/cloudradial/Automations/tree/main/client-value-review#technical-details)).

**In your UCP portal, add the Client Value Review form:**

1. Create a request form called **Client Value Review** in an admin-only category (for example **Operations**).
2. Add a **Comment** question, "Subject", with the default value `@CompanyName Value Review`, and tick **Use as subject**.
3. Add a **Dropdown** question, "Review Timeframe", with the options `30 Days,60 Days,90 Days`. Set its Field ID to `reviewTimeframe`.
4. At the end of the form, add an **Action** question and pick **Client Value Review**.

The [form file](https://github.com/cloudradial/Automations/blob/main/client-value-review/forms/client-value-review.json) has every setting.

**Test it.** Submit the form for one client, then open that client's **Report Archives** and **Planner**.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/client-value-review#technical-details) cover each step, the secrets and how the numbers are worked out.

---

## Technical details

**Formerly:** Value Review | **Marketplace ID:** CRA-00006 | **Type:** Workflow (PowerShell, no AI) | **Version:** 1.0.0

## Files

| What | Link |
|---|---|
| View `client-value-review.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/client-value-review/client-value-review.yml) |
| Download `client-value-review.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/client-value-review/client-value-review.yml) |
| Portal form | [forms/client-value-review.json](https://github.com/cloudradial/Automations/blob/main/client-value-review/forms/client-value-review.json) |
| Step sources and build script | [src/](https://github.com/cloudradial/Automations/tree/main/client-value-review/src) |
| All files in this automation | [client-value-review](https://github.com/cloudradial/Automations/tree/main/client-value-review) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/client-value-review) |

## How it works

```
Start -> Build Review Data -> Lookup CloudRadial Company -> Endpoint lifecycle cards -> Add to QBR prep card -> Finalize Review Outputs -> Post to Report Archive -> End
```

1. **Build Review Data** reads the form (company and `reviewTimeframe`), finds the ConnectWise company, and reads its tickets, time entries and agreements for the period. It works out the KPIs and charts, and takes the brand from the client's portal (`portalThemeColor`, `portalLogoUrl`). Without those it uses the default navy palette and your `ValueReview-LogoUrl`.
2. **Lookup CloudRadial Company** matches the ConnectWise company to the CloudRadial company.
3. **Endpoint lifecycle cards** sorts the company's endpoints into refresh categories and keeps one Planner card per category.
4. **Add to QBR prep card** keeps one QBR prep Planner card per company with the period's numbers, the refresh plan and talking points.
5. **Finalize Review Outputs** assembles the client report and the internal sections.
6. **Post to Report Archive** posts the review to the company's Report Archives (admin-only).

Value Delivered = Hours Delivered x Hourly Rate. Client Savings = Value Delivered - Amount Paid. Covered Hours are hours charged to an agreement or marked NoCharge or DoNotBill. The formula is printed in the report footer.

## Required runner Key Vault secrets

| Secret | Used for |
|---|---|
| `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | Tickets, time entries and agreements |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Company, endpoints, Planner cards and Report Archives |
| `ValueReview-HourlyRate` (optional) | The hourly rate for Value Delivered. Without it, $150 is used and the report says so |
| `ValueReview-LogoUrl` (optional) | Your logo, used when the client's portal has none. Without it the banner has no logo |
| `ValueReview-Tagline` (optional) | A line under the banner title. Without it there is none |

## Inputs

From the form: the ticket's company and `reviewTimeframe` (`30 Days`, `60 Days` or `90 Days`). When it's blank, the review covers the last 12 months.

## Notes

- The webhook ships disabled. The form's **Action** question runs it.
- Exported from the AutomationAI test tenant (tenant version 0.0.14) on 2026-11-12, then split into `src/` with tenant-specific names removed. Build with `node src/build.js`. A strict-mode test harness (`src/test.ps1`) is still to be written.

## Tested

Run on a demo client with 117 endpoints in the test tenant: Report Archive posted, 3 lifecycle cards (Replace 20, Plan replacement 27, Human review 2) and the QBR prep card created.
