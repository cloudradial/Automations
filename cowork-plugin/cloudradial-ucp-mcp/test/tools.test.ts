// Mock-fetch tests for the generic and custom tools. Run with `npm test`.
import { tools } from "../src/tools.js";
import { buildAssessmentXlsx, toUpdateKey } from "../src/xlsx.js";

process.env.CLOUDRADIAL_PUBLIC_KEY = "test-public";
process.env.CLOUDRADIAL_PRIVATE_KEY = "test-private";
process.env.CLOUDRADIAL_BASE_URL = "https://api.example.test";

type Call = { method: string; url: URL; body?: unknown; contentType?: string; form?: [string, string][] };
const calls: Call[] = [];
let route: (c: Call) => { status: number; json?: unknown; text?: string } = () => ({ status: 200, json: {} });

(globalThis as any).fetch = async (url: string, init: RequestInit) => {
  let body: unknown = init.body;
  if (typeof body === "string") { try { body = JSON.parse(body); } catch { /* keep */ } }
  const h = (init.headers || {}) as Record<string, string>;
  let form: [string, string][] | undefined;
  if (body instanceof FormData) {
    form = [];
    for (const [k, v] of body.entries()) form.push([k, typeof v === "string" ? v : `file:${(v as File).name}:${(v as File).size}`]);
  }
  const c: Call = { method: init.method || "GET", url: new URL(url), body, contentType: h["Content-Type"], form };
  calls.push(c);
  const r = route(c);
  if (r.json !== undefined) return new Response(JSON.stringify(r.json), { status: r.status, headers: { "Content-Type": "application/json" } });
  return new Response(r.status === 204 ? null : r.text ?? null, { status: r.status });
};

const tool = (n: string) => tools.find((t) => t.name === n)!;
let failed = 0;
const check = (label: string, ok: boolean, detail = "") => {
  console.log(`${ok ? "PASS" : "FAIL"} ${label}${detail ? " -- " + detail : ""}`);
  if (!ok) failed++;
};
const last = () => calls[calls.length - 1];
const run = async (name: string, args: Record<string, unknown>) => {
  calls.length = 0;
  try { return { ok: true, value: await tool(name).handler(args) }; }
  catch (e) { return { ok: false, error: (e as Error).message }; }
};

// --- HTTP errors now fail the tool --------------------------------------------
route = () => ({ status: 404, json: { success: false, message: "Catalog question not found" } });
let r = await run("get_resource", { resource_type: "article", id: "7" });
check("404 on get is an error", !r.ok && /HTTP 404/.test(r.error!) && /not found/.test(r.error!), r.error);

route = () => ({ status: 404, text: "" });
r = await run("delete_resource", { resource_type: "article", id: "7" });
check("404 on delete is not {deleted:true}", !r.ok, r.error);
r = await run("endpoint_update_warranty", { serial_number: "SN1" });
check("404 on warranty is not {queued:true}", !r.ok, r.error);
r = await run("courseenrollment_complete", { enrollment_id: "5" });
check("404 on complete is not {completed:true}", !r.ok, r.error);
r = await run("courseenrollment_for_user", { course_id: "1", user_id: "u1" });
check("courseenrollment_for_user 404 -> null", r.ok && r.value === null);

route = () => ({ status: 400, json: { title: "Bad Request", errors: { DatePublished: ["required"] } } });
r = await run("create_resource", { resource_type: "article", data: { subject: "x" } });
check("400 shows validation errors", !r.ok && /DatePublished/.test(r.error!), r.error);

route = () => ({ status: 200, json: { success: true, data: { articleId: 7 }, message: "" } });
r = await run("get_resource", { resource_type: "article", id: "7" });
check("success envelope still unwrapped", r.ok && (r.value as any).articleId === 7);

// --- update defaults to PATCH ---------------------------------------------------
route = () => ({ status: 204, text: "" });
r = await run("update_resource", { resource_type: "company", id: "3", data: { territory: "East" } });
check("PATCH is sent as application/json-patch+json", r.ok && last().contentType === "application/json-patch+json", last().contentType);
check("update defaults to PATCH with JSON Patch", r.ok && last().method === "PATCH" &&
  JSON.stringify(last().body) === JSON.stringify([{ op: "replace", path: "/territory", value: "East" }]), JSON.stringify(last().body));
check("204 update returns {updated:true}", r.ok && (r.value as any).updated === true);
r = await run("update_resource", { resource_type: "company", id: "3", method: "PUT", data: { name: "Contoso" } });
check("explicit PUT still sends full body", r.ok && last().method === "PUT" && (last().body as any).name === "Contoso");

r = await run("update_resource", { resource_type: "flexible_asset", id: "9", method: "PUT", data: {} });
check("flexible_asset PUT blocked", !r.ok && /no PUT/.test(r.error!) && calls.length === 0, r.error);
r = await run("update_resource", { resource_type: "flexible_asset_field", id: "9", data: { name: "x" } });
check("flexible_asset_field update blocked", !r.ok && calls.length === 0, r.error);
r = await run("delete_resource", { resource_type: "course_enrollment", id: "9" });
check("course_enrollment delete now calls DELETE", r.ok && last().method === "DELETE" && last().url.pathname === "/v2/courseenrollment/9", r.error);
r = await run("update_resource", { resource_type: "assessment", id: "9", data: {} });
check("assessment update points to assessment_import", !r.ok && /assessment_import/.test(r.error!), r.error);

