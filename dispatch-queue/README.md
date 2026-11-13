# Dispatch Queue: Every Technician's Next Best Ticket

A standing assistant for your service desk. Every half hour on weekdays it looks at the tickets nobody has picked up, ranks them by how urgent they really are, tells each technician which ticket to take next, and proposes who should own each one. You approve or deny each assignment, and it learns from what you deny.

## What your team sees

- **A short list after each check-in:** "Next best ticket per technician", one line each, with the ticket number, summary and score. Post it to a Teams channel if you like.
- **Proposed assignments in AutomationAI:** for example "Assign #48213 Outlook won't open to Alex Kim. Score 130: past SLA, priority 1, Contoso is a VIP; Alex has 3 open tickets and the Microsoft 365 skill." Approve or deny each one.
- **Optionally, a short internal note** on each assigned ticket saying why it was picked.

## What happens behind the scenes

- It reads only unassigned open service tickets from the last 14 days, at most 30 per check-in.
- It ranks them by fixed rules: SLA due time first, then priority, VIP clients and how long they've waited.
- It matches each ticket to the technician with the right skill and the fewest open tickets, never past a load cap, and never more than 2 new tickets per person per check-in.
- Nothing changes until someone approves it. It never reassigns a ticket that already has an owner, and never proposes something that's already waiting for approval.
- When you deny an assignment, it writes that down as a rule and doesn't propose it again.

## Works with

ConnectWise PSA, Autotask and HaloPSA, each with its own version of the agent.

- **Autotask:** the role used for an assignment is the technician's own role for that queue. If your Autotask requires a work type on every ticket change, it asks you which one to use.
- **Kaseya BMS, Syncro and Zendesk** aren't supported yet.

## What you need

- AutomationAI with Pulsars, and a runner with an AI provider
- Your PSA's extension from the catalog (ConnectWise PSA, Autotask or HaloPSA), installed and working on that runner
- Three short documents you fill in: your dispatch rules, your dispatch team and your VIP clients

## Set it up

**1. Add the agent and your documents.**

