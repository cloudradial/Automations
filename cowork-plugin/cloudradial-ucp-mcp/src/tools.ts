import { mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";
import { homedir } from "node:os";
import { createHash } from "node:crypto";
import { callApi, callApiForm, callApiMultipart, CloudRadialApiError, RESOURCE_MAP, escapeODataString } from "./cloudradial-client.js";
import { buildAssessmentXlsx } from "./xlsx.js";
import { clearKeychain, getStatus, installAndVerifyStorage } from "./secure-storage.js";
import { openLocalCredentialSetup } from "./setup-tools.js";

const RESOURCE_TYPES = Object.keys(RESOURCE_MAP);

export interface ToolDefinition {
  name: string;
  description: string;
  inputSchema: {
    type: "object";
    properties: Record<string, unknown>;
    required?: string[];
    additionalProperties?: boolean;
  };
  handler: (args: Record<string, unknown>) => Promise<unknown>;
}

function str(args: Record<string, unknown>, key: string): string | undefined {
  const v = args[key];
  if (v === undefined || v === null) return undefined;
  return String(v);
}

function requireStr(args: Record<string, unknown>, key: string): string {
  const v = str(args, key);
  if (!v) throw new Error(`Missing required parameter: ${key}`);
  return v;
}

// Single-item endpoints that take a companyId query parameter in the v2 spec.
// Without it, /v2/catalogquestion/{id} answers 404 "Catalog question not found"
// for a question that exists (AAI-126).
const COMPANY_SCOPED = new Set([
  "catalog_question",
  "course_lesson",
  "course_lesson_history",
  "domain",
  "user",
  "application_user",
  "token",
  "dashboard",
  "portal_message",
  "archive_folder",
  "license",
  "policy",
]);

// OData key for the types whose companyId can be looked up when the caller
// doesn't pass company_id. user and application_user share the User entity.
const ODATA_KEY: Record<string, { set: string; key: string; quoted?: boolean }> = {
  catalog_question: { set: "catalogquestion", key: "companyCatalogQuestionId" },
  course_lesson: { set: "courselesson", key: "courseLessonId" },
  domain: { set: "domain", key: "companyDomainId" },
  user: { set: "user", key: "userId", quoted: true },
  application_user: { set: "user", key: "userId", quoted: true },
  // No single-item GET in the API: get_resource reads these through OData.
  assessment: { set: "assessment", key: "assessmentId" },
  course_enrollment: { set: "courseenrollment", key: "courseEnrollmentId" },
  dashboard: { set: "dashboard", key: "dashboardId" },
  portal_message: { set: "message", key: "messageId" },
  archive_folder: { set: "archivefolder", key: "companyReportFolderId" },
  license: { set: "license", key: "licenseId" },
  policy: { set: "policy", key: "companyPolicyId" },
};

// Methods whose route takes no ?companyId= even though the type's other single-item routes do.
const NO_COMPANY_QUERY: Record<string, string[]> = {
  archive_folder: ["PATCH"],
  policy: ["PUT"],
  license: ["PUT"],
};

// Types that control access, security or partner-wide behaviour. create/update/delete_resource
// refuse to write them until the caller passes confirmed=true after showing the user the change.
const SENSITIVE = new Set(["role", "role_assignment", "feature_set", "policy", "webhook", "license", "archive_folder_default"]);
function requireConfirmed(resourceType: string, action: string, args: Record<string, unknown>): void {
  if (SENSITIVE.has(resourceType) && args.confirmed !== true) {
    throw new Error(
      `${action} on ${resourceType} changes access, security or partner-wide settings. Show the user exactly what will change (read the current record first), then call again with confirmed=true. Nothing was changed.`
    );
  }
}

// /v2/odata/user answers HTTP 500 whenever supportPin is in the row (live, 2026-10-07:
// every other field reads fine on its own), so user reads select every field but
// supportPin, and not the `company` navigation property, unless the caller chooses.
const USER_SELECT =
  "userId,email,firstName,lastName,userName,phoneNumber,companyId,displayName,department,title,country," +
  "streetAddress,city,state,postalCode,mobilePhone,isDeleted,dateCreated,dateModified,psaKey,psaSiteKey," +
  "psaChildAccountKey";

/** First OData row whose key equals `id`, or undefined. `select` limits the fields read. */
async function odataByKey(resourceType: string, id: string, select?: string): Promise<Record<string, unknown> | undefined> {
  const k = ODATA_KEY[resourceType];
  if (!k) return undefined;
  if (!k.quoted && !/^\d+$/.test(id)) throw new Error(`${resourceType} id must be a number, got "${id}"`);
  const value = k.quoted ? `'${id.replace(/'/g, "''")}'` : id;
  const r = await callApi("GET", `/v2/odata/${k.set}`, {
    $filter: `${k.key} eq ${value}`,
    $top: "1",
    $select: select ?? (k.set === "user" ? USER_SELECT : undefined),
  });
  const rows = (r.data as { value?: unknown })?.value ?? r.data;
  return Array.isArray(rows) ? (rows[0] as Record<string, unknown> | undefined) : undefined;
}

/**
 * The `{ companyId }` query for a get/update/delete on one item, or undefined.
 * Uses `company_id` when given. Otherwise looks the item up through OData
 * (which works unscoped) to find its companyId, so a list-then-get flow works
 * without the caller knowing the company.
 */
async function itemCompanyQuery(
  resourceType: string,
  args: Record<string, unknown>,
  id?: string
): Promise<Record<string, string> | undefined> {
  if (!COMPANY_SCOPED.has(resourceType)) return undefined;
  const given = str(args, "company_id");
  if (given !== undefined && given !== "") return { companyId: given };
  if (id && ODATA_KEY[resourceType]) {
    try {
      const row = await odataByKey(resourceType, id, `${ODATA_KEY[resourceType].key},companyId`);
      if (row && row.companyId !== undefined && row.companyId !== null) return { companyId: String(row.companyId) };
    } catch {
      // Fall through: the item call itself reports the real error.
    }
  }
  return undefined;
}

// endpoint_custom_property is addressed by the endpoint's serial number and the property name.
function customPropertyPath(args: Record<string, unknown>, withName: boolean): string {
  const serial = encodeURIComponent(requireStr(args, "serial_number"));
  if (!withName) return `/v2/endpoint/${serial}/custom-property`;
  const name = str(args, "property_name") || str(args, "id");
  if (!name) throw new Error("Missing required parameter: property_name");
  return `/v2/endpoint/${serial}/custom-property/${encodeURIComponent(name)}`;
}

// Operations the v2 API doesn't have for a type. Checked before calling so the
// caller gets a clear reason, not a bare 404/405.
const NOT_IN_API: Record<string, { put?: string; patch?: string; delete?: string }> = {
  flexible_asset: { put: "flexible_asset has no PUT; use PATCH (the default)." },
  flexible_asset_type: { put: "flexible_asset_type has no PUT; use PATCH (the default)." },
  flexible_asset_field: {
    put: "The API can't update a flexible_asset_field. Create a new field instead.",
    patch: "The API can't update a flexible_asset_field. Create a new field instead.",
    delete: "The API can't delete a flexible_asset_field.",
  },
  course_enrollment: {
    put: "course_enrollment has no PUT; use PATCH (the default).",
  },
  archive_folder: { put: "archive_folder has no PUT; use PATCH (the default)." },
  role_assignment: {
    put: "Role assignments can't be edited. Delete the assignment and create a new one.",
    patch: "Role assignments can't be edited. Delete the assignment and create a new one.",
  },
  webhook: { patch: "webhook has no PATCH; use method PUT with the full body (header values left empty are kept), or webhook_action action=update." },
  archive_folder_default: { patch: "archive_folder_default has no PATCH; use method PUT with the full body." },
  article_feedback: { patch: "article_feedback is changed with method PUT and data {rating} only." },
};

// Types whose writes go through a dedicated tool instead of create/update/delete_resource.
const WRITE_TOOL: Record<string, string> = {
  signal_message:
    "Signal messages are sent, edited, resolved and retracted with the signal_message tool, which previews the audience before anything is sent.",
  assessment_question: "assessment_question is read-only here. Change questions with assessment_lifecycle (set_questions, update_question, delete_question, set_answers) or assessment_import.",
  signal_device: "Signal devices are reset, revoked and unrevoked with the signal_device tool.",
  user_license: "user_license is read-only. Assign license users with access_control action=set_license_users.",
};

// Types whose create goes through a dedicated tool (update/delete stay generic).
const CREATE_TOOL: Record<string, string> = {
  webhook: "Create webhooks with webhook_action (action=create): the signing secret is shown only once, so the tool saves it to a local file instead of returning it into the chat.",
};

const ASSESSMENT_HINT =
  "Assessments are written with assessment_lifecycle (create, set_questions, update_question, delete_question, set_answers) or assessment_import (questions from a list or .xlsx). Read one with get_resource, list_resources or assessment_lifecycle action=get.";

const COMPANY_ID_PARAM = {
  type: "string",
  description:
    "Company the item belongs to, sent as ?companyId=. Used by catalog_question, course_lesson, course_lesson_history, domain, user, application_user, token, dashboard, portal_message and archive_folder; looked up automatically if omitted (except course_lesson_history and token). For company_group_company it is the path key instead.",
};

const CONFIRMED_PARAM = {
  type: "boolean",
  description:
    "Required (true) to write role, role_assignment, feature_set, policy, webhook, license and archive_folder_default, after the user has seen and approved the exact change.",
};

const CUSTOM_PROPERTY_PARAMS = {
  serial_number: { type: "string", description: "endpoint_custom_property: the endpoint's serial number" },
  property_name: { type: "string", description: "endpoint_custom_property: the property name" },
};

const CONTENT_TYPES: Record<string, string> = {
  pdf: "application/pdf", csv: "text/csv", txt: "text/plain", htm: "text/html", html: "text/html",
  json: "application/json", xml: "application/xml", zip: "application/zip",
  png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif",
  doc: "application/msword", xls: "application/vnd.ms-excel", ppt: "application/vnd.ms-powerpoint",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  eml: "message/rfc822", msg: "application/vnd.ms-outlook",
};
function contentTypeFor(path: string): string {
  const ext = (path.split(".").pop() ?? "").toLowerCase();
  return CONTENT_TYPES[ext] ?? "application/octet-stream";
}

/** The archive folder to upload to: by id (checked against the company), or by name, created if asked. */
async function resolveArchiveFolder(
  companyId: number,
  args: Record<string, unknown>
): Promise<{ id: number; name: string; created: boolean }> {
  const given = str(args, "archive_id");
  if (given) {
    // GET with companyId answers 404 when the folder isn't this company's, so a
    // file never lands in another client's archive.
    const f = (await callApi("GET", `/v2/archivefolder/${encodeURIComponent(given)}`, { companyId: String(companyId) })).data as Record<string, unknown>;
    return { id: Number(given), name: String(f?.name ?? ""), created: false };
  }
  const name = str(args, "folder_name");
  if (!name) throw new Error("Give archive_id or folder_name.");
  const list = await callApi("GET", "/v2/odata/archivefolder", {
    $filter: `companyId eq ${companyId}`,
    $select: "companyReportFolderId,companyId,name",
    $top: "200",
  });
  const rows = (((list.data as { value?: unknown })?.value ?? []) as Record<string, unknown>[]);
  const hit = rows.find((f) => String(f.name ?? "").trim().toLowerCase() === name.trim().toLowerCase());
  if (hit) return { id: Number(hit.companyReportFolderId), name: String(hit.name), created: false };
  if (args.create_folder !== true) {
    const names = rows.map((f) => f.name).join(", ") || "none";
    throw new Error(`Company ${companyId} has no archive folder named "${name}". Its folders: ${names}. Set create_folder=true to create it.`);
  }
  const body: Record<string, unknown> = { companyId, name: name.trim() };
  if (str(args, "category")) body.category = str(args, "category");
  if (str(args, "alert_keywords")) body.alertKeywords = str(args, "alert_keywords");
  if (str(args, "required_keywords")) body.requiredKeywords = str(args, "required_keywords");
  if (args.warn_on_past_days !== undefined) body.warnOnPastDays = Number(args.warn_on_past_days);
  if (args.retain_for_days !== undefined) body.retainForDays = Number(args.retain_for_days);
  const created = (await callApi("POST", "/v2/archivefolder", undefined, body)).data as Record<string, unknown>;
  const newId = created?.archiveFolderId ?? created?.companyReportFolderId ?? created?.id;
  if (newId === undefined || newId === null) throw new Error(`Created folder "${name}", but the response had no folder id: ${JSON.stringify(created).slice(0, 200)}`);
  return { id: Number(newId), name: name.trim(), created: true };
}

function checkSignalContent(b: Record<string, unknown>): void {
  const title = b.title === undefined || b.title === null ? "" : String(b.title);
  if (!title.trim()) throw new Error("title is required.");
  if (title.length > 200) throw new Error("title must be 200 characters or less.");
  if (b.body && String(b.body).length > 2000) throw new Error("body must be 2,000 characters or less.");
  if (b.deepLinkUrl && !/^https:\/\/\S+$/i.test(String(b.deepLinkUrl))) throw new Error("deep_link_url must be an absolute https:// URL.");
  if (b.deepLinkLabel && String(b.deepLinkLabel).length > 100) throw new Error("deep_link_label must be 100 characters or less.");
  const p = b.priority === undefined || b.priority === null ? 0 : Number(b.priority);
  if (![0, 1, 2].includes(p)) throw new Error("priority must be 0 (info), 1 (important) or 2 (urgent).");
  if (p > 0 && !b.expiresAt) throw new Error("Important and urgent messages need expires_at.");
  if (b.expiresAt) {
    const t = Date.parse(String(b.expiresAt));
    if (isNaN(t)) throw new Error("expires_at must be an ISO 8601 date-time.");
    if (t - Date.now() > 90 * 86400000) throw new Error("expires_at can be at most 90 days ahead.");
  }
}

/** POST /v2/signalmessage body from tool args, validated, with an automatic dedupe key. */
function signalPublishBody(args: Record<string, unknown>): Record<string, unknown> {
  const arr = (k: string) => (Array.isArray(args[k]) ? (args[k] as unknown[]) : undefined);
  const companyIds = arr("company_ids")?.map(Number);
  const groupIds = arr("group_ids")?.map(Number);
  const users = arr("user_ids")?.map(String);
  const roles = arr("role_ids")?.map(String);
  const all = args.all_companies === true;
  if (!all && !(companyIds?.length) && !(groupIds?.length)) {
    throw new Error("Choose who gets it: company_ids, group_ids or all_companies=true.");
  }
  if ((users?.length ?? 0) > 500 || (roles?.length ?? 0) > 500) throw new Error("user_ids and role_ids are limited to 500 each.");
  if (args.deep_link_label && !args.deep_link_url) throw new Error("deep_link_label needs deep_link_url.");
  const body: Record<string, unknown> = {
    ...(companyIds?.length ? { companyIds } : {}),
    ...(groupIds?.length ? { groupIds } : {}),
    ...(all ? { allCompanies: true } : {}),
    ...(users?.length ? { users } : {}),
    ...(roles?.length ? { roles } : {}),
    title: str(args, "title"),
    ...(str(args, "body") ? { body: str(args, "body") } : {}),
    priority: args.priority === undefined || args.priority === null ? 0 : Number(args.priority),
    ...(str(args, "expires_at") ? { expiresAt: str(args, "expires_at") } : {}),
    ...(str(args, "due_at") ? { dueAt: str(args, "due_at") } : {}),
    ...(str(args, "scheduled_send_at") ? { scheduledSendAt: str(args, "scheduled_send_at") } : {}),
    ...(str(args, "deep_link_url") ? { deepLinkUrl: str(args, "deep_link_url") } : {}),
    ...(str(args, "deep_link_label") ? { deepLinkLabel: str(args, "deep_link_label") } : {}),
    ...(args.ack_required === true ? { ackRequired: true } : {}),
  };
  checkSignalContent(body);
  const day = new Date().toISOString().slice(0, 10);
  body.dedupeKey = str(args, "dedupe_key") ||
    "ucp-" + createHash("sha256").update(JSON.stringify(body) + day).digest("hex").slice(0, 40);
  if (String(body.dedupeKey).length > 200) throw new Error("dedupe_key must be 200 characters or less.");
  return body;
}

/** Every user_license row for one license (all pages), for reads and for the set_license_users preview. */
async function licenseHolders(licenseId: string): Promise<Record<string, unknown>[]> {
  if (!/^\d+$/.test(licenseId)) throw new Error("license_id must be a number.");
  const r = await listAllPages("/v2/odata/userlicense", { $filter: `licenseId eq ${licenseId}` }, 20000);
  return (Array.isArray(r) ? r : ((r as { value?: unknown[] }).value ?? [])) as Record<string, unknown>[];
}

/** Webhook headers for create/update. Values come from a local JSON file so secrets stay out of chat. */
function webhookHeaders(args: Record<string, unknown>, cur: Record<string, unknown>): { name: string; value: string }[] {
  let values: Record<string, unknown> = {};
  const file = str(args, "header_values_file");
  if (file) {
    try { values = JSON.parse(readFileSync(file, "utf8")); } catch { throw new Error(`header_values_file must be a readable JSON file of {name: value}: ${file}`); }
    if (!values || typeof values !== "object" || Array.isArray(values)) throw new Error("header_values_file must hold a JSON object of {name: value}.");
  }
  const curNames = Array.isArray(cur.headers) ? (cur.headers as Record<string, unknown>[]).map((h) => String(h.name)) : [];
  const names = Array.isArray(args.header_names) ? (args.header_names as unknown[]).map(String) : [...new Set([...curNames, ...Object.keys(values)])];
  return names.map((name) => {
    const v = values[name];
    if (v === undefined && !curNames.includes(name)) throw new Error(`Header "${name}" is new, so it needs a value in header_values_file.`);
    return { name, value: v === undefined ? "" : String(v) }; // "" keeps the stored value
  });
}

/**
 * The API shows a webhook's signing secret only once (create, rotate-secret). Save it to a
 * private file on this computer and return the path, so the secret never enters the chat.
 */
function saveSigningSecret(data: unknown): unknown {
  const d = (data ?? {}) as { action?: Record<string, unknown>; signingSecret?: unknown };
  if (!d.signingSecret) return { action: d.action ?? data, signingSecret: "(none returned)" };
  const dir = join(homedir(), ".cloudradial-ucp", "webhook-secrets");
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const id = String(d.action?.actionId ?? "new");
  const file = join(dir, `webhook-${id}-${new Date().toISOString().replace(/[:.]/g, "-")}.txt`);
  writeFileSync(file, String(d.signingSecret) + "\n", { mode: 0o600 });
  return {
    action: d.action,
    signingSecretSavedTo: file,
    note: "The signing secret is shown only once. It was saved to this file on your computer (readable only by you). Copy it into the receiving system, then delete the file.",
  };
}

/** Validates one assessment question for create/set_questions; the v2 routes accept only types 0 and 80. */
function checkQuestion(q: Record<string, unknown>): Record<string, unknown> {
  if (!q || typeof q !== "object") throw new Error("Each question must be an object.");
  if (!q.label || !String(q.label).trim()) throw new Error("Each question needs a label.");
  if (q.type !== undefined && !["0", "80"].includes(String(q.type))) {
    throw new Error(`Question type must be 0 (free text) or 80 (multiple choice); got ${String(q.type)}.`);
  }
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(q)) {
    if (k === "answerOptions" && Array.isArray(v)) out[k] = v.map((o: any) => ({ label: String(o.label), value: String(o.value) }));
    else out[k] = v === null || v === undefined || typeof v === "string" ? v : String(v);
  }
  return out;
}

