# Client Health Scoring

> **Example, replace with your own.** Effective 2026-11-13. The Client Health agent uses these rules instead of its built-in defaults. Delete any section you don't want to change, and the default applies.

## Which clients are scored?

- Clients with at least one ticket or one feedback response in the last **60** days.
- If "Client Health Account Managers" has a watch list, only the clients marked **Watch: yes**.
- Without a watch list, at most the **40** clients with the most tickets in the last 30 days.

## How much does each part count?

| Part | Weight | Needs |
|---|---|---|
| CSAT (last 90 days) | 40 | 3 or more responses |
| Ticket volume trend (last 30 days vs the 30 before) | 20 | Always (fewer than 5 tickets in both windows counts 100) |
| SLA met (tickets created in the last 30 days) | 25 | 3 or more tickets with an SLA result |
| Aged open tickets (open more than 14 days) | 15 | Always |

A part without enough data is left out, and the others are rescaled.

## How is CSAT scored?

Positive counts 100, Neutral 50 and Negative 0. The part is the average.

## How is the volume trend scored?

| Last 30 days divided by the 30 before | Part |
|---|---|
| up to 1.1 | 100 |
| up to 1.5 | 70 |
| up to 2.0 | 40 |
| above 2.0 | 10 |

## How are aged open tickets scored?

| Open tickets older than 14 days | Part |
|---|---|
| 0 | 100 |
| 1 or 2 | 70 |
| 3 to 5 | 40 |
| more than 5 | 10 |

## When does a client get a follow-up?

- The score fell **15** or more points since last week, or
- the score is below **60**.
- At most **10** follow-ups per check-in, worst first, and none for a client that had one in the last **14** days.
