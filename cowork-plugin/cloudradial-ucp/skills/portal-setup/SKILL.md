---
name: portal-setup
description: >
  Guide a partner through setting up and configuring their CloudRadial portal for a
  client company. Use when the user says "set up a portal", "onboard a new client",
  "configure the portal for [company]", "implementation session", "portal onboarding",
  "seed content for [company]", "prepare portal for [company]", "what does [company]
  need next", "CSA pain points", "implementation checklist", or needs to walk through
  portal configuration, content seeding, or implementation sessions for a specific
  client company. This is about configuring the CloudRadial PORTAL — not the Cowork plugin.
  For plugin/credential setup, use the "setup" skill instead.
metadata:
  version: "1.0.0"
---

# Portal Setup & Implementation Guide

Guide partners through setting up and configuring CloudRadial portals for their client companies. This covers the full implementation lifecycle — from initial portal provisioning to account management handoff.

**Important:** This skill is about configuring the CloudRadial PORTAL for a client company. For setting up the Cowork plugin and storing API credentials, use the **setup** skill instead.

## How to Call the API

All CloudRadial work goes through MCP tools served by the `cloudradial-ucp` server. The plugin auto-registers the server via `.mcp.json` — no Azure Function, no Chrome extension, no local config file.

### Before any tool call

Call `setup_status` first to confirm credentials are stored. If it returns `configured: false`, defer to the `setup` skill before doing CloudRadial work.

### Available MCP tools

| Tool | Purpose | Required args |
|------|---------|---------------|
| `setup_status` | Check credential state (never returns the keys) | — |
| `search_companies` | Search companies by partial name | `name` |
| `company_overview` | Snapshot: details, user/endpoint counts, recent articles + feedback | `company_id` |
| `list_resources` | List any of 30 resource types with OData filtering | `resource_type` |
| `count_resources` | Count a resource type with optional `filter` | `resource_type` |
| `get_resource` | Retrieve one resource by ID (optional `company_id` for company-scoped types) | `resource_type`, `id` |
| `create_resource` | Create a new resource | `resource_type`, `data` |
| `update_resource` | Partial update: PATCH by default, so fields you leave out are kept. `method: "PUT"` replaces the whole record | `resource_type`, `id`, `data` |
| `delete_resource` | Delete by ID (always confirm with the user first) | `resource_type`, `id` |
| `user_lookup` | Find users by email, name, or company | one of `email`/`name`/`company_id` |
| `manage_tokens` | List, get, set or delete replacement tokens (the @Token values forms and automations fill in), partner-level or per company. Not API keys. | `action` |
| `endpoint_update_warranty` | Trigger async warranty refresh by endpoint serial number | `serial_number` |
| `courseenrollment_complete` | Mark a course enrollment completed (optional score/comment) | `enrollment_id` |
| `courseenrollment_for_user` | Get a user's enrollment record for a specific course | `course_id`, `user_id` |
| `raw_api_call` | Direct API call for advanced cases | `path` |

### OData parameter conventions

For `list_resources` and `count_resources`, pass OData parameters **without** the leading `$`: `filter`, `select`, `orderby`, `top`, `skip`, `expand`, `search`. The server adds the `$` when forwarding. Defaults to `top=100` if unspecified (pagination by default to avoid hammering the API). Max page is 200 and the API returns no next-page link, so keep incrementing `skip` until a page comes back shorter than `top`.

### Field-name quirks

- Articles use `subject` (not `title`).
- Courses use `name` (not `title`).
- `archive_item` composite key — pass `archive_id` and `id`.
- `service_install` composite key — pass `endpoint_id` and `service_id` (or `id = serviceId` on update/delete).
- `endpoint_custom_property` — get/create/update/delete take `serial_number` and `property_name`; list with `filter: "companyEndpointId eq <id>"`.
- OData returns enum fields as names (for example `enclosure: "Desktop"`), not numbers.

### Errors

