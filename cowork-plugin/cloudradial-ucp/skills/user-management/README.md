# User Management

> Find, list, and analyze portal users — all from a chat prompt.

**Say this:**

```
Who has access to Contoso's portal?
```

<img src="images/skill-result.png" alt="User list in CloudRadial portal" width="100%">

---

## Try it

| Say this | What you get |
|---|---|
| `Find user john@contoso.com` | User record with company, title and department |
| `Who has access to Contoso's portal?` | Full user list with names and emails (roles are portal-only) |
| `How many users does Acme Corp have?` | Quick count by company |
| `List Contoso's users with just name, email, and title` | Filtered fields for a clean view |
| `Which of Contoso's users haven't completed security training?` | Cross-referenced with course enrollments |

## Good to know

- **`user_lookup` is the fast path** when you know the email, name, or company.
- **One user can appear in multiple companies** — lookup by email returns across all companies.
- **Pagination is automatic** for companies with thousands of users (API max 200 per page).

## Related skills

- [Portal Lookup](../portal-lookup) — includes user counts in the company overview.
- [Course Management](../course-management) — to check enrollment and completion per user.
