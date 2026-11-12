# Keep Warranty Dates Current From ScalePad

Your UCP portal keeps every computer's warranty date in step with ScalePad Lifecycle Manager, and puts one plain "Endpoint Warranty Renewal" card on each client's Planner listing the computers whose warranty has ended. Nothing else comes across from ScalePad, and your clients never see the ScalePad name.

## What your clients see in the portal

**On each computer.** Under **Infrastructure > Endpoints**, the warranty date matches ScalePad. A blank purchase date is filled in too, so hardware refresh reviews can work out each computer's age.

**On the Planner.** One **Endpoint Warranty Renewal** card per client lists the computers that are out of warranty, by name and serial, with the date each warranty ended, and recommends renewing or extending the warranty. The card is updated on every run, closes itself when nothing is out of warranty, and opens again when a warranty ends. It starts hidden from clients, so you decide when they see it.

## What happens behind the scenes

- Each client in your portal is matched to the ScalePad client with the same name, and each computer by its serial number.
- A computer the Endpoint LifeCycle Manager already recommends replacing is left off the warranty card, because it needs a replacement quote, not a new warranty.
- Running it again changes only what has changed since the last run, so it is safe to schedule weekly or monthly.
- A first run previews everything and changes nothing until you say so.

## Works with

ScalePad Lifecycle Manager and any UCP portal.

- **Computers without a serial number,** and virtual machines, can't be matched, so their dates are left as they are.
- **Two ScalePad clients with the same name as one portal client** are skipped until you pair them (see Set it up).

## What you need

- A UCP portal, and AutomationAI with a runner
- A ScalePad Lifecycle Manager API key

## Set it up

