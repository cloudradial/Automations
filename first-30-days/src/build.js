// Builds ../first-30-days-week-one.yml: one workflow that runs a new client's first week.
// It reuses the built steps of three sibling automations, so a fix there reaches this workflow on the next build:
//   cloudradial-ucp/set-up-new-company.yml         Read the setup (checks the portal setup input)
//   secure-score-assessment/secure-score-assessment.yml   Import Secure Score
//   license-reclamation/license-reclamation.yml    Read inputs, Find unused licences, Update Planner card
// plus this folder's own plan.ps1 (Read the client), portal.ps1 (Add portal content, no AI) and summary.ps1
// (Week-one summary). portal.ps1 gets the shared CloudRadial and company blocks from _shared/inject.js.
// Usage: node build.js          rewrite the .yml
//        node build.js --check  exit 1 if the .yml is out of date (also when a sibling .yml changed)
// Edit the sources (here or in the sibling's src/), never the .yml.
// Needs js-yaml: npm install in ../../_shared, or set JS_YAML_PATH to an existing copy.
const fs = require('fs');
const path = require('path');
const { injectText } = require(path.join(__dirname, '..', '..', '_shared', 'inject.js'));
let y;
try { y = require('js-yaml'); } catch {
  try { y = require(path.join(__dirname, '..', '..', '_shared', 'node_modules', 'js-yaml')); } catch { y = require(process.env.JS_YAML_PATH); }
}

const root = path.join(__dirname, '..', '..');
const target = path.join(__dirname, '..', 'first-30-days-week-one.yml');
const read = (f) => fs.readFileSync(path.join(__dirname, f), 'utf8').replace(/\r\n/g, '\n').trimEnd() + '\n';
const sibling = (rel) => y.load(fs.readFileSync(path.join(root, rel), 'utf8').replace(/\r\n/g, '\n'));
const nodeOf = (wf, id) => {
  const a = wf.definition.activities.find((x) => x.id === id);
  if (!a) throw new Error(`${wf.name}: no step ${id}`);
  return JSON.parse(JSON.stringify(a));
};

const setupWf = sibling('cloudradial-ucp/set-up-new-company.yml');
const scoreWf = sibling('secure-score-assessment/secure-score-assessment.yml');
const lrWf = sibling('license-reclamation/license-reclamation.yml');

// A step parameter bound to one field of Read the client's output.
const fromPlan = (name, field = name) => ({ name, expression: `{{ nodes.node-plan.output.${field} }}` });
let x = 100;
const at = () => { const p = { x, y: 120 }; x += 220; return p; };
// Copies a sibling step under a new id and name, with new parameters, and no test input of its own.
const reuse = (wf, id, newId, name, parameters) => {
  const a = nodeOf(wf, id);
  a.id = newId; a.name = name; a.position = at();
  delete a.properties.testInput;
  if (parameters) a.properties.parameters = parameters;
  return a;
};

const testInput = {
  company: 'Contoso Ltd',
  company_id: 7,
  mode: 'preview',
  days: 30,
  client_visible: true,
  users: [{ firstName: 'Pat', lastName: 'Lee', email: 'pat.lee@contoso.com' }],
  tokens: [{ token: 'SupportPhone', value: '555-0100' }],
  requestForms: [{ subject: 'Request a new laptop', category: 'Hardware', description: 'Tell us who the laptop is for and when they start.' }],
  menuTiles: [{ name: 'Remote Support', url: 'https://support.examplemsp.com', category: 'Help' }],
};

const start = { id: 'start', name: 'Start', type: 'start', position: at(), properties: { webhookEnabled: false } };
const plan = {
  id: 'node-plan', name: 'Read the client', type: 'powershell-script', position: at(),
  properties: { script: read('plan.ps1'), timeoutSeconds: 60, retryCount: 0, parameters: [], aiExtensions: [], testInput: JSON.stringify(testInput, null, 2) },
};
// Unbound, so it reads Read the client's output: company_id plus the setup fields.
const setupInputs = reuse(setupWf, 'node-inputs', 'node-setup-inputs', 'Check the portal setup');
// Fixed rules, so no agent: duplicate checks, then creates in live mode only. includeAllCompanies lets it
// switch to the client's CloudRadial secrets (_shared/company.ps1); import keeps it.
const portal = {
  id: 'node-portal', name: 'Add portal content', type: 'powershell-script', position: at(),
  properties: {
    script: read('portal.ps1'), timeoutSeconds: 600, retryCount: 0, aiExtensions: [], includeAllCompanies: true,
    parameters: [
      { name: 'plan', expression: '{{ nodes.node-plan.output }}' },
      { name: 'setup', expression: '{{ nodes.node-setup-inputs.output }}' },
    ],
  },
};
const score = reuse(scoreWf, 'node-secure-score', 'node-score', 'Secure Score assessment',
  [fromPlan('company'), fromPlan('companyId', 'company_id'), fromPlan('mode', 'scoreMode')]);