/** companyId of an assessment (any type), read through OData; throws if it doesn't exist. */
async function assessmentCompany(id: string, given?: string): Promise<string> {
  if (given) return given;
  // No $select: it has returned HTTP 500 on assessments (see assessment_import).
  const row = await odataByKey("assessment", id);
  if (!row) throw new Error(`Assessment ${id} not found.`);
  return String(row.companyId);
}

async function deleteAssessment(args: Record<string, unknown>): Promise<unknown> {
  const id = requireStr(args, "id");
  if (!/^\d+$/.test(id)) throw new Error(`assessment id must be a number, got "${id}"`);
  const companyId = await assessmentCompany(id, str(args, "company_id"));
  const query: Record<string, string> = { companyId };
  if (args.include_runs === true) query.includeRuns = "true";
  const r = await callApi("DELETE", `/v2/assessment/${id}`, query);
  return r.data ?? { deleted: true, assessmentId: Number(id), runsDeleted: args.include_runs === true };
}

const PAGE = 200;

/**
 * Every row of an OData list. Follows @odata.nextLink exactly as returned when the
 * API sends one; otherwise walks $skip in pages of 200 until a short page. Stops at
 * maxRecords and reports that it did, so a caller never mistakes a cut-off for "all".
 */
async function listAllPages(
  path: string,
  query: Record<string, string | undefined>,
  maxRecords: number
): Promise<unknown> {
  if (!Number.isFinite(maxRecords) || maxRecords < 1) throw new Error("max_records must be a positive number.");
  const rows: unknown[] = [];
  let next: string | undefined = path;
  let q: Record<string, string | undefined> | undefined = { ...query, $top: String(PAGE), $skip: "0" };
  let pages = 0;
  while (next) {
    const r = await callApi("GET", next, q);
    const body = r.data as { value?: unknown[]; "@odata.nextLink"?: string };
    const page = Array.isArray(body?.value) ? body.value : [];
    rows.push(...page);
    pages++;
    if (rows.length >= maxRecords) {
      const more = page.length === PAGE || !!body?.["@odata.nextLink"];
      return more
        ? { value: rows.slice(0, maxRecords), truncated: true, note: `Stopped at max_records=${maxRecords}; more rows match. Narrow the filter or raise max_records.` }
        : rows.slice(0, maxRecords);
    }
    if (body?.["@odata.nextLink"]) {
      next = body["@odata.nextLink"];
      q = undefined; // nextLink already carries the query
    } else if (page.length === PAGE && q) {
      q = { ...q, $skip: String(Number(q.$skip ?? 0) + PAGE) };
    } else {
      next = undefined;
    }
    if (pages > 500) throw new Error("Paging stopped after 500 pages; narrow the filter.");
  }
  return rows;
}

function requireResource(args: Record<string, unknown>) {
  const resourceType = requireStr(args, "resource_type");
  const config = RESOURCE_MAP[resourceType];
  if (!config) {
    throw new Error(
      `Unknown resource_type: ${resourceType}. Valid: ${RESOURCE_TYPES.join(", ")}`
    );
  }
  return { resourceType, config };
}