r = await run("update_resource", { resource_type: "flexible_asset", id: "9", data: { traits: { name: "Core switch", ip: "10.0.0.1" } } });
check("flexible_asset traits -> one op per trait", r.ok && last().url.pathname === "/v2/flexible-asset/9" &&
  JSON.stringify(last().body) === JSON.stringify([
    { op: "replace", path: "/traits/name", value: "Core switch" },
    { op: "replace", path: "/traits/ip", value: "10.0.0.1" },
  ]), JSON.stringify(last().body));

// --- users are read with a $select (a full row returns HTTP 500 live) ------------
route = () => ({ status: 200, json: { value: [] } });
r = await run("list_resources", { resource_type: "user", filter: "companyId eq 9" });
const sel = last().url.searchParams.get("$select") ?? "";
check("user list leaves out supportPin and the company nav", r.ok && sel.startsWith("userId,email,") && !sel.split(",").includes("company") && !sel.includes("supportPin"), sel);
r = await run("list_resources", { resource_type: "user", select: "userId" });
check("caller's user $select wins", r.ok && last().url.searchParams.get("$select") === "userId");
r = await run("user_lookup", { email: "pat@contoso.com" });
check("user_lookup selects scalar fields", r.ok && (last().url.searchParams.get("$select") ?? "").startsWith("userId,email,"));
route = () => ({ status: 400, json: { error: { code: "", message: "Could not find a property named 'manager'" } } });
r = await run("list_resources", { resource_type: "user", select: "manager" });
check("OData error object shows its message", !r.ok && /Could not find a property/.test(r.error!), r.error);

// --- companyId scoping (AAI-126) -------------------------------------------------
route = (c) => c.url.pathname.startsWith("/v2/odata/")
  ? { status: 200, json: { value: [{ companyId: 9 }] } }
  : { status: 200, json: { success: true, data: { ok: 1 } } };
r = await run("get_resource", { resource_type: "catalog_question", id: "42" });
check("catalog_question companyId looked up", r.ok && calls[0].url.searchParams.get("$filter") === "companyCatalogQuestionId eq 42" &&
  last().url.toString().endsWith("/v2/catalogquestion/42?companyId=9"), last().url.toString());
r = await run("update_resource", { resource_type: "user", id: "abc-1", data: { firstName: "Pat" } });
check("user PATCH looks up companyId with quoted key", r.ok && calls[0].url.searchParams.get("$filter") === "userId eq 'abc-1'" &&
  last().url.searchParams.get("companyId") === "9", last().url.toString());
r = await run("delete_resource", { resource_type: "domain", id: "5", company_id: "3" });
check("domain delete uses given company_id", r.ok && calls.length === 1 && last().url.searchParams.get("companyId") === "3");
r = await run("get_resource", { resource_type: "company_group_company", company_group_id: "2", company_id: "9" });
check("company_group_company unchanged", r.ok && last().url.pathname === "/v2/companygroupcompany/2/9" && last().url.search === "");

// --- reads through OData ---------------------------------------------------------
route = () => ({ status: 200, json: { value: [{ assessmentId: 77, title: "Security Review" }] } });
r = await run("get_resource", { resource_type: "assessment", id: "77" });
check("assessment get via OData", r.ok && (r.value as any).assessmentId === 77 && last().url.searchParams.get("$filter") === "assessmentId eq 77");
route = () => ({ status: 200, json: { value: [] } });
r = await run("get_resource", { resource_type: "course_enrollment", id: "5" });
check("course_enrollment missing -> error", !r.ok && /not found/.test(r.error!), r.error);

// --- endpoint custom properties --------------------------------------------------
route = () => ({ status: 200, json: { success: true, data: { name: "Purchase Date" } } });
r = await run("create_resource", { resource_type: "endpoint_custom_property", serial_number: "SN 1", data: { name: "Purchase Date", value: "2024-01-05", dataType: "Date" } });
check("custom property create", r.ok && last().method === "POST" && last().url.pathname === "/v2/endpoint/SN%201/custom-property", last().url.pathname);
r = await run("get_resource", { resource_type: "endpoint_custom_property", serial_number: "SN1", property_name: "Purchase Date" });
check("custom property get", r.ok && last().url.pathname === "/v2/endpoint/SN1/custom-property/Purchase%20Date", last().url.pathname);
r = await run("update_resource", { resource_type: "endpoint_custom_property", serial_number: "SN1", property_name: "Source", data: { value: "ScalePad" } });
check("custom property PATCH", r.ok && last().method === "PATCH" && last().url.pathname === "/v2/endpoint/SN1/custom-property/Source");
r = await run("delete_resource", { resource_type: "endpoint_custom_property", serial_number: "SN1", property_name: "Source" });
check("custom property delete", r.ok && last().method === "DELETE" && last().url.pathname === "/v2/endpoint/SN1/custom-property/Source");
r = await run("create_resource", { resource_type: "assessment", data: {} });
check("assessment create points to assessment_import", !r.ok && /assessment_import/.test(r.error!) && calls.length === 0);

