# Recurring Issue Finder

Every week, finds the problems that keep coming back for each client and proposes a problem ticket, with a knowledge base draft, for the top three. Your team approves each one before anything is created.

## What your clients see in the portal

**Nothing changes for them.** Over time they see fewer repeat tickets, because the cause gets fixed instead of the same symptom over and over.

## What happens behind the scenes

- **Once a week, an AI agent reads each client's last 30 days of tickets** and groups the ones about the same problem, for example five "Outlook keeps asking for my password" tickets from one client.
- **It picks the three biggest groups** that have at least three tickets and aren't already being tracked.
- **For each one, it proposes a problem ticket** for that client, listing the tickets, what they have in common, what to check first and a draft knowledge base article.
- **Nothing is created until someone approves it.** Approve, deny or ask it a question from the Pulsar. It remembers what you denied and doesn't suggest it again for 30 days.
- **It never changes, merges or closes your existing tickets,** and a problem ticket only ever holds one client's tickets.

## Works with

ConnectWise PSA, Autotask and HaloPSA.

- **HaloPSA:** the knowledge base draft is also proposed as a Halo KB article, created hidden until someone reviews it.
- **ConnectWise PSA and Autotask:** the knowledge base draft goes at the end of the problem ticket, ready to copy into your KB.
- **Not yet proven in a live run.** Watch the first few check-ins.

## What you need

- AutomationAI with Pulsars, and your PSA's catalog extension (**ConnectWise Manage**, **Autotask PSA** or **HaloPSA**) connected on a runner
- Somewhere for problem tickets in your PSA: a board (ConnectWise), a queue and the Problem ticket type (Autotask), or a Problem ticket type (HaloPSA)

## Set it up

