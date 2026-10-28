# Load Your Request Forms into Any Portal

Give AutomationAI a list of service request forms and their questions, and it builds them in a client's portal for you. Forms that already exist are skipped, and nothing is created until you approve it.

## What happens

Someone on your team runs the workflow with the client company's name and the forms you want, for example "New Laptop Request" under Hardware, with questions like "Preferred model" and "Justification". The CloudRadial UCP Assistant checks each form by name. If the client's portal already has it, it's skipped. If not, the assistant asks for your approval, creates the form, then adds its questions in order.

Once it's done, your clients see the new request forms in their portal's service catalog, ready to use.

## What it protects

- **No duplicates.** Each form is looked up by name first, so running the same list twice is safe.
- **You approve every change.** Each form and each question waits in your AutomationAI **Inbox** until you say yes, so a form with many questions means several approvals.
- **Nothing made up.** Only the forms and questions in your list are created.

## Works with

CloudRadial only. No PSA is needed.

You can also use it to **copy** forms from one portal to another: read the forms from the first portal, then feed that list in here.

## What you need

- AutomationAI
- The **CloudRadial UCP Assistant** agent, imported into AutomationAI
- The CloudRadial content extension, installed and connected

## Set it up

**Once, in AutomationAI:**

1. If you don't have it yet, import the [CloudRadial UCP Assistant agent](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) on **Agents > Custom > Import**.
2. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/import-service-catalog/v1.0.0).
3. Go to **Workflows > Import** and upload it.
4. Click **Publish**, then **Deploy**.

**Each time you want to load forms:**

1. Open the workflow and click **Test**.
2. Enter the client company, then each form with its name, category and questions. Descriptions, answer choices and placeholder text are optional (the technical details show the format).
3. Approve each form and question in your **Inbox**.

**Test it.** Load one simple form into a test company such as Contoso, approve it, and check it shows up in that portal's service catalog.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/import-service-catalog#technical-details) show the full list format and how the workflow and agent fit together.

---

## Technical details

**Formerly:** Service Catalog export/import script | **Marketplace ID:** AAI-00003 | **Type:** Workflow (runs the CloudRadial UCP Assistant agent) | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/import-service-catalog/v1.0.0).

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **CloudRadial UCP Assistant** agent, [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/cloudradial-ucp/cloudradial-ucp.agent.yml) from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`import-service-catalog.yml`](https://github.com/cloudradial/Automations/blob/main/import-service-catalog/import-service-catalog.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `import-service-catalog.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/import-service-catalog/import-service-catalog.yml) |
| Download `import-service-catalog.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/import-service-catalog/v1.0.0) |
| Needs the agent | [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) |
| All files in this automation | [import-service-catalog](https://github.com/cloudradial/Automations/tree/main/import-service-catalog) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/import-service-catalog) |
| Marketplace listing | [AAI-00003](https://automations.cloudradial.com/marketplace/AAI-00003) |

## How it works

Create service-catalog items and their questions in a CloudRadial portal from a list, without the old export/import script. A thin **workflow** hands the list to the **CloudRadial UCP Assistant** agent, which skips catalog items that already exist by subject and creates the rest (and their questions) approval-gated.

`Start → Read catalog items (validate the run input) → Create catalog items (Agent node running cloudradial-ucp-assistant) → End`. The agent creates each catalog item, then its questions against the new catalog id; it searches by subject first, so re-runs don't duplicate.

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
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
