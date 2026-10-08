// Builds troubleshooting-article-delivery.yml from the step sources in this folder, then pastes the shared
// libraries (automationai/_shared/inject.js).
// Usage: node build.js          rewrite the .yml
//        node build.js --check  exit 1 if the .yml is out of date
// Edit parse.ps1, check.ps1 and act.ps1 (or the _shared libraries), never the .yml.
// Needs js-yaml: set JS_YAML_PATH (or NODE_PATH) to an existing copy, or npm install in automationai/_shared.
const fs = require('fs');
const path = require('path');
const { injectText } = require('../../_shared/inject.js');

function loadYaml() {
  try { return require('js-yaml'); } catch { /* fall through */ }
  if (process.env.JS_YAML_PATH) return require(process.env.JS_YAML_PATH);
  throw new Error('js-yaml not found. Set JS_YAML_PATH, or npm install in automationai/_shared.');
}

const here = __dirname;
const name = 'troubleshooting-article-delivery.yml';
const out = path.join(here, '..', name);
const read = (f) => fs.readFileSync(path.join(here, f), 'utf8').replace(/\r\n/g, '\n').trimEnd();
const block = (text, indent) => text.split('\n').map((l) => (l ? indent + l : '')).join('\n');

// Placeholder test input: a dry run of the send entry point (dry_run true writes nothing).
const testInput = JSON.stringify({
  mode: 'send',
  ticketId: '12345',
  contactEmail: 'megan.bowen@contoso.com',
  articleTitle: 'Fix Outlook not opening',
  articleUrl: 'https://contoso.portal.example-msp.test/kb/article/321',
  confidence: 0.9,
  min_confidence: 0.75,
  dry_run: true,
  triggerSource: 'manual',
}, null, 2);

function psStep({ id, name: stepName, x, script, test, params }) {
  const p = params && params.length
    ? 'parameters:\n' + params.map(([n, e]) => `      - name: ${n}\n        expression: '${e.replace(/'/g, "''")}'\n`).join('')
    : 'parameters: []\n';
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
      ${p}      aiExtensions: []
`;
  if (test) s += `      testInput: |-\n${block(test, '        ')}\n`;
  return s;
}

const yml = `automationsWorkflow: 1
name: Dynamic Troubleshooting Article Delivery
description: When ServiceAI triage matches a new ticket to a knowledge base article with high confidence,
  checks the article is published for that client and sends it as a public note with "Reply 'fixed' and
  we'll close this ticket". A second entry point (mode reply) closes the ticket only on a clear yes.
  Every action gets an internal note.
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
${psStep({ id: 'parse', name: 'Read the request', x: 280, script: read('parse.ps1'), test: testInput, params: [['trigger', '{{ nodes.trigger.output }}']] })}${psStep({ id: 'check', name: 'Check the ticket and the article', x: 460, script: read('check.ps1') })}${psStep({ id: 'act', name: 'Send or close, and note it', x: 640, script: read('act.ps1') })}  - id: end
    name: End
    type: end
    position:
      x: 820
      y: 80
  connections:
  - source: start
    target: parse
    sourceHandle: null
  - source: parse
    target: check
    sourceHandle: null
  - source: check
    target: act
    sourceHandle: null
  - source: act
    target: end
    sourceHandle: null
  startActivityId: start
`;

const y = loadYaml();
const { text } = injectText(yml, name, new Map());
const doc = y.load(text);
if (doc.automationsWorkflow !== 1) throw new Error('automationsWorkflow marker missing');
const acts = doc.definition.activities;
if (acts.find((a) => a.id === 'start').properties.webhookEnabled !== false) throw new Error('webhook must ship disabled');
if (acts.some((a) => a.properties && 'model' in a.properties && a.properties.model)) throw new Error('model must be blank');
if (/\{\{\s*input\./.test(text)) throw new Error('use nodes.<id>.output bindings, never input.*');
if (text.includes(String.fromCharCode(0x2014))) throw new Error('no em dashes');
if (!acts.find((a) => a.id === 'check').properties.script.includes('function Get-PsaTicketNotes')) throw new Error('_shared/psa.ps1 was not pasted');

const check = process.argv.includes('--check');
const was = fs.existsSync(out) ? fs.readFileSync(out, 'utf8').replace(/\r\n/g, '\n') : '';
if (text === was) { console.log(`${name}: current`); process.exit(0); }
if (check) { console.log(`${name}: OUT OF DATE (run node src/build.js)`); process.exit(1); }
fs.writeFileSync(out, text);
console.log(`${name}: written`);
