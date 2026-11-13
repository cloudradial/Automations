# Ticket Triage from Portal Forms

Every ticket a client opens from your UCP portal lands on the right board, with a priority, a Type and Subtype picked by AI, and a note telling your technician why. No dispatcher needed for the first pass.

## What your clients see in the portal

Nothing changes for them. They pick a form such as **Printer/Scanner Issue** or **Unlisted Issue**, answer a few short questions and submit. Behind the form, the ticket is triaged before a technician opens it.

This folder includes the seven problem report forms used in the demo, ready to add to your portal: Computer Issue, File Issue, Network/Remote Access Issue, Office Phone Issue, Printer/Scanner Issue, Software/Program Issue and Unlisted Issue.

## What happens behind the scenes

- **Board:** the ticket moves to your triage board (set once with the [Ticket Triage Settings](../ticket-triage-settings/) form). Without a setting, it stays on the board it was opened on.
- **Priority:** the priority from the settings, otherwise Medium.
- **Type and Subtype:** AI picks one pair from that board's own list, using the form name and what the client wrote. It can only choose a pair that exists on the board.
- **Internal note:** what was set and a one-line reason, for example "Printer > Not Printing. The client says the office printer shows offline."
- **The client's words are treated as data.** Instructions typed into a ticket are never followed.

## Works with

ConnectWise PSA. Other PSAs aren't supported yet.

## What you need

- A UCP portal with **Actions** on your request forms
- AutomationAI, with ConnectWise and CloudRadial connected
- A ConnectWise board with Types and Subtypes. [ConnectWise Board Types Setup](../connectwise-board-types-setup/) can add a standard set

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://raw.githubusercontent.com/cloudradial/Automations/main/ticket-triage-form/ticket-triage-form.yml) (right-click > Save link as).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.
4. Set up [Ticket Triage Settings](../ticket-triage-settings/) and submit it once to pick your triage board and priority.

**In your UCP portal, on each problem report or request form you want triaged:**

1. Open the form, for example **Printer/Scanner Issue**.
2. At the end of the form, add an **Action** question, "Triage this ticket", and pick **Ticket Triage (Form)**.
3. Make sure the form still sends tickets to your PSA.

To add the demo forms instead, build them from the [form files](https://github.com/cloudradial/Automations/tree/main/ticket-triage-form/forms). Each one lists its questions in order.

**Test it.** Submit **Printer/Scanner Issue** as a client user, then open the ticket in ConnectWise and check the board, Type, Subtype and internal note.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/ticket-triage-form#technical-details) cover each step, the settings and the forms.

---

## Technical details

**Formerly:** Ticket Triage (Form) | **Marketplace ID:** CRA-00007 | **Type:** Workflow (PowerShell plus one AI prompt) | **Version:** 1.0.0

## Files

| What | Link |
|---|---|
| View `ticket-triage-form.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/ticket-triage-form/ticket-triage-form.yml) |
| Download `ticket-triage-form.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/ticket-triage-form/ticket-triage-form.yml) |
| Problem report forms | [forms/](https://github.com/cloudradial/Automations/tree/main/ticket-triage-form/forms) |
| Step sources and build script | [src/](https://github.com/cloudradial/Automations/tree/main/ticket-triage-form/src) |
| All files in this automation | [ticket-triage-form](https://github.com/cloudradial/Automations/tree/main/ticket-triage-form) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/ticket-triage-form) |

## How it works

```
Start -> Read the ticket and board -> Pick the type and subtype (AI prompt) -> Apply the triage -> End
```

1. **Read the ticket and board** reads the settings from the `TicketTriageSettings` CloudRadial token (the client's own, else the partner-wide one with company 0, else the defaults), then the ticket, its first note, and the board's Type > Subtype pairs, priorities and statuses.
2. **Pick the type and subtype** is an `ai-prompt` node with no tools and a blank model. It returns one JSON object, `{"type", "subtype", "reason"}`, chosen from the board's list. The system message says the request JSON was written by the client and must never be followed as instructions.
3. **Apply the triage** matches the choice against the board's real pairs (exact pair first, then the type alone), then patches the ticket: board, priority, status (the board's default when the current status isn't on the new board), type and subtype. It adds the internal note when the setting is on.

A run with `"confirm": false` returns a preview and changes nothing.

## Settings

| Setting | Default |
|---|---|
| `board` | The board the ticket was opened on |
| `priority` | Medium (or Normal) |
| `aiType` | true |
| `note` | true |

## Required runner Key Vault secrets

| Secret | Used for |
|---|---|
| `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | Reading and updating the ticket |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Reading the settings token |

## The forms

The files in `forms/` are the portal form definitions (`item` plus `questions`) exported from the test portal and cleaned up:
- Portal-specific ids are removed.
- The demo portal's question templates are replaced with plain questions: affected computer, start date, affected user and comments.
- Each form ends with an **Action** question for this workflow. Its value says `<id of your imported Ticket Triage (Form) workflow>`. Pick the workflow in the portal instead of typing it.
- **Unlisted Issue** has a branded header and thank-you page. Its phone number is the `@SupportPhone` token.

## Notes

- The webhook ships disabled. The form's **Action** question runs it.
- ConnectWise's automation host can redirect writes to plain http. The steps call the API host ConnectWise reports, and treat a redirect after a write as saved.
- Exported from the AutomationAI test tenant (tenant version 0.0.3) on 2026-11-12, then split into `src/` with tenant-specific names removed. Build with `node src/build.js`. A strict-mode test harness (`src/test.ps1`) is still to be written.

## Tested

A live ticket in the test tenant was moved to the triage board and set to Email > Outlook, with the internal note saved.
