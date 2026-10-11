# Company Management

> Create, update, organize, and audit companies, all from a chat prompt.

**Say this:**

```
Audit all my companies for missing branding and messaging settings
```

<img src="images/skill-result.png" alt="Company audit showing settings across all companies" width="100%">

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing in October 2026 (v2.6.3): **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### List and audit companies
`All clients` · `Read-only` · **Tested**

```
List all my companies with their ID, account manager and endpoint count.
Flag any with no account manager.
```

**What you get:** A company list with gaps flagged.

**Good to know:** The stored endpoint count on a company can be out of date, so the skill counts endpoint rows instead.

### Create a company
`Per-company` · `Writes to the portal` · **Tested**

```
Create a new company called Acme Corp. Check no company with a similar name
exists first, show me the fields you'll send, and only create it when I
confirm.
```

**What you get:** The new company and its ID.

**Good to know:** Follow up with Portal Setup to walk through implementation.

### Change company settings
`Per-company` · `Writes to the portal` · **Tested**

```
Change the account manager for Contoso to Jane Smith. Show me the current
value and the new one, and only save when I confirm.
```

**What you get:** The company updated and read back.

**Good to know:** Branding and messaging can be read but not written through the API. Those stay in the portal.

### Organize company groups
`All clients` · `Writes to the portal` · **Tested**

```
Add Acme Corp to the "Office 365 Only" group. If the group doesn't exist, ask
me before creating it.
```

**What you get:** Group membership updated.

### Rename a company group
`All clients` · `Writes to the portal` · **Tested**

```
Rename the "Office 365 Only" company group to "M365 Clients". Show me which
companies are in it first, and only rename it when I confirm.
```

**What you get:** The group renamed with its members kept.

## Good to know

- **`list_resources` returns limited fields**: use `get_resource` by ID for more detail (territory, account manager). Branding and messaging are portal-only: the API can't set them.
- **Company groups use composite keys**: `company_group_company` needs both `company_group_id` and `company_id` for get/delete.
- **After creating a company**, use the [Portal Setup](../portal-setup) skill to walk through implementation.

## Related skills

- [Portal Lookup](../portal-lookup): for company overview and meeting prep.
- [Portal Setup](../portal-setup): for guided implementation after creating a company.
- [Reporting & Admin](../reporting-admin): for company group reports and cross-company analytics.
