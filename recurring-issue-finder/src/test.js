// Checks the generated Recurring Issue Finder files.
//   node recurring-issue-finder/src/test.js
// js-yaml: set JS_YAML_PATH, or it is looked up in node_modules and the handoffs copy.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { outputs, VERSION, SLUG, ROOT } = require('./build');
const PSAS = require('./psa');
const TOOLS = require('./tools.json');

function loadYaml() {
  const tries = [process.env.JS_YAML_PATH, 'js-yaml',
    'C:/Users/NicholasWestgate/OneDrive - Azurative/Documents/Claude/handoffs/src/node_modules/js-yaml'].filter(Boolean);
  for (const t of tries) { try { return require(t); } catch (e) { /* next */ } }
  throw new Error('js-yaml not found: set JS_YAML_PATH');
}
const yaml = loadYaml();

let pass = 0; let fail = 0;
const check = (name, ok, extra) => { if (ok) { pass++; } else { fail++; console.log('FAIL ' + name + (extra ? ': ' + extra : '')); } };
const DASH = /[\u2013\u2014]/;
const AAI96 = 'before each tool call, write one sentence';

const files = outputs();
for (const [key, p] of Object.entries(PSAS)) {
  const aName = `${SLUG}-${key}.agent.yml`;
  const wName = `${SLUG}-${key}.yml`;
  const onDisk = (n) => fs.readFileSync(path.join(ROOT, n), 'utf8');
  check(`${aName} current`, onDisk(aName) === files[aName]);
  check(`${wName} current`, onDisk(wName) === files[wName]);

  // Agent
  const a = yaml.load(onDisk(aName));
  check(`${aName} marker`, a.automationsAgent === 1 && a.agent);
  const ag = a.agent;
  check(`${aName} slug`, ag.slug === `${SLUG}-${key}`);
  check(`${aName} version`, ag.version === VERSION);
  check(`${aName} model blank`, ag.model === '');
  check(`${aName} dryRunDefault`, ag.dryRunDefault === true);
  check(`${aName} one extension`, JSON.stringify(ag.requiredExtensionSlugs) === JSON.stringify([p.extension]));
  check(`${aName} AAI-96 sentence`, ag.systemPrompt.includes(AAI96) && ag.systemPrompt.includes('Never send a message that is empty'));
  for (const f of ['variablesJson', 'inputSchema', 'outputSchema']) {
    let ok = true; try { JSON.parse(ag[f]); } catch (e) { ok = false; }
    check(`${aName} ${f} is JSON`, ok);
  }
  check(`${aName} no placeholders left`, !/\{\{[A-Z_]+\}\}/.test(ag.systemPrompt));

  // Every tool the prompt names exists in this PSA's snapshot; writes are only the allowed ones.
  const known = TOOLS[p.extension];
  const named = [...new Set(ag.systemPrompt.match(/\b(cw|at|halo)_[a-z_]+\b/g) || [])];
  check(`${aName} names tools`, named.length >= 4, named.join(','));
  for (const t of named) check(`${aName} tool ${t} exists in ${p.extension}`, Object.prototype.hasOwnProperty.call(known, t));
  const writes = named.filter((t) => known[t] === 'write');
  check(`${aName} writes are only ${p.writeTools}`, JSON.stringify(writes.sort()) === JSON.stringify([...p.writeTools].sort()), writes.join(','));
  check(`${aName} no other PSA tools`, !named.some((t) => !t.startsWith({ connectwise: 'cw_', autotask: 'at_', halo: 'halo_' }[key])));

  // Workflow
  const w = yaml.load(onDisk(wName));
  check(`${wName} marker`, w.automationsWorkflow === 1 && w.definition && w.definition.schemaVersion === 1);
  const acts = w.definition.activities;
  const start = acts.find((x) => x.type === 'start');
  check(`${wName} webhook off`, start.properties.webhookEnabled === false);
  const ag2 = acts.find((x) => x.type === 'agent');
  check(`${wName} agent slug`, ag2.properties.agentSlug === ag.slug);
  check(`${wName} agent model blank`, ag2.properties.model === '');
  check(`${wName} autoApprove false`, ag2.properties.autoApprove === false);
  check(`${wName} allowedExtensions`, JSON.stringify(ag2.properties.allowedExtensions) === JSON.stringify([p.extension]));
  check(`${wName} has a goal`, typeof ag2.properties.goal === 'string' && ag2.properties.goal.length > 100);
  check(`${wName} binds nodes.*`, ag2.properties.inputBindingsJson.includes('{{ nodes.node-settings.output.request }}') && !/\{\{\s*input\./.test(onDisk(wName)));
  for (const f of ['inputBindingsJson', 'inputSchema', 'outputSchema']) {
    let ok = true; try { JSON.parse(ag2.properties[f]); } catch (e) { ok = false; }
    check(`${wName} ${f} is JSON`, ok);
  }
  const ids = new Set(acts.map((x) => x.id));
  check(`${wName} connections resolve`, w.definition.connections.every((c) => ids.has(c.source) && ids.has(c.target)));
  check(`${wName} first step unbound`, !acts.find((x) => x.id === 'node-settings').properties.script.includes('{{'));

  for (const n of [aName, wName]) check(`${n} no en or em dashes`, !DASH.test(onDisk(n)));
}

// Knowledge templates and README
const kdir = path.join(ROOT, 'knowledge');
const kfiles = fs.readdirSync(kdir).filter((f) => f.endsWith('.md'));
check('two knowledge templates', kfiles.length === 2, kfiles.join(','));
for (const f of kfiles) {
  const t = fs.readFileSync(path.join(kdir, f), 'utf8');
  check(`${f} has the example banner`, /Example, replace with your own/.test(t));
  check(`${f} no dashes`, !DASH.test(t));
}
const readme = fs.readFileSync(path.join(ROOT, 'README.md'), 'utf8');
check('README no dashes', !DASH.test(readme));
check('README has technical details', readme.includes('\n## Technical details'));
check('README names no competitor', !/timezest|invarosoft|halo ai|halo platform/i.test(readme));
check('README no real client names', !/kmco|westgate/i.test(readme));
for (const s of ['Who\'s doing the work?', 'What\'s the goal?', 'When should it check in?', 'How much can it do on its own?', 'Where does it keep notes?', 'Try a check-in now']) {
  check(`README setup covers "${s}"`, readme.includes(s));
}
check('prompt and psa sources have no dashes', !DASH.test(fs.readFileSync(path.join(__dirname, 'prompt.md'), 'utf8') + fs.readFileSync(path.join(__dirname, 'psa.js'), 'utf8')));

// Settings step in strict mode, when pwsh is available.
try {
  const out = execFileSync('pwsh', ['-NoProfile', '-File', path.join(__dirname, 'test-settings.ps1')], { encoding: 'utf8' });
  const m = out.match(/(\d+) passed, (\d+) failed/);
  check('settings.ps1 strict-mode harness', m && m[2] === '0', out.trim().split('\n').pop());
  if (m) pass += Number(m[1]);
} catch (e) {
  if (e.code === 'ENOENT') console.log('SKIP settings harness: pwsh not found');
  else check('settings.ps1 strict-mode harness', false, (e.stdout || '') + (e.stderr || ''));
}

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
