// Worked example: a day on the hybrid trial-ops platform — five automations firing,
// each TRIGGER -> AI PROPOSES (engine) -> HUMAN APPROVES. Study CP-101.
const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";
pres.title = "Trial-ops worked example — a day on the platform";
const DARK = "15183A", INK = "1A1E33", MUTED = "5A607E", ICE = "D5DAF5", PANEL = "F4F5FB", LINE = "DDE1EE", SUBTLE = "F7F8FC";
const INDIGO = "4338CA", INDIGOINK = "312C8A", INDBG = "ECECFB";
const TEAL = "0E7C86", TEALBG = "E2F1F2", CLOUDB = "2F6DB5", CLOUDBG = "E5EEF8", SLATE = "64748B", GREEN = "0F9D6E", AMBER = "C2891C";
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
// a 3-lane automation screen: TRIGGER -> AI PROPOSES (engine) -> HUMAN APPROVES
function auto(s, eyebrow, title, accent, lanes, note) {
  header(s, eyebrow, title, accent);
  const eng = lanes[1][2]; // LOCAL or CLOUD
  const cards = [
    ["TRIGGER", lanes[0][0], lanes[0][1], SLATE, "EEF1F6", "3a4060", ""],
    ["AI PROPOSES — DRAFT ONLY", lanes[1][0], lanes[1][1], eng === "LOCAL" ? TEAL : CLOUDB, eng === "LOCAL" ? TEALBG : CLOUDBG, eng === "LOCAL" ? "0A4F57" : "1E4C82", eng],
    ["HUMAN APPROVES — the gate", lanes[2][0], lanes[2][1], GREEN, "E7F6F0", "0B5C42", ""],
  ];
  const cw = (12.3 - 0.6) / 3, cy = 1.55, ch = 4.0;
  cards.forEach((c, i) => {
    const x = 0.5 + i * (cw + 0.3);
    s.addShape(R, { x, y: cy, w: cw, h: ch, fill: { color: c[4] }, line: { color: LINE, width: 1 }, shadow: shadow() });
    s.addShape(R, { x, y: cy, w: cw, h: 0.56, fill: { color: c[3] } });
    s.addText(c[0], { x: x + 0.18, y: cy, w: cw - 0.36, h: 0.56, margin: 0, fontFace: BF, fontSize: 10, bold: true, color: "FFFFFF", valign: "middle" });
    if (c[6]) pill(s, x + cw - 1.0, cy + 0.13, c[6], "FFFFFF", c[6] === "LOCAL" ? "0A4F57" : "1E4C82", 0.85);
    s.addText(c[1], { x: x + 0.22, y: cy + 0.72, w: cw - 0.44, h: 0.78, margin: 0, fontFace: HF, fontSize: 14.5, bold: true, color: INK, valign: "top", lineSpacingMultiple: 0.95 });
    s.addText(c[2], { x: x + 0.22, y: cy + 1.55, w: cw - 0.44, h: ch - 1.75, margin: 0, fontFace: BF, fontSize: 12, color: c[5], valign: "top", lineSpacingMultiple: 1.06 });
    if (i < 2) s.addText("→", { x: x + cw + 0.02, y: cy + ch / 2 - 0.2, w: 0.26, h: 0.4, margin: 0, fontFace: BF, fontSize: 18, bold: true, color: SLATE, align: "center" });
  });
  callout(s, note, accent);
}
// ===== 1 TITLE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: DARK };
  s.addText("TRIAL-OPS WORKED EXAMPLE · STUDY CP-101", { x: 0.7, y: 1.6, w: 11, h: 0.3, margin: 0, fontFace: BF, fontSize: 12, bold: true, charSpacing: 2, color: ICE });
  s.addText("A day on the hybrid\ntrial-ops platform", { x: 0.7, y: 2.0, w: 11.5, h: 1.6, margin: 0, fontFace: HF, fontSize: 34, bold: true, color: "FFFFFF", lineSpacingMultiple: 1.0 });
  s.addText("Five automations fire across one day — recurrent QC, SOP knowledge, eTMF filing, timeline cascade, and risk-based monitoring. Each one follows the same shape: a trigger, an AI-drafted proposal, and a human who approves. Nothing reaches a validated system of record without that approval.", { x: 0.7, y: 3.7, w: 11.5, h: 1.3, margin: 0, fontFace: BF, fontSize: 14.5, color: ICE, lineSpacingMultiple: 1.08 });
  s.addText("Illustrative. Sensitive data stays on the LOCAL model; validated systems (EDC / eTMF / CTMS) own every record; a human approves every action.", { x: 0.7, y: 5.6, w: 11.5, h: 0.4, margin: 0, fontFace: BF, fontSize: 11, italic: true, color: "8088B0" });
}
// ===== 2 THE RULE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  header(s, "THE PLATFORM & THE RULE", "Every automation: trigger → AI drafts → a human approves", INDIGO);
  s.addShape(R, { x: 0.5, y: 1.4, w: 12.3, h: 0.95, fill: { color: PANEL }, line: { color: LINE, width: 1 } });
  s.addShape(R, { x: 0.5, y: 1.4, w: 0.1, h: 0.95, fill: { color: INDIGO } });
  s.addText([{ text: "The rule (every one of the 75 automations): ", options: { bold: true, color: INK } }, { text: "the agent ", options: { color: "33384f" } }, { text: "drafts a proposal", options: { bold: true, color: INDIGOINK } }, { text: " into a ", options: { color: "33384f" } }, { text: "human-approval queue", options: { bold: true, color: "0B5C42" } }, { text: "; nothing is filed, sent, or changed in a validated system until a human approves. Sensitive data → LOCAL; non-sensitive → cloud.", options: { color: "33384f" } }], { x: 0.85, y: 1.4, w: 11.7, h: 0.95, margin: 0, fontFace: BF, fontSize: 13.5, valign: "middle", lineSpacingMultiple: 1.05 });
  const items = [["08:00", "Nightly QC triage", "a data discrepancy → a drafted query", TEAL], ["10:30", "SOP knowledge (RAG)", "a CRA's procedure question → a cited answer", CLOUDB], ["13:00", "eTMF filing", "a visit report arrives → a filing proposal", CLOUDB], ["15:00", "Timeline cascade", "a milestone slips → a Smartsheet update", AMBER], ["16:30", "RBQM / KRI", "a KRI breaches → a flag to the PM", TEAL]];
  const cw = (12.3 - 4 * 0.25) / 5, cy = 2.7, ch = 3.4;
  items.forEach((it, i) => {
    const x = 0.5 + i * (cw + 0.25);
    s.addShape(R, { x, y: cy, w: cw, h: ch, fill: { color: "FFFFFF" }, line: { color: LINE, width: 1 }, shadow: shadow() });
    s.addShape(R, { x, y: cy, w: cw, h: 0.08, fill: { color: it[3] } });
    pill(s, x + cw / 2 - 0.5, cy + 0.3, it[0], "FFFFFF", it[3], 1.0);
    s.addText(it[1], { x: x + 0.12, y: cy + 0.85, w: cw - 0.24, h: 0.7, margin: 0, fontFace: HF, fontSize: 13, bold: true, color: INK, align: "center", valign: "top", lineSpacingMultiple: 0.95 });
    s.addText(it[2], { x: x + 0.12, y: cy + 1.65, w: cw - 0.24, h: ch - 1.8, margin: 0, fontFace: BF, fontSize: 11, color: MUTED, align: "center", valign: "top", lineSpacingMultiple: 1.05 });
  });
  callout(s, "Five automations, one day, one shape — the agent does the drafting; a human owns every approval and every validated record.", INDIGO);
}
// ===== 3-7 AUTOMATIONS =====
{ const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  auto(s, "08:00 · RECURRENT QC TRIAGE", "A nightly check catches a data discrepancy", TEAL,
    [["Nightly QC run flags it", "AE onset date is after the resolution date for participant 0188 — a logic check fires on the new EDC extract."],
     ["Agent drafts the data query", "On the participant-level data — LOCAL, zero egress. Drafts a clear, specific query citing the fields and the rule, ready for the data manager.", "LOCAL"],
     ["Data manager approves & issues", "Reviews the drafted query, edits if needed, and issues it in the validated EDC. The agent never writes to the EDC itself."]],
    "Participant-level → LOCAL, zero egress. The agent drafts the query; the data manager approves and issues it in the validated EDC."); }
{ const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  auto(s, "10:30 · SOP KNOWLEDGE (RAG)", "A CRA asks a procedure question", CLOUDB,
    [["“What's our process for a missed PK sample?”", "A CRA asks the ops assistant, grounded on the SOPs / work-instructions library (non-sensitive)."],
     ["Agent answers with citations", "Retrieves the relevant SOP section and answers in plain language, with a citation to the exact SOP + version — de-identified, so cloud.", "CLOUD"],
     ["The human verifies the citation", "The CRA checks the cited SOP before acting; the SOP remains the source of truth, not the model's paraphrase."]],
    "Non-sensitive SOP retrieval → cloud, with citations. The answer points to the controlled SOP; a human verifies before acting."); }
{ const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  auto(s, "13:00 · eTMF FILING", "A monitoring visit report arrives", CLOUDB,
    [["A new MVR lands in the shared drive", "The platform detects a document to be filed in the eTMF."],
     ["Agent proposes the filing", "Classifies it (TMF Reference Model zone/section), proposes the location, and pre-fills metadata — on the non-sensitive document. Nothing is filed yet.", "CLOUD"],
     ["The TMF specialist approves the filing", "Confirms the classification and files it in the validated eTMF; the proposal is a draft in the approval queue."]],
    "The agent proposes the eTMF zone, location, and metadata; the TMF specialist approves and files in the validated eTMF."); }
{ const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  auto(s, "15:00 · TIMELINE CASCADE", "A milestone slips — the schedule must follow", AMBER,
    [["Data-cut moves 17 → 19 Jun", "The confirmed change (from the email-wiki / PM) means downstream dates shift."],
     ["Agent drafts the Smartsheet cascade", "Computes the dependent date shifts (soft-lock, dry-run TLFs, DSMB pack) and drafts the Smartsheet update + a notification — non-sensitive ops data.", "CLOUD"],
     ["The PM reviews & applies", "Checks the cascade, adjusts, and applies it; stakeholders are notified. The PM owns the timeline."]],
    "Non-sensitive timeline logic → cloud draft. The agent computes the cascade; the PM reviews and applies the change."); }
{ const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  auto(s, "16:30 · RBQM / KRI", "A risk indicator breaches its tolerance", TEAL,
    [["Site 02 query rate exceeds its KRI", "A risk-based-monitoring KRI crosses its quality tolerance limit on the latest data."],
     ["Agent packages the signal", "Summarizes the breach with the trend and the contributing records — on the aggregate/site data — and drafts the RBM action note.", "LOCAL"],
     ["The PM / central monitor decides", "Reviews the packaged signal and decides the monitoring response (e.g. a targeted visit). The system flags; the human decides."]],
    "The agent packages the KRI breach with its evidence; the PM / central monitor decides the response. The AI flags, never acts."); }
