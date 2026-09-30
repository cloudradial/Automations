# Add Companies to the Portal

Bulk-add client companies to CloudRadial from a list, without the old PowerShell CSV script. A thin **workflow** hands a list to the **CloudRadial UCP Assistant** agent, which creates each company approval-gated and skips any that already exist.

**Formerly:** Company Management bulk-add script (**AAI-00002**) | **Type:** Workflow (runs an agent)

## How it works

`Start → Read companies (validate the run input) → Add companies (Agent node running cloudradial-ucp-assistant) → End`. The agent searches by name before each create, so re-runs don't duplicate.

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](../cloudradial-ucp/) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
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
