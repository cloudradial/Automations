---
name: report-archive
description: "Upload report files into clients' CloudRadial report archives, set up archive folders, and check archive health. Use when the user says \"upload this report\", \"upload these PDFs\", \"put the backup report in the portal\", \"archive the QBR\", \"report archive\", \"archive folder\", \"set up a Backups folder for every client\", \"which clients haven't received a report\", \"overdue reports\", \"archive alerts\", \"which backup reports failed\", or wants report files (PDF, XLSX, DOCX, CSV, ZIP) stored where clients see them in their portal.\n"
metadata:
  version: "1.0.0"
---

# Report Archive

Every client company has **archive folders** (for example Nightly Backups, Patch Reports, Security
Audits), and each folder holds **archive items**: the reports. Most items arrive by email to the
folder's inbound address. This skill uploads report files directly, creates folders, and checks which
folders are overdue or alerting.

## Before any tool call

Call `setup_status` first. If it returns `configured: false`, defer to the `setup` skill.

## Folders

`list_resources` with `resource_type: "archive_folder"` and `filter: "companyId eq <id>"`. Key fields:
`companyReportFolderId` (the folder id; the same number is `archive_id` / `archiveId` elsewhere),
`companyId`, `name`, `category`, `inboundEmailAddress`, `dateLastReceived`, `warnOnPastDays`,
`retainForDays`, `alertKeywords`, `requiredKeywords`, `totalItemSize`.

| Setting | Meaning |
|---|---|
| `alertKeywords` | Comma-separated. A report containing any of them raises an alert. |
| `requiredKeywords` | Comma-separated. A report containing none of them raises an alert. |
| `warnOnPastDays` | The folder goes into error if no report arrives within this many days. 0 turns the check off. |
| `retainForDays` | How long items are kept. 0 keeps them indefinitely. |

- **Create** with `create_resource`, `resource_type: "archive_folder"`, `data: { companyId, name, category,
  alertKeywords, requiredKeywords, warnOnPastDays, retainForDays }`. `companyId` and `name` are
  required, and the name must be unique within the company. A new folder starts with the partner's
  default alert settings, which can include sending alerts to the PSA (`isSendToPsa`); say so when
  you create one.
- **Change** with `update_resource` (PATCH; no `company_id` needed).
- **Delete** with `delete_resource` after the user confirms. It hasn't been tested whether the
  folder's items go with it, so warn the user and suggest checking the items first.
- Partner default folders (`/v2/archivefolder/default`) aren't covered by a tool yet. Read them with
  `raw_api_call` (GET) if asked, and don't write to them without showing the user the exact call.

## Upload report files

Use `archive_upload`:

- `company_id`, `file_paths` (local files), and either `archive_id` or `folder_name`
  (matched case-insensitively). With `create_folder: true` a missing folder is created first, using
  `category`, `alert_keywords`, `required_keywords`, `warn_on_past_days`, `retain_for_days`.
- Optional `subject` (up to 255 characters, applied to every file; defaults to each file's name),
  `body` (text stored on every item, also checked against the folder's keywords) and `is_html`.
- Each file becomes its own archive item with the file attached, exactly as a portal upload.
- Each file and the whole request must be 128 MB or less. Empty files and file types the portal
  doesn't accept are rejected, and a rejected file means nothing from that request was saved.
- An item that comes back with `isError: true` matched an alert keyword, or none of the required
  keywords. That's the folder working as designed; tell the user which file triggered it.

### Workflow

1. Resolve the company with `search_companies` and list its folders.
2. Show the user: company, folder (and whether it will be created), each file name and size, and the
   subject. Wait for an explicit yes.
3. Call `archive_upload`. Report each item id, file and whether it raised an alert.

### Many files, many clients

When the user drops a batch of reports (for example one backup PDF per client):

1. Match each file to a company, usually from the file name. List every match in a table
   (file, company, folder) and flag files you couldn't match or that matched more than one company.
2. Wait for the user to confirm or correct the table.
3. Upload per company, one `archive_upload` call each. Keep going if one company fails, and report the
   failures at the end.

## Text-only items

When there's no file (a summary the assistant wrote), create an item with `create_resource`,
`resource_type: "archive_item"`, `data: { companyId, archiveId, subject, text, isHtml }`. Read one with
`get_resource` (`archive_id` + `id`). A file's `downloadLink` expires after 24 hours; read the item
again for a fresh one.

## Archive health check

1. `list_resources` on `archive_folder` with `all_pages: true` (add a `companyId` filter for one
   client).
2. **Overdue:** a folder with `warnOnPastDays` > 0 whose `dateLastReceived` is older than that many
   days, or empty.
3. **Alerting:** recent items flagged as errors. List `archive_item` for the folder ordered by
   `dateUploaded desc` and check `isError` where the row has it.
4. Present one row per folder: company, folder, last report date, days overdue, and recent alerts,
   worst first. Read-only: don't change folder settings unless asked.

## Report honestly

Say exactly which files were uploaded where, which were skipped and why. If a folder was created,
say so and list its settings. Never report an upload as done unless `archive_upload` returned the
item ids.
