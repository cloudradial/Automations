# CloudRadial v2 Compliance & Assets extension — 0.2.1

An update to the catalog **`cloudradial-v2-compliance`** extension (0.2.0) that makes its flexible-asset write tools usable.

## Pieces

| File | Type | Role |
|---|---|---|
| [`cloudradial-v2-compliance.extension.yml`](cloudradial-v2-compliance.extension.yml) | `automationsExtension` | Slug `cloudradial-v2-compliance`, version 0.2.1 — 22 tools, 2 skills. Built from the catalog 0.2.0 export (every tool checked byte for byte against Nick's Test before changing), so assessments, certificates and the read tools behave exactly as before. |

## What changed from 0.2.0

- **`cr_patch_flexible_asset` carries data.** 0.2.0 accepted only `id`, so the JSON Patch it sent was empty and nothing changed. 0.2.1 adds `name`, `resourceUrl` and `traitsJson` — send the asset's complete traits object as a JSON string (read it with `cr_get_flexible_asset`, change the keys, send it all back; keys you leave out are removed).
- **`cr_patch_flexible_asset_type`** adds `name`, `description`, `icon` and `showInMenu` (0.2.0 had the same id-only gap).
- **`cr_create_flexible_asset_type`** accepts `fields[]`, so a type and its columns are created in one call — the API already supported this (`CreateFlexibleAssetTypeRequest.fields`).
- **`cr_create_flexible_asset`** explains that `traits` is keyed by each field's `nameKey` (the field name in lowercase with hyphens: `Serial Number` → `serial-number`).
- The context adds a short *Flexible assets* section: trait keys, `traits` vs `traitsJson`, and matching on a stable trait before creating so re-runs don't duplicate.

## Install

1. **Extensions → Custom → Import** `cloudradial-v2-compliance.extension.yml`. A custom extension with the catalog's slug overrides the catalog copy in that tenant.
2. Secrets are unchanged: `CloudRadial-BaseUrl`, `CloudRadial-PublicKey`, `CloudRadial-PrivateKey`.
3. When the catalog ships a version with these fixes, delete the custom copy.

## Used by

- [ScalePad to CloudRadial Alignment](../scalepad-cloudradial-alignment/) — single flexible-asset corrections. (The [Sync workflow](../scalepad-cloudradial-sync/) calls the same REST routes directly, so it doesn't need the extension.)
- [KnowBe4 Training Sync](../knowbe4/) creates flexible assets with the same routes.

## Confirm in your tenant

- **Patching `traitsJson`.** `PATCH /v2/flexible-asset/{id}` takes JSON Patch operations against the stored entity, whose values live in `traitsJson`. The first time you use it, check the asset in the portal shows the new values. If the native route refuses it, the IT Glue-shaped `PATCH /compatibility/flexible_assets/{id}` takes `traits` as an object. The Sync workflow falls back to that route automatically.
