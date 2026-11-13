#!/usr/bin/env node
// Builds the Dispatch Queue agents and goal workflows, one of each per PSA, from src/prompt.md
// and the PSA sections below. Edit the sources, then run:  node dispatch-queue/src/build.js
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

const VERSION = '1.0.0';
const ROOT = path.resolve(__dirname, '..');
const prompt = fs.readFileSync(path.join(__dirname, 'prompt.md'), 'utf8').replace(/\r\n/g, '\n');
const snapshot = JSON.parse(fs.readFileSync(path.join(__dirname, 'tools-snapshot.json'), 'utf8'));

const PSA = {
  connectwise: {
    name: 'ConnectWise PSA',
    label: 'ConnectWise',
    techWord: 'member',
    read: [
      'Turn 1, in parallel:',
      '- cw_query_tickets with conditions `closedFlag = false AND owner/id = null AND dateEntered > [<14 days ago, YYYY-MM-DDT00:00:00Z>]`, adding `AND board/name in ("<board>","<board>")` when the rules list boards; orderBy `dateEntered asc`; fields `id,summary,board,status,priority,company,owner,resources,dateEntered,requiredDate,slaStatus`. Keep the first 30. Skip any ticket whose resources field names someone: it is already being worked.',
      '- cw_query_members with conditions `inactiveFlag = false`. Match the Dispatch Team names or emails to identifier, firstName lastName or primaryEmail.',
      'Turn 2:',
      '- cw_query_tickets with conditions `closedFlag = false AND owner/identifier in ("<id>","<id>")` for the matched members; fields `id,owner`. Count the open tickets per owner: that is each technician\'s load.',
      'Due time is requiredDate when set; otherwise use the time in slaStatus if it shows one. Priority is priority/name.',
    ].join('\n'),
    write: '- cw_update_ticket with ticketId and ownerId (the member\'s numeric id). Change nothing else.',
    note: 'If the why-note is on, also propose cw_create_ticket_note with ticketId, text (the reason, starting "Dispatch Queue:"), internalAnalysisFlag true, detailDescriptionFlag false and resolutionFlag false.',
  },
  autotask: {
    name: 'Autotask',
    label: 'Autotask',
    techWord: 'resource',
    read: [
      'Turn 1, in parallel:',
      '- at_query_tickets with search `{"filter":[{"op":"noteq","field":"status","value":5},{"op":"notExist","field":"assignedResourceID"},{"op":"gte","field":"createDate","value":"<14 days ago, ISO 8601>"}],"IncludeFields":["id","ticketNumber","title","companyID","queueID","priority","status","createDate","dueDateTime","assignedResourceID"]}`, adding `{"op":"in","field":"queueID","value":[<ids>]}` when the rules list queues. Keep the 30 oldest. Status 5 is Complete; if the field values show Complete under another id, use that id.',
      '- at_get_ticket_field_values, for the priority, queue and status labels.',
      '- at_query_resources with search `{"filter":[{"op":"eq","field":"isActive","value":true}]}`. Match the Dispatch Team names or emails to firstName lastName, userName or email.',
      'Turn 2, in parallel:',
      '- at_query_tickets with search `{"filter":[{"op":"noteq","field":"status","value":5},{"op":"in","field":"assignedResourceID","value":[<matched resource ids>]}],"IncludeFields":["id","assignedResourceID"]}`. Count the open tickets per resource: that is each technician\'s load.',
      '- at_query_resource_roles with search `{"filter":[{"op":"in","field":"resourceID","value":[<matched resource ids>]},{"op":"eq","field":"isActive","value":true}]}`.',
      '- Only when the VIP Clients document lists clients: at_query_companies with search `{"filter":[{"op":"in","field":"id","value":[<companyIDs from the tickets>]}],"IncludeFields":["id","companyName"]}`.',
      'Due time is dueDateTime. Every search must be complete, valid JSON.',
    ].join('\n'),
    write: '- at_update_ticket with id, assignedResourceID and assignedResourceRoleID. Take the role from at_query_resource_roles for that resource: the row whose queueID matches the ticket\'s queue, otherwise its first active row. Never use a role the resource doesn\'t hold. Change nothing else. If Autotask rejects it for a missing work type, don\'t guess a billing code: report it and ask which work type to use.',
    note: 'If the why-note is on, read at_get_entity_field_values with entity TicketNotes once, and propose at_create_ticket_note with ticketId, title "Dispatch Queue", description (the reason), noteType (the value labelled "Task Notes", or the first active one) and publish (a value whose label contains "Internal"). If no publish value contains "Internal", propose no notes and say so.',
  },
  halo: {
    name: 'HaloPSA',
    label: 'Halo',
    techWord: 'agent',
    read: [
      'Turn 1, in parallel:',
      '- halo_query_tickets with open_only true, agentId 0, dateSearch "dateoccurred", startDate <14 days ago, ISO 8601>, order "dateoccurred", orderdesc false, pageinate true and page_size 30. Keep only tickets whose agent_id is 0 or empty. Add teamId when the rules name one team.',
      '- halo_query_agents (with teamId when the rules name one team). Match the Dispatch Team names or emails to name or email.',
      '- halo_query_priorities.',
      'Turn 2:',
      '- halo_query_tickets with open_only true, pageinate true and page_size 200 (and teamId when the rules name one team). Count the open tickets per agent_id for the matched agents: that is each technician\'s load.',
      'Due time is fixbydate when set, otherwise deadlinedate. The client is client_name.',
    ].join('\n'),
    write: '- halo_update_ticket with id, agentId and forceReassign true. Change nothing else.',
    note: 'If the why-note is on, read halo_query_outcomes once, and propose halo_add_action with ticketId, note (the reason, starting "Dispatch Queue:"), isPrivate true and the outcomeId of the private note outcome. Never set sendEmail.',
  },
};

