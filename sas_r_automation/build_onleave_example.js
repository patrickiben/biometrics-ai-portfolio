// "Coverage while on leave" — worked-example deck for the SAS/R-only monitoring companion (Study CP-101).
// Mockup screens of the deterministic scheduler→checks→report→alert loop over a one-month leave.
// Renders to PNG (video frames) + PDF (step-by-step picture guide).
const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";
pres.author = "Lead Biostatistician";
pres.title = "Coverage while on leave — SAS/R trial monitoring (CP-101)";

const DARK = "15183A", INK = "1A1E33", MUTED = "5A607E", ICE = "D5DAF5", PANEL = "F4F5FB", LINE = "DDE1EE", SUBTLE = "F7F8FC";
const INDIGO = "4338CA", INDIGOINK = "312C8A", INDBG = "ECECFB";
const SASB = "1A4FA0", SASBG = "E7EEF8", TERM = "12152E", SP = "037B7B", TEAMS = "5059C9";
const GREEN = "1F9D55", GREENBG = "E6F6EC", AMBER = "C2891C", AMBERBG = "FBF1D8", RED = "C0392B", REDBG = "FBECEA";
const HF = "Georgia", BF = "Calibri", MONO = "Consolas";
const W = 13.3, H = 7.5;
const R = pres.shapes.RECTANGLE, RR = pres.shapes.ROUNDED_RECTANGLE, OV = pres.shapes.OVAL;
const shadow = () => ({ type: "outer", color: "1A1E33", blur: 8, offset: 2, angle: 90, opacity: 0.10 });
const S = [];

function header(s, step, title, accent) {
  s.addShape(RR, { x: 0.5, y: 0.32, w: 0.16, h: 0.34, fill: { color: accent }, rectRadius: 0.04 });
  s.addText(step, { x: 0.78, y: 0.28, w: 11.5, h: 0.3, margin: 0, fontFace: BF, fontSize: 11, bold: true, charSpacing: 2, color: MUTED });
  s.addText(title, { x: 0.78, y: 0.55, w: 12.0, h: 0.5, margin: 0, fontFace: HF, fontSize: 22, bold: true, color: INK });
}
function win(s, x, y, w, h, app, barC) {
  s.addShape(R, { x, y, w, h, fill: { color: "FFFFFF" }, line: { color: LINE, width: 1 }, shadow: shadow() });
  s.addShape(R, { x, y, w, h: 0.4, fill: { color: barC } });
  for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) s.addShape(OV, { x: x + 0.16 + c * 0.07, y: y + 0.12 + r * 0.07, w: 0.035, h: 0.035, fill: { color: "FFFFFF" } });
  s.addText(app, { x: x + 0.5, y, w: w - 1, h: 0.4, margin: 0, fontFace: BF, fontSize: 11, bold: true, color: "FFFFFF", valign: "middle" });
}
function callout(s, n, text, accent) {
  s.addShape(R, { x: 0.5, y: 6.82, w: 12.3, h: 0.5, fill: { color: INDBG } });
  s.addShape(OV, { x: 0.66, y: 6.9, w: 0.34, h: 0.34, fill: { color: accent } });
  s.addText(String(n), { x: 0.66, y: 6.9, w: 0.34, h: 0.34, margin: 0, fontFace: HF, fontSize: 15, bold: true, color: "FFFFFF", align: "center", valign: "middle" });
  s.addText(text, { x: 1.16, y: 6.82, w: 11.5, h: 0.5, margin: 0, fontFace: BF, fontSize: 13, bold: true, color: INDIGOINK, valign: "middle" });
}
const pill = (s, x, y, t, fg, bg, w) => { const ww = w || (0.2 + t.length * 0.075); s.addShape(RR, { x, y, w: ww, h: 0.28, fill: { color: bg }, rectRadius: 0.05 }); s.addText(t, { x, y, w: ww, h: 0.28, margin: 0, fontFace: BF, fontSize: 9.5, bold: true, color: fg, align: "center", valign: "middle" }); return ww; };
const statusDot = (s, x, y, c) => { s.addShape(OV, { x, y, w: 0.16, h: 0.16, fill: { color: c } }); };

