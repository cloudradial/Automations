import { createHash } from "node:crypto";

// Minimal .xlsx writer for the CloudRadial assessment upload (POST /v2/assessment/upload).
// Writes one sheet named "Assessment" with the 51-column CloudRadial assessment template
// header, the same layout the Secure Score workflow uploads successfully. No dependencies:
// the zip uses the "stored" method (no compression), which every xlsx reader accepts.

export const ASSESSMENT_COLUMNS = [
  "Partner Notes", "Monthly Unit Cost", "Project Unit Cost", "Psa Board", "Psa Item", "Psa Status",
  "Psa Category", "Psa Sub Type", "Psa Type", "Psa Priority", "Psa Source", "Psa Estimated Time",
  "Email List", "Teams Webhook", "Slack Webhook", "Flow Webhook", "Json Webhook", "Script", "Checklist",
  "Category", "Question", "Order", "Explanation", "Type", "Answer", "Text Answer", "Responses",
  "Is Flagged", "Notes", "Evaluation", "Remediation Summary", "Remediation", "Reference",
  "Monthly Units", "Monthly Unit Price", "Project Units", "Project Unit Price", "Control Type",
  "Likelihood", "Risk", "Risk Cost", "Risk Impact", "Owner", "Updated by", "Update Key",
  "Content Update Key", "Note Compliant", "Note Partially Compliant", "Note NA", "Note Missing",
  "Note Not Compliant",
] as const;

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf: Uint8Array): number {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function zipStored(files: { name: string; data: string }[]): Uint8Array {
  const enc = new TextEncoder();
  const locals: Uint8Array[] = [];
  const centrals: Uint8Array[] = [];
  let offset = 0;
  for (const f of files) {
    const name = enc.encode(f.name);
    const data = enc.encode(f.data);
    const crc = crc32(data);
    const local = new Uint8Array(30 + name.length + data.length);
    const lv = new DataView(local.buffer);
    lv.setUint32(0, 0x04034b50, true); lv.setUint16(4, 20, true); lv.setUint16(6, 0x0800, true);
    lv.setUint16(8, 0, true); lv.setUint32(14, crc, true);
    lv.setUint32(18, data.length, true); lv.setUint32(22, data.length, true);
    lv.setUint16(26, name.length, true);
    local.set(name, 30); local.set(data, 30 + name.length);
    const central = new Uint8Array(46 + name.length);
    const cv = new DataView(central.buffer);
    cv.setUint32(0, 0x02014b50, true); cv.setUint16(4, 20, true); cv.setUint16(6, 20, true);
    cv.setUint16(8, 0x0800, true); cv.setUint16(10, 0, true); cv.setUint32(16, crc, true);
    cv.setUint32(20, data.length, true); cv.setUint32(24, data.length, true);
    cv.setUint16(28, name.length, true); cv.setUint32(42, offset, true);
    central.set(name, 46);
    locals.push(local); centrals.push(central);
    offset += local.length;
  }
  const centralSize = centrals.reduce((s, c) => s + c.length, 0);
  const end = new Uint8Array(22);
  const ev = new DataView(end.buffer);
  ev.setUint32(0, 0x06054b50, true);
  ev.setUint16(8, files.length, true); ev.setUint16(10, files.length, true);
  ev.setUint32(12, centralSize, true); ev.setUint32(16, offset, true);
  const out = new Uint8Array(offset + centralSize + 22);
  let p = 0;
  for (const l of locals) { out.set(l, p); p += l.length; }
  for (const c of centrals) { out.set(c, p); p += c.length; }
  out.set(end, p);
  return out;
}

function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function colName(n: number): string {
  let s = "";
  n++;
  while (n > 0) { const m = (n - 1) % 26; s = String.fromCharCode(65 + m) + s; n = Math.floor((n - 1) / 26); }
  return s;
}

// Answer scores and the text the portal shows for each, as the working
// ScalePad Sync upload writes them (2 compliant ... -2 not compliant).
const SCORE_TEXT: Record<string, string> = {
  "2": "Compliant", "1": "Partially Compliant", "0": "N/A", "-1": "Missing answer", "-2": "Not compliant",
};
// List responses: the suffix marks each one's score (+ partial, = N/A, * unanswered, - no).
const DEFAULT_RESPONSES = "Yes,Partially+,Not Applicable=,Unanswered*,No-";

const GUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Update Key must be a GUID: with any other text the upload fails ("Failed to upload
 * assessment.", live 2026-10-07) after creating the assessment row. A non-GUID key is
 * turned into a stable GUID from its text, the way the ScalePad Sync derives its keys
 * (MD5, version 3), so the same key always refreshes the same question.
 */
export function toUpdateKey(key: string): string {
  const k = key.trim();
  if (GUID.test(k)) return k.toLowerCase();
  const b = createHash("md5").update(`cloudradial-ucp/assessment-import/${k.toLowerCase()}`, "utf8").digest();
  b[6] = (b[6] & 0x0f) | 0x30;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = b.toString("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
}

/**
 * Builds the assessment workbook. Each question is keyed by template column name
 * (e.g. "Category", "Question", "Explanation", "Answer", "Remediation", "Update Key").
 * Unknown keys are rejected. Columns the import needs are filled when left out:
 * Order (10, 20, ...), Type "List", Responses, Answer -1 (unanswered), the Text Answer
 * that matches a numeric Answer, and Is Flagged ("Yes" for a -2 answer).
 */
export function buildAssessmentXlsx(questions: Record<string, unknown>[]): Uint8Array {
  const cols = ASSESSMENT_COLUMNS as readonly string[];
  const at = (c: string) => cols.indexOf(c);
  const lookup = new Map(cols.map((c) => [c.toLowerCase().replace(/\s+/g, ""), c]));
  const rows: string[][] = [cols.slice()];
  questions.forEach((q, i) => {
    const row: string[] = new Array(cols.length).fill("");
    for (const [k, v] of Object.entries(q)) {
      const col = lookup.get(k.toLowerCase().replace(/\s+/g, ""));
      if (!col) throw new Error(`Question ${i + 1}: unknown column "${k}". Valid columns: ${cols.join(", ")}`);
      row[at(col)] = v === undefined || v === null ? "" : String(v);
    }
    if (!row[at("Category")] || !row[at("Question")]) {
      throw new Error(`Question ${i + 1}: "Category" and "Question" are required.`);
    }
    if (!row[at("Order")]) row[at("Order")] = String((i + 1) * 10);
    if (!row[at("Type")]) row[at("Type")] = "List";
    if (!row[at("Responses")] && row[at("Type")] === "List") row[at("Responses")] = DEFAULT_RESPONSES;
    if (!row[at("Answer")]) row[at("Answer")] = "-1";
    if (!row[at("Text Answer")] && SCORE_TEXT[row[at("Answer")]]) row[at("Text Answer")] = SCORE_TEXT[row[at("Answer")]];
    if (!row[at("Is Flagged")]) row[at("Is Flagged")] = row[at("Answer")] === "-2" ? "Yes" : "No";
    if (row[at("Update Key")]) row[at("Update Key")] = toUpdateKey(row[at("Update Key")]);
    rows.push(row);
  });

  // Shared strings and a styles part, as in the workbook the upload accepts live.
  const strings: string[] = [];
  const index = new Map<string, number>();
  const sid = (s: string) => {
    let n = index.get(s);
    if (n === undefined) { n = strings.length; strings.push(s); index.set(s, n); }
    return n;
  };
  let sheet = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>';
  rows.forEach((r, ri) => {
    sheet += `<row r="${ri + 1}">`;
    r.forEach((v, ci) => {
      if (v === "") return;
      const ref = colName(ci) + (ri + 1);
      sheet += /^-?\d+(\.\d+)?$/.test(v) && ri > 0
        ? `<c r="${ref}"><v>${v}</v></c>`
        : `<c r="${ref}" t="s"><v>${sid(v)}</v></c>`;
    });
    sheet += "</row>";
  });
  sheet += "</sheetData></worksheet>";
  const sst =
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="${strings.length}" uniqueCount="${strings.length}">` +
    strings.map((s) => `<si><t xml:space="preserve">${esc(s)}</t></si>`).join("") +
    "</sst>";
  return zipStored([
    { name: "[Content_Types].xml", data: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>' },
    { name: "_rels/.rels", data: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>' },
    { name: "xl/workbook.xml", data: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Assessment" sheetId="1" r:id="rId1"/></sheets></workbook>' },
    { name: "xl/_rels/workbook.xml.rels", data: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>' },
    { name: "xl/worksheets/sheet1.xml", data: sheet },
    { name: "xl/sharedStrings.xml", data: sst },
    { name: "xl/styles.xml", data: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs></styleSheet>' },
  ]);
}
