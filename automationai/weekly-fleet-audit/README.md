# Weekly Fleet Audit

A CloudRadial **AutomationAI workflow** that audits the fleet on a schedule and emails the result. It shows two agents inside one workflow: the [CloudRadial UCP Assistant](../cloudradial-ucp/) does the audit, and the shared [Deliver Result](../deliver-result/) agent sends it. `Start → Run inputs → Agent (Fleet Audit) → PowerShell (Build Email) → Agent (Send Audit) → End`.

## Set up

Do these in order. The workflow won't send anything until step 3 is done.

1. **Import the audit agent.** On **Agents → Custom → Import**, upload [`cloudradial-ucp/`](../cloudradial-ucp/)'s agent (slug `cloudradial-ucp-assistant`). Make sure `cloudradial-v2-companies` and `cloudradial-v2-endpoints` are installed and connected.
2. **Import the workflow.** On **Workflows → Import**, upload [`weekly-fleet-audit.yml`](weekly-fleet-audit.yml), then **Publish** and **deploy** it to your runner.
3. **Set up Deliver Result.** This is the step that sends the email:
   1. On **Agents → Custom → Import**, upload [`deliver-result.agent.yml`](../deliver-result/deliver-result.agent.yml) (slug `deliver-result`).
   2. Install and connect the **Postmark** extension, and add its secrets to the runner Key Vault: `Postmark-ServerToken`, `Postmark-FromEmail`, `Postmark-ApiUrl`.
   3. Set Deliver Result's `fromEmail` variable to a verified Postmark sender, or leave it empty to use `Postmark-FromEmail`.
   4. **Take it out of dry run.** Deliver Result ships with `dryRunDefault: true`, which describes the email and sends nothing. Follow [Dry run and going live](../deliver-result/README.md#dry-run-and-going-live) to re-import it live.
4. **Test it.** Run the workflow from **Test** with the recipients as the Trigger input (see [Inputs](#inputs)), and confirm the email arrives.
5. **Schedule it.** Attach a weekly **Routine**, with the same input.

## Inputs

| Field | Required | What it does |
|---|---|---|
| `toEmail` | Yes | Who gets the audit: one address, a comma list, or a JSON list. |

Example: `{"toEmail": "team@yourmsp.com, service@yourmsp.com"}`

The run stops at **Run inputs** with a clear message if `toEmail` is missing.

## What it does

1. **Run inputs** reads `toEmail` from the run input.
2. **Fleet Audit** (agent) runs the UCP Assistant toward a read-only goal: for every company, count expired or unknown-warranty endpoints and flag companies with no account manager, then summarize.
3. **Build Email** (PowerShell) wraps the agent's `answer` in a dated subject and an HTML body.
4. **Send Audit** (agent) runs Deliver Result with `channel: email`, which sends through Postmark. Its inputs are pre-bound: recipients from Run inputs, subject and body from Build Email. It has `autoApprove: true`, so a scheduled run doesn't wait in the Inbox.

To deliver somewhere else - a PSA ticket instead of email - change `channel` in Build Email to `psa`, add the company routing fields, and set Send Audit's `allowedExtensions` to your PSA extension.

## Required Runner Key Vault secrets

| Secret | For |
|---|---|
| `Postmark-ServerToken`, `Postmark-FromEmail`, `Postmark-ApiUrl` | The Postmark extension Deliver Result sends through |
| `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` | The CloudRadial extensions the audit agent calls |
