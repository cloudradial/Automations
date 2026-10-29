# Safe Device Fixes and Patch Checks Through Your RMM

This is the shared AI agent behind two automations: one fixes common workstation alerts, the other reports each client's patch status. It works through Datto RMM, follows strict safety rules, and hands anything it can't handle to your team as a ticket.

## What happens

You don't run this agent on its own. You install it once, and these automations give it a job to do:

- **[Fix Common Workstation Alerts Without a Technician](https://github.com/cloudradial/Automations/tree/main/rmm-auto-remediation):** when Datto RMM raises an alert, the agent tries a safe fix (for example, a disk cleanup on a workstation that's low on space), checks it worked, and resolves the alert. You approve each fix first.
- **[Show Every Client's Patch Compliance in Their Planner](https://github.com/cloudradial/Automations/tree/main/patch-compliance):** on a schedule, the agent checks patch status and keeps one Planner card per client up to date, written in plain sentences your clients can read.

## What it protects

- **Starts in preview.** Out of the box it reads everything and shows you each change it would make, but changes nothing.
- **Servers are left alone.** It never runs a fix or resolves an alert on a server unless you allow it.
- **It never guesses.** If it's unsure, or a fix fails, it asks for a ticket instead.
- **It only matches a Datto site to a client when it's sure:** from your own list of matches, the client's Autotask company link, or an exact name match. Otherwise it skips the site and tells you.
- **One Planner card per client.** It updates the existing card rather than adding duplicates, and never deletes anything.
- **Technical detail stays internal.** It only goes in a ticket's internal note.

## Works with

- **RMM:** Datto RMM only. Another RMM needs changes to the agent.
- **PSA:** tickets can be opened in ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk. The agent doesn't open them itself: a step in the alert fix workflow does.

## What you need

- AutomationAI, with Datto RMM connected
- CloudRadial companies and services (for Planner cards) connected in AutomationAI
- No PSA connection on the agent itself

## Set it up

**Once, in AutomationAI:**

1. **Download** the [agent file](https://github.com/cloudradial/Automations/releases/tag/rmm-agent/v1.1.0).
2. Go to **Agents > Custom > Import** and upload it.
3. When you deploy it, fill in its settings:
   - Your Datto disk cleanup component
   - The minimum free disk space (5 GB unless you change it)
   - Whether fixes may run on servers (off unless you change it)
   - The Planner category for patch reports (Security unless you change it)
   - Any Datto sites you want matched to a specific client
4. Import the two automations above on **Workflows > Import**, then follow each one's setup.

**Going live.** The agent stays in preview until you change its preview setting in the agent file and import it again. This switches every automation that uses it at once. The [technical details](https://github.com/cloudradial/Automations/tree/main/rmm-agent#dry-run-and-going-live) show exactly how.

**Test it.** Run the patch compliance automation once and check its preview lists a Planner card for each of your clients.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/rmm-agent#technical-details) cover how the agent works, its settings, and how to go live.

---

## Technical details

**Formerly:** RMM Agent (Datto) + command workflows | **Marketplace ID:** AAI-00037 | **Type:** Agent | **Version:** 1.1.0

The shared engine behind the device fix and patch compliance automations. It works through Datto RMM, matches sites to clients, and never acts without approval.

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/rmm-agent/v1.1.0).

**Import** [`rmm-agent.agent.yml`](https://github.com/cloudradial/Automations/blob/main/rmm-agent/rmm-agent.agent.yml) on **Agents → Custom → Import**. An agent only runs from a workflow that gives it a goal; these automations run this one:

- [Show Every Client's Patch Compliance in Their Planner](https://github.com/cloudradial/Automations/tree/main/patch-compliance)
- [Fix Common Workstation Alerts Without a Technician](https://github.com/cloudradial/Automations/tree/main/rmm-auto-remediation)

| What | Link |
|---|---|
| View `rmm-agent.agent.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/rmm-agent/rmm-agent.agent.yml) |
| Download `rmm-agent.agent.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/rmm-agent/v1.1.0) |
| Used by | [Show Every Client's Patch Compliance in Their Planner](https://github.com/cloudradial/Automations/tree/main/patch-compliance) |
| Used by | [Fix Common Workstation Alerts Without a Technician](https://github.com/cloudradial/Automations/tree/main/rmm-auto-remediation) |
| All files in this automation | [rmm-agent](https://github.com/cloudradial/Automations/tree/main/rmm-agent) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/rmm-agent) |

## How it works

A reusable RMM operations **agent** that uses the partner's RMM extension to resolve
issues automatically, plus thin **workflows** that each run it with a goal for one
trigger: an RMM alert webhook, a ServiceAI Triage Action on a ticket, or a schedule.
Each workflow is a `type: agent` node with a `goal` + `agentSlug` (the same pattern as
[Portal Lookup](https://github.com/cloudradial/Automations/tree/main/portal-lookup)).

This build uses the **Datto RMM** extension (`datto-rmm`). To support another RMM, add
its extension slug to the agent's `requiredExtensionSlugs` and the workflow node's
`allowedExtensions`, and adjust the tool names in the system prompt.

**Tickets work with all six PSAs.** The agent has no PSA extension and never opens a
ticket itself. When something needs a person it returns `escalate: true` with
`ticketSummary`, `ticketDescription`, `ticketNote` (technical detail, internal only),
`ticketPriority`, `siteName` and `cloudradialCompanyId`, and the workflow's PowerShell step
opens the ticket in ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro or Zendesk
(`_shared/psa.ps1`). Up to agent 0.4.3 it needed the ConnectWise extension
(`connectwise-manage`); 0.5.0 dropped it.

## Pieces

| File | Type | Role |
|---|---|---|
| [`rmm-agent.agent.yml`](https://github.com/cloudradial/Automations/blob/main/rmm-agent/rmm-agent.agent.yml) | `automationsAgent` | The brain. Safety-first system prompt, knows the Datto tools, matches sites→CloudRadial companies, upserts Planner cards, and returns ticket text for escalations. Publish it → slug `rmm-agent`. |
| [`../rmm-auto-remediation/rmm-auto-remediation.yml`](https://github.com/cloudradial/Automations/blob/main/rmm-auto-remediation/rmm-auto-remediation.yml) | `automationsWorkflow` | **Command: remediate.** Webhook-triggered by a Datto alert; an agent node, `autoApprove: false` (you approve the fix), then a PowerShell step that opens any escalation ticket in your PSA. |
| [`../patch-compliance/patch-compliance.yml`](https://github.com/cloudradial/Automations/blob/main/patch-compliance/patch-compliance.yml) | `automationsWorkflow` | **Command: patch compliance.** Scheduled; one agent node that sweeps patch status and upserts one Planner card per client. |

The **Datto RMM extension already exists in AutomationAI** (`datto-rmm`, MSPTechPro), these reference it, they don't redefine it. Its tools auth via OAuth2 (handled by the
extension); secrets are `Datto-ApiUrl` / `Datto-ApiKey` / `Datto-ApiSecret`.

## Install / run

1. Upload `rmm-agent.agent.yml` on **Agents → Custom** (publishes slug `rmm-agent`).
2. Import both workflows on **Workflows → Import**.
3. Set the agent variables on deploy, `cleanupComponentUid` (the Datto cleanup
   component's UID, from its web-UI URL), `diskFreeThresholdGb`, `autoRemediateServers`.
4. **Patch compliance:** schedule the *Patch Compliance* workflow (Routine), e.g. weekly.
5. **Remediation:** after import, open the workflow's **Properties → Webhook** and toggle **Enable webhook** on (exports must ship with it OFF or the import breaks), then point your Datto alert webhook at the generated hook.

## Confirm in your tenant

- Extension slugs: `datto-rmm` (confirmed), `cloudradial-v2-companies` /
  `cloudradial-v2-services` (confirmed from the migration workflow). No PSA extension: tickets
  are opened by the remediation workflow's PowerShell step, with the runner's PSA secrets.
- The agent runs **dry-run by default**, see [Dry run and going live](#dry-run-and-going-live).
- Remediation keeps `autoApprove: false` so the cleanup job needs your approval; the
  escalation ticket is opened by the workflow's PowerShell step. Patch compliance uses `autoApprove: true` (card upserts only).

## Dry run and going live

`rmm-agent.agent.yml` ships with `dryRunDefault: true`. In dry run the agent does all its reads and shows you each write it *would* make, but changes nothing. AutomationAI has **no dry-run switch** on the workflow's Agent node, the deployment, or the agent's page. The setting lives only in the agent file, so going live means re-importing it:

1. Open `rmm-agent.agent.yml` and change `dryRunDefault: true` to `dryRunDefault: false`. Leave everything else the same.
2. On **Agents → Custom → Import**, upload the edited file. Import is keyed on the slug, so it replaces the installed agent in place. Workflows that use it pick up the change on their next run; nothing needs re-publishing.
3. Run once and confirm it's live: Patch Compliance should report `cardsWritten` of 1 or more and `cardsPreviewed: 0`. RMM Auto-Remediation stays approval-gated either way (`autoApprove: false`), so its live fixes still wait for you in the Inbox.
4. To go back to preview, set it to `true` and re-import.

The change applies to **every** workflow that uses this agent (Patch Compliance and RMM Auto-Remediation). Keep the repo copy on `true`, so a fresh install always starts in preview.
