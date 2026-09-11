#!/usr/bin/env node
// Build the pure-JS MCP server bundle into ./server/index.mjs.
//
// Unlike build-server.mjs (which packs a per-OS native keyring binary), this
// produces ONE platform-agnostic JavaScript file. Credential storage uses the
// pure-JS wrapper (cloudradial-ucp-mcp/src/keyring-safe.ts): an encrypted file
// store by default, with the OS keychain used only if @napi-rs/keyring resolves
// at runtime. That makes server/ committable and the plugin resolvable from a
// single git commit — the requirement for the claude-community marketplace.
//
// Run from the plugin root: node scripts/build-purejs-server.mjs
import { execSync } from "node:child_process";
import { cpSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = resolve(__dirname, "..");
const REPO_ROOT = resolve(PLUGIN_ROOT, "..");
const MCP_PKG = join(REPO_ROOT, "cloudradial-ucp-mcp");
const SERVER_OUT = join(PLUGIN_ROOT, "server");

const sh = (cmd, cwd) => {
  console.log(`\n> (${cwd}) ${cmd}`);
  execSync(cmd, { cwd, stdio: "inherit" });
};

sh("npm install", MCP_PKG);
sh("npm run bundle", MCP_PKG);

rmSync(SERVER_OUT, { recursive: true, force: true });
mkdirSync(SERVER_OUT, { recursive: true });
cpSync(join(MCP_PKG, "dist-bundle", "index.mjs"), join(SERVER_OUT, "index.mjs"));
rmSync(join(MCP_PKG, "dist-bundle"), { recursive: true, force: true });

writeFileSync(
  join(SERVER_OUT, "BUILD_INFO.txt"),
  `Built ${new Date().toISOString()}\nvariant: pure-js (no native keyring binary)\n` +
    `credentials: encrypted file store by default; OS keychain if @napi-rs/keyring resolves at runtime\n`,
);

console.log(`\nBuilt pure-JS server: ${join(SERVER_OUT, "index.mjs")}`);
console.log("Commit server/index.mjs so the plugin resolves from a single git commit.");
