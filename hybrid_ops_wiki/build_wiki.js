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

// Builds the Hybrid AI Trial-Operations Wiki (self-contained HTML): authored narrative pages +
// the 75-use-case catalog rendered data-driven from _catalog.json. Sidebar nav + search.
const fs = require("fs");
const A11Y = require("../wiki_a11y.js");
const _tnotes = require("./notes.js");
const cat = JSON.parse(fs.readFileSync(__dirname + "/_catalog.json", "utf8"));
const esc = (s) => String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const tierClass = (t) => { t = (t || "").toUpperCase(); if (t.includes("RED")) return "tr"; if (t.includes("AMBER")) return "ta"; if (t.includes("GREEN")) return "tg"; return "tn"; };
const tierLabel = (t) => { t = (t || "").toUpperCase(); if (t.includes("RED")) return "RED"; if (t.includes("AMBER")) return "AMBER"; if (t.includes("GREEN")) return "GREEN"; return "—"; };
const findArea = (re) => cat.areas.find(a => re.test(a.area));

function ucTable(area) {
  let h = `<table class="uc"><tr><th>Automation</th><th>What the AI does (vs. what stays human / validated)</th><th>Engine</th><th>Integration</th><th class="tc">Tier</th><th>Human checkpoint</th></tr>`;
  area.usecases.forEach(u => {
    h += `<tr><td><b>${esc(u.name)}</b>${u.trigger ? `<br><span class="trg">${esc(u.trigger)}</span>` : ""}</td>`
      + `<td>${esc(u.what_ai_does)}${u.value ? `<br><span class="val">↳ ${esc(u.value)}</span>` : ""}</td>`
      + `<td>${esc(u.engine)}</td><td>${esc(u.integration)}</td>`
      + `<td class="tc ${tierClass(u.tier)}">${tierLabel(u.tier)}</td>`
      + `<td>${esc(u.human)}</td></tr>`;
  });
  return h + `</table>`;
}

const pmA = findArea(/project|timeline/i), etmfA = findArea(/etmf|document/i), qcA = findArea(/qc|validity/i), monA = findArea(/monitor|rbqm/i), platA = findArea(/platform/i), moreA = findArea(/additional|easily/i);
const counts = {}; cat.areas.forEach(a => a.usecases.forEach(u => { const k = tierLabel(u.tier); counts[k] = (counts[k] || 0) + 1; }));
const total = cat.areas.reduce((a, x) => a + x.usecases.length, 0);

