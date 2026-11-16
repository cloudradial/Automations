# Client Health Account Managers

> **Example, replace with your own.** Effective 2026-11-13. The Client Health agent assigns each follow-up to the account manager named here and never picks one itself. Use the names exactly as your PSA shows them.

## Who is each client's account manager?

| Client | Account manager | Watch |
|---|---|---|
| Contoso Ltd | Alex Wilber | yes |
| Fabrikam Inc | Megan Bowen | yes |
| Northwind Traders | Alex Wilber | yes |
| Tailspin Toys | Megan Bowen | no |

A client that isn't listed still gets scored (unless the watch list is in use), but its follow-up is proposed unassigned with a question asking who owns it.

## Where do follow-ups go in ConnectWise PSA?

- **Activity type:** Follow Up
- If that activity type doesn't exist, a flagged company note is proposed instead.

## Where do follow-ups go in Autotask?

- **Queue:** Account Management
- **Priority:** Medium
- **Due:** 3 working days after the check-in

## Where do follow-ups go in HaloPSA?

- **Internal client:** Example MSP (your own company's client record in HaloPSA)
- **Ticket type:** Account Management
