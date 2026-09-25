# ScalePad Lifecycle Manager → CloudRadial — Migration & Alignment Map

**Purpose.** One reference for aligning ScalePad Lifecycle Manager (the QBR-prep engine)
with CloudRadial's native QBR surface. It serves two audiences:

1. **People** — the team map for what moves where, by which route, and what won't move.
2. **The alignment agent** — drop this file into an AutomationAI **Knowledge** folder and
   ground the *ScalePad → CloudRadial Alignment* agent on it. Every field-level decision the
   agent makes should trace back to a row here.

Verified against the live CloudRadial v2 OpenAPI spec (`api.us.cloudradial.com/swagger/v2/swagger.json`)
and support.cloudradial.com on 2026-09-18. Where a detail is unconfirmed it is marked **[verify]**.

---

## 1. The three-layer mental model

CloudRadial has three distinct layers, and only one of them is API-writable. Getting this
right is the whole game:

| Layer | API-reachable? | What lives here |
|---|---|---|
| **Data** | ✅ Full CRUD | Endpoints, endpoint applications, custom-properties, flexible assets, domains, certificates, services, Planner items, assessments (via upload), media, archive items |
| **Evaluation** (Compliance Policies) | ❌ No API surface | Policies run server-side over the *data* layer. No `/policy` route exists. Policy **definitions** travel as content-package ZIPs; policy **results** (red/yellow/green) are read only via the Policy Review report, the Compliance > Policies dashboard, or the daily policy email |
| **Presentation** | Mixed | Report Layouts (UI-defined), Report Archives (API + email + drag-drop), flexible-asset grids under Infrastructure |

**Rule of thumb for every ScalePad field:**
- Want it **scored / compliance-graded**? → write it to the **endpoint** field the built-in
  policy check already reads. Nothing else is policy-evaluable.
- Want it **just displayed / documented**? → flexible asset or custom-property.
- It's a **judgment call / roadmap**? → Planner item or Assessment.

---

## 2. Section-by-section map

| ScalePad Lifecycle Manager section | CloudRadial home | API entity / route | Import route | Policy-evaluable? |
|---|---|---|---|---|
| Hardware EOL / warranty date | Endpoint `expirationDate` | `PATCH /v2/endpoint/{serialNumber}` (or `/id/{id}`) | API | ✅ **Warranty Coverage** policy |
| Serial / model / manufacturer | Endpoint `serialNumber` / `model` / `manufacturer` | `PATCH /v2/endpoint/...` | API | Via age/lifecycle checks |
| Age / lifecycle | Endpoint `cpu`, ship/manufacture date | `PATCH /v2/endpoint/...` | API | ⚠️ **Old Technology** (derived server-side from `cpu` name), **Past Endpoint Lifecycle** (ship date) |
| Purchase date & other per-asset extras (no native field) | Endpoint **custom-property** | `POST /v2/endpoint/{serialNumber}/custom-property` | API | ❌ Not policy-evaluable |
| Installed software inventory | `endpointapplication` | `POST /v2/endpointapplication` | API | ✅ Application/Software policies |
| Managed services / contracts | `service` + `serviceinstall`, or Planner items | `POST /v2/service`, `/v2/serviceinstall`, `/v2/product` | API | Partial |
| Roadmap / initiatives | Planner items | `POST /v2/product` (`productType:2` + start/end = Timeline) | API + content ZIP (templates) | n/a |
| Budget / forecast | Priced Planner items | `POST /v2/product` (`projectUnitPrice`, `monthlyUnitPrice`) | API | n/a (no multi-year chart) |
| Maturity / risk assessment + recommendations | Assessment | `POST /v2/assessment/upload`, `/import-template` (Excel-backed) | Excel / API + content ZIP | Its own scoring model |
| Recommendation → priced plan | Assessment **Estimate of Work** report → Planner | report → `product` | API | n/a |
| Client health / ranking | Account Planner **scoring** (item weights) | `product` `scoring` field | API | n/a |
| Documentation-style custom assets (esp. if in IT Glue) | **Flexible asset** | `/compatibility/*` (IT Glue-shaped) or `/v2/flexible-asset*` (native) | API / PowerShell script | ❌ Display only |
| SSL certs / domains | `certificate` / `domain` | `POST /v2/certificate`, `/v2/domain` | API | ✅ Certificate / Domain Expiration policies |
| Historical QBR PDFs | **Report Archive** | `POST /v2/archiveitem` | API / archive email / drag-drop | n/a |

---

## 3. Endpoint sync — the core write (field map)

Match each ScalePad asset to an endpoint **by serial**, then enrich. This is where ScalePad's
EOL/warranty data becomes policy-driving CloudRadial data.

| ScalePad column | Endpoint field | Notes |
|---|---|---|
| Serial Number | `serialNumber` | **Match key.** Skip rows with no serial — never invent one |
| Name | `name` (required), `machineName` | |
| Manufacturer | `manufacturer` | Only if blank — never overwrite RMM values |
| Model | `model` | Only if blank |
| EOL / warranty | `expirationDate` | **The high-value write.** Drives Warranty Coverage policy |
| Purchased | endpoint **custom-property** `ScalePad Purchase Date` | No native purchase field; do **not** use `manufacturedDate` |
| Age | — | Derived server-side; do not write |