- **"credentials not configured"** → defer to the `setup` skill.
- **401/403 from CloudRadial** → stored credentials are invalid. Run `setup` to rotate.
- **404** → resource not found. Verify the ID, and for `catalog_question`, `course_lesson`, `domain`, `user`, `application_user` and `token` pass `company_id`.
- Every HTTP 4xx/5xx comes back as a tool error, not as data. Read the message and fix the call instead of retrying it unchanged.

## API Reference

For exact field names and schema details, read `${CLAUDE_PLUGIN_ROOT}/references/api-reference.md`.

---

## LOMG Framework

CloudRadial follows the **Land, Onboard, Manage, Grow** (LOMG) lifecycle. Every partner and client company is somewhere on this journey. Before doing anything, determine where they are:

| Phase | Indicators | Focus |
|-------|-----------|-------|
| **Land** | Company exists, few/no users, no articles, no endpoints | Get portal provisioned, PSA connected, first users added |
| **Onboard** | Users being added, articles being created, catalogs being configured | 5-session implementation, content seeding, ticketing integration |
| **Manage** | Consistent endpoints, regular feedback, published articles | Ongoing content updates, QBR reporting, user adoption |
| **Grow** | Courses deployed, assessments running, high engagement | Advanced features, training courses, compliance tracking, co-management |

### Assess a Company's LOMG Stage

1. Pull the company overview: call `company_overview` with `company_id: "<id>"`.

2. Count key resources. Call `count_resources` once per type with `filter: "companyId eq <id>"`:
   - Users → `resource_type: "user"`
   - Endpoints → `resource_type: "endpoint"`
   - Articles → `resource_type: "article"`
   - Courses → `resource_type: "course"`
   - Assessments → `resource_type: "assessment"`, `filter: "companyId eq <id> and type eq 20"` (type 20 is an assessment; 10 is a template and 30 a run)
   - Feedback → `resource_type: "feedback"`

3. Classify:
   - **0 endpoints + 0 articles** = Land
   - **Endpoints syncing + articles being created** = Onboard
   - **Consistent endpoints + published articles + feedback** = Manage
   - **Courses + assessments + high user count** = Grow

---

## The 5-Session Implementation Process

This is the standard onboarding track for new client companies. Each session has a specific focus and checklist.

### Session 1: Portal Setup & First Impressions

**Goal:** Get the portal provisioned, branded, and connected to the PSA. First users can log in.

**Checklist:**
- [ ] Company created in CloudRadial (or synced from PSA)
- [ ] Portal branding configured (logo, colors, company name)
- [ ] PSA integration connected and syncing (ConnectWise, Autotask, HaloPSA, etc.)
- [ ] Microsoft 365 integration connected (if applicable)
- [ ] First admin user created and can log in
- [ ] Endpoint agent deployed to at least one test machine
- [ ] Portal URL shared with partner's internal team

**API actions to check/verify:**
- Search for the company: call `search_companies` with `name: "<name>"`
- Check user count: call `count_resources` with `resource_type: "user"`, `filter: "companyId eq <id>"`
- Check endpoint count: call `count_resources` with `resource_type: "endpoint"`, `filter: "companyId eq <id>"`
- Review company details: call `company_overview` with `company_id: "<id>"`
- Branding (logo, colors) can't be read or set through the API: check it in the portal

### Session 2: Ticketing & Service Desk

**Goal:** Configure the service desk experience. End users can submit tickets through the portal instead of email/phone.

**Checklist:**
- [ ] Service catalog configured with common request types
- [ ] Catalog questions set up for each service item (captures the right info)
- [ ] Ticket submission tested end-to-end (portal → PSA)
- [ ] Ticket status visibility confirmed (users can see their tickets)
- [ ] Email-to-portal redirect strategy discussed (eliminate email/phone tickets)
- [ ] Quick links or shortcuts configured for common actions

**API actions:**
- List catalogs: call `list_resources` with `resource_type: "catalog"`, `filter: "companyId eq <id>"`
- List catalog questions: call `list_resources` with `resource_type: "catalog_question"`, `filter: "companyId eq <id>"`
- Check services: call `list_resources` with `resource_type: "service"`, `filter: "companyId eq <id>"`

