# "Add a New User" form → New User Onboarding webhook

How the CloudRadial **Add a New User** service request feeds the **New User Onboarding - Day One** playbook, which runs the `new-user-onboarding` agent at each stage.

```
Form "Add a New User"  →  Automation "Create a user (AutomationAI)"  →  Webhook activity (POST JSON)
    →  AutomationAI playbook trigger  new-user-onboarding-day-one-2  →  {{ playbook.briefing }}  →  agent stages
```

Each form question's **Script / JSON Field ID** (question editor → *Show more options*) becomes an `@token` you can use in the Webhook activity's Content. Questions with no Field ID never reach AutomationAI.

## What the playbook needs

The playbook's **intake** stage has to establish, for each starter: full name, **start date**, role, department, company, **who raised it**, **whose access to mirror**, and the ticket number. **A request with no start date is reported as blocked and goes no further.** Later stages also use the licence, groups, and hardware answers.

## Question → Field ID → JSON key

The "Field ID" column is the value to set on each question. The first seven rows already have IDs in the current Content; the rest need one set.

| Page | Question | Type | Field ID | JSON key | Used by |
|---|---|---|---|---|---|
| 1 | First Name | text | `firstName` | `firstName` | intake |
| 1 | Last Name | text | `lastName` | `lastName` | intake |
| 1 | Department | text | `department` | `department` | intake, access plan |
| 1 | Job Title | text | `jobTitle` | `jobTitle` | intake, access plan |
| 3 | New User Email | email (shown when email = Yes) | `email` | `email` | provision |
| 3 | Security Groups | multi-choice (Administrators, Users, Editors, Owners) | `companyFileAccess` | `securityGroups` | access plan |
| 3 | Mail Distribution Groups | multi-choice (from `@MailGroups`) | `mailGroups` | `mailGroups` | access plan |
| 1 | Office Location | text | `officeLocation` | `officeLocation` | provision (usage location, office) |
| 1 | **Start Date** | date | `startDate` | `startDate` | **intake — required, or the run blocks** |
| 2 | Model the new user's account access from | user lookup | `modelAccessFrom` | `mirrorFromUser` | access plan |
| 2 | Software applications required | multi-choice (Adobe Acrobat, Google Chrome, Microsoft Office 365, AutoCAD) | `softwareLicenses` | `software` | procurement, provision |
| 2 | Does the user need a Microsoft 365 License? | Yes / No | `needsM365License` | `needsM365License` | provision |
| 2 | Microsoft 365 License | dropdown (shown when licence = Yes) | `m365License` | `m365License` | provision |
| 3 | Is VPN remote access required? | Yes / No | `vpnRequired` | `vpnRequired` | access plan |
| 3 | Other additions | long text | `otherAdditions` | `otherAdditions` | access plan |
| 3 | Does the user require an email account? | Yes / No | `needsEmail` | `needsEmail` | provision |
| 4 | Will the new user be using an existing or new computer? | Existing / New | `computerSource` | `computerSource` | procurement |
| 4 | Which existing endpoint will be used for the new user? | endpoint lookup (shown when Existing) | `existingEndpoint` | `existingEndpoint` | portal/device check |
| 4 | What type of new computer does the new user require? | dropdown (shown when New) | `newComputerType` | `newComputerType` | procurement (quote) |
| 4 | Which printer does the user need access to? | dropdown | `printer` | `printer` | access plan |
| 4 | Other equipment | long text | `otherEquipment` | `otherEquipment` | procurement (quote) |
| 4 | Does this User need a desk phone? | Yes / No | `deskPhone` | `deskPhone` | procurement |

`softwareLicenses` and `companyFileAccess` keep their existing Field IDs so the older **New User Creation** workflow still reads them; the JSON key renames them to what they actually hold. Attachments and the signature aren't sent.

## Values CloudRadial adds (not questions)

These are CloudRadial's [predefined tokens](https://support.cloudradial.com/hc/en-us/articles/23468736335124-Predefined-Tokens-with-Automations-and-Service-Requests). They're set when the form is submitted and **can't be overridden by a form answer**, so the agent can trust them for the requester check.

