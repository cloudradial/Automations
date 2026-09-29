# Deliver Result

A reusable **agent** that other automations call as their last step, so they don't hardcode one PSA or one delivery method. Give it a result and a `channel`, and it delivers it:

| Channel | What happens |
|---|---|
| `psa` | Creates a ticket in whichever PSA extension the calling node allows (ConnectWise, Autotask, Syncro, HaloPSA or Zendesk), with an internal note. |
| `email` | Sends through the **Postmark** extension. |
| `serviceai` | Creates nothing — returns the ServiceAI contract (`status`, `public_note`, `internal_note`, `ticket_id`) for the calling Triage Action to post. |

## Pieces

| File | Type | Role |
|---|---|---|
| [`deliver-result.agent.yml`](deliver-result.agent.yml) | `automationsAgent` | Slug `deliver-result`, v0.1.0. Keeps secrets and technical detail out of client-visible fields. Dry-run by default. |

## Install / run

1. Upload `deliver-result.agent.yml` on **Agents → Custom** (keyed on the slug).
2. Install and connect the extensions you'll deliver through: **Postmark** (catalog `postmark` 1.0.0 — secrets `Postmark-ServerToken`, `Postmark-FromEmail`, `Postmark-ApiUrl`) and your PSA (`connectwise-manage`, `autotask-psa`, `halo-psa`, `syncro` or `zendesk-ticketing`).
3. Set the agent variables: `fromEmail` (a verified Postmark sender — leave empty to use `Postmark-FromEmail`), `defaultBoard` (board / queue / group for new tickets), `messageStream` (default `outbound`).
4. In the calling workflow, add an **Agent** node with `agentSlug: deliver-result`, set its `allowedExtensions` to the partner's PSA and/or `postmark`, and pass `channel`, `subject`, `body`, plus routing (`companyId` / `companyIdentifier` / `companyName` for PSA, `toEmail` for email).

## Confirm in your tenant

- `requiredExtensionSlugs` lists `postmark` and `connectwise-manage`. If the partner uses a different PSA, change the PSA slug in the agent file before importing — the agent uses whichever PSA extension the run allows.
- The catalog **Postmark** extension (1.0.0) is the one to use; there's no need for a custom Postmark extension.
- The agent runs **dry-run by default** — see [Dry run and going live](#dry-run-and-going-live).

## Dry run and going live

`deliver-result.agent.yml` ships with `dryRunDefault: true`. In dry run the agent describes the ticket or email it *would* send, but sends nothing. AutomationAI has **no dry-run switch** on the workflow's Agent node, the deployment, or the agent's page. The setting lives only in the agent file, so going live means re-importing it:

1. Open `deliver-result.agent.yml` and change `dryRunDefault: true` to `dryRunDefault: false`.
2. On **Agents → Custom → Import**, upload the edited file. It replaces the installed agent in place.
3. Run once and confirm it's live: the output should carry a real `ticketId` or `emailMessageId`.
4. To go back to preview, set it to `true` and re-import.

The change applies to **every** workflow that calls this agent. Keep the repo copy on `true`, so a fresh install always starts in preview.
