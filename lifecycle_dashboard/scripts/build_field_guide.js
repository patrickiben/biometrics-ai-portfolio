// ============================================================================
// SUPERSEDED -- the shipped .html for this page is HAND-ENHANCED beyond what this
// builder generates: the package DARK theme, inline SVG diagrams, and content
// updates (2026-06). Rebuilding from this script regenerates the OLD output and
// DROPS all of that. The .html is the SOURCE OF TRUTH.
// Rebuild is guarded: aborts unless you deliberately set REBUILD=1.
// ============================================================================
if (process.env.REBUILD !== '1') {
  console.error('[SUPERSEDED] ' + __filename.split('/').pop() + ': out of sync with the hand-enhanced shipped HTML. Rebuilding would REGRESS it. The .html is the source of truth. Re-run with REBUILD=1 only if you intend to redo those enhancements.');
  process.exit(1);
}

#!/usr/bin/env node
/* build_field_guide.js — assemble the Study Lifecycle Monitor FIELD GUIDE (operating-depth wiki)
 * from verified section fragments (field_guide_sections.json).
 *
 * Sections were authored + adversarially verified by the `lifecycle-field-guide` workflow
 * (spec from the dashboard source -> 14 section drafts -> per-section accuracy/compliance verify).
 * Terminology: "participant" (never "subject"). No experimental/manuscript methods, no $/headcount.
 * Operations-only, decision-support, not validated software. Self-contained, offline.
 *
 * Run:  node lifecycle_dashboard/scripts/build_field_guide.js
 * Out:  lifecycle_dashboard/Study_Lifecycle_Monitor_FieldGuide.html
 */
const fs = require('fs'), path = require('path');
const here = __dirname;
const SRC = path.join(here, 'field_guide_sections.json');
const OUT = path.join(here, '..', 'Study_Lifecycle_Monitor_FieldGuide.html');

const { sections } = JSON.parse(fs.readFileSync(SRC, 'utf8'));

const TITLES = {
  'overview':'What this is — and what it is not',
  'quickstart':'Quick start — a 5-minute weekly review',
  'data-model':'The data model & the SIMULATED banner',
  'kpis':'KPI strip',
  'rag-heatmap':'Portfolio RAG heatmap & the scoring model',
  'signals':'Operational early-warning signals',
  'milestones':'Milestone track',
  'data-readiness':'Data readiness',
  'tlf-funnel':'TLF production funnel',
  'deliverables':'Deliverables pipeline by phase',
  'roster-modal':'Study roster & the drill-down modal',
  'trends':'Portfolio trend panel',
  'wiring':'Wiring it to live data',
  'governance':'Governance, guardrails & the two-dashboard split',
};
const ORDER = Object.keys(TITLES);
const secs = sections.slice().sort((a,b)=>ORDER.indexOf(a.id)-ORDER.indexOf(b.id));

const toc = secs.map((s,i)=>`      <li><a href="#${s.id}"><span class="tn">${i+1}</span>${s.navTitle}</a></li>`).join('\n');
const body = secs.map((s,i)=>
`  <section id="${s.id}">
    <h2><span class="num">${i+1}</span>${TITLES[s.id]||s.navTitle}</h2>
${s.innerHtml}
  </section>`).join('\n\n');

