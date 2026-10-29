# Send Automation Results Wherever Your Team Works

Lets any automation finish by opening a ticket in your PSA, sending an email or handing the result back to ServiceAI, without rebuilding that step each time.

**Formerly:** Deliver Result | **Marketplace ID:** AAI-00039 | **Type:** Agent | **Version:** 1.2.1

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/deliver-result/v1.2.1).

**Import** [`deliver-result.agent.yml`](https://github.com/cloudradial/Automations/blob/main/deliver-result/deliver-result.agent.yml) on **Agents → Custom → Import**. An agent only runs from a workflow that gives it a goal; these automations run this one:

- [Get a Weekly List of Warranty and Ownership Gaps](https://github.com/cloudradial/Automations/tree/main/weekly-fleet-audit)

| What | Link |
|---|---|
| View `deliver-result.agent.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/deliver-result/deliver-result.agent.yml) |
| Download `deliver-result.agent.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/deliver-result/v1.2.1) |
| Used by | [Get a Weekly List of Warranty and Ownership Gaps](https://github.com/cloudradial/Automations/tree/main/weekly-fleet-audit) |
| All files in this automation | [deliver-result](https://github.com/cloudradial/Automations/tree/main/deliver-result) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/deliver-result) |

## How it works

A reusable **agent** that other automations call as their last step, so they don't hardcode one PSA or one delivery method. Give it a result and a `channel`, and it delivers it:

| Channel | What happens |
|---|---|
| `psa` | Creates a ticket in whichever PSA extension the calling node allows (ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro or Zendesk), with an internal note. |
| `email` | Sends through the **Postmark** extension. |
| `serviceai` | Creates nothing, returns the ServiceAI contract (`status`, `public_note`, `internal_note`, `ticket_id`) for the calling Triage Action to post. |

## Pieces

| File | Type | Role |
|---|---|---|
| [`deliver-result.agent.yml`](https://github.com/cloudradial/Automations/blob/main/deliver-result/deliver-result.agent.yml) | `automationsAgent` | Slug `deliver-result`, v0.3.1. Requires only `postmark`; the PSA extension comes from the calling node. Keeps secrets and technical detail out of client-visible fields. Dry-run by default. |

## Install / run

1. Upload `deliver-result.agent.yml` on **Agents → Custom** (keyed on the slug).
2. Install and connect the extensions you'll deliver through: **Postmark** (catalog `postmark` 1.0.0, secrets `Postmark-ServerToken`, `Postmark-FromEmail`, `Postmark-ApiUrl`) and your PSA (`connectwise-manage`, `autotask-psa`, `halo-psa`, `kaseya-bms`, `syncro` or `zendesk-ticketing`). The agent doesn't require a PSA extension to install.
3. Nothing to set on the agent itself: AutomationAI has no screen for agent variables, and in testing a variable's value didn't reach the agent. The calling node passes the setup as inputs instead (step 4). The variables of the same name stay in the file as a fallback.
4. In the calling workflow, add an **Agent** node with `agentSlug: deliver-result` and set its `allowedExtensions` to the partner's PSA and/or `postmark`. In its input bindings pass `channel`, `subject`, `body`, the routing (`companyId` / `companyIdentifier` / `companyName` for PSA, `toEmail` for email), and the setup:
   - `defaultBoard`: the board / queue / group for new tickets. Required on ConnectWise PSA, Autotask and Kaseya BMS, where the agent fails rather than guess a board.
   - `priorityMap`: see below.
   - `noteTypeId`: Kaseya BMS only, the tenant's note type id for internal notes. Without it the ticket is created and the note is skipped with a message.
   - `fromEmail` (a verified Postmark sender; empty uses `Postmark-FromEmail`) and `messageStream` (default `outbound`) for email.

## Confirm in your tenant

- `requiredExtensionSlugs` lists only `postmark`. Up to 0.1.2 it also required `connectwise-manage`, so partners on another PSA had to edit the file before importing. Now the PSA comes from the calling node's `allowedExtensions`; if that has no PSA extension, a `psa` delivery fails and says so.
- **Kaseya BMS** uses the catalog `kaseya-bms` extension (1.1.0, made executable on 2026-10-28; before that it was a starter with no working tools). Ticket ids for account, queue, priority and status are resolved with `kaseya_bms_list_accounts` and `kaseya_bms_lookup`. Not yet proven by a live run.
- **Priority** is set the same way on every run. The `priority` input becomes one level (low; medium, also normal or empty; high; critical, also urgent or emergency). The level is looked up in `priorityMap`, a JSON object of level to PSA priority name or id, for example `{"low":"Priority 4 - Low","medium":"Priority 3 - Normal","high":"Priority 2 - High","critical":"Priority 1 - Critical"}`. Without a map, the agent uses the one PSA priority whose name contains the level word; if there isn't exactly one, it sets no priority, so the PSA's default applies. Up to 0.2.0 the agent chose a priority itself, and the same input could land on different priorities from run to run.
- The catalog **Postmark** extension (1.0.0) is the one to use; there's no need for a custom Postmark extension.
- The agent runs **dry-run by default**, see [Dry run and going live](#dry-run-and-going-live).

## Dry run and going live

`deliver-result.agent.yml` ships with `dryRunDefault: true`. In dry run the agent describes the ticket or email it *would* send, but sends nothing. A setup problem still fails in dry run: a missing `defaultBoard`, a PSA that isn't available, or a `priorityMap` value the PSA doesn't have returns `status: failed` with the reason, so a preview run shows what would break when you go live. AutomationAI has **no dry-run switch** on the workflow's Agent node, the deployment, or the agent's page. The setting lives only in the agent file, so going live means re-importing it:

1. Open `deliver-result.agent.yml` and change `dryRunDefault: true` to `dryRunDefault: false`.
2. On **Agents → Custom → Import**, upload the edited file. It replaces the installed agent in place.
3. Run once and confirm it's live: the output should carry a real `ticketId` or `emailMessageId`.
4. To go back to preview, set it to `true` and re-import.

The change applies to **every** workflow that calls this agent. Keep the repo copy on `true`, so a fresh install always starts in preview.