// ===== 1 · TITLE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: DARK };
  s.addShape(R, { x: 9.5, y: 0, w: 3.8, h: H, fill: { color: "1B1F47" } });
  s.addShape(R, { x: 9.5, y: 0, w: 0.08, h: H, fill: { color: SASB } });
  const loop = [["Scheduler", "02:00 · 06:00 · 07:00 · Fri"], ["SAS / R program", "deterministic checks"], ["Report", "ODS / R Markdown"], ["Notify", "digest + urgent alert"]];
  let ly = 1.45;
  loop.forEach((l, i) => { s.addShape(RR, { x: 9.95, y: ly, w: 2.95, h: 0.74, fill: { color: "262a55" }, line: { color: "3a3e72", width: 1 }, rectRadius: 0.06 }); s.addText([{ text: l[0] + "\n", options: { fontSize: 12.5, bold: true, color: "FFFFFF" } }, { text: l[1], options: { fontSize: 9.5, color: "AEB4E0" } }], { x: 10.1, y: ly + 0.06, w: 2.7, h: 0.62, margin: 0, fontFace: BF, lineSpacingMultiple: 0.92 }); if (i < 3) s.addText("↓", { x: 11.2, y: ly + 0.74, w: 0.4, h: 0.2, margin: 0, fontFace: BF, fontSize: 12, bold: true, color: SASB, align: "center" }); ly += 0.92; });
  s.addText("COVERAGE WHILE ON LEAVE · STUDY CP-101", { x: 0.7, y: 1.5, w: 8.5, h: 0.3, margin: 0, fontFace: BF, fontSize: 12, bold: true, charSpacing: 2, color: ICE });
  s.addText("A month of trial monitoring —\nautomated, in SAS and R", { x: 0.7, y: 1.95, w: 8.6, h: 1.8, margin: 0, fontFace: HF, fontSize: 34, bold: true, color: "FFFFFF", lineSpacingMultiple: 1.0 });
  s.addText("The lead biostatistician is in Europe for a month. Monitoring keeps running on validated, deterministic SAS/R inside the existing environment — the covering colleague gets the right updates, escalation is automatic, and the manager gets peace of mind. No AI, no new tools, no PHI egress.", { x: 0.7, y: 3.95, w: 8.4, h: 1.3, margin: 0, fontFace: BF, fontSize: 14, color: ICE, lineSpacingMultiple: 1.05 });
  s.addShape(pres.shapes.LINE, { x: 0.7, y: 5.7, w: 3.5, h: 0, line: { color: "3A3E72", width: 1 } });
  s.addText("The third companion pipeline — the one you can ship today.  ·  Illustrative mockups.", { x: 0.7, y: 5.85, w: 8.4, h: 0.5, margin: 0, fontFace: BF, fontSize: 12, italic: true, color: "8088B0" });
}

