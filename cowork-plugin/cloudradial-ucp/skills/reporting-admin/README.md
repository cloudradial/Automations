# Reporting & Admin

> Archives, certificates, company groups, quickstarts, media, replacement tokens, and raw API access, all from a chat prompt.

**Say this:**

```
Show me Acme Corp's archived reports
```

<img src="images/skill-result.png" alt="Archive reports in CloudRadial portal" width="100%">

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing in October 2026 (v2.6.3): **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Certificate expirations
`Per-company` · `Read-only` · **Tested**

```
Which of Contoso's certificates expire in the next 30 days, and are any
already invalid?
```

**What you get:** Certificates with expiration dates and validity.

### Set a replacement token
`Per-company` · `Writes to the portal` · **Tested**

```
Set Contoso's SupportPhone token to 555-0100. Show me the current company and
partner values first and only save when I confirm.
```

**What you get:** The token every Contoso form, article and automation uses.

**Good to know:** A company token overrides the partner one with the same name. Token names are case-sensitive.

### Add a quickstart
`Per-company` · `Writes to the portal` · **Tested**

```
Add a quickstart to Contoso's home page on connecting to the VPN. Show me the
text first and only publish it when I confirm.
```

**What you get:** A published quickstart guide.

### Archive a report
`Per-company` · `Writes to the portal` · **Not yet tested**

```
Upload this month's backup summary PDF to Contoso's Backup Reports archive
folder. Show me the company, folder and file first, and only upload when I
confirm.
```

**What you get:** An archive item with the PDF attached, as if you'd uploaded it in the portal.

**Good to know:** For batches, new folders and overdue checks, see [Report Archive](../report-archive).

### Add an image to the media library
`Partner-wide` · `Writes to the portal` · **Tested**

```
Upload the attached logo to my media library with the description "Contoso
logo".
```

**What you get:** The image stored in your partner media library.

**Good to know:** Media belongs to your partner account, not to one company.

### Raw API call
`All clients` · `Read-only` · **Tested**

```
Count all companies with a raw API call to /v2/odata/company/$count.
```

**What you get:** The raw API response, for anything the other skills don't cover.

## Good to know

- **`archive_item` uses a composite key**: requires both `archive_id` (folder) and `id` (item).
- **Tokens here are replacement tokens** (`@SupportPhone` and the like), not API keys. A company token overrides the partner-level one of the same name.
- **`raw_api_call` is the escape hatch** for anything the other tools don't cover.

## Related skills

- [Report Archive](../report-archive): upload report files, set up folders, find overdue reports.
- [Assessment & Compliance](../assessment-compliance): for assessment-related archive reports.
- [Endpoint Reporting](../endpoint-reporting): for endpoint audit archives.
