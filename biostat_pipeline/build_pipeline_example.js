// Worked example: ONE deliverable end-to-end through the Protocol->CSR pipeline on the hybrid.
// The Phase-1 PK package (Study CP-101) — what each stage routes to AI vs validated tool vs human.
const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";
pres.title = "Pipeline worked example — the Phase-1 PK package";
const DARK = "15183A", INK = "1A1E33", MUTED = "5A607E", ICE = "D5DAF5", PANEL = "F4F5FB", LINE = "DDE1EE", SUBTLE = "F7F8FC";
const INDIGO = "4338CA", INDIGOINK = "312C8A", INDBG = "ECECFB";
const TEAL = "0E7C86", TEALBG = "E2F1F2", TEALINK = "0A4F57", CLOUDB = "2F6DB5", CLOUDBG = "E5EEF8", CLOUDINK = "1E4C82";
const SLATE = "64748B", GREEN = "0F9D6E", AMBER = "C2891C";
const HF = "Georgia", BF = "Calibri", W = 13.3, H = 7.5;
const R = pres.shapes.RECTANGLE, RR = pres.shapes.ROUNDED_RECTANGLE, OV = pres.shapes.OVAL;
const shadow = () => ({ type: "outer", color: "1A1E33", blur: 8, offset: 2, angle: 90, opacity: 0.10 });
const S = [];
function header(s, step, title, accent) {
  s.addShape(RR, { x: 0.5, y: 0.32, w: 0.16, h: 0.34, fill: { color: accent }, rectRadius: 0.04 });
  s.addText(step, { x: 0.78, y: 0.28, w: 11.5, h: 0.3, margin: 0, fontFace: BF, fontSize: 11, bold: true, charSpacing: 2, color: MUTED });
  s.addText(title, { x: 0.78, y: 0.55, w: 12.0, h: 0.5, margin: 0, fontFace: HF, fontSize: 22, bold: true, color: INK });
}
const pill = (s, x, y, t, fg, bg, w) => { const ww = w || (0.2 + t.length * 0.078); s.addShape(RR, { x, y, w: ww, h: 0.3, fill: { color: bg }, rectRadius: 0.05 }); s.addText(t, { x, y, w: ww, h: 0.3, margin: 0, fontFace: BF, fontSize: 10, bold: true, color: fg, align: "center", valign: "middle" }); return ww; };
function callout(s, text, accent) {
  s.addShape(R, { x: 0.5, y: 6.82, w: 12.3, h: 0.5, fill: { color: INDBG } });
  s.addShape(R, { x: 0.5, y: 6.82, w: 0.1, h: 0.5, fill: { color: accent } });
  s.addText(text, { x: 0.75, y: 6.82, w: 11.9, h: 0.5, margin: 0, fontFace: BF, fontSize: 12.5, bold: true, color: INDIGOINK, valign: "middle" });
}
// a stage screen: three lanes — AI engine | validated tool | human
function stage(s, eyebrow, title, accent, lanes, note) {
  header(s, eyebrow, title, accent);
  const cards = [
    ["AI ENGINE", lanes[0][0], lanes[0][1], lanes[0][2] === "LOCAL" ? TEAL : CLOUDB, lanes[0][2] === "LOCAL" ? TEALBG : CLOUDBG, lanes[0][2] === "LOCAL" ? TEALINK : CLOUDINK],
    ["VALIDATED TOOL — OWNS THE NUMBER", lanes[1][0], lanes[1][1], SLATE, "EEF1F6", "3a4060"],
    ["HUMAN — SIGNS", lanes[2][0], lanes[2][1], GREEN, "E7F6F0", "0B5C42"],
  ];
  const cw = (12.3 - 0.6) / 3, cy = 1.55, ch = 4.0;
  cards.forEach((c, i) => {
    const x = 0.5 + i * (cw + 0.3);
    s.addShape(R, { x, y: cy, w: cw, h: ch, fill: { color: c[4] }, line: { color: LINE, width: 1 }, shadow: shadow() });
    s.addShape(R, { x, y: cy, w: cw, h: 0.56, fill: { color: c[3] } });
    s.addText(c[0], { x: x + 0.18, y: cy, w: cw - 0.36, h: 0.56, margin: 0, fontFace: BF, fontSize: 10, bold: true, color: "FFFFFF", valign: "middle" });
    if (i === 0) pill(s, x + cw - 1.0, cy + 0.13, lanes[0][2], "FFFFFF", lanes[0][2] === "LOCAL" ? "0A4F57" : "1E4C82", 0.85);
    s.addText(c[1], { x: x + 0.22, y: cy + 0.72, w: cw - 0.44, h: 0.7, margin: 0, fontFace: HF, fontSize: 14.5, bold: true, color: INK, valign: "top", lineSpacingMultiple: 0.95 });
    s.addText(c[2], { x: x + 0.22, y: cy + 1.5, w: cw - 0.44, h: ch - 1.7, margin: 0, fontFace: BF, fontSize: 12, color: c[5], valign: "top", lineSpacingMultiple: 1.06 });
  });
  callout(s, note, accent);
}

