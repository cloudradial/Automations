# Onboard a New Client from One Form

Fill in one portal form with the client's name, email domain and primary contact. The client is created in your PSA and your portal, linked, set up in Datto RMM and given their portal packages, with an onboarding ticket and a report of everything that was done.

## What your clients see in the portal

Their portal is ready on day one: their company, their email domain, the request forms and service catalog from your **All** company group, and their primary contact as a portal user.

Your team submits the **Onboard a New Client** form. The request ticket gets a note listing what was created and anything that needs a person.

## What happens behind the scenes

- **PSA:** finds the client or creates it, then opens the onboarding checklist ticket.
- **Portal:** creates the company, links it to the PSA company, adds the email domain, and sets up the portal (primary contact, Onboarding and QBR report archive folders).
- **Datto RMM:** creates the client's site, or reuses one with the same name, so new devices land in the right place.
- **Company group:** adds the company to **All**, so it gets your standard packages, for example Sample Problem Reports and Sample Service Catalog.
- **Microsoft 365:** previews the standard security groups and Conditional Access baseline for the client's tenant. It only reports; it changes nothing in Microsoft 365.
- **Safe to rerun.** Anything that already exists is reused, never duplicated.

## Works with

ConnectWise PSA, Autotask, HaloPSA, Kaseya BMS, Syncro and Zendesk (the same PSA support as [New Client Onboarding](../new-client-onboarding/)). Datto RMM for the site.

- **No Datto RMM?** The step is skipped with a note, and the rest still runs.

## What you need

- A UCP portal with **Actions** on your request forms
- AutomationAI, with your PSA and CloudRadial connected
- The **New Client Portal Setup** agent in your AutomationAI tenant (see the [technical details](https://github.com/cloudradial/Automations/tree/main/new-client-onboarding-form#the-portal-setup-agent))
- A company group named **All** in your portal, holding the packages every client gets
- Optional: Datto RMM API keys, and a Microsoft 365 multi-tenant app for the baseline preview

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://raw.githubusercontent.com/cloudradial/Automations/main/new-client-onboarding-form/new-client-onboarding-form.yml) (right-click > Save link as).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.

**In your UCP portal, add the Onboard a New Client form** to an admin-only category (for example **Client Onboarding**), with these questions:

1. **Text**, "Company name". Field ID `companyName`.
2. **Text**, "Email domain". Field ID `emailDomain`.
3. **Text**, "Primary contact name". Field ID `primaryContactName`.
4. **Email**, "Primary contact email". Field ID `primaryContactEmail`.
5. **Action**, "Set up the client", and pick **New Client Onboarding (Form)**.

The [form file](https://github.com/cloudradial/Automations/blob/main/new-client-onboarding-form/forms/onboard-a-new-client.json) has every setting.

**Test it.** Submit the form for a test client such as Contoso Ltd, then check the PSA, the portal, Datto RMM and the request ticket's note.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/new-client-onboarding-form#technical-details) cover each step, the secrets and the portal setup agent.

---

## Technical details

**Formerly:** New Client: Portal + PSA (Form) | **Marketplace ID:** CRA-00004 | **Type:** Workflow (PowerShell plus one agent step) | **Version:** 1.0.0

This is the portal-form version of [New Client Onboarding](../new-client-onboarding/). Its first five steps are that workflow's steps as they were in the test tenant on 2026-11-12. It adds the portal setup agent, Datto RMM and the company group.

## Files

| What | Link |
|---|---|
| View `new-client-onboarding-form.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/new-client-onboarding-form/new-client-onboarding-form.yml) |
| Download `new-client-onboarding-form.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/new-client-onboarding-form/new-client-onboarding-form.yml) |
| Portal form | [forms/onboard-a-new-client.json](https://github.com/cloudradial/Automations/blob/main/new-client-onboarding-form/forms/onboard-a-new-client.json) |
| Step sources and build script | [src/](https://github.com/cloudradial/Automations/tree/main/new-client-onboarding-form/src) |
| All files in this automation | [new-client-onboarding-form](https://github.com/cloudradial/Automations/tree/main/new-client-onboarding-form) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/new-client-onboarding-form) |

## How it works

```
Start -> Read inputs -> Check CloudRadial and the PSA -> Microsoft 365 baseline preview -> Create the company and open the ticket
      -> Hand off to portal setup -> Portal setup agent -> Create Datto RMM site -> Add to the All company group -> Report back on the request -> End
```

1. **Read inputs** maps the form's Field IDs to the workflow inputs. From the form, `confirm` defaults to true; a manual run defaults to a preview.
2. **Check CloudRadial and the PSA** finds or plans the PSA company, the CloudRadial company and the domain.
3. **Microsoft 365 baseline preview** reads the tenant and reports the groups and Conditional Access policies it would apply. Read-only.
4. **Create the company and open the ticket** creates and links the companies, adds the domain and opens the onboarding checklist ticket. It links the PSA company when the CloudRadial company has no PSA key yet.
5. **Hand off to portal setup** passes the agent only what it needs, or a skip reason.
6. **Portal setup agent** (`new-client-portal-setup`) adds the primary contact as a portal user, makes sure the Onboarding and QBR report archive folders exist, and lists the day-one content. It works only on the new company and never deletes.
7. **Create Datto RMM site** creates or reuses the site with the client's name.
8. **Add to the All company group** adds the company to the group (`groupName` parameter, default `All`).
9. **Report back on the request** adds the note to the request ticket and closes it.

## The portal setup agent

The agent step runs the tenant agent with the slug `new-client-portal-setup`, with the CloudRadial companies, compliance, content and tokens extensions and auto-approve on. Its goal is in [src/node-portal-agent.goal.md](src/node-portal-agent.goal.md). The model is left blank so it runs on OpenAI or Anthropic.

## Required runner Key Vault secrets

| Secret | Needed for |
|---|---|
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Everything |
| `PSA-Type` plus that PSA's secrets (`CW-*`, `Autotask-*`, `Halo-*`, `KaseyaBMS-*`, `Syncro-*` or `Zendesk-*`) | The PSA company, ticket and note |
| `Datto-ApiUrl`, `Datto-ApiKey`, `Datto-ApiSecret` | Optional. The Datto RMM site |
| `M365-ClientId`, `M365-ClientSecret` | Optional. The Microsoft 365 baseline preview |

## Notes

- The webhook ships disabled. The form's **Action** question runs it.
- ConnectWise's automation host can redirect writes to plain http. The note and close steps treat a redirect after a write as saved.
- Exported from the AutomationAI test tenant (tenant version 0.0.6) on 2026-11-12, then split into `src/` with tenant-specific names removed. Build with `node src/build.js`. The shared PSA blocks are pasted in as they were in the tenant, not through `_shared/inject.js` yet, and a strict-mode test harness (`src/test.ps1`) is still to be written.

## Tested

A live run in the test tenant created a demo client in ConnectWise and the portal, linked them, created the Datto RMM site and added the company to the All group.
