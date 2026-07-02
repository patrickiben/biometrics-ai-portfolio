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

// "Biostatistics SAS/R Monitoring & On-Leave Coverage" — one dedicated LLM wiki consolidating the
// deterministic SAS/R monitoring backbone (TRIALMON %tm_*), the Smartsheet tracker auto-update
// (SHEETLINK %ss_*), and the optional on-device SLM language layer (LOCALMIND %slm_*), centered on the
// "covering while out on leave" use case — at the same depth as the Outlook operating wiki. No-AI for
// the monitoring itself: deterministic flags only; detect/package/email; humans decide; validated tools own numbers.
const fs = require("fs");
const A = require("../wiki_a11y.js");

const sections = [
  { id: "start", nav: "Start here", html: `
    <h1>SAS/R Monitoring &amp; On-Leave Coverage</h1>
    <p class="lede">Turn your already-validated monitoring programs into a <strong>scheduled, self-escalating loop</strong> so the trial keeps being watched, the tracker keeps being current, and nothing falls through the cracks &mdash; <strong>especially while you&rsquo;re out on leave</strong>. The monitoring itself is <strong>deterministic SAS/R, no AI required</strong> &mdash; the lowest-risk, ship-today pipeline in this whole program.</p>
    <div class="callout rule"><strong>The one rule.</strong> These macros <strong>detect, package, and email pre-specified deterministic flags</strong>. They <strong>do not triage, interpret, or adjudicate</strong>, and they <strong>never auto-act on safety</strong>. A flag is a <em>prompt for a human</em> &mdash; the medical monitor and the covering biostatistician make every call. Validate the threshold logic + scheduling wrapper as study programs (GxP); keep anything <em>reported</em> independently double-programmed; reported numbers come from validated tools, never from a flag and never from the optional language model.</div>
    <h2>Three components, one scheduled job</h2>
    <div class="grid3">
      <div class="comp tm"><b>TRIALMON <span>&middot; the backbone</span></b><p>Deterministic SAS/R that ingests the latest data, gates on <em>freshness</em>, runs the pre-specified safety + operational <em>checks</em>, rolls up severity, emails a <em>digest</em>, fires a <em>tier-2 urgent alert</em> on any RED, and closes with a <em>heartbeat</em> &mdash; watched by an independent <em>dead-man&rsquo;s switch</em>. The <code>%tm_*</code> library.</p></div>
      <div class="comp ss"><b>SHEETLINK <span>&middot; the tracker</span></b><p>The same scheduled job keeps your Smartsheet program tracker <em>current</em> &mdash; idempotent upsert-by-key behind an ops-only allowlist guard &mdash; so the PM dashboard is live while you&rsquo;re away. The <code>%ss_*</code> library. No AI.</p></div>
      <div class="comp slm"><b>LOCALMIND <span>&middot; optional language</span></b><p>An <em>optional</em> on-device SLM drafts the digest prose or triages free-text the deterministic code can&rsquo;t &mdash; ops-only, behind the loopback + validator + human-gate guardrails. The monitoring needs <strong>none</strong> of this; it is a convenience, not a dependency. The <code>%slm_*</code> library.</p></div>
    </div>
    <div class="callout win"><strong>Why this is the lowest-risk piece.</strong> The detection is pre-specified, deterministic SAS/R &mdash; the same logic you already validate, just scheduled and self-escalating. No cloud, no AI in the loop, no model to qualify. It <em>detects, packages, and pages</em>; humans decide. That is exactly the property a regulated shop wants from unattended automation.</div>
    <p>Below: the architecture, the checks, the alerting + escalation, the <a href="#onleave">covering-while-on-leave runbook</a> (the headline), the tracker, the optional language layer, the macro libraries, the safeguards, and IT readiness.</p>
  ` },

  { id: "watch", nav: "&#9654; Watch it work", html: `
    <h1>Watch it work &mdash; written in SAS, then a month of coverage</h1>
    <p class="lede">First, the monitoring backbone <em>written line by line and run</em> in SAS Enterprise Guide &mdash; in the Azure session where the study data actually lives. Then the on-leave scenario end to end: the daily job runs under a service account, a RED finding pages the covering biostatistician with an evidence packet, the tracker stays current, and the dead-man&rsquo;s switch guarantees you&rsquo;d know if it ever went quiet.</p>
    <div class="dl">
      <a class="btn" href="../sas_r_automation/SAS_R_Monitor_Screencast_narrated.mp4">&#9654;&nbsp; The monitor, written &amp; run in SAS &mdash; live screencast</a>
      <a class="btn" href="../sas_r_automation/SAS_R_OnLeave_Screencast_narrated.mp4">&#9654;&nbsp; Covering while on leave &mdash; live screencast</a>
      <a class="btn ghost" href="../sas_r_automation/SAS_R_OnLeave_Example_StepGuide.pdf">&#10515;&nbsp; Picture guide (PDF)</a>
    </div>
    <p>And the two companions in action:</p>
    <div class="dl">
      <a class="btn ghost" href="../smartsheet_sasr/SAS_R_Smartsheet_Screencast_narrated.mp4">&#9654;&nbsp; Smartsheet keeps itself current &mdash; live screencast</a>
      <a class="btn ghost" href="../slm_wiki/SLM_OnDevice_Example_narrated.mp4">&#9654;&nbsp; On-device language triage (optional)</a>
    </div>
    <h2>Every section, demonstrated on screen</h2>
    <p class="blurb">Each part of this wiki has its own live screencast &mdash; the actual SAS (or R) code written line by line in SAS Enterprise Guide 8.3 on the Azure desktop, and every icon clicked. No slides.</p>
    <div class="gal">
      <a class="gv" href="../sas_r_automation/SAS_R_Arch_Screencast_narrated.mp4"><b>&#9654; Architecture</b><span>The daily job wired in <code>tm_config.sas</code> &mdash; libraries, thresholds, recipients, schedule.</span></a>
      <a class="gv" href="../sas_r_automation/SAS_R_Macros_Screencast_narrated.mp4"><b>&#9654; The %tm_* library</b><span>Inside <code>tm_macros.sas</code>: the freshness gate, the roll-up, written line by line.</span></a>
      <a class="gv" href="../sas_r_automation/SAS_R_Checks_Screencast_narrated.mp4"><b>&#9654; The safety checks</b><span>The Hy&rsquo;s-Law AND-gate discipline and the CTCAE labs band &mdash; thresholds, not diagnoses.</span></a>
      <a class="gv" href="../sas_r_automation/SAS_R_Alerts_Screencast_narrated.mp4"><b>&#9654; Alerts &amp; escalation</b><span>The escalation matrix written, then the tier-2 route shown in the log.</span></a>
      <a class="gv" href="../sas_r_automation/SAS_R_RCompanion_Screencast_narrated.mp4"><b>&#9654; The R companion</b><span>Prototyping in RStudio on the laptop &mdash; synthetic, aggregate, never study data.</span></a>
      <a class="gv" href="../sas_r_automation/SAS_R_Language_Screencast_narrated.mp4"><b>&#9654; The optional language layer</b><span>The on-device SLM boxed in: loopback, a string-only schema, a human gate.</span></a>
      <a class="gv" href="../sas_r_automation/SAS_R_ITReady_Screencast_narrated.mp4"><b>&#9654; IT readiness</b><span>Scheduling the job under a service account in Windows Task Scheduler + the watchdog.</span></a>
    </div>
    <div class="callout tip"><b>The scenario:</b> you are out for three weeks. Each morning the job ingests the overnight EDC/lab/ECG exports, checks freshness first, runs the safety flags, and emails a digest to the support alias. On day 9 an eDISH point trips Hy&rsquo;s-Law screening &mdash; a tier-2 alert pages the covering biostatistician with a one-page evidence packet; they loop in the medical monitor, who makes the call. The tracker reflects it within the hour. You return to a complete trail, not a backlog.</div>
  ` },

  { id: "dashboard", nav: "Interactive dashboard", html: `
    <h1>The interactive dashboard &mdash; the backbone made visible</h1>
    <p class="lede">A self-contained, click-through dashboard on a <strong>synthetic, longitudinal</strong> CP-101 run (22 participants &times; 8 visits), presented as a <strong>dark operations console</strong> (status pill, a what-if <em>scenario simulator</em>, cohort <em>ranking bars</em>, a freshness strip, and a network view). It is a <em>teaching view</em> of what the deterministic loop produces &mdash; not a production console, not a record. Open it in any browser; nothing leaves the file.</p>
    <div class="dl">
      <a class="btn" href="TRIALMON_Dashboard.html">&#9656;&nbsp; Open the TRIALMON dashboard</a>
      <a class="btn ghost" href="TRIALMON_Dashboard_Wiki.html">&#128214;&nbsp; The Field Guide (how to read it)</a>
    </div>
    <div class="callout rule"><strong>What it is and isn&rsquo;t.</strong> It runs on <strong>synthetic data</strong> &mdash; no PHI, no real participants, no unblinding. Every flag is a <em>screening prompt</em>, never a determination and never a reportable number; reported numbers (incidence tables, the ICH&nbsp;E14 table, central reads, MTD, final disposition) come only from validated tools (Phoenix WinNonlin, Pinnacle&nbsp;21). It is an <em>illustration</em> of the backbone, not the validated job itself.</div>
    <div class="callout honest"><strong>One tab is fenced off as exploratory.</strong> An <em>&ldquo;Exploratory &#9656; structure&rdquo;</em> section adds unsupervised <b>persistence-homology</b> trial-structure analytics &mdash; H₀ clustering of participants in safety-feature space (the &beta;₀ curve + barcode + a PCA embedding) and a site network &mdash; for hypothesis generation only. It is <b>explicitly NOT part of the validated safety backbone</b>: it never produces a flag, a determination, or a number, and nothing there escalates study status. The deterministic-flag participants happen to surface as topological outliers there too &mdash; an independent structural cross-check, not a second opinion that decides anything.</div>
    <h2>What it shows &mdash; seven validated sections + one exploratory, per-visit detail</h2>
    <p>A section sub-nav (Overview &middot; Hepatic &middot; Cardiac &middot; Labs&nbsp;&amp;&nbsp;Vitals &middot; AE&nbsp;&amp;&nbsp;DLT &middot; Disposition &middot; Participants) with a KPI tile strip and a standing governance ribbon. Every per-visit series is built so its worst on-treatment value equals the original summary &mdash; nothing contradicts the headline plots.</p>
    <ul>
      <li><b>Overview</b> &mdash; KPI tiles; a prioritized <em>attention worklist</em> (every open AMBER/RED screening flag, click-to-open); a first-class <em>data-freshness/SLA</em> panel (stale-green &rarr; RED); and a <em>study heatmap</em> (participant &times; visit, worst flag &mdash; the &ldquo;when did it start&rdquo; view).</li>
      <li><b>Hepatic</b> &mdash; the eDISH scatter now with per-visit <em>history trails</em> (where a participant has been, not a prediction); per-visit <em>LFT trajectories</em>; an <em>R-ratio pattern</em> strip; and a peak/baseline/trend table. The near-miss (high ALT, bilirubin under 2&times;) is correctly kept GREEN by the AND-gate at every visit.</li>
      <li><b>Cardiac</b> &mdash; per-visit QTcF (Fridericia) trajectory with a cohort-median band, and an ICH&nbsp;E14 categorical outlier <em>census</em> (clearly labelled &ldquo;screening census &mdash; not the E14 table&rdquo;; baseline-watch shown distinctly).</li>
      <li><b>Labs &amp; Vitals</b> &mdash; a baseline&rarr;worst <em>lab-shift grid</em> (CTCAE-style screening bands, not adjudicated grades), hematology trajectories, a renal fold-rise panel (eGFR an estimate), and a vitals/orthostatic PCS board (operational context).</li>
      <li><b>AE &amp; DLT</b> &mdash; a 3+3 escalation <em>state ladder</em> (trigger / decision-pending only &mdash; the SRC decides, never the dashboard), an AE SOC&times;CTCAE-grade matrix (severity and seriousness kept separate), and an AE onset swimlane vs study day.</li>
      <li><b>Disposition</b> &mdash; an enrollment/disposition funnel, RBQM KRI tiles + a protocol-deviation log, and a visit-compliance matrix (a missed visit is routed to a human, never read as &ldquo;fine&rdquo;).</li>
      <li><b>Participants</b> &mdash; a sortable/filterable/searchable roster; and on <b>click anywhere</b>, an evidence-packet modal with per-visit sparkline trajectories.</li>
    </ul>
    <div class="callout tip"><strong>A full field guide ships with it.</strong> The dashboard comes with a dedicated, operating-depth <a href="TRIALMON_Dashboard_Wiki.html">Field Guide</a> &mdash; a 15-section reference that documents every section, panel, threshold and governance rule, the synthetic data model, and a guided tour of the planted teaching cases. Read it next to the dashboard the first time through.</div>
  ` },

  { id: "arch", nav: "Architecture", html: `
    <h1>Architecture &mdash; the daily job</h1>
    <p class="lede">One orchestrated batch job (<code>monitor_driver.sas</code>), scheduled under a <strong>service account</strong>, runs the loop. Order matters: <strong>freshness gates everything</strong>, and every fragile step is wrapped to <strong>fail loud</strong>.</p>
    <div class="dl"><a class="btn" href="../sas_r_automation/SAS_R_Arch_Screencast_narrated.mp4">&#9654;&nbsp; Watch it wired in config (tm_config.sas) &mdash; live screencast</a></div>
    <div class="flow">
      ${["Ingest &mdash; resolve the newest dated exports (<code>%tm_latest</code>)", "Freshness gate &mdash; is each feed fresh? <b>a dead feed flags loudest; stale-green is worse than red</b> (<code>%tm_freshness</code>)", "Guard &mdash; assert expected columns exist, are numeric, pass a range-sanity check (<code>%tm_guard</code>)", "Checks &mdash; the pre-specified deterministic safety + operational flags (<code>%tm_chk_*</code>)", "Roll-up &mdash; worst severity GREEN&lt;AMBER&lt;RED (<code>%tm_status</code>)", "Digest &mdash; email the daily summary to the support alias (<code>%tm_digest</code>)", "Tier-2 alert &mdash; on any <em>de-duplicated</em> RED, page with an evidence packet (<code>%tm_alert</code>)", "Heartbeat &mdash; write a run record, always, even on failure (<code>%tm_heartbeat</code>)"].map((t, i, a) => `<div class="node${/RED/.test(t) ? " red" : /Freshness/.test(t) ? " amb" : ""}"><span class="n">${i + 1}</span>${t}</div>${i < a.length - 1 ? '<div class="arr">&darr;</div>' : ""}`).join("")}
    </div>
    <div class="callout key"><strong>The independent dead-man&rsquo;s switch.</strong> <code>tm_watchdog.sh</code> runs on a <em>different host and account</em>, reads the heartbeat, and screams if the job didn&rsquo;t run, ran late, or ran on stale data. The thing most likely to fail silently is the scheduler itself &mdash; so the watchdog is the control that makes &ldquo;no news&rdquo; trustworthy. <strong>No email is itself a signal.</strong></div>
    <h2>The two branches off the same job</h2>
    <ul>
      <li><b>Tracker (SHEETLINK):</b> after the checks, <code>%ss_*</code> upserts the run status + open flags into the Smartsheet tracker &mdash; idempotent by key, ops-only columns allowlisted &mdash; so the PM view is live. See <a href="#tracker">Keeping the tracker current</a>.</li>
      <li><b>Language (LOCALMIND, optional):</b> if enabled, an on-device SLM drafts the digest prose from the already-structured rows &mdash; never deciding what to include. See <a href="#language">The optional language layer</a>.</li>
    </ul>
  ` },

  { id: "checks", nav: "The checks", html: `
    <h1>The monitoring checks &mdash; deterministic flags</h1>
    <p class="lede">Each check reads validated analysis data and writes a flagged dataset with a <code>sev</code> column (GREEN / AMBER / RED) against <strong>pre-specified thresholds</strong>. They are <strong>screening flags, not diagnoses</strong> &mdash; a RED is a prompt for a human, not a finding.</p>
    <div class="dl"><a class="btn" href="../sas_r_automation/SAS_R_Checks_Screencast_narrated.mp4">&#9654;&nbsp; Watch the AND-gate discipline &amp; the CTCAE band &mdash; live screencast</a></div>
    <table class="cat"><thead><tr><th>Check</th><th>What it flags</th><th>Default thresholds</th></tr></thead><tbody>
      <tr><td><code>%tm_chk_hyslaw</code></td><td>eDISH / Hy&rsquo;s-Law screening: ALT or AST &gt;&times;ULN <b>and</b> TBili &gt;&times;ULN</td><td>ALT/AST 3&times;, TBili 2&times;, ALP 2&times; &mdash; <i>screening flag, not a diagnosis</i></td></tr>
      <tr><td><code>%tm_chk_qtcf</code></td><td>QTcF absolute &amp; change-from-baseline tiers (ICH E14)</td><td>RED abs 500 / &Delta;60; AMBER abs 480 / &Delta;30</td></tr>
      <tr><td><code>%tm_chk_ae</code></td><td>AE/SAE running tally by cohort &mdash; participant-incidence + event counts</td><td>study-specified</td></tr>
      <tr><td><code>%tm_chk_dlt</code></td><td>Candidate-DLT tally vs the 3+3 rule (against an <b>adjudicated</b> DLT flag + completed window)</td><td><i>does not make the escalation decision</i></td></tr>
      <tr><td><code>%tm_chk_labs</code></td><td>Out-of-range / potentially-clinically-significant / shift flags</td><td>study-specified</td></tr>
    </tbody></table>
    <div class="callout honest"><strong>Two disciplines that make unattended checks safe.</strong> <b>Fail loud</b> &mdash; <code>%tm_assert</code> wraps every fragile step; on a false condition it sets the return code, forces status to ERROR, emails the backup, and writes a FAILED heartbeat, so a broken run is never a silent green. <b>Guard the inputs</b> &mdash; <code>%tm_guard</code> asserts the expected columns exist, are numeric, and pass a range-sanity check before any threshold runs, catching a unit change or a renamed variable that would otherwise sail through. And the <b>freshness gate runs first</b>: a missing or dead feed flags <em>loudest</em>, because <strong>stale-green is the most dangerous state</strong> &mdash; it looks fine and isn&rsquo;t.</div>
  ` },

  { id: "alerts", nav: "Alerts &amp; escalation", html: `
    <h1>Alerting, paging &amp; escalation</h1>
    <p class="lede">Two tiers, de-duplicated so a standing RED pages <em>once</em>, plus a heartbeat that makes silence meaningful.</p>
    <div class="dl"><a class="btn" href="../sas_r_automation/SAS_R_Alerts_Screencast_narrated.mp4">&#9654;&nbsp; Watch the escalation matrix written &amp; routed &mdash; live screencast</a></div>
    <ul>
      <li><b>Tier 1 &mdash; the daily digest</b> (<code>%tm_digest</code>): every run emails a summary to the support alias, RED/AMBER/GREEN by section. Routine awareness.</li>
      <li><b>Tier 2 &mdash; the urgent alert</b> (<code>%tm_alert</code>): on any <em>new</em> de-duplicated RED, page the support alias + a named backup with a one-page <b>evidence packet</b> (<code>%tm_evidence</code> &mdash; the eDISH scatter with reference lines + the participant&rsquo;s lab trajectory) and the medical monitor&rsquo;s name + phone. Enough to act, not to decide.</li>
      <li><b>The heartbeat</b> (<code>%tm_heartbeat</code>): a run record written <em>always</em>, success or failure &mdash; the input to the watchdog.</li>
    </ul>
    <h2>Escalation matrix</h2>
    <table class="cat"><thead><tr><th>Colour</th><th>Means</th><th>Who acts</th></tr></thead><tbody>
      <tr><td><b style="color:#35C07E">GREEN</b></td><td>Checks ran, fresh data, nothing tripped</td><td>No action &mdash; the digest is the record</td></tr>
      <tr><td><b style="color:#D9A94F">AMBER</b></td><td>A tier threshold crossed, or a feed is ageing</td><td>Covering biostatistician reviews same day</td></tr>
      <tr><td><b style="color:#E0857A">RED</b></td><td>A safety screen tripped, or a feed is dead/stale</td><td>Page &rarr; covering biostatistician loops in the medical monitor, who makes the call</td></tr>
      <tr><td><b>NO EMAIL</b></td><td>The job didn&rsquo;t run (the worst case)</td><td>The watchdog pages the backup &mdash; treat as RED until proven otherwise</td></tr>
    </tbody></table>
    <div class="callout key"><strong>Reportable vs signal-only.</strong> A flag is an internal <em>signal</em> to look &mdash; it is not a reportable safety determination. Reportability (expedited SAE, DSUR, etc.) is the medical monitor&rsquo;s and sponsor&rsquo;s decision through the validated process; the automation accelerates <em>awareness</em>, never the regulatory call.</div>
  ` },

  { id: "onleave", nav: "&#9992; Covering while on leave", html: `
    <h1>Covering while out on leave &mdash; the runbook</h1>
    <p class="lede">The headline use case. Hand the covering biostatistician one page: what runs and when, what the colours mean, who they call, and what to do if the email ever stops. Everything runs under the service account <code>SVC-BIOSTAT</code>, never a personal login &mdash; so it does not break the day you turn off your laptop.</p>
    <div class="callout key"><strong>What runs, and when.</strong> The daily monitoring job at a fixed time (e.g. 06:00, weekdays) under <code>SVC-BIOSTAT</code>; the watchdog ~30&nbsp;min later on a <em>different</em> host; the tracker upsert in the same job. The covering biostatistician is the named <code>backup</code> on every tier-2 alert and every watchdog page for the leave window &mdash; one line in <code>tm_config.sas</code>, not a code change.</div>
    <h2>A worked three-week leave</h2>
    <ol>
      <li><b>Before you go:</b> set <code>backup=</code> to the covering biostatistician and confirm the medical monitor&rsquo;s contact in <code>tm_config.sas</code>; send them this runbook + the picture guide; run the job once and confirm the digest, a test alert, and a heartbeat all arrive.</li>
      <li><b>Days 1&ndash;8:</b> GREEN digests each morning; the tracker stays current; the covering biostatistician does nothing but glance.</li>
      <li><b>Day 9:</b> an eDISH point trips Hy&rsquo;s-Law screening &mdash; a tier-2 alert pages the covering biostatistician with the evidence packet; they review, loop in the medical monitor, who makes the call; the tracker reflects the open flag within the hour.</li>
      <li><b>Day 14:</b> an overnight feed fails to land &mdash; the freshness gate flags it RED and the watchdog confirms the job ran but on a dead feed; IT restores the export; no silent gap.</li>
      <li><b>On return:</b> a complete, dated trail of digests, the one alert, the resolution, and the tracker history &mdash; not a backlog to reconstruct.</li>
    </ol>
    <div class="callout honest"><strong>Accountability does not go on leave.</strong> The automation covers <em>vigilance and logistics</em> &mdash; it never covers the <em>decision</em>. A named covering biostatistician and the medical monitor own every call while you are out; the runbook makes the hand-off explicit so there is never an ambiguous &ldquo;who&rsquo;s watching&rdquo; gap. Tune thresholds before leave to avoid alert fatigue, but never widen a safety threshold to silence a page.</div>
    <div class="dl"><a class="btn" href="../sas_r_automation/SAS_R_Coverage_Runbook.pdf">&#10515;&nbsp; The Coverage Runbook (PDF) &mdash; hand this to your cover</a></div>
  ` },

  { id: "tracker", nav: "Keeping the tracker current", html: `
    <h1>Keeping the Smartsheet tracker current &mdash; SHEETLINK</h1>
    <p class="lede">So the PM&rsquo;s program dashboard is live while you&rsquo;re away, the same scheduled job upserts status into Smartsheet &mdash; deterministically, no AI.</p>
    <ul>
      <li><b>Idempotent upsert-by-key:</b> <code>%ss_*</code> matches each row by a stable key and updates-or-inserts, so re-runs never duplicate and a re-processed day is a no-op.</li>
      <li><b>Ops-only allowlist guard:</b> only an allowlisted set of operational columns can be written &mdash; the automation can never touch a column it shouldn&rsquo;t, by construction.</li>
      <li><b>Token from a secret, never logged:</b> the Smartsheet token comes from an environment variable / secret store, never hard-coded and never written to a log.</li>
    </ul>
    <div class="callout win">Independently SAS-reviewed (three defects found and fixed). The tracker shows <em>operational</em> status only &mdash; never a reported number, never patient-level data.</div>
    <div class="dl"><a class="btn ghost" href="../smartsheet_sasr/Smartsheet_SASR.html">Open the SHEETLINK wiki</a><a class="btn ghost" href="../smartsheet_sasr/macro_library/README.pdf">Macro README (PDF)</a></div>
  ` },

  { id: "language", nav: "Optional language layer", html: `
    <h1>The optional on-device language layer &mdash; LOCALMIND</h1>
    <div class="callout honest"><strong>Optional, and ops-only.</strong> The monitoring needs <strong>no AI</strong> &mdash; the checks, the digest structure, the tracker, and every number are deterministic SAS/R. The on-device SLM is a <em>convenience</em> for the language tasks code can&rsquo;t do (re-phrasing a digest, triaging a free-text comment), and it runs behind the same guardrails as the rest of the program: an <strong>on-prem frozen model on loopback</strong>, schema-constrained output, an allowlist validator, and a <strong>human-gated parse-guard</strong>. It never produces a number and never decides what the digest includes.</div>
    <p>If you enable it, the <code>%slm_*</code> library (loopback-guard <code>%slm_init</code>, schema-constrained <code>%slm_chat</code>, allowlist <code>%slm_validate</code>, <code>%slm_classify</code>) is the engine, and the standard honesty applies: a small local model hallucinates, so its trustworthiness comes from the discipline around it, not from being local. See the dedicated on-device wiki for the full treatment.</p>
    <div class="dl"><a class="btn" href="../sas_r_automation/SAS_R_Language_Screencast_narrated.mp4">&#9654;&nbsp; Watch it boxed in (loopback + string-only schema + human gate) &mdash; live screencast</a></div>
    <div class="dl"><a class="btn ghost" href="../slm_wiki/SLM_SASR_TrialOps.html">On-device SLM &times; SAS/R wiki</a><a class="btn ghost" href="../slm_wiki/IT_SLM_Enablement_Runbook.pdf">IT enablement runbook</a></div>
  ` },

  { id: "macros", nav: "The macro libraries", html: `
    <h1>The macro libraries</h1>
    <p class="lede">Three deterministic SAS libraries (each with an R companion), copy-paste ready, each with a per-study config so a second study or a rotating monitor is one file, not a code edit. Base SAS 9.4; no third-party packages.</p>
    <div class="dl"><a class="btn" href="../sas_r_automation/SAS_R_Macros_Screencast_narrated.mp4">&#9654;&nbsp; Watch inside the %tm_* library &mdash; live screencast</a><a class="btn ghost" href="../sas_r_automation/SAS_R_RCompanion_Screencast_narrated.mp4">&#9654;&nbsp; The R companion on the laptop (RStudio)</a></div>
    <table class="cat"><thead><tr><th>Library</th><th>Driver + key files</th><th>What it does</th></tr></thead><tbody>
      <tr><td><b>TRIALMON</b> <code>%tm_*</code></td><td><code>tm_macros.sas</code> &middot; <code>monitor_driver.sas</code> &middot; <code>tm_config.sas</code> &middot; <code>tm_watchdog.sh</code> &middot; <code>tm_companion.R</code></td><td>The monitoring loop: init, latest, freshness, guard, the safety checks, status, digest, alert, evidence, heartbeat &mdash; plus the independent watchdog.</td></tr>
      <tr><td><b>SHEETLINK</b> <code>%ss_*</code></td><td><code>ss_macros.sas</code> &middot; <code>tracker_update.sas</code> &middot; <code>ss_config.sas</code> &middot; <code>ss_companion.R</code></td><td>Idempotent upsert-by-key into Smartsheet behind an ops-only allowlist guard; token from a secret.</td></tr>
      <tr><td><b>LOCALMIND</b> <code>%slm_*</code></td><td><code>slm_macros.sas</code> &middot; <code>triage_driver.sas</code> &middot; <code>slm_config.sas</code> &middot; <code>slm_companion.R</code></td><td>(Optional) the on-device language layer: loopback guard, schema-constrained call, allowlist validator, classify.</td></tr>
    </tbody></table>
    <div class="callout key"><b>Config, not code.</b> <code>tm_config.sas</code> holds the per-study constants &mdash; paths, recipients, the medical monitor, feeds, thresholds &mdash; <code>%include</code>d before the driver. A new study, a rotating medical monitor, or a leave-coverage backup is a one-line change, change-controlled like any study program.</div>
    <div class="dl"><a class="btn ghost" href="../sas_r_automation/macro_library/TRIALMON_Macro_Library_README.pdf">TRIALMON README</a><a class="btn ghost" href="../smartsheet_sasr/macro_library/README.pdf">SHEETLINK README</a><a class="btn ghost" href="../slm_wiki/macro_library/README.pdf">LOCALMIND README</a></div>
  ` },

  { id: "gov", nav: "&#9888; Safeguards &amp; governance", html: `
    <h1>Safeguards &amp; governance</h1>
    <div class="callout rule"><strong>Detect, package, page &mdash; never decide.</strong> The automation surfaces pre-specified deterministic flags and routes them to people. It does <strong>not</strong> triage, interpret, adjudicate, or auto-act on safety. The medical monitor and the covering biostatistician make every call; reportability is the validated regulatory process, not a flag.</div>
    <h2>The controls that make unattended automation defensible</h2>
    <ul>
      <li><b>Deterministic, validated logic.</b> The checks are the same threshold logic you already validate &mdash; just scheduled. Validate the threshold programs <em>and</em> the scheduling wrapper as study programs (GxP, risk-based CSV); version-control the config and any threshold change.</li>
      <li><b>Fail loud + guard the inputs.</b> <code>%tm_assert</code> turns any broken step into a loud ERROR + a backup email + a FAILED heartbeat; <code>%tm_guard</code> catches a unit change or renamed variable before a threshold runs. A broken run is never a silent green.</li>
      <li><b>Freshness first.</b> Stale-green is the most dangerous state; a dead feed flags loudest.</li>
      <li><b>The independent watchdog.</b> A dead-man&rsquo;s switch on a different host/account makes &ldquo;no email&rdquo; a signal, not a guess.</li>
      <li><b>Service account, not a person.</b> The job runs under <code>SVC-BIOSTAT</code> so coverage doesn&rsquo;t depend on anyone&rsquo;s laptop; the backup is named per leave window.</li>
      <li><b>Numbers stay validated.</b> Anything <em>reported</em> is independently double-programmed and comes from validated tools (Phoenix WinNonlin, Pinnacle&nbsp;21, the validated pipeline). A flag is never a reported value; the optional SLM never produces one.</li>
    </ul>
  ` },

  { id: "itready", nav: "&#128268; IT readiness", html: `
    <h1>IT readiness &mdash; the lowest-friction path in the program</h1>
    <p class="lede">For the deterministic monitoring + tracker, the asks are small and entirely on-prem &mdash; no cloud, no AI to qualify. Hand IT this list.</p>
    <div class="dl"><a class="btn" href="../sas_r_automation/SAS_R_ITReady_Screencast_narrated.mp4">&#9654;&nbsp; Watch it scheduled under a service account (Task Scheduler) &mdash; live screencast</a></div>
    <div class="callout win"><b>What to ask IT for (deterministic core):</b>
      <ul style="margin:6px 0 0">
        <li>A <b>service / group account</b> (<code>SVC-BIOSTAT</code>) to own the scheduled job and read the analysis libraries &mdash; so the automation never orphans on PTO.</li>
        <li><b>Batch scheduling</b> (Windows Task Scheduler / cron) for the daily job, and a <b>second host/account</b> for the watchdog dead-man&rsquo;s switch.</li>
        <li>An <b>internal SMTP relay</b> for the digest + alerts (no external mail).</li>
        <li>Read access to the data exports + a state directory for de-duplication and heartbeats.</li>
        <li>For the tracker: a <b>Smartsheet API token in a secret store</b> (never hard-coded).</li>
      </ul>
    </div>
    <div class="callout honest"><b>Only if you enable the optional language layer</b> do the heavier asks apply &mdash; an on-prem workstation/VM, a signed runtime + a frozen open-weight model, a licence review, and the GAMP-5 qualification of a non-deterministic component (see the <a href="../slm_wiki/IT_SLM_Enablement_Runbook.pdf">SLM enablement runbook</a>). The monitoring core needs none of it; keep the two requests separate so the low-risk piece isn&rsquo;t held up by the AI one.</div>
  ` },

  { id: "faq", nav: "Maintenance &amp; FAQ", html: `
    <h1>Maintenance &amp; FAQ</h1>
    <h2>Monthly upkeep (~15 min)</h2>
    <ul>
      <li>Skim the heartbeat log for missed/late runs; confirm the watchdog fired in any test.</li>
      <li>Review alert volume &mdash; persistent AMBER noise means a threshold needs a (change-controlled) review, not silencing.</li>
      <li>Confirm <code>tm_config.sas</code> recipients + the medical monitor + the current leave backup are correct.</li>
    </ul>
    <h2>FAQ</h2>
    <p><b>Does it make safety decisions?</b> No. It detects, packages, and pages pre-specified deterministic flags; humans decide. It never auto-acts on safety and never adjudicates.</p>
    <p><b>Is there AI in the loop?</b> Not in the monitoring &mdash; it is deterministic SAS/R. The on-device SLM is an optional, ops-only language convenience behind guardrails; the numbers and the flags never depend on it.</p>
    <p><b>What if the job silently dies?</b> The independent watchdog pages the backup &mdash; <em>no email is itself a signal</em>. That is the whole point of the heartbeat + dead-man&rsquo;s switch.</p>
    <p><b>Does it cost anything?</b> The deterministic core is just scheduled SAS/R on a service account + internal SMTP &mdash; no licences beyond what you have. Only the optional SLM adds a real (validation + ownership) cost.</p>
    <p><b>Is it validated?</b> Validate the threshold logic + the scheduling wrapper as study programs, risk-based; version-control thresholds; double-program anything reported. The automation is decision-support and a logistics aid, not a record generator.</p>
    <p><b>How does coverage actually work while I&rsquo;m out?</b> See the <a href="#onleave">coverage runbook</a> &mdash; service-account scheduling, a named backup per leave window, the escalation matrix, and the dead-man&rsquo;s switch, all on one page you hand to your cover.</p>
  ` },
];

