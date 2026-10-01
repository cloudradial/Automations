// Embeds audit.ps1 (with the shared Endpoint LifeCycle Manager rules) into the "node-audit" step
// and email.ps1 into the "node-message" step of the Weekly Fleet Audit export.
// Usage: node build-audit.js <path to weekly-fleet-audit.yml>   (edited in place; defaults to ../weekly-fleet-audit.yml)
const fs = require('fs');
const y = require('js-yaml');
const read = (p) => fs.readFileSync(p, 'utf8').replace(/\r\n/g, '\n');
const target = process.argv[2] || (__dirname + '/../weekly-fleet-audit.yml');
const raw = read(target);
const header = raw.split('\n').filter((l) => l.startsWith('#')).join('\n');
const wf = y.load(raw);
const acts = wf.definition.activities;

// The shared block of elm.ps1: API helpers, date helpers and the grading rules.
const elm = read(__dirname + '/../../endpoint-lifecycle-manager/src/elm.ps1');
const shared = elm.match(/^# ---- shared: begin[^\n]*\n([\s\S]*?)^# ---- shared: end ----$/m);
if (!shared) throw new Error('shared block markers not found in elm.ps1');
const audit = read(__dirname + '/audit.ps1');
if (!audit.includes('#@@ELM_SHARED@@')) throw new Error('#@@ELM_SHARED@@ placeholder not found in audit.ps1');
const auditScript = audit.replace('#@@ELM_SHARED@@', '# ---- shared with Endpoint LifeCycle Manager (copied from elm.ps1 by build-audit.js) ----\n' + shared[1].trimEnd() + '\n# ---- end shared ----').trimEnd() + '\n';

const audNode = acts.find((a) => a.id === 'node-audit');
if (!audNode) throw new Error('node-audit step not found');
audNode.properties.script = auditScript;
const msgNode = acts.find((a) => a.id === 'node-message');
if (!msgNode) throw new Error('node-message step not found');
msgNode.properties.script = read(__dirname + '/email.ps1').trimEnd() + '\n';

const out = (header ? header + '\n' : '') + y.dump(wf, { lineWidth: -1, noRefs: true });
y.load(out);
fs.writeFileSync(target, out);
console.log('embedded audit.ps1 + email.ps1 into', target, '|', out.length, 'bytes');
