# Import Service Catalog Items

Create service-catalog items and their questions in a CloudRadial portal from a list, without the old export/import script. A thin **workflow** hands the list to the **CloudRadial UCP Assistant** agent, which skips catalog items that already exist by subject and creates the rest (and their questions) approval-gated.

**Formerly:** Service Catalog export/import script (**AAI-00003**) | **Type:** Workflow (runs an agent)

## How it works

`Start → Read catalog items (validate the run input) → Create catalog items (Agent node running cloudradial-ucp-assistant) → End`. The agent creates each catalog item, then its questions against the new catalog id; it searches by subject first, so re-runs don't duplicate.

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](../cloudradial-ucp/) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
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
