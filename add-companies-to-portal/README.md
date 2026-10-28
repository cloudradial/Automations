# Add Many Client Companies at Once

Give AutomationAI a list of client companies and it adds them to CloudRadial for you. Companies that are already there are skipped, and nothing is created until you approve it.

## What happens

Someone on your team runs the workflow with a list of company names. For each name, the CloudRadial UCP Assistant checks whether the company already exists in CloudRadial. If it does, it's skipped. If not, the assistant asks for your approval and then creates it, filling in only the details you gave, such as account manager or city.

At the end you get a short result for every company: added, or skipped because it already exists.

## What it protects

- **No duplicates.** Each company is looked up by name first, so running the same list twice is safe.
- **You approve every company.** Each one waits in your AutomationAI **Inbox** until you say yes.
- **Nothing made up.** Only the details in your list are filled in.

## Works with

CloudRadial only. No PSA is needed.

## What you need

- AutomationAI
- The **CloudRadial UCP Assistant** agent, imported into AutomationAI
- The CloudRadial companies extension, installed and connected

## Set it up

**Once, in AutomationAI:**

1. If you don't have it yet, import the [CloudRadial UCP Assistant agent](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) on **Agents > Custom > Import**.
2. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/add-companies-to-portal/v1.0.0).
3. Go to **Workflows > Import** and upload it.
4. Click **Publish**, then **Deploy**.

**Each time you have companies to add:**

1. Open the workflow and click **Test**.
2. Paste your list of company names, one per line. You can also give an account manager, city, territory or PSA identifier for each company (the technical details show the format).
3. Approve each company in your **Inbox**.

**Test it.** Run it with one made-up name, such as "Contoso Test", approve it, and check it appears under your companies in CloudRadial.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/add-companies-to-portal#technical-details) show the full list format and how the workflow and agent fit together.

---

## Technical details

**Formerly:** Company Management bulk-add script | **Marketplace ID:** AAI-00002 | **Type:** Workflow (runs the CloudRadial UCP Assistant agent) | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/add-companies-to-portal/v1.0.0).

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **CloudRadial UCP Assistant** agent, [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/cloudradial-ucp/cloudradial-ucp.agent.yml) from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`add-companies-to-portal.yml`](https://github.com/cloudradial/Automations/blob/main/add-companies-to-portal/add-companies-to-portal.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `add-companies-to-portal.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/add-companies-to-portal/add-companies-to-portal.yml) |
| Download `add-companies-to-portal.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/add-companies-to-portal/v1.0.0) |
| Needs the agent | [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) |
| All files in this automation | [add-companies-to-portal](https://github.com/cloudradial/Automations/tree/main/add-companies-to-portal) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/add-companies-to-portal) |
| Marketplace listing | [AAI-00002](https://automations.cloudradial.com/marketplace/AAI-00002) |

## How it works

Bulk-add client companies to CloudRadial from a list, without the old PowerShell CSV script. A thin **workflow** hands a list to the **CloudRadial UCP Assistant** agent, which creates each company approval-gated and skips any that already exist.

`Start → Read companies (validate the run input) → Add companies (Agent node running cloudradial-ucp-assistant) → End`. The agent searches by name before each create, so re-runs don't duplicate.

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
2. Make sure the **`cloudradial-v2-companies`** extension is installed and connected.
3. On **Workflows → Import**, upload `add-companies-to-portal.yml`, then **Publish** and **deploy** it to your runner.
4. Run it from **Test** (or a form/Automation webhook) with the input below.

## Input

```json
{"companies":[{"name":"Acme Ltd","accountManager":"jsmith@msp.com","city":"Austin"},{"name":"Globex Inc"}]}
```

Each company needs a `name`; `accountManager`, `city`, `territory`, `psaIdentifier` are optional. A bare JSON array, or a newline/comma list of names, also works.

## Notes

- Every create is **approval-gated** (`autoApprove: false`); each company waits in the Inbox until you approve it. Set the Agent node to `autoApprove: true` only for a trusted unattended run.
- **Requires:** AutomationAI + the CloudRadial UCP Assistant agent + the `cloudradial-v2-companies` extension.
