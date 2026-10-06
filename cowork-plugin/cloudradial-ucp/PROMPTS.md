## What you can do

Copy any prompt into Claude and swap in your own company names or IDs. Claude confirms the company and the change before it writes anything to your portal. Every prompt below works through the CloudRadial API, in both the Claude (Cowork, Claude Desktop, Claude Code) and Codex versions of the plugin.

### Get started

| Say this | What happens | Skill |
|---|---|---|
| `Setup the CloudRadial Plugin` | Guided key entry, a live check, and encrypted storage on your computer | setup |
| `Tour the plugin` | Every skill and what it does | setup |
| `Is the CloudRadial plugin configured?` | Status check that never shows the keys | setup |
| `Clear my CloudRadial credentials` | Removes the stored keys | setup |

### Look up a client and prepare for a meeting

| Say this | What happens | Skill |
|---|---|---|
| `Look up Acme Corp in CloudRadial` | Company details with user and endpoint counts | portal-lookup |
| `Prepare me for my meeting with Contoso` | Meeting prep: lifecycle stage, flags and talking points | portal-lookup |
| `How is Acme Corp doing in their portal?` | Adoption snapshot | portal-lookup |
| `Show me overviews for Acme, Contoso and Globex` | Side-by-side comparison | portal-lookup |
| `Prep a QBR for Acme Corp` | Endpoints, assessments and feedback pulled into one view | portal-setup |
| `Build a client deliverable for Contoso: roadmap, budget, machine audit and licenses` | A vCIO deliverable built in the portal | client-deliverable |
| `Recreate this ScalePad deliverable in CloudRadial` *(attach the PDF)* | The roadmap, goals and budget rebuilt as Planner items | client-deliverable |

### Set up a client portal

Walk a new client through implementation, or set up one area at a time. The plugin does every step the API supports and gives you a short list of the steps that stay in the portal (branding, integrations, security roles, agent deployment).

| Portal area | Say this | What happens | Skill |
|---|---|---|---|
| Whole portal | `Onboard a new client called Acme Corp` | Starts the five-session implementation: creates what the API can, lists the rest | portal-setup |
| Whole portal | `What does Contoso need next?` | Lifecycle stage and the next checklist | portal-setup |
| Whole portal | `Walk me through Session 2 for company 42` | The service desk session: checks, creates and to-dos | portal-setup |
| Whole portal | `What can you set up for Contoso through the API, and what do I do in the portal?` | The API-versus-portal split for every area | portal-setup |
| Company | `Create a new company called Acme Corp` | New company | company-management |
| Company | `Change the account manager for Contoso to Jane Smith` | Company updated | company-management |
| Company groups | `Add Acme Corp to the "Office 365 Only" group` | Group membership updated | company-management |
| Users | `Add jane@contoso.com, Jane Doe, to Contoso's portal` | New portal user | user-management |
| Users | `Who has access to Contoso's portal?` | Users with names, emails and roles | user-management |
| Service catalog | `Build a service catalog for Acme Corp` | Request forms for password reset, new user, hardware and software | content-management |
| Service catalog | `Add a required "Start date" question to Contoso's New User form, with JSON field ID startDate` | New question on the form | content-management |
| Knowledge base | `Seed Contoso with 10 starter KB articles` | Ten articles on common IT topics | content-management |
| Knowledge base | `Write a KB article for Contoso about resetting MFA` | One article, step by step | content-management |
| Menus | `Add a "Get Help" menu tile to Contoso's portal that opens the service catalog` | New menu tile | content-management |
| Quickstarts | `Add a quickstart to Contoso's home page on connecting to the VPN` | New quickstart guide | reporting-admin |
| Media | `Upload this image to Contoso's media library` *(attach it)* | Image stored in the portal | reporting-admin |
| Replacement tokens | `Set Contoso's SupportPhone token to 555-0100` | Every form, article and automation using `@SupportPhone` for Contoso shows the new value | reporting-admin |
| Replacement tokens | `List Contoso's replacement tokens` | Company tokens and the partner-level ones it inherits | reporting-admin |
| Training | `Build a phishing-awareness training course for Contoso` | Course with lessons and a quiz | course-management |
| Training | `Build a course for Contoso from this YouTube video: <link>` | Lessons from the video | course-management |
| Training | `Build a course from this document` *(attach it)* | Lessons from the document | course-management |
| Assessments | `Create a CIS Controls assessment for Contoso with these 20 questions` | New assessment with the questions loaded | assessment-compliance |
| Assessments | `Turn this spreadsheet into an assessment for company 42` | The .xlsx imported as an assessment | assessment-compliance |
| Assessments | `Copy our Baseline Security template into a new assessment for Acme, one set per server` | Template questions duplicated per server | assessment-compliance |
| Flexible assets | `Set up flexible-asset tracking for Contoso's network devices` | Asset type, fields and records | assessment-compliance |
| Services | `Mark the Backup service as installed on Contoso's DC01` | Service install recorded | service-management |
| Domains | `Add contoso.com as a managed domain for Contoso` | Domain added | service-management |

