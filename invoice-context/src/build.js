// Builds invoice-context.yml from the step sources in this folder, then pastes the shared libraries
// (_shared/psa.ps1 and, in the first step, psa-tickets.ps1) with _shared/inject.js.
// Usage: node build.js          rewrite the .yml
//        node build.js --check  exit 1 if the .yml is out of date
// Edit gather.ps1, note.ps1 and the summarize.*.txt prompts, never the .yml.
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
const out = path.join(here, '..', 'invoice-context.yml');
const read = (f) => fs.readFileSync(path.join(here, f), 'utf8').replace(/\r\n/g, '\n').trimEnd();
const block = (text, indent) => text.split('\n').map((l) => (l ? indent + l : '')).join('\n');
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;

const step = (f) => read(f);

const testInput = JSON.stringify({
  ticketId: '1001',
  companyName: 'Contoso',
  invoiceNumber: '',
  period: '2026-09',
  addNote: false,
  triggerSource: 'manual',
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
name: Invoice Context Gathering
description: For an invoice question or dispute ticket, reads the company's tickets, time entries
  and agreements for the billing period (from the period input or the invoice), adds them up without
  AI, and posts one internal note with a short neutral AI summary for the account manager. Read-only
  apart from that note.
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
${psStep({ id: 'gather', name: 'Collect billing records', x: 280, script: step('gather.ps1'), test: testInput })}  - id: summarize
    name: Summarize for the account manager
    type: ai-prompt
    position:
      x: 460
      y: 80
    properties:
      model: ''
      promptTemplate: |-
${block(read('summarize.prompt.txt'), '        ')}
      systemMessage: |-
${block(read('summarize.system.txt'), '        ')}
      maxTokens: 600
      outputKey: summary
      parameters: []
${psStep({
  id: 'note', name: 'Post the internal note', x: 640, script: step('note.ps1'),
  params: [
    ['request', '{{ nodes.gather.output.request_json }}'],
    ['figures', '{{ nodes.gather.output.figures_json }}'],
    ['warnings_json', '{{ nodes.gather.output.warnings_json }}'],
    ['actions_json', '{{ nodes.gather.output.actions_json }}'],
    ['summary', '{{ nodes.summarize.output.summary }}'],
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
    target: summarize
    sourceHandle: null
  - source: summarize
    target: note
    sourceHandle: null
  - source: note
    target: end
    sourceHandle: null
  startActivityId: start
`;

const y = loadYaml();
const { text } = injectText(yml, 'invoice-context.yml', new Map());
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
if (text === was) { console.log('invoice-context.yml: current'); process.exit(0); }
if (check) { console.log('invoice-context.yml: OUT OF DATE (run node src/build.js)'); process.exit(1); }
fs.writeFileSync(out, text);
console.log('invoice-context.yml: written');