**Critical mechanics:**
- Write `expirationDate` **directly** with `update_resource` / `PATCH`. Do **NOT** use
  `endpoint_update_warranty` / `update-warranty` — that triggers an async *manufacturer*
  lookup and ignores (can overwrite) the ScalePad date.
- **Enrich, don't clobber.** Read the endpoint first; write only fields the portal is missing.
- Endpoints are addressable three ways: `/v2/endpoint/{serialNumber}`,
  `/v2/endpoint/id/{companyEndpointId}`, and `/v2/endpoint/{manufacturer}/{machineName}`.
- Assets absent from the portal are unmanaged. Creating a placeholder endpoint requires
  synthesizing `companyId`, `name`, `platformType`, `enclosure`,
  `isWindowsDefenderRunning`, `lastOSUpdate`, `lastCheckIn` — **operator confirmation only**,
  tag created rows (`Source = ScalePad`), and set check-in dates to the extract date.

---

## 4. Flexible assets — the IT Glue bridge

CloudRadial ships an **IT Glue-compatible** flexible-asset API (`/compatibility/*`, JSON:API
shape: `type` / `attributes` / `relationships` / `traits`, kebab-case keys). Because Lifecycle
Manager lives in the IT Glue ecosystem, this is the natural migration route for any ScalePad
data that sits in IT Glue flexible assets.

- **Existing tooling:** *Syncing IT Glue Flexible Assets to CloudRadial with PowerShell*
  (support KB 49183488579860) — reads IT Glue asset-type definitions + data and recreates
  them in CloudRadial via the compatible API, CSV-mapped org→company, `-WhatIf` dry run,
  `-FlexibleAssetTypeFilter`, EU/AU base-URL support.
- **Native alternative:** `/v2/flexible-asset`, `/v2/flexible-asset-type`,
  `/v2/flexible-asset-field` for data not coming from IT Glue.
- **Display only.** Flexible assets appear under Infrastructure (grid + detail, searchable).
  A field can carry an `expiration` type that highlights expiring rows *within the asset view*,
  but this does **not** feed the Compliance Policy engine. Never store something in a flexible
  asset expecting a policy to grade it.

---

## 5. Policy layer — read this before touching policies

- There is **no policy API**. You cannot create, read, update, or score policies through v2.
  (`policyPaths: []`, `opHits: []`; the only "policy" schema is `EndpointAuditPolicy`, which is
  Windows audit telemetry on the endpoint, not the compliance engine.)
- The **only lever** is writing the endpoint/infrastructure fields the built-in checks read:

| Policy check | Endpoint input to write |
|---|---|
| Warranty Coverage | `expirationDate` |
| Encrypted Hard Drive | `isEncrypted` |
| Current OS Version / Recent OS Updates | `os` / `osVersion` / `lastOSUpdate` |
| Antivirus Installed / Vendor | `antiVirus` |
| System Memory | `memory` |
| Managed by Intune | `isIntune` |
| Old Technology | `cpu` (release date derived server-side) |
| Past Endpoint Lifecycle | ship/manufacture date **[verify exact field, likely `manufacturedDate`]** |
| Software Installed / Not | via `endpointapplication` records |
| Domain / Certificate Expiration | `domain.dateExpires` / `certificate.expirationDate` |

- Policy **definitions** migrate as **content-package ZIPs** (Partner > Content > Import),
  not via API. Sample packages: Endpoint, Server, Application, and Domain/License/User policies.
- Policy **results** come back out via the Policy Review report module, the Compliance > Policies
  dashboard (with By-Category roll-up), or the daily policy email forwarded to a Report Archive.

---

## 6. Guardrails (encode these in every automation)

1. Match endpoints by serial; **skip rows with no serial**.
2. **Enrich, don't clobber** — read first, write only missing fields, never overwrite RMM data.
3. Write `expirationDate` directly; never `update-warranty` for a ScalePad date.
4. **Plan before apply** — produce a diff, require human approval before writing.
5. Placeholder-endpoint creation is **operator-confirmed only**, tagged `Source = ScalePad`.
6. Do **not** attempt to configure policies (no API) — only write policy-input fields, and
   report which policies the writes will affect.
7. Confirm portal **currency** before writing prices (ScalePad exports vary; £ often mis-extracts).
8. Close every run with counts: matched, enriched, created, skipped (with reasons), unmapped.

---

## 7. Automation vehicles (AutomationAI)

- **Workflow** — the deterministic writes (endpoint enrich, flexible-asset create,
  `endpointapplication`, `archiveitem`, assessment upload). Testable, `plan`/`apply`, logged.
  Extend the existing *ScalePad → CloudRadial Lifecycle Sync* workflow rather than starting over.
- **Agent** — the judgment (mapping, cohorts, enrich-vs-create, the messy long tail). Grounded
  on this document. See `scalepad-cloudradial-alignment-agent.yaml`.
- **Playbook** — recurring, portfolio-wide orchestration: sync workflow → agent → human approval,
  on a schedule, with a spend cap; learnings written back to Knowledge.
