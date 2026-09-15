# CloudRadial Endpoint Tokens

Read CloudRadial endpoints for each company and upsert a company token containing a comma-separated endpoint list.

## Quick Start

This is a CloudRadial **AutomationAI workflow** (folder: *Jeff's*). To use it:

- **Download:** Get [`cloudradial-endpoint-tokens.yml`](cloudradial-endpoint-tokens.yml) from this folder.
- **Import:** In the partner's AutomationAI portal, go to **Workflows → Import** and upload `cloudradial-endpoint-tokens.yml`. (Or recreate it with **AI Generate** using the prompt in [Use / Regenerate](#use--regenerate).)
- **Trigger:** Manual run / schedule (the Start node is not webhook-enabled). Optional `tokenName` and `approvedToWrite` values can be supplied on the Start node's output.
- **Status:** published (v0.0.1).

## How It Works

```
Trigger (manual)
   |
   v
Resolve Token Name -> List CloudRadial Companies -> Build Endpoint Token Payloads -> Check Write Approval
                                                                                          |
                                                          (approved) -> Write Company Tokens -> Summarize Processing Results -> End
                                                          (not approved) -> End Without Writing
   |
   v
External systems: CloudRadial API (v2 OData + token endpoint)
```

The workflow resolves a token name, pages through every CloudRadial company, and for each company pages through its endpoints and builds a sorted, de-duplicated, comma-separated list of endpoint names. A condition gate checks an approval flag; only when approved does it upsert a company token per company via `POST /v2/token`, then summarizes how many companies were processed.

## Steps

| # | Step | Type | What it does |
|---|------|------|--------------|
| 1 | Resolve Token Name | powershell | Reads `tokenName` from the Start output; trims it, defaulting to `endpoint_list` when blank. |
| 2 | List CloudRadial Companies | powershell | Calls CloudRadial `/v2/odata/Company` (Basic auth) and pages through all companies, returning id + name. |
| 3 | Build Endpoint Token Payloads | powershell | For each company, pages `/v2/odata/Endpoint` filtered by `companyId`, builds a sorted unique comma-separated endpoint name list, and assembles one token payload per company. |
| 4 | Check Write Approval | condition | Passes only if the Start output `approvedToWrite` equals one of `true`/`True`/`1`/`yes`/`Yes`; otherwise routes to End Without Writing. |
| 5 | Write Company Tokens | powershell | For each successful payload, upserts a company token via `POST /v2/token` (`type` = `1`), tracking success/error counts. |
| 6 | Summarize Processing Results | powershell | Aggregates write results into processed/error counts and a per-company summary. |

## Configuration

### Runner Key Vault secrets

| Secret | Used for |
|--------|----------|
| `CloudRadial-BaseUrl` | Base URL of the CloudRadial API. |
| `CloudRadial-PublicKey` | Public key for CloudRadial Basic auth. |
| `CloudRadial-PrivateKey` | Private key for CloudRadial Basic auth. |

### AI Extensions

- `cloudradial-v2-companies` (List CloudRadial Companies)
- `cloudradial-v2-endpoints` (Build Endpoint Token Payloads)
- `cloudradial-v2-tokens` (Write Company Tokens)

## Inputs

No request payload is required. Optional values are read from the Start node output:

| Field | Required | Description |
|-------|----------|-------------|
| `tokenName` | No | Name of the company token to upsert. Defaults to `endpoint_list`. |
| `approvedToWrite` | No | Gate for the write step. Must equal `true`/`True`/`1`/`yes`/`Yes` to actually write tokens; otherwise the run ends without writing. |

```json
{
  "tokenName": "endpoint_list",
  "approvedToWrite": "true"
}
```

## Outputs

Final node (Summarize Processing Results) returns:

- `status` — `success` or `error`.
- `message` — human-readable summary.
- `companyCount` — total companies retrieved.
- `processedCount` — companies whose token was written successfully.
- `errorCount` — number of failed writes.
- `processedCompanies` — array of `{ companyId, companyName, endpointCount, tokenName }`.
- `errors` — array of error result items.

(When approval is not granted, the run ends at **End Without Writing** without producing this summary.)

## Use / Regenerate

Paste this into **AI Generate** in the Workflow Designer to recreate a similar workflow:

> Create a manually-triggered CloudRadial workflow that lists every company via the CloudRadial v2 OData Company endpoint (Basic auth using CloudRadial-BaseUrl, CloudRadial-PublicKey, CloudRadial-PrivateKey from Key Vault, handling OData pagination). For each company, page through its endpoints via the v2 OData Endpoint endpoint filtered by companyId, and build a sorted, de-duplicated, comma-separated list of endpoint names. Use an optional input tokenName (default "endpoint_list"). Add a condition that only proceeds when an approvedToWrite flag is true/1/yes; when approved, upsert a company token per company via POST /v2/token with companyId, token name, the comma-separated value, and type "1". Finish with a step that summarizes how many companies were processed and which failed.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Error listing companies asking to add secrets | Add `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey` to the Runner Key Vault. |
| Run ends at "End Without Writing" | Set `approvedToWrite` to `true`/`1`/`yes` on the Start input; without it the workflow is read-only by design. |
| Some company token writes fail | Check the `errors` array in the summary; verify the company id is valid and the API keys have write permission. |
| Token shows wrong/empty list | Confirm the company has endpoints with non-empty names; the list is built from `name` fields only. |

## Notes

- Publish state: published, version 0.0.1.
- The workflow is read-only unless `approvedToWrite` is explicitly set to a truthy value — this is an intentional safety gate.
- Tokens are upserted with `type` = `1`.
