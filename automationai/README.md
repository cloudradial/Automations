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
| **Portal Lookup** _(agent)_ | [`portal-lookup/`](portal-lookup/) | Read-only portal briefing — users, endpoints, warranty posture, setup gaps — for meeting prep. Import under **Agents → Custom**. |

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
