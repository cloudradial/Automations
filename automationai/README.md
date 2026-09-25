# AutomationAI Workflows

Importable **CloudRadial AutomationAI** workflows. Unlike the standalone PowerShell scripts elsewhere in
this repo (which you run directly or via RMM), these are `.yml` workflow/agent definitions you **import into
AutomationAI**, where they run on your **runner**. Most are triggered by a **secure webhook** (from a
CloudRadial catalog form, an Automation, or a ServiceAI Action); the reporting ones run on a **schedule**
(a Routine) or on demand.

Each workflow is broken out into discrete, legible steps (one PowerShell node per concern) rather than a
single monolithic script, so every validation and gate is easy to read, test, and adjust.

## Workflows

| Workflow | Folder | What it does |
|---|---|---|
| **Password Reset (Self-Service)** | [`password-reset/`](password-reset/) | Self-service M365 password reset with an ownership gate (a requester may reset only their own account) plus disabled / tenant-scope / privileged / risk safeguards. |
| **Password Reset (ServiceAI Triage)** | [`password-reset-triage/`](password-reset-triage/) | The triage counterpart, fired by a ServiceAI Action from a ticket: requires the authenticated submitter, resets when they own the account, and otherwise holds for human confirmation. |
| **Domain Expiration Report** | [`domain-expiration-report/`](domain-expiration-report/) | Sweeps managed domains across all companies and writes one Planner card per company listing expired / soon-to-expire domains. |
| **Certificate Expiration Report** | [`certificate-expiration-report/`](certificate-expiration-report/) | Sweeps SSL certificates across all companies and writes one Planner card per company listing expired / soon-to-expire certs. |
| **Endpoint Names Token** | [`endpoint-names-token/`](endpoint-names-token/) | Builds a comma-separated endpoint-name list per company and writes it into a company token for portal content/forms. |
| **KnowBe4 Training Sync** | [`knowbe4/`](knowbe4/) | Manual/scheduled sync: reads KnowBe4 users with incomplete training, writes one CloudRadial flexible asset per user, and opens a ConnectWise ticket for the company summarizing who is overdue. |
| **Portal Lookup** _(agent)_ | [`portal-lookup/`](portal-lookup/) | Read-only portal briefing — users, endpoints, warranty posture, setup gaps — for meeting prep. Import under **Agents → Custom**. |
| **CloudRadial UCP Assistant** _(agent)_ | [`cloudradial-ucp/`](cloudradial-ucp/) | General-purpose portal assistant — the AutomationAI analog of the UCP MCP plugin. Looks up, briefs, audits, reports, and (with approval) changes companies, users, endpoints, services, and tokens. Import under **Agents → Custom**. |
| **Weekly Fleet Audit** | [`weekly-fleet-audit/`](weekly-fleet-audit/) | Demo of an **agent inside a workflow**: an Agent node runs the UCP Assistant to audit warranties / account-manager gaps on a schedule, then a PowerShell node emails the result via Postmark. |
| **Endpoint LifeCycle Manager** _(agent)_ | [`endpoint-lifecycle-manager/`](endpoint-lifecycle-manager/) | Reviews managed computers per company and maintains one Planner card per refresh category (Replace, Plan replacement, Upgrade in place, Retain, Needs data, Human review, VMs), each with a triage priority. Scheduled; writes. Import under **Agents → Custom**. |
| **ScalePad to CloudRadial Migration** _(agent)_ | [`scalepad-to-cloudradial/`](scalepad-to-cloudradial/) | Migrates ScalePad Lifecycle Manager warranty/lifecycle data and vCIO roadmap initiatives into CloudRadial endpoints and Planner items. Read-first, dry-run default. Import under **Agents → Custom**. |
| **New User Onboarding** _(agent)_ | [`new-user-onboarding/`](new-user-onboarding/) | Guarded onboarding agent behind the Day One playbook: plans access from a mirror-from user without copying privileged or sensitive groups, raises quotes instead of buying, and hands credentials over through 1Password. Dry-run default. Import under **Agents → Custom**. |
| **Split Request - Service + Quote** | [`split-request-two-tickets/`](split-request-two-tickets/) | One form or ServiceAI ticket becomes a service ticket plus, when something has to be bought, a linked quote request. A classifier agent grounded on your Knowledge (service ticket standards, quote standards, standard catalog) writes both tickets to your format; ConnectWise Manage. |
| **Patch Compliance** | [`patch-compliance/`](patch-compliance/) | Scheduled: runs the RMM Agent over the Datto RMM fleet, sorts devices into compliant / pending / failing / no policy / no data / not patchable, and writes one Patch Compliance Planner card per matched client. |
| **RMM Agent** _(agent)_ | [`rmm-agent/`](rmm-agent/) | Safety-first Datto RMM agent behind Patch Compliance and RMM Auto-Remediation: site-to-company matching (site map, PSA id, name), one card per client, honest counts. Dry-run default. Import under **Agents → Custom**. |
| **RMM Auto-Remediation** | [`rmm-auto-remediation/`](rmm-auto-remediation/) | Datto alert webhook: the RMM Agent runs a safe fix on workstations, re-checks, then resolves or escalates to a PSA ticket. Every action waits for approval. |
| **Add CC to Ticket** | [`add-cc-to-ticket/`](add-cc-to-ticket/) | Adds a user or email to an existing ConnectWise ticket's CC list from a self-service form field (de-duplicated), with an internal note. |
| **ScalePad to CloudRadial Alignment** | [`scalepad-cloudradial-alignment/`](scalepad-cloudradial-alignment/) | The judgment half of a ScalePad migration: agent + workflow that match clients and plan what the Sync workflow moves, grounded on the migration map in Knowledge. At most 10 direct corrections. |
| **ScalePad to CloudRadial Sync** | [`scalepad-cloudradial-sync/`](scalepad-cloudradial-sync/) | The bulk half: deterministic, paged API-to-API transfer of devices (workstations, servers, VMs), other hardware (network, mobile, imaging, no-serial devices) to flexible assets, installed software, assessments (Excel built in memory), roadmap and budget, and deliverable PDFs to the Report Archive. Plan first, then apply. |
| **Lifecycle Manager extension 1.2.0** _(extension)_ | [`scalepad-lifecycle-manager-extension/`](scalepad-lifecycle-manager-extension/) | Update to the catalog ScalePad extension: every list tool pages automatically, plus installed-software, assessment and deliverable tools. Import under **Extensions → Custom**. |
| **CloudRadial v2 Compliance extension 0.2.1** _(extension)_ | [`cloudradial-v2-compliance-extension/`](cloudradial-v2-compliance-extension/) | Update to the catalog extension: `cr_patch_flexible_asset` now carries `traitsJson` (0.2.0 sent an empty patch), and flexible asset types can be created with their fields. Import under **Extensions → Custom**. |
| **Feedback & CSAT Report** | [`feedback-csat-report/`](feedback-csat-report/) | Scheduled: CSAT summary per company from CloudRadial feedback, written as one Planner card per company. Replaces the Get-FeedbackReport.ps1 helper. |
| **Deliver Result** _(agent)_ | [`deliver-result/`](deliver-result/) | Reusable delivery step: turns a result into a PSA ticket (any connected PSA), a Postmark email, or a ServiceAI return contract. Dry-run default. Import under **Agents → Custom**. |

