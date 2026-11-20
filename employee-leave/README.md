# Employee Leave Handled Automatically

A manager submits one portal form and the employee's Microsoft 365 access is paused at once: sign-in disabled and signed out of every device. When they come back, the same form with **Returning from leave** turns access back on.

## What your clients see in the portal

An **Employee Leave** form: the employee's email, the type of leave (leave of absence, parental leave, extended vacation, sabbatical, or returning from leave) and an optional return date. The manager gets a Signal desktop notice when it's done, for example "Leave is set up for Adele Vance".

## What happens behind the scenes

- **Finds the employee** in the client's Microsoft 365 tenant (the tenant ID saved on the company).
- **On leave:** disables sign-in and revokes every session.
- **Returning from leave:** turns sign-in back on.
- **Safe by default:** the manager can't put their own account on leave, and nothing changes if the user isn't found.
- **Notes the ticket** with what changed and the return date, and **sends the manager a Signal**.

## Works with

Microsoft 365 (Entra ID), with your multi-tenant app consented in the client's tenant. ConnectWise PSA for the ticket note.

## What you need

- A UCP portal with **Actions** on your request forms
- AutomationAI, with CloudRadial and ConnectWise connected
- Your Microsoft 365 app with **User.ReadWrite.All** (application permission, admin consent in the client's tenant)
- The client's tenant ID saved on the company in CloudRadial

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://raw.githubusercontent.com/cloudradial/Automations/main/employee-leave/employee-leave.yml) (right-click > Save link as).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.

**In your UCP portal, add the Employee Leave form** (category **Employees**, visible to managers) with these questions:

1. **Comment**, "Subject", default value `Employee leave`, ticked as the subject.
2. **Email**, "Employee going on leave", required. Field ID `leaveUser`.
3. **Multiple choice dropdown**, "Type of leave", options `Leave of absence,Parental leave,Extended vacation,Sabbatical,Returning from leave`, required. Field ID `leaveType`.
4. **Date**, "Expected return date". Field ID `returnDate`.
5. **Action**, "Update their access", and pick **Employee Leave (Microsoft 365)**.

The [form file](https://github.com/cloudradial/Automations/blob/main/employee-leave/forms/employee-leave.json) has every setting, including a branded header.

**Test it.** Use a test account: submit **Leave of absence**, check the user shows **Sign-in blocked** in Entra, then submit **Returning from leave**.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/employee-leave#technical-details) cover the inputs, permissions and secrets.

---

## Technical details

**Marketplace ID:** AAI-00085 | **Type:** Workflow (one PowerShell step, no AI) | **Version:** 1.0.0

## Files

| What | Link |
|---|---|
| View `employee-leave.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/employee-leave/employee-leave.yml) |
| Download `employee-leave.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/employee-leave/employee-leave.yml) |
| Portal form | [forms/employee-leave.json](https://github.com/cloudradial/Automations/blob/main/employee-leave/forms/employee-leave.json) |
| Step source and build script | [src/](https://github.com/cloudradial/Automations/tree/main/employee-leave/src) |

## How it works

```
Start -> Put the employee on leave -> End
```

The step reads `leaveUser`, `leaveType` and `returnDate`, signs in to the client's tenant with client credentials, reads the user, then `PATCH`es `accountEnabled` and calls `revokeSignInSessions`. A leave type containing "return" sets `accountEnabled` to true instead.

## Inputs

| Input | Default | What it does |
|---|---|---|
| `leaveUser`, `leaveType`, `returnDate` | from the form | Who, what kind of leave, and when they're back |
| `cloudradial_company` | none | Use that portal's `CloudRadial-*-<name>` runner secrets for the Signal |
| `confirm` | `true` | `false` previews without changing anything |

## Required runner Key Vault secrets

| Secret | Used for |
|---|---|
| `M365-ClientId`, `M365-ClientSecret` | Signing in to the client's tenant |
| `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | The ticket note |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | The Signal |

## Notes

- The webhook ships disabled. The form's **Action** question runs it.
- It never deletes or unlicenses anyone. For a permanent departure, use [Offboard a Departing Employee](../user-offboarding/).
- Tested live in the AutomationAI test tenant on 2026-11-18 and from the portal form on 2026-11-19 (leave and return, with ticket notes and Signals). Build with `node src/build.js`.
