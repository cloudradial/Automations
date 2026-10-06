# Onboard Many Portal Users at Once

Give it a list of people and they're added as portal users under the right company, with anyone who already has an account skipped.

**Formerly:** User Management bulk import script | **Marketplace ID:** AAI-00006 | **Type:** Workflow (runs the CloudRadial UCP Assistant agent)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **CloudRadial UCP Assistant** agent, [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/cloudradial-ucp/cloudradial-ucp.agent.yml) from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`onboard-users-to-portal.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/onboard-users-to-portal/onboard-users-to-portal.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `onboard-users-to-portal.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/onboard-users-to-portal/onboard-users-to-portal.yml) |
| Download `onboard-users-to-portal.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/onboard-users-to-portal/onboard-users-to-portal.yml) |
| Needs the agent | [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp) |
| All files in this automation | [automationai/onboard-users-to-portal](https://github.com/cloudradial/Automations/tree/main/automationai/onboard-users-to-portal) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/onboard-users-to-portal) |
| Marketplace listing | [AAI-00006](https://automations.cloudradial.com/marketplace/AAI-00006) |

## How it works

Bulk-add portal users under a company from a list, without the old CSV import script. A thin **workflow** hands the list to the **CloudRadial UCP Assistant** agent, which resolves the company, skips users that already exist by email, and creates the rest approval-gated.

`Start → Read users (validate the run input) → Onboard users (Agent node running cloudradial-ucp-assistant) → End`. The agent resolves the company, then searches each email before creating, so re-runs don't duplicate.

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
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
