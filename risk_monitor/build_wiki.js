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

// Builds the Trial-Termination Early-Warning Dashboard / LLM Wiki (self-contained HTML).
// Dashboard landing (3-tier RAG panels + feed) + data-driven signal catalog from _catalog.json. Hybrid cloud Claude (API + BAA) + on-device local LLM.
const fs = require("fs");
const A11Y = require("../wiki_a11y.js");
const _tnotes = require("./notes.js");
const C = JSON.parse(fs.readFileSync(__dirname + "/_catalog.json", "utf8"));
const esc = (s) => String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const engClass = (e) => /local|device/i.test(e || "") ? "eloc" : /cloud|copilot/i.test(e || "") ? "ecld" : "eval";
const engShort = (e) => /local|device/i.test(e || "") ? "On-device" : /cloud|copilot/i.test(e || "") ? "Cloud Claude" : "Validated + human";

function sigTable(list) {
  let h = `<table class="sig"><tr><th>Signal</th><th>Detection (what the AI does vs. validated/human)</th><th>Engine</th><th>Threshold / KRI</th><th>Escalation</th></tr>`;
  list.forEach(s => {
    h += `<tr${s.adv ? ' class="advrow"' : ""}><td><b>${esc(s.name)}</b>${s.adv ? ` <span class="adv">ADV</span>` : ""}${s.category ? `<br><span class="cat">${esc(s.category)}</span>` : ""}${s.severity ? `<br><span class="sev">${esc(s.severity)}</span>` : ""}</td>`
      + `<td>${esc(s.detection || s.signal)}${s.data_source ? `<br><span class="src">src: ${esc(s.data_source)}</span>` : ""}</td>`
      + `<td class="eng ${engClass(s.engine)}">${engShort(s.engine)}</td>`
      + `<td>${esc(s.threshold)}</td><td>${esc(s.action)}</td></tr>`;
  });
  return h + `</table>`;
}

// ---- nested (deep) active-inference hierarchy diagram ----
function aiHierDiagram() {
  const tier = (cls, name, ts, gm, ot, ai) => `<div class="ai-tier ${cls}"><span class="ai-ts">${ts}</span><b>${name}</b><span class="ai-gm">${gm}</span><div class="ai-sigs"><span class="ai-sig"><span class="ot">OT</span>${ot}</span><span class="ai-sig"><span class="aii">AI</span>${ai}</span></div></div>`;
  const conn = `<div class="ai-conn"><span class="dn">&darr; top-down priors (predictions)</span><span class="up">bottom-up prediction errors (surprise) &uarr;</span></div>`;
  return `<div class="ai-hier">
    <div class="ai-meta"><b>CROSS-STUDY POOLING</b><small>Wasserstein-barycenter priors, learned across prior cohorts / studies (empirical Bayes) &mdash; recalibrated as each study completes</small><div class="ai-meta-a">sets &amp; recalibrates each tier's priors &#9656;</div></div>
    <div class="ai-col">
      ${tier("t-client", "CLIENT / PROGRAM", "slow &middot; weeks&ndash;months", "generative model of the program &amp; sponsor trajectory", "sponsor-behavior drift", "program free-energy")}
      ${conn}
      ${tier("t-study", "STUDY", "medium &middot; days&ndash;weeks", "dose&ndash;toxicity, enrollment &amp; QTL beliefs", "cohort distribution drift", "study free-energy &middot; EFE&rarr;RBM")}
      ${conn}
      ${tier("t-part", "PARTICIPANT", "fast &middot; minutes&ndash;days", "each participant's expected safety / PK trajectory", "participant-trajectory drift", "free-energy spike &middot; EFE&rarr;next assessment")}
      <div class="ai-obs">&darr; observations: central-lab LFTs &middot; ECG / QTcF &middot; PK exposure &middot; AEs &mdash; processed on-device (zero egress)</div>
    </div>
  </div>`;
}

