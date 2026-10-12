# Endpoint Lifecycle Cards

> One Planner card per hardware-refresh category for a client, each with a priority and a plain-language list of the computers in it.

**Say this:**

```
Build hardware refresh cards for Contoso
```

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing in October 2026 (v2.6.3): **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Build refresh cards
`Per-company` · `Writes to the portal` · **Tested**

```
Build hardware refresh cards for Contoso. Show me which computers go in each
category and why, and only write the Planner cards when I confirm.
```

**What you get:** One Planner card per category, each with a priority.

**Good to know:** Computers with no age and no warranty date go to Needs data, never Retain.

### Preview without writing
`Per-company` · `Read-only` · **Tested**

```
Show me Contoso's out-of-spec computers by refresh category without changing
anything.
```

**What you get:** The review as a report, with no cards written.

### Update existing cards
`Per-company` · `Writes to the portal` · **Tested**

```
Refresh the lifecycle cards for company 42. Update the existing cards in
place, don't create copies, and tell me which computers moved category.
```

**What you get:** Cards updated, with what changed.

**Good to know:** A card left with no computers changes to Completed on its own.

### Find what needs replacing
`Per-company` · `Read-only` · **Tested**

```
Which of Acme Corp's computers need replacing now, and why?
```

**What you get:** The Replace list with the reason for each computer.

## Good to know

- **CloudRadial only.** It reads the endpoints already in the portal and writes Planner cards. It doesn't call your RMM or ScalePad.
- **Missing data is reported, not guessed.** Computers without warranty or age data go on the Needs data card.
- **Re-running updates the same cards**, matched by subject, so the client's Planner doesn't fill up with copies.
- **Needs automation instead?** The AutomationAI version, [Keep Every Client's Hardware Refresh Plan Current](https://github.com/cloudradial/Automations/tree/main/endpoint-lifecycle-manager), runs the same rules on a schedule.

## Related skills

- [Endpoint Reporting](../endpoint-reporting): warranty and inventory reports.
- [Client Deliverable](../client-deliverable): turn the refresh plan into a priced, scheduled roadmap.
