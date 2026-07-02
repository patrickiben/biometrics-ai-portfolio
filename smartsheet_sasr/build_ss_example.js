// Worked example: a nightly SAS/R job updates a CP-101 Program Tracker in Smartsheet and lets
// Smartsheet send the alert. No AI. Mockup screens -> picture guide PDF + narrated video.
const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";
pres.title = "Smartsheet × SAS/R — nightly tracker automation (CP-101)";
const DARK = "15183A", INK = "1A1E33", MUTED = "5A607E", ICE = "D5DAF5", PANEL = "F4F5FB", LINE = "DDE1EE", SUBTLE = "F7F8FC";
const INDIGO = "4338CA", INDIGOINK = "312C8A", INDBG = "ECECFB";
const SS = "3A6FB0", SSBG = "EAF1FA", TERM = "12152E", TEAL = "0E7C86";
const GREEN = "1F9D55", GREENBG = "E6F6EC", AMBER = "C2891C", AMBERBG = "FBF1D8", RED = "C0392B", REDBG = "FBECEA", TEAMS = "5059C9";
const HF = "Georgia", BF = "Calibri", MONO = "Consolas", W = 13.3, H = 7.5;
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
  s.addText(text, { x: 1.16, y: 6.82, w: 11.5, h: 0.5, margin: 0, fontFace: BF, fontSize: 12.5, bold: true, color: INDIGOINK, valign: "middle" });
}
const pill = (s, x, y, t, fg, bg, w) => { const ww = w || (0.2 + t.length * 0.075); s.addShape(RR, { x, y, w: ww, h: 0.28, fill: { color: bg }, rectRadius: 0.05 }); s.addText(t, { x, y, w: ww, h: 0.28, margin: 0, fontFace: BF, fontSize: 9.5, bold: true, color: fg, align: "center", valign: "middle" }); return ww; };
const statusColor = (s) => s === "At Risk" ? [RED, REDBG] : s === "On Track" ? [GREEN, GREENBG] : s === "Watch" ? [AMBER, AMBERBG] : [MUTED, "EEE"];
// a Smartsheet grid: cols = [name,width]; rows = array of cell arrays (status cells are objects {s:"At Risk"})
function grid(s, x, y, w, cols, rows, hl) {
  const totalW = cols.reduce((a, c) => a + c[1], 0);
  let cx = x; const hy = y;
  s.addShape(R, { x, y: hy, w, h: 0.4, fill: { color: SS } });
  cols.forEach(c => { s.addText(c[0], { x: cx + 0.1, y: hy, w: c[1] - 0.1, h: 0.4, margin: 0, fontFace: BF, fontSize: 10, bold: true, color: "FFFFFF", valign: "middle" }); cx += c[1]; });
  let ry = hy + 0.4;
  rows.forEach((r, ri) => {
    if (hl && hl.includes(ri)) s.addShape(R, { x, y: ry, w, h: 0.5, fill: { color: "FFF7E0" }, line: { color: AMBER, width: 1 } });
    else if (ri % 2) s.addShape(R, { x, y: ry, w, h: 0.5, fill: { color: SUBTLE } });
    cx = x;
    r.forEach((v, ci) => {
      if (v && v.s) { const [fg, bg] = statusColor(v.s); pill(s, cx + 0.08, ry + 0.11, v.s, fg, bg, cols[ci][1] - 0.2); }
      else s.addText(String(v == null ? "" : v), { x: cx + 0.1, y: ry, w: cols[ci][1] - 0.15, h: 0.5, margin: 0, fontFace: BF, fontSize: 10, color: "33384f", valign: "middle" });
      cx += cols[ci][1];
    });
    if (hl && hl.includes(ri)) pill(s, x + w - 0.75, ry + 0.07, "UPDATED", "1F7A44", "D7F2E1", 0.7);
    ry += 0.5;
  });
  return ry;
}

