# Ticket Triage Settings

A simple portal form for choosing how new tickets are triaged: which board they go to, their priority, whether AI picks the Type and Subtype, and whether a note is added. Set it once for every client, or differently for one client.

## What your clients see in the portal

Nothing. This is an admin-only form for your team. It drives [Ticket Triage from Portal Forms](../ticket-triage-form/).

## What happens behind the scenes

- **Checks before saving.** The board and priority must exist in ConnectWise. If not, nothing is saved and the ticket says what's wrong.
- **Saves the settings** as a CloudRadial token, for all clients or for the one client you name.
- **The client setting wins.** A client's own settings are used before the all-clients settings.

## Works with

ConnectWise PSA.

## What you need

- A UCP portal with **Actions** on your request forms
- AutomationAI, with ConnectWise and CloudRadial connected

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://raw.githubusercontent.com/cloudradial/Automations/main/ticket-triage-settings/ticket-triage-settings.yml) (right-click > Save link as).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.

**In your UCP portal, add the Ticket Triage Settings form** to an admin-only category, with these questions:

1. **Comment**, "Subject", default value `Ticket Triage Settings`, ticked as the subject.
2. **PSA Board**, "Board", required. Field ID `triageBoard`.
3. **PSA Priority**, "Priority". Field ID `triagePriority`.
4. **Multiple choice**, "Let AI set the Type and Subtype", options `Yes,No`, default `Yes`. Field ID `triageAiType`.
5. **Multiple choice**, "Add an internal note", options `Yes,No`, default `Yes`. Field ID `triageNote`.
6. **Text**, "Apply to one client only (leave blank for all clients)". Field ID `triageCompany`.
7. **Action**, pick **Ticket Triage: Save Settings**.

The [form file](https://github.com/cloudradial/Automations/blob/main/ticket-triage-settings/forms/ticket-triage-settings.json) has every setting.

**Test it.** Submit the form with your board and leave the client blank. The ticket's note confirms what was saved.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/ticket-triage-settings#technical-details) show the token format.

---

## Technical details

**Formerly:** Ticket Triage: Save Settings | **Marketplace ID:** Not yet listed | **Type:** Workflow (one PowerShell step, no AI) | **Version:** 1.0.0

## Files

| What | Link |
|---|---|
| View `ticket-triage-settings.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/ticket-triage-settings/ticket-triage-settings.yml) |
| Download `ticket-triage-settings.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/ticket-triage-settings/ticket-triage-settings.yml) |
| Portal form | [forms/ticket-triage-settings.json](https://github.com/cloudradial/Automations/blob/main/ticket-triage-settings/forms/ticket-triage-settings.json) |
| Step sources and build script | [src/](https://github.com/cloudradial/Automations/tree/main/ticket-triage-settings/src) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/ticket-triage-settings) |

## How it works

```
Start -> Check and save the triage settings -> End
```

The step reads the form's answers (by Field ID, else by label), checks the board (by name or id) and the priority in ConnectWise, and writes the `TicketTriageSettings` token:

```json
{"board": "Service Desk", "priority": "Priority 3 - Normal", "aiType": true, "note": true}
```

With no client named, the token is saved for company `0` (all clients). With a client named, it is saved for that CloudRadial company. A run with `"confirm": false` checks and previews without saving.

## Required runner Key Vault secrets

| Secret | Used for |
|---|---|
| `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | Checking the board and priority |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Saving the token |

## Notes

- The webhook ships disabled. The form's **Action** question runs it.
- Exported from the AutomationAI test tenant (tenant version 0.0.2) on 2026-11-12, then split into `src/` with tenant-specific names removed. Build with `node src/build.js`. A strict-mode test harness (`src/test.ps1`) is still to be written.
