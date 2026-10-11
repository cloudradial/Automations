# Portal Setup

> Guided implementation sessions and CSA pain-point playbooks, all from a chat prompt.

**Say this:**

```
What does Contoso need next in their CloudRadial implementation?
```

<img src="images/skill-result.png" alt="Portal setup in CloudRadial" width="100%">

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing in October 2026 (v2.6.3): **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Plan the next step
`Per-company` · `Read-only` · **Tested**

```
What does Contoso need next? Check their portal first, tell me which
implementation session they're in, and list what's done and what's missing.
Split the list into what you can do through the API and what I have to do
in the portal.
```

**What you get:** Lifecycle stage, the next checklist, and the API-versus-portal split.

### Run an implementation session
`Per-company` · `Writes to the portal` · **Tested**

```
Walk me through Session 2 for company 42. Check what already exists, then show
me everything you plan to create. Only create it when I confirm, and give me
the portal-only steps as a short to-do list at the end.
```

**What you get:** The service desk session: checks, a preview, then the items created.

**Good to know:** Branding, integrations, security roles and agent deployment stay in the portal. The skill lists them instead of guessing.

### Onboard a new client
`Per-company` · `Writes to the portal` · **Tested**

```
Onboard a new client called Acme Corp. Create the company, then plan Session 1
with me: show me what you'll set up and only create it when I confirm.
```

**What you get:** The company created and Session 1 started.

### Use a pain-point playbook
`Per-company` · `Read-only` · **Tested**

```
Contoso still gets most tickets by email and phone. Use the playbook for that
pain point, check what their portal already has, and give me the steps to
move them to the portal.
```

**What you get:** The matching CSA playbook, applied to what's actually in their portal.

### Prep a QBR
`Per-company` · `Read-only` · **Tested**

```
Prep a QBR for Acme Corp: device count and age, warranty status, assessment
scores, training completion and recent feedback. Don't change anything.
```

**What you get:** One QBR view pulled from endpoints, assessments, courses and feedback.

## Good to know

- **Always start with a lookup**: Claude checks the current portal state first, then adjusts the playbook.
- **5 implementation sessions**: Portal Setup, Ticketing, Content, Reporting, Account Management handoff.
- **8 CSA pain-point playbooks**: from eliminating email tickets to replacing Invarosoft/Desk Director.
- **Not the same as `setup`**: portal-setup configures a client's portal; setup configures the plugin's API keys.

## Related skills

- [Portal Lookup](../portal-lookup): pulls the overview that drives implementation recommendations.
- [Content Management](../content-management): for content seeding during Session 3.