const sections = [
  { id: "start", nav: "Start here", html: `
    <h1>Hybrid AI &mdash; Trial-Operations Operating Wiki</h1>
    <p class="lede">An agentic <strong>project-management, trial-management, and monitoring</strong> layer built on the hybrid <strong>Claude + local</strong> stack: ${total} automations across the study lifecycle &mdash; recurrent data-validity QC, SOP/WI/study-document ingestion, eTMF filing, Smartsheet timeline automation, and risk-based monitoring &mdash; each routed by data sensitivity, tiered by risk, and gated by a human.</p>
    <div class="callout warn"><strong>The operating principle (non-negotiable).</strong> The AI <strong>drafts, classifies, triages, routes, and summarizes.</strong> <strong>Validated tools own every regulated number and record</strong> (Pinnacle&nbsp;21 for conformance, Phoenix WinNonlin for PK, the EDC/CTMS/eTMF of record). <strong>PHI / unblinded data never leaves the local frozen model.</strong> A <strong>human approves any change</strong> to a regulated record or timeline &mdash; the LLM is never in the decision path for a regulated change.</div>
    <h2>The 60-second version</h2>
    <ol>
      <li>One <strong>gateway</strong> fronts a <strong>local model</strong> (sensitive data), the <strong>Claude API</strong> (de-identified reasoning), and a <strong>RAG store</strong> of your SOPs/WIs/study docs.</li>
      <li>An <strong>orchestrator</strong> fires scheduled and event-driven <strong>agents</strong> that read your systems (eTMF, Smartsheet, EDC, Pinnacle&nbsp;21) via connectors.</li>
      <li>Each agent <strong>proposes</strong> a change into a <strong>human-approval queue</strong>, with a full 21&nbsp;CFR Part&nbsp;11 audit trail.</li>
      <li>On approval, the change is written to the system of record. Nothing regulated moves without a human.</li>
    </ol>
    <p>It is the same hybrid architecture from the AI strategy &mdash; here, pointed at <em>operations</em>.</p>
  ` },

  { id: "platform", nav: "The platform", html: `
    <h1>The platform &mdash; one gateway, many agents</h1>
    <p>Every agent calls one OpenAI-compatible endpoint. The gateway routes by data classification, enforces guardrails, and logs everything; connectors expose your systems as tools.</p>
    <div class="flow">
      <div class="node orch"><b>Orchestration</b><span>scheduler + agent framework fires time-based &amp; event-based agents (cron / n8n / Power Automate)</span></div>
      <div class="arrow">&darr;</div>
      <div class="node gw"><b>The gateway (LiteLLM-class)</b><span>data-classification router &middot; Presidio PII/PHI egress firewall &middot; per-model cost/audit &middot; caching &middot; one Part&nbsp;11 trail</span></div>
      <div class="arrow split">&darr; &nbsp;&nbsp; &darr; &nbsp;&nbsp; &darr;</div>
      <div class="row">
        <div class="node loc"><b>Local frozen model</b><span>vLLM, air-gapped &mdash; sensitive / PHI / unblinded</span></div>
        <div class="node cld"><b>Claude API (BAA)</b><span>de-identified hard reasoning</span></div>
        <div class="node rag"><b>RAG knowledge base</b><span>SOPs / WIs / study docs (local, permissioned)</span></div>
      </div>
      <div class="arrow">&darr; &nbsp; connectors (MCP) &nbsp; &darr;</div>
      <div class="node conn"><b>Systems of record</b><span>eTMF &middot; Smartsheet &middot; EDC &middot; CTMS &middot; SharePoint &middot; Outlook &middot; Pinnacle&nbsp;21 &mdash; read-mostly; writes gated</span></div>
      <div class="arrow">&darr;</div>
      <div class="node hil"><b>Human-in-the-loop approval queue</b><span>every regulated change is proposed here, with the AI rationale + sources, for a human to approve / edit / reject</span></div>
    </div>
    <h2>Platform components</h2>
    ${ucTable(platA)}
  ` },

  { id: "pm", nav: "Project &amp; timeline", html: `<h1>${esc(pmA.area)}</h1><p>Milestone &amp; critical-path tracking, Smartsheet timeline automation, status reporting, action/decision capture, vendor oversight. Smartsheet's engine computes the plan; the AI explains, prioritizes, and proposes &mdash; the PM approves before any committed-date write.</p>${ucTable(pmA)}` },
  { id: "etmf", nav: "eTMF &amp; documents", html: `<h1>${esc(etmfA.area)}</h1><p>Auto-classify &amp; file to the DIA TMF Reference Model, completeness/expiry checks, and SOP/WI/study-doc ingestion into the RAG store for grounded compliance Q&amp;A. Filing to the record-of-truth is human-approved; RAG answers are draft/advisory and always cited.</p>${ucTable(etmfA)}` },
  { id: "qc", nav: "Data-validity QC", html: `<h1>${esc(qcA.area)}</h1><div class="callout tip">Recurrent QC at every stage: validated tools (Pinnacle&nbsp;21) produce the authoritative pass/fail; the <b>local</b> LLM clusters findings, diffs against the last clean run to surface only what's <b>new</b>, drafts the disposition grounded in the cSDRG/ADRG, and routes it &mdash; never altering the verdict. Participant-level data stays on-prem.</div>${ucTable(qcA)}` },
  { id: "mon", nav: "Monitoring &amp; RBQM", html: `<h1>${esc(monA.area)}</h1><p>ICH E6(R3) risk-based quality management: KRI/QTL breach signals, central/statistical monitoring, deviation surveillance, safety triage, DSMB packet assembly. Unblinded/participant-level signals run on the local model; reported safety numbers come from validated tools with medical review.</p>${ucTable(monA)}` },
  { id: "more", nav: "More automations", html: `<h1>${esc(moreA.area)}</h1><p>The easily-missed operations the completeness audit surfaced &mdash; consent version tracking, IP/drug accountability, randomization/IXRS oversight, regulatory-submission &amp; safety-clock tracking, training compliance, data-transfer scheduling, and more.</p>${ucTable(moreA)}` },

  { id: "gov", nav: "&#9888; Governance &amp; routing", html: `
    <h1>Governance &amp; routing</h1>
    <h2>The tier model</h2>
    <table><tr><th>Tier</th><th>Count</th><th>What the AI may do</th></tr>
    <tr><td><span class="tc tg">GREEN</span></td><td>${counts.GREEN || 0}</td><td>Drafts, summaries, cited RAG answers &mdash; advisory only.</td></tr>
    <tr><td><span class="tc ta">AMBER</span></td><td>${counts.AMBER || 0}</td><td>Classification / triage / code / proposed changes &mdash; with a human verify before anything is committed.</td></tr>
    <tr><td><span class="tc tr">RED</span></td><td>${counts.RED || 0}</td><td>Touches a reported number, a record-of-truth, or unblinded data &mdash; a <b>validated tool + human</b> decides; the LLM is out of the path.</td></tr></table>
    <h2>The three hard rules</h2>
    <ol>
      <li><b>PHI / unblinded / randomization data never leaves</b> &mdash; always the local frozen model (zero egress). De-identified text may use cloud Claude.</li>
      <li><b>Every reported number and record-of-truth comes from a validated tool</b> (Pinnacle&nbsp;21, Phoenix, the EDC/CTMS/eTMF), never an LLM.</li>
      <li><b>A human approves any change</b> to a regulated record or timeline &mdash; via the approval queue, with a Part&nbsp;11 audit trail.</li>
    </ol>
    <h2>How it's enforced</h2>
    <ul>
      <li><b>Data-classification router + Presidio</b> firewall at the gateway &mdash; PHI is blocked from the cloud egress by policy, not by trust.</li>
      <li><b>Engine-of-record registry + model-freeze</b> &mdash; the authoritative list of which validated engine / frozen model is in production; LLMs explicitly excluded from producing reported numbers.</li>
      <li><b>Unified 21 CFR Part 11 audit trail</b> &mdash; every gateway call and connector action: who/which agent, model + backend, prompt + classification, sources, proposal, approver, timestamps (ALCOA++).</li>
      <li><b>Least-privilege connectors</b> &mdash; read-mostly; writes to a record-of-truth are gated through the human queue.</li>
    </ul>
  ` },

  { id: "roadmap", nav: "Build roadmap", html: `
    <h1>Build roadmap &mdash; start small, earn trust</h1>
    <p>Stand it up in stages; each new agent goes live behind the human-approval queue and graduates as validation and trust accrue.</p>
    <h2>Phase 0 &mdash; the stack (from the hybrid AI strategy)</h2>
    <ul><li>Gateway (LiteLLM) + local vLLM model + Claude API under BAA + Presidio guardrail.</li><li>The Part&nbsp;11 audit trail and the human-approval queue.</li></ul>
    <h2>Phase 1 &mdash; the RAG knowledge base (highest value, lowest risk)</h2>
    <ul><li>Ingest approved SOPs / WIs / protocols / plans into the local vector store.</li><li>Ship the <b>SOP/compliance Q&amp;A</b> agent first &mdash; pure GREEN, cited answers, immediate daily value.</li></ul>
    <h2>Phase 2 &mdash; read-only connectors + scheduled agents</h2>
    <ul><li>Connect Smartsheet, the eTMF, and Pinnacle&nbsp;21 outputs as read tools.</li><li>Turn on the <b>nightly QC-triage</b> and <b>weekly status-report</b> agents (AMBER &mdash; everything to the approval queue).</li></ul>
    <h2>Phase 3 &mdash; event-driven automation &amp; monitoring</h2>
    <ul><li>Timeline-cascade on data cut / lock, eTMF filing proposals, action-item capture.</li><li>KRI/QTL breach signals and central-monitoring agents.</li><li>Gated writes graduate to lighter review as each agent earns a track record.</li></ul>
  ` },

  { id: "patterns", nav: "Agent &amp; prompt patterns", html: `
    <h1>Agent &amp; prompt patterns</h1>
    <h2>The standard agent loop</h2>
    <pre class="prompt">trigger (schedule / event)
  -> gather context: connectors (read) + RAG (cited)
  -> classify data sensitivity  ->  route to LOCAL or CLOUD via gateway
  -> reason: draft / classify / triage / summarize
  -> PROPOSE change to the human-approval queue (with rationale + sources)
  -> on human approval: write via connector to the system of record
  -> log everything to the Part 11 audit trail</pre>
    <h2>QC finding-triage prompt (local model)</h2>
    <pre class="prompt">You are triaging CDISC conformance findings. Pinnacle 21 has ALREADY produced the authoritative Error/Warning/Notice list (you NEVER change a verdict). Cluster findings by rule and domain; diff against the last clean run and surface only NEW findings; for each, draft a plain-language explanation and a proposed disposition (real defect vs expected/explained-in-cSDRG-ADRG, grounded in the reviewer guides), and name the programmer to route it to. Output a table; flag low confidence.</pre>
    <h2>SOP / compliance Q&amp;A prompt (RAG)</h2>
    <pre class="prompt">Answer ONLY from the approved SOP/WI knowledge base. Quote the exact clause and cite the document ID + version. If the SOPs do not cover it, say so. Never infer a regulatory requirement that isn't written.</pre>
    <h2>Weekly status-report prompt</h2>
    <pre class="prompt">Draft the weekly study status report in the house template from: the Smartsheet plan-of-record (milestones, % complete, slips), open risks/issues, action-item aging, and vendor deliverables. Pull numbers from the systems of record; invent nothing. Mark any reported metric for PM verification. Keep it to one page.</pre>
  ` },

  { id: "example", nav: "Worked example", html: `
    <h1>Worked example &mdash; a day in the ops layer</h1>
    <h2>02:00 &mdash; nightly QC triage</h2>
    <p>A new ADaM build lands. Pinnacle&nbsp;21 runs; the local agent diffs against the last clean run, finds <b>3 genuinely new</b> findings among 240 (the rest pre-explained from the ADRG), drafts dispositions, and routes them to two programmers' worklists. The CDISC lead opens a clean, pre-triaged queue at 08:00 instead of a 4-hour manual slog.</p>
    <h2>10:30 &mdash; data cut declared</h2>
    <p>The data-cut event fires. The agent recomputes the Smartsheet critical path, sees the dry-run TLF date now drives the finish, drafts targeted notifications (&ldquo;you are now blocked&rdquo;), and posts the recomputed plan to the <b>approval queue</b>. The PM approves; Smartsheet and the stakeholders update in minutes.</p>
    <h2>13:00 &mdash; a KRI breaches</h2>
    <p>Central monitoring flags a site whose query rate crossed its QTL. The local agent assembles the signal context (de-identified), drafts a follow-up for the CRA, and logs it to the RBQM register &mdash; medical review owns the call.</p>
    <h2>15:00 &mdash; eTMF filing + an SOP question</h2>
    <p>Three monitoring reports arrive; the agent proposes TMF Reference Model zones/artifacts and flags one as a probable duplicate &mdash; the doc controller approves the filing. Meanwhile a programmer asks the wiki agent &ldquo;what does our SOP require for a derived-variable spec?&rdquo; and gets the exact clause, cited.</p>
    <h2>16:00 &mdash; the weekly status report</h2>
    <p>The Friday agent drafts the status report from the plan-of-record and open risks; the PM edits two lines and sends it. <b>Every regulated number came from a validated system; no patient data left the building; and a human approved every committed change.</b></p>
  ` },

  { id: "faq", nav: "FAQ", html: `
    <h1>FAQ</h1>
    <p><b>Does the AI ever change a record on its own?</b> No. Every change to a regulated record, timeline, or reported output is <em>proposed</em> to the human-approval queue. The LLM is out of the decision path for anything regulated (RED).</p>
    <p><b>Where do the numbers come from?</b> Always a validated tool &mdash; Pinnacle&nbsp;21 (conformance), Phoenix WinNonlin (PK), the EDC/CTMS/eTMF of record. The AI triages and explains; it never produces the authoritative number.</p>
    <p><b>What about patient data?</b> PHI, unblinded, and participant-level data are processed only on the local, air-gapped model. The Presidio guardrail blocks PHI from the cloud egress by policy. De-identified text may use Claude.</p>
    <p><b>How is this different from the Copilot wiki?</b> The Copilot wiki is the M365-native, ops-memory layer for email. <em>This</em> is the full agentic operations platform on the hybrid stack &mdash; broader scope, deeper integration (eTMF, Smartsheet, Pinnacle&nbsp;21, EDC), and validated-tool + human-gated governance throughout.</p>
    <p><b>Is it inspection-defensible?</b> That is the design intent: validated engines of record, model-freeze, a unified Part&nbsp;11 audit trail, least-privilege connectors, and a human approving every regulated change.</p>
  ` },
];

