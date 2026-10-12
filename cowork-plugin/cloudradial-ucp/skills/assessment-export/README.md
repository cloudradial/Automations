# Assessment Export

> Every client's completed assessments in one roll-up, with an executive summary of gaps, common issues and trends.

**Say this:**

```
Roll up assessment scores across all my clients
```

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing in October 2026 (v2.6.3): **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Roll up every client
`All clients` · `Read-only` · **Tested**

```
Roll up assessment scores across all my clients. Leave out deleted companies
and templates, then give me a spreadsheet with one row per assessment and an
executive summary.
```

**What you get:** A spreadsheet plus an executive summary.

### Rank the gaps
`All clients` · `Read-only` · **Tested**

```
Which customers have the most assessment gaps? Rank them by score and call
out any assessment that hasn't been started.
```

**What you get:** Clients ranked by gaps.

### Summarize a quarter
`All clients` · `Read-only` · **Tested**

```
Give me an assessment executive summary for Q3: completed runs, average
scores, the most common gaps and the trend against Q2.
```

**What you get:** Overview, gaps, remediation opportunities and trends for the period.

## Good to know

- **One place instead of one client at a time.** The portal's Excel and Word exports work per assessment run; this pulls every client through the API.
- **Summary-level scores.** The API returns one score per assessment run. Per-question answers come from the portal's per-run Excel export, and the skill says so instead of estimating them.
- **Read-only.** Nothing is written to the portal.

## Related skills

- [Assessment & Compliance](../assessment-compliance): review one client, or create an assessment.
- [Portal Lookup](../portal-lookup): a client snapshot before a review meeting.
