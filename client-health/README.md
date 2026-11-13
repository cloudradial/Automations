# Spot Unhappy Clients Before They Leave

Every week, each client gets a health score from 0 to 100, built from their satisfaction ratings, ticket trend, SLA results and old open tickets. When a client slips, the client's account manager gets a follow-up to approve, with the reasons spelled out.

## What your clients see

Nothing. Client Health only reads your PSA and your CloudRadial feedback. The follow-ups it proposes are for your own team.

## What happens behind the scenes

- **Once a week, every active client is scored.** Satisfaction ratings from the last 90 days count most. Then come SLA results, whether ticket volume is climbing, and tickets left open for more than two weeks.
- **It remembers last week.** Each score is kept in the Pulsar's notes, so it can tell you who dropped, who improved and by how much.
- **A slipping client gets one follow-up.** A drop of 15 points or more, or a score below 60, proposes a follow-up for that client's account manager: an activity in ConnectWise PSA, or an internal ticket in Autotask or HaloPSA.
- **You approve every follow-up.** Nothing is written to your PSA until someone approves it. At most 10 follow-ups a week, worst first, and never twice for the same client within two weeks.
- **A weekly summary** lists the five lowest scores, the biggest drops and the biggest gains.

## What it protects

- **It never closes, reassigns or deletes anything.** Its only writes are the follow-ups you approve.
- **No client comments or personal details** go into the follow-ups or the notes, only scores and counts.
- **It doesn't guess.** A part of the score with too little data is left out, and if an account manager or queue can't be found, it asks you instead of picking one.

## Works with

ConnectWise PSA, Autotask and HaloPSA, with CloudRadial feedback for the satisfaction ratings.

- **ConnectWise PSA:** the SLA part uses ConnectWise's own "in SLA" result, which counts business hours.
- **Autotask:** the SLA part uses Autotask's "SLA met" result.
- **HaloPSA:** the SLA part compares the close date with the fix-by date.
- **Large MSPs:** each check-in reads tickets in bulk. If your PSA returns more tickets than one read allows, that week's volume and SLA parts are skipped and the summary says so. Use a watch list to score fewer clients.

## What you need

- AutomationAI with Pulsars turned on, and a runner connected to your PSA
- The extension for your PSA (ConnectWise PSA, Autotask or HaloPSA) and the CloudRadial feedback extension, installed with their settings filled in
- A list of your clients' account managers

## Set it up

