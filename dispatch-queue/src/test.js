#!/usr/bin/env node
// Checks the generated Dispatch Queue files:  node dispatch-queue/src/test.js
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const yaml = (() => {
  const tries = [process.env.JS_YAML_PATH, 'js-yaml',
    'C:/Users/NicholasWestgate/OneDrive - Azurative/Documents/Claude/handoffs/src/node_modules/js-yaml'];
  for (const t of tries) { if (!t) continue; try { return require(t); } catch (e) { /* next */ } }
  throw new Error('js-yaml not found: set JS_YAML_PATH');
})();

const ROOT = path.resolve(__dirname, '..');
const snapshot = JSON.parse(fs.readFileSync(path.join(__dirname, 'tools-snapshot.json'), 'utf8'));
let pass = 0, fail = 0;
function ok(cond, name) { if (cond) { pass++; } else { fail++; console.log(`FAIL ${name}`); } }

const DASH = /[\u2013\u2014]/;
const AAI96 = 'Write one short sentence before each tool call; never send an empty message';

for (const key of ['connectwise', 'autotask', 'halo']) {
  const s = snapshot[key];
  const agentFile = path.join(ROOT, `dispatch-queue-${key}.agent.yml`);
  const wfFile = path.join(ROOT, `dispatch-queue-${key}.yml`);
  const agentText = fs.readFileSync(agentFile, 'utf8');
  const wfText = fs.readFileSync(wfFile, 'utf8');
  let a, w;
  try { a = yaml.load(agentText); ok(true, `${key} agent parses`); } catch (e) { ok(false, `${key} agent parses: ${e.message}`); continue; }
  try { w = yaml.load(wfText); ok(true, `${key} workflow parses`); } catch (e) { ok(false, `${key} workflow parses: ${e.message}`); continue; }

  // Agent
  ok(a.automationsAgent === 1 && a.agent, `${key} agent marker`);
  const g = a.agent;
  ok(g.slug === `dispatch-queue-${key}`, `${key} agent slug`);
  ok(/^\d+\.\d+\.\d+$/.test(g.version) && g.version === '1.0.0', `${key} agent version 1.0.0`);
  ok(g.model === '', `${key} model blank`);
  ok(g.dryRunDefault === true, `${key} dryRunDefault true`);
  ok(JSON.stringify(g.requiredExtensionSlugs) === JSON.stringify([s.slug]), `${key} requiredExtensionSlugs is only ${s.slug}`);
  ok(g.systemPrompt.includes(AAI96), `${key} AAI-96 sentence`);
  ok(!/\{\{[A-Z_]+\}\}/.test(g.systemPrompt), `${key} no unfilled prompt placeholders`);
  for (const f of ['inputSchema', 'outputSchema', 'variablesJson']) {
    try { JSON.parse(g[f]); ok(true, `${key} ${f} JSON`); } catch (e) { ok(false, `${key} ${f} JSON: ${e.message}`); }
  }
  ok(!DASH.test(agentText) && !DASH.test(wfText), `${key} no en or em dashes`);

  // Every tool the prompt names exists in this PSA's snapshot; no other PSA's tools leak in.
  const prefix = { connectwise: 'cw_', autotask: 'at_', halo: 'halo_' }[key];
  const named = new Set((g.systemPrompt.match(/\b(cw|at|halo)_[a-z_]+\b/g) || []));
  const known = new Set([...s.read, ...s.write]);
  for (const t of named) {
    ok(t.startsWith(prefix), `${key} prompt names only ${prefix} tools (${t})`);
    ok(known.has(t), `${key} tool ${t} is in the snapshot`);
  }
  // Every write tool the prompt names is one the agent may propose.
  for (const t of named) {
    if (/_(update|create|add|delete|close|set)_/.test(t) || /_(add_action)$/.test(t)) ok(s.write.includes(t), `${key} write tool ${t} is an allowed proposal`);
  }
  for (const t of s.write) ok(named.has(t), `${key} allowed write ${t} is used in the prompt`);
  ok(!/delete/.test([...named].join(' ')), `${key} no delete tool named`);

  // Workflow
  ok(w.automationsWorkflow === 1 && w.name && w.description && w.definition, `${key} workflow marker`);
  const d = w.definition;
  ok(d.schemaVersion === 1 && d.startActivityId === 'start', `${key} schemaVersion and start`);
  const start = d.activities.find((x) => x.type === 'start');
  ok(start && start.properties.webhookEnabled === false, `${key} webhook ships disabled`);
  const node = d.activities.find((x) => x.type === 'agent');
  ok(node && node.properties.agentSlug === g.slug, `${key} node uses the agent`);
  ok(node && node.properties.model === '', `${key} node model blank`);
  ok(node && node.properties.autoApprove === false, `${key} node autoApprove false`);
  ok(node && JSON.stringify(node.properties.allowedExtensions) === JSON.stringify([s.slug]), `${key} allowedExtensions only ${s.slug}`);
  ok(node && node.properties.goal && !/\{\{\s*input\./.test(wfText), `${key} goal set, no input.* bindings`);
  for (const f of ['inputSchema', 'outputSchema', 'inputBindingsJson']) {
    try { JSON.parse(node.properties[f]); ok(true, `${key} node ${f} JSON`); } catch (e) { ok(false, `${key} node ${f} JSON: ${e.message}`); }
  }
  const ids = new Set(d.activities.map((x) => x.id));
  ok(d.connections.every((c) => ids.has(c.source) && ids.has(c.target) && c.sourceHandle === null), `${key} connections resolve`);
}

// Knowledge templates and README
const kdir = path.join(ROOT, 'knowledge');
const kfiles = fs.readdirSync(kdir).filter((f) => f.endsWith('.md'));
ok(kfiles.length === 3, 'three knowledge templates');
for (const f of kfiles) {
  const t = fs.readFileSync(path.join(kdir, f), 'utf8');
  ok(/Example, replace with your own/.test(t), `${f} has the example banner`);
  ok(!DASH.test(t), `${f} no en or em dashes`);
}
const readme = fs.readFileSync(path.join(ROOT, 'README.md'), 'utf8');
ok(!DASH.test(readme), 'README no en or em dashes');
ok(!/timezest|invarosoft|usehalo|halo dispatch/i.test(readme), 'README names no competitor');
ok(!/KMCO/i.test(readme + kfiles.map((f) => fs.readFileSync(path.join(kdir, f), 'utf8')).join('')), 'no real client names');
ok(readme.includes('## Technical details'), 'README has Technical details');
const top = readme.split('## Technical details')[0];
ok(!/requiredExtensionSlugs|inputSchema|dryRunDefault/.test(top), 'README top keeps technical fields out');
for (const q of ['Who\'s doing the work?', 'What\'s the goal?', 'When should it check in?', 'How much can it do on its own?', 'Where does it keep notes?']) {
  ok(top.includes(q), `README setup answers "${q}"`);
}
ok(top.includes('Try a check-in now'), 'README says Try a check-in now');
ok(top.includes('Also post to Teams channels'), 'README covers Teams posting');

// Generated files are current.
try {
  execFileSync(process.execPath, [path.join(__dirname, 'build.js'), '--check'], { stdio: 'pipe' });
  ok(true, 'build --check current');
} catch (e) { ok(false, `build --check: ${String(e.stdout || e.message).trim()}`); }

console.log(`${pass}/${pass + fail} passed`);
process.exit(fail ? 1 : 0);
