# Service Ticket Standards

Owner: Service Desk Manager · Effective: 2026-10-01 · Used by: Split Request Classifier

> **Example standard.** Replace the values in the tables with your own before you upload this to Knowledge. Keep the headings — the agent searches by them.

## Service ticket summary format

The summary is the ticket title. Keep it under 100 characters (ConnectWise limit). Use the pattern for the request type; if nothing fits, use "Other request".

| Request type | Summary pattern | Example |
|---|---|---|
| New user | `New User Setup - {First Last} - Start {start date}` | New User Setup - Dana Reyes - Start 14 Oct |
| Offboarding | `Offboarding - {First Last} - Last day {date}` | Offboarding - Sam Ortiz - Last day 31 Oct |
| Hardware deployment | `Deploy {item} - {user}` | Deploy laptop - Dana Reyes |
| Software install | `Install {application} - {user}` | Install AutoCAD - Dana Reyes |
| Access or permissions | `Access Request - {resource} - {user}` | Access Request - Finance share - Sam Ortiz |
| Mobile device | `Mobile Device Setup - {user}` | Mobile Device Setup - Dana Reyes |
| Other request | `{Short verb phrase} - {user or site}` | Move printer - 2nd floor |

Dates are written as day and short month (`14 Oct`). If a date the pattern needs is missing, leave that part out rather than guessing it.

## Service ticket description layout

Write the description in plain sentences and short bullet lists, in this order:

1. **Request** — one sentence saying what is being asked for and for whom.
2. **Who and when** — the person the work is for, their department and job title, the requester, and the date it's needed by.
3. **What needs doing** — a bullet list of the work, one task per bullet, starting with a verb (Create, Add, Install, Configure, Collect).
4. **Linked quote** — one line saying hardware or licences were split onto a separate quote request, when that happened.
5. **Source** — the form name or source ticket number.

Don't paste raw form field names or JSON into the description.

## Service ticket priority

| Condition | Priority |
|---|---|
| Offboarding with a last day today or already passed | Priority 1 - Critical |
| Start date or needed-by date within 3 business days | Priority 2 - High |
| Start date or needed-by date within 10 business days | Priority 3 - Medium |
| Everything else | Priority 4 - Low |

Use the priority names exactly as written — they must match the PSA's priority list.

## Service ticket type and subtype

| Request type | Type | Subtype |
|---|---|---|
| New user | User Management | New User |
| Offboarding | User Management | Termination |
| Hardware deployment | Hardware | Deployment |
| Software install | Software | Installation |
| Access or permissions | User Management | Access Change |
| Mobile device | Hardware | Mobile Device |

Use the names exactly as written. If the request type isn't in the table, leave type and subtype empty.

## What never goes in a ticket

- Passwords, temporary passwords, MFA or recovery codes.
- Full licence or product keys.
- Personal data beyond name, job title, department, work email and start or last date.
