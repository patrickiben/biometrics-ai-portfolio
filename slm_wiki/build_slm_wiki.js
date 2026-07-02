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

// Builds the on-device-SLM + SAS/R Trial-Ops wiki: the 75-component stack re-assessed for a
// SMALL on-device open-weight model paired with SAS/R (✅ Ready / ⚠️ Guardrails / ❌ Beyond / ◇ Platform),
// rendered from _slm_assessment.json, with authored sections from _slm_sections.json.
const fs = require("fs");
const A11Y = require("../wiki_a11y.js");
const _tnotes = require("./slm_notes.js");
const A = JSON.parse(fs.readFileSync(__dirname + "/_slm_assessment.json", "utf8"));
const S = JSON.parse(fs.readFileSync(__dirname + "/_slm_sections.json", "utf8"));
const items = A.assessments || [];
const esc = (s) => String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

const V = {
  Ready:      { c: "vy", i: "✅ Ready",      lbl: "on-device ready" },
  Guardrails: { c: "vc", i: "⚠️ Guardrails", lbl: "with guardrails" },
  Beyond:     { c: "vn", i: "❌ Beyond",     lbl: "beyond a small model" },
  Platform:   { c: "vp", i: "◇ Platform",    lbl: "platform / SAS·R" },
};
const vClass = (v) => (V[v] || V.Guardrails).c;
const vIcon = (v) => (V[v] || V.Guardrails).i;

const areaKey = (s) => { s = (s || "").toLowerCase(); if (s.includes("project") || s.includes("timeline")) return "pm"; if (s.includes("etmf") || s.includes("document")) return "etmf"; if (s.includes("validity") || s.includes("qc")) return "qc"; if (s.includes("monitor") || s.includes("rbqm")) return "mon"; if (s.includes("platform")) return "plat"; return "more"; };
const areas = { pm: "Project & Timeline Management", etmf: "eTMF & Document Control", qc: "Data-Validity & Recurrent QC", mon: "Trial Monitoring & RBQM", plat: "The platform layer", more: "Additional / easily-missed" };
const grouped = {}; Object.keys(areas).forEach(k => grouped[k] = []); items.forEach(it => grouped[areaKey(it.area)].push(it));
const dist = { Ready: 0, Guardrails: 0, Beyond: 0, Platform: 0 }; items.forEach(it => dist[it.slm_verdict] != null ? dist[it.slm_verdict]++ : (dist[it.slm_verdict] = 1));

function table(list) {
  let h = `<table class="uc"><tr><th>Component</th><th class="vc-h">On-device?</th><th>What the small model does &middot; what SAS/R owns &middot; the honest limit</th></tr>`;
  list.forEach(u => {
    const detail = `<b>SLM:</b> ${esc(u.slm_role)}<br><b>SAS/R:</b> ${esc(u.sasr_role)}${u.note ? `<br><span class="lim">${esc(u.note)}</span>` : ""}`;
    h += `<tr><td><b>${esc(u.name)}</b></td><td class="vc ${vClass(u.slm_verdict)}">${vIcon(u.slm_verdict)}</td><td>${detail}</td></tr>`;
  });
  return h + `</table>`;
}
const beyond = items.filter(i => i.slm_verdict === "Beyond");
const sec = (id) => (S[id] && S[id].html) ? S[id].html : `<h1>${esc((S[id] && S[id].title) || id)}</h1><p class="note">[pending]</p>`;