// ===== 8 CLOSE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: DARK };
  s.addShape(RR, { x: 0.7, y: 0.6, w: 0.16, h: 0.34, fill: { color: INDIGO }, rectRadius: 0.04 });
  s.addText("WHAT THE DAY SHOWS", { x: 1.0, y: 0.55, w: 10, h: 0.3, margin: 0, fontFace: BF, fontSize: 11, bold: true, charSpacing: 2, color: ICE });
  s.addText("The platform drafts; the humans approve; the validated systems own the records.", { x: 0.7, y: 1.1, w: 12, h: 0.9, margin: 0, fontFace: HF, fontSize: 23, bold: true, color: "FFFFFF" });
  const pts = [["One shape, every automation", "Trigger → AI draft → human approval. The drafting is automated; the approval and the record are not.", INDIGO], ["Sensitivity routed the engine", "Participant-level QC and the RBM signal stayed LOCAL (zero egress); de-identified SOP / filing / timeline work went to CLOUD.", TEAL], ["Validated systems stayed authoritative", "The EDC issued the query, the eTMF filed the document, Smartsheet held the timeline — the agent wrote to none of them directly.", SLATE], ["The payoff", "The busywork — drafting queries, classifying docs, computing cascades, packaging signals — is automated; judgment and accountability stay human.", GREEN]];
  const cw = (12.3 - 0.5) / 2, cy = 2.15, ch = 1.75;
  pts.forEach((p, i) => { const x = 0.7 + (i % 2) * (cw + 0.5), y = cy + Math.floor(i / 2) * (ch + 0.25); s.addShape(R, { x, y, w: cw, h: ch, fill: { color: "1E2350" }, line: { color: "343A6E", width: 1 } }); s.addShape(R, { x, y, w: 0.09, h: ch, fill: { color: p[2] } }); s.addText(p[0], { x: x + 0.3, y: y + 0.16, w: cw - 0.5, h: 0.5, margin: 0, fontFace: HF, fontSize: 15, bold: true, color: "FFFFFF" }); s.addText(p[1], { x: x + 0.3, y: y + 0.66, w: cw - 0.55, h: ch - 0.78, margin: 0, fontFace: BF, fontSize: 11.5, color: ICE, valign: "top", lineSpacingMultiple: 1.03 }); });
  s.addText("Illustrative. The full 75-automation platform is in the hybrid trial-ops wiki; every automation runs behind a human-approval queue.", { x: 0.7, y: H - 0.6, w: 12, h: 0.35, margin: 0, fontFace: BF, fontSize: 11, italic: true, color: "8088B0", align: "center" });
}
pres.writeFile({ fileName: __dirname + "/TrialOps_Day_WorkedExample.pptx" }).then(f => console.log("WROTE", f, "(" + S.length + " slides)"));