// --- assessment_import -----------------------------------------------------------
route = (c) => {
  if (c.url.pathname === "/v2/assessment/upload") return { status: 204, text: "" };
  if (c.url.pathname === "/v2/odata/assessment") {
    const f = c.url.searchParams.get("$filter") || "";
    if (f.startsWith("assessmentId eq")) return { status: 200, json: { value: [{ assessmentId: 50, title: "Existing Review", type: 20 }] } };
    return { status: 200, json: { value: [
      { assessmentId: 61, title: "Contoso Security Review - 10/7/26", type: 30 },
      { assessmentId: 60, title: "Contoso Security Review", type: 20 },
      { assessmentId: 12, title: "Contoso Security Review", type: 20 },
    ] } };
  }
  return { status: 404, text: "" };
};
const qs = [{ Category: "Identity", Question: "MFA enforced?", Answer: "Yes", "Update Key": "mfa" }];
r = await run("assessment_import", { company_id: 9, title: "Contoso Security Review", questions: qs });
const up = calls.find((c) => c.url.pathname === "/v2/assessment/upload");
check("create goes through upload, no POST /v2/assessment", r.ok && !!up && !calls.some((c) => c.url.pathname === "/v2/assessment"), r.error);
check("new assessment found by title + type 20 (newest)", r.ok && (r.value as any).assessmentId === 60 && (r.value as any).created === true, JSON.stringify(r.value));
r = await run("assessment_import", { company_id: 9, assessment_id: 50, questions: qs });
check("refresh keeps the current title", r.ok && calls[0].url.searchParams.get("$filter") === "assessmentId eq 50" && (r.value as any).assessmentId === 50 && (r.value as any).created === false, JSON.stringify(r.value));
r = await run("assessment_import", { company_id: 9, template_id: 4, title: "X" });
check("template without assessment_id is refused", !r.ok && /needs assessment_id/.test(r.error!) && calls.length === 0, r.error);
r = await run("assessment_import", { company_id: 9, title: "X", questions: qs, type: 0 });
check("type 0 refused", !r.ok && calls.length === 0, r.error);

// --- assessment workbook matches the layout the upload accepts live ---------------
const xlsx = new TextDecoder().decode(buildAssessmentXlsx([
  { Category: "Identity", Question: "MFA enforced?", Answer: -2 },
  { Category: "Identity", Question: "SSPR enabled?" },
]));
check("workbook has sharedStrings and styles parts", xlsx.includes("xl/sharedStrings.xml") && xlsx.includes("xl/styles.xml") && !xlsx.includes("inlineStr"));
check("workbook fills Type/Responses/Text Answer/Is Flagged/Order",
  ["List", "Yes,Partially+,Not Applicable=,Unanswered*,No-", "Not compliant", "Missing answer", ">Yes<", ">No<"].every((s) => xlsx.includes(s)) &&
  /<c r="V2"><v>10<\/v><\/c>/.test(xlsx) && /<c r="V3"><v>20<\/v><\/c>/.test(xlsx), "Order is column V");

