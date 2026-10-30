# Get a Weekly List of Warranty and Ownership Gaps

Every week your team gets one email that grades every managed computer against hardware refresh standards, lists warranty gaps, and flags clients with no account manager. Refresh and ownership conversations stop slipping through the cracks.

## What happens

Once a week, the automation looks at every client and every computer in CloudRadial and sorts each computer into a plain category:

- **Replace:** old, too little memory, or stuck on an operating system that can't move to Windows 11
- **Upgrade in place:** on Windows 10, but the hardware can run Windows 11
- **Plan replacement:** old enough that it's time to plan its replacement
- **Retain:** fine for now, but the warranty has expired or ends soon, or memory is low
- **Needs data:** not enough details to decide
- **Human review:** servers, which a person should judge
- **Virtual machines:** ones with an old operating system or low memory

The most urgent computers are marked **Critical**. It also counts warranty gaps (expired, ending within 90 days, or no date at all) and lists clients with no account manager.

Your team gets one email with the headline numbers, a "Start here" list, a table by client, and up to three of the most urgent computers per client. The subject line shows how many critical computers there are, so you know at a glance how big this week's list is.

## What happens behind the scenes

- **Read-only.** Nothing in CloudRadial is changed.
- **Same rules as Endpoint LifeCycle Manager.** If you use it too, this email and its Hardware Refresh Planner cards always agree.
- **No guessing.** If the account manager details aren't available, the email says so instead of guessing.
- **Deleted clients are left out.**
- **No AI in the audit itself**, so it works with any AI provider. An agent only sends the email.

## Works with

- **CloudRadial:** the computer and client details come from your CloudRadial portal.
- **ScalePad:** optional. If you use the ScalePad sync, it fills in warranty dates.
- **Postmark:** sends the email.
- **Your PSA:** it can post the result to a PSA ticket instead of an email, but that needs a change to the workflow. The technical details explain how.

## What you need

- AutomationAI, with your CloudRadial API details added to your runner
- A Postmark account with a verified sender address, connected in AutomationAI
- The **Deliver Result** agent, which sends the email

## Set it up

