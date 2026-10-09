# Endpoint Lifecycle Cards

> One Planner card per hardware-refresh category for a client, each with a priority and a plain-language list of the computers in it.

**Say this:**

```
Build hardware refresh cards for Contoso
```

---

## Try it

| Say this | What you get |
|---|---|
| `Build hardware refresh cards for Contoso` | Planner cards for Replace, Plan replacement, Upgrade in place, Retain, Needs data, Human review and Virtual machines, each with a triage priority |
| `Which of Acme Corp's computers need replacing?` | The Replace list, with the reason for each computer |
| `Refresh the lifecycle cards for company 42` | Existing cards updated in place, not duplicated |
| `Show me Contoso's out-of-spec computers without changing anything` | The review as a report, with no cards written |

## Good to know

- **CloudRadial only.** It reads the endpoints already in the portal and writes Planner cards. It doesn't call your RMM or ScalePad.
- **Missing data is reported, not guessed.** Computers without warranty or age data go on the Needs data card.
- **Re-running updates the same cards**, matched by subject, so the client's Planner doesn't fill up with copies.
- **Needs automation instead?** The AutomationAI version, [Keep Every Client's Hardware Refresh Plan Current](https://github.com/cloudradial/Automations/tree/main/endpoint-lifecycle-manager), runs the same rules on a schedule.

## Related skills

- [Endpoint Reporting](../endpoint-reporting): warranty and inventory reports.
- [Client Deliverable](../client-deliverable): turn the refresh plan into a priced, scheduled roadmap.
