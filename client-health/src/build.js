// Builds the Client Health Pulsar files from src/prompt.md:
//   client-health-<psa>.agent.yml  (one custom agent per PSA)
//   client-health-<psa>.yml        (its goal workflow: run input -> agent node)
// Usage: node src/build.js          write the files
//        node src/build.js --check  exit 1 if any file is out of date
const fs = require('fs');
const path = require('path');
const yaml = require(process.env.JS_YAML_PATH || 'C:/Users/NicholasWestgate/OneDrive - Azurative/Documents/Claude/handoffs/src/node_modules/js-yaml');

const VERSION = '1.0.0';
const ROOT = path.resolve(__dirname, '..');
const FEEDBACK = 'cloudradial-v2-feedback';

const PSAS = {
  connectwise: {
    name: 'ConnectWise PSA',
    ext: 'connectwise-manage',
    gather: [
      '- Tickets, last 60 days: cw_query_tickets with conditions "dateEntered >= [<today minus 60 days, yyyy-mm-dd>]", fields "id,company/id,company/name,dateEntered,closedFlag,isInSla" and orderBy "dateEntered desc".',
      '- If that reports more than 300 records or exceeding maxPages, run it again as two windows: "dateEntered >= [<today minus 30 days>]" and "dateEntered >= [<today minus 60 days>] and dateEntered < [<today minus 30 days>]". If a window is still capped, don\'t score the volume trend or SLA this week and write a NOTE line.',
      '- Aged open tickets: cw_query_tickets with conditions "closedFlag = false and dateEntered < [<today minus 14 days>]" and fields "id,company/id,company/name,dateEntered".',
    ].join('\n'),
    sla: ' In ConnectWise, use isInSla on closed tickets (closedFlag true) only. ConnectWise counts business hours, so treat it as its own verdict and don\'t recalculate it.',
    propose: [
      '- ConnectWise: propose cw_create_activity with name "Client health follow-up: <client name>", companyId = the client, typeId = the activity type, assignToId = the account manager\'s member id, dateStart = today, and notes = the reason.',
      '- Resolve once per check-in, in parallel: the activity type with cw_query_activity_types (conditions name="<type from Knowledge, default Follow Up>"), and every account manager you need with one cw_query_members call (conditions identifier in ("a","b") or the names Knowledge gives).',
      '- If that activity type doesn\'t exist, propose cw_create_company_note instead, with companyId = the client, text = "Client health follow-up for <account manager>: <reason>" and flagged true.',
    ].join('\n'),
  },
  autotask: {
    name: 'Autotask',
    ext: 'autotask-psa',
    gather: [
      '- Tickets, last 60 days: at_query_tickets with search {"filter":[{"op":"gte","field":"createDate","value":"<today minus 60 days, ISO 8601 UTC>"}],"IncludeFields":["id","companyID","createDate","completedDate","serviceLevelAgreementHasBeenMet"]}. The search must be complete, valid JSON.',
      '- Aged open tickets: at_query_tickets with search {"filter":[{"op":"notExist","field":"completedDate"},{"op":"lt","field":"createDate","value":"<today minus 14 days>"}],"IncludeFields":["id","companyID","createDate"]}.',
      '- Client names: at_query_companies with search {"filter":[{"op":"eq","field":"isActive","value":true}],"IncludeFields":["id","companyName"]}.',
    ].join('\n'),
    sla: ' In Autotask, serviceLevelAgreementHasBeenMet true is met and false is missed. A ticket where it is empty has no SLA result.',
    propose: [
      '- Autotask: propose at_create_ticket with title "Client health follow-up: <client name>", companyID = the client, queueID = the queue Knowledge names (default "Account Management"), status = New, priority = Medium (or the one Knowledge names), dueDateTime = 3 working days from today, description = the reason, and assignedResourceID with assignedResourceRoleID for the account manager.',
      '- Resolve once per check-in, in parallel: the status, priority and queue ids with at_get_ticket_field_values, and the account managers with at_query_resources. Then get each account manager\'s role with at_query_resource_roles (filter resourceID); Autotask rejects a resource without a role it holds.',
    ].join('\n'),
  },
  halo: {
    name: 'HaloPSA',
    ext: 'halo-psa',
    gather: [
      '- Tickets, last 60 days: halo_query_tickets with startDate = today minus 60 days, endDate = today, dateSearch "dateoccurred", pageinate true and page_size 500. Each ticket carries client_id, client_name, dateoccurred, and when closed, dateclosed or datecleared and fixbydate.',
      '- If record_count is more than the rows you got, the volume trend and SLA can\'t be scored this week: write a NOTE line.',
      '- Aged open tickets: halo_query_tickets with open_only true, endDate = today minus 14 days, dateSearch "dateoccurred", pageinate true and page_size 500.',
    ].join('\n'),
    sla: ' In HaloPSA, a closed ticket met its SLA when its fixbydate is set (1900-01-01 means not set) and it was closed on or before it. A ticket without a fixbydate has no SLA result. If no ticket has these fields, skip this part and say so in a NOTE line.',
    propose: [
      '- HaloPSA: propose halo_create_ticket with summary "Client health follow-up: <client name>", details = the reason, clientId = the internal client Knowledge names (your own MSP\'s client in HaloPSA), agentId = the account manager, and tickettypeId if Knowledge names a ticket type.',
      '- Resolve once per check-in, in parallel: the account managers with halo_query_agents, the internal client with halo_query_clients if Knowledge gives a name rather than an id, and the ticket type with halo_query_ticket_types if Knowledge names one.',
    ].join('\n'),
  },
};

