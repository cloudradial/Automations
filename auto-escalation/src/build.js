// Builds auto-escalation.yml from the step sources in this folder, then pastes the shared libraries
// (_shared/psa.ps1, psa-tickets.ps1 and postmark.ps1) between their markers with _shared/inject.js.
// Usage: node build.js          rewrite the .yml
//        node build.js --check  exit 1 if the .yml is out of date
// Edit find.ps1, reassign.ps1, notify.ps1 and note.ps1, never the .yml.
// Needs js-yaml: set JS_YAML_PATH (or NODE_PATH) to an existing copy, or npm install in _shared.
const fs = require('fs');
const path = require('path');
const { injectText } = require('../../_shared/inject.js');

function loadYaml() {
  try { return require('js-yaml'); } catch { /* fall through */ }
  if (process.env.JS_YAML_PATH) return require(process.env.JS_YAML_PATH);
  throw new Error('js-yaml not found. Set JS_YAML_PATH, or npm install in _shared.');
}

const here = __dirname;
const name = 'auto-escalation.yml';
const out = path.join(here, '..', name);
const read = (f) => fs.readFileSync(path.join(here, f), 'utf8').replace(/\r\n/g, '\n').trimEnd();
const block = (text, indent) => text.split('\n').map((l) => (l ? indent + l : '')).join('\n');

// Placeholder test input: a preview run. A Routine sends no input and runs live with the defaults.
const testInput = JSON.stringify({
  preview: true,
  max_tickets: 10,
  minutes_untouched_by_priority: { critical: 15, high: 60, medium: 240, low: 480 },
  sla_risk_percent: 80,
  escalation_map: { 'Service Desk': { queue: 'Tier 2' }, 'Tier 2': { queue: 'Tier 3' } },
  dispatcher_email: 'dispatch@example.com',
  skip_statuses: 'waiting,pending,on hold,scheduled',
  company: '',
  psa: '',
}, null, 2);

function psStep({ id, name: stepName, x, script, test }) {
  let s = `  - id: ${id}
    name: ${stepName}
    type: powershell-script
    position:
      x: ${x}
      y: 80
    properties:
      script: |-
${block(script, '        ')}
      timeoutSeconds: 300
      retryCount: 0
      parameters: []
      aiExtensions: []
`;
  if (test) s += `      testInput: |-\n${block(test, '        ')}\n`;
  return s;
}

const yml = `automationsWorkflow: 1
name: Auto-Escalation
description: Every 15 minutes, finds open tickets nobody has touched for too long for their priority, or whose SLA is at
  risk, adds an internal note with the reason, moves each one up one tier using the escalation map and emails the
  dispatcher through Postmark. A ticket is escalated once, and a retried run never moves or emails it twice. Set preview to true to see the plan without changing anything.
definition:
  schemaVersion: 1
  activities:
  - id: start
    name: Start
    type: start
    position:
      x: 100
      y: 80
    properties:
      # Runs on a Routine (every 15 minutes) or manually. Attach the Routine after import; no webhook is needed.
      webhookEnabled: false
${psStep({ id: 'find', name: 'Find at-risk tickets', x: 280, script: read('find.ps1'), test: testInput })}${psStep({ id: 'reassign', name: 'Mark and reassign up a tier', x: 460, script: read('reassign.ps1') })}${psStep({ id: 'notify', name: 'Notify the dispatcher', x: 640, script: read('notify.ps1') })}${psStep({ id: 'note', name: 'Follow-up note and summary', x: 820, script: read('note.ps1') })}  - id: end
    name: End
    type: end
    position:
      x: 1000
      y: 80
  connections:
  - source: start
    target: find
    sourceHandle: null
  - source: find
    target: reassign
    sourceHandle: null
  - source: reassign
    target: notify
    sourceHandle: null
  - source: notify
    target: note
    sourceHandle: null
  - source: note
    target: end
    sourceHandle: null
  startActivityId: start
`;

const y = loadYaml();
const { text } = injectText(yml, name, new Map());
const doc = y.load(text);
// Guard rails: the shape every workflow must have.
if (doc.automationsWorkflow !== 1) throw new Error('automationsWorkflow marker missing');
const acts = doc.definition.activities;
if (acts.find((a) => a.id === 'start').properties.webhookEnabled !== false) throw new Error('webhook must ship disabled');
if (acts.some((a) => a.properties && 'model' in a.properties && a.properties.model)) throw new Error('model must be blank');
if (/\{\{\s*input\./.test(text)) throw new Error('use nodes.<id>.output bindings, never input.*');
if (text.includes(String.fromCharCode(0x2014))) throw new Error('no em dashes');
const scripts = Object.fromEntries(acts.filter((a) => a.type === 'powershell-script').map((a) => [a.id, a.properties.script]));
const needs = { find: ['Connect-Psa', 'Find-PsaTickets'], reassign: ['Connect-Psa', 'Set-PsaQueue', 'Test-PmConfigured'], notify: ['Send-PmMail'], note: ['Connect-Psa'] };
for (const [id, fns] of Object.entries(needs)) {
  for (const fn of fns) if (!scripts[id].includes(`function ${fn}`)) throw new Error(`${id}: function ${fn} was not injected`);
}

const check = process.argv.includes('--check');
const was = fs.existsSync(out) ? fs.readFileSync(out, 'utf8').replace(/\r\n/g, '\n') : '';
if (text === was) { console.log(`${name}: current`); process.exit(0); }
if (check) { console.log(`${name}: OUT OF DATE (run node src/build.js)`); process.exit(1); }
fs.writeFileSync(out, text);
console.log(`${name}: written`);