// ---- dashboard mock (illustrative current state) ----
const panels = [
  { tier: "PARTICIPANT", rag: "amber", n: C.participant.signals.length, eng: "On-device local LLM · zero egress", sub: "DLTs · safety · PK exposure",
    rows: [["red", "S-1042 — candidate Hy's-Law / DILI: ALT 3.4× ULN + total bili 2.1× ULN (DLT window, day 9)"], ["amber", "S-1039 — ΔQTcF +48 ms (watch >30, alert >60 ms)"], ["amber", "Cohort 4 — within-participant AE cluster trending Grade 2 → 3"], ["amber", "⊳ free-energy spike on S-1042 since day 7 — EFE recommends an unscheduled LFT", 1]] },
  { tier: "STUDY", rag: "amber", n: C.study.signals.length, eng: "Cloud Claude (aggregate) + on-device drill-down", sub: "Dose-escalation · enrollment · QTLs",
    rows: [["green", "Cohort 4 DLT rate 1/6 — within the 3+3 escalation rule"], ["amber", "Screen-failure 38% vs 25% plan — enrollment KRI breached"], ["green", "Safety QTL (SAE rate) — within tolerance limit"], ["amber", "⊳ Wasserstein drift of cohort LFT distribution ↑ vs reference barycenter (tail mass moving)", 1]] },
  { tier: "CLIENT / SPONSOR", rag: "amber", n: C.client.signals.length, eng: "Cloud Claude · CRM / finance / public filings", sub: "Commercial early-warning",
    rows: [["red", "AR: $420K > 60 days past due — payment-aging breach"], ["amber", "Sponsor comms cadence −40% MoM — relationship watch"], ["amber", "2 scope-reduction change-orders this quarter"], ["amber", "⊳ sponsor-behavior Wasserstein drift ↑ vs baseline — relationship cooling", 1]] },
];
const feed = [
  ["09:12", "red", "PARTICIPANT", "S-1042 candidate Hy's-Law signal — flagged on-device, medical monitor + SRC notified, expedited-reporting clock started"],
  ["08:55", "amber", "PARTICIPANT", "⊳ Active-inference free-energy on S-1042 elevated since day 7 — EFE recommends an unscheduled LFT (medical-monitor approval pending)", 1],
  ["08:40", "amber", "STUDY", "Screen-failure KRI breached (38% vs 25%) — PM notified; feasibility review proposed"],
  ["08:05", "amber", "STUDY", "⊳ Wasserstein drift of the cohort-4 LFT distribution rising vs the pooled reference — transport map points to the upper tail", 1],
  ["Yest 16:05", "red", "CLIENT", "AR > 60 days breach ($420K) — account lead alerted; finance escalation drafted"],
  ["Yest 11:20", "amber", "PARTICIPANT", "S-1039 ΔQTcF +48 ms — intensified ECG monitoring flagged to medical monitor"],
  ["2 d ago", "green", "STUDY", "Cohort 4 cleared the 3+3 rule (1/6 DLT) — SRC packet pre-assembled"],
];
const dashHtml = `
  <h1>Trial-Termination Early-Warning &mdash; live risk dashboard</h1>
  <p class="lede">Three tiers of early-termination risk, monitored continuously. The AI <b>detects, aggregates, and triages</b> signals and drafts the alert; the SRC / DSMB / medical monitor, the PM, and the account lead make every call. Rows marked <span class="adv">ADV</span> come from the <a href="#adv">advanced engine</a> — <b>Optimal Transport (Wasserstein drift)</b> and <b>nested Active Inference (free-energy surprise)</b> — which surfaces risk <em>continuously and earlier</em> than a threshold rule. <span class="illus">Values below are illustrative.</span></p>
  <div class="panels">${panels.map(p => `
    <div class="panel ${p.rag}">
      <div class="p-h"><span class="dot ${p.rag}"></span><b>${p.tier}</b><span class="rag-l">${p.rag.toUpperCase()}</span></div>
      <div class="p-sub">${p.sub} &middot; ${p.n} signals monitored</div>
      ${p.rows.map(r => `<div class="srow${r[2] ? " advsr" : ""}"><span class="dot ${r[0]}"></span>${esc(r[1])}${r[2] ? ` <span class="adv">ADV</span>` : ""}</div>`).join("")}
      <div class="p-eng">${esc(p.eng)}</div>
    </div>`).join("")}</div>
  <h2>Early-warning feed</h2>
  <div class="feed">${feed.map(f => `<div class="frow${f[4] ? " advfr" : ""}"><span class="ftime">${f[0]}</span><span class="dot ${f[1]}"></span><span class="ftier">${f[2]}</span><span class="ftxt">${esc(f[3])}${f[4] ? ` <span class="adv">ADV</span>` : ""}</span></div>`).join("")}</div>
  <div class="legend"><span class="dot red"></span> termination-level risk &nbsp; <span class="dot amber"></span> watch / precursor &nbsp; <span class="dot green"></span> within limits &nbsp;&nbsp;|&nbsp;&nbsp; <span class="eng eloc">On-device</span> participant-level safety/PK, zero egress &nbsp; <span class="eng ecld">Cloud Claude</span> non-sensitive ops/commercial &nbsp;&nbsp;|&nbsp;&nbsp; <span class="adv">ADV</span> = continuous / anticipatory signal from the <a href="#adv">advanced engine</a> (Optimal Transport + Active Inference)</div>
`;

