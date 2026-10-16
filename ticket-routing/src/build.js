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
const csv = (f) => fs.readFileSync(path.join(root, f), 'utf8').replace(/^\ufeff/, '').replace(/\r\n/g, '\n').trimEnd() + '\n';
const settings = ['tieBreak: least-open-tickets', 'respectMaxOpen: yes', 'noMatch: leave-unassigned', 'fallbackEngineer:', 'minConfidence: 0.7', 'liveAssign: no'];
const agent = y.load(fs.readFileSync(path.join(root, 'ticket-skill-classifier.agent.yml'), 'utf8')).agent;

const preamble = (title, lines) =>
  ['# =====================================================================', `#  Send Every Ticket to the Right Engineer - ${title}`, ...lines.map((l) => `#  ${l}`),
   '#  Generated from ticket-routing/src. Edit the source, then run build.js.',
   '# =====================================================================', "$ErrorActionPreference = 'Stop'", 'Set-StrictMode -Version Latest', ''].join('\n') + '\n';

// The Routing table step is the one partners edit, so it ships with the templates pasted in and no generated header.
const fill = (t, marker, text) => { if (!t.includes(marker + '\n')) throw new Error('table marker missing: ' + marker); return t.replace(marker + '\n', () => text); };
let tableScript = read('table.ps1');
tableScript = fill(tableScript, '#@@SETTINGS@@', settings.join('\n') + '\n');
tableScript = fill(tableScript, '#@@ENGINEERS@@', csv('engineers-template.csv'));
tableScript = fill(tableScript, '#@@SKILLS@@', csv('skills-template.csv'));
if (tableScript.includes('#@@')) throw new Error('table step markers left');

const prepareScript = preamble('Read the request, routing table and ticket', [
  'Writes nothing. Reads the routing table from the Routing table step (or, with tableSource ucp, two',
  'CloudRadial KB articles) and the ticket from the PSA. Secrets: PSA-Type and the PSA\'s own secrets',
  '(the same names as its catalog extension); for ucp also CloudRadial-BaseUrl, -PublicKey, -PrivateKey',
  'and Routing-CompanyId.',
]) + read('routing-table.ps1') + '\n' + read('psa.ps1') + '\n# ---------- this step ----------\n' + read('prepare.ps1');

const routeScript = preamble('Find, pick, assign and note', [
  'Writes to the PSA only when confirm is true: sets the assignee, then adds an internal note.',
]) + read('psa.ps1') + '\n# ---------- this step ----------\n' + read('route.ps1');

