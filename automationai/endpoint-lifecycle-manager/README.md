# Keep Every Client's Hardware Refresh Plan Current

Every computer is checked against age, warranty and Windows 11 readiness, and each client's refresh plan in Planner stays sorted by priority.

**Formerly:** Endpoint LifeCycle Manager | **Marketplace ID:** Not yet listed | **Type:** Workflow (an optional AI agent version is included)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `endpoint-lifecycle-manager.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager.yml) |
| Download `endpoint-lifecycle-manager.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager.yml) |
| All files in this automation | [automationai/endpoint-lifecycle-manager](https://github.com/cloudradial/Automations/tree/main/automationai/endpoint-lifecycle-manager) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/endpoint-lifecycle-manager) |
| Source (for maintainers) | [src/](https://github.com/cloudradial/Automations/tree/main/automationai/endpoint-lifecycle-manager/src) |

## How it works

A CloudRadial **AutomationAI workflow** that reviews managed computers per company against industry refresh standards and maintains one **Planner card per refresh category**: Replace, Plan replacement, Upgrade in place, Retain, Needs data, Human review and Virtual machines. Each card carries a triage priority and lists that category's devices in plain language.

The workflow is **one PowerShell step with no AI**. The rules are fixed, so it doesn't need a model: it runs the same on any AI provider (OpenAI or Anthropic), has no turn limit, and covers every company in one run.

## Scope, CloudRadial portal only

It uses **only the CloudRadial portal's endpoints**, both **workstations and servers** (servers go to *Human review*, VMs to their own track). It needs **no RMM and no ScalePad** connection; every decision comes from native endpoint fields already in CloudRadial.

Use it when the CloudRadial portal is the source of truth. To bring ScalePad Lifecycle Manager data into CloudRadial first, run the [ScalePad to CloudRadial Sync](../scalepad-cloudradial-sync/); this workflow then works from whatever the endpoints hold.

## Pieces

| File | Type | Role |
|---|---|---|
| [`endpoint-lifecycle-manager.yml`](endpoint-lifecycle-manager.yml) | `automationsWorkflow` | **Use this one.** One PowerShell step, no AI: reads endpoints, sorts them, and writes the cards through the CloudRadial API. |
| [`endpoint-lifecycle-manager.agent.yml`](endpoint-lifecycle-manager.agent.yml) | `automationsAgent` | Optional. The same rules as an AI agent (slug `endpoint-warranty-refresh-advisor-planner-cards`, v0.4.2), for asking questions in the AI Playground. |
| [`endpoint-lifecycle-manager-ai.yml`](endpoint-lifecycle-manager-ai.yml) | `automationsWorkflow` | Optional. Runs the agent with a goal. It handles up to 3 companies per run and is subject to the runner's 25-turn limit, so prefer the PowerShell workflow for scheduled runs. |
| [`src/`](src/) | Source | `elm.ps1` (the PowerShell step), a mocked test harness, and the script that embeds it into the `.yml`. See [Changing the workflow](#changing-the-workflow). |

## Install / run

1. Add the CloudRadial API secrets to the runner Key Vault: `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey`.
2. On **Workflows → Import**, upload [`endpoint-lifecycle-manager.yml`](endpoint-lifecycle-manager.yml), then **Publish** and **deploy** it to your runner.
3. Run it from **Test**. Start with `{"mode": "plan"}` to see what it would change, then run it with no input to write the cards.
4. Attach a **Routine** (for example monthly) to keep the cards current.

## Run inputs

All optional. Send them as the run's Trigger input or the Routine input.

| Field | Default | What it does |
|---|---|---|
| `companyIds` | all companies | One company or a comma list (`1,4,7`). |
| `mode` | `apply` | `plan` lists what would change and writes nothing. |
| `plannerCategory` / `plannerProductCategoryId` | `Efficiency` / `7` | The Planner category for the cards. |
| `closeEmptyCards` | `true` | Close a card when its category has no computers left. |
| `scheduleOnRoadmap` | `false` | Put cards on the Planner roadmap by urgency (Critical and High, Human review and Needs data in the next quarter; Medium the one after; Low the third). |

Example: `{"companyIds": "1,4", "mode": "plan"}`

## What it does

- Reads **native endpoint fields** (age from manufacture date, warranty expiry, OS, Windows 11 readiness, RAM, server and VM flags) and routes each computer through first-match decision tracks. Non-computers (no recognisable OS) are counted and skipped, and healthy computers aren't carded.
- Keeps **one card per company and category**, matched by subject (`Endpoint Hardware Refresh - <Category>`) or the marker line in the body, so re-runs update in place. Other Planner cards are never touched.
- Writes a **client-readable card**: an opening sentence with the count, **What we recommend**, each device under its tier (Critical / High / Medium / Low) with model, serial, age, warranty date, OS and the action, then a **Summary** of tier counts.
- Adds an **internal note** to every card (not shown to clients): the company, how many computers were evaluated, and the tier counts on the card.
- **Closes cards whose category is empty.** When no computer lands in a category any more, its card is marked **Completed** with a one-line note. If devices return to that category later, the card reopens.
- **Critical stays visible.** Planner has no Critical priority, so a Critical card is stored as High, but its summary opens with "Critical:" and the body uses the Critical heading.
- If the portal rejects the internal note or the roadmap fields, the card is written without them and the run reports `optionalFieldsDropped`.

The run output lists every card with its action (`created`, `updated`, `reopened`, `completed`, `skipped`, `error`), priority, device count and a one-line note, plus the totals.

## Changing the workflow

The PowerShell step in `endpoint-lifecycle-manager.yml` is [`src/elm.ps1`](src/elm.ps1). Change that file, test it, then embed it.

From `src/`:

1. `npm install` (installs js-yaml).
2. `pwsh -File test.ps1 -InputJson '{"mode":"apply","companyIds":"1"}'` runs `elm.ps1` against a mocked Key Vault, CloudRadial API and set of cards, in strict mode as on the runner. Add `-RejectNotes` to check the fallback when the portal refuses the internal note.
3. `node build-elm.js` writes `elm.ps1` into `../endpoint-lifecycle-manager.yml`.

The agent (`endpoint-lifecycle-manager.agent.yml`) follows the same rules. If you change a rule in `elm.ps1`, change the agent's system prompt to match.
