# Portal Lookup

> Company search, portal health checks, and meeting prep, all from a chat prompt.

> `Prepare me for my meeting with Contoso`

<img src="images/portal-result.png" alt="Meeting prep visual showing portal snapshot, feedback, flags, and talking points" width="100%">

Claude pulls real data from the portal and renders an interactive visual card with stats, recent feedback, flags, and suggested talking points, ready for your call.

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing in October 2026 (v2.6.3): **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Find a client
`Per-company` · `Read-only` · **Tested**

```
Look up Acme Corp in CloudRadial. If more than one company matches, list them
and ask me which one. Show the company ID, user count, endpoint count and the
most recent articles and feedback.
```

**What you get:** One company snapshot, or a short list to pick from.

**Good to know:** Partial names work: "Acme" matches "Acme Corp" and "Acme Holdings". Once you know the ID, use it to skip the search.

### Prepare for a meeting
`Per-company` · `Read-only` · **Tested**

```
Prepare me for my meeting with Contoso tomorrow. Tell me where they are in
Land, Onboard, Manage, Grow, what looks healthy, what looks stalled, any
negative feedback, and three talking points. Don't change anything.
```

**What you get:** A meeting-prep card with portal stats, flags and talking points.

### Check portal adoption
`Per-company` · `Read-only` · **Tested**

```
How is Acme Corp doing in their portal? Compare users, articles, catalog items
and recent feedback against what a fully onboarded client should have, and
tell me the biggest gap.
```

**What you get:** An adoption snapshot and the one gap to fix first.

### Compare several clients
`All clients` · `Read-only` · **Tested**

```
Show me overviews for Acme, Contoso and Globex side by side: users, endpoints,
articles, catalog items and average feedback rating. Point out which one
needs attention most.
```

**What you get:** A side-by-side comparison.

## Good to know

- **Search is fuzzy**: partial names work ("Acme" matches "Acme Corp", "Acme Holdings").
- **Results are framed against the LOMG lifecycle**: Land, Onboard, Manage, Grow.
- **Meeting prep renders a visual card**: includes portal stats, recent feedback with rating badges, flags, and actionable talking points.
- **Company IDs are stable numbers**: once known, use them directly to skip the search step.

## Related skills

- [Portal Setup](../portal-setup): for guided implementation after the lookup.
- [Content Management](../content-management): to act on content gaps identified in the overview.
