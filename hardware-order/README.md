# Order Computer Hardware

A client asks for a laptop or a monitor on a portal form, and the request comes back as a priced quote from your distributors, then an order that goes in the moment you approve it. Nobody has to look up part numbers, compare prices or retype the address.

## What your clients see in the portal

- **An Order Hardware form.** They list what they need, one item per line (for example "2 x ThinkPad T14" or a part number), and where to send it.
- **Updates on their ticket.** Once the order is placed, the ticket says it has been ordered, with a reference they can quote.

## What happens behind the scenes

- Each item is priced at **Ingram Micro** and **TD SYNNEX**. The cheapest offer that's in stock wins; if nobody has enough stock, the cheapest backorder is used and flagged.
- The quote goes onto the ticket as an internal note: every line, the vendor, the price and the total.
- **Nothing is ordered until a person approves it.** The order waits in AutomationAI for approval, with the exact vendor, lines, prices and address.
- Right before ordering, the price is checked again. If it has gone up by more than 5%, that order stops and the ticket says why.
- After ordering, the vendor order numbers go on the ticket, and the client gets a short public update.
- The PO number comes from the ticket, so running it again can never place a second order.

## Works with

Ingram Micro and TD SYNNEX (US accounts), and any PSA the shared library supports (ConnectWise, Autotask, HaloPSA, Kaseya BMS, Syncro, Zendesk).

- **Dell, Lenovo, HP and Microsoft Surface** are ordered through the distributors. None of them has an ordering API that an MSP can use.
- **D&H** isn't supported yet.
- **US addresses only,** and up to 5 items per request.

## What you need

- AutomationAI with a runner, and the **Ingram Micro** and/or **TD SYNNEX** extensions set up with your reseller API keys
- A UCP portal with **Actions** on your request forms

## Set it up

