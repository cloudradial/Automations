# Domain Expiration Report

A CloudRadial **AutomationAI workflow** that checks every company's managed domains and writes one plain-language **Planner card per company** listing what has expired or is expiring soon.

## Download & import

**Download the workflow:** [`domain-expiration-report.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/domain-expiration-report/domain-expiration-report.yml)

In AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), then **Publish** and **deploy** it to your runner. Run it on demand with **Test**, or attach a **Routine** to run it on a schedule (e.g. weekly). No trigger input is required — it covers all companies.

## Settings

Edit the CONFIG block at the top of the workflow's node:

| Setting | Default | What it does |
|---|---|---|
| `$WindowDays` | `60` | How many days ahead counts as "expiring soon". |
| `$CompanyIdFilter` | `@()` (all) | Set to e.g. `@(1,4,7)` to limit to specific companies. |
| `$WriteCards` | `$true` | Set `$false` to report only, writing no Planner cards. |

## Required Runner Key Vault secrets

`CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` (from CloudRadial **Settings → API**).
