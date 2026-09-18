# Add CC to Ticket

A standalone **workflow** that adds a user/email to an existing ConnectWise ticket's
notification CC list (de-duplicated), driven from a self-service form field. No agent — a
single PowerShell script node.

## Pieces

| File | Type | Role |
|---|---|---|
| [`add-cc-to-ticket.yml`](add-cc-to-ticket.yml) | `automationsWorkflow` | Reads `ticketId` + `ccEmail` from the form payload, appends the address to the CW ticket's `automaticEmailCc` (sets `automaticEmailCcFlag`), and leaves an internal note. Accepts a flat `{key:value}` body or the CloudRadial `{Ticket:{Questions:[{Id,Answer}]}}` shape. |

## Install / run

1. Import `add-cc-to-ticket.yml` on **Workflows → Import**.
2. Add the ConnectWise secrets to the runner Key Vault: `CW-ApiUrl`, `CW-CompanyID`,
   `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` (the workflow errors listing any missing).
3. Trigger from a CloudRadial service-request form that supplies `ticketId` (or
   `ticketNumber`) and `ccEmail`. To webhook-trigger, open **Properties → Webhook** and enable
   it after import (exports ship with it OFF).

## Confirm in your tenant

- ConnectWise Manage REST creds present in the runner Key Vault under the names above.
- Payload field ids: `ticketId`/`ticketNumber` and `ccEmail` (aliases handled: `cc`, `ccUser`,
  `email`, `user`, `contactEmail`).
- **Idempotent:** if the address is already on the CC list it reports "no change." The
  internal-note write is non-fatal (a failure is reported but doesn't fail the run).