const outputSchema = JSON.stringify({
  type: 'object',
  properties: {
    summary: { type: 'string', description: 'The check-in summary: next best ticket per technician, then the counts.' },
    nextBest: { type: 'array', items: { type: 'object', properties: { technician: { type: 'string' }, ticket: { type: 'string' }, summary: { type: 'string' }, score: { type: 'number' } } }, description: 'One row per dispatch-team technician.' },
    proposed: { type: 'integer', description: 'Assignments proposed this check-in.' },
    unassignedLeft: { type: 'integer', description: 'Unassigned tickets not proposed.' },
    defaultsUsed: { type: 'array', items: { type: 'string' }, description: 'Settings taken from a default because a document was missing.' },
  },
  required: ['summary', 'proposed'],
});
const inputSchema = JSON.stringify({ type: 'object', properties: { goal: { type: 'string', description: 'Optional extra instruction for this check-in.' } } });

function systemPrompt(p) {
  return prompt
    .replace(/\{\{PSA_NAME\}\}/g, p.name)
    .replace(/\{\{TECH_WORD\}\}/g, p.techWord)
    .replace('{{PSA_READ}}', p.read)
    .replace('{{PSA_WRITE}}', p.write)
    .replace('{{PSA_NOTE}}', p.note);
}

function agentDoc(key) {
  const p = PSA[key];
  const s = snapshot[key];
  return {
    automationsAgent: 1,
    agent: {
      slug: `dispatch-queue-${key}`,
      name: `Dispatch Queue (${p.label})`,
      vendor: 'CloudRadial',
      version: VERSION,
      description: `Ranks unassigned ${p.name} tickets, shows each technician's next best ticket, and proposes assignments for approval.`,
      category: 'Ticketing',
      tags: ['dispatch', 'ticketing', 'pulsar', key],
      detailsMarkdown: [
        '## What it does',
        '',
        `Built for a Pulsar. At each check-in it reads the unassigned open tickets in ${p.name}, the dispatch team and each technician's open-ticket load. It ranks the tickets by fixed rules (SLA, priority, VIP client, age), lists each technician's next best ticket, and proposes up to 8 assignments. Every assignment is a proposal: nothing changes until someone approves it.`,
        '',
        '## Setup',
        '',
        `- Needs the ${s.slug} extension, installed and working on the runner.`,
        '- Upload the Dispatch Rules, Dispatch Team and VIP Clients documents (templates in the repo folder `dispatch-queue/knowledge/`) to the Knowledge folder you pick as the Pulsar\'s notes folder.',
        '- Without a Dispatch Team document it proposes nothing: it ranks the tickets and asks who dispatches.',
        '- See the dispatch-queue README for the full Pulsar setup.',
      ].join('\n'),
      systemPrompt: systemPrompt(p),
      model: '',
      requiredExtensionSlugs: [s.slug],
      requiredSecretNames: [],
      variablesJson: '[]',
      inputSchema,
      outputSchema,
      dryRunDefault: true,
    },
  };
}

