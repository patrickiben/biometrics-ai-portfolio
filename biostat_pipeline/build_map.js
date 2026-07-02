// One-page visual pipeline map: Early-Phase Clin-Pharm Biostatistics, Protocol -> CSR. Single landscape page.
const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";
pres.title = "Early-Phase Clin-Pharm Biostatistics Pipeline — Protocol to CSR";
const INK = "1A1E33", MUTED = "5A607E", PANEL = "F4F5FB", LINEC = "E0E3F1", HF = "Georgia", BF = "Calibri";
const W = 13.3, M = 0.45;
const s = pres.addSlide(); s.background = { color: "FFFFFF" };

s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: M, y: 0.3, w: 0.16, h: 0.42, fill: { color: "4338CA" }, rectRadius: 0.04 });
s.addText("EARLY-PHASE CLINICAL PHARMACOLOGY · BIOSTATISTICS DELIVERABLES PIPELINE · 136 DELIVERABLES", { x: M + 0.32, y: 0.28, w: 12.5, h: 0.3, margin: 0, fontFace: BF, fontSize: 10, bold: true, charSpacing: 1, color: MUTED });
s.addText("Protocol review  →  CSR draft", { x: M + 0.32, y: 0.52, w: 12, h: 0.5, margin: 0, fontFace: HF, fontSize: 26, bold: true, color: INK });

const stages = [
  { c: "S1", n: "Study Design\n& Protocol", col: "3B4BA8", bg: "ECEEFB", ink: "2B3578", items: ["Protocol biostat input", "Estimands → endpoints", "Sample-size justification", "Randomization design", "DSMB / SRC decision rules"], gate: "Protocol approved" },
  { c: "S2", n: "Planning &\nSpecifications", col: "0E7C86", bg: "E2F1F2", ink: "0A4F57", items: ["Statistical Analysis Plan", "TLF shells / mock-ups", "ADaM & SDTM specs", "Randomization schedule", "Data-review & QC plans"], gate: "SAP & specs final" },
  { c: "S3", n: "Data &\nCDISC", col: "2F6DB5", bg: "E5EEF8", ink: "1E4C82", items: ["SDTM datasets + aCRF", "ADaM datasets", "Define-XML + cSDRG/ADRG", "Conformance (Pinnacle 21)", "Database lock + audit trail"], gate: "Database lock" },
  { c: "S4", n: "Analysis\n& QC", col: "C2891C", bg: "FAF0D8", ink: "6B4E12", items: ["PK conc & NCA TLFs (Phoenix)", "Safety / PD TLFs", "popPK / exposure-response", "Independent double-programming", "Unblinding (controlled)"], gate: "Outputs QC-passed" },
  { c: "S5", n: "Reporting\n& CSR", col: "4338CA", bg: "ECECFB", ink: "312C8A", items: ["CSR methods & results text", "In-text tables / figures", "CSR appendices (16.x)", "Define + guides → eCTD m5", "Cross-doc consistency QC"], gate: "CSR draft delivered" },
];
const gap = 0.32, colW = (W - 2 * M - 4 * gap) / 5, py = 1.45, ch = 3.55;
stages.forEach((st, i) => {
  const x = M + i * (colW + gap);
  s.addShape(pres.shapes.RECTANGLE, { x, y: py, w: colW, h: ch, fill: { color: st.bg }, line: { color: LINEC, width: 1 } });
  s.addShape(pres.shapes.RECTANGLE, { x, y: py, w: colW, h: 0.82, fill: { color: st.col } });
  s.addText([{ text: st.c + "\n", options: { fontSize: 11, bold: true, color: "FFFFFF", charSpacing: 1 } }, { text: st.n, options: { fontSize: 12.5, bold: true, color: "FFFFFF" } }], { x: x + 0.15, y: py + 0.07, w: colW - 0.3, h: 0.72, margin: 0, fontFace: HF, align: "center", valign: "middle", lineSpacingMultiple: 0.9 });
  s.addText(st.items.map(t => ({ text: t, options: { bullet: { code: "2022", indent: 10 }, breakLine: true, paraSpaceAfter: 7 } })), { x: x + 0.18, y: py + 0.95, w: colW - 0.32, h: 2.0, margin: 0, fontFace: BF, fontSize: 10, color: st.ink, lineSpacingMultiple: 0.98 });
  s.addShape(pres.shapes.RECTANGLE, { x, y: py + ch - 0.62, w: colW, h: 0.62, fill: { color: st.col } });
  s.addText([{ text: "GATE\n", options: { fontSize: 8, bold: true, color: "FFFFFF", charSpacing: 1 } }, { text: st.gate, options: { fontSize: 10, bold: true, color: "FFFFFF" } }], { x: x + 0.1, y: py + ch - 0.6, w: colW - 0.2, h: 0.58, margin: 0, fontFace: BF, align: "center", valign: "middle", lineSpacingMultiple: 0.85 });
  if (i < 4) s.addText("▶", { x: x + colW + 0.02, y: py + ch / 2 - 0.16, w: gap - 0.02, h: 0.32, margin: 0, fontFace: BF, fontSize: 13, color: MUTED, align: "center", valign: "middle" });
});

