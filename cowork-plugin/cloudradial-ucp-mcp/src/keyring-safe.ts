// src/keyring-safe.ts
// Pure-JS-by-default credential storage with OPTIONAL native OS keychain.
//
// Purpose: remove the hard dependency on the @napi-rs/keyring native binary so the
// bundled server is pure JavaScript — one artifact that runs on every OS, commits to
// git cleanly (no per-platform .node files), and never crashes on launch. This is what
// makes the plugin commit-resolvable for the claude-community marketplace.
//
// Backend selection (once, at first use):
//   1. Native OS keychain — used ONLY if @napi-rs/keyring happens to resolve at runtime
//      AND a smoke test passes. The shipped plugin does NOT bundle it, so in practice
//      this path is taken only in dev, or if a user installs the module themselves.
//   2. Encrypted file store — pure JS, AES-256-GCM with a machine-derived key. The
//      default for shipped installs.
// Environment variables (CLOUDRADIAL_PUBLIC_KEY / _PRIVATE_KEY) are still read first by
// credentials.ts and bypass this module entirely.
//
// Wire-up (one line in src/credentials.ts):
//   -import { Entry } from "@napi-rs/keyring";
//   +import { Entry } from "./keyring-safe.js";
// `Entry` keeps the same synchronous API, so nothing else changes.

import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
  chmodSync,
} from "node:fs";
import { homedir, hostname, userInfo } from "node:os";
import {
  createCipheriv,
  createDecipheriv,
  randomBytes,
  scryptSync,
} from "node:crypto";

const require = createRequire(import.meta.url);

interface NativeEntryCtor {
  new (service: string, account: string): {
    getPassword(): string | null;
    setPassword(password: string): void;
    deletePassword(): boolean;
  };
}

type Backend = "native" | "file";

let backend: Backend | null = null;
let NativeEntry: NativeEntryCtor | null = null;

const PROBE_SERVICE = "cloudradial-ucp-mcp__probe";
const PROBE_ACCOUNT = "probe";

function selectBackend(): Backend {
  if (backend) return backend;
  // Native keychain is optional and never bundled. Guarded require + smoke test.
  try {
    const native = require("@napi-rs/keyring") as { Entry?: NativeEntryCtor };
    if (native && typeof native.Entry === "function") {
      const probe = new native.Entry(PROBE_SERVICE, PROBE_ACCOUNT);
      probe.getPassword(); // only a throw disqualifies native
      NativeEntry = native.Entry;
      backend = "native";
      return backend;
    }
  } catch {
    // module absent (the normal shipped case) or keychain unavailable → file store
  }
  backend = "file";
  return backend;
}

// ---- Encrypted-at-rest file store (pure JS) ----

const APP_DIR_NAME = "cloudradial-ucp-mcp";
const STATIC_SALT = "cloudradial-ucp-mcp:v1:keyring-fallback";

function configFilePath(): string {
  if (process.env.CLOUDRADIAL_CRED_FILE) return process.env.CLOUDRADIAL_CRED_FILE;
  let base: string;
  if (process.platform === "win32") {
    base = process.env.APPDATA || join(homedir(), "AppData", "Roaming");
  } else if (process.platform === "darwin") {
    base = join(homedir(), "Library", "Application Support");
  } else {
    base = process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
  }
  return join(base, APP_DIR_NAME, "credentials.json");
}

function safeUsername(): string {
  try {
    return userInfo().username || "unknown";
  } catch {
    return "unknown";
  }
}

function machineKey(): Buffer {
  const material =
    process.env.CLOUDRADIAL_CRED_SECRET ||
    `${hostname()}::${safeUsername()}::${STATIC_SALT}`;
  return scryptSync(material, STATIC_SALT, 32);
}

function encrypt(plaintext: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", machineKey(), iv);
  const enc = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${iv.toString("base64")}:${tag.toString("base64")}:${enc.toString("base64")}`;
}

function decrypt(blob: string): string {
  const [ivB64, tagB64, dataB64] = String(blob).split(":");
  const decipher = createDecipheriv(
    "aes-256-gcm",
    machineKey(),
    Buffer.from(ivB64, "base64"),
  );
  decipher.setAuthTag(Buffer.from(tagB64, "base64"));
  const dec = Buffer.concat([
    decipher.update(Buffer.from(dataB64, "base64")),
    decipher.final(),
  ]);
  return dec.toString("utf8");
}

function readStore(): Record<string, string> {
  const path = configFilePath();
  if (!existsSync(path)) return {};
  try {
    return (JSON.parse(readFileSync(path, "utf8")) as Record<string, string>) || {};
  } catch {
    return {};
  }
}

function writeStore(store: Record<string, string>): void {
  const path = configFilePath();
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(store, null, 2), "utf8");
  try {
    chmodSync(path, 0o600);
  } catch {
    // best effort on Windows / restricted filesystems
  }
}

const keyOf = (service: string, account: string) => `${service} ${account}`;

export class Entry {
  private service: string;
  private account: string;

  constructor(service: string, account: string) {
    this.service = service;
    this.account = account;
  }

  getPassword(): string | null {
    if (selectBackend() === "native") {
      return new NativeEntry!(this.service, this.account).getPassword();
    }
    const store = readStore();
    const blob = store[keyOf(this.service, this.account)];
    if (!blob) return null;
    try {
      return decrypt(blob);
    } catch {
      return null; // wrong machine key / tampered file
    }
  }

  setPassword(password: string): void {
    if (selectBackend() === "native") {
      new NativeEntry!(this.service, this.account).setPassword(password);
      return;
    }
    const store = readStore();
    store[keyOf(this.service, this.account)] = encrypt(String(password));
    writeStore(store);
  }

  deletePassword(): boolean {
    if (selectBackend() === "native") {
      return new NativeEntry!(this.service, this.account).deletePassword();
    }
    const store = readStore();
    const k = keyOf(this.service, this.account);
    if (!(k in store)) return false;
    delete store[k];
    writeStore(store);
    return true;
  }
}

/** 'native' (OS keychain) or 'file' (encrypted file store). Surface in setup_status. */
export function credentialBackend(): Backend {
  return selectBackend();
}
