// One-slide "Advanced Engine" explainer for the manager deck — drop-in (pptx + pdf).
// Optimal Transport (Wasserstein) + nested Active Inference, on top of the threshold rules. Governance-first.
const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";
pres.author = "Lead Biostatistician";
pres.title = "Trial-Risk Early-Warning — Advanced Engine";

const DARK = "15183A", INK = "1A1E33", MUTED = "5A607E", ICE = "D5DAF5", PANEL = "F4F5FB", LINEC = "E0E3F1";
const INDIGO = "4338CA", INDIGOINK = "312C8A", VIOLET = "6D28D9", VIOLETBG = "F2F1FB", VIOLETINK = "4A2293";
const TEAL = "0E7C86", TEALBG = "E2F1F2", TEALINK = "0A4F57";
const INDBG = "ECECFB", AMBER = "C2891C", TERRA = "B5564B";
const HF = "Georgia", BF = "Calibri";
const W = 13.3, H = 7.5, M = 0.7;
const shadow = () => ({ type: "outer", color: "1A1E33", blur: 9, offset: 3, angle: 135, opacity: 0.12 });

const s = pres.addSlide();
s.background = { color: "FFFFFF" };

// title block
s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: M, y: 0.5, w: 0.16, h: 0.34, fill: { color: VIOLET }, rectRadius: 0.04 });
s.addText("TRIAL-RISK EARLY-WARNING  ·  ADVANCED ENGINE", { x: M + 0.3, y: 0.45, w: W - 2 * M, h: 0.3, margin: 0, fontFace: BF, fontSize: 11, bold: true, charSpacing: 2, color: MUTED });
s.addText("Optimal Transport + nested Active Inference", { x: M + 0.3, y: 0.73, w: W - 2 * M, h: 0.6, margin: 0, fontFace: HF, fontSize: 27, bold: true, color: INK });
s.addText([
  { text: "A continuous, anticipatory layer ", options: { bold: true, color: INK } },
  { text: "on top of the threshold rules — it surfaces risk ", options: { color: MUTED } },
  { text: "earlier", options: { bold: true, color: VIOLETINK } },
  { text: ", is ", options: { color: MUTED } },
  { text: "geometry- & tail-aware", options: { bold: true, color: VIOLETINK } },
  { text: ", and ", options: { color: MUTED } },
  { text: "tells you what to check next", options: { bold: true, color: VIOLETINK } },
  { text: ".", options: { color: MUTED } },
], { x: M + 0.3, y: 1.42, w: W - 2 * M - 0.3, h: 0.4, margin: 0, fontFace: BF, fontSize: 13.5 });

// three panels
const pw = (W - 2 * M - 0.6) / 3, py = 2.05, ph = 3.0;
const panels = [
  { x: M, accent: VIOLET, bg: VIOLETBG, ink: VIOLETINK, brd: "DCD3F4",
    tag: "OPTIMAL TRANSPORT", sub: "Wasserstein drift",
    body: [
      ["How far has the distribution drifted", " from a pooled reference?"],
      ["Wasserstein distance respects clinical severity", " — it sees mass move toward the dangerous tail (Hy's-Law territory) where a mean or a single threshold is silent."],
      ["Flags drift before a line is crossed", " — and the transport map says which analyte/grade is driving it."],
    ] },
  { x: M + pw + 0.3, accent: TEAL, bg: TEALBG, ink: TEALINK, brd: "C5E2E5",
    tag: "ACTIVE INFERENCE", sub: "free energy + EFE",
    body: [
      ["A model of each participant's expected trajectory.", ""],
      ["Surprise (free energy) rising = early warning", " — the participant is doing something the model didn't expect, before a frank event."],
      ["Expected Free Energy picks the most informative next assessment", " — e.g. an unscheduled LFT — and recommends it for approval."],
    ] },
  { x: M + 2 * (pw + 0.3), accent: INDIGO, bg: INDBG, ink: INDIGOINK, brd: "CFCFF4",
    tag: "NESTED + META", sub: "one deep hierarchy",
    body: [
      ["Participant → study → client as one model", " — priors flow down, prediction-errors (risk) flow up."],
      ["Priors are pooled across studies", " (a Wasserstein barycenter of prior cohorts) — a new study starts population-informed."],
      ["A participant signal propagates to study & program risk", " — not three siloed dashboards."],
    ] },
];
panels.forEach(p => {
  s.addShape(pres.shapes.RECTANGLE, { x: p.x, y: py, w: pw, h: ph, fill: { color: "FFFFFF" }, line: { color: p.brd, width: 1 }, shadow: shadow() });
  s.addShape(pres.shapes.RECTANGLE, { x: p.x, y: py, w: pw, h: 0.62, fill: { color: p.accent } });
  s.addText([{ text: p.tag + "\n", options: { fontSize: 12.5, bold: true, color: "FFFFFF" } }, { text: p.sub, options: { fontSize: 10, italic: true, color: "EBEBF7" } }], { x: p.x + 0.22, y: py + 0.07, w: pw - 0.4, h: 0.5, margin: 0, fontFace: BF, lineSpacingMultiple: 0.92 });
  const runs = [];
  p.body.forEach((b, i) => {
    runs.push({ text: b[0], options: { bold: true, color: p.ink, bullet: { code: "2022", indent: 12 }, breakLine: b[1] ? false : true, paraSpaceAfter: b[1] ? 0 : 8 } });
    if (b[1]) runs.push({ text: b[1], options: { color: MUTED, breakLine: true, paraSpaceAfter: 8 } });
  });
  s.addText(runs, { x: p.x + 0.26, y: py + 0.78, w: pw - 0.5, h: ph - 0.95, margin: 0, fontFace: BF, fontSize: 10.5, lineSpacingMultiple: 1.0, valign: "top" });
});

