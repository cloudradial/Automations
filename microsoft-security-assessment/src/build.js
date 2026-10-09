// Builds ../microsoft-security-assessment.yml from the step scripts. common.ps1 is inlined into steps 2 and 3.
//   npm install, then: node build.js [output.yml]
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const read = f => fs.readFileSync(path.join(__dirname, f), 'utf8').replace(/\r\n/g, '\n').replace(/[ \t]+$/gm, '');
const withCommon = f => {
  const src = read(f);
  if (!src.includes('#{{COMMON}}\n')) throw new Error(`${f} has no #{{COMMON}} line`);
  return src.replace('#{{COMMON}}\n', read('common.ps1'));
};
const step = (id, name, x, script, extra = {}) => ({
  id, name, type: 'powershell-script', position: { x, y: 100 },
  properties: { script, timeoutSeconds: 600, retryCount: 0, parameters: [], aiExtensions: [], ...extra },
});

const doc = {
  automationsWorkflow: 1,
  name: 'Microsoft Security Assessment',
  definition: {
    schemaVersion: 1,
    activities: [
      { id: 'start', name: 'Start', type: 'start', position: { x: 100, y: 100 }, properties: { webhookEnabled: false } },
      // No binding: this step reads the run input from the Run dialog or a Routine.
      step('review-m365-security', 'Review Microsoft 365 security', 320, read('1-review.ps1'), {
        testInput: '{"companyName":"Contoso","mode":"plan"}',
      }),
      // No binding: each step receives the previous step's output.
      step('create-cloudradial-assessment', 'Create CloudRadial assessment', 560, withCommon('2-assessment.ps1')),
      step('create-assessment-run', 'Create assessment run (in development)', 800, withCommon('3-run.ps1')),
      { id: 'end', name: 'End', type: 'end', position: { x: 1040, y: 100 } },
    ],
    connections: [
      { source: 'start', target: 'review-m365-security', sourceHandle: null },
      { source: 'review-m365-security', target: 'create-cloudradial-assessment', sourceHandle: null },
      { source: 'create-cloudradial-assessment', target: 'create-assessment-run', sourceHandle: null },
      { source: 'create-assessment-run', target: 'end', sourceHandle: null },
    ],
    startActivityId: 'start',
  },
};

const out = yaml.dump(doc, { lineWidth: -1, noRefs: true });
const back = yaml.load(out);
for (const a of back.definition.activities) {
  if (a.properties && a.properties.script) {
    const src = doc.definition.activities.find(x => x.id === a.id).properties.script;
    if (a.properties.script !== src) throw new Error(`script round-trip mismatch in ${a.id}`);
  }
}
if (!/script: \|/.test(out)) throw new Error('scripts did not dump as literal blocks');
const target = process.argv[2] || path.join(__dirname, '..', 'microsoft-security-assessment.yml');
fs.writeFileSync(target, out);
console.log(`wrote ${target} (${out.length} bytes, ${back.definition.activities.length} activities)`);
