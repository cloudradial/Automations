---
name: webhooks-audit
description: "Set up and troubleshoot CloudRadial webhook actions, and read the audit trail and sync logs. Use when the user says \"webhook\", \"create a webhook\", \"send catalog submissions to\", \"test the webhook\", \"webhook failed\", \"rotate the signing secret\", \"webhook runs\", \"audit log\", \"who changed\", \"what did the API change\", \"sign-in history\", \"sessions\", \"sync log\", \"did the PSA sync run\", \"ticket sync failed\", or needs to know what happened, when and by whom.\n"
metadata:
  version: "1.0.0"
---

# Webhooks & Audit

## Before any tool call

Call `setup_status` first. If it returns `configured: false`, defer to the `setup` skill.

## Webhook actions

A webhook action is an HTTP call CloudRadial makes to another system, for example when a catalog form
is submitted. Use `webhook_action`.

- **Read:** `action: "list"`, `"get"` (with `id`). Fields: `actionId`, `name`, `description`,
  `isEnabled`, `url`, `method`, `headers` (names only), `hasSigningSecret`, `lastRunStatus`,
  `lastRunUtc`. Header values and the signing secret are never returned.
- **Create:** `action: "create"` with `name`, `url` (https only), `method` (default POST),
  `description`, and optional headers.
  - **Header values are secrets** (for example an `Authorization` token). Don't ask the user to paste
    them into chat. Ask them to save a small JSON file on their computer, for example
    `{"Authorization": "Bearer ..."}`, and pass its path as `header_values_file` with the names in
    `header_names`.
  - The first call returns a preview. After the user's yes, call again with `confirmed: true`.
  - **The signing secret is shown only once.** The tool saves it to a private file on the user's
    computer and returns `signingSecretSavedTo`. Tell the user to copy it into the receiving system
    and then delete the file. Never read the file back into the chat.
- **Update:** `action: "update"` with the fields to change and `confirmed: true`. Headers you don't
  give new values for keep their stored values. A new header needs a value in the file.
- **Enable / disable / delete:** the same action names, each previewed and confirmed.
- **Rotate the secret:** `action: "rotate_secret"` (confirmed). The old secret stops working at once,
  so the receiving system must be updated; the new one is saved to a file the same way.
- **Test:** `action: "test"` sends one signed canned payload (example ticket, company and user values,
  shaped like a catalog submission) within 10 seconds, with no retry. Report the status code and body
  it returns.
- **Runs:** `action: "runs"` (paged), `"run_summary"`, `"run"` with `run_id` for one delivery. Use these
  to answer "why didn't the webhook fire".

### Troubleshooting a webhook

1. `get` the action: is it enabled, what was `lastRunStatus`?
2. `runs` for recent deliveries; open a failed one with `run`.
3. `test` it. A 401/403 from the receiver usually means a wrong header value or signing secret;
   a timeout means the endpoint didn't answer within 10 seconds.
4. Suggest the fix (update a header from a file, rotate the secret) and wait for confirmation.

## Audit log (read-only)

Use `audit_log`.

- `action: "events"`: changes, filtered by `company_id`, `entity` (for example `Company`,
  `ApplicationUser`, `CompanyPolicy`), `entity_id`, `identity` (a user id, a sign-in email, or the API
  key's user name for API changes), `source` (for example `PublicAPI`), `from` and `to` (ISO 8601),
  paged with `page` and `page_size`. `action: "event"` with `id` for one.
- `action: "sessions"`: sign-ins and API sessions with the same filters.
- `action: "sync_log"`: one run of a named sync job for a company, with its status, counts and log
  entries, as the portal's sync status shows it. For example `SyncTicketsForCompanyJob` (per company)
  or `SyncTicketsForPartnerJob` (partner-wide). Pass `job_name`, `company_id` and optional `status`.

### Common questions

- **"Who changed Contoso's settings yesterday?"** `events` with `company_id` and a `from`/`to` window;
  group by identity and entity.
- **"What has this plugin changed?"** `events` with `source: "PublicAPI"` (and the API key's user name
  as `identity` if the partner has several keys).
- **"Did the ticket sync run?"** `sync_log` with `SyncTicketsForCompanyJob` and the company.

Present events newest first with who, what, when and from where. Don't speculate about intent.
