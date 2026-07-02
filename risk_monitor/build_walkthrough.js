// Narrated-walkthrough deck for the Trial-Termination Early-Warning Dashboard (~11 slides).
// Mirrors the dashboard/wiki: 3 tiers, hybrid routing, the advanced engine, the day-9 worked example, governance.
const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";
pres.author = "Lead Biostatistician";
pres.title = "Trial-Termination Early-Warning — Walkthrough";

const DARK = "15183A", NAVY = "23264F", INK = "1A1E33", MUTED = "5A607E", ICE = "D5DAF5", PANEL = "F4F5FB", LINEC = "E0E3F1";
const INDIGO = "4338CA", INDIGOINK = "312C8A", INDBG = "ECECFB";
const VIOLET = "6D28D9", VIOLETBG = "F2F1FB", VIOLETINK = "4A2293";
const TEAL = "0E7C86", TEALBG = "E2F1F2", TEALINK = "0A4F57";
const CLOUDB = "2F6DB5", CLOUDBG = "E5EEF8", CLOUDINK = "1E4C82";
const EMER = "0F9D6E", EMERBG = "E7F6F0", AMBER = "C2891C", AMBERBG = "FAF0D8", TERRA = "B5564B", TERRBG = "F7EAE8", RED = "C0392B";
const HF = "Georgia", BF = "Calibri";
const W = 13.3, H = 7.5, M = 0.7;
const shadow = () => ({ type: "outer", color: "1A1E33", blur: 9, offset: 3, angle: 135, opacity: 0.12 });
const S = [];
function chip(s, x, y, color) { s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 0.16, h: 0.34, fill: { color }, rectRadius: 0.04 }); }
function titleBlock(s, eyebrow, title, accent) {
  chip(s, M, 0.5, accent || INDIGO);
  s.addText(eyebrow, { x: M + 0.3, y: 0.45, w: W - 2 * M, h: 0.3, margin: 0, fontFace: BF, fontSize: 11, bold: true, charSpacing: 2, color: MUTED });
  s.addText(title, { x: M + 0.3, y: 0.73, w: W - 2 * M, h: 0.66, margin: 0, fontFace: HF, fontSize: 25, bold: true, color: INK });
}
function footnote(s, txt) { s.addText(txt, { x: M, y: H - 0.46, w: W - 2 * M, h: 0.3, margin: 0, fontFace: BF, fontSize: 8.5, italic: true, color: "9197B5" }); }
const dot = (s, x, y, c) => s.addShape(pres.shapes.OVAL, { x, y, w: 0.13, h: 0.13, fill: { color: c } });

// ===== 1. TITLE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: DARK };
  s.addShape(pres.shapes.RECTANGLE, { x: 9.7, y: 0, w: 3.6, h: H, fill: { color: "1B1F47" } });
  s.addShape(pres.shapes.RECTANGLE, { x: 9.7, y: 0, w: 0.08, h: H, fill: { color: VIOLET } });
  const tiers = [["PARTICIPANT", "DLTs · safety · PK — on-device", TEAL], ["STUDY", "stopping rules · enrollment · QTLs", AMBER], ["CLIENT", "commercial early-warning", CLOUDB]];
  let ty = 1.5;
  tiers.forEach(t => { dot(s, 10.1, ty + 0.06, t[2]); s.addText([{ text: t[0] + "\n", options: { fontSize: 14, bold: true, color: "FFFFFF", fontFace: HF } }, { text: t[1], options: { fontSize: 9.5, color: ICE } }], { x: 10.35, y: ty - 0.07, w: 2.7, h: 0.8, margin: 0, fontFace: BF, lineSpacingMultiple: 0.92 }); ty += 1.15; });
  s.addText("TRIAL RISK · EARLY-WARNING DASHBOARD", { x: M, y: 1.5, w: 8.6, h: 0.3, margin: 0, fontFace: BF, fontSize: 12, bold: true, charSpacing: 2, color: ICE });
  s.addText("Catching termination\nrisk early — across\nthree tiers", { x: M, y: 1.95, w: 8.7, h: 2.4, margin: 0, fontFace: HF, fontSize: 38, bold: true, color: "FFFFFF", lineSpacingMultiple: 0.98 });
  s.addText("A hybrid of cloud Claude (under a BAA) and on-device local LLMs. The AI detects, aggregates, and triages — it never makes the safety or termination call. A walkthrough.", { x: M, y: 4.75, w: 8.4, h: 0.9, margin: 0, fontFace: BF, fontSize: 14, color: ICE });
  s.addShape(pres.shapes.LINE, { x: M, y: 5.95, w: 3.5, h: 0, line: { color: "3A3E72", width: 1 } });
  s.addText("Prepared by [Your Name], Lead Biostatistician   ·   [Date]", { x: M, y: 6.1, w: 8, h: 0.3, margin: 0, fontFace: BF, fontSize: 12, color: ICE });
  s.addText("Illustrative throughout. Participant-level data runs on-device, zero egress; validated tools own every reported number.", { x: M, y: 6.7, w: 8.4, h: 0.4, margin: 0, fontFace: BF, fontSize: 9, italic: true, color: "8088B0" });
}