1. **Download** the [workflow file](https://raw.githubusercontent.com/cloudradial/Automations/main/scalepad-warranty-sync/scalepad-warranty-sync.yml) (right-click > Save link as).
2. In AutomationAI, go to **Workflows > Import** and upload it. Click **Publish**, then **Deploy**.
3. Add your CloudRadial and ScalePad API details to your runner. The [technical details](https://github.com/cloudradial/Automations/tree/main/scalepad-warranty-sync#secrets) list exactly what to add.
4. **Preview.** Open the workflow, click **Run** and leave the input empty. Nothing changes: the result lists every date it would update and every card it would write.
5. **Run it for real** with this input:

   ```json
   {"confirm": true}
   ```

6. **Schedule it.** Under **Routines**, run it weekly or monthly with the same input.

If a client is skipped because two ScalePad clients share its name, the result names both. Pick one and run again with, for example, `{"confirm": true, "pairs": {"28": "<ScalePad client id>"}}`.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/scalepad-warranty-sync#technical-details) cover every setting, what the result reports, and how it was tested.

---

## Technical details

**Formerly:** none (new) | **Marketplace ID:** Not yet listed | **Type:** Workflow (one PowerShell step, no AI) | **Version:** 1.0.0

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `scalepad-warranty-sync.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/scalepad-warranty-sync/scalepad-warranty-sync.yml) |
| Download `scalepad-warranty-sync.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/scalepad-warranty-sync/scalepad-warranty-sync.yml) |
| Source and tests (for maintainers) | [src/](https://github.com/cloudradial/Automations/tree/main/scalepad-warranty-sync/src) |
| All files in this automation | [scalepad-warranty-sync](https://github.com/cloudradial/Automations/tree/main/scalepad-warranty-sync) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/scalepad-warranty-sync) |
| Works with | [Endpoint LifeCycle Manager](https://github.com/cloudradial/Automations/tree/main/endpoint-lifecycle-manager) (its Replace card) |

## How it works

One PowerShell step, **Sync warranty dates**, with the shared CloudRadial library (`_shared/cloudradial.ps1`) pasted in.

1. **Match companies.** Every CloudRadial company is matched to the ScalePad client with the same name, ignoring case, punctuation and words like Ltd, Limited, Inc and Group. A company that matches two or more ScalePad clients is skipped with a warning naming each one and its id, until `pairs` picks one. `pairs` also pairs a company whose names differ.
2. **Read warranty data.** For each matched client: `GET /lifecycle-manager/v1/assets/hardware/lifecycles` filtered to that client, following `next_cursor`. A 400 or 422 on the first page is retried with a smaller page, then with other filter spellings, as the ScalePad to CloudRadial Sync does.
3. **Update endpoints.** Each CloudRadial endpoint is matched on its serial number (trimmed, ignoring case; placeholder serials such as "To be filled by O.E.M." never match). It then sends a JSON Patch to `/v2/endpoint/id/{id}`:
   - `expirationDate` is set to ScalePad's `warranty_expiry_date` when it is blank, or when it differs and `overwriteWarranty` is on (the default).
   - `manufacturedDate` is filled from ScalePad's `purchase_date` only when it is blank.
4. **The card.** One card per company, subject **Endpoint Warranty Renewal**, written with `Set-CrPlannerCard`. It is found again by its subject or by the marker `Warranty Renewal Card: company <id>` in its body, so it is updated, never duplicated.
   - **Listed:** physical computers whose warranty has ended. With `expiringWithinDays`, warranties ending soon are listed too, in their own section.
   - **Left off:** a computer named on an open **Endpoint Hardware Refresh - Replace** card. The card says how many were left off.
   - **New card:** status open, priority medium, category Efficiency (7), hidden from clients.
   - **Updates** change the body, summary, notes and category only, so a status or priority you set is kept.
   - **Close and reopen:** with nothing out of warranty, an open card is marked Completed. A completed card is reopened when a warranty ends.
   - **No ScalePad name:** the card's subject, body, summary and internal notes never mention ScalePad.

Nothing else is read or written: no initiatives, contracts, insights, flexible assets, software, assessments, meetings or reports.

## Secrets

In the runner's Key Vault, by name:

| Secret | What it is |
|---|---|
| `CloudRadial-BaseUrl` | Your portal's API address, for example `https://api.us.cloudradial.com` |
| `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | A CloudRadial API key pair |
| `ScalePad-ApiUrl` | `https://api.scalepad.com` |
| `ScalePad-ApiKey` | A ScalePad API key with read access to clients and Lifecycle Manager assets |

**Company-scoped secrets.** When a client portal is added to AutomationAI as a Company, set the step's **Company** after import (import clears it), or send `secretSuffix`. The step then reads `<secret>-<suffix>` first and falls back to the plain name.

## Inputs

All optional.

| Field | Default | What it does |
|---|---|---|
| `confirm` | `false` | `true` makes the changes. Anything else previews them. |
| `companyIds` | all matched | Limit to these CloudRadial company ids, for example `"12,40"`. |
| `pairs` | none | Pair companies with ScalePad clients by id: `{"28": "<ScalePad client id>"}`. |
| `overwriteWarranty` | `true` | `false` keeps a CloudRadial warranty date that differs from ScalePad's, and reports it. A blank date is still filled. |
| `fillPurchaseDate` | `true` | `false` leaves blank purchase dates blank. |
| `warrantyCard` | `true` | `false` updates dates only, with no card. |
| `expiringWithinDays` | `0` | Also list warranties ending within this many days (up to 365). |
| `skipReplaceCard` | `true` | `false` lists computers that are on the Replace card too. |
| `plannerCategory`, `plannerProductCategoryId` | `Efficiency`, `7` | The category of a new card. |
| `secretSuffix` | none | Read company-scoped secrets (see Secrets). |

## Output

| Field | What it holds |
|---|---|
| `status` | `ok`, `completed_with_errors` (some companies failed), `failed` (every company failed, and the step fails too) or `error` (setup problem) |
| `message`, `public_note` | One line: companies, computers matched, dates updated or to update, computers out of warranty. A preview says so and gives the input to confirm. |
| `internal_note` | One line per company: matched, updated, filled, without a serial, ScalePad devices not in CloudRadial, out of warranty, and what happened to the card. |
| `actions` | Each change made or previewed (up to 200). |
| `warnings` | Duplicate names to pair, kept differences, missing companies, failures. |
| `counts` | `companies`, `endpointsChecked`, `matched`, `warrantyUpdated`, `purchaseDateFilled`, `differencesKept`, `noSerial`, `notInCloudRadial`, `outOfWarranty`, `cardsCreated`, `cardsUpdated`, `cardsClosed`, `cardsReopened`, `errors`. |

## Build and test

Edit `src/warranty.ps1` (or `_shared/cloudradial.ps1`), never the `.yml`. Then, from the repo root:

```
node scalepad-warranty-sync/src/build.js
pwsh -NoProfile -File scalepad-warranty-sync/src/test.ps1
```

`build.js` writes the `.yml`, pastes in the shared library and checks the workflow's shape. `test.ps1` runs the step as the runner does (strict mode, child scope) against mocked CloudRadial and ScalePad APIs.

## Tested

Mocked CloudRadial and ScalePad APIs, strict mode, placeholder data: 39 checks pass.
- **Preview** reads only and counts every planned change.
- **Confirm:**
  - A blank warranty and purchase date are filled.
  - A different warranty is replaced, with the serial matched despite case and spaces.
  - Matching dates, computers without a serial, virtual machines and computers missing from ScalePad are left alone.
- **The card:**
  - It lists the out-of-warranty computers with their updated dates.
  - It leaves off the future warranty, the virtual machine and the computer on the Replace card.
  - It never mentions ScalePad.
  - It closes for a company with nothing out of warranty, and reopens a completed card when a warranty ends.
  - An update never sets priority.
- **Settings:**
  - `overwriteWarranty: false` keeps a differing date and reports it.
  - `companyIds`, `pairs` for a duplicate name, `warrantyCard: false`, `skipReplaceCard: false` and `expiringWithinDays` all work.
- **Setup and paging:** missing secrets are named, `secretSuffix` reads company-scoped secrets, and a ScalePad 422 on page size 200 is retried at 100.

Not yet run on a tenant.
