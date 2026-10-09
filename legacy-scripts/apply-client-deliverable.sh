#!/usr/bin/env bash
# Applies the client-deliverable skill to the cloudradial-ucp plugin and commits it.
# Run from anywhere:   bash apply-client-deliverable.sh
set -euo pipefail

REPO="$HOME/helpers"
BRANCH="feat/client-deliverable-skill"

cd "$REPO"

echo "==> Repo: $REPO"
echo "==> Current branch: $(git branch --show-current)"

if [ "$(git branch --show-current)" != "$BRANCH" ]; then
  echo "==> Switching to $BRANCH"
  git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH"
fi

BASE=main
git rev-parse --verify -q "$BASE" >/dev/null || BASE=origin/main

if git log --oneline "$BASE"..HEAD 2>/dev/null | grep -q client-deliverable; then
  echo "!! A client-deliverable commit already exists on this branch. Nothing to do."
  git log --oneline "$BASE"..HEAD
  exit 0
fi

echo "==> Writing patch"
cat > /tmp/client-deliverable.patch <<'PATCH_EOF_9f3a1c'
From 0b006cca4f0b109c13c3e1a5f7f7eb4ba3fa069b Mon Sep 17 00:00:00 2001
From: Claude <noreply@anthropic.com>
Date: Mon, 17 Aug 2026 17:06:00 +0000
Subject: [PATCH] feat(cloudradial-ucp): add client-deliverable skill

Adds a skill for building vCIO-style client deliverables (roadmap, goals,
budget, machine audit, Microsoft licenses) inside a CloudRadial portal, and
for answering how competitor maturity scores map onto CloudRadial scoring.

Motivation: partners migrating from ScalePad Lifecycle Manager X (formerly
Lifecycle Insights), myITprocess, or vCIOToolbox arrive with a PDF and ask
whether CloudRadial can produce the same artifact. Three of the four sections
reproduce natively; the skill is explicit about the one that does not.

What it covers:
- Maps each deliverable section to its CloudRadial surface, including the
  gaps (no Goal object, no budget module or chart, no planner-item to asset
  link) so they are stated up front rather than discovered mid-QBR
- An 8-step build sequence: resolve company, read existing state, assess
  endpoint data completeness before promising a roadmap, create categories,
  create roadmap initiatives, create budget lines, build the Report Layout,
  verify and total
- references/planner-item-schema.md: verified Product field map, MatrixStatus
  and productType enums, quarter-boundary dates, inline categoryData creation
- references/scoring-mapping.md: ScalePad DMI, myITprocess and vCIOToolbox
  formulas against CloudRadial assessment and policy scoring, with an explicit
  do-not-claim list

Field corrections verified against a live portal:
- Product create requires the `category` name string in addition to
  `productCategoryId`; omitting it returns a 400
- Planner categories can be created via the API using the nested `categoryData`
  object on a product create; there is no standalone category endpoint
- The endpoint entity returns `companyEndpointId`, `expirationDate` and `os`,
  not `endpointId`, `warrantyExpirationDate` and `operatingSystem` as described
  in the endpoint-reporting skill
- /api/partner/layout is not exposed on the public v2 API, so Report Layout
  creation is documented as a manual UI step

Bumps plugin version to 2.2.0 and adds vcio, qbr, roadmap and reporting keywords.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EETUVsEnMegcnMwTHaq9YJ
---
 .../.claude-plugin/plugin.json                |   8 +-
 .../skills/client-deliverable/README.md       |  62 ++++++
 .../skills/client-deliverable/SKILL.md        | 205 ++++++++++++++++++
 .../references/planner-item-schema.md         | 150 +++++++++++++
 .../references/scoring-mapping.md             | 133 ++++++++++++
 5 files changed, 556 insertions(+), 2 deletions(-)
 create mode 100644 cowork-plugin/cloudradial-ucp/skills/client-deliverable/README.md
 create mode 100644 cowork-plugin/cloudradial-ucp/skills/client-deliverable/SKILL.md
 create mode 100644 cowork-plugin/cloudradial-ucp/skills/client-deliverable/references/planner-item-schema.md
 create mode 100644 cowork-plugin/cloudradial-ucp/skills/client-deliverable/references/scoring-mapping.md

