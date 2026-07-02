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

// Landing page for the "SAS/R Monitoring & On-Leave Coverage" package: the dedicated wiki + the
// on-leave coverage assets + the three component deep-dives + the multimodal assets, led by the
// covering-while-on-leave use case the manager cares about.
const fs = require("fs");
const css = `
*{box-sizing:border-box}body{margin:0;font-family:-apple-system,Segoe UI,Calibri,Arial,sans-serif;color:#16202B;background:#FBFCFE;line-height:1.55}
a.skip{position:absolute;left:-999px}a.skip:focus{left:8px;top:8px;background:#142433;color:#fff;padding:8px 14px;border-radius:6px}
header{background:#142433;color:#fff;padding:34px 7% 28px}
header .k{font-size:12px;letter-spacing:2px;font-weight:700;color:#9fb6cc}
header h1{font-family:Georgia,serif;font-size:31px;margin:8px 0 6px}
header .sub{font-size:16px;color:#cfdae6;font-style:italic;max-width:940px}
header .bar{height:5px;background:#1F7A55;margin:24px -7% 0}
main{max-width:1060px;margin:0 auto;padding:8px 7% 70px}
.rule{background:#fbeceb;border-left:4px solid #B5564B;border-radius:10px;padding:13px 16px;margin:20px 0;font-size:14.5px}
.win{background:#e7f4ee;border-left:4px solid #1F7A55;border-radius:10px;padding:13px 16px;margin:18px 0;font-size:14.5px}
h2{font-family:Georgia,serif;font-size:21px;color:#2C5F8A;margin:30px 0 6px;border-bottom:2px solid #E2E7F2;padding-bottom:6px}
.blurb{color:#566;font-size:14px;margin:0 0 12px}
.hero{display:flex;gap:16px;flex-wrap:wrap;align-items:stretch;margin:14px 0}
.hero .big{flex:2 1 360px;border:1px solid #DCE3EC;border-left:5px solid #2C5F8A;border-radius:12px;padding:16px 20px;background:#fff;box-shadow:0 2px 8px rgba(20,20,40,.05)}
.hero .big h3{margin:0 0 6px;font-size:18px}.hero .big p{font-size:14px;color:#33424f}
.cards{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:8px 0}
.card{border:1px solid #DCE3EC;border-left:5px solid #C9D2E6;border-radius:10px;padding:14px 18px;background:#fff}
.card.tm{border-left-color:#2C5F8A}.card.ss{border-left-color:#1F7A55}.card.slm{border-left-color:#B7791F}
.card h3{margin:0 0 5px;font-size:16px}.card p{font-size:13.5px;color:#33405e;margin:0 0 9px}
.links{display:flex;gap:8px;flex-wrap:wrap}
.links a{display:inline-block;background:#2C5F8A;color:#fff;text-decoration:none;font-weight:700;font-size:12px;padding:6px 11px;border-radius:7px}
.links a.ghost{background:#fff;color:#2C5F8A;border:1px solid #2C5F8A}
.foot{color:#566;font-size:12px;margin-top:24px;border-top:1px solid #DCE3EC;padding-top:10px}
@media(max-width:760px){.cards{grid-template-columns:1fr}}
`;
const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SAS/R Monitoring & On-Leave Coverage</title><style>${css}</style></head>
<body><a class="skip" href="#main">Skip to content</a>
<header><div class="k">FOR BIOSTATISTICIANS</div><h1>SAS/R Monitoring &amp; On-Leave Coverage</h1>
<div class="sub">Deterministic, scheduled SAS/R that keeps the trial monitored and the tracker current &mdash; so nothing slips while you&rsquo;re out on leave. <b>No AI in the loop:</b> it detects, packages, and pages; humans decide.</div><div class="bar"></div></header>
<main id="main">
<div class="rule"><b>The one rule.</b> The automation surfaces <i>pre-specified deterministic flags</i> and routes them to people. It does <b>not</b> triage, interpret, adjudicate, or auto-act on safety. The medical monitor and the covering biostatistician make every call; reported numbers come from validated tools (Phoenix WinNonlin, Pinnacle&nbsp;21, the validated pipeline) with independent double-programming; the optional language model never produces a number. No PHI / unblinded data in the tracker.</div>

<h2>The dedicated wiki</h2>
<div class="hero"><div class="big"><h3>SAS/R Monitoring &amp; On-Leave Coverage &mdash; the full wiki</h3>
<p>One navigable wiki at the same depth as the operating wiki: the daily-job architecture (ingest &rarr; freshness gate &rarr; checks &rarr; roll-up &rarr; digest &rarr; tier-2 alert &rarr; heartbeat &rarr; watchdog), the deterministic safety checks (eDISH/Hy&rsquo;s-Law, QTcF, AE/SAE, DLT-vs-3+3, labs), alerting &amp; the escalation matrix, the <b>covering-while-on-leave runbook</b>, the Smartsheet tracker, the optional on-device language layer, the macro libraries, safeguards, and IT readiness.</p>
<div class="links"><a href="SASR_Monitoring_Coverage_Wiki.html">Open the wiki (HTML)</a><a class="ghost" href="SASR_Monitoring_Coverage_Wiki.pdf">PDF</a></div></div></div>