const css = `
:root{--indigo:#8B86F0;--ink:#E7ECF8;--muted:#9AA6C8;--line:#272D4D;--panel:#181D38;--teal:#3FB6C2;--cloud:#6FA0DC;--amber:#D9A94F;--terra:#E0857A;--emer:#35C07E;--bg:#0E1124}
*{box-sizing:border-box}body{margin:0;font-family:-apple-system,Segoe UI,Calibri,Arial,sans-serif;color:var(--ink);background:var(--bg);line-height:1.55}
#wrap{display:flex;min-height:100vh}
#side{width:268px;flex:0 0 268px;background:#15183A;color:#fff;position:sticky;top:0;height:100vh;overflow:auto;padding:22px 0;border-right:1px solid #2a2f52}
#side .brand{padding:0 22px 14px;border-bottom:1px solid #2c2f55;margin-bottom:10px}
#side .brand b{font-family:Georgia,serif;font-size:16px}#side .brand span{display:block;color:#aeb4e0;font-size:11px;margin-top:4px}
#search{margin:0 16px 12px;width:calc(100% - 32px);padding:8px 10px;border-radius:8px;border:1px solid #3a3e72;background:#1d2150;color:#fff;font-size:13px}
#side a{display:block;color:#cfd3f3;text-decoration:none;padding:7px 22px;font-size:13px;border-left:3px solid transparent}
#side a:hover{background:#1d2150}#side a.active{color:#fff;border-left-color:#8b86f0;background:#1d2150;font-weight:600}
#main{flex:1;max-width:1080px;margin:0 auto;padding:32px 46px 80px}
section{display:none}section.show{display:block;animation:f .2s}@keyframes f{from{opacity:.3}to{opacity:1}}
h1{font-family:Georgia,serif;color:var(--ink);font-size:29px;margin:0 0 14px;line-height:1.15}
h2{font-family:Georgia,serif;color:#A9A4F5;font-size:19px;margin:24px 0 10px;border-bottom:1px solid var(--line);padding-bottom:5px}
.lede{font-size:16px;color:#C3CCE4}p,li{font-size:14.5px}ul,ol{padding-left:22px}li{margin:5px 0}
pre.prompt{background:#080A18;color:#e6e8ff;padding:13px 15px;border-radius:10px;overflow:auto;font-family:Consolas,monospace;font-size:12.5px;line-height:1.5;border:1px solid var(--line);border-left:4px solid var(--indigo);white-space:pre-wrap}
table{border-collapse:collapse;width:100%;margin:12px 0;font-size:13px}
th,td{border:1px solid var(--line);padding:7px 9px;text-align:left;vertical-align:top}
th{background:#15183A;color:#fff;font-weight:600;font-size:12px}
table.uc td:nth-child(1){width:18%}table.uc td:nth-child(2){width:34%}
.trg{color:var(--indigo);font-size:11px;font-style:italic}.val{color:var(--emer);font-size:12px}
.tc{text-align:center;font-weight:700;white-space:nowrap}
.tc.tg{background:#11261C;color:#7FE3B0}.tc.ta{background:#2A2412;color:#F0D58A}.tc.tr{background:#2A1614;color:#F0AFA6}.tc.tn{color:var(--muted)}
.callout{border-radius:10px;padding:13px 16px;margin:16px 0;font-size:14px}
.callout.warn{background:#2A1614;border-left:4px solid var(--terra)}.callout.tip{background:#0F262A;border-left:4px solid var(--teal)}
.flow{margin:16px 0}.node{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:11px 15px;box-shadow:0 2px 6px rgba(0,0,0,.3)}
.node b{display:block;font-size:14px}.node span{display:block;color:var(--muted);font-size:12.5px;margin-top:3px}
.node.orch{border-left:5px solid #64748b}.node.gw{border-left:5px solid var(--indigo)}.node.loc{border-left:5px solid var(--teal)}.node.cld{border-left:5px solid var(--cloud)}.node.rag{border-left:5px solid var(--amber)}.node.conn{border-left:5px solid #7c5cbf}.node.hil{border-left:5px solid var(--emer)}
.arrow{text-align:center;color:var(--indigo);font-size:17px;margin:5px 0;font-weight:700}
.row{display:flex;gap:12px}.row .node{flex:1}
.footer{margin-top:36px;padding-top:14px;border-top:1px solid var(--line);color:var(--muted);font-size:12px}
a{color:var(--indigo)}
`;
const js = `
const secs=[...document.querySelectorAll('section')],links=[...document.querySelectorAll('#side a[data-t]')];
function show(id){secs.forEach(s=>s.classList.toggle('show',s.id===id));links.forEach(a=>a.classList.toggle('active',a.dataset.t===id));window.scrollTo(0,0);if(location.hash!=='#'+id)history.replaceState(null,'','#'+id);}
links.forEach(a=>a.addEventListener('click',e=>{e.preventDefault();show(a.dataset.t);}));
document.querySelectorAll('#main a[href^="#"]').forEach(a=>a.addEventListener('click',e=>{const id=a.getAttribute('href').slice(1);if(document.getElementById(id)){e.preventDefault();show(id);}}));
const q=document.getElementById('search');q.addEventListener('input',()=>{const v=q.value.toLowerCase().trim();links.forEach(a=>{const s=document.getElementById(a.dataset.t);a.style.display=(!v||s.textContent.toLowerCase().includes(v))?'block':'none';});});
show((location.hash||'#start').slice(1)||'start');
`;
sections.push({ id: "transcript", nav: "Transcript", html: `<h1>Walkthrough transcript</h1><p class="lede">The complete narration of the walkthrough video, as readable text.</p>${A11Y.transcript(_tnotes)}` });
const nav = sections.map(s => `<a href="#${s.id}" data-t="${s.id}">${s.nav}</a>`).join("\n");
const body = sections.map(s => `<section id="${s.id}" aria-label="${String(s.nav).replace(/&[^;]+;/g,'').replace(/<[^>]+>/g,'').trim()}">${s.html}<div class="footer">Hybrid AI Trial-Operations Wiki &middot; ${total} automations &middot; built June 2026 &middot; AI drafts/triages/routes; validated tools + humans own every regulated record &amp; number.</div></section>`).join("\n");
const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Hybrid AI Trial-Operations Wiki</title><style>${css}</style></head><body><div id="wrap"><nav id="side"><div class="brand"><b>Hybrid AI &middot; Trial Ops</b><span>${total}-automation operating wiki</span></div><input id="search" placeholder="Search the wiki..." autocomplete="off">${nav}</nav><main id="main">${body}</main></div><script>${js}</script></body></html>`;
fs.writeFileSync(__dirname + "/Hybrid_AI_TrialOps_Wiki.html", A11Y.accessibleShell(html));
console.log("WROTE Hybrid_AI_TrialOps_Wiki.html (" + html.length + " bytes, " + sections.length + " pages, " + total + " automations)");
