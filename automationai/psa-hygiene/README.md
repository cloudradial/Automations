# Keep Your PSA Clean: Stale Tickets, Missing Contacts and Wrong Statuses

Every week, email the service manager the open tickets that have gone quiet, have no contact, or sit in a status that contradicts them, and fill in missing contacts only where the answer is certain and you say so.

**Marketplace ID:** TBD | **Type:** Workflow (run weekly by a Routine, or by hand)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `psa-hygiene.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/psa-hygiene/psa-hygiene.yml) |
| Download `psa-hygiene.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/psa-hygiene/psa-hygiene.yml) |
| Step source, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/automationai/psa-hygiene/src) |
| All files in this automation | [automationai/psa-hygiene](https://github.com/cloudradial/Automations/tree/main/automationai/psa-hygiene) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/psa-hygiene) |

## How it works

The workflow checks every open ticket in your PSA: ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro or Zendesk. No AI step is used; the rules are fixed.

Steps: **Read inputs > Find stale tickets, missing contacts and wrong status > Fix missing contacts (only on confirm) > Report.**

1. **Find** (read-only) lists the open tickets and sorts out three kinds of problem:
   - **Stale:** no update for `stale_days` days or more (14 by default).
   - **Missing contact:** no contact on the ticket (the requester in Zendesk). Syncro isn't checked, because a Syncro ticket with no contact is addressed to the customer record itself.
   - **Wrong status:** the status contradicts the ticket. Either a closed date is set but the ticket is open (often a reopened ticket that was never tidied), or it's open with no assignee for more than `unassigned_hours` hours (24 by default). Zendesk has no separate closed date, so there only the unassigned check applies. Open tickets are listed by status (`Find-PsaTickets -OpenByStatus`), so on HaloPSA and Kaseya BMS an open ticket with a closed date is still listed and flagged.
2. **Fix missing contacts** is the **only** change this workflow ever makes, and only when both `confirm` is true and `fix` names `missing_contact`. For each ticket with no contact it reads that ticket's company's active contacts. When the company has **exactly one primary contact**, it sets the ticket's contact to that person. Anything else is left alone with a reason: no primary contact, two or more, no company on the ticket, or a PSA with no primary-contact flag (Syncro and Zendesk). Stale tickets and wrong statuses are never changed; they need a person.

   Without `confirm`, the report lists what would change and nothing is written. The fixes use the shared preview and confirm plan (`_shared/plan.ps1`), so they run in order and stop at the first failure, and the report says what ran and what didn't. Only tickets on this run's fresh list are touched.
3. **Report** emails the three tables (and the fixes) to the `to` addresses through Postmark. When `archive_company_id` is set, it also saves a copy in the **PSA Hygiene** report archive of that CloudRadial company (Compliance > Reports, admins only). **Use your own MSP company for this, never a client company:** the report lists tickets from every client. If Postmark isn't set up and `ticket_id` is given, the summary goes on that ticket as an internal note instead. The note ends with a marker for the day and the run's settings, so a ServiceAI **Retry** or a Routine that runs again the same day doesn't add it twice. If nothing can be delivered, the report stays in the run output as `report_html`.

How each PSA answers "who is the primary contact":

| PSA | Primary contact |
|---|---|
| ConnectWise PSA | The company's default contact |
| Autotask | The contact marked Primary Contact |
| HaloPSA | The user marked as the primary contact |
| Kaseya BMS | The contact marked as the point of contact |
| Syncro | No such flag, so missing contacts aren't fixed (and aren't checked) |
| Zendesk | No such flag, so missing requesters are reported but not fixed |

## Download & import

