// Builds phishing-report-triage.yml from the step sources in this folder, then pastes the shared
// libraries into it (_shared/inject.js).
// Usage: node build.js          rewrite the .yml
//        node build.js --check  exit 1 if the .yml is out of date
// Edit parse.ps1, enrich.ps1, ticket.ps1 and the classify.*.txt prompts, never the .yml.
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
const out = path.join(here, '..', 'phishing-report-triage.yml');
const read = (f) => fs.readFileSync(path.join(here, f), 'utf8').replace(/\r\n/g, '\n').trimEnd();
const block = (text, indent) => text.split('\n').map((l) => (l ? indent + l : '')).join('\n');
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;

const testInput = JSON.stringify({
  reporter_upn: 'megan.bowen@contoso.com',
  message_id: '<phish-0001@contoso-payroll.example>',
  subject: '',
  sender: '',
  ticket_id: '',
  psa: '',
  company_name: 'Contoso',
  psa_company_id: '',
  company_tenant_id: '',
  psa_queue: '',
  confirm: false,
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
name: Phishing Report Triage
description: When a user reports a suspected phishing email, look it up in their mailbox, check its
  sender, links and attachments, classify the risk, and open or note a PSA ticket with the findings.
  A malicious verdict adds a draft search-and-purge for a technician. Nothing is ever purged automatically.
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
${psStep({ id: 'parse', name: 'Read the report', x: 280, script: read('parse.ps1'), test: testInput })}${psStep({ id: 'enrich', name: 'Look up the email', x: 460, script: read('enrich.ps1') })}  - id: classify
    name: Classify the risk
    type: ai-prompt
    position:
      x: 640
      y: 80
    properties:
      promptTemplate: |-
${block(read('classify.prompt.txt'), '        ')}
      systemMessage: |-
${block(read('classify.system.txt'), '        ')}
      maxTokens: 600
      outputKey: classification
      parameters: []
${psStep({
  id: 'ticket', name: 'Open or update the ticket', x: 820, script: read('ticket.ps1'),
  params: [
    ['enrichment', '{{ nodes.enrich.output.enrichment_json }}'],
    ['request', '{{ nodes.enrich.output.request_json }}'],
    ['rules', '{{ nodes.enrich.output.rules_json }}'],
    ['warnings_json', '{{ nodes.enrich.output.warnings_json }}'],
    ['classification', '{{ nodes.classify.output.classification }}'],
  ],
})}  - id: end
    name: End
    type: end
    position:
      x: 1000
      y: 80
  connections:
  - source: start
    target: parse
    sourceHandle: null
  - source: parse
    target: enrich
    sourceHandle: null
  - source: enrich
    target: classify
    sourceHandle: null
  - source: classify
    target: ticket
    sourceHandle: null
  - source: ticket
    target: end
    sourceHandle: null
  startActivityId: start
`;

const y = loadYaml();
const { text } = injectText(yml, 'phishing-report-triage.yml', new Map());
const doc = y.load(text);
// Guard rails: the shape every workflow must have.
if (doc.automationsWorkflow !== 1) throw new Error('automationsWorkflow marker missing');
const acts = doc.definition.activities;
if (acts.find((a) => a.id === 'start').properties.webhookEnabled !== false) throw new Error('webhook must ship disabled');
if (acts.some((a) => a.properties && 'model' in a.properties && a.properties.model)) throw new Error('model must be blank');
if (/\{\{\s*input\./.test(text)) throw new Error('use nodes.<id>.output bindings, never input.*');

const check = process.argv.includes('--check');
const was = fs.existsSync(out) ? fs.readFileSync(out, 'utf8').replace(/\r\n/g, '\n') : '';
if (text === was) { console.log('phishing-report-triage.yml: current'); process.exit(0); }
if (check) { console.log('phishing-report-triage.yml: OUT OF DATE (run node src/build.js)'); process.exit(1); }
fs.writeFileSync(out, text);
console.log('phishing-report-triage.yml: written');
