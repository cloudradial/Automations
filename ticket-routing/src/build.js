// Builds ../ticket-routing.yml and ../Test-RoutingTable.ps1 from the scripts in this folder.
// Usage: npm install && node build.js
// Edit the .ps1 files here, never the generated .yml or Test-RoutingTable.ps1.
const fs = require('fs');
const path = require('path');
let y;
try { y = require('js-yaml'); } catch { y = require(process.env.JS_YAML_PATH); }

const here = __dirname;
const root = path.join(here, '..');
const read = (f) => fs.readFileSync(path.join(here, f), 'utf8').replace(/\r\n/g, '\n').trimEnd() + '\n';
const agent = y.load(fs.readFileSync(path.join(root, 'ticket-skill-classifier.agent.yml'), 'utf8')).agent;

const preamble = (title, lines) =>
  ['# =====================================================================', `#  Send Every Ticket to the Right Engineer - ${title}`, ...lines.map((l) => `#  ${l}`),
   '#  Generated from ticket-routing/src. Edit the source, then run build.js.',
   '# =====================================================================', "$ErrorActionPreference = 'Stop'", 'Set-StrictMode -Version Latest', ''].join('\n') + '\n';

const prepareScript = preamble('Read the request, routing table and ticket', [
  'Writes nothing. Reads the two routing KB articles from CloudRadial and the ticket from the PSA.',
  'Secrets: CloudRadial-BaseUrl, CloudRadial-PublicKey, CloudRadial-PrivateKey, Routing-CompanyId,',
  'PSA-Type, and the PSA\'s own secrets (the same names as its catalog extension).',
]) + read('routing-table.ps1') + '\n' + read('psa.ps1') + '\n# ---------- this step ----------\n' + read('prepare.ps1');

const routeScript = preamble('Find, pick, assign and note', [
  'Writes to the PSA only when confirm is true: sets the assignee, then adds an internal note.',
]) + read('psa.ps1') + '\n# ---------- this step ----------\n' + read('route.ps1');

const wf = {
  automationsWorkflow: 1,
  name: 'Send Every Ticket to the Right Engineer',
  description:
    'Assigns a new ticket to an engineer who has the right skill, chosen by your rule (least busy, round robin, listed order or random), ' +
    'and adds an internal note saying why. The routing table lives in two CloudRadial KB articles. Run from a ServiceAI Triage Action. ' +
    'Preview only until confirm is true.',
  definition: {
    schemaVersion: 1,
    activities: [
      { id: 'start', name: 'Start', type: 'start', position: { x: 80, y: 120 }, properties: { webhookEnabled: false } },
      {
        id: 'node-prepare', name: 'Read the request, routing table and ticket', type: 'powershell-script', position: { x: 300, y: 120 },
        properties: {
          script: prepareScript, timeoutSeconds: 300, retryCount: 0,
          parameters: [{ name: 'trigger', expression: '{{ nodes.trigger.output }}' }],
          aiExtensions: [],
          testInput: JSON.stringify({ triggerSource: 'manual-test', ticketId: '12345', psa: 'connectwise', confirm: 'false' }, null, 2),
        },
      },
      {
        id: 'node-classify', name: 'Pick the skill', type: 'agent', position: { x: 540, y: 120 },
        properties: {
          goal:
            'Read the ticket summary and description in your input and pick the one skill from skillList that an engineer needs to work it, ' +
            'and the role for that skill. Copy the skill and role exactly as they are written in skillList. Return skill, role, confidence (0 to 1) ' +
            'and a one-sentence reason. If nothing in the list fits, return an empty skill and a confidence below 0.5. If skip is true, return an ' +
            'empty skill and confidence 0 straight away. This is read-only: you have no tools and change nothing.',
          model: '',
          allowedExtensions: [],
          timeoutSeconds: 120,
          autoApprove: true,
          agentSlug: agent.slug,
          inputSchema: agent.inputSchema,
          outputSchema: agent.outputSchema,
          inputBindingsJson: JSON.stringify({
            summary: '{{ nodes.node-prepare.output.summary }}',
            description: '{{ nodes.node-prepare.output.description }}',
            skillList: '{{ nodes.node-prepare.output.skillList }}',
            roles: '{{ nodes.node-prepare.output.roles }}',
            skip: '{{ nodes.node-prepare.output.skip }}',
          }),
        },
      },
      {
        id: 'node-route', name: 'Find, pick, assign and note', type: 'powershell-script', position: { x: 780, y: 120 },
        properties: {
          script: routeScript, timeoutSeconds: 300, retryCount: 0,
          parameters: [
            { name: 'prep', expression: '{{ nodes.node-prepare.output }}' },
            { name: 'ai', expression: '{{ nodes.node-classify.output }}' },
          ],
          aiExtensions: [],
        },
      },
      { id: 'end', name: 'End', type: 'end', position: { x: 1000, y: 120 } },
    ],
    connections: [
      { source: 'start', target: 'node-prepare', sourceHandle: null },
      { source: 'node-prepare', target: 'node-classify', sourceHandle: null },
      { source: 'node-classify', target: 'node-route', sourceHandle: null },
      { source: 'node-route', target: 'end', sourceHandle: null },
    ],
    startActivityId: 'start',
  },
};

