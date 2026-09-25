# ScalePad Lifecycle Manager → CloudRadial — Migration & Alignment Map

**Purpose.** One reference for moving ScalePad Lifecycle Manager (the QBR-prep engine) into CloudRadial's native QBR surface. It serves two audiences:

1. **People** — the team map for what moves where, by which route, and what won't move.
2. **The alignment agent** — upload this file to an AutomationAI **Knowledge** folder and ground the *ScalePad → CloudRadial Alignment* workflow's agent node on it. Every field-level decision the agent makes should trace back to a row here.

Verified against the CloudRadial v2 OpenAPI spec (`api.us.cloudradial.com/swagger/v2/swagger.json`) and the legacy v1 spec, the ScalePad API reference (`developer.scalepad.com`), and support.cloudradial.com — last checked **2026-09-25**. Anything unconfirmed is marked **[verify]**.

---

## 1. The three-layer mental model

CloudRadial has three distinct layers, and only one of them is API-writable. Getting this right is the whole game:

| Layer | API-reachable? | What lives here |
|---|---|---|
| **Data** | ✅ Full CRUD | Endpoints, endpoint applications, custom-properties, flexible assets, domains, certificates, services, Planner items, assessments (via Excel upload), media, archive items |
| **Evaluation** (Compliance Policies) | ❌ No API surface | Policies run server-side over the *data* layer. No `/policy` route exists. Policy **definitions** travel as content-package ZIPs; policy **results** are read only via the Policy Review report, the Compliance > Policies dashboard, or the daily policy email |
| **Presentation** | Mixed | Report Layouts (UI-defined), Report Archives (API + email + drag-drop), flexible-asset grids under Infrastructure |

**Rule of thumb for every ScalePad field:**
- Want it **scored / compliance-graded**? → write it to the **endpoint** field the built-in policy check already reads. Nothing else is policy-evaluable.
- Want it **just displayed / documented**? → flexible asset or custom-property.
- It's a **judgment call / roadmap**? → Planner item or Assessment.

---

## 2. Where the data comes from in ScalePad

Everything below is reachable through the ScalePad API — no exports or files. Every list endpoint returns `{ data, total_count, next_cursor }` and is **cursor-paged** (`page_size` 1–200, then pass `cursor`). A reader that stops after the first page silently loses data — that's why earlier migrations landed only one device.

| ScalePad data | Endpoint | Key fields |
|---|---|---|
| Hardware (workstations, servers, VMs) | `GET /core/v1/assets/hardware` (`filter[client.id]`, `filter[type]`) | `name`, `serial_number`, **`type`** (`WORKSTATION`, `SERVER`, `VIRTUAL`, `NETWORK`, `MOBILE`, `IMAGING`), `manufacturer.name`, `model.description`, `software.operating_system`, `configuration.cpu.name`, `configuration.ram_bytes`, `software.antivirus_info.status` |
| Warranty and purchase dates | `GET /lifecycle-manager/v1/assets/hardware/lifecycles` (`filter[client_id]`) | `serial_number`, `purchase_date`, `warranty_expiry_date`, `manufacturer_expiry_date` |
| Installed software (per device) | `GET /lifecycle-manager/v1/assets/software` (`filter[client.id]`, `filter[hardware_asset.id]`) | `hardware_asset.serial_number`, `product.name`, `product.category`, `publisher.name`, `version.display` |
| Assessments | `GET /lifecycle-manager/v1/assessments`, `GET /lifecycle-manager/v1/assessments/{id}` | categories → questions → criteria (`is_selected` = the answer), comments, remediation tips, linked initiatives |
| Answer labels | `GET /lifecycle-manager/v1/assessments/criteria/labels` | `label_key` → display label |
| Initiatives (roadmap + budget) | `GET /lifecycle-manager/v2/initiatives`, `GET /lifecycle-manager/v1/initiatives/{id}` | `name`, `status`, `priority`, `fiscal_quarter`, `budget.line_items` / `recurring_line_items` (`cost_subunits`, `unit_count`, `frequency`), `budget.currency`, `executive_summary` |
| Contracts | `GET /core/v1/service/contracts` | `name`, `type`, `status`, `term`, `total_price` |
| QBR / vCIO deliverables | `GET /lifecycle-manager/v1/deliverables`, `GET /lifecycle-manager/v1/deliverables/{id}/pdf` | `name`, `created_at`; the PDF itself |

