# CloudRadial Automations

Importable **CloudRadial AutomationAI** automations, plus the CloudRadial AI plugins. Each top-level automation folder holds `.yml` definitions you import into AutomationAI, where they run on your **runner**, with a README that covers what it does, what to install, its secrets and inputs, and how to test it.

Extensions aren't kept here. AutomationAI ships them as default (catalog) extensions, and updates go to the AutomationAI team to publish.

## Folders

| Folder | What it is |
|---|---|
| Each automation folder (listed below) | One AutomationAI automation |
| [`_shared/`](_shared/) | PowerShell libraries pasted into the workflows at build time (for maintainers; nothing to import) |
| [`cowork-plugin/`](cowork-plugin/) | CloudRadial UCP plugin for Cowork and Claude Desktop |
| [`codex-plugin/`](codex-plugin/) | CloudRadial plugin for Claude Code and Codex |
| [`legacy-scripts/`](legacy-scripts/) | The original standalone PowerShell scripts, kept for reference. Most are replaced by an automation below. |

## What's in an automation folder

| File | What it is | Where it imports |
|---|---|---|
| `*.yml` (`automationsWorkflow`) | A workflow: the trigger, the steps, and any Agent nodes with their goals. This is what runs. | **Workflows → Import** |
| `*.agent.yml` (`automationsAgent`) | An agent: the system prompt, tools and guardrails a workflow's Agent node calls by slug. An agent runs from a workflow that gives it a goal. | **Agents → Custom → Import** (keyed on the slug, so re-importing replaces it) |
| `knowledge/*.md` | Example standards an agent is grounded on. Edit them, upload them to **Knowledge**, then turn on **Ground on knowledge** on the Agent node. | **Knowledge** |
| `*.md` (other) | Reference material, such as a form-to-webhook field map. | — |
| `src/` | Build source and test harnesses for maintainers. Not imported. | — |

## Automations

