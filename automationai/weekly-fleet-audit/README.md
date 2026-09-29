# Weekly Fleet Audit

A CloudRadial **AutomationAI workflow** that audits the fleet on a schedule and emails the result. It shows two agents inside one workflow: the [CloudRadial UCP Assistant](../cloudradial-ucp/) does the audit, and the shared [Deliver Result](../deliver-result/) agent sends it. `Start → Agent (Fleet Audit) → PowerShell (Build Email) → Agent (Send Audit) → End`.

## Download & import

**Download the workflow:** [`weekly-fleet-audit.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/weekly-fleet-audit/weekly-fleet-audit.yml)

1. **Import the two agents it calls** on **Agents → Custom → Import**: [`cloudradial-ucp/`](../cloudradial-ucp/) (slug `cloudradial-ucp-assistant`) and [`deliver-result/`](../deliver-result/) (slug `deliver-result`).
2. Install and connect the **Postmark** extension (secrets `Postmark-ServerToken`, `Postmark-FromEmail`, `Postmark-ApiUrl`).
3. On **Workflows → Import**, upload `weekly-fleet-audit.yml`.
4. Set the recipients in the **Build Email** node (`$recipients`), then **Publish** and **deploy** to your runner.
5. Attach a weekly **Routine** to run it unattended.

## What it does

1. **Fleet Audit** (agent) runs the UCP Assistant toward a read-only goal: for every company, count expired or unknown-warranty endpoints and flag companies with no account manager, then summarize.
2. **Build Email** (PowerShell) wraps the agent's `answer` in a dated subject and an HTML body, with the recipient list.
3. **Send Audit** (agent) runs Deliver Result with `channel: email`, which sends through Postmark. Its inputs are pre-bound to Build Email, so there's nothing to map after import.

## Going live

Deliver Result ships in **dry run** (`dryRunDefault: true`): until you re-import it live, Send Audit describes the email it would send and sends nothing. Follow [Dry run and going live](../deliver-result/README.md#dry-run-and-going-live) in its README. Send Audit has `autoApprove: true` so a scheduled run doesn't wait in the Inbox.

To deliver somewhere else - a PSA ticket instead of email - change `channel` in Build Email to `psa`, add the company routing fields, and set Send Audit's `allowedExtensions` to your PSA extension.

## Required Runner Key Vault secrets

| Secret | For |
|---|---|
| `Postmark-ServerToken`, `Postmark-FromEmail`, `Postmark-ApiUrl` | The Postmark extension Deliver Result sends through |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | The CloudRadial extensions the audit agent calls |
