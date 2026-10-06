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
| `get_resource` | Retrieve one resource by ID | `resource_type`, `id` |
| `create_resource` | Create a new resource | `resource_type`, `data` |
| `update_resource` | PUT (full) or PATCH (partial) update | `resource_type`, `id`, `data` |
| `delete_resource` | Delete by ID | `resource_type`, `id` |
| `user_lookup` | Find users by email, name, or company | one of `email`/`name`/`company_id` |
| `manage_tokens` | List, get, set or delete replacement tokens (the @Token values forms and automations fill in), partner-level or per company. Not API keys. | `action` |
| `endpoint_update_warranty` | Trigger async warranty refresh by endpoint serial number | `serial_number` |
| `courseenrollment_complete` | Mark a course enrollment completed (optional score/comment) | `enrollment_id` |
| `courseenrollment_for_user` | Get a user's enrollment record for a specific course | `course_id`, `user_id` |
| `raw_api_call` | Direct API call for advanced cases | `path` |

### OData parameter conventions

For `list_resources` and `count_resources`, pass OData parameters **without** the leading `$`: `filter`, `select`, `orderby`, `top`, `skip`, `expand`, `search`. The server adds the `$` when forwarding. Defaults to `top=100` if unspecified (pagination by default to avoid hammering the API). Max page is 200; walk through larger pages by incrementing `skip`.

### Field-name quirks

- Articles use `subject` (not `title`).
- Courses use `name` (not `title`).
- `archive_item` composite key — pass `archive_id` and `id`.
- `service_install` composite key — pass `endpoint_id` and `service_id` (or `id = serviceId` on update/delete).

### Errors

- **"credentials not configured"** → defer to the `setup` skill.
- **401/403 from CloudRadial** → stored credentials are invalid. Run `setup` to rotate.
- **404** → resource not found, verify the ID.

## Resource Types

### course
Training course containers. Key fields: `courseId`, `companyId`, `name` (NOT `title`), `description` (HTML), `shortDescription`, `category`, `estimatedTime`, `isRequired`, `passScore`, `validMonths`, `enrollmentCount`, `completionCount`.

### course_lesson
Individual lessons within a course. Key fields: `courseLessonId`, `courseId`, `companyId`, `title`, `overview`, `text` (HTML body content), `category`, `order`.

### course_enrollment
Enrollment records tracking user progress. Key fields: `courseEnrollmentId`, `courseId`, `companyId`, `userId`, `status`, `score`, `dateCompleted`.

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

1. **Create the course.** Call `create_resource` with `resource_type: "course"` and `data: { companyId: 42, name: "Course Name Here", description: "<p>HTML course overview shown to learners</p>", category: "Security", estimatedTime: "30 minutes", isRequired: false, passScore: 80 }`. The response includes the new `courseId`.

2. **Create each lesson** in order. Call `create_resource` with `resource_type: "course_lesson"` and `data: { courseId: 999, companyId: 42, title: "Lesson 1: Introduction", overview: "Brief summary of this lesson", text: "<p>Full HTML lesson content goes here.</p>", order: 1 }`.

3. **Repeat** for each lesson, incrementing the `order` field (2, 3, 4...).

4. **Final Exam lesson** — Create as a regular lesson with minimal text (e.g., "Complete the exam below to finish this course."). Quiz questions and answer tracking are handled by the CloudRadial platform separately, not in the lesson text.

5. **For large lesson content**, assemble the HTML in your working notes or local variables across multiple turns, then pass the combined string as `text` in a single `create_resource` call.

### Build a Course from a Document

1. 