// Builds smart-acknowledgement.yml from the step sources in this folder, then pastes the shared libraries
// (_shared/psa.ps1, psa-tickets.ps1 and cloudradial.ps1) with _shared/inject.js.
// Usage: node build.js          rewrite the .yml
//        node build.js --check  exit 1 if the .yml is out of date
// Edit gather.ps1, send.ps1 and the judge.*.txt prompts, never the .yml.
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
const out = path.join(here, '..', 'smart-acknowledgement.yml');
const read = (f) => fs.readFileSync(path.join(here, f), 'utf8').replace(/\r\n/g, '\n').trimEnd();
const block = (text, indent) => text.split('\n').map((l) => (l ? indent + l : '')).join('\n');
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;

const testInput = JSON.stringify({ ticketId: '1001', psa: '', confirm: false, includeArticles: true }, null, 2);

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
name: Smart Acknowledgement
description: Acknowledges a new ticket with a short personal message to its contact, posted as a
  public note so the PSA emails it. States the ticket number and the response target only (the PSA's
  SLA response target, or the target for the ticket's priority), never a resolution time, and may add
  up to two of the company's own knowledge base articles. Writes nothing unless confirm is true.
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
${psStep({ id: 'gather', name: 'Read the ticket and plan the acknowledgement', x: 280, script: read('gather.ps1'), test: testInput })}  - id: judge
    name: Write the personal paragraph
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
      maxTokens: 500
      outputKey: judgment
      parameters: []
${psStep({
  id: 'send', name: 'Send the acknowledgement', x: 640, script: read('send.ps1'),
  params: [
    ['ctx', '{{ nodes.gather.output.ctx_json }}'],
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
    target: send
    sourceHandle: null
  - source: send
    target: end
    sourceHandle: null
  startActivityId: start
`;

const y = loadYaml();
const { text } = injectText(yml, 'smart-acknowledgement.yml', new Map());
const doc = y.load(text);
if (doc.automationsWorkflow !== 1) throw new Error('automationsWorkflow marker missing');
const acts = doc.definition.activities;
if (acts.find((a) => a.id === 'start').properties.webhookEnabled !== false) throw new Error('webhook must ship disabled');
if (acts.some((a) => a.properties && 'model' in a.properties && a.properties.model)) throw new Error('model must be blank');
if (/\{\{\s*input\./.test(text)) throw new Error('use nodes.<id>.output bindings, never input.*');
if (/[–—]/.test(text)) throw new Error('no en or em dashes');

const check = process.argv.includes('--check');
const was = fs.existsSync(out) ? fs.readFileSync(out, 'utf8').replace(/\r\n/g, '\n') : '';
if (text === was) { console.log('smart-acknowledgement.yml: current'); process.exit(0); }
if (check) { console.log('smart-acknowledgement.yml: OUT OF DATE (run node src/build.js)'); process.exit(1); }
fs.writeFileSync(out, text);
console.log('smart-acknowledgement.yml: written');
