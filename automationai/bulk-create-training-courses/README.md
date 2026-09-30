# Bulk-Create Training Courses

Create training courses and their lessons in a CloudRadial portal from a list, without the old CSV import script. A thin **workflow** hands the list to the **CloudRadial UCP Assistant** agent, which skips courses that already exist by name and creates the rest (and their lessons) approval-gated.

**Formerly:** Course Bulk Import script (**AAI-00026**) | **Type:** Workflow (runs an agent)

## How it works

`Start → Read courses (validate the run input) → Create courses (Agent node running cloudradial-ucp-assistant) → End`. The agent creates each course, then its lessons against the new course id; it searches by name first, so re-runs don't duplicate.

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](../cloudradial-ucp/) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
2. Make sure the **`cloudradial-v2-training`** extension is installed and connected.
3. On **Workflows → Import**, upload `bulk-create-training-courses.yml`, then **Publish** and **deploy** it to your runner.
4. Run it from **Test** with the input below.

## Input

```json
{"companyName":"Acme Ltd","courses":[{"name":"Security Basics","shortDescription":"Core security habits","description":"Intro to security","category":"Security","estimatedTime":15,"lessons":[{"title":"Spotting phishing","overview":"Recognise phishing","text":"<p>Check the sender.</p>","order":1}]}]}
```

Pass `companyName` **or** `companyId`. Each course needs a `name`; `shortDescription`, `description`, `category`, `estimatedTime`, and a `lessons` array are optional. Each lesson needs `title` and `text`.

## Notes

- Every create is **approval-gated** (`autoApprove: false`). A course with many lessons means several approvals.
- **Requires:** AutomationAI + the CloudRadial UCP Assistant agent + the `cloudradial-v2-training` extension.
