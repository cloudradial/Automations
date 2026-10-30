# Ticket Devices That Have Dropped Off the RMM

Once a day, every managed device that Datto RMM hasn't seen for too long lands on one PSA ticket per client, servers first, with a suggested first step for each device. Nobody has to sweep the RMM by hand, and a retired laptop or a dead server stops going unnoticed.

## What happens

**Once a day, in the background.** The automation checks every client site in Datto RMM and picks out devices that have been offline too long: 7 days for workstations and laptops, 4 hours for servers.

**Each client gets one ticket.** Your team sees a ticket per client listing the offline devices, with servers at the top. Each device shows when it was last seen and what to try first: check power and network, ask the client whether it was retired, or remove it from the RMM.

**Servers get attention sooner.** A ticket with a server on it opens at high priority.

**It spots a whole site going down.** If most devices at a site drop off at once, including its servers, the ticket starts with a line telling the tech to check the site's power, internet and firewall first.

**The ticket stays up to date.** Later runs add a short note when something new goes offline or comes back, instead of opening another ticket. When everything is back, the note asks the tech to close the ticket.

## What it protects

- **No duplicate tickets.** One open ticket per client, and running it again the same day writes nothing new.
- **No guessing.** A Datto site is only ticketed to a PSA client with the same name, or one you map it to. Anything else is listed in the run summary for you to sort out.
- **Datto RMM is never changed.** The automation only reads from it.
- **No noise.** Phones, printers and network gear are left out unless you ask for them, and Datto's own placeholder sites are skipped.

## Works with

Datto RMM, plus ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro or Zendesk.

- **Proven live:** Datto RMM with ConnectWise PSA. The other five PSAs pass the same tests but haven't run against a real account yet, so start with a preview run (step 4 below).
- **Other RMMs:** not supported yet.

## What you need

- AutomationAI, with your PSA connected on your runner
- A Datto RMM API user that can view all sites and devices (read-only is enough)
- A PSA login for the automation that can read companies, create tickets and add internal notes

## Set it up

**In AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/offline-device-sweep/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. Add your Datto RMM API details to the runner, next to your PSA connection, then click **Publish** and **Deploy** to that runner.
4. **Preview first.** Open **Test** and run it with preview turned on (the first step's test input already does this). It lists which devices would be ticketed for each client, and any sites it couldn't match, and changes nothing.
5. **Match any odd site names.** If a Datto site is named differently from the client in your PSA, add it to the site map setting and preview again.
6. **Schedule it.** Attach a daily **Routine**, early in the morning before your service desk starts.

**Optional settings.** You can change how long a workstation or server must be offline, include phones, printers or network devices, leave out sites you don't want checked, pick the ticket priorities, and choose the board or queue new tickets go to.

**Test it.** Run it live, open one of the new tickets in your PSA and check the device list, then run it again straight away and confirm nothing new was written.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/offline-device-sweep#technical-details) cover how devices are picked, the site-down check, every setting and its default, the secrets and permissions, and what has been proven live.

---

## Technical details

**Formerly:** Offline Device Sweep (tracker 3.3) | **Marketplace ID:** AAI-00066 | **Type:** Workflow (PowerShell, no AI, runs on a schedule) | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/offline-device-sweep/v1.0.0).

