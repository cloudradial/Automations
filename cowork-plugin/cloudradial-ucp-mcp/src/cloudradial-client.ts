import { loadCredentials } from "./secure-storage.js";

function getAuthContext(): { authHeader: string; baseUrl: string } {
  const loaded = loadCredentials();
  if (!loaded) {
    throw new Error(
      "CloudRadial credentials not configured. Ask to set up CloudRadial: run `setup_secure_storage`, then `configure_credentials` to open the local form."
    );
  }
  const { creds } = loaded;
  const authHeader =
    "Basic " + Buffer.from(`${creds.publicKey}:${creds.privateKey}`).toString("base64");
  return { authHeader, baseUrl: creds.baseUrl };
}

export interface ResourceConfig {
  odataPath: string;
  itemPath: string;
  idParam: string;
  createPath?: string;
  /** Plain (non-OData) list route, e.g. "role". Used by list_resources when there is no odataPath. */
  listPath?: string;
}

export const RESOURCE_MAP: Record<string, ResourceConfig> = {
  company:                  { odataPath: "company",                itemPath: "company",                idParam: "id" },
  user:                     { odataPath: "user",                   itemPath: "user",                   idParam: "id" },
  article:                  { odataPath: "article",                itemPath: "article",                idParam: "articleId" },
    endpoint:                 { odataPath: "endpoint",               itemPath: "endpoint/id",            idParam: "endpointId",  createPath: "endpoint" },
  catalog:                  { odataPath: "catalog",                itemPath: "catalog",                idParam: "id" },
  catalog_question:         { odataPath: "catalogquestion",        itemPath: "catalogquestion",        idParam: "id" },
  assessment:               { odataPath: "assessment",             itemPath: "",                       idParam: "" },
  feedback:                 { odataPath: "feedback",               itemPath: "feedback",               idParam: "id" },
  service:                  { odataPath: "service",                itemPath: "service",                idParam: "id" },
  service_install:          { odataPath: "serviceinstall",         itemPath: "serviceinstall",         idParam: "" },
  domain:                   { odataPath: "domain",                 itemPath: "domain",                 idParam: "id" },
  course:                   { odataPath: "course",                 itemPath: "course",                 idParam: "id" },
  course_enrollment:        { odataPath: "courseenrollment",       itemPath: "courseenrollment",       idParam: "id" },
  course_lesson:            { odataPath: "courselesson",           itemPath: "courselesson",           idParam: "courseLessonId" },
  menu:                     { odataPath: "menu",                   itemPath: "menu",                   idParam: "menuId" },
  product:                  { odataPath: "product",                itemPath: "product",                idParam: "id" },
  archive_item:             { odataPath: "archiveitem",            itemPath: "archiveitem",            idParam: "" },
  certificate:              { odataPath: "certificate",            itemPath: "certificate",            idParam: "id" },
  company_group:            { odataPath: "companygroup",           itemPath: "companygroup",           idParam: "companyGroupId" },
  quickstart:               { odataPath: "quickstart",             itemPath: "quickstart",             idParam: "quickstartId" },
  flexible_asset:           { odataPath: "flexibleasset",          itemPath: "flexible-asset",         idParam: "id" },
  flexible_asset_type:      { odataPath: "flexibleassettype",      itemPath: "flexible-asset-type",    idParam: "id" },
  flexible_asset_field:     { odataPath: "flexibleassetfield",     itemPath: "flexible-asset-field",   idParam: "id" },
  endpoint_application:     { odataPath: "endpointapplication",    itemPath: "endpointapplication",    idParam: "id" },
  endpoint_custom_property: { odataPath: "endpointcustomproperty", itemPath: "endpoint",               idParam: "" },                // Keyed by serial_number + property_name
  media:                    { odataPath: "media",                  itemPath: "media",                  idParam: "id" },
  token:                    { odataPath: "token",                  itemPath: "token",                  idParam: "tokenName" },
  application_user:         { odataPath: "",                       itemPath: "applicationuser",        idParam: "id" },              // No OData listing
  company_group_company:    { odataPath: "companygroupcompany",    itemPath: "companygroupcompany",    idParam: "" },                // Composite key
  course_lesson_history:    { odataPath: "courselessonhistory",    itemPath: "courselessonhistory",    idParam: "" },                // Composite key
  // Added in 2.7.0 (v2 API, 2026-11)
  archive_folder:           { odataPath: "archivefolder",          itemPath: "archivefolder",          idParam: "id" },              // OData key companyReportFolderId
  banner:                   { odataPath: "banner",                 itemPath: "banner",                 idParam: "id" },              // Partner-level; targeted by companyGroups
  dashboard:                { odataPath: "dashboard",              itemPath: "dashboard",              idParam: "id" },              // Widgets via raw_api_call
  portal_message:           { odataPath: "message",                itemPath: "message",                idParam: "id" },
  signal_message:           { odataPath: "signalmessage",          itemPath: "signalmessage",          idParam: "id" },              // Writes only through the signal_message tool
  article_feedback:         { odataPath: "articlefeedback",        itemPath: "articlefeedback",        idParam: "id" },              // PUT takes only {rating}
  assessment_question:      { odataPath: "assessmentquestion",     itemPath: "",                       idParam: "" },                // List/count only
  // Added in 2.8.0 (v2 API, 2026-11). Writes to these go through a confirmation step.
  role:                     { odataPath: "",                       itemPath: "role",                   idParam: "id", listPath: "role" },
  role_assignment:          { odataPath: "",                       itemPath: "roleassignment",         idParam: "id", listPath: "roleassignment" },
  feature_set:              { odataPath: "",                       itemPath: "featureset",             idParam: "id", listPath: "featureset" },
  license:                  { odataPath: "license",                itemPath: "license",                idParam: "id" },
  user_license:             { odataPath: "userlicense",            itemPath: "",                       idParam: "" },                // List/count only
  policy:                   { odataPath: "policy",                 itemPath: "policy",                 idParam: "id" },
  webhook:                  { odataPath: "",                       itemPath: "action",                 idParam: "id", listPath: "action" }, // Create/rotate via webhook_action
  archive_folder_default:   { odataPath: "",                       itemPath: "archivefolder/default",  idParam: "id", listPath: "archivefolder/default" },
  signal_device:            { odataPath: "",                       itemPath: "",                       idParam: "", listPath: "signaldevice" }, // Writes via signal_device
};

