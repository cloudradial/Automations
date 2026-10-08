# Load Your Request Forms into Any Portal

Give it a list of service request forms and their questions and they're created in the client's portal, with forms that already exist skipped.

**Formerly:** Service Catalog export/import script | **Marketplace ID:** AAI-00003 | **Type:** Workflow (runs the CloudRadial UCP Assistant agent)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **CloudRadial UCP Assistant** agent, [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/cloudradial-ucp/cloudradial-ucp.agent.yml) from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`import-service-catalog.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/import-service-catalog/import-service-catalog.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `import-service-catalog.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/import-service-catalog/import-service-catalog.yml) |
| Download `import-service-catalog.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/import-service-catalog/import-service-catalog.yml) |
| Needs the agent | [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp) |
| All files in this automation | [automationai/import-service-catalog](https://github.com/cloudradial/Automations/tree/main/automationai/import-service-catalog) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/import-service-catalog) |
| Marketplace listing | [AAI-00003](https://automations.cloudradial.com/marketplace/AAI-00003) |

## How it works

Create service-catalog items and their questions in a CloudRadial portal from a list, without the old export/import script. A thin **workflow** hands the list to the **CloudRadial UCP Assistant** agent, which skips catalog items that already exist by subject and creates the rest (and their questions) approval-gated.

`Start → Read catalog items (validate the run input) → Create catalog items (Agent node running cloudradial-ucp-assistant) → End`. The agent creates each catalog item, then its questions against the new catalog id; it searches by subject first, so re-runs don't duplicate.

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
2. Make sure the **`cloudradial-v2-content`** extension is installed and connected.
3. On **Workflows → Import**, upload `import-service-catalog.yml`, then **Publish** and **deploy** it to your runner.
4. Run it from **Test** with the input below.

## Input

```json
{"companyName":"Acme Ltd","catalogs":[{"subject":"New Laptop Request","category":"Hardware","shortDescription":"Request a new laptop","questions":[{"label":"Preferred model","placeholder":"e.g. Dell 5570"},{"label":"Justification"}]}]}
```

Pass `companyName` **or** `companyId`. Each catalog item needs `subject` and `category`; `description`, `shortDescription`, and a `questions` array are optional. Each question needs a `label`; `options` (pipe-separated), `placeholder`, `defaultValue` are optional.

## Notes

- Every create is **approval-gated** (`autoApprove: false`). An item with many questions means several approvals.
- To **copy** a catalog between portals, read it from the source with the content extension first, then feed that JSON here.
- **Requires:** AutomationAI + the CloudRadial UCP Assistant agent + the `cloudradial-v2-content` extension.