---

## 3. Section-by-section map

| ScalePad data | CloudRadial home | API route | Policy-evaluable? |
|---|---|---|---|
| Warranty expiry | Endpoint `expirationDate` | `PATCH /v2/endpoint/id/{companyEndpointId}` | ✅ **Warranty Coverage** |
| Purchase date | Endpoint `manufacturedDate` (only when blank) | same | ✅ Device age — Past Endpoint Lifecycle, Endpoint LifeCycle Manager |
| Serial / model / manufacturer | Endpoint `serialNumber` / `model` / `manufacturer` | same | Via lifecycle checks |
| **Servers** (`type` = `SERVER`) | Endpoint with `isServer = true`, `enclosure = 80` (Server) | `POST /v2/endpoint` or `PATCH` | ✅ Server policies; shows on the Servers tab |
| Virtual machines (`type` = `VIRTUAL`) | Endpoint with `isVirtual = true`, `enclosure = 30` | same | ✅ |
| Workstations (`type` = `WORKSTATION`) | Endpoint, `enclosure = 10` (Laptop) or `20` (Desktop) from the model | same | ✅ |
| OS / CPU / RAM | Endpoint `os` / `cpu` / `memory` (bytes) | same | ✅ Current OS Version, Old Technology (from `cpu`), System Memory |
| Antivirus running | Endpoint `isWindowsDefenderRunning` (on create, Windows only) | same | ✅ |
| Other per-asset extras | Endpoint **custom-property** | `POST /v2/endpoint/{serialNumber}/custom-property` | ❌ |
| Installed software | `endpointapplication` (one per product per device) | `POST /v2/endpointapplication` | ✅ Software Installed / Not |
| Initiatives | Planner items, `productType = 1`, `scheduledQuarter` = Nth upcoming quarter (`-1` = completed) | `POST` / `PATCH /v2/product` | n/a |
| Initiative budget | Priced Planner items — one-time → `projectUnitPrice`, recurring → `monthlyUnitPrice` | same | n/a |
| Contracts | Planner items (or `service` + `serviceinstall`) | `/v2/product` | Partial |
| Assessments | CloudRadial assessment | `POST /v2/assessment` then `POST /v2/assessment/upload` (Excel) | Its own scoring model |
| Documentation assets (IT Glue) | **Flexible asset** | `/compatibility/*` (IT Glue-shaped) or `/v2/flexible-asset*` | ❌ Display only |
| SSL certs / domains | `certificate` / `domain` | `POST /v2/certificate`, `/v2/domain` | ✅ Certificate / Domain Expiration |
| QBR / deliverable PDFs | **Report Archive** | `POST /api/beta/archive/{archiveId}/item`, or email to the archive's inbound address | n/a |

---

## 4. Endpoint sync — the core write (field map)

Match each ScalePad hardware asset to a CloudRadial endpoint **by serial** (trimmed, case-insensitive). Enrich the ones that exist; create the ones that don't.

| ScalePad | Endpoint field | Rule |
|---|---|---|
| `serial_number` | `serialNumber` | **Match key.** Skip rows with no serial — never invent one |
| `name` | `name` (required), `machineName` | |
| `type` | `isServer`, `isVirtual`, `enclosure` | `SERVER` → server, enclosure 80; `VIRTUAL` → VM, enclosure 30; `WORKSTATION` → laptop (10) or desktop (20) from the model name. `NETWORK`, `MOBILE`, `IMAGING` aren't endpoints — skip and report |
| `manufacturer.name` | `manufacturer` | Only if blank |
| `model.description` | `model` | Only if blank |
| `software.operating_system` | `os`, and `platformType` on create | Only if blank. Platform: Windows 0, macOS 1, Linux 2 — from the OS text, else Apple → macOS, else Windows |
| `configuration.cpu.name` | `cpu` | Only if blank |
| `configuration.ram_bytes` | `memory` | Only if blank or 0 |
| `warranty_expiry_date` | `expirationDate` | **The high-value write.** Fill when blank; when it differs, report it and only overwrite if the operator allows it |
| `purchase_date` | `manufacturedDate` | Only if blank — CloudRadial ages the device from it |
| — | `tagNumber` | `ScalePad` on devices created from ScalePad, so they can be found later |

