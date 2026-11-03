# Report on Devices, Compliance and Training by Asking

Ask about your clients' devices, warranties, assessments, documentation, feedback and training in plain English, and get briefings, audits and reports back. When you ask for a change, it shows you exactly what will change and waits for your approval first.

## What happens

This is the **CloudRadial UCP Reporting** agent, an AI agent in AutomationAI. Your team asks it questions in the **AI Playground**, and other automations run it behind the scenes. Your clients only notice once an approved change shows up in their portal.

Things you can ask it to do:

- **Brief.** "Get me ready for my call with Contoso." Devices, warranties that have run out or are about to, assessment results and recent feedback.
- **Audit.** "Which computers are out of warranty?" Old or unsupported devices, certificates about to expire, empty flexible asset types, and courses nobody has finished.
- **Report.** "What's our satisfaction score by company this quarter?" Counts and totals across your companies, in plain language.
- **Make changes, when you ask.** Add or update devices, flexible assets, certificates, courses and lessons. It removes a flexible asset type only when you name that exact type and no company has anything in it.

Setting up companies, users, tokens, request forms and menus is handled by its sibling, [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp).

## What it protects

- **Every change needs your approval.** It says exactly what will change before it makes any create, update or delete.
- **No guessing.** It finds each company, device or record by name first. If more than one matches, it asks which one you mean.
- **One client per report.** A report it saves to a client's Report Archives holds only that client's data.
- **Preview by default.** Out of the box it describes changes but doesn't make them.

## Works with

CloudRadial: devices, assessments, flexible assets, certificates, feedback, Report Archives and training courses. No PSA is needed.

## What you need

- AutomationAI
- These CloudRadial extensions, installed and connected in AutomationAI: companies, endpoints, compliance, feedback and training

## Set it up

1. **Download** the [agent file](https://github.com/cloudradial/Automations/releases/tag/cloudradial-ucp-reporting/v1.0.0).
2. In AutomationAI, go to **Agents > Custom > Import** and upload it. Importing it again later replaces the one you have.
3. Open the **AI Playground**, or import one of the automations that runs it.

It starts in preview mode. When you're ready for it to make changes, the [technical details](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp-reporting#dry-run-and-going-live) show how to switch it over. That switch applies to every automation that uses it.

**Test it.** In the **AI Playground**, ask how many devices one of your companies has, and check the answer matches your portal.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp-reporting#technical-details) cover the extensions it uses, how preview mode works, and which automations run it.

---

## Technical details

**Formerly:** part of the CloudRadial UCP Assistant (up to agent 0.1.4) | **Marketplace ID:** Not yet listed | **Type:** Agent | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/cloudradial-ucp-reporting/v1.0.0).

**Import** [`cloudradial-ucp-reporting.agent.yml`](https://github.com/cloudradial/Automations/blob/main/cloudradial-ucp-reporting/cloudradial-ucp-reporting.agent.yml) on **Agents → Custom → Import** (slug `cloudradial-ucp-reporting`). An agent only runs from a workflow that gives it a goal, or in the AI Playground.

| What | Link |
|---|---|
| View `cloudradial-ucp-reporting.agent.yml` (agent 0.1.0) | [GitHub](https://github.com/cloudradial/Automations/blob/main/cloudradial-ucp-reporting/cloudradial-ucp-reporting.agent.yml) |
| Download | [Release](https://github.com/cloudradial/Automations/releases/tag/cloudradial-ucp-reporting/v1.0.0) |
| Sibling agent | [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) |
| Used by | [Walk Into Every Client Call Prepared](https://github.com/cloudradial/Automations/tree/main/portal-lookup) |
| Used by | [Remove a Flexible Asset Type You No Longer Use](https://github.com/cloudradial/Automations/tree/main/remove-empty-flexible-asset-type) |
| Used by | [Bring IT Glue Documentation into the Portal](https://github.com/cloudradial/Automations/tree/main/itglue-to-flexible-assets) |
| Used by | [Add Many Training Courses at Once](https://github.com/cloudradial/Automations/tree/main/bulk-create-training-courses) |
| All files in this automation | [cloudradial-ucp-reporting](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp-reporting) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/cloudradial-ucp-reporting) |

## How it works

A CloudRadial **AutomationAI agent** that covers the device, compliance, feedback and training half of the **CloudRadial UCP MCP plugin**. The other half, portal setup and administration, is the [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp). They are split because all eight CloudRadial extensions together have 163 tools, and AutomationAI on OpenAI rejects a run with more than 128.

**Extensions** (103 tools): `cloudradial-v2-companies` (to find companies and users; this agent doesn't change them), `cloudradial-v2-endpoints` (devices, applications, custom properties), `cloudradial-v2-compliance` (assessments, certificates, flexible asset types, fields and rows), `cloudradial-v2-feedback` (feedback and Report Archives) and `cloudradial-v2-training` (courses, lessons, enrollments). They use the runner secrets `CloudRadial-BaseUrl`, `CloudRadial-PublicKey` and `CloudRadial-PrivateKey`.

Pass a `request` (a question, a briefing, an audit or report, or a change to make) and optionally a `companyName` to focus on one company.

## Governance

Read first. Every create, update or delete is mutating and approval-gated: the agent states exactly what will change before doing it and never guesses an id. It runs dry by default. A Report Archive item belongs to one company and never holds another company's data.

## Dry run and going live

`cloudradial-ucp-reporting.agent.yml` ships with `dryRunDefault: true`. In dry run the agent does all its reads and describes each change it *would* make, but changes nothing. AutomationAI has **no dry-run switch** on the workflow's Agent node, the deployment, or the agent's page. The setting lives only in the agent file, so going live means re-importing it:

1. Open `cloudradial-ucp-reporting.agent.yml` and change `dryRunDefault: true` to `dryRunDefault: false`. Leave everything else the same.
2. On **Agents → Custom → Import**, upload the edited file. Import is keyed on the slug, so it replaces the installed agent in place.
3. To go back to preview, set it to `true` and re-import.

The change applies to every workflow that uses this agent. Portal Lookup is read-only either way. The others keep `autoApprove: false`, so even when the agent is live every change waits in the **Inbox** until you approve it. Keep the repo copy on `true`, so a fresh install always starts in preview.
