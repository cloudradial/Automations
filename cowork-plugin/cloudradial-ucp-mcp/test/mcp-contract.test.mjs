// Runs against the built plugin server (node scripts/build-purejs-server.mjs first): `npm run test:contract`.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { mkdtempSync, writeFileSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

test('MCP status is safe without native storage and key arguments are no longer accepted', async () => {
  const directory = mkdtempSync(join(tmpdir(),'cloudradial-contract-'));
  const legacyPath = join(directory,'cloudradial-ucp-mcp','credentials.json');
  mkdirSync(join(directory,'cloudradial-ucp-mcp'));
  writeFileSync(legacyPath,'{"legacy-marker":"untouched"}');
  const child = spawn(process.execPath,[fileURLToPath(new URL('../../cloudradial-ucp/server/index.mjs',import.meta.url))],{
    env:{...process.env, APPDATA:directory, XDG_CONFIG_HOME:directory,CLOUDRADIAL_PUBLIC_KEY:'',CLOUDRADIAL_PRIVATE_KEY:''}, stdio:['pipe','pipe','pipe'], windowsHide:true,
  });
  const pending = new Map(); let id = 0;
  const lines = createInterface({input:child.stdout});
  lines.on('line',line=>{const value=JSON.parse(line);pending.get(value.id)?.(value.result);pending.delete(value.id);});
  const request = (method,params)=>new Promise(resolve=>{const current=++id;pending.set(current,resolve);child.stdin.write(JSON.stringify({jsonrpc:'2.0',id:current,method,params})+'\n');});
  const timer = setTimeout(()=>child.kill(),10000);
  try {
    await request('initialize',{protocolVersion:'2024-11-05',capabilities:{},clientInfo:{name:'test',version:'1'}});
    child.stdin.write(JSON.stringify({jsonrpc:'2.0',method:'notifications/initialized'})+'\n');
    const {tools} = await request('tools/list',{});
    assert.equal(tools.length,19);
    assert.ok(tools.find(tool=>tool.name==='setup_secure_storage'));
    assert.deepEqual(tools.find(tool=>tool.name==='configure_credentials').inputSchema.properties,{});
    const response=await request('tools/call',{name:'setup_status',arguments:{}});
    const status=JSON.parse(response.content[0].text);
    if (process.platform==='win32'||process.platform==='linux') {
      assert.equal(status.keychainReady,false); assert.equal(status.legacyCredentialsDetected,true);
      assert.equal(status.configured,false); assert.equal(status.source,null);
    }
    assert.notEqual(status.source,'file');
    const rejected=await request('tools/call',{name:'configure_credentials',arguments:{public_key:'dummy',private_key:'test-secret'}});
    assert.equal(rejected.isError,true); assert.equal(JSON.stringify(rejected).includes('test-secret'),false);
    assert.equal(readFileSync(legacyPath,'utf8'),'{"legacy-marker":"untouched"}');
  } finally {clearTimeout(timer);lines.close();child.kill();await new Promise(resolve=>child.once('exit',resolve));rmSync(directory,{recursive:true,force:true});}
});
