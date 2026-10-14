// Builds priority-scoring.yml from the step sources in this folder: pastes src/psa-priority.ps1 where a step
// says "# @@ src/psa-priority.ps1 @@", then the shared libraries with _shared/inject.js.
// Usage: node build.js          rewrite the .yml
//        node build.js --check  exit 1 if the .yml is out of date
// Edit score.ps1, apply.ps1 and psa-priority.ps1, never the .yml.
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
const out = path.join(here, '..', 'priority-scoring.yml');
const read = (f) => fs.readFileSync(path.join(here, f), 'utf8').replace(/\r\n/g, '\n').trimEnd();
const block = (text, indent) => text.split('\n').map((l) => (l ? indent + l : '')).join('\n');
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
const PRIO = '# @@ src/psa-priority.ps1 @@';
// A function replacement, so "$'" and "$&" in the PowerShell aren't read as replacement patterns.
const step = (f) => read(f).replace(PRIO, () => read('psa-priority.ps1'));

const testInput = JSON.stringify({ ticketId: '1001', psa: '', confirm: false, addNote: true }, null, 2);

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
name: Severity / Priority Scoring
description: Scores a new ticket's impact with fixed rules (outage and security words, blocked users,
  how many people are affected, the VIP list and the company tier) and raises its priority to match,
  never lowering it and never above high. A possible P1 is emailed to the dispatcher instead. Writes
  nothing unless confirm is true, and adds the score breakdown as an internal note.
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
${psStep({ id: 'score', name: 'Score the ticket', x: 300, script: step('score.ps1'), test: testInput })}${psStep({
  id: 'apply', name: 'Set the priority and note the score', x: 520, script: step('apply.ps1'),
  params: [['ctx', '{{ nodes.score.output.ctx_json }}']],
})}  - id: end
    name: End
    type: end
    position:
      x: 740
      y: 80
  connections:
  - source: start
    target: score
    sourceHandle: null
  - source: score
    target: apply
    sourceHandle: null
  - source: apply
    target: end
    sourceHandle: null
  startActivityId: start
`;

const y = loadYaml();
const { text } = injectText(yml, 'priority-scoring.yml', new Map());
y.load(text);
const doc = y.load(text);
if (doc.automationsWorkflow !== 1) throw new Error('automationsWorkflow marker missing');
if (doc.definition.activities.find((a) => a.id === 'start').properties.webhookEnabled !== false) throw new Error('webhook must ship disabled');
if (/\{\{\s*input\./.test(text)) throw new Error('use nodes.<id>.output bindings, never input.*');
if (text.includes(PRIO)) throw new Error('psa-priority.ps1 not pasted');
if (/[–—]/.test(text)) throw new Error('no en or em dashes');

const check = process.argv.includes('--check');
const was = fs.existsSync(out) ? fs.readFileSync(out, 'utf8').replace(/\r\n/g, '\n') : '';
if (text === was) { console.log('priority-scoring.yml: current'); process.exit(0); }
if (check) { console.log('priority-scoring.yml: OUT OF DATE (run node src/build.js)'); process.exit(1); }
fs.writeFileSync(out, text);
console.log('priority-scoring.yml: written');
