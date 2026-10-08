# Bring IT Glue Documentation into the Portal

Copies an IT Glue flexible asset type and its records into a client's portal as flexible assets, so documentation lives where clients and technicians already look.

**Formerly:** Flexible Assets / IT Glue sync script | **Marketplace ID:** AAI-00004 | **Type:** Workflow (runs the CloudRadial UCP Assistant agent)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **CloudRadial UCP Assistant** agent, [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/cloudradial-ucp/cloudradial-ucp.agent.yml) from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`itglue-to-flexible-assets.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/itglue-to-flexible-assets/itglue-to-flexible-assets.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `itglue-to-flexible-assets.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/itglue-to-flexible-assets/itglue-to-flexible-assets.yml) |
| Download `itglue-to-flexible-assets.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/itglue-to-flexible-assets/itglue-to-flexible-assets.yml) |
| Needs the agent | [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp) |
| All files in this automation | [automationai/itglue-to-flexible-assets](https://github.com/cloudradial/Automations/tree/main/automationai/itglue-to-flexible-assets) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/itglue-to-flexible-assets) |
| Marketplace listing | [AAI-00004](https://automations.cloudradial.com/marketplace/AAI-00004) |

## How it works

Copy an IT Glue **flexible-asset type** and its records into a CloudRadial company as **flexible assets**, without the old PowerShell sync script. A thin **workflow** hands the job to the **CloudRadial UCP Assistant** agent, which reads from IT Glue and writes to CloudRadial, matching existing records so re-runs update rather than duplicate.

`Start → Read inputs → Sync flexible assets (Agent node running cloudradial-ucp-assistant) → End`. The agent:

1. Resolves the CloudRadial company and the IT Glue organization by name.
2. Reads the IT Glue flexible-asset type's trait field names (never guesses them).
3. Ensures a matching CloudRadial flexible-asset type exists (creates it with a field per trait if missing).
4. Lists the IT Glue records for that type, and for each **matches on a de-dup trait** — updating a changed record or creating a new one.

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
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