| What | Link |
|---|---|
| View `offline-device-sweep.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/offline-device-sweep/offline-device-sweep.yml) |
| Download `offline-device-sweep.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/offline-device-sweep/v1.0.0) |
| All files in this automation | [offline-device-sweep](https://github.com/cloudradial/Automations/tree/main/offline-device-sweep) |
| Build source (`src/`) | [offline-device-sweep/src](https://github.com/cloudradial/Automations/tree/main/offline-device-sweep/src) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/offline-device-sweep) |
| Works with | [RMM Agent](https://github.com/cloudradial/Automations/tree/main/rmm-agent) (same Datto RMM secrets), [Waiting-on-Client Nudge](https://github.com/cloudradial/Automations/tree/main/waiting-on-client-nudge) (same schedule and preview pattern) |
| Shared PSA code | [`_shared/psa.ps1` and `_shared/psa-tickets.ps1`](https://github.com/cloudradial/Automations/tree/main/_shared) |

## How it works

A Routine runs the workflow once a day. It reads Datto RMM and works in ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk, using the PSA named by the `PSA-Type` secret.

`Start → Find offline devices → Open or update tickets → End`

1. **Find offline devices** changes nothing anywhere. It:
   - signs in to Datto RMM and reads every site, then every device at each site (all pages);
   - skips Datto's placeholder sites (`Deleted Devices`, `Managed`, `OnDemand`) unless `companyMap` names them, any site in `ignoreSites`, and suspended or deleted devices;
   - keeps a device when Datto says it is offline and it was last seen longer ago than the threshold for its category: `offlineDays` (7) for workstations and laptops, `serverOfflineHours` (4) for servers. Mobile devices, printers and network devices are skipped unless `includeCategories` asks for them;
   - counts the online devices at each site, to spot a site that may be down as a whole. A site counts as down when it has at least two checked devices, every server there is past `serverOfflineHours`, and at least three in four of its checked devices are offline right now (even those still under their own threshold);
   - matches each site to a PSA company: the `companyMap` entry first, otherwise exactly one PSA company with exactly the site's name. A site with no match, or with two companies of the same name, is never ticketed to a guess. It is listed in `unmatchedSites` and in the warnings. Several sites that map to one company share one ticket;
   - looks for this workflow's open ticket for each company (an open ticket whose summary starts with `Offline devices:`) and reads its notes to see which devices were offline last time.
2. **Open or update tickets** acts on what step 1 found:
   - **No open ticket and something offline:** opens one ticket for the company, with summary such as `Offline devices: 3 not seen for 7+ days`. Servers get their own line at the top, and a ticket with a server in it opens at `serverPriority` (high); otherwise at `priority` (medium). An internal note with the marker follows.
   - **An open ticket and the list changed:** adds one internal note saying what is newly offline, what is still offline, and what recovered (back online, checked in recently, suspended, or no longer in Datto RMM). When everything recovered, the note says so and asks the tech to close the ticket. A newly offline server is called out so the tech can raise the priority.
   - **An open ticket and nothing changed:** writes nothing, so the ticket doesn't fill up with the same list every day.

**When a whole site may be down.** If a site looks down, the ticket (or the update note) starts with one line before the device list, for example `The whole Contoso site may be down: Datto RMM shows 9 of its 10 devices offline right now, including its only server.` It asks the tech to check the site's power, internet connection and firewall before working through the devices one by one. The number counts every offline device at the site, so it can be higher than the list below it, which only shows devices past their threshold. A site with no server checked, or a single device, never gets this line. If a site goes down while its ticket is already open, the next run adds a note with the line even when the device list hasn't changed (the rest of the site can go offline while still under its own threshold), and only once: a note that already says so isn't repeated.

Each device line gives the hostname, type, OS, when it was last seen (date, and hours or days ago), and a suggested first step: check power and network (servers, and devices offline under 30 days), confirm with the client whether it has been decommissioned (30 to 90 days), or confirm and remove it from Datto RMM if it looks retired (90 days or more).

**How it knows what it already did.** Every internal note it writes ends with a marker for the day, `[offline-device-sweep: 2026-10-16]`, and a plain line, `Offline in this check: CONTOSO-PC01, CONTOSO-SRV01.` The next run compares that line with what is offline now to find newly offline and recovered devices. Don't edit or delete these lines.

**Safe to run again.** A rerun on the same day (an Action Runs **Retry**, or a manual run after the Routine) finds the ticket by its summary and the day's marker, so it never opens a second ticket and never writes the same day's note twice. If you close the ticket, the next run that finds devices offline opens a new one.

## Download & import

**Download the workflow:** [`offline-device-sweep.yml`](https://github.com/cloudradial/Automations/releases/tag/offline-device-sweep/v1.0.0)

Then in AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), **Publish**, **Deploy** to the runner that holds the secrets, and attach a daily **Routine** (the schedule isn't part of the export). Full steps are under [Import & test](#import--test).

## Inputs

All inputs are optional. A Routine sends no input, so every one has a default. The snake_case names (`offline_days`, `server_offline_hours`, `include_categories`, `ignore_sites`, `company_map`) work too.

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

**Why `preview` and not `confirm`:** like the Waiting-on-Client Nudge, this card runs on a schedule with nobody watching, so the default is to act. `preview: true` is the dry-run switch. The first step's Test Input is `{"preview": true}`.

Bad input fails closed: the run stops with a plain sentence before anything is read or written.

## Output

| Field | What it is |
|---|---|
| `status` | `success`, `incomplete` when any company failed, `pending_confirmation` for a preview with tickets to open or update, or `error` |
| `message` | One plain sentence |
| `preview` | Whether this was a preview |
| `counts` | `sites`, `devicesChecked`, `offline`, `sitesDown`, `ticketsCreated`, `ticketsUpdated`, `ticketsUnchanged`, `wouldCreate`, `wouldUpdate` (preview), `unmatchedSites`, `failed` |
| `companies` | One row per company: `company`, `companyId`, `sites`, `offline`, `servers`, `sitesDown` (Datto sites that look down), `action` (`created`, `updated`, `unchanged`, `would create`, `would update`, `failed`), `ticketId`, `ticketUrl`, `devices`, `recovered`, `summary`, `text` (the ticket body or note), `error` |
| `unmatchedSites` | Each Datto site with no PSA company match: `site`, `offline`, `reason` |
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

- **Datto RMM:** a dedicated API user (**Setup > Users**, with API access enabled; its API key and secret key go in the secrets). Give it a security level that can **view** all sites and their devices. Nothing else is needed: the workflow only reads `GET /api/v2/account/sites` and `GET /api/v2/site/{siteUid}/devices`, and never writes to Datto RMM. If its access is limited to some sites, only those are swept. Datto allows 600 reads a minute across the whole account; a large account uses one read per 250 sites plus one per 250 devices at each site. A `429` waits (Datto's `Retry-After`, or 60 seconds) and tries again.
- **PSA:** the API account needs to read companies, read and create tickets, and read and add internal notes. ConnectWise also reads ticket priorities (Inquire access) to set the priority exactly; without it the priority comes from impact and urgency, with a warning. A missing permission stops that company's ticket with a plain sentence naming the HTTP status.
- **Microsoft Graph:** none.

## Import & test

1. **Import** `offline-device-sweep.yml` on **Workflows → Import**. Add the secrets above to the runner Key Vault, then **Publish** and **Deploy** to that runner.
2. **Preview first.** Run it from **Test** with `{"preview": true}` (the first step's Test Input). Check `companies`: the right devices for each client, servers at the top, and the summary and body under `text`. Check `unmatchedSites` and `warnings`, and add any site whose name differs from the PSA to `companyMap`.
3. **One run live.** Run it with no input (or with your `companyMap` and `ignoreSites`), then open one of the new tickets in the PSA: it should list the devices, and have an internal note ending with `[offline-device-sweep: <today>]`.
4. **Run it again straight away.** Nothing new should be written (`ticketsUnchanged` goes up). That proves a rerun never opens a second ticket.
5. **Schedule it daily.** Attach a **Routine** that runs once a day, early in the morning before the service desk starts, with no input, or with your own `offlineDays`, `serverOfflineHours`, `companyMap` and `ignoreSites`. Once a day is the intended cycle: a second run the same day only finds the day's note already there.

## Editing it

The two PowerShell steps are generated. Edit the files in `src/`, never the script inside the `.yml`:

| File | What it is |
|---|---|
| `src/find.ps1` | Step 1: input, Datto read, thresholds, site-down check, company match, open-ticket lookup |
| `src/ticket.ps1` | Step 2: open or update tickets, preview, run summary |
| `src/common.ps1` | Marker, ticket and note text, helpers used by both steps |
| `src/datto.ps1` | The read-only Datto RMM API v2 client (sign-in, paging, 429 retry, device categories) |
| `src/build.js` | Assembles the `.yml`: pastes `_shared/psa.ps1` and `_shared/psa-tickets.ps1` (through `_shared/inject.js`), then `common.ps1` and `datto.ps1` |
| `src/test.ps1` | Strict-mode harness on `_shared/tests/mock.ps1`: mocked Datto RMM, ConnectWise, Autotask and Zendesk |

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
- **The other five PSAs.** Ticket create, company search, the open-ticket search (`Find-PsaTickets` with text `Offline devices`) and note reads are proven only on ConnectWise PSA. Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk follow `_shared/psa.ps1` and `_shared/psa-tickets.ps1`; see the `Unverified` list in the [_shared README](https://github.com/cloudradial/Automations/tree/main/_shared#calls-not-yet-proven-live). Kaseya BMS has no ticket text search, so its open tickets are read and matched here.