export interface ApiResult {
  status: number;
  data: unknown;
}

/**
 * POST a multipart/form-data request: a JSON `data` part plus one file part.
 * Used by the assessment upload (POST /v2/assessment/upload). Throws on a non-2xx status.
 */
export async function callApiMultipart(
  path: string,
  dataJson: string,
  file: { bytes: Uint8Array; name: string; contentType: string }
): Promise<ApiResult> {
  // A plain string field: appending a Blob makes it a file part named "blob",
  // and the upload answers 400 "Invalid form data." (live, 2026-10-07).
  return callApiForm(path, { data: dataJson }, [{ field: "file", ...file }]);
}

export interface FormFile {
  field: string;
  bytes: Uint8Array;
  name: string;
  contentType: string;
}

/**
 * POST multipart/form-data with plain string fields plus file parts. Fields are
 * appended as strings (never Blobs); a repeated file field (e.g. `files`) is sent
 * once per file. Throws on a non-2xx status, like callApi.
 */
export async function callApiForm(
  path: string,
  fields: Record<string, string | undefined>,
  files: FormFile[],
  opts: { method?: "POST" | "PUT"; query?: Record<string, string | undefined> } = {}
): Promise<ApiResult> {
  const { authHeader, baseUrl } = getAuthContext();
  const form = new FormData();
  for (const [k, v] of Object.entries(fields)) if (v !== undefined) form.append(k, v);
  for (const f of files) form.append(f.field, new Blob([new Uint8Array(f.bytes)], { type: f.contentType }), f.name);
  const url = new URL(path, baseUrl);
  for (const [k, v] of Object.entries(opts.query ?? {})) if (v !== undefined && v !== "") url.searchParams.set(k, v);
  const method = opts.method ?? "POST";
  const resp = await fetch(url.toString(), {
    method,
    headers: { Authorization: authHeader, Accept: "application/json" },
    body: form,
  });
  const text = await resp.text();
  let data: unknown = text;
  try { data = text ? JSON.parse(text) : null; } catch { /* keep text */ }
  if (!resp.ok) throw new CloudRadialApiError(method, path, resp.status, data);
  // Same { data, success, message } envelope as callApi: hand back the payload.
  if (data && typeof data === "object" && !Array.isArray(data) && "data" in data && "success" in data) {
    data = (data as { data: unknown }).data;
  }
  return { status: resp.status, data };
}

