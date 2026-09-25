# ScalePad to CloudRadial Sync

A deterministic **workflow** that moves a client's ScalePad Lifecycle Manager data into CloudRadial — API to API, following every ScalePad page, with nothing stored in between. It's the bulk half of a ScalePad migration; the [ScalePad to CloudRadial Alignment](../scalepad-cloudradial-alignment/) agent handles the judgment calls.

## Pieces

| File | Type | Role |
|---|---|---|
| [`scalepad-cloudradial-sync.yml`](scalepad-cloudradial-sync.yml) | `automationsWorkflow` | Eight PowerShell steps: resolve the client → devices → other hardware to flexible assets → installed software → assessments → roadmap and budget → deliverable PDFs → migration report. Each step is self-contained (the shared helper block is repeated in each). |

## What it moves

| Phase | From ScalePad | To CloudRadial |
|---|---|---|
| `devices` | Core hardware (workstations, servers, VMs) + lifecycle records | Endpoints matched by serial. Existing ones get their blanks filled: warranty → `expirationDate`, purchase date → `manufacturedDate`, model, manufacturer, OS, CPU, RAM. Missing ones are created — servers as `isServer` / enclosure Server, VMs as `isVirtual`, tagged `ScalePad`. Network, mobile and imaging devices, and devices with no serial, go to the `assets` phase instead. |
| `assets` | Other hardware: types `NETWORK`, `MOBILE`, `IMAGING`, plus workstations, servers and VMs with no serial number | Rows of one flexible asset type, **ScalePad Assets** (Infrastructure), created with its fields if missing: name, type, manufacturer, model, serial, warranty and purchase dates, location, assigned user and the ScalePad id. Matched on the ScalePad id, so re-runs update the row. |
| `software` | Installed software per device | One endpoint application per product per device (name, publisher, version). |
| `assessments` | Completed assessments, full question tree | A CloudRadial assessment per ScalePad assessment, imported from an `.xlsx` built in memory in the layout from *Importing Assessments* (support KB 360052746791). Answers are scored +2 / +1 / 0 / −1 / −2. |
| `roadmap` | Initiatives (with budget and fiscal quarter) and contracts | Planner cards `ScalePad Initiative - <name>` / `ScalePad Contract - <name>` — updated if they exist. One-time budget → project price, recurring → monthly price, status and priority mapped, quarter placed on the roadmap. |
| `archive` | Deliverable PDFs | The company's **ScalePad QBR History** report archive (created if missing), uploaded through the archive API. Any PDF the upload route rejects is listed in the migration report for a manual upload. |
| _report_ | — | In apply mode, a **migration report** written into the portal: an HTML item in the company's **ScalePad Migration** report archive (Compliance > Reports), or a knowledge base article if the archive can't be written. It lists what moved per area, what needs attention, and any warnings. |

Every phase is idempotent: re-running updates or skips what's already there. No email or outside service is involved — the result is visible in the portal itself.

## Install / run

1. **Workflows → Import** `scalepad-cloudradial-sync.yml`, publish, and deploy to your runner.
2. **Runner Key Vault secrets:** `ScalePad-ApiUrl` (e.g. `https://api.scalepad.com`), `ScalePad-ApiKey`, `CloudRadial-BaseUrl` (e.g. `https://api.us.cloudradial.com`), `CloudRadial-PublicKey`, `CloudRadial-PrivateKey`. That's all. The first step fails with a message listing anything missing.
3. **Plan first.** Run with `{"companyId": <CloudRadial id>, "mode": "plan"}`. Nothing is written; the summary gives counts per phase and the first 150 planned device changes.
4. **Apply.** Re-run with `"mode": "apply"`. Run the devices phase before software (the default order does this), so software can attach to devices created in the same run. The run output's `reportLocation` says where the migration report was written.
5. Schedule it as a **Routine** to keep CloudRadial current. The webhook ships disabled — enable it only if something else triggers the sync.

## Run inputs

All optional except naming the client (either side works).

