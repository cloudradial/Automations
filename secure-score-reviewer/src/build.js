#!/usr/bin/env node
// Builds the Microsoft Secure Score Reviewer agent and its goal workflow from src/prompt.md.
// Edit the sources, then run:  node secure-score-reviewer/src/build.js
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

const SLUG = 'secure-score-reviewer';
const VERSION = '0.2.0';
const ROOT = path.resolve(__dirname, '..');
const prompt = fs.readFileSync(path.join(__dirname, 'prompt.md'), 'utf8').replace(/\r\n/g, '\n');
const snapshot = JSON.parse(fs.readFileSync(path.join(__dirname, 'tools-snapshot.json'), 'utf8'));
const EXTENSIONS = Object.keys(snapshot.extensions);

const json = (o) => JSON.stringify(o, null, 2);

const inputSchema = json({
  type: 'object',
  properties: {
    companyId: { type: 'integer', description: 'CloudRadial companyId of the client.' },
    goal: { type: 'string', description: 'Optional extra instruction for this check-in.' },
  },
});
const outputSchema = json({
  type: 'object',
  properties: {
    summary: { type: 'string' },
    secureScore: { type: 'number' },
    maxScore: { type: 'number' },
    percent: { type: 'number' },
    changeSinceLast: { type: 'number' },
    topGaps: { type: 'array', items: { type: 'string' } },
    proposed: { type: 'integer' },
    ranOnOwn: { type: 'integer' },
    needsPerson: { type: 'array', items: { type: 'string' } },
    internalNote: { type: 'string' },
  },
  required: ['summary', 'proposed'],
});

const agent = {
  automationsAgent: 1,
  agent: {
    slug: SLUG,
    name: 'Microsoft Secure Score Reviewer',
    vendor: 'CloudRadial',
    version: VERSION,
    description: "Reviews one client's Microsoft Secure Score each check-in, ranks the improvement actions by points and user impact, keeps a Planner card per open action and a Secure Score asset current in the CloudRadial portal, and proposes the fixes it can make safely.",
    category: 'Security',
    tags: ['security', 'secure-score', 'microsoft-365', 'pulsar'],
    detailsMarkdown: [
      '## What it does',
      '',
      "Built to run as one Pulsar per client. At each check-in it reads the client's Microsoft Secure Score and improvement actions, ranks the gaps, keeps a Planner card per open action and a \"Microsoft Secure Score\" flexible asset current in the client's CloudRadial portal, and proposes the user-level fixes it can make safely. Every write is a proposal until someone approves it. It learns from approvals and denials, and asks to take over a kind of fix once it has a clean record.",
      '',
      '## Setup',
      '',
      '- **Reads:** Microsoft 365 Security Posture (`microsoft-365-security`: Secure Score, improvement actions, Conditional Access, MFA registration, risky users) and Entra ID.',
      '- **The `microsoft-365-security` extension is a custom extension, not yet in the catalog.** Install it on the runner first, with the client\'s company-scoped secrets `M365-TenantID`, `M365-ClientID` and `M365-ClientSecret`.',
      '- **Writes (approval-gated):** CloudRadial Planner cards, the Microsoft Secure Score flexible asset, a monthly report in Report Archives, and three user-level fixes through Entra ID (add to the MFA group, revoke sessions, disable an inactive account).',
      '- **Never proposes:** Conditional Access changes, tenant-wide settings, licence changes, password resets, deletions, or all-user changes.',
      '- **Permissions:** SecurityEvents.Read.All is required; Policy.Read.All, AuditLog.Read.All and IdentityRiskyUser.Read.All add evidence.',
      '- **Settings:** upload the Secure Score Settings template (repo folder `secure-score-reviewer/knowledge/`) to the Pulsar\'s notes folder, with your Planner product category id and MFA enforcement group.',
    ].join('\n'),
    systemPrompt: prompt,
    model: '',
    requiredExtensionSlugs: EXTENSIONS,
    requiredSecretNames: [],
    variablesJson: '[]',
    inputSchema,
    outputSchema,
    dryRunDefault: true,
  },
};

const workflow = {
  automationsWorkflow: 1,
  name: 'Microsoft Secure Score Review',
  description: "One Secure Score check-in on demand for one client: reviews the score, ranks the gaps, and proposes Planner card, asset and fix changes, each one waiting for approval. Put the client's companyId in the Run input. The same agent runs as a Pulsar for weekly check-ins; see the secure-score-reviewer README.",
  definition: {
    schemaVersion: 1,
    activities: [
      { id: 'start', name: 'Start', type: 'start', position: { x: 100, y: 120 }, properties: { webhookEnabled: false } },
      {
        id: 'node-review', name: 'Secure Score check-in', type: 'agent', position: { x: 340, y: 120 },
        properties: {
          goal: 'Do one Secure Score check-in for the client with CloudRadial companyId {{ nodes.start.output.companyId }}: review the score and improvement actions, rank the gaps, propose Planner card and Secure Score asset updates for the top gaps, and propose at most 5 safe fixes. Every change waits for approval.',
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
      { source: 'start', target: 'node-review', sourceHandle: null },
      { source: 'node-review', target: 'end', sourceHandle: null },
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
    `# Microsoft Secure Score Reviewer agent. Generated by src/build.js: edit src/, never this file.\n# Upload on Agents > Custom. Use it in a Pulsar (see README) or in ${SLUG}.yml.\n`, agent),
  [`${SLUG}.yml`]: render(
    `# Microsoft Secure Score Review goal workflow. Generated by src/build.js: edit src/, never this file.\n`, workflow),
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
