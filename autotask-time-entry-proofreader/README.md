# Clean Up Time Entry Notes Before They Reach an Invoice

A standing proofreader for your Autotask time entries. Every weekday it reads the notes your technicians wrote on yesterday's time, fixes spelling, shorthand and tone to match your own style guide, and proposes each correction for a reviewer to approve. Credentials typed into a note are removed, and anything that needs a person is flagged instead of edited.

## What your team sees

- **One proposal per time entry that needs a fix,** showing the ticket, the technician, the original note, the corrected note and a plain list of what changed. For example: "pw reset for usr, unlocked acct in AD" becomes "Reset the user's password and unlocked the account in Active Directory."
- **Approve and the corrected note is written to Autotask. Deny and the entry is left alone** for the reviewer to edit, and the proofreader remembers why.
- **Flagged entries** listed in the check-in summary: notes with credentials, frustration about a client, internal-only remarks or unclear meaning.

## What happens behind the scenes

- It reads time entries worked in the date range (yesterday by default), at most 15 per check-in, oldest first.
- It skips entries already approved or posted to billing, and entries with no notes.
- It changes only the Summary Notes. Hours, dates, technician, billing code, role, ticket, internal notes and billable status are never touched, and it never posts time.
- It follows only your style guide. If the guide can't be found, it uses a built-in copy of the example rules.
- Optionally, after a correction is approved, it can also propose marking the entry approved for billing.

## Works with

Autotask. Other PSAs aren't supported.

## What you need

- AutomationAI with Pulsars, and a runner with an AI provider
- The Autotask extension from the catalog, installed and working on that runner, in a version with its time entry tools (it must list `at_update_time_entry_notes` and `at_approve_time_entry`)
- Your style guide: start from the example and change the rules to your own

## Set it up

**1. Add the agent and your style guide.**