**1. Add the agent.** Download the agent for your PSA from the [release](https://github.com/cloudradial/Automations/releases/tag/client-health/v1.0.0): **Client Health (ConnectWise PSA)**, **Client Health (Autotask)** or **Client Health (HaloPSA)**. Go to **Agents > Custom** and upload it.

**2. Add your rules.** Go to **Knowledge**, create a folder called **Client Health**, and add the two example documents from the [knowledge folder](https://github.com/cloudradial/Automations/tree/main/client-health/knowledge). Edit **Client Health Account Managers** with your own clients and account managers, and where follow-ups should go. **Client Health Scoring** is optional: leave it out to use the built-in scoring.

**3. Create the Pulsar.** Go to **Pulsars > New Pulsar** and answer the five questions:

1. **Who's doing the work?**
   - **Agent:** Client Health (your PSA)
   - **Runner:** the runner connected to your PSA and CloudRadial
   - **Name:** Client Health
2. **What's the goal?**
   `Keep every client's health score at 60 or above, and follow up with the account manager whenever a client drops 15 or more points.`
   Leave **How will we know it's done?** empty, because this one keeps going.
3. **When should it check in?** **On a schedule**, **Every week**. Monday morning works well, so account managers start the week with it.
4. **How much can it do on its own?** **Propose changes**. Every follow-up waits for your approval.
5. **Where does it keep notes?** **An existing Knowledge folder**: choose **Client Health**, the folder from step 2. Its scores and your rules then live in one place.

**Limits.** Start with the default token limits. After the first check-in, look at how much it used and set the per-check-in limit a little above that. Leave the finish rules off.

**Who should hear from it?** The defaults (you, plus every Admin and Owner). To share the weekly summary with account managers, turn on **Also post to Teams channels** and pick their channel.

**4. Try it.** Click **Try a check-in now** on the draft. The first check-in is the baseline: there's no last week to compare with, so only clients below 60 get a follow-up. Check a few scores against your PSA and your feedback, then click **Start**.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/client-health#technical-details) cover the scoring rules, which tools each agent reads and proposes, the notes format, and how to test it by hand.

---

## Technical details

**Marketplace ID:** Not listed yet | **Type:** Pulsar (custom agent per PSA, plus a goal workflow to run it by hand) | **Version:** 1.0.0

## Files

Each version is published as a release with every `.yml` attached. Download them from the [**release**](https://github.com/cloudradial/Automations/releases/tag/client-health/v1.0.0).

| What | ConnectWise PSA | Autotask | HaloPSA |
|---|---|---|---|
| Agent (Agents > Custom) | [`client-health-connectwise.agent.yml`](https://github.com/cloudradial/Automations/blob/main/client-health/client-health-connectwise.agent.yml) | [`client-health-autotask.agent.yml`](https://github.com/cloudradial/Automations/blob/main/client-health/client-health-autotask.agent.yml) | [`client-health-halo.agent.yml`](https://github.com/cloudradial/Automations/blob/main/client-health/client-health-halo.agent.yml) |
| Goal workflow (Workflows > Import) | [`client-health-connectwise.yml`](https://github.com/cloudradial/Automations/blob/main/client-health/client-health-connectwise.yml) | [`client-health-autotask.yml`](https://github.com/cloudradial/Automations/blob/main/client-health/client-health-autotask.yml) | [`client-health-halo.yml`](https://github.com/cloudradial/Automations/blob/main/client-health/client-health-halo.yml) |

| Also | Link |
|---|---|
| Knowledge templates | [knowledge/](https://github.com/cloudradial/Automations/tree/main/client-health/knowledge) |
| Build source and tests | [src/](https://github.com/cloudradial/Automations/tree/main/client-health/src) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/client-health) |

## How it works

A Pulsar check-in looks (read tools run for real), proposes (every write becomes a proposal with its tool, arguments and reason), and acts only on what you approve. This agent:

1. Reads its notes (last week's `SCORE` lines and its `PROPOSED` lines) and the two Knowledge documents.
2. Reads, in one parallel batch:
   - CloudRadial feedback for the last 90 days: `cr_list_feedback` with a `dateCreated` filter and a narrow `$select`. Feedback is matched to a PSA client by `companyPsaId`, then by exact name.
   - PSA tickets created in the last 60 days, and open tickets older than 14 days, with only the fields it needs.
3. Scores each client (rules below), then proposes at most 10 follow-ups.
4. Writes one `SCORE` line per client and one `PROPOSED` line per follow-up to its notes, and ends with a summary.

It plans for about 15 tool calls per check-in, well under the runner's 25-turn limit, and never reads clients one by one.

### Scoring (defaults; the "Client Health Scoring" document overrides them)

| Part | Weight | Rule |
|---|---|---|
| CSAT, 90 days | 40 | Positive 100, Neutral 50, Negative 0, averaged. Needs 3 or more responses. |
| Volume trend | 20 | Last 30 days (A) vs the 30 before (B). A/B up to 1.1 is 100, 1.5 is 70, 2.0 is 40, above is 10. Both under 5 is 100. |
| SLA | 25 | Percentage met, of tickets created in the last 30 days with an SLA result. Needs 3 or more. |
| Aged open | 15 | Open tickets older than 14 days: 0 is 100, 1 to 2 is 70, 3 to 5 is 40, more is 10. |

Parts without enough data are left out and the weights are rescaled. Clients with no tickets and no feedback in 60 days aren't scored. Without a watch list, at most the 40 busiest clients are scored.

A follow-up is proposed for a drop of 15 or more points since the last `SCORE` line, or a score below 60, skipping clients with a pending proposal or one in the last 14 days.

### What each PSA reads and proposes

| PSA | Reads | Proposes | SLA signal |
|---|---|---|---|
| ConnectWise PSA (`connectwise-manage`) | `cw_query_tickets` (fields `id,company/id,company/name,dateEntered,closedFlag,isInSla`), `cw_query_activity_types`, `cw_query_members` | `cw_create_activity` (falls back to a flagged `cw_create_company_note` if the activity type is missing) | `isInSla` on closed tickets |
| Autotask (`autotask-psa`) | `at_query_tickets` (`IncludeFields`), `at_query_companies`, `at_get_ticket_field_values`, `at_query_resources`, `at_query_resource_roles` | `at_create_ticket` against the client, in the queue Knowledge names | `serviceLevelAgreementHasBeenMet` |
| HaloPSA (`halo-psa`) | `halo_query_tickets` (`pageinate`, `page_size` 500), `halo_query_agents`, `halo_query_clients`, `halo_query_ticket_types` | `halo_create_ticket` for the internal client Knowledge names | closed date vs `fixbydate` |

ConnectWise ticket reads return at most 300 rows: the agent splits the 60 days into two windows, and if a window is still capped it skips the volume and SLA parts and writes a `NOTE` line. HaloPSA does the same when `record_count` is more than the rows returned. Reopen counts aren't used, because none of the three PSAs exposes them in a bulk ticket read.

### Notes format

```
SCORE | 2026-11-16 | 19300 | Contoso Ltd | 58 | csat 62 (2 neg) | volume 14/8 | sla 80 | aged 3
PROPOSED | 2026-11-16 | 19300 | Contoso Ltd | 58 | Alex Wilber
NOTE | 2026-11-16 | ticket query hit 300 rows; volume trend not scored
```

### Agents

- `model: ""` (the tenant's own model), `dryRunDefault: true`.
- `requiredExtensionSlugs`: the PSA's extension plus `cloudradial-v2-feedback`.
- Every message carries a sentence before each tool call (AAI-96).

### Run it by hand (goal workflow)

Import the goal workflow for your PSA, then **Publish** and **Deploy**. It reads an optional run input, `{"clients":"Contoso Ltd, Fabrikam Inc"}`, to score only those clients, and hands the check-in to the agent with `autoApprove: false`, so every follow-up still waits for approval. Ground the agent node on the **Client Health** Knowledge folder. Outside a Pulsar there are no notes, so the `SCORE` lines come back at the end of the summary.

## Build and test

Edit `src/prompt.md` or `src/build.js`, never the generated `.yml` files.

```bash
node client-health/src/build.js
node client-health/src/test.js
```

`test.js` checks that every file parses and is current, the markers, slugs and versions, a blank `model`, the AAI-96 sentence, no dashes, that every tool named in each prompt is in that PSA's extension (`src/tools-snapshot.json`, read from a tenant on 2026-11-13), that no other PSA's tools are named, and that every write tool named is an allowed proposal. It also runs the goal workflow's PowerShell step through `src/test-step.ps1` in strict mode, in a child scope, with six run inputs (needs `pwsh`).

## Tested

- `node client-health/src/test.js`: 134 checks pass, including the six strict-mode step cases.
- Not yet run live. See the PR for the live test plan.
