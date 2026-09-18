# Split Request — Support + Quote

From one CloudRadial form submission, create **two linked ConnectWise tickets** — a
support/provisioning ticket and a sales quote request — and cross-reference them.
Built for the *new user + new PC* case; generic beyond it.

## Test it against the "Add a New User" form

1. **Import** `split-request-two-tickets.yml` (Workflows → Import), then **publish**
   and **deploy** it to **han-prod** (the runner with the `CW-*` secrets).
2. **Enable the webhook** (Properties → Webhook → Enable — exports ship with it OFF)
   and copy the URL + secret.
3. **Add the board secrets** to the han-prod Key Vault (or pass them in the payload):
   - `CW-ServiceBoard` — the board for the provisioning ticket (e.g. your service board).
   - `CW-SalesBoard` — the board for the quote ticket (e.g. Sales / Procurement).
   (`CW-ApiUrl` / `CW-CompanyID` / `CW-PublicKey` / `CW-PrivateKey` / `CW-ClientId` already exist for the Password Reset / KnowBe4 work.)
4. **Point the form at it.** On the **Add a New User** form (content item 133), add a
   **second Automation → Webhook** activity targeting this workflow's hook, sending the
   secret in the `X-Crauto-Webhook-Secret` header. Leave the existing New User Creation
   webhook alone (or clone the form for testing).
5. **(Recommended) add a hardware Field ID.** The form's Equipment questions have empty
   Script/JSON Field IDs, so hardware detail isn't sent. Give the PC question a Field ID
   of **`deviceType`** so the quote ticket carries the requested model. Without it the
   quote ticket uses a placeholder line.
6. **Submit the form** as a test user → you should get **two CW tickets**:
   - *New User Provisioning - <name>* on `CW-ServiceBoard`, and
   - *New PC / Hardware Quote - <name>* on `CW-SalesBoard`, referencing the support ticket,
   with an internal note on the support ticket linking the quote. The run output shows
   `supportTicketId` and `quoteTicketId`.

## Field mapping (verified Add-a-New-User Field IDs → tickets)

| Form Field ID | Used for |
|---|---|
| `firstName` + `lastName` | Ticket subject + display name |
| `department` | Support ticket body + quote "for whom" |
| `jobTitle` | Support ticket body |
| `email` | Requested email (support body) |
| `softwareLicenses` | "Software / apps to assign" (support body) |
| `companyFileAccess` | "Security groups / access" (support body) |
| `deviceType` *(add this one)* | Hardware line on the quote ticket |
| envelope `companyName` / `companyId` / `ticketId` | CW company resolution + source-ticket reference |

## Notes
- CW company is resolved from `companyIdentifier` → `companyName` → CloudRadial `companyId`→`psaIdentifier`.
- Ticket summaries are trimmed to CW's 100-char limit. Cross-link note is non-fatal.
- No contact object is set (the new user doesn't exist yet), so tickets land at company level with the requester named in the body.
