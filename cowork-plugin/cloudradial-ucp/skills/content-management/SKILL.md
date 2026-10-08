---
name: content-management
description: >
  Manage CloudRadial portal content - articles, catalogs, menus, courses, and assessments.
  Use when the user says "create an article in CloudRadial", "update portal content",
  "add a KB article to the portal", "set up a service catalog", "manage portal menus",
  "create a course", "check article status", "publish content", or needs to create,
  update, or review content within a partner's CloudRadial portal.
metadata:
  version: "1.0.0"
---

# Content Management

Create, update, and review content across CloudRadial portals using the CloudRadial MCP server.

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

If you need to check exact field names, required parameters, or schema details for any resource type, read the API reference at `${CLAUDE_PLUGIN_ROOT}/references/api-reference.md`.

## Supported Content Types

### Articles
Portal knowledge base articles. Key fields: `articleId`, `subject` (NOT `title`), `body` (HTML), `companyId`, `category`, `datePublished`, `author`, `isFavorite`, `isFrontPage`, `url`. Creating one requires `companyId`, `subject`, `body` and `datePublished`. There is no draft or `isPublished` flag in the API.

- **List articles:** Call `list_resources` with `resource_type: "article"`, `filter: "companyId eq 42"`.
- **Get article:** Call `get_resource` with `resource_type: "article"`, `id: "123"`.

### Service Catalog
Service request forms shown to end users. Key fields: `companyCatalogId`, `companyId`, `subject` (NOT `name`), `category`, `description`, `shortDescription`, `thankYou`, `isNeedsApproval`, `isSendToPsa`, and the PSA routing fields (`psaBoard`, `psaType`, `psaSubType`, `psaItem`, `psaPriority`, `psaStatus`). Creating one requires `companyId`, `subject` and `category`.

- **List catalog items:** Call `list_resources` with `resource_type: "catalog"`, `filter: "companyId eq 42"`.
- **Create a catalog item:** Call `create_resource` with `resource_type: "catalog"`, `data: { companyId, subject, category, description, shortDescription }`. Leave the PSA routing fields empty unless the user gives them; wrong board names break ticket creation.

### Catalog questions (the fields on a request form)
Key fields: `companyCatalogQuestionId`, `companyCatalogId`, `companyId`, `label`, `type`, `order`, `isRequired`, `isSubject`, `isDescription`, `options`, `placeholder`, `defaultValue`, `info`, `jsonId` (the Script / JSON Field ID automations read as `@<jsonId>`), `isIncludeInTicket`, `isUserLookup`, `hideConditions`. Creating one requires `companyCatalogId`, `companyId`, `label` and `order`.

- **List a form's questions:** Call `list_resources` with `resource_type: "catalog_question"`, `filter: "companyCatalogId eq 77"`, `orderby: "order asc"`.
- **Add a question:** Call `create_resource` with `resource_type: "catalog_question"`, `data: { companyCatalogId, companyId, label, order, type, isRequired, jsonId }`.
- **`type` is a numeric code** (0 to 230, and 999) and the API doesn't publish names for the codes. Copy the `type` from an existing question of the same kind (text, dropdown, date, user lookup) on any catalog item, and say so. Never guess a code.
- **Set `jsonId`** on every question an automation needs to read. Don't use a predefined token name such as `UserEmail` or `CompanyName`; the predefined value wins and the answer is lost.
- **Subscribed forms:** if the catalog item came from a content package, editing it may detach it from the package. Ask before changing a subscribed item.

### Menus
Portal navigation tiles. Key fields: `companyMenuId` (the ID to pass to `get_resource` / `update_resource` / `delete_resource`), `companyId`, `name`, `url`, `category`, `order`, `editRights`, `icon`, `iconColor`, `toolTip`. Creating one requires `companyId`, `name`, `url`, `category`, `order` and `editRights`.

- **List menus:** Call `list_resources` with `resource_type: "menu"`, `filter: "companyId eq 42"`.
- **Add a menu tile:** Call `create_resource` with `resource_type: "menu"`. Copy `editRights` and `category` from an existing menu on the same company, since their allowed values aren't published.

