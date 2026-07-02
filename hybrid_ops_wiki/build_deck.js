// Narrated walkthrough deck: the hybrid AI trial-operations layer. 13 slides.
const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";
pres.author = "Lead Biostatistician";
pres.title = "Hybrid AI Trial-Operations Layer — Walkthrough";
const S = [];
const NOTES = require("./notes.js");
const DARK = "15183A", NAVY = "23264F", INK = "1A1E33", MUTED = "5A607E", ICE = "D5DAF5", PANEL = "F4F5FB", LINEC = "E0E3F1";
const INDIGO = "4338CA", INDIGOBG = "ECECFB", INDIGOINK = "312C8A";
const TEAL = "0E7C86", TEALBG = "E2F1F2", TEALINK = "0A4F57";
const CLOUDB = "2F6DB5", CLOUDBG = "E5EEF8", CLOUDINK = "1E4C82";
const EMER = "0F9D6E", EMERBG = "E7F6F0", EMERINK = "0B5C42";
const TERRA = "B5564B", TERRBG = "F7EAE8", TERRINK = "6E3A33";
const AMBER = "C2891C", AMBERBG = "FAF0D8", AMBERINK = "6B4E12", GOLD = "E0A100", SLATE = "64748B", PURP = "7C5CBF";
const HF = "Georgia", BF = "Calibri";
const W = 13.3, H = 7.5, M = 0.7;
const mkShadow = () => ({ type: "outer", color: "1A1E33", blur: 9, offset: 3, angle: 135, opacity: 0.12 });
function chip(s, x, y, c) { s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 0.16, h: 0.34, fill: { color: c }, rectRadius: 0.04 }); }
function titleBlock(s, eye, title, opts = {}) { const d = opts.dark; chip(s, M, 0.5, opts.accent || INDIGO); s.addText(eye, { x: M + 0.3, y: 0.45, w: W - 2 * M, h: 0.3, margin: 0, fontFace: BF, fontSize: 11, bold: true, charSpacing: 2, color: d ? ICE : MUTED }); s.addText(title, { x: M + 0.3, y: 0.73, w: W - 2 * M, h: 0.66, margin: 0, fontFace: HF, fontSize: 26, bold: true, color: d ? "FFFFFF" : INK }); }
function footnote(s, t, d) { s.addText(t, { x: M, y: H - 0.46, w: W - 2 * M, h: 0.3, margin: 0, fontFace: BF, fontSize: 8.5, italic: true, color: d ? "9098C0" : "9197B5" }); }
function node(s, x, y, w, h, title, sub, color, bg) { s.addShape(pres.shapes.RECTANGLE, { x, y, w, h, fill: { color: bg }, line: { color: LINEC, width: 1 } }); s.addShape(pres.shapes.RECTANGLE, { x, y, w: 0.09, h, fill: { color } }); s.addText([{ text: title + "  ", options: { bold: true, color: INK, fontSize: 12.5 } }, { text: sub, options: { color: MUTED, fontSize: 10.5 } }], { x: x + 0.28, y, w: w - 0.45, h, margin: 0, fontFace: BF, valign: "middle", lineSpacingMultiple: 0.95 }); }
function areaSlide(eye, title, accent, lead, rows, footColor, footTxt) {
  const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  titleBlock(s, eye, title, { accent });
  s.addText(lead, { x: M + 0.2, y: 1.55, w: W - 2 * M - 0.4, h: 0.55, margin: 0, fontFace: BF, fontSize: 13, italic: true, color: MUTED, lineSpacingMultiple: 1.03 });
  let y = 2.3; const rh = 0.92;
  rows.forEach((r) => { s.addShape(pres.shapes.RECTANGLE, { x: M, y, w: W - 2 * M, h: rh - 0.14, fill: { color: PANEL }, line: { color: LINEC, width: 1 } }); s.addShape(pres.shapes.RECTANGLE, { x: M, y, w: 0.1, h: rh - 0.14, fill: { color: accent } }); s.addText(r[0], { x: M + 0.35, y: y + 0.08, w: 3.7, h: rh - 0.28, margin: 0, fontFace: HF, fontSize: 14, bold: true, color: INK, valign: "middle" }); s.addText(r[1], { x: M + 4.2, y: y + 0.08, w: W - 2 * M - 4.5, h: rh - 0.28, margin: 0, fontFace: BF, fontSize: 11.5, color: MUTED, valign: "middle", lineSpacingMultiple: 1.0 }); y += rh; });
  if (footTxt) footnote(s, footTxt, false);
}

