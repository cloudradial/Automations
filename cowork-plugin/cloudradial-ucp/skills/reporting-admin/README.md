# Reporting & Admin

> Archives, certificates, company groups, quickstarts, media, replacement tokens, and raw API access — all from a chat prompt.

**Say this:**

```
Show me Acme Corp's archived reports
```

<img src="images/skill-result.png" alt="Archive reports in CloudRadial portal" width="100%">

---

## Try it

| Say this | What you get |
|---|---|
| `Show me Acme Corp's archived reports` | List of archive items sorted by date |
| `Which of Contoso's certificates expire in 30 days?` | Filtered certificate list with expiration dates |
| `List Contoso's replacement tokens` | Every @Token value set for Contoso, and the partner-level ones it inherits |
| `Set Contoso's SupportPhone token to 555-0100` | The token every form, article and automation for Contoso uses |
| `Add a quickstart to Contoso's home page on connecting to the VPN` | A published quickstart guide |
| `Hit /v2/odata/company/$count via the API directly` | Raw API response for advanced use cases |

## Good to know

- **`archive_item` uses a composite key** — requires both `archive_id` (folder) and `id` (item).
- **Tokens here are replacement tokens** (`@SupportPhone` and the like), not API keys. A company token overrides the partner-level one of the same name.
- **`raw_api_call` is the escape hatch** — for anything the other tools don't cover.

## Related skills

- [Assessment & Compliance](../assessment-compliance) — for assessment-related archive reports.
- [Endpoint Reporting](../endpoint-reporting) — for endpoint audit archives.
