# Add Many Client Companies at Once

Give it a list of client companies and they're added to CloudRadial, with any that already exist skipped and each addition approved first.

**Formerly:** Company Management bulk-add script | **Marketplace ID:** AAI-00002 | **Type:** Workflow (runs the CloudRadial UCP Assistant agent)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **CloudRadial UCP Assistant** agent, [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/cloudradial-ucp/cloudradial-ucp.agent.yml) from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`add-companies-to-portal.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/add-companies-to-portal/add-companies-to-portal.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `add-companies-to-portal.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/add-companies-to-portal/add-companies-to-portal.yml) |
| Download `add-companies-to-portal.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/add-companies-to-portal/add-companies-to-portal.yml) |
| Needs the agent | [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp) |
| All files in this automation | [automationai/add-companies-to-portal](https://github.com/cloudradial/Automations/tree/main/automationai/add-companies-to-portal) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/add-companies-to-portal) |
| Marketplace listing | [AAI-00002](https://automations.cloudradial.com/marketplace/AAI-00002) |

## How it works

Bulk-add client companies to CloudRadial from a list, without the old PowerShell CSV script. A thin **workflow** hands a list to the **CloudRadial UCP Assistant** agent, which creates each company approval-gated and skips any that already exist.

`Start → Read companies (validate the run input) → Add companies (Agent node running cloudradial-ucp-assistant) → End`. The agent searches by name before each create, so re-runs don't duplicate.

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
2. Make sure the **`cloudradial-v2-companies`** extension is installed and connected.
3. On **Workflows → Import**, upload `add-companies-to-portal.yml`, then **Publish** and **deploy** it to your runner.
4. Run it from **Test** (or a form/Automation webhook) with the input below.

## Input

```json
{"companies":[{"name":"Acme Ltd","accountManager":"jsmith@msp.com","city":"Austin"},{"name":"Globex Inc"}]}
```

Each company needs a `name`; `accountManager`, `city`, `territory`, `psaIdentifier` are optional. A bare JSON array, or a newline/comma list of names, also works.

## Notes

- Every create is **approval-gated** (`autoApprove: false`) — each company waits in the Inbox until you approve it. Set the Agent node to `autoApprove: true` only for a trusted unattended run.
- **Requires:** AutomationAI + the CloudRadial UCP Assistant agent + the `cloudradial-v2-companies` extension.
