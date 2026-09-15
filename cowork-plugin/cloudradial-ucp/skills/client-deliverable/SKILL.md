---
name: client-deliverable
description: >
  Build a vCIO-style client deliverable in a CloudRadial portal: IT roadmap, goals,
  budget, machine audit, and Microsoft licenses in one place. Use when the user says
  "build a client deliverable", "recreate this in CloudRadial", "IT roadmap for [company]",
  "budget report", "quarterly business review", "QBR deck", "asset lifecycle plan",
  "hardware refresh plan", "how do I do what Lifecycle Insights does", "ScalePad",
  "Lifecycle Manager", "myITprocess", "vCIOToolbox", "DMI score", "maturity score",
  "how does our scoring compare", "map a ScalePad PDF to CloudRadial", "import a ScalePad
  Lifecycle Manager deliverable", "sync ScalePad asset/EOL data to endpoints", "write
  warranty/EOL dates onto endpoints", or is migrating a partner off a third-party vCIO/QBR
  tool onto CloudRadial. Also use when asked to turn endpoint EOL or warranty data into
  a priced, quarter-scheduled plan.
metadata:
  version: "1.1.0"
---

# Client Deliverable Builder

Assemble a vCIO-style deliverable (roadmap, goals, budget, machine audit, Microsoft
licenses) inside a CloudRadial portal, using Planner items as the spine and one
Report Layout as the delivery vehicle.

Partners migrating from ScalePad Lifecycle Manager X (formerly Lifecycle Insights),
myITprocess, or vCIOToolbox arrive with a PDF and ask "can CloudRadial do this."
Three quarters of it ships today. Be precise about which quarter does not.

For a **ScalePad Lifecycle Manager** PDF specifically — including how to read the PDF and
how to write its asset/EOL data back onto the real endpoints — follow
`${CLAUDE_PLUGIN_ROOT}/skills/client-deliverable/references/scalepad-lifecycle-mapping.md`
alongside the sequence below.

**Automated alternative.** The same ScalePad → CloudRadial mapping also ships as an
AutomationAI workflow, **ScalePad → CloudRadial Lifecycle Sync**, in the AutomationAI
Workflows marketplace. It reads the ScalePad Lifecycle Manager *API* and writes straight
into CloudRadial (endpoints enriched by serial; initiatives and contracts as Planner
items) — no PDF, on a schedule, with a `plan`/`apply` safety gate. Use **this skill** for a
guided, human-in-the-loop one-off build; use **that workflow** for recurring, unattended
sync across a portfolio.

## Before any tool call

Call `setup_status`. If it returns `configured: false`, defer to the `setup` skill.

## What maps natively, and what does not

| Source deliverable section | CloudRadial home | Status |
|---|---|---|
| Roadmap / initiatives | Planner items + Timeline view | Ships today |
| Linked asset appendix | Asset table rendered into the item `body` | Workaround, no native link |
| Machine audit / EOL list | Endpoints + `AgePolicy` / `WarrantyExpirationPolicy` | Ships today |
| Microsoft licenses | Microsoft Licenses report module | Ships today |
| Goals (parent of initiatives) | Planner Category, or an Assessment | No Goal object exists |
| Budget (multi-year, stacked chart) | Planner items priced by line | Partial, no chart |
| Maturity index (DMI) | Assessment score, transparent | Different model, see below |

State the gaps out loud. A partner who discovers the missing budget chart during
their own QBR loses more trust than one who was told up front.

## Build sequence

### 1. Resolve the target company

`search_companies` with the name fragment. Confirm the `companyId` before writing.

Watch for `companyId: 1`. In most portals that is the **partner's own** company record,
which also holds the Planner template library. If the user names their partner tenant
("build this in my trial"), confirm whether they mean the partner record or a client
company beneath it. Building a client deliverable on the partner record works, but it
mixes deliverable items into the template library.

### 2. Read what already exists

Never write blind.

- `list_resources` `product` filtered `companyId eq {id}` — existing Planner items and
  the category names in use
- `list_resources` `endpoint` filtered `companyId eq {id}` — the asset inventory
- `count_resources` on both for scale

Report what is already there and ask before touching it. Adding alongside is the safe
default; deactivating (`isActive: false`) is reversible; deleting is not.

### 3. Assess the endpoint data before promising a roadmap

Endpoint records vary enormously in completeness. RMM-fed and agent-fed rows carry
serials and warranty dates; Signal-only and discovered rows often carry nothing but a
name and an OS string.

Count how many endpoints have a usable `serialNumber` and `expirationDate` before
designing cohorts. If most rows are empty, say so and offer the honest options:
build a thin roadmap off real data, or mirror the source deliverable's structure with
representative data for demo purposes. Do not silently invent asset detail.

Fields that justify a refresh recommendation, all verified present on the live entity:

| Field | Use |
|---|---|
| `expirationDate` | Warranty or EOL date. Past date is the strongest signal. |
| `cpuDate`, `biosDate` | Derive platform age when no purchase date exists |
| `os`, `osVersion` | Operating system end-of-support exposure |
| `windows11Readiness` | `NotReady` is a hardware-bound refresh driver |
| `lastCheckIn` | A device silent for a year is a data-hygiene finding |
| `manufacturer`, `model`, `serialNumber` | The appendix table columns |
| `isEncrypted`, `antiVirus`, `tpmVersion` | Security posture, feeds Policies |

Note the field names differ from some older docs: the entity uses
`companyEndpointId`, `expirationDate`, and `os` — not `endpointId`,
`warrantyExpirationDate`, or `operatingSystem`.

### 3b. Sync ScalePad asset/EOL data into the endpoints (Lifecycle Manager imports)

