# Feedback & CSAT Report

A scheduled **workflow** that reads CloudRadial feedback, works out a CSAT summary per company, and writes one plain-language **Feedback & CSAT Report** Planner card per company. It's the AutomationAI version of the `Get-FeedbackReport.ps1` helper — the CSV export becomes Planner cards. No agent — a single PowerShell script node.

## Pieces

| File | Type | Role |
|---|---|---|
| [`feedback-csat-report.yml`](feedback-csat-report.yml) | `automationsWorkflow` | Reads `/v2/odata/feedback` and companies, groups responses by company, calculates % positive and average rating, and creates or updates one card per company (matched by subject, so re-runs update in place). |

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

- The Planner category name and id at the top of the script (`$PlannerCategory`, `$PlannerProductCategoryId`) exist in your portal — change them if not.
- Replaces the legacy `feedback-analysis` script listed on the marketplace as **AAI-00022**.
- The webhook ships disabled; you only need it if something other than a Routine triggers the report.
