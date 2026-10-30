# Let Users Pick Their Computer on Portal Forms

Keeps each client's list of computers up to date in your UCP portal, so your forms can ask "Which computer?" and tickets arrive with the right device named.

## What happens

The automation looks at every client company in CloudRadial and collects the names of that company's computers. It sorts them, removes duplicates and saves the list on the company in your portal.

Your portal forms and pages can then show that list, so a client picks their computer instead of guessing at its name. Your team gets tickets that already say which device the problem is on.

Run it whenever you like, or put it on a schedule so the list stays current as computers are added and retired.

## What it protects

- **Nothing changes until you say so.** Unless you turn on write approval, a run only reads and reports what it would save.
- **Each company sees only its own computers.** Every list is built and saved per company.
- **Read only, apart from the list.** It never changes the computers themselves, only the saved list.

## Works with

Any CloudRadial portal. It reads computers already in CloudRadial, so no PSA connection is needed.

## What you need

- A UCP portal with your clients' computers showing in CloudRadial
- AutomationAI, with your CloudRadial API keys (from **Settings > API** in CloudRadial) added to your runner

## Set it up

**Once, in AutomationAI:**

1. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/endpoint-names-token/v1.0.0).
2. Go to **Workflows > Import** and upload it.
3. Click **Publish**, then **Deploy**.
4. Run it with **Test**. Leave write approval off the first time to see what it would save, then run it again with write approval set to yes.
5. To keep lists current, attach a **Routine** so it runs on a schedule.

**In your UCP portal:** add the saved device list to any form or page where you want clients to pick their computer.

Optionally, you can change the name the list is saved under. By default it uses a standard name.

**Test it.** Open a form as a client user and check that their computers appear in the list.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/endpoint-names-token#technical-details) cover the settings, how the list is built and what your runner needs.

---

## Technical details

**Formerly:** Endpoint Names Token | **Marketplace ID:** AAI-00005 | **Type:** Workflow | **Version:** 1.0.0

## Files

Each version is published as a release, with `cloudradial-endpoint-tokens.yml` attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/endpoint-names-token/v1.0.0).

| What | Link |
|---|---|
| Download `cloudradial-endpoint-tokens.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/endpoint-names-token/v1.0.0) |
| View the current source | [`cloudradial-endpoint-tokens.yml`](https://github.com/cloudradial/Automations/blob/main/endpoint-names-token/cloudradial-endpoint-tokens.yml) |
| All files in this automation | [endpoint-names-token](https://github.com/cloudradial/Automations/tree/main/endpoint-names-token) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/endpoint-names-token) |
| Marketplace listing | [AAI-00005](https://automations.cloudradial.com/marketplace/AAI-00005) |

## How it works

A CloudRadial **AutomationAI workflow** that builds a sorted, de-duplicated, comma-separated list of each company's endpoint names and writes it to a company token, handy for portal content and forms.

## Download & import

**Download the workflow:** [`cloudradial-endpoint-tokens.yml`](https://github.com/cloudradial/Automations/releases/tag/endpoint-names-token/v1.0.0)

In AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), then **Publish** and **deploy** it to your runner. Run it on demand with **Test**, or attach a **Routine**.

## Settings

Optional values supplied on the Start node's output:

| Field | Default | What it does |
|---|---|---|
| `tokenName` | `endpoint_list` | Name of the company token to create/update. |
| `approvedToWrite` | *(empty)* | Safety gate, must be `true`/`1`/`yes` to actually write tokens; otherwise the run is read-only and ends without writing. |

## Required Runner Key Vault secrets

`CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` (from CloudRadial **Settings → API**).
