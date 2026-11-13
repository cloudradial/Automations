# CloudRadial UCP MCP Plugin - ChatGPT Codex

Manage your clients' CloudRadial portals by asking Codex in plain English. Look up a client, set up a portal, build training and assessments, or report across every client, without scripts or switching screens.

## What you can ask

- **Get started.** Codex connects to your portal and gives you a tour. "Set up the CloudRadial plugin"
- **Look up a client and prepare for a meeting.** Get a client's portal at a glance before a call or a QBR. "Prepare me for my meeting with Contoso"
- **Set up a client portal.** Add companies and users, build request forms, seed knowledge base articles, and create courses and assessments. "Seed Contoso with 10 starter KB articles"
- **Run the service day to day.** Check training progress, audit portal content, and keep your company list tidy. "Who has completed the security training at Acme Corp?"
- **Devices and lifecycle.** See warranty status and plan hardware refreshes. "Which of Contoso's devices are out of warranty?"
- **Compliance and satisfaction.** Check assessment results, Microsoft Secure Score and client feedback, for one client or all of them. "Roll up assessment scores across all my clients"
- **Communicate with clients.** Put a notice on users' desktops with Signal, or a banner or message in their portal, after you approve the audience and wording. "Remind Pat Jones that their password expires Friday"
- **Reports and archives.** Upload report PDFs into clients' archives and find the reports that are late or alerting. "Upload this backup report to Contoso's Nightly Backups folder"
- **Access, policies and audit.** Review who has admin, change roles and feature sets, check policy compliance and licenses, set up webhooks, and see who changed what, with every change previewed first. "Who has admin access in Contoso's portal?"
- **Domains, certificates and reports.** Spot what is about to expire. "Which of my managed domains expire in the next 90 days?"

The plugin confirms the company and shows you any change before it writes to your portal. A few things, such as portal branding, SSO and connecting integrations, still happen in the portal itself, and the plugin lists those for you instead.

