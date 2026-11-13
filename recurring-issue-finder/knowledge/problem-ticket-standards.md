# Problem Ticket Standards

Owner: Service Desk Manager · Effective: 2026-11-13 · Used by: Recurring Issue Finder

> **Example, replace with your own.** Change the values in the tables before you upload this to the Pulsar's notes folder. Keep the headings: the agent looks for them.

## Where do problem tickets go?

Use the exact names from your PSA. The agent looks up the ids.

| PSA | Setting | Value |
|---|---|---|
| ConnectWise PSA | Board | Problem Management |
| ConnectWise PSA | Type (optional) | Problem |
| Autotask | Queue | Problem Management |
| Autotask | Ticket type | Problem |
| Autotask | Priority | Medium |
| HaloPSA | Ticket type | Problem |

## How is the summary written?

`Recurring: {theme} - {client}`, under 100 characters.

Example: `Recurring: Outlook asks for password - Contoso`

## What goes in the description?

In this order:

1. **Pattern:** one sentence with the number of tickets, the days, the number of users and the problem.
2. **Tickets:** each ticket number, summary and date, newest first.
3. **What they have in common.**
4. **Root-cause check:** two or three things to check first.
5. **KB draft:** a title, symptoms, likely cause and workaround steps, with no client or personal details.

## Who looks at it?

| Setting | Value |
|---|---|
| Owner | Leave unassigned. The service desk manager assigns problem tickets at the weekly review. |
| KB drafts (HaloPSA) | Created hidden (inactive) until a technician reviews them |
