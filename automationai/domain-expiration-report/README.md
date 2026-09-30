# Never Let a Client Domain Expire

Domains expiring in the next 60 days show up as a Planner card for each client, so they're renewed before websites and email go down.

**Formerly:** Domain Expiration Report | **Marketplace ID:** AAI-00023 | **Type:** Workflow

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `domain-expiration-report.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/domain-expiration-report/domain-expiration-report.yml) |
| Download `domain-expiration-report.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/domain-expiration-report/domain-expiration-report.yml) |
| All files in this automation | [automationai/domain-expiration-report](https://github.com/cloudradial/Automations/tree/main/automationai/domain-expiration-report) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/domain-expiration-report) |
| Marketplace listing | [AAI-00023](https://automations.cloudradial.com/marketplace/AAI-00023) |

## How it works

A CloudRadial **AutomationAI workflow** that checks every company's managed domains and writes one plain-language **Planner card per company** listing what has expired or is expiring soon.

## Download & import

**Download the workflow:** [`domain-expiration-report.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/domain-expiration-report/domain-expiration-report.yml)

In AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), then **Publish** and **deploy** it to your runner. Run it on demand with **Test**, or attach a **Routine** to run it on a schedule (e.g. weekly). No trigger input is required, it covers all companies.

## Settings

Edit the CONFIG block at the top of the workflow's node:

| Setting | Default | What it does |
|---|---|---|
| `$WindowDays` | `60` | How many days ahead counts as "expiring soon". |
| `$CompanyIdFilter` | `@()` (all) | Set to e.g. `@(1,4,7)` to limit to specific companies. |
| `$WriteCards` | `$true` | Set `$false` to report only, writing no Planner cards. |

## Required Runner Key Vault secrets

`CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` (from CloudRadial **Settings → API**).