const lf = (s) => s.replace(/\r\n/g, '\n');
const template = lf(fs.readFileSync(path.join(__dirname, 'prompt.md'), 'utf8')).trimEnd() + '\n';

function prompt(p) {
  return template
    .replace(/\{\{PSA_NAME\}\}/g, p.name)
    .replace('{{PSA_GATHER}}', p.gather)
    .replace('{{PSA_SLA_NOTE}}', p.sla)
    .replace('{{PSA_PROPOSE}}', p.propose);
}

const INPUT_SCHEMA = JSON.stringify({ type: 'object', properties: { request: { type: 'string', description: 'What this check-in should do. Optional: limit it to named clients.' } } });
const OUTPUT_SCHEMA = JSON.stringify({
  type: 'object',
  properties: {
    scored: { type: 'number', description: 'Clients scored this check-in.' },
    proposed: { type: 'number', description: 'Follow-ups proposed.' },
    lowest: { type: 'array', items: { type: 'object', properties: { client: { type: 'string' }, score: { type: 'number' }, change: { type: 'string' } }, required: ['client', 'score'] } },
    notes: { type: 'array', items: { type: 'string' }, description: 'Anything capped, skipped or unreadable.' },
    summary: { type: 'string' },
  },
  required: ['scored', 'proposed', 'summary'],
});

function agentDoc(key, p) {
  return {
    automationsAgent: 1,
    agent: {
      slug: `client-health-${key}`,
      name: `Client Health (${p.name})`,
      vendor: 'CloudRadial',
      version: VERSION,
      description: `Weekly health score for every client from CSAT, ticket trend, SLA and aged tickets in ${p.name}; proposes an account-manager follow-up when a client slips.`,
      category: 'Client Success',
      tags: ['client-health', 'csat', 'pulsar', key],
      detailsMarkdown: [
        '## What it does',
        '',
        `Built to run as a Pulsar. Once a week it reads CloudRadial feedback and ${p.name} tickets, scores each active client from 0 to 100, and compares the score with last week's (kept in the Pulsar's notes). A client that drops 15 or more points, or sits below 60, gets one proposed follow-up for its account manager. Nothing changes until you approve the proposal.`,
        '',
        '## Setup',
        '',
        `- Install the ${p.ext} and ${FEEDBACK} extensions and fill in their secrets on the runner.`,
        '- Add the two Knowledge documents from the `knowledge/` folder (scoring and account managers) and edit them.',
        '- Create the Pulsar as the README describes.',
        '',
        'See https://github.com/cloudradial/Automations/tree/main/client-health',
      ].join('\n'),
      systemPrompt: prompt(p),
      model: '',
      requiredExtensionSlugs: [p.ext, FEEDBACK],
      requiredSecretNames: [],
      variablesJson: '[]',
      inputSchema: INPUT_SCHEMA,
      outputSchema: OUTPUT_SCHEMA,
      dryRunDefault: true,
    },
  };
}