// ===== 2. THE PROBLEM =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  titleBlock(s, "WHY THIS EXISTS", "Termination risk hides until the meeting — we want it sooner", TERRA);
  s.addText("Early-phase trials can stop for reasons that build quietly: a participant's safety signal, a cohort's toxicity trend against the stopping rule, or a sponsor cooling on the program. Too often the first formal look is the cohort review or the governance meeting — days or weeks late. The dashboard surfaces all three, continuously.", { x: M + 0.3, y: 1.45, w: W - 2 * M - 0.3, h: 0.9, margin: 0, fontFace: BF, fontSize: 13.5, color: "33384f", lineSpacingMultiple: 1.05 });
  const cards = [
    ["PARTICIPANT", "A dose-limiting toxicity emerging in the DLT window — a Hy's-Law liver signal, QTc prolongation, an AE cluster escalating.", TEAL, TEALBG],
    ["STUDY", "The cohort DLT rate approaching the stopping rule; enrollment or quality limits breached; a futility signal.", AMBER, AMBERBG],
    ["CLIENT / SPONSOR", "Payment aging, communication cooling, scope-reduction change-orders, sponsor pipeline or funding stress.", CLOUDB, CLOUDBG],
  ];
  const cw = (W - 2 * M - 0.6) / 3, cy = 2.7, ch = 3.4;
  cards.forEach((c, i) => {
    const x = M + i * (cw + 0.3);
    s.addShape(pres.shapes.RECTANGLE, { x, y: cy, w: cw, h: ch, fill: { color: c[3] }, line: { color: LINEC, width: 1 }, shadow: shadow() });
    s.addShape(pres.shapes.RECTANGLE, { x, y: cy, w: cw, h: 0.1, fill: { color: c[2] } });
    s.addText(c[0], { x: x + 0.28, y: cy + 0.3, w: cw - 0.5, h: 0.5, margin: 0, fontFace: HF, fontSize: 16, bold: true, color: INK });
    s.addText(c[1], { x: x + 0.28, y: cy + 0.95, w: cw - 0.55, h: ch - 1.2, margin: 0, fontFace: BF, fontSize: 12.5, color: "44496a", valign: "top", lineSpacingMultiple: 1.05 });
  });
  footnote(s, "Three tiers, one screen — so the earliest mover in any of them is visible before the formal review.");
}

