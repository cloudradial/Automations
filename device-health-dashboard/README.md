# Device Health Dashboard from Datto RMM

A branded dashboard in your client's portal that shows how healthy their computers are right now: a health score, patch status, antivirus, reboots pending, devices that stopped checking in, and the fixes Datto RMM made automatically. It refreshes every hour from Datto RMM.

## What your clients see in the portal

A **Device Health** dashboard with four widgets:

- **Device Health Overview:** health score (Excellent, Good, Fair or Poor) and six tiles: managed devices, online now, fully patched, antivirus OK, reboot pending, not checking in.
- **Patch Compliance:** devices by patch status, plus operating systems.
- **Needs Attention:** up to six devices with a plain-language issue and a priority.
- **Automatic Remediation:** fixes this week, success rate, and the latest fixes with their result.

## What happens behind the scenes

- **Reads every device** from Datto RMM (optionally only some sites) and skips printers and network devices.
- **Scores health:** 40% patching, 30% antivirus, 20% checking in, 10% reboots.
- **Fixes patch problems:** on devices you name, it runs the **Windows Update Toolkit [WIN]** component as a quick job, at most once a day per device, and logs the result.
- **Writes the @DH company tokens** the widgets display, and can send a Signal summary.
- **Your other devices are never touched:** fixes only run on the devices named in `remediateDevices` (or every device with `remediateAll`).

## Works with

Datto RMM. Signal for the optional summary.

## What you need

- AutomationAI, with Datto RMM and CloudRadial connected
- **Windows Update Toolkit [WIN]** added to your Datto RMM component library (for fixes)
- A **Routine** to run it on a schedule (hourly works well)

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://raw.githubusercontent.com/cloudradial/Automations/main/device-health-dashboard/device-health-dashboard.yml) (right-click > Save link as).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.
4. Run it once with **Test** and `"confirm": true` for your client (input below). That creates the tokens.
5. Add a **Routine**: hourly, with the same input and `"remediate": false` if you only want fixes when you ask.

```json
{"companyId": 1, "sites": ["Contoso Ltd"], "remediateDevices": ["CONTOSO-LT-031"], "notifyUsers": [], "confirm": true}
```

**In your UCP portal, add the dashboard** for the client: **Account > Dashboards > Add Dashboard**, named **Device Health**, then four **Custom HTML** widgets (2 wide by 3 high, in a 2x2 grid) with the HTML from [widgets/widgets.json](https://github.com/cloudradial/Automations/blob/main/device-health-dashboard/widgets/widgets.json). Or create it through the API: `POST /v2/dashboard`, then `POST /v2/dashboard/{id}/widget?companyId=` for each widget with `{"type": 2, "title", "html", "width": 2, "height": 3, "x", "y"}`.

**Test it.** Reload the dashboard: no `@DH` text should show, and the Updated time should match your run.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/device-health-dashboard#technical-details) cover the inputs, tokens and widgets.

---

## Technical details

**Marketplace ID:** CRA-00021 | **Type:** Workflow (one PowerShell step, no AI) plus a 4-widget dashboard | **Version:** 1.0.0

## Files

| What | Link |
|---|---|
| View `device-health-dashboard.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/device-health-dashboard/device-health-dashboard.yml) |
| Download `device-health-dashboard.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/device-health-dashboard/device-health-dashboard.yml) |
| Widget HTML and demo token values | [widgets/](https://github.com/cloudradial/Automations/tree/main/device-health-dashboard/widgets) |
| Step source, widget template builder and build script | [src/](https://github.com/cloudradial/Automations/tree/main/device-health-dashboard/src) |

## Inputs

| Input | Default | What it does |
|---|---|---|
| `companyId` | required | The CloudRadial company whose tokens to write |
| `sites` | all sites | Datto RMM site names to include |
| `remediate` | `true` | Start fixes (only on allowed devices) |
| `remediateDevices` | none | Hostnames allowed to get a fix |
| `remediateAll` | `false` | Allow fixes on every eligible device |
| `maxFixes` | `3` | Most fixes started in one run |
| `fixComponent` | `Windows Update Toolkit [WIN]` | The Datto component used as the fix |
| `notifyUsers` | none | CloudRadial user ids for a Signal summary |
| `timeZone` | `America/New_York` | Time zone for the Updated time |
| `cloudradial_company` | none | Use that portal's `CloudRadial-*-<name>` runner secrets |
| `confirm` | `true` | `false` previews without writing or fixing |

## The widgets

The widget HTML never changes; every value is a company token (`@DHScoreNum`, `@DHPatchPct`, `@DHNeedName1` and so on, 108 in all). The portal's HTML editor strips `<svg>`, `<script>` and `<style>`, so the widgets use inline styles only. `src/build_widgets.py` regenerates `widgets.json`, `demo-tokens.json` (fictitious values) and a local `preview.html`. The fix history is kept in the `@DHHistory` token.

## Required runner Key Vault secrets

| Secret | Used for |
|---|---|
| `Datto-ApiUrl`, `Datto-ApiKey`, `Datto-ApiSecret` | Devices, components and fixes |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Tokens and the Signal |

## Notes

- The webhook ships disabled. Run it from a Routine or manually.
- Tested live in the AutomationAI test tenant on 2026-11-18 and 2026-11-19: 108 tokens written, a Windows Update repair started and logged, and the hourly Routine kept the dashboard current. Build with `node src/build.js`.