export async function callApi(
  method: string,
  path: string,
  query?: Record<string, string | undefined>,
  body?: unknown
): Promise<ApiResult> {
  const { authHeader, baseUrl } = getAuthContext();
  const url = new URL(path, baseUrl);
  if (query) {
    for (const [k, v] of Object.entries(query)) {
      if (v !== undefined && v !== "") url.searchParams.set(k, v);
    }
  }

  const headers: Record<string, string> = {
    Authorization: authHeader,
    Accept: "application/json",
  };

  const init: RequestInit = { method, headers };

  if (body !== undefined && ["POST", "PUT", "PATCH"].includes(method)) {
    // Every v2 PATCH route takes an RFC 6902 JSON Patch array and declares
    // application/json-patch+json. Sending it as application/json gets HTTP 415
    // on some routes (Menu, live 2026-11). A PATCH with a non-array body is sent
    // as plain JSON so the API reports the real problem.
    headers["Content-Type"] =
      method === "PATCH" && Array.isArray(body) ? "application/json-patch+json" : "application/json";
    init.body = JSON.stringify(body);
  }

  const resp = await fetch(url.toString(), init);

  const contentType = resp.headers.get("content-type") || "";
  let data: unknown;
  if (contentType.includes("application/json")) {
    const parsed = (await resp.json()) as unknown;
    // CloudRadial wraps single-resource and write responses in a standard
    // success envelope: { data, success, message }. Unwrap it so callers
    // see the resource directly, matching the tool descriptions.
    // OData collection responses ({ "@odata.context", value: [...] }) are a
    // different shape and pass through here; they're unwrapped per-handler
    // (search_companies / list_resources / user_lookup) to `.value`.
    if (
      parsed &&
      typeof parsed === "object" &&
      !Array.isArray(parsed) &&
      "data" in parsed &&
      "success" in parsed &&
      !("@odata.context" in parsed) &&
      !("value" in parsed)
    ) {
      data = (parsed as { data: unknown }).data;
    } else {
      data = parsed;
    }
  } else {
    const text = await resp.text();
    const num = Number(text);
    data = text === "" ? null : isNaN(num) ? text : num;
  }

  // A 4xx/5xx used to come back as ordinary data, so a 404 read like a result
  // and delete/warranty/complete reported success on an empty error body.
  if (!resp.ok) throw new CloudRadialApiError(method, path, resp.status, data);
  return { status: resp.status, data };
}

/** Thrown by callApi on any non-2xx response. `status` lets a caller treat e.g. 404 as "none". */
export class CloudRadialApiError extends Error {
  constructor(
    public readonly method: string,
    public readonly path: string,
    public readonly status: number,
    public readonly body: unknown
  ) {
    const b = body as { message?: unknown; error?: unknown; title?: unknown; errors?: unknown } | null;
    // OData errors nest as { error: { code, message } }.
    const text = (v: unknown): string =>
      v && typeof v === "object" ? String((v as { message?: unknown }).message ?? JSON.stringify(v)) : String(v);
    const first = b && typeof b === "object" ? b.message || b.error || b.title : undefined;
    const detail = first
      ? text(first)
      : body === null || body === undefined || body === "" ? "(empty response)" : typeof body === "string" ? body : JSON.stringify(body);
    const errors = b && typeof b === "object" && b.errors ? ` ${JSON.stringify(b.errors).slice(0, 300)}` : "";
    super(`CloudRadial API ${method} ${path} failed (HTTP ${status}): ${String(detail).slice(0, 300)}${errors}`);
    this.name = "CloudRadialApiError";
  }
}

export function escapeODataString(value: string): string {
  return value.toLowerCase().replace(/'/g, "''");
}
