# Endpoint LifeCycle Manager (Refresh Advisor)

Evaluate managed endpoints against a hardware-lifecycle policy and create or update **one Planner card
per company per refresh category** (Replace, Plan replacement, Upgrade in place, Retain, Needs data,
Human review, Virtual machines), each carrying a triage priority.

Available in two forms that share the same logic:

- **PowerShell script** - `Invoke-EndpointRefreshAdvisor.ps1`, run from a workstation, RMM, or
  scheduled task.
- **AutomationAI agent** - `endpoint-lifecycle-manager.agent.yml`, imported as a scheduled agent in
  CloudRadial AutomationAI.

## Business Problem

Endpoint inventory tells you what you have, not what to do about it. Turning age and warranty data
into a client-ready refresh plan is manual, and a task per device buries everyone in noise. This
produces a small set of self-updating cards per company, grouped by recommendation and ranked by
urgency, so you can walk a client through their hardware roadmap in one place. Re-running updates the
same cards in place instead of piling up duplicates.

## What It Does

- Pulls managed endpoints from the CloudRadial v2 OData API, scoped to the companies you name (or all
  companies).
- Reads **native endpoint fields** as the source of truth (see Data Source), so it works without any
  endpoint custom properties.
- Evaluates each device with a deterministic, first-match-wins policy, routing **servers** to Human
  review, **virtual machines** to a VM track, and **physical computers** to an age/OS/warranty
  assessment.
- Groups flagged devices by company and category, assigns each a priority tier, and writes the devices
  in plain, client-readable language.
- Creates or updates **one card per (company, category)**.

## Data Source (native fields)

The evaluation reads these native endpoint fields - not custom properties:

| Signal | Field |
|--------|-------|
| Age | `manufacturedDate` (fallback `biosDate`, `cpuDate`) |
| Warranty / EOL | `expirationDate` |
| OS support | `os` (+ `windows11Readiness` as a positive Win11 signal) |
| Type / routing | `isServer`, `isVirtual` |
| Storage / RAM | `isssd`, `memory` (bytes) |
| Identity | `serialNumber`, `manufacturer`, `model` |

Missing fields degrade gracefully to "unknown", and unknown values never force a "fail" (for example,
unreported memory is treated as unknown, not as low). To populate age and warranty from an external
source such as ScalePad, run the ScalePad -> CloudRadial sync first; this advisor then reports on the
enriched fields.

### Decision policy (first match wins)

| Condition | Recommendation |
|-----------|----------------|
| `isServer` | Human review |
| `isVirtual` (not a server), OS unsupported | Virtual machines (upgrade guest OS) |
| Age >= 5 years, OR OS unsupported (and not Windows 11-ready), OR RAM < 4 GB | Replace |
| OS unsupported and Windows 11-ready | Upgrade in place |
| Age 3 to < 5 years | Plan replacement |
| Age < 3 years | Retain (carded only if warranty expired/expiring or RAM < 8 GB) |
| No age + unknown warranty + unknown OS | Needs data |

OS support: Windows 11 = supported; Windows 10/8/7/XP/Vista = unsupported (Windows 10 EOL
2025-10-14); macOS 14 (Sonoma) and newer = supported, 13 and older = unsupported, no version =
unknown. Healthy devices (Retain with no actionable driver) are skipped.

### Priority (most urgent wins)

| Tier | Trigger |
|------|---------|
| Critical | Age >= 7, OR OS past hard EOL and in use (Windows 10 now; macOS 12 or older), OR RAM < 4 GB |
| High | Age 5 to < 7, OR warranty expired, OR OS unsupported |
| Medium | Age 4.5 to < 5, OR warranty expiring within 90 days |
| Low | Otherwise |

A card's priority is the most urgent device on it. The CloudRadial priority field is three levels
(Low/Medium/High), so Critical caps to High on the field and is labelled "Critical" in the card body.

## Prerequisites

- PowerShell 5.1 or later (for the script), or CloudRadial AutomationAI (for the agent).
- CloudRadial API keys (Settings > API in your portal).

## Usage - PowerShell script

```powershell
# Dry run against the main company (companyId 1) - writes nothing
.\Invoke-EndpointRefreshAdvisor.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" -WhatIf

# Main company only (default)
.\Invoke-EndpointRefreshAdvisor.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE"

# Specific client companies
.\Invoke-EndpointRefreshAdvisor.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" -CompanyId 1,4,7

# Every company in the portal, verbose
.\Invoke-EndpointRefreshAdvisor.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" -AllCompanies -Verbose

# EU region
.\Invoke-EndpointRefreshAdvisor.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" `
    -BaseUrl "https://api.eu.cloudradial.com"
```

**Always run with `-WhatIf` first.** It evaluates and reconciles read-only, reporting exactly which
cards would be created or updated, without writing.

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-PublicKey` | *(required)* | API public key |
| `-PrivateKey` | *(required)* | API private key |
| `-BaseUrl` | `https://api.us.cloudradial.com` | API base URL (`https://api.eu.cloudradial.com` for EU) |
| `-CompanyId` | `@(1)` | One or more companyIds. Ignored with `-AllCompanies` |
| `-AllCompanies` | *(off)* | Process every company in the portal |
| `-SubjectPrefix` | `Endpoint Hardware Refresh - ` | Card subject prefix (category is appended); the reconcile key, keep it stable |
| `-Category` | `Efficiency` | Planner category |
| `-ProductCategoryId` | `7` | Planner product category id |
| `-ReplaceAgeYears` | `5` | Age at/above which a workstation is Replace |
| `-PlanAgeYears` | `3` | Age at/above which a workstation is Plan replacement |
| `-WhatIf` | | Preview without writing |
| `-Verbose` | | Log each API call |

## Usage - AutomationAI agent

Import `endpoint-lifecycle-manager.agent.yml` as a scheduled agent. It requires only the CloudRadial
v2 Endpoints and Services & Products extensions, reads its scope from agent variables (`companyIds`,
`plannerCategory`, `plannerProductCategoryId`), and produces the same cards. The agent always writes
(there is no preview mode); use the script's `-WhatIf` when you want a dry run.

## Expected Output (script)

```
Endpoint Refresh Advisor
Scope: companyId [1]
Evaluated 15 endpoints; flagged 13 across 1 companies; excluded 2; skipped healthy 2.
Cards created: 0  updated: 6  errors: 0
```

Followed by a per-(company, category) result table. Each card body lists its devices grouped by
priority tier; the Human review card notes that servers need a technician's judgment and are not
auto-scheduled.

## Troubleshooting

- **401/403**: API keys invalid, or belong to a different portal than you intend to write to.
- **"Company not found"**: a companyId in `-CompanyId` does not exist here; remove it or use
  `-AllCompanies`.
- **A device is missing**: it did not warrant attention (e.g. a healthy Retain), or it was excluded as
  a non-computer (blank/unrecognized OS, e.g. network gear).
- **Duplicate cards**: the reconcile key is `-SubjectPrefix` + category plus a body marker. If you
  change `-SubjectPrefix` between runs, older cards will not be recognized; keep it stable.

## Customization Tips

- **Schedule it**: run from your RMM or a scheduled task, or import the AutomationAI agent for a hosted
  schedule.
- **Tune thresholds**: `-ReplaceAgeYears` / `-PlanAgeYears` for the age bands; the OS and priority
  rules live in `Get-OsSupport`, `Get-Assessment`, and `Get-Tier` near the top of the script.

## Tested Environments

- PowerShell 5.1 and PowerShell 7
- Windows 11
- CloudRadial v2 API (US region)
