# Remove a Flexible Asset Type You No Longer Use

Deletes one flexible asset type you don't need anymore, such as the old "ScalePad Assets" list. The portal has no button to delete these, so this does it for you, and only when the type is empty.

## What happens

Flexible asset types show up as lists under **Infrastructure** in your portal. You tell the workflow which type to remove by its exact name (it uses "ScalePad Assets" if you don't name one). The CloudRadial UCP Assistant then:

1. Finds the type by its exact name. If there's no match, or more than one, it stops.
2. Checks every company for anything stored in that type. If any company still has something in it, it stops and tells you how much each company has.
3. Only if the type is empty everywhere, it deletes it, after you approve.
4. Confirms the type is gone.

The usual reason to run it is after the [ScalePad to CloudRadial Sync](https://github.com/cloudradial/Automations/tree/main/scalepad-cloudradial-sync). Older versions put all non-computer hardware into one "ScalePad Assets" list; the current version sorts it by kind of device. Once every company has been synced again, "ScalePad Assets" is empty and can go.

## What it protects

- **It only deletes an empty type.** If even one company still has data in it, nothing is deleted.
- **Only the type you named.** It never deletes any of the items, fields or other types.
- **You approve the delete.** The delete waits in the **Inbox** until you approve it, every time.

## Works with

CloudRadial only. No PSA is needed.

- **A type that still has fields:** CloudRadial may refuse to delete it. If so, the workflow reports the error and stops.

## What you need

- AutomationAI
- The **CloudRadial UCP Assistant** agent, from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp), in a recent version that includes the flexible asset tools
- The CloudRadial compliance extension, installed and connected in AutomationAI

## Set it up

**Once, in AutomationAI:**

1. If you don't have it yet, import the [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) on **Agents > Custom > Import**.
2. **Download** the [workflow file](https://github.com/cloudradial/Automations/releases/tag/remove-empty-flexible-asset-type/v1.0.0).
3. Go to **Workflows > Import** and upload it.
4. Click **Publish**, then **Deploy**.

**To remove a type:**

1. **Preview.** Run the workflow. To remove a type other than "ScalePad Assets", give its exact name. It reports what it found and whether it would delete the type. Nothing changes.
2. **Delete.** Take the assistant out of preview (the [assistant's page](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp#dry-run-and-going-live) shows how), run it again, and approve the delete in the **Inbox**.
**Test it.** Run the preview and check the result names the right type and shows zero items before you delete anything.

## Need more detail?

The [technical details](https://github.com/cloudradial/Automations/tree/main/remove-empty-flexible-asset-type#technical-details) cover how the workflow is built, its one setting, and every possible result.

---

## Technical details

**Formerly:** Remove Empty Flexible Asset Type | **Marketplace ID:** AAI-00041 | **Type:** Workflow | **Version:** 1.0.0

## Files

Each version is published as a release, with this automation's `.yml` file(s) attached. Download it from the [**release**](https://github.com/cloudradial/Automations/releases/tag/remove-empty-flexible-asset-type/v1.0.0).

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **CloudRadial UCP Assistant** agent, [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/cloudradial-ucp/cloudradial-ucp.agent.yml) from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`remove-empty-flexible-asset-type.yml`](https://github.com/cloudradial/Automations/blob/main/remove-empty-flexible-asset-type/remove-empty-flexible-asset-type.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `remove-empty-flexible-asset-type.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/remove-empty-flexible-asset-type/remove-empty-flexible-asset-type.yml) |
| Download `remove-empty-flexible-asset-type.yml` | [Release](https://github.com/cloudradial/Automations/releases/tag/remove-empty-flexible-asset-type/v1.0.0) |
| Needs the agent | [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) |
| All files in this automation | [remove-empty-flexible-asset-type](https://github.com/cloudradial/Automations/tree/main/remove-empty-flexible-asset-type) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/remove-empty-flexible-asset-type) |

## How it works

A CloudRadial **AutomationAI workflow** that removes one flexible asset type by name. Flexible asset types appear as lists under **Infrastructure**, and the portal can create them but not delete them.

It runs the [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) agent with a narrow goal:
1. Find the type by its exact name. If there's no match, or more than one, it stops.
2. Check **every company** for rows in the type. If any company still has a row, it stops and reports how many each company has.
3. Only if the type is empty, delete it. The delete waits in the **Inbox** until you approve it.
4. Confirm the type is gone.

It never deletes a row, a field, or any other type.

The usual reason to run it is after the [ScalePad to CloudRadial Sync](https://github.com/cloudradial/Automations/tree/main/scalepad-cloudradial-sync). Older Sync versions put all non-endpoint hardware into a single "ScalePad Assets" type. The current version moves those rows into a type per kind of device (Network Devices, Mobile Devices, Printers & Imaging and so on). Once every company has been synced, "ScalePad Assets" is empty and can go.

## Pieces

| File | Type | Role |
|---|---|---|
| [`remove-empty-flexible-asset-type.yml`](https://github.com/cloudradial/Automations/blob/main/remove-empty-flexible-asset-type/remove-empty-flexible-asset-type.yml) | `automationsWorkflow` | **Run inputs** (reads `typeName` and writes the request) → **Remove the type if empty** (an Agent node running `cloudradial-ucp-assistant`, limited to the `cloudradial-v2-compliance` tools, `autoApprove: false`). |

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp) **0.1.4 or later** on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`). 0.1.4 is the first version that includes the flexible asset tools.
2. Make sure the first-party extension `cloudradial-v2-compliance` is installed and connected.
3. On **Workflows → Import**, upload `remove-empty-flexible-asset-type.yml`, then **Publish** and **deploy** it to your runner.
4. **Preview:** with the agent in dry run (how it ships), run it with no input. The agent reports the type's id and row count and says it *would* delete it. Nothing changes.
5. **Delete:** take the agent out of dry run (see [Dry run and going live](https://github.com/cloudradial/Automations/tree/main/cloudradial-ucp#dry-run-and-going-live)) and run it again. Approve the delete in the **Inbox**. To go back to preview afterwards, set the agent back to dry run.

## Inputs

| Field | Default | What it does |
|---|---|---|
| `typeName` | `ScalePad Assets` | The exact name of the flexible asset type to remove. |

Example: `{"typeName": "ScalePad Assets"}`

## Results

The agent's `answer` gives the type name and id, how many rows it found, and the outcome:
- **Deleted** (after your approval).
- **Would be deleted**, in dry run.
- **Left in place**, either because it still has rows (with the count per company) or because more than one type has that name.
- **The delete failed**, with the error. For example, CloudRadial may refuse to delete a type that still has fields. The extension has no field delete, so the workflow reports the error and stops.

## Safety

- It deletes only a type that has **no rows in any company**. If one company still has data in it, nothing is deleted.
- The goal allows only the flexible asset tools, and only one delete, of the type you named.
- `autoApprove: false` means the delete never runs without your approval in the Inbox, even when the agent is live.
