import { callApi, RESOURCE_MAP, escapeODataString } from "./cloudradial-client.js";
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

      if (company.status !== 200) {
        throw new Error(`Company ${companyId} lookup failed (status ${company.status})`);
      }

      return {
        company: company.data,
        counts: {
          userCount: users.data,
          endpointCount: endpoints.data,
        },
        recentArticles: articles.data,
        recentFeedback: feedback.data,
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
      "Retrieve a single resource by ID. Composite-key types: archive_item needs archive_id + id; service_install needs endpoint_id + service_id; company_group_company needs company_group_id + company_id; course_lesson_history needs course_id + application_user_id + course_lesson_id.",
    inputSchema: {
      type: "object",
      properties: {
        resource_type: { type: "string", enum: RESOURCE_TYPES },
        id: { type: "string", description: "Primary identifier" },
        archive_id: { type: "string", description: "Required for archive_item" },
        endpoint_id: { type: "string", description: "Required for service_install" },
        service_id: { type: "string", description: "Required for service_install" },
        company_group_id: { type: "string", description: "Required for company_group_company" },
        company_id: { type: "string", description: "Required for company_group_company" },
        course_id: { type: "string", description: "Required for course_lesson_history" },
        application_user_id: { type: "string", description: "Required for course_lesson_history" },
        course_lesson_id: { type: "string", description: "Required for course_lesson_history" },
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
        const result = await callApi("GET", `/v2/courselessonhistory/${courseId}/${auId}/${lessonId}`);
        return result.data;
      }
      if (!config.itemPath) {
        throw new Error(`get_resource is not supported for ${resourceType}`);
      }
      const id = requireStr(args, "id");
      const result = await callApi("GET", `/v2/${config.itemPath}/${id}`);
      return result.data;
    },
  },

  {
    name: "create_resource",
    description: "Create a new resource. `data` is the resource body sent to CloudRadial.",
    inputSchema: {
      type: "object",
      properties: {
        resource_type: { type: "string", enum: RESOURCE_TYPES },
        data: { type: "object", description: "Resource fields (e.g. {subject, content, companyId} for an article)" },
      },
      required: ["resource_type", "data"],
    },
    handler: async (args) => {
      const { resourceType, config } = requireResource(args);
            if (!config.itemPath && !config.createPath) throw new Error(`create is not supported for ${resourceType}`);
            const data = (args.data as Record<string, unknown>) || {};
            const createPath = config.createPath || config.itemPath;
            const result = await callApi("POST", `/v2/${createPath}`, undefined, data);
      return result.data;
    },
  },

  {
    name: "update_resource",
    description:
      "Update a resource by ID. method=PUT (full replace) or PATCH (partial). Composite-key types: archive_item (archive_id + id), service_install (endpoint_id + id=serviceId), course_lesson_history (course_id + application_user_id + course_lesson_id). company_group_company is create/delete-only — use create_resource / delete_resource.",
    inputSchema: {
      type: "object",
      properties: {
        resource_type: { type: "string", enum: RESOURCE_TYPES },
        id: { type: "string" },
        method: { type: "string", enum: ["PUT", "PATCH"], default: "PUT" },
        data: { type: "object", description: "Fields to update" },
        archive_id: { type: "string", description: "Required for archive_item" },
        endpoint_id: { type: "string", description: "Required for service_install (id = serviceId)" },
        course_id: { type: "string", description: "Required for course_lesson_history" },
        application_user_id: { type: "string", description: "Required for course_lesson_history" },
        course_lesson_id: { type: "string", description: "Required for course_lesson_history (alternative to id)" },
      },
      required: ["resource_type", "data"],
    },
    handler: async (args) => {
      const { resourceType, config } = requireResource(args);
      if (!config.itemPath) throw new Error(`update is not supported for ${resourceType}`);

      const method = (str(args, "method") || "PUT").toUpperCase();
      if (!["PUT", "PATCH"].includes(method)) {
        throw new Error("method must be PUT or PATCH");
      }
      const data = (args.data as Record<string, unknown>) || {};

      let path: string;
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
      } else if (resourceType === "company_group_company") {
        throw new Error("company_group_company has no update endpoint — use create_resource or delete_resource");
      } else {
        const id = requireStr(args, "id");
        path = `/v2/${config.itemPath}/${id}`;
      }

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
      const result = await callApi(method, path, undefined, body);
      return result.data;
    },
  },

  {
    name: "delete_resource",
    description: "Delete a resource by ID. Composite-key types: archive_item (archive_id + id), service_install (endpoint_id + id=serviceId), company_group_company (company_group_id + company_id), course_lesson_history (course_id + application_user_id + course_lesson_id).",
    inputSchema: {
      type: "object",
      properties: {
        resource_type: { type: "string", enum: RESOURCE_TYPES },
        id: { type: "string" },
        archive_id: { type: "string", description: "Required for archive_item" },
        endpoint_id: { type: "string", description: "Required for service_install (id = serviceId)" },
        company_group_id: { type: "string", description: "Required for company_group_company" },
        company_id: { type: "string", description: "Required for company_group_company" },
        course_id: { type: "string", description: "Required for course_lesson_history" },
        application_user_id: { type: "string", description: "Required for course_lesson_history" },
        course_lesson_id: { type: "string", description: "Required for course_lesson_history (alternative to id)" },
      },
      required: ["resource_type"],
    },
    handler: async (args) => {
      const { resourceType, config } = requireResource(args);
      if (!config.itemPath) throw new Error(`delete is not supported for ${resourceType}`);

      let path: string;
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
      } else {
        const id = requireStr(args, "id");
        path = `/v2/${config.itemPath}/${id}`;
      }

      const result = await callApi("DELETE", path);
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
    description: "Manage CloudRadial API tokens. action = list | get | create | revoke.",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["list", "get", "create", "revoke"] },
        token_id: { type: "string", description: "Required for get and revoke" },
        data: { type: "object", description: "Token body for create" },
      },
      required: ["action"],
    },
    handler: async (args) => {
      const action = requireStr(args, "action");
      switch (action) {
        case "list": {
          const result = await callApi("GET", "/v2/token");
          return result.data;
        }
        case "get": {
          const tokenId = requireStr(args, "token_id");
          const result = await callApi("GET", `/v2/token/${tokenId}`);
          return result.data;
        }
        case "create": {
          const data = (args.data as Record<string, unknown>) || {};
          const result = await callApi("POST", "/v2/token", undefined, data);
          return result.data;
        }
        case "revoke": {
          const tokenId = requireStr(args, "token_id");
          const result = await callApi("DELETE", `/v2/token/${tokenId}`);
          return result.data ?? { revoked: true };
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
      const result = await callApi("GET", `/v2/courseenrollment/course/${courseId}/user/${encodeURIComponent(userId)}`);
      return result.data;
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