1. Download the agent from the [technical details](https://github.com/cloudradial/Automations/tree/main/autotask-time-entry-proofreader#technical-details) and upload it on **Agents > Custom**.
2. Edit the **Autotask Time Entry Style Guide** template to match your standards.
3. In **Knowledge**, create a folder called **Time Entry Review** and upload the style guide to it.

**2. Create the Pulsar.** Go to **Pulsars > New Pulsar** and answer the five questions:

1. **Who's doing the work?**
   - **Agent:** Autotask Time Entry Proofreader
   - **Runner:** the runner where your Autotask extension works.
   - **Name:** Time Entry Review
2. **What's the goal?** `Review the Autotask time entries worked yesterday and propose Summary Notes corrections that follow the Autotask Time Entry Style Guide, one proposal per entry with the original note, the corrected note and the change list.`
   - **How will we know it's done?** `Every eligible entry in range has been corrected, flagged for the reviewer, or confirmed compliant.`
3. **When should it check in?** **On a schedule**, **Every weekday morning**.
4. **How much can it do on its own?** **Propose changes** (the default). Every correction waits for the reviewer.
5. **Where does it keep notes?** **An existing Knowledge folder:** **Time Entry Review**, the folder with your style guide.

**3. Limits and who hears from it.**

- **Limits:** start with a per-check-in limit of about 120,000 tokens and the default monthly limit. Leave the finish rules off.
- **Who should hear from it?** Make sure the person who approves time entries is a recipient. Turn on **Also post to Teams channels** if they review there.

**4. Test it.** Click **Save draft**, then **Try a check-in now**. Check each proposed correction keeps the technician's meaning and follows your guide. Deny one to see it learn. Then click **Start**.

**Optional settings** (on the agent, after you upload it): `proposeApproval` and `approverResourceName` add a "mark approved for billing" proposal after each approved correction; `notifyCompliantEntries` also lists entries that needed no change.

**On demand:** the agent also comes with a small workflow, **Autotask Time Entry Proofreading**, that runs one check-in when you click **Run**, optionally with `{"startDate": "2026-11-02", "endDate": "2026-11-06", "companyName": "Contoso"}`.

## Need more detail?

See the [technical details](https://github.com/cloudradial/Automations/tree/main/autotask-time-entry-proofreader#technical-details) for the tools it uses, its output and how to build and test it.

---

## Technical details

**Marketplace ID:** AAI-00089 | **Type:** Pulsar (custom agent plus a goal workflow) | **Version:** 0.5.0

## Files

| What | Link |
|---|---|
| Agent | [`autotask-time-entry-proofreader.agent.yml`](https://github.com/cloudradial/Automations/blob/main/autotask-time-entry-proofreader/autotask-time-entry-proofreader.agent.yml) |
| Goal workflow | [`autotask-time-entry-proofreader.yml`](https://github.com/cloudradial/Automations/blob/main/autotask-time-entry-proofreader/autotask-time-entry-proofreader.yml) |
| Style guide template | [knowledge/](https://github.com/cloudradial/Automations/tree/main/autotask-time-entry-proofreader/knowledge) |
| Build source and tests | [src/](https://github.com/cloudradial/Automations/tree/main/autotask-time-entry-proofreader/src) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/autotask-time-entry-proofreader) |

## How it works

| Step | What the agent does |
|---|---|
| **Rules** | The style guide from the notes folder or knowledge search; otherwise the embedded fallback. `rulesSource` says which. |
| **Read** | One turn in parallel: `at_query_time_entries` on `dateWorked` in the range, `at_query_companies` when `companyName` is set, `at_query_resources` for the approver when `proposeApproval` is on. `at_get_time_entry` only to fill in one incomplete entry. |
| **Decide** | Credentials (remove and flag), flag without editing, correct, or already compliant, in that order, then the billing review when the guide has billing rules. |
| **Propose** | `at_update_time_entry_notes` (id and summaryNotes only), one per entry, with the original, corrected note and change list in the reason. When `proposeApproval` is on, `at_approve_time_entry` after an approved correction. |
| **Note and result** | A short note to the Pulsar's folder (counts, proposals, denials as rules, entries left), then the final JSON result. |

**Budget:** at most 15 entries and about 15 tool calls a check-in, never more than 20, inside the runner's 25-turn limit. Entries beyond 15 wait for the next check-in.

### Output

One JSON object: `startDate`, `endDate`, `companyName`, `rulesSource`, `rows` (one per entry: IDs, original and corrected notes, `changes`, `status` Updated, Flagged or Skipped, `flagReasons`, `reason`, `writeBack`, `notifyReviewer`, `proposalResult`), `totals` and `summaryTableMarkdown`.

### Agent settings

- `model` is blank, so it uses the runner's provider. The prompt opens with the one-sentence-before-each-tool-call rule, and only the final message is the bare JSON object, so Anthropic never gets an empty message.
- `requiredExtensionSlugs`: `autotask-psa` only (33 tools). It needs `at_get_time_entry`, `at_update_time_entry_notes` and `at_approve_time_entry`, which the catalog `autotask-psa` had on 2026-11-13.
- `dryRunDefault` is true. The goal workflow's agent node has `autoApprove: false`, `allowedExtensions` set to `autotask-psa`, and its webhook ships off.

### Changes from 0.4.0

- **Model:** was pinned to `gpt-5.4`; now blank.
- **Empty messages:** the one-sentence rule is first in the prompt. The old "output valid JSON only, with no text outside the JSON object" now applies only to the final message.
- **Budget:** at most 15 entries per check-in, parallel reads, named tools for each read, and a rule never to re-propose a pending correction.
- **Notes:** each check-in writes a short note, so denials carry over.
- **Style guide:** shipped as a Knowledge template.

### Tested

0.4.0 ran one Pulsar check-in in a test tenant on 2026-10-22 ("Try a check-in now"): it evaluated the day's entries and made 3 proposals. 0.5.0 hasn't run live yet.

## Build and test

Edit `src/prompt.md`, `src/build.js` or `src/tools-snapshot.json`. Never edit the generated `.yml` files.

```
node autotask-time-entry-proofreader/src/build.js
node autotask-time-entry-proofreader/src/test.js
```

`test.js` checks that both files parse (and every embedded JSON string), the marker, slug and version, a blank model, the empty-message rule, the JSON-only rule limited to the final message, the entry cap, that every tool the prompt names is in the snapshot and every write is an allowed proposal, `autoApprove: false`, the webhook off, no dashes, the README setup questions, and that the generated files are current.