// ===== 2 · PRE-DEPARTURE SETUP =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  header(s, "BEAT 0 · BEFORE LEAVING", "Schedule the already-validated programs, hand over the runbook", SASB);
  // left: scheduled jobs (terminal-ish)
  win(s, 0.5, 1.3, 7.1, 5.4, "Scheduled jobs — service account SVC-BIOSTAT (not a personal login)", TERM);
  const jobs = [
    ["02:00 daily", "Data refresh + integrity & FRESHNESS gate", "ingest latest SDTM/safety/IXRS; verify feeds updated"],
    ["06:00 daily", "Safety scan", "AE/SAE · Hy's-Law/eDISH · QTcF · labs · DLT tally"],
    ["07:00 daily", "Routine digest → support", "GREEN/AMBER summary + heartbeat"],
    ["Fri 16:00", "Weekly status + exec one-pager", "→ support (full) · → manager (1 page)"],
    ["on-event", "Threshold ALERT", "KRI/QTL/DLT/SAE → urgent email + escalation"],
  ];
  let jy = 1.85;
  jobs.forEach(j => {
    s.addShape(R, { x: 0.7, y: jy, w: 6.7, h: 0.92, fill: { color: "1a1e40" }, line: { color: "2c3160", width: 1 } });
    pill(s, 0.85, jy + 0.12, j[0], "BFE0FF", "23306a", 1.4);
    s.addText(j[1], { x: 2.35, y: jy + 0.08, w: 4.9, h: 0.3, margin: 0, fontFace: MONO, fontSize: 11.5, bold: true, color: "E6E8FF", valign: "middle" });
    s.addText(j[2], { x: 2.35, y: jy + 0.4, w: 4.9, h: 0.45, margin: 0, fontFace: MONO, fontSize: 9.5, color: "9aa0d8", valign: "top", lineSpacingMultiple: 0.95 });
    jy += 0.99;
  });
  // right: runbook card
  win(s, 7.85, 1.3, 4.95, 5.4, "Coverage runbook (PDF) — to support, cc manager", SP);
  s.addText("CP-101 — Monitoring coverage", { x: 8.05, y: 1.85, w: 4.6, h: 0.3, margin: 0, fontFace: HF, fontSize: 14, bold: true, color: INK });
  const rb = [
    [GREEN, "GREEN", "all checks within limits — no action"],
    [AMBER, "AMBER", "an operational/quality KRI crossed — support reviews & acts"],
    [RED, "RED", "safety threshold (DLT/SAE/Hy's-Law/QTcF) — ack ≤30 min, CONTACT MEDICAL MONITOR"],
  ];
  let ry = 2.3;
  rb.forEach(r => { statusDot(s, 8.05, ry + 0.05, r[0]); s.addText([{ text: r[1] + "  ", options: { bold: true, color: r[0] } }, { text: r[2], options: { color: "33384f" } }], { x: 8.3, y: ry - 0.04, w: 4.35, h: 0.7, margin: 0, fontFace: BF, fontSize: 11, valign: "top", lineSpacingMultiple: 1.0 }); ry += (r[2].length > 45 ? 0.82 : 0.6); });
  s.addShape(pres.shapes.LINE, { x: 8.05, y: ry + 0.05, w: 4.6, h: 0, line: { color: LINE, width: 1 } });
  s.addText([
    { text: "Recipients  ", options: { bold: true, color: MUTED } }, { text: "primary + BACKUP colleague + role alias (never one person)\n", options: { color: "33384f" } },
    { text: "Escalation  ", options: { bold: true, color: MUTED } }, { text: "Medical Monitor: Dr. R. Okafor · +1-…\n", options: { color: "33384f" } },
    { text: "Honest note  ", options: { bold: true, color: MUTED } }, { text: "a flag = a number crossed a line; it is NOT an interpretation. Humans decide.", options: { italic: true, color: "6E3A33" } },
  ], { x: 8.05, y: ry + 0.18, w: 4.6, h: 2.0, margin: 0, fontFace: BF, fontSize: 10.5, valign: "top", lineSpacingMultiple: 1.05 });
  callout(s, 0, "Nothing here is new code — the lead’s normal monitoring programs are simply moved from “run when I remember” to “run on a clock,” under a service account that outlasts the lead’s login.", SASB);
}

