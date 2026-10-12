# Client Deliverable: Partner Guide

> Build the roadmap, budget, machine audit, and Microsoft licenses into one client-facing report.

Use this skill when a partner shows you a deliverable from ScalePad Lifecycle Manager X
(formerly Lifecycle Insights), myITprocess, or vCIOToolbox and asks whether CloudRadial
can do the same thing. It maps each section of that PDF onto a real CloudRadial surface,
builds the Planner items for you, and tells you plainly which parts do not reproduce.

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing in October 2026 (v2.6.3): **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Build a refresh roadmap
`Per-company` · `Writes to the portal` · **Tested**

```
Build a hardware refresh roadmap for Contoso from their endpoint data. Count
how many devices have usable warranty or age data first, then show me the
quarterly plan with prices and only create the Planner items when I confirm.
```

**What you get:** Priced Planner items placed on the timeline by start and end date.

**Good to know:** Timeline placement comes from the start and end dates, not the quarter field.

### Price the overdue backlog
`Per-company` · `Writes to the portal` · **Tested**

```
Which of Acme's devices are past end of life, and what would replacing them
cost at $1,200 each? Show me the list and only add it as an unscheduled
Planner item when I confirm.
```

**What you get:** An exception list turned into one priced, unscheduled Planner item.

### Set up a budget view
`Per-company` · `Writes to the portal` · **Tested**

```
Add Contoso's contract lines to the Planner as monthly items so the budget
renders by quarter. Show me the lines first and only create them when I
confirm.
```

**What you get:** Recurring items that total by quarter.

**Good to know:** CloudRadial has no budget chart. You get the numbers by quarter, not the graph.

### Recreate a ScalePad deliverable
`Per-company` · `Writes to the portal` · **Not yet tested**

```
Recreate the attached Lifecycle Manager PDF in Acme Corp. Map each section to
CloudRadial, tell me plainly what won't carry over, and only create the
Planner items when I confirm.
```

**What you get:** Planner items for the roadmap and budget, plus the Report Layout steps.

### Answer the scoring question
`Per-company` · `Read-only` · **Not yet tested**

```
What's our equivalent of the ScalePad DMI score, and how does our assessment
scoring compare to myITprocess?
```

**What you get:** An honest side-by-side, including what CloudRadial doesn't have.

## What actually reproduces

Three of the four books in a typical vCIO deliverable land natively:

- **Roadmap** → Planner items on the Timeline, priced and quarter-scheduled
- **Machine audit** → Endpoints modules, driven by `AgePolicy` and `WarrantyExpirationPolicy`
- **Microsoft licenses** → the Microsoft Licenses report module

All three tick into a single Report Layout, so one PDF carries the lot.

The fourth does not. There is **no budget module** in CloudRadial: no multi-year spend
model and no stacked Contracts/Initiatives/Hardware chart. The workaround is to carry
every budget row as a priced Planner line so Account Plan (list) renders a quarterly
table. You get the numbers, not the graph. Say so before the partner finds out live.

## Tips

- **Check the endpoint data before promising a roadmap.** Many portals have plenty of
  device rows but few with serials or warranty dates. The skill counts usable rows first
  and offers honest options rather than inventing asset detail.
- **There is no Goal object.** A parent goal that initiatives roll up to does not exist.
  Closest fits are a Planner Category for grouping, or an Assessment if the goal is a
  compliance outcome like Cyber Essentials.
- **There is no planner-item to asset link.** The linked-asset appendix gets rendered as
  an HTML table inside the item body. It looks right in the report and survives export.
- **Report Layouts are UI only.** `/api/partner/layout` is not on the public v2 API, so
  the layout itself is always a manual step. The skill hands over exact clicks.
- **Categories can be created via the API**, inline on a product create using
  `categoryData`. There is no standalone category endpoint, which makes this easy to miss.
- **Client visibility beats a shared link.** A client-visible layout lands under
  Account → Reports permanently, next to their tickets. Competitors deliver a per-QBR
  password link. That persistence is the strongest thing to demo.
- **Watch `companyId: 1`.** In most portals that is the partner's own record and doubles
  as the Planner template library. Confirm the target before writing 20 items into it.

## Related

- [endpoint-reporting](../endpoint-reporting/README.md): source the machine audit and warranty data.
- [assessment-compliance](../assessment-compliance/README.md): the scored assessment behind the maturity number.
- [service-management](../service-management/README.md): Planner items are `product` records; that skill covers the resource type generally.
- [portal-setup](../portal-setup/README.md): Session 4 (Reporting & QBR Prep) is where this normally comes up.
