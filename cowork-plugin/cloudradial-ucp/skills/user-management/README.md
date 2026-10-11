# User Management

> Find, list, and analyze portal users, all from a chat prompt.

**Say this:**

```
Who has access to Contoso's portal?
```

<img src="images/skill-result.png" alt="User list in CloudRadial portal" width="100%">

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing in October 2026 (v2.6.3): **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Find a user
`All clients` · `Read-only` · **Tested**

```
Find john@contoso.com. If they're in more than one company, show each one.
```

**What you get:** The user's company, name, email and department.

### List who has access
`Per-company` · `Read-only` · **Tested**

```
Who has access to Contoso's portal? List name, email and department, sorted by
last name.
```

**What you get:** The full user list.

**Good to know:** Security roles are set in the portal and aren't shown here.

### Add a user
`Per-company` · `Writes to the portal` · **Tested**

```
Add jane@contoso.com, Jane Doe, to Contoso's portal. Check she doesn't already
exist, show me what you'll create, and only add her when I confirm.
```

**What you get:** The new user, read back.

**Good to know:** Job title isn't saved on create. The skill sets it in a second step if you give one.

### Cross-check training
`Per-company` · `Read-only` · **Tested**

```
Which of Contoso's users haven't completed the phishing course? Show name,
email and when they enrolled.
```

**What you get:** Users matched against course enrollments.

**Good to know:** Deleting a user leaves their enrollments behind, so the skill only counts current users.

## Good to know

- **`user_lookup` is the fast path** when you know the email, name, or company.
- **One user can appear in multiple companies**: lookup by email returns across all companies.
- **Pagination is automatic** for companies with thousands of users (API max 200 per page).

## Related skills

- [Portal Lookup](../portal-lookup): includes user counts in the company overview.
- [Course Management](../course-management): to check enrollment and completion per user.
