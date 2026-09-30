# Let Users Pick Their Computer on Portal Forms

Keeps each client's device list current in the portal, so forms offer a "which computer?" dropdown and tickets arrive with the right device.

**Formerly:** Endpoint Names Token | **Marketplace ID:** AAI-00005 | **Type:** Workflow

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

| What | Link |
|---|---|
| View `cloudradial-endpoint-tokens.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-names-token/cloudradial-endpoint-tokens.yml) |
| Download `cloudradial-endpoint-tokens.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/endpoint-names-token/cloudradial-endpoint-tokens.yml) |
| All files in this automation | [automationai/endpoint-names-token](https://github.com/cloudradial/Automations/tree/main/automationai/endpoint-names-token) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/endpoint-names-token) |
| Marketplace listing | [AAI-00005](https://automations.cloudradial.com/marketplace/AAI-00005) |

## How it works

A CloudRadial **AutomationAI workflow** that builds a sorted, de-duplicated, comma-separated list of each company's endpoint names and writes it to a company token, handy for portal content and forms.

## Download & import

**Download the workflow:** [`cloudradial-endpoint-tokens.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-names-token/cloudradial-endpoint-tokens.yml)

In AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), then **Publish** and **deploy** it to your runner. Run it on demand with **Test**, or attach a **Routine**.

## Settings

Optional values supplied on the Start node's output:

| Field | Default | What it does |
|---|---|---|
| `tokenName` | `endpoint_list` | Name of the company token to create/update. |
| `approvedToWrite` | *(empty)* | Safety gate, must be `true`/`1`/`yes` to actually write tokens; otherwise the run is read-only and ends without writing. |

## Required Runner Key Vault secrets

`CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` (from CloudRadial **Settings → API**).
