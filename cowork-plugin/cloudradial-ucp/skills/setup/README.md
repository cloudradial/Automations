# Setup

> First-run plugin setup: validate API keys, store them securely, and tour what's possible.

**Say this:**

```
Setup the CloudRadial Plugin
```

<img src="images/skill-result.png" alt="Setup confirmation" width="100%">

---

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing in October 2026 (v2.6.3): **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Set up the plugin
`Plugin` · `Local only` · **Tested**

```
Setup the CloudRadial Plugin. Check whether keys are already saved, ask me for
my API keys and region, validate them against CloudRadial before saving, and
confirm the connection works before we do anything else.
```

**What you get:** Keys validated and stored in your OS keychain, region set, and a live connection check.

### Check the connection
`Plugin` · `Local only` · **Tested**

```
Is the CloudRadial plugin configured? Tell me which region it's pointed at and
whether the keys work, without showing the keys.
```

**What you get:** Configured or not, region, and the last four characters of the public key.

### Take a tour
`Plugin` · `Read-only` · **Tested**

```
Give me a tour of the CloudRadial plugin: what each skill does, three things
I could ask it today, and what still has to be done in the portal.
```

**What you get:** Every skill in plain English, with starter prompts.

### Rotate or remove the keys
`Plugin` · `Local only` · **Not yet tested**

```
I need to rotate my CloudRadial API keys. Clear the saved credentials, then
set up the new ones and check the connection again.
```

**What you get:** Old keys removed, new keys validated and saved.

**Good to know:** Run this last in a session: the plugin can't reach CloudRadial until the new keys are in.

## Good to know

- **One setup per machine:** keys are stored in the OS keychain and shared across Claude Desktop, Claude Code, and Cowork.
- **EU partners** should pick `https://api.eu.cloudradial.com` as the base URL during setup.
- **Keys briefly appear in chat.** For more privacy, set environment variables instead.
- **All other skills depend on this one.** If anything errors with 401/403, run setup again.

## Related skills

- Every other skill requires setup first.
- See [DEPLOYMENT.md](../../DEPLOYMENT.md) for install instructions across Claude Desktop, Claude Code, and Cowork.
