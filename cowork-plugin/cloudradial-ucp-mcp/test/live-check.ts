// Live checks of the tools against a real CloudRadial tenant. Run against a demo or
// test company only:
//
//   CLOUDRADIAL_PUBLIC_KEY / CLOUDRADIAL_PRIVATE_KEY / CLOUDRADIAL_BASE_URL  API keys (never printed)
//   LIVE_COMPANY_ID     the company to write to
//   LIVE_COMPANY_NAME   its exact name; the run stops unless they match
//
// npm run test:live. It writes only to that company and cleans up what the API lets
// it delete. It leaves one assessment, "Plugin live check (create)", because the API
// can't delete assessments; re-runs reuse it.
import { writeFileSync } from "node:fs";
import { tools } from "../src/tools.js";

const COMPANY = Number(process.env.LIVE_COMPANY_ID);
const COMPANY_NAME = (process.env.LIVE_COMPANY_NAME ?? "").trim();
if (!COMPANY || !COMPANY_NAME) {
  console.error("Set LIVE_COMPANY_ID and LIVE_COMPANY_NAME to a demo or test company.");
  process.exit(2);
}
const TAG = "Plugin live check";
const call = (name: string, args: Record<string, unknown>) => tools.find((t) => t.name === name)!.handler(args);
const results: { check: string; result: "PASS" | "FAIL" | "SKIP"; detail: string }[] = [];
const rec = (check: string, result: "PASS" | "FAIL" | "SKIP", detail = "") => {
  results.push({ check, result, detail });
  console.log(`${result.padEnd(4)} ${check}${detail ? " -- " + detail : ""}`);
};
const msg = (e: unknown) => (e instanceof Error ? e.message : String(e)).slice(0, 300);
const arr = (v: unknown) => (Array.isArray(v) ? (v as Record<string, any>[]) : []);
async function step(name: string, fn: () => Promise<void>) {
  try { await fn(); } catch (e) { rec(name, "FAIL", msg(e)); }
}

// 0. Guard: the keys must reach the named company.
let company: Record<string, any>;
try {
  company = (await call("get_resource", { resource_type: "company", id: String(COMPANY) })) as Record<string, any>;
} catch (e) {
  console.error(/HTTP 401/.test(msg(e)) ? "CloudRadial rejected the API keys (HTTP 401). Check them and run again. Nothing was changed." : msg(e));
  process.exit(2);
}
if (String(company?.name ?? "").trim().toLowerCase() !== COMPANY_NAME.toLowerCase()) {
  console.error(`Company ${COMPANY} is "${company?.name}", not "${COMPANY_NAME}". Stopping without changes.`);
  process.exit(2);
}
rec(`guard: company ${COMPANY} is ${COMPANY_NAME}`, "PASS", String(company.name));

// 1. AAI-126: catalog question get + PATCH without company_id.
await step("catalog_question get + PATCH (companyId lookup)", async () => {
  const qs = arr(await call("list_resources", { resource_type: "catalog_question", filter: `companyId eq ${COMPANY}`, top: "5" }));
  if (!qs.length) return rec("catalog_question get + PATCH (companyId lookup)", "SKIP", "no catalog questions in the company");
  const q = qs[0];
  const id = String(q.companyCatalogQuestionId);
  const got = (await call("get_resource", { resource_type: "catalog_question", id })) as Record<string, any>;
  if (String(got?.companyCatalogQuestionId ?? got?.id) !== id) throw new Error(`get returned ${JSON.stringify(got).slice(0, 200)}`);
  await call("update_resource", { resource_type: "catalog_question", id, data: { label: got.label } });
  const again = (await call("get_resource", { resource_type: "catalog_question", id })) as Record<string, any>;
  rec("catalog_question get + PATCH (companyId lookup)", again.label === got.label ? "PASS" : "FAIL", `question ${id}, label unchanged`);
});