**Content to seed:**
- Service catalog items for: password reset, new user request, hardware request, software request, general support
- Catalog questions for each item that capture the necessary details

### Session 3: Content & Knowledge Base

**Goal:** Populate the portal with useful content. End users have self-service resources.

**Checklist:**
- [ ] KB articles created for top 10 support topics
- [ ] Articles organized by category
- [ ] Menu structure configured (navigation makes sense)
- [ ] Company-specific content vs. global content strategy decided
- [ ] Article publishing workflow established (draft → review → publish)
- [ ] Quickstart guides configured for new user onboarding

**API actions:**
- List articles: call `list_resources` with `resource_type: "article"`, `filter: "companyId eq <id>"`
- List menus: call `list_resources` with `resource_type: "menu"`, `filter: "companyId eq <id>"`
- Create articles: Use `create_resource` with `resource_type: "article"` (see content-management skill)

**Content to seed (common KB articles):**
- How to reset your password
- How to submit a support ticket
- VPN setup guide
- Email setup on mobile devices
- Microsoft 365 tips and tricks
- Approved software list
- IT policies and acceptable use
- How to request new hardware
- Remote work setup guide
- Security awareness basics

### Session 4: Reporting & QBR Preparation

**Goal:** Set up reporting dashboards and QBR templates. Partner can run business reviews.

**Checklist:**
- [ ] Endpoint reporting configured (warranty tracking, OS distribution)
- [ ] User adoption metrics accessible (login frequency, ticket volume)
- [ ] Feedback collection enabled (CSAT after ticket resolution)
- [ ] Archive reports configured for automated delivery
- [ ] QBR template prepared with key metrics
- [ ] GAP analysis tools configured (security posture, compliance)

**API actions:**
- Review endpoints: call `list_resources` with `resource_type: "endpoint"`, `filter: "companyId eq <id>"`
- Check feedback: call `list_resources` with `resource_type: "feedback"`, `filter: "companyId eq <id>"`
- Review assessments: call `list_resources` with `resource_type: "assessment"`, `filter: "companyId eq <id> and type eq 20"` (no `select`; it returns HTTP 500 on assessments)
- Check archives: call `list_resources` with `resource_type: "archive_item"`, `filter: "companyId eq <id>"`

### Session 5: Account Management Handoff

**Goal:** Transition from implementation to ongoing management. Partner's AM team takes over.

**Checklist:**
- [ ] All Session 1-4 items complete
- [ ] End users onboarded and trained (know how to use the portal)
- [ ] Courses assigned if using training features
- [ ] Ongoing content update schedule established
- [ ] Feedback loop configured (CSAT, portal feedback widget)
- [ ] AM team briefed on portal status and next steps
- [ ] Success metrics defined (ticket deflection, user adoption, CSAT scores)

**API actions:**
- Full content audit: List articles, catalogs, menus, courses, assessments
- User adoption check: Count users, review login activity
- Endpoint coverage: Count endpoints vs. known device count
- Course enrollments: call `list_resources` with `resource_type: "course_enrollment"`, `filter: "companyId eq <id>"`

## What the API can set up, and what stays in the portal

When you walk a session, do the API items for the user (after confirming each write) and hand the portal items back as a short to-do list. Never claim to have done a portal-only item.

