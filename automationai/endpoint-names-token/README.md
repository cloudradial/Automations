# Endpoint Names Token

A CloudRadial **AutomationAI workflow** that builds a sorted, de-duplicated, comma-separated list of each company's endpoint names and writes it to a company token — handy for portal content and forms.

## Download & import

**Download the workflow:** [`cloudradial-endpoint-tokens.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/endpoint-names-token/cloudradial-endpoint-tokens.yml)

In AutomationAI: **Workflows → Import**, upload the `.yml`, add the [required runner secrets](#required-runner-key-vault-secrets), then **Publish** and **deploy** it to your runner. Run it on demand with **Test**, or attach a **Routine**.

## Settings

Optional values supplied on the Start node's output:

| Field | Default | What it does |
|---|---|---|
| `tokenName` | `endpoint_list` | Name of the company token to create/update. |
| `approvedToWrite` | *(empty)* | Safety gate — must be `true`/`1`/`yes` to actually write tokens; otherwise the run is read-only and ends without writing. |

## Required Runner Key Vault secrets

`CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` (from CloudRadial **Settings → API**).