[See every example prompt](https://github.com/cloudradial/Automations/tree/main/codex-plugin#technical-details)

## What it protects

- **Your API keys never go into chat.** You type them into a private form that opens on your own computer.
- **Keys are checked before they are saved.** Bad keys are never stored.
- **Keys stay in your computer's own secure keychain.** Windows Credential Manager, macOS Keychain, or Linux Secret Service. Nothing is saved to a plain file.
- **Nothing is hosted.** The plugin runs on your computer and talks straight to CloudRadial.

## Works with

- ChatGPT Codex
- Windows, macOS and Linux
- CloudRadial portals in the US or Europe
- It is the same plugin as the [Claude version](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp), and the same file also installs in Claude Cowork, Claude Desktop and Claude Code.

## What you need

- A CloudRadial public key and private key, from **Partner → Settings → Configuration → Integrations → API** (Add API Key) in your CloudRadial admin portal
- Node.js 18 or newer on your computer, with npm for the first setup

## Set it up

1. [**Download cloudradial-ucp.plugin**](https://github.com/cloudradial/Automations/releases/latest/download/cloudradial-ucp.plugin). It is one file for Windows, macOS and Linux. See what is new in the [release notes](https://github.com/cloudradial/Automations/releases/latest).
2. **Install it in Codex** as a Codex plugin.
3. **Connect your portal.** Start a new conversation and type **Setup the CloudRadial Plugin**. A form opens in your browser. Enter your public and private keys, pick your region, and save.
4. **Try it.** Ask "Prepare me for my meeting with Contoso", using one of your own clients.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/codex-plugin#technical-details) list every example prompt, the skills, how it works, and how keys are stored.

## What's new

**2.8.0** ([release notes](https://github.com/cloudradial/Automations/releases/tag/v2.8.0))
- Covers the rest of the CloudRadial API: security roles and role assignments, feature sets, support PINs, policy review and exceptions, licenses and who holds them, webhooks, the audit log and sync logs, Signal devices, and Microsoft 365 groups and admins.
- Create assessments and templates directly, edit single questions, and record answers without re-importing a spreadsheet.
- Dashboard widgets, media and quickstart file uploads, and attachments on portal messages.
- Every change to access, policies, licenses or webhooks is previewed and waits for your yes. Webhook secrets and header values never go into chat.
- New skills: Access Control, Policies & Licenses, and Webhooks & Audit (31 tools, 20 skills).

**2.7.0** ([release notes](https://github.com/cloudradial/Automations/releases/tag/v2.7.0))
- Signal desktop notices: preview who a message reaches, send, check who read or acknowledged it, and retract it. Portal banners and portal messages.
- Upload report files (PDF, XLSX and more) into clients' archive folders, set up folders for every client, and find overdue or alerting reports.
- Microsoft Secure Score for one client or all of them, with the top improvement actions; it also feeds the QBR deliverable.
- Run, archive and delete assessments, and remove course enrollments.
- Fixes: menu edits no longer fail with HTTP 415, large lists can be read in full, and deleting a partner-level token needs confirmation.
- New skills: Client Communications and Report Archive.

**2.6.4** ([release notes](https://github.com/cloudradial/Automations/releases/tag/v2.6.4))
- Fixed "Forbidden" when saving API keys in the local setup form.

Earlier versions are on the [releases page](https://github.com/cloudradial/Automations/releases?q=v2.&expanded=true).

---

## Technical details

**Marketplace ID:** AAI-00008 | **Type:** Plugin (Codex) | **Version:** 2.8.0

## Install

### Step 1: Get the plugin file

[**Download cloudradial-ucp.plugin**](https://github.com/cloudradial/Automations/releases/latest/download/cloudradial-ucp.plugin). It's **one file for macOS, Windows and Linux**; the older per-computer downloads are no longer needed. See what is new in the [release notes](https://github.com/cloudradial/Automations/releases/latest).

### Step 2: Install it

The file carries two manifests, so the same file installs in either app:

- **Codex:** install it as a Codex plugin. Codex reads `.codex-plugin/plugin.json`, which loads the skills and starts the MCP server from `.codex-mcp.json`.
- **Claude Code, Claude Desktop or Cowork:** see the [Claude plugin install steps](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp#install--start-here).

### Step 3: Set it up

Start a new conversation and type:

> **Setup the CloudRadial Plugin**

Setup checks your computer's keychain first, then opens a local browser form for your CloudRadial **public key** and **private key** (in your CloudRadial admin portal under **Partner → Settings → Configuration → Integrations → API** (Add API Key)) and your region. The keys are checked with a live call and saved in your OS keychain. **Don't paste API keys into chat.**

### Step 4: Try something

Pick any prompt below, or ask in your own words.

<!-- prompts:start -->
<!-- Generated from cowork-plugin/cloudradial-ucp/PROMPTS.md by scripts/sync-prompts.mjs. Edit PROMPTS.md, not this block. -->

## What you can do

Copy a prompt into Claude or Codex and swap in your own company names or IDs. Each one links to the full prompt in that skill's guide, which shows what to ask for, what you get, and what to watch for. The plugin confirms the company and shows you any change before it writes to your portal. Every prompt works through the CloudRadial API, in both the Claude (Cowork, Claude Desktop, Claude Code) and Codex versions of the plugin.

### Get started

| Say this | Skill | Full prompt |
|---|---|---|
| `Set up the CloudRadial plugin` | setup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/setup/README.md#set-up-the-plugin) |
| `Is the CloudRadial plugin configured?` | setup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/setup/README.md#check-the-connection) |
| `Give me a tour of the CloudRadial plugin` | setup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/setup/README.md#take-a-tour) |

### Look up a client and prepare for a meeting

| Say this | Skill | Full prompt |
|---|---|---|
| `Look up Acme Corp in CloudRadial` | portal-lookup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/portal-lookup/README.md#find-a-client) |
| `Prepare me for my meeting with Contoso` | portal-lookup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/portal-lookup/README.md#prepare-for-a-meeting) |
| `How is Acme Corp doing in their portal?` | portal-lookup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/portal-lookup/README.md#check-portal-adoption) |
| `Prep a QBR for Acme Corp` | portal-setup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/portal-setup/README.md#prep-a-qbr) |

### Set up a client portal

Walk a new client through implementation, or set up one area at a time. The plugin does every step the API supports and gives you a short list of the steps that stay in the portal.

| Say this | Skill | Full prompt |
|---|---|---|
| `What does Contoso need next?` | portal-setup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/portal-setup/README.md#plan-the-next-step) |
| `Walk me through Session 2 for company 42` | portal-setup | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/portal-setup/README.md#run-an-implementation-session) |
| `Create a new company called Acme Corp` | company-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/company-management/README.md#create-a-company) |
| `Add jane@contoso.com, Jane Doe, to Contoso's portal` | user-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/user-management/README.md#add-a-user) |
| `Build a New User request form for Acme Corp` | content-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/content-management/README.md#build-a-request-form) |
| `Seed Contoso with 10 starter KB articles` | content-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/content-management/README.md#seed-a-knowledge-base) |
| `Add a "Get Help" menu tile to Contoso's portal` | content-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/content-management/README.md#add-a-menu-tile) |
| `Build a Service Overview dashboard on Contoso's portal` | content-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/content-management/README.md#build-a-portal-dashboard) |
| `Add a quickstart to Contoso's home page` | reporting-admin | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/reporting-admin/README.md#add-a-quickstart) |
| `Set Contoso's SupportPhone token to 555-0100` | reporting-admin | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/reporting-admin/README.md#set-a-replacement-token) |
| `Build a phishing-awareness course for Contoso` | course-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/course-management/README.md#build-a-training-course) |
| `Create a CIS Controls assessment for Contoso` | assessment-compliance | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/assessment-compliance/README.md#create-an-assessment-from-questions) |
| `Add contoso.com as a managed domain` | service-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/service-management/README.md#add-a-domain) |

### Run the service day to day

| Say this | Skill | Full prompt |
|---|---|---|
| `Who has completed the security training at Acme Corp?` | course-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/course-management/README.md#check-who-finished) |
| `Audit Contoso's portal content` | content-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/content-management/README.md#audit-portal-content) |
| `List all my companies` | company-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/company-management/README.md#list-and-audit-companies) |
| `Rename the "Office 365 Only" company group` | company-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/company-management/README.md#rename-a-company-group) |
| `Remove Sam from the phishing course at Contoso` | course-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/course-management/README.md#remove-someone-from-a-course) |

### Communicate with clients

Put a notice on client users' desktops with Signal, or a banner or message in their portal. The plugin shows you who it reaches and the exact message, and sends nothing until you say yes.

| Say this | Skill | Full prompt |
|---|---|---|
| `Remind Pat Jones at Contoso that their password expires Friday` | client-communications | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/client-communications/README.md#send-a-personal-reminder) |
| `Announce Saturday's maintenance window to everyone at Contoso` | client-communications | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/client-communications/README.md#announce-planned-maintenance) |
| `Send an urgent outage notice to the Microsoft 365 company group` | client-communications | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/client-communications/README.md#send-an-outage-notice) |
| `Who has acknowledged the password reminder?` | client-communications | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/client-communications/README.md#check-who-read-it) |
| `Retract this morning's outage notice` | client-communications | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/client-communications/README.md#retract-a-notice) |
| `Add a banner for the Managed Plus group about our after-hours line` | client-communications | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/client-communications/README.md#add-a-portal-banner) |
| `Post an important message to Contoso's portal about the new password policy` | client-communications | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/client-communications/README.md#post-a-portal-message) |

### Reports and archives

| Say this | Skill | Full prompt |
|---|---|---|
| `Upload this backup report to Contoso's Nightly Backups folder` | report-archive | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/report-archive/README.md#upload-a-report) |
| `Upload this month's patch reports, one per client` | report-archive | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/report-archive/README.md#upload-a-batch-for-every-client) |
| `Give every client a Security Audits archive folder` | report-archive | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/report-archive/README.md#set-up-a-folder-for-every-client) |
| `Which clients haven't received their reports on time?` | report-archive | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/report-archive/README.md#find-overdue-reports) |
| `Which of Contoso's archived reports raised an alert this month?` | report-archive | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/report-archive/README.md#find-failed-reports) |
| `Publish Contoso's Q4 review PDF to their portal and let them know` | client-deliverable | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/client-deliverable/README.md#publish-the-qbr-to-the-clients-portal) |

### Devices and lifecycle

| Say this | Skill | Full prompt |
|---|---|---|
| `Which of Contoso's devices are out of warranty?` | endpoint-reporting | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/endpoint-reporting/README.md#warranty-report) |
| `Set the warranty end date on Contoso's laptop` | endpoint-reporting | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/endpoint-reporting/README.md#write-a-warranty-date-by-hand) |
| `Build hardware refresh cards for Contoso` | endpoint-lifecycle-cards | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/endpoint-lifecycle-cards/README.md#build-refresh-cards) |
| `Build a hardware refresh roadmap for Contoso` | client-deliverable | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/client-deliverable/README.md#build-a-refresh-roadmap) |

### Compliance and satisfaction

| Say this | Skill | Full prompt |
|---|---|---|
| `How is Contoso doing on compliance?` | assessment-compliance | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/assessment-compliance/README.md#check-compliance) |
| `Turn this spreadsheet into an assessment` | assessment-compliance | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/assessment-compliance/README.md#import-a-spreadsheet) |
| `Roll up assessment scores across all my clients` | assessment-export | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/assessment-export/README.md#roll-up-every-client) |
| `What's Contoso's Secure Score and its five biggest quick wins?` | assessment-compliance | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/assessment-compliance/README.md#find-secure-score-quick-wins) |
| `Rank all my clients by Secure Score, lowest first` | assessment-export | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/assessment-export/README.md#compare-secure-score-across-clients) |
| `Add Contoso's Secure Score to their QBR` | client-deliverable | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/client-deliverable/README.md#add-secure-score-to-the-qbr) |
| `Mark MFA compliant in Contoso's "2026 Security Review"` | assessment-compliance | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/assessment-compliance/README.md#record-answers) |
| `Run Contoso's "2026 Security Review" assessment` | assessment-compliance | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/assessment-compliance/README.md#run-an-assessment) |
| `Delete the empty "Test Review" assessment in Contoso's portal` | assessment-compliance | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/assessment-compliance/README.md#delete-a-test-assessment) |
| `What feedback has Contoso submitted in the last 30 days?` | feedback-analysis | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/feedback-analysis/README.md#review-recent-feedback) |
| `Fix a feedback entry for ticket 123456` | feedback-analysis | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/feedback-analysis/README.md#fix-a-feedback-entry) |
| `Move feedback to another company` | feedback-analysis | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/feedback-analysis/README.md#move-feedback-to-another-company) |
| `Which of my clients have the lowest CSAT this quarter?` | feedback-analysis | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/feedback-analysis/README.md#compare-satisfaction) |

### Access and security

Roles, role assignments, feature sets and support PINs. Every change is previewed and waits for your yes.

| Say this | Skill | Full prompt |
|---|---|---|
| `Who has admin access in Contoso's portal?` | access-control | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/access-control/README.md#review-who-has-access) |
| `Give Pat Jones the Approver role at Contoso` | access-control | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/access-control/README.md#give-someone-a-role) |
| `Create a "Ticket Viewer" role` | access-control | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/access-control/README.md#create-a-role) |
| `Move Contoso and Fabrikam onto the Essentials feature set` | access-control | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/access-control/README.md#change-which-companies-use-a-feature-set) |
| `Set Pat Jones's support PIN` | access-control | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/access-control/README.md#set-a-support-pin) |
| `Revoke the Signal install on Pat's stolen laptop` | access-control | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/access-control/README.md#reset-or-revoke-a-signal-device) |

### Policies, licenses and Microsoft 365

| Say this | Skill | Full prompt |
|---|---|---|
| `Which of Contoso's policies are failing?` | policies-licenses | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/policies-licenses/README.md#review-policy-compliance) |
| `Ignore the encryption exception on Contoso's build server` | policies-licenses | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/policies-licenses/README.md#accept-a-policy-exception) |
| `Add a policy that flags computers over 5 years old` | policies-licenses | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/policies-licenses/README.md#add-a-policy) |
| `Which licenses have the most unused seats?` | policies-licenses | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/policies-licenses/README.md#find-unused-licenses) |
| `Who at Contoso holds a Microsoft 365 E3 license?` | policies-licenses | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/policies-licenses/README.md#check-who-holds-a-license) |
| `Who are Contoso's Microsoft 365 admins?` | policies-licenses | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/policies-licenses/README.md#list-microsoft-365-admins) |

### Webhooks and audit

| Say this | Skill | Full prompt |
|---|---|---|
| `Create a "PSA intake" webhook` | webhooks-audit | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/webhooks-audit/README.md#create-a-webhook) |
| `Send a test to the "PSA intake" webhook` | webhooks-audit | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/webhooks-audit/README.md#test-a-webhook) |
| `Why did the "PSA intake" webhook stop working?` | webhooks-audit | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/webhooks-audit/README.md#find-out-why-a-webhook-failed) |
| `Rotate the signing secret on the "PSA intake" webhook` | webhooks-audit | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/webhooks-audit/README.md#rotate-a-signing-secret) |
| `Who changed Contoso's portal this week?` | webhooks-audit | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/webhooks-audit/README.md#see-who-changed-what) |
| `Did Contoso's PSA ticket sync run today?` | webhooks-audit | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/webhooks-audit/README.md#check-a-sync) |

### Domains, certificates and reports

| Say this | Skill | Full prompt |
|---|---|---|
| `Which of my managed domains expire in the next 90 days?` | service-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/service-management/README.md#domain-expirations) |
| `Which of Contoso's certificates expire in the next 30 days?` | reporting-admin | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/reporting-admin/README.md#certificate-expirations) |

### What stays in the portal

The CloudRadial API doesn't cover these, so the plugin lists them for you instead of doing them: portal branding (logo, colors, theme), SSO, connecting integrations (PSA, Microsoft 365, RMM), deploying the endpoint agent, approval workflows and automations on a request form, the feedback widget and CSAT surveys, scheduled report delivery, a course's exam passing score, and copying an assessment template. Signal messages need Signal enabled for your partner account.

For work that should run on its own (on a schedule, from a form, or from ServiceAI), use the matching [AutomationAI automations](https://github.com/cloudradial/Automations/tree/main).

<!-- prompts:end -->

## Skills (20)

| Skill | What it does |
|-------|--------------|
| **[setup](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/setup)** | First-run setup and credential management |
| **[portal-setup](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/portal-setup)** | Walk a client through the five-session implementation; what the API sets up and what stays in the portal |
| **[portal-lookup](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/portal-lookup)** | Look up companies, check portal status, prepare for meetings |
| **[company-management](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/company-management)** | Create, update, group and audit companies |
| **[user-management](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/user-management)** | Find, add and analyze portal users |
| **[content-management](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/content-management)** | KB articles, service catalog forms and their questions, menus |
| **[course-management](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/course-management)** | Courses from a topic, a document or a YouTube link; enrollments and lesson progress |
| **[assessment-compliance](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/assessment-compliance)** | Review assessments; create or refresh one from questions or a spreadsheet; flexible assets |
| **[assessment-export](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/assessment-export)** | Roll up assessment results across every client into an executive summary |
| **[endpoint-reporting](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/endpoint-reporting)** | Device inventory, warranty reports, software audits |
| **[endpoint-lifecycle-cards](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/endpoint-lifecycle-cards)** | One Planner card per hardware-refresh category, with priorities |
| **[client-deliverable](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/client-deliverable)** | vCIO deliverable: roadmap, budget, machine audit, licenses |
| **[feedback-analysis](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/feedback-analysis)** | Feedback, CSAT trends, satisfaction reporting |
| **[service-management](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/service-management)** | Services, installs, domains, products |
| **[reporting-admin](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/reporting-admin)** | Archives, certificates, company groups, quickstarts, media, replacement tokens, raw API access |
| **[client-communications](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/client-communications)** | Signal desktop notices, portal banners and portal messages, previewed before anything is sent |
| **[report-archive](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/report-archive)** | Upload report files into clients' archives, set up archive folders, find overdue or alerting reports |
| **[access-control](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/access-control)** | Security roles, role assignments, feature sets, support PINs and Signal installs, every change previewed |
| **[policies-licenses](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/policies-licenses)** | Policy review and exceptions, policies, licenses and their users, Microsoft 365 groups and admins |
| **[webhooks-audit](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp/skills/webhooks-audit)** | Webhook actions (secrets kept out of chat), audit events, sessions and sync logs |

## How it works

```
You in Codex
     |
     |  MCP tool calls (stdio)
     v
server/index.mjs  (bundled in the plugin, pure JavaScript)
     |
     |  HTTPS with HTTP Basic auth (keys from the OS keychain or environment variables)
     v
CloudRadial API V2
```

The plugin is built from the same source as the Claude plugin. The tool reference is in the [Claude plugin README](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp#mcp-tools-31).

## Credentials and security

- **Stored in your OS keychain only:** Windows Credential Manager, macOS Keychain, or Linux Secret Service. There's no encrypted-file fallback.
- **Keys stay out of chat.** You enter them in a local form on 127.0.0.1, protected by a one-time token and a ten-minute expiry.
- **Checked before saving.** The keys go straight to CloudRadial for a live check, so bad keys are never stored.
- **First-time setup needs npm** to install the keychain helper for your OS and CPU.
- **Environment variables** `CLOUDRADIAL_PUBLIC_KEY` and `CLOUDRADIAL_PRIVATE_KEY` still work and take precedence.
- **EU partners:** pick Europe as the region in the setup form.

## Requirements

- Node.js 18 or newer, with npm for first-time setup
- CloudRadial API public and private keys

## Documentation

- [Install and troubleshooting](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/DEPLOYMENT.md)
- [CloudRadial API V2 field reference](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/references/api-reference.md)

## License

MIT
