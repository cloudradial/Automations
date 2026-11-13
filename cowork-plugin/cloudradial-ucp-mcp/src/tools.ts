import { readFileSync, statSync } from "node:fs";
import { basename } from "node:path";
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
};

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
};

// Types whose writes go through a dedicated tool instead of create/update/delete_resource.
const WRITE_TOOL: Record<string, string> = {
  signal_message:
    "Signal messages are sent, edited, resolved and retracted with the signal_message tool, which previews the audience before anything is sent.",
  article_feedback: "article_feedback is read-only (list_resources and count_resources).",
  assessment_question: "assessment_question is read-only here. Change questions with assessment_import.",
};

const ASSESSMENT_HINT =
  "Assessments have no single-item write API. Create or refresh one with assessment_import; read one with get_resource or list_resources.";

const COMPANY_ID_PARAM = {
  type: "string",
  description:
    "Company the item belongs to, sent as ?companyId=. Used by catalog_question, course_lesson, course_lesson_history, domain, user, application_user, token, dashboard, portal_message and archive_folder; looked up automatically if omitted (except course_lesson_history and token). For company_group_company it is the path key instead.",
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
        max_records: { type: "integer", description: "With all_pages: stop after this many rows (default 5000)." },
      },
      required: ["resource_type"],
    },
    handler: async (args) => {
      const { resourceType, config } = requireResource(args);
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
        throw new Error(`${resourceType} does not support count (no OData endpoint).`);
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
      },
      required: ["resource_type", "data"],
    },
    handler: async (args) => {
      const { resourceType, config } = requireResource(args);
      const data = (args.data as Record<string, unknown>) || {};
      if (resourceType === "assessment") throw new Error(ASSESSMENT_HINT);
      if (WRITE_TOOL[resourceType]) throw new Error(WRITE_TOOL[resourceType]);
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
      // PATCH /v2/archivefolder/{id} takes no companyId (unlike its GET and DELETE).
      const query = resourceType === "archive_folder" ? undefined : await itemCompanyQuery(resourceType, args, itemId);

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
      "Without `assessment_id`, the upload creates a new assessment (the API has no other create) and the tool finds its id by title. " +
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
      "Work with an existing assessment beyond importing questions. action = get (the assessment with its scores and questions) | run (create a run: a point-in-time copy, like the portal's Run) | archive | unarchive | delete_run (soft-delete one run). " +
      "To delete an assessment or template, use delete_resource with resource_type=assessment. These write to the portal: confirm with the user first. company_id is looked up when omitted.",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["get", "run", "archive", "unarchive", "delete_run"] },
        assessment_id: { type: "integer" },
        company_id: { type: "integer", description: "Looked up from the assessment when omitted" },
        name: { type: "string", description: "run: the run's title (default: assessment title plus today's date)" },
        run_id: { type: "integer", description: "delete_run: the run's assessmentId" },
      },
      required: ["action", "assessment_id"],
    },
    handler: async (args) => {
      const action = requireStr(args, "action");
      const id = requireStr(args, "assessment_id");
      if (!/^\d+$/.test(id)) throw new Error("assessment_id must be a number.");
      if (action === "get") return (await callApi("GET", `/v2/assessment/${id}`)).data;
      const companyId = await assessmentCompany(id, str(args, "company_id"));
      switch (action) {
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
          throw new Error("action must be one of: get, run, archive, unarchive, delete_run");
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