const header = [
  '# CloudRadial AutomationAI - Send Every Ticket to the Right Engineer.',
  '# Generated by src/build.js. Edit the scripts in src/, not this file.',
  '# Import on Workflows -> Import, after uploading ticket-skill-classifier.agent.yml on Agents -> Custom.',
  '# See README.md for the routing table, secrets and the ServiceAI Action.',
].join('\n');
const out = header + '\n' + y.dump(wf, { lineWidth: -1, noRefs: true });
const back = y.load(out);
// Embedded JSON must parse.
const cls = back.definition.activities.find((a) => a.id === 'node-classify').properties;
for (const k of ['inputSchema', 'outputSchema', 'inputBindingsJson']) JSON.parse(cls[k]);
JSON.parse(back.definition.activities.find((a) => a.id === 'node-prepare').properties.testInput);
if (back.definition.activities[0].properties.webhookEnabled !== false) throw new Error('webhook must ship off');
fs.writeFileSync(path.join(root, 'ticket-routing.yml'), out);

const cli = read('Test-RoutingTable.cli.ps1').replace('#@@ROUTING_TABLE@@\n', () => read('routing-table.ps1')); // a function, so "$'" in the script isn't a replace pattern
if (cli.includes('@@ROUTING_TABLE@@')) throw new Error('marker not replaced');
fs.writeFileSync(path.join(root, 'Test-RoutingTable.ps1'), '﻿' + cli.replace(/\n/g, '\r\n'));

// The two KB article templates are the CSV templates plus the default settings, ready to paste.
const csv = (f) => fs.readFileSync(path.join(root, f), 'utf8').replace(/^﻿/, '').replace(/\r\n/g, '\n').trimEnd() + '\n';
const settings = ['tieBreak: least-open-tickets', 'respectMaxOpen: yes', 'noMatch: leave-unassigned', 'fallbackEngineer:', 'minConfidence: 0.7', 'liveAssign: no'];
fs.mkdirSync(path.join(root, 'kb-articles'), { recursive: true });
fs.writeFileSync(path.join(root, 'kb-articles', 'ticket-routing-engineers-and-settings.txt'), ['[Settings]', ...settings, '', '[Engineers]', ''].join('\n') + csv('engineers-template.csv'));
fs.writeFileSync(path.join(root, 'kb-articles', 'ticket-routing-skills.txt'), '[Skills]\n' + csv('skills-template.csv'));

console.log('ticket-routing.yml', out.length, 'bytes | Test-RoutingTable.ps1', cli.length, 'bytes');