**Critical mechanics:**
- Write `expirationDate` **directly**. Never use `update-warranty` — it triggers an asynchronous manufacturer lookup and can overwrite the ScalePad date.
- **Enrich, don't clobber.** Read the endpoint first; write only fields the portal is missing. Never overwrite RMM-supplied values.
- Creating an endpoint needs `companyId`, `name`, `platformType`, `enclosure`, `isWindowsDefenderRunning`, `lastCheckIn`, `lastOSUpdate`. Set both dates to the sync date for devices that come only from ScalePad.
- Devices created from ScalePad have no RMM agent until one is deployed — they show ScalePad's data, not live telemetry.

---

## 5. Installed software

Each ScalePad software record names the device by serial, so software follows the devices: sync devices first, then write one `endpointapplication` per product per device.

| ScalePad | `endpointapplication` field |
|---|---|
| `hardware_asset.serial_number` | `endpointId` (the matched `companyEndpointId`) |
| `product.name` | `name` |
| `publisher.name` | `publisher` (required — `Unknown` when blank) |
| `version.display` | `display`, and `major` / `minor` / `version` parsed from it |
| `product.category` | `category` |

Skip a product that's already on that endpoint (same name and publisher). Large clients can have thousands of records — cap the writes per run and resume on the next run.

---

## 6. Assessments — converting to CloudRadial's Excel import

CloudRadial imports assessments only from Excel (support KB 360052746791, *Importing Assessments*). The file can be built in memory by the workflow — no storage needed.

1. Create the assessment: `POST /v2/assessment` with `companyId`, `title`, `category`, `description` → `assessmentId`. (Not in the published v2 spec, but used by the Microsoft Security Assessment workflow.)
2. Upload the questions: `POST /v2/assessment/upload`, multipart — part `data` = `{ name, assessmentId, type, companyId }` JSON, part `file` = the `.xlsx` (content type `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`). **[verify]** the meaning of `type` (0 is used).

| CloudRadial column | From ScalePad |
|---|---|
| **Category** (required) | Category title, prefixed `1.`, `2.` … (CloudRadial sorts categories alphabetically) |
| **Question** (required) | Question title |
| **Order** (required) | Position × 10 |
| **Type** (required) | `List` |
| **Responses** (required) | Answer labels with CloudRadial's scoring suffixes: none = Compliant, `+` = Partial, `=` = N/A, `*` = Missing, `-` = Not compliant |
| **Answer** / **Text Answer** (required) | The selected criterion → +2 Compliant, +1 Partially Compliant, 0 N/A, −2 Not compliant; nothing selected → −1 Missing answer |
| Explanation | Question description |
| Evaluation | Scoring instructions |
| Remediation / Remediation Summary | Remediation tips / their first sentence |
| Notes / Partner Notes | Public comment / internal comment |
| Reference | Linked initiative names |
| Is Flagged | `Yes` when not compliant |

**Scoring a ScalePad answer:** read the label from the criterion (or `/assessments/criteria/labels`). Yes / Satisfactory / Compliant → +2; Partial / Needs attention → +1; Not applicable → 0; Unanswered / Unknown → −1; No / At risk / Not compliant → −2. An MSP can override this per label.

---

## 7. Report Archive — QBR PDFs

- The v2 `POST /v2/archiveitem` creates **text/HTML items only** — it has no attachment upload.
- The legacy API lists a company's archives with their **`inboundAddress`** (`GET /api/beta/archive`), creates an archive (`POST /api/beta/archive`), and has an item route (`POST /api/beta/archive/{archiveId}/item`) that accepts files up to 128 MB **[verify the request body]**.
- Fallback: email the PDF to the archive's inbound address (limit 20 MB via email). The workflow sends it through Postmark with the PDF attached.
- Source: download each deliverable with `GET /lifecycle-manager/v1/deliverables/{id}/pdf`, in the same step that uploads it.

