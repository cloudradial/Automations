import { readFileSync } from "node:fs";
import { callApi, callApiMultipart, CloudRadialApiError, RESOURCE_MAP, escapeODataString } from "./cloudradial-client.js";
import { buildAssessmentXlsx } from "./xlsx.js";
import {
  clearKeychain,
  getStatus,
  saveToKeychain,
} from "./credentials.js";

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
};

/** First OData row whose key equals `id`, or undefined. */
async function odataByKey(resourceType: string, id: string): Promise<Record<string, unknown> | undefined> {
  const k = ODATA_KEY[resourceType];
  if (!k) return undefined;
  if (!k.quoted && !/^\d+$/.test(id)) throw new Error(`${resourceType} id must be a number, got "${id}"`);
  const value = k.quoted ? `'${id.replace(/'/g, "''")}'` : id;
  const r = await callApi("GET", `/v2/odata/${k.set}`, { $filter: `${k.key} eq ${value}`, $top: "1" });
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
      const row = await odataByKey(resourceType, id);
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
    delete: "The API can't delete a course enrollment.",
  },
};

const ASSESSMENT_HINT =
  "Assessments have no single-item write API. Create or refresh one with assessment_import; read one with get_resource or list_resources.";

const COMPANY_ID_PARAM = {
  type: "string",
  description:
    "Company the item belongs to, sent as ?companyId=. Used by catalog_question, course_lesson, course_lesson_history, domain, user, application_user and token; looked up automatically if omitted (except course_lesson_history and token). For company_group_company it is the path key instead.",
};

