// @ts-nocheck
// Secure credential setup: keychain-only storage and the local key form. Run with `npm test`.
import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { request as httpRequest } from 'node:http';
import { createCredentialStore, verifyKeychain, validateAndSaveCredentials, platformSupported, API_URLS } from '../src/secure-storage.js';
import { startLocalSetup } from '../src/setup-local.js';
import { openLocalCredentialSetup } from '../src/setup-tools.js';

function memoryKeychain() {
  const values = new Map();
  return { values, entry: (service, account) => {
    const key = `${service}/${account}`;
    return { getPassword: () => values.get(key) ?? null, setPassword: value => values.set(key, value), deletePassword: () => values.delete(key) };
  } };
}
const input = { public_key: 'dummy-public', private_key: 'dummy-private-do-not-echo', base_url: API_URLS[0] };

test('OS keychain probe leaves no credential behind', () => {
  const memory = memoryKeychain(); verifyKeychain(memory.entry); assert.equal(memory.values.size, 0);
});
test('write verification fails closed and restores the prior keychain entry', () => {
  let value = 'prior-value', writes = 0;
  const store = createCredentialStore(() => ({ getPassword: () => writes === 1 ? 'bad-readback' : value, setPassword: next => { value = next; writes++; }, deletePassword: () => { value = null; } }));
  assert.throws(() => store.write({ publicKey: 'new', privateKey: 'new' }), /No file fallback/);
  assert.equal(value, 'prior-value');
});
test('unavailable keychain throws before any file fallback', () => {
  const store = createCredentialStore(() => { throw new Error('keychain locked'); });
  assert.throws(() => store.write({}), /keychain locked/);
});
test('successful validation saves one OS-keychain entry and returns no keys', async () => {
  const memory = memoryKeychain(), store = createCredentialStore(memory.entry);
  let request;
  const result = await validateAndSaveCredentials(input, { store, fetcher: async (url, options) => { request = {url, options}; return new Response('17'); } });
  assert.equal(memory.values.size, 1);
  assert.deepEqual(store.read(), {publicKey: input.public_key, privateKey: input.private_key, baseUrl: input.base_url});
  assert.equal(request.url.hostname, 'api.us.cloudradial.com');
  assert.equal(request.options.redirect, 'error');
  assert.deepEqual(result, {success:true, source:'keychain'});
});
test('401, 403, and server failures do not overwrite saved keys', async () => {
  for (const status of [401,403,500]) {
    let writes = 0;
    await assert.rejects(validateAndSaveCredentials(input, { store:{write:()=>writes++}, fetcher: async () => new Response(input.private_key, {status}) }), new RegExp(`HTTP ${status}`));
    assert.equal(writes, 0);
  }
});
test('network errors never echo exception contents or write keys', async () => {
  let writes = 0;
  await assert.rejects(validateAndSaveCredentials(input, { store:{write:()=>writes++}, fetcher: async () => { throw new Error(input.private_key); } }), error => !error.message.includes(input.private_key));
  assert.equal(writes, 0);
});
test('unsupported API region is rejected before credentials leave the machine', async () => {
  let calls = 0;
  await assert.rejects(validateAndSaveCredentials({...input, base_url:'https://example.com'}, {fetcher:()=>calls++}), /US or EU/);
  assert.equal(calls, 0);
});
test('supported platform list covers desktop architectures and rejects unknown ones', () => {
  for (const os of ['win32','darwin','linux']) for (const arch of ['x64','arm64']) assert.equal(platformSupported(os, arch), true);
  assert.equal(platformSupported('unknown','x64'), false); assert.equal(platformSupported('darwin','ia32'), false);
});
test('no local form starts while OS storage is unavailable', async () => {
  await assert.rejects(startLocalSetup({verify:()=>{throw new Error('locked');}}), /locked/);
});
test('MCP credential tool refuses secret arguments before launch', async () => {
  await assert.rejects(openLocalCredentialSetup(input), error => !error.message.includes(input.private_key) && /local credential form/.test(error.message));
});

