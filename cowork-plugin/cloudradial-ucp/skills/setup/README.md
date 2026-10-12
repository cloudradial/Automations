# Set up CloudRadial

Ask **Set up CloudRadial** after installing the plugin. Setup installs the native
keyring dependency for your machine, verifies your OS keychain, and opens a local
browser form. Enter your CloudRadial API keys there, select US or EU, and click
**Connect**. Keys never need to enter chat.

The same plugin file works across supported Windows, macOS, and Linux machines.
Node.js 18+ is required; first-time dependency setup also needs npm and internet
access. Linux requires a persistent Secret Service and D-Bus desktop session.

If secure storage is unavailable, setup stops before collecting keys. There is
no encrypted-file fallback. See [deployment guidance](../../DEPLOYMENT.md) for
storage locations, local-terminal setup, and troubleshooting.

Try **Is the CloudRadial plugin configured?** to check status, or **Clear my
CloudRadial credentials** to remove saved OS-keychain entries.

## Example prompts

Copy a prompt, swap in your own company names or IDs, and paste it into Claude or Codex. Each prompt says what to check and when to stop for your confirmation, which is what keeps the assistant on track. Prompts that change your portal always show you the change first.

**Labels:** `Per-company` works on one client, `All clients` across your whole partner portal. `Read-only` changes nothing; `Writes to the portal` changes data after you confirm. Status is from live testing in October 2026 (v2.6.3): **Tested**, **Partly works** (see Good to know), **Portal only** (the API can't do it yet), or **Not yet tested**.

### Set up the plugin
`Plugin` · `Local only` · **Tested**

```
Set up the CloudRadial plugin. Check that my computer's keychain works, open the
local form so I can enter my API keys outside this chat, and confirm the
connection works before we do anything else.
```

**What you get:** Keys saved in your OS keychain, region set, and a live connection check.

**Good to know:** Keys never go into chat. If the keychain isn't available, setup stops before asking for keys.

### Check the connection
`Plugin` · `Local only` · **Tested**

```
Is the CloudRadial plugin configured? Tell me which region it's pointed at and
whether the keys work, without showing the keys.
```

**What you get:** Configured or not, region, and whether CloudRadial accepted the keys.

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
I need to rotate my CloudRadial API keys. Clear the saved credentials, then open
the local form so I can enter the new ones, and check the connection again.
```

**What you get:** Old keys removed from the keychain, new keys saved and checked.

**Good to know:** Run this last in a session: the plugin can't reach CloudRadial until the new keys are in.
