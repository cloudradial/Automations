---
name: endpoint-lifecycle-cards
description: >
  Review a company's CloudRadial endpoints and maintain one Planner card per hardware-refresh
  category (Replace, Plan replacement, Upgrade in place, Retain, Needs data, Human review,
  Virtual machines), each carrying a triage priority and listing that category's out-of-spec
  computers in plain language. Use when the user says "endpoint refresh cards", "hardware
  refresh plan", "lifecycle cards", "which computers need replacing", "build refresh Planner
  cards", "endpoint lifecycle review", "out-of-spec computers", or wants aging/out-of-warranty
  devices grouped into prioritized Planner cards. CloudRadial-only: reads endpoints, writes
  Planner cards, no external system.
metadata:
  version: "1.0.0"
---

# Endpoint Lifecycle Cards

Read a company's managed **computers** from CloudRadial and maintain a set of Planner cards
that group its out-of-spec devices by refresh **category**, each carrying a triage
**priority**. This is entirely CloudRadial → CloudRadial: `list_resources` on endpoints in,
`create_resource` / `update_resource` on Planner products out. No external system.

All decision rules are below and are self-contained. Use **native endpoint fields**; do not
invent values. If a company doesn't already hold ScalePad-sourced warranty/EOL data on its
endpoints, that's an upstream (AutomationAI) concern — this skill works with whatever the
endpoints carry, and files data-poor devices as **Needs data**.

## Before any tool call

Call `setup_status`. If `configured` is false, defer to the `setup` skill.

## Scope

