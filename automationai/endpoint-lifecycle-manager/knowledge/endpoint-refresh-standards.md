# Endpoint Refresh Standards

Owner: vCIO / Lifecycle · Effective: 2026-10-02 · Used by: Endpoint LifeCycle Manager

> **These are the default standards.** They match what the Endpoint LifeCycle Manager workflow does out of the box. Change the values to your own before you upload this file to Knowledge. Keep the headings and the setting names, because the agent searches by them. Each section restates the values it uses, so a section still makes sense when it's retrieved on its own.

## Standard values

This table is the single place to change a threshold. The sections below say which setting each rule uses.

| Setting | Default | What it controls |
|---|---|---|
| `replaceAgeYears` | 5 | A computer this many years old or older is **Replace**. |
| `planAgeYears` | 3 | A computer this many years old or older, but younger than `replaceAgeYears`, is **Plan replacement**. |
| `criticalAgeYears` | 7 | A computer this many years old or older gets the **Critical** tier. |
| `mediumAgeYears` | 4.5 | A computer this many years old or older gets at least the **Medium** tier. |
| `warrantyExpiringDays` | 90 | A warranty that ends within this many days counts as **expiring**. |
| `minimumRamGb` | 4 | Less RAM than this is below the minimum specification: **Replace**, Critical tier. |
| `recommendedRamGb` | 8 | Less RAM than this (but at least `minimumRamGb`) puts a healthy computer on the **Retain** card. |
| `vmMinimumRamGb` | 4 | A virtual machine with less RAM than this needs more memory (High tier). |
| `vmRecommendedRamGb` | 8 | A virtual machine with less RAM than this (but at least `vmMinimumRamGb`) needs its resources tuned. |
| `windowsSupported` | Windows 11 | Windows versions that still get security updates. |
| `windowsUnsupported` | Windows 10, 8, 7, Vista, XP | Windows versions past end of support. Windows 10 ended support on 14 Oct 2025. |
| `macosMinimumSupported` | 14 (Sonoma) | macOS this version or newer is supported. Older versions are unsupported. |
| `macosHardEndOfLife` | 12 (Monterey) | macOS this version or older is past hard end of life: Critical tier. |

## Which devices are reviewed

- **Computers only.** A device is reviewed when its operating system contains "Windows", "macOS" or "OS X". Anything else is counted as a non-computer and skipped. That includes network gear, printers, devices with a blank OS, and Linux.
- **Servers** (`isServer` is true) always go to **Human review**.
- **Virtual machines** (`isVirtual` is true and not a server) follow the virtual machine rules, not the age rules.
- **Deleted companies.** Endpoints whose company no longer exists are skipped, and no cards are written for them.
- **Healthy computers are not carded.** A computer appears on a card only when a rule below flags it.

## How age is measured

- Age is the time since `manufacturedDate`, in years to one decimal place.
- If there's no manufacture date, the BIOS date (`biosDate`) is used, then the CPU date (`cpuDate`). An age from either fallback is marked "estimated" on the card.
- If none of the three dates is set, the computer has **no age on file**.
- Age thresholds: `replaceAgeYears` = 5, `planAgeYears` = 3, `mediumAgeYears` = 4.5, `criticalAgeYears` = 7.

## Warranty status

Warranty comes from the endpoint's `expirationDate`:

| Status | Rule |
|---|---|
| Expired | The warranty date has passed. |
| Expiring | The warranty ends within `warrantyExpiringDays` (90) days. |
| Active | The warranty ends more than 90 days from now. |
| Unknown | No warranty date on file. |

## Operating system support

**Windows**

- Supported: `windowsSupported` (Windows 11).
- Unsupported: `windowsUnsupported` (Windows 10, 8, 7, Vista and XP).
- Anything else, such as Windows Server, is **unknown**. Servers are reviewed by a technician anyway.

**macOS**

| Version | Status |
|---|---|
| macOS 14 (Sonoma) and newer, the `macosMinimumSupported` value | Supported |
| macOS 13 (Ventura) | Unsupported |
| macOS 12 (Monterey) and older, the `macosHardEndOfLife` value | Unsupported and past hard end of life (Critical tier) |
| "macOS" with no version number | Unknown |

**Windows 11 readiness.** Windows 11 readiness (`windows11Readiness`) counts only when it says "Installed" or "Capable". "Unknown" or a blank value never means the computer can't run Windows 11.

## RAM

- RAM comes from the endpoint's `memory` field, in bytes, converted to GB.
- A value of 0 or a blank value means **unknown**, not low. A computer is never flagged because its RAM is unknown.
- Below `minimumRamGb` (4 GB) is under the minimum specification.
- Below `recommendedRamGb` (8 GB) is enough to put an otherwise healthy computer on the Retain card for a targeted upgrade.