// ===== 3. DASHBOARD AT A GLANCE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  titleBlock(s, "THE DASHBOARD", "Three RAG panels and a live early-warning feed", INDIGO);
  const panels = [
    ["PARTICIPANT", "AMBER", TEAL, "On-device · zero egress", [[RED, "S-1042 — candidate Hy's-Law / DILI (DLT window, day 9)"], [AMBER, "S-1039 — ΔQTcF +48 ms"], [AMBER, "Cohort 4 — AE cluster Grade 2→3"]]],
    ["STUDY", "AMBER", AMBER, "Cloud aggregate + on-device drill-down", [[EMER, "Cohort 4 DLT rate 1/6 — within the 3+3 rule"], [AMBER, "Screen-failure 38% vs 25% — KRI breached"], [EMER, "Safety QTL — within tolerance"]]],
    ["CLIENT", "AMBER", CLOUDB, "Cloud · CRM / finance / filings", [[RED, "AR $420K >60 days — payment-aging breach"], [AMBER, "Comms cadence −40% MoM"], [AMBER, "2 scope-reduction change-orders"]]],
  ];
  const pw = (W - 2 * M - 0.5) / 3, py = 1.55, ph = 3.5;
  panels.forEach((p, i) => {
    const x = M + i * (pw + 0.25);
    s.addShape(pres.shapes.RECTANGLE, { x, y: py, w: pw, h: ph, fill: { color: "FFFFFF" }, line: { color: LINEC, width: 1 }, shadow: shadow() });
    s.addShape(pres.shapes.RECTANGLE, { x, y: py, w: pw, h: 0.08, fill: { color: i === 1 ? AMBER : i === 2 ? AMBER : AMBER } });
    s.addShape(pres.shapes.RECTANGLE, { x, y: py, w: pw, h: 0.08, fill: { color: AMBER } });
    dot(s, x + 0.22, py + 0.32, AMBER);
    s.addText(p[0], { x: x + 0.42, y: py + 0.2, w: pw - 1.2, h: 0.4, margin: 0, fontFace: HF, fontSize: 14, bold: true, color: INK });
    s.addText(p[1], { x: x + pw - 1.05, y: py + 0.24, w: 0.9, h: 0.3, margin: 0, fontFace: BF, fontSize: 9, bold: true, color: MUTED, align: "right" });
    let ry = py + 0.78;
    p[4].forEach(r => { dot(s, x + 0.22, ry + 0.04, r[0]); s.addText(r[1], { x: x + 0.42, y: ry - 0.05, w: pw - 0.6, h: 0.62, margin: 0, fontFace: BF, fontSize: 10.5, color: "33384f", valign: "top", lineSpacingMultiple: 0.95 }); ry += 0.74; });
    s.addShape(pres.shapes.RECTANGLE, { x, y: py + ph - 0.46, w: pw, h: 0.46, fill: { color: PANEL } });
    s.addText(p[3], { x: x + 0.22, y: py + ph - 0.44, w: pw - 0.4, h: 0.42, margin: 0, fontFace: BF, fontSize: 9.5, color: MUTED, valign: "middle" });
  });
  s.addText([{ text: "Legend:  ", options: { bold: true, color: MUTED } }, { text: "● termination-level   ", options: { color: RED } }, { text: "● watch / precursor   ", options: { color: AMBER } }, { text: "● within limits", options: { color: EMER } }], { x: M, y: py + ph + 0.18, w: W - 2 * M, h: 0.3, margin: 0, fontFace: BF, fontSize: 11, align: "center" });
  footnote(s, "Illustrative current state. Each panel rolls weighted signals up to a RAG status — not an autonomous verdict.");
}

