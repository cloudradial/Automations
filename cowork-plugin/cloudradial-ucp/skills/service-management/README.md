# Service Management

> Services, installations, managed domains, and products, all from a chat prompt.

**Say this:**

```
Which of my managed domains expire in the next 90 days?
```

<img src="images/skill-result.png" alt="Service management in CloudRadial portal" width="100%">

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing in October 2026 (v2.6.3): **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### See what's running
`Per-company` · `Read-only` · **Tested**

```
What Windows services does the agent report on Contoso's DC01? Flag any
backup or antivirus service that isn't running.
```

**What you get:** The services the CloudRadial agent reports for that device.

**Good to know:** "Services" here means Windows services from the agent, not your service catalog. Request forms are in Content Management.

### Domain expirations
`All clients` · `Read-only` · **Tested**

```
Which of my managed domains expire in the next 90 days? Group by client and
leave out deleted companies.
```

**What you get:** A domain expiration sweep.

### Add a domain
`Per-company` · `Writes to the portal` · **Tested**

```
Add contoso.com as a managed domain for Contoso. Check it isn't already there
and show me what you'll create.
```

**What you get:** The domain added.

### Service coverage
`Per-company` · `Read-only` · **Tested**

```
For Contoso, which endpoints are missing the backup agent service?
```

**What you get:** Endpoints with and without the service.

## Good to know

- **`service_install` uses a composite key**: on create: `endpoint_id` + `service_id`. On update/delete: `endpoint_id` + `id`.
- **Domain expirations are partner-wide**: ask without naming a company for a roll-up across all clients.
- **Products vs. services:** `product` is a Planner (roadmap) item on a company's IT plan; `service` is a Windows service reported by the CloudRadial agent, with `service_install` showing which endpoints have it.

## Related skills

- [Reporting & Admin](../reporting-admin): for service-related archive reports.
- [Portal Setup](../portal-setup): Session 2 focuses on ticketing and service desk setup.