const READ_SCRIPT = [
  '# Run input (optional): {"clients":"Contoso, Fabrikam"} limits the check-in to those clients.',
  '$ErrorActionPreference = \'Stop\'',
  'function Get-ChProp { param($o, $n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }',
  '$chIn = Get-NodeInput',
  'if ($chIn -is [string]) { $chIn = $(if ($chIn.Trim().StartsWith(\'{\')) { try { $chIn | ConvertFrom-Json } catch { $null } } else { $null }) }',
  '$chWrap = Get-ChProp $chIn \'trigger\'; if ($null -ne $chWrap) { $chIn = $chWrap }',
  '$chClients = ([string](Get-ChProp $chIn \'clients\')).Trim()',
  '$chToday = (Get-Date).ToUniversalTime().ToString(\'yyyy-MM-dd\')',
  '$chReq = "Run this week\'s client health check-in. Today is $chToday (UTC). Score the clients, compare with your notes, propose follow-ups for the clients that need one, write your notes and summarise."',
  'if ($chClients) { $chReq += " Only score these clients: $chClients." }',
  'Set-NodeOutput ([ordered]@{ status = \'success\'; request = $chReq; message = $(if ($chClients) { "Check-in limited to: $chClients" } else { \'Check-in for every active client.\' }) })',
].join('\n');

function workflowDoc(key, p) {
  return {
    automationsWorkflow: 1,
    name: `Client Health (${p.name})`,
    description: `Goal workflow for the Client Health (${p.name}) agent: one weekly check-in that scores every active client and proposes account-manager follow-ups for approval. The same agent runs as a Pulsar; use this workflow to try it by hand.`,
    definition: {
      schemaVersion: 1,
      activities: [
        { id: 'start', name: 'Start', type: 'start', position: { x: 100, y: 120 }, properties: { webhookEnabled: false } },
        {
          id: 'node-request', name: 'Read the run input', type: 'powershell-script', position: { x: 300, y: 120 },
          properties: { script: READ_SCRIPT, timeoutSeconds: 60, retryCount: 0, parameters: [], aiExtensions: [] },
        },
        {
          id: 'node-agent', name: 'Score clients and propose follow-ups', type: 'agent', position: { x: 500, y: 120 },
          properties: {
            agentSlug: `client-health-${key}`,
            goal: `Score every active client's health from CloudRadial feedback and ${p.name} tickets, compare with last week's scores in your notes, and propose one account-manager follow-up for each client that dropped 15 or more points or is below 60 (at most 10). Read the Knowledge sections "Client Health Scoring" and "Client Health Account Managers". Request: {{ nodes.node-request.output.request }}`,
            model: '',
            allowedExtensions: [p.ext, FEEDBACK],
            timeoutSeconds: 900,
            autoApprove: false,
            inputBindingsJson: JSON.stringify({ request: '{{ nodes.node-request.output.request }}' }),
            inputSchema: INPUT_SCHEMA,
            outputSchema: OUTPUT_SCHEMA,
          },
        },
        { id: 'end', name: 'End', type: 'end', position: { x: 700, y: 120 } },
      ],
      connections: [
        { source: 'start', target: 'node-request', sourceHandle: null },
        { source: 'node-request', target: 'node-agent', sourceHandle: null },
        { source: 'node-agent', target: 'end', sourceHandle: null },
      ],
      startActivityId: 'start',
    },
  };
}

function render(header, doc) {
  const text = header + yaml.dump(doc, { lineWidth: -1, noRefs: true });
  yaml.load(text);
  return text;
}

function outputs() {
  const out = {};
  for (const [key, p] of Object.entries(PSAS)) {
    out[`client-health-${key}.agent.yml`] = render(`# Client Health agent for ${p.name}. Upload on Agents > Custom (keyed on the slug).\n# Generated by src/build.js from src/prompt.md. Don't edit by hand.\n`, agentDoc(key, p));
    out[`client-health-${key}.yml`] = render(`# Client Health goal workflow for ${p.name}. Import on Workflows > Import.\n# Generated by src/build.js. Don't edit by hand.\n`, workflowDoc(key, p));
  }
  return out;
}

module.exports = { PSAS, VERSION, outputs, prompt };

if (require.main === module) {
  const check = process.argv.includes('--check');
  let stale = 0;
  for (const [name, text] of Object.entries(outputs())) {
    const file = path.join(ROOT, name);
    const cur = fs.existsSync(file) ? lf(fs.readFileSync(file, 'utf8')) : null;
    if (cur === text) continue;
    if (check) { console.log(`STALE ${name}`); stale++; } else { fs.writeFileSync(file, text); console.log(`wrote ${name}`); }
  }
  if (check) { console.log(stale ? `${stale} file(s) out of date` : 'all files current'); process.exit(stale ? 1 : 0); }
}