// ===== 4-6. THE THREE TIERS =====
const tierSlides = [
  { eyebrow: "TIER 1 · PARTICIPANT", title: "Participant-level safety — processed on-device, zero egress", accent: TEAL, bg: TEALBG,
    intro: "The AI flags candidate DLTs and safety patterns early, before the formal cohort review, and pre-assembles the SRC packet. It never adjudicates the DLT.",
    rows: [["Candidate DLTs in the evaluation window", "by design — 3+3 / BOIN / mTPI-2 / CRM; sentinel dosing"], ["Hy's-Law / drug-induced liver injury (eDISH)", "ALT/AST >3×ULN + bili >2×ULN + ALP <2×ULN"], ["QTcF prolongation", ">500 ms, or Δ >60 ms from baseline"], ["PK exposure outliers", "Cmax / AUC beyond the NOAEL-scaled safety margin"], ["AE-cluster & grade escalation; SAE / death", "CTCAE grade trend; expedited-reporting clock"]],
    eng: "Engine: on-device local LLM. Decision: the medical monitor / Safety Review Committee." },
  { eyebrow: "TIER 2 · STUDY", title: "Dose-escalation rules, enrollment, quality — aggregate KRIs", accent: AMBER, bg: AMBERBG,
    intro: "De-identified, aggregate signals run on cloud Claude; any participant-level drill-down stays on-device. These watch the study's trajectory against its own rules.",
    rows: [["Cohort DLT rate vs the stopping / de-escalation rule", "excess toxicity → escalation stop / MTD reached early"], ["Enrollment & screen-failure KRIs", "vs the recruitment plan; feasibility"], ["Safety Quality Tolerance Limits (ICH E6(R3))", "aggregate SAE / AE-rate QTL breaches"], ["Data-quality & central-monitoring signals", "query aging, protocol-deviation trend, site anomalies"], ["Futility & probability of meeting the objective", "interim signals against the plan"]],
    eng: "Engine: cloud Claude (aggregate) + on-device drill-down. Decision: the PM, with the SRC / DSMB on safety." },
  { eyebrow: "TIER 3 · CLIENT / SPONSOR", title: "Commercial early-warning — decision-support for the account team", accent: CLOUDB, bg: CLOUDBG,
    intro: "Non-sensitive business data on cloud Claude. This tier is signal and triage for the account team — never a verdict the system renders about a sponsor.",
    rows: [["Accounts-receivable / payment aging", "invoice disputes; days-past-due breaches"], ["Communication cadence & sentiment", "meeting / email drop; relationship cooling"], ["Scope-reduction & change-order trend", "de-scope often precedes cancellation"], ["Sponsor financial & pipeline health", "runway, layoffs, portfolio re-prioritization, M&A"], ["Competitive readouts & contract / renewal window", "adjacent-program failures; option-exercise signals"]],
    eng: "Engine: cloud Claude (CRM / finance / public filings). Decision: the account / BD lead." },
];
tierSlides.forEach(t => {
  const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  titleBlock(s, t.eyebrow, t.title, t.accent);
  s.addShape(pres.shapes.RECTANGLE, { x: M, y: 1.5, w: W - 2 * M, h: 0.78, fill: { color: t.bg }, line: { color: LINEC, width: 1 } });
  s.addShape(pres.shapes.RECTANGLE, { x: M, y: 1.5, w: 0.1, h: 0.78, fill: { color: t.accent } });
  s.addText(t.intro, { x: M + 0.32, y: 1.5, w: W - 2 * M - 0.55, h: 0.78, margin: 0, fontFace: BF, fontSize: 12, italic: true, color: "3a4060", valign: "middle", lineSpacingMultiple: 1.0 });
  let ry = 2.55, rh = 0.72;
  t.rows.forEach((r, i) => {
    if (i % 2 === 0) s.addShape(pres.shapes.RECTANGLE, { x: M, y: ry, w: W - 2 * M, h: rh, fill: { color: PANEL } });
    dot(s, M + 0.15, ry + 0.28, t.accent);
    s.addText(r[0], { x: M + 0.4, y: ry + 0.04, w: 6.4, h: rh - 0.08, margin: 0, fontFace: BF, fontSize: 13, bold: true, color: INK, valign: "middle" });
    s.addText(r[1], { x: M + 6.9, y: ry + 0.04, w: W - 2 * M - 7.0, h: rh - 0.08, margin: 0, fontFace: BF, fontSize: 12, color: MUTED, valign: "middle" });
    ry += rh;
  });
  s.addShape(pres.shapes.RECTANGLE, { x: M, y: ry + 0.12, w: W - 2 * M, h: 0.56, fill: { color: DARK } });
  s.addText(t.eng, { x: M + 0.3, y: ry + 0.12, w: W - 2 * M - 0.5, h: 0.56, margin: 0, fontFace: BF, fontSize: 12, color: "FFFFFF", valign: "middle" });
});