// 1 TITLE
{ const s = pres.addSlide(); S.push(s); s.background = { color: DARK };
  s.addShape(pres.shapes.RECTANGLE, { x: 0, y: 0, w: W, h: 0.12, fill: { color: INDIGO } });
  s.addText("WALKTHROUGH  ·  AGENTIC TRIAL OPERATIONS ON THE HYBRID STACK", { x: M, y: 1.7, w: 11, h: 0.3, margin: 0, fontFace: BF, fontSize: 12, bold: true, charSpacing: 2, color: ICE });
  s.addText("The Hybrid AI\nTrial-Operations Layer", { x: M, y: 2.1, w: 12, h: 1.7, margin: 0, fontFace: HF, fontSize: 42, bold: true, color: "FFFFFF", lineSpacingMultiple: 0.98 });
  s.addText("75 governed automations across project management, trial management, and monitoring — on Claude + local.", { x: M, y: 4.15, w: 11, h: 0.7, margin: 0, fontFace: BF, fontSize: 16, color: ICE });
  s.addText("AI drafts · triages · routes.   Validated tools + humans own every regulated number and record.", { x: M, y: 5.7, w: 11.5, h: 0.4, margin: 0, fontFace: BF, fontSize: 13, italic: true, bold: true, color: "8B92D8" });
}
// 2 PROBLEM
{ const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  titleBlock(s, "THE PROBLEM", "Trial operations are fragmented", { accent: TERRA });
  const cards = [["Spread across systems", "Knowledge and work live in the EDC, eTMF, Smartsheet, Pinnacle 21, email, and a dozen SOPs — none of it joined up."], ["Manual busywork", "QC triage, document filing, status decks, action-item chasing — repetitive, cross-system, and endless."], ["High stakes", "It's regulated work — so any automation has to be governed, not a free-for-all chatbot."]];
  const cw = (W - 2 * M - 0.7) / 3, py = 1.85, ch = 2.95;
  cards.forEach((c, i) => { const cx = M + i * (cw + 0.35); s.addShape(pres.shapes.RECTANGLE, { x: cx, y: py, w: cw, h: ch, fill: { color: PANEL }, line: { color: LINEC, width: 1 }, shadow: mkShadow() }); s.addShape(pres.shapes.RECTANGLE, { x: cx, y: py, w: cw, h: 0.1, fill: { color: TERRA } }); s.addText(c[0], { x: cx + 0.3, y: py + 0.35, w: cw - 0.6, h: 0.6, margin: 0, fontFace: HF, fontSize: 18, bold: true, color: INK }); s.addText(c[1], { x: cx + 0.3, y: py + 1.1, w: cw - 0.6, h: ch - 1.3, margin: 0, fontFace: BF, fontSize: 13, color: MUTED, lineSpacingMultiple: 1.05 }); });
  s.addText("Exactly the work an AI layer can absorb — if, and only if, it's governed properly.", { x: M, y: 5.25, w: W - 2 * M, h: 0.4, margin: 0, fontFace: BF, fontSize: 14, bold: true, italic: true, color: INDIGOINK, align: "center" });
}
// 3 THE IDEA
{ const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  titleBlock(s, "THE IDEA", "Point the hybrid stack at operations", { accent: INDIGO });
  const items = [["75 governed agents", "Across PM, trial management, document control, data QC, and risk-based monitoring."], ["Routed by sensitivity", "PHI / unblinded → local model; de-identified reasoning → Claude. The gateway decides."], ["Tiered by risk", "Green drafts · amber triage with verify · red stays with validated tools + humans."], ["Gated by a human", "Every regulated change is proposed to an approval queue, with a Part 11 audit trail."]];
  const colW = (W - 2 * M - 0.5) / 2, rowH = 1.7, gap = 0.5, x0 = M, y0 = 1.75;
  items.forEach((c, i) => { const cx = x0 + (i % 2) * (colW + gap), cy = y0 + Math.floor(i / 2) * (rowH + 0.3); s.addShape(pres.shapes.RECTANGLE, { x: cx, y: cy, w: colW, h: rowH, fill: { color: INDIGOBG }, line: { color: "D6D6F5", width: 1 } }); s.addShape(pres.shapes.RECTANGLE, { x: cx, y: cy, w: 0.1, h: rowH, fill: { color: INDIGO } }); s.addText(c[0], { x: cx + 0.35, y: cy + 0.22, w: colW - 0.6, h: 0.45, margin: 0, fontFace: HF, fontSize: 17, bold: true, color: INDIGOINK }); s.addText(c[1], { x: cx + 0.35, y: cy + 0.72, w: colW - 0.65, h: rowH - 0.85, margin: 0, fontFace: BF, fontSize: 12.5, color: MUTED, lineSpacingMultiple: 1.02 }); });
}
// 4 ARCHITECTURE
{ const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  titleBlock(s, "THE PLATFORM", "One gateway, many agents", { accent: INDIGO });
  node(s, M, 1.5, W - 2 * M, 0.56, "Orchestration", "scheduler + agent framework — fires agents on schedule or study events", SLATE, PANEL);
  s.addText("▼", { x: W / 2 - 0.2, y: 2.1, w: 0.4, h: 0.2, margin: 0, fontFace: BF, fontSize: 12, color: INDIGO, align: "center" });
  node(s, M, 2.34, W - 2 * M, 0.68, "The Gateway (LiteLLM-class)", "data-classification router · Presidio PHI egress firewall · cost/audit · caching · one Part 11 trail", INDIGO, INDIGOBG);
  s.addText("▼            ▼            ▼", { x: W / 2 - 1.9, y: 3.08, w: 3.8, h: 0.2, margin: 0, fontFace: BF, fontSize: 12, color: INDIGO, align: "center" });
  const pw = (W - 2 * M - 0.6) / 3;
  node(s, M, 3.32, pw, 0.7, "Local model", "sensitive / PHI / unblinded", TEAL, TEALBG);
  node(s, M + pw + 0.3, 3.32, pw, 0.7, "Claude API (BAA)", "de-identified reasoning", CLOUDB, CLOUDBG);
  node(s, M + 2 * (pw + 0.3), 3.32, pw, 0.7, "RAG knowledge base", "SOPs / WIs / study docs", AMBER, AMBERBG);
  s.addText("▼   connectors (MCP)   ▼", { x: W / 2 - 1.5, y: 4.1, w: 3.0, h: 0.2, margin: 0, fontFace: BF, fontSize: 11, color: INDIGO, align: "center" });
  node(s, M, 4.34, W - 2 * M, 0.62, "Systems of record", "eTMF · Smartsheet · EDC · CTMS · SharePoint · Outlook · Pinnacle 21  (read-mostly; writes gated)", PURP, "F1ECFA");
  s.addText("▼", { x: W / 2 - 0.2, y: 5.0, w: 0.4, h: 0.2, margin: 0, fontFace: BF, fontSize: 12, color: INDIGO, align: "center" });
  node(s, M, 5.22, W - 2 * M, 0.64, "Human-in-the-loop approval queue", "every regulated change proposed here — AI rationale + sources — for a human to approve / edit / reject", EMER, EMERBG);
  footnote(s, "Same hybrid architecture as the AI strategy — here, pointed at operations.", false);
}
// 5 GOVERNANCE
{ const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  titleBlock(s, "GOVERNANCE", "Why this is safe to run", { accent: EMER });
  const tiers = [["GREEN · 14", "Drafts, summaries, cited RAG answers — advisory only.", EMER, EMERBG, EMERINK], ["AMBER · 43", "Classification, triage, code, proposed changes — with a human verify before commit.", AMBER, AMBERBG, AMBERINK], ["RED · 18", "Reported numbers, records of truth, unblinded data — validated tool + human; LLM out of the path.", TERRA, TERRBG, TERRINK]];
  const cw = (W - 2 * M - 0.7) / 3, py = 1.7, ch = 2.0;
  tiers.forEach((t, i) => { const cx = M + i * (cw + 0.35); s.addShape(pres.shapes.RECTANGLE, { x: cx, y: py, w: cw, h: ch, fill: { color: t[3] }, line: { color: LINEC, width: 1 } }); s.addShape(pres.shapes.RECTANGLE, { x: cx, y: py, w: cw, h: 0.55, fill: { color: t[2] } }); s.addText(t[0], { x: cx + 0.2, y: py + 0.08, w: cw - 0.4, h: 0.4, margin: 0, fontFace: HF, fontSize: 16, bold: true, color: "FFFFFF" }); s.addText(t[1], { x: cx + 0.25, y: py + 0.7, w: cw - 0.5, h: ch - 0.85, margin: 0, fontFace: BF, fontSize: 12, color: t[4], lineSpacingMultiple: 1.03 }); });
  s.addShape(pres.shapes.RECTANGLE, { x: M, y: 3.9, w: W - 2 * M, h: 2.35, fill: { color: NAVY } });
  s.addText("The three hard rules", { x: M + 0.35, y: 4.02, w: 11, h: 0.4, margin: 0, fontFace: HF, fontSize: 16, bold: true, color: "FFFFFF" });
  s.addText([
    { text: "1.  PHI / unblinded / randomization data never leaves", options: { bold: true, color: "FFFFFF", breakLine: true } },
    { text: "       always the local frozen model (zero egress); de-identified text may use Claude.", options: { color: ICE, breakLine: true, paraSpaceAfter: 6 } },
    { text: "2.  Every reported number & record of truth comes from a validated tool", options: { bold: true, color: "FFFFFF", breakLine: true } },
    { text: "       Pinnacle 21 · Phoenix · the EDC / CTMS / eTMF — never an LLM.", options: { color: ICE, breakLine: true, paraSpaceAfter: 6 } },
    { text: "3.  A human approves any change to a regulated record or timeline", options: { bold: true, color: "FFFFFF", breakLine: true } },
    { text: "       via the approval queue, with a 21 CFR Part 11 audit trail.", options: { color: ICE } },
  ], { x: M + 0.35, y: 4.52, w: 11.6, h: 1.65, margin: 0, fontFace: BF, fontSize: 11.5, lineSpacingMultiple: 1.0 });
}
// 6 PM
areaSlide("USE CASES · PROJECT & TIMELINE", "Smartsheet runs the plan; the AI keeps it current", INDIGO,
  "12 automations. Smartsheet's engine computes the critical path; the AI explains, prioritizes, and proposes — the PM approves before any committed-date write.",
  [["Critical-path tracking", "Nightly + on any change: recompute float, flag tasks now driving the finish, explain what moved."], ["Data-cut / lock cascade", "On the event: recompute downstream dates, draft 'you're now blocked' alerts, post to the approval queue."], ["Status reports", "Weekly/monthly: drafted in the house template from the plan-of-record — numbers from systems of record."], ["Action & decision capture", "From email/meetings (local model): extract owners, due dates, decisions; de-dupe against the log."]],
  null, "Smartsheet API + webhooks · CTMS · Outlook/Teams · RAG (charter / plan-of-record). Tier: mostly AMBER — committed dates need PM approval.");