| Area | Through the plugin | How | Portal only |
|---|---|---|---|
| Company | Create, rename, territory, account manager, PSA ids | `create_resource` / `update_resource` `company` (create needs `name`) | Logo, colors, theme and messaging settings. The API neither returns nor sets branding. |
| Company groups | Create groups, add or remove companies | `company_group`, `company_group_company` | |
| Users | Create, update, remove portal users | `user` (create needs `companyId`, `email`, `firstName`, `lastName`) | Security roles, invitations, SSO |
| Integrations | Read what's synced | `company_overview`, `list_resources` | Connecting the PSA, Microsoft 365, RMM and other integrations |
| Service catalog | Create request forms and their questions | `catalog`, `catalog_question` (see content-management) | Approval workflows and automations attached to a form; end-to-end ticket test |
| Knowledge base | Create and update articles (create needs `companyId`, `subject`, `body`, `datePublished`) | `article` | |
| Menus | Create and order menu tiles | `menu` | |
| Quickstarts | Create home-page quickstart guides | `quickstart` (see reporting-admin) | |
| Media | Upload images and documents | `media` (base64 `data`) | Using an uploaded image as the portal logo |
| Replacement tokens | Set partner-level or company tokens (`@SupportPhone`) | `manage_tokens` | |
| Training | Create courses and lessons, enroll users, record completions | `course`, `course_lesson`, `course_enrollment`, `course_lesson_history` | |
| Assessments | Create an assessment and load its questions | `assessment_import` | Running the assessment with the client |
| Flexible assets | Create types, fields and records | `flexible_asset_type`, `flexible_asset_field`, `flexible_asset` | |
| Endpoints | Read devices, set custom properties, refresh warranty | `endpoint`, `endpoint_update_warranty`, `create_resource` / `update_resource` `endpoint_custom_property` (by `serial_number` + `property_name`) | Deploying the agent |
| Services, domains, certificates | Create and update | `service`, `service_install`, `domain`, `certificate` | |
| Planner and roadmap | Create and update Planner cards | `product` (see client-deliverable, endpoint-lifecycle-cards) | |
| Feedback | Read and analyze | `feedback` | Turning on the feedback widget and CSAT surveys |
| Archives | Read archived reports | `archive_item` | Scheduling report delivery |

---

## 8 CSA Pain Points & Playbooks

These are the most common challenges that drive partners to CloudRadial. Each maps to specific portal features and configuration steps.

### 1. Eliminate Email/Phone Tickets

**Problem:** End users email or call for support instead of using the portal.
**Solution:** Service catalog + ticket submission portal
**Configure:**
- Build an intuitive service catalog with clear categories
- Add catalog questions that capture required info upfront
- Set up email redirect (auto-reply pointing to portal)
- Create a "How to Submit a Ticket" KB article
- Add the portal URL to the company's email signature

### 2. Improve GAP Analysis

**Problem:** Hard to identify gaps in a client's IT environment.
**Solution:** Assessments + endpoint reporting + flexible assets
**Configure:**
- Deploy assessments (security, compliance, infrastructure)
- Review endpoint data for warranty gaps, OS distribution
- Set up flexible assets for tracking non-standard items
- Build a GAP analysis report template using assessment results

### 3. Improve Sales Presentations

**Problem:** QBRs and sales presentations lack data-driven insights.
**Solution:** Portal reporting + archive reports + endpoint data
**Configure:**
- Pull endpoint warranty expiration data for upsell opportunities
- Aggregate user adoption metrics for value demonstration
- Generate archive reports showing before/after metrics
- Use assessment scores to identify expansion opportunities

### 4. User Training & Adoption

**Problem:** End users don't know how to use IT resources effectively.
**Solution:** Courses + lessons + enrollment tracking
**Configure:**
- Create training courses (security awareness, software basics, company policies)
- Build course lessons with HTML content
- Assign courses to users (required vs. optional)
- Track enrollment and completion rates
- Create a "Final Exam" lesson for knowledge verification

### 5. Reduce QBR Preparation Time

**Problem:** QBR prep takes hours of manual data gathering.
**Solution:** Company overview + automated reporting
**Configure:**
- Use `company_overview` to get instant snapshots
- Set up automated archive reports
- Configure feedback collection for ongoing CSAT data
- Build a standard QBR checklist that pulls from portal data

### 6. Sync PSA & Microsoft 365

