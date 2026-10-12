import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { ChildProcess } from 'node:child_process';
import { installAndVerifyStorage, getStatus } from './secure-storage.js';

let active: ChildProcess | undefined;

// The bundle ships setup-local.mjs next to index.mjs; a tsc build emits setup-local.js.
function setupScript(): string {
  const bundled = fileURLToPath(new URL('./setup-local.mjs', import.meta.url));
  return existsSync(bundled) ? bundled : fileURLToPath(new URL('./setup-local.js', import.meta.url));
}
export async function openLocalCredentialSetup(args: Record<string, unknown> = {}): Promise<{ status: string; message: string }> {
  if ('public_key' in args || 'private_key' in args) throw new Error('Do not send API keys through chat or MCP arguments. Use the local credential form.');
  if (active?.exitCode === null) return { status: 'already_open', message: 'Finish or close the existing local credential form.' };
  if (getStatus().source === 'env') throw new Error('Your client supplies environment-variable credentials. Those override the keychain; remove the override before local setup.');
  await installAndVerifyStorage();
  const child = spawn(process.execPath, [setupScript()], { stdio: ['ignore', 'ignore', 'ignore', 'ipc'], windowsHide: true });
  active = child;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { child.kill(); reject(new Error('Local setup launch timed out. No API keys were requested in chat.')); }, 25000);
    child.once('message', (message: any) => {
      clearTimeout(timer);
      child.unref();
      // No credentials or form URL are returned through MCP.
      resolve({ status: message.status, message: message.message });
    });
    child.once('error', () => { clearTimeout(timer); reject(new Error('Could not launch the local setup process.')); });
    child.once('exit', () => { active = undefined; clearTimeout(timer); reject(new Error('Local setup closed before launch completed.')); });
  });
}
