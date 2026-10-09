# Add Many Training Courses at Once

Give it a list of courses and lessons and they're created in the client's portal, ready to assign, with any that already exist skipped.

**Formerly:** Course Bulk Import script | **Marketplace ID:** AAI-00026 | **Type:** Workflow (runs the CloudRadial UCP Assistant agent)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **CloudRadial UCP Assistant** agent, [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/cloudradial-ucp/cloudradial-ucp.agent.yml) from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`bulk-create-training-courses.yml`](https://github.com/cloudradial/Automations/blob/main/bulk-create-training-courses/bulk-create-training-courses.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `bulk-create-training-courses.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/bulk-create-training-courses/bulk-create-training-courses.yml) |
| Download `bulk-create-training-courses.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/bulk-create-training-courses/bulk-create-training-courses.yml) |
| Needs the agent | [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) |
| All files in this automation | [bulk-create-training-courses](https://github.com/cloudradial/Automations/tree/main/bulk-create-training-courses) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/bulk-create-training-courses) |
| Marketplace listing | [AAI-00026](https://automations.cloudradial.com/marketplace/AAI-00026) |

## How it works

Create training courses and their lessons in a CloudRadial portal from a list, without the old CSV import script. A thin **workflow** hands the list to the **CloudRadial UCP Assistant** agent, which skips courses that already exist by name and creates the rest (and their lessons) approval-gated.

`Start → Read courses (validate the run input) → Create courses (Agent node running cloudradial-ucp-assistant) → End`. The agent creates each course, then its lessons against the new course id; it searches by name first, so re-runs don't duplicate.

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`).
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
