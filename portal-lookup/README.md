# Walk Into Every Client Call Prepared

Get a one-page briefing on any client in seconds: their users, devices, warranties and portal setup gaps. It only reads. Nothing is changed.

## What happens

Before a client call, a technician runs it in AutomationAI and names the company. The CloudRadial UCP Assistant pulls together a briefing that starts with a short summary you could read aloud, then covers:

- **Company:** account manager, PSA link, and setup gaps such as a missing logo or no account manager
- **Users:** how many, and their roles
- **Devices:** how many, how many warranties have expired, and how many expire soon
- **Health:** anything that looks unconfigured, empty or out of date

Leave the company out and you get a portal-wide snapshot instead: the total number of companies, then the ones that stand out (most devices, most expired warranties, obvious setup gaps).

## What it protects

- **Read-only.** It's told never to create, change or delete anything. Even if it tried, the change would wait for your approval.
- **No guessing.** If the company name matches more than one company, it lists the candidates instead of picking one.

## Works with

CloudRadial only. No PSA is needed, and it only reads, never changes.

## What you need

- AutomationAI
- The **CloudRadial UCP Assistant** agent, imported in AutomationAI
- The CloudRadial Companies and Endpoints extensions, installed and connected in AutomationAI. The agent also expects the CloudRadial Compliance extension, though this briefing doesn't use it.

## Set it up

1. **Import the agent** (skip if it's already installed). Download the [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) and upload it on **Agents > Custom > Import**.
2. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/portal-lookup/v1.0.0).
3. Go to **Workflows > Import** and upload it.
4. Click **Publish**, then **Deploy**.
5. Run it from **Test** or the **Run** dialog. Name a company, or leave it empty for the portal-wide snapshot.

**Optional:** change how far ahead a warranty counts as "expiring soon" (90 days by default). To have the briefing sent somewhere instead of reading it in AutomationAI, add the [Deliver Result](https://github.com/cloudradial/Automations/tree/main/deliver-result) step after it.

**Test it.** Run it for Contoso and check the user and device counts match what you see in the portal.

## Need more detail?

See the [technical details](https://github.com/cloudradial/Automations/tree/main/portal-lookup#technical-details) for the inputs and how the workflow is built.

---

## Technical details

**Formerly:** Portal Lookup | **Marketplace ID:** AAI-00014 | **Type:** Agent | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/portal-lookup/v1.0.0).

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **CloudRadial UCP Assistant** agent, [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/cloudradial-ucp/cloudradial-ucp.agent.yml) from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`portal-lookup.yml`](https://github.com/cloudradial/Automations/blob/main/portal-lookup/portal-lookup.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `portal-lookup.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/portal-lookup/portal-lookup.yml) |
| Download `portal-lookup.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/portal-lookup/v1.0.0) |
| Needs the agent | [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) |
| All files in this automation | [portal-lookup](https://github.com/cloudradial/Automations/tree/main/portal-lookup) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/portal-lookup) |
| Marketplace listing | [AAI-00014](https://automations.cloudradial.com/marketplace/AAI-00014) |

## How it works

A CloudRadial **AutomationAI workflow** that produces a read-only portal briefing for meeting prep: company footprint, users, endpoints, warranty posture and setup gaps. Name a company and it briefs on that one; name none and it gives a portal-wide snapshot.

It runs the [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) agent with a read-only goal, so there's no separate agent to maintain.

## Pieces

| File | Type | Role |
|---|---|---|
| [`portal-lookup.yml`](https://github.com/cloudradial/Automations/blob/main/portal-lookup/portal-lookup.yml) | `automationsWorkflow` | **Run inputs** (fills in defaults and writes the request) → **Portal Briefing** (an Agent node running `cloudradial-ucp-assistant`). |

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
2. Make sure the first-party extensions `cloudradial-v2-companies` (which also carries the user tools) and `cloudradial-v2-endpoints` are installed and connected. The agent (0.1.4 and later) also requires `cloudradial-v2-compliance`, which this read-only briefing doesn't use.
3. On **Workflows → Import**, upload `portal-lookup.yml`, then **Publish** and **deploy** it to your runner.
4. Run it from **Test** or the Run dialog. Leave the Trigger input empty for a portal-wide snapshot, or send one of the inputs below.

## Inputs

All optional.

| Field | Default | What it does |
|---|---|---|
| `companyName` | (none) | Brief on one company by name. |
| `cloudradialCompanyId` | (none) | Brief on one company by CloudRadial companyId. |
| `warrantyWindowDays` | `90` | Days ahead that count a warranty as "expiring soon". |

Example: `{"companyName": "Contoso Ltd"}`

## Read-only

The goal tells the agent never to create, update or delete anything, and the Agent node keeps `autoApprove: false`, so any write it tried would wait in the Inbox for approval.

The briefing comes back as the agent's `answer`. To send it somewhere, add a [Deliver Result](https://github.com/cloudradial/Automations/tree/main/deliver-result) Agent node after it, the way [Weekly Fleet Audit](https://github.com/cloudradial/Automations/tree/main/weekly-fleet-audit) does.
