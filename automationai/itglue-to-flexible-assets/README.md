# Sync IT Glue Documentation into the Portal

Copy an IT Glue **flexible-asset type** and its records into a CloudRadial company as **flexible assets**, without the old PowerShell sync script. A thin **workflow** hands the job to the **CloudRadial UCP Assistant** agent, which reads from IT Glue and writes to CloudRadial, matching existing records so re-runs update rather than duplicate.

**Formerly:** Flexible Assets / IT Glue sync script (**AAI-00004**) | **Type:** Workflow (runs an agent)

## How it works

`Start → Read inputs → Sync flexible assets (Agent node running cloudradial-ucp-assistant) → End`. The agent:

1. Resolves the CloudRadial company and the IT Glue organization by name.
2. Reads the IT Glue flexible-asset type's trait field names (never guesses them).
3. Ensures a matching CloudRadial flexible-asset type exists (creates it with a field per trait if missing).
4. Lists the IT Glue records for that type, and for each **matches on a de-dup trait** — updating a changed record or creating a new one.

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](../cloudradial-ucp/) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
2. Install and connect both extensions: **`it-glue`** (secrets `ITGlue-ApiUrl`, `ITGlue-ApiKey`) and **`cloudradial-v2-compliance`** (0.2.1+).
3. On **Workflows → Import**, upload `itglue-to-flexible-assets.yml`, then **Publish** and **deploy** to your runner.
4. Run it from **Test** with the input below. Do one asset type per run.

## Input

```json
{"companyName":"Acme Ltd","itglueOrgName":"Acme","flexibleAssetTypeName":"SSL Certificates","matchTrait":"name"}
```

Pass the CloudRadial company (`companyName` **or** `companyId`), the `itglueOrgName`, and the `flexibleAssetTypeName` to copy. `matchTrait` is the trait used to avoid duplicates (defaults to `name`).

## Notes

- Every create/update is **approval-gated** (`autoApprove: false`). IT Glue **password values are never surfaced** — only metadata.
- One flexible-asset type per run. For a **very large estate**, a deterministic PowerShell version (like `scalepad-cloudradial-sync`) scales better than an agent — build that if volumes are high.
- **Requires:** AutomationAI + the CloudRadial UCP Assistant agent + the `it-glue` and `cloudradial-v2-compliance` extensions.