const CUSTOM_PROPERTY_PARAMS = {
  serial_number: { type: "string", description: "endpoint_custom_property: the endpoint's serial number" },
  property_name: { type: "string", description: "endpoint_custom_property: the property name" },
};

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
  // Setup / credential management tools — call these first
  // -------------------------------------------------------------------------
  {
    name: "setup_status",
    description:
      "Check whether CloudRadial credentials are configured. Returns {configured, source ('env'|'keychain'|'file'), baseUrl, publicKeyHint (last 4 chars of public key)}. Never returns the full keys. Call this BEFORE any other CloudRadial tool — if configured is false, run the setup wizard before doing CloudRadial work.",
    inputSchema: {
      type: "object",
      properties: {},
    },
    handler: async () => getStatus(),
  },

  {
    name: "configure_credentials",
    description:
      "Store CloudRadial API credentials securely on this computer — in the OS keychain if the native module is available (Windows Credential Manager / macOS Keychain / Linux libsecret), otherwise an AES-256-encrypted local file. Validates the keys with a live `/v2/odata/company/$count` call before saving — if validation fails, nothing is written. Existing credentials are overwritten. The keys are NEVER logged or returned by this tool.",
    inputSchema: {
      type: "object",
      properties: {
        public_key:  { type: "string", description: "CloudRadial API public key (from CloudRadial admin portal → Settings → API)" },
        private_key: { type: "string", description: "CloudRadial API private key" },
        base_url:    { type: "string", description: "API base URL. Defaults to https://api.us.cloudradial.com (US). EU partners: https://api.eu.cloudradial.com" },
      },
      required: ["public_key", "private_key"],
    },
    handler: async (args) => {
      const publicKey = requireStr(args, "public_key");
      const privateKey = requireStr(args, "private_key");
      const baseUrl = str(args, "base_url") || "https://api.us.cloudradial.com";

      // Validate by attempting a live call with these credentials.
      // Build the auth header inline so we don't write anything until validation succeeds.
      const authHeader = "Basic " + Buffer.from(`${publicKey}:${privateKey}`).toString("base64");
      const testUrl = new URL("/v2/odata/company/$count", baseUrl).toString();
      let resp: Response;
      try {
        resp = await fetch(testUrl, {
          method: "GET",
          headers: { Authorization: authHeader, Accept: "application/json" },
        });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        throw new Error(`Network error reaching ${baseUrl}: ${msg}`);
      }

      if (resp.status === 401 || resp.status === 403) {
        throw new Error(
          `CloudRadial rejected those credentials (HTTP ${resp.status}). Double-check the public and private keys from your CloudRadial admin portal → Settings → API.`
        );
      }
      if (!resp.ok) {
        const body = await resp.text();
        throw new Error(`Validation call failed (HTTP ${resp.status}): ${body.slice(0, 200)}`);
      }

      saveToKeychain({ publicKey, privateKey, baseUrl });

      const status = getStatus();
      return {
        success: true,
        message: `Credentials validated and stored securely on this computer (${status.source === "keychain" ? "OS keychain" : "encrypted local file"}).`,
        ...status,
      };
    },
  },

  {
    name: "clear_credentials",
    description:
      "Delete stored CloudRadial credentials from this computer (OS keychain or encrypted local file). Does NOT affect environment variables — if creds were loaded from env vars, this is a no-op. Use to rotate keys or remove the configuration.",
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
      "List any of 30 resource types with OData filtering, sorting, and pagination. ALWAYS paginates: defaults to top=100 if not specified to avoid hammering the API. Resource API caps each page at 200. To get more, increment `skip` (page through) or pair with `count_resources` to know the total. Note: application_user has no OData listing and will error here — use get_resource instead.",
    inputSchema: {
      type: "object",
      properties: {
        resource_type: { type: "string", enum: RESOURCE_TYPES },
        filter:  { type: "string", description: "OData $filter expression" },
        select:  { type: "string", description: "OData $select (comma-separated field list)" },
        orderby: { type: "string", description: "OData $orderby (e.g. 'dateCreated desc')" },
        top:     { type: "string", description: "OData $top — page size. Defaults to 100, max 200." },
        skip:    { type: "string", description: "OData $skip — offset for pagination (use with top to walk pages)." },
        expand:  { type: "string", description: "OData $expand" },
        search:  { type: "string", description: "OData $search" },
      },
      required: ["resource_type"],
    },
    handler: async (args) => {
      const { resourceType, config } = requireResource(args);
      if (!config.odataPath) {
        throw new Error(`${resourceType} does not support listing (no OData endpoint). Use get_resource with a specific ID.`);
      }
      // Default $top to 100 if the caller didn't specify one — pagination by
      // default avoids accidentally fetching huge result sets that could
      // throttle or block at the CloudRadial side. Callers can override
      // with explicit `top` (max 200) and walk pages via `skip`.
      const query: Record<string, string | undefined> = {
        $filter: str(args, "filter"),
        $select: str(args, "select"),
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
      "Create a new resource. `data` is the resource body sent to CloudRadial; include every field the API requires for that type (e.g. article: subject, body, companyId, datePublished). endpoint_custom_property needs serial_number, with data {name, value, dataType}. Assessments are created with assessment_import, not here.",
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
      "Update a resource by ID. method=PATCH (default) changes only the fields in `data`; PUT replaces the whole record, so fields left out of `data` are cleared. Composite-key types: archive_item (archive_id + id), service_install (endpoint_id + id=serviceId), course_lesson_history (course_id + application_user_id + course_lesson_id), endpoint_custom_property (serial_number + property_name). flexible_asset: pass the complete traits object as data.traits (keys left out are removed). company_group_company is create/delete-only. Not possible in the API: assessment updates (use assessment_import) and flexible_asset_field updates.",
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
      if (!config.itemPath) throw new Error(`update is not supported for ${resourceType}`);

      const method = (str(args, "method") || "PATCH").toUpperCase();
      if (!["PUT", "PATCH"].includes(method)) {
        throw new Error("method must be PATCH or PUT");
      }
      const blocked = NOT_IN_API[resourceType]?.[method.toLowerCase() as "put" | "patch"];
      if (blocked) throw new Error(blocked);

      let data = (args.data as Record<string, unknown>) || {};
      // flexible_asset stores its values as a JSON string in traitsJson.
      if (resourceType === "flexible_asset" && data.traits !== undefined) {
        const { traits, ...rest } = data;
        data = { ...rest, traitsJson: typeof traits === "string" ? traits : JSON.stringify(traits) };
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
        throw new Error("company_group_company has no update endpoint — use create_resource or delete_resource");
      } else {
        itemId = requireStr(args, "id");
        path = `/v2/${config.itemPath}/${itemId}`;
      }
      const query = await itemCompanyQuery(resourceType, args, itemId);

      // CloudRadial's PATCH endpoints expect an RFC 6902 JSON Patch document,
      // not a plain partial object. Convert {field: value, ...} → an array of
      // replace ops so partners can pass a partial object as documented.
      // PUT (full replace) is sent through as-is.
      const body =
        method === "PATCH"
          ? Object.entries(data).map(([key, value]) => ({
              op: "replace",
              path: `/${key}`,
              value,
            }))
          : data;
      const result = await callApi(method, path, query, body);
      return result.data ?? { updated: true };
    },
  },

  {
    name: "delete_resource",
    description:
      "Delete a resource by ID. Composite-key types: archive_item (archive_id + id), service_install (endpoint_id + id=serviceId), company_group_company (company_group_id + company_id), course_lesson_history (course_id + application_user_id + course_lesson_id), endpoint_custom_property (serial_number + property_name). Not possible in the API: assessment, course_enrollment and flexible_asset_field deletes.",
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
        ...CUSTOM_PROPERTY_PARAMS,
      },
      required: ["resource_type"],
    },
    handler: async (args) => {
      const { resourceType, config } = requireResource(args);
      if (resourceType === "assessment") throw new Error("The API can't delete an assessment; remove it in the portal.");
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
      "action = list | get | create (creates or updates; needs token_name and value) | revoke (deletes).",
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
      "`file_path` (a local .xlsx already in the CloudRadial assessment template layout), or `template_id` (copy every question from a template assessment into an existing `assessment_id`, optionally duplicated per server/endpoint/user with `apply_to`). " +
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
        return { assessmentId: existingId, created: false, source: `template ${templateId}`, result: r.data };
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
    name: "raw_api_call",
    description:
      "Direct call to the CloudRadial API for advanced/custom use cases. Provide the path (e.g. '/v2/odata/company') and optional method, query, body.",
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
