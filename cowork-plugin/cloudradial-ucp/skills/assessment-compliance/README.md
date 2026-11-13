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

### Record answers
`Per-company` · `Writes to the portal` · **Not yet tested**

```
In Contoso's "2026 Security Review", mark MFA as compliant and backups as
partially compliant, with the note "Offsite copy pending". Show me the
questions and the new answers first, and only save when I confirm.
```

**What you get:** Those answers updated in place, without re-importing the whole assessment.

### Run an assessment
`Per-company` · `Writes to the portal` · **Not yet tested**

```
Run Contoso's "2026 Security Review" assessment as of today. Show me the
assessment and the run name first, and only create the run when I confirm.
```

**What you get:** A point-in-time run of the assessment, answers included, like the portal's Run button.

### Delete a test assessment
`Per-company` · `Writes to the portal` · **Not yet tested**

```
Delete the empty "Test Review" assessment in Contoso's portal, but keep any
runs. Show me the assessment, its score and question count first, and only
delete it when I confirm.
```

**What you get:** The assessment removed from the portal.

**Good to know:** Deleted assessments can't be restored through the API.

### Find Secure Score quick wins
`Per-company` · `Read-only` · **Not yet tested**

```
What's Contoso's Microsoft Secure Score, and which five improvement actions
would raise it most? Mark the low-cost, low-impact ones as quick wins.
```

**What you get:** The current score and the top improvement actions, with links to each setting.

**Good to know:** The company has to be linked to its Microsoft tenant in the portal.

### Copy a template per server
`Per-company` · `Writes to the portal` · **Portal only**

```
Copy our Baseline Security template into Acme's new assessment, one set of
questions per server.
```

**What you get:** Not available through the API yet. The skill tells you to apply the template in the portal.

**Good to know:** The API accepts this call but copies no questions. Use the portal for template copies until it's fixed.

## Good to know

- **Assessments can be run, archived and deleted through the plugin now.** Imports still create or refresh them; there's no single-question edit.
- **Copying a template doesn't work through the API yet.** Apply templates in the portal.
- **Pair with [Endpoint Reporting](../endpoint-reporting)** for a full GAP picture (warranty + assessments).
- **Microsoft Secure Score** comes from CloudRadial's daily Microsoft 365 sync, so it's as of the last sync. For a scheduled version, use the AutomationAI workflow [Turn Microsoft Secure Score into a Client Assessment](https://github.com/cloudradial/Automations/tree/main/secure-score-assessment).

## Related skills

- [Portal Setup](../portal-setup): CSA pain-point #2 ("Improve GAP Analysis") leans on this skill.
- [Reporting & Admin](../reporting-admin): for assessment-related archive reports.
