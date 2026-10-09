# Assessment & Compliance

> Review security assessments and track compliance — all from a chat prompt.

**Say this:**

```
Create a CIS Controls assessment for Contoso with these 20 questions
```

<img src="images/skill-result.png" alt="An assessment in the CloudRadial portal" width="100%">

---

## Try it

| Say this | What you get |
|---|---|
| `Show me Contoso's assessment scores` | Assessment list with status, score, and completion date |
| `How is Acme Corp doing on compliance?` | Summary across assessments — passing, failing, in progress |
| `Which company has the lowest assessment score?` | Cross-company comparison |
| `Create a CIS Controls assessment for Contoso with these 20 questions` | A new assessment with the questions loaded, ready for the client to complete |
| `Turn this spreadsheet into an assessment for company 42` | The .xlsx (CloudRadial assessment template layout) imported as a new assessment |
| `Copy our Baseline Security template into a new assessment for Acme, one set per server` | Template questions duplicated for each of Acme's servers |
| `Roll up assessment scores across all my clients` | Cross-customer executive summary (with the Assessment Export skill) |
| `Flag the highest-impact non-compliant controls for Contoso` | Sorted list of controls by score impact |

## Good to know

- **Assessments are list-only** — `get_resource` doesn't work for individual assessments (API quirk). Use `list_resources` with a filter instead.
- **Pair with [Endpoint Reporting](../endpoint-reporting)** for a full GAP picture (warranty + assessments).
- **Microsoft Secure Score:** the plugin only talks to CloudRadial, so it can't read Secure Score. Use the AutomationAI workflow [Turn Microsoft Secure Score into a Client Assessment](https://github.com/cloudradial/Automations/tree/main/secure-score-assessment), or paste the controls in and ask for an assessment from them.

## Related skills

- [Portal Setup](../portal-setup) — CSA pain-point #2 ("Improve GAP Analysis") leans on this skill.
- [Reporting & Admin](../reporting-admin) — for assessment-related archive reports.