const sections = [
  { id: "start", nav: "Start here", html: `
    <h1>On-device Small Language Models + SAS/R &mdash; the 75-component stack</h1>
    <p class="lede">We took the <strong>75-component hybrid trial-operations platform</strong> and re-assessed <strong>every component</strong> for a <strong>SMALL open-weight model running on-device</strong> (a 1&ndash;9B quantized model on a workstation, fully offline) paired with <strong>SAS/R</strong>. The principle is strict: <strong>SAS/R owns every number and check; the small model only classifies, extracts, routes, and drafts &mdash; always behind a human gate.</strong></p>
    <div class="verdict"><div class="vbox vy"><b>${dist.Ready}</b><span>✅ on-device ready</span></div><div class="vbox vc"><b>${dist.Guardrails}</b><span>⚠️ with guardrails</span></div><div class="vbox vn"><b>${dist.Beyond}</b><span>❌ beyond a small model</span></div><div class="vbox vp"><b>${dist.Platform}</b><span>◇ platform / SAS&middot;R</span></div></div>
    <div class="callout warn"><strong>The honest headline.</strong> An on-device small model is the <strong>most sovereign and cheapest</strong> option &mdash; data physically never leaves the workstation, it runs on hardware you already own, and it is trivially frozen for reproducibility. But it is a <strong>narrow language helper, not a reasoning engine</strong>: the ${dist.Ready} clean wins and ${dist.Guardrails} guardrailed components are real, while the ${dist.Beyond} marked <em>Beyond</em> genuinely need synthesis / long-context / nuance a small quantized model can&rsquo;t do reliably &mdash; those stay deterministic SAS/R or escalate to a larger model. The ${dist.Platform} <em>Platform</em> items aren&rsquo;t model tasks at all.</div>
    <p>Validated tools (Pinnacle&nbsp;21, Phoenix WinNonlin, the EDC/CTMS) still own every reported number and record &mdash; the &ldquo;RED&rdquo; governance is unchanged. What changes here is that the language helper is a <em>small, local, offline</em> model, so the data-sovereignty story is the simplest of any option &mdash; at the cost of model capability.</p>
  ` },
  { id: "why", nav: "Why on-device SLM + SAS/R", html: sec("why") },
  { id: "envelope", nav: "What a small model can/can't do", html: sec("envelope") },
  { id: "architecture", nav: "The SLM + SAS/R architecture", html: sec("architecture") },
  { id: "landscape", nav: "Choosing an on-device model", html: sec("landscape") },
  { id: "pm", nav: "&#9656; Project & Timeline", html: `<h1>${areas.pm}</h1><p>Status drafting, action capture, vendor oversight, timeline notes &mdash; mostly short classification/extraction/drafting a small model can do behind a human gate. SAS/R owns all the date math and the writes.</p>${table(grouped.pm)}` },
  { id: "etmf", nav: "&#9656; eTMF & documents", html: `<h1>${areas.etmf}</h1><p>Document classification to the TMF model, metadata/expiry extraction, SOP Q&amp;A over RAG &mdash; a strong fit for a small model on short passages with constrained output. Filing of record stays human + validated eTMF.</p>${table(grouped.etmf)}` },
  { id: "qc", nav: "&#9656; Data-validity QC", html: `<h1>${areas.qc}</h1><div class="callout tip">SAS/R (and Pinnacle&nbsp;21 / Phoenix) produce the authoritative findings and every number. The small model only <em>labels, clusters new-vs-known, and drafts a query text</em> over the finding &mdash; schema-constrained and SAS/R-validated. It never touches a value.</div>${table(grouped.qc)}` },
  { id: "mon", nav: "&#9656; Monitoring & RBQM", html: `<h1>${areas.mon}</h1><p>KRI/QTL signal labelling, deviation classification, MVR action extraction. Nuanced safety narrative and multi-signal synthesis are <em>Beyond</em> a small model &mdash; SAS/R computes, the model tags, humans decide.</p>${table(grouped.mon)}` },
  { id: "plat", nav: "&#9656; Platform layer", html: `<h1>${areas.plat}</h1><p>These are infrastructure, not model tasks &mdash; and the on-device variant <em>simplifies</em> most of them: one offline local model means there is no cloud egress to firewall and no model-agnostic gateway to run; SAS/R calls a single local endpoint, pins the model, and writes the audit trail.</p>${table(grouped.plat)}` },
  { id: "more", nav: "&#9656; Additional", html: `<h1>${areas.more}</h1><p>The easily-missed ops: consent-version tracking, IP accountability, safety-clock and submission tracking, training compliance, data-transfer receipt. Extraction and reminders suit a small model; the regulated records stay validated + human.</p>${table(grouped.more)}` },
  { id: "it_enable", nav: "&#9881; Standing it up with IT", html: sec("it_enable") },
  { id: "beyond", nav: "&#10060; What a small model can't do", html: `
    <h1>What a small on-device model can&rsquo;t do &mdash; and why</h1>
    <p>The ${beyond.length} components marked <b>Beyond</b> are the honest line: the <em>language</em> work needs frontier-level reasoning, long-context synthesis, or nuanced clinical/regulatory narrative that a small quantized model will not do reliably. Keep these <b>deterministic SAS/R</b> or escalate to a larger local/cloud model.</p>
    ${beyond.map(n => `<div class="nob"><b>❌ ${esc(n.name)}</b><span>${esc(n.note)} <i>SAS/R owns:</i> ${esc(n.sasr_role)}</span></div>`).join("")}
    <div class="callout warn"><b>The pattern:</b> a small model is safe exactly where the task is short, bounded, and structured. The moment it must reason across documents, hold long context, or write nuanced narrative, it is the wrong tool &mdash; that is not a deployment detail to tune around, it is the capability ceiling.</div>
  ` },
  { id: "macros", nav: "The SAS/R &times; SLM glue", html: `
    <h1>The SAS/R &times; SLM glue &mdash; <code>%slm_*</code> macros &amp; R functions</h1>
    <p>A small helper library so calling the local model is a few lines: SAS/R sends the prompt to the offline endpoint, forces <b>schema-constrained JSON</b>, gets the structured answer, and a <b>SAS/R validator</b> checks every field against an allowlist before anything is shown to a human. The model is pinned (name + quantization + digest + temperature&nbsp;0 + seed) so a run is reproducible.</p>
    <div class="dl">
      <a class="btn ghost" href="macro_library/slm_macros.sas">&#10515;&nbsp; slm_macros.sas</a>
      <a class="btn ghost" href="macro_library/slm_companion.R">&#10515;&nbsp; slm_companion.R</a>
      <a class="btn ghost" href="macro_library/triage_driver.sas">&#10515;&nbsp; triage_driver.sas</a>
      <a class="btn ghost" href="macro_library/slm_config.sas">&#10515;&nbsp; slm_config.sas</a>
      <a class="btn ghost" href="macro_library/README.pdf">&#10515;&nbsp; README (PDF)</a>
    </div>
    ${S.helper_html || ""}
    <div class="callout tip"><b>Five guarantees:</b> offline (loopback-only, asserted in code) &middot; schema-constrained output &middot; SAS/R-validated against an allowlist (never trust free text) &middot; the model pinned &amp; frozen for reproducibility &middot; a human gate before any write. The model never produces a number.</div>
  ` },
  { id: "watch", nav: "&#9654; A morning of on-device triage", html: `
    <h1>A morning of on-device triage &mdash; one offline workstation</h1>
    <p class="lede">A scheduled SAS/R QC run plus a small local model doing only the language layer, fully offline: SAS/R computes the findings, the model labels and drafts, SAS/R validates, the biostatistician approves, SAS/R writes and audits.</p>
    <div class="dl">
      <a class="btn" href="SLM_OnDevice_Example_narrated.mp4">&#9654;&nbsp; Play the narrated walkthrough</a>
      <a class="btn ghost" href="SLM_OnDevice_Example_StepGuide.pdf">&#10515;&nbsp; Step-by-step picture guide (PDF)</a>
      <a class="btn ghost" href="IT_SLM_Enablement_Runbook.pdf">&#10515;&nbsp; IT enablement runbook (PDF)</a>
    </div>
    <div class="shots">
      ${[1, 2, 3, 4, 5, 6].map(n => `<figure><img src="example_img/beat${n}.png" alt="Worked-example beat ${n}"><figcaption>${(_tnotes.captions && _tnotes.captions[n - 1]) || ""}</figcaption></figure>`).join("")}
    </div>
    <p class="muted">Illustrative mockups. Throughout: <b>SAS/R produced every count and check; the small on-device model only labelled, classified, and drafted; the biostatistician decided.</b></p>
  ` },
  { id: "gov", nav: "&#9888; Governance & limits", html: sec("governance") },
  { id: "faq", nav: "FAQ", html: sec("faq") },
];

