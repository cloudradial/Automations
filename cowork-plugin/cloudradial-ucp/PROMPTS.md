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
| `What feedback has Contoso submitted in the last 30 days?` | feedback-analysis | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/feedback-analysis/README.md#review-recent-feedback) |
| `Fix a feedback entry for ticket 123456` | feedback-analysis | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/feedback-analysis/README.md#fix-a-feedback-entry) |
| `Move feedback to another company` | feedback-analysis | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/feedback-analysis/README.md#move-feedback-to-another-company) |
| `Which of my clients have the lowest CSAT this quarter?` | feedback-analysis | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/feedback-analysis/README.md#compare-satisfaction) |

### Domains, certificates and reports

| Say this | Skill | Full prompt |
|---|---|---|
| `Which of my managed domains expire in the next 90 days?` | service-management | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/service-management/README.md#domain-expirations) |
| `Which of Contoso's certificates expire in the next 30 days?` | reporting-admin | [Open](https://github.com/cloudradial/Automations/blob/main/cowork-plugin/cloudradial-ucp/skills/reporting-admin/README.md#certificate-expirations) |

### What stays in the portal

The CloudRadial API doesn't cover these, so the plugin lists them for you instead of doing them: portal branding (logo, colors, theme), security roles and SSO, connecting integrations (PSA, Microsoft 365, RMM), deploying the endpoint agent, approval workflows and automations on a request form, the feedback widget and CSAT surveys, scheduled report delivery, a course's exam passing score, copying an assessment template, deleting assessments, and attaching files to archived reports.

For work that should run on its own (on a schedule, from a form, or from ServiceAI), use the matching [AutomationAI automations](https://github.com/cloudradial/Automations/tree/main).
