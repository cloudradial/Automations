# Employee Leave Handled Automatically

Employees and managers submit one portal form, for themselves or for someone on their team. The employee's Microsoft 365 access is paused on the start date they pick (or right away): sign-in disabled and signed out of every device. On the return date it's turned back on automatically.

## What your clients see in the portal

An **Employee Leave** form: the employee's email (their own or a colleague's), the type of leave (leave of absence, parental leave, extended vacation, sabbatical, or returning from leave), an optional start date and an optional return date. The person who submitted it gets a Signal desktop notice, for example "Leave is scheduled for Adele Vance" or "Leave is set up for Adele Vance", and another when access is paused and when it's back on.

## What happens behind the scenes

- **Finds the employee** in the client's Microsoft 365 tenant (the tenant ID saved on the company).
- **No start date, or today:** disables sign-in and revokes every session right away.
- **A later start date:** nothing changes yet. A daily run pauses access on that morning, so people can set up their own leave ahead of time without being signed out.
- **A return date:** the daily run turns sign-in back on that morning.
- **Returning from leave:** turns sign-in back on now and cancels anything still scheduled for that person.
- **Safe by default:** nothing changes if the user isn't found, and a return date before the start date is refused.
- **Notes the ticket** with what changed or what's scheduled, and **sends the requester a Signal** each time.

## Works with

Microsoft 365 (Entra ID), with your multi-tenant app consented in the client's tenant. ConnectWise PSA for the ticket note.

## What you need

- A UCP portal with **Actions** on your request forms
- AutomationAI, with CloudRadial and ConnectWise connected
- Your Microsoft 365 app with **User.ReadWrite.All** (application permission, admin consent in the client's tenant)
- The client's tenant ID saved on the company in CloudRadial
- A daily **Routine** for scheduled starts and returns

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://raw.githubusercontent.com/cloudradial/Automations/main/employee-leave/employee-leave.yml) (right-click > Save link as).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.
4. Add a **Routine**: daily at 6:00 AM, with this input:

```json
{"mode": "scheduled", "confirm": true}
```

**In your UCP portal, add the Employee Leave form** (category **Employees**) with these questions:

1. **Comment**, "Subject", default value `Employee leave`, ticked as the subject.
2. **Email**, "Employee going on leave", required. Field ID `leaveUser`. Leave the default value empty so nobody puts themselves on leave by accident.
3. **Multiple choice dropdown**, "Type of leave", options `Leave of absence,Parental leave,Extended vacation,Sabbatical,Returning from leave`, required. Field ID `leaveType`.
4. **Date**, "Leave starts". Field ID `leaveStart`.
5. **Date**, "Expected return date". Field ID `returnDate`.
6. **Action**, "Update their access", and pick **Employee Leave (Microsoft 365)**.

The [form file](https://github.com/cloudradial/Automations/blob/main/employee-leave/forms/employee-leave.json) has every setting, including a branded header.

**Test it.** Use a test account: submit **Leave of absence** with a start date of tomorrow and check nothing changed yet. Submit again with no start date and check the user shows **Sign-in blocked** in Entra, then submit **Returning from leave**.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/employee-leave#technical-details) cover the inputs, the schedule, permissions and secrets.

---

## Technical details

**Marketplace ID:** CRA-00020 | **Type:** Workflow (one PowerShell step, no AI), plus a daily Routine | **Version:** 1.1.0

## Files

| What | Link |
|---|---|
| View `employee-leave.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/employee-leave/employee-leave.yml) |
| Download `employee-leave.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/employee-leave/employee-leave.yml) |
| Portal form | [forms/employee-leave.json](https://github.com/cloudradial/Automations/blob/main/employee-leave/forms/employee-leave.json) |
| Step source, tests and build script | [src/](https://github.com/cloudradial/Automations/tree/main/employee-leave/src) |

## How it works

```
Start -> Put the employee on leave -> End
```

**Form run.** The step reads `leaveUser`, `leaveType`, `leaveStart` and `returnDate`, signs in to the client's tenant with client credentials and reads the user. With no start date (or a start date of today or earlier) it `PATCH`es `accountEnabled` to false and calls `revokeSignInSessions`. A future start date and a future return date are saved in the company's `@EmployeeLeaveSchedule` token instead. A leave type containing "return" sets `accountEnabled` to true and removes that person's scheduled entries. A new request for the same person replaces their earlier schedule.

**Scheduled run** (`"mode": "scheduled"`). Reads every `@EmployeeLeaveSchedule` token, applies each start and return dated today or earlier (starts before returns), writes an internal note on the original request ticket, sends the requester a Signal and removes the entry. If Microsoft 365 refuses a change, the entry stays and is retried the next day.

"Today" follows `timeZone`. Dates arrive from the portal as `yyyy-MM-dd`; `MM/dd/yyyy` and ISO dates with a time also work.

## Inputs

| Input | Default | What it does |
|---|---|---|
| `leaveUser`, `leaveType`, `leaveStart`, `returnDate` | from the form | Who, what kind of leave, when it starts and when they're back |
| `mode` | `form` | `scheduled` applies the saved starts and returns that are due |
| `companyIds` | all | Scheduled run: limit it to these CloudRadial company ids |
| `timeZone` | `America/New_York` | Decides what "today" is |
| `scheduleToken` | `EmployeeLeaveSchedule` | The company token that holds the schedule |
| `cloudradial_company` | none | Use that portal's `CloudRadial-*-<name>` runner secrets |
| `confirm` | `true` | `false` previews without changing anything |

## Required runner Key Vault secrets

| Secret | Used for |
|---|---|
| `M365-ClientId`, `M365-ClientSecret` | Signing in to the client's tenant |
| `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | The ticket note |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | The schedule token and the Signal |

## Notes

- The webhook ships disabled. The form's **Action** question and the Routine run it.
- Putting your own account on leave with no start date signs you out straight away, and someone else has to submit **Returning from leave** for you. With a start date, nothing changes before then.
- It never deletes or unlicenses anyone. For a permanent departure, use [Offboard a Departing Employee](../user-offboarding/).
- Local tests: `pwsh -NoProfile -File src/test.ps1` (mocked Microsoft Graph, CloudRadial and ConnectWise, 25 checks).
- Version 1.1.0 was tested live in the AutomationAI test tenant on 2026-11-19: a scheduled start and return, the daily run applying a due start and a due return, and an immediate leave with an automatic return. Build with `node src/build.js`.
