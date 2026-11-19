# Outage Alerts from Vendor Status Pages

When Zoom, Microsoft, Google, Slack or another service your clients rely on has an outage, your clients hear it from you before they open a ticket. One automation checks the vendors' status pages every 10 minutes. A new incident alerts your technicians and tells the client in their portal and on their desktop. When it's fixed, the all-clear goes out the same way.

## What your clients see in the portal

- **A banner** on the portal home page: "Zoom: Zoom is reporting a problem...".
- **A pinned Service Status article** with the details, marked resolved when it's over.
- **A Signal desktop notice:** "Service alert: Zoom", then "Resolved: Zoom".

## What happens behind the scenes

- **Checks the status pages** of Zoom, Google Workspace, Slack, Fathom, Dropbox, Atlassian, CloudRadial and Microsoft Azure by default. Microsoft 365 service health can be added per client tenant.
- **Remembers what it already announced,** so each incident is announced once and cleared once.
- **Ignores old news:** resolved incidents and scheduled maintenance are skipped.
- **Easy to change:** the list of services lives in a portal token, one line per service.
- **Three modes:** `direct` does everything itself (recommended); `approve` only alerts your technicians; `auto` hands each incident to [Outage / Incident Broadcast](../outage-broadcast/).
- **No AI.** It's a plain script, so running it every 10 minutes costs no AI usage.

## Works with

Any portal. Signal needs to be turned on in your portal for the desktop notices.

## What you need

- AutomationAI, with CloudRadial connected
- A **Routine** to run it every 10 minutes
- Optional: your Microsoft 365 app with **ServiceHealth.Read.All** for Microsoft 365 service health

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://raw.githubusercontent.com/cloudradial/Automations/main/status-page-watcher/status-page-watcher.yml) (right-click > Save link as).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.
4. Add a **Routine**: every 10 minutes, with this input (your partner company id, the user ids of the technicians to alert, and the client companies to tell):

```json
{"mode": "direct", "confirm": true, "notifyCompanyId": 1, "notifyUserIds": ["<technician user id>"], "broadcastCompanyIds": [12, 14]}
```

**In your UCP portal:**

1. Add `@ServiceStatus` to the home page banner (or a home page section) of your client portals. It's empty until there's an outage.
2. Optional: create the **@StatusWatcherFeeds** token on your partner company to choose the services, one line each:

```
Zoom | https://status.zoom.us
Google Workspace | https://www.google.com/appsstatus/dashboard/
Slack | https://slack-status.com
CloudRadial | https://status.cloudradial.com/feed.rss
Microsoft Azure | https://rssfeed.azure.status.microsoft/en-us/status/feed/
Microsoft 365 | <client tenant id>
```

The type is worked out from the URL: Atlassian Statuspage pages, Google Workspace, Slack, or any RSS or Atom feed.

**Test it.** Run it with `"simulate": "Zoom"` and `"confirm": true`, then with `"simulateResolved": "Zoom"`. Simulated incidents are never remembered, so the test can be repeated.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/status-page-watcher#technical-details) cover every input and secret.

---

## Technical details

**Marketplace ID:** Not yet listed | **Type:** Workflow (one PowerShell step, no AI), run every 10 minutes by a Routine | **Version:** 1.0.0

## Files

| What | Link |
|---|---|
| View `status-page-watcher.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/status-page-watcher/status-page-watcher.yml) |
| Download `status-page-watcher.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/status-page-watcher/status-page-watcher.yml) |
| Step source and build script | [src/](https://github.com/cloudradial/Automations/tree/main/status-page-watcher/src) |

## Inputs

| Input | Default | What it does |
|---|---|---|
| `mode` | `approve` | `direct`, `approve` or `auto` (see above) |
| `confirm` | `false` | Preview until true |
| `notifyCompanyId` | `1` | Your partner company: technician Signals, and where the state and feed list tokens live |
| `notifyUserIds`, `notifyRoles` | all users | Who gets the technician Signal |
| `broadcastCompanyIds` | `notifyCompanyId` | Direct mode: the client companies to tell |
| `clientUserIds` | all signed-in users | Direct mode: limit the client Signal to these users |
| `minImpact` | `minor` | Lowest impact that counts |
| `statusPages` | the token | One line per service, overrides the token |
| `feedsToken`, `stateToken`, `bannerToken` | `StatusWatcherFeeds`, `StatusWatcherState`, `ServiceStatus` | Token names |
| `m365TenantIds` | none | Microsoft 365 tenants to read service health for |
| `rssMaxAgeHours` | `48` | Ignore RSS items older than this |
| `simulate`, `simulateResolved` | none | Test a made-up incident and its all-clear |
| `cloudradial_company` | none | Use that portal's `CloudRadial-*-<name>` runner secrets |

## Required runner Key Vault secrets

| Secret | Used for |
|---|---|
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Tokens, articles and Signals |
| `M365-ClientID`, `M365-ClientSecret` | Optional. Microsoft 365 service health |
| `StatusWatcher-OutageWebhookUrl`, `StatusWatcher-OutageWebhookSecret` | Auto mode only. The Outage / Incident Broadcast webhook |

## Notes

- The webhook ships disabled. Run it from a Routine.
- Tested live in the AutomationAI test tenant on 2026-11-19: all eight feeds read, a simulated Zoom outage set the banner, article and Signals, the all-clear cleared them, and the 10-minute Routine runs cleanly. Build with `node src/build.js`.