function workflowDoc(key) {
  const p = PSA[key];
  const s = snapshot[key];
  return {
    automationsWorkflow: 1,
    name: `Dispatch Queue (${p.label})`,
    description: `One Dispatch Queue check-in on demand for ${p.name}: ranks the unassigned tickets, lists each technician's next best ticket and proposes assignments, each one waiting for approval. The same agent runs as a Pulsar for standing check-ins; see the dispatch-queue README.`,
    definition: {
      schemaVersion: 1,
      activities: [
        { id: 'start', name: 'Start', type: 'start', position: { x: 100, y: 120 }, properties: { webhookEnabled: false } },
        {
          id: 'node-dispatch', name: 'Dispatch check-in', type: 'agent', position: { x: 340, y: 120 },
          properties: {
            goal: 'Do one Dispatch Queue check-in: read the unassigned open tickets, the dispatch team and their open-ticket load, rank the tickets by the rules, list each technician\'s next best ticket, and propose at most 8 assignments. Every change waits for approval.',
            model: '',
            allowedExtensions: [s.slug],
            timeoutSeconds: 600,
            autoApprove: false,
            agentSlug: `dispatch-queue-${key}`,
            inputSchema,
            outputSchema,
            inputBindingsJson: '{}',
          },
        },
        { id: 'end', name: 'End', type: 'end', position: { x: 580, y: 120 } },
      ],
      connections: [
        { source: 'start', target: 'node-dispatch', sourceHandle: null },
        { source: 'node-dispatch', target: 'end', sourceHandle: null },
      ],
      startActivityId: 'start',
    },
  };
}

function render(header, doc) {
  const body = yaml.dump(doc, { lineWidth: -1, noRefs: true, quotingType: '"' });
  yaml.load(body);
  return header + body;
}

const files = {};
for (const key of Object.keys(PSA)) {
  files[`dispatch-queue-${key}.agent.yml`] = render(
    `# Dispatch Queue agent for ${PSA[key].name}. Generated by src/build.js: edit src/, never this file.\n# Upload on Agents > Custom. Use it in a Pulsar (see README) or in dispatch-queue-${key}.yml.\n`,
    agentDoc(key));
  files[`dispatch-queue-${key}.yml`] = render(
    `# Dispatch Queue goal workflow for ${PSA[key].name}. Generated by src/build.js: edit src/, never this file.\n`,
    workflowDoc(key));
}

const check = process.argv.includes('--check');
let stale = 0;
for (const [name, text] of Object.entries(files)) {
  const f = path.join(ROOT, name);
  const cur = fs.existsSync(f) ? fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n') : null;
  if (check) { if (cur !== text) { console.log(`STALE ${name}`); stale++; } }
  else if (cur !== text) { fs.writeFileSync(f, text); console.log(`wrote ${name}`); }
}
if (check) { console.log(stale ? `${stale} file(s) out of date` : 'current'); process.exit(stale ? 1 : 0); }