const lrInputs = reuse(lrWf, 'node-inputs', 'node-lr-inputs', 'Licence check settings',
  [fromPlan('company'), fromPlan('company_id'), fromPlan('days'), fromPlan('preview'), fromPlan('client_visible')]);
const lrScan = reuse(lrWf, 'node-scan', 'node-lr-scan', 'Find unused licences');
const lrCard = reuse(lrWf, 'node-card', 'node-lr-card', 'Licence card for the client');
const summary = {
  id: 'node-summary', name: 'Week-one summary', type: 'powershell-script', position: at(),
  properties: {
    script: read('summary.ps1'), timeoutSeconds: 60, retryCount: 0, aiExtensions: [],
    parameters: [
      { name: 'plan', expression: '{{ nodes.node-plan.output }}' },
      { name: 'setup', expression: '{{ nodes.node-portal.output }}' },
      { name: 'score', expression: '{{ nodes.node-score.output }}' },
      { name: 'card', expression: '{{ nodes.node-lr-card.output }}' },
    ],
  },
};
const end = { id: 'end', name: 'End', type: 'end', position: at() };

const chain = [start, plan, setupInputs, portal, score, lrInputs, lrScan, lrCard, summary, end];
const wf = {
  automationsWorkflow: 1,
  name: 'First 30 Days: Week One',
  description:
    "Runs a new client's first week in one go: adds their starter portal content (users, tokens, request forms, menu tiles) " +
    'with duplicate checks, turns their Microsoft Secure Score into a portal assessment, and puts a card about unused Microsoft 365 ' +
    'licences on their Planner board, then sums it all up. Preview by default. Send ' +
    '{"company":"Contoso Ltd","company_id":7,"mode":"preview","users":[...]}.',
  definition: {
    schemaVersion: 1,
    activities: chain,
    connections: chain.slice(1).map((a, i) => ({ source: chain[i].id, target: a.id, sourceHandle: null })),
    startActivityId: 'start',
  },
};

// Every {{ nodes.<id>... }} binding must point at an earlier step.
const ids = chain.map((a) => a.id);
chain.forEach((a, i) => {
  const text = JSON.stringify(a.properties || {}).replace(/"script":"(?:[^"\\]|\\.)*"/g, '');
  for (const m of text.matchAll(/nodes\.([a-z0-9-]+)\./g)) {
    const j = ids.indexOf(m[1]);
    if (j < 0 || j >= i) throw new Error(`${a.id} binds to ${m[1]}, which isn't an earlier step`);
  }
});

const header = [
  '# Generated by src/build.js from src/*.ps1 and the built steps of cloudradial-ucp, secure-score-assessment and',
  '# license-reclamation. Edit those sources, not this file.',
  '# CloudRadial AutomationAI - First 30 Days: Week One. No agent needed: every step is PowerShell.',
  '# After import: Read the client is the first step and stays unbound; it reads the Run input.',
].join('\n');
const { text } = injectText(header + '\n' + y.dump(wf, { lineWidth: -1, noRefs: true }), 'first-30-days-week-one.yml', new Map());
const back = y.load(text);
JSON.parse(back.definition.activities.find((a) => a.id === 'node-plan').properties.testInput);
if (back.definition.activities[0].properties.webhookEnabled !== false) throw new Error('webhook must ship off');
for (const a of back.definition.activities) {
  const s = a.properties && a.properties.script;
  if (s && /# >>> _shared\/\S+\n\s*# <<< _shared/.test(s)) throw new Error(`${a.id}: a shared block is empty`);
}

const was = fs.existsSync(target) ? fs.readFileSync(target, 'utf8').replace(/\r\n/g, '\n') : '';
if (text === was) { console.log('first-30-days-week-one.yml: current'); process.exit(0); }
if (process.argv.includes('--check')) { console.log('first-30-days-week-one.yml: OUT OF DATE (run node src/build.js)'); process.exit(1); }
fs.writeFileSync(target, text);
console.log(`first-30-days-week-one.yml: written (${text.length} bytes)`);