Confirm the target company with `search_companies` → `companyId`. Watch for `companyId: 1`
(usually the partner's own record + template library). This skill writes cards for one
company at a time unless the user asks for several; group flagged endpoints by `companyId`.

## Read the endpoints

`list_resources` `endpoint`, filtered `companyId eq {id}`, selecting the native fields below.
Page with `skip` (100/page) until exhausted. Custom properties are usually empty; read
`endpoint_custom_property` only if present. Use present data at face value.

| Field | Use |
|---|---|
| `manufacturedDate` | age basis (fallback `biosDate`, then `cpuDate` — mark estimated) |
| `expirationDate` | warranty end |
| `os`, `osVersion` | operating system |
| `windows11Readiness` | positive-only Win11 signal ("Installed"/"Capable") |
| `isssd` | SSD (true) vs HDD (false) — the field name is lowercase `isssd` |
| `memory` | RAM in bytes (÷ 1073741824 for GB; 0 = unknown) |
| `isServer`, `isVirtual` | routing flags |
| `serialNumber`, `manufacturer`, `model`, `userName` | display / identity |
| `lastCheckIn` | display only — NOT a decision input |

## Exclusions

Exclude entirely (count, do not card): endpoints whose `os` is blank or unrecognized
(network devices, flexible assets, other non-computers). Proceed only with recognizable
Windows or macOS computers.

## Decision tracks (first match wins, after exclusions)

1. `isServer` true → **Human review** (physical or virtual servers).
2. `isVirtual` true and not a server → **Virtual machines** track, judged on OS and specs,
   **ignore age**: OS unsupported → Upgrade OS; RAM < 4 GB or storage below standard →
   Increase resources; RAM 4–8 GB or HDD-backed → Tune resources; otherwise → Retain.
3. Physical (not server, not virtual): age ≥ 5, **or** OS unsupported (and not Win11-ready),
   **or** RAM < 4 GB → **Replace**; OS unsupported and Win11-ready → **Upgrade in place**;
   age 3 to < 5 → **Plan replacement**; age < 3 → **Retain, extend or upgrade**; no age and
   warranty unknown and OS unknown → **Needs data**; otherwise → **Retain, extend or upgrade**.

Age comes from `manufacturedDate` (fallback `biosDate`/`cpuDate`, marked estimated).
Workstation refresh line: 5 years to replace, 3 years to plan.

## OS support

- **Windows:** Windows 11 = supported; Windows 10/8/7/XP/Vista = unsupported (Windows 10
  reached end of support 2025-10-14); server OS routes to Human review.
- **macOS:** supported = macOS 14 (Sonoma)+; unsupported = macOS 13 (Ventura) and older
  (incl. 12 Monterey, 11 Big Sur); unknown = "macOS" with no parseable version.
- Use `windows11Readiness` only as a **positive** signal; never infer "not capable" from "Unknown".

## Priority rubric (most-urgent signal wins)

- **Physical.** Critical = age ≥ 7, or OS past hard end-of-life and in use (Windows 10 now;
  macOS 12 or older), or RAM < 4 GB. High = age 5 to < 7, or warranty expired, or OS
  unsupported (macOS 13). Medium = age 4.5 to < 5, or warranty expiring within 90 days, or OS
  end-of-life within 180 days. Low = age 3 to < 4.5, or a single minor driver with runway.
- **Virtual machines.** unsupported OS → High; RAM < 4 GB → High; otherwise Medium/Low.

A card's priority is the most urgent device tier among the devices on that card.

## Card categories

One card per category that has ≥ 1 device, per company: **Replace**, **Plan replacement**,
**Upgrade in place**, **Retain**, **Needs data**, **Human review** (servers), **Virtual
machines** (the VM-track devices).

## Card body (human language)

Write the body in plain, full sentences a technician or account manager can read aloud. Do
NOT print raw driver tokens (`os_unsupported`, `age>=5y`) or telegraphic field dumps. Group
devices under their tier heading (Critical, High, Medium, Low). **Bold** the device name; use
friendly dates ("24 Jun 2025"); state the reason and recommended action in prose. End the body
with the reconciliation marker as a small italic reference line:
`Refresh Plan Card: company <companyId> / <Category>`.

Example device line: "**DESKTOP-EL2UQ6A** (Dell Precision 5570, serial 8MGBKN3) is about 4.2
years old and its warranty expired on 24 Jun 2025. It is running Windows 11, so the operating
system is fine. Recommended action: plan its replacement this cycle, and extend the warranty or
upgrade components as a bridge."

## Writing the cards (mechanics that must be exact)

All writes go through `create_resource` / `update_resource` on `resource_type: "product"`.

- **Reconcile before writing.** `list_resources` `product` filtered `companyId eq {id}`,
  selecting `productId,subject,body`. Find this skill's card for the category by subject
  `Endpoint Hardware Refresh - <Category>` or by the body marker
  `Refresh Plan Card: company <companyId> / <Category>`. If found → `update_resource`
  (`method: "PATCH"`, replace subject, body, summary, category, productCategoryId, priority).
  Otherwise → `create_resource`. Never more than one card per (company, category); never
  invent productIds; never overwrite generic/catalog cards like "Laptop Refresh".
- **Create fields:** `companyId`, `subject`, `category` (the plannerCategory name, default
  `Efficiency`), `productCategoryId` (default `7`), `datePublished`, `body`, `summary`,
  `isRequired` (false), `isShowPrice` (false), `isClientVisible` (false), `priority` (int).
  Subject = `Endpoint Hardware Refresh - <Category>`.
- **`datePublished` must be a quoted ISO 8601 string**, e.g. `"2026-08-14T00:00:00Z"` — never a
  bare date, number, or null.
- **`priority` integers:** Low = `-1`, Medium = `0`, High = `1`. There is **no** Critical code:
  use High (`1`) for Critical and write "Critical" in the body.
- **Do NOT** set `estimatedStartDate`, `estimatedEndDate`, `scheduledQuarter`, or `status`.
  Cards are created as Proposed and display as "Not scheduled" so the team schedules them
  later (AutomationAI's product tools reject date parameters; keep parity). `datePublished` is
  the only date field.

## Report honestly

Confirm the scope before writing, then report per company: evaluated, excluded (non-computer),
flagged, cards created / updated / skipped, and per-device errors. Return counts, not
adjectives. These cards are client-facing in the portal — a silently wrong recommendation
surfaces in the partner's next QBR.