// ===== 1 TITLE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: DARK };
  s.addShape(R, { x: 9.5, y: 0, w: 3.8, h: H, fill: { color: "1B1F47" } });
  s.addShape(R, { x: 9.5, y: 0, w: 0.08, h: H, fill: { color: SS } });
  const loop = [["Scheduler", "nightly · Task Scheduler / cron"], ["SAS / R", "PROC HTTP / httr2 → API"], ["Smartsheet", "tracker rows updated by key"], ["Smartsheet alert", "a workflow emails the team"]];
  let ly = 1.45;
  loop.forEach((l, i) => { s.addShape(RR, { x: 9.95, y: ly, w: 2.95, h: 0.74, fill: { color: "262a55" }, line: { color: "3a3e72", width: 1 }, rectRadius: 0.06 }); s.addText([{ text: l[0] + "\n", options: { fontSize: 12.5, bold: true, color: "FFFFFF" } }, { text: l[1], options: { fontSize: 9, color: "AEB4E0" } }], { x: 10.1, y: ly + 0.06, w: 2.7, h: 0.62, margin: 0, fontFace: BF, lineSpacingMultiple: 0.92 }); if (i < 3) s.addText("↓", { x: 11.2, y: ly + 0.74, w: 0.4, h: 0.2, margin: 0, fontFace: BF, fontSize: 12, bold: true, color: SS, align: "center" }); ly += 0.92; });
  s.addText("SMARTSHEET × SAS/R · STUDY CP-101", { x: 0.7, y: 1.5, w: 8.5, h: 0.3, margin: 0, fontFace: BF, fontSize: 12, bold: true, charSpacing: 2, color: ICE });
  s.addText("Your tracker updates itself —\nand Smartsheet sends the alert", { x: 0.7, y: 1.95, w: 8.6, h: 1.8, margin: 0, fontFace: HF, fontSize: 33, bold: true, color: "FFFFFF", lineSpacingMultiple: 1.0 });
  s.addText("A nightly SAS/R job reads the CP-101 Program Tracker, updates status, % complete, and milestone dates from the validated data, cascades a moved date, attaches the latest status PDF — and a Smartsheet automated workflow emails the team. No AI. Operations data only, never PHI or a reported clinical number.", { x: 0.7, y: 3.95, w: 8.4, h: 1.3, margin: 0, fontFace: BF, fontSize: 13.5, color: ICE, lineSpacingMultiple: 1.06 });
  s.addText("Illustrative mockups. Smartsheet is a tracker, not a system of record; validated systems own the authoritative data.", { x: 0.7, y: 5.7, w: 8.4, h: 0.5, margin: 0, fontFace: BF, fontSize: 11, italic: true, color: "8088B0" });
}
// ===== 2 ARCHITECTURE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  header(s, "HOW IT WORKS", "Scheduled SAS/R → the Smartsheet API → your tracker → an alert", SS);
  const lanes = [
    ["SCHEDULER", "Task Scheduler / cron fires the SAS/R job nightly, under a service account.", MUTED, "EEF1F6"],
    ["SAS / R → API", "PROC HTTP (SAS) or httr2 (R) calls the Smartsheet REST API with a Bearer token: read the sheet, then update rows by a stable key.", SS, SSBG],
    ["SMARTSHEET", "The tracker rows update in place (no duplicates), files attach, status cells flip.", TEAL, "E2F1F2"],
    ["ALERT", "A Smartsheet automated workflow (configured once in the UI) emails the team when a cell changes.", AMBER, "FBF1D8"],
  ];
  const cw = (12.3 - 0.9) / 4, cy = 1.6, ch = 4.6;
  lanes.forEach((l, i) => {
    const x = 0.5 + i * (cw + 0.3);
    s.addShape(R, { x, y: cy, w: cw, h: ch, fill: { color: l[3] }, line: { color: LINE, width: 1 }, shadow: shadow() });
    s.addShape(R, { x, y: cy, w: cw, h: 0.5, fill: { color: l[2] } });
    s.addText(l[0], { x: x + 0.15, y: cy, w: cw - 0.3, h: 0.5, margin: 0, fontFace: BF, fontSize: 11, bold: true, color: "FFFFFF", valign: "middle" });
    s.addText(l[1], { x: x + 0.2, y: cy + 0.65, w: cw - 0.4, h: ch - 0.85, margin: 0, fontFace: BF, fontSize: 12, color: "33384f", valign: "top", lineSpacingMultiple: 1.06 });
    if (i < 3) s.addText("→", { x: x + cw + 0.02, y: cy + ch / 2 - 0.2, w: 0.26, h: 0.4, margin: 0, fontFace: BF, fontSize: 18, bold: true, color: MUTED, align: "center" });
  });
  callout(s, 0, "The pattern in one line: SAS/R writes the data; Smartsheet sends the notification. You configure the alert once in the UI; the job just changes the cell.", SS);
}
// ===== 3 BEFORE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  header(s, "BEAT 1 · READ THE SHEET", "The job reads the tracker — rows keyed by a Task ID", SS);
  win(s, 0.5, 1.3, 12.3, 5.4, "Smartsheet — CP-101 Program Tracker", SS);
  const cols = [["Task ID", 1.3], ["Task", 4.0], ["Status", 1.7], ["% Done", 1.0], ["Owner", 1.5], ["Due", 1.2], ["", 1.0]];
  const rows = [
    ["CP101-ENR", "Enrollment vs plan", { s: "On Track" }, "—", "PM", "ongoing", ""],
    ["CP101-ADPC", "ADPC spec — finalize", { s: "On Track" }, "60%", "A. Patel", "15 Jun", ""],
    ["CP101-CUT", "Database soft-lock / data cut", { s: "On Track" }, "—", "DM", "17 Jun", ""],
    ["CP101-TLF", "Dry-run TLFs", { s: "On Track" }, "10%", "J. Kim", "24 Jun", ""],
    ["CP101-DSMB", "DSMB pack", { s: "On Track" }, "0%", "Biostat", "30 Jun", ""],
  ];
  grid(s, 0.7, 1.95, 11.9, cols, rows);
  s.addText("The job pulls the sheet (GET /sheets/{id}) and maps each row by its Task ID — so it updates the right rows in place, never appending duplicates.", { x: 0.7, y: 5.5, w: 11.9, h: 0.6, margin: 0, fontFace: BF, fontSize: 12, italic: true, color: MUTED, valign: "top", lineSpacingMultiple: 1.05 });
  callout(s, 1, "Read first, key by Task ID. Idempotency is the whole game: update the existing row, never blind-append — so re-running the job never duplicates a thing.", SS);
}
// ===== 4 UPDATE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  header(s, "BEAT 2 · UPDATE STATUS", "Status, % complete & dates updated from the validated data", AMBER);
  win(s, 0.5, 1.3, 12.3, 5.4, "Smartsheet — CP-101 Program Tracker (after the nightly run)", SS);
  const cols = [["Task ID", 1.3], ["Task", 3.7], ["Status", 1.7], ["% Done", 1.0], ["Owner", 1.5], ["Due", 1.2], ["", 1.05]];
  const rows = [
    ["CP101-ENR", "Enrollment vs plan — 76% of plan", { s: "At Risk" }, "—", "PM", "ongoing", ""],
    ["CP101-ADPC", "ADPC spec — finalize", { s: "On Track" }, "85%", "A. Patel", "15 Jun", ""],
    ["CP101-CUT", "Database soft-lock / data cut", { s: "Watch" }, "—", "DM", "19 Jun", ""],
    ["CP101-TLF", "Dry-run TLFs", { s: "On Track" }, "10%", "J. Kim", "26 Jun", ""],
    ["CP101-DSMB", "DSMB pack", { s: "On Track" }, "0%", "Biostat", "30 Jun", ""],
  ];
  grid(s, 0.7, 1.95, 11.9, cols, rows, [0, 1, 2, 3]);
  callout(s, 2, "PUT /sheets/{id}/rows updates the cells by row id: enrollment flips to At Risk, ADPC jumps to 85%, the cut date moves to 19 Jun — straight from the validated study data.", AMBER);
}
// ===== 5 CASCADE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  header(s, "BEAT 3 · CASCADE A DATE", "The data cut moved 17 → 19 Jun — dependents follow", TEAL);
  // left: the logic; right: the affected rows
  win(s, 0.5, 1.3, 5.9, 5.4, "SAS / R — the cascade (deterministic)", TERM);
  s.addText([
    { text: "/* the confirmed change */\n", options: { color: "8FE3B0" } },
    { text: "data cut: 17 Jun -> 19 Jun  (+2 days)\n\n", options: { color: "E6E8FF" } },
    { text: "/* shift the dependent milestones */\n", options: { color: "8FE3B0" } },
    { text: "soft-lock     22 -> 24 Jun\n", options: { color: "E6E8FF" } },
    { text: "dry-run TLFs  24 -> 26 Jun\n", options: { color: "E6E8FF" } },
    { text: "DSMB pack     30 Jun (holds)\n\n", options: { color: "E6E8FF" } },
    { text: "/* one PUT updates the affected rows */\n", options: { color: "8FE3B0" } },
    { text: "%ss_upsert(sheet=&tracker, keycol=TaskID,\n          data=cascade_rows);", options: { color: "FFD27A" } },
  ], { x: 0.75, y: 1.85, w: 5.4, h: 4.6, margin: 0, fontFace: MONO, fontSize: 12, valign: "top", lineSpacingMultiple: 1.1 });
  win(s, 6.6, 1.3, 6.2, 5.4, "Smartsheet — affected rows", SS);
  const cols = [["Task", 3.0], ["Due (was)", 1.4], ["Due (now)", 1.4]];
  const rows = [["Data cut", "17 Jun", "19 Jun"], ["Soft-lock", "22 Jun", "24 Jun"], ["Dry-run TLFs", "24 Jun", "26 Jun"], ["DSMB pack", "30 Jun", "30 Jun"]];
  grid(s, 6.8, 1.95, 5.8, cols, rows, [0, 1, 2]);
  s.addText("Dependent dates are computed in SAS/R and pushed in one update — the timeline stays consistent without anyone re-typing it.", { x: 6.8, y: 4.6, w: 5.8, h: 0.8, margin: 0, fontFace: BF, fontSize: 11.5, italic: true, color: MUTED, valign: "top", lineSpacingMultiple: 1.05 });
  callout(s, 3, "When a date moves, the job recomputes the dependent milestones and updates them in one call — the cascade is deterministic, and the tracker never drifts out of sync.", TEAL);
}
// ===== 6 ATTACH + NOTIFY =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: SUBTLE };
  header(s, "BEAT 4–5 · ATTACH & ALERT", "Attach the status PDF — and let Smartsheet send the alert", AMBER);
  // left: attach
  win(s, 0.5, 1.3, 5.9, 5.4, "Smartsheet — summary row", SS);
  s.addText("CP-101 — weekly status", { x: 0.75, y: 1.85, w: 5.4, h: 0.35, margin: 0, fontFace: HF, fontSize: 14, bold: true, color: INK });
  s.addShape(R, { x: 0.75, y: 2.35, w: 5.4, h: 0.7, fill: { color: SSBG }, line: { color: "CBDDF0", width: 1 } });
  s.addText("📎  CP101_status_2026-06-16.pdf  (attached by the job)", { x: 0.9, y: 2.35, w: 5.1, h: 0.7, margin: 0, fontFace: BF, fontSize: 11.5, bold: true, color: "1E4C82", valign: "middle" });
  s.addText("POST /sheets/{id}/rows/{rowId}/attachments — the latest one-page status PDF lands on the summary row, so the current report is always one click away in the tracker.", { x: 0.75, y: 3.3, w: 5.4, h: 1.4, margin: 0, fontFace: BF, fontSize: 12, color: "33384f", valign: "top", lineSpacingMultiple: 1.06 });
  // right: the notification (Smartsheet workflow)
  win(s, 6.6, 1.3, 6.2, 5.4, "Outlook — from Smartsheet Automation", TEAMS);
  s.addShape(R, { x: 6.85, y: 1.85, w: 5.7, h: 0.6, fill: { color: REDBG }, line: { color: RED, width: 1 } });
  s.addText("⚠  CP-101 Program Tracker — a task is now At Risk", { x: 7.0, y: 1.85, w: 5.4, h: 0.6, margin: 0, fontFace: HF, fontSize: 13, bold: true, color: "7A2018", valign: "middle" });
  s.addText("Smartsheet · Automated workflow · to: PM, Biostat lead", { x: 6.85, y: 2.55, w: 5.7, h: 0.3, margin: 0, fontFace: BF, fontSize: 10, italic: true, color: MUTED });
  s.addText([
    { text: "Row ", options: {} }, { text: "CP101-ENR — Enrollment vs plan", options: { bold: true } }, { text: " changed to ", options: {} }, { text: "At Risk", options: { bold: true, color: RED } }, { text: " (76% of plan).\n\nOpen the tracker to review. — Sent by the Smartsheet workflow your team configured, triggered by tonight's update.", options: {} },
  ], { x: 6.85, y: 3.0, w: 5.7, h: 2.6, margin: 0, fontFace: BF, fontSize: 12, color: "2b3047", valign: "top", lineSpacingMultiple: 1.08 });
  callout(s, 5, "SAS/R wrote the data; Smartsheet sent the alert. The rich notification is a workflow you set up once in the Smartsheet UI — the job just flips the cell that triggers it.", AMBER);
}
// ===== 7 SAFEGUARDS =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: "FFFFFF" };
  header(s, "DOING IT SAFELY", "Four guardrails for an unattended SAS/R → Smartsheet job", INDIGO);
  const cards = [
    ["Idempotent by key", "Update existing rows by a stable Task ID — never blind-append. Re-running the job (or a retry) never creates duplicate rows.", INDIGO],
    ["Ops-only — no PHI", "Push only timelines, status, % complete, milestone dates, ownership. NEVER PHI, participant-level data, unblinded info, or reported clinical numbers — a column allowlist enforces it.", RED],
    ["Token kept secret + fail-loud", "The API token lives in a permissioned credentials file / env var, never in code. A missing/expired token or an API error stops loud and emails the backup — never a silent no-op.", AMBER],
    ["Rate-limit aware", "Handle HTTP 429 with exponential backoff and batch updates; the tracker stays consistent even under throttling.", TEAL],
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
  s.addText([{ text: "The boundary: ", options: { bold: true, color: "FFFFFF" } }, { text: "Smartsheet is a cloud tracker — operational data only. The validated systems own the authoritative numbers; Smartsheet shows the status.", options: { color: ICE } }], { x: 0.8, y: 6.45, w: 11.7, h: 0.6, margin: 0, fontFace: BF, fontSize: 12.5, valign: "middle" });
}
// ===== 8 CLOSE =====
{
  const s = pres.addSlide(); S.push(s); s.background = { color: DARK };
  s.addShape(RR, { x: 0.7, y: 0.6, w: 0.16, h: 0.34, fill: { color: SS }, rectRadius: 0.04 });
  s.addText("THE BOTTOM LINE", { x: 1.0, y: 0.55, w: 10, h: 0.3, margin: 0, fontFace: BF, fontSize: 11, bold: true, charSpacing: 2, color: ICE });
  s.addText("One macro to push status; Smartsheet does the rest.", { x: 0.7, y: 1.1, w: 12, h: 0.9, margin: 0, fontFace: HF, fontSize: 25, bold: true, color: "FFFFFF" });
  const pts = [
    ["Maximum ease", "A thin SAS/R macro library wraps the Smartsheet API — one call pushes a status, attaches a report, or cascades a date. Schedule it once; the tracker maintains itself.", SS],
    ["SAS/R does the data; Smartsheet does the alert", "Deterministic API calls from your validated programs; the rich notifications are Smartsheet workflows you configure once in the UI.", AMBER],
    ["Governed by design", "Idempotent updates, an ops-only column allowlist (no PHI), a secret token, and fail-loud error handling.", RED],
    ["Fits the family", "The no-AI companion to the SAS/R trial-monitoring automation — same scheduler, same discipline, a different target.", GREEN],
  ];
  const cw = (12.3 - 0.5) / 2, cy = 2.15, ch = 1.75;
  pts.forEach((p, i) => { const x = 0.7 + (i % 2) * (cw + 0.5), y = cy + Math.floor(i / 2) * (ch + 0.25); s.addShape(R, { x, y, w: cw, h: ch, fill: { color: "1E2350" }, line: { color: "343A6E", width: 1 } }); s.addShape(R, { x, y, w: 0.09, h: ch, fill: { color: p[2] } }); s.addText(p[0], { x: x + 0.3, y: y + 0.16, w: cw - 0.5, h: 0.5, margin: 0, fontFace: HF, fontSize: 15, bold: true, color: "FFFFFF" }); s.addText(p[1], { x: x + 0.3, y: y + 0.66, w: cw - 0.55, h: ch - 0.78, margin: 0, fontFace: BF, fontSize: 11.5, color: ICE, valign: "top", lineSpacingMultiple: 1.03 }); });
  s.addText("Illustrative. No AI — deterministic API automation. Operations data only; the validated systems own every reported number.", { x: 0.7, y: H - 0.6, w: 12, h: 0.35, margin: 0, fontFace: BF, fontSize: 11, italic: true, color: "8088B0", align: "center" });
}
pres.writeFile({ fileName: __dirname + "/Smartsheet_SASR_Example_StepGuide.pptx" }).then(f => console.log("WROTE", f, "(" + S.length + " slides)"));