const css = `
:root{--steel:#6FA0DC;--ink:#E7ECF8;--muted:#9AA6C8;--line:#272D4D;--panel:#181D38;--green:#35C07E;--amber:#D9A94F;--red:#E0857A;--bg:#0E1124}
*{box-sizing:border-box}body{margin:0;font-family:-apple-system,Segoe UI,Calibri,Arial,sans-serif;color:var(--ink);background:var(--bg);line-height:1.55}
#wrap{display:flex;min-height:100vh}
#side{width:288px;flex:0 0 288px;background:#142433;color:#fff;position:sticky;top:0;height:100vh;overflow:auto;padding:22px 0;border-right:1px solid #2a2f52}
#side .brand{padding:0 22px 14px;border-bottom:1px solid #294056;margin-bottom:10px}
#side .brand b{font-family:Georgia,serif;font-size:16.5px;line-height:1.25;display:block}#side .brand span{display:block;color:#9fb6cc;font-size:11px;margin-top:5px}
#side .brand .tag{display:inline-block;margin-top:9px;background:var(--green);color:#fff;font-size:10px;font-weight:800;letter-spacing:1px;padding:2px 8px;border-radius:20px}
#search{margin:0 16px 12px;width:calc(100% - 32px);padding:8px 10px;border-radius:8px;border:1px solid #2f4a63;background:#1d3346;color:#fff;font-size:13px}
#side a{display:block;color:#c4d4e2;text-decoration:none;padding:8px 22px;font-size:13.5px;border-left:3px solid transparent}
#side a:hover{background:#1d3346}#side a.active{color:#fff;border-left-color:var(--green);background:#1d3346;font-weight:600}
#main{flex:1;max-width:990px;margin:0 auto;padding:34px 50px 90px}
section{display:none}section.show{display:block;animation:f .2s}@keyframes f{from{opacity:.35}to{opacity:1}}
h1{font-family:Georgia,serif;color:var(--ink);font-size:29px;margin:0 0 14px;line-height:1.16}
h2{font-family:Georgia,serif;color:var(--steel);font-size:20px;margin:26px 0 10px;border-bottom:1px solid var(--line);padding-bottom:5px}
.lede{font-size:17px;color:#C3CCE4}
p,li{font-size:15px}ul,ol{padding-left:22px}li{margin:5px 0}
a{color:var(--steel)}
code{background:#20284a;color:#A9C6F2;padding:1px 6px;border-radius:5px;font-family:Consolas,monospace;font-size:12.5px}
.muted{color:var(--muted);font-size:13px}
.callout{border-radius:10px;padding:13px 16px;margin:16px 0;font-size:14.5px}
.callout.rule{background:#2A1614;border-left:4px solid var(--red)}
.callout.honest{background:#2A2412;border-left:4px solid var(--amber)}.callout.honest b,.callout.honest strong{color:#D9A94F}
.callout.win{background:#11261C;border-left:4px solid var(--green)}
.callout.key{background:#141E2E;border-left:4px solid var(--steel)}
.callout.tip{background:#0F262A;border-left:4px solid #2CAEB8}
.grid3{display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px;margin:14px 0}
.comp{border:1px solid var(--line);border-top:5px solid var(--steel);border-radius:10px;padding:13px 15px;background:var(--panel);box-shadow:0 2px 7px rgba(0,0,0,.25)}
.comp.tm{border-top-color:var(--steel)}.comp.ss{border-top-color:var(--green)}.comp.slm{border-top-color:var(--amber)}
.comp b{font-size:15px}.comp b span{font-weight:400;color:var(--muted);font-size:12px}.comp p{font-size:13px;color:#C3CCE4;margin:6px 0 0}
.flow{margin:16px 0}
.node{background:var(--panel);border:1px solid var(--line);border-left:5px solid var(--steel);border-radius:9px;padding:10px 14px;font-size:14px;display:flex;gap:11px;align-items:center}
.node.amb{border-left-color:var(--amber)}.node.red{border-left-color:var(--red)}
.node .n{flex:0 0 22px;height:22px;border-radius:50%;background:var(--steel);color:#fff;font-size:12px;font-weight:700;display:flex;align-items:center;justify-content:center}
.node.amb .n{background:var(--amber)}.node.red .n{background:var(--red)}
.arr{text-align:center;color:#a9b6c4;font-size:17px;margin:2px 0}
table.cat{border-collapse:collapse;width:100%;margin:13px 0;font-size:14px}
table.cat th,table.cat td{border:1px solid var(--line);padding:8px 11px;text-align:left;vertical-align:top}
table.cat th{background:#142433;color:#fff;font-weight:600}table.cat tr:nth-child(even) td{background:var(--panel)}
.dl{display:flex;gap:12px;margin:16px 0;flex-wrap:wrap}
.btn{display:inline-block;background:var(--steel);color:#fff;text-decoration:none;font-weight:700;font-size:14px;padding:11px 18px;border-radius:9px}
.btn.ghost{background:transparent;color:var(--steel);border:1.5px solid var(--steel)}.btn:hover{opacity:.92}
.blurb{color:var(--muted);font-size:14px;margin:4px 0 12px}
.gal{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:14px 0}
.gv{display:block;border:1px solid var(--line);border-left:4px solid var(--steel);border-radius:10px;padding:13px 16px;background:var(--panel);text-decoration:none;color:inherit}
.gv:hover{background:var(--panel)}
.gv b{display:block;color:var(--steel);font-size:15px;margin-bottom:4px}
.gv span{font-size:13px;color:#C3CCE4}
@media(max-width:760px){.gal{grid-template-columns:1fr}}
.footer{margin-top:42px;padding-top:16px;border-top:1px solid var(--line);color:var(--muted);font-size:12px}
@media(max-width:760px){.grid3{grid-template-columns:1fr}}
`;

