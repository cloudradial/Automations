# AutomationAI

This folder holds importable **CloudRadial AutomationAI** automations: **workflows**, the **agents** they run, and the **Knowledge** documents those agents are grounded on. Unlike the standalone PowerShell scripts elsewhere in this repo, which you run directly or through an RMM, these are `.yml` definitions you import into AutomationAI, where they run on your **runner**.

Extensions aren't kept here. AutomationAI ships them as default (catalog) extensions, and updates go to the AutomationAI team to publish.

## What's in a subfolder

Each subfolder is one automation, with a README that covers what it does, what to install, its secrets and inputs, and how to test it.

| File | What it is | Where it imports |
|---|---|---|
| `*.yml` (`automationsWorkflow`) | A workflow: the trigger, the steps, and any Agent nodes with their goals. This is what runs. | **Workflows → Import** |
| `*.agent.yml` (`automationsAgent`) | An agent: the system prompt, tools and guardrails a workflow's Agent node calls by slug. An agent runs from a workflow that gives it a goal. | **Agents → Custom → Import** (keyed on the slug, so re-importing replaces it) |
| `knowledge/*.md` | Example standards an agent is grounded on. Edit them, upload them to **Knowledge**, then turn on **Ground on knowledge** on the Agent node. | **Knowledge** |
| `*.md` (other) | Reference material, such as a form-to-webhook field map. | — |

## Subfolders

| Folder | Contains |
|---|---|
| [`add-cc-to-ticket/`](add-cc-to-ticket/) | Workflow |
| [`certificate-expiration-report/`](certificate-expiration-report/) | Workflow |
| [`cloudradial-ucp/`](cloudradial-ucp/) | Agent (run by Portal Lookup and Weekly Fleet Audit) |
| [`deliver-result/`](deliver-result/) | Agent (a reusable delivery step other workflows call) |
| [`domain-expiration-report/`](domain-expiration-report/) | Workflow |
| [`endpoint-lifecycle-manager/`](endpoint-lifecycle-manager/) | Agent + workflow |
| [`endpoint-names-token/`](endpoint-names-token/) | Workflow |
| [`feedback-csat-report/`](feedback-csat-report/) | Workflow |
| [`knowbe4/`](knowbe4/) | Workflow |
| [`new-user-onboarding/`](new-user-onboarding/) | Agent + workflow, a no-AI PowerShell workflow, and a form-to-webhook reference (in testing) |
| [`password-reset/`](password-reset/) | Workflow (self-service) |
| [`password-reset-triage/`](password-reset-triage/) | Workflow (ServiceAI triage) |
| [`patch-compliance/`](patch-compliance/) | Workflow (runs the RMM Agent) |
| [`portal-lookup/`](portal-lookup/) | Workflow (runs the UCP Assistant) |
| [`rmm-agent/`](rmm-agent/) | Agent (run by Patch Compliance and RMM Auto-Remediation) |
| [`rmm-auto-remediation/`](rmm-auto-remediation/) | Workflow (runs the RMM Agent) |
| [`scalepad-cloudradial-alignment/`](scalepad-cloudradial-alignment/) | Agent + workflow + Knowledge (optional review before a Sync) |
| [`scalepad-cloudradial-sync/`](scalepad-cloudradial-sync/) | Workflow |
| [`split-request-two-tickets/`](split-request-two-tickets/) | Agent + workflows + Knowledge |
| [`weekly-fleet-audit/`](weekly-fleet-audit/) | Workflow (runs the UCP Assistant and Deliver Result) |

## Conventions

- **Import agents before the workflows that call them.** A workflow's Agent node finds its agent by slug.
- **Secrets** live in the runner's Key Vault. Each README lists the secret names; the files never contain values.
- **Webhooks** ship disabled and without a secret. Enable the webhook under **Properties → Webhook** after import; AutomationAI then issues the URL and secret.
- **Model.** Agents and Agent nodes leave `model` blank, so they run on the tenant's own AI provider (OpenAI or Anthropic). Don't pin a model name such as `gpt-5.4`: a tenant on a different provider has no model by that name, and the run fails.
- **Dry run** is set only by `dryRunDefault` in an agent file. Repo copies ship in dry run where the agent supports it, and each agent's README explains how to go live.
- **Knowledge grounding** points at your tenant's document IDs, so it can't be exported. Re-attach it after every import.
