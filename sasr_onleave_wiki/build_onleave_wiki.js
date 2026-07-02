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

// Standalone, self-contained wiki: the SAS/R "Coverage while on leave" playbook (the on-leave companion example).
// Print-disability friendly: skip link, keyboard focus, text-size control, reduced-motion, a print stylesheet
// that linearises ALL sections, descriptive alt text, and a full video transcript.
const fs = require("fs");
const narration = require("../sas_r_automation/onleave_notes.js");
const captions = ["Intro", "Before leaving — the setup", "Week 1 — the GREEN digest & heartbeat", "Week 2 — the AMBER enrollment dip", "Week 3 — the RED urgent alert", "Week 3 — the evidence & escalation", "Week 4 — the audit trail", "The four safeguards", "The bottom line"];
const transcriptHtml = narration.map((t, i) => `<h2>${i + 1}. ${captions[i] || "Part " + (i + 1)}</h2><p>${t}</p>`).join("");
const sections = [
  { id: "start", nav: "Start here", html: `
    <h1>Coverage while on leave &mdash; a SAS/R playbook</h1>
    <p class="lede">Going on leave for a month? This playbook sets up <strong>deterministic, automated trial monitoring in SAS and/or R</strong> so monitoring never stops, the covering colleague gets the right updates, escalation is automatic, and your manager has <strong>peace of mind</strong> &mdash; with <strong>no AI, no new tools, and no PHI egress</strong>, all inside the existing validated environment.</p>
    <div class="callout warn"><strong>The honest framing.</strong> This <strong>detects, packages, and emails</strong> pre-specified deterministic flags &mdash; counts, thresholds, deltas, run failures &mdash; to a human, reproducibly. It does <strong>not</strong> triage, interpret, or judge. A flag is a prompt for a human; the medical monitor and the covering biostatistician make every call. Necessary, not sufficient &mdash; and that is the point: it&rsquo;s the layer you can ship <em>today</em>.</div>
    <h2>What this playbook gives you</h2>
    <ol>
      <li>A <strong>pre-departure checklist</strong> &mdash; schedule the already-validated programs under a service account.</li>
      <li>A <strong>two-tier notification</strong> design &mdash; a daily digest + an urgent threshold alert &mdash; with a heartbeat so silence is never assumed.</li>
      <li>A ready <strong>macro library</strong> (<code>tm_macros.sas</code> + a driver, and an R companion) for maximum ease of automation.</li>
      <li>A <strong>coverage runbook</strong> to hand your support and your manager.</li>
    </ol>
    <p>See it run for a full month in <a href="#watch">Watch it work</a>.</p>
  ` },
  { id: "setup", nav: "Before you leave", html: `
    <h1>Before you leave &mdash; the pre-departure checklist</h1>
    <p>You don&rsquo;t write new code &mdash; you <b>schedule</b> the monitoring programs that already run on demand.</p>
    <table>
      <tr><th>&#10003;</th><th>Item</th><th>Why</th></tr>
      <tr><td>&#9633;</td><td>Run everything under a <b>service / functional account</b> (e.g. <code>SVC-BIOSTAT</code>) &mdash; not your personal login.</td><td>Your credentials/VPN go idle on leave; a personal-owned job dies the moment they do. <b>The #1 silent-failure cause.</b></td></tr>
      <tr><td>&#9633;</td><td>Confirm the service account has the <b>SAS licence, share access, and SMTP relay rights</b>.</td><td>Verify before you go, not after a missed run.</td></tr>
      <tr><td>&#9633;</td><td>Schedule the jobs (Task Scheduler / cron): <b>02:00</b> refresh+freshness, <b>06:00</b> safety scan, <b>07:00</b> digest, <b>Fri 16:00</b> weekly + manager one-pager, <b>on-event</b> alert.</td><td>Moves them from &ldquo;run when I remember&rdquo; to &ldquo;run on a clock.&rdquo;</td></tr>
      <tr><td>&#9633;</td><td>Set <b>thresholds</b> (KRIs/QTLs/DLT/Hy&rsquo;s-Law/QTcF) to the protocol&rsquo;s pre-specified values.</td><td>Deterministic flags must be pre-specified to stay defensible.</td></tr>
      <tr><td>&#9633;</td><td>Set <b>recipients</b>: primary + <b>backup</b> + a role alias; the medical monitor&rsquo;s name/number; the PM; cc your inbox for the return.</td><td>So a 6 a.m. alert never depends on one inbox.</td></tr>
      <tr><td>&#9633;</td><td>Hand over the <a href="#runbook"><b>coverage runbook</b></a> (PDF) to support, cc the manager.</td><td>Plain-language GREEN/AMBER/RED, who does what, the honest limit.</td></tr>
      <tr><td>&#9633;</td><td>Do a <b>dry run</b> the week before; confirm the heartbeat and a test alert arrive.</td><td>Prove the whole loop fires before you&rsquo;re unreachable.</td></tr>
    </table>
  ` },
  { id: "watch", nav: "&#9654; Watch it work", html: `
    <h1>Watch it work &mdash; a month on Study CP-101</h1>
    <p class="lede">The deterministic system keeping Phase&nbsp;1 monitoring alive and self-escalating for a month while the lead is unreachable in Europe.</p>
    <div class="dl">
      <a class="btn" href="SAS_R_OnLeave_Screencast_narrated.mp4">&#9654;&nbsp; Watch the live screencast &mdash; a morning of coverage, on screen (~2 min)</a>
      <a class="btn ghost" href="OnLeave_Walkthrough.mp4">&#9654;&nbsp; Annotated walkthrough (~5 min)</a>
      <a class="btn ghost" href="OnLeave_StepGuide.pdf">&#10515;&nbsp; Step-by-step picture guide (PDF)</a>
      <a class="btn ghost" href="OnLeave_Coverage_Runbook.pdf">&#10515;&nbsp; The coverage runbook (PDF)</a>
    </div>
    <div class="shots">
      <figure><img src="example_img/beat1.png" alt="Setup"><figcaption><b>Beat 0 &middot; Before leaving</b> &mdash; schedule the validated programs under a service account; hand over the runbook.</figcaption></figure>
      <figure><img src="example_img/beat2.png" alt="Week 1"><figcaption><b>Week 1 &middot; GREEN</b> &mdash; the daily digest is all-clear, and the <b>heartbeat</b> proves the job ran on fresh data.</figcaption></figure>
      <figure><img src="example_img/beat3.png" alt="Week 2"><figcaption><b>Week 2 &middot; AMBER</b> &mdash; an enrollment KRI dips; it stays in the routine channel; the manager just sees it was handled.</figcaption></figure>
      <figure><img src="example_img/beat4.png" alt="Week 3 RED"><figcaption><b>Week 3 &middot; RED</b> &mdash; a candidate Hy&rsquo;s-Law pattern trips the urgent tier &mdash; to primary + backup + alias, with the medical monitor&rsquo;s number and the evidence attached.</figcaption></figure>
      <figure><img src="example_img/beat5.png" alt="Evidence"><figcaption><b>Week 3 &middot; the evidence is pre-packaged</b> &mdash; eDISH plot, lab trajectory, the exact rule that fired; the escalation log is time-stamped. <b>Detect, page, package &mdash; humans decide.</b></figcaption></figure>
      <figure><img src="example_img/beat6.png" alt="Mockup of a monitoring archive file listing: dated run logs, daily and weekly digests, the AMBER and RED alert PDFs, the evidence packet, and a heartbeat history — a complete time-stamped audit trail."><figcaption><b>Week 4 &middot; the lead returns</b> &mdash; a complete, time-stamped, reproducible audit trail. Nothing to reconstruct.</figcaption></figure>
    </div>
    <p class="muted">Prefer text? The full narration is on the <a href="#transcript">Transcript</a> page; the video is captioned, and the PDF of this playbook contains every section in reading order.</p>
  ` },
  { id: "transcript", nav: "Transcript", html: `
    <h1>Walkthrough transcript</h1>
    <p class="lede">The complete narration of the &ldquo;Watch it work&rdquo; video, as readable text &mdash; an alternative to the video and a captioned reference.</p>
    ${transcriptHtml}
  ` },
  { id: "runbook", nav: "Coverage runbook", html: `
    <h1>The coverage runbook</h1>
    <p>The one page you hand the covering colleague (the <em>support</em>), cc the manager. <a href="OnLeave_Coverage_Runbook.pdf">Download the full runbook (PDF)</a>.</p>
    <table>
      <tr><th>Status</th><th>Means</th><th>Who does what</th></tr>
      <tr><td><b style="color:#46C988">GREEN</b></td><td>All checks within limits.</td><td>No action. The heartbeat still confirms the run happened on fresh data.</td></tr>
      <tr><td><b style="color:#D9A94F">AMBER</b></td><td>An operational/quality KRI crossed.</td><td>Support reviews &amp; acts (e.g. a site action with the PM). Stays in the routine channel.</td></tr>
      <tr><td><b style="color:#E0857A">RED</b></td><td>A safety threshold (DLT/SAE/Hy&rsquo;s-Law/QTcF).</td><td>Support acknowledges &le;30 min, then <b>CONTACTS THE MEDICAL MONITOR</b>. Evidence packet attached.</td></tr>
    </table>
    <div class="callout warn"><b>If you receive no email:</b> &ldquo;no news&rdquo; is <b>never</b> &ldquo;all clear.&rdquo; A successful run always sends a GREEN digest with a heartbeat. If the 07:00 digest doesn&rsquo;t arrive by 09:00, treat the system as <b>down</b> and notify IT / the backup. A silent system is a RED condition.</div>
  ` },
  { id: "macros", nav: "Macro library", html: `
    <h1>The macro library &mdash; maximum ease of automation</h1>
    <p>A deterministic, no-AI SAS macro library (with an R companion) that implements the whole loop: <b>ingest &rarr; freshness gate &rarr; checks &rarr; roll-up &rarr; digest</b>, plus a tier-2 urgent alert and a heartbeat. Map the placeholder column names to your validated ADaM/SDTM specs.</p>
    <div class="dl">
      <a class="btn" href="tm_macros.sas">&#10515;&nbsp; tm_macros.sas (the library)</a>
      <a class="btn ghost" href="monitor_driver.sas">&#10515;&nbsp; monitor_driver.sas (the daily job)</a>
    </div>
    <h2>Quick start</h2>
    <pre class="prompt">%include "tm_macros.sas";
%tm_init(study=CP101, root=/opt/trialmon/cp101, smtp=smtp.internal, statelib=.../state);
%tm_freshness(feeds=adam.adlb adam.adeg adam.adae, maxage=26);   /* GATE first        */
%tm_chk_hyslaw(in=adam.adlb_edish);   %tm_status(in=_tm_hyslaw); /* deterministic flag */
%tm_chk_qtcf(in=adam.adeg);           %tm_status(in=_tm_qtcf);
%tm_chk_enroll(in=adam.enroll, kri=0.80);
%tm_digest(title=CP-101 Daily Safety Digest, sections=_tm_enroll _tm_qtcf _tm_hyslaw, to=&support);
%tm_alert(in=_tm_red_new, to=&support, backup=&backup, alias=&alias,
          mm_name=%str(Dr. Okafor), mm_phone=+1-555-0100, evidence=&packet);
%tm_heartbeat(records=&n, watcher_to=&backup);</pre>
    <h2>Schedule it (service account)</h2>
    <pre class="prompt">:: Windows Task Scheduler
schtasks /create /tn "CP101_monitor" /tr "run_monitor.bat" /sc DAILY /st 06:00 /ru SVC-BIOSTAT
# Linux cron
0 6 * * 1-5  /opt/jobs/run_monitor.sh    # sas -sysin monitor_driver.sas -batch</pre>
    <p class="muted">The macros cover the safety checks (Hy&rsquo;s-Law/eDISH, QTcF, AE/SAE, DLT-vs-3+3, labs), operational checks (enrollment KRI, query aging, visits, IXRS reconciliation), the two-tier digest/alert, and the four safeguards (heartbeat, freshness gate, de-dup, primary+backup). See the README in the macro library for the full catalog.</p>
  ` },
  { id: "safeguards", nav: "&#9888; Won't fail silently", html: `
    <h1>Why it won&rsquo;t fail silently</h1>
    <div class="callout warn"><b>The SOP rule:</b> &ldquo;no news&rdquo; is <b>never</b> &ldquo;all clear.&rdquo; A successful, data-fresh run must say so explicitly; the absence of any message is itself escalated.</div>
    <table>
      <tr><th>Failure mode</th><th>The safeguard</th></tr>
      <tr><td><b>The job dies silently</b> (daemon down, expired password, locked licence, full disk).</td><td><b>Heartbeat / dead-man&rsquo;s switch</b> &mdash; every run pings &ldquo;ran OK&rdquo;; an <em>independent</em> watcher on a second host escalates if the ping is missing.</td></tr>
      <tr><td><b>Stale-data masquerade</b> &mdash; green daily, but a feed stopped refreshing. <b>Green here is worse than red.</b></td><td><b>Data-freshness gate, run first</b> &mdash; compare each feed&rsquo;s newest timestamp to now; raise it if a source stopped.</td></tr>
      <tr><td><b>Alert storm</b> &mdash; a mis-set threshold or duplicate fires the same RED dozens of times; the cover mutes the thread.</td><td><b>De-duplication</b> &mdash; a persistent seen-flags table alerts each finding once.</td></tr>
      <tr><td><b>Human single-point-of-failure</b> &mdash; the one cover is also away when a 06:07 RED fires.</td><td><b>Primary + backup + role alias</b> with an acknowledgement SLA and a re-page rule.</td></tr>
    </table>
  ` },
  { id: "gov", nav: "Governance &amp; limits", html: `
    <h1>Governance &amp; honest limits</h1>
    <h2>Why this is the lowest-risk option</h2>
    <ul>
      <li><b>No new validation surface.</b> It surfaces outputs from the <b>same validated programs</b> &mdash; it automates the delivery/cadence, not the method.</li>
      <li><b>Deterministic &amp; reproducible.</b> Same data &rarr; byte-identical result, every run. Nothing to &ldquo;explain&rdquo;; the audit trail is automatic.</li>
      <li><b>Zero PHI egress.</b> Everything runs where the data already lives &mdash; no external API, no cloud model, no new vendor. (Alert bodies carry de-identified signal only; detail is in the attached report.)</li>
      <li><b>Validated like any study program</b> (spec &rarr; review &rarr; test &rarr; change control); anything <em>reported</em> stays independently double-programmed.</li>
      <li><b>No new approval gate</b> between today and go-live &mdash; only the normal program validation you already run.</li>
    </ul>
    <div class="callout warn"><b>The honest limit:</b> deterministic checks only &mdash; no triage, narrative, or judgment. It guarantees pre-specified signals reach a human reliably and reproducibly; it does not replace the human, the medical monitor, or the DSMB/SRC. That triage layer is the seam the AI hybrid fills later.</div>
  ` },
  { id: "faq", nav: "FAQ", html: `
    <h1>FAQ</h1>
    <p><b>Do we need new software?</b> No &mdash; use the SAS/R and scheduler already validated in your environment. Introducing a new orchestrator just for this re-adds the governance cost you&rsquo;re avoiding.</p>
    <p><b>Does it make clinical decisions?</b> No. It detects threshold crossings, pages the right people, and packages the evidence. The medical monitor and covering biostatistician decide.</p>
    <p><b>Is it only for leave coverage?</b> No &mdash; that&rsquo;s the anchoring scenario, but it&rsquo;s the standing monitoring backbone for any study, any time.</p>
    <p><b>What if a job fails while I&rsquo;m away?</b> The heartbeat and freshness gate make a dead job or a frozen feed <em>announce itself</em>. &ldquo;No news&rdquo; is never &ldquo;good news.&rdquo;</p>
  ` },
];

