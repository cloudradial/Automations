// Builds sla-breach-report.yml from the step sources in this folder, then pastes the shared libraries
// (_shared/psa.ps1, psa-tickets.ps1 and postmark.ps1) with _shared/inject.js.
// Usage: node build.js          rewrite the .yml
//        node build.js --check  exit 1 if the .yml is out of date
// Edit find.ps1 and send.ps1, never the .yml.
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
const name = 'sla-breach-report.yml';
const out = path.join(here, '..', name);
const read = (f) => fs.readFileSync(path.join(here, f), 'utf8').replace(/\r\n/g, '\n').trimEnd();
const block = (text, indent) => text.split('\n').map((l) => (l ? indent + l : '')).join('\n');

// Placeholder test input. A Routine sends no input, and every field here is the default.
const testInput = JSON.stringify({
  to: 'service.manager@example.com',
  near_breach_percent: 80,
  sla_hours_by_priority: { critical: 4, high: 8, medium: 24, low: 72 },
  use_psa_sla: true,
  skip_statuses: 'waiting,pending,on hold,scheduled',
  max_tickets: 500,
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
      timeoutSeconds: 600
      retryCount: 0
      parameters: []
      aiExtensions: []
`;
  if (test) s += `      testInput: |-\n${block(test, '        ')}\n`;
  return s;
}

const yml = `automationsWorkflow: 1
name: SLA Breach Report
description: Weekly report of open tickets that have breached their SLA or are close to it, using the PSA's own SLA
  dates where it has them and default hours by priority otherwise. Emailed to the service manager through Postmark,
  grouped by company and technician. Report only; it never changes a ticket.
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
      # Runs on a Routine (weekly) or manually. Attach the Routine after import; no webhook is needed.
      webhookEnabled: false
${psStep({ id: 'find', name: 'List breached and near-breach tickets', x: 280, script: read('find.ps1'), test: testInput })}${psStep({ id: 'send', name: 'Email the service manager', x: 460, script: read('send.ps1') })}  - id: end
    name: End
    type: end
    position:
      x: 640
      y: 80
  connections:
  - source: start
    target: find
    sourceHandle: null
  - source: find
    target: send
    sourceHandle: null
  - source: send
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
if (!text.includes('function Find-PsaTickets')) throw new Error('_shared/psa-tickets.ps1 was not injected');
if (!text.includes('function Send-PmMail')) throw new Error('_shared/postmark.ps1 was not injected');

const check = process.argv.includes('--check');
const was = fs.existsSync(out) ? fs.readFileSync(out, 'utf8').replace(/\r\n/g, '\n') : '';
if (text === was) { console.log(`${name}: current`); process.exit(0); }
if (check) { console.log(`${name}: OUT OF DATE (run node src/build.js)`); process.exit(1); }
fs.writeFileSync(out, text);
console.log(`${name}: written`);