## Agents, dry run and Knowledge

- **Agents** (`*.agent.yml`) import on **Agents → Custom** and are keyed on their slug, so re-importing replaces the installed copy.
- **Dry run** is set only by `dryRunDefault` in the agent file — there's no switch on the workflow node or deployment. Repo copies ship with it on; each agent's README has a *Dry run and going live* section.
- **Knowledge.** Agents that need your own standards ship example documents in a `knowledge/` subfolder (Split Request, ScalePad Alignment). Edit them, upload them to AutomationAI Knowledge, then turn on **Ground on knowledge** on the workflow's agent node. Grounding points at your tenant's document IDs, so it can't be exported — every install re-attaches it. Without Knowledge these agents fall back to built-in defaults.

## Installing a workflow

1. Open the workflow's folder and download its `.yml`.
2. In AutomationAI: **Workflows → Import**, upload the `.yml`.
3. Add the required **Runner Key Vault secrets** listed in that workflow's README.
4. Open **Properties → Webhook** and toggle **Enable webhook** on — AutomationAI mints the URL + secret at
   that point (the exports ship with the webhook **disabled** and **no secret**, so enable it in-portal).
5. **Publish** the workflow and **deploy** it to the runner that holds the secrets.
6. Point your CloudRadial form / Automation / ServiceAI Action at the webhook URL, sending the secret in the
   `X-Crauto-Webhook-Secret` header.

> Webhook URLs and secrets are confidential and are **not** included in these exports — the portal issues a
> fresh pair when you enable the webhook.

## Trigger contract

Workflows accept a JSON body (flat `{key:value}` or the CloudRadial `{Ticket:{Questions:[…]},Company:{…}}`
shape). Fields land at `{{ nodes.trigger.output.<field> }}`. Each workflow returns a structured result
(`status` / `message` / `public_note` / `internal_note` / `ticket_id` / …); any temporary password is placed
only in `internal_note`, never in a client-visible field. See each workflow's README for its exact fields and
gates.
