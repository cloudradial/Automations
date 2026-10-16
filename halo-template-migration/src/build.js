// Builds halo-template-migration.yml from the step sources in this folder, then pastes the shared
// _shared/psa.ps1 and _shared/cloudradial.ps1 with _shared/inject.js.
// Usage: node build.js          rewrite the .yml
//        node build.js --check  exit 1 if the .yml is out of date
// Edit read.ps1, create.ps1 and the judge.*.txt prompts, never the .yml.
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
const out = path.join(here, '..', 'halo-template-migration.yml');
const read = (f) => fs.readFileSync(path.join(here, f), 'utf8').replace(/\r\n/g, '\n').trimEnd();
const block = (text, indent) => text.split('\n').map((l) => (l ? indent + l : '')).join('\n');
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;

const testInput = JSON.stringify({
  companyId: 1,
  confirm: false,
  templateIds: [],
  search: '',
  maxTemplates: 10,
  usage: 'auto',
  category: '',
  sendToPsa: true,
}, null, 2);

function psStep({ id, name, x, script, params, test, timeout }) {
  let s = `  - id: ${id}
    name: ${name}
    type: powershell-script
    position:
      x: ${x}
      y: 80
    properties:
      script: |-
${block(script, '        ')}
      timeoutSeconds: ${timeout || 600}
      retryCount: 0
`;
  if (params && params.length) {
    s += '      parameters:\n' + params.map(([n, e]) => `      - name: ${n}\n        expression: ${q(e)}\n`).join('');
  } else {
    s += '      parameters: []\n';
  }
  s += '      aiExtensions: []\n';
  if (test) s += `      testInput: |-\n${block(test, '        ')}\n`;
  return s;
}

const yml = `automationsWorkflow: 1
name: Move HaloPSA Ticket Templates into CloudRadial Request Forms
description: Turns each HaloPSA ticket template into a CloudRadial Service Request or Problem Report
  form in the company you choose, keeping the template's ticket type, priority, category and team, with
  one AI call choosing which custom fields a requester answers and how to word them. Never writes to
  Halo and never changes an existing form. Creates nothing unless confirm is true. Reruns skip
  templates already moved, so it can move a large set in batches.
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
      webhookEnabled: false
${psStep({ id: 'read', name: 'Read the Halo templates', x: 280, script: read('read.ps1'), test: testInput })}  - id: judge
    name: Draft the forms
    type: ai-prompt
    position:
      x: 460
      y: 80
    properties:
      model: ''
      promptTemplate: |-
${block(read('judge.prompt.txt'), '        ')}
      systemMessage: |-
${block(read('judge.system.txt'), '        ')}
      maxTokens: 6000
      outputKey: judgment
      parameters: []
${psStep({
  id: 'create', name: 'Create the forms', x: 640, script: read('create.ps1'), timeout: 300,
  params: [
    ['request', '{{ nodes.read.output.request_json }}'],
    ['plan', '{{ nodes.read.output.plan_json }}'],
    ['skipped', '{{ nodes.read.output.skipped_json }}'],
    ['remaining', '{{ nodes.read.output.remaining }}'],
    ['warnings_json', '{{ nodes.read.output.warnings_json }}'],
    ['actions_json', '{{ nodes.read.output.actions_json }}'],
    ['judgment', '{{ nodes.judge.output.judgment }}'],
  ],
})}  - id: end
    name: End
    type: end
    position:
      x: 820
      y: 80
  connections:
  - source: start
    target: read
    sourceHandle: null
  - source: read
    target: judge
    sourceHandle: null
  - source: judge
    target: create
    sourceHandle: null
  - source: create
    target: end
    sourceHandle: null
  startActivityId: start
`;

const y = loadYaml();
const { text } = injectText(yml, 'halo-template-migration.yml', new Map());
const doc = y.load(text);
// Guard rails: the shape every workflow must have.
if (doc.automationsWorkflow !== 1) throw new Error('automationsWorkflow marker missing');
const acts = doc.definition.activities;
if (acts.find((a) => a.id === 'start').properties.webhookEnabled !== false) throw new Error('webhook must ship disabled');
if (acts.some((a) => a.properties && 'model' in a.properties && a.properties.model)) throw new Error('model must be blank');
if (/\{\{\s*input\./.test(text)) throw new Error('use nodes.<id>.output bindings, never input.*');
if (/[–—]/.test(text)) throw new Error('no en or em dashes');

const check = process.argv.includes('--check');
const was = fs.existsSync(out) ? fs.readFileSync(out, 'utf8').replace(/\r\n/g, '\n') : '';
if (text === was) { console.log('halo-template-migration.yml: current'); process.exit(0); }
if (check) { console.log('halo-template-migration.yml: OUT OF DATE (run node src/build.js)'); process.exit(1); }
fs.writeFileSync(out, text);
console.log('halo-template-migration.yml: written');
