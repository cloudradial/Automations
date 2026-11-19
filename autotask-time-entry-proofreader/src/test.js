#!/usr/bin/env node
// Checks the generated Autotask Time Entry Proofreader files:  node autotask-time-entry-proofreader/src/test.js
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

const SLUG = 'autotask-time-entry-proofreader';
const VERSION = '0.5.0';
const ROOT = path.resolve(__dirname, '..');
const snapshot = JSON.parse(fs.readFileSync(path.join(__dirname, 'tools-snapshot.json'), 'utf8'));
const EXT = Object.keys(snapshot.extensions);
let pass = 0, fail = 0;
function ok(cond, name) { if (cond) { pass++; } else { fail++; console.log(`FAIL ${name}`); } }
const DASH = /[\u2013\u2014]/;
const AAI96 = 'Write one short sentence before each tool call; never send an empty message';

const agentText = fs.readFileSync(path.join(ROOT, `${SLUG}.agent.yml`), 'utf8');
const wfText = fs.readFileSync(path.join(ROOT, `${SLUG}.yml`), 'utf8');
const a = yaml.load(agentText); ok(true, 'agent parses');
const w = yaml.load(wfText); ok(true, 'workflow parses');

// Agent
ok(a.automationsAgent === 1 && a.agent, 'agent marker');
const g = a.agent;
ok(g.slug === SLUG, 'agent slug');
ok(g.version === VERSION, `agent version ${VERSION}`);
ok(g.model === '', 'model blank');
ok(g.dryRunDefault === true, 'dryRunDefault true');
ok(JSON.stringify(g.requiredExtensionSlugs) === JSON.stringify(EXT), 'requiredExtensionSlugs match the snapshot');
ok(g.systemPrompt.startsWith('Every message you send') && g.systemPrompt.includes(AAI96), 'AAI-96 sentence at the top');
ok(/BUDGET\. Use about 15 tool calls/.test(g.systemPrompt), 'budget line');
ok(!/westgate|kmco/i.test(agentText + wfText), 'no real client names');
for (const f of ['inputSchema', 'outputSchema', 'variablesJson']) {
  try { JSON.parse(g[f]); ok(true, `${f} JSON`); } catch (e) { ok(false, `${f} JSON: ${e.message}`); }
}
ok(/inputSchema: \|/.test(agentText) && /outputSchema: \|/.test(agentText), 'schemas are block scalars');

// Tools: every tool the prompt names is in the snapshot; writes are allowed proposals; total under OpenAI's 128.
const named = new Set(g.systemPrompt.match(/\bat_[a-z_]+\b/g) || []);
const known = new Set([...snapshot.read, ...snapshot.write]);
for (const t of named) ok(known.has(t), `tool ${t} is in the snapshot`);
for (const t of named) if (/^at_(create|patch|update|add|approve|delete)_/.test(t)) ok(snapshot.write.includes(t), `write tool ${t} is an allowed proposal`);
for (const t of snapshot.write) ok(named.has(t), `allowed write ${t} is used in the prompt`);
ok(!/_(delete|create)_/.test([...named].join(' ')), 'no create or delete tool named');
ok(/Only the final message is the JSON object/.test(g.systemPrompt) && !/Output valid JSON only, with no text outside the JSON object/.test(g.systemPrompt), 'JSON-only rule limited to the final message');
ok(/at most 15 eligible time entries/.test(g.systemPrompt), 'caps entries per check-in');
for (const v of JSON.parse(g.variablesJson)) ok(['notifyCompliantEntries', 'proposeApproval', 'approverResourceName'].includes(v.name), `variable ${v.name}`);
const total = Object.values(snapshot.extensions).reduce((n, e) => n + e.toolCount, 0);
ok(total < 128, `total tools ${total} under 128`);

// Workflow
ok(w.automationsWorkflow === 1 && w.name && w.description && w.definition, 'workflow marker');
const d = w.definition;
ok(d.schemaVersion === 1 && d.startActivityId === 'start', 'schemaVersion and start');
const start = d.activities.find((x) => x.type === 'start');
ok(start && start.properties.webhookEnabled === false, 'webhook ships disabled');
const node = d.activities.find((x) => x.type === 'agent');
ok(node && node.properties.agentSlug === SLUG, 'node uses the agent');
ok(node && node.properties.model === '', 'node model blank');
ok(node && node.properties.autoApprove === false, 'node autoApprove false');
ok(node && JSON.stringify(node.properties.allowedExtensions) === JSON.stringify(EXT), 'allowedExtensions match');
ok(node && /\{\{ nodes\.start\.output\.startDate \}\}/.test(node.properties.goal) && /\{\{ nodes\.start\.output\.companyName \}\}/.test(node.properties.goal), 'goal binds nodes.start.output');
ok(!/\{\{\s*input\./.test(wfText), 'no input.* bindings');
for (const f of ['inputSchema', 'outputSchema', 'inputBindingsJson']) {
  try { JSON.parse(node.properties[f]); ok(true, `node ${f} JSON`); } catch (e) { ok(false, `node ${f} JSON: ${e.message}`); }
}
const ids = new Set(d.activities.map((x) => x.id));
ok(d.connections.every((c) => ids.has(c.source) && ids.has(c.target) && c.sourceHandle === null), 'connections resolve');

// Text style across the folder
for (const f of ['README.md', 'knowledge/autotask-time-entry-style-guide.md', 'src/prompt.md', `${SLUG}.agent.yml`, `${SLUG}.yml`]) {
  const t = fs.readFileSync(path.join(ROOT, f), 'utf8');
  ok(!DASH.test(t), `${f}: no en or em dashes`);
}
const readme = fs.readFileSync(path.join(ROOT, 'README.md'), 'utf8');
for (const q of ["Who's doing the work?", "What's the goal?", 'When should it check in?', 'How much can it do on its own?', 'Where does it keep notes?', 'Try a check-in now', '## Technical details', 'at_update_time_entry_notes']) {
  ok(readme.includes(q), `README has "${q}"`);
}
ok(readme.indexOf('## Technical details') > readme.indexOf('## Set it up'), 'Technical details after the setup');

// Generated files are current
try { execFileSync(process.execPath, [path.join(__dirname, 'build.js'), '--check'], { stdio: 'pipe' }); ok(true, 'build --check current'); }
catch (e) { ok(false, `build --check: ${String(e.stdout)}`); }

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
