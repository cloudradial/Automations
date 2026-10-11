// Credential storage: OS keychain only, through a pinned @napi-rs/keyring that
// setup installs per OS/CPU into a per-user runtime cache (not bundled).
import { createRequire } from 'node:module';
import { dirname, join, delimiter } from 'node:path';
import { existsSync, mkdirSync, realpathSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { randomBytes } from 'node:crypto';
import { spawn } from 'node:child_process';

export const KEYRING_VERSION = '2.1.0';
const SERVICE = 'cloudradial-ucp-mcp';
const ACCOUNT = 'credentials-v2';
export const API_URLS = ['https://api.us.cloudradial.com', 'https://api.eu.cloudradial.com'];
export class SetupValidationError extends Error {}

export function dataDirectory(env: NodeJS.ProcessEnv = process.env, platform: string = process.platform): string {
  if (platform === 'win32') return join(env.APPDATA || join(homedir(), 'AppData', 'Roaming'), SERVICE);
  if (platform === 'darwin') return join(homedir(), 'Library', 'Application Support', SERVICE);
  return join(env.XDG_CONFIG_HOME || join(homedir(), '.config'), SERVICE);
}

// Keep downloaded binaries outside the portable plugin and outside synced workspaces.
export const runtimeDirectory = join(dataDirectory(), 'runtime', `keyring-${KEYRING_VERSION}`);
const runtimeRequire = createRequire(join(runtimeDirectory, 'package.json'));

export function platformSupported(platform: string = process.platform, arch: string = process.arch): boolean {
  return ({ win32: ['x64', 'arm64', 'ia32'], darwin: ['x64', 'arm64'], linux: ['x64', 'arm64', 'arm', 'riscv64'], freebsd: ['x64'] } as Record<string, string[]>)[platform]?.includes(arch) === true;
}

function entryConstructor() {
  const installed = runtimeRequire('@napi-rs/keyring/package.json');
  if (installed.version !== KEYRING_VERSION) throw new Error('Unexpected keyring dependency version. Run secure-storage setup again.');
  const { Entry } = runtimeRequire('@napi-rs/keyring');
  if (typeof Entry !== 'function') throw new Error('Keyring dependency did not expose Entry.');
  return Entry;
}

export interface KeychainEntry { getPassword(): string | null; setPassword(value: string): void; deletePassword(): unknown }
export type EntryFactory = (service: string, account: string) => KeychainEntry;
export interface Credentials { publicKey: string; privateKey: string; baseUrl: string }

function nativeEntry(service: string, account: string): KeychainEntry {
  const Entry = entryConstructor();
  // Require persistent Secret Service on Linux; never fall back to volatile keyutils.
  return new Entry(service, account, { linux: { store: 'secret-service' } });
}

export function storageStatus() {
  const status: Record<string, unknown> = {
    platform: process.platform, arch: process.arch, keyringVersion: KEYRING_VERSION,
    keychainReady: false, legacyCredentialsDetected: existsSync(process.env.CLOUDRADIAL_CRED_FILE || join(dataDirectory(), 'credentials.json')),
  };
  if (!platformSupported()) return { ...status, storageError: 'This OS/architecture is not supported by the pinned keyring dependency.' };
  try {
    nativeEntry(`${SERVICE}__probe`, 'availability').getPassword();
    return { ...status, keychainReady: true };
  } catch {
    return { ...status, storageError: 'OS keychain is unavailable or its native dependency is missing. Run setup_secure_storage before entering keys.' };
  }
}

export function createCredentialStore(makeEntry: EntryFactory = nativeEntry) {
  const getEntry = () => makeEntry(SERVICE, ACCOUNT);
  return {
    read(): Credentials | null {
      const payload = getEntry().getPassword();
      if (payload) {
        const data = JSON.parse(payload);
        if (!data.publicKey || !data.privateKey || !API_URLS.includes(data.baseUrl)) throw new Error('Stored credentials are invalid. Re-run local setup.');
        return data;
      }
      // Compatibility with credentials already saved in the OS keychain by older builds.
      const publicKey = makeEntry(SERVICE, 'public_key').getPassword();
      const privateKey = makeEntry(SERVICE, 'private_key').getPassword();
      if (!publicKey || !privateKey) return null;
      const baseUrl = makeEntry(SERVICE, 'base_url').getPassword() || API_URLS[0];
      return { publicKey, privateKey, baseUrl };
    },
    write(creds: Credentials): void {
      const item = getEntry();
      const previous = item.getPassword();
      const payload = JSON.stringify(creds);
      try {
        item.setPassword(payload);
        if (item.getPassword() !== payload) throw new Error('Keychain readback failed.');
      } catch {
        try { previous === null ? item.deletePassword() : item.setPassword(previous); } catch {}
        throw new Error('Could not save and verify credentials in the OS keychain. No file fallback was used.');
      }
    },
    clear() {
      for (const account of [ACCOUNT, 'public_key', 'private_key', 'base_url']) makeEntry(SERVICE, account).deletePassword();
    },
  };
}

export const credentialStore = createCredentialStore();

export function verifyKeychain(makeEntry: EntryFactory = nativeEntry): void {
  const item = makeEntry(`${SERVICE}__probe`, randomBytes(16).toString('hex'));
  const value = randomBytes(32).toString('hex');
  try {
    item.setPassword(value);
    if (item.getPassword() !== value) throw new Error('Keychain verification failed.');
  } finally {
    item.deletePassword();
  }
  if (item.getPassword() !== null) throw new Error('Keychain probe could not be deleted.');
}

function npmCliPath(): string {
  const roots = [dirname(process.execPath), ...(process.env.PATH || '').split(delimiter)];
  for (const root of roots) {
    if (!root) continue;
    for (const path of [join(root, 'node_modules', 'npm', 'bin', 'npm-cli.js'), join(root, '..', 'lib', 'node_modules', 'npm', 'bin', 'npm-cli.js'), join(root, 'npm')]) {
      try { const resolved = realpathSync(path); if (resolved.endsWith('npm-cli.js')) return resolved; } catch {}
    }
  }
  throw new Error('npm is required for first-time keychain setup. Install Node.js with npm, then retry.');
}

let installation: Promise<Record<string, unknown>> | undefined;
export async function installAndVerifyStorage(): Promise<Record<string, unknown>> {
  if (installation) return installation;
  installation = (async () => {
    if (!platformSupported()) throw new Error('Unsupported OS/architecture for the pinned keyring dependency. No keys were requested.');
    try { verifyKeychain(); return { ...storageStatus(), keychainVerified: true }; } catch {}
    const npmCli = npmCliPath();
    mkdirSync(runtimeDirectory, { recursive: true, mode: 0o700 });
    // npm chooses the optional native package for this OS/CPU/libc. No lifecycle scripts.
    writeFileSync(join(runtimeDirectory, 'package.json'), JSON.stringify({ name: 'cloudradial-keyring-runtime', private: true, version: '1.0.0', dependencies: { '@napi-rs/keyring': KEYRING_VERSION } }, null, 2));
    await new Promise<void>((resolve, reject) => {
      const child = spawn(process.execPath, [npmCli, 'install', '--prefix', runtimeDirectory, '--registry=https://registry.npmjs.org', '--ignore-scripts', '--include=optional', '--omit=dev', '--no-audit', '--no-fund', '--fetch-retries=0', '--fetch-timeout=30000'], { stdio: 'ignore', windowsHide: true });
      const timer = setTimeout(() => { child.kill(); reject(new Error('Keyring installation timed out. No keys were requested.')); }, 120000);
      child.once('error', () => { clearTimeout(timer); reject(new Error('Could not start npm for keyring setup.')); });
      child.once('exit', (code: number | null) => { clearTimeout(timer); code === 0 ? resolve() : reject(new Error('Keyring dependency installation failed. Check npm/network access and retry.')); });
    });
    try { verifyKeychain(); } catch {
      throw new Error('Native keyring installed, but OS keychain write/read/delete verification failed. Unlock your keychain; Linux requires a running Secret Service and D-Bus session. No keys were requested or saved.');
    }
    return { ...storageStatus(), keychainVerified: true };
  })();
  try { return await installation; } finally { installation = undefined; }
}

export function loadCredentials(env: NodeJS.ProcessEnv = process.env): { source: 'env' | 'keychain'; creds: Credentials } | null {
  if (env.CLOUDRADIAL_PUBLIC_KEY && env.CLOUDRADIAL_PRIVATE_KEY) return { source: 'env', creds: { publicKey: env.CLOUDRADIAL_PUBLIC_KEY, privateKey: env.CLOUDRADIAL_PRIVATE_KEY, baseUrl: env.CLOUDRADIAL_BASE_URL || API_URLS[0] } };
  try { const creds = credentialStore.read(); return creds ? { source: 'keychain', creds } : null; } catch { return null; }
}

export function getStatus(): Record<string, unknown> {
  const loaded = loadCredentials();
  return { configured: !!loaded, source: loaded?.source || null, baseUrl: loaded?.creds.baseUrl || null, publicKeyHint: loaded ? loaded.creds.publicKey.slice(-4) : null, ...storageStatus() };
}

export function clearKeychain(): void { credentialStore.clear(); }

export async function validateAndSaveCredentials(
  input: Record<string, unknown>,
  { fetcher = fetch as (url: URL, init: RequestInit) => Promise<Response>, store = credentialStore as { write(creds: Credentials): void } } = {},
) {
  const publicKey = typeof input.public_key === 'string' ? input.public_key.trim() : '';
  const privateKey = typeof input.private_key === 'string' ? input.private_key.trim() : '';
  const baseUrl = typeof input.base_url === 'string' && input.base_url ? input.base_url : API_URLS[0];
  if (!publicKey || !privateKey || publicKey.includes(':') || /[\r\n]/.test(publicKey + privateKey)) throw new SetupValidationError('Enter valid public and private API keys.');
  if (!API_URLS.includes(baseUrl)) throw new SetupValidationError('Select the US or EU CloudRadial API region.');
  let response: Response;
  try {
    response = await fetcher(new URL('/v2/odata/company/$count', baseUrl), { method: 'GET', headers: { Authorization: 'Basic ' + Buffer.from(`${publicKey}:${privateKey}`).toString('base64'), Accept: 'application/json' }, redirect: 'error', signal: AbortSignal.timeout(20000) });
  } catch { throw new SetupValidationError('Could not reach the CloudRadial API. No credentials were saved.'); }
  if (!response.ok) throw new SetupValidationError(`CloudRadial validation failed (HTTP ${response.status}). Check both keys and region. No credentials were saved.`);
  // Discard API bodies instead of reflecting anything into the local form or chat.
  await response.body?.cancel();
  store.write({ publicKey, privateKey, baseUrl });
  return { success: true, source: 'keychain' };
}