// ===== 3 · WEEK 1 GREEN + HEARTBEAT =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  header(s, "WEEK 1 · QUIET BASELINE", "The daily digest — GREEN — and the heartbeat that proves it ran", GREEN);
  win(s, 1.2, 1.3, 8.6, 5.4, "Outlook — Daily Safety Digest", GREEN);
  s.addText("Daily Safety Digest — CP-101 — Tue 09 Jun", { x: 1.55, y: 1.85, w: 7.9, h: 0.4, margin: 0, fontFace: HF, fontSize: 15, bold: true, color: INK });
  pill(s, 7.9, 1.9, "● GREEN", "0B5C42", GREENBG, 1.4);
  s.addText("to: Support (covering biostatistician) · auto-sent 07:00", { x: 1.55, y: 2.25, w: 7.9, h: 0.3, margin: 0, fontFace: BF, fontSize: 10.5, italic: true, color: MUTED });
  s.addShape(pres.shapes.LINE, { x: 1.55, y: 2.62, w: 7.9, h: 0, line: { color: LINE, width: 1 } });
  const rows = [
    ["Enrolled / dosed", "24 / 24 across cohorts 1–4 · cohort 5 screening", GREEN],
    ["New AEs / SAEs since last run", "3 AE (all Grade 1) · 0 SAE", GREEN],
    ["Hy's-Law / eDISH · QTcF", "0 flags · 0 flags", GREEN],
    ["Labs / vitals out of range", "0 clinically-notable", GREEN],
    ["Cohort DLT tally", "cohort 4: 0/6 — within 3+3", GREEN],
    ["Open queries / overdue visits", "11 open (none >30 d) · 0 overdue", GREEN],
  ];
  let ry = 2.78;
  rows.forEach((r, i) => { if (i % 2) s.addShape(R, { x: 1.4, y: ry, w: 8.25, h: 0.46, fill: { color: SUBTLE } }); statusDot(s, 1.55, ry + 0.15, r[2]); s.addText(r[0], { x: 1.8, y: ry, w: 3.3, h: 0.46, margin: 0, fontFace: BF, fontSize: 11.5, bold: true, color: INK, valign: "middle" }); s.addText(r[1], { x: 5.1, y: ry, w: 4.4, h: 0.46, margin: 0, fontFace: BF, fontSize: 11, color: "33384f", valign: "middle" }); ry += 0.46; });
  s.addShape(R, { x: 1.4, y: ry + 0.12, w: 8.25, h: 0.62, fill: { color: "0f1130" } });
  s.addText("✓ HEARTBEAT  ran 07:00:04 · data fresh to 06:14 today · 28,114 records · SYSCC=0 · next run 10 Jun 07:00", { x: 1.6, y: ry + 0.12, w: 7.9, h: 0.62, margin: 0, fontFace: MONO, fontSize: 10.5, bold: true, color: "8FE3B0", valign: "middle" });
  callout(s, 1, "“No news” is never assumed: every run emits a heartbeat with a data-freshness timestamp — so a missed job or a frozen feed announces itself instead of hiding behind a green screen.", GREEN);
}

// ===== 4 · WEEK 2 AMBER =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  header(s, "WEEK 2 · TUE 07:00", "An enrollment KRI dips — AMBER, in the routine channel", AMBER);
  win(s, 1.2, 1.3, 8.6, 5.4, "Outlook — Daily Safety Digest", AMBER);
  s.addText("Daily Safety Digest — CP-101 — Tue 16 Jun", { x: 1.55, y: 1.85, w: 7.9, h: 0.4, margin: 0, fontFace: HF, fontSize: 15, bold: true, color: INK });
  pill(s, 7.9, 1.9, "● AMBER", "6B4E12", AMBERBG, 1.4);
  s.addText("to: Support · auto-sent 07:00", { x: 1.55, y: 2.25, w: 7.9, h: 0.3, margin: 0, fontFace: BF, fontSize: 10.5, italic: true, color: MUTED });
  s.addShape(pres.shapes.LINE, { x: 1.55, y: 2.62, w: 7.9, h: 0, line: { color: LINE, width: 1 } });
  // the amber row, highlighted
  s.addShape(R, { x: 1.4, y: 2.78, w: 8.25, h: 0.92, fill: { color: AMBERBG }, line: { color: AMBER, width: 1.5 } });
  statusDot(s, 1.6, 3.0, AMBER);
  s.addText([{ text: "Enrollment vs plan — KRI BREACHED\n", options: { bold: true, color: "6B4E12", fontSize: 12.5 } }, { text: "76% of planned-to-date (KRI floor 80%) · screen-failure cluster at Site 02 (5 of last 7) · cohort-5 fill at risk", options: { color: "5a4510", fontSize: 11 } }], { x: 1.85, y: 2.85, w: 7.6, h: 0.8, margin: 0, fontFace: BF, valign: "top", lineSpacingMultiple: 1.04 });
  const rows = [["Safety (AE/SAE · Hy's-Law · QTcF · DLT)", "all within limits", GREEN], ["Labs / vitals", "0 notable", GREEN], ["Queries / deviations", "14 open · deviation trend flat", GREEN]];
  let ry = 3.9;
  rows.forEach(r => { statusDot(s, 1.6, ry + 0.13, r[2]); s.addText(r[0], { x: 1.85, y: ry, w: 4.7, h: 0.42, margin: 0, fontFace: BF, fontSize: 11, bold: true, color: INK, valign: "middle" }); s.addText(r[1], { x: 6.6, y: ry, w: 2.9, h: 0.42, margin: 0, fontFace: BF, fontSize: 11, color: "33384f", valign: "middle" }); ry += 0.46; });
  s.addShape(R, { x: 1.4, y: ry + 0.12, w: 8.25, h: 0.66, fill: { color: SP } });
  s.addText("Runbook → AMBER: Support reviews enrollment, raises a site-activation action with the PM. Stays in the digest channel. The manager’s Friday one-pager will show: flagged → being handled.", { x: 1.6, y: ry + 0.12, w: 7.9, h: 0.66, margin: 0, fontFace: BF, fontSize: 11, bold: true, color: "FFFFFF", valign: "middle", lineSpacingMultiple: 1.0 });
  callout(s, 2, "An operational signal correctly stays in the routine channel — it does not cry wolf at the medical monitor. The support acts; the manager simply sees it was caught and handled.", AMBER);
}

