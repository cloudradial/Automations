# ScalePad to CloudRadial Sync

A deterministic **workflow** that moves ScalePad Lifecycle Manager data into CloudRadial for **every ScalePad client that matches a CloudRadial company by name** — no input needed — API to API, following every ScalePad page, with nothing stored in between. **This is the only workflow a partner needs to migrate a client.** The [ScalePad to CloudRadial Alignment](../scalepad-cloudradial-alignment/) agent is an optional review for messy data — skip it unless you want a second opinion before applying.

## Pieces

| File | Type | Role |
|---|---|---|
| [`scalepad-cloudradial-sync.yml`](scalepad-cloudradial-sync.yml) | `automationsWorkflow` | Three steps: **Match companies by name** → **Migrate each company** (a For Each that runs every phase below for one company, in order) → **Migration report** (one report per company, written into its portal, plus a roll-up in the run output). |

## What it moves

| Phase | From ScalePad | To CloudRadial |
|---|---|---|
| `devices` | Core hardware (workstations, servers, VMs) + lifecycle records | Endpoints matched by serial. Existing ones get their blanks filled: warranty → `expirationDate`, purchase date → `manufacturedDate`, model, manufacturer, OS, CPU, RAM. Missing ones are created — servers as `isServer` / enclosure Server, VMs as `isVirtual`, tagged `ScalePad`. A device ScalePad calls a workstation but that runs **Windows Server** is treated as a server, and an existing endpoint with a Windows Server OS that isn't marked as a server is corrected. Network, mobile and imaging devices, and devices with no serial, go to the `assets` phase instead. |
| `assets` | Other hardware: types `NETWORK`, `MOBILE`, `IMAGING`, plus workstations, servers and VMs with no serial number | Rows of one flexible asset type, **ScalePad Assets** (Infrastructure), created with its fields if missing: name, type, manufacturer, model, serial, warranty and purchase dates, location, assigned user and the ScalePad id. Matched on the ScalePad id, so re-runs update the row. |
| `software` | Installed software per device | One endpoint application per product per device (name, publisher, version), tagged *Added by ScalePad to CloudRadial Sync* in its comments. Devices that already have software in CloudRadial (usually from the RMM, which keeps its own list current) are left alone; otherwise a product is skipped when the device already has one with the same name, ignoring publisher and version. |
| `assessments` | Completed assessments, full question tree | A CloudRadial assessment per ScalePad assessment, imported from an `.xlsx` built in memory in the layout from *Importing Assessments* (support KB 360052746791). Answers are scored +2 / +1 / 0 / −1 / −2. |
| `roadmap` | Initiatives (with budget and fiscal quarter) and contracts | Planner cards `ScalePad Initiative - <name>` / `ScalePad Contract - <name>` — updated if they exist. One-time budget → project price, recurring → monthly price, status and priority mapped, quarter placed on the roadmap. |
| `archive` | Deliverable PDFs | The company's **ScalePad QBR History** report archive (created if missing), uploaded through the archive API. The archive is found by name (or created), and each PDF is uploaded to it through the archive API; a PDF that fails is reported as an error and retried on the next run. |
| _report_ | — | In apply mode, a **migration report** in each company's portal: a knowledge base article (category *ScalePad Migration*), or with `reportTarget: archive` an item in its **ScalePad Migration** report archive. It lists what moved per area, what needs attention, and any warnings. |

Every phase is idempotent: re-running updates or skips what's already there. No email or outside service is involved — the result is visible in the portal itself.

## Install / run

1. **Workflows → Import** `scalepad-cloudradial-sync.yml`, publish, and deploy to your runner.
2. **Runner Key Vault secrets:** `ScalePad-ApiUrl` (e.g. `https://api.scalepad.com`), `ScalePad-ApiKey`, `CloudRadial-BaseUrl` (e.g. `https://api.us.cloudradial.com`), `CloudRadial-PublicKey`, `CloudRadial-PrivateKey`. That's all. The first step fails with a message listing anything missing.
3. **Run it** — click **Run** and leave **Trigger input** empty. Every ScalePad client whose name matches a CloudRadial company is migrated; clients with no match are listed in the output. Nothing needs wiring.
   - **Preview first:** `{"mode": "plan"}` — counts per company and phase, nothing written.
   - **One company:** `{"companyId": 9}` · **a few:** `{"companyIds": [9, 12]}` · **pair a client whose names differ:** `{"companyId": 9, "scalePadClientId": "<ScalePad id>"}`.
4. **Clean up duplicate software (only if needed).** An early version could write a company's ScalePad software twice. `{"companyId": 20, "cleanupDuplicateSoftware": true}` lists the extra copies; `{"companyId": 20, "cleanupDuplicateSoftware": true, "mode": "apply", "confirmCleanup": true}` deletes them. It only looks at records the Sync wrote (ScalePad's all-caps categories or the Sync's comment), keeps the oldest copy of each device + product + version, and never touches RMM software.
5. **Check the result.** The report step lists each company and where its migration report was written.
6. Schedule it as a **Routine** to keep CloudRadial current. The webhook ships disabled — enable it only if something else triggers the sync.

## Run inputs

All optional. With none, every name-matched company is migrated in apply mode.

