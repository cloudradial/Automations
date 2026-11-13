# Content Management

> Create KB articles, service catalogs, and portal content, all from a chat prompt.

**Say this:**

```
Seed Contoso's portal with 10 starter KB articles covering password reset, VPN, MFA, and M365 basics
```

<img src="images/skill-result.png" alt="Knowledge Base articles in CloudRadial portal" width="100%">

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing in October 2026 (v2.6.3): **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Write a KB article
`Per-company` · `Writes to the portal` · **Tested**

```
Write a KB article for Contoso about resetting MFA, step by step, for end
users. Show me the article first and only publish it when I confirm.
```

**What you get:** One article, previewed, then created.

### Seed a knowledge base
`Per-company` · `Writes to the portal` · **Tested**

```
Seed Contoso with 10 starter KB articles on common IT topics: password reset,
MFA, VPN, printers and Microsoft 365 basics. List the titles first and only
create them when I confirm.
```

**What you get:** Ten articles created after you approve the list.

### Build a request form
`Per-company` · `Writes to the portal` · **Tested**

```
Build a New User request form for Acme Corp with first name, last name, start
date, department and manager. Make start date required and give each field a
JSON ID my automations can read. Don't send it to the PSA yet, and show me the
form before you create it.
```

**What you get:** A catalog item with its questions, created after you approve it.

**Good to know:** If you don't say, new forms are self-approving, append the subject, and send to the PSA. The skill sets each one on purpose.

### Add a menu tile
`Per-company` · `Writes to the portal` · **Tested**

```
Add a "Get Help" menu tile to Contoso's portal that opens the service catalog.
Copy the category, rights and groups from an existing tile, and show me the
tile before you create it.
```

**What you get:** A new menu tile visible to the right groups.

**Good to know:** Edits now change only the fields you name. If an edit fails, the skill reads the tile and sends the whole tile back instead.

### Audit portal content
`Per-company` · `Read-only` · **Tested**

```
Audit Contoso's portal content: articles, catalog items and menu tiles, with
anything out of date or duplicated called out. Don't change anything.
```

**What you get:** Content by status, with gaps.

### Build a portal dashboard
`Per-company` · `Writes to the portal` · **Not yet tested**

```
Build a "Service Overview" dashboard on Contoso's portal with widgets for open
tickets, device health and recent KB articles. List the widget types you'd use
and the layout first, and only build it when I confirm.
```

**What you get:** A new dashboard on Contoso's portal, laid out as agreed.

**Good to know:** The skill reads the available widget types from the API first instead of guessing them.

## Good to know

- **Articles use `subject`, not `title`**: Claude knows this, but keep it in mind for raw API calls.
- **There's no draft state in the API.** An article is live once it's created, so the prompts ask Claude to show you the content first.
- **HTML conversion is automatic**: describe articles in plain English and Claude formats them.

## Related skills

- [Course Management](../course-management): for training content specifically.
- [Portal Setup](../portal-setup): Session 3 focuses on content and knowledge base setup.
