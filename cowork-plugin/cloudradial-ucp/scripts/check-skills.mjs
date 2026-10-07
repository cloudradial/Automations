#!/usr/bin/env node
// Fail if a skill file is cut off or corrupted. Six SKILL.md files once shipped
// truncated mid-sentence (one padded with NUL bytes), twice.
//
// Checks every .md under skills/ and references/:
// - no NUL bytes
// - code fences are balanced
// - SKILL.md has front matter with name and description
// - the last line ends like a finished line (punctuation, a closing fence,
//   a table row, a link or emphasis), not mid-word
//
// Run from anywhere: node scripts/check-skills.mjs
import { readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const files = [];
const walk = (dir) => {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p);
    else if (name.endsWith(".md")) files.push(p);
  }
};
for (const d of ["skills", "references"]) walk(join(ROOT, d));

// A file's last line looks cut off when it's a heading or an empty list
// marker, ends with a comma or an opening bracket, or is prose that stops
// without punctuation. List items, table rows, fences and URLs may end bare.
function cutOff(line) {
  if (/^#{1,6}\s/.test(line)) return true;
  if (/^([-*+]|\d+\.)\s*$/.test(line)) return true;
  if (/[,(\[{]$/.test(line)) return true;
  if (/^([-*+]|\d+\.)\s+\S/.test(line) || line.startsWith("|") || /^(```|~~~|-{3,})/.test(line)) return false;
  if (/https?:\/\/\S+$/.test(line)) return false;
  return !/[.!?:)\]`*_>"'”’]$/.test(line);
}

const problems = [];
for (const f of files) {
  const rel = relative(ROOT, f);
  const text = readFileSync(f, "utf8");
  if (text.includes("\0")) problems.push(`${rel}: contains NUL bytes`);
  const fences = text.split(/\r?\n/).filter((l) => /^\s*(```|~~~)/.test(l)).length;
  if (fences % 2) problems.push(`${rel}: unbalanced code fence (${fences} fence lines)`);
  if (rel.endsWith("SKILL.md")) {
    const fm = /^---\r?\n([\s\S]*?)\r?\n---/.exec(text);
    if (!fm || !/^name:/m.test(fm[1]) || !/^description:/m.test(fm[1])) problems.push(`${rel}: missing front matter name/description`);
  }
  const lastLine = (text.replace(/\0+/g, "").trimEnd().split(/\r?\n/).pop() ?? "").trim();
  if (cutOff(lastLine)) problems.push(`${rel}: looks cut off; last line is "${lastLine.slice(-80)}"`);
}

if (problems.length) {
  console.error(problems.map((p) => "FAIL " + p).join("\n"));
  console.error(`${problems.length} problem(s) in ${files.length} files`);
  process.exit(1);
}
console.log(`Skill files OK (${files.length} checked)`);