| Input | Default | Notes |
|---|---|---|
| `companyId` | — | CloudRadial company id. If only ScalePad is named, the company is matched by exact name. |
| `scalePadClientId` / `scalePadClientName` | — | If only CloudRadial is named, the ScalePad client is matched by exact name. |
| `mode` | `plan` | `apply` writes. |
| `phases` | all | Comma list: `devices,assets,software,assessments,roadmap,archive`. Other names are ignored with a warning — initiatives and contracts are `roadmap`, deliverables are `archive`. |
| `deviceTypes` | `WORKSTATION,SERVER,VIRTUAL` | ScalePad types to sync as endpoints. |
| `createMissingDevices` | `true` | `false` = only enrich devices CloudRadial already has. |
| `overwriteWarranty` | `false` | `true` = replace a CloudRadial warranty date that differs from ScalePad's. Otherwise differences are reported. |
| `assetTypes` | every type not in `deviceTypes` | ScalePad types kept as flexible assets, e.g. `NETWORK,IMAGING`. |
| `includeNoSerialDevices` | `true` | Keep workstations, servers and VMs that have no serial as flexible assets (they are never created as endpoints). |
| `flexibleAssetTypeName` | `ScalePad Assets` | Flexible asset type for the `assets` phase — created if missing. |
| `maxSoftwareWrites` | `2000` | Software records per run; the rest are picked up next run. |
| `assessmentStatus` | `Completed` | `all` to include in-progress assessments. |
| `labelScoreMap` | — | JSON overriding answer scoring, e.g. `{"needs_attention": 1}`. |
| `roadmapCategory` / `roadmapCategoryId` | `Efficiency` / `7` | Planner category for new cards — must exist in your portal. |
| `includeContracts` | `true` | Add contract cards alongside initiatives. |
| `archiveName` | `ScalePad QBR History` | Report archive for deliverable PDFs. |
| `deliverableLimit` | `20` | Newest deliverables per run. |
| `reportTarget` | `archive` | Where the apply-mode migration report goes: `archive`, `article` (knowledge base), or `none` (run output only). Falls back from archive to article automatically. |
| `reportArchiveName` | `ScalePad Migration` | Report archive for the migration report. |

## Confirm in your tenant

- **Flexible asset updates.** New rows use `POST /v2/flexible-asset` (the route the KnowBe4 sync already uses). Changed rows are sent as `PATCH /v2/flexible-asset/{id}` replacing `traitsJson`, falling back to `PATCH /compatibility/flexible_assets/{id}` with `traits`. After the first apply run that updates a row, check it in the portal.
- **ScalePad software paging.** The installed-software list accepts `page_size` 100 at most (the other lists take 200); the step asks for 100. Any list that rejects 200 is retried at 100 automatically.

- **Archive upload route.** `POST /api/beta/archive/{id}/item` is documented without a request body. The workflow sends a multipart PDF; if it's rejected, the report lists the PDFs to upload by hand. The migration report itself doesn't depend on this route — it's written with the documented `POST /v2/archiveitem` (HTML), or as an article.
- **Assessment import `type`.** The upload's `data` part sends `type: 0`. If the import lands as a template instead of an assessment, change it in the assessments step.
- **`POST /v2/assessment`** isn't in the published v2 spec (the Microsoft Security Assessment workflow uses it). If it fails, create the assessment once in the portal and pass its id.
- **Currency.** CloudRadial stores prices as plain numbers. The run warns when ScalePad amounts are in another currency (for example GBP).
- **Devices created from ScalePad** have no RMM agent until one is deployed — they carry ScalePad's data, not live telemetry, and are tagged `ScalePad`.

## Tested (mocked ScalePad and CloudRadial APIs, 2026-09-25)

**Flexible assets and paging (second pass):** the `assets` phase planned and created the ScalePad Assets type with its fields, then created a network device and a no-serial workstation as rows. With the type already present it added the missing fields, updated a changed row, and used the compatibility route when the native patch was refused. The software step read the list with `page_size` 100, against a mock that rejects anything larger.

**First pass:** a seven-step chain run in plan and apply, with each step's output fed to the next as JSON: two pages of hardware (cursor followed), a matched device enriched (OS, CPU, RAM, purchase date → `manufacturedDate`), a desktop, a server (enclosure 80) and a Mac (platform macOS) created, a network device skipped, software written only to known devices and de-duplicated, one assessment converted to `.xlsx` (opened and checked in Excel — required columns, scoring and suffixes correct), an initiative card updated with budget and roadmap quarter, a contract card created, a deliverable PDF the upload route refused listed for manual upload, and the migration report written to the ScalePad Migration archive — or, with the archive write forced to fail, to a knowledge base article. All steps parse after the round trip through YAML.
