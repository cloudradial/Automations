# Assessment & Compliance

> Review security assessments and track compliance, all from a chat prompt.

**Say this:**

```
Create a CIS Controls assessment for Contoso with these 20 questions
```

<img src="images/skill-result.png" alt="An assessment in the CloudRadial portal" width="100%">

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing in October 2026 (v2.6.3): **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Check compliance
`Per-company` · `Read-only` · **Tested**

```
How is Contoso doing on compliance? List their assessments with score,
status and date, and leave out runs and templates unless I ask.
```

**What you get:** Assessments with scores, newest first.

**Good to know:** An assessment scoring exactly -50% hasn't been started. It isn't failing.

### Create an assessment from questions
`Per-company` · `Writes to the portal` · **Tested**

```
Create a CIS Controls assessment for Contoso with these 20 questions. Give
each one a category, an explanation and a stable update key, and show me the
list before you import it.
```

**What you get:** A new assessment with the questions loaded.

**Good to know:** Answers are scores (2, 1, 0, -1, -2), not labels. The skill handles that for you.

### Import a spreadsheet
`Per-company` · `Writes to the portal` · **Tested**

```
Turn the attached spreadsheet into an assessment for company 42 called "2026
Security Review". Check the columns match the CloudRadial template first.
```

**What you get:** The .xlsx imported as a new assessment, with scores read back.

**Good to know:** Uploading the same file again into the same assessment updates the answers instead of duplicating them.

### Refresh answers
`Per-company` · `Writes to the portal` · **Tested**

```
Update the answers in Contoso's "2026 Security Review" assessment: MFA is now
compliant and backups are partially compliant. Use the same update keys so
nothing is duplicated.
```

**What you get:** The existing assessment updated in place.

### Copy a template per server
`Per-company` · `Writes to the portal` · **Portal only**

```
Copy our Baseline Security template into Acme's new assessment, one set of
questions per server.
```

**What you get:** Not available through the API yet. The skill tells you to apply the template in the portal.

**Good to know:** The API accepts this call but copies no questions. Use the portal for template copies until it's fixed.

## Good to know

- **The API can't delete or edit assessments.** Imports create or refresh them; delete test assessments in the portal.
- **Copying a template doesn't work through the API yet.** Apply templates in the portal.
- **Pair with [Endpoint Reporting](../endpoint-reporting)** for a full GAP picture (warranty + assessments).
- **Microsoft Secure Score:** the plugin only talks to CloudRadial, so it can't read Secure Score. Use the AutomationAI workflow [Turn Microsoft Secure Score into a Client Assessment](https://github.com/cloudradial/Automations/tree/main/secure-score-assessment), or paste the controls in and ask for an assessment from them.

## Related skills

- [Portal Setup](../portal-setup): CSA pain-point #2 ("Improve GAP Analysis") leans on this skill.
- [Reporting & Admin](../reporting-admin): for assessment-related archive reports.