const css = `
:root{--indigo:#8B86F0;--ink:#E7ECF8;--muted:#9AA6C8;--line:#272D4D;--panel:#181D38;--teal:#3FB6C2;--amber:#D9A94F;--terra:#E0857A;--sas:#6FA0DC;--bg:#0E1124}
*{box-sizing:border-box}body{margin:0;font-family:-apple-system,Segoe UI,Calibri,Arial,sans-serif;color:var(--ink);background:var(--bg);line-height:1.55}
#wrap{display:flex;min-height:100vh}#side{width:272px;flex:0 0 272px;background:#15183A;color:#fff;border-right:1px solid #2a2f52;position:sticky;top:0;height:100vh;overflow:auto;padding:22px 0}
#side .brand{padding:0 22px 14px;border-bottom:1px solid #2c2f55;margin-bottom:10px}#side .brand b{font-family:Georgia,serif;font-size:15px}#side .brand span{display:block;color:#aeb4e0;font-size:11px;margin-top:4px}
#search{margin:0 16px 12px;width:calc(100% - 32px);padding:8px 10px;border-radius:8px;border:1px solid #3a3e72;background:#1d2150;color:#fff;font-size:13px}
#side a{display:block;color:#cfd3f3;text-decoration:none;padding:8px 22px;font-size:13.5px;border-left:3px solid transparent}#side a:hover{background:#1d2150}#side a.active{color:#fff;border-left-color:#8b86f0;background:#1d2150;font-weight:600}
#main{flex:1;max-width:980px;margin:0 auto;padding:34px 48px 80px}section{display:none}section.show{display:block;animation:f .2s}@keyframes f{from{opacity:.3}to{opacity:1}}
h1{font-family:Georgia,serif;color:var(--ink);font-size:29px;margin:0 0 14px;line-height:1.15}h2{font-family:Georgia,serif;color:#A9A4F5;font-size:20px;margin:26px 0 10px;border-bottom:1px solid var(--line);padding-bottom:5px}
.lede{font-size:16.5px;color:#C3CCE4}p,li{font-size:15px}ul,ol{padding-left:22px}li{margin:5px 0}
code{background:#20284a;color:#A9C6F2;padding:1px 6px;border-radius:5px;font-family:Consolas,monospace;font-size:12.5px}
pre.prompt{background:#080A18;color:#e6e8ff;padding:14px 16px;border-radius:10px;overflow:auto;font-family:Consolas,monospace;font-size:12.5px;line-height:1.5;border:1px solid var(--line);border-left:4px solid var(--sas);white-space:pre-wrap}
table{border-collapse:collapse;width:100%;margin:12px 0;font-size:14px}th,td{border:1px solid var(--line);padding:8px 11px;text-align:left;vertical-align:top}th{background:#15183A;color:#fff;font-weight:600}tr:nth-child(even) td{background:var(--panel)}
.callout{border-radius:10px;padding:13px 16px;margin:16px 0;font-size:14px}.callout.warn{background:#2A1614;border-left:4px solid var(--terra)}.callout.tip{background:#0F262A;border-left:4px solid var(--teal)}
.muted{color:var(--muted);font-size:13px}.footer{margin-top:40px;padding-top:16px;border-top:1px solid var(--line);color:var(--muted);font-size:12px}a{color:var(--indigo)}
.dl{display:flex;gap:12px;margin:16px 0;flex-wrap:wrap}.btn{display:inline-block;background:var(--sas);color:#fff;text-decoration:none;font-weight:700;font-size:14px;padding:11px 18px;border-radius:9px}.btn.ghost{background:transparent;color:var(--sas);border:1.5px solid var(--sas)}.btn:hover{opacity:.92}
.shots{display:grid;grid-template-columns:1fr 1fr;gap:18px;margin:18px 0}.shots figure{margin:0}.shots img{width:100%;border:1px solid var(--line);border-radius:10px;box-shadow:0 3px 12px rgba(20,20,40,.10);display:block}.shots figcaption{font-size:13px;color:var(--muted);margin-top:8px;line-height:1.4}
.vh{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap}
.skip{position:absolute;left:-9999px;top:0;background:#15183A;color:#fff;padding:10px 16px;z-index:100}.skip:focus{left:0}
a:focus-visible,button:focus-visible,#side a:focus-visible,#search:focus-visible,#main:focus-visible{outline:3px solid #8b86f0;outline-offset:2px}


@media (prefers-reduced-motion:reduce){section.show{animation:none}}
@media print{#side,#search,.a11y,.skip,label[for=search]{display:none!important}#main{max-width:none;padding:18px}section{display:block!important;page-break-before:always}section:first-of-type{page-break-before:avoid}h1,h2{page-break-after:avoid}.footer{display:none}}
`;
const js = `const secs=[...document.querySelectorAll('section')],links=[...document.querySelectorAll('#side a[data-t]')];function show(id){secs.forEach(s=>{const on=s.id===id;s.classList.toggle('show',on);s.hidden=!on;});links.forEach(a=>{const on=a.dataset.t===id;a.classList.toggle('active',on);if(on)a.setAttribute('aria-current','page');else a.removeAttribute('aria-current');});window.scrollTo(0,0);const m=document.getElementById('main');if(m)m.focus();if(location.hash!=='#'+id)history.replaceState(null,'','#'+id);}links.forEach(a=>a.addEventListener('click',e=>{e.preventDefault();show(a.dataset.t);}));document.querySelectorAll('#main a[href^="#"]').forEach(a=>a.addEventListener('click',e=>{const id=a.getAttribute('href').slice(1);if(document.getElementById(id)){e.preventDefault();show(id);}}));const q=document.getElementById('search');q.addEventListener('input',()=>{const v=q.value.toLowerCase().trim();links.forEach(a=>{const s=document.getElementById(a.dataset.t);a.style.display=(!v||s.textContent.toLowerCase().includes(v))?'block':'none';});});show((location.hash||'#start').slice(1)||'start');window.addEventListener('beforeprint',()=>secs.forEach(s=>s.hidden=false));window.addEventListener('afterprint',()=>show((location.hash||'#start').slice(1)||'start'));`;
const nav = sections.map(s => `<a href="#${s.id}" data-t="${s.id}">${s.nav}</a>`).join("\n");
const body = sections.map(s => `<section id="${s.id}" aria-label="${String(s.nav).replace(/&[^;]+;/g,'').trim()}">${s.html}<div class="footer">Coverage while on leave &middot; deterministic SAS/R, no AI, no PHI egress &middot; the medical monitor &amp; humans decide &middot; June 2026.</div></section>`).join("\n");
const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Coverage While On Leave — SAS/R Playbook</title><style>${css}</style></head><body><a href="#main" class="skip">Skip to content</a><div id="wrap"><nav id="side" aria-label="Playbook sections"><div class="brand"><b>On-Leave Coverage</b><span>SAS/R monitoring playbook</span></div><label for="search" class="vh">Search the playbook</label><input id="search" type="search" placeholder="Search..." autocomplete="off">${nav}</nav><main id="main" tabindex="-1">${body}</main></div><script>${js}</script></body></html>`;
fs.writeFileSync(__dirname + "/On_Leave_Coverage_Playbook.html", html);
console.log("WROTE On_Leave_Coverage_Playbook.html (" + html.length + " bytes, " + sections.length + " pages)");