const css = `
:root{--indigo:#3FB6C2;--ink:#E7ECF8;--muted:#9AA6C8;--line:#272D4D;--panel:#181D38;--teal:#3FB6C2;--emer:#35C07E;--amber:#D9A94F;--terra:#E0857A;--bg:#0E1124}
*{box-sizing:border-box}body{margin:0;font-family:-apple-system,Segoe UI,Calibri,Arial,sans-serif;color:var(--ink);background:var(--bg);line-height:1.55}a{color:var(--indigo)}
#wrap{display:flex;min-height:100vh}#side{width:266px;flex:0 0 266px;background:#0E2330;color:#fff;position:sticky;top:0;height:100vh;overflow:auto;padding:22px 0;border-right:1px solid #2a2f52}
#side .brand{padding:0 22px 14px;border-bottom:1px solid #244049;margin-bottom:10px}#side .brand b{font-family:Georgia,serif;font-size:15px}#side .brand span{display:block;color:#9fc3c8;font-size:11px;margin-top:4px}
#search{margin:0 16px 12px;width:calc(100% - 32px);padding:8px 10px;border-radius:8px;border:1px solid #2c4a53;background:#15333d;color:#fff;font-size:13px}
#side a{display:block;color:#c5dadd;text-decoration:none;padding:7px 22px;font-size:13px;border-left:3px solid transparent}#side a:hover{background:#15333d}#side a.active{color:#fff;border-left-color:#3fb6c2;background:#15333d;font-weight:600}
#main{flex:1;max-width:1080px;margin:0 auto;padding:32px 46px 80px}section{display:none}section.show{display:block}
h1{font-family:Georgia,serif;color:var(--ink);font-size:28px;margin:0 0 14px;line-height:1.15}h2{font-family:Georgia,serif;color:#5FC9D2;font-size:19px;margin:24px 0 10px;border-bottom:1px solid var(--line);padding-bottom:5px}
.lede{font-size:16px;color:#C3CCE4}p,li{font-size:14.5px}ul,ol{padding-left:22px}li{margin:5px 0}.note{color:var(--muted);font-size:13px}.muted{color:var(--muted);font-size:13px}
.verdict{display:flex;gap:12px;margin:16px 0;flex-wrap:wrap}.vbox{flex:1;min-width:130px;border-radius:10px;padding:14px;text-align:center;border:1px solid var(--line)}.vbox b{display:block;font-family:Georgia,serif;font-size:32px}.vbox span{font-size:12px}
.vbox.vy{background:#11261C}.vbox.vy b{color:#35C07E}.vbox.vc{background:#2A2412}.vbox.vc b{color:#D9A94F}.vbox.vn{background:#2A1614}.vbox.vn b{color:#E0857A}.vbox.vp{background:#141E2E}.vbox.vp b{color:#7FA8E0}
table{border-collapse:collapse;width:100%;margin:12px 0;font-size:13px}th,td{border:1px solid var(--line);padding:7px 9px;text-align:left;vertical-align:top}th{background:#0E2330;color:#fff;font-weight:600;font-size:12px}
table.uc td:nth-child(1){width:23%}.vc-h{width:10%;text-align:center}
.vc{text-align:center;font-weight:700;white-space:nowrap}.vc.vy{background:#11261C;color:#35C07E}.vc.vc{background:#2A2412;color:#D9A94F}.vc.vn{background:#2A1614;color:#E0857A}.vc.vp{background:#141E2E;color:#7FA8E0}
.lim{color:#E0857A;font-size:12px}
.callout{border-radius:10px;padding:13px 16px;margin:16px 0;font-size:14px}.callout.warn{background:#2A1614;border-left:4px solid var(--terra)}.callout.tip{background:#0F262A;border-left:4px solid var(--teal)}
.flow{margin:16px 0}.node{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:11px 15px;box-shadow:0 2px 6px rgba(0,0,0,.30);border-left:5px solid var(--indigo)}.node b{display:block;font-size:14px}.node span{display:block;color:var(--muted);font-size:12.5px;margin-top:3px}
.node.a{border-left-color:#64748b}.node.b{border-left-color:var(--indigo)}.node.c{border-left-color:var(--amber)}.node.d{border-left-color:var(--teal)}.node.e{border-left-color:var(--emer)}.node.f{border-left-color:#7c5cbf}
.arrow{text-align:center;color:var(--indigo);font-size:17px;margin:5px 0;font-weight:700}
.nob{background:#2A1614;border-left:4px solid var(--terra);border-radius:8px;padding:11px 14px;margin:9px 0}.nob b{display:block;color:#E0857A;font-size:14.5px}.nob span{display:block;color:var(--ink);font-size:12.5px;margin-top:3px}
pre.code,code{font-family:Consolas,monospace}code{background:#11302F;color:#7FD6DD;padding:1px 6px;border-radius:5px;font-size:12.5px}
pre.code{background:#080A18;color:#dceaec;padding:14px 16px;border-radius:10px;overflow:auto;font-size:12.5px;line-height:1.5;border:1px solid var(--line)}pre.code code{background:none;color:inherit;padding:0}
.dl{display:flex;gap:10px;margin:14px 0;flex-wrap:wrap}.btn{display:inline-block;background:var(--indigo);color:#0E1124;text-decoration:none;font-weight:700;font-size:14px;padding:10px 16px;border-radius:9px}.btn.ghost{background:transparent;color:var(--indigo);border:1.5px solid var(--indigo)}.btn:hover{opacity:.92}
.shots{display:grid;grid-template-columns:1fr 1fr;gap:18px;margin:18px 0}.shots figure{margin:0}.shots img{width:100%;border:1px solid var(--line);border-radius:10px;box-shadow:0 3px 12px rgba(0,0,0,.35);display:block}.shots figcaption{font-size:13px;color:var(--muted);margin-top:8px;line-height:1.4}
.footer{margin-top:36px;padding-top:14px;border-top:1px solid var(--line);color:var(--muted);font-size:12px}
`;
const js = `const secs=[...document.querySelectorAll('section')],links=[...document.querySelectorAll('#side a[data-t]')];function show(id){secs.forEach(s=>s.classList.toggle('show',s.id===id));links.forEach(a=>a.classList.toggle('active',a.dataset.t===id));window.scrollTo(0,0);if(location.hash!=='#'+id)history.replaceState(null,'','#'+id);}links.forEach(a=>a.addEventListener('click',e=>{e.preventDefault();show(a.dataset.t);}));document.querySelectorAll('#main a[href^="#"]').forEach(a=>a.addEventListener('click',e=>{const id=a.getAttribute('href').slice(1);if(document.getElementById(id)){e.preventDefault();show(id);}}));const q=document.getElementById('search');q.addEventListener('input',()=>{const v=q.value.toLowerCase().trim();links.forEach(a=>{const s=document.getElementById(a.dataset.t);a.style.display=(!v||s.textContent.toLowerCase().includes(v))?'block':'none';});});show((location.hash||'#start').slice(1)||'start');`;

