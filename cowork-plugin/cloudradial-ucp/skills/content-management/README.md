# Content Management

> Create KB articles, service catalogs, and portal content — all from a chat prompt.

**Say this:**

```
Seed Contoso's portal with 10 starter KB articles covering password reset, VPN, MFA, and M365 basics
```

<img src="images/skill-result.png" alt="Knowledge Base articles in CloudRadial portal" width="100%">

---

## Try it

| Say this | What you get |
|---|---|
| `Create a KB article for Acme Corp about resetting MFA` | An article with step-by-step instructions, shown to you before it's created |
| `Seed Contoso with 10 starter KB articles` | 10 draft articles covering common IT topics |
| `Show me all unpublished articles for Contoso` | Filtered list of draft content ready for review |
| `Audit Contoso's portal content` | Summary of articles, catalogs, and menus by status |
| `Build a service catalog for Acme Corp` | Catalog items for password reset, new user, hardware requests |

## Good to know

- **Articles use `subject`, not `title`** — Claude knows this, but keep it in mind for raw API calls.
- **Content is created as drafts by default** — review before publishing to users.
- **HTML conversion is automatic** — describe articles in plain English and Claude formats them.

## Related skills

- [Course Management](../course-management) — for training content specifically.
- [Portal Setup](../portal-setup) — Session 3 focuses on content and knowledge base setup.
