// ============================================================================
// SUPERSEDED -- the shipped .html for this wiki is HAND-ENHANCED beyond what this
// builder generates: the package DARK theme, inline SVG diagrams, and content
// updates (2026-06). Rebuilding from this script regenerates the OLD base shell
// and DROPS all of that. The .html is the SOURCE OF TRUTH.
// Rebuild is therefore guarded: it aborts unless you deliberately set REBUILD=1
// (and accept that you must re-apply the diagrams/content yourself).
// ============================================================================
if (process.env.REBUILD !== '1') {
  console.error('[SUPERSEDED] ' + __filename.split('/').pop() + ': out of sync with the hand-enhanced shipped HTML (dark theme + inline diagrams + content). Rebuilding would REGRESS it. The .html is the source of truth. Re-run with REBUILD=1 only if you intend to redo those enhancements.');
  process.exit(1);
}

// Dedicated operating-depth LLM wiki for the TRIALMON interactive dashboard.
// Section bodies are authored as data in ./trialmon_wiki_sections.json (an array of
// {id, nav, html}); this builder themes them, wires the section-nav SPA via the shared
// wiki_a11y accessibility layer, and writes TRIALMON_Dashboard_Wiki.html.
const fs = require("fs");
const A = require("../wiki_a11y.js");

const ORDER = ["start","tour","governance","data","overview","hepatic","cardiac","labs","aedlt","disposition","subjects","signals","structure","production","reference","faq"];
const raw = JSON.parse(fs.readFileSync(__dirname + "/trialmon_wiki_sections.json", "utf8"));
const byId = {};
raw.forEach(s => { byId[s.id] = s; });
const sections = ORDER.filter(id => byId[id]).map(id => byId[id]);
// append any extra sections the writers produced that aren't in ORDER (defensive)
raw.forEach(s => { if (!ORDER.includes(s.id)) sections.push(s); });

