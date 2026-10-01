# Move Off ScalePad Without Losing Your Data

Moves every matched client's devices, other hardware, software, assessments, roadmap, budget, SaaS, insights and QBR documents from ScalePad into CloudRadial, and is safe to re-run.

**Formerly:** ScalePad to CloudRadial Sync | **Marketplace ID:** Not yet listed | **Type:** Workflow

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `scalepad-cloudradial-sync.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/scalepad-cloudradial-sync/scalepad-cloudradial-sync.yml) |
| Download `scalepad-cloudradial-sync.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/scalepad-cloudradial-sync/scalepad-cloudradial-sync.yml) |
| All files in this automation | [automationai/scalepad-cloudradial-sync](https://github.com/cloudradial/Automations/tree/main/automationai/scalepad-cloudradial-sync) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/scalepad-cloudradial-sync) |
| Works with | [Review Messy ScalePad Data Before You Migrate](https://github.com/cloudradial/Automations/tree/main/automationai/scalepad-cloudradial-alignment) |
| Source (for maintainers) | [src/](https://github.com/cloudradial/Automations/tree/main/automationai/scalepad-cloudradial-sync/src) |

## How it works

A deterministic **workflow** that moves ScalePad Lifecycle Manager data into CloudRadial for **every ScalePad client that matches a CloudRadial company by name**, no input needed, API to API, following every ScalePad page, with nothing stored in between. **This is the only workflow a partner needs to migrate a client.** The [ScalePad to CloudRadial Alignment](https://github.com/cloudradial/Automations/tree/main/automationai/scalepad-cloudradial-alignment) agent is an optional review for messy data, skip it unless you want a second opinion before applying.

## Pieces

| File | Type | Role |
|---|---|---|
| [`scalepad-cloudradial-sync.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/scalepad-cloudradial-sync/scalepad-cloudradial-sync.yml) | `automationsWorkflow` | Three steps: **Match companies by name** → **Migrate each company** (a For Each that runs every phase below for one company, in order) → **Migration report** (one report per company, written into its portal, plus a roll-up in the run output). |
| [`src/`](src/) | Source | The PowerShell for each step and phase, the build script that assembles them into the `.yml`, and a mocked test harness. Partners don't need it; see [Changing the workflow](#changing-the-workflow). |

## What it moves

| Phase | From ScalePad | To CloudRadial |
|---|---|---|
| `devices` | Core hardware (workstations, servers, VMs) + lifecycle records | Endpoints matched by serial. Existing ones get their blanks filled: warranty → `expirationDate`, purchase date → `manufacturedDate`, model, manufacturer, OS, CPU, RAM. Missing ones are created — servers as `isServer` / enclosure Server, VMs as `isVirtual`, tagged `ScalePad`. A device ScalePad calls a workstation but that runs **Windows Server** is treated as a server, and an existing endpoint with a Windows Server OS that isn't marked as a server is corrected. Network, mobile and imaging devices, and devices with no serial, go to the `assets` phase instead. |
| `assets` | Other hardware: types `NETWORK`, `MOBILE`, `IMAGING`, plus workstations, servers and VMs with no serial number | One flexible asset type per kind of device (Infrastructure): Network Devices, Mobile Devices, Printers & Imaging, Storage Devices, Power Devices, Workstations (No Serial), Servers (No Serial), Virtual Machines (No Serial) or Other Hardware. Each type is created with its fields if missing: name, type, manufacturer, model, serial, warranty and purchase dates, location, assigned user and the ScalePad id. Matched on the ScalePad id, so re-runs update the row. Rows an earlier version wrote to the single **ScalePad Assets** type are moved to their device type; the report says when the old type can be deleted. |
| `saas` | SaaS subscriptions (Microsoft 365, Google Workspace, ...) | CloudRadial's software records always belong to a device and its API has no SaaS or licence route, so each subscription becomes a row of a flexible asset type named **SaaS**: product, vendor, SKU, category, status, licences and assigned seats, term start, renewal date, auto-renew, billing, provider, tenant domain and the ScalePad id (the match key, so re-runs update). |
| `software` | Installed software per device | One endpoint application per product per device (name, publisher, version), tagged *Added by ScalePad to CloudRadial Sync* in its comments. Devices that already have software in CloudRadial (usually from the RMM, which keeps its own list current) are left alone; otherwise a product is skipped when the device already has one with the same name, ignoring publisher and version. |
| `assessments` | Completed assessments, full question tree | A CloudRadial assessment per ScalePad assessment, imported from an `.xlsx` built in memory in the layout from *Importing Assessments* (support KB 360052746791). Answers are scored +2 / +1 / 0 / −1 / −2. |
| `roadmap` | Initiatives (with budget and fiscal quarter) and contracts | Planner cards `ScalePad Initiative - <name>` / `ScalePad Contract - <name>`, updated if they exist. One-time budget → project price, recurring → monthly price, status and priority mapped, quarter placed on the roadmap. |
| `insights` | Lifecycle Manager insights (High-risk, Warranty coverage, Hardware and Software modernization, Windows 11, Backup, Security, custom) | Each insight with affected assets becomes a **Proposed** Planner card `ScalePad Insight - <title>`: priority from the risk level, description, affected count, 30-day trend and, for hardware insights, the affected devices (up to 25). Re-runs refresh the text only, keeping any status or priority you set. Every insight, including clear ones, is listed in the report. |
| `archive` | Deliverable PDFs | The company's **ScalePad QBR History** report archive (created if missing), uploaded through the archive API. The archive is found by name (or created), and each PDF is uploaded to it through the archive API; a PDF that fails is reported as an error and retried on the next run. |
| `meetings` | Every meeting, completed and upcoming (newest first; `meetingLimit` caps it if set) | One HTML item per meeting in the company's **ScalePad Meeting Notes** report archive (Compliance > Reports): title, type, date, attendees, the notes/agenda converted from ScalePad's rich text, and the action items raised in it. Re-runs skip meetings already archived. |
| `followup` | Open action items, meetings (upcoming + last 12 months), goals, assessment templates | Nothing is written - these areas have no CloudRadial API. They become the report's **Manual follow-up checklist**, together with anything from the run that needs a person (failed writes, warranty conflicts, skipped cancelled contracts). Action items are listed under the Planner card of their initiative. |
| _report_ |, | In apply mode, a **migration report** in each company's **ScalePad Migration** report archive (Compliance > Reports - admins only), one item updated each run; `reportTarget: article` writes a knowledge base article instead. It lists what moved per area, what needs attention, and any warnings. |

## What it doesn't move

Some parts of ScalePad Lifecycle Manager have no CloudRadial API (or none this workflow uses yet). Every migration report lists them in a **Not migrated** table, so nothing is silently dropped:

| ScalePad area | Why | What to do |
|---|---|---|
| Policies and standards | CloudRadial's API has no route for Compliance Policies; the only policy data it exposes is each endpoint's Windows audit-policy settings (`EndpointAuditPolicy`, reported by the agent). | Set up the equivalent checks under **Compliance > Policies**. The Sync already fills the endpoint fields those checks read (warranty expiry, purchase date, server type). |
| Assessment templates | Only completed assessments (with answers) import. | Recreate templates under Compliance > Assessments, or import one with the Excel template. |
| Meeting scheduling | No meeting or calendar API. Notes, attendees and action items are archived (`meetings` phase). | Recreate upcoming and recurring meetings in your calendar or PSA - the checklist lists them. |
| Goals | No API for client goals or outcomes. | Record them on a Planner card or in QBR notes - the checklist lists them. |
| Initiative action items and notes | No API for Planner card sub-tasks. | Add them to the card description, or track them in your PSA. |
| Report and deliverable templates, branding | Neither API exposes templates. | Rebuild in CloudRadial Report Layouts. |

## Re-runs and schedules

The Sync is built to run again - by hand or as a daily/weekly **Routine** - without duplicating anything or undoing a partner's changes:

| Area | On a re-run |
|---|---|
| Devices, other hardware, SaaS | Matched (serial / ScalePad id); blanks filled and changed values updated; new ones created |
| Software | Devices that already have software from an RMM are left alone; devices the Sync created get any new ScalePad installs; a device whose software can't be read is skipped |
| Roadmap cards | Budget, pricing and quarter kept current; **status and priority are set only when a card is created** |
| Insight cards | Text refreshed; a card is **closed as Completed when its insight clears**, and reopened as Proposed if it comes back |
| Assessments, PDFs | New ones added; existing ones skipped |
| Meeting notes | New meetings added; an archived meeting is **refreshed when its notes, attendees or action items change** |
| Migration report | **One "ScalePad sync report" item per company in the admin-only ScalePad Migration archive, updated each run** (`reportArticleTitle` renames it) |

Nothing is deleted in CloudRadial when it disappears from ScalePad.

Every phase is idempotent: re-running updates or skips what's already there. No email or outside service is involved, the result is visible in the portal itself.

## Install / run

1. **Workflows → Import** `scalepad-cloudradial-sync.yml`, publish, and deploy to your runner.
2. **Runner Key Vault secrets:** `ScalePad-ApiUrl` (e.g. `https://api.scalepad.com`), `ScalePad-ApiKey`, `CloudRadial-BaseUrl` (e.g. `https://api.us.cloudradial.com`), `CloudRadial-PublicKey`, `CloudRadial-PrivateKey`. That's all. The first step fails with a message listing anything missing.
3. **Run it**, click **Run** and leave **Trigger input** empty. Every ScalePad client whose name matches a CloudRadial company is migrated; clients with no match are listed in the output. Nothing needs wiring.
   - **Preview first:** `{"mode": "plan"}`, counts per company and phase, nothing written.
   - **One company:** `{"companyId": 9}` · **a few:** `{"companyIds": [9, 12]}` · **pair a client whose names differ:** `{"companyId": 9, "scalePadClientId": "<ScalePad id>"}`.
4. **Clean up duplicate software (only if needed).** An early version could write a company's ScalePad software twice. `{"companyId": 20, "cleanupDuplicateSoftware": true}` lists the extra copies; `{"companyId": 20, "cleanupDuplicateSoftware": true, "mode": "apply", "confirmCleanup": true}` deletes them. It only looks at records the Sync wrote (ScalePad's all-caps categories or the Sync's comment), keeps the oldest copy of each device + product + version, and never touches RMM software.
5. **Check the result.** The report step lists each company and where its migration report was written.
6. Schedule it as a **Routine** to keep CloudRadial current. The webhook ships disabled, enable it only if something else triggers the sync.

## Run inputs

All optional. With none, every name-matched company is migrated in apply mode.

| Input | Default | Notes |
|---|---|---|
| `companyId` / `companyIds` | all matched | Limit to one CloudRadial company or a list. |
| `maxCompanies` |, | Cap the number of companies per run. |
| `scalePadClientId` / `scalePadClientName` |, | Limit to one ScalePad client. With `companyId`, pairs a client whose name differs from the CloudRadial company. |
| `mode` | `apply` | `plan` previews without writing. |
| `phases` | all | Comma list: `devices,assets,saas,software,assessments,roadmap,insights,archive,meetings,followup`. Other names are ignored with a warning, initiatives and contracts are `roadmap`, deliverables are `archive`. |
| `deviceTypes` | `WORKSTATION,SERVER,VIRTUAL` | ScalePad types to sync as endpoints. |
| `createMissingDevices` | `true` | `false` = only enrich devices CloudRadial already has. |
| `overwriteWarranty` | `false` | `true` = replace a CloudRadial warranty date that differs from ScalePad's. Otherwise differences are reported. |
| `assetTypes` | every type not in `deviceTypes` | ScalePad types kept as flexible assets, e.g. `NETWORK,IMAGING`. |
| `includeNoSerialDevices` | `true` | Keep workstations, servers and VMs that have no serial as flexible assets (they are never created as endpoints). |
| `flexibleAssetTypeNames` | — | Rename a device type's flexible asset type, keyed by ScalePad type, e.g. `{"NETWORK": "Network Equipment"}`. |
| `flexibleAssetTypeName` | *(blank)* | Set only to put every `assets` row in one type instead of one per kind of device. |
| `legacyFlexibleAssetTypeName` | `ScalePad Assets` | The single type earlier versions used. Its rows are moved to their device type. |
| `skipDevicesWithSoftware` | `true` | `false` = also add ScalePad software to devices that already have a software list, skipping only products they already have. |
| `cleanupDuplicateSoftware` / `confirmCleanup` | `false` | Run only the duplicate-software clean-up; deletes only with `mode: apply` **and** `confirmCleanup: true`. |
| `saasTypeName` | `SaaS` | Flexible asset type for the `saas` phase - created if missing. |
| `maxSoftwareWrites` | `2000` | Software records per run; the rest are picked up next run. |
| `assessmentStatus` | `Completed` | `all` to include in-progress assessments. |
| `labelScoreMap` |, | JSON overriding answer scoring, e.g. `{"needs_attention": 1}`. |
| `roadmapCategory` / `roadmapCategoryId` | `Efficiency` / `7` | Planner category for new cards, must exist in your portal. |
| `includeContracts` | `true` | Add contract cards alongside initiatives. |
| `includeInactiveContracts` | `false` | Cancelled and expired ScalePad contracts are skipped and listed in the warnings; `true` adds them too. |
| `insightDeviceLimit` / `insightCategory` | `25` / roadmap category | Devices listed per insight card; Planner category for insight cards. |
| `meetingArchiveName` / `meetingLimit` | `ScalePad Meeting Notes` / `0` (all) | Report archive for meeting notes; set `meetingLimit` only to cap how many of the newest meetings a run archives. |
| `archiveName` | `ScalePad QBR History` | Report archive for deliverable PDFs. |
| `deliverableLimit` | `0` (all) | Set only to cap how many of the newest deliverables a run archives. |
| `reportTarget` | `archive` | Where the migration report goes: `archive` (default - one **ScalePad sync report** item in the **ScalePad Migration** report archive, **admins only** by security role, updated each run), `article` (knowledge base - visible to portal users, so only on request), or `none` (run output only). If the archive can't be written the report stays in the run output; it never falls back to the knowledge base. |
| `reportArchiveName` | `ScalePad Migration` | Report archive for the migration report. |

## Confirm in your tenant

- **Flexible asset updates.** New rows use `POST /v2/flexible-asset` (the route the KnowBe4 sync already uses). Changed rows are sent as `PATCH /v2/flexible-asset/{id}` replacing `traitsJson`, falling back to `PATCH /compatibility/flexible_assets/{id}` with `traits`. After the first apply run that updates a row, check it in the portal.
- **Connection errors are retried.** A request that fails before it reaches the server (TLS handshake, DNS, reset, timeout) is retried up to 3 more times. If a whole step still fails that way, it is run again for that company, up to 3 attempts, and the run output notes it. Steps match what already exists, so a re-run never duplicates.
- **ScalePad software paging.** The installed-software list accepts `page_size` 100 at most (the other lists take 200); the step asks for 100. Any list that rejects 200 is retried at 100 automatically.

- **Archive upload route.** `POST /api/beta/archive/{id}/item` takes the PDF as multipart/form-data. The create call doesn't always return the new archive's id, so the step looks the archive up again by name before uploading (a first live run uploaded to archive 0 and failed with "Sequence contains no elements").
- **Assessment import `type`.** The upload's `data` part sends `type: 0`. If the import lands as a template instead of an assessment, change it in the assessments step.
- **`POST /v2/assessment`** isn't in the published v2 spec (the Microsoft Security Assessment workflow uses it). If it fails, create the assessment once in the portal and pass its id.
- **Currency.** CloudRadial stores prices as plain numbers. The run warns when ScalePad amounts are in another currency (for example GBP).
- **Devices created from ScalePad** have no RMM agent until one is deployed, they carry ScalePad's data, not live telemetry, and are tagged `ScalePad`.

## Tested (mocked ScalePad and CloudRadial APIs, 2026-09-25)

**Flexible assets by device type (third pass):** with a network device already in the old ScalePad Assets type, the `assets` phase created a Network Devices type and a Workstations (No Serial) type, moved the network device (created in the new type, then deleted from the old one), and created the no-serial workstation. With the ScalePad hardware read failing on a TLS error five times in a row, the requests retried and the devices step then ran again for the company and completed.

**Flexible assets and paging (second pass):** the `assets` phase planned and created the ScalePad Assets type with its fields, then created a network device and a no-serial workstation as rows. With the type already present it added the missing fields, updated a changed row, and used the compatibility route when the native patch was refused. The software step read the list with `page_size` 100, against a mock that rejects anything larger.

**First pass:** a seven-step chain run in plan and apply, with each step's output fed to the next as JSON: two pages of hardware (cursor followed), a matched device enriched (OS, CPU, RAM, purchase date → `manufacturedDate`), a desktop, a server (enclosure 80) and a Mac (platform macOS) created, a network device skipped, software written only to known devices and de-duplicated, one assessment converted to `.xlsx` (opened and checked in Excel, required columns, scoring and suffixes correct), an initiative card updated with budget and roadmap quarter, a contract card created, a deliverable PDF the upload route refused listed for manual upload, and the migration report written to the ScalePad Migration archive. With the archive write forced to fail, the report stays in the run output and is not written to the knowledge base. All steps parse after the round trip through YAML.

## Changing the workflow

`scalepad-cloudradial-sync.yml` is **generated** from [`src/`](src/). Don't edit the scripts inside the `.yml`; change the source and rebuild.

| File | What |
|---|---|
| `COMMON.ps1` | Shared helpers, embedded in every step: ScalePad paging, CloudRadial API calls, connection-error retries. |
| `1-resolve.ps1` | **Match companies by name.** |
| `2c-cleanup.ps1`, `2-devices.ps1`, `2b-assets.ps1`, `2d-saas.ps1`, `3-software.ps1`, `4-assessments.ps1`, `5-roadmap.ps1`, `5b-insights.ps1`, `6-archive.ps1`, `6b-meetings.ps1`, `5c-followup.ps1` | One file per phase, run in order inside **Migrate each company**. |
| `7-summary.ps1` | **Migration report.** |
| `make-saas.js` | Generates `2d-saas.ps1` from `2b-assets.ps1`. Run it after changing `2b-assets.ps1`. |
| `build-wf.js` | Assembles the `.yml`: the per-company loop, the per-phase re-run on connection errors, and checks on the result. |
| `harness.ps1`, `test-flow.ps1` | Run the built steps against mocked ScalePad and CloudRadial APIs, in strict mode as on the runner. |

From `src/`:

1. `npm install` (installs js-yaml).
2. `node make-saas.js` if you changed `2b-assets.ps1`.
3. `node build-wf.js` rewrites `../scalepad-cloudradial-sync.yml`.
4. `pwsh -File test-flow.ps1 -InputJson '{"mode":"plan"}'`, then with `"apply"`.

The runner runs PowerShell steps under `Set-StrictMode -Version Latest`, so reading a property or key that doesn't exist throws. The harness does the same, so test there before importing.
