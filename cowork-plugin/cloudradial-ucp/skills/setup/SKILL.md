---
name: setup
description: Set up, verify, rotate, or troubleshoot the CloudRadial plugin connection. Check setup_status before other CloudRadial work. Collect API credentials only in the plugin's local form, after OS-keychain verification.
metadata:
  version: "2.6.0"
---

# CloudRadial setup

Use one portable plugin on Windows, macOS, or Linux. Setup downloads the pinned
native keyring dependency for the current OS, CPU, and Linux libc into a local
per-user runtime cache. Keys belong in Windows Credential Manager, macOS Keychain,
or Linux Secret Service. There is no encrypted-file fallback.

## Check the connection first

Call `setup_status`. It returns no API keys: only configuration status, region,
public-key suffix, platform/architecture, and keychain availability.

- If configured, verify with `search_companies` using `name: "a"` and report the
  result. Don't rotate working credentials unless requested.
- If the source is `env`, preserve that existing setup. Environment variables
  override the keychain. Do not claim those keys are stored in the keychain.
- If tools are missing, confirm Node.js is installed and reload/restart the
  client's plugin. Use the same portable plugin file on all supported platforms.

## Prepare secure storage before asking for keys

Call `setup_secure_storage`. A setup request authorizes the dependency install
and temporary keychain probe; tool/runtime approval rules still apply. Explain
that setup downloads `@napi-rs/keyring@2.1.0` and the matching native package from
npm. Lifecycle scripts are disabled. Wait for `keychainVerified: true`.

If installation or verification fails, report the returned error and fix that
condition first. Never collect credentials to work around a storage failure.

- Missing npm: install Node.js with npm and restart the client.
- Locked/unavailable keychain: unlock it or run setup in the desktop user session.
- Linux: requires a running Secret Service (such as GNOME Keyring or KWallet)
  and D-Bus session; the plugin does not fall back to volatile kernel keyutils.
- Unsupported platform: stop and explain it; do not suggest a different platform's
  native binary.

## Enter credentials locally

Call `configure_credentials` with an empty object. **Never pass API keys as MCP
arguments or ask for keys in chat, attachments, screenshots, or structured chat
questions.** This tool opens a browser form bound only to 127.0.0.1, protected by
a random session token, origin/host checks, and a ten-minute timeout.

Tell the user to enter their public/private keys from CloudRadial **Settings →
API**, select US or EU, and click **Connect**. The local helper sends the keys
directly over HTTPS to CloudRadial for validation and writes them to the OS
keychain only after successful validation. The form URL and keys are not returned
through MCP.

If the browser cannot launch, have the user run this in a **local terminal on the
desktop machine**, substituting the actual plugin path:

```text
node "<plugin-root>/server/setup-local.mjs"
```

The terminal helper prepares the keychain and opens a browser, or prints a local
URL for the user to open on that same computer. Do not run it through a remote
executor to capture the URL. Headless users may keep an established environment
variable/secret-manager setup; do not request secrets in chat.

## Verify completion

After the user finishes, call `setup_status`, then `search_companies` with
`name: "a"`. Confirm keychain storage only when `source: "keychain"`, and confirm
the connection only after the API call succeeds. Do not claim setup is finished
while the form is waiting for the user.

For rotation, re-open local setup. Existing credentials are retained if API
validation fails; a keychain-write failure attempts to restore the previous entry
and reports failure. `clear_credentials` clears OS-keychain entries only and does
not remove environment overrides or legacy credential files.

If `legacyCredentialsDetected` is true, explain that old encrypted-file keys are
no longer used. Set up the keychain locally and verify it before the user decides
whether to remove the old file. Never read, decrypt, display, automatically migrate,
or delete that old file during this setup flow.

Once connected, offer relevant starter prompts such as looking up a company,
reviewing endpoints, or building a training course. Run additional portal changes
only within the user's request.
