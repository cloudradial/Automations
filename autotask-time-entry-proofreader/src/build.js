#!/usr/bin/env node
// Builds the Autotask Time Entry Proofreader agent and its goal workflow from src/prompt.md.
// Edit the sources, then run:  node autotask-time-entry-proofreader/src/build.js
// --check fails when a generated file is out of date.
'use strict';
const fs = require('fs');
const path = require('path');

const yaml = (() => {
  const tries = [process.env.JS_YAML_PATH, 'js-yaml',
    'C:/Users/NicholasWestgate/OneDrive - Azurative/Documents/Claude/handoffs/src/node_modules/js-yaml'];
  for (const t of tries) { if (!t) continue; try { return require(t); } catch (e) { /* next */ } }
  throw new Error('js-yaml not found: set JS_YAML_PATH');
})();

const SLUG = 'autotask-time-entry-proofreader';
const VERSION = '0.5.0';
const ROOT = path.resolve(__dirname, '..');
const prompt = fs.readFileSync(path.join(__dirname, 'prompt.md'), 'utf8').replace(/\r\n/g, '\n');
const snapshot = JSON.parse(fs.readFileSync(path.join(__dirname, 'tools-snapshot.json'), 'utf8'));
const EXTENSIONS = Object.keys(snapshot.extensions);

const json = (o) => JSON.stringify(o, null, 2);

const variables = json([
  { name: 'notifyCompliantEntries', label: 'Also notify the approver about entries that needed no changes', type: 'boolean', default: 'false', required: false },
  { name: 'proposeApproval', label: 'After a correction is approved, also propose marking the time entry approved for billing', type: 'boolean', default: 'false', required: false },
  { name: 'approverResourceName', label: 'Autotask resource name of the approver (used when proposeApproval is on)', type: 'string', default: '', required: false },
]);
const inputSchema = json({
  type: 'object',
  properties: {
    startDate: { type: 'string', description: 'Inclusive start date in YYYY-MM-DD format. Defaults to endDate.' },
    endDate: { type: 'string', description: 'Inclusive end date in YYYY-MM-DD format. Defaults to yesterday.' },
    companyName: { type: 'string', description: 'Optional company name filter.' },
  },
  required: [],
});
const row = {
  type: 'object',
  properties: {
    timeEntryId: { type: 'string' }, ticketId: { type: 'string' }, ticketNumber: { type: 'string' },
    company: { type: 'string' }, resource: { type: 'string' }, dateWorked: { type: 'string' },
    hoursWorked: { type: 'number' }, billable: { type: 'boolean' },
    originalSummaryNotes: { type: 'string' }, correctedSummaryNotes: { type: 'string' },
    changes: { type: 'array', items: { type: 'string' } },
    status: { type: 'string', enum: ['Updated', 'Flagged', 'Skipped'] },
    flagReasons: { type: 'array', items: { type: 'string' } },
    reason: { type: 'string' }, writeBack: { type: 'boolean' }, notifyReviewer: { type: 'boolean' },
    proposalResult: { type: 'string' },
  },
  required: ['timeEntryId', 'ticketId', 'ticketNumber', 'company', 'resource', 'dateWorked', 'hoursWorked', 'billable',
    'originalSummaryNotes', 'correctedSummaryNotes', 'changes', 'status', 'flagReasons', 'reason', 'writeBack',
    'notifyReviewer', 'proposalResult'],
};
const outputSchema = json({
  type: 'object',
  properties: {
    startDate: { type: 'string' }, endDate: { type: 'string' }, companyName: { type: 'string' },
    rulesSource: { type: 'string', enum: ['Knowledge article', 'Embedded fallback'] },
    rows: { type: 'array', items: row },
    totals: { type: 'object', properties: { updated: { type: 'integer' }, flagged: { type: 'integer' }, skipped: { type: 'integer' } }, required: ['updated', 'flagged', 'skipped'] },
    summaryTableMarkdown: { type: 'string' },
  },
  required: ['startDate', 'endDate', 'companyName', 'rulesSource', 'rows', 'totals', 'summaryTableMarkdown'],
});

