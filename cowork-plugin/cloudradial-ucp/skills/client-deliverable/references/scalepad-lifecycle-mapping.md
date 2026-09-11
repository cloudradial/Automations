# ScalePad Lifecycle Manager → CloudRadial

How to turn a **ScalePad Lifecycle Manager X** (formerly Lifecycle Insights) client
deliverable PDF into CloudRadial data: Planner roadmap, priced budget, and — the part
ScalePad hides from the portal — the **asset/EOL data written onto the actual
endpoints** via the API.

This reference was written against a real export (`Deliverable-KMCO Group Ltd`, 213
users, 45 assets, GBP). Field names and section shapes below are from that document.
Not every ScalePad export carries every section — this one had **no DMI/maturity page
and no Microsoft-licenses page**, it is a hardware-lifecycle + budget deliverable. For
the maturity-score question see `scoring-mapping.md`; for the Planner write mechanics
see `planner-item-schema.md`. This file does not repeat those.

## Reading the PDF

There is no PDF-ingest tool. Extract the text yourself, then map:

```bash
pdftotext -layout "Deliverable-<Company>.pdf" out.txt
```

`-layout` preserves the tables well enough to read serials, models, EOL dates and
budget lines. Two known extraction artifacts, both harmless if you know them:

- The `£` glyph often comes through as a replacement character. It is GBP; confirm the
  portal's currency before writing prices.
- In the per-quarter **budget** hardware tables, a serial number can land one text row
  above or below its asset name. Cross-check a suspicious row against the **Appendix
  (linked assets)** section, which lists the same asset cleanly. When the two disagree,
  trust the Appendix.

If a row still can't be resolved from text, render that one page to an image to read it
— do not guess a serial. A wrong serial writes EOL data onto the wrong device.

## Section map

| ScalePad section | Contains | CloudRadial home |
|---|---|---|
| Overview | User count, asset count, open-initiative count, account team | Context only — read with `count_resources` |
| Goals | Named goals with a target period (e.g. "Cyber Essentials Certification", H1 2026) | Planner **Category**, or an **Assessment**. No Goal object — see `client-deliverable` SKILL |
| Roadmap | Initiatives per quarter, each with a narrative, asset count, investment, status | Planner **items** (`product`) — `planner-item-schema.md` |
| Appendix (linked assets) | Per initiative: asset Name, Model, Serial, Purchased date | `body` asset table **and** endpoint sync (below) |
| Budget | Per quarter, split **Hardware / Initiatives / Contracts**, plus an **Overdue** bucket | Planner items priced per line; **no native chart** |

### Roadmap initiatives → Planner items

One `product` per initiative. From the KMCO export:

| ScalePad field | Planner (`product`) field | KMCO example |
|---|---|---|
| Initiative name | `subject` | `Workstation Replacement Q1` |
| Narrative paragraph | `body` (prepend to the asset table) | "…workstations that have reached the end of their useful life…" |
| Status `PROPOSED` / `OPEN` | `status` string | `Proposed` / `In_Progress` (see `planner-item-schema.md`) |
| Quarter (Q1 2026) | `productType: 2` + `estimatedStartDate`/`estimatedEndDate` at quarter bounds | Q1 → `2026-01-01`…`2026-03-31` |
| Investment (£6,775.00) | `projectUnits: 1`, `projectUnitPrice: 6775` | one-time |
| Asset count (5 assets) | length of the `body` table | 5 |

Set `isClientVisible: true` and `isShowPrice: true` or the client sees nothing.

### Budget → Planner items

- **Hardware** lines (one asset each, e.g. `KMCO-LT46 … £1,000.00`) → Planner items in a
  `Hardware Refresh` category, one-time `projectUnitPrice`. In KMCO every workstation is
  budgeted at £1,000.
- **Initiatives** lines repeat the roadmap initiatives — map them once, do not
  double-count.
- **Contracts** lines (`KMC001 Elevate Support … Active … £11,375.04`, M365, Exchange
  Online, etc.) → Planner items with `monthlyUnitPrice`, `status: "Completed"` and
  `currentlyInstalled: true` so they read as active spend, not proposals. Where ScalePad
  shows an annual figure, divide to a monthly equivalent or place the full amount in the
  renewal quarter, and state which convention you used in `body`.
- The **Overdue** bucket (KMCO: 13 workstations, £13,000) → `productType: 0` (Not
  Scheduled): recognised budget, no agreed date.