// ===== 7. HYBRID ROUTING + GOVERNANCE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  titleBlock(s, "ARCHITECTURE & GOVERNANCE", "Sensitivity decides the engine; humans decide the outcome", INDIGO);
  const pw = (W - 2 * M - 0.5) / 2, py = 1.6, ph = 2.6;
  s.addShape(pres.shapes.RECTANGLE, { x: M, y: py, w: pw, h: ph, fill: { color: TEALBG }, line: { color: "C5E2E5", width: 1 }, shadow: shadow() });
  s.addShape(pres.shapes.RECTANGLE, { x: M, y: py, w: pw, h: 0.62, fill: { color: TEAL } });
  s.addText([{ text: "ON-DEVICE LOCAL LLM\n", options: { fontSize: 14, bold: true, color: "FFFFFF" } }, { text: "participant-level safety / PK / unblinded", options: { fontSize: 10.5, color: "DAF0F1" } }], { x: M + 0.3, y: py + 0.08, w: pw - 0.6, h: 0.5, margin: 0, fontFace: BF, lineSpacingMultiple: 0.9 });
  s.addText([{ text: "Zero egress — data never leaves the validated environment.", options: { bullet: { code: "2022", indent: 12 }, breakLine: true, paraSpaceAfter: 7, bold: true } }, { text: "Carries the whole participant tier and any participant-level drill-down.", options: { bullet: { code: "2022", indent: 12 }, breakLine: true, paraSpaceAfter: 7 } }, { text: "Part-11 audited.", options: { bullet: { code: "2022", indent: 12 } } }], { x: M + 0.35, y: py + 0.78, w: pw - 0.7, h: ph - 1.0, margin: 0, fontFace: BF, fontSize: 12, color: TEALINK, lineSpacingMultiple: 1.02 });
  const rx = M + pw + 0.5;
  s.addShape(pres.shapes.RECTANGLE, { x: rx, y: py, w: pw, h: ph, fill: { color: CLOUDBG }, line: { color: "CBDDF0", width: 1 }, shadow: shadow() });
  s.addShape(pres.shapes.RECTANGLE, { x: rx, y: py, w: pw, h: 0.62, fill: { color: CLOUDB } });
  s.addText([{ text: "M365 COPILOT (CLOUD)\n", options: { fontSize: 14, bold: true, color: "FFFFFF" } }, { text: "non-sensitive ops & commercial", options: { fontSize: 10.5, color: "DCE8F6" } }], { x: rx + 0.3, y: py + 0.08, w: pw - 0.6, h: 0.5, margin: 0, fontFace: BF, lineSpacingMultiple: 0.9 });
  s.addText([{ text: "De-identified, aggregate study KRIs and the client / commercial tier.", options: { bullet: { code: "2022", indent: 12 }, breakLine: true, paraSpaceAfter: 7, bold: true } }, { text: "Under BAA; no PHI or unblinded data.", options: { bullet: { code: "2022", indent: 12 }, breakLine: true, paraSpaceAfter: 7 } }, { text: "Where it can't reach, the local model does.", options: { bullet: { code: "2022", indent: 12 } } }], { x: rx + 0.35, y: py + 0.78, w: pw - 0.7, h: ph - 1.0, margin: 0, fontFace: BF, fontSize: 12, color: CLOUDINK, lineSpacingMultiple: 1.02 });
  s.addShape(pres.shapes.RECTANGLE, { x: M, y: py + ph + 0.25, w: W - 2 * M, h: 1.85, fill: { color: DARK } });
  s.addShape(pres.shapes.RECTANGLE, { x: M, y: py + ph + 0.25, w: 0.12, h: 1.85, fill: { color: AMBER } });
  s.addText("The rule that governs everything", { x: M + 0.35, y: py + ph + 0.4, w: W - 2 * M - 0.6, h: 0.4, margin: 0, fontFace: HF, fontSize: 16, bold: true, color: "FFFFFF" });
  s.addText([{ text: "The AI flags, aggregates, triages, and drafts the alert — it never makes the safety or termination call. ", options: { bold: true, color: "FFFFFF" } }, { text: "The medical monitor / SRC / DSMB make every DLT and safety determination; the PM owns the study; the account lead owns the client signal. Reported safety numbers come from the validated safety database, the cohort DLT-rate from the validated dose-escalation tool — never the LLM. Every flag triggers a human review and a logged disposition; nothing is paused or terminated by the system itself.", options: { color: ICE } }], { x: M + 0.35, y: py + ph + 0.82, w: W - 2 * M - 0.7, h: 1.2, margin: 0, fontFace: BF, fontSize: 12.5, valign: "top", lineSpacingMultiple: 1.04 });
  footnote(s, "Same routing principle as the rest of the hybrid AI program — pointed at early-termination risk.");
}

