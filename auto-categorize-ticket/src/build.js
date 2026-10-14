// Builds auto-categorize-ticket.yml from the step sources in this folder: pastes src/psa-categories.ps1
// where a step says "# @@ src/psa-categories.ps1 @@", then the shared _shared/psa.ps1 with _shared/inject.js.
// Usage: node build.js          rewrite the .yml
//        node build.js --check  exit 1 if the .yml is out of date
// Edit gather.ps1, write.ps1, psa-categories.ps1 and the judge.*.txt prompts, never the .yml.
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
const out = path.join(here, '..', 'auto-categorize-ticket.yml');
const read = (f) => fs.readFileSync(path.join(here, f), 'utf8').replace(/\r\n/g, '\n').trimEnd();
const block = (text, indent) => text.split('\n').map((l) => (l ? indent + l : '')).join('\n');
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
const CAT = '# @@ src/psa-categories.ps1 @@';
const step = (f) => {
  const s = read(f);
  if (s.split(CAT).length !== 2) throw new Error(`${f}: expected one "${CAT}" line`);
  // A function, so "$'" and "$&" in the PowerShell aren't read as replacement patterns.
  return s.replace(CAT, () => read('psa-categories.ps1'));
};

const testInput = JSON.stringify({
  ticketId: '1001',
  psa: '',
  confirm: false,
  minConfidence: 0.7,
  addNote: true,
}, null, 2);

function psStep({ id, name, x, script, params, test }) {
  let s = `  - id: ${id}
    name: ${name}
    type: powershell-script
    position:
      x: ${x}
      y: 80
    properties:
      script: |-
${block(script, '        ')}
      timeoutSeconds: 300
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
name: Auto-Categorize New Ticket
description: Reads a new ticket and fills in its blank category fields from the PSA's own list
  (ConnectWise type, subtype and item; Autotask issue and sub-issue type; and the matching fields in
  HaloPSA, Kaseya BMS, Syncro and Zendesk), with one AI call choosing from the allowed values. Never
  changes a field a technician set or the board. Writes nothing unless confirm is true; with low
  confidence it adds an internal note with the suggestion instead.
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
      # Enable the webhook in Properties after import; AutomationAI issues the URL and secret.
      webhookEnabled: false
${psStep({ id: 'gather', name: 'Read the ticket and its categories', x: 280, script: step('gather.ps1'), test: testInput })}  - id: judge
    name: Pick the category
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
      maxTokens: 400
      outputKey: judgment
      parameters: []
${psStep({
  id: 'write', name: 'Set the category and note it', x: 640, script: step('write.ps1'),
  params: [
    ['request', '{{ nodes.gather.output.request_json }}'],
    ['state', '{{ nodes.gather.output.state_json }}'],
    ['warnings_json', '{{ nodes.gather.output.warnings_json }}'],
    ['actions_json', '{{ nodes.gather.output.actions_json }}'],
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
    target: gather
    sourceHandle: null
  - source: gather
    target: judge
    sourceHandle: null
  - source: judge
    target: write
    sourceHandle: null
  - source: write
    target: end
    sourceHandle: null
  startActivityId: start
`;

const y = loadYaml();
const { text } = injectText(yml, 'auto-categorize-ticket.yml', new Map());
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
if (text === was) { console.log('auto-categorize-ticket.yml: current'); process.exit(0); }
if (check) { console.log('auto-categorize-ticket.yml: OUT OF DATE (run node src/build.js)'); process.exit(1); }
fs.writeFileSync(out, text);
console.log('auto-categorize-ticket.yml: written');