test('local form rejects missing token, wrong origin, and rebinding Host without saving', async () => {
  let writes = 0;
  const session = await startLocalSetup({verify:()=>{},save:async()=>writes++});
  try {
    const url = new URL(session.url), origin = url.origin;
    const response = await fetch(session.url);
    assert.equal(response.status,200); assert.equal(response.headers.get('cache-control'),'no-store');
    assert.equal((await fetch(origin)).status,403);
    const rebindingStatus = await new Promise((resolve,reject)=>{
      const req=httpRequest(session.url,{headers:{Host:'malicious.example'}},res=>{res.resume();resolve(res.statusCode);});
      req.on('error',reject);req.end();
    });
    assert.equal(rebindingStatus,403);
    const payload = new URLSearchParams({...input,token:url.searchParams.get('token')});
    assert.equal((await fetch(`${origin}/credentials`, {method:'POST',body:payload,headers:{Origin:'https://malicious.example'}})).status,403);
    payload.set('token','bad-token');
    assert.equal((await fetch(`${origin}/credentials`, {method:'POST',body:payload,headers:{Origin:origin}})).status,403);
    assert.equal(writes,0);
  } finally {session.close();}
});
test('form page lets the browser send its origin on submit (no-referrer made Chrome send Origin: null)', async () => {
  const session = await startLocalSetup({verify:()=>{},save:async()=>{}});
  try {
    const response = await fetch(session.url);
    assert.equal(response.headers.get('referrer-policy'),'same-origin');
  } finally {session.close();}
});
test('Origin null is accepted only with Sec-Fetch-Site same-origin', async () => {
  let saved = 0;
  const session = await startLocalSetup({verify:()=>{},save:async()=>{saved++;}});
  try {
    const url = new URL(session.url), body = () => new URLSearchParams({...input,token:url.searchParams.get('token')});
    assert.equal((await fetch(`${url.origin}/credentials`,{method:'POST',body:body(),headers:{Origin:'null','Sec-Fetch-Site':'cross-site'}})).status,403);
    assert.equal(saved,0);
    assert.equal((await fetch(`${url.origin}/credentials`,{method:'POST',body:body(),headers:{Origin:'null','Sec-Fetch-Site':'same-origin'}})).status,200);
    assert.equal(saved,1);
  } finally {session.close();}
});
test('local form saves directly, emits no keys, and stops listening after success', async () => {
  let saved;
  const session = await startLocalSetup({verify:()=>{},save:async data=>{saved=data;}});
  try {
    const url = new URL(session.url), closed = once(session.server,'close');
    const response = await fetch(`${url.origin}/credentials`, {method:'POST',body:new URLSearchParams({...input,token:url.searchParams.get('token')}),headers:{Origin:url.origin}});
    const html = await response.text();
    assert.equal(response.status,200); assert.deepEqual(saved,input);
    assert.equal(html.includes(input.private_key),false); assert.equal(html.includes(input.public_key),false);
    session.server.closeAllConnections(); await closed;
  } finally {session.close();}
});
test('local form conceals storage exceptions even if they contain submitted secrets', async () => {
  const session = await startLocalSetup({verify:()=>{},save:async()=>{throw new Error(input.private_key);}});
  try {
    const url = new URL(session.url);
    const response = await fetch(`${url.origin}/credentials`, {method:'POST',body:new URLSearchParams({...input,token:url.searchParams.get('token')}),headers:{Origin:url.origin}});
    assert.equal(response.status,400); assert.equal((await response.text()).includes(input.private_key),false);
  } finally {session.close();}
});
test('unused local setup sessions expire', async () => {
  const session = await startLocalSetup({verify:()=>{},save:async()=>{},timeoutMs:30});
  await once(session.server,'close'); assert.equal(session.server.listening,false);
});
