# Never Let a Client Domain Expire

Any client domain that expires in the next 60 days shows up on that client's Planner, so your team renews it before websites and email go down.

## What happens

On the schedule you choose (for example, weekly), the automation looks at the domains you track for every client in your UCP portal.

For each client with a domain that has expired or will expire soon, it puts one card on that client's **Planner**. The card is written in plain sentences, for example: "As of today, Contoso has 1 domain(s) expiring within 60 days." It then lists each domain, its expiry date, how many days are left and the registrar, soonest first.

Clients with nothing expiring get no card. Each time it runs, the same card is refreshed with the latest dates, so you never end up with duplicates.

## What it protects

- **Read-only on your domains.** It never changes, renews or removes a domain. It only reports.
- **One card per client.** The card is updated in place on every run, never copied.
- **Nothing else in Planner is touched.** Other cards stay exactly as they are.
- **Report-only mode.** You can run it to see the results without writing any cards.

## Works with

Your UCP portal on its own. It reads the domains already recorded for each client, so no PSA is needed.

- **Missing expiry dates:** a domain with no expiry date recorded is skipped and gets no card.
- **Renewed domains:** the card isn't removed automatically. Once everything is renewed, the next run stops updating it, and your team can remove it.

## What you need

- A UCP portal with your clients' domains and their expiry dates
- A CloudRadial API key (from **Settings > API** in your portal), added to AutomationAI
- AutomationAI, with a runner

## Set it up

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/domain-expiration-report/v1.0.0).
2. In AutomationAI, go to **Workflows > Import** and upload it.
3. Add your CloudRadial API key to AutomationAI.
4. Click **Publish**, then **Deploy**.
5. Attach a **Routine** so it runs on a schedule, such as once a week. You can also run it any time with **Test**.

**Optional settings**, at the top of the workflow's step: change how many days ahead counts as "expiring soon" (60 by default), limit it to certain clients, or turn off writing cards so it only reports.

**Test it.** Click **Test**, then open a client with a domain due soon and check its **Planner** for the new card.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/domain-expiration-report#technical-details) cover the settings, the secrets the runner needs and how it works.

---

## Technical details

**Formerly:** Domain Expiration Report | **Marketplace ID:** AAI-00023 | **Type:** Workflow | **Version:** 1.0.0

## Files

Each version is published as a release, with `domain-expiration-report.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/domain-expiration-report/v1.0.0).

| What | Link |
|---|---|
| Download `domain-expiration-report.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/domain-expiration-report/v1.0.0) |
| View the current source | [`domain-expiration-report.yml`](https://github.com/cloudradial/Automations/blob/main/domain-expiration-report/domain-expiration-report.yml) |
| All files in this automation | [domain-expiration-report](https://github.com/cloudradial/Automations/tree/main/domain-expiration-report) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/domain-expiration-report) |
| Marketplace listing | [AAI-00023](https://automations.cloudradial.com/marketplace/AAI-00023) |

## How it works

A CloudRadial **AutomationAI workflow** that checks every company's managed domains and writes one plain-language **Planner card per company** listing what has expired or is expiring soon.

## Download & import

**Download the workflow:** [`domain-expiration-report.yml`](https://github.com/cloudradial/Automations/releases/tag/domain-expiration-report/v1.0.0)

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