<div class="win"><b>Covering while out on leave &mdash; the headline.</b> Everything runs under a service account (not your laptop); a named backup is paged on any RED with a one-page evidence packet; the tracker stays current; and an independent dead-man&rsquo;s switch makes &ldquo;no email&rdquo; itself a signal. Hand your cover one page and go.
<div class="links" style="margin-top:10px"><a href="SASR_Monitoring_Coverage_Wiki.html#onleave">The on-leave runbook (wiki &sect;)</a><a class="ghost" href="../sas_r_automation/SAS_R_Coverage_Runbook.pdf">Coverage Runbook (PDF)</a><a class="ghost" href="../sas_r_automation/SAS_R_OnLeave_Screencast_narrated.mp4">&#9654; Watch the live screencast</a><a class="ghost" href="../sas_r_automation/SAS_R_OnLeave_Example_narrated.mp4">&#9654; Annotated walkthrough</a></div></div>

<h2>See it work &mdash; the interactive dashboard</h2>
<p class="blurb">A self-contained, click-through dashboard on a <b>synthetic</b> CP-101 run &mdash; the deterministic backbone made visible (the eDISH / Hy&rsquo;s-Law screen, QTcF tiers, AE/SAE, DLT-vs-3+3, the freshness gate) with a click-to-open participant evidence packet.</p>
<div class="hero"><div class="big" style="border-left-color:#2C5F8A"><h3>TRIALMON &mdash; Interactive Monitoring Dashboard</h3>
<p>The <b>deterministic backbone</b>, made visible (validated logic): the signature plots and the escalation matrix on a seeded synthetic cohort with planted teaching signals &mdash; a Hy&rsquo;s-Law RED, a QTcF RED, a DLT cluster vs 3+3, and an instructive near-miss the AND-gate correctly keeps GREEN. Click any participant for the in-browser analog of the evidence packet. Runs offline in any browser; no data leaves the file.</p>
<div class="links"><a href="TRIALMON_Dashboard.html">Open the dashboard</a><a class="ghost" href="TRIALMON_Dashboard_Wiki.html">&#128214; Field Guide</a><a class="ghost" href="SASR_Monitoring_Coverage_Wiki.html#dashboard">What it shows (wiki &sect;)</a></div></div></div>
<div class="rule"><b>Honest by design.</b> The dashboard runs on <b>synthetic</b> data (no PHI, no real participants); its flags are <i>screening prompts</i>, never determinations or reportable numbers; reported numbers come from validated tools (Phoenix WinNonlin / Pinnacle&nbsp;21). It ships with a dedicated, operating-depth <a href="TRIALMON_Dashboard_Wiki.html">Field Guide</a> documenting every section, panel, threshold and governance rule.</div>

<h2>The three components, in depth</h2>
<div class="cards">
  <div class="card tm"><h3>TRIALMON &middot; the monitoring backbone</h3><p>The deterministic SAS/R loop &mdash; freshness gate, the safety + operational checks, the tier-2 alert with an evidence packet, the heartbeat, and the independent watchdog. The <code>%tm_*</code> library + R companion.</p><div class="links"><a href="../sas_r_automation/SAS_R_Trial_Monitoring_Automation.html">Open wiki</a><a class="ghost" href="../sas_r_automation/SAS_R_Monitor_Screencast_narrated.mp4">&#9654; Written in SAS (screencast)</a><a class="ghost" href="../sas_r_automation/macro_library/TRIALMON_Macro_Library_README.pdf">Macro README</a></div></div>
  <div class="card ss"><h3>SHEETLINK &middot; the tracker stays current</h3><p>The same scheduled job upserts status into the Smartsheet program tracker &mdash; idempotent by key, ops-only allowlist, token from a secret. Independently SAS-reviewed. The <code>%ss_*</code> library.</p><div class="links"><a href="../smartsheet_sasr/Smartsheet_SASR.html">Open wiki</a><a class="ghost" href="../smartsheet_sasr/macro_library/README.pdf">Macro README</a><a class="ghost" href="../smartsheet_sasr/SAS_R_Smartsheet_Screencast_narrated.mp4">&#9654; Live screencast</a></div></div>
  <div class="card slm"><h3>LOCALMIND &middot; optional language layer</h3><p>An <i>optional</i> on-prem SLM for the language tasks code can&rsquo;t do, behind loopback + validator + human-gate guardrails. The monitoring needs none of it. The <code>%slm_*</code> library + the IT enablement runbook.</p><div class="links"><a href="../slm_wiki/SLM_SASR_TrialOps.html">Open wiki</a><a class="ghost" href="../slm_wiki/IT_SLM_Enablement_Runbook.pdf">IT runbook</a><a class="ghost" href="../slm_wiki/SLM_OnDevice_Example_narrated.mp4">&#9654; Example</a></div></div>
</div>

<div class="foot">Deterministic, no-AI monitoring &mdash; the lowest-risk, ship-today pipeline in the program: it detects, packages, and pages; humans decide. Validate the threshold logic + scheduling wrapper as study programs; double-program anything reported. The optional on-device SLM is ops-only and behind guardrails.</div>
</main></body></html>`;
fs.writeFileSync(__dirname + "/SASR_Monitoring_Coverage.html", html);
console.log("WROTE SASR_Monitoring_Coverage.html");
