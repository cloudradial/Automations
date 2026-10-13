// src/setup-local.ts
import { createServer } from "node:http";
import { randomBytes as randomBytes2, timingSafeEqual } from "node:crypto";
import { spawn as spawn2 } from "node:child_process";
import { fileURLToPath } from "node:url";

// src/secure-storage.ts
import { createRequire } from "node:module";
import { dirname, join, delimiter } from "node:path";
import { existsSync, mkdirSync, realpathSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { randomBytes } from "node:crypto";
import { spawn } from "node:child_process";
var KEYRING_VERSION = "2.1.0";
var SERVICE = "cloudradial-ucp-mcp";
var ACCOUNT = "credentials-v2";
var API_URLS = ["https://api.us.cloudradial.com", "https://api.eu.cloudradial.com"];
var SetupValidationError = class extends Error {
};
function dataDirectory(env = process.env, platform = process.platform) {
  if (platform === "win32") return join(env.APPDATA || join(homedir(), "AppData", "Roaming"), SERVICE);
  if (platform === "darwin") return join(homedir(), "Library", "Application Support", SERVICE);
  return join(env.XDG_CONFIG_HOME || join(homedir(), ".config"), SERVICE);
}
var runtimeDirectory = join(dataDirectory(), "runtime", `keyring-${KEYRING_VERSION}`);
var runtimeRequire = createRequire(join(runtimeDirectory, "package.json"));
function platformSupported(platform = process.platform, arch = process.arch) {
  return { win32: ["x64", "arm64", "ia32"], darwin: ["x64", "arm64"], linux: ["x64", "arm64", "arm", "riscv64"], freebsd: ["x64"] }[platform]?.includes(arch) === true;
}
function entryConstructor() {
  const installed = runtimeRequire("@napi-rs/keyring/package.json");
  if (installed.version !== KEYRING_VERSION) throw new Error("Unexpected keyring dependency version. Run secure-storage setup again.");
  const { Entry } = runtimeRequire("@napi-rs/keyring");
  if (typeof Entry !== "function") throw new Error("Keyring dependency did not expose Entry.");
  return Entry;
}
function nativeEntry(service, account) {
  const Entry = entryConstructor();
  return new Entry(service, account, { linux: { store: "secret-service" } });
}
function storageStatus() {
  const status = {
    platform: process.platform,
    arch: process.arch,
    keyringVersion: KEYRING_VERSION,
    keychainReady: false,
    legacyCredentialsDetected: existsSync(process.env.CLOUDRADIAL_CRED_FILE || join(dataDirectory(), "credentials.json"))
  };
  if (!platformSupported()) return { ...status, storageError: "This OS/architecture is not supported by the pinned keyring dependency." };
  try {
    nativeEntry(`${SERVICE}__probe`, "availability").getPassword();
    return { ...status, keychainReady: true };
  } catch {
    return { ...status, storageError: "OS keychain is unavailable or its native dependency is missing. Run setup_secure_storage before entering keys." };
  }
}
function createCredentialStore(makeEntry = nativeEntry) {
  const getEntry = () => makeEntry(SERVICE, ACCOUNT);
  return {
    read() {
      const payload = getEntry().getPassword();
      if (payload) {
        const data = JSON.parse(payload);
        if (!data.publicKey || !data.privateKey || !API_URLS.includes(data.baseUrl)) throw new Error("Stored credentials are invalid. Re-run local setup.");
        return data;
      }
      const publicKey = makeEntry(SERVICE, "public_key").getPassword();
      const privateKey = makeEntry(SERVICE, "private_key").getPassword();
      if (!publicKey || !privateKey) return null;
      const baseUrl = makeEntry(SERVICE, "base_url").getPassword() || API_URLS[0];
      return { publicKey, privateKey, baseUrl };
    },
    write(creds) {
      const item = getEntry();
      const previous = item.getPassword();
      const payload = JSON.stringify(creds);
      try {
        item.setPassword(payload);
        if (item.getPassword() !== payload) throw new Error("Keychain readback failed.");
      } catch {
        try {
          previous === null ? item.deletePassword() : item.setPassword(previous);
        } catch {
        }
        throw new Error("Could not save and verify credentials in the OS keychain. No file fallback was used.");
      }
    },
    clear() {
      for (const account of [ACCOUNT, "public_key", "private_key", "base_url"]) makeEntry(SERVICE, account).deletePassword();
    }
  };
}
var credentialStore = createCredentialStore();
function verifyKeychain(makeEntry = nativeEntry) {
  const item = makeEntry(`${SERVICE}__probe`, randomBytes(16).toString("hex"));
  const value = randomBytes(32).toString("hex");
  try {
    item.setPassword(value);
    if (item.getPassword() !== value) throw new Error("Keychain verification failed.");
  } finally {
    item.deletePassword();
  }
  if (item.getPassword() !== null) throw new Error("Keychain probe could not be deleted.");
}
function npmCliPath() {
  const roots = [dirname(process.execPath), ...(process.env.PATH || "").split(delimiter)];
  for (const root of roots) {
    if (!root) continue;
    for (const path of [join(root, "node_modules", "npm", "bin", "npm-cli.js"), join(root, "..", "lib", "node_modules", "npm", "bin", "npm-cli.js"), join(root, "npm")]) {
      try {
        const resolved = realpathSync(path);
        if (resolved.endsWith("npm-cli.js")) return resolved;
      } catch {
      }
    }
  }
  throw new Error("npm is required for first-time keychain setup. Install Node.js with npm, then retry.");
}
var installation;
async function installAndVerifyStorage() {
  if (installation) return installation;
  installation = (async () => {
    if (!platformSupported()) throw new Error("Unsupported OS/architecture for the pinned keyring dependency. No keys were requested.");
    try {
      verifyKeychain();
      return { ...storageStatus(), keychainVerified: true };
    } catch {
    }
    const npmCli = npmCliPath();
    mkdirSync(runtimeDirectory, { recursive: true, mode: 448 });
    writeFileSync(join(runtimeDirectory, "package.json"), JSON.stringify({ name: "cloudradial-keyring-runtime", private: true, version: "1.0.0", dependencies: { "@napi-rs/keyring": KEYRING_VERSION } }, null, 2));
    await new Promise((resolve, reject) => {
      const child = spawn(process.execPath, [npmCli, "install", "--prefix", runtimeDirectory, "--registry=https://registry.npmjs.org", "--ignore-scripts", "--include=optional", "--omit=dev", "--no-audit", "--no-fund", "--fetch-retries=0", "--fetch-timeout=30000"], { stdio: "ignore", windowsHide: true });
      const timer = setTimeout(() => {
        child.kill();
        reject(new Error("Keyring installation timed out. No keys were requested."));
      }, 12e4);
      child.once("error", () => {
        clearTimeout(timer);
        reject(new Error("Could not start npm for keyring setup."));
      });
      child.once("exit", (code) => {
        clearTimeout(timer);
        code === 0 ? resolve() : reject(new Error("Keyring dependency installation failed. Check npm/network access and retry."));
      });
    });
    try {
      verifyKeychain();
    } catch {
      throw new Error("Native keyring installed, but OS keychain write/read/delete verification failed. Unlock your keychain; Linux requires a running Secret Service and D-Bus session. No keys were requested or saved.");
    }
    return { ...storageStatus(), keychainVerified: true };
  })();
  try {
    return await installation;
  } finally {
    installation = void 0;
  }
}
function loadCredentials(env = process.env) {
  if (env.CLOUDRADIAL_PUBLIC_KEY && env.CLOUDRADIAL_PRIVATE_KEY) return { source: "env", creds: { publicKey: env.CLOUDRADIAL_PUBLIC_KEY, privateKey: env.CLOUDRADIAL_PRIVATE_KEY, baseUrl: env.CLOUDRADIAL_BASE_URL || API_URLS[0] } };
  try {
    const creds = credentialStore.read();
    return creds ? { source: "keychain", creds } : null;
  } catch {
    return null;
  }
}
function getStatus() {
  const loaded = loadCredentials();
  return { configured: !!loaded, source: loaded?.source || null, baseUrl: loaded?.creds.baseUrl || null, publicKeyHint: loaded ? loaded.creds.publicKey.slice(-4) : null, ...storageStatus() };
}
async function validateAndSaveCredentials(input, { fetcher = fetch, store = credentialStore } = {}) {
  const publicKey = typeof input.public_key === "string" ? input.public_key.trim() : "";
  const privateKey = typeof input.private_key === "string" ? input.private_key.trim() : "";
  const baseUrl = typeof input.base_url === "string" && input.base_url ? input.base_url : API_URLS[0];
  if (!publicKey || !privateKey || publicKey.includes(":") || /[\r\n]/.test(publicKey + privateKey)) throw new SetupValidationError("Enter valid public and private API keys.");
  if (!API_URLS.includes(baseUrl)) throw new SetupValidationError("Select the US or EU CloudRadial API region.");
  let response;
  try {
    response = await fetcher(new URL("/v2/odata/company/$count", baseUrl), { method: "GET", headers: { Authorization: "Basic " + Buffer.from(`${publicKey}:${privateKey}`).toString("base64"), Accept: "application/json" }, redirect: "error", signal: AbortSignal.timeout(2e4) });
  } catch {
    throw new SetupValidationError("Could not reach the CloudRadial API. No credentials were saved.");
  }
  if (!response.ok) throw new SetupValidationError(`CloudRadial validation failed (HTTP ${response.status}). Check both keys and region. No credentials were saved.`);
  await response.body?.cancel();
  store.write({ publicKey, privateKey, baseUrl });
  return { success: true, source: "keychain" };
}

// src/setup-local.ts
function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
}
function page(content) {
  return `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>CloudRadial local setup</title><style>body{font:16px system-ui;background:#f2f6f7;color:#172b35;margin:0;padding:40px 20px}main{max-width:480px;margin:0 auto;padding:32px;background:white;border-radius:16px}h1{font-size:26px}p{line-height:1.5}label{display:block;margin-top:20px}input,select,button{box-sizing:border-box;width:100%;padding:12px;margin-top:8px;font:inherit}button{background:#1f7a8c;color:white;border:0;border-radius:8px;cursor:pointer}.notice{background:#eef8fa;padding:12px;border-radius:8px}</style><main>${content}</main></html>`;
}
function form(token, message = "") {
  return page(`<h1>Connect CloudRadial</h1><p>Your OS keychain has been verified. Enter API keys from <strong>Settings \u2192 API</strong> in your CloudRadial portal.</p><p class="notice">This form runs on your computer. Keys go directly to CloudRadial for validation and into your OS keychain. They are not sent to your chat.</p>${message ? `<p role="alert">${escapeHtml(message)}</p>` : ""}<form action="/credentials" method="post" autocomplete="off"><input type="hidden" name="token" value="${token}"><label>Public key<input type="password" name="public_key" required maxlength="4096" autocomplete="off" spellcheck="false"></label><label>Private key<input type="password" name="private_key" required maxlength="4096" autocomplete="new-password" spellcheck="false"></label><label>Region<select name="base_url"><option value="${API_URLS[0]}">United States</option><option value="${API_URLS[1]}">Europe</option></select></label><button type="submit">Connect</button></form><p>You can close this window to cancel.</p>`);
}
async function openBrowser(url) {
  let executable, args;
  if (process.platform === "win32") {
    executable = "powershell.exe";
    args = ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", `Start-Process '${url}'`];
  } else if (process.platform === "darwin") {
    executable = "open";
    args = [url];
  } else {
    executable = "xdg-open";
    args = [url];
  }
  await new Promise((resolve, reject) => {
    const child = spawn2(executable, args, { stdio: "ignore", windowsHide: true });
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error("Browser launch timed out."));
    }, 1e4);
    child.once("error", () => {
      clearTimeout(timer);
      reject(new Error("Could not open your local browser."));
    });
    child.once("exit", (code) => {
      clearTimeout(timer);
      code === 0 ? resolve() : reject(new Error("Could not open your local browser."));
    });
  });
}
async function startLocalSetup({
  verify = verifyKeychain,
  save = validateAndSaveCredentials,
  timeoutMs = 6e5
} = {}) {
  verify();
  const token = randomBytes2(32).toString("base64url");
  let busy = false, completed = false;
  let timer;
  const sameToken = (value) => typeof value === "string" && Buffer.byteLength(value) === Buffer.byteLength(token) && timingSafeEqual(Buffer.from(value), Buffer.from(token));
  const server = createServer(async (request, response) => {
    const headers = {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Referrer-Policy": "same-origin",
      "X-Frame-Options": "DENY",
      "X-Content-Type-Options": "nosniff",
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
    };
    const send = (status, body2) => {
      response.writeHead(status, headers);
      response.end(body2);
    };
    const origin = `http://127.0.0.1:${server.address().port}`;
    if (request.headers.host !== origin.slice(7)) return send(403, "Forbidden");
    const url = new URL(request.url || "/", origin);
    if (request.method === "GET" && url.pathname === "/" && sameToken(url.searchParams.get("token"))) return send(200, form(token));
    const sameOrigin = request.headers.origin === origin || request.headers.origin === "null" && request.headers["sec-fetch-site"] === "same-origin";
    if (request.method !== "POST" || url.pathname !== "/credentials" || !sameOrigin || request.headers["content-type"]?.split(";")[0] !== "application/x-www-form-urlencoded") return send(403, "Forbidden");
    let body = "";
    try {
      for await (const chunk of request) {
        body += chunk;
        if (Buffer.byteLength(body) > 2e4) return send(413, "Request too large");
      }
      const fields = new URLSearchParams(body);
      body = "";
      if (!sameToken(fields.get("token"))) return send(403, "Forbidden");
      if (completed || busy) return send(409, "Setup is already complete or in progress.");
      busy = true;
      verify();
      try {
        await save({ public_key: fields.get("public_key"), private_key: fields.get("private_key"), base_url: fields.get("base_url") });
      } catch (error) {
        const safeMessage = error instanceof SetupValidationError ? error.message : "OS keychain storage failed. Credentials were not confirmed saved. Retry secure-storage setup.";
        return send(400, form(token, safeMessage));
      } finally {
        fields.delete("public_key");
        fields.delete("private_key");
        busy = false;
      }
      completed = true;
      send(200, page("<h1>Connected</h1><p>Your API keys were validated and saved in your OS keychain.</p><p>Close this window and return to your chat to verify the portal connection.</p>"));
      clearTimeout(timer);
      server.close();
    } catch {
      busy = false;
      send(400, "Local setup failed. No submitted values are logged.");
    }
  });
  server.requestTimeout = 3e4;
  server.headersTimeout = 1e4;
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => resolve());
  });
  timer = setTimeout(() => {
    server.closeAllConnections();
    server.close();
  }, timeoutMs);
  const close = () => {
    clearTimeout(timer);
    server.closeAllConnections();
    server.close();
  };
  return { url: `http://127.0.0.1:${server.address().port}/?token=${token}`, server, close };
}
async function main() {
  await installAndVerifyStorage();
  if (getStatus().source === "env") throw new Error("Environment-variable credentials override the keychain. Remove that override in your client before using local setup.");
  const session = await startLocalSetup();
  try {
    await openBrowser(session.url);
    process.send?.({ status: "opened", message: "Local credential form opened. Enter keys there, then check setup_status." });
  } catch {
    if (process.send) {
      session.close();
      process.send({ status: "browser_unavailable", message: "Could not launch a local browser. Run server/setup-local.mjs from a local terminal on the desktop machine." });
    } else console.log("Open this address in a browser on this computer:", session.url);
  }
  process.disconnect?.();
  for (const signal of ["SIGINT", "SIGTERM"]) process.once(signal, session.close);
}
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1] && /setup-local\.(mjs|js)$/.test(process.argv[1])) {
  main().catch(() => {
    const message = "Local setup could not start. Run setup_secure_storage and check OS keychain availability before entering keys.";
    if (process.send) {
      process.send({ status: "failed", message });
      process.disconnect();
    } else console.error(message);
    process.exitCode = 1;
  });
}
export {
  openBrowser,
  startLocalSetup
};
