# Bulk-Create KB Articles

Create many knowledge-base articles in a CloudRadial portal from a list, without the old CSV import script. A thin **workflow** hands the list to the **CloudRadial UCP Assistant** agent, which skips articles that already exist by subject and creates the rest approval-gated.

**Formerly:** Article Bulk Import script (**AAI-00025**) | **Type:** Workflow (runs an agent)

## How it works

`Start → Read articles (validate the run input) → Create articles (Agent node running cloudradial-ucp-assistant) → End`. The agent searches by subject before each create, so re-runs don't duplicate.

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](../cloudradial-ucp/) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
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
