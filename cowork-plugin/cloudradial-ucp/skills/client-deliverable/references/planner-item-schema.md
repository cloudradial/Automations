# Planner Item (Product) Schema

A Planner item is a `Product` record. Everything below was verified against a live
portal via `create_resource` / `list_resources` on `resource_type: "product"`.

## Required on create

`create_resource` rejects the call without these. `category` is the trap — it is the
category **name string**, and it is required *in addition to* the numeric
`productCategoryId`. Omitting it returns:

```
{"errors":{"category":["The Category field is required."]}}
```

| Field | Type | Note |
|---|---|---|
| `companyId` | int | Target company |
| `productCategoryId` | int | FK to `ProductCategory`, enforced |
| `category` | string | The category name, e.g. `"Efficiency"` |
| `subject` | string | Item title |
| `body` | string | HTML. Where the asset appendix goes |
| `summary` | string | One line, shown on the card |

## Scheduling

`productType` sets the scheduling mode:

| Value | Mode | Behaviour |
|---|---|---|
| `0` | Not Scheduled | No dates. Off the Timeline. Correct for an overdue backlog |
| `1` | Quarter Offset | Legacy. Uses `scheduledQuarter`. Do not set on new items |
| `2` | Project Dates | Requires `estimatedStartDate`. Puts a bar on the Timeline |

For quarter alignment with `productType: 2`, set the dates to quarter bounds:

| Quarter | Start | End |
|---|---|---|
| Q1 | `YYYY-01-01T12:00:00Z` | `YYYY-03-31T12:00:00Z` |
| Q2 | `YYYY-04-01T12:00:00Z` | `YYYY-06-30T12:00:00Z` |
| Q3 | `YYYY-07-01T12:00:00Z` | `YYYY-09-30T12:00:00Z` |
| Q4 | `YYYY-10-01T12:00:00Z` | `YYYY-12-31T12:00:00Z` |

Use midday UTC to avoid a timezone shift landing the item in the neighbouring quarter.

## Status

Send the string on write. The API returns the `MatrixStatus` int on read.

| String | Int | Use |
|---|---|---|
| `Proposed` | 0 | Recommended, not yet agreed |
| `Draft` | 1 | Not ready to show |
| `Client_Approved` | 10 | Approved, not started |
| `In_Planning` | 20 | Scoped, scheduled |
| `In_Progress` | 30 | Under way |
| `Completed` | 40 | Done. Also the right status for an active contract line |
| `Client_Declined` | 50 | Declined |

`priority` takes `"Low"` / `"Medium"` / `"High"`, returned as `-1` / `0` / `1`.

## Pricing

| Field | Meaning |
|---|---|
| `projectUnits` x `projectUnitPrice` | One-time investment |
| `monthlyUnits` x `monthlyUnitPrice` | Recurring monthly |
| `projectUnitCost`, `monthlyUnitCost` | Partner-internal cost. Never shown to clients |

Extension is derived, not stored. `isShowPrice: true` is required or the client sees
the item with no number. `isShowEstimated: true` exposes hours, duration and staff.

## Visibility

| Field | Effect |
|---|---|
| `isClientVisible` | `false` hides the item from the client entirely |
| `isShowPrice` | Controls price display independently of visibility |
| `currentlyInstalled` | `true` marks it as existing service rather than a proposal |
| `isActive` | `false` deactivates without deleting. The reversible cleanup |

## Creating a category inline

No standalone category endpoint and no OData listing exist. `ProductRequest` accepts a
nested `categoryData` object:

```json
{
  "companyId": 42,
  "subject": "Workstation Replacement Q1 2027",
  "category": "Hardware Refresh",
  "body": "<p>...</p>",
  "summary": "...",
  "categoryData": {
    "name": "Hardware Refresh",
    "order": 10,
    "color": "#1F6FEB",
    "body": "Endpoint lifecycle and refresh work"
  }
}
```

Omit `productCategoryId` inside `categoryData` to create; supply it to update an
existing one. Capture the `productCategoryId` from the response and reuse it on
subsequent items so you create the category once, not once per item.

## Cross-entity links present on the record

| Field | Links to |
|---|---|
| `psaOpportunityKey` | A PSA quote |
| `psaProjectKey` | A PSA project |
| `psaTicketKey` | A PSA ticket |
| `psaSalesOrderKey` | A PSA sales order |
| `assessmentKey`, `assessmentQuestionKey` | The assessment finding that produced the item |

There is **no endpoint or asset link**. A planner item cannot reference a device.
Render the asset table into `body`.

## Asset appendix table

```html
<h4>Linked assets (3)</h4>
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;width:100%">
  <thead>
    <tr><th align="left">Name</th><th align="left">Model</th>
        <th align="left">Serial Number</th><th align="left">Reason</th></tr>
  </thead>
  <tbody>
    <tr><td>DESKTOP-EL2UQ6A</td><td>Dell Precision 5570</td><td>8MGBKN3</td>
        <td>Warranty expired 24 Jun 2025</td></tr>
  </tbody>
</table>
```

Populate the Reason column from the field that actually triggered the recommendation.
Where the endpoint carries no serial, write `Not reported` rather than leaving the cell
blank or inventing a value.

## Fields that exist but are undocumented

`scoring` (int) is present on every product row and backs a partner-side Planner
"Scoring" view. Its computation is not documented anywhere available. Do not build on
it or explain it to a partner without confirming behaviour first.

## Field-name corrections

The endpoint entity in some older docs is described with `endpointId`,
`warrantyExpirationDate` and `operatingSystem`. The live entity returns
`companyEndpointId`, `expirationDate` and `os`. Filter and select with the live names.
