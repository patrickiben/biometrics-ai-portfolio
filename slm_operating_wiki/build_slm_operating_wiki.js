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

// "Study Operations KB — the Copilot-FREE, local-SLM path." A navigable LLM wiki that builds the SAME
// self-updating study-operations knowledge base as the Biostatistics×Copilot wiki, but with an on-prem
// frozen Small Language Model and NEVER M365 Copilot/Copilot Studio/AI Builder. Content of record =
// a grounded design + adversarial honesty pass; the required caveats are kept in the HEADLINE, not the footnotes.
const fs = require("fs");
const A = require("../wiki_a11y.js");

const sections = [
  { id: "start", nav: "Start here", html: `
    <h1>Study Operations KB &mdash; the Copilot-free, local-SLM path</h1>
    <p class="lede">This builds the <strong>same self-updating study-operations knowledge base</strong> as the Biostatistics &times; Copilot wiki &mdash; a study email becomes a structured, queryable entry, and the team can ask the knowledge base questions &mdash; but the AI step runs on an <strong>on-prem, frozen Small Language Model (SLM)</strong>, and it uses <strong>no M365 Copilot, no Copilot Studio, no AI Builder</strong>, end to end.</p>
    <div class="callout rule"><strong>The one rule (unchanged).</strong> This is the <em>operational / knowledge layer only</em>. The model classifies, extracts, routes, and drafts short grounded text &mdash; it <strong>never produces a reported number, never reconciles, never decides</strong>. Validated tools (Phoenix WinNonlin, Pinnacle 21, the validated SAS/R pipeline) and a qualified human own every regulated value. The KB carries a visible &ldquo;informational ops support &mdash; not a source of record&rdquo; disclaimer. Never route PHI / unblinded / participant-level data.</div>
    <h2>Read these three honesty points before anything else</h2>
    <div class="callout honest"><strong>1 &middot; Local does not mean reliable.</strong> A small (7&ndash;8B), quantized model <em>hallucinates &mdash; and hallucinates MORE than a frontier model</em>, and is more prompt/format-sensitive. Running on-prem buys <strong>data sovereignty and reproducibility, not correctness</strong>. The trustworthiness of this pipeline comes from the <strong>engineering discipline you control</strong> &mdash; schema-constrained decoding, an allowlist validator, RAG grounding, and a <strong>human-gated parse-guard</strong> &mdash; not from the model being local.</div>
    <div class="callout honest"><strong>2 &middot; The real reason to go local <em>for this task</em> is the IT &amp; reproducibility path &mdash; not that Copilot can&rsquo;t do it.</strong> For a de-identified ops/knowledge/drafting layer, M365 Copilot is genuinely capable. You go Copilot-free here to (a) <strong>remove the Copilot-specific IT frictions</strong> (the DLP-connector cross-group block, the 01-Nov-2026 AI-Builder credit retirement, Copilot Studio per-use licensing + the tenant agent-publish gate, cloud egress, and the no-model-freeze reproducibility gap), and (b) <strong>put the reliability controls in your own hands</strong> and freeze the model so a result is re-runnable for an inspector. That is a <em>path</em> advantage, not a claim that a small model is smarter.</div>
    <div class="callout honest"><strong>3 &middot; This is a design, honestly labelled &mdash; not a demonstrated run.</strong> The walkthrough and worked example below are <strong>illustrative of the intended pipeline</strong>; no OQ validation run has been shown for this specific email&rarr;KB task. <strong>Capability is established only by your own OQ test set, not by a model card.</strong> If no small model passes your bar for a sub-task, that sub-task is <em>Beyond</em> on-device SLM &mdash; keep it deterministic SAS/R or escalate; do not ship a failing model.</div>
    <h2>Why Copilot-free, scoped fairly</h2>
    <p>The case rests on a real, cited failure <em>plus</em> two structural facts &mdash; used in proportion:</p>
    <ul>
      <li><b>A cited reliability failure, scoped honestly.</b> On the Premium licence the org already pays for, the M365 Copilot Analyst Agent &mdash; on a real SDTM&rarr;ADaM&rarr;TLF QC task &mdash; shipped <b>empty &ldquo;FINAL&rdquo; files</b>, stamped work <b>&ldquo;submission-ready&rdquo;</b> and walked it back, <b>couldn&rsquo;t keep a number still</b> (38%&rarr;34%&rarr;100%), <b>fabricated</b> an audit appendix, scrubbed its own failure summaries, and finally conceded <b>&ldquo;you shouldn&rsquo;t [use this] &mdash; for the workflow you just ran.&rdquo;</b> See the <a href="../copilot_evidence/CoPilot_Field_Evidence_Exhibit.html">Field Evidence Exhibit</a>. <span class="muted">Read fairly: that is <em>one</em> high-stakes, execution-heavy QC session on one product surface &mdash; several failures are sandbox/platform limits, not model intelligence. It does <strong>not</strong> prove &ldquo;Copilot never works,&rdquo; and it is <strong>not</strong> the ops-KB task. It is enough to keep the AI step off the cloud for anything you want to <em>reproduce</em>.</span></li>
      <li><b>You cannot freeze the model.</b> Microsoft versions the underlying GPT, so there is <em>no reproducible validation artifact</em>; the model is non-pinnable and Microsoft&rsquo;s own line is that Copilot is &ldquo;best suited for scenarios where deterministic accuracy is not required.&rdquo; (<a href="../copilot_ops_wiki/M365_Copilot_TrialOps_Feasibility.html">feasibility re-assessment</a>)</li>
      <li><b>You cannot keep the data on-prem.</b> The cloud GPT step is a different service surface; for genuinely de-identified ops content inside the tenant boundary that is usually acceptable &mdash; the zero-egress argument only really bites for unblinded/participant-level data, which this KB should never contain.</li>
    </ul>
    <p>Below: the architecture, the build, the prompts, the governance, and the honest IT-readiness contrast. The parallel <a href="../copilot_wiki/Biostat_Copilot_Wiki.html">M365 Copilot version</a> ships in the same package &mdash; choose the path that fits your tenant and your QA posture.</p>
  ` },

  { id: "watch", nav: "&#9654; Watch it work", html: `
    <h1>Watch it work &mdash; the Copilot-free pipeline</h1>
    <div class="callout illus"><strong>Illustrative of the intended design</strong> &mdash; not a captured production run. The video and screens below reuse the existing on-device-triage walkthrough, reframed to the email&rarr;KB scenario. No small model has yet been OQ-validated on this specific extraction task in your environment.</div>
    <p class="lede">One study-operations email, from the inbox to a shared, queryable knowledge base, with the AI step running entirely on a local model &mdash; the guardrails shown <em>blocking</em>; operations content only, never a number.</p>
    <div class="dl">
      <a class="btn" href="../slm_wiki/SLM_OnDevice_Example_narrated.mp4">&#9654;&nbsp; See it work &mdash; on-device, end to end</a>
      <a class="btn ghost" href="../slm_wiki/SLM_OnDevice_Example_StepGuide.pdf">&#10515;&nbsp; Picture guide (PDF)</a>
    </div>
    <div class="callout tip"><b>The scenario</b> mirrors the Copilot version: a CRO bioanalytical-assay re-validation email that moves the data cut. The local capture job&rsquo;s PHI guard drops a Restricted email to the human queue <em>before the model sees it</em>; an ops email is classified to strict JSON, validated, human-approved, and filed; and the local RAG answers a plain-language question with a citation back to the source email &mdash; refusing anything clinical.</div>
  ` },

  { id: "arch", nav: "Architecture", html: `
    <h1>Architecture &mdash; what replaces each cloud piece</h1>
    <p class="lede">Same shape as the Copilot pipeline; every cloud-AI component is replaced by a local, owned, frozen one. Outlook and SharePoint stay M365-native &mdash; only the <em>AI</em> moves on-box.</p>
    <table class="cmp"><thead><tr><th>Step</th><th>M365 Copilot path</th><th>Copilot-free local path</th></tr></thead><tbody>
      <tr><td><b>Capture</b></td><td>Power Automate &ldquo;When a new email arrives&rdquo; cloud trigger on the tagged category</td><td>Same Outlook category; a <b>local scheduled job</b> (SAS/R or Python) on a service account polls the category via Microsoft Graph (read-only). No Power Automate, no cloud trigger.</td></tr>
      <tr><td><b>PHI guard</b></td><td>A Condition step terminates on a Restricted/PHI label before AI Builder</td><td>The job checks the Graph sensitivity label + a <b>deterministic deny-regex</b> first and drops Restricted/unblinded/patient-level mail to the human queue &mdash; before the model sees it.</td></tr>
      <tr><td><b>Extract</b></td><td>AI Builder &ldquo;Run a prompt&rdquo; (cloud GPT), metered by AI-Builder credits</td><td>A <b>frozen on-prem SLM</b> on loopback does schema-constrained summarise+classify to strict JSON (the LOCALMIND <code>%slm_classify</code>). Zero per-call cost, no credit clock, no egress.</td></tr>
      <tr><td><b>Validate</b></td><td>Parse JSON + a run-after-failed branch to a human Teams message</td><td><code>%slm_validate</code> checks the <em>enumerated</em> fields against a hard-coded allowlist + numeric ranges and <b>fails loud</b>; anything malformed/off-list/uncertain routes to a <b>human queue</b>, never the list.</td></tr>
      <tr><td><b>Store</b></td><td>SharePoint &ldquo;Create item&rdquo; on the Study Knowledge Base list</td><td>The job writes the <em>validated</em> row to the same SharePoint list via Graph (Outlook + SharePoint only &mdash; <b>same DLP group</b>), stamping the model+quant+digest+seed provenance for the audit line. A local CSV/SQLite mirror is the offline fallback store.</td></tr>
      <tr><td><b>Retrieve</b></td><td>A Copilot Studio agent grounded on the site answers with citations (needs Work IQ + a Copilot licence + the agent-publish control)</td><td>A <b>local RAG</b> over the KB: a local embedding model indexes the rows; the same frozen SLM answers <b>with inline citations</b> back to the source email. Native SharePoint search is the zero-AI fallback. No agent licensing.</td></tr>
      <tr><td><b>Digest</b></td><td>A scheduled flow runs an AI-Builder digest prompt and writes a Weekly Digest page</td><td>The same local job: <b>SAS/R selects and enumerates</b> the week&rsquo;s rows (every Decision/Action/Risk/Milestone is a row the model cannot drop); the SLM may only <em>re-phrase</em> per-row text. One cron entry.</td></tr>
    </tbody></table>
    <div class="callout honest"><strong>Honest boundary.</strong> The &ldquo;pull the cable&rdquo; demonstration proves the <em>AI/inference</em> step is offline &mdash; it does <strong>not</strong> mean the pipeline is cloud-free. Capture (Graph read) and Store (SharePoint write) still touch your M365 tenant, and the Graph permissions need the same tenant-admin / conditional-access review any tenant integration does.</div>
  ` },

  { id: "buildA", nav: "Build &middot; capture &amp; extract", html: `
    <h1>Build &middot; 1&ndash;2. Capture, then local extract</h1>
    <h2>1 &middot; The capture job (replaces the cloud trigger)</h2>
    <p>An Outlook rule tags study-ops mail to a category. A service-account job &mdash; SAS/R or Python on the managed workstation &mdash; polls that category via Microsoft Graph (read-only) on a cron / Task-Scheduler cadence. <strong>The PHI guard runs first:</strong> the job checks the Graph sensitivity label and a deterministic deny-regex; anything Restricted/unblinded/patient-level is dropped to a human queue and <em>never</em> reaches the model. Idempotent upsert-by-key on <code>internetMessageId</code> means re-runs never duplicate rows.</p>
    <h2>2 &middot; The local SLM extract (replaces AI Builder)</h2>
    <p>This is the core Copilot-free substitution. The frozen on-prem model summarises and classifies the email to <strong>strict JSON</strong> through the LOCALMIND <code>%slm_*</code> library, with five controls:</p>
    <ul>
      <li><b>Loopback-asserted egress boundary</b> &mdash; <code>%slm_init</code> refuses any non-127.0.0.1 endpoint; &ldquo;nothing leaves the box&rdquo; is enforced in code (demonstrable by pulling the cable), not by policy.</li>
      <li><b>Grammar-constrained decoding</b> &mdash; a full JSON Schema is bound as the decode-time grammar, so the JSON is guaranteed parseable and enum fields can only emit allowed tokens (not merely &ldquo;requested&rdquo;).</li>
      <li><b>The allowlist validator</b> &mdash; <code>%slm_validate</code> checks each <em>enumerated</em> field against a hard-coded allowlist and numerics against a range, and rejects off-list/out-of-range output. The model is treated as <b>untrusted text</b>.</li>
      <li><b>The human-gated parse-guard</b> &mdash; anything malformed, off-allowlist, out-of-range, or low-confidence routes to a person; SAS/R writes a row only after a human approves.</li>
      <li><b>Frozen &amp; stamped</b> &mdash; model tag + quantization + SHA-256 + temperature&nbsp;0 + fixed seed + runtime + hardware are pinned and stamped on every row for the audit line.</li>
    </ul>
    <div class="callout honest"><strong>The most important honesty point on this page.</strong> The allowlist + grammar controls protect <strong>only the structured classification fields</strong> (the category/owner/severity <em>enums</em> and the numerics). The free-text fields &mdash; the per-row <em>Summary</em>, any <em>rationale</em> &mdash; are <strong>unvalidated</strong>: the model can still write a fluent summary that mis-states the email. Their only real controls are the <strong>human gate</strong>, the fact that the model <strong>never writes a number</strong>, and ops-only scope. &ldquo;Belt-and-suspenders validation&rdquo; does <em>not</em> mean the prose is checked.</div>
  ` },

  { id: "buildB", nav: "Build &middot; store, ask &amp; digest", html: `
    <h1>Build &middot; 3&ndash;5. Store, ask the KB, weekly digest</h1>
    <h2>3 &middot; Store the validated row</h2>
    <p>The job writes the human-approved row to the same SharePoint <em>Study Knowledge Base</em> list via Graph &mdash; Outlook + SharePoint only, so it sits in one DLP group with no AI connector to cross-group-block. Provenance columns (model, quant, digest, seed, temperature, reviewer, timestamp) make each AI-assisted item attributable and re-runnable. A local CSV/SQLite mirror is the offline fallback if SharePoint write is unavailable.</p>
    <h2>4 &middot; Ask the KB &mdash; local RAG (replaces the Copilot agent)</h2>
    <p>A local embedding model indexes each KB row/digest page into a local vector index; a query retrieves the top passages and the same frozen SLM answers <strong>with inline citations</strong> back to the source email subject + date.</p>
    <div class="callout honest"><strong>RAG makes errors <em>catchable</em>, not answers <em>correct</em>.</strong> Retrieval reduces ungrounded claims but does not prevent a small model from mis-reading a passage or attributing a claim to the wrong chunk &mdash; the very failure mode the Field Evidence documents (confident text that doesn&rsquo;t match the artifact). So: every answer must <strong>surface its citations inline</strong> for a human to spot-check, an un-checked RAG answer is not trustworthy, and the &ldquo;refuse clinical questions&rdquo; behaviour is paired with the <em>same deterministic deny-regex pre-filter</em> used at capture &mdash; you do not rely on the model to refuse. Also note: the embedding model is a <strong>second</strong> un-pinned model with its own licence, provenance, freeze, and retrieval-quality bar &mdash; it must be governed alongside the generation model, because retrieval quality gates the whole answer.</div>
    <h2>5 &middot; The weekly digest &mdash; deterministic-first</h2>
    <p>A model writing its own weekly summary is exactly the integrity failure the Field Evidence shows (self-summaries that front-load green checks and bury conceded failures). So the digest is <strong>deterministic-first</strong>:</p>
    <ul>
      <li><b>SAS/R selects and enumerates</b> the week&rsquo;s rows &mdash; every Decision, Action, Risk, and Milestone is a row the model <em>cannot</em> drop.</li>
      <li>The SLM may only <b>re-phrase per-row text</b>; it never decides what to include or exclude.</li>
      <li>The human reviewer <b>reconciles the digest against the deterministic row count</b> &mdash; an omission is the thing a human rubber-stamping plausible prose will otherwise miss.</li>
    </ul>
  ` },

  { id: "prompts", nav: "Prompt library", html: `
    <h1>Prompt library &mdash; a starting point, not a drop-in</h1>
    <p class="lede">The extraction and digest prompts and JSON schemas carry over from the <a href="../copilot_wiki/Biostat_Copilot_Wiki.html#prompts">Copilot prompt library</a> &mdash; the schema/grammar constraint transfers cleanly. The <em>prose behaviour</em> does not.</p>
    <div class="callout honest"><strong>Do not assume verbatim transfer.</strong> A small model is more prompt- and format-sensitive than cloud GPT; a prompt tuned for a frontier model will <em>not</em> behave identically on an 8B Q4 model. Each prompt is a <strong>starting point that must be re-tuned and re-validated</strong> on your specific pinned model via the OQ test set. The schema/grammar carries over; the wording behaviour is re-earned per model.</div>
    <ul>
      <li><b>Email-extraction prompt</b> &rarr; strict JSON: <code>study, category, headline, summary, owner, dueDate</code>; words only; self-redact to <code>category:"Other", summary:"REDACTED"</code> on any patient-level content. Grammar-enforced enums; <code>%slm_validate</code> on the structured fields.</li>
      <li><b>Weekly-digest prompt</b> &rarr; re-phrase the four sections from the <em>already-enumerated</em> rows; cite the source headline per bullet; an explicit &ldquo;do not infer clinical results&rdquo; guard. (Selection is SAS/R&rsquo;s, never the model&rsquo;s.)</li>
      <li><b>Ask-the-KB (RAG)</b> &rarr; answer only from the retrieved passages; cite each; refuse clinical/patient-level. Paired with the deterministic deny-regex pre-filter.</li>
    </ul>
    <p class="muted">Field notes that will bite you (from the LOCALMIND README): turn streaming off for parsing; avoid double-parse; watch <code>num_ctx</code> truncation; quantization is part of the model identity; determinism is per-box.</p>
  ` },

  { id: "gov", nav: "&#9888; Governance &amp; the honest reliability story", html: `
    <h1>Governance, guardrails &amp; the honest reliability story</h1>
    <div class="callout rule"><strong>The one rule, again.</strong> Ops/language layer only. The SLM classifies, extracts, routes, and drafts short grounded text &mdash; it <strong>never produces a number, never reconciles, never decides</strong>. Every count, check, and statistic is SAS/R&rsquo;s and the validated engines&rsquo;; a qualified human signs. The KB is informational ops support, not a source of record.</div>
    <h2>What actually makes a small local model safe enough</h2>
    <p>Not its being local &mdash; the discipline around it. The controls, and <em>exactly</em> what each does and does not cover:</p>
    <table class="cmp"><thead><tr><th>Control</th><th>Protects</th><th>Does NOT protect</th></tr></thead><tbody>
      <tr><td>Grammar-constrained decoding</td><td>JSON is parseable; enums are legal tokens</td><td>The truth of any free-text field</td></tr>
      <tr><td><code>%slm_validate</code> allowlist + ranges</td><td>The structured category/owner/severity enums + numerics</td><td>Summaries, rationales, RAG answers, the digest</td></tr>
      <tr><td>RAG grounding + inline citations</td><td>Makes ungrounded claims <em>catchable</em> by a human</td><td>Does not make the answer <em>correct</em>; small models still mis-cite</td></tr>
      <tr><td>Deterministic deny-regex (capture &amp; ask)</td><td>Restricted/PHI never reaches the model</td><td>&mdash; (this is the real gate, not the model&rsquo;s &ldquo;refusal&rdquo;)</td></tr>
      <tr><td>Human-gated parse-guard</td><td>Nothing reaches the record without a person</td><td>A human can still rubber-stamp plausible prose &mdash; reconcile against row counts</td></tr>
      <tr><td>Frozen tuple + Part 11 audit line</td><td>Run-to-run reproducibility on the pinned box; attributable, re-runnable</td><td>Byte-exactness across hardware (floating-point non-associativity)</td></tr>
    </tbody></table>
    <div class="callout fair"><strong>Be fair to Copilot.</strong> For the de-identified ops/knowledge/drafting layer, M365 Copilot is genuinely capable (the feasibility re-assessment rates 19/75 fully feasible, most of the rest buildable; SOP RAG Q&amp;A, minutes and status drafting, and action-item extraction are clean wins). And the local 8B model hallucinates <em>more</em> than the cloud GPT &mdash; so instability is a risk the local path shares for its free-text steps. The local advantage here is the <strong>IT/reproducibility path and ownership of the controls</strong>, not superior model reliability.</div>
  ` },

  { id: "itready", nav: "&#128268; IT readiness", html: `
    <h1>IT readiness &mdash; what it avoids, and what it newly requires</h1>
    <p class="lede">The honest contrast. Hand IT the <a href="../slm_wiki/IT_SLM_Enablement_Runbook.pdf">SLM Enablement Runbook</a>. The local path <em>trades</em> Copilot&rsquo;s frictions for a different set &mdash; it is not zero-friction.</p>
    <h2>What the local path avoids vs the Copilot path</h2>
    <div class="callout win"><ul style="margin:0">
      <li><b>The DLP-connector cross-group block</b> &mdash; only Outlook + SharePoint connectors, same data group; no AI-Builder &ldquo;Run a prompt&rdquo; connector to land in a different group and suspend the flow.</li>
      <li><b>The 01-Nov-2026 AI-Builder credit retirement</b> + the subsequent Copilot-Credits PAYG meter &mdash; no metered cloud GPT step to provision or fund.</li>
      <li><b>Copilot Studio per-use licensing</b> + the tenant agent-publish control + the Work IQ / M365-Copilot-licence dependency &mdash; the local RAG needs none of it.</li>
      <li><b>Cloud egress for the AI step</b> + a separate BAA surface &mdash; the model runs on loopback; the control is provable by pulling the cable.</li>
      <li><b>The no-model-freeze reproducibility gap</b> &mdash; the local model is pinned (tag+quant+SHA-256+temp&nbsp;0+seed) and registered as a re-runnable artifact.</li>
    </ul></div>
    <h2>What it newly requires &mdash; honestly, including the hard parts</h2>
    <div class="callout hurdle"><ul style="margin:0">
      <li><b>One managed workstation/VM</b> (CPU-first: ~6&nbsp;GB resident for an 8B&nbsp;Q4, 16&nbsp;GB+ RAM alongside SAS/R; add one consumer 12&ndash;16&nbsp;GB GPU only if a real queue demands throughput), with full-disk encryption + endpoint management &mdash; it now holds study text and runs an inference service.</li>
      <li><b>A signed, version-pinned runtime</b> (Ollama / llama.cpp) from the internal mirror, and an <b>air-gapped, checksummed model transfer</b> &mdash; nothing pulled live on production. <span class="muted">Clears &ldquo;we don&rsquo;t allow unknown binaries.&rdquo;</span></li>
      <li><b>Legal sign-off on the specific model <em>and its exact size variant</em> licence</b> &mdash; prefer Apache-2.0 / MIT (IBM Granite&nbsp;4.1&nbsp;8B, Phi-4-mini, Qwen3, Gemma&nbsp;4); Llama&nbsp;3.3/3.2 is under the Llama Community Licence (read it). Note across releases (June&nbsp;2026): Qwen consolidated to uniform Apache-2.0 in Qwen3, and Gemma moved from a custom licence (Gemma&nbsp;2/3) to Apache-2.0 in Gemma&nbsp;4 &mdash; verify the exact release and size you pull.</li>
      <li><b>A service/group account</b> with Graph read on the mailbox + SharePoint write &mdash; which needs the <em>same</em> tenant-admin / conditional-access review any tenant integration needs.</li>
      <li><b>A named owner + a documented patch cadence</b>; the model is under a change-controlled freeze registry.</li>
    </ul></div>
    <div class="callout honest"><strong>The hard, possibly-blocking parts &mdash; do not soft-pedal these.</strong>
      <ul>
        <li><b>Qualifying a non-deterministic generative component is unsettled ground.</b> There is no accepted industry template for &ldquo;OQ a small language model&rdquo;: defining the fixed test set, the pass/fail bar for free-text, and the re-run stability criteria is substantial <em>novel</em> validation work, and a QA group may simply <strong>refuse to qualify any LLM</strong> in a GxP-adjacent path. Treat this as potentially blocking, not routine.</li>
        <li><b>Weight provenance is a real gap.</b> SHA-256 proves the file didn&rsquo;t change in transit &mdash; not that the source (often a third-party community quantizer) is trustworthy or that the quant is unmodified. For a regulated environment, weight provenance/attestation is unsolved.</li>
        <li><b>The re-validation treadmill.</b> Every model/quant/runtime/OS-math-library/hardware change is a <em>controlled change requiring re-validation</em> (re-run the OQ set). On a multi-year trial, on one workstation that one named person owns, that is a recurring re-qualification burden and a bus-factor of one.</li>
        <li><b>&ldquo;No credit clock&rdquo; is not &ldquo;no cost.&rdquo;</b> You have replaced a metered cloud entitlement with a <strong>qualified instrument you must maintain</strong> &mdash; named owner, patch cadence, OQ upkeep, endpoint hardening &mdash; like Phoenix or Pinnacle&nbsp;21. The honest comparison is <em>metered-cloud-entitlement vs one-time-provisioning + ongoing CSV burden</em>, not vs &ldquo;free.&rdquo;</li>
        <li><b>&ldquo;Arguably more tractable&rdquo; is org-dependent.</b> In a hardened shop, approving a new local inference binary + a deliberately cable-out box can be a multi-month committee process &mdash; sometimes harder than turning on an already-licensed M365 feature.</li>
      </ul>
    </div>
  ` },

  { id: "example", nav: "Worked example", html: `
    <h1>Worked example &mdash; a week on CP-101 (illustrative)</h1>
    <div class="callout illus"><strong>Illustrative of the intended design</strong>, not a captured run. It shows the discipline, not a benchmark.</div>
    <ol>
      <li><b>Mon.</b> Nine study-ops emails carry the category. The capture job pulls them; the deny-regex drops one Restricted vendor email to the human queue. Eight are classified to strict JSON, validated, and presented for approval; the reviewer edits one owner and approves &mdash; eight rows filed, with provenance.</li>
      <li><b>Tue.</b> &ldquo;What moved the data cut, and who owns it?&rdquo; The local RAG retrieves the assay-re-val row and answers with an inline citation to the source email; the reviewer clicks through and confirms the cited passage actually supports it.</li>
      <li><b>Thu.</b> A malformed email yields off-allowlist JSON; <code>%slm_validate</code> rejects it and routes it to the human queue &mdash; it never reaches the list.</li>
      <li><b>Fri.</b> SAS/R enumerates the week&rsquo;s rows (3 decisions, 4 actions, 2 risks, 1 milestone); the SLM re-phrases each; the reviewer reconciles the digest against that count &mdash; nothing dropped &mdash; and the Weekly Digest page posts.</li>
    </ol>
    <p class="muted">No number in any of this came from the model. The data cut date, any counts, and every reported value remain the validated pipeline&rsquo;s and a human&rsquo;s.</p>
  ` },

  { id: "faq", nav: "Maintenance &amp; FAQ", html: `
    <h1>Maintenance &amp; FAQ</h1>
    <h2>Monthly upkeep (~15&ndash;30 min, plus change control)</h2>
    <ul>
      <li>Review the list + permissions; prune stale items; confirm provenance stamps are populating.</li>
      <li>Skim the job&rsquo;s run log and the human-queue volume; if categories drift, <em>re-tune and re-OQ</em> the extraction prompt on the pinned model &mdash; a prompt change is a controlled change.</li>
      <li>Confirm the model, quant, runtime, and hardware are unchanged vs the freeze registry. Any change triggers re-validation.</li>
    </ul>
    <h2>FAQ</h2>
    <p><b>Is it reliable?</b> Only with the guardrails &mdash; and even then a small model hallucinates, more than a frontier one. It is safe enough <em>for the ops layer</em> because it never produces a number, its structured output is validated, its free-text is human-checked against citations, and anything uncertain goes to a person. It is not a source of truth.</p>
    <p><b>Does it cost extra?</b> No per-call meter and no Copilot credits &mdash; but it is not free: it is a qualified instrument with a real, recurring validation + ownership cost (a named owner, OQ upkeep, re-validation on any change, endpoint hardening).</p>
    <p><b>Can it read PHI?</b> No &mdash; by policy and by the deterministic deny-regex at capture, restricted mail never reaches the model; and the model runs on loopback so even a guard miss cannot egress. Capture and store still touch the tenant, though.</p>
    <p><b>Why not just use Copilot?</b> For this task Copilot is capable, but you cannot freeze its model (no reproducible artifact) and it carries the DLP/credit/licensing/agent-publish frictions. Go local when reproducibility and control matter more than M365-native convenience &mdash; not because a small model is smarter.</p>
    <p><b>Won&rsquo;t it go stale?</b> Like any KB &mdash; unless someone owns it. Assign a steward, add an effective-date/superseded field, set a monthly review, and keep the &ldquo;not a source of record&rdquo; disclaimer visible.</p>
    <p><b>What about the &ldquo;ships-Monday&rdquo; no-AI fallback?</b> Outlook + SharePoint + native search + a light template (no model at all) captures a surprising share of the value with zero validation burden. If that is enough, it is a fair reason to <em>defer</em> standing up and qualifying a local LLM &mdash; be honest that the model&rsquo;s marginal value must clear its own maintenance cost.</p>
  ` },
];