**1. Import the agent.** Download the [files](https://github.com/cloudradial/Automations/releases/tag/recurring-issue-finder/v1.0.0). On **Agents > Custom > Import**, upload the agent for your PSA, for example **Recurring Issue Finder (ConnectWise PSA)**.

**2. Add your rules.** Edit the two documents in the [knowledge folder](https://github.com/cloudradial/Automations/tree/main/recurring-issue-finder/knowledge) to match how your team works: **Recurring Issue Rules** (how far back, what counts as a repeat, clients to skip) and **Problem Ticket Standards** (where problem tickets go and how they're written). Keep the headings. On **Knowledge**, create a folder named **Recurring Issue Finder** and upload both. Without them, it uses the built-in defaults: 30 days, three tickets, the top three, and a board or queue with "Problem" in its name.

**3. Create the Pulsar.** Go to **Pulsars > New Pulsar** and answer the five questions:

1. **Who's doing the work?**
   - **Agent:** Recurring Issue Finder (your PSA)
   - **Runner:** the runner your PSA extension is connected on
   - **Name:** Recurring Issue Finder
2. **What's the goal?**
   ```
   Each week, find the issues that keep coming back in each client's last 30 days of tickets and propose a problem ticket with a KB draft for the top three that aren't already being tracked.
   ```
   Leave **How will we know it's done?** empty. It keeps watching.
3. **When should it check in?** **On a schedule**, **Every week**.
4. **How much can it do on its own?** **Propose changes** (the default). Every problem ticket waits for your approval.
5. **Where does it keep notes?** **An existing Knowledge folder**: **Recurring Issue Finder** from step 2. It reads its recent notes at every check-in, so it remembers what it already proposed.

**Also set:**
- **Limits:** keep the default monthly and per-check-in limits, and no finish rules. If it stops for going over the per-check-in limit, change the look-back in **Recurring Issue Rules** to 14 days.
- **Who should hear from it?** You, plus every Admin and Owner (the default). Optionally, **Also post to Teams channels** and pick your service desk channel.

**4. Test it.** Click **Save draft**, then **Try a check-in now**. You should see a note listing the repeat issues it found and up to three proposed problem tickets. Approve one to check it lands on the right board or queue, deny the others, then click **Start**.

**Run it by hand (optional).** On **Workflows > Import**, upload **Recurring Issue Finder (your PSA)** for a one-off check-in. Its problem tickets wait for approval in the Inbox.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/recurring-issue-finder#technical-details) cover how it reads tickets, what it writes and how it's built.

---

## Technical details

**Formerly:** none (new) | **Marketplace ID:** to be assigned | **Type:** Pulsar (setup guide) + Agent + Workflow | **Version:** 1.0.0

## Files

Each version is published as a release with all six `.yml` files attached. Download them from the [**release**](https://github.com/cloudradial/Automations/releases/tag/recurring-issue-finder/v1.0.0).

| What | Link |
|---|---|
| Agent, ConnectWise PSA | [`recurring-issue-finder-connectwise.agent.yml`](https://github.com/cloudradial/Automations/blob/main/recurring-issue-finder/recurring-issue-finder-connectwise.agent.yml) |
| Agent, Autotask | [`recurring-issue-finder-autotask.agent.yml`](https://github.com/cloudradial/Automations/blob/main/recurring-issue-finder/recurring-issue-finder-autotask.agent.yml) |
| Agent, HaloPSA | [`recurring-issue-finder-halo.agent.yml`](https://github.com/cloudradial/Automations/blob/main/recurring-issue-finder/recurring-issue-finder-halo.agent.yml) |
| Goal workflow, ConnectWise PSA | [`recurring-issue-finder-connectwise.yml`](https://github.com/cloudradial/Automations/blob/main/recurring-issue-finder/recurring-issue-finder-connectwise.yml) |
| Goal workflow, Autotask | [`recurring-issue-finder-autotask.yml`](https://github.com/cloudradial/Automations/blob/main/recurring-issue-finder/recurring-issue-finder-autotask.yml) |
| Goal workflow, HaloPSA | [`recurring-issue-finder-halo.yml`](https://github.com/cloudradial/Automations/blob/main/recurring-issue-finder/recurring-issue-finder-halo.yml) |
| Knowledge templates | [knowledge/](https://github.com/cloudradial/Automations/tree/main/recurring-issue-finder/knowledge) |
| Prompt, per-PSA steps, build script and tests | [src/](https://github.com/cloudradial/Automations/tree/main/recurring-issue-finder/src) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/recurring-issue-finder) |

## How it works

A Pulsar check-in **looks** (read tools run for real), **proposes** (every write becomes a proposal with its exact tool and arguments), then **acts** only on what's approved. The agent reads the PSA itself through the catalog extension, so there is one agent per PSA, each limited to that one extension.

Each check-in, in about 10 to 12 tool calls (the runner stops an agent at 25 turns):

1. **Reads its notes:** themes already proposed (client, ticket ids), the problem board or queue it resolved, and what people answered or denied.
2. **Resolves where problem tickets go,** unless its notes already hold it.
3. **Reads the tickets in one bulk query** with only the fields it needs, and the open problem tickets in a second one. At most 300 tickets; over that, it drops to 14 days and says so.
4. **Groups each client's tickets into themes** (shared type, subtype, category or item, plus shared key words in the summary), keeps themes of at least 3 tickets, drops any already pending, approved, denied in the last 30 days or covered by an open problem ticket, and ranks by size, then by the newest ticket.
5. **Confirms** a top theme by reading one member ticket only when the summaries aren't clear (at most 3 reads).
6. **Proposes** one problem ticket per top theme (3 by default, never more than 5). Each holds one client's tickets only.
7. **Writes a check-in note:** the window, tickets read, every theme found and why it was or wasn't proposed, and any question it asked.

| PSA | Extension | Reads | Proposes |
|---|---|---|---|
| ConnectWise PSA | `connectwise-manage` | `cw_query_boards`, `cw_query_tickets`, `cw_query_companies`, `cw_get_ticket` | `cw_create_ticket` on the problem board (KB draft in the description) |
| Autotask | `autotask-psa` | `at_get_ticket_field_values`, `at_query_tickets`, `at_get_company`, `at_get_ticket` | `at_create_ticket` with the Problem ticket type, in the problem queue (KB draft in the description) |
| HaloPSA | `halo-psa` | `halo_query_ticket_types`, `halo_query_tickets`, `halo_get_ticket` | `halo_create_ticket` with the Problem ticket type, and `halo_create_kb_article` (inactive) |

**It asks instead of guessing** when the rules name no problem board or queue and it finds none or several, or when it can't separate two clients' tickets. A question is asked once and remembered under **What it has learned**.

**Not in v1:** a note on each member ticket pointing to the problem ticket (too many writes per check-in), and linking the tickets to the problem natively.

## Agent settings

- `model: ""`, so the tenant's own provider is used.
- `dryRunDefault: true`. The goal workflow's agent node has `autoApprove: false`.
- `requiredExtensionSlugs` lists only that PSA's extension, and the workflow's `allowedExtensions` matches it.
- No secrets of its own: it uses the extension's connection on the runner.

## Goal workflow

`recurring-issue-finder-<psa>.yml` runs one check-in by hand: **Start**, then **Check-in settings** (PowerShell; reads the optional run input and today's date), then the agent node. The webhook ships off.

| Run input (optional) | Default | Range |
|---|---|---|
| `lookback_days` | 30 | 7 to 90 |
| `min_tickets` | 3 | 2 to 20 |
| `max_proposals` | 3 | 1 to 5 |

## Build and test

Never edit the `.yml` files by hand. Edit `src/prompt.md` (shared instructions), `src/psa.js` (per-PSA steps and tools) or `src/settings.ps1`, then:

```
node recurring-issue-finder/src/build.js
node recurring-issue-finder/src/test.js
```

`test.js` checks that all six files are current and parse, every embedded JSON string parses, the slugs, versions, blank model, AAI-96 sentence and approval settings are right, every tool the prompt names exists in that PSA's extension (`src/tools.json`, a snapshot of the catalog tool names) and the only writes are the ones above, there are no en or em dashes, and the README covers the five Pulsar questions. It also runs `src/test-settings.ps1`, the strict-mode harness for the settings step.

## Tested

- `node recurring-issue-finder/src/test.js`: all checks pass (see the PR).
- Not yet run live in a tenant.
