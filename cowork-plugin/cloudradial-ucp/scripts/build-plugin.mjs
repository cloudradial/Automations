#!/usr/bin/env node
// Build ONE universal, pure-JS cloudradial-ucp.plugin.
//
// The plugin is platform-agnostic JavaScript (no native keyring binary — see
// cloudradial-ucp-mcp/src/keyring-safe.ts), so a single artifact runs on every
// OS. This replaces the previous six-per-OS native build; the release workflow
// publishes this one file, which is also what README's direct-download links to.
//
// Usage, from the plugin root (cowork-plugin/cloudradial-ucp):
//   node scripts/build-plugin.mjs
import { execFileSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join, posix, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = resolve(__dirname, "..");
const REPO_ROOT = resolve(PLUGIN_ROOT, "..");
const MCP_PKG = join(REPO_ROOT, "cloudradial-ucp-mcp");

// 1. Build (and commit-refresh) the pure-JS server bundle into ./server.
execFileSync(process.execPath, [join(__dirname, "build-purejs-server.mjs")], {
  stdio: "inherit",
});

// 2. Assemble the .plugin zip.
const INCLUDE = [
  ".claude-plugin",
  ".mcp.json",
  "DEPLOYMENT.md",
  "README.md",
  "references",
  "server",
  "skills",
];
const EXCLUDE_REL = new Set(["references/swagger.json"]);
const shouldSkip = (rel) => rel.endsWith(".DS_Store") || EXCLUDE_REL.has(rel);

const require = createRequire(join(MCP_PKG, "package.json"));
const AdmZip = require("adm-zip"); // installed by build-purejs-server.mjs's npm install
const zip = new AdmZip();

const walk = (abs, rel) => {
  const st = statSync(abs);
  if (st.isDirectory()) {
    for (const child of readdirSync(abs)) {
      const childRel = rel ? posix.join(rel, child) : child;
      if (shouldSkip(childRel)) continue;
      walk(join(abs, child), childRel);
    }
  } else if (st.isFile() && !shouldSkip(rel)) {
    // Cowork's installer rejects any zip entry whose path contains "@".
    if (rel.includes("@")) throw new Error(`Path contains "@" (installer will reject): ${rel}`);
    zip.addFile(rel, readFileSync(abs));
  }
};

for (const entry of INCLUDE) {
  const abs = join(PLUGIN_ROOT, entry);
  try {
    statSync(abs);
  } catch {
    continue;
  }
  walk(abs, entry.split(sep).join("/"));
}

const artifact = join(PLUGIN_ROOT, "cloudradial-ucp.plugin");
rmSync(artifact, { force: true });
zip.writeZip(artifact);

// Force create_system = 3 (Unix) on every central-directory header so strict
// Mac extractors accept the Unix mode bits carried by the entries.
{
  const buf = readFileSync(artifact);
  const SIG = Buffer.from([0x50, 0x4b, 0x01, 0x02]); // PK\1\2
  let off = 0, patched = 0;
  while ((off = buf.indexOf(SIG, off)) !== -1) {
    if (buf[off + 5] !== 3) { buf[off + 5] = 3; patched++; }
    off += 4;
  }
  if (patched) writeFileSync(artifact, buf);
}

const size = (statSync(artifact).size / 1024 / 1024).toFixed(2);
console.log(`\nBuilt: cloudradial-ucp.plugin (${size} MB) — one file for every OS.`);