const sections = [
  { id: "dash", nav: "📊 Dashboard", html: dashHtml },
  { id: "arch", nav: "Architecture", html: `
    <h1>The hybrid architecture</h1>
    <p>Sensitivity decides the engine. <b>Participant-level safety, PK, and unblinded data never leave the device</b> — they run on a local LLM. Non-sensitive operational and commercial signals run on cloud Claude (API + BAA). A scoring layer rolls signals up to a tier RAG status; humans own every decision.</p>
    <div class="flow">
      <div class="node a"><b>Data sources</b><span>EDC / validated safety DB · central lab (LFTs) · ECG · IXRS · CTMS · Smartsheet · finance/AR · CRM · sponsor comms · web (public filings)</span></div><div class="arrow">&darr;</div>
      <div class="node b"><b>Routing by data sensitivity</b><span>participant-level safety / PK / unblinded &rarr; on-device · non-sensitive ops / commercial &rarr; cloud</span></div>
      <div class="row2"><div class="node loc"><b>On-device local LLM</b><span>participant safety/PK signals — zero egress, Part-11 audited</span></div><div class="node cld"><b>Cloud Claude (API + BAA)</b><span>study-ops KRIs &amp; client/commercial signals — under BAA</span></div></div>
      <div class="arrow">&darr;</div>
      <div class="node adv"><b>Advanced engine &mdash; Optimal Transport + nested Active Inference</b><span>runs inside each tier (on-device for participant-level): Wasserstein drift vs a pooled reference, and active-inference free-energy / EFE — continuous, anticipatory, geometry-aware signals on top of the rule-based KRIs. <a href="#adv">How it works &rarr;</a></span></div><div class="arrow">&darr;</div>
      <div class="node sc"><b>Scoring &amp; aggregation</b><span>weighted KRIs / stopping rules roll individual signals up to a Participant / Study / Client RAG status — not an autonomous verdict</span></div><div class="arrow">&darr;</div>
      <div class="node esc"><b>Alert &amp; escalation</b><span>safety &rarr; medical monitor / SRC / DSMB · study &rarr; PM · client &rarr; account lead — with a human-acknowledgement &amp; disposition log</span></div>
    </div>
    <div class="callout warn"><b>The rule.</b> The AI flags and prepares; <b>validated tools and humans decide.</b> Reported safety numbers come from the validated safety database, never the LLM. The medical monitor / SRC / DSMB make every DLT and safety determination; the PM owns the study; the account lead owns the client signal.</div>
  ` },
  { id: "participant", nav: "🔴 Participant signals", html: `<h1>Participant-level signals</h1><div class="callout tip">All ${C.participant.signals.length} are participant-level safety/PK — processed <b>on-device, zero egress</b>. The AI flags candidate DLTs and safety patterns <b>early</b>, before the formal cohort review, and pre-assembles the SRC packet. It never adjudicates the DLT.</div>${sigTable(C.participant.signals)}` },
  { id: "study", nav: "🟡 Study signals", html: `<h1>Study-level signals</h1><p>${C.study.signals.length} signals: the dose-escalation stopping rules, enrollment/feasibility KRIs, safety QTLs (ICH E6(R3)), data-quality and operational risk. Aggregate, de-identified KRIs run on cloud Claude; any participant-level drill-down stays on-device.</p>${sigTable(C.study.signals)}` },
  { id: "client", nav: "🟢 Client signals", html: `<h1>Client / sponsor-level signals</h1><div class="callout tip">${C.client.signals.length} <b>commercial</b> early-warnings that a sponsor may cancel, de-scope, or not renew — non-sensitive business data on cloud Claude. This is <b>signal &amp; triage for the account team</b>, not a verdict; the relationship owner decides.</div>${sigTable(C.client.signals)}` },
  { id: "scoring", nav: "Scoring & platform", html: `<h1>Detection, scoring &amp; escalation</h1><p>How individual signals become a tier risk level and an alert — and the platform pieces that run it.</p>${sigTable(C.platform.signals)}` },
  { id: "adv", nav: "🧮 Advanced engine", html: `
    <h1>Advanced engine &mdash; Optimal Transport + nested Active Inference</h1>
    <p class="lede">The rule-based KRIs answer <em>"has a line been crossed?"</em>. This layer answers the earlier question: <b>"is this trial drifting toward a line, and where should we look next?"</b> It adds three things on top of the thresholds — a <b>geometry-aware drift</b> signal (Optimal Transport), an <b>anticipatory surprise</b> signal (Active Inference), and a <b>nested, pooled</b> structure that ties the three tiers together.</p>
    <div class="callout warn"><b>Read this first.</b> This engine is <b>decision-support and advanced analytics</b> — it produces continuous scores and monitoring <em>suggestions</em>, never determinations. The rule-based DLT / Hy's-Law / QTcF / QTL triggers remain the <b>authoritative</b> early-warnings; OT and active inference surface risk <em>earlier and more continuously</em>, they do not replace the rules. Any model-derived signal that would inform a regulated decision must be <b>validated and locked</b> first; the validated tools still own every reported number, and the SRC / DSMB / medical monitor / PM still make every call.</div>

    <h2>1 · Optimal Transport &mdash; the geometry-aware drift signal</h2>
    <p>A threshold rule fires when one value crosses a line. <b>Optimal Transport</b> instead measures how far a whole <em>distribution</em> has moved. The <b>Wasserstein distance</b> is the minimum "cost" to transport one distribution onto another:</p>
    <div class="fml">W<sub>p</sub>(&mu;,&nu;) = ( inf<sub>&pi; &isin; &Pi;(&mu;,&nu;)</sub> &int; d(x,y)<sup>p</sup> d&pi;(x,y) )<sup>1/p</sup><span class="gl">&mdash; the cheapest plan &pi; to move distribution &mu; (e.g. this cohort's LFTs) onto &nu; (the reference). The <b>ground metric</b> d(x,y) encodes the outcome geometry &mdash; a Grade 1&rarr;3 move is farther than 1&rarr;2, a large exposure jump farther than a small one &mdash; and the order p tunes how heavily the large moves are weighted (W&#8322; penalizes them more than W&#8321;).</span></div>
    <p><b>Why Wasserstein and not KL-divergence?</b> Three reasons that matter for safety:</p>
    <ul>
      <li><b>It respects the outcome geometry.</b> Severity ordering and exposure magnitude are built into the cost — so a shift toward <em>worse</em> grades or <em>higher</em> exposure registers as a larger distance, in the right direction.</li>
      <li><b>It counts how far the mass moves.</b> A few participants sliding into a dangerous tail move mass a long way in ground-metric units — W registers that, where a mean/threshold summary misses it and KL (being geometry-blind, and prone to blowing up) tells you the distributions differ but not by how far or in which direction. The dangerous part of a dose-escalation shift <em>is</em> that tail movement.</li>
      <li><b>It is well-defined on non-overlapping support</b> (where KL &rarr; &infin;) and gives a smooth distance and a <b>direction</b> — the transport plan tells you <em>which</em> grades/exposures/participants are driving the drift, so the flag is interpretable.</li>
    </ul>
    <p>The reference each tier compares against is a <b>Wasserstein barycenter</b> of prior cohorts/studies — the distribution that minimizes the average transport cost to the historical set (this is the pooled prior, below):</p>
    <div class="fml">&mu;&#772;<sub>ref</sub> = argmin<sub>&mu;</sub> &sum;<sub>k</sub> &lambda;<sub>k</sub> W<sub>2</sub><sup>2</sup>(&mu;, &nu;<sub>k</sub>)<span class="gl">&mdash; a principled pooled reference built from prior cohorts &nu;<sub>k</sub>, not a hand-picked baseline.</span></div>
    <p><b>On-device feasibility:</b> 1-D Wasserstein is a closed-form sort (cheap), and <b>sliced-Wasserstein</b> reduces the multivariate case (labs + vitals + exposure jointly) to averaged 1-D projections — light enough to run on the <b>local model</b> for participant-level data, zero egress.</p>
    <p class="src">Drives, on the dashboard: participant-trajectory drift, cohort dose-escalation drift, site data-distribution anomaly (central monitoring), sponsor-behavior drift.</p>

    <h2>2 · Active Inference &mdash; the anticipatory surprise signal</h2>
    <p>Treat the monitor as an agent with a <b>generative model</b> of the trial's expected trajectory. Two quantities fall out, and both are exactly what an early-warning system wants.</p>
    <p><b>(a) Variational free energy &mdash; a tractable upper bound on surprise &mdash; is an early-warning signal.</b> As each observation arrives, the agent updates its beliefs to minimize free energy (variational Bayesian belief-updating); the free energy <b>upper-bounds the surprise</b> (the surprisal &minus;ln p(o)) &mdash; how poorly the model explains what it just saw. The same F has two equal forms — one that shows the bound, one that you actually compute:</p>
    <div class="fml">F = D<sub>KL</sub>[ q(s) &#8741; p(s&#124;o) ] &minus; ln p(o) &nbsp;&ge;&nbsp; &minus;ln p(o)&nbsp;&nbsp;<span style="font-weight:normal;font-size:12px">(the bound: the KL is &ge; 0)</span><br>&nbsp;&nbsp;= D<sub>KL</sub>[ q(s) &#8741; p(s) ] &minus; E<sub>q</sub>[ ln p(o&#124;s) ]&nbsp;&nbsp;<span style="font-weight:normal;font-size:12px">(complexity &minus; accuracy &mdash; what you compute)</span><span class="gl">&mdash; minimizing F over beliefs q = perception. Under exact inference the bound is tight (F = &minus;ln p(o) when q = p(s&#124;o)); with a restricted belief family it is a generally non-tight upper bound. Either way, a participant, cohort, or program whose observations are <em>surprising</em> under the expected model drives F up <em>before</em> a frank threshold event.</span></div>
    <p>The trial's <b>safety/quality tolerances (the QTLs, exposure caps, expected enrollment)</b> are encoded as the model's <b>preferred observations</b> (prior preferences <b>C</b>) — which enter the <em>expected</em> free energy below, not the perceptual F above. So there are two distinct early signals worth watching: <b>surprise</b> (F rising — the trial is doing something the model didn't expect) and <b>preference-divergence</b> (outcomes drifting from the preferred QTL state). They usually move together, but not always — a trial can drift toward a fully <em>predicted</em> bad state (low surprise, high preference-divergence), and you want to catch both.</p>
    <p><b>(b) Expected Free Energy = what to monitor next.</b> The agent chooses its next <em>action</em> — here, a monitoring/data-collection action — by minimizing <b>expected</b> free energy over candidate observations:</p>
    <div class="fml">&pi;<sup>&#42;</sup> = argmin<sub>&pi;</sub> G(&pi;),&nbsp;&nbsp; G(&pi;) = &minus; <span class="u">E[ information gain ]</span> &minus; <span class="u">E<sub>q</sub>[ ln p(o&#124;C) ]</span><span class="gl">&mdash; the agent <b>minimizes</b> G; because both terms are negated, that <b>maximizes</b> expected information gain and the expected log-preference ln p(o&#124;C) (where C is the preferred / safe outcome — the utility). The <b>epistemic</b> term picks the assessment that most reduces uncertainty about emerging risk; the <b>pragmatic</b> term favors reaching the safe, on-track state. Together they answer "which unscheduled assessment would tell us the most about whether this is a real DLT?"</span></div>
    <p>So the engine doesn't just wait — it <b>recommends</b> an unscheduled LFT/ECG/PK draw, or which site/cohort to monitor next (precision-weighted attention = risk-based monitoring that focuses where information-gain is highest). <b>Every such action is a suggestion for human approval — never an autonomous clinical or dosing action.</b></p>
    <p class="src">Drives, on the dashboard: participant free-energy spike + EFE-recommended monitoring; study-level free-energy drift + EFE-guided RBM; program-level free-energy.</p>

    <h2>3 · The nested / cross-study pooling structure</h2>
    <p>This is where the two methods compose. The three tiers are <b>not</b> three separate dashboards — they are one <b>deep (hierarchical) active-inference model</b> that minimizes a single hierarchical free energy by local message-passing. Each tier's beliefs are the <b>top-down priors</b> for the tier below; each tier's <b>prediction errors</b> (surprise) propagate <b>up</b>; and the levels run at different timescales (fast at the bedside, slow at the program). Because the levels are coupled in the model, a participant DLT propagates upward as study- and program-level risk instead of staying siloed.</p>
    ${aiHierDiagram()}
    <p style="margin-top:14px"><b>Cross-study pooling (empirical-Bayes pooling) sets the priors.</b> Each level's generative model — expected AE rates, the dose–toxicity prior, the enrollment curve, the "preferred" QTL states — has <b>hyperparameters estimated by pooling across prior cohorts/studies</b> (an empirical-Bayes / hierarchical prior). In the hierarchy the higher level <em>supplies</em> the prior for the level below; what is <em>pooled</em> from the population is the <b>hyperprior</b> that shapes those priors. Concretely, the <b>Wasserstein barycenter</b> of past cohorts is used <em>as</em> the reference a new cohort is scored against, and it <b>recalibrates as each study completes</b> — so a new study starts population-informed instead of from scratch. That cross-study hyperprior is the "meta".</p>
    <p><b>The tie that binds: a Wasserstein-regularized objective.</b> Using an Optimal-Transport cost in place of (or alongside) the KL term in the variational objective makes the divergence <b>geometry-aware and well-defined on non-overlapping support</b> — the same property that made W the right drift metric now makes the belief-updating robust, and it lets the pooled barycenter prior enter directly. The honest trade-off: once you swap KL for W it is <b>no longer the strict variational free energy</b>, so the clean "upper bound on surprisal" guarantee above relaxes into a geometry-aware regularizer — a deliberate, advanced design choice, not a free lunch. OT supplies the <em>metric</em>; active inference supplies the <em>dynamics</em>; cross-study pooling supplies the <em>priors</em>.</p>
    <div class="callout tip"><b>What this buys you over thresholds alone.</b> (1) <b>Earlier</b> — drift and surprise rise before a line is crossed. (2) <b>Geometry- and tail-aware</b> — it catches mass moving toward danger, not just a single value. (3) <b>Anticipatory</b> — it proposes the most informative next assessment instead of waiting. (4) <b>Coherent across tiers</b> — one nested model, so participant-level risk correctly propagates to study and program risk, with priors that get smarter every study.</div>

    <h2>Honesty &amp; validation</h2>
    <ul>
      <li><b>Advanced ≠ validated.</b> These are advanced methods. Treat their outputs as <em>triage and prioritization</em> until the specific implementation is validated and version-locked; the rule-based triggers and the validated safety/dose-escalation tools remain authoritative for any regulated decision.</li>
      <li><b>Frozen for reproducibility.</b> If a model-derived signal ever feeds a submission or a stopping decision, the model, the reference barycenters, and the thresholds must be <b>frozen and documented</b> (the same model-freeze argument as the rest of the program) so a result is reproducible.</li>
      <li><b>Participant-level stays on-device.</b> The participant-tier OT and active-inference computation runs on the local model with zero egress; only de-identified aggregates inform the cloud tiers.</li>
      <li><b>The action is a suggestion.</b> EFE recommends <em>what to observe</em>; a human orders it. Nothing about dosing, escalation, or termination is automated.</li>
    </ul>
  ` },
  { id: "gov", nav: "&#9888; Governance", html: `
    <h1>Governance &mdash; the AI flags, humans decide</h1>
    <ul>
      <li><b>The AI never makes a safety or termination call.</b> It detects, aggregates, triages, explains, and drafts the alert. The medical monitor / SRC / DSMB make DLT &amp; safety determinations; the PM owns the study; the account lead owns the client signal.</li>
      <li><b>Participant-level safety / PK / unblinded data never leaves the device.</b> The local LLM runs on-prem / on-device with zero egress. Only non-sensitive operational &amp; commercial signals use cloud Claude (under BAA).</li>
      <li><b>Validated tools own the numbers.</b> Reported safety numbers come from the validated safety database; cohort DLT-rate / stopping-rule math comes from the validated dose-escalation tool — never an LLM.</li>
      <li><b>Early-warning, not auto-action.</b> A flag triggers a human review and a disposition, logged with a 21 CFR Part 11 audit trail (ALCOA++). Nothing is paused, escalated, or terminated by the system itself.</li>
      <li><b>The client tier is decision-support for the account team</b> — surfacing commercial signals, never a unilateral judgement about a sponsor.</li>
    </ul>
  ` },
  { id: "build", nav: "Build guide", html: `
    <h1>Standing it up</h1>
    <h2>Phase 1 &mdash; the safe wins (cloud)</h2>
    <ul><li>Study &amp; client tiers first: wire enrollment / KRI / QTL feeds and the finance-AR / CRM / sponsor-comms signals into cloud Claude; build the Study and Client RAG panels behind a human-review queue. De-identified / non-sensitive only.</li></ul>
    <h2>Phase 2 &mdash; the on-device participant tier</h2>
    <ul><li>Stand up the on-device local LLM in the validated environment; connect the safety DB / central-lab / ECG feeds; encode the DLT criteria, Hy's-Law / eDISH logic, QTcF and PK-exposure thresholds; route every participant-level signal on-device with zero egress.</li><li>Wire the alerting to the medical monitor / SRC and the disposition log.</li></ul>
    <h2>Phase 3 &mdash; scoring, escalation &amp; audit</h2>
    <ul><li>The weighted roll-up to tier RAG, the escalation routing, the Part-11 audit trail and human-acknowledgement, and the cross-study safety view for the same compound.</li></ul>
  ` },
  { id: "example", nav: "Worked example", html: `
    <h1>Worked example &mdash; a DLT early-warning fires</h1>
    <h2>Day 9, cohort 4 (dose escalation)</h2>
    <p>Participant <b>S-1042</b>'s central-lab feed posts: <b>ALT 3.4× ULN, total bilirubin 2.1× ULN, ALP 1.3× ULN</b>. The <b>on-device</b> local LLM evaluates the eDISH logic, recognizes a <b>Hy's-Law pattern</b>, and &mdash; because it's inside the DLT window for this dose &mdash; flags a <b>candidate DLT</b>. Nothing left the device.</p>
    <h2>Within minutes</h2>
    <p>The model pre-assembles the case: the LFT trajectory, the eDISH context, the participant's dose &amp; exposure, concomitant meds, and the running <b>cohort DLT tally vs the 3+3 rule</b>. It drafts the alert and routes it to the <b>medical monitor and the SRC chair</b> &mdash; <em>ahead</em> of the scheduled cohort review &mdash; and logs the flag with a Part-11 audit entry.</p>
    <h2>The humans decide</h2>
    <p>The medical monitor orders a confirmatory repeat LFT; the SRC convenes. Per protocol, further dosing/escalation pauses pending adjudication. The <b>validated safety database</b> holds the authoritative numbers; the SRC makes the DLT determination. The dashboard's Participant panel goes <b>red</b>, the Study panel flags the cohort, and a cross-study check runs for the same compound.</p>
    <h2>The payoff</h2>
    <p>The signal surfaced on <b>day 9</b>, not at the cohort meeting on day 21 &mdash; with the SRC packet already built, the data never leaving the device, and a human making every call.</p>
  ` },
  { id: "faq", nav: "FAQ", html: `
    <h1>FAQ</h1>
    <p><b>Does the AI stop a study or a dose?</b> No. It is an <em>early-warning</em> system — it flags, aggregates, and drafts; the SRC / DSMB / medical monitor and the PM make every decision.</p>
    <p><b>Why on-device for the participant tier?</b> It's participant-level safety / PK / unblinded data. On-device with zero egress is the only way to use AI on it without a data-residency problem.</p>
    <p><b>Where do the numbers come from?</b> Validated systems — the safety database and the validated dose-escalation tool. The LLM never produces a reported safety number or a DLT-rate verdict.</p>
    <p><b>Is the client tier appropriate?</b> It's commercial decision-support for the account team — surfacing AR, communication, scope, and sponsor-health signals — not a judgement the system makes on its own.</p>
    <p><b>How does it relate to the rest of the program?</b> It's the risk-monitoring layer of the hybrid AI strategy: on-device local for sensitive data, cloud Claude (API + BAA) for non-sensitive — the same routing principle, pointed at early-termination risk.</p>
    <p><b>What are the "ADV" / Optimal-Transport / Active-Inference signals?</b> An <a href="#adv">advanced analytics layer</a> on top of the thresholds: <b>Optimal Transport (Wasserstein)</b> measures how far a distribution has drifted from a pooled reference (earlier and more tail-sensitive than a single value crossing a line), and <b>nested Active Inference</b> treats the monitor as a generative model whose <em>surprise</em> is an early-warning and whose <em>expected free energy</em> recommends the most informative next assessment. They are decision-support — advanced, not yet validated — and never override the rule-based triggers or the humans.</p>
  ` },
];