// cross-cutting tracks
const ty = py + ch + 0.18;
s.addShape(pres.shapes.RECTANGLE, { x: M, y: ty, w: W - 2 * M, h: 0.42, fill: { color: "E5EEF8" }, line: { color: "CBDDF0", width: 1 } });
s.addText([{ text: "CDISC data-standards track:  ", options: { bold: true, color: "1E4C82" } }, { text: "SDTM → ADaM → Define-XML + cSDRG / ADRG + conformance   (runs through Stages 3–5)", options: { color: INK } }], { x: M + 0.25, y: ty, w: W - 2 * M - 0.5, h: 0.42, margin: 0, fontFace: BF, fontSize: 10.5, valign: "middle" });
s.addShape(pres.shapes.RECTANGLE, { x: M, y: ty + 0.5, w: W - 2 * M, h: 0.42, fill: { color: "ECECFB" }, line: { color: "D6D6F5", width: 1 } });
s.addText([{ text: "Hybrid-AI governance track:  ", options: { bold: true, color: "312C8A" } }, { text: "data-classification routing · model-freeze records · engine-of-record register · zero-egress attestation   (all stages)", options: { color: INK } }], { x: M + 0.25, y: ty + 0.5, w: W - 2 * M - 0.5, h: 0.42, margin: 0, fontFace: BF, fontSize: 10.5, valign: "middle" });

// AI tier legend + hard rules
const ly = ty + 1.05;
const legend = [["🟢 GREEN · 48", "drafts, scaffolds, docs (de-identified)", "0F9D6E"], ["🟡 AMBER · 54", "dataset / TLF code — AI as one side of double-programming", "C2891C"], ["🔴 RED · 34", "validated engine produces the number — LLM out of the path", "B5564B"]];
const lw = (W - 2 * M - 2 * 0.25) / 3;
legend.forEach((g, i) => { const x = M + i * (lw + 0.25); s.addShape(pres.shapes.RECTANGLE, { x, y: ly, w: lw, h: 0.6, fill: { color: PANEL }, line: { color: LINEC, width: 1 } }); s.addShape(pres.shapes.RECTANGLE, { x, y: ly, w: 0.09, h: 0.6, fill: { color: g[2] } }); s.addText([{ text: g[0] + "  ", options: { bold: true, color: INK, fontSize: 11 } }, { text: g[1], options: { color: MUTED, fontSize: 9.5 } }], { x: x + 0.22, y: ly, w: lw - 0.35, h: 0.6, margin: 0, fontFace: BF, valign: "middle", lineSpacingMultiple: 0.95 }); });

s.addText([{ text: "3 hard rules:  ", options: { bold: true, color: "312C8A" } }, { text: "PHI / unblinded never leaves (local frozen model) · every reported number from a validated engine, never an LLM · de-identification unlocks the cloud path (Claude API + BAA, never a consumer seat).", options: { color: INK } }], { x: M, y: ly + 0.7, w: W - 2 * M, h: 0.35, margin: 0, fontFace: BF, fontSize: 10, valign: "middle" });
s.addText("136 deliverables across 5 stages · full register with every field = the .xlsx · stage-by-stage detail = the Word/PDF reference · standards current mid-2026 (CDISC SDTMIG v3.4 / ADaMIG v1.3 / Define-XML v2.1; ICH E3·E6(R3)·E9(R1)·M11; 21 CFR Part 11).", { x: M, y: 7.12, w: W - 2 * M, h: 0.3, margin: 0, fontFace: BF, fontSize: 8, italic: true, color: "9197B5" });

pres.writeFile({ fileName: "/Users/patrickiben/Optimized_CCR_Slides/biostat_pipeline/EarlyPhase_Biostat_Pipeline_Map.pptx" }).then(f => console.log("WROTE", f)).catch(e => { console.error(e); process.exit(1); });