// ===== 5 · WEEK 3 RED ALERT =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  header(s, "WEEK 3 · THU 06:07", "A candidate Hy's-Law signal trips the URGENT tier — outside the digest", RED);
  win(s, 1.2, 1.3, 8.6, 5.4, "Outlook — ⛔ URGENT safety alert", RED);
  s.addShape(R, { x: 1.4, y: 1.85, w: 8.25, h: 0.6, fill: { color: REDBG }, line: { color: RED, width: 1.5 } });
  s.addText("⛔  RED ALERT — candidate Hy's-Law lab pattern — Participant 0312 (cohort 5, top dose)", { x: 1.6, y: 1.85, w: 7.9, h: 0.6, margin: 0, fontFace: HF, fontSize: 14, bold: true, color: "7A2018", valign: "middle" });
  s.addText("auto-sent 06:07 · to: Support + BACKUP + role alias · cc: PM", { x: 1.55, y: 2.55, w: 7.9, h: 0.3, margin: 0, fontFace: BF, fontSize: 10.5, italic: true, color: MUTED });
  s.addText([
    { text: "Deterministic criteria met:  ", options: { bold: true, color: INK } },
    { text: "ALT 4.1× ULN  AND  total bilirubin 2.3× ULN  (ALP 1.2× ULN)  — hepatocellular pattern, same episode.\n\n", options: { color: "2b3047" } },
    { text: "▸ CONTACT THE MEDICAL MONITOR NOW", options: { bold: true, color: "7A2018" } },
    { text: "  — Dr. R. Okafor, +1-…\n", options: { color: "7A2018" } },
    { text: "▸ Acknowledge this alert within 30 minutes (reply to confirm receipt).\n", options: { color: "2b3047" } },
    { text: "▸ Evidence packet for Participant 0312 attached (see next page).\n\n", options: { color: "2b3047" } },
    { text: "This is a SCREENING flag that matches Hy's-Law lab criteria — it is NOT a diagnosis. The medical monitor adjudicates.", options: { italic: true, color: MUTED } },
  ], { x: 1.55, y: 2.95, w: 7.9, h: 3.4, margin: 0, fontFace: BF, fontSize: 12, valign: "top", lineSpacingMultiple: 1.06 });
  s.addShape(R, { x: 1.4, y: 6.05, w: 8.25, h: 0.5, fill: { color: "0f1130" } });
  s.addText("📎 CP101_S0312_eDISH_evidence.pdf  ·  📎 S0312_lab_trajectory.pdf  ·  heartbeat: ran 06:07, data fresh to 05:51", { x: 1.6, y: 6.05, w: 7.9, h: 0.5, margin: 0, fontFace: MONO, fontSize: 10, color: "8FE3B0", valign: "middle" });
  callout(s, 3, "A safety threshold fires immediately — outside the daily digest, to a primary + backup + a role alias (never one person) — with the medical monitor’s number and the evidence already attached.", RED);
}