const css = `
:root{--indigo:#4338CA;--violet:#6D28D9;--ink:#1A1E33;--muted:#5A607E;--line:#E0E3F1;--panel:#F4F5FB;--teal:#0E7C86;--cloud:#2F6DB5;--emer:#0F9D6E;--amber:#C2891C;--terra:#B5564B;--red:#C0392B;--bg:#FBFBFE}
*{box-sizing:border-box}body{margin:0;font-family:-apple-system,Segoe UI,Calibri,Arial,sans-serif;color:var(--ink);background:var(--bg);line-height:1.55}a{color:var(--indigo)}
#wrap{display:flex;min-height:100vh}#side{width:248px;flex:0 0 248px;background:#15183A;color:#fff;position:sticky;top:0;height:100vh;overflow:auto;padding:22px 0}
#side .brand{padding:0 22px 14px;border-bottom:1px solid #2c2f55;margin-bottom:10px}#side .brand b{font-family:Georgia,serif;font-size:15px}#side .brand span{display:block;color:#aeb4e0;font-size:11px;margin-top:4px}
#search{margin:0 16px 12px;width:calc(100% - 32px);padding:8px 10px;border-radius:8px;border:1px solid #3a3e72;background:#1d2150;color:#fff;font-size:13px}
#side a{display:block;color:#cfd3f3;text-decoration:none;padding:7px 22px;font-size:13px;border-left:3px solid transparent}#side a:hover{background:#1d2150}#side a.active{color:#fff;border-left-color:#8b86f0;background:#1d2150;font-weight:600}
#main{flex:1;max-width:1100px;margin:0 auto;padding:30px 44px 80px}section{display:none}section.show{display:block}
h1{font-family:Georgia,serif;color:var(--ink);font-size:28px;margin:0 0 12px;line-height:1.15}h2{font-family:Georgia,serif;color:#312C8A;font-size:19px;margin:22px 0 10px;border-bottom:1px solid var(--line);padding-bottom:5px}
.lede{font-size:15.5px;color:#333}p,li{font-size:14.5px}ul{padding-left:22px}li{margin:6px 0}.illus{color:var(--muted);font-style:italic;font-size:13px}
.dot{display:inline-block;width:11px;height:11px;border-radius:50%;margin-right:7px;vertical-align:middle}.dot.red{background:var(--red)}.dot.amber{background:var(--amber)}.dot.green{background:var(--emer)}
.panels{display:flex;gap:14px;margin:16px 0}.panel{flex:1;border-radius:12px;border:1px solid var(--line);background:#fff;overflow:hidden;box-shadow:0 2px 8px rgba(20,20,40,.06)}
.panel.red{border-top:5px solid var(--red)}.panel.amber{border-top:5px solid var(--amber)}.panel.green{border-top:5px solid var(--emer)}
.p-h{display:flex;align-items:center;gap:6px;padding:11px 14px 4px}.p-h b{font-family:Georgia,serif;font-size:15px}.rag-l{margin-left:auto;font-size:10px;font-weight:700;color:var(--muted)}
.p-sub{padding:0 14px 8px;color:var(--muted);font-size:11.5px;border-bottom:1px solid var(--line)}
.srow{padding:8px 14px;font-size:12.5px;border-bottom:1px solid #f0f1f7}.p-eng{padding:8px 14px;font-size:11px;color:var(--muted);background:var(--panel)}
.feed{border:1px solid var(--line);border-radius:10px;overflow:hidden}.frow{display:flex;align-items:center;gap:10px;padding:8px 14px;font-size:13px;border-bottom:1px solid #f0f1f7}
.ftime{flex:0 0 78px;color:var(--muted);font-size:11.5px}.ftier{flex:0 0 96px;font-weight:700;font-size:11px;color:#312C8A}.ftxt{flex:1}
.legend{margin-top:14px;color:var(--muted);font-size:12px}
.eng{display:inline-block;padding:2px 8px;border-radius:5px;font-size:11px;font-weight:700;white-space:nowrap}.eng.eloc{background:#E2F1F2;color:#0A4F57}.eng.ecld{background:#E5EEF8;color:#1E4C82}.eng.eval{background:#EEE;color:#444}
table{border-collapse:collapse;width:100%;margin:12px 0;font-size:12.5px}th,td{border:1px solid var(--line);padding:7px 9px;text-align:left;vertical-align:top}th{background:#15183A;color:#fff;font-weight:600;font-size:12px}
table.sig td:nth-child(1){width:19%}table.sig td:nth-child(2){width:32%}
.cat{color:var(--indigo);font-size:11px;font-weight:700}.sev{color:var(--terra);font-size:11px}.src{color:var(--muted);font-size:11px;font-style:italic}
.callout{border-radius:10px;padding:13px 16px;margin:16px 0;font-size:14px}.callout.warn{background:#fbecea;border-left:4px solid var(--terra)}.callout.tip{background:#e4f2f3;border-left:4px solid var(--teal)}
.flow{margin:16px 0}.node{background:#fff;border:1px solid var(--line);border-radius:10px;padding:11px 15px;box-shadow:0 2px 6px rgba(20,20,40,.06);border-left:5px solid var(--indigo)}.node b{display:block;font-size:14px}.node span{display:block;color:var(--muted);font-size:12.5px;margin-top:3px}
.node.a{border-left-color:#64748b}.node.b{border-left-color:var(--indigo)}.node.loc{border-left-color:var(--teal)}.node.cld{border-left-color:var(--cloud)}.node.sc{border-left-color:var(--amber)}.node.esc{border-left-color:var(--emer)}
.arrow{text-align:center;color:var(--indigo);font-size:17px;margin:5px 0;font-weight:700}.row2{display:flex;gap:12px;margin:5px 0}.row2 .node{flex:1}
.footer{margin-top:34px;padding-top:14px;border-top:1px solid var(--line);color:var(--muted);font-size:12px}
.adv{display:inline-block;background:#EDE7FB;color:#5B21B6;font-size:9.5px;font-weight:800;letter-spacing:.4px;padding:1px 5px;border-radius:4px;vertical-align:middle;border:1px solid #d6c8f5}
.advrow td{background:#faf8ff}.advsr{background:#faf8ff}.advfr .ftxt{color:#3d2a6b}
.node.adv{border-left-color:var(--violet)}
.fml{background:#f7f6fd;border:1px solid #e4def6;border-left:4px solid var(--violet);border-radius:8px;padding:11px 15px;margin:12px 0;font-family:"Cambria Math",Georgia,serif;font-size:15px;color:#241a3d;line-height:1.5}
.fml .gl{display:block;font-family:-apple-system,Segoe UI,Arial,sans-serif;font-size:12.5px;color:var(--muted);margin-top:7px;line-height:1.5}
.fml .u{border-bottom:2px solid #c9bced;padding-bottom:1px}.fml sub,.fml sup{font-size:71%}
.ai-hier{display:flex;gap:12px;align-items:stretch;margin:16px 0}
.ai-meta{flex:0 0 168px;background:linear-gradient(180deg,#5B21B6,#7C3AED);color:#fff;border-radius:11px;padding:14px 14px;display:flex;flex-direction:column}
.ai-meta b{font-size:12px;letter-spacing:.6px}.ai-meta small{font-size:11px;color:#e7ddfb;margin-top:8px;line-height:1.45;flex:1}.ai-meta-a{font-size:11px;font-weight:700;color:#fff;border-top:1px solid #ffffff44;padding-top:8px;margin-top:8px}
.ai-col{flex:1;display:flex;flex-direction:column}
.ai-tier{border:1px solid var(--line);border-radius:11px;padding:11px 15px;background:#fff;box-shadow:0 2px 6px rgba(20,20,40,.05);border-left:5px solid var(--violet)}
.ai-tier.t-client{border-left-color:#2F6DB5}.ai-tier.t-study{border-left-color:var(--amber)}.ai-tier.t-part{border-left-color:var(--teal)}
.ai-tier b{font-size:14px}.ai-ts{float:right;font-size:10.5px;color:var(--muted);font-weight:600;background:var(--panel);padding:1px 7px;border-radius:9px}
.ai-gm{display:block;color:var(--muted);font-size:12px;margin:2px 0 7px}
.ai-sigs{display:flex;gap:8px;flex-wrap:wrap}.ai-sig{font-size:11.5px;background:var(--panel);border:1px solid var(--line);border-radius:7px;padding:3px 8px}
.ai-sig .ot{font-weight:800;color:#5B21B6;margin-right:5px}.ai-sig .aii{font-weight:800;color:#0E7C86;margin-right:5px}
.ai-conn{display:flex;justify-content:space-between;font-size:11px;color:#5B21B6;padding:5px 12px;font-weight:600}.ai-conn .up{color:var(--terra)}
.ai-obs{font-size:11.5px;color:var(--muted);font-style:italic;padding:7px 4px 0}
`;
const js = `const secs=[...document.querySelectorAll('section')],links=[...document.querySelectorAll('#side a[data-t]')];function show(id){secs.forEach(s=>s.classList.toggle('show',s.id===id));links.forEach(a=>a.classList.toggle('active',a.dataset.t===id));window.scrollTo(0,0);if(location.hash!=='#'+id)history.replaceState(null,'','#'+id);}links.forEach(a=>a.addEventListener('click',e=>{e.preventDefault();show(a.dataset.t);}));document.querySelectorAll('#main a[href^="#"]').forEach(a=>a.addEventListener('click',e=>{const id=a.getAttribute('href').slice(1);if(document.getElementById(id)){e.preventDefault();show(id);}}));const q=document.getElementById('search');q.addEventListener('input',()=>{const v=q.value.toLowerCase().trim();links.forEach(a=>{const s=document.getElementById(a.dataset.t);a.style.display=(!v||s.textContent.toLowerCase().includes(v))?'block':'none';});});show((location.hash||'#dash').slice(1)||'dash');`;
const total = C.participant.signals.length + C.study.signals.length + C.client.signals.length;
sections.push({ id: "transcript", nav: "Transcript", html: `<h1>Walkthrough transcript</h1><p class="lede">The complete narration of the walkthrough video, as readable text.</p>${A11Y.transcript(_tnotes)}` });
const nav = sections.map(s => `<a href="#${s.id}" data-t="${s.id}">${s.nav}</a>`).join("\n");
const body = sections.map(s => `<section id="${s.id}" aria-label="${String(s.nav).replace(/&[^;]+;/g,'').replace(/<[^>]+>/g,'').trim()}">${s.html}<div class="footer">Trial-Termination Early-Warning Dashboard &middot; ${total} signals across 3 tiers &middot; hybrid cloud Claude (API + BAA) + on-device local LLM &middot; the AI flags; the SRC / DSMB / PM / account lead decide &middot; built June 2026 (illustrative).</div></section>`).join("\n");
const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Trial-Termination Early-Warning Dashboard</title><style>${css}</style></head><body><div id="wrap"><nav id="side"><div class="brand"><b>Early-Warning Risk</b><span>3-tier termination-risk dashboard</span></div><input id="search" placeholder="Search signals..." autocomplete="off">${nav}</nav><main id="main">${body}</main></div><script>${js}</script></body></html>`;
fs.writeFileSync(__dirname + "/Trial_Risk_EarlyWarning_Dashboard.html", A11Y.accessibleShell(html));
console.log("WROTE Trial_Risk_EarlyWarning_Dashboard.html (" + html.length + " bytes; " + sections.length + " pages; " + total + " signals + " + C.platform.signals.length + " platform)");
