---
name: client-communications
description: "Reach a partner's clients with Signal desktop notices, portal banners and portal messages. Use when the user says \"send a Signal message\", \"Signal notice\", \"push a notice to\", \"desktop notification\", \"remind [user] that\", \"password expires\", \"maintenance notice\", \"outage notice\", \"announce\", \"tell everyone at [company]\", \"portal banner\", \"add a banner\", \"post a portal message\", \"who read the notice\", \"who acknowledged\", \"retract that message\", \"resolve the notice\", or wants to get a message in front of client users through CloudRadial.\n"
metadata:
  version: "1.0.0"
---

# Client Communications

Put a message in front of client users through CloudRadial: on their desktop with **Signal**, across
portal pages with a **banner**, or in a company's portal message list with a **portal message**.
Every one of these is seen by real client users, so nothing is sent or published until the user has
seen exactly what goes out and to whom, and said yes.

## Before any tool call

Call `setup_status` first. If it returns `configured: false`, defer to the `setup` skill.

## Pick the channel

| Channel | Reaches | Best for | Tool |
|---|---|---|---|
| Signal message | Users' desktops (Signal client or browser extension), right away or scheduled | Time-sensitive notices, personal reminders, anything that needs a click or an acknowledgement | `signal_message` |
| Portal banner | Every portal page of the companies in the chosen company groups (sidebar or top of page), between a publish and expire date | Planned maintenance, a new service, a seasonal reminder | `create_resource` with `resource_type: "banner"` |
| Portal message | One company's portal message list, optionally highlighted or shown as an alert | Company news, policy changes, follow-ups that should stay on record | `create_resource` with `resource_type: "portal_message"` |

If the user doesn't say, suggest Signal for anything urgent or personal and a banner or portal
message for anything that should stay visible for days.

## Signal messages

### Who it reaches

- Target with `company_ids`, `group_ids` (company group ids), or `all_companies: true`.
- Narrow with `user_ids` (the `userId` GUIDs from `user_lookup`) and/or `role_ids`. Leave both out to
  reach everyone in the targeted companies.
- Every targeted user must belong to one of the targeted companies, or the send is refused.
- Never use `all_companies` unless the user explicitly asked for every client.

### Content rules

- `title` up to 200 characters, `body` up to 2,000. Lead with what the reader has to do.
- `priority`: 0 info (default), 1 important, 2 urgent. Important and urgent need `expires_at`.
- `expires_at` defaults to 14 days after sending and can be at most 90.
- A button: `deep_link_url` (absolute `https://` only) and `deep_link_label` (default "Open Link").
- `ack_required: true` asks the user to confirm the message, not just read it.
- `scheduled_send_at` sends later; the message starts as scheduled.
- Test sends aren't available through the API (the API key has no author to deliver to). To try a
  message, target the partner's own user in their own company first.

### Workflow

1. Resolve the company with `search_companies`, and each named person with `user_lookup` (use the
   `userId`).
2. Draft the message and call `signal_message` with `action: "send"` and **no** `confirmed`. This
   only returns the audience estimate (`users`, `companies`) and the exact message body. Nothing is
   sent.
3. Show the user: who it reaches (the estimate and the names you resolved), the title, body,
   button, priority, expiry, acknowledgement and any schedule. If the estimate says 0 users, fix
   the targeting before going on.
4. Only after an explicit yes, call `signal_message` again with the same arguments and
   `confirmed: true`. A dedupe key is added automatically, so a retry returns the existing
   message instead of sending a second one.
5. Report the message `id` and `version`. Both are needed to change it later.

### Follow up

- `action: "get"` with `id`: status plus `audienceCount`, `readCount`, `ackedCount` and
  `actedCount` (people who used the button).
- `action: "recipients"`: names and timestamps; `acked_only: true` for acknowledgements. Some
  companies report read receipts only as totals: the response then has `perUser: false` and a count
  in `suppressedCompanies`.
- `action: "edit"` changes an active message (fields you leave out are kept).
  `action: "resolve"` marks it handled. `action: "retract"` withdraws it and clears it from users'
  clients. All three use the version last read; a 409 means someone changed it since, so read it
  again and show the user the current state before retrying.
- `action: "list"` shows recent messages (newest first).

### Errors

- **404 "Signal is not enabled for this partner."** Signal isn't turned on for the account. Tell the
  user to contact CloudRadial; don't retry.
- **400 "Every targeted user must belong to one of the assigned companies"**: add the user's
  `companyId` to `company_ids`.
- **The message never appears**: the user needs the Signal client or browser extension installed
  and signed in.

## Portal banners

Banners belong to the partner account and are shown to companies by **company group**.

- Fields: `title` (required), `description`, `url`, `style` (1 green success, 2 amber warning,
  3 red alert, 4 blue info), `placement` (1 sidebar, 2 across the top), `showOnHome`,
  `showOnLogin`, `showOnReport`, `showOnRequest`, `publishDate`, `expireDate`, `companyGroups`,
  `roleIds`.
- `companyGroups` takes group **names**, not ids. Read them with `list_resources` on
  `company_group` (the name is in `group`). **An empty list means no company sees the banner** on
  home, report or request pages; only the login page ignores groups.
- `roleIds` (strings) limits it to certain portal roles; leave it out for everyone.
- Always set `expireDate` for anything temporary, so the banner takes itself down.

Workflow: list the company groups, draft the banner, show the user the title, text, colour, where it
appears, which groups see it and the dates, then create it after they confirm. Change it later with
`update_resource` (PATCH) and remove it with `delete_resource` after confirming.

## Portal messages

One company's message list in the portal.

- Required: `companyId`, `subject`, `category`, `author`, `body` (HTML allowed).
- `priority`: 0 normal, 10 important (highlighted), 20 critical (strongest highlight).
- `showAsAlert`, `includeInDigest`, `datePublished`, `tags`, `roleIds` are optional.
- `sendAsBroadcast` hasn't been tested through the plugin; leave it unset unless the user asks, and
  say it's untested.
- Attach files with `upload_file` (`target: "message_attachment"`, `message_id`, `company_id`,
  `file_paths`); remove one with `target: "remove_message_attachment"` and `attachment_id`.

Workflow: resolve the company, draft the message, show it with its priority and alert setting, and
create it after the user confirms. Delete with `delete_resource` (`company_id` is looked up).

## Message patterns

| Situation | Channel | Settings |
|---|---|---|
| Password about to expire | Signal to one user | priority 1, `expires_at` the expiry day, button to the reset page, `ack_required` |
| Planned maintenance | Banner for the affected groups, plus Signal the day before | banner style 2, top placement, expires after the window |
| Outage in progress | Signal to the affected companies | priority 2, short `expires_at`; `resolve` it when fixed |
| QBR or report ready | Signal to the client contacts | priority 0, button to the portal report |
| Policy change | Portal message | priority 10, `includeInDigest` |

## Report honestly

After sending or publishing, report exactly what went out, to how many people, and the id to use for
follow-ups. If a call failed, say which one and what the API answered; never say a message was sent
unless `signal_message` returned `sent: true`.
