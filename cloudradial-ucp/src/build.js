// Builds ../set-up-new-company.yml from read-setup.ps1 (the Read the setup step) and the goal below.
// Usage: node build.js          rewrite the .yml
//        node build.js --check  exit 1 if the .yml is out of date
// Edit read-setup.ps1 or this file, never the .yml. Test the step with: pwsh -NoProfile -File test.ps1
// Needs js-yaml: npm install in ../../_shared, or set JS_YAML_PATH to an existing copy.
const fs = require('fs');
const path = require('path');
let y;
try { y = require('js-yaml'); } catch {
  try { y = require(path.join(__dirname, '..', '..', '_shared', 'node_modules', 'js-yaml')); } catch { y = require(process.env.JS_YAML_PATH); }
}
const out = path.join(__dirname, '..', 'set-up-new-company.yml');
const script = fs.readFileSync(path.join(__dirname, 'read-setup.ps1'), 'utf8').replace(/\r\n/g, '\n').trimEnd() + '\n';

const testInput = {
  companyName: 'Contoso Ltd',
  domain: 'contoso.com',
  companyGroup: 'Managed Clients',
  accountManager: 'alex.kim@examplemsp.com',
  users: [{ firstName: 'Pat', lastName: 'Lee', email: 'pat.lee@contoso.com' }],
  tokens: [{ token: 'SupportPhone', value: '555-0100' }],
  requestForms: [{ subject: 'Request a new laptop', category: 'Hardware', description: 'Tell us who the laptop is for and when they start.' }],
  menuTiles: [{ name: 'Remote Support', url: 'https://support.examplemsp.com', category: 'Help' }],
};

const goal = [
  'Write one short sentence before each tool call, and never send an empty message.',
  '',
  'Set up ONE new client company in CloudRadial from the plan in your request, following SETTING UP A NEW',
  'COMPANY in your instructions. Create only what the plan lists, in this order: company, default domain,',
  'company group membership, users, tokens, request forms, menu tiles. Leave out any field the plan leaves',
  'empty, and never invent a value. Menu tiles always get order 0 and editRights 0.',
  '',
  'Do every duplicate check first, in one turn. If the company name or the domain already exists, stop',
  'before creating anything and report what matched. If the company group is named but not found, set up',
  'everything else, skip the group and say so. Never create a company group unless the plan asks for it.',
  '',
  'When the plan has an existingCompanyId, the company already exists: read it with cr_list_company,',
  'filter "companyId eq <id>" (not cr_get_company, which can return 404), and stop if no row comes back.',
  'Never create or change it, and skip the domain or group membership it already has. Stop if another',
  'company already has the domain.',
  '',
  'After the company is created, read it back by name to get its companyId and use that id for every',
  'later create. Do the reads in parallel, but make each create on its own and wait for its result before',
  'the next: each create waits for its own approval. You stop after 25 turns, so never re-read what you have.',
  '',
  'Every create is approval-gated. On a dry run, still do every read and list each record you would',
  'create. Never update or delete anything in this run. Call a record created only when its create call',
  'returned success; otherwise say failed (with the error) or not attempted.',
  '',
  'Always fill companyId in your output, as text: the existing or new id (for example "9"), or "not created".',
  'Finish with: the companyId, one line per record (created, would create, skipped',
  'and why, or failed and the error), and the manual steps: logo and theme, messaging, the PSA and',
  'Microsoft 365 links, security roles, showing each new menu tile to Everyone, and inviting the users.',
].join('\n') + '\n';

const outputSchema = {
  type: 'object',
  properties: {
    companyId: { type: 'string' },
    answer: { type: 'string' },
    actions: { type: 'array', items: { type: 'string' } },
    skipped: { type: 'array', items: { type: 'string' } },
    manualSteps: { type: 'array', items: { type: 'string' } },
  },
  required: ['companyId', 'answer'],
  additionalProperties: false,
};

const wf = {
  automationsWorkflow: 1,
  name: 'Set Up a New Company',
  description:
    'Sets up one new client company in CloudRadial through the CloudRadial UCP Assistant: the company, its default domain, ' +
    'company group, first portal users, replacement tokens, starter request forms and menu tiles. Checks for duplicates first; ' +
    'every create is approval-gated. Send {"companyName":"Contoso Ltd","domain":"contoso.com", ...}, or ' +
    '{"company_id":23, ...} to add to a company that already exists.',
  definition: {
    schemaVersion: 1,
    activities: [
      { id: 'start', name: 'Start', type: 'start', position: { x: 100, y: 120 }, properties: { webhookEnabled: false } },
      {
        id: 'node-inputs', name: 'Read the setup', type: 'powershell-script', position: { x: 300, y: 120 },
        properties: { script, timeoutSeconds: 60, retryCount: 0, parameters: [], aiExtensions: [], testInput: JSON.stringify(testInput, null, 2) },
      },
      {
        id: 'node-agent', name: 'Set up the company', type: 'agent', position: { x: 520, y: 120 },
        properties: {
          agentSlug: 'cloudradial-ucp-assistant',
          goal,
          allowedExtensions: ['cloudradial-v2-companies', 'cloudradial-v2-tokens', 'cloudradial-v2-content'],
          model: '',
          timeoutSeconds: 1800,
          autoApprove: false,
          inputBindingsJson: JSON.stringify({ request: '{{ nodes.node-inputs.output.request }}', companyName: '{{ nodes.node-inputs.output.companyName }}' }),
          inputSchema: JSON.stringify({ type: 'object', properties: { request: { type: 'string' }, companyName: { type: 'string' } }, required: ['request'], additionalProperties: false }),
          outputSchema: JSON.stringify(outputSchema),
        },
      },
      { id: 'end', name: 'End', type: 'end', position: { x: 740, y: 120 } },
    ],
    connections: [
      { source: 'start', target: 'node-inputs', sourceHandle: null },
      { source: 'node-inputs', target: 'node-agent', sourceHandle: null },
      { source: 'node-agent', target: 'end', sourceHandle: null },
    ],
    startActivityId: 'start',
  },
};

const header = [
  '# Generated by src/build.js from src/read-setup.ps1. Edit the sources, not this file.',
  '# CloudRadial AutomationAI - Set Up a New Company (goal workflow for the CloudRadial UCP Assistant).',
  '# Import the agent (cloudradial-ucp.agent.yml) first, then this file on Workflows -> Import.',
  '# Manual run: leave the first step unbound; it reads the Run input. See README.md.',
].join('\n');
const text = header + '\n' + y.dump(wf, { lineWidth: -1, noRefs: true });
const back = y.load(text);
for (const k of ['inputSchema', 'outputSchema', 'inputBindingsJson']) JSON.parse(back.definition.activities[2].properties[k]);
JSON.parse(back.definition.activities[1].properties.testInput);
if (back.definition.activities[0].properties.webhookEnabled !== false) throw new Error('webhook must ship off');
if (back.definition.activities[1].properties.script !== script) throw new Error('script changed in round trip');
const was = fs.existsSync(out) ? fs.readFileSync(out, 'utf8').replace(/\r\n/g, '\n') : '';
if (text === was) { console.log('set-up-new-company.yml: current'); process.exit(0); }
if (process.argv.includes('--check')) { console.log('set-up-new-company.yml: OUT OF DATE (run node src/build.js)'); process.exit(1); }
fs.writeFileSync(out, text);
console.log('set-up-new-company.yml: written (' + text.length + ' bytes)');