// ===== 1 TITLE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: DARK };
  s.addText("PIPELINE WORKED EXAMPLE · STUDY CP-101", { x: 0.7, y: 1.6, w: 11, h: 0.3, margin: 0, fontFace: BF, fontSize: 12, bold: true, charSpacing: 2, color: ICE });
  s.addText("One deliverable, end to end —\nthe Phase-1 PK package", { x: 0.7, y: 2.0, w: 11.5, h: 1.6, margin: 0, fontFace: HF, fontSize: 34, bold: true, color: "FFFFFF", lineSpacingMultiple: 1.0 });
  s.addText("Follow a single PK deliverable from Protocol to CSR — and see exactly what each stage routes to AI, to a validated tool, and to a human. The rule never changes: sensitivity decides the engine, validated tools own every reported number, and a statistician signs.", { x: 0.7, y: 3.9, w: 11.5, h: 1.2, margin: 0, fontFace: BF, fontSize: 14.5, color: ICE, lineSpacingMultiple: 1.08 });
  const tags = [["LOCAL", "sensitive / unmasked", TEAL], ["CLOUD (Claude, BAA)", "hard, de-identified reasoning", CLOUDB], ["VALIDATED + HUMAN", "the numbers & sign-off", GREEN]];
  let tx = 0.7; tags.forEach(t => { const w = pill(s, tx, 5.5, t[0], "FFFFFF", t[2], 0.3 + t[0].length * 0.085); s.addText(t[1], { x: tx, y: 5.85, w: w + 1, h: 0.3, margin: 0, fontFace: BF, fontSize: 10, italic: true, color: "8088B0" }); tx += w + 1.7; });
  s.addText("Illustrative. Reported NCA numbers come from Phoenix WinNonlin, never an LLM.", { x: 0.7, y: 6.7, w: 11, h: 0.3, margin: 0, fontFace: BF, fontSize: 11, italic: true, color: "8088B0" });
}
// ===== 2 ROUTING =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  header(s, "THE DELIVERABLE & THE RULE", "The PK package = ADPC dataset + PK TLFs + the CSR PK section", INDIGO);
  s.addShape(R, { x: 0.5, y: 1.4, w: 12.3, h: 0.95, fill: { color: PANEL }, line: { color: LINE, width: 1 } });
  s.addShape(R, { x: 0.5, y: 1.4, w: 0.1, h: 0.95, fill: { color: INDIGO } });
  s.addText([{ text: "Routing rule (every stage): ", options: { bold: true, color: INK } }, { text: "touches unmasked / participant-level data → ", options: { color: "33384f" } }, { text: "LOCAL", options: { bold: true, color: TEALINK } }, { text: ";  hard reasoning on de-identified text → ", options: { color: "33384f" } }, { text: "CLOUD Claude (BAA)", options: { bold: true, color: CLOUDINK } }, { text: ";  every reported number → ", options: { color: "33384f" } }, { text: "validated tool", options: { bold: true, color: "3a4060" } }, { text: ", QC'd and ", options: { color: "33384f" } }, { text: "signed by a human", options: { bold: true, color: "0B5C42" } }, { text: ".", options: { color: "33384f" } }], { x: 0.85, y: 1.4, w: 11.7, h: 0.95, margin: 0, fontFace: BF, fontSize: 13.5, valign: "middle", lineSpacingMultiple: 1.05 });
  const stages = [["1 · Protocol & SAP", "draft the PK statistical-methods prose", CLOUDB], ["2 · SDTM → ADaM", "build & validate the ADPC dataset", TEAL], ["3 · Analysis (NCA)", "compute Cmax/AUC/t½ + QC", SLATE], ["4 · TLF", "generate & reconcile the PK tables", AMBER], ["5 · CSR", "draft the PK methods/results", CLOUDB]];
  const cw = (12.3 - 4 * 0.25) / 5, cy = 2.7, ch = 3.4;
  stages.forEach((st, i) => {
    const x = 0.5 + i * (cw + 0.25);
    s.addShape(R, { x, y: cy, w: cw, h: ch, fill: { color: "FFFFFF" }, line: { color: LINE, width: 1 }, shadow: shadow() });
    s.addShape(R, { x, y: cy, w: cw, h: 0.08, fill: { color: st[2] } });
    s.addShape(OV, { x: x + cw / 2 - 0.26, y: cy + 0.45, w: 0.52, h: 0.52, fill: { color: st[2] } });
    s.addText(String(i + 1), { x: x + cw / 2 - 0.26, y: cy + 0.45, w: 0.52, h: 0.52, margin: 0, fontFace: HF, fontSize: 20, bold: true, color: "FFFFFF", align: "center", valign: "middle" });
    s.addText(st[0].split(" · ")[1], { x: x + 0.12, y: cy + 1.15, w: cw - 0.24, h: 0.7, margin: 0, fontFace: HF, fontSize: 13, bold: true, color: INK, align: "center", valign: "top", lineSpacingMultiple: 0.95 });
    s.addText(st[1], { x: x + 0.12, y: cy + 1.95, w: cw - 0.24, h: ch - 2.1, margin: 0, fontFace: BF, fontSize: 11, color: MUTED, align: "center", valign: "top", lineSpacingMultiple: 1.05 });
    if (i < 4) s.addText("→", { x: x + cw - 0.02, y: cy + 1.5, w: 0.3, h: 0.4, margin: 0, fontFace: BF, fontSize: 16, bold: true, color: SLATE, align: "center" });
  });
  callout(s, "Same deliverable, five stages — the engine changes with the data, but the numbers and the sign-off never leave validated tools and the statistician.", INDIGO);
}
// ===== 3-7 STAGES =====
{ const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  stage(s, "STAGE 1 · PROTOCOL & SAP", "Drafting the PK statistical-methods section", CLOUDB,
    [["Claude drafts the PK methods prose", "From the protocol + SAP shell (de-identified text): NCA parameters, BLQ rule, nominal-vs-actual time, populations — with [placeholders] for study values. Invents nothing.", "CLOUD"],
     ["—", "No reported number here yet; this stage is text. The analysis logic stays authoritative in the SAP, human-owned.", ""],
     ["Statistician reviews & edits", "Checks every derivation rule, fills placeholders, owns the estimand and endpoint decisions. The SAP is signed."]],
    "Hard, non-sensitive reasoning on de-identified text → cloud. The statistician owns the logic and the sign-off."); }
{ const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  stage(s, "STAGE 2 · SDTM → ADaM", "Building & validating the ADPC dataset (real PK data)", TEAL,
    [["Local model assists the ADPC build", "On the real, unmasked PC/PK data — zero egress: BLQ handling (pre-first-quantifiable→0, else LLOQ/2), nominal & actual time, deviation flags, mapping to ADPC. Drafts the spec & code.", "LOCAL"],
     ["Pinnacle 21 validates conformance", "CDISC/ADaMIG + Define-XML checks run in the validated tool — the conformance result is the tool's, not the model's.", ""],
     ["QC double-programming; statistician signs", "An independent program reconciles ADPC; discrepancies resolved; the dataset is signed and frozen."]],
    "Participant-level / unmasked → LOCAL, zero egress. Conformance comes from Pinnacle 21; a human signs the frozen ADPC."); }
{ const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  stage(s, "STAGE 3 · ANALYSIS (NCA)", "Computing the PK parameters — the numbers", SLATE,
    [["Local model assists QC & narrative", "Sanity-checks profiles, flags outliers/anomalies for review, drafts the analysis notes — on the unmasked data, zero egress. It never produces a reported value.", "LOCAL"],
     ["Phoenix WinNonlin computes the NCA", "Cmax, Tmax, AUC0-t, AUC0-inf, t½, CL/F, Vz/F — in the validated NCA tool. These ARE the reported numbers.", ""],
     ["Independent double-programming; sign-off", "A second analyst's run reconciles the parameters; the medical monitor reviews emerging PK; the statistician signs."]],
    "The reported NCA numbers come from Phoenix — never an LLM. The model assists QC; double-programming and a human own the result."); }
{ const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  stage(s, "STAGE 4 · TLF", "Generating & reconciling the PK tables, listings, figures", AMBER,
    [["Model drafts shells, titles, footnotes", "TLF shell prose, table titles & footnotes, and a consistency check of wording across outputs — text only.", "CLOUD"],
     ["SAS / validated macros produce the TLFs", "The actual tables/figures are produced by the validated programs from the frozen ADPC + NCA results.", ""],
     ["QC reconciles to source; statistician signs", "Independent QC ties every cell back to the validated outputs; the TLF package is signed."]],
    "The model drafts wording; the validated programs produce the numbers; QC reconciles to source and a human signs."); }
{ const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  stage(s, "STAGE 5 · CSR", "Drafting the PK methods & results section", CLOUDB,
    [["Claude drafts the PK CSR prose", "From the SAP + the (de-identified) summary outputs: a methods/results narrative consistent with the TLFs — cites the tables, paraphrases nothing numeric it shouldn't.", "CLOUD"],
     ["The TLFs/Define remain the source of truth", "Every number in the prose traces to a signed TLF; the model copies, never computes.", ""],
     ["Medical writer + statistician finalize & sign", "Human review for accuracy and interpretation; the CSR section is finalized into the regulated document."]],
    "De-identified summary reasoning → cloud draft. The signed TLFs own every number; humans finalize the regulated text."); }