- The stacked budget **chart** does not reproduce — CloudRadial has no multi-year budget
  chart. Say so; report the quarter totals instead (KMCO: Q1 £27,670 · Q2 £27,709 ·
  Q3 £24,709 · Q4 £18,649 · Q1'27 £17,498 · Overdue £13,000).

## Endpoint sync — the part ScalePad keeps in the PDF

ScalePad computes an **EOL date** and holds serial/model/manufacturer/purchase data that
is frequently **absent from the CloudRadial endpoint** (Signal-only and discovered rows
carry little; even RMM rows often lack a warranty/EOL date). The value here is writing
that data back onto the real endpoints so it drives `WarrantyExpirationPolicy`, refresh
cohorts, and future reports — not just a static table in a report body.

`expirationDate` **is a writable field on the `Endpoint` body**, so ScalePad's EOL date
can be written directly. Do **not** use `endpoint_update_warranty` for this — that tool
triggers an async *manufacturer* lookup and will ignore (and can overwrite) the ScalePad
date. Write `expirationDate` yourself.

### Field map: ScalePad asset → `Endpoint`

| ScalePad column | `Endpoint` field | Notes |
|---|---|---|
| Serial Number (`PF2LY0BX`) | `serialNumber` | **Match key.** Skip rows with no serial |
| Name (`KMCO-LT04`) | `name` (required), `machineName` | |
| Manufacturer (`Lenovo`) | `manufacturer` | |
| Model (`E15 Gen 4 … Type 21ED`) | `model` | |
| EOL (`2024-03-02`) | `expirationDate` | The high-value write |
| Purchased (`29/07/2021`) | — no native purchase field | Store as a custom property (e.g. `ScalePad Purchase Date`) or leave; do **not** shoehorn into `manufacturedDate` |
| Age (`3.5`) | — derived, do not write | CloudRadial derives age from `cpuDate`/`biosDate` |

### Match, then update or create

For each asset row **that has a serial**:

1. **Find it.** `list_resources` `endpoint`, filter
   `companyId eq {id} and serialNumber eq '{serial}'`. Serials are case-sensitive in the
   data; match exactly.
2. **If found → enrich, don't clobber.** Read the row first. Only write fields the portal
   is missing (almost always `expirationDate`; add `manufacturer`/`model` only if blank —
   never overwrite RMM-supplied values with ScalePad's). Use the shipped tool:
   `update_resource` `endpoint`, `method: "PATCH"`, `id: {companyEndpointId}`,
   `data: { "expirationDate": "2024-03-02" }`. (`update_resource` addresses endpoints by
   their internal `companyEndpointId` at `/v2/endpoint/id/{id}` and converts the partial
   object to a JSON-Patch document for you.) To address by serial directly instead, use
   `raw_api_call` `PATCH /v2/endpoint/{serial}` with a JSON-Patch array.
3. **If not found → decide before creating.** A ScalePad asset absent from the portal is
   an unmanaged device (no agent). `create_resource` `endpoint` POSTs to `/v2/endpoint`,
   but the `Endpoint` body **requires** fields ScalePad does not provide: `companyId`,
   `name`, `platformType` (`EndpointPlatformType`), `enclosure` (`EnclosureType`),
   `isWindowsDefenderRunning`, `lastOSUpdate`, `lastCheckIn`. You must synthesize those.
   Recommended: only the operator's call — confirm before bulk-creating, tag created rows
   (`tagNumber` or a custom property `Source = ScalePad`) so they are distinguishable from
   RMM-managed endpoints, and set `lastCheckIn`/`lastOSUpdate` to the extract date, not a
   fake recent one. Look up the integer for laptop `enclosure` and Windows `platformType`
   in the **Enumerations** section of `${CLAUDE_PLUGIN_ROOT}/references/api-reference.md`
   and confirm it against a real endpoint in the portal before writing — this file does not hard-code
   those codes because the API exposes the values without names.

Rows **without a serial** (KMCO had several: `KMCO-LT52`, `KMCO-LT48`, `KMCO-LT50`,
`KMCO-LT43/44/45`) cannot be safely matched or created. Leave them out of the sync and
render `Not reported` in the report `body` table. Never invent a serial to force a match.

### Order of operations

Sync endpoints **before** building the roadmap `body` tables. Once the endpoints carry
`expirationDate`, the appendix table's Reason column can cite the live field
("Warranty/EOL 02 Mar 2024") and the numbers in the report match what the portal will
show going forward.

## Automating this

This reference is for a guided, human-in-the-loop build from a PDF. To run the same
mapping unattended, use the **ScalePad → CloudRadial Lifecycle Sync** AutomationAI
workflow (AutomationAI Workflows marketplace). It skips the PDF entirely — reading the
ScalePad Lifecycle Manager *API* (`hardware-lifecycles`, `initiatives`, `contracts`) and
writing into CloudRadial via the `cloudradial-v2-endpoints` / `-services` extensions, with
a `plan`/`apply` safety gate and platform approval on every write. Same field map as here;
different trigger. Reach for the workflow when a partner wants recurring, portfolio-wide
sync rather than a one-off deliverable.

## Report honestly

Close with counts, not adjectives: how many assets had serials, how many endpoints were
updated, how many were created (and that they are ScalePad-seeded placeholders), how many
were skipped for missing data, and which sections of the source PDF have **no** CloudRadial
equivalent (the budget chart; the DMI, if the export had one). A partner who finds a
silently-skipped asset during their own QBR loses more trust than one told the count up
front.