**Download the workflow:** [`psa-hygiene.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/psa-hygiene/psa-hygiene.yml)

Then in AutomationAI: **Workflows > Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), then publish and deploy it to the runner that holds your PSA secrets. **Attach a weekly Routine after import** (the schedule isn't part of the export). Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

| Secret | Needed for |
|---|---|
| `PSA-Type` plus that PSA's secrets (`CW-*`, `Autotask-*`, `Halo-*`, `KaseyaBMS-*`, `Syncro-*` or `Zendesk-*`) | Reading tickets and contacts, and setting a contact on confirm runs. Same names as the PSA's catalog extension. Kaseya BMS also needs `KaseyaBMS-NoteTypeId` for the internal-note fallback. |
| `Postmark-ServerToken`, `Postmark-FromEmail` | Sending the email. Same names as the Postmark extension and Deliver Result. `Postmark-FromEmail` must be a verified Postmark sender. |
| `Postmark-ApiUrl` | Optional. Defaults to `https://api.postmarkapp.com`. |
| `ServiceManager-Email` | Optional. Who gets the email when the run has no `to` input, which is how a Routine runs. |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Only for the archive copy |
| `CloudRadial-InternalCompanyId` | Optional. Your own MSP company's CloudRadial number, used for the archive copy when the run has no `archive_company_id`. The per-client `CloudRadial-CompanyId` secret is deliberately not used. |

The PSA API account needs **read** access to tickets and contacts, and **edit** access to tickets for confirm runs. If it can't read tickets, the run stops with a sentence saying so, for example: "The ConnectWise API account isn't allowed to read tickets (HTTP 403). Give it read access to service tickets and run again. Nothing was changed."

## Required Graph permissions

None. This workflow doesn't use Microsoft Graph.

## Inputs

All inputs are optional. A weekly Routine sends none, so it reports with the defaults and changes nothing.

| Input | Default | Meaning |
|---|---|---|
| `stale_days` | `14` | An open ticket with no update for this many days is stale (1 to 365) |
| `unassigned_hours` | `24` | An open ticket with no assignee for longer than this is flagged (1 to 720) |
| `confirm` | `false` | `false`: report and preview only, nothing changes. `true`: make the fixes named in `fix` |
| `fix` | empty | Comma-separated categories to fix. Only `missing_contact` can be fixed. Naming `stale` or `wrong_status` just adds a warning; anything else is rejected. |
| `to` | `ServiceManager-Email` secret | Comma-separated email addresses for the report |
| `archive_company_id` | `CloudRadial-InternalCompanyId` secret | Your own MSP company's CloudRadial number, for the archive copy |
| `company_id` | empty | Check only this PSA company (the PSA's own company id) |
| `ticket_id` | empty | An internal ticket that gets the summary as an internal note when Postmark isn't set up |
| `max_tickets` | `2000` | Stop after this many open tickets (a warning says so) |
| `psa` | `PSA-Type` secret | `connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro` or `zendesk` |

## Output

`status` (`pending_confirmation` when a preview found contacts it could set, `success`, `incomplete` for bad input, or `error`), `message`, `public_note` (empty; nothing here is client-facing), `internal_note`, `ticket_id`, `actions`, `warnings`, plus `counts` (`open_tickets`, `stale`, `missing_contact`, `wrong_status`, `tickets_with_issues`), `issues` (one row per problem, up to 1,000), `fix` (`planned`, `skipped` with reasons, `changed`, `failed`), `report` (where the archive copy went) and `report_html` when the report was neither emailed nor archived.

## Import & test

1. AutomationAI > **Workflows > Import** `psa-hygiene.yml`. **Publish** and **deploy** it to the runner that holds your PSA and Postmark secrets.
2. Run it by hand with no fixes, for example `{"to": "you@example-msp.com"}`. Check a few listed tickets in the PSA: each should really be stale, missing a contact, or in a contradicting status. Nothing changes.
3. Preview the contact fix: `{"fix": "missing_contact", "to": "you@example-msp.com"}`. The report lists "what confirm would change" and why other tickets were left alone. Check that each planned contact is the company's primary contact.
4. To make the fix, run again with `{"fix": "missing_contact", "confirm": true}`. Try it first with `company_id` set to a test company.
5. **Attach a Routine:** Routines > New, pick this workflow and a weekly schedule (for example `0 7 * * 1`, 07:00 UTC on Mondays). A Routine sends no input, so it only reports. Set the `ServiceManager-Email` secret, and `CloudRadial-InternalCompanyId` if you want the archive copy. A Routine runs the deployed version, so redeploy after every edit.

To change the steps, edit `src/*.ps1`, then run `node src/build.js` (it pastes in `_shared/psa.ps1`, `psa-tickets.ps1`, `plan.ps1`, `cloudradial.ps1` and `postmark.ps1`) and `pwsh -NoProfile -File src/test.ps1`. Never edit the `.yml` by hand.

The ticket list, contact and set-contact calls come from `_shared/psa-tickets.ps1` and `_shared/psa.ps1`, and the email from `_shared/postmark.ps1`. The PSA calls that haven't been proven by a live run are marked `Unverified` there.
