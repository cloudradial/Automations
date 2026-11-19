# Software Requests Your RMM Installs

A client picks an app and a computer on a portal form, and Datto RMM installs it. No technician touches it: the ticket gets a note with the result and the requester gets a Signal desktop notice when it's done.

## What your clients see in the portal

A **Request Software** form with two dropdowns: **Which app do you need?** (for example Google Chrome, Zoom, 7-Zip, Notepad++) and **Which computer?** (their own company's computers). After they submit, a Signal arrives on their desktop: "Zoom is installed".

## What happens behind the scenes

- **Matches the app to a Datto RMM component** from the ComStore, with the right install options.
- **Finds the computer in Datto RMM** by name. If two devices share the name, the online one wins.
- **Runs the install as a quick job** and waits up to 6 minutes for the result.
- **Already installed?** It says so instead of reporting a failure.
- **Offline computer?** Nothing is installed, and the requester is told to turn it on and resubmit.
- **Notes the ticket** with the app, the computer, the result and the Datto job id, and **sends the requester a Signal**.

## Works with

Datto RMM (Windows components) and ConnectWise PSA for the ticket note. Signal needs to be turned on in your portal.

## What you need

- A UCP portal with **Actions** on your request forms
- AutomationAI, with Datto RMM, ConnectWise and CloudRadial connected
- The ComStore components for each app added to your Datto RMM component library (the defaults are **Google Chrome [WIN]**, **Zoom Workplace [WIN]**, **7-Zip [WIN]** and **Notepad++ [WIN]**)
- An `@endpoints` company token listing each client's computers. [Let Users Pick Their Computer on Portal Forms](https://github.com/cloudradial/Automations/tree/main/endpoint-names-token) keeps it current.

## Set it up

**Once, in Datto RMM:** open **Automation > ComStore** and add the components for the apps you'll offer.

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://raw.githubusercontent.com/cloudradial/Automations/main/software-install-datto/software-install-datto.yml) (right-click > Save link as).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.

**In your UCP portal, add the Request Software form** (category **Software**) with these questions:

1. **Comment**, "Subject", default value `Software request`, ticked as the subject.
2. **Multiple choice dropdown**, "Which app do you need?", options `Google Chrome,Zoom,7-Zip,Notepad++`, required. Field ID `softwareApp`.
3. **Multiple choice dropdown**, "Which computer?", options `@endpoints`, required. Field ID `deviceName`.
4. **Action**, "Install the software", and pick **Software Install (Datto RMM)**.

The [form file](https://github.com/cloudradial/Automations/blob/main/software-install-datto/forms/request-software.json) has every setting, including a branded header.

**Test it.** Submit the form for an app that isn't installed yet on a test computer that's online. Watch the job in Datto RMM > **Jobs**, then check the ticket note and the Signal.

**To have the client approve requests,** put the form in a category only the client's approvers can see, or turn on approval on the form.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/software-install-datto#technical-details) cover the app catalog, the inputs and the secrets.

---

## Technical details

**Marketplace ID:** CRA-00019 | **Type:** Workflow (one PowerShell step, no AI) | **Version:** 1.0.0

## Files

| What | Link |
|---|---|
| View `software-install-datto.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/software-install-datto/software-install-datto.yml) |
| Download `software-install-datto.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/software-install-datto/software-install-datto.yml) |
| Portal form | [forms/request-software.json](https://github.com/cloudradial/Automations/blob/main/software-install-datto/forms/request-software.json) |
| Step source and build script | [src/](https://github.com/cloudradial/Automations/tree/main/software-install-datto/src) |

## How it works

```
Start -> Install the requested software -> End
```

The step reads the form's answers by Field ID (`softwareApp`, `deviceName`), matches the app in its catalog, signs in to Datto RMM, finds the component and the device, and runs `PUT /api/v2/device/{uid}/quickjob`. It polls `/api/v2/job/{job}/results/{device}` every 15 seconds. On a failure it reads the job's output to tell "already installed" from a real failure.

### Adding an app

Add the component from the ComStore, then add one line to `$catalog` in [src/install.ps1](src/install.ps1): the dropdown label, the exact component name and its variables. Add the same label to the form's dropdown options, then run `node src/build.js`.

```powershell
'Adobe Acrobat Reader' = @{ component = 'Adobe Acrobat Reader DC [WIN]'; vars = @{} }
```

## Inputs

| Input | Default | What it does |
|---|---|---|
| `softwareApp`, `deviceName` | from the form | The app and the computer |
| `defaultDevice` | none | Computer to use when the form has no computer question |
| `waitMinutes` | `6` | How long to wait for the Datto job before reporting "still running" |
| `cloudradial_company` | none | Use that portal's `CloudRadial-*-<name>` runner secrets for the Signal |
| `confirm` | `true` | `false` previews without installing |

## Required runner Key Vault secrets

| Secret | Used for |
|---|---|
| `Datto-ApiUrl`, `Datto-ApiKey`, `Datto-ApiSecret` | Finding the device and running the install |
| `CW-ApiUrl`, `CW-CompanyID`, `CW-PublicKey`, `CW-PrivateKey`, `CW-ClientId` | The ticket note |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | The Signal |

## Notes

- The webhook ships disabled. The form's **Action** question runs it.
- ConnectWise's automation host can redirect writes. A redirect after the note is treated as saved.
- Built and tested live in the AutomationAI test tenant on 2026-11-18 and 2026-11-19: Google Chrome installed through the workflow, and a Zoom request from the portal form reported "already installed". Build with `node src/build.js`.
