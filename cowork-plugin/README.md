# CloudRadial UCP Plugin

This folder holds the CloudRadial UCP plugin for Claude (Cowork, Claude Desktop, Claude Code) and the source of its MCP server. The same build also ships as the [Codex plugin](https://github.com/cloudradial/Automations/tree/main/codex-plugin).

| Folder | What it is |
|---|---|
| [`cloudradial-ucp/`](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp) | The plugin: skills, the bundled MCP server, manifests for Claude and Codex, and the build scripts. **Start here to install it**, and for the full list of prompts. |
| [`cloudradial-ucp-mcp/`](https://github.com/cloudradial/Automations/tree/main/cowork-plugin/cloudradial-ucp-mcp) | TypeScript source of the MCP server (18 tools over the CloudRadial API V2) |

The plugin runs its MCP server locally with Node.js and talks straight to the CloudRadial API. There's no Azure Function, Chrome extension or hosted server; earlier versions needed them, and they're no longer used.

## Building

From `cloudradial-ucp/`:

```
node scripts/build-plugin.mjs
```

This copies the prompt catalog (`PROMPTS.md`) into the Claude and Codex READMEs, bundles the server into `server/index.mjs`, and writes one `cloudradial-ucp.plugin` for every OS, with both the `.claude-plugin` and `.codex-plugin` manifests. Copy that file to `codex-plugin/` when you release.

To change the prompts, edit `cloudradial-ucp/PROMPTS.md` and run `node scripts/sync-prompts.mjs` (or the build). `node scripts/sync-prompts.mjs --check` fails if a README is out of date.

## License

MIT