// ===== 6 · EVIDENCE PACKET + RUNBOOK EXECUTION =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  header(s, "WEEK 3 · THU MORNING", "The evidence is pre-packaged; the humans decide", RED);
  // left: evidence packet (eDISH)
  win(s, 0.5, 1.3, 6.4, 5.4, "Evidence packet — Participant 0312 (auto-generated, reproducible)", SASB);
  s.addText("eDISH — peak ALT/ULN vs peak TBili/ULN", { x: 0.75, y: 1.8, w: 6.0, h: 0.3, margin: 0, fontFace: BF, fontSize: 11, bold: true, color: INK });
  // mini eDISH plot
  const px = 1.1, py = 2.2, pw = 4.6, ph = 2.7;
  s.addShape(R, { x: px, y: py, w: pw, h: ph, fill: { color: "FFFFFF" }, line: { color: LINE, width: 1 } });
  s.addShape(pres.shapes.LINE, { x: px + pw * 0.5, y: py, w: 0, h: ph, line: { color: AMBER, width: 1, dashType: "dash" } }); // ALT 3xULN
  s.addShape(pres.shapes.LINE, { x: px, y: py + ph * 0.45, w: pw, h: 0, line: { color: AMBER, width: 1, dashType: "dash" } }); // TBili 2xULN
  s.addText("Hy's-Law\nquadrant", { x: px + pw * 0.55, y: py + 0.12, w: 1.9, h: 0.5, margin: 0, fontFace: BF, fontSize: 8.5, bold: true, color: RED, align: "left", lineSpacingMultiple: 0.9 });
  // points
  [[0.2, 0.85], [0.32, 0.78], [0.45, 0.7], [0.28, 0.8], [0.72, 0.28]].forEach((p, i) => s.addShape(OV, { x: px + pw * p[0], y: py + ph * p[1], w: 0.12, h: 0.12, fill: { color: i === 4 ? RED : "9aa0d8" } }));
  s.addText("● S-0312", { x: px + pw * 0.72 + 0.15, y: py + ph * 0.28 - 0.06, w: 1.5, h: 0.25, margin: 0, fontFace: BF, fontSize: 9, bold: true, color: RED });
  s.addText("x: peak ALT (×ULN) →     y: peak total bilirubin (×ULN) ↑", { x: px, y: py + ph + 0.05, w: pw, h: 0.25, margin: 0, fontFace: BF, fontSize: 8.5, italic: true, color: MUTED });
  s.addText([{ text: "Packet also includes:  ", options: { bold: true, color: MUTED } }, { text: "lab trajectory (ALT/AST/TBL/ALP by visit) · dosing & exposure timeline · concomitant meds · the exact threshold rule that fired.", options: { color: "33384f" } }], { x: 0.75, y: 5.35, w: 6.0, h: 1.0, margin: 0, fontFace: BF, fontSize: 11, valign: "top", lineSpacingMultiple: 1.05 });
  // right: runbook execution log
  win(s, 7.1, 1.3, 5.7, 5.4, "Escalation log (time-stamped, automatic)", TERM);
  const log = [
    ["06:07", "ALERT fired — RED — S-0312", "8FE3B0"],
    ["06:09", "delivered: support, backup, alias, PM", "AEB4E0"],
    ["06:31", "support ACK (within 30-min SLA)", "8FE3B0"],
    ["07:10", "medical monitor reviewed packet", "AEB4E0"],
    ["07:25", "MM: repeat LFTs + hold cohort 5 dosing", "FFD27A"],
    ["Fri", "confirmatory labs trending down", "AEB4E0"],
    ["Sun", "MM: not confirmed Hy's Law; cohort released", "8FE3B0"],
    ["", "alert auto-stood-down; loop closed", "8FE3B0"],
  ];
  let ly = 1.9;
  log.forEach(l => { if (l[0]) pill(s, 7.3, ly, l[0], "BFE0FF", "23306a", 0.85); s.addText(l[1], { x: l[0] ? 8.25 : 7.3, y: ly - 0.02, w: 4.4, h: 0.32, margin: 0, fontFace: MONO, fontSize: 10.5, color: l[2], valign: "middle" }); ly += 0.5; });
  s.addShape(R, { x: 7.3, y: ly + 0.05, w: 5.3, h: 0.62, fill: { color: "1a1e40" } });
  s.addText("System did 3 deterministic things: DETECTED · PAGED · PACKAGED. Every clinical decision was the medical monitor’s.", { x: 7.45, y: ly + 0.05, w: 5.0, h: 0.62, margin: 0, fontFace: BF, fontSize: 10.5, bold: true, color: "E6E8FF", valign: "middle", lineSpacingMultiple: 1.0 });
  callout(s, 4, "Under stress, the covering colleague isn’t scrambling to pull data at 6 a.m. — it’s already assembled, identically formatted, and reproducible. Detect, page, package; humans decide.", RED);
}

