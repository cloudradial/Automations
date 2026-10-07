// Mock-fetch tests for the generic and custom tools. Run with `npm test`.
import { tools } from "../src/tools.js";

process.env.CLOUDRADIAL_PUBLIC_KEY = "test-public";
process.env.CLOUDRADIAL_PRIVATE_KEY = "test-private";
process.env.CLOUDRADIAL_BASE_URL = "https://api.example.test";

type Call = { method: string; url: URL; body?: unknown };
const calls: Call[] = [];
let route: (c: Call) => { status: number; json?: unknown; text?: string } = () => ({ status: 200, json: {} });

(globalThis as any).fetch = async (url: string, init: RequestInit) => {
  let body: unknown = init.body;
  if (typeof body === "string") { try { body = JSON.parse(body); } catch { /* keep */ } }
  const c: Call = { method: init.method || "GET", url: new URL(url), body };
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
check("course_enrollment delete blocked", !r.ok && calls.length === 0, r.error);
r = await run("update_resource", { resource_type: "assessment", id: "9", data: {} });
check("assessment update points to assessment_import", !r.ok && /assessment_import/.test(r.error!), r.error);

r = await run("update_resource", { resource_type: "flexible_asset", id: "9", data: { traits: { name: "Core switch", ip: "10.0.0.1" } } });
check("flexible_asset traits -> traitsJson", r.ok && last().url.pathname === "/v2/flexible-asset/9" &&
  JSON.stringify(last().body) === JSON.stringify([{ op: "replace", path: "/traitsJson", value: JSON.stringify({ name: "Core switch", ip: "10.0.0.1" }) }]), JSON.stringify(last().body));

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

// --- company_overview unwraps OData lists ------------------------------------------
route = (c) => c.url.pathname.endsWith("$count") ? { status: 200, text: "4" }
  : c.url.pathname.startsWith("/v2/odata/") ? { status: 200, json: { value: [{ id: 1 }] } }
  : { status: 200, json: { success: true, data: { companyId: 9, name: "Contoso" } } };
r = await run("company_overview", { company_id: "9" });
check("company_overview lists are arrays", r.ok && Array.isArray((r.value as any).recentArticles) && (r.value as any).counts.userCount === 4, JSON.stringify(r.value));

console.log(failed ? `${failed} FAILED` : "ALL PASSED");
process.exit(failed ? 1 : 0);