### Run the service day to day

| Say this | What happens | Skill |
|---|---|---|
| `Show me all unpublished articles for Contoso` | Draft content waiting for review | content-management |
| `Audit Contoso's portal content` | Articles, catalog items and menus by status, with gaps | content-management |
| `Who's completed the security training at Acme Corp?` | Enrollments with completion dates | course-management |
| `Who at Contoso hasn't finished their required training?` | Users with incomplete enrollments | course-management |
| `Which lesson did Sam stop at in the phishing course?` | Lesson-by-lesson progress | course-management |
| `How many users does Acme Corp have?` | Count by company | user-management |
| `Which of Contoso's users haven't completed security training?` | Users cross-checked with enrollments | user-management |
| `List all my companies` | Companies with endpoint counts | company-management |
| `Which companies have no portal logo?` | Branding audit across clients | company-management |

### Devices and lifecycle

| Say this | What happens | Skill |
|---|---|---|
| `How many endpoints does Acme Corp have?` | Device count | endpoint-reporting |
| `Which of Contoso's devices are out of warranty?` | Devices with expiration dates | endpoint-reporting |
| `Refresh warranty for all of Acme Corp's devices` | Warranty lookups queued by serial number | endpoint-reporting |
| `Show all software installed on endpoint 789` | Installed applications | endpoint-reporting |
| `Build a warranty expiration report for the next 6 months` | Devices expiring soon | endpoint-reporting |
| `Build hardware refresh cards for Contoso` | One Planner card per refresh category, each with a priority | endpoint-lifecycle-cards |
| `Which of Acme Corp's computers need replacing?` | The Replace list with reasons | endpoint-lifecycle-cards |

### Security, compliance and satisfaction

| Say this | What happens | Skill |
|---|---|---|
| `Show me Contoso's assessment scores` | Assessments with status, score and date | assessment-compliance |
| `How is Acme Corp doing on compliance?` | Passing, failing and in progress | assessment-compliance |
| `Which company has the lowest assessment score?` | Cross-company comparison | assessment-compliance |
| `Roll up assessment scores across all my clients` | Executive summary: totals, gaps, common issues, trends | assessment-export |
| `Which customers have the most assessment gaps?` | Clients ranked by gaps | assessment-export |
| `What feedback has Contoso submitted lately?` | Recent feedback | feedback-analysis |
| `Which of my clients have the lowest CSAT this quarter?` | Clients ranked by satisfaction | feedback-analysis |
| `Summarize themes in Contoso's recent feedback` | Grouped comment themes | feedback-analysis |

### Services, domains, certificates and reports

| Say this | What happens | Skill |
|---|---|---|
| `What services are installed for Acme Corp?` | Service installations | service-management |
| `Service coverage summary for Acme Corp` | Installed versus available | service-management |
| `Which of my managed domains expire in the next 90 days?` | Domain expiration sweep | service-management |
| `Which of Contoso's certificates expire in 30 days?` | Certificates with expiration dates | reporting-admin |
| `Show me Acme Corp's archived reports` | Archive items by date | reporting-admin |
| `Hit /v2/odata/company/$count via the API directly` | Raw API response, for anything not covered above | reporting-admin |

### What stays in the portal

The CloudRadial API doesn't cover these, so the plugin lists them for you instead of doing them: portal branding (logo, colors, theme), security roles and SSO, connecting integrations (PSA, Microsoft 365, RMM), deploying the endpoint agent, approval workflows and automations on a request form, the feedback widget and CSAT surveys, and scheduled report delivery.

For work that should run on its own (on a schedule, from a form, or from ServiceAI), use the matching [AutomationAI automations](https://github.com/cloudradial/Automations/tree/main/automationai).