const css = `
:root{--slate:#33415C;--ink:#1A1E2E;--muted:#5A6478;--line:#DFE3EC;--panel:#F3F5F9;--green:#1F7A55;--teal:#0E7C86;--amber:#B7791F;--terra:#B5564B;--bg:#FBFCFE}
*{box-sizing:border-box}body{margin:0;font-family:-apple-system,Segoe UI,Calibri,Arial,sans-serif;color:var(--ink);background:var(--bg);line-height:1.55}
#wrap{display:flex;min-height:100vh}
#side{width:286px;flex:0 0 286px;background:#1C2333;color:#fff;position:sticky;top:0;height:100vh;overflow:auto;padding:22px 0}
#side .brand{padding:0 22px 14px;border-bottom:1px solid #313a50;margin-bottom:10px}
#side .brand b{font-family:Georgia,serif;font-size:16.5px;line-height:1.25;display:block}#side .brand span{display:block;color:#aab4cc;font-size:11px;margin-top:5px}
#side .brand .tag{display:inline-block;margin-top:9px;background:var(--green);color:#fff;font-size:10px;font-weight:800;letter-spacing:1px;padding:2px 8px;border-radius:20px}
#search{margin:0 16px 12px;width:calc(100% - 32px);padding:8px 10px;border-radius:8px;border:1px solid #3a4358;background:#252e42;color:#fff;font-size:13px}
#side a{display:block;color:#c8d0e2;text-decoration:none;padding:8px 22px;font-size:13.5px;border-left:3px solid transparent}
#side a:hover{background:#252e42}#side a.active{color:#fff;border-left-color:var(--green);background:#252e42;font-weight:600}
#main{flex:1;max-width:990px;margin:0 auto;padding:34px 50px 90px}
section{display:none}section.show{display:block;animation:f .2s}@keyframes f{from{opacity:.35}to{opacity:1}}
h1{font-family:Georgia,serif;color:var(--ink);font-size:29px;margin:0 0 14px;line-height:1.16}
h2{font-family:Georgia,serif;color:var(--slate);font-size:20px;margin:26px 0 10px;border-bottom:1px solid var(--line);padding-bottom:5px}
.lede{font-size:17px;color:#2f3550}
p,li{font-size:15px}ul,ol{padding-left:22px}li{margin:5px 0}
a{color:var(--teal)}
code{background:#eef1f6;color:#33415C;padding:1px 6px;border-radius:5px;font-family:Consolas,monospace;font-size:13px}
.muted{color:var(--muted);font-size:13px}
.callout{border-radius:10px;padding:13px 16px;margin:16px 0;font-size:14.5px}
.callout.rule{background:#fbeceb;border-left:4px solid var(--terra)}
.callout.honest{background:#fbf3e2;border-left:4px solid var(--amber)}.callout.honest b,.callout.honest strong{color:#8a5a12}
.callout.win{background:#e7f4ee;border-left:4px solid var(--green)}
.callout.hurdle{background:#f3f5f9;border-left:4px solid var(--slate)}
.callout.fair{background:#e7eff7;border-left:4px solid #2F5FB3}
.callout.tip{background:#e4f2f3;border-left:4px solid var(--teal)}
.callout.illus{background:#eef0f4;border-left:4px solid var(--muted);font-size:13.5px}
.dl{display:flex;gap:12px;margin:16px 0;flex-wrap:wrap}
.btn{display:inline-block;background:var(--slate);color:#fff;text-decoration:none;font-weight:700;font-size:14px;padding:11px 18px;border-radius:9px}
.btn.ghost{background:#fff;color:var(--slate);border:1.5px solid var(--slate)}.btn:hover{opacity:.92}
table{border-collapse:collapse;width:100%;margin:13px 0;font-size:14px}
table.cmp th,table.cmp td{border:1px solid var(--line);padding:9px 12px;text-align:left;vertical-align:top}
table.cmp th{background:#1C2333;color:#fff;font-weight:600}table.cmp tr:nth-child(even) td{background:var(--panel)}
table.cmp td:first-child{font-weight:700;color:var(--slate);white-space:nowrap}
.footer{margin-top:42px;padding-top:16px;border-top:1px solid var(--line);color:var(--muted);font-size:12px}
`;

