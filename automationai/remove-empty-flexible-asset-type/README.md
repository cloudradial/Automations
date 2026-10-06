# Remove a Flexible Asset Type You No Longer Use

Deletes one empty flexible asset type, such as the old "ScalePad Assets" list, which the CloudRadial portal has no button for. It checks first that no company has anything in it.

**Formerly:** Remove Empty Flexible Asset Type | **Marketplace ID:** Not yet listed | **Type:** Workflow

## Files (always the latest version)

These links point at the `main` branch, so they always open the current version.

**Import in this order.** A workflow can't find its agent until the agent is imported.

1. Import the **CloudRadial UCP Assistant** agent, [`cloudradial-ucp.agent.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/cloudradial-ucp/cloudradial-ucp.agent.yml) from [Run Portal Admin Tasks by Asking](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp), on **Agents → Custom → Import** (skip this if it's already installed).
2. Import [`remove-empty-flexible-asset-type.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/remove-empty-flexible-asset-type/remove-empty-flexible-asset-type.yml) on **Workflows → Import**.

| What | Link |
|---|---|
| View `remove-empty-flexible-asset-type.yml` | [GitHub](https://github.com/cloudradial/Automations/blob/main/automationai/remove-empty-flexible-asset-type/remove-empty-flexible-asset-type.yml) |
| Download `remove-empty-flexible-asset-type.yml` (right-click > Save link as) | [Raw file](https://raw.githubusercontent.com/cloudradial/Automations/main/automationai/remove-empty-flexible-asset-type/remove-empty-flexible-asset-type.yml) |
| Needs the agent | [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp) |
| All files in this automation | [automationai/remove-empty-flexible-asset-type](https://github.com/cloudradial/Automations/tree/main/automationai/remove-empty-flexible-asset-type) |
| Change history | [Commits](https://github.com/cloudradial/Automations/commits/main/automationai/remove-empty-flexible-asset-type) |

## How it works

A CloudRadial **AutomationAI workflow** that removes one flexible asset type by name. Flexible asset types appear as lists under **Infrastructure**, and the portal can create them but not delete them.

It runs the [CloudRadial UCP Assistant](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp) agent with a narrow goal:
1. Find the type by its exact name. If there's no match, or more than one, it stops.
2. Check **every company** for rows in the type. If any company still has a row, it stops and reports how many each company has.
3. Only if the type is empty, delete it. The delete waits in the **Inbox** until you approve it.
4. Confirm the type is gone.

It never deletes a row, a field, or any other type.

The usual reason to run it is after the [ScalePad to CloudRadial Sync](https://github.com/cloudradial/Automations/tree/main/automationai/scalepad-cloudradial-sync). Older Sync versions put all non-endpoint hardware into a single "ScalePad Assets" type. The current version moves those rows into a type per kind of device (Network Devices, Mobile Devices, Printers & Imaging and so on). Once every company has been synced, "ScalePad Assets" is empty and can go.

## Pieces

| File | Type | Role |
|---|---|---|
| [`remove-empty-flexible-asset-type.yml`](https://github.com/cloudradial/Automations/blob/main/automationai/remove-empty-flexible-asset-type/remove-empty-flexible-asset-type.yml) | `automationsWorkflow` | **Run inputs** (reads `typeName` and writes the request) → **Remove the type if empty** (an Agent node running `cloudradial-ucp-assistant`, limited to the `cloudradial-v2-compliance` tools, `autoApprove: false`). |

## Install / run

1. Import the agent first: [`cloudradial-ucp/`](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp) **0.1.4 or later** on **Agents → Custom → Import** (slug `cloudradial-ucp-assistant`). 0.1.4 is the first version that includes the flexible asset tools.
2. Make sure the first-party extension `cloudradial-v2-compliance` is installed and connected.
3. On **Workflows → Import**, upload `remove-empty-flexible-asset-type.yml`, then **Publish** and **deploy** it to your runner.
4. **Preview:** with the agent in dry run (how it ships), run it with no input. The agent reports the type's id and row count and says it *would* delete it. Nothing changes.
5. **Delete:** take the agent out of dry run (see [Dry run and going live](https://github.com/cloudradial/Automations/tree/main/automationai/cloudradial-ucp#dry-run-and-going-live)) and run it again. Approve the delete in the **Inbox**. To go back to preview afterwards, set the agent back to dry run.

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
