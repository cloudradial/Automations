# Ticket Devices That Have Dropped Off the RMM

Once a day, every managed device that Datto RMM hasn't seen for too long lands on one PSA ticket per client, servers first, with a suggested first step for each device. A level 1 tech no longer has to sweep the RMM by hand.

**Formerly:** Offline Device Sweep (tracker 3.3) | **Marketplace ID:** TBD | **Type:** Workflow (PowerShell, no AI, runs on a schedule)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `offline-device-sweep.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/offline-device-sweep/offline-device-sweep.yml) |
| Download `offline-device-sweep.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/offline-device-sweep/offline-device-sweep.yml) |
| All files in this automation | [offline-device-sweep](https://github.com/cloudradial/Automations/tree/main/offline-device-sweep) |
| Build source (`src/`) | [offline-device-sweep/src](https://github.com/cloudradial/Automations/tree/main/offline-device-sweep/src) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/offline-device-sweep) |
| Works with | [RMM Agent](https://github.com/cloudradial/Automations/tree/main/rmm-agent) (same Datto RMM secrets), [Waiting-on-Client Nudge](https://github.com/cloudradial/Automations/tree/main/waiting-on-client-nudge) (same schedule and preview pattern) |
| Shared PSA code | [`_shared/psa.ps1` and `_shared/psa-tickets.ps1`](https://github.com/cloudradial/Automations/tree/main/_shared) |
| Datto wake component (only for `wake`) | [`datto-component/wake-on-lan.ps1`](https://github.com/cloudradial/Automations/blob/main/offline-device-sweep/datto-component/wake-on-lan.ps1) |

## How it works

A Routine runs the workflow once a day. It reads Datto RMM and works in ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk, using the PSA named by the `PSA-Type` secret.

`Start → Find offline devices → Wake offline desktops → Open or update tickets → End`

1. **Find offline devices** changes nothing anywhere. It:
   - signs in to Datto RMM and reads every site, then every device at each site (all pages);
   - skips Datto's placeholder sites (`Deleted Devices`, `Managed`, `OnDemand`) unless `companyMap` names them, any site in `ignoreSites`, and suspended or deleted devices;
   - keeps a device when Datto says it is offline and it was last seen longer ago than the threshold for its category: `offlineDays` (7) for workstations and laptops, `serverOfflineHours` (4) for servers. Mobile devices, printers and network devices are skipped unless `includeCategories` asks for them;
   - counts the online devices at each site, to spot a site that may be down as a whole. A site counts as down when it has at least two checked devices, every server there is past `serverOfflineHours`, and at least three in four of its checked devices are offline right now (even those still under their own threshold);
   - matches each site to a PSA company: the `companyMap` entry first, otherwise exactly one PSA company with exactly the site's name. A site with no match, or with two companies of the same name, is never ticketed to a guess. It is listed in `unmatchedSites` and in the warnings. Several sites that map to one company share one ticket;
   - looks for this workflow's open ticket for each company (an open ticket whose summary starts with `Offline devices:`) and reads its notes to see which devices were offline last time;
   - when `wake` is on, also notes the online Windows desktops and laptops at each site, for step 2.
2. **Wake offline desktops** does nothing unless the run input has `wake: true`. Then it tries a Wake-on-LAN on each offline desktop first (see [Wake-on-LAN](#wake-on-lan-optional)).
3. **Open or update tickets** acts on what steps 1 and 2 found:
   - **No open ticket and something offline:** opens one ticket for the company, with summary such as `Offline devices: 3 not seen for 7+ days`. Servers get their own line at the top, and a ticket with a server in it opens at `serverPriority` (high); otherwise at `priority` (medium). An internal note with the marker follows.
   - **An open ticket and the list changed:** adds one internal note saying what is newly offline, what is still offline, and what recovered (back online, checked in recently, suspended, or no longer in Datto RMM). When everything recovered, the note says so and asks the tech to close the ticket. A newly offline server is called out so the tech can raise the priority.
   - **An open ticket and nothing changed:** writes nothing, so the ticket doesn't fill up with the same list every day.

**When a whole site may be down.** If a site looks down, the ticket (or the update note) starts with one line before the device list, for example `The whole Contoso site may be down: Datto RMM shows 9 of its 10 devices offline right now, including its only server.` It asks the tech to check the site's power, internet connection and firewall before working through the devices one by one. The number counts every offline device at the site, so it can be higher than the list below it, which only shows devices past their threshold. A site with no server checked, or a single device, never gets this line. If a site goes down while its ticket is already open, the next run adds a note with the line even when the device list hasn't changed (the rest of the site can go offline while still under its own threshold), and only once: a note that already says so isn't repeated.

### Wake-on-LAN (optional)

Off by default. It needs a Datto component and more Datto rights (see [Permissions](#permissions-needed)), so the workflow stays read-only in Datto RMM until you turn it on. With `wake: true`, before ticketing, for each offline desktop:

1. It reads the desktop's MAC and IPv4 addresses from its Datto audit, and picks an online Windows desktop or laptop at the same site on the same network (the first three parts of the IPv4 address match).
2. It runs your Datto **Wake-on-LAN** component on that device as a quick job, passing the desktop's MAC addresses. The component sends the standard magic packet.
3. It waits `wakeWaitMinutes` (5), then reads the site again. A desktop that is back online is left off the new ticket, with one line saying it came back after a wake-up, or noted as recovered on the open ticket. One that is still offline is ticketed as usual, with a line saying when the wake-up was sent and from where, and the Datto job's result if it failed.

**What it never does:**

- Wake a server, laptop, printer or network device. A server that is down needs a person; laptops are usually on Wi-Fi or battery, where Wake-on-LAN rarely works.
- Send a packet from a server, or at a site that looks down as a whole (nothing there is online to send it).
- Send twice in a day: a company whose ticket already has the day's note is skipped, so a rerun or Retry sends nothing.
- Send more than `wakeMax` (20) in one run.
- Stop the tickets. A wake-up that can't be sent (no component, no MAC address, no device on the same network, a refused job) is noted on that device's line and in the output, and the ticket opens as usual.

**Approval.** A `preview` run with `wake: true` lists each desktop it would wake and from which device, and sends nothing. A run with `wake: true` and no `preview` sends. Adding `wake: true` to the daily Routine is a standing approval, so only do that once the preview looks right.

**What to expect.** A desktop offline for 7 days or more is often switched off at the wall, moved or retired, so few will wake. Wake-on-LAN also needs BIOS and network card support and a wired connection. It helps most with a short `offlineDays`, for example desktops left off over a weekend.

Each device line gives the hostname, type, OS, when it was last seen (date, and hours or days ago), and a suggested first step: check power and network (servers, and devices offline under 30 days), confirm with the client whether it has been decommissioned (30 to 90 days), or confirm and remove it from Datto RMM if it looks retired (90 days or more).

**How it knows what it already did.** Every internal note it writes ends with a marker for the day, `[offline-device-sweep: 2026-10-16]`, and a plain line, `Offline in this check: CONTOSO-PC01, CONTOSO-SRV01.` The next run compares that line with what is offline now to find newly offline and recovered devices. Don't edit or delete these lines.

**Safe to run again.** A rerun on the same day (an Action Runs **Retry**, or a manual run after the Routine) finds the ticket by its summary and the day's marker, so it never opens a second ticket and never writes the same day's note twice. If you close the ticket, the next run that finds devices offline opens a new one.

## Download & import

**Download the workflow:** [`offline-device-sweep.yml`](https://raw.githubusercontent.com/cloudradial/Automations/main/offline-device-sweep/offline-device-sweep.yml)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), **Publish**, **Deploy** to the runner that holds the secrets, and attach a daily **Routine** (the schedule isn't part of the export). Full steps are under [Import & test](#import--test).

## Inputs

All inputs are optional. A Routine sends no input, so every one has a default. The snake_case names (`offline_days`, `server_offline_hours`, `include_categories`, `ignore_sites`, `company_map`, `wake_component`, `wake_wait_minutes`, `wake_max`) work too.

| Field | Default | What it does |
|---|---|---|
| `preview` | `false` | `true` reads everything, writes nothing, and returns what would be ticketed. Use it for the first run. `dryRun` is accepted as the same switch. |
| `offlineDays` | `7` | Days a workstation or laptop (and any other included non-server device) must have been unseen before it is ticketed (1 to 3650). |
| `serverOfflineHours` | `4` | Hours a server must have been unseen before it is ticketed (1 to 8760). Servers matter more, so the threshold is much shorter. |
| `includeCategories` | `workstations, laptops, servers` | Which device types to check. Any of `workstations`, `laptops`, `servers`, `mobile`, `printers`, `network`, `other`. A comma list or a JSON list. |
| `ignoreSites` | none | Datto site names or site uids to leave out entirely. A comma list or a JSON list. |
| `companyMap` | none | JSON object from a Datto site name (or site uid) to a PSA company id or exact PSA company name, for sites whose names don't match the PSA, for example `{"Contoso HQ": "42", "Fabrikam - Branch": "Fabrikam"}`. |
| `priority` | `medium` | Priority of a new ticket with no server in it (`critical`, `high`, `medium` or `low`). |
| `serverPriority` | `high` | Priority of a new ticket that lists a server. |
| `queue` | PSA default | Board (ConnectWise), queue (Autotask, Kaseya BMS id), team (HaloPSA), issue type (Syncro) or group id (Zendesk) for new tickets. |
| `psa` | the `PSA-Type` secret | Overrides which PSA to use. |
| `wake` | `false` | `true` tries a Wake-on-LAN on each offline desktop before ticketing (see [Wake-on-LAN](#wake-on-lan-optional)). `wakeBeforeTicket` is accepted as the same switch. |
| `wakeComponent` | `Wake-on-LAN` | Name (or uid) of your Datto RMM wake component. |
| `wakeWaitMinutes` | `5` | Minutes to wait after the wake-ups before reading the sites again (1 to 10). |
| `wakeMax` | `20` | Most wake-ups in one run (1 to 50). Datto allows 100 writes a minute across the account. |

**Why `preview` and not `confirm`:** like the Waiting-on-Client Nudge, this card runs on a schedule with nobody watching, so the default is to act. `preview: true` is the dry-run switch. The first step's Test Input is `{"preview": true}`.

Bad input fails closed: the run stops with a plain sentence before anything is read or written.

## Output

| Field | What it is |
|---|---|
| `status` | `success`, `incomplete` when any company failed, `pending_confirmation` for a preview with tickets to open or update, or `error` |
| `message` | One plain sentence |
| `preview` | Whether this was a preview |
| `counts` | `sites`, `devicesChecked`, `offline`, `sitesDown`, `ticketsCreated`, `ticketsUpdated`, `ticketsUnchanged`, `wouldCreate`, `wouldUpdate` (preview), `unmatchedSites`, `failed`, `wakeSent`, `wokeUp`, `wouldWake` (preview) |
| `companies` | One row per company: `company`, `companyId`, `sites`, `offline`, `servers`, `sitesDown` (Datto sites that look down), `action` (`created`, `updated`, `unchanged`, `would create`, `would update`, `woke` (every desktop came back, so no ticket), `failed`), `ticketId`, `ticketUrl`, `devices`, `recovered`, `wokeUp`, `summary`, `text` (the ticket body or note), `error` |
| `unmatchedSites` | Each Datto site with no PSA company match: `site`, `offline`, `reason` |
| `wake` | Only when `wake` is on: `wouldWake`, `sent`, `cameBack`, `stillOffline`, `skipped` (`hostname`, `company`, `reason`) and `attempts` (`hostname`, `company`, `peer`, `jobUid`, `jobStatus`, `cameBack`) |
| `warnings` | Plain sentences: unmatched sites with offline devices, devices with no type or last seen date, duplicate open tickets, anything the PSA library warned about |
| `internal_note` | The run summary, one line per company, then the warnings |
| `public_note`, `ticket_id` | Empty: this run spans many companies |

## Required Runner Key Vault secrets

The same names as each catalog extension, so one set of secrets serves both.

| System | Secrets |
|---|---|
| Datto RMM | `Datto-ApiUrl` (your platform's API address, such as `https://<platform>-api.centrastage.net`), `Datto-ApiKey`, `Datto-ApiSecret` |
| All PSAs | `PSA-Type` (`connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk`). Optional: `PSA-TicketUrlTemplate` |
| ConnectWise PSA | `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` |
| Autotask | `Autotask-ApiUrl`, `Autotask-ApiIntegrationCode`, `Autotask-Username`, `Autotask-Secret`. Optional: `Autotask-NewStatusId`, `Autotask-BillingCodeId`, `Autotask-NotePublishId`, `Autotask-NoteTypeId` |
| HaloPSA | `Halo-ApiUrl`, `Halo-ClientId`, `Halo-ClientSecret`. Optional: `Halo-NoteOutcomeId` |
| Kaseya BMS | `KaseyaBMS-ApiUrl`, `KaseyaBMS-Username`, `KaseyaBMS-Password`, `KaseyaBMS-CompanyName`, `KaseyaBMS-NoteTypeId`. Optional: `KaseyaBMS-NewStatusId`, `KaseyaBMS-TicketTypeId`, `KaseyaBMS-TicketSourceId`, `KaseyaBMS-PriorityId`, `KaseyaBMS-QueueId` |
| Syncro | `Syncro-ApiUrl`, `Syncro-ApiKey` |
| Zendesk | `Zendesk-BaseUrl`, `Zendesk-Email`, `Zendesk-ApiToken` |

## Permissions needed

- **Datto RMM:** a dedicated API user (**Setup > Users**, with API access enabled; its API key and secret key go in the secrets). Give it a security level that can **view** all sites and their devices. Without `wake`, nothing else is needed: the workflow only reads `GET /api/v2/account/sites` and `GET /api/v2/site/{siteUid}/devices`, and never writes to Datto RMM. If its access is limited to some sites, only those are swept. Datto allows 600 reads a minute across the whole account; a large account uses one read per 250 sites plus one per 250 devices at each site. A `429` waits (Datto's `Retry-After`, or 60 seconds) and tries again.
- **Datto RMM, only with `wake`:** the API user also needs **Devices: Manage**, **Active Jobs: Manage** and **Components: View**, and an **API Component Level** that allows the wake component. The wake step reads `GET /api/v2/audit/device/{deviceUid}`, `GET /api/v2/account/components` and `GET /api/v2/job/{jobUid}/results/{deviceUid}`, and writes only `PUT /api/v2/device/{deviceUid}/quickjob` on the device sending the packet. A job is never retried or redirected, so it can't run twice.
- **PSA:** the API account needs to read companies, read and create tickets, and read and add internal notes. ConnectWise also reads ticket priorities (Inquire access) to set the priority exactly; without it the priority comes from impact and urgency, with a warning. A missing permission stops that company's ticket with a plain sentence naming the HTTP status.
- **Microsoft Graph:** none.

## Import & test

1. **Import** `offline-device-sweep.yml` on **Workflows → Import**. Add the secrets above to the runner Key Vault, then **Publish** and **Deploy** to that runner.
2. **Preview first.** Run it from **Test** with `{"preview": true}` (the first step's Test Input). Check `companies`: the right devices for each client, servers at the top, and the summary and body under `text`. Check `unmatchedSites` and `warnings`, and add any site whose name differs from the PSA to `companyMap`.
3. **One run live.** Run it with no input (or with your `companyMap` and `ignoreSites`), then open one of the new tickets in the PSA: it should list the devices, and have an internal note ending with `[offline-device-sweep: <today>]`.
4. **Run it again straight away.** Nothing new should be written (`ticketsUnchanged` goes up). That proves a rerun never opens a second ticket.
5. **Optional: Wake-on-LAN.** In Datto RMM, create a PowerShell component named `Wake-on-LAN` from [`datto-component/wake-on-lan.ps1`](https://github.com/cloudradial/Automations/blob/main/offline-device-sweep/datto-component/wake-on-lan.ps1), with one String variable `MacAddress`, and give the API user the extra rights above. Run a preview with `{"preview": true, "wake": true}` and check `wake.skipped` and each desktop's line. Then do one live run with `wake: true` on a site with a desktop you know is switched off, and check the Datto job on the sending device and the ticket line.
6. **Schedule it daily.** Attach a **Routine** that runs once a day, early in the morning before the service desk starts, with no input, or with your own `offlineDays`, `serverOfflineHours`, `companyMap` and `ignoreSites`. Once a day is the intended cycle: a second run the same day only finds the day's note already there.

## Editing it

The two PowerShell steps are generated. Edit the files in `src/`, never the script inside the `.yml`:

| File | What it is |
|---|---|
| `src/find.ps1` | Step 1: input, Datto read, thresholds, site-down check, company match, open-ticket lookup |
| `src/wake.ps1` | Step 2: the opt-in Wake-on-LAN (gates, choosing the sending device, quick job, re-read) |
| `src/ticket.ps1` | Step 3: open or update tickets, preview, run summary |
| `src/common.ps1` | Marker, ticket and note text, helpers used by every step |
| `src/datto.ps1` | The Datto RMM API v2 client (sign-in, paging, 429 retry, device categories; audit, components and the quick job for the wake step) |
| `src/build.js` | Assembles the `.yml`: pastes `_shared/psa.ps1` and `_shared/psa-tickets.ps1` (through `_shared/inject.js`), then `common.ps1` and `datto.ps1`. It refuses a build where any step but the wake step starts a Datto job |
| `src/test.ps1` | Strict-mode harness on `_shared/tests/mock.ps1`: mocked Datto RMM, ConnectWise, Autotask and Zendesk |
| `datto-component/wake-on-lan.ps1` | The Datto RMM component the wake step runs. It isn't part of the `.yml`; create it in Datto RMM |

```
cd offline-device-sweep
node src/build.js                     # writes offline-device-sweep.yml (needs js-yaml: JS_YAML_PATH, or npm install in _shared)
pwsh -NoProfile -File src/test.ps1    # runs the shipped steps against the mocks
```

## Proven live

On 2026-10-30 the workflow ran in AutomationAI against a real Datto RMM account and ConnectWise PSA, limited to one test site with `ignoreSites`:

1. **Preview.** With `preview` true, it signed in to Datto RMM and read the test site. It skipped the `Managed` and `OnDemand` placeholder sites and the ignored sites. It found one laptop that Datto RMM last saw 49 days earlier, and matched the site to the PSA company with the same name. It returned `pending_confirmation` with one ticket to open, and wrote nothing.
2. **Live run.** With no `preview`, it opened one ticket, `Offline devices: 1 not seen for 7+ days`, listing the laptop with its suggested first step, and added the internal note with the day's marker.
3. **Rerun.** The same input again returned `success` with `ticketsUnchanged` 1. It found the open ticket and the day's note, and wrote nothing new.
4. **Ticket redirect.** ConnectWise answered the new ticket and the note with a redirect. The workflow searched for the ticket and read the note back, and sent neither again.

That proves the Datto sign-in body, a readable `lastSeen`, the `Laptop` device type, `online: false`, the placeholder site skip, and the ConnectWise company search, ticket create, open-ticket search and note read.

## Not yet proven live

Everything below passes the strict-mode mock harness, but hasn't been run against a real account yet. The `Unverified` comments in `src/datto.ps1` and `src/find.ps1` predate the live run: the sign-in body, `lastSeen` format, `Laptop` type and placeholder-site skip they mention are now proven (see above), and the rest still apply:

- **Servers.** The test site had no server, so the `Server` and `ESXi Host` types, the `serverOfflineHours` threshold, servers at the top of the ticket and `serverPriority` haven't run live.
- **Other `deviceType.category` values.** Only `Laptop` has been seen live. The rest are mapped from the names the Datto web UI shows (Desktop, Server, ESXi Host, Printer, Network Device, Mobile), with `deviceClass` as a fallback. A device with no type is skipped and counted in the warnings.
- **`suspended` and `deleted` on device records.** No suspended or deleted device was in the test. The flags are read when present; if Datto names them differently, those devices would be checked like any other.
- **Updating an open ticket.** The live test opened a ticket and reran with nothing changed. A note for newly offline or recovered devices, and the "everything recovered" note, haven't run live.
- **Retry-After.** No `429` came up. Datto doesn't say it sends one; the workflow uses it when present and waits 60 seconds otherwise (Datto's advice). A `403` after repeated 429s means Datto blocked the runner's address for about 5 minutes.
- **Whole site down.** Only the mock harness has seen it. The live test site had one laptop and no server, so it can't trigger there. The three-in-four share is a starting value, not tuned against a real outage.
- **Wake-on-LAN, all of it.** No wake-up has been sent live. In particular:
  - the API v2 calls (audit `nics[]` with `macAddress` and `ipv4`, the components list, the quick job body and its `job.uid` reply, and `jobDeploymentStatus`) follow the API v2 spec, not a live run;
  - the extra Datto rights the API user needs;
  - the same-network check assumes a /24, because the audit gives addresses but not masks;
  - the component itself (`datto-component/wake-on-lan.ps1`) has only been checked for its packet and broadcast maths;
  - whether a woken desktop checks in to Datto within `wakeWaitMinutes`.
- **The other five PSAs.** Ticket create, company search, the open-ticket search (`Find-PsaTickets` with text `Offline devices`) and note reads are proven only on ConnectWise PSA. Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk follow `_shared/psa.ps1` and `_shared/psa-tickets.ps1`; see the `Unverified` list in the [_shared README](https://github.com/cloudradial/Automations/tree/main/_shared#calls-not-yet-proven-live). Kaseya BMS has no ticket text search, so its open tickets are read and matched here.
