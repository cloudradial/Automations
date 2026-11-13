# Recurring Issue Rules

Owner: Service Desk Manager · Effective: 2026-11-13 · Used by: Recurring Issue Finder

> **Example, replace with your own.** Change the values in the tables before you upload this to the Pulsar's notes folder. Keep the headings: the agent looks for them.

## How far back does it look?

| Setting | Value |
|---|---|
| Look-back | 30 days, by date entered |
| Most tickets read per check-in | 300 (it drops to 14 days when there are more) |

## What counts as a theme?

A theme is a group of tickets **for the same client** about the same problem.

- They share a type, subtype, category or item, **and** their summaries share key words once common words are ignored.
- Words to ignore: please, issue, help, problem, not working, urgent, asap, re, fw, and any ticket number, name or date.
- Different wording for the same thing is one theme. "Outlook keeps asking for password" and "Password prompt in Outlook again" are the same.
- Two unrelated problems that share only a type, such as two different printers on "Hardware", are two themes.

## How many tickets make a theme worth a problem ticket?

| Setting | Value |
|---|---|
| Minimum tickets in the look-back | 3 |
| Problem tickets proposed per check-in | 3 (the biggest themes, newest first on a tie) |
| Propose a denied theme again after | 30 days, or sooner if 3 new tickets join it |

## Which clients and boards are skipped?

| Skip | Why |
|---|---|
| Example MSP (our own company) | Internal tickets |
| The problem board or queue itself | Those are already problem tickets |
| Alerts board (example) | Monitoring alerts have their own process. Remove this row if you want them included. |
