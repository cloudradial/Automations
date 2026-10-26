// Builds create-halo-ticket-from-template.yml from src/create.ps1, then pastes _shared/psa.ps1 with _shared/inject.js.
// Usage: node build.js          rewrite the .yml
//        node build.js --check  exit 1 if the .yml is out of date
// Edit create.ps1, never the .yml.
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
const out = path.join(here, '..', 'create-halo-ticket-from-template.yml');
const read = (f) => fs.readFileSync(path.join(here, f), 'utf8').replace(/\r\n/g, '\n').trimEnd();
const block = (text, indent) => text.split('\n').map((l) => (l ? indent + l : '')).join('\n');

const testInput = JSON.stringify({
  User: { UserEmail: 'pat.example@contoso.com', UserPsaId: 0 },
  Company: { CompanyName: 'Contoso', CompanyPsaId: 0 },
  Ticket: { TicketSubject: 'New Starter Request', TicketDescription: 'Placeholder test submission', Questions: [{ Id: 'haloTemplateId', Label: 'Request reference', Value: '1' }, { Id: 'CFfirstName', Label: 'First name', Value: 'Pat' }] },
  confirm: false,
}, null, 2);

const yml = `automationsWorkflow: 1
name: Create a Halo Ticket from a Template
description: Creates a HaloPSA ticket from a CloudRadial request form made from a Halo ticket template, with the
  template's ticket type, team, priority, status and category and every answer written into its Halo custom field.
  Use it when Halo makes custom fields mandatory, which CloudRadial's own ticket submission can't fill. A form
  submission creates the ticket; a manual run previews it unless confirm is true. No AI.
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
  - id: create
    name: Create the Halo ticket
    type: powershell-script
    position:
      x: 300
      y: 80
    properties:
      script: |-
${block(read('create.ps1'), '        ')}
      timeoutSeconds: 300
      retryCount: 0
      parameters: []
      aiExtensions: []
      testInput: |-
${block(testInput, '        ')}
  - id: end
    name: End
    type: end
    position:
      x: 500
      y: 80
  connections:
  - source: start
    target: create
    sourceHandle: null
  - source: create
    target: end
    sourceHandle: null
  startActivityId: start
`;

const y = loadYaml();
const { text } = injectText(yml, 'create-halo-ticket-from-template.yml', new Map());
const doc = y.load(text);
if (doc.automationsWorkflow !== 1) throw new Error('automationsWorkflow marker missing');
if (doc.definition.activities.find((a) => a.id === 'start').properties.webhookEnabled !== false) throw new Error('webhook must ship disabled');
if (/\{\{\s*input\./.test(text)) throw new Error('use nodes.<id>.output bindings, never input.*');
if (/[–—]/.test(text)) throw new Error('no en or em dashes');

const check = process.argv.includes('--check');
const was = fs.existsSync(out) ? fs.readFileSync(out, 'utf8').replace(/\r\n/g, '\n') : '';
if (text === was) { console.log('create-halo-ticket-from-template.yml: current'); process.exit(0); }
if (check) { console.log('create-halo-ticket-from-template.yml: OUT OF DATE (run node src/build.js)'); process.exit(1); }
fs.writeFileSync(out, text);
console.log('create-halo-ticket-from-template.yml: written');