const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Study Lifecycle Monitor — Field Guide</title>
<style>
  :root{--bg:#0b0f1a;--panel:#141a28;--panel2:#1b2336;--line:#26304a;--ink:#e7ecf5;--mut:#93a0bd;
        --accent:#4ea8ff;--green:#2ecc71;--amber:#e6b450;--red:#ff5d6c;--teal:#3fd0c9;--r:12px;}
  *{box-sizing:border-box}
  html{scroll-behavior:smooth}
  body{margin:0;background:linear-gradient(180deg,#0b0f1a,#0a0d16 60%);color:var(--ink);
       font-family:"Segoe UI",Inter,system-ui,Arial,sans-serif;font-size:15px;line-height:1.62}
  a{color:var(--accent);text-decoration:none} a:hover{text-decoration:underline}
  .wrap{max-width:1180px;margin:0 auto;padding:20px 20px 80px;display:grid;grid-template-columns:248px 1fr;gap:30px}
  header{grid-column:1/-1;border-bottom:1px solid var(--line);padding-bottom:14px;margin-bottom:6px}
  header h1{font-size:23px;margin:0 0 4px;font-weight:680}
  header .sub{color:var(--mut);font-size:13.5px;margin:0}
  header .badge{display:inline-block;font-size:11px;font-weight:700;padding:3px 9px;border-radius:999px;
    border:1px solid var(--line);background:#0e1422;color:var(--mut);margin-right:6px;vertical-align:middle}
  header .badge.b2{color:#9fe0d6;border-color:#235049}
  /* TOC */
  nav.toc{position:sticky;top:14px;align-self:start;max-height:calc(100vh - 28px);overflow:auto;
    background:var(--panel);border:1px solid var(--line);border-radius:var(--r);padding:14px 12px}
  nav.toc .toc-h{font-size:11.5px;text-transform:uppercase;letter-spacing:.06em;color:var(--mut);margin:2px 6px 8px}
  nav.toc ol{list-style:none;margin:0;padding:0;counter-reset:none}
  nav.toc li{margin:1px 0}
  nav.toc a{display:flex;gap:8px;align-items:baseline;color:var(--mut);font-size:12.8px;padding:5px 8px;border-radius:8px;line-height:1.35}
  nav.toc a .tn{color:var(--accent);font-variant-numeric:tabular-nums;min-width:14px;text-align:right;font-size:11.5px}
  nav.toc a:hover{background:var(--panel2);color:var(--ink);text-decoration:none}
  nav.toc a.active{background:#10203a;color:var(--ink);box-shadow:inset 2px 0 0 var(--accent)}
  nav.toc .toc-links{margin-top:12px;padding-top:10px;border-top:1px solid var(--line)}
  nav.toc .toc-links a{display:block;color:var(--teal);font-size:12.3px;padding:4px 8px}
  /* content */
  main{min-width:0}
  section{background:var(--panel);border:1px solid var(--line);border-radius:var(--r);
    padding:8px 22px 20px;margin:0 0 18px;scroll-margin-top:14px}
  section h2{font-size:18px;font-weight:670;margin:18px 0 10px;display:flex;align-items:center;gap:11px;
    padding-bottom:10px;border-bottom:1px solid var(--line)}
  section h2 .num{display:inline-flex;align-items:center;justify-content:center;width:27px;height:27px;flex:0 0 auto;
    font-size:13px;font-weight:700;color:#07101f;background:linear-gradient(135deg,#4ea8ff,#3fd0c9);border-radius:8px}
  section h3{font-size:14.5px;font-weight:650;color:#cfe0ff;margin:18px 0 6px}
  p{margin:9px 0} ul,ol{margin:9px 0;padding-left:22px} li{margin:4px 0}
  strong{color:#fff} em{color:#cdd7ec}
  code{background:#0e1422;border:1px solid var(--line);border-radius:5px;padding:1px 5px;font-size:12.8px;
    color:#cfe3ff;font-family:"SFMono-Regular",Consolas,monospace;word-break:break-word}
  table.t{width:100%;border-collapse:collapse;font-size:13px;margin:12px 0}
  table.t th,table.t td{text-align:left;padding:7px 9px;border-bottom:1px solid var(--line);vertical-align:top}
  table.t th{color:var(--mut);font-weight:600;background:#0e1422}
  table.t tr:hover td{background:#0e1626}
  .note,.warn,.formula,.step{border-radius:9px;padding:11px 14px;margin:12px 0;font-size:13.6px}
  .note{background:#0e2230;border:1px solid #235049;border-left:3px solid var(--teal)}
  .note::before{content:"NOTE";display:block;font-size:10.5px;letter-spacing:.06em;color:var(--teal);font-weight:700;margin-bottom:3px}
  .warn{background:#241c08;border:1px solid #5a4a1f;border-left:3px solid var(--amber)}
  .warn::before{content:"CAUTION";display:block;font-size:10.5px;letter-spacing:.06em;color:var(--amber);font-weight:700;margin-bottom:3px}
  .formula{background:#0c1426;border:1px dashed var(--line);border-left:3px solid var(--accent);
    font-family:"SFMono-Regular",Consolas,monospace;font-size:12.8px;color:#d6e6ff;white-space:normal}
  .step{background:var(--panel2);border:1px solid var(--line);border-left:3px solid var(--accent)}
  footer{grid-column:1/-1;color:var(--mut);font-size:12.3px;margin-top:14px;border-top:1px solid var(--line);padding-top:14px}
  @media(max-width:880px){.wrap{grid-template-columns:1fr}nav.toc{position:static;max-height:none}}
  @media print{body{background:#fff;color:#000}section{break-inside:avoid;border-color:#ccc}nav.toc{display:none}.wrap{grid-template-columns:1fr}}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>Study Lifecycle Monitor — Field Guide</h1>
    <p class="sub"><span class="badge">Biostatistics Operations</span><span class="badge b2">operating-depth wiki</span>
      How to read and act on every panel of <a href="Study_Lifecycle_Monitor.html"><code>Study_Lifecycle_Monitor.html</code></a> —
      the operational complement to the participant-safety <code>TRIALMON_Dashboard.html</code>.
      Operations-only · decision-support, not validated software · demo data is simulated.</p>
  </header>

  <nav class="toc">
    <div class="toc-h">Field Guide</div>
    <ol>
${toc}
    </ol>
    <div class="toc-links">
      <a href="Study_Lifecycle_Monitor.html">→ Open the dashboard</a>
      <a href="../Program_Digest.html">→ Program digest</a>
    </div>
  </nav>

  <main>
${body}
  </main>

  <footer>
    Study Lifecycle Monitor — Field Guide · self-contained &amp; offline. The dashboard is <strong>operational monitoring only</strong>:
    no PHI, no participant-level data, no reported clinical numbers — reported/regulated values always come from validated tools
    (Phoenix WinNonlin, Pinnacle 21, EDC/CTMS). Transparent operational scoring — no predictive model and no experimental components.
    Demo data is SIMULATED (seeded, reproducible). The dashboard surfaces and ranks; the biostatistician decides.
  </footer>
</div>

<script>
/* TOC active-section highlight (no deps, no network) */
(function(){
  var links = {}, ids = [];
  document.querySelectorAll('nav.toc a[href^="#"]').forEach(function(a){
    var id = a.getAttribute('href').slice(1); links[id]=a; ids.push(id);
  });
  var obs = new IntersectionObserver(function(entries){
    entries.forEach(function(e){
      if(e.isIntersecting){
        ids.forEach(function(id){ if(links[id]) links[id].classList.remove('active'); });
        if(links[e.target.id]) links[e.target.id].classList.add('active');
      }
    });
  }, { rootMargin: '-10% 0px -75% 0px', threshold: 0 });
  document.querySelectorAll('main section[id]').forEach(function(s){ obs.observe(s); });
})();
</script>
</body>
</html>
`;
fs.writeFileSync(OUT, html);
console.log('wrote', path.relative(path.join(here,'..','..'), OUT), '('+html.length+' bytes, '+secs.length+' sections)');