| Input | Default | Notes |
|---|---|---|
| `companyId` / `companyIds` | all matched | Limit to one CloudRadial company or a list. |
| `maxCompanies` | — | Cap the number of companies per run. |
| `scalePadClientId` / `scalePadClientName` | — | Limit to one ScalePad client. With `companyId`, pairs a client whose name differs from the CloudRadial company. |
| `mode` | `apply` | `plan` previews without writing. |
| `phases` | all | Comma list: `devices,assets,software,assessments,roadmap,archive`. Other names are ignored with a warning — initiatives and contracts are `roadmap`, deliverables are `archive`. |
| `deviceTypes` | `WORKSTATION,SERVER,VIRTUAL` | ScalePad types to sync as endpoints. |
| `createMissingDevices` | `true` | `false` = only enrich devices CloudRadial already has. |
| `overwriteWarranty` | `false` | `true` = replace a CloudRadial warranty date that differs from ScalePad's. Otherwise differences are reported. |
| `assetTypes` | every type not in `deviceTypes` | ScalePad types kept as flexible assets, e.g. `NETWORK,IMAGING`. |
| `includeNoSerialDevices` | `true` | Keep workstations, servers and VMs that have no serial as flexible assets (they are never created as endpoints). |
| `flexibleAssetTypeName` | `ScalePad Assets` | Flexible asset type for the `assets` phase — created if missing. |
| `skipDevicesWithSoftware` | `true` | `false` = also add ScalePad software to devices that already have a software list, skipping only products they already have. |
| `cleanupDuplicateSoftware` / `confirmCleanup` | `false` | Run only the duplicate-software clean-up; deletes only with `mode: apply` **and** `confirmCleanup: true`. |
| `maxSoftwareWrites` | `2000` | Software records per run; the rest are picked up next run. |
| `assessmentStatus` | `Completed` | `all` to include in-progress assessments. |
| `labelScoreMap` | — | JSON overriding answer scoring, e.g. `{"needs_attention": 1}`. |
| `roadmapCategory` / `roadmapCategoryId` | `Efficiency` / `7` | Planner category for new cards — must exist in your portal. |
| `includeContracts` | `true` | Add contract cards alongside initiatives. |
| `includeInactiveContracts` | `false` | Cancelled and expired ScalePad contracts are skipped and listed in the warnings; `true` adds them too. |
| `archiveName` | `ScalePad QBR History` | Report archive for deliverable PDFs. |
| `deliverableLimit` | `20` | Newest deliverables per run. |
| `reportTarget` | `article` | Where the apply-mode migration report goes: `article` (knowledge base, the default), `archive` (report archive), or `none` (run output only). Archive falls back to article automatically. |
| `reportArchiveName` | `ScalePad Migration` | Report archive for the migration report. |

## Confirm in your tenant

- **Flexible asset updates.** New rows use `POST /v2/flexible-asset` (the route the KnowBe4 sync already uses). Changed rows are sent as `PATCH /v2/flexible-asset/{id}` replacing `traitsJson`, falling back to `PATCH /compatibility/flexible_assets/{id}` with `traits`. After the first apply run that updates a row, check it in the portal.
- **ScalePad software paging.** The installed-software list accepts `page_size` 100 at most (the other lists take 200); the step asks for 100. Any list that rejects 200 is retried at 100 automatically.

- **Archive upload route.** `POST /api/beta/archive/{id}/item` takes the PDF as multipart/form-data. The create call doesn't always return the new archive's id, so the step looks the archive up again by name before uploading (a first live run uploaded to archive 0 and failed with "Sequence contains no elements").
- **Assessment import `type`.** The upload's `data` part sends `type: 0`. If the import lands as a template instead of an assessment, change it in the assessments step.
- **`POST /v2/assessment`** isn't in the published v2 spec (the Microsoft Security Assessment workflow uses it). If it fails, create the assessment once in the portal and pass its id.
- **Currency.** CloudRadial stores prices as plain numbers. The run warns when ScalePad amounts are in another currency (for example GBP).
- **Devices created from ScalePad** have no RMM agent until one is deployed — they carry ScalePad's data, not live telemetry, and are tagged `ScalePad`.

## Tested (mocked ScalePad and CloudRadial APIs, 2026-09-25)

**Flexible assets and paging (second pass):** the `assets` phase planned and created the ScalePad Assets type with its fields, then created a network device and a no-serial workstation as rows. With the type already present it added the missing fields, updated a changed row, and used the compatibility route when the native patch was refused. The software step read the list with `page_size` 100, against a mock that rejects anything larger.

**First pass:** a seven-step chain run in plan and apply, with each step's output fed to the next as JSON: two pages of hardware (cursor followed), a matched device enriched (OS, CPU, RAM, purchase date → `manufacturedDate`), a desktop, a server (enclosure 80) and a Mac (platform macOS) created, a network device skipped, software written only to known devices and de-duplicated, one assessment converted to `.xlsx` (opened and checked in Excel — required columns, scoring and suffixes correct), an initiative card updated with budget and roadmap quarter, a contract card created, a deliverable PDF the upload route refused listed for manual upload, and the migration report written to the ScalePad Migration archive — or, with the archive write forced to fail, to a knowledge base article. All steps parse after the round trip through YAML.
