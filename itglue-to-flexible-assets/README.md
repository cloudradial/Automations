# Bring IT Glue Documentation into the Portal

Copy a type of IT Glue documentation, such as SSL Certificates, into a client's portal as flexible assets. Your documentation then lives where your clients and technicians already look.

## What happens

Someone on your team runs the workflow with three things: the client company in CloudRadial, the matching organization in IT Glue, and the IT Glue asset type to copy. The CloudRadial UCP Assistant reads that asset type's fields from IT Glue, makes a matching flexible asset type in CloudRadial if there isn't one yet, then copies each record across.

If a record is already in the portal, it's updated when something changed instead of being added twice. The documentation then shows under flexible assets in that client's portal.

## What it protects

- **Passwords stay in IT Glue.** Password values are never shown or copied, only their details.
- **No duplicates.** Records are matched by name (or another field you choose), so running it again updates instead of duplicating.
- **You approve every change.** Each create or update waits in your AutomationAI **Inbox** until you say yes.
- **No guessing.** Field names are read from IT Glue, never made up.

## Works with

IT Glue and CloudRadial. No PSA is needed.

- **One asset type per run.** Run it again for each type you want to copy.
- **Very large estates:** a scripted sync would scale better than this assistant-driven one.

## What you need

- AutomationAI
- The **CloudRadial UCP Assistant** agent, imported into AutomationAI
- IT Glue, connected in AutomationAI through the IT Glue extension
- The CloudRadial compliance extension, installed and connected

## Set it up

**Once, in AutomationAI:**

1. If you don't have it yet, import the [CloudRadial UCP Assistant agent](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) on **Agents > Custom > Import**.
2. Install and connect the IT Glue and CloudRadial compliance extensions.
3. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/itglue-to-flexible-assets/v1.0.0).
4. Go to **Workflows > Import** and upload it.
5. Click **Publish**, then **Deploy**.

**Each time you want to copy documentation:**

1. Open the workflow and click **Test**.
2. Enter the client company, the IT Glue organization and the asset type name. Optionally, choose which field to match records on (it uses the name if you don't).
3. Approve each change in your **Inbox**.

**Test it.** Copy one small asset type for a test company such as Contoso, approve it, and check the records appear under flexible assets in that portal.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/itglue-to-flexible-assets#technical-details) show the exact input, the step-by-step sync, and the extension setup.

---

## Technical details

**Formerly:** Flexible Assets / IT Glue sync script | **Marketplace ID:** AAI-00004 | **Type:** Workflow (runs the CloudRadial UCP Assistant agent) | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/itglue-to-flexible-assets/v1.0.0).

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **CloudRadial UCP Assistant** agent, [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/cloudradial-ucp/cloudradial-ucp.agent.yml) from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`itglue-to-flexible-assets.yml`](https://github.com/cloudradial/Automations/blob/main/itglue-to-flexible-assets/itglue-to-flexible-assets.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `itglue-to-flexible-assets.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/itglue-to-flexible-assets/itglue-to-flexible-assets.yml) |
| Download `itglue-to-flexible-assets.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/itglue-to-flexible-assets/v1.0.0) |
| Needs the agent | [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) |
| All files in this automation | [itglue-to-flexible-assets](https://github.com/cloudradial/Automations/tree/main/itglue-to-flexible-assets) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/itglue-to-flexible-assets) |
| Marketplace listing | [AAI-00004](https://automations.cloudradial.com/marketplace/AAI-00004) |

## How it works

Copy an IT Glue **flexible-asset type** and its records into a CloudRadial company as **flexible assets**, without the old PowerShell sync script. A thin **workflow** hands the job to the **CloudRadial UCP Assistant** agent, which reads from IT Glue and writes to CloudRadial, matching existing records so re-runs update rather than duplicate.

`Start → Read inputs → Sync flexible assets (Agent node running cloudradial-ucp-assistant) → End`. The agent:

1. Resolves the CloudRadial company and the IT Glue organization by name.
2. Reads the IT Glue flexible-asset type's trait field names (never guesses them).
3. Ensures a matching CloudRadial flexible-asset type exists (creates it with a field per trait if missing).
4. Lists the IT Glue records for that type, and for each **matches on a de-dup trait**, updating a changed record or creating a new one.

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
2. Install and connect both extensions: **`it-glue`** (secrets `ITGlue-ApiUrl`, `ITGlue-ApiKey`) and **`cloudradial-v2-compliance`** (0.2.1+).
3. On **Workflows → Import**, upload `itglue-to-flexible-assets.yml`, then **Publish** and **deploy** to your runner.
4. Run it from **Test** with the input below. Do one asset type per run.

## Input

```json
{"companyName":"Acme Ltd","itglueOrgName":"Acme","flexibleAssetTypeName":"SSL Certificates","matchTrait":"name"}
```

Pass the CloudRadial company (`companyName` **or** `companyId`), the `itglueOrgName`, and the `flexibleAssetTypeName` to copy. `matchTrait` is the trait used to avoid duplicates (defaults to `name`).

## Notes

- Every create/update is **approval-gated** (`autoApprove: false`). IT Glue **password values are never surfaced**, only metadata.
- One flexible-asset type per run. For a **very large estate**, a deterministic PowerShell version (like `scalepad-cloudradial-sync`) scales better than an agent; build that if volumes are high.
- **Requires:** AutomationAI + the CloudRadial UCP Assistant agent + the `it-glue` and `cloudradial-v2-compliance` extensions.
