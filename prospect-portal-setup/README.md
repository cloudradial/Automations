# Set Up a Prospect in the Portal

Before a prospect signs, give them their own CloudRadial portal company with a short, branded set of recommendations waiting in their Planner. It shows them what working with you looks like, and it needs nothing from them: no PSA record and no Microsoft 365 access.

## What your prospect sees in the portal

Four recommended cards on their **Planner**, ready to walk through on the sales call:

- **Managed Services proposal:** day-to-day support, monitoring and patching for every user and device.
- **Email security review:** a check of how their domain protects against spoofed email (SPF, DKIM and DMARC), which you can run from the outside before they sign.
- **Microsoft 365 security baseline:** a Secure Score assessment once they connect Microsoft 365.
- **Portal access for your team:** one place for tickets, requests, training and reports.

## What happens behind the scenes

- It creates the prospect's company in CloudRadial, adds their domain, and puts the company in the group you name (for example **Prospects**).
- If the company is already there, it uses it and only adds what's missing, so running it twice never makes a second company or duplicate cards.
- The PSA isn't touched and no ticket is opened. When they sign, run [New Client Onboarding](https://github.com/cloudradial/Automations/tree/main/new-client-onboarding) with the same company to link the PSA and open the onboarding ticket.
- A first run previews everything and changes nothing until you say so.

## Works with

Any UCP portal. No PSA or Microsoft 365 connection is needed.

## What you need

- A UCP portal, and AutomationAI with a runner that has your CloudRadial API details

## Set it up

1. **Download** the [workflow file](https://raw.githubusercontent.com/cloudradial/Automations/main/prospect-portal-setup/prospect-portal-setup.yml) (right-click > Save link as).
2. In AutomationAI, go to **Workflows > Import** and upload it. Click **Publish**, then **Deploy**.
3. **Preview.** Open the workflow, click **Run** with the prospect's name and domain. Nothing changes: the result lists what it would create.

   ```json
   {"company_name": "Contoso Ltd", "primary_domain": "contoso.com", "company_group": "Prospects"}
   ```

4. **Run it for real** with the same input plus `"confirm": true`.
5. Open the prospect's Planner in the portal and check the four cards before the call.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/prospect-portal-setup#technical-details) cover every input, the secrets and how it was tested.

---

## Technical details

**Formerly:** Land: Set Up Prospect in Portal (Nick's Test) | **Marketplace ID:** CRA-00027 | **Type:** Workflow (PowerShell, no AI) | **Version:** 1.0.0

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `prospect-portal-setup.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/prospect-portal-setup/prospect-portal-setup.yml) |
| Download `prospect-portal-setup.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/prospect-portal-setup/prospect-portal-setup.yml) |
| Step source, build script and test harness (shared with New Client Onboarding) | [new-client-onboarding/src/](https://github.com/cloudradial/Automations/tree/main/new-client-onboarding/src) |
| All files in this automation | [prospect-portal-setup](https://github.com/cloudradial/Automations/tree/main/prospect-portal-setup) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/prospect-portal-setup) |

## How it works

This is [New Client Onboarding](https://github.com/cloudradial/Automations/tree/main/new-client-onboarding) with its `steps` input defaulting to `portal,landcards`. Both workflows are built from the same four step scripts in `new-client-onboarding/src/` by `new-client-onboarding/src/build.js`, so a fix there reaches both.

`Start > Read inputs > Check CloudRadial > Microsoft 365 baseline preview (skipped unless include_m365 is true) > Create the company and add the cards > End`

1. **Check CloudRadial.** Finds the company by `company_id`, or by its exact name, and checks the domain isn't already used by another company. Because neither `psa` nor `ticket` is in `steps`, the PSA isn't read and no PSA secrets are needed.
2. **Create the company and add the cards.** Plans the changes, previews them, and on `confirm: true` makes them:
   - creates the CloudRadial company (no PSA link), adds the domain as its default, and adds it to `company_group`;
   - adds the four prospect Planner cards (client-visible, category Efficiency). Each card carries a hidden marker (`nco:land:proposal`, `nco:land:email`, `nco:land:m365`, `nco:land:portal`), so a rerun updates the cards instead of adding new ones.

## Required runner Key Vault secrets

| Secret | Needed for |
|---|---|
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Reading and writing the portal |

To set up the prospect in a different portal, store that portal's keys under an AutomationAI company and pass its id as `cloudradial_company`. The run then reads `CloudRadial-*-<company id>`.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `company_name` | required | The prospect's name |
| `primary_domain` | required | Their email domain |
| `company_group` | none | A company group to add them to, for example `Prospects` |
| `account_manager`, `territory` | none | Set on the new CloudRadial company |
| `company_id` | none | Use this existing CloudRadial company instead of finding or creating one |
| `cloudradial_company` | empty (the shared CloudRadial secrets) | See the secrets section |
| `include_m365` | `false` in the Test Input | `true` also previews the Microsoft 365 baseline (needs the `M365-*` secrets) |
| `steps` | `portal,landcards` | Add `planner`, `ticket` or `psa` to do more of New Client Onboarding in the same run |
| `confirm` | `false` | `false`: preview only. `true`: make the changes. |

## Output

The same contract as New Client Onboarding: `status` (`success`, `pending_confirmation`, `incomplete`, `rejected` or `error`), `message`, `planned`, `actions`, `warnings`, and the `cloudradial` and `psa` blocks (`psa.found_by` is `skipped`).

## Build and test

```
cd new-client-onboarding
node src/build.js                     # writes new-client-onboarding.yml and ../prospect-portal-setup/prospect-portal-setup.yml
pwsh -NoProfile -File src/test.ps1    # strict-mode harness; the "prospect" checks cover this workflow
```

## Tested

- `new-client-onboarding/src/test.ps1`: 94 checks pass under strict mode, 12 of them for this workflow. With no PSA secrets on the runner, a preview plans exactly the company, the domain and the prospect cards, and makes no PSA call. A confirm creates the company with no PSA link and four client-visible cards on it.
- **Live, 2026-11-20 (this version, imported from `main` into a test tenant, run on a production runner, demo portal):**
  - **Preview:** `pending_confirmation`, with the three planned changes and nothing written.
  - **Confirm:** created the test company with no PSA link, added the domain as its default, and added the four client-visible cards.
  - **Same confirm again:** found the company by its exact name, updated the same four cards, and created nothing new.
  - The first run's message read "linked to  company ." when there was no PSA; that is fixed here.
