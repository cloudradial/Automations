# Add Many KB Articles at Once

Give it a list of articles and they're created in a client's knowledge base in your CloudRadial portal. Any article that already exists is skipped, so nothing is duplicated.

## What happens

A technician runs it in AutomationAI with a company name and a list of articles. Each article needs a subject and its body text (the body can include formatting), and can also have a category and author.

The CloudRadial UCP Assistant finds the company, checks each subject against the articles already there, and creates only the new ones. Before it creates anything, it tells you exactly what it will add and waits for your approval. When it's done, you get a per-article result (created, skipped or error) and a one-line summary.

It replaces the old CSV import script.

## What it protects

- **No duplicates.** Each subject is checked first. Running the same list twice won't create an article twice.
- **Nothing is added without your OK.** Every new article waits for approval in AutomationAI.
- **No made-up content.** It uses only the text you give it. If the company name matches more than one company, it lists the candidates and stops.

## Works with

CloudRadial only. No PSA is needed.

## What you need

- AutomationAI
- The **CloudRadial UCP Assistant** agent, imported in AutomationAI
- The CloudRadial Content extension, installed and connected in AutomationAI

## Set it up

1. **Import the agent** (skip if it's already installed). Download the [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) and upload it on **Agents > Custom > Import**.
2. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/bulk-create-kb-articles/v1.0.0).
3. Go to **Workflows > Import** and upload it.
4. Click **Publish**, then **Deploy**.
5. Open the workflow and run it from **Test** with the company name and your list of articles. The technical details show the exact format.
6. Approve the new articles when they appear for approval.

**Test it.** Run it for Contoso with one new article and one whose subject already exists, and check that only the new one is created.

## Need more detail?

See the [technical details](https://github.com/cloudradial/Automations/tree/main/bulk-create-kb-articles#technical-details) for the input format and how the workflow is built.

---

## Technical details

**Formerly:** Article Bulk Import script | **Marketplace ID:** AAI-00025 | **Type:** Workflow (runs the CloudRadial UCP Assistant agent) | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/bulk-create-kb-articles/v1.0.0).

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **CloudRadial UCP Assistant** agent, [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/cloudradial-ucp/cloudradial-ucp.agent.yml) from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`bulk-create-kb-articles.yml`](https://github.com/cloudradial/Automations/blob/main/bulk-create-kb-articles/bulk-create-kb-articles.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `bulk-create-kb-articles.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/bulk-create-kb-articles/bulk-create-kb-articles.yml) |
| Download `bulk-create-kb-articles.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/bulk-create-kb-articles/v1.0.0) |
| Needs the agent | [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) |
| All files in this automation | [bulk-create-kb-articles](https://github.com/cloudradial/Automations/tree/main/bulk-create-kb-articles) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/bulk-create-kb-articles) |
| Marketplace listing | [AAI-00025](https://automations.cloudradial.com/marketplace/AAI-00025) |

## How it works

Create many knowledge-base articles in a CloudRadial portal from a list, without the old CSV import script. A thin **workflow** hands the list to the **CloudRadial UCP Assistant** agent, which skips articles that already exist by subject and creates the rest approval-gated.

`Start → Read articles (validate the run input) → Create articles (Agent node running cloudradial-ucp-assistant) → End`. The agent searches by subject before each create, so re-runs don't duplicate.

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
2. Make sure the **`cloudradial-v2-content`** extension is installed and connected.
3. On **Workflows → Import**, upload `bulk-create-kb-articles.yml`, then **Publish** and **deploy** it to your runner.
4. Run it from **Test** with the input below.

## Input

```json
{"companyName":"Acme Ltd","articles":[{"subject":"How to connect to the VPN","category":"Networking","body":"<p>Open the client and sign in.</p>"}]}
```

Pass `companyName` **or** `companyId`. Each article needs `subject` and `body`; `category` and `author` are optional. `body` is HTML.

## Notes

- Every create is **approval-gated** (`autoApprove: false`).
- **Requires:** AutomationAI + the CloudRadial UCP Assistant agent + the `cloudradial-v2-content` extension.