// ===== 8 CLOSE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: DARK };
  s.addShape(RR, { x: 0.7, y: 0.6, w: 0.16, h: 0.34, fill: { color: INDIGO }, rectRadius: 0.04 });
  s.addText("WHAT THE EXAMPLE SHOWS", { x: 1.0, y: 0.55, w: 10, h: 0.3, margin: 0, fontFace: BF, fontSize: 11, bold: true, charSpacing: 2, color: ICE });
  s.addText("AI did the drafting and the QC. Validated tools and humans owned the numbers.", { x: 0.7, y: 1.1, w: 12, h: 0.9, margin: 0, fontFace: HF, fontSize: 24, bold: true, color: "FFFFFF" });
  const pts = [["Sensitivity routed the engine", "Unmasked PK data stayed on the LOCAL model (zero egress); de-identified reasoning went to CLOUD Claude.", TEAL], ["Validated tools owned every number", "Phoenix computed the NCA; Pinnacle 21 validated conformance; SAS produced the TLFs. The LLM never produced a reported value.", SLATE], ["A human signed every gate", "Frozen ADPC, double-programmed parameters, reconciled TLFs, finalized CSR — each signed.", GREEN], ["The payoff", "Faster drafting and tighter QC across Protocol→CSR — with the data staying put and the regulated outputs unchanged in provenance.", INDIGO]];
  const cw = (12.3 - 0.5) / 2, cy = 2.15, ch = 1.75;
  pts.forEach((p, i) => { const x = 0.7 + (i % 2) * (cw + 0.5), y = cy + Math.floor(i / 2) * (ch + 0.25); s.addShape(R, { x, y, w: cw, h: ch, fill: { color: "1E2350" }, line: { color: "343A6E", width: 1 } }); s.addShape(R, { x, y, w: 0.09, h: ch, fill: { color: p[2] } }); s.addText(p[0], { x: x + 0.3, y: y + 0.16, w: cw - 0.5, h: 0.5, margin: 0, fontFace: HF, fontSize: 15, bold: true, color: "FFFFFF" }); s.addText(p[1], { x: x + 0.3, y: y + 0.66, w: cw - 0.55, h: ch - 0.78, margin: 0, fontFace: BF, fontSize: 11.5, color: ICE, valign: "top", lineSpacingMultiple: 1.03 }); });
  s.addText("Illustrative. The full 136-deliverable map and register are in the pipeline package; reported numbers always come from validated tools.", { x: 0.7, y: H - 0.6, w: 12, h: 0.35, margin: 0, fontFace: BF, fontSize: 11, italic: true, color: "8088B0", align: "center" });
}
pres.writeFile({ fileName: __dirname + "/Pipeline_PK_WorkedExample.pptx" }).then(f => console.log("WROTE", f, "(" + S.length + " slides)"));
