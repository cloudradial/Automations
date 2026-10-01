// Re-embeds elm.ps1 into the no-AI workflow export's "node-review" PowerShell step.
// Usage: node build-elm.js <path to endpoint-lifecycle-manager.yml>   (edited in place; defaults to ../endpoint-lifecycle-manager.yml)
const fs = require('fs');
const y = require('js-yaml');
const target = process.argv[2] || (__dirname + '/../endpoint-lifecycle-manager.yml');
const raw = fs.readFileSync(target, 'utf8').replace(/\r\n/g, '\n');
const header = raw.split('\n').filter((l) => l.startsWith('#')).join('\n');
const wf = y.load(raw);
const node = wf.definition.activities.find((a) => a.id === 'node-review');
if (!node) throw new Error('node-review step not found');
node.properties.script = fs.readFileSync(__dirname + '/elm.ps1', 'utf8').replace(/\r\n/g, '\n').trimEnd() + '\n';
const out = (header ? header + '\n' : '') + y.dump(wf, { lineWidth: -1, noRefs: true });
y.load(out);
fs.writeFileSync(target, out);
console.log('embedded elm.ps1 into', target, '|', out.length, 'bytes');
