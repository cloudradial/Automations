# Send Automation Results Wherever Your Team Works

Lets any automation finish by opening a ticket in your PSA, sending an email or handing the result back to ServiceAI, without rebuilding that step each time.

**Formerly:** Deliver Result | **Marketplace ID:** AAI-00039 | **Type:** Agent | **Version:** 1.1.0

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/deliver-result/v1.1.0).

**Import** [`deliver-result.agent.yml`](https://github.com/cloudradial/Automations/blob/main/deliver-result/deliver-result.agent.yml) on **Agents → Custom → Import**. An agent only runs from a workflow that gives it a goal; these automations run this one:

- [Get a Weekly List of Warranty and Ownership Gaps](https://github.com/cloudradial/Automations/tree/main/weekly-fleet-audit)

| What | Link |
|---|---|
| View `deliver-result.agent.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/deliver-result/deliver-result.agent.yml) |
| Download `deliver-result.agent.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/deliver-result/v1.1.0) |
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
| [`deliver-result.agent.yml`](https://github.com/cloudradial/Automations/blob/main/deliver-result/deliver-result.agent.yml) | `automationsAgent` | Slug `deliver-result`, v0.2.0. Requires only `postmark`; the PSA extension comes from the calling node. Keeps secrets and technical detail out of client-visible fields. Dry-run by default. |

## Install / run

1. Upload `deliver-result.agent.yml` on **Agents → Custom** (keyed on the slug).
2. Install and connect the extensions you'll deliver through: **Postmark** (catalog `postmark` 1.0.0, secrets `Postmark-ServerToken`, `Postmark-FromEmail`, `Postmark-ApiUrl`) and your PSA (`connectwise-manage`, `autotask-psa`, `halo-psa`, `kaseya-bms`, `syncro` or `zendesk-ticketing`). The agent doesn't require a PSA extension to install.
3. Set the agent variables: `fromEmail` (a verified Postmark sender, leave empty to use `Postmark-FromEmail`), `defaultBoard` (board / queue / group for new tickets; required on ConnectWise PSA, Autotask and Kaseya BMS, where the agent fails rather than guess a board), `messageStream` (default `outbound`), and on Kaseya BMS `noteTypeId` (the tenant's note type id for internal notes; without it the ticket is created and the note is skipped with a message).
4. In the calling workflow, add an **Agent** node with `agentSlug: deliver-result`, set its `allowedExtensions` to the partner's PSA and/or `postmark`, and pass `channel`, `subject`, `body`, plus routing (`companyId` / `companyIdentifier` / `companyName` for PSA, `toEmail` for email).

## Confirm in your tenant

- `requiredExtensionSlugs` lists only `postmark`. Up to 0.1.2 it also required `connectwise-manage`, so partners on another PSA had to edit the file before importing. Now the PSA comes from the calling node's `allowedExtensions`; if that has no PSA extension, a `psa` delivery fails and says so.
- **Kaseya BMS** uses the catalog `kaseya-bms` extension (1.1.0, made executable on 2026-10-28; before that it was a starter with no working tools). Ticket ids for account, queue, priority and status are resolved with `kaseya_bms_list_accounts` and `kaseya_bms_lookup`. Not yet proven by a live run.
- The catalog **Postmark** extension (1.0.0) is the one to use; there's no need for a custom Postmark extension.
- The agent runs **dry-run by default**, see [Dry run and going live](#dry-run-and-going-live).

## Dry run and going live

`deliver-result.agent.yml` ships with `dryRunDefault: true`. In dry run the agent describes the ticket or email it *would* send, but sends nothing. AutomationAI has **no dry-run switch** on the workflow's Agent node, the deployment, or the agent's page. The setting lives only in the agent file, so going live means re-importing it:

1. Open `deliver-result.agent.yml` and change `dryRunDefault: true` to `dryRunDefault: false`.
2. On **Agents → Custom → Import**, upload the edited file. It replaces the installed agent in place.
3. Run once and confirm it's live: the output should carry a real `ticketId` or `emailMessageId`.
4. To go back to preview, set it to `true` and re-import.

The change applies to **every** workflow that calls this agent. Keep the repo copy on `true`, so a fresh install always starts in preview.
