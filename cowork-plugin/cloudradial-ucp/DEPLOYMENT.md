# CloudRadial UCP installation and secure setup

Install `cloudradial-ucp.plugin` in your MCP-capable client and restart/reload it.
The same file works on supported Windows, macOS, and Linux machines. Node.js 18+
must be available to the client. First-time secure-storage setup also needs npm
and network access to https://registry.npmjs.org.

In Codex, install the plugin through its local marketplace or plugin importer.
In Claude/Cowork, use the client's plugin importer or configured marketplace.
Start a new chat after installation and ask **Set up CloudRadial**.

## What setup does

1. Checks `setup_status`, including OS/CPU and existing credentials.
2. Calls `setup_secure_storage` to install the exact `@napi-rs/keyring@2.1.0`
   dependency and npm's matching optional native package. npm lifecycle scripts
   are disabled; binaries live in a local per-user cache, outside the plugin.
3. Verifies OS-keychain write/read/delete using a temporary random value. It stops
   before requesting API keys if the keychain is unavailable.
4. Calls `configure_credentials` without key arguments to open a local browser form.
5. The user enters keys locally and selects US or EU. The helper validates them
   directly with CloudRadial over HTTPS, then saves them in the OS keychain.
6. The assistant checks status and makes a read-only company search to verify access.

No API keys are passed through chat or MCP setup arguments. The form listens only
on 127.0.0.1 and requires a random session token and matching request origin/host.
It expires after ten minutes. There is no encrypted-file fallback.

## Storage and runtime locations

| Platform | Credentials | Native dependency cache |
|---|---|---|
| Windows | Windows Credential Manager | `%APPDATA%\cloudradial-ucp-mcp\runtime\keyring-2.1.0` |
| macOS | macOS Keychain | `~/Library/Application Support/cloudradial-ucp-mcp/runtime/keyring-2.1.0` |
| Linux | Persistent Secret Service | `$XDG_CONFIG_HOME/cloudradial-ucp-mcp/runtime/keyring-2.1.0`, or `~/.config/...` |

Credentials use service `cloudradial-ucp-mcp`, account `credentials-v2`, as one
JSON entry to avoid partial multi-entry saves. Older credentials already in the
OS keychain remain readable. Old encrypted-file credentials are detected but not
read, migrated, or removed automatically.

An established `CLOUDRADIAL_PUBLIC_KEY` / `CLOUDRADIAL_PRIVATE_KEY` environment
configuration still overrides the keychain. Do not put values in chat. Local
setup refuses to replace that override without the user changing their client.

## Troubleshooting

- **Node/npm missing:** install Node.js with npm; restart the client so PATH updates.
- **Dependency download fails:** check network access and retry `setup_secure_storage`.
- **Keychain verification fails:** unlock the keychain and use the desktop user session.
- **Linux:** run a persistent Secret Service and D-Bus session. Volatile kernel
  keyutils is intentionally disabled.
- **Browser unavailable:** on the desktop machine run
  `node "<plugin-root>/server/setup-local.mjs"` in a local terminal. It opens the
  form or prints a URL for use on that computer. Never share that URL in chat.
- **API rejects keys:** check both keys and region in the local form. Invalid keys
  do not overwrite existing stored credentials.
- **Rotate:** open local setup again. **Remove:** call `clear_credentials`;
  environment overrides and legacy files are unaffected.

## Maintainer validation

Run `node --test` from the plugin directory. Tests cover failed
validation without writes, keychain rollback, unavailable storage, local form
authentication/origin controls, and secret-free MCP results.

`scripts/build-secure-server.mjs` accepts the original 2.5.0 `server/index.mjs`
bundle and replaces its credential subsystem, preserving that release's API
tools. The new security modules are readable `.mjs` source. Do not rebuild from
an older bundle that omits the 2.5.0 tool changes.
