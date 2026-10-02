// Checks the PSA blocks are current, pulls each PowerShell step out of the two workflows, and
// runs the strict-mode harnesses in tests/ against them (mocked runner, Key Vault, Graph and PSAs).
// Usage: node test.js   (needs pwsh and js-yaml; set JS_YAML_PATH if js-yaml isn't installed here)
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
let y;
try { y = require('js-yaml'); } catch { y = require(process.env.JS_YAML_PATH); }

const here = __dirname;
const root = path.join(here, '..');
execFileSync(process.execPath, [path.join(here, 'build.js'), '--check'], { stdio: 'inherit' });

const out = fs.mkdtempSync(path.join(os.tmpdir(), 'nuo-'));
const direct = y.load(fs.readFileSync(path.join(root, 'new-user-onboarding-direct.yml'), 'utf8'));
for (const a of direct.definition.activities) if (a.properties && a.properties.script) fs.writeFileSync(path.join(out, `node-${a.id}.ps1`), a.properties.script);
const agent = y.load(fs.readFileSync(path.join(root, 'new-user-onboarding.yml'), 'utf8'));
const byId = Object.fromEntries(agent.definition.activities.map((a) => [a.id, a]));
fs.writeFileSync(path.join(out, 'agentwf-inputs.ps1'), byId['node-inputs'].properties.script);
fs.writeFileSync(path.join(out, 'agentwf-test.json'), byId['node-inputs'].properties.testInput);
fs.writeFileSync(path.join(out, 'agentwf-note.ps1'), byId['node-note'].properties.script);

let failed = false;
for (const t of ['test-direct.ps1', 'test-psa.ps1']) {
  console.log(`--- ${t}`);
  try { execFileSync('pwsh', ['-NoProfile', '-File', path.join(here, 'tests', t)], { stdio: 'inherit', env: { ...process.env, NUO_NODE_DIR: out } }); }
  catch { failed = true; }
}
fs.rmSync(out, { recursive: true, force: true });
process.exit(failed ? 1 : 0);