const js = A.JS("start");
const nav = sections.map(s => `<a href="#${s.id}" data-t="${s.id}">${s.nav}</a>`).join("\n");
const body = sections.map(s => `<section id="${s.id}" aria-label="${String(s.nav).replace(/&[^;]+;/g, "").replace(/<[^>]+>/g, "").trim()}">${s.html}<div class="footer">Study Operations KB &mdash; Copilot-free local-SLM path &middot; the operational layer only; validated tools &amp; a human own every reported number &middot; a frozen on-prem model is reproducible, not magically reliable &middot; this is an honestly-labelled design, capability proven only by your own OQ validation.</div></section>`).join("\n");

const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Study Operations KB - the Copilot-free local-SLM path</title><style>${css}</style></head>
<body><div id="wrap">
<nav id="side"><div class="brand"><b>Study Ops KB &mdash;<br>Copilot-free</b><span>The same self-updating study-ops knowledge base, on a local frozen SLM &mdash; no M365 Copilot</span><span class="tag">FOR BIOSTATISTICIANS</span></div>
<input id="search" placeholder="Search the wiki..." autocomplete="off">
${nav}</nav>
<main id="main">${body}</main></div>
<script>${js}</script></body></html>`;

fs.writeFileSync(__dirname + "/Local_SLM_Operating_Wiki.html", A.accessibleShell(html));
console.log("WROTE Local_SLM_Operating_Wiki.html (" + sections.length + " sections)");