### Courses & Lessons
Training content for end users. Course uses `name` (NOT `title`); creating one requires `companyId`, `name`, `description`, `shortDescription`, `category` and `estimatedTime` (an integer number of minutes). CourseLesson uses `title`, `overview`, `category`, `text` (HTML body), and `order`; creating one requires `companyId`, `courseId`, `title`, `overview`, `category` and `text`.

- **List courses:** Call `list_resources` with `resource_type: "course"`, `filter: "companyId eq 42"`.
- **List lessons for a course:** Call `list_resources` with `resource_type: "course_lesson"`, `filter: "courseId eq 372"`.
- **Check enrollments:** Call `list_resources` with `resource_type: "course_enrollment"`, `filter: "companyId eq 42"`.

### Assessments
Security and compliance assessments. Key fields: `assessmentId`, `companyId`, `title`, `category`, `type`, `status`, `dateConducted`, `totalScore`, `maxScore`, `compliantScore`. `type` 20 is an assessment (the only type the portal's Assessments list shows); 10 is a template and 30 is a run.

- **List assessments:** Call `list_resources` with `resource_type: "assessment"`, `filter: "companyId eq 42 and type eq 20"`. Don't pass `select` for assessments; it returns HTTP 500.
- **Create or refresh one:** use the `assessment_import` tool (the assessment-compliance skill covers it).

## Workflow for Creating Articles

1. **Confirm the target company.** Call `search_companies` with `name: "<company>"`.

2. **Check existing articles** to avoid duplicates. Call `list_resources` with `resource_type: "article"`, `filter: "companyId eq <id>"`.

3. **Prepare the article content.** The `body` field accepts HTML. If converting from a document, use pandoc to extract HTML.

4. **Create the article.** Use `subject` (not `title`) for the article name. `datePublished` is required, and there's no draft flag, so confirm the content with the user before creating it. Call `create_resource` with `resource_type: "article"` and `data: { companyId: <id>, subject: "Article Title Here", category: "How To", body: "<p>Article HTML content here</p>", datePublished: "<today, ISO 8601>" }`. The response includes the new `articleId`.

5. **For large HTML bodies**, assemble the HTML in your working notes or local variables across multiple turns, then pass the combined string as `body` in a single `create_resource` call.

6. **To update an existing article**, call `update_resource` with `resource_type: "article"`, `id: "<articleId>"`, and `data: { ...only the fields to change }`. The default method is PATCH, so fields you leave out are kept.

## Workflow for Creating Courses

1. **Confirm the target company** (same as articles).

2. **Create the course container first.** Call `create_resource` with `resource_type: "course"` and `data: { companyId: <id>, name: "Course Name Here", shortDescription: "One-line summary", description: "<p>HTML course description</p>", category: "Category", estimatedTime: 30, isRequired: false, passScore: 80 }`. `estimatedTime` is a whole number of minutes. The response includes the new `courseId`.

3. **Create each lesson** in order, referencing the parent courseId. Call `create_resource` with `resource_type: "course_lesson"` and `data: { courseId: <courseId>, companyId: <companyId>, title: "Lesson Title", overview: "Brief lesson summary", category: "Category", text: "<p>HTML lesson body content</p>", order: 1 }`.

4. **Repeat** for each lesson, incrementing the `order` field.

5. **Final Exam lessons** are just stubs — quiz mechanics are handled by the CloudRadial platform separately. Create the exam lesson with minimal text (e.g., "Complete the exam below to finish this course.").

## Workflow for Auditing Portal Content

1. Identify the company.
2. Pull articles filtered by companyId. Note the total count, the categories covered, and how recent `datePublished` is.
3. Pull catalogs filtered by companyId.
4. Pull menus filtered by companyId.
5. Pull courses filtered by companyId.
6. Summarize content coverage and identify gaps (e.g., "No service catalog configured", "No articles published in the last year", "0 courses assigned").