// ===== 8. THE ADVANCED ENGINE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  titleBlock(s, "ADVANCED ENGINE", "A continuous, anticipatory layer on top of the rules", VIOLET);
  s.addText([{ text: "Optional, and decision-support only", options: { bold: true, color: VIOLETINK } }, { text: " — it surfaces risk earlier and continuously, but the threshold rules stay authoritative and it is validated before any regulated use.", options: { color: MUTED } }], { x: M + 0.3, y: 1.42, w: W - 2 * M - 0.3, h: 0.4, margin: 0, fontFace: BF, fontSize: 12.5 });
  const cards = [
    ["OPTIMAL TRANSPORT", "Wasserstein drift", VIOLET, VIOLETBG, "How far has a distribution drifted from a pooled reference? Wasserstein distance respects clinical severity — it sees mass move toward the dangerous tail where a single threshold is silent — and points to which analyte is driving it."],
    ["ACTIVE INFERENCE", "free energy + EFE", TEAL, TEALBG, "Treat the monitor as a model of the expected trajectory. Rising surprise (free energy) is an early warning; Expected Free Energy picks the most informative next assessment — say, an unscheduled liver panel — and recommends it for approval."],
    ["NESTED + META", "one deep hierarchy", INDIGO, INDBG, "Participant, study, and client are one model: priors flow down, risk flows up, and the priors are pooled across studies. A participant signal propagates to study and program risk — not three siloed dashboards."],
  ];
  const cw = (W - 2 * M - 0.6) / 3, cy = 2.0, ch = 3.4;
  cards.forEach((c, i) => {
    const x = M + i * (cw + 0.3);
    s.addShape(pres.shapes.RECTANGLE, { x, y: cy, w: cw, h: ch, fill: { color: "FFFFFF" }, line: { color: LINEC, width: 1 }, shadow: shadow() });
    s.addShape(pres.shapes.RECTANGLE, { x, y: cy, w: cw, h: 0.66, fill: { color: c[2] } });
    s.addText([{ text: c[0] + "\n", options: { fontSize: 12.5, bold: true, color: "FFFFFF" } }, { text: c[1], options: { fontSize: 10, italic: true, color: "EEEBFB" } }], { x: x + 0.22, y: cy + 0.08, w: cw - 0.4, h: 0.5, margin: 0, fontFace: BF, lineSpacingMultiple: 0.9 });
    s.addText(c[4], { x: x + 0.26, y: cy + 0.84, w: cw - 0.5, h: ch - 1.0, margin: 0, fontFace: BF, fontSize: 11.5, color: "3a4060", valign: "top", lineSpacingMultiple: 1.05 });
  });
  s.addShape(pres.shapes.RECTANGLE, { x: M, y: cy + ch + 0.18, w: W - 2 * M, h: 0.5, fill: { color: VIOLETBG }, line: { color: "DCD3F4", width: 1 } });
  s.addText([{ text: "What it buys over thresholds alone:  ", options: { bold: true, color: VIOLETINK } }, { text: "earlier · geometry- & tail-aware · anticipatory · coherent across tiers. Methods independently math-checked.", options: { color: "4a4666" } }], { x: M + 0.3, y: cy + ch + 0.18, w: W - 2 * M - 0.5, h: 0.5, margin: 0, fontFace: BF, fontSize: 12, valign: "middle" });
  footnote(s, "Full detail in the participant-tier implementation spec; this layer is opt-in and never overrides a rule or a human.");
}

