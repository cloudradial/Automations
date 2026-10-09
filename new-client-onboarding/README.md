# Onboard a New Client in CloudRadial, the PSA and Microsoft 365

Bring on a new client in one run: create their CloudRadial company linked to the PSA, open an onboarding checklist ticket, and see the Microsoft 365 security baseline you would apply before anything touches their tenant.

**Marketplace ID:** TBD | **Type:** Workflow (run by hand, MSP-wide)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `new-client-onboarding.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/new-client-onboarding/new-client-onboarding.yml) |
| Download `new-client-onboarding.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/new-client-onboarding/new-client-onboarding.yml) |
| Step source, build script and test harness | [src/](https://github.com/cloudradial/Automations/tree/main/new-client-onboarding/src) |
| All files in this automation | [new-client-onboarding](https://github.com/cloudradial/Automations/tree/main/new-client-onboarding) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/new-client-onboarding) |

## Which onboarding automation to use

| You want to | Use |
|---|---|
| Onboard **one new client** end to end: company, PSA link, domain, group, checklist ticket and the Microsoft 365 baseline | **This workflow** |
| Add **many companies at once** from a list, with nothing else | [Add Companies to the Portal](../add-companies-to-portal/) |
| Add **portal users** to a company from a list (when its Microsoft 365 or PSA sync isn't used) | [Onboard Users into the Portal](../onboard-users-to-portal/) |

They work together. If a company was already created with Add Companies to the Portal, run this workflow with `company_id` set to that company, and it skips the create and does the rest.

## How it works

Steps: **Read inputs > Check CloudRadial and the PSA > Microsoft 365 baseline preview > Create the company and open the ticket.** No AI step is used; the rules are fixed.

AutomationAI has no approval step, so the workflow **previews first**. With `confirm` false (the default) it reads everything, works out every change, and writes nothing anywhere. Run it again with `confirm` true to make the changes.

1. **Read inputs** checks the input. A missing or malformed `company_name` or `primary_domain` stops the run before any call.
2. **Check CloudRadial and the PSA** (read-only):
   - Stops with a plain sentence if the CloudRadial or PSA secrets are missing.
   - Rejects the run if the client is already in CloudRadial: a company with the same name, a company that already has `primary_domain`, or a company already linked to the same PSA company. The message gives the company number, so you can finish that company's onboarding with `company_id` instead.
   - Finds `company_group`, which must already exist (a typo never creates a stray group).
   - Finds the client's company in the PSA. With `psa_company_id` it uses that id. Otherwise it searches by `company_name` and needs **exactly one exact name match**; none or several stops the run and lists what it found.
3. **Microsoft 365 baseline preview** (read-only, every run). See [The Microsoft 365 baseline](#the-microsoft-365-baseline).
4. **Create the company and open the ticket.** On a confirm run it makes these changes in order and stops at the first failure, saying what ran and what didn't:
   1. Creates the CloudRadial company with its PSA link (or, with `company_id`, links that company to the PSA if it has no link yet).
   2. Adds `primary_domain` to the company as its default domain.
   3. Adds the company to `company_group`.
   4. Opens **one** onboarding checklist ticket for the client in the PSA (ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro or Zendesk). The checklist is in the ticket description. Skipped when `ticket_id` is given, or when the check step finds an open ticket for this PSA company with the summary `New client onboarding: <company_name>` (found with the shared `Find-PsaTickets`); that ticket is used instead.

   It then writes the Microsoft 365 baseline into the company's **Onboarding** report archive (Compliance > Reports, admins only, never the knowledge base) and adds an **internal** note to the ticket with what was set up and the baseline. If either of those fails, the run still finishes, says so in `warnings`, and returns the report as `report_html`.

If a confirm run stops after creating the company, the message tells you to run again with `company_id` (and `ticket_id` if the ticket was opened), so nothing is created twice.

**Safe to retry.** A ServiceAI **Retry** (or a rerun with `company_id`) never opens a second onboarding ticket: the open one is reused. The internal note goes through the shared `Add-PsaNote -Marker` and ends with `[new-client-onboarding: <ticket id> <note hash>]`, where the hash is the first 8 hex characters of the note's SHA-256. A rerun with the same outcome adds no second note; a rerun that finished more of the work adds its new note. The marker holds no name or domain. Every note is internal: the workflow writes no client-visible note (`public_note` is only returned in the output).

### What the CloudRadial API can and can't set

| Set by this workflow | How |
|---|---|
| Company name, PSA link (`psaKey`, `psaIdentifier`), account manager, territory | `POST /v2/company` |
| Default domain | `POST /v2/domain` |
| Company group membership | `POST /v2/companygroupcompany` |

**Not settable through the API:** the company's Microsoft 365 tenant link, the RMM or data agent, and portal branding. **User and endpoint sync** is driven by the portal's integrations (Microsoft 365 or PSA contacts for users, the RMM or data agent for endpoints). The CloudRadial v2 API has **no sync call**, so this workflow can't start a sync. It reports what it can see instead: for an existing company, how many users and endpoints it has so far. The default checklist includes linking Microsoft 365 and installing the agent, so the ticket tracks the steps the API can't do.

PSA link values: `psaKey` is the PSA's company number. `psaIdentifier` is the ConnectWise company identifier when the company was found by name, and otherwise the PSA company number.

### The Microsoft 365 baseline

The workflow reads the client's tenant and reports what it **would** apply. It never creates a group or a policy in this version.

| Standard security group | Purpose |
|---|---|
| `SG-All Staff` | Every licensed staff member, for assigning apps, licences and policies to everyone |
| `SG-Admins` | People who hold admin roles |
| `SG-Break Glass Exclusion` | Two cloud-only emergency admin accounts, left out of every Conditional Access policy |

| Conditional Access policy (report-only mode) | What it does |
|---|---|
| `CA001 - Require MFA for admins` | MFA for Microsoft's 14 template admin roles, every app |
| `CA002 - Require MFA for all users` | MFA for every user, every app |
| `CA003 - Block legacy authentication` | Blocks Exchange ActiveSync and other legacy clients |

Every policy excludes `SG-Break Glass Exclusion`. For each group and policy the report says whether it already exists, is already covered by an existing policy (for example, a policy that already blocks legacy clients), or would be created. It also reads the security defaults setting and whether the tenant has Entra ID P1 (Conditional Access needs it), and lists the next steps. The full policy definitions are in the `m365.policies[].definition` output, ready for the next version.

**Which tenant:** the `tenant_id` input, or else the tenant that owns `primary_domain`. Either way, the tenant must list `primary_domain` as a verified domain, or the run is rejected, so one client's tenant is never reported under another client.

**Skipped, with a note in `warnings` and the ticket:** when `include_m365` is false, when the `M365-ClientId` and `M365-ClientSecret` secrets aren't set, or when the app can't sign in to the client's tenant (usually because the client hasn't consented to it yet). The CloudRadial and PSA parts still run.

**Why applying the baseline is the next version:** a Conditional Access policy that is switched on can lock everyone out of the tenant, including the MSP. Two break-glass accounts must exist, be stored safely and be in `SG-Break Glass Exclusion` before any policy is enforced, and the policies should sit in report-only mode while someone checks the sign-in logs. Security defaults also have to be turned off at the moment the policies are switched on. Those are judgment calls for a technician, so this version stops at the report.

## Download & import

**Download the workflow:** [`new-client-onboarding.yml`](https://github.com/cloudradial/Automations/blob/main/new-client-onboarding/new-client-onboarding.yml)

Then in AutomationAI: **Workflows > Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), then publish and deploy it to the runner that holds your MSP-wide CloudRadial and PSA secrets. Full steps are under [Import & test](#import--test).

## Required runner Key Vault secrets

| Secret | Needed for |
|---|---|
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Everything. The run stops with a sentence naming any that are missing. |
| `PSA-Type` plus that PSA's secrets (`CW-*`, `Autotask-*`, `Halo-*`, `KaseyaBMS-*`, `Syncro-*` or `Zendesk-*`) | Finding the PSA company, opening the ticket and adding the note. Same names as the PSA's catalog extension. Kaseya BMS also needs `KaseyaBMS-NoteTypeId` for the note, and may need its optional ticket ids (see [`_shared`](../_shared/)). |
| `M365-ClientId`, `M365-ClientSecret` (the `Entra-*` and `Graph-*` names work too) | Optional. A **multi-tenant** app registration that each client consents to (for example through your GDAP or CSP onboarding). Without them the Microsoft 365 baseline is skipped. `M365-TenantId` is not used: the tenant comes from `tenant_id` or `primary_domain`. |

## Required Graph permissions

Application permissions on the multi-tenant app, with admin consent in the client's tenant. All are read-only.

| Permission | Why |
|---|---|
| `Organization.Read.All` | Checking the tenant owns `primary_domain`, and reading licences (Entra ID P1) |
| `Policy.Read.All` | Reading security defaults and Conditional Access policies |
| `Group.Read.All` | Reading existing security groups |

If a permission is missing, the run stops before changing anything, with a sentence naming it, for example: "Can't read the client's groups. The app registration needs the Group.Read.All application permission, with admin consent in the client's tenant (or set include_m365 to false). Nothing was changed."

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `company_name` | required | The client's name, exactly as it should appear in CloudRadial |
| `primary_domain` | required | The client's main email domain, for example `contoso.com` |
| `psa_company_id` | empty | The client's company number in the PSA. When empty, the PSA is searched by `company_name` and exactly one exact match is needed. |
| `company_group` | empty | A CloudRadial company group to add the company to. It must already exist. |
| `account_manager`, `territory` | empty | Optional CloudRadial company fields |
| `company_id` | empty | An existing CloudRadial company to finish onboarding (made by Add Companies to the Portal, or by an earlier run that stopped). No company is created. |
| `ticket_id` | empty | An onboarding ticket that already exists. No new ticket is opened; the note goes on this one. When empty, an open `New client onboarding: <company_name>` ticket for the PSA company is reused if there is one. |
| `checklist` | the 10 items below | The ticket's checklist: a list, or text with one item per line (or separated by `;`). Up to 50 items. |
| `ticket_queue` | PSA default | Board (ConnectWise), queue (Autotask, Kaseya BMS id), team (HaloPSA), issue type (Syncro) or group id (Zendesk) |
| `tenant_id` | the tenant that owns `primary_domain` | The client's Microsoft 365 tenant id |
| `include_m365` | `true` | `false` skips the Microsoft 365 baseline preview |
| `psa` | `PSA-Type` secret | Which PSA (`connectwise`, `autotask`, `halopsa`, `kaseyabms`, `syncro`, `zendesk`) |
| `confirm` | `false` | `false`: preview only, nothing changes. `true`: create the company and open the ticket. |

Default checklist:

1. Confirm the signed agreement, the billing contact and the service start date.
2. Collect admin access: Microsoft 365 (through GDAP), the domain registrar and line-of-business apps.
3. Link the company to its Microsoft 365 tenant in CloudRadial and check that users sync.
4. Install the RMM agent on every computer and check that endpoints appear in CloudRadial.
5. Document the network: firewall, switches, Wi-Fi, internet provider and IP ranges.
6. Confirm backups for servers and Microsoft 365, and run a test restore.
7. Create two break-glass admin accounts and store them in the password vault.
8. Review the Microsoft 365 security baseline report with the client and agree a rollout date.
9. Send the portal welcome email and walk the main contact through the portal.
10. Hold the 30-day check-in and close out onboarding.

## Output

`status` (`pending_confirmation` on a preview with changes to make, `success`, `rejected`, `incomplete` or `error`), `message`, `public_note` (client-safe, confirm runs only), `internal_note`, `ticket_id`, `actions`, `warnings`, plus `company_id`, `planned` (every change, in order), `cloudradial` (what was set, and the integration note), `psa` (PSA company, ticket and checklist), `m365` (tenant, licence, security defaults, each group and policy with what would happen, the summary, next steps and policy definitions), `report` (where it was written) and `report_html` when it wasn't archived.

## Import & test

1. AutomationAI > **Workflows > Import** `new-client-onboarding.yml`. **Publish** and **deploy** it to the runner that holds your CloudRadial and PSA secrets.
2. Run it by hand with the first step's Test Input, changing `company_name` and `primary_domain` to a test client that exists in your PSA. Leave `confirm` false. Check the message lists the planned changes and the `m365` output shows the tenant you expect. Nothing is written.
3. Run again with `confirm` true. Check the new company in CloudRadial (name, PSA link, domain, group), the ticket and its checklist in the PSA, the internal note, and the "Microsoft 365 security baseline (preview)" item in the company's Onboarding report archive. Confirm that no group or policy was created in the client's tenant.
4. Run the same input again: it should be rejected because the company now exists.

To change the steps, edit `src/*.ps1`, then run `node src/build.js` (it pastes in the shared libraries) and `pwsh -NoProfile -File src/test.ps1`. Never edit the `.yml` by hand.
