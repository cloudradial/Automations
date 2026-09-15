# Weekly Fleet Audit

A CloudRadial **AutomationAI workflow** that shows the "agent inside a workflow" pattern: it runs the [CloudRadial UCP Assistant](../cloudradial-ucp/) agent on a schedule to audit the fleet, then emails the result. `Start → Agent (Fleet Audit) → PowerShell (Email) → End`.

## Download & import

**Download the workflow:** [`weekly-fleet-audit.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/weekly-fleet-audit/weekly-fleet-audit.yml)

1. **First import the agent** it calls — [`cloudradial-ucp/`](../cloudradial-ucp/) (Agents → Custom → Import). The Agent node references it by the slug `cloudradial-ucp-assistant`.
2. In AutomationAI: **Workflows → Import**, upload `weekly-fleet-audit.yml`.
3. Add the runner **Key Vault secrets** below, set the recipient in the email node (`$recipient`), then **Publish** and **deploy** to your runner.
4. Attach a weekly **Routine** to run it unattended.

## What it does

1. **Agent node** runs the UCP Assistant toward the goal: for every company, count expired/unknown-warranty endpoints and flag companies with no account manager, then summarize (read-only).
2. **Email node** takes the agent's `answer` and sends it via Postmark.

## Required Runner Key Vault secrets

| Secret | For |
|---|---|
| `Postmark-ServerToken`, `Postmark-FromEmail`, `Postmark-ApiUrl` | Sending the email |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | Used by the CloudRadial extensions the agent calls |

## Note on the Agent node

The Agent node uses the documented config fields (`goal`, `allowedExtensions`, `model`, `timeoutSeconds`, `autoApprove`) and references the saved agent via `agentSlug`. If your portal expects a different key for the saved-agent reference, open the node after import and pick the agent from the picker (or clear the reference to run the goal inline with the two extensions listed). The most foolproof way to seed a correct Agent node is **Convert an AI Playground run into a workflow**, then add the email node from this file.
