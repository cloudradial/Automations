import { loadCredentials } from "./credentials.js";

function getAuthContext(): { authHeader: string; baseUrl: string } {
  const loaded = loadCredentials();
  if (!loaded) {
    throw new Error(
      "CloudRadial credentials not configured. Run the `configure_credentials` tool or use the setup wizard."
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
  const { authHeader, baseUrl } = getAuthContext();
  const form = new FormData();
  // A plain string field: appending a Blob makes it a file part named "blob",
  // and the upload answers 400 "Invalid form data." (live, 2026-10-07).
  form.append("data", dataJson);
  form.append("file", new Blob([new Uint8Array(file.bytes)], { type: file.contentType }), file.name);
  const resp = await fetch(new URL(path, baseUrl).toString(), {
    method: "POST",
    headers: { Authorization: authHeader, Accept: "application/json" },
    body: form,
  });
  const text = await resp.text();
  let data: unknown = text;
  try { data = text ? JSON.parse(text) : null; } catch { /* keep text */ }
  if (!resp.ok) throw new Error(`HTTP ${resp.status} from ${path}: ${text.slice(0, 500)}`);
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
    headers["Content-Type"] = "application/json";
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
    // different shape and pass through here — they're unwrapped per-handler
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