1. **Download** the [workflow file](https://raw.githubusercontent.com/cloudradial/Automations/main/hardware-order/hardware-order.yml) (right-click > Save link as).
2. In AutomationAI, go to **Workflows > Import** and upload it. Click **Publish**, then **Deploy**.
3. In your UCP portal, create a request form called **Order Hardware** with the questions in the [technical details](https://github.com/cloudradial/Automations/tree/main/hardware-order#the-form), and add an **Action** question that picks **Order Computer Hardware**.
4. **Preview.** Open the workflow, click **Run** with its test input. You get the quote back, and nothing is noted or ordered.
5. Submit the form once as a test user, check the quote on the ticket, and **deny** the approval so nothing is bought.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/hardware-order#technical-details) cover the form, the settings, the approvals and how it was tested.

---

## Technical details

**Formerly:** none (new) | **Marketplace ID:** Not listed yet | **Type:** Workflow (PowerShell steps and two agent steps) | **Version:** 1.0.0

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `hardware-order.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/hardware-order/hardware-order.yml) |
| Download `hardware-order.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/hardware-order/hardware-order.yml) |
| Step sources, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/hardware-order/src) |
| All files in this automation | [hardware-order](https://github.com/cloudradial/Automations/tree/main/hardware-order) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/hardware-order) |

## How it works

`Start > Read the request > Price it at each vendor (agent) > Pick the best offers and post the quote > Place the approved orders (agent) > Record the order on the ticket > End`

1. **Read the request** (PowerShell, read-only). Parses the form: one item per line (`2 x 21MN0001US`, `1 x 27 inch USB-C monitor`, or `21MN0001US x 2`), the ship-to address, and the budget. The PO number is `HW-<ticket id>`.
2. **Price it at each vendor** (agent, read tools only). Ingram Micro: `im_search_catalog`, then one `im_get_price_availability` call. TD SYNNEX: one `tds_get_price_availability` call by manufacturer part number. TD SYNNEX has no catalog search, so an item given only as a description is priced there only after Ingram Micro has found its manufacturer part number. A vendor that fails on every call is skipped and named in the warnings.
3. **Pick the best offers and post the quote** (PowerShell).
   - Per line, it picks the cheapest offer the account may buy with enough stock, or else the cheapest backorder.
   - Lines are grouped by vendor. With two vendors, the PO numbers get `-IM` and `-TD` suffixes.
   - With `confirm`, it adds the quote to the ticket once, marked `[hardware-quote <PO>]`.
   - It stops before ordering when an item couldn't be priced, or the total is over `budget`.
4. **Place the approved orders** (agent). It re-checks the price, then proposes `im_create_order` or `tds_submit_po`, once per vendor. Both tools require approval, so the run waits for a person.
   - If a price rose by more than 5%, it stops that order.
   - If a result is unclear, it searches by PO number before anything else.
5. **Record the order on the ticket** (PowerShell). Adds an internal note with each vendor order number (once, marked `[hardware-order <PO>]`), and a public note when anything was ordered.

## The form

Field IDs for the **Order Hardware** form. Only `items` and the address are required.

| Field ID | Question | Notes |
|---|---|---|
| `items` | What do you need? | Multi-line text, one item per line, quantity first: `2 x ThinkPad T14 Gen 5` or a part number |
| `shipName` | Company or recipient | Defaults to the company name |
| `shipAttention` | Attention | |
| `shipAddress1`, `shipAddress2` | Street address | `shipAddress1` required |
| `shipCity`, `shipState`, `shipZip` | City, state, ZIP | Required |
| `shipCountry` | Country | `US` (default) only |
| `shipPhone`, `shipEmail` | Delivery contact | Email defaults to the requester |
| `neededBy` | Needed by | Shown on the quote only |
| `budget` | Budget | When set, a total above it is quoted but not ordered |
| `notes` | Notes | |

From a form **Action**, the run is live (`confirm` true), but every order still waits for approval. The ticket, company and requester come from the portal, and a form answer can't set `ticketId`, `confirm`, `vendors` or `psa`.

## Required extensions and secrets

| Extension | Secrets |
|---|---|
| `ingram-micro` 0.1.0 | `IngramMicro-ClientId`, `IngramMicro-ClientSecret`, `IngramMicro-CustomerNumber` |
| `td-synnex` 0.1.0 | `TDSynnex-ClientId`, `TDSynnex-ClientSecret` |

Plus, on the runner:
- `PSA-Type` and the PSA's own secrets, for the ticket notes.
- `HardwareOrder-Vendors` (optional): `ingram-micro`, `td-synnex`, or both, comma separated. The default is both.

## Inputs (a flat body from Test or a webhook)

| Input | Default | Meaning |
|---|---|---|
| `ticketId` | none | The ticket to note. Needed to order. |
| `company`, `requester_email` | none | Shown on the quote; the requester gets the ship-to email by default |
| `items` and the form fields above | | As on the form |
| `vendors` | `HardwareOrder-Vendors`, else both | `ingram-micro`, `td-synnex` |
| `confirm` | `false` | `false`: quote only, nothing noted or ordered. `true`: note the quote and send the orders for approval. |
| `psa` | `PSA-Type` | PSA override |

## Output

The standard contract: `status` (`success`, `pending_confirmation`, `incomplete` or `error`), `message`, `public_note`, `internal_note`, `ticket_id`, `po_number`, `actions`, `warnings` and `counts` (`orders_planned`, `orders_placed`, `orders_not_placed`), plus `total`, `quote` (the quote text) and `orders` (vendor, PO, status, order number and message for each).

## Build and test

```
cd hardware-order
node src/build.js                     # writes hardware-order.yml
pwsh -NoProfile -File src/test.ps1    # strict-mode harness for the three PowerShell steps
```

## Tested

- `src/test.ps1`: 35 checks pass under strict mode. The two agent steps are replaced by fixed outputs, against a mocked ConnectWise.
- **Not run live yet.** The Ingram Micro and TD SYNNEX extensions aren't in the catalog yet. Before the first live order:
  - check one real price and availability reply from each vendor;
  - place one order in each vendor's sandbox, or deny the approval;
  - confirm how the approval appears for an agent step in your tenant.