const js = A.JS("start");
const nav = sections.map(s => `<a href="#${s.id}" data-t="${s.id}">${s.nav}</a>`).join("\n");
const body = sections.map(s => `<section id="${s.id}" aria-label="${String(s.nav).replace(/&[^;]+;/g, "").replace(/<[^>]+>/g, "").trim()}">${s.html}<div class="footer">SAS/R Monitoring &amp; On-Leave Coverage &middot; deterministic, no-AI monitoring &mdash; detect, package, page; humans decide &middot; validated tools &amp; double-programming own every reported number &middot; the optional on-device SLM is ops-only.</div></section>`).join("\n");

const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SAS/R Monitoring &amp; On-Leave Coverage - a dedicated wiki</title><style>${css}</style></head>
<body><div id="wrap">
<nav id="side"><div class="brand"><b>SAS/R Monitoring<br>&amp; On-Leave Coverage</b><span>Deterministic scheduled SAS/R that watches the trial &amp; keeps the tracker current &mdash; so nothing slips while you&rsquo;re out</span><span class="tag">FOR BIOSTATISTICIANS</span></div>
<input id="search" placeholder="Search the wiki..." autocomplete="off">
${nav}</nav>
<main id="main">${body}</main></div>
<script>${js}</script></body></html>`;

fs.writeFileSync(__dirname + "/SASR_Monitoring_Coverage_Wiki.html", A.accessibleShell(html));
console.log("WROTE SASR_Monitoring_Coverage_Wiki.html (" + sections.length + " sections)");
