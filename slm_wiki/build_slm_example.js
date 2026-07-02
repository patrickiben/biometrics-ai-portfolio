// Worked example: "A morning of on-device triage" on CP-101. A scheduled SAS/R QC run + a
// small LOCAL model doing only the language layer, fully offline. Mockup screens -> picture
// guide PDF + narrated video. SAS/R owns every number; the model is human-gated.
const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";
pres.title = "On-device SLM × SAS/R — a morning of triage (CP-101)";
const DARK = "0E2330", INK = "11233A", MUTED = "566A77", ICE = "C7E0E4", PANEL = "EEF5F6", LINE = "D7E2E6", SUBTLE = "F6FAFA";
const TEAL = "0E7C86", TEALINK = "0C5560", TEALBG = "E2F1F2", TERM = "0E2330", SLATE = "334E5A";
const GREEN = "1F9D55", GREENBG = "E6F6EC", AMBER = "C2891C", AMBERBG = "FBF1D8", RED = "C0392B", REDBG = "FBECEA", IND = "3B5BA5";
const HF = "Georgia", BF = "Calibri", MONO = "Consolas", W = 13.3, H = 7.5;
const R = pres.shapes.RECTANGLE, RR = pres.shapes.ROUNDED_RECTANGLE, OV = pres.shapes.OVAL;
const shadow = () => ({ type: "outer", color: "11233A", blur: 8, offset: 2, angle: 90, opacity: 0.10 });
const S = [];
function header(s, step, title, accent) {
  s.addShape(RR, { x: 0.5, y: 0.32, w: 0.16, h: 0.34, fill: { color: accent }, rectRadius: 0.04 });
  s.addText(step, { x: 0.78, y: 0.28, w: 11.5, h: 0.3, margin: 0, fontFace: BF, fontSize: 11, bold: true, charSpacing: 2, color: MUTED });
  s.addText(title, { x: 0.78, y: 0.55, w: 12.2, h: 0.5, margin: 0, fontFace: HF, fontSize: 21, bold: true, color: INK });
}
function win(s, x, y, w, h, app, barC) {
  s.addShape(R, { x, y, w, h, fill: { color: "FFFFFF" }, line: { color: LINE, width: 1 }, shadow: shadow() });
  s.addShape(R, { x, y, w, h: 0.4, fill: { color: barC } });
  for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) s.addShape(OV, { x: x + 0.16 + c * 0.07, y: y + 0.12 + r * 0.07, w: 0.035, h: 0.035, fill: { color: "FFFFFF" } });
  s.addText(app, { x: x + 0.5, y, w: w - 1, h: 0.4, margin: 0, fontFace: BF, fontSize: 11, bold: true, color: "FFFFFF", valign: "middle" });
}
function callout(s, n, text, accent) {
  s.addShape(R, { x: 0.5, y: 6.82, w: 12.3, h: 0.5, fill: { color: TEALBG } });
  s.addShape(OV, { x: 0.66, y: 6.9, w: 0.34, h: 0.34, fill: { color: accent } });
  s.addText(String(n), { x: 0.66, y: 6.9, w: 0.34, h: 0.34, margin: 0, fontFace: HF, fontSize: 15, bold: true, color: "FFFFFF", align: "center", valign: "middle" });
  s.addText(text, { x: 1.16, y: 6.82, w: 11.5, h: 0.5, margin: 0, fontFace: BF, fontSize: 12.5, bold: true, color: TEALINK, valign: "middle" });
}
const pill = (s, x, y, t, fg, bg, w) => { const ww = w || (0.2 + t.length * 0.072); s.addShape(RR, { x, y, w: ww, h: 0.28, fill: { color: bg }, rectRadius: 0.05 }); s.addText(t, { x, y, w: ww, h: 0.28, margin: 0, fontFace: BF, fontSize: 9.5, bold: true, color: fg, align: "center", valign: "middle" }); return ww; };
const sev = (v) => v === "CRITICAL" ? [RED, REDBG] : v === "MAJOR" ? [AMBER, AMBERBG] : v === "MINOR" ? [GREEN, GREENBG] : [MUTED, "EEE"];
// generic table: cols=[name,width]; rows of cell arrays. {sev:"MAJOR"} cell -> severity pill; {p:[fg,bg,text]} -> pill.
function grid(s, x, y, cols, rows, accent, hl) {
  const w = cols.reduce((a, c) => a + c[1], 0); let cx = x;
  s.addShape(R, { x, y, w, h: 0.4, fill: { color: accent } });
  cols.forEach(c => { s.addText(c[0], { x: cx + 0.1, y, w: c[1] - 0.1, h: 0.4, margin: 0, fontFace: BF, fontSize: 9.5, bold: true, color: "FFFFFF", valign: "middle" }); cx += c[1]; });
  let ry = y + 0.4;
  rows.forEach((r, ri) => {
    if (hl && hl.includes(ri)) s.addShape(R, { x, y: ry, w, h: 0.5, fill: { color: "FFF7E0" }, line: { color: AMBER, width: 1 } });
    else if (ri % 2) s.addShape(R, { x, y: ry, w, h: 0.5, fill: { color: SUBTLE } });
    cx = x;
    r.forEach((v, ci) => {
      if (v && v.sev) { const [fg, bg] = sev(v.sev); pill(s, cx + 0.08, ry + 0.11, v.sev, fg, bg, cols[ci][1] - 0.2); }
      else if (v && v.p) { pill(s, cx + 0.08, ry + 0.11, v.p[2], v.p[0], v.p[1], cols[ci][1] - 0.2); }
      else s.addText(String(v == null ? "" : v), { x: cx + 0.1, y: ry, w: cols[ci][1] - 0.15, h: 0.5, margin: 0, fontFace: BF, fontSize: 9.5, color: "26323a", valign: "middle", lineSpacingMultiple: 0.92 });
      cx += cols[ci][1];
    });
    ry += 0.5;
  });
  return ry;
}
function codepanel(s, x, y, w, h, title, runs) {
  win(s, x, y, w, h, title, TERM);
  s.addText(runs, { x: x + 0.25, y: y + 0.55, w: w - 0.5, h: h - 0.75, margin: 0, fontFace: MONO, fontSize: 11.5, valign: "top", lineSpacingMultiple: 1.12 });
}