// "what it buys" strip
const chips = ["Earlier", "Geometry- & tail-aware", "Anticipatory", "Coherent across tiers"];
let cx = M;
const cy = py + ph + 0.22;
s.addText("WHAT IT BUYS OVER THRESHOLDS ALONE", { x: M, y: cy - 0.02, w: 3.6, h: 0.3, margin: 0, fontFace: BF, fontSize: 9.5, bold: true, charSpacing: 1, color: MUTED, valign: "middle" });
cx = M + 3.5;
chips.forEach(c => {
  const cw = 0.34 + c.length * 0.082;
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: cx, y: cy - 0.04, w: cw, h: 0.34, fill: { color: VIOLETBG }, line: { color: "DCD3F4", width: 1 }, rectRadius: 0.06 });
  s.addText(c, { x: cx, y: cy - 0.04, w: cw, h: 0.34, margin: 0, fontFace: BF, fontSize: 10.5, bold: true, color: VIOLETINK, align: "center", valign: "middle" });
  cx += cw + 0.18;
});

// governance band
const gy = cy + 0.52;
s.addShape(pres.shapes.RECTANGLE, { x: M, y: gy, w: W - 2 * M, h: 0.92, fill: { color: DARK } });
s.addShape(pres.shapes.RECTANGLE, { x: M, y: gy, w: 0.1, h: 0.92, fill: { color: AMBER } });
s.addText([
  { text: "Decision-support, advanced / advanced.  ", options: { bold: true, color: "FFFFFF" } },
  { text: "Validated & frozen before any regulated use. The rule-based DLT / Hy's-Law / QTcF / QTL triggers stay authoritative; validated tools own every number; the SRC / DSMB / medical monitor decide. EFE only recommends ", options: { color: ICE } },
  { text: "what to observe", options: { italic: true, bold: true, color: "FFFFFF" } },
  { text: " — for human approval, never an autonomous clinical or dosing action.", options: { color: ICE } },
], { x: M + 0.32, y: gy, w: W - 2 * M - 0.55, h: 0.92, margin: 0, fontFace: BF, fontSize: 11.5, valign: "middle", lineSpacingMultiple: 1.0 });

s.addText("Companion to the Trial-Termination Early-Warning Dashboard and the Participant-Tier Advanced-Engine implementation spec.  ·  Methods (OT + active inference) independently math-checked.  ·  Illustrative.", { x: M, y: H - 0.42, w: W - 2 * M, h: 0.3, margin: 0, fontFace: BF, fontSize: 8.5, italic: true, color: "9197B5" });

pres.writeFile({ fileName: __dirname + "/Advanced_Engine_Manager_Slide.pptx" }).then(f => console.log("WROTE", f));