export const tools: ToolDefinition[] = [
  // -------------------------------------------------------------------------
  // Setup / credential management tools: call these first
  // -------------------------------------------------------------------------
  {
    name: "setup_status",
    description:
      "Check whether CloudRadial is configured. Returns configured, source (env or keychain), region, public-key suffix, platform, architecture, keychainReady, and legacyCredentialsDetected. Never returns API keys. If secure storage is missing, run setup_secure_storage, then configure_credentials to open the LOCAL form. Never collect keys through chat.",
    inputSchema: {
      type: "object",
      properties: {},
    },
    handler: async () => getStatus(),
  },

  {
    name: "setup_secure_storage",
    description:
      "Detect OS/CPU, install the pinned native keyring dependency for this machine, and verify a temporary OS-keychain write/read/delete. Run before requesting any credentials. Downloads from npm; never uses a credential-file fallback.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    handler: async () => installAndVerifyStorage(),
  },

  {
    name: "configure_credentials",
    description:
      "Open a local browser form after OS-keychain verification. The user enters API keys locally; they are validated directly with CloudRadial and saved in the OS keychain. Takes NO API keys as arguments. Never ask the user to paste keys into chat. Check setup_status after the user finishes.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    handler: async (args) => openLocalCredentialSetup(args),
  },

  {
    name: "clear_credentials",
    description:
      "Delete CloudRadial credentials from the OS keychain. Environment-variable overrides and legacy encrypted files are unaffected.",
    inputSchema: {
      type: "object",
      properties: {},
    },
    handler: async () => {
      clearKeychain();
      return { success: true, status: getStatus() };
    },
  },

  // -------------------------------------------------------------------------
  // CloudRadial API tools
  // -------------------------------------------------------------------------
  {
    name: "search_companies",
    description:
      "Search CloudRadial companies by (partial) name. Returns companyId, name, psaIdentifier, and endpointCount (top 50).",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Name fragment to search for (case-insensitive)" },
      },
      required: ["name"],
    },
    handler: async (args) => {
      const name = requireStr(args, "name");
      const filter = `contains(tolower(name), '${escapeODataString(name)}')`;
      const result = await callApi("GET", "/v2/odata/company", {
        $filter: filter,
        $select: "companyId,name,psaIdentifier,endpointCount",
        $top: "50",
      });
      // Unwrap OData envelope ({"@odata.context": ..., "value": [...]}) so
      // callers get the array its description promises.
      return (result.data as { value?: unknown })?.value ?? result.data;
    },
  },

  {
    name: "company_overview",
    description:
      "Full snapshot of a company: details, user count, endpoint count, 5 most recent articles, 5 most recent feedback items.",
    inputSchema: {
      type: "object",
      properties: {
        company_id: { type: "string", description: "CloudRadial company ID" },
      },
      required: ["company_id"],
    },
    handler: async (args) => {
      const companyId = requireStr(args, "company_id");
      const [company, users, endpoints, articles, feedback] = await Promise.all([
        callApi("GET", `/v2/company/${companyId}`),
        callApi("GET", "/v2/odata/user/$count", { $filter: `companyId eq ${companyId}` }),
        callApi("GET", "/v2/odata/endpoint/$count", { $filter: `companyId eq ${companyId}` }),
        callApi("GET", "/v2/odata/article", {
          $filter: `companyId eq ${companyId}`,
          $orderby: "dateCreated desc",
          $top: "5",
        }),
        callApi("GET", "/v2/odata/feedback", {
          $filter: `companyId eq ${companyId}`,
          $orderby: "dateCreated desc",
          $top: "5",
        }),
      ]);

      return {
        company: company.data,
        counts: {
          userCount: users.data,
          endpointCount: endpoints.data,
        },
        recentArticles: (articles.data as { value?: unknown })?.value ?? articles.data,
        recentFeedback: (feedback.data as { value?: unknown })?.value ?? feedback.data,
      };
    },
  },

  {
    name: "list_resources",
    description:
      "List any listable resource type with OData filtering, sorting, and pagination. One page by default: top=100 if not specified, and the API caps a page at 200. " +
      "To read every matching row, set all_pages=true: the tool follows @odata.nextLink (or walks $skip) in pages of 200 until done or max_records (default 5000) is reached, and says so if it stopped early. " +
      "Otherwise page with `skip`, or pair with `count_resources` for the total. application_user has no OData listing; use get_resource.",
    inputSchema: {
      type: "object",
      properties: {
        resource_type: { type: "string", enum: RESOURCE_TYPES },
        filter:  { type: "string", description: "OData $filter expression" },
        select:  { type: "string", description: "OData $select (comma-separated field list)" },
        orderby: { type: "string", description: "OData $orderby (e.g. 'dateCreated desc')" },
        top:     { type: "string", description: "OData $top: page size. Defaults to 100, max 200." },
        skip:    { type: "string", description: "OData $skip: offset for pagination (use with top to walk pages)." },
        expand:  { type: "string", description: "OData $expand" },
        search:  { type: "string", description: "OData $search" },
        all_pages: { type: "boolean", description: "Read every matching row (pages of 200) instead of one page. Ignores top and skip." },
        params: { type: "object", description: "For types without OData (role, role_assignment, feature_set, webhook, archive_folder_default, signal_device): the route's own query parameters, e.g. {userId, companyId, page, pageSize} for role_assignment." },
        max_records: { type: "integer", description: "With all_pages: stop after this many rows (default 5000)." },
      },
      required: ["resource_type"],
    },
    handler: async (args) => {
      const { resourceType, config } = requireResource(args);
      if (!config.odataPath && config.listPath) {
        if (str(args, "filter") || str(args, "orderby") || str(args, "select")) {
          throw new Error(`${resourceType} has no OData list: pass its own query parameters in params instead of filter/orderby/select.`);
        }
        const p = (args.params as Record<string, unknown>) || {};
        const q = Object.fromEntries(Object.entries(p).filter(([, v]) => v !== undefined && v !== null).map(([k, v]) => [k, String(v)]));
        return (await callApi("GET", `/v2/${config.listPath}`, q)).data;
      }
      if (!config.odataPath) {
        throw new Error(`${resourceType} does not support listing (no OData endpoint). Use get_resource with a specific ID.`);
      }
      if (args.all_pages === true) {
        return listAllPages(`/v2/odata/${config.odataPath}`, {
          $filter: str(args, "filter"),
          $select: str(args, "select") ?? (resourceType === "user" ? USER_SELECT : undefined),
          $orderby: str(args, "orderby"),
          $expand: str(args, "expand"),
          $search: str(args, "search"),
        }, args.max_records === undefined || args.max_records === null ? 5000 : Number(args.max_records));
      }
      // Default $top to 100 if the caller didn't specify one: pagination by
      // default avoids accidentally fetching huge result sets that could
      // throttle or block at the CloudRadial side. Callers can override
      // with explicit `top` (max 200) and walk pages via `skip`.
      const query: Record<string, string | undefined> = {
        $filter: str(args, "filter"),
        $select: str(args, "select") ?? (resourceType === "user" ? USER_SELECT : undefined),
        $orderby: str(args, "orderby"),
        $top: str(args, "top") ?? "100",
        $skip: str(args, "skip"),
        $expand: str(args, "expand"),
        $search: str(args, "search"),
      };
      const result = await callApi("GET", `/v2/odata/${config.odataPath}`, query);
      // Unwrap OData envelope so callers get a clean array. If the partner
      // wants pagination metadata, count_resources / $count is the way.
      return (result.data as { value?: unknown })?.value ?? result.data;
    },
  },

  {
    name: "count_resources",
    description: "Count a resource type with an optional OData $filter.",
    inputSchema: {
      type: "object",
      properties: {
        resource_type: { type: "string", enum: RESOURCE_TYPES },
        filter: { type: "string", description: "OData $filter expression" },
      },
      required: ["resource_type"],
    },
    handler: async (args) => {
      const { resourceType, config } = requireResource(args);
      if (!config.odataPath) {
        throw new Error(`${resourceType} does not support count (no OData endpoint). List it with list_resources and count the rows.`);
      }
      const filter = str(args, "filter");
      const result = await callApi(
        "GET",
        `/v2/odata/${config.odataPath}/$count`,
        filter ? { $filter: filter } : undefined
      );
      return { count: result.data };
    },
  },

  {
    name: "get_resource",
    description:
      "Retrieve a single resource by ID. Composite-key types: archive_item needs archive_id + id; service_install needs endpoint_id + service_id; company_group_company needs company_group_id + company_id; course_lesson_history needs course_id + application_user_id + course_lesson_id; endpoint_custom_property needs serial_number + property_name. assessment and course_enrollment are read through OData by id.",
    inputSchema: {
      type: "object",
      properties: {
        resource_type: { type: "string", enum: RESOURCE_TYPES },
        id: { type: "string", description: "Primary identifier" },
        archive_id: { type: "string", description: "Required for archive_item" },
        endpoint_id: { type: "string", description: "Required for service_install" },
        service_id: { type: "string", description: "Required for service_install" },
        company_group_id: { type: "string", description: "Required for company_group_company" },
        company_id: COMPANY_ID_PARAM,
        course_id: { type: "string", description: "Required for course_lesson_history" },
        application_user_id: { type: "string", description: "Required for course_lesson_history" },
        course_lesson_id: { type: "string", description: "Required for course_lesson_history" },
        ...CUSTOM_PROPERTY_PARAMS,
      },
      required: ["resource_type"],
    },
    handler: async (args) => {
      const { resourceType, config } = requireResource(args);

      if (resourceType === "archive_item") {
        const archiveId = requireStr(args, "archive_id");
        const id = requireStr(args, "id");
        const result = await callApi("GET", `/v2/archiveitem/${archiveId}/${id}`);
        return result.data;
      }
      if (resourceType === "service_install") {
        const endpointId = requireStr(args, "endpoint_id");
        const serviceId = requireStr(args, "service_id");
        const result = await callApi("GET", `/v2/serviceinstall/${endpointId}/${serviceId}`);
        return result.data;
      }
      if (resourceType === "company_group_company") {
        const cgId = requireStr(args, "company_group_id");
        const cId = requireStr(args, "company_id");
        const result = await callApi("GET", `/v2/companygroupcompany/${cgId}/${cId}`);
        return result.data;
      }
      if (resourceType === "course_lesson_history") {
        const courseId = requireStr(args, "course_id");
        const auId = requireStr(args, "application_user_id");
        const lessonId = requireStr(args, "course_lesson_id");
        const query = await itemCompanyQuery(resourceType, args);
        const result = await callApi("GET", `/v2/courselessonhistory/${courseId}/${auId}/${lessonId}`, query);
        return result.data;
      }
      if (resourceType === "endpoint_custom_property") {
        const result = await callApi("GET", customPropertyPath(args, true));
        return result.data;
      }
      if (resourceType === "assessment" || resourceType === "course_enrollment") {
        const id = requireStr(args, "id");
        const row = await odataByKey(resourceType, id);
        if (!row) throw new Error(`${resourceType} ${id} not found`);
        return row;
      }
      if (!config.itemPath) {
        throw new Error(`get_resource is not supported for ${resourceType}`);
      }
      const id = requireStr(args, "id");
      const query = await itemCompanyQuery(resourceType, args, id);
      const result = await callApi("GET", `/v2/${config.itemPath}/${id}`, query);
      return result.data;
    },
  },

  {
    name: "create_resource",
    description:
      "Create a new resource. `data` is the resource body sent to CloudRadial; include every field the API requires for that type (e.g. article: subject, body, companyId, datePublished). endpoint_custom_property needs serial_number, with data {name, value, dataType}. " +
      "banner: {title, style 1-4 (1 green, 2 amber, 3 red, 4 blue), placement 1 sidebar or 2 top, companyGroups (group NAMES; empty means no company sees it), showOnHome/Login/Report/Request, publishDate, expireDate}. " +
      "portal_message: {companyId, subject, category, author, body, priority 0/10/20, showAsAlert}. dashboard: {companyId, title}. archive_folder: {companyId, name, alertKeywords, requiredKeywords, warnOnPastDays, retainForDays}. " +
      "Assessments are created with assessment_import; Signal messages with signal_message; report files with archive_upload.",
    inputSchema: {
      type: "object",
      properties: {
        resource_type: { type: "string", enum: RESOURCE_TYPES },
        data: { type: "object", description: "Resource fields (e.g. {subject, body, companyId, datePublished} for an article)" },
        serial_number: CUSTOM_PROPERTY_PARAMS.serial_number,
        confirmed: CONFIRMED_PARAM,
      },
      required: ["resource_type", "data"],
    },
    handler: async (args) => {
      const { resourceType, config } = requireResource(args);
      const data = (args.data as Record<string, unknown>) || {};
      if (resourceType === "assessment") throw new Error(ASSESSMENT_HINT);
      if (WRITE_TOOL[resourceType]) throw new Error(WRITE_TOOL[resourceType]);
      if (CREATE_TOOL[resourceType]) throw new Error(CREATE_TOOL[resourceType]);
      requireConfirmed(resourceType, "create", args);
      if (resourceType === "endpoint_custom_property") {
        const result = await callApi("POST", customPropertyPath(args, false), undefined, data);
        return result.data;
      }
      if (!config.itemPath && !config.createPath) throw new Error(`create is not supported for ${resourceType}`);
      const createPath = config.createPath || config.itemPath;
      const result = await callApi("POST", `/v2/${createPath}`, undefined, data);
      return result.data;
    },
  },

  {
    name: "update_resource",
    description:
      "Update a resource by ID. method=PATCH (default) changes only the fields in `data`; PUT replaces the whole record, so fields left out of `data` are cleared. Composite-key types: archive_item (archive_id + id), service_install (endpoint_id + id=serviceId), course_lesson_history (course_id + application_user_id + course_lesson_id), endpoint_custom_property (serial_number + property_name). flexible_asset: pass the traits to change as data.traits; only traits the asset already has can be changed, and traits left out are kept. company_group_company is create/delete-only. Not possible in the API: assessment updates (use assessment_import or assessment_lifecycle) and flexible_asset_field updates. Signal messages are edited with signal_message.",
    inputSchema: {
      type: "object",
      properties: {
        resource_type: { type: "string", enum: RESOURCE_TYPES },
        id: { type: "string" },
        method: { type: "string", enum: ["PATCH", "PUT"], default: "PATCH" },
        data: { type: "object", description: "Fields to update" },
        archive_id: { type: "string", description: "Required for archive_item" },
        endpoint_id: { type: "string", description: "Required for service_install (id = serviceId)" },
        course_id: { type: "string", description: "Required for course_lesson_history" },
        application_user_id: { type: "string", description: "Required for course_lesson_history" },
        course_lesson_id: { type: "string", description: "Required for course_lesson_history (alternative to id)" },
        company_id: COMPANY_ID_PARAM,
        confirmed: CONFIRMED_PARAM,
        ...CUSTOM_PROPERTY_PARAMS,
      },
      required: ["resource_type", "data"],
    },
    handler: async (args) => {
      const { resourceType, config } = requireResource(args);
      if (resourceType === "assessment") throw new Error(ASSESSMENT_HINT);
      if (WRITE_TOOL[resourceType]) throw new Error(WRITE_TOOL[resourceType]);
      if (!config.itemPath) throw new Error(`update is not supported for ${resourceType}`);

      const method = (str(args, "method") || "PATCH").toUpperCase();
      if (!["PUT", "PATCH"].includes(method)) {
        throw new Error("method must be PATCH or PUT");
      }
      const blocked = NOT_IN_API[resourceType]?.[method.toLowerCase() as "put" | "patch"];
      if (blocked) throw new Error(blocked);
      requireConfirmed(resourceType, "update", args);

      let data = (args.data as Record<string, unknown>) || {};
      // flexible_asset traits can only be changed one existing trait at a time
      // (live, 2026-10-07): replacing /traitsJson or the whole /traits object is
      // refused. So each key becomes its own replace op on /traits/<key>.
      const extraOps: { op: string; path: string; value: unknown }[] = [];
      if (resourceType === "flexible_asset" && data.traits !== undefined) {
        const { traits, ...rest } = data;
        const t = typeof traits === "string" ? JSON.parse(traits) : traits;
        if (!t || typeof t !== "object" || Array.isArray(t)) throw new Error("data.traits must be an object of trait name to value");
        for (const [key, value] of Object.entries(t as Record<string, unknown>)) {
          extraOps.push({ op: "replace", path: `/traits/${key.replace(/~/g, "~0").replace(/\//g, "~1")}`, value });
        }
        data = rest;
      }

      let path: string;
      let itemId: string | undefined;
      if (resourceType === "archive_item") {
        const archiveId = requireStr(args, "archive_id");
        const id = requireStr(args, "id");
        path = `/v2/archiveitem/${archiveId}/${id}`;
      } else if (resourceType === "service_install") {
        const endpointId = requireStr(args, "endpoint_id");
        const id = requireStr(args, "id");
        path = `/v2/serviceinstall/${endpointId}/${id}`;
      } else if (resourceType === "course_lesson_history") {
        const courseId = requireStr(args, "course_id");
        const auId = requireStr(args, "application_user_id");
        const lessonId = str(args, "course_lesson_id") || requireStr(args, "id");
        path = `/v2/courselessonhistory/${courseId}/${auId}/${lessonId}`;
      } else if (resourceType === "endpoint_custom_property") {
        path = customPropertyPath(args, true);
      } else if (resourceType === "company_group_company") {
        throw new Error("company_group_company has no update endpoint; use create_resource or delete_resource");
      } else {
        itemId = requireStr(args, "id");
        path = `/v2/${config.itemPath}/${itemId}`;
      }
      // Some routes take no companyId on one method (e.g. PATCH /v2/archivefolder/{id}, PUT /v2/policy/{id}).
      const query = NO_COMPANY_QUERY[resourceType]?.includes(method) ? undefined : await itemCompanyQuery(resourceType, args, itemId);

      // CloudRadial's PATCH endpoints expect an RFC 6902 JSON Patch document,
      // not a plain partial object. Convert {field: value, ...} → an array of
      // replace ops so partners can pass a partial object as documented.
      // PUT (full replace) is sent through as-is.
      const body =
        method === "PATCH"
          ? [
              ...Object.entries(data).map(([key, value]) => ({
                op: "replace",
                path: `/${key}`,
                value,
              })),
              ...extraOps,
            ]
          : data;
      const result = await callApi(method, path, query, body);
      return result.data ?? { updated: true };
    },
  },

  {
    name: "delete_resource",
    description:
      "Delete a resource by ID. Deletes can't be undone through the API: confirm the exact item with the user first. Composite-key types: archive_item (archive_id + id), service_install (endpoint_id + id=serviceId), company_group_company (company_group_id + company_id), course_lesson_history (course_id + application_user_id + course_lesson_id), endpoint_custom_property (serial_number + property_name). " +
      "assessment: soft-deletes an assessment (20), template (10) or archived assessment (50); its runs are kept unless include_runs=true. A run (30) is deleted with assessment_lifecycle action=delete_run. course_enrollment: removes the user from the course; they can be enrolled again. Not possible in the API: flexible_asset_field deletes.",
    inputSchema: {
      type: "object",
      properties: {
        resource_type: { type: "string", enum: RESOURCE_TYPES },
        id: { type: "string" },
        archive_id: { type: "string", description: "Required for archive_item" },
        endpoint_id: { type: "string", description: "Required for service_install (id = serviceId)" },
        company_group_id: { type: "string", description: "Required for company_group_company" },
        company_id: COMPANY_ID_PARAM,
        course_id: { type: "string", description: "Required for course_lesson_history" },
        application_user_id: { type: "string", description: "Required for course_lesson_history" },
        course_lesson_id: { type: "string", description: "Required for course_lesson_history (alternative to id)" },
        include_runs: { type: "boolean", description: "assessment only: also delete the assessment's runs (default false)" },
        confirmed: CONFIRMED_PARAM,
        ...CUSTOM_PROPERTY_PARAMS,
      },
      required: ["resource_type"],
    },
    handler: async (args) => {
      const { resourceType, config } = requireResource(args);
      if (resourceType === "assessment") return deleteAssessment(args);
      if (WRITE_TOOL[resourceType]) throw new Error(WRITE_TOOL[resourceType]);
      if (!config.itemPath) throw new Error(`delete is not supported for ${resourceType}`);
      const blocked = NOT_IN_API[resourceType]?.delete;
      if (blocked) throw new Error(blocked);
      requireConfirmed(resourceType, "delete", args);

      let path: string;
      let itemId: string | undefined;
      if (resourceType === "archive_item") {
        const archiveId = requireStr(args, "archive_id");
        const id = requireStr(args, "id");
        path = `/v2/archiveitem/${archiveId}/${id}`;
      } else if (resourceType === "service_install") {
        const endpointId = requireStr(args, "endpoint_id");
        const id = requireStr(args, "id");
        path = `/v2/serviceinstall/${endpointId}/${id}`;
      } else if (resourceType === "company_group_company") {
        const cgId = requireStr(args, "company_group_id");
        const cId = requireStr(args, "company_id");
        path = `/v2/companygroupcompany/${cgId}/${cId}`;
      } else if (resourceType === "course_lesson_history") {
        const courseId = requireStr(args, "course_id");
        const auId = requireStr(args, "application_user_id");
        const lessonId = str(args, "course_lesson_id") || requireStr(args, "id");
        path = `/v2/courselessonhistory/${courseId}/${auId}/${lessonId}`;
      } else if (resourceType === "endpoint_custom_property") {
        path = customPropertyPath(args, true);
      } else {
        itemId = requireStr(args, "id");
        path = `/v2/${config.itemPath}/${itemId}`;
      }

      const query = resourceType === "company_group_company" ? undefined : await itemCompanyQuery(resourceType, args, itemId);
      const result = await callApi("DELETE", path, query);
      return result.data ?? { deleted: true };
    },
  },

  {
    name: "user_lookup",
    description:
      "Find users by any combination of email, name (matches firstName or lastName), or company_id. At least one filter is required.",
    inputSchema: {
      type: "object",
      properties: {
        email: { type: "string" },
        name: { type: "string", description: "Matches firstName OR lastName (case-insensitive)" },
        company_id: { type: "string" },
        top: { type: "string", description: "Max results (default 20)" },
      },
    },
    handler: async (args) => {
      const email = str(args, "email");
      const name = str(args, "name");
      const companyId = str(args, "company_id");
      const top = str(args, "top") || "20";

      const filters: string[] = [];
      if (email) filters.push(`contains(tolower(email), '${escapeODataString(email)}')`);
      if (name) {
        const safe = escapeODataString(name);
        filters.push(`(contains(tolower(firstName), '${safe}') or contains(tolower(lastName), '${safe}'))`);
      }
      if (companyId) filters.push(`companyId eq ${companyId}`);

      if (filters.length === 0) {
        throw new Error("At least one of email, name, or company_id is required");
      }

      const result = await callApi("GET", "/v2/odata/user", {
        $filter: filters.join(" and "),
        $top: top,
        $select: USER_SELECT,
      });
      // Unwrap OData envelope so callers get a clean array.
      return (result.data as { value?: unknown })?.value ?? result.data;
    },
  },

  {
    name: "manage_tokens",
    description:
      "Manage CloudRadial replacement tokens: the named values (like @SupportPhone) that portal forms, articles and automations fill in. " +
      "These are NOT API keys. Tokens live at partner level (company_id 0, the default) or on one company (company_id > 0), and a company token overrides the partner token of the same name. " +
      "action = list | get | create (creates or updates; needs token_name and value) | revoke (deletes). " +
      "revoke always needs an explicit company_id: a company's token, or 0 for the partner token, which also needs confirm_partner_level=true because it removes the default every client falls back to. Names are case-sensitive.",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["list", "get", "create", "revoke"] },
        company_id: { type: "integer", description: "0 = partner-level token (default); >0 = that company's token" },
        token_name: { type: "string", description: "Token name, case-sensitive. Required for get, create and revoke." },
        value: { type: "string", description: "Token value for create (empty string allowed as a placeholder)" },
        type: { type: "string", description: "Optional token type for create: None, String or Automation" },
        token_id: { type: "string", description: "Deprecated alias for token_name" },
        data: { type: "object", description: "Deprecated: raw body {companyId, token, value, type} for create" },
        confirm_partner_level: { type: "boolean", description: "revoke with company_id 0 only: set true after the user confirms deleting the partner-level token" },
      },
      required: ["action"],
    },
    handler: async (args) => {
      const action = requireStr(args, "action");
      const companyId = args.company_id === undefined || args.company_id === null ? "0" : String(Number(args.company_id));
      const nameOf = () => {
        const n = str(args, "token_name") || str(args, "token_id");
        if (!n) throw new Error("token_name is required for this action.");
        return encodeURIComponent(n);
      };
      switch (action) {
        case "list": {
          const result = await callApi("GET", "/v2/token", { companyId });
          return result.data;
        }
        case "get": {
          const result = await callApi("GET", `/v2/token/${nameOf()}`, { companyId });
          return result.data;
        }
        case "create": {
          const raw = args.data as Record<string, unknown> | undefined;
          const body = raw && !str(args, "token_name")
            ? raw
            : { companyId: Number(companyId), token: decodeURIComponent(nameOf()), value: str(args, "value") ?? "", ...(str(args, "type") ? { type: str(args, "type") } : {}) };
          const result = await callApi("POST", "/v2/token", undefined, body);
          return result.data;
        }
        case "revoke": {
          // DELETE /v2/token/{name} without companyId acts on the PARTNER token, so a
          // forgotten company would remove the default for every client.
          if (args.company_id === undefined || args.company_id === null || str(args, "company_id") === "") {
            throw new Error("revoke needs company_id: the company whose token to delete, or 0 for the partner-level token.");
          }
          if (companyId === "0" && args.confirm_partner_level !== true) {
            throw new Error(`This deletes the PARTNER-level token "${decodeURIComponent(nameOf())}", the default every company without its own token falls back to. Confirm with the user, then call again with confirm_partner_level=true.`);
          }
          const result = await callApi("DELETE", `/v2/token/${nameOf()}`, { companyId });
          return result.data ?? { deleted: true };
        }
        default:
          throw new Error("action must be one of: list, get, create, revoke");
      }
    },
  },

  {
    name: "endpoint_update_warranty",
    description:
      "Trigger an asynchronous warranty refresh for an endpoint, identified by its serial number. The request returns immediately; CloudRadial fetches the warranty info in the background.",
    inputSchema: {
      type: "object",
      properties: {
        serial_number: { type: "string", description: "The endpoint's serial number" },
      },
      required: ["serial_number"],
    },
    handler: async (args) => {
      const serial = requireStr(args, "serial_number");
      const result = await callApi("POST", `/v2/endpoint/${encodeURIComponent(serial)}/update-warranty`);
      return result.data ?? { queued: true };
    },
  },

  {
    name: "courseenrollment_complete",
    description:
      "Mark a course enrollment as completed for a user. Optionally include score, comment, and completionDate in `data`.",
    inputSchema: {
      type: "object",
      properties: {
        enrollment_id: { type: "string", description: "ID of the course_enrollment record" },
        data: {
          type: "object",
          description: "Optional completion details",
          properties: {
            score:          { type: "integer" },
            comment:        { type: "string" },
            completionDate: { type: "string", description: "ISO 8601 timestamp" },
          },
        },
      },
      required: ["enrollment_id"],
    },
    handler: async (args) => {
      const enrollmentId = requireStr(args, "enrollment_id");
      const data = (args.data as Record<string, unknown>) || {};
      const result = await callApi(
        "POST",
        `/v2/courseenrollment/${enrollmentId}/complete`,
        undefined,
        data
      );
      return result.data ?? { completed: true };
    },
  },

  {
    name: "courseenrollment_for_user",
    description:
      "Get a specific user's enrollment record for a specific course. Returns null/404 if the user is not enrolled in that course.",
    inputSchema: {
      type: "object",
      properties: {
        course_id: { type: "string", description: "Course ID" },
        user_id:   { type: "string", description: "Application user ID" },
      },
      required: ["course_id", "user_id"],
    },
    handler: async (args) => {
      const courseId = requireStr(args, "course_id");
      const userId = requireStr(args, "user_id");
      try {
        const result = await callApi("GET", `/v2/courseenrollment/course/${courseId}/user/${encodeURIComponent(userId)}`);
        return result.data;
      } catch (err) {
        // 404 means "not enrolled", as the description promises.
        if (err instanceof CloudRadialApiError && err.status === 404) return null;
        throw err;
      }
    },
  },

  {
    name: "assessment_import",
    description:
      "Create or refresh a CloudRadial assessment for a company from questions, the way the portal's Import Assessment does. " +
      "Give ONE question source: `questions` (an array of objects keyed by assessment template column, e.g. {Category, Question, Order, Explanation, Answer, Remediation, Update Key}), " +
      "`file_path` (a local .xlsx already in the CloudRadial assessment template layout), or `template_id` (copy every question from a template assessment into an existing `assessment_id`, optionally duplicated per server/endpoint/user with `apply_to`; the API currently accepts this call but copies no questions, so prefer the portal). " +
      "Without `assessment_id`, the upload creates a new assessment and the tool finds its id by title (assessment_lifecycle action=create is the direct alternative). " +
      "With `assessment_id`, the upload updates that assessment in place: questions are matched by their Update Key, so give each question a stable Update Key to refresh answers without duplicates. " +
      "Returns {assessmentId, created, questions, source}. This writes to the portal: confirm the company and title with the user first.",
    inputSchema: {
      type: "object",
      properties: {
        company_id:    { type: "integer", description: "Company the assessment belongs to" },
        title:         { type: "string", description: "Assessment title. Required when creating; used to find the new assessment's id." },
        assessment_id: { type: "integer", description: "Existing assessment to refresh in place. Omit to create a new one. Required with template_id." },
        questions:     { type: "array", items: { type: "object" }, description: "Questions keyed by template column name. Category and Question are required on each; set Update Key to make re-imports update in place." },
        file_path:     { type: "string", description: "Path to a local .xlsx in the CloudRadial assessment template layout" },
        template_id:   { type: "integer", description: "Template assessment to copy questions from (needs assessment_id)" },
        apply_to:      { type: "string", enum: ["server", "endpoint", "user"], description: "With template_id: duplicate questions per matching item" },
        type:          { type: "integer", description: "Upload type. Default 20 (an assessment, the only type the portal lists). 10 = template. Never 0: it creates a row the portal doesn't show." },
      },
      required: ["company_id"],
    },
    handler: async (args) => {
      const companyId = Number(requireStr(args, "company_id"));
      const questions = Array.isArray(args.questions) ? (args.questions as Record<string, unknown>[]) : undefined;
      const filePath = str(args, "file_path");
      const templateId = args.template_id === undefined || args.template_id === null ? undefined : Number(args.template_id);
      const sources = [questions, filePath, templateId].filter((s) => s !== undefined);
      if (sources.length !== 1) throw new Error("Give exactly one of: questions, file_path, template_id.");
      if (questions && questions.length === 0) throw new Error("questions is empty.");

      const existingId = args.assessment_id === undefined || args.assessment_id === null ? undefined : Number(args.assessment_id);

      if (templateId !== undefined) {
        // import-template copies into an assessment that already exists; the API can't create an empty one.
        if (existingId === undefined) {
          throw new Error("template_id needs assessment_id. Create the assessment first (import its questions with `questions` or `file_path`, or create it in the portal).");
        }
        const body: Record<string, unknown> = { assessmentId: existingId, templateId };
        if (str(args, "apply_to")) body.applyTo = str(args, "apply_to");
        const r = await callApi("POST", "/v2/assessment/import-template", undefined, body);
        return {
          assessmentId: existingId,
          created: false,
          source: `template ${templateId}`,
          result: r.data,
          warning: "CloudRadial accepted the template import, but in testing this endpoint copied no questions. Ask the user to confirm in the portal, or apply the template there.",
        };
      }

      // The upload sets the assessment's title from `name`, so keep the current title on a refresh.
      let title = str(args, "title");
      if (existingId === undefined && !title) throw new Error("title is required when creating a new assessment.");
      if (existingId !== undefined && !title) {
        const row = await odataByKey("assessment", String(existingId));
        if (!row) throw new Error(`Assessment ${existingId} not found.`);
        title = String(row.title ?? "");
      }
      const type = args.type === undefined || args.type === null ? 20 : Number(args.type);
      if (type === 0) throw new Error("type 0 creates an assessment the portal never lists. Use 20 (assessment) or 10 (template).");

      let bytes: Uint8Array;
      let count: number | undefined;
      if (questions) {
        bytes = buildAssessmentXlsx(questions);
        count = questions.length;
      } else {
        if (!/\.xlsx$/i.test(filePath!)) throw new Error("file_path must be an .xlsx file.");
        bytes = new Uint8Array(readFileSync(filePath!));
      }
      const data = JSON.stringify({ name: title, assessmentId: existingId ?? 0, type, companyId });
      const r = await callApiMultipart("/v2/assessment/upload", data, {
        bytes, name: "assessment.xlsx", contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      });
      const source = questions ? "questions" : filePath;
      if (existingId !== undefined) return { assessmentId: existingId, created: false, questions: count, source, result: r.data };

      // The upload returns 204 with no body, so find the new assessment by title: the newest
      // row of this type with that title. (No $select: it has returned HTTP 500 on assessments.)
      const list = await callApi("GET", "/v2/odata/assessment", {
        $filter: `companyId eq ${companyId}`,
        $orderby: "assessmentId desc",
        $top: "200",
      });
      const rows = ((list.data as { value?: unknown })?.value ?? list.data) as Record<string, unknown>[];
      const hit = (Array.isArray(rows) ? rows : []).find(
        (a) => String(a.title ?? "").toLowerCase() === title!.toLowerCase() && Number(a.type) === type
      );
      return {
        assessmentId: hit ? Number(hit.assessmentId) : null,
        created: true,
        questions: count,
        source,
        ...(hit ? {} : { note: "Uploaded, but the new assessment isn't in this company's list yet. Look it up by title shortly." }),
      };
    },
  },

  {
    name: "archive_upload",
    description:
      "Upload one or more local report files (PDF, XLSX, DOCX, CSV, ZIP and other types the portal accepts) into a client company's report archive, the way uploading in the portal does. " +
      "Each file becomes its own archive item with the file attached, and is checked against the folder's alert and required keywords, so folder alerts keep working. " +
      "Pick the folder by archive_id, or by folder_name (case-insensitive) within company_id; with create_folder=true a missing folder is created first (name, category, alert/required keywords, warn_on_past_days, retain_for_days). " +
      "Each file and the whole request must be 128 MB or less; a rejected file means nothing from the request was saved. This writes to the client's portal: confirm the company, folder and files with the user first.",
    inputSchema: {
      type: "object",
      properties: {
        company_id: { type: "integer", description: "Client company that owns the folder" },
        archive_id: { type: "integer", description: "Folder id (companyReportFolderId). Give this or folder_name." },
        folder_name: { type: "string", description: "Folder name within the company, matched case-insensitively" },
        create_folder: { type: "boolean", description: "Create folder_name if the company doesn't have it (default false)" },
        category: { type: "string", description: "New folder only: category, e.g. Backups" },
        alert_keywords: { type: "string", description: "New folder only: comma-separated; a report containing any of them raises an alert" },
        required_keywords: { type: "string", description: "New folder only: comma-separated; a report containing none of them raises an alert" },
        warn_on_past_days: { type: "integer", description: "New folder only: folder goes into error if nothing arrives in this many days (0 = off)" },
        retain_for_days: { type: "integer", description: "New folder only: keep items this many days (0 = forever)" },
        file_paths: { type: "array", items: { type: "string" }, description: "Local files to upload; each becomes one archive item" },
        subject: { type: "string", description: "Optional, up to 255 characters, applied to every item. Defaults to each file's name." },
        body: { type: "string", description: "Optional text stored on every item (checked against the folder's keywords)" },
        is_html: { type: "boolean", description: "Set true if body is HTML" },
      },
      required: ["company_id", "file_paths"],
    },
    handler: async (args) => {
      const companyId = Number(requireStr(args, "company_id"));
      if (!Number.isInteger(companyId) || companyId <= 0) throw new Error("company_id must be a client company id.");
      const paths = Array.isArray(args.file_paths) ? (args.file_paths as unknown[]).map(String) : [];
      if (paths.length === 0) throw new Error("file_paths needs at least one file.");
      const subject = str(args, "subject");
      if (subject && subject.length > 255) throw new Error("subject must be 255 characters or less.");

      // Read and size-check every file before touching the API.
      const MAX = 128 * 1024 * 1024;
      let total = 0;
      const files = paths.map((p) => {
        let size: number;
        try { size = statSync(p).size; } catch { throw new Error(`File not found: ${p}`); }
        if (size === 0) throw new Error(`File is empty: ${p}`);
        if (size > MAX) throw new Error(`File is over 128 MB: ${p}`);
        total += size;
        return { field: "files", bytes: new Uint8Array(readFileSync(p)), name: basename(p), contentType: contentTypeFor(p) };
      });
      if (total > MAX) throw new Error(`The files add up to over 128 MB (${Math.round(total / 1048576)} MB). Upload them in smaller batches.`);

      const folder = await resolveArchiveFolder(companyId, args);
      const r = await callApiForm("/v2/archiveitem/upload", {
        archiveId: String(folder.id),
        subject,
        body: str(args, "body"),
        isHtml: args.is_html === true ? "true" : undefined,
      }, files);
      const d = (r.data ?? {}) as { items?: Record<string, unknown>[]; archiveItemIds?: unknown };
      return {
        companyId,
        archiveId: folder.id,
        folderName: folder.name,
        folderCreated: folder.created,
        uploaded: (d.items ?? []).map((i) => ({
          archiveItemId: i.archiveItemId,
          subject: i.subject,
          isError: i.isError,
          files: ((i.attachments as Record<string, unknown>[] | undefined) ?? []).map((a) => ({ fileName: a.fileName, bytes: a.length })),
        })),
        ...(d.items ? {} : { result: r.data }),
        note: "An item flagged isError matched the folder's alert keywords (or none of its required keywords); that is the folder working as designed.",
      };
    },
  },

  {
    name: "signal_message",
    description:
      "Signal desktop notices: messages that appear on client users' desktops through the Signal client and browser extension, optionally with a button (deep link) and an acknowledgement. " +
      "action = estimate | send | list | get | recipients | edit | resolve | retract. " +
      "send previews first: without confirmed=true it only returns the audience estimate and the message, and sends nothing. Show that preview to the user, then call again with confirmed=true. " +
      "Target with company_ids, group_ids or all_companies, narrowed by user_ids and/or role_ids (each at most 500; every targeted user must belong to a targeted company). " +
      "priority 0 info, 1 important, 2 urgent; important and urgent need expires_at. expires_at defaults to 14 days and can be at most 90. deep_link_url must be an absolute https:// URL. " +
      "A dedupe key is added automatically (same message, audience and day), so a retried send returns the existing message instead of a second one. " +
      "edit, resolve and retract need the message id and use the version you last read (read automatically if omitted); a stale version is refused with 409. " +
      "If Signal isn't enabled for the partner, every call returns 404 \"Signal is not enabled for this partner.\"",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["estimate", "send", "list", "get", "recipients", "edit", "resolve", "retract"] },
        id: { type: "integer", description: "signalMessageId for get, recipients, edit, resolve, retract" },
        version: { type: "integer", description: "edit/resolve/retract: the version last read" },
        confirmed: { type: "boolean", description: "send only: true after the user approved the preview" },
        company_ids: { type: "array", items: { type: "integer" } },
        group_ids: { type: "array", items: { type: "integer" }, description: "Company group ids" },
        all_companies: { type: "boolean" },
        user_ids: { type: "array", items: { type: "string" }, description: "userId values (GUIDs) from user_lookup" },
        role_ids: { type: "array", items: { type: "string" } },
        title: { type: "string", description: "Up to 200 characters" },
        body: { type: "string", description: "Up to 2,000 characters" },
        priority: { type: "integer", enum: [0, 1, 2] },
        expires_at: { type: "string", description: "UTC ISO 8601" },
        due_at: { type: "string", description: "Informational due date (UTC ISO 8601)" },
        scheduled_send_at: { type: "string", description: "Send later instead of now (UTC ISO 8601)" },
        deep_link_url: { type: "string" },
        deep_link_label: { type: "string", description: "Button text, up to 100 characters (default Open Link)" },
        ack_required: { type: "boolean" },
        dedupe_key: { type: "string", description: "Optional: your own key instead of the automatic one" },
        filter: { type: "string", description: "list: OData $filter" },
        top: { type: "integer", description: "list: rows (default 25, max 200); recipients: page size (default 100)" },
        skip: { type: "integer", description: "recipients: offset" },
        acked_only: { type: "boolean", description: "recipients: only people who acknowledged" },
        search: { type: "string", description: "recipients: name or email search" },
      },
      required: ["action"],
    },
    handler: async (args) => {
      const action = requireStr(args, "action");
      const id = () => {
        const v = requireStr(args, "id");
        if (!/^\d+$/.test(v)) throw new Error("id must be a signalMessageId number.");
        return v;
      };
      switch (action) {
        case "list": {
          const top = Math.min(Number(args.top ?? 25), 200);
          const r = await callApi("GET", "/v2/odata/signalmessage", {
            $filter: str(args, "filter"),
            $orderby: "signalMessageId desc",
            $top: String(top),
          });
          return (r.data as { value?: unknown })?.value ?? r.data;
        }
        case "get":
          return (await callApi("GET", `/v2/signalmessage/${id()}`)).data;
        case "recipients": {
          const r = await callApi("GET", `/v2/signalmessage/${id()}/recipient`, {
            ackedOnly: args.acked_only === true ? "true" : undefined,
            search: str(args, "search"),
            skip: str(args, "skip"),
            take: String(args.top ?? 100),
          });
          return r.data;
        }
        case "estimate":
        case "send": {
          const body = signalPublishBody(args);
          const est = (await callApi("POST", "/v2/signalmessage/estimate", undefined, body)).data as { users?: number; companies?: number };
          if (action === "estimate" || args.confirmed !== true) {
            return {
              sent: false,
              estimate: est,
              message: body,
              ...(est && est.users === 0 ? { warning: "This targeting reaches nobody. Check that each user belongs to one of the targeted companies." } : {}),
              next: action === "send" ? "Show this to the user. Nothing was sent. Call again with confirmed=true to send." : undefined,
            };
          }
          if (est && est.users === 0) throw new Error("Not sent: the targeting reaches 0 users.");
          const r = await callApi("POST", "/v2/signalmessage", undefined, body);
          return { sent: true, estimate: est, result: r.data };
        }
        case "edit": {
          const msgId = id();
          const cur = (await callApi("GET", `/v2/signalmessage/${msgId}`)).data as Record<string, unknown>;
          const pick = (arg: string, field: string) => (args[arg] !== undefined ? args[arg] : cur?.[field]);
          // A read may return priority as a name; the edit takes 0/1/2.
          const PRIORITY: Record<string, number> = { info: 0, important: 1, urgent: 2 };
          const prio = pick("priority", "priority");
          const priority = typeof prio === "string" && isNaN(Number(prio)) ? PRIORITY[prio.toLowerCase()] ?? prio : prio;
          const edit: Record<string, unknown> = {
            version: args.version ?? cur?.version,
            title: pick("title", "title"),
            body: pick("body", "body"),
            priority,
            deepLinkUrl: pick("deep_link_url", "deepLinkUrl"),
            deepLinkLabel: pick("deep_link_label", "deepLinkLabel"),
            dueAt: pick("due_at", "dueAt"),
            ackRequired: pick("ack_required", "ackRequired"),
            expiresAt: pick("expires_at", "expiresAt"),
          };
          checkSignalContent(edit);
          return (await callApi("PUT", `/v2/signalmessage/${msgId}`, undefined, edit)).data;
        }
        case "resolve":
        case "retract": {
          const msgId = id();
          let version = args.version;
          if (version === undefined || version === null) {
            version = ((await callApi("GET", `/v2/signalmessage/${msgId}`)).data as Record<string, unknown>)?.version;
          }
          return (await callApi("POST", `/v2/signalmessage/${msgId}/${action}`, undefined, { version })).data;
        }
        default:
          throw new Error("action must be one of: estimate, send, list, get, recipients, edit, resolve, retract");
      }
    },
  },

  {
    name: "m365_secure_score",
    description:
      "Microsoft Secure Score from CloudRadial's daily Microsoft 365 sync (read-only; the API never calls Microsoft itself, so today's changes show after the next sync). " +
      "With company_id: that company's tenant, its current score and percentage, and the improvement actions worth the most points (top, default 5), each with Microsoft's cost, user impact, license tier and a link to the setting. " +
      "Without company_id: every linked tenant ranked from lowest to highest percentage, for a roll-up across clients. Tenants with companyId null aren't linked to a company yet.",
    inputSchema: {
      type: "object",
      properties: {
        company_id: { type: "integer", description: "Client company; omit for the roll-up across all tenants" },
        top: { type: "integer", description: "How many improvement actions to return (default 5, 0 for all)" },
      },
    },
    handler: async (args) => {
      const tenantsRes = await callApi("GET", "/v2/m365/tenant");
      const tenants = (Array.isArray(tenantsRes.data) ? tenantsRes.data : []) as Record<string, unknown>[];
      const pct = (t: Record<string, unknown>) => (typeof t.secureScorePercentage === "number" ? Math.round(t.secureScorePercentage * 1000) / 10 : null);
      const companyArg = str(args, "company_id");
      if (!companyArg) {
        const rows = tenants
          .map((t) => ({ companyId: t.companyId ?? null, tenant: t.name, domain: t.domainName, licensedUsers: t.licensedUsers, score: t.secureScore, max: t.secureScoreMax, percent: pct(t) }))
          .sort((a, b) => (a.percent ?? 101) - (b.percent ?? 101));
        return { tenants: rows.length, unlinked: rows.filter((r) => r.companyId === null).length, ranking: rows };
      }
      const matches = tenants.filter((t) => String(t.companyId) === companyArg);
      if (matches.length === 0) {
        throw new Error(`No Microsoft tenant is linked to company ${companyArg}. Link it in the portal, then wait for the next daily sync.`);
      }
      const top = args.top === undefined || args.top === null ? 5 : Number(args.top);
      const out = [];
      for (const t of matches) {
        const detail = (await callApi("GET", `/v2/m365/tenant/${t.microsoftTenantId}/securescore`)).data as Record<string, unknown>;
        const controls = ((detail?.controls as Record<string, unknown>[]) ?? [])
          .filter((c) => !c.deprecated && Number(c.maxScore) > Number(c.score))
          .map((c) => ({
            title: c.title, service: c.service, category: c.category,
            pointsAvailable: Math.round((Number(c.maxScore) - Number(c.score)) * 100) / 100,
            implementationCost: c.implementationCost, userImpact: c.userImpact, tier: c.tier, actionUrl: c.actionUrl,
          }))
          .sort((a, b) => b.pointsAvailable - a.pointsAvailable);
        out.push({
          tenant: t.name, domain: t.domainName, microsoftTenantId: t.microsoftTenantId, licensedUsers: t.licensedUsers,
          score: detail?.currentScore ?? t.secureScore, max: detail?.maxScore ?? t.secureScoreMax, percent: pct(t),
          scoreDate: detail?.scoreDate, cached: detail?.cached,
          ...(detail?.cached === false ? { note: "No score stored in the last 7 days; check the tenant's connection in the portal." } : {}),
          actionsWithPointsAvailable: controls.length,
          topActions: top === 0 ? controls : controls.slice(0, top),
        });
      }
      return { companyId: Number(companyArg), tenants: out };
    },
  },

  {
    name: "assessment_lifecycle",
    description:
      "Create and work with assessments through the v2 assessment routes. action = " +
      "create (new assessment or template: company_id, title, type 20 assessment or 10 template, optional category, description and questions) | templates (list the templates available to company_id) | " +
      "get (an assessment with its scores and questions) | set_questions (add or update questions, matched by updateKey; remove_missing=true soft-deletes every question not in the list and needs confirmed=true) | " +
      "update_question (change one question's fields by question_id) | delete_question | set_answers (answers by questionId or updateKey: value 2 compliant, 1 partial, 0 N/A, -1 missing, -2 not compliant, plus textValue, publicNotes, privateNotes, isFlagged, owner) | " +
      "run (a point-in-time copy, like the portal's Run) | archive | unarchive | delete_run. " +
      "A question is {updateKey, category, label (required), type 0 free text or 80 multiple choice, answerOptions [{label, value}], explanation, evaluationInfo, remediationInfo, remediation pricing fields, order}. " +
      "To delete an assessment or template, use delete_resource with resource_type=assessment. Everything except get and templates writes to the portal: confirm with the user first. company_id is looked up when omitted.",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["create", "templates", "get", "set_questions", "update_question", "delete_question", "set_answers", "run", "archive", "unarchive", "delete_run"] },
        assessment_id: { type: "integer", description: "Required except for create and templates" },
        title: { type: "string", description: "create: the assessment title" },
        type: { type: "integer", enum: [10, 20], description: "create: 20 assessment (default) or 10 template" },
        category: { type: "string" },
        description: { type: "string" },
        questions: { type: "array", items: { type: "object" }, description: "create / set_questions: question objects" },
        remove_missing: { type: "boolean", description: "set_questions: soft-delete questions not in the list (needs confirmed=true)" },
        confirmed: { type: "boolean" },
        question_id: { type: "integer", description: "update_question / delete_question" },
        data: { type: "object", description: "update_question: fields to change, e.g. {label, explanation}" },
        answers: { type: "array", items: { type: "object" }, description: "set_answers: [{questionId or updateKey, value, textValue, publicNotes, privateNotes, isFlagged, owner}]" },
        company_id: { type: "integer", description: "Looked up from the assessment when omitted" },
        name: { type: "string", description: "run: the run's title (default: assessment title plus today's date)" },
        run_id: { type: "integer", description: "delete_run: the run's assessmentId" },
      },
      required: ["action"],
    },
    handler: async (args) => {
      const action = requireStr(args, "action");
      if (action === "create") {
        const companyId = Number(requireStr(args, "company_id"));
        const title = requireStr(args, "title");
        const type = args.type === undefined || args.type === null ? 20 : Number(args.type);
        if (![10, 20].includes(type)) throw new Error("type must be 20 (assessment) or 10 (template).");
        const body: Record<string, unknown> = { companyId, title, type: String(type) };
        if (str(args, "category")) body.category = str(args, "category");
        if (str(args, "description")) body.description = str(args, "description");
        if (Array.isArray(args.questions)) body.questions = (args.questions as Record<string, unknown>[]).map(checkQuestion);
        return (await callApi("POST", "/v2/assessment", undefined, body)).data;
      }
      if (action === "templates") {
        return (await callApi("GET", "/v2/assessment/template", { companyId: requireStr(args, "company_id") })).data;
      }
      const id = requireStr(args, "assessment_id");
      if (!/^\d+$/.test(id)) throw new Error("assessment_id must be a number.");
      if (action === "get") return (await callApi("GET", `/v2/assessment/${id}`)).data;
      const companyId = await assessmentCompany(id, str(args, "company_id"));
      const qid = () => {
        const q = requireStr(args, "question_id");
        if (!/^\d+$/.test(q)) throw new Error("question_id must be a number.");
        return q;
      };
      switch (action) {
        case "set_questions": {
          const qs = Array.isArray(args.questions) ? (args.questions as Record<string, unknown>[]) : [];
          if (qs.length === 0) throw new Error("questions needs at least one question.");
          if (args.remove_missing === true && args.confirmed !== true) {
            throw new Error("remove_missing=true deletes every question not in the list. Show the user which questions would go, then call again with confirmed=true.");
          }
          const body = { questions: qs.map(checkQuestion), removeMissing: args.remove_missing === true };
          return (await callApi("PUT", `/v2/assessment/${id}/questions`, { companyId }, body)).data ?? { updated: qs.length };
        }
        case "update_question": {
          const data = (args.data as Record<string, unknown>) || {};
          if (Object.keys(data).length === 0) throw new Error("data needs at least one field to change.");
          const ops = Object.entries(data).map(([k, v]) => ({ op: "replace", path: `/${k}`, value: v }));
          return (await callApi("PATCH", `/v2/assessment/${id}/question/${qid()}`, { companyId }, ops)).data ?? { updated: true };
        }
        case "delete_question":
          return (await callApi("DELETE", `/v2/assessment/${id}/question/${qid()}`, { companyId })).data ?? { deleted: true };
        case "set_answers": {
          const answers = Array.isArray(args.answers) ? (args.answers as Record<string, unknown>[]) : [];
          if (answers.length === 0) throw new Error("answers needs at least one entry.");
          for (const a of answers) {
            if (a.questionId === undefined && a.updateKey === undefined) throw new Error("Each answer needs questionId or updateKey.");
            if (a.value !== undefined && !["0", "1", "2", "-1", "-2"].includes(String(a.value))) {
              throw new Error(`Answer value must be 2, 1, 0, -1 or -2 (got ${String(a.value)}).`);
            }
          }
          const body = { answers: answers.map((a) => Object.fromEntries(Object.entries(a).map(([k, v]) => [k, v === null || v === undefined ? v : String(v)]))) };
          return (await callApi("PATCH", `/v2/assessment/${id}/answers`, { companyId }, body)).data ?? { updated: answers.length };
        }
        case "run": {
          let name = str(args, "name");
          if (!name) {
            const row = await odataByKey("assessment", id);
            name = `${String(row?.title ?? "Assessment")} - ${new Date().toISOString().slice(0, 10)}`;
          }
          const r = await callApi("POST", `/v2/assessment/${id}/run`, undefined, { companyId: Number(companyId), name });
          return r.data ?? { run: true, name };
        }
        case "archive":
        case "unarchive": {
          const r = await callApi("POST", `/v2/assessment/${id}/${action}`, { companyId });
          return r.data ?? { [action === "archive" ? "archived" : "unarchived"]: true };
        }
        case "delete_run": {
          const runId = requireStr(args, "run_id");
          if (!/^\d+$/.test(runId)) throw new Error("run_id must be a number.");
          const r = await callApi("DELETE", `/v2/assessment/${id}/run/${runId}`, { companyId });
          return r.data ?? { deleted: true, runId: Number(runId) };
        }
        default:
          throw new Error("action must be one of: create, templates, get, set_questions, update_question, delete_question, set_answers, run, archive, unarchive, delete_run");
      }
    },
  },

  {
    name: "access_control",
    description:
      "Portal access: role assignments, feature-set membership, license users and user support PINs. Roles and feature sets themselves are read and edited with the generic resource tools (resource_type role / feature_set, writes need confirmed=true). " +
      "action = list_assignments (filters role_id, user_id, company_id, company_group_id, page, page_size) | assign_role (role_id, user_id, scope company|company_group|partner, scope_id) | remove_assignment (assignment_id) | " +
      "feature_set_companies (feature_set_id) | set_feature_set_companies (feature_set_id, company_ids: the COMPLETE new list) | license_users (license_id) | set_license_users (license_id, company_id, user_ids: the complete new list) | set_support_pin (user_id, company_id, support_pin). " +
      "Every write first returns a preview of the change (current vs new) and does nothing until called again with confirmed=true. A support PIN is never echoed back. " +
      "The API refuses partner-level modules or Full permission on client roles (400) and protected or system roles can't be changed.",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["list_assignments", "assign_role", "remove_assignment", "feature_set_companies", "set_feature_set_companies", "license_users", "set_license_users", "set_support_pin"] },
        confirmed: { type: "boolean", description: "true after the user approved the preview" },
        role_id: { type: "string" },
        user_id: { type: "string", description: "userId (GUID)" },
        company_id: { type: "integer" },
        company_group_id: { type: "integer" },
        scope: { type: "string", enum: ["company", "company_group", "partner"], description: "assign_role: what the role applies to (default company)" },
        scope_id: { type: "integer", description: "assign_role: the company or company group id (0 for partner)" },
        assignment_id: { type: "integer" },
        feature_set_id: { type: "integer" },
        company_ids: { type: "array", items: { type: "integer" } },
        license_id: { type: "integer" },
        user_ids: { type: "array", items: { type: "string" } },
        support_pin: { type: "string" },
        page: { type: "integer" },
        page_size: { type: "integer" },
      },
      required: ["action"],
    },
    handler: async (args) => {
      const action = requireStr(args, "action");
      const confirmed = args.confirmed === true;
      const preview = (what: string, change: unknown) => ({ changed: false, preview: change, next: `Show this to the user. Nothing was changed. Call again with confirmed=true to ${what}.` });
      switch (action) {
        case "list_assignments": {
          return (await callApi("GET", "/v2/roleassignment", {
            roleId: str(args, "role_id"), userId: str(args, "user_id"), companyId: str(args, "company_id"),
            companyGroupId: str(args, "company_group_id"), page: str(args, "page"), pageSize: str(args, "page_size"),
          })).data;
        }
        case "assign_role": {
          const scope = str(args, "scope") ?? "company";
          const scopeType = { partner: 1, company_group: 2, company: 3 }[scope];
          if (!scopeType) throw new Error("scope must be company, company_group or partner.");
          const scopeId = scope === "partner" ? 0 : Number(requireStr(args, "scope_id"));
          const body = { roleId: requireStr(args, "role_id"), scopeType, scopeId, memberType: 1, userId: requireStr(args, "user_id") };
          if (!confirmed) {
            const role = (await callApi("GET", `/v2/role/${encodeURIComponent(body.roleId)}`)).data as Record<string, unknown>;
            return preview("assign the role", { role: { roleId: body.roleId, name: role?.name, isPartnerRole: role?.isPartnerRole }, userId: body.userId, scope, scopeId,
              ...(scope === "partner" ? { warning: "Partner scope applies this role across every client company." } : {}) });
          }
          return (await callApi("POST", "/v2/roleassignment", undefined, body)).data;
        }
        case "remove_assignment": {
          const id = requireStr(args, "assignment_id");
          if (!confirmed) return preview("remove the assignment", (await callApi("GET", `/v2/roleassignment/${id}`)).data);
          return (await callApi("DELETE", `/v2/roleassignment/${id}`)).data ?? { deleted: true };
        }
        case "feature_set_companies":
          return (await callApi("GET", `/v2/featureset/${requireStr(args, "feature_set_id")}/companies`)).data;
        case "set_feature_set_companies": {
          const fs = requireStr(args, "feature_set_id");
          const next = Array.isArray(args.company_ids) ? (args.company_ids as unknown[]).map(Number) : undefined;
          if (!next) throw new Error("company_ids is required: the complete list of companies that should use this feature set.");
          if (!confirmed) {
            const cur = (await callApi("GET", `/v2/featureset/${fs}/companies`)).data;
            const curIds = new Set((Array.isArray(cur) ? cur : []).map((c: any) => Number(c?.companyId ?? c)));
            return preview("replace the feature set's companies", {
              featureSetId: Number(fs), added: next.filter((i) => !curIds.has(i)), removed: [...curIds].filter((i) => !next.includes(i)), newCount: next.length,
              note: "This list replaces the current one; companies removed here fall back to the default feature set.",
            });
          }
          return (await callApi("PUT", `/v2/featureset/${fs}/companies`, undefined, { companyIds: next })).data ?? { updated: next.length };
        }
        case "license_users":
          return licenseHolders(requireStr(args, "license_id"));
        case "set_license_users": {
          const lic = requireStr(args, "license_id");
          const companyId = requireStr(args, "company_id");
          const next = Array.isArray(args.user_ids) ? (args.user_ids as unknown[]).map(String) : undefined;
          if (!next) throw new Error("user_ids is required: the complete list of users who should hold this license.");
          if (!confirmed) {
            const cur = new Set((await licenseHolders(lic)).map((u) => String(u.userId)));
            return preview("replace the license's users", { licenseId: Number(lic), added: next.filter((u) => !cur.has(u)), removed: [...cur].filter((u) => !next.includes(u)), newCount: next.length });
          }
          return (await callApi("PUT", `/v2/license/${lic}/users`, { companyId }, { userIds: next })).data ?? { updated: next.length };
        }
        case "set_support_pin": {
          const userId = requireStr(args, "user_id");
          const companyId = requireStr(args, "company_id");
          const pin = requireStr(args, "support_pin");
          if (!confirmed) return preview("set the PIN", { userId, companyId: Number(companyId), supportPin: "(hidden)" });
          await callApi("PUT", `/v2/user/${encodeURIComponent(userId)}/supportpin`, { companyId }, { supportPin: pin });
          return { updated: true, userId, note: "PIN set. It isn't shown here; share it with the user through your normal secure channel." };
        }
        default:
          throw new Error("Unknown action.");
      }
    },
  },

  {
    name: "policy_review",
    description:
      "Policy compliance (the portal's Policies): action = review (a company's policy review by category: each policy's total items, compliant count, allowance, risk score) | exceptions (one policy's exceptions: the items failing it) | ignore | unignore (accept or restore one exception; needs confirmed=true). " +
      "Create, edit and delete policies with the generic tools (resource_type policy; writes need confirmed=true).",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["review", "exceptions", "ignore", "unignore"] },
        company_id: { type: "integer" },
        policy_id: { type: "integer" },
        exception_id: { type: "integer" },
        confirmed: { type: "boolean" },
      },
      required: ["action", "company_id"],
    },
    handler: async (args) => {
      const action = requireStr(args, "action");
      const companyId = requireStr(args, "company_id");
      if (action === "review") return (await callApi("GET", "/v2/policy/review", { companyId })).data;
      const pid = requireStr(args, "policy_id");
      if (action === "exceptions") return (await callApi("GET", `/v2/policy/${pid}/exception`, { companyId })).data;
      if (action === "ignore" || action === "unignore") {
        const eid = requireStr(args, "exception_id");
        if (args.confirmed !== true) {
          return { changed: false, next: `Show the user the exception and that it will be ${action === "ignore" ? "accepted (no longer counted against the policy)" : "counted again"}, then call again with confirmed=true.` };
        }
        return (await callApi("POST", `/v2/policy/${pid}/exception/${eid}/${action}`, { companyId })).data;
      }
      throw new Error("action must be one of: review, exceptions, ignore, unignore");
    },
  },

  {
    name: "webhook_action",
    description:
      "Partner webhook actions (the HTTP calls automations and catalog submissions can trigger). action = list | get | create | update | enable | disable | test | rotate_secret | delete | runs | run_summary | run. " +
      "Every change (create, update, enable, disable, rotate_secret, delete) returns a preview and needs confirmed=true. test sends one signed canned payload to the endpoint (10-second limit, no retry). " +
      "The signing secret is shown by the API only once (create and rotate_secret): this tool saves it to a private file on this computer and returns the file path, never the secret. " +
      "Header values (e.g. an auth token) are write-only: give them in header_values_file (a local JSON file of {name: value}) rather than in chat; an empty value on update keeps the stored one.",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["list", "get", "create", "update", "enable", "disable", "test", "rotate_secret", "delete", "runs", "run_summary", "run"] },
        id: { type: "integer", description: "actionId" },
        run_id: { type: "string" },
        name: { type: "string" },
        description: { type: "string" },
        url: { type: "string", description: "https:// endpoint" },
        method: { type: "string", enum: ["POST", "PUT", "PATCH", "GET", "DELETE"] },
        is_enabled: { type: "boolean" },
        header_names: { type: "array", items: { type: "string" }, description: "Header names; values come from header_values_file (or stay as stored on update)" },
        header_values_file: { type: "string", description: "Local JSON file {headerName: value}" },
        page: { type: "integer" },
        page_size: { type: "integer" },
        confirmed: { type: "boolean" },
      },
      required: ["action"],
    },
    handler: async (args) => {
      const action = requireStr(args, "action");
      const confirmed = args.confirmed === true;
      const id = () => requireStr(args, "id");
      const gate = (what: string, preview: unknown) => ({ changed: false, preview, next: `Show this to the user. Nothing was changed. Call again with confirmed=true to ${what}.` });
      switch (action) {
        case "list": return (await callApi("GET", "/v2/action")).data;
        case "get": return (await callApi("GET", `/v2/action/${id()}`)).data;
        case "runs": return (await callApi("GET", "/v2/action/run", { page: str(args, "page"), pageSize: str(args, "page_size") })).data;
        case "run_summary": return (await callApi("GET", "/v2/action/run/summary")).data;
        case "run": return (await callApi("GET", `/v2/action/run/${encodeURIComponent(requireStr(args, "run_id"))}`)).data;
        case "create":
        case "update": {
          let cur: Record<string, unknown> = {};
          if (action === "update") cur = ((await callApi("GET", `/v2/action/${id()}`)).data ?? {}) as Record<string, unknown>;
          const url = str(args, "url") ?? (cur.url as string | undefined);
          if (!url || !/^https:\/\/\S+$/i.test(url)) throw new Error("url must be an absolute https:// URL.");
          const body = {
            name: str(args, "name") ?? cur.name,
            description: str(args, "description") ?? cur.description,
            type: 1,
            isEnabled: args.is_enabled !== undefined ? args.is_enabled === true : (cur.isEnabled ?? true),
            url,
            method: (str(args, "method") ?? (cur.method as string | undefined) ?? "POST").toUpperCase(),
            headers: webhookHeaders(args, cur),
          };
          if (!body.name) throw new Error("name is required.");
          if (!confirmed) return gate(`${action} the webhook`, { ...body, headers: body.headers.map((h) => ({ name: h.name, value: h.value ? "(from file)" : "(keep stored)" })) });
          if (action === "update") return (await callApi("PUT", `/v2/action/${id()}`, undefined, body)).data ?? { updated: true };
          return saveSigningSecret((await callApi("POST", "/v2/action", undefined, body)).data);
        }
        case "enable":
        case "disable":
        case "delete":
        case "rotate_secret": {
          if (!confirmed) {
            const cur = (await callApi("GET", `/v2/action/${id()}`)).data as Record<string, unknown>;
            return gate(`${action.replace("_", " ")} it`, { actionId: cur?.actionId, name: cur?.name, url: cur?.url, isEnabled: cur?.isEnabled,
              ...(action === "rotate_secret" ? { warning: "The old secret stops working right away; the receiving system must be updated with the new one." } : {}) });
          }
          if (action === "delete") return (await callApi("DELETE", `/v2/action/${id()}`)).data ?? { deleted: true };
          const r = await callApi("POST", `/v2/action/${id()}/${action === "rotate_secret" ? "rotate-secret" : action}`);
          return action === "rotate_secret" ? saveSigningSecret(r.data) : r.data ?? { [action + "d"]: true };
        }
        case "test":
          return (await callApi("POST", `/v2/action/${id()}/test`)).data;
        default:
          throw new Error("Unknown action.");
      }
    },
  },

  {
    name: "audit_log",
    description:
      "Read-only audit trail. action = events (changes: filters company_id, entity e.g. Company / ApplicationUser / CompanyPolicy, entity_id, identity = a user id, sign-in email or API key user name, source e.g. PublicAPI, from, to, page, page_size) | event (one event by id) | sessions (sign-in and API sessions, same filters) | sync_log (one run of a named sync job, e.g. SyncTicketsForCompanyJob, with company_id and optional status).",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["events", "event", "sessions", "sync_log"] },
        id: { type: "string" },
        company_id: { type: "integer" },
        entity: { type: "string" },
        entity_id: { type: "string" },
        identity: { type: "string" },
        source: { type: "string" },
        from: { type: "string", description: "ISO 8601" },
        to: { type: "string", description: "ISO 8601" },
        page: { type: "integer" },
        page_size: { type: "integer" },
        job_name: { type: "string" },
        status: { type: "string" },
      },
      required: ["action"],
    },
    handler: async (args) => {
      const action = requireStr(args, "action");
      const common = { companyId: str(args, "company_id"), identity: str(args, "identity"), source: str(args, "source"), from: str(args, "from"), to: str(args, "to"), page: str(args, "page"), pageSize: str(args, "page_size") };
      switch (action) {
        case "events": return (await callApi("GET", "/v2/audit/event", { ...common, entity: str(args, "entity"), entityId: str(args, "entity_id") })).data;
        case "event": return (await callApi("GET", `/v2/audit/event/${encodeURIComponent(requireStr(args, "id"))}`)).data;
        case "sessions": return (await callApi("GET", "/v2/audit/session", common)).data;
        case "sync_log": return (await callApi("GET", `/v2/audit/synclog/${encodeURIComponent(requireStr(args, "job_name"))}`, { companyId: str(args, "company_id"), status: str(args, "status") })).data;
        default: throw new Error("action must be one of: events, event, sessions, sync_log");
      }
    },
  },

  {
    name: "signal_device",
    description:
      "Signal client installs enrolled under the partner. action = list (every install, most recently seen first, revoked ones included; filter on state yourself for the live fleet) | fleet_stats | rebootstrap (one-shot reset: the install signs out and purges cached credentials and notices; someone must sign in again on that device) | revoke (permanent sign-out until unrevoked) | unrevoke. " +
      "rebootstrap, revoke and unrevoke need confirmed=true after the user approves; without it they return the device and what will happen.",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["list", "fleet_stats", "rebootstrap", "revoke", "unrevoke"] },
        installation_id: { type: "string" },
        confirmed: { type: "boolean" },
      },
      required: ["action"],
    },
    handler: async (args) => {
      const action = requireStr(args, "action");
      if (action === "list") return (await callApi("GET", "/v2/signaldevice")).data;
      if (action === "fleet_stats") return (await callApi("GET", "/v2/signaldevice/fleetstats")).data;
      if (!["rebootstrap", "revoke", "unrevoke"].includes(action)) throw new Error("action must be one of: list, fleet_stats, rebootstrap, revoke, unrevoke");
      const inst = requireStr(args, "installation_id");
      if (args.confirmed !== true) {
        const all = (await callApi("GET", "/v2/signaldevice")).data;
        const device = (Array.isArray(all) ? all : []).find((d: any) => String(d?.installationId) === inst);
        if (!device) throw new Error(`No Signal install with installationId ${inst}.`);
        const effect = {
          rebootstrap: "On its next check-in it signs out and clears its cached credentials and notices. Someone has to sign in on that device again.",
          revoke: "It signs out on its next poll and stays signed out, even if someone signs in, until it is unrevoked.",
          unrevoke: "It can be signed in again.",
        }[action];
        return { changed: false, device, effect, next: "Show this to the user. Nothing was changed. Call again with confirmed=true." };
      }
      return (await callApi("POST", `/v2/signaldevice/${encodeURIComponent(inst)}/${action}`)).data ?? { [action]: true };
    },
  },

  {
    name: "m365_directory",
    description:
      "Read-only Microsoft 365 directory data from CloudRadial's daily sync for one company: action = groups (the company's Microsoft 365 groups) | roles (its Microsoft admin roles and who holds them). The company must be linked to its tenant in the portal.",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["groups", "roles"] },
        company_id: { type: "integer" },
      },
      required: ["action", "company_id"],
    },
    handler: async (args) => {
      const action = requireStr(args, "action");
      if (!["groups", "roles"].includes(action)) throw new Error("action must be groups or roles");
      const companyId = requireStr(args, "company_id");
      return (await callApi("GET", `/v2/m365/company/${encodeURIComponent(companyId)}/${action === "groups" ? "group" : "role"}`)).data;
    },
  },

  {
    name: "dashboard_widgets",
    description:
      "Widgets on a portal dashboard (create the dashboard itself with create_resource resource_type=dashboard). action = types (the widget types and their settings; read this before adding, never guess a type) | add (dashboard_id, widget {type, title, info, url, html, width, height, x, y, refreshInterval, cacheInterval, isPartnerOnly, settings}) | " +
      "update (dashboard_id, widget_id, data: fields to change) | replace_all (dashboard_id, widgets: the complete layout; needs confirmed=true) | delete (dashboard_id, widget_id). company_id is looked up from the dashboard when omitted.",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["types", "add", "update", "replace_all", "delete"] },
        dashboard_id: { type: "integer" },
        widget_id: { type: "string" },
        company_id: { type: "integer" },
        widget: { type: "object" },
        widgets: { type: "array", items: { type: "object" } },
        data: { type: "object" },
        confirmed: { type: "boolean" },
      },
      required: ["action"],
    },
    handler: async (args) => {
      const action = requireStr(args, "action");
      if (action === "types") return (await callApi("GET", "/v2/dashboard/widget-types")).data;
      const dash = requireStr(args, "dashboard_id");
      const q = (await itemCompanyQuery("dashboard", args, dash)) ?? {};
      switch (action) {
        case "add": {
          const w = args.widget as Record<string, unknown> | undefined;
          if (!w || !w.type) throw new Error("widget.type is required (read action=types first).");
          return (await callApi("POST", `/v2/dashboard/${dash}/widget`, q, w)).data;
        }
        case "update": {
          const data = (args.data as Record<string, unknown>) || {};
          if (Object.keys(data).length === 0) throw new Error("data needs at least one field to change.");
          const ops = Object.entries(data).map(([k, v]) => ({ op: "replace", path: `/${k}`, value: v }));
          return (await callApi("PATCH", `/v2/dashboard/${dash}/widget/${encodeURIComponent(requireStr(args, "widget_id"))}`, q, ops)).data ?? { updated: true };
        }
        case "replace_all": {
          const ws = Array.isArray(args.widgets) ? args.widgets : undefined;
          if (!ws) throw new Error("widgets (the complete layout) is required.");
          if (args.confirmed !== true) return { changed: false, widgets: ws.length, next: "This replaces every widget on the dashboard. Show the user the layout, then call again with confirmed=true." };
          return (await callApi("PUT", `/v2/dashboard/${dash}/widgets`, q, ws)).data ?? { replaced: ws.length };
        }
        case "delete":
          return (await callApi("DELETE", `/v2/dashboard/${dash}/widget/${encodeURIComponent(requireStr(args, "widget_id"))}`, q)).data ?? { deleted: true };
        default:
          throw new Error("action must be one of: types, add, update, replace_all, delete");
      }
    },
  },

  {
    name: "upload_file",
    description:
      "Upload local files to the portal. target = media (partner media library; optional description) | quickstart (create a quickstart from a file: company_id, subject, description, category, icon, icon_color, is_favorite) | quickstart_file (replace an existing quickstart's file: quickstart_id) | " +
      "message_attachment (attach files to a portal message: message_id, company_id) | remove_message_attachment (message_id, attachment_id, company_id). For report files use archive_upload. Each file must exist on this computer. Confirm the target with the user first.",
    inputSchema: {
      type: "object",
      properties: {
        target: { type: "string", enum: ["media", "quickstart", "quickstart_file", "message_attachment", "remove_message_attachment"] },
        file_paths: { type: "array", items: { type: "string" }, description: "Local files (one for media, quickstart and quickstart_file)" },
        description: { type: "string" },
        company_id: { type: "integer" },
        subject: { type: "string" },
        category: { type: "string" },
        icon: { type: "string" },
        icon_color: { type: "string" },
        is_favorite: { type: "boolean" },
        quickstart_id: { type: "integer" },
        message_id: { type: "integer" },
        attachment_id: { type: "integer" },
      },
      required: ["target"],
    },
    handler: async (args) => {
      const target = requireStr(args, "target");
      if (target === "remove_message_attachment") {
        return (await callApi("DELETE", `/v2/message/${requireStr(args, "message_id")}/attachment/${requireStr(args, "attachment_id")}`, { companyId: requireStr(args, "company_id") })).data ?? { deleted: true };
      }
      const paths = Array.isArray(args.file_paths) ? (args.file_paths as unknown[]).map(String) : [];
      if (paths.length === 0) throw new Error("file_paths needs at least one file.");
      if (target !== "message_attachment" && paths.length !== 1) throw new Error(`${target} takes exactly one file.`);
      const read = (field: string) => paths.map((p) => {
        let size: number;
        try { size = statSync(p).size; } catch { throw new Error(`File not found: ${p}`); }
        if (size === 0) throw new Error(`File is empty: ${p}`);
        return { field, bytes: new Uint8Array(readFileSync(p)), name: basename(p), contentType: contentTypeFor(p) };
      });
      switch (target) {
        case "media":
          return (await callApiForm("/v2/media/upload", {}, read("file"), { query: { description: str(args, "description") } })).data;
        case "quickstart":
          return (await callApiForm("/v2/quickstart/upload", {
            CompanyId: requireStr(args, "company_id"), Subject: requireStr(args, "subject"), Description: str(args, "description"),
            Category: str(args, "category"), Icon: str(args, "icon"), IconColor: str(args, "icon_color"),
            IsFavorite: args.is_favorite === undefined ? undefined : String(args.is_favorite === true),
          }, read("File"))).data;
        case "quickstart_file":
          return (await callApiForm(`/v2/quickstart/${requireStr(args, "quickstart_id")}/file`, {}, read("File"), { method: "PUT" })).data ?? { replaced: true };
        case "message_attachment":
          return (await callApiForm(`/v2/message/${requireStr(args, "message_id")}/attachment`, {}, read("Files"), { query: { companyId: requireStr(args, "company_id") } })).data;
        default:
          throw new Error("target must be one of: media, quickstart, quickstart_file, message_attachment, remove_message_attachment");
      }
    },
  },

  {
    name: "raw_api_call",
    description:
      "Direct call to the CloudRadial API for advanced/custom use cases. Provide the path (e.g. '/v2/odata/company') and optional method, query, body. " +
      "A PATCH body must be a JSON Patch array ([{op, path, value}]); it is sent as application/json-patch+json. Useful for routes without their own tool, e.g. dashboard widgets: GET /v2/dashboard/widget-types, POST /v2/dashboard/{id}/widget?companyId=, PUT /v2/dashboard/{id}/widgets.",
    inputSchema: {
      type: "object",
      properties: {
        path:   { type: "string", description: "API path, e.g. '/v2/odata/company'" },
        method: { type: "string", enum: ["GET", "POST", "PUT", "PATCH", "DELETE"], default: "GET" },
        query:  { type: "object", description: "Query parameters as a key/value object" },
        body:   { description: "Request body (any JSON value) for POST/PUT/PATCH" },
      },
      required: ["path"],
    },
    handler: async (args) => {
      const path = requireStr(args, "path");
      const method = (str(args, "method") || "GET").toUpperCase();
      const queryObj = (args.query as Record<string, unknown>) || undefined;
      const query: Record<string, string> | undefined = queryObj
        ? Object.fromEntries(
            Object.entries(queryObj)
              .filter(([, v]) => v !== undefined && v !== null)
              .map(([k, v]) => [k, String(v)])
          )
        : undefined;
            let body: unknown = ["POST", "PUT", "PATCH"].includes(method) ? args.body : undefined;
            if (typeof body === "string") { try { body = JSON.parse(body); } catch (e) { /* leave as-is */ } }
      const result = await callApi(method, path, query, body);
      return result.data;
    },
  },
];
