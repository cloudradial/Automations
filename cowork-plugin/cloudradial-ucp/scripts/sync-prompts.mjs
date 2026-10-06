#!/usr/bin/env node
// Copies PROMPTS.md (the prompt catalog) into the plugin READMEs, between
//   <!-- prompts:start --> and <!-- prompts:end -->
// so the Claude and Codex READMEs always list the same prompts.
//
// Usage, from the plugin root (cowork-plugin/cloudradial-ucp):
//   node scripts/sync-prompts.mjs          rewrite the READMEs
//   node scripts/sync-prompts.mjs --check  exit 1 if a README is out of date
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const PLUGIN_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const REPO_ROOT = resolve(PLUGIN_ROOT, "..", "..");
const TARGETS = [join(PLUGIN_ROOT, "README.md"), join(REPO_ROOT, "codex-plugin", "README.md")];
const START = "<!-- prompts:start -->";
const END = "<!-- prompts:end -->";
const check = process.argv.includes("--check");

const catalog = readFileSync(join(PLUGIN_ROOT, "PROMPTS.md"), "utf8").replace(/\r\n/g, "\n").trim();
const block = `${START}\n<!-- Generated from cowork-plugin/cloudradial-ucp/PROMPTS.md by scripts/sync-prompts.mjs. Edit PROMPTS.md, not this block. -->\n\n${catalog}\n\n${END}`;

let stale = 0;
for (const file of TARGETS) {
  const text = readFileSync(file, "utf8").replace(/\r\n/g, "\n");
  const a = text.indexOf(START);
  const b = text.indexOf(END);
  if (a < 0 || b < a) throw new Error(`${file} has no ${START} ... ${END} markers`);
  const next = text.slice(0, a) + block + text.slice(b + END.length);
  if (next === text) { console.log(`up to date: ${file}`); continue; }
  stale++;
  if (check) { console.log(`OUT OF DATE: ${file}`); continue; }
  writeFileSync(file, next);
  console.log(`updated: ${file}`);
}
if (check && stale) process.exit(1);
