# Client Deliverable — Partner Guide

> Build the roadmap, budget, machine audit, and Microsoft licenses into one client-facing report.

Use this skill when a partner shows you a deliverable from ScalePad Lifecycle Manager X
(formerly Lifecycle Insights), myITprocess, or vCIOToolbox and asks whether CloudRadial
can do the same thing. It maps each section of that PDF onto a real CloudRadial surface,
builds the Planner items for you, and tells you plainly which parts do not reproduce.

## Try saying

| What you want | Say this | What you'll get |
|---|---|---|
| Recreate a competitor deliverable | `Recreate this Lifecycle Insights PDF in Acme Corp` | Planner items for every roadmap and budget line, plus the Report Layout steps |
| Build a refresh roadmap | `Build a hardware refresh roadmap for Contoso from their endpoint data` | Quarterly initiatives sourced from real warranty and EOL dates |
| Price the overdue backlog | `Which of Acme's devices are past EOL and what would replacing them cost?` | Exception list turned into a priced, unscheduled Planner item |
| Set up a budget view | `Add Contoso's contract lines to the Planner so the budget renders` | Recurring monthly items that total by quarter |
| Answer the DMI question | `What's our equivalent of the ScalePad DMI score?` | The honest mapping, including what CloudRadial does not have |
| Compare scoring models | `How does our assessment scoring compare to myITprocess?` | Both formulas side by side |
| Plan a QBR | `Set up a QBR deliverable for Acme Corp` | Full build plus the layout module list to tick |

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

- [endpoint-reporting](../endpoint-reporting/README.md) — source the machine audit and warranty data.
- [assessment-compliance](../assessment-compliance/README.md) — the scored assessment behind the maturity number.
- [service-management](../service-management/README.md) — Planner items are `product` records; that skill covers the resource type generally.
- [portal-setup](../portal-setup/README.md) — Session 4 (Reporting & QBR Prep) is where this normally comes up.