diff --git a/cowork-plugin/cloudradial-ucp/.claude-plugin/plugin.json b/cowork-plugin/cloudradial-ucp/.claude-plugin/plugin.json
index eb80589..e5149a0 100644
--- a/cowork-plugin/cloudradial-ucp/.claude-plugin/plugin.json
+++ b/cowork-plugin/cloudradial-ucp/.claude-plugin/plugin.json
@@ -1,7 +1,7 @@
 {
   "name": "cloudradial-ucp",
   "displayName": "CloudRadial UCP",
-  "version": "2.1.0",
+  "version": "2.2.0",
   "description": "☁️📡 CloudRadial UCP — the AI-powered service delivery & client success platform, right inside Claude. Look up companies, manage articles/assessments/courses, refresh endpoint warranty, and work with 30+ CloudRadial resource types in plain English. After installing, say \"Setup the CloudRadial Plugin\" for a quick tour and one-step credential setup.",
   "author": {
     "name": "Nick Westgate"
@@ -17,7 +17,11 @@
     "ai",
     "automation",
     "claude",
-    "mcp"
+    "mcp",
+    "vcio",
+    "qbr",
+    "roadmap",
+    "reporting"
   ],
   "repository": "https://github.com/cloudradial/helpers/tree/main/cowork-plugin/cloudradial-ucp"
 }