// 2. user get + PATCH (companyId required on PATCH).
await step("user get + PATCH (companyId lookup)", async () => {
  const us = arr(await call("list_resources", { resource_type: "user", filter: `companyId eq ${COMPANY}`, top: "1" }));
  if (!us.length) return rec("user get + PATCH (companyId lookup)", "SKIP", "no users in the company");
  const id = String(us[0].userId);
  const got = (await call("get_resource", { resource_type: "user", id })) as Record<string, any>;
  await call("update_resource", { resource_type: "user", id, data: { firstName: got.firstName } });
  rec("user get + PATCH (companyId lookup)", "PASS", `firstName unchanged`);
});

// 3. A failed delete is an error, not {deleted:true}.
await step("failed delete reports an error", async () => {
  try {
    const r = await call("delete_resource", { resource_type: "article", id: "2147480000" });
    rec("failed delete reports an error", "FAIL", `returned ${JSON.stringify(r)}`);
  } catch (e) {
    rec("failed delete reports an error", /HTTP 4\d\d/.test(msg(e)) ? "PASS" : "FAIL", msg(e));
  }
});

// 4. assessment_import: create through upload, then refresh in place.
await step("assessment_import create + refresh", async () => {
  const q = (answer: number) => [
    { Category: "Live check", Question: "Plugin can create an assessment", Order: 1, Answer: answer, "Update Key": "plugin-live-1" },
    { Category: "Live check", Question: "Plugin can refresh an assessment", Order: 2, Answer: 2, "Update Key": "plugin-live-2" },
  ];
  // A new title so the create path runs once; re-runs reuse it.
  const title = `${TAG} (create)`;
  const rows = async () => arr(await call("list_resources", { resource_type: "assessment", filter: `companyId eq ${COMPANY}`, top: "200" }))
    .filter((a) => a.title === title && Number(a.type) === 20);
  const before = await rows();
  let id: number;
  if (before.length) {
    id = Number(before[0].assessmentId);
    rec("assessment_import create", "SKIP", `"${title}" already exists (${id}) from an earlier run; testing refresh only`);
  } else {
    const created = (await call("assessment_import", { company_id: COMPANY, title, questions: q(2) })) as Record<string, any>;
    if (!created.assessmentId) throw new Error(`created, but no id: ${JSON.stringify(created)}`);
    id = Number(created.assessmentId);
    const a = (await call("get_resource", { resource_type: "assessment", id: String(id) })) as Record<string, any>;
    rec("assessment_import create", a.maxScore === 4 && a.totalScore === 4 ? "PASS" : "FAIL", `assessment ${id}, maxScore ${a.maxScore}, totalScore ${a.totalScore} (expected 4, 4)`);
  }
  // Refresh twice with different answers: the same questions must update, not duplicate.
  const scores: string[] = [];
  for (const answer of [2, -2]) {
    const r = (await call("assessment_import", { company_id: COMPANY, assessment_id: id, questions: q(answer) })) as Record<string, any>;
    if (r.assessmentId !== id) throw new Error(`refresh returned ${JSON.stringify(r)}`);
    const a = (await call("get_resource", { resource_type: "assessment", id: String(id) })) as Record<string, any>;
    scores.push(`${a.totalScore}/${a.maxScore}`);
    if (a.title !== title) throw new Error(`title changed to "${a.title}"`);
  }
  const dupes = (await rows()).length;
  rec("assessment_import refresh in place", scores[0] === "4/4" && scores[1] === "0/4" && dupes === 1 ? "PASS" : "FAIL",
    `id ${id}, total/max after answers (2,2): ${scores[0]}, after (-2,2): ${scores[1]} (expected 4/4 then 0/4), rows with this title: ${dupes}`);
});

