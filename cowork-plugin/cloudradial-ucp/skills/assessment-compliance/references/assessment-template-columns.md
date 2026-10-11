# Assessment import template: column guide

Use these column names as keys in `assessment_import` `questions` objects (or as headers in an
.xlsx passed with `file_path`). Names are matched exactly, so use the spelling below. The import
rejects unknown column names.

## Core question columns

| Column | What it holds |
|---|---|
| `Category` | Question category, e.g. `Access Control`. **Required.** Categories always sort alphabetically, so start each name with a number to control order: `1. Identity`, `2. Backup`. |
| `Question` | The question text. **Required.** |
| `Order` | Order within the category. Use steps of 10 (10, 20, 30) so questions can be inserted later without renumbering. |
| `Explanation` | Why the question matters, shown to the client. |
| `Type` | `List` (pick from `Responses`) or `Text` (free text). |
| `Responses` | The answer choices for a `List` question, comma-separated, with a suffix that sets each choice's score (see below). |
| `Answer` | The pre-selected answer as a **score number**, sent as a string: `"2"`, `"1"`, `"0"`, `"-1"`, `"-2"` (see below). Never put a label here: `"Compliant"` in `Answer` makes the whole upload fail. |
| `Text Answer` | The label matching `Answer`: `Compliant`, `Partially Compliant`, `N/A`, `Missing answer`, `Not compliant`. The tool fills it from `Answer` when left out. |
| `Is Flagged` | `Yes` or `No`: flag the question for discussion with the client. The tool sets `Yes` when `Answer` is `"-2"` and this is left out. |
| `Notes` | Client-facing notes on the question. |
| `Evaluation` | How to check or resolve the control. |
| `Remediation Summary` | One-line remediation summary for reports. |
| `Remediation` | Paragraph explaining the remediation, for reports. |
| `Reference` | Source material explaining why the control applies. |
| `Owner` | Person responsible. Doesn't have to match a CloudRadial user. |
| `Partner Notes` | Private notes, partner only. |
| `Updated by` | First and last name of whoever updated the question. |

## Answer scores

| `Answer` | `Text Answer` | Effect on score |
|---|---|---|
| `"2"` | Compliant | +2 |
| `"1"` | Partially Compliant | +1 |
| `"0"` | N/A | 0, and the question leaves `maxScore` |
| `"-1"` | Missing answer | -1 (the default when `Answer` is blank) |
| `"-2"` | Not compliant | -2 |

Every non-N/A question adds 2 to `maxScore`. An assessment imported with no answers scores exactly
-50% (every question -1 of 2), which means **not started**, not failing.

## `Responses` suffix rules

Each choice's score comes from the character after it:

| Suffix | Meaning | Example |
|---|---|---|
| (none) | Compliant | `Yes` |
| `+` | Partially Compliant | `Sort Of+` |
| `=` | N/A | `Not Relevant=` |
| `*` | Missing | `Unanswered*` |
| `-` | Not compliant | `No-` |

Full field: `Yes,Sort Of+,Not Relevant=,Unanswered*,No-`. The tool's default is
`Yes,Partially+,Not Applicable=,Unanswered*,No-`.

## Pricing columns

| Column | What it holds | Client-visible |
|---|---|---|
| `Monthly Units` / `Monthly Unit Price` | Recurring remediation quantity and price | Yes |
| `Project Units` / `Project Unit Price` | One-time remediation quantity and price | Yes |
| `Monthly Unit Cost` / `Project Unit Cost` | Partner's per-unit cost | No |

## Risk matrix columns

| Column | Values |
|---|---|
| `Control Type` | 0 Not specified, 10 Preventative, 20 Corrective, 30 Detective |
| `Likelihood` | 0 Not specified, 1 Rare, 2 Unlikely, 3 Possible, 4 Likely, 5 Almost certain |
| `Risk` | 0 Not specified, 1 Negligible, 2 Minor, 3 Moderate, 4 Major, 5 Severe |
| `Risk Cost` | 0 Not specified, 1 Negligible, 2 Minor, 3 Moderate, 4 Major, 5 Severe |
| `Risk Impact` | 0 Not specified, 5 Very low, 10 Low, 15 Medium, 20 High, 25 Very high |

## Ticket columns (used if the question generates a ticket)

`Psa Board`, `Psa Item`, `Psa Status`, `Psa Category`, `Psa Sub Type`, `Psa Type`, `Psa Priority`,
`Psa Source` (all accept CloudRadial tokens), `Psa Estimated Time`, `Email List` (comma-separated),
`Teams Webhook`, `Slack Webhook`, `Flow Webhook`, `Json Webhook`, `Script` (attached to the ticket,
not run by CloudRadial), `Checklist` (one task per line; `|` for multi-line entries).

## Automatic notes per answer

`Note Compliant`, `Note Partially Compliant`, `Note NA`, `Note Missing`, `Note Not Compliant`: text
inserted into the question's notes when it gets that answer.

## Update keys

- `Update Key` ties an uploaded row to an existing question, so a re-upload into the same
  `assessment_id` replaces answers instead of adding questions.
- `Content Update Key` ties a question across clients when distributed from Partner > Content.
  Leave it blank.
- The portal guidance is to leave `Update Key` blank on new questions and never edit it. The v2
  API has no way to read question keys back, so this plugin generates them instead: send any stable
  name (for example `mfa-all-users`) and the tool turns it into a fixed GUID. Keep that name when
  you reword or move a question, and give a new question a new name. The AutomationAI Microsoft
  Security Assessment workflow uses the same approach.