const g1 = toUpdateKey("mfa-enforced");
check("non-GUID Update Key becomes a stable v3 GUID", /^[0-9a-f]{8}-[0-9a-f]{4}-3[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(g1) && toUpdateKey(" MFA-Enforced ") === g1 && toUpdateKey("other") !== g1, g1);
check("GUID Update Key is kept", toUpdateKey("6F1C2D3E-0000-4000-8000-123456789ABC") === "6f1c2d3e-0000-4000-8000-123456789abc");
check("workbook writes the GUID key", new TextDecoder().decode(buildAssessmentXlsx([{ Category: "A", Question: "B", "Update Key": "mfa-enforced" }])).includes(g1));

// --- company_overview unwraps OData lists ------------------------------------------
route = (c) => c.url.pathname.endsWith("$count") ? { status: 200, text: "4" }
  : c.url.pathname.startsWith("/v2/odata/") ? { status: 200, json: { value: [{ id: 1 }] } }
  : { status: 200, json: { success: true, data: { companyId: 9, name: "Contoso" } } };
r = await run("company_overview", { company_id: "9" });
check("company_overview lists are arrays", r.ok && Array.isArray((r.value as any).recentArticles) && (r.value as any).counts.userCount === 4, JSON.stringify(r.value));

// --- template import returns a warning -----------------------------------------
route = () => ({ status: 200, text: "" });
{
  const tr = await run("assessment_import", { company_id: 1, assessment_id: 5, template_id: 9, apply_to: "server" });
  check("template import posts to import-template", tr.ok && last().url.pathname === "/v2/assessment/import-template", tr.error);
  check("template import warns that nothing may be copied", tr.ok && typeof (tr.value as any).warning === "string");
}


// --- 2.7.0: PUT/POST stay plain JSON; raw PATCH also uses json-patch ----------------
route = () => ({ status: 204, text: "" });
r = await run("update_resource", { resource_type: "menu", id: "4", method: "PUT", data: { title: "Help" } });
check("PUT stays application/json", r.ok && last().contentType === "application/json", last().contentType);
r = await run("raw_api_call", { path: "/v2/menu/4", method: "PATCH", body: [{ op: "replace", path: "/title", value: "Help" }] });
check("raw PATCH array -> json-patch", r.ok && last().contentType === "application/json-patch+json", last().contentType);

// --- assessment delete -----------------------------------------------------------
route = (c) => c.url.pathname === "/v2/odata/assessment"
  ? { status: 200, json: { value: [{ assessmentId: 176, companyId: 1, type: 20 }] } }
  : { status: 204, text: "" };
r = await run("delete_resource", { resource_type: "assessment", id: "176" });
check("assessment delete looks up companyId", r.ok && last().method === "DELETE" && last().url.pathname === "/v2/assessment/176" &&
  last().url.searchParams.get("companyId") === "1" && !last().url.searchParams.has("includeRuns"), last().url.toString());
r = await run("delete_resource", { resource_type: "assessment", id: "176", company_id: "1", include_runs: true });
check("assessment delete include_runs", r.ok && calls.length === 1 && last().url.searchParams.get("includeRuns") === "true", last().url.toString());

// --- token revoke guard ----------------------------------------------------------
r = await run("manage_tokens", { action: "revoke", token_name: "HelpDeskPhone" });
check("token revoke without company_id refused", !r.ok && /needs company_id/.test(r.error!) && calls.length === 0, r.error);
r = await run("manage_tokens", { action: "revoke", token_name: "HelpDeskPhone", company_id: 0 });
check("partner token revoke needs confirm", !r.ok && /PARTNER-level/.test(r.error!) && calls.length === 0, r.error);
r = await run("manage_tokens", { action: "revoke", token_name: "HelpDeskPhone", company_id: 0, confirm_partner_level: true });
check("partner token revoke with confirm", r.ok && last().method === "DELETE" && last().url.searchParams.get("companyId") === "0");
r = await run("manage_tokens", { action: "revoke", token_name: "HelpDeskPhone", company_id: 1021 });
check("company token revoke", r.ok && last().url.searchParams.get("companyId") === "1021");

// --- list all_pages --------------------------------------------------------------
{
  const page = (n: number, start: number) => Array.from({ length: n }, (_, i) => ({ endpointId: start + i }));
  route = (c) => {
    const skip = Number(c.url.searchParams.get("$skip") ?? 0);
    return { status: 200, json: { value: skip === 0 ? page(200, 0) : skip === 200 ? page(200, 200) : page(37, 400) } };
  };
  r = await run("list_resources", { resource_type: "endpoint", all_pages: true });
  check("all_pages walks $skip until a short page", r.ok && Array.isArray(r.value) && (r.value as any[]).length === 437 && calls.length === 3, `${calls.length} calls`);
  route = (c) => c.url.searchParams.get("$skip") === "0"
    ? { status: 200, json: { value: page(200, 0), "@odata.nextLink": "https://api.example.test/v2/odata/endpoint?$skip=200&$top=200" } }
    : { status: 200, json: { value: page(5, 200) } };
  r = await run("list_resources", { resource_type: "endpoint", all_pages: true });
  check("all_pages follows nextLink as returned", r.ok && (r.value as any[]).length === 205 && calls[1].url.searchParams.get("$skip") === "200", calls.map((c) => c.url.search).join(" | "));
  route = () => ({ status: 200, json: { value: page(200, 0) } });
  r = await run("list_resources", { resource_type: "endpoint", all_pages: true, max_records: 300 });
  check("all_pages reports truncation", r.ok && (r.value as any).truncated === true && (r.value as any).value.length === 300, JSON.stringify(r.value).slice(0, 80));
}

// --- new resource types ----------------------------------------------------------
route = (c) => c.url.pathname.startsWith("/v2/odata/")
  ? { status: 200, json: { value: [{ companyId: 1 }] } }
  : { status: 200, json: { success: true, data: { ok: 1 } } };
r = await run("get_resource", { resource_type: "dashboard", id: "12" });
check("dashboard get looks up companyId", r.ok && calls[0].url.searchParams.get("$filter") === "dashboardId eq 12" && last().url.toString().endsWith("/v2/dashboard/12?companyId=1"), last().url.toString());
r = await run("update_resource", { resource_type: "archive_folder", id: "17", data: { alertKeywords: "failed" } });
check("archive_folder PATCH has no companyId", r.ok && calls.length === 1 && last().url.search === "" && last().contentType === "application/json-patch+json", last().url.toString());
r = await run("delete_resource", { resource_type: "portal_message", id: "8", company_id: "1" });
check("portal_message delete scoped", r.ok && last().url.toString().endsWith("/v2/message/8?companyId=1"));
r = await run("create_resource", { resource_type: "signal_message", data: { title: "x" } });
check("signal_message generic create blocked", !r.ok && /signal_message tool/.test(r.error!) && calls.length === 0, r.error);
r = await run("delete_resource", { resource_type: "article_feedback", id: "3" });
check("article_feedback delete (2.8.0)", r.ok && last().method === "DELETE" && last().url.pathname === "/v2/articlefeedback/3");
r = await run("update_resource", { resource_type: "article_feedback", id: "3", data: { rating: "1" } });
check("article_feedback PATCH points to PUT", !r.ok && /PUT/.test(r.error!) && calls.length === 0);

// --- archive_upload --------------------------------------------------------------
{
  const { mkdtempSync, writeFileSync } = await import("node:fs");
  const { join } = await import("node:path");
  const { tmpdir } = await import("node:os");
  const dir = mkdtempSync(join(tmpdir(), "cr-upload-"));
  const pdf = join(dir, "backup-report.pdf"); writeFileSync(pdf, "%PDF-1.4 test");
  const empty = join(dir, "empty.pdf"); writeFileSync(empty, "");
  route = (c) => {
    if (c.url.pathname === "/v2/odata/archivefolder") return { status: 200, json: { value: [{ companyReportFolderId: 17, companyId: 1, name: "Nightly Backups" }] } };
    if (c.url.pathname === "/v2/archivefolder") return { status: 201, json: { success: true, data: { archiveFolderId: 21, name: "QBR" } } };
    if (c.url.pathname === "/v2/archiveitem/upload") return { status: 201, json: { success: true, data: { archiveItemIds: [9021], items: [{ archiveItemId: 9021, subject: "s", isError: false, attachments: [{ fileName: "backup-report.pdf", length: 13 }] }] } } };
    return { status: 404, text: "" };
  };
  r = await run("archive_upload", { company_id: 1, folder_name: "nightly backups", file_paths: [pdf], subject: "Nightly backup" });
  const upl = calls.find((c) => c.url.pathname === "/v2/archiveitem/upload");
  check("archive_upload finds folder by name and posts multipart", r.ok && !!upl && JSON.stringify(upl!.form) ===
    JSON.stringify([["archiveId", "17"], ["subject", "Nightly backup"], ["files", "file:backup-report.pdf:13"]]), JSON.stringify(upl?.form ?? r.error));
  check("archive_upload summarises items", r.ok && (r.value as any).uploaded[0].archiveItemId === 9021 && (r.value as any).folderCreated === false);
  r = await run("archive_upload", { company_id: 1, folder_name: "QBR", file_paths: [pdf] });
  check("missing folder refused without create_folder", !r.ok && /Nightly Backups/.test(r.error!) && !calls.some((c) => c.method === "POST"), r.error);
  r = await run("archive_upload", { company_id: 1, folder_name: "QBR", create_folder: true, alert_keywords: "failed", file_paths: [pdf] });
  const mk = calls.find((c) => c.url.pathname === "/v2/archivefolder");
  check("create_folder creates then uploads", r.ok && (mk?.body as any)?.alertKeywords === "failed" && (r.value as any).archiveId === 21 && (r.value as any).folderCreated === true, r.error);
  r = await run("archive_upload", { company_id: 1, folder_name: "Nightly Backups", file_paths: [empty] });
  check("empty file refused before any call", !r.ok && /empty/.test(r.error!) && calls.length === 0, r.error);
  r = await run("archive_upload", { company_id: 1, folder_name: "Nightly Backups", file_paths: [join(dir, "nope.pdf")] });
  check("missing file refused", !r.ok && /not found/.test(r.error!) && calls.length === 0, r.error);
}

// --- signal_message --------------------------------------------------------------
route = (c) => {
  if (c.url.pathname === "/v2/signalmessage/estimate") return { status: 200, json: { success: true, data: { users: 1, companies: 1 } } };
  if (c.url.pathname === "/v2/signalmessage" && c.method === "POST") return { status: 201, json: { success: true, data: { id: 412, version: 1 } } };
  if (c.url.pathname === "/v2/signalmessage/412" && c.method === "GET") return { status: 200, json: { success: true, data: { id: 412, version: 3, title: "Old", priority: 0 } } };
  return { status: 200, json: { success: true, data: { ok: true } } };
};
const sig = { company_ids: [1021], user_ids: ["8d3f"], title: "Your password expires on Friday", deep_link_url: "https://passwordreset.microsoftonline.com/", deep_link_label: "Change Password" };
r = await run("signal_message", { action: "send", ...sig });
check("send without confirmed only estimates", r.ok && (r.value as any).sent === false && calls.length === 1 && last().url.pathname === "/v2/signalmessage/estimate", JSON.stringify(r.value).slice(0, 120));
const key1 = (calls[0].body as any).dedupeKey;
r = await run("signal_message", { action: "send", confirmed: true, ...sig });
const pub = calls.find((c) => c.url.pathname === "/v2/signalmessage");
check("confirmed send publishes with a stable dedupe key", r.ok && (r.value as any).sent === true && (pub?.body as any)?.dedupeKey === key1 && /^ucp-[0-9a-f]{40}$/.test(key1), key1);
check("send body maps fields", (pub?.body as any)?.users?.[0] === "8d3f" && (pub?.body as any)?.deepLinkLabel === "Change Password" && (pub?.body as any)?.companyIds?.[0] === 1021);
r = await run("signal_message", { action: "send", confirmed: true, ...sig, deep_link_url: "http://x.test" });
check("http deep link refused", !r.ok && /https/.test(r.error!) && calls.length === 0, r.error);
r = await run("signal_message", { action: "send", confirmed: true, ...sig, priority: 2 });
check("urgent without expires_at refused", !r.ok && /expires_at/.test(r.error!) && calls.length === 0, r.error);
r = await run("signal_message", { action: "send", confirmed: true, title: "x" });
check("no audience refused", !r.ok && /company_ids/.test(r.error!) && calls.length === 0, r.error);
route = (c) => c.url.pathname === "/v2/signalmessage/estimate" ? { status: 200, json: { success: true, data: { users: 0, companies: 1 } } } : { status: 201, json: {} };
r = await run("signal_message", { action: "send", confirmed: true, ...sig });
check("0-user audience not sent", !r.ok && !calls.some((c) => c.url.pathname === "/v2/signalmessage"), r.error);
route = (c) => c.method === "GET" ? { status: 200, json: { success: true, data: { id: 412, version: 3, title: "Old", priority: 0 } } } : { status: 200, json: { success: true, data: { version: 4 } } };
r = await run("signal_message", { action: "retract", id: 412 });
check("retract reads version then posts it", r.ok && calls.length === 2 && last().url.pathname === "/v2/signalmessage/412/retract" && (last().body as any).version === 3, JSON.stringify(last().body));
r = await run("signal_message", { action: "edit", id: 412, body: "New text" });
check("edit keeps title, sends version", r.ok && last().method === "PUT" && (last().body as any).title === "Old" && (last().body as any).body === "New text" && (last().body as any).version === 3, JSON.stringify(last().body));
route = (c) => c.method === "GET" ? { status: 200, json: { success: true, data: { id: 412, version: 5, title: "Old", priority: "Important", expiresAt: new Date(Date.now() + 7 * 86400000).toISOString() } } } : { status: 200, json: { success: true, data: { version: 6 } } };
{
  const er = await run("signal_message", { action: "edit", id: 412, body: "x" });
  check("edit maps a named priority back to its number", er.ok && (last().body as any).priority === 1, er.error ?? JSON.stringify(last().body));
}

// --- m365_secure_score -----------------------------------------------------------
route = (c) => c.url.pathname === "/v2/m365/tenant"
  ? { status: 200, json: { success: true, data: [
      { microsoftTenantId: 3, name: "Contoso", companyId: 1021, secureScore: 933.5, secureScoreMax: 1457, secureScorePercentage: 0.64071 },
      { microsoftTenantId: 4, name: "Fabrikam", companyId: null, secureScorePercentage: 0.3 },
    ] } }
  : { status: 200, json: { success: true, data: { cached: true, currentScore: 933.5, maxScore: 1457, controls: [
      { title: "A", score: 10, maxScore: 10 },
      { title: "B", score: 1, maxScore: 9 },
      { title: "C", score: 0, maxScore: 5, deprecated: true },
      { title: "D", score: 0, maxScore: 3 },
    ] } } };
r = await run("m365_secure_score", { company_id: 1021, top: 5 });
const t0 = (r.value as any)?.tenants?.[0];
check("secure score ranks open actions", r.ok && t0.percent === 64.1 && t0.topActions.map((a: any) => a.title).join() === "B,D" && t0.topActions[0].pointsAvailable === 8, JSON.stringify(t0).slice(0, 160));
r = await run("m365_secure_score", {});
check("secure score roll-up sorts lowest first", r.ok && (r.value as any).ranking[0].tenant === "Fabrikam" && (r.value as any).unlinked === 1);
r = await run("m365_secure_score", { company_id: 77 });
check("unlinked company explained", !r.ok && /No Microsoft tenant/.test(r.error!), r.error);

// --- assessment_lifecycle --------------------------------------------------------
route = (c) => c.url.pathname === "/v2/odata/assessment"
  ? { status: 200, json: { value: [{ assessmentId: 60, companyId: 1, title: "Security Review", type: 20 }] } }
  : { status: 201, json: { success: true, data: { assessmentId: 99 } } };
r = await run("assessment_lifecycle", { action: "run", assessment_id: 60 });
check("run posts companyId and a dated name", r.ok && last().url.pathname === "/v2/assessment/60/run" && (last().body as any).companyId === 1 && /^Security Review - \d{4}-\d{2}-\d{2}$/.test((last().body as any).name), JSON.stringify(last().body));
r = await run("assessment_lifecycle", { action: "archive", assessment_id: 60, company_id: 1 });
check("archive scoped", r.ok && calls.length === 1 && last().url.toString().endsWith("/v2/assessment/60/archive?companyId=1"));
r = await run("assessment_lifecycle", { action: "delete_run", assessment_id: 60, run_id: 61, company_id: 1 });
check("delete_run", r.ok && last().method === "DELETE" && last().url.toString().endsWith("/v2/assessment/60/run/61?companyId=1"));

// === 2.8.0 =========================================================================
// --- sensitive generic writes need confirmed ---------------------------------------
route = () => ({ status: 200, json: { success: true, data: { roleId: "r1" } } });
r = await run("create_resource", { resource_type: "role", data: { name: "Helpdesk" } });
check("role create without confirmed refused", !r.ok && /confirmed=true/.test(r.error!) && calls.length === 0, r.error);
r = await run("create_resource", { resource_type: "role", data: { name: "Helpdesk" }, confirmed: true });
check("role create with confirmed", r.ok && last().method === "POST" && last().url.pathname === "/v2/role");
r = await run("delete_resource", { resource_type: "feature_set", id: "4" });
check("feature_set delete needs confirmed", !r.ok && calls.length === 0);
r = await run("update_resource", { resource_type: "role_assignment", id: "4", data: {}, confirmed: true });
check("role_assignment can't be edited", !r.ok && /Delete the assignment/.test(r.error!) && calls.length === 0, r.error);
r = await run("create_resource", { resource_type: "webhook", data: { name: "x" }, confirmed: true });
check("webhook create routed to webhook_action", !r.ok && /webhook_action/.test(r.error!) && calls.length === 0, r.error);
r = await run("update_resource", { resource_type: "article", id: "1", data: { subject: "x" } });
check("non-sensitive update needs no confirm", r.ok);

// --- non-OData lists ----------------------------------------------------------------
route = () => ({ status: 200, json: { success: true, data: [{ roleId: "r1" }] } });
r = await run("list_resources", { resource_type: "role_assignment", params: { userId: "u1", pageSize: 50 } });
check("role_assignment list uses plain GET with params", r.ok && last().url.pathname === "/v2/roleassignment" && last().url.searchParams.get("userId") === "u1" && last().url.searchParams.get("pageSize") === "50", last().url.toString());
r = await run("list_resources", { resource_type: "role", filter: "name eq 'x'" });
check("OData filter refused on plain list", !r.ok && /params/.test(r.error!) && calls.length === 0, r.error);

// --- policy and license company scoping --------------------------------------------
route = (c) => c.url.pathname.startsWith("/v2/odata/") ? { status: 200, json: { value: [{ companyId: 7 }] } } : { status: 204, text: "" };
r = await run("update_resource", { resource_type: "policy", id: "3", method: "PUT", data: { name: "Age" }, confirmed: true });
check("policy PUT sends no companyId", r.ok && calls.length === 1 && last().url.search === "", last().url.toString());
r = await run("delete_resource", { resource_type: "license", id: "3", confirmed: true });
check("license delete looks up companyId", r.ok && last().url.searchParams.get("companyId") === "7", last().url.toString());

// --- access_control -----------------------------------------------------------------
route = (c) => {
  if (c.url.pathname === "/v2/role/r9") return { status: 200, json: { success: true, data: { roleId: "r9", name: "Approver", isPartnerRole: false } } };
  if (c.url.pathname === "/v2/featureset/2/companies" && c.method === "GET") return { status: 200, json: { success: true, data: [{ companyId: 1 }, { companyId: 2 }] } };
  if (c.url.pathname === "/v2/odata/userlicense") return { status: 200, json: { value: [{ userId: "a" }, { userId: "b" }] } };
  return { status: 200, json: { success: true, data: { ok: true } } };
};
r = await run("access_control", { action: "assign_role", role_id: "r9", user_id: "u1", scope: "company", scope_id: 1021 });
check("assign_role previews without confirmed", r.ok && (r.value as any).changed === false && !calls.some((c) => c.method === "POST"), JSON.stringify(r.value).slice(0, 120));
r = await run("access_control", { action: "assign_role", role_id: "r9", user_id: "u1", scope: "company", scope_id: 1021, confirmed: true });
check("assign_role posts scopeType 3 memberType 1", r.ok && last().url.pathname === "/v2/roleassignment" && (last().body as any).scopeType === 3 && (last().body as any).memberType === 1 && (last().body as any).scopeId === 1021);
r = await run("access_control", { action: "set_feature_set_companies", feature_set_id: 2, company_ids: [2, 3] });
check("feature set preview shows added/removed", r.ok && JSON.stringify((r.value as any).preview.added) === "[3]" && JSON.stringify((r.value as any).preview.removed) === "[1]" && !calls.some((c) => c.method === "PUT"), JSON.stringify(r.value));
r = await run("access_control", { action: "set_license_users", license_id: 5, company_id: 1, user_ids: ["b", "c"] });
check("license users preview", r.ok && JSON.stringify((r.value as any).preview.added) === '["c"]' && JSON.stringify((r.value as any).preview.removed) === '["a"]');
r = await run("access_control", { action: "set_support_pin", user_id: "u1", company_id: 1, support_pin: "4821", confirmed: true });
check("support PIN set, never echoed", r.ok && last().url.pathname === "/v2/user/u1/supportpin" && (last().body as any).supportPin === "4821" && !JSON.stringify(r.value).includes("4821"));

// --- webhook_action -----------------------------------------------------------------
{
  const { mkdtempSync, writeFileSync: wf, readFileSync: rf, statSync: st } = await import("node:fs");
  const { join } = await import("node:path");
  const { tmpdir } = await import("node:os");
  const home = mkdtempSync(join(tmpdir(), "cr-home-"));
  process.env.HOME = home; process.env.USERPROFILE = home;
  const hv = join(home, "headers.json"); wf(hv, JSON.stringify({ Authorization: "Bearer s3cret" }));
  route = (c) => c.method === "POST" && c.url.pathname === "/v2/action"
    ? { status: 201, json: { success: true, data: { action: { actionId: 12, name: "PSA hook" }, signingSecret: "whsec_TOPSECRET" } } }
    : { status: 200, json: { success: true, data: { actionId: 12, name: "PSA hook", url: "https://x.test/hook", isEnabled: true, headers: [{ name: "Authorization" }] } } };
  r = await run("webhook_action", { action: "create", name: "PSA hook", url: "https://x.test/hook", header_names: ["Authorization"], header_values_file: hv });
  check("webhook create previews, hides header value", r.ok && (r.value as any).changed === false && !JSON.stringify(r.value).includes("s3cret") && calls.length === 0, JSON.stringify(r.value).slice(0, 160));
  r = await run("webhook_action", { action: "create", name: "PSA hook", url: "https://x.test/hook", header_names: ["Authorization"], header_values_file: hv, confirmed: true });
  const savedTo = (r.value as any)?.signingSecretSavedTo as string;
  check("signing secret saved to file, not returned", r.ok && !JSON.stringify(r.value).includes("TOPSECRET") && !!savedTo && rf(savedTo, "utf8").trim() === "whsec_TOPSECRET", JSON.stringify(r.value).slice(0, 200));
  if (process.platform !== "win32") check("secret file is private", (st(savedTo).mode & 0o077) === 0, (st(savedTo).mode & 0o777).toString(8));
  check("header value sent from file", (calls.find((c) => c.method === "POST")?.body as any)?.headers?.[0]?.value === "Bearer s3cret");
  r = await run("webhook_action", { action: "create", name: "x", url: "http://x.test" , confirmed: true });
  check("webhook http url refused", !r.ok && /https/.test(r.error!), r.error);
  r = await run("webhook_action", { action: "update", id: 12, name: "Renamed", confirmed: true });
  check("webhook update keeps stored header value", r.ok && last().method === "PUT" && (last().body as any).headers[0].value === "" && (last().body as any).name === "Renamed", JSON.stringify(last().body));
  r = await run("webhook_action", { action: "disable", id: 12 });
  check("disable previews without confirmed", r.ok && (r.value as any).changed === false && !calls.some((c) => c.method === "POST"));
}

// --- signal_device / audit / m365 / widgets / upload ------------------------------
route = (c) => c.url.pathname === "/v2/signaldevice" ? { status: 200, json: { success: true, data: [{ installationId: "inst-1", state: "Active" }] } } : { status: 200, json: { success: true, data: { ok: 1 } } };
r = await run("signal_device", { action: "revoke", installation_id: "inst-1" });
check("revoke previews the device", r.ok && (r.value as any).device.installationId === "inst-1" && !calls.some((c) => c.method === "POST"));
r = await run("signal_device", { action: "revoke", installation_id: "inst-1", confirmed: true });
check("revoke posts", r.ok && last().url.pathname === "/v2/signaldevice/inst-1/revoke");
r = await run("signal_device", { action: "revoke", installation_id: "nope" });
check("unknown install refused", !r.ok && /No Signal install/.test(r.error!));
r = await run("audit_log", { action: "events", company_id: 9, entity: "Company", source: "PublicAPI" });
check("audit events filters", r.ok && last().url.pathname === "/v2/audit/event" && last().url.searchParams.get("entity") === "Company" && last().url.searchParams.get("source") === "PublicAPI");
r = await run("audit_log", { action: "sync_log", job_name: "SyncTicketsForCompanyJob", company_id: 9 });
check("sync log path", r.ok && last().url.pathname === "/v2/audit/synclog/SyncTicketsForCompanyJob" && last().url.searchParams.get("companyId") === "9");
r = await run("m365_directory", { action: "roles", company_id: 9 });
check("m365 roles path", r.ok && last().url.pathname === "/v2/m365/company/9/role");
route = (c) => c.url.pathname === "/v2/odata/dashboard" ? { status: 200, json: { value: [{ companyId: 4 }] } } : { status: 200, json: { success: true, data: { id: "w1" } } };
r = await run("dashboard_widgets", { action: "add", dashboard_id: 12, widget: { type: "Html", title: "Hi", html: "<p>x</p>" } });
check("widget add scoped by dashboard company", r.ok && last().url.toString().endsWith("/v2/dashboard/12/widget?companyId=4"), last().url.toString());
r = await run("dashboard_widgets", { action: "replace_all", dashboard_id: 12, widgets: [] });
check("replace_all needs confirmed", r.ok && (r.value as any).changed === false && !calls.some((c) => c.method === "PUT"));
{
  const { mkdtempSync, writeFileSync: wf } = await import("node:fs");
  const { join } = await import("node:path");
  const { tmpdir } = await import("node:os");
  const d = mkdtempSync(join(tmpdir(), "cr-up-")); const img = join(d, "logo.png"); wf(img, "PNGDATA");
  route = () => ({ status: 201, json: { success: true, data: { id: 3 } } });
  r = await run("upload_file", { target: "media", file_paths: [img], description: "Contoso logo" });
  check("media upload multipart + description query", r.ok && last().url.pathname === "/v2/media/upload" && last().url.searchParams.get("description") === "Contoso logo" && JSON.stringify(last().form) === JSON.stringify([["file", "file:logo.png:7"]]), JSON.stringify(last().form));
  r = await run("upload_file", { target: "quickstart_file", quickstart_id: 8, file_paths: [img] });
  check("quickstart file is a PUT", r.ok && last().method === "PUT" && last().url.pathname === "/v2/quickstart/8/file");
  r = await run("upload_file", { target: "message_attachment", message_id: 4, company_id: 1, file_paths: [img, img] });
  check("message attachments repeat Files", r.ok && last().url.searchParams.get("companyId") === "1" && last().form!.filter(([k]) => k === "Files").length === 2);
}

// --- assessment create / questions / answers ----------------------------------------
route = (c) => c.url.pathname === "/v2/odata/assessment" ? { status: 200, json: { value: [{ assessmentId: 60, companyId: 1, title: "R", type: 20 }] } } : { status: 200, json: { success: true, data: { assessmentId: 70 } } };
r = await run("assessment_lifecycle", { action: "create", company_id: 1, title: "Baseline", questions: [{ label: "MFA?", type: 80, order: 1, answerOptions: [{ label: "Yes", value: 2 }] }] });
check("assessment create posts type 20 and stringified fields", r.ok && last().url.pathname === "/v2/assessment" && (last().body as any).type === "20" && (last().body as any).questions[0].type === "80" && (last().body as any).questions[0].answerOptions[0].value === "2", JSON.stringify(last().body));
r = await run("assessment_lifecycle", { action: "create", company_id: 1, title: "x", questions: [{ label: "y", type: 30 }] });
check("question type other than 0/80 refused", !r.ok && /0 \(free text\) or 80/.test(r.error!) && calls.length === 0, r.error);
r = await run("assessment_lifecycle", { action: "set_questions", assessment_id: 60, questions: [{ label: "a" }], remove_missing: true });
check("remove_missing needs confirmed", !r.ok && /confirmed=true/.test(r.error!) && !calls.some((c) => c.method === "PUT"));
r = await run("assessment_lifecycle", { action: "set_answers", assessment_id: 60, answers: [{ updateKey: "mfa", value: -2 }] });
check("answers PATCH is plain JSON object", r.ok && last().method === "PATCH" && last().contentType === "application/json" && (last().body as any).answers[0].value === "-2" && last().url.searchParams.get("companyId") === "1", last().contentType);
r = await run("assessment_lifecycle", { action: "set_answers", assessment_id: 60, answers: [{ updateKey: "mfa", value: 5 }] });
check("bad answer value refused", !r.ok && /2, 1, 0, -1 or -2/.test(r.error!));
r = await run("assessment_lifecycle", { action: "update_question", assessment_id: 60, question_id: 9, company_id: 1, data: { label: "New" } });
check("update_question is JSON Patch", r.ok && last().contentType === "application/json-patch+json" && last().url.pathname === "/v2/assessment/60/question/9");

console.log(failed ? `${failed} FAILED` : "ALL PASSED");
process.exit(failed ? 1 : 0);
