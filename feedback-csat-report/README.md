# See Each Client's Satisfaction Score in Their Planner

Turn the feedback your clients leave in the portal into a satisfaction (CSAT) score and short summary, on one Planner card per client, refreshed every time it runs.

## What happens

On each run, every client that has left feedback gets a **Feedback & CSAT Report** card in their Planner. It's a handy thing to have ready before a quarterly review.

The card says, in plain sentences:

- how many feedback responses came in
- what share of them were positive
- the average rating
- up to three recent comments

## What happens behind the scenes

- **No duplicate cards.** Each run updates the client's existing card instead of adding another.
- **Clients without feedback are left alone.** No empty cards are created.
- **It only reads feedback.** Nothing about the feedback itself changes.
- **Cards land in the Efficiency category** of the Planner by default.

## Works with

CloudRadial only. No PSA is needed.

## What you need

- AutomationAI, with your CloudRadial API connected
- An **Efficiency** category in your Planner (or another category you choose)

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/feedback-csat-report/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.
4. Attach a schedule (a **Routine**) so it runs on its own, for example monthly ahead of your quarterly reviews. You can also run it on demand.

Optionally, limit it to recent feedback, such as the last 90 days. By default it uses all feedback. If your Planner uses a different category than **Efficiency**, change it in the workflow before you publish.

**Test it.** Run it once, then open the Planner for a client that has left feedback and check for the **Feedback & CSAT Report** card.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/feedback-csat-report#technical-details) cover how the score is worked out, the settings to confirm in your tenant, and what each run reports.

---

## Technical details

**Formerly:** Feedback & CSAT Report | **Marketplace ID:** AAI-00022 | **Type:** Workflow | **Version:** 1.0.0

## Files

Each version is published as a release, with `feedback-csat-report.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/feedback-csat-report/v1.0.0).

| What | Link |
|---|---|
| Download `feedback-csat-report.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/feedback-csat-report/v1.0.0) |
| View the current source | [`feedback-csat-report.yml`](https://github.com/cloudradial/Automations/blob/main/feedback-csat-report/feedback-csat-report.yml) |
| All files in this automation | [feedback-csat-report](https://github.com/cloudradial/Automations/tree/main/feedback-csat-report) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/feedback-csat-report) |
| Marketplace listing | [AAI-00022](https://automations.cloudradial.com/marketplace/AAI-00022) |

## How it works

A scheduled **workflow** that reads CloudRadial feedback, works out a CSAT summary per company, and writes one plain-language **Feedback & CSAT Report** Planner card per company. It's the AutomationAI version of the `Get-FeedbackReport.ps1` helper, the CSV export becomes Planner cards. No agent, a single PowerShell script node.

## Pieces

| File | Type | Role |
|---|---|---|
| [`feedback-csat-report.yml`](https://github.com/cloudradial/Automations/blob/main/feedback-csat-report/feedback-csat-report.yml) | `automationsWorkflow` | Reads `/v2/odata/feedback` and companies, groups responses by company, calculates % positive and average rating, and creates or updates one card per company (matched by subject, so re-runs update in place). |

## Install / run

1. Import `feedback-csat-report.yml` on **Workflows → Import**.
2. Add the CloudRadial API secrets to the runner Key Vault: `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` (the workflow errors listing any missing).
3. Publish and deploy to that runner, then schedule it as a **Routine** (for example monthly, ahead of QBRs), or run it on demand.
4. Optional input `DaysBack` limits the window, e.g. `{"DaysBack": 90}`. Omit it to use all feedback.

## What lands in CloudRadial

- One Planner card per company with feedback, subject **Feedback & CSAT Report**, category **Efficiency** (product category id `7`).
- Card body in plain sentences: responses, % positive, average rating, and up to three recent comments.
- Run output: `counts` (feedback, companies, cardsCreated, cardsUpdated, errors) and a per-company `report`.

## Confirm in your tenant

- The Planner category name and id at the top of the script (`$PlannerCategory`, `$PlannerProductCategoryId`) exist in your portal, change them if not.
- Replaces the legacy `feedback-analysis` script listed on the marketplace as **AAI-00022**.
- The webhook ships disabled; you only need it if something other than a Routine triggers the report.