---

## 8. Flexible assets — the IT Glue bridge

CloudRadial ships an **IT Glue-compatible** flexible-asset API (`/compatibility/*`, JSON:API shape, kebab-case keys) plus the native `/v2/flexible-asset`, `/v2/flexible-asset-type`, `/v2/flexible-asset-field`. Both are full API routes.

- **Existing tooling:** *Syncing IT Glue Flexible Assets to CloudRadial with PowerShell* (support KB 49183488579860) — reads IT Glue asset types and data and recreates them via the compatible API, with a `-WhatIf` dry run.
- **Display only.** Flexible assets appear under Infrastructure; an `expiration` field highlights rows *within the asset view* but does **not** feed the Compliance Policy engine.

---

## 9. Policy layer — read this before touching policies

- There is **no policy API**. You cannot create, read, update, or score policies through v2.
- The **only lever** is writing the endpoint and infrastructure fields the built-in checks read:

| Policy check | Endpoint input to write |
|---|---|
| Warranty Coverage | `expirationDate` |
| Encrypted Hard Drive | `isEncrypted` |
| Current OS Version / Recent OS Updates | `os` / `osVersion` / `lastOSUpdate` |
| Antivirus Installed / Vendor | `antiVirus` |
| System Memory | `memory` |
| Managed by Intune | `isIntune` |
| Old Technology | `cpu` (release date derived server-side) |
| Past Endpoint Lifecycle | `manufacturedDate` **[verify]** |
| Software Installed / Not | `endpointapplication` records |
| Domain / Certificate Expiration | `domain.dateExpires` / `certificate.expirationDate` |

- Policy **definitions** migrate as **content-package ZIPs** (Partner > Content > Import).
- Policy **results** come out via the Policy Review report, the Compliance > Policies dashboard, or the daily policy email forwarded to a Report Archive.

---

## 10. Runner storage and files

- Everything in this map is API-to-API. The runner downloads and uploads in the same step (the Function's temporary disk), so nothing needs to be stored.
- The runner's own storage account is private runtime storage for the Function Apps — not a shared file area. Operator-supplied files (anything ScalePad has no API for) need an external location such as a blob with a SAS URL.

---

## 11. Guardrails (encode these in every automation)

1. **Follow every page** of every ScalePad list (`next_cursor` until empty).
2. Match endpoints by serial; **skip rows with no serial**.
3. **Enrich, don't clobber** — read first, write only missing fields, never overwrite RMM data.
4. Write `expirationDate` directly; never `update-warranty` for a ScalePad date.
5. **Plan before apply** — the first run is a plan with counts; writes happen only in apply.
6. Tag devices created from ScalePad (`tagNumber = ScalePad`) and separate servers and VMs by ScalePad's `type`.
7. Do **not** attempt to configure policies — only write policy-input fields, and report which policies the writes affect.
8. Confirm the portal **currency** before relying on prices — CloudRadial stores the number only.
9. Close every run with counts: matched, enriched, created, skipped (with reasons), errors.

---

## 12. Automation vehicles (AutomationAI)

- **Workflow — *ScalePad to CloudRadial Sync*** (`automationai/scalepad-cloudradial-sync/`). The deterministic bulk transfer, in phases: devices → software → assessments → roadmap and budget → archive. Follows every page, `plan` / `apply`, counts per phase.
- **Extension — `lifecycle-manager` 1.2.0** (`automationai/scalepad-lifecycle-manager-extension/`). Every list tool pages automatically; adds installed software, assessments and deliverables for agents.
- **Agent — *ScalePad to CloudRadial Alignment*.** The judgment: matching clients, reviewing a plan, the long tail the workflow reports as skipped or unmatched. Grounded on this document. It doesn't bulk-write.
- **Playbook** (future) — recurring, portfolio-wide: sync workflow (plan) → agent review → human approval → sync workflow (apply), with learnings written back to Knowledge.
