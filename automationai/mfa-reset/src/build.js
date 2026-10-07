// Builds mfa-reset.yml from the step sources in this folder, then pastes the shared libraries into it
// (automationai/_shared/inject.js).
// Usage: node build.js          rewrite the .yml
//        node build.js --check  exit 1 if the .yml is out of date
// Edit parse.ps1, verify.ps1 and reset.ps1, never the .yml.
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
const out = path.join(here, '..', 'mfa-reset.yml');
const read = (f) => fs.readFileSync(path.join(here, f), 'utf8').replace(/\r\n/g, '\n').trimEnd();
const block = (text, indent) => text.split('\n').map((l) => (l ? indent + l : '')).join('\n');

// Placeholder test input: the submitter resets their own account, as a dry run.
const testInput = JSON.stringify({
  submittedByUpn: 'megan.bowen@contoso.com',
  userOfficeId: '',
  userPrincipalName: '',
  companyTenantId: '',
  ticketId: '',
  psa: '',
  psaCompanyId: '',
  issue_tap: false,
  dry_run: true,
}, null, 2);

// params: [[name, expression]]. The first step binds the webhook body the way Password Reset does
// (parameter "trigger" = {{ nodes.trigger.output }}); later steps read the previous step's output.
function psStep({ id, name, x, script, test, params }) {
  const p = params && params.length
    ? 'parameters:\n' + params.map(([n, e]) => `      - name: ${n}\n        expression: '${e.replace(/'/g, "''")}'\n`).join('')
    : 'parameters: []\n';
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
      ${p}      aiExtensions: []
`;
  if (test) s += `      testInput: |-\n${block(test, '        ')}\n`;
  return s;
}

const yml = `automationsWorkflow: 1
name: Self-Service MFA Reset
description: A signed-in portal user resets their own MFA. The portal's verified identity must match the
  account, and disabled, admin and at-risk accounts are refused. Every sign-in method except the password
  is removed and the user is signed out. Detail goes only in the internal ticket note.
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
${psStep({ id: 'parse', name: 'Read the request', x: 280, script: read('parse.ps1'), test: testInput, params: [['trigger', '{{ nodes.trigger.output }}']] })}${psStep({ id: 'verify', name: 'Check the requester and account', x: 460, script: read('verify.ps1') })}${psStep({ id: 'reset', name: 'Clear MFA and record it', x: 640, script: read('reset.ps1') })}  - id: end
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
    target: verify
    sourceHandle: null
  - source: verify
    target: reset
    sourceHandle: null
  - source: reset
    target: end
    sourceHandle: null
  startActivityId: start
`;

const y = loadYaml();
const { text } = injectText(yml, 'mfa-reset.yml', new Map());
const doc = y.load(text);
// Guard rails: the shape every workflow must have.
if (doc.automationsWorkflow !== 1) throw new Error('automationsWorkflow marker missing');
const acts = doc.definition.activities;
if (acts.find((a) => a.id === 'start').properties.webhookEnabled !== false) throw new Error('webhook must ship disabled');
if (acts.some((a) => a.properties && 'model' in a.properties && a.properties.model)) throw new Error('model must be blank');
if (/\{\{\s*input\./.test(text)) throw new Error('use nodes.<id>.output bindings, never input.*');
if (text.includes(String.fromCharCode(0x2014))) throw new Error('no em dashes');

const check = process.argv.includes('--check');
const was = fs.existsSync(out) ? fs.readFileSync(out, 'utf8').replace(/\r\n/g, '\n') : '';
if (text === was) { console.log('mfa-reset.yml: current'); process.exit(0); }
if (check) { console.log('mfa-reset.yml: OUT OF DATE (run node src/build.js)'); process.exit(1); }
fs.writeFileSync(out, text);
console.log('mfa-reset.yml: written');