const css = `
:root{--navy:#16293f;--steel:#2C5F8A;--steel2:#2563a8;--teal:#0E7C86;--ink:#16202B;--muted:#5a6b7b;--line:#DCE3EC;--panel:#F2F6FA;--green:#1F8A5B;--amber:#C2871A;--red:#C4544A;--bg:#FBFCFE}
*{box-sizing:border-box}body{margin:0;font-family:-apple-system,Segoe UI,Calibri,Arial,sans-serif;color:var(--ink);background:var(--bg);line-height:1.55}
#wrap{display:flex;min-height:100vh}
#side{width:296px;flex:0 0 296px;background:linear-gradient(185deg,#101d2e,#16293f 60%,#1c3450);color:#fff;position:sticky;top:0;height:100vh;overflow:auto;padding:22px 0}
#side .brand{padding:0 22px 14px;border-bottom:1px solid #294056;margin-bottom:10px}
#side .brand .mk{display:inline-flex;align-items:center;gap:9px;margin-bottom:9px}
#side .brand .mk i{width:30px;height:30px;border-radius:8px;background:linear-gradient(135deg,#3f7fc4,#2a5e96);display:flex;align-items:center;justify-content:center;font-style:normal;font-size:15px;font-weight:800;color:#fff}
#side .brand b{font-family:Georgia,serif;font-size:16.5px;line-height:1.25;display:block}#side .brand span{display:block;color:#9fb6cc;font-size:11px;margin-top:5px}
#side .brand .tag{display:inline-block;margin-top:9px;background:var(--steel2);color:#fff;font-size:10px;font-weight:800;letter-spacing:1px;padding:2px 8px;border-radius:20px}
#search{margin:0 16px 12px;width:calc(100% - 32px);padding:8px 10px;border-radius:8px;border:1px solid #2f4a63;background:#1d3346;color:#fff;font-size:13px}
#side a{display:block;color:#c4d4e2;text-decoration:none;padding:7.5px 22px;font-size:13.5px;border-left:3px solid transparent}
#side a:hover{background:#1d3346}#side a.active{color:#fff;border-left-color:#3f7fc4;background:#1d3346;font-weight:600}
#main{flex:1;max-width:1000px;margin:0 auto;padding:34px 52px 90px}
section{display:none}section.show{display:block;animation:f .2s}@keyframes f{from{opacity:.35}to{opacity:1}}
h1{font-family:Georgia,serif;color:var(--ink);font-size:29px;margin:0 0 14px;line-height:1.16}
h2{font-family:Georgia,serif;color:var(--steel);font-size:20px;margin:28px 0 10px;border-bottom:1px solid var(--line);padding-bottom:5px}
h3{font-size:15.5px;margin:18px 0 6px;color:var(--navy)}
.lede{font-size:17px;color:#2c3845}
p,li{font-size:15px}ul,ol{padding-left:22px}li{margin:5px 0}
a{color:var(--steel2)}a:hover{color:var(--navy)}
code{background:#eaf0f6;color:#244;padding:1px 6px;border-radius:5px;font-family:Consolas,monospace;font-size:12.5px}
.muted{color:var(--muted);font-size:13px}
.callout{border-radius:10px;padding:13px 16px;margin:16px 0;font-size:14.5px}
.callout.rule{background:#fbeceb;border-left:4px solid var(--red)}.callout.rule b,.callout.rule strong{color:#9a3d34}
.callout.honest{background:#fbf3e2;border-left:4px solid var(--amber)}.callout.honest b,.callout.honest strong{color:#8a5a12}
.callout.win{background:#e9f6ef;border-left:4px solid var(--green)}
.callout.key{background:#e8eff6;border-left:4px solid var(--steel)}
.callout.tip{background:#e4f2f3;border-left:4px solid var(--teal)}
table.cat{border-collapse:collapse;width:100%;margin:14px 0;font-size:13.5px}
table.cat th,table.cat td{border:1px solid var(--line);padding:8px 11px;text-align:left;vertical-align:top}
table.cat th{background:var(--navy);color:#fff;font-weight:600}table.cat tr:nth-child(even) td{background:var(--panel)}
.dl{display:flex;gap:12px;margin:16px 0;flex-wrap:wrap}
.btn{display:inline-block;background:var(--steel2);color:#fff;text-decoration:none;font-weight:700;font-size:14px;padding:11px 18px;border-radius:9px}
.btn.ghost{background:#fff;color:var(--steel2);border:1.5px solid var(--steel2)}.btn:hover{opacity:.92}
.footer{margin-top:42px;padding-top:16px;border-top:1px solid var(--line);color:var(--muted);font-size:12px}
@media(max-width:820px){#wrap{flex-direction:column}#side{width:100%;height:auto;position:static}#main{padding:24px 22px 70px}}
`;

const js = A.JS("start");
const nav = sections.map(s => `<a href="#${s.id}" data-t="${s.id}">${s.nav}</a>`).join("\n");
const footer = 'TRIALMON Dashboard &mdash; Field Guide &middot; the deterministic backbone made visible on SYNTHETIC data &middot; a flag is a screening prompt, not a determination or reportable number &middot; reported numbers come only from validated tools (Phoenix WinNonlin / Pinnacle&nbsp;21); the medical monitor / SRC decide &middot; part of the SAS/R Monitoring &amp; On-Leave Coverage package.';
const body = sections.map(s => {
  const label = String(s.nav).replace(/&[^;]+;/g, "").replace(/<[^>]+>/g, "").trim();
  return `<section id="${s.id}" aria-label="${label}">${s.html}<div class="footer">${footer}</div></section>`;
}).join("\n");

const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>TRIALMON Dashboard &mdash; Field Guide</title><style>${css}</style></head>
<body><div id="wrap">
<nav id="side"><div class="brand"><span class="mk"><i>T</i></span><b>TRIALMON Dashboard<br>Field Guide</b><span>How to read the deterministic safety-monitoring dashboard &mdash; every section, panel, threshold &amp; rule, in depth</span><span class="tag">FOR BIOSTATISTICIANS &amp; MEDICAL MONITORS</span></div>
<input id="search" placeholder="Search the field guide..." autocomplete="off">
${nav}</nav>
<main id="main">${body}</main></div>
<script>${js}</script></body></html>`;

fs.writeFileSync(__dirname + "/TRIALMON_Dashboard_Wiki.html", A.accessibleShell(html));
console.log("WROTE TRIALMON_Dashboard_Wiki.html (" + sections.length + " sections: " + sections.map(s => s.id).join(", ") + ")");
