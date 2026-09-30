# Onboard Users into the Portal

Bulk-add portal users under a company from a list, without the old CSV import script. A thin **workflow** hands the list to the **CloudRadial UCP Assistant** agent, which resolves the company, skips users that already exist by email, and creates the rest approval-gated.

**Formerly:** User Management bulk import script (**AAI-00006**) | **Type:** Workflow (runs an agent)

## How it works

`Start → Read users (validate the run input) → Onboard users (Agent node running cloudradial-ucp-assistant) → End`. The agent resolves the company, then searches each email before creating, so re-runs don't duplicate.

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](../cloudradial-ucp/) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
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
