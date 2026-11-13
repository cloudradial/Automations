# Report Archive

> Upload report files into your clients' portal archives, set up archive folders, and find the reports that are late or alerting.

**Say this:**

```
Upload this backup report to Contoso's Nightly Backups folder
```

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing: **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Upload a report
`Per-company` · `Writes to the portal` · **Not yet tested**

```
Upload the attached backup report PDF to Contoso's "Nightly Backups" archive
folder with the subject "Nightly backup - November 12". Show me the company,
folder and file first, and only upload when I confirm.
```

**What you get:** The PDF stored as an archive item in Contoso's portal, with the file attached.

**Good to know:** The folder's alert keywords still apply, so a report that says "failed" shows as an alert.

### Upload a batch for every client
`All clients` · `Writes to the portal` · **Not yet tested**

```
Here are this month's patch reports, one PDF per client, named after the
client. Match each file to its company and the "Patch Reports" folder, show me
the matches as a table, and only upload when I confirm. Create the folder for
any client that doesn't have one.
```

**What you get:** Every report in the right client's archive, plus a list of any file that couldn't be matched.

### Set up a folder for every client
`All clients` · `Writes to the portal` · **Not yet tested**

```
Make sure every client has a "Security Audits" archive folder that alerts on
"failed" or "critical" and warns if nothing arrives for 35 days. List which
clients already have it and which would get a new one, and only create them
when I confirm.
```

**What you get:** A consistent folder in every client's archive, with the same alert rules.

**Good to know:** New folders start with your partner defaults, which can include sending alerts to your PSA.

### Find overdue reports
`All clients` · `Read-only` · **Not yet tested**

```
Which clients haven't received a report in their archive folders on time?
Show the folder, the last report date and how many days overdue, worst first.
```

**What you get:** One row per late folder across all clients.

### Find failed reports
`Per-company` · `Read-only` · **Not yet tested**

```
Which of Contoso's archived reports from the last 30 days raised an alert?
```

**What you get:** The reports that matched an alert keyword, with their folders and dates.

## Good to know

- **Files up to 128 MB.** Each file and each upload request must be 128 MB or less.
- **One file, one item.** Uploading several files at once creates one archive item per file.
- **Download links expire.** A file's link lasts 24 hours; ask again for a fresh one.
- **Most reports still arrive by email.** Each folder has its own inbound address; the skill can show it.

## Related skills

- [Client Communications](../client-communications): tell the client a new report is ready.
- [Client Deliverable](../client-deliverable): publish a finished QBR or roadmap PDF to the archive.
- [Reporting & Admin](../reporting-admin): certificates, tokens, quickstarts and raw API calls.