// 7 eTMF
areaSlide("USE CASES · eTMF & DOCUMENTS", "Filing, completeness, and SOP knowledge", TEAL,
  "12 automations. Filing to the record-of-truth is human-approved; RAG answers over your SOPs are cited and advisory.",
  [["Auto-classify & file", "Propose TMF Reference Model zone/artifact for each document; flag likely duplicates → controller approves."], ["Completeness & expiry", "Detect missing TMF artifacts and expiring CVs / training / licenses; alert owners."], ["SOP / WI ingestion (RAG)", "Approved SOPs embedded into the local store for grounded, cited compliance Q&A."], ["Inspection readiness", "Gap analysis against the TMF model; PII/redaction check before any cloud use."]],
  null, "DIA TMF Reference Model · eTMF (e.g. Veeva) API · local vector store. Tier: GREEN (RAG Q&A) → RED (filing of record, human-approved).");
// 8 DATA QC (marquee)
{ const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  titleBlock(s, "USE CASES · DATA-VALIDITY QC  (the marquee)", "Recurrent QC triage at every stage", { accent: AMBER });
  s.addText("12 automations. The validated tool produces pass/fail; the AI makes it usable — surfacing only what's new.", { x: M + 0.2, y: 1.55, w: W - 2 * M - 0.4, h: 0.35, margin: 0, fontFace: BF, fontSize: 13, italic: true, color: MUTED });
  const flow = [["1", "Nightly build", "A new SDTM / ADaM dataset lands", SLATE], ["2", "Pinnacle 21 runs", "Validated tool → authoritative Error / Warning / Notice list", TERRA], ["3", "Local agent triages", "Clusters by rule, diffs vs last clean run → only NEW findings; drafts disposition from the cSDRG/ADRG", TEAL], ["4", "Routed + audited", "Each cluster sent to the right programmer; disposition log ready for the reviewer guide", INDIGO]];
  let y = 2.15; const rh = 0.84;
  flow.forEach((f) => { s.addShape(pres.shapes.OVAL, { x: M, y, w: 0.55, h: 0.55, fill: { color: f[3] } }); s.addText(f[0], { x: M, y, w: 0.55, h: 0.55, margin: 0, fontFace: HF, fontSize: 20, bold: true, color: "FFFFFF", align: "center", valign: "middle" }); s.addText([{ text: f[1] + "  ", options: { bold: true, color: INK, fontSize: 14 } }, { text: "— " + f[2], options: { color: MUTED, fontSize: 12.5 } }], { x: M + 0.75, y: y - 0.05, w: W - 2 * M - 0.9, h: 0.65, margin: 0, fontFace: BF, valign: "middle", lineSpacingMultiple: 1.0 }); y += rh; });
  s.addShape(pres.shapes.RECTANGLE, { x: M, y: 5.7, w: W - 2 * M, h: 0.72, fill: { color: EMERBG }, line: { color: "CBE9DD", width: 1 } });
  s.addText([{ text: "It never changes a verdict.  ", options: { bold: true, color: EMERINK } }, { text: "A 4-hour manual triage becomes a clean, pre-explained queue at 8 a.m. — participant-level data stays on the local model.", options: { color: INK } }], { x: M + 0.3, y: 5.7, w: W - 2 * M - 0.6, h: 0.72, margin: 0, fontFace: BF, fontSize: 12.5, valign: "middle" });
}
// 9 MONITORING
areaSlide("USE CASES · MONITORING & RBQM", "Risk-based quality management, signalled", CLOUDB,
  "12 automations under ICH E6(R3). Unblinded signals run on the local model; reported safety numbers come from validated tools with medical review.",
  [["KRI / QTL breach signals", "Watch key risk indicators & quality tolerance limits; flag threshold breaches with context."], ["Central / statistical monitoring", "Site outliers, digit preference, enrollment & visit anomalies surfaced for review."], ["Deviation surveillance", "Detect & classify protocol deviations; route for adjudication; track to closure."], ["DSMB / safety packet assembly", "Assemble the review packet; summarize MVRs; track follow-ups — medical review owns the call."]],
  null, "EDC / CTMS · RBQM platform · local model for unblinded signals. Tier: AMBER signals → RED reported safety numbers (validated + medical).");
