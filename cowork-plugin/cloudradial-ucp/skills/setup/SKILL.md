---
name: setup
description: >
  First-time setup wizard AND welcome tour for the CloudRadial UCP plugin.
  Run this BEFORE any other CloudRadial work in a session — every other skill
  depends on it.
  Triggers: "setup the CloudRadial plugin", "configure the plugin", "connect to
  my portal", "I just installed the CloudRadial plugin", "what does the
  CloudRadial plugin do", "tour the plugin", "show me the welcome", a
  `setup_status` result with `configured: false`, or ANY CloudRadial MCP tool
  failing with a "credentials not configured" / 401 / 403 error. Also run
  proactively at the start of any CloudRadial-related conversation if you
  haven't checked setup_status yet.
metadata:
  version: "2.1.0"
---

# CloudRadial UCP Setup Wizard

## What this plugin needs

The plugin ships with a **bundled local MCP server** (inside the `.plugin` file itself) that talks to the CloudRadial API V2 on your behalf. Setup has two questions:

1. Is the MCP server reachable (i.e. did the MCP client load it)?
2. Are your CloudRadial API keys stored in the OS keychain?

There is **no Azure Function, no Chrome extension, no separate server to deploy**. The MCP server runs as a local Node process spawned by your MCP client (Claude Desktop, Claude Code, Cowork).

---

## Step 0 — Brand intro + plugin tour (do this FIRST on the first run)

The very first thing this wizard does in a conversation is show the user a branded welcome with the four headline things the plugin can do, then let them pick what to see next. Skip this step if you've already shown it earlier in the current conversation.

### 0a. Render the brand intro exactly as below

Output the following block verbatim (preserve emoji, blockquote, bold, and indentation — this is the closest we can get to "brand colors" inside the chat renderer):

> ☁️📡 **CloudRadial UCP**
>
> *The AI-Powered Service Delivery & Client Success Platform — right inside Claude.*
>
> Once it's set up, just ask in plain English. Here's what's included:
>
> - 🔍 **Look things up** — companies, users, endpoints, articles, feedback, and 30+ resource types
> - 📝 **Create content & training** — KB articles, assessments, courses & lessons (even from a YouTube link)
> - 🔧 **Maintain the portal** — refresh endpoint warranty, flexible-asset tracking, services, tokens
> - 🤖 **Talk to your portal** — no scripts, no API tools, no copy-pasting keys

### 0b. Present the tour menu (interactive "buttons")

Immediately after the intro, call `AskUserQuestion` (header **"Get started"**, single-select) with these four options:

| Option label | What you do when picked |
|---|---|
| **Set up credentials now (Recommended)** | Proceed straight to Step 1 (status check) — this is the primary install path. |
| **Show me example commands** | Paste the three category cards from the README's "What you can do" (🔎 / 📝 / 🔧), each with 3–4 sample prompts. Then re-display this tour menu so they can keep exploring. |
| **List all skills** | Show the skill table from the README ("Skills") — name + one-line description for each. Then re-display this tour menu. |
| **List all 17 MCP tools** | Show the tool table from the README ("MCP tools (17)") — name + one-line purpose. Then re-display this tour menu. |

If the user types something free-form instead of picking, just do what they asked (the `Other` choice is always implicit). If they want to bail entirely, that's fine — don't push.

### 0c. Don't repeat the intro

Once Step 0 has run in a conversation, do NOT re-render the brand block on subsequent invocations of this wizard — go straight to Step 1.

---

## Step 1 — Check current state

Call the `setup_status` MCP tool first. Don't ask the user any questions until you've checked.

**Three possible outcomes:**

| `setup_status` result | What it means | What to do |
|---|---|---|
| Tool not available / "Unknown tool" | MCP server isn't registered with the client | Go to Step 2 (register server) |
| `{configured: false, source: null}` | Server is loaded but keys aren't stored | Go to Step 3 (collect keys) |
| `{configured: true, source: "keychain", publicKeyHint: "...abcd"}` | Already configured | Go to Step 4 (verify) |
| `{configured: true, source: "env"}` | Configured via env vars (developer mode) | Go to Step 4 (verify) — don't overwrite their env config |

---

## Step 2 — Register the MCP server (if not already)

If the `setup_status` tool isn't available, the MCP server isn't registered with this client. The plugin's `.mcp.json` declares it, so reinstalling/reloading the plugin usually fixes this. Tell the user:

> "The CloudRadial MCP server isn't loaded yet. Please reload the plugin (Cowork: re-drop the `.plugin` file; Claude Code: `/plugin reload cloudradial-ucp`; Claude Desktop: restart). Then say 'Setup the CloudRadial Plugin' again."

If reinstalling doesn't help, the issue is almost always one of:

- **They installed the wrong OS variant of the `.plugin` file** — e.g., `windows-x64` on a Mac. Have them download the variant matching their machine.
- **Node 18+ isn't on the MCP client's PATH.** The bundled server runs as `node server/index.mjs`. Confirm with `node --version` in a terminal; if the GUI app still can't find it, install Node system-wide and restart the client.