1. Import the [Deliver Result agent](https://github.com/cloudradial/Automations/tree/main/deliver-result) on **Agents > Custom > Import**, if you don't have it yet.
2. Install and connect the **Postmark** extension, and set the sender address Deliver Result should use.
3. Take Deliver Result out of preview mode. It starts out describing the email without sending it. Its [guide](https://github.com/cloudradial/Automations/blob/main/deliver-result/README.md#dry-run-and-going-live) shows how to go live.
4. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/weekly-fleet-audit/v1.0.0).
5. Go to **Workflows > Import** and upload it.
6. Click **Publish**, then **Deploy**.
7. Add your CloudRadial API details to your runner. The [technical details](https://github.com/cloudradial/Automations/tree/main/weekly-fleet-audit#required-runner-key-vault-secrets) list exactly what to add.
8. Schedule it as a weekly **Routine**, with the email addresses that should get the audit. You can list one address or several.

**Test it.** Run the workflow once from **Test** with your own email address, and check the audit arrives.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/weekly-fleet-audit#technical-details) cover the exact grading rules, what each step does, and how to deliver to a PSA ticket instead.

---

## Technical details

**Formerly:** Weekly Fleet Audit | **Marketplace ID:** AAI-00032 | **Type:** Workflow (PowerShell audit + Deliver Result agent) | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/weekly-fleet-audit/v1.0.0).

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **Deliver Result** agent, [`deliver-result.agent.yml`](https://github.com/cloudradial/Automations/blob/main/deliver-result/deliver-result.agent.yml) from [Send Automation Results Wherever Your Team Works](https://github.com/cloudradial/Automations/tree/main/deliver-result), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`weekly-fleet-audit.yml`](https://github.com/cloudradial/Automations/blob/main/weekly-fleet-audit/weekly-fleet-audit.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `weekly-fleet-audit.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/weekly-fleet-audit/weekly-fleet-audit.yml) |
| Download `weekly-fleet-audit.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/weekly-fleet-audit/v1.0.0) |
| Needs the agent | [Deliver Result](https://github.com/cloudradial/Automations/tree/main/deliver-result) |
| All files in this automation | [weekly-fleet-audit](https://github.com/cloudradial/Automations/tree/main/weekly-fleet-audit) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/weekly-fleet-audit) |
| Source (for maintainers) | [src/](https://github.com/cloudradial/Automations/tree/main/weekly-fleet-audit/src) |
| Marketplace listing | [AAI-00032](https://automations.cloudradial.com/marketplace/AAI-00032) |

## How it works

A CloudRadial **AutomationAI workflow** that audits the fleet on a schedule and emails the result. The audit is a PowerShell step with no AI, so it has no turn limit and works on any AI provider. The shared [Deliver Result](https://github.com/cloudradial/Automations/tree/main/deliver-result) agent sends the email. `Start → Run inputs → PowerShell (Fleet Audit) → PowerShell (Build Email) → Agent (Send Audit) → End`.

The audit grades computers with the same rules as [Endpoint LifeCycle Manager](https://github.com/cloudradial/Automations/tree/main/endpoint-lifecycle-manager), so the email and the Endpoint Hardware Refresh Planner cards always agree:

| Category | When |
|---|---|
| **Replace** | 5 or more years old, an unsupported OS that can't take Windows 11, or under 4 GB of memory |
| **Upgrade in place** | Unsupported OS (Windows 10), but the hardware is Windows 11 capable |
| **Plan replacement** | 3 or more years old |
| **Retain** | Younger, but the warranty is expired or ending within 90 days, or memory is under 8 GB |
| **Needs data** | No age, warranty or OS details to decide on |
| **Human review** | Servers |
| **Virtual machines** | VMs with an unsupported guest OS or low memory |

Each flagged computer also gets a tier. **Critical** means 7 or more years old, Windows 10 or older, macOS 12 or older, or under 4 GB of memory. Age comes from `manufacturedDate`, or is estimated from `biosDate` / `cpuDate`. Warranty comes from the endpoint's `expirationDate`. The [ScalePad sync](https://github.com/cloudradial/Automations/tree/main/scalepad-cloudradial-sync) fills it in if you use ScalePad.

## Set up

Do these in order. The workflow won't send anything until step 2 is done.

1. **Import the workflow.** On **Workflows → Import**, upload [`weekly-fleet-audit.yml`](https://github.com/cloudradial/Automations/blob/main/weekly-fleet-audit/weekly-fleet-audit.yml), then **Publish** and **deploy** it to your runner. Add the CloudRadial secrets below to the runner Key Vault.
2. **Set up Deliver Result.** This is the step that sends the email:
   1. On **Agents → Custom → Import**, upload [`deliver-result.agent.yml`](https://github.com/cloudradial/Automations/blob/main/deliver-result/deliver-result.agent.yml) (slug `deliver-result`).
   2. Install and connect the **Postmark** extension, and add its secrets to the runner Key Vault: `Postmark-ServerToken`, `Postmark-FromEmail`, `Postmark-ApiUrl`.
   3. Set Deliver Result's `fromEmail` variable to a verified Postmark sender, or leave it empty to use `Postmark-FromEmail`.
   4. **Take it out of dry run.** Deliver Result ships with `dryRunDefault: true`, which describes the email and sends nothing. Follow [Dry run and going live](https://github.com/cloudradial/Automations/blob/main/deliver-result/README.md#dry-run-and-going-live) to re-import it live.
3. **Test it.** Run the workflow from **Test** with the recipients as the Trigger input (see [Inputs](#inputs)), and confirm the email arrives.
4. **Schedule it.** Attach a weekly **Routine**, with the same input.

## Inputs

| Field | Required | What it does |
|---|---|---|
| `toEmail` | Yes | Who gets the audit: one address, a comma list, or a JSON list. |

Example: `{"toEmail": "team@yourmsp.com, service@yourmsp.com"}`

The run stops at **Run inputs** with a clear message if `toEmail` is missing.

## What it does

1. **Run inputs** reads `toEmail` from the run input.
2. **Fleet Audit** (PowerShell) reads every company and endpoint from the CloudRadial API, read-only. It grades each computer with the rules above and counts warranty gaps (expired, ending within 90 days, no date). It also checks each company's account manager. Endpoints of deleted companies are left out. If the API doesn't return the account manager field, the email says so instead of guessing.
3. **Build Email** (PowerShell) turns the results into the email:
   - headline numbers
   - a "Start here" list
   - a by-company table
   - up to three of the most urgent computers per company

   The subject shows the critical count, for example `Weekly Fleet Audit - 2026-10-01 - 4 critical`.
4. **Send Audit** (agent) runs Deliver Result with `channel: email`, which sends through Postmark. Its inputs are pre-bound: recipients from Run inputs, subject and body from Build Email. It has `autoApprove: true`, so a scheduled run doesn't wait in the Inbox.

To deliver somewhere else - a PSA ticket instead of email - change `channel` in Build Email to `psa`, add the company routing fields, and set Send Audit's `allowedExtensions` to your PSA extension.

## Editing it

The two PowerShell steps are generated. Edit `src/audit.ps1` or `src/email.ps1`, never the script inside the `.yml`. The grading rules aren't copied by hand: `build-audit.js` pulls the block between `# ---- shared: begin` and `# ---- shared: end ----` from [`endpoint-lifecycle-manager/src/elm.ps1`](https://github.com/cloudradial/Automations/blob/main/endpoint-lifecycle-manager/src/elm.ps1). So change a rule there, then rebuild both workflows.

```
cd weekly-fleet-audit/src
npm install
pwsh ./test.ps1 -HtmlOut ./preview.html   # mock API, strict mode; open preview.html to see the email
node build-audit.js                       # writes ../weekly-fleet-audit.yml
pwsh ./test.ps1 -Built                    # re-runs the test on the scripts embedded in the .yml
```

`test.ps1 -NoAccountManager` simulates an API without the account manager field, and `-Empty` a portal with no endpoints. The harness also checks that the email body is safe to drop into Send Audit's JSON binding: no double quotes, backslashes or newlines.

## Required Runner Key Vault secrets

| Secret | For |
|---|---|
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | The Fleet Audit step's API reads |
| `Postmark-ServerToken`, `Postmark-FromEmail`, `Postmark-ApiUrl` | The Postmark extension Deliver Result sends through |
