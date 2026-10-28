# Add Many Training Courses at Once

Give it a list of training courses and their lessons, and they're created in a client's portal, ready to assign. Courses that already exist are skipped, so nothing is duplicated.

## What happens

You run it from AutomationAI with a company name and your list of courses. For each course, the CloudRadial UCP Assistant checks whether a course with that name is already in the portal. If it is, it skips it and tells you. If not, it creates the course, then adds its lessons in order.

When it finishes, you get a short summary for each course: created (with how many lessons), skipped, or failed. Your clients just see the new courses in their portal, ready for you to assign.

## What it protects

- **Nothing changes without your approval.** Each course and lesson it creates waits for you to approve it first. A course with many lessons means several approvals.
- **No duplicates.** It looks for each course by name first, so running the same list twice won't create copies.
- **Nothing is made up.** It only creates the courses and lessons you gave it, with the text you gave it.
- **The right company.** If the company name matches more than one company, it lists them and stops instead of guessing.

## Works with

CloudRadial only. No PSA is needed.

## What you need

- AutomationAI
- The **CloudRadial UCP Assistant** agent, from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp)
- The CloudRadial training extension, installed and connected in AutomationAI

## Set it up

**Once, in AutomationAI:**

1. If you don't have it yet, import the [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) on **Agents > Custom > Import**. The workflow can't find the agent until it's there.
2. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/bulk-create-training-courses/v1.0.0).
3. Go to **Workflows > Import** and upload it.
4. Click **Publish**, then **Deploy**.

**Each time you want to add courses:**

1. Open the workflow and go to **Test**.
2. Enter the company name and your list of courses. Each course needs a name. A short description, category, estimated time and lessons are optional. Each lesson needs a title and its text.
3. Run it, then approve each create as it comes up.

The assistant ships in preview mode. In preview it tells you what it would create but changes nothing. When you're ready to create courses for real, take the assistant out of preview (the [assistant's page](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp#dry-run-and-going-live) shows how).

**Test it.** Run it with one short course for a test company, then check the course and its lessons appear in that company's portal.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/bulk-create-training-courses#technical-details) show the exact list format, an example, and how the workflow is built.

---

## Technical details

**Formerly:** Course Bulk Import script | **Marketplace ID:** AAI-00026 | **Type:** Workflow (runs the CloudRadial UCP Assistant agent) | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/bulk-create-training-courses/v1.0.0).

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **CloudRadial UCP Assistant** agent, [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/cloudradial-ucp/cloudradial-ucp.agent.yml) from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`bulk-create-training-courses.yml`](https://github.com/cloudradial/Automations/blob/main/bulk-create-training-courses/bulk-create-training-courses.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `bulk-create-training-courses.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/bulk-create-training-courses/bulk-create-training-courses.yml) |
| Download `bulk-create-training-courses.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/bulk-create-training-courses/v1.0.0) |
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