diff --git a/cowork-plugin/cloudradial-ucp/skills/client-deliverable/README.md b/cowork-plugin/cloudradial-ucp/skills/client-deliverable/README.md
new file mode 100644
index 0000000..376b47a
--- /dev/null
+++ b/cowork-plugin/cloudradial-ucp/skills/client-deliverable/README.md
@@ -0,0 +1,62 @@
+# Client Deliverable — Partner Guide
+
+> Build the roadmap, budget, machine audit, and Microsoft licenses into one client-facing report.
+
+Use this skill when a partner shows you a deliverable from ScalePad Lifecycle Manager X
+(formerly Lifecycle Insights), myITprocess, or vCIOToolbox and asks whether CloudRadial
+can do the same thing. It maps each section of that PDF onto a real CloudRadial surface,
+builds the Planner items for you, and tells you plainly which parts do not reproduce.
+
+## Try saying
+
+| What you want | Say this | What you'll get |
+|---|---|---|
+| Recreate a competitor deliverable | `Recreate this Lifecycle Insights PDF in Acme Corp` | Planner items for every roadmap and budget line, plus the Report Layout steps |
+| Build a refresh roadmap | `Build a hardware refresh roadmap for Contoso from their endpoint data` | Quarterly initiatives sourced from real warranty and EOL dates |
+| Price the overdue backlog | `Which of Acme's devices are past EOL and what would replacing them cost?` | Exception list turned into a priced, unscheduled Planner item |
+| Set up a budget view | `Add Contoso's contract lines to the Planner so the budget renders` | Recurring monthly items that total by quarter |
+| Answer the DMI question | `What's our equivalent of the ScalePad DMI score?` | The honest mapping, including what CloudRadial does not have |
+| Compare scoring models | `How does our assessment scoring compare to myITprocess?` | Both formulas side by side |
+| Plan a QBR | `Set up a QBR deliverable for Acme Corp` | Full build plus the layout module list to tick |
+
+## What actually reproduces
+
+Three of the four books in a typical vCIO deliverable land natively:
+
+- **Roadmap** → Planner items on the Timeline, priced and quarter-scheduled
+- **Machine audit** → Endpoints modules, driven by `AgePolicy` and `WarrantyExpirationPolicy`
+- **Microsoft licenses** → the Microsoft Licenses report module
+
+All three tick into a single Report Layout, so one PDF carries the lot.
+
+The fourth does not. There is **no budget module** in CloudRadial: no multi-year spend
+model and no stacked Contracts/Initiatives/Hardware chart. The workaround is to carry
+every budget row as a priced Planner line so Account Plan (list) renders a quarterly
+table. You get the numbers, not the graph. Say so before the partner finds out live.
+
+## Tips
+
+- **Check the endpoint data before promising a roadmap.** Many portals have plenty of
+  device rows but few with serials or warranty dates. The skill counts usable rows first
+  and offers honest options rather than inventing asset detail.
+- **There is no Goal object.** A parent goal that initiatives roll up to does not exist.
+  Closest fits are a Planner Category for grouping, or an Assessment if the goal is a
+  compliance outcome like Cyber Essentials.
+- **There is no planner-item to asset link.** The linked-asset appendix gets rendered as
+  an HTML table inside the item body. It looks right in the report and survives export.
+- **Report Layouts are UI only.** `/api/partner/layout` is not on the public v2 API, so
+  the layout itself is always a manual step. The skill hands over exact clicks.
+- **Categories can be created via the API**, inline on a product create using
+  `categoryData`. There is no standalone category endpoint, which makes this easy to miss.
+- **Client visibility beats a shared link.** A client-visible layout lands under
+  Account → Reports permanently, next to their tickets. Competitors deliver a per-QBR
+  password link. That persistence is the strongest thing to demo.
+- **Watch `companyId: 1`.** In most portals that is the partner's own record and doubles
+  as the Planner template library. Confirm the target before writing 20 items into it.
+
+## Related
+
+- [endpoint-reporting](../endpoint-reporting/README.md) — source the machine audit and warranty data.
+- [assessment-compliance](../assessment-compliance/README.md) — the scored assessment behind the maturity number.
+- [service-management](../service-management/README.md) — Planner items are `product` records; that skill covers the resource type generally.
+- [portal-setup](../portal-setup/README.md) — Session 4 (Reporting & QBR Prep) is where this normally comes up.
diff --git a/cowork-plugin/cloudradial-ucp/skills/client-deliverable/SKILL.md b/cowork-plugin/cloudradial-ucp/skills/client-deliverable/SKILL.md
new file mode 100644
index 0000000..9a32b7d
--- /dev/null
+++ b/cowork-plugin/cloudradial-ucp/skills/client-deliverable/SKILL.md
@@ -0,0 +1,205 @@
+---
+name: client-deliverable
+description: >
+  Build a vCIO-style client deliverable in a CloudRadial portal: IT roadmap, goals,
+  budget, machine audit, and Microsoft licenses in one place. Use when the user says
+  "build a client deliverable", "recreate this in CloudRadial", "IT roadmap for [company]",
+  "budget report", "quarterly business review", "QBR deck", "asset lifecycle plan",
+  "hardware refresh plan", "how do I do what Lifecycle Insights does", "ScalePad",
+  "Lifecycle Manager", "myITprocess", "vCIOToolbox", "DMI score", "maturity score",
+  "how does our scoring compare", or is migrating a partner off a third-party vCIO/QBR
+  tool onto CloudRadial. Also use when asked to turn endpoint EOL or warranty data into
+  a priced, quarter-scheduled plan.
+metadata:
+  version: "1.0.0"
+---
+
+# Client Deliverable Builder
+
+Assemble a vCIO-style deliverable (roadmap, goals, budget, machine audit, Microsoft
+licenses) inside a CloudRadial portal, using Planner items as the spine and one
+Report Layout as the delivery vehicle.
+
+Partners migrating from ScalePad Lifecycle Manager X (formerly Lifecycle Insights),
+myITprocess, or vCIOToolbox arrive with a PDF and ask "can CloudRadial do this."
+Three quarters of it ships today. Be precise about which quarter does not.
+
+## Before any tool call
+
+Call `setup_status`. If it returns `configured: false`, defer to the `setup` skill.
+
+## What maps natively, and what does not
+
+| Source deliverable section | CloudRadial home | Status |
+|---|---|---|
+| Roadmap / initiatives | Planner items + Timeline view | Ships today |
+| Linked asset appendix | Asset table rendered into the item `body` | Workaround, no native link |
+| Machine audit / EOL list | Endpoints + `AgePolicy` / `WarrantyExpirationPolicy` | Ships today |
+| Microsoft licenses | Microsoft Licenses report module | Ships today |
+| Goals (parent of initiatives) | Planner Category, or an Assessment | No Goal object exists |
+| Budget (multi-year, stacked chart) | Planner items priced by line | Partial, no chart |
+| Maturity index (DMI) | Assessment score, transparent | Different model, see below |
+
+State the gaps out loud. A partner who discovers the missing budget chart during
+their own QBR loses more trust than one who was told up front.
+
+## Build sequence
+
+### 1. Resolve the target company
+
+`search_companies` with the name fragment. Confirm the `companyId` before writing.
+
+Watch for `companyId: 1`. In most portals that is the **partner's own** company record,
+which also holds the Planner template library. If the user names their partner tenant
+("build this in my trial"), confirm whether they mean the partner record or a client
+company beneath it. Building a client deliverable on the partner record works, but it
+mixes deliverable items into the template library.
+
+### 2. Read what already exists
+
+Never write blind.
+
+- `list_resources` `product` filtered `companyId eq {id}` — existing Planner items and
+  the category names in use
+- `list_resources` `endpoint` filtered `companyId eq {id}` — the asset inventory
+- `count_resources` on both for scale
+
+Report what is already there and ask before touching it. Adding alongside is the safe
+default; deactivating (`isActive: false`) is reversible; deleting is not.
+
+### 3. Assess the endpoint data before promising a roadmap
+
+Endpoint records vary enormously in completeness. RMM-fed and agent-fed rows carry
+serials and warranty dates; Signal-only and discovered rows often carry nothing but a
+name and an OS string.
+
+Count how many endpoints have a usable `serialNumber` and `expirationDate` before
+designing cohorts. If most rows are empty, say so and offer the honest options:
+build a thin roadmap off real data, or mirror the source deliverable's structure with
+representative data for demo purposes. Do not silently invent asset detail.
+
+Fields that justify a refresh recommendation, all verified present on the live entity:
+
+| Field | Use |
+|---|---|
+| `expirationDate` | Warranty or EOL date. Past date is the strongest signal. |
+| `cpuDate`, `biosDate` | Derive platform age when no purchase date exists |
+| `os`, `osVersion` | Operating system end-of-support exposure |
+| `windows11Readiness` | `NotReady` is a hardware-bound refresh driver |
+| `lastCheckIn` | A device silent for a year is a data-hygiene finding |
+| `manufacturer`, `model`, `serialNumber` | The appendix table columns |
+| `isEncrypted`, `antiVirus`, `tpmVersion` | Security posture, feeds Policies |
+
+Note the field names differ from some older docs: the entity uses
+`companyEndpointId`, `expirationDate`, and `os` — not `endpointId`,
+`warrantyExpirationDate`, or `operatingSystem`.
+
+### 4. Create Planner Categories if the deliverable needs its own grouping
+
+Stock portals ship the IT Foundation set (Decision Making, Collaboration, Productivity,
+Compliance, Continuity, Security, Efficiency). A budget page reads better grouped as
+Hardware Refresh / Contracts / Initiatives.
+
+Categories have no standalone endpoint and no OData listing, but `create_resource`
+`product` accepts a `categoryData` object that creates one inline:
+
+```json
+{ "categoryData": { "name": "Hardware Refresh", "order": 10, "color": "#1F6FEB" } }
+```
+
+Omit `productCategoryId` to create; supply it to update. Create the category on the
+first item that needs it, then reuse the returned `productCategoryId` on the rest.
+
+### 5. Create the roadmap initiatives
+
+One Planner item per initiative. See
+`${CLAUDE_PLUGIN_ROOT}/skills/client-deliverable/references/planner-item-schema.md`
+for the full field map, enum values, and verified write quirks.
+
+The essentials:
+
+- `subject`, `body`, `summary`, `category` and `productCategoryId` are all required on create
+- `productType: 2` plus `estimatedStartDate` and `estimatedEndDate` puts the item on the Timeline
+- `productType: 0` means Not Scheduled — the right home for an overdue backlog that has
+  recognised budget but no agreed date
+- `projectUnits` x `projectUnitPrice` is one-time investment; `monthlyUnits` x
+  `monthlyUnitPrice` is recurring
+- `isClientVisible: true` and `isShowPrice: true` or the client sees nothing
+
+Render the linked-asset appendix as an HTML table inside `body`. There is no planner-item
+to endpoint foreign key, so the table is the only way to carry serials and reasons into
+the report. Always include a per-row **reason** column citing the actual field that
+triggered the recommendation ("Warranty expired 24 Jun 2025", not "old").
+
+### 6. Create the budget lines
+
+Recurring contracts and licence lines become Planner items with `monthlyUnitPrice` set,
+`status: "Completed"` and `currentlyInstalled: true` so they read as active spend rather
+than proposals.
+
+Where a contract bills annually, either divide to a monthly equivalent so quarterly
+totals behave, or place the full amount in the renewal quarter. State which convention
+was used in the item `body` so the number is defensible in the meeting.
+
+`monthlyUnitCost` and `projectUnitCost` are partner-internal and never shown to clients.
+Populate them if the partner wants margin visible in their own exports.
+
+### 7. Build the Report Layout — UI only
+
+`/api/partner/layout` is not exposed on the public v2 API. Confirm this rather than
+guessing, then hand the user exact clicks:
+
+> Settings → Report Layouts → new layout → tick modules → save.
+> Generate at Clients → open the company → Print/Generate report.
+
+The module catalog, verified in code:
+
+Cover page · Table of contents · Users · **Account Review** · **Account Plan** ·
+**Account Plan (list)** · Policy Review · Infrastructure Review · Endpoints (summary) ·
+Endpoints (detail) · Servers (summary) · Servers (detail) · Software · Domains ·
+Certificates · **Microsoft Licenses** · Product literature · Category literature ·
+Feedback · Notes
+
+Account Plan and Account Review pull from the Planner. Ticking those plus Endpoints
+(detail) and Microsoft Licenses puts roadmap, machine audit, and licensing in one PDF.
+
+Set "Is client visible" so the layout also appears under Account → Reports in the
+client's standing portal. That persistence is the competitive advantage over a
+per-QBR shared link, so call it out.
+
+### 8. Verify and total
+
+Re-read the created items with `list_resources` and compute the totals yourself rather
+than trusting the intended values. Report project total, monthly recurring, quarterly
+and annual figures.
+
+## Mapping a DMI or maturity score
+
+When asked how a competitor's headline number translates, read
+`${CLAUDE_PLUGIN_ROOT}/skills/client-deliverable/references/scoring-mapping.md`.
+
+The short version, and do not overstate it:
+
+- ScalePad's **Digital Maturity Index** is an opaque proprietary 300 to 850 scale,
+  higher is better. It is deliberately not a transparent percentage.
+- CloudRadial has **no single equivalent index**. It has two scores with opposite
+  polarity: assessment scores where higher is better, and policy risk scores where
+  higher is worse.
+- The honest analog is the **assessment score**: answers weight Compliant +2,
+  PartiallyCompliant +1, NA 0, Missing -1, NotCompliant -2. Every non-NA question adds
+  2 to `maxScore`; NA questions leave the denominator. `totalScore / maxScore` is the
+  posture number. Negative totals are possible and do occur in real data.
+- The differentiator to press is **explainability**. Every DMI point is a black box;
+  every assessment point traces to a named question with a priced remediation line.
+- Do **not** promise a blended posture number or a 0 to 100 policy score. Neither ships.
+
+## Report honestly
+
+Close every build with what was created, what was skipped, and what could not be verified.
+If a claim could not be confirmed against the API or the portal, say which check was run
+and that it came back inconclusive. A guessed detail in a client-facing deliverable
+surfaces in front of the partner's customer.
+
+## API Reference
+
+Full field and schema detail: `${CLAUDE_PLUGIN_ROOT}/references/api-reference.md`.
diff --git a/cowork-plugin/cloudradial-ucp/skills/client-deliverable/references/planner-item-schema.md b/cowork-plugin/cloudradial-ucp/skills/client-deliverable/references/planner-item-schema.md
new file mode 100644
index 0000000..e0c9f96
--- /dev/null
+++ b/cowork-plugin/cloudradial-ucp/skills/client-deliverable/references/planner-item-schema.md
@@ -0,0 +1,150 @@
+# Planner Item (Product) Schema
+
+A Planner item is a `Product` record. Everything below was verified against a live
+portal via `create_resource` / `list_resources` on `resource_type: "product"`.
+
+## Required on create
+
+`create_resource` rejects the call without these. `category` is the trap — it is the
+category **name string**, and it is required *in addition to* the numeric
+`productCategoryId`. Omitting it returns:
+
+```
+{"errors":{"category":["The Category field is required."]}}
+```
+
+| Field | Type | Note |
+|---|---|---|
+| `companyId` | int | Target company |
+| `productCategoryId` | int | FK to `ProductCategory`, enforced |
+| `category` | string | The category name, e.g. `"Efficiency"` |
+| `subject` | string | Item title |
+| `body` | string | HTML. Where the asset appendix goes |
+| `summary` | string | One line, shown on the card |
+
+## Scheduling
+
+`productType` sets the scheduling mode:
+
+| Value | Mode | Behaviour |
+|---|---|---|
+| `0` | Not Scheduled | No dates. Off the Timeline. Correct for an overdue backlog |
+| `1` | Quarter Offset | Legacy. Uses `scheduledQuarter`. Do not set on new items |
+| `2` | Project Dates | Requires `estimatedStartDate`. Puts a bar on the Timeline |
+
+For quarter alignment with `productType: 2`, set the dates to quarter bounds:
+
+| Quarter | Start | End |
+|---|---|---|
+| Q1 | `YYYY-01-01T12:00:00Z` | `YYYY-03-31T12:00:00Z` |
+| Q2 | `YYYY-04-01T12:00:00Z` | `YYYY-06-30T12:00:00Z` |
+| Q3 | `YYYY-07-01T12:00:00Z` | `YYYY-09-30T12:00:00Z` |
+| Q4 | `YYYY-10-01T12:00:00Z` | `YYYY-12-31T12:00:00Z` |
+
+Use midday UTC to avoid a timezone shift landing the item in the neighbouring quarter.
+
+## Status
+
+Send the string on write. The API returns the `MatrixStatus` int on read.
+
+| String | Int | Use |
+|---|---|---|
+| `Proposed` | 0 | Recommended, not yet agreed |
+| `Draft` | 1 | Not ready to show |
+| `Client_Approved` | 10 | Approved, not started |
+| `In_Planning` | 20 | Scoped, scheduled |
+| `In_Progress` | 30 | Under way |
+| `Completed` | 40 | Done. Also the right status for an active contract line |
+| `Client_Declined` | 50 | Declined |
+
+`priority` takes `"Low"` / `"Medium"` / `"High"`, returned as `-1` / `0` / `1`.
+
+## Pricing
+
+| Field | Meaning |
+|---|---|
+| `projectUnits` x `projectUnitPrice` | One-time investment |
+| `monthlyUnits` x `monthlyUnitPrice` | Recurring monthly |
+| `projectUnitCost`, `monthlyUnitCost` | Partner-internal cost. Never shown to clients |
+
+Extension is derived, not stored. `isShowPrice: true` is required or the client sees
+the item with no number. `isShowEstimated: true` exposes hours, duration and staff.
+
+## Visibility
+
+| Field | Effect |
+|---|---|
+| `isClientVisible` | `false` hides the item from the client entirely |
+| `isShowPrice` | Controls price display independently of visibility |
+| `currentlyInstalled` | `true` marks it as existing service rather than a proposal |
+| `isActive` | `false` deactivates without deleting. The reversible cleanup |
+
+## Creating a category inline
+
+No standalone category endpoint and no OData listing exist. `ProductRequest` accepts a
+nested `categoryData` object:
+
+```json
+{
+  "companyId": 42,
+  "subject": "Workstation Replacement Q1 2027",
+  "category": "Hardware Refresh",
+  "body": "<p>...</p>",
+  "summary": "...",
+  "categoryData": {
+    "name": "Hardware Refresh",
+    "order": 10,
+    "color": "#1F6FEB",
+    "body": "Endpoint lifecycle and refresh work"
+  }
+}
+```
+
+Omit `productCategoryId` inside `categoryData` to create; supply it to update an
+existing one. Capture the `productCategoryId` from the response and reuse it on
+subsequent items so you create the category once, not once per item.
+
+## Cross-entity links present on the record
+
+| Field | Links to |
+|---|---|
+| `psaOpportunityKey` | A PSA quote |
+| `psaProjectKey` | A PSA project |
+| `psaTicketKey` | A PSA ticket |
+| `psaSalesOrderKey` | A PSA sales order |
+| `assessmentKey`, `assessmentQuestionKey` | The assessment finding that produced the item |
+
+There is **no endpoint or asset link**. A planner item cannot reference a device.
+Render the asset table into `body`.
+
+## Asset appendix table
+
+```html
+<h4>Linked assets (3)</h4>
+<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;width:100%">
+  <thead>
+    <tr><th align="left">Name</th><th align="left">Model</th>
+        <th align="left">Serial Number</th><th align="left">Reason</th></tr>
+  </thead>
+  <tbody>
+    <tr><td>DESKTOP-EL2UQ6A</td><td>Dell Precision 5570</td><td>8MGBKN3</td>
+        <td>Warranty expired 24 Jun 2025</td></tr>
+  </tbody>
+</table>
+```
+
+Populate the Reason column from the field that actually triggered the recommendation.
+Where the endpoint carries no serial, write `Not reported` rather than leaving the cell
+blank or inventing a value.
+
+## Fields that exist but are undocumented
+
+`scoring` (int) is present on every product row and backs a partner-side Planner
+"Scoring" view. Its computation is not documented anywhere available. Do not build on
+it or explain it to a partner without confirming behaviour first.
+
+## Field-name corrections
+
+The endpoint entity in some older docs is described with `endpointId`,
+`warrantyExpirationDate` and `operatingSystem`. The live entity returns
+`companyEndpointId`, `expirationDate` and `os`. Filter and select with the live names.
diff --git a/cowork-plugin/cloudradial-ucp/skills/client-deliverable/references/scoring-mapping.md b/cowork-plugin/cloudradial-ucp/skills/client-deliverable/references/scoring-mapping.md
new file mode 100644
index 0000000..65eeeb4
--- /dev/null
+++ b/cowork-plugin/cloudradial-ucp/skills/client-deliverable/references/scoring-mapping.md
@@ -0,0 +1,133 @@
+# Mapping Competitor Maturity Scores to CloudRadial
+
+How to answer "what's our DMI?" without inventing a number.
+
+## The competitor scores
+
+### ScalePad Lifecycle Manager X — Digital Maturity Index
+
+An opaque proprietary **300 to 850 "credit rating"** scale, higher is better,
+deliberately not a transparent percentage. Scorecards add partner-defined health-scored
+items, some auto-created from Lifecycle Manager data. ScalePad also pipes Microsoft
+Secure Score straight into QBR deliverables.
+
+The published band thresholds are not available. **Do not invent a
+percentage-to-DMI conversion table.** If a partner wants a numeric equivalence, tell
+them the mapping cannot be derived from published information.
+
+### myITprocess
+
+Weighted attainment: `report % = Σ(priority weight × answer %) / Σ(priority weight)`.
+Priority High/Med/Low maps to 5/3/1. Answer Aligned/Marginal/Highly Vulnerable maps to
+100/50/0. Human-answered standards, no auto-telemetry. The closest prior art to
+CloudRadial's direction.
+
+### vCIOToolbox
+
+Three MSP-selectable models per template: AVGAVG (best-practice weighted average),
+STANDARD-BPVR (each topic starts at 100, subtract a weight per negative answer, average
+topics), AVGALLPOINTS (risk-only weighted average).
+
+### Microsoft Secure Score (adjacent benchmark)
+
+`points achieved / max achievable`, per-action risk-weighted, with partial credit and
+peer benchmarking.
+
+## What CloudRadial actually has
+
+There is **no single maturity index**. There are two scores, running in opposite
+directions, and the roll-up that would unify them is not built.
+
+### Assessment score — the honest analog
+
+Answers map to fixed weights via `AssessmentValueType`:
+
+| Answer | Weight |
+|---|---|
+| Compliant | +2 |
+| PartiallyCompliant | +1 |
+| NA | 0 |
+| Missing | −1 |
+| NotCompliant | −2 |
+
+Every non-NA question adds 2 to `maxScore`. NA questions leave the denominator
+entirely. `totalScore / maxScore` produces the "X out of Y" posture number.
+
+Read these off the assessment record: `compliantScore`, `partialScore`, `totalScore`,
+`maxScore`.
+
+**Negative totals are real.** A live portal returns rows like
+`totalScore: -426, maxScore: 852`. Whether the UI floors the display at zero is not
+documented. Check before explaining a negative number to a partner.
+
+No per-question weighting, no category weighting, and no band thresholds exist. Band
+thresholds are an open design item, not a shipped feature.
+
+### Assessment runs give the trend
+
+`POST /api/assessments/run` clones the assessment and its answers into a frozen
+`Assessment_Run` row, stamps `dateConducted`, and computes `dateNextDue` from
+`scheduleInterval`.
+
+Critical caveat: **nothing enforces the cadence.** No background job generates the next
+run or notifies anyone. The interval field is labelled "Recommended Interval" in the UI,
+which is honest about what it is. A red overdue date is the entire mechanism. Tell
+partners to calendar it.
+
+Runs compare across the last four and export to XLSX. That comparison is the
+quarter-over-quarter trend a DMI is actually used for.
+
+### Policy risk score — opposite polarity
+
+Computed on read, not written by the scan:
+
+```
+fails = TotalItems - ComplianceCount - Allowance
+
+RiskScore = ScoringMethod == Any
+    ? (fails <= 0 ? 0 : ScoreOccurence)   // flat score if anything fails
+    : (fails * ScoreOccurence)            // score × number of failing items
+```
+
+Summed across a company's policies. **Higher is worse**, the inverse of the assessment
+score. Banding today is a digit-length heuristic on the string form of the number:
+3+ digits red, 2 digits orange, otherwise green.
+
+A proper 0 to 100 posture roll-up does **not** exist. It is net-new work.
+
+## The polarity problem
+
+Assessments: higher is better. Policies: higher is worse. A blended client-facing
+"Compliance score" combining both is a draft design decision, **not shipped**.
+
+Never present a single blended posture number as available today.
+
+## What to say to a partner
+
+Lead with the assessment percentage, run quarterly, and show the trend across runs.
+
+The differentiator is **explainability**, not the number itself. Every DMI point is a
+black box. Every CloudRadial assessment point traces to a named question, and where the
+partner filled in the question's remediation profile (`riskCost`, `riskImpact`,
+`likelihood`, monthly and project unit pricing, optional catalog `productId`), it also
+traces to a priced line of work.
+
+That is the loop worth demonstrating:
+
+```
+Assessment question answered NotCompliant
+  → Estimate of Work report prices the remediation
+  → Add to Planner creates the plan item
+  → Account Plan module renders it in the client deliverable
+```
+
+Score to recommendation to budget to report, with every hop visible. A DMI cannot show
+its working.
+
+## Do not claim
+
+- A 300–850 equivalent, or any conversion between the two scales
+- A blended policies-plus-assessments posture number
+- A 0 to 100 policy score
+- Enforced assessment recurrence
+- Defined band thresholds or severity labels for either score
-- 
2.43.0

PATCH_EOF_9f3a1c

echo "==> Checking patch applies cleanly"
git apply --check /tmp/client-deliverable.patch

echo "==> Applying"
git am /tmp/client-deliverable.patch

echo
echo "==> Done. Commit created:"
git log --oneline -1
git show --stat --oneline HEAD | tail -8

echo
echo "==> Commits ahead of $BASE:"
git log --oneline "$BASE"..HEAD

echo
echo "==> Next, run:"
echo "    git push -u origin $BRANCH --force-with-lease"
echo
echo "==> Then open the PR here (no gh needed):"
echo "    https://github.com/cloudradial/helpers/compare/main...$BRANCH?expand=1"
