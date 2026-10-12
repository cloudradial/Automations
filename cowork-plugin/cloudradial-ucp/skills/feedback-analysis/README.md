# Feedback Analysis

> CSAT scores, satisfaction trends, and feedback themes, all from a chat prompt.

**Say this:**

```
What feedback has Contoso submitted lately?
```

<img src="images/skill-result.png" alt="Feedback data in CloudRadial portal" width="100%">

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing in October 2026 (v2.6.3): **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Review recent feedback
`Per-company` · `Read-only` · **Tested**

```
What feedback has Contoso submitted in the last 30 days? Show date, user,
ticket, rating and comment, and call out anyone who asked for a follow-up.
```

**What you get:** Recent feedback, newest first, with follow-ups flagged.

### Compare satisfaction
`All clients` · `Read-only` · **Tested**

```
Which of my clients have the lowest CSAT this quarter? Group by company ID,
leave out deleted companies, and show the number of responses next to each
average.
```

**What you get:** Clients ranked by satisfaction.

### Fix a feedback entry
`Per-company` · `Writes to the portal` · **Tested**

```
Find the feedback for ticket 123456 at Contoso and show me the entry. Change
the rating to Positive with 5 stars and update the comment to "VPN fixed same
day". Show me the before and after, and only save when I confirm.
```

**What you get:** The entry found by ticket, your change previewed, then saved and read back.

**Good to know:** Ratings accept Positive, Neutral or Negative only.

### Move feedback to another company
`Per-company` · `Writes to the portal` · **Tested**

```
The feedback from jane@contoso.com on ticket 123456 was logged under Acme by
mistake. Move it to Contoso. Show me the entry first and only move it when I
confirm.
```

**What you get:** The entry moved, with the company name updated to match.

### Log feedback from outside the portal
`Per-company` · `Writes to the portal` · **Tested**

```
Log phone feedback for Contoso from jane@contoso.com on ticket 123456: 5 stars,
"fast fix on the VPN". Show me the entry before you save it.
```

**What you get:** A new feedback entry.

### Delete a duplicate
`Per-company` · `Writes to the portal` · **Tested**

```
There are two feedback entries for ticket 123456 at Contoso. Show me both and
delete the duplicate only when I confirm which one.
```

**What you get:** The duplicate removed from CSAT history.

## Good to know

- **Comment text matters**: even high-rated feedback can reveal issues. Ask Claude to summarize themes, not just average numbers.
- **Cross-company comparisons are built-in**: ask without naming a company to get a roll-up across all clients.

## Related skills

- [Portal Lookup](../portal-lookup): includes recent feedback in the company overview.
- [User Management](../user-management): resolve user IDs to names in feedback entries.