// 5. Endpoint custom property create / get / PATCH / delete.
await step("endpoint_custom_property CRUD", async () => {
  const eps = arr(await call("list_resources", { resource_type: "endpoint", filter: `companyId eq ${COMPANY} and serialNumber ne null and serialNumber ne ''`, top: "1" }));
  if (!eps.length) return rec("endpoint_custom_property CRUD", "SKIP", "no endpoint with a serial number in the company");
  const serial = String(eps[0].serialNumber);
  const name = "PluginLiveCheck";
  await call("create_resource", { resource_type: "endpoint_custom_property", serial_number: serial, data: { name, value: "1" } });
  const got = (await call("get_resource", { resource_type: "endpoint_custom_property", serial_number: serial, property_name: name })) as Record<string, any>;
  await call("update_resource", { resource_type: "endpoint_custom_property", serial_number: serial, property_name: name, data: { value: "2" } });
  const upd = (await call("get_resource", { resource_type: "endpoint_custom_property", serial_number: serial, property_name: name })) as Record<string, any>;
  await call("delete_resource", { resource_type: "endpoint_custom_property", serial_number: serial, property_name: name });
  let gone = false;
  try { await call("get_resource", { resource_type: "endpoint_custom_property", serial_number: serial, property_name: name }); } catch { gone = true; }
  rec("endpoint_custom_property CRUD", got?.value === "1" && upd?.value === "2" && gone ? "PASS" : "FAIL",
    `created 1 -> read ${got?.value}, patched -> ${upd?.value}, deleted: ${gone}`);
});

// 6. Flexible asset traits PATCH (same values, so nothing changes).
await step("flexible_asset traits PATCH", async () => {
  const fas = arr(await call("list_resources", { resource_type: "flexible_asset", filter: `companyId eq ${COMPANY}`, top: "1" }));
  if (!fas.length) return rec("flexible_asset traits PATCH", "SKIP", "no flexible assets in the company");
  const id = String(fas[0].id);
  const got = (await call("get_resource", { resource_type: "flexible_asset", id })) as Record<string, any>;
  const traits = got.traits ?? (got.traitsJson ? JSON.parse(got.traitsJson) : undefined);
  if (traits === undefined) return rec("flexible_asset traits PATCH", "SKIP", `asset ${id} has no traits field: ${Object.keys(got).join(",")}`);
  await call("update_resource", { resource_type: "flexible_asset", id, data: { traits } });
  const again = (await call("get_resource", { resource_type: "flexible_asset", id })) as Record<string, any>;
  const after = again.traits ?? (again.traitsJson ? JSON.parse(again.traitsJson) : undefined);
  rec("flexible_asset traits PATCH", JSON.stringify(after) === JSON.stringify(traits) ? "PASS" : "FAIL", `asset ${id}, traits unchanged`);
});

// 7. Planner items with string and integer status/priority, then deleted.
await step("planner item status/priority", async () => {
  const ps = arr(await call("list_resources", { resource_type: "product", filter: `companyId eq ${COMPANY}`, top: "1" }));
  if (!ps.length) return rec("planner item status/priority", "SKIP", "no existing product to copy productCategoryId from");
  const base = {
    companyId: COMPANY, productCategoryId: ps[0].productCategoryId, category: ps[0].category ?? "Live check",
    body: "Created by the plugin live check. Safe to delete.", summary: "Plugin live check",
    datePublished: new Date().toISOString(), isRequired: false, isShowPrice: false, isClientVisible: false,
  };
  for (const [label, status, priority] of [["strings", "Proposed", "Low"], ["integers", 0, -1]] as const) {
    let id: string | undefined;
    try {
      const created = (await call("create_resource", { resource_type: "product", data: { ...base, subject: `${TAG} (${label}) - delete me`, status, priority } })) as Record<string, any>;
      id = String(created?.productId ?? created?.id ?? "");
      const got = (await call("get_resource", { resource_type: "product", id })) as Record<string, any>;
      rec(`planner item with ${label}`, "PASS", `product ${id}, status ${JSON.stringify(got.status)}, priority ${JSON.stringify(got.priority)}`);
    } catch (e) {
      rec(`planner item with ${label}`, "FAIL", msg(e));
    } finally {
      if (id) await call("delete_resource", { resource_type: "product", id }).catch((e) => rec(`delete planner item ${id}`, "FAIL", msg(e)));
    }
  }
});

const out = new URL("./live-check-results.json", import.meta.url); // next to the built script, under dist/
writeFileSync(out, JSON.stringify({ ranAt: new Date().toISOString(), results }, null, 2));
const failed = results.filter((r) => r.result === "FAIL").length;
console.log(`\n${failed ? failed + " FAILED" : "No failures"} (${results.length} checks). Results: ${out.pathname}`);
process.exit(failed ? 1 : 0);
