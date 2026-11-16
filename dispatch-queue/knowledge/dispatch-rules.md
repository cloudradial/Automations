# Dispatch Rules

Owner: Service Desk Manager · Effective: 2026-11-14 · Used by: Dispatch Queue

> **Example, replace with your own.** Change the values, keep the headings: the agent looks for them. Delete a section to use the agent's default.

## Which boards or queues does the Dispatch Queue watch?

| Board or queue | Watched |
|---|---|
| Service Desk | Yes |
| Projects | No |
| Sales | No |

Default: every service board or queue.

## How far back does it look?

Tickets created in the last **14 days**.

## How many tickets does it read and propose?

| Setting | Value |
|---|---|
| Tickets read per check-in | 30 |
| Assignments proposed per check-in | 8 |
| Assignments per technician per check-in | 2 |
| Load cap (open tickets a technician already owns) | 12 |

## How does priority score?

| Priority name | Points |
|---|---|
| Priority 1 - Critical | 60 |
| Priority 2 - High | 40 |
| Priority 3 - Medium | 20 |
| Priority 4 - Low | 0 |

Copy your PSA's priority names exactly.

## Does it add a why-note to each assigned ticket?

**No.** Change to **Yes** to propose one internal note per assignment saying why it was picked. Each note is a separate proposal to approve.