const agent = {
  automationsAgent: 1,
  agent: {
    slug: SLUG,
    name: 'Autotask Time Entry Proofreader',
    vendor: 'CloudRadial',
    version: VERSION,
    description: 'Reviews Autotask time entry Summary Notes against your style guide and proposes each correction for approval. Built to run as a Pulsar.',
    category: 'Service Desk',
    tags: ['autotask', 'time-entries', 'proofreading', 'psa', 'billing-readiness', 'pulsar'],
    detailsMarkdown: [
      '## What it does',
      '',
      'Reviews Autotask time entries worked in a date range (at most 15 per check-in), proposes corrected **Summary Notes** that follow your **Autotask Time Entry Style Guide** Knowledge article, and returns one row per entry with a plain-language list of what changed. Every write is a proposal: approved corrections are written, denied ones are left for the reviewer to edit in Autotask. It never posts time entries.',
      '',
      '## Setup',
      '',
      '- **Needs the `autotask-psa` catalog extension with its time entry tools:** `at_query_time_entries`, `at_get_time_entry`, `at_update_time_entry_notes` and `at_approve_time_entry`. Older versions without the last three can\'t write corrections.',
      '- Upload the style guide template (repo folder `autotask-time-entry-proofreader/knowledge/`) to the Pulsar\'s notes folder. The same rules are embedded as a fallback.',
      '- **Writes (approval-gated):** `at_update_time_entry_notes` (id and summaryNotes only) and, only when `proposeApproval` is on, `at_approve_time_entry`. Nothing changes hours, dates, resource, billing code, role, ticket, internal notes or billable status.',
      '- See the autotask-time-entry-proofreader README for the full Pulsar setup.',
    ].join('\n'),
    systemPrompt: prompt,
    model: '',
    requiredExtensionSlugs: EXTENSIONS,
    requiredSecretNames: [],
    variablesJson: variables,
    inputSchema,
    outputSchema,
    dryRunDefault: true,
  },
};

const workflow = {
  automationsWorkflow: 1,
  name: 'Autotask Time Entry Proofreading',
  description: "One proofreading check-in on demand: reviews Autotask time entries worked yesterday (or the startDate, endDate and companyName in the Run input) and proposes Summary Notes corrections, each one waiting for approval. The same agent runs as a Pulsar for daily check-ins; see the autotask-time-entry-proofreader README.",
  definition: {
    schemaVersion: 1,
    activities: [
      { id: 'start', name: 'Start', type: 'start', position: { x: 100, y: 120 }, properties: { webhookEnabled: false } },
      {
        id: 'node-proofread', name: 'Proofread time entries', type: 'agent', position: { x: 340, y: 120 },
        properties: {
          goal: 'Proofread the Summary Notes of Autotask time entries and propose each correction for approval, following the Autotask Time Entry Style Guide. Date range: startDate {{ nodes.start.output.startDate }}, endDate {{ nodes.start.output.endDate }} (blank means yesterday). Company filter: {{ nodes.start.output.companyName }} (blank means all). Review at most 15 entries.',
          model: '',
          allowedExtensions: EXTENSIONS,
          timeoutSeconds: 600,
          autoApprove: false,
          agentSlug: SLUG,
          inputSchema,
          outputSchema,
          inputBindingsJson: '{}',
        },
      },
      { id: 'end', name: 'End', type: 'end', position: { x: 580, y: 120 } },
    ],
    connections: [
      { source: 'start', target: 'node-proofread', sourceHandle: null },
      { source: 'node-proofread', target: 'end', sourceHandle: null },
    ],
    startActivityId: 'start',
  },
};

function render(header, doc) {
  const body = yaml.dump(doc, { lineWidth: -1, noRefs: true });
  yaml.load(body);
  return header + body;
}

const files = {
  [`${SLUG}.agent.yml`]: render(
    `# Autotask Time Entry Proofreader agent. Generated by src/build.js: edit src/, never this file.\n# Upload on Agents > Custom. Use it in a Pulsar (see README) or in ${SLUG}.yml.\n`, agent),
  [`${SLUG}.yml`]: render(
    `# Autotask Time Entry Proofreading goal workflow. Generated by src/build.js: edit src/, never this file.\n`, workflow),
};

const check = process.argv.includes('--check');
let stale = 0;
for (const [name, text] of Object.entries(files)) {
  const f = path.join(ROOT, name);
  const cur = fs.existsSync(f) ? fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n') : null;
  if (check) { if (cur !== text) { console.log(`STALE ${name}`); stale++; } }
  else if (cur !== text) { fs.writeFileSync(f, text); console.log(`wrote ${name}`); }
}
if (check) { console.log(stale ? `${stale} file(s) out of date` : 'current'); process.exit(stale ? 1 : 0); }
