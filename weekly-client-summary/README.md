# Weekly Ticket Summary on the Client's Desktop

Every week, each client gets a short Signal desktop notice: how many tickets you resolved for them, how many are still open, and how many are waiting on a reply from them.

## What your clients see

A Signal notice like: "Your week with IT: 12 resolved. This week we resolved 12 tickets and received 15 new requests. 3 of them are still open, and 1 is waiting on a reply from you. Open the portal to see them."

## What happens behind the scenes

- **Counts the client's ConnectWise tickets** for the last 7 days: resolved, new, new and still open, and waiting on the client.
- **Sends the summary as a Signal** to the users you list. It's marked important when something is waiting on the client.
- **Read-only in ConnectWise.**

## Works with

ConnectWise PSA. Signal needs to be turned on in your portal.

## What you need

- AutomationAI, with ConnectWise and CloudRadial connected
- A **Routine** per client, for example Friday afternoons

## Set it up

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/weekly-client-summary/v1.0.0).
2. In AutomationAI, go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.
4. Add a **Routine** for each client with this input:

```json
{"companyId": 1, "psaCompanyId": 250, "users": ["<CloudRadial user id>"], "confirm": true}
```

**Test it.** Run it with `"confirm": false` first. The result shows the message it would send.

---

## Technical details

**Marketplace ID:** CRA-00017 | **Type:** Workflow (one PowerShell step, no AI) | **Version:** 1.0.0

## Files

| What | Link |
|---|---|
| View `weekly-client-summary.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/weekly-client-summary/weekly-client-summary.yml) |
| Download `weekly-client-summary.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/weekly-client-summary/v1.0.0) |
| Step source and build script | [src/](https://github.com/cloudradial/Automations/tree/main/weekly-client-summary/src) |

## Inputs

| Input | Default | What it does |
|---|---|---|
| `companyId` | required | The CloudRadial company (for the Signal) |
| `psaCompanyId` | required | The same client in ConnectWise |
| `users` | none | CloudRadial user ids to notify. With none, nothing is sent. |
| `waitingStatus` | `Waiting on Client` | Your "waiting on the client" status name |
| `cloudradial_company` | none | Use that portal's `CloudRadial-*-<name>` runner secrets |
| `confirm` | `true` | `false` previews without sending |

## Required runner Key Vault secrets

| Secret | Used for |
|---|---|
| `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | Ticket counts |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | The Signal |

## Notes

- The webhook ships disabled. Run it from a Routine or manually.
- Tested live in the AutomationAI test tenant on 2026-11-18. Build with `node src/build.js`.
