import { createServer } from 'node:http';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { API_URLS, getStatus, installAndVerifyStorage, validateAndSaveCredentials, verifyKeychain, SetupValidationError } from './secure-storage.js';
import type { AddressInfo } from 'node:net';

function escapeHtml(value: unknown): string { return String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' } as Record<string, string>)[char]); }
function page(content: string): string {
  return `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>CloudRadial local setup</title><style>body{font:16px system-ui;background:#f2f6f7;color:#172b35;margin:0;padding:40px 20px}main{max-width:480px;margin:0 auto;padding:32px;background:white;border-radius:16px}h1{font-size:26px}p{line-height:1.5}label{display:block;margin-top:20px}input,select,button{box-sizing:border-box;width:100%;padding:12px;margin-top:8px;font:inherit}button{background:#1f7a8c;color:white;border:0;border-radius:8px;cursor:pointer}.notice{background:#eef8fa;padding:12px;border-radius:8px}</style><main>${content}</main></html>`;
}
function form(token: string, message = ''): string {
  return page(`<h1>Connect CloudRadial</h1><p>Your OS keychain has been verified. Enter API keys from <strong>Settings → API</strong> in your CloudRadial portal.</p><p class="notice">This form runs on your computer. Keys go directly to CloudRadial for validation and into your OS keychain. They are not sent to your chat.</p>${message ? `<p role="alert">${escapeHtml(message)}</p>` : ''}<form action="/credentials" method="post" autocomplete="off"><input type="hidden" name="token" value="${token}"><label>Public key<input type="password" name="public_key" required maxlength="4096" autocomplete="off" spellcheck="false"></label><label>Private key<input type="password" name="private_key" required maxlength="4096" autocomplete="new-password" spellcheck="false"></label><label>Region<select name="base_url"><option value="${API_URLS[0]}">United States</option><option value="${API_URLS[1]}">Europe</option></select></label><button type="submit">Connect</button></form><p>You can close this window to cancel.</p>`);
}

export async function openBrowser(url: string): Promise<void> {
  let executable: string, args: string[];
  if (process.platform === 'win32') {
    executable = 'powershell.exe';
    // URL is generated internally and contains only a loopback address and URL-safe nonce.
    args = ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-Command', `Start-Process '${url}'`];
  } else if (process.platform === 'darwin') { executable = 'open'; args = [url]; }
  else { executable = 'xdg-open'; args = [url]; }
  await new Promise<void>((resolve, reject) => {
    const child = spawn(executable, args, { stdio: 'ignore', windowsHide: true });
    const timer = setTimeout(() => { child.kill(); reject(new Error('Browser launch timed out.')); }, 10000);
    child.once('error', () => { clearTimeout(timer); reject(new Error('Could not open your local browser.')); });
    child.once('exit', (code: number | null) => { clearTimeout(timer); code === 0 ? resolve() : reject(new Error('Could not open your local browser.')); });
  });
}

// Export the loopback server so tests can exercise real HTTP requests without keys.
export async function startLocalSetup({
  verify = verifyKeychain as () => void,
  save = validateAndSaveCredentials as (input: Record<string, unknown>) => Promise<unknown>,
  timeoutMs = 600000,
} = {}) {
  verify(); // Fail before collecting any keys if secure storage is unavailable.
  const token = randomBytes(32).toString('base64url');
  let busy = false, completed = false;
  let timer: NodeJS.Timeout | undefined;
  const sameToken = (value: unknown): boolean => typeof value === 'string' && Buffer.byteLength(value) === Buffer.byteLength(token) && timingSafeEqual(Buffer.from(value as string), Buffer.from(token));
  const server = createServer(async (request, response) => {
    const headers: Record<string, string> = {
      'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store',
      'Referrer-Policy': 'no-referrer', 'X-Frame-Options': 'DENY', 'X-Content-Type-Options': 'nosniff',
      'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
    };
    const send = (status: number, body: string) => { response.writeHead(status, headers); response.end(body); };
    const origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
    if (request.headers.host !== origin.slice(7)) return send(403, 'Forbidden');
    const url = new URL(request.url || '/', origin);
    if (request.method === 'GET' && url.pathname === '/' && sameToken(url.searchParams.get('token'))) return send(200, form(token));
    if (request.method !== 'POST' || url.pathname !== '/credentials' || request.headers.origin !== origin || request.headers['content-type']?.split(';')[0] !== 'application/x-www-form-urlencoded') return send(403, 'Forbidden');
    let body = '';
    try {
      for await (const chunk of request) {
        body += chunk;
        if (Buffer.byteLength(body) > 20000) return send(413, 'Request too large');
      }
      const fields = new URLSearchParams(body);
      body = '';
      if (!sameToken(fields.get('token'))) return send(403, 'Forbidden');
      if (completed || busy) return send(409, 'Setup is already complete or in progress.');
      busy = true;
      verify(); // Keychain may have been locked since the form opened.
      try {
        await save({ public_key: fields.get('public_key'), private_key: fields.get('private_key'), base_url: fields.get('base_url') });
      } catch (error) {
        // Only our validation messages are shown; never reflect submitted values.
        const safeMessage = error instanceof SetupValidationError ? error.message : 'OS keychain storage failed. Credentials were not confirmed saved. Retry secure-storage setup.';
        return send(400, form(token, safeMessage));
      } finally {
        fields.delete('public_key'); fields.delete('private_key'); busy = false;
      }
      completed = true;
      send(200, page('<h1>Connected</h1><p>Your API keys were validated and saved in your OS keychain.</p><p>Close this window and return to your chat to verify the portal connection.</p>'));
      clearTimeout(timer);
      server.close();
    } catch {
      busy = false;
      send(400, 'Local setup failed. No submitted values are logged.');
    }
  });
  server.requestTimeout = 30000;
  server.headersTimeout = 10000;
  await new Promise<void>((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', () => resolve()); });
  timer = setTimeout(() => { server.closeAllConnections(); server.close(); }, timeoutMs);
  const close = () => { clearTimeout(timer); server.closeAllConnections(); server.close(); };
  return { url: `http://127.0.0.1:${(server.address() as AddressInfo).port}/?token=${token}`, server, close };
}

async function main(): Promise<void> {
  // Native storage setup happens before the browser form can accept keys.
  await installAndVerifyStorage();
  if (getStatus().source === 'env') throw new Error('Environment-variable credentials override the keychain. Remove that override in your client before using local setup.');
  const session = await startLocalSetup();
  try {
    await openBrowser(session.url);
    process.send?.({ status: 'opened', message: 'Local credential form opened. Enter keys there, then check setup_status.' });
  } catch {
    if (process.send) { session.close(); process.send({ status: 'browser_unavailable', message: 'Could not launch a local browser. Run server/setup-local.mjs from a local terminal on the desktop machine.' }); }
    else console.log('Open this address in a browser on this computer:', session.url);
  }
  process.disconnect?.();
  for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, session.close);
}

// Run only when launched as its own script (bundles that import this file must not start a form).
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1] && /setup-local\.(mjs|js)$/.test(process.argv[1])) {
  main().catch(() => {
    const message = 'Local setup could not start. Run setup_secure_storage and check OS keychain availability before entering keys.';
    if (process.send) { process.send({ status: 'failed', message }); process.disconnect(); }
    else console.error(message);
    process.exitCode = 1;
  });
}
