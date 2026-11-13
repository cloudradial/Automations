// Static checks for the Client Health Pulsar files. Run: node client-health/src/test.js
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const yaml = require(process.env.JS_YAML_PATH || 'C:/Users/NicholasWestgate/OneDrive - Azurative/Documents/Claude/handoffs/src/node_modules/js-yaml');
const { PSAS, VERSION } = require('./build.js');

const ROOT = path.resolve(__dirname, '..');
const snap = JSON.parse(fs.readFileSync(path.join(__dirname, 'tools-snapshot.json'), 'utf8'));
let pass = 0, fail = 0;
const ok = (cond, msg) => { if (cond) { pass++; } else { fail++; console.log(`FAIL ${msg}`); } };
const DASH = /[\u2013\u2014]/;
const AAI96 = 'before each tool call, write one sentence';

// build is current
let current = true;
try { execFileSync(process.execPath, [path.join(__dirname, 'build.js'), '--check'], { stdio: 'pipe' }); } catch { current = false; }
ok(current, 'build.js --check: generated files are current');

for (const [key, p] of Object.entries(PSAS)) {
  const agentFile = path.join(ROOT, `client-health-${key}.agent.yml`);
  const wfFile = path.join(ROOT, `client-health-${key}.yml`);
  const at = fs.readFileSync(agentFile, 'utf8');
  const wt = fs.readFileSync(wfFile, 'utf8');
  const a = yaml.load(at), w = yaml.load(wt);

  // agent
  ok(a.automationsAgent === 1 && a.agent, `${key} agent: marker and wrapper`);
  const g = a.agent;
  ok(g.slug === `client-health-${key}`, `${key} agent: slug`);
  ok(g.version === VERSION, `${key} agent: version ${VERSION}`);
  ok(g.model === '', `${key} agent: model blank`);
  ok(g.dryRunDefault === true, `${key} agent: dryRunDefault true`);
  ok(g.systemPrompt.includes(AAI96), `${key} agent: AAI-96 sentence`);
  ok(!/\{\{PSA_/.test(g.systemPrompt), `${key} agent: every placeholder filled`);
  ok(JSON.stringify(g.requiredExtensionSlugs) === JSON.stringify([p.ext, 'cloudradial-v2-feedback']), `${key} agent: requiredExtensionSlugs`);
  for (const f of ['inputSchema', 'outputSchema', 'variablesJson']) {
    let parsed = true; try { JSON.parse(g[f]); } catch { parsed = false; }
    ok(parsed, `${key} agent: ${f} is JSON`);
  }
  ok(!DASH.test(at), `${key} agent: no en or em dashes`);

  // every tool named exists in the extensions it may use; writes are only the allowed ones
  const allowed = [p.ext, 'cloudradial-v2-feedback'];
  const known = new Set(allowed.flatMap((e) => [...snap[e].read, ...snap[e].write]));
  const writes = new Set(allowed.flatMap((e) => snap[e].write));
  const named = [...new Set(g.systemPrompt.match(/\b(?:cw|at|halo|cr)_[a-z_]+\b/g) || [])];
  ok(named.length > 0, `${key} agent: names tools`);
  for (const t of named) ok(known.has(t), `${key} agent: tool ${t} is in ${allowed.join(' or ')}`);
  const otherPrefixes = { connectwise: /\b(?:at|halo)_[a-z_]+/, autotask: /\b(?:cw|halo)_[a-z_]+/, halo: /\b(?:cw|at)_[a-z_]+/ }[key];
  ok(!otherPrefixes.test(g.systemPrompt), `${key} agent: no other PSA's tools`);
  const namedWrites = named.filter((t) => writes.has(t));
  ok(namedWrites.length >= 1, `${key} agent: proposes at least one write tool`);
  for (const t of named) {
    const isWrite = allowed.some((e) => snap[e].write.includes(t));
    if (/_(create|update|delete|close|add|set)_/.test(t + '_')) ok(isWrite, `${key} agent: ${t} looks like a write, so it must be an allowed proposal`);
  }

  // workflow
  ok(w.automationsWorkflow === 1 && w.name && w.description && w.definition, `${key} workflow: marker and top level`);
  const d = w.definition;
  ok(d.schemaVersion === 1 && d.startActivityId === 'start', `${key} workflow: schemaVersion and start`);
  const ids = d.activities.map((x) => x.id);
  ok(JSON.stringify(ids) === JSON.stringify(['start', 'node-request', 'node-agent', 'end']), `${key} workflow: steps`);
  ok(d.activities[0].properties.webhookEnabled === false, `${key} workflow: webhook disabled`);
  const ag = d.activities[2].properties;
  ok(ag.agentSlug === g.slug, `${key} workflow: agentSlug matches`);
  ok(ag.model === '', `${key} workflow: node model blank`);
  ok(ag.autoApprove === false, `${key} workflow: autoApprove false`);
  ok(JSON.stringify(ag.allowedExtensions) === JSON.stringify(allowed), `${key} workflow: allowedExtensions`);
  ok(typeof ag.goal === 'string' && ag.goal.length > 40, `${key} workflow: has a goal`);
  for (const f of ['inputBindingsJson', 'inputSchema', 'outputSchema']) {
    let parsed = true; try { JSON.parse(ag[f]); } catch { parsed = false; }
    ok(parsed, `${key} workflow: ${f} is JSON`);
  }
  ok(!/\{\{\s*input\./.test(wt), `${key} workflow: no {{ input.* }} bindings`);
  ok(/nodes\.node-request\.output\.request/.test(ag.inputBindingsJson), `${key} workflow: binds nodes.node-request`);
  ok(!DASH.test(wt), `${key} workflow: no en or em dashes`);
  ok(d.connections.every((c) => c.sourceHandle === null), `${key} workflow: connections`);
}

// the goal workflow step runs in strict mode (needs pwsh)
{
  const os = require("os");
  const wf = yaml.load(fs.readFileSync(path.join(ROOT, "client-health-connectwise.yml"), "utf8"));
  const step = path.join(os.tmpdir(), "client-health-step.ps1");
  fs.writeFileSync(step, wf.definition.activities[1].properties.script);
  let out = "", okStep = true;
  try { out = execFileSync("pwsh", ["-NoProfile", "-File", path.join(__dirname, "test-step.ps1"), step], { encoding: "utf8" }); } catch (e) { okStep = false; out = String(e.stdout || e.message); }
  console.log(out.trim());
  ok(okStep, "goal workflow step: strict-mode cases pass");
}

// README and knowledge
const readme = fs.readFileSync(path.join(ROOT, 'README.md'), 'utf8');
ok(!/TimeZest|Invarosoft|HappySat|\bHalo AI\b|usehalo/i.test(readme), 'README: no competitor names');
ok(!/KMCO|Westgate/i.test(readme), 'README: placeholder data only');
ok(readme.includes('## Technical details'), 'README: technical details section');
ok(!DASH.test(readme), 'README: no en or em dashes');
for (const f of fs.readdirSync(path.join(ROOT, 'knowledge'))) {
  const k = fs.readFileSync(path.join(ROOT, 'knowledge', f), 'utf8');
  ok(k.includes('Example, replace with your own'), `knowledge/${f}: example banner`);
  ok(!DASH.test(k), `knowledge/${f}: no en or em dashes`);
  ok(!/KMCO|Westgate/i.test(k), `knowledge/${f}: placeholder data only`);
}
for (const [key] of Object.entries(PSAS)) {
  for (const f of [`client-health-${key}.agent.yml`, `client-health-${key}.yml`]) ok(readme.includes(f), `README: links ${f}`);
}

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