---

## Step 3 — Collect and store the keys

### 3a. Find the keys

The user gets these from their CloudRadial admin portal: **Settings → API** → Public Key + Private Key. If they don't see this menu, they don't have admin access — direct them to whoever does.

### 3b. Privacy note (state this once, before asking)

Tell the user, verbatim or close:

> "I'll need your CloudRadial public and private keys. Once I store them, they go straight into your OS keychain (Windows Credential Manager / macOS Keychain / Linux libsecret) — encrypted at rest, accessible only to your user account. **However:** when you paste them here, the keys will briefly appear in this conversation's transcript. If you'd rather avoid that, you can instead set them as environment variables in your MCP client config (`CLOUDRADIAL_PUBLIC_KEY`, `CLOUDRADIAL_PRIVATE_KEY`) and skip this wizard. Continue?"

If the user wants the env-var path, point them at the README and stop. Otherwise continue.

### 3c. Ask for the keys

Use `AskUserQuestion` for each so the keys are entered through the structured input UI rather than as a regular chat message:

- **Question 1:** "Paste your CloudRadial **public key**."
- **Question 2:** "Paste your CloudRadial **private key**."
- **Question 3 (only if non-default):** "Which CloudRadial region? Default is US." Options: `https://api.us.cloudradial.com` (US), `https://api.eu.cloudradial.com` (EU), `Other`.

### 3d. Store via the MCP tool

Call `configure_credentials` with `public_key`, `private_key`, and `base_url` (if they chose EU or Other). The tool will:

1. Make a live `GET /v2/odata/company/$count` against CloudRadial to validate the keys.
2. If validation passes, write them to the OS keychain.
3. If validation fails (401/403), it returns an error WITHOUT writing — ask the user to re-check the keys and try again.

**Do not log, echo, or repeat the keys back** in your reply. After a successful call, the tool returns `publicKeyHint` (last 4 chars only) — use that for confirmation.

---

## Step 4 — Verify

Make one real call to prove end-to-end works:

- Call the `search_companies` tool with `name: "a"` (broad search).
- Expected: a small array of company objects.

**If it succeeds:** Confirm, then offer a one-click starter menu so a non-technical user can act immediately.

First confirm using the `publicKeyHint` from `setup_status`:

> "You're all set — your CloudRadial keys are stored securely in this computer's keychain (public key ends in `...{hint}`), and I just confirmed the connection works."

Then present a starter menu with the `AskUserQuestion` tool (header "Get started", single-select) so the user can pick an action with one click instead of having to know what to type. Offer these four options, and after they pick, hand off to the matching skill and actually run the workflow:

| Option label | What you do when picked |
|---|---|
| **Update warranty dates** | Ask which company (or a specific serial number). Use the **endpoint-reporting** skill: list the company's endpoints, then call `endpoint_update_warranty` for each serial that needs a refresh. |
| **Create an assessment** | Ask which company and what kind of assessment. Use the **content-management** skill to `create_resource` an `assessment` for that company. |
| **Build a training course** | Ask for the source — a topic to describe, a document, or a YouTube link. If it's a video/document, you read and summarize the source yourself, then use the **course-management** skill to create the `course` and its `course_lesson`s. (Reading the video is your own capability — the plugin just stores the resulting course.) |
| **Track flexible assets** | Ask which company. Use the **assessment-compliance** skill to review existing `flexible_asset` records, or `create_resource` new ones. (Note: this creates/tracks flexible assets in CloudRadial — it does not import from ITGlue; that's a separate standalone script.) |

The `AskUserQuestion` tool always adds an "Other" choice automatically — if the user types a free-form request instead of picking one, just do that. Don't block them into only these four.

**If it fails after Step 3:** Surface the exact error from the MCP tool. Common issues:

| Symptom | Cause | Fix |
|---|---|---|
| 401/403 from CloudRadial | Wrong keys | Re-run Step 3 with corrected keys |
| Network error / DNS | Wrong base URL | Re-run with the correct region |
| Tool returns "credentials not configured" | Keychain write silently failed (rare; SSH/headless Linux without libsecret) | Tell user to set `CLOUDRADIAL_PUBLIC_KEY` / `CLOUDRADIAL_PRIVATE_KEY` env vars in their MCP client config as a fallback |

---

## Reconfiguring

To rotate keys or switch portals: just re-run this wizard. `configure_credentials` overwrites whatever's in the keychain.

To remove the credentials entirely: call the `clear_credentials` tool. Note this only clears the keychain — env-var-based config is unaffected.

---

## What you should NEVER do in this skill

- Don't read or write any `.cloudradial/config.json` file. That was the old (Azure Function) flow. Credentials now live only in the OS keychain.
- Don't try to run `az`, `func`, `git clone`, or any Azure commands. There is no Azure Function in this version of the plugin.
- Don't log the user's keys back to them in chat, even partially. Use `publicKeyHint` from `setup_status` for confirmation.
- Don't proceed with other CloudRadial work in the same turn if setup fails — fix setup first.