| Folder | What it does | Type | Marketplace |
|---|---|---|---|
| [`add-cc-to-ticket/`](add-cc-to-ticket/) | Let Users Add Colleagues to Ticket Updates | Workflow | — |
| [`add-companies-to-portal/`](add-companies-to-portal/) | Add Many Client Companies at Once | Workflow (runs the CloudRadial UCP Assistant agent) | [AAI-00002](https://automations.cloudradial.com/marketplace/AAI-00002) |
| [`auto-close-resolved/`](auto-close-resolved/) | Close Resolved Tickets Automatically After a Final Notice | Workflow (PowerShell, no AI, runs on a schedule) | — |
| [`auto-escalation/`](auto-escalation/) | Escalate Forgotten Tickets Before They Breach | Workflow (PowerShell steps, no AI), run every 15 minutes by a Routine | — |
| [`bulk-create-kb-articles/`](bulk-create-kb-articles/) | Add Many KB Articles at Once | Workflow (runs the CloudRadial UCP Assistant agent) | [AAI-00025](https://automations.cloudradial.com/marketplace/AAI-00025) |
| [`bulk-create-training-courses/`](bulk-create-training-courses/) | Add Many Training Courses at Once | Workflow (runs the CloudRadial UCP Assistant agent) | [AAI-00026](https://automations.cloudradial.com/marketplace/AAI-00026) |
| [`certificate-expiration-report/`](certificate-expiration-report/) | Renew SSL Certificates Before Browsers Warn | Workflow | [AAI-00024](https://automations.cloudradial.com/marketplace/AAI-00024) |
| [`cloudradial-ucp/`](cloudradial-ucp/) | Run Portal Admin Tasks by Asking | Agent | [AAI-00031](https://automations.cloudradial.com/marketplace/AAI-00031) |
| [`deliver-result/`](deliver-result/) | Send Automation Results Wherever Your Team Works | Agent | — |
| [`domain-expiration-report/`](domain-expiration-report/) | Never Let a Client Domain Expire | Workflow | [AAI-00023](https://automations.cloudradial.com/marketplace/AAI-00023) |
| [`endpoint-lifecycle-manager/`](endpoint-lifecycle-manager/) | Keep Every Client's Hardware Refresh Plan Current | Workflow (an optional AI agent version is included) | [AAI-00021](https://automations.cloudradial.com/marketplace/AAI-00021) |
| [`endpoint-names-token/`](endpoint-names-token/) | Let Users Pick Their Computer on Portal Forms | Workflow | [AAI-00005](https://automations.cloudradial.com/marketplace/AAI-00005) |
| [`feedback-csat-report/`](feedback-csat-report/) | See Each Client's Satisfaction Score in Their Planner | Workflow | [AAI-00022](https://automations.cloudradial.com/marketplace/AAI-00022) |
| [`import-service-catalog/`](import-service-catalog/) | Load Your Request Forms into Any Portal | Workflow (runs the CloudRadial UCP Assistant agent) | [AAI-00003](https://automations.cloudradial.com/marketplace/AAI-00003) |
| [`invoice-context/`](invoice-context/) | Answer Invoice Questions with the Billing Context Already on the Ticket | Workflow (PowerShell steps plus one AI Prompt step) | — |
| [`itglue-to-flexible-assets/`](itglue-to-flexible-assets/) | Bring IT Glue Documentation into the Portal | Workflow (runs the CloudRadial UCP Assistant agent) | [AAI-00004](https://automations.cloudradial.com/marketplace/AAI-00004) |
| [`knowbe4/`](knowbe4/) | Chase Overdue Security Training Automatically | Workflow | [AAI-00029](https://automations.cloudradial.com/marketplace/AAI-00029) |
| [`license-reclamation/`](license-reclamation/) | Find Unused Microsoft 365 Licences and Show the Monthly Saving | Workflow (PowerShell, no AI, read-only in Microsoft 365) | — |
| [`mfa-reset/`](mfa-reset/) | Let Users Reset Their Own MFA Safely | Workflow (PowerShell steps, no AI) | — |
| [`microsoft-security-assessment/`](microsoft-security-assessment/) | Turn a Microsoft 365 Security Review into a Client Assessment | Workflow (PowerShell, no AI) | — |
| [`new-client-onboarding/`](new-client-onboarding/) | Onboard a New Client in CloudRadial, the PSA and Microsoft 365 | Workflow (run by hand, MSP-wide) | — |
| [`new-user-onboarding/`](new-user-onboarding/) | Get New Hires Ready for Day One | Agent + Workflow | — |
| [`onboard-users-to-portal/`](onboard-users-to-portal/) | Onboard Many Portal Users at Once | Workflow (runs the CloudRadial UCP Assistant agent) | [AAI-00006](https://automations.cloudradial.com/marketplace/AAI-00006) |
| [`outage-broadcast/`](outage-broadcast/) | Tell Every Affected Client About an Outage in One Step | Workflow (PowerShell steps, no AI) | — |
| [`password-reset/`](password-reset/) | Let Users Reset Their Own Password Safely | Workflow | [AAI-00027](https://automations.cloudradial.com/marketplace/AAI-00027) |
| [`password-reset-triage/`](password-reset-triage/) | Resolve Password Reset Tickets Automatically | Workflow (ServiceAI Triage Action) | [AAI-00028](https://automations.cloudradial.com/marketplace/AAI-00028) |
| [`patch-compliance/`](patch-compliance/) | Show Every Client's Patch Compliance in Their Planner | Workflow | — |
| [`phishing-report-triage/`](phishing-report-triage/) | Triage Reported Phishing Emails into a Ticket with the Evidence | Workflow (PowerShell steps plus one AI Prompt step) | — |
| [`portal-lookup/`](portal-lookup/) | Walk Into Every Client Call Prepared | Agent | [AAI-00014](https://automations.cloudradial.com/marketplace/AAI-00014) |
| [`post-close-feedback/`](post-close-feedback/) | Ask Every Requester How It Went, and Hear About Bad Scores the Same Day | Workflow (PowerShell steps, no AI) | — |
| [`psa-hygiene/`](psa-hygiene/) | Keep Your PSA Clean: Stale Tickets, Missing Contacts and Wrong Statuses | Workflow (run weekly by a Routine, or by hand) | — |
| [`qbr-data-pack/`](qbr-data-pack/) | Have Every Client's QBR Numbers Ready on One Planner Card | Workflow (PowerShell, no AI, read-only except one internal Planner card) | — |
| [`related-ticket-detection/`](related-ticket-detection/) | Spot Duplicate and Related Tickets as They Arrive | Workflow (PowerShell steps plus one AI Prompt step) | — |
| [`remove-empty-flexible-asset-type/`](remove-empty-flexible-asset-type/) | Remove a Flexible Asset Type You No Longer Use | Workflow | — |
| [`risky-signin-response/`](risky-signin-response/) | Respond to Risky Microsoft 365 Sign-ins Within the Hour | Workflow (run hourly by a Routine, or by hand) | — |
| [`rmm-agent/`](rmm-agent/) | Safe Device Fixes and Patch Checks Through Your RMM | Agent | — |
| [`rmm-auto-remediation/`](rmm-auto-remediation/) | Fix Common Workstation Alerts Without a Technician | Workflow | — |
| [`role-change-mover/`](role-change-mover/) | Move a User to a New Department Without Missing Any Access | Workflow | — |
| [`scalepad-cloudradial-alignment/`](scalepad-cloudradial-alignment/) | Review Messy ScalePad Data Before You Migrate | Agent + Workflow | — |
| [`scalepad-cloudradial-sync/`](scalepad-cloudradial-sync/) | Move Off ScalePad Without Losing Your Data | Workflow | [AAI-00030](https://automations.cloudradial.com/marketplace/AAI-00030) |
| [`secure-score-assessment/`](secure-score-assessment/) | Turn Microsoft Secure Score into a Client Assessment | Workflow | [AAI-00001](https://automations.cloudradial.com/marketplace/AAI-00001) |
| [`shared-mailbox-dl/`](shared-mailbox-dl/) | Create Shared Mailboxes and Distribution Lists on Request | Workflow | — |
| [`sla-breach-report/`](sla-breach-report/) | See Every SLA Breach Before Your Clients Do | Workflow (PowerShell steps, no AI), run weekly by a Routine | — |
| [`split-request-two-tickets/`](split-request-two-tickets/) | Turn One Request into a Service Ticket and a Quote | Workflow + Agent | — |
| [`stale-guest-cleanup/`](stale-guest-cleanup/) | Find and Clean Up Unused Microsoft 365 Accounts and Guests | Workflow (run monthly by a Routine, or by hand) | — |
| [`status-change-updates/`](status-change-updates/) | Tell Requesters in Plain Language When Their Ticket Changes Status | Workflow (PowerShell steps plus one AI Prompt step) | — |
| [`ticket-routing/`](ticket-routing/) | Send Every Ticket to the Right Engineer | Agent + Workflow (ServiceAI Triage Action) | — |
| [`time-entry-review/`](time-entry-review/) | Catch Missing and Low-Detail Time Before It Costs You a Bill | Workflow (run daily by a Routine, or by hand) | — |
| [`troubleshooting-article-delivery/`](troubleshooting-article-delivery/) | Send the Right Fix-It Article the Moment a Ticket Arrives | Workflow (PowerShell steps, no AI) | — |
| [`user-offboarding/`](user-offboarding/) | Offboard a Departing Employee in One Reviewed Run | Workflow | — |
| [`vip-ticket-alert/`](vip-ticket-alert/) | Alert the Account Manager When a VIP Client Opens a Ticket | Workflow (PowerShell steps, no AI) | — |
| [`waiting-on-client-nudge/`](waiting-on-client-nudge/) | Nudge Clients Who Haven't Replied, Then Close the Ticket | Workflow (PowerShell, no AI, runs on a schedule) | — |
| [`weekly-fleet-audit/`](weekly-fleet-audit/) | Get a Weekly List of Warranty and Ownership Gaps | Workflow (PowerShell audit + Deliver Result agent) | [AAI-00032](https://automations.cloudradial.com/marketplace/AAI-00032) |

## Conventions

- **Import agents before the workflows that call them.** A workflow's Agent node finds its agent by slug.
- **Secrets** live in the runner's Key Vault. Each README lists the secret names; the files never contain values.
- **Webhooks** ship disabled and without a secret. Enable the webhook under **Properties → Webhook** after import; AutomationAI then issues the URL and secret.
- **Model.** Agents and Agent nodes leave `model` blank, so they run on the tenant's own AI provider (OpenAI or Anthropic). Don't pin a model name such as `gpt-5.4`: a tenant on a different provider has no model by that name, and the run fails.
- **Dry run** is set only by `dryRunDefault` in an agent file. Repo copies ship in dry run where the agent supports it, and each agent's README explains how to go live.
- **Knowledge grounding** points at your tenant's document IDs, so it can't be exported. Re-attach it after every import.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