| JSON key | Token | Why |
|---|---|---|
| `ticketId` | `@TicketId` | The ticket the stages write notes to |
| `ticketSubject` | `@TicketSubject` | Readable reference in playbook notes |
| `companyName` | `@CompanyName` | The client, for the intake summary and the portal-user stage |
| `companyPsaId` | `@CompanyPsaId` | Resolves the client in ConnectWise without matching by name |
| `companyTenantId` | `@CompanyTenantId` | Which Microsoft 365 tenant to provision in |
| `requestedBy` | `@UserEmail` | Who raised it — the agent checks they're an approved requester for the client |
| `requestedByName` | `@UserName` | The requester's display name, for hand-offs ("name the person to ask") |
| `requestedByOfficeId` | `@UserOfficeId` | The requester's Microsoft 365 id — an exact match, so it can't be spoofed by a similar email |
| `requestedByPsaId` | `@UserPsaId` | The requester's ConnectWise contact, for ticket notes |
| `requestedByIsAdmin` | `@UserIsAdmin` | Whether the requester is a CloudRadial admin for this client — a strong signal they're allowed to approve a starter |

Token rules from the same article that matter here:

- Don't give a question a Field ID that matches a predefined token (for example `UserEmail` or `CompanyName`). The predefined value wins and the answer is lost.
- A token that isn't a Field ID, a standard field, or a predefined token is **left in the JSON as literal text** — so an unset Field ID arrives as `"@startDate"`, not as an empty string. The agent should treat any value that still starts with `@` as missing.

## Webhook activity settings

- **URL** — must be absolute. A relative `/api/hooks/...` URL posts to the CloudRadial portal, not AutomationAI:
  `https://automationai.cloudradial.com/api/hooks/987be4cf-c6cf-4786-b85d-43971adca28a/playbooks/new-user-onboarding-day-one-2/trigger`
- **Method** `POST`, **Content Type** `application/json`, **Authorization Header** empty.
- **Request Headers (JSON)** — the header name and value must be separate strings:
  `{"X-Crauto-Webhook-Secret": "<the playbook's webhook secret>"}`
- **Content:**

```json
{
  "source": "cloudradial-form",
  "form": "Add a New User",
  "ticketId": "@TicketId",
  "ticketSubject": "@TicketSubject",
  "companyName": "@CompanyName",
  "companyPsaId": "@CompanyPsaId",
  "companyTenantId": "@CompanyTenantId",
  "requestedBy": "@UserEmail",
  "requestedByName": "@UserName",
  "requestedByOfficeId": "@UserOfficeId",
  "requestedByPsaId": "@UserPsaId",
  "requestedByIsAdmin": "@UserIsAdmin",
  "firstName": "@firstName",
  "lastName": "@lastName",
  "department": "@department",
  "jobTitle": "@jobTitle",
  "officeLocation": "@officeLocation",
  "startDate": "@startDate",
  "mirrorFromUser": "@modelAccessFrom",
  "software": "@softwareLicenses",
  "needsM365License": "@needsM365License",
  "m365License": "@m365License",
  "securityGroups": "@companyFileAccess",
  "vpnRequired": "@vpnRequired",
  "otherAdditions": "@otherAdditions",
  "needsEmail": "@needsEmail",
  "email": "@email",
  "mailGroups": "@mailGroups",
  "computerSource": "@computerSource",
  "existingEndpoint": "@existingEndpoint",
  "newComputerType": "@newComputerType",
  "printer": "@printer",
  "otherEquipment": "@otherEquipment",
  "deskPhone": "@deskPhone"
}
```

Every value is quoted, so an empty or multi-choice answer still produces valid JSON.

## Confirm before relying on it

- **Editing the form's Field IDs detaches it from its subscription.** In the Westgate Tech Services portal, *Add a New User* is subscribed content, and **Edit → Continue** stops it receiving updates from the package. Decide that before setting the IDs, or make the change in the package source instead.
- The playbook's status must allow a webhook to start a run (it was **Done** after a manual stop on 2026-09-22).
- Submit one test request and check the playbook run's briefing shows every key with a real value — especially `startDate`, `mirrorFromUser`, and `requestedBy`. An `@token` that shows up literally means that question's Field ID doesn't match. Conditional questions that weren't shown (for example `existingEndpoint` when the computer is new) should arrive empty, since they still have a Field ID.