// ===== 9. WORKED EXAMPLE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  titleBlock(s, "WORKED EXAMPLE", "A DLT early-warning fires — day 9, not day 21", TERRA);
  const steps = [
    ["Day 9, cohort 4", "Participant S-1042's central-lab feed posts ALT 3.4×ULN, total bilirubin 2.1×ULN, ALP 1.3×ULN. The on-device model evaluates the eDISH logic, recognizes a Hy's-Law pattern, and — inside the DLT window — flags a candidate DLT. Nothing left the device.", TERRA],
    ["Within minutes", "It pre-assembles the case: the LFT trajectory, the eDISH context, dose & exposure, concomitant meds, and the running cohort DLT tally against the 3+3 rule. It drafts the alert and routes it to the medical monitor and SRC chair — ahead of the scheduled review — with a Part-11 audit entry.", AMBER],
    ["The humans decide", "The medical monitor orders a confirmatory repeat panel; the SRC convenes. Per protocol, further dosing pauses pending adjudication. The validated safety database holds the authoritative numbers; the SRC makes the DLT call.", CLOUDB],
    ["The payoff", "The signal surfaced on day 9, not at the cohort meeting on day 21 — SRC packet already built, data never leaving the device, and a human making every call.", EMER],
  ];
  let y = 1.65, h = 1.18;
  steps.forEach((st, i) => {
    s.addShape(pres.shapes.RECTANGLE, { x: M, y, w: W - 2 * M, h: h - 0.12, fill: { color: PANEL }, line: { color: LINEC, width: 1 } });
    s.addShape(pres.shapes.RECTANGLE, { x: M, y, w: 0.1, h: h - 0.12, fill: { color: st[2] } });
    s.addText(st[0], { x: M + 0.32, y: y + 0.1, w: 2.5, h: h - 0.32, margin: 0, fontFace: HF, fontSize: 14, bold: true, color: st[2], valign: "top" });
    s.addText(st[1], { x: M + 3.0, y: y + 0.08, w: W - 2 * M - 3.2, h: h - 0.24, margin: 0, fontFace: BF, fontSize: 11.5, color: "33384f", valign: "middle", lineSpacingMultiple: 1.0 });
    y += h;
  });
  footnote(s, "Illustrative. The dashboard's Participant panel goes red, the Study panel flags the cohort, and a cross-study check runs for the same compound.");
}