When the source is a ScalePad Lifecycle Manager PDF, do not stop at a table in the report
body. ScalePad holds EOL dates, serials, and models the portal often lacks — write them
onto the real endpoints so they drive `WarrantyExpirationPolicy` and future reports.

Match each asset to an endpoint by `serialNumber`; enrich the match (write the missing
`expirationDate`, never clobber RMM-supplied fields) or, with the operator's confirmation,
create a tagged placeholder endpoint for assets not yet in the portal. `expirationDate` is
directly writable — use `update_resource` / `create_resource`, **not**
`endpoint_update_warranty` (that does an async manufacturer lookup and ignores the ScalePad
date). Rows with no serial cannot be safely matched or created — skip them.

Full field map, match/update/create mechanics, required-field caveats, and the
`pdftotext` extraction recipe:
`${CLAUDE_PLUGIN_ROOT}/skills/client-deliverable/references/scalepad-lifecycle-mapping.md`.

### 4. Create Planner Categories if the deliverable needs its own grouping

Stock portals ship the IT Foundation set (Decision Making, Collaboration, Productivity,
Compliance, Continuity, Security, Efficiency). A budget page reads better grouped as
Hardware Refresh / Contracts / Initiatives.

Categories have no standalone endpoint and no OData listing, but `create_resource`
`product` accepts a `categoryData` object that creates one inline:

```json
{ "categoryData": { "name": "Hardware Refresh", "order": 10, "color": "#1F6FEB" } }
```

Omit `productCategoryId` to create; supply it to update. Create the category on the
first item that needs it, then reuse the returned `productCategoryId` on the rest.

### 5. Create the roadmap initiatives

One Planner item per initiative. See
`${CLAUDE_PLUGIN_ROOT}/skills/client-deliverable/references/planner-item-schema.md`
for the full field map, enum values, and verified write quirks.

The essentials:

- `subject`, `body`, `summary`, `category` and `productCategoryId` are all required on create
- `productType: 2` plus `estimatedStartDate` and `estimatedEndDate` puts the item on the Timeline
- `productType: 0` means Not Scheduled — the right home for an overdue backlog that has
  recognised budget but no agreed date
- `projectUnits` x `projectUnitPrice` is one-time investment; `monthlyUnits` x
  `monthlyUnitPrice` is recurring
- `isClientVisible: true` and `isShowPrice: true` or the client sees nothing

Render the linked-asset appendix as an HTML table inside `body`. There is no planner-item
to endpoint foreign key, so the table is the only way to carry serials and reasons into
the report. Always include a per-row **reason** column citing the actual field that
triggered the recommendation ("Warranty expired 24 Jun 2025", not "old").

### 6. Create the budget lines

Recurring contracts and licence lines become Planner items with `monthlyUnitPrice` set,
`status: "Completed"` and `currentlyInstalled: true` so they read as active spend rather
than proposals.

Where a contract bills annually, either divide to a monthly equivalent so quarterly
totals behave, or place the full amount in the renewal quarter. State which convention
was used in the item `body` so the number is defensible in the meeting.

`monthlyUnitCost` and `projectUnitCost` are partner-internal and never shown to clients.
Populate them if the partner wants margin visible in their own exports.

### 7. Build the Report Layout — UI only

`/api/partner/layout` is not exposed on the public v2 API. Confirm this rather than
guessing, then hand the user exact clicks:

> Settings → Report Layouts → new layout → tick modules → save.
> Generate at Clients → open the company → Print/Generate report.

The module catalog, verified in code:

Cover page · Table of contents · Users · **Account Review** · **Account Plan** ·
**Account Plan (list)** · Policy Review · Infrastructure Review · Endpoints (summary) ·
Endpoints (detail) · Servers (summary) · Servers (detail) · Software · Domains ·
Certificates · **Microsoft Licenses** · Product literature · Category literature ·
Feedback · Notes

Account Plan and Account Review pull from the Planner. Ticking those plus Endpoints
(detail) and Microsoft Licenses puts roadmap, machine audit, and licensing in one PDF.

Set "Is client visible" so the layout also appears under Account → Reports in the
client's standing portal. That persistence is the competitive advantage over a
per-QBR shared link, so call it out.

### 8. Verify and total

Re-read the created items with `list_resources` and compute the totals yourself rather
than trusting the intended values. Report project total, monthly recurring, quarterly
and annual figures.

## Mapping a DMI or maturity score

When asked how a competitor's headline number translates, read
`${CLAUDE_PLUGIN_ROOT}/skills/client-deliverable/references/scoring-mapping.md`.

The short version, and do not overstate it:

- ScalePad's **Digital Maturity Index** is an opaque proprietary 300 to 850 scale,
  higher is better. It is deliberately not a transparent percentage.
- CloudRadial has **no single equivalent index**. It has two scores with opposite
  polarity: assessment scores where higher is better, and policy risk scores where
  higher is worse.
- The honest analog is the **assessment score**: answers weight Compliant +2,
  PartiallyCompliant +1, NA 0, Missing -1, NotCompliant -2. Every non-NA question adds
  2 to `maxScore`; NA questions leave the denominator. `totalScore / maxScore` is the
  posture number. Negative totals are possible and do occur in real data.
- The differentiator to press is **explainability**. Every DMI point is a black box;
  every assessment point traces to a named question with a priced remediation line.
- Do **not** promise a blended posture number or a 0 to 100 policy score. Neither ships.

## Report honestly

Close every build with what was created, what was skipped, and what could not be verified.
If a claim could not be confirmed against the API or the portal, say which check was run
and that it came back inconclusive. A guessed detail in a client-facing deliverable
surfaces in front of the partner's customer.

## API Reference

Full field and schema detail: `${CLAUDE_PLUGIN_ROOT}/references/api-reference.md`.
