# Service Management

> Services, installations, managed domains, and products — all from a chat prompt.

**Say this:**

```
Which of my managed domains expire in the next 90 days?
```

<img src="images/skill-result.png" alt="Service management in CloudRadial portal" width="100%">

---

## Try it

| Say this | What you get |
|---|---|
| `What services are installed for Acme Corp?` | Service installations with details |
| `Which of my managed domains expire in the next 90 days?` | Cross-company domain expiration sweep |
| `What services do we track for Contoso?` | The company's service list |
| `Service coverage summary for Contoso` | Which endpoints have each service |
| `List Contoso's managed domains` | Domain list with expiration dates |

## Good to know

- **`service_install` uses a composite key** — on create: `endpoint_id` + `service_id`. On update/delete: `endpoint_id` + `id`.
- **Domain expirations are partner-wide** — ask without naming a company for a roll-up across all clients.
- **Products vs. services** — `product` = a Planner (roadmap) item on a company's IT plan; `service` = a service tracked for the company, with `service_install` showing which endpoints have it.

## Related skills

- [Reporting & Admin](../reporting-admin) — for service-related archive reports.
- [Portal Setup](../portal-setup) — Session 2 focuses on ticketing and service desk setup.