// ===== 7 · WEEK 4 RETURN / AUDIT TRAIL =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  header(s, "WEEK 4 · THE LEAD RETURNS", "A complete, time-stamped, reproducible audit trail — nothing to reconstruct", GREEN);
  win(s, 0.5, 1.3, 12.3, 5.4, "Monitoring archive — CP-101 — the month, on the validated share", TERM);
  const files = [
    ["logs/2026-06-*.log", "22 dated SAS/R run logs — every job, every day, SYSCC=0", "AEB4E0"],
    ["digests/daily_*.pdf", "22 daily safety digests (heartbeat on each)", "AEB4E0"],
    ["digests/weekly_*.pdf", "4 weekly status packs + 4 manager one-pagers", "AEB4E0"],
    ["alerts/2026-06-16_AMBER_enrollment.pdf", "Week-2 enrollment KRI — flagged → handled (PM action)", "FFD27A"],
    ["alerts/2026-06-25_RED_S0312_HysLaw.pdf", "Week-3 candidate Hy's-Law — escalated → adjudicated → stood down", "FF9E8F"],
    ["evidence/CP101_S0312_eDISH_evidence.pdf", "auto-built evidence packet (eDISH + trajectory + dosing)", "AEB4E0"],
    ["heartbeat/heartbeat_history.csv", "every run accounted for — no silent gaps in the month", "8FE3B0"],
  ];
  let fy = 1.95;
  files.forEach(f => {
    s.addShape(R, { x: 0.7, y: fy, w: 11.9, h: 0.6, fill: { color: "1a1e40" }, line: { color: "2c3160", width: 1 } });
    s.addText("📄 " + f[0], { x: 0.9, y: fy, w: 5.0, h: 0.6, margin: 0, fontFace: MONO, fontSize: 11, bold: true, color: "E6E8FF", valign: "middle" });
    s.addText(f[1], { x: 6.0, y: fy, w: 6.4, h: 0.6, margin: 0, fontFace: BF, fontSize: 11, color: f[2], valign: "middle" });
    fy += 0.66;
  });
  s.addShape(R, { x: 0.7, y: fy + 0.05, w: 11.9, h: 0.55, fill: { color: GREEN } });
  s.addText("Closed loop: flag → escalate → package → decide → stand-down — all logged, all reproducible. No “what did the AI decide and why,” no PHI egress to explain.", { x: 0.9, y: fy + 0.05, w: 11.5, h: 0.55, margin: 0, fontFace: BF, fontSize: 12, bold: true, color: "FFFFFF", valign: "middle" });
  callout(s, 5, "Because the whole system is deterministic and validated, the audit trail is automatic and trustworthy — the lead reconstructs nothing, and the handback is clean.", GREEN);
}

// ===== 8 · SAFEGUARDS =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  header(s, "WHY IT WON'T FAIL SILENTLY", "Four safeguards — because “no news” must never mean “good news”", INDIGO);
  const cards = [
    ["Heartbeat / dead-man’s-switch", "Every successful run pings “ran OK, SYSCC=0”; an independent watcher on a second host escalates if the ping is missing — so a dead job announces itself.", INDIGO],
    ["Data-freshness gate (first check)", "Before any safety logic runs, compare each feed’s newest timestamp to now; if a source stopped refreshing, raise it — a clean green on stale data is worse than red.", SASB],
    ["Alert de-duplication", "A persistent seen-flags table keys each finding by participant+test+event, so one real event alerts once — no storm, no muted thread burying the next real signal.", AMBER],
    ["Primary + backup recipients", "Never one person: a primary, a backup, and a role-based alias, with an acknowledgement SLA — so a 6 a.m. alert never lands in a void while everyone’s away.", GREEN],
  ];
  const cw = (12.3 - 0.5) / 2, ch = 2.1;
  cards.forEach((c, i) => {
    const x = 0.5 + (i % 2) * (cw + 0.5), y = 1.45 + Math.floor(i / 2) * (ch + 0.3);
    s.addShape(R, { x, y, w: cw, h: ch, fill: { color: PANEL }, line: { color: LINE, width: 1 }, shadow: shadow() });
    s.addShape(R, { x, y, w: 0.1, h: ch, fill: { color: c[2] } });
    s.addText(c[0], { x: x + 0.35, y: y + 0.22, w: cw - 0.6, h: 0.5, margin: 0, fontFace: HF, fontSize: 17, bold: true, color: INK });
    s.addText(c[1], { x: x + 0.35, y: y + 0.78, w: cw - 0.65, h: ch - 0.95, margin: 0, fontFace: BF, fontSize: 12.5, color: "3a4060", valign: "top", lineSpacingMultiple: 1.06 });
  });
  s.addShape(R, { x: 0.5, y: 6.45, w: 12.3, h: 0.6, fill: { color: DARK } });
  s.addText([{ text: "The SOP rule: ", options: { bold: true, color: "FFFFFF" } }, { text: "“no news” is never interpreted as “all clear” — a successful, data-fresh run must say so explicitly, and the absence of any message is itself escalated.", options: { color: ICE } }], { x: 0.8, y: 6.45, w: 11.7, h: 0.6, margin: 0, fontFace: BF, fontSize: 12.5, valign: "middle" });
}