// fill worked-example captions from notes if present
const capScript = `<script>const _caps=${JSON.stringify((_tnotes.captions || []))};_caps.forEach((c,i)=>{const el=document.getElementById('cap'+(i+1));if(el)el.innerHTML=c;});</script>`;

sections.push({ id: "transcript", nav: "Transcript", html: `<h1>Walkthrough transcript</h1><p class="lede">The complete narration of the &ldquo;morning of on-device triage&rdquo; video, as readable text.</p>${A11Y.transcript(_tnotes.narration || _tnotes)}` });
const nav = sections.map(s => `<a href="#${s.id}" data-t="${s.id}">${s.nav}</a>`).join("\n");
const body = sections.map(s => `<section id="${s.id}" aria-label="${String(s.nav).replace(/&[^;]+;/g, '').replace(/<[^>]+>/g, '').trim()}">${s.html}<div class="footer">On-device SLM + SAS/R &middot; Trial-Ops &middot; ${items.length} components (✅${dist.Ready} ⚠️${dist.Guardrails} ❌${dist.Beyond} ◇${dist.Platform}) &middot; SAS/R owns every number; the small model is human-gated &middot; offline = zero egress &middot; built June 2026 (illustrative).</div></section>`).join("\n");
const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>On-device SLM + SAS/R — Trial-Ops</title><style>${css}</style></head><body><div id="wrap"><nav id="side"><div class="brand"><b>On-device SLM &times; SAS/R</b><span>${items.length}-component, offline, no big model</span></div><input id="search" placeholder="Search..." autocomplete="off">${nav}</nav><main id="main">${body}</main></div><script>${js}</script>${capScript}</body></html>`;
fs.writeFileSync(__dirname + "/SLM_SASR_TrialOps.html", A11Y.accessibleShell(html));
console.log("WROTE SLM_SASR_TrialOps.html (" + html.length + " bytes; " + sections.length + " pages; " + items.length + " components: ✅" + dist.Ready + " ⚠️" + dist.Guardrails + " ❌" + dist.Beyond + " ◇" + dist.Platform + ")");
