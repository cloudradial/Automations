# Keep Every Client's Hardware Refresh Plan Current

Every computer is checked against age, warranty and Windows 11 readiness, and each client's refresh plan in Planner stays sorted by priority.

**Formerly:** Endpoint LifeCycle Manager | **Marketplace ID:** AAI-00021 | **Type:** Workflow (an optional AI agent version is included)

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

**Start with** [`endpoint-lifecycle-manager.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager.yml) on **Workflows → Import**. It doesn't need an agent.

**Optional:** [`endpoint-lifecycle-manager-ai.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager-ai.yml) on **Workflows → Import**, after importing the **Endpoint LifeCycle Manager** agent, [`endpoint-lifecycle-manager.agent.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager.agent.yml), on **Agents → Custom → Import**. See How it works for when to use it.

| What | Link |
|---|---|
| View `endpoint-lifecycle-manager.yml` (start here) | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager.yml) |
| Download `endpoint-lifecycle-manager.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager.yml) |
| View `endpoint-lifecycle-manager.agent.yml` (agent) | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager.agent.yml) |
| Download `endpoint-lifecycle-manager.agent.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager.agent.yml) |
| View `endpoint-lifecycle-manager-ai.yml` (optional) | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager-ai.yml) |
| Download `endpoint-lifecycle-manager-ai.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager-ai.yml) |
| View `knowledge/endpoint-refresh-standards.md` (upload to Knowledge) | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/knowledge/endpoint-refresh-standards.md) |
| Download `knowledge/endpoint-refresh-standards.md` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/endpoint-lifecycle-manager/knowledge/endpoint-refresh-standards.md) |
| All files in this automation | [automationai/endpoint-lifecycle-manager](https://github.com/cloudradial/Automations/tree/main/automationai/endpoint-lifecycle-manager) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/endpoint-lifecycle-manager) |
| Source (for maintainers) | [src/](https://github.com/cloudradial/Automations/tree/main/automationai/endpoint-lifecycle-manager/src) |
| Marketplace listing | [AAI-00021](https://automations.cloudradial.com/marketplace/AAI-00021) |

## How it works

A CloudRadial **AutomationAI workflow** that reviews managed computers per company against industry refresh standards and maintains one **Planner card per refresh category**: Replace, Plan replacement, Upgrade in place, Retain, Needs data, Human review and Virtual machines. Each card carries a triage priority and lists that category's devices in plain language.

The workflow is **one PowerShell step with no AI**. The rules are fixed, so it doesn't need a model: it runs the same on any AI provider (OpenAI or Anthropic), has no turn limit, and covers every company in one run.

## Scope, CloudRadial portal only

It uses **only the CloudRadial portal's endpoints**, both **workstations and servers** (servers go to *Human review*, VMs to their own track). It needs **no RMM and no ScalePad** connection; every decision comes from native endpoint fields already in CloudRadial.

Use it when the CloudRadial portal is the source of truth. To bring ScalePad Lifecycle Manager data into CloudRadial first, run the [ScalePad to CloudRadial Sync](https://github.com/cloudradial/Automations/tree/main/automationai/scalepad-cloudradial-sync); this workflow then works from whatever the endpoints hold.

## Pieces

| File | Type | Role |
|---|---|---|
| [`endpoint-lifecycle-manager.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager.yml) | `automationsWorkflow` | **Use this one.** One PowerShell step, no AI: reads endpoints, sorts them, and writes the cards through the CloudRadial API. |
| [`endpoint-lifecycle-manager.agent.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager.agent.yml) | `automationsAgent` | Optional. The same rules as an AI agent (slug `endpoint-warranty-refresh-advisor-planner-cards`, v0.4.3), for asking questions in the AI Playground. |
| [`endpoint-lifecycle-manager-ai.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager-ai.yml) | `automationsWorkflow` | Optional. Runs the agent with a goal. It handles up to 3 companies per run and is subject to the runner's 25-turn limit, so prefer the PowerShell workflow for scheduled runs. |
| [`knowledge/endpoint-refresh-standards.md`](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/knowledge/endpoint-refresh-standards.md) | Knowledge | The refresh standards in plain language: age, warranty, OS support, RAM, category rules, priority tiers and roadmap quarters, with one table of adjustable values. See [Adjusting the standards](#adjusting-the-standards). |
| [`src/`](https://github.com/cloudradial/Automations/tree/main/automationai/endpoint-lifecycle-manager/src) | Source | `elm.ps1` (the PowerShell step), a mocked test harness, and the script that embeds it into the `.yml`. See [Changing the workflow](#changing-the-workflow). |

## Install / run

1. Add the CloudRadial API secrets to the runner Key Vault: `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey`.
2. On **Workflows → Import**, upload [`endpoint-lifecycle-manager.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/endpoint-lifecycle-manager.yml), then **Publish** and **deploy** it to your runner.
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

| `pricing` | none | Your approved models, parts, labour hours and rate, so cards carry an estimated cost. See [Pricing the cards](#pricing-the-cards). |

Example: `{"companyIds": "1,4", "mode": "plan"}`

## Pricing the cards

Every MSP has its own approved models and rates, so cards carry no prices until you add a `pricing` object to the run or Routine input. Without it, prices aren't touched, including any you've typed on cards yourself.

```json
{
  "mode": "plan",
  "pricing": {
    "currency": "USD",
    "hourlyRate": 150,
    "showPriceToClient": true,
    "models": {
      "Windows laptop":  { "model": "Dell Latitude 7450", "price": 1450, "cost": 1180 },
      "Windows desktop": { "model": "Dell OptiPlex 7020", "price": 1050, "cost": 850 },
      "Mac laptop":      { "model": "MacBook Air 13 M4", "price": 1299, "cost": 1150 },
      "Mac desktop":     { "model": "Mac mini M4", "price": 799, "cost": 700 }
    },
    "parts": {
      "RAM upgrade":        { "price": 120, "cost": 80 },
      "SSD upgrade":        { "price": 180, "cost": 110 },
      "Warranty extension": { "price": 250, "cost": 190 }
    },
    "labourHours": {
      "Upgrade in place": 2,
      "Retain": 1,
      "Human review": 2,
      "Virtual machines": 1,
      "RAM upgrade": 0.5,
      "SSD upgrade": 1
    }
  }
}
```

- **Replace and Plan replacement cards are priced** from the approved model for each computer's type:
  - The card's project price is the total.
  - `cost` (optional) fills the card's project cost. It's internal only and never shown to clients.
  - The internal note has the breakdown, for example "12 × Dell Latitude 7450 (Windows laptop) at $1,450 = $17,400".
- **How device type is decided,** in this order:
  - **Mac model name:** MacBook is a laptop; iMac, Mac mini, Mac Studio and Mac Pro are desktops.
  - **The endpoint's enclosure.**
  - **A battery:** a computer that reports one is a laptop.
  
  Add a `"Windows"` or `"Mac"` entry as a fallback for computers whose type isn't recorded. Computers with no matching model are listed as not priced and left out of the total.
- **Upgrade in place, Retain and Human review cards are priced from `parts` and `labourHours`.** Each computer gets the parts its data shows it needs:
  - **`RAM upgrade`:** memory is recorded and below 7.5 GB. An 8 GB computer reports about 7.8 GB because some memory is reserved, so it doesn't count. Unknown memory doesn't count either.
  - **`SSD upgrade`:** the endpoint says it has no SSD. Many agents don't collect this and report "no SSD" for everything, so it only counts in a company where at least one endpoint reports an SSD. Servers usually report "no SSD" even when they have one (RAID or virtual disks), so servers never get an SSD line.
  - **`Warranty extension`:** the warranty has expired or ends within 90 days.
  
  These are the only part names the workflow can match. Others are ignored with a warning.
- **Labour hours** are multiplied by `hourlyRate`. You can set two kinds:
  - **Per card**, for example `"Upgrade in place": 2`, is charged for every computer on that card.
  - **Per part**, for example `"RAM upgrade": 0.5`, is charged each time that part is fitted.
- **Virtual machines get labour only,** since there's no hardware to buy.
- **What the card shows:**
  - The parts and labour lines and a total go on the card's project price.
  - The parts `cost` goes in the project cost. Labour cost isn't included.
  - Software and licences are still quoted after a technician has checked each device.
  - A part that's needed but has no price is listed as not priced and left out of the total.
- **If nothing on the card can be priced,** the card says instead that labour is billed at your `hourlyRate` and that parts, software and licences will be quoted. Needs data cards get no cost line.
- **Clients see the price, never the cost.** By default the card's Show price option is on and the card body gets an Estimated cost section listing the models, prices and total. Set `showPriceToClient` to `false` to hide prices too. The cost only goes into the card's project cost field and the internal note. Either way, the cards stay hidden from clients until you publish them.
- **CloudRadial shows a card's price to clients only once the card is Completed.** When a category empties and the workflow marks its card Completed, it turns Show price off, so the client never sees a leftover price on a card that says nothing needs doing. The stored price and cost stay on the card for you. If computers come back, the card reopens and the next priced run sets the price and Show price again.
- **Cards you complete yourself.** Marking a card done in the portal also puts it in Completed. The workflow treats it the same as one it completed. If the category still has computers on the next run, the card is reopened. If the category is empty, the card is left exactly as you closed it, price included.
- **`currency` only sets the symbol:** `USD`, `CAD`, `AUD` and `NZD` show $, `GBP` shows £, and `EUR` shows €. CloudRadial stores only the number, so use your portal's currency.
- **The run output reports:**
  - `pricingApplied`
  - `estimatedTotal`, across the cards written
  - each card's `estimatedPrice` and `priceBreakdown` (which model, parts and labour each card was priced at, and what wasn't priced), so a `plan` run shows the pricing before anything is written
  - any `warnings`, for example a model or part with no valid price, an unrecognised part name, or labour hours with no `hourlyRate`

Reading the pricing from Knowledge, alongside the [refresh standards](knowledge/endpoint-refresh-standards.md), will come once workflows can read Knowledge.

## What it does

- Reads **native endpoint fields** (age from manufacture date, warranty expiry, OS, Windows 11 readiness, RAM, server and VM flags) and routes each computer through first-match decision tracks. Non-computers (no recognisable OS) are counted and skipped, and healthy computers aren't carded.
- **Skips deleted companies.** The endpoint list can still return endpoints that belong to a deleted company, and cards can't be written to a company that no longer exists. Those endpoints are left out and counted as `orphanedEndpoints`, and each deleted company shows as one `skipped` result.
- Keeps **one card per company and category**, matched by subject (`Endpoint Hardware Refresh - <Category>`) or the marker line in the body, so re-runs update in place. Other Planner cards are never touched.
- Writes a **client-readable card**: an opening sentence with the count, **What we recommend**, each device under its tier (Critical / High / Medium / Low) with model, serial, age, warranty date, OS and the action, then a **Summary** of tier counts.
- Adds an **internal note** to every card (not shown to clients): the company, how many computers were evaluated, and the tier counts on the card.
- **Closes cards whose category is empty.** When no computer lands in a category any more, its card is marked **Completed** with a one-line note. If devices return to that category later, the card reopens.
- **Critical stays visible.** Planner has no Critical priority, so a Critical card is stored as High, but its summary opens with "Critical:" and the body uses the Critical heading.
- If the portal rejects the internal note or the roadmap fields, the card is written without them and the run reports `optionalFieldsDropped`.

The run output lists every card with its action (`created`, `updated`, `reopened`, `completed`, `skipped`, `error`), priority, device count and a one-line note, plus the totals.

## Adjusting the standards

[`knowledge/endpoint-refresh-standards.md`](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/knowledge/endpoint-refresh-standards.md) holds every threshold and rule the workflow uses, so you can review or change your refresh standards in one place. Its **Standard values** table lists each setting, such as `replaceAgeYears` = 5 and `minimumRamGb` = 4.

1. Edit the values to your own standards. Keep the headings and setting names: the agent searches by them.
2. Upload the file to a Knowledge folder, for example **Lifecycle Standards**.

**What reads it today.** The file documents the defaults built into the PowerShell workflow, but the workflow doesn't read Knowledge yet. It will use the **Standard values** table once workflows can read Knowledge. Until then, to change how the workflow grades devices, change `src/elm.ps1` (see below) and keep this file in step. The agent version is still self-contained and doesn't search Knowledge either.

## Changing the workflow

The PowerShell step in `endpoint-lifecycle-manager.yml` is [`src/elm.ps1`](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/src/elm.ps1). Change that file, test it, then embed it.

From `src/`:

1. `npm install` (installs js-yaml).
2. `pwsh -File test.ps1 -InputJson '{"mode":"apply","companyIds":"1"}'` runs `elm.ps1` against a mocked Key Vault, CloudRadial API and set of cards, in strict mode as on the runner. Add `-RejectNotes` to check the fallback when the portal refuses the internal note.
3. `node build-elm.js` writes `elm.ps1` into `../endpoint-lifecycle-manager.yml`.

[Weekly Fleet Audit](https://github.com/cloudradial/Automations/tree/main/automationai/weekly-fleet-audit) copies the rules block (between `# ---- shared: begin` and `# ---- shared: end ----`) at build time, so after changing a rule, run its `build-audit.js` too. The agent (`endpoint-lifecycle-manager.agent.yml`) follows the same rules. If you change a rule in `elm.ps1`, change the agent's system prompt and [`knowledge/endpoint-refresh-standards.md`](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-lifecycle-manager/knowledge/endpoint-refresh-standards.md) to match.