// ===== 9 · CLOSE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: DARK };
  s.addShape(RR, { x: 0.7, y: 0.6, w: 0.16, h: 0.34, fill: { color: SASB }, rectRadius: 0.04 });
  s.addText("THE BOTTOM LINE", { x: 1.0, y: 0.55, w: 10, h: 0.3, margin: 0, fontFace: BF, fontSize: 11, bold: true, charSpacing: 2, color: ICE });
  s.addText("Necessary, not sufficient — and that’s exactly the point.", { x: 0.7, y: 1.1, w: 12, h: 0.9, margin: 0, fontFace: HF, fontSize: 26, bold: true, color: "FFFFFF" });
  const pts = [
    ["The lowest-risk pipeline — ship today", "No AI, no new vendor, no PHI egress, no new validation surface. It reuses already-validated SAS/R inside the existing environment, so there’s no new approval gate between today and go-live.", GREEN],
    ["Deterministic & reproducible", "Same data → byte-identical result, every run. Nothing to “explain,” no model drift — the audit trail is automatic and trustworthy.", SASB],
    ["Humans — and the medical monitor — still decide", "It detects, pages, and packages pre-specified threshold crossings. It does not triage, interpret, or adjudicate. A flag is a prompt for a human, never a finding.", AMBER],
    ["The seam the AI hybrid fills later", "Narrative triage, cross-signal summarization, plain-language briefing — that’s the next layer. Ship this now; add AI on top when it’s approved.", INDIGO],
  ];
  const cw = (12.3 - 0.5) / 2, cy = 2.15, ch = 1.75;
  pts.forEach((p, i) => {
    const x = 0.7 + (i % 2) * (cw + 0.5), y = cy + Math.floor(i / 2) * (ch + 0.25);
    s.addShape(R, { x, y, w: cw, h: ch, fill: { color: "1E2350" }, line: { color: "343A6E", width: 1 } });
    s.addShape(R, { x, y, w: 0.09, h: ch, fill: { color: p[2] } });
    s.addText(p[0], { x: x + 0.3, y: y + 0.16, w: cw - 0.5, h: 0.6, margin: 0, fontFace: HF, fontSize: 15, bold: true, color: "FFFFFF" });
    s.addText(p[1], { x: x + 0.3, y: y + 0.7, w: cw - 0.55, h: ch - 0.82, margin: 0, fontFace: BF, fontSize: 11.5, color: ICE, valign: "top", lineSpacingMultiple: 1.03 });
  });
  s.addText("Peace of mind: monitoring never stops, even silence is verified (heartbeat + data-freshness), and every escalation is automatic and logged — while the lead is unreachable in Europe.", { x: 0.7, y: H - 0.66, w: 12, h: 0.4, margin: 0, fontFace: BF, fontSize: 12, italic: true, color: "9DA6E8", align: "center" });
}

pres.writeFile({ fileName: __dirname + "/SAS_R_OnLeave_Example_StepGuide.pptx" }).then(f => console.log("WROTE", f, "(" + S.length + " screens)"));