1. Download the agent for your PSA from the [technical details](https://github.com/cloudradial/Automations/tree/main/dispatch-queue#technical-details) and upload it on **Agents > Custom**.
2. Fill in the three templates (**Dispatch Rules**, **Dispatch Team** and **VIP Clients**) with your own boards, people and clients.
3. In **Knowledge**, create a folder called **Dispatch Queue** and upload the three documents to it.

**2. Create the Pulsar.** Go to **Pulsars > New Pulsar** and answer the five questions:

1. **Who's doing the work?**
   - **Agent:** Dispatch Queue (ConnectWise), Dispatch Queue (Autotask) or Dispatch Queue (Halo), to match your PSA.
   - **Runner:** the runner where your PSA extension works.
   - **Name:** Dispatch Queue
2. **What's the goal?** `Every unassigned service ticket has the right technician proposed, and each technician knows their next best ticket.`
   - **How will we know it's done?** Leave it blank. This Pulsar keeps running.
3. **When should it check in?** **On a schedule**, **Custom**: every 30 minutes, Monday to Friday, during your service desk hours. If your plan doesn't offer custom times, choose **Every hour on weekdays**.
4. **How much can it do on its own?** **Propose changes** (the default). Every assignment waits for you.
5. **Where does it keep notes?** **An existing Knowledge folder:** **Dispatch Queue**, the folder with your three documents. It reads them, and its own notes, at every check-in.

**3. Limits and who hears from it.**

- **Limits:** start with a per-check-in limit of about 60,000 tokens and a monthly limit to match (roughly 22 working days of check-ins). Leave the finish rules off.
- **Who should hear from it?** You, plus every Admin and Owner, by default. Turn on **Also post to Teams channels** and pick your dispatch channel to post the next-best list there.

**4. Test it.** Click **Save draft**, then **Try a check-in now**. Check that the next-best list names your technicians, and that each proposed assignment makes sense. Deny one to see it learn. Then click **Start**.

**On demand:** each agent also comes with a small workflow (**Dispatch Queue (ConnectWise)**, and so on) that runs one check-in when you click **Run**, with the same approvals.

## Need more detail?

See the [technical details](https://github.com/cloudradial/Automations/tree/main/dispatch-queue#technical-details) for the ranking rules, what it reads in each PSA, and how to build and test it.

---

## Technical details

**Marketplace ID:** Not listed yet | **Type:** Pulsar (custom agent per PSA, plus a goal workflow) | **Version:** 1.0.0

## Files

| What | Link |
|---|---|
| Agent, ConnectWise PSA | [`dispatch-queue-connectwise.agent.yml`](https://github.com/cloudradial/Automations/blob/main/dispatch-queue/dispatch-queue-connectwise.agent.yml) |
| Agent, Autotask | [`dispatch-queue-autotask.agent.yml`](https://github.com/cloudradial/Automations/blob/main/dispatch-queue/dispatch-queue-autotask.agent.yml) |
| Agent, HaloPSA | [`dispatch-queue-halo.agent.yml`](https://github.com/cloudradial/Automations/blob/main/dispatch-queue/dispatch-queue-halo.agent.yml) |
| Goal workflow, ConnectWise PSA | [`dispatch-queue-connectwise.yml`](https://github.com/cloudradial/Automations/blob/main/dispatch-queue/dispatch-queue-connectwise.yml) |
| Goal workflow, Autotask | [`dispatch-queue-autotask.yml`](https://github.com/cloudradial/Automations/blob/main/dispatch-queue/dispatch-queue-autotask.yml) |
| Goal workflow, HaloPSA | [`dispatch-queue-halo.yml`](https://github.com/cloudradial/Automations/blob/main/dispatch-queue/dispatch-queue-halo.yml) |
| Knowledge templates | [knowledge/](https://github.com/cloudradial/Automations/tree/main/dispatch-queue/knowledge) |
| Build source and tests | [src/](https://github.com/cloudradial/Automations/tree/main/dispatch-queue/src) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/dispatch-queue) |

## How it works

A Pulsar check-in **looks** (read tools run for real), **proposes** (every write becomes a proposal with its tool, arguments and reason), and then **acts** only on what was approved. This agent is written for that loop.

| Step | What the agent does |
|---|---|
| **Read** | Two turns of parallel reads: the unassigned open tickets (14 days, at most 30, oldest first), the technicians, then the open-ticket load of the matched technicians. It never reads ticket notes. |
| **Rank** | Fixed scores: SLA past due 100, due within 1 hour 80, 4 hours 50, 24 hours 20; priority 60, 40, 20 or 0 (or the Dispatch Rules table); VIP client 30; 1 point per hour waiting, at most 30. Ties go to the older ticket. |
| **Match** | Down the ranked list: a dispatch-team technician under the load cap (default 12 open) with fewer than 2 proposals this check-in, preferring a skill match on the ticket summary, board or queue, then the fewest open tickets, then the order in the Dispatch Team document. |
| **Propose** | One assignment per ticket, at most 8, each with a one-line reason. Optionally one internal note per ticket. Skips owned tickets, pending proposals and pairings a person denied. |
| **Note** | Writes a short note to the Pulsar's folder: counts, proposals, each technician's next best ticket, denials turned into rules, and any default it used. |

**Budget:** about 12 tool calls a check-in, never more than 18, so it stays well inside the runner's 25-turn limit.

**Without a Dispatch Team document** (or when no name matches), it proposes nothing, reports the top 5 tickets and asks who dispatches. The answer becomes something it has learned.

### What it reads and writes in each PSA

| | ConnectWise PSA (`connectwise-manage`) | Autotask (`autotask-psa`) | HaloPSA (`halo-psa`) |
|---|---|---|---|
| Unassigned tickets | `cw_query_tickets`: `closedFlag = false AND owner/id = null`, entered in the last 14 days; skips tickets with resources | `at_query_tickets`: status not Complete, `assignedResourceID` not set, created in the last 14 days | `halo_query_tickets`: `open_only`, `agentId` 0, last 14 days; keeps `agent_id` 0 or empty |
| Technicians | `cw_query_members` (active) | `at_query_resources` (active), `at_query_resource_roles` | `halo_query_agents` |
| Load | `cw_query_tickets` open, `owner/identifier in (...)` | `at_query_tickets` open, `assignedResourceID in (...)` | `halo_query_tickets` open, 200 rows, counted by `agent_id` |
| Labels | priority name on the ticket | `at_get_ticket_field_values` | `halo_query_priorities` |
| Due time | `requiredDate`, else `slaStatus` | `dueDateTime` | `fixbydate`, else `deadlinedate` |
| Assign (proposal) | `cw_update_ticket` `ownerId` | `at_update_ticket` `assignedResourceID` + `assignedResourceRoleID` | `halo_update_ticket` `agentId` + `forceReassign` |
| Why-note (proposal, off by default) | `cw_create_ticket_note`, internal analysis | `at_create_ticket_note`, an "Internal" publish value | `halo_add_action`, `isPrivate`, private note outcome |

### Agent settings

- `model` is blank, so it uses the runner's provider. The prompt tells it to write one sentence before each tool call, so Anthropic never gets an empty message.
- `requiredExtensionSlugs` is only that PSA's extension. `dryRunDefault` is true.
- The goal workflow's agent node has `autoApprove: false` and `allowedExtensions` set to that one extension. Its webhook ships off.
- Ticket text is treated as data: the prompt tells it never to follow instructions in a ticket.

### Not yet proven live

The Pulsar setup, the Halo `agentId` 0 filter for unassigned tickets, and whether documents uploaded to the notes folder are read at every check-in (the support article says recent notes are) haven't been tested in a tenant yet. If the documents aren't read, the agent asks who dispatches, and the answer is kept as something it has learned.

## Build and test

Edit `src/prompt.md` (shared prompt), the PSA sections in `src/build.js`, or `src/tools-snapshot.json` (the tool names the agent relies on, from the catalog extensions on 2026-11-13). Never edit the generated `.yml` files.

```
node dispatch-queue/src/build.js
node dispatch-queue/src/test.js
```

`test.js` checks that every file parses (and every embedded JSON string), the markers, slugs and version, a blank model, the empty-message sentence, that every tool the prompt names exists in that PSA's snapshot and every write it names is an allowed proposal, `autoApprove: false`, the webhook off, no dashes, the README setup questions, and that the generated files are current.