// ===== 1 TITLE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: DARK };
  s.addShape(R, { x: 9.4, y: 0, w: 3.9, h: H, fill: { color: "11283440".slice(0, 6) } });
  s.addShape(R, { x: 9.4, y: 0, w: 3.9, h: H, fill: { color: "12303B" } });
  s.addShape(R, { x: 9.4, y: 0, w: 0.08, h: H, fill: { color: TEAL } });
  const loop = [["Scheduler", "nightly batch"], ["SAS / R + Pinnacle 21", "every check & count"], ["Local SLM (offline)", "label · route · draft — words only"], ["Validator + human", "allowlist · approve"], ["Write + Part 11 audit", "model digest pinned"]];
  let ly = 1.05;
  loop.forEach((l, i) => { s.addShape(RR, { x: 9.85, y: ly, w: 3.05, h: 0.7, fill: { color: "163A47" }, line: { color: "2c5562", width: 1 }, rectRadius: 0.06 }); s.addText([{ text: l[0] + "\n", options: { fontSize: 12, bold: true, color: "FFFFFF" } }, { text: l[1], options: { fontSize: 8.5, color: "9FC3C8" } }], { x: 10.0, y: ly + 0.06, w: 2.8, h: 0.58, margin: 0, fontFace: BF, lineSpacingMultiple: 0.92 }); if (i < 4) s.addText("↓", { x: 11.1, y: ly + 0.69, w: 0.4, h: 0.18, margin: 0, fontFace: BF, fontSize: 11, bold: true, color: TEAL, align: "center" }); ly += 0.86; });
  s.addText("ON-DEVICE SLM × SAS/R · STUDY CP-101", { x: 0.7, y: 1.5, w: 8.4, h: 0.3, margin: 0, fontFace: BF, fontSize: 12, bold: true, charSpacing: 2, color: ICE });
  s.addText("A morning of on-device triage", { x: 0.7, y: 1.95, w: 8.5, h: 1.0, margin: 0, fontFace: HF, fontSize: 35, bold: true, color: "FFFFFF" });
  s.addText("Numbers from SAS/R, words from a small local model.", { x: 0.7, y: 3.0, w: 8.5, h: 0.5, margin: 0, fontFace: HF, fontSize: 17, italic: true, color: TEAL });
  s.addText("A scheduled SAS/R job runs the deterministic checks and Pinnacle 21 produces the conformance findings — exactly as today. A small open-weight model, running offline on the workstation, only labels each finding, sorts it into a queue, and drafts a candidate query. SAS/R owns every number; the model just helps with words; a human approves before anything is written.", { x: 0.7, y: 3.7, w: 8.4, h: 1.6, margin: 0, fontFace: BF, fontSize: 13.5, color: ICE, lineSpacingMultiple: 1.06 });
  s.addText("Illustrative mockups. The model never computes or changes a number; validated tools and SAS/R own every value.", { x: 0.7, y: 5.7, w: 8.4, h: 0.5, margin: 0, fontFace: BF, fontSize: 11, italic: true, color: "7FA6AD" });
}
// ===== 2 OFFLINE SETUP =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  header(s, "BEAT 2 · THE SETUP", "An ordinary workstation, Ollama, one pinned model — offline", TEAL);
  codepanel(s, 0.5, 1.35, 7.3, 5.0, "workstation · terminal (offline)", [
    { text: "$ ollama serve            ", options: { color: "8FE3B0" } }, { text: "# bound to 127.0.0.1:11434\n", options: { color: "7FA6AD" } },
    { text: "$ ollama pull qwen2.5:7b-instruct-q8_0\n", options: { color: "E6F2F4" } },
    { text: "  pulled · sha256 a1f3…9c  (Apache-2.0)\n\n", options: { color: "7FA6AD" } },
    { text: "PINNED:\n", options: { color: "8FE3B0" } },
    { text: "  model   qwen2.5:7b-instruct-q8_0\n", options: { color: "E6F2F4" } },
    { text: "  digest  sha256:a1f3…9c\n", options: { color: "E6F2F4" } },
    { text: "  decode  temperature 0 · seed 42\n", options: { color: "E6F2F4" } },
    { text: "  ctx     8192 · batch 1\n\n", options: { color: "E6F2F4" } },
    { text: "$ curl 127.0.0.1:11434/api/version  ", options: { color: "FFD27A" } }, { text: "→ 200 OK", options: { color: "8FE3B0" } },
  ]);
  s.addShape(RR, { x: 8.1, y: 1.35, w: 4.7, h: 2.4, fill: { color: TEALBG }, line: { color: TEAL, width: 1 }, rectRadius: 0.06 });
  s.addText("◇  No GPU farm. No cloud account. No telemetry.", { x: 8.35, y: 1.6, w: 4.2, h: 0.4, margin: 0, fontFace: HF, fontSize: 14, bold: true, color: TEALINK });
  s.addText("A 7B model at Q8 runs on the workstation you already own. The same input gives the same output every run — the model, quantization, digest, and decoding are pinned.", { x: 8.35, y: 2.1, w: 4.2, h: 1.5, margin: 0, fontFace: BF, fontSize: 12, color: "2b4047", valign: "top", lineSpacingMultiple: 1.08 });
  s.addShape(RR, { x: 8.1, y: 4.0, w: 4.7, h: 2.35, fill: { color: DARK }, rectRadius: 0.06 });
  s.addText("⏚  OFFLINE", { x: 8.35, y: 4.25, w: 4.2, h: 0.4, margin: 0, fontFace: HF, fontSize: 16, bold: true, color: "8FE3B0" });
  s.addText("The network cable is unplugged. SAS/R only ever calls 127.0.0.1 — and asserts the loopback before every run. The data-egress story is simply: nothing can leave.", { x: 8.35, y: 4.75, w: 4.2, h: 1.5, margin: 0, fontFace: BF, fontSize: 12, color: ICE, valign: "top", lineSpacingMultiple: 1.08 });
  callout(s, 2, "Deliberately boring: one offline box, one pinned quantized model on the loopback address. The hardest part of an on-device AI deployment is choosing scope — not securing it.", TEAL);
}
// ===== 3 SAS/R CHECKS =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  header(s, "BEAT 3 · THE NUMBERS ARE SAS/R'S", "Overnight, SAS/R + Pinnacle 21 run every deterministic check", IND);
  codepanel(s, 0.5, 1.35, 5.7, 5.0, "batch log · validated work", [
    { text: "[02:00] Pinnacle 21 CDISC conformance …\n", options: { color: "E6F2F4" } },
    { text: "[02:14] SDTM edit-checks (cross-form) …\n", options: { color: "E6F2F4" } },
    { text: "[02:21] PK timing / BLQ rules …\n", options: { color: "E6F2F4" } },
    { text: "[02:28] lab / IXRS reconciliation …\n\n", options: { color: "E6F2F4" } },
    { text: "FINDINGS:  214\n", options: { color: "FFD27A" } },
    { text: "  Error 38 · Warning 121 · Notice 55\n\n", options: { color: "E6F2F4" } },
    { text: "# the small model has NOT been called.\n", options: { color: "8FE3B0" } },
    { text: "# every count came from validated code.", options: { color: "8FE3B0" } },
  ]);
  win(s, 6.4, 1.35, 6.4, 5.0, "findings (a sample) — owned by SAS/R", IND);
  grid(s, 6.6, 1.95, [["ID", 1.1], ["Rule", 2.0], ["Finding (short)", 3.0]], [
    ["SD0064", "AE date order", "AESTDTC after AEENDTC ×3 (AE)"],
    ["SD0011", "Required var", "LBSTRESN missing ×12 (num)"],
    ["PK0003", "Timing dev", "ADPC 4h actual >10% off nominal ×2"],
    ["SD0204", "CT term", "Non-CT value in AEACN ×1"],
    ["RC0007", "Lab recon", "3 LB records unmatched to transfer"],
  ], IND);
  s.addText("Counts, rules, comparisons, reconciliation — all from validated, double-programmed code.", { x: 6.6, y: 5.45, w: 6.0, h: 0.6, margin: 0, fontFace: BF, fontSize: 11.5, italic: true, color: MUTED, valign: "top" });
  callout(s, 3, "The model never produces a number. Every count and rule evaluation is SAS/R's and Pinnacle 21's — the language layer hasn't even started yet.", IND);
}
// ===== 4 CALL THE MODEL =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  header(s, "BEAT 4 · ASK THE LOCAL MODEL", "SAS/R sends each short finding for three narrow calls — JSON only", TEAL);
  codepanel(s, 0.5, 1.35, 6.3, 5.0, "SAS · PROC HTTP → 127.0.0.1/api/chat", [
    { text: "%slm_init(model=&CFG_MODEL,\n", options: { color: "FFD27A" } },
    { text: "          base=http://127.0.0.1:11434);\n", options: { color: "FFD27A" } },
    { text: "  ↳ loopback asserted · model pinned\n\n", options: { color: "7FA6AD" } },
    { text: "%slm_classify(\n", options: { color: "8FE3B0" } },
    { text: "   usr=%nrstr(AESTDTC is after AEENDTC\n", options: { color: "E6F2F4" } },
    { text: "             for 3 records in AE),\n", options: { color: "E6F2F4" } },
    { text: "   field=owner, allow=&CFG_OWNERS);\n\n", options: { color: "E6F2F4" } },
    { text: "format = JSON SCHEMA (enum-constrained)\n", options: { color: "8FE3B0" } },
    { text: "options: temperature 0 · seed 42 · stream off", options: { color: "7FA6AD" } },
  ]);
  win(s, 7.0, 1.35, 5.8, 5.0, "the model's reply — schema-constrained JSON", TEAL);
  s.addText([
    { text: "{\n", options: { color: SLATE } },
    { text: '  "novelty":  ', options: { color: "26323a" } }, { text: '"NEW",\n', options: { color: TEALINK, bold: true } },
    { text: '  "owner":    ', options: { color: "26323a" } }, { text: '"PROGRAMMING",\n', options: { color: TEALINK, bold: true } },
    { text: '  "severity": ', options: { color: "26323a" } }, { text: '"MAJOR",\n', options: { color: TEALINK, bold: true } },
    { text: '  "confidence": ', options: { color: "26323a" } }, { text: "0.86,\n", options: { color: IND, bold: true } },
    { text: '  "rationale": "start after end\n              date — likely keying"\n', options: { color: "56707a" } },
    { text: "}", options: { color: SLATE } },
  ], { x: 7.3, y: 1.95, w: 5.2, h: 3.0, margin: 0, fontFace: MONO, fontSize: 13, valign: "top", lineSpacingMultiple: 1.15 });
  s.addShape(R, { x: 7.3, y: 5.0, w: 5.2, h: 1.1, fill: { color: TEALBG } });
  s.addText("Short-text classification + routing into a fixed vocabulary — squarely what a small quantized model does reliably. No prose, no numbers.", { x: 7.45, y: 5.05, w: 4.9, h: 1.0, margin: 0, fontFace: BF, fontSize: 11.5, color: TEALINK, valign: "middle", lineSpacingMultiple: 1.05 });
  callout(s, 4, "Three narrow, in-envelope questions per finding — new-vs-known, owner, severity — returned as JSON constrained to allowed values only. The grammar makes an off-list answer impossible to even sample.", TEAL);
}
// ===== 5 VALIDATOR + DRAFT =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  header(s, "BEAT 5 · THE SAFETY NET", "SAS/R validates every field, then drafts a grounded query", AMBER);
  codepanel(s, 0.5, 1.35, 5.9, 5.0, "SAS · %slm_validate (the trust boundary)", [
    { text: "parse JSON  ……………  ok\n", options: { color: "8FE3B0" } },
    { text: 'owner  in CFG_OWNERS  ……  ok\n', options: { color: "8FE3B0" } },
    { text: 'severity in CFG_SEVERITY  …  ok\n', options: { color: "8FE3B0" } },
    { text: "confidence 0–1  …………  ok\n\n", options: { color: "8FE3B0" } },
    { text: "# any off-allowlist value →\n", options: { color: "7FA6AD" } },
    { text: "REJECT + log, never coerce.\n", options: { color: "FFB4A6" } },
    { text: "# 211 valid · 3 rejected (re-queued)\n\n", options: { color: "E6F2F4" } },
    { text: "draft query: grounded by RAG over\n", options: { color: "FFD27A" } },
    { text: "the study's own spec + edit-check defs", options: { color: "FFD27A" } },
  ]);
  win(s, 6.6, 1.35, 6.2, 5.0, "draft query — grounded, marked DRAFT, unsent", AMBER);
  s.addShape(R, { x: 6.85, y: 1.95, w: 5.7, h: 0.45, fill: { color: AMBERBG }, line: { color: AMBER, width: 1 } });
  s.addText("DRAFT · not sent — SD0064 · AE", { x: 7.0, y: 1.95, w: 5.4, h: 0.45, margin: 0, fontFace: BF, fontSize: 11, bold: true, color: "7a5512", valign: "middle" });
  s.addText([
    { text: "Please verify the AE onset/resolution dates:\nAESTDTC (start) is recorded after AEENDTC\n(end) for 3 records. Per the edit-check spec\n(EC-AE-07), confirm and correct the dates or\nconfirm the event sequence.", options: { color: "2b3a40" } },
  ], { x: 7.0, y: 2.6, w: 5.4, h: 2.0, margin: 0, fontFace: BF, fontSize: 12, valign: "top", lineSpacingMultiple: 1.1 });
  s.addText("Wording stays anchored to the study's real spec text — not the model's priors.", { x: 7.0, y: 5.3, w: 5.4, h: 0.7, margin: 0, fontFace: BF, fontSize: 11, italic: true, color: MUTED, valign: "top", lineSpacingMultiple: 1.05 });
  callout(s, 5, "Schema-constrain at the server AND allowlist-validate at the client: belt and suspenders. SAS/R drops anything malformed, then assembles the survivors into one ranked worklist.", AMBER);
}
// ===== 6 HUMAN GATE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  header(s, "BEAT 6 · THE HUMAN GATE", "The biostatistician works a ranked worklist — facts beside suggestions", GREEN);
  win(s, 0.5, 1.3, 12.3, 5.4, "Triage worklist — SAS/R facts · model suggestion · your decision", GREEN);
  grid(s, 0.7, 1.95, [["ID", 0.95], ["SAS/R facts", 3.1], ["Novelty", 1.0], ["Owner", 1.55], ["Sev", 1.05], ["Draft query", 2.3], ["Decision", 1.45]], [
    ["SD0064", "AESTDTC>AEENDTC ×3 (AE)", { p: [IND, "E7ECF7", "NEW"] }, "PROGRAMMING", { sev: "MAJOR" }, "verify AE dates…", { p: [GREEN, GREENBG, "✓ Approve"] }],
    ["RC0007", "3 LB unmatched to transfer", { p: [IND, "E7ECF7", "NEW"] }, "DM", { sev: "MAJOR" }, "reconcile LB…", { p: [GREEN, GREENBG, "✓ Approve"] }],
    ["PK0003", "ADPC 4h >10% off ×2", { p: [MUTED, "ECEFF1", "KNOWN"] }, "PK", { sev: "MINOR" }, "confirm timing dev…", { p: [AMBER, AMBERBG, "✎ Edit"] }],
    ["SD0011", "LBSTRESN missing ×12", { p: [IND, "E7ECF7", "NEW"] }, "DM", { sev: "MAJOR" }, "query missing num…", { p: [GREEN, GREENBG, "✓ Approve"] }],
    ["SD0204", "Non-CT value AEACN ×1", { p: [MUTED, "ECEFF1", "KNOWN"] }, "MEDICAL CODING", { sev: "MINOR" }, "(expected — explained)", { p: [RED, REDBG, "✕ Reject"] }],
  ], GREEN);
  s.addText("Each row shows the deterministic facts from SAS/R next to the model's label and draft. A wrong label is a two-second fix — nothing becomes real until a qualified human signs off.", { x: 0.7, y: 5.55, w: 11.9, h: 0.7, margin: 0, fontFace: BF, fontSize: 12, italic: true, color: MUTED, valign: "top", lineSpacingMultiple: 1.05 });
  callout(s, 6, "The model triaged; the biostatistician decides. Approve, edit, or reject each one — the human gate is the point at which a suggestion can become an action.", GREEN);
}
// ===== 7 WRITE + AUDIT =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  header(s, "BEAT 7 · WRITE + PART 11 AUDIT", "Approved items are written — with the model digest pinned", IND);
  codepanel(s, 0.5, 1.35, 7.6, 5.0, "audit/triage_audit.txt — one line per approved item", [
    { text: "2026-06-16T07:42  SD0064\n", options: { color: "E6F2F4" } },
    { text: "  owner=PROGRAMMING novelty=NEW sev=MAJOR\n", options: { color: "E6F2F4" } },
    { text: "  model=qwen2.5:7b-instruct-q8_0\n", options: { color: "8FE3B0" } },
    { text: "  digest=sha256:a1f3…9c seed=42 temp=0\n", options: { color: "8FE3B0" } },
    { text: '  draft="verify AE dates…"\n', options: { color: "FFD27A" } },
    { text: "  reviewer=pkiben  decision=APPROVED\n", options: { color: "E6F2F4" } },
    { text: "  query_id=Q-10421  (issued to EDC)\n\n", options: { color: "7FA6AD" } },
    { text: "2026-06-16T07:43  RC0007  …APPROVED\n", options: { color: "E6F2F4" } },
    { text: "2026-06-16T07:44  SD0204  …REJECTED (no write)", options: { color: "7FA6AD" } },
  ]);
  s.addShape(RR, { x: 8.4, y: 1.35, w: 4.4, h: 2.45, fill: { color: GREENBG }, line: { color: GREEN, width: 1 }, rectRadius: 0.06 });
  s.addText("Re-runnable for an inspector", { x: 8.62, y: 1.58, w: 4.0, h: 0.4, margin: 0, fontFace: HF, fontSize: 14, bold: true, color: "0B5C42" });
  s.addText("Because the model is frozen and decoding is fixed, the audit line is a reproducible artifact: same input, same model digest, same output.", { x: 8.62, y: 2.05, w: 4.0, h: 1.6, margin: 0, fontFace: BF, fontSize: 12, color: "234a3c", valign: "top", lineSpacingMultiple: 1.08 });
  s.addShape(RR, { x: 8.4, y: 4.05, w: 4.4, h: 2.3, fill: { color: DARK }, rectRadius: 0.06 });
  s.addText("⏚  Offline — proven", { x: 8.62, y: 4.28, w: 4.0, h: 0.4, margin: 0, fontFace: HF, fontSize: 14, bold: true, color: "8FE3B0" });
  s.addText("The cable is unplugged. The only thing that ever left the box was a query you approved — into your own EDC.", { x: 8.62, y: 4.75, w: 4.0, h: 1.5, margin: 0, fontFace: BF, fontSize: 12, color: ICE, valign: "top", lineSpacingMultiple: 1.08 });
  callout(s, 7, "Only approved items are written, each with a 21 CFR Part 11 audit line: prompt, pinned model + digest, draft, and who approved it. The SLM is never the record — SAS/R is.", IND);
}
// ===== 8 WHO DID WHAT =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: DARK };
  s.addShape(RR, { x: 0.7, y: 0.55, w: 0.16, h: 0.34, fill: { color: TEAL }, rectRadius: 0.04 });
  s.addText("WHO DID WHAT", { x: 1.0, y: 0.5, w: 10, h: 0.3, margin: 0, fontFace: BF, fontSize: 11, bold: true, charSpacing: 2, color: ICE });
  s.addText("The honest shape of an on-device win", { x: 0.7, y: 1.0, w: 12, h: 0.7, margin: 0, fontFace: HF, fontSize: 26, bold: true, color: "FFFFFF" });
  const cols = [
    ["SAS / R + Pinnacle 21", ["All data access & computation", "Every check, count & reconciliation", "The output validator (allowlist)", "Every write + the Part 11 audit"], IND],
    ["The local small model", ["Labelled new-vs-known", "Classified owner & severity", "Drafted a grounded candidate query", "— and nothing else; no numbers"], TEAL],
    ["The biostatistician", ["Read the ranked worklist", "Approved, edited, or rejected", "Owned every decision that mattered", "Signed off before any write"], GREEN],
  ];
  const cw = (12.3 - 1.0) / 3, cy = 2.0, ch = 3.6;
  cols.forEach((c, i) => {
    const x = 0.7 + i * (cw + 0.5);
    s.addShape(R, { x, y: cy, w: cw, h: ch, fill: { color: "12303B" }, line: { color: "2c5562", width: 1 } });
    s.addShape(R, { x, y: cy, w: cw, h: 0.6, fill: { color: c[2] } });
    s.addText(c[0], { x: x + 0.2, y: cy, w: cw - 0.4, h: 0.6, margin: 0, fontFace: HF, fontSize: 14.5, bold: true, color: "FFFFFF", valign: "middle" });
    s.addText(c[1].map(t => ({ text: t, options: { bullet: { code: "2022" }, color: ICE } })), { x: x + 0.28, y: cy + 0.8, w: cw - 0.5, h: ch - 1.0, margin: 0, fontFace: BF, fontSize: 12, valign: "top", lineSpacingMultiple: 1.18, paraSpaceAfter: 6 });
  });
  s.addText("The model saved triage time on a narrow, validated task — and the truth stayed exactly where it always was: with SAS/R, the validated engines, and a qualified human.", { x: 0.7, y: 5.85, w: 12.0, h: 0.7, margin: 0, fontFace: BF, fontSize: 13, italic: true, color: TEAL, align: "center", valign: "top", lineSpacingMultiple: 1.05 });
  s.addText("Illustrative. On-device, offline, no number ever produced by the model.", { x: 0.7, y: H - 0.5, w: 12, h: 0.3, margin: 0, fontFace: BF, fontSize: 11, italic: true, color: "7FA6AD", align: "center" });
}
pres.writeFile({ fileName: __dirname + "/SLM_OnDevice_Example_StepGuide.pptx" }).then(f => console.log("WROTE", f, "(" + S.length + " slides)"));
