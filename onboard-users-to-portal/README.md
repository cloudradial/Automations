# Onboard Many Portal Users at Once

Give it a list of people and they're added as portal users under the right company. Anyone who already has an account is skipped, so you never end up with duplicates.

## What happens

A technician runs it in AutomationAI with a company name and a list of people (email, first name and last name, plus job title, department or phone if you have them).

The CloudRadial UCP Assistant finds the company, checks each email against that company's existing users, and adds only the new ones. Before it creates anyone, it tells you exactly who it will add and waits for your approval. When it's done, you get a per-person result (created, skipped or error) and a one-line summary.

It replaces the old CSV import script.

## What it protects

- **No duplicates.** Each email is checked first. Running the same list twice won't create anyone twice.
- **Nothing is added without your OK.** Every new user waits for approval in AutomationAI.
- **No guessing.** If the company name matches more than one company, it lists the candidates and stops. It never makes up values.

## Works with

CloudRadial only. No PSA is needed.

## What you need

- AutomationAI
- The **CloudRadial UCP Assistant** agent, imported in AutomationAI
- The CloudRadial Companies extension, installed and connected in AutomationAI

## Set it up

1. **Import the agent** (skip if it's already installed). Download the [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) and upload it on **Agents > Custom > Import**.
2. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/onboard-users-to-portal/v1.0.0).
3. Go to **Workflows > Import** and upload it.
4. Click **Publish**, then **Deploy**.
5. Open the workflow and run it from **Test** with the company name and your list of people. The technical details show the exact format.
6. Approve the new users when they appear for approval.

**Test it.** Run it with one new person and one person who already has an account at Contoso, and check that only the new person is added.

## Need more detail?

See the [technical details](https://github.com/cloudradial/Automations/tree/main/onboard-users-to-portal#technical-details) for the input format and how the workflow is built.

---

## Technical details

**Formerly:** User Management bulk import script | **Marketplace ID:** AAI-00006 | **Type:** Workflow (runs the CloudRadial UCP Assistant agent) | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/onboard-users-to-portal/v1.0.0).

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **CloudRadial UCP Assistant** agent, [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/cloudradial-ucp/cloudradial-ucp.agent.yml) from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`onboard-users-to-portal.yml`](https://github.com/cloudradial/Automations/blob/main/onboard-users-to-portal/onboard-users-to-portal.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `onboard-users-to-portal.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/onboard-users-to-portal/onboard-users-to-portal.yml) |
| Download `onboard-users-to-portal.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/onboard-users-to-portal/v1.0.0) |
| Needs the agent | [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) |
| All files in this automation | [onboard-users-to-portal](https://github.com/cloudradial/Automations/tree/main/onboard-users-to-portal) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/onboard-users-to-portal) |
| Marketplace listing | [AAI-00006](https://automations.cloudradial.com/marketplace/AAI-00006) |

## How it works

Bulk-add portal users under a company from a list, without the old CSV import script. A thin **workflow** hands the list to the **CloudRadial UCP Assistant** agent, which resolves the company, skips users that already exist by email, and creates the rest approval-gated.

`Start → Read users (validate the run input) → Onboard users (Agent node running cloudradial-ucp-assistant) → End`. The agent resolves the company, then searches each email before creating, so re-runs don't duplicate.

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
2. Make sure the **`cloudradial-v2-companies`** extension (which carries the user tools) is installed and connected.
3. On **Workflows → Import**, upload `onboard-users-to-portal.yml`, then **Publish** and **deploy** it to your runner.
4. Run it from **Test** (or a form/Automation webhook) with the input below.

## Input

```json
{"companyName":"Acme Ltd","users":[{"email":"ann.lee@acme.com","firstName":"Ann","lastName":"Lee","title":"Operations"},{"email":"bo.ng@acme.com","firstName":"Bo","lastName":"Ng"}]}
```

Pass `companyName` **or** `companyId`. Each user needs `email`, `firstName`, `lastName`; `title`, `department`, `phoneNumber` are optional.

## Notes

- Every create is **approval-gated** (`autoApprove: false`). Set the Agent node to `autoApprove: true` only for a trusted unattended run.
- **Requires:** AutomationAI + the CloudRadial UCP Assistant agent + the `cloudradial-v2-companies` extension.