// 10 AGENT LOOP
{ const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  titleBlock(s, "HOW AN AGENT WORKS", "One loop, 75 automations", { accent: INDIGO });
  const steps = [["Trigger", "schedule or study event"], ["Gather context", "connectors (read) + RAG (cited)"], ["Classify & route", "sensitivity → local or cloud, via gateway"], ["Reason", "draft / classify / triage / summarize"], ["Propose", "to the human-approval queue + rationale + sources"], ["On approval → write", "to the system of record, via connector"], ["Audit", "every step → the Part 11 trail"]];
  let y = 1.7; const rh = 0.66;
  steps.forEach((st, i) => { s.addShape(pres.shapes.OVAL, { x: M + 0.1, y, w: 0.46, h: 0.46, fill: { color: INDIGO } }); s.addText(String(i + 1), { x: M + 0.1, y, w: 0.46, h: 0.46, margin: 0, fontFace: HF, fontSize: 16, bold: true, color: "FFFFFF", align: "center", valign: "middle" }); s.addText([{ text: st[0] + "   ", options: { bold: true, color: INK, fontSize: 15 } }, { text: st[1], options: { color: MUTED, fontSize: 13 } }], { x: M + 0.75, y: y - 0.05, w: W - 2 * M - 0.9, h: 0.55, margin: 0, fontFace: BF, valign: "middle" }); if (i < steps.length - 1) s.addShape(pres.shapes.LINE, { x: M + 0.33, y: y + 0.46, w: 0, h: rh - 0.46, line: { color: "C7C9E8", width: 1.5 } }); y += rh; });
  footnote(s, "The loop is what makes 75 different automations safe and consistent — every one ends with a human and an audit entry.", false);
}
// 11 ROADMAP
{ const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  titleBlock(s, "BUILD ROADMAP", "Start small, earn trust", { accent: GOLD });
  const phases = [["PHASE 0", "The stack", SLATE, "Gateway · local model · Claude (BAA) · Presidio guardrail · approval queue · Part 11 trail"], ["PHASE 1", "The knowledge base", EMER, "Ingest SOPs/WIs → ship the SOP/compliance Q&A agent first (pure GREEN, cited, instant value)"], ["PHASE 2", "Read connectors + scheduled agents", CLOUDB, "Smartsheet / eTMF / Pinnacle 21 (read) → nightly QC-triage + weekly status (AMBER, approval queue)"], ["PHASE 3", "Event-driven + monitoring", INDIGO, "Timeline cascade · eTMF filing proposals · KRI/QTL signals — each graduates as it earns a track record"]];
  let y = 1.75; const rh = 1.05;
  phases.forEach((p) => { s.addShape(pres.shapes.RECTANGLE, { x: M, y, w: 2.0, h: rh - 0.15, fill: { color: p[2] } }); s.addText([{ text: p[0] + "\n", options: { fontSize: 10, bold: true, color: "FFFFFF", charSpacing: 1 } }, { text: p[1], options: { fontSize: 12.5, bold: true, color: "FFFFFF" } }], { x: M + 0.15, y, w: 1.8, h: rh - 0.15, margin: 0, fontFace: HF, valign: "middle", lineSpacingMultiple: 0.92 }); s.addShape(pres.shapes.RECTANGLE, { x: M + 2.0, y, w: W - 2 * M - 2.0, h: rh - 0.15, fill: { color: PANEL }, line: { color: LINEC, width: 1 } }); s.addText(p[3], { x: M + 2.25, y: y + 0.05, w: W - 2 * M - 2.5, h: rh - 0.25, margin: 0, fontFace: BF, fontSize: 12.5, color: INK, valign: "middle", lineSpacingMultiple: 1.0 }); y += rh; });
  footnote(s, "Each new agent goes live behind the human-approval queue and graduates to lighter review as validation and trust accrue.", false);
}
// 12 WORKED EXAMPLE
{ const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  titleBlock(s, "WORKED EXAMPLE", "A day in the ops layer", { accent: GOLD });
  const day = [["02:00", "Nightly QC: 3 genuinely new findings surfaced among 240; the rest pre-explained, routed to programmers.", AMBER], ["10:30", "Data cut declared → critical path recomputed, 'you're blocked' alerts drafted → PM approves → Smartsheet updates in minutes.", INDIGO], ["13:00", "A KRI breaches → the local agent drafts the site follow-up and logs the RBQM register; medical review owns the call.", CLOUDB], ["15:00", "3 reports filed to the eTMF on approval; a programmer gets an SOP answer, cited, in seconds.", TEAL], ["16:00", "The weekly status report drafts itself from the plan-of-record; the PM edits two lines and sends.", EMER]];
  let y = 1.7; const rh = 0.86;
  day.forEach((d) => { s.addShape(pres.shapes.RECTANGLE, { x: M, y, w: 1.15, h: rh - 0.13, fill: { color: d[2] } }); s.addText(d[0], { x: M, y, w: 1.15, h: rh - 0.13, margin: 0, fontFace: HF, fontSize: 15, bold: true, color: "FFFFFF", align: "center", valign: "middle" }); s.addShape(pres.shapes.RECTANGLE, { x: M + 1.15, y, w: W - 2 * M - 1.15, h: rh - 0.13, fill: { color: PANEL }, line: { color: LINEC, width: 1 } }); s.addText(d[1], { x: M + 1.4, y: y + 0.04, w: W - 2 * M - 1.65, h: rh - 0.21, margin: 0, fontFace: BF, fontSize: 12.5, color: INK, valign: "middle", lineSpacingMultiple: 1.0 }); y += rh; });
  footnote(s, "Every regulated number came from a validated system; no patient data left the building; a human approved every committed change.", false);
}
// 13 RECAP
{ const s = pres.addSlide(); S.push(s); s.background = { color: DARK };
  s.addShape(pres.shapes.RECTANGLE, { x: 0, y: 0, w: 0.14, h: H, fill: { color: INDIGO } });
  chip(s, M, 0.8, INDIGO);
  s.addText("RECAP", { x: M + 0.3, y: 0.75, w: 8, h: 0.35, margin: 0, fontFace: BF, fontSize: 12, bold: true, charSpacing: 3, color: ICE });
  s.addText("75 governed automations. Humans keep ownership.", { x: M, y: 1.4, w: 11.8, h: 0.9, margin: 0, fontFace: HF, fontSize: 32, bold: true, color: "FFFFFF" });
  const pts = [["Absorbs the cross-system busywork", "QC triage, filing, status, tracking, monitoring — across PM, trial management, and monitoring."], ["Validated tools + humans own what's regulated", "Every reported number and record of truth; PHI stays on the local model."], ["Safe by construction", "One gateway, one audit trail, a human-approval queue on every regulated change."], ["Start with the knowledge base", "Ship the SOP Q&A agent first; keep everything behind the queue; expand as trust grows."]];
  let ay = 2.75;
  pts.forEach((p, i) => { s.addText(String(i + 1), { x: M, y: ay, w: 0.55, h: 0.55, margin: 0, fontFace: HF, fontSize: 22, bold: true, color: "8B86F0" }); s.addText([{ text: p[0] + "   ", options: { bold: true, color: "FFFFFF" } }, { text: p[1], options: { color: ICE } }], { x: M + 0.65, y: ay + 0.02, w: 11.4, h: 0.7, margin: 0, fontFace: BF, fontSize: 13.5, lineSpacingMultiple: 1.02 }); ay += 0.85; });
  s.addShape(pres.shapes.LINE, { x: M, y: 6.4, w: W - 2 * M, h: 0, line: { color: "3A3E72", width: 1 } });
  s.addText("The full catalog — every automation, engine, integration, and human checkpoint — is in the operating wiki.", { x: M, y: 6.52, w: W - 2 * M, h: 0.5, margin: 0, fontFace: HF, fontSize: 15, bold: true, italic: true, color: "FFFFFF" });
}

S.forEach((sl, i) => { if (sl && NOTES[i]) sl.addNotes(NOTES[i]); });
pres.writeFile({ fileName: "/Users/patrickiben/Optimized_CCR_Slides/hybrid_ops_wiki/Hybrid_Ops_Walkthrough.pptx" }).then(f => console.log("WROTE", f)).catch(e => { console.error(e); process.exit(1); });