## Category rules for physical computers

For a computer that isn't a server or a virtual machine, the **first** rule that matches decides its card:

1. **Replace** when any of these is true:
   - it's at least `replaceAgeYears` (5) old
   - its OS is unsupported and it isn't Windows 11-ready
   - it has less than `minimumRamGb` (4 GB) of RAM
2. **Upgrade in place:** its OS is unsupported, but Windows 11 readiness says "Installed" or "Capable". The hardware is fine, so upgrade the OS.
3. **Plan replacement:** it's at least `planAgeYears` (3) old but younger than 5.
4. **Retain:** it's younger than 3 years. It's carded only when its warranty is expired or expiring, or it has less than `recommendedRamGb` (8 GB) of RAM. Otherwise it's healthy and not carded.
5. **Needs data:** it has no age, no warranty date, and an unknown OS. The card asks for those details so it can be placed next time.
6. **Retain**, for anything left over, with the same carding condition as rule 4.

A Mac on macOS 13 or older is unsupported and can never be Windows 11-ready, so it lands on **Replace**.

## Servers

- Every server goes to the **Human review** card, whatever its age or OS. A technician decides the next step.
- A server's tier uses the same rules as a physical computer (see **Priority tiers**). An old server, or one with an expired warranty, is still marked urgent.

## Virtual machines

Age and warranty are ignored for virtual machines. The first matching rule decides the recommended action:

| Condition | Action | Tier |
|---|---|---|
| Guest OS unsupported (for example Windows 10) | Upgrade or rebuild the guest OS onto Windows 11 | High |
| RAM below `vmMinimumRamGb` (4 GB) | Increase the assigned memory | High |
| RAM below `vmRecommendedRamGb` (8 GB) | Review and tune the assigned resources | Low |
| Anything else, including unknown RAM | Healthy; not carded | — |

## Priority tiers

Each device on a card gets a tier. The **first** tier that matches applies, for physical computers and servers alike:

| Tier | When |
|---|---|
| Critical | Any of: at least `criticalAgeYears` (7) old; OS past hard end of life (unsupported Windows, or macOS at or below `macosHardEndOfLife`, version 12); RAM below `minimumRamGb` (4 GB). |
| High | Any of: at least `replaceAgeYears` (5) old; warranty expired; OS unsupported (for example macOS 13). |
| Medium | Any of: at least `mediumAgeYears` (4.5) old; warranty expiring within `warrantyExpiringDays` (90) days. |
| Low | Everything else. |

**Card priority.** A card takes the tier of its most urgent device. Planner has no Critical priority, so a Critical card is stored as High. Its summary starts with "Critical:", and the device list uses a Critical heading.

## Card categories and recommendations

| Card | Recommendation shown to the client |
|---|---|
| Replace | Replace these computers. They are too old, run an operating system that no longer gets security updates, or are below the minimum specification. |
| Plan replacement | Plan to replace these computers in the next budget cycle, and extend warranties or upgrade parts to bridge the gap. |
| Upgrade in place | Upgrade these computers to Windows 11 in place. The hardware is capable, so no replacement is needed. |
| Retain | Keep these computers, but extend the warranty or make a targeted upgrade where noted. |
| Needs data | Confirm the age, warranty and operating system for these computers so they can be placed in a refresh category next time. |
| Human review | Have a technician review these servers and decide the right next step for each one. |
| Virtual machines | Upgrade the guest operating system or adjust the assigned resources on these virtual machines. No hardware refresh is needed. |

Each card is titled `Endpoint Hardware Refresh - <card>`. There's one card per company for each category that has devices. When a category empties, its card is marked Completed. If devices come back, the card reopens.

## Roadmap placement

This applies only when the run sets `scheduleOnRoadmap` to true. Cards go on the Planner roadmap by their most urgent tier:

| Card tier | Quarter |
|---|---|
| Critical or High | Next quarter (1) |
| Medium | Quarter 2 |
| Low | Quarter 3 |
| Human review and Needs data cards, whatever their tier | Next quarter (1) |

## Adjusting these standards

- **Safe to change:** any value in **Standard values**, the client-facing recommendation wording, and the roadmap quarters.
- **Keep consistent:**
  - `planAgeYears` < `mediumAgeYears` < `replaceAgeYears` < `criticalAgeYears`
  - `minimumRamGb` ≤ `recommendedRamGb`
  - `macosHardEndOfLife` < `macosMinimumSupported`
- **When a new OS loses support,** for example a future macOS version, update the `windowsUnsupported` list or the macOS values, and the macOS table above.
- **Keep the headings and setting names.** The agent searches by them, and future workflow support for Knowledge will read the **Standard values** table by setting name.
