---
name: course-management
description: >
  Manage CloudRadial training courses, lessons, and enrollments. Use when the user says
  "create a course", "build a training", "list courses", "check enrollments",
  "course completion", "add a lesson", "training status for [company]",
  "who completed the course", "build out a course on [topic]", or needs to create,
  review, or analyze training content and enrollment data in CloudRadial portals.
metadata:
  version: "1.0.0"
---

# Course Management

Create, list, and analyze training courses, lessons, and enrollments across CloudRadial portals.

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

## Resource Types

### course
Training course containers. Key fields: `courseId`, `companyId`, `name` (NOT `title`), `description` (HTML), `shortDescription`, `category`, `estimatedTime` (integer, minutes), `isRequired`, `passScore` (percentage), `validMonths` (0 = never expires), `enrollmentCount`, `completionCount`. Creating one requires `companyId`, `name`, `description`, `shortDescription`, `category` and `estimatedTime`.

### course_lesson
Individual lessons within a course. Key fields: `courseLessonId`, `courseId`, `companyId`, `title`, `overview`, `text` (HTML body content), `category`, `order`. Creating one requires `companyId`, `courseId`, `title`, `overview`, `category` and `text`. Pass `company_id` to `get_resource`, `update_resource` and `delete_resource` for a lesson (the tool looks it up if you leave it out).

### course_enrollment
Enrollment records tracking user progress. Key fields: `courseEnrollmentId`, `courseId`, `companyId`, `userId`, `currentLessonId`, `dateEnrolled`, `dateLastAccess`, `isCompleted`, `dateCompleted`, `isExpired`, `daysSinceEnrollment`. There is no status or score field: use `isCompleted` and `dateCompleted`. Create with `courseId` and `userId`. `get_resource` works by `courseEnrollmentId`; the API can't delete an enrollment.

### course_lesson_history
Per-lesson progress for one user: which lessons they finished and their score. Composite key: `courseId`, `applicationUserId` (a string), `courseLessonId`. Create body requires `companyId`, `courseId`, `applicationUserId`, `courseLessonId`, `completedScore`. List with `list_resources` and `filter: "courseId eq 372"` (add `and applicationUserId eq '<id>'` for one user). Use it to answer "which lesson did Sam stop at" or to record lesson completions migrated from another training tool.

## Example Calls

**List courses for a company:** Call `list_resources` with `resource_type: "course"`, `filter: "companyId eq 42"`.

**List lessons for a course (use list_resources, not get_resource):** Call `list_resources` with `resource_type: "course_lesson"`, `filter: "courseId eq 372"`, `orderby: "order asc"`.

**Note:** Use `list_resources` with `filter: "courseId eq X"` to get course details and lessons. The `get_resource` operation for courses may return incomplete data (known API quirk).

**Check enrollments for a company:** Call `list_resources` with `resource_type: "course_enrollment"`, `filter: "companyId eq 42"`.

**See where each user is in a course:** Call `list_resources` with `resource_type: "course_lesson_history"`, `filter: "courseId eq 372"`, then match `courseLessonId` against the course's lessons.

**Record a lesson as completed:** Call `create_resource` with `resource_type: "course_lesson_history"` and `data: { companyId, courseId, applicationUserId, courseLessonId, completedScore }`. Confirm with the user first; this changes their training records.

## API Reference

For exact field names and schema details, read `${CLAUDE_PLUGIN_ROOT}/references/api-reference.md`.

## Workflows

### Review Training Status for a Company

1. List courses filtered by companyId
2. For each course, note enrollmentCount and completionCount
3. List enrollments filtered by companyId to get per-user status
4. Summarize: total courses available, total enrollments, completion rate, overdue items

### Build a Course from Scratch

Building a course is a two-step process: create the course container, then create each lesson inside it.

1. **Create the course.** Call `create_resource` with `resource_type: "course"` and `data: { companyId: 42, name: "Course Name Here", shortDescription: "One-line summary shown on the course card", description: "<p>HTML course overview shown to learners</p>", category: "Security", estimatedTime: 30, isRequired: false, passScore: 80 }`. `estimatedTime` is a whole number of minutes. The response includes the new `courseId`.

2. **Create each lesson** in order. Call `create_resource` with `resource_type: "course_lesson"` and `data: { courseId: 999, companyId: 42, title: "Lesson 1: Introduction", overview: "Brief summary of this lesson", category: "Security", text: "<p>Full HTML lesson content goes here.</p>", order: 1 }`.

3. **Repeat** for each lesson, incrementing the `order` field (2, 3, 4...).

4. **Final Exam lesson** — Create as a regular lesson with minimal text (e.g., "Complete the exam below to finish this course."). Quiz questions and answer tracking are handled by the CloudRadial platform separately, not in the lesson text.

5. **For large lesson content**, assemble the HTML in your working notes or local variables across multiple turns, then pass the combined string as `text` in a single `create_resource` call.

### Build a Course from a Document

1. If the user provides a markdown or text document, convert it to HTML sections
2. Split into logical lessons (one per major heading or topic)
3. Create the course container (with `shortDescription` and an integer `estimatedTime`)
4. Create each lesson with the HTML content, a `category` and an `overview`, maintaining logical ordering
5. Add a Final Exam lesson at the end if the course requires assessment

### Enrollment Analysis

1. List enrollments for a company or specific course
2. Group by progress: completed (`isCompleted` true), in progress (not completed but has a `dateLastAccess`), not started, and expired (`isExpired` true)
3. Calculate completion rates
4. Identify users who haven't started required courses
5. Present as an actionable summary
