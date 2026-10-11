#!/usr/bin/env node
// Build the pure-JS MCP server bundle into ./server/index.mjs.
//
// Produces platform-agnostic JavaScript only: index.mjs (the MCP server) and
// setup-local.mjs (the local key form). No native binary is bundled; setup
// installs the pinned @napi-rs/keyring for the user's OS/CPU into a per-user
// runtime cache and stores keys only in the OS keychain (no file fallback).
// server/ stays committable, so the plugin resolves from a single git commit.
//
// Run from the plugin root: node scripts/build-purejs-server.mjs
import { execSync } from "node:child_process";
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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
// index.mjs is the MCP server; setup-local.mjs is the local key form it launches.
for (const file of ["index.mjs", "setup-local.mjs"]) {
  cpSync(join(MCP_PKG, "dist-bundle", file), join(SERVER_OUT, file));
}
rmSync(join(MCP_PKG, "dist-bundle"), { recursive: true, force: true });

const { version } = JSON.parse(readFileSync(join(PLUGIN_ROOT, ".claude-plugin", "plugin.json"), "utf8"));
writeFileSync(
  join(SERVER_OUT, "BUILD_INFO.txt"),
  `Version: ${version}\nBuilt: ${new Date().toISOString()}\nvariant: portable JavaScript; no bundled native binaries\n` +
    `setup: pinned @napi-rs/keyring installed per OS/CPU/libc at first setup\n` +
    `credentials: verified OS keychain; no credential-file fallback; local form only\n`,
);

console.log(`\nBuilt pure-JS server: ${join(SERVER_OUT, "index.mjs")}`);
console.log("Commit server/index.mjs so the plugin resolves from a single git commit.");