// ===== 10. STANDING IT UP =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  titleBlock(s, "STANDING IT UP", "Safe wins first, then the on-device tier, then scoring & audit", EMER);
  const ph = [
    ["1", "The safe wins — cloud", EMER, ["Wire the Study & Client tiers: enrollment / KRI / QTL feeds and the finance-AR / CRM / sponsor-comms signals into cloud Claude.", "Build the Study and Client RAG panels behind a human-review queue. De-identified / non-sensitive only."]],
    ["2", "The on-device participant tier", TEAL, ["Stand up the local LLM in the validated environment; connect safety DB / central-lab / ECG; encode the DLT, Hy's-Law/eDISH, QTcF and PK-exposure logic.", "Route every participant-level signal on-device, zero egress; wire alerting to the medical monitor / SRC and the disposition log."]],
    ["3", "Scoring, escalation & audit", INDIGO, ["The weighted roll-up to tier RAG, the escalation routing, the Part-11 audit trail and human-acknowledgement, the cross-study safety view.", "Optionally layer in the advanced engine — validated and frozen before it informs any regulated decision."]],
  ];
  let y = 1.7, h = 1.55;
  ph.forEach(p => {
    s.addShape(pres.shapes.RECTANGLE, { x: M, y, w: W - 2 * M, h: h - 0.15, fill: { color: "FFFFFF" }, line: { color: LINEC, width: 1 }, shadow: shadow() });
    s.addShape(pres.shapes.OVAL, { x: M + 0.25, y: y + 0.4, w: 0.66, h: 0.66, fill: { color: p[2] } });
    s.addText(p[0], { x: M + 0.25, y: y + 0.4, w: 0.66, h: 0.66, margin: 0, fontFace: HF, fontSize: 22, bold: true, color: "FFFFFF", align: "center", valign: "middle" });
    s.addText(p[1], { x: M + 1.15, y: y + 0.14, w: W - 2 * M - 1.4, h: 0.4, margin: 0, fontFace: HF, fontSize: 16, bold: true, color: INK });
    s.addText(p[3].map(b => ({ text: b, options: { bullet: { code: "2022", indent: 10 }, breakLine: true, paraSpaceAfter: 4 } })), { x: M + 1.15, y: y + 0.58, w: W - 2 * M - 1.45, h: h - 0.8, margin: 0, fontFace: BF, fontSize: 11.5, color: "3a4060", valign: "top", lineSpacingMultiple: 1.0 });
    y += h;
  });
  footnote(s, "Each phase delivers value on its own; the participant tier is the one that needs the on-prem environment.");
}

// ===== 11. CLOSE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: DARK };
  chip(s, M, 0.6, VIOLET);
  s.addText("IN ONE LINE", { x: M + 0.3, y: 0.55, w: 10, h: 0.3, margin: 0, fontFace: BF, fontSize: 11, bold: true, charSpacing: 2, color: ICE });
  s.addText("Catch termination risk before the meeting —\nand let humans make every call.", { x: M, y: 1.15, w: W - 2 * M, h: 1.5, margin: 0, fontFace: HF, fontSize: 27, bold: true, color: "FFFFFF", lineSpacingMultiple: 1.0 });
  const buys = [
    ["Earlier", "Drift and surprise rise before a line is crossed; a Hy's-Law signal on day 9, not day 21."],
    ["Three tiers, one screen", "Participant safety, study stopping-rules, and client/commercial — the earliest mover is visible."],
    ["Governed by design", "On-device for sensitive data; validated tools own the numbers; the SRC / DSMB / PM decide."],
    ["Fits the program", "A Phase-1 green-pilot deliverable on the same hybrid stack — no new principle, new target."],
  ];
  const cw = (W - 2 * M - 0.5) / 2, cy = 3.1, ch = 1.5;
  buys.forEach((b, i) => {
    const x = M + (i % 2) * (cw + 0.5), y = cy + Math.floor(i / 2) * (ch + 0.3);
    s.addShape(pres.shapes.RECTANGLE, { x, y, w: cw, h: ch, fill: { color: "1E2350" }, line: { color: "343A6E", width: 1 } });
    s.addShape(pres.shapes.RECTANGLE, { x, y, w: 0.09, h: ch, fill: { color: VIOLET } });
    s.addText(b[0], { x: x + 0.3, y: y + 0.18, w: cw - 0.5, h: 0.4, margin: 0, fontFace: HF, fontSize: 16, bold: true, color: "FFFFFF" });
    s.addText(b[1], { x: x + 0.3, y: y + 0.66, w: cw - 0.55, h: ch - 0.78, margin: 0, fontFace: BF, fontSize: 12, color: ICE, valign: "top", lineSpacingMultiple: 1.02 });
  });
  s.addText("The AI flags; the SRC / DSMB / medical monitor, the PM, and the account lead decide.  ·  Illustrative throughout.", { x: M, y: H - 0.55, w: W - 2 * M, h: 0.35, margin: 0, fontFace: BF, fontSize: 11, italic: true, color: "8088B0", align: "center" });
}

pres.writeFile({ fileName: __dirname + "/Risk_EarlyWarning_Walkthrough.pptx" }).then(f => console.log("WROTE", f, "(" + S.length + " slides)"));
