# Lifecycle Manager extension (ScalePad) — 1.2.0

An update to the catalog **`lifecycle-manager`** extension (1.0.0) that fixes paging and adds the data a migration needs.

## Pieces

| File | Type | Role |
|---|---|---|
| [`lifecycle-manager.extension.yml`](lifecycle-manager.extension.yml) | `automationsExtension` | Slug `lifecycle-manager`, version 1.2.0 — 21 tools, 6 skills. Built from the catalog 1.0.0 export plus the 1.0.1 argument-name fix, so every existing tool and skill keeps its behavior. |

## What changed from 1.0.0

- **Underscore filter arguments (from 1.0.1).** AI tool-argument names can't contain `[`, `]` or `.`, so `filter[client.id]` is exposed as `filter_client_id` and sent to ScalePad as `filter[client.id]` — the same convention as the custom 1.0.1 in Nick's Test, applied to the new tools too. 1.0.1 has no paging, so it still returns only the first page of every list; 1.2.0 replaces it.

- **Every list tool pages automatically.** ScalePad returns at most 200 records per page plus a `next_cursor`. 1.0.0 had no paging descriptor, so each list returned only the first page and agents had to fetch the rest themselves — which is why migrations stalled. 1.2.0 adds `{"style":"cursor","itemsPath":"data","cursorPath":"next_cursor","cursorParam":"cursor"}` to all 12 list tools, so one call returns the complete set.
- **New tools:**
  - `scalepad_lm_list_software_assets`, `scalepad_lm_list_software_products`, `scalepad_lm_list_software_product_devices` — installed software per device.
  - `scalepad_list_assessments`, `scalepad_get_assessment`, `scalepad_list_assessment_criterion_labels` — assessments with the full question tree and answer labels.
  - `scalepad_list_deliverables` — QBR / vCIO deliverables.
- **Hardware type documented** on `scalepad_list_hardware_assets`: `WORKSTATION`, `SERVER`, `VIRTUAL`, `NETWORK`, `MOBILE`, `IMAGING` — filter with `filter_type` (e.g. `eq:SERVER`) to separate workstations from servers.
- **New skills:** *Inventory Installed Software*, *Review Assessments*.

## Install

1. **Extensions → Custom → Import** `lifecycle-manager.extension.yml`. Importing a custom extension with the catalog's slug overrides the catalog copy in that tenant, and replaces an existing custom copy such as 1.0.1.
2. Secrets are unchanged: `ScalePad-ApiUrl`, `ScalePad-ApiKey`.
3. When the catalog ships a version with paging (**AAI-38**, "ScalePad lifecycle-manager extension v1.1.0 — pagination, region, subscription gate", in progress), compare it with this file and delete the custom copy if it covers the same tools.

## Confirm in your tenant

- The runner accepts `"style":"cursor"` with `cursorPath: "next_cursor"` — 39 catalog tools use cursor paging, but ScalePad's cursor sits at the top level rather than nested. Run `scalepad_list_hardware_assets` for a client with more than 200 devices and check the count matches ScalePad.
- The Lifecycle Manager endpoints (`/lifecycle-manager/...`) need a paid Lifecycle Manager subscription (HTTP 402 without it).
