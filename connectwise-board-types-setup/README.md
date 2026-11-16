# ConnectWise Board Types Setup

Give a ConnectWise service board a clean, standard list of ticket Types and Subtypes in one run, so your team and [Ticket Triage from Portal Forms](../ticket-triage-form/) categorize tickets the same way.

## What your clients see in the portal

Nothing. This is a one-time setup tool for your team.

## What happens behind the scenes

- **Adds 10 Types and 35 Type > Subtype pairs** that fit most service desks, for example Email > Outlook, Printer > Not Printing, Account & Access > Password Reset and Network > VPN or Remote Access.
- **Reuses what's there.** Types and Subtypes that already exist on the board are linked, not duplicated.
- **Never renames or deletes anything.**

## Works with

ConnectWise PSA.

## What you need

- AutomationAI, with ConnectWise connected
- The name of the board to set up

## Set it up

1. **Download** the [workflow file](https://raw.githubusercontent.com/cloudradial/Automations/main/connectwise-board-types-setup/connectwise-board-types-setup.yml) (right-click > Save link as).
2. In AutomationAI, go to **Workflows > Import** and upload it. Click **Publish**, then **Deploy**.
3. Run it with your board's name:

```json
{"board": "Service Desk"}
```

4. Open the board in ConnectWise (**System > Setup Tables > Service Board > Types**) and check the list.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/connectwise-board-types-setup#technical-details) list every pair.

---

## Technical details

**Formerly:** Tool: ConnectWise Board Types Setup | **Marketplace ID:** CRA-00009 | **Type:** Workflow (one PowerShell step, no AI) | **Version:** 1.0.0

## Files

| What | Link |
|---|---|
| View `connectwise-board-types-setup.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/connectwise-board-types-setup/connectwise-board-types-setup.yml) |
| Download `connectwise-board-types-setup.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/connectwise-board-types-setup/connectwise-board-types-setup.yml) |
| Step sources and build script | [src/](https://github.com/cloudradial/Automations/tree/main/connectwise-board-types-setup/src) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/connectwise-board-types-setup) |

## The pairs

| Type | Subtypes |
|---|---|
| Account & Access | Password Reset, MFA, Locked Out, Permissions |
| Email | Outlook, Mailbox Access, Spam or Phishing, Shared Mailbox |
| Hardware | Computer or Laptop, Monitor or Peripheral, New Hardware Request |
| Network | Internet Down, Wi-Fi, VPN or Remote Access, Slow Performance |
| Phone | Desk Phone, Voicemail, Teams Calling |
| Printer | Replacement, Toner/Ink, Not Printing, Scanning |
| Security | Suspicious Email, Security Alert, Lost or Stolen Device |
| Software | Installation, Error or Crash, Licensing, Microsoft 365 Apps |
| User Management | New User, User Change, User Offboarding |
| General | Question, Training, Other |

Edit the `$plan` table in `src/setup.ps1` to change them, then run `node src/build.js`.

## How it works

The step finds the board by name, creates missing Types (category Reactive) and Subtypes, then links each Subtype to its Types by patching the Subtype's `typeAssociationIds`. It returns the board's final Type > Subtype list.

ConnectWise's automation host can redirect writes to plain http. The step calls the API host ConnectWise reports, and treats a redirect after a write as saved.

## Required runner Key Vault secrets

`CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId`.

## Notes

- **No preview yet.** The run writes as soon as it starts. A `confirm` flag (default false) is still to be added.
- Exported from the AutomationAI test tenant (tenant version 0.0.2) on 2026-11-12, then split into `src/` with tenant-specific names removed. Build with `node src/build.js`. A strict-mode test harness (`src/test.ps1`) is still to be written.

## Tested

Run against a demo board in the test tenant: 35 pairs created and linked.
