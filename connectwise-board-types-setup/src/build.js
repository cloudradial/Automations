// Builds <folder>.yml from src/workflow.json and the step sources next to it.
// workflow.json holds the workflow with every script, goal and prompt replaced by "@file:<name>"; this pastes them back.
// Usage: node src/build.js          rewrite the .yml
//        node src/build.js --check  exit 1 if the .yml is out of date
// Edit the .ps1 and .md files in src/ (and workflow.json for wiring), never the .yml.
// Needs js-yaml: set JS_YAML_PATH (or NODE_PATH) to an existing copy, or npm install in _shared.
const fs = require('fs');
const path = require('path');

function loadYaml() {
  try { return require('js-yaml'); } catch { /* fall through */ }
  try { return require(path.join(__dirname, '..', '..', '_shared', 'node_modules', 'js-yaml')); } catch { /* fall through */ }
  if (process.env.JS_YAML_PATH) return require(process.env.JS_YAML_PATH);
  throw new Error('js-yaml not found. Set JS_YAML_PATH, or npm install in _shared.');
}

const yaml = loadYaml();
const here = __dirname;
const folder = path.basename(path.join(here, '..'));
const out = path.join(here, '..', `${folder}.yml`);
const src = JSON.parse(fs.readFileSync(path.join(here, 'workflow.json'), 'utf8'));

const paste = (v) => {
  if (typeof v === 'string' && v.startsWith('@file:')) {
    return fs.readFileSync(path.join(here, v.slice(6)), 'utf8').replace(/\r\n/g, '\n').replace(/\s+$/, '');
  }
  if (Array.isArray(v)) return v.map(paste);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, paste(x)]));
  return v;
};

const doc = { automationsWorkflow: 1, name: src.name, description: src.description, definition: paste(src.definition) };
const text = yaml.dump(doc, { lineWidth: -1, noRefs: true });

// Every JSON string property must still parse.
for (const a of doc.definition.activities) {
  for (const k of ['inputSchema', 'outputSchema', 'testInput']) {
    const v = a.properties && a.properties[k];
    if (typeof v === 'string' && v.trim()) JSON.parse(v);
  }
}
yaml.load(text);

if (process.argv.includes('--check')) {
  const cur = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : '';
  if (cur !== text) { console.error(`${folder}.yml is out of date. Run node src/build.js.`); process.exit(1); }
  console.log(`${folder}.yml is up to date.`);
} else {
  fs.writeFileSync(out, text);
  console.log(`wrote ${folder}.yml (${text.length} bytes)`);
}
