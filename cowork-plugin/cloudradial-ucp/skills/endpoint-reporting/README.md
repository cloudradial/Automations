# Endpoint Reporting

> Warranty status, device inventory, and software audits — all from a chat prompt.

**Say this:**

```
Which of Contoso's devices are out of warranty?
```

<img src="images/skill-result.png" alt="Endpoint inventory in CloudRadial portal" width="100%">

---

## Try it

| Say this | What you get |
|---|---|
| `How many endpoints does Acme Corp have?` | Quick count of managed devices |
| `Which of Contoso's devices are out of warranty?` | Filtered list with expiration dates |
| `Refresh warranty for all of Acme Corp's devices` | Triggers async warranty lookup by serial number |
| `Show all software installed on endpoint 789` | Application list for a specific device |
| `Build a warranty expiration report for the next 6 months` | Sorted list of devices expiring soon |

## Good to know

- **Warranty refresh is async** — `endpoint_update_warranty` triggers a background fetch; new dates appear minutes later.
- **The warranty tool needs the serial number**, not the endpoint ID. Claude looks up the serial first if needed.
- **`lastCheckIn` matters** — devices that haven't checked in recently may have stale data.

## Related skills

- [Assessment & Compliance](../assessment-compliance) — combine with warranty data for GAP analysis.
- [Reporting & Admin](../reporting-admin) — for archived endpoint audit reports.
