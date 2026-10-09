# Add Many KB Articles at Once

Give it a list of articles and they're created in the client's knowledge base, with any that already exist skipped.

**Formerly:** Article Bulk Import script | **Marketplace ID:** AAI-00025 | **Type:** Workflow (runs the CloudRadial UCP Assistant agent)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **CloudRadial UCP Assistant** agent, [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/cloudradial-ucp/cloudradial-ucp.agent.yml) from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`bulk-create-kb-articles.yml`](https://github.com/cloudradial/Automations/blob/main/bulk-create-kb-articles/bulk-create-kb-articles.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `bulk-create-kb-articles.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/bulk-create-kb-articles/bulk-create-kb-articles.yml) |
| Download `bulk-create-kb-articles.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/bulk-create-kb-articles/bulk-create-kb-articles.yml) |
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
