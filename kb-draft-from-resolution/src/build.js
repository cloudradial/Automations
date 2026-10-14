// Builds kb-draft-from-resolution.yml from the step sources in this folder: pastes src/scrub.ps1 where a
// step says "# @@ src/scrub.ps1 @@", then the shared libraries (_shared/psa.ps1, psa-tickets.ps1 and
// cloudradial.ps1) with _shared/inject.js.
// Usage: node build.js          rewrite the .yml
//        node build.js --check  exit 1 if the .yml is out of date
// Edit gather.ps1, save.ps1, scrub.ps1 and the judge.*.txt prompts, never the .yml.
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
const out = path.join(here, '..', 'kb-draft-from-resolution.yml');
const read = (f) => fs.readFileSync(path.join(here, f), 'utf8').replace(/\r\n/g, '\n').trimEnd();
const block = (text, indent) => text.split('\n').map((l) => (l ? indent + l : '')).join('\n');
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
const SCRUB = '# @@ src/scrub.ps1 @@';
const step = (f) => {
  const s = read(f);
  if (s.split(SCRUB).length !== 2) throw new Error(`${f}: expected one "${SCRUB}" line`);
  // A function replacement, so "$'" and "$&" in the PowerShell aren't read as replacement patterns.
  return s.replace(SCRUB, () => read('scrub.ps1'));
};

const testInput = JSON.stringify({ ticketId: '1001', psa: '', confirm: false, resolutionNotes: '', category: '' }, null, 2);

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
name: Resolution to KB Draft
description: Turns how a resolved ticket was fixed into a knowledge base article draft in CloudRadial,
  with client names, people, addresses, IP addresses and secrets taken out before and after one AI call.
  Saves it for review under the MSP's own CloudRadial company with a 2099 publish date, so no client sees
  it until a reviewer publishes it. Writes nothing unless confirm is true.
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
${psStep({ id: 'gather', name: 'Read the resolution', x: 280, script: step('gather.ps1'), test: testInput })}  - id: judge
    name: Draft the article
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
      maxTokens: 1500
      outputKey: judgment
      parameters: []
${psStep({
  id: 'save', name: 'Save the draft for review', x: 640, script: step('save.ps1'),
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
    target: save
    sourceHandle: null
  - source: save
    target: end
    sourceHandle: null
  startActivityId: start
`;

const y = loadYaml();
const { text } = injectText(yml, 'kb-draft-from-resolution.yml', new Map());
const doc = y.load(text);
if (doc.automationsWorkflow !== 1) throw new Error('automationsWorkflow marker missing');
const acts = doc.definition.activities;
if (acts.find((a) => a.id === 'start').properties.webhookEnabled !== false) throw new Error('webhook must ship disabled');
if (acts.some((a) => a.properties && 'model' in a.properties && a.properties.model)) throw new Error('model must be blank');
if (/\{\{\s*input\./.test(text)) throw new Error('use nodes.<id>.output bindings, never input.*');
if (text.includes(SCRUB)) throw new Error('scrub.ps1 not pasted');
if (/[–—]/.test(text)) throw new Error('no en or em dashes');

const check = process.argv.includes('--check');
const was = fs.existsSync(out) ? fs.readFileSync(out, 'utf8').replace(/\r\n/g, '\n') : '';
if (text === was) { console.log('kb-draft-from-resolution.yml: current'); process.exit(0); }
if (check) { console.log('kb-draft-from-resolution.yml: OUT OF DATE (run node src/build.js)'); process.exit(1); }
fs.writeFileSync(out, text);
console.log('kb-draft-from-resolution.yml: written');