**Problem:** Data silos between PSA, M365, and client-facing portal.
**Solution:** Integration configuration (done in CloudRadial admin, not via API)
**Note:** PSA and M365 integrations are configured in the CloudRadial admin portal, not through this plugin. Guide partners to Settings → Integrations.

### 7. Onboarding/Offboarding Forms

**Problem:** New hire onboarding and employee offboarding are manual, error-prone processes.
**Solution:** Service catalog forms with structured questions
**Configure:**
- Create "New Employee Onboarding" catalog item with comprehensive questions (name, department, start date, software needs, hardware needs, access requirements)
- Create "Employee Offboarding" catalog item (last day, equipment return, access revocation checklist)
- Set up automation rules in PSA to create tasks from form submissions

### 8. Replace Invarosoft / DeskDirector

**Problem:** Partner is migrating from another client portal tool.
**Solution:** Full CloudRadial implementation matching/exceeding previous capabilities
**Configure:**
- Audit the existing portal's content and features
- Recreate service catalog items, KB articles, and branding
- Migrate user accounts
- Set up equivalent integrations
- Communicate the transition to end users with training content

---

## Content Seeding Workflows


### Seed Articles for a New Company

1. Identify the company and confirm companyId
2. Check existing articles to avoid duplicates
3. Draft each article and review it with the partner first. The API has no draft or `isPublished` flag, so an article is live once created. Then call `create_resource` with:
   ```
   resource_type: "article"
   data: {
     companyId: <id>,
     subject: "Article Subject Here",
     body: "<p>HTML article content</p>",
     category: "Category Name",
     datePublished: "<today, ISO 8601>"
   }
   ```
   `companyId`, `subject`, `body` and `datePublished` are required.
4. To change an article later, call `update_resource` with only the fields to change (PATCH is the default)

### Seed a Training Course

1. Create the course container:
   ```
   create_resource with resource_type: "course"
   Required: companyId, name, description (HTML), shortDescription, category, estimatedTime (integer minutes)
   Optional: isRequired, passScore, validMonths
   ```
2. Create lessons in order:
   ```
   create_resource with resource_type: "course_lesson"
   Required: companyId, courseId, title, overview, category, text (HTML body)
   Optional: order
   ```
3. Final Exam lesson is a stub — quiz mechanics handled by the platform

### Seed a Service Catalog

1. Create catalog items:
   ```
   create_resource with resource_type: "catalog"
   Required: companyId, subject (the item's name), category
   Optional: description, shortDescription, thankYou, isNeedsApproval
   ```
   Leave the PSA routing fields (`psaBoard`, `psaType`, `psaItem` and so on) empty unless the partner gives you the exact values.
2. Add catalog questions for each item:
   ```
   create_resource with resource_type: "catalog_question"
   Required: companyCatalogId, companyId, label, order
   Optional: type, isRequired, jsonId, options, placeholder
   ```
   Copy `type` from an existing question of the same kind; the API doesn't publish names for the codes (see content-management).

### Set Endpoint Custom Properties

1. Find the endpoint's `serialNumber` with `list_resources` / `resource_type: "endpoint"`
2. Call `create_resource` with `resource_type: "endpoint_custom_property"`, `serial_number: "<serial>"`, `data: { name: "AssetTag", value: "CON-0042", dataType: "String" }`. The API doesn't list the allowed `dataType` values, so copy one from an existing property where you can
3. To change it later, call `update_resource` with `resource_type: "endpoint_custom_property"`, `serial_number`, `property_name` and `data: { value }`

---

## Implementation Readiness Check

Before any implementation session, run a quick readiness check:

1. Pull company overview with `company_overview`
2. Count users, endpoints, articles, catalogs, courses, assessments (`type eq 20`) and feedback with `count_resources`
3. List recent articles (are they being created?)
4. List recent feedback (are users engaged?)
5. Check service catalog (is ticketing configured?)
6. Assess LOMG stage
7. Identify which implementation session they're on based on what's complete vs. missing
8. Present findings and recommend next steps, listing portal-only items (branding, integrations, roles) as checks for the partner to do in the portal