const wf = {
  automationsWorkflow: 1,
  name: 'Send Every Ticket to the Right Engineer',
  description:
    'Assigns a new ticket to an engineer who has the right skill, chosen by your rule (least busy, round robin, listed order or random), ' +
    'and adds an internal note saying why. Paste your routing table into the Routing table step (or keep the skills in AutomationAI Knowledge, or in CloudRadial KB articles). Run from a ServiceAI Triage Action. ' +
    'Preview only until liveAssign is yes.',
  definition: {
    schemaVersion: 1,
    activities: [
      { id: 'start', name: 'Start', type: 'start', position: { x: 80, y: 120 }, properties: { webhookEnabled: false } },
      {
        id: 'node-table', name: 'Routing table (edit me)', type: 'powershell-script', position: { x: 260, y: 120 },
        properties: { script: tableScript, timeoutSeconds: 60, retryCount: 0, parameters: [], aiExtensions: [] },
      },
      {
        id: 'node-prepare', name: 'Read the request, routing table and ticket', type: 'powershell-script', position: { x: 460, y: 120 },
        properties: {
          script: prepareScript, timeoutSeconds: 300, retryCount: 0,
          parameters: [
            { name: 'trigger', expression: '{{ nodes.trigger.output }}' },
            { name: 'table', expression: '{{ nodes.node-table.output }}' },
          ],
          aiExtensions: [],
          testInput: JSON.stringify({ triggerSource: 'manual-test', ticketId: '12345', psa: 'connectwise', confirm: 'false' }, null, 2),
        },
      },
      {
        id: 'node-classify', name: 'Pick the skill', type: 'agent', position: { x: 660, y: 120 },
        properties: {
          goal:
            'Read the ticket summary and description in your input and pick the one skill from skillList that an engineer needs to work it, ' +
            'and the role for that skill. Copy the skill and role exactly as they are written in skillList. Return skill, role, confidence (0 to 1) ' +
            'and a one-sentence reason. If nothing in the list fits, return an empty skill and a confidence below 0.5. If skip is true, return an ' +
            'empty skill and confidence 0 straight away. If useKnowledge is true, skillList is empty: search the skills CSV in your Knowledge instead, ' +
            'and also return in engineers every Engineer the CSV lists for that skill and role, copied exactly. This is read-only: change nothing.',
          model: '',
          allowedExtensions: ['cloudradial-v2-companies'], // never empty: see EXT_COMMENT below
          timeoutSeconds: 300,
          autoApprove: false, // any tool call waits in the Inbox; the classifier should make none
          agentSlug: agent.slug,
          inputSchema: agent.inputSchema,
          outputSchema: agent.outputSchema,
          inputBindingsJson: JSON.stringify({
            summary: '{{ nodes.node-prepare.output.summary }}',
            description: '{{ nodes.node-prepare.output.description }}',
            skillList: '{{ nodes.node-prepare.output.skillList }}',
            roles: '{{ nodes.node-prepare.output.roles }}',
            useKnowledge: '{{ nodes.node-prepare.output.useKnowledge }}',
            skip: '{{ nodes.node-prepare.output.skip }}',
          }),
        },
      },
      {
        id: 'node-route', name: 'Find, pick, assign and note', type: 'powershell-script', position: { x: 860, y: 120 },
        properties: {
          script: routeScript, timeoutSeconds: 300, retryCount: 0,
          parameters: [
            { name: 'prep', expression: '{{ nodes.node-prepare.output }}' },
            { name: 'ai', expression: '{{ nodes.node-classify.output }}' },
          ],
          aiExtensions: [],
        },
      },
      { id: 'end', name: 'End', type: 'end', position: { x: 1060, y: 120 } },
    ],
    connections: [
      { source: 'start', target: 'node-table', sourceHandle: null },
      { source: 'node-table', target: 'node-prepare', sourceHandle: null },
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
// js-yaml can't write comments, so the classifier's allowedExtensions comment is added after the dump.
const EXT_COMMENT = [
  '# Never leave this list empty: an empty list gives the agent every installed',
  "# extension (925 tools on 2026-10-14, over the model's 128-tool limit).",
  '# The agent calls no tools; the list only has to be short and non-empty.',
];
const EXT_LINE = '        allowedExtensions:\n          - cloudradial-v2-companies\n';
let out = header + '\n' + y.dump(wf, { lineWidth: -1, noRefs: true });
if (out.split(EXT_LINE).length !== 2) throw new Error('classifier allowedExtensions not found exactly once');
out = out.replace(EXT_LINE, () => EXT_COMMENT.map((l) => `        ${l}\n`).join('') + EXT_LINE);
const back = y.load(out);
// Embedded JSON must parse.
const cls = back.definition.activities.find((a) => a.id === 'node-classify').properties;
for (const k of ['inputSchema', 'outputSchema', 'inputBindingsJson']) JSON.parse(cls[k]);
JSON.parse(back.definition.activities.find((a) => a.id === 'node-prepare').properties.testInput);
if (back.definition.activities[0].properties.webhookEnabled !== false) throw new Error('webhook must ship off');
if (!Array.isArray(cls.allowedExtensions) || cls.allowedExtensions.length === 0) throw new Error('classifier allowedExtensions must not be empty');
fs.writeFileSync(path.join(root, 'ticket-routing.yml'), out);

const cli = read('Test-RoutingTable.cli.ps1').replace('#@@ROUTING_TABLE@@\n', () => read('routing-table.ps1')); // a function, so "$'" in the script isn't a replace pattern
if (cli.includes('@@ROUTING_TABLE@@')) throw new Error('marker not replaced');
fs.writeFileSync(path.join(root, 'Test-RoutingTable.ps1'), '﻿' + cli.replace(/\n/g, '\r\n'));

// The two KB article templates (tableSource ucp) are the CSV templates plus the default settings, ready to paste.
fs.mkdirSync(path.join(root, 'kb-articles'), { recursive: true });
fs.writeFileSync(path.join(root, 'kb-articles', 'ticket-routing-engineers-and-settings.txt'), ['[Settings]', ...settings, '', '[Engineers]', ''].join('\n') + csv('engineers-template.csv'));
fs.writeFileSync(path.join(root, 'kb-articles', 'ticket-routing-skills.txt'), '[Skills]\n' + csv('skills-template.csv'));

console.log('ticket-routing.yml', out.length, 'bytes | Test-RoutingTable.ps1', cli.length, 'bytes');
